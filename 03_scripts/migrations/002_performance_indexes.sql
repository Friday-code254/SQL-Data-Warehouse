/* Indexes match the current snapshot joins, dimension resolution, and BI workloads. */
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
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'silver.crm_prd_info') AND name=N'IX_silver_product_number_latest')
    CREATE INDEX IX_silver_product_number_latest ON silver.crm_prd_info(prd_key,prd_start_dt DESC) INCLUDE(prd_id,cat_id,prd_nm,prd_cost,prd_line,prd_end_dt);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'silver.crm_sales_details') AND name=N'IX_silver_sales_customer_order_date')
    CREATE INDEX IX_silver_sales_customer_order_date ON silver.crm_sales_details(sls_cust_id,sls_order_dt) INCLUDE(sls_ord_num,sls_prd_key,sls_sales,sls_quantity,sls_price);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'silver.crm_sales_details') AND name=N'IX_silver_sales_product_order_date')
    CREATE INDEX IX_silver_sales_product_order_date ON silver.crm_sales_details(sls_prd_key,sls_order_dt) INCLUDE(sls_ord_num,sls_cust_id,sls_sales,sls_quantity);
GO
