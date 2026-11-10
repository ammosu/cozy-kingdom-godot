extends Node3D
## 跟在玩家身邊的小光靈。帶一盞會閃動、有陰影的點光，所以經過的草、牆和角色都會被照到；
## 看到前方的村民或敵人會飛過去，靠近時光變強、換色。設 WISP=0 可關掉。

const REST_LEASH := 3.2       # 平常離玩家的最遠距離
const FOCUS_ENTER := 7.0      # 多近開始注意
const FOCUS_LEAVE := 9.0      # 多遠放棄（比開始大，才不會在邊界來回切換）
const SNAP_DIST := 15.0       # 超過就是玩家瞬移了，直接跟過去
const WALL_GAP := 0.3
const COL_IDLE := Color("ffd27a")
const COL_FRIEND := Color("ffe9a8")
const COL_FOE := Color("c6e6ff")
const ENERGY_IDLE := 2.0
const ENERGY_FOCUS := 2.4
const FOE_HEAD := 1.6
const FRIEND_HEAD := 1.45

var a: Node3D
var light: OmniLight3D
var mat: ShaderMaterial
var sparks: Array[MeshInstance3D] = []
var vel := Vector3.ZERO
var offset := Vector3(0.7, 0.2, 0.4)
var dart_left := 1.0
var scan_left := 0.0
var leash := REST_LEASH
var focus: Node3D
var focus_foe := false
var level := 0.0              # 0 平常、1 正在注意某人
var tint := COL_IDLE
var t := 0.0
var rng := RandomNumberGenerator.new()

func setup(actors: Node3D) -> void:
	a = actors
	rng.seed = 11
	top_level = true
	global_position = _anchor() + offset
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/wisp.gdshader")
	_quad(0.55)
	for i in 2:
		sparks.append(_quad(0.14))
	_make_trail()
	light = OmniLight3D.new()
	light.light_color = COL_IDLE
	light.light_energy = ENERGY_IDLE
	light.omni_range = 5.5
	light.shadow_enabled = true
	light.shadow_blur = 1.4
	light.light_indirect_energy = 0.0     # 不進 SDFGI，閃動才不會讓整片間接光跟著抖
	light.light_volumetric_fog_energy = 2.5
	add_child(light)

func _quad(size: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 1.0
	add_child(mi)
	return mi

func _make_trail() -> void:
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.03
	pm.initial_velocity_max = 0.18
	pm.gravity = Vector3(0, -0.22, 0)
	pm.color_ramp = ramp
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 0.09
	q.material = mat
	var p := GPUParticles3D.new()
	p.amount = 36
	p.lifetime = 0.9
	p.local_coords = false
	p.process_material = pm
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)

func _anchor() -> Vector3:
	return a.player.global_position + Vector3(0, 2.9 if a.mounted else 1.35, 0)

func _pick_offset() -> void:
	var ang := rng.randf() * TAU
	var r := rng.randf_range(0.6, 0.85) if focus else rng.randf_range(0.65, 1.0)
	offset = Vector3(cos(ang) * r, rng.randf_range(-0.25, 0.45), sin(ang) * r)
	dart_left = rng.randf_range(1.2, 3.2)

## 從 from 到 to 之間如果有牆，回傳牆前面一點的位置
func _clear(from: Vector3, to: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [a.player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return to
	return hit.position + (from - to).normalized() * WALL_GAP

func _scan() -> void:
	var anchor := _anchor()
	var fwd: Vector3 = -a.player.global_basis.z
	var best: Node3D
	var best_foe := false
	var best_score := INF
	for group in [[a.enemies, true], [a.villagers, false], [a.stall_vs, false]]:
		for d in group[0]:
			var n: Node3D = d.node
			var to: Vector3 = n.global_position - a.player.global_position
			to.y = 0.0
			var dist := to.length()
			if dist > (FOCUS_LEAVE if n == focus else FOCUS_ENTER):
				continue
			if n != focus and to.normalized().dot(fwd) < 0.15:
				continue
			var score := dist - (1.5 if group[1] else 0.0) - (1.0 if n == focus else 0.0)
			if score >= best_score:
				continue
			var eye := n.global_position + Vector3.UP * 1.2
			if _clear(anchor, eye) != eye:
				continue
			best = n
			best_foe = group[1]
			best_score = score
	if best != focus:
		focus = best
		focus_foe = best_foe
		_pick_offset()

func _physics_process(dt: float) -> void:
	if a == null or a.player == null:
		return
	t += dt
	dart_left -= dt
	if dart_left <= 0.0:
		_pick_offset()
	scan_left -= dt
	if scan_left <= 0.0:
		scan_left = 0.2
		_scan()
	var anchor := _anchor()
	var base := anchor
	if focus:
		base = focus.global_position + Vector3.UP * (FOE_HEAD if focus_foe else FRIEND_HEAD)
	var bob := Vector3(sin(t * 2.3) * 0.06, sin(t * 3.1) * 0.09, cos(t * 2.7) * 0.06)
	var goal := _clear(anchor, base + offset + bob)
	if global_position.distance_to(anchor) > SNAP_DIST:
		focus = null
		leash = REST_LEASH
		goal = _clear(anchor, anchor + offset)
		global_position = goal
		vel = Vector3.ZERO
	vel += ((goal - global_position) * 28.0 - vel * 8.5) * dt
	var pos := global_position + vel * dt
	leash = move_toward(leash, FOCUS_LEAVE + 1.0 if focus else REST_LEASH, 8.0 * dt)
	var away := pos - anchor
	if away.length() > leash:
		pos = anchor + away.normalized() * leash
	global_position = _clear(anchor, pos)
	_update_look(dt)

func _update_look(dt: float) -> void:
	level = move_toward(level, 1.0 if focus else 0.0, 2.5 * dt)
	var want: Color = COL_IDLE
	if focus:
		want = COL_FOE if focus_foe else COL_FRIEND
	tint = tint.lerp(want, 1.0 - exp(-5.0 * dt))
	var flick := 1.0 + 0.12 * sin(t * 5.1) + 0.07 * sin(t * 13.7 + 1.1) + 0.04 * sin(t * 29.0)
	light.light_color = tint
	light.light_energy = lerpf(ENERGY_IDLE, ENERGY_FOCUS, level) * flick
	mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	mat.set_shader_parameter("gain", flick)
	for i in sparks.size():
		var ang := t * (3.4 + i * 1.3) + i * PI
		sparks[i].position = Vector3(cos(ang) * 0.19, sin(ang * 0.7) * 0.11, sin(ang) * 0.19)
