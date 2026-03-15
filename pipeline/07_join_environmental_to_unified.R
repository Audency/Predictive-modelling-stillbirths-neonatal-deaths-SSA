# ============================================================================
# PIPELINE STEP 07: JOIN ENVIRONMENTAL DATA TO UNIFIED DATASET
# ============================================================================
# PURPOSE:
#   Joins the environmental linkage file (v3.4) to the merged unified dataset
#   (v10.16), producing a single dataset with all harmonised variables plus
#   environmental exposures (elevation, climate, PM2.5, seasonality).
#
# INPUT:
#   output/merged_unified_dataset_v10.16.rds          (from Step 04)
#   output/environmental/environmental_linkage_v3.4.rds (from Step 06)
#
# OUTPUT:
#   output/unified_dataset_with_env_v10.16.rds
#   output/unified_dataset_with_env_v10.16.csv
#   output/unified_dataset_with_env_v10.16.dta
#
# Author: Joseph Akuze (LSHTM)
# ============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(haven)
  library(glue)
})

cat("=== Join Environmental Data to Unified Dataset ===\n\n")

# Load datasets
cat("Loading unified dataset...\n")
unified <- readRDS("output/merged_unified_dataset_v10.16.rds")
cat(glue("  Loaded: {nrow(unified)} rows x {ncol(unified)} cols\n\n"))

cat("Loading environmental linkage...\n")
environmental <- readRDS("output/environmental/environmental_linkage_v3.4.rds")
cat(glue("  Loaded: {nrow(environmental)} rows x {ncol(environmental)} cols\n"))
cat(glue("  linkage_ready: {sum(environmental$linkage_ready, na.rm=TRUE)}\n\n"))

# Select environmental variables
env_vars_to_merge <- environmental %>%
  filter(linkage_ready) %>%
  select(
    unified_id,
    env_latitude, env_longitude, coordinate_source,
    env_elevation, env_slope,
    env_temp_mean_delivery, env_humidity_delivery,
    env_precipitation_delivery, env_heat_index_delivery,
    env_pm25_annual, env_pm25_delivery,
    env_season_delivery, env_season_conception
  )
cat(glue("Env vars to merge: {nrow(env_vars_to_merge)} rows\n\n"))

rm(environmental)
gc()

# Merge
cat("Joining...\n")
unified_with_env <- unified %>%
  left_join(env_vars_to_merge, by = "unified_id")

rm(unified, env_vars_to_merge)
gc()

# Coalesce duplicate columns (.x and .y from join)
env_cols <- names(unified_with_env)
y_cols <- grep("\\.y$", env_cols, value = TRUE)
base_names <- gsub("\\.y$", "", y_cols)

if (length(base_names) > 0) {
  cat(glue("Coalescing {length(base_names)} duplicate column pairs...\n"))
  for (bn in base_names) {
    x_col <- paste0(bn, ".x")
    y_col <- paste0(bn, ".y")

    if (x_col %in% names(unified_with_env) && y_col %in% names(unified_with_env)) {
      tx <- class(unified_with_env[[x_col]])[1]
      ty <- class(unified_with_env[[y_col]])[1]
      if (tx != ty) {
        if (tx %in% c("numeric", "double", "integer") && ty == "character") {
          unified_with_env[[y_col]] <- suppressWarnings(as.numeric(unified_with_env[[y_col]]))
        } else if (ty %in% c("numeric", "double", "integer") && tx == "character") {
          unified_with_env[[x_col]] <- suppressWarnings(as.numeric(unified_with_env[[x_col]]))
        } else {
          unified_with_env[[x_col]] <- as.character(unified_with_env[[x_col]])
          unified_with_env[[y_col]] <- as.character(unified_with_env[[y_col]])
        }
      }
      unified_with_env[[x_col]] <- dplyr::coalesce(
        unified_with_env[[x_col]],
        unified_with_env[[y_col]]
      )
      unified_with_env[[y_col]] <- NULL
      names(unified_with_env)[names(unified_with_env) == x_col] <- bn
      cat(glue("  Coalesced {bn}: {sum(!is.na(unified_with_env[[bn]]))} non-NA values\n"))
    }
  }
} else {
  cat("No duplicate columns to coalesce.\n")
}

cat(glue("\nFinal dataset: {nrow(unified_with_env)} rows x {ncol(unified_with_env)} cols\n"))
cat(glue("Records with env_latitude: {sum(!is.na(unified_with_env$env_latitude))}\n"))
cat(glue("Records with env_temp: {sum(!is.na(unified_with_env$env_temp_mean_delivery))}\n"))
cat(glue("Records with PM2.5: {sum(!is.na(unified_with_env$env_pm25_annual))}\n\n"))

# Save RDS
cat("Saving RDS...\n")
saveRDS(unified_with_env, "output/unified_dataset_with_env_v10.16.rds")
cat(glue("  Saved: unified_dataset_with_env_v10.16.rds ({round(file.info('output/unified_dataset_with_env_v10.16.rds')$size/1024^2,1)} MB)\n"))

# Save CSV
cat("Saving CSV...\n")
write_csv(unified_with_env, "output/unified_dataset_with_env_v10.16.csv")
cat(glue("  Saved: unified_dataset_with_env_v10.16.csv\n"))

# Save Stata
cat("Saving Stata .dta...\n")
stata_out <- unified_with_env
names(stata_out) <- gsub("[.]", "_", names(stata_out))
names(stata_out) <- make.unique(names(stata_out), sep = "_")
long_nms <- nchar(names(stata_out)) > 32
if (any(long_nms)) {
  names(stata_out)[long_nms] <- substr(names(stata_out)[long_nms], 1, 32)
  names(stata_out) <- make.unique(names(stata_out), sep = "_")
}
haven::write_dta(stata_out, "output/unified_dataset_with_env_v10.16.dta", version = 14)
cat(glue("  Saved: unified_dataset_with_env_v10.16.dta\n\n"))
rm(stata_out)

cat("=== JOIN COMPLETE ===\n")
