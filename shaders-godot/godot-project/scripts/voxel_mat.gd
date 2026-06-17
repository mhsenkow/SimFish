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

# Color quantization for cache keys. Bumped 0.01 → 0.04 — 256 levels per
# channel was ~16M unique colors, way more than the palette quantize
# shader could distinguish anyway. 25 levels (0.04) per channel = 15,625
# unique colors total, still way past the visible palette. Result: 10×
# smaller caches without any visual difference.
const _CACHE_SNAP: float = 0.04
# Bound the foliage + fauna caches so a long play session with mutated
# plant colors doesn't grow the cache to thousands of materials. When
# we cross the limit we drop the oldest entries via a queue of keys.
const _CACHE_MAX: int = 800
static var _foliage_key_queue: Array = []
static var _fauna_key_queue: Array = []


# Snap a color to the cache's quantization grid. Used as the dict key.
static func _snap(c: Color) -> Color:
	return Color(
		snappedf(c.r, _CACHE_SNAP),
		snappedf(c.g, _CACHE_SNAP),
		snappedf(c.b, _CACHE_SNAP))


# Evict the oldest entries from a cache when it exceeds _CACHE_MAX.
# Pops half the over-quota so we don't churn one-pop-per-add. Materials
# go to garbage collection naturally — they're RefCounted.
static func _cache_admit(cache: Dictionary, queue: Array, key, value) -> void:
	if cache.size() >= _CACHE_MAX:
		var drop_count: int = int(_CACHE_MAX / 4.0)
		for i in range(drop_count):
			if queue.is_empty():
				break
			var old_key = queue.pop_front()
			cache.erase(old_key)
	cache[key] = value
	queue.append(key)

const FAUNA_SATURATION: float = 1.30
# Originally 1.12. Bumping past ~1.15 makes the palette-quantize dither
# pattern read as a visible grid on bright fish — neighbouring palette
# entries land too far apart in value. 1.14 keeps fauna slightly above
# plants without tripping the dither moiré.
const FAUNA_VALUE: float = 1.14
const FAUNA_LIGHTEN: float = 0.05    # restored from 0.07 — same dither reason
# Plants get a separate, more aggressive saturation push so the greens
# read as planted-tank-green rather than muted forest-green. Reds + tans
# (stems, leaf undersides, bronze new growth) keep the base boost so they
# don't oversaturate into neon.
const FOLIAGE_GREEN_SATURATION: float = 1.55  # hue in green band
const FOLIAGE_OTHER_SATURATION: float = 1.30  # all other hues
const FOLIAGE_VALUE: float = 1.08             # subtler than fauna so plants
                                              # don't outshine creatures


static func boost_life_color(color: Color) -> Color:
	if color.a < 0.04:
		return color
	var h: float = color.h
	var s: float = clampf(color.s * FAUNA_SATURATION, 0.0, 1.0)
	var v: float = clampf(color.v * FAUNA_VALUE + FAUNA_LIGHTEN, 0.0, 1.0)
	return Color.from_hsv(h, s, v, color.a)


# Plant-specific color boost. Pushes greens to "vibrant aquarium green"
# saturation while keeping other hues (red/copper/bronze leaf accents)
# at the default boost. Reads naturally on the existing palette ramps
# without breaking red plants like Ludwigia / Rotala macrandra.
# Green band in Godot's HSV is roughly hue 0.22..0.42 (≈80°..150°).
static func boost_foliage_color(color: Color) -> Color:
	if color.a < 0.04:
		return color
	var h: float = color.h
	var sat_mult: float
	if h >= 0.22 and h <= 0.42:
		sat_mult = FOLIAGE_GREEN_SATURATION
	else:
		sat_mult = FOLIAGE_OTHER_SATURATION
	var s: float = clampf(color.s * sat_mult, 0.0, 1.0)
	var v: float = clampf(color.v * FOLIAGE_VALUE, 0.0, 1.0)
	return Color.from_hsv(h, s, v, color.a)


static func get_box(size: Vector3) -> BoxMesh:
	var key: Vector3 = Vector3(snappedf(size.x, 0.01), snappedf(size.y, 0.01), snappedf(size.z, 0.01))
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var bm := BoxMesh.new()
	bm.size = size
	_mesh_cache[key] = bm
	return bm


static var _room_mat_cache: Dictionary = {}

# Room-side materials. Same voxel.gdshader as `make()` but with the
# room_haze_strength uniform pre-set so the desk + wall + props fade
# toward a warm haze with view distance. Tank-side voxels keep using
# `make()` and stay crisp.
static func make_room(color: Color, haze_strength: float = 0.65,
		haze_color: Color = Color(0.92, 0.84, 0.74)) -> ShaderMaterial:
	var key: String = "%s_%s" % [
		Color(snappedf(color.r, 0.01), snappedf(color.g, 0.01), snappedf(color.b, 0.01)),
		snappedf(haze_strength, 0.05)]
	if _room_mat_cache.has(key):
		return _room_mat_cache[key]
	var m := ShaderMaterial.new()
	m.shader = _get_shader()
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("room_haze_strength", haze_strength)
	m.set_shader_parameter("room_haze_color", Vector3(haze_color.r, haze_color.g, haze_color.b))
	_room_mat_cache[key] = m
	return m


# Push a shared haze tint onto all cached room materials (desk/wall props).
static func update_room_haze(color: Color) -> void:
	var hc := Vector3(color.r, color.g, color.b)
	for m in _room_mat_cache.values():
		if m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter("room_haze_color", hc)


static func make(color: Color) -> ShaderMaterial:
	# Snap + cache; _mat_cache isn't queue-tracked because the base mat
	# stays under ~200 entries naturally (substrate + hardscape voxel set).
	var cache_key: Color = _snap(color)
	if _mat_cache.has(cache_key):
		return _mat_cache[cache_key]

	var m := ShaderMaterial.new()
	m.shader = _get_shader()
	m.set_shader_parameter("albedo", color)
	_mat_cache[cache_key] = m
	return m


static func _experimental_on() -> bool:
	var ml: MainLoop = Engine.get_main_loop()
	if ml is SceneTree:
		var tc: Node = (ml as SceneTree).root.get_node_or_null("/root/TankConfig")
		if tc != null:
			return bool(tc.get("experimental_visuals"))
	return false


static func make_fauna(color: Color) -> ShaderMaterial:
	var boosted: Color = boost_life_color(color)
	var cache_key: Color = _snap(boosted)
	if _fauna_mat_cache.has(cache_key):
		return _fauna_mat_cache[cache_key]
	var m: ShaderMaterial = make(boosted).duplicate()
	# 1.24 — was 1.32 which over-saturated bright fish into the palette
	# quantize's dither-grid territory. 1.24 still rides above foliage
	# (1.22 below) without tripping moiré on fish bodies.
	m.set_shader_parameter("color_vibrancy", 1.24)
	# Subtle living-tissue rim + scale sheen by default; experimental toggle
	# pushes toward jewel-like intensity.
	var exp_on: bool = _experimental_on()
	m.set_shader_parameter("sss_strength", 0.34 if exp_on else 0.15)
	m.set_shader_parameter("irid_strength", 0.45 if exp_on else 0.08)
	m.set_shader_parameter("sss_color", Vector3(1.0, 0.85, 0.62))
	_cache_admit(_fauna_mat_cache, _fauna_key_queue, cache_key, m)
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
	# Plants use the green-aware boost so canopy reads as vibrant aquarium
	# green while still letting red plants (Ludwigia, Rotala, AR) keep
	# their saturated reds.
	var boosted: Color = boost_foliage_color(color)
	var cache_key: Color = _snap(boosted)
	if _foliage_mat_cache.has(cache_key):
		return _foliage_mat_cache[cache_key]

	var m := ShaderMaterial.new()
	m.shader = _get_foliage_shader()
	m.set_shader_parameter("albedo", boosted)
	# 1.22 — was 1.28. Plants kept the green-aware boost in
	# boost_foliage_color so they still read vibrant, but lowering the
	# shader vibrancy a notch reduces palette banding on dense leaves.
	m.set_shader_parameter("color_vibrancy", 1.22)
	_cache_admit(_foliage_mat_cache, _foliage_key_queue, cache_key, m)
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


static func make_bubble(color: Color = Color(0.78, 0.92, 0.96, 0.42),
		emissive_boost: float = 1.0) -> ShaderMaterial:
	if emissive_boost <= 1.001 and _bubble_mat != null:
		return _bubble_mat
	var m := ShaderMaterial.new()
	m.shader = _get_bubble_shader()
	m.set_shader_parameter("bubble_color", color)
	m.set_shader_parameter("emissive_boost", emissive_boost)
	if emissive_boost <= 1.001:
		_bubble_mat = m
	return m


# Overbright albedo for fixture LEDs / emissive voxels — punches through
# the palette-quantize night burnthrough path without a separate shader.
static func make_emissive(color: Color) -> ShaderMaterial:
	var m: ShaderMaterial = make(color).duplicate() as ShaderMaterial
	return m


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


static func update_fixture_glow(glow: float, color: Color, water_y: float,
		water_floor: float) -> void:
	for mat in _mat_cache.values():
		if is_instance_valid(mat):
			mat.set_shader_parameter("tank_fixture_glow", glow)
			mat.set_shader_parameter("tank_fixture_color", color)
			mat.set_shader_parameter("fixture_water_floor", water_floor)
	for mat in _fauna_mat_cache.values():
		if is_instance_valid(mat):
			mat.set_shader_parameter("tank_fixture_glow", glow)
			mat.set_shader_parameter("tank_fixture_color", color)
			mat.set_shader_parameter("fixture_water_floor", water_floor)
	for mat in _foliage_mat_cache.values():
		if is_instance_valid(mat):
			mat.set_shader_parameter("tank_fixture_glow", glow)
			mat.set_shader_parameter("tank_fixture_color", color)
			mat.set_shader_parameter("fixture_water_top", water_y)
			mat.set_shader_parameter("fixture_water_floor", water_floor)
	for mat in _foliage_mm_mats:
		if is_instance_valid(mat):
			mat.set_shader_parameter("tank_fixture_glow", glow)
			mat.set_shader_parameter("tank_fixture_color", color)
			mat.set_shader_parameter("fixture_water_floor", water_floor)
	if _voxel_mm_mat != null and is_instance_valid(_voxel_mm_mat):
		_voxel_mm_mat.set_shader_parameter("tank_fixture_glow", glow)
		_voxel_mm_mat.set_shader_parameter("tank_fixture_color", color)
		_voxel_mm_mat.set_shader_parameter("fixture_water_top", water_y)
		_voxel_mm_mat.set_shader_parameter("fixture_water_floor", water_floor)


static var _foliage_mm_mats: Array = []

static func register_foliage_mm(mat: ShaderMaterial) -> void:
	if mat != null and not _foliage_mm_mats.has(mat):
		_foliage_mm_mats.append(mat)


# Shared MultiMesh-aware voxel material — voxel_mm.gdshader reads color from
# the per-instance MultiMesh COLOR buffer instead of an `albedo` uniform, so a
# single instance of this material is sufficient for every algae cluster +
# biofilm patch in the scene. Each entity still gets its OWN VoxelBatch (one
# MultiMeshInstance3D per cluster, one draw call), but all those batches
# point at this same material — keeping the shader pipeline compile + uniform
# cost flat regardless of how many algae are alive.
static var _voxel_mm_mat: ShaderMaterial = null

static func make_voxel_mm() -> ShaderMaterial:
	if _voxel_mm_mat == null:
		_voxel_mm_mat = ShaderMaterial.new()
		_voxel_mm_mat.shader = load("res://shaders/voxel_mm.gdshader") as Shader
	return _voxel_mm_mat


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


# Push the substrate's "flow origin" (filter intake position) into every
# cached substrate_caustic material so the ripple shader can deepen its
# pattern near the current source. xyz = world position, w = max-radius
# gain (0 disables the system). Called from world.gd at hardscape build
# or whenever the intake position changes.
static func update_substrate_flow_origin(origin: Vector3, gain: float) -> void:
	var v: Vector4 = Vector4(origin.x, origin.y, origin.z, gain)
	for mat in _sub_caustic_mat_cache.values():
		if is_instance_valid(mat):
			mat.set_shader_parameter("flow_origin", v)


# Push hardscape contact-AO footprints (driftwood roots, rock bases) into
# every substrate material so they darken the substrate where wood meets
# sand. Accepts an Array of Vector4 (xyz = world position, w = radius);
# the first 8 entries land in the shader's uniform array, the rest are
# silently dropped. Pass an empty array to clear AO.
static func update_substrate_contact_ao(points: Array) -> void:
	var packed: Array[Vector4] = []
	for i in 8:
		if i < points.size():
			var v_in: Variant = points[i]
			if v_in is Vector4:
				packed.append(v_in as Vector4)
				continue
		packed.append(Vector4.ZERO)
	for mat in _sub_caustic_mat_cache.values():
		if is_instance_valid(mat):
			mat.set_shader_parameter("contact_ao_points", packed)
	for mat in _sub_opaque_mat_cache.values():
		if is_instance_valid(mat):
			mat.set_shader_parameter("contact_ao_points", packed)


# Push soft blob-shadow casters (the nearest fish) into the substrate caustic
# material so the floor darkens beneath swimming fish. Same packing convention
# as contact AO: Array of Vector4 (xyz = world position, w = radius). Only the
# top-face caustic material reads these. Pass an empty array to clear.
static func update_substrate_blob_shadows(points: Array) -> void:
	var packed: Array[Vector4] = []
	for i in 8:
		if i < points.size() and points[i] is Vector4:
			packed.append(points[i] as Vector4)
		else:
			packed.append(Vector4.ZERO)
	for mat in _sub_caustic_mat_cache.values():
		if is_instance_valid(mat):
			mat.set_shader_parameter("blob_shadow_points", packed)


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


static func _apply_palette_to_material(mat: ShaderMaterial, hue: float, sat: float,
		warmth: float, val: float) -> void:
	if mat == null or not is_instance_valid(mat):
		return
	mat.set_shader_parameter("palette_hue_shift", hue)
	mat.set_shader_parameter("palette_saturation", sat)
	mat.set_shader_parameter("palette_warmth", warmth)
	mat.set_shader_parameter("palette_value", val)


static func _scaled_palette_params(cfg: Node, weight: float) -> Dictionary:
	var w: float = clampf(weight, 0.0, 1.0)
	return {
		"hue": float(cfg.material_hue_shift) * w,
		"sat": lerpf(1.0, float(cfg.material_saturation), w),
		"warmth": float(cfg.material_warmth) * w,
		"val": lerpf(1.0, float(cfg.material_value), w),
	}


static func read_albedo(mat: ShaderMaterial, fallback: Color = Color.WHITE) -> Color:
	if mat == null or not is_instance_valid(mat):
		return fallback
	var v: Variant = mat.get_shader_parameter("albedo")
	return v as Color if v is Color else fallback


static func apply_global_palette(cfg: Node, water_mat: ShaderMaterial = null) -> void:
	if cfg == null:
		return
	var fauna_p: Dictionary = _scaled_palette_params(cfg, float(cfg.material_weight_fauna))
	for mat in _fauna_mat_cache.values():
		if is_instance_valid(mat):
			_apply_palette_to_material(mat, fauna_p.hue, fauna_p.sat, fauna_p.warmth, fauna_p.val)
	var foliage_p: Dictionary = _scaled_palette_params(cfg, float(cfg.material_weight_foliage))
	for mat in _foliage_mat_cache.values():
		if is_instance_valid(mat):
			_apply_palette_to_material(mat, foliage_p.hue, foliage_p.sat, foliage_p.warmth, foliage_p.val)
	for mat in _foliage_mm_mats:
		if is_instance_valid(mat):
			_apply_palette_to_material(mat, foliage_p.hue, foliage_p.sat, foliage_p.warmth, foliage_p.val)
	var hardscape_p: Dictionary = _scaled_palette_params(cfg, float(cfg.material_weight_hardscape))
	for mat in _mat_cache.values():
		if is_instance_valid(mat):
			_apply_palette_to_material(mat, hardscape_p.hue, hardscape_p.sat, hardscape_p.warmth, hardscape_p.val)
	for mat in _room_mat_cache.values():
		if is_instance_valid(mat):
			_apply_palette_to_material(mat, hardscape_p.hue * 0.5, hardscape_p.sat, hardscape_p.warmth * 0.5, hardscape_p.val)
	if _voxel_mm_mat != null and is_instance_valid(_voxel_mm_mat):
		_apply_palette_to_material(_voxel_mm_mat, hardscape_p.hue, hardscape_p.sat, hardscape_p.warmth, hardscape_p.val)
	var sub_p: Dictionary = _scaled_palette_params(cfg, float(cfg.material_weight_substrate))
	for mat in _sub_opaque_mat_cache.values():
		if is_instance_valid(mat):
			_apply_palette_to_material(mat, sub_p.hue, sub_p.sat, sub_p.warmth, sub_p.val)
	for mat in _sub_caustic_mat_cache.values():
		if is_instance_valid(mat):
			_apply_palette_to_material(mat, sub_p.hue, sub_p.sat, sub_p.warmth, sub_p.val)
	var water_p: Dictionary = _scaled_palette_params(cfg, float(cfg.material_weight_water))
	if water_mat != null and is_instance_valid(water_mat):
		_apply_palette_to_material(water_mat, water_p.hue, water_p.sat, water_p.warmth, water_p.val)

