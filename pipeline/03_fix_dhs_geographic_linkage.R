# ============================================================================
# FIX: DHS Geographic Linkage (Standalone)
# ============================================================================
# PURPOSE:
#   The original DHS Pipeline v7.1 had a bug in the dataset query (Step 3):
#   FileFormat == "Stata dataset (.dta)" excluded Geographic Data files because
#   GE shapefiles are NOT in Stata format. This meant NO GPS coordinates were
#   ever downloaded for DHS records.
#
#   This standalone script fixes the problem WITHOUT re-running the 24-hour
#   Step 7 processing. It:
#     1. Downloads GE shapefiles from DHS API (using rdhs)
#     2. Loads the existing dhs_unified_dataset.rds (already processed)
#     3. Links GPS coordinates from GE files to DHS records
#     4. Also stores coordinates as loc_latitude/loc_longitude (for env pipeline)
#     5. Re-merges with the 6-study unified dataset → v10.16
#
# RUNTIME: ~15-30 minutes (mostly download time)
# ============================================================================

cat("============================================================\n")
cat("  FIX: DHS Geographic Linkage (Standalone)\n")
cat("============================================================\n\n")

# --- Load packages ---
suppressPackageStartupMessages({
  library(rdhs)
  library(tidyverse)
  library(sf)
  library(haven)
  library(glue)
  library(jsonlite)
})

# --- Directory setup ---
# Set dropbox_base to your local unified_dataset_pipeline directory.
# By default, assumes the script is run from the project root.
dropbox_base <- getwd()
# Uncomment and edit below if running from a different working directory:
# dropbox_base <- "C:/Users/YOUR_USERNAME/path/to/unified_dataset_pipeline"

dirs <- list(
  pipeline     = dropbox_base,
  dhs_cache    = file.path(dropbox_base, "data", "dhs", "cache"),
  dhs_geo      = file.path(dropbox_base, "data", "dhs", "geographic"),
  dhs_output   = file.path(dropbox_base, "outputs", "dhs"),
  output       = file.path(dropbox_base, "output")
)

dir.create(dirs$dhs_geo, recursive = TRUE, showWarnings = FALSE)

cat("Directories:\n")
cat(glue("  Pipeline:    {dirs$pipeline}\n"))
cat(glue("  DHS cache:   {dirs$dhs_cache}\n"))
cat(glue("  DHS geo:     {dirs$dhs_geo}\n"))
cat(glue("  DHS output:  {dirs$dhs_output}\n"))
cat(glue("  Main output: {dirs$output}\n\n"))

# --- Configure rdhs credentials (read from existing config file) ---
rdhs_config_file <- file.path(dropbox_base, "data", "dhs", "rdhs.json")
cat(glue("Setting rdhs config from: {rdhs_config_file}\n"))
existing_config <- jsonlite::fromJSON(rdhs_config_file)
set_rdhs_config(
  email = existing_config$email,
  project = existing_config$project,
  password = existing_config$password,
  config_path = rdhs_config_file,
  cache_path = dirs$dhs_cache,
  global = FALSE,
  verbose_download = TRUE,
  prompt = FALSE
)
cat("rdhs credentials configured.\n\n")

# ============================================================================
# STEP 1: QUERY AND DOWNLOAD GE FILES
# ============================================================================
cat("============================================================\n")
cat("  STEP 1: Download GE shapefiles from DHS API\n")
cat("============================================================\n\n")

# SSA country codes (same as DHS Pipeline v7.1)
ssa_country_codes <- c(
  "AO", "BJ", "BF", "BU", "CM", "CV", "CF", "TD", "KM", "CD",
  "CG", "CI", "ER", "ET", "GA", "GM", "GH", "GN", "GU", "KE",
  "LS", "LB", "MD", "MW", "ML", "MR", "MZ", "NM", "NI", "NG",
  "RW", "ST", "SN", "SL", "ZA", "SD", "SZ", "TZ", "TG", "UG",
  "ZM", "ZW"
)

# Query for GE files specifically (no FileFormat filter!)
cat("Querying DHS API for Geographic Data files...\n")
all_datasets <- dhs_datasets()

ge_datasets <- all_datasets %>%
  filter(
    DHS_CountryCode %in% ssa_country_codes,
    SurveyType == "DHS",
    FileType == "Geographic Data"
  )

cat(glue("Found {nrow(ge_datasets)} GE datasets across {n_distinct(ge_datasets$DHS_CountryCode)} countries\n"))
cat(glue("File formats: {paste(unique(ge_datasets$FileFormat), collapse = ', ')}\n\n"))

# Load the complete surveys list to filter to surveys we actually processed
complete_surveys_path <- file.path(dropbox_base, "data", "dhs", "inventories", "dhs_complete_surveys.csv")
if (file.exists(complete_surveys_path)) {
  complete_surveys <- read.csv(complete_surveys_path)
  ge_to_download <- ge_datasets %>%
    filter(SurveyId %in% complete_surveys$SurveyId)
  cat(glue("Filtered to {nrow(ge_to_download)} GE files matching processed surveys\n\n"))
} else {
  ge_to_download <- ge_datasets
  cat("No complete_surveys.csv found - downloading all available GE files\n\n")
}

if (nrow(ge_to_download) == 0) {
  stop("No GE files to download. Check your DHS API credentials and survey inventory.")
}

# Download GE files
cat(glue("Downloading {nrow(ge_to_download)} GE files...\n"))
cat("(rdhs caches downloads - re-running is safe)\n\n")

downloaded_ge <- tryCatch({
  get_datasets(ge_to_download$FileName)
}, error = function(e) {
  cat(glue("Download error: {e$message}\n"))
  cat("Trying individual downloads...\n\n")

  results <- list()
  for (i in 1:nrow(ge_to_download)) {
    fn <- ge_to_download$FileName[i]
    cat(glue("  [{i}/{nrow(ge_to_download)}] {fn}... "))
    tryCatch({
      r <- get_datasets(fn)
      results[[length(results) + 1]] <- r
      cat("OK\n")
    }, error = function(e2) {
      cat(glue("SKIP ({e2$message})\n"))
    })
  }
  unlist(results)
})

cat(glue("\nDownloaded {length(downloaded_ge)} GE files\n\n"))

# ============================================================================
# STEP 2: EXTRACT SHAPEFILES TO GEOGRAPHIC DIRECTORY
# ============================================================================
cat("============================================================\n")
cat("  STEP 2: Extract shapefiles to geographic directory\n")
cat("============================================================\n\n")

n_extracted <- 0

for (ge_path in downloaded_ge) {
  ge_path <- as.character(ge_path)
  if (!file.exists(ge_path)) next

  stem <- tools::file_path_sans_ext(basename(ge_path))
  cat(glue("  {stem}: "))

  tryCatch({
    # rdhs may return .rds files (it reads shapefiles and caches as RDS)
    if (grepl("\\.rds$", ge_path, ignore.case = TRUE)) {
      geo_data <- readRDS(ge_path)

      # Convert to sf if needed
      if (inherits(geo_data, "SpatialPointsDataFrame")) {
        geo_data <- st_as_sf(geo_data)
      }

      if (inherits(geo_data, "sf")) {
        shp_out <- file.path(dirs$dhs_geo, paste0(stem, ".shp"))
        st_write(geo_data, shp_out, delete_dsn = TRUE, quiet = TRUE)
        n_extracted <- n_extracted + 1
        cat(glue("extracted ({nrow(geo_data)} clusters)\n"))
      } else if (is.data.frame(geo_data)) {
        # Some GE files might be plain data frames
        shp_cols <- c("DHSCLUST", "LATNUM", "LONGNUM")
        if (all(shp_cols %in% names(geo_data))) {
          geo_sf <- st_as_sf(geo_data,
                             coords = c("LONGNUM", "LATNUM"),
                             crs = 4326)
          shp_out <- file.path(dirs$dhs_geo, paste0(stem, ".shp"))
          st_write(geo_sf, shp_out, delete_dsn = TRUE, quiet = TRUE)
          n_extracted <- n_extracted + 1
          cat(glue("converted to shp ({nrow(geo_data)} clusters)\n"))
        } else {
          cat("no coordinate columns found\n")
        }
      } else {
        cat(glue("unknown class: {class(geo_data)[1]}\n"))
      }
    } else if (grepl("\\.shp$", ge_path, ignore.case = TRUE)) {
      # Direct shapefile - copy all components
      shp_dir <- dirname(ge_path)
      shp_base <- tools::file_path_sans_ext(basename(ge_path))
      extensions <- c(".shp", ".shx", ".dbf", ".prj", ".cpg", ".sbn", ".sbx")
      for (ext in extensions) {
        src <- file.path(shp_dir, paste0(shp_base, ext))
        if (file.exists(src)) {
          file.copy(src, file.path(dirs$dhs_geo, basename(src)), overwrite = TRUE)
        }
      }
      n_extracted <- n_extracted + 1
      cat("copied\n")
    } else {
      cat(glue("unknown format: {tools::file_ext(ge_path)}\n"))
    }
  }, error = function(e) {
    cat(glue("ERROR: {e$message}\n"))
  })
}

cat(glue("\nExtracted {n_extracted} GE files to: {dirs$dhs_geo}\n"))

# Verify
shp_files <- list.files(dirs$dhs_geo, pattern = "\\.shp$", full.names = TRUE, recursive = TRUE)
cat(glue("Shapefiles in geographic directory: {length(shp_files)}\n\n"))

if (length(shp_files) == 0) {
  stop("No shapefiles extracted. Check DHS API credentials and download logs above.")
}

# ============================================================================
# STEP 3: LOAD EXISTING DHS UNIFIED DATASET
# ============================================================================
cat("============================================================\n")
cat("  STEP 3: Load existing DHS unified dataset\n")
cat("============================================================\n\n")

dhs_rds <- file.path(dirs$dhs_output, "dhs_unified_dataset.rds")
if (!file.exists(dhs_rds)) {
  stop(glue("Cannot find: {dhs_rds}\nRun the DHS pipeline Steps 7-9 first."))
}

dhs_unified <- readRDS(dhs_rds)
cat(glue("Loaded: {nrow(dhs_unified)} records x {ncol(dhs_unified)} columns\n"))
cat(glue("Countries: {n_distinct(dhs_unified$mat_country, na.rm = TRUE)}\n"))
cat(glue("Existing env_latitude coverage: {sum(!is.na(dhs_unified$env_latitude))} / {nrow(dhs_unified)}\n\n"))

# ============================================================================
# STEP 4: LINK GE SHAPEFILES TO DHS DATA
# ============================================================================
cat("============================================================\n")
cat("  STEP 4: Link GE coordinates to DHS records\n")
cat("============================================================\n\n")

# Read and combine all GE shapefiles (same logic as DHS Pipeline Step 8-9)
ge_files <- list.files(dirs$dhs_geo, pattern = "\\.shp$",
                       full.names = TRUE, recursive = TRUE)

all_geo <- list()

for (ge_path in ge_files) {
  tryCatch({
    geo <- st_read(ge_path, quiet = TRUE)

    geo_df <- geo %>%
      st_drop_geometry() %>%
      select(any_of(c("DHSCLUST", "LATNUM", "LONGNUM", "URBAN_RURA",
                       "DHSID", "DHSREGCO", "DHSREGNA", "ALT_GPS", "ALT_DEM"))) %>%
      rename_with(~case_when(
        . == "DHSCLUST"    ~ "dhs_cluster",
        . == "LATNUM"      ~ "env_latitude",
        . == "LONGNUM"     ~ "env_longitude",
        . == "URBAN_RURA"  ~ "geo_urban_rural",
        . == "ALT_DEM"     ~ "env_altitude_m",
        TRUE ~ .
      )) %>%
      mutate(
        ge_source_file = basename(ge_path),
        ge_country_code = substr(basename(ge_path), 1, 2)
      )

    if ("env_latitude" %in% names(geo_df)) {
      geo_df <- geo_df %>%
        filter(!is.na(env_latitude) & env_latitude != 0)
    }

    all_geo[[length(all_geo) + 1]] <- geo_df
    cat(glue("  {basename(ge_path)}: {nrow(geo_df)} clusters\n"))
  }, error = function(e) {
    cat(glue("  {basename(ge_path)}: ERROR - {e$message}\n"))
  })
}

if (length(all_geo) > 0) {
  geo_combined <- bind_rows(all_geo) %>%
    distinct(dhs_cluster, ge_country_code, .keep_all = TRUE)

  cat(glue("\nCombined: {nrow(geo_combined)} unique cluster-country pairs\n"))
  cat(glue("Countries with GPS: {n_distinct(geo_combined$ge_country_code)}\n\n"))

  # Remove old env_latitude/env_longitude columns if they exist (all NA from v7.1)
  if ("env_latitude" %in% names(dhs_unified)) {
    n_existing <- sum(!is.na(dhs_unified$env_latitude))
    cat(glue("Removing old env_latitude/longitude ({n_existing} non-NA values)\n"))
    dhs_unified$env_latitude <- NULL
    dhs_unified$env_longitude <- NULL
  }

  # Also remove other GE columns if they exist from previous run
  for (col in c("geo_urban_rural", "env_altitude_m", "ge_source_file", "ge_country_code")) {
    if (col %in% names(dhs_unified)) dhs_unified[[col]] <- NULL
  }

  # Link by cluster + country code
  dhs_unified <- dhs_unified %>%
    mutate(.ge_country_code = substr(dhs_survey_id, 1, 2)) %>%
    left_join(
      geo_combined,
      by = c("dhs_cluster" = "dhs_cluster", ".ge_country_code" = "ge_country_code")
    ) %>%
    select(-.ge_country_code)

  n_geo <- sum(!is.na(dhs_unified$env_latitude))
  cat(glue("Geographic data linked: {n_geo}/{nrow(dhs_unified)} records ({round(n_geo/nrow(dhs_unified)*100,1)}%)\n\n"))

  # Show coverage by country
  cat("--- Coverage by country ---\n")
  country_coverage <- dhs_unified %>%
    group_by(mat_country) %>%
    summarise(
      n = n(),
      n_gps = sum(!is.na(env_latitude)),
      pct = round(100 * mean(!is.na(env_latitude)), 1),
      .groups = "drop"
    ) %>%
    arrange(desc(n))
  print(country_coverage, n = 50)
  cat("\n")

} else {
  cat("WARNING: No valid geographic data loaded from shapefiles.\n")
  if (!"env_latitude" %in% names(dhs_unified)) dhs_unified$env_latitude <- NA_real_
  if (!"env_longitude" %in% names(dhs_unified)) dhs_unified$env_longitude <- NA_real_
}

# ============================================================================
# STEP 5: ADD loc_latitude/loc_longitude FOR ENVIRONMENTAL PIPELINE
# ============================================================================
cat("============================================================\n")
cat("  STEP 5: Copy coordinates to loc_latitude/loc_longitude\n")
cat("============================================================\n\n")

# The environmental pipeline reads loc_latitude/loc_longitude, not env_latitude/env_longitude
dhs_unified$loc_latitude <- dhs_unified$env_latitude
dhs_unified$loc_longitude <- dhs_unified$env_longitude

n_with_loc <- sum(!is.na(dhs_unified$loc_latitude))
cat(glue("Copied env_latitude/longitude -> loc_latitude/longitude ({n_with_loc} records)\n\n"))

# ============================================================================
# STEP 6: SAVE UPDATED DHS DATASET
# ============================================================================
cat("============================================================\n")
cat("  STEP 6: Save updated DHS dataset\n")
cat("============================================================\n\n")

# Save to DHS output directory
saveRDS(dhs_unified, file.path(dirs$dhs_output, "dhs_unified_dataset.rds"))
cat(glue("Saved: {file.path(dirs$dhs_output, 'dhs_unified_dataset.rds')}\n"))

write_csv(dhs_unified, file.path(dirs$dhs_output, "dhs_unified_dataset.csv"))
cat(glue("Saved: {file.path(dirs$dhs_output, 'dhs_unified_dataset.csv')}\n"))

# Stata
dhs_stata <- dhs_unified
long_names <- names(dhs_stata)[nchar(names(dhs_stata)) > 32]
if (length(long_names) > 0) {
  names(dhs_stata)[nchar(names(dhs_stata)) > 32] <- substr(
    names(dhs_stata)[nchar(names(dhs_stata)) > 32], 1, 32)
  names(dhs_stata) <- make.unique(names(dhs_stata), sep = "_")
}
haven::write_dta(dhs_stata, file.path(dirs$dhs_output, "dhs_unified_dataset.dta"), version = 14)
cat(glue("Saved: {file.path(dirs$dhs_output, 'dhs_unified_dataset.dta')}\n\n"))
rm(dhs_stata)

# ============================================================================
# STEP 7: MERGE WITH 6-STUDY UNIFIED DATASET -> v10.16
# ============================================================================
cat("============================================================\n")
cat("  STEP 7: Merge with 6-study dataset -> v10.16\n")
cat("============================================================\n\n")

MERGED_VERSION <- "10.16"

# Find the 6-study dataset
six_study_candidates <- c(
  file.path(dirs$output, "unified_dataset_v10.15.rds"),
  file.path(dirs$output, "unified_dataset_v10.14.rds"),
  file.path(dirs$output, "unified_dataset_v10.13.rds")
)

six_study_path <- NULL
for (p in six_study_candidates) {
  if (file.exists(p)) { six_study_path <- p; break }
}

if (is.null(six_study_path)) {
  # Recursive fallback
  recursive_hits <- list.files(
    path = dirs$output,
    pattern = "^unified_dataset_v10.*\\.rds$",
    recursive = TRUE, full.names = TRUE
  )
  # Exclude "merged_" and "with_env" files
  recursive_hits <- recursive_hits[!grepl("merged_|with_env", recursive_hits)]
  if (length(recursive_hits) > 0) {
    six_study_path <- sort(recursive_hits, decreasing = TRUE)[1]
  }
}

if (is.null(six_study_path)) {
  cat("WARNING: Cannot find 6-study unified dataset.\n")
  cat("Searched:\n")
  for (p in six_study_candidates) cat(glue("  {p}\n"))
  cat("\nSkipping merge. The updated DHS standalone files are saved above.\n")
  cat("You can manually run Step 10 of DHS_Pipeline_Complete_v7.2.Rmd.\n")

} else {
  cat(glue("Found 6-study dataset: {basename(six_study_path)}\n"))
  cat(glue("  Path: {six_study_path}\n"))
  cat(glue("  Size: {round(file.info(six_study_path)$size / 1024^2, 1)} MB\n\n"))

  six_study <- readRDS(six_study_path)
  cat(glue("Loaded: {nrow(six_study)} records, {ncol(six_study)} variables\n"))
  cat(glue("Studies: {paste(unique(six_study$study_source), collapse = ', ')}\n\n"))

  # Remove existing DHS rows (re-merge protection)
  if ("DHS" %in% unique(six_study$study_source)) {
    n_before <- nrow(six_study)
    six_study <- six_study %>% filter(study_source != "DHS")
    cat(glue("Removed {n_before - nrow(six_study)} existing DHS rows\n\n"))
  }

  # Align columns
  cols_6study_only <- setdiff(names(six_study), names(dhs_unified))
  cols_dhs_only    <- setdiff(names(dhs_unified), names(six_study))

  for (col in cols_6study_only) dhs_unified[[col]] <- NA
  for (col in cols_dhs_only)    six_study[[col]]    <- NA

  all_cols <- union(names(six_study), names(dhs_unified))
  six_study   <- six_study[, all_cols]
  dhs_unified <- dhs_unified[, all_cols]

  # Type alignment
  cat("Aligning column types...\n")
  common_types <- sapply(all_cols, function(col) {
    t6 <- class(six_study[[col]])[1]
    td <- class(dhs_unified[[col]])[1]
    if (t6 == td) return("match")
    if (t6 == "character" || td == "character") return("character")
    if (t6 %in% c("numeric", "integer") && td %in% c("numeric", "integer")) return("numeric")
    return("character")
  })

  cols_to_char <- names(common_types[common_types == "character"])
  cols_to_num  <- names(common_types[common_types == "numeric"])

  if (length(cols_to_char) > 0) {
    six_study   <- six_study   %>% mutate(across(all_of(cols_to_char), as.character))
    dhs_unified <- dhs_unified %>% mutate(across(all_of(cols_to_char), as.character))
  }
  if (length(cols_to_num) > 0) {
    six_study   <- six_study   %>% mutate(across(all_of(cols_to_num), as.numeric))
    dhs_unified <- dhs_unified %>% mutate(across(all_of(cols_to_num), as.numeric))
  }
  cat(glue("  Coerced {length(cols_to_char)} cols to character, {length(cols_to_num)} to numeric\n\n"))

  # Merge
  cat("Merging datasets...\n")
  merged <- bind_rows(six_study, dhs_unified)
  merged$unified_id <- paste0(merged$study_source, "_", seq_len(nrow(merged)))

  cat(glue("\n=== MERGED DATASET v{MERGED_VERSION} ===\n"))
  cat(glue("  Total records:   {format(nrow(merged), big.mark = ',')}\n"))
  cat(glue("  Total variables: {ncol(merged)}\n"))
  cat(glue("  Studies:         {paste(unique(merged$study_source), collapse = ', ')}\n\n"))

  cat("Records by study:\n")
  print(merged %>% count(study_source, name = "n_records"))
  cat(glue("\nCountries: {n_distinct(merged$mat_country, na.rm = TRUE)}\n"))
  cat(glue("With GPS:  {sum(!is.na(merged$env_latitude))}\n\n"))

  # Save merged outputs
  merged_rds <- file.path(dirs$output, paste0("merged_unified_dataset_v", MERGED_VERSION, ".rds"))
  saveRDS(merged, merged_rds)
  cat(glue("Saved: {basename(merged_rds)} ({round(file.info(merged_rds)$size / 1024^2, 1)} MB)\n"))

  merged_csv <- file.path(dirs$output, paste0("merged_unified_dataset_v", MERGED_VERSION, ".csv"))
  write_csv(merged, merged_csv)
  cat(glue("Saved: {basename(merged_csv)}\n"))

  # Stata
  merged_stata <- merged
  long_names <- names(merged_stata)[nchar(names(merged_stata)) > 32]
  if (length(long_names) > 0) {
    names(merged_stata)[nchar(names(merged_stata)) > 32] <- substr(
      names(merged_stata)[nchar(names(merged_stata)) > 32], 1, 32)
    names(merged_stata) <- make.unique(names(merged_stata), sep = "_")
  }
  merged_dta <- file.path(dirs$output, paste0("merged_unified_dataset_v", MERGED_VERSION, ".dta"))
  haven::write_dta(merged_stata, merged_dta, version = 14)
  cat(glue("Saved: {basename(merged_dta)}\n\n"))
  rm(merged_stata)

  # 10% sample
  set.seed(42)
  merged_sample <- merged %>%
    group_by(study_source) %>%
    sample_frac(0.1) %>%
    ungroup()
  saveRDS(merged_sample, file.path(dirs$output, paste0("merged_unified_10pct_sample_v", MERGED_VERSION, ".rds")))
  cat(glue("Saved: 10% sample ({nrow(merged_sample)} records)\n"))

  rm(six_study, merged, merged_sample)
  gc()
}

# ============================================================================
# DONE
# ============================================================================
cat("\n============================================================\n")
cat("  FIX COMPLETE\n")
cat("============================================================\n\n")
cat("Output files:\n")
cat(glue("  1. {dirs$dhs_output}/dhs_unified_dataset.rds (updated with GPS)\n"))
cat(glue("  2. {dirs$output}/merged_unified_dataset_v10.16.rds (merged 7-study)\n\n"))
cat("Next steps:\n")
cat("  1. Run integrated_environmental_pipeline_v3_3.Rmd\n")
cat("     (reads merged_unified_dataset_v10.16.rds, extracts env data)\n")
cat("  2. Run clean_unified_dataset_v10.15.qmd on the new output\n")
cat("     (update input path to unified_dataset_with_env_v10.16.rds)\n")
