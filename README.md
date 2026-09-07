# NJ Transit Rail Performance: Forecasting & Diagnostics

Forecasts NJ Transit's system-wide monthly on-time percentage and surfaces
trends in what's driving train cancellations (crew availability, equipment,
Amtrak-caused delays, etc.), using NJ Transit's own official monthly
performance data.

**Data source:** [njtransit.com/performance-data-download](https://www.njtransit.com/performance-data-download) —
official, publicly published, updated monthly. Covers January 2017 through
July 2026 (115 months) at time of writing. This is aggregate monthly data
(not per-trip), so the project is built around monthly forecasting and
trend diagnostics rather than per-train delay prediction.

## What's in here

| Layer | Tool | What it does |
|---|---|---|
| Ingestion | Python / pandas | Cleans raw CSVs, loads into SQLite (`app/load_data.py`) |
| Feature engineering | SQL | Pivots cancellation causes, joins tables, computes lag/rolling features (`sql/feature_engineering.sql`) |
| Modeling | Python / statsmodels | SARIMAX(1,1,1)(1,1,1,12) forecast of monthly on-time % (`app/train.py`) |
| Diagnostics | R / ggplot2 | Cancellation-cause composition, Amtrak-adjusted comparison, MDBF regression (`r/eda_and_baseline.Rmd`) |
| Serving | FastAPI | `/forecast` and `/cancellation-trends` endpoints (`app/main.py`) |
| Packaging | Docker + docker-compose | Containerized API, optional Postgres service |
| CI | GitHub Actions | Build data pipeline, train model, test, build image on every push |

## Running it

```bash
pip install -r requirements.txt

# Build the database and feature table
python app/load_data.py
python -c "import sqlite3; conn = sqlite3.connect('njtransit.db'); conn.executescript(open('sql/feature_engineering.sql').read()); conn.commit()"

# Train the model
python app/train.py

# Run tests
pytest -v

# Serve the API
uvicorn app.main:app --reload
```

Then:
```bash
curl "http://localhost:8000/forecast?months=6"
curl "http://localhost:8000/cancellation-trends?category=pct_cause_crew&months=12"
```

### Docker

```bash
docker build -t njtransit-api .
docker run -p 8000:8000 njtransit-api
```

The `docker-compose.yml` additionally spins up a Postgres container
alongside the API — the pipeline itself uses SQLite, so this is included
to demonstrate multi-container orchestration and as a starting point if
you migrate the SQL layer to a client-server database.

### R analysis

Open `r/eda_and_baseline.Rmd` in RStudio and knit it. Requires `tidyverse`,
`lubridate`, and `scales`. (Written and reviewed against the confirmed CSV
schema, but not executed in this environment — no R runtime was available
where this was built, so knit it once locally before treating the output
as final.)

## Model honesty

The SARIMAX model was backtested on the last 6 held-out months: **MAE 1.71
percentage points vs. a naive baseline of 1.77** — a real but modest
improvement. System-wide monthly on-time % is close to a random walk with
mild yearly seasonality, so a large forecasting gain over "predict last
month's value" was never realistic here. The honest pitch for this project
is the full pipeline (SQL feature engineering → backtested forecasting →
served API → CI/CD) and the diagnostic analysis of cancellation causes,
not a claim of high forecast accuracy.

## Known limitations

- Aggregate monthly data only — no per-trip or per-line granularity in the
  official download, so this can't predict whether *your* train today will
  be late.
- Amtrak-adjusted cancellations file has fewer rows than the unadjusted
  file (850 vs. 961) — some months/categories only exist in one version.
  Worth investigating before citing exact adjusted-vs-unadjusted deltas.
- SARIMAX order (1,1,1)(1,1,1,12) was chosen as a reasonable starting
  specification, not selected via grid search / AIC comparison — a next
  step worth doing before treating this as a finished model.
