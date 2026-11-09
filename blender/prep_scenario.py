# blender -b -P blender/prep_scenario.py -- in.glb out.glb <目標面數> [貼圖上限=1024]
# 外部 GLB（Scenario 3D Collection）進遊戲前的整理：減面、縮貼圖。
# 也可給 --split <輸出前綴> <數量>：拆成最大的幾個零件各存一檔（岩石組用）。
import bpy, sys
a = sys.argv[sys.argv.index("--") + 1:]
src, dst, target = a[0], a[1], int(a[2])
tex = int(a[3]) if len(a) > 3 and a[3].isdigit() else 1024
split = int(a[a.index("--split") + 1]) if "--split" in a else 0
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
total = sum(len(o.data.polygons) for o in meshes)
ratio = min(target / max(total, 1), 1.0)
if ratio < 0.98:
    for o in meshes:
        m = o.modifiers.new("dec", "DECIMATE")
        m.ratio = ratio
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=m.name)
for img in bpy.data.images:
    w, h = img.size
    if max(w, h) > tex:
        k = tex / max(w, h)
        img.scale(int(w * k), int(h * k))
bpy.ops.object.select_all(action="DESELECT")
if split:
    meshes.sort(key=lambda o: o.dimensions.x * o.dimensions.y * o.dimensions.z, reverse=True)
    step = max(len(meshes) // split, 1)
    for i, o in enumerate(meshes[::step][:split]):
        o.select_set(True)
        o.location = (0, 0, 0)
        bpy.ops.export_scene.gltf(filepath=f"{dst}_{i + 1}.glb", use_selection=True, export_apply=True)
        o.select_set(False)
else:
    bpy.ops.export_scene.gltf(filepath=dst, export_apply=True)
print("PREP", dst, "faces", total, "->", sum(len(o.data.polygons) for o in meshes))
