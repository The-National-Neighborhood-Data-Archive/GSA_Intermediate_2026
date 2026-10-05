"""Linking NaNDA With Your Data: from a street address to a 2010 tract ID, in Python.

Section 2 of the notebook explains this step and shows its shape without running
it. This file is the whole step: geocode each address against OpenStreetMap, keep
the matches precise enough to place in a tract, download the 2010 TIGER/Line tract
boundaries for the states in your data, and put each point in its tract. The output
has every column of the input plus the coordinates, the match-quality fields, and
tract_fips10, so linking_nanda_tract.py takes it as its input (change the path in
its read-data block). It is translated from r/geocode_to_tract.R, which is adapted
from Robert Melendez's geocode_osm_sj_tract10.R. Block headers match the R file.
The session does not run it live.

Before you run it:
  - It takes about one second per address. That is OpenStreetMap's Nominatim usage
    policy, and the RateLimiter below enforces the pause. The synthetic file has
    2,004 rows, so expect about 35 minutes. The result is saved after the slow
    step, so you never geocode the same file twice.
  - Nominatim is for light, occasional use. For a study of any size, use the
    Census Geocoder (free, no account, batches of 10,000, and it returns the tract
    directly; the Stata file takes that route) or a paid service. Robert has had a
    high match rate with ArcGIS (about $4 per 1,000 addresses) and Google (about $5
    per 1,000). Check the terms of whichever service you use before you store or
    share the output; some restrict both.
  - You need two packages beyond the workshop list: geopy (the geocoding client) and
    geopandas (points, boundaries, spatial join). pip install geopy geopandas
"""

# ---- setup ----
import time
from pathlib import Path

import numpy as np
import pandas as pd
import geopandas as gpd                       # spatial data frames and the spatial join
import requests                               # downloads the boundary files
from geopy.geocoders import Nominatim         # the OpenStreetMap geocoder
from geopy.extra.rate_limiter import RateLimiter

# ROOT is the workshop folder, the one holding workshop.Rproj. Adjust it if you moved the script.
ROOT = Path(__file__).resolve().parents[1] if "__file__" in globals() else Path.cwd()
DATA = ROOT / "data"
TIGER = DATA / "tiger2010"                    # boundary downloads are kept between runs
TIGER.mkdir(exist_ok=True)

# ---- read-data ----
# zip must stay text or 01001 loses its zero; see Section 0 of the notebook.
mydata = pd.read_csv(DATA / "synthetic_data_v20260924.csv", dtype={"zip": str})

# ---- geocode ----
# Each address is one request. The address goes as separate fields (street, city,
# state, postal code), which Nominatim matches better than one long string, and
# addressdetails=True brings back the fields the precision check needs. Nominatim
# requires a user agent that identifies the application. Every row with any
# address field goes, as in the R file (tidygeocoder skips only rows with nothing
# to send); rows with no street, city or ZIP get no coordinates.
geolocator = Nominatim(user_agent="linking-nanda-workshop", timeout=10)
geocode = RateLimiter(geolocator.geocode, min_delay_seconds=1, max_retries=2,
                      swallow_exceptions=True)
NOTHING = pd.Series({"lat": np.nan, "long": np.nan, "addresstype": None, "place_rank": np.nan})


def geocode_row(row):
    query = {"state": row["state"], "country": "US"}
    for field, key in (("address", "street"), ("city", "city"), ("zip", "postalcode")):
        if pd.notna(row[field]) and str(row[field]).strip() != "":
            query[key] = row[field]
    if len(query) == 2:          # state and country only: nothing to geocode
        return NOTHING
    hit = geocode(query, addressdetails=True)
    if hit is None:
        return NOTHING
    return pd.Series({"lat": hit.latitude, "long": hit.longitude,
                      "addresstype": hit.raw.get("addresstype"),
                      "place_rank": hit.raw.get("place_rank")})


print(f"Geocoding {len(mydata)} addresses at about one per second...")
started = time.time()
mydata_geocoded = pd.concat([mydata, mydata.apply(geocode_row, axis=1)], axis=1)
mydata_geocoded["place_rank"] = mydata_geocoded["place_rank"].astype("Int64")
print(f"Done in {(time.time() - started) / 60:.1f} minutes.")

# Save the slow step. To pick up from here another day, run the read line
# instead of the block above.
mydata_geocoded.to_csv(DATA / "synthetic_data_v20260924_osm_geocoded.csv", index=False)
# mydata_geocoded = pd.read_csv(DATA / "synthetic_data_v20260924_osm_geocoded.csv", dtype={"zip": str})

# ---- check-precision ----
# A rooftop match and a "somewhere in this town" match both come back with
# coordinates. Nominatim's place_rank tells them apart: 26 and above is a street
# or a building, below that is a town, county or postcode centroid, too coarse to
# place in a tract. Look at the tables before trusting the cutoff.
# https://nominatim.org/release-docs/latest/customize/Ranking/#address-rank
# One thing to look at: a row with no street address, only a city and a ZIP, can
# still come back as a road at rank 26 and pass this rule. The diagnostics block
# counts how often that happened; decide for your data whether to drop those rows
# before geocoding.
print(mydata_geocoded["addresstype"].value_counts(dropna=False))
print(mydata_geocoded["place_rank"].value_counts(dropna=False).sort_index())
print(pd.crosstab(mydata_geocoded["addresstype"], mydata_geocoded["place_rank"]))

mydata_geocoded["good_place_rank"] = np.where(
    mydata_geocoded["place_rank"].notna() & (mydata_geocoded["place_rank"] >= 26), 1, 0
)

# ---- tract-boundaries ----
# Download the 2010 TIGER/Line tracts for every state in the data, one zip per state from the
# Census Bureau's FTP site, a few MB each, cached in data/tiger2010/. These are the
# full boundaries rather than the generalized cartographic ones, so a point near a
# tract edge lands on the right side. TIGER names the files by state FIPS code.
STATE_FIPS = {
    "AL": "01", "AK": "02", "AZ": "04", "AR": "05", "CA": "06", "CO": "08", "CT": "09",
    "DE": "10", "DC": "11", "FL": "12", "GA": "13", "HI": "15", "ID": "16", "IL": "17",
    "IN": "18", "IA": "19", "KS": "20", "KY": "21", "LA": "22", "ME": "23", "MD": "24",
    "MA": "25", "MI": "26", "MN": "27", "MS": "28", "MO": "29", "MT": "30", "NE": "31",
    "NV": "32", "NH": "33", "NJ": "34", "NM": "35", "NY": "36", "NC": "37", "ND": "38",
    "OH": "39", "OK": "40", "OR": "41", "PA": "42", "RI": "44", "SC": "45", "SD": "46",
    "TN": "47", "TX": "48", "UT": "49", "VT": "50", "VA": "51", "WA": "53", "WV": "54",
    "WI": "55", "WY": "56", "PR": "72",
}


def tracts_2010(state):
    fips = STATE_FIPS[state]
    local = TIGER / f"tl_2010_{fips}_tract10.zip"
    if not local.exists():
        url = f"https://www2.census.gov/geo/tiger/TIGER2010/TRACT/2010/{local.name}"
        with requests.get(url, stream=True, timeout=120) as r:
            r.raise_for_status()
            local.write_bytes(r.content)
    return gpd.read_file(local)[["GEOID10", "geometry"]]


states_in_data = sorted(mydata["state"].dropna().unique())
print(f"Downloading 2010 tract boundaries for {len(states_in_data)} state(s)...")
tracts2010 = pd.concat([tracts_2010(st) for st in states_in_data], ignore_index=True)
tracts2010 = gpd.GeoDataFrame(tracts2010, crs=tracts2010.crs)

# ---- spatial-join ----
# Only the rows that geocoded become points; a point needs both coordinates. OSM
# returns WGS84 (EPSG 4326); TIGER is NAD83, so project the points to match before
# intersecting.
has_point = mydata_geocoded["lat"].notna() & mydata_geocoded["long"].notna()
points = gpd.GeoDataFrame(
    mydata_geocoded.loc[has_point, ["sampleid", "year", "good_place_rank"]],
    geometry=gpd.points_from_xy(mydata_geocoded.loc[has_point, "long"],
                                mydata_geocoded.loc[has_point, "lat"]),
    crs="EPSG:4326",
).to_crs(tracts2010.crs)

joined = gpd.sjoin(points, tracts2010, how="left", predicate="intersects")
joined = pd.DataFrame(joined.drop(columns=["geometry", "index_right"]))
joined["tract_fips10"] = np.where(joined["good_place_rank"] == 1, joined["GEOID10"], None)
joined = joined[["sampleid", "year", "GEOID10", "tract_fips10"]]

# Join the result back onto every original row. Addresses that did not geocode, or geocoded too
# coarsely, stay in the file with a missing tract_fips10, which is where the merge
# diagnostics in linking_nanda_tract.py will count them.
mydata_tract10 = mydata_geocoded.merge(joined, on=["sampleid", "year"], how="left")

# ---- diagnostics ----
# This block counts how many rows reached a tract and why the rest did not. Blank addresses and
# coarse matches come from the input data, so count them separately from join failures.
# (Robert's script has no diagnostics block; this one repeats the accounting the
# merge scripts do in Section 3.)
no_street = mydata_tract10["address"].isna() | (mydata_tract10["address"].astype(str).str.strip() == "")
outcome = np.select(
    [
        mydata_tract10["tract_fips10"].notna(),
        no_street,
        mydata_tract10["lat"].isna(),
        mydata_tract10["good_place_rank"] == 0,
    ],
    [
        "in a 2010 tract",
        "no street address",
        "address did not geocode",
        "geocoded, too coarse for a tract",
    ],
    default="geocoded, no 2010 tract found",
)
print(pd.Series(outcome).value_counts().to_frame("n").assign(
    percent=lambda d: (100 * d["n"] / d["n"].sum()).round(1)))
print("Placed in a tract from a city and ZIP alone, no street address:",
      int((mydata_tract10["tract_fips10"].notna() & no_street).sum()))

# ---- write ----
# The output has the input's columns, then what this script added. GEOID10 is kept beside
# tract_fips10 so you can see which coarse matches were set to missing.
mydata_tract10[list(mydata.columns) + ["lat", "long", "addresstype", "place_rank",
                                       "GEOID10", "tract_fips10"]].to_csv(
    DATA / "synthetic_data_v20260924_geocoded_tract10.csv", index=False)
