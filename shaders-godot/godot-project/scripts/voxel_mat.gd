# Voxel material factory.
#
# Caches the compiled voxel.gdshader once and produces a fresh ShaderMaterial
# per call with the requested albedo. The shader is unshaded + face-based, so
# each cube reads as a 3D object without needing a directional light.

extends RefCounted
class_name VoxelMat

const SHADER_PATH := "res://shaders/voxel.gdshader"
const _ShaderWarmCapture = preload("res://scripts/shader_warm_capture.gd")
const _BakedCaustics = preload("res://scripts/baked_caustics.gd")
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
const FAUNA_SSS_DEFAULT: float = 0.22
const FAUNA_IRID_DEFAULT: float = 0.18
const FAUNA_SSS_EXPERIMENTAL: float = 0.34
const FAUNA_IRID_EXPERIMENTAL: float = 0.45
const FAUNA_RIM: float = 0.58
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


static func boost_life_color(color: Color, sat_mult: float = FAUNA_SATURATION) -> Color:
	if color.a < 0.04:
		return color
	var h: float = color.h
	var s: float = clampf(color.s * sat_mult, 0.0, 1.0)
	var v: float = clampf(color.v * FAUNA_VALUE + FAUNA_LIGHTEN, 0.0, 1.0)
	return Color.from_hsv(h, s, v, color.a)


static func _biotope_fauna_sat_mult() -> float:
	var ml: MainLoop = Engine.get_main_loop()
	if ml is SceneTree:
		var tc: Node = (ml as SceneTree).root.get_node_or_null("/root/TankConfig")
		if tc != null:
			var Aesthetics := preload("res://scripts/aesthetics_runtime.gd")
			var key: String = Aesthetics.biotope_palette_key(tc)
			return Aesthetics.fauna_saturation_mult(key)
	return FAUNA_SATURATION


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
	# Gentler palette tint + lower value so room never out-competes the tank.
	m.set_shader_parameter("palette_global_scale", 0.35)
	m.set_shader_parameter("palette_saturation", 0.72)
	m.set_shader_parameter("palette_value", 0.82)
	# REAL_TANK_FIDELITY #183 — subtle orange-peel / plaster grain on walls.
	m.set_shader_parameter("grain_variation", 0.55)
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
	var boosted: Color = boost_life_color(color, _biotope_fauna_sat_mult())
	var cache_key: Color = _snap(boosted)
	if _fauna_mat_cache.has(cache_key):
		var cached: ShaderMaterial = _fauna_mat_cache[cache_key]
		cached.set_shader_parameter("fauna_rim", FAUNA_RIM)
		return cached
	var m: ShaderMaterial = make(boosted).duplicate()
	m.set_shader_parameter("palette_category", 1)
	m.set_shader_parameter("color_vibrancy", 1.24)
	var exp_on: bool = _experimental_on()
	m.set_shader_parameter("sss_strength",
		FAUNA_SSS_EXPERIMENTAL if exp_on else FAUNA_SSS_DEFAULT)
	m.set_shader_parameter("irid_strength",
		FAUNA_IRID_EXPERIMENTAL if exp_on else FAUNA_IRID_DEFAULT)
	m.set_shader_parameter("sss_color", Vector3(1.0, 0.85, 0.62))
	m.set_shader_parameter("fauna_rim", FAUNA_RIM)
	_cache_admit(_fauna_mat_cache, _fauna_key_queue, cache_key, m)
	return m


# Lightweight color carrier for FaunaVoxelBuilder — no shader, no cache entry.
static func fauna_color_carrier(color: Color) -> ShaderMaterial:
	var boosted: Color = boost_life_color(color, _biotope_fauna_sat_mult())
	var m := ShaderMaterial.new()
	m.set_shader_parameter("albedo", boosted)
	return m


static func fauna_color_from_material(mat: Material) -> Color:
	if mat is ShaderMaterial:
		return read_albedo(mat as ShaderMaterial)
	return Color.WHITE


static var _fauna_mm_template: ShaderMaterial = null
static var _fauna_mm_mats: Array = []
const FAUNA_MM_SHADER_PATH := "res://shaders/voxel_fauna_mm.gdshader"
const FAUNA_MM_CAP: int = 320


static func _ensure_fauna_mm_template() -> void:
	if _fauna_mm_template != null and is_instance_valid(_fauna_mm_template):
		return
	_fauna_mm_template = ShaderMaterial.new()
	_fauna_mm_template.shader = load(FAUNA_MM_SHADER_PATH) as Shader
	_fauna_mm_template.set_shader_parameter("color_vibrancy", 1.24)
	var exp_on: bool = _experimental_on()
	_fauna_mm_template.set_shader_parameter("sss_strength",
		FAUNA_SSS_EXPERIMENTAL if exp_on else FAUNA_SSS_DEFAULT)
	_fauna_mm_template.set_shader_parameter("irid_strength",
		FAUNA_IRID_EXPERIMENTAL if exp_on else FAUNA_IRID_DEFAULT)
	_fauna_mm_template.set_shader_parameter("sss_color", Vector3(1.0, 0.85, 0.62))
	_fauna_mm_template.set_shader_parameter("fauna_rim", FAUNA_RIM)


static func make_fauna_mm() -> ShaderMaterial:
	_ensure_fauna_mm_template()
	var m: ShaderMaterial = _fauna_mm_template.duplicate() as ShaderMaterial
	if _fauna_mm_mats.size() < FAUNA_MM_CAP and not _fauna_mm_mats.has(m):
		_fauna_mm_mats.append(m)
	return m


static func refresh_fauna_rims() -> void:
	for m in _fauna_mat_cache.values():
		if m is ShaderMaterial and (m as ShaderMaterial).get_shader_parameter("fauna_rim") != null:
			(m as ShaderMaterial).set_shader_parameter("fauna_rim", FAUNA_RIM)
	for m in _fauna_mm_mats:
		if m is ShaderMaterial and is_instance_valid(m) \
				and (m as ShaderMaterial).get_shader_parameter("fauna_rim") != null:
			(m as ShaderMaterial).set_shader_parameter("fauna_rim", FAUNA_RIM)


static func make_metallic_fauna(color: Color, strength: float = 0.55) -> ShaderMaterial:
	var m: ShaderMaterial = make_fauna(color)
	m.set_shader_parameter("metallic_strength", clampf(strength, 0.0, 1.0))
	var irid: float = float(m.get_shader_parameter("irid_strength"))
	m.set_shader_parameter("irid_strength", maxf(irid, 0.22))
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
	m.set_shader_parameter("palette_saturation", 0.82)
	_sub_opaque_mat_cache[cache_key] = m
	return m


static var _sub_caustic_shader: Shader = null
const SUB_CAUSTIC_SHADER_PATH := "res://shaders/substrate_caustic.gdshader"

static func _get_sub_caustic_shader() -> Shader:
	if _sub_caustic_shader == null:
		_sub_caustic_shader = load(SUB_CAUSTIC_SHADER_PATH) as Shader
	return _sub_caustic_shader

static var _sub_caustic_mat_cache: Dictionary = {}
static var _shader_perf_tier: int = 0


static func shader_perf_tier() -> int:
	return _shader_perf_tier


static func set_shader_perf_tier(tier: int) -> void:
	_shader_perf_tier = clampi(tier, 0, 2)
	_ShaderWarmCapture.record("shader_perf_tier_%d" % _shader_perf_tier)
	var blob_max: int = 16 if _shader_perf_tier >= 2 else 32
	var caustic_on: float = 0.0 if _shader_perf_tier >= 2 else 1.0
	var irid: float = 0.35 if _shader_perf_tier >= 1 else 1.0
	var outline_scale: float = 0.0 if _shader_perf_tier >= 2 else 1.0
	var region_dither: float = 0.0 if _shader_perf_tier >= 2 else 1.0
	for mat in _sub_caustic_mat_cache.values():
		if is_instance_valid(mat):
			mat.set_shader_parameter("blob_shadow_max", blob_max)
			mat.set_shader_parameter("caustic_enabled", caustic_on)
	for mat in _fauna_mat_cache.values():
		if is_instance_valid(mat):
			mat.set_shader_parameter("iridescence_mix", irid)
	for mat in _foliage_mat_cache.values():
		if is_instance_valid(mat):
			mat.set_shader_parameter("sss_strength", 0.45 if _shader_perf_tier >= 2 else 0.85)
	_shader_tier_post_outline = outline_scale
	_shader_tier_post_dither = region_dither


static var _shader_tier_post_outline: float = 1.0
static var _shader_tier_post_dither: float = 1.0


static func tier_post_outline_scale() -> float:
	return _shader_tier_post_outline


static func tier_post_region_dither() -> float:
	return _shader_tier_post_dither

static func make_substrate_caustic(color: Color, material_id: int = 0) -> ShaderMaterial:
	var cache_key: String = "%d_%s" % [material_id, str(snappedf(color.r, 0.02))]
	if _sub_caustic_mat_cache.has(cache_key):
		return _sub_caustic_mat_cache[cache_key]
	var m := ShaderMaterial.new()
	m.shader = _get_sub_caustic_shader()
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("material_id", material_id)
	m.set_shader_parameter("palette_saturation", 0.82)
	m.set_shader_parameter("blob_shadow_max", 16 if _shader_perf_tier >= 2 else 32)
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
	m.set_shader_parameter("sss_color", Vector3(0.85, 1.0, 0.55))
	_cache_admit(_foliage_mat_cache, _foliage_key_queue, cache_key, m)
	return m


# Surface blooms — much calmer than canopy leaves; per-petal GPU flutter
# at leaf defaults reads as chaotic jitter on small flower voxels.
static var _flower_foliage_cache: Dictionary = {}


static func make_flower_foliage(color: Color) -> ShaderMaterial:
	var key: String = "%s" % [str(_snap(color))]
	if _flower_foliage_cache.has(key):
		return _flower_foliage_cache[key]
	var m: ShaderMaterial = make_foliage(color).duplicate() as ShaderMaterial
	m.set_shader_parameter("sway_amplitude", 0.014)
	m.set_shader_parameter("sway_speed", 0.75)
	m.set_shader_parameter("flutter_amplitude", 0.005)
	m.set_shader_parameter("flutter_speed", 1.2)
	_flower_foliage_cache[key] = m
	return m


static func update_caustic_uniforms(intensity: float, color: Color) -> void:
	var scale: float = 1.0 if _shader_perf_tier < 2 else 0.55
	var eff: float = intensity * scale
	for mat in _sub_caustic_mat_cache.values():
		if is_instance_valid(mat):
			mat.set_shader_parameter("caustic_intensity", eff)
			mat.set_shader_parameter("light_color", color)


static func update_substrate_wave_scale(wave_scale: float) -> void:
	for mat in _sub_caustic_mat_cache.values():
		if is_instance_valid(mat):
			mat.set_shader_parameter("wave_scale", wave_scale)


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
	var m := ShaderMaterial.new()
	m.shader = _get_shader()
	m.set_shader_parameter("albedo", color)
	# Keep fixture panels hot through palette tint + night quantize.
	m.set_shader_parameter("palette_value", 1.18)
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

static var _glass_shape_id: float = -1.0
static var _glass_water_y: float = -1.0


static func make_glass(shape_id: float, water_y: float) -> ShaderMaterial:
	if _glass_mat == null:
		_glass_shader = load(GLASS_SHADER_PATH) as Shader
		_glass_mat = ShaderMaterial.new()
		_glass_mat.shader = _glass_shader
	# Metal screen_texture samples are often black — skip on macOS and
	# compensate with a stronger room fresnel/rim so glass doesn't go flat.
	var mac: bool = OS.get_name() == "macOS"
	_glass_mat.set_shader_parameter("screen_reflection", 0.0 if mac else 0.22)
	_glass_mat.set_shader_parameter("caustic_band", 0.48)
	_glass_mat.set_shader_parameter("fingerprint_strength", 0.16)
	if mac:
		_glass_mat.set_shader_parameter("reflection_strength", 0.58)
		_glass_mat.set_shader_parameter("rim_chrome", 0.78)
		_glass_mat.set_shader_parameter("rim_brightness", 0.48)
	if not is_equal_approx(_glass_shape_id, shape_id) or not is_equal_approx(_glass_water_y, water_y):
		_glass_mat.set_shader_parameter("tank_shape_id", shape_id)
		_glass_mat.set_shader_parameter("water_surface_y", water_y)
		_glass_shape_id = shape_id
		_glass_water_y = water_y
	return _glass_mat


static var _trans_shader: Shader = null
static var _trans_cache: Dictionary = {}
static var _mouthbrood_cache: Dictionary = {}


static func make_mouthbrood_bulge(color: Color) -> ShaderMaterial:
	var key: Color = Color(snappedf(color.r, 0.04), snappedf(color.g, 0.04), snappedf(color.b, 0.04))
	if _mouthbrood_cache.has(key):
		return _mouthbrood_cache[key]
	var m: ShaderMaterial = make_fauna(color)
	_mouthbrood_cache[key] = m
	return m


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
	for mat in _fauna_mm_mats:
		if mat is ShaderMaterial and is_instance_valid(mat):
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
	for mat in _fauna_mm_mats:
		if mat is ShaderMaterial and is_instance_valid(mat):
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
static var _mat_palette_last: Dictionary = {}
static var _palette_globals_ready: bool = false
const FOLIAGE_MM_CAP: int = 96


static func register_foliage_mm(mat: ShaderMaterial) -> void:
	if mat == null or _foliage_mm_mats.has(mat):
		return
	if _foliage_mm_mats.size() >= FOLIAGE_MM_CAP:
		return
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


static func update_foliage_flow(flow: Vector3, strength: float) -> void:
	var flow_dir: Vector3 = flow
	if flow_dir.length_squared() > 1e-6:
		flow_dir = flow_dir.normalized()
	for mat in _foliage_mm_mats:
		if is_instance_valid(mat):
			mat.set_shader_parameter("flow_dir", flow_dir)
			mat.set_shader_parameter("flow_strength", strength)
	for mat in _foliage_mat_cache.values():
		if is_instance_valid(mat):
			mat.set_shader_parameter("flow_dir", flow_dir)
			mat.set_shader_parameter("flow_strength", strength)


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


# REAL_TANK_FIDELITY §A — push stratified soil/cap cross-section uniforms into
# every opaque substrate material (side walls at the glass are where it reads).
static func apply_substrate_strata(params: Dictionary) -> void:
	if params.is_empty():
		return
	var keys: Array[String] = [
		"bed_bottom_y", "bed_top_y", "cap_fraction", "boundary_wave", "mix_band",
		"anoxic_darken", "grain_population", "root_density", "tunnel_strength",
		"detritus_amount", "bed_age", "wet_line_y", "glass_contact", "gas_pocket",
		"slope_hint",
	]
	for mat in _sub_opaque_mat_cache.values():
		if not is_instance_valid(mat):
			continue
		for k in keys:
			if params.has(k):
				mat.set_shader_parameter(k, params[k])
		if params.has("soil_color"):
			mat.set_shader_parameter("soil_color", params["soil_color"])
		if params.has("cap_color"):
			mat.set_shader_parameter("cap_color", params["cap_color"])


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
	for i in 32:
		if i < points.size() and points[i] is Vector4:
			packed.append(points[i] as Vector4)
		else:
			packed.append(Vector4.ZERO)
	var blob_tex: ImageTexture = _blob_shadow_texture(packed)
	for mat in _sub_caustic_mat_cache.values():
		if is_instance_valid(mat):
			mat.set_shader_parameter("blob_shadow_points", packed)
			if blob_tex != null:
				mat.set_shader_parameter("blob_shadow_tex", blob_tex)
				mat.set_shader_parameter("blob_shadow_tex_count", mini(points.size(), 16))


static func _blob_shadow_texture(points: Array[Vector4]) -> ImageTexture:
	# PERFORMANCE_UNTHROTTLED #84 — pack live blob casters into a 16×1 data texture.
	var img := Image.create(16, 1, false, Image.FORMAT_RGBAF)
	for i in 16:
		var p: Vector4 = points[i] if i < points.size() else Vector4.ZERO
		img.set_pixel(i, 0, Color(p.x, p.y, p.z, p.w))
	return ImageTexture.create_from_image(img)


static func update_substrate_shadow_choreo(
		gain: float,
		flash: float,
		calm: float,
		beat_pulse: float = 0.0) -> void:
	for mat in _sub_caustic_mat_cache.values():
		if is_instance_valid(mat):
			mat.set_shader_parameter("blob_shadow_gain", clampf(gain, 0.0, 1.5))
			mat.set_shader_parameter("blob_shadow_flash", clampf(flash, 0.0, 1.0))
			mat.set_shader_parameter("shadow_calm", clampf(calm, 0.0, 1.0))
			mat.set_shader_parameter("caustic_beat_pulse", clampf(beat_pulse, 0.0, 1.0))


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


static func _ensure_palette_globals() -> void:
	if _palette_globals_ready:
		return
	# global_shader_parameter_get_list() is editor-only; project.godot [shader_globals]
	# registers these at startup. Runtime only pushes values via set().
	_palette_globals_ready = true


static func _vec4_palette(p: Dictionary) -> Vector4:
	return Vector4(float(p.get("hue", 0.0)), float(p.get("sat", 1.0)),
		float(p.get("warmth", 0.0)), float(p.get("val", 1.0)))


static func _push_palette_globals(fauna_p: Dictionary, foliage_p: Dictionary,
		hardscape_p: Dictionary, sub_p: Dictionary, water_p: Dictionary) -> void:
	_ensure_palette_globals()
	RenderingServer.global_shader_parameter_set("iaq_palette_fauna", _vec4_palette(fauna_p))
	RenderingServer.global_shader_parameter_set("iaq_palette_foliage", _vec4_palette(foliage_p))
	RenderingServer.global_shader_parameter_set("iaq_palette_hardscape", _vec4_palette(hardscape_p))
	RenderingServer.global_shader_parameter_set("iaq_palette_substrate", _vec4_palette(sub_p))
	RenderingServer.global_shader_parameter_set("iaq_palette_water", _vec4_palette(water_p))


static func _apply_palette_overlay(mat: ShaderMaterial,
		oh: float, osat: float, owarm: float, oval: float) -> void:
	if mat == null or not is_instance_valid(mat):
		return
	mat.set_shader_parameter("palette_hue_shift", oh)
	mat.set_shader_parameter("palette_saturation", osat)
	mat.set_shader_parameter("palette_warmth", owarm)
	mat.set_shader_parameter("palette_value", oval)


static func _clear_palette_overlay(mat: ShaderMaterial) -> void:
	if mat == null or not is_instance_valid(mat):
		return
	mat.set_shader_parameter("palette_hue_shift", 0.0)
	mat.set_shader_parameter("palette_saturation", 1.0)
	mat.set_shader_parameter("palette_warmth", 0.0)
	mat.set_shader_parameter("palette_value", 1.0)


static func _apply_palette_to_material(mat: ShaderMaterial, hue: float, sat: float,
		warmth: float, val: float) -> void:
	if mat == null or not is_instance_valid(mat):
		return
	var mid: int = mat.get_instance_id()
	var key: Vector4 = Vector4(hue, sat, warmth, val)
	if _mat_palette_last.get(mid, Vector4.INF) == key:
		return
	_mat_palette_last[mid] = key
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


static var _palette_hash: int = 0
static var _palette_pending: bool = false
static var _last_music_shimmer: float = -1.0


static func request_global_palette(cfg: Node, water_mat: ShaderMaterial = null) -> void:
	if cfg == null:
		return
	var h: int = hash("%s|%s|%s|%s" % [
		str(snappedf(float(cfg.material_hue_shift), 0.001)),
		str(snappedf(float(cfg.material_saturation), 0.001)),
		str(snappedf(float(cfg.material_warmth), 0.001)),
		str(snappedf(float(cfg.material_value), 0.001)),
	])
	if h == _palette_hash and not _palette_pending:
		return
	_palette_hash = h
	_palette_cfg_pending = cfg
	_palette_water_pending = water_mat
	if _palette_pending:
		return
	_palette_pending = true
	var st: SceneTree = Engine.get_main_loop() as SceneTree
	if st != null:
		st.process_frame.connect(_flush_palette_once, CONNECT_ONE_SHOT)


static var _palette_cfg_pending: Node = null
static var _palette_water_pending: ShaderMaterial = null


static func _flush_palette_once() -> void:
	_palette_pending = false
	apply_global_palette(_palette_cfg_pending, _palette_water_pending)


static func apply_global_palette(cfg: Node, water_mat: ShaderMaterial = null) -> void:
	if cfg == null:
		return
	var fauna_p: Dictionary = _scaled_palette_params(cfg, float(cfg.material_weight_fauna))
	var foliage_p: Dictionary = _scaled_palette_params(cfg, float(cfg.material_weight_foliage))
	var hardscape_p: Dictionary = _scaled_palette_params(cfg, float(cfg.material_weight_hardscape))
	var sub_p: Dictionary = _scaled_palette_params(cfg, float(cfg.material_weight_substrate))
	var water_p: Dictionary = _scaled_palette_params(cfg, float(cfg.material_weight_water))
	_push_palette_globals(fauna_p, foliage_p, hardscape_p, sub_p, water_p)
	# Globals + palette_category on voxel.gdshader — clear per-mat overlays only.
	for mat in _fauna_mat_cache.values():
		if is_instance_valid(mat):
			_clear_palette_overlay(mat as ShaderMaterial)
	for mat in _foliage_mat_cache.values():
		if is_instance_valid(mat):
			_clear_palette_overlay(mat as ShaderMaterial)
	for mat in _foliage_mm_mats:
		if is_instance_valid(mat):
			_clear_palette_overlay(mat as ShaderMaterial)
	for mat in _mat_cache.values():
		if is_instance_valid(mat):
			_clear_palette_overlay(mat as ShaderMaterial)
	for mat in _room_mat_cache.values():
		if is_instance_valid(mat):
			_clear_palette_overlay(mat as ShaderMaterial)
	if _voxel_mm_mat != null and is_instance_valid(_voxel_mm_mat):
		_clear_palette_overlay(_voxel_mm_mat)
	for mat in _sub_opaque_mat_cache.values():
		if is_instance_valid(mat):
			_clear_palette_overlay(mat as ShaderMaterial)
	for mat in _sub_caustic_mat_cache.values():
		if is_instance_valid(mat):
			_clear_palette_overlay(mat as ShaderMaterial)
	if water_mat != null and is_instance_valid(water_mat):
		_clear_palette_overlay(water_mat)


# Music-sync overlay — stacks on top of the global palette while a track drives
# the tank. Fauna + foliage get the full tint; hardscape/substrate a gentler wash.
static func apply_music_sync_overlay(overlay: Dictionary, shimmer: float) -> void:
	var oh: float = float(overlay.get("hue", 0.0))
	var osat: float = float(overlay.get("sat", 1.0))
	var owarm: float = float(overlay.get("warmth", 0.0))
	var oval: float = float(overlay.get("val", 1.0))
	for mat in _fauna_mat_cache.values():
		if is_instance_valid(mat):
			_apply_palette_overlay(mat, oh, osat, owarm, oval)
			if absf(shimmer - _last_music_shimmer) > 0.02:
				mat.set_shader_parameter("aquatic_shimmer", shimmer)
				_last_music_shimmer = shimmer
	for mat in _foliage_mat_cache.values():
		if is_instance_valid(mat):
			_apply_palette_overlay(mat, oh * 0.65, lerpf(1.0, osat, 0.7),
				owarm * 0.5, lerpf(1.0, oval, 0.7))
	for mat in _foliage_mm_mats:
		if is_instance_valid(mat):
			_apply_palette_overlay(mat, oh * 0.65, lerpf(1.0, osat, 0.7),
				owarm * 0.5, lerpf(1.0, oval, 0.7))


# PERFORMANCE_REALTIME #64 — load + pre-draw hot shader variants on the menu.
static var _shader_warm_done: bool = false


static func warm_shader_variants(cfg: Node = null) -> void:
	if _shader_warm_done:
		return
	_shader_warm_done = true
	_warm_shaders_cpu(cfg)
	_ShaderWarmCapture.replay_warm()
	if DisplayServer.get_name() == "headless":
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var warm := ShaderGpuWarm.new()
	tree.root.call_deferred("add_child", warm)


static func _warm_shaders_cpu(cfg: Node = null) -> void:
	_get_shader()
	_ShaderWarmCapture.record("voxel")
	make(Color8(100, 120, 90))
	_ShaderWarmCapture.record("fauna")
	make_fauna(Color(0.55, 0.42, 0.32))
	make_fauna_mm()
	make_foliage(Color(0.42, 0.72, 0.36))
	make_flower_foliage(Color(0.92, 0.55, 0.68))
	make_substrate_opaque(Color8(82, 62, 44))
	var sub_caustic: ShaderMaterial = make_substrate_caustic(Color8(92, 72, 52))
	_BakedCaustics.apply_to_material(sub_caustic, _shader_perf_tier)
	_ShaderWarmCapture.record("substrate_caustic")
	make_water(Color(0.22, 0.52, 0.62), Color(0.06, 0.16, 0.28), 0.0, 12.0)
	_ShaderWarmCapture.record("water")
	make_surface_ripple()
	make_bubble()
	make_glass(0.0, 12.0)
	make_emissive(Color(1.0, 0.9, 0.72))
	make_translucent(Color(0.5, 0.8, 0.9, 0.42))
	make_room(Color8(140, 130, 120))
	if cfg != null:
		apply_global_palette(cfg)
	else:
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree != null and tree.root != null:
			var tank_cfg: Node = tree.root.get_node_or_null("/root/TankConfig")
			if tank_cfg != null:
				apply_global_palette(tank_cfg)


class ShaderGpuWarm extends Node:
	func _ready() -> void:
		call_deferred("_draw_warm")


	func _draw_warm() -> void:
		var vp := SubViewport.new()
		vp.size = Vector2i(8, 8)
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		vp.disable_3d = false
		add_child(vp)
		var root3d := Node3D.new()
		vp.add_child(root3d)
		var cam := Camera3D.new()
		cam.current = true
		cam.position = Vector3(0.0, 0.0, 4.0)
		root3d.add_child(cam)
		var box := BoxMesh.new()
		box.size = Vector3(0.4, 0.4, 0.4)
		var mats: Array[ShaderMaterial] = [
			VoxelMat.make(Color8(100, 120, 90)),
			VoxelMat.make_fauna_mm(),
			VoxelMat.make_foliage(Color(0.42, 0.72, 0.36)),
			VoxelMat.make_surface_ripple(),
			VoxelMat.make_water(Color(0.22, 0.52, 0.62), Color(0.06, 0.16, 0.28), 0.0, 12.0),
		]
		var x: float = -4.0
		for mat in mats:
			var mi := MeshInstance3D.new()
			mi.mesh = box
			mi.material_override = mat
			mi.position = Vector3(x, 0.0, 0.0)
			root3d.add_child(mi)
			x += 2.0
		await get_tree().process_frame
		await get_tree().process_frame
		queue_free()
