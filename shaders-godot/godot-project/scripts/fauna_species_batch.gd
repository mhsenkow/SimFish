extends RefCounted

# PERFORMANCE_UNTHROTTLED #69 — one MultiMesh draw per species family.
# No class_name — callers preload this script and invoke static methods on the
# const (see sim_driver.gd). Global class_name + static calls hit Godot parse
# limits when the registry lags behind reload.
#
# GPU bone palette (CROWDED_FISH "next architectural work" item 3): with
# _gpu_skin on (default), voxel instances are written ONCE in bone-local space
# and animation becomes one 3x4 matrix per moving bone per frame, uploaded as
# a small RGBAF texture the skinned shader composes in its vertex stage
# (voxel_fauna_skinned.gdshader). The legacy per-voxel CPU path is kept behind
# the flag as the rollback and the equivalence baseline: it wrote
# bone_transform * local into every voxel instance every rendered frame —
# ~9,600 Transform3D multiplies + server calls per frame at 197 fish.

static var _batches: Dictionary = {}
static var _sync_groups: Dictionary = {}
static var _active: bool = false
static var _drivers: Dictionary = {}
static var _owners: Dictionary = {}
static var _render_frame: int = -1
static var _inverse_cache: Dictionary = {}
static var _untracked_counts: Dictionary = {}
static var _skins: Dictionary = {}
static var _gpu_skin: bool = true


# One bone-matrix texture per species batch. 3 texels per slot (one matrix
# row each), one texture row per slot. Slot 0 is pinned to identity so
# untracked static geometry (floor(custom.g) == 0) renders unmoved.
class SkinPalette extends RefCounted:
	const SLOT_FLOATS: int = 12
	var material: ShaderMaterial = null
	var image: Image = null
	var texture: ImageTexture = null
	var data := PackedFloat32Array()
	var capacity: int = 0
	var next_slot: int = 1
	var free_slots: Array[int] = []
	var dirty: bool = false

	func _init(mat: ShaderMaterial, initial_capacity: int = 64) -> void:
		material = mat
		_grow(initial_capacity)

	func alloc() -> int:
		if not free_slots.is_empty():
			return free_slots.pop_back()
		if next_slot >= capacity:
			_grow(capacity * 2)
		var s: int = next_slot
		next_slot += 1
		return s

	func release(slot: int) -> void:
		if slot > 0 and slot < next_slot:
			write(slot, Transform3D.IDENTITY)
			free_slots.append(slot)

	func write(slot: int, t: Transform3D) -> void:
		if not t.is_finite():
			t = Transform3D.IDENTITY
		var i: int = slot * SLOT_FLOATS
		var b: Basis = t.basis
		var o: Vector3 = t.origin
		data[i] = b.x.x; data[i + 1] = b.y.x; data[i + 2] = b.z.x; data[i + 3] = o.x
		data[i + 4] = b.x.y; data[i + 5] = b.y.y; data[i + 6] = b.z.y; data[i + 7] = o.y
		data[i + 8] = b.x.z; data[i + 9] = b.y.z; data[i + 10] = b.z.z; data[i + 11] = o.z
		dirty = true

	func bone_transform(slot: int) -> Transform3D:
		var i: int = slot * SLOT_FLOATS
		return Transform3D(
			Basis(Vector3(data[i], data[i + 4], data[i + 8]),
				Vector3(data[i + 1], data[i + 5], data[i + 9]),
				Vector3(data[i + 2], data[i + 6], data[i + 10])),
			Vector3(data[i + 3], data[i + 7], data[i + 11]))

	func commit() -> void:
		if not dirty or image == null or texture == null:
			return
		dirty = false
		image.set_data(3, capacity, false, Image.FORMAT_RGBAF, data.to_byte_array())
		texture.update(image)

	func _grow(new_capacity: int) -> void:
		var old: int = capacity
		capacity = maxi(new_capacity, 64)
		data.resize(capacity * SLOT_FLOATS)
		for s in range(old, capacity):
			var i: int = s * SLOT_FLOATS
			data[i] = 1.0; data[i + 1] = 0.0; data[i + 2] = 0.0; data[i + 3] = 0.0
			data[i + 4] = 0.0; data[i + 5] = 1.0; data[i + 6] = 0.0; data[i + 7] = 0.0
			data[i + 8] = 0.0; data[i + 9] = 0.0; data[i + 10] = 1.0; data[i + 11] = 0.0
		# Growing re-creates the texture; ImageTexture.update needs a stable size.
		image = Image.create_from_data(3, capacity, false, Image.FORMAT_RGBAF,
			data.to_byte_array())
		texture = ImageTexture.create_from_image(image)
		if material != null and is_instance_valid(material):
			material.set_shader_parameter("fauna_bone_tex", texture)
		dirty = false


# Resolve shared transforms once per moving bone rather than once per voxel.
class SyncGroup extends RefCounted:
	var pivot: Node3D
	var batch_root: Node3D
	var batch: VoxelBatch = null
	var skin: SkinPalette = null
	var bone_slot: int = -1
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
	_skins.clear()
	_owners.clear()
	for ref in _drivers.values():
		var driver: Node = (ref as WeakRef).get_ref() as Node
		if is_instance_valid(driver):
			driver.queue_free()
	_drivers.clear()
	_render_frame = -1
	_active = false
	_gpu_skin = true


static func set_active(on: bool) -> void:
	# Admission changes affect future geometry; existing fish still animate.
	_active = on


static func active() -> bool:
	return _active


# Rollback / A-B switch for the GPU bone palette. Affects batches created
# after the change; existing batches keep the mode they were built with.
static func set_gpu_skin_enabled(on: bool) -> void:
	_gpu_skin = on


static func gpu_skin_enabled() -> bool:
	return _gpu_skin


static func should_enable(fish_count: int) -> bool:
	return fish_count >= MIN_FISH_FOR_BATCH


static func sync_slot_count() -> int:
	var count: int = 0
	for group: SyncGroup in _sync_groups.values():
		count += group.handles.size()
	return count


static func skin_for_batch(batch: VoxelBatch) -> SkinPalette:
	return _skins.get(batch) as SkinPalette


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
		var mat: ShaderMaterial = VoxelMat.make_fauna_skinned() if _gpu_skin \
			else VoxelMat.make_fauna_mm()
		var new_batch := VoxelBatch.new(root, mat, 64, true, true)
		_batches[k] = new_batch
		_owners[k] = owner_id
		if _gpu_skin:
			_skins[new_batch] = SkinPalette.new(mat)
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
		new_group.batch = handle.batch
		var skin: SkinPalette = _skins.get(handle.batch) as SkinPalette
		if skin != null:
			new_group.skin = skin
			new_group.bone_slot = skin.alloc()
		_sync_groups[key] = new_group
	var group: SyncGroup = _sync_groups[key]
	group.handles.append(handle)
	group.locals.append(local_xform)
	if group.skin != null:
		# GPU skinning: the instance stays STATIC in bone-local space; the
		# bone palette row moves it. Stamp the slot into floor(custom.g) —
		# fract(g) stays the belly flash (fish.gd preserves the floor).
		handle.set_transform(local_xform)
		var c: Color = handle.custom_data
		handle.set_custom_data(Color(c.r, float(group.bone_slot) + (c.g - floorf(c.g)),
			c.b, c.a))
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
			_release_group_slot(group)
			_sync_groups.erase(key)
			continue
		var root_id: int = group.batch_root.get_instance_id()
		if not _inverse_cache.has(root_id):
			var root_g: Transform3D = group.batch_root.global_transform
			if not root_g.is_finite() or absf(root_g.basis.determinant()) < 1e-8:
				bounds_fallback[group.batch] = true
				continue
			_inverse_cache[root_id] = root_g.affine_inverse()
		var root_inv: Transform3D = _inverse_cache[root_id] as Transform3D
		var pivot_global: Transform3D = group.pivot.global_transform
		if not pivot_global.is_finite() or not root_inv.is_finite():
			# Keep last good bone / voxel transforms; don't push NaN into the
			# MultiMesh buffer or the GPU bone palette.
			bounds_fallback[group.batch] = true
			continue
		var bone_transform: Transform3D = root_inv * pivot_global
		if not bone_transform.is_finite():
			bounds_fallback[group.batch] = true
			continue
		var batch: VoxelBatch = null
		if group.skin != null:
			# One palette row per bone per frame. The shader composes
			# (pivot_global * root_inv) * (root_global * local), which is the
			# exact world transform the legacy path wrote per voxel.
			var skin_xform: Transform3D = pivot_global * root_inv
			if skin_xform.is_finite():
				group.skin.write(group.bone_slot, skin_xform)
			batch = group.batch
			if batch == null or not is_instance_valid(batch.mmi):
				continue
		else:
			var retained: int = 0
			for i in group.handles.size():
				var handle: VoxelBatch.Handle = group.handles[i]
				if not handle.alive or handle.batch == null or not is_instance_valid(handle.batch.mmi):
					continue
				var composed: Transform3D = bone_transform * group.locals[i]
				if composed.is_finite():
					handle.set_transform(composed)
				group.handles[retained] = handle
				group.locals[retained] = group.locals[i]
				retained += 1
			group.handles.resize(retained)
			group.locals.resize(retained)
			if retained == 0:
				_sync_groups.erase(key)
				continue
			batch = group.handles[0].batch
		if group.has_bounds and bone_transform.is_finite():
			var bounds: AABB = bone_transform * group.local_bounds
			bounds_by_batch[batch] = (bounds_by_batch[batch] as AABB).merge(bounds) \
				if bounds_by_batch.has(batch) else bounds
		else:
			# Invalid poses leave the last finite GPU transforms in place.
			# Their actual bounds must remain included until motion recovers.
			bounds_fallback[batch] = true
	for batch: VoxelBatch in bounds_by_batch:
		if bounds_fallback.has(batch):
			continue
		var untracked: int = int(_untracked_counts.get(batch, 0))
		if untracked == 0:
			batch.set_conservative_bounds(bounds_by_batch[batch])
		elif _skins.has(batch):
			# Skinned mirrors are bone-local, so the exact per-voxel fallback
			# would under-cover moving bones. Group bounds cover every tracked
			# voxel; merging the mirror scan keeps the untracked statics in.
			batch.set_conservative_bounds(bounds_by_batch[batch], true)
	for skin: SkinPalette in _skins.values():
		skin.commit()
	flush_all()


static func _release_group_slot(group: SyncGroup) -> void:
	if group.skin != null and group.bone_slot >= 0:
		group.skin.release(group.bone_slot)
		group.bone_slot = -1


# Skinned groups skip the per-frame handle walk, so dead-handle bookkeeping
# (slot + group reclamation) runs at maintenance cadence instead. Dead voxels
# are already invisible the moment they retire — hide() zero-scales the
# static instance — this only reclaims the bone slot and the group entry.
static func _prune_dead_groups() -> void:
	for key: String in _sync_groups.keys():
		var group: SyncGroup = _sync_groups[key]
		if group.skin == null:
			continue
		var retained: int = 0
		for i in group.handles.size():
			var handle: VoxelBatch.Handle = group.handles[i]
			if not handle.alive or handle.batch == null or not is_instance_valid(handle.batch.mmi):
				continue
			group.handles[retained] = handle
			group.locals[retained] = group.locals[i]
			retained += 1
		group.handles.resize(retained)
		group.locals.resize(retained)
		if retained == 0:
			_release_group_slot(group)
			_sync_groups.erase(key)


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
	_prune_dead_groups()
	for k in _owners:
		if int(_owners[k]) == owner_id:
			var batch: VoxelBatch = _batches[k]
			if int(_untracked_counts.get(batch, 0)) == 0:
				batch.consider_compaction(dt)


static func release_parent(owner_id: int) -> void:
	for k in _owners.keys():
		if int(_owners[k]) == owner_id:
			_untracked_counts.erase(_batches[k])
			_skins.erase(_batches[k])
			(_batches[k] as VoxelBatch).dispose()
			_batches.erase(k)
			_owners.erase(k)
	_drivers.erase(owner_id)
	# Releasing a batch invalidates its handles and its bone groups.
	for key: String in _sync_groups.keys():
		var group: SyncGroup = _sync_groups[key]
		if not is_instance_valid(group.batch_root) or group.handles.is_empty() \
				or group.handles[0].batch == null:
			_release_group_slot(group)
			_sync_groups.erase(key)


static func batch_count() -> int:
	return _batches.size()
