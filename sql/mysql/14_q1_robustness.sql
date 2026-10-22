-- 14_q1_robustness.sql  (MySQL 8)
-- Question (Q1, output 4): do the Q1 results survive the vote-accumulation bias?
-- Votes keep accumulating for years, so recent seasons look smaller (decision #14).
-- Re-run the curve and the panel's biggest-drop table using only pairs whose later season
-- started in 2023 or earlier (at least ~3 years to accumulate votes), next to the full result.

-- 14a. Curve: all pairs vs pairs with later season <= 2023
WITH scoped AS (
    SELECT 'all pairs' AS scope, season_from, season_to, vote_change FROM q1_pairs WHERE season_from <= 8
    UNION ALL
    SELECT 'later season <= 2023', season_from, season_to, vote_change FROM q1_pairs WHERE season_from <= 8 AND year_to <= 2023
),
ranked AS (
    SELECT scope, season_from, season_to, vote_change,
           ROW_NUMBER() OVER (PARTITION BY scope, season_from ORDER BY vote_change) AS rn,
           COUNT(*)     OVER (PARTITION BY scope, season_from)                      AS n
    FROM scoped
),
neighbours AS (
    SELECT scope, season_from, season_to, n,
           1 + 0.5 * (n - 1) AS pos50,
           MAX(CASE WHEN rn = FLOOR(1 + 0.5 * (n - 1))   THEN vote_change END) AS v50_lo,
           MAX(CASE WHEN rn = CEILING(1 + 0.5 * (n - 1)) THEN vote_change END) AS v50_hi,
           AVG(vote_change < 0) AS share_lost_votes
    FROM ranked
    GROUP BY scope, season_from, season_to, n
),
medians AS (
    SELECT scope, season_from, season_to, n,
           ROUND(100 * (v50_lo + (pos50 - FLOOR(pos50)) * (v50_hi - v50_lo)), 1) AS median_pct,
           ROUND(100 * share_lost_votes, 1) AS pct_lost
    FROM neighbours
)
SELECT CONCAT(a.season_from, '->', a.season_to) AS transition,
       a.n           AS n_all,
       a.median_pct  AS median_pct_all,
       b.n           AS n_le_2023,
       b.median_pct  AS median_pct_le_2023,
       ROUND(b.median_pct - a.median_pct, 1) AS diff_points,
       a.pct_lost    AS pct_lost_all,
       b.pct_lost    AS pct_lost_le_2023
FROM medians a
JOIN medians b ON b.season_from = a.season_from AND b.scope = 'later season <= 2023'
WHERE a.scope = 'all pairs'
ORDER BY a.season_from;

-- 14b. Panel biggest-drop table, restricted to series whose season 5 started <= 2023
WITH panel AS (
    SELECT series_id
    FROM q1_pairs
    WHERE season_to BETWEEN 2 AND 5
    GROUP BY series_id
    HAVING COUNT(*) = 4 AND MAX(year_to) <= 2023
),
ordered AS (
    SELECT p.series_id, p.season_from, p.season_to,
           ROW_NUMBER() OVER (PARTITION BY p.series_id ORDER BY p.vote_change, p.season_to) AS drop_rank
    FROM q1_pairs p JOIN panel USING (series_id)
    WHERE p.season_to BETWEEN 2 AND 5
)
SELECT CONCAT(season_from, '->', season_to)             AS biggest_drop_at,
       COUNT(*)                                         AS n_series,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_series
FROM ordered
WHERE drop_rank = 1
GROUP BY season_from, season_to
ORDER BY season_from;

-- 14c. Curve by era of the later season. The level of the drop may depend on era
-- (accumulation time and/or a real trend). Check whether the SHAPE holds in every era.
WITH scoped AS (
    SELECT CASE WHEN year_to <= 2012 THEN '1) <= 2012'
                WHEN year_to <= 2018 THEN '2) 2013-2018'
                ELSE '3) 2019-2023' END AS era,
           season_from, season_to, vote_change
    FROM q1_pairs
    WHERE season_from <= 4 AND year_to <= 2023
),
ranked AS (
    SELECT era, season_from, season_to, vote_change,
           ROW_NUMBER() OVER (PARTITION BY era, season_from ORDER BY vote_change) AS rn,
           COUNT(*)     OVER (PARTITION BY era, season_from)                      AS n
    FROM scoped
),
neighbours AS (
    SELECT era, season_from, season_to, n,
           1 + 0.5 * (n - 1) AS pos50,
           MAX(CASE WHEN rn = FLOOR(1 + 0.5 * (n - 1))   THEN vote_change END) AS v50_lo,
           MAX(CASE WHEN rn = CEILING(1 + 0.5 * (n - 1)) THEN vote_change END) AS v50_hi
    FROM ranked
    GROUP BY era, season_from, season_to, n
)
SELECT era,
       CONCAT(season_from, '->', season_to)                                   AS transition,
       n                                                                      AS n_pairs,
       ROUND(100 * (v50_lo + (pos50 - FLOOR(pos50)) * (v50_hi - v50_lo)), 1) AS median_vote_change_pct
FROM neighbours
ORDER BY era, season_from;

-- 14d. Is the era effect a measurement artifact (season 1 had more time to collect votes)
-- or a real change? If it is the head start, a bigger gap in years between season 1 and
-- season 2 should mean a bigger drop, and mostly for recent pairs (where 1 extra year is
-- a large share of the season's total age). Pairs 1->2 with later season <= 2023.
WITH tagged AS (
    SELECT CASE WHEN p.year_to <= 2012 THEN '1) <= 2012'
                WHEN p.year_to <= 2018 THEN '2) 2013-2018'
                ELSE '3) 2019-2023' END AS era,
           CASE WHEN p.year_to - s.season_year <= 0 THEN 'a) same year'
                WHEN p.year_to - s.season_year = 1 THEN 'b) 1 year'
                ELSE 'c) 2+ years' END AS gap,
           p.vote_change
    FROM q1_pairs p
    JOIN season s ON s.series_id = p.series_id AND s.season = p.season_from
    WHERE p.season_from = 1 AND p.year_to <= 2023 AND s.season_year IS NOT NULL
),
ranked AS (
    SELECT era, gap, vote_change,
           ROW_NUMBER() OVER (PARTITION BY era, gap ORDER BY vote_change) AS rn,
           COUNT(*)     OVER (PARTITION BY era, gap)                      AS n
    FROM tagged
),
neighbours AS (
    SELECT era, gap, n,
           1 + 0.5 * (n - 1) AS pos50,
           MAX(CASE WHEN rn = FLOOR(1 + 0.5 * (n - 1))   THEN vote_change END) AS v50_lo,
           MAX(CASE WHEN rn = CEILING(1 + 0.5 * (n - 1)) THEN vote_change END) AS v50_hi
    FROM ranked
    GROUP BY era, gap, n
)
SELECT era, gap, n AS n_pairs,
       ROUND(100 * (v50_lo + (pos50 - FLOOR(pos50)) * (v50_hi - v50_lo)), 1) AS median_vote_change_pct
FROM neighbours
ORDER BY era, gap;
