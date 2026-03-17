################################################################################
# EDA PIPELINE v2 — SSA + >=2010
# Audencio Victor | LSHTM
#
# Improved version: consolidated, robust, well-structured
# INPUT:  unified_dataset_with_env_v10.17_cleaned.rds
# OUTPUT: df_ssa_from2010.rds (filtered + cleaned)
#         outputs_eda/ (figures, tables, logs)
################################################################################

cat("
+------------------------------------------------------------------------+
|  EDA Pipeline v2 - SSA + >=2010                                        |
|  Audencio Victor | LSHTM                                               |
|  Predicting Stillbirth & Neonatal Death in Sub-Saharan Africa          |
+------------------------------------------------------------------------+
\n")

rm(list = ls())
options(stringsAsFactors = FALSE)
set.seed(42)

# ==============================================================================
# 1) CONFIGURATION
# ==============================================================================
DATA_DIR  <- "~/Desktop/AUDENCIO/Producao artigos/Artigo Projeto Principal LSHTM/Dataset"
INPUT_RDS <- file.path(DATA_DIR, "unified_dataset_with_env_v10.17_cleaned.rds")
OUT_DIR   <- file.path(DATA_DIR, "outputs_eda")

AUTO_INSTALL    <- TRUE
MISS_THRESHOLD  <- 0.90  # Remove variables with > 90% missing
YEAR_CUTOFF     <- 2010

# Model readiness thresholds
GLOBAL_THR  <- 70
TYPE_THR    <- 60
STUDY_THR   <- 60

# ==============================================================================
# 2) PACKAGES
# ==============================================================================
REQ_PKGS <- c(
  "dplyr", "tidyr", "stringr", "ggplot2", "scales", "readr", "tibble",
  "janitor", "openxlsx", "gtsummary", "gt", "officer", "flextable",
  "purrr", "forcats", "pheatmap", "corrplot", "ggridges"
)

for (p in REQ_PKGS) {
  if (!requireNamespace(p, quietly = TRUE)) {
    if (AUTO_INSTALL) install.packages(p, repos = "https://cloud.r-project.org", quiet = TRUE)
    else stop("Missing package: ", p)
  }
}

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(stringr); library(ggplot2)
  library(scales); library(readr); library(tibble); library(janitor)
  library(openxlsx); library(gtsummary); library(gt); library(officer)
  library(flextable); library(purrr); library(forcats); library(pheatmap)
  library(corrplot); library(ggridges)
})

# Output directories
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
fig_dir <- file.path(OUT_DIR, "figures"); dir.create(fig_dir, showWarnings = FALSE)
tbl_dir <- file.path(OUT_DIR, "tables");  dir.create(tbl_dir, showWarnings = FALSE)
log_dir <- file.path(OUT_DIR, "logs");    dir.create(log_dir, showWarnings = FALSE)

# ==============================================================================
# 3) HELPER FUNCTIONS
# ==============================================================================
safe_num <- function(x) suppressWarnings(as.numeric(as.character(x)))

to01 <- function(x) {
  if (is.null(x)) return(rep(NA_integer_, 0))
  if (is.logical(x)) return(ifelse(is.na(x), NA_integer_, as.integer(x)))
  if (is.numeric(x)) {
    ux <- sort(unique(x[!is.na(x)]))
    if (length(ux) == 0) return(as.integer(x))
    if (all(ux %in% c(0, 1))) return(as.integer(x))
    if (all(ux %in% c(1, 2))) return(ifelse(is.na(x), NA_integer_, as.integer(x == 2)))
    return(ifelse(is.na(x), NA_integer_, as.integer(x > 0)))
  }
  z <- tolower(trimws(as.character(x)))
  z[z %in% c("", "na", "n/a", "missing", "unknown")] <- NA
  out <- rep(NA_integer_, length(z))
  out[z %in% c("yes", "y", "true", "t", "1", "sim", "s")] <- 1L
  out[z %in% c("no", "n", "false", "f", "0", "nao")] <- 0L
  out
}

rate_1000 <- function(events, denom) {
  ifelse(denom > 0, round(events / denom * 1000, 1), NA_real_)
}

fmt_n <- function(x) format(x, big.mark = ",", scientific = FALSE)

save_plot <- function(p, filename, w = 10, h = 6, dpi = 300) {
  path <- file.path(fig_dir, filename)
  tryCatch(
    ggsave(path, plot = p, width = w, height = h, dpi = dpi, bg = "white"),
    error = function(e) message("  [WARN] ggsave failed: ", filename, " | ", e$message)
  )
  invisible(path)
}

save_csv <- function(df, filename) {
  path <- file.path(tbl_dir, filename)
  write.csv(df, path, row.names = FALSE)
  invisible(path)
}

log_msg <- function(msg) {
  line <- sprintf("[%s] %s", format(Sys.time(), "%H:%M:%S"), msg)
  cat(line, "\n")
}

# Custom ggplot theme
theme_lshtm <- function(base_size = 12) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title    = element_text(face = "bold", size = rel(1.2), color = "#1a3a5c"),
      plot.subtitle = element_text(size = rel(0.9), color = "#5a6d7e"),
      plot.caption  = element_text(size = rel(0.7), color = "#8e99a4", hjust = 0),
      panel.grid.major = element_line(color = "#ecf0f1", linewidth = 0.4),
      panel.grid.minor = element_blank(),
      axis.title    = element_text(size = rel(0.9), color = "#34495e", face = "bold"),
      axis.text     = element_text(size = rel(0.85), color = "#5a6d7e"),
      legend.position = "bottom",
      strip.text    = element_text(face = "bold", size = rel(0.9)),
      plot.background  = element_rect(fill = "white", color = NA),
      panel.background = element_rect(fill = "white", color = NA)
    )
}
theme_set(theme_lshtm())

# ==============================================================================
# 4) LOAD & CLEAN DATA
# ==============================================================================
log_msg("Loading dataset...")
stopifnot(file.exists(INPUT_RDS))
df_raw <- readRDS(INPUT_RDS)
df_raw <- janitor::clean_names(df_raw)

log_msg(sprintf("  Raw dataset: %s rows x %s cols", fmt_n(nrow(df_raw)), fmt_n(ncol(df_raw))))

# String cleaning
for (j in names(df_raw)) {
  if (is.character(df_raw[[j]])) {
    x <- trimws(df_raw[[j]])
    x[x %in% c("", "NA", "N/A", "na", "n/a", "missing", "unknown", "Unknown", "UNK")] <- NA
    df_raw[[j]] <- x
  }
}

# Country standardisation
country_var <- intersect(c("mat_country", "loc_country", "country"), names(df_raw))[1]
stopifnot(!is.na(country_var))

df_raw[[country_var]][df_raw[[country_var]] %in%
  c("Dem Rep Of The Congo", "Congo Democratic Republic")] <- "Democratic Republic of the Congo"
df_raw[[country_var]][df_raw[[country_var]] == "Congo"]     <- "Republic of the Congo"
df_raw[[country_var]][df_raw[[country_var]] == "Gambia"]     <- "The Gambia"
df_raw[[country_var]][df_raw[[country_var]] == "Swaziland"]  <- "Eswatini"

log_msg("  Country labels standardised")

# ==============================================================================
# 5) FILTER: SSA + >= 2010
# ==============================================================================
log_msg("Filtering SSA + >= 2010...")

ssa_countries <- c(
  "Uganda", "Benin", "Malawi", "Tanzania", "Mozambique", "Kenya", "The Gambia",
  "Guinea-Bissau", "Ethiopia", "Ghana", "Angola", "Democratic Republic of the Congo",
  "Republic of the Congo", "Niger", "Nigeria", "Burkina Faso", "Burundi", "Cameroon",
  "Central African Republic", "Chad", "Comoros", "Cote d'Ivoire", "Eswatini", "Gabon",
  "Guinea", "Lesotho", "Liberia", "Madagascar", "Mali", "Mauritania", "Namibia",
  "Rwanda", "Sao Tome and Principe", "Senegal", "Sierra Leone", "South Africa",
  "Sudan", "Togo", "Zambia", "Zimbabwe", "Botswana", "Cabo Verde", "Djibouti",
  "Equatorial Guinea", "Eritrea", "Somalia", "South Sudan"
)

year_var <- intersect(c("studyyear", "study_year", "year"), names(df_raw))[1]
stopifnot(!is.na(year_var))

df <- df_raw %>%
  filter(
    !is.na(.data[[year_var]]),
    safe_num(.data[[year_var]]) >= YEAR_CUTOFF,
    !is.na(.data[[country_var]]),
    .data[[country_var]] %in% ssa_countries
  )

log_msg(sprintf("  After filter: %s rows x %s cols", fmt_n(nrow(df)), fmt_n(ncol(df))))
log_msg(sprintf("  Countries: %d | Years: %s-%s",
                n_distinct(df[[country_var]]),
                min(safe_num(df[[year_var]]), na.rm = TRUE),
                max(safe_num(df[[year_var]]), na.rm = TRUE)))

# ==============================================================================
# 6) IDENTIFY KEY COLUMNS
# ==============================================================================
study_var <- intersect(c("study_source", "study", "source"), names(df))[1]
sex_var   <- intersect(c("neo_sex", "sex", "child_sex"), names(df))[1]
lat_var   <- intersect(c("env_latitude", "lat", "latitude"), names(df))[1]
lon_var   <- intersect(c("env_longitude", "lon", "longitude"), names(df))[1]

V_SB   <- intersect(c("out_stillbirth", "stillbirth"), names(df))[1]
V_LB   <- intersect(c("out_livebirth", "livebirth"), names(df))[1]
V_NND  <- intersect(c("out_nnd", "nnd", "out_neonatal_death"), names(df))[1]
V_PND  <- intersect(c("out_perinatal_death", "perinatal_death"), names(df))[1]
V_PRE  <- intersect(c("out_preterm", "preterm"), names(df))[1]
V_LBW  <- intersect(c("out_lbw", "lbw"), names(df))[1]
V_VLBW <- intersect(c("out_vlbw", "vlbw"), names(df))[1]
V_SGA  <- intersect(c("out_sga", "sga"), names(df))[1]
V_GA   <- intersect(c("out_ga_weeks", "ga_weeks"), names(df))[1]
V_BW   <- intersect(c("out_birthweight_g", "birthweight_g"), names(df))[1]
V_AGE  <- intersect(c("mat_age", "maternal_age"), names(df))[1]
V_EDU  <- intersect(c("mat_education", "education"), names(df))[1]
V_MODE <- intersect(c("delivery_mode", "mat_delivery_mode"), names(df))[1]
V_MAR  <- intersect(c("mat_marital_status", "marital_status"), names(df))[1]
V_MULT <- intersect(c("multiple_birth", "twin", "plurality"), names(df))[1]
V_SBP  <- intersect(c("mat_sbp", "sbp"), names(df))[1]
V_DBP  <- intersect(c("mat_dbp", "dbp"), names(df))[1]
V_AP1  <- intersect(c("neo_apgar_1", "apgar1"), names(df))[1]
V_AP5  <- intersect(c("neo_apgar_5", "apgar5"), names(df))[1]
V_AGEDEATH <- intersect(c("neo_age_at_death_days", "age_at_death_days"), names(df))[1]

env_vars <- grep("^env_", names(df), value = TRUE)
env_num  <- env_vars[sapply(df[env_vars], is.numeric)]

# Study type classification
df <- df %>%
  mutate(
    study_type = case_when(
      str_detect(tolower(.data[[study_var]]), "dhs")                     ~ "Survey / DHS",
      str_detect(tolower(.data[[study_var]]), "who|whomcs")              ~ "Facility / WHO",
      str_detect(tolower(.data[[study_var]]), "alert|precise|ptbi|ncops|indepth|amanhi|interbio|biob") ~ "Cohort / Clinical",
      str_detect(tolower(.data[[study_var]]), "registry|surveillance")   ~ "Registry / Surveillance",
      TRUE ~ "Other"
    )
  )

log_msg("  Key columns identified")
log_msg(sprintf("  Outcomes available: SB=%s LB=%s NND=%s PRE=%s LBW=%s SGA=%s",
                !is.na(V_SB), !is.na(V_LB), !is.na(V_NND),
                !is.na(V_PRE), !is.na(V_LBW), !is.na(V_SGA)))

# ==============================================================================
# 7) REMOVE TRULY EMPTY VARIABLES
# ==============================================================================
log_msg("Removing truly empty variables...")

is_empty <- sapply(df, function(x) all(is.na(x)))
empty_vars <- names(is_empty)[is_empty]

if (length(empty_vars) > 0) {
  save_csv(data.frame(variable = empty_vars), "vars_truly_empty.csv")
  df <- df[, !is_empty, drop = FALSE]
}

log_msg(sprintf("  Removed %d empty variables. Remaining: %d cols", length(empty_vars), ncol(df)))

# ==============================================================================
# 8) MISSINGNESS ANALYSIS
# ==============================================================================
log_msg("Analysing missingness...")

# Variable-level missingness
miss_prop <- sapply(df, function(x) mean(is.na(x)))

miss_df <- tibble(
  variable     = names(miss_prop),
  pct_missing  = round(100 * as.numeric(miss_prop), 2),
  n_missing    = colSums(is.na(df)),
  n_total      = nrow(df),
  domain       = case_when(
    str_detect(variable, "^out_") ~ "Outcomes",
    str_detect(variable, "^mat_") ~ "Maternal",
    str_detect(variable, "^neo_") ~ "Neonatal",
    str_detect(variable, "^env_") ~ "Environmental",
    str_detect(variable, "^loc_") ~ "Location",
    str_detect(variable, "^hh_")  ~ "Household",
    TRUE ~ "Other"
  )
) %>% arrange(desc(pct_missing))

save_csv(miss_df, "missingness_by_variable.csv")

# Variables > threshold
vars_high_miss <- miss_df %>% filter(pct_missing > MISS_THRESHOLD * 100)
save_csv(vars_high_miss, sprintf("vars_missing_gt%d_pct.csv", MISS_THRESHOLD * 100))

log_msg(sprintf("  Variables > %d%% missing: %d", MISS_THRESHOLD * 100, nrow(vars_high_miss)))

# Domain summary
domain_miss <- miss_df %>%
  group_by(domain) %>%
  summarise(
    n_vars         = n(),
    avg_missing    = round(mean(pct_missing), 1),
    median_missing = round(median(pct_missing), 1),
    vars_gt50_miss = sum(pct_missing > 50),
    vars_complete  = sum(pct_missing == 0),
    .groups = "drop"
  ) %>% arrange(desc(avg_missing))

save_csv(domain_miss, "missingness_by_domain.csv")

p <- ggplot(domain_miss, aes(x = reorder(domain, avg_missing), y = avg_missing,
                              fill = avg_missing)) +
  geom_col(show.legend = FALSE, alpha = 0.85) +
  scale_fill_gradient(low = "#c7e9b4", high = "#d73027") +
  coord_flip() +
  labs(title = "Average Missingness by Domain", x = NULL, y = "Avg % Missing")
save_plot(p, "missingness_by_domain.png", w = 9, h = 5)

# ==============================================================================
# 9) COMPLETENESS BY STUDY & STUDY TYPE
# ==============================================================================
log_msg("Computing completeness by study...")

vars_check <- setdiff(names(df), c(study_var, "study_type"))

comp_by_study <- df %>%
  group_by(study = .data[[study_var]]) %>%
  summarise(
    n_rows = n(),
    across(all_of(vars_check), ~ round(100 * mean(!is.na(.)), 2)),
    .groups = "drop"
  )
save_csv(comp_by_study, "completeness_by_study_wide.csv")

comp_study_long <- comp_by_study %>%
  pivot_longer(-c(study, n_rows), names_to = "variable", values_to = "pct_complete")
save_csv(comp_study_long, "completeness_by_study_long.csv")

vars_check2 <- setdiff(names(df), c(study_var, "study_type"))

comp_by_type <- df %>%
  group_by(study_type) %>%
  summarise(
    n_rows   = n(),
    n_studies = n_distinct(.data[[study_var]]),
    across(all_of(vars_check2), ~ round(100 * mean(!is.na(.)), 2)),
    .groups = "drop"
  )
save_csv(comp_by_type, "completeness_by_type_wide.csv")

comp_type_long <- comp_by_type %>%
  pivot_longer(-c(study_type, n_rows, n_studies), names_to = "variable", values_to = "pct_complete")
save_csv(comp_type_long, "completeness_by_type_long.csv")

# Completeness heatmap by study
log_msg("  Creating completeness heatmaps...")

var_rank <- comp_study_long %>%
  group_by(variable) %>%
  summarise(sd_comp = sd(pct_complete, na.rm = TRUE), .groups = "drop") %>%
  arrange(desc(sd_comp))

top_vars <- var_rank %>% slice_head(n = min(50, nrow(var_rank))) %>% pull(variable)

hm_mat <- comp_study_long %>%
  filter(variable %in% top_vars) %>%
  group_by(variable, study) %>%
  summarise(pct_complete = mean(pct_complete, na.rm = TRUE), .groups = "drop") %>%
  pivot_wider(names_from = study, values_from = pct_complete) %>%
  tibble::column_to_rownames("variable") %>%
  as.matrix()

png(file.path(fig_dir, "heatmap_completeness_by_study.png"), width = 16, height = 13, units = "in", res = 300)
pheatmap(
  hm_mat,
  cluster_rows = TRUE, cluster_cols = TRUE,
  main = "Completeness (%) by Study - Top 50 Most Variable",
  fontsize_row = 7, fontsize_col = 9,
  border_color = "white",
  color = colorRampPalette(c("#d73027", "#fc8d59", "#fee090", "#91bfdb", "#4575b4"))(100),
  breaks = seq(0, 100, length.out = 101)
)
dev.off()

# By study type
type_var_rank <- comp_type_long %>%
  group_by(variable) %>%
  summarise(sd_comp = sd(pct_complete, na.rm = TRUE), .groups = "drop") %>%
  arrange(desc(sd_comp))

top_vars_type <- type_var_rank %>%
  slice_head(n = min(60, nrow(type_var_rank))) %>%
  pull(variable)

hm_type <- comp_type_long %>%
  filter(variable %in% top_vars_type) %>%
  group_by(variable, study_type) %>%
  summarise(pct_complete = mean(pct_complete, na.rm = TRUE), .groups = "drop") %>%
  pivot_wider(names_from = study_type, values_from = pct_complete) %>%
  tibble::column_to_rownames("variable") %>%
  as.matrix()

png(file.path(fig_dir, "heatmap_completeness_by_type.png"), width = 14, height = 10, units = "in", res = 300)
pheatmap(
  hm_type,
  cluster_rows = TRUE, cluster_cols = TRUE,
  main = "Completeness (%) by Study Type - Top 60 Most Variable",
  fontsize_row = 7, fontsize_col = 10,
  border_color = "white",
  color = colorRampPalette(c("#d73027", "#fc8d59", "#fee090", "#91bfdb", "#4575b4"))(100),
  breaks = seq(0, 100, length.out = 101)
)
dev.off()

# ==============================================================================
# 10) MODEL READINESS ASSESSMENT
# ==============================================================================
log_msg("Model readiness assessment...")

avail_study <- comp_study_long %>%
  group_by(variable) %>%
  summarise(
    max_study        = max(pct_complete, na.rm = TRUE),
    n_studies_gt50   = sum(pct_complete >= 50),
    n_studies_gt20   = sum(pct_complete >= 20),
    .groups = "drop"
  )

avail_type <- comp_type_long %>%
  group_by(variable) %>%
  summarise(
    max_type       = max(pct_complete, na.rm = TRUE),
    n_types_gt50   = sum(pct_complete >= 50),
    .groups = "drop"
  )

global_comp <- tibble(
  variable   = names(df),
  pct_global = round(100 * (1 - colMeans(is.na(df))), 2)
)

model_readiness <- global_comp %>%
  left_join(avail_study, by = "variable") %>%
  left_join(avail_type, by = "variable") %>%
  left_join(miss_df %>% select(variable, domain), by = "variable") %>%
  mutate(
    readiness = case_when(
      pct_global >= GLOBAL_THR  ~ "Global model",
      max_type >= TYPE_THR      ~ "Type-specific model",
      max_study >= STUDY_THR    ~ "Study-specific model",
      TRUE                      ~ "Descriptive only"
    )
  ) %>%
  arrange(desc(readiness == "Global model"), desc(pct_global))

save_csv(model_readiness, "model_readiness_by_variable.csv")

# Subsets
save_csv(model_readiness %>% filter(readiness == "Global model"), "vars_global_model.csv")
save_csv(model_readiness %>% filter(readiness == "Type-specific model"), "vars_type_specific.csv")
save_csv(model_readiness %>% filter(readiness == "Study-specific model"), "vars_study_specific.csv")
save_csv(model_readiness %>% filter(pct_global < 10, max_study >= 20), "vars_sparse_but_useful.csv")

ready_counts <- model_readiness %>% count(readiness)
log_msg("  Model readiness:")
for (i in seq_len(nrow(ready_counts))) {
  log_msg(sprintf("    %s: %d variables", ready_counts$readiness[i], ready_counts$n[i]))
}

# ==============================================================================
# 11) OUTCOME RATES
# ==============================================================================
log_msg("Computing outcome rates...")

if (!is.na(V_SB) && !is.na(V_LB)) {
  sb <- to01(df[[V_SB]]); lb <- to01(df[[V_LB]])
  tb <- (sb == 1) | (lb == 1)
  nnd <- if (!is.na(V_NND)) to01(df[[V_NND]]) else rep(NA_integer_, nrow(df))

  SB <- sum(sb == 1, na.rm = TRUE)
  LB <- sum(lb == 1, na.rm = TRUE)
  TB <- sum(tb == TRUE, na.rm = TRUE)
  NND <- if (!is.na(V_NND)) sum(nnd == 1, na.rm = TRUE) else NA

  rates_overall <- tibble(
    Metric = c("Stillbirths", "Live Births", "Total Births", "Neonatal Deaths",
               "SBR per 1,000", "NND rate per 1,000 LB", "PMR per 1,000"),
    Value = c(fmt_n(SB), fmt_n(LB), fmt_n(TB),
              if (!is.na(NND)) fmt_n(NND) else "N/A",
              rate_1000(SB, TB),
              if (!is.na(NND)) rate_1000(NND, LB) else NA,
              if (!is.na(NND)) rate_1000(SB + NND, TB) else NA)
  )
  save_csv(rates_overall, "outcome_rates_overall.csv")

  log_msg(sprintf("  SBR = %s per 1,000 | NND rate = %s per 1,000 LB",
                  rate_1000(SB, TB),
                  if (!is.na(NND)) rate_1000(NND, LB) else "N/A"))

  # By study
  mortality_study <- df %>%
    mutate(sb = sb, lb = lb, tb = tb, nnd = nnd) %>%
    group_by(study = .data[[study_var]]) %>%
    summarise(
      N = n(), TB = sum(tb, na.rm = TRUE), LB = sum(lb == 1, na.rm = TRUE),
      SB = sum(sb == 1, na.rm = TRUE),
      NND = if (!is.na(V_NND)) sum(nnd == 1, na.rm = TRUE) else NA_real_,
      SBR_1000 = rate_1000(SB, TB),
      NND_rate = if (!is.na(V_NND)) rate_1000(NND, LB) else NA_real_,
      PMR_1000 = if (!is.na(V_NND)) rate_1000(SB + NND, TB) else NA_real_,
      .groups = "drop"
    ) %>% arrange(desc(TB))
  save_csv(mortality_study, "mortality_rates_by_study.csv")

  # By country
  mortality_country <- df %>%
    mutate(sb = sb, lb = lb, tb = tb, nnd = nnd) %>%
    group_by(country = .data[[country_var]]) %>%
    summarise(
      N = n(), TB = sum(tb, na.rm = TRUE), LB = sum(lb == 1, na.rm = TRUE),
      SB = sum(sb == 1, na.rm = TRUE),
      NND = if (!is.na(V_NND)) sum(nnd == 1, na.rm = TRUE) else NA_real_,
      SBR_1000 = rate_1000(SB, TB),
      NND_rate = if (!is.na(V_NND)) rate_1000(NND, LB) else NA_real_,
      .groups = "drop"
    ) %>% arrange(desc(TB))
  save_csv(mortality_country, "mortality_rates_by_country.csv")
}

# All outcome prevalences
outcome_list <- unique(na.omit(c(V_SB, V_LB, V_NND, V_PND, V_PRE, V_LBW, V_VLBW, V_SGA)))
if (length(outcome_list) > 0) {
  out_counts <- bind_rows(lapply(outcome_list, function(v) {
    y <- to01(df[[v]])
    tibble(
      outcome     = v,
      events      = sum(y == 1, na.rm = TRUE),
      denominator = sum(!is.na(y)),
      prevalence  = round(mean(y == 1, na.rm = TRUE) * 100, 2),
      rate_1000   = rate_1000(sum(y == 1, na.rm = TRUE), sum(!is.na(y)))
    )
  }))
  save_csv(out_counts, "outcome_prevalences.csv")
}

# ==============================================================================
# 12) STUDY & GEOGRAPHIC DISTRIBUTION PLOTS
# ==============================================================================
log_msg("Creating distribution plots...")

# By study
if (!is.na(study_var)) {
  study_dist <- df %>% count(.data[[study_var]], name = "n") %>%
    mutate(pct = round(100 * n / sum(n), 1)) %>% arrange(n)

  p <- ggplot(study_dist, aes(x = reorder(.data[[study_var]], n), y = n, fill = n)) +
    geom_col(show.legend = FALSE) +
    scale_fill_viridis_c(option = "D", direction = -1) +
    geom_text(aes(label = paste0(fmt_n(n), " (", pct, "%)")), hjust = -0.05, size = 3) +
    coord_flip() +
    scale_y_continuous(labels = comma, expand = expansion(mult = c(0, 0.18))) +
    labs(title = "Records by Study Source", x = NULL, y = "N")
  save_plot(p, "records_by_study.png", w = 12, h = 7)
}

# By country
if (!is.na(country_var)) {
  ctry <- df %>% count(.data[[country_var]], name = "n") %>%
    mutate(pct = round(100 * n / sum(n), 1)) %>% arrange(desc(n))

  p <- ggplot(ctry %>% slice_head(n = 30),
              aes(x = reorder(.data[[country_var]], n), y = n, fill = n)) +
    geom_col(show.legend = FALSE) +
    scale_fill_viridis_c(option = "C", direction = -1) +
    coord_flip() +
    scale_y_continuous(labels = comma) +
    labs(title = "Top 30 Countries by Records", x = NULL, y = "N")
  save_plot(p, "geographic_distribution_top30.png", w = 10, h = 8)
}

# Temporal
if (!is.na(year_var)) {
  yr <- df %>% mutate(year = safe_num(.data[[year_var]])) %>%
    filter(!is.na(year)) %>% count(year, name = "n")

  p <- ggplot(yr, aes(x = year, y = n)) +
    geom_area(fill = "#2c7fb8", alpha = 0.3) +
    geom_line(color = "#2c7fb8", linewidth = 1.2) +
    geom_point(color = "#253494", size = 2.5) +
    scale_y_continuous(labels = comma) +
    labs(title = "Temporal Distribution", x = "Year", y = "Records")
  save_plot(p, "temporal_distribution.png", w = 10, h = 5)
}

# ==============================================================================
# 13) OUTCOME PLOTS
# ==============================================================================
log_msg("Creating outcome plots...")

if (!is.na(V_SB) && !is.na(V_LB) && !is.na(study_var) && exists("mortality_study")) {
  p <- ggplot(mortality_study %>% filter(!is.na(SBR_1000)),
              aes(x = reorder(study, SBR_1000), y = SBR_1000, fill = SBR_1000)) +
    geom_col(show.legend = FALSE) +
    scale_fill_gradient2(low = "#fee090", mid = "#fc8d59", high = "#d73027",
                         midpoint = median(mortality_study$SBR_1000, na.rm = TRUE)) +
    coord_flip() +
    labs(title = "Stillbirth Rate by Study", x = NULL, y = "SBR per 1,000 total births")
  save_plot(p, "sbr_by_study.png", w = 11, h = 7)
}

if (!is.na(V_NND) && !is.na(V_LB) && !is.na(study_var) && exists("mortality_study")) {
  p <- ggplot(mortality_study %>% filter(!is.na(NND_rate)),
              aes(x = reorder(study, NND_rate), y = NND_rate, fill = NND_rate)) +
    geom_col(show.legend = FALSE) +
    scale_fill_gradient2(low = "#fee090", mid = "#fc8d59", high = "#d73027",
                         midpoint = median(mortality_study$NND_rate, na.rm = TRUE)) +
    coord_flip() +
    labs(title = "Neonatal Death Rate by Study", x = NULL, y = "NND per 1,000 live births")
  save_plot(p, "nnd_rate_by_study.png", w = 11, h = 7)
}

# ==============================================================================
# 14) BIRTH CHARACTERISTICS
# ==============================================================================
log_msg("Birth characteristics...")

if (!is.na(V_GA)) {
  dga <- tibble(ga = safe_num(df[[V_GA]])) %>% filter(!is.na(ga), ga >= 15, ga <= 45)
  if (nrow(dga) > 0) {
    p <- ggplot(dga, aes(x = ga)) +
      geom_histogram(aes(y = after_stat(density)), bins = 50, fill = "#2c7fb8", alpha = 0.7) +
      geom_density(color = "#d73027", linewidth = 1) +
      geom_vline(xintercept = 37, linetype = "dashed", color = "#d73027") +
      labs(title = "Gestational Age Distribution",
           subtitle = sprintf("N = %s | Median = %.0f weeks", fmt_n(nrow(dga)), median(dga$ga)),
           x = "GA (weeks)", y = "Density")
    save_plot(p, "ga_distribution.png")
  }
}

if (!is.na(V_BW)) {
  dbw <- tibble(bw = safe_num(df[[V_BW]])) %>% filter(!is.na(bw), bw >= 300, bw <= 6000)
  if (nrow(dbw) > 0) {
    p <- ggplot(dbw, aes(x = bw)) +
      geom_histogram(aes(y = after_stat(density)), bins = 60, fill = "#41b6c4", alpha = 0.7) +
      geom_density(color = "#253494", linewidth = 1) +
      geom_vline(xintercept = 2500, linetype = "dashed", color = "#d73027") +
      labs(title = "Birthweight Distribution",
           subtitle = sprintf("N = %s | Median = %.0fg", fmt_n(nrow(dbw)), median(dbw$bw)),
           x = "Birthweight (g)", y = "Density")
    save_plot(p, "birthweight_distribution.png")
  }
}

# Ridgeline plots by study
if (!is.na(V_GA) && !is.na(study_var)) {
  dga_s <- df %>% transmute(study = .data[[study_var]], ga = safe_num(.data[[V_GA]])) %>%
    filter(!is.na(ga), ga >= 15, ga <= 45)
  if (nrow(dga_s) > 0) {
    p <- ggplot(dga_s, aes(x = ga, y = fct_reorder(study, ga, .fun = median), fill = study)) +
      geom_density_ridges(alpha = 0.6, scale = 1.2) +
      scale_fill_viridis_d() +
      geom_vline(xintercept = 37, linetype = "dashed", color = "#d73027", linewidth = 0.5) +
      labs(title = "GA by Study (Ridgeline)", x = "GA (weeks)", y = NULL) +
      theme(legend.position = "none")
    save_plot(p, "ga_by_study_ridges.png", w = 12, h = 9)
  }
}

if (!is.na(V_BW) && !is.na(study_var)) {
  dbw_s <- df %>% transmute(study = .data[[study_var]], bw = safe_num(.data[[V_BW]])) %>%
    filter(!is.na(bw), bw >= 300, bw <= 6000)
  if (nrow(dbw_s) > 0) {
    p <- ggplot(dbw_s, aes(x = bw, y = fct_reorder(study, bw, .fun = median), fill = study)) +
      geom_density_ridges(alpha = 0.6, scale = 1.2) +
      scale_fill_viridis_d(option = "C") +
      geom_vline(xintercept = 2500, linetype = "dashed", color = "#d73027", linewidth = 0.5) +
      labs(title = "Birthweight by Study (Ridgeline)", x = "BW (g)", y = NULL) +
      theme(legend.position = "none")
    save_plot(p, "bw_by_study_ridges.png", w = 12, h = 9)
  }
}

# ==============================================================================
# 15) TABLE 1 (gtsummary)
# ==============================================================================
log_msg("Creating Table 1...")

vars_t1 <- unique(na.omit(c(
  V_AGE, V_EDU, V_MAR, V_MODE, V_MULT,
  V_GA, V_BW, sex_var, V_AP1, V_AP5,
  V_SB, V_LB, V_NND, V_PRE, V_LBW, V_SGA
)))

if (length(vars_t1) > 0) {
  df_t1 <- df %>% select(any_of(c("study_type", vars_t1)))
  cont_v <- intersect(c(V_AGE, V_GA, V_BW, V_AP1, V_AP5, V_SBP, V_DBP), names(df_t1))
  cat_v   <- setdiff(names(df_t1), c("study_type", cont_v))

  if (length(cat_v) > 0) df_t1[cat_v] <- lapply(df_t1[cat_v], as.factor)
  if (length(cont_v) > 0) df_t1[cont_v] <- lapply(df_t1[cont_v], safe_num)

  tbl1 <- df_t1 %>%
    tbl_summary(
      by = study_type,
      statistic = list(all_continuous() ~ "{mean} ({sd})", all_categorical() ~ "{n} ({p}%)"),
      digits = list(all_continuous() ~ 1, all_categorical() ~ c(0, 1)),
      missing = "ifany", missing_text = "Missing"
    ) %>%
    add_overall(last = TRUE) %>%
    bold_labels()

  gtsave(as_gt(tbl1), file.path(tbl_dir, "table1_by_study_type.html"))

  doc <- read_docx() %>%
    body_add_par("Table 1. Descriptive by Study Type", style = "heading 1") %>%
    body_add_flextable(as_flex_table(tbl1))
  print(doc, target = file.path(tbl_dir, "table1_by_study_type.docx"))

  log_msg("  Table 1 saved (HTML + DOCX)")
}

# ==============================================================================
# 16) CROSS-TABULATIONS
# ==============================================================================
log_msg("Cross-tabulations...")

# SB by maternal age
if (!is.na(V_SB) && !is.na(V_AGE)) {
  d <- tibble(sb = to01(df[[V_SB]]), age = safe_num(df[[V_AGE]])) %>%
    filter(!is.na(sb), !is.na(age), age >= 10, age <= 60) %>%
    mutate(age_cat = case_when(
      age < 18 ~ "<18", age < 20 ~ "18-19", age < 25 ~ "20-24",
      age < 30 ~ "25-29", age < 35 ~ "30-34", age < 40 ~ "35-39", TRUE ~ "40+"))
  tab <- d %>% group_by(age_cat) %>%
    summarise(N = n(), SB = sum(sb == 1), SBR = rate_1000(SB, N), .groups = "drop")
  save_csv(tab, "sb_by_maternal_age.csv")

  p <- ggplot(tab, aes(x = age_cat, y = SBR, fill = SBR)) +
    geom_col(show.legend = FALSE) + scale_fill_gradient(low = "#fee090", high = "#d73027") +
    labs(title = "Stillbirth by Maternal Age", x = "Age Group", y = "SBR per 1,000")
  save_plot(p, "sb_by_maternal_age.png", w = 9, h = 5)
}

# NND by BW
if (!is.na(V_NND) && !is.na(V_BW)) {
  d <- tibble(nnd = to01(df[[V_NND]]), bw = safe_num(df[[V_BW]])) %>%
    filter(!is.na(nnd), !is.na(bw), bw >= 300, bw <= 6000) %>%
    mutate(bw_cat = case_when(
      bw < 1000 ~ "<1000g", bw < 1500 ~ "1000-1499g",
      bw < 2500 ~ "1500-2499g", bw < 4000 ~ "2500-3999g", TRUE ~ ">=4000g"))
  tab <- d %>% group_by(bw_cat) %>%
    summarise(N = n(), NND = sum(nnd == 1), NND_rate = rate_1000(NND, N), .groups = "drop")
  save_csv(tab, "nnd_by_birthweight.csv")

  p <- ggplot(tab, aes(x = bw_cat, y = NND_rate, fill = NND_rate)) +
    geom_col(show.legend = FALSE) + scale_fill_gradient(low = "#fee090", high = "#d73027") +
    labs(title = "NND by Birthweight Category", x = "BW Category", y = "NND per 1,000")
  save_plot(p, "nnd_by_birthweight.png", w = 9, h = 5)
}

# ==============================================================================
# 17) EXPORT EXCEL WORKBOOK
# ==============================================================================
log_msg("Exporting Excel workbook...")

wb <- createWorkbook()

add_sheet <- function(wb, name, data) {
  if (!is.null(data) && is.data.frame(data) && nrow(data) > 0) {
    addWorksheet(wb, name)
    writeData(wb, name, data)
  }
}

add_sheet(wb, "missingness", miss_df)
add_sheet(wb, "domain_summary", domain_miss)
add_sheet(wb, "model_readiness", model_readiness)
add_sheet(wb, "comp_by_study", comp_by_study)
add_sheet(wb, "comp_by_type", comp_by_type)
if (exists("out_counts")) add_sheet(wb, "outcome_prevalences", out_counts)
if (exists("mortality_study")) add_sheet(wb, "mortality_by_study", mortality_study)
if (exists("mortality_country")) add_sheet(wb, "mortality_by_country", mortality_country)

saveWorkbook(wb, file.path(tbl_dir, "EDA_complete_workbook.xlsx"), overwrite = TRUE)

# ==============================================================================
# 18) SAVE FILTERED DATASET
# ==============================================================================
log_msg("Saving filtered dataset...")

saveRDS(df, file.path(DATA_DIR, "df_ssa_from2010.rds"), compress = "xz")

# Version without high-missing vars
df_clean <- df[, miss_prop[names(df)] <= MISS_THRESHOLD]
saveRDS(df_clean, file.path(DATA_DIR, "df_ssa_from2010_clean.rds"), compress = "xz")

log_msg(sprintf("  df_ssa_from2010.rds: %s rows x %s cols", fmt_n(nrow(df)), fmt_n(ncol(df))))
log_msg(sprintf("  df_ssa_from2010_clean.rds: %s rows x %s cols (removed vars >%d%% missing)",
                fmt_n(nrow(df_clean)), fmt_n(ncol(df_clean)), MISS_THRESHOLD * 100))

# ==============================================================================
# DONE
# ==============================================================================
n_tables  <- length(list.files(tbl_dir, recursive = TRUE))
n_figures <- length(list.files(fig_dir, recursive = TRUE))

cat("\n")
cat("+------------------------------------------------------------------------+\n")
cat("|  PIPELINE COMPLETE                                                      |\n")
cat(sprintf("|  Tables: %-3d | Figures: %-3d                                           |\n", n_tables, n_figures))
cat(sprintf("|  Output: %-60s |\n", normalizePath(OUT_DIR, winslash = "/")))
cat("+------------------------------------------------------------------------+\n")
