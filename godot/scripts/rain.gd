extends Node3D
## 雨天：跟著鏡頭的雨絲、打到地面的水圈、雨聲。高度場從上往下拍場景，屋頂和城門底下就不會淋到雨。

const BOX := Vector3(20, 7, 20)   # 加上往前移的 9 m 要落在高度場內，超出範圍的雨會在半空中判定成碰撞
var drops: GPUParticles3D
var rings: GPUParticles3D
var field: GPUParticlesCollisionHeightField3D
var audio: AudioStreamPlayer
var active := false
var vol := 0.0

func _ready() -> void:
	field = GPUParticlesCollisionHeightField3D.new()
	field.size = Vector3(64, 60, 64)
	field.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_1024
	field.follow_camera_enabled = true
	field.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	add_child(field)
	_make_rings()
	_make_drops()
	var s: AudioStreamWAV = load("res://assets/sfx/rain_loop.wav")
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = int(s.get_length() * s.mix_rate)
	audio = AudioStreamPlayer.new()
	audio.stream = s
	audio.volume_db = -60.0
	add_child(audio)
	set_active(false)

func _ramp(from_a: float, to_a: float, grow: bool) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, from_a) if grow else Color(1, 1, 1, from_a))
	g.set_color(1, Color(1, 1, 1, to_a))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t

func _make_rings() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.color_ramp = _ramp(1.0, 1.0, true)     # 紅色通道當作「生命進度」給 shader 算環的半徑
	var pl := PlaneMesh.new()
	pl.size = Vector2(0.42, 0.42)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/rain_splash.gdshader")
	pl.material = m
	rings = GPUParticles3D.new()
	rings.amount = 2400
	rings.lifetime = 0.32
	rings.local_coords = false
	rings.emitting = false
	rings.process_material = pm
	rings.draw_pass_1 = pl
	rings.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	rings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rings)

func _make_drops() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = BOX
	pm.direction = Vector3(0.1, -1.0, 0.05)
	pm.spread = 1.5
	pm.initial_velocity_min = 18.0
	pm.initial_velocity_max = 23.0
	pm.gravity = Vector3(0, -6, 0)
	pm.particle_flag_align_y = true
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	pm.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_AT_COLLISION
	pm.sub_emitter_amount_at_collision = 1
	var q := QuadMesh.new()
	q.size = Vector2(0.014, 0.75)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/rain.gdshader")
	q.material = m
	drops = GPUParticles3D.new()
	drops.amount = 7000
	drops.lifetime = 1.0
	drops.local_coords = false
	drops.process_material = pm
	drops.draw_pass_1 = q
	drops.collision_base_size = 0.02
	drops.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(drops)
	drops.sub_emitter = drops.get_path_to(rings)

func set_active(on: bool) -> void:
	active = on
	drops.emitting = on
	drops.visible = on
	rings.visible = on
	field.visible = on
	if on and not audio.playing:
		audio.play()

func _process(dt: float) -> void:
	vol = move_toward(vol, 1.0 if active else 0.0, dt * 1.5)
	if audio.playing:
		audio.volume_db = linear_to_db(maxf(vol, 0.001)) - 6.0
		if vol <= 0.0 and not active:
			audio.stop()
	if not active:
		return
	var cam := get_viewport().get_camera_3d()
	if cam:
		var fwd := -cam.global_basis.z
		drops.global_position = cam.global_position + Vector3(fwd.x, 0, fwd.z).normalized() * 9.0 + Vector3(0, 9, 0)
		field.global_position = cam.global_position
