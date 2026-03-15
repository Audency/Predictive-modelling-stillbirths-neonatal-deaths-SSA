# ============================================================================
# FIX DHS RELIGION, ETHNICITY LABELS + ADD BIRTH ATTENDANT
# ============================================================================
# PROBLEM:
#   The DHS Pipeline v7.2 strips haven labels via zap_labels() (line 631)
#   before extracting religion (v130) and ethnicity (v131), causing numeric
#   codes to pass through instead of decoded text labels.
#   Birth attendant (m3a-m3n) was also not extracted.
#
# FIX:
#   Re-read the rdhs cached BR files (which retain labels), extract v130,
#   v131, and m3a-m3n with proper label decoding, then update both the
#   DHS unified dataset and the merged unified dataset v10.16.
#
# INPUT:
#   data/dhs/cache/datasets/*.rds (rdhs cached BR files)
#   data/dhs/cache/db/keys/downloaded_datasets/ (survey_id mapping)
#   output/dhs_unified_dataset.rds
#   output/merged_unified_dataset_v10.16.rds
#
# OUTPUT:
#   output/dhs_unified_dataset.rds (updated in place)
#   output/merged_unified_dataset_v10.16.rds (updated in place)
# ============================================================================

cat("============================================================\n")
cat("  FIX DHS RELIGION, ETHNICITY & BIRTH ATTENDANT\n")
cat("============================================================\n\n")

suppressPackageStartupMessages({
  library(tidyverse)
  library(haven)
  library(glue)
})

# Set to your unified_dataset_pipeline directory, or run from project root.
base_path <- getwd()
# base_path <- "C:/Users/YOUR_USERNAME/path/to/unified_dataset_pipeline"

# ============================================================================
# STEP 1: Build survey_id -> BR filename mapping from download keys
# ============================================================================
cat("STEP 1: Building survey -> BR file mapping...\n")

key_dir <- "data/dhs/cache/db/keys/downloaded_datasets"
key_files <- list.files(key_dir, full.names = FALSE)
br_keys <- key_files[grepl("BR", key_files, ignore.case = TRUE)]

survey_br_map <- tibble(
  key = br_keys,
  survey_id = sub("_.*", "", br_keys),
  br_filename = sub("^[^_]+_(.+?)\\.(ZIP|zip)_rds_FALSE$", "\\1", br_keys)
) %>%
  mutate(br_file_path = file.path("data/dhs/cache/datasets", paste0(br_filename, ".rds")))

# Verify files exist
survey_br_map$file_exists <- file.exists(survey_br_map$br_file_path)
cat(glue("  {sum(survey_br_map$file_exists)} / {nrow(survey_br_map)} BR files found\n\n"))

# ============================================================================
# STEP 2: Extract labels from each BR cache file
# ============================================================================
cat("STEP 2: Extracting religion, ethnicity, and birth attendant from BR cache files...\n\n")

all_labels <- list()
n_processed <- 0
n_with_religion <- 0
n_with_ethnicity <- 0
n_with_attendant <- 0

for (i in seq_len(nrow(survey_br_map))) {
  sid <- survey_br_map$survey_id[i]
  fpath <- survey_br_map$br_file_path[i]

  if (!survey_br_map$file_exists[i]) next

  tryCatch({
    br <- readRDS(fpath)
    n_rows <- nrow(br)
    n_processed <- n_processed + 1

    # --- Religion (v130) ---
    religion <- rep(NA_character_, n_rows)
    if ("v130" %in% names(br) && is.labelled(br[["v130"]])) {
      religion <- as.character(as_factor(br[["v130"]]))
      n_with_religion <- n_with_religion + 1
    } else if ("v130" %in% names(br)) {
      # Not labelled - keep as character (will be numeric string)
      religion <- as.character(br[["v130"]])
    }

    # --- Ethnicity (v131) ---
    ethnicity <- rep(NA_character_, n_rows)
    if ("v131" %in% names(br) && is.labelled(br[["v131"]])) {
      ethnicity <- as.character(as_factor(br[["v131"]]))
      n_with_ethnicity <- n_with_ethnicity + 1
    } else if ("v131" %in% names(br)) {
      ethnicity <- as.character(br[["v131"]])
    }

    # --- Birth attendant (m3a-m3n) ---
    # Synthesize primary attendant from binary variables
    attendant <- rep(NA_character_, n_rows)
    att_map <- c(
      m3a = "Doctor",
      m3b = "Nurse/Midwife",
      m3c = "Auxiliary midwife",
      m3d = "Traditional birth attendant",
      m3e = "Community health worker",
      m3f = "Relative/Friend",
      m3g = "Other",
      m3n = "No one"
    )

    # Priority order: Doctor > Nurse/Midwife > Auxiliary > TBA > CHW > Relative > Other > No one
    for (var_name in names(att_map)) {
      if (var_name %in% names(br)) {
        vals <- br[[var_name]]
        if (is.labelled(vals)) vals <- zap_labels(vals)
        vals <- suppressWarnings(as.numeric(vals))
        # Set attendant where this type is "yes" (1) and not yet assigned
        is_yes <- !is.na(vals) & vals == 1
        attendant[is_yes & is.na(attendant)] <- att_map[var_name]
      }
    }
    has_att <- sum(!is.na(attendant))
    if (has_att > 0) n_with_attendant <- n_with_attendant + 1

    # Store with survey_id and row_index
    all_labels[[i]] <- tibble(
      survey_id = sid,
      row_index = seq_len(n_rows),
      mat_religion_decoded = religion,
      mat_ethnicity_decoded = ethnicity,
      mat_birth_attendant_decoded = attendant
    )

    if (n_processed %% 20 == 0) {
      cat(glue("  [{n_processed}/{sum(survey_br_map$file_exists)}] {sid}: {n_rows} rows\n"))
    }

  }, error = function(e) {
    cat(glue("  ERROR: {sid} - {e$message}\n"))
  })
}

labels_df <- bind_rows(all_labels)
cat(glue("\n  Total label records: {format(nrow(labels_df), big.mark=',')}\n"))
cat(glue("  Surveys with labelled religion: {n_with_religion} / {n_processed}\n"))
cat(glue("  Surveys with labelled ethnicity: {n_with_ethnicity} / {n_processed}\n"))
cat(glue("  Surveys with attendant data: {n_with_attendant} / {n_processed}\n\n"))

# Build study_id key matching the DHS pipeline format: "DHS_{survey_id}_{row_index}"
labels_df <- labels_df %>%
  mutate(study_id = paste0("DHS_", survey_id, "_", row_index))

# ============================================================================
# STEP 3: Harmonize religion to broad categories
# ============================================================================
cat("STEP 3: Harmonizing religion categories...\n")

# Show raw religion values
cat("  Raw religion values (top 30):\n")
print(head(sort(table(labels_df$mat_religion_decoded), decreasing = TRUE), 30))

# Harmonize: map country-specific labels to broad categories
labels_df <- labels_df %>%
  mutate(
    mat_religion_harmonized = case_when(
      is.na(mat_religion_decoded) ~ NA_character_,

      # Christian variants (extensive matching for DHS country-specific labels)
      grepl("cathol|roman cath", mat_religion_decoded, ignore.case = TRUE) ~ "Christian",
      grepl("protest|prostest|reform|luther|presbyt|baptist|method|anglican|adventist|evangel|pentecost|pentecoti|born.?again|charismat|apostol|salvation|orthodox|jehovah|zion|church|celest|assembl|christian|christr|gospel|mennonit|moravian|quaker|brethren|kimbangui|kibangui|spiritual|reveil|branham|harrist|prophet|prayer|healing|miracle|deliverance|grace|glory|faith.*mission|sda|seventh|watchtower|witness|new.?life|deeper.?life|living.?faith|winner|redeem|mission|grail|ccap|elcin|fjkm|flm|anglik|eglise|arm.e.*salut|chistian|bundu.*kongo|mana|vuvamu|zephir|matsouan|ngunza|sect", mat_religion_decoded, ignore.case = TRUE) ~ "Christian",
      grepl("^christian$", mat_religion_decoded, ignore.case = TRUE) ~ "Christian",
      grepl("^universal$", mat_religion_decoded, ignore.case = TRUE) ~ "Christian",

      # Islam variants (comprehensive DHS spelling variations)
      grepl("islam|muslim|moslem|muslem|muslin|muslm|musulm|mouride|tidjan|ahmadi|sunni|shia|wahabi", mat_religion_decoded, ignore.case = TRUE) ~ "Muslim",

      # Traditional/Animist
      grepl("tradition|taditional|animis|animali|vodoun|voodoo|fetish|ancestor|indigenous|african.*relig|coutumi|naturel|nature.*worship", mat_religion_decoded, ignore.case = TRUE) ~ "Traditional",

      # No religion
      grepl("no relig|^none$|^no$|^sans|^aucun|not relig|without relig|atheist|not respond", mat_religion_decoded, ignore.case = TRUE) ~ "No religion",

      # Other
      grepl("other|autre|hindu|buddh|baha|sikh|jewish|jain|mammon|aventist|new relig", mat_religion_decoded, ignore.case = TRUE) ~ "Other",

      # If it's still a numeric string, keep as NA (couldn't decode)
      grepl("^[0-9]+$", mat_religion_decoded) ~ NA_character_,

      # Default: Other
      TRUE ~ "Other"
    )
  )

cat("\n  Harmonized religion distribution:\n")
print(table(labels_df$mat_religion_harmonized, useNA = "ifany"))

# ============================================================================
# STEP 4: Update DHS unified dataset
# ============================================================================
cat("\nSTEP 4: Updating DHS unified dataset...\n")

dhs <- readRDS("output/dhs_unified_dataset.rds")
cat(glue("  Loaded: {format(nrow(dhs), big.mark=',')} rows x {ncol(dhs)} cols\n"))

# Before counts
cat(glue("  Before - Religion non-NA: {sum(!is.na(dhs$mat_religion))}\n"))
cat(glue("  Before - Ethnicity non-NA: {sum(!is.na(dhs$mat_ethnicity))}\n"))
cat(glue("  Before - Birth attendant non-NA: {sum(!is.na(dhs$mat_birth_attendant) | 'mat_birth_attendant' %in% names(dhs))}\n"))

# Create lookup
lookup <- labels_df %>%
  select(study_id, mat_religion_harmonized, mat_ethnicity_decoded, mat_birth_attendant_decoded)

# Join
dhs <- dhs %>%
  left_join(lookup, by = "study_id")

# Update religion: use harmonized decoded labels
dhs$mat_religion <- coalesce(dhs$mat_religion_harmonized, dhs$mat_religion)
dhs$mat_religion_harmonized <- NULL

# Update ethnicity: use decoded labels (keep country-specific text)
if (!"mat_ethnicity" %in% names(dhs)) dhs$mat_ethnicity <- NA_character_
dhs$mat_ethnicity <- coalesce(dhs$mat_ethnicity_decoded, dhs$mat_ethnicity)
dhs$mat_ethnicity_decoded <- NULL

# Update birth attendant
if (!"mat_birth_attendant" %in% names(dhs)) dhs$mat_birth_attendant <- NA_character_
dhs$mat_birth_attendant <- coalesce(dhs$mat_birth_attendant_decoded, dhs$mat_birth_attendant)
dhs$mat_birth_attendant_decoded <- NULL

# After counts
cat(glue("\n  After - Religion non-NA: {sum(!is.na(dhs$mat_religion))}\n"))
cat(glue("  After - Ethnicity non-NA: {sum(!is.na(dhs$mat_ethnicity))}\n"))
cat(glue("  After - Birth attendant non-NA: {sum(!is.na(dhs$mat_birth_attendant))}\n"))

cat("\n  Religion distribution:\n")
print(table(dhs$mat_religion, useNA = "ifany"))

cat("\n  Attendant distribution:\n")
print(table(dhs$mat_birth_attendant, useNA = "ifany"))

# Save updated DHS dataset
saveRDS(dhs, "output/dhs_unified_dataset.rds")
cat(glue("\n  Saved: dhs_unified_dataset.rds ({round(file.info('output/dhs_unified_dataset.rds')$size/1024^2, 1)} MB)\n\n"))

# ============================================================================
# STEP 5: Update merged unified dataset v10.16
# ============================================================================
cat("STEP 5: Updating merged_unified_dataset_v10.16...\n")

merged <- readRDS("output/merged_unified_dataset_v10.16.rds")
cat(glue("  Loaded: {format(nrow(merged), big.mark=',')} rows x {ncol(merged)} cols\n"))

# Create update lookup from the fixed DHS dataset - DEDUPLICATE to avoid row inflation
dhs_update <- dhs %>%
  filter(!is.na(study_id)) %>%
  select(study_id, mat_religion_new = mat_religion, mat_ethnicity_new = mat_ethnicity,
         mat_birth_attendant_new = mat_birth_attendant) %>%
  distinct(study_id, .keep_all = TRUE)

cat(glue("  Lookup: {format(nrow(dhs_update), big.mark=',')} unique study_ids\n"))

# Use match() for safe update (no row inflation)
match_idx <- match(merged$study_id, dhs_update$study_id)
has_match <- !is.na(match_idx)
cat(glue("  Matched: {format(sum(has_match), big.mark=',')} records\n"))

# Update columns directly using match (no join, no row inflation)
merged$mat_religion[has_match] <- coalesce(
  dhs_update$mat_religion_new[match_idx[has_match]],
  merged$mat_religion[has_match]
)

if (!"mat_ethnicity" %in% names(merged)) merged$mat_ethnicity <- NA_character_
merged$mat_ethnicity[has_match] <- coalesce(
  dhs_update$mat_ethnicity_new[match_idx[has_match]],
  merged$mat_ethnicity[has_match]
)

if (!"mat_birth_attendant" %in% names(merged)) merged$mat_birth_attendant <- NA_character_
merged$mat_birth_attendant[has_match] <- coalesce(
  dhs_update$mat_birth_attendant_new[match_idx[has_match]],
  merged$mat_birth_attendant[has_match]
)

cat(glue("  Updated religion: {sum(!is.na(merged$mat_religion))} non-NA\n"))
cat(glue("  Updated ethnicity: {sum(!is.na(merged$mat_ethnicity))} non-NA\n"))
cat(glue("  Updated attendant: {sum(!is.na(merged$mat_birth_attendant))} non-NA\n"))

cat("\n  Religion by study:\n")
print(table(merged$study_source, merged$mat_religion, useNA = "ifany"))

cat("\n  Attendant by study:\n")
print(table(merged$study_source, merged$mat_birth_attendant, useNA = "ifany"))

# Save
saveRDS(merged, "output/merged_unified_dataset_v10.16.rds")
cat(glue("\n  Saved: merged_unified_dataset_v10.16.rds ({round(file.info('output/merged_unified_dataset_v10.16.rds')$size/1024^2, 1)} MB)\n"))

rm(dhs, merged, labels_df, lookup, dhs_update)
gc()

cat("\n============================================================\n")
cat("  DHS LABEL FIX COMPLETE\n")
cat("============================================================\n")
