# shellcheck shell=bash
# v. 20260717.124001 - offer nearby edition list when user explicitly declines nearest
# v. 20260717.123201 - punctuation on edition-not-found status line
# v. 20260717.123001 - status messages while fetching/checking RSS
# v. 20260717.122601 - clearer website-vs-RSS explanation when no new edition
# v. 20260717.120501 - CLI date: config + pick-style confirm before pipeline start
# v. 20260717.120401 - fix rss temp cleanup under set -u (no local in RETURN trap)
# v. 20260717.120301 - accept YYYY.MM.DD edition date on command line
# v. 20260717.090001 - normalize edition date; nearest RSS fallback; force hint
# v. 20260717.083901 - fix nameref bugs breaking edition dir / archive detection
# v. 20260717.082501 - detect processed via mp3/rar; sat_iso in pipeline skip; clean empty shells
# v. 20260716.234001 - scan archive dir; size threshold; robust dir size; match all folders
# v. 20260716.233501 - show-available: also scan ECONOMIST_WORK_DIR for edition folders
# v. 20260716.233001 - size: pick largest output dir; GB %8.2f; unified processed status
# v. 20260716.232501 - GB via printf %8.2f (always 2 decimal places)
# v. 20260716.232401 - processed = non-empty output dir found; GB with 2 decimals; match by issue
# v. 20260716.232101 - size: B/kB/MB/GB together; fix dir lookup for processed editions
# v. 20260716.231801 - show-available: Size column for processed editions (kB/MB/GB)
# v. 20260716.231501 - fix RSS title cover date parse (EDITION uppercase); status dir aliases
# v. 20260716.231401 - parse cover date from RSS title (case-insensitive); status alias dirs
# v. 20260716.230401 - show-available: blank line every 10th pick number
# v. 20260716.230001 - show-available table: right-align # and age columns
# v. 20260716.225703 - show-available: oldest at top, #1 = newest at bottom
# v. 20260716.225602 - show-available pick: Q quits immediately (no Enter)
# v. 20260716.225501 - show-available: newest is #1; add age column (y/m/d)
# v. 20260716.162602 - shared config loader, validation, RSS helpers, run summary
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

    ECONOMIST_CONFIG_FILE="${conf}"

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

economist_config_is_blank() {
    [[ -z "${1//[[:space:]]/}" ]]
}

economist_config_add_error() {
    local err_arr="$1" message="$2"

    local -n _errs="${err_arr}"
    _errs+=("${message}")
}

economist_config_require_non_blank() {
    local err_arr="$1" name="$2" value="${3:-}"

    if economist_config_is_blank "${value}"; then
        economist_config_add_error "${err_arr}" "${name} is not set or empty"
        return 1
    fi
    return 0
}

economist_config_require_abs_dir_path() {
    local err_arr="$1" name="$2" value="${3:-}" parent

    economist_config_require_non_blank "${err_arr}" "${name}" "${value}" || return 1

    if [[ "${value}" != /* ]]; then
        economist_config_add_error "${err_arr}" "${name} must be an absolute path (got: ${value})"
        return 1
    fi

    parent="$(dirname "${value}")"
    if [[ ! -d "${parent}" && ! -d "${value}" ]]; then
        economist_config_add_error "${err_arr}" "${name} parent directory does not exist: ${parent}"
        return 1
    fi
    return 0
}

economist_config_require_http_url() {
    local err_arr="$1" name="$2" value="${3:-}"

    economist_config_require_non_blank "${err_arr}" "${name}" "${value}" || return 1

    if [[ ! "${value}" =~ ^https?://[^[:space:]]+$ ]]; then
        economist_config_add_error "${err_arr}" "${name} must be an http(s) URL (got: ${value})"
        return 1
    fi
    return 0
}

economist_config_require_executable() {
    local err_arr="$1" name="$2" value="${3:-}"

    economist_config_require_non_blank "${err_arr}" "${name}" "${value}" || return 1

    if [[ ! -f "${value}" ]]; then
        economist_config_add_error "${err_arr}" "${name} file does not exist: ${value}"
        return 1
    fi

    if [[ ! -x "${value}" ]]; then
        economist_config_add_error "${err_arr}" "${name} is not executable: ${value}"
        return 1
    fi
    return 0
}

economist_config_validate_dir_writable() {
    local err_arr="$1" name="$2" dir="${3:-}" probe="" parent="" run_user

    run_user="$(id -un 2>/dev/null || echo unknown)"

    economist_config_require_abs_dir_path "${err_arr}" "${name}" "${dir}" || return 1

    if [[ -e "${dir}" ]]; then
        if [[ ! -w "${dir}" ]]; then
            economist_config_add_error "${err_arr}" \
                "${name} is not writable by ${run_user}: ${dir}"
        fi
    else
        parent="${dir}"
        while [[ ! -e "${parent}" && "${parent}" != "/" ]]; do
            parent="$(dirname "${parent}")"
        done
        if [[ -e "${parent}" && ! -w "${parent}" ]]; then
            economist_config_add_error "${err_arr}" \
                "${name} does not exist and ${parent} is not writable by ${run_user}"
        fi
    fi

    probe="${dir}/.economist-write-test-$$"
    if ! mkdir -p "${probe}" 2>/dev/null; then
        economist_config_add_error "${err_arr}" \
            "${name} — ${run_user} cannot create directories under: ${dir}"
        return 1
    fi
    if ! rmdir "${probe}" 2>/dev/null; then
        rm -rf "${probe}" 2>/dev/null || true
        economist_config_add_error "${err_arr}" \
            "${name} — ${run_user} created a test directory but cannot remove it: ${probe}"
    fi
}

economist_config_validate_ffmpeg() {
    local err_arr="$1" path="${2:-}" version_line="" rc=0 run_user

    run_user="$(id -un 2>/dev/null || echo unknown)"
    ECONOMIST_FFMPEG_VERSION=""

    economist_config_require_executable "${err_arr}" "FFMPEG_PATH" "${path}" || return 1

    version_line="$("${path}" -hide_banner -version 2>&1 | head -n1)" || rc=$?
    if (( rc != 0 )) || economist_config_is_blank "${version_line}"; then
        economist_config_add_error "${err_arr}" \
            "FFMPEG_PATH cannot be executed by ${run_user}: ${path} (exit ${rc})"
        return 1
    fi

    ECONOMIST_FFMPEG_VERSION="${version_line}"
}

economist_config_validate_file_owner() {
    local err_arr="$1" owner="${2:-}" user group run_uid

    run_uid="$(id -u 2>/dev/null || echo 0)"

    if economist_config_is_blank "${owner}"; then
        return 0
    fi

    if [[ ! "${owner}" =~ ^[A-Za-z0-9._-]+(:[A-Za-z0-9._-]+)?$ ]]; then
        economist_config_add_error "${err_arr}" \
            "ECONOMIST_FILE_OWNER must be user or user:group (got: ${owner})"
        return 1
    fi

    if [[ "${owner}" == *:* ]]; then
        user="${owner%%:*}"
        group="${owner#*:}"
        if [[ -n "${user}" ]] && ! getent passwd "${user}" >/dev/null 2>&1; then
            economist_config_add_error "${err_arr}" \
                "ECONOMIST_FILE_OWNER user does not exist: ${user}"
        fi
        if [[ -n "${group}" ]] && ! getent group "${group}" >/dev/null 2>&1; then
            economist_config_add_error "${err_arr}" \
                "ECONOMIST_FILE_OWNER group does not exist: ${group}"
        fi
    elif ! getent passwd "${owner}" >/dev/null 2>&1; then
        economist_config_add_error "${err_arr}" \
            "ECONOMIST_FILE_OWNER user does not exist: ${owner}"
    fi

    if (( run_uid != 0 )); then
        economist_config_add_error "${err_arr}" \
            "ECONOMIST_FILE_OWNER is set to ${owner} but pipeline runs as $(id -un 2>/dev/null) (uid ${run_uid}); chown requires root"
    fi
}

validate_economist_config() {
    local -a errors=()

    economist_config_require_http_url errors "ECONOMIST_RSS_URL" "${ECONOMIST_RSS_URL:-}"
    if ! economist_config_is_blank "${ECONOMIST_RSS_URL:-}" \
        && [[ ! "${ECONOMIST_RSS_URL}" =~ ^https://feeds\.economist\.com/v1/rss/weekly/[A-Za-z0-9-]+$ ]]; then
        economist_config_add_error errors \
            "ECONOMIST_RSS_URL must look like https://feeds.economist.com/v1/rss/weekly/YOUR-UUID"
    fi

    if ! economist_config_is_blank "${HEALTHCHECK_URL:-}"; then
        economist_config_require_http_url errors "HEALTHCHECK_URL" "${HEALTHCHECK_URL}"
    fi

    economist_config_validate_dir_writable errors "ECONOMIST_BASE_DIR" "${ECONOMIST_BASE_DIR:-}"
    economist_config_validate_dir_writable errors "ECONOMIST_WORK_DIR" "${ECONOMIST_WORK_DIR:-}"
    economist_config_validate_dir_writable errors "ECONOMIST_OUTPUT_DIR" "${ECONOMIST_OUTPUT_DIR:-}"
    economist_config_validate_dir_writable errors "ECONOMIST_ARCHIVE_DIR" "${ECONOMIST_ARCHIVE_DIR:-}"

    if ! economist_config_is_blank "${ECONOMIST_WORK_DIR:-}" \
        && ! economist_config_is_blank "${ECONOMIST_OUTPUT_DIR:-}" \
        && [[ "${ECONOMIST_WORK_DIR}" == "${ECONOMIST_OUTPUT_DIR}" ]]; then
        economist_config_add_error errors \
            "ECONOMIST_WORK_DIR and ECONOMIST_OUTPUT_DIR must not be the same path"
    fi

    economist_config_validate_ffmpeg errors "${FFMPEG_PATH:-}"
    economist_config_validate_file_owner errors "${ECONOMIST_FILE_OWNER:-}"

    if ! economist_config_is_blank "${CURL_IMPERSONATE:-}"; then
        economist_config_require_executable errors "CURL_IMPERSONATE" "${CURL_IMPERSONATE}"
    fi

    if ((${#errors[@]} > 0)); then
        echo "Invalid economist.local.conf:" >&2
        local err
        for err in "${errors[@]}"; do
            echo "  - ${err}" >&2
        done
        exit 1
    fi
}

economist_print_config_ok() {
    local hc_state owner_state run_user run_uid

    run_user="$(id -un 2>/dev/null || echo unknown)"
    run_uid="$(id -u 2>/dev/null || echo ?)"

    if economist_config_is_blank "${HEALTHCHECK_URL:-}"; then
        hc_state="disabled"
    else
        hc_state="${HEALTHCHECK_URL}"
    fi

    if economist_config_is_blank "${ECONOMIST_FILE_OWNER:-}"; then
        owner_state="(skip chown)"
    else
        owner_state="${ECONOMIST_FILE_OWNER}"
    fi

    echo "---------- Config ----------"
    economist_summary_line "Config file:" "${ECONOMIST_CONFIG_FILE:-economist.local.conf}"
    economist_summary_line "Running as:" "${run_user} (uid ${run_uid})"
    economist_summary_line "Work dir:" "${ECONOMIST_WORK_DIR:-} (writable, mkdir OK)"
    economist_summary_line "Output dir:" "${ECONOMIST_OUTPUT_DIR:-} (writable, mkdir OK)"
    economist_summary_line "Archive dir:" "${ECONOMIST_ARCHIVE_DIR:-} (writable, mkdir OK)"
    economist_summary_line "FFmpeg:" "${FFMPEG_PATH:-}"
    economist_summary_line "FFmpeg version:" "${ECONOMIST_FFMPEG_VERSION:-unknown}"
    economist_summary_line "File owner:" "${owner_state}"
    economist_summary_line "Healthcheck:" "${hc_state}"
    economist_summary_line "Status:" "loaded and validated OK"
    echo "----------------------------"
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

economist_edition_date_from_rss_title() {
    local title="$1" title_norm="" month="" day="" year="" iso=""

    [[ -n "${title}" && "${title}" != "—" ]] || return 1
    title_norm="${title,,}"

    if [[ "${title_norm}" =~ edition:[[:space:]]+([a-z]+)[[:space:]]+([0-9]{1,2})[a-z]*[[:space:]]+([0-9]{4}) ]]; then
        month="${BASH_REMATCH[1]}"
        day="${BASH_REMATCH[2]}"
        year="${BASH_REMATCH[3]}"
    elif [[ "${title_norm}" =~ edition:[[:space:]]+([0-9]{1,2})[a-z]*[[:space:]]+([a-z]+)[[:space:]]+([0-9]{4}) ]]; then
        day="${BASH_REMATCH[1]}"
        month="${BASH_REMATCH[2]}"
        year="${BASH_REMATCH[3]}"
    else
        return 1
    fi

    iso="$(date -d "${month} ${day} ${year}" +%F 2>/dev/null || true)"
    [[ "${iso}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
    echo "${iso}"
}

economist_edition_date_for_rss_item() {
    local rss_file="$1" pos="$2" title="" iso=""

    [[ -n "${rss_file}" && -f "${rss_file}" ]] || return 1
    [[ "${pos}" =~ ^[0-9]+$ ]] || return 1
    (( pos >= 1 )) || return 1

    title="$(economist_rss_item_title_at "${rss_file}" "${pos}")"
    if iso="$(economist_edition_date_from_rss_title "${title}")"; then
        echo "${iso}"
        return 0
    fi

    economist_edition_date_for_rss_position "${pos}"
}

economist_rss_position_for_edition_date() {
    local rss_file="$1" iso="$2" item_count=0 pos=0 edition_at_pos=""

    [[ -n "${rss_file}" && -f "${rss_file}" ]] || return 1
    [[ "${iso}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1

    item_count="$(economist_rss_item_count "${rss_file}")"
    (( item_count > 0 )) || return 1

    for (( pos = 1; pos <= item_count; ++pos )); do
        edition_at_pos="$(economist_edition_date_for_rss_item "${rss_file}" "${pos}")" || continue
        [[ "${edition_at_pos}" == "${iso}" ]] || continue
        echo "${pos}"
        return 0
    done

    return 1
}

economist_edition_dir_basename_for_date() {
    local iso="$1" y m d

    [[ "${iso}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
    IFS='-' read -r y m d <<< "${iso}"
    echo "${y}${m}${d}_TheEconomist"
}

economist_legacy_edition_dir_basename_for_date() {
    local iso="$1" y m d

    [[ "${iso}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
    IFS='-' read -r y m d <<< "${iso}"
    echo "${y}.${m}.${d}_TheEconomist"
}

economist_edition_output_dir_for_date() {
    local iso="$1" base=""

    base="$(economist_edition_dir_basename_for_date "${iso}")" || return 1
    echo "${ECONOMIST_OUTPUT_DIR}/${base}"
}

economist_edition_output_dir_for_status() {
    local iso="$1" new="" legacy=""

    new="$(economist_edition_output_dir_for_date "${iso}")" || return 1
    if [[ -d "${new}" ]] && [[ -n "$(ls -A "${new}" 2>/dev/null)" ]]; then
        echo "${new}"
        return 0
    fi

    legacy="${ECONOMIST_OUTPUT_DIR}/$(economist_legacy_edition_dir_basename_for_date "${iso}")"
    if [[ -d "${legacy}" ]] && [[ -n "$(ls -A "${legacy}" 2>/dev/null)" ]]; then
        echo "${legacy}"
        return 0
    fi

    if [[ -d "${new}" ]]; then
        echo "${new}"
    elif [[ -d "${legacy}" ]]; then
        echo "${legacy}"
    else
        echo "${new}"
    fi
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

_economist_rss_tmp=""

economist_rss_temp_rm() {
    [[ -n "${1-}" ]] && rm -f "${1}"
}

economist_rss_temp_end() {
    economist_rss_temp_rm "${_economist_rss_tmp-}"
    _economist_rss_tmp=""
}

economist_rss_fetch_to() {
    local dest="$1"

    curl -fsSL "${ECONOMIST_RSS_URL}" -o "${dest}"
}

economist_status_wanted() {
    [[ -t 0 ]] || [[ -r /dev/tty ]]
}

economist_status_msg() {
    economist_status_wanted || return 0
    printf '%s\n' "$*" >&2
}

economist_rss_fetch_with_progress() {
    local dest="$1" dots_pid=0 item_count=0 rc=0

    if economist_status_wanted; then
        printf 'Fetching RSS feed' >&2
        (
            while true; do
                printf '.' >&2
                sleep 0.4
            done
        ) &
        dots_pid=$!
    fi

    if economist_rss_fetch_to "${dest}"; then
        rc=0
    else
        rc=1
    fi

    if (( dots_pid > 0 )); then
        kill "${dots_pid}" 2>/dev/null || true
        wait "${dots_pid}" 2>/dev/null || true
        if (( rc == 0 )); then
            item_count="$(economist_rss_item_count "${dest}")"
            printf ' ok (%s item(s)).\n' "${item_count}" >&2
        else
            printf ' failed.\n' >&2
        fi
    fi
    return "${rc}"
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

economist_edition_iso_from_dir_basename() {
    local name="$1"

    if [[ "${name}" =~ ^([0-9]{4})\.([0-9]{2})\.([0-9]{2})_TheEconomist$ ]]; then
        echo "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
        return 0
    fi
    if [[ "${name}" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})_TheEconomist$ ]]; then
        echo "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
        return 0
    fi
    return 1
}

economist_local_edition_status_for_iso() {
    local iso="$1" alt_iso="${2:-}" issue_no="${3:-}" dir=""

    if dir="$(economist_resolve_processed_edition_dir "${iso}" "${alt_iso}" "${issue_no}" 2>/dev/null)"; then
        echo "already processed"
        return 0
    fi

    if economist_edition_placeholder_dir_exists "${iso}"; then
        echo "output dir empty"
        return 0
    fi

    echo "not downloaded"
}

economist_sat_iso_for_edition_iso() {
    local iso="$1" rss_file="" pos=""

    [[ "${iso}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1

    rss_file="$(mktemp)"
    if economist_rss_fetch_to "${rss_file}"; then
        pos="$(economist_rss_position_for_edition_date "${rss_file}" "${iso}" 2>/dev/null || true)"
        if [[ -n "${pos}" ]]; then
            economist_edition_date_for_rss_position "${pos}"
            rm -f "${rss_file}"
            return 0
        fi
    fi
    rm -f "${rss_file}"
    return 1
}

economist_edition_dir_has_processed_content() {
    local dir="$1" bytes=0 min_bytes=""

    [[ -d "${dir}" ]] || return 1

    if [[ -n "$(find "${dir}" -type f \( -name '*.mp3' -o -name '*.m4a' -o -name '*.aac' \) \
        -size +100k -print -quit 2>/dev/null)" ]]; then
        return 0
    fi
    if [[ -f "${dir}/_org_file.rar" || -f "${dir}/_org_mp3_files_NO_speechnorm_NO_speedup.rar" ]]; then
        return 0
    fi

    min_bytes="$(economist_min_processed_edition_bytes)"
    bytes="$(economist_dir_size_bytes "${dir}")"
    (( bytes >= min_bytes ))
}

economist_remove_empty_edition_placeholders_for_iso() {
    local iso="$1" root="" path=""

    local -a roots=()
    economist_edition_active_storage_roots roots
    for root in "${roots[@]}"; do
        for path in \
            "$(economist_edition_dir_for_root "${iso}" "${root}" 2>/dev/null || true)" \
            "$(economist_legacy_edition_dir_for_root "${iso}" "${root}" 2>/dev/null || true)"; do
            [[ -d "${path}" ]] || continue
            economist_edition_dir_has_processed_content "${path}" && continue
            if [[ -z "$(ls -A "${path}" 2>/dev/null)" ]]; then
                rmdir "${path}" 2>/dev/null || true
            fi
        done
    done
}

economist_min_processed_edition_bytes() {
    echo 1000000
}

economist_append_unique_storage_root() {
    local array_name="$1"
    local -n _arr_ref="${array_name}"
    local root="$2" existing=""

    [[ -n "${root}" ]] || return 0
    for existing in "${_arr_ref[@]}"; do
        [[ "${existing}" == "${root}" ]] && return 0
    done
    _arr_ref+=("${root}")
}

economist_edition_storage_roots() {
    local array_name="$1"
    local -n _roots_ref="${array_name}"

    _roots_ref=()
    economist_append_unique_storage_root "${array_name}" "${ECONOMIST_OUTPUT_DIR:-}"
    economist_append_unique_storage_root "${array_name}" "${ECONOMIST_WORK_DIR:-}"
    economist_append_unique_storage_root "${array_name}" "${ECONOMIST_ARCHIVE_DIR:-}"
}

economist_edition_active_storage_roots() {
    local array_name="$1"
    local -n _roots_ref="${array_name}"

    _roots_ref=()
    economist_append_unique_storage_root "${array_name}" "${ECONOMIST_OUTPUT_DIR:-}"
    economist_append_unique_storage_root "${array_name}" "${ECONOMIST_WORK_DIR:-}"
}

economist_edition_dir_for_root() {
    local iso="$1" root="$2" base=""

    base="$(economist_edition_dir_basename_for_date "${iso}")" || return 1
    echo "${root}/${base}"
}

economist_legacy_edition_dir_for_root() {
    local iso="$1" root="$2" base=""

    base="$(economist_legacy_edition_dir_basename_for_date "${iso}")" || return 1
    echo "${root}/${base}"
}

economist_edition_placeholder_dir_exists() {
    local iso="$1" root=""

    local -a roots=()
    economist_edition_active_storage_roots roots
    for root in "${roots[@]}"; do
        [[ -d "$(economist_edition_dir_for_root "${iso}" "${root}" 2>/dev/null || true)" ]] && return 0
        [[ -d "$(economist_legacy_edition_dir_for_root "${iso}" "${root}" 2>/dev/null || true)" ]] && return 0
    done
    return 1
}

economist_append_edition_dir_candidates_for_iso() {
    local iso="$1"
    local candidates_name="$2"
    local -n _candidates_ref="${candidates_name}"
    local root=""

    local -a roots=()
    economist_edition_storage_roots roots
    for root in "${roots[@]}"; do
        economist_append_unique_dir_candidate "${candidates_name}" "$(economist_edition_dir_for_root "${iso}" "${root}" 2>/dev/null || true)"
        economist_append_unique_dir_candidate "${candidates_name}" "$(economist_legacy_edition_dir_for_root "${iso}" "${root}" 2>/dev/null || true)"
    done
}

economist_append_unique_dir_candidate() {
    local array_name="$1"
    local -n _arr_ref="${array_name}"
    local candidate="$2" existing=""

    [[ -n "${candidate}" && -d "${candidate}" ]] || return 0
    for existing in "${_arr_ref[@]}"; do
        [[ "${existing}" == "${candidate}" ]] && return 0
    done
    _arr_ref+=("${candidate}")
}

economist_collect_processed_edition_dir_candidates() {
    local iso="$1" alt_iso="${2:-}" issue_no="${3:-}" candidates_name="$4"
    local -n _candidates_ref="${candidates_name}"
    local rss_file="" pos="" candidate="" basename="" date_iso="" dir_issue=""
    local root=""

    economist_append_edition_dir_candidates_for_iso "${iso}" "${candidates_name}"

    if [[ -z "${alt_iso}" ]]; then
        rss_file="$(mktemp)"
        if economist_rss_fetch_to "${rss_file}"; then
            pos="$(economist_rss_position_for_edition_date "${rss_file}" "${iso}" 2>/dev/null || true)"
            if [[ -n "${pos}" ]]; then
                alt_iso="$(economist_edition_date_for_rss_position "${pos}")"
            fi
        fi
        rm -f "${rss_file}"
    fi

    if [[ -n "${alt_iso}" ]]; then
        economist_append_edition_dir_candidates_for_iso "${alt_iso}" "${candidates_name}"
    fi

    local -a roots=()
    economist_edition_storage_roots roots
    shopt -s nullglob
    for root in "${roots[@]}"; do
        for candidate in "${root}"/*_TheEconomist; do
            [[ -d "${candidate}" ]] || continue
            basename="$(basename "${candidate}")"
            date_iso="$(economist_edition_iso_from_dir_basename "${basename}" 2>/dev/null || true)"
            dir_issue=""
            if [[ -n "${date_iso}" ]]; then
                if [[ "${date_iso}" == "${iso}" ]] \
                    || [[ -n "${alt_iso}" && "${date_iso}" == "${alt_iso}" ]]; then
                    economist_append_unique_dir_candidate "${candidates_name}" "${candidate}"
                fi
                dir_issue="$(economist_issue_number_for_edition_date "${date_iso}" 2>/dev/null || true)"
            fi
            if [[ "${issue_no}" =~ ^[0-9]+$ && "${dir_issue}" == "${issue_no}" ]]; then
                economist_append_unique_dir_candidate "${candidates_name}" "${candidate}"
            fi
        done
    done
    shopt -u nullglob
}

economist_resolve_processed_edition_dir() {
    local iso="$1" alt_iso="${2:-}" issue_no="${3:-}"
    local -a candidates=()
    local candidate="" best="" best_bytes=0 bytes=0

    economist_collect_processed_edition_dir_candidates "${iso}" "${alt_iso}" "${issue_no}" candidates

    for candidate in "${candidates[@]}"; do
        [[ -d "${candidate}" ]] || continue
        economist_edition_dir_has_processed_content "${candidate}" || continue
        bytes="$(economist_dir_size_bytes "${candidate}")"
        if (( bytes > best_bytes )); then
            best="${candidate}"
            best_bytes="${bytes}"
        fi
    done

    if [[ -n "${best}" ]]; then
        echo "${best}"
        return 0
    fi

    return 1
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
    local timed_out=0

    _char_ref=""
    echo -n "${prompt}"
    if [[ -r /dev/tty ]]; then
        read -t "${timeout}" -n 1 _char_ref </dev/tty || timed_out=1
    else
        read -t "${timeout}" -n 1 _char_ref || timed_out=1
    fi
    echo
    _char_ref="${_char_ref//$'\r'/}"
    if (( $# >= 4 )); then
        local -n _timed_out_ref="$4"
        _timed_out_ref="${timed_out}"
    fi
}

economist_read_tty_pick_choice() {
    local prompt="$1"
    local -n _choice_ref="$2"
    local first="" rest=""

    _choice_ref=""
    echo -n "${prompt}"
    if [[ -r /dev/tty ]]; then
        IFS= read -r -n 1 first </dev/tty || first=""
    else
        IFS= read -r -n 1 first || first=""
    fi

    case "${first}" in
        $'\n'|'')
            echo
            return 0
            ;;
        q|Q)
            _choice_ref="q"
            echo
            return 0
            ;;
        [0-9])
            if [[ -r /dev/tty ]]; then
                IFS= read -r rest </dev/tty || rest=""
            else
                IFS= read -r rest || rest=""
            fi
            _choice_ref="${first}${rest}"
            _choice_ref="${_choice_ref//[[:space:]]/}"
            return 0
            ;;
        *)
            echo
            _choice_ref="?"
            return 0
            ;;
    esac
}

economist_edition_iso_from_weekly_url() {
    local url="$1"

    [[ "${url}" =~ /weeklyedition/([0-9]{4}-[0-9]{2}-[0-9]{2}) ]] || return 1
    echo "${BASH_REMATCH[1]}"
}

economist_normalize_edition_iso() {
    local input="$1" y="" m="" d="" iso=""

    [[ -n "${input}" ]] || return 1

    if [[ "${input}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        iso="${input}"
    elif [[ "${input}" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]]; then
        iso="${input//./-}"
    elif [[ "${input}" =~ ^[0-9]{8}$ ]]; then
        y="${input:0:4}"
        m="${input:4:2}"
        d="${input:6:2}"
        iso="${y}-${m}-${d}"
    else
        return 1
    fi

    [[ "$(date -d "${iso}" +%F 2>/dev/null || true)" == "${iso}" ]] || return 1
    echo "${iso}"
}

economist_force_redownload_hint() {
    echo "Use: economist-0-runme.sh --force   (or -f) to re-download and reprocess."
}

economist_print_website_vs_rss_explanation() {
    local website_iso="$1"

    [[ -n "${website_iso}" ]] || return 0

    cat <<EOF

------------------------------------------------------------------------
NOTE: Website cover date is NOT what this script downloads
------------------------------------------------------------------------

  The Economist website already shows cover date ${website_iso}.
  (from economist.com/weeklyedition/archive — for information only)

  This script does NOT download from that website page.
  It uses ONLY the Economist RSS feed.
  It downloads ONLY editions whose audio file is verified on the server
  (the same check as --show-available).

  A newer date on the website does NOT mean this run will download it.
  When RSS has no new verified edition yet, the script stops here.

------------------------------------------------------------------------

EOF
}

economist_append_unique_iso() {
    local array_name="$1" iso="$2" existing=""

    local -n _arr_ref="${array_name}"
    [[ -n "${iso}" ]] || return 0
    for existing in "${_arr_ref[@]}"; do
        [[ "${existing}" == "${iso}" ]] && return 0
    done
    _arr_ref+=("${iso}")
}

economist_collect_verified_rss_edition_isos() {
    local array_name="$1"
    local -n _isos_ref="${array_name}"
    local rss_file="" pos=0 item_count=0 url="" iso="" ok=0

    _isos_ref=()
    rss_file="$(mktemp)"
    if economist_rss_fetch_with_progress "${rss_file}"; then
        item_count="$(economist_rss_item_count "${rss_file}")"
        if (( item_count > 0 )); then
            if economist_status_wanted; then
                printf 'Checking %s feed item(s) on server' "${item_count}" >&2
            fi
            for (( pos = 1; pos <= item_count; ++pos )); do
                economist_status_wanted && printf '.' >&2
                url="$(economist_rss_enclosure_url_at "${rss_file}" "${pos}" 2>/dev/null || true)"
                [[ -n "${url}" ]] || continue
                economist_verify_enclosure_on_server "${url}" || continue
                iso="$(economist_edition_date_for_rss_item "${rss_file}" "${pos}")" || continue
                economist_append_unique_iso "${array_name}" "${iso}"
            done
            economist_status_wanted && printf ' done.\n' >&2
        fi
    fi
    economist_rss_temp_rm "${rss_file}"
    (( ${#_isos_ref[@]} > 0 )) && ok=1
    (( ok ))
}

economist_nearest_verified_from_available() {
    local requested_iso="$1"
    local -n _available_ref="$2"
    local -n _nearest_ref="$3"
    local iso="" req_epoch=0 iso_epoch=0 diff=0 best="" best_diff=-1

    _nearest_ref=""
    [[ "${requested_iso}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
    (( ${#_available_ref[@]} > 0 )) || return 1

    req_epoch="$(date -d "${requested_iso}" +%s)"
    for iso in "${_available_ref[@]}"; do
        iso_epoch="$(date -d "${iso}" +%s)"
        if (( iso_epoch >= req_epoch )); then
            diff=$(( iso_epoch - req_epoch ))
        else
            diff=$(( req_epoch - iso_epoch ))
        fi
        if (( best_diff < 0 || diff < best_diff || ( diff == best_diff && iso < best ) )); then
            best="${iso}"
            best_diff="${diff}"
        fi
    done

    [[ -n "${best}" ]] || return 1
    _nearest_ref="${best}"
}

economist_nearest_verified_rss_edition_iso() {
    local requested_iso="$1"
    local -n _nearest_ref="$2"
    local -a available=()

    _nearest_ref=""
    economist_collect_verified_rss_edition_isos available || return 1
    economist_nearest_verified_from_available "${requested_iso}" available _nearest_ref
}

economist_window_verified_isos_around() {
    local requested_iso="$1"
    local -n _available_ref="$2"
    local -n _window_ref="$3"
    local before_count="${4:-5}" after_count="${5:-5}"
    local -a sorted=() before=() after=()
    local req_epoch=0 iso_epoch=0 iso="" idx=0 before_start=0 end=0

    _window_ref=()
    [[ "${requested_iso}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
    (( ${#_available_ref[@]} > 0 )) || return 1

    req_epoch="$(date -d "${requested_iso}" +%s)"
    mapfile -t sorted < <(printf '%s\n' "${_available_ref[@]}" | LC_ALL=C sort -u)

    for iso in "${sorted[@]}"; do
        [[ -n "${iso}" ]] || continue
        iso_epoch="$(date -d "${iso}" +%s)"
        if (( iso_epoch < req_epoch )); then
            before+=("${iso}")
        elif (( iso_epoch > req_epoch )); then
            after+=("${iso}")
        fi
    done

    local idx=0 before_start=0
    before_start=0
    if (( ${#before[@]} > before_count )); then
        before_start=$((${#before[@]} - before_count))
    fi
    for (( idx=before_start; idx < ${#before[@]}; ++idx )); do
        _window_ref+=("${before[idx]}")
    done

    end=${#after[@]}
    if (( end > after_count )); then
        end="${after_count}"
    fi
    for (( idx=0; idx < end; ++idx )); do
        _window_ref+=("${after[idx]}")
    done

    (( ${#_window_ref[@]} > 0 ))
}

economist_reverse_pick_arrays() {
    local -n _isos_ref="$1"
    local -n _titles_ref="$2"
    local -n _local_ref="$3"
    local -n _issues_ref="$4"
    local -n _sat_isos_ref="$5"
    local -n _dirs_ref="$6"
    local idx=0
    local -a rev_isos=() rev_titles=() rev_local=() rev_issues=() rev_sat_isos=() rev_dirs=()

    if (( ${#_isos_ref[@]} <= 1 )); then
        return 0
    fi

    for (( idx = ${#_isos_ref[@]} - 1; idx >= 0; --idx )); do
        rev_isos+=("${_isos_ref[idx]}")
        rev_titles+=("${_titles_ref[idx]}")
        rev_local+=("${_local_ref[idx]}")
        rev_issues+=("${_issues_ref[idx]}")
        rev_sat_isos+=("${_sat_isos_ref[idx]}")
        rev_dirs+=("${_dirs_ref[idx]}")
    done
    _isos_ref=("${rev_isos[@]}")
    _titles_ref=("${rev_titles[@]}")
    _local_ref=("${rev_local[@]}")
    _issues_ref=("${rev_issues[@]}")
    _sat_isos_ref=("${rev_sat_isos[@]}")
    _dirs_ref=("${rev_dirs[@]}")
}

economist_rss_build_pick_arrays_for_isos() {
    local -n _filter_isos_ref="$1"
    local -n _pick_isos_ref="$2"
    local -n _pick_titles_ref="$3"
    local -n _pick_local_ref="$4"
    local -n _pick_issues_ref="$5"
    local -n _pick_sat_isos_ref="$6"
    local -n _pick_dirs_ref="$7"
    local rss_file="" item_count=0 pos=0 url="" edition_iso="" title="" issue_no=""
    local local_status="" processed_dir="" sat_iso=""
    local -A filter_map=()
    local iso=""

    _pick_isos_ref=()
    _pick_titles_ref=()
    _pick_local_ref=()
    _pick_issues_ref=()
    _pick_sat_isos_ref=()
    _pick_dirs_ref=()

    for iso in "${_filter_isos_ref[@]}"; do
        filter_map["${iso}"]=1
    done

    rss_file="$(mktemp)"
    if ! economist_rss_fetch_with_progress "${rss_file}"; then
        economist_rss_temp_rm "${rss_file}"
        return 1
    fi

    item_count="$(economist_rss_item_count "${rss_file}")"
    if (( item_count > 0 )); then
        if economist_status_wanted; then
            printf 'Loading details for %s nearby edition(s)' "${#_filter_isos_ref[@]}" >&2
        fi
        for (( pos = 1; pos <= item_count; ++pos )); do
            economist_status_wanted && printf '.' >&2
            url="$(economist_rss_enclosure_url_at "${rss_file}" "${pos}" 2>/dev/null || true)"
            [[ -n "${url}" ]] || continue
            economist_verify_enclosure_on_server "${url}" || continue
            edition_iso="$(economist_edition_date_for_rss_item "${rss_file}" "${pos}")" || continue
            [[ -n "${filter_map[${edition_iso}]+x}" ]] || continue

            title="$(economist_rss_item_title_at "${rss_file}" "${pos}")"
            sat_iso="$(economist_edition_date_for_rss_position "${pos}")"
            issue_no="$(economist_issue_number_for_edition_date "${edition_iso}" 2>/dev/null || echo "—")"
            processed_dir="$(economist_resolve_processed_edition_dir "${edition_iso}" "${sat_iso}" "${issue_no}" 2>/dev/null || true)"
            if [[ -n "${processed_dir}" ]]; then
                local_status="already processed"
            elif economist_edition_placeholder_dir_exists "${edition_iso}"; then
                local_status="output dir empty"
            else
                local_status="not downloaded"
            fi

            _pick_isos_ref+=("${edition_iso}")
            _pick_titles_ref+=("${title}")
            _pick_local_ref+=("${local_status}")
            _pick_issues_ref+=("${issue_no}")
            _pick_sat_isos_ref+=("${sat_iso}")
            _pick_dirs_ref+=("${processed_dir}")
        done
        economist_status_wanted && printf ' done.\n' >&2
    fi
    economist_rss_temp_rm "${rss_file}"

    (( ${#_pick_isos_ref[@]} > 0 )) || return 1
    economist_reverse_pick_arrays \
        _pick_isos_ref _pick_titles_ref _pick_local_ref _pick_issues_ref _pick_sat_isos_ref _pick_dirs_ref
}

economist_interactive_select_from_pick_arrays() {
    local -n _picked_iso_ref="$1"
    local -n _pick_isos_ref="$2"
    local -n _pick_titles_ref="$3"
    local -n _pick_local_ref="$4"
    local -n _pick_issues_ref="$5"
    local -n _pick_sat_isos_ref="$6"
    local -n _pick_dirs_ref="$7"
    local list_heading="$8"
    local choice="" sel_idx=0

    _picked_iso_ref=""

    if [[ ! -t 0 && ! -r /dev/tty ]]; then
        return 1
    fi

    while true; do
        echo
        echo "${list_heading}"
        economist_show_available_print_editions \
            _pick_isos_ref _pick_titles_ref _pick_local_ref _pick_issues_ref _pick_sat_isos_ref _pick_dirs_ref
        echo

        while true; do
            economist_read_tty_pick_choice \
                "To download: enter 1–${#_pick_isos_ref[@]} (1 = newest); Q quits; Enter quits: " \
                choice

            case "${choice}" in
                q|Q|'')
                    return 1
                    ;;
                \?)
                    echo "Invalid input — enter 1–${#_pick_isos_ref[@]} to download, Q to quit, or Enter to quit."
                    ;;
                *[!0-9]*)
                    echo "Invalid input — enter 1–${#_pick_isos_ref[@]} to download, Q to quit, or Enter to quit."
                    ;;
                *)
                    choice=$((10#${choice}))
                    if (( choice >= 1 && choice <= ${#_pick_isos_ref[@]} )); then
                        sel_idx=$((${#_pick_isos_ref[@]} - choice))
                        _picked_iso_ref="${_pick_isos_ref[sel_idx]}"
                        return 0
                    fi
                    echo "Invalid input — enter 1–${#_pick_isos_ref[@]} to download, Q to quit, or Enter to quit."
                    ;;
            esac
        done
    done
}

economist_prompt_browse_editions_near_date() {
    local requested_iso="$1" answer="" timed_out=0

    economist_read_tty_char \
        "Show verified editions near ${requested_iso} (5 before, 5 after)? [y/N]: " \
        answer 60 timed_out
    case "${answer}" in
        y|Y)
            (( timed_out == 0 ))
            ;;
        *)
            return 1
            ;;
    esac
}

economist_pick_edition_window_around_date() {
    local requested_iso="$1"
    local -n _available_ref="$2"
    local -n _picked_iso_ref="$3"
    local -a window_isos=() pick_isos=() pick_titles=() pick_local=() pick_issues=() pick_sat_isos=() pick_dirs=()

    _picked_iso_ref=""

    if ! economist_window_verified_isos_around "${requested_iso}" _available_ref window_isos; then
        echo "No other verified editions near ${requested_iso}."
        return 1
    fi

    if ! economist_prompt_browse_editions_near_date "${requested_iso}"; then
        return 1
    fi

    economist_status_msg ""
    economist_status_msg "Please wait — loading nearby verified editions from RSS..."

    if ! economist_rss_build_pick_arrays_for_isos \
        window_isos pick_isos pick_titles pick_local pick_issues pick_sat_isos pick_dirs; then
        echo "Could not load nearby editions from RSS." >&2
        return 1
    fi

    economist_interactive_select_from_pick_arrays \
        _picked_iso_ref \
        pick_isos pick_titles pick_local pick_issues pick_sat_isos pick_dirs \
        "Verified editions near ${requested_iso} (oldest at top; #1 = newest at bottom):"
}

economist_prompt_nearest_edition_fallback() {
    local requested_iso="$1" nearest_iso="$2" issue_no="" answer="" timed_out=0

    issue_no="$(economist_issue_number_for_edition_date "${nearest_iso}" 2>/dev/null || echo "—")"
    echo
    echo "Edition ${requested_iso} is not available on the RSS server."
    echo "Nearest verified edition: ${nearest_iso} (issue ${issue_no})."

    if [[ ! -t 0 && ! -r /dev/tty ]]; then
        echo "Non-interactive session — not downloading a substitute edition."
        return 1
    fi

    economist_read_tty_char "Download ${nearest_iso} instead? [y/N]: " answer 60 timed_out
    case "${answer}" in
        y|Y)
            return 0
            ;;
        n|N)
            if (( timed_out == 0 )); then
                return 2
            fi
            return 1
            ;;
        q|Q|''|*)
            return 1
            ;;
    esac
}

economist_verify_edition_date_on_server() {
    local iso="$1" rss_file="" pos=0 item_count=0 url="" edition_at_pos="" rc=1

    [[ "${iso}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1

    rss_file="$(mktemp)"
    if economist_rss_fetch_with_progress "${rss_file}"; then
        item_count="$(economist_rss_item_count "${rss_file}")"
        if (( item_count > 0 )); then
            if economist_status_wanted; then
                printf 'Checking edition %s on server' "${iso}" >&2
            fi
            for (( pos = 1; pos <= item_count; ++pos )); do
                edition_at_pos="$(economist_edition_date_for_rss_item "${rss_file}" "${pos}")" || continue
                [[ "${edition_at_pos}" == "${iso}" ]] || continue
                url="$(economist_rss_enclosure_url_at "${rss_file}" "${pos}" 2>/dev/null || true)"
                if [[ -n "${url}" ]] && economist_verify_enclosure_on_server "${url}"; then
                    economist_status_wanted && printf ' ok.\n' >&2
                    rc=0
                    break
                fi
            done
            if (( rc != 0 )) && economist_status_wanted; then
                printf '.. not found.\n' >&2
            fi
        fi
    fi
    economist_rss_temp_rm "${rss_file}"
    return "${rc}"
}

economist_find_newest_verified_rss_edition() {
    local rss_file="" pos=0 item_count=0 url="" edition_at_pos="" found=""

    rss_file="$(mktemp)"
    if economist_rss_fetch_with_progress "${rss_file}"; then
        item_count="$(economist_rss_item_count "${rss_file}")"
        if (( item_count > 0 )); then
            if economist_status_wanted; then
                printf 'Checking feed for newest verified edition' >&2
            fi
            for (( pos = 1; pos <= item_count; ++pos )); do
                economist_status_wanted && printf '.' >&2
                url="$(economist_rss_enclosure_url_at "${rss_file}" "${pos}" 2>/dev/null || true)"
                [[ -n "${url}" ]] || continue
                economist_verify_enclosure_on_server "${url}" || continue
                edition_at_pos="$(economist_edition_date_for_rss_item "${rss_file}" "${pos}")" || continue
                found="${edition_at_pos}"
                break
            done
            if economist_status_wanted; then
                if [[ -n "${found}" ]]; then
                    printf ' ok (%s).\n' "${found}" >&2
                else
                    printf ' none verified.\n' >&2
                fi
            fi
        fi
    fi
    economist_rss_temp_rm "${rss_file}"
    [[ -n "${found}" ]] || return 1
    echo "${found}"
}

economist_check_new_edition_for_run() {
    local explicit_iso="${1:-}" force_reprocess="${2:-0}"
    local -n _resolved_iso_ref="$3"
    local edition_dir="" status="" issue_no="" sat_iso=""
    local -a verified_isos=()
    local nearest_iso="" nearest_prompt_rc=0 picked_nearby=""

    _resolved_iso_ref=""

    if [[ -n "${explicit_iso}" ]]; then
        economist_status_msg ""
        economist_status_msg "Checking whether edition ${explicit_iso} is on the RSS server."
        economist_status_msg "Please wait — fetching the feed and verifying files..."
        _resolved_iso_ref="${explicit_iso}"
        if ! economist_verify_edition_date_on_server "${explicit_iso}"; then
            nearest_iso=""
            nearest_prompt_rc=0
            picked_nearby=""
            verified_isos=()
            economist_status_msg ""
            economist_status_msg "Searching for the nearest verified edition (checking all RSS items)..."
            if ! economist_collect_verified_rss_edition_isos verified_isos; then
                issue_no="$(economist_issue_number_for_edition_date "${explicit_iso}" 2>/dev/null || echo "—")"
                echo
                echo "Edition ${explicit_iso} (issue ${issue_no}) is not on the RSS server."
                echo "No verified substitute edition was found."
                return 1
            fi
            if economist_nearest_verified_from_available "${explicit_iso}" verified_isos nearest_iso \
                && [[ -n "${nearest_iso}" ]]; then
                economist_prompt_nearest_edition_fallback "${explicit_iso}" "${nearest_iso}" || nearest_prompt_rc=$?
                case "${nearest_prompt_rc}" in
                    0)
                        _resolved_iso_ref="${nearest_iso}"
                        ;;
                    2)
                        if economist_pick_edition_window_around_date "${explicit_iso}" verified_isos picked_nearby; then
                            _resolved_iso_ref="${picked_nearby}"
                        else
                            echo "Download cancelled."
                            return 1
                        fi
                        ;;
                    *)
                        echo "Download cancelled."
                        return 1
                        ;;
                esac
            else
                issue_no="$(economist_issue_number_for_edition_date "${explicit_iso}" 2>/dev/null || echo "—")"
                echo
                echo "Edition ${explicit_iso} (issue ${issue_no}) is not on the RSS server."
                echo "No verified substitute edition was found."
                return 1
            fi
        fi
    else
        economist_status_msg ""
        economist_status_msg "Checking RSS feed for the newest verified edition..."
        economist_status_msg "Please wait — fetching the feed and verifying files..."
        if ! _resolved_iso_ref="$(economist_find_newest_verified_rss_edition)"; then
            echo
            echo "No new Economist edition on the server (nothing verified in the RSS feed)."
            return 1
        fi
    fi

    issue_no="$(economist_issue_number_for_edition_date "${_resolved_iso_ref}" 2>/dev/null || echo "—")"
    sat_iso="$(economist_sat_iso_for_edition_iso "${_resolved_iso_ref}" 2>/dev/null || true)"
    status="$(economist_local_edition_status_for_iso "${_resolved_iso_ref}" "${sat_iso}" "${issue_no}")"

    if [[ "${status}" == "already processed" && "${force_reprocess}" != 1 && -z "${explicit_iso}" ]]; then
        echo
        echo "No new edition — ${_resolved_iso_ref} (issue ${issue_no}) is already processed."
        economist_force_redownload_hint
        return 1
    fi

    return 0
}

economist_rss_title_for_edition_iso() {
    local iso="$1" rss_file="" pos="" title=""

    rss_file="$(mktemp)"
    if economist_rss_fetch_to "${rss_file}"; then
        pos="$(economist_rss_position_for_edition_date "${rss_file}" "${iso}" 2>/dev/null || true)"
        if [[ -n "${pos}" ]]; then
            title="$(economist_rss_item_title_at "${rss_file}" "${pos}")"
        fi
    fi
    economist_rss_temp_rm "${rss_file}"
    [[ -n "${title}" ]] || return 1
    echo "${title}"
}

economist_print_edition_selection_summary() {
    local iso="$1" sat_iso="" issue_no="" local_status="" processed_dir="" title=""

    sat_iso="$(economist_sat_iso_for_edition_iso "${iso}" 2>/dev/null || true)"
    issue_no="$(economist_issue_number_for_edition_date "${iso}" 2>/dev/null || echo "—")"
    processed_dir="$(economist_resolve_processed_edition_dir "${iso}" "${sat_iso}" "${issue_no}" 2>/dev/null || true)"
    local_status="$(economist_local_edition_status_for_iso "${iso}" "${sat_iso}" "${issue_no}")"
    title="$(economist_rss_title_for_edition_iso "${iso}" 2>/dev/null || echo "—")"

    printf '  %-12s %s\n' "Edition:" "${iso}"
    printf '  %-12s %s\n' "Title:" "${title:0:72}"
    printf '  %-12s %s\n' "Issue:" "${issue_no}"
    printf '  %-12s %s\n' "Local:" "${local_status}"
    printf '  %-12s %s\n' "Age:" "$(economist_format_age_from_today "${iso}")"
    printf '  %-12s %s\n' "Size:" \
        "$(economist_show_available_edition_size \
            "${iso}" "${sat_iso}" "${issue_no}" "${processed_dir}")"
}

# Confirm before download/reprocess (same screen as --show-available pick).
# Returns: 0 = proceed, 1 = no/back, 2 = quit.
economist_confirm_edition_before_download() {
    local iso="$1"
    local -n _force_reprocess_ref="$2"
    local answer="" local_status="" prompt=""

    if [[ ! -t 0 && ! -r /dev/tty ]]; then
        return 0
    fi

    local_status="$(economist_local_edition_status_for_iso "${iso}")"

    economist_status_msg ""
    economist_status_msg "Please wait — loading edition summary from RSS..."

    echo
    economist_print_edition_selection_summary "${iso}"
    echo
    if [[ "${ECONOMIST_CONFIG_OK_PRINTED:-0}" != 1 ]]; then
        economist_print_config_ok
    fi
    echo

    if [[ "${local_status}" == "already processed" ]]; then
        prompt="Reprocess this edition? [Y/n/q]: "
    else
        prompt="Download this edition? [Y/n/q]: "
    fi

    economist_read_tty_char "${prompt}" answer 10
    case "${answer}" in
        q|Q)
            return 2
            ;;
        n|N)
            return 1
            ;;
        ''|y|Y)
            if [[ "${local_status}" == "already processed" ]]; then
                _force_reprocess_ref=1
            else
                _force_reprocess_ref=0
            fi
            return 0
            ;;
        *)
            if [[ "${local_status}" == "already processed" ]]; then
                _force_reprocess_ref=1
            else
                _force_reprocess_ref=0
            fi
            return 0
            ;;
    esac
}

economist_prompt_proceed_before_download() {
    local iso="$1" force_flag=0 confirm_rc=0

    economist_confirm_edition_before_download "${iso}" force_flag
    confirm_rc=$?
    if (( confirm_rc == 0 )); then
        return 0
    fi
    return 1
}

economist_force_reprocess_edition() {
    local edition_dir="$1" work_dir="$2"

    [[ -n "${edition_dir}" && -d "${edition_dir}" ]] && rm -rf "${edition_dir}"
    economist_cleanup_work_dir "${work_dir}" 1
}

economist_format_age_from_today() {
    local iso="$1" ty=0 tm=0 td=0 ey=0 em=0 ed=0 cy=0 cm=0 cd=0 dim=0

    [[ "${iso}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || {
        printf '%11s' '—'
        return 0
    }
    if [[ "$(date -d "${iso}" +%F 2>/dev/null || true)" != "${iso}" ]]; then
        printf '%11s' '—'
        return 0
    fi

    ty=$(date +%Y)
    tm=$(date +%-m)
    td=$(date +%-d)
    ey=$((10#${iso:0:4}))
    em=$((10#${iso:5:2}))
    ed=$((10#${iso:8:2}))

    cy=$((ty - ey))
    cm=$((tm - em))
    cd=$((td - ed))

    if (( cd < 0 )); then
        cm=$((cm - 1))
        dim="$(date -d "${ty}-$(printf '%02d' "${tm}")-01 - 1 day" +%-d 2>/dev/null || echo 28)"
        cd=$((cd + dim))
    fi
    if (( cm < 0 )); then
        cy=$((cy - 1))
        cm=$((cm + 12))
    fi

    if (( cy < 0 || (cy == 0 && cm < 0) || (cy == 0 && cm == 0 && cd < 0) )); then
        cy=0
        cm=0
        cd=0
    fi

    printf '%2sy %2sm %2sd' "${cy}" "${cm}" "${cd}"
}

economist_dir_size_bytes() {
    local dir="$1" bytes="" blocks=0

    [[ -n "${dir}" && -d "${dir}" ]] || {
        echo "0"
        return 0
    }

    bytes="$(du -sb "${dir}" 2>/dev/null | awk '{print $1}')"
    if [[ "${bytes:-0}" =~ ^[0-9]+$ ]] && (( bytes > 0 )); then
        echo "${bytes}"
        return 0
    fi

    bytes="$(find "${dir}" -type f -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}')"
    if [[ "${bytes:-0}" =~ ^[0-9]+$ ]] && (( bytes > 0 )); then
        echo "${bytes}"
        return 0
    fi

    bytes="$(find "${dir}" -type f -exec stat -c '%s' {} + 2>/dev/null | awk '{s+=$1} END {print s+0}')"
    if [[ "${bytes:-0}" =~ ^[0-9]+$ ]] && (( bytes > 0 )); then
        echo "${bytes}"
        return 0
    fi

    blocks="$(du -sk "${dir}" 2>/dev/null | awk '{print $1}')"
    if [[ "${blocks:-0}" =~ ^[0-9]+$ ]] && (( blocks > 0 )); then
        echo $(( blocks * 1024 ))
        return 0
    fi

    echo "0"
}

economist_format_bytes_all_units() {
    local bytes="$1" kb=0 mb=0 gb=""

    if [[ ! "${bytes:-0}" =~ ^[0-9]+$ ]] || (( bytes <= 0 )); then
        printf '%48s' '—'
        return 0
    fi

    kb=$(( (bytes + 1023) / 1024 ))
    mb=$(( (bytes + 524288) / 1048576 ))
    gb="$(awk -v b="${bytes}" 'BEGIN { print b / 1073741824 }')"
    [[ -n "${gb}" ]] || gb="0"
    LC_NUMERIC=C printf '%12d B %8d kB %6d MB %8.2f GB' "${bytes}" "${kb}" "${mb}" "${gb}"
}

economist_show_available_edition_size() {
    local iso="$1" sat_iso="$2" issue_no="$3" cached_dir="${4:-}" dir="" bytes=0

    dir="${cached_dir}"
    if [[ -z "${dir}" ]]; then
        dir="$(economist_resolve_processed_edition_dir "${iso}" "${sat_iso}" "${issue_no}" 2>/dev/null || true)"
    fi
    [[ -n "${dir}" ]] || {
        printf '%48s' '—'
        return 0
    }

    bytes="$(economist_dir_size_bytes "${dir}")"
    economist_format_bytes_all_units "${bytes}"
}

economist_show_available_print_editions() {
    local -n _isos_ref="$1"
    local -n _titles_ref="$2"
    local -n _local_ref="$3"
    local -n _issues_ref="$4"
    local -n _sat_isos_ref="$5"
    local -n _dirs_ref="$6"
    local idx=0 pick_num=0

    printf '  %3s %-12s %-36s %-18s %6s %11s %48s\n' \
        "#" "Edition" "Title" "Local" "Issue" "Age" "Size"
    printf '  %3s %-12s %-36s %-18s %6s %11s %48s\n' \
        "---" "--------" "-----" "-----" "-----" "---------" "------------------------------------------------"
    for (( idx = 0; idx < ${#_isos_ref[@]}; ++idx )); do
        pick_num=$((${#_isos_ref[@]} - idx))
        printf '  %3s %-12s %-36s %-18s %6s %11s %48s\n' \
            "${pick_num}" \
            "${_isos_ref[idx]}" \
            "${_titles_ref[idx]:0:36}" \
            "${_local_ref[idx]:0:18}" \
            "${_issues_ref[idx]}" \
            "$(economist_format_age_from_today "${_isos_ref[idx]}")" \
            "$(economist_show_available_edition_size \
                "${_isos_ref[idx]}" \
                "${_sat_isos_ref[idx]}" \
                "${_issues_ref[idx]}" \
                "${_dirs_ref[idx]}")"
        if (( pick_num % 10 == 0 )); then
            echo
        fi
    done
}

economist_show_and_pick_available_editions() {
    local -n _picked_iso_ref="$1"
    local -n _force_reprocess_ref="$2"
    local item_count=0 pos=0 edition_iso="" title="" url="" local_status=""
    local edition_dir="" choice="" idx=0 dots_pid=0 verified_count=0 sel_idx=0
    local issue_no="" confirm="" confirm_prompt=""
    local -a pick_isos=()
    local -a pick_titles=()
    local -a pick_local=()
    local -a pick_issues=()
    local -a pick_sat_isos=()
    local -a pick_dirs=()

    _picked_iso_ref=""
    _force_reprocess_ref=0

    economist_rss_temp_end
    _economist_rss_tmp="$(mktemp)"
    trap 'economist_rss_temp_end' RETURN

    if ! economist_rss_fetch_with_progress "${_economist_rss_tmp}"; then
        echo "Failed to fetch RSS: ${ECONOMIST_RSS_URL}" >&2
        return 1
    fi

    item_count="$(economist_rss_item_count "${_economist_rss_tmp}")"
    if [[ "${item_count}" -eq 0 ]]; then
        echo "No items found in RSS feed." >&2
        return 1
    fi

    if economist_status_wanted; then
        printf 'Checking %s feed item(s) on server' "${item_count}" >&2
    fi

    for (( pos = 1; pos <= item_count; ++pos )); do
        economist_status_wanted && printf '.' >&2
        url="$(economist_rss_enclosure_url_at "${_economist_rss_tmp}" "${pos}" 2>/dev/null || true)"
        [[ -n "${url}" ]] || continue
        if ! economist_verify_enclosure_on_server "${url}"; then
            continue
        fi

        title="$(economist_rss_item_title_at "${_economist_rss_tmp}" "${pos}")"
        edition_iso="$(economist_edition_date_for_rss_item "${_economist_rss_tmp}" "${pos}")" || continue
        sat_iso="$(economist_edition_date_for_rss_position "${pos}")"
        issue_no="$(economist_issue_number_for_edition_date "${edition_iso}" 2>/dev/null || echo "—")"
        processed_dir="$(economist_resolve_processed_edition_dir "${edition_iso}" "${sat_iso}" "${issue_no}" 2>/dev/null || true)"
        if [[ -n "${processed_dir}" ]]; then
            local_status="already processed"
        elif economist_edition_placeholder_dir_exists "${edition_iso}"; then
            local_status="output dir empty"
        else
            local_status="not downloaded"
        fi

        pick_isos+=("${edition_iso}")
        pick_titles+=("${title}")
        pick_local+=("${local_status}")
        pick_issues+=("${issue_no}")
        pick_sat_isos+=("${sat_iso}")
        pick_dirs+=("${processed_dir}")
        (( ++verified_count )) || true
    done

    printf ' %s verified.\n' "${verified_count}" >&2

    if [[ ${#pick_isos[@]} -eq 0 ]]; then
        echo "No editions verified as downloadable on the server." >&2
        return 1
    fi

    if [[ ${#pick_isos[@]} -gt 1 ]]; then
        local -a _rev_isos=() _rev_titles=() _rev_local=() _rev_issues=() _rev_sat_isos=() _rev_dirs=()
        for (( idx = ${#pick_isos[@]} - 1; idx >= 0; --idx )); do
            _rev_isos+=("${pick_isos[idx]}")
            _rev_titles+=("${pick_titles[idx]}")
            _rev_local+=("${pick_local[idx]}")
            _rev_issues+=("${pick_issues[idx]}")
            _rev_sat_isos+=("${pick_sat_isos[idx]}")
            _rev_dirs+=("${pick_dirs[idx]}")
        done
        pick_isos=("${_rev_isos[@]}")
        pick_titles=("${_rev_titles[@]}")
        pick_local=("${_rev_local[@]}")
        pick_issues=("${_rev_issues[@]}")
        pick_sat_isos=("${_rev_sat_isos[@]}")
        pick_dirs=("${_rev_dirs[@]}")
    fi

    if [[ ! -t 0 && ! -r /dev/tty ]]; then
        echo
        echo "Verified editions (oldest at top; #1 = newest at bottom):"
        economist_show_available_print_editions pick_isos pick_titles pick_local pick_issues pick_sat_isos pick_dirs
        echo
        echo "Non-interactive session — listing only (no pick)."
        return 0
    fi

    while true; do
        echo
        echo "Verified editions (oldest at top; #1 = newest at bottom):"
        economist_show_available_print_editions pick_isos pick_titles pick_local pick_issues pick_sat_isos pick_dirs
        echo

        while true; do
            economist_read_tty_pick_choice \
                "To download: enter 1–${#pick_isos[@]} (1 = newest); Q quits; Enter quits: " \
                choice

            case "${choice}" in
                q|Q|'')
                    return 0
                    ;;
                \?)
                    echo "Invalid input — enter 1–${#pick_isos[@]} to download, Q to quit, or Enter to quit."
                    ;;
                *[!0-9]*)
                    echo "Invalid input — enter 1–${#pick_isos[@]} to download, Q to quit, or Enter to quit."
                    ;;
                *)
                    choice=$((10#${choice}))
                    if (( choice >= 1 && choice <= ${#pick_isos[@]} )); then
                        sel_idx=$((${#pick_isos[@]} - choice))
                        break
                    fi
                    echo "Invalid input — enter 1–${#pick_isos[@]} to download, Q to quit, or Enter to quit."
                    ;;
            esac
        done

        echo
        confirm_rc=0
        economist_confirm_edition_before_download "${pick_isos[sel_idx]}" _force_reprocess_ref
        confirm_rc=$?
        case "${confirm_rc}" in
            0)
                _picked_iso_ref="${pick_isos[sel_idx]}"
                return 0
                ;;
            2)
                return 0
                ;;
            *)
                break
                ;;
        esac
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
        pipeline_confirm_quit) echo "quit before download" ;;
        no_new_edition) echo "no new edition on server" ;;
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
    elif [[ "${ECONOMIST_RUN_STEP}" == "pipeline_confirm_quit" ]]; then
        echo "quit before download"
    elif [[ "${ECONOMIST_RUN_STEP}" == "no_new_edition" ]]; then
        echo "no new edition on server"
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

economist_work_dir_has_pipeline_artifacts() {
    local work_dir="$1" item=""

    [[ -n "${work_dir}" && -d "${work_dir}" ]] || return 1

    [[ -f "${work_dir}/economist.rss" || -f "${work_dir}/economist.mp3" || -f "${work_dir}/chapters.txt" ]] && return 0
    [[ -f "${work_dir}/_org_file.rar" || -f "${work_dir}/_org_mp3_files_NO_speechnorm_NO_speedup.rar" ]] && return 0

    shopt -s nullglob
    for item in \
        "${work_dir}"/artwork_*.jpg \
        "${work_dir}"/tmp_*.mp3 \
        "${work_dir}"/*_tmp.mp3 \
        "${work_dir}"/*.mp3 \
        "${work_dir}"/*SPEECHNORM_SPEEDUP* \
        "${work_dir}"/*_TheEconomist
    do
        if [[ -e "${item}" ]]; then
            shopt -u nullglob
            return 0
        fi
    done
    shopt -u nullglob

    return 1
}

economist_cleanup_stale_run_leftovers() {
    local work_dir="$1" output_dir="$2"
    local found=0 d=""

    if economist_work_dir_has_pipeline_artifacts "${work_dir}"; then
        found=1
        echo
        echo "Found leftovers from a previous incomplete run in the work directory."
        economist_cleanup_work_dir "${work_dir}" 1
    fi

    if [[ -d "${output_dir}" ]]; then
        shopt -s nullglob
        for d in "${output_dir}"/*_TheEconomist; do
            [[ -d "${d}" ]] || continue
            [[ -n "$(ls -A "${d}" 2>/dev/null)" ]] && continue
            if (( ! found )); then
                echo
                echo "Found leftovers from a previous incomplete run."
                found=1
            fi
            echo "  removing empty output directory: ${d}"
            rmdir --ignore-fail-on-non-empty "${d}" 2>/dev/null || true
        done
        shopt -u nullglob
    fi

    if (( found )); then
        echo "Startup cleanup finished."
        echo
    fi
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
        elif [[ "${ECONOMIST_RUN_STEP}" == "pipeline_confirm_quit" ]]; then
            economist_summary_line "Run:" "quit before download"
        elif [[ "${ECONOMIST_RUN_STEP}" == "no_new_edition" ]]; then
            economist_summary_line "Run:" "no new edition on server"
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
