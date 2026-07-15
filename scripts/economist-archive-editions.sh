#!/usr/bin/env bash
# 2026.07.15 - v. 1.0 - move output editions to archive, replacing existing copies
# Moves processed edition folders from ECONOMIST_OUTPUT_DIR to ECONOMIST_ARCHIVE_DIR.
# If the same edition name already exists in archive, it is removed first.

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
economist_set_run_step archive

echo

output_dir="${ECONOMIST_OUTPUT_DIR}"
archive_dir="${ECONOMIST_ARCHIVE_DIR}"
edition_dir="" edition_name="" target=""

mkdir -p "${archive_dir}" 2>/dev/null || true

shopt -s nullglob
for edition_dir in "${output_dir}"/[0-9]*; do
    [[ -d "${edition_dir}" ]] || continue

    edition_name="$(basename "${edition_dir}")"
    target="${archive_dir}/${edition_name}"

    if [[ -e "${target}" ]]; then
        echo "Replacing existing archive copy: ${target}"
        rm -rf "${target}"
    fi

    echo "Archiving: ${edition_dir} -> ${archive_dir}/"
    mv -f "${edition_dir}" "${archive_dir}/"
done
shopt -u nullglob

economist_chown_if_set "${archive_dir}"

economist_step_exit 0
