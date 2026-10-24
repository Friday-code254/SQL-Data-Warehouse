-- Business question: How are customers, products, and sales spread across groups?
-- Metric definitions: Counts use current dimensions; sales and units use accepted fact lines.
-- Interpretation: Sales amount is not profit because product cost is not subtracted.
USE DataWarehouse;
GO

SELECT country, COUNT_BIG(*) AS customer_count
FROM gold.dim_customers
WHERE is_current = 1 AND customer_key <> 0
GROUP BY country
ORDER BY customer_count DESC, country;

SELECT gender, COUNT_BIG(*) AS customer_count
FROM gold.dim_customers
WHERE is_current = 1 AND customer_key <> 0
GROUP BY gender
ORDER BY customer_count DESC, gender;

SELECT category, COUNT_BIG(*) AS product_count, AVG(cost) AS average_product_cost
FROM gold.dim_products
WHERE is_current = 1 AND product_key <> 0
GROUP BY category
ORDER BY product_count DESC, category;

SELECT
    COALESCE(p.category, N'Unknown') AS category,
    SUM(f.sales_amount) AS sales_amount,
    SUM(CONVERT(bigint, f.quantity)) AS units_sold
FROM gold.fact_sales AS f
LEFT JOIN gold.dim_products AS p
    ON p.product_key = f.product_key AND p.is_current = 1
GROUP BY COALESCE(p.category, N'Unknown')
ORDER BY sales_amount DESC;

SELECT TOP (20)
    c.customer_id, c.first_name, c.last_name, SUM(f.sales_amount) AS sales_amount
FROM gold.fact_sales AS f
INNER JOIN gold.dim_customers AS c
    ON c.customer_key = f.customer_key AND c.is_current = 1
GROUP BY c.customer_id, c.first_name, c.last_name
ORDER BY sales_amount DESC, c.customer_id;

SELECT
    c.country,
    SUM(CONVERT(bigint, f.quantity)) AS units_sold
FROM gold.fact_sales AS f
INNER JOIN gold.dim_customers AS c
    ON c.customer_key = f.customer_key AND c.is_current = 1
GROUP BY c.country
ORDER BY units_sold DESC, c.country;
GO
