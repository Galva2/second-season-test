-- 04_threshold_candidates.sql
-- Question: how many series and seasons survive under candidate thresholds?
-- Nothing is decided here. This produces the numbers used to choose filters.
--
-- Working definitions (candidates. Final choices: notes/decisions.md #5-#11):
--   numbered season  = seasonNumber between 1 and 100 (drops NULL/specials and year-like numbers)
--   rated share      = rated episodes / all episodes in the season
--   season votes     = median numVotes across the season's rated episodes
--   scripted         = genres contain none of Talk-Show, News, Reality-TV, Game-Show,
--                      Documentary, Adult, and isAdult = 0

CREATE TEMP TABLE series AS
SELECT tconst AS series_id, primaryTitle, startYear, endYear, genres,
       NOT (coalesce(isAdult, 0) = 1
            OR regexp_matches(coalesce(genres, ''), 'Talk-Show|News|Reality-TV|Game-Show|Documentary|Adult'))
           AS is_scripted
FROM basics WHERE titleType = 'tvSeries';

CREATE TEMP TABLE season AS
SELECT e.parentTconst AS series_id, e.seasonNumber AS season,
       count(*)                       AS n_ep,
       count(r.tconst)                AS n_rated,
       count(r.tconst) / count(*)     AS rated_share,
       median(r.numVotes)             AS median_votes,
       count(c.writers)               AS n_ep_with_writers
FROM episode e
JOIN series s ON s.series_id = e.parentTconst
LEFT JOIN ratings r ON r.tconst = e.tconst
LEFT JOIN crew    c ON c.tconst = e.tconst
WHERE e.seasonNumber BETWEEN 1 AND 100
GROUP BY ALL;

-- 4a. Year-like or >100 season numbers: which series? (sample)
SELECT b.primaryTitle, b.startYear, min(e.seasonNumber) AS min_season, max(e.seasonNumber) AS max_season, count(*) AS n_ep
FROM episode e JOIN basics b ON b.tconst = e.parentTconst AND b.titleType = 'tvSeries'
WHERE e.seasonNumber > 100
GROUP BY ALL ORDER BY n_ep DESC LIMIT 10;

-- 4b. Distribution of season-level median votes (seasons with >= 50% rated episodes)
SELECT is_scripted,
       count(*) AS n_seasons,
       quantile_cont(median_votes, [0.1, 0.25, 0.5, 0.75, 0.9]) AS q10_25_50_75_90
FROM season JOIN series USING (series_id)
WHERE rated_share >= 0.5
GROUP BY is_scripted;

-- 4c. Threshold grid. For each (genre scope, min rated share, min median votes):
--     qualifying seasons, series with >= 2 / >= 3 qualifying seasons,
--     consecutive qualifying pairs (N-1, N) usable for Q1,
--     ended series with >= 2 qualifying seasons (Q2 pool).
WITH grid AS (
    SELECT * FROM (VALUES (0.5), (0.8)) t(min_share),
                  (VALUES (5), (20), (50), (100), (200)) v(min_votes),
                  (VALUES ('all'), ('scripted')) g(scope)),
q AS (
    SELECT g.scope, g.min_share, g.min_votes, s.series_id, s.season, se.endYear
    FROM grid g
    JOIN season s ON s.rated_share >= g.min_share AND s.median_votes >= g.min_votes
    JOIN series se ON se.series_id = s.series_id
    WHERE g.scope = 'all' OR se.is_scripted),
per_series AS (
    SELECT scope, min_share, min_votes, series_id, any_value(endYear) AS endYear,
           count(*) AS n_q_seasons
    FROM q GROUP BY ALL),
pairs AS (
    SELECT a.scope, a.min_share, a.min_votes, count(*) AS n_consecutive_pairs
    FROM q a JOIN q b
      ON a.scope = b.scope AND a.min_share = b.min_share AND a.min_votes = b.min_votes
     AND a.series_id = b.series_id AND a.season = b.season + 1
    GROUP BY ALL)
SELECT p.scope, p.min_share, p.min_votes,
       sum(n_q_seasons)                              AS n_q_seasons,
       count_if(n_q_seasons >= 2)                    AS n_series_2plus,
       count_if(n_q_seasons >= 3)                    AS n_series_3plus,
       any_value(pr.n_consecutive_pairs)             AS n_consecutive_pairs,
       count_if(n_q_seasons >= 2 AND endYear IS NOT NULL) AS n_ended_2plus
FROM per_series p
LEFT JOIN pairs pr USING (scope, min_share, min_votes)
GROUP BY p.scope, p.min_share, p.min_votes
ORDER BY p.scope, p.min_share, p.min_votes;

-- 4d. Writer coverage in seasons that pass a mid-range candidate (scripted, share>=0.5, votes>=20)
SELECT count(*) AS n_seasons,
       count_if(n_ep_with_writers = 0)         AS n_no_writer_data,
       count_if(n_ep_with_writers = n_ep)      AS n_full_writer_data,
       round(100.0 * sum(n_ep_with_writers) / sum(n_ep), 1) AS pct_episodes_with_writers
FROM season JOIN series USING (series_id)
WHERE is_scripted AND rated_share >= 0.5 AND median_votes >= 20;

-- 4e. Q2 pool (pilot signal): ended series whose season 1 qualifies, any number of seasons.
--     Requiring >= 2 seasons here would drop the one-season cancellations we want to predict.
--     n_seasons = max numbered season (1..100) from all episodes, not just qualifying seasons.
WITH n_seasons AS (
    SELECT series_id, max(season) AS n_seasons FROM season GROUP BY series_id),
s1 AS (
    SELECT s.series_id, s.median_votes, se.is_scripted, n.n_seasons
    FROM season s
    JOIN series se USING (series_id)
    JOIN n_seasons n USING (series_id)
    WHERE s.season = 1 AND s.rated_share >= 0.5 AND se.endYear IS NOT NULL)
SELECT v.min_votes,
       count_if(is_scripted)                      AS n_scripted_ended,
       count_if(is_scripted AND n_seasons = 1)    AS n_1_season,
       count_if(is_scripted AND n_seasons = 2)    AS n_2_seasons,
       count_if(is_scripted AND n_seasons BETWEEN 3 AND 5) AS n_3_to_5,
       count_if(is_scripted AND n_seasons > 5)    AS n_6_plus
FROM s1, (VALUES (5), (20), (50), (100)) v(min_votes)
WHERE s1.median_votes >= v.min_votes
GROUP BY v.min_votes ORDER BY v.min_votes;
