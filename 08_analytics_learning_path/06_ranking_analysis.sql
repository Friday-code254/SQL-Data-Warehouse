-- Business question: Which products and customers have the highest or lowest activity?
-- Metric definitions: Product sales sum accepted fact lines; orders count distinct order numbers.
-- Interpretation: The low-sales query includes current products with no sales as zero.
USE DataWarehouse;
GO

WITH product_sales AS (
    SELECT
        p.product_number,
        p.product_name,
        SUM(f.sales_amount) AS sales_amount
    FROM gold.fact_sales AS f
    INNER JOIN gold.dim_products AS p
        ON p.product_key = f.product_key AND p.is_current = 1
    GROUP BY p.product_number, p.product_name
)
SELECT product_number, product_name, sales_amount,
       DENSE_RANK() OVER (ORDER BY sales_amount DESC) AS sales_rank
FROM product_sales
WHERE sales_amount IS NOT NULL
ORDER BY sales_rank, product_number;

SELECT TOP (5)
    p.product_number,
    p.product_name,
    COALESCE(SUM(f.sales_amount), 0) AS sales_amount
FROM gold.dim_products AS p
LEFT JOIN gold.fact_sales AS f ON f.product_key = p.product_key
WHERE p.is_current = 1 AND p.product_key <> 0
GROUP BY p.product_number, p.product_name
ORDER BY sales_amount, p.product_number;

SELECT TOP (10)
    c.customer_id,
    c.first_name,
    c.last_name,
    SUM(f.sales_amount) AS sales_amount
FROM gold.fact_sales AS f
INNER JOIN gold.dim_customers AS c
    ON c.customer_key = f.customer_key AND c.is_current = 1
GROUP BY c.customer_id, c.first_name, c.last_name
ORDER BY sales_amount DESC, c.customer_id;

WITH customer_orders AS (
    SELECT c.customer_id, c.first_name, c.last_name,
           COUNT_BIG(DISTINCT f.order_number) AS order_count
    FROM gold.dim_customers AS c
    LEFT JOIN gold.fact_sales AS f ON f.customer_key = c.customer_key
    WHERE c.is_current = 1 AND c.customer_key <> 0
    GROUP BY c.customer_id, c.first_name, c.last_name
)
SELECT customer_id, first_name, last_name, order_count
FROM customer_orders
WHERE order_count = (SELECT MIN(order_count) FROM customer_orders)
ORDER BY customer_id;
GO
