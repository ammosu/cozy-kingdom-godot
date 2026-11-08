# blender -b -P blender/obj2glb_smooth.py -- in.obj out.glb [角度]
# Hunyuan Paint 的 obj → glb：金屬度 0、粗糙度 0.8，依角度平滑著色（減面後的三角面才不會一塊塊稜角）
import bpy, sys, math
a = sys.argv[sys.argv.index("--") + 1:]
ang = float(a[2]) if len(a) > 2 else 35.0
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.obj_import(filepath=a[0], forward_axis='NEGATIVE_Z', up_axis='Y')
for o in bpy.context.scene.objects:
    if o.type != "MESH":
        continue
    for m in o.data.materials:
        b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        b.inputs["Metallic"].default_value = 0.0
        for l in list(m.node_tree.links):
            if l.to_node == b and l.to_socket.name in ("Metallic", "Roughness"):
                m.node_tree.links.remove(l)
        b.inputs["Roughness"].default_value = 0.8
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0005)   # obj 匯入時 UV 接縫會切開頂點，先焊回去平滑才有效
    bpy.ops.object.mode_set(mode="OBJECT")
    if o.data.has_custom_normals:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(ang))
bpy.ops.export_scene.gltf(filepath=a[1])
