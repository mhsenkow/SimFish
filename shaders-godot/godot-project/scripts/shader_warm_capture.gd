class_name ShaderWarmCapture
extends RefCounted

# PERFORMANCE_UNTHROTTLED #87 — session shader warm list.

const _VoxelMat = preload("res://scripts/voxel_mat.gd")


static var _keys: PackedStringArray = PackedStringArray()


static func reset_for_test() -> void:
	_keys = PackedStringArray()


static func record(label: String) -> void:
	if label == "" or _keys.has(label):
		return
	_keys.append(label)


static func snapshot() -> PackedStringArray:
	return _keys.duplicate()


static func count() -> int:
	return _keys.size()


static func replay_warm() -> int:
	var n: int = 0
	for label in _keys:
		match label:
			"voxel":
				_VoxelMat.make(Color8(100, 120, 90))
			"fauna":
				_VoxelMat.make_fauna(Color(0.55, 0.42, 0.32))
			"fauna_mm":
				_VoxelMat.make_fauna_mm()
			"substrate_caustic":
				_VoxelMat.make_substrate_caustic(Color8(92, 72, 52))
			"water":
				_VoxelMat.make_water(Color(0.22, 0.52, 0.62), Color(0.06, 0.16, 0.28), 0.0, 12.0)
			_:
				if label.begins_with("shader_perf_tier_"):
					var tier: int = int(label.get_slice("_", 2))
					_VoxelMat.set_shader_perf_tier(tier)
		n += 1
	return n
