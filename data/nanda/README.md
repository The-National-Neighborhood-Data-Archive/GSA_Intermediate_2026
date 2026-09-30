# The NaNDA files: download your own

**You only need these if you want to re-run the code.** The walkthrough page already
shows every output. Nothing in the session depends on you having them.

NaNDA is distributed through ICPSR, which asks for a free account before it will hand
over a file. That means we cannot put these in the ZIP for you — but it takes about
five minutes, and the account is worth having anyway.

## 1. Get an ICPSR account

Go to <https://www.icpsr.umich.edu/> and sign in. If you are at a university, sign in
through your institution; otherwise create a free account. Either works.

## 2. Download three files

Pick the **R** format if you are following along in R. Stata and delimited versions of
every file are on the same pages if you work in another language — the variable names
are the same.

| # | Dataset | Link | What to take |
|---|---|---|---|
| 1 | NaNDA: Social Services, ZCTA | <https://doi.org/10.3886/ICPSR208207.V5> | the ZCTA 2010 file, `nanda_socials_Zcta10_1990-2022_01.csv` |
| 2 | NaNDA: Parks | <https://doi.org/10.3886/ICPSR38586> | **dataset 2** (DS0002), the ZCTA file |
| 3 | NaNDA: Socioeconomic Status | <https://doi.org/10.3886/ICPSR38528> | **datasets 3 and 8** (DS0003 and DS0008) |

Datasets 3 and 8 of Socioeconomic Status are both needed, and they are the point of
Section 3: DS0003 is ZCTA 2010 covering 2008–2017, DS0008 is ZCTA 2020 covering
2018–2022. The walkthrough joins the same ZCTA codes to both.

ICPSR gives you a ZIP per study, with the data nested a few folders deep
(`ICPSR_38586/DS0002/…`). Unzip it and dig the data file out; you do not need the rest
of what comes in the archive.

## 3. Put them here

Move the four data files into this folder, flat — no subfolders:

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

## Citing them

Cite the datasets, not this folder. Each DOI above resolves to a citation on the ICPSR
landing page.
