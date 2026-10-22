# Scheduled pipeline runs

The supported automation entry point is the existing Python runner. Schedule the PowerShell wrapper on Windows or invoke the Python command from another scheduler. The wrapper preserves the runner's exit code and writes a timestamped run log under `logs/`; logs are ignored by Git.

## Windows Task Scheduler

1. Complete the one-time setup in the repository [README](../README.md), including `.env`, Python dependencies, database installation, and one successful `full` run.
2. Open Task Scheduler and create a task using the account that can read `.env` and the dataset and connect to SQL Server.
3. Set the action's program to `powershell.exe`.
4. Set arguments to `-NoProfile -ExecutionPolicy Bypass -File "C:\path\to\sql-data-warehouse-project\07_orchestration\run_pipeline.ps1" -Mode incremental`.
5. Set **Start in** to the repository root. Choose a schedule that matches when a complete source snapshot is available.
6. In task settings, enable **Stop the task if it runs longer than** an agreed operational limit and configure retries according to your recovery policy.

Use `-Mode full` for an intentional full Silver snapshot rebuild. Use `-Mode incremental` for routine complete-snapshot replays; hash-identical inputs are idempotent. Both modes require all six source files.

The task account needs the same SQL permissions and SQL Server dataset-path access as an interactive run. When SQL authentication is used, restrict `.env` to that account and do not place credentials in the task arguments. A nonzero task exit code indicates a failed run; inspect the timestamped log and `etl.pipeline_runs` for the sanitized database error summary.

## Other schedulers

Cron, Jenkins, or another scheduler can call `python 03_scripts/etl/run_pipeline.py --mode incremental` from the repository root. Provide the connection settings through the protected `.env` file or environment variables and preserve the process exit code. Schedule only after the full source snapshot has arrived; partial snapshots are rejected by preflight.
