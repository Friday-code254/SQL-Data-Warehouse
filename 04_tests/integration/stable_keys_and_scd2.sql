/* Run only in a disposable development database after one successful load. */
USE DataWarehouse;
GO
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @run_id uniqueidentifier=NEWID(),@customer_id int,@cid nvarchar(50),@old_key int,@new_key int,@source_batch uniqueidentifier=NEWID();
    DECLARE @before table(customer_id int PRIMARY KEY,customer_key int);
    INSERT @before SELECT customer_id,customer_key FROM gold.dim_customers WHERE is_current=1 AND customer_id<>0;
    SELECT TOP(1) @customer_id=ci.cst_id,@cid=ci.cst_key
    FROM silver.crm_cust_info ci JOIN silver.erp_loc_a101 l ON l.cid=ci.cst_key
    ORDER BY ci.cst_id;
    IF @customer_id IS NULL THROW 51210,'No customer with ERP location data is available for the SCD2 acceptance check.',1;
    SELECT @old_key=customer_key FROM gold.dim_customers WHERE customer_id=@customer_id AND is_current=1;
    INSERT etl.pipeline_runs(run_id,pipeline_name,run_mode,started_at,status)
        VALUES(@run_id,N'scd2_acceptance','INCREMENTAL',SYSUTCDATETIME(),'RUNNING');

    /* Lower-sorting new ID must not renumber existing dimension keys. */
    INSERT silver.crm_cust_info(cst_id,cst_key,cst_firstname,cst_lastname,cst_marital_status,cst_gndr,cst_create_date,record_hash,source_batch_id)
    VALUES(1,N'AA00000001',N'Synthetic',N'Customer',N'Single',N'n/a',CONVERT(date,'20200101'),HASHBYTES('SHA2_256',N'SYNTHETIC'),@source_batch);
    EXEC gold.load_gold @run_id=@run_id;
    IF EXISTS(SELECT 1 FROM @before b JOIN gold.dim_customers d ON d.customer_id=b.customer_id AND d.is_current=1 WHERE d.customer_key<>b.customer_key)
        THROW 51211,'An existing customer surrogate key changed after an earlier-sorting customer was added.',1;
    DELETE FROM silver.crm_cust_info WHERE cst_id=1;

    /* Observe a changed attribute, expire the old version, and repoint latest facts. */
    UPDATE silver.erp_loc_a101 SET cntry=CASE WHEN cntry=N'Codex Test' THEN N'Codex Test 2' ELSE N'Codex Test' END WHERE cid=@cid;
    EXEC gold.load_gold @run_id=@run_id;
    SELECT @new_key=customer_key FROM gold.dim_customers WHERE customer_id=@customer_id AND is_current=1;
    IF @new_key=@old_key THROW 51212,'Changed customer attributes did not create a new SCD2 row.',1;
    IF NOT EXISTS(SELECT 1 FROM gold.dim_customers WHERE customer_key=@old_key AND is_current=0 AND effective_end_date IS NOT NULL)
        THROW 51213,'Prior customer version was not expired.',1;
    IF (SELECT COUNT_BIG(*) FROM gold.dim_customers WHERE customer_id=@customer_id AND is_current=1)<>1
        THROW 51214,'Customer does not have exactly one current SCD2 version.',1;
    IF EXISTS(SELECT 1 FROM gold.fact_sales WHERE customer_id=@customer_id AND customer_key<>@new_key)
        THROW 51215,'Latest snapshot facts do not resolve to the current customer version.',1;
    ROLLBACK TRANSACTION;
    SELECT N'PASS' AS outcome,N'Existing keys remained stable; changed attributes created one current SCD2 version.' AS result;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
