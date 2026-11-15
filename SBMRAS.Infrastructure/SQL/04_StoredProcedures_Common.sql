/*=====================================================================
  SBMRAS - 04_StoredProcedures_Common.sql
  Lookups, reference numbers, audit trail and in-app notifications.
  Error numbers used by all SBMRAS procedures (contract section 3.6):
    50001-50099 business rule conflict          (HTTP 409)
    50400       invalid input                    (HTTP 400)
    50403       forbidden / out of facility scope (HTTP 403)
    50404       not found                        (HTTP 404)
    50409       concurrency / duplicate          (HTTP 409)
=====================================================================*/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*
  Reference data for public and internal forms (anonymous).
  Result sets (in order): areas, components, units, resourceCategories, resourceTypes,
  aboGroups, rhFactors, urgencies, requestStatuses, freshnessStatuses (the last five as single column Value).
*/
CREATE OR ALTER PROCEDURE dbo.usp_Lookups_Get
    @ActorUserId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT a.AreaId, a.Name, a.City
    FROM dbo.Areas a
    WHERE a.IsActive = 1
    ORDER BY a.Name;

    SELECT c.ComponentId, c.Code, c.Name, c.ShelfLifeDays
    FROM dbo.BloodComponents c
    WHERE c.IsActive = 1
    ORDER BY c.ComponentId;

    SELECT u.UnitId, u.Code, u.Name
    FROM dbo.Units u
    WHERE u.IsActive = 1
    ORDER BY u.UnitId;

    SELECT rc.CategoryId, rc.Name
    FROM dbo.ResourceCategories rc
    WHERE rc.IsActive = 1
    ORDER BY rc.Name;

    SELECT t.ResourceTypeId, t.CategoryId, rc.Name AS CategoryName, t.Code, t.Name, t.DefaultUnitId, u.Code AS UnitCode, t.TrackingMode
    FROM dbo.MedicalResourceTypes t
    INNER JOIN dbo.ResourceCategories rc ON rc.CategoryId = t.CategoryId
    LEFT JOIN dbo.Units u ON u.UnitId = t.DefaultUnitId
    WHERE t.IsActive = 1 AND rc.IsActive = 1
    ORDER BY rc.Name, t.Name;

    SELECT v.Value FROM (VALUES (1, N'A'), (2, N'B'), (3, N'AB'), (4, N'O')) v (SortOrder, Value) ORDER BY v.SortOrder;
    SELECT v.Value FROM (VALUES (1, N'Positive'), (2, N'Negative')) v (SortOrder, Value) ORDER BY v.SortOrder;
    SELECT v.Value FROM (VALUES (1, N'Routine'), (2, N'Urgent'), (3, N'Emergency')) v (SortOrder, Value) ORDER BY v.SortOrder;
    SELECT v.Value FROM (VALUES (1, N'Submitted'), (2, N'UnderReview'), (3, N'Matched'), (4, N'Contacted'), (5, N'Fulfilled'),
                                (6, N'UnableToFulfil'), (7, N'Closed'), (8, N'Cancelled')) v (SortOrder, Value) ORDER BY v.SortOrder;
    SELECT v.Value FROM (VALUES (1, N'Fresh'), (2, N'Aging'), (3, N'Stale'), (4, N'Unknown'), (5, N'UnderReview')) v (SortOrder, Value) ORDER BY v.SortOrder;
END
GO

/*
  Allocates the next yearly reference number, e.g. BRQ-2026-0001 / CHG-2026-0001 / IMP-2026-0001.
  Call inside the caller's transaction (a local transaction is used when none is open).
*/
CREATE OR ALTER PROCEDURE dbo.usp_Reference_Next
    @ActorUserId INT = NULL,
    @Prefix      NVARCHAR(10),
    @Next        NVARCHAR(30) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Prefix = UPPER(LTRIM(RTRIM(@Prefix)));
    IF NULLIF(@Prefix, N'') IS NULL
        THROW 50400, N'Reference prefix is required.', 1;

    DECLARE @Year INT = YEAR(SYSUTCDATETIME()), @Number INT, @OwnTran BIT = 0;

    IF @@TRANCOUNT = 0
    BEGIN
        BEGIN TRANSACTION;
        SET @OwnTran = 1;
    END

    UPDATE dbo.ReferenceSequences WITH (UPDLOCK, HOLDLOCK)
    SET @Number = LastNumber = LastNumber + 1
    WHERE Prefix = @Prefix AND [Year] = @Year;

    IF @Number IS NULL
    BEGIN
        INSERT INTO dbo.ReferenceSequences (Prefix, [Year], LastNumber) VALUES (@Prefix, @Year, 1);
        SET @Number = 1;
    END

    IF @OwnTran = 1
        COMMIT TRANSACTION;

    SET @Next = @Prefix + N'-' + CAST(@Year AS NVARCHAR(4)) + N'-'
        + CASE WHEN @Number > 9999 THEN CAST(@Number AS NVARCHAR(10)) ELSE RIGHT(N'0000' + CAST(@Number AS NVARCHAR(10)), 4) END;
END
GO

/*
  Appends an audit entry (AuditLogs is append-only). @EntityId accepts INT or text keys.
  @ActorRole defaults to the actor's highest role (Admin > HospitalManagement > BloodBank > PublicUser).
*/
CREATE OR ALTER PROCEDURE dbo.usp_Audit_Write
    @ActorUserId   INT = NULL,
    @EntityType    NVARCHAR(50),
    @EntityId      NVARCHAR(50),
    @ReferenceNo   NVARCHAR(50) = NULL,
    @FacilityId    INT = NULL,
    @Action        NVARCHAR(50),
    @Description   NVARCHAR(1000) = NULL,
    @OldValues     NVARCHAR(MAX) = NULL,
    @NewValues     NVARCHAR(MAX) = NULL,
    @SourceType    NVARCHAR(30) = NULL,
    @Reason        NVARCHAR(500) = NULL,
    @CorrelationId NVARCHAR(64) = NULL,
    @ActorRole     NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @ActorRole IS NULL AND @ActorUserId IS NOT NULL
        SELECT TOP (1) @ActorRole = r.RoleCode
        FROM dbo.UserRoles ur
        INNER JOIN dbo.Roles r ON r.RoleId = ur.RoleId AND r.IsActive = 1
        WHERE ur.UserId = @ActorUserId
        ORDER BY CASE r.RoleCode WHEN N'Admin' THEN 1 WHEN N'HospitalManagement' THEN 2 WHEN N'BloodBank' THEN 3 WHEN N'PublicUser' THEN 4 ELSE 5 END, r.RoleId;

    INSERT INTO dbo.AuditLogs (EntityType, EntityId, ReferenceNo, FacilityId, Action, Description, OldValues, NewValues,
                               SourceType, Reason, CorrelationId, UserId, ActorRole, CreatedAt)
    VALUES (@EntityType, ISNULL(@EntityId, N''), @ReferenceNo, @FacilityId, @Action,
            COALESCE(NULLIF(@Description, N''), @EntityType + N' ' + @Action),
            @OldValues, @NewValues, @SourceType, NULLIF(@Reason, N''), NULLIF(@CorrelationId, N''), @ActorUserId, @ActorRole, SYSUTCDATETIME());
END
GO

/* Creates an in-app notification for one active user (the actor may notify themself, e.g. request confirmation). */
CREATE OR ALTER PROCEDURE dbo.usp_Notification_Create
    @ActorUserId INT = NULL,
    @UserId      INT,
    @Title       NVARCHAR(200),
    @Message     NVARCHAR(1000),
    @Type        NVARCHAR(20) = N'Info',
    @EntityType  NVARCHAR(50) = NULL,
    @EntityId    NVARCHAR(50) = NULL,
    @Route       NVARCHAR(300) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @UserId IS NULL
        RETURN;

    INSERT INTO dbo.Notifications (UserId, Title, Message, Type, EntityType, EntityId, Route, IsRead, CreatedAt)
    SELECT u.UserId, @Title, @Message, ISNULL(@Type, N'Info'), @EntityType, @EntityId, @Route, 0, SYSUTCDATETIME()
    FROM dbo.Users u
    WHERE u.UserId = @UserId AND u.IsActive = 1;
END
GO

/*
  Notifies every active user holding @RoleCode (except the actor unless @ExcludeActor = 0).
  @AreaId (optional): only users with an active assignment to an active facility in that area
  (used e.g. to notify HospitalManagement / BloodBank users near a blood request).
*/
CREATE OR ALTER PROCEDURE dbo.usp_Notification_NotifyRole
    @ActorUserId  INT = NULL,
    @RoleCode     NVARCHAR(50),
    @Title        NVARCHAR(200),
    @Message      NVARCHAR(1000),
    @Type         NVARCHAR(20) = N'Info',
    @EntityType   NVARCHAR(50) = NULL,
    @EntityId     NVARCHAR(50) = NULL,
    @Route        NVARCHAR(300) = NULL,
    @AreaId       INT = NULL,
    @ExcludeActor BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    INSERT INTO dbo.Notifications (UserId, Title, Message, Type, EntityType, EntityId, Route, IsRead, CreatedAt)
    SELECT u.UserId, @Title, @Message, ISNULL(@Type, N'Info'), @EntityType, @EntityId, @Route, 0, SYSUTCDATETIME()
    FROM dbo.Users u
    WHERE u.IsActive = 1
      AND (ISNULL(@ExcludeActor, 1) = 0 OR u.UserId <> ISNULL(@ActorUserId, 0))
      AND EXISTS (SELECT 1 FROM dbo.UserRoles ur INNER JOIN dbo.Roles r ON r.RoleId = ur.RoleId AND r.IsActive = 1
                  WHERE ur.UserId = u.UserId AND r.RoleCode = @RoleCode)
      AND (@AreaId IS NULL OR EXISTS (SELECT 1 FROM dbo.FacilityUserAssignments fa
                                      INNER JOIN dbo.Facilities f ON f.FacilityId = fa.FacilityId AND f.IsActive = 1
                                      WHERE fa.UserId = u.UserId AND fa.IsActive = 1 AND f.AreaId = @AreaId));
END
GO

/*
  Notifies the active users assigned to a facility (except the actor unless @ExcludeActor = 0).
  @AssignmentRoles (optional CSV of Manager,Operator,Verifier) restricts the recipients.
*/
CREATE OR ALTER PROCEDURE dbo.usp_Notification_NotifyFacilityUsers
    @ActorUserId     INT = NULL,
    @FacilityId      INT,
    @Title           NVARCHAR(200),
    @Message         NVARCHAR(1000),
    @Type            NVARCHAR(20) = N'Info',
    @EntityType      NVARCHAR(50) = NULL,
    @EntityId        NVARCHAR(50) = NULL,
    @Route           NVARCHAR(300) = NULL,
    @AssignmentRoles NVARCHAR(100) = NULL,
    @ExcludeActor    BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @AssignmentRoles = NULLIF(LTRIM(RTRIM(@AssignmentRoles)), N'');

    INSERT INTO dbo.Notifications (UserId, Title, Message, Type, EntityType, EntityId, Route, IsRead, CreatedAt)
    SELECT u.UserId, @Title, @Message, ISNULL(@Type, N'Info'), @EntityType, @EntityId, @Route, 0, SYSUTCDATETIME()
    FROM dbo.Users u
    WHERE u.IsActive = 1
      AND (ISNULL(@ExcludeActor, 1) = 0 OR u.UserId <> ISNULL(@ActorUserId, 0))
      AND EXISTS (SELECT 1 FROM dbo.FacilityUserAssignments fa
                  WHERE fa.UserId = u.UserId AND fa.FacilityId = @FacilityId AND fa.IsActive = 1
                    AND (@AssignmentRoles IS NULL
                         OR fa.AssignmentRole IN (SELECT LTRIM(RTRIM(s.value)) FROM STRING_SPLIT(@AssignmentRoles, N',') s)));
END
GO

/* Paged notifications of the caller. Result set 1: rows; 2: TotalCount. */
CREATE OR ALTER PROCEDURE dbo.usp_Notification_Search
    @ActorUserId INT,
    @UnreadOnly  BIT = 0,
    @Page        INT = 1,
    @PageSize    INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Page = CASE WHEN ISNULL(@Page, 1) < 1 THEN 1 ELSE @Page END;
    SET @PageSize = CASE WHEN ISNULL(@PageSize, 20) < 1 THEN 20 WHEN @PageSize > 100 THEN 100 ELSE @PageSize END;
    SET @UnreadOnly = ISNULL(@UnreadOnly, 0);

    SELECT n.NotificationId, n.Title, n.Message, n.Type, n.EntityType, n.EntityId, n.Route, n.IsRead, n.CreatedAt
    FROM dbo.Notifications n
    WHERE n.UserId = @ActorUserId AND (@UnreadOnly = 0 OR n.IsRead = 0)
    ORDER BY n.CreatedAt DESC, n.NotificationId DESC
    OFFSET (@Page - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT COUNT(*) AS TotalCount
    FROM dbo.Notifications n
    WHERE n.UserId = @ActorUserId AND (@UnreadOnly = 0 OR n.IsRead = 0);
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Notification_GetUnreadCount
    @ActorUserId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT COUNT(*) AS [Count] FROM dbo.Notifications WHERE UserId = @ActorUserId AND IsRead = 0;
END
GO

/* Marks one of the caller's notifications as read. Returns the remaining unread count. */
CREATE OR ALTER PROCEDURE dbo.usp_Notification_MarkRead
    @ActorUserId    INT,
    @NotificationId BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Notifications WHERE NotificationId = @NotificationId AND UserId = @ActorUserId)
        THROW 50404, N'Notification not found.', 1;

    UPDATE dbo.Notifications
    SET IsRead = 1, ReadAt = COALESCE(ReadAt, SYSUTCDATETIME())
    WHERE NotificationId = @NotificationId AND UserId = @ActorUserId AND IsRead = 0;

    SELECT COUNT(*) AS [Count] FROM dbo.Notifications WHERE UserId = @ActorUserId AND IsRead = 0;
END
GO

/* Marks all of the caller's notifications as read. Returns the number of notifications updated. */
CREATE OR ALTER PROCEDURE dbo.usp_Notification_MarkAllRead
    @ActorUserId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    UPDATE dbo.Notifications SET IsRead = 1, ReadAt = SYSUTCDATETIME() WHERE UserId = @ActorUserId AND IsRead = 0;
    SELECT @@ROWCOUNT AS [Count];
END
GO
