/*=====================================================================
  SBMRAS - 10_StoredProcedures_Dashboard_Reports.sql
  Role-scoped dashboard (summary, charts, worklist, activity) and the
  report catalog / runner.
  Scope: data.viewall (Admin) = all facilities; facility roles = active
  FacilityUserAssignments; PublicUser = own requests + public
  (Verified + active) availability.
=====================================================================*/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*---------------------------------------------------------------------
  Dashboard
---------------------------------------------------------------------*/

/* Single KPI row for the caller's role scope. */
CREATE OR ALTER PROCEDURE dbo.usp_Dashboard_GetSummary
    @ActorUserId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'dashboard.view') = 0
        THROW 50403, N'You do not have permission to view the dashboard.', 1;

    DECLARE @ViewAll BIT = dbo.fn_UserHasPermission(@ActorUserId, N'data.viewall');
    DECLARE @CanManage BIT = dbo.fn_UserHasPermission(@ActorUserId, N'requests.manage');
    DECLARE @Role NVARCHAR(50) = (
        SELECT TOP (1) r.RoleCode
        FROM dbo.UserRoles ur
        INNER JOIN dbo.Roles r ON r.RoleId = ur.RoleId AND r.IsActive = 1
        WHERE ur.UserId = @ActorUserId
        ORDER BY CASE r.RoleCode WHEN N'Admin' THEN 1 WHEN N'HospitalManagement' THEN 2 WHEN N'BloodBank' THEN 3 ELSE 4 END);

    CREATE TABLE #Fac (FacilityId INT NOT NULL PRIMARY KEY);
    IF @ViewAll = 1
        INSERT INTO #Fac (FacilityId) SELECT FacilityId FROM dbo.Facilities;
    ELSE
        INSERT INTO #Fac (FacilityId)
        SELECT DISTINCT fa.FacilityId FROM dbo.FacilityUserAssignments fa
        WHERE fa.UserId = @ActorUserId AND fa.IsActive = 1;

    DECLARE @Institutional BIT = CASE WHEN EXISTS (SELECT 1 FROM #Fac) THEN 1 ELSE 0 END;
    -- Public users (no facility scope) see the public picture: Verified + active facilities.
    IF @Institutional = 0
        INSERT INTO #Fac (FacilityId)
        SELECT FacilityId FROM dbo.Facilities WHERE VerificationStatus = N'Verified' AND IsActive = 1;

    DECLARE @TotalFacilities INT, @VerifiedFacilities INT;
    SELECT @TotalFacilities = COUNT(*),
           @VerifiedFacilities = SUM(CASE WHEN f.VerificationStatus = N'Verified' AND f.IsActive = 1 THEN 1 ELSE 0 END)
    FROM dbo.Facilities f INNER JOIN #Fac s ON s.FacilityId = f.FacilityId;

    DECLARE @Units DECIMAL(14,2), @Records INT = 0, @Current INT = 0, @Stale INT = 0, @BRecords INT, @BCurrent INT, @BStale INT;
    SELECT @Units = SUM(CASE WHEN v.FreshnessStatus IN (N'Fresh', N'Aging', N'UnderReview') THEN v.Quantity ELSE 0 END),
           @BRecords = COUNT(*),
           @BCurrent = SUM(CASE WHEN v.FreshnessStatus IN (N'Fresh', N'Aging') THEN 1 ELSE 0 END),
           @BStale = SUM(CASE WHEN v.FreshnessStatus = N'Stale' THEN 1 ELSE 0 END)
    FROM dbo.vw_BloodAvailability v INNER JOIN #Fac s ON s.FacilityId = v.FacilityId;

    SELECT @Records = ISNULL(@BRecords, 0) + COUNT(*),
           @Current = ISNULL(@BCurrent, 0) + ISNULL(SUM(CASE WHEN v.FreshnessStatus IN (N'Fresh', N'Aging') THEN 1 ELSE 0 END), 0),
           @Stale = ISNULL(@BStale, 0) + ISNULL(SUM(CASE WHEN v.FreshnessStatus = N'Stale' THEN 1 ELSE 0 END), 0)
    FROM dbo.vw_ResourceAvailability v INNER JOIN #Fac s ON s.FacilityId = v.FacilityId;

    DECLARE @PendingReviews INT = 0, @OpenIssues INT = 0, @PendingFacilityVerifications INT = 0;
    IF @Institutional = 1
    BEGIN
        SELECT @PendingReviews = COUNT(*) FROM dbo.InventoryChanges c INNER JOIN #Fac s ON s.FacilityId = c.FacilityId
        WHERE c.Status = N'PendingReview';
        SELECT @OpenIssues = COUNT(*) FROM dbo.ValidationIssues i INNER JOIN #Fac s ON s.FacilityId = i.FacilityId
        WHERE i.Status = N'Open';
    END
    IF dbo.fn_UserHasPermission(@ActorUserId, N'facilities.verify') = 1
        SELECT @PendingFacilityVerifications = COUNT(*) FROM dbo.Facilities WHERE VerificationStatus = N'Pending';

    DECLARE @OpenRequests INT, @EmergencyRequests INT, @FulfilledRequests INT, @MyOpenRequests INT;
    SELECT @OpenRequests = SUM(CASE WHEN r.Status IN (N'Submitted', N'UnderReview', N'Matched', N'Contacted') THEN 1 ELSE 0 END),
           @EmergencyRequests = SUM(CASE WHEN r.Status IN (N'Submitted', N'UnderReview', N'Matched', N'Contacted') AND r.Urgency = N'Emergency' THEN 1 ELSE 0 END),
           @FulfilledRequests = SUM(CASE WHEN r.Status = N'Fulfilled'
                                          OR (r.Status = N'Closed' AND fh.RequestId IS NOT NULL)
                                         THEN 1 ELSE 0 END)
    FROM dbo.BloodRequests r
    LEFT JOIN (SELECT DISTINCT RequestId FROM dbo.BloodRequestHistory WHERE ToStatus = N'Fulfilled') fh ON fh.RequestId = r.RequestId
    WHERE (@CanManage = 1 OR r.RequesterUserId = @ActorUserId);

    SELECT @MyOpenRequests = COUNT(*) FROM dbo.BloodRequests r
    WHERE r.RequesterUserId = @ActorUserId AND r.Status IN (N'Submitted', N'UnderReview', N'Matched', N'Contacted');

    DECLARE @AvgQuality DECIMAL(5,1) = (
        SELECT CAST(ROUND(AVG(CAST(q.QualityScore AS DECIMAL(9,2))), 1) AS DECIMAL(5,1))
        FROM dbo.vw_FacilityQualityScore q INNER JOIN #Fac s ON s.FacilityId = q.FacilityId);

    SELECT ISNULL(@Role, N'PublicUser') AS Role,
           ISNULL(@TotalFacilities, 0) AS TotalFacilities,
           ISNULL(@VerifiedFacilities, 0) AS VerifiedFacilities,
           CAST(ISNULL(@Units, 0) AS DECIMAL(14,2)) AS BloodUnitsAvailable,
           CAST(CASE WHEN ISNULL(@Records, 0) = 0 THEN 0 ELSE ROUND(@Current * 100.0 / @Records, 1) END AS DECIMAL(5,1)) AS FreshPercent,
           ISNULL(@Stale, 0) AS StaleRecords,
           ISNULL(@PendingReviews, 0) AS PendingReviews,
           ISNULL(@OpenRequests, 0) AS OpenRequests,
           ISNULL(@EmergencyRequests, 0) AS EmergencyRequests,
           ISNULL(@FulfilledRequests, 0) AS FulfilledRequests,
           ISNULL(@MyOpenRequests, 0) AS MyOpenRequests,
           ISNULL(@OpenIssues, 0) AS OpenIssues,
           ISNULL(@AvgQuality, 0) AS AvgQualityScore,
           ISNULL(@PendingFacilityVerifications, 0) AS PendingFacilityVerifications;
END
GO

/*
  Dashboard charts. Result sets (in order):
    1 bloodByGroup (Label, Value)            4 requestStatus (Label, Value)
    2 freshness (Label, Value)               5 resourceUtilization (Label, Total, Available)
    3 requestTrend (Label, Submitted, Fulfilled) last 14 days
                                             6 qualityByFacility (Label, Value) top 10
*/
CREATE OR ALTER PROCEDURE dbo.usp_Dashboard_GetCharts
    @ActorUserId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'dashboard.view') = 0
        THROW 50403, N'You do not have permission to view the dashboard.', 1;

    DECLARE @ViewAll BIT = dbo.fn_UserHasPermission(@ActorUserId, N'data.viewall');
    DECLARE @CanManage BIT = dbo.fn_UserHasPermission(@ActorUserId, N'requests.manage');

    CREATE TABLE #Fac (FacilityId INT NOT NULL PRIMARY KEY);
    IF @ViewAll = 1
        INSERT INTO #Fac (FacilityId) SELECT FacilityId FROM dbo.Facilities;
    ELSE
        INSERT INTO #Fac (FacilityId)
        SELECT DISTINCT fa.FacilityId FROM dbo.FacilityUserAssignments fa
        WHERE fa.UserId = @ActorUserId AND fa.IsActive = 1;
    IF NOT EXISTS (SELECT 1 FROM #Fac)
        INSERT INTO #Fac (FacilityId)
        SELECT FacilityId FROM dbo.Facilities WHERE VerificationStatus = N'Verified' AND IsActive = 1;

    -- 1 bloodByGroup: current (non-stale, reported) units per blood group, all 8 groups.
    SELECT g.BloodGroup AS Label,
           CAST(ISNULL(SUM(CASE WHEN v.FreshnessStatus IN (N'Fresh', N'Aging', N'UnderReview') THEN v.Quantity END), 0) AS DECIMAL(14,2)) AS Value
    FROM (VALUES (N'A', N'Positive', N'A+', 1), (N'A', N'Negative', N'A-', 2), (N'B', N'Positive', N'B+', 3), (N'B', N'Negative', N'B-', 4),
                 (N'AB', N'Positive', N'AB+', 5), (N'AB', N'Negative', N'AB-', 6), (N'O', N'Positive', N'O+', 7), (N'O', N'Negative', N'O-', 8))
         AS g (AboGroup, RhFactor, BloodGroup, SortOrder)
    LEFT JOIN (dbo.vw_BloodAvailability v INNER JOIN #Fac s ON s.FacilityId = v.FacilityId)
           ON v.AboGroup = g.AboGroup AND v.RhFactor = g.RhFactor
    GROUP BY g.BloodGroup, g.SortOrder
    ORDER BY g.SortOrder;

    -- 2 freshness: blood + resource records by freshness status.
    ;WITH recs AS (
        SELECT v.FreshnessStatus FROM dbo.vw_BloodAvailability v INNER JOIN #Fac s ON s.FacilityId = v.FacilityId
        UNION ALL
        SELECT v.FreshnessStatus FROM dbo.vw_ResourceAvailability v INNER JOIN #Fac s ON s.FacilityId = v.FacilityId)
    SELECT st.Label, COUNT(r.FreshnessStatus) AS Value
    FROM (VALUES (N'Fresh', 1), (N'Aging', 2), (N'Stale', 3), (N'Unknown', 4), (N'UnderReview', 5)) AS st (Label, SortOrder)
    LEFT JOIN recs r ON r.FreshnessStatus = st.Label
    GROUP BY st.Label, st.SortOrder
    ORDER BY st.SortOrder;

    -- 3 requestTrend: last 14 days (UTC) submitted vs fulfilled.
    DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE);
    ;WITH days AS (
        SELECT TOP (14) DATEADD(DAY, -(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1), @Today) AS [Day]
        FROM sys.all_objects)
    SELECT FORMAT(d.[Day], 'dd MMM', 'en-US') AS Label,
           (SELECT COUNT(*) FROM dbo.BloodRequests r
            WHERE CAST(r.CreatedAt AS DATE) = d.[Day] AND (@CanManage = 1 OR r.RequesterUserId = @ActorUserId)) AS Submitted,
           (SELECT COUNT(DISTINCT h.RequestId) FROM dbo.BloodRequestHistory h
            INNER JOIN dbo.BloodRequests r ON r.RequestId = h.RequestId
            WHERE h.ToStatus = N'Fulfilled' AND CAST(h.ChangedAt AS DATE) = d.[Day]
              AND (@CanManage = 1 OR r.RequesterUserId = @ActorUserId)) AS Fulfilled
    FROM days d
    ORDER BY d.[Day];

    -- 4 requestStatus
    SELECT st.Label, COUNT(r.RequestId) AS Value
    FROM (VALUES (N'Submitted', 1), (N'UnderReview', 2), (N'Matched', 3), (N'Contacted', 4), (N'Fulfilled', 5),
                 (N'UnableToFulfil', 6), (N'Closed', 7), (N'Cancelled', 8)) AS st (Label, SortOrder)
    LEFT JOIN dbo.BloodRequests r ON r.Status = st.Label AND (@CanManage = 1 OR r.RequesterUserId = @ActorUserId)
    GROUP BY st.Label, st.SortOrder
    ORDER BY st.SortOrder;

    -- 5 resourceUtilization: totals per resource type (reported records only).
    SELECT v.ResourceTypeName AS Label,
           CAST(ISNULL(SUM(v.TotalQuantity), 0) AS DECIMAL(14,2)) AS Total,
           CAST(ISNULL(SUM(v.AvailableQuantity), 0) AS DECIMAL(14,2)) AS Available
    FROM dbo.vw_ResourceAvailability v INNER JOIN #Fac s ON s.FacilityId = v.FacilityId
    WHERE v.LastUpdatedAt IS NOT NULL
    GROUP BY v.ResourceTypeName
    ORDER BY v.ResourceTypeName;

    -- 6 qualityByFacility: top 10 by quality score.
    SELECT TOP (10) f.Name AS Label, CAST(ISNULL(q.QualityScore, 0) AS DECIMAL(5,1)) AS Value
    FROM dbo.vw_FacilityQualityScore q
    INNER JOIN #Fac s ON s.FacilityId = q.FacilityId
    INNER JOIN dbo.Facilities f ON f.FacilityId = q.FacilityId
    WHERE f.IsActive = 1
    ORDER BY q.QualityScore DESC, f.Name;
END
GO

/*
  Actionable items for the caller: Type, ReferenceNo, Title, Status, Priority (High/Medium/Low), DueAt, Route.
  Coordinators: open requests in their facility areas (all for Admin); verifiers: pending inventory changes;
  facility users: stale records, high-severity issues, validated imports; Admin: pending facility verifications;
  everyone: own open requests.
*/
CREATE OR ALTER PROCEDURE dbo.usp_Dashboard_GetWorklist
    @ActorUserId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'dashboard.view') = 0
        THROW 50403, N'You do not have permission to view the dashboard.', 1;

    DECLARE @ViewAll BIT = dbo.fn_UserHasPermission(@ActorUserId, N'data.viewall');
    DECLARE @CanManage BIT = dbo.fn_UserHasPermission(@ActorUserId, N'requests.manage');
    DECLARE @CanVerify BIT = dbo.fn_UserHasPermission(@ActorUserId, N'inventory.verify');
    DECLARE @CanImport BIT = dbo.fn_UserHasPermission(@ActorUserId, N'inventory.import');
    DECLARE @CanQuality BIT = dbo.fn_UserHasPermission(@ActorUserId, N'dataquality.view');

    CREATE TABLE #Fac (FacilityId INT NOT NULL PRIMARY KEY);
    IF @ViewAll = 1
        INSERT INTO #Fac (FacilityId) SELECT FacilityId FROM dbo.Facilities WHERE IsActive = 1;
    ELSE
        INSERT INTO #Fac (FacilityId)
        SELECT DISTINCT fa.FacilityId FROM dbo.FacilityUserAssignments fa
        INNER JOIN dbo.Facilities f ON f.FacilityId = fa.FacilityId AND f.IsActive = 1
        WHERE fa.UserId = @ActorUserId AND fa.IsActive = 1;

    CREATE TABLE #Work
    (
        [Type] NVARCHAR(30), ReferenceNo NVARCHAR(50), Title NVARCHAR(300), Status NVARCHAR(30),
        Priority NVARCHAR(10), DueAt DATETIME2(0) NULL, Route NVARCHAR(300)
    );

    IF @CanManage = 1
        INSERT INTO #Work
        SELECT N'BloodRequest', r.RequestNo,
               r.Urgency + N' ' + CAST(CAST(r.QuantityRequested AS DECIMAL(12,2)) AS NVARCHAR(20)) + N' '
                 + r.AboGroup + CASE WHEN r.RhFactor = N'Positive' THEN N'+' ELSE N'-' END + N' ' + c.Code
                 + N' - ' + r.HospitalName,
               r.Status,
               CASE r.Urgency WHEN N'Emergency' THEN N'High' WHEN N'Urgent' THEN N'Medium' ELSE N'Low' END,
               r.NeededBy, N'/coordination/' + CAST(r.RequestId AS NVARCHAR(20))
        FROM dbo.BloodRequests r
        INNER JOIN dbo.BloodComponents c ON c.ComponentId = r.ComponentId
        WHERE r.Status IN (N'Submitted', N'UnderReview', N'Matched', N'Contacted')
          AND (@ViewAll = 1
               OR r.MatchedFacilityId IN (SELECT FacilityId FROM #Fac)
               OR r.PreferredFacilityId IN (SELECT FacilityId FROM #Fac)
               OR r.AreaId IN (SELECT f.AreaId FROM dbo.Facilities f INNER JOIN #Fac s ON s.FacilityId = f.FacilityId));

    IF @CanVerify = 1
        INSERT INTO #Work
        SELECT N'InventoryChange', ch.ChangeNo,
               N'Review ' + ch.InventoryKind + N' change at ' + f.Name
                 + CASE WHEN ch.AnomalyFlags IS NOT NULL THEN N' (' + ch.AnomalyFlags + N')' ELSE N'' END,
               ch.Status, N'High', ch.SubmittedAt, N'/verifications'
        FROM dbo.InventoryChanges ch
        INNER JOIN #Fac s ON s.FacilityId = ch.FacilityId
        INNER JOIN dbo.Facilities f ON f.FacilityId = ch.FacilityId
        WHERE ch.Status = N'PendingReview'
          AND (ch.SubmittedBy <> @ActorUserId OR dbo.fn_UserIsAdmin(@ActorUserId) = 1);

    IF EXISTS (SELECT 1 FROM #Fac)
    BEGIN
        ;WITH stale AS (
            SELECT v.FacilityId, N'Blood' AS Kind, COUNT(*) AS Cnt, MIN(v.ValidUntil) AS OldestValidUntil
            FROM dbo.vw_BloodAvailability v INNER JOIN #Fac s ON s.FacilityId = v.FacilityId
            WHERE v.FreshnessStatus = N'Stale'
            GROUP BY v.FacilityId
            UNION ALL
            SELECT v.FacilityId, N'Resource', COUNT(*), MIN(v.ValidUntil)
            FROM dbo.vw_ResourceAvailability v INNER JOIN #Fac s ON s.FacilityId = v.FacilityId
            WHERE v.FreshnessStatus = N'Stale'
            GROUP BY v.FacilityId)
        INSERT INTO #Work
        SELECT N'StaleStock', f.FacilityCode,
               CAST(st.Cnt AS NVARCHAR(10)) + N' stale ' + LOWER(st.Kind) + N' record(s) at ' + f.Name,
               N'Stale', N'Medium', st.OldestValidUntil,
               CASE WHEN st.Kind = N'Blood' THEN N'/blood-stock?facilityId=' ELSE N'/resource-inventory?facilityId=' END
                 + CAST(f.FacilityId AS NVARCHAR(20))
        FROM stale st
        INNER JOIN dbo.Facilities f ON f.FacilityId = st.FacilityId
        WHERE (st.Kind = N'Blood' AND dbo.fn_UserHasPermission(@ActorUserId, N'bloodstock.manage') = 1)
           OR (st.Kind = N'Resource' AND dbo.fn_UserHasPermission(@ActorUserId, N'resources.manage') = 1);

        IF @CanQuality = 1
            INSERT INTO #Work
            SELECT TOP (20) N'DataQualityIssue', i.IssueCode + N'-' + CAST(i.IssueId AS NVARCHAR(20)),
                   f.Name + N': ' + i.Message, i.Status, i.Severity, i.DetectedAt, N'/data-quality'
            FROM dbo.ValidationIssues i
            INNER JOIN #Fac s ON s.FacilityId = i.FacilityId
            INNER JOIN dbo.Facilities f ON f.FacilityId = i.FacilityId
            WHERE i.Status = N'Open' AND i.Severity = N'High'
            ORDER BY i.DetectedAt;

        IF @CanImport = 1
            INSERT INTO #Work
            SELECT N'ImportBatch', b.BatchNo, N'Commit or cancel import ' + b.FileName + N' (' + f.Name + N')',
                   b.Status, N'Low', b.SubmittedAt, N'/imports/' + CAST(b.BatchId AS NVARCHAR(20))
            FROM dbo.ImportBatches b
            INNER JOIN #Fac s ON s.FacilityId = b.FacilityId
            INNER JOIN dbo.Facilities f ON f.FacilityId = b.FacilityId
            WHERE b.Status = N'Validated';
    END

    IF dbo.fn_UserHasPermission(@ActorUserId, N'facilities.verify') = 1
        INSERT INTO #Work
        SELECT N'FacilityVerification', f.FacilityCode, N'Verify ' + f.FacilityType + N' ' + f.Name,
               f.VerificationStatus, N'Medium', f.CreatedAt, N'/admin/facilities'
        FROM dbo.Facilities f
        WHERE f.VerificationStatus = N'Pending';

    INSERT INTO #Work
    SELECT N'MyRequest', r.RequestNo,
           N'Your ' + CAST(CAST(r.QuantityRequested AS DECIMAL(12,2)) AS NVARCHAR(20)) + N' '
             + r.AboGroup + CASE WHEN r.RhFactor = N'Positive' THEN N'+' ELSE N'-' END + N' ' + c.Code + N' request',
           r.Status, CASE r.Urgency WHEN N'Emergency' THEN N'High' WHEN N'Urgent' THEN N'Medium' ELSE N'Low' END,
           r.NeededBy, N'/requests/' + CAST(r.RequestId AS NVARCHAR(20))
    FROM dbo.BloodRequests r
    INNER JOIN dbo.BloodComponents c ON c.ComponentId = r.ComponentId
    WHERE r.RequesterUserId = @ActorUserId AND r.Status IN (N'Submitted', N'UnderReview', N'Matched', N'Contacted', N'UnableToFulfil');

    SELECT TOP (50) w.[Type], w.ReferenceNo, w.Title, w.Status, w.Priority, w.DueAt, w.Route
    FROM #Work w
    ORDER BY CASE w.Priority WHEN N'High' THEN 1 WHEN N'Medium' THEN 2 ELSE 3 END,
             CASE WHEN w.DueAt IS NULL THEN 1 ELSE 0 END, w.DueAt, w.ReferenceNo;
END
GO

/* Recent audit activity visible to the caller (Admin: all; facility users: their facilities + own; others: own). */
CREATE OR ALTER PROCEDURE dbo.usp_Dashboard_GetActivity
    @ActorUserId INT,
    @Top         INT = 10
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'dashboard.view') = 0
        THROW 50403, N'You do not have permission to view the dashboard.', 1;

    DECLARE @ViewAll BIT = dbo.fn_UserHasPermission(@ActorUserId, N'data.viewall');
    SET @Top = CASE WHEN ISNULL(@Top, 10) < 1 THEN 10 WHEN @Top > 100 THEN 100 ELSE @Top END;

    SELECT TOP (@Top) a.AuditId, a.EntityType, a.EntityId, a.ReferenceNo, a.Action, a.Description,
           u.DisplayName AS UserName, a.CreatedAt
    FROM dbo.AuditLogs a
    LEFT JOIN dbo.Users u ON u.UserId = a.UserId
    WHERE @ViewAll = 1
       OR a.UserId = @ActorUserId
       OR (a.FacilityId IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.FacilityUserAssignments fa
                                                WHERE fa.UserId = @ActorUserId AND fa.FacilityId = a.FacilityId AND fa.IsActive = 1))
       OR (a.EntityType = N'BloodRequest' AND EXISTS (SELECT 1 FROM dbo.BloodRequests r
                                                      WHERE r.RequesterUserId = @ActorUserId
                                                        AND CAST(r.RequestId AS NVARCHAR(50)) = a.EntityId))
    ORDER BY a.CreatedAt DESC, a.AuditId DESC;
END
GO

/*---------------------------------------------------------------------
  Reports
---------------------------------------------------------------------*/

/* Report catalog: Code, Name, Description. */
CREATE OR ALTER PROCEDURE dbo.usp_Report_List
    @ActorUserId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'reports.view') = 0
        THROW 50403, N'You do not have permission to view reports.', 1;

    SELECT r.Code, r.Name, r.Description
    FROM (VALUES
        (1, N'INVENTORY_SUMMARY', N'Inventory Summary', N'Current blood units and medical resource availability by facility and area.'),
        (2, N'FRESHNESS_COMPLIANCE', N'Freshness Compliance', N'Fresh, aging, stale and unknown records per facility with update-interval compliance.'),
        (3, N'DATA_COMPLETENESS', N'Data Completeness', N'Expected versus reported inventory records and missing required fields per facility.'),
        (4, N'IMPORT_QUALITY', N'Import Quality', N'Bulk import rows received, accepted, rejected, duplicate and reviewed per batch.'),
        (5, N'REQUEST_LIFECYCLE', N'Request Lifecycle', N'Blood request counts per status and average time spent in each state.'),
        (6, N'FACILITY_RELIABILITY', N'Facility Reliability', N'Update frequency, stale rate, correction rate and verification completion per facility.'),
        (7, N'RESOURCE_AVAILABILITY', N'Resource Availability', N'Medical resource capacity, availability and utilisation by resource type.')
    ) AS r (SortOrder, Code, Name, Description)
    ORDER BY r.SortOrder;
END
GO

/*
  Runs a report. Result sets: 1 meta (Code, Name); 2 columns (Key, Label, Type: text|number|date|percent);
  3 rows (column aliases are camelCase and equal the column Keys).
  Facility-level data is limited to facilities the caller can access (data.viewall = all).
  @FromDate / @ToDate are inclusive days and apply to time-based reports (imports, requests, changes).
*/
CREATE OR ALTER PROCEDURE dbo.usp_Report_Run
    @ActorUserId INT,
    @ReportCode  NVARCHAR(50),
    @FromDate    DATETIME2(0) = NULL,
    @ToDate      DATETIME2(0) = NULL,
    @FacilityId  INT = NULL,
    @AreaId      INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'reports.view') = 0
        THROW 50403, N'You do not have permission to view reports.', 1;

    SET @ReportCode = UPPER(LTRIM(RTRIM(ISNULL(@ReportCode, N''))));
    IF @FacilityId = 0 SET @FacilityId = NULL;
    IF @AreaId = 0 SET @AreaId = NULL;

    DECLARE @Name NVARCHAR(100) = CASE @ReportCode
        WHEN N'INVENTORY_SUMMARY' THEN N'Inventory Summary'
        WHEN N'FRESHNESS_COMPLIANCE' THEN N'Freshness Compliance'
        WHEN N'DATA_COMPLETENESS' THEN N'Data Completeness'
        WHEN N'IMPORT_QUALITY' THEN N'Import Quality'
        WHEN N'REQUEST_LIFECYCLE' THEN N'Request Lifecycle'
        WHEN N'FACILITY_RELIABILITY' THEN N'Facility Reliability'
        WHEN N'RESOURCE_AVAILABILITY' THEN N'Resource Availability' END;
    IF @Name IS NULL
        THROW 50404, N'Report not found.', 1;

    IF @FacilityId IS NOT NULL AND dbo.fn_UserCanAccessFacility(@ActorUserId, @FacilityId) = 0
        THROW 50403, N'You are not assigned to this facility.', 1;
    IF @FromDate IS NOT NULL AND @ToDate IS NOT NULL AND @FromDate > @ToDate
        THROW 50400, N'From date must be on or before to date.', 1;

    DECLARE @ViewAll BIT = dbo.fn_UserHasPermission(@ActorUserId, N'data.viewall');
    DECLARE @From DATETIME2(0) = CAST(CAST(@FromDate AS DATE) AS DATETIME2(0));
    DECLARE @To DATETIME2(0) = DATEADD(DAY, 1, CAST(CAST(@ToDate AS DATE) AS DATETIME2(0)));
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

    CREATE TABLE #Fac (FacilityId INT NOT NULL PRIMARY KEY);
    INSERT INTO #Fac (FacilityId)
    SELECT f.FacilityId
    FROM dbo.Facilities f
    WHERE (@FacilityId IS NULL OR f.FacilityId = @FacilityId)
      AND (@AreaId IS NULL OR f.AreaId = @AreaId)
      AND (@ViewAll = 1 OR EXISTS (SELECT 1 FROM dbo.FacilityUserAssignments fa
                                   WHERE fa.FacilityId = f.FacilityId AND fa.UserId = @ActorUserId AND fa.IsActive = 1));

    SELECT @ReportCode AS Code, @Name AS Name;

    CREATE TABLE #Cols (SortOrder INT, [Key] NVARCHAR(50), Label NVARCHAR(100), [Type] NVARCHAR(10));

    IF @ReportCode = N'INVENTORY_SUMMARY'
    BEGIN
        INSERT INTO #Cols VALUES
            (1, N'facilityName', N'Facility', N'text'), (2, N'facilityType', N'Type', N'text'), (3, N'areaName', N'Area', N'text'),
            (4, N'bloodUnits', N'Blood units (current)', N'number'), (5, N'bloodRecords', N'Blood records', N'number'),
            (6, N'lowStockRecords', N'Low stock', N'number'), (7, N'outOfStockRecords', N'Out of stock', N'number'),
            (8, N'resourceAvailable', N'Resources available', N'number'), (9, N'resourceTotal', N'Resources total', N'number'),
            (10, N'freshPercent', N'Fresh %', N'percent'), (11, N'lastUpdatedAt', N'Last updated', N'date');
        SELECT [Key], Label, [Type] FROM #Cols ORDER BY SortOrder;

        ;WITH b AS (
            SELECT v.FacilityId,
                   SUM(CASE WHEN v.FreshnessStatus IN (N'Fresh', N'Aging', N'UnderReview') THEN v.Quantity ELSE 0 END) AS Units,
                   SUM(CASE WHEN v.LastUpdatedAt IS NOT NULL THEN 1 ELSE 0 END) AS Records,
                   SUM(CASE WHEN v.AvailabilityStatus = N'Low' THEN 1 ELSE 0 END) AS Low,
                   SUM(CASE WHEN v.AvailabilityStatus = N'OutOfStock' THEN 1 ELSE 0 END) AS OutOfStock,
                   COUNT(*) AS AllRecords,
                   SUM(CASE WHEN v.FreshnessStatus IN (N'Fresh', N'Aging') THEN 1 ELSE 0 END) AS CurrentRecords,
                   MAX(v.LastUpdatedAt) AS LastUpdatedAt
            FROM dbo.vw_BloodAvailability v INNER JOIN #Fac s ON s.FacilityId = v.FacilityId
            GROUP BY v.FacilityId),
        r AS (
            SELECT v.FacilityId,
                   SUM(ISNULL(v.AvailableQuantity, 0)) AS Available, SUM(ISNULL(v.TotalQuantity, 0)) AS Total,
                   COUNT(*) AS AllRecords,
                   SUM(CASE WHEN v.FreshnessStatus IN (N'Fresh', N'Aging') THEN 1 ELSE 0 END) AS CurrentRecords,
                   MAX(v.LastUpdatedAt) AS LastUpdatedAt
            FROM dbo.vw_ResourceAvailability v INNER JOIN #Fac s ON s.FacilityId = v.FacilityId
            GROUP BY v.FacilityId)
        SELECT f.Name AS facilityName, f.FacilityType AS facilityType, a.Name AS areaName,
               CAST(ISNULL(b.Units, 0) AS DECIMAL(14,2)) AS bloodUnits,
               ISNULL(b.Records, 0) AS bloodRecords,
               ISNULL(b.Low, 0) AS lowStockRecords,
               ISNULL(b.OutOfStock, 0) AS outOfStockRecords,
               CAST(ISNULL(r.Available, 0) AS DECIMAL(14,2)) AS resourceAvailable,
               CAST(ISNULL(r.Total, 0) AS DECIMAL(14,2)) AS resourceTotal,
               CAST(CASE WHEN ISNULL(b.AllRecords, 0) + ISNULL(r.AllRecords, 0) = 0 THEN 0
                         ELSE ROUND((ISNULL(b.CurrentRecords, 0) + ISNULL(r.CurrentRecords, 0)) * 100.0
                                    / (ISNULL(b.AllRecords, 0) + ISNULL(r.AllRecords, 0)), 1) END AS DECIMAL(5,1)) AS freshPercent,
               CASE WHEN r.LastUpdatedAt IS NULL OR b.LastUpdatedAt >= r.LastUpdatedAt THEN b.LastUpdatedAt ELSE r.LastUpdatedAt END AS lastUpdatedAt
        FROM #Fac s
        INNER JOIN dbo.Facilities f ON f.FacilityId = s.FacilityId
        INNER JOIN dbo.Areas a ON a.AreaId = f.AreaId
        LEFT JOIN b ON b.FacilityId = f.FacilityId
        LEFT JOIN r ON r.FacilityId = f.FacilityId
        WHERE f.IsActive = 1
        ORDER BY bloodUnits DESC, f.Name;
        RETURN;
    END

    IF @ReportCode = N'FRESHNESS_COMPLIANCE'
    BEGIN
        INSERT INTO #Cols VALUES
            (1, N'facilityName', N'Facility', N'text'), (2, N'facilityType', N'Type', N'text'),
            (3, N'compliancePercent', N'Within TTL %', N'percent'), (4, N'totalRecords', N'Records', N'number'),
            (5, N'fresh', N'Fresh', N'number'), (6, N'aging', N'Aging', N'number'), (7, N'stale', N'Stale', N'number'),
            (8, N'unknown', N'Unknown', N'number'), (9, N'underReview', N'Under review', N'number'),
            (10, N'avgAgeMinutes', N'Avg age (min)', N'number'), (11, N'lastUpdatedAt', N'Last updated', N'date');
        SELECT [Key], Label, [Type] FROM #Cols ORDER BY SortOrder;

        ;WITH recs AS (
            SELECT v.FacilityId, v.FreshnessStatus, v.LastUpdatedAt
            FROM dbo.vw_BloodAvailability v INNER JOIN #Fac s ON s.FacilityId = v.FacilityId
            UNION ALL
            SELECT v.FacilityId, v.FreshnessStatus, v.LastUpdatedAt
            FROM dbo.vw_ResourceAvailability v INNER JOIN #Fac s ON s.FacilityId = v.FacilityId)
        SELECT f.Name AS facilityName, f.FacilityType AS facilityType,
               CAST(CASE WHEN COUNT(*) = 0 THEN 0
                         ELSE ROUND(SUM(CASE WHEN r.FreshnessStatus IN (N'Fresh', N'Aging') THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) END
                    AS DECIMAL(5,1)) AS compliancePercent,
               COUNT(*) AS totalRecords,
               SUM(CASE WHEN r.FreshnessStatus = N'Fresh' THEN 1 ELSE 0 END) AS fresh,
               SUM(CASE WHEN r.FreshnessStatus = N'Aging' THEN 1 ELSE 0 END) AS aging,
               SUM(CASE WHEN r.FreshnessStatus = N'Stale' THEN 1 ELSE 0 END) AS stale,
               SUM(CASE WHEN r.FreshnessStatus = N'Unknown' THEN 1 ELSE 0 END) AS unknown,
               SUM(CASE WHEN r.FreshnessStatus = N'UnderReview' THEN 1 ELSE 0 END) AS underReview,
               ISNULL(AVG(CAST(DATEDIFF(MINUTE, r.LastUpdatedAt, @Now) AS BIGINT)), 0) AS avgAgeMinutes,
               MAX(r.LastUpdatedAt) AS lastUpdatedAt
        FROM recs r
        INNER JOIN dbo.Facilities f ON f.FacilityId = r.FacilityId
        WHERE f.IsActive = 1
        GROUP BY f.FacilityId, f.Name, f.FacilityType
        ORDER BY compliancePercent, f.Name;
        RETURN;
    END

    IF @ReportCode = N'DATA_COMPLETENESS'
    BEGIN
        INSERT INTO #Cols VALUES
            (1, N'facilityName', N'Facility', N'text'), (2, N'facilityType', N'Type', N'text'),
            (3, N'completenessPercent', N'Completeness %', N'percent'), (4, N'expectedRecords', N'Expected records', N'number'),
            (5, N'reportedRecords', N'Reported records', N'number'), (6, N'missingRecords', N'Never reported', N'number'),
            (7, N'missingExpiry', N'Stock without expiry date', N'number'), (8, N'missingProfileFields', N'Missing profile fields', N'number'),
            (9, N'openMissingIssues', N'Open missing-field issues', N'number');
        SELECT [Key], Label, [Type] FROM #Cols ORDER BY SortOrder;

        DECLARE @Components INT = (SELECT COUNT(*) FROM dbo.BloodComponents WHERE IsActive = 1);
        DECLARE @ResourceTypes INT = (SELECT COUNT(*) FROM dbo.MedicalResourceTypes WHERE IsActive = 1);

        ;WITH x AS (
            SELECT f.FacilityId, f.Name, f.FacilityType,
                   CASE WHEN f.FacilityType = N'BloodBank' THEN @Components * 8 ELSE @ResourceTypes END AS Expected,
                   CASE WHEN f.FacilityType = N'BloodBank'
                        THEN (SELECT COUNT(*) FROM dbo.BloodInventory bi WHERE bi.FacilityId = f.FacilityId AND bi.LastUpdatedAt IS NOT NULL)
                        ELSE (SELECT COUNT(*) FROM dbo.MedicalResourceInventory mi WHERE mi.FacilityId = f.FacilityId AND mi.LastUpdatedAt IS NOT NULL)
                   END AS Reported,
                   (SELECT COUNT(*) FROM dbo.BloodInventory bi
                    WHERE bi.FacilityId = f.FacilityId AND bi.Quantity > 0 AND bi.EarliestExpiryDate IS NULL) AS MissingExpiry,
                   CASE WHEN f.LicenseNo IS NULL THEN 1 ELSE 0 END + CASE WHEN f.ContactEmail IS NULL THEN 1 ELSE 0 END
                     + CASE WHEN f.Pincode IS NULL THEN 1 ELSE 0 END
                     + CASE WHEN f.Latitude IS NULL OR f.Longitude IS NULL THEN 1 ELSE 0 END AS MissingProfile,
                   (SELECT COUNT(*) FROM dbo.ValidationIssues i
                    WHERE i.FacilityId = f.FacilityId AND i.IssueCode = N'MISSING_FIELD' AND i.Status = N'Open') AS OpenMissing
            FROM #Fac s INNER JOIN dbo.Facilities f ON f.FacilityId = s.FacilityId
            WHERE f.IsActive = 1)
        SELECT x.Name AS facilityName, x.FacilityType AS facilityType,
               CAST(CASE WHEN x.Expected = 0 THEN 0
                         ELSE ROUND(CASE WHEN x.Reported > x.Expected THEN x.Expected ELSE x.Reported END * 100.0 / x.Expected, 1) END
                    AS DECIMAL(5,1)) AS completenessPercent,
               x.Expected AS expectedRecords, x.Reported AS reportedRecords,
               CASE WHEN x.Expected > x.Reported THEN x.Expected - x.Reported ELSE 0 END AS missingRecords,
               x.MissingExpiry AS missingExpiry, x.MissingProfile AS missingProfileFields, x.OpenMissing AS openMissingIssues
        FROM x
        ORDER BY completenessPercent, x.Name;
        RETURN;
    END

    IF @ReportCode = N'IMPORT_QUALITY'
    BEGIN
        INSERT INTO #Cols VALUES
            (1, N'batchNo', N'Batch', N'text'), (2, N'facilityName', N'Facility', N'text'), (3, N'inventoryKind', N'Kind', N'text'),
            (4, N'totalRows', N'Rows received', N'number'), (5, N'validRows', N'Valid', N'number'), (6, N'invalidRows', N'Rejected', N'number'),
            (7, N'duplicateRows', N'Duplicate', N'number'), (8, N'reviewRows', N'For review', N'number'), (9, N'appliedRows', N'Applied', N'number'),
            (10, N'acceptanceRate', N'Acceptance %', N'percent'), (11, N'topErrorCode', N'Top error code', N'text'),
            (12, N'status', N'Status', N'text'), (13, N'fileName', N'File', N'text'), (14, N'submittedAt', N'Submitted', N'date');
        SELECT [Key], Label, [Type] FROM #Cols ORDER BY SortOrder;

        SELECT b.BatchNo AS batchNo, f.Name AS facilityName, b.InventoryKind AS inventoryKind,
               b.TotalRows AS totalRows, b.ValidRows AS validRows, b.InvalidRows AS invalidRows, b.DuplicateRows AS duplicateRows,
               b.ReviewRows AS reviewRows, b.AppliedRows AS appliedRows,
               CAST(CASE WHEN b.TotalRows = 0 THEN 0
                         ELSE ROUND(CASE WHEN b.Status = N'Committed' THEN b.AppliedRows + b.ReviewRows ELSE b.ValidRows + b.ReviewRows END
                                    * 100.0 / b.TotalRows, 1) END AS DECIMAL(5,1)) AS acceptanceRate,
               (SELECT TOP (1) LTRIM(RTRIM(e.value))
                FROM dbo.ImportRows ir
                CROSS APPLY STRING_SPLIT(ir.ErrorCodes, N',') e
                WHERE ir.BatchId = b.BatchId AND ir.ErrorCodes IS NOT NULL AND LTRIM(RTRIM(e.value)) <> N''
                GROUP BY LTRIM(RTRIM(e.value))
                ORDER BY COUNT(*) DESC, LTRIM(RTRIM(e.value))) AS topErrorCode,
               b.Status AS status, b.FileName AS fileName, b.SubmittedAt AS submittedAt
        FROM dbo.ImportBatches b
        INNER JOIN #Fac s ON s.FacilityId = b.FacilityId
        INNER JOIN dbo.Facilities f ON f.FacilityId = b.FacilityId
        WHERE (@From IS NULL OR b.SubmittedAt >= @From)
          AND (@To IS NULL OR b.SubmittedAt < @To)
        ORDER BY b.SubmittedAt DESC, b.BatchId DESC;
        RETURN;
    END

    IF @ReportCode = N'REQUEST_LIFECYCLE'
    BEGIN
        INSERT INTO #Cols VALUES
            (1, N'status', N'Status', N'text'), (2, N'currentRequests', N'Currently in status', N'number'),
            (3, N'everReached', N'Requests that reached status', N'number'), (4, N'emergencyRequests', N'Emergency (current)', N'number'),
            (5, N'avgHoursInState', N'Avg hours in state', N'number'), (6, N'shareOfRequests', N'Share of requests %', N'percent');
        SELECT [Key], Label, [Type] FROM #Cols ORDER BY SortOrder;

        CREATE TABLE #Req (RequestId INT NOT NULL PRIMARY KEY, Status NVARCHAR(20), Urgency NVARCHAR(20));
        INSERT INTO #Req (RequestId, Status, Urgency)
        SELECT r.RequestId, r.Status, r.Urgency
        FROM dbo.BloodRequests r
        WHERE (@From IS NULL OR r.CreatedAt >= @From)
          AND (@To IS NULL OR r.CreatedAt < @To)
          AND (@AreaId IS NULL OR r.AreaId = @AreaId)
          AND (@FacilityId IS NULL OR r.MatchedFacilityId = @FacilityId OR r.PreferredFacilityId = @FacilityId
               OR EXISTS (SELECT 1 FROM dbo.BloodRequestHistory h WHERE h.RequestId = r.RequestId AND h.FacilityId = @FacilityId))
          AND (@ViewAll = 1
               OR r.MatchedFacilityId IN (SELECT FacilityId FROM #Fac)
               OR r.PreferredFacilityId IN (SELECT FacilityId FROM #Fac)
               OR (@FacilityId IS NULL AND r.AreaId IN (SELECT f.AreaId FROM dbo.Facilities f INNER JOIN #Fac s ON s.FacilityId = f.FacilityId)));

        DECLARE @ReqTotal INT = (SELECT COUNT(*) FROM #Req);

        ;WITH h AS (
            SELECT bh.RequestId, bh.ToStatus, bh.ChangedAt,
                   LEAD(bh.ChangedAt) OVER (PARTITION BY bh.RequestId ORDER BY bh.ChangedAt, bh.HistoryId) AS LeftAt
            FROM dbo.BloodRequestHistory bh INNER JOIN #Req q ON q.RequestId = bh.RequestId),
        hs AS (
            SELECT h.ToStatus, COUNT(DISTINCT h.RequestId) AS EverReached,
                   AVG(CASE WHEN h.LeftAt IS NOT NULL THEN DATEDIFF(MINUTE, h.ChangedAt, h.LeftAt) / 60.0 END) AS AvgHours
            FROM h GROUP BY h.ToStatus),
        cur AS (
            SELECT q.Status, COUNT(*) AS Cnt, SUM(CASE WHEN q.Urgency = N'Emergency' THEN 1 ELSE 0 END) AS Emergency
            FROM #Req q GROUP BY q.Status)
        SELECT st.Status AS status,
               ISNULL(c.Cnt, 0) AS currentRequests,
               ISNULL(hs.EverReached, 0) AS everReached,
               ISNULL(c.Emergency, 0) AS emergencyRequests,
               CAST(ISNULL(hs.AvgHours, 0) AS DECIMAL(10,1)) AS avgHoursInState,
               CAST(CASE WHEN @ReqTotal = 0 THEN 0 ELSE ROUND(ISNULL(c.Cnt, 0) * 100.0 / @ReqTotal, 1) END AS DECIMAL(5,1)) AS shareOfRequests
        FROM (VALUES (N'Submitted', 1), (N'UnderReview', 2), (N'Matched', 3), (N'Contacted', 4), (N'Fulfilled', 5),
                     (N'UnableToFulfil', 6), (N'Closed', 7), (N'Cancelled', 8)) AS st (Status, SortOrder)
        LEFT JOIN cur c ON c.Status = st.Status
        LEFT JOIN hs ON hs.ToStatus = st.Status
        ORDER BY st.SortOrder;
        RETURN;
    END

    IF @ReportCode = N'FACILITY_RELIABILITY'
    BEGIN
        INSERT INTO #Cols VALUES
            (1, N'facilityName', N'Facility', N'text'), (2, N'facilityType', N'Type', N'text'),
            (3, N'qualityScore', N'Quality score', N'number'), (4, N'updatesSubmitted', N'Updates submitted', N'number'),
            (5, N'updatesPerDay', N'Updates / day', N'number'), (6, N'appliedChanges', N'Applied', N'number'),
            (7, N'rejectedChanges', N'Rejected', N'number'), (8, N'pendingReview', N'Pending review', N'number'),
            (9, N'correctionRate', N'Correction rate %', N'percent'), (10, N'staleRate', N'Stale rate %', N'percent'),
            (11, N'verificationCompletion', N'Verified records %', N'percent'), (12, N'lastUpdateAt', N'Last update', N'date');
        SELECT [Key], Label, [Type] FROM #Cols ORDER BY SortOrder;

        DECLARE @PeriodFrom DATETIME2(0) = ISNULL(@From, DATEADD(DAY, -30, @Now));
        DECLARE @PeriodTo DATETIME2(0) = ISNULL(@To, @Now);
        DECLARE @Days DECIMAL(10,2) = CASE WHEN DATEDIFF(MINUTE, @PeriodFrom, @PeriodTo) < 1440 THEN 1
                                           ELSE DATEDIFF(MINUTE, @PeriodFrom, @PeriodTo) / 1440.0 END;

        ;WITH ch AS (
            SELECT c.FacilityId, COUNT(*) AS Submitted,
                   SUM(CASE WHEN c.Status = N'Applied' THEN 1 ELSE 0 END) AS Applied,
                   SUM(CASE WHEN c.Status = N'Rejected' THEN 1 ELSE 0 END) AS Rejected,
                   SUM(CASE WHEN c.Status = N'PendingReview' THEN 1 ELSE 0 END) AS Pending,
                   SUM(CASE WHEN c.Status = N'Rejected' OR c.SourceType = N'AdminCorrection' THEN 1 ELSE 0 END) AS Corrections
            FROM dbo.InventoryChanges c INNER JOIN #Fac s ON s.FacilityId = c.FacilityId
            WHERE c.SubmittedAt >= @PeriodFrom AND c.SubmittedAt < @PeriodTo
            GROUP BY c.FacilityId),
        recs AS (
            SELECT v.FacilityId, v.FreshnessStatus, v.VerificationStatus
            FROM dbo.vw_BloodAvailability v INNER JOIN #Fac s ON s.FacilityId = v.FacilityId
            UNION ALL
            SELECT v.FacilityId, v.FreshnessStatus, v.VerificationStatus
            FROM dbo.vw_ResourceAvailability v INNER JOIN #Fac s ON s.FacilityId = v.FacilityId),
        rs AS (
            SELECT r.FacilityId, COUNT(*) AS Total,
                   SUM(CASE WHEN r.FreshnessStatus = N'Stale' THEN 1 ELSE 0 END) AS Stale,
                   SUM(CASE WHEN r.VerificationStatus = N'Confirmed' THEN 1 ELSE 0 END) AS Confirmed
            FROM recs r GROUP BY r.FacilityId)
        SELECT f.Name AS facilityName, f.FacilityType AS facilityType,
               CAST(ISNULL(q.QualityScore, 0) AS DECIMAL(5,1)) AS qualityScore,
               ISNULL(ch.Submitted, 0) AS updatesSubmitted,
               CAST(ROUND(ISNULL(ch.Submitted, 0) / @Days, 2) AS DECIMAL(10,2)) AS updatesPerDay,
               ISNULL(ch.Applied, 0) AS appliedChanges,
               ISNULL(ch.Rejected, 0) AS rejectedChanges,
               ISNULL(ch.Pending, 0) AS pendingReview,
               CAST(CASE WHEN ISNULL(ch.Submitted, 0) = 0 THEN 0 ELSE ROUND(ch.Corrections * 100.0 / ch.Submitted, 1) END AS DECIMAL(5,1)) AS correctionRate,
               CAST(CASE WHEN ISNULL(rs.Total, 0) = 0 THEN 0 ELSE ROUND(rs.Stale * 100.0 / rs.Total, 1) END AS DECIMAL(5,1)) AS staleRate,
               CAST(CASE WHEN ISNULL(rs.Total, 0) = 0 THEN 0 ELSE ROUND(rs.Confirmed * 100.0 / rs.Total, 1) END AS DECIMAL(5,1)) AS verificationCompletion,
               q.LastUpdateAt AS lastUpdateAt
        FROM #Fac s
        INNER JOIN dbo.Facilities f ON f.FacilityId = s.FacilityId
        LEFT JOIN dbo.vw_FacilityQualityScore q ON q.FacilityId = f.FacilityId
        LEFT JOIN ch ON ch.FacilityId = f.FacilityId
        LEFT JOIN rs ON rs.FacilityId = f.FacilityId
        WHERE f.IsActive = 1
        ORDER BY qualityScore DESC, f.Name;
        RETURN;
    END

    IF @ReportCode = N'RESOURCE_AVAILABILITY'
    BEGIN
        INSERT INTO #Cols VALUES
            (1, N'resourceTypeName', N'Resource', N'text'), (2, N'categoryName', N'Category', N'text'),
            (3, N'availableQuantity', N'Available', N'number'), (4, N'totalQuantity', N'Total', N'number'),
            (5, N'utilizationPercent', N'Utilisation %', N'percent'), (6, N'reportingFacilities', N'Reporting hospitals', N'number'),
            (7, N'unavailableFacilities', N'Unavailable at', N'number'), (8, N'staleRecords', N'Stale records', N'number'),
            (9, N'lastUpdatedAt', N'Last updated', N'date');
        SELECT [Key], Label, [Type] FROM #Cols ORDER BY SortOrder;

        SELECT v.ResourceTypeName AS resourceTypeName, v.CategoryName AS categoryName,
               CAST(ISNULL(SUM(v.AvailableQuantity), 0) AS DECIMAL(14,2)) AS availableQuantity,
               CAST(ISNULL(SUM(v.TotalQuantity), 0) AS DECIMAL(14,2)) AS totalQuantity,
               CAST(CASE WHEN ISNULL(SUM(v.TotalQuantity), 0) = 0 THEN 0
                         ELSE ROUND((SUM(v.TotalQuantity) - SUM(ISNULL(v.AvailableQuantity, 0))) * 100.0 / SUM(v.TotalQuantity), 1) END
                    AS DECIMAL(5,1)) AS utilizationPercent,
               COUNT(DISTINCT CASE WHEN v.LastUpdatedAt IS NOT NULL THEN v.FacilityId END) AS reportingFacilities,
               COUNT(DISTINCT CASE WHEN v.OperationalStatus = N'Unavailable' THEN v.FacilityId END) AS unavailableFacilities,
               SUM(CASE WHEN v.FreshnessStatus = N'Stale' THEN 1 ELSE 0 END) AS staleRecords,
               MAX(v.LastUpdatedAt) AS lastUpdatedAt
        FROM dbo.vw_ResourceAvailability v
        INNER JOIN #Fac s ON s.FacilityId = v.FacilityId
        INNER JOIN dbo.Facilities f ON f.FacilityId = v.FacilityId AND f.IsActive = 1
        GROUP BY v.ResourceTypeName, v.CategoryName
        ORDER BY v.CategoryName, v.ResourceTypeName;
        RETURN;
    END
END
GO
