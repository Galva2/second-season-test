"""Export the clean DuckDB tables to CSV files for loading into MySQL.

DuckDB list columns (genre_list, writer_set) have no MySQL equivalent, so they
are split into normalized bridge tables:
    series_genre   (series_id, genre)            one row per series per genre
    season_writer  (series_id, season, writer_id) one row per season per writer

CSV format: comma-separated, header row, text quoted with ", NULL = empty field.
Booleans are written as 0/1. The MySQL loader (sql/mysql/00_schema_and_load.sql)
turns empty fields back into NULL with NULLIF.

Usage:
    python scripts/export_for_mysql.py
"""

from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
PROCESSED = ROOT / "data" / "processed"
OUT = PROCESSED / "mysql"

EXPORTS = {
    "series": """
        SELECT series_id, title, startYear AS start_year, endYear AS end_year,
               is_ended::INT AS is_ended, genres,
               n_seasons_max, n_seasons_listed, n_seasons_qualifying
        FROM series""",
    "series_genre": """
        SELECT series_id, unnest(genre_list) AS genre FROM series""",
    "season": """
        SELECT series_id, season, season_year, n_episodes, n_rated, rated_share,
               median_votes, total_votes::BIGINT AS total_votes, rating, rating_weighted,
               n_ep_with_writers, n_writers,
               is_qualifying::INT AS is_qualifying, is_current_year::INT AS is_current_year
        FROM season""",
    "season_writer": """
        SELECT series_id, season, unnest(writer_set) AS writer_id FROM season""",
    "episode": """
        SELECT episode_id, series_id, season, episode, episode_year, rating, votes
        FROM episode_clean""",
}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect()
    for t in ["series", "season", "episode_clean"]:
        con.execute(f"CREATE VIEW {t} AS SELECT * FROM '{(PROCESSED / f'{t}.parquet').as_posix()}'")

    for name, query in EXPORTS.items():
        dst = (OUT / f"{name}.csv").as_posix()
        con.execute(f"COPY ({query}) TO '{dst}' (HEADER, DELIMITER ',', QUOTE '\"', ESCAPE '\"', NULLSTR '')")
        n = con.execute(f"SELECT count(*) FROM ({query})").fetchone()[0]
        print(f"{name:14s} {n:>10,} rows -> {dst}")


if __name__ == "__main__":
    main()
