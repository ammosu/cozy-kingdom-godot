extends "res://scripts/selftest.gd"
## 剪輯式示範影片（REEL=1 tools/record.sh <名稱>）：逐段瞬移到定點，實際操作角色，換場用黑幕蓋住光照收斂。

var fade: ColorRect

func sec(s: float) -> int:
	return int(s * Engine.physics_ticks_per_second)

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(fade)

func set_fade(from_a: float, to_a: float, s: float) -> void:
	var n := sec(s)
	for i in n:
		fade.color.a = lerpf(from_a, to_a, float(i + 1) / n)
		await get_tree().physics_frame

## 黑幕中換到新位置，等光照穩定後淡入
func cut(x: float, z: float, yaw_v: float, pitch_v: float) -> void:
	await set_fade(0.0, 1.0, 0.25)
	a.pitch = pitch_v
	await tp(x, z, yaw_v)
	await frames(sec(0.8))
	await set_fade(1.0, 0.0, 0.3)

## 鏡頭繞著玩家慢慢轉
func orbit(to_yaw: float, s: float) -> void:
	var n := sec(s)
	var y0: float = a.yaw
	for i in n:
		a.yaw = lerpf(y0, to_yaw, float(i + 1) / n)
		await get_tree().physics_frame

## 鏡頭俯仰慢慢轉到 to
func tilt(to: float, s: float) -> void:
	var n := sec(s)
	var p0: float = a.pitch
	for i in n:
		a.pitch = lerpf(p0, to, float(i + 1) / n)
		await get_tree().physics_frame

## 面向 ang 連砍三下，鏡頭停在 cam_yaw
func combo(ang: float, cam_yaw: float) -> void:
	a.yaw = cam_yaw
	for swing in 3:
		a.yaw = ang
		a._start_attack(swing)
		a.yaw = cam_yaw
		await frames(2)
		while a.attacking:
			await get_tree().physics_frame

## 跳起下劈，鏡頭停在 cam_yaw
func leap(ang: float, cam_yaw: float) -> void:
	a.yaw = cam_yaw
	await hold(["jump"], 2)
	await frames(sec(0.22))
	a.yaw = ang
	a._start_plunge()
	a.yaw = cam_yaw
	while a.plunge != 0:
		await get_tree().physics_frame

## 互動測試片（REEL=interact tools/record.sh <名稱>）：下劈打骷髏、兩種霧裡的下劈和揮砍
func interact(actors: Node3D, fog: Node) -> void:
	a = actors
	fade.color.a = 1.0
	await frames(sec(1.5))
	var n: Node3D = a.enemies[0].node
	var to_e := atan2(1.0, 1.0)
	a.pitch = -0.2
	await tp(n.global_position.x + 1.4, n.global_position.z + 1.4, to_e + 1.5)
	await frames(sec(1.0))
	await set_fade(1.0, 0.0, 0.3)
	await frames(sec(0.6))
	await leap(to_e, to_e + 1.5)
	await frames(sec(2.0))
	for preset in [2, 1]:
		await set_fade(0.0, 1.0, 0.25)
		fog.apply(preset)
		a.pitch = -0.42
		await tp(0, 110, 3.14)
		await frames(sec(4.0))
		await set_fade(1.0, 0.0, 0.3)
		await frames(sec(1.5))
		await leap(3.14, 3.14)
		await frames(sec(7.0))
		await combo(3.14, 3.14)
		await frames(sec(4.5))
	await set_fade(0.0, 1.0, 0.25)
	get_tree().quit()

## 小光靈測試片（REEL=wisp tools/record.sh <名稱>）：靠近骷髏、穿過城門暗處、靠近攤販、濃霧裡走
func wisp_clip(actors: Node3D, fog: Node) -> void:
	a = actors
	fade.color.a = 1.0
	await frames(sec(1.5))
	var en: Vector3 = a.enemies[0].node.global_position
	var from := en + Vector3(7.0, 0, 6.0)
	a.pitch = -0.16
	await tp(from.x, from.z, atan2(7.0, 6.0))
	await frames(sec(0.8))
	await set_fade(1.0, 0.0, 0.3)
	await hold(["move_forward"], sec(2.2))
	await orbit(atan2(7.0, 6.0) + 1.1, 3.0)
	await cut(0, 66, 0.0, -0.12)
	await hold(["move_forward"], sec(5.0))
	var st: Vector3 = a.stall_vs[0].node.global_position
	var out: Vector3 = (_v2(a.layout.plaza) - st).normalized() * 4.0
	await cut(st.x + out.x, st.z + out.z, atan2(out.x, out.z), -0.14)
	await orbit(atan2(out.x, out.z) + 0.9, 3.5)
	await set_fade(0.0, 1.0, 0.25)
	fog.apply(2)
	await tp(0, 92, 0.0)
	a.pitch = -0.08
	await frames(sec(1.5))
	await set_fade(1.0, 0.0, 0.3)
	await hold(["move_forward"], sec(3.5))
	await set_fade(0.0, 1.0, 0.4)
	get_tree().quit()

func _v2(v: Array) -> Vector3:
	return Vector3(v[0], v[1], v[2])

func reel(actors: Node3D, fog: Node) -> void:
	a = actors
	fade.color.a = 1.0
	await frames(sec(1.5))
	# 1. 先看天空和雲，跑向城門，慢慢走進暗處，看光靈照亮門洞
	a.pitch = 0.1
	await tp(-1, 92, 0.0)
	await frames(sec(0.8))
	await set_fade(1.0, 0.0, 0.4)
	await frames(sec(2.0))
	Input.action_press("move_forward")
	Input.action_press("run")
	await tilt(-0.18, 0.9)
	await frames(sec(3.4))
	Input.action_release("run")
	await frames(sec(4.0))
	Input.action_release("move_forward")
	# 2. 草地奔跑踏草，停下來連砍，草被削短
	var grass_cam := 0.876 + 1.3
	await cut(34.3, 79.5, grass_cam, -0.42)
	await hold(["move_forward", "run"], sec(2.5))
	await frames(sec(0.3))
	await combo(0.876, grass_cam)
	await frames(sec(1.0))
	# 3. 打村民：連擊的受擊反應
	var d: Dictionary = a.villagers[0]
	var n: Node3D = d.node
	var from: Vector3 = n.global_position + n.global_basis.z * 1.7
	var ang := atan2(from.x - n.global_position.x, from.z - n.global_position.z)
	await cut(from.x, from.z, ang, -0.16)
	await frames(sec(0.3))
	await combo(ang, ang + 1.9)
	await frames(sec(0.5))
	# 4. 走向骷髏，光靈飛過去換色，接著跳起下劈
	var en: Vector3 = a.enemies[0].node.global_position
	var to_e := atan2(7.0, 6.0)
	await cut(en.x + 7.0, en.z + 6.0, to_e, -0.16)
	await hold(["move_forward"], sec(3.0))
	await orbit(to_e - 1.1, 1.2)
	await leap(to_e, to_e - 1.1)
	await frames(sec(1.3))
	# 5. 噴水池
	await cut(3.5, 13.5, 0.566, -0.1)
	await orbit(1.15, 3.0)
	# 6. 市集與攤販：光靈變成暖色，布隨風動
	var st: Vector3 = a.stall_vs[0].node.global_position
	var out: Vector3 = (_v2(a.layout.plaza) - st).normalized() * 4.0
	await cut(st.x + out.x, st.z + out.z, atan2(out.x, out.z), -0.14)
	await orbit(atan2(out.x, out.z) + 0.35, 3.0)
	# 7. 煉金工作桌、鐵匠爐
	await cut(11.3, 13.9, atan2(-1.7, -1.2), -0.2)
	await orbit(atan2(-1.7, -1.2) + 0.4, 2.0)
	await cut(34.3, -20.8, -0.438, -0.2)
	await orbit(-0.438 - 0.3, 2.0)
	# 8. 騎麋鹿走主街
	await cut(0, 44, 0.0, -0.22)
	a._toggle_mount()
	await frames(sec(0.4))
	await hold(["move_forward"], sec(2.6))
	a._toggle_mount()
	# 9. 城外的小屋與小狐狸、松林木屋
	await cut(-29.3, 106, PI / 2.0, -0.12)
	await hold(["move_forward"], sec(1.0))
	await orbit(PI / 2.0 + 0.4, 1.5)
	await cut(32.3, 116, -PI / 2.0, -0.12)
	await hold(["move_forward"], sec(1.0))
	await orbit(-PI / 2.0 - 0.4, 1.5)
	# 10. 晨霧：光柱裡跑一段，揮砍和下劈吹開低霧
	await set_fade(0.0, 1.0, 0.25)
	fog.apply(1)
	await tp(6, 88, 0.157)
	a.pitch = -0.1
	await frames(sec(1.5))
	await set_fade(1.0, 0.0, 0.3)
	await hold(["move_forward", "run"], sec(2.5))
	await cut(0, 110, 3.14, -0.38)
	await frames(sec(0.6))
	await combo(3.14, 3.14)
	await frames(sec(1.2))
	await leap(3.14, 3.14)
	await frames(sec(2.2))
	# 11. 濃霧：光靈的光暈，下劈收尾
	await set_fade(0.0, 1.0, 0.25)
	fog.apply(2)
	await tp(0, 100, 0.0)
	a.pitch = -0.3
	await frames(sec(1.5))
	await set_fade(1.0, 0.0, 0.3)
	await hold(["move_forward"], sec(2.5))
	await leap(0.0, 0.0)
	await frames(sec(2.8))
	# 12. 雨天：烏雲、雨絲、水圈、路面積水的反光，光靈在雨裡照路
	await set_fade(0.0, 1.0, 0.25)
	fog.apply(fog.RAIN)
	a.pitch = -0.2
	await tp(2, 40, 0.0)
	await frames(sec(1.5))
	await set_fade(1.0, 0.0, 0.3)
	await hold(["move_forward"], sec(3.5))
	await tilt(-0.02, 0.8)
	await orbit(0.5, 2.5)
	await set_fade(0.0, 1.0, 0.5)
	get_tree().quit()
