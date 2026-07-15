# shellcheck shell=bash
# 2026.07.16 - v. 2.20 - summary on show-available quit; result label for no selection
# 2026.07.16 - v. 2.19 - confirm prompt reads one character like install.sh
# 2026.07.16 - v. 2.18 - fix pick loop for bash without labeled continue
# 2026.07.16 - v. 2.17 - show-available: confirm pick; N relists; force reprocess
# 2026.07.16 - v. 2.15 - show-available list: oldest first, newest at bottom
# 2026.07.16 - v. 2.14 - show-available pick: single-line prompt ending with ": "
# 2026.07.16 - v. 2.13 - show-available pick: accept leading zeros (e.g. 000010 → 10)
# 2026.07.15 - v. 2.12 - Issue column shows Economist issue number (e.g. 9419)
# 2026.07.15 - v. 2.11 - show-available pick prompt: Enter/Q=quit default; number=download
# 2026.07.15 - v. 2.10 - show-available table: Issue column (RSS feed position)
# 2026.07.15 - v. 2.9 - show-available: progress dots; Enter defaults to quit
# 2026.07.15 - v. 2.8 - RSS list/verify helpers; interactive --show-available picker
# 2026.07.15 - v. 2.7 - pipeline step exit codes: N/A when stage not reached
# 2026.07.15 - v. 2.6 - summary: edition dir file count; cron archive from/to paths
# 2026.07.15 - v. 2.5 - cleanup_empty_dirs step label in summary
# 2026.07.15 - v. 2.4 - ECONOMIST_ARCHIVE_DIR default; archive step label in summary
# 2026.07.15 - v. 2.3 - clearer pipeline summary labels and step exit codes
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
    : "${ECONOMIST_ARCHIVE_DIR:=${ECONOMIST_BASE_DIR}/archive}"
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

economist_latest_saturday_iso() {
    local dow_now off_now

    dow_now=$(date +%u)
    off_now=$(( (dow_now + 1) % 7 ))
    date -d "today - ${off_now} days" +%F
}

economist_edition_date_for_rss_position() {
    local pos="${1:-1}" latest_sat

    [[ "${pos}" =~ ^[0-9]+$ ]] || return 1
    (( pos >= 1 )) || return 1

    latest_sat="$(economist_latest_saturday_iso)"
    date -d "${latest_sat} - $((pos - 1)) weeks" +%F
}

economist_edition_output_dir_for_date() {
    local iso="$1" y m d

    [[ "${iso}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
    IFS='-' read -r y m d <<< "${iso}"
    echo "${ECONOMIST_OUTPUT_DIR}/${y}.${m}.${d}_TheEconomist"
}

economist_issue_number_for_edition_date() {
    local iso="$1" year="" base_issue=9226 edition_epoch initial_epoch issue_num=""

    [[ "${iso}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
    year="${iso%%-*}"

    edition_epoch=$(date -d "${iso}" +%s)
    initial_epoch=$(date -d "2021-01-02" +%s)

    # Summer double issues: one week is skipped in the official numbering.
    if (( edition_epoch > $(date -d "2022-08-12" +%s) )); then
        (( base_issue-- ))
    fi
    if (( edition_epoch > $(date -d "2023-08-11" +%s) )); then
        (( base_issue-- ))
    fi

    issue_num=$(awk -v bi="${base_issue}" -v y="${year}" -v de="${edition_epoch}" -v ie="${initial_epoch}" \
        'BEGIN { printf "%.0f", bi - (y - 2021) + (de - ie) / 86400 / 7 }')
    [[ "${issue_num}" =~ ^[0-9]+$ ]] || return 1
    echo "${issue_num}"
}

economist_rss_fetch_to() {
    local dest="$1"

    curl -fsSL "${ECONOMIST_RSS_URL}" -o "${dest}"
}

economist_rss_item_count() {
    local rss_file="$1" item_count=0 item_count_raw

    if command -v xmllint >/dev/null 2>&1; then
        item_count_raw="$(xmllint --xpath 'count(//item)' "${rss_file}" 2>/dev/null || echo 0)"
        item_count="${item_count_raw%.*}"
    fi

    if [[ "${item_count}" -eq 0 ]]; then
        item_count="$(grep -oP '<enclosure url="\K[^"]+' "${rss_file}" | wc -l | tr -d '[:space:]')"
    fi

    echo "${item_count:-0}"
}

economist_rss_enclosure_url_at() {
    local rss_file="$1" pos="$2" url="" item_count

    item_count="$(economist_rss_item_count "${rss_file}")"
    if [[ "${pos}" -le 0 || "${pos}" -gt "${item_count}" ]]; then
        return 1
    fi

    if command -v xmllint >/dev/null 2>&1 && [[ "${item_count}" -gt 0 ]]; then
        url="$(xmllint --xpath "string((//item)[${pos}]/enclosure/@url)" "${rss_file}" 2>/dev/null || true)"
    fi

    if [[ -z "${url}" ]]; then
        url="$(grep -oP '<enclosure url="\K[^"]+' "${rss_file}" | sed -n "${pos}p" || true)"
    fi

    [[ -n "${url}" ]] || return 1
    echo "${url}"
}

economist_rss_item_title_at() {
    local rss_file="$1" pos="$2" title=""

    if command -v xmllint >/dev/null 2>&1; then
        title="$(xmllint --xpath "string((//item)[${pos}]/title)" "${rss_file}" 2>/dev/null || true)"
    fi

    if [[ -z "${title}" ]]; then
        title="$(grep -oP '<title>\K[^<]+' "${rss_file}" | sed -n "$((pos + 1))p" || true)"
    fi

    title="${title//$'\n'/ }"
    title="${title//$'\r'/}"
    echo "${title:-—}"
}

economist_verify_enclosure_on_server() {
    local url="$1" code=""

    if ! command -v curl >/dev/null 2>&1; then
        echo "curl is required to verify MP3 URLs on the server." >&2
        return 1
    fi

    code="$(curl -fsSIL -o /dev/null -w '%{http_code}' --max-time 25 --retry 1 "${url}" 2>/dev/null || echo 000)"
    if [[ "${code}" == "200" || "${code}" == "206" ]]; then
        return 0
    fi

    code="$(curl -fsSL -o /dev/null -w '%{http_code}' --max-time 25 --range 0-511 --retry 1 "${url}" 2>/dev/null || echo 000)"
    [[ "${code}" == "200" || "${code}" == "206" ]]
}

economist_local_edition_status() {
    local edition_dir="$1"

    if [[ -d "${edition_dir}" ]] && [[ -n "$(ls -A "${edition_dir}" 2>/dev/null)" ]]; then
        echo "already processed"
    elif [[ -d "${edition_dir}" ]]; then
        echo "output dir empty"
    else
        echo "not downloaded"
    fi
}

economist_read_tty_line() {
    local prompt="$1"
    local -n _line_ref="$2"

    if [[ -r /dev/tty ]]; then
        read -r -p "${prompt}" _line_ref </dev/tty
    else
        read -r -p "${prompt}" _line_ref
    fi
}

economist_read_tty_char() {
    local prompt="$1"
    local -n _char_ref="$2"
    local timeout="${3:-300}"

    _char_ref=""
    echo -n "${prompt}"
    if [[ -r /dev/tty ]]; then
        read -t "${timeout}" -n 1 _char_ref </dev/tty || _char_ref=""
    else
        read -t "${timeout}" -n 1 _char_ref || _char_ref=""
    fi
    echo
    _char_ref="${_char_ref//$'\r'/}"
}

economist_force_reprocess_edition() {
    local edition_dir="$1" work_dir="$2"

    [[ -n "${edition_dir}" && -d "${edition_dir}" ]] && rm -rf "${edition_dir}"
    economist_cleanup_work_dir "${work_dir}" 1
}

economist_show_and_pick_available_editions() {
    local -n _picked_iso_ref="$1"
    local -n _force_reprocess_ref="$2"
    local rss_file="" item_count=0 pos=0 edition_iso="" title="" url="" local_status=""
    local edition_dir="" choice="" idx=0 dots_pid=0 verified_count=0 sel_idx=0
    local issue_no="" confirm="" confirm_prompt=""
    local -a pick_isos=()
    local -a pick_titles=()
    local -a pick_local=()
    local -a pick_issues=()

    _picked_iso_ref=""
    _force_reprocess_ref=0

    rss_file="$(mktemp)"
    trap 'rm -f "${rss_file}"' RETURN

    printf 'Fetching RSS feed' >&2
    (
        while true; do
            printf '.' >&2
            sleep 0.4
        done
    ) &
    dots_pid=$!

    if ! economist_rss_fetch_to "${rss_file}"; then
        kill "${dots_pid}" 2>/dev/null || true
        wait "${dots_pid}" 2>/dev/null || true
        printf ' failed.\n' >&2
        echo "Failed to fetch RSS: ${ECONOMIST_RSS_URL}" >&2
        return 1
    fi

    kill "${dots_pid}" 2>/dev/null || true
    wait "${dots_pid}" 2>/dev/null || true

    item_count="$(economist_rss_item_count "${rss_file}")"
    if [[ "${item_count}" -eq 0 ]]; then
        printf ' done (no items).\n' >&2
        echo "No items found in RSS feed." >&2
        return 1
    fi

    printf ' ok (%s item(s)).\n' "${item_count}" >&2
    printf 'Checking %s feed item(s) on server' "${item_count}" >&2

    for (( pos = 1; pos <= item_count; ++pos )); do
        printf '.' >&2
        url="$(economist_rss_enclosure_url_at "${rss_file}" "${pos}" 2>/dev/null || true)"
        [[ -n "${url}" ]] || continue
        if ! economist_verify_enclosure_on_server "${url}"; then
            continue
        fi

        edition_iso="$(economist_edition_date_for_rss_position "${pos}")" || continue
        title="$(economist_rss_item_title_at "${rss_file}" "${pos}")"
        edition_dir="$(economist_edition_output_dir_for_date "${edition_iso}")"
        local_status="$(economist_local_edition_status "${edition_dir}")"
        issue_no="$(economist_issue_number_for_edition_date "${edition_iso}" 2>/dev/null || echo "—")"

        pick_isos+=("${edition_iso}")
        pick_titles+=("${title}")
        pick_local+=("${local_status}")
        pick_issues+=("${issue_no}")
        (( ++verified_count )) || true
    done

    printf ' %s verified.\n' "${verified_count}" >&2

    if [[ ${#pick_isos[@]} -eq 0 ]]; then
        echo "No editions verified as downloadable on the server." >&2
        return 1
    fi

    if [[ ${#pick_isos[@]} -gt 1 ]]; then
        local -a _rev_isos=() _rev_titles=() _rev_local=() _rev_issues=()
        for (( idx = ${#pick_isos[@]} - 1; idx >= 0; --idx )); do
            _rev_isos+=("${pick_isos[idx]}")
            _rev_titles+=("${pick_titles[idx]}")
            _rev_local+=("${pick_local[idx]}")
            _rev_issues+=("${pick_issues[idx]}")
        done
        pick_isos=("${_rev_isos[@]}")
        pick_titles=("${_rev_titles[@]}")
        pick_local=("${_rev_local[@]}")
        pick_issues=("${_rev_issues[@]}")
    fi

    if [[ ! -t 0 && ! -r /dev/tty ]]; then
        echo
        echo "Verified editions (oldest at top, newest at bottom):"
        printf '  %-3s %-12s %-36s %-18s %s\n' "#" "Edition" "Title" "Local" "Issue"
        printf '  %-3s %-12s %-36s %-18s %s\n' "---" "--------" "-----" "-----" "-----"
        for (( idx = 0; idx < ${#pick_isos[@]}; ++idx )); do
            printf '  %-3s %-12s %-36s %-18s %s\n' \
                "$((idx + 1))" \
                "${pick_isos[idx]}" \
                "${pick_titles[idx]:0:36}" \
                "${pick_local[idx]:0:18}" \
                "${pick_issues[idx]}"
        done
        echo
        echo "Non-interactive session — listing only (no pick)."
        return 0
    fi

    while true; do
        echo
        echo "Verified editions (oldest at top, newest at bottom):"
        printf '  %-3s %-12s %-36s %-18s %s\n' "#" "Edition" "Title" "Local" "Issue"
        printf '  %-3s %-12s %-36s %-18s %s\n' "---" "--------" "-----" "-----" "-----"
        for (( idx = 0; idx < ${#pick_isos[@]}; ++idx )); do
            printf '  %-3s %-12s %-36s %-18s %s\n' \
                "$((idx + 1))" \
                "${pick_isos[idx]}" \
                "${pick_titles[idx]:0:36}" \
                "${pick_local[idx]:0:18}" \
                "${pick_issues[idx]}"
        done
        echo

        while true; do
            economist_read_tty_line "To download: enter 1–${#pick_isos[@]} and press Enter, or Enter/Q to quit: " choice

            case "${choice}" in
                q|Q|'')
                    return 0
                    ;;
                *[!0-9]*)
                    echo "Invalid input — enter 1–${#pick_isos[@]} to download, or press Enter to quit."
                    ;;
                *)
                    choice=$((10#${choice}))
                    if (( choice >= 1 && choice <= ${#pick_isos[@]} )); then
                        sel_idx=$((choice - 1))
                        break
                    fi
                    echo "Invalid input — enter 1–${#pick_isos[@]} to download, or press Enter to quit."
                    ;;
            esac
        done

        echo
        printf '  %-12s %s\n' "Edition:" "${pick_isos[sel_idx]}"
        printf '  %-12s %s\n' "Title:" "${pick_titles[sel_idx]}"
        printf '  %-12s %s\n' "Issue:" "${pick_issues[sel_idx]}"
        printf '  %-12s %s\n' "Local:" "${pick_local[sel_idx]}"
        echo

        if [[ "${pick_local[sel_idx]}" == "already processed" ]]; then
            confirm_prompt="Reprocess this edition? [Y/n/q]: "
        else
            confirm_prompt="Download this edition? [Y/n/q]: "
        fi

        while true; do
            economist_read_tty_char "${confirm_prompt}" confirm

            case "${confirm}" in
                q|Q)
                    return 0
                    ;;
                n|N)
                    break
                    ;;
                ''|y|Y)
                    _picked_iso_ref="${pick_isos[sel_idx]}"
                    if [[ "${pick_local[sel_idx]}" == "already processed" ]]; then
                        _force_reprocess_ref=1
                    else
                        _force_reprocess_ref=0
                    fi
                    return 0
                    ;;
                *)
                    echo "Enter Y to confirm, N to show the list again, or Q to quit."
                    ;;
            esac
        done
    done
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

economist_format_step_name() {
    local step="${1:-}"

    case "${step}" in
        init) echo "not started" ;;
        download) echo "1 — download" ;;
        process) echo "2 — process edition" ;;
        speedup) echo "3 — speedup & loudness" ;;
        move) echo "4 — move results" ;;
        archive) echo "archive editions" ;;
        cleanup_empty_dirs) echo "cleanup empty output dirs" ;;
        complete) echo "all steps completed" ;;
        already_exists) echo "skipped (edition already exists)" ;;
        show_available) echo "show available editions" ;;
        show_available_quit) echo "quit (no edition selected)" ;;
        "") echo "unknown" ;;
        *) echo "${step}" ;;
    esac
}

economist_summary_step_rc() {
    local rc="${1:-}"

    if [[ -z "${rc}" ]]; then
        echo "N/A (this stage not reached)"
    else
        echo "${rc}"
    fi
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
    elif [[ "${ECONOMIST_RUN_STEP}" == "show_available_quit" ]]; then
        echo "quit (no edition selected)"
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

economist_count_files_in_dir() {
    local dir="$1" count

    [[ -d "${dir}" ]] || {
        echo "0"
        return 0
    }

    count="$(find "${dir}" -type f 2>/dev/null | wc -l | tr -d '[:space:]')"
    echo "${count:-0}"
}

economist_summary_edition_paths() {
    local edition_dir="${1:-}" edition_name="${2:-}" archive_dir="${3:-}"
    local file_count archive_target

    [[ -n "${edition_dir}" ]] || return 0

    if [[ -d "${edition_dir}" ]]; then
        file_count="$(economist_count_files_in_dir "${edition_dir}")"
        economist_summary_line "Edition directory:" "${edition_dir} (${file_count} files)"
    else
        economist_summary_line "Edition directory:" "${edition_dir}"
        return 0
    fi

    edition_name="${edition_name:-$(basename "${edition_dir}")}"
    archive_dir="${archive_dir:-${ECONOMIST_ARCHIVE_DIR:-}}"
    [[ -n "${archive_dir}" && -n "${edition_name}" ]] || return 0

    archive_target="${archive_dir}/${edition_name}"
    economist_summary_line "Cron archive:" "Thursday 02:00 — economist-archive-editions.sh"
    printf 'From: %s\n' "${edition_dir}"
    printf 'To:   %s\n' "${archive_target}"
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
        if [[ "${ECONOMIST_RUN_STEP}" == "show_available_quit" ]]; then
            economist_summary_line "Run:" "show-available (no edition selected)"
        else
            economist_summary_line "Run:" "all steps (download → move)"
        fi
        economist_summary_line "Edition URL:" "${ECONOMIST_PIPELINE_EDITION_URL:-}"
        economist_summary_edition_paths \
            "${ECONOMIST_PIPELINE_EDITION_DIR:-}" \
            "${ECONOMIST_PIPELINE_EDITION_NAME:-}" \
            "${ECONOMIST_ARCHIVE_DIR:-}"
        economist_summary_line "Work directory:" "${ECONOMIST_PIPELINE_WORK_DIR:-}"
        economist_summary_line "Output directory:" "${ECONOMIST_PIPELINE_OUTPUT_DIR:-}"
        economist_summary_line "Last step:" "$(economist_format_step_name "${ECONOMIST_RUN_STEP}")"
        economist_summary_line "Download exit code:" "$(economist_summary_step_rc "${ECONOMIST_PIPELINE_RC_DOWNLOAD:-}")"
        economist_summary_line "Process exit code:" "$(economist_summary_step_rc "${ECONOMIST_PIPELINE_RC_PROCESS:-}")"
        economist_summary_line "Speedup exit code:" "$(economist_summary_step_rc "${ECONOMIST_PIPELINE_RC_SPEEDUP:-}")"
        economist_summary_line "Move exit code:" "$(economist_summary_step_rc "${ECONOMIST_PIPELINE_RC_MOVE:-}")"
        if (( ECONOMIST_CLEANUP_DONE )); then
            economist_summary_line "Cleanup performed:" "yes"
        else
            economist_summary_line "Cleanup performed:" "no"
        fi
    else
        economist_summary_line "Step:" "$(economist_format_step_name "${ECONOMIST_RUN_STEP}")"
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
