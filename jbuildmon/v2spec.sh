#!/usr/bin/env bash
set -euo pipefail

# v2spec: record audio -> transcribe (whisper) -> save transcript
#
# Usage:
#   v2spec.sh           # record until Enter is pressed, then transcribe
#
# Env overrides:
#   AUDIO_DIR=specs/interviews   # where audio files are saved
#   TRANSCRIPT_DIR=specs/todo    # where transcripts are saved
#   MODEL=medium
#   WHISPER_LANG=en
#
# Notes:
# - Uses ffmpeg's avfoundation input on macOS.
# - Default mic device is ":0". If your machine differs, list devices:
#     ffmpeg -f avfoundation -list_devices true -i ""

log() { echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") ==> $*" >&2; }

AUDIO_DIR="${AUDIO_DIR:-specs/interviews}"
TRANSCRIPT_DIR="${TRANSCRIPT_DIR:-specs/todo}"
MODEL="${MODEL:-medium}"
WHISPER_LANG="${WHISPER_LANG:-en}"

mkdir -p "$AUDIO_DIR" "$TRANSCRIPT_DIR"

STAMP=$(date +"%Y%m%d-%H%M%S")
AUDIO="${AUDIO_DIR}/interview-${STAMP}.m4a"
TXT="${TRANSCRIPT_DIR}/interview-${STAMP}.txt"

log "Recording to: $AUDIO"
echo "    Press Enter to stop recording." >&2

# Record audio from default mic in the background.
# On most Macs, audio device index 0 works as ":0". If not, list devices (see note above).
ffmpeg -hide_banner -loglevel error \
  -f avfoundation -i ":2" \
  -ac 1 -ar 16000 \
  -c:a aac -b:a 96k \
  "$AUDIO" 2>/dev/null &
FFMPEG_PID=$!

# Show a red "RECORDING NOW" indicator if stderr is a TTY (no trailing newline so we can erase it)
if [ -t 2 ]; then
  printf '\033[1;31m  *** RECORDING NOW ***  \033[0m' >&2
fi

# Wait for user to press Enter, then stop recording
read -r -s
kill "$FFMPEG_PID" 2>/dev/null || true
wait "$FFMPEG_PID" 2>/dev/null || true

# Erase the RECORDING NOW line if we printed it
if [ -t 2 ]; then
  printf '\r\033[2K' >&2
fi

log "Recording stopped."
log "Transcribing with whisper (model=$MODEL, lang=$WHISPER_LANG)"
# Get duration in seconds using ffprobe, then format as minutes:seconds and echo
if command -v ffprobe >/dev/null 2>&1; then
  DURATION_SEC=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$AUDIO" | awk '{printf "%.0f", $1}')
  MIN=$(($DURATION_SEC / 60))
  SEC=$(($DURATION_SEC % 60))
  log "$(printf "Audio length: %d:%02d (min:sec)" "$MIN" "$SEC")"
else
  log "Audio length: (ffprobe not found, unable to determine duration)"
fi

# Whisper writes output named after the input file (without extension)
whisper "$AUDIO" \
  --model "$MODEL" \
  --fp16 False \
  --language "$WHISPER_LANG" \
  --output_format txt \
  --output_dir "$AUDIO_DIR" >/dev/null

WHISPER_TXT="${AUDIO_DIR}/interview-${STAMP}.txt"
if [[ ! -f "$WHISPER_TXT" ]]; then
  echo "ERROR: Expected transcript not found: $WHISPER_TXT" >&2
  exit 1
fi
mv -f "$WHISPER_TXT" "$TXT"

log "Transcript saved: $TXT"
cat "$TXT"
