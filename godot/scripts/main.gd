extends Node3D
## 世界組裝：載入 Blender 生成的王國、天空與光、草地、角色。
## 截圖模式（環境變數）：SHOT=<輸出路徑> CAM=x,y,z LOOK=x,y,z [FRAMES=90] [TIME=秒]

const LAYOUT_PATH := "res://assets/kingdom_layout.json"
var layout: Dictionary
var sun: DirectionalLight3D
var env: Environment
var grass_mat: ShaderMaterial

func _ready() -> void:
	layout = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	_build_environment()
	var kingdom: Node3D = load("res://assets/kingdom.glb").instantiate()
	add_child(kingdom)
	_tune_kingdom_materials(kingdom)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_build_grass()
	_spawn_actors()
	if OS.get_environment("SHOT") != "":
		_screenshot_mode()

# ---------- 天空、太陽、後製 ----------
func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("2f78d8")
	sky_mat.sky_horizon_color = Color("a9d4f2")
	sky_mat.ground_horizon_color = Color("bfe0f5")
	sky_mat.ground_bottom_color = Color("6c8c5a")
	sky_mat.sun_angle_max = 20.0
	sky_mat.sky_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_bounce_feedback = 0.6
	env.sdfgi_cascades = 4
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.08
	env.fog_enabled = true
	env.fog_light_color = Color("cfe3f2")
	env.fog_density = 0.0005
	env.fog_aerial_perspective = 0.25
	env.fog_sky_affect = 0.3
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0015
	env.volumetric_fog_albedo = Color("fff3dc")
	env.volumetric_fog_anisotropy = 0.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color("fff0d4")
	sun.light_energy = 2.2
	sun.rotation_degrees = Vector3(-38, -35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_blend_splits = true
	sun.light_angular_distance = 0.8
	sun.light_volumetric_fog_energy = 1.2
	add_child(sun)

# 材質名稱前綴 → [貼圖, 每公尺重複次數, 是否保留 Blender 底色（染色）]
const TEX := {
	"Wall_": ["plaster", 0.5, true],
	"Roof": ["roof_tiles", 0.6, true],
	"Cobble": ["cobblestone", 0.4, false],
	"Dirt": ["dirt_path", 0.35, false],
	"StoneDark": ["stone_wall", 0.4, true],
	"Stone": ["stone_wall", 0.35, false],
	"Timber": ["wood_planks", 0.8, true],
	"Door": ["wood_planks", 0.8, true],
	"Shutter_": ["wood_planks", 0.8, true],
	"Grass": ["grass_ground", 0.18, false],
}

func _apply_texture(m: BaseMaterial3D) -> void:
	for prefix in TEX:
		if not m.resource_name.begins_with(prefix):
			continue
		var t: Array = TEX[prefix]
		var path := "res://assets/tex/%s.png" % t[0]
		if not ResourceLoader.exists(path):
			return
		m.albedo_texture = load(path)
		if not t[2]:
			m.albedo_color = Color(1, 1, 1)
		else:
			# 貼圖本身偏淺，底色稍微提亮避免整體變暗
			m.albedo_color = m.albedo_color.lightened(0.15)
		var npath := "res://assets/tex/%s_n.png" % t[0]
		if ResourceLoader.exists(npath):
			m.normal_enabled = true
			m.normal_texture = load(npath)
			m.normal_scale = 0.8
		m.uv1_scale = Vector3(t[1], t[1], 1)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		return

func _tune_kingdom_materials(root: Node) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if m == null:
				continue
			_apply_texture(m)
			if m.resource_name == "Window":
				m.emission_enabled = true
				m.emission = Color("ffcf7a")
				m.emission_energy_multiplier = 0.6
			if m.resource_name == "Water":
				m.metallic_specular = 0.9
				m.roughness = 0.08
				m.albedo_color.a = 0.85
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			if m.resource_name.begins_with("Cloth") or m.resource_name == "Banner":
				m.cull_mode = BaseMaterial3D.CULL_DISABLED

# ---------- 草地（MultiMesh＋風） ----------
func _blade_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 3
	var pts := []
	for i in segs + 1:
		var t := float(i) / segs
		var w := 0.05 * (1.0 - t * 0.85)
		pts.append([Vector3(-w, t, 0), Vector3(w, t, 0), t])
	for i in segs:
		var a = pts[i]; var b = pts[i + 1]
		for v in [[a[0], a[2]], [a[1], a[2]], [b[1], b[2]], [a[0], a[2]], [b[1], b[2]], [b[0], b[2]]]:
			st.set_uv(Vector2(0.5, v[1]))
			st.set_normal(Vector3.UP)
			st.add_vertex(v[0])
	return st.commit()

func _on_road_or_building(p: Vector2) -> bool:
	for r in layout.roads:
		var a := Vector2(r.a[0], r.a[2]); var b := Vector2(r.b[0], r.b[2])
		var ab := b - a
		var t: float = clamp((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		if (p - (a + ab * t)).length() < r.w * 0.5 + 0.3:
			return true
	var plaza := Vector2(layout.plaza[0], layout.plaza[2])
	if p.distance_to(plaza) < layout.plaza_radius + 0.5:
		return true
	return false

func _build_grass() -> void:
	grass_mat = ShaderMaterial.new()
	grass_mat.shader = load("res://shaders/grass.gdshader")
	var mesh := _blade_mesh()
	mesh.surface_set_material(0, grass_mat)
	var space := get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var flowers: Array[Transform3D] = []
	var target := 700000
	var radius := 95.0
	var q := PhysicsRayQueryParameters3D.new()
	var attempts := 0
	while xforms.size() < target and attempts < target * 4:
		attempts += 1
		var r := sqrt(rng.randf()) * radius
		var a := rng.randf() * TAU
		var p := Vector2(cos(a) * r, sin(a) * r)
		if _on_road_or_building(p):
			continue
		q.from = Vector3(p.x, 80, p.y)
		q.to = Vector3(p.x, -30, p.y)
		var hit := space.intersect_ray(q)
		if attempts < 400 and OS.get_environment("GRASS_DEBUG") != "":
			print("hit ", "none" if hit.is_empty() else str(hit.collider.get_parent().name) + " n=" + str(hit.normal))
		if hit.is_empty() or not String(hit.collider.get_parent().name).begins_with("Terrain"):
			continue
		if hit.normal.y < 0.8:
			continue
		var outside: bool = r > layout.wall_radius + 4.0
		var h := rng.randf_range(0.25, 0.55) if outside else rng.randf_range(0.1, 0.2)   # 城內是修剪過的短草
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(0.8, h, 0.8))
		basis = basis.rotated(Vector3(rng.randf() - 0.5, 0, rng.randf() - 0.5).normalized(), rng.randf_range(0.0, 0.25))
		xforms.append(Transform3D(basis, hit.position - Vector3(0, 0.02, 0)))
		var tint := rng.randf_range(0.8, 1.15)
		if outside:
			colors.append(Color(tint, tint * rng.randf_range(0.95, 1.05), tint * 0.9))
		else:
			colors.append(Color(tint * 1.05, tint * 1.12, tint * 0.85))
		if rng.randf() < (0.045 if outside else 0.012):
			flowers.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), hit.position + Vector3(0, h * rng.randf_range(0.7, 1.1), 0)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 140.0
	add_child(mmi)
	print("grass blades: ", xforms.size(), " flowers: ", flowers.size())
	_build_flowers(flowers, rng)

func _build_flowers(xs: Array[Transform3D], rng: RandomNumberGenerator) -> void:
	# 小花：五瓣星形平面＋花心，顏色隨機
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 5:
		var a0 := TAU * i / 5.0
		var a1 := a0 + TAU / 10.0
		var a2 := a0 - TAU / 10.0
		for v in [Vector3.ZERO, Vector3(cos(a1), 0, sin(a1)) * 0.035, Vector3(cos(a0), 0, sin(a0)) * 0.075,
				Vector3.ZERO, Vector3(cos(a0), 0, sin(a0)) * 0.075, Vector3(cos(a2), 0, sin(a2)) * 0.035]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.8
	mesh.surface_set_material(0, m)
	var palette := [Color("ffffff"), Color("ffe066"), Color("f7a8c4"), Color("b69cf0"), Color("ff9f6b")]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		mm.set_instance_color(i, palette[rng.randi() % palette.size()])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 90.0
	add_child(mmi)

# ---------- 角色 ----------
func _spawn_actors() -> void:
	if ResourceLoader.exists("res://scenes/actors.gd"):
		pass
	var actors_script := load("res://scripts/actors.gd") if ResourceLoader.exists("res://scripts/actors.gd") else null
	if actors_script:
		var a: Node3D = actors_script.new()
		a.name = "Actors"
		add_child(a)
		a.setup(layout)

# ---------- 截圖 ----------
func _vec(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))

func _ground(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 200, p.z), Vector3(p.x, -50, p.z))
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if not hit.is_empty() else 0.0

func _screenshot_mode() -> void:
	var t := OS.get_environment("TIME")
	if t != "":
		grass_mat.set_shader_parameter("time_override", float(t))
	var cam := Camera3D.new()
	cam.fov = 55
	cam.far = 1200
	add_child(cam)
	var cp := _vec(OS.get_environment("CAM"))
	var lp := _vec(OS.get_environment("LOOK"))
	if OS.get_environment("REL") != "":  # y 當成離地高度
		cp.y += _ground(cp)
		lp.y += _ground(lp)
	cam.global_position = cp
	cam.look_at(lp)
	cam.make_current()
	var frames := int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 90
	for i in frames:
		await get_tree().process_frame
	print("fps ", Engine.get_frames_per_second(), " frames ", frames, " msec ", Time.get_ticks_msec())
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT"))
	print("saved ", OS.get_environment("SHOT"))
	get_tree().quit()
