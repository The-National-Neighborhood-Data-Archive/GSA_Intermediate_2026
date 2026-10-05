# Linking NaNDA With Your Data

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.23071407.svg)](https://doi.org/10.5281/zenodo.23071407)

Materials for **Breakout 2 (Intermediate)** of *Using Neighborhood Data in Aging
Research: the National Neighborhood Data Archive (NaNDA)*, a workshop at the GSA 2026
Annual Scientific Meeting, online, October 7, 2026.

**Start here:** https://the-national-neighborhood-data-archive.github.io/GSA_Intermediate_2026/

You don't need to run anything. The notebook page shows every step with its output,
in R, with the same step in Stata and Python one tab away. If you'd like to run it
yourself, the materials ZIP on the site has the synthetic data, the crosswalk, the
notebook source with R, Stata and Python scripts for both routes, and an offline copy of the
site. The NaNDA files come from ICPSR (free account); the steps are on the site.

| Path | What it is |
|---|---|
| `index.qmd` | Before you begin: what to expect, optional setup |
| `notebook.qmd` | The notebook |
| `data/` | Synthetic dataset, codebook, ZIP-to-ZCTA crosswalk; `data/nanda/README.md` has the ICPSR download steps |
| `r/`, `stata/`, `python/` | The notebook's steps as standalone scripts, three per language: the ZIP-to-ZCTA route the session runs, a tract route for data that already carries a 2010 tract ID, and a geocoding script that gets a tract ID from a street address (the step Section 2 explains and does not run). Each folder's README says what its scripts need |

## Building it yourself

Install [Quarto](https://quarto.org/) and R with the packages listed on the
before-you-begin page, then `quarto render`. The rendered outputs are cached in
`_freeze/`, so the page builds without the NaNDA files; to re-execute the code, put
the ICPSR downloads in `data/nanda/` first (its README says which ones).

## Citing

Clary, W., Melendez, R., Noppert, G., Gypin, L., & Clarke, P. (2026). *Linking NaNDA
With Your Data: GSA 2026 workshop materials* (Version 1.0.0) [Workshop materials].
National Neighborhood Data Archive, Institute for Social Research, University of
Michigan. https://doi.org/10.5281/zenodo.23071407

```bibtex
@misc{clary2026linking,
  author    = {Clary, William and Melendez, Robert and Noppert, Grace and
               Gypin, Lindsay and Clarke, Philippa},
  title     = {Linking {NaNDA} With Your Data: {GSA} 2026 workshop materials},
  year      = {2026},
  version   = {1.0.0},
  publisher = {National Neighborhood Data Archive, Institute for Social Research,
               University of Michigan},
  doi       = {10.5281/zenodo.23071407},
  url       = {https://the-national-neighborhood-data-archive.github.io/GSA_Intermediate_2026/}
}
```

The DOI is the concept DOI and always resolves to the latest version. `CITATION.cff`
carries the same metadata for citation managers and GitHub's "Cite this repository"
button.

## Presenters

Robert Melendez, [Will Clary](https://github.com/w-clary), and Grace Noppert,
National Neighborhood Data Archive, Institute for Social Research, University of
Michigan.

## Sources

- NaNDA: Social Services. https://doi.org/10.3886/ICPSR208207.V5
- NaNDA: Parks. https://doi.org/10.3886/ICPSR38586
- NaNDA: Socioeconomic Status. https://doi.org/10.3886/ICPSR38528
- Chenoweth, M. & Khan, A. (2024). *Code for merging National Neighborhood Data
  Archive ZCTA level datasets with the UDS Mapper ZIP code to ZCTA crosswalk.*
  ICPSR. https://doi.org/10.3886/E124461V4
- John Snow, Inc. (2019). *ZIP Code to ZCTA Crosswalk, 2019 release.* UDS Mapper (site retired). Internet Archive capture of 2 April 2022: <https://web.archive.org/web/20220402144231/https://udsmapper.org/wp-content/uploads/2021/12/ZIPCodetoZCTACrosswalk2019.xlsx>. Included in the materials ZIP as `data/zip_to_zcta_2019.xlsx`; the current release is published by HRSA.
  https://udsmapper.org/zip-code-to-zcta-crosswalk/

Code is MIT; prose and documentation are CC BY 4.0.
