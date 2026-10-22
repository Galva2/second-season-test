-- 13_q1_genre.sql  (MySQL 8)
-- Question (Q1, output 3): does the retention curve differ by genre?
-- A series counts in every genre it has (decision #17), so genre groups overlap.
-- Only genres with >= 150 distinct series in q1_pairs are shown. 'ALL' = every series, for reference.
-- Transitions 1->2 to 4->5 (enough pairs per genre).

WITH eligible_genres AS (
    SELECT g.genre
    FROM series_genre g
    JOIN (SELECT DISTINCT series_id FROM q1_pairs) s USING (series_id)
    GROUP BY g.genre
    HAVING COUNT(*) >= 150
),
genre_pairs AS (
    SELECT g.genre, p.season_from, p.season_to, p.vote_change
    FROM q1_pairs p
    JOIN series_genre g USING (series_id)
    JOIN eligible_genres e USING (genre)
    WHERE p.season_from <= 4
    UNION ALL
    SELECT 'ALL', season_from, season_to, vote_change
    FROM q1_pairs
    WHERE season_from <= 4
),
ranked AS (
    SELECT genre, season_from, season_to, vote_change,
           ROW_NUMBER() OVER (PARTITION BY genre, season_from ORDER BY vote_change) AS rn,
           COUNT(*)     OVER (PARTITION BY genre, season_from)                      AS n
    FROM genre_pairs
),
neighbours AS (
    SELECT genre, season_from, season_to, n,
           1 + 0.5 * (n - 1) AS pos50,
           MAX(CASE WHEN rn = FLOOR(1 + 0.5 * (n - 1))   THEN vote_change END) AS v50_lo,
           MAX(CASE WHEN rn = CEILING(1 + 0.5 * (n - 1)) THEN vote_change END) AS v50_hi,
           AVG(vote_change < 0) AS share_lost_votes
    FROM ranked
    GROUP BY genre, season_from, season_to, n
)
SELECT genre,
       CONCAT(season_from, '->', season_to)                                   AS transition,
       n                                                                      AS n_pairs,
       ROUND(100 * (v50_lo + (pos50 - FLOOR(pos50)) * (v50_hi - v50_lo)), 1) AS median_vote_change_pct,
       ROUND(100 * share_lost_votes, 1)                                       AS pct_pairs_lost_votes
FROM neighbours
ORDER BY genre = 'ALL' DESC, genre, season_from;
