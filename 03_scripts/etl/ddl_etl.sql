/* Pipeline control, observability, validation and source configuration tables. */
USE DataWarehouse;
GO
IF OBJECT_ID(N'etl.schema_migrations', N'U') IS NULL CREATE TABLE etl.schema_migrations (
    version int NOT NULL CONSTRAINT PK_etl_schema_migrations PRIMARY KEY,
    description nvarchar(200) NOT NULL, applied_at datetime2(3) NOT NULL CONSTRAINT DF_etl_migration_date DEFAULT SYSUTCDATETIME()
);
IF OBJECT_ID(N'etl.source_config', N'U') IS NULL CREATE TABLE etl.source_config (
    source_key sysname NOT NULL CONSTRAINT PK_etl_source_config PRIMARY KEY,
    relative_path nvarchar(260) NOT NULL, expected_header nvarchar(1000) NOT NULL,
    expected_columns tinyint NOT NULL, is_required bit NOT NULL CONSTRAINT DF_etl_source_required DEFAULT 1
);
IF OBJECT_ID(N'etl.pipeline_runs', N'U') IS NULL CREATE TABLE etl.pipeline_runs (
    run_id uniqueidentifier NOT NULL CONSTRAINT PK_etl_pipeline_runs PRIMARY KEY,
    pipeline_name sysname NOT NULL, run_mode varchar(12) NOT NULL,
    started_at datetime2(3) NOT NULL, ended_at datetime2(3) NULL,
    status varchar(12) NOT NULL, source_rows bigint NULL, inserted_rows bigint NULL,
    updated_rows bigint NULL, rejected_rows bigint NULL,
    error_number int NULL, error_procedure nvarchar(128) NULL, error_line int NULL,
    error_summary nvarchar(1000) NULL,
    CONSTRAINT CK_etl_pipeline_run_mode CHECK(run_mode IN ('FULL','INCREMENTAL')),
    CONSTRAINT CK_etl_pipeline_run_status CHECK(status IN ('RUNNING','SUCCEEDED','FAILED'))
);
IF OBJECT_ID(N'etl.source_file_history', N'U') IS NULL CREATE TABLE etl.source_file_history (
    source_key sysname NOT NULL, file_sha256 char(64) NOT NULL,
    source_batch_id uniqueidentifier NOT NULL, file_name nvarchar(260) NOT NULL,
    file_size_bytes bigint NOT NULL, source_rows bigint NOT NULL,
    first_seen_at datetime2(3) NOT NULL CONSTRAINT DF_etl_source_first_seen DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_etl_source_file_history PRIMARY KEY(source_key,file_sha256)
);
IF OBJECT_ID(N'etl.pipeline_source_files', N'U') IS NULL CREATE TABLE etl.pipeline_source_files (
    run_id uniqueidentifier NOT NULL, source_key sysname NOT NULL,
    file_sha256 char(64) NOT NULL, file_name nvarchar(260) NOT NULL,
    file_size_bytes bigint NOT NULL, source_rows bigint NOT NULL,
    source_batch_id uniqueidentifier NOT NULL, was_replay bit NOT NULL,
    registered_at datetime2(3) NOT NULL CONSTRAINT DF_etl_pipeline_source_registered DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_etl_pipeline_source_files PRIMARY KEY(run_id,source_key),
    CONSTRAINT FK_etl_pipeline_source_run FOREIGN KEY(run_id) REFERENCES etl.pipeline_runs(run_id)
);
IF OBJECT_ID(N'etl.table_load_logs', N'U') IS NULL CREATE TABLE etl.table_load_logs (
    table_load_log_id bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_etl_table_load_logs PRIMARY KEY,
    run_id uniqueidentifier NOT NULL, layer sysname NOT NULL, table_name sysname NOT NULL,
    started_at datetime2(3) NOT NULL, ended_at datetime2(3) NULL, status varchar(12) NOT NULL,
    source_rows bigint NULL, inserted_rows bigint NULL, updated_rows bigint NULL,
    deleted_rows bigint NULL, rejected_rows bigint NULL, duration_ms bigint NULL,
    error_summary nvarchar(1000) NULL,
    CONSTRAINT FK_etl_table_load_run FOREIGN KEY(run_id) REFERENCES etl.pipeline_runs(run_id)
);
IF OBJECT_ID(N'etl.data_quality_results', N'U') IS NULL CREATE TABLE etl.data_quality_results (
    result_id bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_etl_data_quality_results PRIMARY KEY,
    run_id uniqueidentifier NOT NULL, layer sysname NOT NULL, test_name sysname NOT NULL,
    [rule] nvarchar(1000) NOT NULL, severity varchar(10) NOT NULL,
    actual_result bigint NOT NULL, expected_result nvarchar(200) NOT NULL,
    outcome varchar(8) NOT NULL, failure_reason nvarchar(1000) NULL,
    tested_at datetime2(3) NOT NULL CONSTRAINT DF_etl_dq_tested DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_etl_dq_run FOREIGN KEY(run_id) REFERENCES etl.pipeline_runs(run_id),
    CONSTRAINT CK_etl_dq_severity CHECK(severity IN ('CRITICAL','WARNING','INFO')),
    CONSTRAINT CK_etl_dq_outcome CHECK(outcome IN ('PASS','FAIL','WARN'))
);
IF OBJECT_ID(N'etl.rejected_records', N'U') IS NULL CREATE TABLE etl.rejected_records (
    rejected_record_id bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_etl_rejected_records PRIMARY KEY,
    run_id uniqueidentifier NOT NULL, source_key sysname NOT NULL, entity_name sysname NOT NULL,
    source_record_hash binary(32) NOT NULL, reason_code sysname NOT NULL,
    reason_detail nvarchar(500) NOT NULL, rejected_at datetime2(3) NOT NULL CONSTRAINT DF_etl_rejected_at DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_etl_rejected_run FOREIGN KEY(run_id) REFERENCES etl.pipeline_runs(run_id)
);
IF OBJECT_ID(N'etl.reconciliation_results', N'U') IS NULL CREATE TABLE etl.reconciliation_results (
    reconciliation_id bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_etl_reconciliation_results PRIMARY KEY,
    run_id uniqueidentifier NOT NULL, metric_name sysname NOT NULL,
    source_value decimal(28,4) NULL, target_value decimal(28,4) NULL,
    difference decimal(28,4) NULL, explanation nvarchar(500) NOT NULL,
    recorded_at datetime2(3) NOT NULL CONSTRAINT DF_etl_reconciliation_recorded DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_etl_reconciliation_run FOREIGN KEY(run_id) REFERENCES etl.pipeline_runs(run_id)
);
IF OBJECT_ID(N'etl.performance_results', N'U') IS NULL CREATE TABLE etl.performance_results (
    performance_id bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_etl_performance_results PRIMARY KEY,
    run_id uniqueidentifier NULL, workload_name sysname NOT NULL,
    started_at datetime2(3) NOT NULL, ended_at datetime2(3) NOT NULL,
    elapsed_ms bigint NOT NULL, result_rows bigint NOT NULL,
    fact_rows bigint NOT NULL, notes nvarchar(500) NOT NULL,
    CONSTRAINT FK_etl_performance_run FOREIGN KEY(run_id) REFERENCES etl.pipeline_runs(run_id)
);

IF NOT EXISTS (SELECT 1 FROM etl.source_config WHERE source_key=N'crm_cust_info')
    INSERT etl.source_config VALUES (N'crm_cust_info',N'source_crm\cust_info.csv',N'cst_id,cst_key,cst_firstname,cst_lastname,cst_marital_status,cst_gndr,cst_create_date',7,1);
IF NOT EXISTS (SELECT 1 FROM etl.source_config WHERE source_key=N'crm_prd_info')
    INSERT etl.source_config VALUES (N'crm_prd_info',N'source_crm\prd_info.csv',N'prd_id,prd_key,prd_nm,prd_cost,prd_line,prd_start_dt,prd_end_dt',7,1);
IF NOT EXISTS (SELECT 1 FROM etl.source_config WHERE source_key=N'crm_sales_details')
    INSERT etl.source_config VALUES (N'crm_sales_details',N'source_crm\sales_details.csv',N'sls_ord_num,sls_prd_key,sls_cust_id,sls_order_dt,sls_ship_dt,sls_due_dt,sls_sales,sls_quantity,sls_price',9,1);
IF NOT EXISTS (SELECT 1 FROM etl.source_config WHERE source_key=N'erp_loc_a101')
    INSERT etl.source_config VALUES (N'erp_loc_a101',N'source_erp\LOC_A101.csv',N'CID,CNTRY',2,1);
IF NOT EXISTS (SELECT 1 FROM etl.source_config WHERE source_key=N'erp_cust_az12')
    INSERT etl.source_config VALUES (N'erp_cust_az12',N'source_erp\CUST_AZ12.csv',N'CID,BDATE,GEN',3,1);
IF NOT EXISTS (SELECT 1 FROM etl.source_config WHERE source_key=N'erp_px_cat_g1v2')
    INSERT etl.source_config VALUES (N'erp_px_cat_g1v2',N'source_erp\PX_CAT_G1V2.csv',N'ID,CAT,SUBCAT,MAINTENANCE',4,1);
/* Correct the original defaults for case-sensitive SQL Server/Linux file systems. */
UPDATE etl.source_config SET relative_path=N'source_erp\LOC_A101.csv' WHERE source_key=N'erp_loc_a101' AND LOWER(REPLACE(relative_path,N'/',N'\'))=N'source_erp\loc_a101.csv';
UPDATE etl.source_config SET relative_path=N'source_erp\CUST_AZ12.csv' WHERE source_key=N'erp_cust_az12' AND LOWER(REPLACE(relative_path,N'/',N'\'))=N'source_erp\cust_az12.csv';
UPDATE etl.source_config SET relative_path=N'source_erp\PX_CAT_G1V2.csv' WHERE source_key=N'erp_px_cat_g1v2' AND LOWER(REPLACE(relative_path,N'/',N'\'))=N'source_erp\px_cat_g1v2.csv';
GO
