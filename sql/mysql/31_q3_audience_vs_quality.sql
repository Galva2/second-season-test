-- 31_q3_audience_vs_quality.sql  (MySQL 8)
-- Question (Q3): after season 2, which signal is more closely linked to getting a season 3:
-- the audience change (vote_change, S2 vs S1) or the quality change (rating_change)?
-- Ended series only (q3_base, sql/mysql/30). Correlation, not causation.
-- Each signal is split into equal thirds with NTILE(3) so both get groups of the same size.
-- Tertile 1 = worst third (biggest vote loss / biggest rating drop), 3 = best third.

-- 31a. Renewal by tertile, for each signal. The signal whose best-minus-worst gap is
-- larger is the stronger renewal signal.
WITH t AS (
    SELECT series_id, vote_change, rating_change, got_season_3,
           NTILE(3) OVER (ORDER BY vote_change,   series_id) AS vote_tertile,
           NTILE(3) OVER (ORDER BY rating_change, series_id) AS rating_tertile
    FROM q3_base
),
long_form AS (
    SELECT 'audience (vote change)' AS signal_name, vote_tertile AS tertile, vote_change AS x, got_season_3 FROM t
    UNION ALL
    SELECT 'quality (rating change)', rating_tertile, rating_change, got_season_3 FROM t
)
SELECT signal_name,
       tertile,
       COUNT(*)                            AS n_series,
       ROUND(MIN(x), 3)                    AS min_change,
       ROUND(MAX(x), 3)                    AS max_change,
       ROUND(100 * AVG(got_season_3), 1)   AS pct_got_season_3
FROM long_form
GROUP BY signal_name, tertile
ORDER BY signal_name, tertile;

-- 31b. Both signals together (3 x 3). Read across a row: rating held in the same third,
-- audience changes. Read down a column: audience held, rating changes.
WITH t AS (
    SELECT got_season_3,
           NTILE(3) OVER (ORDER BY vote_change,   series_id) AS vote_tertile,
           NTILE(3) OVER (ORDER BY rating_change, series_id) AS rating_tertile
    FROM q3_base
)
SELECT rating_tertile,
       SUM(vote_tertile = 1)                                                    AS n_vote_t1,
       ROUND(100 * AVG(CASE WHEN vote_tertile = 1 THEN got_season_3 END), 1)    AS pct_s3_vote_t1_worst,
       SUM(vote_tertile = 2)                                                    AS n_vote_t2,
       ROUND(100 * AVG(CASE WHEN vote_tertile = 2 THEN got_season_3 END), 1)    AS pct_s3_vote_t2,
       SUM(vote_tertile = 3)                                                    AS n_vote_t3,
       ROUND(100 * AVG(CASE WHEN vote_tertile = 3 THEN got_season_3 END), 1)    AS pct_s3_vote_t3_best
FROM t
GROUP BY rating_tertile
ORDER BY rating_tertile;

-- 31c. Robustness by era of season 2. Tertile cut-offs come from the whole sample (31a),
-- so a tertile means the same range of change in both eras.
WITH t AS (
    SELECT s2_year, got_season_3,
           NTILE(3) OVER (ORDER BY vote_change,   series_id) AS vote_tertile,
           NTILE(3) OVER (ORDER BY rating_change, series_id) AS rating_tertile
    FROM q3_base
),
long_form AS (
    SELECT CASE WHEN s2_year <= 2018 THEN '1) <= 2018' ELSE '2) 2019-2025' END AS era,
           'audience (vote change)' AS signal_name, vote_tertile AS tertile, got_season_3 FROM t
    UNION ALL
    SELECT CASE WHEN s2_year <= 2018 THEN '1) <= 2018' ELSE '2) 2019-2025' END,
           'quality (rating change)', rating_tertile, got_season_3 FROM t
)
SELECT era, signal_name, tertile,
       COUNT(*)                          AS n_series,
       ROUND(100 * AVG(got_season_3), 1) AS pct_got_season_3
FROM long_form
GROUP BY era, signal_name, tertile
ORDER BY era, signal_name, tertile;
