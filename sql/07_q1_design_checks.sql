-- 07_q1_design_checks.sql
-- Question: inputs for two Q1 design decisions.
--   (1) How to assign genres to series that have several.
--   (2) Whether a balanced panel (same series in every transition) is large enough.

-- Q1 pairs: consecutive qualifying seasons, later season not from 2026 (#10, #14).
CREATE TEMP TABLE pairs AS
SELECT a.series_id, a.season AS season_from, b.season AS season_to
FROM season a
JOIN season b ON b.series_id = a.series_id AND b.season = a.season + 1
WHERE a.is_qualifying AND b.is_qualifying AND NOT b.is_current_year;

-- 7a. Is IMDb's genre order meaningful? Share of multi-genre series whose list is alphabetical.
SELECT count(*) AS n_multi_genre_series,
       count_if(genre_list = list_sort(genre_list)) AS n_alphabetical,
       round(100.0 * count_if(genre_list = list_sort(genre_list)) / count(*), 2) AS pct_alphabetical
FROM series WHERE len(genre_list) > 1;

-- 7b. Series in Q1 pairs, per genre: (A) counted in every genre it has vs (B) single-genre series only
WITH s AS (SELECT DISTINCT series_id FROM pairs),
g AS (SELECT se.series_id, unnest(se.genre_list) AS genre, len(se.genre_list) AS n_genres
      FROM series se JOIN s USING (series_id))
SELECT genre,
       count(*)                   AS a_series_any_genre,
       count_if(n_genres = 1)     AS b_series_single_genre
FROM g GROUP BY genre ORDER BY a_series_any_genre DESC;

-- 7c. Q1 pairs by transition (unbalanced: every pair counts)
SELECT season_from || '->' || season_to AS transition, count(*) AS n_pairs
FROM pairs WHERE season_from <= 10 GROUP BY season_from, season_to ORDER BY season_from;

-- 7d. Balanced panel size: series whose seasons 1..K all qualify and form K-1 pairs
WITH runs AS (
    SELECT series_id,
           count_if(season_from = 1) AS has_1,
           -- length of the unbroken chain of pairs starting at season 1
           min(CASE WHEN season_from <> rn THEN rn END) AS first_break,
           count(*) AS n_pairs
    FROM (SELECT series_id, season_from,
                 row_number() OVER (PARTITION BY series_id ORDER BY season_from) AS rn
          FROM pairs)
    GROUP BY series_id),
chain AS (
    SELECT series_id, CASE WHEN first_break IS NULL THEN n_pairs ELSE first_break - 1 END AS chain_pairs
    FROM runs WHERE has_1 = 1)
SELECT k AS seasons_1_to_k, count_if(chain_pairs >= k - 1) AS n_series
FROM chain, (VALUES (3), (4), (5), (6)) t(k)
GROUP BY k ORDER BY k;
