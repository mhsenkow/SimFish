# Named dance moves, formations, easing, and genre → choreography profiles.
class_name MusicChoreography
extends RefCounted

const MOVES: Array = [
	"sweep", "spiral", "vortex", "wave", "starburst", "breathe", "sway", "carousel",
	"curtain", "cascade", "fountain", "kickline",
	"mandala", "radial_bloom", "planar_ring", "pinwheel",
]

const FORMATIONS: Array = ["scatter", "line", "v", "circle", "mirror", "heart", "star", "ring", "crescent"]

const GENRE_PROFILES: Dictionary = {
	"ambient": {"tempo_scale": 0.72, "sweep": 0.42, "vertical": 0.28, "easing": "soft", "default_move": "breathe", "formation": "circle", "cast": "bass"},
	"lofi": {"tempo_scale": 0.68, "sweep": 0.38, "vertical": 0.22, "swing_bias": 0.62, "easing": "swing", "default_move": "sway", "formation": "line", "cast": "mid"},
	"trance": {"tempo_scale": 1.0, "sweep": 0.92, "vertical": 0.48, "easing": "snap", "default_move": "sweep", "formation": "v", "cast": "balanced"},
	"dnb": {"tempo_scale": 1.18, "sweep": 0.78, "vertical": 0.55, "easing": "sharp", "default_move": "starburst", "formation": "scatter", "cast": "treble"},
	"pop": {"tempo_scale": 0.95, "sweep": 0.65, "vertical": 0.4, "easing": "bounce", "default_move": "carousel", "formation": "v", "cast": "balanced"},
	"orchestral": {"tempo_scale": 0.8, "sweep": 0.55, "vertical": 0.35, "easing": "soft", "default_move": "wave", "formation": "line", "cast": "sectional"},
}


static func ease_in_out_cubic(t: float) -> float:
	var u: float = clampf(t, 0.0, 1.0)
	if u < 0.5:
		return 4.0 * u * u * u
	return 1.0 - pow(-2.0 * u + 2.0, 3.0) / 2.0


static func ease_out_back(t: float) -> float:
	var u: float = clampf(t, 0.0, 1.0)
	var c1: float = 1.70158
	var c3: float = c1 + 1.0
	return 1.0 + c3 * pow(u - 1.0, 3.0) + c1 * pow(u - 1.0, 2.0)


static func beat_anticipation(beat_phase: float) -> float:
	var p: float = fposmod(beat_phase, 1.0)
	if p > 0.78:
		return ease_in_out_cubic((p - 0.78) / 0.22)
	if p < 0.12:
		return 1.0 - ease_in_out_cubic(p / 0.12)
	return 0.0


static func swing_offset(beat_phase: float, swing: float) -> float:
	if swing <= 0.001:
		return beat_phase
	if int(beat_phase * 4.0) % 2 == 1:
		var sixteenth: float = fposmod(beat_phase * 4.0, 1.0)
		return beat_phase + swing * 0.04 * (1.0 - sixteenth)
	return beat_phase


static func arc_intensity(phrase_state: String, phrase_progress: float) -> float:
	match phrase_state:
		"verse":
			return lerpf(0.48, 0.62, phrase_progress)
		"build":
			return lerpf(0.62, 0.92, phrase_progress)
		"drop":
			return 1.0
		"breakdown":
			return lerpf(0.42, 0.28, phrase_progress)
		"chorus":
			return lerpf(0.72, 0.88, phrase_progress)
	return 0.58


static func classify_genre(tempo: float, energy: float, danceability: float, valence: float) -> String:
	if tempo < 95.0 and energy < 0.42:
		return "ambient"
	if tempo < 108.0 and danceability < 0.62:
		return "lofi"
	if tempo > 165.0 and energy > 0.62:
		return "dnb"
	if tempo > 128.0 and energy > 0.5 and danceability > 0.55:
		return "trance"
	if valence > 0.58 and danceability > 0.6:
		return "pop"
	if energy < 0.5 and valence < 0.45:
		return "orchestral"
	return "pop"


static func profile_for_genre(genre: String) -> Dictionary:
	return GENRE_PROFILES.get(genre, GENRE_PROFILES["pop"]).duplicate()


static func pick_move(
	phrase_state: String,
	energy: float,
	genre: String,
	_seed: int,
	overhead: bool = false,
) -> String:
	if overhead:
		return TopdownMotion.pick_move_overhead(phrase_state, energy, genre, _seed)
	var profile: Dictionary = profile_for_genre(genre)
	match phrase_state:
		"build":
			return "fountain" if energy > 0.35 else "curtain"
		"drop":
			return "fountain" if energy > 0.5 else "starburst"
		"breakdown":
			return "breathe"
		"chorus":
			return String(profile.get("default_move", "sweep"))
	if energy < 0.32:
		return "breathe"
	if energy > 0.72:
		return "vortex"
	var choices: Array = [
		String(profile.get("default_move", "sweep")),
		"wave",
		"carousel",
	]
	return String(choices[_seed % choices.size()])


static func pick_formation(
	phrase_state: String,
	genre: String,
	move: String,
	rng_seed: int = 0,
	overhead: bool = false,
	valence: float = 0.5,
) -> String:
	if overhead:
		return TopdownMotion.pick_formation_overhead(phrase_state, genre, move, rng_seed, valence)
	if move == "kickline":
		return "line"
	if move == "fountain" and phrase_state == "build":
		return "circle"
	var profile: Dictionary = profile_for_genre(genre)
	match phrase_state:
		"build":
			return "circle"
		"drop":
			return "scatter"
		"breakdown":
			return "line"
		"chorus":
			if move in ["sweep", "carousel", "wave"]:
				var shapes: Array = ["heart", "star", "ring"]
				return String(shapes[rng_seed % shapes.size()])
			return "mirror"
	if move in ["vortex", "starburst"]:
		return "circle"
	if move in ["wave", "carousel"]:
		return "v"
	return String(profile.get("formation", "scatter"))


static func choir_for_instance(instance_id: int) -> int:
	return int(instance_id) % 2


static func choir_active(choir: int, bar_phase: float) -> bool:
	var half: int = int(bar_phase * 2.0) % 2
	return choir == half


static func is_soloist(lead_score: float, phrase_state: String) -> bool:
	return lead_score > 0.68 and phrase_state == "chorus"


static func species_modifiers(swim_pattern: String) -> Dictionary:
	match swim_pattern:
		"dart":
			return {"sweep": 1.08, "speed": 1.05, "vertical": 0.58, "wander": 0.95}
		"hover":
			return {"sweep": 0.52, "speed": 0.78, "vertical": 1.18, "wander": 0.65}
		"shuffle":
			return {"sweep": 0.62, "speed": 0.88, "vertical": 0.38, "wander": 0.95}
		"cruise":
			return {"sweep": 1.08, "speed": 0.92, "vertical": 0.55}
		"meander":
			return {"sweep": 0.75, "speed": 0.82, "vertical": 0.48, "wander": 1.25}
		"shoal":
			return {"sweep": 0.95, "speed": 1.05, "vertical": 0.52, "tightness": 1.08}
	return {"sweep": 1.0, "speed": 1.0, "vertical": 1.0}


static func personality_modifiers(boldness: float, calm: float, gluttony: float) -> Dictionary:
	var out: Dictionary = {"sweep": 1.0, "tightness": 1.0, "dart_chance": 1.0, "solo_bias": 0.0}
	if boldness > 0.68:
		out.sweep = 1.18
		out.solo_bias = 0.25
		out.dart_chance = 1.2
	elif boldness < 0.32:
		out.sweep = 0.58
		out.tightness = 1.22
	if calm > 0.7:
		out.sweep *= 0.88
	if gluttony > 0.72:
		out.sweep *= 0.72
		out.dart_chance *= 0.65
	return out


static func section_leader_lag(instance_id: int) -> float:
	if instance_id % 7 == 0:
		return 0.0
	return 0.5


static func mouth_staging_y(mouth_orientation: int, y_min: float, y_max: float) -> float:
	match mouth_orientation:
		-1:
			return y_max - 0.28
		1:
			return y_min + 0.38
	return lerpf(y_min + 0.35, y_max - 0.25, 0.5)


static func formation_offset(
	formation: String,
	slot: int,
	total_slots: int,
	hw: float,
	hd: float,
	y_band: float,
	mirror: bool = false,
	fish_count: int = 24,
) -> Vector3:
	var slots: int = TopdownMotion.formation_slot_count(fish_count)
	total_slots = maxi(total_slots, slots)
	var pop_scale: float = clampf(float(fish_count) / 24.0, 0.85, 1.65)
	hw *= pop_scale
	hd *= pop_scale
	var n: float = maxf(float(total_slots), 1.0)
	var t: float = float(slot) / maxf(n - 1.0, 1.0)
	var off := Vector3.ZERO
	match formation:
		"line":
			off = Vector3(lerpf(-hw * 0.82, hw * 0.82, t), y_band, -hd * 0.15)
		"v":
			var row: float = float(slot) / 2.0 / maxf(n * 0.5, 1.0)
			var side: float = 1.0 if slot % 2 == 0 else -1.0
			off = Vector3(side * row * hw * 0.78, y_band, -row * hd * 0.62)
		"circle":
			var ang: float = float(slot) / n * TAU
			off = Vector3(cos(ang) * hw * 0.62, y_band, sin(ang) * hd * 0.62)
		"mirror":
			var half: float = 1.0 if slot % 2 == 0 else -1.0
			off = Vector3(half * absf(sin(t * TAU)) * hw * 0.55, y_band, cos(t * TAU) * hd * 0.45)
		"heart":
			var ang_h: float = float(slot) / n * TAU
			var hx: float = 16.0 * pow(sin(ang_h), 3.0)
			var hy: float = 13.0 * cos(ang_h) - 5.0 * cos(2.0 * ang_h) \
				- 2.0 * cos(3.0 * ang_h) - cos(4.0 * ang_h)
			off = Vector3(hx * hw * 0.04, y_band, hy * hd * 0.035)
		"star":
			var ang_s: float = float(slot) / n * TAU
			var star_r: float = 0.52 + 0.48 * absf(cos(5.0 * ang_s))
			off = Vector3(cos(ang_s) * hw * star_r * 0.52, y_band, sin(ang_s) * hd * star_r * 0.52)
		"ring":
			var ang_r: float = float(slot) / n * TAU
			var size_r: float = TopdownMotion.formation_size_radius_mult(slot, total_slots)
			off = Vector3(cos(ang_r) * hw * 0.72 * size_r, y_band, sin(ang_r) * hd * 0.72 * size_r)
		"donut":
			var ang_d: float = float(slot) / n * TAU
			var band: float = 0.74 + float(slot % 5) * 0.028
			off = Vector3(cos(ang_d) * hw * band, y_band, sin(ang_d) * hd * band)
		"crescent":
			var ang_c: float = float(slot) / n * PI * 1.35 - PI * 0.675
			off = Vector3(cos(ang_c) * hw * 0.68, y_band, sin(ang_c) * hd * 0.55)
		_:
			var ang2: float = float(slot % 360) * (TAU / 360.0)
			off = Vector3(cos(ang2) * hw * 0.5, y_band, sin(ang2) * hd * 0.5)
	if mirror and slot % 2 == 1:
		off.x *= -1.0
	return off


static func depth_stage_y(
	phrase_state: String,
	phrase_progress: float,
	y_min: float,
	y_max: float,
	home_y: float,
	vertical_strength: float,
	mouth_orientation: int = 0,
) -> float:
	var mid: float = lerpf(y_min + 0.35, y_max - 0.25, 0.5)
	var mouth_y: float = mouth_staging_y(mouth_orientation, y_min, y_max)
	var staged: float
	match phrase_state:
		"build":
			staged = lerpf(home_y, y_max - 0.35, ease_in_out_cubic(phrase_progress) * vertical_strength)
		"drop":
			staged = lerpf(y_max - 0.35, mid, ease_out_back(phrase_progress) * vertical_strength)
		"breakdown":
			staged = lerpf(mid, y_min + 0.45, phrase_progress * vertical_strength)
		"chorus":
			staged = lerpf(home_y, mid + 0.25, vertical_strength * 0.55)
		_:
			staged = lerpf(home_y, mid, vertical_strength * 0.45)
	if mouth_orientation != 0:
		staged = lerpf(staged, mouth_y, clampf(vertical_strength * 0.42, 0.0, 0.72))
	return staged


static func mood_palette(valence: float, mode: String, energy: float, key: int = 0) -> Dictionary:
	var major: bool = mode != "minor" and valence > 0.48
	var key_hue: float = float(key) / 12.0 * 0.14
	return {
		"hue": (valence - 0.5) * 0.12 + (0.03 if major else -0.04) + key_hue * 0.5,
		"sat": lerpf(1.0, 1.06, energy * 0.35),
		"warmth": (valence - 0.35) * 0.28 if major else -0.08,
		"val": lerpf(1.0, 1.04, energy * 0.22),
	}


static func rotate_xz(v: Vector3, yaw: float) -> Vector3:
	if absf(yaw) < 0.001:
		return v
	var c: float = cos(yaw)
	var s: float = sin(yaw)
	return Vector3(v.x * c - v.z * s, v.y, v.x * s + v.z * c)


static func species_band(species: String, swim_pattern: String) -> String:
	var sp: String = species.to_lower()
	if swim_pattern in ["shuffle", "hover"] or "pleco" in sp or "cory" in sp or "snail" in sp:
		return "bass"
	if swim_pattern == "dart" or "tetra" in sp or "neon" in sp or "rasbora" in sp:
		return "high"
	if swim_pattern == "cruise" or "betta" in sp or "angelfish" in sp:
		return "mid"
	return "mid"


static func band_drive(band: String, bass: float, mid: float, high: float) -> float:
	match band:
		"bass": return bass
		"high", "treble": return high
	return mid


# ---- Playbook: casting + universal feature→motion (#11, #12–18, #37) ----

static func color_hue_band(base_color: Color) -> String:
	var h: float = base_color.h
	if h < 0.12 or h > 0.92:
		return "bass"
	if h < 0.38:
		return "bass"
	if h < 0.58:
		return "mid"
	return "treble"


static func vertical_column(preferred_y: float, y_min: float, y_max: float) -> String:
	var span: float = maxf(y_max - y_min, 0.5)
	var t: float = clampf((preferred_y - y_min) / span, 0.0, 1.0)
	if t < 0.34:
		return "bass"
	if t > 0.66:
		return "treble"
	return "mid"


static func size_stroke_subdiv(growth_factor: float) -> float:
	if growth_factor >= 1.25:
		return 0.5
	if growth_factor <= 0.82:
		return 2.0
	return 1.0


static func species_section(species: String, swim_pattern: String) -> Dictionary:
	var sp: String = species.to_lower()
	if "tetra" in sp or "neon" in sp or "rasbora" in sp or swim_pattern == "dart":
		return {"section": "shimmer", "move_bias": "wave", "expressive": 0.55}
	if "cory" in sp or "pleco" in sp or swim_pattern in ["shuffle", "hover"]:
		return {"section": "floor", "move_bias": "sway", "expressive": 0.35}
	if "hatchet" in sp or swim_pattern == "dart":
		return {"section": "surface", "move_bias": "carousel", "expressive": 0.5}
	if "betta" in sp or "gourami" in sp or swim_pattern == "cruise":
		return {"section": "melody", "move_bias": "breathe", "expressive": 0.85}
	if swim_pattern in ["school", "shoal"]:
		return {"section": "corps", "move_bias": "sweep", "expressive": 0.4}
	return {"section": "ensemble", "move_bias": "sweep", "expressive": 0.5}


static func assign_music_role(traits: Dictionary, instance_id: int) -> Dictionary:
	var species: String = String(traits.get("species", ""))
	var swim_pattern: String = String(traits.get("swim_pattern", "school"))
	var growth_factor: float = float(traits.get("growth_factor", 1.0))
	var preferred_y: float = float(traits.get("preferred_y", 3.5))
	var y_min: float = float(traits.get("y_min", 0.5))
	var y_max: float = float(traits.get("y_max", 8.0))
	var base_color: Color = traits.get("base_color", Color.WHITE)
	var vibrancy: float = float(traits.get("color_vibrancy", 0.5))
	var lead_score: float = float(traits.get("lead_score", 0.0))
	var finnage: float = float(traits.get("finnage", 1.0))
	var mouth_orientation: int = int(traits.get("mouth_orientation", 0))
	var boldness: float = float(traits.get("boldness", 0.5))
	var section: Dictionary = species_section(species, swim_pattern)
	var role: String = "ensemble"
	if vibrancy > 0.68 and lead_score > 0.58:
		role = "soloist"
	elif String(section.get("section", "")) == "corps":
		role = "corps"
	var color_band: String = color_hue_band(base_color)
	var warm: bool = base_color.h < 0.45 or base_color.r > base_color.b * 1.15
	return {
		"column": vertical_column(preferred_y, y_min, y_max),
		"color_band": color_band,
		"section": String(section.get("section", "ensemble")),
		"move_bias": String(section.get("move_bias", "sweep")),
		"register": size_stroke_subdiv(growth_factor),
		"stroke_subdiv": size_stroke_subdiv(growth_factor),
		"choir": choir_for_instance(instance_id),
		"choir_warm": warm,
		"role": role,
		"finnage": finnage,
		"mouth": mouth_orientation,
		"expressive": float(section.get("expressive", 0.5)) * lerpf(0.7, 1.25, finnage * 0.35),
		"improv": boldness,
		"hue": base_color.h,
	}


static func role_band_drive(role: Dictionary, bass: float, mid: float, high: float) -> float:
	var color_band: String = String(role.get("color_band", "mid"))
	var column: String = String(role.get("column", "mid"))
	var c_drive: float = band_drive(color_band, bass, mid, high)
	var col_drive: float = band_drive(column, bass, mid, high)
	return clampf(c_drive * 0.62 + col_drive * 0.38, 0.08, 1.0)


static func column_vertical_bias(role: Dictionary, energy: float, brightness: float) -> float:
	var column: String = String(role.get("column", "mid"))
	var lift: float = (brightness - 0.5) * 0.28 * energy
	match column:
		"bass": return -0.12 * energy + lift * 0.35
		"treble": return 0.14 * energy + lift
	return lift * 0.55


static func cast_emphasis_for_genre(genre: String, role: Dictionary) -> float:
	var profile: Dictionary = profile_for_genre(genre)
	var emphasis: String = String(profile.get("cast", "balanced"))
	var column: String = String(role.get("column", "mid"))
	match emphasis:
		"bass": return 1.22 if column == "bass" else 0.72
		"treble": return 1.22 if column == "treble" else 0.72
		"mid": return 1.15 if column == "mid" else 0.85
		"sectional": return 1.08
	return 1.0


# Universal feature→motion table (#37). Returns locomotion overlays for fish.gd.
static func universal_locomotion_mods(ctx: Dictionary, role: Dictionary, intensity: float) -> Dictionary:
	var tempo: float = clampf(float(ctx.get("tempo", 120.0)), 72.0, 190.0)
	var subdiv: float = float(role.get("stroke_subdiv", 1.0))
	var wag_target: float = tempo / 60.0 * subdiv
	var bass: float = float(ctx.get("bass", 0.0))
	var mid: float = float(ctx.get("mid", 0.0))
	var high: float = float(ctx.get("high", 0.0))
	var energy_env: float = float(ctx.get("energy_env", 0.0))
	var beat_phase: float = float(ctx.get("beat_phase", 0.0))
	var swing: float = float(ctx.get("swing", 0.0))
	var drive: float = role_band_drive(role, bass, mid, high) * intensity
	var expressive: float = float(role.get("expressive", 0.5))
	var onsets: Array = ctx.get("onsets", [])
	var kick: float = 0.0
	var snare: float = 0.0
	var hat: float = 0.0
	if onsets.size() > 0 and onsets[0] is Dictionary:
		kick = float(onsets[0].get("strength", 0.0))
	if onsets.size() > 1 and onsets[1] is Dictionary:
		snare = float(onsets[1].get("strength", 0.0))
	if onsets.size() > 2 and onsets[2] is Dictionary:
		hat = float(onsets[2].get("strength", 0.0))
	var swung_phase: float = swing_offset(beat_phase, swing)
	var glide: float = 1.0 if energy_env < 0.2 else 0.0
	var band: String = String(role.get("color_band", "mid"))
	var kick_hit: float = kick if band == "bass" else kick * 0.35
	var snare_hit: float = snare if band == "mid" else snare * 0.4
	var hat_hit: float = hat if band == "treble" else hat * 0.45
	var wave_tail: float = 0.0
	if String(ctx.get("move", "")) == "wave":
		var slot: float = float(ctx.get("instance_id", 0) % 17) / 17.0
		var wave_front: float = fposmod(beat_phase - slot * 0.65, 1.0)
		if wave_front < 0.09:
			wave_tail = (1.0 - wave_front / 0.09) * drive
	var eye_flash: float = 0.0
	if bool(ctx.get("downbeat", false)):
		eye_flash = clampf(drive * 0.85, 0.0, 1.0)
	return {
		"wag_freq_target": wag_target,
		"tail_amp_extra": clampf(bass * 0.22 * drive * expressive, 0.0, 0.28),
		"pec_flutter": clampf(high * 0.42 * drive + hat_hit * 0.35, 0.0, 0.55),
		"downbeat_pulse": 1.0 if bool(ctx.get("downbeat", false)) else 0.0,
		"kick_thump": clampf(kick_hit * drive, 0.0, 1.0),
		"snare_flick": clampf(snare_hit * drive * expressive, 0.0, 1.0),
		"glide_hold": glide,
		"swung_beat_phase": swung_phase,
		"fin_flare": clampf(maxf(kick_hit, snare_hit) * drive * 0.45, 0.0, 0.35),
		"scale_pulse": clampf(kick_hit * 0.18 + snare_hit * 0.08, 0.0, 0.22) * drive,
		"wave_tail": wave_tail,
		"eye_flash": eye_flash,
	}


static func dance_style_genre(style: String) -> String:
	match style:
		"ballet": return "ambient"
		"frenzy": return "dnb"
		"sway": return "lofi"
		"stately": return "orchestral"
		"bounce": return "pop"
		"sync": return "trance"
	return ""


static func dance_target(
	move: String,
	instance_id: int,
	beat_phase: float,
	bar_phase: float,
	phrase_state: String,
	phrase_progress: float,
	formation: String,
	choir_on: bool,
	soloist: bool,
	tank_half_w: float,
	tank_half_d: float,
	y_min: float,
	y_max: float,
	home_y: float,
	sweep_strength: float,
	vertical_strength: float,
	drop_tension: float,
	camera_yaw: float = 0.0,
	drop_flash: float = 0.0,
	role: Dictionary = {},
	leader_lag: float = 0.0,
	ensemble_dim: float = 1.0,
	mouth_orientation: int = 0,
	bar_count: int = 0,
	fish_count: int = 24,
	overhead: bool = false,
	formation_radius_mult: float = 1.0,
	_treble_shimmer: float = 0.0,
) -> Vector3:
	move = TopdownMotion.effective_move(move, overhead)
	if overhead and choir_on and not soloist:
		move = TopdownMotion.antiphonal_move(move, int(role.get("choir", 0)) % 2)
	beat_phase = fposmod(beat_phase - leader_lag, 1.0)
	sweep_strength *= ensemble_dim
	var finish := func(v: Vector3) -> Vector3:
		return rotate_xz(v, camera_yaw)
	if not choir_on and not soloist and formation != "scatter":
		sweep_strength *= 0.35

	var lane: float = beat_phase * TAU + float(instance_id % 997) * 0.17
	var eased_bar: float = ease_in_out_cubic(bar_phase)
	var hw: float = tank_half_w * 0.96 * maxf(formation_radius_mult, 0.55)
	var hd: float = tank_half_d * 0.96 * maxf(formation_radius_mult, 0.55)
	var slots: int = TopdownMotion.formation_slot_count(fish_count)
	var slot: int = instance_id % slots
	var y_stage: float = depth_stage_y(
		phrase_state, phrase_progress, y_min, y_max, home_y, vertical_strength, mouth_orientation)
	var form_base: Vector3 = formation_offset(
		formation, slot, slots, hw, hd, y_stage, formation == "mirror" or phrase_state == "chorus", fish_count)
	if overhead and formation != "scatter":
		var col: String = String(role.get("column", "mid"))
		var eq: float = TopdownMotion.visual_eq_radius_mult(col)
		form_base.x *= eq
		form_base.z *= eq
		if formation in ["circle", "star", "ring", "heart"]:
			form_base = TopdownMotion.symmetry_snap_xz(form_base)
		if formation in ["circle", "ring"] and role.has("hue"):
			var ang: float = TopdownMotion.color_wheel_angle(float(role.get("hue", 0.0)), slot, slots)
			var rad: float = Vector2(form_base.x, form_base.z).length()
			form_base.x = cos(ang) * rad
			form_base.z = sin(ang) * rad

	if soloist:
		var solo_ang: float = bar_phase * TAU * 0.5
		var solo_r: float = 0.28 if overhead else 0.35
		var solo_y: float = y_stage if overhead else y_stage + sin(bar_phase * TAU * 0.35) * 0.22
		return finish.call(Vector3(sin(solo_ang) * hw * solo_r, solo_y + (0.05 if overhead else 0.35), cos(solo_ang) * hd * solo_r))

	match move:
		"spiral":
			var r: float = lerpf(0.18 if overhead else 0.35, 0.95 if overhead else 0.92,
				phrase_progress + drop_tension * (0.55 if overhead else 0.35))
			if phrase_state == "build":
				r = lerpf(r, 0.22, phrase_progress * 0.65)
			var spiral := Vector3(sin(lane * 1.6) * hw * r, y_stage if overhead else y_stage, cos(lane * 1.6) * hd * r)
			return finish.call(spiral.lerp(form_base, 0.35))
		"vortex":
			var column: String = String(role.get("column", "mid"))
			var spin_speed: float = 2.2
			var torus: float = lerpf(0.45, 0.78, sweep_strength)
			if overhead:
				torus = lerpf(0.55, 0.92, sweep_strength)
			if overhead and choir_on:
				spin_speed *= TopdownMotion.counter_rotate_sign(int(role.get("choir", 0)) % 2)
			match column:
				"bass":
					spin_speed = 1.05
					torus = 0.38
				"treble":
					spin_speed = 3.15
					torus = 0.58
			var spin: float = lane * spin_speed + eased_bar * TAU
			var eye: float = 0.12 if overhead else 0.0
			return finish.call(Vector3(sin(spin) * hw * torus * (1.0 - eye), y_stage, cos(spin) * hd * torus * (1.0 - eye)))
		"wave":
			var axis: float = float(instance_id % 17) / 17.0
			var ripple: float = sin(lane - axis * TAU * 2.0) * 0.5 + 0.5
			var lane_x: float = lerpf(-hw * 0.7, hw * 0.7, axis)
			if bar_count % 2 == 1:
				lane_x = -lane_x
			return finish.call(Vector3(
				lane_x,
				y_stage + ripple * 0.45,
				sin(lane * 0.9 + axis * 3.0) * hd * (0.55 + ripple * 0.35),
			))
		"starburst":
			var burst: float = ease_out_back(1.0 - beat_phase) if beat_phase > 0.02 else 1.0
			var ang: float = float(instance_id % 360) * (TAU / 360.0)
			var rad: float = lerpf(0.2, 1.0, burst) * sweep_strength
			return finish.call(Vector3(cos(ang) * hw * rad, y_stage, sin(ang) * hd * rad))
		"breathe":
			var breath: float = sin(bar_phase * TAU) * 0.5 + 0.5
			var expand: float = lerpf(0.42, 0.88, breath)
			if overhead:
				return finish.call(Vector3(
					form_base.x * expand, y_stage, form_base.z * expand))
			return finish.call(form_base + Vector3(sin(lane * 0.7) * hw * expand * 0.35, 0.0, cos(lane * 0.65) * hd * expand * 0.35))
		"curtain":
			var rise: float = ease_in_out_cubic(phrase_progress + drop_tension * 0.25)
			if phrase_state == "verse" and phrase_progress < 0.22:
				rise = ease_in_out_cubic(phrase_progress / 0.22)
			elif phrase_state == "breakdown" or phrase_progress > 0.82:
				rise = 1.0 - ease_in_out_cubic(clampf((phrase_progress - 0.82) / 0.18, 0.0, 1.0))
			return finish.call(Vector3(form_base.x * 0.65, lerpf(y_min + 0.4, y_max - 0.3, rise), form_base.z * 0.65))
		"cascade":
			var fall: float = ease_in_out_cubic(phrase_progress)
			var stagger: float = float(slot % 8) / 8.0
			return finish.call(Vector3(form_base.x, lerpf(y_max - 0.2, y_min + 0.5, fall + stagger * 0.08), form_base.z))
		"sway":
			var lazy: float = sin(lane * 0.55 + bar_phase * PI) * 0.5 + 0.5
			return finish.call(form_base + Vector3(sin(lane * 0.45) * hw * 0.22 * lazy, 0.0, cos(lane * 0.38) * hd * 0.18))
		"carousel":
			var band: String = String(role.get("color_band", "mid"))
			var car_speed: float = 1.0
			var radius: float = 0.75
			if formation == "circle":
				radius = lerpf(0.42, 0.88, float(slot % 8) / 8.0)
			match band:
				"bass":
					radius = minf(radius, 0.42)
					car_speed = 0.58
				"treble":
					radius = maxf(radius, 0.88)
					car_speed = 1.42
			var car: float = bar_phase * TAU * car_speed + float(instance_id % 13) * 0.4
			return finish.call(Vector3(sin(car) * hw * radius, y_stage, cos(car) * hd * radius))
		"fountain":
			var center := Vector3(0.0, lerpf(y_min + 0.35, y_max - 0.55, 0.5), 0.0)
			if phrase_state == "build":
				var gather: float = ease_in_out_cubic(phrase_progress)
				return finish.call(form_base.lerp(center, gather * 0.82))
			var erupt: float = ease_out_back(clampf(drop_flash + drop_tension, 0.0, 1.0))
			var burst_y: float = lerpf(y_min + 0.4, y_max - 0.15, erupt)
			var spread: float = lerpf(0.15, 1.0, erupt) * sweep_strength
			return finish.call(Vector3(
				form_base.x * spread,
				lerpf(center.y, burst_y, erupt),
				form_base.z * spread,
			))
		"kickline":
			var seq: float = float(slot % 12) / 12.0
			var bob: float = sin((beat_phase - seq) * TAU) * 0.5 + 0.5
			var line_x: float = lerpf(-hw * 0.78, hw * 0.78, seq)
			return finish.call(Vector3(line_x, y_stage + bob * 0.38 * sweep_strength, form_base.z * 0.35))
		"mandala":
			var petals: int = clampi(int(lerpf(4.0, 10.0, sweep_strength + drop_tension * 0.35)), 4, 10)
			var petal_i: int = slot % petals
			var petal_ang: float = float(petal_i) / float(petals) * TAU + bar_phase * TAU * 0.35
			var petal_r: float = lerpf(0.28, 0.82, sin(lane * 0.5) * 0.5 + 0.5)
			return finish.call(Vector3(cos(petal_ang) * hw * petal_r, y_stage, sin(petal_ang) * hd * petal_r))
		"radial_bloom":
			var bloom: float = ease_out_back(clampf(drop_flash + drop_tension + phrase_progress * 0.5, 0.0, 1.0))
			var ang_b: float = float(instance_id % 360) * (TAU / 360.0)
			var rad_b: float = lerpf(0.12, 1.0, bloom) * sweep_strength
			return finish.call(Vector3(cos(ang_b) * hw * rad_b, y_stage, sin(ang_b) * hd * rad_b))
		"planar_ring":
			var ring_t: float = ease_in_out_cubic(phrase_progress)
			var ring_r: float = lerpf(0.25, 0.88, ring_t)
			var ang_p: float = float(slot) / float(slots) * TAU
			return finish.call(Vector3(cos(ang_p) * hw * ring_r, y_stage, sin(ang_p) * hd * ring_r))
		"pinwheel":
			var pin_ang: float = float(slot) / float(slots) * TAU + bar_phase * TAU * 1.4
			var pin_r: float = lerpf(0.35, 0.78, sweep_strength)
			return finish.call(Vector3(cos(pin_ang) * hw * pin_r, y_stage, sin(pin_ang) * hd * pin_r))
		_:
			if formation == "v" and phrase_state in ["chorus", "build"]:
				var fly: float = ease_in_out_cubic(phrase_progress)
				return finish.call(Vector3(
					lerpf(-hw * 0.9, hw * 0.9, fly),
					y_stage if overhead else y_stage,
					lerpf(hd * 0.55, -hd * 0.35, fly) + sin(lane) * hd * 0.12,
				))
			if overhead and move == "sweep":
				var band_z: float = lerpf(-hd * 0.75, hd * 0.75, eased_bar)
				var band_x: float = sin(lane * 0.45 + bar_phase * TAU) * hw * 0.15
				return finish.call(Vector3(band_x, y_stage, band_z))
			var ty: float = lerpf(y_min + 0.35, y_max - 0.25, clampf(0.5 + sin(lane * 1.35) * 0.44, 0.08, 0.92))
			ty = lerpf(y_stage, ty, clampf(0.35 + sweep_strength * 0.65, 0.0, 1.0))
			return finish.call(Vector3(sin(lane) * hw, ty, cos(lane * 0.81 + 0.9) * hd).lerp(form_base, 0.28))
