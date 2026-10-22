# Memo: Using the Second Season Test in Renewal Decisions

**To:** Content Strategy leadership
**From:** Business Analytics
**Re:** What IMDb data says about when series lose their audience, and which signals track renewal

---

## Bottom line

Season 2 is the critical checkpoint. That is where series lose the most audience, and the size of that loss tracks renewal much more closely than changes in quality. We recommend a formal season-2 review using three benchmarks.

## Findings

**1. The audience drop is concentrated at season 2.**
The median scripted series loses 24.5% of its votes per episode from season 1 to season 2 (4,518 series pairs), against 12.3% at season 3 and 8.7% at season 4. In a fixed group of 1,025 series with five seasons, 70% had their largest drop at season 2. Lost audience rarely returns: only 5.7–10.9% of series gained votes again in season 3.

**2. After season 2, audience change matters more than rating change.**
Among 3,801 ended series, those in the worst third of audience change (lost more than 30%) got a season 3 only 44.0% of the time, against about 72% for the other two thirds. Splitting by rating change moved renewal by 10 points at most. The pattern holds before and after 2019, and it is strongest in the streaming era.

**3. Season 1 rating helps, but with a ceiling.**
Among 8,252 ended series, renewal after season 1 rose from 35.2% (rating below 6.5) to a peak of 63.9% (7.5–8.0), then fell to 38.5% at 8.5+. Very high ratings partly reflect small fan bases (a median of 51 votes per episode, against 115 at the peak). The pilot episode alone gives about the same signal as the full season.

## Impact

- A season-2 audience loss above 30% marks a series whose historical renewal odds are roughly 28 points lower than the rest.
- Rating improvements in season 2 do not offset audience loss. Series in the best rating third but the worst audience third renewed only 41.8% of the time.
- Genre sets the baseline. A 30% drop is about normal for Sci-Fi (31.6% median, era-adjusted) but above normal for Comedy (24.3%).

## Recommendations

1. **Make season 2 a formal review point** and compare each series' audience change with its genre benchmark (Comedy ~24%, Drama ~26%, Fantasy ~29%, Sci-Fi ~32%).
2. **Flag for review when season 2 loses more than 30% of season-1 audience.** Prioritize audience retention over rating change in that review.
3. **Read season-1 ratings as a band, not a ranking.** Below 7.0 is a warning sign. At 8.5+, check audience size before treating the rating as a strong signal.
4. **Calibrate on internal data.** These benchmarks use IMDb votes as an audience proxy. The same queries can be run on the platform's own viewing data (starts, completions, hours) to set the real thresholds.

## Caveats

These are historical associations, not causal effects. Networks decided renewals using their own data, and IMDb votes likely reflect the same decline. IMDb voters are self-selected, votes accumulate over time (so recent seasons look smaller), "ended" mixes cancellations with planned endings, and pilot ratings may carry hindsight bias. Full method and robustness checks: see the README.

*Data: IMDb non-commercial datasets (personal, non-commercial use). Scripted TV series only.*
