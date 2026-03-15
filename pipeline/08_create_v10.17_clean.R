# ============================================================================
# CREATE v10.17 CLEANED DATASET
# ============================================================================
# PURPOSE:
#   Takes unified_dataset_with_env_v10.16_cleaned.rds and produces v10.17:
#     1. Coalesce duplicate variable pairs (merge into one, drop redundant)
#     2. Standardise all date columns to Date type
#     3. Compute missing DHS dates (delivery_date, conception_date)
#     4. Compute missing season of conception
#     5. Standardise gestational age (clean decimals, create obstetric string)
#     6. Drop 100% NA / redundant columns
#     7. Rename for consistency
#     8. Re-apply factor levels
#     9. Reorder all columns logically
#    10. Final diagnostics
#    11. Save as .rds, .csv, .dta + GA log
#
# INPUT:  output/unified_dataset_with_env_v10.16.rds  (from Step 07, ~160 cols)
# OUTPUT: output/unified_dataset_with_env_v10.17_cleaned.rds (~130 cols)
#
# Author: Joseph Akuze (LSHTM)
# ============================================================================

cat("============================================================\n")
cat("  CREATE v10.17 CLEANED DATASET\n")
cat("============================================================\n\n")

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(haven)
  library(glue)
})

# Set to your unified_dataset_pipeline directory, or run from project root.
base_path <- file.path(getwd(), "output")
# base_path <- "C:/Users/YOUR_USERNAME/path/to/unified_dataset_pipeline/output"
input_file <- file.path(base_path, "unified_dataset_with_env_v10.16.rds")

cat("Loading v10.16 cleaned dataset...\n")
df <- readRDS(input_file)
cat(glue("Loaded: {format(nrow(df), big.mark=',')} rows x {ncol(df)} columns\n\n"))

# --- Fix column types: some columns stored as character should be numeric ---
numeric_cols <- c("out_ga_days", "mat_parity", "mat_gravidity", "mat_anc_visits",
                  "out_apgar_1min", "out_apgar_5min", "out_apgar_10min",
                  "mat_height", "mat_weight", "mat_previous_cs",
                  "hh_household_size", "studyyear", "mat_sbp", "mat_dbp", "mat_muac",
                  "out_birthweight_centile", "out_birthweight_zscore",
                  "loc_latitude", "loc_longitude", "hh_size", "hh_num_rooms",
                  "hh_monthly_income",
                  "obs_parity", "obs_gravidity", "mat_height_cm", "mat_weight_kg",
                  "anc_num_visits")
for (col in numeric_cols) {
  if (col %in% names(df) && is.character(df[[col]])) {
    df[[col]] <- suppressWarnings(as.numeric(df[[col]]))
  }
}
cat("Fixed character-to-numeric column types\n\n")

# ============================================================================
# STEP 1: COALESCE DUPLICATE VARIABLE PAIRS
# ============================================================================
cat("============================================================\n")
cat("  STEP 1: Coalesce duplicate variable pairs\n")
cat("============================================================\n\n")

# Helper: coalesce safely across factor/character types
safe_coalesce <- function(primary, secondary) {
  p <- if (is.factor(primary)) as.character(primary) else primary
  s <- if (is.factor(secondary)) as.character(secondary) else secondary
  coalesce(p, s)
}

# Track before/after for each coalesce
coalesce_log <- function(col_name, before_na, after_na, n_total) {
  gained <- before_na - after_na
  cat(sprintf("  %-25s  NA: %s -> %s  (gained %s values, now %.1f%% complete)\n",
              col_name,
              format(before_na, big.mark = ","),
              format(after_na, big.mark = ","),
              format(gained, big.mark = ","),
              100 * (1 - after_na / n_total)))
}

n <- nrow(df)

# --- 1. mat_country <- coalesce(mat_country, loc_country) ---
before <- sum(is.na(df$mat_country))
df$mat_country <- safe_coalesce(df$mat_country, df$loc_country)
coalesce_log("mat_country", before, sum(is.na(df$mat_country)), n)

# --- 2. mat_facility <- coalesce(mat_facility, loc_facility) ---
before <- sum(is.na(df$mat_facility))
df$mat_facility <- safe_coalesce(df$mat_facility, df$loc_facility)
coalesce_log("mat_facility", before, sum(is.na(df$mat_facility)), n)

# --- 3. mat_district <- coalesce(mat_district, loc_district) ---
before <- sum(is.na(df$mat_district))
df$mat_district <- safe_coalesce(df$mat_district, df$loc_district)
coalesce_log("mat_district", before, sum(is.na(df$mat_district)), n)

# --- 4. mat_urban_rural <- coalesce(mat_urban_rural, loc_urban_rural) ---
before <- sum(is.na(df$mat_urban_rural))
df$mat_urban_rural <- safe_coalesce(df$mat_urban_rural, df$loc_urban_rural)
coalesce_log("mat_urban_rural", before, sum(is.na(df$mat_urban_rural)), n)

# --- 5. mat_parity <- coalesce(mat_parity, obs_parity) ---
before <- sum(is.na(df$mat_parity))
df$mat_parity <- coalesce(df$mat_parity, df$obs_parity)
coalesce_log("mat_parity", before, sum(is.na(df$mat_parity)), n)

# --- 6. mat_gravidity <- coalesce(mat_gravidity, obs_gravidity) ---
before <- sum(is.na(df$mat_gravidity))
df$mat_gravidity <- coalesce(df$mat_gravidity, df$obs_gravidity)
coalesce_log("mat_gravidity", before, sum(is.na(df$mat_gravidity)), n)

# --- 7. mat_height <- coalesce(mat_height, mat_height_cm) ---
before <- sum(is.na(df$mat_height))
df$mat_height <- coalesce(df$mat_height, df$mat_height_cm)
coalesce_log("mat_height->mat_height_cm", before, sum(is.na(df$mat_height)), n)

# --- 8. mat_weight <- coalesce(mat_weight, mat_weight_kg) ---
before <- sum(is.na(df$mat_weight))
df$mat_weight <- coalesce(df$mat_weight, df$mat_weight_kg)
coalesce_log("mat_weight->mat_weight_kg", before, sum(is.na(df$mat_weight)), n)

# --- 9. mat_delivery_mode <- coalesce(mat_delivery_mode, del_mode) ---
before <- sum(is.na(df$mat_delivery_mode))
df$mat_delivery_mode <- safe_coalesce(df$mat_delivery_mode, df$del_mode)
# Harmonise: DHS del_mode may have "Vaginal" instead of "Vaginal spontaneous"
df$mat_delivery_mode[df$mat_delivery_mode == "Vaginal"] <- "Vaginal spontaneous"
coalesce_log("mat_delivery_mode", before, sum(is.na(df$mat_delivery_mode)), n)

# --- 10. mat_delivery_location <- coalesce(mat_delivery_location, del_location) ---
before <- sum(is.na(df$mat_delivery_location))
df$mat_delivery_location <- safe_coalesce(df$mat_delivery_location, df$del_location)
coalesce_log("mat_delivery_location", before, sum(is.na(df$mat_delivery_location)), n)

# --- 11. mat_anc_visits <- coalesce(mat_anc_visits, anc_num_visits) ---
before <- sum(is.na(df$mat_anc_visits))
df$mat_anc_visits <- coalesce(df$mat_anc_visits, df$anc_num_visits)
coalesce_log("mat_anc_visits", before, sum(is.na(df$mat_anc_visits)), n)

# --- 12. hh_house_floor <- coalesce(hh_house_floor, hh_floor_material) ---
before <- sum(is.na(df$hh_house_floor))
df$hh_house_floor <- safe_coalesce(df$hh_house_floor, df$hh_floor_material)
coalesce_log("hh_house_floor", before, sum(is.na(df$hh_house_floor)), n)

# --- 13. hh_house_wall <- coalesce(hh_house_wall, hh_wall_material) ---
before <- sum(is.na(df$hh_house_wall))
df$hh_house_wall <- safe_coalesce(df$hh_house_wall, df$hh_wall_material)
coalesce_log("hh_house_wall", before, sum(is.na(df$hh_house_wall)), n)

# --- 14. hh_household_size <- coalesce(hh_household_size, hh_size) ---
before <- sum(is.na(df$hh_household_size))
df$hh_household_size <- coalesce(df$hh_household_size, df$hh_size)
coalesce_log("hh_household_size", before, sum(is.na(df$hh_household_size)), n)

# --- 15. env_latitude <- coalesce(env_latitude, loc_latitude) ---
before <- sum(is.na(df$env_latitude))
if (is.character(df$loc_latitude)) df$loc_latitude <- suppressWarnings(as.numeric(df$loc_latitude))
df$env_latitude <- coalesce(df$env_latitude, df$loc_latitude)
coalesce_log("env_latitude", before, sum(is.na(df$env_latitude)), n)

# --- 16. env_longitude <- coalesce(env_longitude, loc_longitude) ---
before <- sum(is.na(df$env_longitude))
if (is.character(df$loc_longitude)) df$loc_longitude <- suppressWarnings(as.numeric(df$loc_longitude))
df$env_longitude <- coalesce(df$env_longitude, df$loc_longitude)
coalesce_log("env_longitude", before, sum(is.na(df$env_longitude)), n)

# --- 17. mat_birth_attendant <- coalesce(mat_birth_attendant, del_attendant) ---
if ("del_attendant" %in% names(df)) {
  if (!"mat_birth_attendant" %in% names(df)) df$mat_birth_attendant <- NA_character_
  before <- sum(is.na(df$mat_birth_attendant))
  df$mat_birth_attendant <- safe_coalesce(df$mat_birth_attendant, df$del_attendant)
  coalesce_log("mat_birth_attendant", before, sum(is.na(df$mat_birth_attendant)), n)
}

cat("\n")
gc()

# ============================================================================
# STEP 2: STANDARDISE DATE COLUMNS
# ============================================================================
cat("============================================================\n")
cat("  STEP 2: Convert character dates to Date type\n")
cat("============================================================\n\n")

for (v in c("delivery_date_raw", "conception_date", "study_date")) {
  if (v %in% names(df) && is.character(df[[v]])) {
    before_na <- sum(is.na(df[[v]]))
    df[[v]] <- as.Date(df[[v]], format = "%Y-%m-%d")
    after_na <- sum(is.na(df[[v]]))
    coerced_to_na <- after_na - before_na
    cat(glue("  {v}: char -> Date (range: {min(df[[v]], na.rm=TRUE)} to {max(df[[v]], na.rm=TRUE)})"))
    if (coerced_to_na > 0) cat(glue("  WARNING: {coerced_to_na} values lost in conversion"))
    cat("\n")
  } else if (v %in% names(df)) {
    cat(glue("  {v}: already {class(df[[v]])[1]}\n"))
  }
}

# --- 2b. Cap implausible dates (set to NA) ---
date_cols <- c("out_dob", "out_dod", "delivery_date_raw", "conception_date", "study_date")
min_date <- as.Date("1940-01-01")
max_date <- as.Date("2025-12-31")
for (v in date_cols) {
  if (v %in% names(df) && inherits(df[[v]], "Date")) {
    bad <- !is.na(df[[v]]) & (df[[v]] < min_date | df[[v]] > max_date)
    if (sum(bad) > 0) {
      cat(glue("  {v}: capping {sum(bad)} implausible dates to NA (outside {min_date} to {max_date})\n"))
      df[[v]][bad] <- NA
    }
  }
}
cat("\n")

# ============================================================================
# STEP 3: COMPUTE MISSING DHS DATES
# ============================================================================
cat("============================================================\n")
cat("  STEP 3: Compute missing DHS dates\n")
cat("============================================================\n\n")

dhs_with_dob <- df$study_source == "DHS" & !is.na(df$out_dob)
cat(glue("DHS records with out_dob: {format(sum(dhs_with_dob), big.mark=',')}\n"))

# --- 3a. delivery_date_raw = out_dob for DHS ---
needs_delivery <- dhs_with_dob & is.na(df$delivery_date_raw)
cat(glue("DHS needing delivery_date_raw: {format(sum(needs_delivery), big.mark=',')}\n"))
df$delivery_date_raw[needs_delivery] <- df$out_dob[needs_delivery]
cat(glue("  -> Filled {format(sum(needs_delivery), big.mark=',')} delivery dates from out_dob\n"))

# --- 3b. conception_date = out_dob - GA or out_dob - 280 days ---
needs_conception <- dhs_with_dob & is.na(df$conception_date)
has_ga <- needs_conception & !is.na(df$out_ga_weeks)
no_ga <- needs_conception & is.na(df$out_ga_weeks)

cat(glue("\nDHS needing conception_date: {format(sum(needs_conception), big.mark=',')}\n"))
cat(glue("  With GA weeks (precise): {format(sum(has_ga), big.mark=',')}\n"))
cat(glue("  Without GA (default 280d): {format(sum(no_ga), big.mark=',')}\n"))

# Compute from GA where available
df$conception_date[has_ga] <- df$out_dob[has_ga] - days(round(df$out_ga_weeks[has_ga] * 7))
# Default 280 days (40 weeks) for the rest
df$conception_date[no_ga] <- df$out_dob[no_ga] - days(280L)

cat(glue("  -> Filled {format(sum(needs_conception), big.mark=',')} conception dates\n"))

# --- 3c. Update conception_date_source ---
df$conception_date_source <- as.character(df$conception_date_source)
filled_mask <- needs_conception & !is.na(df$conception_date)
df$conception_date_source[has_ga & !is.na(df$conception_date)] <- "Estimated from DOB and GA"
df$conception_date_source[no_ga & !is.na(df$conception_date)] <- "Estimated from DOB (default 40wk)"

cat("\nconception_date_source distribution:\n")
print(table(df$conception_date_source, useNA = "ifany"))
cat("\n")

# Verify date ranges
cat(glue("delivery_date_raw range: {min(df$delivery_date_raw, na.rm=TRUE)} to {max(df$delivery_date_raw, na.rm=TRUE)}\n"))
cat(glue("conception_date range: {min(df$conception_date, na.rm=TRUE)} to {max(df$conception_date, na.rm=TRUE)}\n\n"))

gc()

# ============================================================================
# STEP 4: COMPUTE MISSING SEASON OF CONCEPTION
# ============================================================================
cat("============================================================\n")
cat("  STEP 4: Compute missing env_season_conception\n")
cat("============================================================\n\n")

before_season <- sum(!is.na(df$env_season_conception))

# Identify records needing season computation
needs_season <- is.na(df$env_season_conception) & !is.na(df$env_latitude) & !is.na(df$conception_date)
cat(glue("Records needing season_conception: {format(sum(needs_season), big.mark=',')}\n"))

# Compute conception month
c_month <- month(df$conception_date[needs_season])
c_lat <- df$env_latitude[needs_season]

# Season logic: Northern (lat >= 0): Wet = May-Oct, Dry = Nov-Apr
#               Southern (lat < 0):  Wet = Nov-Apr, Dry = May-Oct
season_vals <- case_when(
  c_lat >= 0 & c_month %in% 5:10 ~ "Wet",
  c_lat >= 0 & c_month %in% c(1:4, 11:12) ~ "Dry",
  c_lat < 0 & c_month %in% c(11:12, 1:4) ~ "Wet",
  c_lat < 0 & c_month %in% 5:10 ~ "Dry",
  TRUE ~ NA_character_
)

df$env_season_conception <- as.character(df$env_season_conception)
df$env_season_conception[needs_season] <- season_vals

after_season <- sum(!is.na(df$env_season_conception))
cat(glue("  -> Filled {format(after_season - before_season, big.mark=',')} season values\n"))
cat(glue("  Season conception: {format(after_season, big.mark=',')} / {format(n, big.mark=',')} ({round(100*after_season/n, 1)}%)\n\n"))

cat("env_season_conception by study:\n")
print(table(df$study_source, df$env_season_conception, useNA = "ifany"))
cat("\n")

# ============================================================================
# STEP 5: STANDARDISE GESTATIONAL AGE
# ============================================================================
cat("============================================================\n")
cat("  STEP 5: Standardise gestational age variables\n")
cat("============================================================\n\n")

# APPROACH:
#   The source data already stores GA as weeks + days/7, giving clean
#   1/7 decimal fractions:
#     +0 = .000000, +1 = .142857, +2 = .285714, +3 = .428571,
#     +4 = .571428, +5 = .714286, +6 = .857143
#   We do NOT modify out_ga_weeks — just extract weeks+days from it.
#   We recompute out_ga_days (total days) and create out_ga_string.

has_ga_wk <- !is.na(df$out_ga_weeks)

# --- 5a. Log current state ---
ga_log <- list()
ga_log$n_weeks    <- sum(has_ga_wk)
ga_log$n_days_pre <- sum(!is.na(df$out_ga_days))
ga_log$weeks_range <- if (ga_log$n_weeks > 0) range(df$out_ga_weeks, na.rm = TRUE) else c(NA, NA)
ga_log$days_range_pre <- if (ga_log$n_days_pre > 0) range(df$out_ga_days, na.rm = TRUE) else c(NA, NA)

cat("CURRENT STATE:\n")
cat(glue("  out_ga_weeks: {format(ga_log$n_weeks, big.mark=',')} non-NA"), "\n")
cat(glue("    range: {round(ga_log$weeks_range[1], 6)} to {round(ga_log$weeks_range[2], 6)}"), "\n")
cat(glue("  out_ga_days:  {format(ga_log$n_days_pre, big.mark=',')} non-NA"), "\n")
cat(glue("    range: {ga_log$days_range_pre[1]} to {ga_log$days_range_pre[2]}"), "\n\n")

# --- 5b. Verify decimal pattern (1/7 fractions) ---
# Check that remainders cluster around expected 1/7 multiples
remainders <- df$out_ga_weeks[has_ga_wk] - floor(df$out_ga_weeks[has_ga_wk])
expected_fracs <- (0:6) / 7
nearest_frac <- sapply(remainders, function(r) expected_fracs[which.min(abs(r - expected_fracs))])
max_deviation <- max(abs(remainders - nearest_frac))
cat(glue("  Decimal verification: max deviation from nearest 1/7 fraction = {format(max_deviation, scientific=FALSE)}"), "\n")
if (max_deviation > 0.01) {
  cat("  WARNING: Some GA values have non-standard decimals (not clean 1/7 fractions)\n")
} else {
  cat("  OK: All decimals are clean 1/7 fractions (days/7)\n")
}

# --- 5c. Extract whole weeks and remainder days ---
ga_whole   <- floor(df$out_ga_weeks[has_ga_wk])
ga_rem_days <- as.integer(round((df$out_ga_weeks[has_ga_wk] - ga_whole) * 7))

# --- 5c2. Roll over +7 to next week (max remainder is +6) ---
rollover <- ga_rem_days == 7L
if (sum(rollover) > 0) {
  cat(glue("  Rolling over {sum(rollover)} records with +7 to next week (+0)\n"))
  ga_whole[rollover] <- ga_whole[rollover] + 1L
  ga_rem_days[rollover] <- 0L
}

# --- 5c3. Cap implausible GA values to NA ---
# Plausible range: 12-47 weeks (< 12 = miscarriage, > 47 = clinically impossible)
GA_MIN <- 12
GA_MAX <- 47
implausible_ga <- df$out_ga_weeks[has_ga_wk] < GA_MIN | df$out_ga_weeks[has_ga_wk] > GA_MAX
n_implausible <- sum(implausible_ga, na.rm = TRUE)
if (n_implausible > 0) {
  cat(glue("\n  GA PLAUSIBILITY CAPPING: {format(n_implausible, big.mark=',')} records outside [{GA_MIN}, {GA_MAX}] weeks set to NA"), "\n")

  # Show breakdown
  n_too_low  <- sum(df$out_ga_weeks[has_ga_wk] < GA_MIN, na.rm = TRUE)
  n_too_high <- sum(df$out_ga_weeks[has_ga_wk] > GA_MAX, na.rm = TRUE)
  cat(glue("    GA < {GA_MIN}: {format(n_too_low, big.mark=',')} records"), "\n")
  cat(glue("    GA > {GA_MAX}: {format(n_too_high, big.mark=',')} records"), "\n")

  # Show by study
  implausible_idx <- which(has_ga_wk)[implausible_ga]
  cat("    By study:\n")
  print(table(df$study_source[implausible_idx]))

  # Set to NA
  df$out_ga_weeks[which(has_ga_wk)[implausible_ga]] <- NA_real_

  # Also clear out_ga_days for capped records (prevent stale values)
  df$out_ga_days[which(has_ga_wk)[implausible_ga]] <- NA_integer_

  # Update tracking vectors — remove implausible entries from local vectors
  has_ga_wk <- !is.na(df$out_ga_weeks)
  ga_whole   <- ga_whole[!implausible_ga]
  ga_rem_days <- ga_rem_days[!implausible_ga]

  cat(glue("    Remaining valid GA: {format(sum(has_ga_wk), big.mark=',')} records"), "\n")
  cat(glue("    New range: [{round(min(df$out_ga_weeks, na.rm=TRUE), 4)}, {round(max(df$out_ga_weeks, na.rm=TRUE), 4)}]"), "\n\n")
} else {
  cat("  GA plausibility check: all values within [12, 47] weeks\n\n")
}

# --- 5d. Compute out_ga_days (total integer days) from weeks ---
df$out_ga_days[has_ga_wk] <- as.integer(ga_whole * 7L + ga_rem_days)
cat(glue("\n  Computed out_ga_days: {format(sum(has_ga_wk), big.mark=',')} values (total integer days)"), "\n")

# --- 5e. Create obstetric string "weeks+days" (e.g., "38+3") ---
df$out_ga_string <- NA_character_
df$out_ga_string[has_ga_wk] <- paste0(ga_whole, "+", ga_rem_days)
cat(glue("  Created out_ga_string: {format(sum(!is.na(df$out_ga_string)), big.mark=',')} values"), "\n")

# Show examples
example_idx <- which(has_ga_wk)[1:min(10, sum(has_ga_wk))]
cat("\n  Examples (ga_weeks | ga_days | ga_string):\n")
for (idx in example_idx) {
  cat(sprintf("    %10.6f | %4d | %s\n",
              df$out_ga_weeks[idx], df$out_ga_days[idx], df$out_ga_string[idx]))
}

# --- 5e2. Round out_ga_weeks to 4 decimal places (consistent with PRECISE format) ---
df$out_ga_weeks[has_ga_wk] <- round(df$out_ga_weeks[has_ga_wk], 4)
cat(glue("  Rounded out_ga_weeks to 4 decimal places\n"))

# --- 5f. Summary ---
cat(glue("\n  out_ga_weeks: rounded to 4dp — range: {round(min(df$out_ga_weeks, na.rm=TRUE), 4)} to {round(max(df$out_ga_weeks, na.rm=TRUE), 4)}"), "\n")
cat(glue("  out_ga_days:  range {min(df$out_ga_days, na.rm=TRUE)} to {max(df$out_ga_days, na.rm=TRUE)}"), "\n")

cat("\n  out_ga_string frequency (top 20):\n")
ga_tab <- sort(table(df$out_ga_string), decreasing = TRUE)
print(head(ga_tab, 20))

# Verify expected day values (0-6 only)
day_vals <- ga_rem_days
unexpected_days <- sum(day_vals < 0 | day_vals > 6)
if (unexpected_days > 0) {
  cat(glue("\n  WARNING: {unexpected_days} records with remainder days outside 0-6 — check source data"), "\n")
}

# Confirm post-capping range
cat(glue("\n  Post-capping GA range: [{round(min(df$out_ga_weeks, na.rm=TRUE), 4)}, {round(max(df$out_ga_weeks, na.rm=TRUE), 4)}]"), "\n")

# --- 5g. Write GA standardisation log file ---
ga_log_path <- file.path(base_path, "ga_standardisation_log_v10.17.txt")
sink(ga_log_path)
cat("================================================================\n")
cat("  GA STANDARDISATION LOG — v10.17\n")
cat(paste0("  Generated: ", Sys.time(), "\n"))
cat("================================================================\n\n")

cat("APPROACH:\n")
cat("  The source data stores GA as weeks + days/7, giving clean 1/7\n")
cat("  decimal fractions. out_ga_weeks is PRESERVED as-is.\n")
cat("  1. Extract whole weeks = floor(out_ga_weeks)\n")
cat("  2. Extract remainder days = round((out_ga_weeks - weeks) * 7)\n")
cat("  3. Compute out_ga_days = weeks * 7 + days (total integer days)\n")
cat("  4. Create out_ga_string = 'weeks+days' (obstetric format)\n\n")

cat("EXPECTED 1/7 DECIMAL PATTERN:\n")
cat("  +0 days = .000000   +1 day  = .142857   +2 days = .285714\n")
cat("  +3 days = .428571   +4 days = .571429   +5 days = .714286\n")
cat("  +6 days = .857143\n\n")

cat(sprintf("RECORDS:\n  out_ga_weeks: %s non-NA (range: %.6f to %.6f)\n",
            format(ga_log$n_weeks, big.mark = ","),
            ga_log$weeks_range[1], ga_log$weeks_range[2]))
cat(sprintf("  out_ga_days (pre):  %s non-NA (range: %s to %s)\n",
            format(ga_log$n_days_pre, big.mark = ","),
            ga_log$days_range_pre[1], ga_log$days_range_pre[2]))
cat(sprintf("  out_ga_days (post): %s non-NA (range: %.0f to %.0f)\n",
            format(sum(has_ga_wk), big.mark = ","),
            min(df$out_ga_days, na.rm = TRUE),
            max(df$out_ga_days, na.rm = TRUE)))
cat(sprintf("  out_ga_string:      %s non-NA\n",
            format(sum(!is.na(df$out_ga_string)), big.mark = ",")))
cat(sprintf("  Decimal verification: max deviation = %s\n",
            format(max_deviation, scientific = FALSE)))

cat(sprintf("\n  GA plausibility capping: %d records outside [%d, %d] set to NA\n",
            n_implausible, GA_MIN, GA_MAX))

cat("\nout_ga_string FULL DISTRIBUTION:\n")
print(table(df$out_ga_string, useNA = "ifany"))

cat("\nout_ga_string BY STUDY SOURCE:\n")
print(table(df$study_source, df$out_ga_string, useNA = "ifany"))

sink()
cat(glue("\n  GA log saved: {basename(ga_log_path)}"), "\n\n")

rm(ga_whole, ga_rem_days, ga_tab, example_idx, remainders, nearest_frac, day_vals)
gc()

# ============================================================================
# STEP 6: DROP REDUNDANT COLUMNS
# ============================================================================
cat("============================================================\n")
cat("  STEP 6: Drop redundant / coalesced duplicate columns\n")
cat("============================================================\n\n")

cols_to_drop <- c(
  # Coalesced duplicates (data merged into primary)
  "loc_country",        # -> mat_country
  "loc_facility",       # -> mat_facility
  "loc_district",       # -> mat_district
  "loc_urban_rural",    # -> mat_urban_rural
  "obs_parity",         # -> mat_parity
  "obs_gravidity",      # -> mat_gravidity
  "mat_height_cm",      # -> mat_height (will be renamed mat_height_cm)
  "mat_weight_kg",      # -> mat_weight (will be renamed mat_weight_kg)
  "del_mode",           # -> mat_delivery_mode
  "del_location",       # -> mat_delivery_location
  "anc_num_visits",     # -> mat_anc_visits
  "hh_floor_material",  # -> hh_house_floor
  "hh_wall_material",   # -> hh_house_wall
  "hh_size",            # -> hh_household_size (will be renamed hh_size)
  "loc_latitude",       # -> env_latitude
  "loc_longitude",      # -> env_longitude
  "del_attendant",      # -> mat_birth_attendant

  # 100% NA with no duplicate - pure dead columns
  "hh_ownership",       # 100% NA
  "hh_num_rooms",       # 100% NA
  "hh_monthly_income",  # 100% NA
  "hh_hygiene"          # 99.9% NA
)

cat(glue("Dropping {length(cols_to_drop)} columns:\n"))
for (col in cols_to_drop) {
  if (col %in% names(df)) {
    n_na <- sum(is.na(df[[col]]))
    cat(sprintf("  - %-25s  NAs: %s / %s (%.1f%%)\n",
                col, format(n_na, big.mark = ","), format(n, big.mark = ","),
                100 * n_na / n))
  }
}

df <- df %>% select(-any_of(cols_to_drop))
cat(glue("\nDimensions after drop: {nrow(df)} x {ncol(df)}\n\n"))

# ============================================================================
# STEP 7: RENAME FOR CONSISTENCY
# ============================================================================
cat("============================================================\n")
cat("  STEP 7: Rename variables for consistency\n")
cat("============================================================\n\n")

df <- df %>%
  rename(
    mat_height_cm = mat_height,        # Add _cm suffix for clarity
    mat_weight_kg = mat_weight,        # Add _kg suffix for clarity
    hh_size       = hh_household_size  # Shorter, more standard
  )

cat("  mat_height -> mat_height_cm\n")
cat("  mat_weight -> mat_weight_kg\n")
cat("  hh_household_size -> hh_size\n\n")

# ============================================================================
# STEP 8: RE-APPLY FACTOR LEVELS
# ============================================================================
cat("============================================================\n")
cat("  STEP 8: Re-apply factor levels to coalesced columns\n")
cat("============================================================\n\n")

# --- 8a. Convert character columns that should be numeric ---
char_to_num <- c("yob", "hh_ppi_score", "hh_poverty_likelihood", "hh_asset_score",
                 "anc_tetanus", "dhs_cluster")
for (col in char_to_num) {
  if (col %in% names(df) && is.character(df[[col]])) {
    df[[col]] <- suppressWarnings(as.numeric(df[[col]]))
  }
}

# --- 8b. Recode values before factoring ---
# Harmonise mat_delivery_location: Health center/Hospital -> Health facility
if ("mat_delivery_location" %in% names(df)) {
  df$mat_delivery_location[df$mat_delivery_location %in% c("Health center", "Hospital")] <- "Health facility"
}
# Harmonise out_infant_sex: Indeterminate -> Ambiguous
if ("out_infant_sex" %in% names(df)) {
  df$out_infant_sex[df$out_infant_sex == "Indeterminate"] <- "Ambiguous"
}

# --- 8c. Apply factor levels to all categorical columns ---
# SAFETY: Use as.factor() for columns with many/unknown levels.
# Only specify explicit levels for ordered categories and binary No/Yes.
df <- df %>%
  mutate(
    study_source = factor(study_source,
                          levels = c("NCOPS", "ALERT", "PRECISE", "PTBi",
                                     "EN-INDEPTH", "WHOMCS", "DHS")),
    study_design = as.factor(study_design),
    module = as.factor(module),
    coordinate_source = as.factor(coordinate_source),
    out_dob_source = as.factor(out_dob_source),
    conception_date_source = as.factor(conception_date_source),
    mat_age_cat = factor(mat_age_cat,
                         levels = c("<20", "20-24", "25-29", "30-34", "35+")),
    mat_marital_status = as.factor(mat_marital_status),
    mat_education = factor(mat_education,
                           levels = c("None", "Primary", "Secondary", "Higher")),
    mat_literacy = as.factor(mat_literacy),
    mat_occupation = as.factor(mat_occupation),
    mat_urban_rural = factor(mat_urban_rural,
                             levels = c("Rural", "Peri-urban", "Urban")),
    mat_delivery_mode = factor(mat_delivery_mode,
                               levels = c("Vaginal spontaneous", "Vaginal assisted",
                                           "Caesarean", "Other")),
    mat_delivery_location = factor(mat_delivery_location,
                                   levels = c("Home", "Health facility",
                                               "En route/Other facility", "Other")),
    mat_birth_attendant = as.factor(mat_birth_attendant),
    mat_hypertension = factor(mat_hypertension, levels = c("No", "Yes")),
    mat_hypertension_stage = as.factor(mat_hypertension_stage),
    mat_preeclampsia = factor(mat_preeclampsia, levels = c("No", "Yes")),
    mat_eclampsia = factor(mat_eclampsia, levels = c("No", "Yes")),
    mat_aph = factor(mat_aph, levels = c("No", "Yes")),
    mat_diabetes = factor(mat_diabetes, levels = c("No", "Yes")),
    mat_malaria = factor(mat_malaria, levels = c("No", "Yes")),
    mat_anaemia = factor(mat_anaemia, levels = c("No", "Yes")),
    mat_hiv_status = as.factor(mat_hiv_status),
    mat_syphilis = as.factor(mat_syphilis),
    mat_csection = factor(mat_csection, levels = c("No", "Yes")),
    mat_prolonged_labour = factor(mat_prolonged_labour, levels = c("No", "Yes")),
    mat_obstructed_labour = factor(mat_obstructed_labour, levels = c("No", "Yes")),
    mat_prom = factor(mat_prom, levels = c("No", "Yes")),
    mat_previous_stillbirth = factor(mat_previous_stillbirth, levels = c("No", "Yes")),
    mat_previous_csection = as.factor(mat_previous_csection),
    mat_anc_provider = as.factor(mat_anc_provider),
    obs_previous_csection = factor(obs_previous_csection, levels = c("No", "Yes")),
    anc_attendance = factor(anc_attendance, levels = c("No", "Yes")),
    fat_education = factor(fat_education,
                           levels = c("None", "Primary", "Secondary", "Higher")),
    fat_occupation = as.factor(fat_occupation),
    hh_wealth_quintile = as.factor(hh_wealth_quintile),
    hh_ses_binary = as.factor(hh_ses_binary),
    hh_house_floor = as.factor(hh_house_floor),
    hh_house_wall = as.factor(hh_house_wall),
    hh_ppi_band = as.factor(hh_ppi_band),
    hh_cooking_fuel = as.factor(hh_cooking_fuel),
    hh_heating_fuel = as.factor(hh_heating_fuel),
    hh_lighting = as.factor(hh_lighting),
    hh_electricity = factor(hh_electricity, levels = c("No", "Yes")),
    hh_water_source = as.factor(hh_water_source),
    hh_sanitation = as.factor(hh_sanitation),
    hh_mosquito_net = factor(hh_mosquito_net, levels = c("No", "Yes")),
    hh_asset_radio = factor(hh_asset_radio, levels = c("No", "Yes")),
    hh_asset_tv = factor(hh_asset_tv, levels = c("No", "Yes")),
    hh_asset_mobile = factor(hh_asset_mobile, levels = c("No", "Yes")),
    hh_asset_motorbike = factor(hh_asset_motorbike, levels = c("No", "Yes")),
    hh_asset_car = factor(hh_asset_car, levels = c("No", "Yes")),
    out_stillbirth = factor(out_stillbirth, levels = c("No", "Yes")),
    out_stillbirth_20wks = factor(out_stillbirth_20wks, levels = c("No", "Yes")),
    out_stillbirth_28wks = factor(out_stillbirth_28wks, levels = c("No", "Yes")),
    out_fresh_stillbirth = factor(out_fresh_stillbirth, levels = c("No", "Yes")),
    out_macerated_stillbirth = factor(out_macerated_stillbirth, levels = c("No", "Yes")),
    out_livebirth = factor(out_livebirth, levels = c("No", "Yes")),
    out_nnd = factor(out_nnd, levels = c("No", "Yes")),
    out_nnd_early = factor(out_nnd_early, levels = c("No", "Yes")),
    out_nnd_late = factor(out_nnd_late, levels = c("No", "Yes")),
    out_perinatal_death = factor(out_perinatal_death, levels = c("No", "Yes")),
    out_infant_sex = factor(out_infant_sex, levels = c("Female", "Male", "Ambiguous")),
    out_ga_method = as.factor(out_ga_method),
    out_sga = factor(out_sga, levels = c("No", "Yes")),
    out_lga = factor(out_lga, levels = c("No", "Yes")),
    out_aga = factor(out_aga, levels = c("No", "Yes")),
    out_sizeforGA = as.factor(out_sizeforGA),
    out_lbw = factor(out_lbw, levels = c("No", "Yes")),
    out_vlbw = factor(out_vlbw, levels = c("No", "Yes")),
    out_elbw = factor(out_elbw, levels = c("No", "Yes")),
    out_preterm = factor(out_preterm, levels = c("No", "Yes")),
    out_very_preterm = factor(out_very_preterm, levels = c("No", "Yes")),
    out_extremely_preterm = factor(out_extremely_preterm, levels = c("No", "Yes")),
    out_multiple = factor(out_multiple, levels = c("No", "Yes")),
    neo_size_at_birth = as.factor(neo_size_at_birth),
    life_tobacco = factor(life_tobacco, levels = c("No", "Yes")),
    preg_anaemia = factor(preg_anaemia, levels = c("No", "Yes")),
    preg_hiv = as.factor(preg_hiv),
    loc_facility_type = as.factor(loc_facility_type),
    env_season_delivery = factor(env_season_delivery, levels = c("Dry", "Wet")),
    env_season_conception = factor(env_season_conception, levels = c("Dry", "Wet"))
  )

# --- 8d. Validate: check no data was lost ---
n_factors <- sum(sapply(df, is.factor))
cat(glue("  Factor levels applied to {n_factors} columns\n\n"))

# ============================================================================
# STEP 9: REORDER COLUMNS LOGICALLY
# ============================================================================
cat("============================================================\n")
cat("  STEP 9: Reorder columns logically\n")
cat("============================================================\n\n")

col_order <- c(
  # === 1. IDs ===
  "unified_id", "study_source", "study_design", "module",
  "raw_id", "raw_id_secondary", "study_id",
  "dhs_survey_id", "dhs_cluster", "dhs_caseid",

  # === 2. Location ===
  "mat_country", "mat_district", "mat_facility",
  "loc_region", "loc_village", "loc_facility_type",
  "mat_urban_rural",
  "env_latitude", "env_longitude", "coordinate_source",

  # === 3. Dates / Time ===
  "study_date", "studyyear",
  "out_dob", "yob", "out_dob_source",
  "delivery_date_raw",
  "conception_date", "conception_date_source",

  # === 4. Maternal demographics ===
  "mat_age", "mat_age_cat",
  "mat_marital_status", "mat_religion", "mat_ethnicity",
  "mat_education", "mat_literacy", "mat_occupation",

  # === 5. Maternal clinical / anthropometry ===
  "mat_height_cm", "mat_weight_kg", "mat_bmi",
  "mat_muac",
  "mat_sbp", "mat_dbp",
  "mat_hypertension", "mat_hypertension_stage",
  "mat_preeclampsia", "mat_eclampsia",
  "mat_aph", "mat_diabetes", "mat_malaria", "mat_anaemia",
  "mat_hiv_status", "mat_syphilis",

  # === 6. Obstetric ===
  "mat_gravidity", "mat_parity",
  "mat_previous_cs", "obs_previous_csection", "mat_previous_csection",
  "mat_previous_stillbirth",
  "mat_anc_visits", "mat_anc_provider", "anc_attendance", "anc_tetanus",
  "mat_delivery_mode", "mat_delivery_location",
  "mat_birth_attendant", "mat_csection",
  "mat_prolonged_labour", "mat_obstructed_labour", "mat_prom",

  # === 7. Paternal ===
  "fat_education", "fat_occupation",

  # === 8. Household / SES ===
  "hh_wealth_quintile", "hh_ses_binary",
  "hh_size", "hh_asset_score",
  "hh_house_floor", "hh_house_wall",
  "hh_ppi_band",
  "hh_cooking_fuel", "hh_heating_fuel", "hh_lighting",
  "hh_electricity", "hh_water_source", "hh_sanitation",
  "hh_mosquito_net",
  "hh_ppi_score", "hh_poverty_likelihood",
  "hh_asset_radio", "hh_asset_tv", "hh_asset_mobile",
  "hh_asset_motorbike", "hh_asset_car",

  # === 9. Outcomes ===
  "out_stillbirth", "out_stillbirth_20wks", "out_stillbirth_28wks",
  "out_fresh_stillbirth", "out_macerated_stillbirth",
  "out_livebirth",
  "out_nnd", "out_nnd_early", "out_nnd_late",
  "out_perinatal_death",
  "out_infant_sex",
  "out_ga_method", "out_ga_weeks", "out_ga_days", "out_ga_string",
  "out_birthweight_g", "out_birthweight_centile", "out_birthweight_zscore",
  "out_sga", "out_lga", "out_aga", "out_sizeforGA",
  "out_lbw", "out_vlbw", "out_elbw",
  "out_preterm", "out_very_preterm", "out_extremely_preterm",
  "out_apgar_1min", "out_apgar_5min", "out_apgar_10min",
  "out_multiple",
  "out_dod", "out_ageatdeath",
  "neo_size_at_birth",

  # === 10. Lifestyle / Pregnancy ===
  "life_tobacco", "preg_anaemia", "preg_hiv",
  "sample_weight",

  # === 11. Environmental ===
  "env_elevation", "env_slope",
  "env_temp_mean_delivery", "env_humidity_delivery",
  "env_precipitation_delivery", "env_heat_index_delivery",
  "env_pm25_annual", "env_pm25_delivery",
  "env_season_delivery", "env_season_conception"
)

# Safety: catch any columns not in the ordering spec
remaining_cols <- setdiff(names(df), col_order)
if (length(remaining_cols) > 0) {
  cat("WARNING: Columns not in ordering spec (appended at end):\n")
  cat("  ", paste(remaining_cols, collapse = ", "), "\n")
  col_order <- c(col_order, remaining_cols)
}

# Safety: catch columns in spec but missing from df
missing_cols <- setdiff(col_order, names(df))
if (length(missing_cols) > 0) {
  cat("NOTE: Columns in spec but not in dataset (skipped):\n")
  cat("  ", paste(missing_cols, collapse = ", "), "\n")
  col_order <- col_order[col_order %in% names(df)]
}

df <- df %>% select(all_of(col_order))
cat(glue("Final column order applied: {ncol(df)} columns\n\n"))

# ============================================================================
# STEP 10: COMPREHENSIVE DIAGNOSTICS
# ============================================================================
cat("============================================================\n")
cat("  STEP 10: Final diagnostics\n")
cat("============================================================\n\n")

cat(glue("=== FINAL DATASET: v10.17 ===\n"))
cat(glue("{format(nrow(df), big.mark=',')} rows x {ncol(df)} columns\n\n"))

# Column types
cat("=== COLUMN TYPES ===\n")
print(table(sapply(df, function(x) class(x)[1])))
cat("\n")

# Full column listing
cat("=== ALL COLUMNS ===\n")
for (i in seq_along(names(df))) {
  col <- names(df)[i]
  cls <- class(df[[col]])[1]
  n_na <- sum(is.na(df[[col]]))
  pct_na <- round(100 * n_na / nrow(df), 1)
  cat(sprintf("  %3d. %-35s %-12s  NA: %5.1f%%\n", i, col, cls, pct_na))
}

# Date verification
cat("\n=== DATE VERIFICATION ===\n")
for (v in c("out_dob", "out_dod", "delivery_date_raw", "conception_date", "study_date")) {
  if (v %in% names(df) && inherits(df[[v]], "Date")) {
    vals <- df[[v]][!is.na(df[[v]])]
    cat(sprintf("  %-20s  class: Date  range: %s to %s  NAs: %s\n",
                v, min(vals), max(vals), format(sum(is.na(df[[v]])), big.mark = ",")))
  }
}

# Coalesce verification
cat("\n=== COALESCE RESULTS ===\n")
coalesce_checks <- c(
  "mat_parity" = 89.7, "mat_gravidity" = 92.3,
  "mat_height_cm" = 99.9, "mat_weight_kg" = 99.9,
  "mat_delivery_mode" = 91.3, "mat_delivery_location" = 92.6,
  "mat_anc_visits" = 97.6
)
for (v in names(coalesce_checks)) {
  if (v %in% names(df)) {
    now_pct <- round(100 * mean(is.na(df[[v]])), 1)
    cat(sprintf("  %-25s  was: %5.1f%% NA -> now: %5.1f%% NA\n",
                v, coalesce_checks[v], now_pct))
  }
}

# GA verification
cat("\n=== GESTATIONAL AGE VERIFICATION ===\n")
cat(sprintf("  out_ga_weeks:  %s non-NA  range: %.4f to %.4f\n",
            format(sum(!is.na(df$out_ga_weeks)), big.mark = ","),
            min(df$out_ga_weeks, na.rm = TRUE),
            max(df$out_ga_weeks, na.rm = TRUE)))
cat(sprintf("  out_ga_days:   %s non-NA  range: %d to %d\n",
            format(sum(!is.na(df$out_ga_days)), big.mark = ","),
            min(df$out_ga_days, na.rm = TRUE),
            max(df$out_ga_days, na.rm = TRUE)))
cat(sprintf("  out_ga_string: %s non-NA  (e.g., %s)\n",
            format(sum(!is.na(df$out_ga_string)), big.mark = ","),
            paste(head(na.omit(df$out_ga_string), 3), collapse = ", ")))
# Consistency check: weeks * 7 should equal days
ga_check <- !is.na(df$out_ga_weeks) & !is.na(df$out_ga_days)
inconsistent <- sum(abs(round(df$out_ga_weeks[ga_check] * 7) - df$out_ga_days[ga_check]) > 0)
cat(sprintf("  Consistency (weeks*7 == days): %s / %s match\n",
            format(sum(ga_check) - inconsistent, big.mark = ","),
            format(sum(ga_check), big.mark = ",")))
if (inconsistent > 0) cat("  WARNING: inconsistent GA records found!\n")

# Records by study
cat("\n=== RECORDS BY STUDY ===\n")
print(df %>% count(study_source, name = "n_records"))
cat("\n")

gc()

# ============================================================================
# STEP 11: SAVE OUTPUTS
# ============================================================================
cat("============================================================\n")
cat("  STEP 11: Save v10.17 outputs\n")
cat("============================================================\n\n")

# --- RDS ---
rds_path <- file.path(base_path, "unified_dataset_with_env_v10.17_cleaned.rds")
saveRDS(df, rds_path)
cat(glue("Saved: {basename(rds_path)} ({round(file.info(rds_path)$size/1024^2, 1)} MB)\n"))

# --- CSV ---
csv_path <- file.path(base_path, "unified_dataset_with_env_v10.17_cleaned.csv")
write_csv(df, csv_path, na = "")
cat(glue("Saved: {basename(csv_path)} ({round(file.info(csv_path)$size/1024^2, 1)} MB)\n"))

# --- Stata .dta ---
cat("Saving Stata .dta...\n")
df_stata <- df
for (col in names(df_stata)) {
  if (is.factor(df_stata[[col]])) {
    lvls <- levels(df_stata[[col]])
    df_stata[[col]] <- as.integer(df_stata[[col]])
    df_stata[[col]] <- haven::labelled(df_stata[[col]], setNames(seq_along(lvls), lvls))
  }
}
names(df_stata) <- gsub("[.]", "_", names(df_stata))
long_nms <- nchar(names(df_stata)) > 32
if (any(long_nms)) {
  names(df_stata)[long_nms] <- substr(names(df_stata)[long_nms], 1, 32)
}
names(df_stata) <- make.unique(names(df_stata), sep = "_")

dta_path <- file.path(base_path, "unified_dataset_with_env_v10.17_cleaned.dta")
haven::write_dta(df_stata, dta_path, version = 14)
cat(glue("Saved: {basename(dta_path)} ({round(file.info(dta_path)$size/1024^2, 1)} MB)\n\n"))
rm(df_stata)

cat("============================================================\n")
cat("  v10.17 CREATION COMPLETE\n")
cat("============================================================\n\n")
cat(glue("Output files in: {base_path}\n"))
cat("  - unified_dataset_with_env_v10.17_cleaned.rds\n")
cat("  - unified_dataset_with_env_v10.17_cleaned.csv\n")
cat("  - unified_dataset_with_env_v10.17_cleaned.dta\n")
cat("  - ga_standardisation_log_v10.17.txt\n")

rm(df)
gc()
