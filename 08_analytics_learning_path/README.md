# Analytics Learning Path

These scripts add a step-by-step set of SQL analyses to the warehouse. They are adapted from the Data With Baraa SQL Data Analytics project and adjusted to use this project's `DataWarehouse` Gold tables.

They do not create, reset, or load the database. First install the warehouse and complete a pipeline run using the instructions in the main [README](../README.md).

## Run the scripts

Run a script from the project root with SQLCMD. For example:

```powershell
sqlcmd -S localhost -E -b -i 08_analytics_learning_path/01_database_exploration.sql
```

Scripts `01` to `11` are standalone analyses. Scripts `12` and `13` create or update the customer and product report views in the Gold schema. Run them with a database login that has permission to create or update views.

The scripts use `is_current = 1` when counting customer and product dimension rows. This avoids counting older SCD Type 2 versions as additional customers or products. Sales reports use the current dimension keys that the warehouse stores on its fact rows.

These are supplemental learning queries. The six curated queries in `05_analytics/` remain the queries run by the current CI workflow.

## What each script covers

| Script | Analysis |
|---|---|
| `01_database_exploration.sql` | List warehouse tables and inspect columns |
| `02_dimensions_exploration.sql` | Explore countries, categories, subcategories, and products |
| `03_date_range_exploration.sql` | Check the sales date range and customer age range |
| `04_measures_exploration.sql` | Calculate sales, units, price, order, product, and customer measures |
| `05_magnitude_analysis.sql` | Compare customers, products, categories, and sales totals |
| `06_ranking_analysis.sql` | Find top products and customers, and products with the least sales |
| `07_change_over_time_analysis.sql` | Summarize sales by month |
| `08_cumulative_analysis.sql` | Calculate running sales totals and average prices |
| `09_performance_analysis.sql` | Compare yearly product sales with prior years and averages |
| `10_part_to_whole_analysis.sql` | Show each product category's share of sales |
| `11_data_segmentation.sql` | Group products by cost and customers by observed spending |
| `12_report_customers.sql` | Create a customer activity and sales report view |
| `13_report_products.sql` | Create a product activity and sales report view |

Customer and product spending thresholds are examples based on the source data's numeric sales amounts. The source files do not define a currency, so the scripts do not add a currency symbol or claim these are approved business segments.

## Attribution

The analysis sequence is adapted from the [Data With Baraa SQL Data Analytics project](https://github.com/DataWithBaraa/sql-data-analytics-project). The scripts are adjusted for this warehouse's schema and SCD Type 2 dimensions. The upstream copyright notice is included in the repository's [MIT license](../LICENSE).
