#!/bin/bash
# 2026.07.15 - v. 3.5 - source github-bin _script_header.sh directly (drop wrapper)
# v. 3.2 - 2026.07.15 - renamed to economist-1-download.sh
# v. 3.1 - 2026.07.15 - restored numbered name 1-economist-download.sh
# v. 2.10 - 2026.07.15 - added script description header
# v. 2.8 - 2026.06.19 - runtime messages translated to English
# v. 2.7 - 2026.06.19 - changelog comments translated to English
# v. 2.6 - 2026.06.19 - renamed from 1-economist-sciagnij.sh
# v. 2.5 - 2026.06.16 - RSS URL from economist.local.conf (not in git)
# v. 2.4 - 2025.09.17 - auto-tip for xmllint + grep fallback when xmllint missing or returns 0
# v. 2.3 - 2025.09.17 - added echo/logging
# v. 2.2 - 2025.09.17 - optional YYYY-MM-DD selects n-th RSS item (xmllint); default is first enclosure
# Downloads the weekly Economist MP3 from the personal RSS feed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_economist-run-control.sh
source "${SCRIPT_DIR}/_economist-run-control.sh"
economist_source_script_header

set -euo pipefail
LC_ALL=C

# shellcheck source=_load-config.sh
source "${SCRIPT_DIR}/_load-config.sh"
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
  local iso="$1"

  if [[ ! "$iso" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || [[ "$(date -d "$iso" +%F 2>/dev/null)" != "$iso" ]]; then
    echo "Expected YYYY-MM-DD (e.g. 2025-08-16)" >&2
    return 2
  fi

  echo "[INFO] Input date: $iso" >&2
  local dow_in off_in target_sat
  dow_in=$(date -d "$iso" +%u)
  off_in=$(( (dow_in + 1) % 7 ))
  target_sat=$(date -d "$iso - $off_in days" +%F)
  echo "[INFO] Mapped Saturday (edition): $target_sat (dow=$dow_in, offset=$off_in)" >&2

  local dow_now off_now latest_sat
  dow_now=$(date +%u)
  off_now=$(( (dow_now + 1) % 7 ))
  latest_sat=$(date -d "today - $off_now days" +%F)
  echo "[INFO] Latest Saturday (reference): $latest_sat (dow_now=$dow_now, offset=$off_now)" >&2

  if (( $(date -d "$target_sat" +%s) > $(date -d "$latest_sat" +%s) )); then
    echo "Date is in the future vs. latest edition (${latest_sat})." >&2
    return 3
  fi

  local days=$(( ( $(date -d "$latest_sat" +%s) - $(date -d "$target_sat" +%s) ) / 86400 ))
  local pos=$(( days / 7 + 1 ))
  echo "[INFO] Day difference: $days -> RSS position: $pos" >&2
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
