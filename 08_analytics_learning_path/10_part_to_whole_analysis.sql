-- Business question: What share of accepted sales comes from each product category?
-- Metric definitions: Category sales are divided by total Gold sales and shown as a percentage.
-- Interpretation: The result shows revenue mix, not profit or product margin.
USE DataWarehouse;
GO

WITH category_sales AS (
    SELECT
        COALESCE(p.category, N'Unknown') AS category,
        SUM(f.sales_amount) AS sales_amount
    FROM gold.fact_sales AS f
    LEFT JOIN gold.dim_products AS p
        ON p.product_key = f.product_key AND p.is_current = 1
    GROUP BY COALESCE(p.category, N'Unknown')
)
SELECT
    category,
    sales_amount,
    SUM(sales_amount) OVER () AS total_sales,
    CONVERT(decimal(9, 2), 100.0 * sales_amount / NULLIF(SUM(sales_amount) OVER (), 0)) AS percent_of_sales
FROM category_sales
ORDER BY sales_amount DESC, category;
GO
