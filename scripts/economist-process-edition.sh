#!/bin/bash
# v. 1.9 - 2026.07.15 - renamed from 2-economist-process-edition.sh
# v. 1.8 - 2026.07.15 - added script description header
# v. 1.6 - 2026.06.19 - runtime messages translated to English
# v. 1.5 - 2026.06.19 - changelog comments translated to English
# v. 1.4 - 2026.06.19 - renamed from 2-economist-obrob.sh
# v. 1.3 - 2026.06.16 - paths and chown from economist.local.conf
# v. 1.2 - 2025.10.27 - bugfix: removed -df from rar for artwork — it was deleting the input file
# v. 1.1 - 2025.10.21 - artwork file is added to output RAR but not deleted
# v. 1.0 - 2025.01.28 - major rewrite — practically a new script
# Splits chapters, embeds artwork, renames files, and archives the original MP3.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_load-config.sh
source "${SCRIPT_DIR}/_load-config.sh"
load_economist_config

echo "---- Script start: $0 ($(date '+%Y.%m.%d %H:%M:%S'))"

work_dir="${ECONOMIST_WORK_DIR}"

mkdir -p "${work_dir}"

mp3_file="${work_dir}/economist.mp3"

if [[ ! -s "$mp3_file" || $(stat -c%s "$mp3_file") -lt 1000000 ]]; then
  echo
  echo "❌ File $mp3_file is missing or too small. Cleaning up work directory (if empty) and exiting."
  cd /tmp || exit 1
  rmdir --ignore-fail-on-non-empty "$work_dir"
  exit 1
fi

cd "${work_dir}" || {
  echo "Cannot change to directory ${work_dir}"
  exit 1
}

rm -v chapters.txt 0*mp3 artwork_*jpg 2>/dev/null

ffmpeg -hide_banner -loglevel error -y -i economist.mp3 -f ffmetadata chapters.txt < /dev/null

convert_album_to_date() {
    local album_date="$1"
    album_date=$(echo "$album_date" | sed 's/-[^ ]*//')
    local month=$(echo "$album_date" | awk '{print $1}')
    local day=$(echo "$album_date" | awk '{print $2}' | sed 's/[a-zA-Z]//g')
    local year=$(echo "$album_date" | awk '{print $NF}')
    date -d "$month $day $year" +"%Y%m%d"
}

album_metadata=$(ffprobe -v error -show_entries format_tags=album -of default=noprint_wrappers=1:nokey=1 economist.mp3)
album_date=$(convert_album_to_date "$album_metadata")
echo "Album date: $album_date"

artwork_url="https://www.economist.com/cdn-cgi/image/width=1024,quality=100,format=jpeg/content-assets/images/${album_date}_DE_EU.jpg"
echo "Artwork URL: $artwork_url"

artwork_file="artwork_${album_date}.jpg"

UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36'
ref="https://www.economist.com/weeklyedition/${album_date:0:4}-${album_date:4:2}-${album_date:6:2}"

"${CURL_IMPERSONATE}" -fsSL --compressed -e "$ref" -o "$artwork_file" "$artwork_url"

if [[ -f "$artwork_file" && -s "$artwork_file" ]]; then
    echo "Artwork downloaded successfully: $artwork_file"
    file "$artwork_file"
else
    echo "Failed to download artwork: $artwork_url"
    exit 1
fi

while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^\[CHAPTER\]$ ]]; then
        title=""
        start=""
        end=""
    elif [[ "$line" =~ ^START=([0-9]+)$ ]]; then
        start=$((BASH_REMATCH[1] / 1000))
    elif [[ "$line" =~ ^END=([0-9]+)$ ]]; then
        end=$((BASH_REMATCH[1] / 1000))
    elif [[ "$line" =~ ^title=(.+)$ ]]; then
        title="${BASH_REMATCH[1]}"
        filename=$(echo "$title.mp3" | sed 's/[^a-zA-Z0-9._-]/_/g')
        if [[ -z "$filename" ]]; then
            filename="chapter_${start}_${end}.mp3"
        fi
        if [[ -n "$start" && -n "$end" && "$end" -gt "$start" ]]; then
            echo "Processing: $filename (start=$start, end=$end)"
            ffmpeg -hide_banner -loglevel error -y -i economist.mp3 -ss "$start" -to "$end" -c copy "$filename" < /dev/null
            sleep 0.1
        else
            echo "Skipping invalid chapter: START=$start, END=$end"
        fi
    fi
done < chapters.txt

echo "Adding artwork to MP3 files..."
for mp3 in *.mp3; do
    if [[ "$mp3" != "economist.mp3" ]]; then
        echo "Adding artwork to: $mp3"
        chapter_title=$(basename "$mp3" .mp3)
        ffmpeg -hide_banner -loglevel error -y -i "$mp3" -i "$artwork_file" -map 0 -map 1 -c copy -disposition:v attached_pic \
            -metadata title="$chapter_title" -metadata artist="The Economist" "tmp_$mp3" < /dev/null
        sleep 0.1
        mv "tmp_$mp3" "$mp3"
    fi
done

echo "Renaming original economist.mp3 file..."
formatted_date=$(echo "$album_date" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1.\2.\3/')
mv economist.mp3 "TheEconomist_${formatted_date}.mp3"
echo "Original file renamed to: TheEconomist_${formatted_date}.mp3"

echo "Creating directory for output files..."
output_dir="${formatted_date}_TheEconomist"

mkdir -p "$output_dir"
mv TheEconomist_${formatted_date}.mp3 "$output_dir"
mv -v chapters.txt artwork_*jpg *.mp3 "$output_dir"

echo "All files moved to: $output_dir"
echo "All MP3 files processed with artwork, updated metadata, renamed, and organized in a new directory."

chmod -R 755 "${output_dir}"
economist_chown_if_set "${output_dir}"

cd "$output_dir"

rename --force 's/ /_/g' *mp3 *aac *m4a
rename --force 's/,/_/g' *mp3 *aac *m4a
rename --force 's/__/_/g' *mp3 *aac *m4a

rm -v [0-9][0-9][0-9]_Books_and_arts.mp3 \
      [0-9][0-9][0-9]_Middle_East_and_Africa.mp3 \
      [0-9][0-9][0-9]_Science_and_technology.mp3 \
      [0-9][0-9][0-9]_Finance_and_economics.mp3 \
      [0-9][0-9][0-9]_United_States.mp3 \
      [0-9][0-9][0-9]_Britain.mp3 \
      [0-9][0-9][0-9]_Asia.mp3 \
      [0-9][0-9][0-9]_Leaders.mp3 \
      [0-9][0-9][0-9]_The_Americas.mp3 \
      [0-9][0-9][0-9]_Europe.mp3 \
      [0-9][0-9][0-9]_Business.mp3 \
      [0-9][0-9][0-9]_China.mp3 \
      [0-9][0-9][0-9]_International.mp3 \
      [0-9][0-9][0-9]_Briefing.mp3 \
      [0-9][0-9][0-9]_Graphic_detail.mp3 \
      [0-9][0-9][0-9]_Culture.mp3 \
      [0-9][0-9][0-9]_Special_report.mp3 \
      [0-9][0-9][0-9]_*_fiction.mp3      2> /dev/null

rar m -htb -df -m0 _org_file.rar TheEconomist_${formatted_date}.mp3  chapters.txt
rar a -htb     -m0 _org_file.rar artwork_*jpg

economist_chown_if_set _org_file.rar

echo "---- Script end:   $0 ($(date '+%Y.%m.%d %H:%M:%S'))"
