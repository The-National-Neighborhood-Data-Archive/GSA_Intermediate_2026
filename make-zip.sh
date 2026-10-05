#!/usr/bin/env bash
# Build the participant-facing materials ZIP into _site/ so the packet URL resolves.
# Run AFTER `quarto render`, BEFORE `quarto publish gh-pages`.
#
# The script refuses to build a ZIP a participant couldn't use:
#   - every data file the notebook reads must be in data/
#   - the R, Stata and Python scripts must be present, both routes each
#   - the site URLs in _variables.yml must name the repo this is running in
#     (the private working repo and the public participant repo have different names)
# It also warns about anything still marked TODO, and removes build junk that
# would otherwise be published.
#
# Override the Quarto binary with QUARTO=/path/to/quarto if it isn't on PATH.
set -euo pipefail
cd "$(dirname "$0")"

OUT="workshop-materials"
QUARTO="${QUARTO:-quarto}"

# --- What a participant needs ------------------------------------------------
# Only redistributable files. The NaNDA extracts are NOT here: they come from
# ICPSR, which requires a free account, so participants download their own
# (data/nanda/README.md has the steps). Gating on them would be gating on files
# we are not allowed to ship.
REQUIRED_DATA=(
  synthetic_data_v20260924.csv
  synthetic_data_v20260924_tract10.csv
  codebook_synthetic_data_v20260924.log
  zip_to_zcta_2019.xlsx
)
CONTACT="nanda-admin@umich.edu"

fail=0
red()    { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; fail=1; }
yellow() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }

# --- Gate 1: the render exists and is current --------------------------------
[ -f _site/notebook.html ] || red "_site/notebook.html is missing. Run 'quarto render' first."
if [ -f _site/notebook.html ] && [ notebook.qmd -nt _site/notebook.html ]; then
  red "notebook.qmd is newer than _site/notebook.html. Run 'quarto render' again."
fi

# --- Gate 2: data files ------------------------------------------------------
for f in "${REQUIRED_DATA[@]}"; do
  [ -s "data/$f" ] || red "data/$f is missing or empty."
done

# --- Gate 3: the scripts, one folder per language, both routes in each --------
for route in zcta tract; do
  [ -s "r/linking_nanda_$route.R"       ] || red "r/linking_nanda_$route.R is missing. The manifest promises it."
  [ -s "stata/linking_nanda_$route.do"  ] || red "stata/linking_nanda_$route.do is missing. The manifest promises it."
  [ -s "python/linking_nanda_$route.py" ] || red "python/linking_nanda_$route.py is missing. The manifest promises it."
done
for lang in r stata python; do
  [ -s "$lang/README.md" ] || yellow "$lang/README.md is missing; the manifest points to it."
done

# --- Gate 4: URLs point at this repo -----------------------------------------
# GitHub Pages lowercases the org, so compare case-insensitively.
repo=$(basename -s .git "$(git remote get-url origin 2>/dev/null || echo unknown)")
repo_lc=$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]')
url_fail=0
for key in url zip repo; do
  val=$(awk -v k="  $key:" '$0 ~ "^"k {sub(/^[^"]*"/,""); sub(/".*$/,""); print; exit}' _variables.yml)
  [ "$key" = url ] && SITE_URL="$val"   # reused in the manifest below
  val_lc=$(printf '%s' "$val" | tr '[:upper:]' '[:lower:]')
  case "$val_lc" in
    *"/$repo_lc/"*|*"/$repo_lc"|*"/$repo_lc.git") ;;
    *) url_fail=1
       printf '\033[31mERROR:\033[0m site.%s in _variables.yml is "%s" but this repo is "%s". Fix _variables.yml (runbook step 1), or set ALLOW_URL_MISMATCH=1 for a local test build.\n' "$key" "$val" "$repo" >&2 ;;
  esac
done
if [ "$url_fail" = 1 ]; then
  if [ "${ALLOW_URL_MISMATCH:-0}" = 1 ]; then
    yellow "ALLOW_URL_MISMATCH=1: building anyway. Do NOT publish this ZIP."
  else
    fail=1
  fi
fi

# --- Warnings (non-fatal) ----------------------------------------------------
if grep -qE '^\s*(short_url|doi|start_time):\s*"?TODO' _variables.yml; then
  yellow "_variables.yml still has TODO values (short_url / doi / start_time). Fine before the tag; not fine in the Oct 2 packet."
fi
case "$CONTACT" in *TODO*) yellow "CONTACT in make-zip.sh is still a TODO." ;; esac
if [ -d _site/_review ]; then
  yellow "Removing _site/_review (junk from the docx review render; it must not be published)."
  rm -rf _site/_review
fi
[ -d site_libs ] && yellow "A stray site_libs/ sits in the repo root (RStudio render leftover). Harmless; delete it."

if [ "$fail" = 1 ]; then
  echo "Not building the ZIP. Fix the errors above." >&2
  exit 1
fi

# --- Offline copy of the site -------------------------------------------------
# _quarto-offline.yml renders the pages with embed-resources, so the HTML in the
# ZIP works on a laptop with no network. freeze: auto means no code re-runs.
# The slides are not included: reveal.js can't be embedded in a project render
# without breaking it (see the profile file), and participants have them on the site.
rm -rf _offline
"$QUARTO" render --profile offline >/dev/null
[ -s _offline/notebook.html ] || { red "Offline render produced no _offline/notebook.html."; exit 1; }
# Quarto treats the other output folder as a project resource and copies it
# along, so each render nests the other. Neither copy belongs anywhere.
rm -rf _site/_offline _offline/_site

# --- Stage and zip -------------------------------------------------------------
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/$OUT/site"

cp -r data r stata python "$STAGE/$OUT/"
cp notebook.qmd _variables.yml "$STAGE/$OUT/"
[ -f workshop.Rproj ] && cp workshop.Rproj "$STAGE/$OUT/"
cp _offline/index.html _offline/notebook.html "$STAGE/$OUT/site/"
rm -f "$STAGE/$OUT/data/README.md"   # repo-facing notes, not for participants
find "$STAGE/$OUT" -name __pycache__ -type d -prune -exec rm -rf {} +   # py_compile leftovers

# The NaNDA extracts never ship. Whatever is in data/nanda/ on this machine was
# downloaded from ICPSR to render the page; it is not ours to redistribute.
# The folder and its README go in the ZIP so the path exists and tells people
# what to put there.
if [ -d "$STAGE/$OUT/data/nanda" ]; then
  find "$STAGE/$OUT/data/nanda" -mindepth 1 -maxdepth 1 ! -name README.md -exec rm -rf {} +
fi
[ -f "$STAGE/$OUT/data/nanda/README.md" ] || \
  yellow "data/nanda/README.md is missing; participants get an empty folder with no download instructions."

cat > "$STAGE/$OUT/README.txt" << INNER
Linking NaNDA With Your Data
GSA 2026 Annual Scientific Meeting, Breakout 2 (Intermediate)

You do not need to run any of this. The full notebook, with every output
already rendered, is at:

  $SITE_URL

Cite it: https://doi.org/10.5281/zenodo.23071407

MANIFEST

  README.txt          this file
  notebook.qmd        the notebook source (R). Open workshop.Rproj in RStudio
                      and press Render to run it yourself.
  workshop.Rproj      the RStudio project. Open it first so every path resolves.
  _variables.yml      names, DOIs and URLs the notebook reads

  site/               the notebook and the before-you-begin page, saved for
                      offline reading. Open site/notebook.html in any browser;
                      no internet needed.

  data/               what the scripts read
    synthetic_data_v20260924.csv           the synthetic survey
    synthetic_data_v20260924_tract10.csv   the same rows with a synthetic 2010
                                           tract ID added, for the tract scripts
    codebook_synthetic_data_v20260924.log  the codebook for both
    zip_to_zcta_2019.xlsx                  the ZIP-to-ZCTA crosswalk (UDS Mapper, 2019)
    nanda/                                 EMPTY except README.md. The NaNDA files
                                           come from ICPSR, which needs a free
                                           account; the README says which files
                                           and where to put them. You only need
                                           them to re-run the code.

  Scripts: one folder per language, two scripts per folder. Same steps, same
  block headers, so any two read side by side.

                    ZIP-to-ZCTA route            tract route
                    (what the session runs)      (a tract ID already on your data)
    r/              linking_nanda_zcta.R         linking_nanda_tract.R
    stata/          linking_nanda_zcta.do        linking_nanda_tract.do
    python/         linking_nanda_zcta.py        linking_nanda_tract.py

  Each folder has a README.md. r/README.md explains the tract route and lists
  where a tract ID comes from. Geocoding itself is not part of these materials.

Questions: $CONTACT
INNER

rm -f "_site/$OUT.zip"
if command -v zip >/dev/null 2>&1; then
  (cd "$STAGE" && zip -qr "$OLDPWD/_site/$OUT.zip" "$OUT")
elif [ -x /c/Windows/System32/tar.exe ]; then
  # Git Bash on Windows has no zip. Windows ships bsdtar, which writes a proper
  # ZIP (forward-slash entries, unlike PowerShell's Compress-Archive, which
  # writes backslashes that unpack wrongly on a Mac).
  /c/Windows/System32/tar.exe -a -cf "$(cygpath -w "$PWD/_site/$OUT.zip")" -C "$(cygpath -w "$STAGE")" "$OUT"
else
  red "Neither zip nor Windows tar.exe is available. Install zip (brew install zip / apt install zip)."
  exit 1
fi
[ -s "_site/$OUT.zip" ] || { red "No ZIP was written."; exit 1; }
echo "Built _site/$OUT.zip ($(du -h "_site/$OUT.zip" | cut -f1))"
if command -v unzip >/dev/null 2>&1; then
  unzip -l "_site/$OUT.zip" | awk 'NR>3 && $4 != "" {print "  " $4}' | grep -v '/$' || true
fi
