# Pure-visual helpers — biotope palettes, health grade, beauty defaults, colorblind LUTs.
class_name AestheticsRuntime
extends RefCounted

# First-launch curated look (#99). Does not override saved render prefs once applied.
const BEAUTY_DEFAULTS: Dictionary = {
	"render_width": 512,
	"render_height": 288,
	"outline_strength": 0.14,
	"dither_strength": 0.88,
	"dither_region_aware": true,
	"palette_bank_lock": true,
	"pp_vignette_strength": 0.26,
	"pp_vignette_falloff": 1.55,
	"pp_bloom_strength": 0.72,
	"pp_bloom_threshold": 0.70,
	"lighting_preset": "sunset",
	"sunset_drama": 0.82,
	"light_caustics": true,
}


static func apply_first_launch_defaults(cfg: Node) -> void:
	if cfg == null or bool(cfg.get("beauty_defaults_applied")):
		return
	for key: String in BEAUTY_DEFAULTS:
		cfg.set(key, BEAUTY_DEFAULTS[key])
	cfg.set("beauty_defaults_applied", true)
	if cfg.has_method("apply_lighting_preset"):
		cfg.apply_lighting_preset(String(BEAUTY_DEFAULTS["lighting_preset"]))


# Extended biotope key — maps tank preset strings to one of the 48-color LUTs.
static func biotope_palette_key(cfg: Variant) -> String:
	if cfg == null:
		return "planted"
	var preset_l := ""
	if cfg is Dictionary:
		preset_l = String((cfg as Dictionary).get("tank_preset", "")).to_lower()
	else:
		var pv: Variant = cfg.get("tank_preset") if cfg.has_method("get") else null
		if pv != null:
			preset_l = String(pv).to_lower()
		if cfg.has_method("current_tank_preset"):
			var p: Variant = cfg.current_tank_preset()
			if p is Dictionary:
				var pd: Dictionary = p
				if bool(pd.get("is_saltwater", false)):
					return "reef"
				var tags: Variant = pd.get("tags", [])
				if tags is Array:
					for t in tags:
						var ts := String(t).to_lower()
						if ts.find("reef") != -1 or ts.find("marine") != -1:
							return "reef"
						if ts.find("brackish") != -1:
							return "brackish"
						if ts.find("temperate") != -1 or ts.find("cold") != -1:
							return "temperate"
	return biotope_palette_key_from_preset(preset_l)


static func biotope_palette_key_from_preset(preset_l: String) -> String:
	preset_l = preset_l.to_lower()
	if preset_l.find("reef") != -1 or preset_l.find("polyp") != -1 \
			or preset_l.find("marine") != -1 or preset_l.find("salt") != -1:
		return "reef"
	if preset_l.find("brackish") != -1 or preset_l.find("estuary") != -1:
		return "brackish"
	if preset_l.find("tanganyika") != -1 or preset_l.find("malawi") != -1 \
			or preset_l.find("rift") != -1 or preset_l.find("cichlid") != -1:
		return "tanganyika_rock"
	if preset_l.find("amazon") != -1 or preset_l.find("discus") != -1 \
			or preset_l.find("angelfish") != -1 or preset_l.find("clearwater") != -1:
		return "amazon_clearwater"
	if preset_l.find("blackwater") != -1 or preset_l.find("tannin") != -1:
		return "blackwater"
	if preset_l.find("peat") != -1 or preset_l.find("betta") != -1 \
			or preset_l.find("rice") != -1 or preset_l.find("asian") != -1:
		return "asian_peat"
	if preset_l.find("temperate") != -1 or preset_l.find("goldfish") != -1 \
			or preset_l.find("koi") != -1 or preset_l.find("cold") != -1:
		return "temperate"
	if preset_l.find("alkaline") != -1 or preset_l.find("hard") != -1:
		return "hard_alkaline"
	return "planted"


static func fauna_saturation_mult(key: String) -> float:
	match key:
		"blackwater", "asian_peat":
			return 1.18
		"reef", "hard_alkaline", "amazon_clearwater":
			return 1.36
		"tanganyika_rock", "brackish":
			return 1.22
		"temperate":
			return 1.14
		_:
			return 1.30


# 1 = thriving/clear, 0 = stressed/murky — drives palette health grade.
static func health_grade_from_transmittance(transmittance: float) -> float:
	return clampf(transmittance, 0.0, 1.0)


static func ambient_breath(t: float, calm: float = 1.0) -> float:
	return sin(t * 0.35) * 0.012 * clampf(calm, 0.0, 1.0)


# Remap accent slots for color-vision variants while keeping the 48-index layout.
static func remap_palette_hexes(hexes: Array, mode: String) -> Array:
	if mode == "none" or mode.is_empty():
		return hexes
	var out: Array = []
	out.resize(hexes.size())
	for i in hexes.size():
		var c := Color.from_string("#" + String(hexes[i]), Color.BLACK)
		var h: float = c.h
		var s: float = c.s
		var v: float = c.v
		match mode:
			"protan":
				if h < 0.08 or h > 0.92:
					h = lerpf(h, 0.08, 0.55)
					s = clampf(s * 0.85, 0.0, 1.0)
				elif h > 0.45 and h < 0.72:
					v = clampf(v * 1.06, 0.0, 1.0)
			"deutan":
				if h > 0.22 and h < 0.48:
					h = lerpf(h, 0.12, 0.45)
					s = clampf(s * 0.82, 0.0, 1.0)
			"tritan":
				if h > 0.52 and h < 0.72:
					h = lerpf(h, 0.48, 0.50)
					s = clampf(s * 0.88, 0.0, 1.0)
		out[i] = Color.from_hsv(h, s, v).to_html(false)
	return out


static func apply_pixel_purity(cfg: Node) -> Dictionary:
	if cfg == null or not bool(cfg.get("pixel_purity")):
		return {}
	return {
		"dither_strength": maxf(float(cfg.dither_strength), 0.92),
		"palette_bank_lock": 1.0,
		"region_aware_dither": 1.0,
		"film_grain_strength": 0.08,
	}


# Lavish capture grade — applied briefly around F12 / signature shot (#78).
const PHOTO_MODE_GRADE: Dictionary = {
	"outline_strength": 0.18,
	"pp_bloom_strength": 0.82,
	"pp_bloom_threshold": 0.66,
	"pp_vignette_strength": 0.32,
	"selective_glow_strength": 0.72,
	"film_grain_strength": 0.05,
	"dither_strength": 0.82,
}


# The poster frame — golden hour planted tank (#100).
const SIGNATURE_SHOT: Dictionary = {
	"lighting_preset": "sunset",
	"sunset_drama": 0.92,
	"global_warmth": 0.74,
	"day_phase": 0.46,
	"outline_strength": 0.16,
	"pp_bloom_strength": 0.80,
	"pp_vignette_strength": 0.30,
	"selective_glow_strength": 0.68,
}


static func apply_photo_mode_grade(cfg: Node, on: bool) -> void:
	if cfg == null:
		return
	if on:
		_photo_revert.clear()
		for key: String in PHOTO_MODE_GRADE:
			_photo_revert[key] = cfg.get(key)
			cfg.set(key, PHOTO_MODE_GRADE[key])
	else:
		for key: String in _photo_revert:
			cfg.set(key, _photo_revert[key])
		_photo_revert.clear()


static var _photo_revert: Dictionary = {}


static func apply_signature_shot(cfg: Node, sim: Node) -> void:
	if cfg == null:
		return
	if cfg.has_method("apply_lighting_preset"):
		cfg.apply_lighting_preset(String(SIGNATURE_SHOT["lighting_preset"]))
	for key: String in SIGNATURE_SHOT:
		if key == "lighting_preset" or key == "day_phase":
			continue
		cfg.set(key, SIGNATURE_SHOT[key])
	if sim != null and sim.get("day_phase") != null:
		sim.day_phase = float(SIGNATURE_SHOT["day_phase"])


# UI cohesion tokens sampled from the active 48-set (#91).
static func ui_palette_tokens(hexes: Array) -> Dictionary:
	if hexes.is_empty() or hexes.size() < 40:
		return {}
	var water := Color.from_string("#" + String(hexes[4]), Color(0.3, 0.5, 0.6))
	var green := Color.from_string("#" + String(hexes[12]), Color(0.2, 0.5, 0.3))
	var accent := Color.from_string("#" + String(hexes[36]), Color(0.8, 0.3, 0.2))
	var bg_base := Color(0.06, 0.07, 0.12, 0.92)
	return {
		"bg": bg_base.lerp(water.darkened(0.88), 0.14),
		"border": Color(water.r, water.g, water.b, 0.55).lerp(Color(0.35, 0.45, 0.6, 0.55), 0.35),
		"section": green.lightened(0.35).lerp(Color(0.65, 0.80, 1.0), 0.45),
		"primary_bg": accent.darkened(0.15).lerp(Color(0.22, 0.58, 0.88), 0.55),
		"glass_tint": Color(water.r * 0.12, water.g * 0.14, water.b * 0.18, 0.55),
	}

