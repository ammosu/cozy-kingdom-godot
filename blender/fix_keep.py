"""主堡入口修補：Hunyuan 重建的階梯和大門邊緣黏成一團、貼圖也糊，這裡蓋上乾淨的程序化階梯，和 Codex 畫的清晰門板。
blender -b -P blender/fix_keep.py    輸入 assets3d/ck_keep/ck_keep.glb → 輸出 godot/assets/props/ck_keep.glb
數值是模型單位，用射線量測：階梯 |x|<0.2、y 從 -0.546 到 -0.282；門面 y = -0.282；模型高 1.973、底部 z = -0.984。
"""
import bpy, bmesh
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
SRC, DST = ROOT / "assets3d/ck_keep/ck_keep.glb", ROOT / "godot/assets/props/ck_keep.glb"
Z0 = -0.984
DOOR_Y = -0.297
DOOR_W, DOOR_H, DOOR_BASE = 0.27, 0.385, 0.203
UV_SCALE = 2.6
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SRC))


def stone():
    m = bpy.data.materials.new("KeepStone"); m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    t = m.node_tree.nodes.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(str(ROOT / "godot/assets/tex/gate_stone.png"))
    m.node_tree.links.new(t.outputs["Color"], b.inputs["Base Color"])
    n = m.node_tree.nodes.new("ShaderNodeNormalMap"); nt = m.node_tree.nodes.new("ShaderNodeTexImage")
    nt.image = bpy.data.images.load(str(ROOT / "godot/assets/tex/gate_stone_n.png")); nt.image.colorspace_settings.name = "Non-Color"
    m.node_tree.links.new(nt.outputs["Color"], n.inputs["Color"]); m.node_tree.links.new(n.outputs["Normal"], b.inputs["Normal"])
    b.inputs["Roughness"].default_value = 0.9; b.inputs["Metallic"].default_value = 0.0
    return m


me = bpy.data.meshes.new("KeepEntry"); bm = bmesh.new(); uvl = bm.loops.layers.uv.new("UVMap")


def box(x0, x1, y0, y1, z0, z1):
    v = [bm.verts.new((x, y, z)) for z in (z0, z1) for y in (y0, y1) for x in (x0, x1)]
    for idx in ((0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)):
        f = bm.faces.new([v[i] for i in idx]); f.normal_update(); n = f.normal
        for l in f.loops:
            c = l.vert.co
            uv = (c.x, c.y) if abs(n.z) > .7 else ((c.x, c.z) if abs(n.y) > .7 else (c.y, c.z))
            l[uvl].uv = (uv[0] * UV_SCALE, uv[1] * UV_SCALE)


steps = [(0.0, -0.556, 0.066), (0.066, -0.5, 0.106), (0.106, -0.452, 0.146), (0.146, -0.404, 0.178), (0.178, -0.356, 0.206)]
for z_lo, y, z_hi in steps:
    box(-0.215, 0.215, y, -0.27, Z0 - 0.01, Z0 + z_hi)
for s in (-1, 1):      # 兩側階梯牆
    x0, x1 = sorted((s * 0.195, s * 0.25))
    box(x0, x1, -0.57, -0.3, Z0 - 0.01, Z0 + 0.21)
    box(x0 - 0.006, x1 + 0.006, -0.582, -0.5, Z0 - 0.01, Z0 + 0.24)   # 收頭的石墩
bm.to_mesh(me); bm.free(); me.materials.append(stone())
bpy.context.scene.collection.objects.link(bpy.data.objects.new("KeepEntry", me))

# 門板：四邊形貼 Codex 門，透明裁切出拱形
dm = bpy.data.meshes.new("KeepDoor")
base = Z0 + DOOR_BASE
dm.from_pydata([(-DOOR_W / 2, DOOR_Y, base), (DOOR_W / 2, DOOR_Y, base), (DOOR_W / 2, DOOR_Y, base + DOOR_H), (-DOOR_W / 2, DOOR_Y, base + DOOR_H)], [], [(0, 1, 2, 3)])
u = dm.uv_layers.new(name="UVMap")
for l, t in zip(u.data, ((0, 0), (1, 0), (1, 1), (0, 1))):
    l.uv = t
m = bpy.data.materials.new("KeepDoor"); m.use_nodes = True
b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
t = m.node_tree.nodes.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(str(ROOT / "godot/assets/tex/keep_door.png"))
m.node_tree.links.new(t.outputs["Color"], b.inputs["Base Color"]); m.node_tree.links.new(t.outputs["Alpha"], b.inputs["Alpha"])
b.inputs["Roughness"].default_value = 0.8; b.inputs["Metallic"].default_value = 0.0
m.blend_method = "CLIP" if hasattr(m, "blend_method") else None
dm.materials.append(m)
bpy.context.scene.collection.objects.link(bpy.data.objects.new("KeepDoor", dm))
bpy.ops.export_scene.gltf(filepath=str(DST), export_format="GLB", export_tangents=True)
print("exported", DST)
