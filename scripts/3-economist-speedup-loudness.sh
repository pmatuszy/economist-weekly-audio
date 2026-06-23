#!/bin/bash
# v. 2.3 - 2026.06.19 - changelog comments translated to English
# v. 2.2 - 2026.06.19 - renamed from 3-zmien-szybkosc-podbij-glosnosc.sh
# v. 2.1 - 2026.06.16 - ffmpeg path from economist.local.conf
# v. 2.0 - 2025.01.28 - major rewrite — practically a new script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_load-config.sh
source "${SCRIPT_DIR}/_load-config.sh"
load_economist_config

echo "---- Poczatek wykonywania skryptu $0 ($(date '+%Y.%m.%d %H:%M:%S'))"

ffmpeg_path="${FFMPEG_PATH}"
katalog_zrodlowy="${ECONOMIST_WORK_DIR}"

ls -l "$katalog_zrodlowy"

czy_robimy_pliki_mono="  -ac 1 "

o_ile_przyspieszyc=1.7
ffmpeg_kill_po_tylu_sekundach=60

ffmpeg_rozne_generic_parametry=" -y -hide_banner -loglevel error "

usun_cisze="silenceremove=stop_periods=-1:stop_duration=0.2:stop_threshold=-48dB"
equalizer="firequalizer=gain_entry='entry(0,-8);entry(250,-6);entry(1000,-8);entry(4000,0)'"
przyspieszenie="atempo=${o_ile_przyspieszyc}"
norm_glosu="speechnorm=expansion=20[po_normalizacji];[po_normalizacji]apad=pad_dur=1s"

plik_wyn_ext=mp3

for p in $(find "${katalog_zrodlowy}" -type f -not -name \*SPEECHNORM_SPEEDUP\* -name \*mp3 | sort); do
   export rozszerzenie="${p##*.}"
   plik_wynikowy="$(dirname "${p}")/$(basename "${p}" '.'"${rozszerzenie}")_SPEECHNORM_SPEEDUP_${o_ile_przyspieszyc}.${plik_wyn_ext}"

   if [ -f "$p" ]; then
     /usr/bin/timeout --verbose --kill-after=10 --foreground "${ffmpeg_kill_po_tylu_sekundach}" "${ffmpeg_path}" ${ffmpeg_rozne_generic_parametry} \
       -i "$p" $czy_robimy_pliki_mono -filter:a "${usun_cisze},${equalizer},${przyspieszenie}" "${p}_tymcz.${plik_wyn_ext}"
     /usr/bin/timeout --verbose --kill-after=10 --foreground "${ffmpeg_kill_po_tylu_sekundach}" "${ffmpeg_path}" ${ffmpeg_rozne_generic_parametry} \
       -i "${p}_tymcz.${plik_wyn_ext}" $czy_robimy_pliki_mono -filter_complex:a "${norm_glosu}" "$plik_wynikowy"
     chmod --reference="${p}" "$plik_wynikowy"
     chown --reference="${p}" "$plik_wynikowy"
     touch --reference="${p}" "$plik_wynikowy"
     rm "${p}_tymcz.${plik_wyn_ext}" "$p"
   else
     echo "plik $p nie istnieje, nie odpalam ffmpega"
   fi
   sleep 0.1
done

pwd
cd "${katalog_zrodlowy}"
pwd
cd "$(dirname "${p}")"
pwd

ls -l

echo "---- Koniec wykonywania skryptu   $0 ($(date '+%Y.%m.%d %H:%M:%S'))"
