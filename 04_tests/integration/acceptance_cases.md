# SQL Server acceptance cases

Run these against a disposable development database with the SQL Server service account able to read the test dataset. The local Python unit tests do not need SQL Server:

```powershell
python -m unittest discover -s 04_tests/unit -v
```

## Cases

1. Run the same complete snapshot twice with `python 03_scripts/etl/run_pipeline.py --mode incremental`. The source checksum history should reuse the same Bronze batches, Silver/Gold counts should stay stable, and the second run should show zero inserts for unchanged rows.
2. Point the runner to a copy with one required file removed, an empty file, a changed header, and a row with the wrong number of columns. Each run should fail preflight, leave Gold unchanged, and write a failure to `etl.pipeline_runs` / `etl.table_load_logs` when the database is reachable.
3. Add a malformed date, negative quantity, missing amount, inconsistent amount/price, and duplicate sales grain to a disposable CSV snapshot. Confirm invalid rows appear in `etl.rejected_records` by reason code and accepted rows still satisfy `04_tests/smoke_test.sql`.
4. Add an unmatched customer or product key to a disposable sales row. Gold should omit that row, record `UNMATCHED_CUSTOMER_DIMENSION` or `UNMATCHED_PRODUCT_DIMENSION`, and explain the count and amount difference in `etl.reconciliation_results`.
5. Run `sqlcmd -S <server> -E -i 04_tests/integration/redeploy_preserves_data.sql` from the repository root. It reapplies the installer and verifies that Bronze/Silver/Gold counts and current surrogate keys remain unchanged. `etl.schema_migrations` records the schema versions once.
6. In a development transaction, insert a synthetic customer into Silver whose ID sorts before current IDs, call `gold.load_gold` with a new `etl.pipeline_runs.run_id`, and verify existing customer keys did not change. Update a tracked customer attribute and rerun; verify the old row is expired, one new current version exists, and facts point to the current key. Roll the test transaction back.
7. For a failure gate, run the master procedure with a valid manifest and a deliberately unavailable SQL Server dataset root. Confirm the run is `FAILED`, the generic error summary is persisted, and Gold row counts are unchanged.
8. Run `04_tests/performance/benchmark_gold.sql`, capture actual execution plans and `STATISTICS IO/TIME`, and compare with a baseline before reporting any performance gain.

The checks are deliberately split between repeatable Python preflight unit tests, read-only SQL smoke checks, and database acceptance scenarios. Do not run destructive cases in a shared or production database.

The opt-in `test_sql_pipeline.py` automates replay idempotency and missing-source failure isolation when `RUN_SQL_INTEGRATION=1`; the SCD2/stable-key scenario remains an explicit SQL transaction in `stable_keys_and_scd2.sql`.
