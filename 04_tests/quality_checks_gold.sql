/* Results of the Gold relationship, measure, SCD2, date and reconciliation gates. */
USE DataWarehouse;
GO
DECLARE @run_id uniqueidentifier=(SELECT TOP(1) run_id FROM etl.pipeline_runs ORDER BY started_at DESC);
SELECT run_id,layer,test_name,[rule],severity,actual_result,expected_result,outcome,failure_reason,tested_at
FROM etl.data_quality_results WHERE run_id=@run_id AND layer IN(N'gold',N'etl')
ORDER BY CASE severity WHEN 'CRITICAL' THEN 0 WHEN 'WARNING' THEN 1 ELSE 2 END,test_name;
SELECT metric_name,source_value,target_value,difference,explanation,recorded_at
FROM etl.reconciliation_results WHERE run_id=@run_id ORDER BY reconciliation_id;
SELECT reason_code,reason_detail,COUNT_BIG(*) AS rejected_rows
FROM etl.rejected_records WHERE run_id=@run_id AND entity_name=N'sales_line'
GROUP BY reason_code,reason_detail ORDER BY reason_code;
GO
