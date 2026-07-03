# Batches fauna voxels into per-pivot MultiMesh draw calls (same pattern as plants).
#
# class_name intentionally omitted — fish.gd / shrimp.gd preload this via
# `const FaunaVoxelBuilder = preload(...)` and use the const as a type
# annotation. Keeping a class_name on top of that fires SHADOWED_GLOBAL_IDENTIFIER
# warnings on every reload. The const itself is a valid type in Godot 4
# variable annotations, so removing class_name doesn't break anything.
extends RefCounted

const _FaunaSpeciesBatchScript = preload("res://scripts/fauna_species_batch.gd")

var _batches: Dictionary = {}
var _pivot_seq: Dictionary = {}
var handles: Array = []
var _species_batch: bool = false
var _world_parent: Node3D = null
var _species: String = ""
var _subspecies: String = ""


func enable_species_batch(world_parent: Node3D, species: String, subspecies: String = "") -> void:
	_species_batch = true
	_world_parent = world_parent
	_species = species
	_subspecies = subspecies


func add_voxel(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	if parent == null:
		return
	if not pos.is_finite() or not size.is_finite():
		push_warning("FaunaVoxelBuilder.add_voxel: non-finite pos=%s or size=%s on %s, skipping voxel." \
			% [pos, size, String(parent.name) if parent != null else "?"])
		return
	var albedo: Color = VoxelMat.fauna_color_from_material(mat)
	var bend_w: float = _bone_bend_weight(parent)
	var inst_custom: Color = Color(bend_w, 0.0, 0.0, 1.0)
	if mat is ShaderMaterial:
		var irid_v: Variant = (mat as ShaderMaterial).get_shader_parameter("irid_strength")
		if irid_v != null:
			inst_custom.g = clampf(float(irid_v), 0.0, 1.0)
	var xform := Transform3D(Basis.from_scale(size), pos)
	if _species_batch and _world_parent != null and _species != "" \
			and _FaunaSpeciesBatchScript.active():
		var h: VoxelBatch.Handle = _FaunaSpeciesBatchScript.register_instance(
			_world_parent, _species, Transform3D.IDENTITY, albedo, inst_custom.r, _subspecies)
		if h != null:
			if inst_custom.g > 0.001:
				h.set_meta("fauna_custom_a", inst_custom.g)
				h.set_custom_data(inst_custom)
			h.set_meta("orig_color", albedo)
			_FaunaSpeciesBatchScript.track_sync(parent, xform, h)
			handles.append(h)
		return
	var key: String = str(parent.get_instance_id())
	if not _batches.has(key):
		_batches[key] = VoxelBatch.new(parent, VoxelMat.make_fauna_mm(), 24, true)
		_pivot_seq[key] = 0
	var batch: VoxelBatch = _batches[key]
	var h2: VoxelBatch.Handle = batch.add(xform, albedo)
	if inst_custom.g > 0.001 or inst_custom.r > 0.001:
		h2.set_meta("fauna_custom_a", inst_custom.g)
		h2.set_custom_data(inst_custom)
	h2.set_meta("orig_color", albedo)
	handles.append(h2)


func flush_all() -> void:
	if _species_batch and _FaunaSpeciesBatchScript.active():
		_FaunaSpeciesBatchScript.sync_all()
		return
	for batch: VoxelBatch in _batches.values():
		batch.flush()
		batch.blit_buffer()


func get_batches() -> Array:
	if _species_batch and _FaunaSpeciesBatchScript.active():
		return _FaunaSpeciesBatchScript.batches_for(_species, _subspecies)
	return _batches.values()


static func handle_orig_color(h: VoxelBatch.Handle) -> Color:
	if h == null:
		return Color.WHITE
	if h.has_meta("orig_color"):
		return h.get_meta("orig_color")
	return h.base_color


static func _bone_bend_weight(parent: Node3D) -> float:
	if parent == null:
		return 0.2
	match String(parent.name):
		"Head":
			return 0.08
		"BodyMid":
			return 0.42
		"TailPivot", "Tail":
			return 1.0
		"GillPivot", "PectoralL", "PectoralR", "Dorsal", "Anal":
			return 0.72
		_:
			return 0.22
