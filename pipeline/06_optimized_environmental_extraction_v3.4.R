# ============================================================================
# OPTIMIZED ENVIRONMENTAL EXTRACTION v3.4
# ============================================================================
# PURPOSE:
#   Re-extract all environmental variables at real DHS cluster-level GPS
#   coordinates (~56K unique pairs) instead of country centroids.
#   Optimized: extract per unique coordinate, then join back to full dataset.
#   This reduces ERA5 extraction from ~10 hours to ~30 minutes.
#
# INPUT:
#   output/merged_unified_dataset_v10.16.rds
#   data/srtm/srtm_elevation.tif, srtm_slope.tif
#   data/era5/data_stream-moda_stepType-avgua.nc (t2m, d2m)
#   data/era5/era5_monthly_africa.nc (tp)
#   data/pm25/V6GL02.04.CNNPM25.0p10.GL.YYYYMM-YYYYMM.nc
#   data/PRECISE_dataset.dta (optional, for GPS)
#
# OUTPUT:
#   output/environmental/environmental_linkage_v3.4.rds
#   output/environmental/environmental_linkage_v3.4.csv
# ============================================================================

cat("================================================================\n")
cat("  OPTIMIZED ENVIRONMENTAL EXTRACTION v3.4\n")
cat("================================================================\n\n")

suppressPackageStartupMessages({
  library(tidyverse)
  library(terra)
  library(sf)
  library(lubridate)
  library(ncdf4)
  library(haven)
  library(glue)
})

VERSION <- "3.4"

# Set to your unified_dataset_pipeline directory, or run from project root.
base_path <- getwd()
# base_path <- "C:/Users/YOUR_USERNAME/path/to/unified_dataset_pipeline"

# Configuration
FILE_UNIFIED    <- "output/merged_unified_dataset_v10.16.rds"
FILE_PRECISE_RAW <- "data/PRECISE_dataset.dta"
FILE_ERA5_TEMP  <- "data/era5/data_stream-moda_stepType-avgua.nc"
FILE_ERA5_PRECIP <- "data/era5/era5_monthly_africa.nc"
DIR_SRTM <- "data/srtm"
DIR_PM25 <- "data/pm25"
DIR_OUTPUT <- "output/environmental"
OUTPUT_FILE <- "environmental_linkage_v3.4"

dir.create(DIR_OUTPUT, recursive = TRUE, showWarnings = FALSE)

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================
get_col_chr <- function(df, col_name) {
  if (col_name %in% names(df)) return(as.character(df[[col_name]]))
  return(rep(NA_character_, nrow(df)))
}

get_col_num <- function(df, col_name) {
  if (col_name %in% names(df)) return(suppressWarnings(as.numeric(df[[col_name]])))
  return(rep(NA_real_, nrow(df)))
}

get_col_date <- function(df, col_name) {
  if (col_name %in% names(df)) {
    val <- df[[col_name]]
    if (inherits(val, "Date")) return(val)
    if (inherits(val, "POSIXct")) return(as.Date(val))
    return(suppressWarnings(as.Date(val)))
  }
  return(rep(as.Date(NA), nrow(df)))
}

# ============================================================================
# PHASE 1: LOAD UNIFIED DATASET
# ============================================================================
cat("PHASE 1: Loading unified dataset...\n")
unified_dataset <- readRDS(FILE_UNIFIED)
cat(glue("  Loaded: {format(nrow(unified_dataset), big.mark=',')} rows x {ncol(unified_dataset)} cols\n"))
cat(glue("  Studies: {paste(unique(unified_dataset$study_source), collapse=', ')}\n\n"))

# ============================================================================
# PHASE 2: GEOGRAPHIC REFERENCE DATA (same as v3.3)
# ============================================================================
cat("PHASE 2: Loading geographic reference data...\n")

facility_geocodes <- tribble(
  ~study_source, ~facility_clean, ~latitude, ~longitude, ~accuracy_level,
  "NCOPS", "mulago national referral hospital", 0.3370, 32.5766, "facility",
  "NCOPS", "kawempe national referral hospital", 0.3645, 32.5506, "facility",
  "NCOPS", "nsambya hospital", 0.3026, 32.5848, "facility",
  "NCOPS", "jinja regional referral hospital", 0.4244, 33.2041, "facility",
  "NCOPS", "mbale regional referral hospital", 1.0806, 34.1750, "facility",
  "NCOPS", "mbarara regional referral hospital", -0.6127, 30.6464, "facility",
  "NCOPS", "gulu regional referral hospital", 2.7691, 32.2989, "facility",
  "NCOPS", "hoima regional referral hospital", 1.4334, 31.3523, "facility",
  "NCOPS", "soroti regional referral hospital", 1.7111, 33.6097, "facility",
  "NCOPS", "lira regional referral hospital", 2.2494, 32.5434, "facility",
  "NCOPS", "fort portal regional referral hospital", 0.6710, 30.2750, "facility",
  "NCOPS", "arua regional referral hospital", 3.0293, 30.9067, "facility",
  "NCOPS", "kabale regional referral hospital", -1.2503, 29.9881, "facility",
  "NCOPS", "moroto regional referral hospital", 2.5288, 34.6613, "facility",
  "PTBi", "mulago national referral hospital", 0.3370, 32.5766, "facility",
  "PTBi", "kawempe national referral hospital", 0.3645, 32.5506, "facility",
  "PTBi", "jinja regional referral hospital", 0.4244, 33.2041, "facility",
  "PTBi", "masaka regional referral hospital", -0.3372, 31.7136, "facility",
  "ALERT", "jinja regional hospital", 0.4244, 33.2041, "facility",
  "ALERT", "1. jinja regional hospital", 0.4244, 33.2041, "facility",
  "ALERT", "ndanda hospital", -10.6500, 39.6167, "facility",
  "ALERT", "3.1 ndanda", -10.6500, 39.6167, "facility",
  "ALERT", "kamuzu central hospital", -13.9833, 33.7833, "facility",
  "PRECISE", "farafenni", 13.5667, -15.6000, "district",
  "PRECISE", "mariakani", -3.8591, 39.4783, "facility",
  "PRECISE", "rabai", -3.9333, 39.5500, "facility",
  "PRECISE", "manhica", -25.4033, 32.8072, "district",
  "PRECISE", "xinavane", -25.0500, 32.8000, "facility",
  "EN-INDEPTH", "matlab", 23.3500, 90.7333, "district",
  "EN-INDEPTH", "bandim", 11.8500, -15.6000, "district",
  "EN-INDEPTH", "dabat", 13.0333, 37.7500, "district",
  "EN-INDEPTH", "kintampo", 8.0500, -1.7333, "district",
  "EN-INDEPTH", "navrongo", 10.8833, -1.0833, "district",
  "EN-INDEPTH", "iganga/mayuge", 0.6500, 33.5000, "district",
  "EN-INDEPTH", "iganga", 0.6500, 33.5000, "district"
)

country_centroids <- tribble(
  ~country_clean, ~latitude, ~longitude,
  "uganda", 1.3733, 32.2903, "kenya", -0.0236, 37.9062,
  "tanzania", -6.3690, 34.8888, "malawi", -13.2543, 34.3015,
  "mozambique", -18.6657, 35.5296, "the gambia", 13.4432, -15.3101,
  "gambia", 13.4432, -15.3101, "ghana", 7.9465, -1.0232,
  "ethiopia", 9.1450, 40.4897, "guinea-bissau", 11.8037, -15.1804,
  "angola", -11.2027, 17.8739, "niger", 17.6078, 8.0817,
  "nigeria", 9.0820, 7.4898, "democratic republic of the congo", -4.0383, 21.7587,
  "benin", 9.3077, 2.3158, "burkina faso", 12.2383, -1.5616,
  "burundi", -3.3731, 29.9189, "cameroon", 7.3697, 12.3547,
  "cape verde", 16.5388, -23.0418, "central african republic", 6.6111, 20.9394,
  "chad", 15.4542, 18.7322, "comoros", -11.6455, 43.3333,
  "congo", -0.2280, 15.8277, "congo (brazzaville)", -0.2280, 15.8277,
  "cote d'ivoire", 7.5400, -5.5471, "ivory coast", 7.5400, -5.5471,
  "eritrea", 15.1794, 39.7823, "eswatini", -26.5225, 31.4659,
  "swaziland", -26.5225, 31.4659, "gabon", -0.8037, 11.6094,
  "guinea", 9.9456, -9.6966, "lesotho", -29.6100, 28.2336,
  "liberia", 6.4281, -9.4295, "madagascar", -18.7669, 46.8691,
  "mali", 17.5707, -3.9962, "mauritania", 21.0079, -10.9408,
  "namibia", -22.9576, 18.4904, "rwanda", -1.9403, 29.8739,
  "sao tome and principe", 0.1864, 6.6131, "senegal", 14.4974, -14.4524,
  "sierra leone", 8.4606, -11.7799, "south africa", -30.5595, 22.9375,
  "sudan", 12.8628, 30.2176, "togo", 8.6195, 0.8248,
  "zambia", -13.1339, 27.8493, "zimbabwe", -19.0154, 29.1549,
  "congo democratic republic", -4.0383, 21.7587,
  "dem rep of the congo", -4.0383, 21.7587,
  "viet nam", 14.0583, 108.2772,
  "afghanistan", 33.9391, 67.7100, "argentina", -38.4161, -63.6167,
  "bangladesh", 23.6850, 90.3563, "brazil", -14.2350, -51.9253,
  "cambodia", 12.5657, 104.9910, "china", 35.8617, 104.1954,
  "ecuador", -1.8312, -78.1834, "india", 20.5937, 78.9629,
  "japan", 36.2048, 138.2529, "jordan", 30.5852, 36.2384,
  "mexico", 23.6345, -102.5528, "nepal", 28.3949, 84.1240,
  "nicaragua", 12.8654, -85.2072, "pakistan", 30.3753, 69.3451,
  "peru", -9.1900, -75.0152, "philippines", 12.8797, 121.7740,
  "thailand", 15.8700, 100.9925, "vietnam", 14.0583, 108.2772,
  "lebanon", 33.8547, 35.8623, "mongolia", 46.8625, 103.8467,
  "occupied palestinian territory", 31.9522, 35.2332,
  "palestine", 31.9522, 35.2332, "paraguay", -23.4425, -58.4438,
  "qatar", 25.3548, 51.1839, "sri lanka", 7.8731, 80.7718
)

cat(glue("  {nrow(facility_geocodes)} facility geocodes, {nrow(country_centroids)} country centroids\n\n"))

# ============================================================================
# PHASE 3: EXTRACT GEOGRAPHIC-TEMPORAL DATA
# ============================================================================
cat("PHASE 3: Extracting geographic-temporal data...\n")

environmental_linkage <- unified_dataset %>%
  transmute(
    unified_id = unified_id,
    study_source = study_source,
    raw_id = raw_id,
    geo_country = get_col_chr(., "mat_country"),
    geo_facility = get_col_chr(., "mat_facility"),
    geo_district = get_col_chr(., "mat_district"),
    geo_latitude = dplyr::coalesce(get_col_num(., "loc_latitude"), get_col_num(., "env_latitude")),
    geo_longitude = dplyr::coalesce(get_col_num(., "loc_longitude"), get_col_num(., "env_longitude")),
    geo_urban_rural = get_col_chr(., "mat_urban_rural"),
    date_delivery = get_col_date(., "out_dob"),
    date_death = get_col_date(., "out_dod"),
    conception_date_unified = get_col_date(., "conception_date"),
    ga_weeks = get_col_num(., "out_ga_weeks"),
    studyyear = get_col_num(., "studyyear"),
    out_stillbirth = get_col_chr(., "out_stillbirth"),
    out_nnd = get_col_chr(., "out_nnd")
  )

rm(unified_dataset)
gc()
cat(glue("  Extracted {format(nrow(environmental_linkage), big.mark=',')} records\n\n"))

# ============================================================================
# PHASE 4: GEOCODING (PRECISE GPS + facility + country centroid cascade)
# ============================================================================
cat("PHASE 4: Geocoding and coordinate enhancement...\n")

# Load PRECISE GPS if available
if (file.exists(FILE_PRECISE_RAW)) {
  tryCatch({
    raw_precise <- read_dta(FILE_PRECISE_RAW)
    id_col <- if ("f2a_participant_id" %in% names(raw_precise)) "f2a_participant_id" else
      if ("f2a_precise_id" %in% names(raw_precise)) "f2a_precise_id" else NULL

    if (!is.null(id_col)) {
      precise_coords <- raw_precise %>%
        select(raw_id = all_of(id_col), any_of(c("villagelat", "villagelong"))) %>%
        rename_with(~case_when(. == "villagelat" ~ "gps_latitude",
                                . == "villagelong" ~ "gps_longitude", TRUE ~ .)) %>%
        filter(!is.na(gps_latitude) & !is.na(gps_longitude)) %>%
        mutate(raw_id = as.character(raw_id),
               gps_latitude = as.numeric(gps_latitude),
               gps_longitude = as.numeric(gps_longitude)) %>%
        filter(gps_latitude >= -90 & gps_latitude <= 90) %>%
        group_by(raw_id) %>% slice_head(n = 1) %>% ungroup()

      environmental_linkage <- environmental_linkage %>%
        mutate(raw_id = as.character(raw_id)) %>%
        left_join(precise_coords, by = "raw_id") %>%
        mutate(
          geo_latitude = case_when(study_source == "PRECISE" & !is.na(gps_latitude) ~ gps_latitude, TRUE ~ geo_latitude),
          geo_longitude = case_when(study_source == "PRECISE" & !is.na(gps_longitude) ~ gps_longitude, TRUE ~ geo_longitude)
        ) %>%
        select(-any_of(c("gps_latitude", "gps_longitude")))
      cat("  Merged PRECISE GPS coordinates\n")
    }
    rm(raw_precise)
  }, error = function(e) cat(glue("  PRECISE GPS: {e$message}\n")))
}

# Match facilities
environmental_linkage <- environmental_linkage %>%
  mutate(facility_clean = tolower(trimws(geo_facility))) %>%
  left_join(facility_geocodes %>% select(study_source, facility_clean, lat_fac = latitude,
                                          lon_fac = longitude, accuracy_fac = accuracy_level),
            by = c("study_source", "facility_clean"), relationship = "many-to-one")

# Match countries
environmental_linkage <- environmental_linkage %>%
  mutate(country_clean = tolower(trimws(geo_country))) %>%
  left_join(country_centroids %>% select(country_clean, lat_ctr = latitude, lon_ctr = longitude),
            by = "country_clean", relationship = "many-to-one")

# Coordinate priority cascade: direct_gps > facility > country_centroid
environmental_linkage <- environmental_linkage %>%
  mutate(
    env_latitude = case_when(
      !is.na(geo_latitude) & geo_latitude >= -90 & geo_latitude <= 90 ~ geo_latitude,
      !is.na(lat_fac) ~ lat_fac,
      !is.na(lat_ctr) ~ lat_ctr,
      TRUE ~ NA_real_
    ),
    env_longitude = case_when(
      !is.na(geo_longitude) & geo_longitude >= -180 & geo_longitude <= 180 ~ geo_longitude,
      !is.na(lon_fac) ~ lon_fac,
      !is.na(lon_ctr) ~ lon_ctr,
      TRUE ~ NA_real_
    ),
    coordinate_source = case_when(
      !is.na(geo_latitude) & geo_latitude >= -90 ~ "direct_gps",
      !is.na(lat_fac) ~ accuracy_fac,
      !is.na(lat_ctr) ~ "country_centroid",
      TRUE ~ "missing"
    )
  ) %>%
  select(-facility_clean, -country_clean, -lat_fac, -lon_fac, -accuracy_fac, -lat_ctr, -lon_ctr)

cat("\n  Coordinate source summary:\n")
print(table(environmental_linkage$coordinate_source))

# ============================================================================
# PHASE 5: TEMPORAL WINDOWS
# ============================================================================
cat("\nPHASE 5: Computing temporal windows...\n")

environmental_linkage <- environmental_linkage %>%
  mutate(
    date_conception = case_when(
      !is.na(conception_date_unified) ~ conception_date_unified,
      !is.na(date_delivery) & !is.na(ga_weeks) ~ date_delivery - (ga_weeks * 7),
      TRUE ~ as.Date(NA)
    ),
    delivery_month = month(date_delivery),
    delivery_year = year(date_delivery),
    conception_month = month(date_conception),
    conception_year = year(date_conception)
  ) %>%
  select(-conception_date_unified)

# ============================================================================
# PHASE 6: PLACEHOLDERS AND FLAGS
# ============================================================================
cat("PHASE 6: Creating placeholders and quality flags...\n")

environmental_linkage <- environmental_linkage %>%
  mutate(
    env_temp_mean_delivery = NA_real_, env_temp_mean_pregnancy = NA_real_,
    env_humidity_delivery = NA_real_, env_humidity_pregnancy = NA_real_,
    env_precipitation_delivery = NA_real_, env_precipitation_pregnancy = NA_real_,
    env_heat_index_delivery = NA_real_,
    env_season_conception = NA_character_, env_season_delivery = NA_character_,
    env_pm25_annual = NA_real_, env_pm25_delivery = NA_real_, env_pm25_pregnancy = NA_real_,
    env_elevation = NA_real_, env_slope = NA_real_,
    env_ndvi_delivery = NA_real_, env_ndvi_pregnancy = NA_real_,
    has_coordinates = !is.na(env_latitude) & !is.na(env_longitude),
    has_delivery_date = !is.na(date_delivery),
    has_conception_date = !is.na(date_conception),
    has_death_date = !is.na(date_death),
    linkage_ready = has_coordinates & has_delivery_date
  )

cat(glue("  Records with coordinates: {format(sum(environmental_linkage$has_coordinates), big.mark=',')}\n"))
cat(glue("  Linkage-ready records: {format(sum(environmental_linkage$linkage_ready), big.mark=',')}\n\n"))

# ============================================================================
# PHASE 7: EXTRACT ELEVATION AND SLOPE (SRTM) - UNIQUE COORDS OPTIMIZATION
# ============================================================================
cat("PHASE 7: Extracting elevation and slope (SRTM)...\n")

elev_file <- file.path(DIR_SRTM, "srtm_elevation.tif")
slope_file <- file.path(DIR_SRTM, "srtm_slope.tif")

if (file.exists(elev_file) && file.exists(slope_file)) {

  # Get unique coordinates
  unique_coords <- environmental_linkage %>%
    filter(!is.na(env_latitude) & !is.na(env_longitude)) %>%
    distinct(env_latitude, env_longitude)

  cat(glue("  Unique coordinate pairs: {format(nrow(unique_coords), big.mark=',')}\n"))

  coord_vect <- vect(unique_coords, geom = c("env_longitude", "env_latitude"), crs = "EPSG:4326")

  # Elevation
  cat("  Extracting elevation...")
  elev_rast <- rast(elev_file)
  elev_vals <- terra::extract(elev_rast, coord_vect)
  unique_coords$env_elevation <- elev_vals[[2]]
  cat(glue(" done ({sum(!is.na(unique_coords$env_elevation))} values, {round(min(unique_coords$env_elevation, na.rm=TRUE))}-{round(max(unique_coords$env_elevation, na.rm=TRUE))}m)\n"))

  # Slope
  cat("  Extracting slope...")
  slope_rast <- rast(slope_file)
  slope_vals <- terra::extract(slope_rast, coord_vect)
  unique_coords$env_slope <- slope_vals[[2]]
  cat(glue(" done ({round(min(unique_coords$env_slope, na.rm=TRUE), 1)}-{round(max(unique_coords$env_slope, na.rm=TRUE), 1)} degrees)\n"))

  # Join back to full dataset
  environmental_linkage <- environmental_linkage %>%
    select(-env_elevation, -env_slope) %>%
    left_join(unique_coords %>% select(env_latitude, env_longitude, env_elevation, env_slope),
              by = c("env_latitude", "env_longitude"))

  rm(unique_coords, coord_vect, elev_rast, slope_rast, elev_vals, slope_vals)

} else {
  cat("  SRTM files not found\n")
}

gc()

# ============================================================================
# PHASE 8: EXTRACT ERA5 CLIMATE DATA - UNIQUE COORDS OPTIMIZATION
# ============================================================================
cat("\nPHASE 8: Extracting ERA5 climate data (optimized)...\n")

if (file.exists(FILE_ERA5_TEMP)) {

  # Get unique coordinates
  unique_coords <- environmental_linkage %>%
    filter(!is.na(env_latitude) & !is.na(env_longitude)) %>%
    distinct(env_latitude, env_longitude)

  cat(glue("  Unique coordinate pairs for ERA5: {format(nrow(unique_coords), big.mark=',')}\n"))

  # --- Open ERA5 temperature/dewpoint NetCDF ---
  cat("  Opening ERA5 temperature file...\n")
  nc <- nc_open(FILE_ERA5_TEMP)
  lon <- ncvar_get(nc, "longitude")
  lat <- ncvar_get(nc, "latitude")

  # Temperature (t2m)
  cat("  Reading t2m data...")
  t2m_data <- ncvar_get(nc, "t2m")
  cat(" done\n")

  # Dewpoint (d2m)
  cat("  Reading d2m data...")
  d2m_data <- ncvar_get(nc, "d2m")
  cat(" done\n")

  nc_close(nc)

  # For each unique coordinate, find nearest grid indices and extract
  cat(glue("  Extracting for {nrow(unique_coords)} unique coordinates...\n"))

  # Pre-compute nearest indices for all unique coords
  lon_indices <- sapply(unique_coords$env_longitude, function(x) which.min(abs(lon - x)))
  lat_indices <- sapply(unique_coords$env_latitude, function(x) which.min(abs(lat - x)))

  # Extract mean values across all time steps
  t2m_vals <- numeric(nrow(unique_coords))
  d2m_vals <- numeric(nrow(unique_coords))

  for (i in seq_len(nrow(unique_coords))) {
    if (length(dim(t2m_data)) == 3) {
      t2m_vals[i] <- mean(t2m_data[lon_indices[i], lat_indices[i], ], na.rm = TRUE)
      d2m_vals[i] <- mean(d2m_data[lon_indices[i], lat_indices[i], ], na.rm = TRUE)
    } else {
      t2m_vals[i] <- t2m_data[lon_indices[i], lat_indices[i]]
      d2m_vals[i] <- d2m_data[lon_indices[i], lat_indices[i]]
    }
    if (i %% 10000 == 0) cat(glue("    [{i}/{nrow(unique_coords)}]\n"))
  }

  # Convert Kelvin to Celsius
  unique_coords$env_temp_mean_delivery <- t2m_vals - 273.15
  dewpoint_c <- d2m_vals - 273.15
  temp_c <- unique_coords$env_temp_mean_delivery

  # Magnus formula for relative humidity
  unique_coords$env_humidity_delivery <- 100 * exp((17.625 * dewpoint_c) / (243.04 + dewpoint_c)) /
    exp((17.625 * temp_c) / (243.04 + temp_c))
  unique_coords$env_humidity_delivery <- pmin(pmax(unique_coords$env_humidity_delivery, 0), 100)

  # Heat Index (Rothfusz regression)
  T_f <- temp_c * 9/5 + 32
  RH <- unique_coords$env_humidity_delivery
  unique_coords$env_heat_index_delivery <- (-42.379 + 2.04901523*T_f + 10.14333127*RH -
    0.22475541*T_f*RH - 0.00683783*T_f^2 - 0.05481717*RH^2 +
    0.00122874*T_f^2*RH + 0.00085282*T_f*RH^2 - 0.00000199*T_f^2*RH^2 - 32) * 5/9

  cat(glue("  Temperature: {round(min(temp_c, na.rm=TRUE), 1)} to {round(max(temp_c, na.rm=TRUE), 1)} C\n"))
  cat(glue("  Humidity: {round(min(unique_coords$env_humidity_delivery, na.rm=TRUE), 1)} to {round(max(unique_coords$env_humidity_delivery, na.rm=TRUE), 1)} %\n"))
  cat(glue("  Heat index: {round(min(unique_coords$env_heat_index_delivery, na.rm=TRUE), 1)} to {round(max(unique_coords$env_heat_index_delivery, na.rm=TRUE), 1)} C\n"))

  rm(t2m_data, d2m_data, t2m_vals, d2m_vals, dewpoint_c, T_f, RH)
  gc()

  # --- Precipitation ---
  if (file.exists(FILE_ERA5_PRECIP)) {
    cat("  Extracting precipitation...\n")
    nc_p <- nc_open(FILE_ERA5_PRECIP)
    lon_p <- ncvar_get(nc_p, "longitude")
    lat_p <- ncvar_get(nc_p, "latitude")
    tp_data <- ncvar_get(nc_p, "tp")
    nc_close(nc_p)

    lon_p_idx <- sapply(unique_coords$env_longitude, function(x) which.min(abs(lon_p - x)))
    lat_p_idx <- sapply(unique_coords$env_latitude, function(x) which.min(abs(lat_p - x)))

    tp_vals <- numeric(nrow(unique_coords))
    for (i in seq_len(nrow(unique_coords))) {
      if (length(dim(tp_data)) == 3) {
        tp_vals[i] <- mean(tp_data[lon_p_idx[i], lat_p_idx[i], ], na.rm = TRUE)
      } else {
        tp_vals[i] <- tp_data[lon_p_idx[i], lat_p_idx[i]]
      }
    }
    unique_coords$env_precipitation_delivery <- tp_vals * 1000 * 30  # m -> mm/month
    cat(glue("  Precipitation: {round(min(unique_coords$env_precipitation_delivery, na.rm=TRUE), 1)} to {round(max(unique_coords$env_precipitation_delivery, na.rm=TRUE), 1)} mm/month\n"))
    rm(tp_data, tp_vals)
  }

  # Pregnancy-period copies (same as delivery for now - monthly mean data)
  unique_coords$env_temp_mean_pregnancy <- unique_coords$env_temp_mean_delivery
  unique_coords$env_humidity_pregnancy <- unique_coords$env_humidity_delivery
  unique_coords$env_precipitation_pregnancy <- unique_coords$env_precipitation_delivery

  # Join back to full dataset
  climate_cols <- c("env_latitude", "env_longitude", "env_temp_mean_delivery",
                    "env_temp_mean_pregnancy", "env_humidity_delivery", "env_humidity_pregnancy",
                    "env_precipitation_delivery", "env_precipitation_pregnancy",
                    "env_heat_index_delivery")

  environmental_linkage <- environmental_linkage %>%
    select(-any_of(setdiff(climate_cols, c("env_latitude", "env_longitude")))) %>%
    left_join(unique_coords %>% select(any_of(climate_cols)),
              by = c("env_latitude", "env_longitude"))

  rm(unique_coords)
  gc()

} else {
  cat("  ERA5 files not found\n")
}

# ============================================================================
# PHASE 9: PM2.5 - UNIQUE COORDS OPTIMIZATION
# ============================================================================
cat("\nPHASE 9: Extracting PM2.5 air quality...\n")

# Use annual files (pattern: YYYYMM-YYYYMM.nc in top-level pm25 dir)
pm25_files <- list.files(DIR_PM25, pattern = "^V6GL.*\\.nc$", full.names = TRUE)

if (length(pm25_files) > 0) {
  cat(glue("  Found {length(pm25_files)} annual PM2.5 files\n"))

  coords_for_pm25 <- environmental_linkage %>%
    filter(!is.na(env_latitude) & !is.na(env_longitude) & !is.na(date_delivery))

  coords_for_pm25$env_pm25_annual <- NA_real_
  coords_for_pm25$env_pm25_delivery <- NA_real_
  coords_for_pm25$env_pm25_pregnancy <- NA_real_

  years_available <- unique(na.omit(coords_for_pm25$delivery_year))
  years_valid <- years_available[years_available >= 1998 & years_available <= 2023]

  for (yr in sort(years_valid)) {
    pattern <- sprintf("%d01-%d12", yr, yr)
    match_file <- pm25_files[grep(pattern, pm25_files)]

    if (length(match_file) == 0) next

    cat(glue("  {yr}: "))

    tryCatch({
      pm25_rast <- rast(match_file[1])

      yr_rows <- which(coords_for_pm25$delivery_year == yr)
      if (length(yr_rows) == 0) { cat("no records\n"); next }

      # Get unique coords for this year
      yr_unique <- coords_for_pm25[yr_rows, ] %>%
        distinct(env_latitude, env_longitude) %>%
        mutate(pm25_val = {
          xy <- cbind(env_longitude, env_latitude)
          extracted <- terra::extract(pm25_rast, xy)
          if (ncol(extracted) >= 2) extracted[[2]] else extracted[[1]]
        })

      # Join back
      coords_for_pm25[yr_rows, ] <- coords_for_pm25[yr_rows, ] %>%
        left_join(yr_unique %>% select(env_latitude, env_longitude, pm25_new = pm25_val),
                  by = c("env_latitude", "env_longitude")) %>%
        mutate(
          env_pm25_annual = pm25_new,
          env_pm25_delivery = pm25_new,
          env_pm25_pregnancy = pm25_new
        ) %>%
        select(-pm25_new)

      n_extracted <- sum(!is.na(coords_for_pm25$env_pm25_annual[yr_rows]))
      cat(glue("{n_extracted} values\n"))

    }, error = function(e) cat(glue("ERROR: {e$message}\n")))
  }

  # Merge PM2.5 back
  pm25_cols <- c("unified_id", "env_pm25_annual", "env_pm25_delivery", "env_pm25_pregnancy")
  environmental_linkage <- environmental_linkage %>%
    select(-any_of(pm25_cols[pm25_cols != "unified_id"])) %>%
    left_join(coords_for_pm25 %>% select(any_of(pm25_cols)), by = "unified_id")

  n_pm25 <- sum(!is.na(environmental_linkage$env_pm25_annual))
  cat(glue("  PM2.5: {format(n_pm25, big.mark=',')} records ({round(100 * n_pm25 / nrow(environmental_linkage), 1)}%)\n"))

  rm(coords_for_pm25)
  gc()

} else {
  cat("  No PM2.5 files found\n")
}

# ============================================================================
# PHASE 10: SEASONAL CLASSIFICATION
# ============================================================================
cat("\nPHASE 10: Classifying seasons...\n")

environmental_linkage <- environmental_linkage %>%
  mutate(
    env_season_delivery = case_when(
      is.na(env_latitude) | is.na(delivery_month) ~ NA_character_,
      env_latitude >= 0 & delivery_month %in% c(5:10) ~ "Wet",
      env_latitude >= 0 & delivery_month %in% c(1:4, 11:12) ~ "Dry",
      env_latitude < 0 & delivery_month %in% c(11:12, 1:4) ~ "Wet",
      env_latitude < 0 & delivery_month %in% c(5:10) ~ "Dry",
      TRUE ~ NA_character_
    ),
    env_season_conception = case_when(
      is.na(env_latitude) | is.na(conception_month) ~ NA_character_,
      env_latitude >= 0 & conception_month %in% c(5:10) ~ "Wet",
      env_latitude >= 0 & conception_month %in% c(1:4, 11:12) ~ "Dry",
      env_latitude < 0 & conception_month %in% c(11:12, 1:4) ~ "Wet",
      env_latitude < 0 & conception_month %in% c(5:10) ~ "Dry",
      TRUE ~ NA_character_
    )
  )

cat(glue("  Wet: {sum(environmental_linkage$env_season_delivery == 'Wet', na.rm=TRUE)}, Dry: {sum(environmental_linkage$env_season_delivery == 'Dry', na.rm=TRUE)}\n"))

# ============================================================================
# PHASE 11: QUALITY SUMMARY
# ============================================================================
cat("\nPHASE 11: Quality summary...\n")
cat(glue("  Total records: {format(nrow(environmental_linkage), big.mark=',')}\n"))
cat(glue("  With coordinates: {format(sum(environmental_linkage$has_coordinates), big.mark=',')} ({round(100*mean(environmental_linkage$has_coordinates), 1)}%)\n"))
cat(glue("  Linkage-ready: {format(sum(environmental_linkage$linkage_ready), big.mark=',')} ({round(100*mean(environmental_linkage$linkage_ready), 1)}%)\n"))

env_vars <- c("env_elevation", "env_slope", "env_temp_mean_delivery",
              "env_humidity_delivery", "env_precipitation_delivery",
              "env_heat_index_delivery", "env_pm25_annual", "env_season_delivery")

cat("\n  Variable completeness:\n")
for (v in env_vars) {
  if (v %in% names(environmental_linkage)) {
    pct <- round(mean(!is.na(environmental_linkage[[v]])) * 100, 1)
    cat(sprintf("    %-30s %5.1f%%\n", v, pct))
  }
}

# Check unique coordinates
n_unique <- environmental_linkage %>%
  filter(!is.na(env_latitude)) %>%
  distinct(env_latitude, env_longitude) %>%
  nrow()
cat(glue("\n  Unique coordinate pairs: {format(n_unique, big.mark=',')}\n"))

# ============================================================================
# PHASE 12: EXPORT
# ============================================================================
cat("\nPHASE 12: Exporting...\n")

environmental_linkage_final <- environmental_linkage

saveRDS(environmental_linkage_final, file.path(DIR_OUTPUT, paste0(OUTPUT_FILE, ".rds")))
cat(glue("  Saved: {OUTPUT_FILE}.rds ({round(file.info(file.path(DIR_OUTPUT, paste0(OUTPUT_FILE, '.rds')))$size/1024^2, 1)} MB)\n"))

write_csv(environmental_linkage_final, file.path(DIR_OUTPUT, paste0(OUTPUT_FILE, ".csv")))
cat(glue("  Saved: {OUTPUT_FILE}.csv\n"))

# Geocode references
write_csv(facility_geocodes, file.path(DIR_OUTPUT, "facility_geocodes_reference.csv"))
write_csv(country_centroids, file.path(DIR_OUTPUT, "country_centroids_reference.csv"))

rm(environmental_linkage, environmental_linkage_final)
gc()

cat("\n================================================================\n")
cat(glue("  ENVIRONMENTAL EXTRACTION v{VERSION} COMPLETE\n"))
cat("================================================================\n")
