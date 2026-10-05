* Linking NaNDA With Your Data: from a street address to a 2010 tract ID, in Stata.
* Section 2 of the notebook explains this step and shows its shape without running
* it. The R and Python files geocode against OpenStreetMap and spatially join the
* points to 2010 tract boundaries. Stata has neither a geocoding client nor a
* spatial join built in, so this file reaches the same output by a different
* route: the Census Bureau's batch geocoder, which is free, needs no account,
* takes up to 10,000 addresses per call, and returns the 2010 tract code with each
* match. It needs no boundary files and no spatial join, and it takes a minute or
* two instead of half an hour. The output has every column of the input plus the
* coordinates, the match fields, and tract_fips10, so linking_nanda_tract.do takes
* it as its input (change the path in its read-data block). Block headers match
* the R file where the step is the same. The session does not run it live.
*
* Before you run it:
*   - The Census call was checked on a sample of the synthetic file, and the
*     result format described at read-result is what it returned. If something
*     here fails, use r/geocode_to_tract.R or python/geocode_to_tract.py, or
*     upload data/census_batch_in_1.csv by hand at
*     https://geocoding.geo.census.gov/geocoder/geographies/addressbatch, save
*     the result as data/census_batch_out_1.csv, and run from read-result on.
*   - The call goes through curl, which Windows 10 and later, macOS, and most
*     Linux distributions ship with. If the shell line fails, curl is not on your
*     PATH, and the by-hand upload above is the fallback.
*   - The Census Geocoder places a match on its street segment, which is precise
*     enough for a tract. "Match" rows get a tract; "No_Match" and "Tie"
*     (ambiguous) rows do not. It covers the United States and Puerto Rico only.
*   - It is a public service shared with everyone; do not loop it needlessly.

* ---- setup ----
* Run this from the workshop folder (the one holding workshop.Rproj), so the
* relative paths below resolve: File > Change Working Directory, or `cd`.
version 16
clear all
set more off

* ---- read-data ----
* Everything comes in as text. The identifiers must (zip loses its leading zero
* otherwise; see Section 0 of the notebook), and the other columns go back out
* to CSV unchanged, so there is nothing to gain from typing them here.
import delimited using "data/synthetic_data_v20260924.csv", varnames(1) stringcols(_all) clear

* The batch geocoder needs a unique id per row and returns rows in any order.
gen long rowid = _n
* Every row with any address field goes, as in the R and Python files. A row
* with no street, city or ZIP has nothing to send.
gen byte has_address = !missing(trim(address)) | !missing(trim(city)) | !missing(trim(zip))

* ---- geocode ----
* Each batch file has no header and five columns: id, street, city, state, ZIP.
* One call per 10,000 addresses. The Census Geocoder returns No_Match for a row
* without a street, so those rows come back with no coordinates.
count if has_address
local n_batches = ceil(r(N) / 10000)
display as text "Sending " r(N) " addresses to the Census Geocoder in `n_batches' batch(es)..."
gen int batch = ceil(sum(has_address) / 10000)   // running count: the first 10,000 sent rows are batch 1
forvalues b = 1/`n_batches' {
    preserve
    keep if has_address & batch == `b'
    keep rowid address city state zip
    export delimited using "data/census_batch_in_`b'.csv", novarnames replace
    restore
    shell curl --silent --show-error --form "addressFile=@data/census_batch_in_`b'.csv" --form benchmark=Public_AR_Current --form vintage=Census2010_Current "https://geocoding.geo.census.gov/geocoder/geographies/addressbatch" --output "data/census_batch_out_`b'.csv"
}
tempfile mydata
save `mydata'

* ---- read-result ----
* The result has twelve columns and no header, and the rows come back in any order. Unmatched rows carry only the
* first three. Column 6 holds "longitude,latitude" in one quoted field. The last
* four are the 2010 state, county, tract and block codes of the matched point.
tempfile geocoded
forvalues b = 1/`n_batches' {
    import delimited using "data/census_batch_out_`b'.csv", varnames(nonames) stringcols(_all) clear
    forvalues j = 1/12 {
        capture confirm variable v`j'
        if _rc gen str1 v`j' = ""     // a batch with no matches has fewer columns
    }
    rename (v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12) ///
           (rowid input_address match matchtype matched_address coordinates ///
            tigerline_id side state_fips county_fips tract block)
    if `b' > 1 append using `geocoded'
    save `geocoded', replace
}
destring rowid, replace
split coordinates, parse(",") destring
forvalues j = 1/2 {
    capture confirm variable coordinates`j'
    if _rc gen coordinates`j' = .     // nothing matched, so nothing to split
}
rename (coordinates1 coordinates2) (long lat)
gen str11 tract_fips10 = state_fips + county_fips + tract if match == "Match"
keep rowid lat long match matchtype matched_address tract_fips10
save `geocoded', replace

* Join the result back onto every original row. Addresses that were not sent or did not match
* stay in the file with a missing tract_fips10, which is where the merge
* diagnostics in linking_nanda_tract.do will count them.
use `mydata', clear
merge 1:1 rowid using `geocoded', keep(master match) nogenerate
sort rowid

* ---- diagnostics ----
* This block counts how many rows reached a tract and why the rest did not. Blank addresses and
* failed matches come from the input data, so count them separately from join failures.
gen str40 outcome = "in a 2010 tract"
replace outcome = "no street address"            if missing(trim(address))
replace outcome = "no result from the geocoder"  if has_address & missing(match)
replace outcome = "address did not match"        if match == "No_Match" & !missing(trim(address))
replace outcome = "ambiguous match (Tie)"        if match == "Tie"
tab outcome

* ---- write ----
* The output has the input's columns, then what this script added.
drop rowid has_address batch outcome
export delimited using "data/synthetic_data_v20260924_geocoded_tract10.csv", replace
