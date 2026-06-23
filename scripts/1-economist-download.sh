#!/bin/bash
# v. 2.7 - 2026.06.19 - changelog comments translated to English
# v. 2.6 - 2026.06.19 - renamed from 1-economist-sciagnij.sh
# v. 2.5 - 2026.06.16 - RSS URL from economist.local.conf (not in git)
# v. 2.4 - 2025.09.17 - auto-tip for xmllint + grep fallback when xmllint missing or returns 0
# v. 2.3 - 2025.09.17 - added echo/logging
# v. 2.2 - 2025.09.17 - optional YYYY-MM-DD selects n-th RSS item (xmllint); default is first enclosure

set -euo pipefail
LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_load-config.sh
source "${SCRIPT_DIR}/_load-config.sh"
load_economist_config
require_economist_rss_url

command -v xmllint >/dev/null 2>&1 || echo "[INFO] Tip: brak 'xmllint'. Zainstaluj: \
Debian/Ubuntu: 'apt install libxml2-utils' | RHEL/CentOS: 'yum install libxml2' | Alpine: 'apk add libxml2-utils'"

echo
echo "---- Poczatek wykonywania skryptu $0 ($(date '+%Y.%m.%d %H:%M:%S'))"

katalog_roboczy="${ECONOMIST_WORK_DIR}"
kat_zrodlowy="${ECONOMIST_BASE_DIR}"
kat_wynikowy="${ECONOMIST_OUTPUT_DIR}"

mkdir -p "${katalog_roboczy}" 2>/dev/null
cd "${katalog_roboczy}"

kod_powrotu=$?
if (( kod_powrotu != 0 )); then
   echo "cos poszlo nie tak - nie moge zmienic katalogu na \"${katalog_roboczy}\" - kod powrotu to ${kod_powrotu}"
   exit "${kod_powrotu}"
fi

pwd

if [[ -f "${katalog_roboczy}/economist.mp3" ]]; then
  echo
  echo "Plik ${katalog_roboczy}/economist.mp3 istnieje, wiec nie sciagam go ponownie"
  echo "kasuje tez katalog ${katalog_roboczy} bo jest pusty"
  echo "wiec KONCZE DZIALANIE"
  echo
  exit 1
fi

cd "${katalog_roboczy}"

rm -f economist.rss 2>/dev/null
echo "[INFO] Pobieram RSS: ${ECONOMIST_RSS_URL}"
curl -fsSL "${ECONOMIST_RSS_URL}" -o economist.rss
echo "[INFO] Zapisano RSS do: $(pwd)/economist.rss"

weeks_position_from_date() {
  local iso="$1"

  if [[ ! "$iso" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || [[ "$(date -d "$iso" +%F 2>/dev/null)" != "$iso" ]]; then
    echo "Expected YYYY-MM-DD (np. 2025-08-16)" >&2
    return 2
  fi

  echo "[INFO] Wejsciowa data: $iso" >&2
  local dow_in off_in target_sat
  dow_in=$(date -d "$iso" +%u)
  off_in=$(( (dow_in + 1) % 7 ))
  target_sat=$(date -d "$iso - $off_in days" +%F)
  echo "[INFO] Zmapowana sobota (wydanie): $target_sat (dow=$dow_in, cofniecie=$off_in)" >&2

  local dow_now off_now latest_sat
  dow_now=$(date +%u)
  off_now=$(( (dow_now + 1) % 7 ))
  latest_sat=$(date -d "today - $off_now days" +%F)
  echo "[INFO] Najnowsza sobota (referencja): $latest_sat (dow_now=$dow_now, cofniecie=$off_now)" >&2

  if (( $(date -d "$target_sat" +%s) > $(date -d "$latest_sat" +%s) )); then
    echo "Data w przyszlosci vs. najnowsze wydanie (${latest_sat})." >&2
    return 3
  fi

  local days=$(( ( $(date -d "$latest_sat" +%s) - $(date -d "$target_sat" +%s) ) / 86400 ))
  local pos=$(( days / 7 + 1 ))
  echo "[INFO] Roznica dni: $days -> pozycja w RSS: $pos" >&2
  echo "$pos"
}

download_url=""

if [[ $# -eq 0 ]]; then
  echo "[INFO] Brak argumentow – biore najnowszy (pozycja 1, pierwszy enclosure)."
  download_url="$(grep -oP '<enclosure url="\K[^"]+' economist.rss | head -n 1 || true)"
else
  iso="$1"
  pos="$(weeks_position_from_date "$iso")" || { echo "[INFO] Blad przeliczania pozycji dla daty: $iso"; rm -f economist.rss; exit 1; }

  item_count=0
  if command -v xmllint >/dev/null 2>&1; then
    item_count_raw="$(xmllint --xpath 'count(//item)' economist.rss 2>/dev/null || echo 0)"
    item_count="${item_count_raw%.*}"
    echo "[INFO] Liczba pozycji wg xmllint: $item_count"
  else
    echo "[INFO] xmllint nie znaleziony — użyje fallbacku grep." >&2
  fi

  if [[ "$item_count" -eq 0 ]]; then
    item_count="$(grep -oP '<enclosure url="\K[^"]+' economist.rss | wc -l | awk '{print $1}')"
    echo "[INFO] Liczba pozycji wg grep: $item_count"
  fi

  if [[ "$pos" -le 0 || "$pos" -gt "$item_count" ]]; then
    echo "Brak elementu o pozycji $pos (feed ma $item_count pozycji)." >&2
    rm -f economist.rss
    exit 2
  fi

  if command -v xmllint >/dev/null 2>&1 && [[ "$item_count" -gt 0 ]]; then
    download_url="$(xmllint --xpath "string((//item)[$pos]/enclosure/@url)" economist.rss 2>/dev/null || true)"
    [[ -n "$download_url" ]] && echo "[INFO] URL MP3 (xmllint, poz. $pos): $download_url"
  fi

  if [[ -z "$download_url" ]]; then
    download_url="$(grep -oP '<enclosure url="\K[^"]+' economist.rss | sed -n "${pos}p" || true)"
    echo "[INFO] URL MP3 (grep fallback, poz. $pos): ${download_url:-<pusty>}"
  fi
fi

if [[ -z "${download_url}" ]]; then
  echo "Nie znaleziono URL do pobrania w economist.rss." >&2
  rm -f economist.rss
  exit 1
fi

rm -f economist.rss

echo
echo "sciagam plik $(pwd)/economist.mp3"
echo "[INFO] Zrodlo: $download_url"
echo

wget --max-redirect=5 "${download_url}" -O economist.mp3 2>/dev/null

if [[ ! -s economist.mp3 ]]; then
  echo "Plik economist.mp3 NIE istnieje lub jest pusty. Czyszcze katalog roboczy."
  cd /tmp || exit 1
  rmdir "${katalog_roboczy}"
  exit 1
fi

echo "[INFO] OK — pobrano economist.mp3 ($(du -h economist.mp3 | awk '{print $1}'))"
echo "---- Koniec wykonywania skryptu   $0 ($(date '+%Y.%m.%d %H:%M:%S'))"
