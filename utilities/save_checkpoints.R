# ============================================================================
# SCRIPT 1: SAVE CHECKPOINTS FROM MEMORY — RUN THIS NOW
# ============================================================================
#
# PURPOSE: Captures whatever Step 7 left in your RStudio memory, saves it to
#          disk as checkpoint files, links geographic data, and re-exports
#          everything (RDS, CSV, DTA) with geographic data included.
#
# HOW TO RUN:
#   In RStudio console, type:
#     source("C:/Users/eidejwai/Dropbox/Predictive Models for SB and NND/Minimalist/unified_dataset_pipeline/1_SAVE_CHECKPOINTS_NOW.R")
#
#   OR if on your personal laptop:
#     source("C:/Users/josep/Dropbox/Predictive Models for SB and NND/Minimalist/unified_dataset_pipeline/1_SAVE_CHECKPOINTS_NOW.R")
#
# WHAT IT DOES:
#   1. Detects what Step 7 objects are in your current R session memory
#   2. Saves them as checkpoint files to Dropbox (so Step 7 never reruns)
#   3. Links geographic data from GE shapefiles
#   4. Re-exports dhs_unified_dataset as RDS, CSV, and DTA — all with geo data
#   5. Copies to OneDrive as backup
#
# AFTER RUNNING THIS:
#   - You can safely close RStudio / Positron
#   - Checkpoints are saved to disk — Step 7 will never need 10 hours again
#   - Your updated pipeline (.Rmd file 2) will find these checkpoints automatically
#
# ============================================================================

cat("\n")
cat(strrep("=", 70), "\n")
cat("  SAVING CHECKPOINTS FROM MEMORY + RE-EXPORTING WITH GEOGRAPHIC DATA\n")
cat(strrep("=", 70), "\n\n")

# --- Load required packages ---
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(glue)
  library(haven)
})

# ============================================================================
# PART 1: SET UP DIRECTORIES
# ============================================================================

user <- Sys.info()[["user"]]
cat(glue("Detected user: {user}\n\n"))

# --- CONFIGURATION: Set your local paths below ---
if (user == "josep") {
  dropbox_base <- "C:/Users/josep/Dropbox/Predictive Models for SB and NND/Minimalist/unified_dataset_pipeline"
  onedrive_data <- "C:/Users/josep/OneDrive - London School of Hygiene and Tropical Medicine/LSHTM Grants and Consultancies/Wellcome_Accelerator grant_minorities/Datasets"
} else if (user == "eidejwai") {
  dropbox_base <- "C:/Users/eidejwai/Dropbox/Predictive Models for SB and NND/Minimalist/unified_dataset_pipeline"
  onedrive_data <- "C:/Users/eidejwai/OneDrive - London School of Hygiene and Tropical Medicine/LSHTM Grants and Consultancies/Wellcome_Accelerator grant_minorities/Datasets"
} else {
  dropbox_base <- getwd()
  onedrive_data <- NULL
  cat("NOTE: Unknown user. Using working directory as project root.\n")
  cat("      Set dropbox_base manually if paths do not resolve.\n")
}

# Key directories
dhs_checkpts <- file.path(dropbox_base, "data", "dhs", "checkpoints")
dhs_geo      <- file.path(dropbox_base, "data", "dhs", "geographic")
dhs_logs     <- file.path(dropbox_base, "data", "dhs", "processing_logs")
output_dropbox  <- file.path(dropbox_base, "output")
output_onedrive <- file.path(onedrive_data, "master", "Unified Dataset")

# Create directories that don't exist yet
for (d in c(dhs_checkpts, dhs_logs, output_dropbox)) {
  if (!dir.exists(d)) {
    dir.create(d, recursive = TRUE)
    cat(glue("  Created: {d}\n"))
  }
}

# ============================================================================
# PART 2: DETECT WHAT'S IN MEMORY
# ============================================================================

cat("--- Checking what Step 7 left in memory ---\n")

# Check for each possible object from Step 7
has_all_br     <- exists("all_br_processed")
has_all_sb     <- exists("all_stillbirths")
has_proc_log   <- exists("processing_log")
has_livebirths <- exists("dhs_livebirths")
has_stillbirths <- exists("dhs_stillbirths")
has_unified    <- exists("dhs_unified")
has_log_df     <- exists("log_df")

cat(glue("  all_br_processed:  {if(has_all_br) 'FOUND' else 'not found'}\n"))
cat(glue("  all_stillbirths:   {if(has_all_sb) 'FOUND' else 'not found'}\n"))
cat(glue("  processing_log:    {if(has_proc_log) 'FOUND' else 'not found'}\n"))
cat(glue("  dhs_livebirths:    {if(has_livebirths) 'FOUND' else 'not found'}\n"))
cat(glue("  dhs_stillbirths:   {if(has_stillbirths) 'FOUND' else 'not found'}\n"))
cat(glue("  dhs_unified:       {if(has_unified) 'FOUND' else 'not found'}\n"))
cat(glue("  log_df:            {if(has_log_df) 'FOUND' else 'not found'}\n\n"))

# We need at least ONE of these combinations to proceed
if (!has_all_br && !has_livebirths && !has_unified) {
  stop(paste(
    "\n!! NOTHING FOUND IN MEMORY !!\n",
    "None of the Step 7 objects exist in your R session.\n",
    "This means either:\n",
    "  - You already closed and reopened RStudio (data is gone)\n",
    "  - Step 7 used different variable names\n\n",
    "Check your Environment pane in RStudio. What large dataframes do you see?\n",
    "If you see the data under different names, let me know and I'll update this script."
  ))
}


# ============================================================================
# PART 3: SAVE CHECKPOINTS TO DISK
# ============================================================================

cat("--- Saving checkpoints to disk ---\n")
cat(glue("  Checkpoint directory: {dhs_checkpts}\n\n"))

# --- SCENARIO A: We have the per-survey lists (best case) ---
if (has_all_br && has_all_sb && has_proc_log) {
  
  cat("  Using per-survey lists (all_br_processed, all_stillbirths, processing_log)\n")
  saveRDS(all_br_processed, file.path(dhs_checkpts, "all_br_processed.rds"))
  saveRDS(all_stillbirths,  file.path(dhs_checkpts, "all_stillbirths.rds"))
  saveRDS(processing_log,   file.path(dhs_checkpts, "processing_log.rds"))
  
  cat(glue("  Saved: all_br_processed.rds ({length(all_br_processed)} surveys)\n"))
  cat(glue("  Saved: all_stillbirths.rds ({length(all_stillbirths)} surveys)\n"))
  cat(glue("  Saved: processing_log.rds\n\n"))
  
  # Also make sure the combined versions exist for Part 4
  if (!has_livebirths)  dhs_livebirths  <- bind_rows(all_br_processed)
  if (!has_stillbirths) dhs_stillbirths <- bind_rows(all_stillbirths)
  if (!has_log_df)      log_df          <- bind_rows(processing_log)

# --- SCENARIO B: We have the combined dataframes but not the lists ---
} else if (has_livebirths && has_stillbirths) {
  
  cat("  Using combined dataframes (dhs_livebirths, dhs_stillbirths)\n")
  cat("  Will split by survey to create per-survey checkpoint format.\n")
  
  # Split back into per-survey lists
  if ("dhs_survey_id" %in% names(dhs_livebirths)) {
    all_br_processed <- split(dhs_livebirths, dhs_livebirths$dhs_survey_id)
  } else {
    all_br_processed <- list(all = dhs_livebirths)
  }
  
  if ("dhs_survey_id" %in% names(dhs_stillbirths) && nrow(dhs_stillbirths) > 0) {
    all_stillbirths <- split(dhs_stillbirths, dhs_stillbirths$dhs_survey_id)
  } else {
    all_stillbirths <- list()
  }
  
  # Build a processing log from the data
  all_surveys <- unique(c(names(all_br_processed), names(all_stillbirths)))
  processing_log <- lapply(all_surveys, function(sid) {
    lb_n <- if (!is.null(all_br_processed[[sid]])) nrow(all_br_processed[[sid]]) else 0
    sb_n <- if (!is.null(all_stillbirths[[sid]])) nrow(all_stillbirths[[sid]]) else 0
    
    # Try to get country from the data
    country_val <- NA_character_
    year_val <- NA_character_
    if (lb_n > 0 && "mat_country" %in% names(all_br_processed[[sid]])) {
      country_val <- all_br_processed[[sid]]$mat_country[1]
    }
    if (lb_n > 0 && "studyyear" %in% names(all_br_processed[[sid]])) {
      year_val <- all_br_processed[[sid]]$studyyear[1]
    }
    
    list(
      survey_id = sid, country = country_val, year = year_val,
      status = "success", module = "bootstrapped", sb_method = "bootstrapped",
      n_births = lb_n, n_stillbirths = sb_n
    )
  })
  names(processing_log) <- all_surveys
  
  saveRDS(all_br_processed, file.path(dhs_checkpts, "all_br_processed.rds"))
  saveRDS(all_stillbirths,  file.path(dhs_checkpts, "all_stillbirths.rds"))
  saveRDS(processing_log,   file.path(dhs_checkpts, "processing_log.rds"))
  
  cat(glue("  Saved: all_br_processed.rds ({length(all_br_processed)} surveys)\n"))
  cat(glue("  Saved: all_stillbirths.rds ({length(all_stillbirths)} entries)\n"))
  cat(glue("  Saved: processing_log.rds\n\n"))
  
  if (!has_log_df) log_df <- bind_rows(processing_log)

# --- SCENARIO C: We only have the final unified dataset ---
} else if (has_unified) {
  
  cat("  Using dhs_unified (final combined dataset)\n")
  cat("  Will split into livebirths/stillbirths to create checkpoints.\n")
  
  dhs_livebirths <- dhs_unified %>%
    filter(
      (out_livebirth == "Yes") |
      (is.na(out_stillbirth) | out_stillbirth != "Yes")
    )
  
  dhs_stillbirths <- dhs_unified %>%
    filter(out_stillbirth == "Yes")
  
  # Split by survey
  if ("dhs_survey_id" %in% names(dhs_livebirths)) {
    all_br_processed <- split(dhs_livebirths, dhs_livebirths$dhs_survey_id)
    all_stillbirths  <- if (nrow(dhs_stillbirths) > 0) {
      split(dhs_stillbirths, dhs_stillbirths$dhs_survey_id)
    } else { list() }
  } else {
    all_br_processed <- list(all = dhs_livebirths)
    all_stillbirths  <- list(all = dhs_stillbirths)
  }
  
  # Build processing log
  all_surveys <- unique(c(names(all_br_processed), names(all_stillbirths)))
  processing_log <- lapply(all_surveys, function(sid) {
    list(
      survey_id = sid, country = NA, year = NA,
      status = "success", module = "bootstrapped", sb_method = "bootstrapped",
      n_births = if(!is.null(all_br_processed[[sid]])) nrow(all_br_processed[[sid]]) else 0,
      n_stillbirths = if(!is.null(all_stillbirths[[sid]])) nrow(all_stillbirths[[sid]]) else 0
    )
  })
  names(processing_log) <- all_surveys
  
  saveRDS(all_br_processed, file.path(dhs_checkpts, "all_br_processed.rds"))
  saveRDS(all_stillbirths,  file.path(dhs_checkpts, "all_stillbirths.rds"))
  saveRDS(processing_log,   file.path(dhs_checkpts, "processing_log.rds"))
  
  cat(glue("  Saved: all_br_processed.rds ({length(all_br_processed)} surveys)\n"))
  cat(glue("  Saved: all_stillbirths.rds ({length(all_stillbirths)} entries)\n"))
  cat(glue("  Saved: processing_log.rds\n\n"))
  
  log_df <- bind_rows(processing_log)
}

cat("  >> CHECKPOINTS SAVED. Step 7 will never need 10 hours again. <<\n\n")


# ============================================================================
# PART 4: COMBINE + LINK GEOGRAPHIC DATA + SAVE EVERYTHING
# ============================================================================

cat("--- Combining and linking geographic data ---\n")

# Build dhs_unified if not already in memory
if (!has_unified) {
  # Align columns
  missing_in_sb <- setdiff(names(dhs_livebirths), names(dhs_stillbirths))
  missing_in_lb <- setdiff(names(dhs_stillbirths), names(dhs_livebirths))
  for (col in missing_in_sb) dhs_stillbirths[[col]] <- NA
  for (col in missing_in_lb) dhs_livebirths[[col]] <- NA
  
  dhs_unified <- bind_rows(dhs_livebirths, dhs_stillbirths)
}

# Add perinatal death and IDs if not present
if (!"unified_id" %in% names(dhs_unified)) {
  dhs_unified$unified_id <- paste0("DHS_", seq_len(nrow(dhs_unified)))
}
if (!"out_perinatal_death" %in% names(dhs_unified)) {
  dhs_unified <- dhs_unified %>%
    mutate(
      out_perinatal_death = case_when(
        out_stillbirth_28wks == "Yes" | out_nnd_early == "Yes" ~ "Yes",
        out_stillbirth_28wks == "No" & (out_nnd_early == "No" | is.na(out_nnd_early)) ~ "No",
        TRUE ~ NA_character_
      )
    )
}

cat(glue("  Combined dataset: {nrow(dhs_unified)} records\n"))
cat(glue("  Live births: {sum(dhs_unified$out_livebirth == 'Yes', na.rm=TRUE)}\n"))
cat(glue("  Stillbirths: {sum(dhs_unified$out_stillbirth == 'Yes', na.rm=TRUE)}\n"))
cat(glue("  Neonatal deaths: {sum(dhs_unified$out_nnd == 'Yes', na.rm=TRUE)}\n\n"))


# --- LINK GEOGRAPHIC DATA ---
cat("--- Linking geographic data from GE shapefiles ---\n")
cat(glue("  Looking in: {dhs_geo}\n"))

# Remove existing geo columns if they exist (to avoid duplicates on re-run)
geo_cols_to_remove <- intersect(
  names(dhs_unified), 
  c("env_latitude", "env_longitude", "geo_urban_rural", "env_altitude_m",
    "ge_source_file", "ge_country_code", "DHSID", "DHSREGCO", "DHSREGNA",
    "ALT_GPS", ".ge_country_code")
)
if (length(geo_cols_to_remove) > 0) {
  cat(glue("  Removing {length(geo_cols_to_remove)} existing geo columns to avoid duplicates\n"))
  dhs_unified <- dhs_unified %>% select(-all_of(geo_cols_to_remove))
}

if (dir.exists(dhs_geo)) {
  ge_files <- list.files(dhs_geo, pattern = "\\.shp$", full.names = TRUE, recursive = TRUE)
  
  if (length(ge_files) > 0) {
    cat(glue("  Found {length(ge_files)} GE shapefiles\n"))
    
    if (!requireNamespace("sf", quietly = TRUE)) {
      cat("  WARNING: 'sf' package not installed. Installing now...\n")
      install.packages("sf")
    }
    library(sf)
    
    all_geo <- list()
    
    for (ge_path in ge_files) {
      tryCatch({
        geo <- sf::st_read(ge_path, quiet = TRUE)
        
        geo_df <- geo %>%
          sf::st_drop_geometry() %>%
          select(any_of(c("DHSCLUST", "LATNUM", "LONGNUM", "URBAN_RURA", 
                          "DHSID", "DHSREGCO", "DHSREGNA", "ALT_GPS", "ALT_DEM")))
        
        # Rename to unified names
        rename_map <- c(
          "DHSCLUST"   = "dhs_cluster",
          "LATNUM"     = "env_latitude",
          "LONGNUM"    = "env_longitude",
          "URBAN_RURA" = "geo_urban_rural",
          "ALT_DEM"    = "env_altitude_m"
        )
        for (old_nm in names(rename_map)) {
          if (old_nm %in% names(geo_df)) {
            names(geo_df)[names(geo_df) == old_nm] <- rename_map[old_nm]
          }
        }
        
        geo_df$ge_source_file <- basename(ge_path)
        geo_df$ge_country_code <- substr(basename(ge_path), 1, 2)
        
        # Remove missing coordinates (0,0 = missing in DHS)
        if ("env_latitude" %in% names(geo_df)) {
          geo_df <- geo_df %>% filter(!is.na(env_latitude) & env_latitude != 0)
        }
        
        all_geo[[length(all_geo) + 1]] <- geo_df
      }, error = function(e) {
        cat(glue("  Warning: Could not read {basename(ge_path)}: {e$message}\n"))
      })
    }
    
    if (length(all_geo) > 0) {
      geo_combined <- bind_rows(all_geo) %>%
        distinct(dhs_cluster, ge_country_code, .keep_all = TRUE)
      
      cat(glue("  Loaded {nrow(geo_combined)} unique cluster locations\n"))
      
      # Match on cluster number + country code
      if ("dhs_cluster" %in% names(dhs_unified) && "dhs_survey_id" %in% names(dhs_unified)) {
        dhs_unified <- dhs_unified %>%
          mutate(.ge_country_code = substr(dhs_survey_id, 1, 2)) %>%
          left_join(
            geo_combined,
            by = c("dhs_cluster" = "dhs_cluster", ".ge_country_code" = "ge_country_code")
          ) %>%
          select(-.ge_country_code)
        
        n_geo <- sum(!is.na(dhs_unified$env_latitude))
        pct_geo <- round(n_geo / nrow(dhs_unified) * 100, 1)
        cat(glue("  Geographic data linked: {n_geo}/{nrow(dhs_unified)} records ({pct_geo}%)\n\n"))
      } else {
        cat("  WARNING: dhs_cluster or dhs_survey_id columns not found. Cannot link geo data.\n")
        cat("  Columns available: ", paste(head(names(dhs_unified), 20), collapse = ", "), "\n\n")
        dhs_unified$env_latitude  <- NA_real_
        dhs_unified$env_longitude <- NA_real_
      }
    } else {
      cat("  No valid geographic data could be loaded from shapefiles.\n\n")
      dhs_unified$env_latitude  <- NA_real_
      dhs_unified$env_longitude <- NA_real_
    }
  } else {
    cat("  No .shp files found in geographic directory.\n")
    cat("  Make sure GE files are downloaded and placed in this directory.\n\n")
    dhs_unified$env_latitude  <- NA_real_
    dhs_unified$env_longitude <- NA_real_
  }
} else {
  cat(glue("  Geographic directory does not exist: {dhs_geo}\n"))
  cat("  Creating it now. Place GE shapefiles there for future runs.\n\n")
  dir.create(dhs_geo, recursive = TRUE)
  dhs_unified$env_latitude  <- NA_real_
  dhs_unified$env_longitude <- NA_real_
}


# ============================================================================
# PART 5: SAVE EVERYTHING (WITH GEOGRAPHIC DATA)
# ============================================================================

cat("--- Saving to Dropbox (primary) ---\n")

# RDS
saveRDS(dhs_unified, file.path(output_dropbox, "dhs_unified_dataset.rds"))
cat(glue("  Saved: dhs_unified_dataset.rds\n"))

# CSV
write_csv(dhs_unified, file.path(output_dropbox, "dhs_unified_dataset.csv"))
cat(glue("  Saved: dhs_unified_dataset.csv\n"))

# Stata .dta
dhs_stata <- dhs_unified
long_names <- names(dhs_stata)[nchar(names(dhs_stata)) > 32]
if (length(long_names) > 0) {
  cat(glue("  Truncating {length(long_names)} variable names for Stata 32-char limit\n"))
  names(dhs_stata)[nchar(names(dhs_stata)) > 32] <- substr(
    names(dhs_stata)[nchar(names(dhs_stata)) > 32], 1, 32
  )
}
haven::write_dta(dhs_stata, file.path(output_dropbox, "dhs_unified_dataset.dta"), version = 14)
cat(glue("  Saved: dhs_unified_dataset.dta\n"))
rm(dhs_stata)

# 10% sample
set.seed(42)
if ("mat_country" %in% names(dhs_unified)) {
  dhs_sample <- dhs_unified %>% group_by(mat_country) %>% sample_frac(0.1) %>% ungroup()
} else {
  dhs_sample <- dhs_unified %>% sample_frac(0.1)
}
saveRDS(dhs_sample, file.path(output_dropbox, "dhs_unified_10pct_sample.rds"))
write_csv(dhs_sample, file.path(output_dropbox, "dhs_unified_10pct_sample.csv"))
cat(glue("  Saved 10% sample: {nrow(dhs_sample)} records\n"))

# Processing log
if (exists("log_df")) {
  write_csv(log_df, file.path(dhs_logs, "dhs_processing_log.csv"))
  cat(glue("  Saved: dhs_processing_log.csv\n"))
}

cat(glue("\n  All saved to: {output_dropbox}\n\n"))


# --- Copy to OneDrive ---
if (dir.exists(output_onedrive)) {
  cat("--- Copying to OneDrive (backup) ---\n")
  
  files_to_copy <- c(
    "dhs_unified_dataset.rds",
    "dhs_unified_dataset.csv",
    "dhs_unified_dataset.dta",
    "dhs_unified_10pct_sample.rds",
    "dhs_unified_10pct_sample.csv"
  )
  
  for (f in files_to_copy) {
    src <- file.path(output_dropbox, f)
    if (file.exists(src)) {
      file.copy(src, file.path(output_onedrive, f), overwrite = TRUE)
      cat(glue("  Copied: {f}\n"))
    }
  }
  cat(glue("  OneDrive copy complete: {output_onedrive}\n\n"))
} else {
  cat(glue("  OneDrive directory not found, skipping copy: {output_onedrive}\n\n"))
}


# ============================================================================
# FINAL SUMMARY
# ============================================================================

cat(strrep("=", 70), "\n")
cat("  DONE — ALL FILES SAVED WITH GEOGRAPHIC DATA\n")
cat(strrep("=", 70), "\n\n")

cat(glue("Total records:     {nrow(dhs_unified)}\n"))
if ("out_livebirth" %in% names(dhs_unified))
  cat(glue("  Live births:     {sum(dhs_unified$out_livebirth == 'Yes', na.rm=TRUE)}\n"))
if ("out_stillbirth" %in% names(dhs_unified))
  cat(glue("  Stillbirths:     {sum(dhs_unified$out_stillbirth == 'Yes', na.rm=TRUE)}\n"))
if ("out_nnd" %in% names(dhs_unified))
  cat(glue("  Neonatal deaths: {sum(dhs_unified$out_nnd == 'Yes', na.rm=TRUE)}\n"))
if ("mat_country" %in% names(dhs_unified))
  cat(glue("  Countries:       {n_distinct(dhs_unified$mat_country)}\n"))
if ("dhs_survey_id" %in% names(dhs_unified))
  cat(glue("  Surveys:         {n_distinct(dhs_unified$dhs_survey_id)}\n"))
if ("env_latitude" %in% names(dhs_unified))
  cat(glue("  With GPS coords: {sum(!is.na(dhs_unified$env_latitude))}\n"))

cat(glue("\nCheckpoints saved to:  {dhs_checkpts}\n"))
cat(glue("Outputs saved to:      {output_dropbox}\n"))
if (dir.exists(output_onedrive))
  cat(glue("OneDrive backup:       {output_onedrive}\n"))

cat("\n")
cat("WHAT TO DO NEXT:\n")
cat("  1. You can now safely close RStudio — your data is saved to disk.\n")
cat("  2. Replace your DHS pipeline .Rmd with the updated version (Script 2).\n")
cat("  3. Future pipeline runs will load from checkpoints in seconds.\n")
cat("\n")
