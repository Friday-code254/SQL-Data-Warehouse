-- Business question: How do sales vary by country and observable customer segments?
-- Metric definitions: A segment groups current customers by normalized country, marital
-- status (Married, Single, or Other/Unknown), and gender. An order is distinct by customer,
-- order number, and order date. Segment AOV is sales divided by observed orders.
-- Interpretation: Segment metrics are descriptive. They do not imply that demographics
-- cause purchasing behavior; customer counts include current customers with no sales.
USE DataWarehouse;
GO

WITH current_customers AS (
    SELECT
        c.customer_key,
        c.customer_id,
        COALESCE(NULLIF(LTRIM(RTRIM(c.country)), N''), N'Unknown') AS country,
        CASE
            WHEN c.marital_status IN (N'Married', N'Single') THEN c.marital_status
            ELSE N'Other/Unknown'
        END AS customer_segment,
        CASE
            WHEN c.gender IN (N'Female', N'Male') THEN c.gender
            ELSE N'Other/Unknown'
        END AS gender
    FROM gold.dim_customers AS c
    WHERE
        c.is_current = 1
        AND c.customer_id <> 0
),
segment_members AS (
    SELECT
        country,
        customer_segment,
        gender,
        COUNT_BIG(*) AS current_customers
    FROM current_customers
    GROUP BY country, customer_segment, gender
),
customer_orders AS (
    SELECT
        f.customer_key,
        f.customer_id,
        f.order_number,
        f.order_date,
        SUM(f.sales_amount) AS order_sales,
        COUNT_BIG(*) AS sales_lines
    FROM gold.fact_sales AS f
    GROUP BY f.customer_key, f.customer_id, f.order_number, f.order_date
),
segment_activity AS (
    SELECT
        c.country,
        c.customer_segment,
        c.gender,
        COUNT_BIG(DISTINCT c.customer_id) AS purchasing_customers,
        COUNT_BIG(*) AS order_count,
        SUM(o.order_sales) AS sales_amount,
        SUM(o.sales_lines) AS sales_lines
    FROM customer_orders AS o
    INNER JOIN current_customers AS c
        ON c.customer_key = o.customer_key
    GROUP BY c.country, c.customer_segment, c.gender
)
SELECT
    m.country,
    m.customer_segment,
    m.gender,
    m.current_customers,
    COALESCE(a.purchasing_customers, CONVERT(bigint, 0)) AS purchasing_customers,
    COALESCE(a.order_count, CONVERT(bigint, 0)) AS order_count,
    COALESCE(a.sales_lines, CONVERT(bigint, 0)) AS sales_lines,
    COALESCE(a.sales_amount, CONVERT(decimal(38, 4), 0)) AS sales_amount,
    CONVERT(decimal(19, 2), a.sales_amount / NULLIF(a.order_count, 0)) AS average_order_value,
    CONVERT(decimal(19, 2), a.sales_amount / NULLIF(m.current_customers, 0)) AS sales_per_current_customer
FROM segment_members AS m
LEFT JOIN segment_activity AS a
    ON
        a.country = m.country
        AND a.customer_segment = m.customer_segment
        AND a.gender = m.gender
ORDER BY sales_amount DESC, m.country, m.customer_segment, m.gender;
GO
