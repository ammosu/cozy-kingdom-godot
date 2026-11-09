extends SkeletonModifier3D
## 揮劍動作：疊在 AnimationPlayer 上，只改上半身，腿繼續播走路。
## 不靠骨骼局部軸：關鍵姿勢寫成「角色空間的方向」（+Z 前、+Y 上、角色右手在 -X），每幀把骨頭轉到那個方向。

# 每個關鍵：[時間 0..1, 上臂方向, 前臂方向, 劍身方向, 上身左右轉(度), 前傾(度)]
const SWINGS := [
	[ # 第一段：右上往左橫砍
		[0.00, Vector3(-.85, .35, -.35), Vector3(-.6, .55, .55), Vector3(-.75, .45, -.5), -40.0, 0.0],
		[0.22, Vector3(-.9, .35, -.3), Vector3(-.75, .45, .45), Vector3(-.9, .35, -.25), -50.0, 0.0],
		[0.42, Vector3(-.25, .05, .95), Vector3(.05, .05, 1), Vector3(.1, .05, 1), 0.0, 8.0],
		[0.60, Vector3(.4, -.05, .9), Vector3(.8, 0, .55), Vector3(1, -.05, 0), 45.0, 8.0],
		[1.00, Vector3(.25, -.35, .8), Vector3(.6, -.2, .7), Vector3(.75, -.3, .55), 30.0, 0.0],
	],
	[ # 第二段：反手往右橫砍
		[0.00, Vector3(.3, .1, .9), Vector3(.75, .15, .6), Vector3(.95, .25, -.1), 35.0, 0.0],
		[0.22, Vector3(.35, .2, .85), Vector3(.8, .2, .5), Vector3(.95, .3, -.25), 45.0, 0.0],
		[0.42, Vector3(-.35, .05, .95), Vector3(-.1, .05, 1), Vector3(-.1, 0, 1), 0.0, 8.0],
		[0.60, Vector3(-.9, 0, .4), Vector3(-.9, .05, .4), Vector3(-1, 0, 0), -45.0, 8.0],
		[1.00, Vector3(-.8, -.4, .3), Vector3(-.7, -.3, .6), Vector3(-.7, -.35, .6), -25.0, 0.0],
	],
	[ # 第三段：高舉下劈
		[0.00, Vector3(-.4, .8, .1), Vector3(-.25, .9, -.2), Vector3(-.1, .6, -.8), -15.0, -8.0],
		[0.28, Vector3(-.35, .9, -.05), Vector3(-.2, .75, -.6), Vector3(-.05, .35, -.95), -20.0, -12.0],
		[0.48, Vector3(-.2, .15, 1), Vector3(-.05, -.05, 1), Vector3(0, -.25, 1), 5.0, 22.0],
		[0.62, Vector3(-.15, -.25, .95), Vector3(0, -.45, .9), Vector3(0, -.75, .65), 5.0, 28.0],
		[1.00, Vector3(-.4, -.6, .6), Vector3(-.3, -.6, .7), Vector3(-.2, -.7, .7), 0.0, 5.0],
	],
]
const FINGERS := ["index", "middle", "ring", "pinky"]
const CURL_SIGN := 1.0

var weight := 0.0     # 外部設定：0 = 完全不影響
var swing := 0
var t := 0.0
var blade_local := Vector3.UP     # 劍身在手骨局部空間的方向
var curl_axis_local := Vector3.UP
var to_skeleton := Basis.IDENTITY # 角色空間 → 骨架空間
var ids := {}

func bind(sk: Skeleton3D) -> void:
	for n in ["spine_03", "upperarm_r", "lowerarm_r", "hand_r"]:
		ids[n] = sk.find_bone(n)
	for f in FINGERS:
		for k in ["01", "02", "03"]:
			ids["%s_%s" % [f, k]] = sk.find_bone("%s_%s_r" % [f, k])

func sample() -> Array:
	var keys: Array = SWINGS[swing]
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if t <= b[0]:
			var k: float = smoothstep(0.0, 1.0, (t - a[0]) / maxf(b[0] - a[0], 0.001))
			return [_mix(a[1], b[1], k), _mix(a[2], b[2], k), _mix(a[3], b[3], k), lerpf(a[4], b[4], k), lerpf(a[5], b[5], k)]
	var last: Array = keys[-1]
	return [last[1].normalized(), last[2].normalized(), last[3].normalized(), last[4], last[5]]

func _mix(a: Vector3, b: Vector3, k: float) -> Vector3:
	return a.lerp(b, k).normalized()

func _process_modification_with_delta(_delta: float) -> void:
	if weight <= 0.001 or ids.is_empty():
		return
	var sk := get_skeleton()
	var s := sample()
	var up := to_skeleton * Vector3.UP
	var right := to_skeleton * Vector3.RIGHT
	_rotate_global(sk, ids.spine_03, Quaternion(up, deg_to_rad(s[3]) * 0.6 * weight) * Quaternion(right, deg_to_rad(s[4]) * weight))
	_aim(sk, ids.upperarm_r, ids.lowerarm_r, to_skeleton * s[0])
	_aim(sk, ids.lowerarm_r, ids.hand_r, to_skeleton * s[1])
	var hb := sk.get_bone_global_pose(ids.hand_r).basis.orthonormalized()
	var cur := (hb * blade_local).normalized()
	_rotate_global(sk, ids.hand_r, _arc(cur, (to_skeleton * s[2]).normalized()).slerp(Quaternion.IDENTITY, 1.0 - weight))
	# 握拳：手指繞劍柄方向彎
	for f in FINGERS:
		for k in ["01", "02", "03"]:
			var b: int = ids["%s_%s" % [f, k]]
			if b < 0:
				continue
			var hand := sk.get_bone_global_pose(ids.hand_r).basis.orthonormalized()
			_rotate_global(sk, b, Quaternion((hand * curl_axis_local).normalized(), CURL_SIGN * 1.05 * weight))

func _arc(a: Vector3, b: Vector3) -> Quaternion:
	if a.dot(b) < -0.9995:
		return Quaternion(a.cross(Vector3.RIGHT if absf(a.x) < 0.9 else Vector3.UP).normalized(), PI)
	return Quaternion(a, b)

func _aim(sk: Skeleton3D, b: int, tip: int, target: Vector3) -> void:
	var g := sk.get_bone_global_pose(b)
	var dir := (sk.get_bone_global_pose(tip).origin - g.origin).normalized()
	_rotate_global(sk, b, _arc(dir, target.normalized()).slerp(Quaternion.IDENTITY, 1.0 - weight))

func _rotate_global(sk: Skeleton3D, b: int, q: Quaternion) -> void:
	var p := sk.get_bone_parent(b)
	var pb := sk.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis.IDENTITY
	var nb := Basis(q) * sk.get_bone_global_pose(b).basis.orthonormalized()
	sk.set_bone_pose_rotation(b, (pb.inverse() * nb).get_rotation_quaternion())
