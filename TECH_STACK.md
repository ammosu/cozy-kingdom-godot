# Cozy Kingdom 使用清單

這份文件整理本專案用到的工具、AI 服務、素材來源與遊戲技術。操作指令和踩過的坑在 `NOTES.md`，第三方素材的逐項來源在 `CREDITS.md`。

## 一覽

| 類別 | 使用項目 | 用途 |
|---|---|---|
| 遊戲引擎 | Godot 4.7（Forward+） | 遊戲本體、算繪、物理、錄影 |
| 3D 製作 | Blender 5.2（Python 腳本、無介面執行） | 王國底圖、樹木、劍、合併動作、模型修補 |
| AI 角色 | Tripo（`tripo3d` Python SDK） | 圖轉 3D、自動綁骨、套用動作 |
| AI 建築與道具 | Hunyuan3D 2.0 MV、Hunyuan3D 2.1 Paint、ComfyUI | 形狀生成與上色 |
| AI 圖片 | Codex CLI 內建 image generation | 概念圖、材質、草花貼圖、四視角設計圖 |
| AI 評審 | Codex CLI | 依 `eval/rubric.md` 對固定鏡頭截圖評分 |
| 開發協作 | Claude Code | 程式、腳本、調校與驗證 |
| 圖片處理 | Python、NumPy、Pillow、OpenCV | 無縫化、法線貼圖、去背與顏色外擴 |
| 影片處理 | Godot Movie Maker、FFmpeg | 逐格錄影、裁黑場、壓縮、縮圖總表 |

## 內容是怎麼做出來的

| 內容 | 做法 | 主要檔案 |
|---|---|---|
| 主角、獾、蒼鷺、麋鹿 | Codex 概念圖 → Tripo 建模、綁骨、動作 → Blender 合併動作 | `concept/`、`tools/tripo_chars.py`、`blender/merge_anims.py` |
| 房屋、攤位、噴水池、塔樓、城門、主堡、城牆等 26 項 | Codex 四視角圖 → Hunyuan 2.0 MV 形狀 → 減面 → Hunyuan 2.1 Paint 上色 | `assets3d/list.tsv`、`tools/codex_sheet.sh`、`tools/hy_asset.sh` |
| 地形、道路、王國配置 | Blender 程序化生成 | `blender/gen_kingdom.py` |
| 闊葉樹、松樹、灌木 | Blender 程序化生成，樹冠貼葉簇卡片 | `blender/gen_trees.py`、`godot/scripts/nature.gd` |
| 草、花、蕨類、葉簇、粒子 | Codex 透明圖貼在交叉面片上 | `textures/sprites/list.tsv`、`tools/codex_sprites.sh`、`tools/prep_sprites.py` |
| 地面、石牆、屋瓦、木板等材質 | Codex 生成後無縫化，並產生法線貼圖 | `textures/src/`、`tools/prep_textures.py` |
| 茅草屋、木屋、工作桌、熔爐、狐狸、岩石 | Scenario 3D Collection，減面並縮小貼圖 | `CREDITS.md`、`blender/prep_scenario.py` |
| 骷髏敵人與刀 | KayKit Skeletons 1.0，內建 95 個動作 | `godot/assets/chars/kaykit/` |
| 劍 | Blender 程序化生成 | `blender/gen_sword.py` |
| 揮劍與命中音效 | Python 標準函式庫程序化合成 | `tools/gen_sfx.py` |

## 第三方素材與授權

| 項目 | 授權 | 注意事項 |
|---|---|---|
| KayKit Skeletons 1.0（Kay Lousberg） | CC0 | 不需標註，授權檔在 `godot/assets/chars/kaykit/LICENSE.txt` |
| Scenario 3D Collection | CC BY 4.0 | 必須標註出處，並說明有修改，見 `CREDITS.md` |
| Hunyuan3D 2.1 Paint | 限非商業用途 | **遊戲內 Hunyuan 上色的建築與道具不能直接商用** |
| Godot | MIT | 引擎本身可商用 |

商用或公開發行前，還要另外確認以下幾項，本專案尚未查證：

- Tripo 產出模型的使用權，可能依付費方案不同。
- Codex 生成圖片的使用條款。
- Hunyuan3D 2.0 形狀模型的授權範圍。

## 遊戲技術

**算繪**
- SDFGI 全域光照、SSAO、Glow、AgX 色調映射、體積霧。
- 自製 shader：地形、草花卡片、樹冠、攤位布料、噴水池的水與水柱、霧。
- 三種霧氣預設：平常、晨霧、濃霧。

**植被與環境**
- 約 31 萬叢地被，用 MultiMesh 繪製。
- 草的擺動與草高成比例，並有風浪掃過。
- 角色走過會推開草，腳印處慢慢彈回。
- 霧分成高層霧與貼地低霧，濃度會隨時間緩慢起伏。

**戰鬥與手感**
- 三段連擊與跳起下劈，動作由程序化骨架姿勢疊加。
- 命中時只暫停當事人（卡肉），並有鏡頭晃動與 FOV 內縮、程序化受擊、火花與刀光。
- 劍可以砍草，被砍的草約半分鐘後長回來。
- 揮砍吹出一段霧的通道；下劈產生環形衝擊波，霧從外圍回流。

**其他**
- 第三人稱操作、跳躍、麋鹿坐騎、村民走動與軟碰撞。

## 驗證方式

| 方式 | 指令或位置 |
|---|---|
| 實機自我測試 | `SELFTEST=1 godot --path godot --windowed --resolution 1600x900` |
| 固定鏡頭截圖 | `tools/shot.sh` |
| 展示影片 | `REEL=1 tools/record.sh <名稱>` |
| 互動測試片 | `REEL=interact tools/record.sh <名稱>` |
| 分區評分 | `tools/eval_round.sh <輪次>` |

## 參考來源

- 製作流程：X 貼文（dhruvalgolakiya，2026-11-07）。
- 打擊感：YouTube 影片（水蛭JogsLeech，`Nwa-zMRWDXM`），只參考設計方法，沒有使用影片內容。分析時用到 yt-dlp 與 faster-whisper，這兩項不在專案內。
