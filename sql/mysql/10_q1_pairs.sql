-- 10_q1_pairs.sql  (MySQL 8)
-- Question: build the base table for Q1, one row per pair of consecutive qualifying seasons.
-- Used by files 11-15.
--
-- A pair (N-1, N) is kept only if (decisions #10, #14):
--   * the previous listed season is exactly N-1 (no gap)
--   * both seasons qualify (>= 80% episodes rated, median votes >= 20)
--   * the later season did not start in 2026 (votes still accumulating)
-- LAG runs over ALL seasons, not only qualifying ones. Otherwise a non-qualifying
-- season 3 would be skipped and season 4 would wrongly be compared with season 2.

DROP TABLE IF EXISTS q1_pairs;

CREATE TABLE q1_pairs AS
WITH with_prev AS (
    SELECT
        series_id,
        season,
        season_year,
        median_votes,
        rating,
        is_qualifying,
        is_current_year,
        LAG(season)        OVER w AS prev_season,
        LAG(median_votes)  OVER w AS prev_median_votes,
        LAG(rating)        OVER w AS prev_rating,
        LAG(is_qualifying) OVER w AS prev_is_qualifying
    FROM season
    WINDOW w AS (PARTITION BY series_id ORDER BY season)
)
SELECT
    series_id,
    prev_season                         AS season_from,
    season                              AS season_to,
    season_year                         AS year_to,
    prev_median_votes                   AS votes_from,
    median_votes                        AS votes_to,
    median_votes / prev_median_votes - 1 AS vote_change,     -- decision #16
    prev_rating                         AS rating_from,
    rating                              AS rating_to,
    rating - prev_rating                AS rating_change
FROM with_prev
WHERE prev_season = season - 1
  AND prev_is_qualifying = 1
  AND is_qualifying = 1
  AND is_current_year = 0;

ALTER TABLE q1_pairs ADD PRIMARY KEY (series_id, season_to);

-- Check: expected 12,582 pairs (same as DuckDB, decisions.md #14)
SELECT COUNT(*) AS n_pairs,
       COUNT(DISTINCT series_id) AS n_series,
       MIN(vote_change) AS min_vote_change,
       MAX(vote_change) AS max_vote_change,
       SUM(year_to IS NULL) AS n_missing_year
FROM q1_pairs;

-- Check: pairs per transition (expected, from DuckDB sql/07 7c: 4,518 / 2,582 / 1,602 / 1,046 / 698)
SELECT CONCAT(season_from, '->', season_to) AS transition, COUNT(*) AS n_pairs
FROM q1_pairs
WHERE season_from <= 5
GROUP BY season_from, season_to
ORDER BY season_from;
