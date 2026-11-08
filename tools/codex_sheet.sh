#!/usr/bin/env bash
# Codex 畫物件的四視角設計圖（透明背景）→ assets3d/<名稱>/sheet.png，再切成 front/left/back/right.png
# 用法：tools/codex_sheet.sh <名稱>...（描述在 assets3d/list.tsv）；同時跑 3 張
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
gen() {
  n="$1"; D="$ROOT/assets3d/$n"; mkdir -p "$D"
  desc="$(awk -F'\t' -v k="$n" '$1==k{print $2}' "$ROOT/assets3d/list.tsv")"
  cat > "$D/prompt.md" <<P
Attached: concept art of characters from our cozy fantasy game, as a STYLE reference only (soft painterly 3D-render look, warm saturated but natural colours, chunky friendly proportions, soft studio lighting).

Use your image generation tool to create ONE orthographic turnaround sheet of a game environment asset, in the same art style, designed to be rebuilt as a 3D model:
Asset: $desc

Rules:
1. Exactly four views in one row, left to right: FRONT, LEFT SIDE (the asset's front faces the left edge of the image), BACK, RIGHT SIDE (front faces the right edge). The FRONT is the side with the door / counter / main opening.
2. Orthographic, no perspective, eye-level, identical scale in all views, all bottoms on the same ground line, each view centred in its quarter with clear empty space between views. The four views must be consistent with each other (same details on the same sides).
3. Solid closed shapes, chunky readable details, no tiny floating parts, no characters, no ground plane, no cast shadow, no text or labels.
4. The background must be truly transparent alpha (PNG). No white background, no checkerboard, no background colour at all.
Image size: wide landscape (e.g. 2048x768).

Save the final image as ./sheet.png in the current directory. Do not modify any other file.
P
  timeout 900 codex exec -s workspace-write --skip-git-repo-check -C "$D" "$(cat "$D/prompt.md")" \
    -i "$ROOT/concept/villager_badger.png" -i "$ROOT/concept/hero.png" < /dev/null > "$D/codex.log" 2>&1
  if [ -f "$D/sheet.png" ]; then python3 "$ROOT/tools/split_alpha.py" "$D/sheet.png" "$D" && echo "ok   $n"; else echo "FAIL $n"; fi
}
export -f gen; export ROOT
printf '%s\n' "$@" | xargs -P 3 -I{} bash -c 'gen {}'
