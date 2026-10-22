-- 12_q1_panel.sql  (MySQL 8)
-- Question (Q1, output 2): in a fixed group of series, where do they lose the most votes?
-- Balanced panel (decision #18): series that have all four pairs 1->2, 2->3, 3->4, 4->5,
-- i.e. seasons 1-5 all qualify with no gap and no 2026 season. The same series appear in
-- every transition, so transitions are comparable without survivorship changing the mix.

DROP TEMPORARY TABLE IF EXISTS panel_pairs;

CREATE TEMPORARY TABLE panel_pairs AS
SELECT p.*
FROM q1_pairs p
JOIN (
    SELECT series_id
    FROM q1_pairs
    WHERE season_to BETWEEN 2 AND 5
    GROUP BY series_id
    HAVING COUNT(*) = 4
) panel USING (series_id)
WHERE p.season_to BETWEEN 2 AND 5;

-- 12a. Panel size (expected 1,025 series, from DuckDB sql/07 7d)
SELECT COUNT(DISTINCT series_id) AS n_series, COUNT(*) AS n_pairs FROM panel_pairs;

-- 12b. Table A: median vote change per transition, same series throughout
WITH ranked AS (
    SELECT season_from, season_to, vote_change, rating_change,
           ROW_NUMBER() OVER (PARTITION BY season_from ORDER BY vote_change)   AS rn_votes,
           ROW_NUMBER() OVER (PARTITION BY season_from ORDER BY rating_change) AS rn_rating,
           COUNT(*)     OVER (PARTITION BY season_from)                        AS n
    FROM panel_pairs
),
positions AS (
    SELECT *, 1 + 0.25 * (n - 1) AS pos25, 1 + 0.50 * (n - 1) AS pos50, 1 + 0.75 * (n - 1) AS pos75
    FROM ranked
),
neighbours AS (
    SELECT season_from, season_to, n, pos25, pos50, pos75,
           MAX(CASE WHEN rn_votes  = FLOOR(pos25)   THEN vote_change   END) AS v25_lo,
           MAX(CASE WHEN rn_votes  = CEILING(pos25) THEN vote_change   END) AS v25_hi,
           MAX(CASE WHEN rn_votes  = FLOOR(pos50)   THEN vote_change   END) AS v50_lo,
           MAX(CASE WHEN rn_votes  = CEILING(pos50) THEN vote_change   END) AS v50_hi,
           MAX(CASE WHEN rn_votes  = FLOOR(pos75)   THEN vote_change   END) AS v75_lo,
           MAX(CASE WHEN rn_votes  = CEILING(pos75) THEN vote_change   END) AS v75_hi,
           MAX(CASE WHEN rn_rating = FLOOR(pos50)   THEN rating_change END) AS r50_lo,
           MAX(CASE WHEN rn_rating = CEILING(pos50) THEN rating_change END) AS r50_hi,
           AVG(vote_change < 0) AS share_lost_votes
    FROM positions
    GROUP BY season_from, season_to, n, pos25, pos50, pos75
)
SELECT CONCAT(season_from, '->', season_to)                                   AS transition,
       n                                                                      AS n_series,
       ROUND(100 * (v50_lo + (pos50 - FLOOR(pos50)) * (v50_hi - v50_lo)), 1) AS median_vote_change_pct,
       ROUND(100 * (v25_lo + (pos25 - FLOOR(pos25)) * (v25_hi - v25_lo)), 1) AS p25_vote_change_pct,
       ROUND(100 * (v75_lo + (pos75 - FLOOR(pos75)) * (v75_hi - v75_lo)), 1) AS p75_vote_change_pct,
       ROUND(100 * share_lost_votes, 1)                                       AS pct_series_lost_votes,
       ROUND(r50_lo + (pos50 - FLOOR(pos50)) * (r50_hi - r50_lo), 3)          AS median_rating_change
FROM neighbours
ORDER BY season_from;

-- 12c. Table B: for each series, the transition with its biggest drop (most negative vote change).
-- If drops were spread at random, each of the 4 transitions would get 25%.
WITH ordered AS (
    SELECT series_id, season_from, season_to, vote_change,
           ROW_NUMBER() OVER (PARTITION BY series_id ORDER BY vote_change, season_to) AS drop_rank
    FROM panel_pairs
)
SELECT CONCAT(season_from, '->', season_to)              AS biggest_drop_at,
       COUNT(*)                                          AS n_series,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)  AS pct_series,
       SUM(vote_change >= 0)                             AS n_where_biggest_drop_was_not_a_loss
FROM ordered
WHERE drop_rank = 1
GROUP BY season_from, season_to
ORDER BY season_from;
