/*
  Preserve tables created by the tutorial version before the new schemas are built.
  Legacy Silver/Gold objects are kept as *_legacy; Bronze tables are renamed to
  *_legacy_raw. The next DDL step creates the new schema alongside them. No row is deleted.
*/
USE DataWarehouse;
GO
IF OBJECT_ID(N'gold.fact_sales',N'V') IS NOT NULL DROP VIEW gold.fact_sales;
IF OBJECT_ID(N'gold.dim_products',N'V') IS NOT NULL DROP VIEW gold.dim_products;
IF OBJECT_ID(N'gold.dim_customers',N'V') IS NOT NULL DROP VIEW gold.dim_customers;
GO
DECLARE @renames table(schema_name sysname,old_name sysname,new_name sysname,upgrade_marker sysname);
INSERT @renames VALUES
 (N'bronze',N'crm_cust_info',N'crm_cust_info_legacy_raw',N'source_record_hash'),
 (N'bronze',N'crm_prd_info',N'crm_prd_info_legacy_raw',N'source_record_hash'),
 (N'bronze',N'crm_sales_details',N'crm_sales_details_legacy_raw',N'source_record_hash'),
 (N'bronze',N'erp_loc_a101',N'erp_loc_a101_legacy_raw',N'source_record_hash'),
 (N'bronze',N'erp_cust_az12',N'erp_cust_az12_legacy_raw',N'source_record_hash'),
 (N'bronze',N'erp_px_cat_g1v2',N'erp_px_cat_g1v2_legacy_raw',N'source_record_hash'),
 (N'silver',N'crm_cust_info',N'crm_cust_info_legacy',N'record_hash'),
 (N'silver',N'crm_prd_info',N'crm_prd_info_legacy',N'record_hash'),
 (N'silver',N'crm_sales_details',N'crm_sales_details_legacy',N'sales_row_hash'),
 (N'silver',N'erp_loc_a101',N'erp_loc_a101_legacy',N'record_hash'),
 (N'silver',N'erp_cust_az12',N'erp_cust_az12_legacy',N'record_hash'),
 (N'silver',N'erp_px_cat_g1v2',N'erp_px_cat_g1v2_legacy',N'record_hash');
DECLARE @schema sysname,@old sysname,@new sysname,@upgrade_marker sysname,@object_id int,@sql nvarchar(1000);
DECLARE rename_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT schema_name,old_name,new_name,upgrade_marker FROM @renames;
OPEN rename_cursor;
FETCH NEXT FROM rename_cursor INTO @schema,@old,@new,@upgrade_marker;
WHILE @@FETCH_STATUS=0
BEGIN
    SET @object_id=OBJECT_ID(QUOTENAME(@schema)+N'.'+QUOTENAME(@old),N'U');
    /* On a repeated install, leave the current upgraded tables in place even when a
       prior legacy table did not exist and therefore has no *_legacy target. */
    IF @object_id IS NOT NULL
       AND NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=@object_id AND name=@upgrade_marker)
       AND OBJECT_ID(QUOTENAME(@schema)+N'.'+QUOTENAME(@new),N'U') IS NULL
    BEGIN
        SET @sql=N'EXEC sys.sp_rename N'''+@schema+N'.'+@old+N''',N'''+@new+N''',N''OBJECT'';';
        EXEC sys.sp_executesql @sql;
    END
    FETCH NEXT FROM rename_cursor INTO @schema,@old,@new,@upgrade_marker;
END
CLOSE rename_cursor;
DEALLOCATE rename_cursor;
GO
