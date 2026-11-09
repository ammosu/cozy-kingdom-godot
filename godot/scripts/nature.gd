extends Node3D
## 植被：樹（MultiMesh、會投影子）、灌木（貼著房子牆腳、城牆腳、林緣）。
## 樹的位置來自 kingdom_layout.json 的 trees；模型由 blender/gen_trees.py 產生。

const SPECIES := {
	"oak": ["oak_a", "oak_b", "oak_c"],
	"pine": ["pine_a", "pine_b"],
	"bush": ["bush_a", "bush_b"],
}
var foliage_mat: ShaderMaterial
var card_mat: ShaderMaterial
var needle_mat: ShaderMaterial
const NEEDLE_LUM := 0.135
var bark_mat: StandardMaterial3D
var layout: Dictionary

func setup(lay: Dictionary) -> void:
	layout = lay
	foliage_mat = ShaderMaterial.new()
	foliage_mat.shader = load("res://shaders/foliage.gdshader")
	var nt := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_CELLULAR
	fn.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_DIV
	fn.frequency = 0.04
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM
	fn.fractal_octaves = 2
	nt.noise = fn
	nt.seamless = true
	nt.width = 256; nt.height = 256
	nt.generate_mipmaps = true
	foliage_mat.set_shader_parameter("leaf_noise", nt)
	if ResourceLoader.exists("res://assets/sprites/leaf_cluster.png"):
		card_mat = ShaderMaterial.new()
		card_mat.shader = load("res://shaders/foliage_card.gdshader")
		card_mat.set_shader_parameter("leaf_noise", nt)
		card_mat.set_shader_parameter("leaf_tex", load("res://assets/sprites/leaf_cluster.png"))
		needle_mat = card_mat.duplicate()
		needle_mat.set_shader_parameter("leaf_tex", load("res://assets/sprites/pine_branch.png"))
		needle_mat.set_shader_parameter("tex_lum", NEEDLE_LUM)
		needle_mat.set_shader_parameter("sway_height", 14.0)
	bark_mat = StandardMaterial3D.new()
	bark_mat.vertex_color_use_as_albedo = true
	bark_mat.roughness = 0.95
	if ResourceLoader.exists("res://assets/tex/wood_planks_n.png"):
		bark_mat.normal_enabled = true
		bark_mat.normal_texture = load("res://assets/tex/wood_planks_n.png")
		bark_mat.uv1_triplanar = true
		bark_mat.uv1_scale = Vector3(0.6, 0.15, 0.6)
		bark_mat.albedo_texture = load("res://assets/tex/wood_planks.png")
		bark_mat.albedo_color = Color(1.0, 0.9, 0.78)
	_plant_trees()
	_plant_bushes()
	_plant_far_forest()

func set_time(t: float) -> void:
	foliage_mat.set_shader_parameter("time_override", t)
	if card_mat:
		card_mat.set_shader_parameter("time_override", t)
		needle_mat.set_shader_parameter("time_override", t)
	for m in cover_mats:
		m.set_shader_parameter("time_override", t)

## 每幀由 actors 呼叫。points：最多 6 個 Vector4(x, y, z, 半徑)；第 0 個是玩家
func set_pushers(points: PackedVector4Array, waist: Vector3, r: float) -> void:
	for m in cover_mats:
		m.set_shader_parameter("pushers", points)
	foliage_mat.set_shader_parameter("pusher", Vector4(waist.x, waist.y, waist.z, r))
	if card_mat:
		card_mat.set_shader_parameter("pusher", Vector4(waist.x, waist.y, waist.z, r))
		needle_mat.set_shader_parameter("pusher", Vector4(waist.x, waist.y, waist.z, r))

func _parts(file: String) -> Dictionary:
	var scene: Node = load("res://assets/nature/%s.glb" % file).instantiate()
	var out := {}
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		out[String(mi.name)] = mi.mesh
	scene.free()
	return out

func _multimesh(mesh: Mesh, mat: Material, xs: Array, shadow: bool, vis_end: float) -> void:
	if xs.is_empty():
		return
	var m := mesh.duplicate() as Mesh
	for i in m.get_surface_count():
		m.surface_set_material(i, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if vis_end > 0:
		mmi.visibility_range_end = vis_end
		mmi.visibility_range_end_margin = 10.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi)

func _plant(groups: Dictionary, shadow: bool, vis_end := 0.0) -> void:
	for file in groups:
		var parts := _parts(file)
		if parts.has("Trunk"):
			_multimesh(parts["Trunk"], bark_mat, groups[file], shadow, vis_end)
		if parts.has("Leaves"):
			_multimesh(parts["Leaves"], foliage_mat, groups[file], shadow, vis_end)
		if parts.has("LeafCards") and card_mat:
			_multimesh(parts["LeafCards"], card_mat, groups[file], shadow, vis_end)
		if parts.has("NeedleCards") and needle_mat:
			_multimesh(parts["NeedleCards"], needle_mat, groups[file], shadow, vis_end)

func _plant_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var groups := {}
	for p in layout.trees:
		var pos := Vector3(p[0], p[1], p[2])
		# 遠處（山坡上）多針葉樹，近城處多闊葉樹
		var r := Vector2(pos.x, pos.z).length()
		var kind := "pine" if rng.randf() < clamp((r - 70.0) / 80.0, 0.15, 0.8) else "oak"
		var file: String = SPECIES[kind][rng.randi() % SPECIES[kind].size()]
		var s := rng.randf_range(0.8, 1.25)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.1), s))
		groups.get_or_add(file, []).append(Transform3D(b, pos - Vector3(0, 0.1, 0)))
	_plant(groups, true)

## 遠山的樹林：交叉面片的遠景樹，一片片聚成林相，讓山坡不再是一塊平滑的綠幕
func _plant_far_forest() -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sprites/sprites.json"))
	var space := get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var forest := FastNoiseLite.new(); forest.seed = 12; forest.frequency = 0.014; forest.fractal_octaves = 3
	var groups := {"far_pine": [], "far_oak": []}
	var n := 0
	var attempts := 0
	while n < 15000 and attempts < 110000:
		attempts += 1
		var r := sqrt(rng.randf()) * 300.0 + 145.0
		var a := rng.randf() * TAU
		var p := Vector2(cos(a), sin(a)) * r
		if forest.get_noise_2dv(p) < -0.22:   # 林與林之間留空地
			continue
		if abs(p.x) < 16.0 and p.y > 0.0:      # 南門大道的視線通廊
			continue
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 400, p.y), Vector3(p.x, -60, p.y))
		var hit := space.intersect_ray(q)
		if hit.is_empty() or hit.normal.y < 0.6:
			continue
		var kind := "far_pine" if rng.randf() < clampf((hit.position.y - 8.0) / 40.0, 0.35, 0.92) else "far_oak"
		var s := rng.randf_range(10.0, 17.0) * (1.0 if kind == "far_pine" else 0.75)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
		var v := rng.randf_range(0.82, 1.1)
		groups[kind].append([Transform3D(b, hit.position - Vector3(0, 0.6, 0)), Color(v, v, v)])
		n += 1
	var pnoise := NoiseTexture2D.new()
	var pf := FastNoiseLite.new(); pf.frequency = 0.02
	pnoise.noise = pf; pnoise.seamless = true; pnoise.width = 64; pnoise.height = 64
	for kind in groups:
		var xs: Array = groups[kind]
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/grass_card.gdshader")
		mat.set_shader_parameter("albedo_tex", load("res://assets/sprites/%s.png" % kind))
		mat.set_shader_parameter("patch_noise", pnoise)
		mat.set_shader_parameter("tint_amount", 0.0)
		mat.set_shader_parameter("wind_strength", 0.0)
		mat.set_shader_parameter("root_color", Color(0.3, 0.42, 0.28))
		var mesh := _card_mesh(meta[kind], 2)
		mesh.surface_set_material(0, mat)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = xs.size()
		for i in xs.size():
			mm.set_instance_transform(i, xs[i][0])
			mm.set_instance_color(i, xs[i][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(mmi)

func _terrain_hit(space: PhysicsDirectSpaceState3D, x: float, z: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 80, z), Vector3(x, -30, z))
	var hit := space.intersect_ray(q)
	if hit.is_empty() or not String(hit.collider.get_parent().name).begins_with("Terrain"):
		return {}
	return hit

func _plant_bushes() -> void:
	var space := get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var groups := {}
	var main := get_parent()
	var count := 0
	# 1) 房子牆腳：在房子附近找「自己落在地形上、往房子中心 1.2m 會打到建築」的點
	for h in layout.houses:
		var c := Vector2(h.pos[0], h.pos[2])
		var n := 0
		for k in 40:
			if n >= rng.randi_range(2, 5):
				break
			var a := rng.randf() * TAU
			var d := rng.randf_range(2.5, 7.0)
			var p := c + Vector2(cos(a), sin(a)) * d
			if main._on_road_or_building(p):
				continue
			var hit := _terrain_hit(space, p.x, p.y)
			if hit.is_empty():
				continue
			var inward := p + (c - p).normalized() * 1.3
			if not _terrain_hit(space, inward.x, inward.y).is_empty():
				continue   # 往內還是地面：不是牆腳
			_add_bush(groups, rng, hit.position, rng.randf_range(0.7, 1.1))
			n += 1; count += 1
	# 2) 城牆外牆腳、林間
	var wr: float = layout.wall_radius
	for k in 900:
		var a := rng.randf() * TAU
		var r := wr + 3.5 + rng.randf_range(0.0, 1.5) if k < 300 else rng.randf_range(wr + 8, 140.0)
		var p := Vector2(cos(a), sin(a)) * r
		if main._on_road_or_building(p) or (abs(p.x) < 10 and p.y > 0):   # 避開南門大道（Godot +Z 是南）
			continue
		var hit := _terrain_hit(space, p.x, p.y)
		if hit.is_empty() or hit.normal.y < 0.85:
			continue
		_add_bush(groups, rng, hit.position, rng.randf_range(0.8, 1.6))
		count += 1
	_plant(groups, true, 120.0)
	print("bushes: ", count)

func _add_bush(groups: Dictionary, rng: RandomNumberGenerator, pos: Vector3, s: float) -> void:
	var file: String = SPECIES.bush[rng.randi() % SPECIES.bush.size()]
	var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.1), s))
	groups.get_or_add(file, []).append(Transform3D(b, pos - Vector3(0, 0.08, 0)))

# ---------- 地被：草叢、花叢、蕨類（Codex 透明元件＋交叉面片） ----------
# [元件, 城外高度範圍, 城內高度範圍（0 = 城內不種）]
const COVER := {
	"grass_clump": [Vector2(0.35, 0.6), Vector2(0.16, 0.26)],
	"grass_tall": [Vector2(0.6, 0.95), Vector2.ZERO],
	"flowers_daisy": [Vector2(0.3, 0.45), Vector2(0.22, 0.3)],
	"flowers_poppy": [Vector2(0.4, 0.6), Vector2.ZERO],
	"flowers_lavender": [Vector2(0.45, 0.65), Vector2(0.35, 0.45)],
	"flowers_buttercup": [Vector2(0.25, 0.4), Vector2(0.2, 0.28)],
	"fern": [Vector2(0.5, 0.85), Vector2.ZERO],
}
var cover_mats: Array[ShaderMaterial] = []

func _card_mesh(aspect: float, cards: int) -> ArrayMesh:
	# cards 片寬 aspect、高 1 的面片，繞 Y 軸平均交叉；原點在底部中央
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in cards:
		var a := PI * k / cards
		var d := Vector3(cos(a), 0, sin(a)) * aspect * 0.5
		var v := [-d, d, d + Vector3.UP, -d + Vector3.UP]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uv[i]); st.set_normal(Vector3.UP); st.add_vertex(v[i])
	return st.commit()

func plant_ground_cover(main: Node) -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sprites/sprites.json"))
	var space := get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var dens := FastNoiseLite.new(); dens.seed = 3; dens.frequency = 0.035; dens.fractal_octaves = 3
	var kindn := FastNoiseLite.new(); kindn.seed = 9; kindn.frequency = 0.06
	var pnoise := NoiseTexture2D.new(); var pf := FastNoiseLite.new(); pf.frequency = 0.02; pf.fractal_octaves = 3
	pnoise.noise = pf; pnoise.seamless = true; pnoise.width = 256; pnoise.height = 256
	var flowers := ["flowers_daisy", "flowers_poppy", "flowers_lavender", "flowers_buttercup"]
	var groups := {}
	for k in COVER:
		groups[k] = []
	var trees: Array = layout.trees
	var radius := 150.0
	var target := 480000
	var placed := 0
	var attempts := 0
	var wr: float = layout.wall_radius
	while placed < target and attempts < target * 3:
		attempts += 1
		var r := sqrt(rng.randf()) * radius
		var a := rng.randf() * TAU
		var p := Vector2(cos(a) * r, sin(a) * r)
		var d := dens.get_noise_2dv(p) * 0.5 + 0.5
		if rng.randf() < 0.72 * (1.0 - smoothstep(0.36, 0.56, d)):   # 留空地，邊緣漸變，不會一刀切
			continue
		var far := clampf((r - 105.0) / 45.0, 0.0, 1.0)   # 105 m 外逐漸稀疏（玩家多半在城附近）
		if rng.randf() > (0.12 + 0.88 * d * d) * (1.0 - far * 0.6):   # 疏密不均：有濃密處也有稀疏處
			continue
		if main._on_road_or_building(p, -0.2):   # 草可以稍微長進路緣，路邊才不會是一刀切
			continue
		var hit := _terrain_hit(space, p.x, p.y)
		if hit.is_empty() or hit.normal.y < 0.8:
			continue
		var outside := r > wr + 4.0
		var kind := "grass_clump"
		var kn := kindn.get_noise_2dv(p) * 0.5 + 0.5
		var u := rng.randf()
		var near_tree := false
		if outside and u < 0.3:
			for t in trees:
				if absf(t[0] - p.x) < 3.5 and absf(t[2] - p.y) < 3.5:
					near_tree = true; break
		if near_tree and u < 0.12:
			kind = "fern"
		elif outside and d > 0.55 and u < 0.25:
			kind = "grass_tall"
		elif u > (0.955 if outside else 0.98):
			# 花一片一片長：同一區以同一種花為主
			kind = flowers[int(kn * 3.99)] if rng.randf() < 0.8 else flowers[rng.randi() % 4]
		var hr: Vector2 = COVER[kind][0] if outside else COVER[kind][1]
		if hr == Vector2.ZERO:
			kind = "grass_clump"; hr = COVER[kind][1]
		if not meta.has(kind):
			continue
		var h := rng.randf_range(hr.x, hr.y) * (0.8 + 0.4 * d)
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		b = b.rotated(Vector3(rng.randf() - 0.5, 0, rng.randf() - 0.5).normalized(), rng.randf_range(0.0, 0.12))
		var wide := 1.0 if outside or not kind.begins_with("grass") else 2.0   # 城內修剪過的草：矮而寬，連成一片
		b = b.scaled(Vector3(h * wide, h, h * wide))
		var tint := rng.randf_range(0.88, 1.12)
		groups[kind].append([Transform3D(b, hit.position - Vector3(0, 0.03, 0)), Color(tint, tint, tint)])
		placed += 1
	var summary := []
	for kind in groups:
		var xs: Array = groups[kind]
		if xs.is_empty():
			continue
		summary.append("%s=%d" % [kind, xs.size()])
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/grass_card.gdshader")
		mat.set_shader_parameter("albedo_tex", load("res://assets/sprites/%s.png" % kind))
		mat.set_shader_parameter("patch_noise", pnoise)
		if kind.begins_with("flowers"):
			mat.set_shader_parameter("tint_amount", 0.15)
		cover_mats.append(mat)
		var mesh := _card_mesh(meta[kind], 2 if kind.begins_with("flowers") or kind == "fern" else 3)
		mesh.surface_set_material(0, mat)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = xs.size()
		for i in xs.size():
			mm.set_instance_transform(i, xs[i][0])
			mm.set_instance_color(i, xs[i][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(mmi)
	print("ground cover: ", ", ".join(summary))
