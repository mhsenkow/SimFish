# Voxel material factory.
#
# Caches the compiled voxel.gdshader once and produces a fresh ShaderMaterial
# per call with the requested albedo. The shader is unshaded + face-based, so
# each cube reads as a 3D object without needing a directional light.

extends RefCounted
class_name VoxelMat

const SHADER_PATH := "res://shaders/voxel.gdshader"
static var _shader: Shader = null


static func _get_shader() -> Shader:
	if _shader == null:
		_shader = load(SHADER_PATH) as Shader
	return _shader


static var _mat_cache: Dictionary = {}
static var _mesh_cache: Dictionary = {}

static func get_box(size: Vector3) -> BoxMesh:
	var key: Vector3 = Vector3(snappedf(size.x, 0.01), snappedf(size.y, 0.01), snappedf(size.z, 0.01))
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var bm := BoxMesh.new()
	bm.size = size
	_mesh_cache[key] = bm
	return bm


static func make(color: Color) -> ShaderMaterial:
	# Round color slightly to ensure caching of nearly-identical procedural colors.
	var cache_key: Color = Color(snappedf(color.r, 0.01), snappedf(color.g, 0.01), snappedf(color.b, 0.01))
	if _mat_cache.has(cache_key):
		return _mat_cache[cache_key]
		
	var m := ShaderMaterial.new()
	m.shader = _get_shader()
	m.set_shader_parameter("albedo", color)
	_mat_cache[cache_key] = m
	return m
