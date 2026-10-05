# R scripts

The live session is in R, from the notebook. These are the same steps as plain
scripts, one per geography, with the same block headers (`# ---- setup ----`,
`# ---- read-data ----`, and so on) as the notebook page and as the Stata and Python
files, so you can read any two side by side.

| File | Key | What it is |
|---|---|---|
| `linking_nanda_zcta.R` | ZIP code, crosswalked to a 2010 ZCTA | The notebook's R code, block for block. This is the route the session runs. |
| `linking_nanda_tract.R` | A 2010 Census tract ID already on your data | The same merge with a different key, adapted from Robert Melendez's tract-level script. Not demonstrated live. |
| `geocode_to_tract.R` | A street address | Gets the tract ID: geocodes each address against OpenStreetMap, keeps the matches precise enough to place, and spatially joins the points to 2010 tract boundaries. It is adapted from Robert Melendez's geocoder and is not run live in the session. Read the section below before running it. |

The two merge scripts read the NaNDA files from `data/nanda/`; `data/nanda/README.md`
lists the downloads for each route. Open `workshop.Rproj` first so `here::here()`
finds them.

## The tract route in one paragraph

Everything after the key is the same merge: Social Services joins on tract and year
(carried forward past 2022), Parks joins on tract alone, Socioeconomic Status joins
on tract. One thing is cleaner at the tract level: NaNDA's SES tract files are on
2010 boundaries for both 2008-2017 (DS0002) and 2018-2022 (DS0006), so the tract
script splits the rows at 2018 and gives each period its own file. The ZCTA route
cannot, because its 2018-2022 file is on 2020 boundaries, which is why the notebook
joins one file to every row.

## Where a tract ID comes from

The tract script starts from a column called `tract_fips10`: state (2) + county (3)
+ tract (6), eleven characters, 2010 boundaries. Getting that column onto your data
is a separate job. The session does not run it; `geocode_to_tract.R` does, for the
synthetic file, and the next section says what to expect. The usual routes:

- **Your data already has it.** Many survey, claims, and administrative files carry a
  tract code. Check the boundary year: a 2020 tract ID needs a 2020-to-2010 crosswalk
  before it will match NaNDA's 2010 files, or use NaNDA's 2020-boundary files where
  they exist.
- **The Census Geocoder.** It is free, needs no account, and accepts batch files of up
  to 10,000 addresses. It returns the tract GEOID directly when you request 2010
  boundaries, so no shapefiles or spatial join are needed:
  <https://geocoding.geo.census.gov/geocoder/>.
- **A geocoding package plus a spatial join.** `tidygeocoder` (OpenStreetMap, Census,
  and others) for coordinates, `tigris` for 2010 tract boundaries, `sf::st_join` to put
  each point in its tract. This is what `geocode_to_tract.R` does; Section 2 of the
  notebook shows its shape. Free services are rate-limited to about one address a
  second.
- **An institutional or commercial geocoder** (ArcGIS, Google, your university's GIS
  service). Check the terms before storing or sharing the results.

Whichever you use, keep the match-quality field it returns and decide, before you
merge, which matches are precise enough to place in a tract. Rooftop matches are
precise enough. City-center matches are not.

The `tract_fips10` column in `data/synthetic_data_v20260924_tract10.csv` is as
synthetic as the rest of the file: real 2010 tract IDs drawn at random within each
row's state, with no tract where the address is blank and a few dropped to stand in
for geocoder failures. No address was geocoded to make it.

## The geocoding script

`geocode_to_tract.R` reads `data/synthetic_data_v20260924.csv` and writes
`data/synthetic_data_v20260924_geocoded_tract10.csv`: the same columns plus the
coordinates, OpenStreetMap's match-quality fields (`addresstype`, `place_rank`), the
tract the point fell in (`GEOID10`), and `tract_fips10`, which is that tract where
the match was precise enough and missing otherwise. Point `linking_nanda_tract.R` at
the output (one path in its read-data block) and the merge runs on geocoded data
instead of the synthetic tract IDs.

Know before you run it:

- **It is slow.** OpenStreetMap's Nominatim service allows one request a second, and
  the script waits accordingly. The synthetic file has about 2,000 rows, so expect
  about 35 minutes. The geocoded result is saved to an `.rds`
  file before the spatial join, so a second run can skip the slow part.
- **It needs three packages that the session does not:** `tidygeocoder`, `tigris` and
  `sf`. `install.packages(c("tidygeocoder", "tigris", "sf"))`. The tract boundaries
  download once per state (about 10 MB each) and are cached by `tigris`.
- **Expect a low match rate on this file.** The synthetic addresses are rural and
  often missing a city or ZIP, and OpenStreetMap's coverage of rural US addresses is
  thin. On a 15-row sample it placed 3 to 5 of the 12 rows that had a street address,
  and the set changed between runs a few minutes apart. The Census Geocoder placed 7
  of the same 12 in about a second; for real data, change `method = "osm"` to
  `method = "census"` in the geocode block, or use the Census batch route the Stata
  file takes.
- **The precision cutoff is a judgment.** Robert's rule, `place_rank >= 26`, accepts a
  road-level match. A stricter study would require 30, a match to the building. Look
  at the tables the script prints before deciding. One case to watch: a row with no
  street address, only a city and a ZIP, can come back as a road at rank 26 and pass.
  The script reports how many rows were placed that way; whether to drop them, or to
  leave such rows out before geocoding, is your decision for your data.
- **Terms of service.** Nominatim is for light, occasional use, and it asks that you
  not bulk-geocode large files. Paid services (ArcGIS, Google) match well and cost a
  few dollars per thousand addresses; some restrict storing or sharing the results.
