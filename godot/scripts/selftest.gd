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
	# 9. 砍村民：打擊停頓會結束
	from = n.global_position + n.global_basis.z * 1.4
	ang = atan2(from.x - n.global_position.x, from.z - n.global_position.z)
	await tp(from.x, from.z, ang)
	d.spin = 0.0
	a._start_attack(0)
	await frames(40)
	check("砍到村民有反應", d.spin > 0.0 or d.bump.length() > 0.001, d.spin)
	await get_tree().create_timer(0.5, true, false, true).timeout
	check("打擊停頓有恢復", is_equal_approx(Engine.time_scale, 1.0), Engine.time_scale)
	# 10. 騎乘時不能揮劍的情況與上下坐騎
	await tp(0, 68)
	a._toggle_mount()
	await hold(["move_forward"], 30)
	check("騎乘可移動", a.mounted and p.global_position.z < 67.5, p.global_position)
	a._toggle_mount()
	await frames(10)
	check("下坐騎", not a.mounted)
	print("SELFTEST done fails=", fails)
	get_tree().quit()
