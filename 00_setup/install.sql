:ON ERROR EXIT
/* Run from the repository root with sqlcmd -S <server> -E -i 00_setup/install.sql */
:r 03_scripts/init_database.sql
:r 03_scripts/etl/ddl_etl.sql
:r 03_scripts/migrations/001_preserve_legacy_schema.sql

:r 03_scripts/bronze/ddl_bronze.sql
:r 03_scripts/silver/ddl_silver.sql
:r 03_scripts/gold/ddl_gold.sql
:r 03_scripts/migrations/002_performance_indexes.sql

:r 03_scripts/bronze/proc_load_bronze.sql
:r 03_scripts/silver/proc_load_silver.sql
:r 03_scripts/gold/proc_load_gold.sql
:r 03_scripts/etl/proc_build_reconciliation.sql
:r 03_scripts/etl/proc_run_quality_checks.sql
:r 03_scripts/etl/proc_record_preflight_failure.sql
:r 03_scripts/etl/proc_load_warehouse.sql
GO
USE DataWarehouse;
GO
IF NOT EXISTS (SELECT 1 FROM etl.schema_migrations WHERE version=1)
    INSERT etl.schema_migrations(version,description) VALUES(1,N'Preserved prior tutorial tables and created Bronze, Silver, Gold, and ETL control plane.');
IF NOT EXISTS (SELECT 1 FROM etl.schema_migrations WHERE version=2)
    INSERT etl.schema_migrations(version,description) VALUES(2,N'Materialized stable Gold dimensions, date dimension, fact table, keys, foreign keys, and indexes.');
IF NOT EXISTS (SELECT 1 FROM etl.schema_migrations WHERE version=3)
    INSERT etl.schema_migrations(version,description) VALUES(3,N'Added audited Bronze/Silver/Gold loaders, orchestration, reconciliation, and quality gates.');
IF NOT EXISTS (SELECT 1 FROM etl.schema_migrations WHERE version=4)
    INSERT etl.schema_migrations(version,description) VALUES(4,N'Added workload-aligned Silver and Gold indexes plus benchmark result storage.');
GO
