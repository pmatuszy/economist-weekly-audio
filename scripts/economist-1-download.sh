#!/bin/bash
# v. 20260716.231500 - map edition date via RSS title cover date, not release Saturday
# v. 20260716.162604 - download weekly Economist MP3 from personal RSS feed
# Downloads the weekly Economist MP3 from the personal RSS feed.

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

set -euo pipefail
LC_ALL=C

load_economist_config
require_economist_rss_url

economist_run_control_init step
economist_install_run_traps
economist_set_run_step download

command -v xmllint >/dev/null 2>&1 || echo "[INFO] Tip: 'xmllint' not found. Install: \
Debian/Ubuntu: 'apt install libxml2-utils' | RHEL/CentOS: 'yum install libxml2' | Alpine: 'apk add libxml2-utils'"

echo

work_dir="${ECONOMIST_WORK_DIR}"

mkdir -p "${work_dir}" 2>/dev/null
cd "${work_dir}"

exit_code=$?
if (( exit_code != 0 )); then
   echo "Something went wrong — cannot change to directory \"${work_dir}\" (exit code ${exit_code})"
   economist_step_exit "${exit_code}"
fi

pwd

if [[ -f "${work_dir}/economist.mp3" ]]; then
  echo
  echo "File ${work_dir}/economist.mp3 already exists — not downloading again"
  echo "Also removing empty work directory ${work_dir}"
  echo "STOPPING"
  echo
  economist_step_exit 1
fi

cd "${work_dir}"

rm -f economist.rss 2>/dev/null
echo "[INFO] Fetching RSS: ${ECONOMIST_RSS_URL}"
curl -fsSL "${ECONOMIST_RSS_URL}" -o economist.rss
echo "[INFO] Saved RSS to: $(pwd)/economist.rss"

weeks_position_from_date() {
  local iso="$1" pos=""

  if [[ ! "$iso" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || [[ "$(date -d "$iso" +%F 2>/dev/null)" != "$iso" ]]; then
    echo "Expected YYYY-MM-DD (e.g. 2025-08-16)" >&2
    return 2
  fi

  echo "[INFO] Input date (cover date): $iso" >&2
  pos="$(economist_rss_position_for_edition_date economist.rss "$iso")" || {
    echo "No feed item matches edition cover date ${iso} (checked RSS titles)." >&2
    return 3
  }
  echo "[INFO] RSS position for ${iso}: ${pos}" >&2
  echo "$pos"
}

download_url=""

if [[ $# -eq 0 ]]; then
  echo "[INFO] No date argument — using latest item (position 1, first enclosure)."
  download_url="$(grep -oP '<enclosure url="\K[^"]+' economist.rss | head -n 1 || true)"
else
  iso="$1"
  pos="$(weeks_position_from_date "$iso")" || { echo "[INFO] Failed to compute RSS position for date: $iso"; rm -f economist.rss; economist_step_exit 1; }

  item_count=0
  if command -v xmllint >/dev/null 2>&1; then
    item_count_raw="$(xmllint --xpath 'count(//item)' economist.rss 2>/dev/null || echo 0)"
    item_count="${item_count_raw%.*}"
    echo "[INFO] Item count (xmllint): $item_count"
  else
    echo "[INFO] xmllint not found — using grep fallback." >&2
  fi

  if [[ "$item_count" -eq 0 ]]; then
    item_count="$(grep -oP '<enclosure url="\K[^"]+' economist.rss | wc -l | awk '{print $1}')"
    echo "[INFO] Item count (grep): $item_count"
  fi

  if [[ "$pos" -le 0 || "$pos" -gt "$item_count" ]]; then
    echo "No feed item at position $pos (feed has $item_count items)." >&2
    rm -f economist.rss
    economist_step_exit 2
  fi

  if command -v xmllint >/dev/null 2>&1 && [[ "$item_count" -gt 0 ]]; then
    download_url="$(xmllint --xpath "string((//item)[$pos]/enclosure/@url)" economist.rss 2>/dev/null || true)"
    [[ -n "$download_url" ]] && echo "[INFO] MP3 URL (xmllint, pos. $pos): $download_url"
  fi

  if [[ -z "$download_url" ]]; then
    download_url="$(grep -oP '<enclosure url="\K[^"]+' economist.rss | sed -n "${pos}p" || true)"
    echo "[INFO] MP3 URL (grep fallback, pos. $pos): ${download_url:-<empty>}"
  fi
fi

if [[ -z "${download_url}" ]]; then
  echo "No download URL found in economist.rss." >&2
  rm -f economist.rss
  economist_step_exit 1
fi

rm -f economist.rss

echo
echo "Downloading $(pwd)/economist.mp3"
echo "[INFO] Source: $download_url"
echo

wget --max-redirect=5 "${download_url}" -O economist.mp3 2>/dev/null

if [[ ! -s economist.mp3 ]]; then
  echo "economist.mp3 is missing or empty. Cleaning up work directory."
  cd /tmp || economist_step_exit 1
  rmdir "${work_dir}"
  economist_step_exit 1
fi

echo "[INFO] OK — downloaded economist.mp3 ($(du -h economist.mp3 | awk '{print $1}'))"
economist_step_exit 0
