# Changelog

## Engineering upgrade

- Replaced database-dropping bootstrap with repeatable setup and a separate development reset.
- Added legacy-table preservation and workload-aligned migrations/indexes.
- Added configurable, validated CSV preflight, SQL-side checksum verification, staging, and append-only Bronze batches.
- Added run, file, table, rejection, quality, reconciliation, and performance audit tables.
- Added one-command pipeline orchestration with transactional Gold publication and persistent failure handling.
- Reworked Silver conversions, explicit correction codes, deduplication, reason-coded rejects, and snapshot-aware upserts.
- Materialized Gold dimensions/facts, stable surrogate keys, SCD Type 2 versions, role-playing date keys, constraints, and indexes.
- Added unit, SQL smoke, acceptance, and performance benchmark scripts and architecture/source lineage docs.
- Added repeatable Linux UTF-16 bulk sidecars, sidecar hash verification, and a shared read-only Docker dataset mount.
- Added install-time coverage and corrected SQL Server parser, migration, key-column, and source line-ending issues found during SQL Server 2022 validation.

## Portfolio phase

- Added six documented Gold analytics queries for monthly growth, product/category performance, customer lifetime behavior, country/segment sales, order value, and shipping trends.
- Added a Task Scheduler wrapper with run logs and setup guidance.
- Added GitHub Actions CI for SQLFluff, Python unit tests, SQL Server 2022 integration, smoke checks, all analytics queries, migrations, SCD2, replay, and failure isolation.
- Added column-level source lineage and an explicit pipeline dependency and failure-boundary guide.
- Expanded fresh setup, analytics, automation, CI, and safe-reset instructions.
- Fixed Linux UTF-16 sidecar preparation for source paths stored with Windows separators.
- Fixed monthly order-value analytics to avoid invalid attributes on the unknown date member.
- Expanded local-only environment-file ignore patterns while preserving `.env.example`.
- Added reason-level sales reject amount reconciliation and a critical zero-residual source-to-Gold amount bridge, while keeping business disposition separate from accounting balance.
