/* Current cleansed snapshots. Surrogate history and publish model live in Gold. */
USE DataWarehouse;
GO
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO
IF OBJECT_ID(N'silver.crm_cust_info', N'U') IS NULL CREATE TABLE silver.crm_cust_info (
    cst_id int NOT NULL CONSTRAINT PK_silver_crm_cust_info PRIMARY KEY,
    cst_key nvarchar(50) NOT NULL, cst_firstname nvarchar(100) NULL, cst_lastname nvarchar(100) NULL,
    cst_marital_status nvarchar(20) NOT NULL, cst_gndr nvarchar(20) NOT NULL, cst_create_date date NULL,
    record_hash binary(32) NOT NULL, source_batch_id uniqueidentifier NOT NULL,
    dwh_create_date datetime2(3) NOT NULL CONSTRAINT DF_silver_customer_created DEFAULT SYSUTCDATETIME(),
    dwh_update_date datetime2(3) NOT NULL CONSTRAINT DF_silver_customer_updated DEFAULT SYSUTCDATETIME()
);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'silver.crm_cust_info') AND name=N'UX_silver_customer_business_key')
    CREATE UNIQUE INDEX UX_silver_customer_business_key ON silver.crm_cust_info(cst_key) INCLUDE(cst_id,cst_gndr,cst_create_date);
IF OBJECT_ID(N'silver.crm_prd_info', N'U') IS NULL CREATE TABLE silver.crm_prd_info (
    prd_id int NOT NULL CONSTRAINT PK_silver_crm_prd_info PRIMARY KEY,
    cat_id nvarchar(50) NOT NULL, prd_key nvarchar(50) NOT NULL, prd_nm nvarchar(100) NOT NULL,
    prd_cost decimal(19,4) NULL, prd_line nvarchar(30) NOT NULL, prd_start_dt date NOT NULL, prd_end_dt date NULL,
    correction_code nvarchar(50) NULL,
    record_hash binary(32) NOT NULL, source_batch_id uniqueidentifier NOT NULL,
    dwh_create_date datetime2(3) NOT NULL CONSTRAINT DF_silver_product_created DEFAULT SYSUTCDATETIME(),
    dwh_update_date datetime2(3) NOT NULL CONSTRAINT DF_silver_product_updated DEFAULT SYSUTCDATETIME()
);
IF OBJECT_ID(N'silver.crm_sales_details', N'U') IS NULL CREATE TABLE silver.crm_sales_details (
    sales_row_hash binary(32) NOT NULL CONSTRAINT PK_silver_crm_sales_details PRIMARY KEY,
    sls_ord_num nvarchar(50) NOT NULL, sls_prd_key nvarchar(50) NOT NULL, sls_cust_id int NOT NULL,
    sls_order_dt date NOT NULL, sls_ship_dt date NULL, sls_due_dt date NULL,
    sls_sales decimal(19,4) NOT NULL, sls_quantity int NOT NULL, sls_price decimal(19,4) NOT NULL,
    correction_code nvarchar(50) NULL, source_batch_id uniqueidentifier NOT NULL,
    dwh_create_date datetime2(3) NOT NULL CONSTRAINT DF_silver_sales_created DEFAULT SYSUTCDATETIME(),
    dwh_update_date datetime2(3) NOT NULL CONSTRAINT DF_silver_sales_updated DEFAULT SYSUTCDATETIME()
);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'silver.crm_sales_details') AND name=N'UX_silver_sales_grain')
    CREATE UNIQUE INDEX UX_silver_sales_grain ON silver.crm_sales_details(sls_ord_num,sls_prd_key,sls_cust_id,sls_order_dt);
IF OBJECT_ID(N'silver.erp_loc_a101', N'U') IS NULL CREATE TABLE silver.erp_loc_a101 (
    cid nvarchar(50) NOT NULL CONSTRAINT PK_silver_erp_loc_a101 PRIMARY KEY,
    cntry nvarchar(100) NOT NULL, record_hash binary(32) NOT NULL, source_batch_id uniqueidentifier NOT NULL,
    dwh_create_date datetime2(3) NOT NULL CONSTRAINT DF_silver_location_created DEFAULT SYSUTCDATETIME(),
    dwh_update_date datetime2(3) NOT NULL CONSTRAINT DF_silver_location_updated DEFAULT SYSUTCDATETIME()
);
IF OBJECT_ID(N'silver.erp_cust_az12', N'U') IS NULL CREATE TABLE silver.erp_cust_az12 (
    cid nvarchar(50) NOT NULL CONSTRAINT PK_silver_erp_cust_az12 PRIMARY KEY,
    bdate date NULL, gen nvarchar(20) NOT NULL, record_hash binary(32) NOT NULL, source_batch_id uniqueidentifier NOT NULL,
    dwh_create_date datetime2(3) NOT NULL CONSTRAINT DF_silver_erp_customer_created DEFAULT SYSUTCDATETIME(),
    dwh_update_date datetime2(3) NOT NULL CONSTRAINT DF_silver_erp_customer_updated DEFAULT SYSUTCDATETIME()
);
IF OBJECT_ID(N'silver.erp_px_cat_g1v2', N'U') IS NULL CREATE TABLE silver.erp_px_cat_g1v2 (
    id nvarchar(50) NOT NULL CONSTRAINT PK_silver_erp_px_cat_g1v2 PRIMARY KEY,
    cat nvarchar(100) NOT NULL, subcat nvarchar(100) NOT NULL, maintenance nvarchar(20) NOT NULL,
    record_hash binary(32) NOT NULL, source_batch_id uniqueidentifier NOT NULL,
    dwh_create_date datetime2(3) NOT NULL CONSTRAINT DF_silver_category_created DEFAULT SYSUTCDATETIME(),
    dwh_update_date datetime2(3) NOT NULL CONSTRAINT DF_silver_category_updated DEFAULT SYSUTCDATETIME()
);
GO
