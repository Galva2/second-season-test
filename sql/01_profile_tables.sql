-- 01_profile_tables.sql
-- Question: what is in each raw table? Row counts, nulls per column, duplicate keys.
-- (Note for run_sql.py: no semicolons inside comments or strings.)

-- 1a. Row counts and distinct primary keys per table
SELECT 'basics'  AS tbl, count(*) AS n_rows, count(DISTINCT tconst) AS n_distinct_tconst FROM basics
UNION ALL SELECT 'episode', count(*), count(DISTINCT tconst) FROM episode
UNION ALL SELECT 'ratings', count(*), count(DISTINCT tconst) FROM ratings
UNION ALL SELECT 'crew',    count(*), count(DISTINCT tconst) FROM crew;

-- 1b. basics: null share per column (pct of all rows)
SELECT
    round(100.0 * count_if(titleType      IS NULL) / count(*), 2) AS pct_null_titleType,
    round(100.0 * count_if(primaryTitle   IS NULL) / count(*), 2) AS pct_null_primaryTitle,
    round(100.0 * count_if(startYear      IS NULL) / count(*), 2) AS pct_null_startYear,
    round(100.0 * count_if(endYear        IS NULL) / count(*), 2) AS pct_null_endYear,
    round(100.0 * count_if(runtimeMinutes IS NULL) / count(*), 2) AS pct_null_runtime,
    round(100.0 * count_if(genres         IS NULL) / count(*), 2) AS pct_null_genres
FROM basics;

-- 1c. basics: title types (how big is our population vs everything else)
SELECT titleType, count(*) AS n, round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct
FROM basics GROUP BY titleType ORDER BY n DESC;

-- 1d. episode: null share per column
SELECT
    count(*) AS n_rows,
    count_if(parentTconst  IS NULL) AS n_null_parent,
    count_if(seasonNumber  IS NULL) AS n_null_season,
    count_if(episodeNumber IS NULL) AS n_null_episode,
    round(100.0 * count_if(seasonNumber  IS NULL) / count(*), 2) AS pct_null_season,
    round(100.0 * count_if(episodeNumber IS NULL) / count(*), 2) AS pct_null_episode
FROM episode;

-- 1e. ratings: value ranges
SELECT min(averageRating) AS min_rating, max(averageRating) AS max_rating,
       min(numVotes) AS min_votes, median(numVotes) AS median_votes, max(numVotes) AS max_votes
FROM ratings;

-- 1f. crew: null share for directors and writers
SELECT
    round(100.0 * count_if(directors IS NULL) / count(*), 2) AS pct_null_directors,
    round(100.0 * count_if(writers   IS NULL) / count(*), 2) AS pct_null_writers
FROM crew;

-- 1g. Referential integrity: do the keys join?
SELECT
    (SELECT count(*) FROM ratings r ANTI JOIN basics b USING (tconst))                       AS ratings_without_basics,
    (SELECT count(*) FROM episode e ANTI JOIN basics b USING (tconst))                       AS episodes_without_basics,
    (SELECT count(*) FROM episode e ANTI JOIN basics b ON e.parentTconst = b.tconst)         AS episodes_parent_missing;
