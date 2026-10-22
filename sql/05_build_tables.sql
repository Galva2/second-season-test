-- 05_build_tables.sql
-- Purpose: build the clean analysis tables and print the filtering funnel.
-- Outputs (data/processed/):
--   series.parquet         one row per scripted tvSeries
--   season.parquet         one row per (series, numbered season 1..100), with is_qualifying flag
--   episode_clean.parquet  one row per episode in those seasons
-- Decisions applied: notes/decisions.md #5-#14.
-- Run from the repo root: python scripts/run_sql.py sql/05_build_tables.sql

-- ---------------------------------------------------------------- series
-- Scripted = tvSeries, not adult, has genres, and no non-scripted genre tag (#5, #11).
CREATE TEMP TABLE series_all AS
SELECT tconst AS series_id, primaryTitle AS title, startYear, endYear, genres, isAdult
FROM basics WHERE titleType = 'tvSeries';

CREATE TEMP TABLE series_base AS
SELECT series_id, title, startYear, endYear, genres,
       string_split(genres, ',') AS genre_list,
       (endYear IS NOT NULL AND endYear <= 2026) AS is_ended          -- #9
FROM series_all
WHERE coalesce(isAdult, 0) = 0
  AND genres IS NOT NULL
  AND NOT regexp_matches(genres, 'Talk-Show|News|Reality-TV|Game-Show|Documentary|Adult|Sport');

-- --------------------------------------------------------------- episodes
-- Episodes of scripted series with a numbered season 1..100 (#8), excluding episode 0 (#12:
-- unaired pilots and specials, so the pilot is always season 1 episode 1).
-- Writers: crew.writers is a comma-separated list of person ids (nconst).
CREATE TEMP TABLE episode_base AS
SELECT e.tconst AS episode_id, e.parentTconst AS series_id,
       e.seasonNumber AS season, e.episodeNumber AS episode,
       eb.startYear AS episode_year,
       r.averageRating AS rating, r.numVotes AS votes,
       CASE WHEN c.writers IS NULL THEN NULL ELSE string_split(c.writers, ',') END AS writer_list
FROM episode e
JOIN series_base s ON s.series_id = e.parentTconst
LEFT JOIN basics  eb ON eb.tconst = e.tconst
LEFT JOIN ratings r  ON r.tconst  = e.tconst
LEFT JOIN crew    c  ON c.tconst  = e.tconst
WHERE e.seasonNumber BETWEEN 1 AND 100
  AND coalesce(e.episodeNumber, -1) <> 0;

-- ----------------------------------------------------------------- season
-- Qualifying season (#6, #7): >= 80% of episodes rated AND median votes of rated episodes >= 20.
CREATE TEMP TABLE season_base AS
SELECT series_id, season,
       min(episode_year)                                   AS season_year,
       count(*)                                            AS n_episodes,
       count(rating)                                       AS n_rated,
       count(rating) / count(*)                            AS rated_share,
       median(votes)                                       AS median_votes,
       sum(votes)                                          AS total_votes,
       round(avg(rating), 3)                               AS rating,          -- #13: simple mean of episode ratings
       round(sum(rating * votes) / sum(votes), 3)          AS rating_weighted, -- kept only for robustness checks
       count(writer_list)                                  AS n_ep_with_writers,
       list_sort(list_distinct(flatten(list(writer_list)))) AS writer_set
FROM episode_base
GROUP BY series_id, season;

CREATE TEMP TABLE season_out AS
SELECT *,
       (rated_share >= 0.8 AND median_votes >= 20) AS is_qualifying,
       (season_year >= 2026)                       AS is_current_year,   -- #14: votes still accumulating
       len(writer_set) AS n_writers
FROM season_base;

-- Series length (Q2 outcome), from all numbered seasons, not only qualifying ones.
CREATE TEMP TABLE series_out AS
SELECT s.series_id, s.title, s.startYear, s.endYear, s.is_ended, s.genres, s.genre_list,
       max(se.season)              AS n_seasons_max,
       count(se.season)            AS n_seasons_listed,
       count_if(se.is_qualifying)::INTEGER AS n_seasons_qualifying
FROM series_base s
LEFT JOIN season_out se USING (series_id)
GROUP BY ALL;

COPY series_out   TO 'data/processed/series.parquet'        (FORMAT parquet);
COPY season_out   TO 'data/processed/season.parquet'        (FORMAT parquet);
COPY (SELECT * FROM episode_base)
                  TO 'data/processed/episode_clean.parquet' (FORMAT parquet);

-- ----------------------------------------------------------------- funnel
-- Funnel: series and seasons remaining after each filter step.
SELECT step, n_series, n_seasons FROM (
    SELECT 1 AS ord, '1. all tvSeries'                          AS step, count(*) AS n_series, NULL::BIGINT AS n_seasons FROM series_all
    UNION ALL
    SELECT 2, '2. not adult', count(*), NULL FROM series_all WHERE coalesce(isAdult, 0) = 0
    UNION ALL
    SELECT 3, '3. has genres', count(*), NULL FROM series_all WHERE coalesce(isAdult, 0) = 0 AND genres IS NOT NULL
    UNION ALL
    SELECT 4, '4. no Talk-Show/News/Reality/Game-Show/Documentary/Adult', count(*), NULL FROM series_all
     WHERE coalesce(isAdult, 0) = 0 AND genres IS NOT NULL
       AND NOT regexp_matches(genres, 'Talk-Show|News|Reality-TV|Game-Show|Documentary|Adult')
    UNION ALL
    SELECT 5, '5. no Sport (= scripted population)', count(*), NULL FROM series_base
    UNION ALL
    SELECT 6, '6. has >= 1 numbered season 1..100', count(DISTINCT series_id), count(*) FROM season_out
    UNION ALL
    SELECT 7, '7. season >= 80% episodes rated', count(DISTINCT series_id), count(*) FROM season_out WHERE rated_share >= 0.8
    UNION ALL
    SELECT 8, '8. season median votes >= 20 (= qualifying)', count(DISTINCT series_id), count(*) FROM season_out WHERE is_qualifying
)
ORDER BY ord;

-- Episodes dropped by the season-number rule within scripted series (#8)
SELECT count(*) AS n_scripted_episodes_all,
       count_if(e.seasonNumber IS NULL)  AS n_null_season,
       count_if(e.seasonNumber > 100)    AS n_season_over_100,
       count_if(e.seasonNumber BETWEEN 1 AND 100 AND e.episodeNumber = 0) AS n_episode_0,
       count_if(e.seasonNumber BETWEEN 1 AND 100 AND coalesce(e.episodeNumber, -1) <> 0) AS n_kept
FROM episode e JOIN series_base s ON s.series_id = e.parentTconst;

-- Analysis pools
SELECT
    (SELECT count(*) FROM series_out WHERE n_seasons_qualifying >= 2)                         AS series_2plus_qualifying,
    (SELECT count(*) FROM season_out a JOIN season_out b
        ON a.series_id = b.series_id AND a.season = b.season + 1
       WHERE a.is_qualifying AND b.is_qualifying)                                             AS q1_consecutive_pairs,
    (SELECT count(*) FROM series_out s JOIN season_out se USING (series_id)
       WHERE s.is_ended AND se.season = 1 AND se.is_qualifying)                               AS q2_ended_series_s1_qualifying;
