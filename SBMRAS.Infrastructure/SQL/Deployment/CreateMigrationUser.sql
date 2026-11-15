/*
  Creates or updates the contained SQL user sbmras_migrator used by deploy-database.yml and makes it db_owner of this
  database only (no server-level rights). Variables: MigrationPassword. Idempotent; re-running rotates the password.
*/
SET NOCOUNT ON;

DECLARE @Password NVARCHAR(128) = N'$(MigrationPassword)';
IF LEN(@Password) < 16
    THROW 50400, N'MigrationPassword must be at least 16 characters.', 1;

DECLARE @QuotedPassword NVARCHAR(300) = QUOTENAME(@Password, N'''');
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'sbmras_migrator')
    EXEC (N'CREATE USER [sbmras_migrator] WITH PASSWORD = ' + @QuotedPassword + N';');
ELSE
    EXEC (N'ALTER USER [sbmras_migrator] WITH PASSWORD = ' + @QuotedPassword + N';');

IF IS_ROLEMEMBER(N'db_owner', N'sbmras_migrator') = 0
    ALTER ROLE db_owner ADD MEMBER [sbmras_migrator];

PRINT N'sbmras_migrator is ready.';
