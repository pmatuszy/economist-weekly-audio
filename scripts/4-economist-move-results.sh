#!/usr/bin/env bash
# v. 0.9 - 2026.07.15 - restored numbered name 4-economist-move-results.sh
# v. 0.8 - 2026.07.15 - renamed from 4-economist-move-results.sh
# v. 0.7 - 2026.07.15 - added script description header
# v. 0.5 - 2026.06.19 - runtime messages translated to English
# v. 0.4 - 2026.06.19 - changelog comments translated to English
# v. 0.3 - 2026.06.19 - renamed from 4-wszystko-obrobione-przenies-wyniki.sh
# v. 0.2 - 2026.06.16 - paths from economist.local.conf
# v. 0.1 - 2021.04.19 - initial release
# Moves processed files from the work directory to the output directory.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_load-config.sh
source "${SCRIPT_DIR}/_load-config.sh"
load_economist_config

echo "---- Script start: $0 ($(date '+%Y.%m.%d %H:%M:%S'))"

work_dir="${ECONOMIST_WORK_DIR}"
output_dir="${ECONOMIST_OUTPUT_DIR}"

mv -v "${work_dir}"/* "${output_dir}"

echo "---- Script end:   $0 ($(date '+%Y.%m.%d %H:%M:%S'))"
