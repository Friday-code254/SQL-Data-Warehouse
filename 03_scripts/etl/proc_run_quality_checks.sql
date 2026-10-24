/* Named pipeline gates. Critical failures block the Gold transaction; warnings persist. */
USE DataWarehouse;
GO
CREATE OR ALTER PROCEDURE etl.run_quality_checks @run_id uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @tests table(layer sysname,test_name sysname,[rule] nvarchar(1000),severity varchar(10),actual_result bigint,expected_result nvarchar(200),outcome varchar(8),failure_reason nvarchar(1000));
    DECLARE @bad bigint,@expected bigint,@source_rows bigint,@bronze_rows bigint,@accepted bigint,@rejected bigint,@gold bigint,@diff decimal(28,4);

    SELECT @bad=COUNT_BIG(*) FROM (SELECT cst_id FROM silver.crm_cust_info GROUP BY cst_id HAVING cst_id IS NULL OR COUNT_BIG(*)>1) q;
    INSERT @tests VALUES(N'silver',N'customer_key_unique',N'Customer business key is populated and unique.',N'CRITICAL',@bad,N'0 violations',IIF(@bad=0,'PASS','FAIL'),N'Duplicate or missing customer key in Silver.');
    SELECT @bad=COUNT_BIG(*) FROM (SELECT cst_key FROM silver.crm_cust_info GROUP BY cst_key HAVING cst_key IS NULL OR COUNT_BIG(*)>1) q;
    INSERT @tests VALUES(N'silver',N'customer_number_unique',N'CRM customer number is populated and unique in the accepted snapshot.',N'CRITICAL',@bad,N'0 violations',IIF(@bad=0,'PASS','FAIL'),N'Duplicate or missing customer business number in Silver.');
    SELECT @bad=COUNT_BIG(*) FROM (SELECT prd_id FROM silver.crm_prd_info GROUP BY prd_id HAVING prd_id IS NULL OR COUNT_BIG(*)>1) q;
    INSERT @tests VALUES(N'silver',N'product_key_unique',N'Product source key is populated and unique.',N'CRITICAL',@bad,N'0 violations',IIF(@bad=0,'PASS','FAIL'),N'Duplicate or missing product key in Silver.');
    SELECT @bad=COUNT_BIG(*) FROM (SELECT sls_ord_num,sls_prd_key,sls_cust_id,sls_order_dt FROM silver.crm_sales_details GROUP BY sls_ord_num,sls_prd_key,sls_cust_id,sls_order_dt HAVING COUNT_BIG(*)>1) q;
    INSERT @tests VALUES(N'silver',N'sales_grain_unique',N'One accepted line per order, product, customer, and order date.',N'CRITICAL',@bad,N'0 duplicates',IIF(@bad=0,'PASS','FAIL'),N'Duplicate Silver sales grain.');
    SELECT @bad=COUNT_BIG(*) FROM silver.crm_cust_info WHERE cst_id IS NULL OR NULLIF(TRIM(cst_key),N'') IS NULL OR NULLIF(TRIM(cst_firstname),N'') IS NULL OR NULLIF(TRIM(cst_lastname),N'') IS NULL;
    INSERT @tests VALUES(N'silver',N'customer_required_fields',N'Customer ID, business key, first name and last name are populated.',N'CRITICAL',@bad,N'0 missing fields',IIF(@bad=0,'PASS','FAIL'),N'Required customer fields are missing.');
    SELECT @bad=COUNT_BIG(*) FROM silver.crm_prd_info WHERE prd_id IS NULL OR NULLIF(TRIM(prd_key),N'') IS NULL OR NULLIF(TRIM(prd_nm),N'') IS NULL OR prd_start_dt IS NULL OR prd_cost<0 OR prd_end_dt<prd_start_dt;
    INSERT @tests VALUES(N'silver',N'product_required_and_valid',N'Product keys and names exist; cost is nonnegative and effective dates are ordered.',N'CRITICAL',@bad,N'0 violations',IIF(@bad=0,'PASS','FAIL'),N'Product field, cost, or date validation failed.');
    SELECT @bad=COUNT_BIG(*) FROM silver.crm_sales_details WHERE sls_ord_num IS NULL OR sls_prd_key IS NULL OR sls_cust_id IS NULL OR sls_order_dt IS NULL OR sls_quantity<=0 OR sls_price<0 OR sls_sales<0 OR ABS(sls_sales-CONVERT(decimal(19,4),sls_quantity*sls_price))>CASE WHEN correction_code=N'PRICE_DERIVED_FROM_SALES' THEN CONVERT(decimal(19,4),0.0001*sls_quantity) ELSE CONVERT(decimal(19,4),0.0001) END OR (sls_ship_dt IS NOT NULL AND sls_order_dt>sls_ship_dt) OR (sls_due_dt IS NOT NULL AND sls_order_dt>sls_due_dt) OR (sls_ship_dt IS NOT NULL AND sls_due_dt IS NOT NULL AND sls_ship_dt>sls_due_dt);
    INSERT @tests VALUES(N'silver',N'sales_dates_quantity_and_amount',N'Accepted sales have valid date order, positive quantity, nonnegative amounts, and sales equals quantity times price.',N'CRITICAL',@bad,N'0 violations',IIF(@bad=0,'PASS','FAIL'),N'Sales validation failed for an accepted Silver row.');
    SELECT @bad=COUNT_BIG(*) FROM silver.crm_cust_info WHERE cst_gndr NOT IN(N'Female',N'Male',N'n/a') OR cst_marital_status NOT IN(N'Single',N'Married',N'n/a');
    INSERT @tests VALUES(N'silver',N'customer_code_values',N'Gender and marital status use documented standardized values.',N'CRITICAL',@bad,N'0 violations',IIF(@bad=0,'PASS','FAIL'),N'Unexpected standardized customer value.');
    SELECT @bad=COUNT_BIG(*) FROM silver.crm_prd_info WHERE prd_line NOT IN(N'Mountain',N'Road',N'Other Sales',N'Touring',N'n/a');
    INSERT @tests VALUES(N'silver',N'product_line_values',N'Product line uses the documented mapping.',N'CRITICAL',@bad,N'0 violations',IIF(@bad=0,'PASS','FAIL'),N'Unexpected product line value.');
    SELECT @bad=COUNT_BIG(*) FROM silver.crm_prd_info WHERE correction_code IS NOT NULL;
    INSERT @tests VALUES(N'silver',N'product_date_repairs_reported',N'Product validity end dates rebuilt from ordered source versions are explicitly marked.',N'WARNING',@bad,N'0 preferred; each correction is identified',IIF(@bad=0,'PASS','WARN'),N'One or more product end dates were rebuilt or cleared; see silver.crm_prd_info.correction_code.');
    SELECT @bad=COUNT_BIG(*) FROM silver.erp_cust_az12 WHERE gen NOT IN(N'Female',N'Male',N'n/a') OR bdate>CONVERT(date,SYSUTCDATETIME());
    INSERT @tests VALUES(N'silver',N'erp_customer_values',N'ERP gender and birthdate enrichment values are standardized and not future dated.',N'CRITICAL',@bad,N'0 violations',IIF(@bad=0,'PASS','FAIL'),N'Invalid ERP customer enrichment value.');
    SELECT @bad=COUNT_BIG(*) FROM silver.erp_px_cat_g1v2 WHERE NULLIF(TRIM(id),N'') IS NULL OR NULLIF(TRIM(cat),N'') IS NULL OR NULLIF(TRIM(subcat),N'') IS NULL OR maintenance NOT IN(N'Yes',N'No',N'n/a');
    INSERT @tests VALUES(N'silver',N'category_required_values',N'ERP category keys and descriptions are populated and maintenance uses its source values.',N'CRITICAL',@bad,N'0 violations',IIF(@bad=0,'PASS','FAIL'),N'ERP category validation failed.');
    SELECT @bad=COUNT_BIG(*) FROM (SELECT customer_id FROM gold.dim_customers WHERE is_current=1 AND customer_id<>0 GROUP BY customer_id HAVING COUNT_BIG(*)<>1) q;
    INSERT @tests VALUES(N'gold',N'one_current_customer_version',N'Each represented customer has exactly one current dimension version.',N'CRITICAL',COALESCE(@bad,0),N'0 duplicate current keys',IIF(COALESCE(@bad,0)=0,'PASS','FAIL'),N'Multiple current customer dimension versions.');
    SELECT @bad=COUNT_BIG(*) FROM (SELECT product_number FROM gold.dim_products WHERE is_current=1 AND product_key<>0 GROUP BY product_number HAVING COUNT_BIG(*)<>1) q;
    INSERT @tests VALUES(N'gold',N'one_current_product_version',N'Each represented product has exactly one current dimension version.',N'CRITICAL',COALESCE(@bad,0),N'0 duplicate current keys',IIF(COALESCE(@bad,0)=0,'PASS','FAIL'),N'Multiple current product dimension versions.');
    SELECT @bad=COUNT_BIG(*) FROM gold.fact_sales f LEFT JOIN gold.dim_customers c ON c.customer_key=f.customer_key LEFT JOIN gold.dim_products p ON p.product_key=f.product_key LEFT JOIN gold.dim_date d ON d.date_key=f.order_date_key LEFT JOIN gold.dim_date sd ON sd.date_key=f.shipping_date_key LEFT JOIN gold.dim_date dd ON dd.date_key=f.due_date_key WHERE c.customer_key IS NULL OR p.product_key IS NULL OR d.date_key IS NULL OR sd.date_key IS NULL OR dd.date_key IS NULL;
    INSERT @tests VALUES(N'gold',N'fact_dimension_relationships',N'Every fact has enforced customer, product, and role-playing date dimension members.',N'CRITICAL',@bad,N'0 unmatched foreign keys',IIF(@bad=0,'PASS','FAIL'),N'Fact row does not resolve to a Gold dimension.');
    SELECT @bad=COUNT_BIG(*) FROM gold.fact_sales WHERE quantity<=0 OR sales_amount<0 OR price<0 OR ABS(sales_amount-CONVERT(decimal(19,4),quantity*price))>CASE WHEN correction_code=N'PRICE_DERIVED_FROM_SALES' THEN CONVERT(decimal(19,4),0.0001*quantity) ELSE CONVERT(decimal(19,4),0.0001) END;
    INSERT @tests VALUES(N'gold',N'fact_measure_validity',N'Published fact measures are valid; division rounding is tolerated only for a derived price.',N'CRITICAL',@bad,N'0 violations',IIF(@bad=0,'PASS','FAIL'),N'Gold fact measure validation failed.');
    DECLARE @min_date date,@max_date date,@date_count bigint;
    SELECT @min_date=MIN(order_date),@max_date=MAX(order_date) FROM gold.fact_sales;
    SELECT @date_count=COUNT_BIG(*) FROM gold.dim_date WHERE date_key<>0 AND full_date BETWEEN @min_date AND @max_date;
    SELECT @bad=CASE WHEN @min_date IS NULL THEN 0 ELSE ABS(DATEDIFF(day,@min_date,@max_date)+1-COALESCE(@date_count,0)) END;
    INSERT @tests VALUES(N'gold',N'date_dimension_complete',N'Date dimension has one row for each calendar day in the fact order-date range.',N'CRITICAL',@bad,N'0 missing dates',IIF(@bad=0,'PASS','FAIL'),N'Gold date dimension has gaps in the loaded analysis range.');
    SELECT @diff=ABS(COALESCE((SELECT SUM(sales_amount) FROM gold.fact_sales),0)-COALESCE((
        SELECT SUM(s.sls_sales) FROM silver.crm_sales_details s
        WHERE EXISTS(SELECT 1 FROM gold.dim_products p WHERE p.product_number=s.sls_prd_key AND p.is_current=1)
          AND EXISTS(SELECT 1 FROM gold.dim_customers c WHERE c.customer_id=s.sls_cust_id AND c.is_current=1)
    ),0));
    INSERT @tests VALUES(N'gold',N'silver_gold_sales_reconciliation',N'Gold sales total equals accepted Silver sales total after documented dimension exclusions.',N'CRITICAL',IIF(@diff>0.0001,1,0),N'0 amount variance',IIF(@diff<=0.0001,'PASS','FAIL'),N'Silver-to-Gold amount reconciliation differs.');
    SELECT @bad=COUNT_BIG(*) FROM etl.rejected_records WHERE run_id=@run_id;
    INSERT @tests VALUES(N'etl',N'rejected_records_visible',N'Rows excluded or corrected by a documented rule are captured without raw field values.',N'WARNING',@bad,N'0 preferred; nonzero requires review',IIF(@bad=0,'PASS','WARN'),N'One or more rows were recorded in etl.rejected_records.');
    SELECT @source_rows=source_rows FROM etl.pipeline_source_files WHERE run_id=@run_id AND source_key=N'crm_sales_details';
    SELECT @bronze_rows=COUNT_BIG(*) FROM bronze.crm_sales_details b JOIN etl.pipeline_source_files p ON p.source_key=N'crm_sales_details' AND p.run_id=@run_id AND p.source_batch_id=b.source_batch_id;
    SELECT @accepted=COUNT_BIG(*) FROM silver.crm_sales_details;
    SELECT @rejected=COUNT_BIG(*) FROM etl.rejected_records WHERE run_id=@run_id AND source_key=N'crm_sales_details' AND reason_code NOT LIKE N'UNMATCHED_%';
    SELECT @gold=COUNT_BIG(*) FROM gold.fact_sales;
    SELECT @expected=COUNT_BIG(*) FROM etl.rejected_records WHERE run_id=@run_id AND source_key=N'crm_sales_details' AND reason_code LIKE N'UNMATCHED_%';
    INSERT @tests VALUES(N'etl',N'source_to_bronze_reconciliation',N'Every validated source row appears once in its retained Bronze batch.',N'CRITICAL',IIF(@source_rows=@bronze_rows,0,1),N'0 source-to-Bronze mismatch',IIF(@source_rows=@bronze_rows,'PASS','FAIL'),N'Source and Bronze row counts differ.');
    INSERT @tests VALUES(N'etl',N'silver_acceptance_reconciliation',N'Each sales input is accepted or rejected with a non-Gold transformation reason.',N'CRITICAL',ABS(COALESCE(@source_rows,0)-COALESCE(@accepted,0)-COALESCE(@rejected,0)),N'0 unexplained source rows',IIF(COALESCE(@source_rows,0)=COALESCE(@accepted,0)+COALESCE(@rejected,0),'PASS','FAIL'),N'Source, Silver, and rejection counts do not reconcile.');
    INSERT @tests VALUES(N'etl',N'gold_fact_reconciliation',N'Gold facts equal accepted Silver rows after explicit unmatched-dimension rejects.',N'CRITICAL',ABS(COALESCE(@accepted,0)-COALESCE(@expected,0)-COALESCE(@gold,0)),N'0 unexplained fact rows',IIF(COALESCE(@accepted,0)=COALESCE(@expected,0)+COALESCE(@gold,0),'PASS','FAIL'),N'Accepted sales and Gold fact counts do not reconcile.');
    SELECT @diff=MAX(ABS(COALESCE(difference,0))) FROM etl.reconciliation_results WHERE run_id=@run_id AND metric_name=N'source_gold_sales_amount_bridge';
    INSERT @tests VALUES(N'etl',N'source_gold_sales_amount_bridge',N'Gold amount plus reason-coded Silver rejects, accepted-source/Silver adjustment, and Silver/Gold difference reconstructs the source amount.',N'CRITICAL',IIF(@diff IS NULL OR @diff>0.0001,1,0),N'0 unexplained amount variance',IIF(@diff IS NOT NULL AND @diff<=0.0001,'PASS','FAIL'),N'Source-to-Gold sales amount is not fully accounted for by persisted bridge components. A balanced bridge is an accounting result, not business approval.');

    INSERT etl.data_quality_results(run_id,layer,test_name,[rule],severity,actual_result,expected_result,outcome,failure_reason)
    SELECT @run_id,layer,test_name,[rule],severity,actual_result,expected_result,outcome,IIF(outcome='PASS',NULL,failure_reason) FROM @tests;
    IF EXISTS(SELECT 1 FROM @tests WHERE severity=N'CRITICAL' AND outcome=N'FAIL')
    BEGIN
        DECLARE @payload nvarchar(max);
        SELECT @payload=(SELECT layer,test_name,[rule],severity,actual_result,expected_result,outcome,failure_reason
            FROM @tests WHERE severity=N'CRITICAL' AND outcome=N'FAIL' FOR JSON PATH);
        DECLARE @compressed_payload varbinary(max)=COMPRESS(CONVERT(varbinary(max),@payload));
        IF DATALENGTH(@compressed_payload)>8000 THROW 51121,'Quality failure details exceed the audit transfer limit.',1;
        DECLARE @payload_bytes varbinary(8000)=CONVERT(varbinary(8000),@compressed_payload);
        EXEC sys.sp_set_session_context @key=N'dq_payload',@value=@payload_bytes;
        THROW 51120, 'Critical data quality gate failed; see etl.data_quality_results.', 1;
    END;
END;
GO
