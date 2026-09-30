* Linking NaNDA With Your Data: the Stata version of the walkthrough.
* Each block carries the same label as the code block on the walkthrough page,
* so you can read the two side by side. The session is run in R; this file is
* the same steps in Stata, step for step. Not demonstrated live.
*
* Data: data/ holds the synthetic CSV and the crosswalk; data/nanda/ holds the
* NaNDA files you download from ICPSR yourself (see data/nanda/README.md).
* Take the Stata-format downloads for Parks and Socioeconomic Status.

* ---- setup ----
* Run this from the workshop folder (the one holding workshop.Rproj), so the
* relative paths below resolve: File > Change Working Directory, or `cd`.
version 16
clear all
set more off

* One tempfile per table the R version keeps in memory. Stata holds one
* dataset at a time, so each step saves and the next step merges it back.
tempfile mydata socialservices parks ses2010 ses2020 xwalk mydata_zcta10 mydata_nanda

* ---- read-data ----
* Our own data. Stata guesses "number" for a column of digits, and 03042 comes
* in as 3042. Check what it guessed and pad back to five characters if so.
import delimited using "data/synthetic_data_v20260924.csv", varnames(1) clear
capture confirm string variable zip
if _rc tostring zip, replace format(%05.0f)
save `mydata'

* NaNDA: Social Services, ZCTA 2010, 1990-2022. Same rule for the ZCTA code.
import delimited using "data/nanda/nanda_socials_Zcta10_1990-2022_01.csv", varnames(1) clear
capture confirm string variable zcta10
if _rc tostring zcta10, replace format(%05.0f)
save `socialservices'

* Parks and Socioeconomic Status: take the Stata format from ICPSR. Variable
* names arrive in upper case, as the ICPSR codebook lists them.
use "data/nanda/38586-0002-Data.dta", clear          // Parks, ZCTA, 2022
capture confirm string variable ZCTA19
if _rc tostring ZCTA19, replace format(%05.0f)
save `parks'

use "data/nanda/38528-0003-Data.dta", clear          // SES, ZCTA 2010, 2008-2017
capture confirm string variable ZCTA10
if _rc tostring ZCTA10, replace format(%05.0f)
save `ses2010'

use "data/nanda/38528-0008-Data.dta", clear          // SES, ZCTA 2020, 2018-2022
capture confirm string variable ZCTA20
if _rc tostring ZCTA20, replace format(%05.0f)
save `ses2020'

* ---- glimpse-data ----
use `mydata', clear
describe
list in 1/5

* ---- inspect-identifiers ----
* How many rows carry a ZIP we can actually look something up with?
use `mydata', clear
generate byte missing_zip = missing(zip)
summarize missing_zip
display "rows = " r(N) ", missing ZIP = " r(sum) ", pct missing = " %4.1f 100 * r(mean)

* ---- inspect-address ----
* address, city and zip are each incomplete, and not for the same rows. A row
* with no ZIP may still have an address you could geocode, and the other way
* round, so "how much geography do I have" depends on which route you take.
use `mydata', clear
generate byte address_missing = missing(address)
generate byte city_missing    = missing(city)
generate byte zip_missing     = missing(zip)
contract address_missing city_missing zip_missing, freq(n)
gsort -n
list, clean noobs

* ---- read-crosswalk ----
* Every column as text, for the same reason as `zip` above. Then pad back to
* five characters: whatever stripped a leading zero upstream did it before we
* got here.
import excel using "data/zip_to_zcta_2019.xlsx", firstrow allstring clear
replace ZIP_CODE = substr("00000", 1, 5 - strlen(ZIP_CODE)) + ZIP_CODE if strlen(ZIP_CODE) < 5
replace ZCTA     = substr("00000", 1, 5 - strlen(ZCTA))     + ZCTA     if strlen(ZCTA)     < 5
keep ZIP_CODE ZCTA zip_join_type
save `xwalk'

* zip_join_type is the crosswalk telling you how each ZIP got its ZCTA, or that
* it has none. Read this before you join, not after something looks wrong.
tabulate zip_join_type

* ---- crosswalk-join ----
use `xwalk', clear
rename (ZIP_CODE ZCTA zip_join_type) (zip zcta10 zip_join_type10)
save `xwalk', replace

use `mydata', clear
count
local rows_before = r(N)

* m:1 says "many of mine to one of theirs". If the crosswalk has two rows for
* one ZIP, Stata stops here instead of quietly duplicating people. keep(master
* match) is the left join: every row of ours stays, matched or not.
merge m:1 zip using `xwalk', keep(master match)
count
display "rows before = `rows_before', rows after = " r(N)

* Two different failures, worth keeping apart. A row with no ZIP never had
* anything to look up. A row whose ZIP is missing from the crosswalk had one,
* and it led nowhere: PO-box ZIPs, single-building ZIPs, retired ZIPs.
generate str zcta_status = "has a ZCTA"
replace  zcta_status = "ZIP not in crosswalk" if _merge == 1
replace  zcta_status = "no ZIP"               if missing(zip)
tabulate zcta_status
drop _merge
save `mydata_zcta10'

* ---- who-is-missing ----
* The question a match rate cannot answer: are the people who fell out different
* from the people who stayed, on the things the study is actually about?
use `mydata_zcta10', clear
generate byte has_zcta = !missing(zcta10)
tabstat loneliness physical_activity own_pet, by(has_zcta) statistics(n mean) format(%9.3f)

* ---- carry-forward ----
* Stata has no complete(); every ZCTA here has a 2022 row, so make three copies
* of it and number them 2023-2025. Then carry each ZCTA's last value down into
* anything still missing. Like R's fill(), that also reaches values missing
* inside 1990-2022 (population, and densities where population is zero).
use `socialservices', clear
expand 4 if year == 2022
bysort zcta10 year: replace year = 2021 + _n if year == 2022
sort zcta10 year
foreach v of varlist _all {
    if !inlist("`v'", "zcta10", "year") {
        by zcta10: replace `v' = `v'[_n-1] if missing(`v')
    }
}
save `socialservices', replace

* Every year from 2022 on should now carry the same values.
tabulate year if year >= 2020

* ---- join-nanda ----
use `socialservices', clear
keep zcta10 year totpop aland10 ///
     count_totindivfamilyservices den_totindivfamilyservices ///
     count_childyouthservices     den_childyouthservices ///
     count_elderservices          den_elderservices
save `socialservices', replace

use `mydata_zcta10', clear
count
local rows_before = r(N)

* Social Services is longitudinal, so the key is ZCTA *and* year. Stata's
* _merge is the diagnostic the R version has to build by hand: 3 = matched,
* 1 = ours only. Keep it as in_nanda.
merge m:1 zcta10 year using `socialservices', keep(master match)
generate byte in_nanda = (_merge == 3)
drop _merge

* Parks is a single 2022 snapshot, so it joins on ZCTA alone and every year of
* a person's records gets the same value. That assumes park provision held
* still across the study period. Say so in your methods.
preserve
    use `parks', clear
    keep ZCTA19 ANY_OPEN_PARK COUNT_OPEN_PARKS_TC10 PROP_PARK_AREA_ZCTA
    rename ZCTA19 zcta10
    save `parks', replace
restore
merge m:1 zcta10 using `parks', keep(master match) nogenerate

count
display "rows before = `rows_before', rows after = " r(N)
save `mydata_nanda'

* ---- ses-join ----
* The 2010-boundary file (DS0003) names its affluence measure for the ACS years
* behind it. Give it a plain name before merging. The 2020-boundary file is
* trimmed the same way here, for the comparison below only.
use `ses2010', clear
keep ZCTA10 AFFLUENCE13_17
rename (ZCTA10 AFFLUENCE13_17) (zcta10 AFFLUENCE)
save `ses2010', replace

use `ses2020', clear
keep ZCTA20 AFFLUENCE
rename ZCTA20 zcta10
save `ses2020', replace

use `mydata_nanda', clear
merge m:1 zcta10 using `ses2010', keep(master match) nogenerate
count if !missing(AFFLUENCE)
display "rows = " _N ", with affluence = " r(N)
save `mydata_nanda', replace

* ---- boundaries-2010 ----
* Socioeconomic Status, 2010-boundary file (ICPSR 38528, DS0003), already
* trimmed and renamed above, against every row.
use `mydata_zcta10', clear
merge m:1 zcta10 using `ses2010', keep(master match) nogenerate
generate byte matched = !missing(AFFLUENCE)
summarize matched
local rows = r(N)
local matched = r(sum)
local rate = 100 * r(mean)
summarize AFFLUENCE
display "SES, ZCTA 2010 file: rows = `rows', matched = `matched', match rate = " ///
        %4.1f `rate' "%, mean affluence = " %6.3f r(mean)
tempfile on_2010
save `on_2010'

* ---- boundaries-2020 ----
* The same 2010-boundary codes, straight from the crosswalk, against the
* 2020-boundary file (ICPSR 38528, DS0008). Nothing in this merge knows that
* the codes and the boundaries come from different censuses. It runs, it
* matches, it returns a number.
use `mydata_zcta10', clear
merge m:1 zcta10 using `ses2020', keep(master match) nogenerate
generate byte matched = !missing(AFFLUENCE)
summarize matched
local rows = r(N)
local matched = r(sum)
local rate = 100 * r(mean)
summarize AFFLUENCE
display "SES, ZCTA 2020 file: rows = `rows', matched = `matched', match rate = " ///
        %4.1f `rate' "%, mean affluence = " %6.3f r(mean)
tempfile on_2020
save `on_2020'

* ---- boundaries-compare ----
use `on_2010', clear
generate str nanda_file = "SES, ZCTA 2010 file"
append using `on_2020'
replace nanda_file = "SES, ZCTA 2020 file" if missing(nanda_file)
generate byte one = 1
collapse (sum) rows = one (sum) matched (mean) match_rate_pct = matched ///
         (mean) mean_affluence = AFFLUENCE, by(nanda_file)
replace match_rate_pct = round(100 * match_rate_pct, 0.1)
replace mean_affluence = round(mean_affluence, 0.001)
list, clean noobs

* ---- match-rate ----
* The headline.
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

* A count is not a diagnosis. A row can fail for four different reasons, and
* the reasons call for different answers: the first two are a data-collection
* problem, the third is a coverage limit you state in your methods, the fourth
* is usually a boundary mismatch. Three occur in this file; the third cannot,
* because we carried Social Services forward. It is named so the table says
* so if that step is ever dropped.
generate str reason = "ZCTA not in the NaNDA file"
replace  reason = "year past NaNDA's coverage" if year > 2022
replace  reason = "ZIP not in the crosswalk"   if missing(zcta10)
replace  reason = "no ZIP to start from"       if missing(zip)
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
