-- Business question: How do sales and average prices build up over time?
-- Metric definitions: Monthly sales accumulate within each calendar year. Annual price is sales divided by units.
-- Interpretation: The running average gives each year equal weight, regardless of units sold.
USE DataWarehouse;
GO

WITH monthly_sales AS (
    SELECT
        DATEFROMPARTS(YEAR(order_date), MONTH(order_date), 1) AS month_start,
        SUM(sales_amount) AS sales_amount
    FROM gold.fact_sales
    WHERE order_date IS NOT NULL
    GROUP BY DATEFROMPARTS(YEAR(order_date), MONTH(order_date), 1)
)
SELECT
    month_start,
    sales_amount,
    SUM(sales_amount) OVER (
        PARTITION BY YEAR(month_start)
        ORDER BY month_start
        ROWS UNBOUNDED PRECEDING
    ) AS year_to_date_sales
FROM monthly_sales
ORDER BY month_start;

WITH annual_sales AS (
    SELECT
        YEAR(order_date) AS order_year,
        SUM(sales_amount) AS sales_amount,
        SUM(CONVERT(bigint, quantity)) AS units_sold
    FROM gold.fact_sales
    WHERE order_date IS NOT NULL
    GROUP BY YEAR(order_date)
)
SELECT
    order_year,
    sales_amount,
    SUM(sales_amount) OVER (ORDER BY order_year ROWS UNBOUNDED PRECEDING) AS running_sales,
    CONVERT(decimal(18, 2), sales_amount / NULLIF(units_sold * 1.0, 0)) AS annual_average_unit_price,
    AVG(sales_amount / NULLIF(units_sold * 1.0, 0)) OVER (
        ORDER BY order_year ROWS UNBOUNDED PRECEDING
    ) AS running_average_of_annual_unit_prices
FROM annual_sales
ORDER BY order_year;
GO
