# Stata version

The live session is in R. These `.do` files do the same thing, step for step, for
participants who work in Stata. Each step also appears on the notebook page, in
the Stata tab beside the R version, so the two must stay aligned.

Use the same section headers as the R script (`* ---- setup ----`, `* ---- read-data ----`,
and so on) so each block drops into its tab.

One contrast worth a comment in the code: Stata's `merge` hands you `_merge` for free;
R's joins drop and duplicate silently. The diagnostic in Section 3 has to be built
deliberately in R, which is part of the point.
