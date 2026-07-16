#!/usr/bin/env bash
# 2026.07.16 - v. 1.17 - quit when no new RSS edition; proceed prompt only if new
# 2026.07.16 - v. 1.16 - RSS verify + proceed prompt before download (10s, Y default)
# 2026.07.16 - v. 1.15 - print summary when user quits show-available without picking
# 2026.07.16 - v. 1.14 - show-available confirm pick; force reprocess when confirmed
# 2026.07.15 - v. 1.13 - --show-available lists verified RSS editions and interactive pick
# 2026.07.15 - v. 1.12 - pipeline exit records finish time before summary
# 2026.07.15 - v. 1.11 - align debug label values in a fixed column
# 2026.07.15 - v. 1.10 - clearer English debug labels
# 2026.07.15 - v. 1.9 - dot _script_header.sh at script top level (fixes banner)
# 2026.07.15 - v. 1.7 - Ctrl-C cleanup, pipeline summary, improved child step capture
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

if [[ "${0:-}" == *"/scripts/"* ]] || [[ "$(basename "${0:-}")" == 0-economist-runme.sh ]]; then
    echo "WARNING: obsolete script path: ${0}" >&2
    echo "Use ${profile_location_dir:-$HOME}/bin/economist-0-runme.sh instead." >&2
    echo "Run: ${profile_location_dir:-$HOME}/bin/economist-script-reinstall.sh -y" >&2
    echo >&2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HEADER_EXTRA_ARGS=()
edition_date_args=()
SHOW_AVAILABLE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no_startup_delay|NO_STARTUP_DELAY)
            HEADER_EXTRA_ARGS+=(NO_STARTUP_DELAY)
            shift
            ;;
        --show-available|--list-available)
            SHOW_AVAILABLE=1
            HEADER_EXTRA_ARGS+=(NO_STARTUP_DELAY)
            shift
            ;;
        -h|--help)
            cat <<EOF
Usage: $(basename "$0") [--no_startup_delay] [--show-available] [YYYY-MM-DD]

Run the full Economist weekly audio pipeline.

Options:
  --no_startup_delay   Skip random startup delay (recommended for cron).
  --show-available     List RSS editions verified on the server; pick one to download.
  --list-available     Alias for --show-available.
  YYYY-MM-DD             Process a specific edition date instead of the latest.

Requires github-bin _script_header.sh in \${profile_location_dir:-\$HOME}/bin/.
EOF
            exit 0
            ;;
        *)
            if [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ && $(date -d "$1" +%F 2>/dev/null) == "$1" ]]; then
                edition_date_args=("$1")
                shift
            else
                echo "Unknown argument or invalid date: $1" >&2
                echo "Expected YYYY-MM-DD (e.g., 2025-09-13), --show-available, or --no_startup_delay" >&2
                exit 1
            fi
            ;;
    esac
done

if ! tty >/dev/null 2>&1; then
    HEADER_EXTRA_ARGS+=(NO_STARTUP_DELAY)
fi

# shellcheck source=_load-config.sh
source "${SCRIPT_DIR}/_load-config.sh"
_economist_header_file="$(economist_find_script_header_file)" || true
if [[ -n "${_economist_header_file}" ]]; then
    if [[ ${#HEADER_EXTRA_ARGS[@]} -eq 0 ]] && ! tty >/dev/null 2>&1; then
        # shellcheck source=/dev/null
        . "${_economist_header_file}" NO_STARTUP_DELAY
    else
        # shellcheck source=/dev/null
        . "${_economist_header_file}" "${HEADER_EXTRA_ARGS[@]}"
    fi
    if (( ! script_is_run_interactively )); then
        echo "${SCRIPT_VERSION}"
        echo
    fi
else
    echo "Warning: _script_header.sh not found — install github-bin into ${profile_location_dir:-$HOME}/bin/." >&2
fi
unset _economist_header_file

DEBUG=1

load_economist_config
require_economist_rss_url

economist_run_control_init pipeline
economist_install_run_traps

ECONOMIST_PIPELINE_WORK_DIR="${ECONOMIST_WORK_DIR}"
ECONOMIST_PIPELINE_OUTPUT_DIR="${ECONOMIST_OUTPUT_DIR}"

if (( SHOW_AVAILABLE )); then
    if [[ ${#edition_date_args[@]} -eq 1 ]]; then
        echo "Cannot use --show-available together with an edition date." >&2
        exit 1
    fi
    economist_set_run_step show_available
    picked_edition=""
    force_reprocess=0
    if ! economist_show_and_pick_available_editions picked_edition force_reprocess; then
        economist_set_run_step show_available_quit
        economist_finish_run 1
    fi
    if [[ -z "${picked_edition}" ]]; then
        economist_set_run_step show_available_quit
        economist_finish_run 0
    fi
    edition_date_args=("${picked_edition}")
    ECONOMIST_FORCE_REPROCESS="${force_reprocess}"
    ECONOMIST_SKIP_DOWNLOAD_PROCEED_PROMPT=1
fi

########################################################################
log() {
    if [[ "$DEBUG" -eq 1 ]]; then
        echo "[DEBUG] $*"
    fi
}

log_kv() {
    if [[ "$DEBUG" -eq 1 ]]; then
        printf '[DEBUG] %-27s%s\n' "$1" "$2"
    fi
}

run_pipeline_child() {
    local step="$1"
    local script="$2"
    shift 2
    local log_file rc

    economist_set_run_step "${step}"
    log_file="$(mktemp)"

    set +e
    {
        echo
        ECONOMIST_PIPELINE_PARENT=1 "${script}" "$@"
    } 2>&1 | tee "${log_file}"
    rc=${PIPESTATUS[0]}
    set -e

    cat "${log_file}"
    rm -f "${log_file}"
    return "${rc}"
}

economist_exit_pipeline() {
    local exit_code="$1"

    ECONOMIST_RUN_EXIT_CODE="${exit_code}"
    economist_mark_finish_time
    economist_print_summary || true
    exit "${exit_code}"
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
output_dir="${ECONOMIST_OUTPUT_DIR}"

ECONOMIST_PIPELINE_WORK_DIR="${work_dir}"
ECONOMIST_PIPELINE_OUTPUT_DIR="${output_dir}"

mkdir -p "${work_dir}" 2>/dev/null
cd "${work_dir}"

exit_code=$?
if (( exit_code != 0 )); then
    echo "Something went wrong — cannot change to directory \"${work_dir}\" (exit code ${exit_code})"
    economist_exit_pipeline "${exit_code}"
fi

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

archive_edition_url="${latest_edition}"
explicit_edition_iso=""
if [[ ${#edition_date_args[@]} -eq 1 ]]; then
    explicit_edition_iso="${edition_date_args[0]}"
fi

resolved_edition_iso=""
if [[ "${ECONOMIST_SKIP_DOWNLOAD_PROCEED_PROMPT:-0}" != 1 ]]; then
    if ! economist_check_new_edition_for_run "${explicit_edition_iso}" "${ECONOMIST_FORCE_REPROCESS:-0}" resolved_edition_iso; then
        if [[ -n "${archive_edition_url}" ]]; then
            log_kv "Economist.com archive:" "${archive_edition_url}"
        fi
        economist_set_run_step no_new_edition
        economist_exit_pipeline 0
    fi
else
    resolved_edition_iso="${explicit_edition_iso}"
    if [[ -z "${resolved_edition_iso}" ]]; then
        resolved_edition_iso="$(economist_edition_iso_from_weekly_url "${archive_edition_url}" 2>/dev/null || true)"
    fi
    if [[ -z "${resolved_edition_iso}" ]]; then
        echo "Cannot determine edition date." >&2
        economist_exit_pipeline 1
    fi
fi

latest_edition="https://www.economist.com/weeklyedition/${resolved_edition_iso}"
args=("${resolved_edition_iso}")

if [[ -n "${archive_edition_url}" && "${archive_edition_url}" != "${latest_edition}" ]]; then
    log_kv "Economist.com archive:" "${archive_edition_url}"
fi

log_kv "Latest edition URL:" "${latest_edition}"

edition_directory="${output_dir}/$(echo "${latest_edition}" | awk -F'/' '{split($NF, date, "-"); print date[1]"."date[2]"."date[3]}')_TheEconomist"
edition_name="$(basename "${edition_directory}")"
log_kv "Edition output directory:" "${edition_directory}"

ECONOMIST_PIPELINE_EDITION_URL="${latest_edition}"
ECONOMIST_PIPELINE_EDITION_DIR="${edition_directory}"
ECONOMIST_PIPELINE_EDITION_NAME="${edition_name}"

if [[ -d "${edition_directory}" && $(/bin/ls -A "${edition_directory}") ]]; then
    if [[ "${ECONOMIST_FORCE_REPROCESS:-0}" == 1 ]]; then
        echo "Force reprocess — removing existing edition output and work files..."
        economist_force_reprocess_edition "${edition_directory}" "${work_dir}"
    else
        log_part1=$(
            echo
            echo "Directory ${edition_directory} exists and is not empty"
            echo "Will not download this edition again..."
            echo "... exiting."
        )
        economist_set_run_step already_exists
        hc_ping "" "${log_part1}"
        log "$log_part1"
        economist_exit_pipeline 0
    fi
fi

mkdir -p "${edition_directory}" 2>/dev/null
cd "${edition_directory}"

log_kv "Current working directory:" "$(pwd)"

issue_no="$(economist_issue_number_for_edition_date "${resolved_edition_iso}" 2>/dev/null || echo "—")"
log_kv "RSS/server check:" "available (issue ${issue_no})"

if [[ "${ECONOMIST_SKIP_DOWNLOAD_PROCEED_PROMPT:-0}" != 1 ]]; then
    if ! economist_prompt_proceed_before_download "${resolved_edition_iso}"; then
        echo "Download cancelled."
        economist_set_run_step pipeline_confirm_quit
        economist_cleanup_pipeline_artifacts "${work_dir}" "${edition_directory}" "${output_dir}" "${edition_name}"
        economist_exit_pipeline 0
    fi
fi

log_part1="$(run_pipeline_child download "${SCRIPT_DIR}/economist-1-download.sh" "${args[@]}")"
exit_code=$?
ECONOMIST_PIPELINE_RC_DOWNLOAD="${exit_code}"

log "Output from ${SCRIPT_DIR}/economist-1-download.sh:"
log "$log_part1"
log ""
log "Exit code from ${SCRIPT_DIR}/economist-1-download.sh: ${exit_code}"

if (( exit_code == 130 )); then
    ECONOMIST_STOPPED_BY_USER=yes
    economist_cleanup_pipeline_artifacts "${work_dir}" "${edition_directory}" "${output_dir}" "${edition_name}"
    economist_exit_pipeline 130
fi

if [[ $exit_code -eq 2 ]]; then
    hc_ping "" "${log_part1}"
    economist_cleanup_pipeline_artifacts "${work_dir}" "${edition_directory}" "${output_dir}" "${edition_name}"
    economist_exit_pipeline "${exit_code}"
fi

if (( exit_code != 0 )); then
    hc_ping "/fail" "${log_part1}"
    economist_cleanup_pipeline_artifacts "${work_dir}" "${edition_directory}" "${output_dir}" "${edition_name}"
    economist_exit_pipeline "${exit_code}"
fi

log_part2="$(run_pipeline_child process "${SCRIPT_DIR}/economist-2-process-edition.sh" "${args[@]}")"
exit_code=$?
ECONOMIST_PIPELINE_RC_PROCESS="${exit_code}"

log "Output from ${SCRIPT_DIR}/economist-2-process-edition.sh:"
log "$log_part2"
log ""

if (( exit_code == 130 )); then
    ECONOMIST_STOPPED_BY_USER=yes
    economist_cleanup_pipeline_artifacts "${work_dir}" "${edition_directory}" "${output_dir}" "${edition_name}"
    economist_exit_pipeline 130
fi

if [[ $exit_code -ne 0 ]]; then
    hc_ping "/fail" "${log_part1}${log_part2}"
    economist_cleanup_pipeline_artifacts "${work_dir}" "${edition_directory}" "${output_dir}" "${edition_name}"
    economist_exit_pipeline "${exit_code}"
fi

log_part3="$(run_pipeline_child speedup "${SCRIPT_DIR}/economist-3-speedup-loudness.sh")"
exit_code=$?
ECONOMIST_PIPELINE_RC_SPEEDUP="${exit_code}"

if (( exit_code == 130 )); then
    ECONOMIST_STOPPED_BY_USER=yes
    economist_cleanup_pipeline_artifacts "${work_dir}" "${edition_directory}" "${output_dir}" "${edition_name}"
    economist_exit_pipeline 130
fi

if [[ $exit_code -ne 0 ]]; then
    hc_ping "/fail" "${log_part1}${log_part2}${log_part3}"
    economist_cleanup_pipeline_artifacts "${work_dir}" "${edition_directory}" "${output_dir}" "${edition_name}"
    economist_exit_pipeline "${exit_code}"
fi

log_part4="$(run_pipeline_child move "${SCRIPT_DIR}/economist-4-move-results.sh")"
exit_code=$?
ECONOMIST_PIPELINE_RC_MOVE="${exit_code}"

if (( exit_code == 130 )); then
    ECONOMIST_STOPPED_BY_USER=yes
    economist_cleanup_pipeline_artifacts "${work_dir}" "${edition_directory}" "${output_dir}" "${edition_name}"
    economist_exit_pipeline 130
fi

if [[ $exit_code -ne 0 ]]; then
    hc_ping "/fail" "${log_part1}${log_part2}${log_part3}${log_part4}"
    economist_exit_pipeline "${exit_code}"
fi

economist_set_run_step complete
hc_ping "" "${log_part1}${log_part2}${log_part3}${log_part4}"
economist_exit_pipeline 0
