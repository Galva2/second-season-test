# Decision log

Every filtering or definition decision, why it was made, and its effect on row counts.
Row counts are only recorded from queries that were actually run.

| # | Phase | Decision | Rationale | Rows before → after |
|---|-------|----------|-----------|---------------------|
| 1 | 0 | Use only `title.basics`, `title.episode`, `title.ratings`, `title.crew`; exclude `title.principals`. | Principals is very large and not needed for the questions (writers come from `title.crew`). | n/a |
| 2 | 0 | Keep raw files gzipped; read `.tsv.gz` directly with DuckDB. | Saves disk space; DuckDB decompresses on the fly. Later converted to Parquet for speed (#4). | n/a |
| 3 | 0 | Static charts with matplotlib; dropped `kaleido` (plotly static export). | Kaleido v1 requires a Chrome install; matplotlib covers README PNGs. | n/a |
| 4 | 1 | Convert raw TSV to typed Parquet (`scripts/build_parquet.py`): `nullstr='\N'`, `quote=''`, read as text then `TRY_CAST`. | Faster queries. Cast-failure counting makes bad values visible. Disabling quotes protects titles containing a bare `"`. | Row counts match raw files exactly: basics 12,880,486 / episode 9,962,602 / ratings 1,723,150 / crew 12,880,486. 0 cast failures. |

## Phase 1 profiling facts (from sql/01–04)

- `ratings` minimum numVotes = 5 → IMDb only publishes ratings at ≥5 votes. Unrated ≠ zero audience.
- tvSeries: 307,289 titles. 120,660 (39.3%) have endYear. 25,876 have no startYear. 3,164 isAdult. 199,370 have ≥1 episode.
- Episodes of tvSeries: 9,627,551. NULL seasonNumber: 2,065,303 (45,758 series). **Season 0 does not exist** (specials are NULL instead). Only 838,998 episodes (8.7%) are rated. 45.9% have writers.
- Season numbers > 100: 4,938 episodes (1,331 year-like in 33 series + 3,607 other in 10 series) (year-like numbers such as 2024, or running counts like House Hunters 101–281).
- 7,371 of 175,408 series with numbered seasons have gaps or don't start at 1. 5 duplicate (series, season, episode) keys.
- 257,752 of 334,358 series-seasons (77%) have zero rated episodes.
- Median of season-level median votes (seasons ≥50% rated): scripted 30, non-scripted 15.
- Writer coverage in candidate seasons (scripted, ≥50% rated, ≥20 votes): 91.5% of episodes, 1,461 of 24,724 seasons have no writer data.

## Decisions after Phase 1 profiling

Candidate impact numbers come from `sql/04_threshold_candidates.sql` (4c). The last column shows the final row counts from the final build (`sql/05_build_tables.sql`).

| # | Phase | Decision | Rationale | Rows before → after |
|---|-------|----------|-----------|---------------------|
| 5 | 1 | **Scripted series only.** Population = `titleType = 'tvSeries'`, `isAdult = 0`, and genres contain none of Talk-Show, News, Reality-TV, Game-Show, Documentary, Adult (Sport and NULL genres added in #11). tvMiniSeries excluded. | Retention, pilot and writers'-room questions are about scripted products. Non-scripted shows behave differently (median season votes 15 vs 30 for scripted, per 4b). Stated in README. | tvSeries 307,289 → 167,650 scripted series (including #11). Step by step in the funnel below. |
| 6 | 1 | **Season votes = median numVotes over the season's rated episodes. A season qualifies only if this is ≥ 20.** | Median resists a single high-vote pilot/finale. Below 20, a rating rests on a handful of self-selected voters. At ≥20 vs ≥50: 4,770 vs 3,212 series with 2+ qualifying seasons (scripted, 80% rated). | Seasons 37,491 → 24,013 (series 18,414 → 11,026). |
| 7 | 1 | **A season qualifies only if ≥ 80% of its episodes are rated.** | The season median must describe the whole season, not just its popular episodes. Costs ~1% of seasons vs a 50% rule (24,724 → 24,471 at ≥20 votes). | Seasons 176,251 → 37,491 (series 105,421 → 18,414). |
| 8 | 1 | **Season numbers outside 1–100 are excluded** (NULL = specials/undated, plus year-like and running-count numbers). | They are not comparable "season N" cohorts. | Episodes 4,842,040 → 4,625,049 (−216,676 with NULL season, −315 with season > 100). |
| 9 | 1 | **Q2 "ended series" = `endYear IS NOT NULL AND endYear <= 2026`. No minimum season count. Season 1 must qualify.** | Right-censoring: running series' final length is unknown. 139 series have endYear > 2026 (planned, not actual). One-season cancellations are the outcome being predicted, so requiring ≥2 seasons would create survivorship bias. | 8,252 ended series with a qualifying season 1 (after #12 and #26). |
| 10 | 1 | **Season-over-season comparisons use only truly consecutive pairs (N-1, N) where both seasons qualify.** A missing or non-qualifying season breaks the pair. Series with gaps are kept. | Gaps are mostly incomplete IMDb data entry (e.g. Happy Tree Friends 1,2,3,5,6. Peppa Pig 1–9,11). Comparing across a gap would mislabel a 2-season change as 1. Dropping whole series would discard valid pairs. | 12,582 consecutive qualifying pairs (after #12 and #14). |
| 11 | 1 | **Also exclude series tagged Sport and series with no genres.** | Genres are user-entered, so "scripted" = "not tagged as non-scripted". Spot checks of season>100 cases found non-scripted shows slipping through (Wrexham A.F.C. = Sport docuseries, NFL Follow Your Team = no genre). Cost: 390 + 41 = 431 of 24,471 qualifying seasons (1.8%). | Series 304,125 → 279,915 (−24,210 with no genre). 174,130 → 167,650 (−6,480 tagged Sport). |

Known limitation (stated in README): the scripted filter relies on user-entered IMDb genres, so some non-scripted shows may remain (e.g. Fort Boyard, a game show tagged Adventure/Comedy/Family).

## Phase 2 build results (sql/05_build_tables.sql, first build, before #12)

Funnel (series / seasons remaining after each step):

| Step | Series | Seasons |
|---|---|---|
| 1. all tvSeries | 307,289 | |
| 2. not adult | 304,125 | |
| 3. has genres | 279,915 | |
| 4. no Talk-Show/News/Reality-TV/Game-Show/Documentary/Adult | 174,130 | |
| 5. no Sport (= scripted population) | 167,650 | |
| 6. has ≥1 numbered season 1–100 | 105,732 | 176,777 |
| 7. season ≥80% episodes rated | 18,435 | 37,532 |
| 8. season median votes ≥20 (= qualifying) | 11,035 | 24,040 |

Episodes of scripted series: 4,842,040 → dropped NULL season 216,676 and season >100 315 → kept 4,625,049.
Pools: 4,707 series with ≥2 qualifying seasons. 12,869 consecutive qualifying pairs (Q1). 8,370 ended series with qualifying S1 (Q2).

Validation (sql/06_validate.sql): no duplicate keys, all values in range. Breaking Bad, Game of Thrones, Friends, Lost, The Office, The Sopranos and The Wire have the expected season counts. Episode-count differences vs public figures: Game of Thrones 74 (an "Unaired Original Pilot" listed as S1 episode 0). Friends 234 and The Office 191 (IMDb lists double-length episodes as one entry, and episode numbers are contiguous with all episodes rated).

## Decisions after the Phase 2 first build

| # | Phase | Decision | Rationale | Rows before → after |
|---|-------|----------|-----------|---------------------|
| 12 | 2 | **Exclude episode number 0.** The pilot is defined as season 1, episode 1 (the first aired episode). | Episode 0 holds unaired pilots and specials (e.g. Game of Thrones "Unaired Original Pilot", Sherlock "The Abominable Bride", Doctor Who Christmas specials), not regular season episodes. | Episodes 4,625,049 → 4,621,376 (−3,673). Qualifying seasons 24,040 → 24,013. Q1 pairs 12,869 → 12,851. Q2 pool 8,370 → 8,368. Game of Thrones now 73 episodes (matches public count). |
| 13 | 2 | **Season rating = simple (unweighted) mean of episode ratings.** Column `rating`. `rating_weighted` is kept only for robustness checks. Explain in README. | Every episode counts once. Easy to explain. A single viral episode cannot dominate. In practice the two definitions are almost identical: correlation 0.9955, median absolute difference 0.016 points (24,013 qualifying seasons). | n/a |
| 14 | 2 | **Season pairs (Q1, Q3) exclude pairs whose later season started in 2026** (`is_current_year`). **Phase 3 adds a robustness check** using only pairs whose later season started ≤ 2023 (at least ~3 years of vote accumulation). | Votes keep accumulating for years after airing. Median vote change between consecutive qualifying seasons grows more negative for recent years (later season 2018: −15.8%, 2023: −25.6%, 2025: −32.0%, 2026: −42.9%), consistent with less accumulation time (a real audience trend may also contribute, and the two cannot be fully separated). Only 736 seasons from 2026 qualify vs ~1,100–1,300 per year in 2021–2025. | Q1 pairs 12,851 → 12,582 (−269). Robustness subset (later season ≤ 2023): 11,603 pairs. |

Wording rule for findings: vote-based retention numbers must be stated with their time window (e.g. "among seasons that aired before 2023"), not as general audience loss.

## Decisions in Phase 3 setup

| # | Phase | Decision | Rationale | Rows before → after |
|---|-------|----------|-----------|---------------------|
| 15 | 3 | **Hybrid stack: DuckDB for preparation, MySQL 8 for analysis.** Clean tables exported to CSV and loaded into MySQL database `imdb_series`. List columns are normalized into `series_genre` (251,173 rows) and `season_writer` (572,733 rows). | MySQL is the SQL dialect I work in, so all analysis queries are written in it. Raw-file parsing and comma-list splitting stay in DuckDB, where they are one-liners. | Export: series 167,650, season 176,251, episode 4,621,376 |

MySQL load verified (sql/mysql/00_schema_and_load.sql, ~5 min): row counts identical to export for all 5 tables. DuckDB vs MySQL parity on `season`: NULL season_year 5,530 / NULL rating 124,781 / sum total_votes 198,318,342 / sum rating 385,127.06 / sum median_votes 14,336,394.5, identical in both. Titles with special characters survive the round trip (14 with `"`, 1 with `\`, 2,806 with `,`, max length 146, identical in both). Qualifying seasons in MySQL: 24,013.

## Phase 3 (Q1) design decisions

| # | Phase | Decision | Rationale | Rows before → after |
|---|-------|----------|-----------|---------------------|
| 16 | 3 | **Vote change of a pair = median_votes(N) / median_votes(N−1) − 1.** Rating change = rating(N) − rating(N−1). | Ratio is scale-free, so a big and a small series are comparable. Both seasons already have median votes ≥ 20, so the ratio is stable. | n/a |
| 17 | 3 | **Genre: a series counts in every genre it has. Only genres with ≥ 150 distinct series in Q1 pairs are compared** (13 genres: Drama, Comedy, Crime, Action, Animation, Adventure, Mystery, Romance, Family, Fantasy, Thriller, Horror, Sci-Fi). | IMDb lists genres alphabetically (100% of 54,932 multi-genre series), so "first genre" is meaningless. Single-genre-only leaves almost nothing (e.g. Action 3 series). Caveat: genre groups overlap. | 20 genres → 13 |
| 18 | 3 | **Two complementary views of retention.** (a) Full curve: all pairs per transition (unbalanced, survivorship-affected). (b) Balanced panel: series whose seasons 1–5 all qualify with all 4 pairs present (1,025 series). "Biggest drop" = the transition with the most negative vote change for that series. | (a) uses all data. (b) compares the same series in every transition and directly answers "where do most series lose the biggest share" (random baseline = 25% per transition). | Panel: 1,025 series |
| 19 | 3 | **Include a decision-rule preview in Q1:** for triples of consecutive qualifying seasons, bucket the N−1→N vote change and measure what happens at N→N+1 (rating up, votes recover), plus, for ended series, whether a season N+1 exists at all. | Links retention directly to the renew/end question. Caveat: the triple view only covers series that reached N+1 (survivorship). | Computed in Phase 3 |
| 20 | 3 | **Q1 genre story focuses on 5 genres: Drama, Comedy, Thriller, Sci-Fi, Fantasy.** All 13 eligible genres stay in the Power BI export. | After era adjustment (scripts/q1_genre_uncertainty.py) most genres cluster at −23% to −26% (1→2), so 13 rows add little. Drama and Comedy = baseline (largest). Sci-Fi (−31.6%, bootstrap CI −32.2 to −28.2) and Fantasy (−28.7%) = clearest genre effect, and they are almost disjoint sets (11 shared series = 7.9% of Sci-Fi, 4.3% of Fantasy), so they confirm the pattern independently. Thriller = cautionary case: raw −30.4% but 49.8% of its pairs are 2019–2023, adjusted −27.6%. Caveat: 55–75% of these genre series are also tagged Drama. | 13 → 5 genres in the main story |

### Q1 robustness facts (sql/mysql/14)

- Pairs with later season ≤ 2023 vs all: median vote change differs by < 1 point at every transition (1→2: −24.5% vs −23.6%). Panel biggest drop at 1→2: 70.0% (all) vs 71.7% (≤ 2023).
- By era of the later season, 1→2 median: ≤2012 −19.7%, 2013–2018 −24.4%, 2019–2023 −34.1%. Shape (largest drop at 1→2, flattening after) holds in every era. Size does not.
- By gap between season 1 and 2 (14d): in ≤2012 the gap barely matters (−20.0 / −19.5 / −21.4% for same year / 1 year / 2+ years). In 2019–2023 it matters a lot (−26.6 / −32.0 / −38.3%), consistent with a vote-accumulation head start for season 1. Same-year pairs still drop more in 2019–2023 than in ≤2012 (−26.6% vs −20.0%), consistent with some real change. 2+ year gaps: 45% of 2019–2023 pairs (527/1,176) vs 15% of ≤2012 pairs (289/1,892). A long gap may also cause real loss, so the gap result is association only.

### Q1 decision-rule preview facts (sql/mysql/15)

- Ended series, drop at 1→2 → share that got any season 3: lost 50%+ 26.0% (n=277), lost 25–50% 55.6% (1,495), lost 0–25% 74.5% (1,906), gained 54.5% (123). Later transitions: 44.8% (67) / 47.9% (562) / 71.9% (4,525) / 59.7% (1,193).
- Era check (15c), drop at 1→2: the link holds within every era, but its strength grows with era. 25–50% vs 0–25%: ≤2012 71.5% vs 76.5%, 2013–2018 56.2% vs 73.9%, 2019–2025 41.5% vs 65.4%. "Lost 50%+" is mostly a recent-era bucket (231 of 277 pairs are 2019–2025). In older eras it has n=14 and n=32, too few to rely on.
- Triples (15a): after a drop at 1→2, votes recover at 2→3 in only 5.7–10.9% of cases (13.3% after a vote gain). Share with a rating increase at the next season is 39–48% regardless of drop size, so the size of a vote drop does not predict the next season's rating.
- Wording rule: renewal numbers are associations. Networks decide on their own viewing data, and IMDb votes likely mirror the same decline. "Ended" mixes cancellations and planned endings.

## Scope decisions after Phase 3

| # | Phase | Decision | Rationale | Rows before → after |
|---|-------|----------|-----------|---------------------|
| 21 | 3 | **Project story = "the second season test".** Q1 = when is the audience lost (season 2, and it does not come back). Q2 = can we know earlier (pilot / season 1 rating). Q3 = what should leadership watch when deciding (audience vs quality). Robustness checks go to a methodology appendix, not the main story. | Phase 3 produced many necessary side checks. A single storyline keeps the README and memo focused. | n/a |
| 22 | 3 | **Replace the writers'-room question with "audience vs quality as a renewal signal".** For ended series: compare the season-2 vote change and the season-2 rating change as predictors of getting another season. | Writer data has no names, ~12% of qualifying seasons have missing or partial writer data (1,338 none + 1,650 partial of 24,013), and IMDb does not distinguish head writers from one-episode writers, so any finding would be hard to turn into a recommendation. The new question builds on the strongest Q1 result and needs no new data. | n/a |
| 23 | 3 | **Drop secondary questions Q4 (final-season curse) and Q5 (best episode position).** | They do not serve the season-2 story. | n/a |

## Phase 4 (Q2) design decisions

| # | Phase | Decision | Rationale | Rows before → after |
|---|-------|----------|-----------|---------------------|
| 24 | 4 | **Two predictors, compared: pilot rating (S1E1) and season-1 rating (mean of S1 episodes).** | Tests whether the first episode alone carries the signal or the full season is needed. Pilot may be unrated in some series (fewer rows). | Phase 4 |
| 25 | 4 | **Primary outcome: got a season 2 (n_seasons_max ≥ 2). Secondary: share reaching 3+ seasons and average number of seasons.** | "Renew after season 1?" is the real platform decision. | n/a |
| 26 | 4 | **Exclude series whose season 1 started in 2026** (`is_current_year`), consistent with #14. | Ratings and votes for 2026 seasons are still accumulating. | Phase 4 |

Known caveat (stated in README): hindsight bias. Pilot ratings are given today, by people who may already know the series became a hit, so pilot rating may partly reflect success rather than predict it. No rating-at-air-time data exists to test this.

### Q2 results (sql/mysql/20–21)

- Base: 8,252 ended series with qualifying, non-2026 season 1. Pilot rated: 8,244. Got season 2: 4,440 (53.8%).
- Renewal by rating is an **inverted U**, not a straight line. Season 1: <6.5 35.2% (n=687), 6.5–7.0 42.8%, 7.0–7.5 55.3%, **7.5–8.0 63.9% (peak, n=2,546)**, 8.0–8.5 56.5%, 8.5+ 38.5% (n=663). Pilot rating shows the same shape (peak 61.4% at 7.5–8.0, 8.5+ 44.2%).
- Pearson correlation with got_season_2 is weak: pilot 0.090, season 1 0.074 (n=8,244). Linear correlation understates a non-monotonic link, so the bucket table is the main result. Pilot and season 1 carry about the same signal.
- Era check (21c): the peak at 7.0–8.0 and the drop at 8.0+ hold in every era of season 1 (≤2012: 46.6 / 71.0 / 65.6%, 2013–2018: 47.6 / 65.8 / 60.3%, 2019–2025: 27.9 / 40.6 / 31.1%). Renewal is lower overall in 2019–2025.
- Why 8.5+ renew less (21d): 8.5+ seasons have small audiences (median S1 votes 51 vs 115 at 7.5–8.0), so very high ratings partly reflect small enthusiastic fan bases. But within large audiences (S1 median votes ≥ 76, the overall median) 8.5+ still renew less (46.2% vs 71.0%). Remaining explanation not testable with this data (e.g. planned one-season series, no country/network field).
- Ad-hoc check (not saved as SQL): Animation share is flat across buckets (20.1–25.2%), so "anime planned as one season" does not explain the drop.
- At every rating level, large-audience series renew more than small-audience ones (e.g. 7.5–8.0: 71.0% vs 52.6%). Feeds Q3 (audience vs quality).

## Phase 5 (new Q3) — audience vs quality as a renewal signal

| # | Phase | Decision | Rationale | Rows before → after |
|---|-------|----------|-----------|---------------------|
| 27 | 5 | **Compare signals with equal thirds (NTILE(3)) of vote_change and rating_change.** Outcome = got any season 3. | The two signals are on different scales (median vote change −24%, median rating change +0.07). Equal-size groups make the best-minus-worst gap comparable. | 3,801 ended series (sql/mysql/30) |

### Q3 results (sql/mysql/31)

- 31a. Audience thirds (vote change): worst third (lost > 30.2%) 44.0% got S3, middle (lost 18.9–30.2%) 71.7%, best (lost < 18.9% or gained) 72.9%. Gap 28.9 points. Quality thirds (rating change): worst (−3.50 to −0.05) 58.6%, middle (−0.05 to +0.185) 68.3%, best (+0.186 to +3.23) 61.7%. Gap at most 9.7 points, and not monotonic.
- 31b. Holding the rating third fixed, moving from the worst to a better audience third raises renewal by 21–33 points (e.g. rating middle third: 45.6% → 77.2%). Holding the audience third fixed, the rating third changes renewal by at most ~12 points.
- 31c. Audience is the stronger signal in both eras. ≤2018: audience 56.1 / 74.8 / 73.8% vs quality 67.0 / 73.6 / 70.4%. 2019–2025: audience 34.1 / 57.0 / 66.4% vs quality 40.5 / 49.1 / 42.5%. The worst audience third is mostly recent series (695 of 1,267 are 2019–2025), but the gap holds within each era.
- Note: `signal` is a reserved word in MySQL 8, so the column is named `signal_name`.

## Phase 6 — charts and Power BI exports

| # | Phase | Decision | Rationale | Rows before → after |
|---|-------|----------|-----------|---------------------|
| 28 | 6 | **5 README charts built from the exact statements in sql/mysql/11, 12, 21, 31** (scripts/build_outputs.py runs those statements, so charts and SQL cannot disagree). Colorblind-safe blue/orange palette, checked with a color-vision-deficiency contrast test. | Single source of truth for every number. | n/a |
| 29 | 6 | **Row-level Power BI CSVs (dim_, bridge_, fact_) are gitignored. Only summary_*.csv aggregates, charts and the data dictionary are committed.** | They contain IMDb-derived rows (titles, ratings) under a personal/non-commercial license, and are ~22 MB. They are regenerated by one script. | n/a |
| 30 | 6 | Chart wording corrected to match the data: Q1 title "biggest audience drop" (not "most of the audience": median loss is 24.5%), Q2 "very high ratings partly reflect small fan bases". | Titles must not overstate findings. | n/a |

## Dashboard decisions (Power BI)

| # | Phase | Decision | Rationale | Rows before → after |
|---|-------|----------|-----------|---------------------|
| 31 | 6 | **Dashboard genre chart shows 6 genres: the 5 focus genres (#20) plus Action.** Values are raw 1→2 medians (not era-adjusted), labelled as such on the chart. README genre chart stays at the 5 focus genres, era-adjusted. | Action is a large, commercially important genre (1,015 pairs at 1→2). It behaves like the overall median (raw −24.2% vs −24.5% all, era-adjusted −24.4%), so it reinforces the "mainstream vs genre fiction" contrast instead of replacing Sci-Fi, the strongest genre finding. | n/a |
