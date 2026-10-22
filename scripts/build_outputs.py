"""Phase 6: build the README charts and the Power BI CSV exports.

Every number comes from MySQL. Summary tables are produced by running the exact
statements in the numbered analysis files (sql/mysql/11, 12, 21, 31), so the charts,
the CSVs and the SQL a reviewer reads can never disagree. Genre figures come from
scripts/q1_genre_uncertainty.py (era adjustment).

Outputs:
    outputs/charts/*.png      5 static charts for the README
    outputs/powerbi/*.csv     fact/dimension tables + summary tables for Power BI

Usage:
    python scripts/build_outputs.py
"""

import sys
from pathlib import Path

import matplotlib
import matplotlib.pyplot as plt
import pandas as pd

import q1_genre_uncertainty
import run_mysql

matplotlib.use("Agg")

ROOT = Path(__file__).resolve().parent.parent
SQL = ROOT / "sql" / "mysql"
CHARTS = ROOT / "outputs" / "charts"
POWERBI = ROOT / "outputs" / "powerbi"

# Colorblind-safe palette (light mode). Blue/orange pass a color-vision-deficiency contrast check.
SURFACE = "#fcfcfb"
INK = "#0b0b0b"
INK_2 = "#52514e"
MUTED = "#898781"
GRID = "#e1e0d9"
BASELINE = "#c3c2b7"
BLUE = "#2a78d6"        # series 1
BLUE_LIGHT = "#cde2fb"  # sequential step 100, for the IQR band
ORANGE = "#eb6834"      # series 2
DEEMPH = "#c3c2b7"      # de-emphasized bars
SOURCE = "Source: IMDb non-commercial datasets (personal, non-commercial use). Scripted TV series only."

FOCUS_GENRES = ["Drama", "Comedy", "Thriller", "Sci-Fi", "Fantasy"]  # decision #20


# ------------------------------------------------------------------ data access
def query(con, sql: str) -> pd.DataFrame:
    cur = con.cursor()
    cur.execute(sql)
    df = pd.DataFrame(cur.fetchall(), columns=cur.column_names)
    cur.close()
    return df


def run_statement(con, filename: str, index: int, setup: tuple[int, ...] = ()) -> pd.DataFrame:
    """Run statement number `index` of a numbered SQL file (after any `setup` statements,
    e.g. temporary tables) and return its result."""
    stmts = run_mysql.split_statements((SQL / filename).read_text(encoding="utf-8"))
    cur = con.cursor()
    for i in setup:
        cur.execute(stmts[i])
    cur.close()
    return query(con, stmts[index])


def to_float(df: pd.DataFrame) -> pd.DataFrame:
    """MySQL returns DECIMAL as Python Decimal. Convert numeric-looking columns to float."""
    for c in df.columns:
        if df[c].dtype == object:
            try:
                df[c] = pd.to_numeric(df[c])
            except (ValueError, TypeError):
                continue
        # Whole-number columns with NULLs come back as float (58.0). Keep them integer.
        if df[c].dtype.kind == "f" and df[c].dropna().mod(1).eq(0).all():
            df[c] = df[c].astype("Int64")
    return df


# ----------------------------------------------------------------- chart style
def style_axes(ax, title: str, subtitle: str) -> None:
    ax.set_facecolor(SURFACE)
    ax.figure.set_facecolor(SURFACE)
    for side in ["top", "right", "left"]:
        ax.spines[side].set_visible(False)
    ax.spines["bottom"].set_color(BASELINE)
    ax.tick_params(colors=MUTED, labelcolor=INK_2, length=0)
    ax.grid(axis="y", color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    ax.figure.text(0.02, 0.965, title, fontsize=14, fontweight="bold", color=INK, ha="left", va="top")
    ax.figure.text(0.02, 0.905, subtitle, fontsize=9.5, color=INK_2, ha="left", va="top")
    ax.figure.text(0.02, 0.02, SOURCE, fontsize=7.5, color=MUTED, ha="left", va="bottom")


def new_figure():
    plt.rcParams["font.family"] = ["Segoe UI", "DejaVu Sans"]
    fig, ax = plt.subplots(figsize=(9, 5.2), dpi=150)
    fig.subplots_adjust(left=0.09, right=0.97, top=0.78, bottom=0.15)
    return fig, ax


def save(fig, name: str) -> None:
    path = CHARTS / name
    fig.savefig(path, facecolor=SURFACE)
    plt.close(fig)
    print(f"chart    {path.relative_to(ROOT)}")


# ---------------------------------------------------------------------- charts
def chart_retention_curve(curve: pd.DataFrame) -> None:
    d = curve[curve.transition.isin([f"{i}->{i + 1}" for i in range(1, 9)])].reset_index(drop=True)
    x = range(len(d))
    fig, ax = new_figure()
    ax.fill_between(x, d.p25_vote_change_pct, d.p75_vote_change_pct, color=BLUE_LIGHT, linewidth=0,
                    label="Middle half of series (25th–75th percentile)")
    ax.plot(x, d.median_vote_change_pct, color=BLUE, linewidth=2, marker="o", markersize=7,
            markeredgecolor=SURFACE, markeredgewidth=2, label="Median series")
    ax.axhline(0, color=BASELINE, linewidth=1)
    for i in [0, len(d) - 1]:
        ax.annotate(f"{d.median_vote_change_pct[i]:+.1f}%", (i, d.median_vote_change_pct[i]),
                    textcoords="offset points", xytext=(0, -16), ha="center", fontsize=9.5, color=INK)
    ax.set_xticks(list(x), [t.replace("->", "→") + f"\nn={n:,}" for t, n in zip(d.transition, d.n_pairs)], fontsize=8.5)
    ax.set_ylabel("Change in median votes per episode vs previous season (%)", color=INK_2, fontsize=9)
    ax.set_xlabel("Season transition (n = series pairs)", color=INK_2, fontsize=9)
    ax.legend(loc="lower right", frameon=False, fontsize=8.5, labelcolor=INK_2)
    style_axes(ax, "The biggest audience drop happens between season 1 and season 2",
               "IMDb votes per episode as an audience proxy, consecutive qualifying seasons. "
               "Later transitions include only series that survived.")
    save(fig, "q1_retention_curve.png")


def chart_biggest_drop(panel_b: pd.DataFrame) -> None:
    d = panel_b.reset_index(drop=True)
    labels = [t.replace("->", "→") for t in d.biggest_drop_at]
    colors = [BLUE if t == "1->2" else DEEMPH for t in d.biggest_drop_at]
    fig, ax = new_figure()
    ax.bar(labels, d.pct_series, color=colors, width=0.6, edgecolor=SURFACE, linewidth=2)
    ax.axhline(25, color=MUTED, linewidth=1)
    ax.text(len(d) - 0.5, 26.5, "If drops were random: 25%", ha="right", fontsize=8.5, color=INK_2)
    for i, v in enumerate(d.pct_series):
        ax.text(i, v + 1.5, f"{v:.1f}%", ha="center", fontsize=10, color=INK)
    ax.set_ylim(0, 80)
    ax.set_ylabel("Share of series (%)", color=INK_2, fontsize=9)
    ax.set_xlabel("Transition with that series' biggest vote drop", color=INK_2, fontsize=9)
    n = int(d.n_series.sum())
    style_axes(ax, f"For {d.pct_series[0]:.0f}% of series, the biggest drop is season 1 → 2",
               f"Fixed panel: the same {n:,} series, each with seasons 1–5 all qualifying.")
    save(fig, "q1_biggest_drop.png")


def chart_genres(genre: pd.DataFrame) -> None:
    d = genre[genre.genre.isin(FOCUS_GENRES + ["ALL"])].copy()
    d["lost"] = -d.era_adjusted_median_pct
    d = d.sort_values("lost").reset_index(drop=True)
    d["label"] = d.genre.replace({"ALL": "All series"})
    colors = [DEEMPH if g == "ALL" else BLUE for g in d.genre]
    fig, ax = new_figure()
    fig.subplots_adjust(left=0.14)
    ax.barh(d.label, d.lost, color=colors, height=0.6, edgecolor=SURFACE, linewidth=2)
    for i, (v, n) in enumerate(zip(d.lost, d.n_pairs)):
        ax.text(v + 0.4, i, f"{v:.1f}%   (n={n:,})", va="center", fontsize=9, color=INK)
    ax.grid(axis="y", visible=False)
    ax.grid(axis="x", color=GRID, linewidth=0.8)
    ax.set_xlim(0, 40)
    ax.set_xlabel("Median share of votes lost from season 1 to season 2, era-adjusted (%)", color=INK_2, fontsize=9)
    style_axes(ax, "Sci-Fi and Fantasy lose more of their season-1 audience",
               "Era-adjusted to the same mix of release periods. Pairs with season 2 aired ≤ 2023. "
               "Genres overlap (a series counts in each of its genres).")
    save(fig, "q1_genre_season2_drop.png")


def chart_pilot_signal(buckets: pd.DataFrame, overall_pct: float) -> None:
    d = buckets[buckets.predictor == "season 1"].reset_index(drop=True)
    labels = [b.split(") ")[1] for b in d.rating_bucket]
    peak = d.pct_got_season_2.idxmax()
    colors = [BLUE if i == peak else "#86b6ef" for i in range(len(d))]
    fig, ax = new_figure()
    ax.bar(labels, d.pct_got_season_2, color=colors, width=0.62, edgecolor=SURFACE, linewidth=2)
    ax.axhline(overall_pct, color=MUTED, linewidth=1)
    ax.text(-0.4, overall_pct + 1.2, f"All ended series: {overall_pct:.1f}%", fontsize=8.5, color=INK_2)
    for i, v in enumerate(d.pct_got_season_2):
        ax.text(i, v + 1.5, f"{v:.1f}%", ha="center", fontsize=10, color=INK)
    ax.set_xticks(range(len(d)), [f"{lab}\nn={n:,}" for lab, n in zip(labels, d.n_series)], fontsize=9)
    ax.set_ylim(0, 80)
    ax.set_ylabel("Got a season 2 (%)", color=INK_2, fontsize=9)
    ax.set_xlabel("Season 1 rating (mean of episode ratings, n = series)", color=INK_2, fontsize=9)
    style_axes(ax, "A good season 1 helps, but a top rating is not a safe bet",
               "Ended series only. Renewal peaks at a season-1 rating of 7.5–8.0. "
               "Very high ratings partly reflect small fan bases.")
    save(fig, "q2_renewal_by_season1_rating.png")


def chart_audience_vs_quality(tertiles: pd.DataFrame) -> None:
    names = {1: "Worst third", 2: "Middle third", 3: "Best third"}
    a = tertiles[tertiles.signal_name.str.startswith("audience")].set_index("tertile")
    q = tertiles[tertiles.signal_name.str.startswith("quality")].set_index("tertile")
    x = range(3)
    w = 0.36
    fig, ax = new_figure()
    ax.bar([i - w / 2 - 0.01 for i in x], a.pct_got_season_3, width=w, color=BLUE,
           label="Audience: change in votes, S1 → S2", edgecolor=SURFACE, linewidth=2)
    ax.bar([i + w / 2 + 0.01 for i in x], q.pct_got_season_3, width=w, color=ORANGE,
           label="Quality: change in rating, S1 → S2", edgecolor=SURFACE, linewidth=2)
    for i, t in enumerate([1, 2, 3]):
        ax.text(i - w / 2 - 0.01, a.pct_got_season_3[t] + 1.5, f"{a.pct_got_season_3[t]:.1f}%", ha="center", fontsize=9.5, color=INK)
        ax.text(i + w / 2 + 0.01, q.pct_got_season_3[t] + 1.5, f"{q.pct_got_season_3[t]:.1f}%", ha="center", fontsize=9.5, color=INK)
    ax.set_xticks(list(x), [names[t] for t in [1, 2, 3]])
    ax.set_ylim(0, 90)
    ax.set_ylabel("Got a season 3 (%)", color=INK_2, fontsize=9)
    ax.set_xlabel("Series split into equal thirds by each signal (worst = biggest loss or drop)", color=INK_2, fontsize=9)
    ax.legend(loc="upper left", frameon=False, fontsize=9, labelcolor=INK_2)
    n = int(a.n_series.sum())
    style_axes(ax, "After season 2, audience change predicts renewal much better than rating change",
               f"{n:,} ended series. Worst audience third = lost more than 30% of season-1 votes.")
    save(fig, "q3_audience_vs_quality.png")


# ----------------------------------------------------------------- CSV exports
EXPORTS = {
    "dim_series.csv": """
        SELECT series_id, title, start_year, end_year, is_ended, genres,
               n_seasons_max, n_seasons_qualifying
        FROM series""",
    "bridge_series_genre.csv": "SELECT series_id, genre FROM series_genre",
    "fact_season.csv": """
        SELECT series_id, season, season_year, n_episodes, n_rated, median_votes,
               rating, is_qualifying, is_current_year
        FROM season""",
    "fact_season_pair.csv": """
        SELECT p.series_id, p.season_from, p.season_to, s.season_year AS year_from, p.year_to,
               CASE WHEN p.year_to <= 2012 THEN '<=2012'
                    WHEN p.year_to <= 2018 THEN '2013-2018'
                    ELSE '2019-2025' END AS era,
               p.votes_from, p.votes_to, p.vote_change, p.rating_from, p.rating_to, p.rating_change
        FROM q1_pairs p
        JOIN season s ON s.series_id = p.series_id AND s.season = p.season_from""",
    "fact_q2_pilot.csv": """
        SELECT series_id, title, s1_year, pilot_rating, pilot_votes, s1_rating, s1_median_votes,
               n_seasons_max, got_season_2,
               CASE WHEN s1_rating < 6.5 THEN '1) < 6.5'
                    WHEN s1_rating < 7.0 THEN '2) 6.5-7.0'
                    WHEN s1_rating < 7.5 THEN '3) 7.0-7.5'
                    WHEN s1_rating < 8.0 THEN '4) 7.5-8.0'
                    WHEN s1_rating < 8.5 THEN '5) 8.0-8.5'
                    ELSE '6) 8.5+' END AS s1_rating_bucket
        FROM q2_base""",
    "fact_q3_renewal.csv": """
        SELECT series_id, title, s2_year, vote_change, rating_change, n_seasons_max, got_season_3,
               NTILE(3) OVER (ORDER BY vote_change,   series_id) AS vote_tertile,
               NTILE(3) OVER (ORDER BY rating_change, series_id) AS rating_tertile
        FROM q3_base""",
}


def write_csv(df: pd.DataFrame, name: str) -> None:
    path = POWERBI / name
    df.to_csv(path, index=False, encoding="utf-8-sig")  # BOM so Power BI/Excel read UTF-8 titles
    print(f"csv      {path.relative_to(ROOT)}  ({len(df):,} rows)")


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    CHARTS.mkdir(parents=True, exist_ok=True)
    POWERBI.mkdir(parents=True, exist_ok=True)
    con = run_mysql.connect("imdb_series")

    curve = to_float(run_statement(con, "11_q1_curve.sql", 0))
    panel_b = to_float(run_statement(con, "12_q1_panel.sql", 4, setup=(0, 1)))
    buckets = to_float(run_statement(con, "21_q2_pilot_signal.sql", 0))
    tertiles = to_float(run_statement(con, "31_q3_audience_vs_quality.sql", 0))
    overall_s2 = float(query(con, "SELECT 100 * AVG(got_season_2) AS p FROM q2_base").p[0])
    genre, _ = q1_genre_uncertainty.compute()

    chart_retention_curve(curve)
    chart_biggest_drop(panel_b)
    chart_genres(genre)
    chart_pilot_signal(buckets, overall_s2)
    chart_audience_vs_quality(tertiles)

    for name, sql in EXPORTS.items():
        write_csv(to_float(query(con, sql)), name)
    write_csv(curve, "summary_q1_retention_curve.csv")
    write_csv(panel_b, "summary_q1_biggest_drop.csv")
    write_csv(genre, "summary_q1_genre_season2_drop.csv")
    write_csv(buckets, "summary_q2_renewal_by_rating.csv")
    write_csv(tertiles, "summary_q3_renewal_by_tertile.csv")
    con.close()


if __name__ == "__main__":
    main()
