extends Node3D
## 輕量特效：billboard 粒子池（踏草、揚塵、火花）與揮劍軌跡。
## 自己算位置，不用 GPUParticles 的 emit_particle：粒子少、行為可重現（截圖時也一樣）。

const CAP := 96
# 種類 → [貼圖(空字串 = 程序化光點), 重力, 空氣阻力, 加法混合]
const KINDS := {
	"blade": ["fx_blade", 6.5, 1.2, false],
	"petal": ["fx_petal", 2.2, 2.6, false],
	"dust": ["fx_dust", -0.25, 3.0, false],
	"spark": ["", 9.0, 1.0, true],
}
var pools := {}
var trail_mesh: ImmediateMesh
var trail_pts: Array = []   # [hilt, tip, age]
const TRAIL_LIFE := 0.16
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = 21
	for k in KINDS:
		var d: Array = KINDS[k]
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if d[3]:
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		var path := "res://assets/sprites/%s.png" % d[0]
		if d[0] != "" and ResourceLoader.exists(path):
			m.albedo_texture = load(path)
		else:
			m.albedo_texture = _dot()
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		q.material = m
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = q
		mm.instance_count = CAP
		mm.visible_instance_count = 0
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.custom_aabb = AABB(Vector3(-2000, -500, -2000), Vector3(4000, 1000, 4000))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(mi)
		pools[k] = {"mm": mm, "list": [], "cfg": d}
	trail_mesh = ImmediateMesh.new()
	var ti := MeshInstance3D.new()
	ti.mesh = trail_mesh
	ti.custom_aabb = AABB(Vector3(-2000, -500, -2000), Vector3(4000, 1000, 4000))
	ti.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ti.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.vertex_color_use_as_albedo = true
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	ti.material_override = tm
	add_child(ti)

func _dot() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(.5, .5)
	t.fill_to = Vector2(1, .5)
	t.width = 64
	t.height = 64
	return t

## 噴一批粒子：n 顆、spread 水平速度、up 上升速度、size 公尺、life 秒
func burst(kind: String, pos: Vector3, n: int, spread: float, up: float, size: float, life: float, tint := Color.WHITE) -> void:
	var p: Dictionary = pools[kind]
	for i in n:
		if p.list.size() >= CAP:
			p.list.pop_front()
		var a := rng.randf() * TAU
		var v := Vector3(cos(a), 0, sin(a)) * rng.randf_range(spread * 0.4, spread) + Vector3.UP * rng.randf_range(up * 0.5, up)
		var l := life * rng.randf_range(0.7, 1.2)
		p.list.append({"p": pos + Vector3(rng.randf_range(-.08, .08), rng.randf_range(0, .1), rng.randf_range(-.08, .08)),
			"v": v, "age": 0.0, "life": l, "size": size * rng.randf_range(0.75, 1.25), "c": tint})

func add_trail(hilt: Vector3, tip: Vector3) -> void:
	trail_pts.append([hilt, tip, 0.0])

func _process(dt: float) -> void:
	for k in pools:
		var p: Dictionary = pools[k]
		var g: float = p.cfg[1]
		var drag: float = p.cfg[2]
		var alive := []
		for q in p.list:
			q.age += dt
			if q.age >= q.life:
				continue
			q.v.y -= g * dt
			q.v *= exp(-drag * dt)
			q.p += q.v * dt
			alive.append(q)
		p.list = alive
		var mm: MultiMesh = p.mm
		mm.visible_instance_count = alive.size()
		for i in alive.size():
			var q: Dictionary = alive[i]
			var f: float = q.age / q.life
			var s: float = q.size * (1.0 + f * 1.4 if k == "dust" else 1.0 - f * 0.3)
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), q.p))
			var c: Color = q.c
			c.a *= (1.0 - f) * (0.55 if k == "dust" else 1.0)
			mm.set_instance_color(i, c)
	_draw_trail(dt)

func _draw_trail(dt: float) -> void:
	trail_mesh.clear_surfaces()
	var kept := []
	for s in trail_pts:
		s[2] += dt
		if s[2] < TRAIL_LIFE:
			kept.append(s)
	trail_pts = kept
	if trail_pts.size() < 2:
		return
	trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for s in trail_pts:
		var a: float = pow(1.0 - s[2] / TRAIL_LIFE, 1.5)
		trail_mesh.surface_set_color(Color(1.0, .95, .75, 0.0))
		trail_mesh.surface_add_vertex(s[0].lerp(s[1], 0.25))
		trail_mesh.surface_set_color(Color(1.0, .92, .7, a * 0.85))
		trail_mesh.surface_add_vertex(s[1])
	trail_mesh.surface_end()
