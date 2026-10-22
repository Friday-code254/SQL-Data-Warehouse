/* Raw layer: retain source text and immutable batch/file lineage. Safe to rerun. */
USE DataWarehouse;
GO
IF OBJECT_ID(N'bronze.crm_cust_info', N'U') IS NULL CREATE TABLE bronze.crm_cust_info (
    cst_id nvarchar(4000) NULL, cst_key nvarchar(4000) NULL, cst_firstname nvarchar(4000) NULL,
    cst_lastname nvarchar(4000) NULL, cst_marital_status nvarchar(4000) NULL, cst_gndr nvarchar(4000) NULL,
    cst_create_date nvarchar(4000) NULL, source_batch_id uniqueidentifier NOT NULL,
    source_file_name nvarchar(260) NOT NULL, source_file_hash char(64) NOT NULL,
    loaded_at datetime2(3) NOT NULL, source_record_hash binary(32) NOT NULL
);
IF OBJECT_ID(N'bronze.crm_prd_info', N'U') IS NULL CREATE TABLE bronze.crm_prd_info (
    prd_id nvarchar(4000) NULL, prd_key nvarchar(4000) NULL, prd_nm nvarchar(4000) NULL,
    prd_cost nvarchar(4000) NULL, prd_line nvarchar(4000) NULL, prd_start_dt nvarchar(4000) NULL,
    prd_end_dt nvarchar(4000) NULL, source_batch_id uniqueidentifier NOT NULL,
    source_file_name nvarchar(260) NOT NULL, source_file_hash char(64) NOT NULL,
    loaded_at datetime2(3) NOT NULL, source_record_hash binary(32) NOT NULL
);
IF OBJECT_ID(N'bronze.crm_sales_details', N'U') IS NULL CREATE TABLE bronze.crm_sales_details (
    sls_ord_num nvarchar(4000) NULL, sls_prd_key nvarchar(4000) NULL, sls_cust_id nvarchar(4000) NULL,
    sls_order_dt nvarchar(4000) NULL, sls_ship_dt nvarchar(4000) NULL, sls_due_dt nvarchar(4000) NULL,
    sls_sales nvarchar(4000) NULL, sls_quantity nvarchar(4000) NULL, sls_price nvarchar(4000) NULL,
    source_batch_id uniqueidentifier NOT NULL, source_file_name nvarchar(260) NOT NULL,
    source_file_hash char(64) NOT NULL, loaded_at datetime2(3) NOT NULL, source_record_hash binary(32) NOT NULL
);
IF OBJECT_ID(N'bronze.erp_loc_a101', N'U') IS NULL CREATE TABLE bronze.erp_loc_a101 (
    cid nvarchar(4000) NULL, cntry nvarchar(4000) NULL, source_batch_id uniqueidentifier NOT NULL,
    source_file_name nvarchar(260) NOT NULL, source_file_hash char(64) NOT NULL,
    loaded_at datetime2(3) NOT NULL, source_record_hash binary(32) NOT NULL
);
IF OBJECT_ID(N'bronze.erp_cust_az12', N'U') IS NULL CREATE TABLE bronze.erp_cust_az12 (
    cid nvarchar(4000) NULL, bdate nvarchar(4000) NULL, gen nvarchar(4000) NULL,
    source_batch_id uniqueidentifier NOT NULL, source_file_name nvarchar(260) NOT NULL,
    source_file_hash char(64) NOT NULL, loaded_at datetime2(3) NOT NULL, source_record_hash binary(32) NOT NULL
);
IF OBJECT_ID(N'bronze.erp_px_cat_g1v2', N'U') IS NULL CREATE TABLE bronze.erp_px_cat_g1v2 (
    id nvarchar(4000) NULL, cat nvarchar(4000) NULL, subcat nvarchar(4000) NULL,
    maintenance nvarchar(4000) NULL, source_batch_id uniqueidentifier NOT NULL,
    source_file_name nvarchar(260) NOT NULL, source_file_hash char(64) NOT NULL,
    loaded_at datetime2(3) NOT NULL, source_record_hash binary(32) NOT NULL
);
GO
