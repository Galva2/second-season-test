"""Run a numbered .sql file against the processed Parquet tables and print results.

The tables are exposed as views named basics, episode, ratings, crew so the
.sql files stay short and readable. Statements are separated by ';' and each
SELECT's result is printed under the comment line(s) that precede it.

Usage:
    python scripts/run_sql.py sql/01_profile_basics.sql
"""

import sys
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
PROCESSED = ROOT / "data" / "processed"
TABLES = ["basics", "episode", "ratings", "crew"]
# Built by sql/05_build_tables.sql; exposed only once they exist.
CLEAN_TABLES = ["series", "season", "episode_clean"]


def connect() -> duckdb.DuckDBPyConnection:
    con = duckdb.connect()
    for t in TABLES + CLEAN_TABLES:
        path = PROCESSED / f"{t}.parquet"
        if path.exists():
            con.execute(f"CREATE VIEW {t} AS SELECT * FROM '{path.as_posix()}'")
    return con


def split_statements(sql: str) -> list[str]:
    return [s.strip() for s in sql.split(";") if s.strip()]


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")  # Windows console defaults to cp1252
    path = Path(sys.argv[1])
    con = connect()
    for stmt in split_statements(path.read_text(encoding="utf-8")):
        header = [ln for ln in stmt.splitlines() if ln.strip().startswith("--")]
        print("\n" + "\n".join(header) if header else "")
        rel = con.sql(stmt)
        if rel is not None:
            rel.show(max_rows=60, max_width=250)


if __name__ == "__main__":
    main()
