extends RefCounted

# PERFORMANCE_UNTHROTTLED #69 — one MultiMesh draw per species family.
# No class_name — callers preload this script and invoke static methods on the
# const (see sim_driver.gd). Global class_name + static calls hit Godot parse
# limits when the registry lags behind reload.

static var _batches: Dictionary = {}
static var _sync_slots: Array = []
static var _active: bool = false
static var _drivers: Dictionary = {}
static var _owners: Dictionary = {}
static var _render_frame: int = -1
static var _inverse_cache: Dictionary = {}
static var _pivot_cache: Dictionary = {}

# Upload after fish have animated their pivots, rather than at the 10 Hz
# simulation cadence. A driver belongs to the same scene as its geometry.
class RenderSync extends Node:
	var sync: Callable
	var release: Callable
	func _process(_dt: float) -> void:
		sync.call()
	func _exit_tree() -> void:
		release.call()

const MIN_FISH_FOR_BATCH: int = 36


static func reset_for_test() -> void:
	for b in _batches.values():
		if b is VoxelBatch:
			(b as VoxelBatch).queue_free()
	_batches.clear()
	_sync_slots.clear()
	_owners.clear()
	for ref in _drivers.values():
		var driver: Node = (ref as WeakRef).get_ref() as Node
		if is_instance_valid(driver):
			driver.queue_free()
	_drivers.clear()
	_render_frame = -1
	_active = false


static func set_active(on: bool) -> void:
	# Admission changes affect future geometry; existing fish still animate.
	_active = on


static func active() -> bool:
	return _active


static func should_enable(fish_count: int) -> bool:
	return fish_count >= MIN_FISH_FOR_BATCH


static func sync_slot_count() -> int:
	return _sync_slots.size()


static func _key(species: String, subspecies: String = "") -> String:
	if subspecies != "":
		return "%s|%s" % [species, subspecies]
	return species


static func register_instance(parent: Node3D, species: String, xform: Transform3D,
		color: Color, bone_index: float = 0.0, subspecies: String = "") -> VoxelBatch.Handle:
	var owner_id: int = parent.get_instance_id()
	var k: String = "%d|%s" % [owner_id, _key(species, subspecies)]
	if not _drivers.has(owner_id):
		var driver := RenderSync.new()
		driver.name = "FaunaRenderSync"
		driver.process_priority = 100
		driver.sync = sync_render_frame
		driver.release = release_parent.bind(owner_id)
		parent.add_child(driver)
		_drivers[owner_id] = weakref(driver)
	if not _batches.has(k):
		var root := Node3D.new()
		root.name = "SpeciesBatch_%s" % k.replace("|", "_")
		parent.add_child(root)
		_batches[k] = VoxelBatch.new(root, VoxelMat.make_fauna_mm(), 64, true)
		_owners[k] = owner_id
	var batch: VoxelBatch = _batches[k] as VoxelBatch
	var h: VoxelBatch.Handle = batch.add(xform, color)
	# a = 0: iridescence comes from the builder's per-voxel value, not a
	# blanket 1.0 (which the shader reads as full iridescence).
	h.set_custom_data(Color(bone_index, 0.0, 0.0, 0.0))
	return h


static func track_sync(pivot: Node3D, local_xform: Transform3D, handle: VoxelBatch.Handle) -> void:
	_sync_slots.append({
		"pivot": pivot,
		"local": local_xform,
		"handle": handle,
	})


static func sync_all() -> void:
	if _sync_slots.is_empty():
		return
	_inverse_cache.clear()
	_pivot_cache.clear()
	var retained: int = 0
	for slot in _sync_slots:
		if not (slot is Dictionary):
			continue
		var pivot_v: Variant = (slot as Dictionary).get("pivot")
		var h_v: Variant = (slot as Dictionary).get("handle")
		if pivot_v == null or not is_instance_valid(pivot_v):
			if h_v is VoxelBatch.Handle:
				(h_v as VoxelBatch.Handle).hide()
			continue
		if h_v == null or not (h_v is VoxelBatch.Handle):
			continue
		var h: VoxelBatch.Handle = h_v as VoxelBatch.Handle
		if not h.alive:
			continue
		var pivot: Node3D = pivot_v as Node3D
		if pivot == null:
			continue
		var local_xf: Variant = (slot as Dictionary).get("local")
		if not (local_xf is Transform3D):
			continue
		if h.batch == null or not is_instance_valid(h.batch.mmi):
			continue
		var batch_root: Node3D = h.batch.mmi.get_parent() as Node3D
		var root_id: int = batch_root.get_instance_id()
		var pivot_id: int = pivot.get_instance_id()
		if not _inverse_cache.has(root_id):
			_inverse_cache[root_id] = batch_root.global_transform.affine_inverse()
		if not _pivot_cache.has(pivot_id):
			_pivot_cache[pivot_id] = pivot.global_transform
		h.set_transform((_inverse_cache[root_id] as Transform3D) \
			* (_pivot_cache[pivot_id] as Transform3D) * (local_xf as Transform3D))
		_sync_slots[retained] = slot
		retained += 1
	_sync_slots.resize(retained)
	flush_all()


static func flush_all() -> void:
	for b in _batches.values():
		if b is VoxelBatch:
			var vb: VoxelBatch = b as VoxelBatch
			vb.flush()
			vb.blit_buffer()


static func batches_for(species: String, subspecies: String = "") -> Array:
	var suffix: String = "|" + _key(species, subspecies)
	var result: Array = []
	for k in _batches:
		if String(k).ends_with(suffix):
			result.append(_batches[k])
	return result


static func sync_render_frame() -> void:
	var frame: int = Engine.get_process_frames()
	if frame == _render_frame:
		return
	_render_frame = frame
	sync_all()


static func release_parent(owner_id: int) -> void:
	for k in _owners.keys():
		if int(_owners[k]) == owner_id:
			(_batches[k] as VoxelBatch).dispose()
			_batches.erase(k)
			_owners.erase(k)
	_drivers.erase(owner_id)
	# Releasing a batch invalidates its handles; drop those retained slots.
	var kept: Array = []
	for slot in _sync_slots:
		var handle: VoxelBatch.Handle = slot.get("handle") as VoxelBatch.Handle
		if handle != null and handle.alive and handle.batch != null:
			kept.append(slot)
	_sync_slots = kept


static func batch_count() -> int:
	return _batches.size()
