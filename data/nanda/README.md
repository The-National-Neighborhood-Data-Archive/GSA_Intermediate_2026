# The NaNDA files: download your own

**You only need these if you want to re-run the code.** The notebook page already
shows every output.

NaNDA is distributed through ICPSR, which requires a free account to download files.
That means we cannot include them in the ZIP. Downloading takes about five minutes.

## 1. Get an ICPSR account

Go to <https://www.icpsr.umich.edu/> and sign in. If you are at a university, sign in
through your institution; otherwise create a free account. Either works.

## 2. Download three files

Pick the **R** format if you are following along in R. Stata and delimited versions of
every file are on the same pages if you work in another language, and the variable
names are the same.

| # | Dataset | Link | What to take |
|---|---|---|---|
| 1 | NaNDA: Social Services, ZCTA | <https://doi.org/10.3886/ICPSR208207.V5> | the ZCTA 2010 file, `nanda_socials_Zcta10_1990-2022_01.csv` |
| 2 | NaNDA: Parks | <https://doi.org/10.3886/ICPSR38586> | **dataset 2** (DS0002), the ZCTA file |
| 3 | NaNDA: Socioeconomic Status | <https://doi.org/10.3886/ICPSR38528> | **datasets 3 and 8** (DS0003 and DS0008) |

Datasets 3 and 8 of Socioeconomic Status are both needed, and both are used in
Section 4: DS0003 is drawn on 2010 ZCTA boundaries (2008–2017), DS0008 on 2020 boundaries
(2018–2022). The notebook joins on the 2010 file and uses the 2020 file once, to
show what changes when boundaries are mixed.

ICPSR gives you a ZIP per study, with the data nested a few folders deep
(`ICPSR_38586/DS0002/…`). Unzip it and extract the data file; you do not need the rest
of what comes in the archive.

## 3. Put them here

Move the four data files into this folder, flat, with no subfolders:

```
data/nanda/
  nanda_socials_Zcta10_1990-2022_01.csv    Social Services   (ICPSR 208207)
  38586-0002-Data.rda                      Parks, DS0002     (ICPSR 38586)
  38528-0003-Data.rda                      SES, ZCTA 2010    (ICPSR 38528)
  38528-0008-Data.rda                      SES, ZCTA 2020    (ICPSR 38528)
```

The notebook reads them with `here::here("data", "nanda", …)`, so as long as you opened
`workshop.Rproj` the paths resolve no matter where the folder sits on your machine.

## If a filename does not match

ICPSR revises studies, and a new version can change a version number in a folder name
(`ICPSR_208207-V5` vs `-V5.1`) or, less often, a data filename. If your download does
not match the names above, use the file you actually got and edit the path in the
`read-data` chunk. The variable names inside are what the code depends on, and those
are stable.

## Tract-level files (for the tract scripts only)

The notebook and the live session use the ZCTA files above. The tract route
(`r/linking_nanda_tract.R` and its Stata and Python versions) reads the tract-level
files of the same three studies. Same ICPSR pages, different datasets:

| # | Dataset | Link | What to take |
|---|---|---|---|
| 1 | NaNDA: Social Services, tract | <https://doi.org/10.3886/ICPSR208207.V5> | the tract 2010 file, `nanda_socials_Tract10_1990-2022_01.csv` |
| 2 | NaNDA: Parks | <https://doi.org/10.3886/ICPSR38586> | **dataset 1** (DS0001), the tract file |
| 3 | NaNDA: Socioeconomic Status | <https://doi.org/10.3886/ICPSR38528> | **datasets 2 and 6** (DS0002 and DS0006), both on 2010 tract boundaries |

Put them in this same folder, flat, beside the ZCTA files:

```
data/nanda/
  nanda_socials_Tract10_1990-2022_01.csv   Social Services, tract   (ICPSR 208207)
  38586-0001-Data.rda                      Parks, DS0001            (ICPSR 38586)
  38528-0002-Data.rda                      SES, tract 2010, 2008-17 (ICPSR 38528)
  38528-0006-Data.rda                      SES, tract 2010, 2018-22 (ICPSR 38528)
```

Stata and Python take the `.dta` versions of the Parks and SES files, as for ZCTA.
The Social Services tract file is large (about 2.4 million rows, one per tract per
year); it reads in well under a minute in any of the three languages.

## Citing them

Cite the ICPSR datasets. Each DOI above resolves to a citation on the ICPSR
landing page.
