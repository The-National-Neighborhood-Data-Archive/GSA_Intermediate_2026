"""Linking NaNDA With Your Data: the Python version of the walkthrough.

Each block carries the same label as the code block on the walkthrough page,
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
# Our own data. `zip` is a label, not a quantity: say so, or pandas guesses
# "number" and 03042 silently becomes 3042.
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
# How many rows carry a ZIP we can actually look something up with?
pd.Series({
    "rows":        len(mydata),
    "has_zip":     mydata["zip"].notna().sum(),
    "missing_zip": mydata["zip"].isna().sum(),
    "pct_missing": round(100 * mydata["zip"].isna().mean(), 1),
})

# ---- inspect-address ----
# address, city and zip are each incomplete, and not for the same rows. A row
# with no ZIP may still have an address you could geocode, and the other way
# round, so "how much geography do I have" depends on which route you take.
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

# zip_join_type is the crosswalk telling you how each ZIP got its ZCTA, or that
# it has none. Read this before you join, not after something looks wrong.
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

# A left join keeps every row of the left-hand table. Check it; don't assume it.
# If this number grew, the crosswalk has more than one row per ZIP and you have
# quietly duplicated people.
{"rows_before": len(mydata), "rows_after": len(mydata_zcta10)}

# Two different failures, worth keeping apart. A row with no ZIP never had
# anything to look up. A row whose ZIP is missing from the crosswalk had one,
# and it led nowhere: PO-box ZIPs, single-building ZIPs, retired ZIPs.
import numpy as np
mydata_zcta10.assign(zcta_status=np.select(
    [mydata_zcta10["zip"].isna(), mydata_zcta10["zcta10"].isna()],
    ["no ZIP", "ZIP not in crosswalk"], default="has a ZCTA",
))["zcta_status"].value_counts()

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
# merge(indicator=True) is the diagnostic Stata hands you as _merge: "both"
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
    # of a person's records gets the same value. That is an assumption, that
    # park provision held still across the study period, not a free lunch.
    .merge(
        parks2022_zcta10[["ZCTA19", "ANY_OPEN_PARK", "COUNT_OPEN_PARKS_TC10", "PROP_PARK_AREA_ZCTA"]],
        how="left", left_on="zcta10", right_on="ZCTA19",
    )
    .drop(columns="ZCTA19")
)

{"rows_before": len(mydata_zcta10), "rows_after": len(mydata_nanda)}

# ---- ses-split ----
# The two files name the affluence measure differently; give them one name
# before stacking.
ses2010 = ses2008_2017_zcta10[["ZCTA10", "AFFLUENCE13_17"]].rename(
    columns={"ZCTA10": "zcta10", "AFFLUENCE13_17": "AFFLUENCE"})
ses2020 = ses2018_2022_zcta20[["ZCTA20", "AFFLUENCE"]].rename(columns={"ZCTA20": "zcta10"})

# Note: ZIP codes and ZCTAs can change geographically over time. The 2018-on
# half joins 2010-vintage codes from the crosswalk to a file drawn on 2020 ZCTAs.
mydata_nanda = pd.concat([
    mydata_nanda[mydata_nanda["year"] <= 2017].merge(ses2010, how="left", on="zcta10"),
    mydata_nanda[mydata_nanda["year"] >= 2018].merge(ses2020, how="left", on="zcta10"),
], ignore_index=True)

{"rows": len(mydata_nanda), "with_affluence": mydata_nanda["AFFLUENCE"].notna().sum()}

# ---- vintage-2010 ----
# Socioeconomic Status, ZCTA 2010 file (ICPSR 38528, DS0003). Its affluence
# measure is named for the ACS years behind it, so rename it to a common name
# now: the two files we are comparing call the same construct different things.
vintage_2010 = mydata_zcta10.merge(
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

match_summary(vintage_2010)

# ---- vintage-2020 ----
# The same ZCTA codes, 2010-vintage codes straight from the crosswalk above,
# against the ZCTA 2020 file (ICPSR 38528, DS0008). Nothing in this join knows
# that the codes and the geography come from different censuses. It runs, it
# matches, it returns a number.
vintage_2020 = mydata_zcta10.merge(
    ses2018_2022_zcta20[["ZCTA20", "AFFLUENCE"]],
    how="left", left_on="zcta10", right_on="ZCTA20",
).drop(columns="ZCTA20")

match_summary(vintage_2020)

# ---- vintage-compare ----
pd.concat(
    {"SES, ZCTA 2010 file": vintage_2010, "SES, ZCTA 2020 file": vintage_2020},
    names=["nanda_file"],
).groupby(level="nanda_file").apply(match_summary)

# ---- match-rate ----
# The headline.
pd.Series({
    "rows":           len(mydata_nanda),
    "matched":        mydata_nanda["in_nanda"].sum(),
    "match_rate_pct": round(100 * mydata_nanda["in_nanda"].mean(), 1),
})

# The same number, by year, which is where it stops being a headline. 2023
# onward matches because we carried Social Services forward; without that step
# these rows would show 0%.
(mydata_nanda.groupby("year")["in_nanda"]
   .agg(rows="size", matched="sum", match_rate_pct=lambda s: round(100 * s.mean(), 1))
   .reset_index())

# ---- anti-join ----
# The rows that found no partner: the complement of the join, and the half
# nobody looks at. indicator="left_only" is the anti-join.
unmatched = (
    mydata_nanda.merge(
        socialservices_zcta10[["zcta10", "year"]].drop_duplicates(),
        how="left", on=["zcta10", "year"], indicator=True,
    )
    .query('_merge == "left_only"')
    .drop(columns="_merge")
)

# A count is not a diagnosis. A row can fail for four different reasons, and
# the reasons call for different answers: the first two are a data-collection
# problem, the third is a coverage limit you state in your methods, the fourth
# is usually a vintage mismatch. Three occur in this file; the third cannot,
# because we carried Social Services forward. It is named so the table says
# so if that step is ever dropped.
unmatched.assign(reason=np.select(
    [unmatched["zip"].isna(), unmatched["zcta10"].isna(), unmatched["year"] > 2022],
    ["no ZIP to start from", "ZIP not in the crosswalk", "year past NaNDA's coverage"],
    default="ZCTA not in the NaNDA file",
))["reason"].value_counts()

# ---- who-is-missing ----
# The question a match rate cannot answer: are the people who fell out different
# from the people who stayed, on the things the study is actually about?
(mydata_nanda.groupby("in_nanda")
   .agg(n=("in_nanda", "size"),
        loneliness=("loneliness", "mean"),
        physical_activity=("physical_activity", "mean"),
        own_pet=("own_pet", "mean"))
   .round({"loneliness": 2, "physical_activity": 2, "own_pet": 3})
   .reset_index())

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

