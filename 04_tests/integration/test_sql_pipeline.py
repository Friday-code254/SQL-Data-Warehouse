"""Opt-in SQL Server acceptance tests. Enable with RUN_SQL_INTEGRATION=1."""
import os
from pathlib import Path
import shutil
import unittest
import uuid

import importlib.util
import json


PROJECT = Path(__file__).resolve().parents[2]
RUNNER_SPEC = importlib.util.spec_from_file_location("run_pipeline", PROJECT / "03_scripts" / "etl" / "run_pipeline.py")
runner = importlib.util.module_from_spec(RUNNER_SPEC)
RUNNER_SPEC.loader.exec_module(runner)


@unittest.skipUnless(os.getenv("RUN_SQL_INTEGRATION") == "1", "set RUN_SQL_INTEGRATION=1 for disposable SQL Server integration tests")
class SqlPipelineAcceptanceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import pyodbc
        cls.connection = pyodbc.connect(runner.connection_string(), autocommit=True)
        cls.dataset_root = Path(os.getenv("SQLSERVER_LOCAL_DATASET_ROOT", PROJECT / "01_datasets"))
        cls.source_config = runner.load_source_config(cls.connection)
        cls.manifest = runner.build_manifest(cls.dataset_root, cls.source_config)

    @classmethod
    def tearDownClass(cls):
        cls.connection.close()

    def state(self):
        cursor = self.connection.cursor()
        cursor.execute("""
            SELECT (SELECT COUNT_BIG(*) FROM bronze.crm_sales_details),
                   (SELECT COUNT_BIG(*) FROM silver.crm_sales_details),
                   (SELECT COUNT_BIG(*) FROM gold.fact_sales),
                   (SELECT COUNT_BIG(*) FROM etl.source_file_history)
        """)
        counts = tuple(cursor.fetchone())
        cursor.execute("SELECT customer_id,customer_key FROM gold.dim_customers WHERE is_current=1 ORDER BY customer_id")
        customers = tuple(tuple(row) for row in cursor.fetchall())
        cursor.execute("SELECT product_number,product_key FROM gold.dim_products WHERE is_current=1 ORDER BY product_number")
        products = tuple(tuple(row) for row in cursor.fetchall())
        return counts, customers, products

    def prepare_manifest_for_sql_server(self):
        if runner.sql_server_is_linux(self.connection):
            return runner.prepare_linux_bulk_files(self.dataset_root, self.manifest)
        return self.manifest, None

    def invoke_current_snapshot(self, mode):
        manifest, stage_dir = self.prepare_manifest_for_sql_server()
        try:
            return runner.invoke_sql(self.connection, self.dataset_root, mode, manifest)
        finally:
            if stage_dir is not None:
                shutil.rmtree(stage_dir, ignore_errors=True)

    def test_replaying_snapshot_is_idempotent_and_preserves_dimension_keys(self):
        self.invoke_current_snapshot("incremental")
        after_first = self.state()
        self.invoke_current_snapshot("incremental")
        after_second = self.state()
        self.assertEqual(after_first, after_second)
        cursor = self.connection.cursor()
        cursor.execute("SELECT TOP(1) status FROM etl.pipeline_runs ORDER BY started_at DESC")
        self.assertEqual(cursor.fetchone()[0], "SUCCEEDED")
        cursor.execute("SELECT SUM(inserted_rows) FROM etl.table_load_logs WHERE run_id=(SELECT TOP(1) run_id FROM etl.pipeline_runs ORDER BY started_at DESC) AND layer=N'bronze'")
        self.assertEqual(cursor.fetchone()[0], 0)

    def test_missing_sql_server_source_path_fails_without_publishing_gold(self):
        import pyodbc
        before = self.state()
        cursor = self.connection.cursor()
        cursor.execute("SELECT CONVERT(nvarchar(20),SERVERPROPERTY('HostPlatform'))")
        is_linux = "linux" in str(cursor.fetchone()[0]).lower()
        missing_root = ("/tmp/codex_missing_" if is_linux else "Z:\\codex_missing_") + uuid.uuid4().hex
        manifest, stage_dir = self.prepare_manifest_for_sql_server()
        manifest_json = json.dumps(manifest, separators=(",", ":"))
        try:
            with self.assertRaises(pyodbc.Error):
                cursor.execute("EXEC etl.load_warehouse @dataset_root=?, @manifest_json=?, @run_mode='FULL'", missing_root, manifest_json)
        finally:
            if stage_dir is not None:
                shutil.rmtree(stage_dir, ignore_errors=True)
        after = self.state()
        self.assertEqual(before, after)
        cursor.execute("SELECT TOP(1) status,error_summary FROM etl.pipeline_runs ORDER BY started_at DESC")
        status, error_summary = cursor.fetchone()
        self.assertEqual(status, "FAILED")
        self.assertIn("Bronze source staging failed", error_summary)

    def test_sample_source_to_gold_sales_amount_is_explained_by_reject_reason(self):
        cursor = self.connection.cursor()
        cursor.execute("SELECT TOP(1) run_id FROM etl.pipeline_runs WHERE status='SUCCEEDED' ORDER BY started_at DESC")
        run_id = cursor.fetchone()[0]
        cursor.execute("SELECT metric_name,source_value,target_value,difference FROM etl.reconciliation_results WHERE run_id=?", run_id)
        metrics = {row.metric_name: row for row in cursor.fetchall()}

        self.assertEqual(metrics["source_gold_sales_amount"].difference, 7705)
        self.assertEqual(metrics["sales_reject_amount_INVALID_DATE_OR_AMOUNT"].difference, 4922)
        self.assertEqual(metrics["sales_reject_amount_NEGATIVE_AMOUNT"].difference, 2471)
        self.assertEqual(metrics["sales_reject_amount_SALES_PRICE_MISMATCH"].difference, 312)
        self.assertEqual(metrics["rejected_sales_amount_total"].difference, 7705)
        self.assertEqual(metrics["source_gold_sales_amount_bridge"].difference, 0)


if __name__ == "__main__":
    unittest.main()
