"""程序化生成城牆王國 → godot/assets/kingdom.glb ＋ godot/assets/kingdom_layout.json

blender -b -P blender/gen_kingdom.py -- [--seed 7] [--houses 70]

座標：Blender Z 向上、單位公尺；glTF 匯出後在 Godot 是 Y 向上（Blender (x, y, z) → Godot (x, z, -y)）。
物件名稱帶 -col 的，Godot 匯入時自動產生 trimesh 碰撞。
"""
import bpy, bmesh, json, math, random, sys
from mathutils import Vector, noise
from pathlib import Path

ROOT = Path(bpy.path.abspath("//")).parent if bpy.data.filepath else Path(__file__).resolve().parent.parent
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
opt = {argv[i].lstrip("-"): argv[i + 1] for i in range(0, len(argv) - 1, 2)}
SEED = int(opt.get("seed", 7))
N_HOUSES = int(opt.get("houses", 70))
rng = random.Random(SEED)

WALL_R = 58.0        # 城牆半徑
WALL_H = 7.0
WALL_SEG = 14        # 城牆邊數（每個頂點一座塔）
FLAT_R = WALL_R + 6  # 這半徑內地面全平
TERRAIN = 720.0
KEEP = Vector((0, 32, 0))
PLAZA = Vector((0, -8, 0))
PLAZA_R = 13.0
GATE_ANGLE = -math.pi / 2  # 南門

# ---------- 場景清空 ----------
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# ---------- 材質 ----------
MATS = {}


def mat(name, rgb, rough=0.85, metal=0.0):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    MATS[name] = m
    return m


def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


M = {
    "grass": mat("Grass", srgb("#7fae4e"), 0.95),
    "dirt": mat("Dirt", srgb("#b99467"), 0.95),
    "cobble": mat("Cobble", srgb("#a79f93"), 0.9),
    "stone": mat("Stone", srgb("#c9c0ae"), 0.9),
    "stone_dark": mat("StoneDark", srgb("#8d8678"), 0.9),
    "roof_blue": mat("RoofBlue", srgb("#4f6fa8"), 0.7),
    "timber": mat("Timber", srgb("#5b3a24"), 0.8),
    "window": mat("Window", srgb("#ffd889"), 0.4),
    "door": mat("Door", srgb("#6e4429"), 0.8),
    "water": mat("Water", srgb("#5aa6c9"), 0.15),
}
WALL_COLORS = ["#f1e3c6", "#f4d6b8", "#e9e1d3", "#f2ccc0", "#e3e8d0", "#f6e9a8"]
ROOF_COLORS = ["#c2553e", "#d0743c", "#8a4f3a", "#5f7fa8", "#6f8f55", "#a8463f"]
CLOTH_COLORS = ["#e9c46a", "#e76f51", "#2a9d8f", "#f4a3a8", "#ffffff", "#8ab6d6"]


# ---------- 幾何工具：所有零件寫進「分類 bmesh」，最後每類一個物件 ----------
class Bucket:
    def __init__(self, name):
        self.name, self.bm, self.mats = name, bmesh.new(), []
        self.uv = self.bm.loops.layers.uv.new("UVMap")

    def mi(self, m):
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def add(self, verts, faces, m):
        idx = self.mi(m)
        vs = [self.bm.verts.new(v) for v in verts]
        for f in faces:
            try:
                face = self.bm.faces.new([vs[i] for i in f])
            except ValueError:
                continue
            face.material_index = idx
            # UV（單位：公尺）：近水平面用 xy；其餘用「水平切線 × 沿坡向上」，牆與屋頂斜面都對齊自己的方向
            pts = [Vector(verts[i]) for i in f]
            n = (pts[1] - pts[0]).cross(pts[2] - pts[0])
            if n.length < 1e-9 and len(pts) > 3:
                n = (pts[2] - pts[0]).cross(pts[3] - pts[0])
            n = n.normalized() if n.length > 1e-9 else Vector((0, 0, 1))
            if abs(n.z) > 0.97:
                proj = lambda p: (p.x, p.y)
            else:
                t = Vector((-n.y, n.x, 0)).normalized()
                b = n.cross(t)
                if b.z < 0:
                    b = -b
                proj = lambda p, t=t, b=b: (p.dot(t), p.dot(b))
            for loop in face.loops:
                loop[self.uv].uv = proj(loop.vert.co)

    def obj(self, recalc=True):
        me = bpy.data.meshes.new(self.name)
        if recalc:
            bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        self.bm.to_mesh(me)
        for m in self.mats:
            me.materials.append(m)
        ob = bpy.data.objects.new(self.name, me)
        scene.collection.objects.link(ob)
        return ob


BOX_F = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]


def box(b, c, size, m, rot=0.0):
    """c：底面中心；size：(x, y, z)；rot：繞 Z 旋轉。"""
    sx, sy, sz = size[0] / 2, size[1] / 2, size[2]
    cs, sn = math.cos(rot), math.sin(rot)
    pts = []
    for z in (0, sz):
        for x, y in ((-sx, -sy), (sx, -sy), (sx, sy), (-sx, sy)):
            pts.append((c[0] + x * cs - y * sn, c[1] + x * sn + y * cs, c[2] + z))
    b.add(pts, BOX_F, m)


def cyl(b, c, r, h, m, n=12, r_top=None):
    r_top = r if r_top is None else r_top
    pts = [(c[0] + r * math.cos(2 * math.pi * i / n), c[1] + r * math.sin(2 * math.pi * i / n), c[2]) for i in range(n)]
    pts += [(c[0] + r_top * math.cos(2 * math.pi * i / n), c[1] + r_top * math.sin(2 * math.pi * i / n), c[2] + h) for i in range(n)]
    faces = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    faces.append(tuple(range(n - 1, -1, -1)))
    if r_top > 0:
        faces.append(tuple(range(n, 2 * n)))
    b.add(pts, faces, m)


def cone(b, c, r, h, m, n=12):
    pts = [(c[0] + r * math.cos(2 * math.pi * i / n), c[1] + r * math.sin(2 * math.pi * i / n), c[2]) for i in range(n)]
    pts.append((c[0], c[1], c[2] + h))
    faces = [(i, (i + 1) % n, n) for i in range(n)] + [tuple(range(n - 1, -1, -1))]
    b.add(pts, faces, m)


def gable(b, c, w, d, h, m, rot, overhang=0.35):
    """人字屋頂：屋脊沿本地 x 軸。c 為簷口高度的中心。"""
    sx, sy = w / 2 + overhang, d / 2 + overhang
    cs, sn = math.cos(rot), math.sin(rot)
    T = lambda x, y, z: (c[0] + x * cs - y * sn, c[1] + x * sn + y * cs, c[2] + z)
    t = 0.18
    pts = [T(-sx, -sy, 0), T(sx, -sy, 0), T(sx, 0, h), T(-sx, 0, h), T(-sx, sy, 0), T(sx, sy, 0),
           T(-sx, -sy, t), T(sx, -sy, t), T(sx, 0, h + t), T(-sx, 0, h + t), T(-sx, sy, t), T(sx, sy, t)]
    faces = [(6, 7, 8, 9), (9, 8, 11, 10),  # 上表面
             (0, 3, 2, 1), (3, 4, 5, 2),    # 下表面
             (0, 1, 7, 6), (4, 10, 11, 5), (1, 2, 8, 7), (2, 5, 11, 8), (0, 6, 9, 3), (3, 9, 10, 4)]
    b.add(pts, faces, m)


def gable_end(b, c, w, d, h, m, rot):
    """山牆三角形（牆面材質），填人字屋頂兩端。"""
    cs, sn = math.cos(rot), math.sin(rot)
    T = lambda x, y, z: (c[0] + x * cs - y * sn, c[1] + x * sn + y * cs, c[2] + z)
    for x in (-w / 2, w / 2):
        pts = [T(x, -d / 2, 0), T(x, d / 2, 0), T(x, 0, h)]
        b.add(pts, [(0, 1, 2), (2, 1, 0)], m)


def hip(b, c, w, d, h, m, rot, overhang=0.35):
    sx, sy = w / 2 + overhang, d / 2 + overhang
    cs, sn = math.cos(rot), math.sin(rot)
    T = lambda x, y, z: (c[0] + x * cs - y * sn, c[1] + x * sn + y * cs, c[2] + z)
    rx = max(sx - sy, 0.05)
    pts = [T(-sx, -sy, 0), T(sx, -sy, 0), T(sx, sy, 0), T(-sx, sy, 0), T(-rx, 0, h), T(rx, 0, h)]
    faces = [(0, 1, 5, 4), (2, 3, 4, 5), (1, 2, 5), (3, 0, 4), (3, 2, 1, 0)]
    b.add(pts, faces, m)


# ---------- 地形 ----------
def ground_h(x, y):
    r = math.hypot(x, y)
    if r < FLAT_R:
        return 0.0
    k = min((r - FLAT_R) / 30.0, 1.0)
    k = k * k * (3 - 2 * k)
    # 南門大道走廊（x≈0, y<0）整平，越遠越放開
    if y < 0:
        c = min(max((abs(x) - 5.0) / 14.0, 0.0), 1.0)
        c = c * c * (3 - 2 * c)
        far = min(max((r - 115.0) / 40.0, 0.0), 1.0)
        k *= max(c, far)
    n = noise.noise(Vector((x / 45, y / 45, SEED * 0.37))) * 9 + noise.noise(Vector((x / 14, y / 14, 3.1))) * 1.6
    hills = max(r - 160.0, 0.0) ** 1.35 * 0.09 * (1.0 + noise.noise(Vector((x / 90, y / 90, 9.0))))   # 遠方山丘
    return k * (n + 2.5 + (r - FLAT_R) * 0.06 + hills)


def build_terrain():
    b = Bucket("Terrain-col")
    n = 220
    step = TERRAIN / n
    grid = []
    for j in range(n + 1):
        for i in range(n + 1):
            x, y = -TERRAIN / 2 + i * step, -TERRAIN / 2 + j * step
            grid.append((x, y, ground_h(x, y)))
    faces = [(j * (n + 1) + i, j * (n + 1) + i + 1, (j + 1) * (n + 1) + i + 1, (j + 1) * (n + 1) + i) for j in range(n) for i in range(n)]
    b.add(grid, faces, M["grass"])
    t = b.obj(recalc=False)   # 開放網格不重算法線，避免整片翻成朝下（Godot 碰撞只吃正面）
    pond = Bucket("Pond")
    cyl(pond, (-80, 60, ground_h(-80, 60) + 0.05), 9, 0.02, M["water"], n=20)
    pond.obj()
    return t


# ---------- 道路 ----------
ROADS = []  # (起點, 終點, 寬度)


def road(b, a, c, w, m):
    a, c = Vector(a), Vector(c)
    d = (c - a)
    L = d.length
    rot = math.atan2(d.y, d.x)
    mid = (a + c) / 2
    box(b, (mid.x, mid.y, 0.0), (L + w * 0.5, w, 0.04), m, rot)
    ROADS.append((a.to_2d(), c.to_2d(), w))


def build_roads():
    b = Bucket("Roads")
    gate = Vector((WALL_R * math.cos(GATE_ANGLE), WALL_R * math.sin(GATE_ANGLE), 0))
    road(b, gate * 2.0, PLAZA, 6, M["cobble"])          # 南門大道（延伸到城外）
    road(b, PLAZA, KEEP - Vector((0, 9, 0)), 6, M["cobble"])  # 往城堡
    for ang in (0, math.pi):                            # 東西街
        e = Vector((math.cos(ang), math.sin(ang), 0)) * (WALL_R - 6)
        road(b, PLAZA, e + Vector((0, -8, 0)), 4.5, M["cobble"])
    # 環城內街（多邊形）
    R2 = WALL_R - 9
    pts = [Vector((R2 * math.cos(2 * math.pi * i / 16), R2 * math.sin(2 * math.pi * i / 16), 0)) for i in range(16)]
    for i in range(16):
        road(b, pts[i], pts[(i + 1) % 16], 3.6, M["dirt"])
    # 斜街
    for ang in (math.radians(35), math.radians(145), math.radians(215), math.radians(325)):
        e = Vector((math.cos(ang), math.sin(ang), 0)) * R2
        road(b, PLAZA + (e - PLAZA).normalized() * PLAZA_R, e, 3.2, M["dirt"])
    cyl(b, (PLAZA.x, PLAZA.y, 0.0), PLAZA_R, 0.05, M["cobble"], n=24)
    return b.obj(), gate


def dist_to_roads(p):
    best = 1e9
    for a, c, w in ROADS:
        ab = c - a
        t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
        best = min(best, (p - (a + ab * t)).length - w / 2)
    return best


def nearest_road_dir(p):
    best, dirv = 1e9, Vector((0, 1))
    for a, c, w in ROADS:
        ab = c - a
        t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
        q = a + ab * t
        d = (p - q).length
        if d < best:
            best, dirv = d, (q - p)
    return dirv.normalized() if dirv.length > 1e-6 else Vector((0, 1))


# ---------- 城牆、塔、城門 ----------
def build_walls():
    b = Bucket("Walls-col")
    roofs = Bucket("TowerRoofs")
    verts = [Vector((WALL_R * math.cos(GATE_ANGLE + 2 * math.pi * i / WALL_SEG),
                     WALL_R * math.sin(GATE_ANGLE + 2 * math.pi * i / WALL_SEG), 0)) for i in range(WALL_SEG)]
    for i in range(WALL_SEG):
        a, c = verts[i], verts[(i + 1) % WALL_SEG]
        d = c - a
        rot = math.atan2(d.y, d.x)
        L = d.length
        dirn = d.normalized()
        if i == 0 or i == WALL_SEG - 1:
            pass
        # 城門在 verts[0]（南）兩側各留 4 m 缺口
        start, end = 0.0, L
        if i == 0:
            start = 4.0
        if i == WALL_SEG - 1:
            end = L - 4.0
        seg_a, seg_c = a + dirn * start, a + dirn * end
        mid = (seg_a + seg_c) / 2
        box(b, (mid.x, mid.y, 0), ((seg_c - seg_a).length, 2.4, WALL_H), M["stone"], rot)
        # 城垛
        k = int((seg_c - seg_a).length / 1.6)
        nrm = Vector((-dirn.y, dirn.x, 0))
        for j in range(k):
            if j % 2:
                continue
            p = seg_a + dirn * (0.8 + j * 1.6)
            for side in (-1, 1):
                q = p + nrm * side * 1.0
                box(b, (q.x, q.y, WALL_H), (0.8, 0.4, 0.8), M["stone"], rot)
    for i, v in enumerate(verts):
        if i == 0:
            continue
        cyl(b, (v.x, v.y, 0), 3.4, WALL_H + 4, M["stone"], n=14)
        cyl(b, (v.x, v.y, WALL_H + 4), 3.8, 0.6, M["stone_dark"], n=14)
        cone(roofs, (v.x, v.y, WALL_H + 4.6), 4.2, 5.5, M["roof_blue"], n=14)
    # 城門樓
    g = verts[0]
    tang = math.atan2(math.cos(GATE_ANGLE), -math.sin(GATE_ANGLE))  # 牆切線方向
    tx, ty = math.cos(tang), math.sin(tang)
    for side in (-1, 1):
        p = (g.x + tx * side * 5.5, g.y + ty * side * 5.5, 0)
        box(b, p, (4, 6, WALL_H + 5), M["stone"], tang)
        hip(roofs, (p[0], p[1], WALL_H + 5), 4, 6, 3.5, M["roof_blue"], tang)
    box(b, (g.x, g.y, WALL_H - 0.5), (7.2, 5, 3.0), M["stone"], tang)  # 門洞上方的橋
    box(b, (g.x, g.y, WALL_H + 2.5), (7.2, 5, 0.4), M["stone_dark"], tang)
    return b.obj(), roofs.obj(), [list(v) for v in verts]


# ---------- 城堡（keep） ----------
def build_keep():
    b = Bucket("Keep-col")
    r = Bucket("KeepRoofs")
    k = KEEP
    box(b, (k.x, k.y, 0), (20, 18, 2.5), M["stone_dark"])           # 基座
    box(b, (k.x, k.y, 2.5), (16, 14, 13), M["stone"])
    hip(r, (k.x, k.y, 15.5), 16, 14, 6, M["roof_blue"], 0)
    for dx in (-8, 8):
        for dy in (-7, 7):
            cyl(b, (k.x + dx, k.y + dy, 0), 2.8, 19, M["stone"], n=14)
            cone(r, (k.x + dx, k.y + dy, 19), 3.4, 6.5, M["roof_blue"], n=14)
    cyl(b, (k.x, k.y, 15.5), 2.6, 9, M["stone"], n=14)   # 中央尖塔
    cone(r, (k.x, k.y, 24.5), 3.2, 8, M["roof_blue"], n=14)
    box(b, (k.x, k.y - 7.05, 2.5), (3, 0.3, 4.5), M["door"])
    for x in (-5, -2, 2, 5):
        for z in (7, 11):
            box(b, (k.x + x, k.y - 7.08, 2.5 + z - 1), (0.9, 0.2, 1.6), M["window"])
    # 旗子
    box(b, (k.x, k.y, 32.5), (0.15, 0.15, 3), M["timber"])
    box(r, (k.x + 0.9, k.y, 34.6), (1.6, 0.05, 0.9), mat("Banner", srgb("#e9c46a"), 0.8))
    return b.obj(), r.obj()


# ---------- 民宅：26 種設計由參數組合而來 ----------
def house_designs(n=26):
    ds = []
    for i in range(n):
        r = random.Random(SEED * 100 + i)
        ds.append(dict(
            w=r.choice([5.0, 6.0, 7.0, 8.0]), d=r.choice([4.5, 5.5, 6.0]),
            floors=r.choice([1, 2, 2, 3]), fh=r.uniform(2.6, 3.0),
            wall=r.choice(WALL_COLORS), roof=r.choice(ROOF_COLORS),
            style=r.choice(["gable", "gable", "hip"]), timber=r.random() < 0.6,
            jetty=r.random() < 0.4, chimney=r.random() < 0.6, roof_h=r.uniform(2.2, 3.6),
            window_boxes=r.random() < 0.5, shutters=r.random() < 0.5,
            shutter_color=r.choice(["#3d6e8f", "#5c8a4f", "#8f3d3d", "#d9a441"]), sign=r.random() < 0.25))
    return ds


def build_house(walls, roofs, trim, p, rot, ds):
    mw = mat("Wall_" + ds["wall"], srgb(ds["wall"]))
    mr = mat("Roof_" + ds["roof"], srgb(ds["roof"]), 0.75)
    w, d, fh = ds["w"], ds["d"], ds["fh"]
    cs, sn = math.cos(rot), math.sin(rot)
    L = lambda x, y, z=0: (p.x + x * cs - y * sn, p.y + x * sn + y * cs, z)
    box(walls, L(0, 0), (w + 0.4, d + 0.4, 0.5), M["stone_dark"], rot)     # 石基
    z = 0.5
    for f in range(ds["floors"]):
        grow = 0.35 if (ds["jetty"] and f > 0) else 0.0
        ww, dd = w + grow * 2, d + grow * 2
        box(walls, L(0, 0, z), (ww, dd, fh), mw, rot)
        if ds["timber"] and (f > 0 or ds["floors"] == 1):
            for face_rot, half_w, half_d in ((0, ww, dd), (math.pi, ww, dd), (math.pi / 2, dd, ww), (-math.pi / 2, dd, ww)):
                cs2, sn2 = math.cos(face_rot), math.sin(face_rot)
                F = lambda x, y, zz, cs2=cs2, sn2=sn2: L(x * cs2 - y * sn2, x * sn2 + y * cs2, zz)
                for x in [-half_w / 2 + 0.06 + i * (half_w - 0.12) / 3 for i in range(4)]:
                    box(trim, F(x, -half_d / 2 - 0.03, z), (0.18, 0.08, fh), M["timber"], rot + face_rot)
                box(trim, F(0, -half_d / 2 - 0.03, z + fh - 0.18), (half_w, 0.09, 0.18), M["timber"], rot + face_rot)
                box(trim, F(0, -half_d / 2 - 0.03, z), (half_w, 0.09, 0.18), M["timber"], rot + face_rot)
        # 窗：四面都開（正面最多、側面背面少一點）；門只在正面一樓
        for face_rot, fw, fd, front in ((0, ww, dd, True), (math.pi, ww, dd, False), (math.pi / 2, dd, ww, False), (-math.pi / 2, dd, ww, False)):
            cs2, sn2 = math.cos(face_rot), math.sin(face_rot)
            F = lambda x, y, zz, cs2=cs2, sn2=sn2: L(x * cs2 - y * sn2, x * sn2 + y * cs2, zz)
            R = rot + face_rot
            nwin = max(1, int(fw // 2.4)) if front else int(fw // 3.2)
            for i in range(nwin):
                x = -fw / 2 + (i + 0.5) * fw / nwin
                if front and f == 0 and i == nwin // 2:
                    box(trim, F(x, -fd / 2 - 0.04, z), (1.1, 0.12, 2.0), M["door"], R)
                    box(trim, F(x, -fd / 2 - 0.1, z + 2.0), (1.5, 0.2, 0.18), M["timber"], R)     # 門楣
                    for sx in (-0.65, 0.65):
                        box(trim, F(x + sx, -fd / 2 - 0.1, z), (0.16, 0.2, 2.0), M["timber"], R)
                    box(walls, F(x, -fd / 2 - 0.45, 0.0), (1.6, 0.7, 0.5), M["stone_dark"], R)    # 台階
                    if ds["sign"]:
                        box(trim, F(x + 1.0, -fd / 2 - 0.55, z + 2.35), (0.06, 0.9, 0.06), M["timber"], R)
                        box(trim, F(x + 1.0, -fd / 2 - 0.85, z + 1.75), (0.05, 0.6, 0.5), mat("Sign", srgb("#e9c46a"), 0.7), R)
                    continue
                y0 = -fd / 2
                box(trim, F(x, y0 - 0.02, z + 0.9), (0.8, 0.1, 1.1), M["window"], R)
                box(trim, F(x, y0 - 0.12, z + 0.8), (1.1, 0.2, 0.1), M["timber"], R)       # 窗台
                box(trim, F(x, y0 - 0.08, z + 1.98), (1.04, 0.14, 0.12), M["timber"], R)   # 上框
                for sx in (-0.46, 0.46):
                    box(trim, F(x + sx, y0 - 0.08, z + 0.9), (0.1, 0.14, 1.1), M["timber"], R)  # 側框
                box(trim, F(x, y0 - 0.07, z + 0.9), (0.06, 0.1, 1.1), M["timber"], R)       # 窗格
                box(trim, F(x, y0 - 0.07, z + 1.42), (0.8, 0.1, 0.06), M["timber"], R)
                if ds["shutters"]:
                    ms = mat("Shutter_" + ds["shutter_color"], srgb(ds["shutter_color"]), 0.8)
                    for sx in (-0.82, 0.82):
                        box(trim, F(x + sx, y0 - 0.09, z + 0.88), (0.5, 0.06, 1.14), ms, R)
                if ds["window_boxes"] and f > 0 and front:
                    box(trim, F(x, y0 - 0.3, z + 0.65), (0.95, 0.35, 0.25), mat("Flowers", srgb("#d9506b"), 0.9), R)
        z += fh
    top_w = w + (0.7 if ds["jetty"] and ds["floors"] > 1 else 0)
    top_d = d + (0.7 if ds["jetty"] and ds["floors"] > 1 else 0)
    if ds["style"] == "gable":
        gable(roofs, L(0, 0, z), top_w, top_d, ds["roof_h"], mr, rot)
        gable_end(walls, L(0, 0, z), top_w, top_d, ds["roof_h"], mw, rot)
    else:
        hip(roofs, L(0, 0, z), top_w, top_d, ds["roof_h"], mr, rot)
    if ds["chimney"]:
        box(walls, L(top_w * 0.28, top_d * 0.18, z), (0.7, 0.7, ds["roof_h"] + 0.8), M["stone_dark"], rot)
    return z + ds["roof_h"]


def place_houses():
    walls, roofs, trim = Bucket("Houses-col"), Bucket("HouseRoofs"), Bucket("HouseTrim")
    ds = house_designs()
    placed, layout = [], []
    tries = 0
    # 沿每條路兩側依序排屋，候選點先洗牌，避免某條路吃掉全部名額
    cands = []
    for a, c, w in ROADS:
        ab = c - a
        L = ab.length
        t_dir = ab / L
        nrm = Vector((-t_dir.y, t_dir.x))
        s = 4.0
        while s < L - 4.0:
            for side in (-1, 1):
                cands.append((a + t_dir * s, nrm * side, w))
            s += rng.uniform(7.5, 9.5)
    rng.shuffle(cands)
    for base, nrm, w in cands:
        if len(placed) >= N_HOUSES:
            break
        tries += 1
        di = rng.randrange(len(ds))
        dsn = ds[di]
        p = base + nrm * (w / 2 + dsn["d"] / 2 + rng.uniform(0.6, 1.4))
        rad = math.hypot(dsn["w"], dsn["d"]) / 2
        if p.length + rad > WALL_R - 3.5:
            continue
        if (p - KEEP.to_2d()).length < 15 + rad or (p - PLAZA.to_2d()).length < PLAZA_R + rad + 1:
            continue
        if dist_to_roads(p) < dsn["d"] / 2 + 0.3:   # 不壓到別條路
            continue
        if any((p - q).length < (rad + qr) * 0.85 for q, qr in placed):
            continue
        fwd = -nrm                                   # 正面朝向這條路
        rot = math.atan2(fwd.y, fwd.x) + math.pi / 2
        top = build_house(walls, roofs, trim, p, rot, dsn)
        placed.append((p, rad))
        layout.append(dict(pos=[p.x, p.y], rot=rot, design=di, top=top, door=[p.x + fwd.x * (dsn["d"] / 2 + 1.0), p.y + fwd.y * (dsn["d"] / 2 + 1.0)]))
    print(f"houses placed {len(placed)} (tries {tries}), designs used {len({h['design'] for h in layout})}")
    walls.obj(); roofs.obj(); trim.obj()
    return layout, placed


# ---------- 市集攤位、曬衣繩、樹 ----------
def build_market():
    b, cloth = Bucket("Market-col"), Bucket("MarketCloth")
    stalls = []
    for i in range(8):
        a = 2 * math.pi * i / 8 + 0.2
        p = PLAZA + Vector((math.cos(a), math.sin(a), 0)) * (PLAZA_R - 4)
        rot = a + math.pi / 2
        cs, sn = math.cos(rot), math.sin(rot)
        L = lambda x, y, z=0: (p.x + x * cs - y * sn, p.y + x * sn + y * cs, z)
        box(b, L(0, 0), (2.8, 1.4, 0.95), M["timber"], rot)  # 櫃台
        for x in (-1.4, 1.4):
            for y in (-0.8, 0.8):
                box(b, L(x, y), (0.12, 0.12, 2.5), M["timber"], rot)
        c1 = mat("Cloth_" + CLOTH_COLORS[i % 6], srgb(CLOTH_COLORS[i % 6]), 0.9)
        for k in range(6):  # 條紋棚子
            mm = c1 if k % 2 == 0 else mat("Cloth_#ffffff", srgb("#ffffff"), 0.9)
            box(cloth, L(-1.55 + k * 0.62 + 0.31, 0, 2.5), (0.62, 2.0, 0.06), mm, rot)
        # 貨物
        for x in (-0.8, 0, 0.8):
            cyl(b, L(x, 0, 0.95), 0.28, 0.2, mat("Produce_" + str(i), srgb(rng.choice(["#e05d44", "#f2b84b", "#8cc152", "#d97ab0"])), 0.7), n=8)
        stalls.append(dict(pos=[p.x, p.y], rot=rot))
    # 噴水池
    cyl(b, (PLAZA.x, PLAZA.y, 0), 3.2, 0.7, M["stone"], n=20)
    cyl(b, (PLAZA.x, PLAZA.y, 0.6), 2.8, 0.05, M["water"], n=20)
    cyl(b, (PLAZA.x, PLAZA.y, 0), 0.5, 2.2, M["stone"], n=10)
    b.obj(); cloth.obj()
    return stalls


def build_laundry(houses):
    b, cloth = Bucket("Laundry"), Bucket("LaundryCloth")
    n = 0
    for i, (p, r) in enumerate(houses):
        for q, qr in houses[i + 1:]:
            d = (q - p).length
            if r + qr < d < r + qr + 4.5 and n < 18 and rng.random() < 0.5:
                a3, c3 = p.to_3d() + Vector((0, 0, 4.2)), q.to_3d() + Vector((0, 0, 4.2))
                dvec = c3 - a3
                rot = math.atan2(dvec.y, dvec.x)
                mid = (a3 + c3) / 2
                box(b, (mid.x, mid.y, mid.z), (dvec.length, 0.03, 0.03), M["timber"], rot)
                for k in range(int(dvec.length / 1.0)):
                    if rng.random() < 0.6:
                        t = (k + 0.5) / int(dvec.length / 1.0)
                        c = a3 + dvec * t
                        col = rng.choice(CLOTH_COLORS)
                        box(cloth, (c.x, c.y, c.z - rng.uniform(0.5, 0.9)), (rng.uniform(0.4, 0.7), 0.02, rng.uniform(0.5, 0.85)), mat("Cloth_" + col, srgb(col), 0.9), rot)
                n += 1
    b.obj(); cloth.obj()
    print("laundry lines", n)


def build_trees():
    trunks, leaves = Bucket("TreeTrunks-col"), Bucket("TreeLeaves")
    lm = [mat(f"Leaf{i}", srgb(c), 0.9) for i, c in enumerate(["#4f8f3a", "#5f9e43", "#3f7a35", "#7aa84a"])]
    trees = []
    for _ in range(4000):
        if len(trees) >= 320:
            break
        x, y = rng.uniform(-150, 150), rng.uniform(-150, 150)
        r = math.hypot(x, y)
        if r < WALL_R + 10 or r > 150 or abs(x) < 9 and y < 0:   # 城外、避開南門大道
            continue
        if any(math.hypot(x - a, y - b) < 4.5 for a, b, _ in trees):
            continue
        h = ground_h(x, y)
        s = rng.uniform(0.8, 1.4)
        cyl(trunks, (x, y, h - 0.3), 0.3 * s, 3.0 * s, M["timber"], n=7)
        m = rng.choice(lm)
        if rng.random() < 0.5:
            for k in range(3):
                cone(leaves, (x, y, h + (2.0 + k * 1.5) * s), (2.4 - k * 0.6) * s, 2.6 * s, m, n=9)
        else:
            cyl(leaves, (x, y, h + 2.4 * s), 1.6 * s, 2.2 * s, m, n=9, r_top=1.0 * s)
            cyl(leaves, (x, y, h + 4.6 * s), 1.0 * s, 0.9 * s, m, n=9, r_top=0.2 * s)
        trees.append((x, y, s))
    trunks.obj(); leaves.obj()
    return trees


# ---------- 主程式 ----------
build_terrain()
_, gate = build_roads()
_, _, wall_verts = build_walls()
build_keep()
houses_layout, houses_placed = place_houses()
stalls = build_market()
build_laundry(houses_placed)
trees = build_trees()

for ob in scene.objects:   # 平滑著色關掉，保留低多邊形硬邊；地形例外（平滑起伏）
    for poly in ob.data.polygons:
        poly.use_smooth = ob.name.startswith("Terrain")
    up = sum(p.normal.z for p in ob.data.polygons if abs(p.normal.z) > 0.5)
    if ob.name.startswith(("Terrain", "Roads")):
        print(ob.name, "net up-facing", round(up))

out_dir = ROOT / "godot" / "assets"
out_dir.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "blender" / "kingdom.blend"))
bpy.ops.export_scene.gltf(filepath=str(out_dir / "kingdom.glb"), export_format="GLB", export_apply=True, export_yup=True)

to_godot = lambda x, y, z=0.0: [round(x, 3), round(z, 3), round(-y, 3)]
layout = dict(
    seed=SEED, wall_radius=WALL_R, wall_height=WALL_H,
    gate=to_godot(gate.x, gate.y), plaza=to_godot(PLAZA.x, PLAZA.y), plaza_radius=PLAZA_R,
    keep=to_godot(KEEP.x, KEEP.y), keep_door=to_godot(KEEP.x, KEEP.y - 9),
    spawn=to_godot(gate.x * 1.25, gate.y * 1.25),
    houses=[dict(pos=to_godot(*h["pos"]), door=to_godot(*h["door"]), design=h["design"]) for h in houses_layout],
    stalls=[to_godot(*s["pos"]) for s in stalls],
    roads=[dict(a=to_godot(a.x, a.y), b=to_godot(c.x, c.y), w=w) for a, c, w in ROADS],
    trees=[to_godot(x, y, ground_h(x, y)) for x, y, _ in trees],
)
(out_dir / "kingdom_layout.json").write_text(json.dumps(layout, ensure_ascii=False))
tri = sum(sum(len(p.vertices) - 2 for p in ob.data.polygons) for ob in scene.objects)
print(f"exported {out_dir / 'kingdom.glb'}  objects={len(scene.objects)} tris={tri}")
