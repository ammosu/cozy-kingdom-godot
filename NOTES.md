# Cozy Kingdom 實驗筆記

照 X 貼文（dhruvalgolakiya，2026-11-07）的流程做溫馨奇幻小遊戲，引擎改用 Godot 4.7（本機沒有 UE）。

## 流程與指令

1. **概念圖**（Codex 內建 image generation）：`concept/prompt.md` → 白底、全身、A-pose 的 PNG。
2. **角色**（Tripo）：`.venv/bin/python tools/tripo_chars.py --dry-run | all | <角色>`
   - 依序是圖轉模型 → 綁骨 → 套動作。task id 存在 `assets/tripo/state.json`，重跑會跳過已完成的步驟。
   - 第一輪 4 隻角色共花 310 點。
3. **合併動作**：`blender -b -P blender/merge_anims.py -- <角色> <身高m> [轉向角度]`（雙足給 -90、四足給 0） → `godot/assets/chars/<角色>.glb`
4. **王國**：`blender -b -P blender/gen_kingdom.py -- --seed 7 --houses 120` → `godot/assets/kingdom.glb`＋`kingdom_layout.json`
5. **材質**：Codex 生成 `textures/src/*.png`，再跑 `python3 tools/prep_textures.py`（無縫化、法線貼圖、可染色的貼圖去飽和）。
6. **截圖**：`[REL=1] tools/shot.sh <名稱> "x,y,z" "x,y,z" [frames]`
   - `REL=1` 時 y 代表離地高度。
7. **示範影片**：`tools/record.sh <名稱>` → `video/<名稱>.mp4`
   - 時間軸寫在 `actors.gd` 的 `DEMO_STEPS`。
   - 用 `tools/contact.sh video/x.mp4 1.0` 出縮圖總表。

操作：WASD 移動、Shift 跑、Space 跳、R 召喚／上下麋鹿、Esc 放開滑鼠。

## 踩過的坑

- **Tripo 四足綁骨**：預設 v1.0 會回 `Invalid input parameter`，要用 `client.rig(model="v3.0-20260909", rig_type="quadruped", spec="tripo")`。
- **Tripo 雙足綁骨**：v3.0＋`spec="unreal"` 可用，骨架名稱是 UE Mannequin 式。
- **Tripo 並行送出**：某一隻 `SystemExit` 會把其他隻已送出的任務一起中斷。任務其實已在跑、點數也已扣，要用 task id 接回來。
- **Tripo GLB 夾帶 Icosphere**：每個 GLB 都夾帶一顆 Icosphere，模型本身已正規化成高 1，要自己縮放。
- **法線方向**：bmesh 對開放網格（地形）做 `recalc_face_normals` 會整片翻成朝下。畫面因為雙面材質看不出異狀，但 Godot 的 trimesh 碰撞只吃正面，射線打不到，草就長不出來。
- **Tripo 角色朝向**：`spec="unreal"` 的雙足骨架面向 +X（UE 慣例），四足 `spec="tripo"` 面向 +Z。雙足要在合併時轉 -90°，不然走路會側著走。用 Workbench 從 +Z 方向算一張正視圖就能檢查。
- **城門大道**：城外地形隆起會把延伸出去的路埋掉，要整平一條走廊。
- **錄影節流**：Godot 視窗在背景時，vsync 會被合成器節流到約 1 fps。`project.godot` 要設 `vsync_mode=0`，錄 21 秒的影片才只要 34 秒。
- **相關筆記**：beach3d-eval 的 `PLAYBOOK.md` 有 Tripo 與 Blender 的其他筆記。
