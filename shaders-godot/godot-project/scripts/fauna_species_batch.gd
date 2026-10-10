extends RefCounted

# PERFORMANCE_UNTHROTTLED #69 — one MultiMesh draw per species family.
# No class_name — callers preload this script and invoke static methods on the
# const (see sim_driver.gd). Global class_name + static calls hit Godot parse
# limits when the registry lags behind reload.

static var _batches: Dictionary = {}
static var _sync_groups: Dictionary = {}
static var _active: bool = false
static var _drivers: Dictionary = {}
static var _owners: Dictionary = {}
static var _render_frame: int = -1
static var _inverse_cache: Dictionary = {}
static var _untracked_counts: Dictionary = {}
# Resolve shared transforms once per moving bone rather than once per voxel.
class SyncGroup extends RefCounted:
	var pivot: Node3D
	var batch_root: Node3D
	var handles: Array[VoxelBatch.Handle] = []
	var locals: Array[Transform3D] = []
	var local_bounds: AABB
	var has_bounds: bool = false

# Upload after fish have animated their pivots, rather than at the 10 Hz
# simulation cadence. A driver belongs to the same scene as its geometry.
class RenderSync extends Node:
	var sync: Callable
	var release: Callable
	var maintain: Callable
	var maintenance_s: float = 0.0
	func _process(dt: float) -> void:
		sync.call()
		maintenance_s += dt
		if maintenance_s >= 1.0:
			maintain.call(maintenance_s)
			maintenance_s = 0.0
	func _exit_tree() -> void:
		release.call()

const MIN_FISH_FOR_BATCH: int = 36


static func reset_for_test() -> void:
	for b in _batches.values():
		if b is VoxelBatch:
			(b as VoxelBatch).queue_free()
	_batches.clear()
	_sync_groups.clear()
	_untracked_counts.clear()
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
	var count: int = 0
	for group: SyncGroup in _sync_groups.values():
		count += group.handles.size()
	return count


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
		driver.maintain = maintain_parent.bind(owner_id)
		parent.add_child(driver)
		_drivers[owner_id] = weakref(driver)
	if not _batches.has(k):
		var root := Node3D.new()
		root.name = "SpeciesBatch_%s" % k.replace("|", "_")
		parent.add_child(root)
		_batches[k] = VoxelBatch.new(root, VoxelMat.make_fauna_mm(), 64, true, true)
		_owners[k] = owner_id
	var batch: VoxelBatch = _batches[k] as VoxelBatch
	var h: VoxelBatch.Handle = batch.add(xform, color)
	_untracked_counts[batch] = int(_untracked_counts.get(batch, 0)) + 1
	# a = 0: iridescence comes from the builder's per-voxel value, not a
	# blanket 1.0 (which the shader reads as full iridescence).
	h.set_custom_data(Color(bone_index, 0.0, 0.0, 0.0))
	return h


static func track_sync(pivot: Node3D, local_xform: Transform3D, handle: VoxelBatch.Handle) -> void:
	if pivot == null or handle == null or handle.batch == null:
		return
	var batch_root: Node3D = handle.batch.mmi.get_parent() as Node3D
	var key: String = "%d|%d" % [pivot.get_instance_id(), batch_root.get_instance_id()]
	if not _sync_groups.has(key):
		var new_group := SyncGroup.new()
		new_group.pivot = pivot
		new_group.batch_root = batch_root
		_sync_groups[key] = new_group
	var group: SyncGroup = _sync_groups[key]
	group.handles.append(handle)
	group.locals.append(local_xform)
	if not handle.has_meta("fauna_tracked"):
		handle.set_meta("fauna_tracked", true)
		_untracked_counts[handle.batch] = int(_untracked_counts.get(handle.batch, 0)) - 1
	if local_xform.is_finite():
		var box: AABB = local_xform * AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
		group.local_bounds = group.local_bounds.merge(box) if group.has_bounds else box
		group.has_bounds = true


static func sync_all() -> void:
	if _sync_groups.is_empty():
		return
	_inverse_cache.clear()
	var bounds_by_batch: Dictionary = {}
	var bounds_fallback: Dictionary = {}
	for key: String in _sync_groups.keys():
		var group: SyncGroup = _sync_groups[key]
		if not is_instance_valid(group.pivot) or not is_instance_valid(group.batch_root):
			for handle: VoxelBatch.Handle in group.handles:
				handle.hide()
			_sync_groups.erase(key)
			continue
		var root_id: int = group.batch_root.get_instance_id()
		if not _inverse_cache.has(root_id):
			_inverse_cache[root_id] = group.batch_root.global_transform.affine_inverse()
		var bone_transform: Transform3D = (_inverse_cache[root_id] as Transform3D) \
			* group.pivot.global_transform
		var retained: int = 0
		for i in group.handles.size():
			var handle: VoxelBatch.Handle = group.handles[i]
			if not handle.alive or handle.batch == null or not is_instance_valid(handle.batch.mmi):
				continue
			handle.set_transform(bone_transform * group.locals[i])
			group.handles[retained] = handle
			group.locals[retained] = group.locals[i]
			retained += 1
		group.handles.resize(retained)
		group.locals.resize(retained)
		if retained == 0:
			_sync_groups.erase(key)
		else:
			var batch: VoxelBatch = group.handles[0].batch
			if group.has_bounds and bone_transform.is_finite():
				var bounds: AABB = bone_transform * group.local_bounds
				bounds_by_batch[batch] = (bounds_by_batch[batch] as AABB).merge(bounds) \
					if bounds_by_batch.has(batch) else bounds
			else:
				# Invalid poses leave the last finite GPU transforms in place.
				# Their actual bounds must remain included until motion recovers.
				bounds_fallback[batch] = true
	for batch: VoxelBatch in bounds_by_batch:
		if int(_untracked_counts.get(batch, 0)) == 0 and not bounds_fallback.has(batch):
			batch.set_conservative_bounds(bounds_by_batch[batch])
	flush_all()


static func flush_all() -> void:
	for b in _batches.values():
		if b is VoxelBatch:
			var vb: VoxelBatch = b as VoxelBatch
			vb.flush()


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


static func maintain_parent(dt: float, owner_id: int) -> void:
	# Coarse maintenance also releases historical population peaks. Never scan
	# every weak voxel handle at render cadence or affect another tank's clock.
	for k in _owners:
		if int(_owners[k]) == owner_id:
			var batch: VoxelBatch = _batches[k]
			if int(_untracked_counts.get(batch, 0)) == 0:
				batch.consider_compaction(dt)


static func release_parent(owner_id: int) -> void:
	for k in _owners.keys():
		if int(_owners[k]) == owner_id:
			_untracked_counts.erase(_batches[k])
			(_batches[k] as VoxelBatch).dispose()
			_batches.erase(k)
			_owners.erase(k)
	_drivers.erase(owner_id)
	# Releasing a batch invalidates its handles and its bone groups.
	for key: String in _sync_groups.keys():
		var group: SyncGroup = _sync_groups[key]
		if not is_instance_valid(group.batch_root) or group.handles.is_empty() \
				or group.handles[0].batch == null:
			_sync_groups.erase(key)


static func batch_count() -> int:
	return _batches.size()
