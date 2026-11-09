"""textures/src/*.png（Codex 生成）→ godot/assets/tex/<名>.png（保證無縫）＋ <名>_n.png（由亮度推算的法線貼圖）

無縫處理：把圖平移半張，用中央十字羽化遮罩混回原圖，接縫被移到圖中央並被原圖蓋掉。
用法：python3 tools/prep_textures.py
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SRC, OUT = ROOT / "textures" / "src", ROOT / "godot" / "assets" / "tex"
OUT.mkdir(parents=True, exist_ok=True)
NEUTRAL = {"plaster": 238.0, "roof_tiles": 215.0}
COLOR_ADJUST = {"gate_stone": (0.85, 1.05)}
STRENGTH = {"cobblestone": 3.0, "stone_wall": 3.0, "gate_stone": 3.0, "roof_tiles": 2.5, "wood_planks": 1.5, "plaster": 1.0, "dirt_path": 1.5, "grass_ground": 1.0}


def seam_score(a):
    return float(np.abs(a[:, 0] - a[:, -1]).mean() + np.abs(a[0] - a[-1]).mean())


def make_tileable(a):
    h, w = a.shape[:2]
    shifted = np.roll(np.roll(a, h // 2, 0), w // 2, 1)
    yy, xx = np.mgrid[0:h, 0:w]
    # 遮罩：靠近原圖邊緣（=平移後的中央十字以外）用平移圖，中央十字用原圖
    dx = np.abs(xx - w / 2) / (w / 2)
    dy = np.abs(yy - h / 2) / (h / 2)
    edge = np.clip((np.maximum(dx, dy) - 0.55) / 0.35, 0, 1)
    edge = edge * edge * (3 - 2 * edge)
    m = edge[..., None]
    return a * (1 - m) + shifted * m


def normal_map(rgb, strength):
    g = np.asarray(Image.fromarray(rgb.astype(np.uint8)).convert("L").filter(ImageFilter.GaussianBlur(1.2)), dtype=np.float32) / 255
    dx = (np.roll(g, -1, 1) - np.roll(g, 1, 1)) * strength
    dy = (np.roll(g, -1, 0) - np.roll(g, 1, 0)) * strength
    n = np.dstack([-dx, dy, np.ones_like(g)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)


for p in sorted(SRC.glob("*.png")):
    a = np.asarray(Image.open(p).convert("RGB").resize((1024, 1024), Image.LANCZOS), dtype=np.float32)
    if p.stem in COLOR_ADJUST:   # [飽和度, 亮度]：讓材質的色調接近旁邊的模型
        sat, gain = COLOR_ADJUST[p.stem]
        a = np.clip((a.mean(axis=2, keepdims=True) * (1 - sat) + a * sat) * gain, 0, 255)
    before = seam_score(a)
    if before > 6:
        t = make_tileable(a)
        if seam_score(t) < before:   # 木板這種直條紋，平移反而對不齊，保留原圖
            a = t
    if p.stem in NEUTRAL:   # 會在遊戲內染色的貼圖：去飽和、亮度拉到固定平均，顏色交給材質底色
        lum = a @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
        lum = lum * (NEUTRAL[p.stem] / lum.mean())
        a = np.clip(np.repeat(lum[..., None], 3, 2), 0, 255)
    Image.fromarray(a.astype(np.uint8)).save(OUT / p.name)
    Image.fromarray(normal_map(a, STRENGTH.get(p.stem, 1.5))).save(OUT / f"{p.stem}_n.png")
    print(f"{p.stem:14} seam {before:5.1f} → {seam_score(a):5.1f}")
