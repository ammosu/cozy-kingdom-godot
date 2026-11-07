#!/usr/bin/env bash
# 用法：tools/shot.sh <名稱> "x,y,z" "x,y,z" [frames]  → shots/<名稱>.png
# 視窗會短暫出現在桌面上（要用 GPU 算繪）。
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REL="${REL:-}" SHOT="$ROOT/shots/$1.png" CAM="$2" LOOK="$3" FRAMES="${4:-120}" TIME="${TIME:-3.0}" \
  timeout 300 godot --path "$ROOT/godot" --windowed --resolution 1600x900 2>&1 | grep -vE "^\s*$" | tail -20
