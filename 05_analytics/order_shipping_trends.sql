-- Business question: How are order volume, fulfillment time, and late shipments trending?
-- Metric definitions: An order is distinct by customer, order number, and order date.
-- Fulfillment time is calendar days from order date to the latest line shipment in that
-- order. A late order has at least one shipped line later than its line due date. Late
-- rate uses only orders with at least one shipped line and due date for comparison.
-- Interpretation: Split shipments are summarized to their final line shipment date;
-- this is calendar-day elapsed time, not a business-day service-level measure.
USE DataWarehouse;
GO

WITH order_shipping AS (
    SELECT
        f.customer_id,
        f.order_number,
        f.order_date,
        MAX(f.shipping_date) AS final_line_shipping_date,
        MAX(
            CASE
                WHEN f.shipping_date IS NOT NULL AND f.due_date IS NOT NULL THEN 1
                ELSE 0
            END
        ) AS has_comparable_shipment,
        MAX(
            CASE
                WHEN f.shipping_date > f.due_date THEN 1
                ELSE 0
            END
        ) AS has_late_line,
        MAX(
            CASE
                WHEN f.shipping_date > f.due_date THEN DATEDIFF(DAY, f.due_date, f.shipping_date)
                ELSE NULL
            END
        ) AS max_line_days_late
    FROM gold.fact_sales AS f
    GROUP BY f.customer_id, f.order_number, f.order_date
)
SELECT
    DATEFROMPARTS(YEAR(order_date), MONTH(order_date), 1) AS order_month,
    COUNT_BIG(*) AS order_count,
    SUM(CONVERT(bigint, CASE WHEN final_line_shipping_date IS NOT NULL THEN 1 ELSE 0 END)) AS shipped_orders,
    CONVERT(
        decimal(9, 2),
        AVG(
            CASE
                WHEN final_line_shipping_date IS NOT NULL
                    THEN CONVERT(decimal(9, 2), DATEDIFF(DAY, order_date, final_line_shipping_date))
                ELSE NULL
            END
        )
    ) AS average_days_to_final_line_shipment,
    SUM(CONVERT(bigint, CASE WHEN has_late_line = 1 THEN 1 ELSE 0 END)) AS late_orders,
    SUM(CONVERT(bigint, has_comparable_shipment)) AS orders_with_comparable_due_date,
    CONVERT(
        decimal(9, 2),
        100.0 * SUM(CONVERT(bigint, CASE WHEN has_late_line = 1 THEN 1 ELSE 0 END))
        / NULLIF(SUM(CONVERT(bigint, has_comparable_shipment)), 0)
    ) AS late_order_rate_pct,
    MAX(max_line_days_late) AS maximum_line_days_late
FROM order_shipping
GROUP BY DATEFROMPARTS(YEAR(order_date), MONTH(order_date), 1)
ORDER BY order_month;
GO
