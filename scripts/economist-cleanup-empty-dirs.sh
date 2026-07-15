#!/usr/bin/env bash
# 2026.07.15 - v. 1.0 - remove empty edition subdirs under ECONOMIST_OUTPUT_DIR
# Safe cron helper: paths come from economist.local.conf, not unexpanded shell variables.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_load-config.sh
source "${SCRIPT_DIR}/_load-config.sh"
_economist_header_extra=()
if ! tty >/dev/null 2>&1; then
    _economist_header_extra=(NO_STARTUP_DELAY)
fi
_economist_header_file="$(economist_find_script_header_file)" || true
if [[ -n "${_economist_header_file}" ]]; then
    # shellcheck source=/dev/null
    . "${_economist_header_file}" ${_economist_header_extra[@]+"${_economist_header_extra[@]}"}
    if (( ! script_is_run_interactively )); then
        echo "${SCRIPT_VERSION}"
        echo
    fi
else
    echo "Warning: _script_header.sh not found — install github-bin into ${profile_location_dir:-$HOME}/bin/." >&2
fi
unset _economist_header_file _economist_header_extra

load_economist_config

economist_run_control_init step
economist_install_run_traps
economist_set_run_step cleanup_empty_dirs

echo

output_dir="${ECONOMIST_OUTPUT_DIR:-}"

if [[ -z "${output_dir}" ]]; then
    echo "ECONOMIST_OUTPUT_DIR is not set — refusing to run find." >&2
    economist_step_exit 1
fi

if [[ ! -d "${output_dir}" ]]; then
    echo "ECONOMIST_OUTPUT_DIR does not exist: ${output_dir}" >&2
    economist_step_exit 1
fi

echo "Removing empty subdirectories under: ${output_dir}"
find "${output_dir}" -mindepth 1 -maxdepth 1 -type d -empty -delete

economist_step_exit 0
