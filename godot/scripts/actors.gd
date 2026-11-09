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
# 回饋與戰鬥
var fx: Node3D
var nature: Node3D
var step_dist := 0.0
var step_side := 1.0
var trail: Array = []          # 腳印：[位置, 剩餘秒數, 起始半徑]
var was_on_floor := true
var fall_speed := 0.0
var wall_cd := 0.0
var shake := 0.0
var squash := 0.0
var squash_v := 0.0
var skeleton: Skeleton3D
var pose: SkeletonModifier3D
var sword_hand: Node3D
var sword_back: Node3D
var sword_tip: Marker3D
var sword_hilt: Marker3D
var attacking := false
var attack_t := 0.0
var attack_swing := 0
var attack_queued := false
var attack_hit := false
var attack_rest := 0.0     # 收劍倒數
var hit_stop := 0.0
var hit_stop_until := 0
var hold_t := -1.0         # 截圖用：固定在某個揮劍時間點

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
const WORLD_R := 300.0    # 可走範圍半徑；地形只到 ±360，山脊外就是虛空
const FALL_Y := -40.0     # 掉到地形下方就送回出生點
const JUMP_V := 8.0
const ATTACK_TIME := 0.46
const SHEATHE_AFTER := 2.5
const PUSH_R := 0.75        # 玩家和村民的軟碰撞半徑（兩人圓心距）
const SWORD := "res://assets/chars/sword.glb"


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
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400, z), Vector3(x, -40, z))
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
	var env_p := OS.get_environment("PLAYER")   # 截圖用：PLAYER=x,z
	if env_p != "":
		sp = Vector3(float(env_p.get_slice(",", 0)), 0, float(env_p.get_slice(",", 1)))
	player.global_position = Vector3(sp.x, _ground_y(sp.x, sp.z) + 0.1, sp.z)
	_make_weapon()
	yaw = 0.0  # 面向北（城門）

	cam_pivot = Node3D.new()
	add_child(cam_pivot)
	spring = SpringArm3D.new()
	spring.spring_length = 5.5
	# 用球體掃掠：單條射線只保證中心點，貼著地面時鏡頭只離地幾公分。半徑要小於玩家膠囊（0.3），起點才不會卡進牆裡
	var cam_shape := SphereShape3D.new()
	cam_shape.radius = 0.25
	spring.shape = cam_shape
	spring.margin = 0.12
	spring.add_excluded_object(player.get_rid())
	cam_pivot.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 60
	camera.far = 1200
	spring.add_child(camera)
	if OS.get_environment("SHOT") == "":
		camera.make_current()
		if not demo and OS.get_environment("SELFTEST") == "" and OS.get_environment("REEL") == "":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------- 武器 ----------
func _make_weapon() -> void:
	skeleton = player_visual.find_children("*", "Skeleton3D", true, false)[0]
	var hand := skeleton.find_bone("hand_r")
	var rest := skeleton.get_bone_global_rest(hand)
	var F := (skeleton.get_bone_global_rest(skeleton.find_bone("middle_01_r")).origin - rest.origin).normalized()   # 手指方向
	var thumb := (skeleton.get_bone_global_rest(skeleton.find_bone("thumb_01_r")).origin - rest.origin).normalized()
	var blade := (thumb - F * thumb.dot(F)).normalized()   # 握拳時劍身從拇指那側伸出去
	var grip := Transform3D(Basis(F, blade, F.cross(blade)).orthonormalized(), rest.origin + F * 0.09)
	var at := BoneAttachment3D.new()
	at.bone_name = "hand_r"
	skeleton.add_child(at)
	sword_hand = load(SWORD).instantiate()
	sword_hand.transform = rest.affine_inverse() * grip
	at.add_child(sword_hand)
	sword_hilt = Marker3D.new(); sword_hilt.position = Vector3(0, 0.08, 0); sword_hand.add_child(sword_hilt)
	sword_tip = Marker3D.new(); sword_tip.position = Vector3(0, 0.68, 0); sword_hand.add_child(sword_tip)
	sword_hand.visible = false
	# 收劍：斜背在背上（劍柄在右肩後）
	var back := BoneAttachment3D.new()
	back.bone_name = "spine_05"
	skeleton.add_child(back)
	sword_back = load(SWORD).instantiate()
	var spine := skeleton.get_bone_global_rest(skeleton.find_bone("spine_05"))
	var to_sk := (player_visual.global_basis.inverse() * skeleton.global_basis).orthonormalized().inverse()
	var dn := (to_sk * Vector3(0.45, -1, -0.12)).normalized()    # 劍尖朝左下（角色空間）
	var side := (to_sk * Vector3(0, 0, 1)).cross(dn).normalized()
	var at_back := Transform3D(Basis(side, dn, side.cross(dn)).orthonormalized(), spine.origin + to_sk * Vector3(-0.05, 0.02, -0.2))
	sword_back.transform = spine.affine_inverse() * at_back
	back.add_child(sword_back)
	pose = load("res://scripts/attack_pose.gd").new()
	skeleton.add_child(pose)
	pose.bind(skeleton)
	pose.to_skeleton = to_sk
	pose.blade_local = (rest.basis.inverse() * blade).normalized()
	pose.curl_axis_local = (rest.basis.inverse() * blade).normalized()
	var h := OS.get_environment("ATTACK_HOLD")    # 截圖用：ATTACK_HOLD=<段數>:<0..1>
	if h != "":
		attack_swing = int(h.get_slice(":", 0))
		hold_t = float(h.get_slice(":", 1))
		attacking = true
		_show_sword(true)


func _show_sword(in_hand: bool) -> void:
	sword_hand.visible = in_hand
	sword_back.visible = not in_hand


func _start_attack(swing: int) -> void:
	attacking = true
	attack_t = 0.0
	attack_swing = swing
	attack_hit = false
	attack_queued = false
	attack_rest = SHEATHE_AFTER
	_show_sword(true)
	# 朝鏡頭方向揮
	player.rotation.y = yaw


func _update_attack(dt: float) -> void:
	if hold_t >= 0.0:
		pose.swing = attack_swing
		pose.t = hold_t
		pose.weight = 1.0
		return
	if attacking:
		attack_t += dt / ATTACK_TIME
		pose.swing = attack_swing
		pose.t = clampf(attack_t, 0.0, 1.0)
		pose.weight = clampf(attack_t / 0.08, 0.0, 1.0) * clampf((1.0 - attack_t) / 0.18, 0.0, 1.0)
		if attack_t > 0.22 and attack_t < 0.68:
			fx.add_trail(sword_hilt.global_position, sword_tip.global_position)
		if attack_t > 0.4 and not attack_hit:
			attack_hit = true
			_resolve_hit()
		if attack_queued and attack_t > 0.62:
			_start_attack((attack_swing + 1) % 3)
		elif attack_t >= 1.0:
			attacking = false
			pose.weight = 0.0
	elif attack_rest > 0.0:
		attack_rest -= dt
		if attack_rest <= 0.0:
			_show_sword(false)


func _resolve_hit() -> void:
	var fwd := -player.global_basis.z
	var at := player.global_position + Vector3.UP * 0.75
	var landed := false
	for d in villagers + stall_vs:
		var n: Node3D = d.node
		var to: Vector3 = n.global_position - player.global_position
		to.y = 0.0
		if to.length() < 1.9 and to.normalized().dot(fwd) > 0.3:
			d.bump_v = to.normalized() * 5.5
			d.spin = 1.0
			fx.burst("spark", n.global_position + Vector3.UP * 0.8, 10, 3.5, 3.0, 0.16, 0.3, Color(1, .85, .5))
			landed = true
	# 砍到牆、房子、道具：火花
	var q := PhysicsRayQueryParameters3D.create(at, at + fwd * 1.5)
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit.normal.y < 0.6:
		fx.burst("spark", hit.position, 12, 3.0, 2.5, 0.13, 0.28, Color(1, .8, .45))
		landed = true
	# 砍草：劍尖前方的地上噴草屑
	var tip := player.global_position + fwd * 1.1
	if player.is_on_floor() and not get_parent()._on_road_or_building(Vector2(tip.x, tip.z)):
		fx.burst("blade", tip + Vector3.UP * 0.3, 9, 2.6, 3.2, 0.2, 0.7)
	if landed:
		shake = maxf(shake, 0.32)
		hit_stop = 0.055


func _add_shake(a: float) -> void:
	shake = maxf(shake, a)


# ---------- 走路、撞擊的回饋 ----------
func _footstep(pos: Vector3, heavy: bool) -> void:
	var onroad: bool = get_parent()._on_road_or_building(Vector2(pos.x, pos.z))
	if onroad:
		fx.burst("dust", pos + Vector3.UP * 0.05, 3 if heavy else 1, 0.5, 0.35, 0.28 if heavy else 0.2, 0.55)
	else:
		fx.burst("blade", pos + Vector3.UP * 0.15, 8 if heavy else 4, 1.3, 2.4, 0.24, 0.6)
		if randf() < (0.35 if heavy else 0.15):
			fx.burst("petal", pos + Vector3.UP * 0.25, 3, 1.0, 1.8, 0.13, 1.0)
		trail.append([pos, 1.8, 0.85 if not mounted else 1.5])
		if trail.size() > 5:
			trail.pop_front()


func _update_feedback(dt: float, moved: float, running: bool) -> void:
	# 腳步：依移動距離踩點，不依賴動作長度
	var stride := 1.8 if mounted else (1.25 if running else 0.62)
	if player.is_on_floor():
		step_dist += moved
		if step_dist >= stride:
			step_dist = 0.0
			step_side = -step_side
			var side := player.global_basis.x * step_side * (0.45 if mounted else 0.13)
			_footstep(player.global_position + side, running or mounted)
	# 落地
	if player.is_on_floor() and not was_on_floor and fall_speed > 3.0:
		var k := clampf(fall_speed / 10.0, 0.2, 1.0)
		var p := player.global_position
		var road: bool = get_parent()._on_road_or_building(Vector2(p.x, p.z))
		fx.burst("dust" if road else "blade", p + Vector3.UP * 0.08, int(4 + 8 * k), 1.8, 1.0 if road else 2.6, 0.3 if road else 0.16, 0.6)
		_add_shake(0.25 * k)
		squash_v -= 5.0 * k
	was_on_floor = player.is_on_floor()
	fall_speed = maxf(-player.get_real_velocity().y, 0.0)
	# 撞牆（跑步或騎乘時，正面撞上才有反應）
	wall_cd -= dt
	var want := Vector3(player.velocity.x, 0, player.velocity.z)
	if wall_cd <= 0.0 and want.length() > WALK_SPEED * 1.4:
		for i in player.get_slide_collision_count():
			var c := player.get_slide_collision(i)
			var n := c.get_normal()
			if absf(n.y) < 0.5 and want.normalized().dot(n) < -0.7:
				fx.burst("dust", c.get_position(), 6, 1.4, 0.9, 0.3, 0.5)
				_add_shake(0.3)
				squash_v -= 3.5
				wall_cd = 0.55
				break
	# 跟村民、坐騎的軟碰撞：彼此推開，村民被撞會晃一下
	var pp := player.global_position
	var r := PUSH_R + (0.5 if mounted else 0.0)
	for d in villagers + stall_vs:
		_soft_collide(d, pp, r, want.length())
	if not mounted and elk:
		var to := Vector3(pp.x - elk.global_position.x, 0, pp.z - elk.global_position.z)
		if to.length() < 1.15 and to.length() > 0.001:
			player.global_position += to.normalized() * (1.15 - to.length()) * minf(1.0, 12.0 * dt)
	# 擠壓彈簧（落地、撞牆時身體一縮再彈回）
	squash_v += (-squash * 180.0 - squash_v * 16.0) * dt
	squash += squash_v * dt
	var sy := 1.0 + clampf(squash, -0.28, 0.28)
	player_visual.scale = Vector3(1.0 / sqrt(sy), sy, 1.0 / sqrt(sy))
	# 草被推開：玩家當下的位置＋還沒彈回的腳印
	var pts := PackedVector4Array()
	pts.append(Vector4(pp.x, pp.y, pp.z, 1.25 if mounted else 0.8))
	var kept := []
	for tr in trail:
		tr[1] -= dt
		if tr[1] > 0.0:
			kept.append(tr)
			pts.append(Vector4(tr[0].x, tr[0].y, tr[0].z, tr[2] * clampf(tr[1] / 1.2, 0.0, 1.0)))
	trail = kept
	while pts.size() < 6:
		pts.append(Vector4.ZERO)
	nature.set_pushers(pts, pp + Vector3.UP * 0.6, 1.3 if mounted else 0.95)


func _soft_collide(d: Dictionary, pp: Vector3, r: float, speed: float) -> void:
	d.cd -= get_physics_process_delta_time()
	var n: Node3D = d.node
	var to := Vector3(pp.x - n.global_position.x, 0, pp.z - n.global_position.z)
	var len := to.length()
	if len >= r or len < 0.001:
		return
	var dir := to / len
	player.global_position += dir * (r - len) * 0.6
	if d.cd <= 0.0 and speed > WALK_SPEED * 0.8:
		d.cd = 0.7
		d.bump_v = -dir * (2.0 + speed * 0.45)
		d.spin = clampf(speed / RUN_SPEED, 0.3, 1.0)
		fx.burst("dust", n.global_position + Vector3.UP * 0.5, 4, 1.2, 0.8, 0.26, 0.45)
		_add_shake(0.1 + 0.14 * clampf(speed / RUN_SPEED, 0.0, 1.0))
		squash_v -= 2.0


## 村民被撞的位移彈簧與身體搖晃
func _npc_spring(d: Dictionary, dt: float) -> void:
	d.bump_v += (-d.bump * 42.0 - d.bump_v * 7.0) * dt
	d.bump += d.bump_v * dt
	d.spin = move_toward(d.spin, 0.0, dt * 1.4)
	var n: Node3D = d.node
	n.position = d.base_pos + d.bump
	n.rotation.z = sin(d.spin * 18.0) * d.spin * 0.28


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED    # 視窗放開滑鼠後，點一下回到遊戲
		elif not mounted:
			if not attacking:
				_start_attack(0)
			elif attack_t > 0.3:
				attack_queued = true
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= e.relative.x * 0.004
		pitch = clamp(pitch - e.relative.y * 0.003, -1.2, 0.4)
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	if e.is_action_pressed("mount"):
		_toggle_mount()


# 鏡頭到正下方地面的距離（晃動幅度不能超過它）
func _camera_clearance() -> float:
	var from := camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0)
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return 3.0 if hit.is_empty() else from.y - hit.position.y

# 走到世界邊界時去掉往外的速度，沿邊界滑動，走路動畫也會跟實際速度一致
func _limit_to_world() -> void:
	var pos := Vector2(player.global_position.x, player.global_position.z)
	if pos.length() < WORLD_R:
		return
	var n := pos.normalized()
	var v := Vector2(player.velocity.x, player.velocity.z)
	var out := v.dot(n)
	if out > 0.0:
		v -= n * out
		player.velocity.x = v.x
		player.velocity.z = v.y

func _clamp_to_world() -> void:
	var pos := Vector2(player.global_position.x, player.global_position.z)
	if pos.length() > WORLD_R:
		pos = pos.normalized() * WORLD_R
		player.global_position.x = pos.x
		player.global_position.z = pos.y
	if player.global_position.y < FALL_Y:
		var sp := _v(layout.spawn)
		player.global_position = Vector3(sp.x, _ground_y(sp.x, sp.z) + 0.1, sp.z)
		vel_y = 0.0

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
	if attacking:
		# 揮劍時放慢，揮下去那一刻往前踏一步
		speed *= 0.3
	player.velocity.x = dir.x * speed
	player.velocity.z = dir.z * speed
	if attacking and attack_t > 0.25 and attack_t < 0.5:
		var lunge := -player.global_basis.z * 3.2
		player.velocity.x += lunge.x
		player.velocity.z += lunge.z
	var before := player.global_position
	if player.is_on_floor():
		vel_y = -1.0
		if Input.is_action_just_pressed("jump") and not mounted:
			vel_y = JUMP_V
			player_anim.play("jump", 0.1)
	else:
		vel_y -= GRAVITY * dt
	player.velocity.y = vel_y
	_limit_to_world()
	player.move_and_slide()
	_clamp_to_world()
	var moved := Vector2(player.global_position.x - before.x, player.global_position.z - before.z).length()
	if dir.length() > 0.05 and not attacking:
		var target := atan2(-dir.x, -dir.z)
		player.rotation.y = lerp_angle(player.rotation.y, target, 1.0 - exp(-12.0 * dt))
	# 依實際移動判斷（撞牆時不會原地跑）
	var real_speed := Vector2(player.get_real_velocity().x, player.get_real_velocity().z).length()
	_update_player_anim(dir.length() > 0.05 and real_speed > 0.5, running)
	_update_attack(dt)
	_update_feedback(dt, moved, running)
	cam_pivot.global_position = player.global_position + Vector3(0, 1.4 if not mounted else 3.0, 0)
	cam_pivot.rotation = Vector3(pitch, yaw, 0)
	spring.spring_length = 5.5 if not mounted else 8.0
	_update_villagers(dt)
	_update_elk(dt)
	# 鏡頭晃動（平方衰減，小晃動幾乎察覺不到）
	shake = move_toward(shake, 0.0, dt * 1.6)
	var a := shake * shake * 0.55
	a *= smoothstep(0.35, 1.0, spring.get_hit_length() / spring.spring_length)   # 鏡頭被擠近地面或牆時不晃，不然會晃進去
	if a > 0.001:
		a = min(a, _camera_clearance() - 0.3)
		a = maxf(a, 0.0)
	var tt := Time.get_ticks_msec() * 0.001
	camera.h_offset = sin(tt * 47.0) * a
	camera.v_offset = sin(tt * 61.0 + 1.3) * a
	# 打擊停頓用真實時間算（dt 會被 time_scale 縮小）
	if hit_stop > 0.0:
		hit_stop_until = Time.get_ticks_msec() + int(hit_stop * 1000.0)
		hit_stop = 0.0
		Engine.time_scale = 0.08
	elif Engine.time_scale < 1.0 and Time.get_ticks_msec() >= hit_stop_until:
		Engine.time_scale = 1.0


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
			"speed": rng.randf_range(0.9, 1.3), "len": a.distance_to(b), "look": 0.0,
			"base_pos": Vector3.ZERO, "bump": Vector3.ZERO, "bump_v": Vector3.ZERO, "spin": 0.0, "cd": 0.0})
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
		stall_vs.append({"node": v, "base": v.rotation.y, "base_pos": v.global_position, "bump": Vector3.ZERO, "bump_v": Vector3.ZERO, "spin": 0.0, "cd": 0.0})


func _update_villagers(dt: float) -> void:
	var pp := player.global_position
	for d in stall_vs:
		var n: Node3D = d.node
		var target: float = d.base
		if n.global_position.distance_to(pp) < 6.0:
			var to := pp - n.global_position
			target = atan2(to.x, to.z)
		n.rotation.y = lerp_angle(n.rotation.y, target, 1.0 - exp(-4.0 * dt))
		_npc_spring(d, dt)
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
			_npc_spring(d, dt)
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
		d.base_pos = p
		n.rotation.y = lerp_angle(n.rotation.y, atan2(fwd.x, fwd.z), 1.0 - exp(-6.0 * dt))
		_npc_spring(d, dt)


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
		was_on_floor = false
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
