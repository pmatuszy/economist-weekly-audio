#!/usr/bin/env bash
# 2026.07.15 - v. 1.6 - _script_header.sh banner (version, hostname); skip startup delay when non-tty
# v. 1.5 - 2026.07.15 - renamed to economist-0-runme.sh; call economist-1..4-*.sh
# v. 1.3 - 2026.07.15 - restored numbered names 0-4-economist-*.sh
# v. 1.1 - 2026.07.15 - added script description header
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
# Orchestrates the full Economist weekly audio pipeline with healthcheck pings.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HEADER_EXTRA_ARGS=()
edition_date_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no_startup_delay|NO_STARTUP_DELAY)
            HEADER_EXTRA_ARGS+=(NO_STARTUP_DELAY)
            shift
            ;;
        -h|--help)
            cat <<EOF
Usage: $(basename "$0") [--no_startup_delay] [YYYY-MM-DD]

Run the full Economist weekly audio pipeline.

Options:
  --no_startup_delay   Skip random startup delay (recommended for cron).
  YYYY-MM-DD             Process a specific edition date instead of the latest.

Requires _script_header.sh in the same bin directory (from github-bin).
EOF
            exit 0
            ;;
        *)
            if [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ && $(date -d "$1" +%F 2>/dev/null) == "$1" ]]; then
                edition_date_args=("$1")
                shift
            else
                echo "Unknown argument or invalid date: $1" >&2
                echo "Expected YYYY-MM-DD (e.g., 2025-09-13) or --no_startup_delay" >&2
                exit 1
            fi
            ;;
    esac
done

if ! tty >/dev/null 2>&1; then
    HEADER_EXTRA_ARGS+=(NO_STARTUP_DELAY)
fi

_script_header_file=""
for _candidate in \
    "${SCRIPT_DIR}/_script_header.sh" \
    "/root/bin/_script_header.sh" \
    "${profile_location_dir:-$HOME}/bin/_script_header.sh"
do
    if [[ -f "${_candidate}" ]]; then
        _script_header_file="${_candidate}"
        break
    fi
done

if [[ -n "${_script_header_file}" ]]; then
    # shellcheck source=/dev/null
    . "${_script_header_file}" "${HEADER_EXTRA_ARGS[@]}"
    if (( ! script_is_run_interactively )); then
        echo "${SCRIPT_VERSION}"
        echo
    fi
else
    echo "Warning: _script_header.sh not found — skipping version banner." >&2
    echo "Install github-bin scripts into bin/ (expected: ${SCRIPT_DIR}/_script_header.sh)." >&2
fi

DEBUG=1

# shellcheck source=_load-config.sh
source "${SCRIPT_DIR}/_load-config.sh"
load_economist_config

########################################################################
log() {
    if [[ "$DEBUG" -eq 1 ]]; then
        echo "[DEBUG] $*"
    fi
}
########################################################################

args=()
if [[ ${#edition_date_args[@]} -eq 1 ]]; then
  args=("${edition_date_args[0]}")
fi

rmdir "${ECONOMIST_OUTPUT_DIR}"/* 2>/dev/null

hc_ping "/start"

wget_params="User-Agent: Mozilla/5.0"
economist_url="https://www.economist.com/weeklyedition/"

work_dir="${ECONOMIST_WORK_DIR}"

mkdir -p "${work_dir}" 2>/dev/null
cd "${work_dir}"

exit_code=$?
if (( exit_code != 0 )); then
   echo "Something went wrong — cannot change to directory \"${work_dir}\" (exit code ${exit_code})"
   exit $exit_code
fi

output_dir="${ECONOMIST_OUTPUT_DIR}"

export wget_params economist_url

UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36'
ARCHIVE='https://www.economist.com/weeklyedition/archive'

latest_edition="$(
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

if [[ ${#edition_date_args[@]} -eq 1 ]]; then
  latest_edition=https://www.economist.com/weeklyedition/"${edition_date_args[0]}"
fi

log "latest_edition = $latest_edition"

edition_directory="${output_dir}/$(echo "${latest_edition}" | awk -F'/' '{split($NF, date, "-"); print date[1]"."date[2]"."date[3]}')_TheEconomist"
log "edition_directory = $edition_directory"

if [[ -d "${edition_directory}" && $(/bin/ls -A "${edition_directory}") ]]; then
   log_part1=$( echo ;  echo ;
   echo "Directory ${edition_directory} exists and is not empty";
   echo "Will not download this edition again...";
   echo "... exiting.";)
   hc_ping "" "${log_part1}"
   log "$log_part1"
   exit 0
fi

mkdir -p "${edition_directory}" 2>/dev/null
cd "${edition_directory}"

log "working directory: $(pwd)"

log_part1=$(echo ; "${SCRIPT_DIR}/economist-1-download.sh" "${args[@]}" ; exit $?)
exit_code=$?

log "output from ${SCRIPT_DIR}/economist-1-download.sh:"
log "$log_part1"
log ""

log "exit code from ${SCRIPT_DIR}/economist-1-download.sh = $exit_code"

if [[ $exit_code -eq 2 ]]; then
  hc_ping "" "${log_part1}"
  echo "Cleaning up incomplete directory: ${edition_directory}"
  rmdir --ignore-fail-on-non-empty "${edition_directory}"
  exit $exit_code
fi

log_part2=$(echo ; "${SCRIPT_DIR}/economist-2-process-edition.sh" "${args[@]}" ; exit $?)
exit_code=$?

log "output from ${SCRIPT_DIR}/economist-2-process-edition.sh:"
log "$log_part2"
log ""

if [[ $exit_code -ne 0 ]]; then
  hc_ping "/fail" "${log_part1}${log_part2}"
  echo "Cleaning up incomplete directory: ${edition_directory}"
  rmdir --ignore-fail-on-non-empty "${edition_directory}"
  exit $exit_code
fi

log_part3=$(echo ; "${SCRIPT_DIR}/economist-3-speedup-loudness.sh" ; exit $?)
exit_code=$?

if [[ $exit_code -ne 0 ]]; then
  hc_ping "/fail" "${log_part1}${log_part2}${log_part3}"
  echo "Cleaning up incomplete directory: ${edition_directory}"
  rmdir --ignore-fail-on-non-empty "${edition_directory}"
  exit $exit_code
fi

log_part4=$(echo ; "${SCRIPT_DIR}/economist-4-move-results.sh" ; exit $?)
exit_code=$?

if [[ $exit_code -ne 0 ]]; then
  hc_ping "/fail" "${log_part1}${log_part2}${log_part3}${log_part4}"
  exit $exit_code
fi

hc_ping "" "${log_part1}${log_part2}${log_part3}${log_part4}"
