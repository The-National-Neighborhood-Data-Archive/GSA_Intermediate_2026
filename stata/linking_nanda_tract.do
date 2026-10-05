* Linking NaNDA With Your Data: the tract route, in Stata.
* The notebook and the live session join on ZIP-to-ZCTA. This file is the same
* merge with a different key: a 2010 Census tract ID already on your data. Where
* that ID comes from (a geocoder, a data vendor, a survey file that carries it)
* is your choice and is not covered here; r/README.md lists the usual sources.
* Block labels match the notebook where the step is the same, so you can read
* the two side by side. Not demonstrated live.
*
* Data: data/synthetic_data_v20260924_tract10.csv is the synthetic dataset with
* a tract_fips10 column added (synthetic too; see r/README.md). data/nanda/
* holds the tract-level NaNDA files you download from ICPSR yourself
* (data/nanda/README.md, "Tract-level files"). Take the Stata-format downloads
* for Parks and Socioeconomic Status.

* ---- setup ----
* Run this from the workshop folder (the one holding workshop.Rproj), so the
* relative paths below resolve: File > Change Working Directory, or `cd`.
version 16
clear all
set more off

* One tempfile per table the R version keeps in memory. Stata holds one
* dataset at a time, so each step saves and the next step merges it back.
tempfile mydata socialservices parks ses0817 ses1822 mydata_nanda ge2018

* ---- read-data ----
* tract_fips10 is state (2) + county (3) + tract (6): eleven characters, and the
* first can be a zero. Stata guesses "number" for a column of digits, and
* 01001020100 comes in as 1001020100. Check what it guessed and pad back to
* eleven characters if so. tostring writes a missing number as ".", so blank
* that out too, so missing() counts it.
import delimited using "data/synthetic_data_v20260924_tract10.csv", varnames(1) clear
capture confirm string variable zip
if _rc tostring zip, replace format(%05.0f)
replace zip = "" if zip == "."
capture confirm string variable tract_fips10
if _rc tostring tract_fips10, replace format(%011.0f)
replace tract_fips10 = "" if tract_fips10 == "."
save `mydata'

* NaNDA: Social Services, tract 2010, 1990-2022. Same rule for the tract ID.
import delimited using "data/nanda/nanda_socials_Tract10_1990-2022_01.csv", varnames(1) clear
capture confirm string variable tract_fips10
if _rc tostring tract_fips10, replace format(%011.0f)
save `socialservices'

* Parks and Socioeconomic Status: take the Stata format from ICPSR. Variable
* names arrive in upper case, as the ICPSR codebook lists them.
use "data/nanda/38586-0001-Data.dta", clear          // Parks, tract 2010, 2022
capture confirm string variable TRACT_FIPS10
if _rc tostring TRACT_FIPS10, replace format(%011.0f)
save `parks'

use "data/nanda/38528-0002-Data.dta", clear          // SES, tract 2010, 2008-2017
capture confirm string variable TRACT_FIPS10
if _rc tostring TRACT_FIPS10, replace format(%011.0f)
save `ses0817'

use "data/nanda/38528-0006-Data.dta", clear          // SES, tract 2010, 2018-2022
capture confirm string variable TRACT_FIPS10
if _rc tostring TRACT_FIPS10, replace format(%011.0f)
save `ses1822'

* ---- glimpse-data ----
use `mydata', clear
describe
list in 1/5

* ---- inspect-identifiers ----
* Count the rows that have a tract ID.
use `mydata', clear
generate byte missing_tract = missing(tract_fips10)
summarize missing_tract
display "rows = " r(N) ", missing tract = " r(sum) ", pct missing = " %4.1f 100 * r(mean)

* Every ID that is present should be eleven characters. Any other length means
* the ID was altered before it reached you, often by a spreadsheet.
generate id_length = strlen(tract_fips10) if !missing(tract_fips10)
tabulate id_length

* ---- who-is-missing ----
* Compare the rows that matched with those that did not, on the variables the
* study is about.
use `mydata', clear
generate byte has_tract = !missing(tract_fips10)
tabstat loneliness physical_activity own_pet, by(has_tract) statistics(n mean) format(%9.3f)

* ---- carry-forward ----
* Stata has no complete(); every tract here has a 2022 row, so make three copies
* of it and number them 2023-2025. Then carry each tract's last value down into
* anything still missing. Like R's fill(), that also reaches values missing
* inside 1990-2022 (population, and densities where population is zero).
use `socialservices', clear
expand 4 if year == 2022
bysort tract_fips10 year: replace year = 2021 + _n if year == 2022
sort tract_fips10 year
foreach v of varlist _all {
    if !inlist("`v'", "tract_fips10", "year") {
        by tract_fips10: replace `v' = `v'[_n-1] if missing(`v')
    }
}
save `socialservices', replace

* Every year from 2022 on should now carry the same values.
tabulate year if year >= 2020

* ---- join-nanda ----
use `socialservices', clear
keep tract_fips10 year totpop aland10 ///
     count_totindivfamilyservices den_totindivfamilyservices ///
     count_childyouthservices     den_childyouthservices ///
     count_elderservices          den_elderservices
save `socialservices', replace

use `mydata', clear
count
local rows_before = r(N)

* Social Services is longitudinal, so the key is tract *and* year. Stata's
* _merge is the diagnostic the R version has to build by hand: 3 = matched,
* 1 = ours only. Keep it as in_nanda.
merge m:1 tract_fips10 year using `socialservices', keep(master match)
generate byte in_nanda = (_merge == 3)
drop _merge

* Parks is a single 2022 snapshot, so it joins on tract alone and every year of
* a person's records gets the same value. That assumes park provision held
* still across the study period.
preserve
    use `parks', clear
    keep TRACT_FIPS10 ANY_OPEN_PARK COUNT_OPEN_PARKS_TC10 PROP_PARK_AREA_TRACT
    rename TRACT_FIPS10 tract_fips10
    save `parks', replace
restore
merge m:1 tract_fips10 using `parks', keep(master match) nogenerate

count
display "rows before = `rows_before', rows after = " r(N)
save `mydata_nanda'

* ---- ses-join ----
* At the tract level NaNDA has Socioeconomic Status on 2010 boundaries for both
* periods: DS0002 (2008-2017) and DS0006 (2018-2022). So the rows split at 2018,
* each period takes its own file, and the two halves stack back together. The
* ZCTA route cannot do this, because its 2018-2022 file is drawn on 2020
* boundaries; that is why the notebook joins one file to every row instead.
* The 2008-2017 file names its affluence measure for the ACS years behind it.
* Give it the plain name before stacking.
use `ses0817', clear
keep TRACT_FIPS10 AFFLUENCE13_17
rename (TRACT_FIPS10 AFFLUENCE13_17) (tract_fips10 AFFLUENCE)
save `ses0817', replace

use `ses1822', clear
keep TRACT_FIPS10 AFFLUENCE
rename TRACT_FIPS10 tract_fips10
save `ses1822', replace

use `mydata_nanda', clear
count
local rows_before = r(N)

preserve
    keep if year >= 2018
    merge m:1 tract_fips10 using `ses1822', keep(master match) nogenerate
    save `ge2018'
restore
keep if year <= 2017
merge m:1 tract_fips10 using `ses0817', keep(master match) nogenerate
append using `ge2018'
sort sampleid year

* A split-and-stack can lose rows (a missing year falls through both keeps)
* or gain them (a duplicate tract in a NaNDA file). Compare the counts.
count
display "rows before = `rows_before', rows after = " r(N)
count if !missing(AFFLUENCE)
display "with affluence = " r(N)
save `mydata_nanda', replace

* ---- match-rate ----
* Overall match rate.
use `mydata_nanda', clear
summarize in_nanda
display "rows = " r(N) ", matched = " r(sum) ", match rate = " %4.1f 100 * r(mean) "%"

* The same number, by year. 2023 onward matches because we carried Social
* Services forward; without that step these rows would show 0%.
tabulate year in_nanda, row nofreq

* ---- anti-join ----
* The rows that found no partner: the complement of the join. in_nanda == 0 is
* exactly the "ours only" side of the merge.
use `mydata_nanda', clear
keep if in_nanda == 0

* A row can fail for three different reasons here, and each calls for a
* different response: the first is a data-collection or geocoding problem, the
* second is a coverage limit, the third is usually a boundary mismatch (a 2020
* tract ID against a 2010 file). The second cannot occur in this file, because
* we carried Social Services forward. The case stays in the table in case that
* step is removed.
generate str reason = "tract not in the NaNDA file"
replace  reason = "year past NaNDA's coverage" if year > 2022
replace  reason = "no tract ID to start from"  if missing(tract_fips10)
tabulate reason

* ---- toy-model ----
use `mydata_nanda', clear
generate byte count_totindivfamilyservices_6cat = .
replace count_totindivfamilyservices_6cat = 1 if count_totindivfamilyservices == 0
replace count_totindivfamilyservices_6cat = 2 if count_totindivfamilyservices == 1
replace count_totindivfamilyservices_6cat = 3 if count_totindivfamilyservices == 2
replace count_totindivfamilyservices_6cat = 4 if count_totindivfamilyservices == 3
replace count_totindivfamilyservices_6cat = 5 if inrange(count_totindivfamilyservices, 4, 5)
replace count_totindivfamilyservices_6cat = 6 if inrange(count_totindivfamilyservices, 6, 10)
replace count_totindivfamilyservices_6cat = 7 if count_totindivfamilyservices >= 11 & !missing(count_totindivfamilyservices)
label define svc6 1 "0" 2 "1" 3 "2" 4 "3" 5 "4-5" 6 "6-10" 7 "11+"
label values count_totindivfamilyservices_6cat svc6

* ANY_OPEN_PARK is a labeled factor in the .dta; i. treats it as categorical.
logit own_pet hot_meal_days i.count_totindivfamilyservices_6cat i.ANY_OPEN_PARK AFFLUENCE

* ---- session-info ----
about
