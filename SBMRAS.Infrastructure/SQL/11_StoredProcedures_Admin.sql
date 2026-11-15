/*=====================================================================
  SBMRAS - 11_StoredProcedures_Admin.sql
  Administration: users & local roles, facility assignments, roles &
  permissions, facility registry & verification, master data, system
  settings and audit search / entity timeline.
  CSV parameters: @RoleCodes, @PermissionCodes. JSON parameters:
  @AssignmentsJson, @PayloadJson, @SettingsJson.
=====================================================================*/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*---------------------------------------------------------------------
  Users
---------------------------------------------------------------------*/

/* Paged users (users.manage). Result set 1: rows; 2: TotalCount. */
CREATE OR ALTER PROCEDURE dbo.usp_Admin_SearchUsers
    @ActorUserId INT,
    @Search      NVARCHAR(200) = NULL,
    @RoleCode    NVARCHAR(50) = NULL,
    @IsActive    BIT = NULL,
    @Page        INT = 1,
    @PageSize    INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'users.manage') = 0
        THROW 50403, N'You do not have permission to manage users.', 1;

    SET @Page = CASE WHEN ISNULL(@Page, 1) < 1 THEN 1 ELSE @Page END;
    SET @PageSize = CASE WHEN ISNULL(@PageSize, 20) < 1 THEN 20 WHEN @PageSize > 100 THEN 100 ELSE @PageSize END;
    SET @Search = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @RoleCode = NULLIF(LTRIM(RTRIM(@RoleCode)), N'');

    DECLARE @Ids TABLE (UserId INT PRIMARY KEY);
    INSERT INTO @Ids (UserId)
    SELECT u.UserId
    FROM dbo.Users u
    WHERE (@IsActive IS NULL OR u.IsActive = @IsActive)
      AND (@RoleCode IS NULL OR EXISTS (SELECT 1 FROM dbo.UserRoles ur INNER JOIN dbo.Roles r ON r.RoleId = ur.RoleId
                                        WHERE ur.UserId = u.UserId AND r.RoleCode = @RoleCode))
      AND (@Search IS NULL OR u.DisplayName LIKE N'%' + @Search + N'%' OR u.Email LIKE N'%' + @Search + N'%'
           OR u.OrganizationName LIKE N'%' + @Search + N'%' OR u.Phone LIKE N'%' + @Search + N'%');

    SELECT u.UserId, u.DisplayName, u.GivenName, u.FamilyName, u.Email, u.Phone, u.OrganizationName, u.AreaId, a.Name AS AreaName,
           rl.RoleCodes, rl.RoleNames, u.IsActive, u.IsSelfRegistered,
           CAST(CASE WHEN u.EntraObjectId IS NULL THEN 0 ELSE 1 END AS BIT) AS EntraLinked,
           u.LastLoginAt, u.CreatedAt,
           (SELECT COUNT(*) FROM dbo.FacilityUserAssignments fa WHERE fa.UserId = u.UserId AND fa.IsActive = 1) AS FacilityCount
    FROM @Ids i
    INNER JOIN dbo.Users u ON u.UserId = i.UserId
    LEFT JOIN dbo.Areas a ON a.AreaId = u.AreaId
    OUTER APPLY (
        SELECT STRING_AGG(x.RoleCode, N',') WITHIN GROUP (ORDER BY x.Priority) AS RoleCodes,
               STRING_AGG(x.RoleName, N',') WITHIN GROUP (ORDER BY x.Priority) AS RoleNames
        FROM (SELECT r.RoleCode, r.RoleName,
                     CASE r.RoleCode WHEN N'Admin' THEN 1 WHEN N'HospitalManagement' THEN 2 WHEN N'BloodBank' THEN 3 WHEN N'PublicUser' THEN 4 ELSE 5 END AS Priority
              FROM dbo.UserRoles ur INNER JOIN dbo.Roles r ON r.RoleId = ur.RoleId
              WHERE ur.UserId = u.UserId) x) rl
    ORDER BY u.DisplayName, u.UserId
    OFFSET (@Page - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT COUNT(*) AS TotalCount FROM @Ids;
END
GO

/*
  One user (users.manage).
  Result set 1: user; 2: roleSources (RoleCode, Source); 3: facilities (FacilityId, Name, FacilityType, AssignmentRole).
*/
CREATE OR ALTER PROCEDURE dbo.usp_Admin_GetUser
    @ActorUserId INT,
    @UserId      INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'users.manage') = 0
        THROW 50403, N'You do not have permission to manage users.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE UserId = @UserId)
        THROW 50404, N'User not found.', 1;

    SELECT u.UserId, u.DisplayName, u.GivenName, u.FamilyName, u.Email, u.Phone, u.OrganizationName, u.AreaId, a.Name AS AreaName,
           rl.RoleCodes, rl.RoleNames, u.IsActive, u.IsSelfRegistered,
           CAST(CASE WHEN u.EntraObjectId IS NULL THEN 0 ELSE 1 END AS BIT) AS EntraLinked,
           u.LastLoginAt, u.CreatedAt
    FROM dbo.Users u
    LEFT JOIN dbo.Areas a ON a.AreaId = u.AreaId
    OUTER APPLY (
        SELECT STRING_AGG(x.RoleCode, N',') WITHIN GROUP (ORDER BY x.Priority) AS RoleCodes,
               STRING_AGG(x.RoleName, N',') WITHIN GROUP (ORDER BY x.Priority) AS RoleNames
        FROM (SELECT r.RoleCode, r.RoleName,
                     CASE r.RoleCode WHEN N'Admin' THEN 1 WHEN N'HospitalManagement' THEN 2 WHEN N'BloodBank' THEN 3 WHEN N'PublicUser' THEN 4 ELSE 5 END AS Priority
              FROM dbo.UserRoles ur INNER JOIN dbo.Roles r ON r.RoleId = ur.RoleId
              WHERE ur.UserId = u.UserId) x) rl
    WHERE u.UserId = @UserId;

    SELECT r.RoleCode, ur.Source
    FROM dbo.UserRoles ur
    INNER JOIN dbo.Roles r ON r.RoleId = ur.RoleId
    WHERE ur.UserId = @UserId
    ORDER BY CASE r.RoleCode WHEN N'Admin' THEN 1 WHEN N'HospitalManagement' THEN 2 WHEN N'BloodBank' THEN 3 WHEN N'PublicUser' THEN 4 ELSE 5 END, ur.Source;

    SELECT f.FacilityId, f.FacilityCode, f.Name, f.FacilityType, fa.AssignmentRole
    FROM dbo.FacilityUserAssignments fa
    INNER JOIN dbo.Facilities f ON f.FacilityId = fa.FacilityId
    WHERE fa.UserId = @UserId AND fa.IsActive = 1
    ORDER BY f.Name;
END
GO

/*
  Internal: validates and saves a user (insert when @UserId is NULL).
  @RoleCodes = CSV of Local roles; PublicUser is always kept; Entra-sourced rows are never removed.
  Keeps at least one active administrator and prevents admins from locking themselves out.
*/
CREATE OR ALTER PROCEDURE dbo.usp_Admin_SaveUser
    @ActorUserId      INT,
    @UserId           INT = NULL,
    @DisplayName      NVARCHAR(150),
    @GivenName        NVARCHAR(100) = NULL,
    @FamilyName       NVARCHAR(100) = NULL,
    @Email            NVARCHAR(320),
    @Phone            NVARCHAR(30) = NULL,
    @OrganizationName NVARCHAR(200) = NULL,
    @AreaId           INT = NULL,
    @RoleCodes        NVARCHAR(400) = NULL,
    @IsActive         BIT = 1,
    @CorrelationId    NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'users.manage') = 0
        THROW 50403, N'You do not have permission to manage users.', 1;
    IF @UserId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Users WHERE UserId = @UserId)
        THROW 50404, N'User not found.', 1;

    SET @DisplayName = NULLIF(LTRIM(RTRIM(@DisplayName)), N'');
    SET @GivenName = NULLIF(LTRIM(RTRIM(@GivenName)), N'');
    SET @FamilyName = NULLIF(LTRIM(RTRIM(@FamilyName)), N'');
    SET @Email = LOWER(NULLIF(LTRIM(RTRIM(@Email)), N''));
    SET @Phone = NULLIF(LTRIM(RTRIM(@Phone)), N'');
    SET @OrganizationName = NULLIF(LTRIM(RTRIM(@OrganizationName)), N'');
    SET @IsActive = ISNULL(@IsActive, 1);

    IF @DisplayName IS NULL
        THROW 50400, N'Display name is required.', 1;
    IF @Email IS NULL OR @Email NOT LIKE N'_%@_%._%'
        THROW 50400, N'A valid e-mail address is required.', 1;
    IF @AreaId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Areas WHERE AreaId = @AreaId)
        THROW 50400, N'Select a valid area.', 1;
    IF EXISTS (SELECT 1 FROM STRING_SPLIT(ISNULL(@RoleCodes, N''), N',') s
               WHERE NULLIF(LTRIM(RTRIM(s.value)), N'') IS NOT NULL
                 AND NOT EXISTS (SELECT 1 FROM dbo.Roles r WHERE r.RoleCode = LTRIM(RTRIM(s.value)) AND r.IsActive = 1))
        THROW 50400, N'One or more role codes are invalid.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Users WHERE Email = @Email AND (@UserId IS NULL OR UserId <> @UserId))
        THROW 50409, N'A user with this e-mail address already exists.', 1;

    DECLARE @Local TABLE (RoleId INT PRIMARY KEY, RoleCode NVARCHAR(50));
    INSERT INTO @Local (RoleId, RoleCode)
    SELECT DISTINCT r.RoleId, r.RoleCode
    FROM STRING_SPLIT(ISNULL(@RoleCodes, N''), N',') s
    INNER JOIN dbo.Roles r ON r.RoleCode = LTRIM(RTRIM(s.value)) AND r.IsActive = 1;
    INSERT INTO @Local (RoleId, RoleCode)
    SELECT r.RoleId, r.RoleCode FROM dbo.Roles r
    WHERE r.RoleCode = N'PublicUser' AND NOT EXISTS (SELECT 1 FROM @Local l WHERE l.RoleId = r.RoleId);

    DECLARE @WillBeAdmin BIT = CASE WHEN EXISTS (SELECT 1 FROM @Local WHERE RoleCode = N'Admin')
                                      OR EXISTS (SELECT 1 FROM dbo.UserRoles ur INNER JOIN dbo.Roles r ON r.RoleId = ur.RoleId
                                                 WHERE ur.UserId = @UserId AND ur.Source = N'Entra' AND r.RoleCode = N'Admin')
                                    THEN 1 ELSE 0 END;

    IF @UserId = @ActorUserId AND @IsActive = 0
        THROW 50002, N'You cannot deactivate your own account.', 1;
    IF @UserId = @ActorUserId AND dbo.fn_UserIsAdmin(@ActorUserId) = 1 AND @WillBeAdmin = 0
        THROW 50003, N'You cannot remove the Administrator role from your own account.', 1;
    IF @UserId IS NOT NULL AND dbo.fn_UserIsAdmin(@UserId) = 1 AND (@IsActive = 0 OR @WillBeAdmin = 0)
       AND NOT EXISTS (SELECT 1 FROM dbo.Users u INNER JOIN dbo.UserRoles ur ON ur.UserId = u.UserId
                       INNER JOIN dbo.Roles r ON r.RoleId = ur.RoleId AND r.RoleCode = N'Admin'
                       WHERE u.IsActive = 1 AND u.UserId <> @UserId)
        THROW 50004, N'At least one active administrator must remain.', 1;

    DECLARE @Old NVARCHAR(MAX), @Action NVARCHAR(50);

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @UserId IS NULL
        BEGIN
            SET @Action = N'Created';
            INSERT INTO dbo.Users (DisplayName, GivenName, FamilyName, Email, Phone, OrganizationName, AreaId, IsSelfRegistered, IsActive, CreatedAt, CreatedBy)
            VALUES (@DisplayName, @GivenName, @FamilyName, @Email, @Phone, @OrganizationName, @AreaId, 0, @IsActive, SYSUTCDATETIME(), @ActorUserId);
            SET @UserId = CONVERT(INT, SCOPE_IDENTITY());
        END
        ELSE
        BEGIN
            SET @Action = N'Updated';
            SET @Old = (SELECT u.DisplayName AS displayName, u.GivenName AS givenName, u.FamilyName AS familyName, u.Email AS email,
                               u.Phone AS phone, u.OrganizationName AS organizationName, u.AreaId AS areaId, u.IsActive AS isActive,
                               (SELECT STRING_AGG(r.RoleCode + N':' + ur.Source, N',') FROM dbo.UserRoles ur INNER JOIN dbo.Roles r ON r.RoleId = ur.RoleId
                                WHERE ur.UserId = u.UserId) AS roles
                        FROM dbo.Users u WHERE u.UserId = @UserId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

            UPDATE dbo.Users
            SET DisplayName = @DisplayName, GivenName = @GivenName, FamilyName = @FamilyName, Email = @Email, Phone = @Phone,
                OrganizationName = @OrganizationName, AreaId = @AreaId, IsActive = @IsActive,
                UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @ActorUserId
            WHERE UserId = @UserId;

            DELETE ur FROM dbo.UserRoles ur
            WHERE ur.UserId = @UserId AND ur.Source = N'Local'
              AND NOT EXISTS (SELECT 1 FROM @Local l WHERE l.RoleId = ur.RoleId);
        END

        INSERT INTO dbo.UserRoles (UserId, RoleId, Source, AssignedAt, AssignedBy)
        SELECT @UserId, l.RoleId, N'Local', SYSUTCDATETIME(), @ActorUserId
        FROM @Local l
        WHERE NOT EXISTS (SELECT 1 FROM dbo.UserRoles ur WHERE ur.UserId = @UserId AND ur.RoleId = l.RoleId);

        DECLARE @New NVARCHAR(MAX) = (SELECT u.DisplayName AS displayName, u.GivenName AS givenName, u.FamilyName AS familyName, u.Email AS email,
                                             u.Phone AS phone, u.OrganizationName AS organizationName, u.AreaId AS areaId, u.IsActive AS isActive,
                                             (SELECT STRING_AGG(r.RoleCode + N':' + ur.Source, N',') FROM dbo.UserRoles ur INNER JOIN dbo.Roles r ON r.RoleId = ur.RoleId
                                              WHERE ur.UserId = u.UserId) AS roles
                                      FROM dbo.Users u WHERE u.UserId = @UserId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        DECLARE @Desc NVARCHAR(1000) = N'User ' + LOWER(@Action) + N': ' + @DisplayName + N'.';

        EXEC dbo.usp_Audit_Write @ActorUserId = @ActorUserId, @EntityType = N'User', @EntityId = @UserId, @ReferenceNo = @Email,
             @Action = @Action, @Description = @Desc, @OldValues = @Old, @NewValues = @New, @SourceType = N'ManualPortal',
             @CorrelationId = @CorrelationId;

        IF @Action = N'Created'
            EXEC dbo.usp_Notification_Create @ActorUserId = @ActorUserId, @UserId = @UserId, @Title = N'Welcome to SBMRAS',
                 @Message = N'An administrator has created your SBMRAS account. Sign in with this e-mail address to get started.',
                 @Type = N'Info', @EntityType = N'User', @EntityId = @UserId, @Route = N'/dashboard';
        ELSE IF @UserId <> @ActorUserId AND ISNULL(JSON_VALUE(@Old, N'$.roles'), N'') <> ISNULL(JSON_VALUE(@New, N'$.roles'), N'')
            EXEC dbo.usp_Notification_Create @ActorUserId = @ActorUserId, @UserId = @UserId, @Title = N'Your access was updated',
                 @Message = N'An administrator changed your SBMRAS roles. Sign in again if your menu does not refresh.',
                 @Type = N'Info', @EntityType = N'User', @EntityId = @UserId, @Route = N'/profile';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    EXEC dbo.usp_Admin_GetUser @ActorUserId = @ActorUserId, @UserId = @UserId;
END
GO

/* Creates a pre-provisioned user (linked by e-mail on first Entra sign-in). Returns usp_Admin_GetUser sets. */
CREATE OR ALTER PROCEDURE dbo.usp_Admin_CreateUser
    @ActorUserId      INT,
    @DisplayName      NVARCHAR(150),
    @GivenName        NVARCHAR(100) = NULL,
    @FamilyName       NVARCHAR(100) = NULL,
    @Email            NVARCHAR(320),
    @Phone            NVARCHAR(30) = NULL,
    @OrganizationName NVARCHAR(200) = NULL,
    @AreaId           INT = NULL,
    @RoleCodes        NVARCHAR(400) = NULL,
    @IsActive         BIT = 1,
    @CorrelationId    NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC dbo.usp_Admin_SaveUser @ActorUserId = @ActorUserId, @UserId = NULL, @DisplayName = @DisplayName, @GivenName = @GivenName,
         @FamilyName = @FamilyName, @Email = @Email, @Phone = @Phone, @OrganizationName = @OrganizationName, @AreaId = @AreaId,
         @RoleCodes = @RoleCodes, @IsActive = @IsActive, @CorrelationId = @CorrelationId;
END
GO

/* Updates a user; @RoleCodes = Local roles (Entra-sourced roles are never removed). Returns usp_Admin_GetUser sets. */
CREATE OR ALTER PROCEDURE dbo.usp_Admin_UpdateUser
    @ActorUserId      INT,
    @UserId           INT,
    @DisplayName      NVARCHAR(150),
    @GivenName        NVARCHAR(100) = NULL,
    @FamilyName       NVARCHAR(100) = NULL,
    @Email            NVARCHAR(320),
    @Phone            NVARCHAR(30) = NULL,
    @OrganizationName NVARCHAR(200) = NULL,
    @AreaId           INT = NULL,
    @RoleCodes        NVARCHAR(400) = NULL,
    @IsActive         BIT = 1,
    @CorrelationId    NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @UserId IS NULL
        THROW 50404, N'User not found.', 1;

    EXEC dbo.usp_Admin_SaveUser @ActorUserId = @ActorUserId, @UserId = @UserId, @DisplayName = @DisplayName, @GivenName = @GivenName,
         @FamilyName = @FamilyName, @Email = @Email, @Phone = @Phone, @OrganizationName = @OrganizationName, @AreaId = @AreaId,
         @RoleCodes = @RoleCodes, @IsActive = @IsActive, @CorrelationId = @CorrelationId;
END
GO

/* Activates / deactivates a user. Returns usp_Admin_GetUser sets. */
CREATE OR ALTER PROCEDURE dbo.usp_Admin_SetUserStatus
    @ActorUserId   INT,
    @UserId        INT,
    @IsActive      BIT,
    @CorrelationId NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'users.manage') = 0
        THROW 50403, N'You do not have permission to manage users.', 1;

    DECLARE @OldActive BIT, @Email NVARCHAR(320);
    SELECT @OldActive = IsActive, @Email = Email FROM dbo.Users WHERE UserId = @UserId;

    IF @OldActive IS NULL
        THROW 50404, N'User not found.', 1;
    IF @IsActive IS NULL
        THROW 50400, N'isActive is required.', 1;
    IF @UserId = @ActorUserId AND @IsActive = 0
        THROW 50002, N'You cannot deactivate your own account.', 1;
    IF @IsActive = 0 AND dbo.fn_UserIsAdmin(@UserId) = 1
       AND NOT EXISTS (SELECT 1 FROM dbo.Users u INNER JOIN dbo.UserRoles ur ON ur.UserId = u.UserId
                       INNER JOIN dbo.Roles r ON r.RoleId = ur.RoleId AND r.RoleCode = N'Admin'
                       WHERE u.IsActive = 1 AND u.UserId <> @UserId)
        THROW 50004, N'At least one active administrator must remain.', 1;

    IF @OldActive <> @IsActive
    BEGIN
        BEGIN TRY
            BEGIN TRANSACTION;

            UPDATE dbo.Users SET IsActive = @IsActive, UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @ActorUserId WHERE UserId = @UserId;

            DECLARE @Old NVARCHAR(MAX) = (SELECT @OldActive AS isActive FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            DECLARE @New NVARCHAR(MAX) = (SELECT @IsActive AS isActive FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            DECLARE @Action NVARCHAR(50) = CASE WHEN @IsActive = 1 THEN N'Activated' ELSE N'Deactivated' END;
            DECLARE @Desc NVARCHAR(1000) = N'User account ' + LOWER(@Action) + N'.';

            EXEC dbo.usp_Audit_Write @ActorUserId = @ActorUserId, @EntityType = N'User', @EntityId = @UserId, @ReferenceNo = @Email,
                 @Action = @Action, @Description = @Desc, @OldValues = @Old, @NewValues = @New, @CorrelationId = @CorrelationId;

            IF @IsActive = 1
                EXEC dbo.usp_Notification_Create @ActorUserId = @ActorUserId, @UserId = @UserId, @Title = N'Account reactivated',
                     @Message = N'Your SBMRAS account has been reactivated by an administrator.', @Type = N'Info',
                     @EntityType = N'User', @EntityId = @UserId, @Route = N'/dashboard';

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            THROW;
        END CATCH
    END

    EXEC dbo.usp_Admin_GetUser @ActorUserId = @ActorUserId, @UserId = @UserId;
END
GO

/*
  Replaces the active facility assignments of a user.
  @AssignmentsJson = [{ "facilityId": 1, "assignmentRole": "Manager" }, ...] (empty array removes all).
  Hospital assignments require the HospitalManagement role, blood bank assignments the BloodBank role (Admins may hold any).
  Removed assignments are end-dated (IsActive = 0, EndedAt). Returns usp_Admin_GetUser sets.
*/
CREATE OR ALTER PROCEDURE dbo.usp_Admin_SetUserFacilities
    @ActorUserId     INT,
    @UserId          INT,
    @AssignmentsJson NVARCHAR(MAX),
    @CorrelationId   NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'users.manage') = 0
        THROW 50403, N'You do not have permission to manage users.', 1;

    DECLARE @Email NVARCHAR(320), @UserActive BIT;
    SELECT @Email = Email, @UserActive = IsActive FROM dbo.Users WHERE UserId = @UserId;
    IF @UserActive IS NULL
        THROW 50404, N'User not found.', 1;

    SET @AssignmentsJson = NULLIF(LTRIM(RTRIM(@AssignmentsJson)), N'');
    IF @AssignmentsJson IS NULL SET @AssignmentsJson = N'[]';
    IF ISJSON(@AssignmentsJson) = 0
        THROW 50400, N'Assignments must be a JSON array.', 1;
    IF LEFT(@AssignmentsJson, 1) = N'{' AND JSON_QUERY(@AssignmentsJson, N'$.assignments') IS NOT NULL
        SET @AssignmentsJson = JSON_QUERY(@AssignmentsJson, N'$.assignments');

    DECLARE @Rows TABLE (FacilityId INT NULL, AssignmentRole NVARCHAR(20) NULL);
    INSERT INTO @Rows (FacilityId, AssignmentRole)
    SELECT TRY_CONVERT(INT, j.facilityId), NULLIF(LTRIM(RTRIM(j.assignmentRole)), N'')
    FROM OPENJSON(@AssignmentsJson) WITH (facilityId NVARCHAR(20) N'$.facilityId', assignmentRole NVARCHAR(40) N'$.assignmentRole') j;

    IF EXISTS (SELECT 1 FROM @Rows WHERE FacilityId IS NULL)
        THROW 50400, N'Each assignment requires a facility.', 1;
    IF EXISTS (SELECT 1 FROM @Rows WHERE ISNULL(AssignmentRole, N'') NOT IN (N'Manager', N'Operator', N'Verifier'))
        THROW 50400, N'Assignment role must be Manager, Operator or Verifier.', 1;
    IF EXISTS (SELECT FacilityId FROM @Rows GROUP BY FacilityId HAVING COUNT(*) > 1)
        THROW 50400, N'A facility can only be assigned once per user.', 1;
    IF EXISTS (SELECT 1 FROM @Rows r WHERE NOT EXISTS (SELECT 1 FROM dbo.Facilities f WHERE f.FacilityId = r.FacilityId))
        THROW 50404, N'Facility not found.', 1;
    IF EXISTS (SELECT 1 FROM @Rows r WHERE NOT EXISTS (SELECT 1 FROM dbo.Facilities f WHERE f.FacilityId = r.FacilityId AND f.IsActive = 1)
                                     AND NOT EXISTS (SELECT 1 FROM dbo.FacilityUserAssignments fa
                                                     WHERE fa.UserId = @UserId AND fa.FacilityId = r.FacilityId AND fa.IsActive = 1))
        THROW 50005, N'Users cannot be newly assigned to an inactive facility.', 1;

    DECLARE @IsAdmin BIT = dbo.fn_UserIsAdmin(@UserId);
    IF @IsAdmin = 0 AND EXISTS (
            SELECT 1 FROM @Rows r INNER JOIN dbo.Facilities f ON f.FacilityId = r.FacilityId
            WHERE NOT EXISTS (SELECT 1 FROM dbo.UserRoles ur INNER JOIN dbo.Roles ro ON ro.RoleId = ur.RoleId AND ro.IsActive = 1
                              WHERE ur.UserId = @UserId
                                AND ro.RoleCode = CASE f.FacilityType WHEN N'Hospital' THEN N'HospitalManagement' ELSE N'BloodBank' END))
        THROW 50006, N'Hospital assignments require the Hospital Management role and blood bank assignments require the Blood Bank role.', 1;

    DECLARE @Old NVARCHAR(MAX) = (SELECT fa.FacilityId AS facilityId, fa.AssignmentRole AS assignmentRole
                                  FROM dbo.FacilityUserAssignments fa WHERE fa.UserId = @UserId AND fa.IsActive = 1
                                  ORDER BY fa.FacilityId FOR JSON PATH);
    DECLARE @New NVARCHAR(MAX) = (SELECT r.FacilityId AS facilityId, r.AssignmentRole AS assignmentRole FROM @Rows r ORDER BY r.FacilityId FOR JSON PATH);

    IF ISNULL(@Old, N'[]') <> ISNULL(@New, N'[]')
    BEGIN
        BEGIN TRY
            BEGIN TRANSACTION;

            UPDATE fa
            SET IsActive = 0, EndedAt = SYSUTCDATETIME()
            FROM dbo.FacilityUserAssignments fa
            WHERE fa.UserId = @UserId AND fa.IsActive = 1
              AND NOT EXISTS (SELECT 1 FROM @Rows r WHERE r.FacilityId = fa.FacilityId);

            UPDATE fa
            SET AssignmentRole = r.AssignmentRole,
                AssignedAt = CASE WHEN fa.IsActive = 0 THEN SYSUTCDATETIME() ELSE fa.AssignedAt END,
                AssignedBy = CASE WHEN fa.IsActive = 0 OR fa.AssignmentRole <> r.AssignmentRole THEN @ActorUserId ELSE fa.AssignedBy END,
                IsActive = 1, EndedAt = NULL
            FROM dbo.FacilityUserAssignments fa
            INNER JOIN @Rows r ON r.FacilityId = fa.FacilityId
            WHERE fa.UserId = @UserId
              AND (fa.IsActive = 0 OR fa.AssignmentRole <> r.AssignmentRole);

            INSERT INTO dbo.FacilityUserAssignments (FacilityId, UserId, AssignmentRole, IsActive, AssignedAt, AssignedBy)
            SELECT r.FacilityId, @UserId, r.AssignmentRole, 1, SYSUTCDATETIME(), @ActorUserId
            FROM @Rows r
            WHERE NOT EXISTS (SELECT 1 FROM dbo.FacilityUserAssignments fa WHERE fa.UserId = @UserId AND fa.FacilityId = r.FacilityId);

            EXEC dbo.usp_Audit_Write @ActorUserId = @ActorUserId, @EntityType = N'User', @EntityId = @UserId, @ReferenceNo = @Email,
                 @Action = N'FacilitiesAssigned', @Description = N'Facility assignments updated.',
                 @OldValues = @Old, @NewValues = @New, @CorrelationId = @CorrelationId;

            EXEC dbo.usp_Notification_Create @ActorUserId = @ActorUserId, @UserId = @UserId, @Title = N'Facility assignments updated',
                 @Message = N'An administrator updated the facilities you are assigned to.', @Type = N'Info',
                 @EntityType = N'User', @EntityId = @UserId, @Route = N'/facilities';

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            THROW;
        END CATCH
    END

    EXEC dbo.usp_Admin_GetUser @ActorUserId = @ActorUserId, @UserId = @UserId;
END
GO

/*---------------------------------------------------------------------
  Roles & permissions
---------------------------------------------------------------------*/

/* Roles with active user counts and CSV PermissionCodes (roles.manage). */
CREATE OR ALTER PROCEDURE dbo.usp_Admin_GetRoles
    @ActorUserId INT,
    @RoleId      INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'roles.manage') = 0
        THROW 50403, N'You do not have permission to manage roles.', 1;

    SELECT r.RoleId, r.RoleCode, r.RoleName, r.Description, r.EntraAppRole, r.EntraGroupName, r.IsSystem, r.IsActive,
           (SELECT COUNT(*) FROM dbo.UserRoles ur INNER JOIN dbo.Users u ON u.UserId = ur.UserId AND u.IsActive = 1 WHERE ur.RoleId = r.RoleId) AS UserCount,
           (SELECT STRING_AGG(p.PermissionCode, N',') WITHIN GROUP (ORDER BY p.PermissionCode)
            FROM dbo.RolePermissions rp INNER JOIN dbo.Permissions p ON p.PermissionId = rp.PermissionId
            WHERE rp.RoleId = r.RoleId) AS PermissionCodes
    FROM dbo.Roles r
    WHERE @RoleId IS NULL OR r.RoleId = @RoleId
    ORDER BY CASE r.RoleCode WHEN N'PublicUser' THEN 1 WHEN N'HospitalManagement' THEN 2 WHEN N'BloodBank' THEN 3 WHEN N'Admin' THEN 4 ELSE 5 END, r.RoleId;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_GetPermissions
    @ActorUserId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'roles.manage') = 0
        THROW 50403, N'You do not have permission to manage roles.', 1;

    SELECT p.PermissionId, p.PermissionCode, p.PermissionName, p.Module, p.Description
    FROM dbo.Permissions p
    ORDER BY p.Module, p.PermissionCode;
END
GO

/* Replaces the permission set of a role (CSV). The Admin role must keep users.manage and roles.manage. Returns the role row. */
CREATE OR ALTER PROCEDURE dbo.usp_Admin_UpdateRolePermissions
    @ActorUserId     INT,
    @RoleId          INT,
    @PermissionCodes NVARCHAR(MAX) = NULL,
    @CorrelationId   NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'roles.manage') = 0
        THROW 50403, N'You do not have permission to manage roles.', 1;

    DECLARE @RoleCode NVARCHAR(50) = (SELECT RoleCode FROM dbo.Roles WHERE RoleId = @RoleId);
    IF @RoleCode IS NULL
        THROW 50404, N'Role not found.', 1;

    IF EXISTS (SELECT 1 FROM STRING_SPLIT(ISNULL(@PermissionCodes, N''), N',') s
               WHERE NULLIF(LTRIM(RTRIM(s.value)), N'') IS NOT NULL
                 AND NOT EXISTS (SELECT 1 FROM dbo.Permissions p WHERE p.PermissionCode = LTRIM(RTRIM(s.value))))
        THROW 50400, N'One or more permission codes are invalid.', 1;

    DECLARE @Perms TABLE (PermissionId INT PRIMARY KEY, PermissionCode NVARCHAR(60));
    INSERT INTO @Perms (PermissionId, PermissionCode)
    SELECT DISTINCT p.PermissionId, p.PermissionCode
    FROM STRING_SPLIT(ISNULL(@PermissionCodes, N''), N',') s
    INNER JOIN dbo.Permissions p ON p.PermissionCode = LTRIM(RTRIM(s.value));

    IF @RoleCode = N'Admin' AND (NOT EXISTS (SELECT 1 FROM @Perms WHERE PermissionCode = N'roles.manage')
                                 OR NOT EXISTS (SELECT 1 FROM @Perms WHERE PermissionCode = N'users.manage'))
        THROW 50007, N'The Administrator role must keep the users.manage and roles.manage permissions.', 1;

    DECLARE @Old NVARCHAR(MAX) = (SELECT STRING_AGG(p.PermissionCode, N',') WITHIN GROUP (ORDER BY p.PermissionCode)
                                  FROM dbo.RolePermissions rp INNER JOIN dbo.Permissions p ON p.PermissionId = rp.PermissionId
                                  WHERE rp.RoleId = @RoleId);
    DECLARE @New NVARCHAR(MAX) = (SELECT STRING_AGG(p.PermissionCode, N',') WITHIN GROUP (ORDER BY p.PermissionCode) FROM @Perms p);

    IF ISNULL(@Old, N'') <> ISNULL(@New, N'')
    BEGIN
        BEGIN TRY
            BEGIN TRANSACTION;

            DELETE rp FROM dbo.RolePermissions rp
            WHERE rp.RoleId = @RoleId AND NOT EXISTS (SELECT 1 FROM @Perms p WHERE p.PermissionId = rp.PermissionId);

            INSERT INTO dbo.RolePermissions (RoleId, PermissionId)
            SELECT @RoleId, p.PermissionId FROM @Perms p
            WHERE NOT EXISTS (SELECT 1 FROM dbo.RolePermissions rp WHERE rp.RoleId = @RoleId AND rp.PermissionId = p.PermissionId);

            DECLARE @OldJson NVARCHAR(MAX) = (SELECT @Old AS permissionCodes FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);
            DECLARE @NewJson NVARCHAR(MAX) = (SELECT @New AS permissionCodes FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

            EXEC dbo.usp_Audit_Write @ActorUserId = @ActorUserId, @EntityType = N'Role', @EntityId = @RoleId, @ReferenceNo = @RoleCode,
                 @Action = N'PermissionsUpdated', @Description = N'Role permissions updated.', @OldValues = @OldJson, @NewValues = @NewJson,
                 @CorrelationId = @CorrelationId;

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            THROW;
        END CATCH
    END

    EXEC dbo.usp_Admin_GetRoles @ActorUserId = @ActorUserId, @RoleId = @RoleId;
END
GO

/*---------------------------------------------------------------------
  Facility registry & verification (facilities.verify)
---------------------------------------------------------------------*/

/* Paged facilities for administration (GET admin/facilities). Result set 1: Facility rows; 2: TotalCount. */
CREATE OR ALTER PROCEDURE dbo.usp_Facility_AdminSearch
    @ActorUserId  INT,
    @Status       NVARCHAR(20) = NULL,
    @FacilityType NVARCHAR(20) = NULL,
    @Search       NVARCHAR(200) = NULL,
    @FacilityId   INT = NULL,
    @Page         INT = 1,
    @PageSize     INT = 20,
    @IncludeTotal BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'facilities.verify') = 0
        THROW 50403, N'You do not have permission to administer facilities.', 1;

    SET @Page = CASE WHEN ISNULL(@Page, 1) < 1 THEN 1 ELSE @Page END;
    SET @PageSize = CASE WHEN ISNULL(@PageSize, 20) < 1 THEN 20 WHEN @PageSize > 100 THEN 100 ELSE @PageSize END;
    SET @Status = NULLIF(LTRIM(RTRIM(@Status)), N'');
    SET @FacilityType = NULLIF(LTRIM(RTRIM(@FacilityType)), N'');
    SET @Search = NULLIF(LTRIM(RTRIM(@Search)), N'');

    DECLARE @Ids TABLE (FacilityId INT PRIMARY KEY);
    INSERT INTO @Ids (FacilityId)
    SELECT f.FacilityId
    FROM dbo.Facilities f
    LEFT JOIN dbo.Areas a ON a.AreaId = f.AreaId
    WHERE (@FacilityId IS NULL OR f.FacilityId = @FacilityId)
      AND (@Status IS NULL
           OR (@Status = N'Inactive' AND f.IsActive = 0)
           OR (@Status = N'Active' AND f.IsActive = 1)
           OR f.VerificationStatus = @Status)
      AND (@FacilityType IS NULL OR f.FacilityType = @FacilityType)
      AND (@Search IS NULL OR f.Name LIKE N'%' + @Search + N'%' OR f.FacilityCode LIKE N'%' + @Search + N'%'
           OR f.LicenseNo LIKE N'%' + @Search + N'%' OR f.City LIKE N'%' + @Search + N'%' OR a.Name LIKE N'%' + @Search + N'%');

    SELECT f.FacilityId, f.FacilityCode, f.Name, f.FacilityType, f.LicenseNo, f.AddressLine, f.AreaId, a.Name AS AreaName, f.City,
           f.Pincode, f.Latitude, f.Longitude, f.ContactPhone, f.ContactEmail, f.Is24x7, f.VerificationStatus, f.VerifiedAt,
           vb.DisplayName AS VerifiedByName, f.VerificationNotes, f.IsActive,
           q.QualityScore, q.FreshPercent, ISNULL(q.StaleRecords, 0) AS StaleRecords, q.LastUpdateAt,
           (SELECT COUNT(*) FROM dbo.FacilityUserAssignments fa WHERE fa.FacilityId = f.FacilityId AND fa.IsActive = 1) AS AssignedUsers,
           f.RowVer AS RowVersion, f.CreatedAt
    FROM @Ids i
    INNER JOIN dbo.Facilities f ON f.FacilityId = i.FacilityId
    LEFT JOIN dbo.Areas a ON a.AreaId = f.AreaId
    LEFT JOIN dbo.Users vb ON vb.UserId = f.VerifiedBy
    LEFT JOIN dbo.vw_FacilityQualityScore q ON q.FacilityId = f.FacilityId
    ORDER BY CASE f.VerificationStatus WHEN N'Pending' THEN 1 WHEN N'Suspended' THEN 2 WHEN N'Rejected' THEN 3 ELSE 4 END, f.Name, f.FacilityId
    OFFSET (@Page - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

    IF ISNULL(@IncludeTotal, 1) = 1
        SELECT COUNT(*) AS TotalCount FROM @Ids;
END
GO

/* Internal: validates and saves a facility (insert when @FacilityId is NULL). Returns the Facility row. */
CREATE OR ALTER PROCEDURE dbo.usp_Facility_AdminSave
    @ActorUserId   INT,
    @FacilityId    INT = NULL,
    @FacilityType  NVARCHAR(20) = NULL,
    @Name          NVARCHAR(200),
    @LicenseNo     NVARCHAR(60) = NULL,
    @AddressLine   NVARCHAR(300),
    @AreaId        INT,
    @City          NVARCHAR(100) = NULL,
    @Pincode       NVARCHAR(10) = NULL,
    @Latitude      DECIMAL(9,6) = NULL,
    @Longitude     DECIMAL(9,6) = NULL,
    @ContactPhone  NVARCHAR(30),
    @ContactEmail  NVARCHAR(320) = NULL,
    @Is24x7        BIT = 0,
    @IsActive      BIT = NULL,
    @RowVersion    VARBINARY(8) = NULL,
    @CorrelationId NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'facilities.verify') = 0
        THROW 50403, N'You do not have permission to administer facilities.', 1;

    DECLARE @CurType NVARCHAR(20), @CurRowVer VARBINARY(8), @CurActive BIT;
    IF @FacilityId IS NOT NULL
    BEGIN
        SELECT @CurType = FacilityType, @CurRowVer = CAST(RowVer AS VARBINARY(8)), @CurActive = IsActive FROM dbo.Facilities WHERE FacilityId = @FacilityId;
        IF @CurType IS NULL
            THROW 50404, N'Facility not found.', 1;
        IF @RowVersion IS NOT NULL AND @RowVersion <> @CurRowVer
            THROW 50409, N'The facility was changed by someone else. Reload and try again.', 1;
    END

    SET @FacilityType = COALESCE(NULLIF(LTRIM(RTRIM(@FacilityType)), N''), @CurType);
    SET @Name = NULLIF(LTRIM(RTRIM(@Name)), N'');
    SET @LicenseNo = NULLIF(LTRIM(RTRIM(@LicenseNo)), N'');
    SET @AddressLine = NULLIF(LTRIM(RTRIM(@AddressLine)), N'');
    SET @City = NULLIF(LTRIM(RTRIM(@City)), N'');
    SET @Pincode = NULLIF(LTRIM(RTRIM(@Pincode)), N'');
    SET @ContactPhone = NULLIF(LTRIM(RTRIM(@ContactPhone)), N'');
    SET @ContactEmail = LOWER(NULLIF(LTRIM(RTRIM(@ContactEmail)), N''));
    SET @Is24x7 = ISNULL(@Is24x7, 0);
    SET @IsActive = COALESCE(@IsActive, @CurActive, 1);

    IF @FacilityType IS NULL OR @FacilityType NOT IN (N'Hospital', N'BloodBank')
        THROW 50400, N'Facility type must be Hospital or BloodBank.', 1;
    IF @Name IS NULL
        THROW 50400, N'Facility name is required.', 1;
    IF @AddressLine IS NULL
        THROW 50400, N'Address is required.', 1;
    IF @ContactPhone IS NULL
        THROW 50400, N'Contact phone is required.', 1;
    IF @ContactEmail IS NOT NULL AND @ContactEmail NOT LIKE N'_%@_%._%'
        THROW 50400, N'Contact e-mail is not valid.', 1;
    IF @Latitude IS NOT NULL AND (@Latitude < -90 OR @Latitude > 90)
        THROW 50400, N'Latitude must be between -90 and 90.', 1;
    IF @Longitude IS NOT NULL AND (@Longitude < -180 OR @Longitude > 180)
        THROW 50400, N'Longitude must be between -180 and 180.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Areas WHERE AreaId = @AreaId)
        THROW 50400, N'Select a valid area.', 1;
    SET @City = COALESCE(@City, (SELECT City FROM dbo.Areas WHERE AreaId = @AreaId));

    IF @CurType IS NOT NULL AND @CurType <> @FacilityType
       AND (EXISTS (SELECT 1 FROM dbo.BloodInventory WHERE FacilityId = @FacilityId)
            OR EXISTS (SELECT 1 FROM dbo.MedicalResourceInventory WHERE FacilityId = @FacilityId))
        THROW 50008, N'The facility type cannot be changed once inventory has been recorded.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Facilities WHERE Name = @Name AND AreaId = @AreaId AND (@FacilityId IS NULL OR FacilityId <> @FacilityId))
        THROW 50409, N'A facility with this name already exists in the area.', 1;
    IF @LicenseNo IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.Facilities WHERE LicenseNo = @LicenseNo AND (@FacilityId IS NULL OR FacilityId <> @FacilityId))
        THROW 50409, N'A facility with this licence number already exists.', 1;

    DECLARE @Old NVARCHAR(MAX), @Action NVARCHAR(50), @Code NVARCHAR(20);

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @FacilityId IS NULL
        BEGIN
            SET @Action = N'Created';
            DECLARE @Prefix NVARCHAR(3) = CASE @FacilityType WHEN N'Hospital' THEN N'HSP' ELSE N'BBK' END;
            DECLARE @Number INT = 1 + ISNULL((SELECT MAX(TRY_CONVERT(INT, SUBSTRING(FacilityCode, 5, 10)))
                                              FROM dbo.Facilities WITH (UPDLOCK, HOLDLOCK)
                                              WHERE FacilityCode LIKE @Prefix + N'-%'), 0);
            SET @Code = @Prefix + N'-' + RIGHT(N'0000' + CAST(@Number AS NVARCHAR(10)), CASE WHEN @Number > 9999 THEN 10 ELSE 4 END);

            INSERT INTO dbo.Facilities (FacilityCode, Name, FacilityType, LicenseNo, AddressLine, AreaId, City, Pincode, Latitude, Longitude,
                                        ContactPhone, ContactEmail, Is24x7, VerificationStatus, IsActive, CreatedAt, CreatedBy)
            VALUES (@Code, @Name, @FacilityType, @LicenseNo, @AddressLine, @AreaId, @City, @Pincode, @Latitude, @Longitude,
                    @ContactPhone, @ContactEmail, @Is24x7, N'Pending', @IsActive, SYSUTCDATETIME(), @ActorUserId);
            SET @FacilityId = CONVERT(INT, SCOPE_IDENTITY());
        END
        ELSE
        BEGIN
            SET @Action = N'Updated';
            SET @Code = (SELECT FacilityCode FROM dbo.Facilities WHERE FacilityId = @FacilityId);
            SET @Old = (SELECT f.Name AS name, f.FacilityType AS facilityType, f.LicenseNo AS licenseNo, f.AddressLine AS addressLine,
                               f.AreaId AS areaId, f.City AS city, f.Pincode AS pincode, f.Latitude AS latitude, f.Longitude AS longitude,
                               f.ContactPhone AS contactPhone, f.ContactEmail AS contactEmail, f.Is24x7 AS is24x7, f.IsActive AS isActive
                        FROM dbo.Facilities f WHERE f.FacilityId = @FacilityId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

            UPDATE dbo.Facilities
            SET Name = @Name, FacilityType = @FacilityType, LicenseNo = @LicenseNo, AddressLine = @AddressLine, AreaId = @AreaId,
                City = @City, Pincode = @Pincode, Latitude = @Latitude, Longitude = @Longitude, ContactPhone = @ContactPhone,
                ContactEmail = @ContactEmail, Is24x7 = @Is24x7, IsActive = @IsActive, UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @ActorUserId
            WHERE FacilityId = @FacilityId;
        END

        DECLARE @New NVARCHAR(MAX) = (SELECT f.Name AS name, f.FacilityType AS facilityType, f.LicenseNo AS licenseNo, f.AddressLine AS addressLine,
                                             f.AreaId AS areaId, f.City AS city, f.Pincode AS pincode, f.Latitude AS latitude, f.Longitude AS longitude,
                                             f.ContactPhone AS contactPhone, f.ContactEmail AS contactEmail, f.Is24x7 AS is24x7, f.IsActive AS isActive,
                                             f.VerificationStatus AS verificationStatus
                                      FROM dbo.Facilities f WHERE f.FacilityId = @FacilityId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        DECLARE @Desc NVARCHAR(1000) = N'Facility ' + LOWER(@Action) + N': ' + @Name + N'.';

        EXEC dbo.usp_Audit_Write @ActorUserId = @ActorUserId, @EntityType = N'Facility', @EntityId = @FacilityId, @ReferenceNo = @Code,
             @FacilityId = @FacilityId, @Action = @Action, @Description = @Desc, @OldValues = @Old, @NewValues = @New,
             @SourceType = N'AdminCorrection', @CorrelationId = @CorrelationId;

        IF @Action = N'Updated'
            EXEC dbo.usp_Notification_NotifyFacilityUsers @ActorUserId = @ActorUserId, @FacilityId = @FacilityId,
                 @Title = N'Facility profile updated', @Message = @Desc, @Type = N'Info',
                 @EntityType = N'Facility', @EntityId = @FacilityId, @Route = N'/facilities';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    EXEC dbo.usp_Facility_AdminSearch @ActorUserId = @ActorUserId, @FacilityId = @FacilityId, @Page = 1, @PageSize = 1, @IncludeTotal = 0;
END
GO

/* Registers a facility (VerificationStatus = Pending). Returns the Facility row. */
CREATE OR ALTER PROCEDURE dbo.usp_Facility_Create
    @ActorUserId   INT,
    @FacilityType  NVARCHAR(20),
    @Name          NVARCHAR(200),
    @LicenseNo     NVARCHAR(60) = NULL,
    @AddressLine   NVARCHAR(300),
    @AreaId        INT,
    @City          NVARCHAR(100) = NULL,
    @Pincode       NVARCHAR(10) = NULL,
    @Latitude      DECIMAL(9,6) = NULL,
    @Longitude     DECIMAL(9,6) = NULL,
    @ContactPhone  NVARCHAR(30),
    @ContactEmail  NVARCHAR(320) = NULL,
    @Is24x7        BIT = 0,
    @CorrelationId NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC dbo.usp_Facility_AdminSave @ActorUserId = @ActorUserId, @FacilityId = NULL, @FacilityType = @FacilityType, @Name = @Name,
         @LicenseNo = @LicenseNo, @AddressLine = @AddressLine, @AreaId = @AreaId, @City = @City, @Pincode = @Pincode,
         @Latitude = @Latitude, @Longitude = @Longitude, @ContactPhone = @ContactPhone, @ContactEmail = @ContactEmail,
         @Is24x7 = @Is24x7, @IsActive = 1, @CorrelationId = @CorrelationId;
END
GO

/* Admin update of any facility (type change only while no inventory exists). Returns the Facility row. */
CREATE OR ALTER PROCEDURE dbo.usp_Facility_AdminUpdate
    @ActorUserId   INT,
    @FacilityId    INT,
    @FacilityType  NVARCHAR(20) = NULL,
    @Name          NVARCHAR(200),
    @LicenseNo     NVARCHAR(60) = NULL,
    @AddressLine   NVARCHAR(300),
    @AreaId        INT,
    @City          NVARCHAR(100) = NULL,
    @Pincode       NVARCHAR(10) = NULL,
    @Latitude      DECIMAL(9,6) = NULL,
    @Longitude     DECIMAL(9,6) = NULL,
    @ContactPhone  NVARCHAR(30),
    @ContactEmail  NVARCHAR(320) = NULL,
    @Is24x7        BIT = 0,
    @IsActive      BIT = NULL,
    @RowVersion    VARBINARY(8) = NULL,
    @CorrelationId NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @FacilityId IS NULL
        THROW 50404, N'Facility not found.', 1;

    EXEC dbo.usp_Facility_AdminSave @ActorUserId = @ActorUserId, @FacilityId = @FacilityId, @FacilityType = @FacilityType, @Name = @Name,
         @LicenseNo = @LicenseNo, @AddressLine = @AddressLine, @AreaId = @AreaId, @City = @City, @Pincode = @Pincode,
         @Latitude = @Latitude, @Longitude = @Longitude, @ContactPhone = @ContactPhone, @ContactEmail = @ContactEmail,
         @Is24x7 = @Is24x7, @IsActive = @IsActive, @RowVersion = @RowVersion, @CorrelationId = @CorrelationId;
END
GO

/*
  Facility verification decision (facilities.verify):
    Verify     Pending | Rejected -> Verified
    Reject     Pending            -> Rejected   (notes required)
    Suspend    Verified           -> Suspended  (notes required)
    Reactivate Suspended          -> Verified
  Invalid transition -> 50409. Returns the Facility row.
*/
CREATE OR ALTER PROCEDURE dbo.usp_Facility_Verify
    @ActorUserId   INT,
    @FacilityId    INT,
    @Decision      NVARCHAR(20),
    @Notes         NVARCHAR(500) = NULL,
    @CorrelationId NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'facilities.verify') = 0
        THROW 50403, N'You do not have permission to verify facilities.', 1;

    DECLARE @From NVARCHAR(20), @Code NVARCHAR(20), @Name NVARCHAR(200);
    SELECT @From = VerificationStatus, @Code = FacilityCode, @Name = Name FROM dbo.Facilities WHERE FacilityId = @FacilityId;
    IF @From IS NULL
        THROW 50404, N'Facility not found.', 1;

    SET @Decision = NULLIF(LTRIM(RTRIM(@Decision)), N'');
    SET @Notes = NULLIF(LTRIM(RTRIM(@Notes)), N'');
    IF @Decision IS NULL OR @Decision NOT IN (N'Verify', N'Reject', N'Suspend', N'Reactivate')
        THROW 50400, N'Decision must be Verify, Reject, Suspend or Reactivate.', 1;
    IF @Decision IN (N'Reject', N'Suspend') AND @Notes IS NULL
        THROW 50400, N'Notes are required to reject or suspend a facility.', 1;

    DECLARE @To NVARCHAR(20) =
        CASE
            WHEN @Decision = N'Verify' AND @From IN (N'Pending', N'Rejected') THEN N'Verified'
            WHEN @Decision = N'Reject' AND @From = N'Pending' THEN N'Rejected'
            WHEN @Decision = N'Suspend' AND @From = N'Verified' THEN N'Suspended'
            WHEN @Decision = N'Reactivate' AND @From = N'Suspended' THEN N'Verified'
        END;
    IF @To IS NULL
    BEGIN
        DECLARE @Msg NVARCHAR(300) = N'A ' + @From + N' facility cannot be processed with decision ' + @Decision + N'.';
        THROW 50409, @Msg, 1;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.Facilities
        SET VerificationStatus = @To,
            VerifiedAt = CASE WHEN @To = N'Verified' THEN SYSUTCDATETIME() ELSE VerifiedAt END,
            VerifiedBy = CASE WHEN @To = N'Verified' THEN @ActorUserId ELSE VerifiedBy END,
            VerificationNotes = COALESCE(@Notes, VerificationNotes),
            IsActive = CASE WHEN @To = N'Verified' THEN 1 ELSE IsActive END,
            UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @ActorUserId
        WHERE FacilityId = @FacilityId;

        DECLARE @Old NVARCHAR(MAX) = (SELECT @From AS verificationStatus FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        DECLARE @New NVARCHAR(MAX) = (SELECT @To AS verificationStatus, @Notes AS notes FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        DECLARE @Action NVARCHAR(50) = CASE @Decision WHEN N'Verify' THEN N'Verified' WHEN N'Reject' THEN N'Rejected'
                                                      WHEN N'Suspend' THEN N'Suspended' ELSE N'Reactivated' END;
        DECLARE @Desc NVARCHAR(1000) = N'Facility ' + @Name + N' ' + LOWER(@Action) + N' (' + @From + N' -> ' + @To + N').';

        EXEC dbo.usp_Audit_Write @ActorUserId = @ActorUserId, @EntityType = N'Facility', @EntityId = @FacilityId, @ReferenceNo = @Code,
             @FacilityId = @FacilityId, @Action = @Action, @Description = @Desc, @OldValues = @Old, @NewValues = @New,
             @Reason = @Notes, @CorrelationId = @CorrelationId;

        DECLARE @Title NVARCHAR(200) = N'Facility ' + LOWER(@Action);
        DECLARE @Type NVARCHAR(20) = CASE WHEN @To = N'Verified' THEN N'Success' ELSE N'Warning' END;
        DECLARE @NotifyMsg NVARCHAR(1000) = @Desc + CASE WHEN @Notes IS NOT NULL THEN N' Notes: ' + @Notes ELSE N'' END;
        EXEC dbo.usp_Notification_NotifyFacilityUsers @ActorUserId = @ActorUserId, @FacilityId = @FacilityId,
             @Title = @Title, @Message = @NotifyMsg, @Type = @Type,
             @EntityType = N'Facility', @EntityId = @FacilityId, @Route = N'/facilities';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    EXEC dbo.usp_Facility_AdminSearch @ActorUserId = @ActorUserId, @FacilityId = @FacilityId, @Page = 1, @PageSize = 1, @IncludeTotal = 0;
END
GO

/*---------------------------------------------------------------------
  Master data (masterdata.manage)
  @Type: areas | components | units | resource-categories | resource-types
  Every row has a generic Id column plus the typed key.
---------------------------------------------------------------------*/
CREATE OR ALTER PROCEDURE dbo.usp_MasterData_Get
    @ActorUserId INT,
    @Type        NVARCHAR(40),
    @Id          INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'masterdata.manage') = 0
        THROW 50403, N'You do not have permission to manage master data.', 1;

    SET @Type = LOWER(LTRIM(RTRIM(@Type)));

    IF @Type = N'areas'
        SELECT a.AreaId AS Id, a.AreaId, a.Name, a.City, a.State, a.Pincode, a.IsActive
        FROM dbo.Areas a WHERE @Id IS NULL OR a.AreaId = @Id ORDER BY a.Name;
    ELSE IF @Type = N'components'
        SELECT c.ComponentId AS Id, c.ComponentId, c.Code, c.Name, c.ShelfLifeDays, c.StorageNote, c.IsActive
        FROM dbo.BloodComponents c WHERE @Id IS NULL OR c.ComponentId = @Id ORDER BY c.ComponentId;
    ELSE IF @Type = N'units'
        SELECT u.UnitId AS Id, u.UnitId, u.Code, u.Name, u.IsActive
        FROM dbo.Units u WHERE @Id IS NULL OR u.UnitId = @Id ORDER BY u.UnitId;
    ELSE IF @Type = N'resource-categories'
        SELECT rc.CategoryId AS Id, rc.CategoryId, rc.Name, rc.Description, rc.IsActive
        FROM dbo.ResourceCategories rc WHERE @Id IS NULL OR rc.CategoryId = @Id ORDER BY rc.Name;
    ELSE IF @Type = N'resource-types'
        SELECT t.ResourceTypeId AS Id, t.ResourceTypeId, t.CategoryId, rc.Name AS CategoryName, t.Code, t.Name, t.DefaultUnitId,
               u.Code AS UnitCode, t.TrackingMode, t.IsActive
        FROM dbo.MedicalResourceTypes t
        INNER JOIN dbo.ResourceCategories rc ON rc.CategoryId = t.CategoryId
        LEFT JOIN dbo.Units u ON u.UnitId = t.DefaultUnitId
        WHERE @Id IS NULL OR t.ResourceTypeId = @Id
        ORDER BY rc.Name, t.Name;
    ELSE
        THROW 50400, N'Unknown master data type. Use areas, components, units, resource-categories or resource-types.', 1;
END
GO

/*
  Upserts one master data row from a camelCase JSON payload (@Id NULL/0 = insert). Returns the saved row.
    areas:               { name, city, state, pincode, isActive }
    components:          { code, name, shelfLifeDays, storageNote, isActive }
    units:               { code, name, isActive }
    resource-categories: { name, description, isActive }
    resource-types:      { categoryId, code, name, defaultUnitId, trackingMode, isActive }
*/
CREATE OR ALTER PROCEDURE dbo.usp_MasterData_Save
    @ActorUserId   INT,
    @Type          NVARCHAR(40),
    @Id            INT = NULL,
    @PayloadJson   NVARCHAR(MAX),
    @CorrelationId NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'masterdata.manage') = 0
        THROW 50403, N'You do not have permission to manage master data.', 1;

    SET @Type = LOWER(LTRIM(RTRIM(@Type)));
    IF @Type IS NULL OR @Type NOT IN (N'areas', N'components', N'units', N'resource-categories', N'resource-types')
        THROW 50400, N'Unknown master data type. Use areas, components, units, resource-categories or resource-types.', 1;
    IF ISJSON(@PayloadJson) = 0
        THROW 50400, N'The master data payload must be a JSON object.', 1;
    IF @Id = 0 SET @Id = NULL;

    DECLARE @Name NVARCHAR(200) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@PayloadJson, N'$.name'))), N''),
            @Code NVARCHAR(30) = UPPER(NULLIF(LTRIM(RTRIM(JSON_VALUE(@PayloadJson, N'$.code'))), N'')),
            @City NVARCHAR(100) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@PayloadJson, N'$.city'))), N''),
            @State NVARCHAR(100) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@PayloadJson, N'$.state'))), N''),
            @Pincode NVARCHAR(10) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@PayloadJson, N'$.pincode'))), N''),
            @Description NVARCHAR(400) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@PayloadJson, N'$.description'))), N''),
            @StorageNote NVARCHAR(400) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@PayloadJson, N'$.storageNote'))), N''),
            @ShelfLifeRaw NVARCHAR(30) = JSON_VALUE(@PayloadJson, N'$.shelfLifeDays'),
            @CategoryRaw NVARCHAR(30) = JSON_VALUE(@PayloadJson, N'$.categoryId'),
            @UnitRaw NVARCHAR(30) = JSON_VALUE(@PayloadJson, N'$.defaultUnitId'),
            @TrackingMode NVARCHAR(20) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@PayloadJson, N'$.trackingMode'))), N''),
            @ActiveRaw NVARCHAR(10) = LOWER(JSON_VALUE(@PayloadJson, N'$.isActive'));
    DECLARE @ShelfLifeDays INT = TRY_CONVERT(INT, @ShelfLifeRaw),
            @CategoryId INT = TRY_CONVERT(INT, @CategoryRaw),
            @DefaultUnitId INT = TRY_CONVERT(INT, @UnitRaw),
            @IsActive BIT = CASE WHEN @ActiveRaw IN (N'false', N'0') THEN 0 ELSE 1 END;

    IF @Name IS NULL
        THROW 50400, N'Name is required.', 1;

    DECLARE @Entity NVARCHAR(50), @Old NVARCHAR(MAX), @New NVARCHAR(MAX), @Action NVARCHAR(50) = CASE WHEN @Id IS NULL THEN N'Created' ELSE N'Updated' END;

    /* Validation per type */
    IF @Type = N'areas'
    BEGIN
        SET @Entity = N'Area';
        IF @Id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Areas WHERE AreaId = @Id) THROW 50404, N'Area not found.', 1;
        IF @City IS NULL OR @State IS NULL THROW 50400, N'City and state are required.', 1;
        IF EXISTS (SELECT 1 FROM dbo.Areas WHERE Name = @Name AND (@Id IS NULL OR AreaId <> @Id)) THROW 50409, N'An area with this name already exists.', 1;
        SET @Old = (SELECT Name AS name, City AS city, State AS state, Pincode AS pincode, IsActive AS isActive FROM dbo.Areas WHERE AreaId = @Id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END
    ELSE IF @Type = N'components'
    BEGIN
        SET @Entity = N'BloodComponent';
        IF @Id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.BloodComponents WHERE ComponentId = @Id) THROW 50404, N'Blood component not found.', 1;
        IF @Code IS NULL THROW 50400, N'Code is required.', 1;
        IF @ShelfLifeDays IS NULL OR @ShelfLifeDays < 1 OR @ShelfLifeDays > 3650 THROW 50400, N'Shelf life must be between 1 and 3650 days.', 1;
        IF EXISTS (SELECT 1 FROM dbo.BloodComponents WHERE Code = @Code AND (@Id IS NULL OR ComponentId <> @Id)) THROW 50409, N'A blood component with this code already exists.', 1;
        SET @Old = (SELECT Code AS code, Name AS name, ShelfLifeDays AS shelfLifeDays, StorageNote AS storageNote, IsActive AS isActive FROM dbo.BloodComponents WHERE ComponentId = @Id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END
    ELSE IF @Type = N'units'
    BEGIN
        SET @Entity = N'Unit';
        IF @Id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Units WHERE UnitId = @Id) THROW 50404, N'Unit not found.', 1;
        IF @Code IS NULL THROW 50400, N'Code is required.', 1;
        IF EXISTS (SELECT 1 FROM dbo.Units WHERE Code = @Code AND (@Id IS NULL OR UnitId <> @Id)) THROW 50409, N'A unit with this code already exists.', 1;
        SET @Old = (SELECT Code AS code, Name AS name, IsActive AS isActive FROM dbo.Units WHERE UnitId = @Id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END
    ELSE IF @Type = N'resource-categories'
    BEGIN
        SET @Entity = N'ResourceCategory';
        IF @Id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.ResourceCategories WHERE CategoryId = @Id) THROW 50404, N'Resource category not found.', 1;
        IF EXISTS (SELECT 1 FROM dbo.ResourceCategories WHERE Name = @Name AND (@Id IS NULL OR CategoryId <> @Id)) THROW 50409, N'A resource category with this name already exists.', 1;
        SET @Old = (SELECT Name AS name, Description AS description, IsActive AS isActive FROM dbo.ResourceCategories WHERE CategoryId = @Id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END
    ELSE
    BEGIN
        SET @Entity = N'MedicalResourceType';
        SET @TrackingMode = ISNULL(@TrackingMode, N'Count');
        IF @Id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.MedicalResourceTypes WHERE ResourceTypeId = @Id) THROW 50404, N'Resource type not found.', 1;
        IF @Code IS NULL THROW 50400, N'Code is required.', 1;
        IF @CategoryId IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.ResourceCategories WHERE CategoryId = @CategoryId) THROW 50400, N'Select a valid resource category.', 1;
        IF @DefaultUnitId IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.Units WHERE UnitId = @DefaultUnitId) THROW 50400, N'Select a valid default unit.', 1;
        IF @TrackingMode NOT IN (N'Count', N'Status', N'Capacity') THROW 50400, N'Tracking mode must be Count, Status or Capacity.', 1;
        IF EXISTS (SELECT 1 FROM dbo.MedicalResourceTypes WHERE Code = @Code AND (@Id IS NULL OR ResourceTypeId <> @Id)) THROW 50409, N'A resource type with this code already exists.', 1;
        SET @Old = (SELECT CategoryId AS categoryId, Code AS code, Name AS name, DefaultUnitId AS defaultUnitId, TrackingMode AS trackingMode, IsActive AS isActive
                    FROM dbo.MedicalResourceTypes WHERE ResourceTypeId = @Id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @Type = N'areas'
        BEGIN
            IF @Id IS NULL
            BEGIN
                INSERT INTO dbo.Areas (Name, City, State, Pincode, IsActive) VALUES (@Name, @City, @State, @Pincode, @IsActive);
                SET @Id = CONVERT(INT, SCOPE_IDENTITY());
            END
            ELSE
                UPDATE dbo.Areas SET Name = @Name, City = @City, State = @State, Pincode = @Pincode, IsActive = @IsActive WHERE AreaId = @Id;
            SET @New = (SELECT Name AS name, City AS city, State AS state, Pincode AS pincode, IsActive AS isActive FROM dbo.Areas WHERE AreaId = @Id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        END
        ELSE IF @Type = N'components'
        BEGIN
            IF @Id IS NULL
            BEGIN
                INSERT INTO dbo.BloodComponents (Code, Name, ShelfLifeDays, StorageNote, IsActive) VALUES (@Code, @Name, @ShelfLifeDays, @StorageNote, @IsActive);
                SET @Id = CONVERT(INT, SCOPE_IDENTITY());
            END
            ELSE
                UPDATE dbo.BloodComponents SET Code = @Code, Name = @Name, ShelfLifeDays = @ShelfLifeDays, StorageNote = @StorageNote, IsActive = @IsActive WHERE ComponentId = @Id;
            SET @New = (SELECT Code AS code, Name AS name, ShelfLifeDays AS shelfLifeDays, StorageNote AS storageNote, IsActive AS isActive FROM dbo.BloodComponents WHERE ComponentId = @Id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        END
        ELSE IF @Type = N'units'
        BEGIN
            IF @Id IS NULL
            BEGIN
                INSERT INTO dbo.Units (Code, Name, IsActive) VALUES (@Code, @Name, @IsActive);
                SET @Id = CONVERT(INT, SCOPE_IDENTITY());
            END
            ELSE
                UPDATE dbo.Units SET Code = @Code, Name = @Name, IsActive = @IsActive WHERE UnitId = @Id;
            SET @New = (SELECT Code AS code, Name AS name, IsActive AS isActive FROM dbo.Units WHERE UnitId = @Id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        END
        ELSE IF @Type = N'resource-categories'
        BEGIN
            IF @Id IS NULL
            BEGIN
                INSERT INTO dbo.ResourceCategories (Name, Description, IsActive) VALUES (@Name, @Description, @IsActive);
                SET @Id = CONVERT(INT, SCOPE_IDENTITY());
            END
            ELSE
                UPDATE dbo.ResourceCategories SET Name = @Name, Description = @Description, IsActive = @IsActive WHERE CategoryId = @Id;
            SET @New = (SELECT Name AS name, Description AS description, IsActive AS isActive FROM dbo.ResourceCategories WHERE CategoryId = @Id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        END
        ELSE
        BEGIN
            IF @Id IS NULL
            BEGIN
                INSERT INTO dbo.MedicalResourceTypes (CategoryId, Code, Name, DefaultUnitId, TrackingMode, IsActive)
                VALUES (@CategoryId, @Code, @Name, @DefaultUnitId, @TrackingMode, @IsActive);
                SET @Id = CONVERT(INT, SCOPE_IDENTITY());
            END
            ELSE
                UPDATE dbo.MedicalResourceTypes
                SET CategoryId = @CategoryId, Code = @Code, Name = @Name, DefaultUnitId = @DefaultUnitId, TrackingMode = @TrackingMode, IsActive = @IsActive
                WHERE ResourceTypeId = @Id;
            SET @New = (SELECT CategoryId AS categoryId, Code AS code, Name AS name, DefaultUnitId AS defaultUnitId, TrackingMode AS trackingMode, IsActive AS isActive
                        FROM dbo.MedicalResourceTypes WHERE ResourceTypeId = @Id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        END

        DECLARE @Ref NVARCHAR(50) = LEFT(COALESCE(@Code, @Name), 50);
        DECLARE @Desc NVARCHAR(1000) = @Entity + N' ' + LOWER(@Action) + N': ' + @Name + N'.';
        EXEC dbo.usp_Audit_Write @ActorUserId = @ActorUserId, @EntityType = @Entity, @EntityId = @Id, @ReferenceNo = @Ref,
             @Action = @Action, @Description = @Desc, @OldValues = @Old, @NewValues = @New, @CorrelationId = @CorrelationId;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    EXEC dbo.usp_MasterData_Get @ActorUserId = @ActorUserId, @Type = @Type, @Id = @Id;
END
GO

/*---------------------------------------------------------------------
  System settings (settings.manage)
---------------------------------------------------------------------*/
CREATE OR ALTER PROCEDURE dbo.usp_Settings_Get
    @ActorUserId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'settings.manage') = 0
        THROW 50403, N'You do not have permission to manage settings.', 1;

    SELECT s.SettingKey, s.SettingValue, s.DataType, s.Category, s.Description, s.UpdatedAt, u.DisplayName AS UpdatedByName
    FROM dbo.SystemSettings s
    LEFT JOIN dbo.Users u ON u.UserId = s.UpdatedBy
    ORDER BY s.Category, s.SettingKey;
END
GO

/*
  Updates settings. @SettingsJson = [{ "settingKey": "...", "settingValue": "..." }] (or { "settings": [...] }).
  Values are validated against DataType (int, decimal, bool -> 'true'/'false', string) and key-specific ranges.
  Returns usp_Settings_Get.
*/
CREATE OR ALTER PROCEDURE dbo.usp_Settings_Update
    @ActorUserId   INT,
    @SettingsJson  NVARCHAR(MAX),
    @CorrelationId NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'settings.manage') = 0
        THROW 50403, N'You do not have permission to manage settings.', 1;
    IF ISJSON(@SettingsJson) = 0
        THROW 50400, N'Settings must be a JSON array.', 1;
    IF LEFT(LTRIM(@SettingsJson), 1) = N'{' AND JSON_QUERY(@SettingsJson, N'$.settings') IS NOT NULL
        SET @SettingsJson = JSON_QUERY(@SettingsJson, N'$.settings');

    DECLARE @In TABLE (SettingKey NVARCHAR(100) NULL, SettingValue NVARCHAR(400) NULL);
    INSERT INTO @In (SettingKey, SettingValue)
    SELECT NULLIF(LTRIM(RTRIM(j.settingKey)), N''), LTRIM(RTRIM(j.settingValue))
    FROM OPENJSON(@SettingsJson) WITH (settingKey NVARCHAR(100) N'$.settingKey', settingValue NVARCHAR(400) N'$.settingValue') j;

    IF NOT EXISTS (SELECT 1 FROM @In)
        THROW 50400, N'At least one setting is required.', 1;
    IF EXISTS (SELECT 1 FROM @In WHERE SettingKey IS NULL OR SettingValue IS NULL)
        THROW 50400, N'Each setting requires a key and a value.', 1;
    IF EXISTS (SELECT SettingKey FROM @In GROUP BY SettingKey HAVING COUNT(*) > 1)
        THROW 50400, N'A setting key appears more than once.', 1;

    DECLARE @BadKey NVARCHAR(100), @Msg NVARCHAR(400);
    SELECT TOP (1) @BadKey = i.SettingKey FROM @In i WHERE NOT EXISTS (SELECT 1 FROM dbo.SystemSettings s WHERE s.SettingKey = i.SettingKey);
    IF @BadKey IS NOT NULL
    BEGIN
        SET @Msg = N'Unknown setting: ' + @BadKey + N'.';
        THROW 50404, @Msg, 1;
    END

    DECLARE @Work TABLE (SettingKey NVARCHAR(100) PRIMARY KEY, DataType NVARCHAR(10), OldValue NVARCHAR(400), NewValue NVARCHAR(400));
    INSERT INTO @Work (SettingKey, DataType, OldValue, NewValue)
    SELECT s.SettingKey, s.DataType, s.SettingValue,
           CASE s.DataType
               WHEN N'bool' THEN CASE LOWER(i.SettingValue) WHEN N'true' THEN N'true' WHEN N'1' THEN N'true'
                                                         WHEN N'false' THEN N'false' WHEN N'0' THEN N'false' END
               WHEN N'int' THEN CAST(TRY_CONVERT(INT, i.SettingValue) AS NVARCHAR(400))
               WHEN N'decimal' THEN CASE WHEN TRY_CONVERT(DECIMAL(18,4), i.SettingValue) IS NOT NULL THEN i.SettingValue END
               ELSE i.SettingValue
           END
    FROM @In i INNER JOIN dbo.SystemSettings s ON s.SettingKey = i.SettingKey;

    SELECT TOP (1) @BadKey = SettingKey FROM @Work WHERE NewValue IS NULL;
    IF @BadKey IS NOT NULL
    BEGIN
        SET @Msg = N'Invalid value for ' + @BadKey + N' (expected ' + (SELECT DataType FROM @Work WHERE SettingKey = @BadKey) + N').';
        THROW 50400, @Msg, 1;
    END

    SELECT TOP (1) @BadKey = w.SettingKey
    FROM @Work w
    WHERE (w.DataType IN (N'int', N'decimal') AND TRY_CONVERT(DECIMAL(18,4), w.NewValue) < 0)
       OR (w.SettingKey IN (N'BLOOD_STOCK_TTL_MINUTES', N'RESOURCE_TTL_MINUTES') AND TRY_CONVERT(INT, w.NewValue) NOT BETWEEN 5 AND 10080)
       OR (w.SettingKey IN (N'MAX_IMPORT_ROWS') AND TRY_CONVERT(INT, w.NewValue) NOT BETWEEN 1 AND 5000)
       OR ((w.SettingKey LIKE N'%PERCENT%' OR w.SettingKey LIKE N'QUALITY_WEIGHT_%') AND TRY_CONVERT(DECIMAL(18,4), w.NewValue) > 100 AND w.SettingKey <> N'LARGE_JUMP_PERCENT')
       OR (w.SettingKey = N'LARGE_JUMP_PERCENT' AND TRY_CONVERT(DECIMAL(18,4), w.NewValue) NOT BETWEEN 1 AND 1000)
       OR (w.SettingKey = N'AGING_THRESHOLD_PERCENT' AND TRY_CONVERT(DECIMAL(18,4), w.NewValue) NOT BETWEEN 1 AND 99);
    IF @BadKey IS NOT NULL
    BEGIN
        SET @Msg = N'The value for ' + @BadKey + N' is out of the allowed range.';
        THROW 50400, @Msg, 1;
    END

    DELETE FROM @Work WHERE NewValue = OldValue;

    IF EXISTS (SELECT 1 FROM @Work)
    BEGIN
        DECLARE @Old NVARCHAR(MAX) = (SELECT w.SettingKey AS settingKey, w.OldValue AS settingValue FROM @Work w ORDER BY w.SettingKey FOR JSON PATH);
        DECLARE @New NVARCHAR(MAX) = (SELECT w.SettingKey AS settingKey, w.NewValue AS settingValue FROM @Work w ORDER BY w.SettingKey FOR JSON PATH);
        DECLARE @Keys NVARCHAR(1000) = (SELECT STRING_AGG(w.SettingKey, N', ') WITHIN GROUP (ORDER BY w.SettingKey) FROM @Work w);
        DECLARE @Desc NVARCHAR(1000) = LEFT(N'System settings updated: ' + @Keys + N'.', 1000);

        BEGIN TRY
            BEGIN TRANSACTION;

            UPDATE s
            SET SettingValue = w.NewValue, UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @ActorUserId
            FROM dbo.SystemSettings s
            INNER JOIN @Work w ON w.SettingKey = s.SettingKey;

            EXEC dbo.usp_Audit_Write @ActorUserId = @ActorUserId, @EntityType = N'SystemSetting', @EntityId = N'Settings',
                 @Action = N'Updated', @Description = @Desc, @OldValues = @Old, @NewValues = @New, @CorrelationId = @CorrelationId;

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            THROW;
        END CATCH
    END

    EXEC dbo.usp_Settings_Get @ActorUserId = @ActorUserId;
END
GO

/*---------------------------------------------------------------------
  Audit
---------------------------------------------------------------------*/

/* Paged audit log search (audit.view). Result set 1: rows; 2: TotalCount. */
CREATE OR ALTER PROCEDURE dbo.usp_Audit_Search
    @ActorUserId   INT,
    @Search        NVARCHAR(200) = NULL,
    @EntityType    NVARCHAR(50) = NULL,
    @Action        NVARCHAR(50) = NULL,
    @FacilityId    INT = NULL,
    @UserId        INT = NULL,
    @CorrelationId NVARCHAR(64) = NULL,
    @FromDate      DATETIME2(0) = NULL,
    @ToDate        DATETIME2(0) = NULL,
    @Page          INT = 1,
    @PageSize      INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'audit.view') = 0
        THROW 50403, N'You do not have permission to view audit logs.', 1;

    SET @Page = CASE WHEN ISNULL(@Page, 1) < 1 THEN 1 ELSE @Page END;
    SET @PageSize = CASE WHEN ISNULL(@PageSize, 20) < 1 THEN 20 WHEN @PageSize > 200 THEN 200 ELSE @PageSize END;
    SET @Search = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @EntityType = NULLIF(LTRIM(RTRIM(@EntityType)), N'');
    SET @Action = NULLIF(LTRIM(RTRIM(@Action)), N'');
    SET @CorrelationId = NULLIF(LTRIM(RTRIM(@CorrelationId)), N'');
    DECLARE @FromInclusive DATETIME2(0) = CASE WHEN @FromDate IS NULL THEN NULL ELSE CAST(CAST(@FromDate AS DATE) AS DATETIME2(0)) END;
    DECLARE @ToExclusive DATETIME2(0) = CASE WHEN @ToDate IS NULL THEN NULL ELSE DATEADD(DAY, 1, CAST(CAST(@ToDate AS DATE) AS DATETIME2(0))) END;

    DECLARE @Ids TABLE (AuditId BIGINT PRIMARY KEY);
    INSERT INTO @Ids (AuditId)
    SELECT a.AuditId
    FROM dbo.AuditLogs a
    LEFT JOIN dbo.Users u ON u.UserId = a.UserId
    WHERE (@EntityType IS NULL OR a.EntityType = @EntityType)
      AND (@Action IS NULL OR a.Action = @Action)
      AND (@FacilityId IS NULL OR a.FacilityId = @FacilityId)
      AND (@UserId IS NULL OR a.UserId = @UserId)
      AND (@CorrelationId IS NULL OR a.CorrelationId = @CorrelationId)
      AND (@FromInclusive IS NULL OR a.CreatedAt >= @FromInclusive)
      AND (@ToExclusive IS NULL OR a.CreatedAt < @ToExclusive)
      AND (@Search IS NULL OR a.ReferenceNo LIKE N'%' + @Search + N'%' OR a.Description LIKE N'%' + @Search + N'%'
           OR u.DisplayName LIKE N'%' + @Search + N'%' OR a.Action LIKE N'%' + @Search + N'%'
           OR a.EntityId = @Search OR a.CorrelationId = @Search);

    SELECT a.AuditId, a.EntityType, a.EntityId, a.ReferenceNo, a.FacilityId, f.Name AS FacilityName, a.Action, a.Description,
           a.OldValues, a.NewValues, a.SourceType, a.Reason, a.CorrelationId, a.UserId,
           COALESCE(u.DisplayName, N'System') AS UserName, a.ActorRole, a.CreatedAt
    FROM @Ids i
    INNER JOIN dbo.AuditLogs a ON a.AuditId = i.AuditId
    LEFT JOIN dbo.Users u ON u.UserId = a.UserId
    LEFT JOIN dbo.Facilities f ON f.FacilityId = a.FacilityId
    ORDER BY a.CreatedAt DESC, a.AuditId DESC
    OFFSET (@Page - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT COUNT(*) AS TotalCount FROM @Ids;
END
GO

/*
  Audit timeline of one entity (GET audit-logs/{entityType}/{entityId}).
  Visible to audit.view / data.viewall holders; otherwise:
    BloodRequest  -> requester or requests.manage
    User          -> the user themself
    Facility / facility-owned records (inventory, changes, imports, issues) -> fn_UserCanAccessFacility
  Throws 50403 when not visible.
*/
CREATE OR ALTER PROCEDURE dbo.usp_Audit_GetEntityTimeline
    @ActorUserId INT,
    @EntityType  NVARCHAR(50),
    @EntityId    NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @EntityType = NULLIF(LTRIM(RTRIM(@EntityType)), N'');
    SET @EntityId = NULLIF(LTRIM(RTRIM(@EntityId)), N'');
    IF @EntityType IS NULL OR @EntityId IS NULL
        THROW 50400, N'Entity type and id are required.', 1;

    DECLARE @Allowed BIT = 0, @Key INT = TRY_CONVERT(INT, @EntityId), @FacilityId INT;

    IF dbo.fn_UserHasPermission(@ActorUserId, N'audit.view') = 1 OR dbo.fn_UserHasPermission(@ActorUserId, N'data.viewall') = 1
        SET @Allowed = 1;
    ELSE IF @EntityType IN (N'BloodRequest', N'Request')
        SET @Allowed = CASE WHEN EXISTS (SELECT 1 FROM dbo.BloodRequests WHERE RequestId = @Key AND RequesterUserId = @ActorUserId)
                                 OR (dbo.fn_UserHasPermission(@ActorUserId, N'requests.manage') = 1
                                     AND EXISTS (SELECT 1 FROM dbo.BloodRequests WHERE RequestId = @Key))
                            THEN 1 ELSE 0 END;
    ELSE IF @EntityType = N'User'
        SET @Allowed = CASE WHEN @Key = @ActorUserId THEN 1 ELSE 0 END;
    ELSE
    BEGIN
        SET @FacilityId =
            CASE
                WHEN @EntityType = N'Facility' THEN (SELECT FacilityId FROM dbo.Facilities WHERE FacilityId = @Key)
                WHEN @EntityType IN (N'BloodInventory', N'BloodStock') THEN (SELECT FacilityId FROM dbo.BloodInventory WHERE InventoryId = @Key)
                WHEN @EntityType IN (N'MedicalResourceInventory', N'ResourceInventory', N'MedicalResource') THEN (SELECT FacilityId FROM dbo.MedicalResourceInventory WHERE ResourceInventoryId = @Key)
                WHEN @EntityType = N'InventoryChange' THEN (SELECT FacilityId FROM dbo.InventoryChanges WHERE ChangeId = @Key)
                WHEN @EntityType = N'ImportBatch' THEN (SELECT FacilityId FROM dbo.ImportBatches WHERE BatchId = @Key)
                WHEN @EntityType = N'ValidationIssue' THEN (SELECT FacilityId FROM dbo.ValidationIssues WHERE IssueId = @Key)
            END;

        IF @FacilityId IS NULL
            SELECT TOP (1) @FacilityId = a.FacilityId
            FROM dbo.AuditLogs a
            WHERE a.EntityType = @EntityType AND a.EntityId = @EntityId AND a.FacilityId IS NOT NULL
            ORDER BY a.AuditId;

        IF @FacilityId IS NOT NULL AND dbo.fn_UserCanAccessFacility(@ActorUserId, @FacilityId) = 1
            SET @Allowed = 1;
    END

    IF @Allowed = 0
        THROW 50403, N'You are not allowed to view the history of this record.', 1;

    SELECT a.AuditId, a.EntityType, a.EntityId, a.ReferenceNo, a.FacilityId, f.Name AS FacilityName, a.Action, a.Description,
           a.OldValues, a.NewValues, a.SourceType, a.Reason, a.CorrelationId, a.UserId,
           COALESCE(u.DisplayName, N'System') AS UserName, a.ActorRole, a.CreatedAt
    FROM dbo.AuditLogs a
    LEFT JOIN dbo.Users u ON u.UserId = a.UserId
    LEFT JOIN dbo.Facilities f ON f.FacilityId = a.FacilityId
    WHERE a.EntityType = @EntityType AND a.EntityId = @EntityId
    ORDER BY a.CreatedAt DESC, a.AuditId DESC;
END
GO
