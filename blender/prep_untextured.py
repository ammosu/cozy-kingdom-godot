# blender -b -P prep_untextured.py -- in.glb out.glb [target_tris] [tex]
# 從 img2_3d/tools/prep_untextured.py 複製；加了破碎網格的體素重建備援（ck_house_c 原始 256 萬面、34 萬條非流形邊，直接減面卡在 70 萬面，Paint 跑兩小時沒結束）
"""Untextured clean mesh (e.g. Hunyuan3D MV) -> decimated, smart-UV'd, blank texture ready for projection."""
import bpy, sys, math
argv = sys.argv[sys.argv.index("--") + 1:]
SRC, DST = argv[0], argv[1]
TARGET = int(argv[2]) if len(argv) > 2 else 30000
TEX = int(argv[3]) if len(argv) > 3 else 2048
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
ms = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in list(bpy.context.scene.objects):
    if o.type != "MESH": bpy.data.objects.remove(o)
bpy.ops.object.select_all(action="DESELECT")
for o in ms: o.select_set(True)
bpy.context.view_layer.objects.active = ms[0]
if len(ms) > 1: bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active; ob.parent = None
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT"); bpy.ops.mesh.remove_doubles(threshold=1e-4)
bpy.ops.mesh.normals_make_consistent(inside=False)  # some Hunyuan meshes come out with inverted winding
bpy.ops.object.mode_set(mode="OBJECT")
tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
if tris > TARGET * 40:   # 破碎網格（大量非流形邊）減面會卡住 → 先體素重建成封閉表面
    r = ob.modifiers.new("v", "REMESH"); r.mode = "VOXEL"; r.voxel_size = max(ob.dimensions) / 400; bpy.ops.object.modifier_apply(modifier="v")
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons); print("REMESH tris", tris)
if tris > TARGET:
    m = ob.modifiers.new("d", "DECIMATE"); m.ratio = TARGET / tris; bpy.ops.object.modifier_apply(modifier="d")
bpy.ops.object.shade_smooth()
while ob.data.uv_layers: ob.data.uv_layers.remove(ob.data.uv_layers[0])
ob.data.uv_layers.new(name="UVMap")
bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.003)
bpy.ops.object.mode_set(mode="OBJECT")
img = bpy.data.images.new("basecolor", TEX, TEX, alpha=False)
img.pixels[:] = [0.5, 0.5, 0.5, 1.0] * (TEX * TEX); img.pack()
ob.data.materials.clear()
mat = bpy.data.materials.new("projected"); mat.use_nodes = True
nt = mat.node_tree; bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = img
nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
bsdf.inputs["Roughness"].default_value = 0.6; bsdf.inputs["Metallic"].default_value = 0.0
ob.data.materials.append(mat)
bpy.ops.export_scene.gltf(filepath=DST, export_format="GLB")
print("RESULT tris", sum(len(p.vertices) - 2 for p in ob.data.polygons))
