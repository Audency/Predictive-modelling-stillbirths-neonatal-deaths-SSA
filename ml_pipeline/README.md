# ML Pipeline: Predictive Modelling of Stillbirth and Neonatal Death in SSA

Machine learning pipeline for predicting adverse perinatal outcomes (stillbirth and neonatal death) using the unified harmonised dataset from seven contributing studies across Sub-Saharan Africa.

## Models (8 algorithms)

| Algorithm | Type |
|---|---|
| Logistic Regression (L2) | Baseline |
| Gaussian Naive Bayes | Probabilistic baseline |
| Linear SVM (SGD, modified-Huber) | Margin-based |
| Random Forest | Ensemble |
| XGBoost | Gradient Boosting |
| LightGBM | Gradient Boosting |
| CatBoost | Gradient Boosting |
| MLP (Optuna-tuned) | Neural Network |

## Two-arm predictor design

Models use parsimonious, SSA-feasible **predictor sets** (not fixed scenarios), matched to what each source carries, in two arms:

- **Arm A · Survey (DHS + EN-INDEPTH)**: maternal age, twin, education, residence, wealth quintile, country, GDP, MMR.
- **Arm B · Clinical (ALERT, PTBi, PRECISE, WHOMCS, NCOPS)**: maternal age, parity, twin, BMI, gestational age, ANC visits, country, GDP, MMR.
- Outcomes: stillbirth, neonatal death, perinatal death (per arm). Neonatal adds infant sex; clinical neonatal adds birthweight + delivery mode.

**Leak-audited:** survey stillbirth/perinatal include DHS using `out_multiple` (twin) instead of parity — DHS stillbirth parity is a reproductive-calendar count (value leak); twin is measurement-consistent. Survey neonatal keeps real lifetime parity. Country-year GDP/MMR linked by study year. `hh_wealth_quintile` harmonised to Q1–Q5.

## Pipeline Steps

1. Data loading, SSA filter, year >= 2010
2. Nested cross-validation (5-fold outer, 3-fold inner) with SMOTE
3. Calibration assessment (CITL, calibration slope, E/O ratio)
4. Decision Curve Analysis
5. SHAP feature importance
6. Internal-External Cross-Validation (Leave-One-Country-Out)
7. Fairness / subgroup analysis

## Usage

```bash
conda run -n base python run_modeling_pipeline.py
```

## Experiment Tracking (MLflow)

Results are tracked with MLflow. After running the pipeline:

```bash
cd ml_pipeline
mlflow ui
```

Then open http://localhost:5000 to explore experiments.

## Output Files

Results saved to `outputs_ML_results/` (MLflow artefacts + CSVs). Curated figures and tables:

**`figures/`** — AUROC forest (`F9`), AUROC/AUPRC bars (`F10`/`F11`), calibration (`F1`), ROC/PR (`F2`/`F3`), decision-curve (`F4`), SHAP (`F5`), internal-vs-external (`F12`).

**`tables/`**
| Table | Contents |
|---|---|
| `AUROC_8models.csv` | AUROC (8 models × 2 arms × 3 outcomes) |
| `T6_performance_internal.csv` | AUROC/AUPRC/Brier/calibration |
| `T6b_extended_metrics.csv` | Se, Sp, PPV, NPV, F1, F2, MCC (Youden) |
| `T9_performance_external.csv` | External validation (Bangladesh / India+Pakistan) |
| `T10_by_country.csv` | Per-country AUROC |
| `T12_fairness_metrics.csv` | Subgroup performance (age, wealth Q1–Q5, residence, delivery mode) |
| `T3_sample_events_by_outcome_arm.csv` | Sample sizes and events |
