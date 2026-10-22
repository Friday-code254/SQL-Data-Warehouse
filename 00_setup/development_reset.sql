/* DEVELOPMENT ONLY. This permanently deletes the local DataWarehouse database. */
USE master;
GO
IF DB_ID(N'DataWarehouse') IS NOT NULL
BEGIN
    ALTER DATABASE DataWarehouse SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE DataWarehouse;
END;
GO
/* Rebuild after reset with: sqlcmd -S <server> -E -i 03_scripts/init_database.sql */
