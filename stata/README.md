# Stata version

The live session is in R. These `.do` files do the same thing, step for step, for
participants who work in Stata. Each ZCTA step also appears on the notebook page, in
the Stata tab beside the R version.

| File | Key | What it is |
|---|---|---|
| `linking_nanda_zcta.do` | ZIP code, crosswalked to a 2010 ZCTA | The notebook's steps. This is the route the session runs. |
| `linking_nanda_tract.do` | A 2010 Census tract ID already on your data | The same merge with a different key. Where the ID comes from is covered in `r/README.md`. |
| `geocode_to_tract.do` | A street address | Gets the tract ID through the Census Bureau's batch geocoder, called with curl. It has not been run in Stata; read the section below first. |

The scripts use the same section headers as the R scripts (`* ---- setup ----`,
`* ---- read-data ----`, and so on), so a block in one language lines up with the same
block in `r/` and `python/`.

Both take the Stata-format downloads from ICPSR; `data/nanda/README.md` lists them
for each route. Run from the workshop folder (the one holding `workshop.Rproj`) so the
relative paths resolve.

Stata's `merge` creates a `_merge` variable automatically. R's joins drop and
duplicate unmatched rows without any message, so in R the Section 3 diagnostic has to
be built by hand.

## The geocoding script, and why it is different

The R and Python geocoding scripts geocode against OpenStreetMap and spatially join
the points to 2010 tract boundaries. Stata has no geocoding client and no spatial
join built in, and the community commands that fill the gap need API keys or
shapefile handling of their own. So `geocode_to_tract.do` takes the other route
`r/README.md` describes: it writes the addresses to a batch file, sends it to the
Census Bureau's geocoder with `shell curl`, and reads back the result, which already
carries the 2010 tract code. It needs no boundary files and no spatial join, and it
takes a minute or two instead of half an hour. The output file and its columns match
the R and Python versions, so `linking_nanda_tract.do` takes it with one path change.

Expect to debug it. The Census call and the format of what it returns were checked
from the command line on a 15-row sample of the synthetic file, and that is the
format the read-result block parses. The `.do` file itself has not been run in Stata.
The likely trouble spots:

- **curl.** Windows 10 and later, macOS, and most Linux distributions ship it. If the
  `shell curl` line does nothing or errors, curl is not on the PATH Stata sees. The
  fallback is to upload `data/census_batch_in_1.csv` by hand at
  <https://geocoding.geo.census.gov/geocoder/geographies/addressbatch>, save the
  result as `data/census_batch_out_1.csv`, and run the script from the read-result
  block on.
- **`import delimited` on the result.** The geocoder returns rows in any order,
  unmatched rows with only three fields, and the coordinates as one quoted
  `"longitude,latitude"` field. The read-result block is written for all of that,
  and nobody has run it from inside Stata to confirm.
- **Match quality.** The Census Geocoder has no place rank. A `Match` is placed on its
  street segment, which is precise enough for a tract; `No_Match` and `Tie` get no
  tract. On the 15-row sample it placed 7 of the 12 rows that had a street address;
  OpenStreetMap placed 3 to 5, varying between runs.

If it fails and you cannot see why, run `r/geocode_to_tract.R` or
`python/geocode_to_tract.py` instead; the merge scripts in this folder read the output
either way.
