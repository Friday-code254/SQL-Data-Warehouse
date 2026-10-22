# Query performance report

## Workloads and indexes

The workload script measures monthly sales by order date, product rollups, and customer rollups. The indexes support the actual load and query paths:

- `silver.crm_cust_info(cst_key)` supports CRM-to-ERP customer enrichment.
- `silver.crm_prd_info(prd_key, prd_start_dt DESC)` supports selecting the latest product version per business key.
- Silver sales indexes support customer/date and product/date filters, with common measures included.
- Gold fact indexes support order-date aggregation and product/customer dimension joins.
- Gold dimension indexes support current business-key lookups and product category filters.

## Measurements

Captured on SQL Server 2022 for Linux, build `16.0.4305.5`, after a full pipeline load with 60,360 Gold fact rows. Each benchmark ran twice with the five reporting indexes disabled and twice with them enabled. Times are raw milliseconds in run order. Result row counts matched between variants.

| Workload | Baseline runs (ms) | Indexed runs (ms) | Logical reads, baseline → indexed | Result rows |
| --- | ---: | ---: | ---: | ---: |
| Monthly sales by order date | 49, 80 | 46, 30 | 1,173 → 305 | 38 |
| Product sales rollup | 29, 92 | 42, 38 | 1,173 → 305 | 130 |
| Customer sales rollup | 308, 379 | 109, 87 | 1,561 → 633 | 18,482 |

`STATISTICS IO` showed zero physical reads in these plan-capture runs. The actual plans explain the logical-read changes:

- **Monthly sales:** the baseline scanned the clustered fact and date indexes and used hash joins/aggregation. With indexes enabled, SQL Server scanned `IX_gold_fact_order_date`, scanned the date dimension, and used a merge join with stream/hash aggregation.
- **Product rollup:** the baseline scanned both clustered tables and used a hash join plus sort/stream aggregation. With indexes enabled, the fact side used the covering `IX_gold_fact_order_date` and the product dimension used its clustered key, followed by merge/sort/stream aggregation.
- **Customer rollup:** the baseline scanned both clustered tables and used hash joins/aggregation. With indexes enabled, the fact side used `IX_gold_fact_customer`, the customer dimension used its clustered key, and the plan used a merge join and hash aggregation.

Logical reads fell by about 74% for monthly and product rollups, and 59% for the customer rollup in this run. Elapsed times varied between the two executions, so treat all results as measurements from this local container, not a general speed-up guarantee. Repeat under controlled cache and load conditions before making a production claim.
