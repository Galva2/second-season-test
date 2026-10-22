-- 21_q2_pilot_signal.sql  (MySQL 8)
-- Question (Q2): does the pilot rating (S1E1) or the season-1 rating predict whether a
-- series gets a season 2 (and how long it lasts)? Ended series only (right-censoring).
-- Base table: q2_base (sql/mysql/20). Correlation, not causation.
-- Caveat: ratings are given today, possibly in hindsight of the series' success.

-- 21a. Renewal by rating bucket, for each predictor
WITH long_form AS (
    SELECT 'pilot (S1E1)' AS predictor, pilot_rating AS r, got_season_2, n_seasons_max
    FROM q2_base WHERE pilot_rating IS NOT NULL
    UNION ALL
    SELECT 'season 1', s1_rating, got_season_2, n_seasons_max
    FROM q2_base
),
bucketed AS (
    SELECT predictor, got_season_2, n_seasons_max,
           CASE WHEN r < 6.5 THEN '1) < 6.5'
                WHEN r < 7.0 THEN '2) 6.5-7.0'
                WHEN r < 7.5 THEN '3) 7.0-7.5'
                WHEN r < 8.0 THEN '4) 7.5-8.0'
                WHEN r < 8.5 THEN '5) 8.0-8.5'
                ELSE              '6) 8.5+' END AS rating_bucket
    FROM long_form
)
SELECT predictor,
       rating_bucket,
       COUNT(*)                                   AS n_series,
       ROUND(100 * AVG(got_season_2), 1)          AS pct_got_season_2,
       ROUND(100 * AVG(n_seasons_max >= 3), 1)    AS pct_3plus_seasons,
       ROUND(AVG(n_seasons_max), 2)               AS avg_seasons
FROM bucketed
GROUP BY predictor, rating_bucket
ORDER BY predictor, rating_bucket;

-- 21b. Which predictor is stronger? Pearson correlation with got_season_2, computed from
-- sums (MySQL has no CORR). Same series for both predictors (pilot rated).
-- r = (n*Sxy - Sx*Sy) / sqrt((n*Sxx - Sx^2) * (n*Syy - Sy^2))
WITH sums AS (
    SELECT COUNT(*)                          AS n,
           SUM(got_season_2)                 AS sy,
           SUM(got_season_2 * got_season_2)  AS syy,
           SUM(pilot_rating)                 AS sx_p,
           SUM(pilot_rating * pilot_rating)  AS sxx_p,
           SUM(pilot_rating * got_season_2)  AS sxy_p,
           SUM(s1_rating)                    AS sx_s,
           SUM(s1_rating * s1_rating)        AS sxx_s,
           SUM(s1_rating * got_season_2)     AS sxy_s
    FROM q2_base
    WHERE pilot_rating IS NOT NULL
)
SELECT n,
       ROUND((n * sxy_p - sx_p * sy) / SQRT((n * sxx_p - sx_p * sx_p) * (n * syy - sy * sy)), 3) AS corr_pilot_vs_got_s2,
       ROUND((n * sxy_s - sx_s * sy) / SQRT((n * sxx_s - sx_s * sx_s) * (n * syy - sy * sy)), 3) AS corr_season1_vs_got_s2
FROM sums;

-- 21c. Robustness: does the season-1 rating -> renewal link hold within each era of season 1?
-- Three wider buckets keep enough series per era.
SELECT CASE WHEN s1_year <= 2012 THEN '1) <= 2012'
            WHEN s1_year <= 2018 THEN '2) 2013-2018'
            ELSE '3) 2019-2025' END             AS s1_era,
       CASE WHEN s1_rating < 7.0 THEN '1) < 7.0'
            WHEN s1_rating < 8.0 THEN '2) 7.0-8.0'
            ELSE '3) 8.0+' END                  AS s1_rating_bucket,
       COUNT(*)                                 AS n_series,
       ROUND(100 * AVG(got_season_2), 1)        AS pct_got_season_2
FROM q2_base
WHERE s1_year IS NOT NULL
GROUP BY s1_era, s1_rating_bucket
ORDER BY s1_era, s1_rating_bucket;

-- 21d. Why do 8.5+ season-1 ratings get FEWER renewals than 7.5-8.0? Test: are they small
-- fan bases? Split series at the overall median of s1_median_votes (computed below with the
-- ROW_NUMBER pattern) into small vs large audience, and compare renewal within each group.
WITH ranked AS (
    SELECT s1_median_votes,
           ROW_NUMBER() OVER (ORDER BY s1_median_votes) AS rn,
           COUNT(*)     OVER ()                         AS n
    FROM q2_base
),
overall_median AS (
    SELECT AVG(s1_median_votes) AS median_votes
    FROM ranked
    WHERE rn IN (FLOOR((n + 1) / 2), CEILING((n + 1) / 2))
),
tagged AS (
    SELECT CASE WHEN b.s1_rating < 6.5 THEN '1) < 6.5'
                WHEN b.s1_rating < 7.0 THEN '2) 6.5-7.0'
                WHEN b.s1_rating < 7.5 THEN '3) 7.0-7.5'
                WHEN b.s1_rating < 8.0 THEN '4) 7.5-8.0'
                WHEN b.s1_rating < 8.5 THEN '5) 8.0-8.5'
                ELSE                        '6) 8.5+' END AS s1_rating_bucket,
           b.s1_median_votes >= m.median_votes          AS is_large_audience,
           b.got_season_2,
           m.median_votes
    FROM q2_base b CROSS JOIN overall_median m
)
SELECT s1_rating_bucket,
       MAX(median_votes)                                                         AS split_at_votes,
       SUM(is_large_audience = 0)                                                AS n_small,
       ROUND(100 * AVG(CASE WHEN is_large_audience = 0 THEN got_season_2 END), 1) AS pct_got_s2_small,
       SUM(is_large_audience = 1)                                                AS n_large,
       ROUND(100 * AVG(CASE WHEN is_large_audience = 1 THEN got_season_2 END), 1) AS pct_got_s2_large
FROM tagged
GROUP BY s1_rating_bucket
ORDER BY s1_rating_bucket;
