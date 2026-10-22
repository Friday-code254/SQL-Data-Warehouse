# SQL Data Warehouse and Analytics Project

This project ingests CRM and ERP CSV snapshots into SQL Server Bronze, Silver, and Gold layers. The supplied tutorial project is retained as the starting point and its MIT license remains in [LICENSE](LICENSE). This upgrade adds auditable orchestration, safer snapshot ingestion, incremental current-state upserts, SCD Type 2 dimensions, a date dimension, quality gates, reconciliation, and measured performance tooling.

## Requirements

- SQL Server 2022 (the Docker configuration uses the SQL Server 2022 image); the CSV bulk syntax requires SQL Server 2017 or later.
- SQLCMD utilities for installation, and the ODBC Driver 18 for SQL Server for the Python runner.
- Python 3.9 or later.
- The SQL Server service account must be able to read the six CSV files. On Linux it must also be able to read the runner's temporary .sql_bulk_stage directory. Local Python access alone is not sufficient for BULK INSERT.
- The deployment account needs database/schema/procedure creation rights. The pipeline login needs execution rights plus bulk-operation permission. SQL Server on Linux before 2022 CU24 may require `sysadmin` for bulk loading; use a current supported CU for `bulkadmin` / `ADMINISTER BULK OPERATIONS` support.

For Linux ODBC setup, follow Microsoft's [ODBC Driver installation instructions](https://learn.microsoft.com/sql/connect/odbc/linux-mac/installing-the-microsoft-odbc-driver-for-sql-server). The CI workflow installs Driver 18 on Ubuntu 24.04 and runs a disposable SQL Server 2022 Developer container.

## Install

Run from this repository's root so the SQLCMD includes resolve:

```powershell
sqlcmd -S localhost -E -i 00_setup/install.sql
```

For SQL authentication, use `sqlcmd -S <server> -U <user> -C -i 00_setup/install.sql` and enter the password when prompted. Installation creates `DataWarehouse` only if it does not exist, preserves existing tutorial tables as `*_legacy`, and can be run repeatedly. It does not clear warehouse data.

`00_setup/development_reset.sql` is a **development-only destructive reset**. Do not use it where existing data must be retained.

### Docker on macOS

Run `00_setup/mac-docker/start.command`. It prompts for a strong `sa` password if `MSSQL_SA_PASSWORD` is unset and mounts the dataset directory read-only at `/sql/dwh_project/01_datasets`. Install the schema from the repository root using the container's SQLCMD tool or a host SQLCMD connection. In your local `.env`, set SQL authentication and `SQLSERVER_DATASET_ROOT=/sql/dwh_project/01_datasets`.

## Configure and run

```powershell
Copy-Item .env.example .env
python -m pip install -r requirements.txt
python 03_scripts/etl/run_pipeline.py --mode full
```

Edit `.env` with your server, database, driver, and authentication settings. `.env` is ignored by Git. On Windows, integrated authentication is the default. For SQL authentication, set `SQLSERVER_TRUSTED_CONNECTION=no`, `SQLSERVER_USER`, and `SQLSERVER_PASSWORD`. Set `SQLSERVER_DATASET_ROOT` when the SQL Server service sees the files at a different absolute path than Python does.

Required source paths, headers, and column counts are centralized in `etl.source_config`. Update that table when a dataset's relative path or schema changes; the runner reads the same settings before preflight.

`--mode full` rebuilds the current Silver snapshot transactionally and refreshes Gold while preserving Bronze batches and Gold surrogate-key history. `--mode incremental` applies row-hash upserts and snapshot deletion reconciliation. Both modes require a complete snapshot of all six files. Replaying the same unchanged files reuses the original Bronze batches and does not duplicate raw rows.

The runner reads file paths and expected headers from `etl.source_config`, then checks source existence, UTF-8 CSV structure, exact headers, column counts, row counts, line endings, file sizes, and SHA-256 hashes before opening a pipeline run. SQL Server verifies each original file checksum again and stages every file before committing Bronze data. On Linux, the runner creates a per-run UTF-16 sidecar for each CSV; SQL Server verifies each sidecar checksum before loading it. The sidecars are removed after the run, and the Mac Docker setup bind-mounts their directory so SQL Server can read them. If preflight fails, a sanitized failed run is recorded.

Each CSV must use consistent LF or CRLF line endings and end with a line terminator. This avoids SQL Server bulk import silently omitting a final record or retaining a carriage return in a field.

## Script layout

- `03_scripts/init_database.sql`: safe database/schema bootstrap.
- `03_scripts/migrations/`: legacy-preservation migration and workload-aligned indexes.
- `03_scripts/{bronze,silver,gold}/`: layer DDL and load procedures.
- `03_scripts/etl/`: control-plane tables, pipeline orchestration, reconciliation, and quality gates.
- `04_tests/unit/`: repeatable Python input-validation tests.
- `04_tests/integration/`: SQL Server acceptance scenarios.
- `04_tests/performance/`: benchmark workload and SQL IO/time capture.
- `05_analytics/`: documented, runnable SQL answers for sales trends, products, customers, segments, order value, and shipping.
- `06_reports/`: benchmark evidence and project reports, including the [sample data quality profile](06_reports/sample_data_quality_profile.md) for the supplied snapshot.
- `07_orchestration/`: Windows scheduling wrapper and scheduler setup notes.
- `.github/workflows/`: automated Python, SQL lint, SQL Server integration, smoke, and analytics checks.
- `02_docs/`: architecture, column lineage, source mapping, data catalog, and design decisions.

## Tests and verification

Run the local unit suite with:

```powershell
python -m unittest discover -s 04_tests/unit -v
```

After a pipeline run, execute `04_tests/smoke_test.sql` in `DataWarehouse` to inspect the latest run, quality outcomes, and reconciliations. Use `04_tests/integration/acceptance_cases.md` for replay, failure, migration, SCD2, invalid-data, and stable-key scenarios. The SQL Server acceptance cases require a disposable development database and file access for the SQL Server service account.

Opt-in integration tests exercise snapshot replay and failure isolation against SQL Server. Set `RUN_SQL_INTEGRATION=1` and run `python -m unittest discover -s 04_tests/integration -p "test_*.py" -v` only against a disposable development database.

For performance measurements, enable Actual Execution Plan in SSMS and run `04_tests/performance/benchmark_gold.sql`. It records durations and result sizes in `etl.performance_results` and emits `STATISTICS IO/TIME`. The [performance report](06_reports/performance_report.md) contains a captured baseline-versus-indexed comparison on SQL Server 2022; rerun it under controlled conditions before applying those local results to another environment.

## Curated analytics

Run a query from the repository root, for example:

```powershell
sqlcmd -S localhost -E -i 05_analytics/monthly_sales_mom.sql
```

All six analytics scripts state the question, metric definitions, and interpretation limits at the top. They run against the materialized Gold tables; the query descriptions and metric details are in [05_analytics/README.md](05_analytics/README.md).

## Scheduling and continuous integration

On Windows, schedule `07_orchestration/run_pipeline.ps1 -Mode incremental` with Task Scheduler after a complete snapshot arrives. The wrapper logs output and returns the runner's exit code. See [the scheduler guide](07_orchestration/README.md). For other schedulers, call the Python CLI directly and preserve its return code.

The GitHub Actions workflow in `.github/workflows/warehouse-ci.yml` checks project structure, lints the analytics SQL, runs the Python unit tests, installs the schema in a disposable SQL Server 2022 container, runs the complete pipeline, executes the smoke and analytics queries, and checks data-preserving redeployment, SCD2, replay, and failure isolation. It uses a generated test-only SQL password and does not need repository secrets.

To run the same checks locally, install `requirements-dev.txt`, run the Python unit and integration commands above against a disposable database, execute every script in `05_analytics/`, then run `04_tests/smoke_test.sql`. The local integration tests must never target a shared or production database.

## Fresh setup and reset

1. Install SQL Server 2022 (or a compatible supported SQL Server), SQLCMD, Python, and ODBC Driver 18.
2. From the repository root, install the warehouse with `sqlcmd -S <server> -E -i 00_setup/install.sql`. This is repeatable and preserves loaded data.
3. Copy `.env.example` to `.env`, configure the connection and SQL Server-visible dataset path, then install runtime dependencies with `python -m pip install -r requirements.txt`.
4. Run `python 03_scripts/etl/run_pipeline.py --mode full`. Use `--mode incremental` for later complete snapshots.
5. Run `04_tests/smoke_test.sql` and the curated queries. Inspect the ETL audit tables for row counts, rejects, reconciliations, and failures.

Only for a disposable development database, `sqlcmd -S <server> -E -i 00_setup/development_reset.sql` drops the database; follow it with `00_setup/install.sql` and a fresh full pipeline run. Do not use the reset script where warehouse data must be retained.

## Logs and troubleshooting

- `etl.pipeline_runs`: one run outcome and sanitized failure summary.
- `etl.table_load_logs`: per-table inserted/updated/deleted/rejected counts and durations.
- `etl.data_quality_results`: named gate rule, severity, actual/expected values, and outcome.
- `etl.rejected_records`: source fingerprint and reason code; raw values are not copied.
- `etl.reconciliation_results`: source, Bronze, Silver, and Gold counts and sales totals.
- `etl.source_file_history`: checksum-based replay history.

If the runner passes but SQL bulk loading fails, confirm the configured SQL dataset root exists from the SQL Server host/container and that its service account has read permission. For malformed files, compare the exact headers to the values in `etl.source_config`. If a critical gate fails, inspect `etl.data_quality_results` and `etl.rejected_records`; the previous successful Gold state remains committed.

## Attribution

The included source CSVs, diagrams, starter SQL, documentation, and original license came from the Data With Baraa SQL Data Warehouse project. The orchestration, logging, safer loading, dimensional history, reconciliation, testing, and performance additions are project upgrades. See [LICENSE](LICENSE) for the original MIT terms and attribution.
