/* Called by the local runner when source files fail preflight before BULK INSERT. */
USE DataWarehouse;
GO
CREATE OR ALTER PROCEDURE etl.record_preflight_failure
    @source_key sysname,
    @reason_code sysname,
    @run_mode varchar(12)='FULL'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @run_id uniqueidentifier=NEWID(),@now datetime2(3)=SYSUTCDATETIME();
    INSERT etl.pipeline_runs(run_id,pipeline_name,run_mode,started_at,ended_at,status,error_summary)
    VALUES(@run_id,N'sql_warehouse',UPPER(@run_mode),@now,@now,'FAILED',CONCAT(N'Input preflight failed for ',@source_key,N' (',@reason_code,N').'));
    INSERT etl.table_load_logs(run_id,layer,table_name,started_at,ended_at,status,error_summary)
    VALUES(@run_id,N'preflight',@source_key,@now,@now,'FAILED',CONCAT(N'Input preflight failed for ',@source_key,N' (',@reason_code,N').'));
    SELECT @run_id AS run_id,'FAILED' AS status,@source_key AS source_key,@reason_code AS reason_code;
END;
GO
