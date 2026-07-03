class_name DartTrailPool
extends RefCounted

const _VoxelMatScript = preload("res://scripts/voxel_mat.gd")

# PERFORMANCE_UNTHROTTLED #70 — shared fry dart-trail smear pool.

const POOL_SIZE: int = 16
const TRAIL_LIFETIME: float = 0.32

static var _slots: Array = []
static var _parent: Node = null
static var _inited: bool = false


static func _object_alive(v: Variant) -> bool:
	return v != null and typeof(v) == TYPE_OBJECT and is_instance_valid(v)


static func reset_for_test() -> void:
	for s in _slots:
		if s is Dictionary:
			_kill_slot_tween(s as Dictionary)
			var mi: Variant = (s as Dictionary).get("mi")
			if _object_alive(mi):
				(mi as Node).queue_free()
	_slots.clear()
	_parent = null
	_inited = false


static func _kill_slot_tween(s: Dictionary) -> void:
	var tw: Variant = s.get("tween")
	if _object_alive(tw) and tw is Tween:
		(tw as Tween).kill()
	s["tween"] = null


static func _ensure(parent: Node) -> void:
	if _inited and _parent == parent and is_instance_valid(_parent):
		return
	reset_for_test()
	_parent = parent
	_inited = true
	for i in POOL_SIZE:
		var mi := MeshInstance3D.new()
		mi.visible = false
		parent.add_child(mi)
		_slots.append({"mi": mi, "mat": null, "busy": false, "t": 0.0})


static func spawn(parent: Node, gp: Transform3D, smear_color: Color, heading: Vector3,
		on_release: Callable) -> bool:
	if parent == null or not is_instance_valid(parent):
		return false
	_ensure(parent)
	for s in _slots:
		if not (s is Dictionary):
			continue
		if bool(s.get("busy", false)):
			continue
		var mi_v: Variant = s.get("mi")
		if not _object_alive(mi_v):
			continue
		var mi: MeshInstance3D = mi_v as MeshInstance3D
		if mi == null:
			continue
		var v: float = 0.10
		mi.mesh = _VoxelMatScript.get_box(Vector3(v, v * 0.6, v * 1.4))
		var mat: ShaderMaterial = _VoxelMatScript.make_translucent(smear_color)
		mi.material_override = mat
		mi.global_transform = gp
		if heading.length_squared() > 0.001:
			var d: Vector3 = heading.normalized()
			var up := Vector3.UP if absf(d.dot(Vector3.UP)) > 0.92 else Vector3.UP
			mi.look_at_from_position(gp.origin, gp.origin + d, up)
		mi.scale = Vector3.ONE
		mi.visible = true
		s["busy"] = true
		s["mat"] = mat
		s["t"] = TRAIL_LIFETIME
		s["release_cb"] = on_release
		var tree: SceneTree = parent.get_tree()
		if tree == null:
			_release_slot(s)
			return false
		_kill_slot_tween(s)
		var tw := tree.create_tween().set_parallel(true)
		s["tween"] = tw
		tw.tween_property(mi, "scale", Vector3(0.35, 0.35, 0.18), TRAIL_LIFETIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		var faded: Color = Color(smear_color.r, smear_color.g, smear_color.b, 0.0)
		tw.tween_property(mat, "shader_parameter/albedo", faded, TRAIL_LIFETIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.chain().tween_callback(func() -> void:
			if _slots.find(s) < 0:
				return
			_release_slot(s))
		return true
	# REFINEMENT_II #79 — steal the oldest active slot instead of dropping.
	var oldest: Dictionary = {}
	var oldest_t: float = -1.0
	for s in _slots:
		if not (s is Dictionary) or not bool(s.get("busy", false)):
			continue
		var rem: float = float(s.get("t", 0.0))
		if rem > oldest_t:
			oldest_t = rem
			oldest = s
	if not oldest.is_empty():
		_release_slot(oldest)
		return spawn(parent, gp, smear_color, heading, on_release)
	return false


static func _release_slot(s: Dictionary) -> void:
	if s.is_empty() or _slots.find(s) < 0:
		return
	_kill_slot_tween(s)
	var mi_v: Variant = s.get("mi")
	if _object_alive(mi_v):
		var mi := mi_v as MeshInstance3D
		if mi != null:
			mi.visible = false
	s["busy"] = false
	s["mat"] = null
	var cb: Variant = s.get("release_cb")
	s.erase("release_cb")
	if cb is Callable and (cb as Callable).is_valid():
		(cb as Callable).call()
