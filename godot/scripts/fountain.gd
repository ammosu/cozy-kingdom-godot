extends Node3D
## 噴水池的水：疊在生成模型上。模型畫死的藍色水面被蓋在下面，這裡換成會流動的水面、落水、水花。
## 模型空間的量測值（模型高 1.846、底部 y = -0.918；正面 +Z）：
## 下池：池緣頂 0.281H、半徑 0.85 內是水；上盆：盆緣頂 0.633H、半徑 0.40 內是水，四個方向有溢流口（0.5→0.6 往下斜）。
## 水面要略低於池緣，外圈才藏得住。四道落水在 ±X、±Z；魚嘴高 0.79H、Z = 0.40。

const Y0 := -0.918
const H := 1.846
const POOL_H := 0.2785
const BOWL_H := 0.628
const POOL_R := 0.865
const BOWL_R := 0.425
const FALL_R := 0.615
const FALL_HALF_DEG := 21.0
const SPOUT_MOUTH := Vector3(0.0, Y0 + 0.79 * H, 0.40)
const SPOUT_LAND := Vector3(0.0, Y0 + BOWL_H * H, 0.385)

var mats: Array[ShaderMaterial] = []
var root: Node3D

func y_at(h: float) -> float:
	return Y0 + h * H

func setup(model_root: Node3D) -> void:
	root = model_root
	var nt := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.012
	fn.fractal_octaves = 4
	nt.noise = fn
	nt.seamless = true
	nt.width = 512
	nt.height = 512
	nt.generate_mipmaps = true
	# 水面（模型座標，掛在模型底下跟著縮放）
	var fr := FALL_R + 0.05
	var falls := [Vector2(fr, 0.0), Vector2(0.0, fr), Vector2(-fr, 0.0), Vector2(0.0, -fr)]
	var pool_imp := PackedVector3Array()
	for f in falls:
		pool_imp.append(Vector3(f.x, f.y, 1.0))
	pool_imp.append(Vector3.ZERO)
	_disc(POOL_R, y_at(POOL_H), nt, pool_imp, true)
	var bowl_imp := PackedVector3Array()
	bowl_imp.append(Vector3(SPOUT_LAND.x, SPOUT_LAND.z, 0.6))
	for i in 4:
		bowl_imp.append(Vector3.ZERO)
	_disc(BOWL_R, y_at(BOWL_H), nt, bowl_imp, false)
	# 四道落水＋魚嘴
	for i in 4:
		_curtain(TAU * i / 4.0, nt, i * 1.7)
	_spout(nt)
	# 水花（世界座標）
	for f in falls:
		_splash(root.to_global(Vector3(f.x, y_at(POOL_H) + 0.01, f.y)), 1.0)
	_splash(root.to_global(Vector3(SPOUT_LAND.x, y_at(BOWL_H) + 0.01, SPOUT_LAND.z)), 0.45)

func _add(mesh: ArrayMesh, mat: ShaderMaterial) -> void:
	mats.append(mat)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(mi)

func _disc(r: float, y: float, nt: Texture2D, imp: PackedVector3Array, pads: bool) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 48
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		for v in [Vector3.ZERO, Vector3(cos(a1), 0, sin(a1)) * r, Vector3(cos(a0), 0, sin(a0)) * r]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v + Vector3.UP * y)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/fountain_water.gdshader")
	m.set_shader_parameter("noise_tex", nt)
	m.set_shader_parameter("impacts", imp)
	m.set_shader_parameter("radius", r)
	m.set_shader_parameter("pads_on", 1.0 if pads else 0.0)
	_add(st.commit(), m)

func _fall_material(nt: Texture2D, ph: float, across: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/fountain_fall.gdshader")
	m.set_shader_parameter("noise_tex", nt)
	m.set_shader_parameter("stream", ph)
	m.set_shader_parameter("across", across)
	return m

func _curtain(az: float, nt: Texture2D, ph: float) -> void:
	# 水從上盆內側翻過盆緣，再一路往下、稍微往外張，落進下池
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 14
	var nv := 22
	var bot := y_at(POOL_H)
	var half := deg_to_rad(FALL_HALF_DEG)
	var at := func(iu: int, iv: int) -> Array:
		var u := float(iu) / nu
		var v := float(iv) / nv
		var R: float
		var y: float
		if v < 0.22:      # 流過溢流口：貼著盆緣往外、再往下斜
			var k := v / 0.22
			R = lerpf(BOWL_R - 0.03, FALL_R, k)
			y = y_at(0.637 - 0.057 * smoothstep(0.45, 1.0, k))
		else:             # 自由落下，稍微往外張
			var k := (v - 0.22) / 0.78
			R = FALL_R + 0.05 * k * k
			y = lerpf(y_at(0.58), bot, k * k * 0.35 + k * 0.65)
		var a := az + (u - 0.5) * 2.0 * half
		return [Vector3(cos(a) * R, y, sin(a) * R), Vector2(u, v), Vector3(cos(a), 0, sin(a))]
	for iu in nu:
		for iv in nv:
			for c in [[iu, iv], [iu + 1, iv], [iu + 1, iv + 1], [iu, iv], [iu + 1, iv + 1], [iu, iv + 1]]:
				var d: Array = at.call(c[0], c[1])
				st.set_uv(d[1])
				st.set_normal(d[2])
				st.add_vertex(d[0])
	_add(st.commit(), _fall_material(nt, ph, 1.3))

func _spout(nt: Texture2D) -> void:
	# 魚嘴吐出的水柱：沿拋物線的細管
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ns := 16
	var nr := 8
	var r0 := 0.03
	var pt := func(s: float) -> Vector3:
		var p := SPOUT_MOUTH.lerp(SPOUT_LAND, s)
		p.y += sin(s * PI * 0.5) * 0.02 * (1.0 - s)
		p.z += sin(s * PI) * 0.05
		return p
	for i in ns:
		var s0 := float(i) / ns
		var s1 := float(i + 1) / ns
		for j in nr:
			var a0 := TAU * j / nr
			var a1 := TAU * (j + 1) / nr
			var q := []
			for c in [[s0, a0], [s1, a0], [s1, a1], [s0, a0], [s1, a1], [s0, a1]]:
				var n := Vector3(cos(c[1]), 0, sin(c[1]) * 0.6 + 0.0).normalized()
				q.append([pt.call(c[0]) + n * r0 * (1.0 + c[0] * 0.5), Vector2(c[1] / TAU, c[0]), n])
			for d in q:
				st.set_uv(d[1])
				st.set_normal(d[2])
				st.add_vertex(d[0])
	_add(st.commit(), _fall_material(nt, 9.1, 2.0))

func _splash(pos: Vector3, k: float) -> void:
	# 水痕：沿速度拉長的細條（不用小圓球）；十字交叉兩片，任何角度都看得到
	var streak := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.28 * k
	pm.direction = Vector3.UP
	pm.spread = 28.0
	pm.initial_velocity_min = 1.3 * k
	pm.initial_velocity_max = 3.0 * k
	pm.gravity = Vector3(0, -9.8, 0)
	pm.particle_flag_align_y = true
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var fade := Curve.new()
	fade.add_point(Vector2(0, 1)); fade.add_point(Vector2(1, 0.15))
	var ft := CurveTexture.new()
	ft.curve = fade
	pm.scale_curve = ft
	streak.process_material = pm
	streak.draw_pass_1 = _cross_mesh(0.022 * (0.7 + k * 0.3), 0.2 * (0.6 + k * 0.4))
	streak.amount = int(46 * k)
	streak.lifetime = 0.55
	streak.preprocess = 1.0
	streak.visibility_aabb = AABB(Vector3(-3, -2, -3), Vector3(6, 5, 6))
	streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(streak)
	streak.global_position = pos
	# 水霧：柔邊的四邊形，慢慢往上飄散
	var mist := GPUParticles3D.new()
	var mp := ParticleProcessMaterial.new()
	mp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mp.emission_sphere_radius = 0.3 * k
	mp.direction = Vector3.UP
	mp.spread = 55.0
	mp.initial_velocity_min = 0.25
	mp.initial_velocity_max = 0.7
	mp.gravity = Vector3(0, 0.15, 0)
	mp.damping_min = 0.3
	mp.damping_max = 0.6
	mp.scale_min = 0.7
	mp.scale_max = 1.5
	var mc := Curve.new()
	mc.add_point(Vector2(0, 0.25)); mc.add_point(Vector2(1, 1))
	var mct := CurveTexture.new()
	mct.curve = mc
	mp.scale_curve = mct
	var ga := Gradient.new()
	ga.set_color(0, Color(1, 1, 1, 0.16))
	ga.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = ga
	mp.color_ramp = gt
	mist.process_material = mp
	var q := QuadMesh.new()
	q.size = Vector2.ONE * (1.25 * (0.55 + k * 0.45))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft()
	q.material = m
	mist.draw_pass_1 = q
	mist.amount = int(14 * k)
	mist.lifetime = 1.1
	mist.preprocess = 2.0
	mist.visibility_aabb = AABB(Vector3(-3, -2, -3), Vector3(6, 5, 6))
	mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mist)
	mist.global_position = pos

func _soft() -> Texture2D:
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

func _cross_mesh(w: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var d := Vector3(w, 0, 0) if k == 0 else Vector3(0, 0, w)
		var v := [-d - Vector3.UP * h * 0.5, d - Vector3.UP * h * 0.5, d + Vector3.UP * h * 0.5, -d + Vector3.UP * h * 0.5]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uv[i]); st.set_normal(Vector3.UP); st.add_vertex(v[i])
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(0.92, 0.97, 1.0, 0.9)
	m.albedo_texture = _soft()
	mesh.surface_set_material(0, m)
	return mesh

func set_time(t: float) -> void:
	for m in mats:
		m.set_shader_parameter("time_override", t)
