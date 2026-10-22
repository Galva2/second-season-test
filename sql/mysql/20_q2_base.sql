-- 20_q2_base.sql  (MySQL 8)
-- Question (Q2): base table for the pilot signal. One row per ended series whose
-- season 1 qualifies and did not start in 2026 (decisions #9, #24-26).
-- LEFT JOIN to episode keeps series whose S1E1 is missing or unrated (pilot_rating NULL),
-- so the season-1 predictor still has every series.

DROP TABLE IF EXISTS q2_base;

CREATE TABLE q2_base AS
SELECT sr.series_id,
       sr.title,
       s.season_year         AS s1_year,
       e.rating              AS pilot_rating,
       e.votes               AS pilot_votes,
       s.rating              AS s1_rating,
       s.median_votes        AS s1_median_votes,
       sr.n_seasons_max,
       sr.n_seasons_max >= 2 AS got_season_2
FROM season AS s
JOIN series AS sr
  ON s.series_id = sr.series_id
LEFT JOIN episode AS e
  ON e.series_id = s.series_id
 AND e.season = 1
 AND e.episode = 1
WHERE s.season = 1
  AND s.is_qualifying = 1
  AND s.is_current_year = 0
  AND sr.is_ended = 1;

ALTER TABLE q2_base ADD PRIMARY KEY (series_id);

-- Check: rows, pilots rated, share that got a season 2
SELECT COUNT(*)                              AS n_series,
       SUM(pilot_rating IS NOT NULL)         AS n_pilot_rated,
       SUM(got_season_2)                     AS n_got_season_2,
       ROUND(100 * AVG(got_season_2), 1)     AS pct_got_season_2
FROM q2_base;
