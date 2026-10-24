-- Business question: How did yearly sales for each product compare with prior years?
-- Metric definitions: Current product sales are grouped by year and product business number.
-- Interpretation: Results use the latest accepted facts, not a historical event-time snapshot.
USE DataWarehouse;
GO

WITH yearly_product_sales AS (
    SELECT
        YEAR(f.order_date) AS order_year,
        p.product_number,
        MAX(p.product_name) AS product_name,
        SUM(f.sales_amount) AS current_year_sales
    FROM gold.fact_sales AS f
    INNER JOIN gold.dim_products AS p
        ON p.product_key = f.product_key AND p.is_current = 1
    WHERE f.order_date IS NOT NULL
    GROUP BY YEAR(f.order_date), p.product_number
),
product_comparisons AS (
    SELECT
        order_year,
        product_number,
        product_name,
        current_year_sales,
        AVG(current_year_sales) OVER (PARTITION BY product_number) AS average_yearly_sales,
        LAG(current_year_sales) OVER (PARTITION BY product_number ORDER BY order_year) AS prior_year_sales
    FROM yearly_product_sales
)
SELECT
    order_year,
    product_number,
    product_name,
    current_year_sales,
    average_yearly_sales,
    current_year_sales - average_yearly_sales AS difference_from_average,
    prior_year_sales,
    current_year_sales - prior_year_sales AS difference_from_prior_year
FROM product_comparisons
ORDER BY product_number, order_year;
GO
