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
	# 11. 砍草、揮劍的風、敵人受擊
	await tp(24, 90, 0.876)
	var cut_before: int = a.nature.cover_cut.size()
	a._start_attack(0)
	while a.attacking:
		await get_tree().physics_frame
	check("砍草有削短", a.nature.cover_cut.size() > cut_before, a.nature.cover_cut.size())
	var cut_id: int = a.nature.cover_cut.keys()[0]
	var cut_mm: MultiMesh = a.nature.cover_mms[cut_id >> 24]
	var cut_i: int = cut_id & 0xFFFFFF
	var full_h: float = a.nature.cover_cut[cut_id].xf.basis.y.length()
	check("被砍的草變矮", cut_mm.get_instance_transform(cut_i).basis.y.length() < 0.2, full_h)
	a.nature.cover_cut[cut_id].t = 3.9
	await frames(20)
	check("草會長回來", absf(cut_mm.get_instance_transform(cut_i).basis.y.length() - full_h) < 0.001 and not a.nature.cover_cut.has(cut_id))
	var fog_n: Node3D = a.get_parent().fog
	check("揮劍帶起風", fog_n.gusts.size() > 0, fog_n.gusts.size())
	await frames(int(4.2 * Engine.physics_ticks_per_second))
	check("霧會補回來", fog_n.gusts.is_empty(), fog_n.gusts.size())
	var en: Dictionary = a.enemies[0]
	var en_n: Node3D = en.node
	await tp(en_n.global_position.x, en_n.global_position.z + 1.4, 0.0)
	a._start_attack(0)
	while a.stop_left <= 0.0 and a.attacking:
		await get_tree().physics_frame
	check("打得到敵人", en.stun > 0.0)
	await frames(10)
	check("敵人播受擊動作", en.anim.current_animation == "Hit_A", en.anim.current_animation)
	await frames(90)
	check("敵人回到待機", en.anim.current_animation == "Idle_Combat", en.anim.current_animation)
	# 12. 跳起下劈：空中才能用、落地範圍命中、霧有衝擊波
	await frames(60)
	check("地上不能下劈", not a._can_plunge())
	await tp(en_n.global_position.x + 1.2, en_n.global_position.z + 0.8, 0.9)
	await hold(["jump"], 2)
	await frames(10)
	check("空中可以下劈", a._can_plunge())
	var cut_n: int = a.nature.cover_cut.size()
	var hit_before: float = en.stun
	a._start_plunge()
	var top_y: float = p.global_position.y
	while a.plunge == 1:
		await get_tree().physics_frame
		top_y = maxf(top_y, p.global_position.y)
	check("下劈先往上蹬", top_y > terrain_y(p.global_position.x, p.global_position.z) + 1.0, top_y)
	var dive_guard := 0
	while a.plunge == 2 and dive_guard < 120:
		dive_guard += 1
		await get_tree().physics_frame
	check("俯衝很快落地", dive_guard < 40, dive_guard)
	check("落地卡肉", a.stop_left > 0.0)
	check("落地打到周圍的敵人", en.stun > 0.0 and en.stun != hit_before, en.stun)
	check("落地砍掉一圈草", a.nature.cover_cut.size() >= cut_n)
	check("落地產生衝擊波", fog_n.blasts.size() == 1, fog_n.blasts.size())
	await frames(int(7.0 * Engine.physics_ticks_per_second))
	check("衝擊波結束", fog_n.blasts.is_empty(), fog_n.blasts.size())
	check("下劈收招", not a.attacking and a.plunge == 0)
	# 13. 小光靈：跟隨、不穿牆、注意敵人、瞬移跟上、光會閃動
	var wsp: Node3D = a.wisp
	await tp(0, 84, 0.0)
	await frames(20)
	var far := 0.0
	var energies := {}
	for i in 90:
		Input.action_press("move_forward")
		Input.action_press("run")
		await get_tree().physics_frame
		if wsp.focus == null and wsp.leash <= wsp.REST_LEASH:   # 路上遇到村民會飛過去，這不算跟丟
			far = maxf(far, wsp.global_position.distance_to(wsp._anchor()))
		energies[snappedf(wsp.light.light_energy, 0.01)] = true
	Input.action_release("move_forward")
	Input.action_release("run")
	check("光靈跟著跑", far <= wsp.REST_LEASH + 0.05, far)
	check("光靈的光會閃動", energies.size() > 20, energies.size())
	await tp(1.0, 58, -PI / 2.0)
	var through := 0
	for i in 150:
		Input.action_press("move_forward")
		await get_tree().physics_frame
		var ws: Vector3 = wsp.global_position
		if wsp._clear(wsp._anchor(), ws) != ws:
			through += 1
	Input.action_release("move_forward")
	check("光靈不穿牆", through == 0, through)
	await frames(30)
	var ep: Vector3 = en_n.global_position
	await tp(ep.x + 4.0, ep.z + 3.0, atan2(4.0, 3.0))
	var idle_blue: float = wsp.tint.b
	await frames(90)
	check("光靈注意到敵人", wsp.focus == en_n, wsp.focus)
	check("靠近敵人時換色", wsp.tint.b > idle_blue + 0.2, wsp.tint)
	check("光靈飛到敵人旁邊", wsp.global_position.distance_to(ep + Vector3.UP * wsp.FOE_HEAD) < 1.6, wsp.global_position)
	await tp(0, 110, 0.0)
	await frames(30)
	check("瞬移後光靈跟上", wsp.global_position.distance_to(wsp._anchor()) < wsp.REST_LEASH, wsp.global_position)
	check("離開後不再注意", wsp.focus == null, wsp.focus)
	# 14. 天氣：雨天開關、地面變濕、切回晴天全部復原
	var main_n: Node = a.get_parent()
	fog_n.apply(fog_n.RAIN)
	await frames(30)
	var sky_m: ShaderMaterial = main_n.env.sky.sky_material
	check("雨天下雨", fog_n.rain.drops.emitting and fog_n.rain.drops.visible)
	check("雨天有雨聲", fog_n.rain.audio.playing)
	check("雨天烏雲", sky_m.get_shader_parameter("storm") == 1.0)
	check("雨天地面變濕", main_n.wet == 1.0 and main_n.wet_shaders.size() > 1, main_n.wet_shaders.size())
	fog_n.apply(fog_n.RAIN + 1)
	await frames(120)
	check("切回晴天雨停", not fog_n.rain.drops.emitting and fog_n.idx == 0, fog_n.idx)
	check("雨聲停止", not fog_n.rain.audio.playing)
	check("地面變乾", main_n.wet == 0.0 and sky_m.get_shader_parameter("storm") == 0.0)
	# 15. 出招方向：跟方向鍵、沒按維持面向、前方有骷髏輕度轉向
	await tp(0, 68, 0.0)
	Input.action_press("move_right")
	var face_r: float = a._attack_facing()
	Input.action_release("move_right")
	check("按右鍵往右砍", absf(angle_difference(face_r, -PI / 2.0)) < 0.01, face_r)
	a.player.rotation.y = 1.0
	check("沒按方向維持面向", absf(angle_difference(a._attack_facing(), 1.0)) < 0.01)
	a._start_attack(0, a._attack_facing())
	check("出招轉向指定方向", absf(angle_difference(a.player.rotation.y, 1.0)) < 0.01, a.player.rotation.y)
	while a.attacking:
		await get_tree().physics_frame
	ep = en_n.global_position
	await tp(ep.x + 0.8, ep.z + 2.2, 0.0)
	var to_en: Vector3 = en_n.global_position - a.player.global_position
	var aim: float = a._attack_facing()
	check("前方骷髏自動修正", absf(angle_difference(aim, atan2(-to_en.x, -to_en.z))) < 0.01, aim)
	a.player.rotation.y = PI
	check("背後骷髏不修正", absf(angle_difference(a._attack_facing(), PI)) < 0.01)
	# 16. 鏡頭：滾輪縮放、拉到底進第一人稱、V 切換
	await tp(0, 68, 0.0)
	var wheel := func(up: bool) -> void:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		ev.pressed = true
		a._unhandled_input(ev)
	for i in 5:
		wheel.call(true)
	check("滾輪拉近到最近", absf(a.cam_dist - a.CAM_MIN) < 0.01 and not a.first_person, a.cam_dist)
	wheel.call(true)
	await frames(60)
	check("再滾進第一人稱", a.first_person and a.cam_cur < 0.05 and a.body_hidden, a.cam_cur)
	var eye_y: float = a.camera.global_position.y - a.player.global_position.y
	check("第一人稱在眼睛高度", eye_y > 0.9 and eye_y < 1.6, eye_y)
	await snap("test_first_person")
	wheel.call(false)
	await frames(60)
	check("滾回第三人稱", not a.first_person and absf(a.cam_cur - a.CAM_MIN) < 0.05 and not a.body_hidden, a.cam_cur)
	for i in 12:
		wheel.call(false)
	check("滾輪拉遠有上限", absf(a.cam_dist - a.CAM_MAX) < 0.01, a.cam_dist)
	var vk := InputEventKey.new()
	vk.keycode = KEY_V
	vk.pressed = true
	a._unhandled_input(vk)
	check("V 切第一人稱", a.first_person)
	a._unhandled_input(vk)
	check("V 切回第三人稱", not a.first_person)
	a.cam_dist = 5.5
	await frames(60)
	print("SELFTEST done fails=", fails)
	get_tree().quit()
