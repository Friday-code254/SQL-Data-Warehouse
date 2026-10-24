-- Business question: How can products and active customers be grouped for exploration?
-- Metric definitions: Product groups use current product cost; customer groups use accepted sales.
-- Interpretation: The 5,000 sales threshold is an example in source units, not a currency rule.
USE DataWarehouse;
GO

WITH product_segments AS (
    SELECT
        product_number,
        cost,
        CASE
            WHEN cost < 100 THEN N'Below 100'
            WHEN cost < 500 THEN N'100 to 499.99'
            WHEN cost < 1000 THEN N'500 to 999.99'
            ELSE N'1,000 and above'
        END AS cost_range
    FROM gold.dim_products
    WHERE is_current = 1 AND product_key <> 0 AND cost IS NOT NULL
)
SELECT cost_range, COUNT_BIG(*) AS product_count
FROM product_segments
GROUP BY cost_range
ORDER BY product_count DESC, cost_range;

WITH customer_activity AS (
    SELECT
        f.customer_id,
        SUM(f.sales_amount) AS total_sales,
        MIN(f.order_date) AS first_order_date,
        MAX(f.order_date) AS last_order_date
    FROM gold.fact_sales AS f
    GROUP BY f.customer_id
),
customer_segments AS (
    SELECT
        customer_id,
        CASE
            WHEN DATEDIFF(MONTH, first_order_date, last_order_date) + 1 < 12 THEN N'New'
            WHEN total_sales > 5000 THEN N'VIP'
            ELSE N'Regular'
        END AS customer_segment
    FROM customer_activity
)
SELECT customer_segment, COUNT_BIG(*) AS customer_count
FROM customer_segments
GROUP BY customer_segment
ORDER BY customer_count DESC, customer_segment;
GO
