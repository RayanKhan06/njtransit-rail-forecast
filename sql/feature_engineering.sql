-- ============================================================================
-- feature_engineering.sql
--
-- Builds a single, analysis-ready monthly table from the raw NJ Transit
-- tables loaded by app/load_data.py. Run against njtransit.db, e.g.:
--
--   sqlite3 njtransit.db < sql/feature_engineering.sql
--
-- Produces: monthly_performance
--   One row per calendar month with on-time %, cancellation cause shares
--   (pivoted from long to wide), fleet reliability (MDBF), and lag/rolling
--   features for the forecasting model.
-- ============================================================================

DROP TABLE IF EXISTS monthly_performance;

CREATE TABLE monthly_performance AS
WITH cancel_totals AS (
    -- Total cancellations per month, regardless of cause
    SELECT period, SUM(cancel_count) AS total_cancellations
    FROM cancellations_monthly
    GROUP BY period
),
cancel_pivot AS (
    -- Pivot cause categories into columns as a % share of that month's
    -- total cancellations, so the shares are comparable across months
    -- even as total cancellation volume changes.
    SELECT
        c.period,
        ROUND(100.0 * SUM(CASE WHEN c.category = 'AMTRAK' THEN c.cancel_count ELSE 0 END) / NULLIF(t.total_cancellations, 0), 2) AS pct_cause_amtrak,
        ROUND(100.0 * SUM(CASE WHEN c.category = 'Crew/Engineer Availability' THEN c.cancel_count ELSE 0 END) / NULLIF(t.total_cancellations, 0), 2) AS pct_cause_crew,
        ROUND(100.0 * SUM(CASE WHEN c.category = 'Equipment Availability' THEN c.cancel_count ELSE 0 END) / NULLIF(t.total_cancellations, 0), 2) AS pct_cause_equipment,
        ROUND(100.0 * SUM(CASE WHEN c.category = 'Infrastructure Engineering' THEN c.cancel_count ELSE 0 END) / NULLIF(t.total_cancellations, 0), 2) AS pct_cause_infrastructure,
        ROUND(100.0 * SUM(CASE WHEN c.category = 'Mechanical' THEN c.cancel_count ELSE 0 END) / NULLIF(t.total_cancellations, 0), 2) AS pct_cause_mechanical,
        ROUND(100.0 * SUM(CASE WHEN c.category = 'Human Factor' THEN c.cancel_count ELSE 0 END) / NULLIF(t.total_cancellations, 0), 2) AS pct_cause_human_factor,
        ROUND(100.0 * SUM(CASE WHEN c.category = 'Other Railroads' THEN c.cancel_count ELSE 0 END) / NULLIF(t.total_cancellations, 0), 2) AS pct_cause_other_railroads,
        ROUND(100.0 * SUM(CASE WHEN c.category = 'Unpreventable' THEN c.cancel_count ELSE 0 END) / NULLIF(t.total_cancellations, 0), 2) AS pct_cause_unpreventable,
        ROUND(100.0 * SUM(CASE WHEN c.category IN ('Carryover/Other', 'Other', 'Technologies') THEN c.cancel_count ELSE 0 END) / NULLIF(t.total_cancellations, 0), 2) AS pct_cause_other_misc
    FROM cancellations_monthly c
    JOIN cancel_totals t ON t.period = c.period
    GROUP BY c.period
),
joined AS (
    SELECT
        o.period,
        o.year,
        o.month_num,
        o.on_time_pct,
        oa.on_time_pct           AS on_time_pct_amtrak_adj,
        m.mdbf,
        ct.total_cancellations,
        cp.pct_cause_amtrak,
        cp.pct_cause_crew,
        cp.pct_cause_equipment,
        cp.pct_cause_infrastructure,
        cp.pct_cause_mechanical,
        cp.pct_cause_human_factor,
        cp.pct_cause_other_railroads,
        cp.pct_cause_unpreventable,
        cp.pct_cause_other_misc
    FROM otp_monthly o
    LEFT JOIN otp_monthly_amtrak_adj oa ON oa.period = o.period
    LEFT JOIN mdbf_monthly m            ON m.period = o.period
    LEFT JOIN cancel_totals ct          ON ct.period = o.period
    LEFT JOIN cancel_pivot cp           ON cp.period = o.period
)
SELECT
    *,
    -- Prior-month on-time % (useful lag feature / naive baseline)
    LAG(on_time_pct, 1)  OVER (ORDER BY period) AS on_time_pct_lag1,
    -- Same month prior year (captures yearly seasonality, e.g. winter storms)
    LAG(on_time_pct, 12) OVER (ORDER BY period) AS on_time_pct_lag12,
    -- 3-month trailing average, smooths month-to-month noise
    ROUND(AVG(on_time_pct) OVER (
        ORDER BY period ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2) AS on_time_pct_rolling3,
    -- Month-over-month change in fleet reliability
    mdbf - LAG(mdbf, 1) OVER (ORDER BY period) AS mdbf_change_mom
FROM joined
ORDER BY period;

-- Quick sanity check query (not part of the table build, just for eyeballing
-- after running this script):
-- SELECT period, on_time_pct, on_time_pct_rolling3, pct_cause_equipment, pct_cause_crew
-- FROM monthly_performance ORDER BY period DESC LIMIT 12;
