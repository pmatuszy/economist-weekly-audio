# shellcheck shell=bash
# 2026.07.15 - v. 2.2 - quiet rollback: remove only empty output placeholders
# 2026.07.15 - v. 2.1 - acquire flock at startup; skip if another instance is running
# 2026.07.15 - v. 2.0 - merge run-control (traps, summary, cleanup) into this file
# v. 1.4 - 2026.07.15 - load config from ${profile_location_dir:-$HOME}/conf/
# v. 1.0 - 2026.06.16 - shared config loader for pipeline scripts
# Shared library: config, header lookup, Ctrl-C cleanup, and run summary.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Source this file; do not execute it directly." >&2
    exit 1
fi

economist_find_script_header_file() {
    local base_dir candidate

    base_dir="${profile_location_dir:-$HOME}"
    for candidate in \
        "${base_dir}/bin/_script_header.sh" \
        "/root/bin/_script_header.sh" \
        "$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)/_script_header.sh"
    do
        if [[ -f "${candidate}" ]]; then
            echo "${candidate}"
            return 0
        fi
    done
    return 1
}

economist_conf_octal_mode() {
    local path="$1"

    if stat -c '%a' "${path}" &>/dev/null; then
        stat -c '%a' "${path}"
    elif stat -f '%OLp' "${path}" &>/dev/null; then
        stat -f '%OLp' "${path}"
    else
        echo ""
    fi
}

assert_economist_conf_permissions() {
    local conf="$1" check_path mode

    check_path="${conf}"
    if [[ -L "${conf}" ]]; then
        check_path="$(readlink -f "${conf}" 2>/dev/null || realpath "${conf}" 2>/dev/null || echo "${conf}")"
    fi

    mode="$(economist_conf_octal_mode "${check_path}")"
    if [[ -z "${mode}" ]]; then
        echo "Cannot read permissions for economist.local.conf: ${conf}" >&2
        exit 1
    fi

    if (( 8#${mode} != 8#600 )); then
        echo "economist.local.conf must be mode 0600 (owner read/write only), got ${mode}: ${conf}" >&2
        echo "Fix: chmod 600 \"${check_path}\"" >&2
        exit 1
    fi
}

economist_default_conf_paths() {
    local root="$1"
    local base="${profile_location_dir:-$HOME}"

    echo "${base}/conf/economist.local.conf"
    echo "${root}/economist.local.conf"
    echo "${root}/../economist-weekly-audio-private/economist.local.conf"
    echo "${root}/../github-economist-weekly-audio-private/economist.local.conf"
}

load_economist_config() {
    local conf root script_dir candidate

    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    root="$(cd "${script_dir}/.." && pwd)"

    if [[ -n "${ECONOMIST_CONF:-}" ]]; then
        conf="${ECONOMIST_CONF}"
    else
        conf=""
        while IFS= read -r candidate; do
            if [[ -f "${candidate}" ]]; then
                conf="${candidate}"
                break
            fi
        done < <(economist_default_conf_paths "${root}")
    fi

    if [[ -z "${conf}" || ! -f "${conf}" ]]; then
        echo "Missing economist.local.conf" >&2
        echo "Options:" >&2
        echo "  1) run install.sh to copy config into \${profile_location_dir:-\$HOME}/conf/economist.local.conf" >&2
        echo "  2) cp economist.conf.example economist.local.conf, chmod 600, and edit" >&2
        echo "  3) clone economist-weekly-audio-private next to this repo (e.g. \${profile_location_dir:-\$HOME}/github/economist-weekly-audio-private)" >&2
        echo "  4) set ECONOMIST_CONF=/path/to/economist.local.conf" >&2
        exit 1
    fi

    assert_economist_conf_permissions "${conf}"

    # shellcheck source=/dev/null
    source "${conf}"

    : "${ECONOMIST_BASE_DIR:=/worek/economist/theEconomist}"
    : "${ECONOMIST_WORK_DIR:=${ECONOMIST_BASE_DIR}/katalog-roboczy}"
    : "${ECONOMIST_OUTPUT_DIR:=${ECONOMIST_BASE_DIR}/_obrobione}"
    : "${FFMPEG_PATH:=/usr/local/bin/ffmpeg}"
    : "${ECONOMIST_FILE_OWNER:=}"
    : "${CURL_IMPERSONATE:=/usr/local/bin/curl-impersonate/curl_chrome116}"
    : "${HEALTHCHECK_URL:=}"
    : "${ECONOMIST_LOCK_FILE:=/var/lock/economist-runme.lock}"
}

require_economist_rss_url() {
    if [[ -z "${ECONOMIST_RSS_URL:-}" ]]; then
        echo "ECONOMIST_RSS_URL is not set in economist.local.conf" >&2
        exit 1
    fi
}

hc_ping() {
    local suffix="${1:-}" body="${2:-}" url

    [[ -n "${HEALTHCHECK_URL:-}" ]] || return 0

    url="${HEALTHCHECK_URL}${suffix}"
    if [[ -n "${body}" ]]; then
        /usr/bin/curl -fsS -m 10 --retry 5 --retry-delay 5 --data-raw "${body}" \
            -o /dev/null "${url}" 2>/dev/null || true
    else
        /usr/bin/curl -fsS -m 10 --retry 5 --retry-delay 5 \
            -o /dev/null "${url}" 2>/dev/null || true
    fi
}

economist_chown_if_set() {
    [[ -n "${ECONOMIST_FILE_OWNER:-}" ]] || return 0
    chown -R "${ECONOMIST_FILE_OWNER}" "$@"
}

: "${ECONOMIST_SUMMARY_PRINTED:=0}"
: "${ECONOMIST_STOPPED_BY_USER:=no}"
: "${ECONOMIST_CLEANUP_DONE:=0}"
: "${ECONOMIST_RUN_MODE:=step}"
: "${ECONOMIST_SCRIPT_START_TIME:=}"
: "${ECONOMIST_SCRIPT_START_EPOCH:=0}"
: "${ECONOMIST_SCRIPT_FINISH_TIME:=}"
: "${ECONOMIST_SCRIPT_FINISH_EPOCH:=0}"
: "${ECONOMIST_SCRIPT_NAME:=}"
: "${ECONOMIST_RUN_STEP:=init}"
: "${ECONOMIST_RUN_EXIT_CODE:=0}"

economist_restore_screen_title() {
    if [[ -n "${STY:-}" ]]; then
        echo -ne "${tcScrTitleStart}${CALLER_SCRIPT_BASENAME:-$(basename "${BASH_SOURCE[1]}")}${tcScrTitleEnd}"
    fi
}

economist_acquire_run_lock() {
    local lock_file="${ECONOMIST_LOCK_FILE:-/var/lock/economist-runme.lock}"
    local lock_dir=""

    [[ -z "${ECONOMIST_PIPELINE_PARENT:-}" ]] || return 0
    [[ -n "${ECONOMIST_SKIP_RUN_LOCK:-}" ]] && return 0

    lock_dir="$(dirname "${lock_file}")"
    mkdir -p "${lock_dir}" 2>/dev/null || true

    if ! command -v flock >/dev/null 2>&1; then
        echo "WARNING: flock is not installed — overlapping runs are possible." >&2
        echo "Install util-linux, or set ECONOMIST_SKIP_RUN_LOCK=1 in economist.local.conf." >&2
        return 0
    fi

    exec {ECONOMIST_LOCK_FD}>>"${lock_file}"
    if ! flock -n "${ECONOMIST_LOCK_FD}"; then
        echo "Another economist instance is already running — exiting."
        echo "Lock file: ${lock_file}"
        exit 0
    fi
}

economist_run_control_init() {
    local mode="${1:-step}"

    ECONOMIST_RUN_MODE="${mode}"
    ECONOMIST_SCRIPT_NAME="$(basename "${BASH_SOURCE[1]}")"
    ECONOMIST_SCRIPT_START_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
    ECONOMIST_SCRIPT_START_EPOCH="$(date +%s)"
    ECONOMIST_SCRIPT_FINISH_TIME=""
    ECONOMIST_SCRIPT_FINISH_EPOCH=0
    ECONOMIST_RUN_STEP=init
    ECONOMIST_RUN_EXIT_CODE=0
}

economist_summary_line() {
    printf '%-27s%s\n' "$1" "$2"
}

economist_format_runtime() {
    local elapsed="$1" hours minutes seconds

    (( elapsed < 0 )) && elapsed=0
    hours=$((elapsed / 3600))
    minutes=$(((elapsed % 3600) / 60))
    seconds=$((elapsed % 60))

    if (( hours > 0 )); then
        printf '%dh %dm %ds' "${hours}" "${minutes}" "${seconds}"
    elif (( minutes > 0 )); then
        printf '%dm %ds' "${minutes}" "${seconds}"
    else
        printf '%ds' "${seconds}"
    fi
}

economist_summary_result() {
    if [[ "${ECONOMIST_STOPPED_BY_USER}" == yes ]]; then
        echo "interrupted (Ctrl-C)"
    elif (( ECONOMIST_RUN_EXIT_CODE == 0 )); then
        echo "success"
    else
        echo "failed (exit ${ECONOMIST_RUN_EXIT_CODE})"
    fi
}

economist_mark_finish_time() {
    ECONOMIST_SCRIPT_FINISH_EPOCH="$(date +%s)"
    ECONOMIST_SCRIPT_FINISH_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
}

economist_set_run_step() {
    ECONOMIST_RUN_STEP="$1"
}

economist_cleanup_work_dir() {
    local work_dir="$1"
    local remove_edition_subdirs="${2:-1}"

    [[ -n "${work_dir}" && -d "${work_dir}" ]] || return 0

    echo "Cleaning work directory: ${work_dir}"

    rm -f "${work_dir}/economist.rss" "${work_dir}/economist.mp3" "${work_dir}/chapters.txt" \
        "${work_dir}/_org_file.rar" 2>/dev/null || true
    rm -f "${work_dir}"/artwork_*.jpg "${work_dir}"/tmp_*.mp3 "${work_dir}"/*_tmp.mp3 2>/dev/null || true

    if (( remove_edition_subdirs )); then
        local d
        shopt -s nullglob
        for d in "${work_dir}"/*_TheEconomist; do
            if [[ -d "${d}" ]]; then
                echo "  removing: ${d}"
                rm -rf "${d}"
            fi
        done
        shopt -u nullglob
    fi

    rm -f "${work_dir}"/*.mp3 2>/dev/null || true
}

economist_cleanup_empty_output_placeholder() {
    local output_dir="$1" edition_name="$2" target=""

    [[ -n "${output_dir}" && -n "${edition_name}" ]] || return 0
    target="${output_dir}/${edition_name}"
    [[ -d "${target}" ]] || return 0
    [[ -z "$(ls -A "${target}" 2>/dev/null)" ]] || return 0

    rmdir --ignore-fail-on-non-empty "${target}" 2>/dev/null || true
}

economist_cleanup_step_artifacts() {
    local work_dir="${ECONOMIST_WORK_DIR:-}"

    case "${ECONOMIST_RUN_STEP}" in
        download|init)
            economist_cleanup_work_dir "${work_dir}" 0
            ;;
        process)
            economist_cleanup_work_dir "${work_dir}" 1
            ;;
        speedup)
            find "${work_dir}" -type f \( -name '*_tmp.mp3' -o -name '*_SPEECHNORM_SPEEDUP_*' \) \
                -delete 2>/dev/null || true
            ;;
        move)
            :
            ;;
    esac
}

economist_cleanup_pipeline_artifacts() {
    local work_dir="$1"
    local _edition_dir="$2"
    local output_dir="$3"
    local edition_name="$4"

    (( ECONOMIST_CLEANUP_DONE )) && return 0
    ECONOMIST_CLEANUP_DONE=1

    echo
    echo "Rolling back incomplete pipeline artifacts..."
    economist_cleanup_work_dir "${work_dir}" 1
    economist_cleanup_empty_output_placeholder "${output_dir}" "${edition_name}"
    echo
}

economist_print_summary() {
    (( ECONOMIST_SUMMARY_PRINTED )) && return 0
    ECONOMIST_SUMMARY_PRINTED=1

    local runtime runtime_text result

    if [[ -z "${ECONOMIST_SCRIPT_FINISH_TIME}" ]]; then
        economist_mark_finish_time
    elif (( ECONOMIST_SCRIPT_FINISH_EPOCH == 0 )); then
        ECONOMIST_SCRIPT_FINISH_EPOCH="$(date +%s)"
    fi

    runtime=$((ECONOMIST_SCRIPT_FINISH_EPOCH - ECONOMIST_SCRIPT_START_EPOCH))
    runtime_text="$(economist_format_runtime "${runtime}")"
    result="$(economist_summary_result)"

    echo
    echo "========= SUMMARY ========="
    economist_summary_line "Script:" "${ECONOMIST_SCRIPT_NAME:-unknown}"
    economist_summary_line "Script start time:" "${ECONOMIST_SCRIPT_START_TIME}"
    economist_summary_line "Script finish time:" "${ECONOMIST_SCRIPT_FINISH_TIME}"
    economist_summary_line "Runtime:" "${runtime_text} (${runtime}s)"
    economist_summary_line "Result:" "${result}"
    economist_summary_line "Stopped by user:" "${ECONOMIST_STOPPED_BY_USER}"
    economist_summary_line "Exit code:" "${ECONOMIST_RUN_EXIT_CODE}"

    if [[ "${ECONOMIST_RUN_MODE}" == pipeline ]]; then
        economist_summary_line "Mode:" "full pipeline"
        economist_summary_line "Edition URL:" "${ECONOMIST_PIPELINE_EDITION_URL:-}"
        economist_summary_line "Edition directory:" "${ECONOMIST_PIPELINE_EDITION_DIR:-}"
        economist_summary_line "Work directory:" "${ECONOMIST_PIPELINE_WORK_DIR:-}"
        economist_summary_line "Output directory:" "${ECONOMIST_PIPELINE_OUTPUT_DIR:-}"
        economist_summary_line "Pipeline step reached:" "${ECONOMIST_RUN_STEP}"
        economist_summary_line "Download exit code:" "${ECONOMIST_PIPELINE_RC_DOWNLOAD:-}"
        economist_summary_line "Process exit code:" "${ECONOMIST_PIPELINE_RC_PROCESS:-}"
        economist_summary_line "Speedup exit code:" "${ECONOMIST_PIPELINE_RC_SPEEDUP:-}"
        economist_summary_line "Move exit code:" "${ECONOMIST_PIPELINE_RC_MOVE:-}"
        if (( ECONOMIST_CLEANUP_DONE )); then
            economist_summary_line "Cleanup performed:" "yes"
        else
            economist_summary_line "Cleanup performed:" "no"
        fi
    else
        economist_summary_line "Mode:" "pipeline step"
        economist_summary_line "Step:" "${ECONOMIST_RUN_STEP}"
        economist_summary_line "Work directory:" "${ECONOMIST_WORK_DIR:-}"
        if [[ -n "${ECONOMIST_OUTPUT_DIR:-}" ]]; then
            economist_summary_line "Output directory:" "${ECONOMIST_OUTPUT_DIR}"
        fi
        if (( ECONOMIST_CLEANUP_DONE )); then
            economist_summary_line "Cleanup performed:" "yes"
        else
            economist_summary_line "Cleanup performed:" "no"
        fi
    fi

    echo "==========================="
    echo
}

economist_on_interrupt() {
    trap '' INT
    echo
    printf '%s\n' "** Trapped CTRL-C - cleaning up...."
    echo
    economist_restore_screen_title

    ECONOMIST_STOPPED_BY_USER=yes
    ECONOMIST_RUN_EXIT_CODE=130

    if [[ -n "${ECONOMIST_PIPELINE_PARENT:-}" ]]; then
        economist_cleanup_step_artifacts || true
        exit 130
    fi

    if [[ "${ECONOMIST_RUN_MODE}" == pipeline ]]; then
        economist_cleanup_pipeline_artifacts \
            "${ECONOMIST_PIPELINE_WORK_DIR:-}" \
            "${ECONOMIST_PIPELINE_EDITION_DIR:-}" \
            "${ECONOMIST_PIPELINE_OUTPUT_DIR:-}" \
            "${ECONOMIST_PIPELINE_EDITION_NAME:-}" || true
    else
        economist_cleanup_step_artifacts || true
        ECONOMIST_CLEANUP_DONE=1
    fi

    if [[ "${ECONOMIST_RUN_MODE}" == pipeline ]] && declare -F hc_ping >/dev/null 2>&1; then
        hc_ping "/fail" "Interrupted by user (Ctrl-C)." || true
    fi

    economist_mark_finish_time
    economist_print_summary || true
    exit 130
}

economist_install_run_traps() {
    economist_acquire_run_lock
    trap economist_on_interrupt INT
}

economist_step_exit() {
    local exit_code="${1:-0}"

    if [[ -n "${ECONOMIST_PIPELINE_PARENT:-}" ]]; then
        exit "${exit_code}"
    fi
    economist_finish_run "${exit_code}"
}

economist_finish_run() {
    local exit_code="${1:-0}"

    if [[ "${ECONOMIST_STOPPED_BY_USER}" == yes ]]; then
        exit_code=130
    fi

    ECONOMIST_RUN_EXIT_CODE="${exit_code}"
    economist_mark_finish_time
    economist_print_summary || true
    exit "${exit_code}"
}
