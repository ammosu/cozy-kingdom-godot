#!/usr/bin/env bash
# 錄示範影片：[REEL=1] tools/record.sh [名稱=demo]（REEL=1 是分段展示版）  → video/<名稱>.mp4（Godot Movie Maker 逐格 30fps，與實際效能無關）
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:-demo}"
mkdir -p "$ROOT/video"
if [ -n "${REEL:-}" ]; then DEMO=""; else DEMO=1; fi
DEMO="$DEMO" REEL="${REEL:-}" timeout 1800 godot --path "$ROOT/godot" --windowed --resolution 1600x900 --fixed-fps 30 \
  --write-movie "$ROOT/video/$NAME.avi" 2>&1 | grep -vE "^\s*$" | tail -5
ffmpeg -y -loglevel error -i "$ROOT/video/$NAME.avi" -c:v libx264 -crf 22 -pix_fmt yuv420p -c:a aac "$ROOT/video/$NAME.mp4"
rm -f "$ROOT/video/$NAME.avi"
ffprobe -v error -show_entries format=duration -of csv=p=0 "$ROOT/video/$NAME.mp4"
