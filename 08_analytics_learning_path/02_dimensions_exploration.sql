-- Business question: Which countries, categories, and products are in the current data?
-- Metric definitions: Distinct values are taken from current SCD Type 2 dimension rows.
-- Interpretation: Historical versions are left out so one business entity is counted once.
USE DataWarehouse;
GO

SELECT DISTINCT country
FROM gold.dim_customers
WHERE is_current = 1 AND customer_key <> 0
ORDER BY country;

SELECT DISTINCT category, subcategory, product_name
FROM gold.dim_products
WHERE is_current = 1 AND product_key <> 0
ORDER BY category, subcategory, product_name;
GO
