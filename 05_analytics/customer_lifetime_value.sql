-- Business question: How often does each current customer order and how much have they spent?
-- Metric definitions: An order is distinct by customer, order number, and order date.
-- Lifetime sales sum accepted Gold line sales. Active months include both the first and
-- last order month; orders per active month divides order count by that inclusive span.
-- Interpretation: The source snapshots do not provide complete customer tenure, so this
-- is observed warehouse lifetime sales, not a forecast or customer profitability measure.
USE DataWarehouse;
GO

WITH customer_orders AS (
    SELECT
        f.customer_key,
        f.customer_id,
        f.order_number,
        f.order_date,
        SUM(f.sales_amount) AS order_sales
    FROM gold.fact_sales AS f
    GROUP BY f.customer_key, f.customer_id, f.order_number, f.order_date
),
customer_totals AS (
    SELECT
        customer_key,
        customer_id,
        COUNT_BIG(*) AS order_count,
        SUM(order_sales) AS lifetime_sales,
        MIN(order_date) AS first_order_date,
        MAX(order_date) AS last_order_date
    FROM customer_orders
    GROUP BY customer_key, customer_id
)
SELECT
    c.customer_id,
    c.customer_number,
    c.first_name,
    c.last_name,
    c.country,
    t.order_count,
    t.lifetime_sales,
    t.first_order_date,
    t.last_order_date,
    DATEDIFF(MONTH, t.first_order_date, t.last_order_date) + 1 AS active_months,
    CONVERT(
        decimal(18, 2),
        t.order_count * 1.0 / NULLIF(DATEDIFF(MONTH, t.first_order_date, t.last_order_date) + 1, 0)
    ) AS orders_per_active_month
FROM customer_totals AS t
INNER JOIN gold.dim_customers AS c
    ON
        c.customer_key = t.customer_key
        AND c.is_current = 1
ORDER BY t.lifetime_sales DESC, c.customer_id;
GO
