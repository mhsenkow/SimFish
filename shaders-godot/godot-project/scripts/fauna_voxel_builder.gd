# Batches fauna voxels into per-pivot MultiMesh draw calls (same pattern as plants).
class_name FaunaVoxelBuilder
extends RefCounted

var _batches: Dictionary = {}
var handles: Array = []


func add_voxel(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	if parent == null:
		return
	var key: String = "%d_%d" % [parent.get_instance_id(), mat.get_instance_id()]
	if not _batches.has(key):
		_batches[key] = VoxelBatch.new(parent, mat, 24)
	var batch: VoxelBatch = _batches[key]
	var albedo: Color = Color.WHITE
	if mat is ShaderMaterial:
		albedo = mat.get_shader_parameter("albedo")
	var xform := Transform3D(Basis.from_scale(size), pos)
	var h: VoxelBatch.Handle = batch.add(xform, albedo)
	h.set_meta("orig_color", albedo)
	handles.append(h)


func flush_all() -> void:
	for batch: VoxelBatch in _batches.values():
		batch.flush()


func get_batches() -> Array:
	return _batches.values()


static func handle_orig_color(h: VoxelBatch.Handle) -> Color:
	if h == null:
		return Color.WHITE
	if h.has_meta("orig_color"):
		return h.get_meta("orig_color")
	return h.base_color
