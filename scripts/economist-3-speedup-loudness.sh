#!/bin/bash
# v. 20260716.162606 - speed up chapters and apply speech normalization filters
# Speeds up chapter MP3s and applies speech normalization and loudness filters.

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
economist_set_run_step speedup

echo

ffmpeg_path="${FFMPEG_PATH}"
work_dir="${ECONOMIST_WORK_DIR}"

ls -l "$work_dir"

mono_flag="  -ac 1 "

speed_factor=1.7
ffmpeg_timeout_seconds=60

ffmpeg_common_args=" -y -hide_banner -loglevel error "

silence_removal_filter="silenceremove=stop_periods=-1:stop_duration=0.2:stop_threshold=-48dB"
equalizer="firequalizer=gain_entry='entry(0,-8);entry(250,-6);entry(1000,-8);entry(4000,0)'"
speedup_filter="atempo=${speed_factor}"
speech_norm_filter="speechnorm=expansion=20[after_normalization];[after_normalization]apad=pad_dur=1s"

output_file_ext=mp3

for p in $(find "${work_dir}" -type f -not -name \*SPEECHNORM_SPEEDUP\* -name \*mp3 | sort); do
   export extension="${p##*.}"
   output_file="$(dirname "${p}")/$(basename "${p}" '.'"${extension}")_SPEECHNORM_SPEEDUP_${speed_factor}.${output_file_ext}"

   if [ -f "$p" ]; then
     /usr/bin/timeout --verbose --kill-after=10 --foreground "${ffmpeg_timeout_seconds}" "${ffmpeg_path}" ${ffmpeg_common_args} \
       -i "$p" $mono_flag -filter:a "${silence_removal_filter},${equalizer},${speedup_filter}" "${p}_tmp.${output_file_ext}"
     /usr/bin/timeout --verbose --kill-after=10 --foreground "${ffmpeg_timeout_seconds}" "${ffmpeg_path}" ${ffmpeg_common_args} \
       -i "${p}_tmp.${output_file_ext}" $mono_flag -filter_complex:a "${speech_norm_filter}" "$output_file"
     chmod --reference="${p}" "$output_file"
     chown --reference="${p}" "$output_file"
     touch --reference="${p}" "$output_file"
     rm "${p}_tmp.${output_file_ext}" "$p"
   else
     echo "File $p does not exist — skipping ffmpeg"
   fi
   sleep 0.1
done

pwd
cd "${work_dir}"
pwd
cd "$(dirname "${p}")"
pwd

ls -l

economist_step_exit 0
