#!/usr/bin/env bash
# v. 1.0 - 2026.06.19 - runtime messages translated to English
# v. 0.9 - 2026.06.19 - changelog comments translated to English
# v. 0.8 - 2026.06.19 - child scripts: English filenames (download, process-edition, speedup-loudness, move-results)
# v. 0.7 - 2026.06.16 - secrets in economist.local.conf; child scripts via SCRIPT_DIR
# v. 0.6 - 2025.04.18 - ping healthcheck OK when output directory already exists (edition already downloaded)
# v. 0.5 - 2025.01.28 - major changes after The Economist portal changes
# v. 0.4 - 2022.05.06 - added healthcheck support
# v. 0.3 - 2021.06.07 - check exit codes from all child scripts
# v. 0.2 - 2021.04.19 - check exit code from 1-economist-download.sh
# v. 0.1 - 2018.07.31 - initial release

DEBUG=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_load-config.sh
source "${SCRIPT_DIR}/_load-config.sh"
load_economist_config

# Edition dates: https://www.economist.com/weeklyedition/archive

# Arg is optional; if provided it must be a real date in YYYY-MM-DD
[[ $# -eq 0 ]] || [[ $1 =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ && $(date -d "$1" +%F 2>/dev/null) == "$1" ]] || { echo "Expected YYYY-MM-DD (e.g., 2025-09-13)"; exit 1; }

########################################################################
log() {
    if [[ "$DEBUG" -eq 1 ]]; then
        echo "[DEBUG] $*"
    fi
}
########################################################################

args=()
if [[ $# -eq 1 ]]; then
  args=("$1")
fi

rmdir "${ECONOMIST_OUTPUT_DIR}"/* 2>/dev/null

hc_ping "/start"

wget_params="User-Agent: Mozilla/5.0"
economist_url="https://www.economist.com/weeklyedition/"

katalog_roboczy="${ECONOMIST_WORK_DIR}"

mkdir -p "${katalog_roboczy}" 2>/dev/null
cd "${katalog_roboczy}"

kod_powrotu=$?
if (( kod_powrotu != 0 )); then
   echo "Something went wrong — cannot change to directory \"${katalog_roboczy}\" (exit code ${kod_powrotu})"
   exit $kod_powrotu
fi

kat_wynikowy="${ECONOMIST_OUTPUT_DIR}"

export wget_params economist_url

UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36'
ARCHIVE='https://www.economist.com/weeklyedition/archive'

najnowsze_wydanie="$(
  wget -qO- --user-agent="$UA" \
    --header='Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' \
    --header='Accept-Language: en-US,en;q=0.9' \
    --header='Upgrade-Insecure-Requests: 1' \
    --header='Accept-Encoding: gzip' \
    --referer='https://www.economist.com/' \
    --compression=auto \
    --tries=5 --timeout=20 --max-redirect=10 \
    "$ARCHIVE" \
  | grep -oE '/weeklyedition/[0-9]{4}-[0-9]{2}-[0-9]{2}' \
  | head -n1 | sed 's#^#https://www.economist.com#' | sort -u
)"

if [[ "$#" -eq 1 ]]; then
  najnowsze_wydanie=https://www.economist.com/weeklyedition/"$1"
fi

log "latest_edition = $najnowsze_wydanie"

nazwa_katalogu="${kat_wynikowy}/$(echo "${najnowsze_wydanie}" | awk -F'/' '{split($NF, date, "-"); print date[1]"."date[2]"."date[3]}')_TheEconomist"
log "edition_directory = $nazwa_katalogu"

if [[ -d "${nazwa_katalogu}" && $(/bin/ls -A "${nazwa_katalogu}") ]]; then
   log_cz1=$( echo ;  echo ;
   echo "Directory ${nazwa_katalogu} exists and is not empty";
   echo "Will not download this edition again...";
   echo "... exiting.";)
   hc_ping "" "${log_cz1}"
   log "$log_cz1"
   exit 0
fi

mkdir -p "${nazwa_katalogu}" 2>/dev/null
cd "${nazwa_katalogu}"

log "working directory: $(pwd)"

log_cz1=$(echo ; "${SCRIPT_DIR}/1-economist-download.sh" "${args[@]}" ; exit $?)
kod_powrotu=$?

log "output from ${SCRIPT_DIR}/1-economist-download.sh:"
log "$log_cz1"
log ""

log "exit code from ${SCRIPT_DIR}/1-economist-download.sh = $kod_powrotu"

if [[ $kod_powrotu -eq 2 ]]; then
  hc_ping "" "${log_cz1}"
  echo "Cleaning up incomplete directory: ${nazwa_katalogu}"
  rmdir --ignore-fail-on-non-empty "${nazwa_katalogu}"
  exit $kod_powrotu
fi

log_cz2=$(echo ; "${SCRIPT_DIR}/2-economist-process-edition.sh" "${args[@]}" ; exit $?)
kod_powrotu=$?

log "output from ${SCRIPT_DIR}/2-economist-process-edition.sh:"
log "$log_cz2"
log ""

if [[ $kod_powrotu -ne 0 ]]; then
  hc_ping "/fail" "${log_cz1}${log_cz2}"
  echo "Cleaning up incomplete directory: ${nazwa_katalogu}"
  rmdir --ignore-fail-on-non-empty "${nazwa_katalogu}"
  exit $kod_powrotu
fi

log_cz3=$(echo ; "${SCRIPT_DIR}/3-economist-speedup-loudness.sh" ; exit $?)
kod_powrotu=$?

if [[ $kod_powrotu -ne 0 ]]; then
  hc_ping "/fail" "${log_cz1}${log_cz2}${log_cz3}"
  echo "Cleaning up incomplete directory: ${nazwa_katalogu}"
  rmdir --ignore-fail-on-non-empty "${nazwa_katalogu}"
  exit $kod_powrotu
fi

log_cz4=$(echo ; "${SCRIPT_DIR}/4-economist-move-results.sh" ; exit $?)
kod_powrotu=$?

if [[ $kod_powrotu -ne 0 ]]; then
  hc_ping "/fail" "${log_cz1}${log_cz2}${log_cz3}${log_cz4}"
  exit $kod_powrotu
fi

hc_ping "" "${log_cz1}${log_cz2}${log_cz3}${log_cz4}"
