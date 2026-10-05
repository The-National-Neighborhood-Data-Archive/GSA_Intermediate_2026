# R scripts

The live session is in R, from the notebook. These are the same steps as plain
scripts, one per geography, with the same block headers (`# ---- setup ----`,
`# ---- read-data ----`, and so on) as the notebook page and as the Stata and Python
files, so you can read any two side by side.

| File | Key | What it is |
|---|---|---|
| `linking_nanda_zcta.R` | ZIP code, crosswalked to a 2010 ZCTA | The notebook's R code, block for block. This is the route the session runs. |
| `linking_nanda_tract.R` | A 2010 Census tract ID already on your data | The same merge with a different key, adapted from Robert Melendez's tract-level script. Not demonstrated live. |

Both read the NaNDA files from `data/nanda/`; `data/nanda/README.md` lists the
downloads for each route. Open `workshop.Rproj` first so `here::here()` finds them.

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
is a separate job, and this workshop does not teach it. The usual routes:

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
  each point in its tract. Section 2 of the notebook shows the shape of this workflow
  without running it. Free services are rate-limited to about one address a second.
- **An institutional or commercial geocoder** (ArcGIS, Google, your university's GIS
  service). Check the terms before storing or sharing the results.

Whichever you use, keep the match-quality field it returns and decide, before you
merge, which matches are precise enough to place in a tract. Rooftop matches are
precise enough. City-center matches are not.

The `tract_fips10` column in `data/synthetic_data_v20260924_tract10.csv` is as
synthetic as the rest of the file: real 2010 tract IDs drawn at random within each
row's state, with no tract where the address is blank and a few dropped to stand in
for geocoder failures. No address was geocoded.
