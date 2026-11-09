extends SkeletonModifier3D
## 受擊動作：村民的模型只有 idle／walk，這裡程序化疊上去。
## 上身往擊退方向彎、頭往反方向甩、雙臂張開；amount 由外部驅動（命中瞬間拉滿，之後衰減）。

var amount := 0.0
var dir := Vector3.FORWARD    # 世界座標的擊退方向
var ids := {}

func bind(sk: Skeleton3D) -> void:
	for n in ["spine_03", "spine_05", "head", "upperarm_l", "upperarm_r"]:
		ids[n] = sk.find_bone(n)

func _process_modification_with_delta(_delta: float) -> void:
	if amount < 0.002 or ids.is_empty():
		return
	var sk := get_skeleton()
	var inv := sk.global_basis.orthonormalized().inverse()
	var up := (inv * Vector3.UP).normalized()
	var d := (inv * dir).normalized()
	var bend := up.cross(d).normalized()    # 繞這軸正轉＝上方往擊退方向倒
	_rotate_global(sk, ids.spine_03, Quaternion(bend, deg_to_rad(20.0) * amount))
	_rotate_global(sk, ids.spine_05, Quaternion(bend, deg_to_rad(12.0) * amount))
	_rotate_global(sk, ids.head, Quaternion(bend, deg_to_rad(-26.0) * amount))
	var chest := sk.get_bone_global_pose(ids.spine_05).origin
	for arm in [ids.upperarm_l, ids.upperarm_r]:
		var out: Vector3 = sk.get_bone_global_pose(arm).origin - chest
		out = (out - up * out.dot(up)).normalized()
		_rotate_global(sk, arm, Quaternion((-up).cross(out).normalized(), deg_to_rad(55.0) * amount))

func _rotate_global(sk: Skeleton3D, b: int, q: Quaternion) -> void:
	var p := sk.get_bone_parent(b)
	var pb := sk.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis.IDENTITY
	var nb := Basis(q) * sk.get_bone_global_pose(b).basis.orthonormalized()
	sk.set_bone_pose_rotation(b, (pb.inverse() * nb).get_rotation_quaternion())
