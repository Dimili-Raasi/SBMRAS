/* Run with sqlcmd against master before applying 01..12 in order.
   Example: sqlcmd -S localhost -E -C -d master -i CreateDatabase.sql
   (integration tests use a separate SBMRAS_Test database created the same way). */
USE [master];
GO
IF DB_ID(N'SBMRAS') IS NULL
BEGIN
    PRINT N'Creating database SBMRAS.';
    CREATE DATABASE [SBMRAS];
END
ELSE
    PRINT N'Database SBMRAS already exists.';
GO