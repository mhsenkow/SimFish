# FISH_ALIVE foundations — body-first aliveness (voice/LLM optional).
# Prefer readable motion/posture/world answers over mind modules.
extends RefCounted
class_name FishAlive

const FEAR_NONE := 0
const FEAR_FREEZE := 1
const FEAR_FLEE := 2
const FEAR_HIDE := 3
const FEAR_PEEK := 4
const FEAR_RECOVER := 5

const LATERAL_LINE_R2: float = 2.8 * 2.8
const MIRACLE_BUDGET: int = 2


## #761 — richer defaults keyed by swim_pattern (habit kit).
static func habit_kit(pattern: String) -> Dictionary:
	match pattern:
		"school":
			return {
				"home_radius": 5.0, "wander": 1.25, "dart": 0.005, "turn": 2.6,
				"sep_mult": 0.92, "y_band": 0.55, "night_active": 0.25,
			}
		"shoal":
			return {
				"home_radius": 5.5, "wander": 1.4, "dart": 0.01, "turn": 2.5,
				"sep_mult": 1.15, "y_band": 0.7, "night_active": 0.3,
			}
		"dart":
			return {
				"home_radius": 3.5, "wander": 0.75, "dart": 0.045, "turn": 3.2,
				"sep_mult": 1.05, "y_band": 0.9, "night_active": 0.35,
				"dart_speed": 1.9,
			}
		"hover":
			return {
				"home_radius": 2.8, "wander": 0.42, "dart": 0.002, "turn": 1.1,
				"sep_mult": 1.35, "y_band": 0.35, "night_active": 0.2,
			}
		"cruise":
			return {
				"home_radius": 7.0, "wander": 0.65, "dart": 0.003, "turn": 1.8,
				"sep_mult": 1.0, "y_band": 0.5, "night_active": 0.22,
			}
		"meander":
			return {
				"home_radius": 4.2, "wander": 1.65, "dart": 0.0, "turn": 1.5,
				"sep_mult": 1.25, "y_band": 0.85, "night_active": 0.4,
			}
		"shuffle":
			return {
				"home_radius": 6.0, "wander": 1.35, "dart": 0.012, "turn": 2.2,
				"sep_mult": 1.1, "y_band": 0.4, "night_active": 0.85,
				"dart_speed": 1.4,
			}
		"sit":
			return {
				"home_radius": 2.2, "wander": 0.18, "dart": 0.0, "turn": 4.2,
				"sep_mult": 1.4, "y_band": 0.25, "night_active": 0.15,
				"dart_speed": 2.4,
			}
		_:
			return {
				"home_radius": 5.0, "wander": 1.0, "dart": 0.008, "turn": 2.6,
				"sep_mult": 1.0, "y_band": 0.6, "night_active": 0.3,
			}


static func apply_habit_kit(f: Fish) -> void:
	var kit: Dictionary = habit_kit(String(f.swim_pattern))
	f.home_radius = float(kit.get("home_radius", f.home_radius))
	f.wander_strength = float(kit.get("wander", f.wander_strength))
	f.dart_chance = float(kit.get("dart", f.dart_chance))
	f.max_turn_rate = float(kit.get("turn", f.max_turn_rate))
	if kit.has("dart_speed"):
		f.dart_speed_mult = float(kit["dart_speed"])
	f.separation_radius = clampf(
			f.separation_radius * float(kit.get("sep_mult", 1.0)), 0.28, 1.4)
	f.home_y_radius = clampf(float(kit.get("y_band", f.home_y_radius)), 0.25, 1.6)


## #41 — personality as posture (hang height / personal space).
static func posture_y_offset(f: Fish) -> float:
	var bold: float = float(f.personality.get("boldness", 0.5)) if f.personality is Dictionary else 0.5
	var calm: float = float(f.personality.get("calm", 0.5)) if f.personality is Dictionary else 0.5
	# Bold rides higher; timid sinks; calm levels the bias.
	return (bold - 0.5) * 0.55 * lerpf(1.15, 0.55, calm)


static func posture_sep_mult(f: Fish) -> float:
	var bold: float = float(f.personality.get("boldness", 0.5)) if f.personality is Dictionary else 0.5
	var soc: float = float(f.personality.get("sociability", 0.5)) if f.personality is Dictionary else 0.5
	# Timid wants more space; social packs tighter.
	return lerpf(1.22, 0.88, bold) * lerpf(1.12, 0.9, soc)


## #481 — when calm + sated, home is a loiter magnet (not only a fence).
static func home_loiter_mult(f: Fish) -> float:
	if f.hunger > 0.45 or f.stress > 0.5 or f.spooked > 0.35:
		return 1.0
	if f.current_mode == Fish.Mode.FLEE or f.current_mode == Fish.Mode.COURT:
		return 1.0
	var calm: float = float(f.personality.get("calm", 0.5)) if f.personality is Dictionary else 0.5
	return lerpf(1.15, 1.55, calm)


static func home_soft_attract(f: Fish, dist_home: float, home_r: float) -> float:
	# Inside the radius: gentle pull toward center so fish loaf at home.
	if dist_home >= home_r or home_r < 0.2:
		return 0.0
	if f.hunger > 0.4 or f.stress > 0.45:
		return 0.0
	var t: float = 1.0 - dist_home / home_r
	return t * t * 0.22 * home_loiter_mult(f)


## #1+#121 — continuous micro-idle: breath bob + never-parked floor.
static func micro_idle_y(f: Fish, dt: float) -> float:
	if f.get("_dying") == true:
		return 0.0
	var load: float = maxf(float(f._breath_load), 0.55)
	f._breath_phase = float(f._breath_phase) + dt * lerpf(0.7, 1.55, clampf(load - 0.4, 0.0, 1.2))
	var amp: float = 0.028 + clampf(load - 1.0, 0.0, 1.0) * 0.04
	if f._asleep:
		amp *= 0.45
	elif f.speed > f.max_speed * 0.55:
		amp *= 0.35
	return sin(float(f._breath_phase) * TAU) * amp


static func velocity_floor(f: Fish, speed: float) -> float:
	if f._asleep or f.get("_dying") == true or float(f.motion_freeze_t) > 0.05:
		return speed
	if f.current_mode == Fish.Mode.REST and f.swim_pattern == "sit":
		return maxf(speed, 0.02)
	# Never truly still while "alive" in open water.
	var floor_v: float = 0.04 + (0.03 if f.swim_pattern == "hover" else 0.0)
	return maxf(speed, floor_v)


## #521 — fear recovery arc phases.
static func ensure_fear_state(f: Fish) -> void:
	if f.get("_fear_phase") == null:
		f._fear_phase = FEAR_NONE
	if f.get("_fear_phase_t") == null:
		f._fear_phase_t = 0.0
	if f.get("_fear_peek_dir") == null:
		f._fear_peek_dir = Vector3.ZERO


static func begin_fear_freeze(f: Fish, seconds: float = 0.22) -> void:
	ensure_fear_state(f)
	f._fear_phase = FEAR_FREEZE
	f._fear_phase_t = seconds
	f.motion_freeze_t = maxf(float(f.motion_freeze_t), seconds)


static func tick_fear_arc(f: Fish, dt: float, in_cover: bool) -> Vector3:
	ensure_fear_state(f)
	var phase: int = int(f._fear_phase)
	f._fear_phase_t = maxf(0.0, float(f._fear_phase_t) - dt)
	var steer := Vector3.ZERO
	match phase:
		FEAR_FREEZE:
			if float(f._fear_phase_t) <= 0.0:
				f._fear_phase = FEAR_FLEE
				f._fear_phase_t = 1.2
		FEAR_FLEE:
			if in_cover or f.stress > 0.65:
				f._fear_phase = FEAR_HIDE
				var bold: float = float(f.personality.get("boldness", 0.5)) if f.personality is Dictionary else 0.5
				f._fear_phase_t = lerpf(2.0, 6.0, 1.0 - bold)
			elif float(f._fear_phase_t) <= 0.0 and f.spooked < 0.35 \
					and float(f._startle_remaining) <= 0.0:
				f._fear_phase = FEAR_RECOVER
				f._fear_phase_t = 1.5
			elif float(f._fear_phase_t) <= 0.0 and f.spooked >= 0.35:
				# Keep fleeing while still spooked.
				f._fear_phase_t = 0.6
		FEAR_HIDE:
			if float(f._fear_phase_t) <= 0.0 or f.stress < 0.45:
				f._fear_phase = FEAR_PEEK
				f._fear_phase_t = lerpf(0.6, 1.8, 1.0 - float(f.personality.get("boldness", 0.5)) \
						if f.personality is Dictionary else 1.0)
				# Peek toward open water / last heading.
				var h: Vector3 = f.heading
				if h.length_squared() < 1e-6:
					h = Vector3(0, 0, 1)
				f._fear_peek_dir = h.normalized()
		FEAR_PEEK:
			var peek_dir: Vector3 = f._fear_peek_dir as Vector3
			if peek_dir.length_squared() > 1e-6:
				steer = peek_dir * f.max_speed * 0.12
			if float(f._fear_phase_t) <= 0.0:
				f._fear_phase = FEAR_RECOVER
				f._fear_phase_t = 1.2
		FEAR_RECOVER:
			f.spooked = maxf(0.0, f.spooked - dt * 0.35)
			f.stress = maxf(0.0, f.stress - dt * 0.08)
			if float(f._fear_phase_t) <= 0.0 and f.spooked < 0.2:
				f._fear_phase = FEAR_NONE
		_:
			if f.spooked > 0.55 and float(f._startle_remaining) > 0.05:
				begin_fear_freeze(f, 0.18)
	return steer


## #841 — feel neighbor bursts even when behind (lateral line).
static func lateral_line_flinch(f: Fish, neighbors: Array) -> Vector3:
	if f.get("_dying") == true or f._asleep:
		return Vector3.ZERO
	var best := Vector3.ZERO
	var best_w: float = 0.0
	for n in neighbors:
		if not (n is Fish) or n == f or not is_instance_valid(n):
			continue
		var other: Fish = n
		if float(other.burst_remaining) < 0.12 and float(other._startle_remaining) < 0.08:
			continue
		var d: Vector3 = other.position - f.position
		var d2: float = d.length_squared()
		if d2 < 1e-4 or d2 > LATERAL_LINE_R2:
			continue
		var w: float = 1.0 - sqrt(d2) / 2.8
		w *= 0.55 + float(other.burst_remaining)
		# Behind still counts (that's the point).
		var ahead: float = 0.0
		if f.heading.length_squared() > 1e-6:
			ahead = f.heading.normalized().dot(d.normalized())
		if ahead > 0.35:
			w *= 0.55  # vision already handles frontal; lateral is quieter
		else:
			w *= 1.15
		if w > best_w:
			best_w = w
			best = -d.normalized()  # flinch away
	if best_w < 0.2:
		return Vector3.ZERO
	# Brief freeze-flinch telegraph.
	if best_w > 0.55 and float(f.motion_freeze_t) < 0.05:
		f.motion_freeze_t = maxf(float(f.motion_freeze_t), 0.08)
	return best * f.max_speed * clampf(best_w * 0.45, 0.0, 0.55)


## #641 — fin nicks as visible asymmetry on the tail pivot.
static func apply_fin_nicks_visual(f: Fish) -> void:
	var nicks: int = int(f._fin_nicks)
	if f._tail_pivot == null or not is_instance_valid(f._tail_pivot):
		return
	if nicks <= 0:
		if absf(f._tail_pivot.scale.y - 1.0) > 0.02:
			f._tail_pivot.scale.y = lerpf(f._tail_pivot.scale.y, 1.0, 0.2)
		return
	# Asymmetric vertical squash + slight yaw bias = torn caudal.
	var tear: float = clampf(0.08 * float(mini(nicks, 4)), 0.08, 0.32)
	var side: float = 1.0 if (f.get_instance_id() & 1) == 0 else -1.0
	f._tail_pivot.scale.y = lerpf(f._tail_pivot.scale.y, 1.0 - tear, 0.25)
	f._tail_pivot.rotation.z = lerpf(f._tail_pivot.rotation.z, side * tear * 0.55, 0.2)


static func maybe_earn_fin_nick(f: Fish, chance: float = 0.04) -> void:
	if f._behavior_rng().randf() < chance:
		f._fin_nicks = mini(int(f._fin_nicks) + 1, 6)


## #881 — world answers key verbs (ripple / dust / plant brush).
static func world_answer(f: Fish, verb: String) -> void:
	if f == null or not is_instance_valid(f):
		return
	var w: Node = f._world_node() if f.has_method("_world_node") else null
	if w == null:
		return
	var pos: Vector3 = f.global_position
	match verb:
		"dart":
			if pos.y >= (f.preferred_y if f.preferred_y > 3.2 else 4.0) \
					and w.has_method("spawn_burst_ripple"):
				w.spawn_burst_ripple(pos, 0.55)
			if w.has_method("brush_plants_near"):
				var d: Vector3 = f.velocity
				if d.length_squared() > 1e-4:
					w.brush_plants_near(pos, d.normalized(), maxf(f.speed, 0.6))
		"gulp":
			if w.has_method("spawn_burst_ripple"):
				w.spawn_burst_ripple(pos, 0.7)
		"sift":
			if w.has_method("spawn_substrate_dust"):
				w.spawn_substrate_dust(pos)
		"hide":
			if w.has_method("brush_plants_near"):
				w.brush_plants_near(pos, Vector3(0, 1, 0), 0.4)
		"feed_boil":
			if w.has_method("spawn_burst_ripple"):
				w.spawn_burst_ripple(pos, 0.4)


## Session miracle budget (#961/#999).
static func miracle_allowed(state: Dictionary) -> bool:
	return int(state.get("miracles", 0)) < MIRACLE_BUDGET


static func note_miracle(state: Dictionary) -> void:
	state["miracles"] = int(state.get("miracles", 0)) + 1
