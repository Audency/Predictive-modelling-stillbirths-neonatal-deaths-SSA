#!/usr/bin/env python3
"""
==============================================================================
SSA Perinatal Prediction Models — Production Pipeline
==============================================================================
Predictive models for stillbirth and neonatal death in Sub-Saharan Africa.
Dataset: Unified dataset v10.17 (3.2M births, 33 countries, 7 studies).

Outputs all results to outputs_ML_results/.

Usage:
    conda run -n base python run_modeling_pipeline.py
==============================================================================
"""

import warnings, random, os, sys, time, pickle, json
warnings.filterwarnings('ignore')

import pyreadr
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import seaborn as sns
from scipy import stats

from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import (
    StratifiedKFold, RandomizedSearchCV, train_test_split
)
from sklearn.preprocessing import StandardScaler, OneHotEncoder
from sklearn.impute import SimpleImputer
from sklearn.pipeline import Pipeline
from sklearn.compose import ColumnTransformer
from sklearn.metrics import (
    roc_auc_score, average_precision_score, brier_score_loss,
    roc_curve, precision_recall_curve, confusion_matrix,
    classification_report
)
from sklearn.utils.class_weight import compute_class_weight
from sklearn.calibration import calibration_curve

import xgboost as xgb
import lightgbm as lgb
import catboost as cb

import torch
import torch.nn as nn
import optuna
optuna.logging.set_verbosity(optuna.logging.WARNING)

import shap
from imblearn.over_sampling import SMOTE
import mlflow
import mlflow.sklearn
import mlflow.xgboost

# ──────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ──────────────────────────────────────────────────────────────────────────────
SEED = 42
random.seed(SEED)
np.random.seed(SEED)
torch.manual_seed(SEED)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(SCRIPT_DIR, 'outputs_ML_results')
os.makedirs(OUTPUT_DIR, exist_ok=True)

# ── MLflow Configuration ─────────────────────────────────────────────────────
MLFLOW_DIR = os.path.join(SCRIPT_DIR, 'mlruns')
mlflow.set_tracking_uri(f'file://{MLFLOW_DIR}')
mlflow.set_experiment('SSA_Perinatal_Prediction')

# Try multiple dataset paths
RDS_PATHS = [
    os.path.join(SCRIPT_DIR, '..', 'Dataset',
                 'df_ssa_from2010_clean.rds'),
    os.path.join(SCRIPT_DIR, '..', 'Dataset',
                 'unified_dataset_with_env_v10.17_cleaned.rds'),
    '/Users/lshva8/Desktop/AUDENCIO/LSHTM -Researcher Assistent/'
    'Projeto Principal/Banco de dados/dados novos/data/'
    'unified_dataset_with_env_v10.17_cleaned.rds',
]

YEAR_MIN = 2010
N_OUTER_FOLDS = 5
N_INNER_FOLDS = 3
N_RANDOM_ITER = 10    # RandomizedSearchCV iterations
MLP_OPTUNA_TRIALS = 20
SHAP_SAMPLE = 5000    # subsample for SHAP computation

# ──────────────────────────────────────────────────────────────────────────────
# SSA COUNTRY LIST
# ──────────────────────────────────────────────────────────────────────────────
SSA_COUNTRIES = [
    'Angola','Benin','Botswana','Burkina Faso','Burundi','Cabo Verde',
    'Cameroon','Central African Republic','Chad','Comoros',
    'Congo','Democratic Republic of the Congo',"Côte d'Ivoire",
    'Djibouti','Equatorial Guinea','Eritrea','Eswatini','Ethiopia',
    'Gabon','Gambia','Ghana','Guinea','Guinea-Bissau','Kenya',
    'Lesotho','Liberia','Madagascar','Malawi','Mali','Mauritania',
    'Mauritius','Mozambique','Namibia','Niger','Nigeria','Rwanda',
    'São Tomé and Príncipe','Senegal','Sierra Leone','Somalia',
    'South Africa','South Sudan','Sudan','Tanzania','Togo','Uganda',
    'Zambia','Zimbabwe',
]

# ──────────────────────────────────────────────────────────────────────────────
# PREDICTOR DEFINITIONS — 3 Clinical Scenarios
# ──────────────────────────────────────────────────────────────────────────────
NUM_S1 = ['mat_age','mat_parity','mat_anc_visits',
          'env_temp_mean_delivery','env_humidity_delivery',
          'env_precipitation_delivery','env_elevation',
          'env_pm25_annual','env_slope','hh_size','hh_asset_score']

CAT_S1 = ['mat_marital_status','mat_education','mat_religion','mat_occupation',
          'hh_wealth_quintile','hh_water_source','hh_sanitation','hh_cooking_fuel',
          'mat_urban_rural','env_season_delivery','study_source']

BIN_S1 = ['mat_previous_stillbirth','mat_previous_cs','hh_mosquito_net',
          'mat_previous_nnd','mat_hiv_status']

NUM_S2 = NUM_S1 + ['out_ga_weeks']
CAT_S2 = CAT_S1 + ['mat_delivery_mode','mat_hypertension','mat_facility_delivery']
BIN_S2 = BIN_S1 + ['out_multiple']

NUM_S3 = NUM_S2 + ['out_birthweight_g','out_apgar_1min','out_apgar_5min']
CAT_S3 = CAT_S2
BIN_S3 = BIN_S2 + ['out_preterm','out_lbw','out_sga','out_sex_male']

SCENARIOS = [
    ('S1', NUM_S1, CAT_S1, BIN_S1),
    ('S2', NUM_S2, CAT_S2, BIN_S2),
    ('S3', NUM_S3, CAT_S3, BIN_S3),
]

OUTCOMES = ['out_stillbirth', 'out_nnd']
OUTCOME_LABELS = {'out_stillbirth': 'Stillbirth', 'out_nnd': 'Neonatal Death'}

# ──────────────────────────────────────────────────────────────────────────────
# HYPERPARAMETER GRIDS
# ──────────────────────────────────────────────────────────────────────────────
RF_GRID = {
    'n_estimators': [200, 400, 600],
    'max_depth': [6, 10, 15, None],
    'min_samples_split': [10, 20, 50],
    'min_samples_leaf': [5, 10, 20],
    'max_features': ['sqrt', 'log2'],
}

XGB_GRID = {
    'n_estimators': [300, 500, 800],
    'max_depth': [3, 5, 7],
    'learning_rate': [0.01, 0.05, 0.1],
    'subsample': [0.7, 0.8, 1.0],
    'colsample_bytree': [0.7, 0.8, 1.0],
    'reg_alpha': [0, 0.1, 1.0],
}

LGB_GRID = {
    'n_estimators': [300, 500, 800],
    'num_leaves': [31, 63, 127],
    'learning_rate': [0.01, 0.05, 0.1],
    'subsample': [0.7, 0.8, 1.0],
    'colsample_bytree': [0.7, 0.8, 1.0],
    'reg_alpha': [0, 0.1, 1.0],
}

CB_GRID = {
    'iterations': [300, 500, 800],
    'depth': [4, 6, 8],
    'learning_rate': [0.01, 0.05, 0.1],
    'l2_leaf_reg': [1, 3, 10],
}


# ══════════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════

def log(msg):
    print(f'[{time.strftime("%H:%M:%S")}] {msg}', flush=True)


def convert_outcome(df, col):
    """Convert outcome column to 0/1 Int8, handling numeric, string, category, and factor encodings."""
    if col not in df.columns:
        return df
    raw = df[col].copy()

    # Handle category dtype → convert to string first
    if hasattr(raw, 'cat'):
        raw = raw.astype(str)
        raw = raw.replace('nan', pd.NA)

    # Try numeric first — some .rds files store outcomes as integer 0/1
    num = pd.to_numeric(raw, errors='coerce')
    if num.notna().sum() > 0:
        n_vals = set(num.dropna().unique())
        if n_vals.issubset({0, 1, 0.0, 1.0}):
            df[col] = num.astype('Int8')
            return df

    # String matching (handles Yes/No, True/False, etc.)
    s = raw.astype(str).str.strip().str.lower()
    out = pd.array([pd.NA] * len(df), dtype='Int8')
    out[s.isin({'yes', 'y', 'true', 't', '1', 'sim', '2'})] = 1
    out[s.isin({'no', 'n', 'false', 'f', '0', 'nao', 'não'})] = 0
    # Fill remaining from numeric
    still_na = pd.isna(out)
    out[still_na & num.notna()] = num[still_na & num.notna()].round().astype('Int8')
    df[col] = out
    return df


def make_prep(n, c, b):
    """Create ColumnTransformer for numeric/cat/binary features."""
    num_pipe = Pipeline([
        ('imp', SimpleImputer(strategy='median')),
        ('sc', StandardScaler()),
    ])
    bin_pipe = Pipeline([
        ('imp', SimpleImputer(strategy='most_frequent')),
    ])
    cat_pipe = Pipeline([
        ('imp', SimpleImputer(strategy='constant', fill_value='missing')),
        ('enc', OneHotEncoder(handle_unknown='ignore', sparse_output=False)),
    ])
    t = []
    if n: t.append(('num', num_pipe, n))
    if b: t.append(('bin', bin_pipe, b))
    if c: t.append(('cat', cat_pipe, c))
    return ColumnTransformer(t, remainder='drop')


def build_Xy(df, outcome_col, nums, cats, bins):
    """Build X, y arrays. Keeps only columns present in the dataframe."""
    if outcome_col not in df.columns:
        return None, None, None, None, None, None
    n = [v for v in nums if v in df.columns]
    c = [v for v in cats if v in df.columns]
    b = [v for v in bins if v in df.columns]
    mask = df[outcome_col].notna()
    X = df.loc[mask, n + c + b].copy()
    y = df.loc[mask, outcome_col].astype(int)

    # Ensure binary columns are truly numeric (handle residual strings/categories)
    for col in b:
        if col in X.columns:
            if hasattr(X[col], 'cat'):
                X[col] = X[col].astype(str).replace('nan', pd.NA)
            if X[col].dtype == object or str(X[col].dtype) == 'category':
                s = X[col].astype(str).str.strip().str.lower()
                mapped = s.map({'yes': 1, 'no': 0, 'true': 1, 'false': 0,
                                '1': 1, '0': 0, '1.0': 1, '0.0': 0,
                                'sim': 1, 'nao': 0, 'nan': np.nan,
                                '<na>': np.nan, 'none': np.nan})
                X[col] = pd.to_numeric(mapped, errors='coerce')
    # Also ensure categorical columns are strings for OneHotEncoder
    for col in c:
        if col in X.columns and hasattr(X[col], 'cat'):
            X[col] = X[col].astype(str).replace('nan', 'missing')

    prep = make_prep(n, c, b)
    X_np = prep.fit_transform(X)
    # Ensure all values are float (catch residual string/object columns)
    X_np = np.asarray(X_np, dtype=np.float64)
    try:
        feat_names = list(prep.get_feature_names_out())
    except Exception:
        feat_names = [f'feat_{i}' for i in range(X_np.shape[1])]
    return X, y, X_np, prep, (n, c, b), feat_names


def optimal_threshold(y_true, y_prob):
    """Find threshold maximizing Youden's J (sensitivity + specificity - 1)."""
    fpr, tpr, thresholds = roc_curve(y_true, y_prob)
    j = tpr - fpr
    idx = np.argmax(j)
    return thresholds[idx]


def classification_at_threshold(y_true, y_prob, thr):
    """Compute sens, spec, PPV, NPV at a given threshold."""
    pred = (y_prob >= thr).astype(int)
    tn, fp, fn, tp = confusion_matrix(y_true, pred, labels=[0, 1]).ravel()
    sens = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    spec = tn / (tn + fp) if (tn + fp) > 0 else 0.0
    ppv  = tp / (tp + fp) if (tp + fp) > 0 else 0.0
    npv  = tn / (tn + fn) if (tn + fn) > 0 else 0.0
    return sens, spec, ppv, npv


def net_benefit(y_true, y_prob, threshold):
    """Net benefit at a single threshold."""
    n = len(y_true)
    pred = (y_prob >= threshold).astype(int)
    tp = ((pred == 1) & (y_true == 1)).sum()
    fp = ((pred == 1) & (y_true == 0)).sum()
    return tp / n - fp / n * threshold / (1 - threshold + 1e-10)


# ──────────────────────────────────────────────────────────────────────────────
# MLP Model with Optuna
# ──────────────────────────────────────────────────────────────────────────────
class MLPClassifier:
    """Simple MLP wrapper for sklearn-like interface, tuned with Optuna."""

    def __init__(self, input_dim, n_trials=50, seed=42):
        self.input_dim = input_dim
        self.n_trials = n_trials
        self.seed = seed
        self.model = None
        self.best_params = None

    def _build_model(self, params):
        layers = []
        in_dim = self.input_dim
        for i in range(params['n_layers']):
            out_dim = params[f'hidden_{i}']
            layers.append(nn.Linear(in_dim, out_dim))
            layers.append(nn.ReLU())
            layers.append(nn.Dropout(params['dropout']))
            in_dim = out_dim
        layers.append(nn.Linear(in_dim, 1))
        layers.append(nn.Sigmoid())
        return nn.Sequential(*layers)

    def fit(self, X_train, y_train, X_val=None, y_val=None):
        device = torch.device('cpu')
        X_t = torch.FloatTensor(X_train).to(device)
        y_t = torch.FloatTensor(y_train).to(device)

        if X_val is not None:
            X_v = torch.FloatTensor(X_val).to(device)
            y_v = torch.FloatTensor(y_val).to(device)
        else:
            # Use 20% of train as validation
            n_val = max(1, int(0.2 * len(X_train)))
            X_v = X_t[-n_val:]
            y_v = y_t[-n_val:]
            X_t = X_t[:-n_val]
            y_t = y_t[:-n_val]

        # Compute pos_weight for imbalanced data
        n_pos = y_t.sum().item()
        n_neg = len(y_t) - n_pos
        pos_weight = torch.tensor([n_neg / max(n_pos, 1)]).to(device)

        def objective(trial):
            params = {
                'n_layers': trial.suggest_int('n_layers', 1, 3),
                'dropout': trial.suggest_float('dropout', 0.1, 0.5),
                'lr': trial.suggest_float('lr', 1e-4, 1e-2, log=True),
            }
            for i in range(params['n_layers']):
                params[f'hidden_{i}'] = trial.suggest_categorical(
                    f'hidden_{i}', [64, 128, 256])

            torch.manual_seed(self.seed)
            model = self._build_model(params).to(device)
            optimizer = torch.optim.Adam(model.parameters(), lr=params['lr'])
            criterion = nn.BCEWithLogitsLoss(pos_weight=pos_weight)

            best_val_loss = float('inf')
            patience_counter = 0

            for epoch in range(100):
                model.train()
                optimizer.zero_grad()
                out = model(X_t).squeeze()
                # Use raw logits for BCEWithLogitsLoss — remove sigmoid
                raw = out  # model already has sigmoid, so use BCELoss instead
                loss = nn.BCELoss()(out, y_t)
                loss.backward()
                optimizer.step()

                model.eval()
                with torch.no_grad():
                    val_out = model(X_v).squeeze()
                    val_loss = nn.BCELoss()(val_out, y_v).item()

                if val_loss < best_val_loss - 1e-4:
                    best_val_loss = val_loss
                    patience_counter = 0
                else:
                    patience_counter += 1
                    if patience_counter >= 10:
                        break

            return best_val_loss

        study = optuna.create_study(direction='minimize',
                                     sampler=optuna.samplers.TPESampler(seed=self.seed))
        study.optimize(objective, n_trials=self.n_trials, show_progress_bar=False)
        self.best_params = study.best_params

        # Rebuild with best params
        params = dict(self.best_params)
        torch.manual_seed(self.seed)
        self.model = self._build_model(params).to(device)
        optimizer = torch.optim.Adam(self.model.parameters(), lr=params['lr'])

        # Retrain on full train data
        X_full = torch.FloatTensor(X_train).to(device)
        y_full = torch.FloatTensor(y_train).to(device)

        for epoch in range(100):
            self.model.train()
            optimizer.zero_grad()
            out = self.model(X_full).squeeze()
            loss = nn.BCELoss()(out, y_full)
            loss.backward()
            optimizer.step()

    def predict_proba(self, X):
        self.model.eval()
        with torch.no_grad():
            probs = self.model(torch.FloatTensor(X)).squeeze().numpy()
        return np.column_stack([1 - probs, probs])


# ══════════════════════════════════════════════════════════════════════════════
# STEP 1: DATA LOADING & QC
# ══════════════════════════════════════════════════════════════════════════════

def load_data():
    log('Loading dataset...')
    rds_path = None
    for p in RDS_PATHS:
        p = os.path.abspath(p)
        if os.path.exists(p):
            rds_path = p
            break
    if rds_path is None:
        sys.exit(f'ERROR: Dataset not found. Tried:\n' +
                 '\n'.join(f'  {os.path.abspath(p)}' for p in RDS_PATHS))

    log(f'  Path: {rds_path}')
    result = pyreadr.read_r(rds_path)
    df_raw = list(result.values())[0].copy()
    log(f'  Raw: {df_raw.shape[0]:,} rows x {df_raw.shape[1]} columns')

    # Normalize country names before filtering
    if 'mat_country' in df_raw.columns:
        country_norm = {
            'The Gambia': 'Gambia',
            'Gambia, The': 'Gambia',
            'Congo, Dem. Rep.': 'Democratic Republic of the Congo',
            'Congo, Rep.': 'Congo',
            'DRC': 'Democratic Republic of the Congo',
            "Cote d'Ivoire": "Côte d'Ivoire",
            'Ivory Coast': "Côte d'Ivoire",
            'Sao Tome and Principe': 'São Tomé and Príncipe',
            'United Republic of Tanzania': 'Tanzania',
            'Swaziland': 'Eswatini',
            'Cape Verde': 'Cabo Verde',
        }
        df_raw['mat_country'] = df_raw['mat_country'].replace(country_norm)

    # SSA filter
    if 'mat_country' in df_raw.columns:
        mask = df_raw['mat_country'].isin(SSA_COUNTRIES)
        df = df_raw[mask].copy()
        log(f'  SSA filter: {len(df):,} rows ({df["mat_country"].nunique()} countries)')
        # Show which countries are present
        countries_found = sorted(df['mat_country'].unique())
        log(f'  Countries: {countries_found}')
    else:
        df = df_raw.copy()
        log('  WARNING: No mat_country column, using full dataset')

    # Year filter
    if 'studyyear' in df.columns:
        df['studyyear'] = pd.to_numeric(df['studyyear'], errors='coerce')
        n_before = len(df)
        df = df[df['studyyear'] >= YEAR_MIN].copy()
        log(f'  Year >= {YEAR_MIN}: {n_before:,} -> {len(df):,} rows')

    # QC fixes
    for col in ['env_pm25_annual', 'env_pm25_delivery']:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors='coerce')
            df[col] = df[col].where(df[col] != -999, np.nan)

    if 'env_pm25_delivery' in df.columns:
        df.drop(columns=['env_pm25_delivery'], inplace=True)

    drop_cols = ['loc_facility_type', 'mat_eclampsia', 'mat_aph',
                 'mat_diabetes', 'mat_hypertension_type', 'out_nnd_cause']
    drop_present = [c for c in drop_cols if c in df.columns]
    if drop_present:
        df.drop(columns=drop_present, inplace=True)
        log(f'  Dropped {len(drop_present)} sparse columns')

    # Convert outcomes AND binary predictors to 0/1
    outcome_cols = [
        'out_stillbirth', 'out_livebirth', 'out_nnd', 'out_nnd_early',
        'out_nnd_late', 'out_perinatal_death', 'out_preterm', 'out_lbw',
        'out_vlbw', 'out_sga', 'out_multiple',
    ]
    binary_predictor_cols = [
        'mat_previous_stillbirth', 'mat_previous_cs', 'hh_mosquito_net',
        'mat_previous_nnd', 'mat_hiv_status', 'out_sex_male',
    ]
    for col in outcome_cols + binary_predictor_cols:
        df = convert_outcome(df, col)

    # Sanity check
    log('\n  Outcome prevalences:')
    for col in OUTCOMES:
        if col in df.columns:
            n_events = int(df[col].sum())
            n_total = int(df[col].notna().sum())
            rate = n_events / n_total * 1000 if n_total > 0 else 0
            log(f'    {col:25s}  events={n_events:>8,}  N={n_total:>10,}  '
                f'rate={rate:.1f}/1000')
            if n_events == 0:
                sys.exit(f'ERROR: {col} has 0 events — check outcome parsing')

    # Variable availability by study source
    if 'study_source' in df.columns:
        log('\n  Variable availability by study:')
        for study in sorted(df['study_source'].dropna().unique()):
            sub = df[df['study_source'] == study]
            n_obs = len(sub)
            all_vars = NUM_S3 + CAT_S3 + BIN_S3
            present = [v for v in all_vars if v in sub.columns and sub[v].notna().any()]
            pct = len(present) / len(all_vars) * 100
            log(f'    {study:35s}  N={n_obs:>8,}  vars={len(present)}/{len(all_vars)} ({pct:.0f}%)')

    log(f'\n  Final dataset: {len(df):,} rows x {df.shape[1]} columns')
    return df


# ══════════════════════════════════════════════════════════════════════════════
# STEP 2: MAIN TRAINING LOOP
# ══════════════════════════════════════════════════════════════════════════════

def downsample_for_training(df, max_dhs=500000):
    """Downsample DHS to max_dhs rows, keep all clinical studies intact."""
    if 'study_source' not in df.columns:
        if len(df) > max_dhs:
            return df.sample(max_dhs, random_state=SEED)
        return df

    dhs_mask = df['study_source'] == 'DHS'
    n_dhs = dhs_mask.sum()
    if n_dhs <= max_dhs:
        return df

    clinical = df[~dhs_mask]
    dhs_sampled = df[dhs_mask].sample(max_dhs, random_state=SEED)
    df_out = pd.concat([clinical, dhs_sampled], ignore_index=True)
    log(f'  Downsampled DHS: {n_dhs:,} -> {max_dhs:,} '
        f'(total: {len(df):,} -> {len(df_out):,})')
    return df_out


def run_training(df):
    log('=' * 70)
    log('STARTING MODEL TRAINING')
    log('=' * 70)

    # Downsample for computational feasibility
    # (3.3M rows too large for LR with liblinear, SMOTE, etc.)
    df_train = downsample_for_training(df, max_dhs=300000)

    CV_OUTER = StratifiedKFold(n_splits=N_OUTER_FOLDS, shuffle=True, random_state=SEED)
    CV_INNER = StratifiedKFold(n_splits=N_INNER_FOLDS, shuffle=True, random_state=SEED)

    ALL_RESULTS = {}
    PROBS_DICT = {}
    BEST_MODELS = {}
    ROC_DATA = {}
    PR_DATA = {}
    BEST_PARAMS = {}

    # Precompute class imbalance info (on downsampled data)
    imbalance = {}
    for outcome in OUTCOMES:
        if outcome not in df_train.columns:
            continue
        y = df_train[outcome].dropna().astype(int)
        n_pos = (y == 1).sum()
        n_neg = (y == 0).sum()
        spw = n_neg / n_pos if n_pos > 0 else 1.0
        cw = compute_class_weight('balanced', classes=np.array([0, 1]), y=y.values)
        imbalance[outcome] = {
            'scale_pos_weight': spw,
            'class_weight_dict': {0: cw[0], 1: cw[1]},
        }
        log(f'  {outcome}: prevalence={n_pos/len(y)*100:.2f}%, spw={spw:.1f}')

    for outcome in OUTCOMES:
        if outcome not in df_train.columns:
            continue
        out_label = OUTCOME_LABELS.get(outcome, outcome)
        log(f'\n{"=" * 60}')
        log(f'  OUTCOME: {out_label} ({outcome})')
        log(f'{"=" * 60}')

        spw = imbalance[outcome]['scale_pos_weight']

        for sc_name, nums, cats, bins in SCENARIOS:
            result = build_Xy(df_train, outcome, nums, cats, bins)
            X, y, X_np, prep, feat_sets, feat_names = result
            if X is None or y.sum() < 10:
                log(f'  {sc_name}: insufficient events, skipping')
                continue

            log(f'\n  --- {sc_name}: {X_np.shape[1]} features, '
                f'{int(y.sum()):,} events / {len(y):,} total ---')

            # ── Model definitions ────────────────────────────────────────
            model_defs = []

            # Logistic Regression (Ridge — fast lbfgs solver)
            model_defs.append(('LR_Ridge', 'lr',
                               LogisticRegression(
                                   penalty='l2', solver='lbfgs', C=0.1,
                                   max_iter=2000, class_weight='balanced',
                                   random_state=SEED), None))

            # Random Forest
            model_defs.append(('RandomForest', 'tree',
                               RandomForestClassifier(
                                   n_jobs=-1, random_state=SEED,
                                   class_weight='balanced'),
                               RF_GRID))

            # XGBoost
            model_defs.append(('XGBoost', 'tree',
                               xgb.XGBClassifier(
                                   objective='binary:logistic',
                                   scale_pos_weight=spw,
                                   eval_metric='logloss',
                                   random_state=SEED, verbosity=0),
                               XGB_GRID))

            # LightGBM
            model_defs.append(('LightGBM', 'tree',
                               lgb.LGBMClassifier(
                                   is_unbalance=True,
                                   random_state=SEED, verbose=-1),
                               LGB_GRID))

            # CatBoost
            model_defs.append(('CatBoost', 'tree',
                               cb.CatBoostClassifier(
                                   loss_function='Logloss',
                                   eval_metric='AUC',
                                   auto_class_weights='Balanced',
                                   random_state=SEED, verbose=0),
                               CB_GRID))

            # MLP
            model_defs.append(('MLP', 'mlp', None, None))

            for model_name, mtype, base_model, grid in model_defs:
                t0 = time.time()
                aurocs, auprcs, briers = [], [], []
                all_y_test, all_p_test = [], []
                sens_list, spec_list = [], []
                best_fitted = None

                for fold_i, (tr_idx, te_idx) in enumerate(
                        CV_OUTER.split(X_np, y.values)):
                    X_f, X_v = X_np[tr_idx], X_np[te_idx]
                    y_f, y_v = y.values[tr_idx], y.values[te_idx]

                    # SMOTE only for tree/MLP models (LR uses class_weight)
                    if mtype in ('tree', 'mlp'):
                        try:
                            sm_ratio = min(0.1, max(0.02, y_f.mean() * 2))
                            X_f_sm, y_f_sm = SMOTE(
                                sampling_strategy=sm_ratio,
                                random_state=SEED,
                                k_neighbors=min(5, (y_f == 1).sum() - 1)
                            ).fit_resample(X_f, y_f)
                        except Exception:
                            X_f_sm, y_f_sm = X_f, y_f
                    else:
                        X_f_sm, y_f_sm = X_f, y_f

                    if mtype == 'lr':
                        m = base_model.__class__(**base_model.get_params())
                        m.fit(X_f_sm, y_f_sm)
                    elif mtype == 'tree' and grid is not None:
                        search = RandomizedSearchCV(
                            base_model.__class__(
                                **base_model.get_params()),
                            grid, n_iter=N_RANDOM_ITER,
                            cv=CV_INNER, scoring='roc_auc',
                            n_jobs=-1, random_state=SEED, verbose=0)
                        search.fit(X_f_sm, y_f_sm)
                        m = search.best_estimator_
                        if fold_i == 0:
                            BEST_PARAMS[(outcome, sc_name, model_name)] = \
                                search.best_params_
                    elif mtype == 'mlp':
                        mlp = MLPClassifier(
                            input_dim=X_np.shape[1],
                            n_trials=MLP_OPTUNA_TRIALS, seed=SEED)
                        mlp.fit(X_f_sm, y_f_sm.astype(np.float32),
                                X_v, y_v.astype(np.float32))
                        m = mlp
                        if fold_i == 0 and mlp.best_params:
                            BEST_PARAMS[(outcome, sc_name, model_name)] = \
                                mlp.best_params
                    else:
                        m = base_model.__class__(**base_model.get_params())
                        m.fit(X_f_sm, y_f_sm)

                    p = m.predict_proba(X_v)[:, 1]

                    if y_v.sum() >= 2:
                        aurocs.append(roc_auc_score(y_v, p))
                        auprcs.append(average_precision_score(y_v, p))
                        briers.append(brier_score_loss(y_v, p))

                        thr = optimal_threshold(y_v, p)
                        s, sp, _, _ = classification_at_threshold(y_v, p, thr)
                        sens_list.append(s)
                        spec_list.append(sp)

                    all_y_test.extend(y_v.tolist())
                    all_p_test.extend(p.tolist())

                    if fold_i == N_OUTER_FOLDS - 1:
                        best_fitted = m

                key = (outcome, sc_name, model_name)
                res_dict = {
                    'AUROC': np.mean(aurocs) if aurocs else np.nan,
                    'AUROC_sd': np.std(aurocs) if aurocs else np.nan,
                    'AUPRC': np.mean(auprcs) if auprcs else np.nan,
                    'AUPRC_sd': np.std(auprcs) if auprcs else np.nan,
                    'Brier': np.mean(briers) if briers else np.nan,
                    'Brier_sd': np.std(briers) if briers else np.nan,
                    'Sensitivity': np.mean(sens_list) if sens_list else np.nan,
                    'Specificity': np.mean(spec_list) if spec_list else np.nan,
                    'N': len(y),
                    'Events': int(y.sum()),
                    'n_features': X_np.shape[1],
                }
                ALL_RESULTS[key] = res_dict
                PROBS_DICT[key] = (np.array(all_y_test), np.array(all_p_test))
                if best_fitted is not None:
                    BEST_MODELS[key] = best_fitted

                # Store ROC/PR curve data
                y_all = np.array(all_y_test)
                p_all = np.array(all_p_test)
                if y_all.sum() >= 2:
                    fpr, tpr, _ = roc_curve(y_all, p_all)
                    ROC_DATA[key] = (fpr, tpr)
                    prec, rec, _ = precision_recall_curve(y_all, p_all)
                    PR_DATA[key] = (rec, prec)

                elapsed = time.time() - t0
                auc_str = (f'{np.mean(aurocs):.3f}+/-{np.std(aurocs):.3f}'
                           if aurocs else 'N/A')
                log(f'    {model_name:20s} AUROC={auc_str}  ({elapsed:.0f}s)')

                # ── MLflow: Log this model run ─────────────────────────────
                run_name = f'{out_label}_{sc_name}_{model_name}'
                with mlflow.start_run(run_name=run_name, nested=True):
                    mlflow.set_tags({
                        'outcome': outcome,
                        'outcome_label': out_label,
                        'scenario': sc_name,
                        'model_type': model_name,
                        'n_outer_folds': N_OUTER_FOLDS,
                    })
                    # Log metrics
                    for metric_name, metric_val in res_dict.items():
                        if isinstance(metric_val, (int, float)) and not np.isnan(metric_val):
                            mlflow.log_metric(metric_name, metric_val)
                    # Log best hyperparams if available
                    bp_key = (outcome, sc_name, model_name)
                    if bp_key in BEST_PARAMS:
                        mlflow.log_params({
                            str(k): str(v)
                            for k, v in BEST_PARAMS[bp_key].items()
                        })
                    # Log model artifact (sklearn-compatible only)
                    if best_fitted is not None and not isinstance(best_fitted, MLPClassifier):
                        try:
                            mlflow.sklearn.log_model(best_fitted, 'model')
                        except Exception:
                            pass

    return ALL_RESULTS, PROBS_DICT, BEST_MODELS, ROC_DATA, PR_DATA, BEST_PARAMS, imbalance


# ══════════════════════════════════════════════════════════════════════════════
# STEP 3: CALIBRATION ASSESSMENT
# ══════════════════════════════════════════════════════════════════════════════

def run_calibration(PROBS_DICT, ALL_RESULTS):
    log('\n' + '=' * 60)
    log('CALIBRATION ASSESSMENT')
    log('=' * 60)

    cal_rows = []
    cal_curves = {}

    for outcome in OUTCOMES:
        for sc_name, _, _, _ in SCENARIOS:
            # Find best model for this outcome/scenario by AUROC
            candidates = {k: v for k, v in ALL_RESULTS.items()
                          if k[0] == outcome and k[1] == sc_name}
            if not candidates:
                continue
            best_key = max(candidates, key=lambda k: candidates[k]['AUROC'])
            best_model_name = best_key[2]

            y_true, y_prob = PROBS_DICT.get(best_key, (None, None))
            if y_true is None or len(y_true) < 100:
                continue

            # Calibration metrics
            prevalence = y_true.mean()
            mean_pred = y_prob.mean()
            citl = np.log(mean_pred / (1 - mean_pred + 1e-10)) - \
                   np.log(prevalence / (1 - prevalence + 1e-10))

            # Calibration slope via logistic regression on logit(predictions)
            logit_p = np.log(y_prob / (1 - y_prob + 1e-10) + 1e-10)
            logit_p = np.clip(logit_p, -20, 20)
            from sklearn.linear_model import LogisticRegression as LR2
            cal_lr = LR2(penalty=None, max_iter=1000)
            cal_lr.fit(logit_p.reshape(-1, 1), y_true)
            cal_slope = cal_lr.coef_[0][0]

            # E/O ratio
            eo_ratio = mean_pred / (prevalence + 1e-10)

            # Calibration curve
            try:
                frac_pos, mean_pred_bins = calibration_curve(
                    y_true, y_prob, n_bins=10, strategy='quantile')
                cal_curves[(outcome, sc_name)] = (mean_pred_bins, frac_pos, best_model_name)
            except Exception:
                pass

            cal_rows.append({
                'Outcome': OUTCOME_LABELS.get(outcome, outcome),
                'Scenario': sc_name,
                'Best_Model': best_model_name,
                'CITL': round(citl, 4),
                'Cal_Slope': round(cal_slope, 4),
                'EO_Ratio': round(eo_ratio, 4),
                'AUROC': round(ALL_RESULTS[best_key]['AUROC'], 3),
            })
            log(f'  {OUTCOME_LABELS.get(outcome, outcome)} {sc_name} '
                f'({best_model_name}): CITL={citl:.3f}, slope={cal_slope:.3f}, '
                f'E/O={eo_ratio:.3f}')

    cal_df = pd.DataFrame(cal_rows)
    cal_df.to_csv(os.path.join(OUTPUT_DIR, 'results_calibration.csv'), index=False)
    log(f'  Saved results_calibration.csv')
    return cal_df, cal_curves


# ══════════════════════════════════════════════════════════════════════════════
# STEP 4: DECISION CURVE ANALYSIS
# ══════════════════════════════════════════════════════════════════════════════

def run_dca(df, PROBS_DICT, ALL_RESULTS):
    log('\n' + '=' * 60)
    log('DECISION CURVE ANALYSIS')
    log('=' * 60)

    dca_data = {}

    for outcome in OUTCOMES:
        out_label = OUTCOME_LABELS.get(outcome, outcome)
        if outcome == 'out_stillbirth':
            thr_range = np.linspace(0.001, 0.15, 150)
        else:
            thr_range = np.linspace(0.002, 0.20, 150)

        # Best ML model for S1
        s1_keys = {k: v for k, v in ALL_RESULTS.items()
                   if k[0] == outcome and k[1] == 'S1'}
        if not s1_keys:
            continue
        best_key = max(s1_keys, key=lambda k: s1_keys[k]['AUROC'])
        lr_key = (outcome, 'S1', 'LR_L2')

        models_to_plot = {}
        for k in [best_key, lr_key]:
            if k in PROBS_DICT:
                y_t, p_t = PROBS_DICT[k]
                nb_vals = [net_benefit(y_t, p_t, t) for t in thr_range]
                models_to_plot[k[2]] = nb_vals

        # Treat-all
        if best_key in PROBS_DICT:
            y_t, _ = PROBS_DICT[best_key]
            prev = y_t.mean()
            nb_all = [prev - t / (1 - t + 1e-10) * (1 - prev) for t in thr_range]
            models_to_plot['Treat All'] = nb_all

        dca_data[outcome] = (thr_range, models_to_plot)
        log(f'  {out_label}: DCA computed over {len(thr_range)} thresholds')

    return dca_data


# ══════════════════════════════════════════════════════════════════════════════
# STEP 5: SHAP INTERPRETATION
# ══════════════════════════════════════════════════════════════════════════════

def run_shap(df, BEST_MODELS):
    log('\n' + '=' * 60)
    log('SHAP FEATURE IMPORTANCE')
    log('=' * 60)

    shap_data = {}

    for outcome in OUTCOMES:
        out_label = OUTCOME_LABELS.get(outcome, outcome)
        sc_name = 'S1'

        # Prefer XGBoost for SHAP (TreeExplainer)
        xgb_key = (outcome, sc_name, 'XGBoost')
        if xgb_key not in BEST_MODELS:
            # Try any tree model
            tree_keys = [k for k in BEST_MODELS
                         if k[0] == outcome and k[1] == sc_name
                         and k[2] in ('XGBoost', 'LightGBM', 'RandomForest')]
            if not tree_keys:
                log(f'  {out_label}: no tree model available for SHAP')
                continue
            xgb_key = tree_keys[0]

        model = BEST_MODELS[xgb_key]
        result = build_Xy(df, outcome, NUM_S1, CAT_S1, BIN_S1)
        X, y, X_np, prep, _, feat_names = result
        if X is None:
            continue

        log(f'  {out_label}: Computing SHAP values ({xgb_key[2]})...')

        # Subsample for speed
        n_shap = min(SHAP_SAMPLE, len(X_np))
        idx = np.random.choice(len(X_np), n_shap, replace=False)
        X_shap = X_np[idx]

        try:
            explainer = shap.TreeExplainer(model)
            shap_vals = explainer.shap_values(X_shap)
        except Exception as e:
            log(f'    TreeExplainer failed: {e}. Trying KernelExplainer...')
            try:
                bg = shap.kmeans(X_np, 50)
                explainer = shap.KernelExplainer(model.predict_proba, bg)
                shap_vals = explainer.shap_values(X_shap)
                if isinstance(shap_vals, list):
                    shap_vals = shap_vals[1]
            except Exception as e2:
                log(f'    SHAP failed entirely: {e2}')
                continue

        # Mean absolute SHAP values
        shap_imp = pd.DataFrame({
            'Feature': feat_names,
            'Mean_abs_SHAP': np.abs(shap_vals).mean(axis=0),
        }).sort_values('Mean_abs_SHAP', ascending=False)

        shap_imp.to_csv(os.path.join(OUTPUT_DIR, f'shap_values_{outcome.split("_")[-1]}.csv'),
                        index=False)

        shap_data[outcome] = {
            'shap_values': shap_vals,
            'X_shap': X_shap,
            'feat_names': feat_names,
            'importance': shap_imp,
            'model_name': xgb_key[2],
        }

        log(f'    Top 10 features:')
        for _, row in shap_imp.head(10).iterrows():
            log(f'      {row["Feature"]:40s}  |SHAP|={row["Mean_abs_SHAP"]:.4f}')

    return shap_data


# ══════════════════════════════════════════════════════════════════════════════
# STEP 6: IECV — Leave-One-Country-Out
# ══════════════════════════════════════════════════════════════════════════════

def run_iecv(df):
    log('\n' + '=' * 60)
    log('IECV — LEAVE-ONE-COUNTRY-OUT')
    log('=' * 60)

    if 'mat_country' not in df.columns:
        log('  WARNING: mat_country not available, skipping IECV')
        return pd.DataFrame()

    iecv_rows = []

    for outcome in OUTCOMES:
        if outcome not in df.columns:
            continue
        out_label = OUTCOME_LABELS.get(outcome, outcome)
        sc_name, nums, cats, bins = SCENARIOS[0]  # S1

        mask_o = df[outcome].notna()
        df_o = df.loc[mask_o].reset_index(drop=True)

        countries = [
            c for c in df_o['mat_country'].dropna().unique()
            if (df_o[df_o['mat_country'] == c][outcome] == 1).sum() >= 5
        ]
        log(f'  {out_label}: IECV on {len(countries)} countries with >=5 events')

        n_feats = [v for v in nums if v in df.columns]
        c_feats = [v for v in cats if v in df.columns]
        b_feats = [v for v in bins if v in df.columns]

        for model_name, model_factory in [
            ('LR_L2', lambda spw: LogisticRegression(
                penalty='l2', C=1.0, class_weight='balanced',
                max_iter=2000, random_state=SEED)),
            ('XGBoost', lambda spw: xgb.XGBClassifier(
                n_estimators=300, scale_pos_weight=spw,
                eval_metric='logloss', random_state=SEED, verbosity=0)),
        ]:
            for country in countries:
                tr_m = df_o['mat_country'] != country
                te_m = df_o['mat_country'] == country

                X_tr_r = df_o.loc[tr_m, n_feats + c_feats + b_feats]
                X_te_r = df_o.loc[te_m, n_feats + c_feats + b_feats]
                y_tr = df_o.loc[tr_m, outcome].astype(int).values
                y_te = df_o.loc[te_m, outcome].astype(int).values

                p_cv = make_prep(n_feats, c_feats, b_feats)
                X_tr_np = p_cv.fit_transform(X_tr_r)
                X_te_np = p_cv.transform(X_te_r)

                spw = (y_tr == 0).sum() / max((y_tr == 1).sum(), 1)
                m = model_factory(spw)
                m.fit(X_tr_np, y_tr)
                prob = m.predict_proba(X_te_np)[:, 1]

                if y_te.sum() >= 2:
                    try:
                        auc = roc_auc_score(y_te, prob)
                        auprc = average_precision_score(y_te, prob)
                    except Exception:
                        continue

                    iecv_rows.append({
                        'Outcome': out_label,
                        'Model': model_name,
                        'Country': country,
                        'N_test': len(y_te),
                        'Events': int(y_te.sum()),
                        'Prevalence': round(y_te.mean() * 1000, 1),
                        'AUROC': round(auc, 3),
                        'AUPRC': round(auprc, 3),
                    })

            n_done = sum(1 for r in iecv_rows
                         if r['Model'] == model_name
                         and r['Outcome'] == out_label)
            log(f'    {model_name}: {n_done} countries evaluated')

    iecv_df = pd.DataFrame(iecv_rows)
    iecv_df.to_csv(os.path.join(OUTPUT_DIR, 'results_iecv.csv'), index=False)
    log(f'  Saved results_iecv.csv ({len(iecv_df)} rows)')
    return iecv_df


# ══════════════════════════════════════════════════════════════════════════════
# STEP 7: FAIRNESS / SUBGROUP ANALYSIS
# ══════════════════════════════════════════════════════════════════════════════

def run_fairness(df):
    log('\n' + '=' * 60)
    log('FAIRNESS / SUBGROUP ANALYSIS')
    log('=' * 60)

    subgroup_cols = {
        'Wealth Quintile': 'hh_wealth_quintile',
        'Education': 'mat_education',
        'Urban/Rural': 'mat_urban_rural',
        'Country': 'mat_country',
        'Study Source': 'study_source',
    }

    fairness_rows = []

    for outcome in OUTCOMES:
        if outcome not in df.columns:
            continue
        out_label = OUTCOME_LABELS.get(outcome, outcome)
        sc_name, nums, cats, bins = SCENARIOS[0]

        result = build_Xy(df, outcome, nums, cats, bins)
        X, y, X_np, prep, _, feat_names = result
        if X is None:
            continue

        # Train a model on full data for subgroup evaluation
        spw = (y == 0).sum() / max((y == 1).sum(), 1)
        model = xgb.XGBClassifier(
            n_estimators=300, scale_pos_weight=spw,
            eval_metric='logloss', random_state=SEED, verbosity=0)
        model.fit(X_np, y.values)
        prob_all = model.predict_proba(X_np)[:, 1]

        mask_o = df[outcome].notna()
        df_sub = df.loc[mask_o].copy()

        for sg_label, sg_col in subgroup_cols.items():
            if sg_col not in df_sub.columns:
                continue
            sg = df_sub[sg_col].astype(str)
            for level in sorted(sg.dropna().unique()):
                if level in ('nan', 'None', ''):
                    continue
                idx = (sg == level).values
                y_sg = y.values[idx]
                p_sg = prob_all[idx]
                if y_sg.sum() < 5 or len(y_sg) < 20:
                    continue
                try:
                    auc_sg = roc_auc_score(y_sg, p_sg)
                    auprc_sg = average_precision_score(y_sg, p_sg)
                except Exception:
                    continue
                fairness_rows.append({
                    'Outcome': out_label,
                    'Subgroup': sg_label,
                    'Level': level,
                    'N': len(y_sg),
                    'Events': int(y_sg.sum()),
                    'Prevalence_per_1k': round(y_sg.mean() * 1000, 1),
                    'AUROC': round(auc_sg, 3),
                    'AUPRC': round(auprc_sg, 3),
                })

    fairness_df = pd.DataFrame(fairness_rows)
    fairness_df.to_csv(os.path.join(OUTPUT_DIR, 'results_fairness.csv'), index=False)
    log(f'  Saved results_fairness.csv ({len(fairness_df)} rows)')
    return fairness_df


# ══════════════════════════════════════════════════════════════════════════════
# STEP 8: SAVE ALL RESULTS
# ══════════════════════════════════════════════════════════════════════════════

def save_results(ALL_RESULTS, BEST_MODELS, BEST_PARAMS, PROBS_DICT):
    log('\n' + '=' * 60)
    log('SAVING RESULTS')
    log('=' * 60)

    # Master summary table
    summary_rows = []
    for (outcome, sc, model), res in ALL_RESULTS.items():
        # Compute PPV/NPV from pooled probabilities
        ppv, npv = np.nan, np.nan
        if (outcome, sc, model) in PROBS_DICT:
            y_t, p_t = PROBS_DICT[(outcome, sc, model)]
            if len(y_t) > 0 and y_t.sum() >= 2:
                thr = optimal_threshold(y_t, p_t)
                _, _, ppv, npv = classification_at_threshold(y_t, p_t, thr)

        summary_rows.append({
            'Outcome': OUTCOME_LABELS.get(outcome, outcome),
            'Scenario': sc,
            'Model': model,
            'AUROC': round(res['AUROC'], 3),
            'AUROC_SD': round(res['AUROC_sd'], 3),
            'AUPRC': round(res['AUPRC'], 3),
            'AUPRC_SD': round(res.get('AUPRC_sd', 0), 3),
            'Brier': round(res['Brier'], 4),
            'Sensitivity': round(res['Sensitivity'], 3),
            'Specificity': round(res['Specificity'], 3),
            'PPV': round(ppv, 3) if not np.isnan(ppv) else np.nan,
            'NPV': round(npv, 3) if not np.isnan(npv) else np.nan,
            'N': res['N'],
            'Events': res['Events'],
            'n_features': res['n_features'],
        })

    summary_df = pd.DataFrame(summary_rows).sort_values(
        ['Outcome', 'Scenario', 'AUROC'], ascending=[True, True, False])
    summary_df.to_csv(os.path.join(OUTPUT_DIR, 'results_summary.csv'), index=False)
    log(f'  Saved results_summary.csv ({len(summary_df)} rows)')

    # Hyperparameters table
    if BEST_PARAMS:
        hp_rows = []
        for (outcome, sc, model), params in BEST_PARAMS.items():
            for param, val in params.items():
                hp_rows.append({
                    'Outcome': OUTCOME_LABELS.get(outcome, outcome),
                    'Scenario': sc,
                    'Model': model,
                    'Parameter': param,
                    'Best_Value': val,
                })
        hp_df = pd.DataFrame(hp_rows)
        hp_df.to_csv(os.path.join(OUTPUT_DIR, 'stable4_hyperparams.csv'), index=False)
        log(f'  Saved stable4_hyperparams.csv')

    # Serialize best models
    try:
        # Save only sklearn-compatible models (not MLP)
        serializable = {str(k): v for k, v in BEST_MODELS.items()
                        if not isinstance(v, MLPClassifier)}
        with open(os.path.join(OUTPUT_DIR, 'best_models.pkl'), 'wb') as f:
            pickle.dump(serializable, f)
        log(f'  Saved best_models.pkl ({len(serializable)} models)')
    except Exception as e:
        log(f'  WARNING: Could not save models: {e}')

    return summary_df


# ══════════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════════

def main():
    t_start = time.time()
    log('SSA Perinatal Prediction Pipeline — Starting')
    log(f'Output directory: {OUTPUT_DIR}')
    log(f'MLflow tracking: {MLFLOW_DIR}')

    # Start parent MLflow run for the entire pipeline
    with mlflow.start_run(run_name='SSA_Pipeline_Full') as parent_run:
        mlflow.set_tags({
            'pipeline_version': 'v3',
            'seed': SEED,
            'year_min': YEAR_MIN,
            'n_outer_folds': N_OUTER_FOLDS,
            'n_inner_folds': N_INNER_FOLDS,
        })

        # Step 1: Load data
        df = load_data()
        mlflow.log_params({
            'n_rows': len(df),
            'n_cols': df.shape[1],
            'n_countries': df['mat_country'].nunique() if 'mat_country' in df.columns else 0,
        })

        # Step 2: Train models (nested runs logged inside)
        (ALL_RESULTS, PROBS_DICT, BEST_MODELS,
         ROC_DATA, PR_DATA, BEST_PARAMS, imbalance) = run_training(df)

        # Step 3: Calibration
        cal_df, cal_curves = run_calibration(PROBS_DICT, ALL_RESULTS)

        # Step 4: DCA
        dca_data = run_dca(df, PROBS_DICT, ALL_RESULTS)

        # Step 5: SHAP
        shap_data = run_shap(df, BEST_MODELS)

        # Step 6: IECV
        iecv_df = run_iecv(df)

        # Step 7: Fairness
        fairness_df = run_fairness(df)

        # Step 8: Save everything
        summary_df = save_results(ALL_RESULTS, BEST_MODELS, BEST_PARAMS, PROBS_DICT)

        # ── MLflow: Log CSV artifacts ──────────────────────────────────
        for csv_file in ['results_summary.csv', 'results_calibration.csv',
                         'results_iecv.csv', 'results_fairness.csv',
                         'stable4_hyperparams.csv']:
            csv_path = os.path.join(OUTPUT_DIR, csv_file)
            if os.path.exists(csv_path):
                mlflow.log_artifact(csv_path, 'results')

        # Log best overall AUROC per outcome
        for outcome in OUTCOMES:
            out_label = OUTCOME_LABELS.get(outcome, outcome)
            candidates = {k: v for k, v in ALL_RESULTS.items() if k[0] == outcome}
            if candidates:
                best_key = max(candidates, key=lambda k: candidates[k]['AUROC'])
                mlflow.log_metric(f'best_AUROC_{out_label}', candidates[best_key]['AUROC'])
                mlflow.log_metric(f'best_AUPRC_{out_label}', candidates[best_key]['AUPRC'])

        log(f'MLflow parent run ID: {parent_run.info.run_id}')

        # Save intermediate data for figure generation
        intermediate = {
            'ALL_RESULTS': ALL_RESULTS,
            'ROC_DATA': {str(k): (v[0].tolist(), v[1].tolist())
                         for k, v in ROC_DATA.items()},
            'PR_DATA': {str(k): (v[0].tolist(), v[1].tolist())
                        for k, v in PR_DATA.items()},
            'cal_curves': {str(k): (v[0].tolist(), v[1].tolist(), v[2])
                           for k, v in cal_curves.items()},
            'dca_data': {str(k): (v[0].tolist(), {mn: nb for mn, nb in v[1].items()})
                         for k, v in dca_data.items()},
            'PROBS_DICT': {str(k): (v[0].tolist(), v[1].tolist())
                           for k, v in PROBS_DICT.items()},
        }
        with open(os.path.join(OUTPUT_DIR, '_intermediate_data.json'), 'w') as f:
            json.dump(intermediate, f)

        # Save SHAP data separately (numpy arrays)
        for outcome, sd in shap_data.items():
            np.savez_compressed(
                os.path.join(OUTPUT_DIR, f'_shap_data_{outcome}.npz'),
                shap_values=sd['shap_values'],
                X_shap=sd['X_shap'],
                feat_names=sd['feat_names'],
            )

        elapsed = time.time() - t_start
        log(f'\n{"=" * 60}')
        log(f'PIPELINE COMPLETE — {elapsed / 60:.1f} minutes')
        log(f'{"=" * 60}')
        log(f'Results saved to: {OUTPUT_DIR}')
        log(f'\nFiles generated:')
        for f_name in sorted(os.listdir(OUTPUT_DIR)):
            size = os.path.getsize(os.path.join(OUTPUT_DIR, f_name))
            log(f'  {f_name:45s}  {size/1024:.0f} KB')

        # Quick validation
        log(f'\nVALIDATION:')
        log(f'  Expected rows in results_summary.csv: ~{2*3*6} (2 outcomes x 3 scenarios x 6 models)')
        log(f'  Actual rows: {len(summary_df)}')

        auroc_vals = summary_df['AUROC'].dropna()
        log(f'  AUROC range: {auroc_vals.min():.3f} — {auroc_vals.max():.3f}')
        if auroc_vals.min() < 0.45 or auroc_vals.max() > 0.99:
            log(f'  WARNING: AUROC values outside expected range (0.50-0.95)')

        log(f'\nMLflow UI: cd "{SCRIPT_DIR}" && mlflow ui')

    return 0


if __name__ == '__main__':
    sys.exit(main())
