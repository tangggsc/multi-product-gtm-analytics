# 0001: Toolchain versions

Status: accepted, 2026-11-04

## Decision

| Component | Pinned version | Where pinned |
| --- | --- | --- |
| Python | 3.12 (minor only) | `.python-version`, `pyproject.toml` (`>=3.12,<3.13`) |
| dbt Core | 1.12.6 | `pyproject.toml`, exact; full tree in `uv.lock` |
| dbt-duckdb | 1.11.1 | same |
| DuckDB | 2.0.0 | same |

Dependencies are managed with uv. `uv.lock` pins every transitive dependency.

## Compatibility evidence (PyPI metadata, checked 2026-11-04)

- dbt-core 1.12.6, dbt-adapters 1.24.5, dbt-common 1.39.0 and dbt-duckdb 1.11.1 declare Python 3.10 to 3.14.
- duckdb 2.0.0 requires Python >= 3.11 and declares 3.11 to 3.15.
- The supported range shared by all of them is therefore 3.11 to 3.14.
- dbt-duckdb declares `duckdb>=1.0.0` with no upper bound, so its compatibility with DuckDB 2.0.0 is not declared explicitly. It was verified locally: `dbt build` completes with seeds, source tests and singular tests passing.

## Why Python 3.12

- It is inside the shared range with margin on both sides.
- It gets security fixes until October 2028, compared with October 2027 for 3.11.
- DuckDB publishes a cp312 abi3 wheel for macOS arm64.

## Why dbt Core v1 rather than dbt v2

dbt v2 (`dbt` / `dbt-oss` 2.0.x) is now the default for new installations, and the `dbt-core` package name is planned for deprecation. However, nothing checked states that dbt-duckdb supports v2, and dbt-duckdb pins `dbt-adapters<2` and `dbt-common<2`. dbt Core 1.12 with dbt-duckdb is the stable, documented path for local DuckDB.

Revisit this when dbt-duckdb, or DuckDB support in dbt v2, is documented. The upgrade should be its own PR, verified by a full `dbt build` against the same fixtures.

## Upgrade rule

Change versions together in a dedicated PR. Re-check the compatibility metadata, regenerate `uv.lock`, and run the full build from a clean environment before merging.
