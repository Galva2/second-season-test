-- 06_validate.sql
-- Question: are the clean tables built correctly?
-- Structural checks, value ranges, and spot checks on well-known series.

-- 6a. Grain: exactly one row per series and per (series, season)
SELECT
    (SELECT count(*) - count(DISTINCT series_id) FROM series)                     AS dup_series,
    (SELECT count(*) - count(DISTINCT (series_id, season)) FROM season)           AS dup_series_season,
    (SELECT count(*) - count(DISTINCT episode_id) FROM episode_clean)             AS dup_episodes;

-- 6b. Value ranges (every column should be within its expected bounds)
SELECT
    count_if(n_rated > n_episodes)                          AS n_rated_gt_episodes,
    count_if(rated_share < 0 OR rated_share > 1)            AS bad_rated_share,
    count_if(rating < 1 OR rating > 10)                AS bad_rating,
    count_if(rating_weighted < 1 OR rating_weighted > 10)   AS bad_rating_weighted,
    count_if(is_qualifying AND (median_votes < 20 OR rated_share < 0.8)) AS bad_qualifying_flag,
    count_if(is_qualifying AND rating IS NULL)         AS qualifying_without_rating,
    min(season_year) AS min_season_year, max(season_year) AS max_season_year
FROM season;

-- 6c. Episode numbers repeated within a season (IMDb data-entry duplicates)
SELECT count(*) AS n_dup_episode_numbers FROM (
    SELECT series_id, season, episode FROM episode_clean
    WHERE episode IS NOT NULL GROUP BY ALL HAVING count(*) > 1);

-- 6d. Well-known series: seasons and episodes vs public knowledge
--     Expected (public knowledge, not from this data): Breaking Bad 5 seasons / 62 episodes,
--     Game of Thrones 8 / 73, Friends 10 / 236, The Sopranos 6 / 86, The Wire 5 / 60, Lost 6 / 121.
SELECT s.series_id, s.title, s.startYear, s.endYear, s.is_ended,
       s.n_seasons_max, s.n_seasons_qualifying,
       sum(se.n_episodes) AS n_episodes
FROM series s JOIN season se USING (series_id)
WHERE s.series_id IN ('tt0903747', 'tt0944947', 'tt0108778', 'tt0141842', 'tt0306414', 'tt0411008', 'tt0386676')
GROUP BY ALL ORDER BY s.title;

-- 6e. Season detail: Game of Thrones (season 8 is widely reported as the lowest-rated)
SELECT season, season_year, n_episodes, n_rated, median_votes, rating, rating_weighted,
       n_writers, is_qualifying
FROM season WHERE series_id = 'tt0944947' ORDER BY season;

-- 6f. Season detail: Breaking Bad
SELECT season, season_year, n_episodes, n_rated, median_votes, rating, rating_weighted,
       n_writers, is_qualifying
FROM season WHERE series_id = 'tt0903747' ORDER BY season;

-- 6g. Writer continuity check (no names available): in how many seasons does each
--     Breaking Bad writer id appear? A creator/showrunner should appear in all 5.
SELECT writer, count(*) AS n_seasons_present
FROM (SELECT season, unnest(writer_set) AS writer FROM season WHERE series_id = 'tt0903747')
GROUP BY writer ORDER BY n_seasons_present DESC, writer LIMIT 8;

-- 6h. Season-rating definitions: how different are the chosen simple mean (rating) and the vote-weighted mean?
SELECT count(*) AS n_qualifying_seasons,
       round(corr(rating, rating_weighted), 4)                         AS correlation,
       round(median(abs(rating - rating_weighted)), 3)                 AS median_abs_diff,
       round(quantile_cont(abs(rating - rating_weighted), 0.95), 3)    AS p95_abs_diff,
       round(max(abs(rating - rating_weighted)), 3)                    AS max_abs_diff
FROM season WHERE is_qualifying;

-- 6i. Writer data coverage in qualifying seasons
SELECT count(*) AS n_qualifying_seasons,
       count_if(n_ep_with_writers = 0)                     AS no_writer_data,
       count_if(n_ep_with_writers < n_episodes AND n_ep_with_writers > 0) AS partial_writer_data,
       count_if(n_ep_with_writers = n_episodes)            AS full_writer_data
FROM season WHERE is_qualifying;
