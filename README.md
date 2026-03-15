# Predictive Modelling for Stillbirths and Neonatal Deaths in Sub-Saharan Africa

Reproducible analytical pipeline for data harmonisation and predictive modelling across seven contributing studies (ALERT, EN-INDEPTH, PTBi, PRECISE, WHOMCS, NCOPS, DHS). Implements a 13-domain harmonisation framework and classical, machine learning and AI modelling approaches. Associated with a Wellcome Accelerator Award at the London School of Hygiene and Tropical Medicine.

## Pipeline overview

The pipeline produces a unified analytical dataset (v10.17) from six prospective cohort studies and national DHS surveys across Sub-Saharan Africa, linked with geospatial environmental exposures. Scripts are numbered in execution order and should be run sequentially from the project root directory.

### Execution order

| Step | Script | Description |
|------|--------|-------------|
| 01 | `pipeline/01_unified_dataset_pipeline_v10.15.Rmd` | Load and harmonise six studies (NCOPS, ALERT, PRECISE, PTBi, EN-INDEPTH, WHOMCS) into the 13-domain variable schema. Outputs `unified_dataset_v10.15.rds`. |
| 02 | `pipeline/02_dhs_pipeline_v7.2.Rmd` | Download, process and harmonise DHS Birth Recode data for all SSA countries with incremental checkpointing. Merges DHS with the 6-study dataset to produce `merged_unified_dataset_v10.16.rds`. |
| 03 | `pipeline/03_fix_dhs_geographic_linkage.R` | Download DHS GE shapefiles and link cluster-level GPS coordinates (replacing country centroids). Updates `merged_unified_dataset_v10.16.rds` with real GPS. |
| 04 | `pipeline/04_fix_dhs_labels_attendant.R` | Restore religion, ethnicity and birth attendant labels from DHS raw BR files. Updates `merged_unified_dataset_v10.16.rds` in place. |
| 05 | `pipeline/05_integrated_environmental_pipeline_v3.3.Rmd` | Extract environmental exposures (elevation, ERA5 climate, PM2.5, seasonality) from raster data. Outputs `environmental_linkage_v3.3.rds`. |
| 06 | `pipeline/06_optimized_environmental_extraction_v3.4.R` | Optimised re-extraction at ~56K unique coordinate pairs (reduces runtime from ~10h to ~30min). Outputs `environmental_linkage_v3.4.rds`. |
| 07 | `pipeline/07_join_environmental_to_unified.R` | Join environmental linkage v3.4 to the merged unified dataset. Outputs `unified_dataset_with_env_v10.16.rds`. |
| 08 | `pipeline/08_create_v10.17_clean.R` | Final cleaning: coalesce duplicate columns, standardise dates, clean gestational age, drop empty columns, reorder. Reads v10.16 and outputs `unified_dataset_with_env_v10.17_cleaned.rds`. |
| 09 | `pipeline/09_export_cleaned_dataset.R` | Export v10.17 to Stata (.dta), CSV, and generate a data dictionary (XLSX). |
| 10 | `pipeline/10_generate_documentation.R` | Generate documentation suite: DHS variable mapping, harmonisation documentation, pipeline workflow, data dictionary (4 Word/Excel files). |
| 11 | `pipeline/11_unified_dataset_analysis_v10.17.Rmd` | Comprehensive exploratory analysis report (HTML output). |

### Utilities

| Script | Description |
|--------|-------------|
| `utilities/save_checkpoints.R` | Save DHS processing checkpoints from RStudio memory before closing session |
| `utilities/download_dhs_gis.R` | Download DHS GIS shapefiles via direct URLs and link GPS to unified dataset |
| `utilities/download_era5_fixed.py` | Download ERA5 monthly climate data from Copernicus CDS API |
| `utilities/export_missingness_report.R` | Generate variable-level missingness report (XLSX) for v10.17 |
| `utilities/compare_v15_v17.R` | Validation: compare v10.15 vs v10.17 (GA, environmental data, column counts) |

### Legacy

| Script | Description |
|--------|-------------|
| `legacy/outcomes_harmonisation_v7.do` | Stata do-file for outcomes variable harmonisation (historical reference) |

## Configuration

All scripts that require a base path detect the current user and set paths accordingly. If running on a new machine, either:

1. Set your working directory to the project root before running scripts, or
2. Edit the `base_path` / `dropbox_base` variable at the top of each script.

Scripts 01, 05 and 11 use relative paths by default and require no configuration.

## Version history

- **v10.17** (current): Final cleaned dataset with standardised dates, coalesced duplicate columns, cleaned gestational age values, and logically ordered columns (~130 variables)
- **v10.16**: Added real DHS cluster-level GPS coordinates (replacing country centroids), restored DHS religion/ethnicity/birth attendant labels
- **v10.15**: Base unified dataset merging six prospective studies with DHS data and environmental variable placeholders

Environmental pipeline versions: v3.4 (optimised extraction at unique coordinates), v3.3 (complete integrated extraction), v3.2/v3.1 (earlier iterations)

## Data access

Individual-level data from the contributing studies are not publicly available due to ethical restrictions. DHS data can be requested from the [DHS Program](https://dhsprogram.com/).

## Associated resources

- **OSF:** <https://osf.io/ptf7x/overview>
- **DOI:** [10.12688/wellcomeopenres.25574.1](https://doi.org/10.12688/wellcomeopenres.25574.1)

## Author

Joseph Akuze, London School of Hygiene and Tropical Medicine

## Licence

MIT
