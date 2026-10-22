"""Check required portfolio deliverables and per-query documentation."""
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
REQUIRED_FILES = (
    ".env.example",
    "LICENSE",
    "README.md",
    "00_setup/install.sql",
    "00_setup/development_reset.sql",
    "02_docs/architecture.md",
    "02_docs/column_lineage.md",
    "02_docs/data_catalog.md",
    "02_docs/design_decisions.md",
    "02_docs/pipeline_dependencies.md",
    "03_scripts/etl/run_pipeline.py",
    "04_tests/smoke_test.sql",
    "07_orchestration/run_pipeline.ps1",
    ".github/workflows/warehouse-ci.yml",
)
REQUIRED_QUERY_NOTES = (
    "Business question:",
    "Metric definitions:",
    "Interpretation:",
)


def main() -> int:
    missing = [name for name in REQUIRED_FILES if not (ROOT / name).is_file()]
    analytics = sorted((ROOT / "05_analytics").glob("*.sql"))
    if len(analytics) < 6:
        missing.append("at least six SQL files under 05_analytics/")

    undocumented = []
    for query in analytics:
        text = query.read_text(encoding="utf-8-sig")
        if any(note not in text for note in REQUIRED_QUERY_NOTES):
            undocumented.append(query.relative_to(ROOT).as_posix())

    committed_env = (ROOT / ".env").exists()
    if missing or undocumented or committed_env:
        if missing:
            print("Missing required deliverables:")
            for name in missing:
                print(f"  - {name}")
        if undocumented:
            print("Analytics queries missing question/metric/interpretation notes:")
            for name in undocumented:
                print(f"  - {name}")
        if committed_env:
            print("A local .env file must not be committed.")
        return 1

    print(f"Project structure and documentation checks passed ({len(analytics)} analytics queries).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
