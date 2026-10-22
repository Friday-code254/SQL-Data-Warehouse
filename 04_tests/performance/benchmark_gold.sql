/*
  Run after a successful pipeline. Enable Actual Execution Plan in SSMS (Ctrl+M)
  and capture Messages output. This records real elapsed times and result sizes;
  it intentionally makes no speed-up claim without a comparison run.
*/
USE DataWarehouse;
GO
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
DECLARE @run_id uniqueidentifier,@started datetime2(3),@ended datetime2(3),@rows bigint,@fact_rows bigint,
        @variant nvarchar(40);
SELECT @variant=CASE WHEN EXISTS(
    SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'gold.fact_sales')
        AND name=N'IX_gold_fact_order_date' AND is_disabled=1
) THEN N'baseline_without_reporting_indexes' ELSE N'with_reporting_indexes' END;
SELECT TOP(1) @run_id=run_id FROM etl.pipeline_runs WHERE status='SUCCEEDED' ORDER BY ended_at DESC;
SELECT @fact_rows=COUNT_BIG(*) FROM gold.fact_sales;
IF @run_id IS NULL THROW 51230,'A successful pipeline run is required before benchmarking.',1;

DROP TABLE IF EXISTS #monthly_sales;
SET @started=SYSUTCDATETIME();
SELECT d.calendar_year,d.month_number,SUM(f.sales_amount) AS sales_amount,COUNT_BIG(*) AS fact_rows
INTO #monthly_sales
FROM gold.fact_sales f JOIN gold.dim_date d ON d.date_key=f.order_date_key
GROUP BY d.calendar_year,d.month_number;
SET @ended=SYSUTCDATETIME(); SELECT @rows=COUNT_BIG(*) FROM #monthly_sales;
INSERT etl.performance_results(run_id,workload_name,started_at,ended_at,elapsed_ms,result_rows,fact_rows,notes)
VALUES(@run_id,N'monthly_sales_by_order_date',@started,@ended,DATEDIFF_BIG(millisecond,@started,@ended),@rows,@fact_rows,CONCAT(N'variant=',@variant,N'; group fact sales by the order-date dimension. Review Actual Plan and STATISTICS IO/TIME.'));
SELECT * FROM #monthly_sales ORDER BY calendar_year,month_number;

DROP TABLE IF EXISTS #product_sales;
SET @started=SYSUTCDATETIME();
SELECT p.category,p.subcategory,p.product_name,SUM(f.sales_amount) AS sales_amount,SUM(f.quantity) AS units_sold
INTO #product_sales
FROM gold.fact_sales f JOIN gold.dim_products p ON p.product_key=f.product_key
WHERE p.is_current=1
GROUP BY p.category,p.subcategory,p.product_name;
SET @ended=SYSUTCDATETIME(); SELECT @rows=COUNT_BIG(*) FROM #product_sales;
INSERT etl.performance_results(run_id,workload_name,started_at,ended_at,elapsed_ms,result_rows,fact_rows,notes)
VALUES(@run_id,N'product_sales_rollup',@started,@ended,DATEDIFF_BIG(millisecond,@started,@ended),@rows,@fact_rows,CONCAT(N'variant=',@variant,N'; join and aggregate facts by current product attributes.'));
SELECT TOP(20) * FROM #product_sales ORDER BY sales_amount DESC;

DROP TABLE IF EXISTS #customer_sales;
SET @started=SYSUTCDATETIME();
SELECT c.country,c.customer_id,SUM(f.sales_amount) AS lifetime_sales,COUNT_BIG(*) AS line_count
INTO #customer_sales
FROM gold.fact_sales f JOIN gold.dim_customers c ON c.customer_key=f.customer_key
WHERE c.is_current=1
GROUP BY c.country,c.customer_id;
SET @ended=SYSUTCDATETIME(); SELECT @rows=COUNT_BIG(*) FROM #customer_sales;
INSERT etl.performance_results(run_id,workload_name,started_at,ended_at,elapsed_ms,result_rows,fact_rows,notes)
VALUES(@run_id,N'customer_sales_rollup',@started,@ended,DATEDIFF_BIG(millisecond,@started,@ended),@rows,@fact_rows,CONCAT(N'variant=',@variant,N'; join and aggregate facts by current customer attributes.'));
SELECT TOP(20) * FROM #customer_sales ORDER BY lifetime_sales DESC;
SELECT workload_name,elapsed_ms,result_rows,fact_rows,started_at,ended_at,notes
FROM etl.performance_results WHERE run_id=@run_id ORDER BY performance_id;
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
