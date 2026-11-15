/*=====================================================================
  SBMRAS - 09_StoredProcedures_Public_Requests.sql
  Anonymous public search (blood, medical resources, facility directory,
  headline stats) and the blood request lifecycle (create, search,
  details, cancel, status state machine, facility matches).
  Public procedures accept @ActorUserId = 0 (anonymous caller), only
  return Verified + active facilities and never return requester data.
=====================================================================*/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*---------------------------------------------------------------------
  Public (anonymous)
---------------------------------------------------------------------*/

/* Landing page headline numbers (Verified + active facilities only). */
CREATE OR ALTER PROCEDURE dbo.usp_Public_GetStats
    @ActorUserId INT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @VerifiedFacilities INT, @Hospitals INT, @BloodBanks INT;
    SELECT @VerifiedFacilities = COUNT(*),
           @Hospitals = SUM(CASE WHEN f.FacilityType = N'Hospital' THEN 1 ELSE 0 END),
           @BloodBanks = SUM(CASE WHEN f.FacilityType = N'BloodBank' THEN 1 ELSE 0 END)
    FROM dbo.Facilities f
    WHERE f.VerificationStatus = N'Verified' AND f.IsActive = 1;

    DECLARE @UnitsAvailable DECIMAL(14,2), @BloodRecords INT, @BloodCurrent INT, @BloodLast DATETIME2(0);
    SELECT @UnitsAvailable = SUM(CASE WHEN v.FreshnessStatus IN (N'Fresh', N'Aging', N'UnderReview') THEN v.Quantity ELSE 0 END),
           @BloodRecords = COUNT(*),
           @BloodCurrent = SUM(CASE WHEN v.FreshnessStatus IN (N'Fresh', N'Aging') THEN 1 ELSE 0 END),
           @BloodLast = MAX(v.LastUpdatedAt)
    FROM dbo.vw_BloodAvailability v
    INNER JOIN dbo.Facilities f ON f.FacilityId = v.FacilityId AND f.VerificationStatus = N'Verified' AND f.IsActive = 1;

    DECLARE @ResourceRecords INT, @ResourceCurrent INT, @ResourceLast DATETIME2(0);
    SELECT @ResourceRecords = COUNT(*),
           @ResourceCurrent = SUM(CASE WHEN v.FreshnessStatus IN (N'Fresh', N'Aging') THEN 1 ELSE 0 END),
           @ResourceLast = MAX(v.LastUpdatedAt)
    FROM dbo.vw_ResourceAvailability v
    INNER JOIN dbo.Facilities f ON f.FacilityId = v.FacilityId AND f.VerificationStatus = N'Verified' AND f.IsActive = 1;

    DECLARE @OpenRequests INT, @FulfilledRequests INT;
    SELECT @OpenRequests = SUM(CASE WHEN r.Status IN (N'Submitted', N'UnderReview', N'Matched', N'Contacted') THEN 1 ELSE 0 END),
           @FulfilledRequests = SUM(CASE WHEN r.Status = N'Fulfilled'
                                          OR (r.Status = N'Closed' AND fh.RequestId IS NOT NULL)
                                         THEN 1 ELSE 0 END)
    FROM dbo.BloodRequests r
    LEFT JOIN (SELECT DISTINCT RequestId FROM dbo.BloodRequestHistory WHERE ToStatus = N'Fulfilled') fh ON fh.RequestId = r.RequestId;

    DECLARE @Records INT = ISNULL(@BloodRecords, 0) + ISNULL(@ResourceRecords, 0);
    DECLARE @Current INT = ISNULL(@BloodCurrent, 0) + ISNULL(@ResourceCurrent, 0);

    SELECT ISNULL(@VerifiedFacilities, 0) AS VerifiedFacilities,
           ISNULL(@Hospitals, 0) AS Hospitals,
           ISNULL(@BloodBanks, 0) AS BloodBanks,
           CAST(ISNULL(@UnitsAvailable, 0) AS DECIMAL(14,2)) AS UnitsAvailable,
           CAST(CASE WHEN @Records = 0 THEN 0 ELSE ROUND(@Current * 100.0 / @Records, 1) END AS DECIMAL(5,1)) AS FreshPercent,
           ISNULL(@OpenRequests, 0) AS OpenRequests,
           ISNULL(@FulfilledRequests, 0) AS FulfilledRequests,
           CASE WHEN @ResourceLast IS NULL OR @BloodLast >= @ResourceLast THEN @BloodLast ELSE @ResourceLast END AS LastUpdatedAt;
END
GO

/*
  Public blood availability search (paged). @FreshOnly = 1 (default) hides Stale and Unknown records.
  Ranking: freshness (Fresh, Aging, UnderReview, Stale, Unknown), then quantity, then facility name.
  Result sets: 1 rows, 2 TotalCount.
*/
CREATE OR ALTER PROCEDURE dbo.usp_Public_SearchBlood
    @ActorUserId INT = 0,
    @AboGroup    NVARCHAR(2) = NULL,
    @RhFactor    NVARCHAR(10) = NULL,
    @ComponentId INT = NULL,
    @AreaId      INT = NULL,
    @Search      NVARCHAR(200) = NULL,
    @FreshOnly   BIT = 1,
    @MinQuantity DECIMAL(12,2) = NULL,
    @Page        INT = 1,
    @PageSize    INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Page = CASE WHEN ISNULL(@Page, 1) < 1 THEN 1 ELSE @Page END;
    SET @PageSize = CASE WHEN ISNULL(@PageSize, 20) < 1 THEN 20 WHEN @PageSize > 100 THEN 100 ELSE @PageSize END;
    SET @AboGroup = NULLIF(LTRIM(RTRIM(@AboGroup)), N'');
    SET @RhFactor = NULLIF(LTRIM(RTRIM(@RhFactor)), N'');
    SET @Search = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @FreshOnly = ISNULL(@FreshOnly, 1);
    IF @MinQuantity <= 0 SET @MinQuantity = NULL;

    IF @AboGroup IS NOT NULL AND @AboGroup NOT IN (N'A', N'B', N'AB', N'O')
        THROW 50400, N'ABO group must be A, B, AB or O.', 1;
    IF @RhFactor IS NOT NULL AND @RhFactor NOT IN (N'Positive', N'Negative')
        THROW 50400, N'Rh factor must be Positive or Negative.', 1;

    SELECT v.InventoryId, v.FacilityId, v.FacilityName, v.FacilityType, v.AreaId, v.AreaName, v.City, v.AddressLine,
           v.ContactPhone, v.Is24x7, v.ComponentId, v.ComponentCode, v.ComponentName, v.AboGroup, v.RhFactor, v.BloodGroup,
           v.Quantity, v.UnitCode, v.AvailabilityStatus, v.FreshnessStatus, v.VerificationStatus, v.SourceType,
           v.LastUpdatedAt, v.ValidUntil, v.MinutesSinceUpdate, v.EarliestExpiryDate, v.QualityScore,
           CASE v.FreshnessStatus WHEN N'Fresh' THEN 1 WHEN N'Aging' THEN 2 WHEN N'UnderReview' THEN 3 WHEN N'Stale' THEN 4 ELSE 5 END AS FreshRank
    INTO #Rows
    FROM dbo.vw_BloodAvailability v
    INNER JOIN dbo.Facilities f ON f.FacilityId = v.FacilityId AND f.VerificationStatus = N'Verified' AND f.IsActive = 1
    WHERE (@AboGroup IS NULL OR v.AboGroup = @AboGroup)
      AND (@RhFactor IS NULL OR v.RhFactor = @RhFactor)
      AND (@ComponentId IS NULL OR v.ComponentId = @ComponentId)
      AND (@AreaId IS NULL OR v.AreaId = @AreaId)
      AND (@FreshOnly = 0 OR v.FreshnessStatus NOT IN (N'Stale', N'Unknown'))
      AND (@MinQuantity IS NULL OR v.Quantity >= @MinQuantity)
      AND (@Search IS NULL OR v.FacilityName LIKE N'%' + @Search + N'%' OR v.AreaName LIKE N'%' + @Search + N'%'
           OR v.City LIKE N'%' + @Search + N'%' OR v.AddressLine LIKE N'%' + @Search + N'%');

    SELECT r.InventoryId, r.FacilityId, r.FacilityName, r.FacilityType, r.AreaId, r.AreaName, r.City, r.AddressLine,
           r.ContactPhone, r.Is24x7, r.ComponentId, r.ComponentCode, r.ComponentName, r.AboGroup, r.RhFactor, r.BloodGroup,
           r.Quantity, r.UnitCode, r.AvailabilityStatus, r.FreshnessStatus, r.VerificationStatus, r.SourceType,
           r.LastUpdatedAt, r.ValidUntil, r.MinutesSinceUpdate, r.EarliestExpiryDate, r.QualityScore
    FROM #Rows r
    ORDER BY r.FreshRank, CASE WHEN r.Quantity > 0 THEN 0 ELSE 1 END, r.Quantity DESC, r.FacilityName, r.InventoryId
    OFFSET (@Page - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT COUNT(*) AS TotalCount FROM #Rows;
END
GO

/*
  Public medical resource search (paged). @FreshOnly = 1 (default) hides Stale and Unknown records;
  @AvailableOnly = 1 keeps rows with available quantity or Available/Limited status.
*/
CREATE OR ALTER PROCEDURE dbo.usp_Public_SearchResources
    @ActorUserId    INT = 0,
    @CategoryId     INT = NULL,
    @ResourceTypeId INT = NULL,
    @AreaId         INT = NULL,
    @Search         NVARCHAR(200) = NULL,
    @AvailableOnly  BIT = 0,
    @FreshOnly      BIT = 1,
    @Page           INT = 1,
    @PageSize       INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Page = CASE WHEN ISNULL(@Page, 1) < 1 THEN 1 ELSE @Page END;
    SET @PageSize = CASE WHEN ISNULL(@PageSize, 20) < 1 THEN 20 WHEN @PageSize > 100 THEN 100 ELSE @PageSize END;
    SET @Search = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @AvailableOnly = ISNULL(@AvailableOnly, 0);
    SET @FreshOnly = ISNULL(@FreshOnly, 1);

    SELECT v.ResourceInventoryId, v.FacilityId, v.FacilityName, v.AreaId, v.AreaName, v.City, v.ContactPhone, v.Is24x7,
           v.CategoryName, v.ResourceTypeId, v.ResourceTypeCode, v.ResourceTypeName, v.TotalQuantity, v.AvailableQuantity,
           v.UnitCode, v.OperationalStatus, v.FreshnessStatus, v.VerificationStatus, v.LastUpdatedAt, v.ValidUntil,
           v.MinutesSinceUpdate, v.Notes,
           CASE v.FreshnessStatus WHEN N'Fresh' THEN 1 WHEN N'Aging' THEN 2 WHEN N'UnderReview' THEN 3 WHEN N'Stale' THEN 4 ELSE 5 END AS FreshRank
    INTO #Rows
    FROM dbo.vw_ResourceAvailability v
    INNER JOIN dbo.Facilities f ON f.FacilityId = v.FacilityId AND f.VerificationStatus = N'Verified' AND f.IsActive = 1
    WHERE (@CategoryId IS NULL OR v.CategoryId = @CategoryId)
      AND (@ResourceTypeId IS NULL OR v.ResourceTypeId = @ResourceTypeId)
      AND (@AreaId IS NULL OR v.AreaId = @AreaId)
      AND (@FreshOnly = 0 OR v.FreshnessStatus NOT IN (N'Stale', N'Unknown'))
      AND (@AvailableOnly = 0 OR v.AvailableQuantity > 0 OR v.OperationalStatus IN (N'Available', N'Limited'))
      AND (@Search IS NULL OR v.FacilityName LIKE N'%' + @Search + N'%' OR v.AreaName LIKE N'%' + @Search + N'%'
           OR v.City LIKE N'%' + @Search + N'%' OR v.ResourceTypeName LIKE N'%' + @Search + N'%'
           OR v.CategoryName LIKE N'%' + @Search + N'%');

    SELECT r.ResourceInventoryId, r.FacilityId, r.FacilityName, r.AreaId, r.AreaName, r.City, r.ContactPhone, r.Is24x7,
           r.CategoryName, r.ResourceTypeId, r.ResourceTypeCode, r.ResourceTypeName, r.TotalQuantity, r.AvailableQuantity,
           r.UnitCode, r.OperationalStatus, r.FreshnessStatus, r.VerificationStatus, r.LastUpdatedAt, r.ValidUntil,
           r.MinutesSinceUpdate, r.Notes
    FROM #Rows r
    ORDER BY r.FreshRank, CASE WHEN r.AvailableQuantity > 0 THEN 0 ELSE 1 END, r.AvailableQuantity DESC, r.FacilityName, r.ResourceInventoryId
    OFFSET (@Page - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT COUNT(*) AS TotalCount FROM #Rows;
END
GO

/* Public facility directory (paged): Verified + active facilities with quality score and last update. */
CREATE OR ALTER PROCEDURE dbo.usp_Public_SearchFacilities
    @ActorUserId  INT = 0,
    @FacilityType NVARCHAR(20) = NULL,
    @AreaId       INT = NULL,
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

    DECLARE @Total INT = (
        SELECT COUNT(*)
        FROM dbo.Facilities f
        INNER JOIN dbo.Areas a ON a.AreaId = f.AreaId
        WHERE f.VerificationStatus = N'Verified' AND f.IsActive = 1
          AND (@FacilityType IS NULL OR f.FacilityType = @FacilityType)
          AND (@AreaId IS NULL OR f.AreaId = @AreaId)
          AND (@Search IS NULL OR f.Name LIKE N'%' + @Search + N'%' OR f.FacilityCode LIKE N'%' + @Search + N'%'
               OR a.Name LIKE N'%' + @Search + N'%' OR f.City LIKE N'%' + @Search + N'%' OR f.AddressLine LIKE N'%' + @Search + N'%'));

    SELECT f.FacilityId, f.FacilityCode, f.Name, f.FacilityType, f.AddressLine, a.Name AS AreaName, f.City,
           f.ContactPhone, f.ContactEmail, f.Is24x7, q.QualityScore, q.LastUpdateAt
    FROM dbo.Facilities f
    INNER JOIN dbo.Areas a ON a.AreaId = f.AreaId
    LEFT JOIN dbo.vw_FacilityQualityScore q ON q.FacilityId = f.FacilityId
    WHERE f.VerificationStatus = N'Verified' AND f.IsActive = 1
      AND (@FacilityType IS NULL OR f.FacilityType = @FacilityType)
      AND (@AreaId IS NULL OR f.AreaId = @AreaId)
      AND (@Search IS NULL OR f.Name LIKE N'%' + @Search + N'%' OR f.FacilityCode LIKE N'%' + @Search + N'%'
           OR a.Name LIKE N'%' + @Search + N'%' OR f.City LIKE N'%' + @Search + N'%' OR f.AddressLine LIKE N'%' + @Search + N'%')
    ORDER BY f.Name, f.FacilityId
    OFFSET (@Page - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT ISNULL(@Total, 0) AS TotalCount;
END
GO

/*---------------------------------------------------------------------
  Blood requests
---------------------------------------------------------------------*/

/*
  Internal: returns a single BloodRequest row shaped for the caller
  (ContactName / ContactPhone only for the owner or requests.manage holders).
*/
CREATE OR ALTER PROCEDURE dbo.usp_Request_GetRow
    @ActorUserId INT,
    @RequestId   INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @CanManage BIT = dbo.fn_UserHasPermission(@ActorUserId, N'requests.manage');

    SELECT v.RequestId, v.RequestNo, v.RequesterUserId, v.RequesterName, v.PatientReference, v.AboGroup, v.RhFactor, v.BloodGroup,
           v.ComponentId, v.ComponentCode, v.ComponentName, v.QuantityRequested, v.UnitId, v.UnitCode, v.Urgency, v.NeededBy,
           v.AreaId, v.AreaName, v.HospitalName, v.PreferredFacilityId, v.PreferredFacilityName, v.MatchedFacilityId,
           v.MatchedFacilityName, v.MatchedFacilityPhone,
           CASE WHEN v.RequesterUserId = @ActorUserId OR @CanManage = 1 THEN v.ContactName END AS ContactName,
           CASE WHEN v.RequesterUserId = @ActorUserId OR @CanManage = 1 THEN v.ContactPhone END AS ContactPhone,
           v.Notes, v.Status, v.StatusReason,
           CAST(CASE WHEN v.RequesterUserId = @ActorUserId THEN 1 ELSE 0 END AS BIT) AS IsOwner,
           v.CreatedAt, v.UpdatedAt, v.RowVersion
    FROM dbo.vw_BloodRequests v
    WHERE v.RequestId = @RequestId;
END
GO

/*
  Paged blood requests. @Scope = 'mine' (default) returns the caller's own requests;
  @Scope = 'all' is honoured only for requests.manage holders.
*/
CREATE OR ALTER PROCEDURE dbo.usp_Request_Search
    @ActorUserId INT,
    @Scope       NVARCHAR(10) = N'mine',
    @Status      NVARCHAR(20) = NULL,
    @Urgency     NVARCHAR(20) = NULL,
    @AboGroup    NVARCHAR(2) = NULL,
    @AreaId      INT = NULL,
    @Search      NVARCHAR(200) = NULL,
    @Page        INT = 1,
    @PageSize    INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'requests.view') = 0
        THROW 50403, N'You do not have permission to view blood requests.', 1;

    DECLARE @CanManage BIT = dbo.fn_UserHasPermission(@ActorUserId, N'requests.manage');
    DECLARE @All BIT = CASE WHEN LOWER(LTRIM(RTRIM(ISNULL(@Scope, N'mine')))) = N'all' AND @CanManage = 1 THEN 1 ELSE 0 END;

    SET @Page = CASE WHEN ISNULL(@Page, 1) < 1 THEN 1 ELSE @Page END;
    SET @PageSize = CASE WHEN ISNULL(@PageSize, 20) < 1 THEN 20 WHEN @PageSize > 100 THEN 100 ELSE @PageSize END;
    SET @Status = NULLIF(LTRIM(RTRIM(@Status)), N'');
    SET @Urgency = NULLIF(LTRIM(RTRIM(@Urgency)), N'');
    SET @AboGroup = NULLIF(LTRIM(RTRIM(@AboGroup)), N'');
    SET @Search = NULLIF(LTRIM(RTRIM(@Search)), N'');

    SELECT v.RequestId, v.RequestNo, v.RequesterUserId, v.RequesterName, v.PatientReference, v.AboGroup, v.RhFactor, v.BloodGroup,
           v.ComponentId, v.ComponentCode, v.ComponentName, v.QuantityRequested, v.UnitId, v.UnitCode, v.Urgency, v.NeededBy,
           v.AreaId, v.AreaName, v.HospitalName, v.PreferredFacilityId, v.PreferredFacilityName, v.MatchedFacilityId,
           v.MatchedFacilityName, v.MatchedFacilityPhone,
           CASE WHEN v.RequesterUserId = @ActorUserId OR @CanManage = 1 THEN v.ContactName END AS ContactName,
           CASE WHEN v.RequesterUserId = @ActorUserId OR @CanManage = 1 THEN v.ContactPhone END AS ContactPhone,
           v.Notes, v.Status, v.StatusReason,
           CAST(CASE WHEN v.RequesterUserId = @ActorUserId THEN 1 ELSE 0 END AS BIT) AS IsOwner,
           v.CreatedAt, v.UpdatedAt, v.RowVersion
    INTO #Rows
    FROM dbo.vw_BloodRequests v
    WHERE (@All = 1 OR v.RequesterUserId = @ActorUserId)
      AND (@Status IS NULL OR v.Status = @Status)
      AND (@Urgency IS NULL OR v.Urgency = @Urgency)
      AND (@AboGroup IS NULL OR v.AboGroup = @AboGroup)
      AND (@AreaId IS NULL OR v.AreaId = @AreaId)
      AND (@Search IS NULL OR v.RequestNo LIKE N'%' + @Search + N'%' OR v.HospitalName LIKE N'%' + @Search + N'%'
           OR v.PatientReference LIKE N'%' + @Search + N'%' OR v.ComponentName LIKE N'%' + @Search + N'%'
           OR (@All = 1 AND v.RequesterName LIKE N'%' + @Search + N'%'));

    SELECT r.RequestId, r.RequestNo, r.RequesterUserId, r.RequesterName, r.PatientReference, r.AboGroup, r.RhFactor, r.BloodGroup,
           r.ComponentId, r.ComponentCode, r.ComponentName, r.QuantityRequested, r.UnitId, r.UnitCode, r.Urgency, r.NeededBy,
           r.AreaId, r.AreaName, r.HospitalName, r.PreferredFacilityId, r.PreferredFacilityName, r.MatchedFacilityId,
           r.MatchedFacilityName, r.MatchedFacilityPhone, r.ContactName, r.ContactPhone, r.Notes, r.Status, r.StatusReason,
           r.IsOwner, r.CreatedAt, r.UpdatedAt, r.RowVersion
    FROM #Rows r
    ORDER BY CASE WHEN @All = 1 AND r.Status IN (N'Submitted', N'UnderReview', N'Matched', N'Contacted') THEN 0 ELSE 1 END,
             CASE WHEN @All = 1 THEN CASE r.Urgency WHEN N'Emergency' THEN 0 WHEN N'Urgent' THEN 1 ELSE 2 END ELSE 0 END,
             r.CreatedAt DESC, r.RequestId DESC
    OFFSET (@Page - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT COUNT(*) AS TotalCount FROM #Rows;
END
GO

/*
  Request details. Visible to the owner or requests.manage holders (otherwise 404).
  Result sets: 1 request row; 2 history; 3 allowed transitions for the caller (ToStatus).
*/
CREATE OR ALTER PROCEDURE dbo.usp_Request_GetById
    @ActorUserId INT,
    @RequestId   INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @CanManage BIT = dbo.fn_UserHasPermission(@ActorUserId, N'requests.manage');
    DECLARE @RequesterUserId INT, @Status NVARCHAR(20);
    SELECT @RequesterUserId = RequesterUserId, @Status = Status FROM dbo.BloodRequests WHERE RequestId = @RequestId;

    IF @RequesterUserId IS NULL OR (@RequesterUserId <> @ActorUserId AND @CanManage = 0)
        THROW 50404, N'Blood request not found.', 1;

    EXEC dbo.usp_Request_GetRow @ActorUserId = @ActorUserId, @RequestId = @RequestId;

    SELECT h.HistoryId, h.FromStatus, h.ToStatus, h.Note, f.Name AS FacilityName, u.DisplayName AS ChangedByName, h.ChangedAt
    FROM dbo.BloodRequestHistory h
    LEFT JOIN dbo.Facilities f ON f.FacilityId = h.FacilityId
    LEFT JOIN dbo.Users u ON u.UserId = h.ChangedBy
    WHERE h.RequestId = @RequestId
    ORDER BY h.ChangedAt, h.HistoryId;

    SELECT t.ToStatus
    FROM (VALUES (N'Submitted', N'UnderReview', 1), (N'Submitted', N'Cancelled', 2),
                 (N'UnderReview', N'Matched', 1), (N'UnderReview', N'UnableToFulfil', 2), (N'UnderReview', N'Cancelled', 3),
                 (N'Matched', N'Contacted', 1), (N'Matched', N'Closed', 2), (N'Matched', N'Cancelled', 3),
                 (N'Contacted', N'Fulfilled', 1), (N'Contacted', N'UnableToFulfil', 2), (N'Contacted', N'Closed', 3),
                 (N'UnableToFulfil', N'Submitted', 1), (N'UnableToFulfil', N'Closed', 2),
                 (N'Fulfilled', N'Closed', 1)) AS t (FromStatus, ToStatus, SortOrder)
    WHERE t.FromStatus = @Status
      AND (@CanManage = 1
           OR (@RequesterUserId = @ActorUserId AND t.ToStatus = N'Cancelled' AND t.FromStatus IN (N'Submitted', N'UnderReview')))
    ORDER BY t.SortOrder;
END
GO

/*
  Creates a blood request (status Submitted) with history, audit and notifications in one transaction.
  The same @IdempotencyKey for the same requester returns the existing request instead of creating a new one.
*/
CREATE OR ALTER PROCEDURE dbo.usp_Request_Create
    @ActorUserId         INT,
    @PatientReference    NVARCHAR(50) = NULL,
    @AboGroup            NVARCHAR(2),
    @RhFactor            NVARCHAR(10),
    @ComponentId         INT,
    @QuantityRequested   DECIMAL(12,2),
    @UnitId              INT,
    @Urgency             NVARCHAR(20) = N'Routine',
    @NeededBy            DATETIME2(0),
    @AreaId              INT,
    @HospitalName        NVARCHAR(200),
    @PreferredFacilityId INT = NULL,
    @ContactName         NVARCHAR(150),
    @ContactPhone        NVARCHAR(30),
    @ContactConsent      BIT = 0,
    @Notes               NVARCHAR(1000) = NULL,
    @IdempotencyKey      NVARCHAR(100) = NULL,
    @CorrelationId       NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'requests.create') = 0
        THROW 50403, N'You do not have permission to create blood requests.', 1;

    SET @PatientReference = NULLIF(LTRIM(RTRIM(@PatientReference)), N'');
    SET @AboGroup = NULLIF(LTRIM(RTRIM(@AboGroup)), N'');
    SET @RhFactor = NULLIF(LTRIM(RTRIM(@RhFactor)), N'');
    SET @Urgency = ISNULL(NULLIF(LTRIM(RTRIM(@Urgency)), N''), N'Routine');
    SET @HospitalName = NULLIF(LTRIM(RTRIM(@HospitalName)), N'');
    SET @ContactName = NULLIF(LTRIM(RTRIM(@ContactName)), N'');
    SET @ContactPhone = NULLIF(LTRIM(RTRIM(@ContactPhone)), N'');
    SET @Notes = NULLIF(LTRIM(RTRIM(@Notes)), N'');
    SET @IdempotencyKey = NULLIF(LTRIM(RTRIM(@IdempotencyKey)), N'');
    IF @PreferredFacilityId = 0 SET @PreferredFacilityId = NULL;

    DECLARE @ExistingId INT;
    IF @IdempotencyKey IS NOT NULL
    BEGIN
        SELECT @ExistingId = RequestId FROM dbo.BloodRequests
        WHERE RequesterUserId = @ActorUserId AND IdempotencyKey = @IdempotencyKey;
        IF @ExistingId IS NOT NULL
        BEGIN
            EXEC dbo.usp_Request_GetRow @ActorUserId = @ActorUserId, @RequestId = @ExistingId;
            RETURN;
        END
    END

    IF ISNULL(@ContactConsent, 0) = 0
        THROW 50400, N'Contact consent is required to submit a blood request.', 1;
    IF @AboGroup IS NULL OR @AboGroup NOT IN (N'A', N'B', N'AB', N'O')
        THROW 50400, N'ABO group must be A, B, AB or O.', 1;
    IF @RhFactor IS NULL OR @RhFactor NOT IN (N'Positive', N'Negative')
        THROW 50400, N'Rh factor must be Positive or Negative.', 1;
    IF @Urgency NOT IN (N'Routine', N'Urgent', N'Emergency')
        THROW 50400, N'Urgency must be Routine, Urgent or Emergency.', 1;
    IF @QuantityRequested IS NULL OR @QuantityRequested <= 0 OR @QuantityRequested > 50
        THROW 50400, N'Quantity requested must be greater than 0 and not more than 50.', 1;
    IF @NeededBy IS NULL OR @NeededBy <= SYSUTCDATETIME()
        THROW 50400, N'Needed-by date must be in the future.', 1;
    IF @HospitalName IS NULL
        THROW 50400, N'Hospital name is required.', 1;
    IF @ContactName IS NULL OR @ContactPhone IS NULL
        THROW 50400, N'Contact name and phone are required.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.BloodComponents WHERE ComponentId = @ComponentId AND IsActive = 1)
        THROW 50400, N'Blood component is not valid.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Units WHERE UnitId = @UnitId AND IsActive = 1)
        THROW 50400, N'Unit is not valid.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Areas WHERE AreaId = @AreaId AND IsActive = 1)
        THROW 50400, N'Area is not valid.', 1;
    IF @PreferredFacilityId IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM dbo.Facilities WHERE FacilityId = @PreferredFacilityId AND IsActive = 1 AND VerificationStatus = N'Verified')
        THROW 50400, N'Preferred facility is not a verified active facility.', 1;

    DECLARE @RequestId INT, @RequestNo NVARCHAR(30), @BloodGroup NVARCHAR(5), @ComponentCode NVARCHAR(20), @AreaName NVARCHAR(150),
            @Message NVARCHAR(1000), @EntityId NVARCHAR(50), @Route NVARCHAR(300), @NewValues NVARCHAR(MAX);

    SET @BloodGroup = @AboGroup + CASE WHEN @RhFactor = N'Positive' THEN N'+' ELSE N'-' END;
    SELECT @ComponentCode = Code FROM dbo.BloodComponents WHERE ComponentId = @ComponentId;
    SELECT @AreaName = Name FROM dbo.Areas WHERE AreaId = @AreaId;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @IdempotencyKey IS NOT NULL
        BEGIN
            SELECT @ExistingId = RequestId FROM dbo.BloodRequests WITH (UPDLOCK, HOLDLOCK)
            WHERE RequesterUserId = @ActorUserId AND IdempotencyKey = @IdempotencyKey;
            IF @ExistingId IS NOT NULL
            BEGIN
                COMMIT TRANSACTION;
                EXEC dbo.usp_Request_GetRow @ActorUserId = @ActorUserId, @RequestId = @ExistingId;
                RETURN;
            END
        END

        EXEC dbo.usp_Reference_Next @ActorUserId = @ActorUserId, @Prefix = N'BRQ', @Next = @RequestNo OUTPUT;

        INSERT INTO dbo.BloodRequests
            (RequestNo, RequesterUserId, PatientReference, AboGroup, RhFactor, ComponentId, QuantityRequested, UnitId, Urgency,
             NeededBy, AreaId, HospitalName, PreferredFacilityId, ContactName, ContactPhone, ContactConsent, Notes, Status,
             IdempotencyKey, CreatedAt, CreatedBy)
        VALUES
            (@RequestNo, @ActorUserId, @PatientReference, @AboGroup, @RhFactor, @ComponentId, @QuantityRequested, @UnitId, @Urgency,
             @NeededBy, @AreaId, @HospitalName, @PreferredFacilityId, @ContactName, @ContactPhone, 1, @Notes, N'Submitted',
             @IdempotencyKey, SYSUTCDATETIME(), @ActorUserId);

        SET @RequestId = SCOPE_IDENTITY();
        SET @EntityId = CAST(@RequestId AS NVARCHAR(50));
        SET @Route = N'/requests/' + @EntityId;

        INSERT INTO dbo.BloodRequestHistory (RequestId, FromStatus, ToStatus, Note, FacilityId, ChangedBy, ChangedAt)
        VALUES (@RequestId, NULL, N'Submitted', N'Request submitted.', @PreferredFacilityId, @ActorUserId, SYSUTCDATETIME());

        SET @NewValues = (SELECT @RequestNo AS requestNo, @BloodGroup AS bloodGroup, @ComponentCode AS componentCode,
                                 @QuantityRequested AS quantityRequested, @Urgency AS urgency, @NeededBy AS neededBy,
                                 @AreaId AS areaId, @HospitalName AS hospitalName, @PreferredFacilityId AS preferredFacilityId,
                                 N'Submitted' AS status
                          FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        EXEC dbo.usp_Audit_Write @ActorUserId = @ActorUserId, @EntityType = N'BloodRequest', @EntityId = @EntityId,
             @ReferenceNo = @RequestNo, @FacilityId = @PreferredFacilityId, @Action = N'Create',
             @Description = N'Blood request submitted.', @NewValues = @NewValues, @SourceType = N'ManualPortal',
             @CorrelationId = @CorrelationId;

        SET @Message = N'Your request ' + @RequestNo + N' for ' + CAST(CAST(@QuantityRequested AS DECIMAL(12,2)) AS NVARCHAR(20))
                     + N' ' + @BloodGroup + N' ' + ISNULL(@ComponentCode, N'') + N' has been submitted.';
        EXEC dbo.usp_Notification_Create @ActorUserId = @ActorUserId, @UserId = @ActorUserId, @Title = N'Blood request submitted',
             @Message = @Message, @Type = N'Success', @EntityType = N'BloodRequest', @EntityId = @EntityId, @Route = @Route;

        SET @Route = N'/coordination/' + @EntityId;
        SET @Message = @Urgency + N' request ' + @RequestNo + N': ' + CAST(CAST(@QuantityRequested AS DECIMAL(12,2)) AS NVARCHAR(20))
                     + N' ' + @BloodGroup + N' ' + ISNULL(@ComponentCode, N'') + N' needed in ' + ISNULL(@AreaName, N'your area')
                     + N' at ' + @HospitalName + N'.';
        EXEC dbo.usp_Notification_NotifyRole @ActorUserId = @ActorUserId, @RoleCode = N'HospitalManagement',
             @Title = N'New blood request in your area', @Message = @Message, @Type = N'Action',
             @EntityType = N'BloodRequest', @EntityId = @EntityId, @Route = @Route, @AreaId = @AreaId;
        EXEC dbo.usp_Notification_NotifyRole @ActorUserId = @ActorUserId, @RoleCode = N'BloodBank',
             @Title = N'New blood request in your area', @Message = @Message, @Type = N'Action',
             @EntityType = N'BloodRequest', @EntityId = @EntityId, @Route = @Route, @AreaId = @AreaId;
        EXEC dbo.usp_Notification_NotifyRole @ActorUserId = @ActorUserId, @RoleCode = N'Admin',
             @Title = N'New blood request', @Message = @Message, @Type = N'Action',
             @EntityType = N'BloodRequest', @EntityId = @EntityId, @Route = @Route;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        -- A concurrent submission with the same idempotency key won the race: return that request.
        IF ERROR_NUMBER() IN (2601, 2627) AND @IdempotencyKey IS NOT NULL
        BEGIN
            SELECT @ExistingId = RequestId FROM dbo.BloodRequests
            WHERE RequesterUserId = @ActorUserId AND IdempotencyKey = @IdempotencyKey;
            IF @ExistingId IS NOT NULL
            BEGIN
                EXEC dbo.usp_Request_GetRow @ActorUserId = @ActorUserId, @RequestId = @ExistingId;
                RETURN;
            END
        END;
        THROW;
    END CATCH

    EXEC dbo.usp_Request_GetRow @ActorUserId = @ActorUserId, @RequestId = @RequestId;
END
GO

/*
  Changes the status of a blood request following the state machine:
    Submitted      -> UnderReview | Cancelled
    UnderReview    -> Matched | UnableToFulfil | Cancelled
    Matched        -> Contacted | Closed | Cancelled
    Contacted      -> Fulfilled | UnableToFulfil | Closed
    UnableToFulfil -> Submitted | Closed
    Fulfilled      -> Closed
  requests.manage is required, except that the owner may cancel from Submitted / UnderReview.
  Matched requires @MatchedFacilityId (verified, active, accessible to the actor unless admin).
  Writes history, audit and requester notification in the same transaction. Returns the request row.
*/
CREATE OR ALTER PROCEDURE dbo.usp_Request_ChangeStatus
    @ActorUserId       INT,
    @RequestId         INT,
    @ToStatus          NVARCHAR(20),
    @Note              NVARCHAR(500) = NULL,
    @MatchedFacilityId INT = NULL,
    @RowVersion        VARBINARY(8) = NULL,
    @CorrelationId     NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @CanManage BIT = dbo.fn_UserHasPermission(@ActorUserId, N'requests.manage');
    DECLARE @IsAdmin BIT = dbo.fn_UserIsAdmin(@ActorUserId);
    SET @ToStatus = NULLIF(LTRIM(RTRIM(@ToStatus)), N'');
    SET @Note = NULLIF(LTRIM(RTRIM(@Note)), N'');
    IF @MatchedFacilityId = 0 SET @MatchedFacilityId = NULL;

    IF @ToStatus IS NULL OR @ToStatus NOT IN (N'Submitted', N'UnderReview', N'Matched', N'Contacted', N'Fulfilled', N'UnableToFulfil', N'Closed', N'Cancelled')
        THROW 50400, N'Target status is not valid.', 1;

    DECLARE @RequesterUserId INT, @FromStatus NVARCHAR(20), @RequestNo NVARCHAR(20), @CurrentMatchedId INT,
            @CurrentRowVer VARBINARY(8), @AboGroup NVARCHAR(2), @RhFactor NVARCHAR(10), @ComponentId INT,
            @Message NVARCHAR(1000), @EntityId NVARCHAR(50), @Route NVARCHAR(300), @OldValues NVARCHAR(MAX), @NewValues NVARCHAR(MAX),
            @HistoryFacilityId INT, @FacilityName NVARCHAR(200), @Action NVARCHAR(50), @ErrorText NVARCHAR(400), @NotifyType NVARCHAR(20);

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @RequesterUserId = RequesterUserId, @FromStatus = Status, @RequestNo = RequestNo,
               @CurrentMatchedId = MatchedFacilityId, @CurrentRowVer = CAST(RowVer AS VARBINARY(8)),
               @AboGroup = AboGroup, @RhFactor = RhFactor, @ComponentId = ComponentId
        FROM dbo.BloodRequests WITH (UPDLOCK, HOLDLOCK)
        WHERE RequestId = @RequestId;

        IF @RequesterUserId IS NULL OR (@RequesterUserId <> @ActorUserId AND @CanManage = 0)
            THROW 50404, N'Blood request not found.', 1;

        IF @CanManage = 0
           AND NOT (@RequesterUserId = @ActorUserId AND @ToStatus = N'Cancelled' AND @FromStatus IN (N'Submitted', N'UnderReview'))
            THROW 50403, N'Only the requester (while the request is Submitted or UnderReview) or a coordinator can change this request.', 1;

        IF @RowVersion IS NOT NULL AND @RowVersion <> @CurrentRowVer
            THROW 50409, N'The request was changed by someone else. Reload and try again.', 1;

        IF NOT EXISTS (SELECT 1
                       FROM (VALUES (N'Submitted', N'UnderReview'), (N'Submitted', N'Cancelled'),
                                    (N'UnderReview', N'Matched'), (N'UnderReview', N'UnableToFulfil'), (N'UnderReview', N'Cancelled'),
                                    (N'Matched', N'Contacted'), (N'Matched', N'Closed'), (N'Matched', N'Cancelled'),
                                    (N'Contacted', N'Fulfilled'), (N'Contacted', N'UnableToFulfil'), (N'Contacted', N'Closed'),
                                    (N'UnableToFulfil', N'Submitted'), (N'UnableToFulfil', N'Closed'),
                                    (N'Fulfilled', N'Closed')) AS t (FromStatus, ToStatus)
                       WHERE t.FromStatus = @FromStatus AND t.ToStatus = @ToStatus)
        BEGIN
            SET @ErrorText = N'Invalid status transition from ' + @FromStatus + N' to ' + @ToStatus + N'.';
            THROW 50409, @ErrorText, 1;
        END

        IF @ToStatus = N'Matched'
        BEGIN
            IF @MatchedFacilityId IS NULL
                THROW 50400, N'A matched facility is required to mark the request as Matched.', 1;
            IF NOT EXISTS (SELECT 1 FROM dbo.Facilities
                           WHERE FacilityId = @MatchedFacilityId AND IsActive = 1 AND VerificationStatus = N'Verified')
                THROW 50400, N'Matched facility must be a verified, active facility.', 1;
            IF @IsAdmin = 0 AND dbo.fn_UserCanAccessFacility(@ActorUserId, @MatchedFacilityId) = 0
                THROW 50403, N'You are not assigned to this facility.', 1;
        END
        ELSE IF @FromStatus = N'Matched' AND @CurrentMatchedId IS NULL AND @ToStatus <> N'Cancelled'
            THROW 50409, N'The request has no matched facility.', 1;

        SET @OldValues = (SELECT @FromStatus AS status, @CurrentMatchedId AS matchedFacilityId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        UPDATE dbo.BloodRequests
        SET Status = @ToStatus,
            StatusReason = @Note,
            MatchedFacilityId = CASE WHEN @ToStatus = N'Matched' THEN @MatchedFacilityId
                                     WHEN @ToStatus = N'Submitted' THEN NULL
                                     ELSE MatchedFacilityId END,
            UpdatedAt = SYSUTCDATETIME(),
            UpdatedBy = @ActorUserId
        WHERE RequestId = @RequestId;

        SET @HistoryFacilityId = CASE WHEN @ToStatus = N'Matched' THEN @MatchedFacilityId
                                      WHEN @ToStatus = N'Submitted' THEN NULL
                                      ELSE @CurrentMatchedId END;
        SELECT @FacilityName = Name FROM dbo.Facilities WHERE FacilityId = @HistoryFacilityId;

        INSERT INTO dbo.BloodRequestHistory (RequestId, FromStatus, ToStatus, Note, FacilityId, ChangedBy, ChangedAt)
        VALUES (@RequestId, @FromStatus, @ToStatus, @Note, @HistoryFacilityId, @ActorUserId, SYSUTCDATETIME());

        SET @NewValues = (SELECT @ToStatus AS status, @HistoryFacilityId AS matchedFacilityId, @Note AS note
                          FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SET @EntityId = CAST(@RequestId AS NVARCHAR(50));
        SET @Action = CASE WHEN @ToStatus = N'Cancelled' THEN N'Cancel' ELSE N'StatusChange' END;
        SET @Message = N'Request ' + @RequestNo + N' changed from ' + @FromStatus + N' to ' + @ToStatus + N'.';

        EXEC dbo.usp_Audit_Write @ActorUserId = @ActorUserId, @EntityType = N'BloodRequest', @EntityId = @EntityId,
             @ReferenceNo = @RequestNo, @FacilityId = @HistoryFacilityId, @Action = @Action, @Description = @Message,
             @OldValues = @OldValues, @NewValues = @NewValues, @Reason = @Note, @CorrelationId = @CorrelationId;

        IF @RequesterUserId <> @ActorUserId
        BEGIN
            SET @Route = N'/requests/' + @EntityId;
            SET @Message = N'Your request ' + @RequestNo + N' is now ' + @ToStatus
                         + CASE WHEN @FacilityName IS NOT NULL AND @ToStatus IN (N'Matched', N'Contacted', N'Fulfilled')
                                THEN N' (' + @FacilityName + N')' ELSE N'' END
                         + N'.' + CASE WHEN @Note IS NOT NULL THEN N' ' + @Note ELSE N'' END
                         + CASE WHEN @ToStatus = N'Matched' THEN N' Please reconfirm availability with the facility.' ELSE N'' END;
            SET @Message = LEFT(@Message, 1000);
            SET @NotifyType = CASE WHEN @ToStatus IN (N'Matched', N'Fulfilled') THEN N'Success'
                                   WHEN @ToStatus IN (N'UnableToFulfil', N'Cancelled') THEN N'Warning' ELSE N'Info' END;
            EXEC dbo.usp_Notification_Create @ActorUserId = @ActorUserId, @UserId = @RequesterUserId,
                 @Title = N'Blood request updated', @Message = @Message, @Type = @NotifyType,
                 @EntityType = N'BloodRequest', @EntityId = @EntityId, @Route = @Route;
        END
        ELSE IF @CurrentMatchedId IS NOT NULL
        BEGIN
            -- Owner cancelled: let the matched facility know.
            SET @Route = N'/coordination/' + @EntityId;
            SET @Message = N'Request ' + @RequestNo + N' was cancelled by the requester.';
            EXEC dbo.usp_Notification_NotifyFacilityUsers @ActorUserId = @ActorUserId, @FacilityId = @CurrentMatchedId,
                 @Title = N'Blood request cancelled', @Message = @Message, @Type = N'Info',
                 @EntityType = N'BloodRequest', @EntityId = @EntityId, @Route = @Route;
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    EXEC dbo.usp_Request_GetRow @ActorUserId = @ActorUserId, @RequestId = @RequestId;
END
GO

/* Cancels a request (owner from Submitted / UnderReview, or a coordinator per the state machine). */
CREATE OR ALTER PROCEDURE dbo.usp_Request_Cancel
    @ActorUserId   INT,
    @RequestId     INT,
    @Reason        NVARCHAR(500) = NULL,
    @CorrelationId NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'requests.create') = 0
       AND dbo.fn_UserHasPermission(@ActorUserId, N'requests.manage') = 0
        THROW 50403, N'You do not have permission to cancel blood requests.', 1;

    SET @Reason = ISNULL(NULLIF(LTRIM(RTRIM(@Reason)), N''), N'Cancelled by user.');

    EXEC dbo.usp_Request_ChangeStatus @ActorUserId = @ActorUserId, @RequestId = @RequestId, @ToStatus = N'Cancelled',
         @Note = @Reason, @CorrelationId = @CorrelationId;
END
GO

/*
  Candidate facilities for a request: same ABO / Rh / component, quantity > 0, verified + active facility,
  Stale and never-updated records excluded. Ordered same area first, Fresh before Aging, then quantity.
*/
CREATE OR ALTER PROCEDURE dbo.usp_Request_GetMatches
    @ActorUserId INT,
    @RequestId   INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @CanManage BIT = dbo.fn_UserHasPermission(@ActorUserId, N'requests.manage');
    DECLARE @RequesterUserId INT, @AboGroup NVARCHAR(2), @RhFactor NVARCHAR(10), @ComponentId INT, @AreaId INT;
    SELECT @RequesterUserId = RequesterUserId, @AboGroup = AboGroup, @RhFactor = RhFactor,
           @ComponentId = ComponentId, @AreaId = AreaId
    FROM dbo.BloodRequests WHERE RequestId = @RequestId;

    IF @RequesterUserId IS NULL OR (@RequesterUserId <> @ActorUserId AND @CanManage = 0)
        THROW 50404, N'Blood request not found.', 1;

    SELECT TOP (50)
           v.InventoryId, v.FacilityId, v.FacilityName, v.FacilityType, v.AreaId, v.AreaName, v.City, v.AddressLine,
           v.ContactPhone, v.Is24x7, v.ComponentId, v.ComponentCode, v.ComponentName, v.AboGroup, v.RhFactor, v.BloodGroup,
           v.Quantity, v.UnitCode, v.AvailabilityStatus, v.FreshnessStatus, v.VerificationStatus, v.SourceType,
           v.LastUpdatedAt, v.ValidUntil, v.MinutesSinceUpdate, v.EarliestExpiryDate, v.QualityScore
    FROM dbo.vw_BloodAvailability v
    INNER JOIN dbo.Facilities f ON f.FacilityId = v.FacilityId AND f.VerificationStatus = N'Verified' AND f.IsActive = 1
    WHERE v.AboGroup = @AboGroup AND v.RhFactor = @RhFactor AND v.ComponentId = @ComponentId
      AND v.Quantity > 0
      AND v.FreshnessStatus NOT IN (N'Stale', N'Unknown')
    ORDER BY CASE WHEN v.AreaId = @AreaId THEN 0 ELSE 1 END,
             CASE v.FreshnessStatus WHEN N'Fresh' THEN 1 WHEN N'Aging' THEN 2 ELSE 3 END,
             v.Quantity DESC, v.FacilityName, v.InventoryId;
END
GO
