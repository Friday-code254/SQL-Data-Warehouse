# Source-to-target mapping

| Source | Key fields | Bronze | Silver rule | Gold target |
| --- | --- | --- | --- | --- |
| `source_crm/cust_info.csv` | `cst_id`, `cst_key` | Text values plus batch, file hash, file name, load time, row hash | Parse ID/date safely; trim names and key; map gender and marital codes; keep latest source row by customer ID; quarantine invalid/duplicate IDs | `gold.dim_customers`, current row selected for `gold.fact_sales` |
| `source_crm/prd_info.csv` | `prd_id`, `prd_key` | Text values and ingestion metadata | `TRY_CONVERT` ID/cost/dates; derive category and product business key; keep nullable cost as NULL; rebuild version end dates from the next start date and mark the correction; standardize product line | Latest product attributes in SCD2 `gold.dim_products` |
| `source_crm/sales_details.csv` | order + product + customer + order date | Text values and ingestion metadata | Safe `YYYYMMDD` dates, decimal amount/price; derive a single missing amount from the other value and quantity; reject both missing, invalid, negative, inconsistent, or duplicate-grain rows | `gold.fact_sales`, one sales line at the documented grain |
| `source_erp/CUST_AZ12.csv` | `CID` | Text values and ingestion metadata | Remove `NAS` prefix; parse ISO birth date; future dates become NULL with a reject record; standardize gender | Customer enrichment in `gold.dim_customers` |
| `source_erp/LOC_A101.csv` | `CID` | Text values and ingestion metadata | Remove dashes from customer ID; normalize country names | Customer enrichment in `gold.dim_customers` |
| `source_erp/PX_CAT_G1V2.csv` | `ID` | Text values and ingestion metadata | Trim source category attributes | Product enrichment in `gold.dim_products` |

Raw values are not copied into rejection logs. Rejections contain source key, entity, SHA-256 row fingerprint, reason code, and a generic reason description.
