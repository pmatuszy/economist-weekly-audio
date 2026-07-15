#!/usr/bin/env bash
# v. 1.1 - 2026.07.15 - use profile_location_dir when set, else HOME
# v. 1.0 - 2026.07.15 - interactive install of wrappers into ~/bin from ~/github clone
# Interactive install: wrapper scripts into ${profile_location_dir:-$HOME}/bin.
# Wrappers exec pipeline scripts from this repo clone.

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

Expected first-time layout:
  \${profile_location_dir:-\$HOME}/github/${REPO_NAME}/                 # this repo
  \${profile_location_dir:-\$HOME}/github/${REPO_NAME}-private/         # optional secrets repo (sibling)
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

private_conf="${REPO_ROOT}/../${REPO_NAME}-private/economist.local.conf"
local_conf="${REPO_ROOT}/economist.local.conf"

echo "Economist weekly audio — install"
echo
echo "Base directory:  ${BASE_DIR}"
echo "Repository:      ${REPO_ROOT}"
echo "Bin directory:   ${BIN_DIR}"
echo
echo "Config lookup:"
if [[ -f "${private_conf}" ]]; then
    echo "  found: ${private_conf}"
elif [[ -f "${local_conf}" ]]; then
    echo "  found: ${local_conf}"
else
    echo "  not found yet"
    echo "  expected sibling: ${private_conf}"
    echo "  or local copy:    ${local_conf}"
fi
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
