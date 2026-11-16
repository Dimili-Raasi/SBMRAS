/* Example: sqlcmd -S localhost -d SBMRAS -v UserEmail="ops@example.org" DisplayName="Hospital Ops" RoleCode="HospitalManagement" -i ProvisionFacilityUser.sql
   Pre-provisions a HospitalManagement or BloodBank user by email and makes them Manager of every active, verified facility
   of the matching type. On first Entra sign-in usp_User_ResolveEntra links the account by email. Idempotent. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Email NVARCHAR(320) = LOWER(LTRIM(RTRIM(N'$(UserEmail)')));
DECLARE @DisplayName NVARCHAR(150) = NULLIF(LTRIM(RTRIM(N'$(DisplayName)')), N'');
DECLARE @RoleCode NVARCHAR(50) = LTRIM(RTRIM(N'$(RoleCode)'));
DECLARE @FacilityType NVARCHAR(20) = CASE @RoleCode WHEN N'HospitalManagement' THEN N'Hospital' WHEN N'BloodBank' THEN N'BloodBank' END;

IF @FacilityType IS NULL
    THROW 51010, N'RoleCode must be HospitalManagement or BloodBank.', 1;
IF @Email NOT LIKE N'_%@_%._%'
    THROW 51011, N'UserEmail is not a valid email address.', 1;

DECLARE @RoleId INT = (SELECT RoleId FROM dbo.Roles WHERE RoleCode = @RoleCode);
DECLARE @PublicRoleId INT = (SELECT RoleId FROM dbo.Roles WHERE RoleCode = N'PublicUser');
IF @RoleId IS NULL OR @PublicRoleId IS NULL
    THROW 51012, N'Roles are missing. Apply scripts 01..12 first.', 1;

BEGIN TRANSACTION;

DECLARE @UserId INT = (SELECT TOP (1) UserId FROM dbo.Users WHERE Email = @Email ORDER BY IsActive DESC, UserId);
IF @UserId IS NULL
BEGIN
    INSERT dbo.Users (DisplayName, Email, IsSelfRegistered, IsActive)
    VALUES (COALESCE(@DisplayName, LEFT(@Email, CHARINDEX(N'@', @Email) - 1)), @Email, 0, 1);
    SET @UserId = CONVERT(INT, SCOPE_IDENTITY());
END
ELSE
    UPDATE dbo.Users SET IsActive = 1, UpdatedAt = SYSUTCDATETIME() WHERE UserId = @UserId;

INSERT dbo.UserRoles (UserId, RoleId, Source, AssignedBy)
SELECT @UserId, r.RoleId, N'Local', @UserId
FROM (VALUES (@RoleId), (@PublicRoleId)) r (RoleId)
WHERE NOT EXISTS (SELECT 1 FROM dbo.UserRoles ur WHERE ur.UserId = @UserId AND ur.RoleId = r.RoleId);
UPDATE dbo.UserRoles SET Source = N'Local' WHERE UserId = @UserId AND RoleId = @RoleId;

UPDATE fa SET IsActive = 1, AssignmentRole = N'Manager'
FROM dbo.FacilityUserAssignments fa
INNER JOIN dbo.Facilities f ON f.FacilityId = fa.FacilityId
WHERE fa.UserId = @UserId AND f.FacilityType = @FacilityType AND f.IsActive = 1 AND f.VerificationStatus = N'Verified';

INSERT dbo.FacilityUserAssignments (FacilityId, UserId, AssignmentRole, IsActive, AssignedBy)
SELECT f.FacilityId, @UserId, N'Manager', 1, @UserId
FROM dbo.Facilities f
WHERE f.FacilityType = @FacilityType AND f.IsActive = 1 AND f.VerificationStatus = N'Verified'
  AND NOT EXISTS (SELECT 1 FROM dbo.FacilityUserAssignments fa WHERE fa.FacilityId = f.FacilityId AND fa.UserId = @UserId);

INSERT dbo.AuditLogs (EntityType, EntityId, Action, Description, SourceType, UserId, ActorRole)
VALUES (N'User', CONVERT(NVARCHAR(50), @UserId), N'ProvisionFacilityUser',
        N'User provisioned by deployment script with role ' + @RoleCode + N'.', N'AdminCorrection', @UserId, @RoleCode);

COMMIT TRANSACTION;

DECLARE @Count INT = (SELECT COUNT(*) FROM dbo.FacilityUserAssignments WHERE UserId = @UserId AND IsActive = 1);
PRINT CONCAT(N'Provisioned ', @Email, N' as ', @RoleCode, N' (UserId ', @UserId, N', ', @Count, N' facilities).');
