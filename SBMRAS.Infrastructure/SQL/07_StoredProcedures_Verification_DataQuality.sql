/*=====================================================================
  SBMRAS - 07_StoredProcedures_Verification_DataQuality.sql
  Inventory change verification queue / decisions and data-quality
  summary, issues, resolution and on-demand scan (contract §4.4, §6).
  Depends on 05 helpers (vw_InventoryChanges, fn_CanDecideChange, usp_Inventory_ApplyChange, usp_Change_GetRow).
=====================================================================*/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* GET inventory-changes — Paged<InventoryChange>, scoped to accessible facilities. Pending first. */
CREATE OR ALTER PROCEDURE dbo.usp_Change_Search
    @ActorUserId   INT,
    @Status        NVARCHAR(20) = NULL,
    @FacilityId    INT = NULL,
    @InventoryKind NVARCHAR(10) = NULL,
    @Page          INT = 1,
    @PageSize      INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'inventory.verify') = 0
        THROW 50403, N'You do not have permission to verify inventory changes.', 1;
    IF @FacilityId IS NOT NULL
        EXEC dbo.usp_Inventory_AssertFacility @ActorUserId = @ActorUserId, @FacilityId = @FacilityId;

    SET @Page = CASE WHEN ISNULL(@Page, 1) < 1 THEN 1 ELSE @Page END;
    SET @PageSize = CASE WHEN ISNULL(@PageSize, 20) < 1 THEN 20 WHEN @PageSize > 100 THEN 100 ELSE @PageSize END;
    SET @Status = NULLIF(LTRIM(RTRIM(@Status)), N'');
    SET @InventoryKind = NULLIF(LTRIM(RTRIM(@InventoryKind)), N'');

    DECLARE @ViewAll BIT = dbo.fn_UserHasPermission(@ActorUserId, N'data.viewall');

    SELECT ic.ChangeId INTO #Ids
    FROM dbo.InventoryChanges ic
    WHERE (@Status IS NULL OR ic.Status = @Status)
      AND (@FacilityId IS NULL OR ic.FacilityId = @FacilityId)
      AND (@InventoryKind IS NULL OR ic.InventoryKind = @InventoryKind)
      AND (@ViewAll = 1 OR EXISTS (SELECT 1 FROM dbo.FacilityUserAssignments fa
                                   WHERE fa.FacilityId = ic.FacilityId AND fa.UserId = @ActorUserId AND fa.IsActive = 1));

    DECLARE @Total INT = (SELECT COUNT(*) FROM #Ids);

    SELECT v.ChangeId, v.ChangeNo, v.FacilityId, v.FacilityName, v.FacilityCode, v.InventoryKind, v.InventoryId, v.ItemLabel,
           v.ComponentId, v.ComponentCode, v.AboGroup, v.RhFactor, v.ResourceTypeId, v.ResourceTypeCode,
           v.PreviousQuantity, v.ProposedQuantity, v.PreviousAvailable, v.ProposedAvailable, v.ProposedTotal, v.ProposedStatus,
           v.EarliestExpiryDate, v.ValidUntil, v.SourceType, v.Reason, v.AnomalyFlags, v.Status, v.ImportBatchId,
           v.SubmittedBy, v.SubmittedByName, v.SubmittedAt, v.DecidedBy, v.DecidedByName, v.DecidedAt, v.DecisionReason,
           dbo.fn_CanDecideChange(@ActorUserId, v.FacilityId, v.SubmittedBy, v.Status) AS CanDecide
    FROM dbo.vw_InventoryChanges v
    INNER JOIN #Ids i ON i.ChangeId = v.ChangeId
    ORDER BY CASE WHEN v.Status = N'PendingReview' THEN 0 ELSE 1 END, v.SubmittedAt DESC, v.ChangeId DESC
    OFFSET (@Page - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT @Total AS TotalCount;
END
GO

/*
  POST inventory-changes/{id}/decision — Approve applies the proposed values (snapshot + audit) and resolves the
  LARGE_JUMP issue(s); Reject (reason required) restores the record's verification status. Submitter notified.
  Decider must hold inventory.verify, be scoped to the facility and differ from the submitter unless Admin.
*/
CREATE OR ALTER PROCEDURE dbo.usp_Change_Decide
    @ActorUserId   INT,
    @ChangeId      INT,
    @Decision      NVARCHAR(10),
    @Reason        NVARCHAR(500) = NULL,
    @CorrelationId NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Decision = LTRIM(RTRIM(@Decision));
    SET @Reason = NULLIF(LTRIM(RTRIM(@Reason)), N'');

    IF dbo.fn_UserHasPermission(@ActorUserId, N'inventory.verify') = 0
        THROW 50403, N'You do not have permission to verify inventory changes.', 1;
    IF @Decision IS NULL OR @Decision NOT IN (N'Approve', N'Reject')
        THROW 50400, N'Decision must be Approve or Reject.', 1;
    IF @Decision = N'Reject' AND @Reason IS NULL
        THROW 50400, N'A reason is required to reject a change.', 1;

    DECLARE @FacilityId INT, @Kind NVARCHAR(10), @Status NVARCHAR(20), @SubmittedBy INT, @ChangeNo NVARCHAR(20), @InventoryId INT,
            @SourceType NVARCHAR(20);
    SELECT @FacilityId = FacilityId, @Kind = InventoryKind, @Status = Status, @SubmittedBy = SubmittedBy, @ChangeNo = ChangeNo,
           @InventoryId = InventoryId, @SourceType = SourceType
    FROM dbo.InventoryChanges WHERE ChangeId = @ChangeId;

    IF @FacilityId IS NULL
        THROW 50404, N'Inventory change not found.', 1;
    IF dbo.fn_UserCanAccessFacility(@ActorUserId, @FacilityId) = 0
        THROW 50403, N'You are not assigned to this facility.', 1;
    IF @Status <> N'PendingReview'
        THROW 50409, N'This change has already been decided.', 1;
    IF @SubmittedBy = @ActorUserId AND dbo.fn_UserIsAdmin(@ActorUserId) = 0
        THROW 50403, N'You cannot decide a change you submitted.', 1;
    IF @Decision = N'Approve'
        EXEC dbo.usp_Inventory_AssertFacility @ActorUserId = @ActorUserId, @FacilityId = @FacilityId, @Kind = @Kind, @RequireWritable = 1;

    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @IdText NVARCHAR(50) = CAST(@ChangeId AS NVARCHAR(50));
    DECLARE @Label NVARCHAR(100) = (SELECT ItemLabel FROM dbo.vw_InventoryChanges WHERE ChangeId = @ChangeId);
    DECLARE @Desc NVARCHAR(1000), @Msg NVARCHAR(1000);

    BEGIN TRANSACTION;
    BEGIN TRY
        -- Re-check under lock (concurrent deciders).
        IF NOT EXISTS (SELECT 1 FROM dbo.InventoryChanges WITH (UPDLOCK, HOLDLOCK) WHERE ChangeId = @ChangeId AND Status = N'PendingReview')
            THROW 50409, N'This change has already been decided.', 1;

        IF @Decision = N'Approve'
        BEGIN
            EXEC dbo.usp_Inventory_ApplyChange @ActorUserId = @ActorUserId, @ChangeId = @ChangeId, @CorrelationId = @CorrelationId;

            UPDATE dbo.InventoryChanges
            SET DecidedBy = @ActorUserId, DecidedAt = @Now, DecisionReason = @Reason
            WHERE ChangeId = @ChangeId;

            UPDATE dbo.ValidationIssues
            SET Status = N'Resolved', ResolvedBy = @ActorUserId, ResolvedAt = @Now,
                Resolution = LEFT(N'Change approved' + ISNULL(N': ' + @Reason, N'.'), 500)
            WHERE EntityType = N'InventoryChange' AND EntityId = @ChangeId AND Status = N'Open';

            SET @Desc = CONCAT(N'Inventory change ', @ChangeNo, N' (', @Label, N') approved.');
            SET @Msg = CONCAT(N'Your change ', @ChangeNo, N' for ', @Label, N' was approved and is now live.');
        END
        ELSE
        BEGIN
            UPDATE dbo.InventoryChanges
            SET Status = N'Rejected', DecidedBy = @ActorUserId, DecidedAt = @Now, DecisionReason = @Reason
            WHERE ChangeId = @ChangeId;

            IF NOT EXISTS (SELECT 1 FROM dbo.InventoryChanges WHERE Status = N'PendingReview' AND InventoryId = @InventoryId
                           AND InventoryKind = @Kind AND ChangeId <> @ChangeId)
            BEGIN
                IF @Kind = N'Blood'
                    UPDATE dbo.BloodInventory
                    SET VerificationStatus = CASE WHEN LastUpdatedAt IS NULL THEN N'Unverified' ELSE N'Confirmed' END,
                        UpdatedAt = @Now, UpdatedBy = @ActorUserId
                    WHERE InventoryId = @InventoryId AND VerificationStatus = N'PendingReview';
                ELSE
                    UPDATE dbo.MedicalResourceInventory
                    SET VerificationStatus = CASE WHEN LastUpdatedAt IS NULL THEN N'Unverified' ELSE N'Confirmed' END,
                        UpdatedAt = @Now, UpdatedBy = @ActorUserId
                    WHERE ResourceInventoryId = @InventoryId AND VerificationStatus = N'PendingReview';
            END

            UPDATE dbo.ValidationIssues
            SET Status = N'Resolved', ResolvedBy = @ActorUserId, ResolvedAt = @Now,
                Resolution = LEFT(N'Change rejected: ' + @Reason, 500)
            WHERE EntityType = N'InventoryChange' AND EntityId = @ChangeId AND Status = N'Open';

            SET @Desc = CONCAT(N'Inventory change ', @ChangeNo, N' (', @Label, N') rejected.');
            SET @Msg = CONCAT(N'Your change ', @ChangeNo, N' for ', @Label, N' was rejected: ', @Reason);
        END

        DECLARE @Action NVARCHAR(50) = CASE @Decision WHEN N'Approve' THEN N'Approved' ELSE N'Rejected' END;
        DECLARE @NewVals NVARCHAR(MAX) = (SELECT Status, DecidedBy, DecidedAt, DecisionReason FROM dbo.InventoryChanges
                                          WHERE ChangeId = @ChangeId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC dbo.usp_Audit_Write @ActorUserId = @ActorUserId, @EntityType = N'InventoryChange', @EntityId = @IdText,
             @ReferenceNo = @ChangeNo, @FacilityId = @FacilityId, @Action = @Action, @Description = @Desc,
             @OldValues = N'{"Status":"PendingReview"}', @NewValues = @NewVals, @SourceType = @SourceType, @Reason = @Reason,
             @CorrelationId = @CorrelationId;

        IF @SubmittedBy <> @ActorUserId
        BEGIN
            DECLARE @Title NVARCHAR(200) = CASE @Decision WHEN N'Approve' THEN N'Inventory change approved' ELSE N'Inventory change rejected' END;
            DECLARE @Type NVARCHAR(20) = CASE @Decision WHEN N'Approve' THEN N'Success' ELSE N'Warning' END;
            DECLARE @Route NVARCHAR(300) = CASE @Kind WHEN N'Blood' THEN N'/blood-stock?facilityId=' ELSE N'/resource-inventory?facilityId=' END
                                           + CAST(@FacilityId AS NVARCHAR(20));
            EXEC dbo.usp_Notification_Create @ActorUserId = @ActorUserId, @UserId = @SubmittedBy, @Title = @Title, @Message = @Msg,
                 @Type = @Type, @EntityType = N'InventoryChange', @EntityId = @IdText, @Route = @Route;
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    EXEC dbo.usp_Change_GetRow @ActorUserId = @ActorUserId, @ChangeId = @ChangeId;
END
GO

/*=====================================================================
  Data quality
=====================================================================*/

/* GET data-quality/summary?facilityId — 2 sets: overall (1 row), facilities. */
CREATE OR ALTER PROCEDURE dbo.usp_DataQuality_GetSummary
    @ActorUserId INT,
    @FacilityId  INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'dataquality.view') = 0
        THROW 50403, N'You do not have permission to view data quality.', 1;
    IF @FacilityId IS NOT NULL
        EXEC dbo.usp_Inventory_AssertFacility @ActorUserId = @ActorUserId, @FacilityId = @FacilityId;

    DECLARE @ViewAll BIT = dbo.fn_UserHasPermission(@ActorUserId, N'data.viewall');

    SELECT q.FacilityId, q.FacilityName, q.FacilityCode, q.FacilityType, q.VerificationStatus, q.TotalRecords,
           q.QualityScore, q.CompletenessScore, q.RecencyScore, q.VerificationScore, q.AnomalyScore,
           q.Fresh, q.Aging, q.Stale, q.Unknown, q.UnderReview, q.OpenIssues, q.LastUpdateAt
    INTO #Q
    FROM dbo.vw_FacilityQualityScore q
    WHERE q.IsActive = 1
      AND (@FacilityId IS NULL OR q.FacilityId = @FacilityId)
      AND (@ViewAll = 1 OR EXISTS (SELECT 1 FROM dbo.FacilityUserAssignments fa
                                   WHERE fa.FacilityId = q.FacilityId AND fa.UserId = @ActorUserId AND fa.IsActive = 1));

    SELECT CAST(ISNULL(AVG(CASE WHEN TotalRecords > 0 THEN QualityScore END), 0) AS DECIMAL(5,2)) AS QualityScore,
           CAST(CASE WHEN SUM(TotalRecords) > 0 THEN SUM(CompletenessScore * TotalRecords) / SUM(TotalRecords) ELSE 0 END AS DECIMAL(5,2)) AS CompletenessScore,
           CAST(CASE WHEN SUM(TotalRecords) > 0 THEN SUM(RecencyScore * TotalRecords) / SUM(TotalRecords) ELSE 0 END AS DECIMAL(5,2)) AS RecencyScore,
           CAST(CASE WHEN SUM(TotalRecords) > 0 THEN SUM(VerificationScore * TotalRecords) / SUM(TotalRecords) ELSE 0 END AS DECIMAL(5,2)) AS VerificationScore,
           CAST(ISNULL(AVG(AnomalyScore), 100) AS DECIMAL(5,2)) AS AnomalyScore,
           ISNULL(SUM(Fresh), 0) AS Fresh, ISNULL(SUM(Aging), 0) AS Aging, ISNULL(SUM(Stale), 0) AS Stale,
           ISNULL(SUM(Unknown), 0) AS Unknown, ISNULL(SUM(UnderReview), 0) AS UnderReview, ISNULL(SUM(OpenIssues), 0) AS OpenIssues,
           COUNT(*) AS FacilityCount, MAX(LastUpdateAt) AS LastUpdateAt
    FROM #Q;

    SELECT FacilityId, FacilityName, FacilityCode, FacilityType, VerificationStatus, TotalRecords,
           QualityScore, CompletenessScore, RecencyScore, VerificationScore, AnomalyScore,
           Fresh, Aging, Stale, Unknown, UnderReview, OpenIssues, LastUpdateAt
    FROM #Q
    ORDER BY QualityScore ASC, FacilityName;
END
GO

/* GET data-quality/issues — Paged issues, scoped. Open first, then severity, newest. */
CREATE OR ALTER PROCEDURE dbo.usp_DataQuality_SearchIssues
    @ActorUserId INT,
    @Status      NVARCHAR(20) = NULL,
    @Severity    NVARCHAR(10) = NULL,
    @IssueCode   NVARCHAR(20) = NULL,
    @FacilityId  INT = NULL,
    @Page        INT = 1,
    @PageSize    INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'dataquality.view') = 0
        THROW 50403, N'You do not have permission to view data quality.', 1;
    IF @FacilityId IS NOT NULL
        EXEC dbo.usp_Inventory_AssertFacility @ActorUserId = @ActorUserId, @FacilityId = @FacilityId;

    SET @Page = CASE WHEN ISNULL(@Page, 1) < 1 THEN 1 ELSE @Page END;
    SET @PageSize = CASE WHEN ISNULL(@PageSize, 20) < 1 THEN 20 WHEN @PageSize > 100 THEN 100 ELSE @PageSize END;
    SET @Status = NULLIF(LTRIM(RTRIM(@Status)), N'');
    SET @Severity = NULLIF(LTRIM(RTRIM(@Severity)), N'');
    SET @IssueCode = NULLIF(LTRIM(RTRIM(@IssueCode)), N'');

    DECLARE @ViewAll BIT = dbo.fn_UserHasPermission(@ActorUserId, N'data.viewall');

    SELECT vi.IssueId INTO #Ids
    FROM dbo.ValidationIssues vi
    WHERE (@Status IS NULL OR vi.Status = @Status)
      AND (@Severity IS NULL OR vi.Severity = @Severity)
      AND (@IssueCode IS NULL OR vi.IssueCode = @IssueCode)
      AND (@FacilityId IS NULL OR vi.FacilityId = @FacilityId)
      AND (@ViewAll = 1 OR EXISTS (SELECT 1 FROM dbo.FacilityUserAssignments fa
                                   WHERE fa.FacilityId = vi.FacilityId AND fa.UserId = @ActorUserId AND fa.IsActive = 1));

    DECLARE @Total INT = (SELECT COUNT(*) FROM #Ids);

    SELECT vi.IssueId, vi.FacilityId, f.Name AS FacilityName, vi.EntityType, vi.EntityId, vi.IssueCode, vi.Severity,
           vi.ObservedValue, vi.Message, vi.Status, vi.DetectedAt, ru.DisplayName AS ResolvedByName, vi.ResolvedAt, vi.Resolution
    FROM dbo.ValidationIssues vi
    INNER JOIN #Ids i ON i.IssueId = vi.IssueId
    INNER JOIN dbo.Facilities f ON f.FacilityId = vi.FacilityId
    LEFT JOIN dbo.Users ru ON ru.UserId = vi.ResolvedBy
    ORDER BY CASE vi.Status WHEN N'Open' THEN 0 ELSE 1 END,
             CASE vi.Severity WHEN N'High' THEN 0 WHEN N'Medium' THEN 1 ELSE 2 END,
             vi.DetectedAt DESC, vi.IssueId DESC
    OFFSET (@Page - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT @Total AS TotalCount;
END
GO

/* POST data-quality/issues/{id}/resolve { resolution, dismiss } — returns the issue row. */
CREATE OR ALTER PROCEDURE dbo.usp_DataQuality_ResolveIssue
    @ActorUserId   INT,
    @IssueId       INT,
    @Resolution    NVARCHAR(500) = NULL,
    @Dismiss       BIT = 0,
    @CorrelationId NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'dataquality.view') = 0
        THROW 50403, N'You do not have permission to manage data quality issues.', 1;

    SET @Resolution = NULLIF(LTRIM(RTRIM(@Resolution)), N'');
    DECLARE @FacilityId INT, @Status NVARCHAR(20), @EntityType NVARCHAR(50), @EntityId INT, @Code NVARCHAR(20), @Message NVARCHAR(500);
    SELECT @FacilityId = FacilityId, @Status = Status, @EntityType = EntityType, @EntityId = EntityId, @Code = IssueCode, @Message = Message
    FROM dbo.ValidationIssues WHERE IssueId = @IssueId;

    IF @FacilityId IS NULL
        THROW 50404, N'Issue not found.', 1;
    IF dbo.fn_UserCanAccessFacility(@ActorUserId, @FacilityId) = 0
        THROW 50403, N'You are not assigned to this facility.', 1;
    IF @Status <> N'Open'
        THROW 50409, N'This issue is no longer open.', 1;
    IF @Resolution IS NULL
        THROW 50400, N'A resolution note is required.', 1;
    IF @EntityType = N'InventoryChange' AND EXISTS (SELECT 1 FROM dbo.InventoryChanges WHERE ChangeId = @EntityId AND Status = N'PendingReview')
        THROW 50409, N'Approve or reject the related inventory change instead.', 1;

    DECLARE @NewStatus NVARCHAR(20) = CASE WHEN ISNULL(@Dismiss, 0) = 1 THEN N'Dismissed' ELSE N'Resolved' END;
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

    BEGIN TRANSACTION;
    BEGIN TRY
        UPDATE dbo.ValidationIssues
        SET Status = @NewStatus, ResolvedBy = @ActorUserId, ResolvedAt = @Now, Resolution = @Resolution
        WHERE IssueId = @IssueId AND Status = N'Open';
        IF @@ROWCOUNT = 0
            THROW 50409, N'This issue is no longer open.', 1;

        DECLARE @IdText NVARCHAR(50) = CAST(@IssueId AS NVARCHAR(50));
        DECLARE @Desc NVARCHAR(1000) = CONCAT(@Code, N' issue ', LOWER(@NewStatus), N': ', @Message);
        DECLARE @NewVals NVARCHAR(MAX) = (SELECT @NewStatus AS Status, @Resolution AS Resolution FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        DECLARE @Action NVARCHAR(50) = CASE @NewStatus WHEN N'Dismissed' THEN N'Dismissed' ELSE N'Resolved' END;
        EXEC dbo.usp_Audit_Write @ActorUserId = @ActorUserId, @EntityType = N'ValidationIssue', @EntityId = @IdText,
             @FacilityId = @FacilityId, @Action = @Action, @Description = @Desc, @OldValues = N'{"Status":"Open"}',
             @NewValues = @NewVals, @Reason = @Resolution, @CorrelationId = @CorrelationId;

        DECLARE @Msg NVARCHAR(1000) = CONCAT(@Code, N' issue #', @IssueId, N' was ', LOWER(@NewStatus), N'.');
        EXEC dbo.usp_Notification_NotifyFacilityUsers @ActorUserId = @ActorUserId, @FacilityId = @FacilityId,
             @Title = N'Data quality issue closed', @Message = @Msg, @Type = N'Info', @EntityType = N'ValidationIssue',
             @EntityId = @IdText, @Route = N'/data-quality', @AssignmentRoles = N'Manager';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT vi.IssueId, vi.FacilityId, f.Name AS FacilityName, vi.EntityType, vi.EntityId, vi.IssueCode, vi.Severity,
           vi.ObservedValue, vi.Message, vi.Status, vi.DetectedAt, ru.DisplayName AS ResolvedByName, vi.ResolvedAt, vi.Resolution
    FROM dbo.ValidationIssues vi
    INNER JOIN dbo.Facilities f ON f.FacilityId = vi.FacilityId
    LEFT JOIN dbo.Users ru ON ru.UserId = vi.ResolvedBy
    WHERE vi.IssueId = @IssueId;
END
GO

/*
  POST data-quality/scan { facilityId? } — on-demand scan of accessible active facilities:
  STALE (ValidUntil passed), EXPIRING (blood with stock expiring within EXPIRING_WITHIN_DAYS), MISSING_FIELD
  (never reported / blood stock without expiry / resource status Unknown), NEGATIVE (negative or available > total),
  DUPLICATE (identical applied changes for the same item within 2 minutes). Creates missing open issues and
  auto-resolves STALE/EXPIRING/MISSING_FIELD issues whose condition cleared.
  Returns { StaleFound, ExpiringFound, MissingFound, NegativeFound, DuplicateFound, IssuesCreated, IssuesResolved }.
*/
CREATE OR ALTER PROCEDURE dbo.usp_DataQuality_Scan
    @ActorUserId   INT,
    @FacilityId    INT = NULL,
    @CorrelationId NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'dataquality.view') = 0
        THROW 50403, N'You do not have permission to run data quality scans.', 1;
    IF @FacilityId IS NOT NULL
        EXEC dbo.usp_Inventory_AssertFacility @ActorUserId = @ActorUserId, @FacilityId = @FacilityId;

    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @ExpDays INT = dbo.fn_GetSettingInt(N'EXPIRING_WITHIN_DAYS', 3);
    DECLARE @ExpLimit DATE = DATEADD(DAY, @ExpDays, CAST(@Now AS DATE));
    DECLARE @ViewAll BIT = dbo.fn_UserHasPermission(@ActorUserId, N'data.viewall');

    DECLARE @Fac TABLE (FacilityId INT PRIMARY KEY);
    INSERT INTO @Fac (FacilityId)
    SELECT f.FacilityId FROM dbo.Facilities f
    WHERE f.IsActive = 1
      AND (@FacilityId IS NULL OR f.FacilityId = @FacilityId)
      AND (@ViewAll = 1 OR EXISTS (SELECT 1 FROM dbo.FacilityUserAssignments fa
                                   WHERE fa.FacilityId = f.FacilityId AND fa.UserId = @ActorUserId AND fa.IsActive = 1));

    DECLARE @Found TABLE (FacilityId INT, EntityType NVARCHAR(50), EntityId INT, IssueCode NVARCHAR(20), Severity NVARCHAR(10),
                          ObservedValue NVARCHAR(200), Message NVARCHAR(500));

    -- STALE
    INSERT INTO @Found
    SELECT b.FacilityId, N'BloodInventory', b.InventoryId, N'STALE', CASE WHEN b.ValidUntil < DATEADD(HOUR, -24, @Now) THEN N'High' ELSE N'Medium' END,
           CONVERT(NVARCHAR(30), b.ValidUntil, 126),
           CONCAT(bc.Code, N' ', b.AboGroup, CASE b.RhFactor WHEN N'Positive' THEN N'+' ELSE N'-' END, N' stock is stale (valid until ', CONVERT(NVARCHAR(16), b.ValidUntil, 120), N' UTC).')
    FROM dbo.BloodInventory b INNER JOIN @Fac x ON x.FacilityId = b.FacilityId
    INNER JOIN dbo.BloodComponents bc ON bc.ComponentId = b.ComponentId
    WHERE b.LastUpdatedAt IS NOT NULL AND b.ValidUntil < @Now AND b.VerificationStatus <> N'PendingReview';
    INSERT INTO @Found
    SELECT m.FacilityId, N'ResourceInventory', m.ResourceInventoryId, N'STALE', CASE WHEN m.ValidUntil < DATEADD(HOUR, -24, @Now) THEN N'High' ELSE N'Medium' END,
           CONVERT(NVARCHAR(30), m.ValidUntil, 126),
           CONCAT(rt.Name, N' availability is stale (valid until ', CONVERT(NVARCHAR(16), m.ValidUntil, 120), N' UTC).')
    FROM dbo.MedicalResourceInventory m INNER JOIN @Fac x ON x.FacilityId = m.FacilityId
    INNER JOIN dbo.MedicalResourceTypes rt ON rt.ResourceTypeId = m.ResourceTypeId
    WHERE m.LastUpdatedAt IS NOT NULL AND m.ValidUntil < @Now AND m.VerificationStatus <> N'PendingReview';

    -- EXPIRING
    INSERT INTO @Found
    SELECT b.FacilityId, N'BloodInventory', b.InventoryId, N'EXPIRING', CASE WHEN b.EarliestExpiryDate <= CAST(@Now AS DATE) THEN N'High' ELSE N'Medium' END,
           CONVERT(NVARCHAR(10), b.EarliestExpiryDate, 23),
           CONCAT(bc.Code, N' ', b.AboGroup, CASE b.RhFactor WHEN N'Positive' THEN N'+' ELSE N'-' END, N': ', CAST(b.Quantity AS NVARCHAR(20)),
                  N' unit(s) with earliest expiry ', CONVERT(NVARCHAR(10), b.EarliestExpiryDate, 23), N'.')
    FROM dbo.BloodInventory b INNER JOIN @Fac x ON x.FacilityId = b.FacilityId
    INNER JOIN dbo.BloodComponents bc ON bc.ComponentId = b.ComponentId
    WHERE b.Quantity > 0 AND b.EarliestExpiryDate IS NOT NULL AND b.EarliestExpiryDate <= @ExpLimit;

    -- MISSING_FIELD
    INSERT INTO @Found
    SELECT b.FacilityId, N'BloodInventory', b.InventoryId, N'MISSING_FIELD', N'Low',
           CASE WHEN b.LastUpdatedAt IS NULL THEN N'LastUpdatedAt' ELSE N'EarliestExpiryDate' END,
           CONCAT(bc.Code, N' ', b.AboGroup, CASE b.RhFactor WHEN N'Positive' THEN N'+' ELSE N'-' END,
                  CASE WHEN b.LastUpdatedAt IS NULL THEN N' has never been reported by this facility.' ELSE N' stock has no earliest expiry date.' END)
    FROM dbo.BloodInventory b INNER JOIN @Fac x ON x.FacilityId = b.FacilityId
    INNER JOIN dbo.BloodComponents bc ON bc.ComponentId = b.ComponentId
    WHERE b.VerificationStatus <> N'PendingReview'
      AND (b.LastUpdatedAt IS NULL OR (b.Quantity > 0 AND b.EarliestExpiryDate IS NULL));
    INSERT INTO @Found
    SELECT m.FacilityId, N'ResourceInventory', m.ResourceInventoryId, N'MISSING_FIELD', N'Low',
           CASE WHEN m.LastUpdatedAt IS NULL THEN N'LastUpdatedAt' ELSE N'OperationalStatus' END,
           CONCAT(rt.Name, CASE WHEN m.LastUpdatedAt IS NULL THEN N' has never been reported by this facility.' ELSE N' has an Unknown operational status.' END)
    FROM dbo.MedicalResourceInventory m INNER JOIN @Fac x ON x.FacilityId = m.FacilityId
    INNER JOIN dbo.MedicalResourceTypes rt ON rt.ResourceTypeId = m.ResourceTypeId
    WHERE m.VerificationStatus <> N'PendingReview' AND (m.LastUpdatedAt IS NULL OR m.OperationalStatus = N'Unknown');

    -- NEGATIVE (defensive; constraints normally prevent it)
    INSERT INTO @Found
    SELECT b.FacilityId, N'BloodInventory', b.InventoryId, N'NEGATIVE', N'High', CAST(b.Quantity AS NVARCHAR(30)), N'Negative blood stock quantity.'
    FROM dbo.BloodInventory b INNER JOIN @Fac x ON x.FacilityId = b.FacilityId
    WHERE b.Quantity < 0;
    INSERT INTO @Found
    SELECT m.FacilityId, N'ResourceInventory', m.ResourceInventoryId, N'NEGATIVE', N'High',
           CONCAT(CAST(m.AvailableQuantity AS NVARCHAR(30)), N'/', CAST(m.TotalQuantity AS NVARCHAR(30))),
           N'Negative quantity or available exceeds total.'
    FROM dbo.MedicalResourceInventory m INNER JOIN @Fac x ON x.FacilityId = m.FacilityId
    WHERE m.AvailableQuantity < 0 OR m.TotalQuantity < 0 OR m.AvailableQuantity > m.TotalQuantity;

    -- DUPLICATE: applied change repeating an earlier applied change for the same item within 2 minutes (last 7 days)
    INSERT INTO @Found
    SELECT c.FacilityId, N'InventoryChange', c.ChangeId, N'DUPLICATE', N'Low', c.ChangeNo,
           CONCAT(N'Change ', c.ChangeNo, N' repeats ', p.ChangeNo, N' within 2 minutes.')
    FROM dbo.InventoryChanges c INNER JOIN @Fac x ON x.FacilityId = c.FacilityId
    CROSS APPLY (SELECT TOP (1) p.ChangeNo FROM dbo.InventoryChanges p
                 WHERE p.FacilityId = c.FacilityId AND p.InventoryKind = c.InventoryKind AND p.ChangeId < c.ChangeId
                   AND p.Status = N'Applied'
                   AND ISNULL(p.ComponentId, -1) = ISNULL(c.ComponentId, -1) AND ISNULL(p.AboGroup, N'') = ISNULL(c.AboGroup, N'')
                   AND ISNULL(p.RhFactor, N'') = ISNULL(c.RhFactor, N'') AND ISNULL(p.ResourceTypeId, -1) = ISNULL(c.ResourceTypeId, -1)
                   AND ISNULL(p.ProposedQuantity, -1) = ISNULL(c.ProposedQuantity, -1)
                   AND ISNULL(p.ProposedAvailable, -1) = ISNULL(c.ProposedAvailable, -1)
                   AND ISNULL(p.ProposedTotal, -1) = ISNULL(c.ProposedTotal, -1)
                   AND p.SubmittedAt >= DATEADD(MINUTE, -2, c.SubmittedAt)
                 ORDER BY p.ChangeId DESC) p
    WHERE c.Status = N'Applied' AND c.SubmittedAt >= DATEADD(DAY, -7, @Now);

    DECLARE @Created INT = 0, @Resolved INT = 0;

    BEGIN TRANSACTION;
    BEGIN TRY
        INSERT INTO dbo.ValidationIssues (FacilityId, EntityType, EntityId, IssueCode, Severity, ObservedValue, Message, Status, DetectedAt)
        SELECT fd.FacilityId, fd.EntityType, fd.EntityId, fd.IssueCode, fd.Severity, fd.ObservedValue, fd.Message, N'Open', @Now
        FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY EntityType, EntityId, IssueCode ORDER BY Severity) AS rn FROM @Found) fd
        WHERE fd.rn = 1
          AND NOT EXISTS (SELECT 1 FROM dbo.ValidationIssues vi WITH (UPDLOCK, HOLDLOCK)
                          WHERE vi.EntityType = fd.EntityType AND vi.EntityId = fd.EntityId AND vi.IssueCode = fd.IssueCode AND vi.Status = N'Open');
        SET @Created = @@ROWCOUNT;

        UPDATE vi
        SET Status = N'Resolved', ResolvedBy = @ActorUserId, ResolvedAt = @Now, Resolution = N'Condition cleared (data-quality scan).'
        FROM dbo.ValidationIssues vi
        INNER JOIN @Fac x ON x.FacilityId = vi.FacilityId
        WHERE vi.Status = N'Open' AND vi.IssueCode IN (N'STALE', N'EXPIRING', N'MISSING_FIELD')
          AND vi.EntityType IN (N'BloodInventory', N'ResourceInventory')
          AND NOT EXISTS (SELECT 1 FROM @Found fd WHERE fd.EntityType = vi.EntityType AND fd.EntityId = vi.EntityId AND fd.IssueCode = vi.IssueCode);
        SET @Resolved = @@ROWCOUNT;

        DECLARE @Summary NVARCHAR(MAX) = (SELECT
                (SELECT COUNT(*) FROM @Found WHERE IssueCode = N'STALE') AS StaleFound,
                (SELECT COUNT(*) FROM @Found WHERE IssueCode = N'EXPIRING') AS ExpiringFound,
                (SELECT COUNT(*) FROM @Found WHERE IssueCode = N'MISSING_FIELD') AS MissingFound,
                @Created AS IssuesCreated, @Resolved AS IssuesResolved, @FacilityId AS FacilityId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        DECLARE @EntityIdText NVARCHAR(50) = ISNULL(CAST(@FacilityId AS NVARCHAR(50)), N'ALL');
        DECLARE @Desc NVARCHAR(1000) = CONCAT(N'Data-quality scan: ', @Created, N' issue(s) created, ', @Resolved, N' auto-resolved.');
        EXEC dbo.usp_Audit_Write @ActorUserId = @ActorUserId, @EntityType = N'DataQualityScan', @EntityId = @EntityIdText,
             @FacilityId = @FacilityId, @Action = N'Scan', @Description = @Desc, @NewValues = @Summary, @CorrelationId = @CorrelationId;

        IF @Created > 0
        BEGIN
            DECLARE @Msg NVARCHAR(1000) = CONCAT(N'The data-quality scan found ', @Created, N' new issue(s).');
            EXEC dbo.usp_Notification_Create @ActorUserId = @ActorUserId, @UserId = @ActorUserId, @Title = N'Data-quality scan completed',
                 @Message = @Msg, @Type = N'Warning', @EntityType = N'DataQualityScan', @EntityId = @EntityIdText, @Route = N'/data-quality';
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT (SELECT COUNT(*) FROM @Found WHERE IssueCode = N'STALE') AS StaleFound,
           (SELECT COUNT(*) FROM @Found WHERE IssueCode = N'EXPIRING') AS ExpiringFound,
           (SELECT COUNT(*) FROM @Found WHERE IssueCode = N'MISSING_FIELD') AS MissingFound,
           (SELECT COUNT(*) FROM @Found WHERE IssueCode = N'NEGATIVE') AS NegativeFound,
           (SELECT COUNT(*) FROM @Found WHERE IssueCode = N'DUPLICATE') AS DuplicateFound,
           @Created AS IssuesCreated, @Resolved AS IssuesResolved;
END
GO
