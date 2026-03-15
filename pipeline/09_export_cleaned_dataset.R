# ============================================================================
# PIPELINE STEP 09: EXPORT CLEANED DATASET
# ============================================================================
# PURPOSE:
#   Exports the cleaned v10.17 dataset to Stata (.dta), CSV, and generates
#   a comprehensive data dictionary in XLSX format (5 sheets).
#
# INPUT:
#   output/unified_dataset_with_env_v10.17_cleaned.rds  (from Step 08)
#
# OUTPUT:
#   output/unified_dataset_with_env_v10.17_cleaned.dta
#   output/unified_dataset_with_env_v10.17_cleaned.csv
#   output/unified_dataset_v10.17_data_dictionary.xlsx
#
# Author: Joseph Akuze (LSHTM)
# ============================================================================

library(haven)
library(openxlsx)
library(tidyverse)

cat("Loading cleaned dataset...\n")
base_path <- file.path(getwd(), "output")
df <- readRDS(file.path(base_path, "unified_dataset_with_env_v10.17_cleaned.rds"))
cat("Loaded:", nrow(df), "rows x", ncol(df), "columns\n\n")

# ============================================================
# 1. Export to Stata .dta
# ============================================================
cat("Exporting to Stata .dta ...\n")

df_stata <- df
for (col in names(df_stata)) {
  if (is.factor(df_stata[[col]])) {
    lvls <- levels(df_stata[[col]])
    df_stata[[col]] <- as.integer(df_stata[[col]])
    df_stata[[col]] <- haven::labelled(df_stata[[col]], setNames(seq_along(lvls), lvls))
  }
}

dta_path <- file.path(base_path, "unified_dataset_with_env_v10.17_cleaned.dta")
write_dta(df_stata, dta_path, version = 14)
cat("  Saved:", dta_path, "\n")
cat("  Size:", round(file.size(dta_path) / 1024^2, 1), "MB\n\n")
rm(df_stata)
gc()

# ============================================================
# 2. Export to CSV
# ============================================================
cat("Exporting to CSV ...\n")
csv_path <- file.path(base_path, "unified_dataset_with_env_v10.17_cleaned.csv")
write_csv(df, csv_path, na = "")
cat("  Saved:", csv_path, "\n")
cat("  Size:", round(file.size(csv_path) / 1024^2, 1), "MB\n\n")

# ============================================================
# 3. Create comprehensive data dictionary (XLSX)
# ============================================================
cat("Creating data dictionary...\n")

# --- Sheet 1: Variable Overview ---
overview <- data.frame(
  variable_number = seq_along(names(df)),
  variable_name   = names(df),
  class           = sapply(df, function(x) paste(class(x), collapse = "/")),
  n_total         = nrow(df),
  n_present       = sapply(df, function(x) sum(!is.na(x))),
  n_missing       = sapply(df, function(x) sum(is.na(x))),
  pct_present     = round(sapply(df, function(x) mean(!is.na(x)) * 100), 2),
  pct_missing     = round(sapply(df, function(x) mean(is.na(x)) * 100), 2),
  n_unique        = sapply(df, function(x) length(unique(x[!is.na(x)]))),
  stringsAsFactors = FALSE
)
rownames(overview) <- NULL

# Add data type category
overview$type_category <- sapply(df, function(x) {
  cls <- class(x)[1]
  if (cls == "factor") {
    lvls <- levels(x)
    if (all(lvls %in% c("No", "Yes"))) return("Binary (Yes/No)")
    return("Categorical (factor)")
  }
  if (cls == "numeric" || cls == "integer") return("Numeric")
  if (cls == "Date") return("Date")
  if (cls == "character") return("Character/ID")
  return(cls)
})

# Add example values / levels
overview$example_values <- sapply(names(df), function(col) {
  vals <- df[[col]][!is.na(df[[col]])]
  if (length(vals) == 0) return("(all NA)")
  if (is.factor(df[[col]])) {
    return(paste(levels(df[[col]]), collapse = " | "))
  }
  uniq_vals <- unique(vals)
  if (length(uniq_vals) <= 10) {
    return(paste(sort(as.character(uniq_vals)), collapse = " | "))
  }
  if (is.numeric(vals)) {
    return(sprintf("min=%.2f | median=%.2f | max=%.2f", min(vals), median(vals), max(vals)))
  }
  return(paste(head(unique(as.character(vals)), 5), collapse = " | "))
})

# Add range for numeric/date
overview$range_min <- sapply(names(df), function(col) {
  x <- df[[col]]
  if (is.numeric(x)) {
    v <- x[!is.na(x)]
    if (length(v) > 0) return(as.character(round(min(v), 4)))
  }
  if (inherits(x, "Date")) {
    v <- x[!is.na(x)]
    if (length(v) > 0) return(as.character(min(v)))
  }
  return(NA_character_)
})

overview$range_max <- sapply(names(df), function(col) {
  x <- df[[col]]
  if (is.numeric(x)) {
    v <- x[!is.na(x)]
    if (length(v) > 0) return(as.character(round(max(v), 4)))
  }
  if (inherits(x, "Date")) {
    v <- x[!is.na(x)]
    if (length(v) > 0) return(as.character(max(v)))
  }
  return(NA_character_)
})

cat("  Sheet 1: Variable Overview done\n")

# --- Sheet 2: Data Presence by Study Source ---
src_levels <- levels(df$study_source)
if (is.null(src_levels)) src_levels <- sort(unique(as.character(df$study_source)))

presence_by_source <- data.frame(variable_name = names(df), stringsAsFactors = FALSE)
for (src in src_levels) {
  sub <- df[as.character(df$study_source) == src, ]
  col_n   <- paste0("n_present_", src)
  col_pct <- paste0("pct_present_", src)
  presence_by_source[[col_n]]   <- sapply(sub, function(x) sum(!is.na(x)))
  presence_by_source[[col_pct]] <- round(sapply(sub, function(x) mean(!is.na(x)) * 100), 1)
}
cat("  Sheet 2: Presence by Study Source done\n")

# --- Sheet 3: Factor/Categorical Value Labels ---
factor_rows <- list()
factor_vars <- names(df)[sapply(df, is.factor)]
for (v in factor_vars) {
  tbl <- table(df[[v]], useNA = "no")
  n_nonmiss <- sum(tbl)
  for (i in seq_along(tbl)) {
    factor_rows[[length(factor_rows) + 1]] <- data.frame(
      variable_name     = v,
      level_number      = i,
      level_label       = names(tbl)[i],
      n_count           = as.integer(tbl[i]),
      pct_of_nonmissing = round(tbl[i] / n_nonmiss * 100, 2),
      stringsAsFactors  = FALSE
    )
  }
}
factor_details <- do.call(rbind, factor_rows)
cat("  Sheet 3: Factor Value Labels done\n")

# --- Sheet 4: Numeric Variable Statistics ---
num_rows <- list()
num_vars <- names(df)[sapply(df, is.numeric)]
for (v in num_vars) {
  vals <- df[[v]][!is.na(df[[v]])]
  if (length(vals) > 0) {
    num_rows[[length(num_rows) + 1]] <- data.frame(
      variable_name = v,
      n_present     = length(vals),
      n_missing     = sum(is.na(df[[v]])),
      min           = round(min(vals), 4),
      p1            = round(quantile(vals, 0.01), 4),
      p5            = round(quantile(vals, 0.05), 4),
      p25           = round(quantile(vals, 0.25), 4),
      median        = round(median(vals), 4),
      mean          = round(mean(vals), 4),
      p75           = round(quantile(vals, 0.75), 4),
      p95           = round(quantile(vals, 0.95), 4),
      p99           = round(quantile(vals, 0.99), 4),
      max           = round(max(vals), 4),
      sd            = round(sd(vals), 4),
      stringsAsFactors = FALSE
    )
  }
}
numeric_stats <- do.call(rbind, num_rows)
rownames(numeric_stats) <- NULL
cat("  Sheet 4: Numeric Statistics done\n")

# --- Sheet 5: Cleaning Actions Log ---
cleaning_log <- data.frame(
  step = c("2", "3", "4", "5",
           "6.1", "6.2", "6.3", "6.4", "6.5", "6.6", "6.7", "6.8", "6.9", "6.10",
           "6.11", "6.12", "6.13", "6.14", "6.15", "6.16", "6.17", "6.18", "6.19",
           "7.1", "7.2", "7.3", "7.4", "7.5",
           "7.8", "7.9", "7.10", "7.11", "7.13",
           "8", "9", "10"),
  variables = c(
    "11 columns (mat_previous_csection, mat_anc_provider, etc.)",
    "dhs_caseid + others", "All character columns", "32 columns",
    "mat_marital_status", "mat_occupation", "mat_hiv_status", "hh_wealth_quintile",
    "hh_water_source", "hh_sanitation", "mat_birth_attendant", "mat_delivery_mode",
    "mat_delivery_location", "hh_cooking_fuel",
    "out_infant_sex", "mat_syphilis", "mat_hypertension_stage", "hh_heating_fuel",
    "hh_lighting", "out_ga_method", "hh_house_wall", "hh_house_floor", "conception_date_source",
    "out_ga_weeks, out_ga_days", "out_birthweight_g", "out_ageatdeath", "mat_age", "mat_bmi",
    "mat_sbp, mat_dbp", "out_apgar_1min, out_apgar_5min",
    "mat_height, mat_weight, mat_height_cm, mat_weight_kg", "mat_muac",
    "mat_parity, mat_gravidity, obs_parity, obs_gravidity",
    "out_dob, out_dod", "38 binary columns", "35 categorical columns"
  ),
  action = c(
    "Dropped (100% NA or single-value)", "Trimmed whitespace", "Empty strings to NA",
    "Character to numeric conversion",
    "Merged duplicate categories (7 to 4)", "Merged duplicate categories (11 to 6)",
    "Merged duplicate categories (6 to 3)", "Merged duplicate categories (10 to 5)",
    "Merged duplicate categories (8 to 7)", "Merged duplicate categories (9 to 6)",
    "Merged duplicate categories (9 to 7)", "Merged duplicate categories (5 to 4)",
    "Merged facility subtypes (5 to 4)", "Merged fuel types (14 to 5)",
    "Indeterminate (n=79) to NA", "Merged unknown categories (5 to 3)",
    "Shortened labels", "Grouped small categories", "Grouped small categories",
    "Merged subtypes", "Separator fix (hyphen to slash)", "Separator fix (hyphen to slash)",
    "Merged 2 labels to 1",
    "Range cap 12-46 wk / 84-322 days", "Range cap 200-7000g",
    "Negatives and >365d to NA", "Range cap 10-55 years", "Range cap 13-60",
    "SBP 60-250, DBP 30-160", "Integer 0-10 only",
    "Height 100-210cm, Weight 25-200kg", "Range cap 15-50cm",
    "Upper cap >20 to NA",
    "Date cap 1990-2026", "Character to factor (No/Yes)", "Character to ordered/unordered factor"
  ),
  stringsAsFactors = FALSE
)
cat("  Sheet 5: Cleaning Actions Log done\n")

# --- Write XLSX ---
xlsx_path <- file.path(base_path, "unified_dataset_v10.17_data_dictionary.xlsx")

wb <- createWorkbook()

addWorksheet(wb, "Variable Overview")
writeData(wb, "Variable Overview", overview)
setColWidths(wb, "Variable Overview", cols = 1:ncol(overview), widths = "auto")
conditionalFormatting(wb, "Variable Overview", cols = 8, rows = 2:(nrow(overview)+1),
                      type = "colourScale",
                      style = c("#63BE7B", "#FFEB84", "#F8696B"),
                      rule = c(0, 50, 100))

addWorksheet(wb, "Presence by Study Source")
writeData(wb, "Presence by Study Source", presence_by_source)
setColWidths(wb, "Presence by Study Source", cols = 1:ncol(presence_by_source), widths = "auto")

addWorksheet(wb, "Factor Value Labels")
writeData(wb, "Factor Value Labels", factor_details)
setColWidths(wb, "Factor Value Labels", cols = 1:ncol(factor_details), widths = "auto")

addWorksheet(wb, "Numeric Statistics")
writeData(wb, "Numeric Statistics", numeric_stats)
setColWidths(wb, "Numeric Statistics", cols = 1:ncol(numeric_stats), widths = "auto")

addWorksheet(wb, "Cleaning Actions Log")
writeData(wb, "Cleaning Actions Log", cleaning_log)
setColWidths(wb, "Cleaning Actions Log", cols = 1:ncol(cleaning_log), widths = "auto")

for (s in c("Variable Overview", "Presence by Study Source", "Factor Value Labels",
            "Numeric Statistics", "Cleaning Actions Log")) {
  freezePane(wb, s, firstRow = TRUE)
}

saveWorkbook(wb, xlsx_path, overwrite = TRUE)
cat("  Saved:", xlsx_path, "\n")
cat("  Size:", round(file.size(xlsx_path) / 1024^2, 1), "MB\n\n")

cat("=== ALL EXPORTS COMPLETE ===\n")
