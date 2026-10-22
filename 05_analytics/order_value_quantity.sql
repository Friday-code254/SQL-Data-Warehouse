-- Business question: What are monthly order count, average order value, and units sold?
-- Metric definitions: An order is distinct by customer, order number, and order date.
-- Average order value is order sales divided by order count. Units per order divides
-- accepted fact quantity by this same order count.
-- Interpretation: AOV is based on gross sales_amount and is not adjusted for refunds,
-- discounts, or cost because those fields are not present in the source model.
USE DataWarehouse;
GO

WITH customer_orders AS (
    SELECT
        f.customer_id,
        f.order_number,
        f.order_date,
        SUM(f.sales_amount) AS order_sales,
        SUM(CONVERT(bigint, f.quantity)) AS units_sold
    FROM gold.fact_sales AS f
    GROUP BY f.customer_id, f.order_number, f.order_date
),
monthly_orders AS (
    SELECT
        DATEFROMPARTS(YEAR(o.order_date), MONTH(o.order_date), 1) AS month_start,
        COUNT_BIG(*) AS order_count,
        SUM(o.order_sales) AS sales_amount,
        SUM(o.units_sold) AS units_sold
    FROM customer_orders AS o
    GROUP BY DATEFROMPARTS(YEAR(o.order_date), MONTH(o.order_date), 1)
)
SELECT
    month_start,
    order_count,
    sales_amount,
    units_sold,
    CONVERT(decimal(19, 2), sales_amount / NULLIF(order_count, 0)) AS average_order_value,
    CONVERT(decimal(19, 2), units_sold * 1.0 / NULLIF(order_count, 0)) AS average_units_per_order
FROM monthly_orders
ORDER BY month_start;
GO
