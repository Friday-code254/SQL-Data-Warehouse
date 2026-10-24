-- Business question: What sales activity has each current product had in the snapshot?
-- Metric definitions: Orders and customers are distinct; average unit sales is total sales divided by units.
-- Interpretation: Revenue bands use source amount units and are examples, not profit categories.
USE DataWarehouse;
GO

CREATE OR ALTER VIEW gold.report_products AS
WITH product_activity AS (
    SELECT
        f.product_key,
        COUNT_BIG(DISTINCT f.order_number) AS total_orders,
        COUNT_BIG(DISTINCT f.customer_id) AS total_customers,
        SUM(f.sales_amount) AS total_sales,
        SUM(CONVERT(bigint, f.quantity)) AS total_units,
        MIN(f.order_date) AS first_sale_date,
        MAX(f.order_date) AS last_sale_date
    FROM gold.fact_sales AS f
    GROUP BY f.product_key
)
SELECT
    p.product_id,
    p.product_key,
    p.product_number,
    p.product_name,
    p.category,
    p.subcategory,
    p.cost,
    a.first_sale_date,
    a.last_sale_date,
    CASE
        WHEN a.last_sale_date IS NULL THEN NULL
        ELSE DATEDIFF(MONTH, a.last_sale_date, CONVERT(date, GETDATE()))
    END AS months_since_last_sale,
    CASE
        WHEN COALESCE(a.total_sales, 0) >= 50000 THEN N'High sales'
        WHEN COALESCE(a.total_sales, 0) >= 10000 THEN N'Mid-range sales'
        ELSE N'Lower sales'
    END AS sales_segment,
    CASE
        WHEN a.first_sale_date IS NULL THEN 0
        ELSE DATEDIFF(MONTH, a.first_sale_date, a.last_sale_date) + 1
    END AS active_months,
    COALESCE(a.total_orders, 0) AS total_orders,
    COALESCE(a.total_sales, 0) AS total_sales,
    COALESCE(a.total_units, 0) AS total_units,
    COALESCE(a.total_customers, 0) AS total_customers,
    CONVERT(decimal(18, 2), a.total_sales / NULLIF(a.total_units * 1.0, 0)) AS average_sales_per_unit,
    CONVERT(decimal(18, 2), a.total_sales / NULLIF(a.total_orders * 1.0, 0)) AS average_sales_per_order,
    CASE
        WHEN a.first_sale_date IS NULL THEN 0
        ELSE CONVERT(decimal(18, 2), a.total_sales / NULLIF((DATEDIFF(MONTH, a.first_sale_date, a.last_sale_date) + 1) * 1.0, 0))
    END AS average_monthly_sales
FROM gold.dim_products AS p
LEFT JOIN product_activity AS a ON a.product_key = p.product_key
WHERE p.is_current = 1 AND p.product_key <> 0;
GO
