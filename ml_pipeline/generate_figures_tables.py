#!/usr/bin/env python3
"""
==============================================================================
Generate All Figures and Tables for Article + Supplementary Material
==============================================================================
Reads results from outputs_ML_results/ (produced by run_modeling_pipeline.py)
and generates publication-ready figures (300 DPI, PNG + PDF) and tables.

Usage:
    conda run -n base python generate_figures_tables.py
==============================================================================
"""

import os, sys, json, warnings
warnings.filterwarnings('ignore')

import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.lines import Line2D
import seaborn as sns

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(SCRIPT_DIR, 'outputs_ML_results')

DPI = 300
FIG_FORMAT = ['png', 'pdf']

OUTCOME_LABELS = {'out_stillbirth': 'Stillbirth', 'out_nnd': 'Neonatal Death'}
OUTCOMES = ['out_stillbirth', 'out_nnd']

# Publication style
plt.rcParams.update({
    'font.size': 10,
    'axes.titlesize': 12,
    'axes.labelsize': 11,
    'xtick.labelsize': 9,
    'ytick.labelsize': 9,
    'legend.fontsize': 8,
    'figure.dpi': 100,
    'savefig.dpi': DPI,
    'savefig.bbox': 'tight',
    'font.family': 'sans-serif',
})

# Color palette for models
MODEL_COLORS = {
    'LR_L2': '#1f77b4',
    'LR_L1': '#aec7e8',
    'LR_ElasticNet': '#6baed6',
    'RandomForest': '#2ca02c',
    'XGBoost': '#d62728',
    'LightGBM': '#ff7f0e',
    'CatBoost': '#9467bd',
    'MLP': '#8c564b',
}

REGION_COLORS = {
    'East Africa': '#1f77b4',
    'West Africa': '#ff7f0e',
    'Central Africa': '#2ca02c',
    'Southern Africa': '#d62728',
    'Other': '#9467bd',
}

REGION_MAP = {
    'Ethiopia': 'East Africa', 'Kenya': 'East Africa',
    'Tanzania': 'East Africa', 'Uganda': 'East Africa',
    'Rwanda': 'East Africa', 'Burundi': 'East Africa',
    'Somalia': 'East Africa', 'South Sudan': 'East Africa',
    'Sudan': 'East Africa', 'Djibouti': 'East Africa',
    'Eritrea': 'East Africa', 'Comoros': 'East Africa',
    'Nigeria': 'West Africa', 'Ghana': 'West Africa',
    'Senegal': 'West Africa', 'Mali': 'West Africa',
    'Burkina Faso': 'West Africa', 'Niger': 'West Africa',
    'Benin': 'West Africa', 'Togo': 'West Africa',
    'Guinea': 'West Africa', 'Sierra Leone': 'West Africa',
    'Liberia': 'West Africa', 'Gambia': 'West Africa',
    'Mauritania': 'West Africa', "Cote d'Ivoire": 'West Africa',
    'Democratic Republic of the Congo': 'Central Africa',
    'Congo': 'Central Africa', 'Cameroon': 'Central Africa',
    'Chad': 'Central Africa', 'Central African Republic': 'Central Africa',
    'Gabon': 'Central Africa', 'Equatorial Guinea': 'Central Africa',
    'Mozambique': 'Southern Africa', 'Zimbabwe': 'Southern Africa',
    'Zambia': 'Southern Africa', 'Malawi': 'Southern Africa',
    'South Africa': 'Southern Africa', 'Namibia': 'Southern Africa',
    'Botswana': 'Southern Africa', 'Lesotho': 'Southern Africa',
    'Eswatini': 'Southern Africa', 'Madagascar': 'Southern Africa',
    'Angola': 'Southern Africa',
}


def save_fig(fig, name):
    """Save figure in multiple formats."""
    for fmt in FIG_FORMAT:
        path = os.path.join(OUTPUT_DIR, f'{name}.{fmt}')
        fig.savefig(path, dpi=DPI, bbox_inches='tight', facecolor='white')
    plt.close(fig)
    print(f'  Saved {name}.png/.pdf')


def parse_key(key_str):
    """Parse string key like "('out_stillbirth', 'S1', 'XGBoost')" back to tuple."""
    return eval(key_str)


def load_data():
    """Load all intermediate data from the pipeline."""
    data = {}

    # Summary CSV
    path = os.path.join(OUTPUT_DIR, 'results_summary.csv')
    if os.path.exists(path):
        data['summary'] = pd.read_csv(path)
    else:
        sys.exit(f'ERROR: {path} not found. Run run_modeling_pipeline.py first.')

    # Other CSVs
    for name in ['results_calibration', 'results_iecv', 'results_fairness',
                  'stable4_hyperparams']:
        path = os.path.join(OUTPUT_DIR, f'{name}.csv')
        if os.path.exists(path):
            data[name] = pd.read_csv(path)

    # Intermediate JSON
    json_path = os.path.join(OUTPUT_DIR, '_intermediate_data.json')
    if os.path.exists(json_path):
        with open(json_path) as f:
            intermediate = json.load(f)
        data['intermediate'] = intermediate

    # SHAP data
    data['shap'] = {}
    for outcome in OUTCOMES:
        npz_path = os.path.join(OUTPUT_DIR, f'_shap_data_{outcome}.npz')
        if os.path.exists(npz_path):
            npz = np.load(npz_path, allow_pickle=True)
            data['shap'][outcome] = {
                'shap_values': npz['shap_values'],
                'X_shap': npz['X_shap'],
                'feat_names': list(npz['feat_names']),
            }

    # SHAP importance CSVs
    for suffix in ['sb', 'nnd']:
        path = os.path.join(OUTPUT_DIR, f'shap_values_{suffix}.csv')
        if os.path.exists(path):
            data[f'shap_imp_{suffix}'] = pd.read_csv(path)

    return data


# ══════════════════════════════════════════════════════════════════════════════
# FIGURE 1: AUROC Comparison Heatmap
# ══════════════════════════════════════════════════════════════════════════════

def fig1_auroc_heatmap(data):
    print('Generating Figure 1: AUROC Heatmap...')
    df = data['summary'].copy()

    fig, axes = plt.subplots(1, 2, figsize=(14, 6))

    for ax, outcome_label in zip(axes, ['Stillbirth', 'Neonatal Death']):
        sub = df[df['Outcome'] == outcome_label]
        if sub.empty:
            continue
        pivot = sub.pivot_table(index='Model', columns='Scenario',
                                values='AUROC', aggfunc='first')
        pivot = pivot.reindex(columns=['S1', 'S2', 'S3'])
        pivot = pivot.sort_values('S1', ascending=False)

        sns.heatmap(pivot, annot=True, fmt='.3f', cmap='RdYlGn',
                    vmin=0.50, vmax=0.90, ax=ax, linewidths=0.5,
                    cbar_kws={'label': 'AUROC'})
        ax.set_title(f'{outcome_label}')
        ax.set_ylabel('Model')
        ax.set_xlabel('Scenario')

    fig.suptitle('AUROC by Model and Clinical Scenario', fontsize=14, y=1.02)
    plt.tight_layout()
    save_fig(fig, 'fig1_auroc_heatmap')


# ══════════════════════════════════════════════════════════════════════════════
# FIGURE 2: ROC Curves (best models per scenario)
# ══════════════════════════════════════════════════════════════════════════════

def fig2_roc_curves(data):
    print('Generating Figure 2: ROC Curves...')
    inter = data.get('intermediate', {})
    roc = inter.get('ROC_DATA', {})
    summary = data['summary']

    fig, axes = plt.subplots(2, 3, figsize=(16, 10))

    for row_idx, outcome in enumerate(OUTCOMES):
        out_label = OUTCOME_LABELS[outcome]
        for col_idx, scenario in enumerate(['S1', 'S2', 'S3']):
            ax = axes[row_idx, col_idx]

            # Get all models for this outcome/scenario
            sub = summary[(summary['Outcome'] == out_label) &
                          (summary['Scenario'] == scenario)]
            sub = sub.sort_values('AUROC', ascending=False)

            for _, row in sub.iterrows():
                model = row['Model']
                key_str = str((outcome, scenario, model))
                if key_str in roc:
                    fpr, tpr = roc[key_str]
                    color = MODEL_COLORS.get(model, '#7f7f7f')
                    ax.plot(fpr, tpr, color=color, lw=1.5,
                            label=f'{model} ({row["AUROC"]:.3f})')

            ax.plot([0, 1], [0, 1], 'k--', lw=0.8, alpha=0.5)
            ax.set_xlim([0, 1])
            ax.set_ylim([0, 1])
            ax.set_xlabel('1 - Specificity')
            ax.set_ylabel('Sensitivity')
            ax.set_title(f'{out_label} - {scenario}')
            ax.legend(fontsize=7, loc='lower right')

    plt.tight_layout()
    save_fig(fig, 'fig2_roc_curves')


# ══════════════════════════════════════════════════════════════════════════════
# FIGURE 3: Calibration Plots
# ══════════════════════════════════════════════════════════════════════════════

def fig3_calibration(data):
    print('Generating Figure 3: Calibration...')
    inter = data.get('intermediate', {})
    cal_curves = inter.get('cal_curves', {})
    cal_df = data.get('results_calibration')

    if not cal_curves:
        print('  Skipping — no calibration data')
        return

    fig, axes = plt.subplots(1, len(cal_curves), figsize=(6 * len(cal_curves), 5))
    if len(cal_curves) == 1:
        axes = [axes]

    for ax, (key_str, (mean_pred, frac_pos, model_name)) in zip(axes, cal_curves.items()):
        key = parse_key(key_str)
        outcome, scenario = key[0], key[1]
        out_label = OUTCOME_LABELS.get(outcome, outcome)

        ax.plot([0, max(mean_pred) * 1.1], [0, max(mean_pred) * 1.1],
                'k--', lw=1, label='Perfect calibration')
        ax.plot(mean_pred, frac_pos, 'o-', color='steelblue', lw=2,
                markersize=6, label=model_name)
        ax.set_xlabel('Mean Predicted Probability')
        ax.set_ylabel('Observed Frequency')
        ax.set_title(f'{out_label} ({scenario})')
        ax.legend()

        # Add calibration metrics from table
        if cal_df is not None:
            match = cal_df[(cal_df['Scenario'] == scenario)]
            match = match[match['Outcome'] == out_label]
            if not match.empty:
                r = match.iloc[0]
                txt = (f'CITL: {r["CITL"]:.3f}\n'
                       f'Slope: {r["Cal_Slope"]:.3f}\n'
                       f'E/O: {r["EO_Ratio"]:.3f}')
                ax.text(0.05, 0.95, txt, transform=ax.transAxes,
                        fontsize=8, va='top',
                        bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5))

    plt.tight_layout()
    save_fig(fig, 'fig3_calibration')


# ══════════════════════════════════════════════════════════════════════════════
# FIGURE 4: Decision Curve Analysis
# ══════════════════════════════════════════════════════════════════════════════

def fig4_dca(data):
    print('Generating Figure 4: DCA...')
    inter = data.get('intermediate', {})
    dca_data = inter.get('dca_data', {})

    if not dca_data:
        print('  Skipping — no DCA data')
        return

    fig, axes = plt.subplots(1, 2, figsize=(14, 5))

    for ax, outcome in zip(axes, OUTCOMES):
        out_label = OUTCOME_LABELS.get(outcome, outcome)
        key_str = str(outcome)

        if key_str not in dca_data:
            # Try the raw key
            matching = [k for k in dca_data if outcome in k]
            if matching:
                key_str = matching[0]
            else:
                continue

        thr_range, models_nb = dca_data[key_str]
        thr_range = np.array(thr_range)

        ax.axhline(0, color='black', lw=2, label='Treat None')

        colors = plt.cm.tab10(np.linspace(0, 1, len(models_nb)))
        for (model_name, nb_vals), color in zip(models_nb.items(), colors):
            style = '--' if model_name == 'Treat All' else '-'
            lw = 1.5 if model_name == 'Treat All' else 2
            if model_name == 'Treat All':
                color = 'red'
            ax.plot(thr_range, nb_vals, style, color=color, lw=lw,
                    label=model_name)

        ax.set_xlabel('Threshold Probability')
        ax.set_ylabel('Net Benefit')
        ax.set_title(f'Decision Curve — {out_label}')
        ax.legend(fontsize=9)
        ax.set_ylim(bottom=-0.02)

    plt.tight_layout()
    save_fig(fig, 'fig4_dca')


# ══════════════════════════════════════════════════════════════════════════════
# FIGURE 5: SHAP Beeswarm
# ══════════════════════════════════════════════════════════════════════════════

def fig5_shap_beeswarm(data):
    print('Generating Figure 5: SHAP Beeswarm...')

    shap_data = data.get('shap', {})
    if not shap_data:
        print('  Skipping — no SHAP data')
        return

    try:
        import shap as shap_lib
    except ImportError:
        print('  Skipping — shap not installed')
        return

    n_panels = len(shap_data)
    fig, axes = plt.subplots(1, n_panels, figsize=(10 * n_panels, 8))
    if n_panels == 1:
        axes = [axes]

    for ax, (outcome, sd) in zip(axes, shap_data.items()):
        out_label = OUTCOME_LABELS.get(outcome, outcome)
        shap_vals = sd['shap_values']
        X_shap = sd['X_shap']
        feat_names = sd['feat_names']

        plt.sca(ax)
        shap_lib.summary_plot(
            shap_vals, features=pd.DataFrame(X_shap, columns=feat_names),
            feature_names=feat_names, max_display=20, show=False)
        ax.set_title(f'SHAP — {out_label} (S1)')

    plt.tight_layout()
    save_fig(fig, 'fig5_shap_beeswarm')


# ══════════════════════════════════════════════════════════════════════════════
# FIGURE 6: IECV Forest Plot
# ══════════════════════════════════════════════════════════════════════════════

def fig6_iecv_forest(data):
    print('Generating Figure 6: IECV Forest Plot...')
    iecv = data.get('results_iecv')
    if iecv is None or iecv.empty:
        print('  Skipping — no IECV data')
        return

    # Use LR_L2 for forest plot (simpler model, cleaner interpretation)
    model_to_plot = 'LR_L2'
    if model_to_plot not in iecv['Model'].values:
        model_to_plot = iecv['Model'].iloc[0]

    n_outcomes = iecv['Outcome'].nunique()
    fig, axes = plt.subplots(1, n_outcomes, figsize=(8 * n_outcomes, max(6, len(iecv) * 0.2)))
    if n_outcomes == 1:
        axes = [axes]

    for ax, out_label in zip(axes, iecv['Outcome'].unique()):
        sub = iecv[(iecv['Outcome'] == out_label) & (iecv['Model'] == model_to_plot)]
        sub = sub.sort_values('AUROC')

        countries = sub['Country'].values
        aurocs = sub['AUROC'].values
        events = sub['Events'].values

        # Color by region
        colors = [REGION_COLORS.get(REGION_MAP.get(c, 'Other'), '#7f7f7f')
                  for c in countries]

        y_pos = np.arange(len(countries))
        ax.barh(y_pos, aurocs, color=colors, alpha=0.85, height=0.7)
        ax.set_yticks(y_pos)
        ax.set_yticklabels(countries, fontsize=8)

        ax.axvline(0.70, color='green', linestyle='--', lw=1.2, label='AUROC=0.70')
        ax.axvline(0.60, color='orange', linestyle='--', lw=1.2, label='AUROC=0.60')
        ax.axvline(0.50, color='red', linestyle=':', lw=1, alpha=0.5)

        # Add event counts
        for i, (auc, ev) in enumerate(zip(aurocs, events)):
            ax.text(auc + 0.005, i, f' {auc:.3f} (n={ev})',
                    va='center', fontsize=7)

        ax.set_xlabel('AUROC')
        ax.set_title(f'IECV — {out_label} ({model_to_plot})')
        ax.set_xlim([0.35, 1.05])

        # Region legend
        legend_handles = [mpatches.Patch(color=c, label=r)
                          for r, c in REGION_COLORS.items()]
        ax.legend(handles=legend_handles, fontsize=7, loc='lower right')

        # Summary statistics
        mean_auc = aurocs.mean()
        median_auc = np.median(aurocs)
        ax.text(0.02, 0.98,
                f'Mean AUROC: {mean_auc:.3f}\nMedian: {median_auc:.3f}\n'
                f'N countries: {len(countries)}',
                transform=ax.transAxes, fontsize=8, va='top',
                bbox=dict(boxstyle='round', facecolor='lightyellow', alpha=0.7))

    plt.tight_layout()
    save_fig(fig, 'fig6_iecv_forest')


# ══════════════════════════════════════════════════════════════════════════════
# TABLE 4: Model Performance Comparison
# ══════════════════════════════════════════════════════════════════════════════

def table4_model_performance(data):
    print('Generating Table 4: Model Performance...')
    df = data['summary'].copy()

    # Format: AUROC (SD)
    df['AUROC_fmt'] = df.apply(lambda r: f"{r['AUROC']:.3f} ({r['AUROC_SD']:.3f})", axis=1)
    df['AUPRC_fmt'] = df.apply(lambda r: f"{r['AUPRC']:.3f} ({r['AUPRC_SD']:.3f})", axis=1)
    df['Brier_fmt'] = df['Brier'].apply(lambda x: f'{x:.4f}')

    table = df[['Outcome', 'Scenario', 'Model', 'AUROC_fmt', 'AUPRC_fmt',
                'Brier_fmt', 'N', 'Events']].copy()
    table.columns = ['Outcome', 'Scenario', 'Model', 'AUROC (SD)', 'AUPRC (SD)',
                     'Brier', 'N', 'Events']
    table.to_csv(os.path.join(OUTPUT_DIR, 'table4_model_performance.csv'), index=False)
    print(f'  Saved table4_model_performance.csv')


# ══════════════════════════════════════════════════════════════════════════════
# TABLE 5: Classification Metrics at Optimal Threshold
# ══════════════════════════════════════════════════════════════════════════════

def table5_classification_metrics(data):
    print('Generating Table 5: Classification Metrics...')
    df = data['summary'].copy()

    # Best model per outcome/scenario
    best = df.loc[df.groupby(['Outcome', 'Scenario'])['AUROC'].idxmax()]
    cols = ['Outcome', 'Scenario', 'Model', 'AUROC', 'Sensitivity',
            'Specificity', 'PPV', 'NPV']
    available_cols = [c for c in cols if c in best.columns]
    table = best[available_cols].copy()
    table.to_csv(os.path.join(OUTPUT_DIR, 'table5_classification_metrics.csv'),
                 index=False)
    print(f'  Saved table5_classification_metrics.csv')


# ══════════════════════════════════════════════════════════════════════════════
# SUPPLEMENTARY FIGURE 1: PR Curves
# ══════════════════════════════════════════════════════════════════════════════

def sfig1_pr_curves(data):
    print('Generating sFig 1: PR Curves...')
    inter = data.get('intermediate', {})
    pr = inter.get('PR_DATA', {})
    summary = data['summary']

    fig, axes = plt.subplots(2, 3, figsize=(16, 10))

    for row_idx, outcome in enumerate(OUTCOMES):
        out_label = OUTCOME_LABELS[outcome]
        for col_idx, scenario in enumerate(['S1', 'S2', 'S3']):
            ax = axes[row_idx, col_idx]
            sub = summary[(summary['Outcome'] == out_label) &
                          (summary['Scenario'] == scenario)]
            sub = sub.sort_values('AUPRC', ascending=False)

            for _, row in sub.iterrows():
                model = row['Model']
                key_str = str((outcome, scenario, model))
                if key_str in pr:
                    rec, prec = pr[key_str]
                    color = MODEL_COLORS.get(model, '#7f7f7f')
                    ax.plot(rec, prec, color=color, lw=1.5,
                            label=f'{model} ({row["AUPRC"]:.3f})')

            ax.set_xlabel('Recall')
            ax.set_ylabel('Precision')
            ax.set_title(f'{out_label} - {scenario}')
            ax.legend(fontsize=7, loc='upper right')

    plt.tight_layout()
    save_fig(fig, 'sfig1_pr_curves')


# ══════════════════════════════════════════════════════════════════════════════
# SUPPLEMENTARY FIGURE 2: SHAP Partial Dependence
# ══════════════════════════════════════════════════════════════════════════════

def sfig2_shap_pdp(data):
    print('Generating sFig 2: SHAP Partial Dependence...')
    shap_data = data.get('shap', {})
    if not shap_data:
        print('  Skipping — no SHAP data')
        return

    try:
        import shap as shap_lib
    except ImportError:
        print('  Skipping — shap not installed')
        return

    fig, axes = plt.subplots(2, 5, figsize=(24, 8))

    for row_idx, (outcome, sd) in enumerate(shap_data.items()):
        out_label = OUTCOME_LABELS.get(outcome, outcome)
        shap_vals = sd['shap_values']
        X_shap = sd['X_shap']
        feat_names = sd['feat_names']

        # Top 5 features by mean |SHAP|
        mean_shap = np.abs(shap_vals).mean(axis=0)
        top5_idx = np.argsort(mean_shap)[-5:][::-1]

        for col_idx, feat_idx in enumerate(top5_idx):
            ax = axes[row_idx, col_idx]
            feat_name = feat_names[feat_idx]
            ax.scatter(X_shap[:, feat_idx], shap_vals[:, feat_idx],
                       alpha=0.3, s=2, color='steelblue')
            ax.axhline(0, color='black', lw=0.5)
            ax.set_xlabel(feat_name, fontsize=8)
            ax.set_ylabel('SHAP value' if col_idx == 0 else '')
            if col_idx == 2:
                ax.set_title(f'{out_label}', fontsize=11)

    plt.tight_layout()
    save_fig(fig, 'sfig2_shap_pdp')


# ══════════════════════════════════════════════════════════════════════════════
# SUPPLEMENTARY FIGURE 3: Fairness
# ══════════════════════════════════════════════════════════════════════════════

def sfig3_fairness(data):
    print('Generating sFig 3: Fairness...')
    fairness = data.get('results_fairness')
    if fairness is None or fairness.empty:
        print('  Skipping — no fairness data')
        return

    # Focus on wealth, education, urban/rural
    subgroups = ['Wealth Quintile', 'Education', 'Urban/Rural']
    fair_sub = fairness[fairness['Subgroup'].isin(subgroups)]

    if fair_sub.empty:
        print('  Skipping — no matching subgroups')
        return

    n_outcomes = fair_sub['Outcome'].nunique()
    n_subgroups = len(subgroups)

    fig, axes = plt.subplots(n_outcomes, n_subgroups,
                              figsize=(5 * n_subgroups, 4 * n_outcomes))
    if n_outcomes == 1:
        axes = axes.reshape(1, -1)

    for row_idx, out_label in enumerate(fair_sub['Outcome'].unique()):
        for col_idx, sg in enumerate(subgroups):
            ax = axes[row_idx, col_idx]
            sub = fair_sub[(fair_sub['Outcome'] == out_label) &
                           (fair_sub['Subgroup'] == sg)]
            if sub.empty:
                ax.set_visible(False)
                continue

            sub = sub.sort_values('AUROC')
            bars = ax.barh(sub['Level'], sub['AUROC'], color='steelblue', alpha=0.85)
            ax.axvline(0.70, color='green', linestyle='--', lw=1)
            ax.set_xlabel('AUROC')
            ax.set_title(f'{out_label}\n{sg}', fontsize=10)
            ax.set_xlim([0.4, max(sub['AUROC'].max() + 0.1, 0.85)])

            for bar, auc in zip(bars, sub['AUROC']):
                ax.text(bar.get_width() + 0.005, bar.get_y() + bar.get_height() / 2,
                        f'{auc:.3f}', va='center', fontsize=8)

    plt.tight_layout()
    save_fig(fig, 'sfig3_fairness')


# ══════════════════════════════════════════════════════════════════════════════
# SUPPLEMENTARY FIGURE 4: Feature Importance Bar Chart
# ══════════════════════════════════════════════════════════════════════════════

def sfig4_feature_importance(data):
    print('Generating sFig 4: Feature Importance...')

    # Use SHAP importance data
    fig, axes = plt.subplots(1, 2, figsize=(12, 8))

    for ax, (suffix, outcome) in zip(axes, [('sb', 'out_stillbirth'), ('nnd', 'out_nnd')]):
        out_label = OUTCOME_LABELS.get(outcome, outcome)
        key = f'shap_imp_{suffix}'
        if key not in data:
            ax.set_visible(False)
            continue

        imp = data[key].head(20)
        ax.barh(imp['Feature'][::-1], imp['Mean_abs_SHAP'][::-1],
                color='steelblue', alpha=0.85)
        ax.set_xlabel('Mean |SHAP value|')
        ax.set_title(f'Feature Importance — {out_label}')

    plt.tight_layout()
    save_fig(fig, 'sfig4_feature_importance')


# ══════════════════════════════════════════════════════════════════════════════
# SUPPLEMENTARY FIGURE 5: Hyperparameter Sensitivity
# ══════════════════════════════════════════════════════════════════════════════

def sfig5_hyperparam(data):
    print('Generating sFig 5: Hyperparameter Sensitivity...')
    hp = data.get('stable4_hyperparams')
    if hp is None or hp.empty:
        print('  Skipping — no hyperparameter data')
        return

    # Show learning rate distributions for tree models
    lr_data = hp[hp['Parameter'] == 'learning_rate']
    if lr_data.empty:
        print('  Skipping — no learning_rate in hyperparams')
        return

    fig, ax = plt.subplots(figsize=(10, 5))
    models = lr_data['Model'].unique()
    x = np.arange(len(lr_data))

    for i, (_, row) in enumerate(lr_data.iterrows()):
        color = MODEL_COLORS.get(row['Model'], '#7f7f7f')
        label = f"{row['Outcome']} - {row['Scenario']} - {row['Model']}"
        ax.bar(i, float(row['Best_Value']), color=color, alpha=0.85)
        ax.text(i, float(row['Best_Value']) + 0.002, f"{float(row['Best_Value']):.3f}",
                ha='center', fontsize=7, rotation=45)

    ax.set_xticks(range(len(lr_data)))
    ax.set_xticklabels([f"{r['Outcome'][:3]}-{r['Scenario']}-{r['Model']}"
                         for _, r in lr_data.iterrows()],
                        rotation=45, ha='right', fontsize=7)
    ax.set_ylabel('Best Learning Rate')
    ax.set_title('Best Learning Rate by Model/Scenario/Outcome')
    plt.tight_layout()
    save_fig(fig, 'sfig5_hyperparam')


# ══════════════════════════════════════════════════════════════════════════════
# SUPPLEMENTARY TABLES
# ══════════════════════════════════════════════════════════════════════════════

def supplementary_tables(data):
    print('Generating Supplementary Tables...')

    # sTable 1: Full IECV results
    iecv = data.get('results_iecv')
    if iecv is not None and not iecv.empty:
        iecv.to_csv(os.path.join(OUTPUT_DIR, 'stable1_iecv_full.csv'), index=False)
        print(f'  Saved stable1_iecv_full.csv')

    # sTable 2: Fairness metrics
    fairness = data.get('results_fairness')
    if fairness is not None and not fairness.empty:
        fairness.to_csv(os.path.join(OUTPUT_DIR, 'stable2_fairness.csv'), index=False)
        print(f'  Saved stable2_fairness.csv')

    # sTable 3: SHAP top 30
    for suffix, outcome in [('sb', 'out_stillbirth'), ('nnd', 'out_nnd')]:
        key = f'shap_imp_{suffix}'
        if key in data:
            top30 = data[key].head(30)
            top30.to_csv(os.path.join(OUTPUT_DIR, f'stable3_shap_importance_{suffix}.csv'),
                         index=False)
            print(f'  Saved stable3_shap_importance_{suffix}.csv')


# ══════════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════════

def main():
    print('=' * 60)
    print('GENERATING FIGURES AND TABLES')
    print('=' * 60)
    print(f'Output directory: {OUTPUT_DIR}\n')

    data = load_data()
    print(f'Loaded: {list(data.keys())}\n')

    # Main article figures
    fig1_auroc_heatmap(data)
    fig2_roc_curves(data)
    fig3_calibration(data)
    fig4_dca(data)
    fig5_shap_beeswarm(data)
    fig6_iecv_forest(data)

    # Main article tables
    table4_model_performance(data)
    table5_classification_metrics(data)

    # Supplementary figures
    sfig1_pr_curves(data)
    sfig2_shap_pdp(data)
    sfig3_fairness(data)
    sfig4_feature_importance(data)
    sfig5_hyperparam(data)

    # Supplementary tables
    supplementary_tables(data)

    print(f'\n{"=" * 60}')
    print('ALL FIGURES AND TABLES GENERATED')
    print(f'{"=" * 60}')
    print(f'\nFiles in {OUTPUT_DIR}:')
    for f in sorted(os.listdir(OUTPUT_DIR)):
        if f.startswith('_'):
            continue
        size = os.path.getsize(os.path.join(OUTPUT_DIR, f))
        print(f'  {f:50s}  {size/1024:.0f} KB')

    return 0


if __name__ == '__main__':
    sys.exit(main())
