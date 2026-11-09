"""程序化樹木：圓冠闊葉樹、層狀針葉樹、灌木，各幾個變體，輸出成獨立 GLB 給 Godot 用 MultiMesh 種。

blender -b -P blender/gen_trees.py
輸出 godot/assets/nature/<種類>_<變體>.glb，每個檔有兩個網格：Trunk（樹皮）、Leaves（樹葉）。
樹葉用頂點色做明暗：樹冠底部／內側暗、頂部亮；法線改成從樹冠中心往外的「球形法線」，
光影會像一整團樹冠而不是一顆顆多面體（風格化樹木的常見做法）。
"""
import bpy, bmesh, math, random
from mathutils import Vector, noise
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "godot" / "assets" / "nature"
OUT.mkdir(parents=True, exist_ok=True)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    t = max(0.0, min(1.0, t))
    return tuple(lerp(a, b, t) for a, b in zip(c1, c2))


def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple((x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c) + (1.0,)


class Part:
    """一個網格：頂點、面、頂點色、自訂法線。"""

    def __init__(self, name):
        self.name = name
        self.v, self.f, self.col, self.nrm, self.uv = [], [], [], [], []

    def add_vert(self, p, c, n):
        self.v.append(Vector(p)); self.col.append(c); self.nrm.append(Vector(n).normalized())
        return len(self.v) - 1

    def build(self, mat_name):
        me = bpy.data.meshes.new(self.name)
        me.from_pydata([tuple(p) for p in self.v], [], self.f)
        me.update()
        attr = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
        for i, c in enumerate(self.col):
            attr.data[i].color = c
        for p in me.polygons:
            p.use_smooth = True
        me.normals_split_custom_set_from_vertices([tuple(n) for n in self.nrm])
        if self.uv:
            uvl = me.uv_layers.new(name="UVMap")
            for poly in me.polygons:
                for li in poly.loop_indices:
                    uvl.data[li].uv = self.uv[me.loops[li].vertex_index]
        m = bpy.data.materials.get(mat_name) or bpy.data.materials.new(mat_name)
        m.use_nodes = True
        nt = m.node_tree
        ca = nt.nodes.new("ShaderNodeVertexColor"); ca.layer_name = "Col"
        nt.links.new(ca.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
        me.materials.append(m)
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


def tube(part, spine, radii, color_fn, sides=8):
    """沿著 spine 點列做錐狀管子（樹幹、樹枝）。"""
    rings = []
    for i, (p, r) in enumerate(zip(spine, radii)):
        d = (spine[min(i + 1, len(spine) - 1)] - spine[max(i - 1, 0)]).normalized()
        a = d.orthogonal().normalized(); b = d.cross(a).normalized()
        ring = []
        for k in range(sides):
            t = k / sides * math.tau
            n = a * math.cos(t) + b * math.sin(t)
            # 樹皮凹凸：沿著角度與高度的雜訊
            rr = r * (1 + 0.12 * noise.noise(Vector((math.cos(t) * 2, math.sin(t) * 2, p.z * 1.5))))
            ring.append(part.add_vert(p + n * rr, color_fn(i / (len(spine) - 1), t), n))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(sides):
            a, b = rings[i][k], rings[i][(k + 1) % sides]
            c, d = rings[i + 1][(k + 1) % sides], rings[i + 1][k]
            part.f.append((a, b, c, d))


def shade_of(p, d, crown_c, crown_r, n2, col_dark, col_mid, col_light):
    rel = p - crown_c
    h = (rel.z / crown_r) * 0.5 + 0.5
    out = min(1.0, rel.length / crown_r)
    shade = 0.55 * h + 0.45 * out * out + 0.12 * n2
    return mix(col_dark, col_mid, shade * 1.4) if shade < 0.7 else mix(col_mid, col_light, (shade - 0.7) / 0.4)


def leaf_cards(cards, center, radius, crown_c, crown_r, rng, cols, n=130, size=0.36, squash=1.0):
    """在樹葉團表面貼葉簇卡片（透明貼圖）：卡片朝外、沿法線隨機轉，打破圓球輪廓。"""
    for _ in range(n):
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
        if d.z < -0.55 and rng.random() < 0.6:
            continue   # 底部少放
        p = center + Vector((d.x, d.y, d.z * squash)) * radius * rng.uniform(0.62, 1.12)   # 卡片分布在整個厚度，看不到內核
        rel = p - crown_c
        sph = rel.normalized() if rel.length > 1e-4 else d
        nrm = (sph * 0.7 + d * 0.3).normalized()
        # 卡片平面：法線偏向外側但有隨機傾斜（不要全部正對外面）
        fn = (d + Vector((rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), rng.uniform(-0.3, 0.6)))).normalized()
        a = fn.orthogonal().normalized(); b = fn.cross(a).normalized()
        rot = rng.uniform(0, math.tau)
        a, b = a * math.cos(rot) + b * math.sin(rot), b * math.cos(rot) - a * math.sin(rot)
        s = radius * size * rng.uniform(0.8, 1.25)
        c = shade_of(p, d, crown_c, crown_r, rng.uniform(-0.5, 0.5), *cols)
        c = tuple(min(1.0, x * rng.uniform(0.9, 1.15)) for x in c[:3]) + (1.0,)
        base = len(cards.v)
        for (u, v) in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            cards.add_vert(p + a * u * s + b * v * s, c, nrm)
            cards.uv.append((u * 0.5 + 0.5, v * 0.5 + 0.5))
        cards.f.append((base, base + 1, base + 2, base + 3))


def blob(part, center, radius, crown_c, crown_r, rng, col_dark, col_mid, col_light, subdiv=3, lumpy=0.22, squash=1.0):
    """一團樹葉：雜訊擾動的 icosphere。法線取「從整個樹冠中心往外」，顏色依高度與外側程度。"""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    seed = Vector((rng.uniform(0, 100), rng.uniform(0, 100), rng.uniform(0, 100)))
    base = len(part.v)
    for v in bm.verts:
        d = v.co.normalized()
        n1 = noise.noise(d * 1.6 + seed)
        n2 = noise.noise(d * 4.5 + seed * 2) * 0.45
        r = radius * (1 + lumpy * (n1 + n2))
        p = center + Vector((d.x * r, d.y * r, d.z * r * squash))
        # 樹冠內的相對位置：高度 0..1、外側程度
        rel = p - crown_c
        h = (rel.z / crown_r) * 0.5 + 0.5
        out = min(1.0, rel.length / crown_r)
        sph = rel.normalized() if rel.length > 1e-4 else Vector((0, 0, 1))
        nrm = (sph * 0.75 + d * 0.25)
        shade = 0.55 * h + 0.45 * out * out + 0.12 * n2
        c = mix(col_dark, col_mid, shade * 1.4) if shade < 0.7 else mix(col_mid, col_light, (shade - 0.7) / 0.4)
        part.add_vert(p, c, nrm)
    for f in bm.faces:
        part.f.append(tuple(base + v.index for v in f.verts))
    bm.free()


BARK_DARK, BARK_LIGHT = srgb("#3d2a1c"), srgb("#7a5a3e")


def core(c):
    return tuple(x * 0.42 for x in c[:3]) + (1.0,)


def bark_col(t, ang):
    k = 0.5 + 0.5 * math.sin(ang * 3 + t * 7)
    return mix(BARK_DARK, BARK_LIGHT, 0.35 + 0.4 * k * (0.4 + 0.6 * t))


def oak(name, seed, height=7.5, palette=None):
    rng = random.Random(seed)
    reset()
    dark, mid, light = palette or (srgb("#1f4a22"), srgb("#4c8a34"), srgb("#a8cf5a"))
    trunk, leaves, cards = Part("Trunk"), Part("Leaves"), Part("LeafCards")
    trunk_h = height * 0.45
    lean = Vector((rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), 0))
    spine = [Vector((0, 0, -0.3))]
    for i in range(1, 8):
        t = i / 7
        spine.append(Vector((lean.x * t * t, lean.y * t * t, -0.3 + (trunk_h + 0.3) * t)))
    radii = [lerp(0.42, 0.2, (i / 7) ** 0.7) * height / 7.5 for i in range(8)]
    radii[0] *= 1.35   # 樹根外擴
    tube(trunk, spine, radii, bark_col)
    top = spine[-1]
    crown_c = top + Vector((0, 0, height * 0.22))
    crown_r = height * 0.36
    # 主枝：從樹幹上段伸向各團樹葉
    n_cl = rng.randint(7, 10)
    centers = []
    for k in range(n_cl):
        a = k / n_cl * math.tau + rng.uniform(-0.3, 0.3)
        el = rng.uniform(-0.15, 0.9)
        r = crown_r * rng.uniform(0.35, 0.95)   # 枝團遠近不一，輪廓不是一顆圓球
        c = crown_c + Vector((math.cos(a) * r * math.cos(el), math.sin(a) * r * math.cos(el), r * math.sin(el) * 0.8))
        centers.append(c)
    centers.append(crown_c + Vector((0, 0, crown_r * 0.55)))
    for c in centers[:5]:
        st = top - Vector((0, 0, rng.uniform(0.2, 0.9)))
        sp = [st.lerp(c, t) + Vector((0, 0, math.sin(t * math.pi) * 0.4)) for t in (0, 0.35, 0.7, 0.95)]
        tube(trunk, sp, [radii[-1] * 0.7, radii[-1] * 0.5, radii[-1] * 0.3, 0.05], bark_col, sides=6)
    for c in centers:
        rad = crown_r * rng.uniform(0.3, 0.62)
        # 內核縮小、壓暗：只當葉片縫隙裡的陰影，不再看得出是一顆綠球
        blob(leaves, c, rad * 0.62, crown_c, crown_r, rng, core(dark), core(dark), core(mid))
        leaf_cards(cards, c, rad, crown_c, crown_r, rng, (dark, mid, light))
    trunk.build("Bark"); leaves.build("Foliage"); cards.build("LeafCard")
    export(name)


def pine(name, seed, height=10.0):
    """雲杉：細樹幹＋深色窄內核，外面是一圈圈下垂的針葉枝卡片（Codex 的 pine_branch 透明貼圖）。"""
    rng = random.Random(seed)
    reset()
    dark, mid, light = srgb("#16402c"), srgb("#2f7044"), srgb("#86b86a")
    trunk, leaves, cards = Part("Trunk"), Part("Leaves"), Part("NeedleCards")
    spine = [Vector((0, 0, -0.3 + (height * 0.86 + 0.3) * i / 6)) for i in range(7)]   # 樹幹比枝葉矮，頂端才不會露出一截
    tube(trunk, spine, [lerp(0.34, 0.03, i / 6) * height / 10 for i in range(7)], bark_col)
    z_lo, z_hi = height * 0.14, height * 0.98
    prof = lambda z: max(1.0 - (z - z_lo) / (z_hi - z_lo), 0.0) ** 0.85 * height * 0.31 + 0.12
    # 內核：暗色窄錐，擋住從枝葉縫隙穿過去的視線
    nside, rings = 10, []
    for i in range(8):
        z = lerp(z_lo + 0.3, z_hi - 0.2, i / 7)
        r = prof(z) * 0.2
        ring = []
        for k in range(nside):
            a = k / nside * math.tau
            n = Vector((math.cos(a), math.sin(a), 0.5))
            ring.append(leaves.add_vert(Vector((math.cos(a) * r, math.sin(a) * r, z)), core(mix(dark, mid, 0.3 + 0.5 * i / 7)), n))
        rings.append(ring)
    for i in range(7):
        for k in range(nside):
            leaves.f.append((rings[i][k], rings[i][(k + 1) % nside], rings[i + 1][(k + 1) % nside], rings[i + 1][k]))
    whorls = int(height * 5.0)
    for w in range(whorls):
        t = w / (whorls - 1)
        z = lerp(z_lo, z_hi, t) + rng.uniform(-0.06, 0.06)
        n = max(6, int(lerp(17, 8, t)))
        rot = rng.uniform(0, math.tau)
        for k in range(n):
            if rng.random() < 0.22:      # 有些枝條缺掉，樹冠才有疏密，不是規律放射
                continue
            a = rot + k / n * math.tau + rng.uniform(-0.45, 0.45)
            L = prof(z) * rng.uniform(0.7, 1.3) * (1.0 + 0.3 * noise.noise(Vector((math.cos(a) * 1.4, math.sin(a) * 1.4, z * 0.35))))
            W = L / 2.05 * rng.uniform(1.0, 1.25)
            dirn = Vector((math.cos(a), math.sin(a), 0))
            side = Vector((-dirn.y, dirn.x, 0))
            droop = lerp(0.55, 0.12, t) * L + rng.uniform(-0.05, 0.1) * L
            roll = rng.uniform(-1.0, 1.0)
            side = (side * math.cos(roll) + Vector((0, 0, 1)) * math.sin(roll)).normalized()
            shade = 0.25 + 0.55 * t + rng.uniform(-0.12, 0.12)
            # 每根枝條兩片十字交叉的卡片，從側面看也有體積，不是扁平的一層
            up = dirn.cross(side).normalized()
            for sd, ww in ((side, W), ((side + up * 1.3).normalized(), W * 0.72)):
                for j in range(3):        # 三段：根部 → 中段 → 下垂的枝梢
                    u = j / 2
                    c = Vector((0, 0, z)) + dirn * L * u + Vector((0, 0, -droop * u * u + 0.08 * L * u))
                    nrm = (dirn * 0.65 + Vector((0, 0, 1.0))).normalized()
                    col = mix(dark, mid, shade * 1.3) if u < 0.6 else mix(mid, light, shade)
                    for v, sgn in ((0.0, -1), (1.0, 1)):
                        cards.add_vert(c + sd * sgn * ww * 0.5, col, nrm)
                        cards.uv.append((u, v))
                b0 = len(cards.v) - 6
                for j in range(2):
                    i0 = b0 + j * 2
                    cards.f.append((i0, i0 + 2, i0 + 3, i0 + 1))
    trunk.build("Bark"); leaves.build("Foliage"); cards.build("NeedleCard")
    export(name)


def bush(name, seed, size=1.3, flowers=False):
    rng = random.Random(seed)
    reset()
    dark, mid, light = srgb("#24502a"), srgb("#4f8f3c"), srgb("#9cc95a")
    leaves, cards = Part("Leaves"), Part("LeafCards")
    crown_c = Vector((0, 0, size * 0.4)); crown_r = size * 0.75
    for k in range(rng.randint(4, 6)):
        a = rng.uniform(0, math.tau); r = size * rng.uniform(0.15, 0.45)
        c = Vector((math.cos(a) * r, math.sin(a) * r, size * rng.uniform(0.3, 0.6)))
        rad = size * rng.uniform(0.35, 0.5)
        blob(leaves, c, rad * 0.62, crown_c, crown_r, rng, core(dark), core(dark), core(mid), subdiv=2, squash=0.8)
        leaf_cards(cards, c, rad, crown_c, crown_r, rng, (dark, mid, light), n=130, size=0.25, squash=0.8)
    leaves.build("Foliage"); cards.build("LeafCard")
    export(name)


def export(name):
    bpy.ops.export_scene.gltf(filepath=str(OUT / f"{name}.glb"), export_format="GLB",
                              export_yup=True, export_vertex_color="ACTIVE", export_normals=True)
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in bpy.context.scene.objects)
    print("exported", name, "tris", tris)


oak("oak_a", 1, 7.5)
oak("oak_b", 2, 6.5, (srgb("#2a4d1e"), srgb("#5e8f2e"), srgb("#c2d468")))
oak("oak_c", 3, 8.5, (srgb("#1c4426"), srgb("#3f7f3a"), srgb("#93c463")))
pine("pine_a", 4, 10.0)
pine("pine_b", 5, 12.0)
bush("bush_a", 6, 1.3)
bush("bush_b", 7, 1.0)
