-- Business question: Which products and categories contribute the most sales?
-- Metric definitions: Product sales and units sum accepted fact lines joined to the
-- current product version. Category results roll up the same product-level totals.
-- Interpretation: These are sales totals, not profit; product cost is not subtracted.
USE DataWarehouse;
GO

WITH product_sales AS (
    SELECT
        p.product_key,
        p.product_number,
        p.product_name,
        p.category,
        p.subcategory,
        SUM(f.sales_amount) AS sales_amount,
        SUM(CONVERT(bigint, f.quantity)) AS units_sold,
        COUNT_BIG(*) AS sales_lines
    FROM gold.fact_sales AS f
    INNER JOIN gold.dim_products AS p
        ON
            p.product_key = f.product_key
            AND p.is_current = 1
    GROUP BY
        p.product_key,
        p.product_number,
        p.product_name,
        p.category,
        p.subcategory
)
SELECT TOP (20)
    DENSE_RANK() OVER (ORDER BY sales_amount DESC) AS sales_rank,
    product_number,
    product_name,
    category,
    subcategory,
    sales_amount,
    units_sold,
    sales_lines
FROM product_sales
ORDER BY sales_amount DESC, product_number;

WITH category_sales AS (
    SELECT
        COALESCE(category, N'Unknown') AS category,
        COALESCE(subcategory, N'Unknown') AS subcategory,
        COUNT_BIG(*) AS products_sold,
        SUM(sales_amount) AS sales_amount,
        SUM(units_sold) AS units_sold,
        SUM(sales_lines) AS sales_lines
    FROM (
        SELECT
            p.product_key,
            p.category,
            p.subcategory,
            SUM(f.sales_amount) AS sales_amount,
            SUM(CONVERT(bigint, f.quantity)) AS units_sold,
            COUNT_BIG(*) AS sales_lines
        FROM gold.fact_sales AS f
        INNER JOIN gold.dim_products AS p
            ON
                p.product_key = f.product_key
                AND p.is_current = 1
        GROUP BY p.product_key, p.category, p.subcategory
    ) AS product_totals
    GROUP BY COALESCE(category, N'Unknown'), COALESCE(subcategory, N'Unknown')
)
SELECT TOP (20)
    DENSE_RANK() OVER (ORDER BY sales_amount DESC) AS sales_rank,
    category,
    subcategory,
    products_sold,
    sales_amount,
    units_sold,
    sales_lines
FROM category_sales
ORDER BY sales_amount DESC, category, subcategory;
GO
