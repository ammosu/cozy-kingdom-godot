"""把透明背景的四視角設計圖切成 front/left/back/right.png（RGBA，依 alpha 欄位切）。
沒有透明背景時退回用「接近白色」判斷前景（白牆會被吃掉，盡量避免）。"""
import sys
import numpy as np
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGBA"); out = sys.argv[2]
a = np.asarray(im).astype(int)
if a[..., 3].min() > 200:
    print("!! 沒有透明背景，改用白底判斷")
    fgpix = a[..., :3].min(2) < 235
else:
    fgpix = a[..., 3] > 32
cnt = fgpix.sum(0); fg = cnt > 2
runs, s = [], None
for x, f in enumerate(list(fg) + [False]):
    if f and s is None: s = x
    if not f and s is not None:
        if runs and s - runs[-1][1] < 15: runs[-1] = (runs[-1][0], x)
        else: runs.append((s, x))
        s = None
runs = [r for r in runs if r[1] - r[0] >= 40]
if len(runs) != 4:
    xs = np.nonzero(fg)[0]; q = (xs[-1] - xs[0]) / 4
    cuts = [xs[0]] + [int(xs[0] + i * q - q * 0.3 + np.argmin(cnt[int(xs[0] + i * q - q * 0.3):int(xs[0] + i * q + q * 0.3)])) for i in (1, 2, 3)] + [xs[-1]]
    print(f"found {len(runs)} figures, cutting at {cuts[1:4]}")
    runs = [(cuts[i], cuts[i + 1]) for i in range(4)]
for (x0, x1), v in zip(runs, ("front", "left", "back", "right")):
    c = np.asarray(im)[:, x0:x1].copy()
    if a[..., 3].min() > 200:
        c[..., 3] = np.where(fgpix[:, x0:x1], 255, 0)
    ys = np.nonzero((c[..., 3] > 32).any(1))[0]
    c = c[ys[0]:ys[-1] + 1]
    Image.fromarray(c).save(f"{out}/{v}.png")
    print(v, c.shape[1], "x", c.shape[0])
