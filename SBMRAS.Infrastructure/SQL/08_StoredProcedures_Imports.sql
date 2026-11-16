/*=====================================================================
  SBMRAS - 08_StoredProcedures_Imports.sql
  Bulk inventory import (browser parses CSV, API posts JSON rows). Contract §4.4 / §6.
  Idempotent (CREATE OR ALTER). Requires 01, 02, 04 and 05 (shared inventory helpers).

  Public SPs:
    usp_Import_Search   (@ActorUserId, @FacilityId, @Status, @Page, @PageSize)            -> rows, TotalCount
    usp_Import_GetById  (@ActorUserId, @BatchId)                                            -> batch, rows
    usp_Import_Stage    (@ActorUserId, @FacilityId, @InventoryKind, @FileName, @FileHash,
                         @RowsJson, @CorrelationId)                                         -> batch, rows
    usp_Import_Commit   (@ActorUserId, @BatchId, @IdempotencyKey, @CorrelationId)          -> batch, rows
    usp_Import_Cancel   (@ActorUserId, @BatchId, @Reason, @CorrelationId)                  -> batch, rows
  Private helpers:
    usp_Import_AssertBatchAccess, usp_Import_ValidateRows, usp_Import_RefreshCounts

  Row ErrorCodes are comma separated, ErrorMessages ';' separated. Valid/Review rows may carry
  warning codes (UNCHANGED, EXPIRING, LARGE_JUMP) that do not block commit.
  Commit applies every Valid/Review row through usp_Inventory_RecordBloodChange /
  usp_Inventory_RecordResourceChange (same anomaly/PendingReview/InventoryChanges/snapshot/audit
  logic as single updates), SourceType 'CSVImport', linked by ImportBatchId.
=====================================================================*/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* Batch exists (50404), actor has inventory.import (50403) and facility scope (50403). */
CREATE OR ALTER PROCEDURE dbo.usp_Import_AssertBatchAccess
    @ActorUserId INT,
    @BatchId     INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'inventory.import') = 0
        THROW 50403, N'You do not have permission to manage inventory imports.', 1;

    DECLARE @FacilityId INT = (SELECT FacilityId FROM dbo.ImportBatches WHERE BatchId = @BatchId);
    IF @FacilityId IS NULL
        THROW 50404, N'Import batch not found.', 1;
    IF dbo.fn_UserCanAccessFacility(@ActorUserId, @FacilityId) = 0
        THROW 50403, N'You are not assigned to this facility.', 1;
END
GO

/* Recomputes batch counters from row statuses. ValidRows = rows that passed validation (incl. Review/Applied). */
CREATE OR ALTER PROCEDURE dbo.usp_Import_RefreshCounts
    @BatchId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    UPDATE b
    SET TotalRows     = x.TotalRows,
        ValidRows     = x.ValidRows,
        InvalidRows   = x.InvalidRows,
        DuplicateRows = x.DuplicateRows,
        ReviewRows    = x.ReviewRows,
        AppliedRows   = x.AppliedRows
    FROM dbo.ImportBatches b
    CROSS APPLY (
        SELECT COUNT(*) AS TotalRows,
               SUM(CASE WHEN r.ValidationStatus IN (N'Valid', N'Review', N'Applied') THEN 1 ELSE 0 END) AS ValidRows,
               SUM(CASE WHEN r.ValidationStatus = N'Invalid' THEN 1 ELSE 0 END) AS InvalidRows,
               SUM(CASE WHEN r.ValidationStatus = N'Duplicate' THEN 1 ELSE 0 END) AS DuplicateRows,
               SUM(CASE WHEN r.ValidationStatus = N'Review' THEN 1 ELSE 0 END) AS ReviewRows,
               SUM(CASE WHEN r.ValidationStatus = N'Applied' THEN 1 ELSE 0 END) AS AppliedRows
        FROM dbo.ImportRows r WHERE r.BatchId = b.BatchId
    ) x
    WHERE b.BatchId = @BatchId;
END
GO

/*
  (Re)validates the rows of a batch against master data, ranges, duplicates within the batch and
  current inventory. Rows in Valid/Review/Duplicate are reset and fully re-evaluated.
  @IncludeInvalid = 1 (staging) also evaluates rows already Invalid because of parse errors and
  appends to their codes. Applied rows are never touched.
*/
CREATE OR ALTER PROCEDURE dbo.usp_Import_ValidateRows
    @BatchId        INT,
    @IncludeInvalid BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @Today DATE = CAST(@Now AS DATE);
    DECLARE @MaxValid DATETIME2(0) = DATEADD(DAY, 7, @Now);
    DECLARE @ExpiringDays INT = dbo.fn_GetSettingInt(N'EXPIRING_WITHIN_DAYS', 3);
    DECLARE @RequireReview BIT = dbo.fn_InventoryRequireReview();
    DECLARE @FacilityId INT, @Kind NVARCHAR(10);
    SELECT @FacilityId = FacilityId, @Kind = InventoryKind FROM dbo.ImportBatches WHERE BatchId = @BatchId;

    UPDATE dbo.ImportRows
    SET ValidationStatus = N'Valid', ErrorCodes = NULL, ErrorMessages = NULL
    WHERE BatchId = @BatchId AND ValidationStatus IN (N'Valid', N'Review', N'Duplicate');

    DECLARE @Target TABLE (ImportRowId INT PRIMARY KEY);
    INSERT INTO @Target (ImportRowId)
    SELECT ImportRowId FROM dbo.ImportRows
    WHERE BatchId = @BatchId
      AND (ValidationStatus = N'Valid' OR (ISNULL(@IncludeInvalid, 0) = 1 AND ValidationStatus = N'Invalid'));

    DECLARE @Issues TABLE (ImportRowId INT NOT NULL, Seq INT NOT NULL, Code NVARCHAR(40) NOT NULL, Msg NVARCHAR(300) NOT NULL);

    /* ---------- Static (blocking) rules ---------- */
    IF @Kind = N'Blood'
    BEGIN
        INSERT INTO @Issues (ImportRowId, Seq, Code, Msg)
        SELECT r.ImportRowId, v.Seq, v.Code, v.Msg
        FROM dbo.ImportRows r
        INNER JOIN @Target t ON t.ImportRowId = r.ImportRowId
        LEFT JOIN dbo.BloodComponents bc ON bc.Code = r.ComponentCode AND bc.IsActive = 1
        CROSS APPLY (VALUES
            (10, CASE WHEN r.ComponentCode IS NULL THEN N'MISSING_FIELD' END, N'Component code is required.'),
            (11, CASE WHEN r.AboGroup IS NULL THEN N'MISSING_FIELD' END, N'ABO group is required.'),
            (12, CASE WHEN r.RhFactor IS NULL THEN N'MISSING_FIELD' END, N'Rh factor is required.'),
            (13, CASE WHEN r.Quantity IS NULL AND ISNULL(r.ErrorCodes, N'') NOT LIKE N'%INVALID_QUANTITY%' THEN N'MISSING_FIELD' END, N'Quantity is required.'),
            (20, CASE WHEN r.ComponentCode IS NOT NULL AND bc.ComponentId IS NULL THEN N'UNKNOWN_COMPONENT' END,
                 N'Unknown component code ''' + ISNULL(r.ComponentCode, N'') + N'''.'),
            (21, CASE WHEN r.AboGroup IS NOT NULL AND r.AboGroup NOT IN (N'A', N'B', N'AB', N'O') THEN N'INVALID_ABO' END,
                 N'ABO group must be A, B, AB or O.'),
            (22, CASE WHEN r.RhFactor IS NOT NULL AND r.RhFactor NOT IN (N'Positive', N'Negative') THEN N'INVALID_RH' END,
                 N'Rh factor must be Positive or Negative.'),
            (30, CASE WHEN r.Quantity < 0 THEN N'NEGATIVE' END, N'Quantity must be zero or greater.'),
            (31, CASE WHEN r.Quantity > 100000 THEN N'OUT_OF_RANGE' END, N'Quantity is out of range.'),
            (40, CASE WHEN r.EarliestExpiryDate < @Today THEN N'EXPIRY_IN_PAST' END, N'Earliest expiry date cannot be in the past.'),
            (41, CASE WHEN r.ValidUntil IS NOT NULL AND (r.ValidUntil <= @Now OR r.ValidUntil > @MaxValid) THEN N'VALID_UNTIL_RANGE' END,
                 N'Valid until must be in the future and within 7 days.')
        ) v (Seq, Code, Msg)
        WHERE v.Code IS NOT NULL;
    END
    ELSE
    BEGIN
        INSERT INTO @Issues (ImportRowId, Seq, Code, Msg)
        SELECT r.ImportRowId, v.Seq, v.Code, v.Msg
        FROM dbo.ImportRows r
        INNER JOIN @Target t ON t.ImportRowId = r.ImportRowId
        LEFT JOIN dbo.MedicalResourceTypes rt ON rt.Code = r.ResourceTypeCode AND rt.IsActive = 1
        CROSS APPLY (VALUES
            (10, CASE WHEN r.ResourceTypeCode IS NULL THEN N'MISSING_FIELD' END, N'Resource type code is required.'),
            (11, CASE WHEN r.TotalQuantity IS NULL AND ISNULL(r.ErrorCodes, N'') NOT LIKE N'%INVALID_TOTAL%' THEN N'MISSING_FIELD' END, N'Total quantity is required.'),
            (12, CASE WHEN r.AvailableQuantity IS NULL AND ISNULL(r.ErrorCodes, N'') NOT LIKE N'%INVALID_AVAILABLE%' THEN N'MISSING_FIELD' END, N'Available quantity is required.'),
            (13, CASE WHEN r.OperationalStatus IS NULL THEN N'MISSING_FIELD' END, N'Operational status is required.'),
            (20, CASE WHEN r.ResourceTypeCode IS NOT NULL AND rt.ResourceTypeId IS NULL THEN N'UNKNOWN_RESOURCE_TYPE' END,
                 N'Unknown resource type code ''' + ISNULL(r.ResourceTypeCode, N'') + N'''.'),
            (21, CASE WHEN r.OperationalStatus IS NOT NULL AND r.OperationalStatus NOT IN (N'Available', N'Limited', N'Unavailable', N'Unknown') THEN N'INVALID_STATUS' END,
                 N'Operational status must be Available, Limited, Unavailable or Unknown.'),
            (30, CASE WHEN r.TotalQuantity < 0 OR r.AvailableQuantity < 0 THEN N'NEGATIVE' END, N'Quantities must be zero or greater.'),
            (31, CASE WHEN r.TotalQuantity > 100000 OR r.AvailableQuantity > 100000 THEN N'OUT_OF_RANGE' END, N'Quantity is out of range.'),
            (32, CASE WHEN r.AvailableQuantity > r.TotalQuantity THEN N'AVAILABLE_GT_TOTAL' END, N'Available quantity cannot exceed total quantity.'),
            (41, CASE WHEN r.ValidUntil IS NOT NULL AND (r.ValidUntil <= @Now OR r.ValidUntil > @MaxValid) THEN N'VALID_UNTIL_RANGE' END,
                 N'Valid until must be in the future and within 7 days.')
        ) v (Seq, Code, Msg)
        WHERE v.Code IS NOT NULL;
    END

    UPDATE r
    SET ValidationStatus = N'Invalid',
        ErrorCodes = LEFT(CONCAT_WS(N',', r.ErrorCodes, a.Codes), 400),
        ErrorMessages = LEFT(CONCAT_WS(N';', r.ErrorMessages, a.Msgs), 1000)
    FROM dbo.ImportRows r
    INNER JOIN (
        SELECT ImportRowId,
               STRING_AGG(Code, N',') WITHIN GROUP (ORDER BY Seq) AS Codes,
               STRING_AGG(CAST(Msg AS NVARCHAR(MAX)), N';') WITHIN GROUP (ORDER BY Seq) AS Msgs
        FROM @Issues GROUP BY ImportRowId
    ) a ON a.ImportRowId = r.ImportRowId;

    /* ---------- Rows still Valid: resolve keys against master + current inventory ---------- */
    DECLARE @Cand TABLE (
        ImportRowId INT PRIMARY KEY, RowNumber INT, ItemKey NVARCHAR(60), Label NVARCHAR(150),
        InventoryId INT NULL, OriginalRowVersion VARBINARY(8) NULL, LastUpdatedAt DATETIME2(0) NULL,
        OldQty DECIMAL(12,2) NULL, OldTotal DECIMAL(12,2) NULL, OldAvail DECIMAL(12,2) NULL, OldStatus NVARCHAR(20) NULL,
        OldExpiry DATE NULL, HasPending BIT NOT NULL DEFAULT 0,
        Qty DECIMAL(12,2) NULL, Total DECIMAL(12,2) NULL, Avail DECIMAL(12,2) NULL, OpStatus NVARCHAR(20) NULL, Expiry DATE NULL);

    IF @Kind = N'Blood'
        INSERT INTO @Cand (ImportRowId, RowNumber, ItemKey, Label, InventoryId, OriginalRowVersion, LastUpdatedAt,
                           OldQty, OldExpiry, HasPending, Qty, Expiry)
        SELECT r.ImportRowId, r.RowNumber,
               CONCAT(bc.ComponentId, N'|', r.AboGroup, N'|', r.RhFactor),
               CONCAT(bc.Code, N' ', r.AboGroup, CASE r.RhFactor WHEN N'Positive' THEN N'+' ELSE N'-' END),
               bi.InventoryId, CAST(bi.RowVer AS VARBINARY(8)), bi.LastUpdatedAt, bi.Quantity, bi.EarliestExpiryDate,
               CASE WHEN EXISTS (SELECT 1 FROM dbo.InventoryChanges ic WHERE ic.Status = N'PendingReview' AND ic.FacilityId = @FacilityId
                                   AND ic.InventoryKind = N'Blood' AND ic.ComponentId = bc.ComponentId
                                   AND ic.AboGroup = r.AboGroup AND ic.RhFactor = r.RhFactor) THEN 1 ELSE 0 END,
               r.Quantity, r.EarliestExpiryDate
        FROM dbo.ImportRows r
        INNER JOIN dbo.BloodComponents bc ON bc.Code = r.ComponentCode
        LEFT JOIN dbo.BloodInventory bi ON bi.FacilityId = @FacilityId AND bi.ComponentId = bc.ComponentId
                                       AND bi.AboGroup = r.AboGroup AND bi.RhFactor = r.RhFactor
        WHERE r.BatchId = @BatchId AND r.ValidationStatus = N'Valid';
    ELSE
        INSERT INTO @Cand (ImportRowId, RowNumber, ItemKey, Label, InventoryId, OriginalRowVersion, LastUpdatedAt,
                           OldTotal, OldAvail, OldStatus, HasPending, Total, Avail, OpStatus)
        SELECT r.ImportRowId, r.RowNumber, CAST(rt.ResourceTypeId AS NVARCHAR(20)), rt.Code,
               mi.ResourceInventoryId, CAST(mi.RowVer AS VARBINARY(8)), mi.LastUpdatedAt,
               mi.TotalQuantity, mi.AvailableQuantity, mi.OperationalStatus,
               CASE WHEN EXISTS (SELECT 1 FROM dbo.InventoryChanges ic WHERE ic.Status = N'PendingReview' AND ic.FacilityId = @FacilityId
                                   AND ic.InventoryKind = N'Resource' AND ic.ResourceTypeId = rt.ResourceTypeId) THEN 1 ELSE 0 END,
               r.TotalQuantity, r.AvailableQuantity, r.OperationalStatus
        FROM dbo.ImportRows r
        INNER JOIN dbo.MedicalResourceTypes rt ON rt.Code = r.ResourceTypeCode
        LEFT JOIN dbo.MedicalResourceInventory mi ON mi.FacilityId = @FacilityId AND mi.ResourceTypeId = rt.ResourceTypeId
        WHERE r.BatchId = @BatchId AND r.ValidationStatus = N'Valid';

    UPDATE r
    SET OriginalRowVersion = c.OriginalRowVersion
    FROM dbo.ImportRows r
    INNER JOIN @Cand c ON c.ImportRowId = r.ImportRowId;

    /* Duplicates within the batch: first occurrence wins. */
    ;WITH d AS (
        SELECT c.ImportRowId, c.Label,
               ROW_NUMBER() OVER (PARTITION BY c.ItemKey ORDER BY c.RowNumber) AS Rn,
               FIRST_VALUE(c.RowNumber) OVER (PARTITION BY c.ItemKey ORDER BY c.RowNumber) AS FirstRow
        FROM @Cand c
    )
    UPDATE r
    SET ValidationStatus = N'Duplicate', ErrorCodes = N'DUPLICATE',
        ErrorMessages = CONCAT(N'Row duplicates row ', d.FirstRow, N' (', d.Label, N').')
    FROM dbo.ImportRows r INNER JOIN d ON d.ImportRowId = r.ImportRowId
    WHERE d.Rn > 1;
    DELETE c FROM @Cand c INNER JOIN dbo.ImportRows r ON r.ImportRowId = c.ImportRowId WHERE r.ValidationStatus = N'Duplicate';

    /* Conflict with a change already awaiting review for the same record. */
    UPDATE r
    SET ValidationStatus = N'Invalid', ErrorCodes = N'PENDING_REVIEW',
        ErrorMessages = CONCAT(N'Another change for ', c.Label, N' is awaiting review.')
    FROM dbo.ImportRows r INNER JOIN @Cand c ON c.ImportRowId = r.ImportRowId
    WHERE c.HasPending = 1;
    DELETE FROM @Cand WHERE HasPending = 1;

    /* Anomaly (same rule as single updates) -> Review; warnings on remaining rows. */
    UPDATE r
    SET ValidationStatus = CASE WHEN w.IsJump = 1 AND @RequireReview = 1 THEN N'Review' ELSE N'Valid' END,
        ErrorCodes = NULLIF(CONCAT_WS(N',',
                        CASE WHEN w.IsJump = 1 THEN N'LARGE_JUMP' END,
                        CASE WHEN w.IsUnchanged = 1 THEN N'UNCHANGED' END,
                        CASE WHEN w.IsExpiring = 1 THEN N'EXPIRING' END), N''),
        ErrorMessages = NULLIF(CONCAT_WS(N';',
                        CASE WHEN w.IsJump = 1 THEN CONCAT(N'Large change for ', c.Label, N' (',
                             ISNULL(CAST(COALESCE(c.OldQty, c.OldAvail) AS NVARCHAR(30)), N'-'), N' -> ',
                             CAST(COALESCE(c.Qty, c.Avail) AS NVARCHAR(30)), N')',
                             CASE WHEN @RequireReview = 1 THEN N' will require verification.' ELSE N'.' END) END,
                        CASE WHEN w.IsUnchanged = 1 THEN N'Values are unchanged from current inventory (will re-confirm).' END,
                        CASE WHEN w.IsExpiring = 1 THEN CONCAT(N'Stock expires within ', @ExpiringDays, N' days.') END), N'')
    FROM dbo.ImportRows r
    INNER JOIN @Cand c ON c.ImportRowId = r.ImportRowId
    CROSS APPLY (
        SELECT CASE WHEN c.LastUpdatedAt IS NOT NULL AND
                         ((@Kind = N'Blood' AND dbo.fn_IsLargeJump(c.OldQty, c.Qty) = 1)
                       OR (@Kind = N'Resource' AND (dbo.fn_IsLargeJump(c.OldAvail, c.Avail) = 1 OR dbo.fn_IsLargeJump(c.OldTotal, c.Total) = 1)))
                    THEN 1 ELSE 0 END AS IsJump,
               CASE WHEN c.InventoryId IS NOT NULL AND
                         ((@Kind = N'Blood' AND c.OldQty = c.Qty AND ISNULL(c.OldExpiry, '19000101') = ISNULL(c.Expiry, '19000101'))
                       OR (@Kind = N'Resource' AND c.OldTotal = c.Total AND c.OldAvail = c.Avail AND c.OldStatus = c.OpStatus))
                    THEN 1 ELSE 0 END AS IsUnchanged,
               CASE WHEN @Kind = N'Blood' AND c.Expiry IS NOT NULL AND c.Expiry <= DATEADD(DAY, @ExpiringDays, @Today) THEN 1 ELSE 0 END AS IsExpiring
    ) w;

    EXEC dbo.usp_Import_RefreshCounts @BatchId = @BatchId;
END
GO

/* GET imports/{id} -> (1) ImportBatch, (2) ImportRow[] */
CREATE OR ALTER PROCEDURE dbo.usp_Import_GetById
    @ActorUserId INT,
    @BatchId     INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC dbo.usp_Import_AssertBatchAccess @ActorUserId = @ActorUserId, @BatchId = @BatchId;

    SELECT b.BatchId, b.BatchNo, b.FacilityId, f.Name AS FacilityName, f.FacilityCode, b.InventoryKind, b.FileName, b.FileHash,
           b.TotalRows, b.ValidRows, b.InvalidRows, b.DuplicateRows, b.ReviewRows, b.AppliedRows, b.Status,
           b.SubmittedBy, su.DisplayName AS SubmittedByName, b.SubmittedAt,
           b.CommittedBy, cu.DisplayName AS CommittedByName, b.CommittedAt
    FROM dbo.ImportBatches b
    INNER JOIN dbo.Facilities f ON f.FacilityId = b.FacilityId
    LEFT JOIN dbo.Users su ON su.UserId = b.SubmittedBy
    LEFT JOIN dbo.Users cu ON cu.UserId = b.CommittedBy
    WHERE b.BatchId = @BatchId;

    SELECT r.ImportRowId, r.RowNumber, r.RawData, r.ComponentCode, r.AboGroup, r.RhFactor, r.ResourceTypeCode,
           r.Quantity, r.TotalQuantity, r.AvailableQuantity, r.OperationalStatus, r.EarliestExpiryDate, r.ValidUntil,
           r.ValidationStatus, r.ErrorCodes, r.ErrorMessages
    FROM dbo.ImportRows r
    WHERE r.BatchId = @BatchId
    ORDER BY r.RowNumber;
END
GO

/* GET imports?facilityId&status&page&pageSize -> Paged<ImportBatch> (rows, TotalCount). Scoped to accessible facilities. */
CREATE OR ALTER PROCEDURE dbo.usp_Import_Search
    @ActorUserId INT,
    @FacilityId  INT = NULL,
    @Status      NVARCHAR(20) = NULL,
    @Page        INT = 1,
    @PageSize    INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'inventory.import') = 0
        THROW 50403, N'You do not have permission to manage inventory imports.', 1;

    SET @Page = CASE WHEN ISNULL(@Page, 1) < 1 THEN 1 ELSE @Page END;
    SET @PageSize = CASE WHEN ISNULL(@PageSize, 20) < 1 THEN 20 WHEN @PageSize > 100 THEN 100 ELSE @PageSize END;
    SET @Status = NULLIF(LTRIM(RTRIM(@Status)), N'');
    IF @FacilityId = 0 SET @FacilityId = NULL;

    IF @FacilityId IS NOT NULL AND dbo.fn_UserCanAccessFacility(@ActorUserId, @FacilityId) = 0
        THROW 50403, N'You are not assigned to this facility.', 1;

    DECLARE @ViewAll BIT = dbo.fn_UserHasPermission(@ActorUserId, N'data.viewall');

    DECLARE @Ids TABLE (BatchId INT PRIMARY KEY, SubmittedAt DATETIME2(0));
    INSERT INTO @Ids (BatchId, SubmittedAt)
    SELECT b.BatchId, b.SubmittedAt
    FROM dbo.ImportBatches b
    WHERE (@FacilityId IS NULL OR b.FacilityId = @FacilityId)
      AND (@Status IS NULL OR b.Status = @Status)
      AND (@ViewAll = 1 OR EXISTS (SELECT 1 FROM dbo.FacilityUserAssignments a
                                   WHERE a.FacilityId = b.FacilityId AND a.UserId = @ActorUserId AND a.IsActive = 1));

    DECLARE @Total INT = (SELECT COUNT(*) FROM @Ids);

    SELECT b.BatchId, b.BatchNo, b.FacilityId, f.Name AS FacilityName, f.FacilityCode, b.InventoryKind, b.FileName, b.FileHash,
           b.TotalRows, b.ValidRows, b.InvalidRows, b.DuplicateRows, b.ReviewRows, b.AppliedRows, b.Status,
           b.SubmittedBy, su.DisplayName AS SubmittedByName, b.SubmittedAt,
           b.CommittedBy, cu.DisplayName AS CommittedByName, b.CommittedAt
    FROM @Ids i
    INNER JOIN dbo.ImportBatches b ON b.BatchId = i.BatchId
    INNER JOIN dbo.Facilities f ON f.FacilityId = b.FacilityId
    LEFT JOIN dbo.Users su ON su.UserId = b.SubmittedBy
    LEFT JOIN dbo.Users cu ON cu.UserId = b.CommittedBy
    ORDER BY i.SubmittedAt DESC, i.BatchId DESC
    OFFSET (@Page - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT @Total AS TotalCount;
END
GO

/*
  POST imports -> stages + validates rows (status 'Validated'), returns batch detail (2 sets).
  @RowsJson = [{ rowNumber, rawData, componentCode, aboGroup, rhFactor, resourceTypeCode, quantity, totalQuantity,
                 availableQuantity, operationalStatus, earliestExpiryDate, validUntil }]
  The same file (FacilityId + FileHash) cannot be staged twice unless the earlier batch was cancelled (50409).
*/
CREATE OR ALTER PROCEDURE dbo.usp_Import_Stage
    @ActorUserId   INT,
    @FacilityId    INT,
    @InventoryKind NVARCHAR(10),
    @FileName      NVARCHAR(260),
    @FileHash      NVARCHAR(64),
    @RowsJson      NVARCHAR(MAX),
    @CorrelationId NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'inventory.import') = 0
        THROW 50403, N'You do not have permission to manage inventory imports.', 1;

    SET @InventoryKind = LTRIM(RTRIM(@InventoryKind));
    SET @FileName = NULLIF(LTRIM(RTRIM(@FileName)), N'');
    SET @FileHash = LOWER(NULLIF(LTRIM(RTRIM(@FileHash)), N''));

    IF @InventoryKind IS NULL OR @InventoryKind NOT IN (N'Blood', N'Resource')
        THROW 50400, N'Inventory kind must be Blood or Resource.', 1;
    IF @FileName IS NULL
        THROW 50400, N'File name is required.', 1;
    IF @FileHash IS NULL
        THROW 50400, N'File hash is required.', 1;

    EXEC dbo.usp_Inventory_AssertFacility @ActorUserId = @ActorUserId, @FacilityId = @FacilityId,
         @Kind = @InventoryKind, @RequireWritable = 1;

    IF @RowsJson IS NULL OR ISJSON(@RowsJson) = 0 OR LEFT(LTRIM(@RowsJson), 1) <> N'['
        THROW 50400, N'Rows must be a JSON array.', 1;

    DECLARE @MaxRows INT = dbo.fn_GetSettingInt(N'MAX_IMPORT_ROWS', 500);
    DECLARE @Count INT = (SELECT COUNT(*) FROM OPENJSON(@RowsJson));
    IF @Count = 0
        THROW 50400, N'The import file contains no data rows.', 1;
    IF @Count > @MaxRows
    BEGIN
        DECLARE @MaxMsg NVARCHAR(200) = CONCAT(N'The import file has ', @Count, N' rows; the maximum is ', @MaxRows, N'.');
        THROW 50400, @MaxMsg, 1;
    END

    DECLARE @Rows TABLE (
        RowNumber INT NOT NULL, RawData NVARCHAR(1000) NOT NULL,
        ComponentCode NVARCHAR(20) NULL, AboGroup NVARCHAR(2) NULL, RhFactor NVARCHAR(10) NULL, ResourceTypeCode NVARCHAR(30) NULL,
        Quantity DECIMAL(12,2) NULL, TotalQuantity DECIMAL(12,2) NULL, AvailableQuantity DECIMAL(12,2) NULL,
        OperationalStatus NVARCHAR(20) NULL, EarliestExpiryDate DATE NULL, ValidUntil DATETIME2(0) NULL,
        ErrorCodes NVARCHAR(400) NULL, ErrorMessages NVARCHAR(1000) NULL);

    ;WITH src AS (
        SELECT CAST(j.[key] AS INT) + 1 AS Ordinal, x.*
        FROM OPENJSON(@RowsJson) j
        CROSS APPLY OPENJSON(j.[value]) WITH (
            rowNumber          NVARCHAR(20)   '$.rowNumber',
            rawData            NVARCHAR(4000) '$.rawData',
            componentCode      NVARCHAR(100)  '$.componentCode',
            aboGroup           NVARCHAR(100)  '$.aboGroup',
            rhFactor           NVARCHAR(100)  '$.rhFactor',
            resourceTypeCode   NVARCHAR(100)  '$.resourceTypeCode',
            quantity           NVARCHAR(100)  '$.quantity',
            totalQuantity      NVARCHAR(100)  '$.totalQuantity',
            availableQuantity  NVARCHAR(100)  '$.availableQuantity',
            operationalStatus  NVARCHAR(100)  '$.operationalStatus',
            earliestExpiryDate NVARCHAR(100)  '$.earliestExpiryDate',
            validUntil         NVARCHAR(100)  '$.validUntil'
        ) x
    ), norm AS (
        SELECT COALESCE(TRY_CONVERT(INT, s.rowNumber), s.Ordinal) AS RowNumber,
               s.rawData,
               UPPER(NULLIF(LTRIM(RTRIM(s.componentCode)), N'')) AS ComponentCode,
               UPPER(NULLIF(LTRIM(RTRIM(s.aboGroup)), N'')) AS AboGroup,
               NULLIF(LTRIM(RTRIM(s.rhFactor)), N'') AS RhIn,
               UPPER(NULLIF(LTRIM(RTRIM(s.resourceTypeCode)), N'')) AS ResourceTypeCode,
               NULLIF(LTRIM(RTRIM(s.quantity)), N'') AS QtyIn,
               NULLIF(LTRIM(RTRIM(s.totalQuantity)), N'') AS TotalIn,
               NULLIF(LTRIM(RTRIM(s.availableQuantity)), N'') AS AvailIn,
               NULLIF(LTRIM(RTRIM(s.operationalStatus)), N'') AS StatusIn,
               NULLIF(LTRIM(RTRIM(s.earliestExpiryDate)), N'') AS ExpiryIn,
               NULLIF(LTRIM(RTRIM(s.validUntil)), N'') AS ValidIn
        FROM src s
    ), typed AS (
        SELECT n.*,
               TRY_CONVERT(DECIMAL(12,2), n.QtyIn) AS Qty,
               TRY_CONVERT(DECIMAL(12,2), n.TotalIn) AS Total,
               TRY_CONVERT(DECIMAL(12,2), n.AvailIn) AS Avail,
               TRY_CONVERT(DATE, n.ExpiryIn) AS Expiry,
               CAST(SWITCHOFFSET(TRY_CONVERT(DATETIMEOFFSET(0), n.ValidIn), N'+00:00') AS DATETIME2(0)) AS ValidUntil
        FROM norm n
    )
    INSERT INTO @Rows (RowNumber, RawData, ComponentCode, AboGroup, RhFactor, ResourceTypeCode, Quantity, TotalQuantity,
                       AvailableQuantity, OperationalStatus, EarliestExpiryDate, ValidUntil, ErrorCodes, ErrorMessages)
    SELECT t.RowNumber,
           LEFT(COALESCE(t.rawData, CONCAT_WS(N',', t.ComponentCode, t.AboGroup, t.RhIn, t.ResourceTypeCode, t.QtyIn, t.TotalIn,
                                               t.AvailIn, t.StatusIn, t.ExpiryIn, t.ValidIn), N''), 1000),
           CASE WHEN @InventoryKind = N'Blood' THEN LEFT(t.ComponentCode, 20) END,
           CASE WHEN @InventoryKind = N'Blood' THEN LEFT(t.AboGroup, 2) END,
           CASE WHEN @InventoryKind = N'Blood' THEN
               CASE WHEN t.RhIn IN (N'+', N'Positive', N'Pos', N'P') THEN N'Positive'
                    WHEN t.RhIn IN (N'-', N'Negative', N'Neg', N'N') THEN N'Negative'
                    ELSE LEFT(t.RhIn, 10) END END,
           CASE WHEN @InventoryKind = N'Resource' THEN LEFT(t.ResourceTypeCode, 30) END,
           CASE WHEN @InventoryKind = N'Blood' THEN t.Qty END,
           CASE WHEN @InventoryKind = N'Resource' THEN t.Total END,
           CASE WHEN @InventoryKind = N'Resource' THEN t.Avail END,
           CASE WHEN @InventoryKind = N'Resource' THEN
               COALESCE((SELECT v.S FROM (VALUES (N'Available'), (N'Limited'), (N'Unavailable'), (N'Unknown')) v (S) WHERE v.S = t.StatusIn),
                        LEFT(t.StatusIn, 20)) END,
           CASE WHEN @InventoryKind = N'Blood' THEN t.Expiry END,
           t.ValidUntil,
           NULLIF(CONCAT_WS(N',',
               CASE WHEN @InventoryKind = N'Blood' AND t.QtyIn IS NOT NULL AND t.Qty IS NULL THEN N'INVALID_QUANTITY' END,
               CASE WHEN @InventoryKind = N'Resource' AND t.TotalIn IS NOT NULL AND t.Total IS NULL THEN N'INVALID_TOTAL' END,
               CASE WHEN @InventoryKind = N'Resource' AND t.AvailIn IS NOT NULL AND t.Avail IS NULL THEN N'INVALID_AVAILABLE' END,
               CASE WHEN @InventoryKind = N'Blood' AND t.ExpiryIn IS NOT NULL AND t.Expiry IS NULL THEN N'INVALID_EXPIRY_DATE' END,
               CASE WHEN t.ValidIn IS NOT NULL AND t.ValidUntil IS NULL THEN N'INVALID_VALID_UNTIL' END,
               CASE WHEN @InventoryKind = N'Blood' AND LEN(t.ComponentCode) > 20 THEN N'UNKNOWN_COMPONENT' END,
               CASE WHEN @InventoryKind = N'Resource' AND LEN(t.ResourceTypeCode) > 30 THEN N'UNKNOWN_RESOURCE_TYPE' END), N''),
           NULLIF(CONCAT_WS(N';',
               CASE WHEN @InventoryKind = N'Blood' AND t.QtyIn IS NOT NULL AND t.Qty IS NULL THEN N'Quantity ''' + LEFT(t.QtyIn, 30) + N''' is not a number.' END,
               CASE WHEN @InventoryKind = N'Resource' AND t.TotalIn IS NOT NULL AND t.Total IS NULL THEN N'Total quantity ''' + LEFT(t.TotalIn, 30) + N''' is not a number.' END,
               CASE WHEN @InventoryKind = N'Resource' AND t.AvailIn IS NOT NULL AND t.Avail IS NULL THEN N'Available quantity ''' + LEFT(t.AvailIn, 30) + N''' is not a number.' END,
               CASE WHEN @InventoryKind = N'Blood' AND t.ExpiryIn IS NOT NULL AND t.Expiry IS NULL THEN N'Earliest expiry date ''' + LEFT(t.ExpiryIn, 30) + N''' is not a valid date (yyyy-MM-dd).' END,
               CASE WHEN t.ValidIn IS NOT NULL AND t.ValidUntil IS NULL THEN N'Valid until ''' + LEFT(t.ValidIn, 30) + N''' is not a valid date/time.' END,
               CASE WHEN @InventoryKind = N'Blood' AND LEN(t.ComponentCode) > 20 THEN N'Unknown component code.' END,
               CASE WHEN @InventoryKind = N'Resource' AND LEN(t.ResourceTypeCode) > 30 THEN N'Unknown resource type code.' END), N'')
    FROM typed t;

    IF EXISTS (SELECT RowNumber FROM @Rows GROUP BY RowNumber HAVING COUNT(*) > 1)
        THROW 50400, N'Row numbers must be unique within the import.', 1;
    IF EXISTS (SELECT 1 FROM @Rows WHERE RowNumber < 1)
        THROW 50400, N'Row numbers must be positive.', 1;

    DECLARE @BatchId INT, @BatchNo NVARCHAR(30), @Existing NVARCHAR(30);

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @Existing = BatchNo FROM dbo.ImportBatches WITH (UPDLOCK, HOLDLOCK)
        WHERE FacilityId = @FacilityId AND FileHash = @FileHash AND Status <> N'Cancelled';
        IF @Existing IS NOT NULL
        BEGIN
            DECLARE @DupMsg NVARCHAR(300) = CONCAT(N'This file has already been imported for this facility (', @Existing, N'). Cancel that batch to re-import it.');
            THROW 50409, @DupMsg, 1;
        END

        EXEC dbo.usp_Reference_Next @ActorUserId = @ActorUserId, @Prefix = N'IMP', @Next = @BatchNo OUTPUT;

        INSERT INTO dbo.ImportBatches (BatchNo, FacilityId, InventoryKind, FileName, FileHash, TotalRows, Status, SubmittedBy, SubmittedAt)
        VALUES (@BatchNo, @FacilityId, @InventoryKind, LEFT(@FileName, 260), LEFT(@FileHash, 64), @Count, N'Validated', @ActorUserId, SYSUTCDATETIME());
        SET @BatchId = SCOPE_IDENTITY();

        INSERT INTO dbo.ImportRows (BatchId, RowNumber, RawData, ComponentCode, AboGroup, RhFactor, ResourceTypeCode, Quantity,
                                    TotalQuantity, AvailableQuantity, OperationalStatus, EarliestExpiryDate, ValidUntil,
                                    ValidationStatus, ErrorCodes, ErrorMessages)
        SELECT @BatchId, RowNumber, RawData, ComponentCode, AboGroup, RhFactor, ResourceTypeCode, Quantity,
               TotalQuantity, AvailableQuantity, OperationalStatus, EarliestExpiryDate, ValidUntil,
               CASE WHEN ErrorCodes IS NULL THEN N'Valid' ELSE N'Invalid' END, ErrorCodes, ErrorMessages
        FROM @Rows;

        EXEC dbo.usp_Import_ValidateRows @BatchId = @BatchId, @IncludeInvalid = 1;

        DECLARE @EntityId NVARCHAR(50) = CAST(@BatchId AS NVARCHAR(50));
        DECLARE @NewValues NVARCHAR(MAX) = (SELECT BatchNo, InventoryKind, FileName, FileHash, TotalRows, ValidRows, InvalidRows,
                                                   DuplicateRows, ReviewRows, Status
                                            FROM dbo.ImportBatches WHERE BatchId = @BatchId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        DECLARE @Desc NVARCHAR(1000) = CONCAT(@InventoryKind, N' import ', @BatchNo, N' staged from ''', LEFT(@FileName, 200), N''' (', @Count, N' rows).');
        EXEC dbo.usp_Audit_Write @ActorUserId = @ActorUserId, @EntityType = N'ImportBatch', @EntityId = @EntityId,
             @ReferenceNo = @BatchNo, @FacilityId = @FacilityId, @Action = N'Staged', @Description = @Desc,
             @NewValues = @NewValues, @SourceType = N'CSVImport', @CorrelationId = @CorrelationId;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    EXEC dbo.usp_Import_GetById @ActorUserId = @ActorUserId, @BatchId = @BatchId;
END
GO

/*
  POST imports/{id}/commit -> re-validates rows against current inventory, then applies each Valid row
  and queues each Review row (PendingReview change) through the shared inventory recorders, atomically.
  Idempotent: an already committed batch is returned unchanged when @IdempotencyKey matches (or is not
  supplied); a different key, or a cancelled batch, -> 50409.
*/
CREATE OR ALTER PROCEDURE dbo.usp_Import_Commit
    @ActorUserId    INT,
    @BatchId        INT,
    @IdempotencyKey NVARCHAR(100) = NULL,
    @CorrelationId  NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @IdempotencyKey = NULLIF(LTRIM(RTRIM(@IdempotencyKey)), N'');

    EXEC dbo.usp_Import_AssertBatchAccess @ActorUserId = @ActorUserId, @BatchId = @BatchId;

    DECLARE @FacilityId INT, @Kind NVARCHAR(10), @Status NVARCHAR(20), @StoredKey NVARCHAR(100), @BatchNo NVARCHAR(20);

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @FacilityId = FacilityId, @Kind = InventoryKind, @Status = Status, @StoredKey = IdempotencyKey, @BatchNo = BatchNo
        FROM dbo.ImportBatches WITH (UPDLOCK, HOLDLOCK)
        WHERE BatchId = @BatchId;

        IF @Status = N'Committed'
        BEGIN
            IF @IdempotencyKey IS NOT NULL AND ISNULL(@StoredKey, N'') <> @IdempotencyKey
                THROW 50409, N'This import batch has already been committed.', 1;
            COMMIT TRANSACTION;
            EXEC dbo.usp_Import_GetById @ActorUserId = @ActorUserId, @BatchId = @BatchId;
            RETURN;
        END
        IF @Status = N'Cancelled'
            THROW 50409, N'A cancelled import batch cannot be committed.', 1;

        IF @IdempotencyKey IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.ImportBatches
                WHERE IdempotencyKey = @IdempotencyKey AND SubmittedBy = @ActorUserId AND BatchId <> @BatchId)
            THROW 50409, N'This idempotency key was already used for another import batch.', 1;

        EXEC dbo.usp_Inventory_AssertFacility @ActorUserId = @ActorUserId, @FacilityId = @FacilityId, @Kind = @Kind, @RequireWritable = 1;

        -- Inventory may have changed since staging; expired ValidUntil windows become VALID_UNTIL_RANGE errors.
        EXEC dbo.usp_Import_ValidateRows @BatchId = @BatchId, @IncludeInvalid = 0;

        IF NOT EXISTS (SELECT 1 FROM dbo.ImportRows WHERE BatchId = @BatchId AND ValidationStatus IN (N'Valid', N'Review'))
            THROW 50400, N'The import batch has no valid rows to commit.', 1;

        DECLARE @ImportRowId INT, @RowNumber INT, @RowStatus NVARCHAR(20), @ComponentCode NVARCHAR(20), @AboGroup NVARCHAR(2),
                @RhFactor NVARCHAR(10), @ResourceTypeCode NVARCHAR(30), @Quantity DECIMAL(12,2), @Total DECIMAL(12,2),
                @Avail DECIMAL(12,2), @OpStatus NVARCHAR(20), @Expiry DATE, @ValidUntil DATETIME2(0),
                @ComponentId INT, @ResourceTypeId INT, @RowKey NVARCHAR(100), @Reason NVARCHAR(500), @ForceReview BIT,
                @OriginalRowVersion VARBINARY(8), @ChangeId INT, @IsDuplicate BIT, @ResultStatus NVARCHAR(20),
                @RowCodes NVARCHAR(400), @RowMsgs NVARCHAR(1000);

        DECLARE rc CURSOR LOCAL FAST_FORWARD FOR
            SELECT ImportRowId, RowNumber, ValidationStatus, ComponentCode, AboGroup, RhFactor, ResourceTypeCode, Quantity,
                   TotalQuantity, AvailableQuantity, OperationalStatus, EarliestExpiryDate, ValidUntil, OriginalRowVersion,
                   ErrorCodes, ErrorMessages
            FROM dbo.ImportRows
            WHERE BatchId = @BatchId AND ValidationStatus IN (N'Valid', N'Review')
            ORDER BY RowNumber;
        OPEN rc;
        FETCH NEXT FROM rc INTO @ImportRowId, @RowNumber, @RowStatus, @ComponentCode, @AboGroup, @RhFactor, @ResourceTypeCode, @Quantity,
                                @Total, @Avail, @OpStatus, @Expiry, @ValidUntil, @OriginalRowVersion, @RowCodes, @RowMsgs;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @RowKey = CONCAT(@BatchNo, N'#', @RowNumber);
            SET @Reason = CONCAT(N'Bulk import ', @BatchNo, N' row ', @RowNumber, N'.');
            SET @ForceReview = CASE WHEN @RowStatus = N'Review' THEN 1 ELSE 0 END;
            SET @ChangeId = NULL; SET @IsDuplicate = 0; SET @ResultStatus = NULL;

            IF @Kind = N'Blood'
            BEGIN
                SET @ComponentId = (SELECT ComponentId FROM dbo.BloodComponents WHERE Code = @ComponentCode);
                EXEC dbo.usp_Inventory_RecordBloodChange @ActorUserId = @ActorUserId, @FacilityId = @FacilityId,
                     @ComponentId = @ComponentId, @AboGroup = @AboGroup, @RhFactor = @RhFactor, @Quantity = @Quantity,
                     @EarliestExpiryDate = @Expiry, @ValidUntil = @ValidUntil, @Reason = @Reason, @SourceType = N'CSVImport',
                     @RowVersion = @OriginalRowVersion,
                     @ImportBatchId = @BatchId, @IdempotencyKey = @RowKey, @ForceReview = @ForceReview,
                     @SuppressNotifications = 1, @CorrelationId = @CorrelationId,
                     @ChangeId = @ChangeId OUTPUT, @IsDuplicate = @IsDuplicate OUTPUT, @ResultStatus = @ResultStatus OUTPUT;
            END
            ELSE
            BEGIN
                SET @ResourceTypeId = (SELECT ResourceTypeId FROM dbo.MedicalResourceTypes WHERE Code = @ResourceTypeCode);
                EXEC dbo.usp_Inventory_RecordResourceChange @ActorUserId = @ActorUserId, @FacilityId = @FacilityId,
                     @ResourceTypeId = @ResourceTypeId, @TotalQuantity = @Total, @AvailableQuantity = @Avail,
                     @OperationalStatus = @OpStatus, @ValidUntil = @ValidUntil, @Reason = @Reason, @SourceType = N'CSVImport',
                     @RowVersion = @OriginalRowVersion,
                     @ImportBatchId = @BatchId, @IdempotencyKey = @RowKey, @ForceReview = @ForceReview,
                     @SuppressNotifications = 1, @CorrelationId = @CorrelationId,
                     @ChangeId = @ChangeId OUTPUT, @IsDuplicate = @IsDuplicate OUTPUT, @ResultStatus = @ResultStatus OUTPUT;
            END

            IF @IsDuplicate = 1
                UPDATE dbo.ImportRows
                SET ValidationStatus = N'Duplicate', ErrorCodes = N'DUPLICATE',
                    ErrorMessages = CONCAT(N'An identical update was submitted moments ago (',
                                           (SELECT ChangeNo FROM dbo.InventoryChanges WHERE ChangeId = @ChangeId), N').')
                WHERE ImportRowId = @ImportRowId;
            ELSE IF @ResultStatus = N'PendingReview'
                UPDATE dbo.ImportRows
                SET ValidationStatus = N'Review',
                    ErrorCodes = CASE WHEN ISNULL(ErrorCodes, N'') LIKE N'%LARGE_JUMP%' THEN ErrorCodes
                                      ELSE LEFT(CONCAT_WS(N',', N'LARGE_JUMP', ErrorCodes), 400) END,
                    ErrorMessages = LEFT(CONCAT_WS(N';', ErrorMessages,
                                    CONCAT(N'Queued for verification as ', (SELECT ChangeNo FROM dbo.InventoryChanges WHERE ChangeId = @ChangeId), N'.')), 1000)
                WHERE ImportRowId = @ImportRowId;
            ELSE
                UPDATE dbo.ImportRows SET ValidationStatus = N'Applied' WHERE ImportRowId = @ImportRowId;

            FETCH NEXT FROM rc INTO @ImportRowId, @RowNumber, @RowStatus, @ComponentCode, @AboGroup, @RhFactor, @ResourceTypeCode, @Quantity,
                                    @Total, @Avail, @OpStatus, @Expiry, @ValidUntil, @OriginalRowVersion, @RowCodes, @RowMsgs;
        END
        CLOSE rc;
        DEALLOCATE rc;

        EXEC dbo.usp_Import_RefreshCounts @BatchId = @BatchId;

        UPDATE dbo.ImportBatches
        SET Status = N'Committed', CommittedBy = @ActorUserId, CommittedAt = SYSUTCDATETIME(),
            IdempotencyKey = COALESCE(@IdempotencyKey, IdempotencyKey)
        WHERE BatchId = @BatchId;

        DECLARE @Applied INT, @Review INT, @Skipped INT, @FacilityName NVARCHAR(200);
        SELECT @Applied = AppliedRows, @Review = ReviewRows, @Skipped = InvalidRows + DuplicateRows
        FROM dbo.ImportBatches WHERE BatchId = @BatchId;
        SET @FacilityName = (SELECT Name FROM dbo.Facilities WHERE FacilityId = @FacilityId);

        DECLARE @EntityId NVARCHAR(50) = CAST(@BatchId AS NVARCHAR(50));
        DECLARE @Route NVARCHAR(300) = N'/imports/' + @EntityId;
        DECLARE @NewValues NVARCHAR(MAX) = (SELECT BatchNo, Status, TotalRows, ValidRows, InvalidRows, DuplicateRows, ReviewRows, AppliedRows,
                                                   IdempotencyKey, CommittedAt
                                            FROM dbo.ImportBatches WHERE BatchId = @BatchId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        DECLARE @Desc NVARCHAR(1000) = CONCAT(N'Import ', @BatchNo, N' committed: ', @Applied, N' applied, ', @Review,
                                              N' queued for review, ', @Skipped, N' skipped.');
        EXEC dbo.usp_Audit_Write @ActorUserId = @ActorUserId, @EntityType = N'ImportBatch', @EntityId = @EntityId,
             @ReferenceNo = @BatchNo, @FacilityId = @FacilityId, @Action = N'Committed', @Description = @Desc,
             @NewValues = @NewValues, @SourceType = N'CSVImport', @CorrelationId = @CorrelationId;

        DECLARE @Msg NVARCHAR(1000) = CONCAT(@Desc, N' (', @FacilityName, N')');
        EXEC dbo.usp_Notification_Create @ActorUserId = @ActorUserId, @UserId = @ActorUserId, @Title = N'Import committed',
             @Message = @Msg, @Type = N'Success', @EntityType = N'ImportBatch', @EntityId = @EntityId, @Route = @Route;

        IF @Review > 0
        BEGIN
            DECLARE @RMsg NVARCHAR(1000) = CONCAT(N'Import ', @BatchNo, N' at ', @FacilityName, N' has ', @Review,
                                                  N' change(s) awaiting verification.');
            EXEC dbo.usp_Notification_NotifyFacilityUsers @ActorUserId = @ActorUserId, @FacilityId = @FacilityId,
                 @Title = N'Imported changes need review', @Message = @RMsg, @Type = N'Action', @EntityType = N'ImportBatch',
                 @EntityId = @EntityId, @Route = N'/verifications', @AssignmentRoles = N'Verifier,Manager';
            EXEC dbo.usp_Notification_NotifyRole @ActorUserId = @ActorUserId, @RoleCode = N'Admin',
                 @Title = N'Imported changes need review', @Message = @RMsg, @Type = N'Action', @EntityType = N'ImportBatch',
                 @EntityId = @EntityId, @Route = N'/verifications';
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'rc') >= -1
        BEGIN
            IF CURSOR_STATUS('local', 'rc') >= 0 CLOSE rc;
            DEALLOCATE rc;
        END
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    EXEC dbo.usp_Import_GetById @ActorUserId = @ActorUserId, @BatchId = @BatchId;
END
GO

/* POST imports/{id}/cancel -> Validated batch becomes Cancelled (file may be re-imported). Returns batch detail. */
CREATE OR ALTER PROCEDURE dbo.usp_Import_Cancel
    @ActorUserId   INT,
    @BatchId       INT,
    @Reason        NVARCHAR(500) = NULL,
    @CorrelationId NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Reason = NULLIF(LTRIM(RTRIM(@Reason)), N'');

    EXEC dbo.usp_Import_AssertBatchAccess @ActorUserId = @ActorUserId, @BatchId = @BatchId;

    DECLARE @FacilityId INT, @Status NVARCHAR(20), @BatchNo NVARCHAR(20);

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @FacilityId = FacilityId, @Status = Status, @BatchNo = BatchNo
        FROM dbo.ImportBatches WITH (UPDLOCK, HOLDLOCK) WHERE BatchId = @BatchId;

        IF @Status = N'Committed'
            THROW 50409, N'A committed import batch cannot be cancelled.', 1;

        IF @Status = N'Validated'
        BEGIN
            UPDATE dbo.ImportBatches SET Status = N'Cancelled' WHERE BatchId = @BatchId;

            DECLARE @EntityId NVARCHAR(50) = CAST(@BatchId AS NVARCHAR(50));
            DECLARE @Desc NVARCHAR(1000) = CONCAT(N'Import ', @BatchNo, N' cancelled.');
            EXEC dbo.usp_Audit_Write @ActorUserId = @ActorUserId, @EntityType = N'ImportBatch', @EntityId = @EntityId,
                 @ReferenceNo = @BatchNo, @FacilityId = @FacilityId, @Action = N'Cancelled', @Description = @Desc,
                 @OldValues = N'{"Status":"Validated"}', @NewValues = N'{"Status":"Cancelled"}', @SourceType = N'CSVImport',
                 @Reason = @Reason, @CorrelationId = @CorrelationId;
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    EXEC dbo.usp_Import_GetById @ActorUserId = @ActorUserId, @BatchId = @BatchId;
END
GO
