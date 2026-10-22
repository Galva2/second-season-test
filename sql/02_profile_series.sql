-- 02_profile_series.sql
-- Question: what does the tvSeries population look like before any filtering?
-- Status (ended / running), years, genres, rating coverage, adult titles.

-- 2a. tvSeries vs tvMiniSeries: counts, ended share, adult share
SELECT titleType,
       count(*)                                   AS n_titles,
       count_if(endYear IS NOT NULL)              AS n_with_endYear,
       round(100.0 * count_if(endYear IS NOT NULL) / count(*), 1) AS pct_ended,
       count_if(startYear IS NULL)                AS n_no_startYear,
       count_if(isAdult = 1)                      AS n_adult
FROM basics
WHERE titleType IN ('tvSeries', 'tvMiniSeries')
GROUP BY titleType;

-- 2b. tvSeries: how many have a series-level rating, and how many have any episode at all
SELECT
    count(*) AS n_series,
    count(r.tconst) AS n_series_rated,
    count_if(EXISTS (SELECT 1 FROM episode e WHERE e.parentTconst = b.tconst)) AS n_series_with_episodes
FROM basics b
LEFT JOIN ratings r USING (tconst)
WHERE b.titleType = 'tvSeries';

-- 2c. tvSeries by start decade
SELECT (startYear // 10) * 10 AS decade, count(*) AS n_series,
       count_if(endYear IS NOT NULL) AS n_ended
FROM basics
WHERE titleType = 'tvSeries'
GROUP BY decade ORDER BY decade;

-- 2d. Odd year values: endYear before startYear, years in the future
SELECT
    count_if(endYear < startYear)  AS n_end_before_start,
    count_if(startYear > 2026)     AS n_start_after_2026,
    count_if(endYear   > 2026)     AS n_end_after_2026,
    min(startYear) AS min_start, max(startYear) AS max_start
FROM basics WHERE titleType = 'tvSeries';

-- 2e. Genres: a series can have up to 3 genres (comma-separated). Count series per genre.
SELECT genre, count(*) AS n_series
FROM (SELECT unnest(string_split(genres, ',')) AS genre
      FROM basics WHERE titleType = 'tvSeries' AND genres IS NOT NULL)
GROUP BY genre ORDER BY n_series DESC;

-- 2f. How many genres per series
SELECT CASE WHEN genres IS NULL THEN 0 ELSE len(string_split(genres, ',')) END AS n_genres,
       count(*) AS n_series
FROM basics WHERE titleType = 'tvSeries'
GROUP BY n_genres ORDER BY n_genres;
