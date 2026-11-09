extends Node
## 實際跑物理的自我測試（SELFTEST=1）：真的按方向鍵走、撞、揮劍，印 PASS/FAIL，並存幾張動態截圖到 shots/。
## 用法：SELFTEST=1 godot --path godot --windowed --resolution 1600x900

var a: Node3D
var nature: Node3D
var fails := 0

func check(name: String, ok: bool, info = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, info])
	if not ok:
		fails += 1

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func tp(x: float, z: float, yaw_v: float = 0.0) -> void:
	a.player.global_position = Vector3(x, a._ground_y(x, z) + 0.1, z)
	a.yaw = yaw_v
	a.player.rotation.y = yaw_v
	await frames(3)

func hold(act: Array, n: int) -> void:
	for x in act:
		Input.action_press(x)
	await frames(n)
	for x in act:
		Input.action_release(x)

# 鏡頭正下方的地形高度（略過樹與建築的碰撞）
func terrain_y(x: float, z: float) -> float:
	var space: PhysicsDirectSpaceState3D = a.get_world_3d().direct_space_state
	var ex := [a.player.get_rid()]
	for i in 12:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 500, z), Vector3(x, -60, z))
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return -INF
		if String(hit.collider.get_parent().name).begins_with("Terrain"):
			return hit.position.y
		ex.append(hit.rid)
	return -INF

func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../shots/%s.png" % name))

func run(actors: Node3D, nat: Node3D) -> void:
	a = actors
	nature = nat
	await frames(30)
	var p: CharacterBody3D = a.player
	# 1. 穿過城門
	await tp(0, 66)
	await hold(["move_forward", "run"], 200)
	check("穿過城門", p.global_position.z < 52.0, p.global_position)
	# 2. 門洞側牆擋得住（裡面往右走）
	await tp(1.0, 58)
	await hold(["move_right", "run"], 90)
	check("門洞側牆擋住", p.global_position.x < 2.2 and p.global_position.x > 1.0, p.global_position)
	# 3. 城牆擋得住（城外往北撞牆）
	await tp(-16, 66)
	await hold(["move_forward", "run"], 150)
	var r := Vector2(p.global_position.x, p.global_position.z).length()
	check("城牆擋住", r > 54.0, "r=%.2f" % r)
	# 4. 撞牆時不原地跑、有晃動
	a.shake = 0.0
	Input.action_press("move_forward"); Input.action_press("run")
	await frames(20)
	var anim_wall: String = a.player_anim.current_animation
	Input.action_release("move_forward"); Input.action_release("run")
	check("撞牆不原地跑", anim_wall == "idle", anim_wall)
	# 5. 走在草上：有草屑、推草資料有更新
	await tp(22, 84, 1.2)
	await hold(["move_forward", "run"], 40)
	var blades: int = a.fx.pools.blade.list.size()
	check("踏草有草屑", blades > 0, blades)
	check("腳印會更新", a.trail.size() > 0, a.trail.size())
	await snap("test_grass_run")
	# 6. 路上：揚塵
	await tp(0, 68)
	await frames(30)
	await hold(["move_forward", "run"], 40)
	check("路上有揚塵", a.fx.pools.dust.list.size() > 0)
	await snap("test_road_run")
	# 7. 撞村民：有反彈且不會穿過去
	var d: Dictionary = a.villagers[0]
	var n: Node3D = d.node
	var from: Vector3 = n.global_position + n.global_basis.z * 2.5
	var ang := atan2(from.x - n.global_position.x, from.z - n.global_position.z)
	await tp(from.x, from.z, ang)
	await hold(["move_forward", "run"], 40)
	var dist := Vector2(p.global_position.x - n.global_position.x, p.global_position.z - n.global_position.z).length()
	check("撞村民被擋開", dist > 0.5, "dist=%.2f" % dist)
	check("村民有反應", d.bump.length() > 0.001 or d.bump_v.length() > 0.001 or d.spin > 0.0, d.spin)
	# 8. 三段連擊
	await tp(0, 68)
	var seen := {}
	a._start_attack(0)
	for i in 110:
		await get_tree().physics_frame
		seen[a.attack_swing] = true
		if a.attacking and a.attack_t > 0.3:
			a.attack_queued = a.attack_swing < 2
		if i == 16:
			await snap("test_swing")
	check("三段連擊", seen.size() == 3, seen.keys())
	check("揮完結束", not a.attacking)
	check("劍在手上", a.sword_hand.visible and not a.sword_back.visible)
	await frames(180)
	check("收回背上", a.sword_back.visible and not a.sword_hand.visible)
	# 9. 打擊感：卡肉只停當事人、第三擊最重、音效和鏡頭都有反應
	var stops := []
	for swing in [0, 2]:
		from = n.global_position + n.global_basis.z * 1.4
		ang = atan2(from.x - n.global_position.x, from.z - n.global_position.z)
		await tp(from.x, from.z, ang)
		a._start_attack(swing)
		var before_soft: int = a.sfx.played.hit_soft + a.sfx.played.hit_heavy
		while a.stop_left <= 0.0 and a.attacking:
			await get_tree().physics_frame
		check("砍到村民觸發卡肉", a.stop_left > 0.0, swing)
		check("命中音效", a.sfx.played.hit_soft + a.sfx.played.hit_heavy == before_soft + 1)
		check("命中後鏡頭內縮", a.camera.fov < 59.5, a.camera.fov)
		var t0: float = a.attack_t
		check("受擊有骨架動作", d.react != null and d.react.amount > 0.5 and not d.react.ids.values().has(-1), d.react.ids if d.react else null)
		var n_frames := 0
		while a.stop_left > 0.0:
			await get_tree().physics_frame
			n_frames += 1
		stops.append(n_frames)
		check("卡肉中揮劍定住", is_equal_approx(a.attack_t, t0), a.attack_t)
		check("世界沒有被減速", is_equal_approx(Engine.time_scale, 1.0), Engine.time_scale)
		await frames(3)
		check("卡肉後被擊退", d.bump.length() > 0.01 or d.bump_v.length() > 0.1, d.bump)
		check("卡肉後揮劍繼續", a.attack_t > t0)
		while a.attacking:
			await get_tree().physics_frame
		await frames(45)
	check("第三擊卡肉較長", stops[1] > stops[0] and stops[0] >= 2 and stops[1] <= 10, stops)
	check("閃白結束", d.flash <= 0.0)
	check("受擊動作收回", d.react.amount < 0.05, d.react.amount)
	check("鏡頭視野回復", absf(a.camera.fov - 60.0) < 0.1, a.camera.fov)
	# 揮空：有風聲，沒有卡肉
	await tp(24, 90, 0.0)
	var w: int = a.sfx.played.whoosh
	var h0: int = a.sfx.played.hit_hard + a.sfx.played.hit_soft
	a._start_attack(0)
	var any_stop := false
	while a.attacking:
		await get_tree().physics_frame
		any_stop = any_stop or a.stop_left > 0.0
	check("揮空有風聲", a.sfx.played.whoosh == w + 1)
	check("揮空不卡肉", not any_stop, "%d %s" % [a.sfx.played.hit_hard + a.sfx.played.hit_soft - h0, a.player.global_position])
	# 10. 騎乘時不能揮劍的情況與上下坐騎
	await tp(0, 68)
	a._toggle_mount()
	await hold(["move_forward"], 30)
	check("騎乘可移動", a.mounted and p.global_position.z < 67.5, p.global_position)
	a._toggle_mount()
	await frames(10)
	check("下坐騎", not a.mounted)
	# 11. 世界邊界：跑不出去，會沿著邊界滑
	# 外圈山坡太陡，走路到不了邊界，所以直接放到界外，再從界線上往外跑
	await tp(0, 310, PI)
	var edge := Vector2(p.global_position.x, p.global_position.z).length()
	check("界外會被拉回", edge <= a.WORLD_R + 0.05, "r=%.2f" % edge)
	await tp(0, a.WORLD_R, PI)
	var max_r := 0.0
	Input.action_press("move_forward"); Input.action_press("run")
	for i in 40:
		await get_tree().physics_frame
		max_r = maxf(max_r, Vector2(p.global_position.x, p.global_position.z).length())
	Input.action_release("move_forward"); Input.action_release("run")
	check("世界邊界擋住", max_r <= a.WORLD_R + 0.05, "max r=%.2f" % max_r)
	# 12. 掉到地形下會回出生點
	p.global_position.y = a.FALL_Y - 5.0
	await frames(4)
	check("掉出地形會回來", p.global_position.y > a.FALL_Y, p.global_position)
	# 13. 平地、緩坡、山腰各轉一圈，鏡頭仰到底加晃動，都要在地面上
	var lowest := INF
	var lowest_body := INF
	var low_at := Vector3.ZERO
	var spots := [Vector2(0, 30), Vector2(22, 84), Vector2(120, 90), Vector2(190, 150), Vector2(-160, 150), Vector2(0, 290)]
	for spot: Vector2 in spots:
		await tp(spot.x, spot.y)
		a.pitch = 0.4
		for i in 16:
			a.yaw = TAU * i / 16.0
			a.shake = 1.0
			await frames(3)
			var c: Camera3D = a.camera
			var eye := c.global_position + c.global_basis.y * c.v_offset + c.global_basis.x * c.h_offset
			var g := eye.y - terrain_y(eye.x, eye.z)
			if g < lowest:
				lowest = g
				low_at = eye
			lowest_body = minf(lowest_body, c.global_position.y - terrain_y(c.global_position.x, c.global_position.z))
	check("鏡頭不穿地", lowest >= 0.2, "含晃動最低 %.2f m，不含晃動 %.2f m @ %s" % [lowest, lowest_body, low_at])
	a.pitch = -0.25
	print("SELFTEST done fails=", fails)
	get_tree().quit()
