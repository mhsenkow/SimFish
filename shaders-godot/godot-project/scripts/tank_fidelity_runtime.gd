# REAL_TANK_FIDELITY_200 — shared helpers for stratified substrate, glass dust,
# grazing tracks, turbidity spikes, photo-mode bundle, and density-cap messaging.
extends RefCounted
class_name TankFidelityRuntime

# Green-dust film on glass (items 21–24). 0..1 coverage; tracks carve clean paths.
var glass_dust: float = 0.0
var dust_panel_bias: float = 0.55  # heavier on light-facing / back panels
var _track_points: Array[Vector4] = []  # xyz = world, w = radius+strength
var _track_fade_t: float = 0.0
var turbidity_spike: float = 0.0
var wipe_cooldown: float = 0.0
var cap_bind_toast_cd: float = 0.0
var last_cap_bind_kind: String = ""

const MAX_TRACKS: int = 24
const GRAVEL_PALETTE: Array[Color] = [
	Color8(220, 204, 174), Color8(184, 158, 122), Color8(108, 112, 122),
	Color8(148, 96, 72), Color8(46, 42, 40), Color8(198, 208, 218),
	Color8(140, 132, 118), Color8(92, 78, 64),
]


static func strata_from_profile(profile: Dictionary, bed_bottom: float, bed_top: float,
		wet_line: float, tank_age_01: float = 0.35) -> Dictionary:
	var colors: Array = profile.get("colors", [])
	var soil: Color = Color8(26, 18, 12)
	var cap: Color = Color8(140, 130, 110)
	if colors.size() >= 2:
		soil = colors[0] as Color
		cap = colors[mini(3, colors.size() - 1)] as Color
	if profile.has("soil_color"):
		var sc: Variant = profile["soil_color"]
		if sc is Color:
			soil = sc
		elif sc is Array and (sc as Array).size() >= 3:
			var a: Array = sc
			soil = Color8(int(a[0]), int(a[1]), int(a[2]))
	if profile.has("cap_color"):
		var cc: Variant = profile["cap_color"]
		if cc is Color:
			cap = cc
		elif cc is Array and (cc as Array).size() >= 3:
			var a2: Array = cc
			cap = Color8(int(a2[0]), int(a2[1]), int(a2[2]))
	var cap_frac: float = float(profile.get("cap_fraction", 0.42))
	return {
		"bed_bottom_y": bed_bottom,
		"bed_top_y": bed_top,
		"cap_fraction": clampf(cap_frac, 0.08, 0.92),
		"soil_color": soil,
		"cap_color": cap,
		"boundary_wave": float(profile.get("boundary_wave", 0.18)),
		"mix_band": float(profile.get("mix_band", 0.30)),
		"anoxic_darken": float(profile.get("anoxic_darken", 0.55)),
		"grain_population": float(profile.get("grain_population", 0.85)),
		"root_density": float(profile.get("root_density", 0.0)),
		"tunnel_strength": float(profile.get("tunnel_strength", 0.0)),
		"detritus_amount": float(profile.get("detritus_amount", 0.25)),
		"bed_age": clampf(tank_age_01, 0.0, 1.0),
		"wet_line_y": wet_line,
		"glass_contact": float(profile.get("glass_contact", 0.7)),
		"gas_pocket": float(profile.get("gas_pocket", 0.12)),
		"slope_hint": float(profile.get("slope_hint", 0.0)),
	}


static func apply_substrate_strata(params: Dictionary) -> void:
	VoxelMat.apply_substrate_strata(params)


static func reference_snail_boost(preset_id: String) -> Dictionary:
	# Item 93 — order-of-magnitude more snails on reference presets.
	match preset_id:
		"snail_bar":
			return {"glass": 28, "trumpet": 14, "ramshorn_bias": 0.15}
		"valli_jungle":
			return {"glass": 36, "trumpet": 8, "ramshorn_bias": 0.72}
		"counter_nano":
			return {"glass": 12, "trumpet": 4, "ramshorn_bias": 0.35}
		_:
			return {}


static func reference_floater_recipe(preset_id: String) -> Dictionary:
	# Items 56–57 — thick multi-species mat for counter_nano.
	match preset_id:
		"counter_nano":
			return {"duckweed": 48, "salvinia": 18, "water_hyacinth": 2, "coverage": 0.72}
		"valli_jungle":
			return {"duckweed": 8, "salvinia": 4, "water_hyacinth": 0, "coverage": 0.12}
		_:
			return {}


static func photo_mode_bundle() -> Dictionary:
	# Items 187–194 — handheld / off-level / DOF / noise / highlight rolloff.
	return {
		"handheld_drift": true,
		"horizon_roll_deg": 1.4,
		"dof_enabled": true,
		"dof_blur_amount": 0.22,
		"macro_min_radius": 2.4,
		"sensor_noise": 0.18,
		"highlight_rolloff": 0.65,
		"photo_mode_enhanced": true,
	}


func tick_glass_dust(dt: float, light: float, nutrients: float, snail_graze: float,
		daylight: float) -> void:
	# Accumulate with light × nutrients; graze clears locally via tracks.
	wipe_cooldown = maxf(0.0, wipe_cooldown - dt)
	var grow: float = (0.0008 + light * 0.0014 + nutrients * 0.0006) * dt
	# Uneven: light-facing / back panels heavier (item 24).
	grow *= lerpf(0.55, 1.25, dust_panel_bias)
	# Daytime grows faster.
	grow *= lerpf(0.45, 1.0, daylight)
	glass_dust = clampf(glass_dust + grow - snail_graze * dt * 0.002, 0.0, 1.0)
	# Fade tracks over hours (item 23) — ~sim hours compressed.
	_track_fade_t += dt
	if _track_fade_t >= 2.5:
		_track_fade_t = 0.0
		var kept: Array[Vector4] = []
		for t in _track_points:
			var w: float = t.w * 0.92
			if w > 0.08:
				kept.append(Vector4(t.x, t.y, t.z, w))
		_track_points = kept
	# Turbidity spike decay (items 48).
	turbidity_spike = maxf(0.0, turbidity_spike - dt * 0.015)


func record_graze_track(world_pos: Vector3, radius: float = 0.18) -> void:
	var pt := Vector4(world_pos.x, world_pos.y, world_pos.z, clampf(radius, 0.08, 0.45))
	_track_points.append(pt)
	while _track_points.size() > MAX_TRACKS:
		_track_points.pop_front()


func wipe_glass(amount: float = 0.85) -> void:
	glass_dust = maxf(0.0, glass_dust * (1.0 - amount))
	_track_points.clear()
	wipe_cooldown = 8.0


func spike_turbidity(amount: float = 0.55) -> void:
	turbidity_spike = clampf(turbidity_spike + amount, 0.0, 1.0)


func track_uniform_array() -> Array:
	var packed: Array = []
	for i in MAX_TRACKS:
		if i < _track_points.size():
			packed.append(_track_points[i])
		else:
			packed.append(Vector4.ZERO)
	return packed


func note_cap_bind(kind: String) -> String:
	# Item 199 — surface when ecology growth is blocked by hard ceiling.
	if kind == last_cap_bind_kind and cap_bind_toast_cd > 0.0:
		return ""
	last_cap_bind_kind = kind
	cap_bind_toast_cd = 45.0
	match kind:
		"snail":
			return "Snail breeding paused — population ceiling reached."
		"plant":
			return "Plant runners held — density ceiling reached."
		"floater":
			return "Floating mat full — floater ceiling reached."
		"shrimp":
			return "Shrimp breeding paused — population ceiling reached."
		"fish":
			return "Stocking at the fish ceiling."
		_:
			return "Population ceiling holding %s back." % kind


func tick_cap_toast(dt: float) -> void:
	cap_bind_toast_cd = maxf(0.0, cap_bind_toast_cd - dt)


static func auto_tune_cap_scale(budget_pressure: float, current: float) -> float:
	# Item 200 — slow decay of effective ceilings under sustained pressure.
	if budget_pressure < 0.55:
		return minf(1.0, current + 0.002)
	if budget_pressure > 0.78:
		return maxf(0.55, current - 0.004 * (budget_pressure - 0.78))
	return current
