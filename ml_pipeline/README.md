# ML Pipeline: Predictive Modelling of Stillbirth and Neonatal Death in SSA

Machine learning pipeline for predicting adverse perinatal outcomes (stillbirth and neonatal death) using the unified harmonised dataset from seven contributing studies across Sub-Saharan Africa.

## Models

| Algorithm | Type |
|---|---|
| Logistic Regression (L2) | Baseline |
| Random Forest | Ensemble |
| XGBoost | Gradient Boosting |
| LightGBM | Gradient Boosting |
| CatBoost | Gradient Boosting |
| MLP (Optuna-tuned) | Neural Network |

## Clinical Scenarios

- **S1 (Antenatal)**: Maternal demographics, household, environmental variables
- **S2 (Intrapartum)**: S1 + gestational age, delivery mode, facility delivery
- **S3 (Postnatal)**: S2 + birthweight, Apgar scores, preterm/LBW/SGA

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

All results are saved to `outputs_ML_results/`:
- `results_summary.csv` — master performance table
- `results_calibration.csv` — calibration metrics
- `results_iecv.csv` — leave-one-country-out validation
- `results_fairness.csv` — subgroup performance
- `stable4_hyperparams.csv` — best hyperparameters
- SHAP values and model artifacts
