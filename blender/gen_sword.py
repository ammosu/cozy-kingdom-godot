"""程序化短劍：Hunyuan 對細長物件會糊掉，所以用 Blender 直接做。原點在握把中央、劍尖朝 +Y（glTF）、刃面朝 ±Z。
blender -b -P blender/gen_sword.py → godot/assets/chars/sword.glb
"""
import bpy, bmesh, math
from pathlib import Path
OUT = Path(__file__).resolve().parent.parent / "godot/assets/chars/sword.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name, col, metal, rough):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*col, 1); b.inputs["Metallic"].default_value = metal; b.inputs["Roughness"].default_value = rough
    return m


def loft(name, sections, material, smooth=False, cap=True):
    """sections：[(高度 h, [(x, y), ...])]，每圈點數相同；Blender 座標 z = 長軸"""
    bm = bmesh.new(); rings = [[bm.verts.new((x, y, h)) for x, y in pts] for h, pts in sections]
    n = len(rings[0])
    for a, b in zip(rings, rings[1:]):
        for i in range(n):
            f = bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i])); f.smooth = smooth
    if cap:
        bm.faces.new(rings[0][::-1]); bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free(); me.materials.append(material)
    o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o); return o


def blade_ring(w, t):
    return [(-w, 0), (-w * .35, t), (w * .35, t), (w, 0), (w * .35, -t), (-w * .35, -t)]


def circle(r, n=10, sx=1.0, sy=1.0):
    return [(math.cos(2 * math.pi * i / n) * r * sx, math.sin(2 * math.pi * i / n) * r * sy) for i in range(n)]


steel = mat("Steel", (.42, .45, .5), .1, .72)   
# ↑金屬度不能高：會整片反射天空和草地的顏色
gold = mat("Gold", (.86, .60, .20), .85, .35); gold = mat("Gold", (.86, .60, .20), .85, .35)
leather = mat("Leather", (.30, .16, .09), 0, .8)
G = .075   # 護手高度（握把中心在 0）
objs = [
    loft("Blade", [(G, blade_ring(.038, .012)), (.42, blade_ring(.036, .011)), (.60, blade_ring(.028, .008)), (.68, blade_ring(.0015, .001))], steel),
    loft("Fuller", [(G + .01, [(-.012, 0), (0, .0132), (.012, 0), (0, -.0132)]), (.5, [(-.009, 0), (0, .0122), (.009, 0), (0, -.0122)])], mat("Dark", (.17, .19, .24), .2, .55)),   # 血槽：刃中央的深色溝，劍身才有明暗層次
    loft("Guard", [(G - .02, circle(.03, 10, 3.3, 1.0)), (G, circle(.034, 10, 3.5, 1.0)), (G + .02, circle(.026, 10, 3.0, .9))], gold, True),
    loft("Grip", [(-G, circle(.019)), (0, circle(.021)), (G, circle(.019))], leather, True),
    loft("Pommel", [(-G - .05, circle(.012)), (-G - .04, circle(.032)), (-G - .012, circle(.032)), (-G, circle(.016))], gold, True),
]
bpy.ops.export_scene.gltf(filepath=str(OUT), export_format="GLB")
print("exported", OUT)
