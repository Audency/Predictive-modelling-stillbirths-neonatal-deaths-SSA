# ============================================================================
# VALIDATION: COMPARE v10.15 vs v10.17 DATASETS
# ============================================================================
# Compares dimensions, gestational age distributions, environmental data
# coverage, and column inventories between v10.15 and v10.17.
#
# Author: Joseph Akuze (LSHTM)
# ============================================================================

suppressPackageStartupMessages(library(tidyverse))

# Set to your unified_dataset_pipeline/output directory, or run from project root.
base <- file.path(getwd(), "output")
cat("Loading v10.15...\n")
v15 <- readRDS(file.path(base, "unified_dataset_with_env_v10.15_cleaned.rds"))
cat("Loading v10.17...\n")
v17 <- readRDS(file.path(base, "unified_dataset_with_env_v10.17_cleaned.rds"))

cat(sprintf("\n=== DIMENSIONS ===\nv10.15: %s rows x %d cols\nv10.17: %s rows x %d cols\n",
            format(nrow(v15), big.mark=","), ncol(v15),
            format(nrow(v17), big.mark=","), ncol(v17)))

cat("\n=== GA STRING +7 CHECK ===\n")
if ("out_ga_string" %in% names(v15)) {
  gs15 <- v15$out_ga_string[!is.na(v15$out_ga_string)]
  has_plus7_v15 <- grepl("[+]7", as.character(gs15))
  cat(sprintf("v10.15 out_ga_string: %d non-NA, %d contain '+7'\n", length(gs15), sum(has_plus7_v15)))
  if (sum(has_plus7_v15) > 0) cat("  Sample: ", head(as.character(gs15[has_plus7_v15]), 5), "\n")
}
if ("out_ga_string" %in% names(v17)) {
  gs17 <- v17$out_ga_string[!is.na(v17$out_ga_string)]
  has_plus7_v17 <- grepl("[+]7", as.character(gs17))
  cat(sprintf("v10.17 out_ga_string: %d non-NA, %d contain '+7'\n", length(gs17), sum(has_plus7_v17)))
  if (sum(has_plus7_v17) > 0) cat("  Sample: ", head(as.character(gs17[has_plus7_v17]), 5), "\n")
} else {
  cat("v10.17: out_ga_string column absent\n")
}

cat("\n=== GA WEEKS RANGE ===\n")
ga15 <- v15$out_ga_weeks[!is.na(v15$out_ga_weeks)]
ga17 <- v17$out_ga_weeks[!is.na(v17$out_ga_weeks)]
cat(sprintf("v10.15: n=%s, range=[%.4f, %.4f], mean=%.4f, median=%.4f\n",
            format(length(ga15), big.mark=","), min(ga15), max(ga15), mean(ga15), median(ga15)))
cat(sprintf("v10.17: n=%s, range=[%.4f, %.4f], mean=%.4f, median=%.4f\n",
            format(length(ga17), big.mark=","), min(ga17), max(ga17), mean(ga17), median(ga17)))

cat("\nv10.17 GA < 12:\n")
cat(sprintf("  Count: %d\n", sum(ga17 < 12)))
cat("\nv10.17 GA > 45:\n")
cat(sprintf("  Count: %d\n", sum(ga17 > 45)))

cat("\nv10.17 GA > 45 by study:\n")
idx45 <- which(!is.na(v17$out_ga_weeks) & v17$out_ga_weeks > 45)
if (length(idx45) > 0) print(table(as.character(v17$study_source[idx45])))

cat("\nv10.17 GA < 12 by study:\n")
idx12 <- which(!is.na(v17$out_ga_weeks) & v17$out_ga_weeks < 12)
if (length(idx12) > 0) print(table(as.character(v17$study_source[idx12])))

cat("\n=== ENVIRONMENTAL DATA ===\n")
env_vars <- c("env_latitude", "env_longitude", "env_elevation_m", "env_slope_deg",
              "env_temp_mean_delivery", "env_humidity_mean_delivery",
              "env_precip_total_delivery", "env_heat_index_mean_delivery",
              "env_pm25_annual", "env_season_delivery", "env_coord_source")
for (v in env_vars) {
  in15 <- v %in% names(v15)
  in17 <- v %in% names(v17)
  if (in15 && in17) {
    n15 <- sum(!is.na(v15[[v]]))
    n17 <- sum(!is.na(v17[[v]]))
    cat(sprintf("  %-35s v15: %9s  v17: %9s  diff: %+d\n",
                v, format(n15, big.mark=","), format(n17, big.mark=","), n17 - n15))
  } else if (in17) {
    n17 <- sum(!is.na(v17[[v]]))
    cat(sprintf("  %-35s v15: (absent)   v17: %9s  NEW\n", v, format(n17, big.mark=",")))
  }
}

cat("\n=== ENV VALUE VARIATION (DHS only) ===\n")
dhs_idx <- as.character(v17$study_source) == "DHS"
if ("env_temp_mean_delivery" %in% names(v17)) {
  dhs_temp <- v17$env_temp_mean_delivery[dhs_idx & !is.na(v17$env_temp_mean_delivery)]
  cat(sprintf("DHS temp: n=%s, unique=%d, range=[%.2f, %.2f]\n",
              format(length(dhs_temp), big.mark=","), n_distinct(dhs_temp), min(dhs_temp), max(dhs_temp)))
}
if ("env_elevation_m" %in% names(v17)) {
  dhs_elev <- v17$env_elevation_m[dhs_idx & !is.na(v17$env_elevation_m)]
  cat(sprintf("DHS elev: n=%s, unique=%d, range=[%.1f, %.1f]\n",
              format(length(dhs_elev), big.mark=","), n_distinct(dhs_elev), min(dhs_elev), max(dhs_elev)))
}

cat("\n=== RELIGION ===\n")
cat("v10.15 top 10:\n")
print(head(sort(table(as.character(v15$mat_religion), useNA="no"), decreasing=TRUE), 10))
cat("\nv10.17 top 10:\n")
print(head(sort(table(as.character(v17$mat_religion), useNA="no"), decreasing=TRUE), 10))

cat("\n=== BIRTH ATTENDANT ===\n")
cat("v10.15:\n")
if ("mat_birth_attendant" %in% names(v15)) {
  print(table(as.character(v15$mat_birth_attendant), useNA="ifany"))
} else cat("  (absent)\n")
cat("\nv10.17:\n")
print(table(as.character(v17$mat_birth_attendant), useNA="ifany"))

cat("\n=== INFANT SEX ===\n")
cat("v10.15:\n")
print(table(as.character(v15$out_sex), useNA="ifany"))
cat("\nv10.17:\n")
print(table(as.character(v17$out_sex), useNA="ifany"))

cat("\n=== DELIVERY LOCATION ===\n")
cat("v10.15:\n")
if ("mat_delivery_location" %in% names(v15)) print(table(as.character(v15$mat_delivery_location), useNA="ifany"))
cat("\nv10.17:\n")
if ("mat_delivery_location" %in% names(v17)) print(table(as.character(v17$mat_delivery_location), useNA="ifany"))

cat("\n=== DATE COLUMNS ===\n")
date_vars <- c("out_dob", "out_dod", "delivery_date_raw", "mat_dob")
for (v in date_vars) {
  in15 <- v %in% names(v15)
  in17 <- v %in% names(v17)
  if (in15 && in17) {
    t15 <- class(v15[[v]])[1]; t17 <- class(v17[[v]])[1]
    n15 <- sum(!is.na(v15[[v]])); n17 <- sum(!is.na(v17[[v]]))
    cat(sprintf("  %-20s v15: %s (%s)  v17: %s (%s)\n",
                v, t15, format(n15, big.mark=","), t17, format(n17, big.mark=",")))
    if (t17 == "Date") {
      vals <- v17[[v]][!is.na(v17[[v]])]
      cat(sprintf("    v17 range: [%s, %s]\n", min(vals), max(vals)))
    }
  } else if (in17) {
    t17 <- class(v17[[v]])[1]; n17 <- sum(!is.na(v17[[v]]))
    cat(sprintf("  %-20s v15: (absent)  v17: %s (%s)\n", v, t17, format(n17, big.mark=",")))
  }
}

cat("\n=== TYPE CHANGES (common columns) ===\n")
common <- intersect(names(v15), names(v17))
for (col in common) {
  t15 <- class(v15[[col]])[1]; t17 <- class(v17[[col]])[1]
  if (t15 != t17) cat(sprintf("  %-30s %s -> %s\n", col, t15, t17))
}

cat("\n=== KEY COMPLETENESS COMPARISON ===\n")
key_vars <- c("mat_age", "mat_bmi", "mat_height", "mat_weight_kg", "mat_parity",
              "mat_gravidity", "mat_education", "mat_religion", "mat_ethnicity",
              "mat_birth_attendant", "mat_delivery_mode", "mat_delivery_location",
              "mat_marital_status", "mat_anc_visits", "mat_hypertension",
              "out_ga_weeks", "out_bw_grams", "out_sex", "out_outcome",
              "out_apgar_5min", "out_dob", "out_dod",
              "mat_eclampsia", "mat_aph", "mat_diabetes", "mat_malaria",
              "mat_anaemia", "mat_previous_csection", "preg_hiv",
              "loc_facility_type", "hh_ppi_band", "out_apgar_10min")
cat(sprintf("%-30s %12s %12s %12s\n", "Variable", "v10.15", "v10.17", "Diff"))
cat(paste(rep("-", 70), collapse=""), "\n")
for (v in key_vars) {
  in15 <- v %in% names(v15); in17 <- v %in% names(v17)
  if (in15 && in17) {
    n15 <- sum(!is.na(v15[[v]])); n17 <- sum(!is.na(v17[[v]]))
    cat(sprintf("%-30s %12s %12s %+12d\n", v, format(n15, big.mark=","), format(n17, big.mark=","), n17-n15))
  } else if (in17 && !in15) {
    n17 <- sum(!is.na(v17[[v]]))
    cat(sprintf("%-30s %12s %12s %12s\n", v, "(absent)", format(n17, big.mark=","), "NEW"))
  } else if (in15 && !in17) {
    n15 <- sum(!is.na(v15[[v]]))
    cat(sprintf("%-30s %12s %12s %12s\n", v, format(n15, big.mark=","), "(absent)", "DROPPED"))
  }
}

cat("\n=== COLUMNS ONLY IN v10.15 (dropped) ===\n")
only15 <- setdiff(names(v15), names(v17))
cat(paste(only15, collapse="\n"), "\n")

cat("\n=== COLUMNS ONLY IN v10.17 (new) ===\n")
only17 <- setdiff(names(v17), names(v15))
cat(paste(only17, collapse="\n"), "\n")

rm(v15, v17); gc(verbose=FALSE)
cat("\nDONE\n")
