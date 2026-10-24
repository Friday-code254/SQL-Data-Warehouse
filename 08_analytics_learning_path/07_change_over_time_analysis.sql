-- Business question: How do sales, customers, and units change month by month?
-- Metric definitions: Sales and units sum accepted fact lines; customers are distinct IDs.
-- Interpretation: This describes the latest snapshot and does not adjust for seasonality.
USE DataWarehouse;
GO

SELECT
    DATEFROMPARTS(YEAR(order_date), MONTH(order_date), 1) AS month_start,
    SUM(sales_amount) AS sales_amount,
    COUNT_BIG(DISTINCT customer_id) AS customers,
    SUM(CONVERT(bigint, quantity)) AS units_sold
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATEFROMPARTS(YEAR(order_date), MONTH(order_date), 1)
ORDER BY month_start;
GO
