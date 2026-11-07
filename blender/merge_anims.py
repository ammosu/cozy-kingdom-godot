"""Tripo 輸出（rigged.glb＋每個動作一個 glb）→ 合併成單一 glb、所有動作都在同一個骨架上。
刪掉 Tripo 匯出夾帶的 Icosphere，量模型高度、把腳底放到原點、縮放到目標身高。

blender -b -P blender/merge_anims.py -- <角色> <目標身高m> [轉向角度]
轉向角度：Tripo 的 spec="unreal" 雙足骨架面向 +X（UE 慣例），要給 -90 轉成 glTF 正面 +Z；
四足 spec="tripo" 本來就面向 +Z，給 0（預設）。
輸出 godot/assets/chars/<角色>.glb
"""
import bpy, sys
from mathutils import Vector
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
import math
args = sys.argv[sys.argv.index("--") + 1:]
name, height = args[0], float(args[1])
yaw = float(args[2]) if len(args) > 2 else 0.0
src = ROOT / "assets" / "glb" / name
bpy.ops.wm.read_factory_settings(use_empty=True)


def import_glb(p):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(p))
    return [o for o in bpy.data.objects if o not in before]


objs = import_glb(src / "rigged.glb")
for o in list(objs):
    if o.type == "MESH" and o.name.startswith("Icosphere"):
        bpy.data.objects.remove(o)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
arm.name = name
arm.animation_data_create()

for f in sorted(src.glob("*.glb")):
    if f.stem in ("rigged", "model"):
        continue
    new = import_glb(f)
    a2 = next(o for o in new if o.type == "ARMATURE")
    act = a2.animation_data.action
    act.name = f.stem
    act.use_fake_user = True
    slot = a2.animation_data.action_slot if hasattr(a2.animation_data, "action_slot") else None
    tr = arm.animation_data.nla_tracks.new()
    tr.name = f.stem
    strip = tr.strips.new(f.stem, int(act.frame_range[0]), act)
    if slot is not None and hasattr(strip, "action_slot"):
        strip.action_slot = slot
    for o in new:
        if o.type == "MESH" or o.type == "ARMATURE":
            bpy.data.objects.remove(o)
    print("added action", f.stem, act.frame_range[:])

# 轉成正面朝 glTF +Z（Blender -Y）
arm.rotation_mode = "XYZ"
arm.rotation_euler.z += math.radians(yaw)
# 量高度（rest pose）、腳底對齊
bpy.context.view_layer.update()
lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
for m in meshes:
    for v in m.data.vertices:
        w = m.matrix_world @ v.co
        lo = Vector(map(min, lo, w)); hi = Vector(map(max, hi, w))
h = hi.z - lo.z
s = height / h
arm.scale = [c * s for c in arm.scale]
arm.location.z -= lo.z * s
arm.location.x -= (lo.x + hi.x) / 2 * s
arm.location.y -= (lo.y + hi.y) / 2 * s
print(f"{name}: raw height {h:.3f} → scale {s:.3f}, bbox x {hi.x-lo.x:.2f} y {hi.y-lo.y:.2f}")

out = ROOT / "godot" / "assets" / "chars"
out.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(out / f"{name}.glb"), export_format="GLB",
                          export_animation_mode="NLA_TRACKS", export_force_sampling=True,
                          export_image_format="WEBP" if hasattr(bpy.types, "Image") else "AUTO")
print("exported", out / f"{name}.glb")
