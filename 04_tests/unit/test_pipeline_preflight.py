import csv
import hashlib
import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest


PROJECT = Path(__file__).resolve().parents[2]
RUNNER_PATH = PROJECT / "03_scripts" / "etl" / "run_pipeline.py"
SPEC = importlib.util.spec_from_file_location("run_pipeline", RUNNER_PATH)
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class CsvPreflightTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.key = "crm_cust_info"
        self.relative_path = "source_crm/cust_info.csv"
        self.header = "cst_id,cst_key,cst_firstname,cst_lastname,cst_marital_status,cst_gndr,cst_create_date"
        self.file = self.root / "cust_info.csv"

    def tearDown(self):
        self.temp.cleanup()

    def write(self, header=None, rows=None):
        with self.file.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.writer(stream)
            writer.writerow((header or self.header).split(","))
            for row in rows if rows is not None else [["1", "AW00000001", "Alex", "Lee", "S", "F", "2025-01-01"]]:
                writer.writerow(row)

    def test_valid_file_produces_row_count_size_and_sha256(self):
        self.write()
        metadata = runner.inspect_csv(self.file, self.key, self.relative_path, self.header)
        self.assertEqual(metadata["row_count"], 1)
        self.assertEqual(metadata["file_size"], self.file.stat().st_size)
        self.assertEqual(metadata["sha256"], hashlib.sha256(self.file.read_bytes()).hexdigest().upper())
        self.assertEqual(metadata["line_terminator"], "CRLF")

    def test_header_change_is_rejected(self):
        self.write(header="cst_id,cst_key,unexpected")
        with self.assertRaisesRegex(runner.InputError, "Unexpected CSV header"):
            runner.inspect_csv(self.file, self.key, self.relative_path, self.header)

    def test_malformed_column_count_is_rejected(self):
        self.write(rows=[["1", "AW00000001"]])
        with self.assertRaisesRegex(runner.InputError, "column count mismatch"):
            runner.inspect_csv(self.file, self.key, self.relative_path, self.header)

    def test_missing_file_is_rejected_with_audit_code(self):
        with self.assertRaises(runner.InputError) as caught:
            runner.inspect_csv(self.file, self.key, self.relative_path, self.header)
        self.assertEqual(caught.exception.reason_code, "MISSING_FILE")

    def test_empty_data_file_is_rejected(self):
        self.write(rows=[])
        with self.assertRaisesRegex(runner.InputError, "no data rows"):
            runner.inspect_csv(self.file, self.key, self.relative_path, self.header)

    def test_missing_final_line_terminator_is_rejected(self):
        self.write()
        self.file.write_bytes(self.file.read_bytes()[:-1])
        with self.assertRaisesRegex(runner.InputError, "must end with a line terminator") as caught:
            runner.inspect_csv(self.file, self.key, self.relative_path, self.header)
        self.assertEqual(caught.exception.reason_code, "MISSING_FINAL_LINE_TERMINATOR")

    def test_lf_terminators_are_reported_for_sql_bulk_loading(self):
        self.write()
        self.file.write_bytes(self.file.read_bytes().replace(b"\r\n", b"\n"))
        metadata = runner.inspect_csv(self.file, self.key, self.relative_path, self.header)
        self.assertEqual(metadata["line_terminator"], "LF")

    def test_mixed_line_terminators_are_rejected(self):
        self.write(rows=[["1", "AW00000001", "Alex", "Lee", "S", "F", "2025-01-01"],
                         ["2", "AW00000002", "Sam", "Wu", "M", "M", "2025-01-02"]])
        contents = self.file.read_bytes().replace(b"\r\n", b"\n", 1)
        self.file.write_bytes(contents)
        with self.assertRaisesRegex(runner.InputError, "mixes CRLF and LF") as caught:
            runner.inspect_csv(self.file, self.key, self.relative_path, self.header)
        self.assertEqual(caught.exception.reason_code, "MIXED_LINE_TERMINATORS")

    def test_linux_bulk_sidecar_normalizes_windows_path_and_preserves_unicode_rows(self):
        self.write(rows=[["1", "AW00000001", "José", "Lee", "S", "M", "2025-01-01"]])
        source_dir = self.root / "source_crm"
        source_dir.mkdir()
        source_file = source_dir / self.file.name
        self.file.replace(source_file)
        manifest = [runner.inspect_csv(source_file, self.key, r"source_crm\cust_info.csv", self.header)]
        prepared, stage_dir = runner.prepare_linux_bulk_files(self.root, manifest)
        try:
            self.assertEqual(prepared[0]["row_count"], 1)
            self.assertGreater(prepared[0]["bulk_file_size"], 0)
            self.assertEqual(len(prepared[0]["bulk_sha256"]), 64)
            sidecar = self.root / Path(prepared[0]["bulk_relative_path"])
            with sidecar.open("r", encoding="utf-16", newline="") as stream:
                self.assertEqual(list(csv.reader(stream))[1][2], "José")
        finally:
            shutil.rmtree(stage_dir, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
