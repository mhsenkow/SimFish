# Unified atmosphere: day/night curves, water-column murk, caustic/god-ray
# attenuation, sim clock, shape-aware mineral spots, aeration substrate flow.
class_name WorldAtmosphere
extends RefCounted

const DEFAULTS: Dictionary = {
	"room_warmth": 0.52,
	"sunset_boost": 1.0,
	"night_depth_boost": 1.0,
	"ice_lens_strength": 0.0,
	"tannin_affinity": 0.0,
	"sim_clock": true,
}


static func atmosphere_profile(cfg: Node) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate()
	if cfg == null or not cfg.has_method("current_environment_profile"):
		return out
	var prof: Dictionary = cfg.current_environment_profile()
	for key in DEFAULTS.keys():
		if prof.has(key):
			out[key] = prof[key]
	return out


# Shared day/night lighting curves for room sky, tank fixture, and water tint.
static func day_night_lighting(sim_n: Node, cfg: Node) -> Dictionary:
	var dl: float = 1.0
	var dp: float = 0.25
	if sim_n != null:
		dl = float(sim_n.daylight())
		dp = fposmod(float(sim_n.day_phase), 1.0)
	var sunset_hour: float = clampf(1.0 - absf(dp - 0.5) / 0.12, 0.0, 1.0)
	var dawn_glow: float = 0.0
	if dp < 0.12:
		dawn_glow = 1.0 - dp / 0.12
	elif dp > 0.92:
		dawn_glow = (dp - 0.92) / 0.08
	sunset_hour = maxf(sunset_hour, dawn_glow * 0.5)
	var deep_night: float = 1.0 - smoothstep(0.04, 0.58, dl)
	var tank_lights_on: bool = true
	var atm: Dictionary = atmosphere_profile(cfg)
	sunset_hour = minf(1.5, sunset_hour * float(atm["sunset_boost"]))
	const SUNSET_SHADER_CAP: float = 1.5
	sunset_hour = minf(SUNSET_SHADER_CAP, sunset_hour)
	deep_night = clampf(deep_night * float(atm["night_depth_boost"]), 0.0, 1.0)
	if cfg != null:
		tank_lights_on = not not cfg.tank_lights_on
	return {
		"dl": dl,
		"dp": dp,
		"sunset_hour": sunset_hour,
		"deep_night": deep_night,
		"tank_lights_on": tank_lights_on,
		"atmosphere": atm,
	}


static func bacterial_bloom_from_chemistry(water_chemistry) -> float:
	if water_chemistry == null:
		return 0.0
	var nh3: float = float(water_chemistry.ammonia)
	var no2: float = float(water_chemistry.nitrite)
	return clampf(((nh3 + no2 * 0.5) - 0.4) / 0.8, 0.0, 1.0)


# Water tint + transmittance bundle - ties the water shader to the same murk
# model plants use via WorldWaterVisuals.light_penetration().
static func water_column_bundle(tannins: float, bloom: float, floater_coverage: float,
		water_chemistry, shallow_rgb: Color, deep_rgb: Color,
		tannin_affinity: float = 0.0) -> Dictionary:
	var eff_tannins: float = clampf(tannins + tannin_affinity, 0.0, 0.65)
	var tannin_color := Color(0.83, 0.55, 0.25)
	var base_water := Color(shallow_rgb.r, shallow_rgb.g, shallow_rgb.b)
	var tinted: Color = base_water.lerp(tannin_color, eff_tannins * 0.80)
	if bloom > 0.01:
		var algae_green := Color(0.36, 0.62, 0.32)
		tinted = tinted.lerp(algae_green, bloom * 0.65)
	var tint_strength: float = eff_tannins * 0.70 + bloom * 0.55
	var shallow_a: float = 0.12 + eff_tannins * 0.12 + bloom * 0.14
	var deep_a: float = 0.20 + eff_tannins * 0.18 + bloom * 0.22
	var bact_bloom: float = bacterial_bloom_from_chemistry(water_chemistry)
	var transmittance: float = WorldWaterVisuals.light_penetration(
		floater_coverage, floater_coverage, bloom, eff_tannins)
	# Milky cycle haze stacks on top of green-water murk.
	transmittance *= 1.0 - bact_bloom * 0.38
	transmittance = clampf(transmittance, 0.06, 1.0)
	return {
		"tint_color": tinted,
		"tint_strength": clampf(tint_strength, 0.0, 0.85),
		"bloom_haze": bloom,
		"bacterial_bloom": bact_bloom,
		"shallow_color": Color(shallow_rgb.r, shallow_rgb.g, shallow_rgb.b, shallow_a),
		"deep_color": Color(deep_rgb.r, deep_rgb.g, deep_rgb.b, deep_a),
		"depth_fog": 0.42 + bloom * 0.12 + (1.0 - transmittance) * 0.22,
		"transmittance": transmittance,
	}


static func water_day_night_uniforms(ln: Dictionary) -> Dictionary:
	var dl: float = ln["dl"]
	var dp: float = ln["dp"]
	var sunset_hour: float = ln["sunset_hour"]
	var deep_night: float = ln["deep_night"]
	var tank_lights_on: bool = ln["tank_lights_on"]
	var sunset: float = sunset_hour * clampf(1.0 - deep_night * 0.35, 0.0, 1.0)
	var moon: float = clampf((0.22 - dl) / 0.22, 0.0, 1.0) * deep_night
	if tank_lights_on:
		moon *= 1.0 - deep_night * 0.92
	return {
		"sunset_warmth": sunset,
		"moonlight": moon,
		"day_phase_offset": dp,
	}


static func ice_lens_uniform(ln: Dictionary, atm: Dictionary) -> float:
	var dl: float = ln["dl"]
	var strength: float = float(atm.get("ice_lens_strength", 0.0))
	if strength <= 0.001:
		return 0.0
	return clampf((0.4 - dl) * strength, 0.0, 0.35)


static func modulate_caustic_intensity(base: float, transmittance: float,
		bact_bloom: float) -> float:
	var murk: float = clampf(1.0 - transmittance, 0.0, 1.0)
	var cycle_haze: float = bact_bloom * 0.45
	return base * clampf(transmittance * 0.70 + 0.30 - murk * 0.25 - cycle_haze, 0.04, 1.0)


static func modulate_god_ray_alpha(base_alpha: float, transmittance: float) -> float:
	return base_alpha * clampf(transmittance * 0.72 + 0.22, 0.06, 1.0)


static func apply_water_shader(mat: ShaderMaterial, column: Dictionary,
		day_night: Dictionary, ice_lens: float) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("tint_color", column["tint_color"])
	mat.set_shader_parameter("tint_strength", column["tint_strength"])
	mat.set_shader_parameter("bloom_haze", column["bloom_haze"])
	mat.set_shader_parameter("bacterial_bloom", column["bacterial_bloom"])
	mat.set_shader_parameter("shallow_color", column["shallow_color"])
	mat.set_shader_parameter("deep_color", column["deep_color"])
	mat.set_shader_parameter("depth_fog", column["depth_fog"])
	var trans: float = float(column.get("transmittance", 1.0))
	mat.set_shader_parameter("depth_absorption",
		clampf(0.34 + (1.0 - trans) * 0.36, 0.0, 1.0))
	# macOS-safe atmospheric depth (#20) - volumetric fog stays off on Metal.
	mat.set_shader_parameter("aerial_haze",
		clampf(0.40 + (1.0 - trans) * 0.38, 0.0, 0.82))
	var dn: Dictionary = water_day_night_uniforms(day_night)
	mat.set_shader_parameter("surface_reflection",
		clampf(0.22 + float(dn["sunset_warmth"]) * 0.18, 0.0, 0.48))
	mat.set_shader_parameter("underside_mirror", 0.34)
	var room_warm: float = float(dn["sunset_warmth"])
	mat.set_shader_parameter("room_sky_color", Vector3(
		lerp(0.52, 0.72, room_warm),
		lerp(0.58, 0.62, room_warm),
		lerp(0.68, 0.55, room_warm)))
	mat.set_shader_parameter("sunset_warmth", dn["sunset_warmth"])
	mat.set_shader_parameter("moonlight", dn["moonlight"])
	mat.set_shader_parameter("day_phase_offset", dn["day_phase_offset"])
	if ice_lens > 0.001:
		mat.set_shader_parameter("ice_lens", ice_lens)


# Room clock: sim day-phase by default; wall time when preset sets sim_clock false.
static func clock_hand_rotations(cfg: Node, sim: Node) -> Dictionary:
	var atm: Dictionary = atmosphere_profile(cfg)
	if bool(atm.get("sim_clock", true)) and sim != null:
		var dp: float = fposmod(float(sim.day_phase), 1.0)
		var hours: float = dp * 24.0
		var hr: float = fmod(hours, 12.0)
		var mn: float = fmod(hours * 60.0, 60.0)
		var sc: float = fmod(hours * 3600.0, 60.0)
		return {
			"hour_z": -((hr) + mn / 60.0 + sc / 3600.0) * (TAU / 12.0),
			"min_z": -(mn + sc / 60.0) * (TAU / 60.0),
		}
	var sys_time := Time.get_time_dict_from_system()
	var hr_w: float = float(sys_time.hour)
	var mn_w: float = float(sys_time.minute)
	var sc_w: float = float(sys_time.second)
	return {
		"hour_z": -((int(hr_w) % 12) + mn_w / 60.0 + sc_w / 3600.0) * (TAU / 12.0),
		"min_z": -(mn_w + sc_w / 60.0) * (TAU / 60.0),
	}


# Shape-aware mineral spot on interior glass near the meniscus.
static func pick_glass_mineral_position(fp: TankFootprint, water_y: float,
		tank_half_w: float, tank_half_d: float, rng: RandomNumberGenerator) -> Vector3:
	var y: float = water_y - rng.randf_range(0.04, 0.40)
	var inset: float = 0.04
	match fp.shape:
		"cylinder", "sphere":
			var ang: float = rng.randf() * TAU
			var rad: float = fp.radius_at_height(y, inset)
			return Vector3(cos(ang) * (rad - inset), y, sin(ang) * (rad - inset))
		"hex", "triangle":
			var corners: Array[Vector3] = fp.footprint_corners(24)
			if corners.is_empty():
				return Vector3.ZERO
			var i0: int = rng.randi() % corners.size()
			var i1: int = (i0 + 1) % corners.size()
			var edge: Vector3 = (corners[i0] as Vector3).lerp(corners[i1] as Vector3,
				rng.randf_range(0.12, 0.88))
			return Vector3(edge.x * 0.98, y, edge.z * 0.98)
		_:
			var wall_pick: int = rng.randi() % 4
			var x: float = 0.0
			var z: float = 0.0
			match wall_pick:
				0:
					x = rng.randf_range(-tank_half_w + 0.5, tank_half_w - 0.5)
					z = -tank_half_d + inset
				1:
					x = rng.randf_range(-tank_half_w + 0.5, tank_half_w - 0.5)
					z = tank_half_d - inset
				2:
					x = -tank_half_w + inset
					z = rng.randf_range(-tank_half_d + 0.5, tank_half_d - 0.5)
				_:
					x = tank_half_w - inset
					z = rng.randf_range(-tank_half_d + 0.5, tank_half_d - 0.5)
			return Vector3(x, y, z)


# Substrate ripple direction/strength from aeration anchor to jet (surface pop / spout).
static func substrate_flow_from_jet(origin: Vector3, jet: Vector3,
		flow_rate: float) -> Dictionary:
	var dx: float = jet.x - origin.x
	var dz: float = jet.z - origin.z
	var dir := Vector2(dx, dz)
	if dir.length_squared() < 1e-4:
		dir = Vector2(0.0, 1.0)
	else:
		dir = dir.normalized()
	var strength: float = clampf(0.10 + flow_rate * 0.14, 0.08, 0.42)
	return {"dir": dir, "strength": strength}
