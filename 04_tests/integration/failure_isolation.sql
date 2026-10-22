/* Run only in a disposable development database after one successful load. */
USE DataWarehouse;
GO
DECLARE @before bigint,@root nvarchar(2048)=CONCAT(N'/definitely_missing_',CONVERT(nvarchar(36),NEWID())),
        @manifest nvarchar(max)=N'[
          {"source_key":"crm_cust_info","relative_path":"source_crm\\cust_info.csv","file_name":"cust_info.csv","sha256":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","file_size":1,"row_count":1,"line_terminator":"CRLF","bulk_relative_path":".sql_bulk_stage/test/file.utf16.csv","bulk_sha256":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","bulk_file_size":1,"column_count":7,"header":"cst_id,cst_key,cst_firstname,cst_lastname,cst_marital_status,cst_gndr,cst_create_date"},
          {"source_key":"crm_prd_info","relative_path":"source_crm\\prd_info.csv","file_name":"prd_info.csv","sha256":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","file_size":1,"row_count":1,"line_terminator":"CRLF","bulk_relative_path":".sql_bulk_stage/test/file.utf16.csv","bulk_sha256":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","bulk_file_size":1,"column_count":7,"header":"prd_id,prd_key,prd_nm,prd_cost,prd_line,prd_start_dt,prd_end_dt"},
          {"source_key":"crm_sales_details","relative_path":"source_crm\\sales_details.csv","file_name":"sales_details.csv","sha256":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","file_size":1,"row_count":1,"line_terminator":"CRLF","bulk_relative_path":".sql_bulk_stage/test/file.utf16.csv","bulk_sha256":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","bulk_file_size":1,"column_count":9,"header":"sls_ord_num,sls_prd_key,sls_cust_id,sls_order_dt,sls_ship_dt,sls_due_dt,sls_sales,sls_quantity,sls_price"},
          {"source_key":"erp_loc_a101","relative_path":"source_erp\\LOC_A101.csv","file_name":"LOC_A101.csv","sha256":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","file_size":1,"row_count":1,"line_terminator":"CRLF","bulk_relative_path":".sql_bulk_stage/test/file.utf16.csv","bulk_sha256":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","bulk_file_size":1,"column_count":2,"header":"CID,CNTRY"},
          {"source_key":"erp_cust_az12","relative_path":"source_erp\\CUST_AZ12.csv","file_name":"CUST_AZ12.csv","sha256":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","file_size":1,"row_count":1,"line_terminator":"CRLF","bulk_relative_path":".sql_bulk_stage/test/file.utf16.csv","bulk_sha256":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","bulk_file_size":1,"column_count":3,"header":"CID,BDATE,GEN"},
          {"source_key":"erp_px_cat_g1v2","relative_path":"source_erp\\PX_CAT_G1V2.csv","file_name":"PX_CAT_G1V2.csv","sha256":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","file_size":1,"row_count":1,"line_terminator":"CRLF","bulk_relative_path":".sql_bulk_stage/test/file.utf16.csv","bulk_sha256":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","bulk_file_size":1,"column_count":4,"header":"ID,CAT,SUBCAT,MAINTENANCE"}
        ]';
SELECT @before=COUNT_BIG(*) FROM gold.fact_sales;
BEGIN TRY
    EXEC etl.load_warehouse @dataset_root=@root,@manifest_json=@manifest,@run_mode='FULL';
    THROW 51220,'Expected the missing SQL Server dataset root to fail.',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()=51220 THROW;
END CATCH;
IF (SELECT COUNT_BIG(*) FROM gold.fact_sales)<>@before THROW 51221,'Failed Bronze staging changed Gold facts.',1;
IF NOT EXISTS(SELECT 1 FROM etl.pipeline_runs WHERE status='FAILED' AND error_summary LIKE N'Bronze source staging failed%')
    THROW 51222,'Failed pipeline audit record was not written.',1;
SELECT TOP(1) run_id,status,error_summary FROM etl.pipeline_runs WHERE status='FAILED' ORDER BY started_at DESC;
GO
