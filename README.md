# NJ Transit Rail Performance: Time Series Forecast & Dashboard

A look at NJ Transit's monthly rail performance data, from 2017 through mid-2026. This project forecasts future on-time percentage, checks whether fleet reliability actually predicts performance, digs into what's driving train cancellations, and figures out how much of NJ Transit's reported delay is really Amtrak's fault. Built using SQL, R, and Power BI.

**Data source:** [njtransit.com/performance-data-download](https://www.njtransit.com/performance-data-download), NJ Transit's official monthly performance data.

## How it's organized

| Tool | What it's doing |
|---|---|
| SQL (SQLite) | Cleans the raw CSVs and joins them into one table with the features the analysis needs (lags, rolling averages, cancellation causes pivoted into columns) |
| R | Forecasts on-time % with `auto.arima`, regresses it against fleet reliability, looks at cancellation trends, and compares official vs. Amtrak-adjusted performance |
| Power BI | Ties it all together in a four-page dashboard |

## Project structure

```
data/            Raw CSVs from njtransit.com
sql/             The SQL script that builds the joined monthly_performance table
r/               R script covering the forecast, regression, and cancellation analysis
exports/         CSVs written by R for Power BI to pick up
figures/         Static charts saved by the R script
njtransit.sqbpro DB Browser for SQLite project file
*.pbix           The Power BI dashboard
```

## Running it yourself

**1. Build the database.** Import the CSVs in `data/` into a SQLite database (tables: `otp_monthly`, `otp_monthly_amtrak_adj`, `cancellations_monthly`, `mdbf_monthly`), then run:
```sql
.read sql/feature_engineering.sql
```
That builds `monthly_performance`, which everything downstream reads from.

**2. Run the R script.** Open `r/njtanalysis.R` in RStudio, set your working directory to the `r/` folder, and run it top to bottom (needs `tidyverse` and `forecast`). It'll forecast the next 6 months, run the MDBF regression, look at cancellation causes, and calculate the Amtrak gap, then write everything out to `exports/` and `figures/`.

**3. Open the dashboard.** `NJT Time Series Forecast.pbix` pulls from the SQLite database and the exported CSVs. If you rebuild the data, you'll need to refresh the connections in Power BI.

## What I found

Forecasting turned out to be quite difficult. A backtested `auto.arima` model only just edges out a naive "assume nothing changes" baseline (MAE of about 1.72 vs. 1.77) — on-time percentage behaves close to a random walk month to month, so a fancier model doesn't buy you much.

Fleet reliability does matter, but not as much as I expected going in. The relationship between MDBF and on-time % is statistically significant, and roughly translates to a 0.95 percentage point improvement in on-time performance for every 10,000 extra miles between failures. Still, it only explains about a quarter of the month-to-month variation, so it's one piece of the puzzle rather than the main driver.

Cancellation causes are noisy rather than trending. Most categories (AMTRAK, crew availability, human factor) spike unpredictably without any clear long-term direction, which suggests they're driven by one-off events rather than gradual change. Mechanical issues are the exception, sitting at a noticeably higher baseline from around 2021 onward compared to earlier years.

And a meaningful chunk of NJ Transit's reported delays trace back to Amtrak. On average, NJ Transit's on-time percentage would be 2.64 points higher if you excluded delays attributed to Amtrak-controlled infrastructure, and in the worst month that gap hit 9.2 points.

## Limitations worth knowing about

This is monthly, system-wide data, not per-trip, so it can't tell you whether your specific train today will be late. The Amtrak-adjusted cancellations file also has fewer rows than the unadjusted one, so some months or categories only show up in one version. And the forecasting model's order came from `auto.arima`'s automatic search rather than a manual grid search, since the modest improvement over the naive baseline didn't seem to justify the extra tuning.
