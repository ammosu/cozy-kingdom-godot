#!/usr/bin/env bash
# 影片縮圖總表：tools/contact.sh video/x.mp4 [每幾秒一張=1.5] → shots/<x>_sheet.jpg
set -e
IN="$1"; STEP="${2:-1.5}"
OUT="$(dirname "$0")/../shots/$(basename "${IN%.*}")_sheet.jpg"
ffmpeg -y -loglevel error -i "$IN" -vf "fps=1/$STEP,scale=400:-1,drawtext=text='%{pts\:hms}':x=8:y=8:fontsize=20:fontcolor=white:box=1:boxcolor=black@0.5,tile=4x5" -frames:v 1 "$OUT"
echo "$OUT"
