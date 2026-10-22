-- 00_schema_and_load.sql  (MySQL 8)
-- Purpose: create the imdb_series database and load the clean tables exported by
-- scripts/export_for_mysql.py. Run with: python scripts/run_mysql.py sql/mysql/00_schema_and_load.sql
-- {DATA_DIR} is replaced by run_mysql.py with the absolute path of data/processed/mysql.
--
-- NULL handling: the CSVs write NULL as an empty field. Nullable columns are read into
-- @variables and converted with NULLIF(@x, '') so an empty field becomes a real NULL.

CREATE DATABASE IF NOT EXISTS imdb_series CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE imdb_series;

DROP TABLE IF EXISTS season_writer;
DROP TABLE IF EXISTS series_genre;
DROP TABLE IF EXISTS episode;
DROP TABLE IF EXISTS season;
DROP TABLE IF EXISTS series;

-- One row per scripted tvSeries
CREATE TABLE series (
    series_id             VARCHAR(12)  NOT NULL PRIMARY KEY,
    title                 VARCHAR(500) NOT NULL,
    start_year            SMALLINT     NULL,
    end_year              SMALLINT     NULL,
    is_ended              TINYINT(1)   NOT NULL,   -- endYear not null and <= 2026 (decision #9)
    genres                VARCHAR(100) NOT NULL,   -- original comma list, see series_genre
    n_seasons_max         SMALLINT     NULL,       -- highest numbered season (Q2 outcome)
    n_seasons_listed      SMALLINT     NOT NULL,
    n_seasons_qualifying  SMALLINT     NOT NULL
);

-- One row per series per genre (normalized from the comma list)
CREATE TABLE series_genre (
    series_id  VARCHAR(12) NOT NULL,
    genre      VARCHAR(20) NOT NULL,
    PRIMARY KEY (series_id, genre),
    KEY idx_genre (genre)
);

-- One row per series per numbered season (1..100)
CREATE TABLE season (
    series_id          VARCHAR(12) NOT NULL,
    season             SMALLINT    NOT NULL,
    season_year        SMALLINT    NULL,        -- earliest episode year in the season
    n_episodes         INT         NOT NULL,
    n_rated            INT         NOT NULL,
    rated_share        DOUBLE      NOT NULL,
    median_votes       DOUBLE      NULL,        -- median numVotes over rated episodes
    total_votes        BIGINT      NULL,
    rating             DOUBLE      NULL,        -- simple mean of episode ratings (decision #13)
    rating_weighted    DOUBLE      NULL,        -- robustness check only
    n_ep_with_writers  INT         NOT NULL,
    n_writers          INT         NULL,
    is_qualifying      TINYINT(1)  NULL,        -- >= 80% rated AND median_votes >= 20 (#6, #7)
    is_current_year    TINYINT(1)  NULL,        -- season_year >= 2026 (#14)
    PRIMARY KEY (series_id, season)
);

-- One row per season per writer (normalized from the writer set)
CREATE TABLE season_writer (
    series_id  VARCHAR(12) NOT NULL,
    season     SMALLINT    NOT NULL,
    writer_id  VARCHAR(12) NOT NULL,
    PRIMARY KEY (series_id, season, writer_id)
);

-- One row per episode in a numbered season (episode 0 excluded, #12)
CREATE TABLE episode (
    episode_id    VARCHAR(12) NOT NULL PRIMARY KEY,
    series_id     VARCHAR(12) NOT NULL,
    season        SMALLINT    NOT NULL,
    episode       INT         NOT NULL,
    episode_year  SMALLINT    NULL,
    rating        DOUBLE      NULL,
    votes         INT         NULL,
    KEY idx_series_season (series_id, season, episode)
);

LOAD DATA LOCAL INFILE '{DATA_DIR}/series.csv' INTO TABLE series
    CHARACTER SET utf8mb4
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
    LINES TERMINATED BY '\n' IGNORE 1 LINES
    (series_id, title, @start_year, @end_year, is_ended, genres,
     @n_seasons_max, n_seasons_listed, n_seasons_qualifying)
    SET start_year    = NULLIF(@start_year, ''),
        end_year      = NULLIF(@end_year, ''),
        n_seasons_max = NULLIF(@n_seasons_max, '');

LOAD DATA LOCAL INFILE '{DATA_DIR}/series_genre.csv' INTO TABLE series_genre
    CHARACTER SET utf8mb4
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
    LINES TERMINATED BY '\n' IGNORE 1 LINES
    (series_id, genre);

LOAD DATA LOCAL INFILE '{DATA_DIR}/season.csv' INTO TABLE season
    CHARACTER SET utf8mb4
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
    LINES TERMINATED BY '\n' IGNORE 1 LINES
    (series_id, season, @season_year, n_episodes, n_rated, rated_share,
     @median_votes, @total_votes, @rating, @rating_weighted,
     n_ep_with_writers, @n_writers, @is_qualifying, @is_current_year)
    SET season_year     = NULLIF(@season_year, ''),
        median_votes    = NULLIF(@median_votes, ''),
        total_votes     = NULLIF(@total_votes, ''),
        rating          = NULLIF(@rating, ''),
        rating_weighted = NULLIF(@rating_weighted, ''),
        n_writers       = NULLIF(@n_writers, ''),
        is_qualifying   = NULLIF(@is_qualifying, ''),
        is_current_year = NULLIF(@is_current_year, '');

LOAD DATA LOCAL INFILE '{DATA_DIR}/season_writer.csv' INTO TABLE season_writer
    CHARACTER SET utf8mb4
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
    LINES TERMINATED BY '\n' IGNORE 1 LINES
    (series_id, season, writer_id);

LOAD DATA LOCAL INFILE '{DATA_DIR}/episode.csv' INTO TABLE episode
    CHARACTER SET utf8mb4
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
    LINES TERMINATED BY '\n' IGNORE 1 LINES
    (episode_id, series_id, season, episode, @episode_year, @rating, @votes)
    SET episode_year = NULLIF(@episode_year, ''),
        rating       = NULLIF(@rating, ''),
        votes        = NULLIF(@votes, '');

-- Load check: row counts must match the export (series 167,650 / series_genre 251,173 /
-- season 176,251 / season_writer 572,733 / episode 4,621,376)
SELECT 'series' AS tbl, COUNT(*) AS n_rows FROM series
UNION ALL SELECT 'series_genre',  COUNT(*) FROM series_genre
UNION ALL SELECT 'season',        COUNT(*) FROM season
UNION ALL SELECT 'season_writer', COUNT(*) FROM season_writer
UNION ALL SELECT 'episode',       COUNT(*) FROM episode;

-- Load check: qualifying seasons and NULL handling (expected 24,013 qualifying)
SELECT SUM(is_qualifying) AS n_qualifying,
       SUM(season_year IS NULL) AS n_null_season_year,
       SUM(rating IS NULL) AS n_null_rating
FROM season;
