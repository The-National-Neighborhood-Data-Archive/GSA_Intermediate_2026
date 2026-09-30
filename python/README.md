# Python version

The live session is in R. These `.py` scripts do the same thing, step for step, for
participants who work in Python. Each step also appears on the walkthrough page, in
the Python tab beside the R version, so the two must stay aligned.

Use the same section headers as the R script (`# ---- setup ----`, `# ---- read-data ----`,
and so on) so each block drops into its tab.

Use pandas with explicit `dtype=str` on every identifier column at read time; the
leading-zero pitfall is the same one the R walkthrough warns about in Section 0. Use
`merge(..., indicator=True)` so the match-rate diagnostic in Section 3 falls out of the
join the way Stata's `_merge` does, rather than being rebuilt by hand.
