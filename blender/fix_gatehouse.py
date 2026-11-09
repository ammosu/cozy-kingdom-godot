"""ck_gatehouse 的門洞修補：Hunyuan 只看得到外側四個視角，門洞內部的形狀和貼圖都是壞的（有尖刺、拉伸貼圖）。
刪掉門洞範圍內的面，再襯一條乾淨的拱形石頭通道（兩側牆＋橢圓拱頂，兩端有收邊），貼可重複的石材貼圖。

blender -b -P blender/fix_gatehouse.py
輸入 assets3d/ck_gatehouse/ck_gatehouse.glb → 輸出 godot/assets/props/ck_gatehouse.glb
重新生成城門樓模型後要再跑一次。
"""
import bpy, bmesh, math
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parent.parent
SRC, DST = ROOT / "assets3d/ck_gatehouse/ck_gatehouse.glb", ROOT / "godot/assets/props/ck_gatehouse.glb"
TEX, NOR = ROOT / "godot/assets/tex/gate_stone.png", ROOT / "godot/assets/tex/gate_stone_n.png"
# 以下是模型單位（模型高約 1.85）。量測值：門洞半寬約 0.30、拱腳在 0.22H、拱頂在 0.345H，模型深度 ±0.345
WORLD_SCALE = 8.6        # 擺進遊戲的大約倍率（props.gd 的 fit）
TILE_PER_M = 0.27        # 貼圖每公尺重複次數
HALF_W = 0.285           # 比原本的石面略窄，把凹凸不平的表面藏在後面
SPRING = 0.22            # 拱腳高（占模型高）
TOP = 0.335              # 拱頂高（占模型高）
DEPTH = 0.335            # 通道半長
RIM = 0.03               # 兩端收邊的寬度
N_ARC = 24

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SRC))
ob = next(o for o in bpy.data.objects if o.type == "MESH")
bm = bmesh.new(); bm.from_mesh(ob.data); bm.transform(ob.matrix_world)
zs = [v.co.z for v in bm.verts]; z0, H = min(zs), max(zs) - min(zs)
xs = [v.co.x for v in bm.verts]; cx = (min(xs) + max(xs)) / 2
ys = [v.co.y for v in bm.verts]; cy = (min(ys) + max(ys)) / 2
spring, rise = SPRING * H, (TOP - SPRING) * H


def inside(p, grow=1.0):
    x, h = (p.x - cx) / (HALF_W * grow), p.z - z0
    if abs(x) >= 1.0 or abs(p.y - cy) > DEPTH + 0.02:
        return False
    return h < spring or h < spring + rise * grow * math.sqrt(1 - x * x)


# 只要有一個頂點進到通道內就刪：尖刺的面中心可能在石面後面，但尖端會穿出來
kill = [f for f in bm.faces if inside(f.calc_center_median()) or any(inside(v.co) for v in f.verts)]
bmesh.ops.delete(bm, geom=kill, context="FACES")
print("deleted faces", len(kill))
bm.to_mesh(ob.data); ob.matrix_world.identity(); bm.free()

# 拱形剖面：左牆腳 → 左拱腳 → 拱頂 → 右拱腳 → 右牆腳（x, 高度, 累計弧長）
prof = [(-HALF_W, 0.0)]
for i in range(N_ARC + 1):
    a = math.pi - math.pi * i / N_ARC
    prof.append((HALF_W * math.cos(a), spring + rise * math.sin(a)))
prof.append((HALF_W, 0.0))
arc = [0.0]
for a, b in zip(prof, prof[1:]):
    arc.append(arc[-1] + math.dist(a, b))
uvs = WORLD_SCALE * TILE_PER_M
me = bpy.data.meshes.new("GateLining"); lb = bmesh.new()
uvl = lb.loops.layers.uv.new("UVMap")


def quad(pts, uv, smooth):
    # pts 依逆時針（由通道內看）排列，法線朝內
    f = lb.faces.new([lb.verts.new(p) for p in pts])
    f.smooth = smooth
    for l, t in zip(f.loops, uv):
        l[uvl].uv = t


for i in range(len(prof) - 1):
    (x0, h0), (x1, h1) = prof[i], prof[i + 1]
    pts = [(cx + x0, cy - DEPTH, z0 + h0), (cx + x0, cy + DEPTH, z0 + h0), (cx + x1, cy + DEPTH, z0 + h1), (cx + x1, cy - DEPTH, z0 + h1)]
    uv = [(0.0, arc[i] * uvs), (2 * DEPTH * uvs, arc[i] * uvs), (2 * DEPTH * uvs, arc[i + 1] * uvs), (0.0, arc[i + 1] * uvs)]   # 石層沿通道方向，和外牆一樣是水平線
    quad(pts, uv, 0 < i < len(prof) - 2)
    # 兩端收邊：往外擴一圈，蓋住模型與襯裡的交界
    for y, flip in ((cy - DEPTH, False), (cy + DEPTH, True)):
        def out(x, h):
            return (cx + x * (1 + RIM / HALF_W), y, z0 + h if h < spring else z0 + spring + (h - spring) * (1 + RIM / rise))
        ring = [(cx + x0, y, z0 + h0), (cx + x1, y, z0 + h1), out(x1, h1), out(x0, h0)]
        ruv = [(0.0, arc[i] * uvs), (0.0, arc[i + 1] * uvs), (RIM * uvs, arc[i + 1] * uvs), (RIM * uvs, arc[i] * uvs)]
        if flip:
            ring, ruv = ring[::-1], ruv[::-1]
        quad(ring, ruv, False)
bmesh.ops.remove_doubles(lb, verts=lb.verts, dist=1e-5)
bmesh.ops.recalc_face_normals(lb, faces=lb.faces)
# 法線要朝通道內（往軸心）；recalc 對開放網格可能整片翻轉，用第一面驗證
lb.faces.ensure_lookup_table()
f0 = lb.faces[0]
if f0.normal.dot(Vector((cx, f0.calc_center_median().y, z0 + spring * 0.5)) - f0.calc_center_median()) < 0:
    for f in lb.faces:
        f.normal_flip()
lb.to_mesh(me); lb.free()
lining = bpy.data.objects.new("GateLining", me); bpy.context.scene.collection.objects.link(lining)

mat = bpy.data.materials.new("GateStone"); mat.use_nodes = True
nt = mat.node_tree; bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = bpy.data.images.load(str(TEX))
nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
nmap = nt.nodes.new("ShaderNodeNormalMap"); nmap.inputs["Strength"].default_value = 0.8
ntex = nt.nodes.new("ShaderNodeTexImage"); ntex.image = bpy.data.images.load(str(NOR)); ntex.image.colorspace_settings.name = "Non-Color"
nt.links.new(ntex.outputs["Color"], nmap.inputs["Color"]); nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
bsdf.inputs["Roughness"].default_value = 0.9; bsdf.inputs["Metallic"].default_value = 0.0
me.materials.append(mat)
bpy.ops.export_scene.gltf(filepath=str(DST), export_format="GLB", export_tangents=True)
print("exported", DST)
