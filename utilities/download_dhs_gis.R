# ============================================================================
# DOWNLOAD DHS GIS DATA AND LINK GPS TO UNIFIED DATASET
# ============================================================================
# PURPOSE:
#   Downloads DHS Geographic Data (GE) shapefiles using direct URLs from
#   gis_url.txt, extracts cluster-level GPS coordinates, and links them
#   to the merged unified dataset to create v10.16 with real GPS data.
#
#   This replaces the country centroid workaround with actual cluster-level
#   GPS coordinates (displaced up to 2km urban, 5km rural per DHS protocol).
#
# AUTHENTICATION:
#   DHS file downloads require login. The script will prompt for your
#   DHS password at runtime (never stored in files).
#
# INPUTS:
#   - data/dhs/geographic/gis_url.txt  (127 DHS GIS download URLs)
#   - output/merged_unified_dataset_v10.15.rds  (6+DHS study base)
#   - output/environmental/environmental_linkage_v3.3.rds  (env data)
#
# OUTPUTS:
#   - data/dhs/geographic/zips/  (downloaded GE zip files)
#   - data/dhs/geographic/shapefiles/  (extracted shapefiles)
#   - data/dhs/geographic/dhs_gps_lookup.rds  (combined GPS reference)
#   - output/merged_unified_dataset_v10.16.rds  (with real GPS)
#   - output/merged_unified_dataset_v10.16.csv
#   - output/merged_unified_dataset_v10.16.dta
#
# RUNTIME: ~30-60 minutes (mostly download time)
# ============================================================================

cat("============================================================\n")
cat("  DOWNLOAD DHS GIS DATA & LINK GPS\n")
cat("============================================================\n\n")

# --- Load packages ---
suppressPackageStartupMessages({
  library(httr)
  library(tidyverse)
  library(sf)
  library(haven)
  library(glue)
  library(jsonlite)
})

# --- Directory setup ---
user <- Sys.info()[["user"]]
# --- CONFIGURATION: Set your local path below ---
if (user == "eidejwai") {
  dropbox_base <- "C:/Users/eidejwai/Dropbox/Predictive Models for SB and NND/Minimalist/unified_dataset_pipeline"
} else if (user == "josep") {
  dropbox_base <- "C:/Users/josep/Dropbox/Predictive Models for SB and NND/Minimalist/unified_dataset_pipeline"
} else {
  dropbox_base <- getwd()
  cat("NOTE: Unknown user. Using working directory as project root.\n")
}

dirs <- list(
  pipeline   = dropbox_base,
  geo_base   = file.path(dropbox_base, "data", "dhs", "geographic"),
  geo_zips   = file.path(dropbox_base, "data", "dhs", "geographic", "zips"),
  geo_shp    = file.path(dropbox_base, "data", "dhs", "geographic", "shapefiles"),
  output     = file.path(dropbox_base, "output")
)

for (d in dirs) dir.create(d, recursive = TRUE, showWarnings = FALSE)

cat("Directories:\n")
cat(glue("  Pipeline:    {dirs$pipeline}\n"))
cat(glue("  GIS zips:    {dirs$geo_zips}\n"))
cat(glue("  Shapefiles:  {dirs$geo_shp}\n"))
cat(glue("  Output:      {dirs$output}\n\n"))

# ============================================================================
# STEP 1: DHS AUTHENTICATION
# ============================================================================
cat("============================================================\n")
cat("  STEP 1: Authenticate with DHS website\n")
cat("============================================================\n\n")

# Read email from rdhs.json
rdhs_config_file <- file.path(dropbox_base, "data", "dhs", "rdhs.json")
rdhs_config <- jsonlite::fromJSON(rdhs_config_file)
dhs_email <- rdhs_config$email
cat(glue("DHS email: {dhs_email}\n"))

# Get password (prompt at runtime - never stored)
dhs_password <- rdhs_config$password
if (is.null(dhs_password) || nchar(trimws(dhs_password)) == 0) {
  if (requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
    dhs_password <- rstudioapi::askForPassword("Enter your DHS password:")
  } else {
    cat("Enter your DHS password: ")
    dhs_password <- readline()
  }
}

if (nchar(trimws(dhs_password)) == 0) {
  stop("No DHS password provided. Cannot download files.")
}

# Create persistent session handle
dhs_handle <- handle("https://dhsprogram.com")

# Login
cat("Logging in to DHS website...\n")
login_resp <- POST(
  "https://dhsprogram.com/data/dataset_admin/login_main.cfm",
  handle = dhs_handle,
  body = list(
    Submitted = "1",
    UserType  = "2",
    UserName  = dhs_email,
    UserPass  = dhs_password,
    submit    = "Sign In"
  ),
  encode = "form",
  timeout(30)
)

# Clear password from memory immediately
rm(dhs_password)

if (status_code(login_resp) >= 400) {
  stop(glue("DHS login failed with HTTP {status_code(login_resp)}"))
}

# Verify login by checking if we get redirected to download page (not back to login)
login_content <- content(login_resp, "text", encoding = "UTF-8")
if (grepl("Incorrect email or password", login_content, ignore.case = TRUE)) {
  stop("DHS login failed: Incorrect email or password")
}

cat("DHS authentication successful.\n\n")

# ============================================================================
# STEP 2: DOWNLOAD GE ZIP FILES
# ============================================================================
cat("============================================================\n")
cat("  STEP 2: Download GE zip files from gis_url.txt\n")
cat("============================================================\n\n")

# Read URLs
url_file <- file.path(dirs$geo_base, "gis_url.txt")
urls <- readLines(url_file)
urls <- urls[nchar(trimws(urls)) > 0]  # Remove empty lines
cat(glue("Found {length(urls)} download URLs\n\n"))

# Extract filename from each URL
extract_filename <- function(url) {
  m <- regmatches(url, regexpr("Filename=([^&]+)", url))
  if (length(m) > 0) gsub("Filename=", "", m) else NA_character_
}

# Download each file
n_downloaded <- 0
n_skipped    <- 0
n_failed     <- 0
failed_files <- character(0)

for (i in seq_along(urls)) {
  url <- urls[i]
  filename <- extract_filename(url)

  if (is.na(filename)) {
    cat(glue("  [{i}/{length(urls)}] SKIP - cannot parse filename from URL\n"))
    n_failed <- n_failed + 1
    next
  }

  dest_path <- file.path(dirs$geo_zips, filename)

  # Skip if already downloaded and file size > 1KB
  if (file.exists(dest_path) && file.info(dest_path)$size > 1024) {
    n_skipped <- n_skipped + 1
    if (i %% 20 == 0 || i == length(urls)) {
      cat(glue("  [{i}/{length(urls)}] {filename} - already exists (skipped)\n"))
    }
    next
  }

  cat(glue("  [{i}/{length(urls)}] {filename}... "))

  tryCatch({
    resp <- GET(url, handle = dhs_handle, timeout(120),
                write_disk(dest_path, overwrite = TRUE))

    if (status_code(resp) == 200) {
      fsize <- file.info(dest_path)$size
      # Check if we got an actual ZIP (not an HTML login page)
      if (fsize > 5000) {
        # Quick check: ZIP magic number starts with PK (0x50 0x4B)
        con <- file(dest_path, "rb")
        magic <- readBin(con, raw(), n = 2)
        close(con)
        if (length(magic) >= 2 && magic[1] == as.raw(0x50) && magic[2] == as.raw(0x4B)) {
          cat(glue("OK ({round(fsize/1024)} KB)\n"))
          n_downloaded <- n_downloaded + 1
        } else {
          cat(glue("FAILED (not a ZIP, likely auth error)\n"))
          file.remove(dest_path)
          n_failed <- n_failed + 1
          failed_files <- c(failed_files, filename)
        }
      } else {
        cat(glue("FAILED (too small: {fsize} bytes)\n"))
        file.remove(dest_path)
        n_failed <- n_failed + 1
        failed_files <- c(failed_files, filename)
      }
    } else {
      cat(glue("FAILED (HTTP {status_code(resp)})\n"))
      if (file.exists(dest_path)) file.remove(dest_path)
      n_failed <- n_failed + 1
      failed_files <- c(failed_files, filename)
    }
  }, error = function(e) {
    cat(glue("ERROR ({e$message})\n"))
    if (file.exists(dest_path)) file.remove(dest_path)
    n_failed <<- n_failed + 1
    failed_files <<- c(failed_files, filename)
  })

  # Small delay to be polite to server
  Sys.sleep(0.5)
}

cat(glue("\n--- Download Summary ---\n"))
cat(glue("  New downloads: {n_downloaded}\n"))
cat(glue("  Skipped (already exist): {n_skipped}\n"))
cat(glue("  Failed: {n_failed}\n"))
if (length(failed_files) > 0) {
  cat("  Failed files:\n")
  for (f in failed_files) cat(glue("    - {f}\n"))
}
cat("\n")

# Count total available zips
zip_files <- list.files(dirs$geo_zips, pattern = "\\.zip$", full.names = TRUE)
cat(glue("Total ZIP files available: {length(zip_files)}\n\n"))

if (length(zip_files) == 0) {
  stop("No ZIP files downloaded. Check DHS credentials and try again.")
}

# ============================================================================
# STEP 3: EXTRACT SHAPEFILES FROM ZIPS
# ============================================================================
cat("============================================================\n")
cat("  STEP 3: Extract shapefiles from ZIP files\n")
cat("============================================================\n\n")

n_extracted <- 0

for (zf in zip_files) {
  stem <- tools::file_path_sans_ext(basename(zf))
  extract_dir <- file.path(dirs$geo_shp, stem)

  # Skip if already extracted and has .shp file
  existing_shp <- list.files(extract_dir, pattern = "\\.shp$",
                              full.names = TRUE, recursive = TRUE)
  if (length(existing_shp) > 0) {
    n_extracted <- n_extracted + 1
    next
  }

  tryCatch({
    dir.create(extract_dir, recursive = TRUE, showWarnings = FALSE)
    unzip(zf, exdir = extract_dir, overwrite = TRUE)
    shp_check <- list.files(extract_dir, pattern = "\\.shp$",
                             recursive = TRUE, full.names = TRUE)
    if (length(shp_check) > 0) {
      n_extracted <- n_extracted + 1
    } else {
      cat(glue("  WARNING: {stem} - no .shp found in zip\n"))
    }
  }, error = function(e) {
    cat(glue("  ERROR extracting {stem}: {e$message}\n"))
  })
}

cat(glue("Extracted shapefiles: {n_extracted} / {length(zip_files)}\n\n"))

# ============================================================================
# STEP 4: READ ALL SHAPEFILES AND BUILD GPS LOOKUP TABLE
# ============================================================================
cat("============================================================\n")
cat("  STEP 4: Read shapefiles and build GPS lookup table\n")
cat("============================================================\n\n")

# Find all .shp files
all_shp <- list.files(dirs$geo_shp, pattern = "\\.shp$",
                       full.names = TRUE, recursive = TRUE)
cat(glue("Found {length(all_shp)} shapefiles\n\n"))

all_geo <- list()

for (shp_path in all_shp) {
  tryCatch({
    geo <- st_read(shp_path, quiet = TRUE)
    geo_df <- geo %>% st_drop_geometry()

    # Standard DHS GE columns
    needed_cols <- c("DHSCLUST", "LATNUM", "LONGNUM")
    if (!all(needed_cols %in% names(geo_df))) {
      cat(glue("  SKIP {basename(shp_path)}: missing columns ({paste(setdiff(needed_cols, names(geo_df)), collapse=', ')})\n"))
      next
    }

    # Extract survey identifiers from shapefile
    geo_out <- geo_df %>%
      select(any_of(c("DHSID", "DHSCC", "DHSYEAR", "DHSCLUST",
                        "LATNUM", "LONGNUM", "URBAN_RURA",
                        "ALT_GPS", "ALT_DEM", "DATUM"))) %>%
      filter(!is.na(LATNUM) & LATNUM != 0 & !is.na(LONGNUM) & LONGNUM != 0)

    # If DHSCC/DHSYEAR not in shapefile, extract from filename
    if (!"DHSCC" %in% names(geo_out)) {
      geo_out$DHSCC <- substr(basename(shp_path), 1, 2)
    }

    # Extract survey year from DHSID if DHSYEAR is missing
    if (!"DHSYEAR" %in% names(geo_out) && "DHSID" %in% names(geo_out)) {
      # DHSID format: e.g., "AO201500000001" -> year = chars 3-6
      geo_out$DHSYEAR <- as.integer(substr(geo_out$DHSID, 3, 6))
    }

    # Also extract surv_id from the GE filename mapping
    # Filename pattern: XXGE##FL.shp where XX = country code
    ge_filename <- tools::file_path_sans_ext(basename(shp_path))
    geo_out$ge_source_file <- ge_filename

    all_geo[[length(all_geo) + 1]] <- geo_out

    cat(glue("  {ge_filename}: {nrow(geo_out)} clusters"))
    if ("DHSYEAR" %in% names(geo_out)) {
      years <- unique(geo_out$DHSYEAR)
      cat(glue(" (year: {paste(years, collapse='/')})"))
    }
    cat("\n")
  }, error = function(e) {
    cat(glue("  ERROR reading {basename(shp_path)}: {e$message}\n"))
  })
}

if (length(all_geo) == 0) {
  stop("No valid geographic data loaded from shapefiles.")
}

# Combine all GPS data
gps_combined <- bind_rows(all_geo)
cat(glue("\nCombined GPS records: {nrow(gps_combined)}\n"))
cat(glue("Countries with GPS: {n_distinct(gps_combined$DHSCC)}\n"))

# Build a unique survey key for matching
# DHS survey_id format: XX####DHS (e.g., AO2015DHS)
# Build this from DHSCC + DHSYEAR
if ("DHSYEAR" %in% names(gps_combined)) {
  gps_combined$survey_key <- paste0(gps_combined$DHSCC, gps_combined$DHSYEAR, "DHS")
} else {
  # Fallback: just use country code (less precise)
  gps_combined$survey_key <- paste0(gps_combined$DHSCC, "XXXX", "DHS")
}

cat(glue("Unique survey keys: {n_distinct(gps_combined$survey_key)}\n"))
cat(glue("Unique survey-cluster pairs: {nrow(distinct(gps_combined, survey_key, DHSCLUST))}\n\n"))

# Deduplicate: keep one GPS per survey+cluster
gps_lookup <- gps_combined %>%
  distinct(survey_key, DHSCLUST, .keep_all = TRUE) %>%
  select(survey_key, DHSCLUST, LATNUM, LONGNUM,
         any_of(c("URBAN_RURA", "ALT_DEM", "DHSCC", "DHSYEAR", "ge_source_file")))

cat(glue("GPS lookup table: {nrow(gps_lookup)} unique survey-cluster pairs\n"))

# Save GPS lookup table
gps_lookup_path <- file.path(dirs$geo_base, "dhs_gps_lookup.rds")
saveRDS(gps_lookup, gps_lookup_path)
cat(glue("Saved: {gps_lookup_path}\n\n"))

# Show GPS coverage by country
cat("GPS clusters by country:\n")
country_clusters <- gps_lookup %>%
  group_by(DHSCC) %>%
  summarise(
    n_surveys = n_distinct(survey_key),
    n_clusters = n(),
    surveys = paste(unique(survey_key), collapse = ", "),
    .groups = "drop"
  ) %>%
  arrange(DHSCC)
print(country_clusters, n = 50)
cat("\n")

# ============================================================================
# STEP 5: LOAD MERGED DATASET v10.15
# ============================================================================
cat("============================================================\n")
cat("  STEP 5: Load merged unified dataset v10.15\n")
cat("============================================================\n\n")

input_path <- file.path(dirs$output, "merged_unified_dataset_v10.15.rds")
if (!file.exists(input_path)) {
  stop(glue("Cannot find: {input_path}\nRun the unified dataset pipeline first."))
}

df <- readRDS(input_path)
cat(glue("Loaded: {format(nrow(df), big.mark=',')} rows x {ncol(df)} columns\n"))
cat(glue("Studies: {paste(unique(df$study_source), collapse = ', ')}\n\n"))

# Show current coordinate status
cat("Current coordinate columns:\n")
for (col in c("loc_latitude", "loc_longitude", "env_latitude", "env_longitude")) {
  if (col %in% names(df)) {
    n_ok <- sum(!is.na(df[[col]]))
    cat(glue("  {col}: {format(n_ok, big.mark=',')} / {format(nrow(df), big.mark=',')} non-NA ({round(100*n_ok/nrow(df),1)}%)\n"))
  } else {
    cat(glue("  {col}: DOES NOT EXIST\n"))
  }
}
cat("\n")

# ============================================================================
# STEP 6: LINK GPS TO DHS RECORDS
# ============================================================================
cat("============================================================\n")
cat("  STEP 6: Link GPS coordinates to DHS records\n")
cat("============================================================\n\n")

# Identify DHS records
is_dhs <- df$study_source == "DHS"
n_dhs <- sum(is_dhs, na.rm = TRUE)
cat(glue("DHS records: {format(n_dhs, big.mark=',')}\n"))

if (n_dhs == 0) {
  stop("No DHS records found in dataset!")
}

# Extract matching keys from DHS records
# dhs_survey_id format: AO2015DHS (same as survey_key in GPS lookup)
dhs_subset <- df[is_dhs, ]

cat(glue("Unique DHS surveys in dataset: {n_distinct(dhs_subset$dhs_survey_id)}\n"))
cat(glue("Unique DHS clusters in dataset: {n_distinct(paste0(dhs_subset$dhs_survey_id, '_', dhs_subset$dhs_cluster))}\n\n"))

# Join GPS data to DHS records
# Match on: dhs_survey_id = survey_key AND dhs_cluster = DHSCLUST
gps_for_join <- gps_lookup %>%
  select(survey_key, DHSCLUST, LATNUM, LONGNUM,
         any_of(c("URBAN_RURA", "ALT_DEM"))) %>%
  rename(
    gps_latitude  = LATNUM,
    gps_longitude = LONGNUM
  )

# First attempt: exact match on survey_key + cluster
dhs_matched <- dhs_subset %>%
  left_join(
    gps_for_join,
    by = c("dhs_survey_id" = "survey_key", "dhs_cluster" = "DHSCLUST")
  )

n_exact <- sum(!is.na(dhs_matched$gps_latitude))
cat(glue("Exact match (survey+cluster): {format(n_exact, big.mark=',')} / {format(n_dhs, big.mark=',')} ({round(100*n_exact/n_dhs,1)}%)\n"))

# For unmatched records, try matching just by country + cluster
# (some surveys might have year discrepancies between dataset and shapefile)
if (n_exact < n_dhs) {
  n_unmatched <- n_dhs - n_exact
  cat(glue("\nAttempting fuzzy match for {format(n_unmatched, big.mark=',')} unmatched records...\n"))

  # Show which surveys have no GPS match
  unmatched_surveys <- dhs_matched %>%
    filter(is.na(gps_latitude)) %>%
    count(dhs_survey_id, name = "n_unmatched") %>%
    arrange(desc(n_unmatched))
  cat("Unmatched surveys:\n")
  print(unmatched_surveys, n = 40)
  cat("\n")

  # Available GPS surveys
  available_surveys <- unique(gps_lookup$survey_key)

  # Try matching by country code + cluster (when no exact survey match)
  # Extract country code from survey ID
  unmatched_idx <- which(is_dhs)[is.na(dhs_matched$gps_latitude)]

  if (length(unmatched_idx) > 0) {
    # Build a country-level GPS fallback (for surveys without GE files)
    gps_by_country_cluster <- gps_lookup %>%
      group_by(DHSCC, DHSCLUST) %>%
      # If multiple surveys have the same country+cluster, use the most recent
      arrange(desc(survey_key)) %>%
      slice(1) %>%
      ungroup() %>%
      select(DHSCC, DHSCLUST, LATNUM, LONGNUM)

    # Get country code from unmatched records
    df_unmatched <- df[unmatched_idx, ] %>%
      mutate(.cc = substr(dhs_survey_id, 1, 2))

    df_unmatched <- df_unmatched %>%
      left_join(gps_by_country_cluster,
                by = c(".cc" = "DHSCC", "dhs_cluster" = "DHSCLUST"))

    n_fuzzy <- sum(!is.na(df_unmatched$LATNUM))
    cat(glue("Fuzzy match (country+cluster): {format(n_fuzzy, big.mark=',')} additional matches\n"))

    # Update the matched results
    fuzzy_matched_idx <- unmatched_idx[!is.na(df_unmatched$LATNUM)]
    if (length(fuzzy_matched_idx) > 0) {
      dhs_matched$gps_latitude[is.na(dhs_matched$gps_latitude)][!is.na(df_unmatched$LATNUM)] <- df_unmatched$LATNUM[!is.na(df_unmatched$LATNUM)]
      dhs_matched$gps_longitude[is.na(dhs_matched$gps_longitude)][!is.na(df_unmatched$LATNUM)] <- df_unmatched$LONGNUM[!is.na(df_unmatched$LATNUM)]
    }

    n_total_matched <- sum(!is.na(dhs_matched$gps_latitude))
    n_still_unmatched <- n_dhs - n_total_matched
    cat(glue("\nTotal GPS-matched DHS records: {format(n_total_matched, big.mark=',')} / {format(n_dhs, big.mark=',')} ({round(100*n_total_matched/n_dhs,1)}%)\n"))
    cat(glue("Still unmatched: {format(n_still_unmatched, big.mark=',')}\n"))

    if (n_still_unmatched > 0) {
      cat("\nSurveys still without GPS (no GE file available):\n")
      still_unmatched <- dhs_matched %>%
        filter(is.na(gps_latitude)) %>%
        count(dhs_survey_id, name = "n_records") %>%
        arrange(desc(n_records))
      print(still_unmatched, n = 30)
    }
  }
}
cat("\n")

# ============================================================================
# STEP 7: UPDATE COORDINATES IN MERGED DATASET
# ============================================================================
cat("============================================================\n")
cat("  STEP 7: Update coordinates in merged dataset\n")
cat("============================================================\n\n")

# Ensure coordinate columns exist
if (!"env_latitude" %in% names(df))  df$env_latitude  <- NA_real_
if (!"env_longitude" %in% names(df)) df$env_longitude <- NA_real_
if (!"loc_latitude" %in% names(df))  df$loc_latitude  <- NA_real_
if (!"loc_longitude" %in% names(df)) df$loc_longitude <- NA_real_

# Update DHS records with GPS coordinates
dhs_rows <- which(is_dhs)
df$env_latitude[dhs_rows]  <- dhs_matched$gps_latitude
df$env_longitude[dhs_rows] <- dhs_matched$gps_longitude
df$loc_latitude[dhs_rows]  <- dhs_matched$gps_latitude
df$loc_longitude[dhs_rows] <- dhs_matched$gps_longitude

# Also update geo_urban_rural from GE if available
if ("URBAN_RURA" %in% names(dhs_matched)) {
  # Only update if mat_urban_rural is NA
  has_ge_urban <- !is.na(dhs_matched$URBAN_RURA)
  has_no_urban <- is.na(df$mat_urban_rural[dhs_rows])
  update_urban <- has_ge_urban & has_no_urban
  if (any(update_urban, na.rm = TRUE)) {
    df$mat_urban_rural[dhs_rows[update_urban]] <- dhs_matched$URBAN_RURA[update_urban]
    cat(glue("Updated mat_urban_rural for {sum(update_urban)} records from GE data\n"))
  }
}

# Show coordinate coverage
cat("\nCoordinate coverage after GPS linkage:\n")
coord_summary <- df %>%
  group_by(study_source) %>%
  summarise(
    n = n(),
    n_gps = sum(!is.na(loc_latitude)),
    pct_gps = round(100 * mean(!is.na(loc_latitude)), 1),
    .groups = "drop"
  )
print(coord_summary)
cat("\n")

# Show GPS coverage by country (DHS only)
cat("DHS GPS coverage by country:\n")
dhs_country_gps <- df %>%
  filter(study_source == "DHS") %>%
  group_by(mat_country) %>%
  summarise(
    n = n(),
    n_gps = sum(!is.na(loc_latitude)),
    pct_gps = round(100 * mean(!is.na(loc_latitude)), 1),
    .groups = "drop"
  ) %>%
  arrange(desc(n))
print(dhs_country_gps, n = 50)
cat("\n")

# ============================================================================
# STEP 8: SAVE AS v10.16
# ============================================================================
cat("============================================================\n")
cat("  STEP 8: Save as merged_unified_dataset_v10.16\n")
cat("============================================================\n\n")

MERGED_VERSION <- "10.16"

# Regenerate unified_id (same formula as workaround - preserves ID consistency)
df$unified_id <- paste0(df$study_source, "_", seq_len(nrow(df)))

# Save RDS
rds_path <- file.path(dirs$output, paste0("merged_unified_dataset_v", MERGED_VERSION, ".rds"))
saveRDS(df, rds_path)
cat(glue("Saved: {basename(rds_path)} ({round(file.info(rds_path)$size / 1024^2, 1)} MB)\n"))

# Save CSV
csv_path <- file.path(dirs$output, paste0("merged_unified_dataset_v", MERGED_VERSION, ".csv"))
write_csv(df, csv_path)
cat(glue("Saved: {basename(csv_path)} ({round(file.info(csv_path)$size / 1024^2, 1)} MB)\n"))

# Save Stata .dta
df_stata <- df
long_names <- names(df_stata)[nchar(names(df_stata)) > 32]
if (length(long_names) > 0) {
  names(df_stata)[nchar(names(df_stata)) > 32] <- substr(
    names(df_stata)[nchar(names(df_stata)) > 32], 1, 32)
  names(df_stata) <- make.unique(names(df_stata), sep = "_")
}
dta_path <- file.path(dirs$output, paste0("merged_unified_dataset_v", MERGED_VERSION, ".dta"))
haven::write_dta(df_stata, dta_path, version = 14)
cat(glue("Saved: {basename(dta_path)} ({round(file.info(dta_path)$size / 1024^2, 1)} MB)\n"))
rm(df_stata)

# 10% sample
set.seed(42)
df_sample <- df %>%
  group_by(study_source) %>%
  sample_frac(0.1) %>%
  ungroup()
sample_path <- file.path(dirs$output, paste0("merged_unified_10pct_sample_v", MERGED_VERSION, ".rds"))
saveRDS(df_sample, sample_path)
cat(glue("Saved: {basename(sample_path)} ({format(nrow(df_sample), big.mark=',')} records)\n\n"))
rm(df_sample)

# ============================================================================
# STEP 9: VERIFY UNIFIED_ID COMPATIBILITY WITH ENV LINKAGE v3.3
# ============================================================================
cat("============================================================\n")
cat("  STEP 9: Verify unified_id compatibility with env linkage\n")
cat("============================================================\n\n")

env_path <- file.path(dirs$output, "environmental", "environmental_linkage_v3.3.rds")
if (file.exists(env_path)) {
  env_ids <- readRDS(env_path)$unified_id
  dataset_ids <- df$unified_id

  n_env <- length(unique(env_ids))
  n_match <- length(intersect(unique(env_ids), unique(dataset_ids)))

  cat(glue("Environmental linkage v3.3: {format(n_env, big.mark=',')} unique IDs\n"))
  cat(glue("New v10.16 dataset: {format(length(unique(dataset_ids)), big.mark=',')} unique IDs\n"))
  cat(glue("IDs matching: {format(n_match, big.mark=',')} / {format(n_env, big.mark=',')} ({round(100*n_match/n_env,1)}%)\n"))

  if (n_match == n_env) {
    cat("PASS: All environmental linkage IDs match the new dataset.\n")
  } else {
    n_missing <- n_env - n_match
    cat(glue("WARNING: {format(n_missing, big.mark=',')} env linkage IDs do not match!\n"))
    cat("The environmental data join may lose some records.\n")
  }
} else {
  cat(glue("Environmental linkage not found at: {env_path}\n"))
  cat("Will need to run the environmental pipeline before creating v10.17.\n")
}
cat("\n")

# ============================================================================
# SUMMARY
# ============================================================================
cat("============================================================\n")
cat("  DOWNLOAD AND LINKAGE COMPLETE\n")
cat("============================================================\n\n")

cat(glue("Dataset v{MERGED_VERSION} with real GPS:\n"))
cat(glue("  Records:   {format(nrow(df), big.mark=',')}\n"))
cat(glue("  Variables: {ncol(df)}\n"))
cat(glue("  Studies:   {paste(unique(df$study_source), collapse = ', ')}\n"))
cat(glue("  Countries: {n_distinct(df$mat_country, na.rm = TRUE)}\n\n"))

n_with_gps <- sum(!is.na(df$loc_latitude))
n_dhs_gps  <- sum(!is.na(df$loc_latitude) & df$study_source == "DHS")
cat(glue("GPS coverage:\n"))
cat(glue("  Total:     {format(n_with_gps, big.mark=',')} / {format(nrow(df), big.mark=',')} ({round(100*n_with_gps/nrow(df),1)}%)\n"))
cat(glue("  DHS only:  {format(n_dhs_gps, big.mark=',')} / {format(n_dhs, big.mark=',')} ({round(100*n_dhs_gps/n_dhs,1)}%)\n\n"))

cat("Records by study:\n")
print(df %>% count(study_source, name = "n_records"))
cat("\n")

cat("NEXT STEPS:\n")
cat("  1. Run join_env_to_unified.R (join environmental linkage v3.3)\n")
cat("  2. Run clean_unified_dataset_v10.15.qmd (clean/standardise)\n")
cat("  3. Run create_v10.17_clean.R (create final v10.17)\n\n")

cat("NOTE: Environmental data was extracted at country-centroid resolution\n")
cat("      (from the workaround run). The GPS coordinates are now real\n")
cat("      cluster-level, but env variables remain at centroid resolution.\n")
cat("      To get cluster-level env data, re-run the environmental pipeline.\n")

rm(df)
gc()
