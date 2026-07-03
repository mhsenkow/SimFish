class_name HardscapeBatch
extends RefCounted

# PERFORMANCE_UNTHROTTLED #79 — merge static hardscape pebbles into per-material MultiMesh.


var _buckets: Dictionary = {}  # mat_id -> VoxelBatch


func add(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	if parent == null or mat == null:
		return
	var key: int = mat.get_instance_id()
	if not _buckets.has(key):
		var holder := Node3D.new()
		holder.name = "HardscapeBatch_%d" % key
		parent.add_child(holder)
		_buckets[key] = VoxelBatch.new(holder, mat, 32, false)
	var batch: VoxelBatch = _buckets[key] as VoxelBatch
	batch.add(Transform3D(Basis.from_scale(size), pos), Color.WHITE)


func flush() -> void:
	for batch in _buckets.values():
		if batch is VoxelBatch:
			var vb: VoxelBatch = batch as VoxelBatch
			vb.flush()
			vb.blit_buffer()


func draw_calls() -> int:
	return _buckets.size()
