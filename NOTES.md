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
5b. **植被**：
   - `blender -b -P blender/gen_trees.py` → `godot/assets/nature/*.glb`（闊葉樹、松樹、灌木）。
   - `tools/codex_sprites.sh` 用 Codex 生透明植物圖（清單在 `textures/sprites/list.tsv`），再跑 `python3 tools/prep_sprites.py` 做裁邊、顏色外擴，輸出到 `godot/assets/sprites/`。
   - 種植寫在 `godot/scripts/nature.gd`。設 `OLD_GRASS=1` 可切回舊的單片草葉。
5c. **Hunyuan3D 建築與道具**（取代程序化的房子、攤位、噴水池、塔樓、城門、主堡、城牆）：
   - 清單在 `assets3d/list.tsv`（名稱＋英文描述）。
   - `tools/codex_sheet.sh <名稱>...`：Codex 畫四視角透明設計圖，切成 `assets3d/<名稱>/{front,left,back,right}.png`。
   - `tools/hy_asset.sh <名稱>...`：Hunyuan 2.0 MV 出形狀（ComfyUI 要開著）→ `blender/prep_untextured.py` 減面到 3 萬面 → Hunyuan 2.1 Paint 用四張圖上色 → `assets3d/<名稱>/<名稱>.glb`。每個約 2 分鐘。可加 `SHAPE_ONLY=1`、`PAINT_ONLY=1`、`SEED=`。
   - 成品複製到 `godot/assets/props/`。`blender -b -P blender/gen_kingdom.py -- --seed 7 --houses 120 --hy 1` 產生不含這些建築的 `kingdom_hy.glb`，由 `props.gd` 依配置擺放。設 `KINGDOM=proc` 可切回程序化版。
   - **授權**：Hunyuan3D 2.1 Paint 模型限非商業用途。
   - 城門樓與主堡入口有修補腳本：重新生成後要跑 `blender -b -P blender/fix_gatehouse.py`、`blender/fix_keep.py`（會輸出到 `godot/assets/props/`）。
5d. **分區評分**：`tools/eval_round.sh <輪次>` 固定鏡頭拍 14 個區塊，Codex 依 `eval/rubric.md` 評分，結果在 `eval/rNN.json`。分數有 ±0.3 的波動。
5e. **自我測試**：`SELFTEST=1 godot --path godot --windowed --resolution 1600x900` 實際跑物理（穿門洞、撞牆、撞村民、連擊），印 PASS/FAIL。
6. **截圖**：`[REL=1] tools/shot.sh <名稱> "x,y,z" "x,y,z" [frames]`
   - `REL=1` 時 y 代表離地高度。
7. **示範影片**：`tools/record.sh <名稱>` → `video/<名稱>.mp4`
   - 時間軸寫在 `actors.gd` 的 `DEMO_STEPS`。`REEL=1 tools/record.sh <名稱>` 錄分段展示版，內容寫在 `godot/scripts/demo_reel.gd`。
   - 用 `tools/contact.sh video/x.mp4 1.0` 出縮圖總表。

操作：WASD 移動、Shift 跑、Space 跳、左鍵攻擊（空中按是跳起下劈）、R 召喚／上下麋鹿、F 切換霧氣、Esc 放開滑鼠。

## 踩過的坑

- **Tripo 四足綁骨**：預設 v1.0 會回 `Invalid input parameter`，要用 `client.rig(model="v3.0-20260909", rig_type="quadruped", spec="tripo")`。
- **Tripo 雙足綁骨**：v3.0＋`spec="unreal"` 可用，骨架名稱是 UE Mannequin 式。
- **Tripo 並行送出**：某一隻 `SystemExit` 會把其他隻已送出的任務一起中斷。任務其實已在跑、點數也已扣，要用 task id 接回來。
- **Tripo GLB 夾帶 Icosphere**：每個 GLB 都夾帶一顆 Icosphere，模型本身已正規化成高 1，要自己縮放。
- **法線方向**：bmesh 對開放網格（地形）做 `recalc_face_normals` 會整片翻成朝下。畫面因為雙面材質看不出異狀，但 Godot 的 trimesh 碰撞只吃正面，射線打不到，草就長不出來。
- **Tripo 角色朝向**：`spec="unreal"` 的雙足骨架面向 +X（UE 慣例），四足 `spec="tripo"` 面向 +Z。雙足要在合併時轉 -90°，不然走路會側著走。用 Workbench 從 +Z 方向算一張正視圖就能檢查。
- **城門大道**：城外地形隆起會把延伸出去的路埋掉，要整平一條走廊。
- **錄影節流**：Godot 視窗在背景時，vsync 會被合成器節流到約 1 fps。`project.godot` 要設 `vsync_mode=0`，錄 21 秒的影片才只要 34 秒。
- **植被不像遊戲**：hd2d／beach3d 的經驗是樹冠用平滑圓球會有團塊感，要在表面貼葉簇卡片（每團約 34 張）。草和花用透明貼圖的交叉面片，法線一律朝上，背面才不會變黑。Codex 的 prompt 要明寫「背景必須是真正透明的 alpha，不要白底、不要棋盤格」，這次 8 張全部一次成功。
- **截圖的 fps**：前 120 幀還在編譯 shader、算 SDFGI，數字不準，量效能要給 900 幀（shot.sh 第 4 個參數）。
- **Hunyuan 破碎網格**：有些房子的原始網格有兩、三百萬面、幾十萬條非流形邊，直接減面會卡在 70 萬面，Paint 一跑十幾分鐘到兩小時。`prep_untextured.py` 遇到超過目標 40 倍的網格會先做體素重建再減面。
- **扁長物件細節糊掉**：10 m 長的城牆，城垛在 Hunyuan 裡解析度不夠，糊成一團。模組化的物件要做短一點、接近正方形。
- **隱藏碰撞擋到貼地射線**：城牆用 Blender 的隱藏方塊做碰撞，擺牆段時往下打的射線要跳過 `HiddenCol*`，不然整段牆會浮在 7 m 高。
- **zsh 不拆變數**：`for n in $names` 在 zsh 只跑一次，批次腳本要用 bash 跑。
- **Hunyuan 重建不了細件**：細窗格、斜撐、雕像、藤蔓會變成破洞和融化感。Codex 設計圖改成粗獷大塊面（`SHEET_EXTRA`）後，民房評分從 4.0 升到 6.5。
- **陰影梳齒**：屋簷下規律的鋸齒是陰影貼圖解析度不足，要調 `directional_shadow_split_*`、`light_angular_distance = 0`，調 bias 沒用。
- **Paint 的記憶體**：voxcpm-api 開著時 8 視角／512 可以跑，768 會記憶體不足。殘留的上色程序也會讓後面的批次全部失敗，批次中斷後要確認沒有舊程序。
- **減面門檻**：體素重建的判斷要看原始面數（>120 萬），綁目標面數的話，目標調高就不會觸發。
- **鏡頭貼地**：SpringArm 的單條射線只保證中心點，鏡頭仰角大時只離地幾公分，再加晃動就穿地。改用球體掃掠，半徑要小於玩家膠囊，起點才不會卡進牆裡。
- **地形邊界**：地形只到 ±360，外圈是山丘，爬得上去就會走出地面掉進虛空，玩家要限制在半徑 300 內。
- **768 上色**：要 `HY_RES=768 HY_TEX=4096 HY_VAE_SLICE=1` 並暫停 voxcpm。`HY_TEX` 的實際輸出是一半，8 視角不開逐張解碼會記憶體不足。
- **卡肉不要用 Engine.time_scale**：物理幀間隔會跟著拉長（0.08 倍時約 0.2 秒一幀），判斷寫在物理迴圈裡就停不準，全世界還一起卡。改成只停玩家和被打的人，用遊戲內 dt 倒數，錄影也會一致。
- **音效**：`python3 tools/gen_sfx.py` 程序化合成到 `godot/assets/sfx/`，新增後要跑 `godot --headless --path godot --import`。
- **揮劍吹霧**：遠處的霧在鏡頭 8 m 內會淡出，濃霧的遠景又主要是距離霧，吹開也看不出來，所以霧天多一層貼地低霧（`ground_density`），風吹的主要是這層。範圍不能大：揮砍 11–16 m、下劈 8 m，再大就太誇張。在邊緣補霧反而會像憑空冒出一團霧。
- **敵人素材**：`godot/assets/chars/kaykit/` 是 KayKit Skeletons 1.0（CC0，授權檔在同目錄）。測試片：`REEL=interact tools/record.sh <名稱>`。
- **相關筆記**：beach3d-eval 的 `PLAYBOOK.md` 有 Tripo 與 Blender 的其他筆記。
