# Linking NaNDA With Your Data: the R code from the notebook, as one script.
# Each block carries the same label as the code block on the notebook page, so
# you can read the two side by side. This is the ZIP-to-ZCTA route, the one run
# live in the session. The same steps are in stata/ and python/; the tract
# route is linking_nanda_tract.R beside this file.
#
# Data: data/ holds the synthetic CSV and the crosswalk; data/nanda/ holds the
# NaNDA files you download from ICPSR yourself (see data/nanda/README.md).
# Open workshop.Rproj first so here::here() resolves the paths.


# ---- setup ----
library(tidyverse)   # dplyr for the joins, readr for the CSVs
library(readxl)      # the crosswalk is an .xlsx; installs with tidyverse, loads separately
library(here)        # file paths that work wherever this folder sits on your machine
library(janitor)     # tabyl(), for frequency tables you can read

# ---- read-data ----
# Our own data. `zip` is a label: say so, or read_csv guesses "number" and
# 03042 becomes 3042.
mydata <- read_csv(
  here("data", "synthetic_data_v20260924.csv"),
  col_types = cols(zip = col_character())
)

# NaNDA: Social Services, ZCTA 2010, 1990-2022. Same rule for the ZCTA code.
socialservices_zcta10 <- read_csv(
  here("data", "nanda", "nanda_socials_Zcta10_1990-2022_01.csv"),
  col_types = cols(zcta10 = col_character())
)

# Parks and Socioeconomic Status come from ICPSR as .rda files. load() drops an
# object into your session under a name ICPSR picked, and returns that name.
# Print it, then rename it to something you will recognise later.
print(load(here("data", "nanda", "38586-0002-Data.rda")))
# The object keeps Robert's name, parks2022. The file is the 2018 ParkServe
# snapshot (DS0002, 2010 boundaries); ICPSR retitled it in October 2026.
parks2022_zcta10 <- da38586.0002
rm(da38586.0002)

print(load(here("data", "nanda", "38528-0003-Data.rda")))   # SES, ZCTA 2010, 2008-2017
ses2008_2017_zcta10 <- da38528.0003
rm(da38528.0003)

print(load(here("data", "nanda", "38528-0008-Data.rda")))   # SES, ZCTA 2020, 2018-2022
ses2018_2022_zcta20 <- da38528.0008
rm(da38528.0008)

# ---- glimpse-data ----
glimpse(mydata)

# ---- inspect-identifiers ----
# Count the rows that have a ZIP.
mydata %>%
  summarise(
    rows        = n(),
    has_zip     = sum(!is.na(zip)),
    missing_zip = sum(is.na(zip)),
    pct_missing = round(100 * mean(is.na(zip)), 1)
  )

# ---- inspect-address ----
# address, city and zip are missing on different rows. A row with no ZIP may
# still have an address you could geocode, and the other way round, so the
# usable geography depends on the route.
mydata %>%
  count(
    address_missing = is.na(address),
    city_missing    = is.na(city),
    zip_missing     = is.na(zip)
  ) %>%
  arrange(desc(n))

# ---- read-crosswalk ----
# Every column as text, for the same reason as `zip` above. Then pad back to five
# characters: whatever stripped a leading zero upstream did it before we got here.
zipzctaxwalk2019 <- read_excel(
  here("data", "zip_to_zcta_2019.xlsx"),
  col_types = "text"
) %>%
  mutate(
    ZIP_CODE = str_pad(ZIP_CODE, 5, pad = "0"),
    ZCTA     = str_pad(ZCTA,     5, pad = "0")
  )

# zip_join_type records how each ZIP was assigned its ZCTA, or that it has
# none. Check it before joining.
tabyl(zipzctaxwalk2019, zip_join_type)

# ---- crosswalk-join ----
mydata_zcta10 <- mydata %>%
  left_join(
    zipzctaxwalk2019 %>% select(ZIP_CODE, ZCTA, zip_join_type),
    by = c("zip" = "ZIP_CODE")
  ) %>%
  rename(zcta10 = ZCTA, zip_join_type10 = zip_join_type)

# A left join keeps every row of the left-hand table. Compare the counts.
# If this number grew, the crosswalk has more than one row per ZIP and some
# people are now counted twice.
c(rows_before = nrow(mydata), rows_after = nrow(mydata_zcta10))

# A row can lack a ZCTA for two reasons. A row with no ZIP has nothing to look
# up. A row whose ZIP is missing from the crosswalk had a ZIP but no match: PO-box ZIPs, single-building ZIPs, ZIPs the USPS has retired.
mydata_zcta10 %>%
  mutate(zcta_status = case_when(
    is.na(zip)    ~ "no ZIP",
    is.na(zcta10) ~ "ZIP not in crosswalk",
    TRUE          ~ "has a ZCTA"
  )) %>%
  tabyl(zcta_status)

# ---- who-is-missing ----
# Compare the rows that matched with those that did not, on the variables the
# study is about.
mydata_zcta10 %>%
  group_by(has_zcta = !is.na(zcta10)) %>%
  summarise(
    n                 = n(),
    loneliness        = round(mean(loneliness,        na.rm = TRUE), 2),
    physical_activity = round(mean(physical_activity, na.rm = TRUE), 2),
    own_pet           = round(mean(own_pet,           na.rm = TRUE), 3),
    .groups = "drop"
  )

# ---- carry-forward ----
# complete() adds the missing ZCTA-year rows; fill() carries each ZCTA's last
# value down into them. fill() does not stop at 2022: any value missing inside
# 1990-2022 (population, and the densities where population is zero) also gets
# the year before.
socialservices_zcta10 <- socialservices_zcta10 %>%
  complete(zcta10, year = 1990:2025) %>%
  arrange(zcta10, year) %>%
  group_by(zcta10) %>%
  fill(everything(), .direction = "down") %>%
  ungroup()

# Every year from 2022 on should now carry the same values.
tabyl(socialservices_zcta10, year) %>% filter(year >= 2020)

# ---- join-nanda ----
mydata_nanda <- mydata_zcta10 %>%
  # Social Services is longitudinal, so the key is ZCTA *and* year.
  # `in_nanda` is added before the join: it is TRUE on every row of the NaNDA
  # side, so after the join it is TRUE where something matched and NA where
  # nothing did. Stata's `_merge` flags matched rows; here `in_nanda` does the
  # same.
  left_join(
    socialservices_zcta10 %>%
      select(zcta10, year, totpop, aland10,
             count_totindivfamilyservices, den_totindivfamilyservices,
             count_childyouthservices,     den_childyouthservices,
             count_elderservices,          den_elderservices) %>%
      mutate(in_nanda = TRUE),
    by = c("zcta10", "year")
  ) %>%
  mutate(in_nanda = coalesce(in_nanda, FALSE)) %>%
  # Parks is a single 2018 snapshot, so it joins on ZCTA alone and every year of
  # a person's records gets the same value. That assumes park provision held
  # still across the study period.
  left_join(
    parks2022_zcta10 %>%
      select(ZCTA19, ANY_OPEN_PARK, COUNT_OPEN_PARKS_TC10, PROP_PARK_AREA_ZCTA),
    by = c("zcta10" = "ZCTA19")
  )

c(rows_before = nrow(mydata_zcta10), rows_after = nrow(mydata_nanda))

# ---- ses-join ----
# The 2010-boundary file (DS0003) names its affluence measure for the ACS years
# behind it. Give it a plain name before joining.
mydata_nanda <- mydata_nanda %>%
  left_join(
    ses2008_2017_zcta10 %>%
      select(ZCTA10, AFFLUENCE13_17) %>%
      rename(AFFLUENCE = AFFLUENCE13_17),
    by = c("zcta10" = "ZCTA10")
  )

c(rows = nrow(mydata_nanda), with_affluence = sum(!is.na(mydata_nanda$AFFLUENCE)))

# ---- boundaries-2010 ----
# Socioeconomic Status, 2010-boundary file (ICPSR 38528, DS0003), joined to
# every row. Same rename as above: the two files call the same construct
# different things.
on_2010 <- mydata_zcta10 %>%
  left_join(
    ses2008_2017_zcta10 %>%
      select(ZCTA10, AFFLUENCE13_17) %>%
      rename(AFFLUENCE = AFFLUENCE13_17),
    by = c("zcta10" = "ZCTA10")
  )

on_2010 %>%
  summarise(
    rows           = n(),
    matched        = sum(!is.na(AFFLUENCE)),
    match_rate_pct = round(100 * mean(!is.na(AFFLUENCE)), 1),
    mean_affluence = round(mean(AFFLUENCE, na.rm = TRUE), 3)
  )

# ---- boundaries-2020 ----
# The same 2010-boundary codes, straight from the crosswalk, against the
# 2020-boundary file (ICPSR 38528, DS0008). The codes and the boundaries come
# from different censuses, and the join still returns a match rate and a mean.
on_2020 <- mydata_zcta10 %>%
  left_join(
    ses2018_2022_zcta20 %>% select(ZCTA20, AFFLUENCE),
    by = c("zcta10" = "ZCTA20")
  )

on_2020 %>%
  summarise(
    rows           = n(),
    matched        = sum(!is.na(AFFLUENCE)),
    match_rate_pct = round(100 * mean(!is.na(AFFLUENCE)), 1),
    mean_affluence = round(mean(AFFLUENCE, na.rm = TRUE), 3)
  )

# ---- boundaries-compare ----
bind_rows(
  `SES, ZCTA 2010 file` = on_2010,
  `SES, ZCTA 2020 file` = on_2020,
  .id = "nanda_file"
) %>%
  group_by(nanda_file) %>%
  summarise(
    rows           = n(),
    matched        = sum(!is.na(AFFLUENCE)),
    match_rate_pct = round(100 * mean(!is.na(AFFLUENCE)), 1),
    mean_affluence = round(mean(AFFLUENCE, na.rm = TRUE), 3),
    .groups = "drop"
  )

# ---- match-rate ----
# Overall match rate.
mydata_nanda %>%
  summarise(
    rows           = n(),
    matched        = sum(in_nanda),
    match_rate_pct = round(100 * mean(in_nanda), 1)
  )

# The same number, by year. 2023 onward matches because we carried Social
# Services forward; without that step these rows would show 0%.
mydata_nanda %>%
  group_by(year) %>%
  summarise(
    rows           = n(),
    matched        = sum(in_nanda),
    match_rate_pct = round(100 * mean(in_nanda), 1),
    .groups = "drop"
  )

# ---- anti-join ----
# anti_join() keeps the rows of the left table that found no partner: the
# complement of the join.
unmatched <- mydata_nanda %>%
  anti_join(
    socialservices_zcta10 %>% select(zcta10, year),
    by = c("zcta10", "year")
  )

# A row can fail for four different reasons, and each calls for a different
# response: the first two are a data-collection problem, the third is a
# coverage limit, the fourth is usually a boundary mismatch. Three occur in
# this file; the third cannot, because we carried Social Services forward.
# The case stays in the table in case that step is removed.
unmatched %>%
  mutate(reason = case_when(
    is.na(zip)    ~ "no ZIP to start from",
    is.na(zcta10) ~ "ZIP not in the crosswalk",
    year > 2022   ~ "year past NaNDA's coverage",
    TRUE          ~ "ZCTA not in the NaNDA file"
  )) %>%
  tabyl(reason)

# ---- toy-model ----
mydata_nanda <- mydata_nanda %>%
  mutate(count_totindivfamilyservices_6cat = cut(
    count_totindivfamilyservices,
    breaks = c(-1, 0, 1, 2, 3, 5, 10, Inf),
    labels = c("0", "1", "2", "3", "4-5", "6-10", "11+"),
    right = TRUE
  ))

own_pet_model <- glm(
  own_pet ~ hot_meal_days + count_totindivfamilyservices_6cat + ANY_OPEN_PARK + AFFLUENCE,
  data = mydata_nanda, family = binomial
)
summary(own_pet_model)

# ---- session-info ----
sessionInfo()
