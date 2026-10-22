/*
  Stage every file before persisting any row. Bronze is append-only by content
  hash; a repeated file is linked to its original batch and never duplicated.
  Files must be readable by the SQL Server service account.
*/
USE DataWarehouse;
GO
CREATE OR ALTER PROCEDURE bronze.load_bronze
    @run_id uniqueidentifier,
    @dataset_root nvarchar(2048),
    @manifest_json nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @started datetime2(3)=SYSUTCDATETIME(), @ended datetime2(3),
            @sql nvarchar(max), @path nvarchar(2048), @quoted_path nvarchar(max), @source_key sysname,
            @file_name nvarchar(260), @hash char(64), @rows bigint, @size bigint,
            @header nvarchar(1000), @expected_rows bigint, @batch_id uniqueidentifier,
            @temp_table sysname,
            @was_replay bit, @separator nchar(1), @codepage_option nvarchar(32),
            @line_terminator nvarchar(4),
            @bulk_path nvarchar(2048), @quoted_bulk_path nvarchar(max),
            @bulk_relative_path nvarchar(260), @bulk_hash char(64), @bulk_size bigint,
            @is_linux bit,
            @actual_hash char(64), @actual_size bigint, @row_error nvarchar(2048);
    SET @separator = CASE WHEN LEFT(@dataset_root,1)=N'/' THEN N'/' ELSE N'\' END;
    SET @is_linux=IIF(@@VERSION LIKE N'%Linux%',1,0);
    SET @codepage_option=CASE WHEN @is_linux=1 THEN N'' ELSE N', CODEPAGE=''65001''' END;

    CREATE TABLE #manifest (
        source_key sysname NOT NULL PRIMARY KEY, relative_path nvarchar(260) NOT NULL,
        file_name nvarchar(260) NOT NULL, sha256 char(64) NOT NULL,
        file_size bigint NOT NULL, row_count bigint NOT NULL, column_count tinyint NOT NULL,
        line_terminator nvarchar(4) NOT NULL, header nvarchar(1000) NOT NULL,
        bulk_relative_path nvarchar(260) NULL, bulk_sha256 char(64) NULL, bulk_file_size bigint NULL
    );
    INSERT #manifest(source_key,relative_path,file_name,sha256,file_size,row_count,column_count,line_terminator,header,
        bulk_relative_path,bulk_sha256,bulk_file_size)
    SELECT source_key,relative_path,file_name,UPPER(sha256),file_size,row_count,column_count,line_terminator,header,
        bulk_relative_path,UPPER(bulk_sha256),bulk_file_size
    FROM OPENJSON(@manifest_json) WITH (
        source_key sysname '$.source_key', relative_path nvarchar(260) '$.relative_path',
        file_name nvarchar(260) '$.file_name', sha256 char(64) '$.sha256',
        file_size bigint '$.file_size', row_count bigint '$.row_count', column_count tinyint '$.column_count',
        line_terminator nvarchar(4) '$.line_terminator', header nvarchar(1000) '$.header',
        bulk_relative_path nvarchar(260) '$.bulk_relative_path', bulk_sha256 char(64) '$.bulk_sha256',
        bulk_file_size bigint '$.bulk_file_size'
    );

    IF (SELECT COUNT(*) FROM #manifest) <> (SELECT COUNT(*) FROM etl.source_config WHERE is_required=1)
        THROW 51101, 'Source manifest does not contain every required source file.', 1;
    IF EXISTS (
        SELECT 1 FROM etl.source_config c
        LEFT JOIN #manifest m ON m.source_key=c.source_key
        WHERE c.is_required=1 AND (m.source_key IS NULL OR m.header<>c.expected_header OR m.column_count<>c.expected_columns
            OR REPLACE(m.relative_path,N'/',N'\')<>REPLACE(c.relative_path,N'/',N'\') OR m.file_size<=0 OR m.row_count<=0
            OR m.line_terminator NOT IN(N'CRLF',N'LF') OR LEN(m.sha256)<>64 OR m.sha256 LIKE '%[^0-9A-F]%')
    ) THROW 51102, 'Source manifest failed header, path, or metadata validation.', 1;
    IF @is_linux=1 AND EXISTS (
        SELECT 1 FROM #manifest m
        WHERE m.bulk_relative_path IS NULL
           OR REPLACE(m.bulk_relative_path,N'/',N'\') NOT LIKE N'.sql_bulk_stage\%'
           OR REPLACE(m.bulk_relative_path,N'/',N'\') LIKE N'%\..\%'
           OR REPLACE(m.bulk_relative_path,N'/',N'\') LIKE N'%\..'
           OR m.bulk_file_size<=0 OR LEN(m.bulk_sha256)<>64 OR m.bulk_sha256 LIKE '%[^0-9A-F]%'
    ) THROW 51106, 'Linux bulk manifest is missing a valid prepared UTF-16 file.', 1;

    CREATE TABLE #cust (cst_id nvarchar(4000),cst_key nvarchar(4000),cst_firstname nvarchar(4000),cst_lastname nvarchar(4000),cst_marital_status nvarchar(4000),cst_gndr nvarchar(4000),cst_create_date nvarchar(4000));
    CREATE TABLE #prd (prd_id nvarchar(4000),prd_key nvarchar(4000),prd_nm nvarchar(4000),prd_cost nvarchar(4000),prd_line nvarchar(4000),prd_start_dt nvarchar(4000),prd_end_dt nvarchar(4000));
    CREATE TABLE #sales (sls_ord_num nvarchar(4000),sls_prd_key nvarchar(4000),sls_cust_id nvarchar(4000),sls_order_dt nvarchar(4000),sls_ship_dt nvarchar(4000),sls_due_dt nvarchar(4000),sls_sales nvarchar(4000),sls_quantity nvarchar(4000),sls_price nvarchar(4000));
    CREATE TABLE #loc (cid nvarchar(4000),cntry nvarchar(4000));
    CREATE TABLE #erp_cust (cid nvarchar(4000),bdate nvarchar(4000),gen nvarchar(4000));
    CREATE TABLE #cat (id nvarchar(4000),cat nvarchar(4000),subcat nvarchar(4000),maintenance nvarchar(4000));

    /* BULK INSERT reads into temporary staging tables first: no prior batch is touched. */
    DECLARE @loads table(source_key sysname, temp_table sysname);
    INSERT @loads VALUES (N'crm_cust_info',N'#cust'),(N'crm_prd_info',N'#prd'),(N'crm_sales_details',N'#sales'),
        (N'erp_loc_a101',N'#loc'),(N'erp_cust_az12',N'#erp_cust'),(N'erp_px_cat_g1v2',N'#cat');
    DECLARE load_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT source_key,temp_table FROM @loads;
    OPEN load_cursor;
    FETCH NEXT FROM load_cursor INTO @source_key,@temp_table;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SELECT @path=CONCAT(@dataset_root,CASE WHEN RIGHT(@dataset_root,1) IN (N'/',N'\') THEN N'' ELSE @separator END,
            REPLACE(c.relative_path,N'\',@separator)), @file_name=m.file_name,
            @hash=m.sha256, @expected_rows=m.row_count, @size=m.file_size,
            @line_terminator=m.line_terminator, @bulk_relative_path=m.bulk_relative_path,
            @bulk_hash=m.bulk_sha256, @bulk_size=m.bulk_file_size
        FROM etl.source_config c JOIN #manifest m ON m.source_key=c.source_key WHERE c.source_key=@source_key;
        SET @actual_hash=NULL; SET @actual_size=NULL;
        SET @quoted_path=NCHAR(39)+REPLACE(@path,NCHAR(39),NCHAR(39)+NCHAR(39))+NCHAR(39);
        SET @sql=N'SELECT @digest=CONVERT(char(64),HASHBYTES(''SHA2_256'',BulkColumn),2),@bytes=DATALENGTH(BulkColumn) FROM OPENROWSET(BULK '+@quoted_path+N',SINGLE_BLOB) AS source_file;';
        EXEC sys.sp_executesql @sql,N'@digest char(64) OUTPUT,@bytes bigint OUTPUT',@digest=@actual_hash OUTPUT,@bytes=@actual_size OUTPUT;
        IF @actual_hash<>@hash OR @actual_size<>@size THROW 51104, 'Source file changed after local preflight or its checksum did not match.', 1;
        IF @is_linux=1
        BEGIN
            SET @bulk_path=CONCAT(@dataset_root,CASE WHEN RIGHT(@dataset_root,1) IN (N'/',N'\') THEN N'' ELSE @separator END,
                REPLACE(@bulk_relative_path,N'\',@separator));
            SET @quoted_bulk_path=NCHAR(39)+REPLACE(@bulk_path,NCHAR(39),NCHAR(39)+NCHAR(39))+NCHAR(39);
            SET @actual_hash=NULL; SET @actual_size=NULL;
            SET @sql=N'SELECT @digest=CONVERT(char(64),HASHBYTES(''SHA2_256'',BulkColumn),2),@bytes=DATALENGTH(BulkColumn) FROM OPENROWSET(BULK '+@quoted_bulk_path+N',SINGLE_BLOB) AS source_file;';
            EXEC sys.sp_executesql @sql,N'@digest char(64) OUTPUT,@bytes bigint OUTPUT',@digest=@actual_hash OUTPUT,@bytes=@actual_size OUTPUT;
            IF @actual_hash<>@bulk_hash OR @actual_size<>@bulk_size
                THROW 51105, 'Prepared Linux UTF-16 bulk file changed after local validation.', 1;
            SET @sql=N'BULK INSERT '+QUOTENAME(@temp_table)+N' FROM '+@quoted_bulk_path+
                N' WITH (FORMAT=''CSV'', DATAFILETYPE=''widechar'', FIRSTROW=2, ROWTERMINATOR=''0x0d000a00'', FIELDQUOTE=''"'', TABLOCK);';
        END
        ELSE
            SET @sql=N'BULK INSERT '+QUOTENAME(@temp_table)+N' FROM '+@quoted_path+
                N' WITH (FORMAT=''CSV'', FIRSTROW=2'+@codepage_option+
                CASE WHEN @line_terminator=N'CRLF' THEN N', ROWTERMINATOR=''0x0d0a''' ELSE N', ROWTERMINATOR=''0x0a''' END+
                N', FIELDQUOTE=''"'', TABLOCK);';
        EXEC sys.sp_executesql @sql;
        SET @rows=CASE @source_key
            WHEN N'crm_cust_info' THEN (SELECT COUNT_BIG(*) FROM #cust)
            WHEN N'crm_prd_info' THEN (SELECT COUNT_BIG(*) FROM #prd)
            WHEN N'crm_sales_details' THEN (SELECT COUNT_BIG(*) FROM #sales)
            WHEN N'erp_loc_a101' THEN (SELECT COUNT_BIG(*) FROM #loc)
            WHEN N'erp_cust_az12' THEN (SELECT COUNT_BIG(*) FROM #erp_cust)
            ELSE (SELECT COUNT_BIG(*) FROM #cat) END;
        IF @rows<>@expected_rows
        BEGIN
            SET @row_error=CONCAT(N'SQL Server read ',@rows,N' rows from ',@source_key,
                N'; the validated manifest expected ',@expected_rows,N'.');
            THROW 51103, @row_error, 1;
        END;
        FETCH NEXT FROM load_cursor INTO @source_key,@temp_table;
    END
    CLOSE load_cursor;
    DEALLOCATE load_cursor;

    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE source_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT source_key FROM @loads;
        OPEN source_cursor;
        FETCH NEXT FROM source_cursor INTO @source_key;
        WHILE @@FETCH_STATUS=0
        BEGIN
            SET @started=SYSUTCDATETIME();
            SELECT @file_name=m.file_name,@hash=m.sha256,@size=m.file_size,@expected_rows=m.row_count
            FROM #manifest m WHERE m.source_key=@source_key;
            SELECT @batch_id=h.source_batch_id FROM etl.source_file_history h WHERE h.source_key=@source_key AND h.file_sha256=@hash;
            SET @was_replay=IIF(@batch_id IS NULL,0,1);
            IF @batch_id IS NULL
            BEGIN
                SET @batch_id=@run_id;
                IF @source_key=N'crm_cust_info'
                    INSERT bronze.crm_cust_info SELECT *,@batch_id,@file_name,@hash,SYSUTCDATETIME(),HASHBYTES('SHA2_256',CONCAT_WS(CHAR(31),cst_id,cst_key,cst_firstname,cst_lastname,cst_marital_status,cst_gndr,cst_create_date)) FROM #cust;
                ELSE IF @source_key=N'crm_prd_info'
                    INSERT bronze.crm_prd_info SELECT *,@batch_id,@file_name,@hash,SYSUTCDATETIME(),HASHBYTES('SHA2_256',CONCAT_WS(CHAR(31),prd_id,prd_key,prd_nm,prd_cost,prd_line,prd_start_dt,prd_end_dt)) FROM #prd;
                ELSE IF @source_key=N'crm_sales_details'
                    INSERT bronze.crm_sales_details SELECT *,@batch_id,@file_name,@hash,SYSUTCDATETIME(),HASHBYTES('SHA2_256',CONCAT_WS(CHAR(31),sls_ord_num,sls_prd_key,sls_cust_id,sls_order_dt,sls_ship_dt,sls_due_dt,sls_sales,sls_quantity,sls_price)) FROM #sales;
                ELSE IF @source_key=N'erp_loc_a101'
                    INSERT bronze.erp_loc_a101 SELECT *,@batch_id,@file_name,@hash,SYSUTCDATETIME(),HASHBYTES('SHA2_256',CONCAT_WS(CHAR(31),cid,cntry)) FROM #loc;
                ELSE IF @source_key=N'erp_cust_az12'
                    INSERT bronze.erp_cust_az12 SELECT *,@batch_id,@file_name,@hash,SYSUTCDATETIME(),HASHBYTES('SHA2_256',CONCAT_WS(CHAR(31),cid,bdate,gen)) FROM #erp_cust;
                ELSE
                    INSERT bronze.erp_px_cat_g1v2 SELECT *,@batch_id,@file_name,@hash,SYSUTCDATETIME(),HASHBYTES('SHA2_256',CONCAT_WS(CHAR(31),id,cat,subcat,maintenance)) FROM #cat;
                INSERT etl.source_file_history(source_key,file_sha256,source_batch_id,file_name,file_size_bytes,source_rows)
                    VALUES(@source_key,@hash,@batch_id,@file_name,@size,@expected_rows);
            END
            INSERT etl.pipeline_source_files(run_id,source_key,file_sha256,file_name,file_size_bytes,source_rows,source_batch_id,was_replay)
                VALUES(@run_id,@source_key,@hash,@file_name,@size,@expected_rows,@batch_id,@was_replay);
            SET @ended=SYSUTCDATETIME();
            INSERT etl.table_load_logs(run_id,layer,table_name,started_at,ended_at,status,source_rows,inserted_rows,updated_rows,deleted_rows,rejected_rows,duration_ms)
            VALUES(@run_id,N'bronze',@source_key,@started,@ended,'SUCCEEDED',@expected_rows,IIF(@was_replay=1,0,@expected_rows),0,0,0,DATEDIFF_BIG(millisecond,@started,@ended));
            SET @batch_id=NULL;
            FETCH NEXT FROM source_cursor INTO @source_key;
        END
        CLOSE source_cursor;
        DEALLOCATE source_cursor;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local','source_cursor')>=0 CLOSE source_cursor;
        IF CURSOR_STATUS('local','source_cursor')>-3 DEALLOCATE source_cursor;
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
