extends Node3D
## 天氣預設：F 鍵切換（截圖用環境變數 FOG=0/1/2/3）。
## 0 平常；1 晨霧：低角度暖陽＋貼地薄霧＋光柱＋飄浮光塵；2 濃霧：能見度低、燈籠光暈明顯；3 雨天：烏雲、雨絲、地面積水。

const AREA := 340.0
const RES := 170
# [名稱, 太陽俯角, 太陽能量, 太陽色, 體積霧底密度, 霧層密度, 霧層厚, 覆蓋率, 距離霧, 環境光, 光塵量, 霧的補光色]
const PRESETS := [
	["平常", -38.0, 2.2, "fff0d4", 0.0015, 0.0, 0.1, 0.0, 0.0005, 0.55, 0.0, "000000"],
	["晨霧", -18.0, 3.0, "ffdcae", 0.0012, 0.15, 13.0, 0.55, 0.82, 0.72, 1.0, "f4ead8"],
	["濃霧", -30.0, 2.0, "fff2dc", 0.0, 0.03, 40.0, 0.95, 1.0, 0.95, 0.6, "f6f3ea"],   # 霧層比屋頂高很多，畫面上看不到霧頂的水平線
	["雨天", -55.0, 0.32, "d3dbe6", 0.0, 0.0, 0.1, 0.0, 0.8, 0.62, 0.0, "000000"],
]
var env: Environment
var sun: DirectionalLight3D
var mat: ShaderMaterial
var vol: FogVolume
var motes: GPUParticles3D
var target: Node3D
var idx := 0
var label: Label
var label_t := 0.0
const GUST_MAX := 4
const BLAST_MAX := 2
const BLAST_R := 8.0
const BLAST_LIFE := 4.5
var blasts: Array = []         # 下劈的衝擊波：{o 落點, t 經過秒數}
const RAIN := 3
var rain: Node3D
var cloud_t := 0.0
const CLOUD_T0 := 4000.0   # 開場時雲的位置
var gusts: Array = []          # 揮劍的風：{o 起點, d 方向, len 最終長度, r 半徑, life 全長, t 經過秒數}

func setup(e: Environment, s: DirectionalLight3D) -> void:
	env = e
	sun = s
	env.volumetric_fog_length = 180.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_temporal_reprojection_amount = 0.85
	RenderingServer.environment_set_volumetric_fog_volume_size(128, 128)
	_build_volume()
	_build_motes()
	rain = load("res://scripts/rain.gd").new()
	rain.name = "Rain"
	add_child(rain)
	var cl := CanvasLayer.new()
	add_child(cl)
	label = Label.new()
	label.position = Vector2(24, 20)
	label.add_theme_font_size_override("font_size", 22)
	label.modulate.a = 0.0
	cl.add_child(label)
	var f := OS.get_environment("FOG")
	apply(int(f) if f != "" else 0)
	label_t = 0.0   # 開場不顯示

func _build_volume() -> void:
	var img := _bake_height()
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.03
	fn.fractal_octaves = 3
	var n3 := NoiseTexture3D.new()
	n3.width = 96; n3.height = 48; n3.depth = 96
	n3.seamless = true
	n3.normalize = true
	n3.noise = fn
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/mist.gdshader")
	mat.set_shader_parameter("height_tex", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("height_rect", Vector4(-AREA * 0.5, -AREA * 0.5, AREA, AREA))
	mat.set_shader_parameter("noise_tex", n3)
	vol = FogVolume.new()
	vol.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	vol.size = Vector3(AREA, 90.0, AREA)
	vol.position = Vector3(0, 30, 0)
	vol.material = mat
	add_child(vol)

func _bake_height() -> Image:
	# 射線量地面高度，霧才會順著山坡。只認地形，房子和牆不算
	var img := Image.create(RES, RES, false, Image.FORMAT_RF)
	var space := get_world_3d().direct_space_state
	for y in RES:
		for x in RES:
			var wx := (float(x) + 0.5) / RES * AREA - AREA * 0.5
			var wz := (float(y) + 0.5) / RES * AREA - AREA * 0.5
			var q := PhysicsRayQueryParameters3D.create(Vector3(wx, 150, wz), Vector3(wx, -60, wz))
			var h := 0.0
			for i in 6:
				var hit := space.intersect_ray(q)
				if hit.is_empty():
					break
				if String(hit.collider.get_parent().name).begins_with("Terrain"):
					h = hit.position.y
					break
				q.exclude = q.exclude + [hit.rid]
			img.set_pixel(x, y, Color(h, 0, 0))
	return img

func _build_motes() -> void:
	motes = GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(16, 5, 16)
	pm.gravity = Vector3(0, 0.02, 0)
	pm.direction = Vector3(1, 0.2, 0.5)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0)); curve.add_point(Vector2(.2, 1)); curve.add_point(Vector2(.8, 1)); curve.add_point(Vector2(1, 0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(1.0, 0.86, 0.55, 0.8)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g; tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(.5, .5); tex.fill_to = Vector2(1, .5); tex.width = 32; tex.height = 32
	m.albedo_texture = tex
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	q.material = m
	motes.draw_pass_1 = q
	motes.process_material = pm
	motes.amount = 260
	motes.lifetime = 7.0
	motes.preprocess = 7.0
	motes.local_coords = false
	motes.visibility_aabb = AABB(Vector3(-40, -15, -40), Vector3(80, 30, 80))
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(motes)

func apply(i: int) -> void:
	idx = i % PRESETS.size()
	var p: Array = PRESETS[idx]
	sun.rotation_degrees.x = p[1]
	sun.light_energy = p[2]
	sun.light_color = Color(p[3])
	sun.light_volumetric_fog_energy = 1.2 if idx == 0 else 2.6
	env.volumetric_fog_density = p[4]
	env.volumetric_fog_enabled = true
	# 霧天用距離式的霧：近景保留對比，越遠越濃，最遠處完全融進霧色（濃度欄位在這個模式是最大不透明度）
	if idx == 0:
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_density = 0.0011
	else:
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_density = p[8]
		env.fog_depth_begin = [0.0, 18.0, 4.0, 10.0][idx]
		env.fog_depth_end = [0.0, 420.0, 165.0, 300.0][idx]
		env.fog_depth_curve = [1.0, 1.3, 0.72, 1.1][idx]
	env.fog_light_energy = [1.0, 1.0, 1.5, 0.72][idx]   # 濃霧時遠山要跟天空同亮，不然會留下深色剪影
	env.fog_sky_affect = [0.08, 0.45, 1.0, 0.55][idx]
	env.fog_aerial_perspective = 0.45 if idx == 0 else 0.0   # 霧天不混天空色，山才會整片融進霧色
	env.volumetric_fog_sky_affect = 1.0 if idx == 0 else 0.2   # 霧不要把天空壓暗
	var sky := env.sky.sky_material as ShaderMaterial
	sky.set_shader_parameter("coverage", [0.47, 0.4, 0.5, 0.92][idx])
	sky.set_shader_parameter("haze", [1.0, 3.0, 1.0, 1.0][idx])
	sky.set_shader_parameter("flat_mix", 1.0 if idx == 2 else 0.0)
	sky.set_shader_parameter("storm", 1.0 if idx == RAIN else 0.0)
	sky.set_shader_parameter("flat_col", Color("efece4"))
	env.ambient_light_energy = p[9]
	# 濃霧時霧色、天空色要相同，遠山才會整片消失，不留深色剪影
	env.fog_light_color = [Color("cfe3f2"), Color(p[3]).lerp(Color("dfe8f2"), 0.55), Color("efece4"), Color("9aa4b2")][idx]
	var g := Color(p[11])
	mat.set_shader_parameter("glow", g)
	env.volumetric_fog_emission = g
	env.volumetric_fog_emission_energy = 0.0 if idx == 0 else p[4] * 0.9
	env.volumetric_fog_gi_inject = 1.0 if idx == 0 else 0.25
	env.adjustment_saturation = [1.05, 0.98, 0.8, 0.85][idx]   # 霧裡的顏色會變淡，前景不能還是飽和的鮮綠
	mat.set_shader_parameter("density", p[5])
	mat.set_shader_parameter("ground_density", 0.0 if idx == 0 or idx == RAIN else 0.2)
	mat.set_shader_parameter("near_start", 8.0 if idx < 2 else 14.0)
	mat.set_shader_parameter("mist_height", p[6])
	mat.set_shader_parameter("coverage", p[7])
	vol.visible = p[5] > 0.0
	motes.emitting = p[10] > 0.0
	motes.visible = p[10] > 0.0
	motes.amount_ratio = maxf(p[10], 0.01)
	env.ssr_enabled = idx == RAIN     # 只有雨天地面有積水要反射
	if rain:
		rain.set_active(idx == RAIN)
	get_parent().set_wet(1.0 if idx == RAIN else 0.0)
	label.text = "天氣：%s（F 切換）" % p[0]
	label_t = 2.0

func _unhandled_key_input(e: InputEvent) -> void:
	if e.is_pressed() and not e.is_echo() and (e as InputEventKey).keycode == KEY_F:
		apply(idx + 1)

## 揮劍時呼叫：從 origin 往 dir 吹開一道風，霧散開後慢慢補回來
func gust(origin: Vector3, dir: Vector3, heavy: bool) -> void:
	if gusts.size() >= GUST_MAX:
		gusts.pop_front()
	gusts.append({"o": origin, "d": dir.normalized(), "len": 16.0 if heavy else 11.0, "r": 3.4 if heavy else 2.4, "life": 2.8 if heavy else 2.2, "t": 0.0})

## 下劈落地：衝擊波從落點往外推，霧堆在波前翻起，之後從外圍回流
func blast(origin: Vector3) -> void:
	if blasts.size() >= BLAST_MAX:
		blasts.pop_front()
	blasts.append({"o": origin, "t": 0.0})

func _update_gusts(dt: float) -> void:
	var had := not gusts.is_empty() or not blasts.is_empty()
	var kept := []
	for g in gusts:
		g.t += dt
		if g.t < g.life:
			kept.append(g)
	gusts = kept
	kept = []
	for b in blasts:
		b.t += dt
		if b.t < BLAST_LIFE:
			kept.append(b)
	blasts = kept
	if not had:
		return
	var pa := PackedVector4Array(); var pb := PackedVector4Array(); var pr := PackedFloat32Array()
	pa.resize(GUST_MAX); pb.resize(GUST_MAX); pr.resize(GUST_MAX)
	for i in gusts.size():
		var g: Dictionary = gusts[i]
		var grow := 1.0 - pow(1.0 - clampf(g.t / 0.25, 0.0, 1.0), 3.0)   # 風一下子衝出去
		var close := smoothstep(g.life, 0.5, g.t)                         # 通道從兩側慢慢合攏，不是整片變淡
		pa[i] = Vector4(g.o.x, g.o.y, g.o.z, g.len * grow)
		pb[i] = Vector4(g.d.x, g.d.y, g.d.z, smoothstep(0.0, 0.12, close))
		pr[i] = g.r * (0.5 + 0.5 * grow) * close
	var ba := PackedVector4Array(); var bb := PackedVector4Array()
	ba.resize(BLAST_MAX); bb.resize(BLAST_MAX)
	for i in blasts.size():
		var b: Dictionary = blasts[i]
		var front: float = BLAST_R * (1.0 - exp(-b.t / 0.3))                 # 一開始極快，很快被空氣減速
		var hole: float = front * (1.0 - smoothstep(1.0, BLAST_LIFE, b.t))   # 霧從外圍往中心回流
		ba[i] = Vector4(b.o.x, b.o.y, b.o.z, maxf(front, 0.01))
		bb[i] = Vector4(hole, exp(-b.t / 0.8), front * 0.55, 0.0)
	mat.set_shader_parameter("gust_a", pa)
	mat.set_shader_parameter("gust_b", pb)
	mat.set_shader_parameter("gust_r", pr)
	mat.set_shader_parameter("blast_a", ba)
	mat.set_shader_parameter("blast_b", bb)

func _process(dt: float) -> void:
	_update_gusts(dt)
	cloud_t += dt
	RenderingServer.global_shader_parameter_set("cloud_t", cloud_t + CLOUD_T0)
	var cam := get_viewport().get_camera_3d()
	if cam:
		mat.set_shader_parameter("cam_pos", cam.global_position)
	if target and motes.visible:
		motes.global_position = target.global_position + Vector3(0, 2.5, 0)
	label_t -= dt
	label.modulate.a = clampf(label_t, 0.0, 1.0)
