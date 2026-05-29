extends RefCounted
class_name VoxelBatch

# A MultiMesh-backed batch of unit-box voxels drawn by ONE MultiMeshInstance3D
# (one draw call) instead of one MeshInstance3D node per voxel. This is what
# lets a plant with hundreds of voxels cost a single draw call and a single
# scene-tree node rather than hundreds of each.
#
# Voxels are added with a local transform (translation + per-voxel size baked
# into the basis scale) and a color (per-instance, via the MultiMesh color
# buffer — the *_mm.gdshader pair reads it). Removal hides the instance by
# zero-scaling it, so handles/indices stay stable and the rest of plant.gd can
# keep treating voxels as individually addressable.
#
# A CPU mirror of transforms + colors is kept so we can re-apply everything when
# the instance buffer has to grow (resizing instance_count can drop existing
# data on some backends).

const UNIT_BOX := Vector3(1.0, 1.0, 1.0)


# Lightweight stand-in for the old per-voxel MeshInstance3D. Carries just the
# data plant.gd actually reads (local position for height, base color for
# tint/untint) plus a back-reference so callers can recolor / remove it.
class Handle extends RefCounted:
	var batch: VoxelBatch = null
	var index: int = -1
	var local_pos: Vector3 = Vector3.ZERO
	var base_color: Color = Color.WHITE
	var alive: bool = true

	func set_color(c: Color) -> void:
		if alive and batch != null:
			batch._apply_color(index, c)

	func hide() -> void:
		if alive and batch != null:
			batch._hide(index)
			alive = false


var mmi: MultiMeshInstance3D = null
var _mm: MultiMesh = null
var _count: int = 0
var _xforms: Array[Transform3D] = []
var _colors: PackedColorArray = PackedColorArray()


func _init(parent: Node3D, material: Material, initial_capacity: int = 64) -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.instance_count = maxi(1, initial_capacity)
	_mm.visible_instance_count = 0
	_mm.mesh = VoxelMat.get_box(UNIT_BOX)
	mmi = MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.material_override = material
	# Voxels are small; without a generous custom AABB the MultiMesh can be
	# frustum-culled too aggressively (its computed AABB lags buffer writes).
	mmi.custom_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	parent.add_child(mmi)


# Add a voxel at a full local transform (translation + rotation + the per-voxel
# size baked into the basis scale, so the shared unit-box mesh can represent any
# voxel size/orientation). Returns a Handle the caller can recolor / remove.
func add(xform: Transform3D, color: Color) -> Handle:
	var i: int = _count
	_count += 1
	_xforms.append(xform)
	_colors.append(color)
	_ensure_capacity(_count)
	_mm.set_instance_transform(i, xform)
	_mm.set_instance_color(i, color)
	_mm.visible_instance_count = _count
	var h := Handle.new()
	h.batch = self
	h.index = i
	h.local_pos = xform.origin
	h.base_color = color
	return h


func _ensure_capacity(n: int) -> void:
	if n <= _mm.instance_count:
		return
	var new_cap: int = maxi(64, _mm.instance_count * 2)
	while new_cap < n:
		new_cap *= 2
	_mm.instance_count = new_cap
	# Re-apply from the mirror — resizing may have dropped existing instances.
	for i in _count - 1:
		_mm.set_instance_transform(i, _xforms[i])
		_mm.set_instance_color(i, _colors[i])
	_mm.visible_instance_count = _count


func _apply_color(i: int, c: Color) -> void:
	if i >= 0 and i < _count:
		_colors[i] = c
		_mm.set_instance_color(i, c)


func _hide(i: int) -> void:
	if i >= 0 and i < _count:
		# Zero-scale in place; keep the origin so any stray reference stays sane.
		var origin: Vector3 = _xforms[i].origin
		var hidden := Transform3D(Basis().scaled(Vector3.ZERO), origin)
		_xforms[i] = hidden
		_mm.set_instance_transform(i, hidden)


func clear() -> void:
	_count = 0
	_xforms.clear()
	_colors.resize(0)
	if _mm != null:
		_mm.visible_instance_count = 0


func queue_free() -> void:
	if mmi != null and is_instance_valid(mmi):
		mmi.queue_free()
	mmi = null
	_mm = null
