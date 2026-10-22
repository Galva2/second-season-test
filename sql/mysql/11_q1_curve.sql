-- 11_q1_curve.sql  (MySQL 8)
-- Question (Q1, output 1): season-over-season retention curve.
-- For each transition N-1 -> N: number of pairs, median vote change with its
-- interquartile range (p25-p75), share of pairs that lost votes, median rating change.
-- All pairs are used (unbalanced). Later transitions only contain series that survived.
--
-- Percentiles: MySQL has no MEDIAN, so values are ranked with ROW_NUMBER and the
-- percentile p is read at position 1 + p * (n - 1), interpolating linearly between the
-- two neighbouring values (same method as DuckDB quantile_cont).

WITH ranked AS (
    SELECT
        season_from,
        season_to,
        vote_change,
        rating_change,
        ROW_NUMBER() OVER (PARTITION BY season_from ORDER BY vote_change)   AS rn_votes,
        ROW_NUMBER() OVER (PARTITION BY season_from ORDER BY rating_change) AS rn_rating,
        COUNT(*)     OVER (PARTITION BY season_from)                        AS n
    FROM q1_pairs
    WHERE season_from <= 9
),
positions AS (
    SELECT *,
           1 + 0.25 * (n - 1) AS pos25,
           1 + 0.50 * (n - 1) AS pos50,
           1 + 0.75 * (n - 1) AS pos75
    FROM ranked
),
neighbours AS (
    SELECT
        season_from,
        season_to,
        n,
        pos25, pos50, pos75,
        MAX(CASE WHEN rn_votes  = FLOOR(pos25)   THEN vote_change   END) AS v25_lo,
        MAX(CASE WHEN rn_votes  = CEILING(pos25) THEN vote_change   END) AS v25_hi,
        MAX(CASE WHEN rn_votes  = FLOOR(pos50)   THEN vote_change   END) AS v50_lo,
        MAX(CASE WHEN rn_votes  = CEILING(pos50) THEN vote_change   END) AS v50_hi,
        MAX(CASE WHEN rn_votes  = FLOOR(pos75)   THEN vote_change   END) AS v75_lo,
        MAX(CASE WHEN rn_votes  = CEILING(pos75) THEN vote_change   END) AS v75_hi,
        MAX(CASE WHEN rn_rating = FLOOR(pos50)   THEN rating_change END) AS r50_lo,
        MAX(CASE WHEN rn_rating = CEILING(pos50) THEN rating_change END) AS r50_hi,
        AVG(vote_change < 0)                                             AS share_lost_votes,
        AVG(rating_change < 0)                                           AS share_rating_down
    FROM positions
    GROUP BY season_from, season_to, n, pos25, pos50, pos75
)
SELECT
    CONCAT(season_from, '->', season_to)                                   AS transition,
    n                                                                      AS n_pairs,
    ROUND(100 * (v50_lo + (pos50 - FLOOR(pos50)) * (v50_hi - v50_lo)), 1) AS median_vote_change_pct,
    ROUND(100 * (v25_lo + (pos25 - FLOOR(pos25)) * (v25_hi - v25_lo)), 1) AS p25_vote_change_pct,
    ROUND(100 * (v75_lo + (pos75 - FLOOR(pos75)) * (v75_hi - v75_lo)), 1) AS p75_vote_change_pct,
    ROUND(100 * share_lost_votes, 1)                                       AS pct_pairs_lost_votes,
    ROUND(r50_lo + (pos50 - FLOOR(pos50)) * (r50_hi - r50_lo), 3)          AS median_rating_change,
    ROUND(100 * share_rating_down, 1)                                      AS pct_pairs_rating_down
FROM neighbours
ORDER BY season_from;
