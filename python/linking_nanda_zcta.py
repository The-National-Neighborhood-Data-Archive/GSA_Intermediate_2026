"""Linking NaNDA With Your Data: the Python version of the notebook.

Each block carries the same label as the code block on the notebook page,
so you can read the two side by side. The session is run in R; this file is
the same steps in pandas, step for step. Not demonstrated live.

Data: data/ holds the synthetic CSV and the crosswalk; data/nanda/ holds the
NaNDA files you download from ICPSR yourself (see data/nanda/README.md).
Take the Stata-format downloads for Parks and Socioeconomic Status; pandas
reads .dta files natively. Requires pandas, numpy, openpyxl; the last step
also wants statsmodels and skips itself if that is missing.
"""

# ---- setup ----
import pandas as pd            # data frames, read_csv / read_stata / merge
from pathlib import Path       # file paths that work wherever this folder sits

# The workshop folder: the one holding workshop.Rproj. Adjust if you moved the script.
ROOT = Path(__file__).resolve().parents[1] if "__file__" in globals() else Path.cwd()
DATA = ROOT / "data"

# ---- read-data ----
# Our own data. `zip` is a label: say so, or pandas guesses "number" and
# 03042 becomes 3042.
mydata = pd.read_csv(DATA / "synthetic_data_v20260924.csv", dtype={"zip": str})

# NaNDA: Social Services, ZCTA 2010, 1990-2022. Same rule for the ZCTA code.
socialservices_zcta10 = pd.read_csv(
    DATA / "nanda" / "nanda_socials_Zcta10_1990-2022_01.csv", dtype={"zcta10": str}
)

# Parks and Socioeconomic Status: take the Stata format from ICPSR; pandas reads
# it without extra packages. Force every ZCTA code to five-character text.
def zcta_text(df, col):
    df[col] = df[col].astype(str).str.replace(r"\.0$", "", regex=True).str.zfill(5)
    return df

parks2022_zcta10    = zcta_text(pd.read_stata(DATA / "nanda" / "38586-0002-Data.dta"), "ZCTA19")
ses2008_2017_zcta10 = zcta_text(pd.read_stata(DATA / "nanda" / "38528-0003-Data.dta"), "ZCTA10")
ses2018_2022_zcta20 = zcta_text(pd.read_stata(DATA / "nanda" / "38528-0008-Data.dta"), "ZCTA20")

# ---- glimpse-data ----
mydata.info()
mydata.head()

# ---- inspect-identifiers ----
# Count the rows that have a ZIP.
pd.Series({
    "rows":        len(mydata),
    "has_zip":     mydata["zip"].notna().sum(),
    "missing_zip": mydata["zip"].isna().sum(),
    "pct_missing": round(100 * mydata["zip"].isna().mean(), 1),
})

# ---- inspect-address ----
# address, city and zip are missing on different rows. A row with no ZIP may
# still have an address you could geocode, and the other way round, so the
# usable geography depends on the route.
(mydata
   .assign(address_missing=mydata["address"].isna(),
           city_missing=mydata["city"].isna(),
           zip_missing=mydata["zip"].isna())
   .value_counts(["address_missing", "city_missing", "zip_missing"])
   .rename("n")
   .reset_index()
   .sort_values("n", ascending=False))

# ---- read-crosswalk ----
# Every column as text, for the same reason as `zip` above. Then pad back to
# five characters: whatever stripped a leading zero upstream did it before we
# got here. (read_excel needs the openpyxl package: pip install openpyxl)
zipzctaxwalk2019 = pd.read_excel(DATA / "zip_to_zcta_2019.xlsx", dtype=str)
zipzctaxwalk2019["ZIP_CODE"] = zipzctaxwalk2019["ZIP_CODE"].str.zfill(5)
zipzctaxwalk2019["ZCTA"]     = zipzctaxwalk2019["ZCTA"].str.zfill(5)

# zip_join_type records how each ZIP was assigned its ZCTA, or that it has
# none. Check it before joining.
zipzctaxwalk2019["zip_join_type"].value_counts(dropna=False)

# ---- crosswalk-join ----
mydata_zcta10 = (
    mydata.merge(
        zipzctaxwalk2019[["ZIP_CODE", "ZCTA", "zip_join_type"]],
        how="left", left_on="zip", right_on="ZIP_CODE",
    )
    .drop(columns="ZIP_CODE")
    .rename(columns={"ZCTA": "zcta10", "zip_join_type": "zip_join_type10"})
)

# A left join keeps every row of the left-hand table. Compare the counts.
# If this number grew, the crosswalk has more than one row per ZIP and some
# people are now counted twice.
{"rows_before": len(mydata), "rows_after": len(mydata_zcta10)}

# A row can lack a ZCTA for two reasons. A row with no ZIP has nothing to look
# up. A row whose ZIP is missing from the crosswalk had a ZIP but no match: PO-box ZIPs, single-building ZIPs, retired ZIPs.
import numpy as np
mydata_zcta10.assign(zcta_status=np.select(
    [mydata_zcta10["zip"].isna(), mydata_zcta10["zcta10"].isna()],
    ["no ZIP", "ZIP not in crosswalk"], default="has a ZCTA",
))["zcta_status"].value_counts()

# ---- who-is-missing ----
# Compare the rows that matched with those that did not, on the variables the
# study is about.
(mydata_zcta10.assign(has_zcta=mydata_zcta10["zcta10"].notna())
   .groupby("has_zcta")
   .agg(n=("has_zcta", "size"),
        loneliness=("loneliness", "mean"),
        physical_activity=("physical_activity", "mean"),
        own_pet=("own_pet", "mean"))
   .round({"loneliness": 2, "physical_activity": 2, "own_pet": 3})
   .reset_index())

# ---- carry-forward ----
# pandas has no complete(); every ZCTA here has a 2022 row, so copy it to
# 2023-2025. Then carry each ZCTA's last value down into anything still missing.
# Like R's fill(), that also reaches values missing inside 1990-2022
# (population, and densities where population is zero).
ss_2022 = socialservices_zcta10[socialservices_zcta10["year"] == 2022]
socialservices_zcta10 = (
    pd.concat([socialservices_zcta10] + [ss_2022.assign(year=y) for y in (2023, 2024, 2025)])
    .sort_values(["zcta10", "year"])
    .reset_index(drop=True)
)
cols = socialservices_zcta10.columns.drop("zcta10")
socialservices_zcta10[cols] = socialservices_zcta10.groupby("zcta10")[cols].ffill()

# Every year from 2022 on should now carry the same values.
socialservices_zcta10.loc[socialservices_zcta10["year"] >= 2020, "year"].value_counts().sort_index()

# ---- join-nanda ----
# Social Services is longitudinal, so the key is ZCTA *and* year.
# merge(indicator=True) does what Stata's _merge does: "both"
# where something matched, "left_only" where nothing did. Keep it as in_nanda.
mydata_nanda = (
    mydata_zcta10.merge(
        socialservices_zcta10[[
            "zcta10", "year", "totpop", "aland10",
            "count_totindivfamilyservices", "den_totindivfamilyservices",
            "count_childyouthservices",     "den_childyouthservices",
            "count_elderservices",          "den_elderservices",
        ]],
        how="left", on=["zcta10", "year"], indicator=True,
    )
    .assign(in_nanda=lambda d: d["_merge"].eq("both"))
    .drop(columns="_merge")
    # Parks is a single 2022 snapshot, so it joins on ZCTA alone and every year
    # of a person's records gets the same value. That assumes park provision
    # held still across the study period.
    .merge(
        parks2022_zcta10[["ZCTA19", "ANY_OPEN_PARK", "COUNT_OPEN_PARKS_TC10", "PROP_PARK_AREA_ZCTA"]],
        how="left", left_on="zcta10", right_on="ZCTA19",
    )
    .drop(columns="ZCTA19")
)

{"rows_before": len(mydata_zcta10), "rows_after": len(mydata_nanda)}

# ---- ses-join ----
# The 2010-boundary file (DS0003) names its affluence measure for the ACS years
# behind it. Give it a plain name before merging. The 2020-boundary file is
# trimmed the same way here, for the comparison below only.
ses2010 = ses2008_2017_zcta10[["ZCTA10", "AFFLUENCE13_17"]].rename(
    columns={"ZCTA10": "zcta10", "AFFLUENCE13_17": "AFFLUENCE"})
ses2020 = ses2018_2022_zcta20[["ZCTA20", "AFFLUENCE"]].rename(columns={"ZCTA20": "zcta10"})

mydata_nanda = mydata_nanda.merge(ses2010, how="left", on="zcta10")

{"rows": len(mydata_nanda), "with_affluence": mydata_nanda["AFFLUENCE"].notna().sum()}

# ---- boundaries-2010 ----
# Socioeconomic Status, 2010-boundary file (ICPSR 38528, DS0003), joined to
# every row. Same rename as above: the two files call the same construct
# different things.
on_2010 = mydata_zcta10.merge(
    ses2008_2017_zcta10[["ZCTA10", "AFFLUENCE13_17"]].rename(columns={"AFFLUENCE13_17": "AFFLUENCE"}),
    how="left", left_on="zcta10", right_on="ZCTA10",
).drop(columns="ZCTA10")

def match_summary(df):
    return pd.Series({
        "rows":           len(df),
        "matched":        df["AFFLUENCE"].notna().sum(),
        "match_rate_pct": round(100 * df["AFFLUENCE"].notna().mean(), 1),
        "mean_affluence": round(df["AFFLUENCE"].mean(), 3),
    })

match_summary(on_2010)

# ---- boundaries-2020 ----
# The same 2010-boundary codes, straight from the crosswalk, against the
# 2020-boundary file (ICPSR 38528, DS0008). The codes and the boundaries come
# from different censuses, and the join still returns a match rate and a mean.
on_2020 = mydata_zcta10.merge(
    ses2018_2022_zcta20[["ZCTA20", "AFFLUENCE"]],
    how="left", left_on="zcta10", right_on="ZCTA20",
).drop(columns="ZCTA20")

match_summary(on_2020)

# ---- boundaries-compare ----
pd.concat(
    {"SES, ZCTA 2010 file": on_2010, "SES, ZCTA 2020 file": on_2020},
    names=["nanda_file"],
).groupby(level="nanda_file").apply(match_summary)

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
        socialservices_zcta10[["zcta10", "year"]].drop_duplicates(),
        how="left", on=["zcta10", "year"], indicator=True,
    )
    .query('_merge == "left_only"')
    .drop(columns="_merge")
)

# A row can fail for four different reasons, and each calls for a different
# response: the first two are a data-collection problem, the third is a
# coverage limit, the fourth is usually a boundary mismatch. Three occur in
# this file; the third cannot, because we carried Social Services forward.
# The case stays in the table in case that step is removed.
unmatched.assign(reason=np.select(
    [unmatched["zip"].isna(), unmatched["zcta10"].isna(), unmatched["year"] > 2022],
    ["no ZIP to start from", "ZIP not in the crosswalk", "year past NaNDA's coverage"],
    default="ZCTA not in the NaNDA file",
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
