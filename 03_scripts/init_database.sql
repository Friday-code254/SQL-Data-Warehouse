/* Safe bootstrap. This script never drops an existing database or schema. */
USE master;
GO

IF DB_ID(N'DataWarehouse') IS NULL
    CREATE DATABASE DataWarehouse;
GO

USE DataWarehouse;
GO

IF SCHEMA_ID(N'bronze') IS NULL EXEC(N'CREATE SCHEMA bronze');
IF SCHEMA_ID(N'silver') IS NULL EXEC(N'CREATE SCHEMA silver');
IF SCHEMA_ID(N'gold')   IS NULL EXEC(N'CREATE SCHEMA gold');
IF SCHEMA_ID(N'etl')    IS NULL EXEC(N'CREATE SCHEMA etl');
GO
