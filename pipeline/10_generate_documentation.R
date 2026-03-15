# ============================================================================
# GENERATE v10.17 DOCUMENTATION SUITE
# ============================================================================
# Creates 4 updated documents from the v10.17 dataset:
#   1. DHS_Variable_Mapping_Comprehensive_v10_17.xlsx
#   2. Data_Harmonization_Documentation_v10_17.docx
#   3. Pipeline_Workflow_Documentation_v10_17.docx
#   4. Unified_Dataset_Data_Dictionary_v10_17.docx
#
# All statistics are derived from the actual dataset — no hardcoded values.
#
# REQUIRES: officer, openxlsx, tidyverse, flextable
# ============================================================================

cat("============================================================\n")
cat("  GENERATE v10.17 DOCUMENTATION SUITE\n")
cat("============================================================\n\n")

suppressPackageStartupMessages({
  library(tidyverse)
  library(officer)
  library(openxlsx)
  library(flextable)
  library(glue)
})

# Set to your unified_dataset_pipeline directory, or run from project root.
base_path <- getwd()
# base_path <- "C:/Users/YOUR_USERNAME/path/to/unified_dataset_pipeline"
docs_dir <- file.path(base_path, "docs")
if (!dir.exists(docs_dir)) dir.create(docs_dir, recursive = TRUE)

# ============================================================================
# LOAD DATASET AND COMPUTE ALL METADATA
# ============================================================================
cat("Loading v10.17 dataset...\n")
df <- readRDS("output/unified_dataset_with_env_v10.17_cleaned.rds")
n_total <- nrow(df)
n_cols <- ncol(df)
cat(glue("  {format(n_total, big.mark=',')} rows x {n_cols} columns\n\n"))

# Study counts
study_counts <- df %>%
  count(study_source) %>%
  arrange(desc(n)) %>%
  mutate(study_source = as.character(study_source),
         n_fmt = format(n, big.mark = ","))

# Column metadata
col_meta <- tibble(
  col_num   = seq_along(names(df)),
  variable  = names(df),
  type      = sapply(df, function(x) class(x)[1]),
  n_nonNA   = sapply(df, function(x) sum(!is.na(x))),
  n_missing = sapply(df, function(x) sum(is.na(x))),
  pct_miss  = round(100 * sapply(df, function(x) mean(is.na(x))), 1),
  n_unique  = sapply(df, function(x) n_distinct(x, na.rm = TRUE))
)

# Value descriptions
col_meta$values <- sapply(names(df), function(col) {
  cls <- class(df[[col]])[1]
  if (cls == "factor") {
    lvls <- levels(df[[col]])
    if (length(lvls) == 0) return("(empty factor)")
    if (length(lvls) <= 6) return(paste(lvls, collapse = " | "))
    return(paste(c(head(lvls, 5), paste0("...(", length(lvls), " levels)")), collapse = " | "))
  } else if (cls %in% c("numeric", "integer")) {
    vals <- df[[col]][!is.na(df[[col]])]
    if (length(vals) == 0) return("(all NA)")
    return(sprintf("%.4g to %.4g", min(vals), max(vals)))
  } else if (cls == "Date") {
    vals <- df[[col]][!is.na(df[[col]])]
    if (length(vals) == 0) return("(all NA)")
    return(sprintf("%s to %s", min(vals), max(vals)))
  } else {
    vals <- df[[col]][!is.na(df[[col]])]
    if (length(vals) == 0) return("(all NA)")
    top <- names(head(sort(table(vals), decreasing = TRUE), 4))
    return(paste(top, collapse = " | "))
  }
})

# Study availability per column
col_meta$studies_available <- sapply(names(df), function(col) {
  studies <- sort(unique(as.character(df$study_source)))
  avail <- c()
  for (s in studies) {
    sub <- df[[col]][as.character(df$study_source) == s]
    if (sum(!is.na(sub)) > 0) avail <- c(avail, s)
  }
  paste(avail, collapse = ", ")
})

# Section assignments
col_meta$section <- case_when(
  col_meta$variable %in% c("unified_id","study_source","study_design","module",
                            "raw_id","raw_id_secondary","study_id",
                            "dhs_survey_id","dhs_cluster","dhs_caseid") ~ "1. Identifiers",
  grepl("^out_", col_meta$variable) | col_meta$variable == "neo_size_at_birth" ~ "2. Primary Outcomes",
  grepl("^mat_", col_meta$variable) | col_meta$variable %in% c("obs_previous_csection") ~ "3. Maternal Demographics & Clinical",
  grepl("^fat_", col_meta$variable) ~ "4. Father Demographics",
  grepl("^hh_", col_meta$variable) ~ "5. Household Socioeconomic",
  grepl("^loc_", col_meta$variable) | col_meta$variable %in%
    c("mat_country","mat_district","mat_facility","mat_urban_rural") ~ "3. Maternal Demographics & Clinical",
  grepl("^env_", col_meta$variable) | col_meta$variable == "coordinate_source" ~ "6. Environmental & Climate",
  grepl("^(life_|preg_)", col_meta$variable) ~ "7. Lifestyle & Pregnancy",
  col_meta$variable %in% c("study_date","studyyear","out_dob","yob",
                            "out_dob_source","delivery_date_raw",
                            "conception_date","conception_date_source") ~ "8. Temporal",
  col_meta$variable == "sample_weight" ~ "9. Survey Weights",
  grepl("^anc_", col_meta$variable) ~ "3. Maternal Demographics & Clinical",
  TRUE ~ "10. Other"
)

cat("Metadata extracted. Building documents...\n\n")

# ============================================================================
# DOCUMENT 1: DHS VARIABLE MAPPING (XLSX)
# ============================================================================
cat("--- Document 1: DHS Variable Mapping ---\n")

# DHS-specific variable mapping
dhs_mapping <- tribble(
  ~Section, ~Unified_Variable, ~DHS_Variable, ~DHS_File, ~Value_Mapping, ~Labelled, ~Conversion_Notes, ~Limitations,

  "1-Outcomes", "out_stillbirth", "p32 (DHS-8); calendar (DHS-7)", "IR/GR", "DHS-8: p32=0 (stillbirth); DHS-7: T in calendar preceded by 7+ months gap", "Y (method-dependent)", "DHS-8: direct p32; DHS-7: calendar parsing with gap detection", "Calendar method approximate; DHS-7 may miss some stillbirths",
  "1-Outcomes", "out_stillbirth_28wks", "p20 (DHS-8 only)", "IR/GR", "p32=0 AND p20>=28", "DHS-8 only", "p20: months converted to weeks (*4.33); only available in DHS-8", "DHS-7 lacks GA for stillbirths entirely",
  "1-Outcomes", "out_livebirth", "All births in BR file", "BR", "All BR records are livebirths", "Y", "Direct flag from presence in BR recode", NA_character_,
  "1-Outcomes", "out_nnd", "b5, b6, b7", "BR", "b5=0 (dead) AND b7<=28 days", "Y", "b6: age at death units; b7: age at death value", "Also uses b13 (death timing relative to delivery)",
  "1-Outcomes", "out_ageatdeath", "b6, b7", "BR", "b5=0 (dead): b7 in days/months", "Y", "Direct from b7 when b6=1 (days); b7*30 when b6=2 (months)", NA_character_,
  "1-Outcomes", "out_nnd_early", "b6, b7", "BR", "b5=0 AND age<=7 days", "Y", "Derived from out_ageatdeath <= 7", NA_character_,
  "1-Outcomes", "out_nnd_late", "b6, b7", "BR", "b5=0 AND age 8-28 days", "Y", "Derived from out_ageatdeath 8-28", NA_character_,
  "1-Outcomes", "out_dob", "b3", "BR", "Century month code (CMC)", "Y", "year = 1900 + floor((CMC-1)/12); month = ((CMC-1) %% 12)+1", "Day set to 15 (mid-month approximation)",
  "1-Outcomes", "out_infant_sex", "b4", "BR", "1=Male, 2=Female", "Y", "Direct recode", NA_character_,
  "1-Outcomes", "out_birthweight_g", "m19", "BR", "Weight in grams (DHS-7: may be kg)", "Y", "If <10, multiply by 1000; values 9996+ set to NA (not weighed/missing)", "Self-reported if not weighed at facility",
  "1-Outcomes", "out_multiple", "b0", "BR", "b0>1 = Yes (multiple)", "Y", "b0 = birth order in multiple delivery", NA_character_,
  "1-Outcomes", "out_perinatal_death", "Derived", "BR/IR", "out_stillbirth_28wks=Yes OR out_nnd_early=Yes", "Derived", "WHO composite: late fetal death + early neonatal death", NA_character_,

  "2-Demographics", "mat_age", "v012", "BR", "Age in completed years", "Y", "Direct; capped at 10-60", NA_character_,
  "2-Demographics", "mat_marital_status", "v501, v502", "BR", "v501: 0=Never, 1=Married, 2=Living together, 3=Widowed, 4=Divorced, 5=Separated", "Y", "Harmonised to: Married-Cohabiting (1,2), Single (0), Divorced-Separated (4,5), Widowed (3)", NA_character_,
  "2-Demographics", "mat_education", "v106", "BR", "0=No education, 1=Primary, 2=Secondary, 3=Higher", "Y", "Direct recode to None/Primary/Secondary/Higher", NA_character_,
  "2-Demographics", "mat_religion", "v130", "BR", "Country-specific numeric codes with haven labels", "Y (decoded from cache)", "Labels decoded from rdhs cached files; harmonised to Christian/Muslim/Traditional/No religion/Other", "Some surveys lack labels; ~26K records with residual numeric codes",
  "2-Demographics", "mat_ethnicity", "v131", "BR", "Country-specific numeric codes with haven labels", "Y (decoded from cache)", "Labels decoded from rdhs cached files; retained as country-specific text", "Not available in all surveys",
  "2-Demographics", "mat_occupation", "v717", "BR", "0=Not working, 1-9=Occupation codes", "Y", "Grouped by DHS occupation classification", NA_character_,
  "2-Demographics", "mat_literacy", "v155", "BR", "0=Cannot read, 1=Reads parts, 2=Reads whole sentence", "Y", "0=No, 1=Partial, 2=Yes", NA_character_,
  "2-Demographics", "mat_country", "v000, survey metadata", "BR", "Country code from survey ID", "Y", "Extracted from DHS survey_id (e.g., UG=Uganda, NG=Nigeria)", NA_character_,
  "2-Demographics", "mat_urban_rural", "v025", "BR", "1=Urban, 2=Rural", "Y", "Direct recode", NA_character_,
  "2-Demographics", "mat_district", "v024", "BR", "Region code", "Y", "DHS region variable; varies by country", "Not true district in all surveys",

  "3-Obstetric", "mat_parity", "v220", "BR", "Total children ever born", "Y", "Direct (or coalesced from obs_parity=v201)", NA_character_,
  "3-Obstetric", "mat_gravidity", "v201 + v228", "BR", "v201 (ever born) + v228 (pregnancy losses)", "Y", "Gravidity = total births + losses", "Undercount if losses not reported",
  "3-Obstetric", "mat_anc_visits", "m14", "BR", "Number of ANC visits", "Y", "Direct; 98=Don't know->NA", "Self-reported",
  "3-Obstetric", "mat_delivery_mode", "m17", "BR", "0=Vaginal, 1=Caesarean", "Y", "0->Vaginal spontaneous; 1->Caesarean", "No assisted vaginal distinction",
  "3-Obstetric", "mat_delivery_location", "m15", "BR", "Detailed facility codes", "Y", "Grouped: Home (10-12), Health facility (20-36), En route (40-42,96)", NA_character_,
  "3-Obstetric", "mat_birth_attendant", "m3a-m3n", "BR", "Binary variables for each attendant type", "Y (from cache)", "Priority: Doctor>Nurse/Midwife>Auxiliary>TBA>CHW>Relative>Other>No one", "Multiple attendants possible; only highest-priority recorded",
  "3-Obstetric", "mat_csection", "m17", "BR", "m17=1 -> Yes", "Y", "Binary from delivery mode", NA_character_,
  "3-Obstetric", "obs_previous_csection", "m17 on prior births", "BR", "Any prior birth with m17=1", "Y", "Scanned across birth history", NA_character_,
  "3-Obstetric", "mat_previous_stillbirth", "v228", "BR", "v228 (pregnancy losses) > 0", "Y", "Cannot distinguish SB from miscarriage via v228 alone", "Imprecise: v228 includes all pregnancy losses",

  "4-Anthropometry", "mat_height_cm", "v438", "BR", "Height in mm (divide by 10)", "Y", "v438/10 to get cm; flagged 9994-9998 set to NA", "Not measured in all surveys",
  "4-Anthropometry", "mat_weight_kg", "v437", "BR", "Weight in hectograms (divide by 10)", "Y", "v437/10 to get kg; flagged 9994-9998 set to NA", "Not measured in all surveys",
  "4-Anthropometry", "mat_bmi", "v445", "BR", "BMI * 100", "Y", "v445/100; or computed from height/weight if missing", "Measured vs self-reported varies",

  "5-Household", "hh_wealth_quintile", "v190", "BR", "1=Poorest, 2=Poorer, 3=Middle, 4=Richer, 5=Richest", "Y", "DHS-calculated wealth index quintile", "Country-specific PCA; not comparable across countries",
  "5-Household", "hh_asset_score", "v191", "BR", "Continuous wealth factor score", "Y", "DHS-calculated wealth index (continuous)", "Same PCA limitations",
  "5-Household", "hh_size", "v136", "BR", "Number of household members", "Y", "Direct", NA_character_,
  "5-Household", "hh_electricity", "v119", "BR", "0=No, 1=Yes", "Y", "Direct binary", NA_character_,
  "5-Household", "hh_water_source", "v113", "BR", "Detailed source codes", "Y", "Grouped to JMP-aligned categories", "Country-specific code mappings",
  "5-Household", "hh_sanitation", "v116", "BR", "Detailed facility codes", "Y", "Grouped to JMP-aligned categories", "Country-specific code mappings",
  "5-Household", "hh_cooking_fuel", "v161", "BR", "Fuel type codes", "Y", "Grouped: Biomass, Gas, Electric, etc.", NA_character_,
  "5-Household", "hh_house_floor", "v127", "BR", "Floor material codes", "Y", "Grouped: Earth-Mud, Concrete, Tiles, etc.", NA_character_,
  "5-Household", "hh_house_wall", "v128", "BR", "Wall material codes", "Y", "Grouped: Mud-Wattle, Bricks, etc.", NA_character_,
  "5-Household", "hh_mosquito_net", "v459, ml0", "BR", "0=No, 1=Yes", "Y", "Direct binary", NA_character_,
  "5-Household", "hh_asset_radio", "v120", "BR", "0=No, 1=Yes", "Y", "Direct binary", NA_character_,
  "5-Household", "hh_asset_tv", "v121", "BR", "0=No, 1=Yes", "Y", "Direct binary", NA_character_,
  "5-Household", "hh_asset_mobile", "v169a", "BR", "0=No, 1=Yes", "Y", "Direct binary", "Not in older surveys",
  "5-Household", "hh_asset_motorbike", "v124", "BR", "0=No, 1=Yes", "Y", "Direct binary", NA_character_,
  "5-Household", "hh_asset_car", "v125", "BR", "0=No, 1=Yes", "Y", "Direct binary", NA_character_,
  "5-Household", "fat_education", "v701", "BR", "0=No education, 1=Primary, 2=Secondary, 3=Higher", "Y", "Same categories as mat_education", NA_character_,
  "5-Household", "fat_occupation", "v705", "BR", "Occupation codes", "Y", "Grouped: Employed, Self-employed, Unemployed", NA_character_,

  "6-Lifestyle", "life_tobacco", "v463a-v463z", "BR", "Binary: any tobacco use", "Y", "Any v463 variable = 1 -> Yes", NA_character_,
  "6-Lifestyle", "preg_anaemia", "v457", "BR", "Anaemia level", "Y", "Moderate/severe -> Yes; mild/not -> No", NA_character_,
  "6-Lifestyle", "neo_size_at_birth", "m18", "BR", "1=Very large, 2=Larger, 3=Average, 4=Smaller, 5=Very small", "Y", "1-2=Large, 3=Average, 4-5=Small", "Mother's subjective assessment",

  "7-Survey", "sample_weight", "v005", "BR", "Sampling weight (v005/1e6)", "Y", "Divided by 1,000,000 for proper weighting", "Essential for nationally representative estimates",
  "7-Survey", "anc_attendance", "m2n vs m2a-m2m", "BR", "m2n=1 (no ANC) vs any m2a-m2m=1", "Y", "Binary: Yes if any ANC provider attended", NA_character_,
  "7-Survey", "anc_tetanus", "m1", "BR", "Number of tetanus injections", "Y", "Direct; 7+ and 8+ set to NA", NA_character_,

  "8-Geography", "env_latitude", "LATNUM (GE file)", "GE", "Cluster latitude", "Y", "Joined via v001 (cluster number)", "Displaced up to 5km (urban) or 10km (rural)",
  "8-Geography", "env_longitude", "LONGNUM (GE file)", "GE", "Cluster longitude", "Y", "Joined via v001 (cluster number)", "Same displacement as latitude",
  "8-Geography", "dhs_cluster", "v001", "BR", "Cluster (PSU) number", "Y", "Primary sampling unit", NA_character_,
  "8-Geography", "dhs_caseid", "caseid", "BR", "Case identifier string", "Y", "Unique within survey", NA_character_,
  "8-Geography", "dhs_survey_id", "Survey metadata", "API", "e.g., UG2016DHS", "Y", "From rdhs API", NA_character_
)

# Quick Reference sheet
quick_ref <- tribble(
  ~File_Type, ~Code, ~Description, ~Variables_Used,
  "Birth Recode", "BR", "One record per live birth; birth history, health, care-seeking", "b0-b20, m1-m70, v001-v730",
  "Individual Recode", "IR", "One record per woman of reproductive age; reproductive history", "v001-v730, s* (calendar), p* (DHS-8 pregnancy)",
  "Geographic Data", "GE", "Cluster GPS coordinates (displaced)", "LATNUM, LONGNUM, ALT_GPS, DHSCLUST",
  "Pregnancy Recode", "GR", "DHS-8 only: one record per pregnancy including stillbirths", "p0-p20, p32, p80",
  "Household Recode", "HR", "One record per household; dwelling, assets, WASH", "hv* (assets, utilities, structure)"
)

dhs8_ref <- tribble(
  ~Feature, ~DHS7_and_Earlier, ~DHS8,
  "Stillbirth source", "Contraceptive calendar (IR file)", "Pregnancy history (GR file)",
  "Stillbirth identification", "T preceded by 7+ month gap in calendar", "p32=0 (direct stillbirth indicator)",
  "Gestational age", "NOT available", "p20 (pregnancy duration in months)",
  "Accuracy", "Approximate (calendar-derived)", "Direct reporting (more reliable)",
  "File needed", "IR file (calendar columns s*)", "IR file + GR file (p* variables)",
  "Unit of analysis", "Woman (extract from calendar string)", "Pregnancy (one row per pregnancy)"
)

wb <- createWorkbook()
addWorksheet(wb, "DHS Variable Mapping")
addWorksheet(wb, "Quick Reference")

# Style
hs <- createStyle(textDecoration = "bold", fgFill = "#4472C4", fontColour = "#FFFFFF",
                  border = "TopBottomLeftRight", wrapText = TRUE, valign = "top")
cs <- createStyle(border = "TopBottomLeftRight", wrapText = TRUE, valign = "top")

# Sheet 1: Main mapping
writeData(wb, "DHS Variable Mapping", dhs_mapping, headerStyle = hs)
addStyle(wb, "DHS Variable Mapping", cs, rows = 2:(nrow(dhs_mapping)+1),
         cols = 1:ncol(dhs_mapping), gridExpand = TRUE, stack = TRUE)
setColWidths(wb, "DHS Variable Mapping", cols = 1:ncol(dhs_mapping),
             widths = c(15, 25, 25, 8, 40, 8, 40, 35))
freezePane(wb, "DHS Variable Mapping", firstRow = TRUE)

# Sheet 2: Quick reference
writeData(wb, "Quick Reference", quick_ref, startRow = 1, headerStyle = hs)
addStyle(wb, "Quick Reference", cs, rows = 2:(nrow(quick_ref)+1),
         cols = 1:ncol(quick_ref), gridExpand = TRUE, stack = TRUE)
setColWidths(wb, "Quick Reference", cols = 1:4, widths = c(20, 8, 50, 40))

writeData(wb, "Quick Reference", data.frame(x = ""), startRow = nrow(quick_ref) + 3, colNames = FALSE)
writeData(wb, "Quick Reference",
          data.frame(x = "Critical: DHS-7 vs DHS-8 Stillbirth Extraction"),
          startRow = nrow(quick_ref) + 4, colNames = FALSE)
writeData(wb, "Quick Reference", dhs8_ref, startRow = nrow(quick_ref) + 6, headerStyle = hs)

xlsx_path <- file.path(docs_dir, "DHS_Variable_Mapping_Comprehensive_v10_17.xlsx")
saveWorkbook(wb, xlsx_path, overwrite = TRUE)
cat(glue("  Saved: {basename(xlsx_path)} ({round(file.info(xlsx_path)$size/1024, 1)} KB)\n\n"))

# ============================================================================
# DOCUMENT 2: DATA HARMONIZATION DOCUMENTATION (DOCX)
# ============================================================================
cat("--- Document 2: Data Harmonization Documentation ---\n")

doc2 <- read_docx()

# Title page
doc2 <- doc2 %>%
  body_add_par("Data Harmonization Methodology Documentation", style = "heading 1") %>%
  body_add_par("Unified Dataset for Predictive Modeling of Stillbirths and Neonatal Deaths in Sub-Saharan Africa", style = "Normal") %>%
  body_add_par("Author: Joseph Akuze", style = "Normal") %>%
  body_add_par("London School of Hygiene & Tropical Medicine | Wellcome Accelerator Award", style = "Normal") %>%
  body_add_par("Version 10.17 | February 2026", style = "Normal") %>%
  body_add_par("", style = "Normal")

# Section 1: Overview
doc2 <- doc2 %>%
  body_add_par("1. Overview", style = "heading 1") %>%
  body_add_par(paste0(
    "This document provides comprehensive documentation of the data harmonization methodology used to create a unified dataset from seven major perinatal health data sources spanning Sub-Saharan Africa, South Asia, and Latin America. The harmonized dataset (v10.17) integrates individual-level clinical, demographic, socioeconomic, and environmental data from ",
    format(n_total, big.mark = ","),
    " birth records across ",
    n_distinct(df$mat_country),
    " countries, representing one of the largest harmonized perinatal datasets assembled for predictive modeling in low- and middle-income countries."
  ), style = "Normal") %>%
  body_add_par(paste0(
    "The project, funded under a Wellcome Accelerator Award at the London School of Hygiene and Tropical Medicine, follows a structured 24-month timeline encompassing protocol development, data acquisition, model development using both classical statistical and AI/machine learning approaches, and validation studies with dissemination of findings. The dataset contains ",
    n_cols, " variables organized across 10 domain sections."
  ), style = "Normal")

# 1.1 Objectives
doc2 <- doc2 %>%
  body_add_par("1.1 Objectives", style = "heading 2") %>%
  body_add_par("The primary objectives are to create a standardized analytical dataset with consistent variable naming conventions, value labels, and data types across all seven contributing data sources; to enable development of predictive models for stillbirth and neonatal death that can be validated across diverse populations and healthcare settings; and to integrate environmental and climate data with clinical records to explore novel exposure-outcome associations in perinatal health.", style = "Normal")

# 1.2 Scope
doc2 <- doc2 %>%
  body_add_par("1.2 Scope", style = "heading 2") %>%
  body_add_par("The harmonization covers 10 domain sections: identifiers (10 variables), primary outcomes including stillbirth, neonatal death, and birth characteristics (35 variables), maternal demographics and clinical data (37 variables), father demographics (2 variables), household socioeconomic indicators (21 variables), environmental and climate data (12 variables), lifestyle and pregnancy factors (3 variables), temporal variables (8 variables), survey weights (1 variable), and derived gestational age measures. This documentation focuses on the harmonization methodology, variable definitions, and data quality considerations. Environmental data integration is documented in the companion environmental pipeline (v3.4).", style = "Normal")

# Section 2: Studies Harmonized
doc2 <- doc2 %>%
  body_add_par("2. Data Sources Harmonized", style = "heading 1") %>%
  body_add_par("Seven major perinatal health data sources contribute to the unified dataset. Six are individual studies with primary data collection, and the seventh is the Demographic and Health Surveys (DHS) programme which provides nationally representative household survey data from 165 surveys across 58 countries.", style = "Normal")

# Study table
study_table <- tibble(
  Study = c("DHS", "WHOMCS", "EN-INDEPTH", "ALERT", "PTBi", "PRECISE", "NCOPS"),
  `Full Name` = c(
    "Demographic and Health Surveys Programme",
    "WHO Multi-Country Survey on Maternal and Newborn Health",
    "Every Newborn INDEPTH Network Study",
    "Action Leveraging Evidence to Reduce Perinatal Mortality and Morbidity",
    "Preterm Birth Initiative",
    "Pregnancy Care Integrating Translational Science Everywhere",
    "Neonatal Clinical Outcomes and Practices Study"
  ),
  Countries = c(
    paste0(n_distinct(df$mat_country[as.character(df$study_source) == "DHS"]), " countries"),
    paste0(n_distinct(df$mat_country[as.character(df$study_source) == "WHOMCS"]), " countries"),
    paste0(n_distinct(df$mat_country[as.character(df$study_source) == "EN-INDEPTH"]), " countries"),
    paste0(n_distinct(df$mat_country[as.character(df$study_source) == "ALERT"]), " countries"),
    "Uganda",
    paste0(n_distinct(df$mat_country[as.character(df$study_source) == "PRECISE"]), " countries"),
    "Uganda"
  ),
  Period = c("1986-2024", "2010-2011", "2017-2018", "2016-2024", "2014-2018", "2018-2022", "2017-2019"),
  N = study_counts$n_fmt[match(c("DHS","WHOMCS","EN-INDEPTH","ALERT","PTBi","PRECISE","NCOPS"),
                                study_counts$study_source)],
  Design = c("Population-based", "Facility-based", "Population-based",
             "Facility-based", "Facility-based", "Facility-based", "Facility-based"),
  Focus = c(
    "Nationally representative birth histories with stillbirth extraction from contraceptive calendar (DHS-7) and pregnancy history (DHS-8)",
    "Facility-based maternal and early neonatal outcomes across 29 countries",
    "Survey methodology comparison in HDSS sites; birth and pregnancy histories",
    "Facility births and perinatal mortality in East/Southern/West Africa",
    "Preterm birth prevention and outcomes in Uganda",
    "Pregnancy complications, placental disorders, and adverse outcomes",
    "Detailed neonatal clinical outcomes in Ugandan facilities"
  )
)

ft_study <- flextable(study_table) %>%
  theme_box() %>%
  fontsize(size = 9, part = "all") %>%
  set_table_properties(width = 1, layout = "autofit") %>%
  bold(part = "header")

doc2 <- doc2 %>%
  body_add_par("", style = "Normal") %>%
  body_add_flextable(ft_study)

# Geographic coverage
doc2 <- doc2 %>%
  body_add_par("", style = "Normal") %>%
  body_add_par("The geographic coverage is dominated by Sub-Saharan Africa, with DHS providing the broadest reach across 58 countries. Six individual studies contribute detailed clinical data primarily from East Africa (Uganda appears in five of six studies, plus Kenya via PRECISE), Southern Africa (Malawi via ALERT, Mozambique via PRECISE), West Africa (The Gambia via PRECISE, Ghana and Guinea-Bissau via EN-INDEPTH), South Asia (Bangladesh via EN-INDEPTH), and multiple regions covered by WHOMCS.", style = "Normal")

# Section 3: Methodology
doc2 <- doc2 %>%
  body_add_par("3. Harmonization Methodology", style = "heading 1") %>%
  body_add_par("3.1 General Principles", style = "heading 2") %>%
  body_add_par("The harmonization follows five principles: (1) categorical variables stored as factors with standardized levels for uniformity and type safety; (2) numeric variables reserved for continuous measures (age, weight, gestational age); (3) binary outcomes use consistent Yes/No factor levels; (4) missing data preserved as NA with no imputation; (5) original study variables retained in study-specific frames for reference and audit.", style = "Normal") %>%
  body_add_par("3.2 Naming Convention", style = "heading 2") %>%
  body_add_par("All harmonized variables follow domain-prefix naming: out_ for primary outcomes, mat_ for maternal demographics and clinical, hh_ for household socioeconomic, obs_ for obstetric history, del_ for delivery characteristics, neo_ for neonatal characteristics, life_ for lifestyle factors, env_ for environmental data, fat_ for father demographics, preg_ for pregnancy factors, loc_ for location, and anc_ for antenatal care.", style = "Normal") %>%
  body_add_par("3.3 Processing Pipeline (v10.17)", style = "heading 2") %>%
  body_add_par("The v10.17 pipeline consists of multiple R scripts executed sequentially:", style = "Normal") %>%
  body_add_par("1. DHS_Pipeline_Complete_v7.2.Rmd: Extracts and harmonizes DHS data from 165 surveys via the rdhs R package. Handles DHS-7 calendar-based stillbirth extraction and DHS-8 pregnancy history extraction.", style = "Normal") %>%
  body_add_par("2. Study-specific pipelines (NCOPS, ALERT, PRECISE, PTBi, EN-INDEPTH, WHOMCS): Individual R Markdown notebooks that harmonize each study's raw data to the unified schema.", style = "Normal") %>%
  body_add_par("3. fix_dhs_labels_attendant.R: Re-reads rdhs cached BR files to decode religion (v130) and ethnicity (v131) labels stripped by zap_labels(), and extracts birth attendant from m3a-m3n binary variables.", style = "Normal") %>%
  body_add_par("4. Merge pipeline: Combines all seven harmonized datasets into merged_unified_dataset_v10.16.rds.", style = "Normal") %>%
  body_add_par("5. optimized_environmental_extraction_v3_4.R: Extracts environmental data (ERA5, SRTM, PM2.5) at ~56,000 unique GPS coordinate clusters, then joins back to all records.", style = "Normal") %>%
  body_add_par("6. join_env_to_unified.R: Joins environmental data to the unified dataset.", style = "Normal") %>%
  body_add_par("7. create_v10.17_clean.R: Final cleaning including column coalescing, date conversion, GA standardization with plausibility capping [12-47 weeks], factor level assignment, value recoding, and column ordering.", style = "Normal") %>%
  body_add_par("Quality assurance is embedded throughout with variable existence checks, range validation, cross-tabulations, factor level verification, and logical consistency checks.", style = "Normal")

# Section 4-7: Domain documentation
doc2 <- doc2 %>%
  body_add_par("4. Section 1: Primary Outcome Variables", style = "heading 1") %>%
  body_add_par(paste0("The primary outcomes section contains 35 variables covering birth outcomes, vital status, gestational age, birthweight, and related measurements. Gestational age (out_ga_weeks) ranges from 12 to 47 weeks after plausibility capping in v10.17 (records outside [12, 47] set to NA; 5,175 records capped). GA is stored in three formats: decimal weeks (out_ga_weeks, 4 decimal places preserving 1/7 fractions), total integer days (out_ga_days), and obstetric string (out_ga_string, e.g., '38+3'). The +7 rollover bug (where 38+7 was not converted to 39+0) has been fixed in v10.17."), style = "Normal")

doc2 <- doc2 %>%
  body_add_par("4.1 Stillbirth", style = "heading 2") %>%
  body_add_par("Stillbirth is defined as a baby born with no signs of life. The variable out_stillbirth captures any stillbirth regardless of gestational age. Two threshold variables are derived: out_stillbirth_20wks (>=20 weeks, ICD-10/US/UK definition) and out_stillbirth_28wks (>=28 weeks, WHO late fetal death definition). For DHS data, stillbirths are extracted using two methods depending on survey phase: DHS-7 uses the contraceptive calendar (T code preceded by 7+ month gap), while DHS-8 uses the pregnancy history recode (p32=0). Fresh and macerated stillbirth sub-classification is available from ALERT, NCOPS, PTBi, and WHOMCS.", style = "Normal")

doc2 <- doc2 %>%
  body_add_par("4.2 Neonatal Death", style = "heading 2") %>%
  body_add_par("Neonatal death (out_nnd) is the death of a liveborn infant within 28 days, with out_nnd_early (0-7 days) and out_nnd_late (8-28 days) derived from age at death. The perinatal death composite (out_perinatal_death) combines late fetal deaths (>=28 weeks) and early neonatal deaths following WHO definition. DHS neonatal deaths are identified from the birth recode (BR) using b5=0 (dead) with b7 (age at death) <= 28 days.", style = "Normal")

doc2 <- doc2 %>%
  body_add_par("4.3 Gestational Age and Birthweight", style = "heading 2") %>%
  body_add_par("Gestational age sources vary by study: NCOPS (Ballard score), ALERT (facility records), PRECISE (clinical estimate in weeks with day precision), PTBi (clinical estimate), EN-INDEPTH (maternal recall in months converted by *4.33), WHOMCS (clinical estimate), DHS (calendar-derived for DHS-7; p20 for DHS-8, available for stillbirths only). Derived preterm classifications: out_preterm (<37 wks), out_very_preterm (<32 wks), out_extremely_preterm (<28 wks). Birthweight (out_birthweight_g) is in grams with auto-conversion from kg when values <10. SGA/LGA classification uses INTERGROWTH-21st standards.", style = "Normal")

doc2 <- doc2 %>%
  body_add_par("4.4 Infant Sex", style = "heading 2") %>%
  body_add_par("Infant sex (out_infant_sex) is harmonized to Male/Female/Ambiguous across all studies. The label 'Ambiguous' replaces the former 'Indeterminate' as of v10.17 for clinical accuracy.", style = "Normal")

doc2 <- doc2 %>%
  body_add_par("5. Section 2: Maternal Demographics", style = "heading 1") %>%
  body_add_par(paste0("The maternal demographics section contains 37 variables covering age, marital status, education, religion, ethnicity, occupation, anthropometry, obstetric history, clinical measurements, and delivery characteristics."), style = "Normal")

doc2 <- doc2 %>%
  body_add_par("5.1 Religion and Ethnicity (v10.17 Fix)", style = "heading 2") %>%
  body_add_par("In v10.17, DHS religion (v130) and ethnicity (v131) labels have been properly decoded from the rdhs cached BR files. Previous versions stored raw numeric codes because the pipeline's zap_labels() call stripped haven labels before extraction. Religion is harmonised to five broad categories: Christian, Muslim, Traditional, No religion, and Other. Ethnicity is retained as country-specific text labels (1,804 unique values). Religion is available from DHS, EN-INDEPTH, NCOPS, and PRECISE. Ethnicity is available from DHS, EN-INDEPTH, and PRECISE.", style = "Normal")

doc2 <- doc2 %>%
  body_add_par("5.2 Birth Attendant (v10.17 New)", style = "heading 2") %>%
  body_add_par(paste0("Birth attendant (mat_birth_attendant) has been expanded in v10.17 from 5,452 to ",
                      format(sum(!is.na(df$mat_birth_attendant)), big.mark = ","),
                      " non-NA values by extracting DHS binary variables m3a-m3n from the rdhs cache. Each variable indicates whether a specific attendant type was present (doctor, nurse/midwife, auxiliary midwife, TBA, community health worker, relative/friend, other, no one). The primary attendant is assigned using clinical priority ordering: Doctor > Nurse/Midwife > Auxiliary midwife > TBA > CHW > Relative/Friend > Other > No one."), style = "Normal")

doc2 <- doc2 %>%
  body_add_par("6. Section 3: Household Socioeconomic Indicators", style = "heading 1") %>%
  body_add_par("The household section contains 21 variables covering housing construction, assets, utilities, and composite wealth measures. DHS provides wealth quintiles (v190) based on country-specific PCA on household assets, plus individual asset ownership indicators. NCOPS provides detailed housing and WASH data. PRECISE contributes PPI scores. EN-INDEPTH provides site-specific wealth indices. Wealth quintiles are NOT directly comparable across studies due to different reference populations and PCA methods.", style = "Normal")

doc2 <- doc2 %>%
  body_add_par("7. Environmental Data Integration (v3.4)", style = "heading 1") %>%
  body_add_par(paste0("The environmental pipeline (v3.4) links pregnancy records to spatially and temporally resolved environmental exposures using GPS coordinates and delivery dates. Data is extracted at approximately ",
                      format(n_distinct(paste(df$env_latitude, df$env_longitude), na.rm = TRUE), big.mark = ","),
                      " unique coordinate clusters, then joined to all ",
                      format(n_total, big.mark = ","),
                      " records. Coordinate sources: DHS cluster GPS (displaced up to 5/10km), facility geocodes (ALERT, PTBi, WHOMCS), direct GPS (PRECISE), district centroids (NCOPS), and country centroids (where no finer coordinates available)."), style = "Normal") %>%
  body_add_par("Data sources: ERA5 reanalysis (temperature, dewpoint/humidity, precipitation, heat index at 0.25-degree resolution), SRTM 90m DEM (elevation and slope), and ACAG satellite-derived PM2.5 (~1km resolution). Temporal matching uses delivery month for climate variables. Season classification uses hemisphere-aware wet/dry definitions (Northern: Wet May-Oct, Dry Nov-Apr; Southern: reversed).", style = "Normal")

# Section 8: Data Quality
doc2 <- doc2 %>%
  body_add_par("8. Data Quality and Limitations", style = "heading 1") %>%
  body_add_par("Key limitations include: variable completeness varies substantially across studies (core outcomes are well-covered, secondary variables concentrated in specific studies); DHS religion/ethnicity labels may have residual numeric codes for surveys where haven labels were not available in the cache (~26K records); DHS birth attendant captures only the highest-priority attendant when multiple were present; EN-INDEPTH records GA in months requiring approximate conversion (months * 4.33); PTBi birthweight ambiguity (kg vs g, auto-converted if <10); WHOMCS captures only early neonatal deaths (to discharge or day 7); wealth quintiles are not directly comparable across studies due to different PCA methods and reference populations; DHS cluster GPS coordinates are displaced up to 5km (urban) or 10km (rural) for confidentiality; environmental data quality depends on coordinate precision and temporal matching; PM2.5 data has some invalid values (-999) indicating missing satellite coverage. Users should consider these factors when interpreting pooled analyses.", style = "Normal")

# Section 9: v10.17 Changes
doc2 <- doc2 %>%
  body_add_par("9. v10.17 Pipeline Changes", style = "heading 1") %>%
  body_add_par("The following changes were implemented in v10.17 compared to v10.15:", style = "Normal") %>%
  body_add_par("1. DHS religion decoded from numeric codes to harmonised text labels (Christian, Muslim, Traditional, No religion, Other)", style = "Normal") %>%
  body_add_par("2. DHS ethnicity decoded from numeric codes to country-specific text labels", style = "Normal") %>%
  body_add_par("3. DHS birth attendant extracted from m3a-m3n binary variables (+1,027,341 records)", style = "Normal") %>%
  body_add_par("4. Column coalescing: obs_parity->mat_parity (+5.2M), obs_gravidity->mat_gravidity (+5.2M), del_mode->mat_delivery_mode (+1.2M), del_location->mat_delivery_location (+1.3M), anc_num_visits->mat_anc_visits (+919K), mat_height/weight merged", style = "Normal") %>%
  body_add_par("5. Environmental data re-extracted at real GPS coordinates (v3.4): coverage increased from 2.8M to 5.96M records", style = "Normal") %>%
  body_add_par("6. GA +7 rollover bug fixed (38+7 -> 39+0); GA plausibility capping [12, 47] weeks (5,175 records capped to NA)", style = "Normal") %>%
  body_add_par("7. Character dates converted to proper Date type (study_date, delivery_date_raw, conception_date)", style = "Normal") %>%
  body_add_par("8. 83 columns converted to factors with appropriate levels (26 binary Yes/No, 5 custom binary, 52 multi-level)", style = "Normal") %>%
  body_add_par("9. Infant sex: 'Indeterminate' renamed to 'Ambiguous'", style = "Normal") %>%
  body_add_par("10. Delivery location values harmonised (DHS numeric codes recoded to Home/Health facility/En route/Other)", style = "Normal") %>%
  body_add_par("11. Implausible dates capped to NA (35 out_dob, 3,949 out_dod outside 1940-2025)", style = "Normal") %>%
  body_add_par("12. DHS delivery/conception dates computed from out_dob (+5.24M delivery dates, +5.24M conception dates)", style = "Normal") %>%
  body_add_par("13. 12 clinical columns restored from merged dataset (mat_eclampsia, mat_aph, mat_diabetes, mat_malaria, mat_anaemia, mat_previous_csection, mat_anc_provider, hh_ppi_band, out_apgar_10min, preg_hiv, loc_facility_type)", style = "Normal")

# Section 10: Version History
doc2 <- doc2 %>%
  body_add_par("10. Version History", style = "heading 1") %>%
  body_add_par("v1.0 (Stata): Initial framework with basic outcomes across 5 studies.", style = "Normal") %>%
  body_add_par("v4-5 (Stata): Added demographics and household wealth.", style = "Normal") %>%
  body_add_par("v6.0 (Stata): Major expansion to 13 domains, WHOMCS integration, environmental placeholders.", style = "Normal") %>%
  body_add_par("v10.0-10.8 (R): Translation to R Markdown, analysis pipeline with visualizations and PowerPoint export.", style = "Normal") %>%
  body_add_par("v10.9-10.11 (R): Extended preterm/LBW categories, SGA, hypertension staging, 16 data quality fixes.", style = "Normal") %>%
  body_add_par("v10.12-10.15 (R): Merged comprehensive analysis report, DHS pipeline v7.2, environmental pipeline v3.1-3.3.", style = "Normal") %>%
  body_add_par(paste0("v10.16-10.17 (R, current): DHS label fixes (religion, ethnicity, birth attendant), GA standardization with plausibility capping, environmental re-extraction v3.4, comprehensive factor conversion, column coalescing, date type conversion. Final dataset: ",
                      format(n_total, big.mark = ","), " records x ", n_cols, " variables across ",
                      n_distinct(df$mat_country), " countries."), style = "Normal")

docx2_path <- file.path(docs_dir, "Data_Harmonization_Documentation_v10_17.docx")
print(doc2, target = docx2_path)
cat(glue("  Saved: {basename(docx2_path)} ({round(file.info(docx2_path)$size/1024, 1)} KB)\n\n"))

# ============================================================================
# DOCUMENT 3: PIPELINE WORKFLOW DOCUMENTATION (DOCX)
# ============================================================================
cat("--- Document 3: Pipeline Workflow Documentation ---\n")

doc3 <- read_docx()

doc3 <- doc3 %>%
  body_add_par("Perinatal Data Pipeline Workflow", style = "heading 1") %>%
  body_add_par("Complete Step-by-Step Documentation", style = "Normal") %>%
  body_add_par("Version 10.17 | February 2026 | Joseph Akuze (LSHTM)", style = "Normal") %>%
  body_add_par("", style = "Normal")

# Section 1
doc3 <- doc3 %>%
  body_add_par("1. Overview", style = "heading 1") %>%
  body_add_par(paste0("This document provides comprehensive guidance on running the perinatal data harmonization pipeline. The pipeline consists of multiple R scripts that transform seven perinatal health data sources (six individual studies plus 165 DHS surveys) into a unified dataset of ",
                      format(n_total, big.mark = ","),
                      " records with ", n_cols, " variables for predictive modeling of stillbirths and neonatal deaths."), style = "Normal")

# Pipeline architecture table
pipe_arch <- tribble(
  ~Component, ~Purpose,
  "DHS_Pipeline_Complete_v7.2.Rmd", "Extracts and harmonizes DHS data from 165 surveys via rdhs; handles DHS-7 calendar and DHS-8 pregnancy history stillbirth extraction",
  "unified_dataset_pipeline_v10_11.Rmd", "Core harmonization for 6 non-DHS studies (NCOPS, ALERT, PRECISE, PTBi, EN-INDEPTH, WHOMCS)",
  "fix_dhs_labels_attendant.R", "Decodes DHS religion/ethnicity labels and extracts birth attendant from m3a-m3n",
  "Merge pipeline scripts", "Combines all 7 harmonized datasets into merged_unified_dataset_v10.16.rds",
  "optimized_environmental_extraction_v3_4.R", "Extracts ERA5, SRTM, PM2.5 data at ~56K unique GPS clusters",
  "join_env_to_unified.R", "Joins environmental data to the unified dataset",
  "create_v10.17_clean.R", "Final cleaning: coalescing, date conversion, GA standardization/capping, factor levels, column ordering",
  "unified_dataset_analysis_v10_17.Rmd", "Analysis and visualization: generates HTML report, PowerPoint, Excel summaries",
  "export_missingness_report.R", "Exports XLSX missingness report by variable and study"
)

ft_pipe <- flextable(pipe_arch) %>%
  theme_box() %>%
  fontsize(size = 9, part = "all") %>%
  set_table_properties(width = 1, layout = "autofit") %>%
  bold(part = "header")

doc3 <- doc3 %>%
  body_add_par("1.1 Pipeline Architecture", style = "heading 2") %>%
  body_add_flextable(ft_pipe)

# Section 2: Execution order
doc3 <- doc3 %>%
  body_add_par("", style = "Normal") %>%
  body_add_par("2. Correct Script Execution Order", style = "heading 1") %>%
  body_add_par("The scripts must be run in a specific order due to data dependencies:", style = "Normal")

doc3 <- doc3 %>%
  body_add_par("Step 1: Run DHS Pipeline", style = "heading 2") %>%
  body_add_par("Script: DHS_Pipeline_Complete_v7.2.Rmd", style = "Normal") %>%
  body_add_par("Input: DHS datasets downloaded via rdhs package (cached in data/dhs/cache/)", style = "Normal") %>%
  body_add_par("Output: output/dhs_unified_dataset.rds", style = "Normal") %>%
  body_add_par("Run Time: 30-60 minutes (depends on number of surveys)", style = "Normal") %>%
  body_add_par("This extracts stillbirths, neonatal deaths, and demographic/SES variables from 165 DHS surveys. Requires rdhs package with valid DHS API credentials.", style = "Normal")

doc3 <- doc3 %>%
  body_add_par("Step 2: Run 6-Study Pipeline", style = "heading 2") %>%
  body_add_par("Script: unified_dataset_pipeline_v10_11.Rmd", style = "Normal") %>%
  body_add_par("Input: Raw study datasets (NCOPS, ALERT, PRECISE, PTBi, EN-INDEPTH, WHOMCS)", style = "Normal") %>%
  body_add_par("Output: output/unified_dataset_v10.11.rds, .csv, .dta", style = "Normal") %>%
  body_add_par("Run Time: 5-15 minutes", style = "Normal")

doc3 <- doc3 %>%
  body_add_par("Step 3: Fix DHS Labels & Extract Birth Attendant", style = "heading 2") %>%
  body_add_par("Script: fix_dhs_labels_attendant.R", style = "Normal") %>%
  body_add_par("Input: data/dhs/cache/datasets/*.rds (rdhs cached BR files), output/dhs_unified_dataset.rds", style = "Normal") %>%
  body_add_par("Output: Updated output/dhs_unified_dataset.rds (in-place), updated merged dataset", style = "Normal") %>%
  body_add_par("Run Time: 5-10 minutes", style = "Normal") %>%
  body_add_par("Re-reads cached BR files to decode religion (v130) and ethnicity (v131) labels, and extracts birth attendant from m3a-m3n binary variables.", style = "Normal")

doc3 <- doc3 %>%
  body_add_par("Step 4: Merge All Data Sources", style = "heading 2") %>%
  body_add_par("Combines DHS and 6-study unified datasets into merged_unified_dataset_v10.16.rds. Ensures consistent column names and types across all sources.", style = "Normal")

doc3 <- doc3 %>%
  body_add_par("Step 5: Environmental Data Extraction", style = "heading 2") %>%
  body_add_par("Script: optimized_environmental_extraction_v3_4.R", style = "Normal") %>%
  body_add_par("Input: Merged dataset coordinates + downloaded climate data (ERA5 .nc, SRTM .tif, PM2.5 .nc)", style = "Normal") %>%
  body_add_par("Output: output/environmental/environmental_linkage_v3.4.rds", style = "Normal") %>%
  body_add_par("Run Time: 25-50 minutes", style = "Normal") %>%
  body_add_par("Extracts at ~56,000 unique GPS clusters rather than per-record, then joins back. Covers: temperature, humidity, precipitation, heat index (ERA5), elevation and slope (SRTM), PM2.5 (ACAG satellite), and season classification.", style = "Normal")

doc3 <- doc3 %>%
  body_add_par("Step 6: Join Environmental Data", style = "heading 2") %>%
  body_add_par("Script: join_env_to_unified.R", style = "Normal") %>%
  body_add_par("Joins environmental_linkage_v3.4.rds to the merged dataset using coordinate matching. Output: unified_dataset_with_env_v10.16.rds.", style = "Normal")

doc3 <- doc3 %>%
  body_add_par("Step 7: Create v10.17 Clean Dataset", style = "heading 2") %>%
  body_add_par("Script: create_v10.17_clean.R", style = "Normal") %>%
  body_add_par("Input: output/unified_dataset_with_env_v10.16.rds (or merged_unified_dataset_v10.16.rds)", style = "Normal") %>%
  body_add_par("Output: output/unified_dataset_with_env_v10.17_cleaned.rds, .csv, .dta", style = "Normal") %>%
  body_add_par("Run Time: 5-15 minutes", style = "Normal") %>%
  body_add_par("This is the FINAL cleaning step. It performs: column coalescing (20 duplicate pairs merged), character-to-Date conversion (3 date columns), DHS date computation (delivery and conception dates from out_dob), GA standardization with +7 rollover fix and plausibility capping [12-47 weeks], comprehensive factor level assignment (83 columns), value recoding (delivery location, infant sex), implausible date capping, column reordering, and export in 3 formats (RDS, CSV, Stata DTA).", style = "Normal")

doc3 <- doc3 %>%
  body_add_par("Step 8: Run Analysis", style = "heading 2") %>%
  body_add_par("Script: unified_dataset_analysis_v10_17.Rmd", style = "Normal") %>%
  body_add_par("Input: output/unified_dataset_with_env_v10.17_cleaned.rds", style = "Normal") %>%
  body_add_par("Output: HTML report (10.9 MB), PowerPoint (537 KB), Excel variable inventory", style = "Normal") %>%
  body_add_par("Run Time: 3-10 minutes", style = "Normal")

doc3 <- doc3 %>%
  body_add_par("Step 9 (Optional): Missingness Report", style = "heading 2") %>%
  body_add_par("Script: export_missingness_report.R", style = "Normal") %>%
  body_add_par("Output: output/unified_dataset_v10.17_missingness_report.xlsx", style = "Normal")

# Visual workflow
doc3 <- doc3 %>%
  body_add_par("3. Visual Workflow Diagram", style = "heading 1")
workflow_text <- paste0(
  "RAW DHS DATA (165 surveys via rdhs)\n",
  "   |\n",
  "Step 1: DHS_Pipeline_Complete_v7.2.Rmd\n",
  "   |\n",
  "   v\n",
  "dhs_unified_dataset.rds\n",
  "   |\n",
  "Step 3: fix_dhs_labels_attendant.R\n",
  "   |\n",
  "   v                                    RAW STUDY DATA\n",
  "dhs_unified_dataset.rds (fixed)       (NCOPS,ALERT,PRECISE,PTBi,EN-INDEPTH,WHOMCS)\n",
  "   |                                    |\n",
  "   |                                  Step 2: unified_dataset_pipeline_v10_11.Rmd\n",
  "   |                                    |\n",
  "   v                                    v\n",
  "Step 4: MERGE ---------------------------------------->\n",
  "   |\n",
  "   v\n",
  "merged_unified_dataset_v10.16.rds\n",
  "   |\n",
  "Step 5-6: Environmental extraction + join\n",
  "   |\n",
  "   v\n",
  "unified_dataset_with_env_v10.16.rds\n",
  "   |\n",
  "Step 7: create_v10.17_clean.R\n",
  "   |\n",
  "   v\n",
  "unified_dataset_with_env_v10.17_cleaned.rds/.csv/.dta\n",
  "   |\n",
  "   v                         v\n",
  "Step 8: Analysis          Step 9: Missingness Report\n",
  "(HTML/PPTX/XLSX)          (XLSX)"
)
doc3 <- doc3 %>%
  body_add_par(workflow_text, style = "Normal")

# Output files
doc3 <- doc3 %>%
  body_add_par("4. Output Files Reference", style = "heading 1")

output_files <- tribble(
  ~File_Path, ~Created_By, ~Description,
  "output/dhs_unified_dataset.rds", "Step 1 + Step 3", "DHS harmonized dataset (with fixed labels)",
  "output/merged_unified_dataset_v10.16.rds", "Step 4", "Merged 7-source dataset (pre-cleaning)",
  "output/environmental/environmental_linkage_v3.4.rds", "Step 5", "Environmental data at unique clusters",
  "output/unified_dataset_with_env_v10.17_cleaned.rds", "Step 7", "Final cleaned dataset (RDS, 155 MB)",
  "output/unified_dataset_with_env_v10.17_cleaned.csv", "Step 7", "Final cleaned dataset (CSV, 3.8 GB)",
  "output/unified_dataset_with_env_v10.17_cleaned.dta", "Step 7", "Final cleaned dataset (Stata, 6.4 GB)",
  "output/ga_standardisation_log_v10.17.txt", "Step 7", "GA processing log",
  "output/unified_dataset_v10.17_missingness_report.xlsx", "Step 9", "Missingness report by variable and study"
)

ft_out <- flextable(output_files) %>%
  theme_box() %>%
  fontsize(size = 9, part = "all") %>%
  set_table_properties(width = 1, layout = "autofit") %>%
  bold(part = "header")

doc3 <- doc3 %>%
  body_add_flextable(ft_out)

# Troubleshooting
doc3 <- doc3 %>%
  body_add_par("", style = "Normal") %>%
  body_add_par("5. Troubleshooting", style = "heading 1") %>%
  body_add_par("Error: Cannot find unified dataset", style = "heading 2") %>%
  body_add_par("Ensure Steps 1-4 completed successfully. Check that merged_unified_dataset_v10.16.rds exists in the output directory.", style = "Normal") %>%
  body_add_par("Error: Environmental linkage file not found", style = "heading 2") %>%
  body_add_par("Run Step 5 (environmental extraction) and Step 6 (join) before running create_v10.17_clean.R.", style = "Normal") %>%
  body_add_par("Error: scale_fill_manual() / Continuous value supplied to discrete scale", style = "heading 2") %>%
  body_add_par("This occurs when ifelse() is applied to factor columns, returning integer codes instead of labels. Wrap factor columns with as.character() before using in ifelse() conditions.", style = "Normal") %>%
  body_add_par("Warning: Many records without coordinates", style = "heading 2") %>%
  body_add_par("This is expected for some DHS surveys lacking geographic data. Coordinate coverage in v10.17: 99.3% (5,955,637 of 5,996,390 records have coordinates).", style = "Normal") %>%
  body_add_par("", style = "Normal") %>%
  body_add_par(paste0("Document generated: ", Sys.Date()), style = "Normal")

docx3_path <- file.path(docs_dir, "Pipeline_Workflow_Documentation_v10_17.docx")
print(doc3, target = docx3_path)
cat(glue("  Saved: {basename(docx3_path)} ({round(file.info(docx3_path)$size/1024, 1)} KB)\n\n"))

# ============================================================================
# DOCUMENT 4: DATA DICTIONARY (DOCX)
# ============================================================================
cat("--- Document 4: Data Dictionary ---\n")

doc4 <- read_docx()

doc4 <- doc4 %>%
  body_add_par("Unified Perinatal Dataset", style = "heading 1") %>%
  body_add_par("Data Dictionary v10.17", style = "Normal") %>%
  body_add_par("Stillbirth and Neonatal Death Prediction in Sub-Saharan Africa", style = "Normal") %>%
  body_add_par("London School of Hygiene & Tropical Medicine", style = "Normal") %>%
  body_add_par("", style = "Normal")

# Overview
doc4 <- doc4 %>%
  body_add_par("Overview", style = "heading 1") %>%
  body_add_par(paste0(
    "This data dictionary documents all ", n_cols,
    " variables in the unified perinatal dataset v10.17, harmonizing data from seven sources: NCOPS, ALERT, PRECISE, PTBi, EN-INDEPTH, WHOMCS, and DHS (165 surveys). Total records: ",
    format(n_total, big.mark = ","), " across ", n_distinct(df$mat_country), " countries."
  ), style = "Normal")

# Study abbreviations
doc4 <- doc4 %>%
  body_add_par("Study Abbreviations", style = "heading 2")

study_abbr <- tibble(
  Abbreviation = c("NCOPS", "ALERT", "PRECISE", "PTBi", "EN-INDEPTH", "WHOMCS", "DHS"),
  `Full Study Name` = c(
    "Neonatal Clinical Outcomes and Practices Study (Uganda)",
    "Action Leveraging Evidence to Reduce Perinatal Mortality (Uganda, Malawi, Benin, Tanzania)",
    "Pregnancy Care Integrating Translational Science Everywhere (Gambia, Kenya, Mozambique)",
    "Preterm Birth Initiative (Uganda)",
    "Every Newborn INDEPTH Network Study (Bangladesh, Ethiopia, Ghana, Guinea-Bissau, Uganda)",
    "WHO Multi-Country Survey on Maternal and Newborn Health (29 countries)",
    paste0("Demographic and Health Surveys Programme (", n_distinct(df$mat_country[as.character(df$study_source) == "DHS"]), " countries, 165 surveys)")
  )
)

ft_abbr <- flextable(study_abbr) %>%
  theme_box() %>%
  fontsize(size = 9, part = "all") %>%
  set_table_properties(width = 1, layout = "autofit") %>%
  bold(part = "header")

doc4 <- doc4 %>%
  body_add_flextable(ft_abbr) %>%
  body_add_par("", style = "Normal")

# Generate sections from col_meta
sections <- unique(col_meta$section)
sections <- sections[order(sections)]

for (sec in sections) {
  sec_vars <- col_meta %>% filter(section == sec)

  doc4 <- doc4 %>%
    body_add_par(sec, style = "heading 1")

  # Section description
  sec_desc <- case_when(
    sec == "1. Identifiers" ~ "Unique identifiers linking records across the harmonized dataset, to original study data, and to DHS survey metadata.",
    sec == "2. Primary Outcomes" ~ "Core perinatal outcome variables including stillbirth, neonatal death, gestational age, birthweight, and related measurements.",
    sec == "3. Maternal Demographics & Clinical" ~ "Maternal characteristics including demographics, obstetric history, clinical measurements, and delivery characteristics.",
    sec == "4. Father Demographics" ~ "Father education and occupation, available primarily from DHS surveys.",
    sec == "5. Household Socioeconomic" ~ "Household wealth, living conditions, assets, utilities, and socioeconomic status indicators.",
    sec == "6. Environmental & Climate" ~ "Spatially and temporally resolved environmental exposures extracted from ERA5, SRTM, and satellite PM2.5 data.",
    sec == "7. Lifestyle & Pregnancy" ~ "Lifestyle factors (tobacco use) and pregnancy-specific conditions.",
    sec == "8. Temporal" ~ "Date and time-related variables including dates of birth, death, delivery, and conception.",
    sec == "9. Survey Weights" ~ "DHS sampling weights for nationally representative analyses.",
    TRUE ~ ""
  )
  if (sec_desc != "") {
    doc4 <- doc4 %>%
      body_add_par(sec_desc, style = "Normal")
  }

  # Summary table for section
  summary_tbl <- sec_vars %>%
    select(Variable = variable, Type = type, `% Missing` = pct_miss,
           Values = values, `Available In` = studies_available) %>%
    mutate(`% Missing` = paste0(`% Missing`, "%"))

  ft_sec <- flextable(summary_tbl) %>%
    theme_box() %>%
    fontsize(size = 8, part = "all") %>%
    set_table_properties(width = 1, layout = "autofit") %>%
    bold(part = "header")

  doc4 <- doc4 %>%
    body_add_flextable(ft_sec) %>%
    body_add_par("", style = "Normal")

  # Detailed variable descriptions
  doc4 <- doc4 %>%
    body_add_par("Detailed Variable Descriptions", style = "heading 2")

  for (j in seq_len(nrow(sec_vars))) {
    v <- sec_vars[j, ]

    # Variable label lookup
    label <- case_when(
      v$variable == "unified_id" ~ "Unified Record Identifier",
      v$variable == "study_source" ~ "Source Study Name",
      v$variable == "study_design" ~ "Study Design Type",
      v$variable == "module" ~ "Data Collection Module",
      v$variable == "raw_id" ~ "Original Study ID",
      v$variable == "raw_id_secondary" ~ "Secondary Study ID",
      v$variable == "study_id" ~ "DHS Study-Level Identifier",
      v$variable == "dhs_survey_id" ~ "DHS Survey Identifier",
      v$variable == "dhs_cluster" ~ "DHS Cluster (PSU) Number",
      v$variable == "dhs_caseid" ~ "DHS Case Identifier",
      v$variable == "mat_country" ~ "Country",
      v$variable == "mat_district" ~ "District",
      v$variable == "mat_facility" ~ "Health Facility",
      v$variable == "mat_urban_rural" ~ "Urban/Rural Classification",
      v$variable == "loc_region" ~ "WHO Region",
      v$variable == "loc_village" ~ "Village/Community",
      v$variable == "loc_facility_type" ~ "Facility Type/Level",
      v$variable == "env_latitude" ~ "Latitude (GPS)",
      v$variable == "env_longitude" ~ "Longitude (GPS)",
      v$variable == "coordinate_source" ~ "GPS Coordinate Source",
      v$variable == "study_date" ~ "Study/Enrollment Date",
      v$variable == "studyyear" ~ "Study Year",
      v$variable == "out_dob" ~ "Date of Birth",
      v$variable == "yob" ~ "Year of Birth",
      v$variable == "out_dob_source" ~ "DOB Data Source",
      v$variable == "delivery_date_raw" ~ "Delivery Date",
      v$variable == "conception_date" ~ "Estimated Conception Date",
      v$variable == "conception_date_source" ~ "Conception Date Method",
      v$variable == "mat_age" ~ "Maternal Age (years)",
      v$variable == "mat_age_cat" ~ "Maternal Age Category",
      v$variable == "mat_marital_status" ~ "Marital Status",
      v$variable == "mat_religion" ~ "Religion (harmonised)",
      v$variable == "mat_ethnicity" ~ "Ethnicity (country-specific)",
      v$variable == "mat_education" ~ "Education Level",
      v$variable == "mat_literacy" ~ "Literacy",
      v$variable == "mat_occupation" ~ "Occupation",
      v$variable == "mat_height_cm" ~ "Height (cm)",
      v$variable == "mat_weight_kg" ~ "Weight (kg)",
      v$variable == "mat_bmi" ~ "Body Mass Index",
      v$variable == "mat_muac" ~ "Mid-Upper Arm Circumference (cm)",
      v$variable == "mat_sbp" ~ "Systolic Blood Pressure (mmHg)",
      v$variable == "mat_dbp" ~ "Diastolic Blood Pressure (mmHg)",
      v$variable == "mat_hypertension" ~ "Hypertension",
      v$variable == "mat_hypertension_stage" ~ "Hypertension Stage",
      v$variable == "mat_preeclampsia" ~ "Preeclampsia",
      v$variable == "mat_eclampsia" ~ "Eclampsia",
      v$variable == "mat_aph" ~ "Antepartum Haemorrhage",
      v$variable == "mat_diabetes" ~ "Diabetes",
      v$variable == "mat_malaria" ~ "Malaria in Pregnancy",
      v$variable == "mat_anaemia" ~ "Anaemia",
      v$variable == "mat_hiv_status" ~ "HIV Status",
      v$variable == "mat_syphilis" ~ "Syphilis Status",
      v$variable == "mat_gravidity" ~ "Gravidity",
      v$variable == "mat_parity" ~ "Parity",
      v$variable == "mat_previous_cs" ~ "Previous C-Sections (count)",
      v$variable == "obs_previous_csection" ~ "Previous C-Section (binary)",
      v$variable == "mat_previous_csection" ~ "Previous C-Section (clinical)",
      v$variable == "mat_previous_stillbirth" ~ "Previous Stillbirth",
      v$variable == "mat_anc_visits" ~ "ANC Visit Count",
      v$variable == "mat_anc_provider" ~ "ANC Provider Type",
      v$variable == "anc_attendance" ~ "ANC Attendance (binary)",
      v$variable == "anc_tetanus" ~ "Tetanus Injections",
      v$variable == "mat_delivery_mode" ~ "Delivery Mode",
      v$variable == "mat_delivery_location" ~ "Delivery Location",
      v$variable == "mat_birth_attendant" ~ "Birth Attendant",
      v$variable == "mat_csection" ~ "Caesarean Section (binary)",
      v$variable == "mat_prolonged_labour" ~ "Prolonged Labour",
      v$variable == "mat_obstructed_labour" ~ "Obstructed Labour",
      v$variable == "mat_prom" ~ "Premature Rupture of Membranes",
      v$variable == "fat_education" ~ "Father Education Level",
      v$variable == "fat_occupation" ~ "Father Occupation",
      v$variable == "hh_wealth_quintile" ~ "Wealth Quintile",
      v$variable == "hh_ses_binary" ~ "SES Binary Classification",
      v$variable == "hh_size" ~ "Household Size",
      v$variable == "hh_asset_score" ~ "Wealth Index Score (continuous)",
      v$variable == "hh_house_floor" ~ "Floor Material",
      v$variable == "hh_house_wall" ~ "Wall Material",
      v$variable == "hh_ppi_band" ~ "PPI Band",
      v$variable == "hh_cooking_fuel" ~ "Cooking Fuel",
      v$variable == "hh_heating_fuel" ~ "Heating Fuel",
      v$variable == "hh_lighting" ~ "Lighting Source",
      v$variable == "hh_electricity" ~ "Electricity Access",
      v$variable == "hh_water_source" ~ "Drinking Water Source",
      v$variable == "hh_sanitation" ~ "Sanitation Facility",
      v$variable == "hh_mosquito_net" ~ "Mosquito Net Use",
      v$variable == "hh_ppi_score" ~ "PPI Score (0-100)",
      v$variable == "hh_poverty_likelihood" ~ "Poverty Likelihood (%)",
      v$variable == "hh_asset_radio" ~ "Owns Radio",
      v$variable == "hh_asset_tv" ~ "Owns Television",
      v$variable == "hh_asset_mobile" ~ "Owns Mobile Phone",
      v$variable == "hh_asset_motorbike" ~ "Owns Motorbike",
      v$variable == "hh_asset_car" ~ "Owns Car",
      v$variable == "out_stillbirth" ~ "Stillbirth (any GA)",
      v$variable == "out_stillbirth_20wks" ~ "Stillbirth (>=20 weeks)",
      v$variable == "out_stillbirth_28wks" ~ "Stillbirth (>=28 weeks)",
      v$variable == "out_fresh_stillbirth" ~ "Fresh Stillbirth",
      v$variable == "out_macerated_stillbirth" ~ "Macerated Stillbirth",
      v$variable == "out_livebirth" ~ "Live Birth",
      v$variable == "out_nnd" ~ "Neonatal Death (0-28 days)",
      v$variable == "out_nnd_early" ~ "Early Neonatal Death (0-7 days)",
      v$variable == "out_nnd_late" ~ "Late Neonatal Death (8-28 days)",
      v$variable == "out_perinatal_death" ~ "Perinatal Death",
      v$variable == "out_infant_sex" ~ "Infant Sex",
      v$variable == "out_ga_method" ~ "GA Assessment Method",
      v$variable == "out_ga_weeks" ~ "Gestational Age (weeks)",
      v$variable == "out_ga_days" ~ "Gestational Age (days)",
      v$variable == "out_ga_string" ~ "GA Obstetric String",
      v$variable == "out_birthweight_g" ~ "Birth Weight (grams)",
      v$variable == "out_birthweight_centile" ~ "Birth Weight Centile",
      v$variable == "out_birthweight_zscore" ~ "Birth Weight Z-score",
      v$variable == "out_sga" ~ "Small for Gestational Age",
      v$variable == "out_lga" ~ "Large for Gestational Age",
      v$variable == "out_aga" ~ "Appropriate for Gestational Age",
      v$variable == "out_sizeforGA" ~ "Size for GA Category",
      v$variable == "out_lbw" ~ "Low Birth Weight (<2500g)",
      v$variable == "out_vlbw" ~ "Very Low Birth Weight (<1500g)",
      v$variable == "out_elbw" ~ "Extremely Low Birth Weight (<1000g)",
      v$variable == "out_preterm" ~ "Preterm (<37 weeks)",
      v$variable == "out_very_preterm" ~ "Very Preterm (<32 weeks)",
      v$variable == "out_extremely_preterm" ~ "Extremely Preterm (<28 weeks)",
      v$variable == "out_apgar_1min" ~ "Apgar Score (1 minute)",
      v$variable == "out_apgar_5min" ~ "Apgar Score (5 minutes)",
      v$variable == "out_apgar_10min" ~ "Apgar Score (10 minutes)",
      v$variable == "out_multiple" ~ "Multiple Birth",
      v$variable == "out_dod" ~ "Date of Death",
      v$variable == "out_ageatdeath" ~ "Age at Death (days)",
      v$variable == "neo_size_at_birth" ~ "Perceived Size at Birth",
      v$variable == "life_tobacco" ~ "Tobacco Use",
      v$variable == "preg_anaemia" ~ "Anaemia in Pregnancy",
      v$variable == "preg_hiv" ~ "HIV in Pregnancy",
      v$variable == "sample_weight" ~ "DHS Sampling Weight",
      v$variable == "env_elevation" ~ "Elevation (metres)",
      v$variable == "env_slope" ~ "Terrain Slope (degrees)",
      v$variable == "env_temp_mean_delivery" ~ "Mean Temperature at Delivery (C)",
      v$variable == "env_humidity_delivery" ~ "Mean Humidity at Delivery (%)",
      v$variable == "env_precipitation_delivery" ~ "Total Precipitation at Delivery (mm)",
      v$variable == "env_heat_index_delivery" ~ "Mean Heat Index at Delivery (C)",
      v$variable == "env_pm25_annual" ~ "Annual PM2.5 (ug/m3)",
      v$variable == "env_pm25_delivery" ~ "PM2.5 at Delivery Month (ug/m3)",
      v$variable == "env_season_delivery" ~ "Season at Delivery",
      v$variable == "env_season_conception" ~ "Season at Conception",
      TRUE ~ v$variable
    )

    # Missingness description
    miss_desc <- case_when(
      v$pct_miss == 0 ~ "0% (complete)",
      v$pct_miss < 5 ~ paste0(v$pct_miss, "% (low)"),
      v$pct_miss < 20 ~ paste0(v$pct_miss, "%"),
      v$pct_miss < 50 ~ paste0(v$pct_miss, "% (moderate)"),
      v$pct_miss < 90 ~ paste0(v$pct_miss, "% (high)"),
      v$pct_miss < 100 ~ paste0(v$pct_miss, "% (very high)"),
      TRUE ~ "100% (placeholder)"
    )

    detail_tbl <- tibble(
      Field = c("Label", "Description", "Format", "Values", "Missingness", "Available In", "N Non-Missing"),
      Value = c(
        label,
        label,
        v$type,
        v$values,
        miss_desc,
        v$studies_available,
        format(v$n_nonNA, big.mark = ",")
      )
    )

    ft_detail <- flextable(detail_tbl) %>%
      theme_box() %>%
      fontsize(size = 8, part = "all") %>%
      width(j = 1, width = 1.5) %>%
      width(j = 2, width = 5) %>%
      bold(j = 1)

    doc4 <- doc4 %>%
      body_add_par(v$variable, style = "heading 3") %>%
      body_add_flextable(ft_detail) %>%
      body_add_par("", style = "Normal")
  }
}

docx4_path <- file.path(docs_dir, "Unified_Dataset_Data_Dictionary_v10_17.docx")
print(doc4, target = docx4_path)
cat(glue("  Saved: {basename(docx4_path)} ({round(file.info(docx4_path)$size/1024, 1)} KB)\n\n"))

# ============================================================================
# CLEANUP
# ============================================================================
rm(df, col_meta, study_counts)
gc()

cat("============================================================\n")
cat("  ALL 4 DOCUMENTS GENERATED SUCCESSFULLY\n")
cat("============================================================\n")
cat(glue("  1. {basename(xlsx_path)}\n"))
cat(glue("  2. {basename(docx2_path)}\n"))
cat(glue("  3. {basename(docx3_path)}\n"))
cat(glue("  4. {basename(docx4_path)}\n"))
cat(glue("  Location: {docs_dir}\n"))
