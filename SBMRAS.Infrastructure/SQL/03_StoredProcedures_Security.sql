/*=====================================================================
  SBMRAS - 03_StoredProcedures_Security.sql
  Authentication support: development user switcher, current user
  context (profile, roles, permissions, facilities), dynamic menu and
  Microsoft Entra External ID resolution / self-registration.
  Role priority (PrimaryRole): Admin > HospitalManagement > BloodBank > PublicUser.
=====================================================================*/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* Users offered by the development (X-User-Id) sign-in screen; one row per active user with the primary role. */
CREATE OR ALTER PROCEDURE dbo.usp_Auth_GetDevUsers
    @ActorUserId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT u.UserId, u.DisplayName, u.Email, pr.RoleCode, pr.RoleName, u.OrganizationName, a.Name AS AreaName,
           (SELECT STRING_AGG(f.Name, N', ') WITHIN GROUP (ORDER BY f.Name)
            FROM dbo.FacilityUserAssignments fa
            INNER JOIN dbo.Facilities f ON f.FacilityId = fa.FacilityId
            WHERE fa.UserId = u.UserId AND fa.IsActive = 1) AS FacilityNames
    FROM dbo.Users u
    OUTER APPLY (
        SELECT TOP (1) r.RoleCode, r.RoleName
        FROM dbo.UserRoles ur
        INNER JOIN dbo.Roles r ON r.RoleId = ur.RoleId AND r.IsActive = 1
        WHERE ur.UserId = u.UserId
        ORDER BY CASE r.RoleCode WHEN N'Admin' THEN 1 WHEN N'HospitalManagement' THEN 2 WHEN N'BloodBank' THEN 3 WHEN N'PublicUser' THEN 4 ELSE 5 END, r.RoleId) pr
    LEFT JOIN dbo.Areas a ON a.AreaId = u.AreaId
    WHERE u.IsActive = 1
    ORDER BY u.UserId;
END
GO

/*
  Loads the security context of a user.
  Result set 1: profile (0 rows when the user does not exist; IsActive = 0 -> API returns 401)
  Result set 2: roles (RoleCode, RoleName) ordered by role priority
  Result set 3: effective permission codes (PermissionCode)
  Result set 4: active facility assignments (FacilityId, FacilityCode, Name, FacilityType, AssignmentRole)
*/
CREATE OR ALTER PROCEDURE dbo.usp_User_GetContext
    @ActorUserId INT = NULL,
    @UserId      INT,
    @TouchLogin  BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @TouchLogin = 1
        UPDATE dbo.Users
        SET LastLoginAt = SYSUTCDATETIME()
        WHERE UserId = @UserId AND IsActive = 1
          AND (LastLoginAt IS NULL OR LastLoginAt < DATEADD(MINUTE, -15, SYSUTCDATETIME()));

    SELECT u.UserId, u.DisplayName, u.GivenName, u.FamilyName, u.Email, u.Phone, u.OrganizationName, u.AreaId, a.Name AS AreaName,
           u.IsActive, u.IsSelfRegistered, u.LastLoginAt,
           (SELECT TOP (1) r.RoleCode
            FROM dbo.UserRoles ur INNER JOIN dbo.Roles r ON r.RoleId = ur.RoleId AND r.IsActive = 1
            WHERE ur.UserId = u.UserId
            ORDER BY CASE r.RoleCode WHEN N'Admin' THEN 1 WHEN N'HospitalManagement' THEN 2 WHEN N'BloodBank' THEN 3 WHEN N'PublicUser' THEN 4 ELSE 5 END, r.RoleId) AS PrimaryRole
    FROM dbo.Users u
    LEFT JOIN dbo.Areas a ON a.AreaId = u.AreaId
    WHERE u.UserId = @UserId;

    SELECT r.RoleCode, r.RoleName
    FROM dbo.UserRoles ur
    INNER JOIN dbo.Roles r ON r.RoleId = ur.RoleId AND r.IsActive = 1
    WHERE ur.UserId = @UserId
    ORDER BY CASE r.RoleCode WHEN N'Admin' THEN 1 WHEN N'HospitalManagement' THEN 2 WHEN N'BloodBank' THEN 3 WHEN N'PublicUser' THEN 4 ELSE 5 END, r.RoleId;

    SELECT DISTINCT p.PermissionCode
    FROM dbo.UserRoles ur
    INNER JOIN dbo.Roles r            ON r.RoleId = ur.RoleId AND r.IsActive = 1
    INNER JOIN dbo.RolePermissions rp ON rp.RoleId = r.RoleId
    INNER JOIN dbo.Permissions p      ON p.PermissionId = rp.PermissionId
    WHERE ur.UserId = @UserId
    ORDER BY p.PermissionCode;

    SELECT f.FacilityId, f.FacilityCode, f.Name, f.FacilityType, fa.AssignmentRole
    FROM dbo.FacilityUserAssignments fa
    INNER JOIN dbo.Facilities f ON f.FacilityId = fa.FacilityId
    WHERE fa.UserId = @UserId AND fa.IsActive = 1 AND f.IsActive = 1
    ORDER BY f.Name;
END
GO

/*
  Maps a validated Entra (External ID) token to an SBMRAS user (contract 3.2):
    1) match by (EntraTenantId, EntraObjectId)
    2) else link a pre-provisioned, not yet linked user by e-mail / alternate e-mail
    3) else self-register as PublicUser (IsSelfRegistered = 1)
  Always ensures the PublicUser role and syncs UserRoles rows with Source = 'Entra' to exactly
  @EntraRoles (CSV of HospitalManagement, BloodBank, Admin); Local rows are never touched.
  Audits registration / linking / Entra role changes in the same transaction.
  Returns the same 4 result sets as usp_User_GetContext.
*/
CREATE OR ALTER PROCEDURE dbo.usp_User_ResolveEntra
    @ActorUserId    INT = NULL,
    @EntraTenantId  UNIQUEIDENTIFIER,
    @EntraObjectId  UNIQUEIDENTIFIER,
    @Email          NVARCHAR(320) = NULL,
    @AlternateEmail NVARCHAR(320) = NULL,
    @DisplayName    NVARCHAR(150) = NULL,
    @GivenName      NVARCHAR(100) = NULL,
    @FamilyName     NVARCHAR(100) = NULL,
    @EntraRoles     NVARCHAR(400) = NULL,
    @CorrelationId  NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @EntraTenantId IS NULL OR @EntraObjectId IS NULL
        THROW 50400, N'The access token does not identify a Microsoft Entra account.', 1;

    SET @Email = LOWER(NULLIF(LTRIM(RTRIM(@Email)), N''));
    SET @AlternateEmail = LOWER(NULLIF(LTRIM(RTRIM(@AlternateEmail)), N''));
    SET @DisplayName = NULLIF(LTRIM(RTRIM(@DisplayName)), N'');
    SET @GivenName = NULLIF(LTRIM(RTRIM(@GivenName)), N'');
    SET @FamilyName = NULLIF(LTRIM(RTRIM(@FamilyName)), N'');

    DECLARE @Desired TABLE (RoleId INT PRIMARY KEY, RoleCode NVARCHAR(50));
    INSERT INTO @Desired (RoleId, RoleCode)
    SELECT DISTINCT r.RoleId, r.RoleCode
    FROM STRING_SPLIT(ISNULL(@EntraRoles, N''), N',') s
    INNER JOIN dbo.Roles r ON r.RoleCode = LTRIM(RTRIM(s.value)) AND r.IsActive = 1
    WHERE r.RoleCode IN (N'HospitalManagement', N'BloodBank', N'Admin');

    DECLARE @PublicRoleId INT = (SELECT RoleId FROM dbo.Roles WHERE RoleCode = N'PublicUser');
    IF @PublicRoleId IS NULL
        THROW 50001, N'The PublicUser role is missing. Apply the seed data first.', 1;

    DECLARE @UserId INT, @IsActive BIT;
    SELECT TOP (1) @UserId = u.UserId, @IsActive = u.IsActive
    FROM dbo.Users u
    WHERE u.EntraTenantId = @EntraTenantId AND u.EntraObjectId = @EntraObjectId;

    /* Fast path: linked user whose roles are already in sync -> no write needed. */
    IF @UserId IS NOT NULL
       AND (@IsActive = 0
            OR (EXISTS (SELECT 1 FROM dbo.UserRoles WHERE UserId = @UserId AND RoleId = @PublicRoleId)
                AND NOT EXISTS (SELECT 1 FROM dbo.UserRoles ur WHERE ur.UserId = @UserId AND ur.Source = N'Entra'
                                AND NOT EXISTS (SELECT 1 FROM @Desired d WHERE d.RoleId = ur.RoleId))
                AND NOT EXISTS (SELECT 1 FROM @Desired d WHERE NOT EXISTS (SELECT 1 FROM dbo.UserRoles ur WHERE ur.UserId = @UserId AND ur.RoleId = d.RoleId))))
    BEGIN
        EXEC dbo.usp_User_GetContext @ActorUserId = @UserId, @UserId = @UserId, @TouchLogin = 1;
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Serialises concurrent first requests of the same account (the SPA loads profile and menu in parallel).
        DECLARE @LockResource NVARCHAR(255) = N'SBMRAS:EntraUser:' + CONVERT(NVARCHAR(36), @EntraObjectId);
        EXEC sp_getapplock @Resource = @LockResource, @LockMode = N'Exclusive', @LockOwner = N'Transaction', @LockTimeout = 15000;

        SET @UserId = NULL;
        SELECT TOP (1) @UserId = u.UserId, @IsActive = u.IsActive
        FROM dbo.Users u
        WHERE u.EntraTenantId = @EntraTenantId AND u.EntraObjectId = @EntraObjectId;

        DECLARE @Ref NVARCHAR(320), @New NVARCHAR(MAX);

        IF @UserId IS NULL AND (@Email IS NOT NULL OR @AlternateEmail IS NOT NULL)
        BEGIN
            SELECT TOP (1) @UserId = u.UserId, @IsActive = u.IsActive
            FROM dbo.Users u
            WHERE u.EntraObjectId IS NULL
              AND (u.Email = @Email OR u.Email = @AlternateEmail)
            ORDER BY u.IsActive DESC, u.UserId;

            IF @UserId IS NOT NULL
            BEGIN
                UPDATE dbo.Users
                SET EntraTenantId = @EntraTenantId, EntraObjectId = @EntraObjectId,
                    GivenName = COALESCE(GivenName, @GivenName), FamilyName = COALESCE(FamilyName, @FamilyName),
                    UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UserId
                WHERE UserId = @UserId;

                SET @Ref = (SELECT Email FROM dbo.Users WHERE UserId = @UserId);
                SET @New = (SELECT CONVERT(NVARCHAR(36), @EntraTenantId) AS entraTenantId, CONVERT(NVARCHAR(36), @EntraObjectId) AS entraObjectId
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
                EXEC dbo.usp_Audit_Write @ActorUserId = @UserId, @EntityType = N'User', @EntityId = @UserId, @ReferenceNo = @Ref,
                     @Action = N'EntraLinked', @Description = N'Microsoft Entra identity linked to the pre-provisioned account on first sign-in.',
                     @NewValues = @New, @SourceType = N'Entra', @CorrelationId = @CorrelationId;
            END
        END

        IF @UserId IS NULL
        BEGIN
            DECLARE @NewEmail NVARCHAR(320) = COALESCE(@Email, @AlternateEmail);
            IF @NewEmail IS NULL OR @NewEmail NOT LIKE N'_%@_%._%'
                THROW 50400, N'Your Microsoft account did not provide an e-mail address. Ask the administrator to add the email claim to the SBMRAS API access token.', 1;
            IF EXISTS (SELECT 1 FROM dbo.Users WHERE Email = @NewEmail)
                THROW 50409, N'This e-mail address is already linked to another SBMRAS sign-in. Contact the administrator.', 1;

            DECLARE @Name NVARCHAR(150) = LEFT(COALESCE(@DisplayName,
                                                        NULLIF(LTRIM(RTRIM(CONCAT(@GivenName, N' ', @FamilyName))), N''),
                                                        LEFT(@NewEmail, CHARINDEX(N'@', @NewEmail) - 1)), 150);

            INSERT INTO dbo.Users (DisplayName, GivenName, FamilyName, Email, EntraTenantId, EntraObjectId, IsSelfRegistered, IsActive, CreatedAt)
            VALUES (@Name, @GivenName, @FamilyName, @NewEmail, @EntraTenantId, @EntraObjectId, 1, 1, SYSUTCDATETIME());
            SET @UserId = CONVERT(INT, SCOPE_IDENTITY());
            SET @IsActive = 1;

            UPDATE dbo.Users SET CreatedBy = @UserId WHERE UserId = @UserId;

            INSERT INTO dbo.UserRoles (UserId, RoleId, Source, AssignedAt, AssignedBy)
            VALUES (@UserId, @PublicRoleId, N'Local', SYSUTCDATETIME(), @UserId);

            SET @New = (SELECT @Name AS displayName, @NewEmail AS email, N'PublicUser' AS roleCodes FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            EXEC dbo.usp_Audit_Write @ActorUserId = @UserId, @EntityType = N'User', @EntityId = @UserId, @ReferenceNo = @NewEmail,
                 @Action = N'SelfRegistered', @Description = N'Public user registered through Microsoft Entra External ID.',
                 @NewValues = @New, @SourceType = N'Entra', @CorrelationId = @CorrelationId, @ActorRole = N'PublicUser';

            EXEC dbo.usp_Notification_Create @ActorUserId = @UserId, @UserId = @UserId, @Title = N'Welcome to SBMRAS',
                 @Message = N'You can search blood and medical resource availability and raise blood requests. Always reconfirm availability with the facility.',
                 @Type = N'Info', @EntityType = N'User', @EntityId = @UserId, @Route = N'/dashboard';
        END

        IF @IsActive = 1
        BEGIN
            DECLARE @OldRoles NVARCHAR(400) = (SELECT STRING_AGG(r.RoleCode, N',') WITHIN GROUP (ORDER BY r.RoleCode)
                                               FROM dbo.UserRoles ur INNER JOIN dbo.Roles r ON r.RoleId = ur.RoleId
                                               WHERE ur.UserId = @UserId AND ur.Source = N'Entra');

            IF NOT EXISTS (SELECT 1 FROM dbo.UserRoles WHERE UserId = @UserId AND RoleId = @PublicRoleId)
                INSERT INTO dbo.UserRoles (UserId, RoleId, Source, AssignedAt, AssignedBy)
                VALUES (@UserId, @PublicRoleId, N'Local', SYSUTCDATETIME(), @UserId);

            DELETE ur
            FROM dbo.UserRoles ur
            WHERE ur.UserId = @UserId AND ur.Source = N'Entra'
              AND NOT EXISTS (SELECT 1 FROM @Desired d WHERE d.RoleId = ur.RoleId);
            DECLARE @Removed INT = @@ROWCOUNT;

            INSERT INTO dbo.UserRoles (UserId, RoleId, Source, AssignedAt, AssignedBy)
            SELECT @UserId, d.RoleId, N'Entra', SYSUTCDATETIME(), NULL
            FROM @Desired d
            WHERE NOT EXISTS (SELECT 1 FROM dbo.UserRoles ur WHERE ur.UserId = @UserId AND ur.RoleId = d.RoleId);
            DECLARE @Added INT = @@ROWCOUNT;

            IF @Removed > 0 OR @Added > 0
            BEGIN
                DECLARE @NewRoles NVARCHAR(400) = (SELECT STRING_AGG(r.RoleCode, N',') WITHIN GROUP (ORDER BY r.RoleCode)
                                                   FROM dbo.UserRoles ur INNER JOIN dbo.Roles r ON r.RoleId = ur.RoleId
                                                   WHERE ur.UserId = @UserId AND ur.Source = N'Entra');
                DECLARE @OldJson NVARCHAR(MAX) = (SELECT @OldRoles AS entraRoles FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);
                DECLARE @NewJson NVARCHAR(MAX) = (SELECT @NewRoles AS entraRoles FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);
                SET @Ref = (SELECT Email FROM dbo.Users WHERE UserId = @UserId);
                EXEC dbo.usp_Audit_Write @ActorUserId = @UserId, @EntityType = N'User', @EntityId = @UserId, @ReferenceNo = @Ref,
                     @Action = N'EntraRolesSynced', @Description = N'Roles granted by Microsoft Entra app roles / security groups synchronised.',
                     @OldValues = @OldJson, @NewValues = @NewJson, @SourceType = N'Entra', @CorrelationId = @CorrelationId;
            END
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    EXEC dbo.usp_User_GetContext @ActorUserId = @UserId, @UserId = @UserId, @TouchLogin = 1;
END
GO

/*
  Dynamic menu: active items without a permission requirement or whose permission the caller holds.
  Flat rows (Section, SectionOrder, Code, Label, Icon, Route, SortOrder); the API groups them by section.
*/
CREATE OR ALTER PROCEDURE dbo.usp_Me_GetMenu
    @ActorUserId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT m.Section, m.SectionOrder, m.Code, m.Label, m.Icon, m.Route, m.SortOrder
    FROM dbo.MenuItems m
    WHERE m.IsActive = 1
      AND EXISTS (SELECT 1 FROM dbo.Users u WHERE u.UserId = @ActorUserId AND u.IsActive = 1)
      AND (NOT EXISTS (SELECT 1 FROM dbo.MenuPermissions mp WHERE mp.MenuItemId = m.MenuItemId)
           OR EXISTS (SELECT 1
                      FROM dbo.MenuPermissions mp
                      INNER JOIN dbo.RolePermissions rp ON rp.PermissionId = mp.PermissionId
                      INNER JOIN dbo.Roles r            ON r.RoleId = rp.RoleId AND r.IsActive = 1
                      INNER JOIN dbo.UserRoles ur       ON ur.RoleId = r.RoleId AND ur.UserId = @ActorUserId
                      WHERE mp.MenuItemId = m.MenuItemId))
    ORDER BY m.SectionOrder, m.SortOrder, m.Label;
END
GO
