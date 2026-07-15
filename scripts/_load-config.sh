# shellcheck shell=bash
# v. 1.4 - 2026.07.15 - load config from ${profile_location_dir:-$HOME}/conf/
# v. 1.3 - 2026.07.15 - require economist.local.conf mode 0600
# v. 1.2 - 2026.07.15 - config hint: profile_location_dir fallback to HOME
# v. 1.1 - 2026.07.15 - config hint: ~/github sibling path
# v. 1.0 - 2026.06.16 - shared config loader for pipeline scripts
# Shared config loader: paths, secrets, healthcheck pings, and chown helper.

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
