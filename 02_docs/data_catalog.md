# Gold layer data catalog

## `gold.dim_customers`

One row per observed version of a customer. `customer_key` is an identity surrogate key and never recalculated from sort order. `customer_id` is the source business key. Customer attributes are enriched from CRM and ERP. `effective_start_date`, `effective_end_date`, and `is_current` describe warehouse-observed SCD Type 2 versions. A customer absent from the latest complete snapshot has its current row expired.

## `gold.dim_products`

One row per observed version of a product business key. `product_key` is a stable identity surrogate; `product_number` joins the CRM sales file to the latest product attributes. Cost uses `DECIMAL(19,4)` and may be NULL when the source cost is missing. Category information comes from ERP. The effective columns implement SCD Type 2.

## `gold.dim_date`

One row per calendar date in the loaded order, shipping, and due-date range, plus key `0` for an unknown optional date. It includes calendar year, quarter, month, ISO week, day-of-week, and weekend flag. Order, shipping, and due dates use separate role-playing keys in the fact table.

## `gold.fact_sales`

One row per accepted order line at grain `(order_number, product_number, customer_id, order_date)`. `fact_sales_key` is a warehouse row identity. `product_key`, `customer_key`, and the three date keys are enforced foreign keys. `sales_amount` and `price` use `DECIMAL(19,4)`; quantity must be positive. `correction_code` identifies a derived amount. Facts resolve to dimension versions current at the latest snapshot load, because the sources do not provide reliable attribute-effective timestamps.

## Audit tables

`etl.pipeline_runs` records run-level status. `etl.table_load_logs` stores per-table metrics and duration. `etl.data_quality_results` stores named tests and outcomes. `etl.rejected_records` stores hashed row references and reason codes but no source values. `etl.reconciliation_results` provides row and amount comparisons. `etl.source_file_history` records one row per source key/checksum. `etl.performance_results` captures measured benchmark runtimes and result volumes.
