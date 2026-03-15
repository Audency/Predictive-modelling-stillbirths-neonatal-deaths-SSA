# -*- coding: utf-8 -*-
"""
Created on Wed Feb  4 12:38:58 2026

@author: eidejwai
"""

# Save this as: download_era5_fixed.py

import cdsapi
import os

os.makedirs("data/era5", exist_ok=True)

c = cdsapi.Client()

print("Downloading ERA5 data (NetCDF-4 format)...")

c.retrieve(
    "reanalysis-era5-single-levels-monthly-means",
    {
        "product_type": "monthly_averaged_reanalysis",
        "variable": [
            "2m_temperature",
            "2m_dewpoint_temperature",
            "total_precipitation",
        ],
        "year": ["2015", "2016", "2017", "2018", "2019", "2020"],
        "month": ["01", "02", "03", "04", "05", "06", "07", "08", "09", "10", "11", "12"],
        "time": "00:00",
        "area": [40, -20, -35, 55],
        "data_format": "netcdf",  # Explicit format
        "download_format": "unarchived"  # Don't compress
    },
    "data/era5/era5_monthly_africa.nc"
)

print("✅ Download complete!")