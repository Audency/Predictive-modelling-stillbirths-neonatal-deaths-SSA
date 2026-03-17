################################################################################
# RENDER SCRIPT — Gera o HTML e o PowerPoint automaticamente
# Audencio Victor | LSHTM
#
# Uso: source("render_report.R") ou Ctrl+Shift+Enter no RStudio
################################################################################

if (!requireNamespace("rmarkdown", quietly = TRUE)) {
  install.packages("rmarkdown", repos = "https://cloud.r-project.org")
}

rmarkdown::render(
  input  = "LSHTM_Descriptive_PreModeling_Report.Rmd",
  output_file = "../Dataset/LSHTM_Descriptive_Report.html",
  params = list(
    data_path    = "unified_dataset_with_env_v10.17_cleaned.rds",
    dataset_dir  = "../Dataset",
    output_dir   = "../outputs_descriptive_report",
    global_threshold = 70,
    type_threshold   = 60,
    study_threshold  = 60
  ),
  envir = new.env()
)

cat("\n\nHTML report generated at: ../Dataset/LSHTM_Descriptive_Report.html\n")
cat("Excel + PPTX exported to: ../outputs_descriptive_report/\n")
