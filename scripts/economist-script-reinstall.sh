#!/usr/bin/env bash
# 2026.07.16 - v. 1.6 - ASCII-only version banner (no UTF-8 box-drawing)
# 2026.07.16 - v. 1.5 - interactive discard of dirty clone; align with -y behavior
# 2026.07.16 - v. 1.4 - do not chmod repo clone (keeps git pull clean)
# 2026.07.16 - v. 1.3 - discard local scripts/ edits before git pull (-y)
# 2026.07.15 - v. 1.2 - source github-bin _script_header.sh directly (drop wrapper)
# 2026.07.15 - v. 1.1 - _script_header.sh banner via _economist-script-header.sh
# 2026.07.15 - v. 1.0 - clone/pull economist repos under github/ and run install.sh
# economist-script-reinstall.sh
#
# Ensures ${profile_location_dir:-$HOME}/github/economist-weekly-audio (and private
# sibling) exist and are up to date, then runs install.sh to refresh bin/ and conf/.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_version_banner() {
    local ver=unknown date= line title verline width=60
    while IFS= read -r line; do
        if [[ "$line" =~ ^#\ ([0-9]{4}\.[0-9]{2}\.[0-9]{2})\ -\ v\.\ ([0-9]+(\.[0-9]+)*) ]]; then
            date="${BASH_REMATCH[1]}"
            ver="${BASH_REMATCH[2]}"
            break
        fi
    done < "$0"
    title="$(basename "$0")"
    if [[ -n "$date" ]]; then
        verline="Version: ${ver} (${date})"
    else
        verline="Version: ${ver}"
    fi
    printf '+%*s+\n' "$width" '' | tr ' ' '-'
    printf '| %-*.*s |\n' $((width - 2)) $((width - 2)) "$title"
    printf '| %-*.*s |\n' $((width - 2)) $((width - 2)) "$verline"
    printf '+%*s+\n' "$width" '' | tr ' ' '-'
}

show_help() {
    cat <<EOF
Usage: $(basename "$0") [-h|--help] [-v|--version] [-y|--yes] [--no_startup_delay]

Clone or update economist-weekly-audio (and private config repo) under
\${profile_location_dir:-\$HOME}/github/, then run install.sh.

Options:
  -h, --help           Show this help and exit.
  -v, --version        Print script version and exit.
  -y, --yes            Pass -y to install.sh (non-interactive install prompts).
  --no_startup_delay   Skip random startup delay from _script_header.sh.

Environment:
  profile_location_dir          Base directory (default: \$HOME)
  ECONOMIST_GITHUB_USER         GitHub user (default: pmatuszy)
  ECONOMIST_PUBLIC_REPO         Public clone path
  ECONOMIST_PRIVATE_REPO        Private clone path
  ECONOMIST_PUBLIC_GIT_URL      Public git remote URL
  ECONOMIST_PRIVATE_GIT_URL     Private git remote URL
EOF
}

HEADER_EXTRA_ARGS=()
ASSUME_YES=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help; exit 0 ;;
        -v|--version) print_version_banner; exit 0 ;;
        -y|--yes) ASSUME_YES=1; shift ;;
        --no_startup_delay|NO_STARTUP_DELAY)
            HEADER_EXTRA_ARGS+=(NO_STARTUP_DELAY)
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Try: $(basename "$0") --help" >&2
            exit 1
            ;;
    esac
done

if ! tty >/dev/null 2>&1; then
    HEADER_EXTRA_ARGS+=(NO_STARTUP_DELAY)
fi

# shellcheck source=_load-config.sh
source "${SCRIPT_DIR}/_load-config.sh"
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

BASE_DIR="${profile_location_dir:-$HOME}"
GITHUB_DIR="${BASE_DIR}/github"
BIN_DIR="${BASE_DIR}/bin"
GITHUB_USER="${ECONOMIST_GITHUB_USER:-pmatuszy}"
PUBLIC_REPO="${ECONOMIST_PUBLIC_REPO:-${GITHUB_DIR}/economist-weekly-audio}"
PRIVATE_REPO="${ECONOMIST_PRIVATE_REPO:-${GITHUB_DIR}/economist-weekly-audio-private}"
PUBLIC_GIT_URL="${ECONOMIST_PUBLIC_GIT_URL:-git@github.com:${GITHUB_USER}/economist-weekly-audio.git}"
PRIVATE_GIT_URL="${ECONOMIST_PRIVATE_GIT_URL:-git@github.com:${GITHUB_USER}/economist-weekly-audio-private.git}"

setup_git_ssh() {
    if [[ -f "${SCRIPT_DIR}/_git-economist-common.sh" ]]; then
        # shellcheck source=/dev/null
        . "${SCRIPT_DIR}/_git-economist-common.sh"
        git_economist_setup_ssh
        return 0
    fi
    if [[ -f "/root/bin/_git-economist-common.sh" ]]; then
        # shellcheck source=/dev/null
        . /root/bin/_git-economist-common.sh
        git_economist_setup_ssh
        return 0
    fi

    export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -i ${HOME}/.ssh/id_SSH_ed25519_20230207_OpenSSH}"
    if command -v keychain >/dev/null 2>&1; then
        eval keychain -q --nogui --nocolor --eval id_rsa id_ed25519 id_SSH_ed25519_20230207_OpenSSH 2>&1 || true
        if [[ -f "${HOME}/.keychain/${HOSTNAME}-sh" ]]; then
            # shellcheck source=/dev/null
            . "${HOME}/.keychain/${HOSTNAME}-sh"
        fi
    fi
}

economist_git_prepare_pull() {
    local dir="$1" assume_yes="${2:-0}" dirty="" answer=""

    [[ -d "${dir}/.git" ]] || return 0

    dirty="$(git -C "${dir}" status --porcelain -- scripts/ install.sh 2>/dev/null || true)"
    [[ -n "${dirty}" ]] || return 0

    if (( assume_yes )); then
        echo "Note: discarding local changes under scripts/ and install.sh before git pull."
        echo "      Edit /root/bin/ or push changes from your dev machine - not the server clone."
        git -C "${dir}" checkout -- scripts/ install.sh 2>/dev/null || true
        return 0
    fi

    if [[ ! -t 0 && ! -r /dev/tty ]]; then
        echo "Local changes would block git pull in ${dir}:" >&2
        git -C "${dir}" status --short -- scripts/ install.sh >&2
        echo "Run: economist-script-reinstall.sh -y" >&2
        return 1
    fi

    echo
    echo "Local changes in ${dir} would block git pull:"
    git -C "${dir}" status --short -- scripts/ install.sh
    echo "The server clone should match GitHub (edit /root/bin/, not the repo clone)."
    economist_read_tty_char "Discard local script changes and pull? [Y/n/q]: " answer 300
    case "${answer}" in
        n|N)
            echo "Cancelled - fix the clone or run with -y."
            return 1
            ;;
        q|Q)
            echo "Quit."
            exit 0
            ;;
        ''|y|Y)
            git -C "${dir}" checkout -- scripts/ install.sh 2>/dev/null || true
            return 0
            ;;
        *)
            git -C "${dir}" checkout -- scripts/ install.sh 2>/dev/null || true
            return 0
            ;;
    esac
}

sync_repo() {
    local dir="$1" url="$2" label="$3"
    local rc=0

    mkdir -p "$(dirname "${dir}")"

    if [[ ! -d "${dir}/.git" ]]; then
        echo
        echo "Cloning ${label}..."
        echo "  into: ${dir}"
        echo "  from: ${url}"
        git clone "${url}" "${dir}" || rc=$?
    else
        economist_git_prepare_pull "${dir}" "${ASSUME_YES}" || return 1
        echo
        echo "Pulling ${label}..."
        echo "  repo: ${dir}"
        git -C "${dir}" pull --ff-only || rc=$?
    fi

    if (( rc != 0 )); then
        echo "${label}: sync failed (exit ${rc})." >&2
        return "${rc}"
    fi
    return 0
}

confirm_reinstall() {
    local answer=""

    if (( ASSUME_YES )); then
        echo "Proceed with reinstall? [y/N/q]: y (--yes)"
        return 0
    fi

    echo
    echo "Reinstall economist scripts from GitHub?"
    echo "  public : ${PUBLIC_REPO}"
    echo "  private: ${PRIVATE_REPO}"
    echo "  bin    : ${BIN_DIR}"
    echo
    echo -n "Proceed? [y/N/q]: "
    read -t 300 -n 1 answer || answer=""
    echo
    answer="${answer//$'\r'/}"

    case "${answer}" in
        y|Y) return 0 ;;
        q|Q) echo "Quit."; exit 0 ;;
        *) echo "Cancelled."; exit 0 ;;
    esac
}

setup_git_ssh
confirm_reinstall

sync_repo "${PUBLIC_REPO}" "${PUBLIC_GIT_URL}" "economist-weekly-audio (public)" || exit $?

if ! sync_repo "${PRIVATE_REPO}" "${PRIVATE_GIT_URL}" "economist-weekly-audio-private"; then
    echo
    echo "Warning: private repo sync failed."
    echo "install.sh will still run; config may come from existing conf/ or economist.conf.example."
    echo
fi

install_args=(--bin-dir "${BIN_DIR}")
if (( ASSUME_YES )); then
    install_args+=(-y)
fi

echo
echo "Running ${PUBLIC_REPO}/install.sh ${install_args[*]}"
echo

bash "${PUBLIC_REPO}/install.sh" "${install_args[@]}"
exit $?
