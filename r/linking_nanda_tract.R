# Linking NaNDA With Your Data: the tract route, in R.
# The notebook and the live session join on ZIP-to-ZCTA. This script is the same
# merge with a different key: a 2010 Census tract ID already on your data. Where
# that ID comes from (a geocoder, a data vendor, a survey file that carries it)
# is your choice; geocode_to_tract.R beside this file gets one from a street
# address, and r/README.md lists the other sources.
# Block labels match the notebook where the step is the same, so you can read
# the two side by side. Adapted from Robert Melendez's tract merge.
#
# Data: data/synthetic_data_v20260924_tract10.csv is the synthetic dataset with
# a tract_fips10 column added (synthetic too; see r/README.md). data/nanda/
# holds the tract-level NaNDA files you download from ICPSR yourself
# (data/nanda/README.md, "Tract-level files").
# Open workshop.Rproj first so here::here() resolves the paths.

# ---- setup ----
library(tidyverse)   # dplyr for the joins, readr for the CSVs, stringr for padding
library(here)        # file paths that work wherever this folder sits on your machine
library(janitor)     # tabyl(), for frequency tables you can read

# ---- read-data ----
# tract_fips10 is state (2) + county (3) + tract (6): eleven characters, and the
# first can be a zero. Read it as text, or Alabama's tracts lose a digit.
mydata_tract10 <- read_csv(
  here("data", "synthetic_data_v20260924_tract10.csv"),
  col_types = cols(zip = col_character(), tract_fips10 = col_character())
)

# NaNDA: Social Services, tract 2010, 1990-2022. Same rule for the tract ID.
socialservices_tract10 <- read_csv(
  here("data", "nanda", "nanda_socials_Tract10_1990-2022_01.csv"),
  col_types = cols(tract_fips10 = col_character())
)

# Parks and Socioeconomic Status come from ICPSR as .rda files. load() drops an
# object into your session under a name ICPSR picked, and returns that name.
# Print it, then rename it to something you will recognise later.
print(load(here("data", "nanda", "38586-0001-Data.rda")))   # Parks, tract 2010, 2022
parks2022_tract10 <- da38586.0001
rm(da38586.0001)

print(load(here("data", "nanda", "38528-0002-Data.rda")))   # SES, tract 2010, 2008-2017
ses2008_2017_tract10 <- da38528.0002
rm(da38528.0002)

print(load(here("data", "nanda", "38528-0006-Data.rda")))   # SES, tract 2010, 2018-2022
ses2018_2022_tract10 <- da38528.0006
rm(da38528.0006)

# An .rda may hold the tract ID as a factor or a number. Make it eleven-character
# text everywhere before joining; a join on mismatched types matches nothing.
as_tract <- function(x) str_pad(as.character(x), 11, pad = "0")
mydata_tract10         <- mydata_tract10         %>% mutate(tract_fips10 = as_tract(tract_fips10))
socialservices_tract10 <- socialservices_tract10 %>% mutate(tract_fips10 = as_tract(tract_fips10))
parks2022_tract10      <- parks2022_tract10      %>% mutate(TRACT_FIPS10 = as_tract(TRACT_FIPS10))
ses2008_2017_tract10   <- ses2008_2017_tract10   %>% mutate(TRACT_FIPS10 = as_tract(TRACT_FIPS10))
ses2018_2022_tract10   <- ses2018_2022_tract10   %>% mutate(TRACT_FIPS10 = as_tract(TRACT_FIPS10))

# ---- glimpse-data ----
glimpse(mydata_tract10)

# ---- inspect-identifiers ----
# Count the rows that have a tract ID.
mydata_tract10 %>%
  summarise(
    rows          = n(),
    has_tract     = sum(!is.na(tract_fips10)),
    missing_tract = sum(is.na(tract_fips10)),
    pct_missing   = round(100 * mean(is.na(tract_fips10)), 1)
  )

# Every ID that is present should be eleven characters. Any other length means
# the ID was altered before it reached you, often by a spreadsheet.
mydata_tract10 %>%
  filter(!is.na(tract_fips10)) %>%
  count(id_length = nchar(tract_fips10))

# ---- who-is-missing ----
# Compare the rows that matched with those that did not, on the variables the
# study is about.
mydata_tract10 %>%
  group_by(has_tract = !is.na(tract_fips10)) %>%
  summarise(
    n                 = n(),
    loneliness        = round(mean(loneliness,        na.rm = TRUE), 2),
    physical_activity = round(mean(physical_activity, na.rm = TRUE), 2),
    own_pet           = round(mean(own_pet,           na.rm = TRUE), 3),
    .groups = "drop"
  )

# ---- carry-forward ----
# complete() adds the missing tract-year rows; fill() carries each tract's last
# value down into them. fill() does not stop at 2022: any value missing inside
# 1990-2022 (population, and the densities where population is zero) also gets
# the year before.
socialservices_tract10 <- socialservices_tract10 %>%
  complete(tract_fips10, year = 1990:2025) %>%
  arrange(tract_fips10, year) %>%
  group_by(tract_fips10) %>%
  fill(everything(), .direction = "down") %>%
  ungroup()

# Every year from 2022 on should now carry the same values.
tabyl(socialservices_tract10, year) %>% filter(year >= 2020)

# ---- join-nanda ----
mydata_nanda <- mydata_tract10 %>%
  # Social Services is longitudinal, so the key is tract *and* year.
  # `in_nanda` is added before the join: it is TRUE on every row of the NaNDA
  # side, so after the join it is TRUE where something matched and NA where
  # nothing did. Stata's `_merge` flags matched rows; here `in_nanda` does the
  # same.
  left_join(
    socialservices_tract10 %>%
      select(tract_fips10, year, totpop, aland10,
             count_totindivfamilyservices, den_totindivfamilyservices,
             count_childyouthservices,     den_childyouthservices,
             count_elderservices,          den_elderservices) %>%
      mutate(in_nanda = TRUE),
    by = c("tract_fips10", "year")
  ) %>%
  mutate(in_nanda = coalesce(in_nanda, FALSE)) %>%
  # Parks is a single 2022 snapshot, so it joins on tract alone and every year of
  # a person's records gets the same value. That assumes park provision held
  # still across the study period.
  left_join(
    parks2022_tract10 %>%
      select(TRACT_FIPS10, ANY_OPEN_PARK, COUNT_OPEN_PARKS_TC10, PROP_PARK_AREA_TRACT),
    by = c("tract_fips10" = "TRACT_FIPS10")
  )

c(rows_before = nrow(mydata_tract10), rows_after = nrow(mydata_nanda))

# ---- ses-join ----
# At the tract level NaNDA has Socioeconomic Status on 2010 boundaries for both
# periods: DS0002 (2008-2017) and DS0006 (2018-2022). So the rows split at 2018,
# each period takes its own file, and the two halves stack back together. The
# ZCTA route cannot do this, because its 2018-2022 file is drawn on 2020
# boundaries; that is why the notebook joins one file to every row instead.
# The 2008-2017 file names its affluence measure for the ACS years behind it.
# Give it the plain name before stacking.
rows_before <- nrow(mydata_nanda)

mydata_nanda <- bind_rows(
  mydata_nanda %>%
    filter(year <= 2017) %>%
    left_join(
      ses2008_2017_tract10 %>%
        select(TRACT_FIPS10, AFFLUENCE13_17) %>%
        rename(AFFLUENCE = AFFLUENCE13_17),
      by = c("tract_fips10" = "TRACT_FIPS10")
    ),
  mydata_nanda %>%
    filter(year >= 2018) %>%
    left_join(
      ses2018_2022_tract10 %>% select(TRACT_FIPS10, AFFLUENCE),
      by = c("tract_fips10" = "TRACT_FIPS10")
    )
) %>%
  arrange(sampleid, year)

# A split-and-stack can lose rows (a missing year falls through both filters)
# or gain them (a duplicate tract in a NaNDA file). Compare the counts.
c(rows_before = rows_before, rows_after = nrow(mydata_nanda),
  with_affluence = sum(!is.na(mydata_nanda$AFFLUENCE)))

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
    socialservices_tract10 %>% select(tract_fips10, year),
    by = c("tract_fips10", "year")
  )

# A row can fail for three different reasons here, and each calls for a
# different response: the first is a data-collection or geocoding problem, the
# second is a coverage limit, the third is usually a boundary mismatch (a 2020
# tract ID against a 2010 file). The second cannot occur in this file, because
# we carried Social Services forward. The case stays in the table in case that
# step is removed.
unmatched %>%
  mutate(reason = case_when(
    is.na(tract_fips10) ~ "no tract ID to start from",
    year > 2022         ~ "year past NaNDA's coverage",
    TRUE                ~ "tract not in the NaNDA file"
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
