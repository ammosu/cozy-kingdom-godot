"""Paint 烘出來的貼圖後處理（用 Hunyuan venv 跑，要 cv2）：
- 補洞：四張視角都看不到的縫隙會留下近黑的小斑點，遠看就是「破洞」。只補面積小的黑斑，大塊的暗部（門、窗）不動。
- 銳化：多視角投影混合後偏糊，做一次輕度 unsharp mask。
用法：python post_texture.py <貼圖路徑>
"""
import os
import sys
import cv2
import numpy as np

p = sys.argv[1]
img = cv2.imread(p, cv2.IMREAD_COLOR)
v = img.max(axis=2)
mask = (v < 62).astype(np.uint8)   # 深褐色的凹坑也算，遠看一樣像破洞
n, labels, stats, _ = cv2.connectedComponentsWithStats(mask, connectivity=8)
keep = np.zeros_like(mask)
for i in range(1, n):
    if stats[i, cv2.CC_STAT_AREA] < 520:   # 2048 貼圖上約 23×23 以內；窗洞、門洞比這大，不會被補掉
        keep[labels == i] = 1
filled = int(keep.sum())
if filled:
    img = cv2.inpaint(img, cv2.dilate(keep, np.ones((3, 3), np.uint8)), 4, cv2.INPAINT_TELEA)
if not os.environ.get("NO_SHARPEN"):   # 對已處理過的貼圖重跑時要關掉，銳化兩次會出現白邊
    blur = cv2.GaussianBlur(img, (0, 0), 2.2)
    img = cv2.addWeighted(img, 1.55, blur, -0.55, 0)
cv2.imwrite(p, img, [cv2.IMWRITE_JPEG_QUALITY, 95])
print(f"post_texture: filled {filled}px of {n - 1} dark spots")
