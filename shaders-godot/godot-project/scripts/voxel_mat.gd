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
static var _fauna_mat_cache: Dictionary = {}
static var _mesh_cache: Dictionary = {}

const FAUNA_SATURATION: float = 1.30
const FAUNA_VALUE: float = 1.12
const FAUNA_LIGHTEN: float = 0.05


static func boost_life_color(color: Color) -> Color:
	if color.a < 0.04:
		return color
	var h: float = color.h
	var s: float = clampf(color.s * FAUNA_SATURATION, 0.0, 1.0)
	var v: float = clampf(color.v * FAUNA_VALUE + FAUNA_LIGHTEN, 0.0, 1.0)
	return Color.from_hsv(h, s, v, color.a)


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


static func make_fauna(color: Color) -> ShaderMaterial:
	var boosted: Color = boost_life_color(color)
	var cache_key: Color = Color(
		snappedf(boosted.r, 0.01), snappedf(boosted.g, 0.01), snappedf(boosted.b, 0.01))
	if _fauna_mat_cache.has(cache_key):
		return _fauna_mat_cache[cache_key]
	var m: ShaderMaterial = make(boosted).duplicate()
	m.set_shader_parameter("color_vibrancy", 1.20)
	_fauna_mat_cache[cache_key] = m
	return m


static var _sub_opaque_shader: Shader = null
const SUB_OPAQUE_SHADER_PATH := "res://shaders/substrate_opaque.gdshader"

static func _get_sub_opaque_shader() -> Shader:
	if _sub_opaque_shader == null:
		_sub_opaque_shader = load(SUB_OPAQUE_SHADER_PATH) as Shader
	return _sub_opaque_shader

static var _sub_opaque_mat_cache: Dictionary = {}

static func make_substrate_opaque(color: Color, material_id: int = 0) -> ShaderMaterial:
	var cache_key: String = "%d_%s" % [material_id, str(snappedf(color.r, 0.02))]
	if _sub_opaque_mat_cache.has(cache_key):
		return _sub_opaque_mat_cache[cache_key]
	var m := ShaderMaterial.new()
	m.shader = _get_sub_opaque_shader()
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("material_id", material_id)
	_sub_opaque_mat_cache[cache_key] = m
	return m


static var _sub_caustic_shader: Shader = null
const SUB_CAUSTIC_SHADER_PATH := "res://shaders/substrate_caustic.gdshader"

static func _get_sub_caustic_shader() -> Shader:
	if _sub_caustic_shader == null:
		_sub_caustic_shader = load(SUB_CAUSTIC_SHADER_PATH) as Shader
	return _sub_caustic_shader

static var _sub_caustic_mat_cache: Dictionary = {}

static func make_substrate_caustic(color: Color, material_id: int = 0) -> ShaderMaterial:
	var cache_key: String = "%d_%s" % [material_id, str(snappedf(color.r, 0.02))]
	if _sub_caustic_mat_cache.has(cache_key):
		return _sub_caustic_mat_cache[cache_key]
	var m := ShaderMaterial.new()
	m.shader = _get_sub_caustic_shader()
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("material_id", material_id)
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
	var boosted: Color = boost_life_color(color)
	var cache_key: Color = Color(
		snappedf(boosted.r, 0.01), snappedf(boosted.g, 0.01), snappedf(boosted.b, 0.01))
	if _foliage_mat_cache.has(cache_key):
		return _foliage_mat_cache[cache_key]
		
	var m := ShaderMaterial.new()
	m.shader = _get_foliage_shader()
	m.set_shader_parameter("albedo", boosted)
	m.set_shader_parameter("color_vibrancy", 1.16)
	_foliage_mat_cache[cache_key] = m
	return m


static func update_caustic_uniforms(intensity: float, color: Color) -> void:
	for mat in _sub_caustic_mat_cache.values():
		if is_instance_valid(mat):
			mat.set_shader_parameter("caustic_intensity", intensity)
			mat.set_shader_parameter("light_color", color)


static var _water_shader: Shader = null
const WATER_SHADER_PATH := "res://shaders/water.gdshader"

static func _get_water_shader() -> Shader:
	if _water_shader == null:
		_water_shader = load(WATER_SHADER_PATH) as Shader
	return _water_shader


static func make_water(shallow: Color, deep: Color, floor_y: float, surface_y: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _get_water_shader()
	m.set_shader_parameter("shallow_color", shallow)
	m.set_shader_parameter("deep_color", deep)
	m.set_shader_parameter("water_floor_y", floor_y)
	m.set_shader_parameter("water_surface_y", surface_y)
	return m


static var _bubble_shader: Shader = null
const BUBBLE_SHADER_PATH := "res://shaders/bubble.gdshader"
static var _bubble_mat: ShaderMaterial = null

static func _get_bubble_shader() -> Shader:
	if _bubble_shader == null:
		_bubble_shader = load(BUBBLE_SHADER_PATH) as Shader
	return _bubble_shader


static func make_bubble(color: Color = Color(0.78, 0.92, 0.96, 0.42)) -> ShaderMaterial:
	if _bubble_mat != null:
		return _bubble_mat
	_bubble_mat = ShaderMaterial.new()
	_bubble_mat.shader = _get_bubble_shader()
	_bubble_mat.set_shader_parameter("bubble_color", color)
	return _bubble_mat


static var _ripple_shader: Shader = null
const RIPPLE_SHADER_PATH := "res://shaders/surface_ripple.gdshader"
static var _ripple_mat: ShaderMaterial = null

static func _get_ripple_shader() -> Shader:
	if _ripple_shader == null:
		_ripple_shader = load(RIPPLE_SHADER_PATH) as Shader
	return _ripple_shader


static func make_surface_ripple(color: Color = Color(0.86, 0.92, 0.96, 0.55)) -> ShaderMaterial:
	if _ripple_mat != null:
		return _ripple_mat
	_ripple_mat = ShaderMaterial.new()
	_ripple_mat.shader = _get_ripple_shader()
	_ripple_mat.set_shader_parameter("ripple_color", color)
	return _ripple_mat


static var _glass_shader: Shader = null
const GLASS_SHADER_PATH := "res://shaders/glass.gdshader"
static var _glass_mat: ShaderMaterial = null

static func make_glass(shape_id: float, water_y: float) -> ShaderMaterial:
	if _glass_mat == null:
		_glass_shader = load(GLASS_SHADER_PATH) as Shader
		_glass_mat = ShaderMaterial.new()
		_glass_mat.shader = _glass_shader
	_glass_mat.set_shader_parameter("tank_shape_id", shape_id)
	_glass_mat.set_shader_parameter("water_surface_y", water_y)
	return _glass_mat


static var _trans_shader: Shader = null
static var _trans_cache: Dictionary = {}

static func make_translucent(color: Color) -> ShaderMaterial:
	var key: Color = Color(snappedf(color.r, 0.02), snappedf(color.g, 0.02), snappedf(color.b, 0.02), snappedf(color.a, 0.05))
	if _trans_cache.has(key):
		return _trans_cache[key]
	if _trans_shader == null:
		_trans_shader = load("res://shaders/voxel_translucent.gdshader") as Shader
	var m := ShaderMaterial.new()
	m.shader = _trans_shader
	m.set_shader_parameter("albedo", color)
	_trans_cache[key] = m
	return m


static var _stem_shader: Shader = null

static func make_stem(color: Color, daylight: float = 1.0) -> ShaderMaterial:
	if _stem_shader == null:
		_stem_shader = load("res://shaders/stem_subsurface.gdshader") as Shader
	var m := ShaderMaterial.new()
	m.shader = _stem_shader
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("daylight", daylight)
	return m


static func get_bubble_material() -> ShaderMaterial:
	return make_bubble()


static func update_aquatic_uniforms(intensity: float, light_color: Color, water_y: float,
		day_offset: float, shimmer: float) -> void:
	for mat in _mat_cache.values():
		if is_instance_valid(mat):
			mat.set_shader_parameter("aquatic_caustic_intensity", intensity)
			mat.set_shader_parameter("aquatic_light_color", light_color)
			mat.set_shader_parameter("water_surface_y", water_y)
			mat.set_shader_parameter("day_phase_offset", day_offset)
			mat.set_shader_parameter("aquatic_shimmer", shimmer)
	for mat in _fauna_mat_cache.values():
		if is_instance_valid(mat):
			mat.set_shader_parameter("aquatic_caustic_intensity", intensity)
			mat.set_shader_parameter("aquatic_light_color", light_color)
			mat.set_shader_parameter("water_surface_y", water_y)
			mat.set_shader_parameter("day_phase_offset", day_offset)
			mat.set_shader_parameter("aquatic_shimmer", shimmer)


static var _foliage_mm_mats: Array = []

static func register_foliage_mm(mat: ShaderMaterial) -> void:
	if mat != null and not _foliage_mm_mats.has(mat):
		_foliage_mm_mats.append(mat)


static func update_foliage_uniforms(canopy_shade: float, water_y: float, daylight: float) -> void:
	for mat in _foliage_mm_mats:
		if is_instance_valid(mat):
			mat.set_shader_parameter("canopy_shade", canopy_shade)
			mat.set_shader_parameter("water_surface_y", water_y)
			mat.set_shader_parameter("daylight", daylight)
	# Push daylight into node-based foliage too so the SSS rim there
	# fades at night, matching the MultiMesh variant.
	for mat in _foliage_mat_cache.values():
		if is_instance_valid(mat):
			mat.set_shader_parameter("sss_daylight", daylight)


# Push a substrate ripple_phase value to every cached substrate_caustic
# material. World.gd advances this slowly with sim time so the sand bed's
# imprinted ripple pattern walks forward over many sim-minutes — visible
# evolution without needing per-voxel state.
static func update_substrate_ripple(phase: float, strength: float, dir: Vector2) -> void:
	for mat in _sub_caustic_mat_cache.values():
		if is_instance_valid(mat):
			mat.set_shader_parameter("ripple_phase", phase)
			mat.set_shader_parameter("ripple_strength", strength)
			mat.set_shader_parameter("ripple_dir", dir)


# Update SSS rim strength on every foliage material (both node-based and
# MultiMesh). Wires into TankConfig's plant_sss_strength field so the rim
# brightens/dims as the player tunes it.
static func update_foliage_sss(strength: float) -> void:
	for mat in _foliage_mat_cache.values():
		if is_instance_valid(mat):
			mat.set_shader_parameter("sss_strength", strength)
	for mat in _foliage_mm_mats:
		if is_instance_valid(mat):
			mat.set_shader_parameter("sss_strength", strength)

