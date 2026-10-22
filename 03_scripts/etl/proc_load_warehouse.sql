/* Single entry point: Bronze -> Silver -> Gold -> reconciliation -> quality gate. */
USE DataWarehouse;
GO
CREATE OR ALTER PROCEDURE etl.load_warehouse
    @dataset_root nvarchar(2048),
    @manifest_json nvarchar(max),
    @run_mode varchar(12)='FULL'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @run_id uniqueidentifier=NEWID(),@started datetime2(3)=SYSUTCDATETIME(),@stage_started datetime2(3),@stage_ended datetime2(3),
        @stage sysname=N'preflight',@lock_result int,@dq_payload nvarchar(max),@dq_payload_bytes varbinary(8000),
        @err int,@proc nvarchar(128),@line int,@summary nvarchar(1000);
    IF UPPER(@run_mode) NOT IN ('FULL','INCREMENTAL') THROW 51130, 'run_mode must be FULL or INCREMENTAL.', 1;
    IF NULLIF(TRIM(@dataset_root),N'') IS NULL THROW 51131, 'dataset_root is required.', 1;
    EXEC sys.sp_set_session_context @key=N'dq_payload',@value=NULL;
    INSERT etl.pipeline_runs(run_id,pipeline_name,run_mode,started_at,status)
        VALUES(@run_id,N'sql_warehouse',UPPER(@run_mode),@started,'RUNNING');
    EXEC @lock_result=sys.sp_getapplock @Resource=N'etl.load_warehouse',@LockMode=N'Exclusive',@LockOwner=N'Session',@LockTimeout=0;
    IF @lock_result<0
    BEGIN
        UPDATE etl.pipeline_runs SET status='FAILED',ended_at=SYSUTCDATETIME(),error_summary=N'Another warehouse pipeline run is already active.' WHERE run_id=@run_id;
        THROW 51132, 'Another warehouse pipeline run is already active.', 1;
    END;
    BEGIN TRY
        SET @stage=N'bronze';
        SET @stage_started=SYSUTCDATETIME();
        EXEC bronze.load_bronze @run_id=@run_id,@dataset_root=@dataset_root,@manifest_json=@manifest_json;

        SET @stage=N'silver';
        SET @stage_started=SYSUTCDATETIME();
        EXEC silver.load_silver @run_id=@run_id,@run_mode=@run_mode;

        /* Gold mutation and quality gates share one transaction. A critical test rolls back
           every dimension, date, and fact change, leaving the last successful Gold snapshot. */
        BEGIN TRANSACTION;
        SET @stage=N'gold';
        SET @stage_started=SYSUTCDATETIME();
        EXEC gold.load_gold @run_id=@run_id;
        SET @stage=N'reconciliation';
        SET @stage_started=SYSUTCDATETIME();
        EXEC etl.build_reconciliation @run_id=@run_id;
        SET @stage=N'quality';
        SET @stage_started=SYSUTCDATETIME();
        EXEC etl.run_quality_checks @run_id=@run_id;
        COMMIT TRANSACTION;

        UPDATE etl.pipeline_runs SET status='SUCCEEDED',ended_at=SYSUTCDATETIME(),
            source_rows=(SELECT SUM(source_rows) FROM etl.pipeline_source_files WHERE run_id=@run_id),
            inserted_rows=(SELECT SUM(inserted_rows) FROM etl.table_load_logs WHERE run_id=@run_id),
            updated_rows=(SELECT SUM(updated_rows) FROM etl.table_load_logs WHERE run_id=@run_id),
            rejected_rows=(SELECT COUNT_BIG(*) FROM etl.rejected_records WHERE run_id=@run_id)
        WHERE run_id=@run_id;
        EXEC sys.sp_releaseapplock @Resource=N'etl.load_warehouse',@LockOwner=N'Session';
        SELECT run_id,pipeline_name,run_mode,started_at,ended_at,status,source_rows,inserted_rows,updated_rows,rejected_rows
        FROM etl.pipeline_runs WHERE run_id=@run_id;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        SET @stage_ended=SYSUTCDATETIME();
        SELECT @err=ERROR_NUMBER(),@proc=ERROR_PROCEDURE(),@line=ERROR_LINE();
        SET @summary=CASE WHEN @stage=N'quality' THEN N'Critical quality validation failed. See persisted test results.'
            WHEN @stage=N'bronze' THEN CONCAT(N'Bronze source staging failed (SQL error ',@err,N'). Check source file access and etl configuration.')
            ELSE CONCAT(@stage,N' stage failed (SQL error ',@err,N'). Source row values are omitted from the audit message.') END;
        SET @dq_payload_bytes=TRY_CONVERT(varbinary(8000),SESSION_CONTEXT(N'dq_payload'));
        IF @dq_payload_bytes IS NOT NULL SET @dq_payload=CONVERT(nvarchar(max),DECOMPRESS(@dq_payload_bytes));
        IF @dq_payload IS NOT NULL
        BEGIN
            INSERT etl.data_quality_results(run_id,layer,test_name,[rule],severity,actual_result,expected_result,outcome,failure_reason)
            SELECT @run_id,layer,test_name,[rule],severity,actual_result,expected_result,outcome,
                IIF(outcome='PASS',NULL,failure_reason)
            FROM OPENJSON(@dq_payload) WITH (
                layer sysname '$.layer',test_name sysname '$.test_name',[rule] nvarchar(1000) '$.rule',
                severity varchar(10) '$.severity',actual_result bigint '$.actual_result',
                expected_result nvarchar(200) '$.expected_result',outcome varchar(8) '$.outcome',failure_reason nvarchar(1000) '$.failure_reason'
            );
            EXEC sys.sp_set_session_context @key=N'dq_payload',@value=NULL;
        END;
        INSERT etl.table_load_logs(run_id,layer,table_name,started_at,ended_at,status,duration_ms,error_summary)
        VALUES(@run_id,@stage,@stage,@stage_started,@stage_ended,'FAILED',DATEDIFF_BIG(millisecond,@stage_started,@stage_ended),@summary);
        UPDATE etl.pipeline_runs SET status='FAILED',ended_at=SYSUTCDATETIME(),error_number=@err,
            error_procedure=@proc,error_line=@line,error_summary=@summary,
            source_rows=(SELECT SUM(source_rows) FROM etl.pipeline_source_files WHERE run_id=@run_id),
            rejected_rows=(SELECT COUNT_BIG(*) FROM etl.rejected_records WHERE run_id=@run_id)
        WHERE run_id=@run_id;
        EXEC sys.sp_releaseapplock @Resource=N'etl.load_warehouse',@LockOwner=N'Session';
        THROW;
    END CATCH;
END;
GO
