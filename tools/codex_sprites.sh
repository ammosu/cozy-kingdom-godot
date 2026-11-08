#!/usr/bin/env bash
# 用 Codex CLI 生成透明背景的植物元件 → textures/sprites/raw/<name>.png
# 用法：tools/codex_sprites.sh [名稱...]（不給名稱 = 全部、已存在的略過）；同時跑 4 張
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIST="$ROOT/textures/sprites/list.tsv"
RAW="$ROOT/textures/sprites/raw"
COMMON='這是 3D 遊戲用的透明植物元件（PNG，背景必須是真正透明的 alpha，不要白底、不要棋盤格、不要任何背景色）。美術風格：溫馨奇幻冒險遊戲的風格化手繪寫實（介於吉卜力動畫與薩爾達曠野之息之間），色彩飽和但自然，柔和均勻的漫射光，元件四周留一點空白，底部置中，不要地面、不要投影、不要任何文字。'
gen() {
  name="$1"; desc="$(awk -F'\t' -v n="$name" '$1==n{print $2}' "$LIST")"
  dir="$(mktemp -d /tmp/codex_sprite_${name}_XXXX)"
  printf '請用你的圖片生成功能產生一張圖片。%s內容：%s\n完成後把圖片存成目前目錄下的 ./%s.png（只要這一個檔案）。' "$COMMON" "$desc" "$name" \
    | timeout 600 codex exec -s workspace-write --skip-git-repo-check -C "$dir" - >"$dir/log.txt" 2>&1
  if [ -f "$dir/$name.png" ]; then cp "$dir/$name.png" "$RAW/$name.png"; echo "ok   $name"; else echo "FAIL $name ($dir/log.txt)"; fi
}
export -f gen; export LIST RAW COMMON
names=("$@"); [ ${#names[@]} -eq 0 ] && mapfile -t names < <(cut -f1 "$LIST" | while read -r n; do [ -f "$RAW/$n.png" ] || echo "$n"; done)
printf '%s\n' "${names[@]}" | xargs -P 4 -I{} bash -c 'gen {}'
