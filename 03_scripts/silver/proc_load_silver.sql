/* Snapshot-aware upsert. Bronze is immutable; Silver exposes only the latest source snapshot. */
USE DataWarehouse;
GO
CREATE OR ALTER PROCEDURE silver.load_silver @run_id uniqueidentifier,@run_mode varchar(12)='FULL'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @started datetime2(3),@ended datetime2(3),@src bigint,@ins bigint,@upd bigint,@del bigint,
            @batch uniqueidentifier;
    DECLARE @actions table(action_name nvarchar(10));
    IF UPPER(@run_mode) NOT IN('FULL','INCREMENTAL') THROW 51110,'run_mode must be FULL or INCREMENTAL.',1;
    BEGIN TRY
        BEGIN TRANSACTION;
        IF (SELECT COUNT_BIG(*) FROM etl.pipeline_source_files WHERE run_id=@run_id)<>
           (SELECT COUNT_BIG(*) FROM etl.source_config WHERE is_required=1)
            THROW 51111,'A complete source snapshot is not registered for this run.',1;

        /* FULL clears only current Silver snapshots; immutable Bronze and Gold key history remain. */
        IF UPPER(@run_mode)='FULL'
        BEGIN
            DELETE FROM silver.crm_sales_details;
            DELETE FROM silver.crm_prd_info;
            DELETE FROM silver.crm_cust_info;
            DELETE FROM silver.erp_loc_a101;
            DELETE FROM silver.erp_cust_az12;
            DELETE FROM silver.erp_px_cat_g1v2;
        END;

        /* CRM customers: deduplicate by source business key, retaining the latest source date. */
        SET @started=SYSUTCDATETIME();
        SELECT @batch=source_batch_id FROM etl.pipeline_source_files WHERE run_id=@run_id AND source_key=N'crm_cust_info';
        SELECT b.source_record_hash, TRY_CONVERT(int,NULLIF(TRIM(b.cst_id),N'')) AS cst_id,
            NULLIF(TRIM(b.cst_key),N'') AS cst_key, NULLIF(TRIM(b.cst_firstname),N'') AS cst_firstname,
            NULLIF(TRIM(b.cst_lastname),N'') AS cst_lastname,
            CASE UPPER(TRIM(b.cst_marital_status)) WHEN N'S' THEN N'Single' WHEN N'M' THEN N'Married' ELSE N'n/a' END AS cst_marital_status,
            CASE UPPER(TRIM(b.cst_gndr)) WHEN N'F' THEN N'Female' WHEN N'M' THEN N'Male' ELSE N'n/a' END AS cst_gndr,
            TRY_CONVERT(date,NULLIF(TRIM(b.cst_create_date),N''),23) AS cst_create_date,
            NULLIF(TRIM(b.cst_create_date),N'') AS cst_create_date_text,
            ROW_NUMBER() OVER(PARTITION BY TRY_CONVERT(int,NULLIF(TRIM(b.cst_id),N'')) ORDER BY TRY_CONVERT(date,b.cst_create_date,23) DESC,b.source_record_hash DESC) AS rn
        INTO #cust_all FROM bronze.crm_cust_info b WHERE b.source_batch_id=@batch;
        INSERT etl.rejected_records(run_id,source_key,entity_name,source_record_hash,reason_code,reason_detail)
        SELECT @run_id,N'crm_cust_info',N'customer',source_record_hash,
            CASE WHEN cst_id IS NULL OR cst_key IS NULL THEN N'INVALID_CUSTOMER_KEY'
                 WHEN cst_firstname IS NULL OR cst_lastname IS NULL THEN N'MISSING_CUSTOMER_NAME'
                 WHEN cst_create_date_text IS NOT NULL AND cst_create_date IS NULL THEN N'INVALID_CUSTOMER_CREATE_DATE'
                 ELSE N'DUPLICATE_CUSTOMER_KEY' END,
            CASE WHEN cst_id IS NULL OR cst_key IS NULL THEN N'Customer identifier or business key is missing or invalid.'
                 WHEN cst_firstname IS NULL OR cst_lastname IS NULL THEN N'Customer name is missing.'
                 WHEN cst_create_date_text IS NOT NULL AND cst_create_date IS NULL THEN N'Customer create date is invalid.'
                 ELSE N'Additional source row for a customer key; latest create date was retained.' END
        FROM #cust_all WHERE cst_id IS NULL OR cst_key IS NULL OR cst_firstname IS NULL OR cst_lastname IS NULL
            OR (cst_create_date_text IS NOT NULL AND cst_create_date IS NULL) OR rn>1;
        SELECT *,ROW_NUMBER() OVER(PARTITION BY cst_key ORDER BY cst_create_date DESC,cst_id,source_record_hash) AS business_key_rank
        INTO #cust_ranked FROM #cust_all WHERE cst_id IS NOT NULL AND cst_key IS NOT NULL AND cst_firstname IS NOT NULL
            AND cst_lastname IS NOT NULL AND NOT(cst_create_date_text IS NOT NULL AND cst_create_date IS NULL) AND rn=1;
        INSERT etl.rejected_records(run_id,source_key,entity_name,source_record_hash,reason_code,reason_detail)
        SELECT @run_id,N'crm_cust_info',N'customer',source_record_hash,N'DUPLICATE_CUSTOMER_BUSINESS_KEY',N'Additional customer row for the same CRM business key was excluded; latest create date and lowest ID were retained.'
        FROM #cust_ranked WHERE business_key_rank>1;
        SELECT * INTO #cust FROM #cust_ranked WHERE business_key_rank=1;
        SELECT @src=COUNT_BIG(*) FROM #cust_all;
        DELETE @actions;
        MERGE silver.crm_cust_info AS t USING #cust AS s ON t.cst_id=s.cst_id
        WHEN MATCHED AND t.record_hash<>s.source_record_hash THEN UPDATE SET cst_key=s.cst_key,cst_firstname=s.cst_firstname,cst_lastname=s.cst_lastname,
            cst_marital_status=s.cst_marital_status,cst_gndr=s.cst_gndr,cst_create_date=s.cst_create_date,record_hash=s.source_record_hash,
            source_batch_id=@batch,dwh_update_date=SYSUTCDATETIME()
        WHEN NOT MATCHED BY TARGET THEN INSERT(cst_id,cst_key,cst_firstname,cst_lastname,cst_marital_status,cst_gndr,cst_create_date,record_hash,source_batch_id)
            VALUES(s.cst_id,s.cst_key,s.cst_firstname,s.cst_lastname,s.cst_marital_status,s.cst_gndr,s.cst_create_date,s.source_record_hash,@batch)
        WHEN NOT MATCHED BY SOURCE THEN DELETE
        OUTPUT $action INTO @actions;
        SELECT @ins=COUNT_BIG(*) FROM @actions WHERE action_name=N'INSERT';
        SELECT @upd=COUNT_BIG(*) FROM @actions WHERE action_name=N'UPDATE';
        SELECT @del=COUNT_BIG(*) FROM @actions WHERE action_name=N'DELETE';
        SET @ended=SYSUTCDATETIME();
        INSERT etl.table_load_logs(run_id,layer,table_name,started_at,ended_at,status,source_rows,inserted_rows,updated_rows,deleted_rows,rejected_rows,duration_ms)
        VALUES(@run_id,N'silver',N'crm_cust_info',@started,@ended,'SUCCEEDED',@src,@ins,@upd,@del,(SELECT COUNT_BIG(*) FROM etl.rejected_records WHERE run_id=@run_id AND source_key=N'crm_cust_info'),DATEDIFF_BIG(millisecond,@started,@ended));

        /* CRM products. Null cost remains NULL; it is never silently changed to zero. */
        SET @started=SYSUTCDATETIME();
        SELECT @batch=source_batch_id FROM etl.pipeline_source_files WHERE run_id=@run_id AND source_key=N'crm_prd_info';
        SELECT b.source_record_hash,TRY_CONVERT(int,NULLIF(TRIM(b.prd_id),N'')) AS prd_id,
            REPLACE(SUBSTRING(TRIM(b.prd_key),1,5),N'-',N'_') AS cat_id,
            SUBSTRING(TRIM(b.prd_key),7,50) AS prd_key,NULLIF(TRIM(b.prd_nm),N'') AS prd_nm,
            TRY_CONVERT(decimal(19,4),NULLIF(TRIM(b.prd_cost),N'')) AS prd_cost,
            NULLIF(TRIM(b.prd_cost),N'') AS prd_cost_text,
            CASE UPPER(TRIM(b.prd_line)) WHEN N'M' THEN N'Mountain' WHEN N'R' THEN N'Road' WHEN N'S' THEN N'Other Sales' WHEN N'T' THEN N'Touring' ELSE N'n/a' END AS prd_line,
            TRY_CONVERT(date,NULLIF(TRIM(b.prd_start_dt),N''),23) AS prd_start_dt,
            TRY_CONVERT(date,NULLIF(TRIM(b.prd_end_dt),N''),23) AS prd_end_dt,
            NULLIF(TRIM(b.prd_end_dt),N'') AS prd_end_dt_text
        INTO #prd_raw FROM bronze.crm_prd_info b WHERE b.source_batch_id=@batch;
        INSERT etl.rejected_records(run_id,source_key,entity_name,source_record_hash,reason_code,reason_detail)
        SELECT @run_id,N'crm_prd_info',N'product',source_record_hash,
            CASE WHEN prd_cost_text IS NOT NULL AND prd_cost IS NULL OR prd_cost<0 THEN N'INVALID_PRODUCT_COST' ELSE N'INVALID_PRODUCT_KEY_OR_DATE' END,
            CASE WHEN prd_cost_text IS NOT NULL AND prd_cost IS NULL OR prd_cost<0 THEN N'Nonblank product cost could not be parsed or was negative.'
                 ELSE N'Product identifier, business key, name, or effective start date is missing or invalid.' END
        FROM #prd_raw WHERE prd_id IS NULL OR cat_id IS NULL OR prd_key=N'' OR prd_nm IS NULL OR prd_start_dt IS NULL
            OR (prd_cost_text IS NOT NULL AND prd_cost IS NULL) OR prd_cost<0;
        SELECT *,DATEADD(day,-1,LEAD(prd_start_dt) OVER(PARTITION BY prd_key ORDER BY prd_start_dt,prd_id)) AS derived_end_dt
        INTO #prd_ranges FROM #prd_raw WHERE prd_id IS NOT NULL AND cat_id IS NOT NULL AND prd_key<>N'' AND prd_nm IS NOT NULL AND prd_start_dt IS NOT NULL
            AND NOT(prd_cost_text IS NOT NULL AND prd_cost IS NULL) AND COALESCE(prd_cost,0)>=0;
        SELECT source_record_hash,prd_id,cat_id,prd_key,prd_nm,prd_cost,prd_line,prd_start_dt,
            CASE WHEN derived_end_dt IS NOT NULL THEN derived_end_dt
                 WHEN prd_end_dt IS NOT NULL AND prd_end_dt>=prd_start_dt THEN prd_end_dt ELSE NULL END AS prd_end_dt,
            CASE WHEN derived_end_dt IS NOT NULL AND (prd_end_dt IS NULL OR prd_end_dt<>derived_end_dt) THEN N'PRODUCT_END_DATE_REBUILT'
                 WHEN derived_end_dt IS NULL AND prd_end_dt_text IS NOT NULL AND (prd_end_dt IS NULL OR prd_end_dt<prd_start_dt) THEN N'PRODUCT_END_DATE_CLEARED'
                 ELSE NULL END AS correction_code
        INTO #prd FROM #prd_ranges;
        SELECT @src=COUNT_BIG(*) FROM #prd_raw;
        DELETE @actions;
        MERGE silver.crm_prd_info AS t USING #prd AS s ON t.prd_id=s.prd_id
        WHEN MATCHED AND (t.record_hash<>s.source_record_hash OR ISNULL(t.prd_end_dt,CONVERT(date,'00010101'))<>ISNULL(s.prd_end_dt,CONVERT(date,'00010101')) OR ISNULL(t.correction_code,N'')<>ISNULL(s.correction_code,N'')) THEN UPDATE SET cat_id=s.cat_id,prd_key=s.prd_key,prd_nm=s.prd_nm,prd_cost=s.prd_cost,
            prd_line=s.prd_line,prd_start_dt=s.prd_start_dt,prd_end_dt=s.prd_end_dt,correction_code=s.correction_code,record_hash=s.source_record_hash,source_batch_id=@batch,dwh_update_date=SYSUTCDATETIME()
        WHEN NOT MATCHED BY TARGET THEN INSERT(prd_id,cat_id,prd_key,prd_nm,prd_cost,prd_line,prd_start_dt,prd_end_dt,correction_code,record_hash,source_batch_id)
            VALUES(s.prd_id,s.cat_id,s.prd_key,s.prd_nm,s.prd_cost,s.prd_line,s.prd_start_dt,s.prd_end_dt,s.correction_code,s.source_record_hash,@batch)
        WHEN NOT MATCHED BY SOURCE THEN DELETE
        OUTPUT $action INTO @actions;
        SELECT @ins=COUNT_BIG(*) FROM @actions WHERE action_name=N'INSERT'; SELECT @upd=COUNT_BIG(*) FROM @actions WHERE action_name=N'UPDATE'; SELECT @del=COUNT_BIG(*) FROM @actions WHERE action_name=N'DELETE';
        SET @ended=SYSUTCDATETIME();
        INSERT etl.table_load_logs(run_id,layer,table_name,started_at,ended_at,status,source_rows,inserted_rows,updated_rows,deleted_rows,rejected_rows,duration_ms)
        VALUES(@run_id,N'silver',N'crm_prd_info',@started,@ended,'SUCCEEDED',@src,@ins,@upd,@del,(SELECT COUNT_BIG(*) FROM etl.rejected_records WHERE run_id=@run_id AND source_key=N'crm_prd_info'),DATEDIFF_BIG(millisecond,@started,@ended));

        /* Sales: safe date/decimal conversion, explicit derivations, and reason-coded quarantine. */
        SET @started=SYSUTCDATETIME();
        SELECT @batch=source_batch_id FROM etl.pipeline_source_files WHERE run_id=@run_id AND source_key=N'crm_sales_details';
        SELECT b.source_record_hash,TRIM(b.sls_ord_num) AS sls_ord_num,TRIM(b.sls_prd_key) AS sls_prd_key,
            TRY_CONVERT(int,NULLIF(TRIM(b.sls_cust_id),N'')) AS sls_cust_id,
            CASE WHEN LEN(TRIM(b.sls_order_dt))=8 THEN TRY_CONVERT(date,TRIM(b.sls_order_dt),112) END AS sls_order_dt,
            CASE WHEN NULLIF(TRIM(b.sls_ship_dt),N'') IS NULL OR TRIM(b.sls_ship_dt)=N'0' THEN NULL WHEN LEN(TRIM(b.sls_ship_dt))=8 THEN TRY_CONVERT(date,TRIM(b.sls_ship_dt),112) END AS sls_ship_dt,
            CASE WHEN NULLIF(TRIM(b.sls_due_dt),N'') IS NULL OR TRIM(b.sls_due_dt)=N'0' THEN NULL WHEN LEN(TRIM(b.sls_due_dt))=8 THEN TRY_CONVERT(date,TRIM(b.sls_due_dt),112) END AS sls_due_dt,
            NULLIF(NULLIF(TRIM(b.sls_ship_dt),N''),N'0') AS ship_text,NULLIF(NULLIF(TRIM(b.sls_due_dt),N''),N'0') AS due_text,
            TRY_CONVERT(decimal(19,4),NULLIF(TRIM(b.sls_sales),N'')) AS raw_sales,
            TRY_CONVERT(int,NULLIF(TRIM(b.sls_quantity),N'')) AS sls_quantity,
            TRY_CONVERT(decimal(19,4),NULLIF(TRIM(b.sls_price),N'')) AS raw_price,
            NULLIF(TRIM(b.sls_sales),N'') AS sales_text,NULLIF(TRIM(b.sls_price),N'') AS price_text
        INTO #sales_parsed FROM bronze.crm_sales_details b WHERE b.source_batch_id=@batch;
        SELECT *,
            CASE WHEN price_text IS NULL AND raw_sales IS NOT NULL AND sls_quantity>0 THEN raw_sales/NULLIF(sls_quantity,0) ELSE raw_price END AS final_price,
            CASE WHEN sales_text IS NULL AND raw_price IS NOT NULL AND sls_quantity>0 THEN TRY_CONVERT(decimal(19,4),sls_quantity*raw_price) ELSE raw_sales END AS final_sales,
            CASE WHEN price_text IS NULL AND sales_text IS NULL THEN NULL
                 WHEN price_text IS NULL THEN N'PRICE_DERIVED_FROM_SALES'
                 WHEN sales_text IS NULL THEN N'SALES_DERIVED_FROM_PRICE' END AS correction_code,
            CASE WHEN sls_ord_num=N'' OR sls_prd_key=N'' OR sls_cust_id IS NULL THEN N'MISSING_BUSINESS_KEY'
                 WHEN sls_order_dt IS NULL OR sls_order_dt<CONVERT(date,'19000101') OR sls_order_dt>DATEADD(day,1,CONVERT(date,SYSUTCDATETIME()))
                   OR (ship_text IS NOT NULL AND sls_ship_dt IS NULL) OR (due_text IS NOT NULL AND sls_due_dt IS NULL)
                   OR sls_ship_dt<CONVERT(date,'19000101') OR sls_due_dt<CONVERT(date,'19000101')
                   OR sls_ship_dt>DATEADD(day,1,CONVERT(date,SYSUTCDATETIME())) OR sls_due_dt>DATEADD(day,1,CONVERT(date,SYSUTCDATETIME()))
                   OR (sales_text IS NOT NULL AND raw_sales IS NULL) OR (price_text IS NOT NULL AND raw_price IS NULL) THEN N'INVALID_DATE_OR_AMOUNT'
                 WHEN sls_quantity IS NULL OR sls_quantity<=0 THEN N'INVALID_QUANTITY'
                 WHEN raw_sales<0 OR raw_price<0 THEN N'NEGATIVE_AMOUNT'
                 WHEN (sales_text IS NULL AND price_text IS NULL) THEN N'BOTH_SALES_AND_PRICE_MISSING'
                 WHEN sls_ship_dt IS NOT NULL AND sls_order_dt>sls_ship_dt THEN N'ORDER_AFTER_SHIP_DATE'
                 WHEN sls_due_dt IS NOT NULL AND sls_order_dt>sls_due_dt THEN N'ORDER_AFTER_DUE_DATE'
                 WHEN sls_ship_dt IS NOT NULL AND sls_due_dt IS NOT NULL AND sls_ship_dt>sls_due_dt THEN N'SHIP_AFTER_DUE_DATE'
                 WHEN (CASE WHEN sales_text IS NULL AND raw_price IS NOT NULL AND sls_quantity>0 THEN TRY_CONVERT(decimal(19,4),sls_quantity*raw_price) ELSE raw_sales END) IS NULL
                   OR (CASE WHEN price_text IS NULL AND raw_sales IS NOT NULL AND sls_quantity>0 THEN raw_sales/NULLIF(sls_quantity,0) ELSE raw_price END) IS NULL THEN N'UNRESOLVED_AMOUNT'
                 WHEN ABS((CASE WHEN sales_text IS NULL THEN TRY_CONVERT(decimal(19,4),sls_quantity*raw_price) ELSE raw_sales END)-
                           (CASE WHEN price_text IS NULL THEN raw_sales/NULLIF(sls_quantity,0) ELSE raw_price END)*sls_quantity)>
                      CASE WHEN price_text IS NULL THEN CONVERT(decimal(19,4),0.0001*sls_quantity) ELSE CONVERT(decimal(19,4),0.0001) END THEN N'SALES_PRICE_MISMATCH'
            END AS reason_code
        INTO #sales_candidates FROM #sales_parsed;
        SELECT *,ROW_NUMBER() OVER(PARTITION BY sls_ord_num,sls_prd_key,sls_cust_id,sls_order_dt ORDER BY source_record_hash) AS grain_rank
        INTO #sales_ranked FROM #sales_candidates;
        INSERT etl.rejected_records(run_id,source_key,entity_name,source_record_hash,reason_code,reason_detail)
        SELECT @run_id,N'crm_sales_details',N'sales_line',source_record_hash,
            COALESCE(reason_code,N'DUPLICATE_SALES_GRAIN'),
            CASE COALESCE(reason_code,N'DUPLICATE_SALES_GRAIN')
              WHEN N'PRICE_DERIVED_FROM_SALES' THEN N'Unreachable correction state.'
              WHEN N'DUPLICATE_SALES_GRAIN' THEN N'Duplicate source line for order, product, customer, and order date; one row was retained.'
              ELSE N'Sales line failed a date, key, quantity, or monetary validation rule.' END
        FROM #sales_ranked WHERE reason_code IS NOT NULL OR grain_rank>1;
        SELECT source_record_hash,sls_ord_num,sls_prd_key,sls_cust_id,sls_order_dt,sls_ship_dt,sls_due_dt,
            final_sales AS sls_sales,sls_quantity,final_price AS sls_price,correction_code
        INTO #sales FROM #sales_ranked WHERE reason_code IS NULL AND grain_rank=1;
        SELECT @src=COUNT_BIG(*) FROM #sales_ranked;
        DELETE @actions;
        MERGE silver.crm_sales_details AS t USING #sales AS s
          ON t.sls_ord_num=s.sls_ord_num AND t.sls_prd_key=s.sls_prd_key AND t.sls_cust_id=s.sls_cust_id AND t.sls_order_dt=s.sls_order_dt
        WHEN MATCHED AND t.sales_row_hash<>s.source_record_hash THEN UPDATE SET sales_row_hash=s.source_record_hash,sls_ship_dt=s.sls_ship_dt,sls_due_dt=s.sls_due_dt,
            sls_sales=s.sls_sales,sls_quantity=s.sls_quantity,sls_price=s.sls_price,correction_code=s.correction_code,source_batch_id=@batch,dwh_update_date=SYSUTCDATETIME()
        WHEN NOT MATCHED BY TARGET THEN INSERT(sales_row_hash,sls_ord_num,sls_prd_key,sls_cust_id,sls_order_dt,sls_ship_dt,sls_due_dt,sls_sales,sls_quantity,sls_price,correction_code,source_batch_id)
            VALUES(s.source_record_hash,s.sls_ord_num,s.sls_prd_key,s.sls_cust_id,s.sls_order_dt,s.sls_ship_dt,s.sls_due_dt,s.sls_sales,s.sls_quantity,s.sls_price,s.correction_code,@batch)
        WHEN NOT MATCHED BY SOURCE THEN DELETE
        OUTPUT $action INTO @actions;
        SELECT @ins=COUNT_BIG(*) FROM @actions WHERE action_name=N'INSERT'; SELECT @upd=COUNT_BIG(*) FROM @actions WHERE action_name=N'UPDATE'; SELECT @del=COUNT_BIG(*) FROM @actions WHERE action_name=N'DELETE';
        SET @ended=SYSUTCDATETIME();
        INSERT etl.table_load_logs(run_id,layer,table_name,started_at,ended_at,status,source_rows,inserted_rows,updated_rows,deleted_rows,rejected_rows,duration_ms)
        VALUES(@run_id,N'silver',N'crm_sales_details',@started,@ended,'SUCCEEDED',@src,@ins,@upd,@del,(SELECT COUNT_BIG(*) FROM etl.rejected_records WHERE run_id=@run_id AND source_key=N'crm_sales_details'),DATEDIFF_BIG(millisecond,@started,@ended));

        /* ERP customer enrichment. A future birth date is nulled and explicitly quarantined. */
        SET @started=SYSUTCDATETIME(); SELECT @batch=source_batch_id FROM etl.pipeline_source_files WHERE run_id=@run_id AND source_key=N'erp_cust_az12';
        SELECT b.source_record_hash,CONVERT(nvarchar(50),CASE WHEN UPPER(TRIM(b.cid)) LIKE N'NAS%' THEN SUBSTRING(TRIM(b.cid),4,50) ELSE TRIM(b.cid) END) AS cid,
            TRY_CONVERT(date,NULLIF(TRIM(b.bdate),N''),23) AS bdate,
            NULLIF(TRIM(b.bdate),N'') AS bdate_text,
            CASE WHEN UPPER(TRIM(b.gen)) IN(N'F',N'FEMALE') THEN N'Female' WHEN UPPER(TRIM(b.gen)) IN(N'M',N'MALE') THEN N'Male' ELSE N'n/a' END AS gen
        INTO #erp_customer_raw FROM bronze.erp_cust_az12 b WHERE b.source_batch_id=@batch;
        INSERT etl.rejected_records(run_id,source_key,entity_name,source_record_hash,reason_code,reason_detail)
        SELECT @run_id,N'erp_cust_az12',N'customer_enrichment',source_record_hash,
            CASE WHEN cid=N'' THEN N'INVALID_CUSTOMER_ID' WHEN bdate_text IS NOT NULL AND bdate IS NULL THEN N'INVALID_BIRTH_DATE' WHEN bdate>CONVERT(date,SYSUTCDATETIME()) THEN N'FUTURE_BIRTH_DATE' ELSE N'OUT_OF_RANGE_BIRTH_DATE' END,
            CASE WHEN cid=N'' THEN N'Customer identifier is missing.' WHEN bdate_text IS NOT NULL AND bdate IS NULL THEN N'Nonblank birth date could not be parsed.' WHEN bdate>CONVERT(date,SYSUTCDATETIME()) THEN N'Future birth date was excluded from the enrichment.' ELSE N'Out-of-range birth date was excluded from the enrichment.' END
        FROM #erp_customer_raw WHERE cid=N'' OR (bdate_text IS NOT NULL AND bdate IS NULL) OR bdate>CONVERT(date,SYSUTCDATETIME()) OR bdate<CONVERT(date,'19000101');
        SELECT *,ROW_NUMBER() OVER(PARTITION BY cid ORDER BY source_record_hash) AS rn INTO #erp_customer FROM #erp_customer_raw WHERE cid<>N'';
        INSERT etl.rejected_records(run_id,source_key,entity_name,source_record_hash,reason_code,reason_detail)
        SELECT @run_id,N'erp_cust_az12',N'customer_enrichment',source_record_hash,N'DUPLICATE_ERP_CUSTOMER_ID',N'Additional ERP enrichment row for the same normalized customer ID was excluded.' FROM #erp_customer WHERE rn>1;
        DELETE FROM #erp_customer WHERE rn>1;
        SELECT @src=COUNT_BIG(*) FROM #erp_customer_raw; DELETE @actions;
        MERGE silver.erp_cust_az12 AS t USING #erp_customer AS s ON t.cid=s.cid
        WHEN MATCHED AND t.record_hash<>s.source_record_hash THEN UPDATE SET bdate=IIF(s.bdate>CONVERT(date,SYSUTCDATETIME()) OR s.bdate<CONVERT(date,'19000101'),NULL,s.bdate),gen=s.gen,record_hash=s.source_record_hash,source_batch_id=@batch,dwh_update_date=SYSUTCDATETIME()
        WHEN NOT MATCHED BY TARGET THEN INSERT(cid,bdate,gen,record_hash,source_batch_id) VALUES(s.cid,IIF(s.bdate>CONVERT(date,SYSUTCDATETIME()) OR s.bdate<CONVERT(date,'19000101'),NULL,s.bdate),s.gen,s.source_record_hash,@batch)
        WHEN NOT MATCHED BY SOURCE THEN DELETE OUTPUT $action INTO @actions;
        SELECT @ins=COUNT_BIG(*) FROM @actions WHERE action_name=N'INSERT'; SELECT @upd=COUNT_BIG(*) FROM @actions WHERE action_name=N'UPDATE'; SELECT @del=COUNT_BIG(*) FROM @actions WHERE action_name=N'DELETE';
        SET @ended=SYSUTCDATETIME();
        INSERT etl.table_load_logs(run_id,layer,table_name,started_at,ended_at,status,source_rows,inserted_rows,updated_rows,deleted_rows,rejected_rows,duration_ms)
        VALUES(@run_id,N'silver',N'erp_cust_az12',@started,@ended,'SUCCEEDED',@src,@ins,@upd,@del,(SELECT COUNT_BIG(*) FROM etl.rejected_records WHERE run_id=@run_id AND source_key=N'erp_cust_az12'),DATEDIFF_BIG(millisecond,@started,@ended));

        /* ERP locations and product categories are set-based upserts keyed by source ID. */
        SET @started=SYSUTCDATETIME(); SELECT @batch=source_batch_id FROM etl.pipeline_source_files WHERE run_id=@run_id AND source_key=N'erp_loc_a101';
        INSERT etl.rejected_records(run_id,source_key,entity_name,source_record_hash,reason_code,reason_detail)
        SELECT @run_id,N'erp_loc_a101',N'customer_location',source_record_hash,N'MISSING_ERP_LOCATION_ID',N'ERP location customer identifier is missing.'
        FROM bronze.erp_loc_a101 WHERE source_batch_id=@batch AND NULLIF(TRIM(cid),N'') IS NULL;
        SELECT b.source_record_hash,REPLACE(TRIM(b.cid),N'-',N'') AS cid,
            CASE WHEN TRIM(b.cntry)=N'DE' THEN N'Germany' WHEN TRIM(b.cntry) IN(N'US',N'USA') THEN N'United States' WHEN NULLIF(TRIM(b.cntry),N'') IS NULL THEN N'n/a' ELSE TRIM(b.cntry) END AS cntry
        INTO #locations_base FROM bronze.erp_loc_a101 b WHERE b.source_batch_id=@batch AND NULLIF(TRIM(b.cid),N'') IS NOT NULL;
        SELECT *,ROW_NUMBER() OVER(PARTITION BY cid ORDER BY source_record_hash) AS rn INTO #locations_ranked FROM #locations_base;
        INSERT etl.rejected_records(run_id,source_key,entity_name,source_record_hash,reason_code,reason_detail)
        SELECT @run_id,N'erp_loc_a101',N'customer_location',source_record_hash,N'DUPLICATE_ERP_LOCATION_ID',N'Additional ERP location row for the same normalized customer ID was excluded.' FROM #locations_ranked WHERE rn>1;
        SELECT source_record_hash,cid,cntry INTO #locations FROM #locations_ranked WHERE rn=1;
        SELECT @src=COUNT_BIG(*) FROM bronze.erp_loc_a101 WHERE source_batch_id=@batch; DELETE @actions;
        MERGE silver.erp_loc_a101 AS t USING #locations AS s ON t.cid=s.cid
        WHEN MATCHED AND t.record_hash<>s.source_record_hash THEN UPDATE SET cntry=s.cntry,record_hash=s.source_record_hash,source_batch_id=@batch,dwh_update_date=SYSUTCDATETIME()
        WHEN NOT MATCHED BY TARGET THEN INSERT(cid,cntry,record_hash,source_batch_id) VALUES(s.cid,s.cntry,s.source_record_hash,@batch)
        WHEN NOT MATCHED BY SOURCE THEN DELETE OUTPUT $action INTO @actions;
        SELECT @ins=COUNT_BIG(*) FROM @actions WHERE action_name=N'INSERT'; SELECT @upd=COUNT_BIG(*) FROM @actions WHERE action_name=N'UPDATE'; SELECT @del=COUNT_BIG(*) FROM @actions WHERE action_name=N'DELETE';
        SET @ended=SYSUTCDATETIME(); INSERT etl.table_load_logs(run_id,layer,table_name,started_at,ended_at,status,source_rows,inserted_rows,updated_rows,deleted_rows,rejected_rows,duration_ms)
        VALUES(@run_id,N'silver',N'erp_loc_a101',@started,@ended,'SUCCEEDED',@src,@ins,@upd,@del,0,DATEDIFF_BIG(millisecond,@started,@ended));

        SET @started=SYSUTCDATETIME(); SELECT @batch=source_batch_id FROM etl.pipeline_source_files WHERE run_id=@run_id AND source_key=N'erp_px_cat_g1v2';
        INSERT etl.rejected_records(run_id,source_key,entity_name,source_record_hash,reason_code,reason_detail)
        SELECT @run_id,N'erp_px_cat_g1v2',N'product_category',source_record_hash,N'MISSING_CATEGORY_FIELD',N'ERP product category ID or descriptive field is missing.'
        FROM bronze.erp_px_cat_g1v2 WHERE source_batch_id=@batch AND (NULLIF(TRIM(id),N'') IS NULL OR NULLIF(TRIM(cat),N'') IS NULL OR NULLIF(TRIM(subcat),N'') IS NULL);
        SELECT b.source_record_hash,TRIM(b.id) AS id,TRIM(b.cat) AS cat,TRIM(b.subcat) AS subcat,TRIM(b.maintenance) AS maintenance
        INTO #categories_base FROM bronze.erp_px_cat_g1v2 b WHERE b.source_batch_id=@batch AND NULLIF(TRIM(b.id),N'') IS NOT NULL AND NULLIF(TRIM(b.cat),N'') IS NOT NULL AND NULLIF(TRIM(b.subcat),N'') IS NOT NULL;
        SELECT *,ROW_NUMBER() OVER(PARTITION BY id ORDER BY source_record_hash) AS rn INTO #categories_ranked FROM #categories_base;
        INSERT etl.rejected_records(run_id,source_key,entity_name,source_record_hash,reason_code,reason_detail)
        SELECT @run_id,N'erp_px_cat_g1v2',N'product_category',source_record_hash,N'DUPLICATE_CATEGORY_ID',N'Additional ERP category row with the same ID was excluded.' FROM #categories_ranked WHERE rn>1;
        SELECT source_record_hash,id,cat,subcat,maintenance INTO #categories FROM #categories_ranked WHERE rn=1;
        SELECT @src=COUNT_BIG(*) FROM bronze.erp_px_cat_g1v2 WHERE source_batch_id=@batch; DELETE @actions;
        MERGE silver.erp_px_cat_g1v2 AS t USING #categories AS s ON t.id=s.id
        WHEN MATCHED AND t.record_hash<>s.source_record_hash THEN UPDATE SET cat=s.cat,subcat=s.subcat,maintenance=s.maintenance,record_hash=s.source_record_hash,source_batch_id=@batch,dwh_update_date=SYSUTCDATETIME()
        WHEN NOT MATCHED BY TARGET THEN INSERT(id,cat,subcat,maintenance,record_hash,source_batch_id) VALUES(s.id,s.cat,s.subcat,s.maintenance,s.source_record_hash,@batch)
        WHEN NOT MATCHED BY SOURCE THEN DELETE OUTPUT $action INTO @actions;
        SELECT @ins=COUNT_BIG(*) FROM @actions WHERE action_name=N'INSERT'; SELECT @upd=COUNT_BIG(*) FROM @actions WHERE action_name=N'UPDATE'; SELECT @del=COUNT_BIG(*) FROM @actions WHERE action_name=N'DELETE';
        SET @ended=SYSUTCDATETIME(); INSERT etl.table_load_logs(run_id,layer,table_name,started_at,ended_at,status,source_rows,inserted_rows,updated_rows,deleted_rows,rejected_rows,duration_ms)
        VALUES(@run_id,N'silver',N'erp_px_cat_g1v2',@started,@ended,'SUCCEEDED',@src,@ins,@upd,@del,0,DATEDIFF_BIG(millisecond,@started,@ended));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
