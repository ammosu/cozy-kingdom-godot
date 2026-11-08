# Cozy Kingdom

溫馨奇幻 3D 小遊戲的實驗專案，引擎是 Godot 4.7。回覆使用繁體中文台灣用語。

各步驟的完整指令與踩過的坑都在 `NOTES.md`，動手前先讀相關段落。

## 執行與檢查

```bash
godot --path godot --windowed --resolution 1600x900     # 玩遊戲
KINGDOM=proc godot --path godot --windowed --resolution 1600x900   # 切回程序化王國
godot --headless --path godot --import                  # 新增或更換 glb 後要跑
[REL=1] tools/shot.sh <名稱> "x,y,z" "x,y,z" [frames]   # 截圖到 shots/，REL=1 時 y 是離地高度
tools/record.sh <名稱>                                  # 錄示範影片到 video/
```

- 這個專案沒有自動測試，改動靠截圖驗證。截圖會短暫在桌面開視窗。
- 看效能要給 900 幀，前面幾百幀還在編譯 shader，數字會偏低（曾量到 51 fps，實際 146）。
- 城外地勢比城內高，鏡頭要貼近地面時用 `REL=1`，不然會拍到地底。

## 內容管線

| 內容 | 工具 | 輸出 |
|---|---|---|
| 角色 | `tools/tripo_chars.py` → `blender/merge_anims.py` | `godot/assets/chars/` |
| 建築、城牆、道具 | `tools/codex_sheet.sh` → `tools/hy_asset.sh`（清單 `assets3d/list.tsv`） | `assets3d/<名稱>/<名稱>.glb`，手動複製到 `godot/assets/props/` |
| 王國底圖 | `blender/gen_kingdom.py`（`--hy 1` 是不含建築的版本） | `godot/assets/kingdom_hy.glb`＋`kingdom_hy_layout.json` |
| 樹與灌木 | `blender/gen_trees.py` | `godot/assets/nature/` |
| 草花貼圖 | `tools/codex_sprites.sh` → `tools/prep_sprites.py` | `godot/assets/sprites/` |

`hy_asset.sh` 依賴本機其他專案：`~/git_project/ComfyUI`（要先開在 8188 port）、`~/git_project/Hunyuan3D-2.1`、`~/git_project/img2_3d/tools`。

## 程式慣例

- 生成模型的正面一律朝 +Z；`props.gd` 的 yaw 是正面要朝的角度。
- `props.setup()` 要在種草之前跑，草和灌木的射線才會避開模型。
- Blender 的物件名稱帶 `-col` 會產生碰撞。名稱以 `HiddenCol` 開頭的只留碰撞、畫面上隱藏，往下打的射線要跳過它們（見 `props.gd` 的 `_ground`）。
- 城牆用哪個模型、一節多長，由 `props.gd` 開頭的 `WALL_PIECE`、`WALL_PIECE_LEN` 決定。
- 要拿來重複拼接的模型做短一點、接近正方形，扁長物件在 Hunyuan 裡細節會糊掉。

## 規則

- Tripo 會花點數，呼叫前先問使用者；可以先用 `--dry-run`。
- 不要印出 `.env` 的內容（裡面有 `TRIPO_API_KEY`）。
- 顯示卡上有常駐的 voxcpm-api（約 7 GB），沒問過不要停掉。
- 停程序用 PID，不要用 `pkill -f`。
- 批次腳本用 bash 跑；zsh 的 `$names` 不會拆字。
- Hunyuan3D 2.1 Paint 模型限非商業用途，要商用得先換掉上色這一步。
