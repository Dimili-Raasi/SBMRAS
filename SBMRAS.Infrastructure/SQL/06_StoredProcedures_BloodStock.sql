/*=====================================================================
  SBMRAS - 06_StoredProcedures_BloodStock.sql
  Blood stock matrix, single / multi update, re-confirm (contract §4.4, §6).
  Depends on helpers in 05 (usp_Inventory_AssertFacility, usp_Inventory_RecordBloodChange, usp_Change_GetRow).
=====================================================================*/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* GET facilities/{id}/blood-stock — full component × ABO × Rh matrix (missing cells with NULL InventoryId / Unknown). */
CREATE OR ALTER PROCEDURE dbo.usp_BloodStock_GetByFacility
    @ActorUserId INT,
    @FacilityId  INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'bloodstock.manage') = 0
        THROW 50403, N'You do not have permission to manage blood stock.', 1;
    EXEC dbo.usp_Inventory_AssertFacility @ActorUserId = @ActorUserId, @FacilityId = @FacilityId, @Kind = N'Blood';

    DECLARE @Low INT = dbo.fn_GetSettingInt(N'LOW_STOCK_THRESHOLD_UNITS', 5);
    DECLARE @DefaultUnit NVARCHAR(10) = (SELECT TOP (1) Code FROM dbo.Units WHERE Code = N'UNITS');

    ;WITH Matrix AS
    (
        SELECT bc.ComponentId, bc.Code AS ComponentCode, bc.Name AS ComponentName, g.AboGroup, g.AboOrder, r.RhFactor, r.RhOrder
        FROM dbo.BloodComponents bc
        CROSS JOIN (VALUES (N'A', 1), (N'B', 2), (N'AB', 3), (N'O', 4)) g(AboGroup, AboOrder)
        CROSS JOIN (VALUES (N'Positive', 1), (N'Negative', 2)) r(RhFactor, RhOrder)
        WHERE bc.IsActive = 1
           OR EXISTS (SELECT 1 FROM dbo.BloodInventory x WHERE x.FacilityId = @FacilityId AND x.ComponentId = bc.ComponentId)
    )
    SELECT bi.InventoryId, @FacilityId AS FacilityId, m.ComponentId, m.ComponentCode, m.ComponentName, m.AboGroup, m.RhFactor,
           m.AboGroup + CASE m.RhFactor WHEN N'Positive' THEN N'+' ELSE N'-' END AS BloodGroup,
           bi.Quantity, ISNULL(un.Code, @DefaultUnit) AS UnitCode, bi.EarliestExpiryDate,
           CASE WHEN bi.InventoryId IS NULL OR bi.LastUpdatedAt IS NULL THEN N'Unknown'
                WHEN bi.Quantity = 0 THEN N'OutOfStock'
                WHEN bi.Quantity < @Low THEN N'Low'
                ELSE N'Available' END AS AvailabilityStatus,
           CASE WHEN bi.InventoryId IS NULL THEN N'Unknown'
                ELSE dbo.fn_FreshnessStatus(bi.LastUpdatedAt, bi.ValidUntil, bi.VerificationStatus) END AS FreshnessStatus,
           bi.VerificationStatus, bi.SourceType, bi.LastUpdatedAt, lu.DisplayName AS LastUpdatedByName, bi.ValidUntil,
           CAST(bi.RowVer AS VARBINARY(8)) AS RowVersion,
           pc.ChangeId AS PendingChangeId
    FROM Matrix m
    LEFT JOIN dbo.BloodInventory bi ON bi.FacilityId = @FacilityId AND bi.ComponentId = m.ComponentId
                                   AND bi.AboGroup = m.AboGroup AND bi.RhFactor = m.RhFactor
    LEFT JOIN dbo.Units un ON un.UnitId = bi.UnitId
    LEFT JOIN dbo.Users lu ON lu.UserId = bi.LastUpdatedBy
    OUTER APPLY (SELECT TOP (1) ic.ChangeId FROM dbo.InventoryChanges ic
                 WHERE ic.FacilityId = @FacilityId AND ic.InventoryKind = N'Blood' AND ic.ComponentId = m.ComponentId
                   AND ic.AboGroup = m.AboGroup AND ic.RhFactor = m.RhFactor AND ic.Status = N'PendingReview'
                 ORDER BY ic.ChangeId DESC) pc
    ORDER BY m.ComponentId, m.AboOrder, m.RhOrder;
END
GO

/* POST facilities/{id}/blood-stock/updates — returns InventoryChange (existing change when duplicate). */
CREATE OR ALTER PROCEDURE dbo.usp_BloodStock_SubmitUpdate
    @ActorUserId        INT,
    @FacilityId         INT,
    @ComponentId        INT,
    @AboGroup           NVARCHAR(2),
    @RhFactor           NVARCHAR(10),
    @Quantity           DECIMAL(12,2),
    @EarliestExpiryDate DATE = NULL,
    @ValidUntil         DATETIME2(0) = NULL,
    @Reason             NVARCHAR(500) = NULL,
    @RowVersion         VARBINARY(8) = NULL,
    @CorrelationId      NVARCHAR(64) = NULL,
    @IdempotencyKey     NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'bloodstock.manage') = 0
        THROW 50403, N'You do not have permission to manage blood stock.', 1;

    DECLARE @ChangeId INT, @IsDuplicate BIT, @ResultStatus NVARCHAR(20);
    EXEC dbo.usp_Inventory_RecordBloodChange @ActorUserId = @ActorUserId, @FacilityId = @FacilityId, @ComponentId = @ComponentId,
         @AboGroup = @AboGroup, @RhFactor = @RhFactor, @Quantity = @Quantity, @EarliestExpiryDate = @EarliestExpiryDate,
         @ValidUntil = @ValidUntil, @Reason = @Reason, @SourceType = N'ManualPortal', @RowVersion = @RowVersion,
         @IdempotencyKey = @IdempotencyKey, @CorrelationId = @CorrelationId,
         @ChangeId = @ChangeId OUTPUT, @IsDuplicate = @IsDuplicate OUTPUT, @ResultStatus = @ResultStatus OUTPUT;

    EXEC dbo.usp_Change_GetRow @ActorUserId = @ActorUserId, @ChangeId = @ChangeId;
END
GO

/*
  Multi-cell update in one transaction (all-or-nothing).
  @UpdatesJson = [{ "componentId":1, "aboGroup":"O", "rhFactor":"Positive", "quantity":12, "earliestExpiryDate":"2026-11-20",
                    "validUntil":"2026-11-16T06:00:00Z", "reason":"...", "rowVersion":"<base64>" }, ...] (max 48).
  Returns InventoryChange rows (one per item, existing change for duplicates).
*/
CREATE OR ALTER PROCEDURE dbo.usp_BloodStock_SubmitBatch
    @ActorUserId   INT,
    @FacilityId    INT,
    @UpdatesJson   NVARCHAR(MAX),
    @Reason        NVARCHAR(500) = NULL,
    @CorrelationId NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'bloodstock.manage') = 0
        THROW 50403, N'You do not have permission to manage blood stock.', 1;
    IF @UpdatesJson IS NULL OR ISJSON(@UpdatesJson) = 0
        THROW 50400, N'Updates must be a JSON array.', 1;

    DECLARE @Items TABLE (Seq INT IDENTITY(1,1) PRIMARY KEY, ComponentId INT, AboGroup NVARCHAR(2), RhFactor NVARCHAR(10),
                          Quantity DECIMAL(12,2), EarliestExpiryDate DATE, ValidUntil DATETIME2(0), Reason NVARCHAR(500), RowVersion VARBINARY(8));
    INSERT INTO @Items (ComponentId, AboGroup, RhFactor, Quantity, EarliestExpiryDate, ValidUntil, Reason, RowVersion)
    SELECT j.ComponentId, j.AboGroup, j.RhFactor, j.Quantity, TRY_CONVERT(DATE, j.EarliestExpiryDate),
           CAST(TRY_CONVERT(DATETIMEOFFSET, j.ValidUntil) AT TIME ZONE 'UTC' AS DATETIME2(0)),
           COALESCE(NULLIF(LTRIM(RTRIM(j.Reason)), N''), @Reason),
           CASE WHEN NULLIF(j.RowVersion, N'') IS NULL THEN NULL
                ELSE CAST(N'' AS XML).value('xs:base64Binary(sql:column("j.RowVersion"))', 'VARBINARY(8)') END
    FROM OPENJSON(@UpdatesJson)
         WITH (ComponentId INT '$.componentId', AboGroup NVARCHAR(2) '$.aboGroup', RhFactor NVARCHAR(10) '$.rhFactor',
               Quantity DECIMAL(12,2) '$.quantity', EarliestExpiryDate NVARCHAR(40) '$.earliestExpiryDate',
               ValidUntil NVARCHAR(40) '$.validUntil', Reason NVARCHAR(500) '$.reason', RowVersion NVARCHAR(20) '$.rowVersion') j;

    DECLARE @Count INT = (SELECT COUNT(*) FROM @Items);
    IF @Count = 0 THROW 50400, N'At least one update is required.', 1;
    IF @Count > 48 THROW 50400, N'At most 48 updates can be submitted at once.', 1;
    IF EXISTS (SELECT 1 FROM @Items GROUP BY ComponentId, AboGroup, RhFactor HAVING COUNT(*) > 1)
        THROW 50400, N'Each component / blood group may appear only once per submission.', 1;

    DECLARE @Changes TABLE (Seq INT PRIMARY KEY, ChangeId INT);
    DECLARE @Seq INT = 1, @C INT, @A NVARCHAR(2), @R NVARCHAR(10), @Q DECIMAL(12,2), @E DATE, @V DATETIME2(0), @Rs NVARCHAR(500),
            @Rv VARBINARY(8), @ChangeId INT, @IsDuplicate BIT, @ResultStatus NVARCHAR(20);

    BEGIN TRANSACTION;
    BEGIN TRY
        WHILE @Seq <= @Count
        BEGIN
            SELECT @C = ComponentId, @A = AboGroup, @R = RhFactor, @Q = Quantity, @E = EarliestExpiryDate, @V = ValidUntil,
                   @Rs = Reason, @Rv = RowVersion
            FROM @Items WHERE Seq = @Seq;

            EXEC dbo.usp_Inventory_RecordBloodChange @ActorUserId = @ActorUserId, @FacilityId = @FacilityId, @ComponentId = @C,
                 @AboGroup = @A, @RhFactor = @R, @Quantity = @Q, @EarliestExpiryDate = @E, @ValidUntil = @V, @Reason = @Rs,
                 @SourceType = N'ManualPortal', @RowVersion = @Rv, @CorrelationId = @CorrelationId,
                 @ChangeId = @ChangeId OUTPUT, @IsDuplicate = @IsDuplicate OUTPUT, @ResultStatus = @ResultStatus OUTPUT;

            INSERT INTO @Changes (Seq, ChangeId) VALUES (@Seq, @ChangeId);
            SET @Seq += 1;
        END
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT v.ChangeId, v.ChangeNo, v.FacilityId, v.FacilityName, v.FacilityCode, v.InventoryKind, v.InventoryId, v.ItemLabel,
           v.ComponentId, v.ComponentCode, v.AboGroup, v.RhFactor, v.ResourceTypeId, v.ResourceTypeCode,
           v.PreviousQuantity, v.ProposedQuantity, v.PreviousAvailable, v.ProposedAvailable, v.ProposedTotal, v.ProposedStatus,
           v.EarliestExpiryDate, v.ValidUntil, v.SourceType, v.Reason, v.AnomalyFlags, v.Status, v.ImportBatchId,
           v.SubmittedBy, v.SubmittedByName, v.SubmittedAt, v.DecidedBy, v.DecidedByName, v.DecidedAt, v.DecisionReason,
           dbo.fn_CanDecideChange(@ActorUserId, v.FacilityId, v.SubmittedBy, v.Status) AS CanDecide
    FROM @Changes c
    INNER JOIN dbo.vw_InventoryChanges v ON v.ChangeId = c.ChangeId
    ORDER BY c.Seq;
END
GO

/*
  POST facilities/{id}/blood-stock/confirm — re-confirms unchanged values (new LastUpdatedAt/ValidUntil, Confirmed,
  snapshot, audit; resolves open STALE issues). @InventoryIds = CSV. Rows under review / never reported are skipped.
  Returns the confirmed rows in the blood stock matrix shape.
*/
CREATE OR ALTER PROCEDURE dbo.usp_BloodStock_ConfirmCurrent
    @ActorUserId   INT,
    @FacilityId    INT,
    @InventoryIds  NVARCHAR(MAX),
    @CorrelationId NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'bloodstock.manage') = 0
        THROW 50403, N'You do not have permission to manage blood stock.', 1;
    EXEC dbo.usp_Inventory_AssertFacility @ActorUserId = @ActorUserId, @FacilityId = @FacilityId, @Kind = N'Blood', @RequireWritable = 1;

    DECLARE @Ids TABLE (Id INT PRIMARY KEY);
    INSERT INTO @Ids (Id)
    SELECT DISTINCT TRY_CONVERT(INT, LTRIM(RTRIM(s.value))) FROM STRING_SPLIT(ISNULL(@InventoryIds, N''), N',') s
    WHERE TRY_CONVERT(INT, LTRIM(RTRIM(s.value))) IS NOT NULL;
    IF NOT EXISTS (SELECT 1 FROM @Ids)
        THROW 50400, N'Select at least one stock record to confirm.', 1;
    IF (SELECT COUNT(*) FROM @Ids) > 500
        THROW 50400, N'At most 500 records can be confirmed at once.', 1;
    IF EXISTS (SELECT 1 FROM @Ids i WHERE NOT EXISTS (SELECT 1 FROM dbo.BloodInventory b WHERE b.InventoryId = i.Id AND b.FacilityId = @FacilityId))
        THROW 50404, N'One or more stock records were not found for this facility.', 1;

    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME(), @VU DATETIME2(0) = dbo.fn_InventoryDefaultValidUntil(N'Blood');
    DECLARE @Done TABLE (Id INT PRIMARY KEY);

    BEGIN TRANSACTION;
    BEGIN TRY
        UPDATE b
        SET LastUpdatedAt = @Now, LastUpdatedBy = @ActorUserId, ValidUntil = @VU, VerificationStatus = N'Confirmed',
            UpdatedAt = @Now, UpdatedBy = @ActorUserId
        OUTPUT inserted.InventoryId INTO @Done (Id)
        FROM dbo.BloodInventory b
        INNER JOIN @Ids i ON i.Id = b.InventoryId
        WHERE b.FacilityId = @FacilityId AND b.VerificationStatus <> N'PendingReview' AND b.LastUpdatedAt IS NOT NULL;

        INSERT INTO dbo.AvailabilitySnapshots (FacilityId, InventoryKind, InventoryId, ComponentId, AboGroup, RhFactor, Quantity,
            SourceType, VerificationStatus, RecordedAt, ValidUntil, ChangeId, RecordedBy)
        SELECT b.FacilityId, N'Blood', b.InventoryId, b.ComponentId, b.AboGroup, b.RhFactor, b.Quantity,
            b.SourceType, N'Confirmed', @Now, @VU, NULL, @ActorUserId
        FROM dbo.BloodInventory b INNER JOIN @Done d ON d.Id = b.InventoryId;

        UPDATE vi SET Status = N'Resolved', ResolvedBy = @ActorUserId, ResolvedAt = @Now, Resolution = N'Stock re-confirmed as current.'
        FROM dbo.ValidationIssues vi INNER JOIN @Done d ON d.Id = vi.EntityId
        WHERE vi.EntityType = N'BloodInventory' AND vi.Status = N'Open' AND vi.IssueCode = N'STALE';

        DECLARE @Cnt INT = (SELECT COUNT(*) FROM @Done);
        DECLARE @FIdText NVARCHAR(50) = CAST(@FacilityId AS NVARCHAR(50));
        DECLARE @NewVals NVARCHAR(MAX) = (SELECT d.Id AS InventoryId, @VU AS ValidUntil FROM @Done d FOR JSON PATH);
        DECLARE @Desc NVARCHAR(1000) = CONCAT(N'Re-confirmed ', @Cnt, N' blood stock record(s) as current.');
        EXEC dbo.usp_Audit_Write @ActorUserId = @ActorUserId, @EntityType = N'Facility', @EntityId = @FIdText,
             @FacilityId = @FacilityId, @Action = N'BloodStockConfirmed', @Description = @Desc, @NewValues = @NewVals,
             @SourceType = N'ManualPortal', @CorrelationId = @CorrelationId;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    DECLARE @Low INT = dbo.fn_GetSettingInt(N'LOW_STOCK_THRESHOLD_UNITS', 5);
    SELECT b.InventoryId, b.FacilityId, b.ComponentId, bc.Code AS ComponentCode, bc.Name AS ComponentName, b.AboGroup, b.RhFactor,
           b.AboGroup + CASE b.RhFactor WHEN N'Positive' THEN N'+' ELSE N'-' END AS BloodGroup,
           b.Quantity, un.Code AS UnitCode, b.EarliestExpiryDate,
           CASE WHEN b.Quantity = 0 THEN N'OutOfStock' WHEN b.Quantity < @Low THEN N'Low' ELSE N'Available' END AS AvailabilityStatus,
           dbo.fn_FreshnessStatus(b.LastUpdatedAt, b.ValidUntil, b.VerificationStatus) AS FreshnessStatus,
           b.VerificationStatus, b.SourceType, b.LastUpdatedAt, lu.DisplayName AS LastUpdatedByName, b.ValidUntil,
           CAST(b.RowVer AS VARBINARY(8)) AS RowVersion
    FROM dbo.BloodInventory b
    INNER JOIN @Done d ON d.Id = b.InventoryId
    INNER JOIN dbo.BloodComponents bc ON bc.ComponentId = b.ComponentId
    INNER JOIN dbo.Units un ON un.UnitId = b.UnitId
    LEFT JOIN dbo.Users lu ON lu.UserId = b.LastUpdatedBy
    ORDER BY b.ComponentId, b.AboGroup, b.RhFactor;
END
GO
