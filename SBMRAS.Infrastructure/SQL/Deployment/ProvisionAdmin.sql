/* Example: sqlcmd -S localhost -d SBMRAS -v AdminEmail="admin@example.org" AdminDisplayName="SBMRAS Administrator" -i ProvisionAdmin.sql
   Pre-provisions an administrator by email. On first Entra sign-in usp_User_ResolveEntra links the account by email. */
USE [SBMRAS];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @AdminEmail NVARCHAR(320) = N'$(AdminEmail)';
DECLARE @AdminDisplayName NVARCHAR(150) = N'$(AdminDisplayName)';
DECLARE @AdminUserId INT;
DECLARE @AdminRoleId INT = (SELECT RoleId FROM dbo.Roles WHERE RoleCode = N'Admin');
DECLARE @PublicRoleId INT = (SELECT RoleId FROM dbo.Roles WHERE RoleCode = N'PublicUser');

IF @AdminRoleId IS NULL OR @PublicRoleId IS NULL
    THROW 51000, N'Admin/PublicUser roles are missing. Apply scripts 01..12 before provisioning the administrator.', 1;
IF @AdminEmail NOT LIKE N'_%@_%._%' OR NULLIF(LTRIM(RTRIM(@AdminDisplayName)), N'') IS NULL
    THROW 51001, N'AdminEmail and AdminDisplayName must be valid and non-empty.', 1;

BEGIN TRANSACTION;

SELECT @AdminUserId = UserId FROM dbo.Users WHERE Email = @AdminEmail;
IF @AdminUserId IS NULL
BEGIN
    INSERT dbo.Users (DisplayName, Email, IsSelfRegistered, IsActive)
    VALUES (@AdminDisplayName, @AdminEmail, 0, 1);
    SET @AdminUserId = CONVERT(INT, SCOPE_IDENTITY());
END
ELSE
    UPDATE dbo.Users
    SET DisplayName = @AdminDisplayName, IsActive = 1, UpdatedAt = SYSUTCDATETIME()
    WHERE UserId = @AdminUserId;

IF NOT EXISTS (SELECT 1 FROM dbo.UserRoles WHERE UserId = @AdminUserId AND RoleId = @AdminRoleId)
    INSERT dbo.UserRoles (UserId, RoleId, Source, AssignedBy) VALUES (@AdminUserId, @AdminRoleId, N'Local', @AdminUserId);
ELSE
    UPDATE dbo.UserRoles SET Source = N'Local' WHERE UserId = @AdminUserId AND RoleId = @AdminRoleId;

IF NOT EXISTS (SELECT 1 FROM dbo.UserRoles WHERE UserId = @AdminUserId AND RoleId = @PublicRoleId)
    INSERT dbo.UserRoles (UserId, RoleId, Source, AssignedBy) VALUES (@AdminUserId, @PublicRoleId, N'Local', @AdminUserId);

INSERT dbo.AuditLogs (EntityType, EntityId, Action, Description, SourceType, UserId, ActorRole)
VALUES (N'User', CONVERT(NVARCHAR(50), @AdminUserId), N'ProvisionAdmin',
        N'Administrator provisioned by deployment script.', N'AdminCorrection', @AdminUserId, N'Admin');

COMMIT TRANSACTION;

PRINT N'Administrator provisioned with UserId ' + CONVERT(NVARCHAR(20), @AdminUserId) + N'.';
GO