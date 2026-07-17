#!/usr/bin/env bash
# v. 20260717.124401 - print validated config block before RSS/edition checks
# v. 20260717.124001 - browse nearby editions when user explicitly declines nearest
# v. 20260717.123001 - status messages while fetching/checking RSS
# v. 20260717.122001 - website hint only when checking latest edition (no CLI date)
# v. 20260717.120501 - CLI date: resolve + pick-style confirm before pipeline start
# v. 20260717.120301 - accept YYYY.MM.DD edition date on command line
# v. 20260717.090001 - --force/-f; YYYYMMDD date; nearest edition fallback
# v. 20260717.082501 - pass sat_iso to processed-edition check before download
# v. 20260716.233501 - detect processed editions in work dir as well as output dir
# v. 20260716.162603 - orchestrate full pipeline with healthcheck pings
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
raw_date_args=()
SHOW_AVAILABLE=0
FORCE_REPROCESS=0
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
        -f|--force)
            FORCE_REPROCESS=1
            shift
            ;;
        -h|--help)
            cat <<EOF
Usage: $(basename "$0") [options] [YYYY-MM-DD | YYYY.MM.DD | YYYYMMDD]

Run the full Economist weekly audio pipeline.

Options:
  --no_startup_delay   Skip random startup delay (recommended for cron).
  --show-available     List RSS editions verified on the server; pick one to download.
  --list-available     Alias for --show-available.
  -f, --force          Re-download and reprocess even if the edition already exists.
  YYYY-MM-DD           Download a specific edition cover date (e.g. 2026-07-18).
  YYYY.MM.DD           Same with dots (e.g. 2026.07.18).
  YYYYMMDD             Same without separators (e.g. 20260718).

If the requested date is not on the RSS server, the nearest verified edition is
suggested interactively (default: no).

Requires github-bin _script_header.sh in \${profile_location_dir:-\$HOME}/bin/.
EOF
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            echo "Try: $(basename "$0") --help" >&2
            exit 1
            ;;
        *)
            raw_date_args+=("$1")
            shift
            ;;
    esac
done

if (( ${#raw_date_args[@]} > 1 )); then
    echo "Specify at most one edition date." >&2
    exit 1
fi

if ! tty >/dev/null 2>&1; then
    HEADER_EXTRA_ARGS+=(NO_STARTUP_DELAY)
fi

# shellcheck source=_load-config.sh
source "${SCRIPT_DIR}/_load-config.sh"

load_economist_config
validate_economist_config

if (( ${#raw_date_args[@]} == 1 )); then
    normalized_edition_iso=""
    if ! normalized_edition_iso="$(economist_normalize_edition_iso "${raw_date_args[0]}")"; then
        echo "Invalid edition date: ${raw_date_args[0]}" >&2
        echo "Expected YYYY-MM-DD, YYYY.MM.DD, or YYYYMMDD (e.g. 2026-07-18)." >&2
        exit 1
    fi
    edition_date_args=("${normalized_edition_iso}")
fi

ECONOMIST_FORCE_REPROCESS="${FORCE_REPROCESS}"

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

economist_run_control_init pipeline
economist_install_run_traps

if [[ -t 0 ]] || [[ -r /dev/tty ]]; then
    echo
    economist_print_config_ok
    echo
    ECONOMIST_CONFIG_OK_PRINTED=1
fi

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
    if (( FORCE_REPROCESS )); then
        ECONOMIST_FORCE_REPROCESS=1
    else
        ECONOMIST_FORCE_REPROCESS="${force_reprocess}"
    fi
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

UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36'
ARCHIVE='https://www.economist.com/weeklyedition/archive'

economist_fetch_website_newest_edition_url() {
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
}

args=()
if [[ ${#edition_date_args[@]} -eq 1 ]]; then
    args=("${edition_date_args[0]}")
fi

explicit_edition_iso=""
if [[ ${#edition_date_args[@]} -eq 1 ]]; then
    explicit_edition_iso="${edition_date_args[0]}"
fi

resolved_edition_iso=""
if [[ "${ECONOMIST_SKIP_DOWNLOAD_PROCEED_PROMPT:-0}" != 1 ]]; then
    if ! economist_check_new_edition_for_run "${explicit_edition_iso}" "${ECONOMIST_FORCE_REPROCESS:-0}" resolved_edition_iso; then
        if [[ -z "${explicit_edition_iso}" ]]; then
            website_url=""
            website_iso=""
            website_url="$(economist_fetch_website_newest_edition_url 2>/dev/null || true)"
            if [[ -n "${website_url}" ]]; then
                website_iso="$(economist_edition_iso_from_weekly_url "${website_url}" 2>/dev/null || true)"
            fi
            if [[ -n "${website_iso}" ]]; then
                economist_print_website_vs_rss_explanation "${website_iso}"
            fi
            economist_set_run_step no_new_edition
        else
            economist_set_run_step pipeline_confirm_quit
        fi
        economist_exit_pipeline 0
    fi

    confirm_force="${ECONOMIST_FORCE_REPROCESS:-0}"
    confirm_rc=0
    economist_confirm_edition_before_download "${resolved_edition_iso}" confirm_force
    confirm_rc=$?
    if (( confirm_rc != 0 )); then
        echo "Download cancelled."
        economist_set_run_step pipeline_confirm_quit
        economist_finish_run 0
    fi
    ECONOMIST_FORCE_REPROCESS="${confirm_force}"
else
    resolved_edition_iso="${explicit_edition_iso}"
    if [[ -z "${resolved_edition_iso}" ]]; then
        resolved_edition_iso="$(
            economist_edition_iso_from_weekly_url "$(economist_fetch_website_newest_edition_url 2>/dev/null || true)" 2>/dev/null || true
        )"
    fi
    if [[ -z "${resolved_edition_iso}" ]]; then
        echo "Cannot determine edition date." >&2
        economist_exit_pipeline 1
    fi
fi

latest_edition="https://www.economist.com/weeklyedition/${resolved_edition_iso}"
args=("${resolved_edition_iso}")

log_kv "RSS edition to download:" "${latest_edition}"

edition_directory="$(economist_edition_output_dir_for_date "${resolved_edition_iso}")"
edition_name="$(basename "${edition_directory}")"
log_kv "Edition output directory:" "${edition_directory}"

ECONOMIST_PIPELINE_EDITION_URL="${latest_edition}"
ECONOMIST_PIPELINE_EDITION_DIR="${edition_directory}"
ECONOMIST_PIPELINE_EDITION_NAME="${edition_name}"

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

economist_cleanup_stale_run_leftovers "${work_dir}" "${output_dir}"

export wget_params economist_url

status_issue_no="$(economist_issue_number_for_edition_date "${resolved_edition_iso}" 2>/dev/null || true)"
status_sat_iso="$(economist_sat_iso_for_edition_iso "${resolved_edition_iso}" 2>/dev/null || true)"
status_dir="$(economist_resolve_processed_edition_dir "${resolved_edition_iso}" "${status_sat_iso}" "${status_issue_no}" 2>/dev/null || true)"
if [[ -n "${status_dir}" ]]; then
    if [[ "${ECONOMIST_FORCE_REPROCESS:-0}" == 1 ]]; then
        echo "Force reprocess — removing existing edition output and work files..."
        economist_force_reprocess_edition "${status_dir}" "${work_dir}"
    else
        log_part1=$(
            echo
            echo "Edition ${resolved_edition_iso} (issue ${status_issue_no}) is already processed:"
            echo "  ${status_dir}"
            echo "Will not download this edition again..."
            economist_force_redownload_hint
            echo "... exiting."
        )
        economist_set_run_step already_exists
        hc_ping "" "${log_part1}"
        log "$log_part1"
        economist_exit_pipeline 0
    fi
fi

economist_remove_empty_edition_placeholders_for_iso "${resolved_edition_iso}"

mkdir -p "${edition_directory}" 2>/dev/null
cd "${edition_directory}"

log_kv "Current working directory:" "$(pwd)"

issue_no="$(economist_issue_number_for_edition_date "${resolved_edition_iso}" 2>/dev/null || echo "—")"
log_kv "RSS/server check:" "available (issue ${issue_no})"

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
