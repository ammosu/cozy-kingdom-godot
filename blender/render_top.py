"""kingdom.blend 俯視＋斜視快照 → shots/blender_top.png、shots/blender_oblique.png（Workbench，看配置用）"""
import bpy, math
from pathlib import Path
ROOT = Path(bpy.data.filepath).parent.parent
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "STUDIO"; sc.display.shading.color_type = "MATERIAL"
sc.display.shading.show_shadows = True; sc.display.shading.show_cavity = True
sc.render.resolution_x = sc.render.resolution_y = 1400
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = "ORTHO"; cam.data.ortho_scale = 135; cam.location = (0, 0, 200); cam.rotation_euler = (0, 0, 0)
cam.data.clip_end = 1000
sc.render.filepath = str(ROOT / "shots" / "blender_top.png"); bpy.ops.render.render(write_still=True)
cam.data.type = "PERSP"; cam.data.lens = 28; cam.location = (0, -115, 55); cam.rotation_euler = (math.radians(66), 0, 0)
sc.render.resolution_x = 1600; sc.render.resolution_y = 900
sc.render.filepath = str(ROOT / "shots" / "blender_oblique.png"); bpy.ops.render.render(write_still=True)
