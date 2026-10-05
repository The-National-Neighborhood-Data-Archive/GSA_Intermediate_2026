# Stata version

The live session is in R. These `.do` files do the same thing, step for step, for
participants who work in Stata. Each ZCTA step also appears on the notebook page, in
the Stata tab beside the R version.

| File | Key | What it is |
|---|---|---|
| `linking_nanda_zcta.do` | ZIP code, crosswalked to a 2010 ZCTA | The notebook's steps. This is the route the session runs. |
| `linking_nanda_tract.do` | A 2010 Census tract ID already on your data | The same merge with a different key. Where the ID comes from is covered in `r/README.md`. |

The scripts use the same section headers as the R scripts (`* ---- setup ----`,
`* ---- read-data ----`, and so on), so a block in one language lines up with the same
block in `r/` and `python/`.

Both take the Stata-format downloads from ICPSR; `data/nanda/README.md` lists them
for each route. Run from the workshop folder (the one holding `workshop.Rproj`) so the
relative paths resolve.

Stata's `merge` creates a `_merge` variable automatically. R's joins drop and
duplicate unmatched rows without any message, so in R the Section 3 diagnostic has to
be built by hand.
