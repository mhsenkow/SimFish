extends RefCounted

# PERFORMANCE_UNTHROTTLED #69 — one MultiMesh draw per species family.
# No class_name — callers preload this script and invoke static methods on the
# const (see sim_driver.gd). Global class_name + static calls hit Godot parse
# limits when the registry lags behind reload.

static var _batches: Dictionary = {}
static var _sync_slots: Array = []
static var _active: bool = false
const MIN_FISH_FOR_BATCH: int = 36


static func reset_for_test() -> void:
	for b in _batches.values():
		if b is VoxelBatch:
			(b as VoxelBatch).queue_free()
	_batches.clear()
	_sync_slots.clear()
	_active = false


static func set_active(on: bool) -> void:
	_active = on
	if not on:
		_sync_slots.clear()


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
	var k: String = _key(species, subspecies)
	if not _batches.has(k):
		var root := Node3D.new()
		root.name = "SpeciesBatch_%s" % k.replace("|", "_")
		parent.add_child(root)
		_batches[k] = VoxelBatch.new(root, VoxelMat.make_fauna_mm(), 64, true)
	var batch: VoxelBatch = _batches[k] as VoxelBatch
	var h: VoxelBatch.Handle = batch.add(xform, color)
	h.set_custom_data(Color(bone_index, 0.0, 0.0, 1.0))
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
	var alive: Array = []
	for slot in _sync_slots:
		if not (slot is Dictionary):
			continue
		var pivot_v: Variant = (slot as Dictionary).get("pivot")
		var h_v: Variant = (slot as Dictionary).get("handle")
		if pivot_v == null or not is_instance_valid(pivot_v):
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
		h.set_transform(pivot.global_transform * (local_xf as Transform3D))
		alive.append(slot)
	_sync_slots = alive
	flush_all()


static func flush_all() -> void:
	for b in _batches.values():
		if b is VoxelBatch:
			var vb: VoxelBatch = b as VoxelBatch
			vb.flush()
			vb.blit_buffer()


static func batches_for(species: String, subspecies: String = "") -> Array:
	var k: String = _key(species, subspecies)
	if _batches.has(k):
		return [_batches[k]]
	return []


static func batch_count() -> int:
	return _batches.size()
