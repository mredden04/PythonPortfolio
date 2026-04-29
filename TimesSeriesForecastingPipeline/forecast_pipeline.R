# ============================================================================
# Forecast Pipeline: Regional Distribution Center Weekly Demand Forecasting
# ============================================================================
# Builds, compares, and deploys three time series forecasting models for
# weekly units shipped at a regional distribution center. Uses the modeltime
# + timetk packages within the tidymodels framework.

# Flow: Phase 2 (EDA) -> Phase 3 (Modeling) -> Phase 4 (Deployment + S3)
# Run top-to-bottom. Do not skip ahead.
# ============================================================================

# --- Libraries ---
library(tidyverse)
library(tidymodels)
library(modeltime)
library(timetk)
library(lubridate)
library(vetiver)
library(pins)
library(httr)
library(jsonlite)

# ============================================================================
# PHASE 2: DATA PREPARATION AND EXPLORATION
# ============================================================================

# --- 2.1 Load and inspect the data ---
center_data <- read_csv('data/distribution_center_weekly.csv')

# Structural inspection: column types, sample values, scale of target variable
center_data |> glimpse()
center_data |> summary()

# Date range and observation count
cat('Date range:', format(min(center_data$date)), 'to', format(max(center_data$date)), '\n')
cat('Total observations:', nrow(center_data), '\n')

# Check for gaps in the weekly sequence -- missing weeks would break time-based splits
# and cause modeltime to misinterpret the seasonal structure
expected_weeks <- seq(min(center_data$date), max(center_data$date), by = 'week')
missing_weeks <- expected_weeks[!expected_weeks %in% center_data$date]
cat('Missing weeks:', length(missing_weeks), '\n')


# --- 2.2 Visualize the series ---

# Main line plot: weekly units over time, peak periods highlighted
# Red points mark weeks where is_peak_period == 1
# EDA finding: the flag fires one week BEFORE the shipment volume peak -- it is a leading indicator, not a contemporaneous marker
# Models learn this lag structure from training data and use the flag correctly as a forward signal in both the test set and future_tbl
plot_series <- center_data |> 
  ggplot(aes(x = date, y = weekly_units)) +
  geom_line(color = '#2C3E50', linewidth = 0.8) +
  geom_point(
    data = filter(center_data, is_peak_period == 1),
    aes(x = date, y = weekly_units),
    color = '#E74C3C', size = 2.5
  ) +
  scale_y_continuous(labels = scales::comma) +
  scale_x_date(date_breaks = '3 months', date_labels = '%b %Y') +
  labs(
    title = 'Regional Distribution Center - Weekly Units Shipped',
    subtitle = 'Red points indicate peak/holiday demand periods',
    x = NULL,
    y = 'Units Shipped'
  ) +
  theme_minimal(base_size = 13) +
  theme(
    plot.title = element_text(face = 'bold'),
    axis.text.x = element_text(angle = 45, hjust = 1),
    panel.grid.major = element_blank()
  )

plot_series
ggsave('plots/plot_series.png', plot_series, width = 10, height = 5, dpi = 150)

# Lab structure check: confirms is_peak_period leads the spike by one week
# Output: avg_units_this_week ~92k, avg_units_next_week ~ 101k (+9%),
# avg_units_2wk_ahead ~75k (already falling)
# One week lead confirmed
center_data |> 
  mutate(
    units_next_week = lead(weekly_units, 1),
    units_2wk_ahead = lead(weekly_units, 2)
  ) |> 
  filter(is_peak_period == 1) |> 
  summarise(
    avg_units_this_week = mean(weekly_units),
    avg_units_next_week = mean(units_next_week, na.rm = TRUE),
    avg_units_2wk_ahead = mean(units_2wk_ahead, na.rm = TRUE)
  )

# Seasonal diagnostics: breaks the series into week-of-year, month, quarter, and year facets
# to surface recurring patterns before choosing model settings
plot_seasonal <- center_data |> 
  plot_seasonal_diagnostics(
    .date_var = date,
    .value = weekly_units,
    .interactive = FALSE,
    .title = 'Seasonal Diagnostics - Weekly Units Shipped'
  )

plot_seasonal
ggsave('plots/plot_seasonal_diagnostics.png', plot_seasonal, width = 12, height = 8, dpi = 150)

# SEASONAL DIAGNOSTICS FINDINGS:
# - Week panel: Multiple elevated windows (wks 1-8 post-holiday tail, wks 11-16
#   spring bump, wks 47-52 Q4 buildup). Quiet baseline in weeks 20-40.
#   Confirms seasonal_period = 52 is the correct setting for ARIMA models.
# - Month panel: Jan/Feb/Apr elevated, Jun-Aug consistently flat and low,
#   Nov/Dec rising with high outliers. Clean seasonal structure.
# - Quarter panel: Q1/Q4 tall boxes with outliers reaching ~200k vs. flat
#   Q2/Q3 medians. Gap between median and outlier confirms MULTIPLICATIVE
#   seasonality -- peaks scale proportionally with baseline 
# - Year panel: Nearly identical distributions across 2022-2024. No meaningful
#   trend -- stable volume year-over-year. Seasonal-naive regressor lookup
#   for future_tbl is valid; past years are a reliable template.

# ACF/PACF diagnostics: measures autocorrelation structure to inform ARIMA order selection
# Plotted to lag 60 to check for the expected lag-52 spike
center_data |> 
  plot_acf_diagnostics(
    .date_var = date,
    .value = weekly_units,
    .lags = 60, # go past lag 52 to see the annual spike
    .title = 'ACF / PACF Diagnostics - Weekly Units'
  )

# ACF / PACF DIAGNOSTICS FINDINGS:
# - ACF lag 1 (~0.55): Strong positive autocorrelation -- a busy week tends
#   to be followed by another busy week. Most important predictor is last week.
# - ACF lags 2-6: Decaying but significant -- correlation fades gradually,
#   suggesting an AR process rather than a sharp cutoff.
# - ACF lag 7-8 (~0.32): Secondary bump -- possible monthly ordering cycle.
# - ACF lag 52: No clean spike breaching the significance band. Annual
#   seasonality IS real (confirmed visually in line plot and seasonal
#   diagnostics) but the series is too short (~130 weeks = ~2.5 cycles)
#   for the ACF to detect it statistically. This is a data length limitation,
#   not evidence against annual seasonality.
# - PACF lag 1 (~0.55): Strong direct effect -- last week directly predicts
#   this week after removing indirect effects.
# - PACF lag 2 (~-0.35): Strong negative direct effect -- mean reversion
#   after accounting for lag 1.
# - PACF lags 3+: Inside significance band -- no further direct effects.
#   Classic AR(1)/AR(2) signature; auto_arima will likely favor a low-order
#   autoregressive specification.
# - IMPLICATION: auto_arima may struggle with seasonal_period = 52 given
#   the short series. Prophet's Fourier seasonality approach is better suited
#   to detecting annual patterns from limited cycles -- point in Prophet's
#   favor going into model comparison.


# ============================================================================
# PHASE 3: MODEL BUILDING WITH MODELTIME
# ============================================================================

# --- 3.1 Time-based train/test split ---

# Time series data cannot be split randomly -- training on future rows and
# testing on past rows would constitute data leakage
# time_series_split() enforces chronological order: all training rows precede all testing rows

# assess = '24 weeks' holds out the last 24 weeks as the test set, 
# which is long enough to include at least one full Q4 holiday cycle
# cumulative = TRUE means training grows forward rather than rolling

splits <- center_data |> 
  time_series_split(
    date_var = date,
    assess = '24 weeks',
    cumulative = TRUE
  )

training_data <- training(splits)
testing_data <- testing(splits)

cat('Training rows:', nrow(training_data), '\n')
cat('Testing rows:', nrow(testing_data), '\n')
cat('Training ends:', format(max(training_data$date)), '\n')
cat('Testing starts:', format(min(testing_data$date)), '\n')

# Visualize the split: confirm the holiday spike falls inside the test window
splits |> 
  tk_time_series_cv_plan() |> 
  plot_time_series_cv_plan(
    .date_var = date,
    .value = weekly_units,
    .interactive = FALSE,
    .title = 'Train / Test Split -- 24-Week Test Window'
  )

# --- 3.2 Model specifications ---

# Shared recipe for all three models
# price_index and local_unemp_rate are excluded: both are slow-moving
# macroeconomic variables unlikely to explain week-to-week variance at a single facility,
# and include week regressors risks adding noise
# No step_*() preprocessing needed -- classical modeltime engines extract
# their own time features internally from the date column
recipe_prophet_xreg <- recipe(
  weekly_units ~ date + is_peak_period + avg_temp_f + transport_cost_idx,
  data = training_data
)

# --- Model 1: Auto-ARIMA -----------------------------------------------------
# auto_arima searches the ARIMA(p,d,q)(P,D,Q)[52] model space and selects
# the best configuration by AIC. seasonal_period = 52 is set explicitly --
# auto-detection is unreliable on short series and can land on nonsensical values
# The regressors enter as a linear layer ("REGRESSION WITH ARIMA ERRORS" in
# output -- this is the correct statistical name, not an error message)
# ARIMA models the autocorrelation structure in the residuals from that regression
# Limitation: uses additive assumption; may underfit Q4 peaks given the confirmed
# multiplicative seasonality. ACF/PACF suggest auto_arima will favor a low-order
# AR spec. Convergence warnings are possible with seasonal_period = 52 on
# ~100 training rows -- acceptable if forecasts are reasonable
wkfl_arima <- workflow() |> 
  add_recipe(recipe_prophet_xreg) |> 
  add_model(
    arima_reg(seasonal_period = 52) |> set_engine('auto_arima')
  ) |> 
  fit(training_data)

# --- Model 2: Boosted ARIMA --------------------------------------------------
# Hybrid model: ARIMA handles the seasonal backbone and trend; XGBoost then
# fits the ARIMA residuals using the external regressors as features
# This allows non-linear regressor effects (e.g. threshold behavior in the peak flag)
# to be captured where a purely linear ARIMA coefficient would miss them
# min_n = 2 and conservative learn_rate = 0.015 prevent XGBoost from
# memorizing the training residuals on a small dataset (~100 rows)
# Same multiplicative seasonality caveat as Model 1 applies.
wkfl_arima_boost <- workflow() |> 
  add_recipe(recipe_prophet_xreg) |> 
  add_model(
    arima_boost(seasonal_period = 52, min_n = 2, learn_rate = 0.015) |> set_engine('auto_arima_xgboost') 
  ) |> 
  fit(training_data)

# --- Model 3: Prophet --------------------------------------------------------
# Prophet decomposes the series into trend + Fourier seasonality + regressors
# seasonality_yearly = TRUE fits an annual Fourier component -- appropriate for
# a weekly series with pronounced Q4 holiday spikes
# Prophet's Fourier approach is also better suited than ARIMA for detecting
# annual patterns from only ~2.5 seasonal cycles (per ACF/PACF findings)
wkfl_prophet <- workflow() |> 
  add_recipe(recipe_prophet_xreg) |> 
  add_model(
    prophet_reg(
      seasonality_yearly = TRUE
    ) |> set_engine('prophet')
  ) |> 
  fit(training_data)


# --- 3.3 Modeltime table, calibration, accuracy ---

# Bundle all three fitted workflows into a modeltime table -- 
#modeltime's container for organizing multiple models through calibration and forecasting
models_tbl <- modeltime_table(
  wkfl_arima,
  wkfl_arima_boost,
  wkfl_prophet
)

models_tbl

# Calibration: runs each model on the test set and computes residuals and prediction intervals
# Required before modeltime_accuracy() or modeltime_forecast() will product correct results
calibration_tbl <- models_tbl |> 
  modeltime_calibrate(new_data = testing_data)

# Accuracy table: MAE, MAPE, RMSE, and R-squared for each model
# Sorted by RMSE ascending -- RMSE is the primary selection criterion because
# it penalizes large errors (e.g. holiday spike misses) more heavily than MAE
accuracy_tbl <- calibration_tbl |> 
  modeltime_accuracy() |> 
  arrange(rmse)

accuracy_tbl

# Visual comparison: each model's test-period predictions overlaid on actuals
# actual_data = center_data plots the full historical series as context so the 
# holiday spike is visible, not just the isolated 24-week test window
plot_forecast_comparison <- calibration_tbl |> 
  modeltime_forecast(
    new_data = testing_data,
    actual_data = center_data
  ) |> 
  plot_modeltime_forecast(
    .interactive = FALSE,
    .title = 'Model Comparison - Test Set Forecast vs. Actuals',
    .y_lab = 'Units Shipped',
    .x_lab = 'Week',
    .legend_show = TRUE
  )

plot_forecast_comparison
ggsave('plots/forecast_comparison.png', plot_forecast_comparision, width = 12, height = 6, dpi = 150)

# --- 3.4 Pick the best model, refit, forward forecast ---

# Select winner programmatically by lowest RMSE -- hardcoding a model ID
# would break if the accuracy ranking changes after a refit or data update
best_model_id <- accuracy_tbl |> 
  slice_min(rmse, n = 1) |> 
  pull(.model_id)

cat('Best model ID:', best_model_id, '\n')

# Refit winner on the full dataset (training + test combines) before forward forecast
# This gives the deployed model the maximum amount of information before it 
# has to predict genuinely unseen future weeks
refit_tbl <- calibration_tbl |> 
  filter(.model_id == best_model_id) |> 
  modeltime_refit(data = center_data)

# Build the future data frame: 24 weeks beyond the last observed date
future_tbl <- center_data |> 
  future_frame(.date_var = date, .length_out = '24 weeks')

# Populate external regressors for future week
# is_peak_period and avg_temp_f use seasonal-naive imputation: average the same
# ISO week number across all historical years
# is_peak_period uses majority vote (round of mean) so weeks that are flagged in most years stay flagged -- this
# preserves the one-week leading indicator structure confirmed during EDA
# transport_cost_idx uses last-observation-carried-forward: it drifts slowly
# and there is no better signal available over a 24-week horizon

# Last known cost index value for LOCF
last_cost_idx <- center_data |> 
  slice_tail(n = 1) |> 
  pull(transport_cost_idx)

# Historical seasonal averages by ISO week number
seasonal_lookup <- center_data |> 
  mutate(iso_week = isoweek(date)) |> 
  group_by(iso_week) |> 
  summarise(
    is_peak_period = round(mean(is_peak_period)),
    avg_temp_f = mean(avg_temp_f)
  )

# Join seasonal values onto the future frame and add the carried-forward index
future_tbl <- future_tbl |> 
  mutate(iso_week = isoweek(date)) |> 
  left_join(seasonal_lookup, by = 'iso_week') |> 
  mutate(transport_cost_idx = last_cost_idx) |> 
  select(-iso_week)

# Forward forecast: best model predicts 24 weeks into the future
# actual_data = center_data anchors the plot with the full historical series
# so the forecast is readable in context
plot_forward_forecast <- refit_tbl |> 
  modeltime_forecast(
    new_data = future_tbl,
    actual_data = center_data
  ) |> 
  plot_modeltime_forecast(
    .interactive = FALSE,
    .title = '24-Week Forward Forecast - Best Model',
    .y_lab = 'Units Shipped',
    .x_lab = 'Week',
    .legend_show = TRUE
  )

plot_forward_forecast
ggsave('plots/forward_forecast.png', plot_forward_forecast, width = 12, height = 6, dpi = 150)

# ============================================================================
# PHASE 4.1: LOCAL DOCKER DEPLOYMENT
# ============================================================================

# The student_net_id variables drives:
#     - the vetiver_model's model name
#     - the pin name on both the local board and the class s3 board
#     - the folder name inside the class s3 bucket
student_net_id <- ""

# --- Extract the best fitted workflow/model ---
# best_fit is a parsnip workflow, not a bare model_fit -- because Phase 3.2
# wraps every candidate in workflow() + add_recipe() + add_model() before fitting
# That's the shape vetiver_model() needs: its workflow method builds
# a description from the workflow spec rather than drilling into modeltime's
# engine bridge classes (which have no vetiver S3 methods and would error)

best_fit <- refit_tbl %>%
  pluck(".model", 1)

# Create a vetiver model object
# model_name is also the pin name on every board this model gets written to
deployable_model <- vetiver_model(
  best_fit,
  model_name = student_net_id
)

deployable_model

# Pin to a local board (the pin name is taken from deployable_model$model_name)
model_board <- board_folder("models")
model_board %>% vetiver_pin_write(deployable_model)

# Generate Docker deployment files -- second arg must match the local pin name
vetiver_prepare_docker(
  model_board,
  student_net_id
)

# Docker files should now be generated. To deploy for local testing:
#   1. docker build -t forecast-api .
#   2. docker run -p 8000:8000 forecast-api
#   3. Visit http://127.0.0.1:8000/__docs__/

# --- Now Test the API (run AFTER Docker container is running) ---

# Batch prediction test
v_api <- vetiver_endpoint("http://127.0.0.1:8000/predict")
test_preds <- predict(v_api, testing_data)
test_preds

# Single observation test via httr
one_week <- testing_data %>% slice(1)
one_week_json <- toJSON(one_week)

response <- POST(
  url = "http://127.0.0.1:8000/predict",
  body = one_week_json,
  content_type_json()
)

single_pred <- fromJSON(content(response, as = "text", encoding = "UTF-8")) %>%
  as_tibble()
single_pred

# ============================================================================
# PHASE 4.2: UPLOAD MODEL TO S3 FOR GRADING
# ============================================================================

# Explicitly load .Renviron file
readRenviron(".Renviron")

# Check to make sure values are in each of these environment variables
Sys.getenv("AWS_ACCESS_KEY_ID")     # should start with "AKIA..."
Sys.getenv("AWS_SECRET_ACCESS_KEY") # should be ~40 chars
Sys.getenv("AWS_DEFAULT_REGION")    # should be "us-west-2"

# Connect to the class S3 bucket
s3_board <- board_s3(
  bucket = "is555-model-submissions-w26",
  prefix = "submissions/"
)

# Upload to the class S3 board
vetiver_pin_write(s3_board, deployable_model)

# Verify the upload by reading it back
my_model_check <- vetiver_pin_read(s3_board, student_net_id)

my_model_check

# Quick sanity check: does it predict correctly?
test_prediction <- predict(my_model_check, testing_data)

test_prediction
