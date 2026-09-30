# Data

Two kinds of file live here, and they are handled differently.

## Ships with the materials

These are redistributable and require no login. `make-zip.sh` refuses to build the
participant ZIP unless all three are present:

- `synthetic_data_v20260924.csv`: the synthetic dataset (2,004 rows, 2014–2025).
  No real people.
- `codebook_synthetic_data_v20260924.log`: its codebook.
- `zip_to_zcta_2019.xlsx`: UDS Mapper ZIP-to-ZCTA crosswalk, 2019 release
  (targets 2010 ZCTAs). This is the release Robert's script uses.

## Does not ship: `nanda/`

The NaNDA extracts come from ICPSR, which requires a free account, so we cannot
redistribute them. Participants download their own. See `nanda/README.md` for the
three downloads and where they go.

`data/nanda/*` is gitignored, `make-zip.sh` strips it out of the ZIP, and
`publish/make-public.sh` strips it out of the public repo. The folder and its README
survive all three, so the path the code reads from exists and explains itself.

Anyone rendering the site needs the ICPSR files present locally — the R chunks
execute. `_freeze` is tracked, so once someone renders with the files in place and
commits `_freeze`, the next person can rebuild the site without them.
