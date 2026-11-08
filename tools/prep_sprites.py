"""Codex 植物元件後處理：textures/sprites/raw/*.png → godot/assets/sprites/<name>.png
- 沒有真透明背景（alpha 最小值 > 200）就退件
- 依 alpha 裁邊（底部不留空白，讓草根貼地），長邊縮到 512
- 透明區的顏色往外擴（color bleed），避免 mipmap 後邊緣出現白邊／黑邊
- 印出可見部分的寬高比，給 Godot 決定面片比例
"""
import sys, json
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "textures" / "sprites" / "raw"
OUT = ROOT / "godot" / "assets" / "sprites"
OUT.mkdir(parents=True, exist_ok=True)
meta = {}
for src in sorted(RAW.glob("*.png")):
    im = Image.open(src).convert("RGBA")
    a = np.array(im)[..., 3]
    if a.min() > 200:
        print(f"!! {src.stem}: 沒有透明背景"); continue
    ys, xs = np.where(a > 16)
    pad = 4
    im = im.crop((max(xs.min() - pad, 0), max(ys.min() - pad, 0), min(xs.max() + pad, im.width), min(ys.max() + 1, im.height)))
    s = min(1.0, 512 / max(im.size))
    if s < 1:
        im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    arr = np.array(im).astype(np.float32)
    rgb, al = arr[..., :3], arr[..., 3:] / 255.0
    # color bleed：用 alpha 加權模糊把顏色擴到透明區
    filled = rgb.copy()
    w = al[..., 0].copy()
    for r in (2, 6, 16, 40):
        num = np.array(Image.fromarray(np.uint8(np.clip(rgb * al, 0, 255))).filter(ImageFilter.GaussianBlur(r)), dtype=np.float32)
        den = np.array(Image.fromarray(np.uint8(al[..., 0] * 255)).filter(ImageFilter.GaussianBlur(r)), dtype=np.float32)[..., None] / 255.0
        est = num / np.maximum(den, 1e-3)
        mask = (w < 0.5) & (den[..., 0] > 0.02)
        filled[mask] = est[mask]
        w = np.maximum(w, (den[..., 0] > 0.02).astype(np.float32))
    out = np.dstack([np.clip(np.where(al > 0.5, rgb, filled), 0, 255), arr[..., 3]]).astype(np.uint8)
    Image.fromarray(out).save(OUT / f"{src.stem}.png", optimize=True)
    meta[src.stem] = round(im.width / im.height, 3)
    print(f"ok {src.stem}: {im.size} aspect {meta[src.stem]} alpha-cover {(a > 128).mean():.2f}")
(OUT / "sprites.json").write_text(json.dumps(meta))
