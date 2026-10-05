"""Linking NaNDA With Your Data: the tract route, in Python.

The notebook and the live session join on ZIP-to-ZCTA. This script is the same
merge with a different key: a 2010 Census tract ID already on your data. Where
that ID comes from (a geocoder, a data vendor, a survey file that carries it) is
your choice and is not covered here; r/README.md lists the usual sources. Block
labels match the notebook where the step is the same, so you can read the two
side by side. Not demonstrated live.

Data: data/synthetic_data_v20260924_tract10.csv is the synthetic dataset with a
tract_fips10 column added (synthetic too; see r/README.md). data/nanda/ holds
the tract-level NaNDA files you download from ICPSR yourself (data/nanda/README.md,
"Tract-level files"). Take the Stata-format downloads for Parks and Socioeconomic
Status; pandas reads .dta files natively. Requires pandas, numpy; the last step
also wants statsmodels and skips itself if that is missing.
"""

# ---- setup ----
import numpy as np
import pandas as pd            # data frames, read_csv / read_stata / merge
from pathlib import Path       # file paths that work wherever this folder sits

# The workshop folder: the one holding workshop.Rproj. Adjust if you moved the script.
ROOT = Path(__file__).resolve().parents[1] if "__file__" in globals() else Path.cwd()
DATA = ROOT / "data"

# ---- read-data ----
# tract_fips10 is state (2) + county (3) + tract (6): eleven characters, and the
# first can be a zero. Read it as text, or Alabama's tracts lose a digit.
mydata_tract10 = pd.read_csv(
    DATA / "synthetic_data_v20260924_tract10.csv",
    dtype={"zip": str, "tract_fips10": str},
)
mydata_tract10["tract_fips10"] = mydata_tract10["tract_fips10"].str.zfill(11)

# NaNDA: Social Services, tract 2010, 1990-2022. Same rule for the tract ID.
socialservices_tract10 = pd.read_csv(
    DATA / "nanda" / "nanda_socials_Tract10_1990-2022_01.csv", dtype={"tract_fips10": str}
)
socialservices_tract10["tract_fips10"] = socialservices_tract10["tract_fips10"].str.zfill(11)

# Parks and Socioeconomic Status: take the Stata format from ICPSR; pandas reads
# it without extra packages. The .dta may hold the tract ID as a number; force
# eleven-character text everywhere before joining.
def tract_text(df, col):
    df[col] = df[col].astype(str).str.replace(r"\.0$", "", regex=True).str.zfill(11)
    return df

parks2022_tract10    = tract_text(pd.read_stata(DATA / "nanda" / "38586-0001-Data.dta"), "TRACT_FIPS10")
ses2008_2017_tract10 = tract_text(pd.read_stata(DATA / "nanda" / "38528-0002-Data.dta"), "TRACT_FIPS10")
ses2018_2022_tract10 = tract_text(pd.read_stata(DATA / "nanda" / "38528-0006-Data.dta"), "TRACT_FIPS10")

# ---- glimpse-data ----
mydata_tract10.info()
mydata_tract10.head()

# ---- inspect-identifiers ----
# Count the rows that have a tract ID.
pd.Series({
    "rows":          len(mydata_tract10),
    "has_tract":     mydata_tract10["tract_fips10"].notna().sum(),
    "missing_tract": mydata_tract10["tract_fips10"].isna().sum(),
    "pct_missing":   round(100 * mydata_tract10["tract_fips10"].isna().mean(), 1),
})

# Every ID that is present should be eleven characters. Any other length means
# the ID was altered before it reached you, often by a spreadsheet.
mydata_tract10["tract_fips10"].dropna().str.len().value_counts()

# ---- who-is-missing ----
# Compare the rows that matched with those that did not, on the variables the
# study is about.
(mydata_tract10.assign(has_tract=mydata_tract10["tract_fips10"].notna())
   .groupby("has_tract")
   .agg(n=("has_tract", "size"),
        loneliness=("loneliness", "mean"),
        physical_activity=("physical_activity", "mean"),
        own_pet=("own_pet", "mean"))
   .round({"loneliness": 2, "physical_activity": 2, "own_pet": 3})
   .reset_index())

# ---- carry-forward ----
# pandas has no complete(); every tract here has a 2022 row, so copy it to
# 2023-2025. Then carry each tract's last value down into anything still
# missing. Like R's fill(), that also reaches values missing inside 1990-2022
# (population, and densities where population is zero).
ss_2022 = socialservices_tract10[socialservices_tract10["year"] == 2022]
socialservices_tract10 = (
    pd.concat([socialservices_tract10] + [ss_2022.assign(year=y) for y in (2023, 2024, 2025)])
    .sort_values(["tract_fips10", "year"])
    .reset_index(drop=True)
)
cols = socialservices_tract10.columns.drop("tract_fips10")
socialservices_tract10[cols] = socialservices_tract10.groupby("tract_fips10")[cols].ffill()

# Every year from 2022 on should now carry the same values.
socialservices_tract10.loc[socialservices_tract10["year"] >= 2020, "year"].value_counts().sort_index()

# ---- join-nanda ----
# Social Services is longitudinal, so the key is tract *and* year.
# merge(indicator=True) does what Stata's _merge does: "both"
# where something matched, "left_only" where nothing did. Keep it as in_nanda.
mydata_nanda = (
    mydata_tract10.merge(
        socialservices_tract10[[
            "tract_fips10", "year", "totpop", "aland10",
            "count_totindivfamilyservices", "den_totindivfamilyservices",
            "count_childyouthservices",     "den_childyouthservices",
            "count_elderservices",          "den_elderservices",
        ]],
        how="left", on=["tract_fips10", "year"], indicator=True,
    )
    .assign(in_nanda=lambda d: d["_merge"].eq("both"))
    .drop(columns="_merge")
    # Parks is a single 2022 snapshot, so it joins on tract alone and every year
    # of a person's records gets the same value. That assumes park provision
    # held still across the study period.
    .merge(
        parks2022_tract10[["TRACT_FIPS10", "ANY_OPEN_PARK", "COUNT_OPEN_PARKS_TC10", "PROP_PARK_AREA_TRACT"]],
        how="left", left_on="tract_fips10", right_on="TRACT_FIPS10",
    )
    .drop(columns="TRACT_FIPS10")
)

{"rows_before": len(mydata_tract10), "rows_after": len(mydata_nanda)}

# ---- ses-join ----
# At the tract level NaNDA has Socioeconomic Status on 2010 boundaries for both
# periods: DS0002 (2008-2017) and DS0006 (2018-2022). So the rows split at 2018,
# each period takes its own file, and the two halves stack back together. The
# ZCTA route cannot do this, because its 2018-2022 file is drawn on 2020
# boundaries; that is why the notebook joins one file to every row instead.
# The 2008-2017 file names its affluence measure for the ACS years behind it.
# Give it the plain name before stacking.
rows_before = len(mydata_nanda)

le2017 = mydata_nanda[mydata_nanda["year"] <= 2017].merge(
    ses2008_2017_tract10[["TRACT_FIPS10", "AFFLUENCE13_17"]].rename(columns={"AFFLUENCE13_17": "AFFLUENCE"}),
    how="left", left_on="tract_fips10", right_on="TRACT_FIPS10",
)
ge2018 = mydata_nanda[mydata_nanda["year"] >= 2018].merge(
    ses2018_2022_tract10[["TRACT_FIPS10", "AFFLUENCE"]],
    how="left", left_on="tract_fips10", right_on="TRACT_FIPS10",
)
mydata_nanda = (
    pd.concat([le2017, ge2018])
    .drop(columns="TRACT_FIPS10")
    .sort_values(["sampleid", "year"])
    .reset_index(drop=True)
)

# A split-and-stack can lose rows (a missing year falls through both filters)
# or gain them (a duplicate tract in a NaNDA file). Compare the counts.
{"rows_before": rows_before, "rows_after": len(mydata_nanda),
 "with_affluence": mydata_nanda["AFFLUENCE"].notna().sum()}

# ---- match-rate ----
# Overall match rate.
pd.Series({
    "rows":           len(mydata_nanda),
    "matched":        mydata_nanda["in_nanda"].sum(),
    "match_rate_pct": round(100 * mydata_nanda["in_nanda"].mean(), 1),
})

# The same number, by year. 2023 onward matches because we carried Social
# Services forward; without that step these rows would show 0%.
(mydata_nanda.groupby("year")["in_nanda"]
   .agg(rows="size", matched="sum", match_rate_pct=lambda s: round(100 * s.mean(), 1))
   .reset_index())

# ---- anti-join ----
# The rows that found no partner: the complement of the join.
# indicator="left_only" is the anti-join.
unmatched = (
    mydata_nanda.merge(
        socialservices_tract10[["tract_fips10", "year"]].drop_duplicates(),
        how="left", on=["tract_fips10", "year"], indicator=True,
    )
    .query('_merge == "left_only"')
    .drop(columns="_merge")
)

# A row can fail for three different reasons here, and each calls for a
# different response: the first is a data-collection or geocoding problem, the
# second is a coverage limit, the third is usually a boundary mismatch (a 2020
# tract ID against a 2010 file). The second cannot occur in this file, because
# we carried Social Services forward. The case stays in the table in case that
# step is removed.
unmatched.assign(reason=np.select(
    [unmatched["tract_fips10"].isna(), unmatched["year"] > 2022],
    ["no tract ID to start from", "year past NaNDA's coverage"],
    default="tract not in the NaNDA file",
))["reason"].value_counts()

# ---- toy-model ----
mydata_nanda["count_totindivfamilyservices_6cat"] = pd.cut(
    mydata_nanda["count_totindivfamilyservices"],
    bins=[-1, 0, 1, 2, 3, 5, 10, np.inf],
    labels=["0", "1", "2", "3", "4-5", "6-10", "11+"],
)

# pandas has no models. statsmodels is the one extra package this step needs
# (pip install statsmodels); everything above runs without it.
try:
    import statsmodels.formula.api as smf
except ImportError:
    smf = None
    print("statsmodels is not installed; skipping the toy model.")

if smf is not None:
    own_pet_model = smf.logit(
        "own_pet ~ hot_meal_days + C(count_totindivfamilyservices_6cat) + C(ANY_OPEN_PARK) + AFFLUENCE",
        data=mydata_nanda.dropna(subset=["count_totindivfamilyservices_6cat", "ANY_OPEN_PARK", "AFFLUENCE"]),
    ).fit()
    print(own_pet_model.summary())

# ---- session-info ----
import sys
print(sys.version)
print("pandas", pd.__version__, "| numpy", np.__version__)
