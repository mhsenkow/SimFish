# Top-down / pond-mode motion, dance, surface, and flock helpers.
# Pure static API — no hidden side effects (ENGINEERING_EXCELLENCE §32).
# Implements TOPDOWN_MOTION_IDEAS.md items wired from main, fish, world,
# music_choreography, and music_context.
class_name TopdownMotion
extends RefCounted

const PREFS_SECTION := "topdown"
const PREFS_POND_HINT := "pond_view_hint_shown"

enum Phrase {
	VERSE,
	BUILD,
	DROP,
	BREAKDOWN,
	CHORUS,
}

enum EqColumn {
	BASS,
	MID,
	TREBLE,
}

# --- Pond mode state (main.gd toggles) ---
static var pond_active: bool = false
static var overhead_yaw_spin: bool = false
static var pond_bowl_vignette: bool = false

const HORIZONTAL_MOVES: Array[String] = [
	"sweep", "spiral", "vortex", "wave", "starburst", "breathe", "sway",
	"carousel", "kickline", "mandala", "radial_bloom", "planar_ring", "pinwheel",
]
const VERTICAL_MOVES: Array[String] = ["curtain", "cascade", "fountain"]
const PLANAR_FORMATIONS: Array[String] = [
	"heart", "star", "ring", "circle", "v", "mirror", "donut", "crescent",
]

const MOVE_LEGIBILITY: Dictionary = {
	"sweep": 0.92, "spiral": 0.98, "vortex": 0.95, "wave": 0.88,
	"starburst": 0.94, "breathe": 0.72, "sway": 0.80, "carousel": 0.90,
	"kickline": 0.75, "mandala": 1.0, "radial_bloom": 0.96,
	"planar_ring": 0.93, "pinwheel": 0.91,
	"curtain": 0.18, "cascade": 0.22, "fountain": 0.25,
}

const _PHRASE_POOLS: Dictionary = {
	"build": ["spiral", "mandala", "carousel", "planar_ring"],
	"drop": ["starburst", "radial_bloom", "vortex", "pinwheel"],
	"breakdown": ["breathe", "sway"],
	"chorus": ["mandala", "spiral", "carousel", "wave", "sweep"],
	"verse": ["sweep", "wave", "carousel", "spiral"],
}


class KeyGeometry:
	var radius: float = 1.0
	var rotation: float = 1.0
	var tightness: float = 1.0


class PathSignature:
	var wander_amp: float = 1.0
	var wander_freq: float = 1.55
	var turn_mult: float = 1.0
	var straight_bias: float = 0.52


class ColorSpill:
	var rgb: Vector3 = Vector3.ZERO
	var gain: float = 0.0


class ConductResult:
	var move: String = "sweep"
	var formation: String = "circle"
	var center: Vector3 = Vector3.ZERO
	var radius: float = 1.0


static func phrase_from_string(state: String) -> Phrase:
	match state:
		"build":
			return Phrase.BUILD
		"drop":
			return Phrase.DROP
		"breakdown":
			return Phrase.BREAKDOWN
		"chorus":
			return Phrase.CHORUS
		_:
			return Phrase.VERSE


static func phrase_to_string(phrase: Phrase) -> String:
	match phrase:
		Phrase.BUILD:
			return "build"
		Phrase.DROP:
			return "drop"
		Phrase.BREAKDOWN:
			return "breakdown"
		Phrase.CHORUS:
			return "chorus"
		_:
			return "verse"


static func eq_column_from_string(column: String) -> EqColumn:
	match column:
		"bass":
			return EqColumn.BASS
		"treble":
			return EqColumn.TREBLE
		_:
			return EqColumn.MID


static func is_overhead_from(projection_id: String, pitch: float) -> bool:
	if projection_id == "top_down_ortho":
		return true
	return pitch > 1.05


static func is_overhead(main_node: Node) -> bool:
	if pond_active:
		return true
	if main_node == null:
		return false
	var projection_id: String = ""
	if main_node.has_method("get_camera_projection_id"):
		projection_id = String(main_node.get_camera_projection_id())
	var pitch: float = float(main_node.get("pitch")) if main_node.get("pitch") != null else 0.0
	return is_overhead_from(projection_id, pitch)


static func move_legibility(move: String) -> float:
	return float(MOVE_LEGIBILITY.get(move, 0.55))


static func effective_move(move: String, overhead: bool) -> String:
	if not overhead:
		return move
	match move:
		"fountain":
			return "radial_bloom"
		"curtain":
			return "planar_ring"
		"cascade":
			return "pinwheel"
		_:
			return move


static func pick_move_overhead(
	phrase_state: String,
	_energy: float,
	_genre: String,
	rng_seed: int,
) -> String:
	var pool: Array = _PHRASE_POOLS.get(phrase_state, _PHRASE_POOLS["verse"])
	if pool.is_empty():
		return "sweep"
	var best: String = String(pool[0])
	var best_score: float = -1.0
	for i in pool.size():
		var m: String = String(pool[i])
		var leg: float = move_legibility(m)
		var tie: float = float((rng_seed + i * 17) % 997) / 997.0
		var score: float = leg * 0.82 + tie * 0.18
		if score > best_score:
			best_score = score
			best = m
	return best


static func pick_formation_overhead(
	phrase_state: String,
	_genre: String,
	move: String,
	rng_seed: int,
	valence: float = 0.5,
) -> String:
	if valence > 0.58 and phrase_state in ["chorus", "verse"]:
		var happy: Array[String] = ["heart", "star", "ring", "donut"]
		return happy[rng_seed % happy.size()]
	if valence < 0.42:
		return "donut" if phrase_state == "drop" else "crescent"
	if move in ["mandala", "spiral", "vortex", "carousel"]:
		var planar: Array[String] = ["star", "ring", "circle"]
		return planar[rng_seed % planar.size()]
	return PLANAR_FORMATIONS[rng_seed % PLANAR_FORMATIONS.size()]


static func formation_morph_blend(
	phrase_bars_left: int,
	bar_phase: float,
	phrase_progress: float,
) -> float:
	if phrase_bars_left <= 0:
		return 1.0
	var u: float = clampf(phrase_progress, 0.0, 1.0)
	# Finish on the downbeat of the last bar (#75).
	if phrase_bars_left == 1:
		u = maxf(u, clampf(bar_phase, 0.0, 1.0))
	return _ease_in_out_cubic(u)


static func formation_slot_count(fish_count: int) -> int:
	return clampi(maxi(fish_count, 8), 8, 48)


static func lerp_formation_offset(
	from_f: String,
	to_f: String,
	slot: int,
	total: int,
	hw: float,
	hd: float,
	y_band: float,
	blend: float,
	fish_count: int = 24,
) -> Vector3:
	var a: Vector3 = MusicChoreography.formation_offset(
		from_f, slot, total, hw, hd, y_band, false, fish_count)
	var b: Vector3 = MusicChoreography.formation_offset(
		to_f, slot, total, hw, hd, y_band, false, fish_count)
	return a.lerp(b, clampf(blend, 0.0, 1.0))


static func key_geometry_bias(key: int, mode: String) -> KeyGeometry:
	var out := KeyGeometry.new()
	var major: bool = mode != "minor"
	out.radius = 1.12 if major else 0.82
	out.rotation = 1.0 if (key % 2) == 0 else -1.0
	out.tightness = 0.88 if major else 1.18
	return out


static func tempo_mill_speed(tempo: float) -> float:
	return clampf(tempo / 120.0, 0.55, 1.65)


static func species_sync_tightness(swim_pattern: String, species: String) -> float:
	var sp: String = species.to_lower()
	if swim_pattern in ["school", "shoal"] or "tetra" in sp or "rasbora" in sp:
		return 0.92
	if "guppy" in sp:
		return 0.55
	if swim_pattern == "dart":
		return 0.48
	return 0.72


static func wake_intensity(speed: float, yaw_rate: float, turning: bool) -> float:
	var base: float = clampf(speed * 0.38, 0.25, 1.35)
	base += clampf(absf(yaw_rate) * 0.22, 0.0, 0.65)
	if turning:
		base *= 1.25
	return base


static func surface_calm_factor(motion_energy: float, is_night: bool) -> float:
	var calm: float = 1.0 - clampf(motion_energy, 0.0, 1.0)
	if is_night:
		calm = maxf(calm, 0.72)
	return clampf(calm, 0.08, 1.0)


static func health_surface_tint(stress: float, cycle_ok: bool) -> float:
	var t: float = 1.0 - clampf(stress, 0.0, 1.0) * 0.45
	if not cycle_ok:
		t *= 0.78
	return clampf(t, 0.42, 1.0)


static func shadow_flash_strength(silver_flash: float, sync_polarization: float) -> float:
	return clampf(silver_flash * (0.55 + sync_polarization * 0.45), 0.0, 1.0)


static func should_show_pond_hint() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load("user://global_prefs.cfg") != OK:
		return true
	return not cfg.get_value(PREFS_SECTION, PREFS_POND_HINT, false)


static func mark_pond_hint_shown() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://global_prefs.cfg")
	cfg.set_value(PREFS_SECTION, PREFS_POND_HINT, true)
	cfg.save("user://global_prefs.cfg")


# --- §B surface / §C motion / §E startle / §H music / §I shaders ---


static func turn_rate_at_speed(speed: float, max_speed: float) -> float:
	return clampf(1.0 - speed / maxf(max_speed, 0.2) * 0.38, 0.45, 1.0)


static func turn_anticipation_delta(angle: float, speed: float) -> float:
	if absf(angle) < 0.06:
		return 0.0
	return clampf(-signf(angle) * speed * 0.14, -0.4, 0.4)


static func burst_glide_speed_mult(phase: float, swim_pattern: String) -> float:
	if swim_pattern not in ["cruise", "school", "shoal", "meander"]:
		return 1.0
	var p: float = fposmod(phase, 1.0)
	var kick: float = clampf(1.0 - absf(p - 0.25) * 4.0, 0.0, 1.0)
	var glide: float = clampf((p - 0.45) / 0.5, 0.0, 1.0) if p > 0.45 else 0.0
	return lerpf(0.82, 1.0, kick) * lerpf(1.0, 0.88, glide)


static func home_loop_wander(angle: float, dt: float, calm: bool) -> float:
	return angle + dt * (0.32 if calm else 0.22)


static func home_drift_loop_offset(
		home_x: float, home_z: float, angle: float, radius: float) -> Vector3:
	return Vector3(home_x + cos(angle) * radius, 0.0, home_z + sin(angle) * radius)


static func startle_radial_dir(fish_pos: Vector3, origin: Vector3, fallback: Vector3) -> Vector3:
	var away: Vector3 = fish_pos - origin
	away.y = 0.0
	if away.length_squared() < 0.04:
		return fallback
	return away.normalized()


static func sync_settle_tightness(remaining: float, duration: float) -> float:
	if remaining > duration * 0.4:
		return 0.0
	return clampf(1.0 - remaining / maxf(duration * 0.4, 0.01), 0.0, 0.5)


static func bass_formation_radius(bass: float) -> float:
	return lerpf(0.9, 1.24, clampf(bass, 0.0, 1.0))


static func treble_edge_shimmer(high: float) -> float:
	return clampf(high * 0.9, 0.0, 1.0)


static func swing_path_offset(groove: float, swing: float, phase: float, overhead: bool) -> Vector3:
	if not overhead or groove < 0.12:
		return Vector3.ZERO
	var sway: float = groove * (0.65 + swing * 0.35)
	return Vector3(
		sin(phase * TAU * 2.0) * sway * 0.42,
		0.0,
		cos(phase * TAU * 1.5) * sway * 0.28,
	)


static func calm_mill_rate(stress: float, music_active: bool) -> float:
	if music_active:
		return 0.26
	return 0.34 if stress < 0.28 else 0.18


static func wake_interference_strength(n_wake: int) -> float:
	return clampf(float(n_wake) * 0.07, 0.0, 1.0)


static func pond_wind_strength(calm: float) -> float:
	return lerpf(0.38, 0.06, calm)


static func pond_mirror_boost(pond: bool) -> float:
	return 0.58 if pond else 0.28


static func caustic_beat_pulse(downbeat: bool, bass: float, energy: float) -> float:
	if downbeat:
		return 0.32 + bass * 0.48 + energy * 0.18
	return bass * 0.14 + energy * 0.06


static func formation_size_radius_mult(slot: int, total: int) -> float:
	var t: float = float(slot) / maxf(float(total - 1), 1.0)
	return lerpf(0.68, 1.14, t)


static func counter_rotate_sign(choir_half: int) -> float:
	return -1.0 if choir_half == 1 else 1.0


static func polarization_tightness(alignment: float) -> float:
	return clampf(alignment, 0.0, 1.0)


static func visual_eq_radius_mult(column: String) -> float:
	return visual_eq_radius_mult_enum(eq_column_from_string(column))


static func visual_eq_radius_mult_enum(column: EqColumn) -> float:
	match column:
		EqColumn.BASS:
			return 0.52
		EqColumn.TREBLE:
			return 1.14
		_:
			return 0.84


static func symmetry_snap_xz(v: Vector3) -> Vector3:
	var xz := Vector2(v.x, v.z)
	if xz.length_squared() < 0.04:
		return v
	var ang: float = xz.angle()
	var snap: float = round(ang / (TAU / 8.0)) * (TAU / 8.0)
	var r: float = xz.length()
	return Vector3(cos(snap) * r, v.y, sin(snap) * r)


static func color_wheel_angle(hue: float, slot: int, total: int) -> float:
	var order: float = fposmod(hue + float(slot) / maxf(float(total), 1.0), 1.0)
	return order * TAU


static func collision_weave_y(relative_y: float, rel_speed: float) -> float:
	if absf(relative_y) > 0.32:
		return 0.0
	return signf(relative_y if absf(relative_y) > 0.04 else 1.0) * clampf(rel_speed, 0.0, 1.0) * 0.16


static func polarization_align_boost(polarization: float) -> float:
	return 1.0 + clampf(polarization, 0.0, 1.0) * 0.72


static func aggregate_color_spill(colors: Array) -> ColorSpill:
	var out := ColorSpill.new()
	if colors.is_empty():
		return out
	var sum := Vector3.ZERO
	for c in colors:
		if c is Color:
			var col: Color = c
			sum += Vector3(col.r, col.g, col.b)
	sum /= float(colors.size())
	out.rgb = sum
	out.gain = clampf(float(colors.size()) * 0.035, 0.0, 0.38)
	return out


static func plan_path_signature(locomotion_type: String, swim_pattern: String) -> PathSignature:
	var out := PathSignature.new()
	match locomotion_type:
		"anguilliform", "ribbon":
			out.wander_amp = 1.85
			out.wander_freq = 3.4
			out.turn_mult = 1.32
			out.straight_bias = 0.22
		"thunniform", "sagittiform":
			out.wander_amp = 0.32
			out.wander_freq = 0.42
			out.turn_mult = 0.58
			out.straight_bias = 0.94
		"ostraciiform", "ballistiform":
			out.wander_amp = 0.48
			out.wander_freq = 0.95
			out.turn_mult = 0.52
			out.straight_bias = 0.78
		_:
			var sp: float = 0.68 if swim_pattern in ["school", "shoal"] else 1.0
			out.wander_amp = sp
			out.wander_freq = 1.55
			out.turn_mult = 1.0
			out.straight_bias = 0.52
	return out


static func density_wave_sep_push(dist: float, radius: float, strength: float) -> float:
	if radius <= 0.01 or strength <= 0.01:
		return 0.0
	var front: float = absf(dist - radius)
	if front > 1.85:
		return 0.0
	return strength * (1.0 - front / 1.85)


static func flock_split_centers(phase: float, hw: float) -> Array:
	var split: float = sin(phase) * 0.5 + 0.5
	var sep: float = lerpf(0.0, hw * 0.38, split)
	return [Vector3(-sep, 0.0, 0.0), Vector3(sep, 0.0, 0.0)]


static func species_depth_band_tint(preferred_y: float, y_min: float, y_max: float) -> float:
	var t: float = clampf((preferred_y - y_min) / maxf(y_max - y_min, 0.5), 0.0, 1.0)
	return lerpf(0.86, 1.14, t)


static func conduct_from_stroke(points: Array) -> ConductResult:
	var out := ConductResult.new()
	if points.is_empty():
		return out
	var center := Vector3.ZERO
	var minx: float = INF
	var maxx: float = -INF
	var minz: float = INF
	var maxz: float = -INF
	for p in points:
		center += p
		minx = minf(minx, p.x)
		maxx = maxf(maxx, p.x)
		minz = minf(minz, p.z)
		maxz = maxf(maxz, p.z)
	center /= float(points.size())
	var span: float = 0.0
	for i in range(1, points.size()):
		span += (points[i] as Vector3).distance_to(points[i - 1] as Vector3)
	var closed: bool = points.size() >= 4 \
		and (points[0] as Vector3).distance_to(points[-1] as Vector3) < 2.2
	var aspect: float = (maxx - minx) / maxf(maxz - minz, 0.12)
	out.center = center
	if closed and span > 3.5:
		out.move = "mandala" if span > 7.0 else "carousel"
		out.formation = "donut" if span > 5.5 else "ring"
		out.radius = span * 0.14
	elif aspect > 2.2 or aspect < 0.45:
		out.move = "sweep"
		out.formation = "line"
		out.radius = span * 0.18
	else:
		out.move = "spiral"
		out.formation = "star"
		out.radius = span * 0.16
	return out


static func overhead_lod_range_mult() -> float:
	return 1.52


static func dance_trail_wake_interval(trail: float) -> float:
	return lerpf(0.36, 0.08, clampf(trail, 0.0, 1.0))


static func floater_dance_pull(strength: float, to: Vector3, from: Vector3) -> Vector3:
	if strength <= 0.01:
		return Vector3.ZERO
	var d: Vector3 = to - from
	d.y = 0.0
	if d.length_squared() < 0.12:
		return Vector3.ZERO
	return d.normalized() * strength * 0.024


static func antiphonal_move(base_move: String, choir_half: int) -> String:
	if choir_half == 0:
		return "carousel" if base_move in ["sway", "breathe", "wave"] else base_move
	return "radial_bloom" if base_move in ["carousel", "spiral", "mandala"] else "breathe"


static func biolum_wake_gain(daylight: float, biolum: bool) -> float:
	if not biolum or daylight > 0.35:
		return 0.0
	return lerpf(0.55, 1.0, 1.0 - daylight / 0.35)


static func _ease_in_out_cubic(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	if u < 0.5:
		return 4.0 * u * u * u
	return 1.0 - pow(-2.0 * u + 2.0, 3.0) / 2.0
