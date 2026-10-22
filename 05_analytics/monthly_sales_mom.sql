-- Business question: How do monthly sales and units change over time?
-- Metric definitions: Sales is the sum of accepted Gold line sales. Units are the sum
-- of line quantities. MoM growth compares a calendar month with the immediately prior
-- calendar month; it is NULL for the first month or when the prior month has zero sales.
-- Interpretation: A missing activity month is shown as zero. Growth is descriptive and
-- is not adjusted for seasonality, price changes, or changes in the input snapshot.
USE DataWarehouse;
GO

WITH month_spine AS (
    SELECT DISTINCT
        DATEFROMPARTS(d.calendar_year, d.month_number, 1) AS month_start
    FROM gold.dim_date AS d
    WHERE d.date_key <> 0
),
monthly_sales AS (
    SELECT
        DATEFROMPARTS(d.calendar_year, d.month_number, 1) AS month_start,
        SUM(f.sales_amount) AS sales_amount,
        COUNT_BIG(*) AS sales_lines,
        SUM(CONVERT(bigint, f.quantity)) AS units_sold
    FROM gold.fact_sales AS f
    INNER JOIN gold.dim_date AS d
        ON d.date_key = f.order_date_key
    WHERE d.date_key <> 0
    GROUP BY DATEFROMPARTS(d.calendar_year, d.month_number, 1)
),
complete_months AS (
    SELECT
        s.month_start,
        COALESCE(m.sales_amount, CONVERT(decimal(38, 4), 0)) AS sales_amount,
        COALESCE(m.sales_lines, CONVERT(bigint, 0)) AS sales_lines,
        COALESCE(m.units_sold, CONVERT(bigint, 0)) AS units_sold
    FROM month_spine AS s
    LEFT JOIN monthly_sales AS m
        ON m.month_start = s.month_start
),
with_prior_month AS (
    SELECT
        month_start,
        sales_amount,
        sales_lines,
        units_sold,
        LAG(sales_amount) OVER (ORDER BY month_start) AS prior_month_sales
    FROM complete_months
)
SELECT
    month_start,
    sales_amount,
    sales_lines,
    units_sold,
    prior_month_sales,
    CASE
        WHEN prior_month_sales IS NULL OR prior_month_sales = 0 THEN NULL
        ELSE CONVERT(decimal(9, 2), 100.0 * (sales_amount - prior_month_sales) / prior_month_sales)
    END AS month_over_month_growth_pct
FROM with_prior_month
ORDER BY month_start;
GO
