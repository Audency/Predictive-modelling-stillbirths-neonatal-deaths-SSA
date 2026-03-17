bash -lc cat > /mnt/data/SSA_StudyType_Descriptive_Pipeline_v3.R <<'EOF'
################################################################################
# SSA MULTI-STUDY DESCRIPTIVE + MODEL-READINESS PIPELINE (V3)
# Audencio Victor | LSHTM
#
# Built around df_ssa_from2010.rds
# Main principles:
# - Keep study-specific clinically useful variables
# - Do not drop variables only because DHS dominates global missingness
# - Evaluate completeness by study source and study type
# - Produce academic-looking outputs with theme_classic()
# - Export tables, Excel workbook, Word report and PowerPoint
################################################################################

rm(list = ls())
options(stringsAsFactors = FALSE)
set.seed(42)

################################################################################
# 1) USER CONFIGURATION
################################################################################
ROOT_DIR <- getwd()
INPUT_RDS <- "df_ssa_from2010.rds"   # change if needed
OUT_DIR <- "outputs_ssa_academic_v3"

AUTO_INSTALL <- TRUE
MAKE_WORD_REPORT <- TRUE
MAKE_POWERPOINT <- TRUE
SAVE_FILTERED_OBJECTS <- TRUE

TOP_N_COUNTRIES <- 20
TOP_N_STUDIES_FOR_FACETS <- 8
TOP_N_VARIABLES_HEATMAP <- 60

GLOBAL_MODEL_THRESHOLD <- 70
TYPE_MODEL_THRESHOLD <- 60
STUDY_MODEL_THRESHOLD <- 60
WEAK_THRESHOLD <- 40

################################################################################
# 2) PACKAGES
################################################################################
REQ_PKGS <- c(
  "dplyr","tidyr","stringr","ggplot2","scales","readr","tibble",
  "janitor","openxlsx","gtsummary","gt","officer","flextable","purrr",
  "forcats","pheatmap","lubridate","maps","htmltools"
)

for (p in REQ_PKGS) {
  if (!requireNamespace(p, quietly = TRUE)) {
    if (AUTO_INSTALL) install.packages(p, repos = "https://cloud.r-project.org")
    else stop("Missing package: ", p)
  }
}

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(ggplot2)
  library(scales)
  library(readr)
  library(tibble)
  library(janitor)
  library(openxlsx)
  library(gtsummary)
  library(gt)
  library(officer)
  library(flextable)
  library(purrr)
  library(forcats)
  library(pheatmap)
  library(lubridate)
  library(maps)
  library(htmltools)
})

################################################################################
# 3) DIRECTORIES
################################################################################
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
for (sub in c("tables","figures","figures/general","figures/outcomes",
              "figures/maternal","figures/birth","figures/completeness",
              "figures/models","figures/by_type","figures/by_country",
              "logs","objects","report","slides")) {
  dir.create(file.path(OUT_DIR, sub), showWarnings = FALSE, recursive = TRUE)
}

################################################################################
# 4) LOGGING
################################################################################
LOG_FILE <- file.path(OUT_DIR, "logs", paste0("run_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".txt"))
log_con <- file(LOG_FILE, open = "wt")
log_msg <- function(x) {
  line <- paste0("[", format(Sys.time(), "%H:%M:%S"), "] ", x)
  cat(line, "\n")
  cat(line, "\n", file = log_con, append = TRUE)
}
on.exit(try(close(log_con), silent = TRUE), add = TRUE)

################################################################################
# 5) VISUAL STYLE
################################################################################
pal_main <- c(
  navy   = "#17324D",
  teal   = "#1B7F79",
  green  = "#4F9D69",
  gold   = "#C9972B",
  wine   = "#8C3B4A",
  slate  = "#5B6770",
  sky    = "#75A9D6",
  coral  = "#D36A5C",
  purple = "#6C5B7B",
  grey   = "#9AA1A8"
)

pal_study_type <- c(
  "Survey / DHS" = pal_main["navy"],
  "Facility / WHO" = pal_main["teal"],
  "Cohort / Clinical" = pal_main["wine"],
  "Registry / Surveillance" = pal_main["gold"],
  "Trial / Intervention" = pal_main["green"],
  "Other" = pal_main["slate"]
)

theme_set(
  theme_classic(base_size = 12) +
    theme(
      plot.title = element_text(face = "bold", size = 15, colour = pal_main["navy"]),
      plot.subtitle = element_text(size = 10.5, colour = pal_main["slate"]),
      axis.title = element_text(face = "bold", colour = pal_main["navy"]),
      axis.text = element_text(colour = "#333333"),
      legend.title = element_text(face = "bold", colour = pal_main["navy"]),
      legend.text = element_text(colour = "#333333"),
      strip.text = element_text(face = "bold", colour = pal_main["navy"]),
      plot.caption = element_text(size = 8.5, colour = pal_main["slate"])
    )
)

################################################################################
# 6) SMALL HELPERS
################################################################################
safe_num <- function(x) suppressWarnings(as.numeric(as.character(x)))

clean_character_missing <- function(x) {
  y <- trimws(as.character(x))
  y[y %in% c("", "NA", "N/A", "na", "n/a", "missing", "unknown", "Unknown", "UNK")] <- NA
  y
}

to01 <- function(x) {
  if (is.logical(x)) return(ifelse(is.na(x), NA_integer_, as.integer(x)))
  if (is.numeric(x)) {
    ux <- sort(unique(x[!is.na(x)]))
    if (length(ux) == 0) return(as.integer(x))
    if (all(ux %in% c(0, 1))) return(as.integer(x))
    if (all(ux %in% c(1, 2))) return(ifelse(is.na(x), NA_integer_, as.integer(x == 2)))
    return(ifelse(is.na(x), NA_integer_, as.integer(x > 0)))
  }
  z <- tolower(trimws(as.character(x)))
  z[z %in% c("", "na", "n/a", "missing", "unknown", "unk")] <- NA
  out <- rep(NA_integer_, length(z))
  out[z %in% c("yes", "y", "true", "t", "1", "sim", "s")] <- 1L
  out[z %in% c("no", "n", "false", "f", "0", "nao", "não")] <- 0L
  out
}

rate_1000 <- function(events, denom) ifelse(denom > 0, round(events / denom * 1000, 1), NA_real_)

save_plot <- function(p, file, width = 10, height = 6, dpi = 320) {
  ggsave(filename = file, plot = p, width = width, height = height, dpi = dpi, bg = "white")
}

save_pheatmap <- function(mat, file, main = "Heatmap", width = 12, height = 8) {
  png(file, width = width, height = height, units = "in", res = 320)
  pheatmap(
    mat,
    cluster_rows = TRUE,
    cluster_cols = TRUE,
    main = main,
    fontsize_row = 7,
    fontsize_col = 10,
    border_color = "white",
    breaks = seq(0, 100, length.out = 101)
  )
  dev.off()
}

save_table_docx <- function(tbl, title, file) {
  doc <- read_docx() |>
    body_add_par(title, style = "heading 1") |>
    body_add_flextable(as_flex_table(tbl))
  print(doc, target = file)
}

make_summary_table <- function(data, by_var = NULL, vars_use, title, file_stub,
                               continuous_stat = "{mean} ({sd})") {
  d <- data |> select(any_of(c(by_var, vars_use)))
  if (ncol(d) == 0) return(NULL)
  
  numeric_candidates <- names(d)[sapply(d, function(x) is.numeric(x) || is.integer(x))]
  if (length(numeric_candidates) > 0) {
    d[numeric_candidates] <- lapply(d[numeric_candidates], function(x) suppressWarnings(as.numeric(as.character(x))))
  }
  
  cat_vars <- names(d)[!names(d) %in% c(by_var, numeric_candidates)]
  if (length(cat_vars) > 0) d[cat_vars] <- lapply(d[cat_vars], as.factor)
  
  if (is.null(by_var)) {
    tbl <- d |>
      tbl_summary(
        statistic = list(
          all_continuous() ~ continuous_stat,
          all_categorical() ~ "{n} ({p}%)"
        ),
        digits = list(all_continuous() ~ 1, all_categorical() ~ c(0, 1)),
        missing = "ifany",
        missing_text = "Missing"
      ) |>
      bold_labels()
  } else {
    tbl <- d |>
      tbl_summary(
        by = all_of(by_var),
        statistic = list(
          all_continuous() ~ continuous_stat,
          all_categorical() ~ "{n} ({p}%)"
        ),
        digits = list(all_continuous() ~ 1, all_categorical() ~ c(0, 1)),
        missing = "ifany",
        missing_text = "Missing"
      ) |>
      add_overall(last = TRUE) |>
      bold_labels()
  }
  
  gt::gtsave(as_gt(tbl), paste0(file_stub, ".html"))
  save_table_docx(tbl, title, paste0(file_stub, ".docx"))
  capture.output(tbl, file = paste0(file_stub, ".txt"))
  tbl
}

################################################################################
# 7) LOAD DATA
################################################################################
log_msg("Loading data...")
if (!file.exists(INPUT_RDS)) stop("Input file not found: ", INPUT_RDS)
df <- readRDS(INPUT_RDS)
if (!is.data.frame(df)) stop("Input object is not a data.frame/tibble.")

df <- janitor::clean_names(df)
for (j in names(df)) {
  if (is.character(df[[j]]) || is.factor(df[[j]])) df[[j]] <- clean_character_missing(df[[j]])
}

log_msg(paste("Loaded object with", nrow(df), "rows and", ncol(df), "columns"))

################################################################################
# 8) IDENTIFY CORE VARIABLES
################################################################################
study_var   <- intersect(c("study_source", "study", "source"), names(df))[1]
country_var <- intersect(c("mat_country", "loc_country", "country"), names(df))[1]
year_var    <- intersect(c("studyyear", "study_year", "year", "studyyear_num"), names(df))[1]
site_var    <- intersect(c("site","site_id","facility","cluster","loc_site","study_site"), names(df))[1]

if (is.na(study_var)) stop("No study variable found.")
if (is.na(country_var)) stop("No country variable found.")
if (is.na(year_var)) stop("No year variable found.")

################################################################################
# 9) COUNTRY HARMONIZATION
################################################################################
df[[country_var]][df[[country_var]] %in% c("Dem Rep Of The Congo","Congo Democratic Republic")] <-
  "Democratic Republic of the Congo"
df[[country_var]][df[[country_var]] == "Congo"] <- "Republic of the Congo"
df[[country_var]][df[[country_var]] == "Gambia"] <- "The Gambia"

################################################################################
# 10) FILTER
################################################################################
ssa <- c(
  "Uganda","Benin","Malawi","Tanzania","Mozambique","Kenya","The Gambia","Guinea-Bissau",
  "Ethiopia","Ghana","Angola","Democratic Republic of the Congo","Republic of the Congo",
  "Niger","Nigeria","Burkina Faso","Burundi","Cameroon","Central African Republic","Chad","Comoros",
  "Cote d'Ivoire","Eswatini","Gabon","Guinea","Lesotho","Liberia","Madagascar","Mali","Mauritania",
  "Namibia","Rwanda","Sao Tome and Principe","Senegal","Sierra Leone","South Africa","Sudan",
  "Togo","Zambia","Zimbabwe","Botswana","Cabo Verde","Cape Verde","Djibouti","Equatorial Guinea",
  "Eritrea","Mauritius","Seychelles","Somalia","South Sudan","United Republic of Tanzania",
  "Swaziland","Côte d’Ivoire","Ivory Coast"
)

yy <- safe_num(df[[year_var]])
df_ssa_from2010 <- df |>
  mutate(.year_num = yy) |>
  filter(!is.na(.year_num), .year_num >= 2010,
         !is.na(.data[[country_var]]),
         .data[[country_var]] %in% ssa) |>
  select(-.year_num)

log_msg(paste("Filtered dataset:", nrow(df_ssa_from2010), "rows and", ncol(df_ssa_from2010), "columns"))

################################################################################
# 11) DERIVE STUDY TYPE
################################################################################
df_ssa_from2010 <- df_ssa_from2010 |>
  mutate(
    study_source_std = as.character(.data[[study_var]]),
    study_type = case_when(
      str_detect(tolower(study_source_std), "dhs|demographic and health") ~ "Survey / DHS",
      str_detect(tolower(study_source_std), "who|whomcs|mcs") ~ "Facility / WHO",
      str_detect(tolower(study_source_std), "trial|random") ~ "Trial / Intervention",
      str_detect(tolower(study_source_std), "registry|surveillance") ~ "Registry / Surveillance",
      str_detect(tolower(study_source_std), "alert|precise|ptbi|ncops|indepth|amanhi|interbio|biodata|cohort|clinical") ~ "Cohort / Clinical",
      TRUE ~ "Other"
    )
  )

################################################################################
# 12) REMOVE ONLY TRULY EMPTY VARIABLES
################################################################################
is_truly_empty <- sapply(df_ssa_from2010, function(x) all(is.na(x)))
vars_truly_empty <- names(is_truly_empty)[is_truly_empty]
write.csv(data.frame(variable = vars_truly_empty),
          file.path(OUT_DIR, "tables", "vars_truly_empty_overall.csv"),
          row.names = FALSE)

df_ssa_from2010 <- df_ssa_from2010[, !is_truly_empty, drop = FALSE]

################################################################################
# 13) COMPLETENESS BY STUDY / TYPE / COUNTRY
################################################################################
vars_to_check <- setdiff(names(df_ssa_from2010), study_var)

completeness_by_study_wide <- df_ssa_from2010 |>
  group_by(.data[[study_var]]) |>
  summarise(
    n_rows = n(),
    across(all_of(vars_to_check), ~ round(100 * mean(!is.na(.)), 2), .names = "{.col}"),
    .groups = "drop"
  )

completeness_by_study_long <- completeness_by_study_wide |>
  pivot_longer(cols = -c(all_of(study_var), n_rows), names_to = "variable", values_to = "pct_complete")

vars_to_check2 <- setdiff(names(df_ssa_from2010), c(study_var, "study_source_std", "study_type"))

completeness_by_type_wide <- df_ssa_from2010 |>
  group_by(study_type) |>
  summarise(
    n_rows = n(),
    n_studies = n_distinct(.data[[study_var]]),
    across(all_of(vars_to_check2), ~ round(100 * mean(!is.na(.)), 2), .names = "{.col}"),
    .groups = "drop"
  )

completeness_by_type_long <- completeness_by_type_wide |>
  pivot_longer(cols = -c(study_type, n_rows, n_studies), names_to = "variable", values_to = "pct_complete")

completeness_by_country_wide <- df_ssa_from2010 |>
  group_by(.data[[country_var]]) |>
  summarise(
    n_rows = n(),
    across(all_of(vars_to_check2), ~ round(100 * mean(!is.na(.)), 2), .names = "{.col}"),
    .groups = "drop"
  )

write.csv(completeness_by_study_wide, file.path(OUT_DIR, "tables", "completeness_by_study_wide.csv"), row.names = FALSE)
write.csv(completeness_by_study_long, file.path(OUT_DIR, "tables", "completeness_by_study_long.csv"), row.names = FALSE)
write.csv(completeness_by_type_wide,  file.path(OUT_DIR, "tables", "completeness_by_type_wide.csv"), row.names = FALSE)
write.csv(completeness_by_type_long,  file.path(OUT_DIR, "tables", "completeness_by_type_long.csv"), row.names = FALSE)
write.csv(completeness_by_country_wide, file.path(OUT_DIR, "tables", "completeness_by_country_wide.csv"), row.names = FALSE)

################################################################################
# 14) AVAILABILITY REVIEW
################################################################################
availability_study <- completeness_by_study_long |>
  group_by(variable) |>
  summarise(
    max_pct_complete_study = max(pct_complete, na.rm = TRUE),
    n_studies_with_any_data = sum(pct_complete > 0, na.rm = TRUE),
    n_studies_with_20plus = sum(pct_complete >= 20, na.rm = TRUE),
    n_studies_with_50plus = sum(pct_complete >= 50, na.rm = TRUE),
    .groups = "drop"
  )

availability_type <- completeness_by_type_long |>
  group_by(variable) |>
  summarise(
    max_pct_complete_type = max(pct_complete, na.rm = TRUE),
    n_types_with_any_data = sum(pct_complete > 0, na.rm = TRUE),
    n_types_with_20plus = sum(pct_complete >= 20, na.rm = TRUE),
    n_types_with_50plus = sum(pct_complete >= 50, na.rm = TRUE),
    .groups = "drop"
  )

global_comp <- data.frame(
  variable = names(df_ssa_from2010),
  pct_complete_global = round(100 * sapply(df_ssa_from2010, function(x) mean(!is.na(x))), 2),
  n_non_missing = sapply(df_ssa_from2010, function(x) sum(!is.na(x))),
  stringsAsFactors = FALSE
)

variable_availability_review <- global_comp |>
  left_join(availability_study, by = "variable") |>
  left_join(availability_type, by = "variable") |>
  mutate(
    recommended_use = case_when(
      pct_complete_global >= GLOBAL_MODEL_THRESHOLD ~ "Good for global models",
      max_pct_complete_type >= TYPE_MODEL_THRESHOLD ~ "Good for type-specific models",
      max_pct_complete_study >= STUDY_MODEL_THRESHOLD ~ "Good for study-specific models",
      TRUE ~ "Descriptive only / limited modeling"
    )
  ) |>
  arrange(pct_complete_global, desc(max_pct_complete_type), desc(max_pct_complete_study))

write.csv(variable_availability_review,
          file.path(OUT_DIR, "tables", "variable_availability_review.csv"),
          row.names = FALSE)

vars_zero_everywhere <- variable_availability_review |>
  filter((is.na(max_pct_complete_study) | max_pct_complete_study == 0),
         (is.na(max_pct_complete_type) | max_pct_complete_type == 0)) |>
  pull(variable)

write.csv(data.frame(variable = vars_zero_everywhere),
          file.path(OUT_DIR, "tables", "vars_zero_everywhere.csv"),
          row.names = FALSE)

df_clean <- df_ssa_from2010[, !names(df_ssa_from2010) %in% vars_zero_everywhere, drop = FALSE]

vars_sparse_but_useful <- variable_availability_review |>
  filter(pct_complete_global < 10,
         (max_pct_complete_study >= 20 | max_pct_complete_type >= 20)) |>
  arrange(desc(max_pct_complete_type), desc(max_pct_complete_study))

write.csv(vars_sparse_but_useful,
          file.path(OUT_DIR, "tables", "vars_sparse_but_useful.csv"),
          row.names = FALSE)

################################################################################
# 15) DOMAIN MAP
################################################################################
domain_map <- data.frame(
  variable = names(df_clean),
  domain = case_when(
    str_detect(names(df_clean), "^out_") ~ "Outcomes",
    str_detect(names(df_clean), "^mat_") ~ "Maternal",
    str_detect(names(df_clean), "^neo_") ~ "Neonatal",
    str_detect(names(df_clean), "^env_") ~ "Environmental",
    str_detect(names(df_clean), "^loc_") ~ "Location",
    str_detect(names(df_clean), "^hh_")  ~ "Household",
    TRUE ~ "Other"
  ),
  stringsAsFactors = FALSE
)

################################################################################
# 16) IDENTIFY ANALYTIC VARIABLES
################################################################################
sex_var     <- intersect(c("neo_sex","sex","child_sex","baby_sex","infant_sex"), names(df_clean))[1]
V_AGE  <- intersect(c("mat_age","maternal_age","age"), names(df_clean))[1]
V_EDU  <- intersect(c("mat_education","education","edu_level","mat_edu"), names(df_clean))[1]
V_MAR  <- intersect(c("mat_marital_status","marital_status","marital"), names(df_clean))[1]
V_MODE <- intersect(c("delivery_mode","mat_delivery_mode","csection","c_section","mode_delivery"), names(df_clean))[1]
V_MULT <- intersect(c("multiple_birth","twin","twins","plurality"), names(df_clean))[1]
V_SBP  <- intersect(c("mat_sbp","sbp"), names(df_clean))[1]
V_DBP  <- intersect(c("mat_dbp","dbp"), names(df_clean))[1]
V_GA   <- intersect(c("out_ga_weeks","ga_weeks","gest_age_weeks","gestational_age_weeks"), names(df_clean))[1]
V_BW   <- intersect(c("out_birthweight_g","birthweight_g","bw_g","birth_weight_g"), names(df_clean))[1]
V_AP1  <- intersect(c("neo_apgar_1","apgar1","apgar_1"), names(df_clean))[1]
V_AP5  <- intersect(c("neo_apgar_5","apgar5","apgar_5"), names(df_clean))[1]
V_SB   <- intersect(c("out_stillbirth","stillbirth"), names(df_clean))[1]
V_LB   <- intersect(c("out_livebirth","livebirth"), names(df_clean))[1]
V_NND  <- intersect(c("out_nnd","nnd","out_neonatal_death"), names(df_clean))[1]
V_PRE  <- intersect(c("out_preterm","preterm"), names(df_clean))[1]
V_LBW  <- intersect(c("out_lbw","lbw"), names(df_clean))[1]
V_VLBW <- intersect(c("out_vlbw","vlbw"), names(df_clean))[1]
V_SGA  <- intersect(c("out_sga","sga"), names(df_clean))[1]

################################################################################
# 17) INVENTORY TABLES
################################################################################
var_inventory <- data.frame(
  variable = names(df_clean),
  class = sapply(df_clean, function(x) paste(class(x), collapse = "/")),
  n_missing = sapply(df_clean, function(x) sum(is.na(x))),
  pct_missing = round(100 * sapply(df_clean, function(x) mean(is.na(x))), 2),
  n_unique = sapply(df_clean, function(x) length(unique(na.omit(x)))),
  stringsAsFactors = FALSE
) |>
  left_join(domain_map, by = "variable") |>
  left_join(variable_availability_review, by = "variable") |>
  arrange(domain, pct_missing)

write.csv(var_inventory, file.path(OUT_DIR, "tables", "variable_inventory_enhanced.csv"), row.names = FALSE)

################################################################################
# 18) DISTRIBUTION TABLES
################################################################################
study_distribution <- df_clean |>
  count(.data[[study_var]], study_type, name = "n") |>
  mutate(pct = round(100 * n / sum(n), 2)) |>
  arrange(desc(n))

type_distribution <- df_clean |>
  count(study_type, name = "n") |>
  mutate(pct = round(100 * n / sum(n), 2)) |>
  arrange(desc(n))

country_distribution <- df_clean |>
  count(.data[[country_var]], study_type, name = "n") |>
  arrange(desc(n))

year_distribution <- df_clean |>
  mutate(.year_num = safe_num(.data[[year_var]])) |>
  filter(!is.na(.year_num)) |>
  count(.year_num, study_type, name = "n") |>
  arrange(.year_num)

write.csv(study_distribution, file.path(OUT_DIR, "tables", "study_distribution.csv"), row.names = FALSE)
write.csv(type_distribution,  file.path(OUT_DIR, "tables", "study_type_distribution.csv"), row.names = FALSE)
write.csv(country_distribution, file.path(OUT_DIR, "tables", "country_distribution_by_type.csv"), row.names = FALSE)
write.csv(year_distribution, file.path(OUT_DIR, "tables", "year_distribution_by_type.csv"), row.names = FALSE)

################################################################################
# 19) OVERALL + DOMAIN TABLES
################################################################################
maternal_vars <- unique(na.omit(c(country_var, year_var, V_AGE, V_EDU, V_MAR, V_MODE, V_MULT, V_SBP, V_DBP)))
birth_vars    <- unique(na.omit(c(V_GA, V_BW, sex_var, V_AP1, V_AP5, V_PRE, V_LBW, V_VLBW, V_SGA)))
outcome_vars  <- unique(na.omit(c(V_LB, V_SB, V_NND)))

make_summary_table(df_clean, NULL, maternal_vars, "Overall maternal characteristics",
                   file.path(OUT_DIR, "tables", "overall_maternal"))
make_summary_table(df_clean, NULL, birth_vars, "Overall birth and neonatal characteristics",
                   file.path(OUT_DIR, "tables", "overall_birth"))
make_summary_table(df_clean, NULL, outcome_vars, "Overall outcomes",
                   file.path(OUT_DIR, "tables", "overall_outcomes"))

make_summary_table(df_clean, "study_type", maternal_vars, "Table 1. Maternal characteristics by study type",
                   file.path(OUT_DIR, "tables", "table1_maternal_by_type"))
make_summary_table(df_clean, "study_type", birth_vars, "Table 1. Birth and neonatal characteristics by study type",
                   file.path(OUT_DIR, "tables", "table1_birth_by_type"))
make_summary_table(df_clean, "study_type", outcome_vars, "Table 1. Outcomes by study type",
                   file.path(OUT_DIR, "tables", "table1_outcomes_by_type"))

make_summary_table(df_clean, study_var, maternal_vars, "Table 1. Maternal characteristics by study",
                   file.path(OUT_DIR, "tables", "table1_maternal_by_study"))
make_summary_table(df_clean, study_var, birth_vars, "Table 1. Birth and neonatal characteristics by study",
                   file.path(OUT_DIR, "tables", "table1_birth_by_study"))
make_summary_table(df_clean, study_var, outcome_vars, "Table 1. Outcomes by study",
                   file.path(OUT_DIR, "tables", "table1_outcomes_by_study"))

################################################################################
# 20) CONTINUOUS / CATEGORICAL SUMMARIES BY TYPE
################################################################################
cont_vars <- unique(na.omit(c(V_AGE, V_SBP, V_DBP, V_GA, V_BW, V_AP1, V_AP5)))

if (length(cont_vars) > 0) {
  continuous_summary_by_type <- bind_rows(lapply(cont_vars, function(v) {
    tmp <- df_clean |>
      transmute(study_type = study_type, x = safe_num(.data[[v]])) |>
      filter(!is.na(x))
    if (nrow(tmp) == 0) return(NULL)
    tmp |>
      group_by(study_type) |>
      summarise(
        variable = v,
        n = n(),
        mean = round(mean(x), 2),
        sd = round(sd(x), 2),
        median = round(median(x), 2),
        p25 = round(quantile(x, 0.25), 2),
        p75 = round(quantile(x, 0.75), 2),
        min = round(min(x), 2),
        max = round(max(x), 2),
        .groups = "drop"
      )
  }))
  write.csv(continuous_summary_by_type,
            file.path(OUT_DIR, "tables", "continuous_summary_by_type.csv"),
            row.names = FALSE)
}

cat_vars <- unique(na.omit(c(country_var, sex_var, V_EDU, V_MAR, V_MODE, V_MULT,
                             V_SB, V_LB, V_NND, V_PRE, V_LBW, V_VLBW, V_SGA)))

if (length(cat_vars) > 0) {
  categorical_summary_by_type <- bind_rows(lapply(cat_vars, function(v) {
    df_clean |>
      filter(!is.na(.data[[v]])) |>
      count(study_type, level = .data[[v]], name = "n") |>
      group_by(study_type) |>
      mutate(variable = v, pct = round(100 * n / sum(n), 2)) |>
      ungroup() |>
      select(variable, study_type, level, n, pct)
  }))
  write.csv(categorical_summary_by_type,
            file.path(OUT_DIR, "tables", "categorical_summary_by_type.csv"),
            row.names = FALSE)
}

################################################################################
# 21) MORTALITY / OUTCOME RATES
################################################################################
if (!is.na(V_SB) && !is.na(V_LB)) {
  sb  <- to01(df_clean[[V_SB]])
  lb  <- to01(df_clean[[V_LB]])
  tb  <- (sb == 1) | (lb == 1)
  nnd <- if (!is.na(V_NND)) to01(df_clean[[V_NND]]) else rep(NA_integer_, nrow(df_clean))
  
  mortality_by_type <- df_clean |>
    mutate(sb = sb, lb = lb, tb = tb, nnd = nnd) |>
    group_by(study_type) |>
    summarise(
      N = n(),
      LB = sum(lb == 1, na.rm = TRUE),
      SB = sum(sb == 1, na.rm = TRUE),
      NND = if (!is.na(V_NND)) sum(nnd == 1, na.rm = TRUE) else NA_real_,
      TB = sum(tb == TRUE, na.rm = TRUE),
      SBR_1000 = rate_1000(SB, TB),
      NND_rate_1000 = if (!is.na(V_NND)) rate_1000(NND, LB) else NA_real_,
      PMR_1000 = if (!is.na(V_NND)) rate_1000(SB + NND, TB) else NA_real_,
      .groups = "drop"
    ) |>
    arrange(desc(TB))
  
  mortality_by_study <- df_clean |>
    mutate(sb = sb, lb = lb, tb = tb, nnd = nnd) |>
    group_by(.data[[study_var]], study_type) |>
    summarise(
      N = n(),
      LB = sum(lb == 1, na.rm = TRUE),
      SB = sum(sb == 1, na.rm = TRUE),
      NND = if (!is.na(V_NND)) sum(nnd == 1, na.rm = TRUE) else NA_real_,
      TB = sum(tb == TRUE, na.rm = TRUE),
      SBR_1000 = rate_1000(SB, TB),
      NND_rate_1000 = if (!is.na(V_NND)) rate_1000(NND, LB) else NA_real_,
      PMR_1000 = if (!is.na(V_NND)) rate_1000(SB + NND, TB) else NA_real_,
      .groups = "drop"
    ) |>
    arrange(desc(TB))
  
  write.csv(mortality_by_type, file.path(OUT_DIR, "tables", "mortality_rates_by_study_type.csv"), row.names = FALSE)
  write.csv(mortality_by_study, file.path(OUT_DIR, "tables", "mortality_rates_by_study.csv"), row.names = FALSE)
}

################################################################################
# 22) COMPLETENESS BY DOMAIN
################################################################################
comp_domain_by_type <- bind_rows(lapply(unique(df_clean$study_type), function(tt) {
  dsub <- df_clean |> filter(study_type == tt)
  data.frame(
    study_type = tt,
    variable = names(dsub),
    pct_complete = round(100 * sapply(dsub, function(x) mean(!is.na(x))), 2),
    stringsAsFactors = FALSE
  )
})) |>
  left_join(domain_map, by = "variable") |>
  group_by(study_type, domain) |>
  summarise(
    n_vars = n(),
    mean_pct_complete = round(mean(pct_complete, na.rm = TRUE), 2),
    median_pct_complete = round(median(pct_complete, na.rm = TRUE), 2),
    n_vars_50plus = sum(pct_complete >= 50, na.rm = TRUE),
    n_vars_80plus = sum(pct_complete >= 80, na.rm = TRUE),
    .groups = "drop"
  ) |>
  arrange(domain, desc(mean_pct_complete))

write.csv(comp_domain_by_type,
          file.path(OUT_DIR, "tables", "completeness_by_domain_and_study_type.csv"),
          row.names = FALSE)

################################################################################
# 23) MODEL READINESS
################################################################################
eligible_variables_for_models_by_type <- completeness_by_type_long |>
  left_join(domain_map, by = "variable") |>
  mutate(
    modeling_flag = case_when(
      pct_complete >= 80 ~ "Strong",
      pct_complete >= 60 ~ "Usable",
      pct_complete >= 40 ~ "Borderline",
      TRUE ~ "Weak"
    )
  ) |>
  arrange(study_type, desc(pct_complete))

write.csv(eligible_variables_for_models_by_type,
          file.path(OUT_DIR, "tables", "eligible_variables_for_models_by_type.csv"),
          row.names = FALSE)

clinical_useful <- variable_availability_review |>
  left_join(domain_map, by = "variable") |>
  filter(domain %in% c("Maternal", "Neonatal", "Outcomes", "Environmental"),
         pct_complete_global < 20,
         max_pct_complete_type >= 50) |>
  arrange(desc(max_pct_complete_type), desc(max_pct_complete_study))

write.csv(clinical_useful,
          file.path(OUT_DIR, "tables", "clinical_variables_sparse_globally_but_good_by_type.csv"),
          row.names = FALSE)

################################################################################
# 24) FIGURES
################################################################################
p1 <- ggplot(type_distribution, aes(x = fct_reorder(study_type, n), y = n, fill = study_type)) +
  geom_col(width = 0.75) +
  coord_flip() +
  scale_fill_manual(values = pal_study_type) +
  scale_y_continuous(labels = comma) +
  labs(title = "Records by study type", x = NULL, y = "N") +
  theme(legend.position = "none")
save_plot(p1, file.path(OUT_DIR, "figures", "general", "records_by_study_type.png"), 8, 5)

p2 <- ggplot(study_distribution |> slice_head(n = min(25, nrow(study_distribution))),
             aes(x = fct_reorder(.data[[study_var]], n), y = n, fill = study_type)) +
  geom_col(width = 0.75) +
  coord_flip() +
  scale_fill_manual(values = pal_study_type) +
  scale_y_continuous(labels = comma) +
  labs(title = "Top studies by number of records", x = NULL, y = "N", fill = "Study type")
save_plot(p2, file.path(OUT_DIR, "figures", "general", "records_by_study_top25.png"), 11, 7)

country_plot_data <- df_clean |>
  count(.data[[country_var]], name = "n") |>
  slice_max(order_by = n, n = TOP_N_COUNTRIES)

p3 <- ggplot(country_plot_data, aes(x = fct_reorder(.data[[country_var]], n), y = n)) +
  geom_col(fill = pal_main["teal"], width = 0.75) +
  coord_flip() +
  scale_y_continuous(labels = comma) +
  labs(title = paste0("Top ", TOP_N_COUNTRIES, " countries by number of records"),
       x = NULL, y = "N")
save_plot(p3, file.path(OUT_DIR, "figures", "general", "records_by_country_top.png"), 10, 7)

year_plot <- df_clean |>
  mutate(.year_num = safe_num(.data[[year_var]])) |>
  filter(!is.na(.year_num)) |>
  count(.year_num, study_type, name = "n")

p4 <- ggplot(year_plot, aes(x = .year_num, y = n, colour = study_type)) +
  geom_line(linewidth = 1) +
  geom_point(size = 2) +
  scale_colour_manual(values = pal_study_type) +
  scale_y_continuous(labels = comma) +
  labs(title = "Records by year and study type", x = "Year", y = "N", colour = "Study type")
save_plot(p4, file.path(OUT_DIR, "figures", "general", "records_by_year_type.png"), 10, 5)

if (exists("mortality_by_type")) {
  p5 <- ggplot(mortality_by_type, aes(x = fct_reorder(study_type, SBR_1000), y = SBR_1000, fill = study_type)) +
    geom_col(width = 0.75) +
    coord_flip() +
    scale_fill_manual(values = pal_study_type) +
    labs(title = "Stillbirth rate by study type", x = NULL, y = "Stillbirth rate per 1,000") +
    theme(legend.position = "none")
  save_plot(p5, file.path(OUT_DIR, "figures", "outcomes", "stillbirth_rate_by_type.png"), 8, 5)
  
  p6 <- ggplot(mortality_by_type, aes(x = fct_reorder(study_type, PMR_1000), y = PMR_1000, fill = study_type)) +
    geom_col(width = 0.75) +
    coord_flip() +
    scale_fill_manual(values = pal_study_type) +
    labs(title = "Perinatal mortality rate by study type", x = NULL, y = "PMR per 1,000") +
    theme(legend.position = "none")
  save_plot(p6, file.path(OUT_DIR, "figures", "outcomes", "pmr_by_type.png"), 8, 5)
}

if (!is.na(V_GA)) {
  ga_plot <- df_clean |>
    mutate(ga = safe_num(.data[[V_GA]])) |>
    filter(!is.na(ga), ga >= 15, ga <= 45)
  if (nrow(ga_plot) > 0) {
    p7 <- ggplot(ga_plot, aes(x = ga, fill = study_type)) +
      geom_histogram(alpha = 0.8, bins = 35, position = "identity") +
      scale_fill_manual(values = pal_study_type) +
      labs(title = "Gestational age distribution", x = "Gestational age (weeks)", y = "Count")
    save_plot(p7, file.path(OUT_DIR, "figures", "birth", "ga_distribution.png"), 9, 5)
  }
}

if (!is.na(V_BW)) {
  bw_plot <- df_clean |>
    mutate(bw = safe_num(.data[[V_BW]])) |>
    filter(!is.na(bw), bw >= 300, bw <= 6000)
  if (nrow(bw_plot) > 0) {
    p8 <- ggplot(bw_plot, aes(x = bw, fill = study_type)) +
      geom_histogram(alpha = 0.8, bins = 40, position = "identity") +
      scale_fill_manual(values = pal_study_type) +
      labs(title = "Birthweight distribution", x = "Birthweight (g)", y = "Count")
    save_plot(p8, file.path(OUT_DIR, "figures", "birth", "birthweight_distribution.png"), 9, 5)
  }
}

hm_type_vars <- completeness_by_type_long |>
  group_by(variable) |>
  summarise(sd_comp = sd(pct_complete, na.rm = TRUE), .groups = "drop") |>
  arrange(desc(sd_comp)) |>
  slice_head(n = min(TOP_N_VARIABLES_HEATMAP, n())) |>
  pull(variable)

if (length(hm_type_vars) > 1) {
  hm_type <- completeness_by_type_long |>
    filter(variable %in% hm_type_vars) |>
    pivot_wider(names_from = study_type, values_from = pct_complete) |>
    tibble::column_to_rownames("variable") |>
    as.matrix()
  save_pheatmap(hm_type,
                file.path(OUT_DIR, "figures", "completeness", "heatmap_completeness_by_type.png"),
                "Completeness (%) by study type")
}

hm_domain <- comp_domain_by_type |>
  select(study_type, domain, mean_pct_complete) |>
  pivot_wider(names_from = study_type, values_from = mean_pct_complete) |>
  tibble::column_to_rownames("domain") |>
  as.matrix()

save_pheatmap(hm_domain,
              file.path(OUT_DIR, "figures", "completeness", "heatmap_domain_completeness_by_type.png"),
              "Mean completeness (%) by domain and study type",
              width = 10, height = 5)

################################################################################
# 25) EXCEL WORKBOOK
################################################################################
wb <- createWorkbook()

tab_files <- list(
  study_distribution = study_distribution,
  study_type_distribution = type_distribution,
  country_distribution_by_type = country_distribution,
  year_distribution_by_type = year_distribution,
  completeness_by_study_wide = completeness_by_study_wide,
  completeness_by_study_long = completeness_by_study_long,
  completeness_by_type_wide = completeness_by_type_wide,
  completeness_by_type_long = completeness_by_type_long,
  variable_inventory = var_inventory,
  availability_review = variable_availability_review,
  sparse_but_useful = vars_sparse_but_useful,
  comp_domain_by_type = comp_domain_by_type,
  eligible_vars_by_type = eligible_variables_for_models_by_type,
  clinical_useful = clinical_useful
)

if (exists("continuous_summary_by_type")) tab_files$continuous_summary_by_type <- continuous_summary_by_type
if (exists("categorical_summary_by_type")) tab_files$categorical_summary_by_type <- categorical_summary_by_type
if (exists("mortality_by_type")) tab_files$mortality_by_type <- mortality_by_type
if (exists("mortality_by_study")) tab_files$mortality_by_study <- mortality_by_study

for (nm in names(tab_files)) {
  addWorksheet(wb, substr(nm, 1, 31))
  writeData(wb, substr(nm, 1, 31), tab_files[[nm]])
}
saveWorkbook(wb, file.path(OUT_DIR, "tables", "descriptive_structured_by_study_type.xlsx"), overwrite = TRUE)

################################################################################
# 26) SAVE OBJECTS
################################################################################
if (SAVE_FILTERED_OBJECTS) {
  saveRDS(df_ssa_from2010, file.path(OUT_DIR, "objects", "df_ssa_from2010_filtered.rds"), compress = "xz")
  saveRDS(df_clean, file.path(OUT_DIR, "objects", "df_ssa_from2010_structured_clean.rds"), compress = "xz")
}

################################################################################
# 27) WORD REPORT
################################################################################
if (MAKE_WORD_REPORT) {
  doc <- read_docx()
  doc <- body_add_par(doc, "SSA multi-study descriptive report", style = "heading 1")
  doc <- body_add_par(doc, paste0("Generated on ", format(Sys.time(), "%Y-%m-%d %H:%M")), style = "Normal")
  
  summary_lines <- c(
    paste("Filtered rows:", nrow(df_ssa_from2010)),
    paste("Structured-clean rows:", nrow(df_clean)),
    paste("Columns after removing truly empty and zero-everywhere variables:", ncol(df_clean)),
    paste("Studies:", dplyr::n_distinct(df_clean[[study_var]])),
    paste("Countries:", dplyr::n_distinct(df_clean[[country_var]])),
    paste("Study types:", paste(sort(unique(df_clean$study_type)), collapse = ", "))
  )
  
  for (ln in summary_lines) doc <- body_add_par(doc, ln, style = "Normal")
  
  doc <- body_add_par(doc, "Key messages", style = "heading 2")
  msg <- c(
    "Variables were not removed only because of high global missingness.",
    "Completeness was evaluated by study and by study type to protect clinically useful variables in smaller studies.",
    "Outputs include descriptive tables, model-readiness summaries, mortality rates, and completeness heatmaps."
  )
  for (ln in msg) doc <- body_add_par(doc, paste0("• ", ln), style = "Normal")
  
  if (file.exists(file.path(OUT_DIR, "figures", "general", "records_by_study_type.png"))) {
    doc <- body_add_par(doc, "Records by study type", style = "heading 2")
    doc <- body_add_img(doc, src = file.path(OUT_DIR, "figures", "general", "records_by_study_type.png"), width = 6.5, height = 4.0)
  }
  
  if (file.exists(file.path(OUT_DIR, "figures", "completeness", "heatmap_domain_completeness_by_type.png"))) {
    doc <- body_add_par(doc, "Completeness by domain and study type", style = "heading 2")
    doc <- body_add_img(doc, src = file.path(OUT_DIR, "figures", "completeness", "heatmap_domain_completeness_by_type.png"), width = 6.5, height = 3.3)
  }
  
  if (exists("mortality_by_type")) {
    doc <- body_add_par(doc, "Mortality rates by study type", style = "heading 2")
    ft <- regulartable(mortality_by_type)
    ft <- autofit(ft)
    doc <- body_add_flextable(doc, ft)
  }
  
  ft2 <- regulartable(head(variable_availability_review, 25))
  ft2 <- autofit(ft2)
  doc <- body_add_par(doc, "Variable availability review (first 25 rows)", style = "heading 2")
  doc <- body_add_flextable(doc, ft2)
  
  print(doc, target = file.path(OUT_DIR, "report", "SSA_Analytic_Report_v3.docx"))
}

################################################################################
# 28) POWERPOINT
################################################################################
if (MAKE_POWERPOINT) {
  ppt <- read_pptx()
  
  ppt <- add_slide(ppt, layout = "Title Slide", master = "Office Theme")
  ppt <- ph_with(ppt, value = "SSA multi-study descriptive analysis", location = ph_location_type(type = "ctrTitle"))
  ppt <- ph_with(ppt, value = "Study-structured completeness and model-readiness pipeline", location = ph_location_type(type = "subTitle"))
  
  ppt <- add_slide(ppt, layout = "Title and Content", master = "Office Theme")
  ppt <- ph_with(ppt, "Dataset summary", location = ph_location_type(type = "title"))
  ppt <- ph_with(ppt,
                 value = paste(
                   paste0("Filtered rows: ", nrow(df_ssa_from2010)),
                   paste0("Structured-clean rows: ", nrow(df_clean)),
                   paste0("Studies: ", dplyr::n_distinct(df_clean[[study_var]])),
                   paste0("Countries: ", dplyr::n_distinct(df_clean[[country_var]])),
                   sep = "\n"
                 ),
                 location = ph_location_type(type = "body"))
  
  if (file.exists(file.path(OUT_DIR, "figures", "general", "records_by_study_type.png"))) {
    ppt <- add_slide(ppt, layout = "Title and Content", master = "Office Theme")
    ppt <- ph_with(ppt, "Records by study type", location = ph_location_type(type = "title"))
    ppt <- ph_with(ppt,
                   external_img(file.path(OUT_DIR, "figures", "general", "records_by_study_type.png"),
                                width = 8.5, height = 4.8),
                   location = ph_location(left = 0.5, top = 1.2, width = 8.5, height = 4.8))
  }
  
  if (file.exists(file.path(OUT_DIR, "figures", "completeness", "heatmap_domain_completeness_by_type.png"))) {
    ppt <- add_slide(ppt, layout = "Title and Content", master = "Office Theme")
    ppt <- ph_with(ppt, "Completeness by domain and study type", location = ph_location_type(type = "title"))
    ppt <- ph_with(ppt,
                   external_img(file.path(OUT_DIR, "figures", "completeness", "heatmap_domain_completeness_by_type.png"),
                                width = 8.5, height = 4.5),
                   location = ph_location(left = 0.5, top = 1.2, width = 8.5, height = 4.5))
  }
  
  if (exists("mortality_by_type")) {
    ppt <- add_slide(ppt, layout = "Title and Content", master = "Office Theme")
    ppt <- ph_with(ppt, "Mortality rates by study type", location = ph_location_type(type = "title"))
    ppt <- ph_with(ppt, value = as.data.frame(mortality_by_type), location = ph_location_type(type = "body"))
  }
  
  print(ppt, target = file.path(OUT_DIR, "slides", "SSA_Analytic_Presentation_v3.pptx"))
}

################################################################################
# 29) FINAL MASTER SUMMARY
################################################################################
summary_master <- tibble(
  metric = c(
    "rows_filtered", "rows_structured_clean", "columns_structured_clean",
    "n_studies", "n_countries", "n_study_types",
    "truly_empty_variables_removed", "zero_everywhere_variables_removed", "log_file"
  ),
  value = c(
    nrow(df_ssa_from2010),
    nrow(df_clean),
    ncol(df_clean),
    dplyr::n_distinct(df_clean[[study_var]]),
    dplyr::n_distinct(df_clean[[country_var]]),
    dplyr::n_distinct(df_clean$study_type),
    length(vars_truly_empty),
    length(vars_zero_everywhere),
    LOG_FILE
  )
)

write.csv(summary_master, file.path(OUT_DIR, "analysis_summary_master.csv"), row.names = FALSE)

log_msg("Pipeline complete.")
cat("\nDONE.\n")
cat("Main output folder:", normalizePath(OUT_DIR, winslash = "/"), "\n")
EOF
wc -l /mnt/data/SSA_StudyType_Descriptive_Pipeline_v3.R