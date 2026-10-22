"""Q1, output 3 follow-up: are the genre differences at 1->2 real?

Two checks on the median 1->2 vote change per genre (pairs with later season <= 2023):
  1. Bootstrap 95% confidence interval: resample each genre's pairs with replacement
     5,000 times, take the median each time, report the 2.5th-97.5th percentile.
  2. Era adjustment: genres differ in how many of their series are recent, and recent
     seasons show bigger drops (sql/mysql/14 14c). Compute the median within each era
     and re-weight with the era mix of ALL pairs, so every genre gets the same era mix.

Data comes from MySQL (q1_pairs + series_genre). Genre eligibility = decision #17.

Usage:
    python scripts/q1_genre_uncertainty.py
"""

import sys

import numpy as np
import pandas as pd

import run_mysql

QUERY = """
WITH eligible AS (
    SELECT g.genre
    FROM series_genre g
    JOIN (SELECT DISTINCT series_id FROM q1_pairs) s USING (series_id)
    GROUP BY g.genre
    HAVING COUNT(*) >= 150
)
SELECT g.genre, p.vote_change,
       CASE WHEN p.year_to <= 2012 THEN '<=2012'
            WHEN p.year_to <= 2018 THEN '2013-2018'
            ELSE '2019-2023' END AS era
FROM q1_pairs p
JOIN series_genre g USING (series_id)
JOIN eligible e USING (genre)
WHERE p.season_from = 1 AND p.year_to <= 2023
UNION ALL
SELECT 'ALL', vote_change,
       CASE WHEN year_to <= 2012 THEN '<=2012'
            WHEN year_to <= 2018 THEN '2013-2018'
            ELSE '2019-2023' END
FROM q1_pairs
WHERE season_from = 1 AND year_to <= 2023
"""

N_BOOT = 5000
SEED = 42


def bootstrap_ci(values: np.ndarray, rng: np.random.Generator) -> tuple[float, float]:
    samples = rng.choice(values, size=(N_BOOT, len(values)), replace=True)
    medians = np.median(samples, axis=1)
    return np.percentile(medians, 2.5), np.percentile(medians, 97.5)


def compute() -> tuple[pd.DataFrame, pd.Series]:
    """Return (per-genre table, era weights of ALL pairs)."""
    con = run_mysql.connect("imdb_series")
    cur = con.cursor()
    cur.execute(QUERY)
    df = pd.DataFrame(cur.fetchall(), columns=cur.column_names)
    con.close()
    df["vote_change"] = df["vote_change"].astype(float)

    era_weights = df[df.genre == "ALL"].era.value_counts(normalize=True)
    rng = np.random.default_rng(SEED)

    rows = []
    for genre, g in df.groupby("genre"):
        lo, hi = bootstrap_ci(g.vote_change.to_numpy(), rng)
        era_medians = g.groupby("era").vote_change.median()
        adjusted = (era_medians * era_weights).sum() / era_weights[era_medians.index].sum()
        rows.append({
            "genre": genre,
            "n_pairs": len(g),
            "pct_pairs_2019_2023": round(100 * (g.era == "2019-2023").mean(), 1),
            "median_pct": round(100 * g.vote_change.median(), 1),
            "ci95_low": round(100 * lo, 1),
            "ci95_high": round(100 * hi, 1),
            "era_adjusted_median_pct": round(100 * adjusted, 1),
        })

    return pd.DataFrame(rows).sort_values("era_adjusted_median_pct"), era_weights


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    out, era_weights = compute()
    print("Q1 1->2 median vote change by genre (later season <= 2023)")
    print(f"Era mix of ALL pairs: {era_weights.round(3).to_dict()}")
    print(out.to_string(index=False))


if __name__ == "__main__":
    main()
