/* Results of the Silver checks that ran as part of etl.load_warehouse. */
USE DataWarehouse;
GO
DECLARE @run_id uniqueidentifier=(SELECT TOP(1) run_id FROM etl.pipeline_runs ORDER BY started_at DESC);
SELECT run_id,layer,test_name,[rule],severity,actual_result,expected_result,outcome,failure_reason,tested_at
FROM etl.data_quality_results WHERE run_id=@run_id AND layer IN(N'silver',N'etl')
ORDER BY CASE severity WHEN 'CRITICAL' THEN 0 WHEN 'WARNING' THEN 1 ELSE 2 END,test_name;
SELECT source_key,entity_name,reason_code,reason_detail,COUNT_BIG(*) AS rejected_rows
FROM etl.rejected_records WHERE run_id=@run_id AND source_key NOT IN(N'crm_sales_details')
GROUP BY source_key,entity_name,reason_code,reason_detail ORDER BY source_key,reason_code;
GO
