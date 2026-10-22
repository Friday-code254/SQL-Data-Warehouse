/*
  Run from the repository root against a disposable development database.
  Reapplies the full SQLCMD install and verifies that data and dimension keys remain stable.
*/
USE DataWarehouse;
GO
SELECT N'bronze.crm_sales_details' AS metric_name,COUNT_BIG(*) AS row_count INTO #before_counts FROM bronze.crm_sales_details
UNION ALL SELECT N'silver.crm_sales_details',COUNT_BIG(*) FROM silver.crm_sales_details
UNION ALL SELECT N'gold.fact_sales',COUNT_BIG(*) FROM gold.fact_sales
UNION ALL SELECT N'gold.dim_customers',COUNT_BIG(*) FROM gold.dim_customers
UNION ALL SELECT N'gold.dim_products',COUNT_BIG(*) FROM gold.dim_products;
SELECT customer_id,customer_key INTO #before_customer_keys
FROM gold.dim_customers WHERE is_current=1 AND customer_id<>0;
SELECT product_number,product_key INTO #before_product_keys
FROM gold.dim_products WHERE is_current=1 AND product_key<>0;
GO
:r 00_setup/install.sql
GO
USE DataWarehouse;
GO
IF EXISTS (
    SELECT metric_name,row_count FROM #before_counts
    EXCEPT
    SELECT metric_name,row_count FROM (
        SELECT N'bronze.crm_sales_details' AS metric_name,COUNT_BIG(*) AS row_count FROM bronze.crm_sales_details
        UNION ALL SELECT N'silver.crm_sales_details',COUNT_BIG(*) FROM silver.crm_sales_details
        UNION ALL SELECT N'gold.fact_sales',COUNT_BIG(*) FROM gold.fact_sales
        UNION ALL SELECT N'gold.dim_customers',COUNT_BIG(*) FROM gold.dim_customers
        UNION ALL SELECT N'gold.dim_products',COUNT_BIG(*) FROM gold.dim_products
    ) after_install
) OR EXISTS (
    SELECT metric_name,row_count FROM (
        SELECT N'bronze.crm_sales_details' AS metric_name,COUNT_BIG(*) AS row_count FROM bronze.crm_sales_details
        UNION ALL SELECT N'silver.crm_sales_details',COUNT_BIG(*) FROM silver.crm_sales_details
        UNION ALL SELECT N'gold.fact_sales',COUNT_BIG(*) FROM gold.fact_sales
        UNION ALL SELECT N'gold.dim_customers',COUNT_BIG(*) FROM gold.dim_customers
        UNION ALL SELECT N'gold.dim_products',COUNT_BIG(*) FROM gold.dim_products
    ) after_install
    EXCEPT
    SELECT metric_name,row_count FROM #before_counts
)
    THROW 51240,'Repeated installation changed warehouse row counts.',1;

IF EXISTS (
    SELECT customer_id,customer_key FROM #before_customer_keys
    EXCEPT
    SELECT customer_id,customer_key FROM gold.dim_customers WHERE is_current=1 AND customer_id<>0
) OR EXISTS (
    SELECT customer_id,customer_key FROM gold.dim_customers WHERE is_current=1 AND customer_id<>0
    EXCEPT
    SELECT customer_id,customer_key FROM #before_customer_keys
)
    THROW 51241,'Repeated installation changed current customer surrogate keys.',1;

IF EXISTS (
    SELECT product_number,product_key FROM #before_product_keys
    EXCEPT
    SELECT product_number,product_key FROM gold.dim_products WHERE is_current=1 AND product_key<>0
) OR EXISTS (
    SELECT product_number,product_key FROM gold.dim_products WHERE is_current=1 AND product_key<>0
    EXCEPT
    SELECT product_number,product_key FROM #before_product_keys
)
    THROW 51242,'Repeated installation changed current product surrogate keys.',1;

SELECT N'PASS' AS outcome,N'Install preserved warehouse rows and dimension surrogate keys.' AS result;
DROP TABLE #before_counts;
DROP TABLE #before_customer_keys;
DROP TABLE #before_product_keys;
GO
