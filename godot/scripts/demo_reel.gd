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

func reel(actors: Node3D, fog: Node) -> void:
	a = actors
	fade.color.a = 1.0
	await frames(sec(1.5))
	# 1. 從城外跑進城門
	a.pitch = -0.18
	await tp(0, 84, 0.0)
	await frames(sec(0.8))
	await set_fade(1.0, 0.0, 0.4)
	await hold(["move_forward", "run"], sec(6.3))
	# 2. 草地奔跑：踏草與風吹
	await cut(24, 90, -1.2, -0.3)
	await hold(["move_forward", "run"], sec(4.0))
	# 3. 三段連擊，鏡頭在側前方才看得到揮劍
	var d: Dictionary = a.villagers[0]
	var n: Node3D = d.node
	var from: Vector3 = n.global_position + n.global_basis.z * 1.7
	var ang := atan2(from.x - n.global_position.x, from.z - n.global_position.z)
	await cut(from.x, from.z, ang, -0.16)
	var side := ang + 1.9
	a.yaw = side
	await frames(sec(0.5))
	for swing in 3:
		a.yaw = ang
		a._start_attack(swing)
		a.yaw = side
		await frames(2)
		while a.attacking:
			await get_tree().physics_frame
	await frames(sec(0.6))
	# 4. 噴水池
	await cut(3.5, 13.5, 0.566, -0.1)
	await hold(["move_forward"], sec(0.8))
	await orbit(1.15, 4.5)
	# 5. 市集攤位與隨風的布
	await cut(10.5, 0.2, 2.08, -0.1)
	await hold(["move_forward"], sec(0.8))
	await orbit(1.6, 3.8)
	# 5b. 廣場的煉金工作桌
	await cut(11.3, 13.9, atan2(-1.7, -1.2), -0.2)
	await orbit(atan2(-1.7, -1.2) + 0.7, 3.0)
	# 5c. 鐵匠鋪旁的熔爐
	await cut(34.3, -20.8, -0.438, -0.2)
	await orbit(-0.438 - 0.5, 3.0)
	# 6. 騎麋鹿走主街
	await cut(0, 44, 0.0, -0.22)
	a._toggle_mount()
	await frames(sec(0.6))
	await hold(["move_forward"], sec(3.0))
	await frames(sec(0.4))
	a._toggle_mount()
	# 6b. 城外的爬藤茅草屋與小狐狸
	await cut(-24, 106, PI / 2.0, -0.12)
	await hold(["move_forward"], sec(3.2))
	await orbit(PI / 2.0 + 0.5, 2.5)
	# 6c. 松林邊的木屋與岩石
	await cut(27, 116, -PI / 2.0, -0.12)
	await hold(["move_forward"], sec(3.2))
	await orbit(-PI / 2.0 - 0.5, 2.5)
	# 7. 晨霧
	await set_fade(0.0, 1.0, 0.25)
	fog.apply(1)
	await tp(6, 88, 0.157)
	a.pitch = -0.1
	await frames(sec(1.5))
	await set_fade(1.0, 0.0, 0.3)
	await hold(["move_forward", "run"], sec(5.0))
	# 8. 濃霧
	await set_fade(0.0, 1.0, 0.25)
	fog.apply(2)
	await tp(0, 92, 0.0)
	a.pitch = -0.05
	await frames(sec(1.5))
	await set_fade(1.0, 0.0, 0.3)
	await hold(["move_forward"], sec(4.0))
	await set_fade(0.0, 1.0, 0.4)
	get_tree().quit()
