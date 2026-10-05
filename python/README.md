# Python version

The live session is in R. These `.py` scripts do the same thing, step for step, for
participants who work in Python. Each ZCTA step also appears on the notebook page, in
the Python tab beside the R version.

| File | Key | What it is |
|---|---|---|
| `linking_nanda_zcta.py` | ZIP code, crosswalked to a 2010 ZCTA | The notebook's steps. This is the route the session runs. |
| `linking_nanda_tract.py` | A 2010 Census tract ID already on your data | The same merge with a different key. Where the ID comes from is covered in `r/README.md`. |

The scripts use the same section headers as the R scripts (`# ---- setup ----`,
`# ---- read-data ----`, and so on), so a block in one language lines up with the same
block in `r/` and `stata/`.

Both take the Stata-format downloads from ICPSR (pandas reads `.dta` natively);
`data/nanda/README.md` lists them for each route. Requires pandas, numpy, and openpyxl
for the crosswalk. The toy model also needs statsmodels and is skipped if it is missing.

Every identifier column is read with an explicit `dtype=str`, the same leading-zero
pitfall described in Section 0 of the notebook. The joins use `merge(..., indicator=True)`,
so the Section 3 match-rate diagnostic comes from the join itself, as with Stata's
`_merge`.
