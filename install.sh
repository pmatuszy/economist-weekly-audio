#!/usr/bin/env bash
# v. 1.3 - 2026.07.15 - install economist.local.conf into conf/ beside bin/
# v. 1.2 - 2026.07.15 - check private config file permissions are 600
# v. 1.1 - 2026.07.15 - use profile_location_dir when set, else HOME
# v. 1.0 - 2026.07.15 - interactive install of wrappers into ~/bin from ~/github clone
# Interactive install: wrappers into bin/, config into conf/ (sibling directories).
# Copies economist.local.conf from the private repo when needed; requires mode 600.

set -euo pipefail

BASE_DIR="${profile_location_dir:-$HOME}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_NAME="$(basename "${REPO_ROOT}")"
SCRIPTS_DIR="${REPO_ROOT}/scripts"
BIN_DIR="${BASE_DIR}/bin"
DO_PULL=0
ASSUME_YES=0

usage() {
    cat <<EOF
Usage: install.sh [options]

Install pipeline scripts into a bin directory as small wrappers that run the
copy in this repository.

Expected layout:
  \${profile_location_dir:-\$HOME}/github/${REPO_NAME}/                 # this repo
  \${profile_location_dir:-\$HOME}/github/${REPO_NAME}-private/         # optional secrets source
  \${profile_location_dir:-\$HOME}/conf/economist.local.conf             # installed config (mode 600)
  \${profile_location_dir:-\$HOME}/bin/0-economist-runme.sh             # installed wrappers

Options:
  --bin-dir PATH   Target bin directory (default: \${profile_location_dir:-\$HOME}/bin)
  --pull           Run "git pull --ff-only" in this repo before installing
  -y, --yes        Install without confirmation prompt
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

CONF_DIR="$(dirname "${BIN_DIR}")/conf"
CONF_FILE="${CONF_DIR}/economist.local.conf"
PRIVATE_CONF="${REPO_ROOT}/../${REPO_NAME}-private/economist.local.conf"
LOCAL_CONF="${REPO_ROOT}/economist.local.conf"

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

mapfile -t SCRIPT_PATHS < <(find "${SCRIPTS_DIR}" -maxdepth 1 -type f -name '*.sh' ! -name '_*.sh' | sort)

if [[ ${#SCRIPT_PATHS[@]} -eq 0 ]]; then
    echo "No installable scripts found in ${SCRIPTS_DIR}" >&2
    exit 1
fi

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
        echo "Refusing to install: fix config permissions first." >&2
        exit 1
    fi

    read -r -p "Fix permissions now with chmod 600? [y/N] " fix_answer
    case "${fix_answer}" in
        y|Y|yes|YES)
            chmod 600 "${conf_file}"
            echo "  permissions: 600 (fixed)"
            ;;
        *)
            echo "Installation cancelled: config file must be mode 600." >&2
            exit 1
            ;;
    esac
}

describe_config_plan() {
    if [[ -f "${CONF_FILE}" ]]; then
        echo "  target: ${CONF_FILE} (already exists)"
        check_config_permissions "${CONF_FILE}"
        return
    fi

    if [[ -f "${PRIVATE_CONF}" ]]; then
        echo "  target: ${CONF_FILE} (will copy from ${PRIVATE_CONF})"
        check_config_permissions "${PRIVATE_CONF}"
        return
    fi

    if [[ -f "${LOCAL_CONF}" ]]; then
        echo "  target: ${CONF_FILE} (will copy from ${LOCAL_CONF})"
        check_config_permissions "${LOCAL_CONF}"
        return
    fi

    echo "  target: ${CONF_FILE} (not available yet)"
    echo "  source not found:"
    echo "    ${PRIVATE_CONF}"
    echo "    ${LOCAL_CONF}"
}

install_config_file() {
    local source=""

    mkdir -p "${CONF_DIR}"

    if [[ -f "${CONF_FILE}" ]]; then
        echo "Config: ${CONF_FILE}"
        check_config_permissions "${CONF_FILE}"
        return
    fi

    if [[ -f "${PRIVATE_CONF}" ]]; then
        source="${PRIVATE_CONF}"
    elif [[ -f "${LOCAL_CONF}" ]]; then
        source="${LOCAL_CONF}"
    fi

    if [[ -z "${source}" ]]; then
        echo "Config not installed: no source file found." >&2
        echo "Create ${CONF_FILE} before running the pipeline." >&2
        return
    fi

    cp "${source}" "${CONF_FILE}"
    chmod 600 "${CONF_FILE}"
    echo "Installed config: ${CONF_FILE} (from ${source})"
    check_config_permissions "${CONF_FILE}"
}

echo "Economist weekly audio — install"
echo
echo "Base directory:   ${BASE_DIR}"
echo "Repository:       ${REPO_ROOT}"
echo "Bin directory:    ${BIN_DIR}"
echo "Config directory: ${CONF_DIR}"
echo
echo "Config plan:"
describe_config_plan
echo
echo "Wrappers to install:"
for script_path in "${SCRIPT_PATHS[@]}"; do
    echo "  ${BIN_DIR}/$(basename "${script_path}") -> ${script_path}"
done
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

if (( ! ASSUME_YES )); then
    read -r -p "Proceed with installation? [y/N] " answer
    case "${answer}" in
        y|Y|yes|YES) ;;
        *)
            echo "Installation cancelled."
            exit 0
            ;;
    esac
fi

install_config_file

mkdir -p "${BIN_DIR}"

for script_path in "${SCRIPT_PATHS[@]}"; do
    name="$(basename "${script_path}")"
    target="${BIN_DIR}/${name}"

    cat > "${target}" <<EOF
#!/usr/bin/env bash
exec "${script_path}" "\$@"
EOF
    chmod 755 "${target}"
    echo "Installed ${target}"
done

echo
echo "Done. Run the pipeline with:"
echo "  ${BIN_DIR}/0-economist-runme.sh"
