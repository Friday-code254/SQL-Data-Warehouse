/* Read-only checks for a completed pipeline run. */
USE DataWarehouse;
GO
DECLARE @latest uniqueidentifier;
SELECT TOP(1) @latest=run_id FROM etl.pipeline_runs ORDER BY started_at DESC;
IF @latest IS NULL THROW 51200,'No pipeline run is recorded.',1;
IF NOT EXISTS(SELECT 1 FROM etl.pipeline_runs WHERE run_id=@latest AND status='SUCCEEDED')
    THROW 51201,'The latest pipeline run did not succeed; inspect etl.pipeline_runs.',1;
IF EXISTS(SELECT 1 FROM etl.data_quality_results WHERE run_id=@latest AND severity='CRITICAL' AND outcome='FAIL')
    THROW 51202,'The latest pipeline run contains a critical quality failure.',1;
IF EXISTS(SELECT 1 FROM gold.fact_sales f LEFT JOIN gold.dim_customers c ON c.customer_key=f.customer_key LEFT JOIN gold.dim_products p ON p.product_key=f.product_key WHERE c.customer_key IS NULL OR p.product_key IS NULL)
    THROW 51203,'A fact row has an unresolved customer or product.',1;
SELECT r.run_id,r.status,r.source_rows,r.inserted_rows,r.updated_rows,r.rejected_rows,
       (SELECT COUNT_BIG(*) FROM gold.fact_sales) AS gold_fact_rows,
       (SELECT SUM(sales_amount) FROM gold.fact_sales) AS gold_sales_amount
FROM etl.pipeline_runs r WHERE r.run_id=@latest;
SELECT test_name,severity,actual_result,expected_result,outcome,failure_reason
FROM etl.data_quality_results WHERE run_id=@latest ORDER BY severity,test_name;
SELECT metric_name,source_value,target_value,difference,explanation
FROM etl.reconciliation_results WHERE run_id=@latest ORDER BY reconciliation_id;
GO
