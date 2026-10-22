-- 15_q1_rule_preview.sql  (MySQL 8)
-- Question (Q1, output 5, decision #19): after a season loses votes, what happens next?
-- First step toward a renew / end decision rule.
--
-- Drop buckets use the vote change of the pair N-1 -> N:
--   1) lost 50%+   2) lost 25-50%   3) lost 0-25%   4) gained
-- Part A: triples of consecutive qualifying seasons (N-1, N, N+1). What happens at N -> N+1?
--         Caveat: only series that reached a qualifying season N+1 (survivorship).
-- Part B: ended series only (no right-censoring). Did a season N+1 exist at all?

-- 15a. Part A: next transition after a drop, by drop bucket and by where the drop happened
WITH triples AS (
    SELECT
        CASE WHEN p1.season_from = 1 THEN 'a) drop at 1->2' ELSE 'b) drop at a later season' END AS drop_position,
        CASE WHEN p1.vote_change < -0.50 THEN '1) lost 50%+'
             WHEN p1.vote_change < -0.25 THEN '2) lost 25-50%'
             WHEN p1.vote_change <  0    THEN '3) lost 0-25%'
             ELSE                             '4) gained' END AS drop_bucket,
        p2.vote_change   AS next_vote_change,
        p2.rating_change AS next_rating_change
    FROM q1_pairs p1
    JOIN q1_pairs p2
      ON p2.series_id = p1.series_id
     AND p2.season_from = p1.season_to
)
SELECT drop_position,
       drop_bucket,
       COUNT(*)                                  AS n_triples,
       ROUND(100 * AVG(next_rating_change > 0), 1) AS pct_next_rating_up,
       ROUND(100 * AVG(next_vote_change > 0), 1)   AS pct_next_votes_recover,
       ROUND(AVG(next_rating_change), 3)           AS avg_next_rating_change
FROM triples
GROUP BY drop_position, drop_bucket
ORDER BY drop_position, drop_bucket;

-- 15b. Part B: ended series. After a pair N-1 -> N, did the series get any season N+1?
-- n_seasons_max = highest numbered season listed for the series (all seasons, not only qualifying).
WITH ended_pairs AS (
    SELECT
        CASE WHEN p.season_from = 1 THEN 'a) drop at 1->2' ELSE 'b) drop at a later season' END AS drop_position,
        CASE WHEN p.vote_change < -0.50 THEN '1) lost 50%+'
             WHEN p.vote_change < -0.25 THEN '2) lost 25-50%'
             WHEN p.vote_change <  0    THEN '3) lost 0-25%'
             ELSE                            '4) gained' END AS drop_bucket,
        (s.n_seasons_max > p.season_to) AS got_next_season
    FROM q1_pairs p
    JOIN series s USING (series_id)
    WHERE s.is_ended = 1
)
SELECT drop_position,
       drop_bucket,
       COUNT(*)                                AS n_pairs,
       ROUND(100 * AVG(got_next_season), 1)    AS pct_got_next_season
FROM ended_pairs
GROUP BY drop_position, drop_bucket
ORDER BY drop_position, drop_bucket;

-- 15c. Era check for Part B (drop at 1->2, ended series). Recent series show bigger vote
-- drops (partly accumulation, sql/mysql/14) and may also be cancelled more often. If the
-- drop -> renewal link were only an era effect, it would vanish within each era.
WITH ended_12 AS (
    SELECT
        CASE WHEN p.year_to <= 2012 THEN '1) <= 2012'
             WHEN p.year_to <= 2018 THEN '2) 2013-2018'
             ELSE '3) 2019-2025' END AS era,
        CASE WHEN p.vote_change < -0.50 THEN '1) lost 50%+'
             WHEN p.vote_change < -0.25 THEN '2) lost 25-50%'
             WHEN p.vote_change <  0    THEN '3) lost 0-25%'
             ELSE                            '4) gained' END AS drop_bucket,
        (s.n_seasons_max > p.season_to) AS got_next_season
    FROM q1_pairs p
    JOIN series s USING (series_id)
    WHERE s.is_ended = 1 AND p.season_from = 1
)
SELECT era,
       drop_bucket,
       COUNT(*)                             AS n_pairs,
       ROUND(100 * AVG(got_next_season), 1) AS pct_got_season_3
FROM ended_12
GROUP BY era, drop_bucket
ORDER BY era, drop_bucket;
