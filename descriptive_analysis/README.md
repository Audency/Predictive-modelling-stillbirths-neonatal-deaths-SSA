# Phase 2: Descriptive Analysis & Pre-Modeling Report

Comprehensive descriptive analysis of the harmonised unified dataset (v10.17) prior to predictive modelling. This phase characterises the study population, quantifies outcome rates, examines covariate distributions, assesses data completeness, and produces bivariate analyses suitable for the manuscript's descriptive tables.

## Key Results

### Dataset

| Metric | Value |
|--------|-------|
| Total records | 3,210,530 |
| Variables | 141 |
| SSA countries | 33 |
| Contributing studies | 7 |
| Period | 2010--2024 |

### Outcome Rates

| Outcome | Events | Rate per 1,000 |
|---------|--------|-----------------|
| Stillbirth (SBR) | 33,394 | 10.4 per 1,000 total births |
| Neonatal death (NND) | 96,694 | 30.4 per 1,000 live births |
| Perinatal mortality (PMR) | 130,088 | 40.5 per 1,000 total births |

### Contributing Studies

ALERT, DHS, EN-INDEPTH, NCOPS, PRECISE, PTBi, WHOMCS

### Countries (33)

Angola, Benin, Burkina Faso, Burundi, Cameroon, Chad, Comoros, Ethiopia, Gabon, Ghana, Guinea, Guinea-Bissau, Kenya, Lesotho, Liberia, Madagascar, Malawi, Mali, Mauritania, Mozambique, Namibia, Niger, Nigeria, Rwanda, Senegal, Sierra Leone, South Africa, Tanzania, The Gambia, Togo, Uganda, Zambia, Zimbabwe

## Scripts

| Script | Description |
|--------|-------------|
| `LSHTM_Descriptive_PreModeling_Report.Rmd` | Main parameterised RMarkdown report (HTML output with interactive tables and figures) |
| `render_report.R` | Rendering wrapper — run this to generate the HTML report, Excel workbook, and PowerPoint |
| `EDA_df_ssa_from2010_pipeline_v2.R` | Standalone EDA pipeline for the SSA subset (exploratory, precedes the Rmd report) |
| `SSA_StudyType_Descriptive_Pipeline.R` | Study-type stratified descriptive pipeline |

## Report Contents

The main Rmd report (`LSHTM_Descriptive_PreModeling_Report.Rmd`) generates:

### HTML Report
1. **Executive Summary** — KPI cards, outcome verification, study overview
2. **Geographic Distribution** — interactive choropleth map of SSA coverage
3. **Study Composition** — sample sizes, temporal trends, study-type classification
4. **Outcome Epidemiology** — SBR/NND rates by study, country, year; forest-style plots
5. **Maternal & Birth Characteristics** — age distribution, GA, birthweight, delivery mode
6. **Cross-tabulations** — SB by maternal age, NND by birthweight, outcomes by education
7. **Table 1** — Descriptive characteristics by study type and by individual study
8. **Table 2** — Bivariate analysis: covariates vs stillbirth (2a) and neonatal death (2b) with p-values (Wilcoxon/Chi-squared)
9. **Table 3** — Covariate profile by individual study with p-values (Kruskal-Wallis/Chi-squared)
10. **Covariate Availability** — heatmap of data completeness by study
11. **Missingness Analysis** — variable-level and pattern-level missingness
12. **Pre-Modeling Readiness** — variable classification into global/type-specific/study-specific model tiers
13. **Environmental Variables** — distributions and correlations of geospatial exposures

### Excel Workbook (`LSHTM_Descriptive_Analysis.xlsx`)
Sheets: study_distribution, study_overview, covariate_availability, candidate_variables, variable_inventory, model_readiness, missingness, outcome_counts, table2_sb, table2_nnd

### PowerPoint (`LSHTM_Descriptive_Presentation.pptx`)
13 slides: title, executive summary, study sizes, geographic map, outcome rates, birth characteristics, ridgeline plots, model readiness, candidate variables, covariate heatmap, cross-tabulations, key findings, recommendations

## How to Run

```r
# From the descriptive_analysis/ directory:
source("render_report.R")

# Or manually:
rmarkdown::render(
  "LSHTM_Descriptive_PreModeling_Report.Rmd",
  params = list(
    data_path = "unified_dataset_with_env_v10.17_cleaned.rds",
    dataset_dir = "../Dataset"
  )
)
```

### Requirements

R >= 4.3 with packages: tidyverse, gtsummary, gt, plotly, officer, flextable, openxlsx, DT, pheatmap, patchwork, ggridges, scales, rnaturalearth, sf

## Next Phase

Phase 3 (Python): Predictive modelling with classical ML, ensemble methods, and deep learning approaches for stillbirth and neonatal death prediction.
