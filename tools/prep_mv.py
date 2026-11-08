"""四視角（透明背景）→ ComfyUI/input/mv/<名稱>-<視角>.png：1024 正方形、四張同一個縮放（以最高的那張為準）、底部對齊同一條地平線。
跟 img2_3d 的 prep_views.py 一樣的排法，但直接用 Codex 圖的 alpha，不跑 BiRefNet（白牆不會被當成背景切掉）。"""
import os, sys
import numpy as np
from PIL import Image
COMFY = os.path.expanduser("~/git_project/ComfyUI")
name, d = sys.argv[1], sys.argv[2]
R = 1024
views = {v: Image.open(f"{d}/{v}.png").convert("RGBA") for v in ("front", "left", "back", "right")}
H = max(im.height for im in views.values())
W = max(im.width for im in views.values())
s = (R / 1.1) / max(H, W)
for v, im in views.items():
    im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    out = Image.new("RGBA", (R, R), (0, 0, 0, 0))
    base = R - (R - R / 1.1) / 2
    out.paste(im, (round(R / 2 - im.width / 2), round(base - im.height)), im)
    out.save(f"{COMFY}/input/mv/{name}-{v}.png")
    print(v, im.size)
# Paint 的參考圖：白底 RGB（img2_3d 驗證過的輸入格式）
for v in ("front", "back", "left", "right"):
    im = Image.open(f"{d}/{v}.png").convert("RGBA")
    W2 = max(im.size) + 80
    bg = Image.new("RGBA", (W2, W2), (255, 255, 255, 255))
    bg.alpha_composite(im, ((W2 - im.width) // 2, (W2 - im.height) // 2))
    bg.convert("RGB").save(f"{d}/ref_{v}.png")
