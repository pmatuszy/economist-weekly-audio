#!/usr/bin/env bash
# 2026.07.15 - v. 1.3 - source github-bin _script_header.sh directly (drop wrapper)
# v. 1.0 - 2026.07.15 - renamed to economist-4-move-results.sh
# v. 0.9 - 2026.07.15 - restored numbered name 4-economist-move-results.sh
# v. 0.7 - 2026.07.15 - added script description header
# v. 0.5 - 2026.06.19 - runtime messages translated to English
# v. 0.4 - 2026.06.19 - changelog comments translated to English
# v. 0.3 - 2026.06.19 - renamed from 4-wszystko-obrobione-przenies-wyniki.sh
# v. 0.2 - 2026.06.16 - paths from economist.local.conf
# v. 0.1 - 2021.04.19 - initial release
# Moves processed files from the work directory to the output directory.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_economist-run-control.sh
source "${SCRIPT_DIR}/_economist-run-control.sh"
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

# shellcheck source=_load-config.sh
source "${SCRIPT_DIR}/_load-config.sh"
load_economist_config

economist_run_control_init step
economist_install_run_traps
economist_set_run_step move

echo

work_dir="${ECONOMIST_WORK_DIR}"
output_dir="${ECONOMIST_OUTPUT_DIR}"

mv -v "${work_dir}"/* "${output_dir}"

economist_step_exit 0
