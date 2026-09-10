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
	var transform: Transform3D = Transform3D.IDENTITY
	var alive: bool = true
	var visible: bool = true

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
			transform = xform
			local_pos = xform.origin
			if visible:
				batch._apply_transform(index, xform)

	# Temporarily hide damage such as pinholes without changing biological
	# biomass. A later true restores the latest logical transform.
	func set_visible(value: bool) -> void:
		if not alive or batch == null or visible == value:
			return
		visible = value
		if visible:
			batch._apply_transform(index, transform)
		else:
			batch._hide(index)

	func hide() -> void:
		if alive and batch != null:
			batch._hide(index)
			alive = false
			visible = false


var mmi: MultiMeshInstance3D = null
var _mm: MultiMesh = null
var _count: int = 0
var _visible: int = 0
var _xforms: Array[Transform3D] = []
var _colors: PackedColorArray = PackedColorArray()
var _customs: PackedColorArray = PackedColorArray()
var _use_custom: bool = false
var _bounds_dirty: bool = true
var _bounds_margin: Vector3 = Vector3(0.75, 0.35, 0.75)
var _deferred_indices: Array[int] = []
var _deferred_cursor: int = 0
var _handles: Array[WeakRef] = []
var _underutilized_s: float = 0.0
const COMPACT_HOLD_S: float = 5.0
const MIN_CAPACITY: int = 64


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
	# Start conservative enough for the first write; flush() replaces this with
	# live bounds expanded by shader-sway margin.
	mmi.custom_aabb = AABB(-_bounds_margin, _bounds_margin * 2.0)
	parent.add_child(mmi)


# Add a voxel at a full local transform (translation + rotation + the per-voxel
# size baked into the basis scale, so the shared unit-box mesh can represent any
# voxel size/orientation). Returns a Handle the caller can recolor / remove.
func add(xform: Transform3D, color: Color) -> Handle:
	var h: Handle = _reserve(xform, color, false)
	_write_instance(h.index)
	return h


# Reserve a stable biological handle immediately, but defer its GPU write.
# Large cached leaves use this so their descriptors can be admitted in one
# growth step and uploaded in bounded chunks over later ticks.
func add_deferred(xform: Transform3D, color: Color) -> Handle:
	var h: Handle = _reserve(xform, color, true)
	_deferred_indices.append(h.index)
	return h


func _reserve(xform: Transform3D, color: Color, deferred: bool) -> Handle:
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
	_bounds_dirty = true
	_colors.append(color)
	var custom: Color = Color(0.0, 0.0, 0.0, 1.0)
	if _use_custom:
		_customs.append(custom)
	_ensure_capacity(_count, i if deferred else -1)
	var h := Handle.new()
	h.batch = self
	h.index = i
	h.local_pos = xform.origin
	h.base_color = color
	h.transform = xform
	_handles.append(weakref(h))
	return h


func _write_instance(i: int) -> void:
	_mm.set_instance_transform(i, _xforms[i])
	_mm.set_instance_color(i, _colors[i])
	if _use_custom:
		_mm.set_instance_custom_data(i, _customs[i])


func has_deferred_writes() -> bool:
	return _deferred_cursor < _deferred_indices.size()


# Returns the number of GPU instance writes performed. Visibility is committed
# exactly once after the final chunk, avoiding partially drawn leaf silhouettes.
func process_deferred_writes(max_writes: int) -> int:
	var wrote: int = 0
	while wrote < maxi(0, max_writes) and has_deferred_writes():
		_write_instance(_deferred_indices[_deferred_cursor])
		_deferred_cursor += 1
		wrote += 1
	if not has_deferred_writes() and not _deferred_indices.is_empty():
		_deferred_indices.clear()
		_deferred_cursor = 0
		flush()
	return wrote


# Shrink sustained sparse buffers without invalidating biological handles.
# Callers invoke this at coarse simulation cadence; compaction is forbidden
# while a deferred bake owns unwritten slots.
func consider_compaction(dt: float) -> bool:
	if _mm == null or has_deferred_writes():
		_underutilized_s = 0.0
		return false
	var live_count: int = 0
	for handle_ref in _handles:
		var h: Handle = handle_ref.get_ref() as Handle
		if h != null and h.alive:
			live_count += 1
	var capacity: int = _mm.instance_count
	if capacity <= MIN_CAPACITY or live_count * 4 >= capacity:
		_underutilized_s = 0.0
		return false
	_underutilized_s += maxf(0.0, dt)
	if _underutilized_s < COMPACT_HOLD_S:
		return false
	_compact_live_handles(live_count)
	_underutilized_s = 0.0
	return true


func _compact_live_handles(live_count: int) -> void:
	var new_xforms: Array[Transform3D] = []
	var new_colors := PackedColorArray()
	var new_customs := PackedColorArray()
	var new_handles: Array[Handle] = []
	for handle_ref in _handles:
		var h: Handle = handle_ref.get_ref() as Handle
		if h == null or not h.alive:
			if h != null:
				h.index = -1
				h.batch = null
			continue
		var old_index: int = h.index
		h.index = new_handles.size()
		new_handles.append(h)
		new_xforms.append(_xforms[old_index])
		new_colors.append(_colors[old_index])
		if _use_custom:
			new_customs.append(_customs[old_index])

	var new_mm := MultiMesh.new()
	new_mm.transform_format = MultiMesh.TRANSFORM_3D
	new_mm.use_colors = true
	new_mm.use_custom_data = _use_custom
	var new_capacity: int = MIN_CAPACITY
	while new_capacity < maxi(1, live_count):
		new_capacity *= 2
	new_mm.instance_count = new_capacity
	new_mm.mesh = _mm.mesh
	_mm = new_mm
	mmi.multimesh = _mm
	_xforms = new_xforms
	_colors = new_colors
	_customs = new_customs
	_handles.clear()
	for h in new_handles:
		_handles.append(weakref(h))
	_count = live_count
	_visible = live_count
	for i in _count:
		_write_instance(i)
	_mm.visible_instance_count = _visible
	_bounds_dirty = true
	_refresh_custom_aabb()


# Commit pending instance writes in one GPU upload (avoids Metal fence stalls
# when hundreds of plants bake leaves in the same frame).
func flush() -> void:
	if has_deferred_writes():
		return
	if _count == _visible and not _bounds_dirty:
		return
	_visible = _count
	_mm.visible_instance_count = _visible
	if _count >= 8:
		blit_buffer()
	_refresh_custom_aabb()


func set_bounds_margin(margin: Vector3) -> void:
	_bounds_margin = Vector3(
		maxf(0.0, margin.x), maxf(0.0, margin.y), maxf(0.0, margin.z))
	_bounds_dirty = true


func _refresh_custom_aabb() -> void:
	if mmi == null or not _bounds_dirty:
		return
	var have_live: bool = false
	var min_v: Vector3 = Vector3.ZERO
	var max_v: Vector3 = Vector3.ZERO
	for xform in _xforms:
		if not xform.is_finite():
			continue
		var bx: Vector3 = xform.basis.x.abs()
		var by: Vector3 = xform.basis.y.abs()
		var bz: Vector3 = xform.basis.z.abs()
		var half: Vector3 = (bx + by + bz) * 0.5
		if half.length_squared() <= 1e-10:
			continue
		var lo: Vector3 = xform.origin - half
		var hi: Vector3 = xform.origin + half
		if not have_live:
			min_v = lo
			max_v = hi
			have_live = true
		else:
			min_v = min_v.min(lo)
			max_v = max_v.max(hi)
	if not have_live:
		mmi.custom_aabb = AABB(-_bounds_margin, _bounds_margin * 2.0)
	else:
		min_v -= _bounds_margin
		max_v += _bounds_margin
		mmi.custom_aabb = AABB(min_v, max_v - min_v)
	_bounds_dirty = false


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

func _ensure_capacity(n: int, first_unwritten: int = -1) -> void:
	if n <= _mm.instance_count:
		return
	var new_cap: int = maxi(64, _mm.instance_count * 2)
	while new_cap < n:
		new_cap *= 2
	_mm.instance_count = new_cap
	# Re-apply from the mirror — resizing may have dropped existing instances.
	var rewrite_count: int = first_unwritten if first_unwritten >= 0 else _count
	for i in range(rewrite_count):
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
		_bounds_dirty = true


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
		_bounds_dirty = true


func clear() -> void:
	for handle_ref in _handles:
		var h: Handle = handle_ref.get_ref() as Handle
		if h != null:
			h.alive = false
			h.visible = false
			h.index = -1
			h.batch = null
	_count = 0
	_visible = 0
	_xforms.clear()
	_colors.resize(0)
	_customs.resize(0)
	_deferred_indices.clear()
	_deferred_cursor = 0
	_handles.clear()
	_underutilized_s = 0.0
	_bounds_dirty = true
	if _mm != null:
		_mm.visible_instance_count = 0
		_refresh_custom_aabb()


func queue_free() -> void:
	if mmi != null and is_instance_valid(mmi):
		mmi.queue_free()
	mmi = null
	_mm = null
