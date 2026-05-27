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


static var _sub_opaque_shader: Shader = null
const SUB_OPAQUE_SHADER_PATH := "res://shaders/substrate_opaque.gdshader"

static func _get_sub_opaque_shader() -> Shader:
	if _sub_opaque_shader == null:
		_sub_opaque_shader = load(SUB_OPAQUE_SHADER_PATH) as Shader
	return _sub_opaque_shader

static var _sub_opaque_mat_cache: Dictionary = {}

static func make_substrate_opaque(color: Color) -> ShaderMaterial:
	var cache_key: Color = Color(snappedf(color.r, 0.01), snappedf(color.g, 0.01), snappedf(color.b, 0.01))
	if _sub_opaque_mat_cache.has(cache_key):
		return _sub_opaque_mat_cache[cache_key]
		
	var m := ShaderMaterial.new()
	m.shader = _get_sub_opaque_shader()
	m.set_shader_parameter("albedo", color)
	_sub_opaque_mat_cache[cache_key] = m
	return m


static var _sub_caustic_shader: Shader = null
const SUB_CAUSTIC_SHADER_PATH := "res://shaders/substrate_caustic.gdshader"

static func _get_sub_caustic_shader() -> Shader:
	if _sub_caustic_shader == null:
		_sub_caustic_shader = load(SUB_CAUSTIC_SHADER_PATH) as Shader
	return _sub_caustic_shader

static var _sub_caustic_mat_cache: Dictionary = {}

static func make_substrate_caustic(color: Color) -> ShaderMaterial:
	var cache_key: Color = Color(snappedf(color.r, 0.01), snappedf(color.g, 0.01), snappedf(color.b, 0.01))
	if _sub_caustic_mat_cache.has(cache_key):
		return _sub_caustic_mat_cache[cache_key]
		
	var m := ShaderMaterial.new()
	m.shader = _get_sub_caustic_shader()
	m.set_shader_parameter("albedo", color)
	_sub_caustic_mat_cache[cache_key] = m
	return m

static var _foliage_shader: Shader = null
const FOLIAGE_SHADER_PATH := "res://shaders/foliage.gdshader"

static func _get_foliage_shader() -> Shader:
	if _foliage_shader == null:
		_foliage_shader = load(FOLIAGE_SHADER_PATH) as Shader
	return _foliage_shader

static var _foliage_mat_cache: Dictionary = {}

static func make_foliage(color: Color) -> ShaderMaterial:
	var cache_key: Color = Color(snappedf(color.r, 0.01), snappedf(color.g, 0.01), snappedf(color.b, 0.01))
	if _foliage_mat_cache.has(cache_key):
		return _foliage_mat_cache[cache_key]
		
	var m := ShaderMaterial.new()
	m.shader = _get_foliage_shader()
	m.set_shader_parameter("albedo", color)
	_foliage_mat_cache[cache_key] = m
	return m


static func update_caustic_uniforms(intensity: float, color: Color) -> void:
	for mat in _sub_caustic_mat_cache.values():
		if is_instance_valid(mat):
			mat.set_shader_parameter("caustic_intensity", intensity)
			mat.set_shader_parameter("light_color", color)



