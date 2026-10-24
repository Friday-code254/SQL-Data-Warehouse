-- Business question: What time period does the current sales snapshot cover?
-- Metric definitions: The range runs from the earliest to latest accepted Gold order date.
-- Interpretation: Customer ages are approximate; DATEDIFF(YEAR) does not check birthdays.
USE DataWarehouse;
GO

SELECT
    MIN(order_date) AS first_order_date,
    MAX(order_date) AS last_order_date,
    DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) AS order_range_months
FROM gold.fact_sales;

SELECT
    MIN(birthdate) AS oldest_birthdate,
    DATEDIFF(YEAR, MIN(birthdate), CONVERT(date, GETDATE())) AS approximate_oldest_age,
    MAX(birthdate) AS youngest_birthdate,
    DATEDIFF(YEAR, MAX(birthdate), CONVERT(date, GETDATE())) AS approximate_youngest_age
FROM gold.dim_customers
WHERE is_current = 1 AND customer_key <> 0 AND birthdate IS NOT NULL;
GO
