# ============================================================================
# NJ Transit Rail Performance Analysis
#
# Loads NJ Transit's official monthly performance CSVs, builds a time series
# forecast of on-time %, tests whether fleet reliability (MDBF) predicts
# on-time performance, analyzes cancellation cause trends, and quantifies
# the gap between official and Amtrak-adjusted on-time percentage.
#
# Outputs (written to ../exports/) feed the Power BI dashboard.
# ============================================================================

library(tidyverse)
library(forecast)

setwd("C:/Users/RayKh/Downloads/njtransit-forecast/njtransit-forecast/r")

# ----------------------------------------------------------------------------
# 1. Load and clean on-time performance (OTP) data
# ----------------------------------------------------------------------------
# Raw file has a header row, a dashed separator row, then data starting row 3.

otp <- read_csv(
  "../data/RAIL_OTP_DATA.csv",
  skip = 2,
  col_names = c("year", "month", "status", "on_time_count", "total_trips", "on_time_pct")
)

otp <- otp %>%
  mutate(
    month_num = match(toupper(month), toupper(month.name)),
    period = make_date(year, month_num, 1)
  ) %>%
  arrange(period)  # raw file is not chronologically sorted

# Quick look at the worst months
otp %>% arrange(on_time_pct) %>% select(period, on_time_pct) %>% head(5)

dir.create("../figures", showWarnings = FALSE)

p_otp_history <- ggplot(otp, aes(x = period, y = on_time_pct)) +
  geom_line(color = "#2980b9") +
  labs(title = "NJ Transit Monthly On-Time %", x = NULL, y = "On-time %")
ggsave("../figures/01_otp_history.png", p_otp_history, width = 8, height = 5)

# ----------------------------------------------------------------------------
# 2. Time series forecast (auto.arima)
# ----------------------------------------------------------------------------

otp_ts <- ts(otp$on_time_pct, start = c(2017, 1), frequency = 12)

# Backtest: hold out the last 6 months, fit on the rest, compare forecast
# to what actually happened. This is the honest accuracy check.
n <- length(otp_ts)
train_ts <- window(otp_ts, end = time(otp_ts)[n - 6])
test_ts  <- window(otp_ts, start = time(otp_ts)[n - 5])

fit_train <- auto.arima(train_ts)
fc <- forecast(fit_train, h = 6)
accuracy(fc, test_ts)

# Naive baseline for comparison ("predict no change from last known value")
naive_fc <- rep(as.numeric(train_ts[length(train_ts)]), 6)
naive_mae <- mean(abs(naive_fc - as.numeric(test_ts)))
naive_mae
# Finding: auto.arima's MAE (~1.72) is close to the naive baseline (~1.77) -
# on-time % behaves close to a random walk with mild autocorrelation.

# Refit on full history for the actual production forecast
final_fit <- auto.arima(otp_ts)
final_fc <- forecast(final_fit, h = 6)
final_fc

forecast_df <- data.frame(
  period = seq(as.Date("2026-08-01"), by = "month", length.out = 6),
  forecast_on_time_pct = as.numeric(final_fc$mean),
  lower_80 = as.numeric(final_fc$lower[, 1]),
  upper_80 = as.numeric(final_fc$upper[, 1]),
  lower_95 = as.numeric(final_fc$lower[, 2]),
  upper_95 = as.numeric(final_fc$upper[, 2])
)

dir.create("../exports", showWarnings = FALSE)
write_csv(forecast_df, "../exports/forecast_output.csv")
write_csv(otp, "../exports/otp_history.csv")

# ----------------------------------------------------------------------------
# 3. Fleet reliability (MDBF) vs. on-time % regression
# ----------------------------------------------------------------------------
# MDBF = Mean Distance Between Failure, a fleet maintenance/reliability metric.

mdbf <- read_csv(
  "../data/RAIL_MDBF_DATA.csv",
  skip = 2,
  col_names = c("month_raw", "mdbf")
)

mdbf <- mdbf %>%
  separate(month_raw, into = c("year", "month"), sep = " ", extra = "merge") %>%
  mutate(
    year = as.integer(year),
    month_num = match(toupper(month), toupper(month.name)),
    period = make_date(year, month_num, 1)
  ) %>%
  arrange(period)

model_df <- otp %>%
  select(period, on_time_pct) %>%
  inner_join(mdbf %>% select(period, mdbf), by = "period") %>%
  arrange(period)

fit_mdbf <- lm(on_time_pct ~ mdbf, data = model_df)
summary(fit_mdbf)
# Finding: statistically significant (p = 1.34e-8), but R-squared is only
# ~0.25 - MDBF explains about a quarter of month-to-month variation.
# Real relationship, modest predictor.

p_mdbf <- ggplot(model_df, aes(x = mdbf, y = on_time_pct)) +
  geom_point(alpha = 0.6, color = "#2980b9") +
  geom_smooth(method = "lm", color = "#c0392b", se = TRUE) +
  labs(title = "On-Time % vs. Mean Distance Between Failure",
       x = "MDBF (miles)", y = "On-time %")
ggsave("../figures/02_mdbf_vs_ontime.png", p_mdbf, width = 8, height = 5)

mdbf_summary <- data.frame(
  r_squared = round(summary(fit_mdbf)$r.squared, 4),
  coefficient = round(coef(fit_mdbf)["mdbf"], 6),
  p_value = format(summary(fit_mdbf)$coefficients["mdbf", "Pr(>|t|)"], scientific = TRUE)
)
write_csv(mdbf_summary, "../exports/mdbf_regression_summary.csv")

# ----------------------------------------------------------------------------
# 4. Cancellation cause trends
# ----------------------------------------------------------------------------

cancellations <- read_csv(
  "../data/RAIL_CANCELLATIONS_DATA.csv",
  skip = 2,
  col_names = c("year", "month", "category", "cancel_count", "cancel_total", "cancel_pct")
)

cancellations <- cancellations %>%
  mutate(
    month_num = match(toupper(month), toupper(month.name)),
    period = make_date(year, month_num, 1)
  ) %>%
  arrange(period)

# Rank categories by total volume to pick the top causes worth charting
cancellations %>%
  group_by(category) %>%
  summarise(total = sum(cancel_count)) %>%
  arrange(desc(total))

top_causes <- cancellations %>%
  group_by(category) %>%
  summarise(total = sum(cancel_count)) %>%
  arrange(desc(total)) %>%
  slice_head(n = 6) %>%
  pull(category)

# Small multiples: one panel per cause, each on its own scale.
# (A single stacked area chart was tried first but stayed too noisy to read
# even with 3- and 6-month rolling averages - the small multiples view below
# is the one actually used in the dashboard.)
p_cancel_trends <- cancellations %>%
  filter(category %in% top_causes) %>%
  group_by(period, category) %>%
  summarise(cancel_pct = sum(cancel_count) / cancel_total[1] * 100, .groups = "drop") %>%
  distinct() %>%
  ggplot(aes(x = period, y = cancel_pct)) +
  geom_line(color = "#2980b9") +
  facet_wrap(~ category, scales = "free_y") +
  labs(title = "Cancellation Cause Trends Over Time",
       subtitle = "Each panel shows that cause's share of monthly cancellations",
       x = NULL, y = "Share of cancellations (%)") +
  theme_minimal()
ggsave("../figures/03_cancellation_causes.png", p_cancel_trends, width = 10, height = 6)
# Finding: cause composition is genuinely volatile month-to-month for most
# categories (event-driven, not a smooth trend). Mechanical is a partial
# exception, showing a step-up to a higher baseline from ~2021 onward.

cancellations %>%
  filter(category %in% top_causes) %>%
  select(period, category, cancel_pct) %>%
  distinct() %>%
  write_csv("../exports/cancellation_causes.csv")

# ----------------------------------------------------------------------------
# 5. Amtrak-adjusted comparison
# ----------------------------------------------------------------------------
# NJ Transit shares track with Amtrak on parts of its network. This section
# quantifies how much of NJ Transit's reported delay is attributed to
# Amtrak-controlled infrastructure rather than NJ Transit's own operations.

otp_adj <- read_csv(
  "../data/RAIL_OTP_DATA_AMTRAK_ADJUSTED.csv",
  skip = 2,
  col_names = c("year", "month", "status", "on_time_count", "total_trips", "on_time_pct_adj")
)

otp_adj <- otp_adj %>%
  mutate(
    month_num = match(toupper(month), toupper(month.name)),
    period = make_date(year, month_num, 1)
  ) %>%
  arrange(period)

gap_summary <- otp %>%
  select(period, on_time_pct) %>%
  left_join(otp_adj %>% select(period, on_time_pct_adj), by = "period") %>%
  mutate(gap = on_time_pct_adj - on_time_pct) %>%
  summarise(
    mean_gap_pts = round(mean(gap, na.rm = TRUE), 2),
    max_gap_pts = round(max(gap, na.rm = TRUE), 2)
  )
gap_summary
# Finding: NJ Transit's on-time % is 2.64 points higher on average once
# Amtrak-attributed delays are excluded (max single-month gap: 9.2 points).

write_csv(gap_summary, "../exports/amtrak_gap_summary.csv")

# ----------------------------------------------------------------------------
# Confirm all exports landed
# ----------------------------------------------------------------------------
list.files("../exports")
