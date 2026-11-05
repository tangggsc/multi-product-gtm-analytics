"""Load a hand-checkable fixture into the local DuckDB database.

Creates the `raw` schema (seven raw source tables) and the `expected`
schema (the independent expected-results ledger), then loads the fixture
CSVs. Raw tables are rebuilt from scratch on every run, so reruns are
idempotent.

Usage (from the repository root):
    uv run python data_generation/load_fixtures.py [--fixture e01_counting_units]
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path

import duckdb

REPO_ROOT = Path(__file__).resolve().parent.parent
GENERATION_DIR = REPO_ROOT / "data_generation"
DEFAULT_DB_PATH = REPO_ROOT / "gtm_analytics.duckdb"

RAW_TABLES = [
    "raw_crm_accounts",
    "raw_users",
    "raw_workspaces",
    "raw_workspace_memberships",
    "raw_event_deliveries",
    "raw_billing_customers",
    "raw_billing_transactions",
]


def load_fixture(fixture: str, db_path: Path) -> dict[str, int]:
    fixture_dir = GENERATION_DIR / "fixtures" / fixture
    if not fixture_dir.is_dir():
        raise SystemExit(f"Fixture not found: {fixture_dir}")

    con = duckdb.connect(str(db_path))
    try:
        con.execute("set TimeZone = 'UTC'")
        con.execute((GENERATION_DIR / "raw_schema.sql").read_text())

        row_counts: dict[str, int] = {}
        for table in RAW_TABLES:
            csv_path = fixture_dir / f"{table}.csv"
            if not csv_path.exists():
                raise SystemExit(f"Missing fixture file: {csv_path}")
            # COPY casts each CSV field to the column type declared in
            # raw_schema.sql; empty fields load as NULL.
            con.execute(f"copy raw.{table} from '{csv_path.as_posix()}' (header true)")
            row_counts[f"raw.{table}"] = con.execute(
                f"select count(*) from raw.{table}"
            ).fetchone()[0]

        con.execute("create schema if not exists expected")
        con.execute(
            """
            create or replace table expected.paying_counts (
                fixture         varchar,
                as_of           timestamptz,
                metric          varchar,
                product         varchar,
                expected_value  integer,
                rationale       varchar
            )
            """
        )
        ledger_path = fixture_dir / "expected_paying_counts.csv"
        con.execute(
            f"""
            insert into expected.paying_counts
            select ?, as_of, metric, product, expected_value, rationale
            from read_csv('{ledger_path.as_posix()}', header = true, columns = {{
                'as_of': 'timestamptz', 'metric': 'varchar', 'product': 'varchar',
                'expected_value': 'integer', 'rationale': 'varchar'
            }})
            """,
            [fixture],
        )
        row_counts["expected.paying_counts"] = con.execute(
            "select count(*) from expected.paying_counts"
        ).fetchone()[0]
        return row_counts
    finally:
        con.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--fixture", default="e01_counting_units")
    parser.add_argument(
        "--db-path",
        type=Path,
        default=Path(os.environ.get("GTM_DUCKDB_PATH", DEFAULT_DB_PATH)),
    )
    args = parser.parse_args()

    counts = load_fixture(args.fixture, args.db_path)
    print(f"Loaded fixture '{args.fixture}' into {args.db_path}")
    for table, n in counts.items():
        print(f"  {table}: {n} rows")


if __name__ == "__main__":
    main()
