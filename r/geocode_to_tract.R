# Linking NaNDA With Your Data: from a street address to a 2010 tract ID, in R.
# Section 2 of the notebook explains this step and shows its shape without
# running it. This file is the whole step: geocode each address against
# OpenStreetMap, keep the matches precise enough to place in a tract, download
# the 2010 TIGER/Line tract boundaries for the states in your data, and put each
# point in its tract. The output has every column of the input plus the
# coordinates, the match-quality fields, and tract_fips10, so
# linking_nanda_tract.R takes it as its input (change the path in its read-data
# block). It is adapted from Robert Melendez's geocode_osm_sj_tract10.R, and the
# session does not run it live. The same steps are in python/; stata/ reaches
# the same output by a different route (see stata/README.md).
#
# Before you run it:
#   - It takes about one second per address. That is OpenStreetMap's Nominatim
#     usage policy, and tidygeocoder enforces the pause. The synthetic file has
#     2,004 rows, so expect about 35 minutes. The result is saved after the slow
#     step, so you never geocode the same file twice.
#   - Nominatim is for light, occasional use. For a study of any size, use the
#     Census Geocoder (free, no account, batches of 10,000, and it returns the
#     tract directly: method = "census" in tidygeocoder, or the route the Stata
#     file takes), or a paid service. Robert has had a high match rate with
#     ArcGIS (about $4 per 1,000 addresses) and Google (about $5 per 1,000).
#     Check the terms of whichever service you use before you store or share
#     the output; some restrict both.
#   - Three packages beyond the workshop install list:
#     install.packages(c("tidygeocoder", "tigris", "sf"))
# Open workshop.Rproj first so here::here() resolves the paths.

# ---- setup ----
library(tidyverse)
library(here)
library(janitor)
library(tidygeocoder)   # one interface to many geocoding services
library(tigris)         # Census boundary files
library(sf)             # spatial joins
options(tigris_use_cache = TRUE)   # boundary downloads are kept between runs

# ---- read-data ----
# zip must stay text or 01001 loses its zero; see Section 0 of the notebook.
mydata <- read_csv(
  here("data", "synthetic_data_v20260924.csv"),
  col_types = cols(zip = col_character())
)

# ---- geocode ----
# Each address is one request. The address goes as separate fields (street, city,
# state, postal code), which Nominatim matches better than one long string.
# Every row goes, as in Robert's script; tidygeocoder skips a row with nothing
# to send and waits the required second between requests.
message("Geocoding ", nrow(mydata), " addresses at about one per second...")
mydata_geocoded <- mydata %>%
  geocode(
    street = address, city = city, state = state, postalcode = zip,
    method = "osm", full_results = TRUE
  )

# Save the slow step. To pick up from here another day, run the read_rds line
# instead of the block above.
write_rds(mydata_geocoded, here("data", "synthetic_data_v20260924_osm_geocoded.rds"))
# mydata_geocoded <- read_rds(here("data", "synthetic_data_v20260924_osm_geocoded.rds"))

# ---- check-precision ----
# A rooftop match and a "somewhere in this town" match both come back with
# coordinates. Nominatim's place_rank tells them apart: 26 and above is a
# street or a building, below that is a town, county or postcode centroid, too
# coarse to place in a tract. Look at the tables before trusting the cutoff.
# https://nominatim.org/release-docs/latest/customize/Ranking/#address-rank
# One thing to look at: a row with no street address, only a city and a ZIP,
# can still come back as a road at rank 26 and pass this rule. The diagnostics
# block counts how often that happened; decide for your data whether to drop
# those rows before geocoding.
tabyl(mydata_geocoded, addresstype)
tabyl(mydata_geocoded, place_rank)
tabyl(mydata_geocoded, addresstype, place_rank)

mydata_geocoded <- mydata_geocoded %>%
  mutate(good_place_rank = if_else(!is.na(place_rank) & place_rank >= 26, 1, 0))

# ---- tract-boundaries ----
# Download the 2010 TIGER/Line tracts for every state in the data. cb = FALSE takes the full
# boundaries rather than the generalized cartographic ones, so a point near a
# tract edge lands on the right side. Each state is one download of a few MB.
states_in_data <- unique(na.omit(mydata$state))
message("Downloading 2010 tract boundaries for ", length(states_in_data), " state(s)...")
tracts2010 <- states_in_data %>%
  map(\(st) tracts(state = st, cb = FALSE, year = 2010)) %>%
  bind_rows()

# ---- spatial-join ----
# Only the rows that geocoded become points; st_as_sf cannot take a missing
# coordinate. OSM returns WGS84 (EPSG 4326); TIGER is NAD83, so project the
# points to match before intersecting.
points <- mydata_geocoded %>%
  filter(!is.na(lat), !is.na(long)) %>%
  st_as_sf(coords = c("long", "lat"), crs = 4326) %>%
  st_transform(st_crs(tracts2010))

joined <- st_join(points, select(tracts2010, GEOID10), join = st_intersects) %>%
  st_drop_geometry() %>%
  mutate(tract_fips10 = if_else(good_place_rank == 1, GEOID10, NA_character_)) %>%
  select(sampleid, year, GEOID10, tract_fips10)

# Join the result back onto every original row. Addresses that did not geocode, or geocoded
# too coarsely, stay in the file with a missing tract_fips10, which is where
# the merge diagnostics in linking_nanda_tract.R will count them.
mydata_tract10 <- mydata_geocoded %>%
  left_join(joined, by = c("sampleid", "year"))

# ---- diagnostics ----
# This block counts how many rows reached a tract and why the rest did not. Blank addresses and
# coarse matches come from the input data, so count them separately from join failures.
# (Robert's script has no diagnostics block; this one repeats the accounting
# the merge scripts do in Section 3.)
mydata_tract10 %>%
  mutate(outcome = case_when(
    !is.na(tract_fips10)           ~ "in a 2010 tract",
    is.na(address) | address == "" ~ "no street address",
    is.na(lat)                     ~ "address did not geocode",
    good_place_rank == 0           ~ "geocoded, too coarse for a tract",
    TRUE                           ~ "geocoded, no 2010 tract found"
  )) %>%
  tabyl(outcome) %>%
  adorn_pct_formatting()
message("Placed in a tract from a city and ZIP alone, no street address: ",
        sum(!is.na(mydata_tract10$tract_fips10) &
            (is.na(mydata_tract10$address) | mydata_tract10$address == "")))

# ---- write ----
# The output has the input's columns, then what this script added. GEOID10 is kept beside
# tract_fips10 so you can see which coarse matches were set to missing.
mydata_tract10 %>%
  select(all_of(names(mydata)), lat, long, addresstype, place_rank, GEOID10, tract_fips10) %>%
  write_csv(here("data", "synthetic_data_v20260924_geocoded_tract10.csv"), na = "")
