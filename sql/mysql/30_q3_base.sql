-- 30_q3_base.sql  (MySQL 8)
-- Question (Q3): base table for "audience vs quality as a renewal signal" (decision #22).
-- One row per ended series with a valid season 1 -> 2 pair (q1_pairs: both seasons qualify,
-- no gap, season 2 not from 2026). Outcome: did the series get any season 3?

DROP TABLE IF EXISTS q3_base;

CREATE TABLE q3_base AS
SELECT p.series_id,
       sr.title,
       p.year_to              AS s2_year,
       p.vote_change,                          -- audience signal: S2 vs S1 median votes
       p.rating_change,                        -- quality signal: S2 rating minus S1 rating
       sr.n_seasons_max,
       sr.n_seasons_max >= 3  AS got_season_3
FROM q1_pairs AS p
JOIN series   AS sr ON sr.series_id = p.series_id
WHERE p.season_from = 1
  AND sr.is_ended = 1;

ALTER TABLE q3_base ADD PRIMARY KEY (series_id);

-- Check: expected 3,801 series (same pool as sql/mysql/15 15b, drop at 1->2)
SELECT COUNT(*) AS n_series,
       SUM(got_season_3) AS n_got_season_3,
       ROUND(100 * AVG(got_season_3), 1) AS pct_got_season_3
FROM q3_base;
