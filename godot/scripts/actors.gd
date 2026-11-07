extends Node3D
## 角色：玩家（燈籠守夜人）、村民（沿街走、玩家靠近會轉頭看）、坐騎（R 召喚／上下坐騎）。
## 截圖模式下可用環境變數 DEMO=<秒> 讓時間快轉，角色走到指定位置。

const HERO := "res://assets/chars/hero.glb"
const VILLAGERS := ["res://assets/chars/villager_badger.glb", "res://assets/chars/villager_heron.glb"]
const ELK := "res://assets/chars/mount_elk.glb"

var layout: Dictionary
var player: CharacterBody3D
var player_visual: Node3D
var player_anim: AnimationPlayer
var cam_pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var elk: Node3D
var elk_anim: AnimationPlayer
var mounted := false
var villagers: Array = []
var stall_vs: Array = []
var yaw := 0.0
var pitch := -0.25
var vel_y := 0.0
var demo := OS.get_environment("DEMO") != ""
var demo_t := 0.0
var demo_mounted_once := false
var demo_dismounted := false

# 示範時間軸：[開始秒, 前進量, 側向量, 跑步, 鏡頭 yaw]
const DEMO_STEPS := [
	[0.0, 0.0, 0.0, false, 0.0],     # 站著（idle）
	[1.5, 1.0, 0.0, false, 0.0],     # 走向城門
	[4.5, 1.0, 0.0, true, 0.0],      # 跑
	[7.0, 0.0, 0.0, false, 0.0],     # 停、召喚坐騎（7.3 秒）
	[8.0, 1.0, 0.0, false, 0.0],     # 騎進城
	[11.0, 0.7, 0.7, false, -0.5],   # 廣場前往右繞，避開噴水池
	[12.6, 0.0, 0.0, false, -0.5],   # 停、下坐騎（12.9 秒）
	[13.6, 1.0, -0.2, false, -0.5],  # 走向攤販
	[15.6, 0.0, 0.0, false, 2.4],    # 停下，鏡頭繞到前面看大家轉頭
]
const DEMO_END := 21.0

const WALK_SPEED := 2.4
const RUN_SPEED := 6.0
const MOUNT_SPEED := 9.0
const GRAVITY := 22.0
const JUMP_V := 8.0


static func find_anim(root: Node) -> AnimationPlayer:
	var a := root.find_children("*", "AnimationPlayer", true, false)
	return a[0] if a.size() > 0 else null


static func set_loops(ap: AnimationPlayer, names: Array) -> void:
	for n in names:
		if ap.has_animation(n):
			ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR


func setup(l: Dictionary) -> void:
	layout = l
	_make_player()
	_make_villagers()
	_make_elk()


func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _ground_y(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 80, z), Vector3(x, -40, z))
	if player:
		q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if not hit.is_empty() else 0.0


# ---------- 玩家 ----------
func _make_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.3
	col.shape = cap
	col.position.y = 0.65
	player.add_child(col)
	player_visual = load(HERO).instantiate()
	player_visual.rotation.y = PI  # 模型面向 +Z，Godot 前方是 -Z
	player.add_child(player_visual)
	player_anim = find_anim(player_visual)
	set_loops(player_anim, ["idle", "walk", "run"])
	player_anim.play("idle")
	# 燈籠光
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("ffc56b")
	lamp.light_energy = 0.8
	lamp.omni_range = 4.0
	lamp.position = Vector3(0.25, 0.6, 0.1)
	player.add_child(lamp)
	add_child(player)
	var sp := _v(layout.spawn)
	player.global_position = Vector3(sp.x, _ground_y(sp.x, sp.z) + 0.1, sp.z)
	yaw = 0.0  # 面向北（城門）

	cam_pivot = Node3D.new()
	add_child(cam_pivot)
	spring = SpringArm3D.new()
	spring.spring_length = 5.5
	spring.margin = 0.3
	spring.add_excluded_object(player.get_rid())
	cam_pivot.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 60
	camera.far = 1200
	spring.add_child(camera)
	if OS.get_environment("SHOT") == "":
		camera.make_current()
		if not demo:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= e.relative.x * 0.004
		pitch = clamp(pitch - e.relative.y * 0.003, -1.2, 0.4)
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	if e.is_action_pressed("mount"):
		_toggle_mount()


func _physics_process(dt: float) -> void:
	if player == null:
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var running := Input.is_action_pressed("run")
	var demo_jump := false
	if demo:
		demo_t += dt
		var step: Array = DEMO_STEPS[0]
		for st in DEMO_STEPS:
			if demo_t >= st[0]:
				step = st
		input = Vector2(step[2], -step[1])
		running = step[3]
		yaw = lerp_angle(yaw, step[4], 1.0 - exp(-1.5 * dt))
		pitch = -0.22
		if demo_t > 7.3 and not demo_mounted_once:
			demo_mounted_once = true
			_toggle_mount()
		if demo_t > 12.9 and mounted and not demo_dismounted:
			demo_dismounted = true
			_toggle_mount()
		if demo_t > DEMO_END:
			get_tree().quit()
	var dir := Vector3(input.x, 0, input.y).rotated(Vector3.UP, yaw)
	var speed := MOUNT_SPEED if mounted else (RUN_SPEED if running else WALK_SPEED)
	player.velocity.x = dir.x * speed
	player.velocity.z = dir.z * speed
	if player.is_on_floor():
		vel_y = -1.0
		if Input.is_action_just_pressed("jump") and not mounted:
			vel_y = JUMP_V
			player_anim.play("jump", 0.1)
	else:
		vel_y -= GRAVITY * dt
	player.velocity.y = vel_y
	player.move_and_slide()
	if dir.length() > 0.05:
		var target := atan2(-dir.x, -dir.z)
		player.rotation.y = lerp_angle(player.rotation.y, target, 1.0 - exp(-12.0 * dt))
	_update_player_anim(dir.length() > 0.05, running)
	cam_pivot.global_position = player.global_position + Vector3(0, 1.4 if not mounted else 3.0, 0)
	cam_pivot.rotation = Vector3(pitch, yaw, 0)
	spring.spring_length = 5.5 if not mounted else 8.0
	_update_villagers(dt)
	_update_elk(dt)


func _update_player_anim(moving: bool, running: bool) -> void:
	if mounted:
		if player_anim.current_animation != "idle":
			player_anim.play("idle", 0.2)
		return
	if player_anim.current_animation == "jump" and player_anim.is_playing() and not player.is_on_floor():
		return
	var want := "idle"
	if moving:
		want = "run" if running else "walk"
	if player_anim.current_animation != want:
		player_anim.play(want, 0.2)
	# 步頻對齊移動速度（Tripo walk 原地踏步約 1.2 m/s、run 約 3.5 m/s）
	player_anim.speed_scale = 1.0
	if want == "walk":
		player_anim.speed_scale = WALK_SPEED / 1.4
	elif want == "run":
		player_anim.speed_scale = RUN_SPEED / 4.5


# ---------- 村民 ----------
func _make_villagers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var roads: Array = layout.roads
	for i in 14:
		var path: String = VILLAGERS[i % VILLAGERS.size()]
		var v: Node3D = load(path).instantiate()
		add_child(v)
		var ap := find_anim(v)
		set_loops(ap, ["idle", "walk"])
		ap.play("walk")
		ap.seek(rng.randf() * 2.0)
		var r: Dictionary = roads[rng.randi() % roads.size()]
		var a := _v(r.a)
		var b := _v(r.b)
		# 走在路的一側，避免全部擠在中線
		var side := (b - a).normalized().cross(Vector3.UP) * rng.randf_range(-r.w * 0.3, r.w * 0.3)
		var t := rng.randf()
		villagers.append({"node": v, "anim": ap, "a": a + side, "b": b + side, "t": t, "dir": 1 if rng.randf() < 0.5 else -1,
			"speed": rng.randf_range(0.9, 1.3), "len": a.distance_to(b), "look": 0.0})
	# 市集固定攤販（站著）
	var stalls: Array = layout.stalls
	for i in stalls.size():
		var v: Node3D = load(VILLAGERS[i % 2]).instantiate()
		add_child(v)
		var ap := find_anim(v)
		set_loops(ap, ["idle"])
		ap.play("idle")
		ap.seek(i * 0.7)
		var s := _v(stalls[i])
		var plaza := _v(layout.plaza)
		var out := (s - plaza).normalized()
		v.global_position = s + out * 1.2
		var to_plaza := plaza - v.global_position
		v.rotation.y = atan2(to_plaza.x, to_plaza.z)  # 面向廣場（模型正面是 +Z）
		stall_vs.append({"node": v, "base": v.rotation.y})


func _update_villagers(dt: float) -> void:
	var pp := player.global_position
	for d in stall_vs:
		var n: Node3D = d.node
		var target: float = d.base
		if n.global_position.distance_to(pp) < 6.0:
			var to := pp - n.global_position
			target = atan2(to.x, to.z)
		n.rotation.y = lerp_angle(n.rotation.y, target, 1.0 - exp(-4.0 * dt))
	for d in villagers:
		var n: Node3D = d.node
		var near := n.global_position.distance_to(pp) < 4.0
		if near:
			# 停下來轉頭看玩家
			var to := pp - n.global_position
			var target := atan2(to.x, to.z)
			n.rotation.y = lerp_angle(n.rotation.y, target, 1.0 - exp(-5.0 * dt))
			if d.anim.current_animation != "idle":
				d.anim.play("idle", 0.3)
			continue
		if d.anim.current_animation != "walk":
			d.anim.play("walk", 0.3)
		d.anim.speed_scale = d.speed / 1.2
		d.t += d.dir * d.speed * dt / max(d.len, 0.1)
		if d.t > 1.0 or d.t < 0.0:
			d.dir *= -1
			d.t = clamp(d.t, 0.0, 1.0)
		var p: Vector3 = d.a.lerp(d.b, d.t)
		p.y = 0.0
		var fwd: Vector3 = (d.b - d.a) * d.dir
		n.global_position = p
		n.rotation.y = lerp_angle(n.rotation.y, atan2(fwd.x, fwd.z), 1.0 - exp(-6.0 * dt))


# ---------- 坐騎 ----------
func _make_elk() -> void:
	elk = load(ELK).instantiate()
	add_child(elk)
	elk_anim = find_anim(elk)
	set_loops(elk_anim, ["walk"])
	elk_anim.play("walk")
	elk_anim.speed_scale = 0.0
	var sp := _v(layout.spawn)
	elk.global_position = Vector3(sp.x + 4, _ground_y(sp.x + 4, sp.z + 2), sp.z + 2)
	elk.rotation.y = PI * 0.75


func _toggle_mount() -> void:
	if mounted:
		mounted = false
		player.global_position = elk.global_position + elk.global_basis.x * 1.5
		player_visual.position = Vector3.ZERO
		return
	# 召喚：坐騎跳到玩家身旁，然後騎上去
	mounted = true
	elk.global_position = player.global_position
	elk.rotation.y = player.rotation.y + PI


func _update_elk(dt: float) -> void:
	if mounted:
		elk.global_position = player.global_position
		elk.rotation.y = player.rotation.y + PI
		player_visual.position = Vector3(0, 1.45, 0.15)  # 鞍座高度
		var moving := Vector2(player.velocity.x, player.velocity.z).length() > 0.3
		elk_anim.speed_scale = 1.6 if moving else 0.0
	else:
		elk_anim.speed_scale = 0.0
