# Curated analytics

Each script runs against the materialized `DataWarehouse` Gold schema and starts with its business question, metric definitions, and interpretation guidance. The queries are descriptive; they do not infer that an observed customer or product attribute caused a sales outcome.

| Script | Question |
| --- | --- |
| `monthly_sales_mom.sql` | How do monthly sales and units change, including months with no sales? |
| `product_performance.sql` | Which products and categories contribute the most sales? |
| `customer_lifetime_value.sql` | How often does each current customer order, and what is their lifetime sales total? |
| `country_customer_segments.sql` | How do sales vary by country, marital-status segment, and gender? |
| `order_value_quantity.sql` | What are monthly order count, average order value, and units per order? |
| `order_shipping_trends.sql` | How do order volume, fulfillment time, and late shipments trend? |

Run one query from the repository root with `sqlcmd -S <server> -E -i 05_analytics/monthly_sales_mom.sql`. The CI workflow executes these six curated queries against a disposable SQL Server database after loading the sample snapshots.

For a step-by-step collection of 13 additional exploratory and advanced queries, see the [analytics learning path](../08_analytics_learning_path/README.md). Those scripts also use the Gold schema; the report scripts create or update `gold.report_customers` and `gold.report_products` views.
