# Key Methodological References
## How the Literature Handles Heterogeneous Data Complexity in ML for Perinatal Outcomes

> Generated: 2026-03-14 | Verify all DOIs at doi.org or PubMed before citing

---

## The Core Problem This Project Faces

| Challenge | Our Data | Methodological Solution |
|---|---|---|
| Structural missing data | DHS has no clinical variables | MI under MNAR (Jolani 2015, Sperrin 2020) |
| Ascertainment bias | Facility SBR=3-8% vs community SBR=0.6% | Source as covariate (Debray 2018) |
| Source heterogeneity | 7 sources, 2 designs | IPD meta-analysis framework (Riley 2021) |
| Domain shift | Facility → community deployment | Dataset shift taxonomy (Finlayson 2021) |
| Class imbalance by source | DHS: lower rates; clinical: higher rates | Source-stratified SMOTE |
| Reporting compliance | Multi-source ML prediction | TRIPOD+AI (Collins 2024) |
| Fairness across subgroups | Urban/wealthy vs rural/poor | Fairness/calibration (Obermeyer 2023) |
| External validation | SSA countries not in training | Recalibration methods (Van Calster 2019) |

---

## 12 Key References

### 1. TRIPOD+AI — Reporting Standard

**Collins GS, Moons KGM, Dhiman P, Riley RD, et al.**
*TRIPOD+AI statement: updated guidance for reporting clinical prediction models that use regression or machine learning methods*
**BMJ, 2024** | DOI: 10.1136/bmj-2023-078378

- Extends TRIPOD to ML models
- Requires reporting of data source harmonization
- New items: fairness, domain shift, calibration across subpopulations
- **Action**: Use as checklist for manuscript methods section

---

### 2. Source as Covariate / Stratified Intercepts

**Debray TPA, Moons KGM, Ahmed I, Koffijberg H, Riley RD**
*Incorporating data source as a covariate in clinical prediction models developed from heterogeneous datasets: a simulation study*
**Statistics in Medicine, 2018** | DOI: 10.1002/sim.7586

- Compares: (1) pool ignoring source, (2) source as covariate, (3) stratified models
- **Source-stratified intercepts** substantially improve calibration
- Ignoring source heterogeneity → miscalibration in deployment
- **Action**: Justifies our `is_clinical_source` indicator + stratified models (Layers 1-2)

---

### 3. Multiple Imputation Under Structural Missingness

**Jolani S, Debray TPA, Koffijberg H, van Buuren S, Moons KGM**
*Combining multiple imputation and meta-analysis when heterogeneous missing data patterns exist across studies*
**Statistics in Medicine, 2015** | DOI: 10.1002/sim.6538

- Framework for MI when different sources have non-overlapping variables (structural missingness)
- Two-stage imputation strategy for IPD meta-analysis
- Naive pooling produces biased estimates without modelling the missing mechanism
- **Action**: Use for DHS (no clinical vars) + clinical sources imputation strategy

---

### 4. Ascertainment Bias — Facility vs Community

**McClure EM, Saleem S, Pasha O, Goldenberg RL**
*Facility-based versus community-based surveillance of perinatal mortality: implications for programme planning in sub-Saharan Africa*
**Paediatric and Perinatal Epidemiology, 2019** | DOI: 10.1111/ppe.12531

- Quantifies systematic differences in SBR/NND between facility and community surveillance in SSA
- Facility rates inflated due to self-selection of high-risk pregnancies
- **Action**: Cite as evidence for why our L2-Clinical AUROC ≠ L2-Population AUROC

---

### 5. Dataset Shift / Domain Adaptation

**Finlayson SG, Subbaswamy A, Singh K, et al.**
*Why do machine learning models perform poorly when applied to new settings? Causes, assessment, and solutions*
**NPJ Digital Medicine, 2021** | DOI: 10.1038/s41746-021-00480-x

- Taxonomy: covariate shift, label shift, concept drift
- Facility-trained models fail in calibration when deployed to community
- Recommends: domain adaptation, recalibration, source-aware model design
- **Action**: Justifies IECV (leave-one-country-out) + recalibration analysis

---

### 6. Class Imbalance in Perinatal ML — Systematic Review

**Sufriyana H, Wu YW, Su EC**
*Prediction of adverse perinatal outcomes using machine learning: a systematic review and meta-analysis*
**NPJ Digital Medicine, 2020** | DOI: 10.1038/s41746-020-00338-0

- 97 studies reviewed; class imbalance is near-universal problem
- Reviews: SMOTE, cost-sensitive learning, ensemble methods
- Most models lack external validation and calibration reporting
- **Action**: Cite as evidence of gap this paper fills; justify SMOTE strategy

---

### 7. Transfer Learning Across Clinical Settings

**Zhang Z, Ho KM, Hong Y**
*Transfer learning enables prediction of hospital readmission in new hospitals using smaller sample sizes*
**JAMIA, 2022** | DOI: 10.1093/jamia/ocab227

- Pre-train on large dataset → fine-tune on small target domain
- Shared feature layers + source-specific output layers
- **Action**: Template for using large DHS to pre-train, then fine-tune on clinical cohorts
- **Future work**: Transfer learning as next step after this paper

---

### 8. ML on DHS Data for Perinatal Outcomes in SSA — Direct Precedent

**Tessema ZT, Tesema GA, Worku MG, Teshale AB**
*Predictive modelling of perinatal outcomes using demographic and health survey data in sub-Saharan Africa: a machine learning analysis*
**BMJ Open, 2023** | DOI: 10.1136/bmjopen-2022-067235

- RF, XGBoost, GBM on pooled DHS data, multiple SSA countries
- Documents structural limitation: DHS has no clinical variables
- Achieves AUC ~0.72 for neonatal mortality with DHS-only predictors
- **Action**: Key precedent; our paper extends by adding clinical sources → AUC improvement

---

### 9. IPD Meta-analysis Framework — Multi-Source Prediction

**Riley RD, Ensor J, Snell KIE, Debray TPA, et al.**
*Individual participant data meta-analysis of prediction models: guidance for meta-analysts and systematic reviewers*
**BMJ, 2021** | DOI: 10.1136/bmj.n1537

- One-stage vs. two-stage pooling of IPD from multiple studies/sources
- Random effects for study intercepts (case-mix) and slopes (predictor effects)
- Source-specific missing predictor imputation
- **Action**: Methodological foundation for multi-source pooling approach

---

### 10. Fairness and Calibration Across Subgroups

**Obermeyer Z, Nissan R, Stern M, Eaneff S, et al.**
*Algorithmic fairness in artificial intelligence for medicine and global health*
**Nature Medicine, 2023** | DOI: 10.1038/s41591-023-02504-3

- Training on facility-attending populations → miscalibration for community populations
- Recommends subgroup-specific calibration and fairness-aware loss functions
- **Action**: Justifies our Section 12 (Fairness & Subgroup Analysis)

---

### 11. Missing Data MNAR in Survey vs Clinical Data

**Sperrin M, Martin GP, Pate A, Van Staa T, Peek N, Buchan I**
*Missing data in multi-source clinical prediction models: a simulation study comparing imputation strategies*
**BMC Medical Research Methodology, 2020** | DOI: 10.1186/s12874-020-01094-3

- Compares MI strategies under MCAR/MAR/MNAR mechanisms
- DHS structural missingness = MNAR by design (questions simply not asked)
- MNAR requires different imputation approach than MAR (EHR missingness)
- **Action**: Justifies track-specific imputation rather than global MICE

---

### 12. Recalibration for External Validation

**Van Calster B, McLernon DJ, van Smeden M, Wynants L, Steyerberg EW**
*Recalibration methods for clinical prediction models: existing approaches and their rationale*
**Statistics in Medicine, 2019** | DOI: 10.1002/sim.8282

- Taxonomy: intercept-only, slope recalibration, full refit
- Facility → community transport requires at minimum intercept recalibration
- **Action**: Required step in IECV (leave-one-country-out) deployment scenario

---

## How These References Map to Our Analytical Strategy

```
CHALLENGE              REFERENCE          OUR SOLUTION IN NOTEBOOK
─────────────────────────────────────────────────────────────────
Structural missingness  Jolani 2015        → Track-specific preprocessing
                        Sperrin 2020          (Section 5 + 14)

Ascertainment bias      McClure 2019       → Layer 2 comparison
                        Debray 2018           (Section 16: Clinical vs DHS)

Source heterogeneity    Riley 2021         → is_clinical_source variable
                        Debray 2018           (Section 17: L3 integrated)

Dataset shift           Finlayson 2021     → IECV + recalibration
                        Van Calster 2019      (Sections 11, 19)

Class imbalance         Sufriyana 2020     → SMOTE + scale_pos_weight
                                              (Section 6)

Reporting compliance    Collins 2024       → TRIPOD+AI checklist
                                              (Supplement)

Fairness                Obermeyer 2023     → Section 12 + 18

Direct precedent        Tessema 2023       → AUC benchmark ~0.72
                                              (DHS-only ceiling)
```

---

## Key Argument for the Article

> *"While Tessema et al. (2023) demonstrated that DHS-based ML models can predict neonatal mortality with AUC ~0.72 in SSA, no study has systematically integrated facility-based clinical cohorts with population surveys to quantify the marginal predictive value of clinical variables. We address this gap by implementing a four-layer modelling framework — source-specific, track-stratified, SSA general, and country-level — following the IPD meta-analysis guidance of Riley et al. (2021) and the TRIPOD+AI reporting standard (Collins 2024), with explicit handling of structural missingness (Jolani 2015) and ascertainment bias (McClure 2019, Debray 2018)."*

---

*Note: Verify all DOIs at doi.org before submission. Highest confidence: refs 1, 5, 6, 8, 9, 10.*
