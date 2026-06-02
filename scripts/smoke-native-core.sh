#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT/release/VidPress.app"
FFMPEG="$APP_PATH/Contents/Resources/ffmpeg"
FFPROBE="$APP_PATH/Contents/Resources/ffprobe"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vidpress-smoke.XXXXXX")"
INPUT="$WORK_DIR/input.mp4"
OUTPUT="$WORK_DIR/output-balanced.mp4"
PROGRESS_LOG="$WORK_DIR/progress.log"
ERROR_LOG="$WORK_DIR/ffmpeg-error.log"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [[ ! -x "$FFMPEG" || ! -x "$FFPROBE" ]]; then
  echo "Missing bundled FFmpeg/FFprobe. Run npm run dist first." >&2
  exit 1
fi

"$FFMPEG" \
  -hide_banner \
  -y \
  -f lavfi \
  -i testsrc=size=320x180:rate=15 \
  -f lavfi \
  -i sine=frequency=880:sample_rate=44100 \
  -t 1.5 \
  -shortest \
  -c:v libx264 \
  -pix_fmt yuv420p \
  -c:a aac \
  "$INPUT" >/dev/null 2>"$ERROR_LOG"

"$FFPROBE" -v error -show_entries format=duration,size -of json "$INPUT" >/dev/null

"$FFMPEG" \
  -hide_banner \
  -y \
  -nostdin \
  -i "$INPUT" \
  -c:v libx264 \
  -preset medium \
  -crf 24 \
  -c:a aac \
  -b:a 128k \
  -movflags +faststart \
  -progress pipe:1 \
  -stats_period 0.25 \
  -nostats \
  "$OUTPUT" >"$PROGRESS_LOG" 2>"$ERROR_LOG"

if [[ ! -s "$OUTPUT" ]]; then
  echo "Smoke output was not created." >&2
  cat "$ERROR_LOG" >&2
  exit 1
fi

"$FFPROBE" -v error -show_entries format=duration,size -of json "$OUTPUT" >/dev/null

if ! grep -q "progress=end" "$PROGRESS_LOG"; then
  echo "FFmpeg progress stream did not finish cleanly." >&2
  cat "$PROGRESS_LOG" >&2
  exit 1
fi

echo "VidPress native core smoke passed."
