"""Run a .sql file against the local MySQL server and print each SELECT's result.

Credentials are read from .env in the repo root (gitignored, see .env.example).
Statements are separated by ';'. The placeholder {DATA_DIR} is replaced with the
absolute path of data/processed/mysql (used by the load script).

Usage:
    python scripts/run_mysql.py sql/mysql/00_schema_and_load.sql
"""

import os
import sys
from pathlib import Path

import mysql.connector
import pandas as pd
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = (ROOT / "data" / "processed" / "mysql").as_posix()


def connect(database: str | None = None):
    load_dotenv(ROOT / ".env")
    if not os.getenv("MYSQL_PASSWORD"):
        sys.exit("MYSQL_PASSWORD is not set. Copy .env.example to .env and fill it in.")
    return mysql.connector.connect(
        host=os.getenv("MYSQL_HOST", "localhost"),
        port=int(os.getenv("MYSQL_PORT", "3306")),
        user=os.getenv("MYSQL_USER", "root"),
        password=os.getenv("MYSQL_PASSWORD"),
        database=database,
        allow_local_infile=True,          # needed for LOAD DATA LOCAL INFILE
        allow_local_infile_in_path=DATA_DIR,
    )


def split_statements(sql: str) -> list[str]:
    return [s.strip() for s in sql.split(";") if s.strip()]


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    pd.set_option("display.width", 250)
    pd.set_option("display.max_columns", 30)
    path = Path(sys.argv[1])
    sql = path.read_text(encoding="utf-8").replace("{DATA_DIR}", DATA_DIR)

    database = None if "CREATE DATABASE" in sql else os.getenv("MYSQL_DATABASE", "imdb_series")
    con = connect(database)
    cur = con.cursor()
    for stmt in split_statements(sql):
        header = [ln for ln in stmt.splitlines() if ln.strip().startswith("--")]
        if header:
            print("\n" + "\n".join(header))
        cur.execute(stmt)
        if cur.with_rows:
            df = pd.DataFrame(cur.fetchall(), columns=cur.column_names)
            print(df.to_string(index=False, max_rows=60))
        elif cur.rowcount and cur.rowcount > 0:
            print(f"   rows affected: {cur.rowcount:,}")
    con.commit()
    con.close()


if __name__ == "__main__":
    main()
