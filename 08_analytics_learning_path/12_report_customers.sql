-- Business question: What sales activity has each current customer had in the snapshot?
-- Metric definitions: Orders are distinct order numbers; active months include first and last month.
-- Interpretation: This report includes customers with Gold sales and uses the current customer version.
USE DataWarehouse;
GO

CREATE OR ALTER VIEW gold.report_customers AS
WITH customer_activity AS (
    SELECT
        f.customer_key,
        f.customer_id,
        COUNT_BIG(DISTINCT f.order_number) AS total_orders,
        SUM(f.sales_amount) AS total_sales,
        SUM(CONVERT(bigint, f.quantity)) AS total_units,
        COUNT_BIG(DISTINCT f.product_number) AS distinct_products,
        MIN(f.order_date) AS first_order_date,
        MAX(f.order_date) AS last_order_date
    FROM gold.fact_sales AS f
    GROUP BY f.customer_key, f.customer_id
),
customer_metrics AS (
    SELECT
        a.*,
        DATEDIFF(MONTH, first_order_date, last_order_date) + 1 AS active_months,
        DATEDIFF(YEAR, c.birthdate, CONVERT(date, GETDATE())) AS approximate_age,
        c.customer_number,
        c.first_name,
        c.last_name,
        c.country,
        c.gender,
        c.marital_status
    FROM customer_activity AS a
    INNER JOIN gold.dim_customers AS c
        ON c.customer_key = a.customer_key AND c.is_current = 1
    WHERE c.customer_key <> 0
)
SELECT
    customer_id,
    customer_number,
    CONCAT(first_name, N' ', last_name) AS customer_name,
    country,
    gender,
    marital_status,
    approximate_age,
    CASE
        WHEN approximate_age IS NULL THEN N'Unknown'
        WHEN approximate_age < 20 THEN N'Under 20'
        WHEN approximate_age < 30 THEN N'20 to 29'
        WHEN approximate_age < 40 THEN N'30 to 39'
        WHEN approximate_age < 50 THEN N'40 to 49'
        ELSE N'50 and above'
    END AS age_group,
    CASE
        WHEN active_months < 12 THEN N'New'
        WHEN total_sales > 5000 THEN N'VIP'
        ELSE N'Regular'
    END AS customer_segment,
    first_order_date,
    last_order_date,
    DATEDIFF(MONTH, last_order_date, CONVERT(date, GETDATE())) AS months_since_last_order,
    total_orders,
    total_sales,
    total_units,
    distinct_products,
    active_months,
    CONVERT(decimal(18, 2), total_sales / NULLIF(total_orders * 1.0, 0)) AS average_order_value,
    CONVERT(decimal(18, 2), total_sales / NULLIF(active_months * 1.0, 0)) AS average_monthly_sales
FROM customer_metrics;
GO
