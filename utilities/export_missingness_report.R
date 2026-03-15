# ============================================================================
# EXPORT MISSINGNESS REPORT (XLSX)
# ============================================================================
# Creates an Excel workbook with variable-level missingness summaries
# for the final v10.17 cleaned dataset.
#
# INPUT:  output/unified_dataset_with_env_v10.17_cleaned.rds
# OUTPUT: output/unified_dataset_v10.17_missingness_report.xlsx
# ============================================================================

cat("============================================================\n")
cat("  EXPORT MISSINGNESS REPORT\n")
cat("============================================================\n\n")

suppressPackageStartupMessages({
  library(tidyverse)
  library(glue)
})

# Install writexl if needed
if (!requireNamespace("writexl", quietly = TRUE)) {
  install.packages("writexl", repos = "https://cloud.r-project.org")
}
library(writexl)

# Set to your unified_dataset_pipeline/output directory, or run from project root.
base_path <- file.path(getwd(), "output")
input_file <- file.path(base_path, "unified_dataset_with_env_v10.17_cleaned.rds")

cat("Loading v10.17 cleaned dataset...\n")
df <- readRDS(input_file)
cat(glue("  Loaded: {format(nrow(df), big.mark=',')} rows x {ncol(df)} columns\n\n"))

# ============================================================================
# SHEET 1: Overall missingness by variable
# ============================================================================
cat("Computing overall missingness...\n")

overall <- tibble(
  Column_Number = seq_along(names(df)),
  Variable = names(df),
  Type = sapply(df, function(x) class(x)[1]),
  N_Total = nrow(df),
  N_NonMissing = sapply(df, function(x) sum(!is.na(x))),
  N_Missing = sapply(df, function(x) sum(is.na(x))),
  Pct_Missing = round(100 * sapply(df, function(x) mean(is.na(x))), 2),
  Pct_Complete = round(100 * sapply(df, function(x) mean(!is.na(x))), 2),
  N_Unique = sapply(df, function(x) n_distinct(x, na.rm = TRUE))
)

cat(glue("  {nrow(overall)} variables\n"))
cat(glue("  Fully complete: {sum(overall$Pct_Missing == 0)}\n"))
cat(glue("  Fully missing: {sum(overall$Pct_Missing == 100)}\n"))
cat(glue("  Partial: {sum(overall$Pct_Missing > 0 & overall$Pct_Missing < 100)}\n\n"))

# ============================================================================
# SHEET 2: Missingness by study_source x variable
# ============================================================================
cat("Computing missingness by study...\n")

studies <- sort(unique(df$study_source))
by_study_list <- list()

for (study in studies) {
  sub <- df %>% filter(study_source == study)
  n_study <- nrow(sub)

  study_miss <- tibble(
    Variable = names(sub),
    !!paste0("N_", study) := n_study,
    !!paste0("NonMissing_", study) := sapply(sub, function(x) sum(!is.na(x))),
    !!paste0("PctMissing_", study) := round(100 * sapply(sub, function(x) mean(is.na(x))), 2)
  )
  by_study_list[[study]] <- study_miss
}

# Join all study summaries
by_study <- by_study_list[[1]]
for (i in 2:length(by_study_list)) {
  by_study <- left_join(by_study, by_study_list[[i]], by = "Variable")
}

cat(glue("  {length(studies)} studies: {paste(studies, collapse=', ')}\n\n"))

# ============================================================================
# SHEET 3: Summary statistics for numeric variables
# ============================================================================
cat("Computing summary statistics...\n")

numeric_vars <- names(df)[sapply(df, is.numeric)]

numeric_summary <- tibble(
  Variable = numeric_vars,
  N_NonMissing = sapply(df[numeric_vars], function(x) sum(!is.na(x))),
  Pct_Missing = round(100 * sapply(df[numeric_vars], function(x) mean(is.na(x))), 2),
  Min = sapply(df[numeric_vars], function(x) if (all(is.na(x))) NA_real_ else min(x, na.rm = TRUE)),
  Q1 = sapply(df[numeric_vars], function(x) if (all(is.na(x))) NA_real_ else quantile(x, 0.25, na.rm = TRUE)),
  Median = sapply(df[numeric_vars], function(x) if (all(is.na(x))) NA_real_ else median(x, na.rm = TRUE)),
  Mean = sapply(df[numeric_vars], function(x) if (all(is.na(x))) NA_real_ else mean(x, na.rm = TRUE)),
  Q3 = sapply(df[numeric_vars], function(x) if (all(is.na(x))) NA_real_ else quantile(x, 0.75, na.rm = TRUE)),
  Max = sapply(df[numeric_vars], function(x) if (all(is.na(x))) NA_real_ else max(x, na.rm = TRUE))
)

cat(glue("  {nrow(numeric_summary)} numeric variables summarized\n\n"))

# ============================================================================
# WRITE XLSX
# ============================================================================
output_file <- file.path(base_path, "unified_dataset_v10.17_missingness_report.xlsx")

sheets <- list(
  "Overall_Missingness" = overall,
  "By_Study" = by_study,
  "Numeric_Summary" = numeric_summary
)

write_xlsx(sheets, output_file)
cat(glue("Saved: {basename(output_file)} ({round(file.info(output_file)$size/1024, 1)} KB)\n"))

rm(df, overall, by_study, numeric_summary)
gc()

cat("\n============================================================\n")
cat("  MISSINGNESS REPORT COMPLETE\n")
cat("============================================================\n")
