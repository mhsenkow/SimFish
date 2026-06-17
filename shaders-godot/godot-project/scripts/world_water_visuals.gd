# Water-column visuals + light penetration helpers extracted from world.gd.
class_name WorldWaterVisuals
extends RefCounted

const LOCAL_SHADE_RADIUS: float = 1.35
const FLOATER_FOOTPRINT: float = 0.26


# Submerged light after surface floaters, green-water bloom, and tannin murk.
# local_floater_shade is position-specific; global_coverage is tank-wide fallback.
static func light_penetration(local_floater_shade: float, global_floater_coverage: float,
		bloom: float, tannins: float) -> float:
	var local: float = clampf(local_floater_shade, 0.0, 1.0)
	var global: float = clampf(global_floater_coverage, 0.0, 1.0)
	var floater_shade: float = lerpf(global, local, 0.82) * 0.62
	var bloom_murk: float = clampf(bloom, 0.0, 1.0) * 0.48
	var tannin_murk: float = clampf(tannins, 0.0, 1.0) * 0.32
	return clampf(1.0 - floater_shade - bloom_murk - tannin_murk, 0.08, 1.0)


# Radius-weighted local shade at a submerged XZ point (#21).
static func local_floater_shade_at(world_pos: Vector3, floaters: Array,
		radius: float = LOCAL_SHADE_RADIUS) -> float:
	var weight: float = 0.0
	var r2: float = radius * radius
	for f in floaters:
		if not is_instance_valid(f):
			continue
		var fn: Node3D = f
		var dx: float = fn.position.x - world_pos.x
		var dz: float = fn.position.z - world_pos.z
		var d2: float = dx * dx + dz * dz
		if d2 > r2:
			continue
		var shade_r: float = FLOATER_FOOTPRINT
		var leaf_sz: float = 0.3
		if f is FloatingPlant:
			var fp: FloatingPlant = f
			if not fp.is_surface_active():
				continue
			shade_r = fp.effective_shade_radius()
			leaf_sz = fp.leaf_size
		var falloff: float = 1.0 - sqrt(d2) / radius
		weight += falloff * shade_r * leaf_sz
	var local_cap: float = maxf(1.0, PI * radius * radius / FLOATER_FOOTPRINT)
	return clampf(weight / local_cap, 0.0, 1.0)


# Warmth at a world position: room baseline + daylight lamp warmth + heater falloff.
static func effective_warmth_at(pos: Vector3, _sim: Node, cfg: Node,
		heater_pos: Vector3, daylight: float, heater_enabled: bool = true) -> float:
	var light_warmth: float = 0.5
	if cfg != null and cfg.get("light_warmth") != null:
		light_warmth = clampf(float(cfg.light_warmth), 0.0, 1.0)
	var room_warmth: float = 0.52
	if cfg != null and cfg.has_method("current_environment_profile"):
		var prof: Dictionary = cfg.current_environment_profile()
		if prof.has("room_warmth"):
			room_warmth = float(prof["room_warmth"])
	var heater_boost: float = 0.0
	if heater_enabled and heater_pos != Vector3.ZERO:
		var dist: float = pos.distance_to(heater_pos)
		heater_boost = clampf(1.0 - dist / 4.5, 0.0, 1.0) * 0.30
	var lit: float = light_warmth * clampf(daylight, 0.0, 1.0)
	return clampf(room_warmth * 0.38 + lit * 0.42 + heater_boost, 0.0, 1.0)


# Surface-film warmth for floating plants. The meniscus stays near room temp when
# lights are off; lamp warmth is a daytime boost, not the baseline. Using
# submerged effective_warmth_at at night drove warmth below floater temp_min and
# culled entire mats after one dusk.
static func surface_warmth_at(pos: Vector3, cfg: Node, heater_pos: Vector3,
		daylight: float, heater_enabled: bool = true) -> float:
	var light_warmth: float = 0.5
	if cfg != null and cfg.get("light_warmth") != null:
		light_warmth = clampf(float(cfg.light_warmth), 0.0, 1.0)
	var room_warmth: float = 0.52
	if cfg != null and cfg.has_method("current_environment_profile"):
		var prof: Dictionary = cfg.current_environment_profile()
		if prof.has("room_warmth"):
			room_warmth = float(prof["room_warmth"])
	var heater_boost: float = 0.0
	if heater_enabled and heater_pos != Vector3.ZERO:
		var dist: float = pos.distance_to(heater_pos)
		heater_boost = clampf(1.0 - dist / 4.5, 0.0, 1.0) * 0.30
	var dl: float = clampf(daylight, 0.0, 1.0)
	var lamp_boost: float = light_warmth * lerpf(0.28, 0.42, dl)
	return clampf(room_warmth * 0.62 + lamp_boost + heater_boost, 0.0, 1.0)
