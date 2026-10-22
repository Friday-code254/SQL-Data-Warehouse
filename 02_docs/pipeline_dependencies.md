# Pipeline dependencies and failure boundaries

## Dependency graph

```mermaid
flowchart TD
  A[Six complete CSV inputs] --> B[Python checks config, path, encoding, header, row width, checksum]
  S[Manual run or scheduled wrapper] --> B
  B -->|Linux SQL Server| C[Create hash-verified UTF-16 sidecars]
  B --> D[Open one pipeline run]
  C --> D
  D --> E[Stage and verify all six source files]
  E -->|All pass| F[Commit Bronze batches and source manifest]
  E -->|Any source failure| X[Record FAILED; Gold untouched]
  F --> G[Silver validate, reject, and upsert complete snapshot]
  G -->|Failure| Y[Rollback Silver transaction; Gold untouched]
  G -->|Success| H[Gold dimension and fact publication]
  H --> I[Reconciliation]
  I --> J[Named data-quality gates]
  J -->|Critical failure| K[Rollback Gold; persist failed run and test outcomes]
  J -->|Pass| L[Commit Gold; mark run SUCCEEDED]
  L --> M[Curated 05_analytics queries]
```

## Stage contracts

| Stage | Reads | Writes | Transaction / publication rule |
| --- | --- | --- | --- |
| Python preflight | `etl.source_config`, six configured files | A manifest in memory; Linux sidecars for the run | No warehouse rows are changed. When SQL Server is reachable, preflight failures are recorded. |
| Bronze | Validated manifest, original files, optional sidecars | Append-only Bronze batches, `etl.source_file_history`, `etl.pipeline_source_files`, per-table logs | Hashes and row counts are verified for all six files before the Bronze transaction commits. A repeated checksum reuses its original batch. |
| Silver | Bronze batches registered for this run | Current CRM/ERP Silver snapshot and reason-coded rejects | The complete snapshot is transformed in a transaction. Invalid rows are excluded with hashed fingerprints and reason codes. |
| Gold | Accepted Silver snapshot | Stable SCD2 dimensions, dense date dimension, fact snapshot | Gold load, reconciliation, and quality gates run in one transaction. Critical failures roll back publication. |
| Analytics | Committed Gold dimensions and facts | Query result sets only | Scripts are read-only and define their grain and metric calculations in comments. |

Run-level state is in `etl.pipeline_runs`; stage and per-table state is in `etl.table_load_logs`. Source content is never copied into failure summaries or rejection logs. Gold results are available only after the critical gates pass.
