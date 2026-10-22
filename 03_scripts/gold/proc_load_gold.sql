/* Persistent dimensions with SCD Type 2 versions and a materialized fact snapshot. */
USE DataWarehouse;
GO
CREATE OR ALTER PROCEDURE gold.load_gold @run_id uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @started datetime2(3),@ended datetime2(3),@now datetime2(3)=SYSUTCDATETIME(),
            @source_rows bigint,@ins bigint,@upd bigint,@del bigint;
    DECLARE @actions table(action_name nvarchar(10));
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @last_effective datetime2(3);
        SELECT @last_effective=MAX(effective_start_date) FROM (
            SELECT effective_start_date FROM gold.dim_customers UNION ALL SELECT effective_start_date FROM gold.dim_products
        ) dimension_versions;
        IF @last_effective IS NOT NULL AND @last_effective>=@now SET @now=DATEADD(millisecond,1,@last_effective);

        /* Reserve key 0 as an explicit unknown member. */
        IF NOT EXISTS(SELECT 1 FROM gold.dim_customers WHERE customer_key=0)
        BEGIN
            SET IDENTITY_INSERT gold.dim_customers ON;
            INSERT gold.dim_customers(customer_key,customer_id,customer_number,first_name,last_name,country,marital_status,gender,birthdate,create_date,effective_start_date,effective_end_date,is_current,attribute_hash)
            VALUES(0,0,N'UNKNOWN',N'Unknown',N'Unknown',N'Unknown',N'n/a',N'n/a',NULL,NULL,CONVERT(datetime2(3),'19000101'),NULL,1,HASHBYTES('SHA2_256',N'UNKNOWN_CUSTOMER'));
            SET IDENTITY_INSERT gold.dim_customers OFF;
        END;
        IF NOT EXISTS(SELECT 1 FROM gold.dim_products WHERE product_key=0)
        BEGIN
            SET IDENTITY_INSERT gold.dim_products ON;
            INSERT gold.dim_products(product_key,product_id,product_number,product_name,category_id,category,subcategory,maintenance,cost,product_line,start_date,effective_start_date,effective_end_date,is_current,attribute_hash)
            VALUES(0,0,N'UNKNOWN',N'Unknown',N'UNKNOWN',N'Unknown',N'Unknown',N'Unknown',NULL,N'n/a',CONVERT(date,'19000101'),CONVERT(datetime2(3),'19000101'),NULL,1,HASHBYTES('SHA2_256',N'UNKNOWN_PRODUCT'));
            SET IDENTITY_INSERT gold.dim_products OFF;
        END;
        IF NOT EXISTS(SELECT 1 FROM gold.dim_date WHERE date_key=0)
            INSERT gold.dim_date(date_key,full_date,calendar_year,calendar_quarter,month_number,month_name,week_of_year,day_of_month,day_of_week,day_name,is_weekend)
            VALUES(0,CONVERT(date,'00010101'),0,0,0,N'Unknown',0,0,0,N'Unknown',0);

        /* Customer versions: attributes become effective when observed in a complete snapshot. */
        SET @started=SYSUTCDATETIME();
        SELECT ci.cst_id AS customer_id,ci.cst_key AS customer_number,ci.cst_firstname AS first_name,ci.cst_lastname AS last_name,
            la.cntry AS country,ci.cst_marital_status AS marital_status,
            CASE WHEN ci.cst_gndr<>N'n/a' THEN ci.cst_gndr ELSE COALESCE(ca.gen,N'n/a') END AS gender,
            ca.bdate AS birthdate,ci.cst_create_date AS create_date,
            HASHBYTES('SHA2_256',CONCAT_WS(CHAR(31),ci.cst_id,ci.cst_key,ci.cst_firstname,ci.cst_lastname,la.cntry,ci.cst_marital_status,
                CASE WHEN ci.cst_gndr<>N'n/a' THEN ci.cst_gndr ELSE COALESCE(ca.gen,N'n/a') END,ca.bdate,ci.cst_create_date)) AS attribute_hash
        INTO #customer_source
        FROM silver.crm_cust_info ci
        LEFT JOIN silver.erp_cust_az12 ca ON ca.cid=ci.cst_key
        LEFT JOIN silver.erp_loc_a101 la ON la.cid=ci.cst_key;
        UPDATE d SET is_current=0,effective_end_date=@now
        FROM gold.dim_customers d JOIN #customer_source s ON s.customer_id=d.customer_id
        WHERE d.is_current=1 AND d.customer_id<>0 AND d.attribute_hash<>s.attribute_hash;
        UPDATE d SET is_current=0,effective_end_date=@now
        FROM gold.dim_customers d WHERE d.is_current=1 AND d.customer_id<>0
          AND NOT EXISTS(SELECT 1 FROM #customer_source s WHERE s.customer_id=d.customer_id);
        INSERT gold.dim_customers(customer_id,customer_number,first_name,last_name,country,marital_status,gender,birthdate,create_date,effective_start_date,effective_end_date,is_current,attribute_hash)
        SELECT s.customer_id,s.customer_number,s.first_name,s.last_name,s.country,s.marital_status,s.gender,s.birthdate,s.create_date,@now,NULL,1,s.attribute_hash
        FROM #customer_source s WHERE NOT EXISTS(SELECT 1 FROM gold.dim_customers d WHERE d.customer_id=s.customer_id AND d.is_current=1);
        SELECT @source_rows=COUNT_BIG(*) FROM #customer_source; SET @ended=SYSUTCDATETIME();
        INSERT etl.table_load_logs(run_id,layer,table_name,started_at,ended_at,status,source_rows,inserted_rows,updated_rows,deleted_rows,rejected_rows,duration_ms)
        VALUES(@run_id,N'gold',N'dim_customers',@started,@ended,'SUCCEEDED',@source_rows,
            (SELECT COUNT_BIG(*) FROM gold.dim_customers WHERE is_current=1 AND effective_start_date=@now),
            (SELECT COUNT_BIG(*) FROM gold.dim_customers WHERE effective_end_date=@now),0,0,DATEDIFF_BIG(millisecond,@started,@ended));

        /* Current product attributes per business key; previous versions stay queryable. */
        SET @started=SYSUTCDATETIME();
        WITH ranked AS (
            SELECT p.*,c.cat,c.subcat,c.maintenance,
                ROW_NUMBER() OVER(PARTITION BY p.prd_key ORDER BY p.prd_start_dt DESC,p.prd_id DESC) AS rn
            FROM silver.crm_prd_info p LEFT JOIN silver.erp_px_cat_g1v2 c ON c.id=p.cat_id
        )
        SELECT prd_id AS product_id,prd_key AS product_number,prd_nm AS product_name,cat_id AS category_id,cat,subcat,maintenance,
            prd_cost AS cost,prd_line AS product_line,prd_start_dt AS start_date,
            HASHBYTES('SHA2_256',CONCAT_WS(CHAR(31),prd_id,prd_key,prd_nm,cat_id,cat,subcat,maintenance,prd_cost,prd_line,prd_start_dt)) AS attribute_hash
        INTO #product_source FROM ranked WHERE rn=1;
        UPDATE d SET is_current=0,effective_end_date=@now
        FROM gold.dim_products d JOIN #product_source s ON s.product_number=d.product_number
        WHERE d.is_current=1 AND d.product_key<>0 AND d.attribute_hash<>s.attribute_hash;
        UPDATE d SET is_current=0,effective_end_date=@now
        FROM gold.dim_products d WHERE d.is_current=1 AND d.product_key<>0
          AND NOT EXISTS(SELECT 1 FROM #product_source s WHERE s.product_number=d.product_number);
        INSERT gold.dim_products(product_id,product_number,product_name,category_id,category,subcategory,maintenance,cost,product_line,start_date,effective_start_date,effective_end_date,is_current,attribute_hash)
        SELECT s.product_id,s.product_number,s.product_name,s.category_id,s.cat,s.subcat,s.maintenance,s.cost,s.product_line,s.start_date,@now,NULL,1,s.attribute_hash
        FROM #product_source s WHERE NOT EXISTS(SELECT 1 FROM gold.dim_products d WHERE d.product_number=s.product_number AND d.is_current=1);
        SELECT @source_rows=COUNT_BIG(*) FROM #product_source; SET @ended=SYSUTCDATETIME();
        INSERT etl.table_load_logs(run_id,layer,table_name,started_at,ended_at,status,source_rows,inserted_rows,updated_rows,deleted_rows,rejected_rows,duration_ms)
        VALUES(@run_id,N'gold',N'dim_products',@started,@ended,'SUCCEEDED',@source_rows,
            (SELECT COUNT_BIG(*) FROM gold.dim_products WHERE is_current=1 AND effective_start_date=@now),
            (SELECT COUNT_BIG(*) FROM gold.dim_products WHERE effective_end_date=@now),0,0,DATEDIFF_BIG(millisecond,@started,@ended));

        /* Dense date dimension covering all order, ship and due dates in the current snapshot. */
        SET @started=SYSUTCDATETIME();
        DECLARE @min_date date,@max_date date;
        SELECT @min_date=MIN(d),@max_date=MAX(d) FROM (
            SELECT sls_order_dt AS d FROM silver.crm_sales_details UNION ALL
            SELECT sls_ship_dt FROM silver.crm_sales_details WHERE sls_ship_dt IS NOT NULL UNION ALL
            SELECT sls_due_dt FROM silver.crm_sales_details WHERE sls_due_dt IS NOT NULL
        ) dates;
        IF @min_date IS NOT NULL
        BEGIN
            ;WITH calendar AS (
                SELECT @min_date AS full_date
                UNION ALL SELECT DATEADD(day,1,full_date) FROM calendar WHERE full_date<@max_date
            )
            INSERT gold.dim_date(date_key,full_date,calendar_year,calendar_quarter,month_number,month_name,week_of_year,day_of_month,day_of_week,day_name,is_weekend)
            SELECT CONVERT(int,CONVERT(char(8),full_date,112)),full_date,YEAR(full_date),DATEPART(quarter,full_date),MONTH(full_date),
                CHOOSE(MONTH(full_date),N'January',N'February',N'March',N'April',N'May',N'June',N'July',N'August',N'September',N'October',N'November',N'December'),
                DATEPART(iso_week,full_date),DAY(full_date),((DATEDIFF(day,CONVERT(date,'19000101'),full_date)%7)+1),
                CHOOSE(((DATEDIFF(day,CONVERT(date,'19000101'),full_date)%7)+1),N'Monday',N'Tuesday',N'Wednesday',N'Thursday',N'Friday',N'Saturday',N'Sunday'),
                IIF(((DATEDIFF(day,CONVERT(date,'19000101'),full_date)%7)+1)>=6,1,0)
            FROM calendar c WHERE NOT EXISTS(SELECT 1 FROM gold.dim_date d WHERE d.full_date=c.full_date)
            OPTION(MAXRECURSION 0);
        END;
        SET @ended=SYSUTCDATETIME();
        INSERT etl.table_load_logs(run_id,layer,table_name,started_at,ended_at,status,source_rows,inserted_rows,updated_rows,deleted_rows,rejected_rows,duration_ms)
        VALUES(@run_id,N'gold',N'dim_date',@started,@ended,'SUCCEEDED',COALESCE(DATEDIFF(day,@min_date,@max_date)+1,0),
            (SELECT COUNT_BIG(*) FROM gold.dim_date WHERE date_key<>0 AND full_date BETWEEN @min_date AND @max_date),0,0,0,DATEDIFF_BIG(millisecond,@started,@ended));

        /* Documented policy: facts in this latest-snapshot warehouse resolve to the current
           dimension version observed in the same run. Source change timestamps are absent. */
        SET @started=SYSUTCDATETIME();
        SELECT s.sales_row_hash,s.sls_ord_num,s.sls_prd_key,s.sls_cust_id,s.sls_order_dt,s.sls_ship_dt,s.sls_due_dt,s.sls_sales,s.sls_quantity,s.sls_price,s.correction_code,
            p.product_id,p.product_number,p.product_key,c.customer_key,
            COALESCE(CONVERT(int,CONVERT(char(8),s.sls_order_dt,112)),0) AS order_date_key,
            COALESCE(CONVERT(int,CONVERT(char(8),s.sls_ship_dt,112)),0) AS shipping_date_key,
            COALESCE(CONVERT(int,CONVERT(char(8),s.sls_due_dt,112)),0) AS due_date_key
        INTO #fact_source
        FROM silver.crm_sales_details s
        LEFT JOIN gold.dim_products p ON p.product_number=s.sls_prd_key AND p.is_current=1
        LEFT JOIN gold.dim_customers c ON c.customer_id=s.sls_cust_id AND c.is_current=1;
        INSERT etl.rejected_records(run_id,source_key,entity_name,source_record_hash,reason_code,reason_detail)
        SELECT @run_id,N'crm_sales_details',N'sales_line',sales_row_hash,
            CASE WHEN product_id IS NULL THEN N'UNMATCHED_PRODUCT_DIMENSION' ELSE N'UNMATCHED_CUSTOMER_DIMENSION' END,
            N'Fact row is excluded from Gold because a current dimension business key was not found.'
        FROM #fact_source WHERE product_id IS NULL OR customer_key IS NULL;
        SELECT * INTO #fact FROM #fact_source WHERE product_id IS NOT NULL AND customer_key IS NOT NULL;
        SELECT @source_rows=COUNT_BIG(*) FROM #fact_source;
        DELETE @actions;
        MERGE gold.fact_sales AS t USING #fact AS s
          ON t.order_number=s.sls_ord_num AND t.product_number=s.product_number AND t.customer_id=s.sls_cust_id AND t.order_date=s.sls_order_dt
        WHEN MATCHED AND (t.source_line_hash<>s.sales_row_hash OR t.sales_amount<>s.sls_sales OR t.price<>s.sls_price OR t.quantity<>s.sls_quantity OR t.customer_key<>s.customer_key OR t.product_key<>s.product_key OR ISNULL(t.correction_code,N'')<>ISNULL(s.correction_code,N''))
            THEN UPDATE SET product_id=s.product_id,product_key=s.product_key,customer_key=s.customer_key,order_date_key=s.order_date_key,shipping_date_key=s.shipping_date_key,due_date_key=s.due_date_key,
                shipping_date=s.sls_ship_dt,due_date=s.sls_due_dt,sales_amount=s.sls_sales,quantity=s.sls_quantity,price=s.sls_price,correction_code=s.correction_code,source_line_hash=s.sales_row_hash,loaded_at=SYSUTCDATETIME()
        WHEN NOT MATCHED BY TARGET THEN INSERT(order_number,product_id,product_number,customer_id,product_key,customer_key,order_date_key,shipping_date_key,due_date_key,order_date,shipping_date,due_date,sales_amount,quantity,price,correction_code,source_line_hash)
            VALUES(s.sls_ord_num,s.product_id,s.product_number,s.sls_cust_id,s.product_key,s.customer_key,s.order_date_key,s.shipping_date_key,s.due_date_key,s.sls_order_dt,s.sls_ship_dt,s.sls_due_dt,s.sls_sales,s.sls_quantity,s.sls_price,s.correction_code,s.sales_row_hash)
        WHEN NOT MATCHED BY SOURCE THEN DELETE
        OUTPUT $action INTO @actions;
        SELECT @ins=COUNT_BIG(*) FROM @actions WHERE action_name=N'INSERT'; SELECT @upd=COUNT_BIG(*) FROM @actions WHERE action_name=N'UPDATE'; SELECT @del=COUNT_BIG(*) FROM @actions WHERE action_name=N'DELETE';
        SET @ended=SYSUTCDATETIME();
        INSERT etl.table_load_logs(run_id,layer,table_name,started_at,ended_at,status,source_rows,inserted_rows,updated_rows,deleted_rows,rejected_rows,duration_ms)
        VALUES(@run_id,N'gold',N'fact_sales',@started,@ended,'SUCCEEDED',@source_rows,@ins,@upd,@del,
            (SELECT COUNT_BIG(*) FROM etl.rejected_records WHERE run_id=@run_id AND entity_name=N'sales_line'),DATEDIFF_BIG(millisecond,@started,@ended));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
