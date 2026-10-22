"""Convert the raw IMDb .tsv.gz files into typed Parquet files in data/processed/.

Why: Parquet is columnar and compressed, so every later query is much faster
than re-parsing gzipped text.

How each file is read:
  - nullstr='\\N'  -> IMDb's null marker becomes a real NULL, never the string "\\N"
  - quote=''       -> IMDb TSV does not quote fields; some titles contain a bare "
                      character, which would otherwise break row parsing
  - all_varchar    -> read everything as text first, then TRY_CAST to numbers so we
                      can COUNT values that fail to convert instead of hiding them

Usage:
    python scripts/build_parquet.py
"""

from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw"
OUT = ROOT / "data" / "processed"

# table name -> {column: target type}. Columns not listed stay VARCHAR.
SCHEMAS = {
    "basics": {
        "isAdult": "INTEGER",
        "startYear": "INTEGER",
        "endYear": "INTEGER",
        "runtimeMinutes": "INTEGER",
    },
    "episode": {
        "seasonNumber": "INTEGER",
        "episodeNumber": "INTEGER",
    },
    "ratings": {
        "averageRating": "DOUBLE",
        "numVotes": "INTEGER",
    },
    "crew": {},
}


def build(con: duckdb.DuckDBPyConnection, table: str, casts: dict[str, str]) -> None:
    src = (RAW / f"title.{table}.tsv.gz").as_posix()
    dst = (OUT / f"{table}.parquet").as_posix()

    con.execute(f"""
        CREATE OR REPLACE TEMP TABLE raw_{table} AS
        SELECT * FROM read_csv('{src}', delim='\t', header=true, quote='', escape='',
                               nullstr='\\N', all_varchar=true)
    """)
    columns = [r[0] for r in con.execute(f"DESCRIBE raw_{table}").fetchall()]

    select_list = ",\n".join(
        f'TRY_CAST("{c}" AS {casts[c]}) AS "{c}"' if c in casts else f'"{c}"'
        for c in columns
    )
    con.execute(f"COPY (SELECT {select_list} FROM raw_{table}) TO '{dst}' (FORMAT parquet)")

    n_rows = con.execute(f"SELECT count(*) FROM raw_{table}").fetchone()[0]
    print(f"{table:8s} {n_rows:>12,} rows -> {dst}")
    # A cast failure = raw text was present (not \N) but could not become a number.
    for c, t in casts.items():
        failed = con.execute(f"""
            SELECT count(*) FROM raw_{table}
            WHERE "{c}" IS NOT NULL AND TRY_CAST("{c}" AS {t}) IS NULL
        """).fetchone()[0]
        print(f"           cast failures {c} -> {t}: {failed:,}")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect()
    for table, casts in SCHEMAS.items():
        build(con, table, casts)


if __name__ == "__main__":
    main()
