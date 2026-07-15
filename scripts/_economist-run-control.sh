# shellcheck shell=bash
# 2026.07.15 - v. 1.3 - dot _script_header.sh at caller top level (fixes banner/version)
# 2026.07.15 - v. 1.2 - source github-bin _script_header.sh directly (no wrapper)
# 2026.07.15 - v. 1.1 - child scripts skip summary when ECONOMIST_PIPELINE_PARENT is set
# 2026.07.15 - v. 1.0 - Ctrl-C cleanup, rollback helpers, and run summary for economist scripts
# _economist-run-control.sh
#
# economist_find_script_header_file — locate github-bin _script_header.sh
# Dot it from the calling script at top level (not inside a function), e.g.:
#   . "$(economist_find_script_header_file)" "${HEADER_EXTRA_ARGS[@]}"

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

: "${ECONOMIST_SUMMARY_PRINTED:=0}"
: "${ECONOMIST_STOPPED_BY_USER:=no}"
: "${ECONOMIST_CLEANUP_DONE:=0}"
: "${ECONOMIST_RUN_MODE:=step}"
: "${ECONOMIST_SCRIPT_START_TIME:=}"
: "${ECONOMIST_SCRIPT_FINISH_TIME:=}"
: "${ECONOMIST_RUN_STEP:=init}"
: "${ECONOMIST_RUN_EXIT_CODE:=0}"

economist_restore_screen_title() {
    if [[ -n "${STY:-}" ]]; then
        echo -ne "${tcScrTitleStart}${CALLER_SCRIPT_BASENAME:-$(basename "${BASH_SOURCE[1]}")}${tcScrTitleEnd}"
    fi
}

economist_run_control_init() {
    local mode="${1:-step}"

    ECONOMIST_RUN_MODE="${mode}"
    ECONOMIST_SCRIPT_START_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
    ECONOMIST_RUN_STEP=init
    ECONOMIST_RUN_EXIT_CODE=0
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

economist_cleanup_edition_placeholder() {
    local edition_dir="$1"

    [[ -n "${edition_dir}" && -d "${edition_dir}" ]] || return 0

    if [[ -z "$(ls -A "${edition_dir}" 2>/dev/null)" ]]; then
        echo "Removing empty edition directory: ${edition_dir}"
        rmdir --ignore-fail-on-non-empty "${edition_dir}" 2>/dev/null || true
    else
        echo "Leaving edition directory for manual review: ${edition_dir}" >&2
    fi
}

economist_cleanup_output_edition_dir() {
    local output_dir="$1"
    local edition_name="$2"

    local target=""
    [[ -n "${output_dir}" && -n "${edition_name}" ]] || return 0
    target="${output_dir}/${edition_name}"

    [[ -d "${target}" ]] || return 0

    echo "Removing incomplete output edition folder: ${target}"
    rm -rf "${target}"
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
    local edition_dir="$2"
    local output_dir="$3"
    local edition_name="$4"

    (( ECONOMIST_CLEANUP_DONE )) && return 0
    ECONOMIST_CLEANUP_DONE=1

    echo
    echo "Rolling back incomplete pipeline artifacts..."
    economist_cleanup_work_dir "${work_dir}" 1
    economist_cleanup_edition_placeholder "${edition_dir}"
    if [[ -n "${edition_name}" ]]; then
        economist_cleanup_output_edition_dir "${output_dir}" "${edition_name}"
    fi
    echo
}

economist_print_summary() {
    (( ECONOMIST_SUMMARY_PRINTED )) && return 0
    ECONOMIST_SUMMARY_PRINTED=1
    ECONOMIST_SCRIPT_FINISH_TIME="${ECONOMIST_SCRIPT_FINISH_TIME:-$(date '+%Y-%m-%d %H:%M:%S')}"

    local script_name
    script_name="$(basename "${BASH_SOURCE[1]}")"

    echo
    echo "========= SUMMARY ========="
    echo "Script:                ${script_name}"
    echo "Script start time:     ${ECONOMIST_SCRIPT_START_TIME}"
    echo "Script finish time:    ${ECONOMIST_SCRIPT_FINISH_TIME}"
    echo "Stopped by user:       ${ECONOMIST_STOPPED_BY_USER}"
    echo "Exit code:             ${ECONOMIST_RUN_EXIT_CODE}"

    if [[ "${ECONOMIST_RUN_MODE}" == pipeline ]]; then
        echo "Mode:                  full pipeline"
        echo "Edition URL:           ${ECONOMIST_PIPELINE_EDITION_URL:-}"
        echo "Edition directory:     ${ECONOMIST_PIPELINE_EDITION_DIR:-}"
        echo "Work directory:        ${ECONOMIST_PIPELINE_WORK_DIR:-}"
        echo "Output directory:      ${ECONOMIST_PIPELINE_OUTPUT_DIR:-}"
        echo "Pipeline step reached: ${ECONOMIST_RUN_STEP}"
        echo "Download exit code:    ${ECONOMIST_PIPELINE_RC_DOWNLOAD:-}"
        echo "Process exit code:     ${ECONOMIST_PIPELINE_RC_PROCESS:-}"
        echo "Speedup exit code:     ${ECONOMIST_PIPELINE_RC_SPEEDUP:-}"
        echo "Move exit code:        ${ECONOMIST_PIPELINE_RC_MOVE:-}"
        if (( ECONOMIST_CLEANUP_DONE )); then
            echo "Cleanup performed:     yes"
        else
            echo "Cleanup performed:     no"
        fi
    else
        echo "Mode:                  pipeline step"
        echo "Step:                  ${ECONOMIST_RUN_STEP}"
        echo "Work directory:        ${ECONOMIST_WORK_DIR:-}"
        if [[ -n "${ECONOMIST_OUTPUT_DIR:-}" ]]; then
            echo "Output directory:      ${ECONOMIST_OUTPUT_DIR}"
        fi
        if (( ECONOMIST_CLEANUP_DONE )); then
            echo "Cleanup performed:     yes"
        else
            echo "Cleanup performed:     no"
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

    economist_print_summary || true
    exit 130
}

economist_install_run_traps() {
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
    ECONOMIST_SCRIPT_FINISH_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
    economist_print_summary || true
    exit "${exit_code}"
}
