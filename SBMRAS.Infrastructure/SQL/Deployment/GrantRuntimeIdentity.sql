/*
  Run in the SBMRAS database while connected as the SQL server's Microsoft Entra admin.
  Example: sqlcmd -S <server> -d SBMRAS -v RuntimeIdentityName="app-mi-name" RuntimeIdentityClientId="<client-id>" -i GrantRuntimeIdentity.sql
  WITH SID ... TYPE = E creates the managed identity user without a Microsoft Graph lookup, so the SQL server
  does not need the Directory Readers role.
*/
SET NOCOUNT ON;

DECLARE @RuntimeIdentityName SYSNAME = N'$(RuntimeIdentityName)';
DECLARE @RuntimeIdentityClientId NVARCHAR(100) = N'$(RuntimeIdentityClientId)';
IF NULLIF(@RuntimeIdentityName, N'') IS NULL OR NULLIF(@RuntimeIdentityClientId, N'') IS NULL
    THROW 51002, N'RuntimeIdentityName and RuntimeIdentityClientId are required sqlcmd variables.', 1;
DECLARE @ClientId UNIQUEIDENTIFIER = TRY_CONVERT(UNIQUEIDENTIFIER, @RuntimeIdentityClientId);
IF @ClientId IS NULL
    THROW 51003, N'RuntimeIdentityClientId must be a GUID.', 1;

IF DATABASE_PRINCIPAL_ID(@RuntimeIdentityName) IS NULL
BEGIN
    DECLARE @CreateUser NVARCHAR(MAX) =
        N'CREATE USER ' + QUOTENAME(@RuntimeIdentityName) + N' WITH SID = '
        + CONVERT(NVARCHAR(40), CONVERT(VARBINARY(16), @ClientId), 1) + N', TYPE = E;';
    EXEC sys.sp_executesql @CreateUser;
END

DECLARE @GrantExecute NVARCHAR(MAX) =
    N'GRANT EXECUTE ON SCHEMA::dbo TO ' + QUOTENAME(@RuntimeIdentityName) + N';';
EXEC sys.sp_executesql @GrantExecute;
PRINT N'Granted stored-procedure execution to ' + @RuntimeIdentityName
    + N' (client id ' + @RuntimeIdentityClientId + N').';
GO
