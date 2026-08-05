extends RefCounted
class_name VoxelBatch

const _MultiMeshBufferBlit = preload("res://scripts/multimesh_buffer_blit.gd")

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

	func set_custom_data(c: Color) -> void:
		if alive and batch != null:
			batch._apply_custom(index, c)

	# Re-write this voxel's per-instance transform. Used by entities that
	# animate individual voxels (biofilm sheet sway, algae waver) without
	# moving the whole batch via the parent Node3D's transform.
	func set_transform(xform: Transform3D) -> void:
		if alive and batch != null:
			batch._apply_transform(index, xform)

	func hide() -> void:
		if alive and batch != null:
			batch._hide(index)
			alive = false


var mmi: MultiMeshInstance3D = null
var _mm: MultiMesh = null
var _count: int = 0
var _visible: int = 0
var _xforms: Array[Transform3D] = []
var _colors: PackedColorArray = PackedColorArray()
var _customs: PackedColorArray = PackedColorArray()
var _use_custom: bool = false


func _init(parent: Node3D, material: Material, initial_capacity: int = 64,
		use_custom_data: bool = false) -> void:
	_use_custom = use_custom_data
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	if _use_custom:
		_mm.use_custom_data = true
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
	# Guard against non-finite transforms (NaN/Inf) that would flood the
	# Godot console with "instance_set_transform: !v.is_finite()" errors and
	# corrupt the _xforms mirror (causing _ensure_capacity to re-fire the
	# error for every existing instance on the next resize). Replace with a
	# zero-scale hidden placeholder at the origin so the slot is occupied but
	# invisible; the voxel will just be missing rather than spamming errors.
	var safe_xform: Transform3D = xform
	if not xform.is_finite():
		push_warning("VoxelBatch.add: non-finite transform (pos=%s), hiding voxel." % xform.origin)
		safe_xform = Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	_xforms.append(safe_xform)
	_colors.append(color)
	var custom: Color = Color(0.0, 0.0, 0.0, 1.0)
	if _use_custom:
		_customs.append(custom)
	_ensure_capacity(_count)
	_mm.set_instance_transform(i, safe_xform)
	_mm.set_instance_color(i, color)
	if _use_custom:
		_mm.set_instance_custom_data(i, custom)
	var h := Handle.new()
	h.batch = self
	h.index = i
	h.local_pos = xform.origin
	h.base_color = color
	return h


# Commit pending instance writes in one GPU upload (avoids Metal fence stalls
# when hundreds of plants bake leaves in the same frame).
func flush() -> void:
	if _count == _visible:
		return
	_visible = _count
	_mm.visible_instance_count = _visible
	if _count >= 8:
		blit_buffer()


func blit_buffer() -> void:
	if _mm == null or _count <= 0:
		return
	# Metal has historically corrupted bulk MultiMesh uploads under MSAA /
	# fence pressure. Per-instance writes are slower but stable on macOS.
	if OS.get_name() == "macOS":
		for i in range(_count):
			var xform: Transform3D = _xforms[i]
			if not xform.is_finite():
				xform = Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
			_mm.set_instance_transform(i, xform)
			_mm.set_instance_color(i, _colors[i])
			if _use_custom and i < _customs.size():
				_mm.set_instance_custom_data(i, _customs[i])
		for i in range(_count, _mm.instance_count):
			_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
		return
	var xforms_arr: Array = []
	xforms_arr.assign(_xforms.slice(0, _count))
	_MultiMeshBufferBlit.upload(_mm, xforms_arr, _colors, _customs, _count, _use_custom)

func _ensure_capacity(n: int) -> void:
	if n <= _mm.instance_count:
		return
	var new_cap: int = maxi(64, _mm.instance_count * 2)
	while new_cap < n:
		new_cap *= 2
	_mm.instance_count = new_cap
	# Re-apply from the mirror — resizing may have dropped existing instances.
	for i in range(_count):
		var xform: Transform3D = _xforms[i]
		if not xform.is_finite():
			xform = Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
			_xforms[i] = xform
		_mm.set_instance_transform(i, xform)
		_mm.set_instance_color(i, _colors[i])
		if _use_custom and i < _customs.size():
			_mm.set_instance_custom_data(i, _customs[i])
	_visible = mini(_visible, _count)
	_mm.visible_instance_count = _visible


func _apply_color(i: int, c: Color) -> void:
	if i >= 0 and i < _count:
		_colors[i] = c
		_mm.set_instance_color(i, c)


func _apply_custom(i: int, c: Color) -> void:
	if not _use_custom or i < 0 or i >= _count:
		return
	_customs[i] = c
	_mm.set_instance_custom_data(i, c)


func _apply_transform(i: int, x: Transform3D) -> void:
	if i >= 0 and i < _count:
		if not x.is_finite():
			# Same guard as add() — silently skip non-finite per-frame updates
			# so a corrupted animation origin doesn't flood the console.
			return
		_xforms[i] = x
		_mm.set_instance_transform(i, x)


func _hide(i: int) -> void:
	if i >= 0 and i < _count:
		# Zero-scale in place; keep the origin so any stray reference stays sane.
		# If the stored origin was already non-finite (from a prior bad add()),
		# fall back to Vector3.ZERO so the hide transform is always valid.
		var origin: Vector3 = _xforms[i].origin
		if not origin.is_finite():
			origin = Vector3.ZERO
		var hidden := Transform3D(Basis().scaled(Vector3.ZERO), origin)
		_xforms[i] = hidden
		_mm.set_instance_transform(i, hidden)


func clear() -> void:
	_count = 0
	_visible = 0
	_xforms.clear()
	_colors.resize(0)
	_customs.resize(0)
	if _mm != null:
		_mm.visible_instance_count = 0


func queue_free() -> void:
	if mmi != null and is_instance_valid(mmi):
		mmi.queue_free()
	mmi = null
	_mm = null
