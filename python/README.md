# Python version

The live session is in R. These `.py` scripts do the same thing, step for step, for
participants who work in Python. Each ZCTA step also appears on the notebook page, in
the Python tab beside the R version.

| File | Key | What it is |
|---|---|---|
| `linking_nanda_zcta.py` | ZIP code, crosswalked to a 2010 ZCTA | The notebook's steps. This is the route the session runs. |
| `linking_nanda_tract.py` | A 2010 Census tract ID already on your data | The same merge with a different key. Where the ID comes from is covered in `r/README.md`. |
| `geocode_to_tract.py` | A street address | Gets the tract ID: geocodes each address against OpenStreetMap, keeps the matches precise enough to place, and spatially joins the points to 2010 tract boundaries. It follows the same steps as the R file and is not run live in the session. Read the section below before running it. |

The scripts use the same section headers as the R scripts (`# ---- setup ----`,
`# ---- read-data ----`, and so on), so a block in one language lines up with the same
block in `r/` and `stata/`.

The two merge scripts take the Stata-format downloads from ICPSR (pandas reads `.dta`
natively); `data/nanda/README.md` lists them for each route. They require pandas,
numpy, and openpyxl for the crosswalk. The toy model also needs statsmodels and is
skipped if it is missing.

## The geocoding script

`geocode_to_tract.py` reads `data/synthetic_data_v20260924.csv` and writes
`data/synthetic_data_v20260924_geocoded_tract10.csv`, the same output file as the R
version, column for column: the input plus coordinates, OpenStreetMap's
match-quality fields, the tract the point fell in, and `tract_fips10`. Point
`linking_nanda_tract.py` at it (one path in its read-data block) and the merge runs on
geocoded data. Everything in the "geocoding script" section of `r/README.md` applies
here too: about one address a second, so about 35 minutes for this file; a low match
rate on these rural, often incomplete addresses; the precision cutoff is a judgment,
and the script reports how many tracts were placed from a city and ZIP alone. Two
things are Python's own:

- **Packages.** geopy (the Nominatim client, with a rate limiter) and geopandas (the
  points, the boundaries and the spatial join): `pip install geopy geopandas`. The
  2010 tract boundaries are downloaded one zip per state from the Census Bureau's
  site, about 10 MB each, into `data/tiger2010/`, and reused on later runs.
- **The checkpoint is a CSV.** The geocoded rows are written to
  `data/synthetic_data_v20260924_osm_geocoded.csv` before the spatial join, and a
  commented line reads it back, so a second run can skip the slow part.

Every identifier column is read with an explicit `dtype=str`, the same leading-zero
pitfall described in Section 0 of the notebook. The joins use `merge(..., indicator=True)`,
so the Section 3 match-rate diagnostic comes from the join itself, as with Stata's
`_merge`.
