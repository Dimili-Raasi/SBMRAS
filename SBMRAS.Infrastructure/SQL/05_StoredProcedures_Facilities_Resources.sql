/*=====================================================================
  SBMRAS - 05_StoredProcedures_Facilities_Resources.sql
  Shared inventory helpers (also used by 06 blood stock, 07 verification
  and 08 imports), facility SPs and medical resource inventory SPs.
  Idempotent (CREATE OR ALTER). Contract §4.4 / §6.

  Shared helpers (no permission check; callers check permissions):
    fn_IsLargeJump(@Old, @New)                  -> BIT  (LARGE_JUMP rule)
    fn_InventoryRequireReview()                 -> BIT  (REQUIRE_REVIEW_FOR_ANOMALY)
    fn_InventoryDefaultValidUntil(@Kind)        -> DATETIME2 (now + TTL)
    fn_CanDecideChange(@UserId,@FacilityId,@SubmittedBy,@Status) -> BIT
    vw_InventoryChanges                         (InventoryChange shape minus CanDecide)
    vw_Facilities                               (Facility shape)
    usp_Inventory_AssertFacility                (exists / scope / type / writable)
    usp_Inventory_ApplyChange                   (applies a recorded change to inventory + snapshot + audit)
    usp_Inventory_RecordBloodChange             (validate, dedupe, anomaly, record, apply or queue)
    usp_Inventory_RecordResourceChange          (same for medical resources)
    usp_Change_GetRow                           (InventoryChange row incl. CanDecide)
=====================================================================*/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* LARGE_JUMP: |new-old| >= max(LARGE_JUMP_MIN_UNITS, old * LARGE_JUMP_PERCENT%). No baseline -> 0. */
CREATE OR ALTER FUNCTION dbo.fn_IsLargeJump (@Old DECIMAL(12,2), @New DECIMAL(12,2))
RETURNS BIT
AS
BEGIN
    IF @Old IS NULL OR @New IS NULL RETURN CAST(0 AS BIT);
    DECLARE @Pct DECIMAL(18,4) = dbo.fn_GetSettingInt(N'LARGE_JUMP_PERCENT', 50);
    DECLARE @Min DECIMAL(18,4) = dbo.fn_GetSettingInt(N'LARGE_JUMP_MIN_UNITS', 20);
    DECLARE @Threshold DECIMAL(18,4) = CASE WHEN @Old * @Pct / 100.0 > @Min THEN @Old * @Pct / 100.0 ELSE @Min END;
    RETURN CASE WHEN ABS(@New - @Old) >= @Threshold THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END;
END
GO

CREATE OR ALTER FUNCTION dbo.fn_InventoryRequireReview ()
RETURNS BIT
AS
BEGIN
    DECLARE @V NVARCHAR(400) = (SELECT LOWER(LTRIM(RTRIM(SettingValue))) FROM dbo.SystemSettings WHERE SettingKey = N'REQUIRE_REVIEW_FOR_ANOMALY');
    RETURN CASE WHEN @V IS NULL OR @V IN (N'true', N'1', N'yes') THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END;
END
GO

/* Default ValidUntil = now + BLOOD_STOCK_TTL_MINUTES (Blood) / RESOURCE_TTL_MINUTES (Resource). */
CREATE OR ALTER FUNCTION dbo.fn_InventoryDefaultValidUntil (@Kind NVARCHAR(10))
RETURNS DATETIME2(0)
AS
BEGIN
    RETURN DATEADD(MINUTE,
        CASE WHEN @Kind = N'Blood' THEN dbo.fn_GetSettingInt(N'BLOOD_STOCK_TTL_MINUTES', 360)
             ELSE dbo.fn_GetSettingInt(N'RESOURCE_TTL_MINUTES', 240) END,
        CAST(SYSUTCDATETIME() AS DATETIME2(0)));
END
GO

/* inventory.verify + facility scope + pending + (decider <> submitter unless Admin). */
CREATE OR ALTER FUNCTION dbo.fn_CanDecideChange (@UserId INT, @FacilityId INT, @SubmittedBy INT, @Status NVARCHAR(20))
RETURNS BIT
AS
BEGIN
    IF @Status <> N'PendingReview' OR @UserId IS NULL RETURN CAST(0 AS BIT);
    IF dbo.fn_UserHasPermission(@UserId, N'inventory.verify') = 0 RETURN CAST(0 AS BIT);
    IF dbo.fn_UserCanAccessFacility(@UserId, @FacilityId) = 0 RETURN CAST(0 AS BIT);
    IF @SubmittedBy = @UserId AND dbo.fn_UserIsAdmin(@UserId) = 0 RETURN CAST(0 AS BIT);
    RETURN CAST(1 AS BIT);
END
GO

CREATE OR ALTER VIEW dbo.vw_InventoryChanges
AS
SELECT ic.ChangeId, ic.ChangeNo, ic.FacilityId, f.Name AS FacilityName, f.FacilityCode, f.FacilityType,
       ic.InventoryKind, ic.InventoryId,
       ic.ComponentId, bc.Code AS ComponentCode, ic.AboGroup, ic.RhFactor,
       ic.ResourceTypeId, rt.Code AS ResourceTypeCode,
       CASE WHEN ic.InventoryKind = N'Blood'
            THEN ISNULL(bc.Code, N'?') + N' ' + ISNULL(ic.AboGroup, N'') + CASE ic.RhFactor WHEN N'Positive' THEN N'+' WHEN N'Negative' THEN N'-' ELSE N'' END
            ELSE rt.Name END AS ItemLabel,
       ic.PreviousQuantity, ic.ProposedQuantity, ic.PreviousAvailable, ic.ProposedAvailable, ic.ProposedTotal,
       ic.ProposedStatus, ic.EarliestExpiryDate, ic.ValidUntil, ic.SourceType, ic.Reason, ic.AnomalyFlags, ic.Status,
       ic.ImportBatchId, ic.SubmittedBy, su.DisplayName AS SubmittedByName, ic.SubmittedAt,
       ic.DecidedBy, du.DisplayName AS DecidedByName, ic.DecidedAt, ic.DecisionReason
FROM dbo.InventoryChanges ic
INNER JOIN dbo.Facilities f           ON f.FacilityId = ic.FacilityId
LEFT JOIN dbo.BloodComponents bc      ON bc.ComponentId = ic.ComponentId
LEFT JOIN dbo.MedicalResourceTypes rt ON rt.ResourceTypeId = ic.ResourceTypeId
LEFT JOIN dbo.Users su                ON su.UserId = ic.SubmittedBy
LEFT JOIN dbo.Users du                ON du.UserId = ic.DecidedBy;
GO

CREATE OR ALTER VIEW dbo.vw_Facilities
AS
SELECT f.FacilityId, f.FacilityCode, f.Name, f.FacilityType, f.LicenseNo, f.AddressLine,
       f.AreaId, a.Name AS AreaName, f.City, f.Pincode, f.Latitude, f.Longitude,
       f.ContactPhone, f.ContactEmail, f.Is24x7, f.VerificationStatus, f.VerifiedAt, f.VerificationNotes, f.IsActive,
       q.QualityScore, q.FreshPercent, q.StaleRecords, q.LastUpdateAt,
       f.RowVer AS RowVersion, f.CreatedAt
FROM dbo.Facilities f
INNER JOIN dbo.Areas a ON a.AreaId = f.AreaId
LEFT JOIN dbo.vw_FacilityQualityScore q ON q.FacilityId = f.FacilityId;
GO

/*
  Facility guard. @Kind: 'Blood' (BloodBank only) | 'Resource' (Hospital only) | NULL (any).
  @RequireWritable = 1 -> facility must be active and Verified or Pending.
*/
CREATE OR ALTER PROCEDURE dbo.usp_Inventory_AssertFacility
    @ActorUserId     INT,
    @FacilityId      INT,
    @Kind            NVARCHAR(10) = NULL,
    @RequireWritable BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Type NVARCHAR(20), @Status NVARCHAR(20), @IsActive BIT;
    SELECT @Type = FacilityType, @Status = VerificationStatus, @IsActive = IsActive
    FROM dbo.Facilities WHERE FacilityId = @FacilityId;

    IF @Type IS NULL
        THROW 50404, N'Facility not found.', 1;
    IF dbo.fn_UserCanAccessFacility(@ActorUserId, @FacilityId) = 0
        THROW 50403, N'You are not assigned to this facility.', 1;
    IF @Kind = N'Blood' AND @Type <> N'BloodBank'
        THROW 50403, N'Blood stock can only be managed for blood bank facilities.', 1;
    IF @Kind = N'Resource' AND @Type <> N'Hospital'
        THROW 50403, N'Medical resources can only be managed for hospital facilities.', 1;
    IF ISNULL(@RequireWritable, 0) = 1 AND (@IsActive = 0 OR @Status NOT IN (N'Verified', N'Pending'))
        THROW 50409, N'Inventory cannot be updated for an inactive, rejected or suspended facility.', 1;
END
GO

/*
  Applies the proposed values of an InventoryChange to BloodInventory / MedicalResourceInventory
  (insert when missing), marks the change Applied, writes snapshot + audit.
  When the change was PendingReview the validity window is re-based on now (same duration, ≤ 7 days).
  Does NOT set DecidedBy/DecidedAt (caller does for approvals).
*/
CREATE OR ALTER PROCEDURE dbo.usp_Inventory_ApplyChange
    @ActorUserId   INT,
    @ChangeId      INT,
    @CorrelationId NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @FacilityId INT, @Kind NVARCHAR(10), @InventoryId INT, @ComponentId INT, @AboGroup NVARCHAR(2), @RhFactor NVARCHAR(10),
            @ResourceTypeId INT, @ProposedQuantity DECIMAL(12,2), @ProposedAvailable DECIMAL(12,2), @ProposedTotal DECIMAL(12,2),
            @ProposedStatus NVARCHAR(20), @Expiry DATE, @ValidUntil DATETIME2(0), @SourceType NVARCHAR(20), @Reason NVARCHAR(500),
            @Status NVARCHAR(20), @SubmittedBy INT, @SubmittedAt DATETIME2(0), @ChangeNo NVARCHAR(20), @Notes NVARCHAR(500);

    SELECT @FacilityId = FacilityId, @Kind = InventoryKind, @InventoryId = InventoryId, @ComponentId = ComponentId,
           @AboGroup = AboGroup, @RhFactor = RhFactor, @ResourceTypeId = ResourceTypeId,
           @ProposedQuantity = ProposedQuantity, @ProposedAvailable = ProposedAvailable, @ProposedTotal = ProposedTotal,
           @ProposedStatus = ProposedStatus, @Expiry = EarliestExpiryDate, @ValidUntil = ValidUntil,
           @SourceType = SourceType, @Reason = Reason, @Status = Status, @SubmittedBy = SubmittedBy,
           @SubmittedAt = SubmittedAt, @ChangeNo = ChangeNo,
           @Notes = JSON_VALUE(AfterJson, '$.Notes')
    FROM dbo.InventoryChanges WITH (UPDLOCK, HOLDLOCK)
    WHERE ChangeId = @ChangeId;

    IF @FacilityId IS NULL
        THROW 50404, N'Inventory change not found.', 1;
    IF @Status = N'Rejected'
        THROW 50409, N'A rejected change cannot be applied.', 1;

    IF @Status = N'PendingReview' OR @ValidUntil IS NULL OR @ValidUntil <= @Now
    BEGIN
        DECLARE @Seconds BIGINT = CASE WHEN @ValidUntil IS NOT NULL AND @SubmittedAt IS NOT NULL
                                       THEN DATEDIFF_BIG(SECOND, @SubmittedAt, @ValidUntil) ELSE 0 END;
        IF @Seconds <= 0 SET @ValidUntil = dbo.fn_InventoryDefaultValidUntil(@Kind);
        ELSE
        BEGIN
            IF @Seconds > 7 * 86400 SET @Seconds = 7 * 86400;
            SET @ValidUntil = DATEADD(SECOND, CAST(@Seconds AS INT), @Now);
        END
    END

    DECLARE @Before NVARCHAR(MAX), @After NVARCHAR(MAX);

    BEGIN TRY
        DECLARE @TranStarted BIT = 0;
        IF @@TRANCOUNT = 0 BEGIN BEGIN TRANSACTION; SET @TranStarted = 1; END

        IF @Kind = N'Blood'
        BEGIN
            SELECT @InventoryId = InventoryId
            FROM dbo.BloodInventory WITH (UPDLOCK, HOLDLOCK)
            WHERE FacilityId = @FacilityId AND ComponentId = @ComponentId AND AboGroup = @AboGroup AND RhFactor = @RhFactor;

            SET @Before = (SELECT Quantity, EarliestExpiryDate, SourceType, VerificationStatus, LastUpdatedAt, ValidUntil
                           FROM dbo.BloodInventory WHERE InventoryId = @InventoryId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

            IF @InventoryId IS NULL
            BEGIN
                INSERT INTO dbo.BloodInventory (FacilityId, ComponentId, AboGroup, RhFactor, Quantity, UnitId, EarliestExpiryDate,
                    SourceType, VerificationStatus, LastUpdatedAt, LastUpdatedBy, ValidUntil, CreatedAt, CreatedBy)
                VALUES (@FacilityId, @ComponentId, @AboGroup, @RhFactor, @ProposedQuantity,
                    ISNULL((SELECT TOP (1) UnitId FROM dbo.Units WHERE Code = N'UNITS'), (SELECT MIN(UnitId) FROM dbo.Units)),
                    @Expiry, @SourceType, N'Confirmed', @Now, @SubmittedBy, @ValidUntil, @Now, @ActorUserId);
                SET @InventoryId = SCOPE_IDENTITY();
            END
            ELSE
                UPDATE dbo.BloodInventory
                SET Quantity = @ProposedQuantity, EarliestExpiryDate = @Expiry, SourceType = @SourceType,
                    VerificationStatus = N'Confirmed', LastUpdatedAt = @Now, LastUpdatedBy = @SubmittedBy,
                    ValidUntil = @ValidUntil, UpdatedAt = @Now, UpdatedBy = @ActorUserId
                WHERE InventoryId = @InventoryId;

            SET @After = (SELECT Quantity, EarliestExpiryDate, SourceType, VerificationStatus, LastUpdatedAt, ValidUntil
                          FROM dbo.BloodInventory WHERE InventoryId = @InventoryId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

            INSERT INTO dbo.AvailabilitySnapshots (FacilityId, InventoryKind, InventoryId, ComponentId, AboGroup, RhFactor,
                Quantity, SourceType, VerificationStatus, RecordedAt, ValidUntil, ChangeId, RecordedBy)
            VALUES (@FacilityId, N'Blood', @InventoryId, @ComponentId, @AboGroup, @RhFactor,
                @ProposedQuantity, @SourceType, N'Confirmed', @Now, @ValidUntil, @ChangeId, @ActorUserId);
        END
        ELSE
        BEGIN
            SELECT @InventoryId = ResourceInventoryId
            FROM dbo.MedicalResourceInventory WITH (UPDLOCK, HOLDLOCK)
            WHERE FacilityId = @FacilityId AND ResourceTypeId = @ResourceTypeId;

            SET @Before = (SELECT TotalQuantity, AvailableQuantity, OperationalStatus, Notes, SourceType, VerificationStatus, LastUpdatedAt, ValidUntil
                           FROM dbo.MedicalResourceInventory WHERE ResourceInventoryId = @InventoryId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

            IF @InventoryId IS NULL
            BEGIN
                INSERT INTO dbo.MedicalResourceInventory (FacilityId, ResourceTypeId, TotalQuantity, AvailableQuantity, UnitId,
                    OperationalStatus, Notes, SourceType, VerificationStatus, LastUpdatedAt, LastUpdatedBy, ValidUntil, CreatedAt, CreatedBy)
                SELECT @FacilityId, @ResourceTypeId, @ProposedTotal, @ProposedAvailable, rt.DefaultUnitId,
                    @ProposedStatus, @Notes, @SourceType, N'Confirmed', @Now, @SubmittedBy, @ValidUntil, @Now, @ActorUserId
                FROM dbo.MedicalResourceTypes rt WHERE rt.ResourceTypeId = @ResourceTypeId;
                SET @InventoryId = SCOPE_IDENTITY();
            END
            ELSE
                UPDATE dbo.MedicalResourceInventory
                SET TotalQuantity = @ProposedTotal, AvailableQuantity = @ProposedAvailable, OperationalStatus = @ProposedStatus,
                    Notes = COALESCE(@Notes, Notes), SourceType = @SourceType, VerificationStatus = N'Confirmed',
                    LastUpdatedAt = @Now, LastUpdatedBy = @SubmittedBy, ValidUntil = @ValidUntil, UpdatedAt = @Now, UpdatedBy = @ActorUserId
                WHERE ResourceInventoryId = @InventoryId;

            SET @After = (SELECT TotalQuantity, AvailableQuantity, OperationalStatus, Notes, SourceType, VerificationStatus, LastUpdatedAt, ValidUntil
                          FROM dbo.MedicalResourceInventory WHERE ResourceInventoryId = @InventoryId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

            INSERT INTO dbo.AvailabilitySnapshots (FacilityId, InventoryKind, InventoryId, ResourceTypeId,
                AvailableQuantity, TotalQuantity, OperationalStatus, SourceType, VerificationStatus, RecordedAt, ValidUntil, ChangeId, RecordedBy)
            VALUES (@FacilityId, N'Resource', @InventoryId, @ResourceTypeId,
                @ProposedAvailable, @ProposedTotal, @ProposedStatus, @SourceType, N'Confirmed', @Now, @ValidUntil, @ChangeId, @ActorUserId);
        END

        UPDATE dbo.InventoryChanges
        SET Status = N'Applied', InventoryId = @InventoryId, ValidUntil = @ValidUntil,
            BeforeJson = COALESCE(BeforeJson, @Before), AfterJson = @After
        WHERE ChangeId = @ChangeId;

        -- Stale/missing issues for this record are no longer valid after a fresh update.
        UPDATE dbo.ValidationIssues
        SET Status = N'Resolved', ResolvedBy = @ActorUserId, ResolvedAt = @Now,
            Resolution = N'Resolved by inventory update ' + @ChangeNo + N'.'
        WHERE Status = N'Open' AND IssueCode IN (N'STALE', N'MISSING_FIELD')
          AND EntityType = CASE @Kind WHEN N'Blood' THEN N'BloodInventory' ELSE N'ResourceInventory' END
          AND EntityId = @InventoryId;

        DECLARE @EntityType NVARCHAR(50) = CASE @Kind WHEN N'Blood' THEN N'BloodInventory' ELSE N'ResourceInventory' END;
        DECLARE @EntityIdText NVARCHAR(50) = CAST(@InventoryId AS NVARCHAR(50));
        DECLARE @Desc NVARCHAR(1000) = N'Inventory updated via ' + @ChangeNo + N'.';
        EXEC dbo.usp_Audit_Write @ActorUserId = @ActorUserId, @EntityType = @EntityType, @EntityId = @EntityIdText,
             @ReferenceNo = @ChangeNo, @FacilityId = @FacilityId, @Action = N'InventoryUpdated', @Description = @Desc,
             @OldValues = @Before, @NewValues = @After, @SourceType = @SourceType, @Reason = @Reason, @CorrelationId = @CorrelationId;

        IF @TranStarted = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @TranStarted = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/*
  Shared blood change recorder (manual portal, multi-update and CSV import).
  Validates facility (exists/scope/BloodBank/writable) and values, enforces optimistic concurrency
  (an existing row requires a matching @RowVersion), de-duplicates (same IdempotencyKey, or identical submission by the same
  user within 2 minutes -> returns the existing change, @IsDuplicate = 1), detects LARGE_JUMP and either
  applies the change or queues it for review (issue + notifications). @ForceReview = 1 always queues.
  Outputs @ChangeId / @IsDuplicate / @ResultStatus. Does not return result sets.
*/
CREATE OR ALTER PROCEDURE dbo.usp_Inventory_RecordBloodChange
    @ActorUserId           INT,
    @FacilityId            INT,
    @ComponentId           INT,
    @AboGroup              NVARCHAR(2),
    @RhFactor              NVARCHAR(10),
    @Quantity              DECIMAL(12,2),
    @EarliestExpiryDate    DATE = NULL,
    @ValidUntil            DATETIME2(0) = NULL,
    @Reason                NVARCHAR(500) = NULL,
    @SourceType            NVARCHAR(20) = N'ManualPortal',
    @RowVersion            VARBINARY(8) = NULL,
    @ImportBatchId         INT = NULL,
    @IdempotencyKey        NVARCHAR(100) = NULL,
    @ForceReview           BIT = 0,
    @SkipDuplicateCheck    BIT = 0,
    @SuppressNotifications BIT = 0,
    @CorrelationId         NVARCHAR(64) = NULL,
    @ChangeId              INT = NULL OUTPUT,
    @IsDuplicate           BIT = 0 OUTPUT,
    @ResultStatus          NVARCHAR(20) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
    SET @ChangeId = NULL; SET @IsDuplicate = 0; SET @ResultStatus = NULL;
    SET @AboGroup = UPPER(LTRIM(RTRIM(@AboGroup)));
    SET @RhFactor = LTRIM(RTRIM(@RhFactor));
    SET @Reason = NULLIF(LTRIM(RTRIM(@Reason)), N'');
    SET @SourceType = ISNULL(NULLIF(LTRIM(RTRIM(@SourceType)), N''), N'ManualPortal');
    SET @IdempotencyKey = NULLIF(LTRIM(RTRIM(@IdempotencyKey)), N'');

    EXEC dbo.usp_Inventory_AssertFacility @ActorUserId = @ActorUserId, @FacilityId = @FacilityId, @Kind = N'Blood', @RequireWritable = 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.BloodComponents WHERE ComponentId = @ComponentId AND IsActive = 1)
        THROW 50400, N'Unknown or inactive blood component.', 1;
    IF @AboGroup IS NULL OR @AboGroup NOT IN (N'A', N'B', N'AB', N'O')
        THROW 50400, N'ABO group must be A, B, AB or O.', 1;
    IF @RhFactor IS NULL OR @RhFactor NOT IN (N'Positive', N'Negative')
        THROW 50400, N'Rh factor must be Positive or Negative.', 1;
    IF @Quantity IS NULL OR @Quantity < 0
        THROW 50400, N'Quantity must be zero or greater.', 1;
    IF @Quantity > 100000
        THROW 50400, N'Quantity is out of range.', 1;
    IF @SourceType NOT IN (N'ManualPortal', N'CSVImport', N'PartnerAPI', N'AdminCorrection')
        THROW 50400, N'Invalid source type.', 1;
    IF @EarliestExpiryDate IS NOT NULL AND @EarliestExpiryDate < CAST(@Now AS DATE)
        THROW 50400, N'Earliest expiry date cannot be in the past.', 1;
    IF @ValidUntil IS NULL SET @ValidUntil = dbo.fn_InventoryDefaultValidUntil(N'Blood');
    IF @ValidUntil <= @Now OR @ValidUntil > DATEADD(DAY, 7, @Now)
        THROW 50400, N'Valid until must be in the future and within 7 days.', 1;

    -- Idempotency / duplicate submission
    IF @IdempotencyKey IS NOT NULL
        SELECT TOP (1) @ChangeId = ChangeId, @ResultStatus = Status
        FROM dbo.InventoryChanges
        WHERE SubmittedBy = @ActorUserId AND IdempotencyKey = @IdempotencyKey AND FacilityId = @FacilityId
          AND InventoryKind = N'Blood' AND ComponentId = @ComponentId AND AboGroup = @AboGroup AND RhFactor = @RhFactor
        ORDER BY ChangeId DESC;
    IF @ChangeId IS NULL AND ISNULL(@SkipDuplicateCheck, 0) = 0
        SELECT TOP (1) @ChangeId = ChangeId, @ResultStatus = Status
        FROM dbo.InventoryChanges
        WHERE SubmittedBy = @ActorUserId AND FacilityId = @FacilityId AND InventoryKind = N'Blood'
          AND ComponentId = @ComponentId AND AboGroup = @AboGroup AND RhFactor = @RhFactor
          AND ProposedQuantity = @Quantity
          AND ISNULL(EarliestExpiryDate, '19000101') = ISNULL(@EarliestExpiryDate, '19000101')
          AND Status <> N'Rejected' AND SubmittedAt >= DATEADD(MINUTE, -2, @Now)
        ORDER BY ChangeId DESC;
    IF @ChangeId IS NOT NULL
    BEGIN
        SET @IsDuplicate = 1;
        RETURN;
    END

    DECLARE @TranStarted BIT = 0;
    BEGIN TRY
        IF @@TRANCOUNT = 0 BEGIN BEGIN TRANSACTION; SET @TranStarted = 1; END

        DECLARE @InventoryId INT, @OldQty DECIMAL(12,2), @OldRowVer VARBINARY(8), @OldLastUpdated DATETIME2(0), @OldVerification NVARCHAR(20),
                @Before NVARCHAR(MAX);
        SELECT @InventoryId = InventoryId, @OldQty = Quantity, @OldRowVer = CAST(RowVer AS VARBINARY(8)),
               @OldLastUpdated = LastUpdatedAt, @OldVerification = VerificationStatus
        FROM dbo.BloodInventory WITH (UPDLOCK, HOLDLOCK)
        WHERE FacilityId = @FacilityId AND ComponentId = @ComponentId AND AboGroup = @AboGroup AND RhFactor = @RhFactor;

        IF @InventoryId IS NOT NULL AND (@RowVersion IS NULL OR @RowVersion <> @OldRowVer)
            THROW 50409, N'This stock record was changed by someone else. Reload and try again.', 1;
        IF @InventoryId IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.InventoryChanges WHERE Status = N'PendingReview'
                AND FacilityId = @FacilityId AND InventoryKind = N'Blood' AND ComponentId = @ComponentId AND AboGroup = @AboGroup AND RhFactor = @RhFactor)
            THROW 50409, N'Another change for this stock record is awaiting review.', 1;

        IF @InventoryId IS NOT NULL
            SET @Before = (SELECT Quantity, EarliestExpiryDate, SourceType, VerificationStatus, LastUpdatedAt, ValidUntil
                           FROM dbo.BloodInventory WHERE InventoryId = @InventoryId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        DECLARE @Flags NVARCHAR(400) = NULL;
        IF @OldLastUpdated IS NOT NULL AND dbo.fn_IsLargeJump(@OldQty, @Quantity) = 1
            SET @Flags = N'LARGE_JUMP';

        DECLARE @NeedsReview BIT = CASE WHEN ISNULL(@ForceReview, 0) = 1 THEN 1
                                        WHEN @Flags IS NOT NULL AND dbo.fn_InventoryRequireReview() = 1 THEN 1 ELSE 0 END;

        DECLARE @ChangeNo NVARCHAR(30);
        EXEC dbo.usp_Reference_Next @ActorUserId = @ActorUserId, @Prefix = N'CHG', @Next = @ChangeNo OUTPUT;

        DECLARE @AfterProposed NVARCHAR(MAX) = (SELECT @Quantity AS Quantity, @EarliestExpiryDate AS EarliestExpiryDate, @ValidUntil AS ValidUntil
                                               FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        INSERT INTO dbo.InventoryChanges (ChangeNo, FacilityId, InventoryKind, InventoryId, ComponentId, AboGroup, RhFactor,
            PreviousQuantity, ProposedQuantity, EarliestExpiryDate, ValidUntil, BeforeJson, AfterJson, SourceType, Reason,
            AnomalyFlags, Status, ImportBatchId, IdempotencyKey, SubmittedBy, SubmittedAt)
        VALUES (@ChangeNo, @FacilityId, N'Blood', @InventoryId, @ComponentId, @AboGroup, @RhFactor,
            @OldQty, @Quantity, @EarliestExpiryDate, @ValidUntil, @Before, @AfterProposed, @SourceType, @Reason,
            @Flags, CASE WHEN @NeedsReview = 1 THEN N'PendingReview' ELSE N'Applied' END, @ImportBatchId, @IdempotencyKey, @ActorUserId, @Now);
        SET @ChangeId = SCOPE_IDENTITY();

        IF @NeedsReview = 0
        BEGIN
            EXEC dbo.usp_Inventory_ApplyChange @ActorUserId = @ActorUserId, @ChangeId = @ChangeId, @CorrelationId = @CorrelationId;
            SET @ResultStatus = N'Applied';
        END
        ELSE
        BEGIN
            IF @InventoryId IS NULL
            BEGIN
                INSERT INTO dbo.BloodInventory (FacilityId, ComponentId, AboGroup, RhFactor, Quantity, UnitId, SourceType,
                    VerificationStatus, CreatedAt, CreatedBy)
                VALUES (@FacilityId, @ComponentId, @AboGroup, @RhFactor, 0,
                    ISNULL((SELECT TOP (1) UnitId FROM dbo.Units WHERE Code = N'UNITS'), (SELECT MIN(UnitId) FROM dbo.Units)),
                    @SourceType, N'PendingReview', @Now, @ActorUserId);
                SET @InventoryId = SCOPE_IDENTITY();
                UPDATE dbo.InventoryChanges SET InventoryId = @InventoryId WHERE ChangeId = @ChangeId;
            END
            ELSE
                UPDATE dbo.BloodInventory SET VerificationStatus = N'PendingReview', UpdatedAt = @Now, UpdatedBy = @ActorUserId
                WHERE InventoryId = @InventoryId;

            DECLARE @Label NVARCHAR(100) = (SELECT ItemLabel FROM dbo.vw_InventoryChanges WHERE ChangeId = @ChangeId);
            DECLARE @FacilityName NVARCHAR(200) = (SELECT Name FROM dbo.Facilities WHERE FacilityId = @FacilityId);

            IF @Flags IS NOT NULL
            BEGIN
                DECLARE @Observed NVARCHAR(200) = CONCAT(ISNULL(CAST(@OldQty AS NVARCHAR(30)), N'-'), N' -> ', CAST(@Quantity AS NVARCHAR(30)));
                DECLARE @IssueMsg NVARCHAR(500) = CONCAT(N'Large change for ', @Label, N' (', @Observed, N') requires review (', @ChangeNo, N').');
                IF NOT EXISTS (SELECT 1 FROM dbo.ValidationIssues WHERE EntityType = N'InventoryChange' AND EntityId = @ChangeId AND IssueCode = N'LARGE_JUMP' AND Status = N'Open')
                    INSERT INTO dbo.ValidationIssues (FacilityId, EntityType, EntityId, IssueCode, Severity, ObservedValue, Message, Status, DetectedAt)
                    VALUES (@FacilityId, N'InventoryChange', @ChangeId, N'LARGE_JUMP', N'High', @Observed, @IssueMsg, N'Open', @Now);
            END

            DECLARE @ChangeIdText NVARCHAR(50) = CAST(@ChangeId AS NVARCHAR(50));
            DECLARE @AuditDesc NVARCHAR(1000) = CONCAT(N'Blood stock change ', @ChangeNo, N' for ', @Label, N' queued for review.');
            EXEC dbo.usp_Audit_Write @ActorUserId = @ActorUserId, @EntityType = N'InventoryChange', @EntityId = @ChangeIdText,
                 @ReferenceNo = @ChangeNo, @FacilityId = @FacilityId, @Action = N'SubmittedForReview', @Description = @AuditDesc,
                 @OldValues = @Before, @NewValues = @AfterProposed, @SourceType = @SourceType, @Reason = @Reason, @CorrelationId = @CorrelationId;

            IF ISNULL(@SuppressNotifications, 0) = 0
            BEGIN
                DECLARE @NTitle NVARCHAR(200) = N'Inventory change needs review';
                DECLARE @NMsg NVARCHAR(1000) = CONCAT(@ChangeNo, N': ', @Label, N' at ', @FacilityName, N' (',
                        ISNULL(CAST(@OldQty AS NVARCHAR(30)), N'-'), N' -> ', CAST(@Quantity AS NVARCHAR(30)), N') awaits verification.');
                EXEC dbo.usp_Notification_NotifyFacilityUsers @ActorUserId = @ActorUserId, @FacilityId = @FacilityId, @Title = @NTitle,
                     @Message = @NMsg, @Type = N'Action', @EntityType = N'InventoryChange', @EntityId = @ChangeIdText,
                     @Route = N'/verifications', @AssignmentRoles = N'Verifier,Manager';
                EXEC dbo.usp_Notification_NotifyRole @ActorUserId = @ActorUserId, @RoleCode = N'Admin', @Title = @NTitle,
                     @Message = @NMsg, @Type = N'Action', @EntityType = N'InventoryChange', @EntityId = @ChangeIdText,
                     @Route = N'/verifications';
            END
            SET @ResultStatus = N'PendingReview';
        END

        IF @TranStarted = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @TranStarted = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/*
  Shared medical resource change recorder. Same semantics as usp_Inventory_RecordBloodChange.
  LARGE_JUMP evaluated on AvailableQuantity and TotalQuantity.
*/
CREATE OR ALTER PROCEDURE dbo.usp_Inventory_RecordResourceChange
    @ActorUserId           INT,
    @FacilityId            INT,
    @ResourceTypeId        INT,
    @TotalQuantity         DECIMAL(12,2),
    @AvailableQuantity     DECIMAL(12,2),
    @OperationalStatus     NVARCHAR(20),
    @ValidUntil            DATETIME2(0) = NULL,
    @Notes                 NVARCHAR(500) = NULL,
    @Reason                NVARCHAR(500) = NULL,
    @SourceType            NVARCHAR(20) = N'ManualPortal',
    @RowVersion            VARBINARY(8) = NULL,
    @ImportBatchId         INT = NULL,
    @IdempotencyKey        NVARCHAR(100) = NULL,
    @ForceReview           BIT = 0,
    @SkipDuplicateCheck    BIT = 0,
    @SuppressNotifications BIT = 0,
    @CorrelationId         NVARCHAR(64) = NULL,
    @ChangeId              INT = NULL OUTPUT,
    @IsDuplicate           BIT = 0 OUTPUT,
    @ResultStatus          NVARCHAR(20) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
    SET @ChangeId = NULL; SET @IsDuplicate = 0; SET @ResultStatus = NULL;
    SET @OperationalStatus = LTRIM(RTRIM(@OperationalStatus));
    SET @Reason = NULLIF(LTRIM(RTRIM(@Reason)), N'');
    SET @Notes = NULLIF(LTRIM(RTRIM(@Notes)), N'');
    SET @SourceType = ISNULL(NULLIF(LTRIM(RTRIM(@SourceType)), N''), N'ManualPortal');
    SET @IdempotencyKey = NULLIF(LTRIM(RTRIM(@IdempotencyKey)), N'');

    EXEC dbo.usp_Inventory_AssertFacility @ActorUserId = @ActorUserId, @FacilityId = @FacilityId, @Kind = N'Resource', @RequireWritable = 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.MedicalResourceTypes WHERE ResourceTypeId = @ResourceTypeId AND IsActive = 1)
        THROW 50400, N'Unknown or inactive resource type.', 1;
    IF @TotalQuantity IS NULL OR @AvailableQuantity IS NULL OR @TotalQuantity < 0 OR @AvailableQuantity < 0
        THROW 50400, N'Quantities must be zero or greater.', 1;
    IF @AvailableQuantity > @TotalQuantity
        THROW 50400, N'Available quantity cannot exceed total quantity.', 1;
    IF @TotalQuantity > 100000
        THROW 50400, N'Quantity is out of range.', 1;
    IF @OperationalStatus IS NULL OR @OperationalStatus NOT IN (N'Available', N'Limited', N'Unavailable', N'Unknown')
        THROW 50400, N'Operational status must be Available, Limited, Unavailable or Unknown.', 1;
    IF @SourceType NOT IN (N'ManualPortal', N'CSVImport', N'PartnerAPI', N'AdminCorrection')
        THROW 50400, N'Invalid source type.', 1;
    IF @ValidUntil IS NULL SET @ValidUntil = dbo.fn_InventoryDefaultValidUntil(N'Resource');
    IF @ValidUntil <= @Now OR @ValidUntil > DATEADD(DAY, 7, @Now)
        THROW 50400, N'Valid until must be in the future and within 7 days.', 1;

    IF @IdempotencyKey IS NOT NULL
        SELECT TOP (1) @ChangeId = ChangeId, @ResultStatus = Status
        FROM dbo.InventoryChanges
        WHERE SubmittedBy = @ActorUserId AND IdempotencyKey = @IdempotencyKey AND FacilityId = @FacilityId
          AND InventoryKind = N'Resource' AND ResourceTypeId = @ResourceTypeId
        ORDER BY ChangeId DESC;
    IF @ChangeId IS NULL AND ISNULL(@SkipDuplicateCheck, 0) = 0
        SELECT TOP (1) @ChangeId = ChangeId, @ResultStatus = Status
        FROM dbo.InventoryChanges
        WHERE SubmittedBy = @ActorUserId AND FacilityId = @FacilityId AND InventoryKind = N'Resource'
          AND ResourceTypeId = @ResourceTypeId AND ProposedTotal = @TotalQuantity AND ProposedAvailable = @AvailableQuantity
          AND ProposedStatus = @OperationalStatus
          AND Status <> N'Rejected' AND SubmittedAt >= DATEADD(MINUTE, -2, @Now)
        ORDER BY ChangeId DESC;
    IF @ChangeId IS NOT NULL
    BEGIN
        SET @IsDuplicate = 1;
        RETURN;
    END

    DECLARE @TranStarted BIT = 0;
    BEGIN TRY
        IF @@TRANCOUNT = 0 BEGIN BEGIN TRANSACTION; SET @TranStarted = 1; END

        DECLARE @InventoryId INT, @OldTotal DECIMAL(12,2), @OldAvail DECIMAL(12,2), @OldRowVer VARBINARY(8), @OldLastUpdated DATETIME2(0),
                @Before NVARCHAR(MAX);
        SELECT @InventoryId = ResourceInventoryId, @OldTotal = TotalQuantity, @OldAvail = AvailableQuantity,
               @OldRowVer = CAST(RowVer AS VARBINARY(8)), @OldLastUpdated = LastUpdatedAt
        FROM dbo.MedicalResourceInventory WITH (UPDLOCK, HOLDLOCK)
        WHERE FacilityId = @FacilityId AND ResourceTypeId = @ResourceTypeId;

        IF @InventoryId IS NOT NULL AND (@RowVersion IS NULL OR @RowVersion <> @OldRowVer)
            THROW 50409, N'This resource record was changed by someone else. Reload and try again.', 1;
        IF @InventoryId IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.InventoryChanges WHERE Status = N'PendingReview'
                AND FacilityId = @FacilityId AND InventoryKind = N'Resource' AND ResourceTypeId = @ResourceTypeId)
            THROW 50409, N'Another change for this resource record is awaiting review.', 1;

        IF @InventoryId IS NOT NULL
            SET @Before = (SELECT TotalQuantity, AvailableQuantity, OperationalStatus, Notes, SourceType, VerificationStatus, LastUpdatedAt, ValidUntil
                           FROM dbo.MedicalResourceInventory WHERE ResourceInventoryId = @InventoryId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        DECLARE @Flags NVARCHAR(400) = NULL;
        IF @OldLastUpdated IS NOT NULL AND (dbo.fn_IsLargeJump(@OldAvail, @AvailableQuantity) = 1 OR dbo.fn_IsLargeJump(@OldTotal, @TotalQuantity) = 1)
            SET @Flags = N'LARGE_JUMP';

        DECLARE @NeedsReview BIT = CASE WHEN ISNULL(@ForceReview, 0) = 1 THEN 1
                                        WHEN @Flags IS NOT NULL AND dbo.fn_InventoryRequireReview() = 1 THEN 1 ELSE 0 END;

        DECLARE @ChangeNo NVARCHAR(30);
        EXEC dbo.usp_Reference_Next @ActorUserId = @ActorUserId, @Prefix = N'CHG', @Next = @ChangeNo OUTPUT;

        DECLARE @AfterProposed NVARCHAR(MAX) = (SELECT @TotalQuantity AS TotalQuantity, @AvailableQuantity AS AvailableQuantity,
                                                       @OperationalStatus AS OperationalStatus, @Notes AS Notes, @ValidUntil AS ValidUntil
                                               FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        INSERT INTO dbo.InventoryChanges (ChangeNo, FacilityId, InventoryKind, InventoryId, ResourceTypeId,
            PreviousQuantity, ProposedQuantity, PreviousAvailable, ProposedAvailable, ProposedTotal, ProposedStatus, ValidUntil,
            BeforeJson, AfterJson, SourceType, Reason, AnomalyFlags, Status, ImportBatchId, IdempotencyKey, SubmittedBy, SubmittedAt)
        VALUES (@ChangeNo, @FacilityId, N'Resource', @InventoryId, @ResourceTypeId,
            @OldTotal, @TotalQuantity, @OldAvail, @AvailableQuantity, @TotalQuantity, @OperationalStatus, @ValidUntil,
            @Before, @AfterProposed, @SourceType, @Reason, @Flags, CASE WHEN @NeedsReview = 1 THEN N'PendingReview' ELSE N'Applied' END,
            @ImportBatchId, @IdempotencyKey, @ActorUserId, @Now);
        SET @ChangeId = SCOPE_IDENTITY();

        IF @NeedsReview = 0
        BEGIN
            EXEC dbo.usp_Inventory_ApplyChange @ActorUserId = @ActorUserId, @ChangeId = @ChangeId, @CorrelationId = @CorrelationId;
            SET @ResultStatus = N'Applied';
        END
        ELSE
        BEGIN
            IF @InventoryId IS NULL
            BEGIN
                INSERT INTO dbo.MedicalResourceInventory (FacilityId, ResourceTypeId, TotalQuantity, AvailableQuantity, UnitId,
                    OperationalStatus, SourceType, VerificationStatus, CreatedAt, CreatedBy)
                SELECT @FacilityId, @ResourceTypeId, 0, 0, rt.DefaultUnitId, N'Unknown', @SourceType, N'PendingReview', @Now, @ActorUserId
                FROM dbo.MedicalResourceTypes rt WHERE rt.ResourceTypeId = @ResourceTypeId;
                SET @InventoryId = SCOPE_IDENTITY();
                UPDATE dbo.InventoryChanges SET InventoryId = @InventoryId WHERE ChangeId = @ChangeId;
            END
            ELSE
                UPDATE dbo.MedicalResourceInventory SET VerificationStatus = N'PendingReview', UpdatedAt = @Now, UpdatedBy = @ActorUserId
                WHERE ResourceInventoryId = @InventoryId;

            DECLARE @Label NVARCHAR(100) = (SELECT ItemLabel FROM dbo.vw_InventoryChanges WHERE ChangeId = @ChangeId);
            DECLARE @FacilityName NVARCHAR(200) = (SELECT Name FROM dbo.Facilities WHERE FacilityId = @FacilityId);
            DECLARE @Observed NVARCHAR(200) = CONCAT(N'Available ', ISNULL(CAST(@OldAvail AS NVARCHAR(30)), N'-'), N' -> ', CAST(@AvailableQuantity AS NVARCHAR(30)),
                                                     N'; Total ', ISNULL(CAST(@OldTotal AS NVARCHAR(30)), N'-'), N' -> ', CAST(@TotalQuantity AS NVARCHAR(30)));

            IF @Flags IS NOT NULL
            BEGIN
                DECLARE @IssueMsg NVARCHAR(500) = CONCAT(N'Large change for ', @Label, N' (', @Observed, N') requires review (', @ChangeNo, N').');
                IF NOT EXISTS (SELECT 1 FROM dbo.ValidationIssues WHERE EntityType = N'InventoryChange' AND EntityId = @ChangeId AND IssueCode = N'LARGE_JUMP' AND Status = N'Open')
                    INSERT INTO dbo.ValidationIssues (FacilityId, EntityType, EntityId, IssueCode, Severity, ObservedValue, Message, Status, DetectedAt)
                    VALUES (@FacilityId, N'InventoryChange', @ChangeId, N'LARGE_JUMP', N'High', @Observed, @IssueMsg, N'Open', @Now);
            END

            DECLARE @ChangeIdText NVARCHAR(50) = CAST(@ChangeId AS NVARCHAR(50));
            DECLARE @AuditDesc NVARCHAR(1000) = CONCAT(N'Resource change ', @ChangeNo, N' for ', @Label, N' queued for review.');
            EXEC dbo.usp_Audit_Write @ActorUserId = @ActorUserId, @EntityType = N'InventoryChange', @EntityId = @ChangeIdText,
                 @ReferenceNo = @ChangeNo, @FacilityId = @FacilityId, @Action = N'SubmittedForReview', @Description = @AuditDesc,
                 @OldValues = @Before, @NewValues = @AfterProposed, @SourceType = @SourceType, @Reason = @Reason, @CorrelationId = @CorrelationId;

            IF ISNULL(@SuppressNotifications, 0) = 0
            BEGIN
                DECLARE @NTitle NVARCHAR(200) = N'Inventory change needs review';
                DECLARE @NMsg NVARCHAR(1000) = CONCAT(@ChangeNo, N': ', @Label, N' at ', @FacilityName, N' (', @Observed, N') awaits verification.');
                EXEC dbo.usp_Notification_NotifyFacilityUsers @ActorUserId = @ActorUserId, @FacilityId = @FacilityId, @Title = @NTitle,
                     @Message = @NMsg, @Type = N'Action', @EntityType = N'InventoryChange', @EntityId = @ChangeIdText,
                     @Route = N'/verifications', @AssignmentRoles = N'Verifier,Manager';
                EXEC dbo.usp_Notification_NotifyRole @ActorUserId = @ActorUserId, @RoleCode = N'Admin', @Title = @NTitle,
                     @Message = @NMsg, @Type = N'Action', @EntityType = N'InventoryChange', @EntityId = @ChangeIdText,
                     @Route = N'/verifications';
            END
            SET @ResultStatus = N'PendingReview';
        END

        IF @TranStarted = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @TranStarted = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/* Returns one InventoryChange row (contract shape + extra keys) with CanDecide for the actor. */
CREATE OR ALTER PROCEDURE dbo.usp_Change_GetRow
    @ActorUserId INT,
    @ChangeId    INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT v.ChangeId, v.ChangeNo, v.FacilityId, v.FacilityName, v.FacilityCode, v.InventoryKind, v.InventoryId, v.ItemLabel,
           v.ComponentId, v.ComponentCode, v.AboGroup, v.RhFactor, v.ResourceTypeId, v.ResourceTypeCode,
           v.PreviousQuantity, v.ProposedQuantity, v.PreviousAvailable, v.ProposedAvailable, v.ProposedTotal, v.ProposedStatus,
           v.EarliestExpiryDate, v.ValidUntil, v.SourceType, v.Reason, v.AnomalyFlags, v.Status, v.ImportBatchId,
           v.SubmittedBy, v.SubmittedByName, v.SubmittedAt, v.DecidedBy, v.DecidedByName, v.DecidedAt, v.DecisionReason,
           dbo.fn_CanDecideChange(@ActorUserId, v.FacilityId, v.SubmittedBy, v.Status) AS CanDecide
    FROM dbo.vw_InventoryChanges v
    WHERE v.ChangeId = @ChangeId;
END
GO

/*=====================================================================
  Facilities
=====================================================================*/

/* GET facilities — facilities the actor is assigned to (all for data.viewall). Paged<Facility>. */
CREATE OR ALTER PROCEDURE dbo.usp_Facility_SearchMine
    @ActorUserId  INT,
    @FacilityType NVARCHAR(20) = NULL,
    @Search       NVARCHAR(200) = NULL,
    @Page         INT = 1,
    @PageSize     INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Page = CASE WHEN ISNULL(@Page, 1) < 1 THEN 1 ELSE @Page END;
    SET @PageSize = CASE WHEN ISNULL(@PageSize, 20) < 1 THEN 20 WHEN @PageSize > 100 THEN 100 ELSE @PageSize END;
    SET @FacilityType = NULLIF(LTRIM(RTRIM(@FacilityType)), N'');
    SET @Search = NULLIF(LTRIM(RTRIM(@Search)), N'');

    DECLARE @ViewAll BIT = dbo.fn_UserHasPermission(@ActorUserId, N'data.viewall');

    SELECT f.FacilityId INTO #Ids
    FROM dbo.Facilities f
    INNER JOIN dbo.Areas a ON a.AreaId = f.AreaId
    WHERE (@ViewAll = 1 OR EXISTS (SELECT 1 FROM dbo.FacilityUserAssignments fa
                                   WHERE fa.FacilityId = f.FacilityId AND fa.UserId = @ActorUserId AND fa.IsActive = 1))
      AND (@FacilityType IS NULL OR f.FacilityType = @FacilityType)
      AND (@Search IS NULL OR f.Name LIKE N'%' + @Search + N'%' OR f.FacilityCode LIKE N'%' + @Search + N'%'
           OR f.City LIKE N'%' + @Search + N'%' OR a.Name LIKE N'%' + @Search + N'%');

    DECLARE @Total INT = (SELECT COUNT(*) FROM #Ids);

    SELECT v.FacilityId, v.FacilityCode, v.Name, v.FacilityType, v.LicenseNo, v.AddressLine, v.AreaId, v.AreaName, v.City,
           v.Pincode, v.Latitude, v.Longitude, v.ContactPhone, v.ContactEmail, v.Is24x7, v.VerificationStatus, v.VerifiedAt,
           v.VerificationNotes, v.IsActive, v.QualityScore, v.FreshPercent, v.StaleRecords, v.LastUpdateAt, v.RowVersion, v.CreatedAt,
           fa.AssignmentRole
    FROM dbo.vw_Facilities v
    INNER JOIN #Ids i ON i.FacilityId = v.FacilityId
    LEFT JOIN dbo.FacilityUserAssignments fa ON fa.FacilityId = v.FacilityId AND fa.UserId = @ActorUserId AND fa.IsActive = 1
    ORDER BY v.Name, v.FacilityId
    OFFSET (@Page - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT @Total AS TotalCount;
END
GO

/* GET facilities/{id} — 3 sets: Facility, users, quality (vw_FacilityQualityScore). */
CREATE OR ALTER PROCEDURE dbo.usp_Facility_GetById
    @ActorUserId INT,
    @FacilityId  INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC dbo.usp_Inventory_AssertFacility @ActorUserId = @ActorUserId, @FacilityId = @FacilityId;

    SELECT v.FacilityId, v.FacilityCode, v.Name, v.FacilityType, v.LicenseNo, v.AddressLine, v.AreaId, v.AreaName, v.City,
           v.Pincode, v.Latitude, v.Longitude, v.ContactPhone, v.ContactEmail, v.Is24x7, v.VerificationStatus, v.VerifiedAt,
           v.VerificationNotes, v.IsActive, v.QualityScore, v.FreshPercent, v.StaleRecords, v.LastUpdateAt, v.RowVersion, v.CreatedAt
    FROM dbo.vw_Facilities v
    WHERE v.FacilityId = @FacilityId;

    SELECT u.UserId, u.DisplayName, u.Email, fa.AssignmentRole
    FROM dbo.FacilityUserAssignments fa
    INNER JOIN dbo.Users u ON u.UserId = fa.UserId AND u.IsActive = 1
    WHERE fa.FacilityId = @FacilityId AND fa.IsActive = 1
    ORDER BY CASE fa.AssignmentRole WHEN N'Manager' THEN 1 WHEN N'Verifier' THEN 2 ELSE 3 END, u.DisplayName;

    SELECT q.FacilityId, q.FacilityCode, q.FacilityName, q.FacilityType, q.TotalRecords, q.Fresh, q.Aging, q.Stale, q.Unknown,
           q.UnderReview, q.OpenIssues, q.StaleRecords, q.FreshPercent, q.CompletenessScore, q.RecencyScore, q.VerificationScore,
           q.AnomalyScore, q.QualityScore, q.LastUpdateAt
    FROM dbo.vw_FacilityQualityScore q
    WHERE q.FacilityId = @FacilityId;
END
GO

/* PUT facilities/{id} — profile edit by assigned users (facilities.manage). Returns Facility. */
CREATE OR ALTER PROCEDURE dbo.usp_Facility_Update
    @ActorUserId   INT,
    @FacilityId    INT,
    @Name          NVARCHAR(200),
    @LicenseNo     NVARCHAR(60) = NULL,
    @AddressLine   NVARCHAR(300),
    @AreaId        INT,
    @City          NVARCHAR(100),
    @Pincode       NVARCHAR(10) = NULL,
    @Latitude      DECIMAL(9,6) = NULL,
    @Longitude     DECIMAL(9,6) = NULL,
    @ContactPhone  NVARCHAR(30),
    @ContactEmail  NVARCHAR(320) = NULL,
    @Is24x7        BIT = 0,
    @RowVersion    VARBINARY(8) = NULL,
    @CorrelationId NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'facilities.manage') = 0
        THROW 50403, N'You do not have permission to manage facilities.', 1;
    EXEC dbo.usp_Inventory_AssertFacility @ActorUserId = @ActorUserId, @FacilityId = @FacilityId;

    SET @Name = NULLIF(LTRIM(RTRIM(@Name)), N'');
    SET @AddressLine = NULLIF(LTRIM(RTRIM(@AddressLine)), N'');
    SET @City = NULLIF(LTRIM(RTRIM(@City)), N'');
    SET @ContactPhone = NULLIF(LTRIM(RTRIM(@ContactPhone)), N'');
    SET @ContactEmail = NULLIF(LTRIM(RTRIM(@ContactEmail)), N'');
    SET @LicenseNo = NULLIF(LTRIM(RTRIM(@LicenseNo)), N'');
    SET @Pincode = NULLIF(LTRIM(RTRIM(@Pincode)), N'');

    IF @Name IS NULL OR @AddressLine IS NULL OR @City IS NULL OR @ContactPhone IS NULL
        THROW 50400, N'Name, address, city and contact phone are required.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Areas WHERE AreaId = @AreaId AND IsActive = 1)
        THROW 50400, N'Unknown or inactive area.', 1;
    IF (@Latitude IS NOT NULL AND (@Latitude < -90 OR @Latitude > 90)) OR (@Longitude IS NOT NULL AND (@Longitude < -180 OR @Longitude > 180))
        THROW 50400, N'Latitude/longitude out of range.', 1;
    IF @ContactEmail IS NOT NULL AND @ContactEmail NOT LIKE N'%_@_%._%'
        THROW 50400, N'Contact email is invalid.', 1;

    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME(), @Code NVARCHAR(20), @Old NVARCHAR(MAX), @New NVARCHAR(MAX);

    BEGIN TRANSACTION;
    BEGIN TRY
        IF @RowVersion IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Facilities WITH (UPDLOCK, HOLDLOCK)
                                                   WHERE FacilityId = @FacilityId AND RowVer = @RowVersion)
            THROW 50409, N'The facility was changed by someone else. Reload and try again.', 1;

        SELECT @Code = FacilityCode,
               @Old = (SELECT f2.Name, f2.LicenseNo, f2.AddressLine, f2.AreaId, f2.City, f2.Pincode, f2.Latitude, f2.Longitude,
                              f2.ContactPhone, f2.ContactEmail, f2.Is24x7
                       FROM dbo.Facilities f2 WHERE f2.FacilityId = @FacilityId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        FROM dbo.Facilities WHERE FacilityId = @FacilityId;

        UPDATE dbo.Facilities
        SET Name = @Name, LicenseNo = @LicenseNo, AddressLine = @AddressLine, AreaId = @AreaId, City = @City, Pincode = @Pincode,
            Latitude = @Latitude, Longitude = @Longitude, ContactPhone = @ContactPhone, ContactEmail = @ContactEmail,
            Is24x7 = ISNULL(@Is24x7, 0), UpdatedAt = @Now, UpdatedBy = @ActorUserId
        WHERE FacilityId = @FacilityId;

        SET @New = (SELECT f2.Name, f2.LicenseNo, f2.AddressLine, f2.AreaId, f2.City, f2.Pincode, f2.Latitude, f2.Longitude,
                           f2.ContactPhone, f2.ContactEmail, f2.Is24x7
                    FROM dbo.Facilities f2 WHERE f2.FacilityId = @FacilityId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        DECLARE @IdText NVARCHAR(50) = CAST(@FacilityId AS NVARCHAR(50));
        DECLARE @Desc NVARCHAR(1000) = N'Facility profile updated: ' + @Name + N'.';
        EXEC dbo.usp_Audit_Write @ActorUserId = @ActorUserId, @EntityType = N'Facility', @EntityId = @IdText, @ReferenceNo = @Code,
             @FacilityId = @FacilityId, @Action = N'Updated', @Description = @Desc, @OldValues = @Old, @NewValues = @New,
             @SourceType = N'ManualPortal', @CorrelationId = @CorrelationId;

        DECLARE @Msg NVARCHAR(1000) = N'The profile of ' + @Name + N' (' + @Code + N') was updated.';
        DECLARE @Route NVARCHAR(300) = N'/facilities/' + @IdText;
        EXEC dbo.usp_Notification_NotifyFacilityUsers @ActorUserId = @ActorUserId, @FacilityId = @FacilityId,
             @Title = N'Facility profile updated', @Message = @Msg, @Type = N'Info', @EntityType = N'Facility',
             @EntityId = @IdText, @Route = @Route;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT v.FacilityId, v.FacilityCode, v.Name, v.FacilityType, v.LicenseNo, v.AddressLine, v.AreaId, v.AreaName, v.City,
           v.Pincode, v.Latitude, v.Longitude, v.ContactPhone, v.ContactEmail, v.Is24x7, v.VerificationStatus, v.VerifiedAt,
           v.VerificationNotes, v.IsActive, v.QualityScore, v.FreshPercent, v.StaleRecords, v.LastUpdateAt, v.RowVersion, v.CreatedAt
    FROM dbo.vw_Facilities v
    WHERE v.FacilityId = @FacilityId;
END
GO

/* GET facilities/{id}/history?kind&top — snapshot rows (newest first, max 1000). */
CREATE OR ALTER PROCEDURE dbo.usp_Inventory_GetSnapshots
    @ActorUserId INT,
    @FacilityId  INT,
    @Kind        NVARCHAR(10) = NULL,
    @Top         INT = 200
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC dbo.usp_Inventory_AssertFacility @ActorUserId = @ActorUserId, @FacilityId = @FacilityId;
    SET @Kind = NULLIF(LTRIM(RTRIM(@Kind)), N'');
    SET @Top = CASE WHEN ISNULL(@Top, 200) < 1 THEN 200 WHEN @Top > 1000 THEN 1000 ELSE @Top END;

    SELECT TOP (@Top)
           s.SnapshotId, s.FacilityId, s.InventoryKind, s.InventoryId,
           s.ComponentId, bc.Code AS ComponentCode, s.AboGroup, s.RhFactor,
           CASE WHEN s.AboGroup IS NULL THEN NULL ELSE s.AboGroup + CASE s.RhFactor WHEN N'Positive' THEN N'+' ELSE N'-' END END AS BloodGroup,
           s.ResourceTypeId, rt.Code AS ResourceTypeCode, rt.Name AS ResourceTypeName,
           CASE WHEN s.InventoryKind = N'Blood'
                THEN bc.Code + N' ' + s.AboGroup + CASE s.RhFactor WHEN N'Positive' THEN N'+' ELSE N'-' END
                ELSE rt.Name END AS ItemLabel,
           s.Quantity, s.AvailableQuantity, s.TotalQuantity, s.OperationalStatus, s.SourceType, s.VerificationStatus,
           s.RecordedAt, s.ValidUntil, s.ChangeId, u.DisplayName AS RecordedByName
    FROM dbo.AvailabilitySnapshots s
    LEFT JOIN dbo.BloodComponents bc      ON bc.ComponentId = s.ComponentId
    LEFT JOIN dbo.MedicalResourceTypes rt ON rt.ResourceTypeId = s.ResourceTypeId
    LEFT JOIN dbo.Users u                 ON u.UserId = s.RecordedBy
    WHERE s.FacilityId = @FacilityId AND (@Kind IS NULL OR s.InventoryKind = @Kind)
    ORDER BY s.RecordedAt DESC, s.SnapshotId DESC;
END
GO

/*=====================================================================
  Medical resource inventory
=====================================================================*/

/* GET facilities/{id}/resources — every active resource type (un-recorded ones with NULLs / Unknown). */
CREATE OR ALTER PROCEDURE dbo.usp_Resource_GetByFacility
    @ActorUserId INT,
    @FacilityId  INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'resources.manage') = 0
        THROW 50403, N'You do not have permission to manage medical resources.', 1;
    EXEC dbo.usp_Inventory_AssertFacility @ActorUserId = @ActorUserId, @FacilityId = @FacilityId, @Kind = N'Resource';

    SELECT mri.ResourceInventoryId, @FacilityId AS FacilityId, rt.ResourceTypeId, rt.Code AS ResourceTypeCode, rt.Name AS ResourceTypeName,
           rc.Name AS CategoryName, rt.TrackingMode, mri.TotalQuantity, mri.AvailableQuantity,
           ISNULL(mri.UnitId, rt.DefaultUnitId) AS UnitId, un.Code AS UnitCode,
           ISNULL(mri.OperationalStatus, N'Unknown') AS OperationalStatus, mri.Notes, mri.SourceType, mri.VerificationStatus,
           CASE WHEN mri.ResourceInventoryId IS NULL THEN N'Unknown'
                ELSE dbo.fn_FreshnessStatus(mri.LastUpdatedAt, mri.ValidUntil, mri.VerificationStatus) END AS FreshnessStatus,
           mri.LastUpdatedAt, lu.DisplayName AS LastUpdatedByName, mri.ValidUntil,
           CAST(mri.RowVer AS VARBINARY(8)) AS RowVersion,
           pc.ChangeId AS PendingChangeId
    FROM dbo.MedicalResourceTypes rt
    INNER JOIN dbo.ResourceCategories rc ON rc.CategoryId = rt.CategoryId
    LEFT JOIN dbo.MedicalResourceInventory mri ON mri.ResourceTypeId = rt.ResourceTypeId AND mri.FacilityId = @FacilityId
    LEFT JOIN dbo.Units un ON un.UnitId = ISNULL(mri.UnitId, rt.DefaultUnitId)
    LEFT JOIN dbo.Users lu ON lu.UserId = mri.LastUpdatedBy
    OUTER APPLY (SELECT TOP (1) ic.ChangeId FROM dbo.InventoryChanges ic
                 WHERE ic.FacilityId = @FacilityId AND ic.InventoryKind = N'Resource' AND ic.ResourceTypeId = rt.ResourceTypeId
                   AND ic.Status = N'PendingReview' ORDER BY ic.ChangeId DESC) pc
    WHERE rt.IsActive = 1 OR mri.ResourceInventoryId IS NOT NULL
    ORDER BY rc.Name, rt.Name;
END
GO

/* POST facilities/{id}/resources/updates — returns InventoryChange. */
CREATE OR ALTER PROCEDURE dbo.usp_Resource_SubmitUpdate
    @ActorUserId       INT,
    @FacilityId        INT,
    @ResourceTypeId    INT,
    @TotalQuantity     DECIMAL(12,2),
    @AvailableQuantity DECIMAL(12,2),
    @OperationalStatus NVARCHAR(20),
    @ValidUntil        DATETIME2(0) = NULL,
    @Notes             NVARCHAR(500) = NULL,
    @Reason            NVARCHAR(500) = NULL,
    @RowVersion        VARBINARY(8) = NULL,
    @CorrelationId     NVARCHAR(64) = NULL,
    @IdempotencyKey    NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'resources.manage') = 0
        THROW 50403, N'You do not have permission to manage medical resources.', 1;

    DECLARE @ChangeId INT, @IsDuplicate BIT, @ResultStatus NVARCHAR(20);
    EXEC dbo.usp_Inventory_RecordResourceChange @ActorUserId = @ActorUserId, @FacilityId = @FacilityId, @ResourceTypeId = @ResourceTypeId,
         @TotalQuantity = @TotalQuantity, @AvailableQuantity = @AvailableQuantity, @OperationalStatus = @OperationalStatus,
         @ValidUntil = @ValidUntil, @Notes = @Notes, @Reason = @Reason, @SourceType = N'ManualPortal', @RowVersion = @RowVersion,
         @IdempotencyKey = @IdempotencyKey, @CorrelationId = @CorrelationId,
         @ChangeId = @ChangeId OUTPUT, @IsDuplicate = @IsDuplicate OUTPUT, @ResultStatus = @ResultStatus OUTPUT;

    EXEC dbo.usp_Change_GetRow @ActorUserId = @ActorUserId, @ChangeId = @ChangeId;
END
GO

/*
  Re-confirms unchanged resource values ("still valid"): new LastUpdatedAt/ValidUntil, Confirmed, snapshot, audit.
  @ResourceInventoryIds = CSV; rows under review or never recorded are skipped. Returns the confirmed rows.
*/
CREATE OR ALTER PROCEDURE dbo.usp_Resource_ConfirmCurrent
    @ActorUserId          INT,
    @FacilityId           INT,
    @ResourceInventoryIds NVARCHAR(MAX),
    @CorrelationId        NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'resources.manage') = 0
        THROW 50403, N'You do not have permission to manage medical resources.', 1;
    EXEC dbo.usp_Inventory_AssertFacility @ActorUserId = @ActorUserId, @FacilityId = @FacilityId, @Kind = N'Resource', @RequireWritable = 1;

    DECLARE @Ids TABLE (Id INT PRIMARY KEY);
    INSERT INTO @Ids (Id)
    SELECT DISTINCT TRY_CONVERT(INT, LTRIM(RTRIM(s.value))) FROM STRING_SPLIT(ISNULL(@ResourceInventoryIds, N''), N',') s
    WHERE TRY_CONVERT(INT, LTRIM(RTRIM(s.value))) IS NOT NULL;
    IF NOT EXISTS (SELECT 1 FROM @Ids)
        THROW 50400, N'Select at least one resource record to confirm.', 1;
    IF EXISTS (SELECT 1 FROM @Ids i WHERE NOT EXISTS (SELECT 1 FROM dbo.MedicalResourceInventory m WHERE m.ResourceInventoryId = i.Id AND m.FacilityId = @FacilityId))
        THROW 50404, N'One or more resource records were not found for this facility.', 1;

    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME(), @VU DATETIME2(0) = dbo.fn_InventoryDefaultValidUntil(N'Resource');
    DECLARE @Done TABLE (Id INT PRIMARY KEY);

    BEGIN TRANSACTION;
    BEGIN TRY
        UPDATE m
        SET LastUpdatedAt = @Now, LastUpdatedBy = @ActorUserId, ValidUntil = @VU, VerificationStatus = N'Confirmed',
            UpdatedAt = @Now, UpdatedBy = @ActorUserId
        OUTPUT inserted.ResourceInventoryId INTO @Done (Id)
        FROM dbo.MedicalResourceInventory m
        INNER JOIN @Ids i ON i.Id = m.ResourceInventoryId
        WHERE m.FacilityId = @FacilityId AND m.VerificationStatus <> N'PendingReview' AND m.LastUpdatedAt IS NOT NULL;

        INSERT INTO dbo.AvailabilitySnapshots (FacilityId, InventoryKind, InventoryId, ResourceTypeId, AvailableQuantity, TotalQuantity,
            OperationalStatus, SourceType, VerificationStatus, RecordedAt, ValidUntil, ChangeId, RecordedBy)
        SELECT m.FacilityId, N'Resource', m.ResourceInventoryId, m.ResourceTypeId, m.AvailableQuantity, m.TotalQuantity,
            m.OperationalStatus, m.SourceType, N'Confirmed', @Now, @VU, NULL, @ActorUserId
        FROM dbo.MedicalResourceInventory m INNER JOIN @Done d ON d.Id = m.ResourceInventoryId;

        UPDATE vi SET Status = N'Resolved', ResolvedBy = @ActorUserId, ResolvedAt = @Now, Resolution = N'Values re-confirmed as current.'
        FROM dbo.ValidationIssues vi INNER JOIN @Done d ON d.Id = vi.EntityId
        WHERE vi.EntityType = N'ResourceInventory' AND vi.Status = N'Open' AND vi.IssueCode = N'STALE';

        DECLARE @Cnt INT = (SELECT COUNT(*) FROM @Done);
        DECLARE @FIdText NVARCHAR(50) = CAST(@FacilityId AS NVARCHAR(50));
        DECLARE @NewVals NVARCHAR(MAX) = (SELECT d.Id AS ResourceInventoryId, @VU AS ValidUntil FROM @Done d FOR JSON PATH);
        DECLARE @Desc NVARCHAR(1000) = CONCAT(N'Re-confirmed ', @Cnt, N' medical resource record(s) as current.');
        EXEC dbo.usp_Audit_Write @ActorUserId = @ActorUserId, @EntityType = N'Facility', @EntityId = @FIdText,
             @FacilityId = @FacilityId, @Action = N'ResourcesConfirmed', @Description = @Desc, @NewValues = @NewVals,
             @SourceType = N'ManualPortal', @CorrelationId = @CorrelationId;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT m.ResourceInventoryId, m.FacilityId, m.ResourceTypeId, rt.Code AS ResourceTypeCode, rt.Name AS ResourceTypeName,
           m.TotalQuantity, m.AvailableQuantity, m.OperationalStatus, m.VerificationStatus,
           dbo.fn_FreshnessStatus(m.LastUpdatedAt, m.ValidUntil, m.VerificationStatus) AS FreshnessStatus,
           m.LastUpdatedAt, m.ValidUntil, CAST(m.RowVer AS VARBINARY(8)) AS RowVersion
    FROM dbo.MedicalResourceInventory m
    INNER JOIN @Done d ON d.Id = m.ResourceInventoryId
    INNER JOIN dbo.MedicalResourceTypes rt ON rt.ResourceTypeId = m.ResourceTypeId
    ORDER BY rt.Name;
END
GO
