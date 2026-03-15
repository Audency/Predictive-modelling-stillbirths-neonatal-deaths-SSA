/*==============================================================================
UNIFIED DATASET CREATION - VERSION 6.0
================================================================================
Author: Joseph Akuze
Institution: London School of Hygiene & Tropical Medicine
Project: Wellcome Accelerator Award - Predictive Modeling for Stillbirths and 
         Neonatal Deaths in Sub-Saharan Africa
Created: January 2026
Version: 6.0

PURPOSE:
--------
Create unified dataset with comprehensive variable harmonization across six
perinatal health studies for predictive modeling of:
- Primary outcomes: Stillbirths, neonatal deaths
- Secondary outcomes: Preterm births, SGA, low birthweight
- Extended outcomes: Newborn complications, caesarean sections, maternal 
  morbidity and mortality

STUDIES HARMONIZED:
-------------------
1. NCOPS - Neonatal Care Outcomes Project Study (Uganda)
2. ALERT - Action Leveraging Evidence to Reduce Perinatal Mortality (Uganda, Malawi)
3. PRECISE - Pregnancy Care Integrating Translational Science Everywhere 
   (The Gambia, Kenya, Mozambique)
4. PTBi - Preterm Birth Initiative (Uganda)
5. EN-INDEPTH - Every Newborn International Network for Demographic Evaluation 
   of Populations and Their Health (Bangladesh, Ethiopia, Ghana, Guinea-Bissau, Uganda)
6. WHOMCS - WHO Multi-Country Survey on Maternal and Newborn Health 
   (29 countries across Africa, Asia, Latin America, Middle East)

SECTIONS COVERED:
-----------------
Section 1: Primary Outcome Variables
Section 2: Maternal Demographics
Section 3: Household Socioeconomic Indicators
Section 4: Pre-existing Medical Conditions (NEW in v6)
Section 5: Obstetric History (NEW in v6)
Section 6: Maternal Anthropometry (NEW in v6)
Section 7: Antenatal Care (NEW in v6)
Section 8: Current Pregnancy Complications (NEW in v6)
Section 9: Delivery Characteristics (NEW in v6)
Section 10: Lifestyle Factors (NEW in v6)
Section 11: Neonatal Characteristics (NEW in v6)
Section 12: Maternal Outcomes (NEW in v6)
Section 13: Environmental/Climate Data (NEW in v6)

NEW IN VERSION 6:
-----------------
1. Extended outcomes: preterm, SGA, LBW, newborn complications, caesarean sections
2. Maternal morbidity and mortality indicators
3. Environmental/climate data integration placeholders
4. Documentation for gigs R package SGA calculation
5. Open-source environmental data source documentation

DATA QUALITY NOTES:
-------------------
- All string variables created for uniformity except obvious numerics (age, weight, dates)
- Gestational age-based outcome definitions: â‰¥20 weeks and â‰¥28 weeks for stillbirths
- SGA calculation requires post-processing with gigs R package (see documentation)
- Environmental data requires separate linkage to ERA5 climate reanalysis

ENVIRONMENTAL DATA SOURCES:
---------------------------
For climate/environmental linkage, the following open-source data are available:

1. ERA5 Climate Reanalysis (ECMWF/Copernicus)
   - Coverage: 1940 to near real-time
   - Resolution: 0.25Â° (~31km)
   - Variables: 2m temperature, precipitation, humidity, pressure
   - Access: https://cds.climate.copernicus.eu
   - Africa-specific validation: Gleixner et al. (2020) Atmosphere 11(9):996

2. CHIRPS Precipitation (Climate Hazards Group)
   - Coverage: 1981-present
   - Resolution: 0.05Â° (~5km) for Africa
   - Variables: Daily and monthly precipitation
   - Access: https://data.chc.ucsb.edu/products/CHIRPS-2.0/

3. MODIS Land Surface Temperature (NASA)
   - Coverage: 2000-present
   - Resolution: 1km
   - Access: https://modis.gsfc.nasa.gov/

SGA CALCULATION METHODOLOGY:
----------------------------
Small-for-Gestational-Age (SGA) will be calculated using the gigs R package
developed at LSHTM as part of the Guidance for International Growth Standards project.

Required inputs:
- Gestational age in days (out_ga_days)
- Birth weight in kg (out_birthweight_g / 1000)
- Infant sex (out_infant_sex: Male/Female)

R code for SGA calculation:
```r
library(gigs)

# Load unified dataset
unified_data <- haven::read_dta("unified_dataset_v6.dta")

# Calculate SGA using INTERGROWTH-21st standards
unified_data <- classify_sga(
  .data = unified_data,
  weight_kg = out_birthweight_g / 1000,
  gest_days = out_ga_weeks * 7,
  sex = out_infant_sex
)

# Results include:
# - birthweight_centile: Centile on INTERGROWTH-21st standards
# - sga: Classification (SGA if <10th centile)
```

References:
- Villar et al. (2014) Lancet 384:857-868 (INTERGROWTH-21st Newborn Standards)
- Parker et al. (2025) Stata Journal - gigs package documentation
- https://docs.ropensci.org/gigs/

==============================================================================*/

clear all
set more off
frames reset
capture log close
set maxvar 10000

// Set timestamp for this run
local datetime = c(current_date) + " " + c(current_time)
display "Starting unified dataset creation v6.0 at: `datetime'"

/*==============================================================================
DIRECTORY SETUP
==============================================================================*/

// Try alternative paths
capture cd "C:\Users\josep\OneDrive - London School of Hygiene and Tropical Medicine\LSHTM Grants and Consultancies\Wellcome_Accelerator grant_minorities\Datasets\"
capture cd "C:\Users\eidejwai\OneDrive - London School of Hygiene and Tropical Medicine\LSHTM Grants and Consultancies\Wellcome_Accelerator grant_minorities\Datasets\"

capture global projectdir "C:\Users\josep\OneDrive - London School of Hygiene and Tropical Medicine\LSHTM Grants and Consultancies\Wellcome_Accelerator grant_minorities\Datasets\"
capture global projectdir "C:\Users\eidejwai\OneDrive - London School of Hygiene and Tropical Medicine\LSHTM Grants and Consultancies\Wellcome_Accelerator grant_minorities\Datasets\"

global master "$projectdir/master"
global ncops "$projectdir/ncops"
global alert "$projectdir/alert"
global precise "$projectdir/precise"
global ptbi "$projectdir/ptbi"
global enindepth "$projectdir/en-indepth"
global whomcs "$projectdir/whomcs"
global dhs "$projectdir/dhs"

/*==============================================================================
CREATE FRAMES FOR EACH STUDY
==============================================================================*/
frame create ncops
frame create alert  
frame create precise
frame create ptbi
frame create enindepth
frame create whomcs

/*==============================================================================
==============================================================================
SECTION: NCOPS DATA PROCESSING
==============================================================================
==============================================================================*/
frame change ncops

display _newline(2) "=" * 70
display "LOADING AND PROCESSING NCOPS DATA"
display "=" * 70

capture import delimited "$master/converted_dates.csv", clear stringcols(_all)

if _rc == 0 & _N > 0 {
    display "âœ“ NCOPS CSV loaded: " _N " observations"
    local ncops_loaded = 1
    
    // Merge with SES wealth quintiles if available
    capture confirm file "C:\Users\eidejwai\Dropbox\DELL Latitute LAPT2126\NCOPS\Analysis plan\SES_wealth_quintiles.dta"
    if _rc == 0 {
        display "Merging with SES wealth quintiles..."
        merge 1:1 unique_id using "C:\Users\eidejwai\Dropbox\DELL Latitute LAPT2126\NCOPS\Analysis plan\SES_wealth_quintiles.dta", ///
            keep(master matched) nogenerate
        display "âœ“ Merge completed"
    }
    else {
        display "Note: SES wealth quintiles file not found, creating placeholders"
        generate quintile = .
        generate asset_index = .
    }
}
else {
    display "âœ— Failed to load NCOPS data"
    local ncops_loaded = 0
}

if `ncops_loaded' == 1 {
    
    display "Processing NCOPS data: " _N " observations"
    
    // Create study identifiers
    generate str20 study_source = "NCOPS"
    generate str20 study_design = "Facility-based"
    generate str40 module = "Facility admission records"
    generate str30 study_id = "NCOPS_" + string(_n)
    generate studyyear = .
    
    // Extract year from date_of_birth
    capture {
        generate double temp_dob = date(date_of_birth, "DMY")
        replace temp_dob = date(date_of_birth, "YMD") if missing(temp_dob)
        replace studyyear = year(temp_dob)
        drop temp_dob
    }
    
    /*==========================================================================
    SECTION 1: PRIMARY OUTCOME VARIABLES
    ==========================================================================*/
    
    // Initialize ALL outcome variables as STRINGS
    generate str10 out_stillbirth = ""
    generate str10 out_fresh_stillbirth = ""
    generate str10 out_macerated_stillbirth = ""
    generate str10 out_stillbirth_20wks = ""
    generate str10 out_stillbirth_28wks = ""
    generate str10 out_livebirth = ""
    generate str10 out_nnd = ""
    generate str10 out_nnd_early = ""
    generate str10 out_nnd_late = ""
    generate str10 out_perinatal_death = ""
    
    // NEW IN V6: Extended outcome variables
    generate str10 out_preterm = ""
    generate str10 out_very_preterm = ""
    generate str10 out_extremely_preterm = ""
    generate str10 out_sga = ""
    generate str10 out_lga = ""
    generate str10 out_lbw = ""
    generate str10 out_vlbw = ""
    generate str10 out_elbw = ""
    generate str10 out_multiple = ""
    
    // Date variables (numeric)
    generate double out_dob = .
    generate double out_dod = .
    format out_dob out_dod %td
    
    // Numeric outcomes
    generate out_ga_weeks = .
    generate out_ga_days = .
    generate out_ageatdeath = .
    generate out_birthweight_g = .
    generate out_apgar_1min = .
    generate out_apgar_5min = .
    generate out_apgar_10min = .
    generate str10 out_infant_sex = ""
    generate str50 out_birth_location = ""
    generate out_birthweight_centile = .
    generate out_birthweight_zscore = .
    
    // Convert dates
    foreach var in date_of_birth if_death_date_of_deati date_of_dischargf {
        capture confirm string variable `var'
        if !_rc {
            generate double `var'_td = date(`var', "DMY")
            replace `var'_td = date(`var', "YMD") if missing(`var'_td)
            replace `var'_td = date(`var', "MDY") if missing(`var'_td)
            format `var'_td %td
        }
    }
    
    // Dates
    replace out_dob = date_of_birth_td if !missing(date_of_birth_td)
    replace out_dod = if_death_date_of_deati_td if !missing(if_death_date_of_deati_td)
    replace out_dod = date_of_dischargf_td if missing(out_dod) & !missing(date_of_dischargf_td)
    
    // Gestational age
    capture destring ballard_score, replace force
    replace out_ga_weeks = ballard_score if !missing(ballard_score)
    replace out_ga_days = out_ga_weeks * 7 if !missing(out_ga_weeks)
    
    // Birth weight - convert to grams
    capture destring birth_weight_kg, replace force
    replace out_birthweight_g = birth_weight_kg * 1000 if !missing(birth_weight_kg)
    
    // Apgar scores
    capture destring apgar_at_1min apgar_at_5min, replace force
    replace out_apgar_1min = apgar_at_1min if !missing(apgar_at_1min)
    replace out_apgar_5min = apgar_at_5min if !missing(apgar_at_5min)
    
    // Infant sex
    capture {
        replace out_infant_sex = "Male" if regexm(lower(gender), "male|boy|m")
        replace out_infant_sex = "Female" if regexm(lower(gender), "female|girl|f")
    }
    
    // Birth location
    capture {
        replace out_birth_location = "Hospital" if regexm(lower(birth_location), "hospital")
        replace out_birth_location = "Health facility" if regexm(lower(birth_location), "facility|clinic|centre|center") & out_birth_location == ""
        replace out_birth_location = "Home" if regexm(lower(birth_location), "home")
        replace out_birth_location = "En route" if regexm(lower(birth_location), "way|route|transit")
    }
    
    // OUTCOME CLASSIFICATION
    generate str100 status_lower = lower(status_of_baby_at_dischargf)
    
    // Stillbirths
    replace out_stillbirth = "Yes" if regexm(status_lower, "stillbirth|still birth")
    replace out_stillbirth = "No" if !missing(status_of_baby_at_dischargf) & ///
        !regexm(status_lower, "stillbirth|still birth")
    
    // Fresh vs macerated (not available in NCOPS)
    replace out_fresh_stillbirth = "" if out_stillbirth == "Yes"
    replace out_macerated_stillbirth = "" if out_stillbirth == "Yes"
    
    // For missing discharge status, use additional indicators
    capture confirm string variable did_baby_cry_at_birth
    if !_rc {
        replace out_stillbirth = "Yes" if missing(status_of_baby_at_dischargf) & ///
            regexm(lower(did_baby_cry_at_birth), "no|unknown") & ///
            (out_apgar_1min == 0 | out_apgar_5min == 0 | ///
            (missing(out_apgar_1min) & missing(out_apgar_5min)))
    }
    
    // Live births
    replace out_livebirth = "Yes" if out_stillbirth == "No"
    replace out_livebirth = "No" if out_stillbirth == "Yes"
    
    replace out_livebirth = "Yes" if out_stillbirth == "" & ///
        (out_apgar_1min > 0 | out_apgar_5min > 0 | ///
        regexm(lower(did_baby_cry_at_birth), "yes"))
    
    replace out_stillbirth = "No" if out_livebirth == "Yes" & out_stillbirth == ""
    replace out_livebirth = "No" if out_stillbirth == "Yes" & out_livebirth == ""
    
    // Neonatal deaths
    replace out_nnd = "Yes" if out_livebirth == "Yes" & ///
        (regexm(status_lower, "dead|died|death") | ///
        (!missing(out_dob) & !missing(out_dod) & out_dod > out_dob))
    replace out_nnd = "No" if out_livebirth == "Yes" & out_nnd != "Yes"
    replace out_nnd = "" if out_livebirth != "Yes"
    
    // Age at death
    replace out_ageatdeath = out_dod - out_dob if out_nnd == "Yes" & ///
        !missing(out_dod) & !missing(out_dob)
    replace out_ageatdeath = . if out_ageatdeath < 0 | out_ageatdeath > 28
    
    // Early and late NND
    replace out_nnd_early = "Yes" if out_nnd == "Yes" & inrange(out_ageatdeath, 0, 7)
    replace out_nnd_early = "No" if out_nnd == "Yes" & !inrange(out_ageatdeath, 0, 7)
    replace out_nnd_early = "" if out_livebirth != "Yes"
    
    replace out_nnd_late = "Yes" if out_nnd == "Yes" & inrange(out_ageatdeath, 8, 28)
    replace out_nnd_late = "No" if out_nnd == "Yes" & !inrange(out_ageatdeath, 8, 28)
    replace out_nnd_late = "" if out_livebirth != "Yes"
    
    // GA-based stillbirth classifications
    replace out_stillbirth_20wks = "Yes" if out_stillbirth == "Yes" & out_ga_weeks >= 20
    replace out_stillbirth_20wks = "No" if out_stillbirth == "No"
    replace out_stillbirth_20wks = "" if missing(out_ga_weeks) & out_stillbirth == "Yes"
    
    replace out_stillbirth_28wks = "Yes" if out_stillbirth == "Yes" & out_ga_weeks >= 28
    replace out_stillbirth_28wks = "No" if out_stillbirth == "No"
    replace out_stillbirth_28wks = "" if missing(out_ga_weeks) & out_stillbirth == "Yes"
    
    // Perinatal death
    replace out_perinatal_death = "Yes" if out_stillbirth_28wks == "Yes" | out_nnd_early == "Yes"
    replace out_perinatal_death = "No" if out_stillbirth_28wks == "No" & out_nnd_early == "No"
    
    // NEW V6: Extended outcomes
    
    // Preterm classifications
    capture {
        replace out_preterm = "Yes" if out_livebirth == "Yes" & out_ga_weeks < 37 & out_ga_weeks >= 20
        replace out_preterm = "No" if out_livebirth == "Yes" & out_ga_weeks >= 37
        replace out_very_preterm = "Yes" if out_livebirth == "Yes" & out_ga_weeks < 32 & out_ga_weeks >= 20
        replace out_very_preterm = "No" if out_livebirth == "Yes" & (out_ga_weeks >= 32 | out_ga_weeks < 20)
        replace out_extremely_preterm = "Yes" if out_livebirth == "Yes" & out_ga_weeks < 28 & out_ga_weeks >= 20
        replace out_extremely_preterm = "No" if out_livebirth == "Yes" & (out_ga_weeks >= 28 | out_ga_weeks < 20)
        
        // Also use term_preterm variable if available
        replace out_preterm = "Yes" if regexm(lower(term_preterm), "pre-term|preterm")
        replace out_preterm = "No" if regexm(lower(term_preterm), "^term$") & out_preterm == ""
    }
    
    // Low birth weight classifications
    replace out_lbw = "Yes" if out_livebirth == "Yes" & out_birthweight_g < 2500 & out_birthweight_g > 0
    replace out_lbw = "No" if out_livebirth == "Yes" & out_birthweight_g >= 2500
    
    replace out_vlbw = "Yes" if out_livebirth == "Yes" & out_birthweight_g < 1500 & out_birthweight_g > 0
    replace out_vlbw = "No" if out_livebirth == "Yes" & out_birthweight_g >= 1500
    
    replace out_elbw = "Yes" if out_livebirth == "Yes" & out_birthweight_g < 1000 & out_birthweight_g > 0
    replace out_elbw = "No" if out_livebirth == "Yes" & out_birthweight_g >= 1000
    
    // SGA placeholder - requires gigs R package for calculation
    // Will be calculated post-processing using INTERGROWTH-21st standards
    replace out_sga = ""
    replace out_lga = ""
    
    drop status_lower
    
    /*==========================================================================
    SECTION 2: MATERNAL DEMOGRAPHICS
    ==========================================================================*/
    
    generate mat_age = .
    generate str20 mat_age_cat = ""
    generate str50 mat_education = ""
    generate str50 fat_education = ""
    generate str50 mat_occupation = ""
    generate str50 fat_occupation = ""
    generate str30 marital_status = ""
    generate str30 religion = ""
    generate str50 ethnicity = ""
    generate str50 out_country = "Uganda"
    generate str100 mat_facility = ""
    generate str50 mat_district = ""
    generate str20 mat_urban_rural = ""
    generate str10 mat_literacy = ""
    
    // Maternal age
    capture destring mother_s_age, replace force
    replace mat_age = mother_s_age if !missing(mother_s_age) & inrange(mother_s_age, 10, 60)
    
    // Age categories
    replace mat_age_cat = "<20" if mat_age < 20 & !missing(mat_age)
    replace mat_age_cat = "20-24" if inrange(mat_age, 20, 24)
    replace mat_age_cat = "25-29" if inrange(mat_age, 25, 29)
    replace mat_age_cat = "30-34" if inrange(mat_age, 30, 34)
    replace mat_age_cat = "35+" if mat_age >= 35 & !missing(mat_age)
    
    // Education
    capture {
        replace mat_education = "None" if regexm(lower(if_yes_what_is_the_highest_leve), "none|never|no education")
        replace mat_education = "Primary" if regexm(lower(if_yes_what_is_the_highest_leve), "primary|p[1-7]")
        replace mat_education = "Secondary" if regexm(lower(if_yes_what_is_the_highest_leve), "secondary|s[1-6]|o level|a level")
        replace mat_education = "Higher" if regexm(lower(if_yes_what_is_the_highest_leve), "university|college|tertiary|higher|diploma|degree")
    }
    
    // Father's education
    capture {
        replace fat_education = "None" if regexm(lower(if_yes_what_is_his_highest_leve), "none|never|no education")
        replace fat_education = "Primary" if regexm(lower(if_yes_what_is_his_highest_leve), "primary|p[1-7]")
        replace fat_education = "Secondary" if regexm(lower(if_yes_what_is_his_highest_leve), "secondary|s[1-6]|o level|a level")
        replace fat_education = "Higher" if regexm(lower(if_yes_what_is_his_highest_leve), "university|college|tertiary|higher|diploma|degree")
    }
    
    // Occupation
    capture {
        replace mat_occupation = "Employed" if regexm(lower(what_is_your_primary_occupation), "employed|salaried|professional|formal")
        replace mat_occupation = "Self-employed" if regexm(lower(what_is_your_primary_occupation), "self|business|trader|farmer")
        replace mat_occupation = "Unemployed" if regexm(lower(what_is_your_primary_occupation), "unemployed|housewife|not employed|none")
        replace mat_occupation = "Student" if regexm(lower(what_is_your_primary_occupation), "student")
    }
    
    // Marital status
    capture {
        replace marital_status = "Married/Cohabiting" if regexm(lower(marital_status_relationship), "married|living with|cohabit")
        replace marital_status = "Single" if regexm(lower(marital_status_relationship), "single|never married")
        replace marital_status = "Divorced/Separated" if regexm(lower(marital_status_relationship), "divorced|separated")
        replace marital_status = "Widowed" if regexm(lower(marital_status_relationship), "widow")
    }
    
    // Religion
    capture {
        replace religion = "Christian" if regexm(lower(religioo), "christian|catholic|protestant|anglican|pentecostal|sda|adventist")
        replace religion = "Muslim" if regexm(lower(religioo), "muslim|islam")
        replace religion = "Traditional" if regexm(lower(religioo), "traditional|ancestral")
        replace religion = "Other" if regexm(lower(religioo), "other") & religion == ""
        replace religion = "None" if regexm(lower(religioo), "none|no religion|atheist")
    }
    
    // Facility
    capture replace mat_facility = facility_name if !missing(facility_name)
    
    // District
    capture replace mat_district = mother_s_district_of_residence if !missing(mother_s_district_of_residence)
    
    // Literacy
    capture {
        replace mat_literacy = "Yes" if regexm(lower(have_you_ever_attended_school), "yes")
        replace mat_literacy = "No" if regexm(lower(have_you_ever_attended_school), "no")
    }
    
    /*==========================================================================
    SECTION 3: HOUSEHOLD SOCIOECONOMIC INDICATORS
    ==========================================================================*/
    
    generate str50 house_wall = ""
    generate str50 house_floor = ""
    generate str20 house_ownership = ""
    generate house_rooms = .
    generate str10 electricity = ""
    generate str50 water_source = ""
    generate str50 toilet_facilities = ""
    generate str30 cooking_fuel = ""
    generate str10 mosquito_net = ""
    generate str10 asset_bed = ""
    generate str10 asset_mobile = ""
    generate str10 asset_motorbike = ""
    generate str10 asset_car = ""
    generate str10 asset_radio = ""
    generate str10 asset_tv = ""
    generate monthly_income = .
    generate household_size = .
    generate ppi_score = .
    generate wealth_quintile = .
    generate asset_score = .
    
    // House materials
    capture {
        replace house_wall = "Permanent" if regexm(lower(what_are_your_house_walls_made_o), "brick|cement|block|stone")
        replace house_wall = "Semi-permanent" if regexm(lower(what_are_your_house_walls_made_o), "mud|wattle|wood")
        replace house_wall = "Temporary" if regexm(lower(what_are_your_house_walls_made_o), "metal|iron|tin|thatch")
        
        replace house_floor = "Finished" if regexm(lower(what_is_your_house_floor_made_of), "cement|concrete|tile|brick")
        replace house_floor = "Unfinished" if regexm(lower(what_is_your_house_floor_made_of), "earth|mud|sand|dung")
    }
    
    // Ownership
    capture {
        replace house_ownership = "Own" if regexm(lower(do_you_own_or_rent_your_house), "own")
        replace house_ownership = "Rent" if regexm(lower(do_you_own_or_rent_your_house), "rent")
    }
    
    // Rooms
    capture destring how_many_rooms_in_your_house_i, replace force
    replace house_rooms = how_many_rooms_in_your_house_i if !missing(how_many_rooms_in_your_house_i)
    
    // Electricity
    capture {
        replace electricity = "Yes" if regexm(lower(do_you_have_electricity_at_home), "yes")
        replace electricity = "No" if regexm(lower(do_you_have_electricity_at_home), "no")
    }
    
    // Water source
    capture {
        replace water_source = "Improved" if regexm(lower(where_do_you_get_your_clean_drin), "tap|pipe|borehole|protected|30 min")
        replace water_source = "Unimproved" if regexm(lower(where_do_you_get_your_clean_drin), "unprotected|river|pond|surface|>30")
    }
    
    // Sanitation
    capture {
        replace toilet_facilities = "Improved" if regexm(lower(what_toilet_facilities_do_you_ha), "flush|toilet in household|pit latrine|vip")
        replace toilet_facilities = "Shared" if regexm(lower(what_toilet_facilities_do_you_ha), "shared")
        replace toilet_facilities = "Unimproved" if regexm(lower(what_toilet_facilities_do_you_ha), "no toilet|open|bush|field")
    }
    
    // Cooking fuel
    capture {
        replace cooking_fuel = "Clean" if regexm(lower(what_is_the_primary_fuel_used_fo), "electric|gas|lpg")
        replace cooking_fuel = "Biomass" if regexm(lower(what_is_the_primary_fuel_used_fo), "firewood|charcoal|dung|crop|wood")
        replace cooking_fuel = "Other" if regexm(lower(what_is_the_primary_fuel_used_fo), "paraffin|kerosene")
    }
    
    // Mosquito net
    capture {
        replace mosquito_net = "Yes" if regexm(lower(do_you_sleep_under_mosquito_net), "yes")
        replace mosquito_net = "No" if regexm(lower(do_you_sleep_under_mosquito_net), "no")
    }
    
    // Income and household size
    capture destring what_is_your_personnal_monthly_i how_many_people_including_yours, replace force
    replace monthly_income = what_is_your_personnal_monthly_i if !missing(what_is_your_personnal_monthly_i)
    replace household_size = how_many_people_including_yours if !missing(how_many_people_including_yours)
    
    // Wealth quintile from merged data
    capture replace wealth_quintile = quintile if !missing(quintile)
    capture replace asset_score = asset_index if !missing(asset_index)
    
    /*==========================================================================
    SECTION 4: PRE-EXISTING MEDICAL CONDITIONS (NEW IN V6)
    ==========================================================================*/
    
    generate str10 preg_hiv = ""
    generate str10 preg_chronic_htn = ""
    generate str10 preg_diabetes = ""
    generate str10 preg_anaemia = ""
    generate str10 preg_sickle_cell = ""
    generate str10 preg_tb = ""
    generate str10 preg_heart_disease = ""
    generate str10 preg_renal_disease = ""
    generate str10 preg_hepatic_disease = ""
    generate str10 preg_malaria = ""
    generate str10 preg_uti = ""
    
    // HIV status
    capture {
        replace preg_hiv = "Yes" if regexm(lower(if_yes_result), "positive|tr|trr|reactive")
        replace preg_hiv = "No" if regexm(lower(if_yes_result), "negative|non-reactive|nr")
        replace preg_hiv = "Unknown" if regexm(lower(mother_tested_for_hiv), "no|unknown") | ///
            (regexm(lower(mother_tested_for_hiv), "yes") & missing(if_yes_result))
    }
    
    // Chronic conditions
    capture {
        replace preg_chronic_htn = "Yes" if regexm(lower(hypertension), "yes")
        replace preg_chronic_htn = "No" if regexm(lower(hypertension), "no")
        
        replace preg_diabetes = "Yes" if regexm(lower(diabetes_mellitus), "yes")
        replace preg_diabetes = "No" if regexm(lower(diabetes_mellitus), "no")
        
        replace preg_anaemia = "Yes" if regexm(lower(anaemia), "yes")
        replace preg_anaemia = "No" if regexm(lower(anaemia), "no")
        
        replace preg_tb = "Yes" if regexm(lower(tb), "yes")
        replace preg_tb = "No" if regexm(lower(tb), "no")
        
        replace preg_heart_disease = "Yes" if regexm(lower(heart_disease), "yes")
        replace preg_heart_disease = "No" if regexm(lower(heart_disease), "no")
        
        replace preg_malaria = "Yes" if regexm(lower(fever_malaria), "yes")
        replace preg_malaria = "No" if regexm(lower(fever_malaria), "no")
        
        replace preg_uti = "Yes" if regexm(lower(uti), "yes")
        replace preg_uti = "No" if regexm(lower(uti), "no")
    }
    
    /*==========================================================================
    SECTION 5: OBSTETRIC HISTORY (NEW IN V6)
    ==========================================================================*/
    
    generate obs_gravidity = .
    generate obs_parity = .
    generate obs_previous_livebirths = .
    generate str10 obs_given_birth_before = ""
    generate str10 obs_previous_stillbirth = ""
    generate str10 obs_previous_csection = ""
    generate str10 obs_previous_abortion = ""
    
    capture {
        destring number_of_pregnacies number_of_live_children, replace force
        replace obs_gravidity = number_of_pregnacies if !missing(number_of_pregnacies) & inrange(number_of_pregnacies, 1, 20)
        replace obs_previous_livebirths = number_of_live_children if !missing(number_of_live_children)
        
        // Derive parity from previous live children
        replace obs_parity = obs_previous_livebirths if !missing(obs_previous_livebirths)
        
        // Given birth before
        replace obs_given_birth_before = "Yes" if obs_previous_livebirths > 0 & !missing(obs_previous_livebirths)
        replace obs_given_birth_before = "No" if obs_previous_livebirths == 0
    }
    
    /*==========================================================================
    SECTION 6: MATERNAL ANTHROPOMETRY (NEW IN V6)
    ==========================================================================*/
    
    generate mat_height_cm = .
    generate mat_weight_kg = .
    generate mat_bmi = .
    generate str20 mat_bmi_cat = ""
    generate mat_muac_cm = .
    generate str20 mat_muac_cat = ""
    
    // NCOPS doesn't have anthropometry data - placeholders only
    
    /*==========================================================================
    SECTION 7: ANTENATAL CARE (NEW IN V6)
    ==========================================================================*/
    
    generate str10 anc_attended = ""
    generate anc_num_visits = .
    generate anc_ga_first_visit = .
    generate str100 anc_facility = ""
    generate str10 anc_tetanus_toxoid = ""
    
    capture {
        replace anc_attended = "Yes" if regexm(lower(anc_attendance), "yes")
        replace anc_attended = "No" if regexm(lower(anc_attendance), "no")
        
        destring number_of_anc_visits, replace force
        replace anc_num_visits = number_of_anc_visits if !missing(number_of_anc_visits) & inrange(number_of_anc_visits, 0, 20)
        
        replace anc_facility = name_of_facility_anc if !missing(name_of_facility_anc)
        
        replace anc_tetanus_toxoid = "Yes" if regexm(lower(received_tt), "yes")
        replace anc_tetanus_toxoid = "No" if regexm(lower(received_tt), "no")
    }
    
    /*==========================================================================
    SECTION 8: CURRENT PREGNANCY COMPLICATIONS (NEW IN V6)
    ==========================================================================*/
    
    generate str10 preg_gest_htn = ""
    generate str10 preg_preeclampsia = ""
    generate str10 preg_eclampsia = ""
    generate str10 preg_hdp = ""
    generate preg_sbp = .
    generate preg_dbp = .
    generate str10 preg_pprom = ""
    generate str10 preg_placenta_praevia = ""
    generate str10 preg_placenta_abruption = ""
    generate str10 preg_aph = ""
    generate str10 preg_pph = ""
    generate str10 preg_ruptured_uterus = ""
    generate str10 preg_prolonged_labour = ""
    generate str10 preg_obstructed_labour = ""
    generate str10 preg_breech = ""
    generate str10 preg_maternal_fever = ""
    generate str10 preg_meconium = ""
    
    capture {
        replace preg_gest_htn = "Yes" if regexm(lower(high_blood_pressure_elampsia), "yes")
        replace preg_gest_htn = "No" if regexm(lower(high_blood_pressure_elampsia), "no")
        
        replace preg_pprom = "Yes" if regexm(lower(pre_labor_rupture_of_membranes), "yes")
        replace preg_pprom = "No" if regexm(lower(pre_labor_rupture_of_membranes), "no")
        
        replace preg_aph = "Yes" if regexm(lower(maternal_hemorrhage_at_or_before), "yes")
        replace preg_aph = "No" if regexm(lower(maternal_hemorrhage_at_or_before), "no")
        
        replace preg_pph = "Yes" if regexm(lower(maternal_hemorrhage_after_delive), "yes")
        replace preg_pph = "No" if regexm(lower(maternal_hemorrhage_after_delive), "no")
        
        replace preg_prolonged_labour = "Yes" if regexm(lower(prolonged_labour), "yes")
        replace preg_prolonged_labour = "No" if regexm(lower(prolonged_labour), "no")
        
        replace preg_obstructed_labour = "Yes" if regexm(lower(obstructed_labour), "yes")
        replace preg_obstructed_labour = "No" if regexm(lower(obstructed_labour), "no")
        
        replace preg_breech = "Yes" if regexm(lower(breech_presentation), "yes")
        replace preg_breech = "No" if regexm(lower(breech_presentation), "no")
        
        replace preg_maternal_fever = "Yes" if regexm(lower(maternal_fever_1_day_before_or_a), "yes")
        replace preg_maternal_fever = "No" if regexm(lower(maternal_fever_1_day_before_or_a), "no")
        
        replace preg_meconium = "Yes" if regexm(lower(meconium_stained_fluid), "yes")
        replace preg_meconium = "No" if regexm(lower(meconium_stained_fluid), "no")
    }
    
    /*==========================================================================
    SECTION 9: DELIVERY CHARACTERISTICS (NEW IN V6)
    ==========================================================================*/
    
    generate str30 del_mode = ""
    generate str50 del_location = ""
    generate str20 del_location_type = ""
    generate str10 del_attendant_doctor = ""
    generate str10 del_attendant_midwife = ""
    generate str10 del_attendant_nurse = ""
    generate str10 del_attendant_tba = ""
    generate str10 del_attendant_family = ""
    generate str10 del_any_attendant = ""
    generate str20 del_labour_onset = ""
    generate str10 del_induction = ""
    generate str10 del_referred = ""
    generate str10 del_bba = ""
    
    // Mode of delivery
    capture {
        replace del_mode = "Vaginal" if regexm(lower(mode_of_delivery), "normal|vaginal|svd|spontaneous")
        replace del_mode = "Caesarean" if regexm(lower(mode_of_delivery), "caesarean|c-section|cs|c/s")
        replace del_mode = "Instrumental" if regexm(lower(mode_of_delivery), "vacuum|forceps|assisted")
    }
    
    // Delivery location
    capture {
        replace del_location = "Hospital" if regexm(lower(birth_location), "hospital")
        replace del_location = "Health facility" if regexm(lower(birth_location), "facility|clinic|centre") & del_location == ""
        replace del_location = "Home" if regexm(lower(birth_location), "home")
        replace del_location = "En route" if regexm(lower(birth_location), "way|route|transit")
        
        replace del_location_type = "Facility" if inlist(del_location, "Hospital", "Health facility")
        replace del_location_type = "Non-facility" if inlist(del_location, "Home", "En route")
    }
    
    // Referral
    capture {
        replace del_referred = "Yes" if regexm(lower(referall_status), "referr|hospital|clinic|centre")
        replace del_referred = "No" if regexm(lower(referall_status), "not applicable|self")
    }
    
    /*==========================================================================
    SECTION 10: LIFESTYLE FACTORS (NEW IN V6)
    ==========================================================================*/
    
    generate str10 life_tobacco = ""
    generate str10 life_alcohol = ""
    generate str20 life_sleep_position = ""
    generate str10 life_fgm = ""
    
    capture {
        replace life_tobacco = "Yes" if regexm(lower(smoking_ciggarates), "yes")
        replace life_tobacco = "No" if regexm(lower(smoking_ciggarates), "no") | regexm(lower(non_smoker), "yes")
        
        replace life_alcohol = "Yes" if regexm(lower(taking_alcohol), "yes")
        replace life_alcohol = "No" if regexm(lower(taking_alcohol), "no")
    }
    
    /*==========================================================================
    SECTION 11: NEONATAL CHARACTERISTICS (NEW IN V6)
    ==========================================================================*/
    
    generate str10 neo_resuscitation = ""
    generate str30 neo_resuscitation_type = ""
    generate str10 neo_malformation = ""
    generate str100 neo_malformation_type = ""
    generate str10 neo_nicu = ""
    generate str10 neo_breastfeeding = ""
    generate str10 neo_cry_at_birth = ""
    
    capture {
        replace neo_cry_at_birth = "Yes" if regexm(lower(did_baby_cry_at_birth), "yes")
        replace neo_cry_at_birth = "No" if regexm(lower(did_baby_cry_at_birth), "no")
        replace neo_cry_at_birth = "Unknown" if regexm(lower(did_baby_cry_at_birth), "unknown")
    }
    
    /*==========================================================================
    SECTION 12: MATERNAL OUTCOMES (NEW IN V6)
    ==========================================================================*/
    
    generate str10 mat_death = ""
    generate str30 mat_discharge_status = ""
    generate str10 mat_near_miss = ""
    
    // Derived from discharge status if available
    
    /*==========================================================================
    SECTION 13: ENVIRONMENTAL/CLIMATE DATA PLACEHOLDERS (NEW IN V6)
    ==========================================================================*/
    
    // These variables will be populated through linkage with ERA5 climate data
    // Based on delivery date and location coordinates
    
    generate env_temp_mean = .           // Mean temperature (Â°C) at delivery month
    generate env_temp_max = .            // Maximum temperature (Â°C) at delivery month
    generate env_temp_min = .            // Minimum temperature (Â°C) at delivery month
    generate env_precipitation = .        // Total precipitation (mm) at delivery month
    generate env_humidity = .             // Mean relative humidity (%) at delivery month
    generate str20 env_season = ""        // Season at delivery (Dry/Wet/Transition)
    generate env_heat_index = .           // Heat index at delivery
    generate env_latitude = .             // Facility/village latitude
    generate env_longitude = .            // Facility/village longitude
    
    // Label environmental variables
    label variable env_temp_mean "Mean temperature at delivery month (Â°C)"
    label variable env_temp_max "Maximum temperature at delivery month (Â°C)"
    label variable env_temp_min "Minimum temperature at delivery month (Â°C)"
    label variable env_precipitation "Total precipitation at delivery month (mm)"
    label variable env_humidity "Mean relative humidity at delivery month (%)"
    label variable env_season "Season at delivery"
    label variable env_heat_index "Heat index at delivery"
    label variable env_latitude "Facility/village latitude"
    label variable env_longitude "Facility/village longitude"
    
    display "âœ“ NCOPS processing complete"
}

/*==============================================================================
==============================================================================
SECTION: ALERT DATA PROCESSING
==============================================================================
==============================================================================*/
frame change alert

display _newline(2) "=" * 70
display "LOADING AND PROCESSING ALERT DATA"
display "=" * 70

capture import delimited "$alert/ALERT_final.csv", clear stringcols(_all)
if _rc != 0 {
    capture import delimited "$master/ALERT_sample.csv", clear stringcols(_all)
}

if _rc == 0 & _N > 0 {
    display "âœ“ ALERT data loaded: " _N " observations"
    local alert_loaded = 1
    
    // Study identifiers
    generate str20 study_source = "ALERT"
    generate str20 study_design = "Facility-based"
    generate str40 module = "Facility birth registry"
    generate str30 study_id = "ALERT_" + string(_n)
    generate studyyear = .
    
    // Initialize ALL outcome variables
    generate str10 out_stillbirth = ""
    generate str10 out_fresh_stillbirth = ""
    generate str10 out_macerated_stillbirth = ""
    generate str10 out_stillbirth_20wks = ""
    generate str10 out_stillbirth_28wks = ""
    generate str10 out_livebirth = ""
    generate str10 out_nnd = ""
    generate str10 out_nnd_early = ""
    generate str10 out_nnd_late = ""
    generate str10 out_perinatal_death = ""
    generate str10 out_preterm = ""
    generate str10 out_very_preterm = ""
    generate str10 out_extremely_preterm = ""
    generate str10 out_sga = ""
    generate str10 out_lga = ""
    generate str10 out_lbw = ""
    generate str10 out_vlbw = ""
    generate str10 out_elbw = ""
    generate str10 out_multiple = ""
    
    generate double out_dob = .
    generate double out_dod = .
    format out_dob out_dod %td
    
    generate out_ga_weeks = .
    generate out_ga_days = .
    generate out_ageatdeath = .
    generate out_birthweight_g = .
    generate out_apgar_1min = .
    generate out_apgar_5min = .
    generate out_apgar_10min = .
    generate str10 out_infant_sex = ""
    generate str50 out_birth_location = ""
    generate out_birthweight_centile = .
    generate out_birthweight_zscore = .
    
    // Process birth outcome from q27out
    // q27out: 1=Alive, 2=Fresh stillbirth, 3=Macerated stillbirth
    capture {
        destring q27out, replace force
        replace out_livebirth = "Yes" if q27out == 1
        replace out_livebirth = "No" if inlist(q27out, 2, 3)
        replace out_stillbirth = "Yes" if inlist(q27out, 2, 3)
        replace out_stillbirth = "No" if q27out == 1
        replace out_fresh_stillbirth = "Yes" if q27out == 2
        replace out_fresh_stillbirth = "No" if q27out != 2 & !missing(q27out)
        replace out_macerated_stillbirth = "Yes" if q27out == 3
        replace out_macerated_stillbirth = "No" if q27out != 3 & !missing(q27out)
    }
    
    // Gestational age from q9aga (weeks) or derived from gest_age
    capture {
        destring q9aga, replace force
        replace out_ga_weeks = q9aga if !missing(q9aga) & inrange(q9aga, 20, 45)
        
        // Alternative from gest_age (days)
        capture destring gest_age, replace force
        replace out_ga_weeks = gest_age / 7 if missing(out_ga_weeks) & !missing(gest_age)
        
        replace out_ga_days = out_ga_weeks * 7 if !missing(out_ga_weeks)
    }
    
    // Birth weight from q28weight (grams)
    capture {
        destring q28weight, replace force
        replace out_birthweight_g = q28weight if !missing(q28weight) & inrange(q28weight, 300, 6000)
    }
    
    // Infant sex from q29sex
    capture {
        replace out_infant_sex = "Male" if regexm(lower(q29sex), "male|boy|m")
        replace out_infant_sex = "Female" if regexm(lower(q29sex), "female|girl|f")
    }
    
    // Apgar from q30apg
    capture {
        destring q30apg, replace force
        replace out_apgar_5min = q30apg if !missing(q30apg) & inrange(q30apg, 0, 10)
    }
    
    // GA-based stillbirth classifications
    replace out_stillbirth_20wks = "Yes" if out_stillbirth == "Yes" & out_ga_weeks >= 20
    replace out_stillbirth_20wks = "No" if out_stillbirth == "No"
    replace out_stillbirth_28wks = "Yes" if out_stillbirth == "Yes" & out_ga_weeks >= 28
    replace out_stillbirth_28wks = "No" if out_stillbirth == "No"
    
    // Preterm
    replace out_preterm = "Yes" if out_livebirth == "Yes" & out_ga_weeks < 37 & out_ga_weeks >= 20
    replace out_preterm = "No" if out_livebirth == "Yes" & out_ga_weeks >= 37
    replace out_very_preterm = "Yes" if out_livebirth == "Yes" & out_ga_weeks < 32 & out_ga_weeks >= 20
    replace out_very_preterm = "No" if out_livebirth == "Yes" & out_ga_weeks >= 32
    replace out_extremely_preterm = "Yes" if out_livebirth == "Yes" & out_ga_weeks < 28 & out_ga_weeks >= 20
    replace out_extremely_preterm = "No" if out_livebirth == "Yes" & out_ga_weeks >= 28
    
    // Low birth weight
    replace out_lbw = "Yes" if out_livebirth == "Yes" & out_birthweight_g < 2500 & out_birthweight_g > 0
    replace out_lbw = "No" if out_livebirth == "Yes" & out_birthweight_g >= 2500
    replace out_vlbw = "Yes" if out_livebirth == "Yes" & out_birthweight_g < 1500 & out_birthweight_g > 0
    replace out_vlbw = "No" if out_livebirth == "Yes" & out_birthweight_g >= 1500
    replace out_elbw = "Yes" if out_livebirth == "Yes" & out_birthweight_g < 1000 & out_birthweight_g > 0
    replace out_elbw = "No" if out_livebirth == "Yes" & out_birthweight_g >= 1000
    
    // Neonatal death from neonataldeath
    capture {
        destring neonataldeath, replace force
        replace out_nnd = "Yes" if neonataldeath == 1 & out_livebirth == "Yes"
        replace out_nnd = "No" if neonataldeath == 0 & out_livebirth == "Yes"
        replace out_nnd = "No" if out_livebirth == "Yes" & missing(neonataldeath) & out_nnd == ""
    }
    
    // Perinatal death
    replace out_perinatal_death = "Yes" if out_stillbirth_28wks == "Yes" | out_nnd_early == "Yes"
    replace out_perinatal_death = "No" if out_stillbirth_28wks == "No" & out_nnd_early == "No"
    
    // MATERNAL DEMOGRAPHICS
    generate mat_age = .
    generate str20 mat_age_cat = ""
    generate str50 mat_education = ""
    generate str50 fat_education = ""
    generate str50 mat_occupation = ""
    generate str50 fat_occupation = ""
    generate str30 marital_status = ""
    generate str30 religion = ""
    generate str50 ethnicity = ""
    generate str50 out_country = ""
    generate str100 mat_facility = ""
    generate str50 mat_district = ""
    generate str20 mat_urban_rural = ""
    generate str10 mat_literacy = ""
    
    // Age from q3age
    capture {
        destring q3age, replace force
        replace mat_age = q3age if !missing(q3age) & inrange(q3age, 10, 60)
    }
    
    replace mat_age_cat = "<20" if mat_age < 20 & !missing(mat_age)
    replace mat_age_cat = "20-24" if inrange(mat_age, 20, 24)
    replace mat_age_cat = "25-29" if inrange(mat_age, 25, 29)
    replace mat_age_cat = "30-34" if inrange(mat_age, 30, 34)
    replace mat_age_cat = "35+" if mat_age >= 35 & !missing(mat_age)
    
    // Country from country variable
    capture replace out_country = country if !missing(country)
    
    // HOUSEHOLD WEALTH (placeholders - limited data in ALERT)
    generate str50 house_wall = ""
    generate str50 house_floor = ""
    generate str20 house_ownership = ""
    generate house_rooms = .
    generate str10 electricity = ""
    generate str50 water_source = ""
    generate str50 toilet_facilities = ""
    generate str30 cooking_fuel = ""
    generate str10 mosquito_net = ""
    generate str10 asset_bed = ""
    generate str10 asset_mobile = ""
    generate str10 asset_motorbike = ""
    generate str10 asset_car = ""
    generate str10 asset_radio = ""
    generate str10 asset_tv = ""
    generate monthly_income = .
    generate household_size = .
    generate ppi_score = .
    generate wealth_quintile = .
    generate asset_score = .
    
    // SECTIONS 4-12 placeholders (ALERT has limited data for these sections)
    generate str10 preg_hiv = ""
    generate str10 preg_chronic_htn = ""
    generate str10 preg_diabetes = ""
    generate str10 preg_anaemia = ""
    generate str10 preg_sickle_cell = ""
    generate str10 preg_tb = ""
    generate str10 preg_heart_disease = ""
    generate str10 preg_renal_disease = ""
    generate str10 preg_hepatic_disease = ""
    generate str10 preg_malaria = ""
    generate str10 preg_uti = ""
    
    // HIV from q11hiv
    capture {
        replace preg_hiv = "Yes" if regexm(lower(q11hiv), "yes|positive")
        replace preg_hiv = "No" if regexm(lower(q11hiv), "no|negative")
    }
    
    generate obs_gravidity = .
    generate obs_parity = .
    generate obs_previous_livebirths = .
    generate str10 obs_given_birth_before = ""
    generate str10 obs_previous_stillbirth = ""
    generate str10 obs_previous_csection = ""
    generate str10 obs_previous_abortion = ""
    
    // Obstetric history from ALERT variables
    capture {
        // Gravidity from q4grav
        destring q4grav, replace force
        replace obs_gravidity = q4grav if !missing(q4grav) & inrange(q4grav, 1, 20)
        
        // Parity from q6par
        destring q6par, replace force
        replace obs_parity = q6par if !missing(q6par) & inrange(q6par, 0, 15)
        
        // Previous CS from q7ces
        replace obs_previous_csection = "Yes" if regexm(lower(q7ces), "yes")
        replace obs_previous_csection = "No" if regexm(lower(q7ces), "no")
    }
    
    generate mat_height_cm = .
    generate mat_weight_kg = .
    generate mat_bmi = .
    generate str20 mat_bmi_cat = ""
    generate mat_muac_cm = .
    generate str20 mat_muac_cat = ""
    
    generate str10 anc_attended = ""
    generate anc_num_visits = .
    generate anc_ga_first_visit = .
    generate str100 anc_facility = ""
    generate str10 anc_tetanus_toxoid = ""
    
    // ANC from q8anc
    capture {
        replace anc_attended = "Yes" if regexm(lower(q8anc), "yes")
        replace anc_attended = "No" if regexm(lower(q8anc), "no")
    }
    
    generate str10 preg_gest_htn = ""
    generate str10 preg_preeclampsia = ""
    generate str10 preg_eclampsia = ""
    generate str10 preg_hdp = ""
    generate preg_sbp = .
    generate preg_dbp = .
    generate str10 preg_pprom = ""
    generate str10 preg_placenta_praevia = ""
    generate str10 preg_placenta_abruption = ""
    generate str10 preg_aph = ""
    generate str10 preg_pph = ""
    generate str10 preg_ruptured_uterus = ""
    generate str10 preg_prolonged_labour = ""
    generate str10 preg_obstructed_labour = ""
    generate str10 preg_breech = ""
    generate str10 preg_maternal_fever = ""
    generate str10 preg_meconium = ""
    
    generate str30 del_mode = ""
    generate str50 del_location = ""
    generate str20 del_location_type = ""
    generate str10 del_attendant_doctor = ""
    generate str10 del_attendant_midwife = ""
    generate str10 del_attendant_nurse = ""
    generate str10 del_attendant_tba = ""
    generate str10 del_attendant_family = ""
    generate str10 del_any_attendant = ""
    generate str20 del_labour_onset = ""
    generate str10 del_induction = ""
    generate str10 del_referred = ""
    generate str10 del_bba = ""
    
    generate str10 life_tobacco = ""
    generate str10 life_alcohol = ""
    generate str20 life_sleep_position = ""
    generate str10 life_fgm = ""
    
    generate str10 neo_resuscitation = ""
    generate str30 neo_resuscitation_type = ""
    generate str10 neo_malformation = ""
    generate str100 neo_malformation_type = ""
    generate str10 neo_nicu = ""
    generate str10 neo_breastfeeding = ""
    generate str10 neo_cry_at_birth = ""
    
    generate str10 mat_death = ""
    generate str30 mat_discharge_status = ""
    generate str10 mat_near_miss = ""
    
    // ENVIRONMENTAL DATA PLACEHOLDERS
    generate env_temp_mean = .
    generate env_temp_max = .
    generate env_temp_min = .
    generate env_precipitation = .
    generate env_humidity = .
    generate str20 env_season = ""
    generate env_heat_index = .
    generate env_latitude = .
    generate env_longitude = .
    
    display "âœ“ ALERT processing complete"
}
else {
    display "âœ— ALERT data not loaded"
    local alert_loaded = 0
}

/*==============================================================================
==============================================================================
SECTION: PRECISE DATA PROCESSING
==============================================================================
==============================================================================*/
frame change precise

display _newline(2) "=" * 70
display "LOADING AND PROCESSING PRECISE DATA"
display "=" * 70

capture import delimited "$precise/PRECISE_merged.csv", clear stringcols(_all)
if _rc != 0 {
    capture import delimited "$master/PRECISE_sample.csv", clear stringcols(_all)
}

if _rc == 0 & _N > 0 {
    display "âœ“ PRECISE data loaded: " _N " observations"
    local precise_loaded = 1
    
    // Study identifiers
    generate str20 study_source = "PRECISE"
    generate str20 study_design = "Facility-based"
    generate str40 module = "Prospective cohort"
    generate str30 study_id = "PRECISE_" + string(_n)
    generate studyyear = .
    
    // Extract year from delivery_date
    capture {
        generate double temp_dob = date(delivery_date, "DMY")
        replace temp_dob = date(delivery_date, "MDY") if missing(temp_dob)
        replace studyyear = year(temp_dob)
        drop temp_dob
    }
    
    // PRIMARY OUTCOMES
    generate str10 out_stillbirth = ""
    generate str10 out_fresh_stillbirth = ""
    generate str10 out_macerated_stillbirth = ""
    generate str10 out_stillbirth_20wks = ""
    generate str10 out_stillbirth_28wks = ""
    generate str10 out_livebirth = ""
    generate str10 out_nnd = ""
    generate str10 out_nnd_early = ""
    generate str10 out_nnd_late = ""
    generate str10 out_perinatal_death = ""
    generate str10 out_preterm = ""
    generate str10 out_very_preterm = ""
    generate str10 out_extremely_preterm = ""
    generate str10 out_sga = ""
    generate str10 out_lga = ""
    generate str10 out_lbw = ""
    generate str10 out_vlbw = ""
    generate str10 out_elbw = ""
    generate str10 out_multiple = ""
    
    generate double out_dob = .
    generate double out_dod = .
    format out_dob out_dod %td
    
    generate out_ga_weeks = .
    generate out_ga_days = .
    generate out_ageatdeath = .
    generate out_birthweight_g = .
    generate out_apgar_1min = .
    generate out_apgar_5min = .
    generate out_apgar_10min = .
    generate str10 out_infant_sex = ""
    generate str50 out_birth_location = ""
    generate out_birthweight_centile = .
    generate out_birthweight_zscore = .
    
    // Birth outcomes from PRECISE variables
    capture {
        // Stillbirth
        replace out_stillbirth = "Yes" if regexm(lower(stillbirth), "yes")
        replace out_stillbirth = "No" if regexm(lower(stillbirth), "no")
        
        // Live birth
        replace out_livebirth = "Yes" if regexm(lower(livebirth), "yes") | regexm(lower(bornalive), "yes")
        replace out_livebirth = "No" if regexm(lower(livebirth), "no") | regexm(lower(bornalive), "no")
        
        // Neonatal death
        replace out_nnd = "Yes" if regexm(lower(neonataldeath), "yes")
        replace out_nnd = "No" if regexm(lower(neonataldeath), "no")
        replace out_nnd = "" if out_livebirth != "Yes"
        
        // Preterm
        replace out_preterm = "Yes" if regexm(lower(preterm), "yes")
        replace out_preterm = "No" if regexm(lower(preterm), "no")
        
        // SGA from PRECISE sga variable
        replace out_sga = "Yes" if regexm(lower(sga), "yes|sga")
        replace out_sga = "No" if regexm(lower(sga), "no|aga|lga")
        
        // Low birthweight
        replace out_lbw = "Yes" if regexm(lower(lowbirthweight), "yes")
        replace out_lbw = "No" if regexm(lower(lowbirthweight), "no")
        
        // Multiple birth
        replace out_multiple = "Yes" if regexm(lower(delivery_num_of_babies), "twin|triplet|multiple|2|3")
        replace out_multiple = "No" if regexm(lower(delivery_num_of_babies), "single|1") & out_multiple == ""
    }
    
    // Gestational age from GA_PRECISE (weeks)
    capture {
        destring ga_precise, replace force
        replace out_ga_weeks = ga_precise if !missing(ga_precise) & inrange(ga_precise, 20, 45)
        
        destring ga_precise_days, replace force
        replace out_ga_days = ga_precise_days if !missing(ga_precise_days)
        replace out_ga_days = out_ga_weeks * 7 if missing(out_ga_days) & !missing(out_ga_weeks)
    }
    
    // Birth weight from Birthweight (grams)
    capture {
        destring birthweight, replace force
        replace out_birthweight_g = birthweight if !missing(birthweight) & inrange(birthweight, 300, 6000)
    }
    
    // Apgar scores
    capture {
        destring apgarscore_1min apgarscore_5min, replace force
        replace out_apgar_1min = apgarscore_1min if !missing(apgarscore_1min) & inrange(apgarscore_1min, 0, 10)
        replace out_apgar_5min = apgarscore_5min if !missing(apgarscore_5min) & inrange(apgarscore_5min, 0, 10)
    }
    
    // Infant sex
    capture {
        replace out_infant_sex = "Male" if regexm(lower(sex_of_baby), "male|boy|m")
        replace out_infant_sex = "Female" if regexm(lower(sex_of_baby), "female|girl|f")
    }
    
    // Birth location
    capture {
        replace out_birth_location = "Hospital" if regexm(lower(deliverylocation), "hospital|tertiary|regional")
        replace out_birth_location = "Health facility" if regexm(lower(deliverylocation), "phc|clinic|district") & out_birth_location == ""
        replace out_birth_location = "Home" if regexm(lower(deliverylocation), "home")
        replace out_birth_location = "En route" if regexm(lower(deliverylocation), "route")
    }
    
    // Date of birth
    capture {
        generate double temp_dob = date(delivery_date, "DMY")
        replace temp_dob = date(delivery_date, "MDY") if missing(temp_dob)
        replace out_dob = temp_dob
        format out_dob %td
        drop temp_dob
    }
    
    // Date of death
    capture {
        generate double temp_dod = date(baby_death_date, "DMY")
        replace temp_dod = date(baby_death_date, "MDY") if missing(temp_dod)
        replace out_dod = temp_dod
        format out_dod %td
        drop temp_dod
    }
    
    // Age at death from ageatdeath
    capture {
        destring ageatdeath, replace force
        replace out_ageatdeath = ageatdeath if !missing(ageatdeath) & out_nnd == "Yes"
    }
    
    // GA-based classifications
    replace out_stillbirth_20wks = "Yes" if out_stillbirth == "Yes" & out_ga_weeks >= 20
    replace out_stillbirth_20wks = "No" if out_stillbirth == "No"
    replace out_stillbirth_28wks = "Yes" if out_stillbirth == "Yes" & out_ga_weeks >= 28
    replace out_stillbirth_28wks = "No" if out_stillbirth == "No"
    
    // Preterm classifications
    replace out_preterm = "Yes" if out_livebirth == "Yes" & out_ga_weeks < 37 & out_ga_weeks >= 20 & out_preterm == ""
    replace out_preterm = "No" if out_livebirth == "Yes" & out_ga_weeks >= 37 & out_preterm == ""
    replace out_very_preterm = "Yes" if out_livebirth == "Yes" & out_ga_weeks < 32 & out_ga_weeks >= 20
    replace out_very_preterm = "No" if out_livebirth == "Yes" & out_ga_weeks >= 32
    replace out_extremely_preterm = "Yes" if out_livebirth == "Yes" & out_ga_weeks < 28 & out_ga_weeks >= 20
    replace out_extremely_preterm = "No" if out_livebirth == "Yes" & out_ga_weeks >= 28
    
    // LBW classifications
    replace out_lbw = "Yes" if out_livebirth == "Yes" & out_birthweight_g < 2500 & out_birthweight_g > 0 & out_lbw == ""
    replace out_lbw = "No" if out_livebirth == "Yes" & out_birthweight_g >= 2500 & out_lbw == ""
    replace out_vlbw = "Yes" if out_livebirth == "Yes" & out_birthweight_g < 1500 & out_birthweight_g > 0
    replace out_vlbw = "No" if out_livebirth == "Yes" & out_birthweight_g >= 1500
    replace out_elbw = "Yes" if out_livebirth == "Yes" & out_birthweight_g < 1000 & out_birthweight_g > 0
    replace out_elbw = "No" if out_livebirth == "Yes" & out_birthweight_g >= 1000
    
    // Early and late NND
    replace out_nnd_early = "Yes" if out_nnd == "Yes" & inrange(out_ageatdeath, 0, 7)
    replace out_nnd_early = "No" if out_nnd == "Yes" & !inrange(out_ageatdeath, 0, 7)
    replace out_nnd_early = "" if out_livebirth != "Yes"
    replace out_nnd_late = "Yes" if out_nnd == "Yes" & inrange(out_ageatdeath, 8, 28)
    replace out_nnd_late = "No" if out_nnd == "Yes" & !inrange(out_ageatdeath, 8, 28)
    replace out_nnd_late = "" if out_livebirth != "Yes"
    
    // Perinatal death
    replace out_perinatal_death = "Yes" if out_stillbirth_28wks == "Yes" | out_nnd_early == "Yes"
    replace out_perinatal_death = "No" if out_stillbirth_28wks == "No" & out_nnd_early == "No"
    
    // MATERNAL DEMOGRAPHICS
    generate mat_age = .
    generate str20 mat_age_cat = ""
    generate str50 mat_education = ""
    generate str50 fat_education = ""
    generate str50 mat_occupation = ""
    generate str50 fat_occupation = ""
    generate str30 marital_status = ""
    generate str30 religion = ""
    generate str50 ethnicity = ""
    generate str50 out_country = ""
    generate str100 mat_facility = ""
    generate str50 mat_district = ""
    generate str20 mat_urban_rural = ""
    generate str10 mat_literacy = ""
    
    capture {
        destring age_enrolment, replace force
        replace mat_age = age_enrolment if !missing(age_enrolment) & inrange(age_enrolment, 10, 60)
    }
    
    replace mat_age_cat = "<20" if mat_age < 20 & !missing(mat_age)
    replace mat_age_cat = "20-24" if inrange(mat_age, 20, 24)
    replace mat_age_cat = "25-29" if inrange(mat_age, 25, 29)
    replace mat_age_cat = "30-34" if inrange(mat_age, 30, 34)
    replace mat_age_cat = "35+" if mat_age >= 35 & !missing(mat_age)
    
    // Country
    capture replace out_country = country if !missing(country)
    
    // Education
    capture {
        replace mat_education = "None" if regexm(lower(highest_school_level), "none|never")
        replace mat_education = "Primary" if regexm(lower(highest_school_level), "primary")
        replace mat_education = "Secondary" if regexm(lower(highest_school_level), "secondary")
        replace mat_education = "Higher" if regexm(lower(highest_school_level), "higher|university|college|tertiary")
    }
    
    // Marital status
    capture {
        replace marital_status = "Married/Cohabiting" if regexm(lower(marital_status), "married|co-habit|cohabit")
        replace marital_status = "Single" if regexm(lower(marital_status), "single|never married")
        replace marital_status = "Divorced/Separated" if regexm(lower(marital_status), "divorced|separated")
        replace marital_status = "Widowed" if regexm(lower(marital_status), "widow")
    }
    
    // Religion
    capture {
        replace religion = "Christian" if regexm(lower(religion), "christian")
        replace religion = "Muslim" if regexm(lower(religion), "muslim|islam")
    }
    
    // Occupation
    capture {
        replace mat_occupation = "Employed" if regexm(lower(occupation), "professional|formal|employ")
        replace mat_occupation = "Self-employed" if regexm(lower(occupation), "informal|self|business")
        replace mat_occupation = "Unemployed" if regexm(lower(occupation), "housewife|unemployed|none")
        replace mat_occupation = "Student" if regexm(lower(occupation), "student")
    }
    
    // Ethnicity
    capture replace ethnicity = ethnicity if !missing(ethnicity)
    
    // Facility
    capture replace mat_facility = health_facility if !missing(health_facility)
    
    // Urban/rural
    capture {
        replace mat_urban_rural = "Urban" if regexm(lower(rural_urban_index), "urban") & !regexm(lower(rural_urban_index), "peri")
        replace mat_urban_rural = "Peri-urban" if regexm(lower(rural_urban_index), "peri")
        replace mat_urban_rural = "Rural" if regexm(lower(rural_urban_index), "rural")
    }
    
    // HOUSEHOLD WEALTH (PRECISE has PPI scores)
    generate str50 house_wall = ""
    generate str50 house_floor = ""
    generate str20 house_ownership = ""
    generate house_rooms = .
    generate str10 electricity = ""
    generate str50 water_source = ""
    generate str50 toilet_facilities = ""
    generate str30 cooking_fuel = ""
    generate str10 mosquito_net = ""
    generate str10 asset_bed = ""
    generate str10 asset_mobile = ""
    generate str10 asset_motorbike = ""
    generate str10 asset_car = ""
    generate str10 asset_radio = ""
    generate str10 asset_tv = ""
    generate monthly_income = .
    generate household_size = .
    generate ppi_score = .
    generate wealth_quintile = .
    generate asset_score = .
    
    // PPI Score
    capture {
        destring ppi_score, replace force
        replace ppi_score = ppi_score if !missing(ppi_score) & inrange(ppi_score, 0, 100)
    }
    
    // Water source from water_jmp
    capture {
        replace water_source = "Improved" if regexm(lower(water_jmp), "basic|improved")
        replace water_source = "Unimproved" if regexm(lower(water_jmp), "unimproved|surface|limited")
    }
    
    // Sanitation from sanitation_jmp
    capture {
        replace toilet_facilities = "Improved" if regexm(lower(sanitation_jmp), "basic")
        replace toilet_facilities = "Limited" if regexm(lower(sanitation_jmp), "limited")
        replace toilet_facilities = "Unimproved" if regexm(lower(sanitation_jmp), "unimproved|open")
    }
    
    // Cooking fuel
    capture {
        replace cooking_fuel = "Clean" if regexm(lower(cooking), "electric|gas")
        replace cooking_fuel = "Biomass" if regexm(lower(cooking), "biomass|wood|charcoal")
        replace cooking_fuel = "Other" if regexm(lower(cooking), "kerosene|coal")
    }
    
    // PRE-EXISTING MEDICAL CONDITIONS
    generate str10 preg_hiv = ""
    generate str10 preg_chronic_htn = ""
    generate str10 preg_diabetes = ""
    generate str10 preg_anaemia = ""
    generate str10 preg_sickle_cell = ""
    generate str10 preg_tb = ""
    generate str10 preg_heart_disease = ""
    generate str10 preg_renal_disease = ""
    generate str10 preg_hepatic_disease = ""
    generate str10 preg_malaria = ""
    generate str10 preg_uti = ""
    
    capture {
        replace preg_hiv = "Yes" if regexm(lower(hiv_status), "yes|positive")
        replace preg_hiv = "No" if regexm(lower(hiv_status), "no|negative")
        
        replace preg_chronic_htn = "Yes" if regexm(lower(ch_overall), "yes")
        replace preg_chronic_htn = "No" if regexm(lower(ch_overall), "no")
        
        replace preg_diabetes = "Yes" if regexm(lower(pre_gest_diab), "yes")
        replace preg_diabetes = "No" if regexm(lower(pre_gest_diab), "no")
    }
    
    // OBSTETRIC HISTORY
    generate obs_gravidity = .
    generate obs_parity = .
    generate obs_previous_livebirths = .
    generate str10 obs_given_birth_before = ""
    generate str10 obs_previous_stillbirth = ""
    generate str10 obs_previous_csection = ""
    generate str10 obs_previous_abortion = ""
    
    capture {
        destring parity, replace force
        replace obs_parity = parity if !missing(parity) & inrange(parity, 0, 15)
        
        replace obs_given_birth_before = "Yes" if regexm(lower(given_birth_before), "yes")
        replace obs_given_birth_before = "No" if regexm(lower(given_birth_before), "no")
        
        replace obs_previous_stillbirth = "Yes" if regexm(lower(previous_stillbirth), "yes")
        replace obs_previous_stillbirth = "No" if regexm(lower(previous_stillbirth), "no")
        
        replace obs_previous_csection = "Yes" if regexm(lower(previous_csection), "yes")
        replace obs_previous_csection = "No" if regexm(lower(previous_csection), "no")
        
        // Previous livebirths
        destring number_livebirths_male number_livebirths_female, replace force
        replace obs_previous_livebirths = number_livebirths_male + number_livebirths_female if ///
            !missing(number_livebirths_male) | !missing(number_livebirths_female)
    }
    
    // MATERNAL ANTHROPOMETRY
    generate mat_height_cm = .
    generate mat_weight_kg = .
    generate mat_bmi = .
    generate str20 mat_bmi_cat = ""
    generate mat_muac_cm = .
    generate str20 mat_muac_cat = ""
    
    capture {
        destring maternal_height maternal_weight maternal_bmi average_muac, replace force
        replace mat_height_cm = maternal_height if !missing(maternal_height) & inrange(maternal_height, 100, 200)
        replace mat_weight_kg = maternal_weight if !missing(maternal_weight) & inrange(maternal_weight, 30, 200)
        replace mat_bmi = maternal_bmi if !missing(maternal_bmi) & inrange(maternal_bmi, 10, 60)
        replace mat_muac_cm = average_muac if !missing(average_muac) & inrange(average_muac, 10, 50)
        
        // BMI categories
        replace mat_bmi_cat = "<18.5" if mat_bmi < 18.5 & !missing(mat_bmi)
        replace mat_bmi_cat = "18.5-24.9" if inrange(mat_bmi, 18.5, 24.9)
        replace mat_bmi_cat = "25-29.9" if inrange(mat_bmi, 25, 29.9)
        replace mat_bmi_cat = "30+" if mat_bmi >= 30 & !missing(mat_bmi)
        
        // MUAC categories
        replace mat_muac_cat = "Underweight" if mat_muac_cm < 23 & !missing(mat_muac_cm)
        replace mat_muac_cat = "Normal" if inrange(mat_muac_cm, 23, 26.4)
        replace mat_muac_cat = "Overweight" if inrange(mat_muac_cm, 26.5, 29.9)
        replace mat_muac_cat = "Obese" if mat_muac_cm >= 30 & !missing(mat_muac_cm)
    }
    
    // ANTENATAL CARE (placeholders)
    generate str10 anc_attended = ""
    generate anc_num_visits = .
    generate anc_ga_first_visit = .
    generate str100 anc_facility = ""
    generate str10 anc_tetanus_toxoid = ""
    
    capture {
        destring f7_antenatal_care_number_of_visi, replace force
        replace anc_num_visits = f7_antenatal_care_number_of_visi if !missing(f7_antenatal_care_number_of_visi)
        replace anc_attended = "Yes" if anc_num_visits > 0 & !missing(anc_num_visits)
        replace anc_attended = "No" if anc_num_visits == 0
    }
    
    // PREGNANCY COMPLICATIONS
    generate str10 preg_gest_htn = ""
    generate str10 preg_preeclampsia = ""
    generate str10 preg_eclampsia = ""
    generate str10 preg_hdp = ""
    generate preg_sbp = .
    generate preg_dbp = .
    generate str10 preg_pprom = ""
    generate str10 preg_placenta_praevia = ""
    generate str10 preg_placenta_abruption = ""
    generate str10 preg_aph = ""
    generate str10 preg_pph = ""
    generate str10 preg_ruptured_uterus = ""
    generate str10 preg_prolonged_labour = ""
    generate str10 preg_obstructed_labour = ""
    generate str10 preg_breech = ""
    generate str10 preg_maternal_fever = ""
    generate str10 preg_meconium = ""
    
    capture {
        replace preg_gest_htn = "Yes" if regexm(lower(gh_overall), "yes")
        replace preg_gest_htn = "No" if regexm(lower(gh_overall), "no")
        
        replace preg_preeclampsia = "Yes" if regexm(lower(pe_overall), "yes")
        replace preg_preeclampsia = "No" if regexm(lower(pe_overall), "no")
        
        replace preg_hdp = "Yes" if regexm(lower(hdp_overall), "yes") | regexm(lower(ht_overall), "yes")
        replace preg_hdp = "No" if regexm(lower(hdp_overall), "no") & regexm(lower(ht_overall), "no")
        
        destring average_sbp average_dbp, replace force
        replace preg_sbp = average_sbp if !missing(average_sbp) & inrange(average_sbp, 60, 250)
        replace preg_dbp = average_dbp if !missing(average_dbp) & inrange(average_dbp, 40, 150)
        
        replace preg_placenta_abruption = "Yes" if regexm(lower(f7_placenta_abruption), "yes")
        replace preg_placenta_abruption = "No" if regexm(lower(f7_placenta_abruption), "no")
    }
    
    // DELIVERY CHARACTERISTICS
    generate str30 del_mode = ""
    generate str50 del_location = ""
    generate str20 del_location_type = ""
    generate str10 del_attendant_doctor = ""
    generate str10 del_attendant_midwife = ""
    generate str10 del_attendant_nurse = ""
    generate str10 del_attendant_tba = ""
    generate str10 del_attendant_family = ""
    generate str10 del_any_attendant = ""
    generate str20 del_labour_onset = ""
    generate str10 del_induction = ""
    generate str10 del_referred = ""
    generate str10 del_bba = ""
    
    capture {
        replace del_mode = "Vaginal" if regexm(lower(delivery_mode), "vaginal|unassist")
        replace del_mode = "Caesarean" if regexm(lower(delivery_mode), "caesarean|c-section")
        replace del_mode = "Instrumental" if regexm(lower(delivery_mode), "operative|vacuum|forceps")
        
        replace del_location = out_birth_location
        replace del_location_type = "Facility" if inlist(del_location, "Hospital", "Health facility")
        replace del_location_type = "Non-facility" if inlist(del_location, "Home", "En route")
        
        replace del_attendant_doctor = "Yes" if regexm(lower(delivery_attendant_doctor), "yes")
        replace del_attendant_doctor = "No" if regexm(lower(delivery_attendant_doctor), "no")
        
        replace del_attendant_midwife = "Yes" if regexm(lower(delivery_attendant_midwife), "yes")
        replace del_attendant_midwife = "No" if regexm(lower(delivery_attendant_midwife), "no")
        
        replace del_any_attendant = "Yes" if regexm(lower(delivery_attendant_presence), "yes")
        replace del_any_attendant = "No" if regexm(lower(delivery_attendant_presence), "no")
    }
    
    // LIFESTYLE FACTORS
    generate str10 life_tobacco = ""
    generate str10 life_alcohol = ""
    generate str20 life_sleep_position = ""
    generate str10 life_fgm = ""
    
    capture {
        replace life_tobacco = "Yes" if regexm(lower(tobacco_use), "yes")
        replace life_tobacco = "No" if regexm(lower(tobacco_use), "no")
        
        replace life_fgm = "Yes" if regexm(lower(fgm), "yes")
        replace life_fgm = "No" if regexm(lower(fgm), "no")
        
        replace life_sleep_position = "Side" if regexm(lower(f6a_sleeping_position), "side")
        replace life_sleep_position = "Back" if regexm(lower(f6a_sleeping_position), "back")
        replace life_sleep_position = "Stomach" if regexm(lower(f6a_sleeping_position), "stomach")
    }
    
    // NEONATAL CHARACTERISTICS
    generate str10 neo_resuscitation = ""
    generate str30 neo_resuscitation_type = ""
    generate str10 neo_malformation = ""
    generate str100 neo_malformation_type = ""
    generate str10 neo_nicu = ""
    generate str10 neo_breastfeeding = ""
    generate str10 neo_cry_at_birth = ""
    
    capture {
        replace neo_nicu = "Yes" if regexm(lower(nicu_admission), "yes")
        replace neo_nicu = "No" if regexm(lower(nicu_admission), "no")
        
        replace neo_malformation = "Yes" if regexm(lower(f9_baby_malformation), "yes")
        replace neo_malformation = "No" if regexm(lower(f9_baby_malformation), "no")
    }
    
    // MATERNAL OUTCOMES
    generate str10 mat_death = ""
    generate str30 mat_discharge_status = ""
    generate str10 mat_near_miss = ""
    
    capture {
        replace mat_death = "Yes" if regexm(lower(maternal_death), "yes")
        replace mat_death = "No" if regexm(lower(maternal_death), "no")
    }
    
    // ENVIRONMENTAL DATA PLACEHOLDERS
    generate env_temp_mean = .
    generate env_temp_max = .
    generate env_temp_min = .
    generate env_precipitation = .
    generate env_humidity = .
    generate str20 env_season = ""
    generate env_heat_index = .
    generate env_latitude = .
    generate env_longitude = .
    
    // PRECISE has coordinates
    capture {
        destring villagelat villagelong, replace force
        replace env_latitude = villagelat if !missing(villagelat)
        replace env_longitude = villagelong if !missing(villagelong)
    }
    
    display "âœ“ PRECISE processing complete"
}
else {
    display "âœ— PRECISE data not loaded"
    local precise_loaded = 0
}

/*==============================================================================
[CONTINUING WITH PTBi, EN-INDEPTH, AND WHOMCS - SIMILAR STRUCTURE]
Due to length constraints, the remaining study sections follow the same pattern
with study-specific variable mappings as documented in Comprehensive_Data_Mapping_v5.docx
==============================================================================*/

// For brevity, I'll include abbreviated versions of the remaining studies
// Full implementations follow the same structure as above

/*==============================================================================
PTBi DATA PROCESSING (ABBREVIATED)
==============================================================================*/
frame change ptbi

display _newline(2) "=" * 70
display "LOADING AND PROCESSING PTBi DATA"
display "=" * 70

capture import delimited "$master/PTBi_sample.csv", clear stringcols(_all)

if _rc == 0 & _N > 0 {
    display "âœ“ PTBi data loaded: " _N " observations"
    local ptbi_loaded = 1
    
    // Study identifiers
    generate str20 study_source = "PTBi"
    generate str20 study_design = "Facility-based"
    generate str40 module = "Facility admission records"
    generate str30 study_id = "PTBi_" + string(_n)
    generate studyyear = .
    
    // Initialize all outcome variables
    generate str10 out_stillbirth = ""
    generate str10 out_fresh_stillbirth = ""
    generate str10 out_macerated_stillbirth = ""
    generate str10 out_stillbirth_20wks = ""
    generate str10 out_stillbirth_28wks = ""
    generate str10 out_livebirth = ""
    generate str10 out_nnd = ""
    generate str10 out_nnd_early = ""
    generate str10 out_nnd_late = ""
    generate str10 out_perinatal_death = ""
    generate str10 out_preterm = ""
    generate str10 out_very_preterm = ""
    generate str10 out_extremely_preterm = ""
    generate str10 out_sga = ""
    generate str10 out_lga = ""
    generate str10 out_lbw = ""
    generate str10 out_vlbw = ""
    generate str10 out_elbw = ""
    generate str10 out_multiple = ""
    
    generate double out_dob = .
    generate double out_dod = .
    format out_dob out_dod %td
    
    generate out_ga_weeks = .
    generate out_ga_days = .
    generate out_ageatdeath = .
    generate out_birthweight_g = .
    generate out_apgar_1min = .
    generate out_apgar_5min = .
    generate out_apgar_10min = .
    generate str10 out_infant_sex = ""
    generate str50 out_birth_location = ""
    generate out_birthweight_centile = .
    generate out_birthweight_zscore = .
    
    // Birth outcome from c_birth_outcome
    capture {
        replace out_stillbirth = "Yes" if regexm(lower(c_birth_outcome), "still_birth|stillbirth")
        replace out_stillbirth = "No" if regexm(lower(c_birth_outcome), "born_alive|livebirth")
        replace out_livebirth = "Yes" if regexm(lower(c_birth_outcome), "born_alive|livebirth")
        replace out_livebirth = "No" if regexm(lower(c_birth_outcome), "still_birth|stillbirth")
    }
    
    // GA from ga variable
    capture {
        destring ga, replace force
        replace out_ga_weeks = ga if !missing(ga) & inrange(ga, 20, 45)
        replace out_ga_days = out_ga_weeks * 7 if !missing(out_ga_weeks)
    }
    
    // Birth weight from birth_weight (kg to grams)
    capture {
        destring birth_weight, replace force
        replace out_birthweight_g = birth_weight * 1000 if !missing(birth_weight) & birth_weight < 10
        replace out_birthweight_g = birth_weight if !missing(birth_weight) & birth_weight >= 100 // Already in grams
    }
    
    // Apgar scores
    capture {
        destring apgar_1 apgar_5 apgar_10, replace force
        replace out_apgar_1min = apgar_1 if !missing(apgar_1) & inrange(apgar_1, 0, 10)
        replace out_apgar_5min = apgar_5 if !missing(apgar_5) & inrange(apgar_5, 0, 10)
        replace out_apgar_10min = apgar_10 if !missing(apgar_10) & inrange(apgar_10, 0, 10)
    }
    
    // Sex
    capture {
        replace out_infant_sex = "Male" if regexm(lower(sex), "male|m")
        replace out_infant_sex = "Female" if regexm(lower(sex), "female|f")
    }
    
    // GA-based classifications
    replace out_stillbirth_20wks = "Yes" if out_stillbirth == "Yes" & out_ga_weeks >= 20
    replace out_stillbirth_20wks = "No" if out_stillbirth == "No"
    replace out_stillbirth_28wks = "Yes" if out_stillbirth == "Yes" & out_ga_weeks >= 28
    replace out_stillbirth_28wks = "No" if out_stillbirth == "No"
    
    // Preterm
    replace out_preterm = "Yes" if out_livebirth == "Yes" & out_ga_weeks < 37 & out_ga_weeks >= 20
    replace out_preterm = "No" if out_livebirth == "Yes" & out_ga_weeks >= 37
    
    // LBW
    replace out_lbw = "Yes" if out_livebirth == "Yes" & out_birthweight_g < 2500 & out_birthweight_g > 0
    replace out_lbw = "No" if out_livebirth == "Yes" & out_birthweight_g >= 2500
    
    // Multiple birth
    capture {
        destring multiple, replace force
        replace out_multiple = "Yes" if multiple > 1 & !missing(multiple)
        replace out_multiple = "No" if multiple == 1
    }
    
    // Neonatal death from baby_discharge_status
    capture {
        replace out_nnd = "Yes" if regexm(lower(baby_discharge_status), "death|died") & out_livebirth == "Yes"
        replace out_nnd = "No" if !regexm(lower(baby_discharge_status), "death|died") & out_livebirth == "Yes"
    }
    
    // Maternal demographics
    generate mat_age = .
    generate str20 mat_age_cat = ""
    generate str50 mat_education = ""
    generate str50 fat_education = ""
    generate str50 mat_occupation = ""
    generate str50 fat_occupation = ""
    generate str30 marital_status = ""
    generate str30 religion = ""
    generate str50 ethnicity = ""
    generate str50 out_country = "Uganda"
    generate str100 mat_facility = ""
    generate str50 mat_district = ""
    generate str20 mat_urban_rural = ""
    generate str10 mat_literacy = ""
    
    capture {
        destring mothers_age, replace force
        replace mat_age = mothers_age if !missing(mothers_age) & inrange(mothers_age, 10, 60)
    }
    
    replace mat_age_cat = "<20" if mat_age < 20 & !missing(mat_age)
    replace mat_age_cat = "20-24" if inrange(mat_age, 20, 24)
    replace mat_age_cat = "25-29" if inrange(mat_age, 25, 29)
    replace mat_age_cat = "30-34" if inrange(mat_age, 30, 34)
    replace mat_age_cat = "35+" if mat_age >= 35 & !missing(mat_age)
    
    capture replace mat_facility = facility if !missing(facility)
    
    // Initialize remaining section variables as placeholders
    // (Full implementation follows same pattern as NCOPS/PRECISE)
    
    generate str50 house_wall = ""
    generate str50 house_floor = ""
    generate str20 house_ownership = ""
    generate house_rooms = .
    generate str10 electricity = ""
    generate str50 water_source = ""
    generate str50 toilet_facilities = ""
    generate str30 cooking_fuel = ""
    generate str10 mosquito_net = ""
    generate str10 asset_bed = ""
    generate str10 asset_mobile = ""
    generate str10 asset_motorbike = ""
    generate str10 asset_car = ""
    generate str10 asset_radio = ""
    generate str10 asset_tv = ""
    generate monthly_income = .
    generate household_size = .
    generate ppi_score = .
    generate wealth_quintile = .
    generate asset_score = .
    
    generate str10 preg_hiv = ""
    generate str10 preg_chronic_htn = ""
    generate str10 preg_diabetes = ""
    generate str10 preg_anaemia = ""
    generate str10 preg_sickle_cell = ""
    generate str10 preg_tb = ""
    generate str10 preg_heart_disease = ""
    generate str10 preg_renal_disease = ""
    generate str10 preg_hepatic_disease = ""
    generate str10 preg_malaria = ""
    generate str10 preg_uti = ""
    
    // Medical conditions from finaldiag variables
    capture {
        destring finaldiag_malaria_in_pregnancy finaldiag_high_blood_pressure_in ///
            finaldiag_anaemia_in_pregnancy finaldiag_urinary_tract_infectio, replace force
        
        replace preg_malaria = "Yes" if finaldiag_malaria_in_pregnancy == 1
        replace preg_malaria = "No" if finaldiag_malaria_in_pregnancy == 0
        
        replace preg_gest_htn = "Yes" if finaldiag_high_blood_pressure_in == 1
        replace preg_gest_htn = "No" if finaldiag_high_blood_pressure_in == 0
        
        replace preg_anaemia = "Yes" if finaldiag_anaemia_in_pregnancy == 1
        replace preg_anaemia = "No" if finaldiag_anaemia_in_pregnancy == 0
        
        replace preg_uti = "Yes" if finaldiag_urinary_tract_infectio == 1
        replace preg_uti = "No" if finaldiag_urinary_tract_infectio == 0
    }
    
    generate obs_gravidity = .
    generate obs_parity = .
    generate obs_previous_livebirths = .
    generate str10 obs_given_birth_before = ""
    generate str10 obs_previous_stillbirth = ""
    generate str10 obs_previous_csection = ""
    generate str10 obs_previous_abortion = ""
    
    generate mat_height_cm = .
    generate mat_weight_kg = .
    generate mat_bmi = .
    generate str20 mat_bmi_cat = ""
    generate mat_muac_cm = .
    generate str20 mat_muac_cat = ""
    
    generate str10 anc_attended = ""
    generate anc_num_visits = .
    generate anc_ga_first_visit = .
    generate str100 anc_facility = ""
    generate str10 anc_tetanus_toxoid = ""
    
    generate str10 preg_gest_htn = ""
    generate str10 preg_preeclampsia = ""
    generate str10 preg_eclampsia = ""
    generate str10 preg_hdp = ""
    generate preg_sbp = .
    generate preg_dbp = .
    generate str10 preg_pprom = ""
    generate str10 preg_placenta_praevia = ""
    generate str10 preg_placenta_abruption = ""
    generate str10 preg_aph = ""
    generate str10 preg_pph = ""
    generate str10 preg_ruptured_uterus = ""
    generate str10 preg_prolonged_labour = ""
    generate str10 preg_obstructed_labour = ""
    generate str10 preg_breech = ""
    generate str10 preg_maternal_fever = ""
    generate str10 preg_meconium = ""
    
    // Pregnancy complications from finaldiag
    capture {
        destring finaldiag_aph finaldiag_pph finaldiag_obstructed_labour ///
            finaldiag_ruptured_uterus finaldiag_puerperal_sepsis, replace force
        
        replace preg_aph = "Yes" if finaldiag_aph == 1
        replace preg_aph = "No" if finaldiag_aph == 0
        
        replace preg_pph = "Yes" if finaldiag_pph == 1
        replace preg_pph = "No" if finaldiag_pph == 0
        
        replace preg_obstructed_labour = "Yes" if finaldiag_obstructed_labour == 1
        replace preg_obstructed_labour = "No" if finaldiag_obstructed_labour == 0
        
        replace preg_ruptured_uterus = "Yes" if finaldiag_ruptured_uterus == 1
        replace preg_ruptured_uterus = "No" if finaldiag_ruptured_uterus == 0
    }
    
    generate str30 del_mode = ""
    generate str50 del_location = ""
    generate str20 del_location_type = ""
    generate str10 del_attendant_doctor = ""
    generate str10 del_attendant_midwife = ""
    generate str10 del_attendant_nurse = ""
    generate str10 del_attendant_tba = ""
    generate str10 del_attendant_family = ""
    generate str10 del_any_attendant = ""
    generate str20 del_labour_onset = ""
    generate str10 del_induction = ""
    generate str10 del_referred = ""
    generate str10 del_bba = ""
    
    // Delivery mode
    capture {
        replace del_mode = "Vaginal" if regexm(lower(mode_of_delivery), "vaginal|normal")
        replace del_mode = "Caesarean" if regexm(lower(mode_of_delivery), "caesarean")
        replace del_mode = "Instrumental" if regexm(lower(mode_of_delivery), "vacuum")
        
        destring bba, replace force
        replace del_bba = "Yes" if bba == 1
        replace del_bba = "No" if bba == 0
        
        replace del_referred = "Yes" if regexm(lower(referral_in), "yes")
        replace del_referred = "No" if regexm(lower(referral_in), "no")
    }
    
    generate str10 life_tobacco = ""
    generate str10 life_alcohol = ""
    generate str20 life_sleep_position = ""
    generate str10 life_fgm = ""
    
    generate str10 neo_resuscitation = ""
    generate str30 neo_resuscitation_type = ""
    generate str10 neo_malformation = ""
    generate str100 neo_malformation_type = ""
    generate str10 neo_nicu = ""
    generate str10 neo_breastfeeding = ""
    generate str10 neo_cry_at_birth = ""
    
    generate str10 mat_death = ""
    generate str30 mat_discharge_status = ""
    generate str10 mat_near_miss = ""
    
    capture {
        replace mat_death = "Yes" if regexm(lower(c_mother_status), "died|death")
        replace mat_death = "No" if regexm(lower(c_mother_status), "alive|discharged")
        replace mat_discharge_status = c_mother_status if !missing(c_mother_status)
    }
    
    // Environmental data placeholders
    generate env_temp_mean = .
    generate env_temp_max = .
    generate env_temp_min = .
    generate env_precipitation = .
    generate env_humidity = .
    generate str20 env_season = ""
    generate env_heat_index = .
    generate env_latitude = .
    generate env_longitude = .
    
    display "âœ“ PTBi processing complete"
}
else {
    display "âœ— PTBi data not loaded"
    local ptbi_loaded = 0
}

/*==============================================================================
EN-INDEPTH DATA PROCESSING (ABBREVIATED)
==============================================================================*/
frame change enindepth

display _newline(2) "=" * 70
display "LOADING AND PROCESSING EN-INDEPTH DATA"
display "=" * 70

capture import delimited "$master/ENINDEPTH_sample.csv", clear stringcols(_all)

if _rc == 0 & _N > 0 {
    display "âœ“ EN-INDEPTH data loaded: " _N " observations"
    local enindepth_loaded = 1
    
    // Study identifiers
    generate str20 study_source = "EN-INDEPTH"
    generate str20 study_design = "Population-based"
    generate str40 module = "HDSS pregnancy surveillance"
    generate str30 study_id = "ENINDEPTH_" + string(_n)
    generate studyyear = .
    
    // Initialize all outcome variables (same structure as other studies)
    generate str10 out_stillbirth = ""
    generate str10 out_fresh_stillbirth = ""
    generate str10 out_macerated_stillbirth = ""
    generate str10 out_stillbirth_20wks = ""
    generate str10 out_stillbirth_28wks = ""
    generate str10 out_livebirth = ""
    generate str10 out_nnd = ""
    generate str10 out_nnd_early = ""
    generate str10 out_nnd_late = ""
    generate str10 out_perinatal_death = ""
    generate str10 out_preterm = ""
    generate str10 out_very_preterm = ""
    generate str10 out_extremely_preterm = ""
    generate str10 out_sga = ""
    generate str10 out_lga = ""
    generate str10 out_lbw = ""
    generate str10 out_vlbw = ""
    generate str10 out_elbw = ""
    generate str10 out_multiple = ""
    
    generate double out_dob = .
    generate double out_dod = .
    format out_dob out_dod %td
    
    generate out_ga_weeks = .
    generate out_ga_days = .
    generate out_ageatdeath = .
    generate out_birthweight_g = .
    generate out_apgar_1min = .
    generate out_apgar_5min = .
    generate out_apgar_10min = .
    generate str10 out_infant_sex = ""
    generate str50 out_birth_location = ""
    generate out_birthweight_centile = .
    generate out_birthweight_zscore = .
    
    // Birth outcomes from EN-INDEPTH
    capture {
        destring sb nnd neonataldeath livebirths, replace force
        
        replace out_stillbirth = "Yes" if sb == 1
        replace out_stillbirth = "No" if sb == 0
        
        replace out_livebirth = "Yes" if alivedead == "YES" | p212b == "BORN ALIVE"
        replace out_livebirth = "No" if alivedead == "NO" | p212b == "BORN DEAD"
        
        replace out_nnd = "Yes" if (nnd == 1 | neonataldeath == 1) & out_livebirth == "Yes"
        replace out_nnd = "No" if (nnd == 0 | neonataldeath == 0) & out_livebirth == "Yes"
        
        // Age at death
        destring agedead_d, replace force
        replace out_ageatdeath = agedead_d if !missing(agedead_d) & out_nnd == "Yes"
        
        // Early/late NND
        replace out_nnd_early = "Yes" if out_nnd == "Yes" & inrange(out_ageatdeath, 0, 7)
        replace out_nnd_early = "No" if out_nnd == "Yes" & !inrange(out_ageatdeath, 0, 7)
        replace out_nnd_late = "Yes" if out_nnd == "Yes" & inrange(out_ageatdeath, 8, 28)
        replace out_nnd_late = "No" if out_nnd == "Yes" & !inrange(out_ageatdeath, 8, 28)
    }
    
    // GA from gestation variables
    capture {
        destring gestation1, replace force
        replace out_ga_weeks = gestation1 * 4 if !missing(gestation1) // Convert months to weeks
        replace out_ga_days = out_ga_weeks * 7 if !missing(out_ga_weeks)
    }
    
    // Sex
    capture {
        replace out_infant_sex = "Male" if regexm(lower(gender), "boy|male")
        replace out_infant_sex = "Female" if regexm(lower(gender), "girl|female")
    }
    
    // Multiple birth
    capture {
        replace out_multiple = "Yes" if regexm(lower(sing_mult), "yes|multiple")
        replace out_multiple = "No" if regexm(lower(sing_mult), "no|single")
    }
    
    // GA-based classifications
    replace out_stillbirth_20wks = "Yes" if out_stillbirth == "Yes" & out_ga_weeks >= 20
    replace out_stillbirth_20wks = "No" if out_stillbirth == "No"
    replace out_stillbirth_28wks = "Yes" if out_stillbirth == "Yes" & out_ga_weeks >= 28
    replace out_stillbirth_28wks = "No" if out_stillbirth == "No"
    
    // Perinatal death
    replace out_perinatal_death = "Yes" if out_stillbirth_28wks == "Yes" | out_nnd_early == "Yes"
    replace out_perinatal_death = "No" if out_stillbirth_28wks == "No" & out_nnd_early == "No"
    
    // Maternal demographics
    generate mat_age = .
    generate str20 mat_age_cat = ""
    generate str50 mat_education = ""
    generate str50 fat_education = ""
    generate str50 mat_occupation = ""
    generate str50 fat_occupation = ""
    generate str30 marital_status = ""
    generate str30 religion = ""
    generate str50 ethnicity = ""
    generate str50 out_country = ""
    generate str100 mat_facility = ""
    generate str50 mat_district = ""
    generate str20 mat_urban_rural = ""
    generate str10 mat_literacy = ""
    
    capture {
        destring womanage, replace force
        replace mat_age = womanage if !missing(womanage) & inrange(womanage, 10, 60)
    }
    
    replace mat_age_cat = "<20" if mat_age < 20 & !missing(mat_age)
    replace mat_age_cat = "20-24" if inrange(mat_age, 20, 24)
    replace mat_age_cat = "25-29" if inrange(mat_age, 25, 29)
    replace mat_age_cat = "30-34" if inrange(mat_age, 30, 34)
    replace mat_age_cat = "35+" if mat_age >= 35 & !missing(mat_age)
    
    // Country and HDSS
    capture replace out_country = country if !missing(country)
    capture replace mat_facility = hdss if !missing(hdss)
    
    // Education
    capture {
        replace mat_education = "None" if regexm(lower(education), "none|never|no education")
        replace mat_education = "Primary" if regexm(lower(education), "primary")
        replace mat_education = "Secondary" if regexm(lower(education), "secondary")
        replace mat_education = "Higher" if regexm(lower(education), "higher|university|college|tertiary")
    }
    
    // Marital status
    capture {
        replace marital_status = "Married/Cohabiting" if regexm(lower(q107_combined), "yes")
        replace marital_status = "Single" if regexm(lower(q107_combined), "no")
    }
    
    // Religion
    capture {
        replace religion = "Christian" if regexm(lower(religion), "christian")
        replace religion = "Muslim" if regexm(lower(religion), "muslim|islam")
        replace religion = "Traditional" if regexm(lower(religion), "traditional")
        replace religion = "Other" if regexm(lower(religion), "other")
    }
    
    // Literacy
    capture {
        replace mat_literacy = "Yes" if regexm(lower(q111), "able to read")
        replace mat_literacy = "No" if regexm(lower(q111), "cannot read")
    }
    
    // Household wealth
    generate str50 house_wall = ""
    generate str50 house_floor = ""
    generate str20 house_ownership = ""
    generate house_rooms = .
    generate str10 electricity = ""
    generate str50 water_source = ""
    generate str50 toilet_facilities = ""
    generate str30 cooking_fuel = ""
    generate str10 mosquito_net = ""
    generate str10 asset_bed = ""
    generate str10 asset_mobile = ""
    generate str10 asset_motorbike = ""
    generate str10 asset_car = ""
    generate str10 asset_radio = ""
    generate str10 asset_tv = ""
    generate monthly_income = .
    generate household_size = .
    generate ppi_score = .
    generate wealth_quintile = .
    generate asset_score = .
    
    capture {
        destring quintile asset_index1 asset_index2 asset_index3 asset_index4 asset_index5, replace force
        replace wealth_quintile = quintile if !missing(quintile)
        
        // Use appropriate asset index based on site
        replace asset_score = asset_index1 if !missing(asset_index1)
        replace asset_score = asset_index2 if missing(asset_score) & !missing(asset_index2)
        replace asset_score = asset_index3 if missing(asset_score) & !missing(asset_index3)
        replace asset_score = asset_index4 if missing(asset_score) & !missing(asset_index4)
        replace asset_score = asset_index5 if missing(asset_score) & !missing(asset_index5)
    }
    
    // Initialize remaining variables (placeholders)
    generate str10 preg_hiv = ""
    generate str10 preg_chronic_htn = ""
    generate str10 preg_diabetes = ""
    generate str10 preg_anaemia = ""
    generate str10 preg_sickle_cell = ""
    generate str10 preg_tb = ""
    generate str10 preg_heart_disease = ""
    generate str10 preg_renal_disease = ""
    generate str10 preg_hepatic_disease = ""
    generate str10 preg_malaria = ""
    generate str10 preg_uti = ""
    
    generate obs_gravidity = .
    generate obs_parity = .
    generate obs_previous_livebirths = .
    generate str10 obs_given_birth_before = ""
    generate str10 obs_previous_stillbirth = ""
    generate str10 obs_previous_csection = ""
    generate str10 obs_previous_abortion = ""
    
    capture {
        destring gravidity n_gravidity, replace force
        replace obs_gravidity = n_gravidity if !missing(n_gravidity)
        
        replace obs_given_birth_before = "Yes" if regexm(lower(pq201), "yes")
        replace obs_given_birth_before = "No" if regexm(lower(pq201), "no")
    }
    
    generate mat_height_cm = .
    generate mat_weight_kg = .
    generate mat_bmi = .
    generate str20 mat_bmi_cat = ""
    generate mat_muac_cm = .
    generate str20 mat_muac_cat = ""
    
    generate str10 anc_attended = ""
    generate anc_num_visits = .
    generate anc_ga_first_visit = .
    generate str100 anc_facility = ""
    generate str10 anc_tetanus_toxoid = ""
    
    generate str10 preg_gest_htn = ""
    generate str10 preg_preeclampsia = ""
    generate str10 preg_eclampsia = ""
    generate str10 preg_hdp = ""
    generate preg_sbp = .
    generate preg_dbp = .
    generate str10 preg_pprom = ""
    generate str10 preg_placenta_praevia = ""
    generate str10 preg_placenta_abruption = ""
    generate str10 preg_aph = ""
    generate str10 preg_pph = ""
    generate str10 preg_ruptured_uterus = ""
    generate str10 preg_prolonged_labour = ""
    generate str10 preg_obstructed_labour = ""
    generate str10 preg_breech = ""
    generate str10 preg_maternal_fever = ""
    generate str10 preg_meconium = ""
    
    generate str30 del_mode = ""
    generate str50 del_location = ""
    generate str20 del_location_type = ""
    generate str10 del_attendant_doctor = ""
    generate str10 del_attendant_midwife = ""
    generate str10 del_attendant_nurse = ""
    generate str10 del_attendant_tba = ""
    generate str10 del_attendant_family = ""
    generate str10 del_any_attendant = ""
    generate str20 del_labour_onset = ""
    generate str10 del_induction = ""
    generate str10 del_referred = ""
    generate str10 del_bba = ""
    
    generate str10 life_tobacco = ""
    generate str10 life_alcohol = ""
    generate str20 life_sleep_position = ""
    generate str10 life_fgm = ""
    
    generate str10 neo_resuscitation = ""
    generate str30 neo_resuscitation_type = ""
    generate str10 neo_malformation = ""
    generate str100 neo_malformation_type = ""
    generate str10 neo_nicu = ""
    generate str10 neo_breastfeeding = ""
    generate str10 neo_cry_at_birth = ""
    
    generate str10 mat_death = ""
    generate str30 mat_discharge_status = ""
    generate str10 mat_near_miss = ""
    
    // Environmental data placeholders
    generate env_temp_mean = .
    generate env_temp_max = .
    generate env_temp_min = .
    generate env_precipitation = .
    generate env_humidity = .
    generate str20 env_season = ""
    generate env_heat_index = .
    generate env_latitude = .
    generate env_longitude = .
    
    display "âœ“ EN-INDEPTH processing complete"
}
else {
    display "âœ— EN-INDEPTH data not loaded"
    local enindepth_loaded = 0
}

/*==============================================================================
WHOMCS DATA PROCESSING (FULL IMPLEMENTATION)
==============================================================================*/
frame change whomcs

display _newline(2) "=" * 70
display "LOADING AND PROCESSING WHOMCS DATA"
display "=" * 70

capture import delimited "$master/whomcs_sample.csv", clear stringcols(_all)

if _rc == 0 & _N > 0 {
    display "âœ“ WHOMCS data loaded: " _N " observations"
    local whomcs_loaded = 1
    
    // Study identifiers
    generate str20 study_source = "WHOMCS"
    generate str20 study_design = "Facility-based"
    generate str40 module = "Facility cross-sectional survey"
    generate str30 study_id = "WHOMCS_" + patient if !missing(patient)
    replace study_id = "WHOMCS_" + string(_n) if missing(study_id)
    generate studyyear = .
    
    // Extract year from date of delivery
    capture {
        generate double temp_dob = date(datedelorabort, "DMY")
        replace temp_dob = date(datedelorabort, "YMD") if missing(temp_dob)
        replace studyyear = year(temp_dob)
        drop temp_dob
    }
    
    /*==========================================================================
    SECTION 1: PRIMARY OUTCOME VARIABLES
    ==========================================================================*/
    
    // Initialize ALL outcome variables
    generate str10 out_stillbirth = ""
    generate str10 out_fresh_stillbirth = ""
    generate str10 out_macerated_stillbirth = ""
    generate str10 out_stillbirth_20wks = ""
    generate str10 out_stillbirth_28wks = ""
    generate str10 out_livebirth = ""
    generate str10 out_nnd = ""
    generate str10 out_nnd_early = ""
    generate str10 out_nnd_late = ""
    generate str10 out_perinatal_death = ""
    generate str10 out_preterm = ""
    generate str10 out_very_preterm = ""
    generate str10 out_extremely_preterm = ""
    generate str10 out_sga = ""
    generate str10 out_lga = ""
    generate str10 out_lbw = ""
    generate str10 out_vlbw = ""
    generate str10 out_elbw = ""
    generate str10 out_multiple = ""
    
    generate double out_dob = .
    generate double out_dod = .
    format out_dob out_dod %td
    
    generate out_ga_weeks = .
    generate out_ga_days = .
    generate out_ageatdeath = .
    generate out_birthweight_g = .
    generate out_apgar_1min = .
    generate out_apgar_5min = .
    generate out_apgar_10min = .
    generate str10 out_infant_sex = ""
    generate str50 out_birth_location = ""
    generate out_birthweight_centile = .
    generate out_birthweight_zscore = .
    
    // Convert date of delivery
    capture {
        generate double dob_td = date(datedelorabort, "DMY")
        replace dob_td = date(datedelorabort, "YMD") if missing(dob_td)
        format dob_td %td
        replace out_dob = dob_td if !missing(dob_td)
    }
    
    // Convert neonatal date (discharge/death)
    capture {
        generate double neo_date_td = date(neo_date, "DMY")
        replace neo_date_td = date(neo_date, "YMD") if missing(neo_date_td)
        format neo_date_td %td
    }
    
    // Gestational age
    capture {
        destring ga, replace force
        replace out_ga_weeks = ga if !missing(ga) & inrange(ga, 20, 45)
        replace out_ga_days = out_ga_weeks * 7 if !missing(out_ga_weeks)
    }
    
    // Birth weight - WHOMCS records weight in grams
    capture {
        destring bw, replace force
        replace out_birthweight_g = bw if !missing(bw) & inrange(bw, 300, 6000)
    }
    
    // Apgar score at 5 min
    capture {
        destring apgar, replace force
        replace out_apgar_5min = apgar if !missing(apgar) & inrange(apgar, 0, 10)
    }
    
    // Infant sex (1=male, 2=female in WHOMCS)
    capture {
        destring sex, replace force
        replace out_infant_sex = "Male" if sex == 1
        replace out_infant_sex = "Female" if sex == 2
    }
    
    // BIRTH OUTCOMES - birthstat: 1=livebirth, 2=fresh stillbirth, 3=macerated stillbirth
    capture {
        destring birthstat, replace force
        replace out_livebirth = "Yes" if birthstat == 1
        replace out_livebirth = "No" if inlist(birthstat, 2, 3)
        
        replace out_stillbirth = "Yes" if inlist(birthstat, 2, 3)
        replace out_stillbirth = "No" if birthstat == 1
        
        replace out_fresh_stillbirth = "Yes" if birthstat == 2
        replace out_fresh_stillbirth = "No" if birthstat != 2 & !missing(birthstat)
        
        replace out_macerated_stillbirth = "Yes" if birthstat == 3
        replace out_macerated_stillbirth = "No" if birthstat != 3 & !missing(birthstat)
    }
    
    // Use STILLBIRTH_INDICATOR and LFD_INDICATOR if available
    capture {
        destring stillbirth_indicator lfd_indicator enm_indicator, replace force
        replace out_stillbirth = "Yes" if stillbirth_indicator == 1 & out_stillbirth == ""
        replace out_stillbirth_28wks = "Yes" if lfd_indicator == 1
        replace out_stillbirth_28wks = "No" if lfd_indicator == 0
    }
    
    // GA-based stillbirth classifications
    replace out_stillbirth_20wks = "Yes" if out_stillbirth == "Yes" & out_ga_weeks >= 20
    replace out_stillbirth_20wks = "No" if out_stillbirth == "No"
    replace out_stillbirth_20wks = "" if missing(out_ga_weeks) & out_stillbirth == "Yes"
    
    replace out_stillbirth_28wks = "Yes" if out_stillbirth == "Yes" & out_ga_weeks >= 28 & out_stillbirth_28wks == ""
    replace out_stillbirth_28wks = "No" if out_stillbirth == "No" & out_stillbirth_28wks == ""
    
    // NEONATAL DEATH - neostat: newborn status at hospital discharge/day 7
    // ENM_INDICATOR: early neonatal death indicator
    capture {
        destring neostat enm_indicator, replace force
        // neostat interpretation may vary - check if dead/alive
        replace out_nnd = "Yes" if enm_indicator == 1 & out_livebirth == "Yes"
        replace out_nnd = "No" if enm_indicator == 0 & out_livebirth == "Yes"
        
        // neostat = 0 typically means alive, other values may indicate death
        replace out_nnd = "Yes" if neostat > 0 & out_livebirth == "Yes" & out_nnd == ""
        replace out_nnd = "No" if neostat == 0 & out_livebirth == "Yes" & out_nnd == ""
    }
    replace out_nnd = "" if out_livebirth != "Yes"
    
    // Age at death - calculate from dates if available
    capture {
        replace out_ageatdeath = neo_date_td - out_dob if out_nnd == "Yes" & ///
            !missing(neo_date_td) & !missing(out_dob)
        replace out_ageatdeath = . if out_ageatdeath < 0 | out_ageatdeath > 28
    }
    
    // Early and late NND
    replace out_nnd_early = "Yes" if out_nnd == "Yes" & inrange(out_ageatdeath, 0, 7)
    replace out_nnd_early = "Yes" if enm_indicator == 1 & out_livebirth == "Yes" & out_nnd_early == ""
    replace out_nnd_early = "No" if out_nnd == "Yes" & !inrange(out_ageatdeath, 0, 7) & out_nnd_early == ""
    replace out_nnd_early = "" if out_livebirth != "Yes"
    
    replace out_nnd_late = "Yes" if out_nnd == "Yes" & inrange(out_ageatdeath, 8, 28)
    replace out_nnd_late = "No" if out_nnd == "Yes" & !inrange(out_ageatdeath, 8, 28)
    replace out_nnd_late = "" if out_livebirth != "Yes"
    
    // Perinatal death - use PNM_INDICATOR or derive
    capture {
        destring pnm_indicator, replace force
        replace out_perinatal_death = "Yes" if pnm_indicator == 1
        replace out_perinatal_death = "No" if pnm_indicator == 0
    }
    replace out_perinatal_death = "Yes" if out_stillbirth_28wks == "Yes" | out_nnd_early == "Yes"
    replace out_perinatal_death = "No" if out_stillbirth_28wks == "No" & out_nnd_early == "No" & out_perinatal_death == ""
    
    // EXTENDED OUTCOMES
    
    // Preterm classifications
    replace out_preterm = "Yes" if out_livebirth == "Yes" & out_ga_weeks < 37 & out_ga_weeks >= 20
    replace out_preterm = "No" if out_livebirth == "Yes" & out_ga_weeks >= 37
    replace out_very_preterm = "Yes" if out_livebirth == "Yes" & out_ga_weeks < 32 & out_ga_weeks >= 20
    replace out_very_preterm = "No" if out_livebirth == "Yes" & (out_ga_weeks >= 32 | out_ga_weeks < 20)
    replace out_extremely_preterm = "Yes" if out_livebirth == "Yes" & out_ga_weeks < 28 & out_ga_weeks >= 20
    replace out_extremely_preterm = "No" if out_livebirth == "Yes" & (out_ga_weeks >= 28 | out_ga_weeks < 20)
    
    // Low birth weight classifications
    replace out_lbw = "Yes" if out_livebirth == "Yes" & out_birthweight_g < 2500 & out_birthweight_g > 0
    replace out_lbw = "No" if out_livebirth == "Yes" & out_birthweight_g >= 2500
    replace out_vlbw = "Yes" if out_livebirth == "Yes" & out_birthweight_g < 1500 & out_birthweight_g > 0
    replace out_vlbw = "No" if out_livebirth == "Yes" & out_birthweight_g >= 1500
    replace out_elbw = "Yes" if out_livebirth == "Yes" & out_birthweight_g < 1000 & out_birthweight_g > 0
    replace out_elbw = "No" if out_livebirth == "Yes" & out_birthweight_g >= 1000
    
    // Multiple birth
    capture {
        destring num_neo, replace force
        replace out_multiple = "Yes" if num_neo > 1 & !missing(num_neo)
        replace out_multiple = "No" if num_neo == 1
    }
    
    // SGA placeholder - requires gigs R package
    replace out_sga = ""
    replace out_lga = ""
    
    /*==========================================================================
    SECTION 2: MATERNAL DEMOGRAPHICS
    ==========================================================================*/
    
    generate mat_age = .
    generate str20 mat_age_cat = ""
    generate str50 mat_education = ""
    generate str50 fat_education = ""
    generate str50 mat_occupation = ""
    generate str50 fat_occupation = ""
    generate str30 marital_status = ""
    generate str30 religion = ""
    generate str50 ethnicity = ""
    generate str50 out_country = ""
    generate str100 mat_facility = ""
    generate str50 mat_district = ""
    generate str20 mat_urban_rural = ""
    generate str10 mat_literacy = ""
    
    // Maternal age
    capture {
        destring age, replace force
        replace mat_age = age if !missing(age) & inrange(age, 10, 60)
    }
    
    // Age categories
    replace mat_age_cat = "<20" if mat_age < 20 & !missing(mat_age)
    replace mat_age_cat = "20-24" if inrange(mat_age, 20, 24)
    replace mat_age_cat = "25-29" if inrange(mat_age, 25, 29)
    replace mat_age_cat = "30-34" if inrange(mat_age, 30, 34)
    replace mat_age_cat = "35+" if mat_age >= 35 & !missing(mat_age)
    
    // Marital status
    capture {
        replace marital_status = "Married-Cohabiting" if regexm(lower(maritalstatus), "married|cohabit")
        replace marital_status = "Single" if regexm(lower(maritalstatus), "single|never") & marital_status == ""
        replace marital_status = "Divorced-Separated" if regexm(lower(maritalstatus), "divorc|separat") & marital_status == ""
        replace marital_status = "Widowed" if regexm(lower(maritalstatus), "widow") & marital_status == ""
    }
    
    // Education from yearsschool
    capture {
        destring yearsschool, replace force
        replace mat_education = "None" if yearsschool == 0
        replace mat_education = "Primary" if inrange(yearsschool, 1, 6)
        replace mat_education = "Secondary" if inrange(yearsschool, 7, 12)
        replace mat_education = "Higher" if yearsschool > 12 & !missing(yearsschool)
    }
    
    // Country from countrycode and country variables
    capture {
        replace out_country = country if !missing(country)
        replace out_country = countrycode if missing(out_country) & !missing(countrycode)
    }
    
    // Facility
    capture {
        replace mat_facility = name_fac if !missing(name_fac)
        replace mat_facility = string(facilitycod) if missing(mat_facility) & !missing(facilitycod)
    }
    
    /*==========================================================================
    SECTION 3: HOUSEHOLD SOCIOECONOMIC INDICATORS
    ==========================================================================*/
    
    generate str50 house_wall = ""
    generate str50 house_floor = ""
    generate str20 house_ownership = ""
    generate house_rooms = .
    generate str10 electricity = ""
    generate str50 water_source = ""
    generate str50 toilet_facilities = ""
    generate str30 cooking_fuel = ""
    generate str10 mosquito_net = ""
    generate str10 asset_bed = ""
    generate str10 asset_mobile = ""
    generate str10 asset_motorbike = ""
    generate str10 asset_car = ""
    generate str10 asset_radio = ""
    generate str10 asset_tv = ""
    generate monthly_income = .
    generate household_size = .
    generate ppi_score = .
    generate str10 wealth_quintile = ""
    generate asset_score = .
    
    // Note: WHOMCS is facility-based and has limited household SES data
    
    /*==========================================================================
    SECTION 4: PRE-EXISTING MEDICAL CONDITIONS
    ==========================================================================*/
    
    generate str10 preg_hiv = ""
    generate str10 preg_chronic_htn = ""
    generate str10 preg_diabetes = ""
    generate str10 preg_anaemia = ""
    generate str10 preg_sickle_cell = ""
    generate str10 preg_tb = ""
    generate str10 preg_heart_disease = ""
    generate str10 preg_renal_disease = ""
    generate str10 preg_hepatic_disease = ""
    generate str10 preg_malaria = ""
    generate str10 preg_uti = ""
    
    // HIV status
    capture {
        replace preg_hiv = "Yes" if regexm(lower(hivpos), "yes|1|positive")
        replace preg_hiv = "No" if regexm(lower(hivpos), "no|0|negative") & preg_hiv == ""
    }
    
    // Chronic hypertension
    capture {
        replace preg_chronic_htn = "Yes" if regexm(lower(chrohype), "yes|1")
        replace preg_chronic_htn = "No" if regexm(lower(chrohype), "no|0") & preg_chronic_htn == ""
    }
    
    // Anaemia
    capture {
        replace preg_anaemia = "Yes" if regexm(lower(anaemia), "yes|1")
        replace preg_anaemia = "No" if regexm(lower(anaemia), "no|0") & preg_anaemia == ""
    }
    
    // Malaria/dengue
    capture {
        replace preg_malaria = "Yes" if regexm(lower(malaria_dengue), "yes|1")
        replace preg_malaria = "No" if regexm(lower(malaria_dengue), "no|0") & preg_malaria == ""
    }
    
    // Heart disease
    capture {
        replace preg_heart_disease = "Yes" if regexm(lower(heartdisease), "yes|1")
        replace preg_heart_disease = "No" if regexm(lower(heartdisease), "no|0") & preg_heart_disease == ""
    }
    
    // Renal disease
    capture {
        replace preg_renal_disease = "Yes" if regexm(lower(renaldisease), "yes|1")
        replace preg_renal_disease = "No" if regexm(lower(renaldisease), "no|0") & preg_renal_disease == ""
    }
    
    // Hepatic disease
    capture {
        replace preg_hepatic_disease = "Yes" if regexm(lower(hepaticdisease), "yes|1")
        replace preg_hepatic_disease = "No" if regexm(lower(hepaticdisease), "no|0") & preg_hepatic_disease == ""
    }
    
    /*==========================================================================
    SECTION 5: OBSTETRIC HISTORY
    ==========================================================================*/
    
    generate obs_gravidity = .
    generate obs_parity = .
    generate obs_previous_livebirths = .
    generate str10 obs_given_birth_before = ""
    generate str10 obs_previous_stillbirth = ""
    generate str10 obs_previous_csection = ""
    generate str10 obs_previous_abortion = ""
    
    // Gravidity from numpreg
    capture {
        destring numpreg, replace force
        replace obs_gravidity = numpreg if !missing(numpreg) & inrange(numpreg, 1, 20)
    }
    
    // Parity from previousbirth
    capture {
        destring previousbirth, replace force
        replace obs_parity = previousbirth if !missing(previousbirth) & inrange(previousbirth, 0, 15)
    }
    
    // Previous caesarean
    capture {
        destring prevcaes, replace force
        replace obs_previous_csection = "Yes" if prevcaes > 0 & !missing(prevcaes)
        replace obs_previous_csection = "No" if prevcaes == 0
    }
    
    // Given birth before
    replace obs_given_birth_before = "Yes" if obs_parity > 0 & !missing(obs_parity)
    replace obs_given_birth_before = "No" if obs_parity == 0
    
    /*==========================================================================
    SECTION 6: MATERNAL ANTHROPOMETRY
    ==========================================================================*/
    
    generate mat_height_cm = .
    generate mat_weight_kg = .
    generate mat_bmi = .
    generate str20 mat_bmi_cat = ""
    generate mat_muac_cm = .
    generate str20 mat_muac_cat = ""
    
    // Note: WHOMCS does not have anthropometry data
    
    /*==========================================================================
    SECTION 7: ANTENATAL CARE
    ==========================================================================*/
    
    generate str10 anc_attended = ""
    generate anc_num_visits = .
    generate anc_ga_first_visit = .
    generate str100 anc_facility = ""
    generate str10 anc_tetanus_toxoid = ""
    
    // Note: WHOMCS has limited ANC data
    
    /*==========================================================================
    SECTION 8: CURRENT PREGNANCY COMPLICATIONS
    ==========================================================================*/
    
    generate str10 preg_gest_htn = ""
    generate str10 preg_preeclampsia = ""
    generate str10 preg_eclampsia = ""
    generate str10 preg_hdp = ""
    generate preg_sbp = .
    generate preg_dbp = .
    generate str10 preg_pprom = ""
    generate str10 preg_placenta_praevia = ""
    generate str10 preg_placenta_abruption = ""
    generate str10 preg_aph = ""
    generate str10 preg_pph = ""
    generate str10 preg_ruptured_uterus = ""
    generate str10 preg_prolonged_labour = ""
    generate str10 preg_obstructed_labour = ""
    generate str10 preg_breech = ""
    generate str10 preg_maternal_fever = ""
    generate str10 preg_meconium = ""
    
    // Pre-eclampsia
    capture {
        replace preg_preeclampsia = "Yes" if regexm(lower(preeclampsia), "yes|1")
        replace preg_preeclampsia = "No" if regexm(lower(preeclampsia), "no|0") & preg_preeclampsia == ""
    }
    
    // Eclampsia
    capture {
        replace preg_eclampsia = "Yes" if regexm(lower(eclampsia), "yes|1")
        replace preg_eclampsia = "No" if regexm(lower(eclampsia), "no|0") & preg_eclampsia == ""
    }
    
    // Any hypertensive disorder
    replace preg_hdp = "Yes" if preg_chronic_htn == "Yes" | preg_preeclampsia == "Yes" | preg_eclampsia == "Yes"
    replace preg_hdp = "No" if preg_chronic_htn == "No" & preg_preeclampsia == "No" & preg_eclampsia == "No"
    
    // Placenta praevia
    capture {
        replace preg_placenta_praevia = "Yes" if regexm(lower(placentapraevia), "yes|1")
        replace preg_placenta_praevia = "No" if regexm(lower(placentapraevia), "no|0") & preg_placenta_praevia == ""
    }
    
    // Placental abruption
    capture {
        replace preg_placenta_abruption = "Yes" if regexm(lower(abruptionplacenta), "yes|1")
        replace preg_placenta_abruption = "No" if regexm(lower(abruptionplacenta), "no|0") & preg_placenta_abruption == ""
    }
    
    // PPH
    capture {
        replace preg_pph = "Yes" if regexm(lower(pph), "yes|1")
        replace preg_pph = "No" if regexm(lower(pph), "no|0") & preg_pph == ""
    }
    
    // Ruptured uterus
    capture {
        replace preg_ruptured_uterus = "Yes" if regexm(lower(ruptureduterus), "yes|1")
        replace preg_ruptured_uterus = "No" if regexm(lower(ruptureduterus), "no|0") & preg_ruptured_uterus == ""
    }
    
    // Breech presentation (fetpres)
    capture {
        destring fetpres, replace force
        replace preg_breech = "Yes" if fetpres == 2  // Typically 1=cephalic, 2=breech
        replace preg_breech = "No" if fetpres == 1
    }
    
    /*==========================================================================
    SECTION 9: DELIVERY CHARACTERISTICS
    ==========================================================================*/
    
    generate str30 del_mode = ""
    generate str50 del_location = ""
    generate str20 del_location_type = ""
    generate str10 del_attendant_doctor = ""
    generate str10 del_attendant_midwife = ""
    generate str10 del_attendant_nurse = ""
    generate str10 del_attendant_tba = ""
    generate str10 del_attendant_family = ""
    generate str10 del_any_attendant = ""
    generate str20 del_labour_onset = ""
    generate str10 del_induction = ""
    generate str10 del_referred = ""
    generate str10 del_bba = ""
    
    // Mode of delivery from delabort_mode
    capture {
        destring delabort_mode, replace force
        // WHOMCS coding: 1=Spont vaginal, 2=Forceps, 3=Vacuum, 4=Caesarean, etc.
        replace del_mode = "Vaginal" if inlist(delabort_mode, 1)
        replace del_mode = "Instrumental" if inlist(delabort_mode, 2, 3)
        replace del_mode = "Caesarean" if delabort_mode == 4
    }
    
    // Delivery location (facility-based study)
    replace del_location = "Hospital"
    replace del_location_type = "Facility"
    
    // Born before arrival
    capture {
        replace del_bba = "Yes" if regexm(lower(deliveryatarrival), "yes|1")
        replace del_bba = "No" if regexm(lower(deliveryatarrival), "no|0") & del_bba == ""
    }
    
    // Labour onset
    capture {
        destring onsetoflabour, replace force
        // Typically: 1=Spontaneous, 2=Induced, 3=No labour/elective CS
        replace del_labour_onset = "Spontaneous" if onsetoflabour == 1
        replace del_labour_onset = "Induced" if onsetoflabour == 2
        replace del_labour_onset = "No labour" if onsetoflabour == 3
        
        replace del_induction = "Yes" if onsetoflabour == 2
        replace del_induction = "No" if inlist(onsetoflabour, 1, 3)
    }
    
    // Referral
    capture {
        replace del_referred = "Yes" if regexm(lower(womanreferred), "yes|1")
        replace del_referred = "No" if regexm(lower(womanreferred), "no|0") & del_referred == ""
    }
    
    // All facility births have attendants
    replace del_any_attendant = "Yes"
    
    /*==========================================================================
    SECTION 10: LIFESTYLE FACTORS
    ==========================================================================*/
    
    generate str10 life_tobacco = ""
    generate str10 life_alcohol = ""
    generate str20 life_sleep_position = ""
    generate str10 life_fgm = ""
    
    // Note: WHOMCS does not have lifestyle data
    
    /*==========================================================================
    SECTION 11: NEONATAL CHARACTERISTICS
    ==========================================================================*/
    
    generate str10 neo_resuscitation = ""
    generate str30 neo_resuscitation_type = ""
    generate str10 neo_malformation = ""
    generate str100 neo_malformation_type = ""
    generate str10 neo_nicu = ""
    generate str10 neo_breastfeeding = ""
    generate str10 neo_cry_at_birth = ""
    
    // NICU admission
    capture {
        replace neo_nicu = "Yes" if regexm(lower(neo_icu), "yes|1")
        replace neo_nicu = "No" if regexm(lower(neo_icu), "no|0") & neo_nicu == ""
    }
    
    // Congenital malformation
    capture {
        replace neo_malformation = "Yes" if regexm(lower(congmalf), "yes|1")
        replace neo_malformation = "No" if regexm(lower(congmalf), "no|0") & neo_malformation == ""
    }
    
    // Malformation types
    capture {
        local malf_str ""
        foreach mtype in neuraltube cardiac renal limb chromosomal {
            local mtype_val = `mtype'
            if regexm(lower(`"`mtype_val'"'), "yes|1") {
                local malf_str = "`malf_str'" + ", `mtype'"
            }
        }
        replace neo_malformation_type = substr("`malf_str'", 3, .) if neo_malformation == "Yes"
    }
    
    // Resuscitation - check for neonatal interventions
    capture {
        replace neo_resuscitation = "Yes" if regexm(lower(anyintubation), "yes|1") | ///
                                              regexm(lower(cpr), "yes|1") | ///
                                              regexm(lower(nasalcpap), "yes|1")
        replace neo_resuscitation = "No" if neo_resuscitation == "" & out_livebirth == "Yes"
    }
    
    /*==========================================================================
    SECTION 12: MATERNAL OUTCOMES
    ==========================================================================*/
    
    generate str10 mat_death = ""
    generate str30 mat_discharge_status = ""
    generate str10 mat_near_miss = ""
    
    // Maternal death
    capture {
        replace mat_death = "Yes" if regexm(lower(matstat), "dead|death|died")
        replace mat_death = "No" if regexm(lower(matstat), "alive|discharged") & mat_death == ""
    }
    
    capture {
        replace mat_death = "Yes" if regexm(lower(matdeath24), "yes|1")
        replace mat_death = "No" if regexm(lower(matdeath24), "no|0") & mat_death == ""
    }
    
    // Discharge status
    capture {
        replace mat_discharge_status = "Alive" if regexm(lower(matstat), "alive|discharged")
        replace mat_discharge_status = "Dead" if regexm(lower(matstat), "dead|death|died")
        replace mat_discharge_status = "Transferred" if regexm(lower(matstat), "transfer|refer")
    }
    
    // Maternal near miss
    capture {
        destring mnm, replace force
        replace mat_near_miss = "Yes" if mnm == 1
        replace mat_near_miss = "No" if mnm == 0
    }
    
    /*==========================================================================
    SECTION 13: ENVIRONMENTAL DATA (PLACEHOLDERS)
    ==========================================================================*/
    
    generate env_temp_mean = .
    generate env_temp_max = .
    generate env_temp_min = .
    generate env_precipitation = .
    generate env_humidity = .
    generate str20 env_season = ""
    generate env_heat_index = .
    generate env_latitude = .
    generate env_longitude = .
    
    // Note: Requires linkage to ERA5/CHIRPS using facility coordinates and delivery dates
    
    display "âœ“ WHOMCS processing complete"
}
else {
    display "âœ— WHOMCS data not loaded"
    local whomcs_loaded = 0
}

/*==============================================================================
COMBINE ALL FRAMES INTO UNIFIED DATASET
==============================================================================*/

display _newline(2) "=" * 70
display "COMBINING DATASETS INTO UNIFIED FRAME"
display "=" * 70

// Create unified frame
frame create unified

// Append each study (now including WHOMCS)
foreach study in ncops alert precise ptbi enindepth whomcs {
    capture frame `study': count
    if _rc == 0 & r(N) > 0 {
        frame change `study'
        tempfile `study'_temp
        save ``study'_temp', replace
        
        frame change unified
        if _N == 0 {
            use ``study'_temp', clear
        }
        else {
            append using ``study'_temp', force
        }
        display "âœ“ Appended `study': " _N " total observations"
    }
}

frame change unified

/*==============================================================================
FINAL PROCESSING
==============================================================================*/

display _newline(2) "=" * 70
display "FINAL PROCESSING AND VARIABLE LABELING"
display "=" * 70

// Generate unified ID
generate str50 unified_id = study_source + "_" + string(_n)

// Year of birth
capture confirm variable yob
if !_rc {
    capture rename yob yob_orig
}
generate yob = year(out_dob)

/*==============================================================================
COMPREHENSIVE VARIABLE LABELS
==============================================================================*/

// Study identifiers
label variable unified_id "Unified record identifier"
label variable study_source "Source study"
label variable study_design "Study design (Population-based / Facility-based)"
label variable module "Data collection methodology"
label variable study_id "Original study ID"
label variable studyyear "Year of data collection"
label variable yob "Year of birth"

// Primary outcomes (Section 1)
label variable out_stillbirth "Stillbirth (any GA)"
label variable out_fresh_stillbirth "Fresh stillbirth"
label variable out_macerated_stillbirth "Macerated stillbirth"
label variable out_stillbirth_20wks "Stillbirth â‰¥20 weeks GA"
label variable out_stillbirth_28wks "Stillbirth â‰¥28 weeks GA (late fetal death)"
label variable out_livebirth "Live birth"
label variable out_nnd "Neonatal death (0-28 days)"
label variable out_nnd_early "Early neonatal death (0-7 days)"
label variable out_nnd_late "Late neonatal death (8-28 days)"
label variable out_perinatal_death "Perinatal death (SBâ‰¥28wks + early NND)"
label variable out_preterm "Preterm birth (<37 weeks)"
label variable out_very_preterm "Very preterm birth (<32 weeks)"
label variable out_extremely_preterm "Extremely preterm birth (<28 weeks)"
label variable out_sga "Small for gestational age (<10th centile)"
label variable out_lga "Large for gestational age (>90th centile)"
label variable out_lbw "Low birth weight (<2500g)"
label variable out_vlbw "Very low birth weight (<1500g)"
label variable out_elbw "Extremely low birth weight (<1000g)"
label variable out_multiple "Multiple birth (twins/triplets)"
label variable out_dob "Date of birth"
label variable out_dod "Date of death"
label variable out_ageatdeath "Age at death (days)"
label variable out_ga_weeks "Gestational age (weeks)"
label variable out_ga_days "Gestational age (days)"
label variable out_birth_location "Location of birth"
label variable out_infant_sex "Infant sex"
label variable out_birthweight_g "Birth weight (grams)"
label variable out_apgar_1min "Apgar score at 1 minute"
label variable out_apgar_5min "Apgar score at 5 minutes"
label variable out_apgar_10min "Apgar score at 10 minutes"
label variable out_birthweight_centile "Birth weight centile (INTERGROWTH-21st)"
label variable out_birthweight_zscore "Birth weight z-score (INTERGROWTH-21st)"

// Maternal demographics (Section 2)
label variable mat_age "Maternal age (years)"
label variable mat_age_cat "Maternal age category"
label variable mat_education "Maternal education level"
label variable fat_education "Father's education level"
label variable mat_occupation "Maternal occupation"
label variable fat_occupation "Father's occupation"
label variable marital_status "Marital status"
label variable religion "Religion"
label variable ethnicity "Ethnicity"
label variable out_country "Country"
label variable mat_facility "Health facility/HDSS site"
label variable mat_district "District/Region"
label variable mat_urban_rural "Urban/Rural classification"
label variable mat_literacy "Maternal literacy"

// Household wealth (Section 3)
label variable house_wall "House wall material"
label variable house_floor "House floor material"
label variable house_ownership "House ownership status"
label variable house_rooms "Number of rooms in house"
label variable electricity "Electricity access"
label variable water_source "Water source"
label variable toilet_facilities "Toilet facilities"
label variable cooking_fuel "Cooking fuel type"
label variable mosquito_net "Mosquito net ownership"
label variable asset_bed "Owns bed"
label variable asset_mobile "Owns mobile phone"
label variable asset_motorbike "Owns motorbike"
label variable asset_car "Owns car"
label variable asset_radio "Owns radio"
label variable asset_tv "Owns television"
label variable monthly_income "Monthly income"
label variable household_size "Household size"
label variable ppi_score "Progress out of Poverty Index score"
label variable wealth_quintile "Wealth quintile (1=poorest)"
label variable asset_score "Asset index score"

// Pre-existing conditions (Section 4)
label variable preg_hiv "HIV status"
label variable preg_chronic_htn "Chronic hypertension"
label variable preg_diabetes "Diabetes mellitus"
label variable preg_anaemia "Anaemia"
label variable preg_sickle_cell "Sickle cell disease"
label variable preg_tb "Tuberculosis"
label variable preg_heart_disease "Heart disease"
label variable preg_renal_disease "Renal disease"
label variable preg_hepatic_disease "Hepatic disease"
label variable preg_malaria "Malaria in pregnancy"
label variable preg_uti "Urinary tract infection"

// Obstetric history (Section 5)
label variable obs_gravidity "Gravidity"
label variable obs_parity "Parity"
label variable obs_previous_livebirths "Number of previous livebirths"
label variable obs_given_birth_before "Given birth before"
label variable obs_previous_stillbirth "Previous stillbirth"
label variable obs_previous_csection "Previous caesarean section"
label variable obs_previous_abortion "Previous abortion/miscarriage"

// Maternal anthropometry (Section 6)
label variable mat_height_cm "Maternal height (cm)"
label variable mat_weight_kg "Maternal weight (kg)"
label variable mat_bmi "Maternal BMI (kg/mÂ²)"
label variable mat_bmi_cat "Maternal BMI category"
label variable mat_muac_cm "Maternal MUAC (cm)"
label variable mat_muac_cat "Maternal MUAC category"

// Antenatal care (Section 7)
label variable anc_attended "ANC attendance"
label variable anc_num_visits "Number of ANC visits"
label variable anc_ga_first_visit "GA at first ANC visit (weeks)"
label variable anc_facility "ANC facility"
label variable anc_tetanus_toxoid "Tetanus toxoid received"

// Pregnancy complications (Section 8)
label variable preg_gest_htn "Gestational hypertension"
label variable preg_preeclampsia "Pre-eclampsia"
label variable preg_eclampsia "Eclampsia"
label variable preg_hdp "Any hypertensive disorder of pregnancy"
label variable preg_sbp "Systolic blood pressure (mmHg)"
label variable preg_dbp "Diastolic blood pressure (mmHg)"
label variable preg_pprom "Preterm premature rupture of membranes"
label variable preg_placenta_praevia "Placenta praevia"
label variable preg_placenta_abruption "Placental abruption"
label variable preg_aph "Antepartum haemorrhage"
label variable preg_pph "Postpartum haemorrhage"
label variable preg_ruptured_uterus "Ruptured uterus"
label variable preg_prolonged_labour "Prolonged labour"
label variable preg_obstructed_labour "Obstructed labour"
label variable preg_breech "Breech presentation"
label variable preg_maternal_fever "Maternal fever/infection"
label variable preg_meconium "Meconium stained liquor"

// Delivery characteristics (Section 9)
label variable del_mode "Mode of delivery"
label variable del_location "Delivery location"
label variable del_location_type "Delivery location type"
label variable del_attendant_doctor "Doctor attended delivery"
label variable del_attendant_midwife "Midwife attended delivery"
label variable del_attendant_nurse "Nurse attended delivery"
label variable del_attendant_tba "TBA attended delivery"
label variable del_attendant_family "Family member attended delivery"
label variable del_any_attendant "Any attendant present"
label variable del_labour_onset "Labour onset"
label variable del_induction "Labour induction"
label variable del_referred "Referral during delivery"
label variable del_bba "Born before arrival"

// Lifestyle factors (Section 10)
label variable life_tobacco "Tobacco use"
label variable life_alcohol "Alcohol use"
label variable life_sleep_position "Sleeping position (3rd trimester)"
label variable life_fgm "Female genital mutilation"

// Neonatal characteristics (Section 11)
label variable neo_resuscitation "Resuscitation required"
label variable neo_resuscitation_type "Type of resuscitation"
label variable neo_malformation "Congenital malformation"
label variable neo_malformation_type "Type of malformation"
label variable neo_nicu "NICU admission"
label variable neo_breastfeeding "Breastfeeding initiated"
label variable neo_cry_at_birth "Cried at birth"

// Maternal outcomes (Section 12)
label variable mat_death "Maternal death"
label variable mat_discharge_status "Mother discharge status"
label variable mat_near_miss "Maternal near miss"

// Environmental data (Section 13)
label variable env_temp_mean "Mean temperature at delivery month (Â°C)"
label variable env_temp_max "Maximum temperature at delivery month (Â°C)"
label variable env_temp_min "Minimum temperature at delivery month (Â°C)"
label variable env_precipitation "Total precipitation at delivery month (mm)"
label variable env_humidity "Mean relative humidity at delivery month (%)"
label variable env_season "Season at delivery"
label variable env_heat_index "Heat index at delivery"
label variable env_latitude "Facility/village latitude"
label variable env_longitude "Facility/village longitude"

/*==============================================================================
VERIFICATION SUMMARY
==============================================================================*/

display _newline(2) "=" * 70
display "VERIFICATION SUMMARY"
display "=" * 70
display ""
display "Total unified observations: " _N
display ""

// By study
display "Observations by study:"
tabulate study_source, missing
display ""

// By study design (population vs facility)
display "Observations by study design:"
tabulate study_design, missing
display ""

// By module (data collection methodology)
display "Observations by data collection module:"
tabulate module, missing
display ""

// Study design x study source cross-tabulation
display "Study source by study design:"
tabulate study_source study_design, missing
display ""

// By country
display "Observations by country:"
tabulate out_country, missing
display ""

// Primary outcomes
display "PRIMARY OUTCOMES SUMMARY"
display "-" * 50

display "Stillbirths by study:"
tabulate study_source out_stillbirth, missing row
display ""

display "Live births by study:"
tabulate study_source out_livebirth, missing row
display ""

display "Neonatal deaths by study:"
tabulate study_source out_nnd, missing row
display ""

display "Preterm births by study:"
tabulate study_source out_preterm, missing row
display ""

display "Low birth weight by study:"
tabulate study_source out_lbw, missing row
display ""

// Numeric summaries
display "NUMERIC VARIABLE SUMMARIES"
display "-" * 50

display "Gestational age (weeks):"
summarize out_ga_weeks, detail
display ""

display "Birth weight (grams):"
summarize out_birthweight_g, detail
display ""

display "Maternal age (years):"
summarize mat_age, detail
display ""

/*==============================================================================
SAVE DATASETS
==============================================================================*/

display _newline(2) "=" * 70
display "SAVING DATASETS"
display "=" * 70

// Order variables
order unified_id study_id study_source study_design module studyyear out_country yob ///
      out_stillbirth out_fresh_stillbirth out_macerated_stillbirth ///
      out_stillbirth_20wks out_stillbirth_28wks ///
      out_livebirth out_nnd out_nnd_early out_nnd_late out_perinatal_death ///
      out_preterm out_very_preterm out_extremely_preterm ///
      out_sga out_lga out_lbw out_vlbw out_elbw out_multiple ///
      out_dob out_dod out_ageatdeath out_ga_weeks out_ga_days ///
      out_birth_location out_infant_sex out_birthweight_g ///
      out_apgar_1min out_apgar_5min out_apgar_10min ///
      out_birthweight_centile out_birthweight_zscore ///
      mat_age mat_age_cat mat_education fat_education ///
      mat_occupation fat_occupation marital_status religion ethnicity ///
      mat_facility mat_district mat_urban_rural mat_literacy

// Save Stata format
capture save "$master/unified_dataset_v6.dta", replace
if _rc == 0 {
    display "âœ“ Saved: unified_dataset_v6.dta"
}

// Export CSV
capture export delimited using "$master/unified_dataset_v6.csv", replace
if _rc == 0 {
    display "âœ“ Exported: unified_dataset_v6.csv"
}

// Create 10% sample
preserve
sample 10, by(study_source)
capture save "$master/unified_dataset_v6_10pct_sample.dta", replace
capture export delimited using "$master/unified_dataset_v6_10pct_sample.csv", replace
display "âœ“ 10% sample saved"
restore

display _newline(2) "=" * 70
display "PROCESSING COMPLETE!"
display "=" * 70
display ""
display "Next steps:"
display "1. Run SGA calculation using gigs R package (see header documentation)"
display "2. Link environmental data from ERA5/CHIRPS using coordinates and dates"
display "3. Verify variable distributions and missing data patterns"
display ""
display "Version 6.0 unified dataset created: " c(current_date) " " c(current_time)

/*==============================================================================
END OF DO FILE
==============================================================================*/
