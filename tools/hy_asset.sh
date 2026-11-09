#!/usr/bin/env bash
# 四視角設計圖 → Hunyuan3D 2.0 MV 形狀（ComfyUI）→ 減面＋UV → Hunyuan3D 2.1 Paint 上色 → GLB
# 用法：[SHAPE_ONLY=1|PAINT_ONLY=1] [REFS="front back"] tools/hy_asset.sh <名稱>...   需要 assets3d/<名稱>/{front,left,back,right}.png、ComfyUI 在 127.0.0.1:8188
# 輸出 assets3d/<名稱>/<名稱>.glb（另有 blank.glb＝未上色形狀）；工具沿用 ~/git_project/img2_3d/tools
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMG=~/git_project/img2_3d/tools
CPY=~/git_project/ComfyUI/.venv/bin/python
HPY=~/git_project/Hunyuan3D-2.1/.venv/bin/python
TRIS=${TRIS:-90000}
for n in "$@"; do
  D="$ROOT/assets3d/$n"; t0=$(date +%s)
  if [ -z "${PAINT_ONLY:-}" ]; then
  python3 "$ROOT/tools/prep_mv.py" "$n" "$D" >/dev/null || { echo "$n: prep failed"; continue; }
  $CPY $IMG/hymv.py "$n" "mesh/$n-hymv" ${CFG:-7.5} ${SEED:-1} | sed "s/^/$n hymv: /"
  mesh=$(ls -t ~/git_project/ComfyUI/output/mesh/$n-hymv_*.glb 2>/dev/null | head -1)
  [ -n "$mesh" ] || { echo "$n: no mesh"; continue; }
  blender -b -P "$ROOT/blender/prep_untextured.py" -- "$mesh" "$D/blank.glb" $TRIS 2048 >/dev/null 2>&1
  fi
  t1=$(date +%s); echo "$n: shape $((t1 - t0))s"
  [ -n "${SHAPE_ONLY:-}" ] && continue
  curl -s -X POST 127.0.0.1:8188/free -H 'Content-Type: application/json' -d '{"unload_models":true,"free_memory":true}' >/dev/null; sleep 2
  HY_VIEWS=${HY_VIEWS:-8} PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True $HPY $IMG/hy21_paint.py "$D/blank.glb" "$D/paint/$n.obj" $(for r in ${REFS:-front left back right}; do echo "$D/ref_$r.png"; done) > "$D/paint.log" 2>&1 \
    || { echo "$n: paint failed (see $D/paint.log)"; continue; }
  $HPY "$ROOT/tools/post_texture.py" "$D/paint/$n.jpg" >/dev/null 2>&1
  blender -b -P "$ROOT/blender/obj2glb_smooth.py" -- "$D/paint/$n.obj" "$D/$n.glb" >/dev/null 2>&1
  echo "$n: paint $(( $(date +%s) - t1 ))s → $D/$n.glb"
done
