# shellcheck shell=bash
# 2026.07.15 - v. 1.0 - shared _script_header.sh wrapper for economist scripts
# _economist-script-header.sh
#
# Source from a pipeline/install script (not from a function) to show the github-bin
# version banner (figlet + boxes on a tty; SCRIPT_VERSION box in cron logs).
#
#   source "${SCRIPT_DIR}/_economist-script-header.sh" [NO_STARTUP_DELAY ...]

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Source this file; do not execute it directly." >&2
    exit 1
fi

_economist_header_extra=("$@")
if [[ ${#_economist_header_extra[@]} -eq 0 ]] && ! tty >/dev/null 2>&1; then
    _economist_header_extra=(NO_STARTUP_DELAY)
fi

_economist_script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
_economist_header_file=""
for _candidate in \
    "${_economist_script_dir}/_script_header.sh" \
    "/root/bin/_script_header.sh" \
    "${profile_location_dir:-$HOME}/bin/_script_header.sh"
do
    if [[ -f "${_candidate}" ]]; then
        _economist_header_file="${_candidate}"
        break
    fi
done

if [[ -n "${_economist_header_file}" ]]; then
    # shellcheck source=/dev/null
    . "${_economist_header_file}" "${_economist_header_extra[@]}"
    if (( ! script_is_run_interactively )); then
        echo "${SCRIPT_VERSION}"
        echo
    fi
else
    echo "Warning: _script_header.sh not found — skipping version banner." >&2
    echo "Install github-bin scripts into bin/ (expected: ${_economist_script_dir}/_script_header.sh)." >&2
fi

unset -v _economist_header_extra _economist_script_dir _economist_header_file _candidate
