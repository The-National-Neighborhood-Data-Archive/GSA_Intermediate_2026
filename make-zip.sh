#!/usr/bin/env bash
# Build the participant-facing materials ZIP into _site/ so the packet URL resolves.
# Run AFTER `quarto render`, BEFORE `quarto publish gh-pages`.
#
# The script refuses to build a ZIP a participant couldn't use:
#   - every data file the walkthrough reads must be in data/
#   - the Stata and Python scripts must be present
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

# --- Gate 3: the Stata and Python versions -----------------------------------
ls stata/*.do  >/dev/null 2>&1 || red "stata/ has no .do file. The page promises one."
ls python/*.py >/dev/null 2>&1 || red "python/ has no .py file. The page promises one."

# --- Gate 4: URLs point at this repo -----------------------------------------
# GitHub Pages lowercases the org, so compare case-insensitively.
repo=$(basename -s .git "$(git remote get-url origin 2>/dev/null || echo unknown)")
repo_lc=$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]')
url_fail=0
for key in url zip repo; do
  val=$(awk -v k="  $key:" '$0 ~ "^"k {sub(/^[^"]*"/,""); sub(/".*$/,""); print; exit}' _variables.yml)
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

# --- Stage and zip -------------------------------------------------------------
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/$OUT/site"

cp -r data stata python "$STAGE/$OUT/"
cp notebook.qmd _variables.yml "$STAGE/$OUT/"
[ -f workshop.Rproj ] && cp workshop.Rproj "$STAGE/$OUT/"
cp _offline/index.html _offline/notebook.html "$STAGE/$OUT/site/"
rm -f "$STAGE/$OUT/data/README.md"   # repo-facing notes, not for participants

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
GSA 2026 Annual Scientific Meeting — Breakout 2 (Intermediate)

You do not need to run any of this. The full walkthrough, with every output
already rendered, is at:

  https://the-national-neighborhood-data-archive.github.io/GSA_Intermediate_2026/

What's in here:
  site/      the walkthrough and the before-you-join page, saved for offline
             reading. Open site/notebook.html in any browser; no internet needed.
  data/      synthetic dataset, its codebook, and the ZIP-to-ZCTA crosswalk.
             The NaNDA files are NOT in here — they come from ICPSR, which
             needs a free account. data/nanda/README.md has the three
             downloads and where to put them. You only need them if you want
             to re-run the code; the walkthrough already shows every output.
  stata/     the Stata version of the walkthrough, step for step
  python/    the Python version of the walkthrough, step for step
  notebook.qmd   the walkthrough source (R, with the same Stata and Python
                 steps shown one tab away on the web page). Open workshop.Rproj
                 in RStudio and press Render to run it yourself.

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
