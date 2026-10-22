# Sample data quality profile

**Profile date:** 2026-10-23  
**Snapshot:** the six CSV files shipped in `01_datasets/`  
**Observed SQL Server:** SQL Server 2022, disposable review database

This profile records what the supplied sample snapshot does under the current loader rules. It is a reproducible data-quality baseline, not a business approval of the resulting fact count. The source files do not establish whether rejected sales should be corrected, retained as exceptions, or excluded from the business definition.

## Full-load result

| Measure | Rows / amount |
| --- | ---: |
| Source sales lines | 60,398 |
| Silver sales lines | 60,360 |
| Gold sales facts | 60,360 |
| Sales lines rejected before Silver | 38 |
| Total reject ledger entries across all sources | 64 |
| Source `sls_sales` total | 29,355,647 |
| Gold sales amount | 29,347,942 |
| Source-to-Gold amount difference | 7,705 |

The source amount difference equals the sum of `sls_sales` values on the 38 rejected rows in this snapshot. The six files contain 116,294 source rows in total.

## Sales rejects

| Reason code | Rows | Sum of source `sls_sales` |
| --- | ---: | ---: |
| `INVALID_DATE_OR_AMOUNT` | 19 | 4,922 |
| `NEGATIVE_AMOUNT` | 7 | 2,471 |
| `SALES_PRICE_MISMATCH` | 12 | 312 |
| **Total** | **38** | **7,705** |

Review of `sales_details.csv` against the Silver predicate found:

- All 19 `INVALID_DATE_OR_AMOUNT` rows have an unparseable order date: 17 have `sls_order_dt = 0`, and two have short malformed values (`32154` and `5489`). The input provides no supported order date to substitute.
- The seven rows classified as `NEGATIVE_AMOUNT` have a negative value in `sls_sales` or `sls_price`. There is one additional negative-value line with a malformed date; it is classified under the earlier `INVALID_DATE_OR_AMOUNT` rule. Whether any represent legitimate credits or returns is not defined by the sample project.
- The 12 `SALES_PRICE_MISMATCH` rows differ from `sls_quantity × sls_price` by more than the loader's `0.0001` tolerance. The source does not say whether line sales or unit price is authoritative for these records.

The same checks were independently applied to the supplied CSV using decimal arithmetic; the reason counts, rejected source-amount sum, and accepted count match the SQL run. The corresponding SQL rules are in [`proc_load_silver.sql`](../03_scripts/silver/proc_load_silver.sql#L142).

## Other rejects and corrections

| Source / treatment | Rows | Detail |
| --- | ---: | --- |
| CRM customers rejected | 10 | 1 duplicate customer ID, 4 invalid customer keys, 5 rows missing a first or last name |
| ERP customer enrichment rejected | 16 | Future birth dates relative to the load date (2026-10-23) |
| Product end dates corrected in Silver | 200 | 102 rebuilt from the next product version's start date; 98 cleared on latest versions |

The 26 customer and enrichment rejects bring the ledger total to 64. Product date repairs are warnings rather than rejects. Each repaired Silver product row carries a correction code. The implementation is in [`proc_load_silver.sql`](../03_scripts/silver/proc_load_silver.sql#L101), and the quality warning is defined in [`proc_run_quality_checks.sql`](../03_scripts/etl/proc_run_quality_checks.sql#L30).

## Run and verification interpretation

The complete snapshot load succeeded with the rules above. A separate expected-failure integration case deliberately uses a SQL-side source path that does not exist; it passes when the pipeline fails and the previously published Gold data remains unchanged. That `FAILED` test run is not the status of the complete load.

The hosted [SQL warehouse CI run](https://github.com/Friday-code254/SQL-Data-Warehouse/actions/runs/39827208082) completed successfully for commit `1d5bba633b4ddddaca47b4ddc8faf76043d25484`. The workflow runs the SQL Server integration cases, replay and failure-isolation checks, redeployment and SCD Type 2 checks, smoke tests, and all six analytics queries.

No business validation rule was changed as part of this profile. Review the 38 rejected sales rows with the data owner before treating 60,360 as the approved sales fact count. The measured query results remain documented in [`performance_report.md`](performance_report.md); no SQL or index changes were made for this review.
