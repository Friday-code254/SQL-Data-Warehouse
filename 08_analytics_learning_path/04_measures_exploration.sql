-- Business question: What are the main sales and customer measures in Gold?
-- Metric definitions: Sales and units sum accepted fact lines; orders are distinct order numbers.
-- Interpretation: Totals describe accepted rows in the latest loaded snapshot.
USE DataWarehouse;
GO

SELECT
    SUM(sales_amount) AS total_sales_amount,
    SUM(CONVERT(bigint, quantity)) AS total_units,
    AVG(price) AS average_line_price,
    COUNT_BIG(DISTINCT order_number) AS total_orders,
    COUNT_BIG(*) AS total_sales_lines
FROM gold.fact_sales;

SELECT
    (SELECT COUNT_BIG(*) FROM gold.dim_products WHERE is_current = 1 AND product_key <> 0) AS current_products,
    (SELECT COUNT_BIG(*) FROM gold.dim_customers WHERE is_current = 1 AND customer_key <> 0) AS current_customers,
    (SELECT COUNT_BIG(DISTINCT customer_id) FROM gold.fact_sales) AS customers_with_sales;
GO
