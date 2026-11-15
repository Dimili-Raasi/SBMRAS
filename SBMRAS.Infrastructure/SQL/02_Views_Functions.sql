/*=====================================================================
  SBMRAS - 02_Views_Functions.sql
  Permission/scope helpers and read-model views. Freshness is computed
  at read time (no background job) via dbo.fn_FreshnessStatus.
=====================================================================*/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* Integer system setting with fallback (accepts '30' or '30.0'). */
CREATE OR ALTER FUNCTION dbo.fn_GetSettingInt (@Key NVARCHAR(100), @Default INT)
RETURNS INT
AS
BEGIN
    DECLARE @Value NVARCHAR(400) = (SELECT SettingValue FROM dbo.SystemSettings WHERE SettingKey = @Key);
    RETURN COALESCE(TRY_CONVERT(INT, @Value), TRY_CONVERT(INT, TRY_CONVERT(DECIMAL(18,4), @Value)), @Default);
END
GO

/* Returns 1 when an active user holds the permission through any active role. */
CREATE OR ALTER FUNCTION dbo.fn_UserHasPermission (@UserId INT, @Code NVARCHAR(60))
RETURNS BIT
AS
BEGIN
    RETURN CASE WHEN EXISTS (
        SELECT 1
        FROM dbo.Users u
        INNER JOIN dbo.UserRoles ur       ON ur.UserId = u.UserId
        INNER JOIN dbo.Roles r            ON r.RoleId = ur.RoleId AND r.IsActive = 1
        INNER JOIN dbo.RolePermissions rp ON rp.RoleId = r.RoleId
        INNER JOIN dbo.Permissions p      ON p.PermissionId = rp.PermissionId
        WHERE u.UserId = @UserId AND u.IsActive = 1 AND p.PermissionCode = @Code)
    THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END;
END
GO

/* Returns 1 when an active user holds the Admin role. */
CREATE OR ALTER FUNCTION dbo.fn_UserIsAdmin (@UserId INT)
RETURNS BIT
AS
BEGIN
    RETURN CASE WHEN EXISTS (
        SELECT 1
        FROM dbo.Users u
        INNER JOIN dbo.UserRoles ur ON ur.UserId = u.UserId
        INNER JOIN dbo.Roles r      ON r.RoleId = ur.RoleId AND r.IsActive = 1
        WHERE u.UserId = @UserId AND u.IsActive = 1 AND r.RoleCode = N'Admin')
    THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END;
END
GO

/* Facility scope (BR-08/BR-09): data.viewall OR an active assignment to the facility. */
CREATE OR ALTER FUNCTION dbo.fn_UserCanAccessFacility (@UserId INT, @FacilityId INT)
RETURNS BIT
AS
BEGIN
    IF dbo.fn_UserHasPermission(@UserId, N'data.viewall') = 1
        RETURN CAST(1 AS BIT);

    RETURN CASE WHEN EXISTS (
        SELECT 1
        FROM dbo.FacilityUserAssignments a
        INNER JOIN dbo.Users u ON u.UserId = a.UserId AND u.IsActive = 1
        WHERE a.UserId = @UserId AND a.FacilityId = @FacilityId AND a.IsActive = 1)
    THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END;
END
GO

/* UnderReview | Unknown | Stale | Aging | Fresh, evaluated against SYSUTCDATETIME() at read time. */
CREATE OR ALTER FUNCTION dbo.fn_FreshnessStatus (@LastUpdatedAt DATETIME2(0), @ValidUntil DATETIME2(0), @VerificationStatus NVARCHAR(20))
RETURNS NVARCHAR(20)
AS
BEGIN
    IF @VerificationStatus = N'PendingReview' RETURN N'UnderReview';
    IF @LastUpdatedAt IS NULL OR @ValidUntil IS NULL RETURN N'Unknown';

    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
    IF @ValidUntil < @Now RETURN N'Stale';

    DECLARE @AgingPercent BIGINT = dbo.fn_GetSettingInt(N'AGING_THRESHOLD_PERCENT', 75);
    DECLARE @Window BIGINT = DATEDIFF_BIG(SECOND, @LastUpdatedAt, @ValidUntil);
    DECLARE @Elapsed BIGINT = DATEDIFF_BIG(SECOND, @LastUpdatedAt, @Now);

    IF @Window <= 0 OR @Elapsed * 100 >= @AgingPercent * @Window RETURN N'Aging';
    RETURN N'Fresh';
END
GO

CREATE OR ALTER VIEW dbo.vw_UserPermissions
AS
SELECT DISTINCT u.UserId, p.PermissionId, p.PermissionCode, p.Module
FROM dbo.Users u
INNER JOIN dbo.UserRoles ur       ON ur.UserId = u.UserId
INNER JOIN dbo.Roles r            ON r.RoleId = ur.RoleId AND r.IsActive = 1
INNER JOIN dbo.RolePermissions rp ON rp.RoleId = r.RoleId
INNER JOIN dbo.Permissions p      ON p.PermissionId = rp.PermissionId
WHERE u.IsActive = 1;
GO

/*---------------------------------------------------------------------
  Facility data-quality score (SDD 13.1). Weights from SystemSettings
  QUALITY_WEIGHT_* (defaults 30/30/25/15). All component scores 0..100.
---------------------------------------------------------------------*/
CREATE OR ALTER VIEW dbo.vw_FacilityQualityScore
AS
WITH Records AS
(
    SELECT bi.FacilityId,
           dbo.fn_FreshnessStatus(bi.LastUpdatedAt, bi.ValidUntil, bi.VerificationStatus) AS FreshnessStatus,
           bi.VerificationStatus,
           bi.LastUpdatedAt,
           CASE WHEN bi.LastUpdatedAt IS NOT NULL AND bi.ValidUntil IS NOT NULL
                 AND (bi.Quantity = 0 OR bi.EarliestExpiryDate IS NOT NULL)
                THEN 1 ELSE 0 END AS IsComplete
    FROM dbo.BloodInventory bi
    UNION ALL
    SELECT mri.FacilityId,
           dbo.fn_FreshnessStatus(mri.LastUpdatedAt, mri.ValidUntil, mri.VerificationStatus),
           mri.VerificationStatus,
           mri.LastUpdatedAt,
           CASE WHEN mri.LastUpdatedAt IS NOT NULL AND mri.ValidUntil IS NOT NULL
                 AND mri.OperationalStatus <> N'Unknown'
                THEN 1 ELSE 0 END
    FROM dbo.MedicalResourceInventory mri
),
Agg AS
(
    SELECT r.FacilityId,
           COUNT(*) AS TotalRecords,
           SUM(CASE WHEN r.FreshnessStatus = N'Fresh' THEN 1 ELSE 0 END)       AS Fresh,
           SUM(CASE WHEN r.FreshnessStatus = N'Aging' THEN 1 ELSE 0 END)       AS Aging,
           SUM(CASE WHEN r.FreshnessStatus = N'Stale' THEN 1 ELSE 0 END)       AS Stale,
           SUM(CASE WHEN r.FreshnessStatus = N'Unknown' THEN 1 ELSE 0 END)     AS Unknown,
           SUM(CASE WHEN r.FreshnessStatus = N'UnderReview' THEN 1 ELSE 0 END) AS UnderReview,
           SUM(CASE WHEN r.VerificationStatus = N'Confirmed' THEN 1 ELSE 0 END) AS Confirmed,
           SUM(r.IsComplete) AS Complete,
           MAX(r.LastUpdatedAt) AS LastUpdateAt
    FROM Records r
    GROUP BY r.FacilityId
),
Issues AS
(
    SELECT vi.FacilityId,
           COUNT(*) AS OpenIssues,
           SUM(CASE vi.Severity WHEN N'High' THEN 20 WHEN N'Medium' THEN 10 ELSE 5 END) AS Penalty
    FROM dbo.ValidationIssues vi
    WHERE vi.Status = N'Open'
    GROUP BY vi.FacilityId
),
Weights AS
(
    SELECT CAST(dbo.fn_GetSettingInt(N'QUALITY_WEIGHT_COMPLETENESS', 30) AS DECIMAL(9,4)) AS WCompleteness,
           CAST(dbo.fn_GetSettingInt(N'QUALITY_WEIGHT_RECENCY', 30) AS DECIMAL(9,4))      AS WRecency,
           CAST(dbo.fn_GetSettingInt(N'QUALITY_WEIGHT_VERIFICATION', 25) AS DECIMAL(9,4)) AS WVerification,
           CAST(dbo.fn_GetSettingInt(N'QUALITY_WEIGHT_ANOMALY', 15) AS DECIMAL(9,4))      AS WAnomaly
),
Scores AS
(
    SELECT f.FacilityId, f.FacilityCode, f.Name AS FacilityName, f.FacilityType, f.AreaId,
           f.VerificationStatus, f.IsActive,
           ISNULL(a.TotalRecords, 0) AS TotalRecords,
           ISNULL(a.Fresh, 0) AS Fresh, ISNULL(a.Aging, 0) AS Aging, ISNULL(a.Stale, 0) AS Stale,
           ISNULL(a.Unknown, 0) AS Unknown, ISNULL(a.UnderReview, 0) AS UnderReview,
           ISNULL(i.OpenIssues, 0) AS OpenIssues,
           a.LastUpdateAt,
           CAST(CASE WHEN ISNULL(a.TotalRecords, 0) = 0 THEN 0
                     ELSE 100.0 * a.Complete / a.TotalRecords END AS DECIMAL(5,2)) AS CompletenessScore,
           CAST(CASE WHEN ISNULL(a.TotalRecords, 0) = 0 THEN 0
                     ELSE 100.0 * (a.Fresh + a.Aging) / a.TotalRecords END AS DECIMAL(5,2)) AS RecencyScore,
           CAST(CASE WHEN ISNULL(a.TotalRecords, 0) = 0 THEN 0
                     ELSE 100.0 * a.Confirmed / a.TotalRecords END AS DECIMAL(5,2)) AS VerificationScore,
           CAST(CASE WHEN 100 - ISNULL(i.Penalty, 0) < 0 THEN 0 ELSE 100 - ISNULL(i.Penalty, 0) END AS DECIMAL(5,2)) AS AnomalyScore,
           CAST(CASE WHEN ISNULL(a.TotalRecords, 0) = 0 THEN 0
                     ELSE 100.0 * a.Fresh / a.TotalRecords END AS DECIMAL(5,2)) AS FreshPercent
    FROM dbo.Facilities f
    LEFT JOIN Agg a    ON a.FacilityId = f.FacilityId
    LEFT JOIN Issues i ON i.FacilityId = f.FacilityId
)
SELECT s.FacilityId, s.FacilityCode, s.FacilityName, s.FacilityType, s.AreaId, s.VerificationStatus, s.IsActive,
       s.TotalRecords, s.Fresh, s.Aging, s.Stale, s.Unknown, s.UnderReview, s.OpenIssues,
       s.Stale AS StaleRecords, s.FreshPercent,
       s.CompletenessScore, s.RecencyScore, s.VerificationScore, s.AnomalyScore,
       CAST(CASE WHEN w.WCompleteness + w.WRecency + w.WVerification + w.WAnomaly <= 0 THEN 0
                 ELSE (w.WCompleteness * s.CompletenessScore + w.WRecency * s.RecencyScore
                       + w.WVerification * s.VerificationScore + w.WAnomaly * s.AnomalyScore)
                      / (w.WCompleteness + w.WRecency + w.WVerification + w.WAnomaly) END AS DECIMAL(5,2)) AS QualityScore,
       s.LastUpdateAt
FROM Scores s
CROSS JOIN Weights w;
GO

CREATE OR ALTER VIEW dbo.vw_BloodAvailability
AS
SELECT bi.InventoryId,
       bi.FacilityId, f.FacilityCode, f.Name AS FacilityName, f.FacilityType,
       f.VerificationStatus AS FacilityVerificationStatus, f.IsActive AS FacilityIsActive,
       f.AreaId, ar.Name AS AreaName, f.City, f.AddressLine, f.Pincode, f.Latitude, f.Longitude,
       f.ContactPhone, f.ContactEmail, f.Is24x7,
       bi.ComponentId, bc.Code AS ComponentCode, bc.Name AS ComponentName,
       bi.AboGroup, bi.RhFactor,
       bi.AboGroup + CASE bi.RhFactor WHEN N'Positive' THEN N'+' ELSE N'-' END AS BloodGroup,
       bi.Quantity, bi.UnitId, un.Code AS UnitCode, un.Name AS UnitName,
       bi.EarliestExpiryDate,
       CASE WHEN bi.LastUpdatedAt IS NULL THEN N'Unknown'
            WHEN bi.Quantity = 0 THEN N'OutOfStock'
            WHEN bi.Quantity < st.LowStockThreshold THEN N'Low'
            ELSE N'Available' END AS AvailabilityStatus,
       dbo.fn_FreshnessStatus(bi.LastUpdatedAt, bi.ValidUntil, bi.VerificationStatus) AS FreshnessStatus,
       bi.VerificationStatus, bi.SourceType,
       bi.LastUpdatedAt, bi.LastUpdatedBy, lu.DisplayName AS LastUpdatedByName,
       bi.ValidUntil,
       DATEDIFF(MINUTE, bi.LastUpdatedAt, SYSUTCDATETIME()) AS MinutesSinceUpdate,
       q.QualityScore,
       bi.RowVer AS RowVersion
FROM dbo.BloodInventory bi
INNER JOIN dbo.Facilities f       ON f.FacilityId = bi.FacilityId
INNER JOIN dbo.Areas ar           ON ar.AreaId = f.AreaId
INNER JOIN dbo.BloodComponents bc ON bc.ComponentId = bi.ComponentId
INNER JOIN dbo.Units un           ON un.UnitId = bi.UnitId
LEFT JOIN dbo.Users lu            ON lu.UserId = bi.LastUpdatedBy
LEFT JOIN dbo.vw_FacilityQualityScore q ON q.FacilityId = bi.FacilityId
CROSS JOIN (SELECT dbo.fn_GetSettingInt(N'LOW_STOCK_THRESHOLD_UNITS', 5) AS LowStockThreshold) st;
GO

CREATE OR ALTER VIEW dbo.vw_ResourceAvailability
AS
SELECT mri.ResourceInventoryId,
       mri.FacilityId, f.FacilityCode, f.Name AS FacilityName, f.FacilityType,
       f.VerificationStatus AS FacilityVerificationStatus, f.IsActive AS FacilityIsActive,
       f.AreaId, ar.Name AS AreaName, f.City, f.AddressLine, f.Pincode, f.Latitude, f.Longitude,
       f.ContactPhone, f.ContactEmail, f.Is24x7,
       rt.CategoryId, rc.Name AS CategoryName,
       mri.ResourceTypeId, rt.Code AS ResourceTypeCode, rt.Name AS ResourceTypeName, rt.TrackingMode,
       mri.TotalQuantity, mri.AvailableQuantity,
       mri.UnitId, un.Code AS UnitCode, un.Name AS UnitName,
       mri.OperationalStatus, mri.Notes,
       dbo.fn_FreshnessStatus(mri.LastUpdatedAt, mri.ValidUntil, mri.VerificationStatus) AS FreshnessStatus,
       mri.VerificationStatus, mri.SourceType,
       mri.LastUpdatedAt, mri.LastUpdatedBy, lu.DisplayName AS LastUpdatedByName,
       mri.ValidUntil,
       DATEDIFF(MINUTE, mri.LastUpdatedAt, SYSUTCDATETIME()) AS MinutesSinceUpdate,
       q.QualityScore,
       mri.RowVer AS RowVersion
FROM dbo.MedicalResourceInventory mri
INNER JOIN dbo.Facilities f             ON f.FacilityId = mri.FacilityId
INNER JOIN dbo.Areas ar                 ON ar.AreaId = f.AreaId
INNER JOIN dbo.MedicalResourceTypes rt  ON rt.ResourceTypeId = mri.ResourceTypeId
INNER JOIN dbo.ResourceCategories rc    ON rc.CategoryId = rt.CategoryId
INNER JOIN dbo.Units un                 ON un.UnitId = mri.UnitId
LEFT JOIN dbo.Users lu                  ON lu.UserId = mri.LastUpdatedBy
LEFT JOIN dbo.vw_FacilityQualityScore q ON q.FacilityId = mri.FacilityId;
GO

CREATE OR ALTER VIEW dbo.vw_BloodRequests
AS
SELECT br.RequestId, br.RequestNo,
       br.RequesterUserId, ru.DisplayName AS RequesterName, ru.Email AS RequesterEmail,
       br.PatientReference, br.AboGroup, br.RhFactor,
       br.AboGroup + CASE br.RhFactor WHEN N'Positive' THEN N'+' ELSE N'-' END AS BloodGroup,
       br.ComponentId, bc.Code AS ComponentCode, bc.Name AS ComponentName,
       br.QuantityRequested, br.UnitId, un.Code AS UnitCode,
       br.Urgency, br.NeededBy,
       br.AreaId, ar.Name AS AreaName,
       br.HospitalName,
       br.PreferredFacilityId, pf.Name AS PreferredFacilityName,
       br.MatchedFacilityId, mf.Name AS MatchedFacilityName, mf.ContactPhone AS MatchedFacilityPhone,
       br.ContactName, br.ContactPhone, br.ContactConsent, br.Notes,
       br.Status, br.StatusReason, br.IdempotencyKey,
       br.CreatedAt, br.CreatedBy, br.UpdatedAt, br.UpdatedBy,
       br.RowVer AS RowVersion
FROM dbo.BloodRequests br
INNER JOIN dbo.Users ru           ON ru.UserId = br.RequesterUserId
INNER JOIN dbo.BloodComponents bc ON bc.ComponentId = br.ComponentId
INNER JOIN dbo.Units un           ON un.UnitId = br.UnitId
INNER JOIN dbo.Areas ar           ON ar.AreaId = br.AreaId
LEFT JOIN dbo.Facilities pf       ON pf.FacilityId = br.PreferredFacilityId
LEFT JOIN dbo.Facilities mf       ON mf.FacilityId = br.MatchedFacilityId;
GO
