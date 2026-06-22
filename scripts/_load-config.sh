# shellcheck shell=bash
# Shared config loader for economist-weekly-audio scripts.

economist_default_conf_paths() {
    local root="$1"
    echo "${root}/economist.local.conf"
    echo "${root}/../economist-weekly-audio-private/economist.local.conf"
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
        echo "  1) cp economist.conf.example economist.local.conf and edit" >&2
        echo "  2) clone economist-weekly-audio-private next to this repo" >&2
        echo "  3) set ECONOMIST_CONF=/path/to/economist.local.conf" >&2
        exit 1
    fi

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
