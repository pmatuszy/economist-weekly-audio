#!/usr/bin/env bash
# 2026.07.15 - v. 1.23 - after cron migration show old (commented) and new sections
# 2026.07.15 - v. 1.22 - offer to comment out obsolete economist cron lines and add new block
# 2026.07.15 - v. 1.21 - offer removal of obsolete /root/scripts Polish-era copies
# 2026.07.15 - v. 1.20 - drop _economist-script-header.sh; use github-bin _script_header.sh
# 2026.07.15 - v. 1.19 - install _economist-run-control.sh; Ctrl-C cleanup and pipeline summary
# v. 1.17 - 2026.07.15 - install economist-script-reinstall.sh into bin/
# v. 1.16 - 2026.07.15 - section separators; flock check for crontab hint
# v. 1.15 - 2026.07.15 - print crontab hint after install (paths, flock, archive)
# v. 1.14 - 2026.07.15 - create starter config from example when none exists
# v. 1.13 - 2026.07.15 - install script copies into bin/, not repo exec wrappers
# v. 1.12 - 2026.07.15 - pipeline scripts use economist-N-*.sh names
# v. 1.11 - 2026.07.15 - pipeline scripts restored to 0-4-economist-*.sh names
# v. 1.10 - 2026.07.15 - config replace: description, paths, then prompt line
# v. 1.9 - 2026.07.15 - config replace prompt: aligned paths, no one-liner
# v. 1.8 - 2026.07.15 - offer to replace conf/ config from private repo (20s, default N)
# v. 1.7 - 2026.07.15 - wrappers economist-*.sh; prompt to remove legacy numbered names
# v. 1.6 - 2026.07.15 - prompts default no [y/N/q]; --yes still auto-yes
# v. 1.5 - 2026.07.15 - prompts default yes [Y/n/q]; --yes auto-fixes chmod 600
# v. 1.4 - 2026.07.15 - prompts: single key [y/N/q], 300s timeout, default N
# v. 1.3 - 2026.07.15 - install economist.local.conf into conf/ beside bin/
# v. 1.2 - 2026.07.15 - check private config file permissions are 600
# v. 1.1 - 2026.07.15 - use profile_location_dir when set, else HOME
# v. 1.0 - 2026.07.15 - interactive install of wrappers into ~/bin from ~/github clone
# Copies economist-N-*.sh scripts into bin/; child scripts run from same directory.
# Single-key prompts [y/N/q] with 300s timeout; default is no.

set -euo pipefail

BASE_DIR="${profile_location_dir:-$HOME}"
PROMPT_TIMEOUT=300
CONFIG_REPLACE_TIMEOUT=20
SECTION_RULE='======================================================================'

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_NAME="$(basename "${REPO_ROOT}")"
SCRIPTS_DIR="${REPO_ROOT}/scripts"
BIN_DIR="${BASE_DIR}/bin"
DO_PULL=0
ASSUME_YES=0
INSTALL_HEADER_EXTRA_ARGS=()

LEGACY_WRAPPER_NAMES=(
    "0-economist-runme.sh"
    "1-economist-download.sh"
    "1-economist-sciagnij.sh"
    "2-economist-process-edition.sh"
    "2-economist-obrob.sh"
    "3-economist-speedup-loudness.sh"
    "3-zmien-szybkosc-podbij-glosnosc.sh"
    "4-economist-move-results.sh"
    "4-wszystko-obrobione-przenies-wyniki.sh"
    "economist-runme.sh"
    "economist-download.sh"
    "economist-process-edition.sh"
    "economist-speedup-loudness.sh"
    "economist-move-results.sh"
)

LEGACY_SCRIPTS_DIR="${LEGACY_SCRIPTS_DIR:-/root/scripts}"

usage() {
    cat <<EOF
Usage: install.sh [options]

Install pipeline scripts into a bin directory (default:
\${profile_location_dir:-\$HOME}/bin). Scripts call each other from that
same bin directory — not from the git repo.

Expected layout:
  \${profile_location_dir:-\$HOME}/github/${REPO_NAME}/                 # this repo
  \${profile_location_dir:-\$HOME}/github/${REPO_NAME}-private/         # optional secrets source
  \${profile_location_dir:-\$HOME}/conf/economist.local.conf             # installed config (mode 600)
  \${profile_location_dir:-\$HOME}/bin/economist-0-runme.sh             # installed scripts

Options:
  --bin-dir PATH   Target bin directory (default: \${profile_location_dir:-\$HOME}/bin)
  --pull           Run "git pull --ff-only" in this repo before installing
  -y, --yes        Install without prompts (auto-answer yes, like batch mode)
  --no_startup_delay   Skip random startup delay from _script_header.sh
  -h, --help       Show this help

Examples:
  ./install.sh
  ./install.sh --pull
  ./install.sh --bin-dir "\${profile_location_dir:-\$HOME}/bin" -y
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bin-dir)
            [[ $# -ge 2 ]] || { echo "Missing value for --bin-dir" >&2; exit 1; }
            BIN_DIR="$2"
            shift 2
            ;;
        --pull)
            DO_PULL=1
            shift
            ;;
        -y|--yes)
            ASSUME_YES=1
            shift
            ;;
        --no_startup_delay|NO_STARTUP_DELAY)
            INSTALL_HEADER_EXTRA_ARGS+=(NO_STARTUP_DELAY)
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if ! tty >/dev/null 2>&1; then
    INSTALL_HEADER_EXTRA_ARGS+=(NO_STARTUP_DELAY)
fi

# shellcheck source=scripts/_economist-run-control.sh
source "${SCRIPTS_DIR}/_economist-run-control.sh"
_economist_header_file="$(economist_find_script_header_file)" || true
if [[ -n "${_economist_header_file}" ]]; then
    if [[ ${#INSTALL_HEADER_EXTRA_ARGS[@]} -eq 0 ]] && ! tty >/dev/null 2>&1; then
        # shellcheck source=/dev/null
        . "${_economist_header_file}" NO_STARTUP_DELAY
    else
        # shellcheck source=/dev/null
        . "${_economist_header_file}" "${INSTALL_HEADER_EXTRA_ARGS[@]}"
    fi
    if (( ! script_is_run_interactively )); then
        echo "${SCRIPT_VERSION}"
        echo
    fi
else
    echo "Warning: _script_header.sh not found — install github-bin into ${profile_location_dir:-$HOME}/bin/." >&2
fi
unset _economist_header_file

CONF_DIR="$(dirname "${BIN_DIR}")/conf"
CONF_FILE="${CONF_DIR}/economist.local.conf"
EXAMPLE_CONF="${REPO_ROOT}/economist.conf.example"
PRIVATE_CONF="$(cd "${REPO_ROOT}/.." && pwd)/${REPO_NAME}-private/economist.local.conf"
LOCAL_CONF="${REPO_ROOT}/economist.local.conf"
CONFIG_PATH_LABEL_WIDTH=8
CONFIG_PATH_TEXT_COL=12

normalize_path() {
    local path="$1" dir base resolved=""

    if [[ -e "${path}" ]]; then
        resolved="$(readlink -f "${path}" 2>/dev/null || realpath "${path}" 2>/dev/null || true)"
        if [[ -n "${resolved}" ]]; then
            echo "${resolved}"
            return 0
        fi
    fi

    base="$(basename "${path}")"
    dir="$(dirname "${path}")"
    if [[ -d "${dir}" ]]; then
        echo "$(cd "${dir}" && pwd -P)/${base}"
    else
        echo "${path}"
    fi
}

print_aligned_config_path() {
    local label="$1" path="$2" dir base

    path="$(normalize_path "${path}")"
    dir="${path%/*}"
    base="${path##*/}"

    printf "  %-${CONFIG_PATH_LABEL_WIDTH}s  %s/\n" "${label}:" "${dir}"
    printf "%${CONFIG_PATH_TEXT_COL}s%s\n" "" "${base}"
}

print_section() {
    echo
    echo "${SECTION_RULE}"
    echo "$1"
    echo "${SECTION_RULE}"
    echo
}

print_config_replace_offer() {
    print_section "Config replace offer"
    echo "An economist.local.conf file is already installed in conf/."
    echo "The installer can overwrite it with the copy from your private repo"
    echo "(RSS URL, healthcheck, and paths). Waits ${CONFIG_REPLACE_TIMEOUT}s; default is no."
    echo
    print_aligned_config_path "current" "${CONF_FILE}"
    print_aligned_config_path "private" "${PRIVATE_CONF}"
}

if [[ ! -d "${SCRIPTS_DIR}" ]]; then
    echo "Scripts directory not found: ${SCRIPTS_DIR}" >&2
    exit 1
fi

if (( DO_PULL )); then
    if [[ -d "${REPO_ROOT}/.git" ]]; then
        echo "Pulling latest changes in ${REPO_ROOT}..."
        git -C "${REPO_ROOT}" pull --ff-only
    else
        echo "Skipping pull: ${REPO_ROOT} is not a git repository." >&2
    fi
fi

mapfile -t SCRIPT_PATHS < <(find "${SCRIPTS_DIR}" -maxdepth 1 -type f \( -name 'economist-[0-9]-*.sh' -o -name 'economist-script-reinstall.sh' \) | sort)

if [[ ${#SCRIPT_PATHS[@]} -eq 0 ]]; then
    echo "No installable scripts found in ${SCRIPTS_DIR}" >&2
    exit 1
fi

read_yes_no_quit() {
    local prompt="$1"
    local timeout="${2:-${PROMPT_TIMEOUT}}"
    local allow_batch="${3:-1}"
    local answer=""

    if (( ASSUME_YES && allow_batch )); then
        echo "${prompt}y (--yes)"
        REPLY=y
        return 0
    fi

    echo -n "${prompt}"
    read -t "${timeout}" -n 1 answer || answer=""
    echo
    answer="${answer//$'\r'/}"

    case "${answer}" in
        y|Y) REPLY=y ;;
        q|Q) REPLY=q ;;
        *)   REPLY=n ;;
    esac
}

flock_path() {
    command -v flock 2>/dev/null || true
}

install_flock_package() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "Installing util-linux (flock) via apt-get..."
        DEBIAN_FRONTEND=noninteractive apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y util-linux
        return $?
    fi
    if command -v dnf >/dev/null 2>&1; then
        echo "Installing util-linux (flock) via dnf..."
        dnf install -y util-linux
        return $?
    fi
    if command -v yum >/dev/null 2>&1; then
        echo "Installing util-linux (flock) via yum..."
        yum install -y util-linux
        return $?
    fi
    if command -v apk >/dev/null 2>&1; then
        echo "Installing util-linux (flock) via apk..."
        apk add --no-cache util-linux
        return $?
    fi
    echo "No supported package manager found. Install util-linux manually." >&2
    return 1
}

resolve_flock_for_cron() {
    local flock_bin

    flock_bin="$(flock_path)"
    if [[ -n "${flock_bin}" ]]; then
        FLOCK_BIN="${flock_bin}"
        USE_FLOCK_IN_CRON=1
        return 0
    fi

    FLOCK_BIN=""
    USE_FLOCK_IN_CRON=0

    if (( ASSUME_YES )); then
        echo "flock is not installed — crontab hint will omit flock (--yes)."
        return 0
    fi

    echo "flock is not installed (usually from the util-linux package)."

    if [[ "$(id -u)" -eq 0 ]]; then
        read_yes_no_quit "Install util-linux now to enable flock in cron? [y/N/q]: " "${PROMPT_TIMEOUT}" 0
        case "${REPLY}" in
            y)
                if install_flock_package; then
                    flock_bin="$(flock_path)"
                    if [[ -n "${flock_bin}" ]]; then
                        FLOCK_BIN="${flock_bin}"
                        USE_FLOCK_IN_CRON=1
                        echo "flock installed: ${FLOCK_BIN}"
                        return 0
                    fi
                fi
                echo "flock still not available — crontab hint will omit flock." >&2
                ;;
            q)
                echo "Quit."
                exit 0
                ;;
            *)
                echo "Crontab hint will omit flock (overlapping cron runs are possible)."
                ;;
        esac
    else
        echo "Not running as root — cannot install flock."
        echo "Crontab hint will omit flock (overlapping cron runs are possible)."
    fi
}

find_legacy_wrappers() {
    local -n _out="$1"
    local name path

    _out=()
    for name in "${LEGACY_WRAPPER_NAMES[@]}"; do
        path="${BIN_DIR}/${name}"
        if [[ -f "${path}" ]]; then
            _out+=("${path}")
        fi
    done
}

remove_legacy_wrappers() {
    local -a legacy_paths=()

    find_legacy_wrappers legacy_paths
    if [[ ${#legacy_paths[@]} -eq 0 ]]; then
        return 0
    fi

    print_section "Legacy script cleanup (bin/)"
    echo "Legacy script names (old naming):"
    for path in "${legacy_paths[@]}"; do
        echo "  ${path}"
    done

    read_yes_no_quit "Remove these legacy scripts? [y/N/q]: "
    case "${REPLY}" in
        y)
            rm -f "${legacy_paths[@]}"
            echo "Removed ${#legacy_paths[@]} legacy script(s)."
            ;;
        q)
            echo "Quit."
            exit 0
            ;;
        *)
            echo "Kept legacy scripts."
            ;;
    esac
}

find_legacy_scripts_dir() {
    local -n _out="$1"
    local name path

    _out=()
    [[ -d "${LEGACY_SCRIPTS_DIR}" ]] || return 0

    for name in "${LEGACY_WRAPPER_NAMES[@]}"; do
        path="${LEGACY_SCRIPTS_DIR}/${name}"
        if [[ -f "${path}" ]]; then
            _out+=("${path}")
        fi
    done
}

remove_legacy_scripts_dir() {
    local -a legacy_paths=()

    find_legacy_scripts_dir legacy_paths
    if [[ ${#legacy_paths[@]} -eq 0 ]]; then
        return 0
    fi

    print_section "Obsolete scripts in ${LEGACY_SCRIPTS_DIR}"
    echo "Old Polish-era pipeline copies (English scripts are in ${BIN_DIR}):"
    for path in "${legacy_paths[@]}"; do
        echo "  ${path}"
    done
    echo
    echo "Do not run these — use: ${BIN_DIR}/economist-0-runme.sh"

    read_yes_no_quit "Remove obsolete scripts from ${LEGACY_SCRIPTS_DIR}? [y/N/q]: "
    case "${REPLY}" in
        y)
            rm -f "${legacy_paths[@]}"
            echo "Removed ${#legacy_paths[@]} obsolete script(s) from ${LEGACY_SCRIPTS_DIR}."
            ;;
        q)
            echo "Quit."
            exit 0
            ;;
        *)
            echo "Kept obsolete scripts in ${LEGACY_SCRIPTS_DIR}."
            ;;
    esac
}

check_config_permissions() {
    local conf_file="$1"
    local perms

    perms="$(stat -c '%a' "${conf_file}")"
    if [[ "${perms}" == "600" ]]; then
        echo "  permissions: 600 (ok)"
        return 0
    fi

    echo "  permissions: ${perms} (expected 600)" >&2
    echo "  Fix with: chmod 600 ${conf_file}" >&2

    if (( ASSUME_YES )); then
        chmod 600 "${conf_file}"
        echo "  permissions: 600 (fixed, --yes)"
        return 0
    fi

    read_yes_no_quit "Fix permissions now with chmod 600? [y/N/q]: "
    case "${REPLY}" in
        y)
            chmod 600 "${conf_file}"
            echo "  permissions: 600 (fixed)"
            ;;
        q)
            echo "Quit."
            exit 0
            ;;
        *)
            echo "Installation cancelled: config file must be mode 600." >&2
            exit 1
            ;;
    esac
}

describe_config_plan() {
    if [[ -f "${CONF_FILE}" ]]; then
        echo "  installed:"
        print_aligned_config_path "current" "${CONF_FILE}"
        if [[ -f "${PRIVATE_CONF}" ]]; then
            echo "  If you proceed, the installer may offer to replace it from"
            echo "  your private repo (${CONFIG_REPLACE_TIMEOUT}s timeout, default no):"
            print_aligned_config_path "private" "${PRIVATE_CONF}"
        fi
        check_config_permissions "${CONF_FILE}"
        return
    fi

    if [[ -f "${PRIVATE_CONF}" ]]; then
        echo "  will install:"
        print_aligned_config_path "target" "${CONF_FILE}"
        echo "  from:"
        print_aligned_config_path "private" "${PRIVATE_CONF}"
        check_config_permissions "${PRIVATE_CONF}"
        return
    fi

    if [[ -f "${LOCAL_CONF}" ]]; then
        echo "  will install:"
        print_aligned_config_path "target" "${CONF_FILE}"
        echo "  from:"
        print_aligned_config_path "local" "${LOCAL_CONF}"
        check_config_permissions "${LOCAL_CONF}"
        return
    fi

    echo "  No config found. A starter file will be created from economist.conf.example."
    echo "  You must edit it before running the pipeline (RSS URL, paths, etc.)."
    echo "  will create:"
    print_aligned_config_path "target" "${CONF_FILE}"
    if [[ -f "${EXAMPLE_CONF}" ]]; then
        echo "  from:"
        print_aligned_config_path "example" "${EXAMPLE_CONF}"
    fi
}

install_config_file() {
    local source=""

    mkdir -p "${CONF_DIR}"

    if [[ -f "${CONF_FILE}" ]]; then
        check_config_permissions "${CONF_FILE}"

        if [[ -f "${PRIVATE_CONF}" ]]; then
            print_config_replace_offer
            read_yes_no_quit "Replace installed config with private repo copy? [y/N/q]: " "${CONFIG_REPLACE_TIMEOUT}" 0
            case "${REPLY}" in
                y)
                    check_config_permissions "${PRIVATE_CONF}"
                    cp "${PRIVATE_CONF}" "${CONF_FILE}"
                    chmod 600 "${CONF_FILE}"
                    echo "Replaced config:"
                    print_aligned_config_path "current" "${CONF_FILE}"
                    check_config_permissions "${CONF_FILE}"
                    ;;
                q)
                    echo "Quit."
                    exit 0
                    ;;
                *)
                    echo "Kept existing config:"
                    print_aligned_config_path "current" "${CONF_FILE}"
                    ;;
            esac
        fi
        return
    fi

    if [[ -f "${PRIVATE_CONF}" ]]; then
        source="${PRIVATE_CONF}"
    elif [[ -f "${LOCAL_CONF}" ]]; then
        source="${LOCAL_CONF}"
    fi

    if [[ -z "${source}" ]]; then
        if [[ -f "${EXAMPLE_CONF}" ]]; then
            cp "${EXAMPLE_CONF}" "${CONF_FILE}"
            chmod 600 "${CONF_FILE}"
            echo
            echo "Created starter config — edit it before running the pipeline:"
            print_aligned_config_path "current" "${CONF_FILE}"
            echo "Required: set ECONOMIST_RSS_URL (and adjust paths if needed)."
            check_config_permissions "${CONF_FILE}"
            return
        fi

        echo "Config not installed: no source file found." >&2
        echo "Create ${CONF_FILE} before running the pipeline." >&2
        return
    fi

    cp "${source}" "${CONF_FILE}"
    chmod 600 "${CONF_FILE}"
    echo "Installed config:"
    print_aligned_config_path "current" "${CONF_FILE}"
    check_config_permissions "${CONF_FILE}"
}

install_bin_scripts() {
    local script_path name target

    print_section "Installing scripts"
    mkdir -p "${BIN_DIR}"

    for script_path in "${SCRIPT_PATHS[@]}"; do
        name="$(basename "${script_path}")"
        target="${BIN_DIR}/${name}"
        cp "${script_path}" "${target}"
        chmod 755 "${target}"
        echo "Installed ${target}"
    done

    cp "${SCRIPTS_DIR}/_load-config.sh" "${BIN_DIR}/_load-config.sh"
    chmod 755 "${BIN_DIR}/_load-config.sh"
    echo "Installed ${BIN_DIR}/_load-config.sh"

    cp "${SCRIPTS_DIR}/_economist-run-control.sh" "${BIN_DIR}/_economist-run-control.sh"
    chmod 755 "${BIN_DIR}/_economist-run-control.sh"
    echo "Installed ${BIN_DIR}/_economist-run-control.sh"
    rm -f "${BIN_DIR}/_economist-script-header.sh"
}

print_crontab_hint() {
    print_section "Crontab hint — add with: crontab -e"
    resolve_flock_for_cron
    build_economist_cron_paths
    echo_economist_cron_block "hint"
    echo "${SECTION_RULE}"
    echo
}

cron_line_core_content() {
    local line="$1"

    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    if [[ "${line}" =~ ^[[:space:]]*# ]]; then
        line="${line#\#}"
        line="${line#"${line%%[![:space:]]*}"}"
    fi
    printf '%s' "${line}"
}

cron_line_is_obsolete() {
    local core="$1"

    core="$(cron_line_core_content "$1")"
    [[ -n "${core}" ]] || return 1

    if [[ "${core}" == *"economist-0-runme.sh"* ]]; then
        return 1
    fi

    if [[ "${core}" == *"/root/scripts/"* ]] && [[ "${core}" == *[Ee]conomist* ]]; then
        return 0
    fi
    if [[ "${core}" == *"0-economist-runme"* ]]; then
        return 0
    fi
    if [[ "${core}" == *"1-economist-sciagnij"* ]]; then
        return 0
    fi
    if [[ "${core}" == *"2-economist-obrob"* ]]; then
        return 0
    fi
    if [[ "${core}" == *"3-zmien-szybkosc-podbij-glosnosc"* ]]; then
        return 0
    fi
    if [[ "${core}" == *"4-wszystko-obrobione"* ]]; then
        return 0
    fi
    if [[ "${core}" == *"/bin/0-economist-runme"* ]]; then
        return 0
    fi
    if [[ "${core}" == *"/bin/1-economist-download"* ]]; then
        return 0
    fi
    if [[ "${core}" == *"/bin/2-economist-process-edition"* ]]; then
        return 0
    fi
    if [[ "${core}" == *"/bin/3-economist-speedup-loudness"* ]]; then
        return 0
    fi
    if [[ "${core}" == *"/bin/4-economist-move-results"* ]]; then
        return 0
    fi
    if [[ "${core}" == *"/bin/economist-runme.sh"* ]]; then
        return 0
    fi
    if [[ "${core}" == *"/bin/economist-download.sh"* ]]; then
        return 0
    fi

    return 1
}

build_economist_cron_paths() {
    ECON_CRON_RUN_SCRIPT="${BIN_DIR}/economist-0-runme.sh"
    ECON_CRON_LOCK_FILE="${BASE_DIR}/var/lock/economist-runme.lock"
    ECON_CRON_LOG_FILE="${BASE_DIR}/var/log/economist-runme.log"
    ECON_CRON_BASE_DIR="/worek/economist/theEconomist"
    ECON_CRON_OUTPUT_DIR="${ECON_CRON_BASE_DIR}/_obrobione"
    ECON_CRON_ARCHIVE_DIR="${ECON_CRON_BASE_DIR}/archive"

    if [[ -f "${CONF_FILE}" ]]; then
        # shellcheck disable=SC1090
        source "${CONF_FILE}" 2>/dev/null || true
        ECON_CRON_BASE_DIR="${ECONOMIST_BASE_DIR:-${ECON_CRON_BASE_DIR}}"
        ECON_CRON_OUTPUT_DIR="${ECONOMIST_OUTPUT_DIR:-${ECON_CRON_OUTPUT_DIR}}"
        ECON_CRON_ARCHIVE_DIR="${ECON_CRON_BASE_DIR}/archive"
    fi

    mkdir -p "${BASE_DIR}/var/lock" "${BASE_DIR}/var/log" 2>/dev/null || true

    if (( USE_FLOCK_IN_CRON )); then
        ECON_CRON_RUN_CMD="${FLOCK_BIN} -n \${ECONOMIST_LOCK} \${ECONOMIST_RUN}"
        ECON_CRON_LOCK_VAR="ECONOMIST_LOCK=${ECON_CRON_LOCK_FILE}"
        ECON_CRON_FLOCK_NOTE="# Use a separate lock file (\${ECONOMIST_LOCK}) — not the script path."
    else
        ECON_CRON_RUN_CMD="\${ECONOMIST_RUN}"
        ECON_CRON_LOCK_VAR="# ECONOMIST_LOCK=  (flock not installed — cron runs without overlap lock)"
        ECON_CRON_FLOCK_NOTE="# flock not installed — install util-linux for overlap protection."
    fi
}

echo_economist_cron_block() {
    local mode="${1:-hint}"
    local header_comment=""

    if [[ "${mode}" == "migrate" ]]; then
        header_comment="# Economist weekly audio — new cron block added by install.sh on $(date '+%Y.%m.%d %H:%M:%S')"
    else
        header_comment="# Economist weekly audio — paths for this install"
    fi

    cat <<EOF
${header_comment}
# Full example: ${REPO_ROOT}/crontab.example

PROFILE_LOCATION_DIR=${BASE_DIR}
ECONOMIST_BIN=${BIN_DIR}
ECONOMIST_RUN=${ECON_CRON_RUN_SCRIPT}
${ECON_CRON_LOCK_VAR}
ECONOMIST_LOG=${ECON_CRON_LOG_FILE}
ECONOMIST_OUTPUT=${ECON_CRON_OUTPUT_DIR}
ECONOMIST_ARCHIVE=${ECON_CRON_ARCHIVE_DIR}

# Thursday evening (edition usually available)
30 21-23 * * 4 ${ECON_CRON_RUN_CMD} >>\${ECONOMIST_LOG} 2>&1

# Retry early morning and daytime (Mon–Wed, Fri–Sun)
15 0-4  * * 0-3,5,6 ${ECON_CRON_RUN_CMD} >>\${ECONOMIST_LOG} 2>&1
15 7-22 * * 0-3,5,6 ${ECON_CRON_RUN_CMD} >>\${ECONOMIST_LOG} 2>&1

# Move processed editions to archive (Thursday night)
0 2 * * 4 /bin/mv -f \${ECONOMIST_OUTPUT}/[0-9]* \${ECONOMIST_ARCHIVE}/ 2>/dev/null

# Remove empty output subdirs (Wednesday)
0 4 * * 3 /usr/bin/find \${ECONOMIST_OUTPUT} -mindepth 1 -maxdepth 1 -type d -empty -delete

${ECON_CRON_FLOCK_NOTE}
EOF
}

offer_crontab_obsolete_migration() {
    local current_crontab="" tmp="" stamp="" line=""
    local -a kept_lines=() obsolete_lines=()
    local has_new_cron=0

    if ! command -v crontab >/dev/null 2>&1; then
        echo "crontab command not found — skipping cron migration." >&2
        return 0
    fi

    current_crontab="$(crontab -l 2>/dev/null || true)"
    if [[ -z "${current_crontab}" ]]; then
        return 0
    fi

    while IFS= read -r line || [[ -n "${line}" ]]; do
        if cron_line_is_obsolete "${line}"; then
            obsolete_lines+=("${line}")
        else
            kept_lines+=("${line}")
        fi
    done <<< "${current_crontab}"

    if [[ ${#obsolete_lines[@]} -eq 0 ]]; then
        return 0
    fi

    if [[ "${current_crontab}" == *"${BIN_DIR}/economist-0-runme.sh"* ]]; then
        has_new_cron=1
    fi

    print_section "Obsolete economist cron entries"
    echo "Found ${#obsolete_lines[@]} obsolete line(s) in your crontab:"
    for line in "${obsolete_lines[@]}"; do
        echo "  ${line}"
    done
    echo
    if (( has_new_cron )); then
        echo "Your crontab already contains ${BIN_DIR}/economist-0-runme.sh"
        echo "Obsolete lines will be commented out together; no new block will be added."
    else
        echo "Obsolete lines will be commented out and replaced with a new economist block."
    fi
    echo

    read_yes_no_quit "Update crontab (comment obsolete lines, add new block if needed)? [y/N/q]: " "${PROMPT_TIMEOUT}" 0
    case "${REPLY}" in
        y) ;;
        q)
            echo "Quit."
            exit 0
            ;;
        *)
            echo "Kept crontab unchanged."
            return 0
            ;;
    esac

    build_economist_cron_paths
    stamp="$(date '+%Y.%m.%d %H:%M:%S')"
    tmp="$(mktemp)"

    {
        if [[ ${#kept_lines[@]} -gt 0 ]]; then
            printf '%s\n' "${kept_lines[@]}"
            echo
        fi
        echo "# --- economist-weekly-audio: obsolete cron lines commented out by install.sh on ${stamp} ---"
        for line in "${obsolete_lines[@]}"; do
            if [[ "${line}" =~ ^[[:space:]]*# ]]; then
                printf '%s\n' "${line}"
            else
                printf '# %s\n' "${line}"
            fi
        done
        echo "# --- end obsolete economist cron lines ---"
        echo
        if (( has_new_cron == 0 )); then
            echo_economist_cron_block migrate
        fi
    } > "${tmp}"

    if crontab "${tmp}"; then
        echo "Crontab updated."
        echo

        print_section "Crontab — old section (now commented out)"
        echo "# --- economist-weekly-audio: obsolete cron lines commented out by install.sh on ${stamp} ---"
        for line in "${obsolete_lines[@]}"; do
            if [[ "${line}" =~ ^[[:space:]]*# ]]; then
                echo "${line}"
            else
                echo "# ${line}"
            fi
        done
        echo "# --- end obsolete economist cron lines ---"
        echo

        if (( has_new_cron == 0 )); then
            print_section "Crontab — new section added"
            echo_economist_cron_block migrate
        else
            print_section "Crontab — new section"
            echo "No new block added — ${BIN_DIR}/economist-0-runme.sh is already in your crontab."
        fi
        echo "${SECTION_RULE}"
        echo
    else
        echo "Failed to update crontab. Temp file left at: ${tmp}" >&2
        return 1
    fi

    rm -f "${tmp}"
}

print_section "Economist weekly audio — install"
echo "Base directory:   ${BASE_DIR}"
echo "Repository:       ${REPO_ROOT}"
echo "Bin directory:    ${BIN_DIR}"
echo "Config directory: ${CONF_DIR}"
echo
print_section "Config plan"
describe_config_plan
print_section "Scripts to install"
echo "Target directory: ${BIN_DIR}"
for script_path in "${SCRIPT_PATHS[@]}"; do
    echo "  $(basename "${script_path}")"
done
echo "  _load-config.sh"

legacy_preview=()
find_legacy_wrappers legacy_preview
legacy_scripts_preview=()
find_legacy_scripts_dir legacy_scripts_preview
if [[ ${#legacy_preview[@]} -gt 0 ]]; then
    echo
    echo "Legacy script names in bin/ (will offer removal after install):"
    for path in "${legacy_preview[@]}"; do
        echo "  ${path}"
    done
fi
if [[ ${#legacy_scripts_preview[@]} -gt 0 ]]; then
    echo
    echo "Obsolete scripts in ${LEGACY_SCRIPTS_DIR} (Polish-era copies; will offer removal):"
    for path in "${legacy_scripts_preview[@]}"; do
        echo "  ${path}"
    done
fi
echo

case ":${PATH}:" in
    *:"${BIN_DIR}":*) ;;
    *)
        echo "Note: ${BIN_DIR} is not in your PATH."
        echo "Add this to your shell profile if needed:"
        echo "  export PATH=\"${BIN_DIR}:\${PATH}\""
        echo
        ;;
esac

read_yes_no_quit "Proceed with installation? [y/N/q]: "
case "${REPLY}" in
    y) ;;
    q)
        echo "Quit."
        exit 0
        ;;
    *)
        echo "Installation cancelled."
        exit 0
        ;;
esac

install_config_file

install_bin_scripts

remove_legacy_wrappers

remove_legacy_scripts_dir

print_section "Install complete"
echo "Run the pipeline with:"
echo "  ${BIN_DIR}/economist-0-runme.sh"
echo

print_crontab_hint
offer_crontab_obsolete_migration
