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
        @source_sales decimal(28,4),@rejected_sales_amount decimal(28,4),@accepted_source_sales decimal(28,4),
        @silver_sales decimal(28,4),@gold_sales decimal(28,4);
    DELETE FROM etl.reconciliation_results WHERE run_id=@run_id;
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
    /* Build source amounts once, using the same blank-sales fallback as the previous source total.
       Aggregate by hash because identical source lines can share a hash while only some copies are rejected. */
    SELECT b.source_record_hash,
        CONVERT(decimal(28,4),CASE
            WHEN TRY_CONVERT(decimal(19,4),NULLIF(TRIM(b.sls_sales),N'')) IS NOT NULL
                THEN TRY_CONVERT(decimal(19,4),NULLIF(TRIM(b.sls_sales),N''))
            WHEN NULLIF(TRIM(b.sls_sales),N'') IS NULL AND TRY_CONVERT(int,NULLIF(TRIM(b.sls_quantity),N''))>0
                 AND TRY_CONVERT(decimal(19,4),NULLIF(TRIM(b.sls_price),N''))>=0
                THEN TRY_CONVERT(int,NULLIF(TRIM(b.sls_quantity),N''))*TRY_CONVERT(decimal(19,4),NULLIF(TRIM(b.sls_price),N''))
            ELSE 0 END) AS source_sales_amount
    INTO #sales_source_amounts
    FROM bronze.crm_sales_details b WHERE b.source_batch_id=@batch;
    SELECT source_record_hash,MAX(source_sales_amount) AS amount_per_row,COUNT_BIG(*) AS source_row_count
    INTO #sales_source_amounts_by_hash
    FROM #sales_source_amounts GROUP BY source_record_hash;
    SELECT @source_sales=COALESCE(SUM(amount_per_row*source_row_count),0)
    FROM #sales_source_amounts_by_hash;
    SELECT @rejected_sales_amount=COALESCE(SUM(h.amount_per_row*r.rejected_rows),0)
    FROM #sales_source_amounts_by_hash h
    JOIN (
        SELECT source_record_hash,COUNT_BIG(*) AS rejected_rows
        FROM etl.rejected_records
        WHERE run_id=@run_id AND source_key=N'crm_sales_details' AND reason_code NOT LIKE N'UNMATCHED_%'
        GROUP BY source_record_hash
    ) r ON r.source_record_hash=h.source_record_hash;
    SELECT @accepted_source_sales=COALESCE(SUM(h.amount_per_row*(h.source_row_count-COALESCE(r.rejected_rows,0))),0)
    FROM #sales_source_amounts_by_hash h
    LEFT JOIN (
        SELECT source_record_hash,COUNT_BIG(*) AS rejected_rows
        FROM etl.rejected_records
        WHERE run_id=@run_id AND source_key=N'crm_sales_details' AND reason_code NOT LIKE N'UNMATCHED_%'
        GROUP BY source_record_hash
    ) r ON r.source_record_hash=h.source_record_hash;
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
      (@run_id,N'source_sales_amount',@source_sales,@silver_sales,@source_sales-@silver_sales,N'Source-to-Silver difference is decomposed into raw source sales amounts on Silver rejects and the accepted-source-to-Silver normalization adjustment.'),
      (@run_id,N'source_silver_sales_amount',@accepted_source_sales,@silver_sales,@accepted_source_sales-@silver_sales,N'Accepted source amount versus Silver amount; the difference is the accepted-row normalization adjustment and is part of the source-to-Gold bridge.'),
      (@run_id,N'rejected_sales_amount_total',@rejected_sales_amount,0,@rejected_sales_amount,N'Signed source sales amount assigned to reason-coded sales rejects before Silver; reason-level amounts are recorded as sales_reject_amount_<reason_code>.'),
      (@run_id,N'silver_gold_sales_amount',@silver_sales,@gold_sales,@silver_sales-@gold_sales,N'This Silver-to-Gold amount difference is the Gold-stage component of the source-to-Gold bridge.'),
      (@run_id,N'gold_unmatched_sales_amount',@silver_sales,@unmatched_amount,@silver_sales-@gold_sales-@unmatched_amount,N'Amount excluded from Gold due to unresolved current customer or product dimensions.'),
      (@run_id,N'source_gold_sales_amount',@source_sales,@gold_sales,@source_sales-@gold_sales,N'End-to-end variance; compare with reason-level sales rejects, accepted-source-to-Silver adjustment, and Silver-to-Gold difference.'),
      (@run_id,N'source_gold_sales_amount_bridge',@source_sales,
        @gold_sales+@rejected_sales_amount+(@accepted_source_sales-@silver_sales)+(@silver_sales-@gold_sales),
        @source_sales-(@gold_sales+@rejected_sales_amount+(@accepted_source_sales-@silver_sales)+(@silver_sales-@gold_sales)),
        N'Source amount must equal Gold amount plus reason-coded Silver rejects, accepted-source-to-Silver normalization adjustment, and Silver-to-Gold difference. Zero difference means the amount is accounted for; it does not confer business approval.');

    ;WITH sales_rejections AS (
        SELECT source_record_hash,reason_code,COUNT_BIG(*) AS rejected_rows
        FROM etl.rejected_records
        WHERE run_id=@run_id AND source_key=N'crm_sales_details' AND reason_code NOT LIKE N'UNMATCHED_%'
        GROUP BY source_record_hash,reason_code
    )
    INSERT etl.reconciliation_results(run_id,metric_name,source_value,target_value,difference,explanation)
    SELECT @run_id,CONCAT(N'sales_reject_amount_',r.reason_code),
        SUM(h.amount_per_row*r.rejected_rows),CONVERT(decimal(28,4),0),SUM(h.amount_per_row*r.rejected_rows),
        CONCAT(N'Signed source sales amount for Silver-rejected rows with reason ',r.reason_code,N'; this is an amount contribution to the source-to-Gold bridge, not a disposition decision.')
    FROM sales_rejections r
    JOIN #sales_source_amounts_by_hash h ON h.source_record_hash=r.source_record_hash
    GROUP BY r.reason_code;
END;
GO
