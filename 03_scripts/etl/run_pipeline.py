#!/usr/bin/env python3
"""Preflight CSV snapshots and invoke the SQL Server warehouse pipeline."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
from contextlib import closing
from typing import Iterable
import uuid

class InputError(ValueError):
    """A controlled source-file validation error safe to show in run output."""

    def __init__(self, message: str, source_key: str = "dataset_root", reason_code: str = "INVALID_INPUT") -> None:
        super().__init__(message)
        self.source_key = source_key
        self.reason_code = reason_code


def inspect_csv(path: Path, source_key: str, relative_path: str, expected_header: str) -> dict:
    """Validate the header and CSV shape; return non-sensitive file metadata."""
    if not path.is_file():
        raise InputError(f"Required source file is missing: {source_key}", source_key, "MISSING_FILE")
    digest = hashlib.sha256()
    last_byte = b""
    previous_byte = None
    saw_crlf = False
    saw_lf = False
    try:
        with path.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
                for index, value in enumerate(block):
                    if value == 10:
                        is_crlf = block[index - 1] == 13 if index else previous_byte == 13
                        saw_crlf = saw_crlf or is_crlf
                        saw_lf = saw_lf or not is_crlf
                last_byte = block[-1:]
                previous_byte = block[-1]
        row_count = 0
        with path.open("r", encoding="utf-8-sig", newline="") as stream:
            reader = csv.reader(stream, strict=True)
            header = next(reader, None)
            expected = expected_header.split(",")
            if header != expected:
                raise InputError(f"Unexpected CSV header or column order: {source_key}", source_key, "HEADER_MISMATCH")
            for line_number, row in enumerate(reader, start=2):
                if len(row) != len(expected):
                    raise InputError(f"CSV column count mismatch in {source_key} at line {line_number}", source_key, "COLUMN_COUNT_MISMATCH")
                row_count += 1
    except UnicodeDecodeError as exc:
        raise InputError(f"CSV is not valid UTF-8: {source_key}", source_key, "INVALID_ENCODING") from exc
    except csv.Error as exc:
        raise InputError(f"Malformed CSV structure in {source_key}", source_key, "MALFORMED_CSV") from exc
    except OSError as exc:
        raise InputError(f"Source file is unreadable: {source_key}", source_key, "UNREADABLE_FILE") from exc
    if row_count == 0:
        raise InputError(f"Required source file has no data rows: {source_key}", source_key, "EMPTY_FILE")
    if last_byte != b"\n":
        raise InputError(
            f"CSV must end with a line terminator for SQL Server bulk loading: {source_key}",
            source_key,
            "MISSING_FINAL_LINE_TERMINATOR",
        )
    if saw_crlf and saw_lf:
        raise InputError(
            f"CSV mixes CRLF and LF line terminators: {source_key}",
            source_key,
            "MIXED_LINE_TERMINATORS",
        )
    line_terminator = "CRLF" if saw_crlf else "LF"
    return {
        "source_key": source_key,
        "relative_path": relative_path.replace("/", "\\"),
        "file_name": path.name,
        "sha256": digest.hexdigest().upper(),
        "file_size": path.stat().st_size,
        "row_count": row_count,
        "column_count": len(expected_header.split(",")),
        "line_terminator": line_terminator,
        "header": expected_header,
    }


def load_source_config(connection) -> list[dict]:
    """Read paths and schema expectations from the central SQL configuration table."""
    cursor = connection.cursor()
    cursor.execute("SELECT source_key,relative_path,expected_header,expected_columns FROM etl.source_config WHERE is_required=1 ORDER BY source_key")
    config = []
    for row in cursor.fetchall():
        source_key, relative_path, header, columns = (str(value) for value in row)
        expected = header.split(",")
        if len(expected) != int(columns) or any(not item for item in expected):
            raise InputError("Source configuration has an inconsistent header/column count.", str(source_key), "INVALID_SOURCE_CONFIG")
        path = Path(relative_path.replace("\\", "/"))
        if path.is_absolute() or ".." in path.parts:
            raise InputError("Source configuration path must stay under the dataset root.", str(source_key), "INVALID_SOURCE_PATH")
        config.append({"source_key": str(source_key), "relative_path": path.as_posix(), "header": header, "column_count": int(columns)})
    if not config:
        raise InputError("No required source files are configured in SQL Server.", "etl.source_config", "MISSING_SOURCE_CONFIG")
    return config


def build_manifest(dataset_root: Path, source_config: list[dict]) -> list[dict]:
    """Validate all source files using the active SQL-side configuration."""
    try:
        root = dataset_root.expanduser().resolve(strict=True)
    except OSError as exc:
        raise InputError("Configured dataset directory is missing or unreadable.", "dataset_root", "DATASET_ROOT_UNAVAILABLE") from exc
    if not root.is_dir():
        raise InputError("Configured dataset directory is missing or unreadable.", "dataset_root", "DATASET_ROOT_UNAVAILABLE")
    files = []
    for item in source_config:
        source_key, relative_path, header = item["source_key"], item["relative_path"], item["header"]
        if len(header.split(",")) != item["column_count"]:
            raise InputError("Source configuration has an inconsistent header/column count.", source_key, "INVALID_SOURCE_CONFIG")
        path = (root / Path(relative_path)).resolve(strict=False)
        if not path.is_relative_to(root):
            raise InputError(f"Configured source path escapes dataset root: {source_key}", source_key, "PATH_OUTSIDE_ROOT")
        files.append(inspect_csv(path, source_key, relative_path, header))
    return files


def prepare_linux_bulk_files(dataset_root: Path, manifest: list[dict]) -> tuple[list[dict], Path]:
    """Prepare hash-audited UTF-16 CSV sidecars for SQL Server on Linux."""
    root = dataset_root.expanduser().resolve(strict=True)
    stage_root = (root / ".sql_bulk_stage").resolve(strict=False)
    if not stage_root.is_relative_to(root):
        raise InputError("SQL bulk staging path escapes the dataset directory.", ".sql_bulk_stage", "INVALID_STAGE_PATH")
    stage_dir = stage_root / uuid.uuid4().hex
    try:
        stage_dir.mkdir(parents=True, exist_ok=False)
        prepared = []
        for item in manifest:
            source_relative_path = item["relative_path"].replace("\\", "/")
            source_path = (root / Path(source_relative_path)).resolve(strict=True)
            if not source_path.is_relative_to(root):
                raise InputError(f"Configured source path escapes dataset root: {item['source_key']}", item["source_key"], "PATH_OUTSIDE_ROOT")
            destination = stage_dir / f"{item['source_key']}.utf16.csv"
            rows_written = 0
            with source_path.open("r", encoding="utf-8-sig", newline="") as source, destination.open(
                "w", encoding="utf-16", newline=""
            ) as target:
                reader = csv.reader(source, strict=True)
                writer = csv.writer(target, lineterminator="\r\n")
                for row in reader:
                    writer.writerow(row)
                    rows_written += 1
            if rows_written != item["row_count"] + 1:
                raise InputError(
                    f"Source file changed while preparing SQL bulk data: {item['source_key']}",
                    item["source_key"],
                    "SOURCE_CHANGED_DURING_STAGING",
                )
            digest = hashlib.sha256()
            size = 0
            with destination.open("rb") as staged:
                for block in iter(lambda: staged.read(1024 * 1024), b""):
                    digest.update(block)
                    size += len(block)
            relative_stage_path = Path(".sql_bulk_stage") / stage_dir.name / destination.name
            prepared.append({
                **item,
                "bulk_relative_path": relative_stage_path.as_posix(),
                "bulk_sha256": digest.hexdigest().upper(),
                "bulk_file_size": size,
            })
        return prepared, stage_dir
    except (OSError, UnicodeError, csv.Error) as exc:
        shutil.rmtree(stage_dir, ignore_errors=True)
        raise InputError("Unable to prepare UTF-16 SQL bulk files.", ".sql_bulk_stage", "BULK_STAGE_PREPARATION_FAILED") from exc
    except Exception:
        shutil.rmtree(stage_dir, ignore_errors=True)
        raise


def read_env_file(path: Path) -> None:
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def connection_string() -> str:
    driver = os.getenv("SQLSERVER_DRIVER", "ODBC Driver 18 for SQL Server")
    server = os.getenv("SQLSERVER_SERVER", "localhost")
    database = os.getenv("SQLSERVER_DATABASE", "DataWarehouse")
    encrypt = os.getenv("SQLSERVER_ENCRYPT", "yes")
    trust = os.getenv("SQLSERVER_TRUST_CERTIFICATE", "yes")
    trusted = os.getenv("SQLSERVER_TRUSTED_CONNECTION", "yes").lower() in {"yes", "true", "1"}
    parts = [f"DRIVER={{{driver}}}", f"SERVER={server}", f"DATABASE={database}", f"Encrypt={encrypt}", f"TrustServerCertificate={trust}"]
    if trusted:
        parts.append("Trusted_Connection=yes")
    else:
        def quote(value: str) -> str:
            return "{" + value.replace("}", "}}") + "}"
        parts.extend((f"UID={quote(os.getenv('SQLSERVER_USER', ''))}", f"PWD={quote(os.getenv('SQLSERVER_PASSWORD', ''))}"))
    return ";".join(parts) + ";"


def invoke_sql(connection, dataset_root: Path, run_mode: str, manifest: list[dict]) -> int:
    root_for_sql = os.getenv("SQLSERVER_DATASET_ROOT", str(dataset_root.resolve()))
    sql = "EXEC etl.load_warehouse @dataset_root=?, @run_mode=?, @manifest_json=?"
    cursor = connection.cursor()
    cursor.execute(sql, root_for_sql, run_mode.upper(), json.dumps(manifest, separators=(",", ":")))
    while True:
        if cursor.description:
            rows = cursor.fetchall()
            for row in rows:
                print(" | ".join(str(value) for value in row))
        if not cursor.nextset():
            break
    return 0


def sql_server_is_linux(connection) -> bool:
    cursor = connection.cursor()
    cursor.execute("SELECT CASE WHEN @@VERSION LIKE N'%Linux%' THEN 1 ELSE 0 END")
    return bool(cursor.fetchone()[0])


def record_preflight_failure(connection, source_key: str, reason_code: str, run_mode: str) -> None:
    """Persist preflight failures when SQL Server is configured and reachable."""
    try:
        cursor = connection.cursor()
        cursor.execute("EXEC etl.record_preflight_failure @source_key=?, @reason_code=?, @run_mode=?", source_key, reason_code, run_mode.upper())
        while True:
            if cursor.description:
                for row in cursor.fetchall():
                    print(" | ".join(str(value) for value in row))
            if not cursor.nextset():
                break
    except Exception:
        print("Preflight failure could not be written to SQL Server; confirm the database is installed and reachable.", file=sys.stderr)


def main(argv: Iterable[str] | None = None) -> int:
    project_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description="Run a validated full-snapshot warehouse load.")
    parser.add_argument("--dataset-root", type=Path, default=project_root / "01_datasets", help="Directory containing source_crm and source_erp")
    parser.add_argument("--mode", choices=("full", "incremental"), default="full")
    parser.add_argument("--env-file", type=Path, default=project_root / ".env")
    args = parser.parse_args(argv)
    read_env_file(args.env_file)
    try:
        import pyodbc
    except ImportError:
        print("Install requirements.txt (pyodbc) before running the SQL pipeline.", file=sys.stderr)
        return 2
    try:
        with closing(pyodbc.connect(connection_string(), autocommit=True)) as connection:
            stage_dir = None
            try:
                source_config = load_source_config(connection)
                manifest = build_manifest(args.dataset_root, source_config)
                if sql_server_is_linux(connection):
                    manifest, stage_dir = prepare_linux_bulk_files(args.dataset_root, manifest)
            except InputError as exc:
                record_preflight_failure(connection, exc.source_key, exc.reason_code, args.mode)
                print(f"Pipeline preflight failed: {exc}", file=sys.stderr)
                return 2
            print(f"Preflight passed for {len(manifest)} CSV files ({sum(item['row_count'] for item in manifest):,} rows).")
            try:
                return invoke_sql(connection, args.dataset_root, args.mode, manifest)
            finally:
                if stage_dir is not None:
                    shutil.rmtree(stage_dir, ignore_errors=True)
    except Exception as exc:  # Driver errors may include paths or values; keep console output generic.
        print(f"Pipeline execution failed. Check etl.pipeline_runs for the persisted error summary. ({type(exc).__name__})", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
