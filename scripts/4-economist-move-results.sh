#!/usr/bin/env bash
# v. 0.5 - 2026.06.19 - runtime messages translated to English
# v. 0.4 - 2026.06.19 - changelog comments translated to English
# v. 0.3 - 2026.06.19 - renamed from 4-wszystko-obrobione-przenies-wyniki.sh
# v. 0.2 - 2026.06.16 - paths from economist.local.conf
# v. 0.1 - 2021.04.19 - initial release

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_load-config.sh
source "${SCRIPT_DIR}/_load-config.sh"
load_economist_config

echo "---- Script start: $0 ($(date '+%Y.%m.%d %H:%M:%S'))"

kat_zrodlowy="${ECONOMIST_WORK_DIR}"
kat_wynikowy="${ECONOMIST_OUTPUT_DIR}"

mv -v "${kat_zrodlowy}"/* "${kat_wynikowy}"

echo "---- Script end:   $0 ($(date '+%Y.%m.%d %H:%M:%S'))"
