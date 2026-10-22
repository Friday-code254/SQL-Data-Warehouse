# Column lineage

This page follows the fields that drive the Gold model and curated analytics. Bronze retains the source text plus source-file and row metadata; the rules below begin when Silver parses that text.

| Source field | Silver transformation | Gold destination / use |
| --- | --- | --- |
| `cust_info.cst_id` | `TRY_CONVERT(int, ...)`; missing or invalid identifiers are rejected; the latest customer row is retained | `gold.dim_customers.customer_id`; joins accepted sales lines to the customer dimension |
| `cust_info.cst_key` | Trimmed CRM business key | `gold.dim_customers.customer_number`; joins to ERP customer enrichment |
| `cust_info.cst_firstname`, `cst_lastname` | Trimmed; blanks become NULL | `gold.dim_customers.first_name`, `last_name`; customer lifetime query labels |
| `cust_info.cst_marital_status` | `S` → `Single`, `M` → `Married`, other values → `n/a` | `gold.dim_customers.marital_status`; descriptive customer segment |
| `cust_info.cst_gndr` | `F`/`M` → `Female`/`Male`; otherwise `n/a` | `gold.dim_customers.gender`, with ERP gender fallback when CRM is `n/a` |
| `cust_info.cst_create_date` | Safe ISO date conversion; invalid nonblank date is rejected | `gold.dim_customers.create_date` |
| `CUST_AZ12.CID` | Removes the leading `NAS` prefix where present; deduplicates normalized IDs | `silver.erp_cust_az12.cid`; join to CRM `cst_key` |
| `CUST_AZ12.BDATE` | ISO date conversion; invalid, future, or out-of-range values are rejected from enrichment | `gold.dim_customers.birthdate` |
| `CUST_AZ12.GEN` | Standardizes male/female values; other values become `n/a` | Gender fallback in `gold.dim_customers.gender` |
| `LOC_A101.CID` | Removes hyphens and trims; duplicate normalized IDs are quarantined | Join key to CRM customer business key |
| `LOC_A101.CNTRY` | `DE` → `Germany`, `US`/`USA` → `United States`, blank → `n/a` | `gold.dim_customers.country`; country and segment analytics |
| `prd_info.prd_id` | Safe integer conversion | `gold.dim_products.product_id` |
| `prd_info.prd_key` | First five characters become `cat_id` with hyphen changed to underscore; characters from position seven form the product business key | `gold.dim_products.category_id`, `product_number`; sales-to-product matching |
| `prd_info.prd_nm`, `prd_cost`, `prd_line` | Trimmed name; cost parsed as `DECIMAL(19,4)` and retained as NULL when missing; line code standardized | `gold.dim_products.product_name`, `cost`, `product_line` |
| `prd_info.prd_start_dt`, `prd_end_dt` | Safe ISO dates; version end date is rebuilt from the next start date when needed and tagged with a correction code | Product ordering and SCD2 current attributes |
| `PX_CAT_G1V2.ID`, `CAT`, `SUBCAT`, `MAINTENANCE` | Trimmed; missing required category identifiers/labels and duplicate IDs are recorded as rejects | Product category attributes in `gold.dim_products`; product/category analytics |
| `sales_details.sls_ord_num`, `sls_prd_key`, `sls_cust_id` | Trimmed; customer ID parsed safely; duplicate `(order, product, customer, order date)` grain is rejected | `gold.fact_sales.order_number`, product and customer business keys; dimension surrogate-key resolution |
| `sales_details.sls_order_dt`, `sls_ship_dt`, `sls_due_dt` | `YYYYMMDD` safe conversion; invalid or impossible dates are rejected; optional missing ship/due dates remain NULL | Fact date attributes and `order_date_key`, `shipping_date_key`, `due_date_key` references to `gold.dim_date` |
| `sales_details.sls_sales`, `sls_quantity`, `sls_price` | Sales and price use `DECIMAL(19,4)`; quantity must be positive; one missing amount may be derived and tagged; invalid, negative, missing-both, or inconsistent values are rejected | `gold.fact_sales.sales_amount`, `quantity`, `price`; monthly, customer, product, and order-value measures |

The accepted fact grain is one line per `(order_number, product_number, customer_id, order_date)`. Gold uses persisted customer/product surrogate keys and three role-playing date keys. See [data_catalog.md](data_catalog.md) for table grains and [source_to_target_mapping.md](source_to_target_mapping.md) for the layer-level mapping.
