/* Persist current-run row-count and amount reconciliation for the sales path. */
USE DataWarehouse;
GO
CREATE OR ALTER PROCEDURE etl.build_reconciliation @run_id uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @batch uniqueidentifier,@source_rows decimal(28,4),@bronze_rows decimal(28,4),
        @silver_rows decimal(28,4),@rejected decimal(28,4),@unmatched_rows decimal(28,4),@gold_rows decimal(28,4),
        @unmatched_amount decimal(28,4),
        @source_sales decimal(28,4),@silver_sales decimal(28,4),@gold_sales decimal(28,4);
    SELECT @batch=source_batch_id FROM etl.pipeline_source_files WHERE run_id=@run_id AND source_key=N'crm_sales_details';
    SELECT @source_rows=source_rows FROM etl.pipeline_source_files WHERE run_id=@run_id AND source_key=N'crm_sales_details';
    SELECT @bronze_rows=COUNT_BIG(*) FROM bronze.crm_sales_details WHERE source_batch_id=@batch;
    SELECT @silver_rows=COUNT_BIG(*) FROM silver.crm_sales_details;
    SELECT @rejected=COUNT_BIG(*) FROM etl.rejected_records WHERE run_id=@run_id AND source_key=N'crm_sales_details' AND reason_code NOT LIKE N'UNMATCHED_%';
    SELECT @unmatched_rows=COUNT_BIG(*),@unmatched_amount=COALESCE(SUM(s.sls_sales),0)
    FROM silver.crm_sales_details s
    LEFT JOIN gold.dim_products p ON p.product_number=s.sls_prd_key AND p.is_current=1
    LEFT JOIN gold.dim_customers c ON c.customer_id=s.sls_cust_id AND c.is_current=1
    WHERE p.product_key IS NULL OR c.customer_key IS NULL;
    SELECT @gold_rows=COUNT_BIG(*) FROM gold.fact_sales;
    SELECT @source_sales=SUM(CASE
        WHEN TRY_CONVERT(decimal(19,4),NULLIF(TRIM(sls_sales),N'')) IS NOT NULL THEN TRY_CONVERT(decimal(19,4),NULLIF(TRIM(sls_sales),N''))
        WHEN NULLIF(TRIM(sls_sales),N'') IS NULL AND TRY_CONVERT(int,NULLIF(TRIM(sls_quantity),N''))>0
             AND TRY_CONVERT(decimal(19,4),NULLIF(TRIM(sls_price),N''))>=0
            THEN TRY_CONVERT(int,NULLIF(TRIM(sls_quantity),N''))*TRY_CONVERT(decimal(19,4),NULLIF(TRIM(sls_price),N''))
        ELSE 0 END)
    FROM bronze.crm_sales_details WHERE source_batch_id=@batch;
    SELECT @silver_sales=COALESCE(SUM(sls_sales),0) FROM silver.crm_sales_details;
    SELECT @gold_sales=COALESCE(SUM(sales_amount),0) FROM gold.fact_sales;

    INSERT etl.reconciliation_results(run_id,metric_name,source_value,target_value,difference,explanation)
    VALUES
      (@run_id,N'source_sales_rows',@source_rows,@source_rows,0,N'Count from the validated source manifest.'),
      (@run_id,N'bronze_sales_rows',@source_rows,@bronze_rows,@source_rows-@bronze_rows,N'Bronze rows are retained once per unique source-file checksum; replays reference the original batch.'),
      (@run_id,N'silver_sales_rows',@bronze_rows,@silver_rows,@bronze_rows-@silver_rows,N'Difference is accounted for by reason-coded rejected or duplicate source rows.'),
      (@run_id,N'sales_rejected_rows',@source_rows,@rejected,@source_rows-@silver_rows-@rejected,N'Silver rejection counts explain malformed, invalid, or duplicate-grain source rows.'),
      (@run_id,N'gold_fact_rows',@silver_rows,@gold_rows,@silver_rows-@gold_rows,N'Difference is due to documented unmatched-dimension exclusions in etl.rejected_records.'),
      (@run_id,N'gold_unmatched_dimension_rows',@silver_rows,@unmatched_rows,@silver_rows-@gold_rows-@unmatched_rows,N'Rows without a current customer/product are excluded from Gold and have reason-coded rejection records.'),
      (@run_id,N'source_sales_amount',@source_sales,@silver_sales,@source_sales-@silver_sales,N'Invalid records and normalization corrections can change the accepted amount; review rejected rows and Silver correction_code.'),
      (@run_id,N'silver_gold_sales_amount',@silver_sales,@gold_sales,@silver_sales-@gold_sales,N'Gold amount should equal accepted Silver amount less unmatched dimension rows.'),
      (@run_id,N'gold_unmatched_sales_amount',@silver_sales,@unmatched_amount,@silver_sales-@gold_sales-@unmatched_amount,N'Amount excluded from Gold due to unresolved current customer or product dimensions.'),
      (@run_id,N'source_gold_sales_amount',@source_sales,@gold_sales,@source_sales-@gold_sales,N'End-to-end difference is explained by Silver rejects, corrections, or Gold unmatched-dimension rejects.');
END;
GO
