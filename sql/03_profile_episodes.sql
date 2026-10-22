-- 03_profile_episodes.sql
-- Question: what do episodes of tvSeries look like? Missing season numbers, season 0,
-- odd season values, gaps, and coverage of ratings and writers at episode level.

-- Episodes joined to their parent series (tvSeries only) plus episode rating and writers.
CREATE TEMP TABLE ep AS
SELECT e.tconst, e.parentTconst, e.seasonNumber, e.episodeNumber,
       r.averageRating, r.numVotes, c.writers
FROM episode e
JOIN basics p ON p.tconst = e.parentTconst AND p.titleType = 'tvSeries'
LEFT JOIN ratings r ON r.tconst = e.tconst
LEFT JOIN crew    c ON c.tconst = e.tconst;

-- 3a. Episode counts: total, missing season/episode number, season 0, rated, has writers
SELECT
    count(*)                                  AS n_episodes,
    count_if(seasonNumber IS NULL)            AS n_null_season,
    count_if(episodeNumber IS NULL)           AS n_null_episode,
    count_if(seasonNumber = 0)                AS n_season_0,
    count_if(averageRating IS NOT NULL)       AS n_rated,
    round(100.0 * count_if(averageRating IS NOT NULL) / count(*), 1) AS pct_rated,
    count_if(writers IS NOT NULL)             AS n_with_writers,
    round(100.0 * count_if(writers IS NOT NULL) / count(*), 1) AS pct_with_writers
FROM ep;

-- 3b. Distribution of season numbers (spot year-like or huge values)
SELECT CASE WHEN seasonNumber IS NULL THEN 'NULL'
            WHEN seasonNumber = 0     THEN '0'
            WHEN seasonNumber <= 10   THEN '1-10'
            WHEN seasonNumber <= 30   THEN '11-30'
            WHEN seasonNumber <= 100  THEN '31-100'
            WHEN seasonNumber BETWEEN 1900 AND 2030 THEN '1900-2030 (year-like)'
            ELSE 'other >100' END AS season_bucket,
       count(*) AS n_episodes,
       count(DISTINCT parentTconst) AS n_series
FROM ep GROUP BY season_bucket ORDER BY min(coalesce(seasonNumber, -1));

-- 3c. Max season number observed
SELECT max(seasonNumber) AS max_season FROM ep;

-- 3d. Series with gaps: numbered seasons that are not contiguous 1..max
WITH s AS (
    SELECT parentTconst, count(DISTINCT seasonNumber) AS n_seasons,
           min(seasonNumber) AS min_s, max(seasonNumber) AS max_s
    FROM ep WHERE seasonNumber >= 1 GROUP BY parentTconst)
SELECT count(*) AS n_series_with_numbered_seasons,
       count_if(min_s <> 1)          AS n_not_starting_at_1,
       count_if(max_s <> n_seasons)  AS n_with_gaps_or_not_from_1
FROM s;

-- 3e. Duplicate (series, season, episode) numbers
SELECT count(*) AS n_duplicate_keys, sum(n) AS n_rows_involved FROM (
    SELECT parentTconst, seasonNumber, episodeNumber, count(*) AS n
    FROM ep WHERE seasonNumber IS NOT NULL AND episodeNumber IS NOT NULL
    GROUP BY ALL HAVING count(*) > 1);

-- 3f. Episodes per season: distribution (numbered seasons >= 1)
WITH ss AS (SELECT parentTconst, seasonNumber, count(*) AS n_ep
            FROM ep WHERE seasonNumber >= 1 GROUP BY ALL)
SELECT count(*) AS n_series_seasons,
       quantile_cont(n_ep, [0.1, 0.25, 0.5, 0.75, 0.9, 0.99]) AS q10_25_50_75_90_99,
       max(n_ep) AS max_ep
FROM ss;

-- 3g. Votes per rated episode: distribution
SELECT count(*) AS n_rated_episodes,
       quantile_cont(numVotes, [0.1, 0.25, 0.5, 0.75, 0.9, 0.99]) AS q10_25_50_75_90_99,
       max(numVotes) AS max_votes
FROM ep WHERE numVotes IS NOT NULL;

-- 3h. Rating coverage within a season: share of episodes rated per series-season
WITH ss AS (SELECT parentTconst, seasonNumber,
                   count(*) AS n_ep, count(averageRating) AS n_rated
            FROM ep WHERE seasonNumber >= 1 GROUP BY ALL)
SELECT CASE WHEN n_rated = 0 THEN '0%'
            WHEN n_rated = n_ep THEN '100%'
            WHEN 1.0 * n_rated / n_ep >= 0.5 THEN '50-99%'
            ELSE '1-49%' END AS rated_share,
       count(*) AS n_series_seasons
FROM ss GROUP BY rated_share ORDER BY rated_share;
