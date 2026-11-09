extends Node3D
## Hunyuan3D 生成的模型（assets/props/*.glb）擺進王國。
## - hy 模式（載入 kingdom_hy.glb 時）：依 layout 自動擺房子、攤位、噴水池、塔樓、城門樓、主堡，再撒小道具。
## - 另外 assets/props/props.json 可手動加物件：{"file", "pos": [x, z], "yaw", "height" 或 "fit": [寬, 深]}
## 模型正面一律是 +Z；yaw 是正面要朝的角度（0 = +Z）。量包圍盒、縮放、底部貼地，產生三角網格碰撞。
## 這個節點要在種草之前 setup，草和灌木的射線才會避開模型。

# 民房款式：[檔名, 原設計寬, 深, 樓層, 最多幾棟]
const HOUSES := [
	["ck_house_a", 6.0, 5.0, 2, 99],
	["ck_house_b", 5.0, 5.0, 3, 99],
	["ck_house_c", 8.0, 5.5, 1, 99],
	["ck_house_d", 6.0, 6.0, 2, 99],
	["ck_house_e", 7.0, 6.0, 3, 8],
	["ck_bakery", 7.0, 6.0, 2, 3],
	["ck_inn", 8.0, 6.0, 3, 2],
	["ck_smithy", 7.0, 5.5, 2, 2],
]
# 城牆模型與一節的長度（ck_wall2 高約 7.8 m 時不變形的長度約 6 m；舊版 ck_wall 用 10 m）
const WALL_PIECE := "ck_wall2"
const WALL_PIECE_LEN := 6.0
const STALLS := ["ck_stall", "ck_stall_b", "ck_stall_c"]

var space: PhysicsDirectSpaceState3D
var scenes := {}
var counts := {}
var cloth_mats := {}
var fountain: Node3D
var rng := RandomNumberGenerator.new()

func setup(layout: Dictionary, hy: bool) -> void:
	space = get_world_3d().direct_space_state
	rng.seed = 5
	if hy:
		_place_kingdom(layout)
	var path := "res://assets/props/props.json"
	if FileAccess.file_exists(path):
		for it in JSON.parse_string(FileAccess.get_file_as_string(path)):
			place(it.file, Vector2(it.pos[0], it.pos[1]), it.get("yaw", 0.0), it)
	var summary := []
	for k in counts:
		summary.append("%s×%d" % [k, counts[k]])
	print("props: ", ", ".join(summary))

func _place_kingdom(L: Dictionary) -> void:
	var plaza := Vector2(L.plaza[0], L.plaza[2])
	# 房子：依占地挑最接近的款式（樓層差、寬深差），同款太多就換
	for h in L.houses:
		var best := ""
		var best_score := 1e9
		for d in HOUSES:
			if counts.get(d[0], 0) >= d[4] or not _exists(d[0]):
				continue
			var score: float = absf(d[1] - h.w) + absf(d[2] - h.d) + 1.5 * absf(d[3] - h.floors) + rng.randf() * 2.5 + counts.get(d[0], 0) * 0.15
			if score < best_score:
				best_score = score; best = d[0]
		if best != "":
			place(best, Vector2(h.pos[0], h.pos[2]), h.yaw, {"fit": [h.w + 0.4, h.d + 0.4]})
	# 市集攤位：櫃台朝廣場中心
	for i in L.stalls.size():
		var p := Vector2(L.stalls[i][0], L.stalls[i][2])
		_add_cloth_wind(place(STALLS[i % STALLS.size()], p, _yaw_to(p, plaza), {"height": 3.0}))
		# 攤位旁堆貨，市集才有人在做生意的樣子
		var out := (p - plaza).normalized()
		var tan := Vector2(out.y, -out.x) * (1.0 if i % 2 == 0 else -1.0)
		place("ck_props_barrels", p + tan * 2.1 + out * 0.5, rng.randf() * 360.0, {"height": 1.3})
	var ft := place("ck_fountain", plaza, 0.0, {"fit": [6.6, 6.6]})
	if ft:
		fountain = load("res://scripts/fountain.gd").new()
		ft.add_child(fountain)
		fountain.setup(ft.get_child(0))
	# 城牆：每段切成約 WALL_PIECE_LEN 一節，正面朝外；節與節略重疊蓋住接縫，轉角由塔樓蓋住。碰撞用 Blender 的隱藏方塊
	var wh: float = L.get("wall_h", 7.0)
	for seg in L.get("wall_segs", []):
		var a := Vector2(seg[0][0], seg[0][2])
		var b := Vector2(seg[1][0], seg[1][2])
		var n := maxi(1, roundi(a.distance_to(b) / WALL_PIECE_LEN))
		var piece := a.distance_to(b) / n
		for k in n:
			var p := a.lerp(b, (k + 0.5) / n)
			# 三節裡換一節有扶壁的款式；隨機翻面、高度略不同，長牆才不會一眼看出重複
			var file: String = "ck_wall3" if rng.randf() < 0.3 and _exists("ck_wall3") else WALL_PIECE
			var ya := rad_to_deg(atan2(p.x, p.y)) + (180.0 if rng.randf() < 0.5 else 0.0)
			place(file, p, ya, {"box": [piece + 0.5, (wh + 0.8) * rng.randf_range(0.96, 1.05), 2.6], "collide": false})
	# 城牆塔樓（正面朝外）、城門樓（朝南，碰撞用 Blender 的隱藏方塊，門洞才走得過）、主堡
	for t in L.towers:
		var p := Vector2(t[0], t[2])
		place("ck_tower", p, rad_to_deg(atan2(p.x, p.y)), {"fit": [7.4, 7.4]})
	place("ck_gatehouse", Vector2(L.gatehouse[0], L.gatehouse[2]), 0.0, {"fit": [15.5, 6.5], "collide": false})
	place("ck_keep", Vector2(L.keep[0], L.keep[2]), 0.0, {"fit": [20.0, 18.0]})
	_scatter(L, plaza)

func _scatter(L: Dictionary, plaza: Vector2) -> void:
	# 屋前：木桶貨物、長椅（門的左右側）、柴堆（屋側）
	for h in L.houses:
		var pos := Vector2(h.pos[0], h.pos[2])
		var yaw := deg_to_rad(h.yaw)
		var fwd := Vector2(sin(yaw), cos(yaw))
		var side := Vector2(fwd.y, -fwd.x)
		var u := rng.randf()
		var s := 1.0 if rng.randf() < 0.5 else -1.0
		var at: Vector2 = pos + fwd * (h.d * 0.5 + 0.9) + side * s * (h.w * 0.32)
		if u < 0.42:
			place("ck_props_barrels", at, h.yaw + rng.randf_range(-20, 20), {"height": 1.4})
		elif u < 0.58:
			place("ck_bench", at, h.yaw, {"height": 1.0})
		elif u < 0.78:
			place("ck_woodpile", pos + side * s * (h.w * 0.5 + 1.1), h.yaw + 90 * s, {"height": 1.8})
	_lots(L)
	# 廣場：噴水池外圈長椅朝中心、兩台推車
	for i in 6:
		var a := TAU * i / 6.0
		var p := plaza + Vector2(cos(a), sin(a)) * 5.6
		place("ck_bench", p, _yaw_to(p, plaza), {"height": 1.0})
	for i in 2:
		var a := TAU * (i + 0.5) / 2.0 + 0.4
		var p: Vector2 = plaza + Vector2(cos(a), sin(a)) * (L.plaza_radius + 1.5)
		place("ck_cart", p, rng.randf() * 360.0, {"height": 1.8})
	# 路燈：沿每條路兩側交替、每 14 m 一支
	var n := 0
	for r in L.roads:
		var a := Vector2(r.a[0], r.a[2])
		var b := Vector2(r.b[0], r.b[2])
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var nrm := Vector2(-dir.y, dir.x)
		var t := 5.0
		while t < length - 3.0:
			var p: Vector2 = a + dir * t + nrm * (r.w * 0.5 + 0.5) * (1.0 if n % 2 == 0 else -1.0)
			if p.length() < L.wall_radius - 3.0 and p.distance_to(plaza) > L.plaza_radius + 1.0 and _free(p, 0.6):
				place("ck_lamppost", p, _yaw_to(p, a + dir * t), {"height": 3.4})
			n += 1
			t += 14.0

## 把攤位換成會隨風擺動的材質（同一款共用一個材質）
func _add_cloth_wind(holder: Node3D) -> void:
	if holder == null:
		return
	for n in holder.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var key := String(holder.name)
		if not cloth_mats.has(key):
			var src := mi.mesh.surface_get_material(0) as BaseMaterial3D
			var m := ShaderMaterial.new()
			m.shader = load("res://shaders/cloth_wind.gdshader")
			m.set_shader_parameter("albedo_tex", src.albedo_texture)
			var b3 := mi.transform.basis.orthonormalized()
			m.set_shader_parameter("node_basis", b3)
			var box := Transform3D(b3, Vector3.ZERO) * mi.mesh.get_aabb()
			m.set_shader_parameter("box_min", box.position)
			m.set_shader_parameter("box_size", box.size)
			cloth_mats[key] = m
		mi.material_override = cloth_mats[key]

func set_time(t: float) -> void:
	for k in cloth_mats:
		cloth_mats[k].set_shader_parameter("time_override", t)
	if fountain:
		fountain.set_time(t)

## 院落：約四成的房子圍起側面與後方的籬笆，後院放菜圃，城鎮才讀得出一塊塊地
func _lots(L: Dictionary) -> void:
	if not _exists("ck_fence"):
		return
	for h in L.houses:
		if rng.randf() > 0.45:
			continue
		var c := Vector2(h.pos[0], h.pos[2])
		var yaw := deg_to_rad(h.yaw)
		var fwd := Vector2(sin(yaw), cos(yaw))
		var side := Vector2(fwd.y, -fwd.x)
		var hw: float = h.w * 0.5 + 1.8
		var hb: float = h.d * 0.5 + 3.4
		var hf: float = h.d * 0.5 + 0.2
		# [起點, 終點, 籬笆面朝的角度]
		var runs := [
			[c + side * hw + fwd * hf, c + side * hw - fwd * hb, h.yaw + 90.0],
			[c - side * hw + fwd * hf, c - side * hw - fwd * hb, h.yaw + 90.0],
			[c - fwd * hb + side * hw, c - fwd * hb - side * hw, h.yaw],
		]
		for run in runs:
			var a: Vector2 = run[0]
			var b: Vector2 = run[1]
			var n := maxi(1, roundi(a.distance_to(b) / 2.4))
			var piece := a.distance_to(b) / n
			for k in n:
				var p := a.lerp(b, (k + 0.5) / n)
				if p.length() < L.wall_radius - 3.0 and _on_grass(p, 1.0):
					place("ck_fence", p, run[2], {"box": [piece + 0.1, 1.05, 0.28], "tint": Color(0.68, 0.62, 0.58)})
		var g: Vector2 = c - fwd * (h.d * 0.5 + 1.75) + side * (rng.randf_range(-1.0, 1.0) * h.w * 0.2)
		if _exists("ck_garden") and _on_grass(g, 1.3):
			place("ck_garden", g, h.yaw, {"fit": [2.6, 1.9]})

func _on_grass(p: Vector2, r: float) -> bool:
	for o in [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		var hit := _ground(p + o)
		if hit.is_empty() or not String(hit.collider.get_parent().name).begins_with("Terrain"):
			return false
	return not get_parent()._on_road_or_building(p, 0.5)

func _yaw_to(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return rad_to_deg(atan2(d.x, d.y))

func _exists(file: String) -> bool:
	return ResourceLoader.exists("res://assets/props/%s.glb" % file)

func _ground(p: Vector2) -> Dictionary:
	# 跳過 HiddenCol*（城牆、城門樓的隱藏碰撞方塊），不然牆段會被擺到方塊頂上
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 120, p.y), Vector3(p.x, -50, p.y))
	for i in 4:
		var hit := space.intersect_ray(q)
		if hit.is_empty() or not String(hit.collider.get_parent().name).begins_with("HiddenCol"):
			return hit
		q.exclude = q.exclude + [hit.rid]
	return {}

func _free(p: Vector2, r: float) -> bool:
	# 這點附近沒有已擺好的模型（射線先打到的是地形或道路）
	for o in [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		var hit := _ground(p + o)
		if hit.is_empty():
			continue
		var nm := String(hit.collider.get_parent().name)
		if not (nm.begins_with("Terrain") or nm.begins_with("Roads")):
			return false
	return true

func place(file: String, p: Vector2, yaw_deg: float, opt: Dictionary) -> Node3D:
	if not _exists(file):
		return null
	if not scenes.has(file):
		var res: PackedScene = load("res://assets/props/%s.glb" % file)
		var node0: Node3D = res.instantiate()
		if opt.has("tint"):   # 材質是這個模型共用的，只調一次
			for mi in node0.find_children("*", "MeshInstance3D", true, false):
				(mi.mesh.surface_get_material(0) as BaseMaterial3D).albedo_color = opt.tint
		scenes[file] = [res, _aabb(node0)]
		node0.free()
	var aabb: AABB = scenes[file][1]
	var node: Node3D = scenes[file][0].instantiate()
	var sc := Vector3.ONE
	if opt.has("box"):
		sc = Vector3(opt.box[0] / aabb.size.x, opt.box[1] / aabb.size.y, opt.box[2] / aabb.size.z)
	elif opt.has("fit"):
		var sx: float = opt.fit[0] / aabb.size.x
		var sz: float = opt.fit[1] / aabb.size.z
		var sy := (sx + sz) * 0.5
		sc = Vector3(clampf(sx, sy * 0.8, sy * 1.2), sy, clampf(sz, sy * 0.8, sy * 1.2))
	else:
		sc = Vector3.ONE * (float(opt.get("height", 2.0)) / aabb.size.y)
	var holder := Node3D.new()
	holder.name = file
	add_child(holder)
	holder.add_child(node)
	node.scale = sc
	node.position = Vector3(-aabb.get_center().x * sc.x, -aabb.position.y * sc.y, -aabb.get_center().z * sc.z)
	var y := 0.0
	var hit := _ground(p)
	if not hit.is_empty():
		y = hit.position.y
	holder.position = Vector3(p.x, y - 0.05, p.y)
	holder.rotation.y = deg_to_rad(yaw_deg)
	if opt.get("collide", true):
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).create_trimesh_collision()
	counts[file] = counts.get(file, 0) + 1
	return holder

func _aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var t := m.transform
		var par := m.get_parent()
		while par != root and par is Node3D:
			t = (par as Node3D).transform * t
			par = par.get_parent()
		var b := t * m.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
