# Fish life: the small, unsynchronised things that make a shoal read as
# animals instead of a particle system. State lives on Fish (the _bout_*,
# _lb_*, _peck_* fields); the logic lives here so fish.gd only carries hooks.
#
# WHY. dev/fish_behaviour_probe on valli_jungle (26 fish, 30 s) measured the
# baseline: 0% darts, speed-series lockstep 0.25-0.38 between neighbours,
# no courtship or display ever, no pecking. Every fish cruised at the same
# ~18% of max speed and turned at a bang-bang capped rate. Four layers here:
#
#  1. Bouts - each fish runs its own cruise / hover / dart schedule, with a
#     personal cruise pace and two personal slow speed rhythms. Nothing is
#     shared, so neighbours stop speeding up and slowing down together.
#  2. Turn inertia - yaw rate accelerates and decays instead of snapping to
#     the cap, so turns have a start and an end (fish.gd heading rotation).
#  3. Livebearer pursuit - adult male guppies/endlers tail females for a few
#     seconds at a time and pull ahead of them into the sigmoid display: body
#     bent into an S, fins spread, quivering (render hook in fish.gd). Only a
#     third of displays hold her; the rest she darts off from.
#  4. Pecking - well-fed fish pick at plant blades, the glass and the surface
#     film: approach, a few forward jabs, move on.
extends RefCounted

enum { BOUT_CRUISE, BOUT_HOVER, BOUT_DART }

# Pecks per minute-ish scale by species; unknown species peck rarely. A genome
# "peck_rate" (read in Fish.init_genome) overrides.
const PECK_RATE: Dictionary = {
	"guppy": 1.0, "endler": 1.0, "harlequin_rasbora": 0.55, "ember_tetra": 0.6,
	"rummy_nose": 0.45, "glassdart": 0.45, "danio": 0.35, "killifish": 0.5,
}
const DEFAULT_PECK_RATE: float = 0.2
# Bottom sifters and dedicated grazers already have their own feeding loops.
const NO_PECK_PATTERNS: Array = ["shuffle", "sit"]

const LB_SEARCH_R: float = 3.0
const LB_GIVE_UP_R: float = 3.6


static func _seed(f: Fish) -> void:
	if f._bout_w.x != 0.0:
		return
	var r: RandomNumberGenerator = f._behavior_rng()
	f._bout_w = Vector4(r.randf_range(0.22, 0.55), r.randf_range(0.8, 1.7),
		r.randf() * TAU, r.randf() * TAU)
	f._cruise_mult = r.randf_range(0.8, 1.22)
	f._bout_t = r.randf_range(0.5, 6.0)
	f._peck_cool = r.randf_range(2.0, 14.0)
	f._lb_cool = r.randf_range(1.0, 8.0)


# Hunger / hypoxia / escape / breeding may preempt decorative hover/dart.
# Soft abort: leave the bout without a dart-rate speed spike toward cruise.
static func emergency_interrupt(f: Fish) -> bool:
	if f.hunger >= 0.55:
		return true
	if f.burst_remaining > 0.0 or f._startle_remaining > 0.0:
		return true
	if f.current_mode == Fish.Mode.FLEE or f.current_mode == Fish.Mode.SPAWN \
			or f.current_mode == Fish.Mode.COURT:
		return true
	if f._aerial_timer > 0.0:
		return true
	if f.sim != null and f.sim.get("dissolved_o2") != null \
			and float(f.sim.dissolved_o2) < Fish.SURFACE_GULP_O2:
		return true
	return false


static func _abort_bout_soft(f: Fish) -> void:
	f._bout_kind = BOUT_CRUISE
	f._bout_yaw = 0.0
	f._bout_t = f._behavior_rng().randf_range(0.8, 2.2)
	f._bout_level = 1.0


# ---- 1. Speed bouts (per frame, fish._process) ------------------------------

static func bout_speed(f: Fish, target_spd: float, dt: float, eligible: bool,
		daylight: float) -> float:
	_seed(f)
	f._bout_clock += dt
	f._bout_t -= dt
	var emergency: bool = emergency_interrupt(f)
	if emergency and f._bout_kind != BOUT_CRUISE:
		_abort_bout_soft(f)
	if f._bout_t <= 0.0 or (not eligible and f._bout_kind != BOUT_CRUISE) or emergency:
		if emergency:
			_abort_bout_soft(f)
		else:
			_next_bout(f, eligible and not emergency, daylight)
	var level: float
	match f._bout_kind:
		BOUT_HOVER:
			level = f._bout_level
		BOUT_DART:
			# A dart is an absolute speed, not a multiple of an idle cruise.
			level = maxf(f._bout_level * f.max_speed / maxf(target_spd, 0.05), 1.0)
		_:
			level = f._cruise_mult * (1.0 + 0.2 * sin(f._bout_clock * f._bout_w.x + f._bout_w.z)
				+ 0.1 * sin(f._bout_clock * f._bout_w.y + f._bout_w.w))
	if not eligible or emergency:
		level = 1.0
	# Emergency return eases toward cruise; never use dart snap-rate.
	var rate: float = 2.2 if emergency else (7.0 if f._bout_kind == BOUT_DART else 1.4)
	f._bout_env = move_toward(f._bout_env, level, dt * rate * maxf(absf(level - f._bout_env), 0.25))
	return target_spd * f._bout_env


static func _next_bout(f: Fish, eligible: bool, daylight: float) -> void:
	var r: RandomNumberGenerator = f._behavior_rng()
	f._bout_yaw = 0.0
	if not eligible:
		f._bout_kind = BOUT_CRUISE
		f._bout_t = r.randf_range(1.0, 3.0)
		return
	var night: bool = daylight < 0.25
	var p_dart: float = 0.0 if night or f.maturity == Fish.MATURITY_SENESCENT else 0.2
	var p_hover: float = 0.36 if night else 0.2
	if f.swim_pattern in ["hover", "sit"]:
		p_hover += 0.15
	elif f.swim_pattern in ["dart", "cruise"]:
		p_dart += 0.06
	# Never two darts back to back - a dart is punctuation.
	if f._bout_kind == BOUT_DART:
		p_dart = 0.0
	var roll: float = r.randf()
	if roll < p_dart:
		f._bout_kind = BOUT_DART
		f._bout_t = r.randf_range(0.4, 0.8)
		f._bout_level = r.randf_range(0.9, 1.0)
		f._bout_yaw = r.randf_range(-0.75, 0.75)
	elif roll < p_dart + p_hover:
		f._bout_kind = BOUT_HOVER
		f._bout_t = r.randf_range(1.2, 3.8)
		f._bout_level = r.randf_range(0.12, 0.32)
	else:
		f._bout_kind = BOUT_CRUISE
		f._bout_t = r.randf_range(2.5, 8.0)


static func is_darting(f: Fish) -> bool:
	return f._bout_kind == BOUT_DART and f._bout_t > 0.0


# ---- 2. Turn inertia (per frame) --------------------------------------------

# Returns this frame's turn (radians). max_step is the capped turn for the
# frame; the yaw rate itself ramps toward what the fish wants.
# speed_frac (0..1 of max) and body_m bound the floor so large/slow fish
# cannot spin in place (Holistic #083).
static func inertial_turn(f: Fish, angle: float, max_step: float, dt: float,
		wall_t: float, speed_frac: float = 1.0, body_m: float = 0.45) -> float:
	var want_rate: float = minf(max_step, angle) / maxf(dt, 1e-4)
	var cap_rate: float = max_step / maxf(dt, 1e-4)
	# Full rate in ~0.3 s; near glass the fish may snap harder.
	var accel: float = cap_rate * lerpf(3.2, 12.0, clampf(wall_t, 0.0, 1.0))
	# Larger bodies yaw more slowly toward the want rate.
	accel *= clampf(0.52 / maxf(body_m, 0.28), 0.45, 1.25)
	var sf: float = clampf(speed_frac, 0.0, 1.0)
	if sf < 0.06:
		# Near-zero speed: bleed yaw rate out; do not invent a floor turn.
		f._turn_rate_state = move_toward(f._turn_rate_state, 0.0, cap_rate * 5.0 * dt)
		return minf(absf(f._turn_rate_state) * dt, angle)
	f._turn_rate_state = move_toward(f._turn_rate_state, want_rate, accel * dt)
	# Floor scales with speed so crawl never forces a minimum spin.
	var floor_step: float = max_step * 0.18 * clampf(sf / 0.14, 0.0, 1.0)
	return minf(maxf(f._turn_rate_state * dt, floor_step), angle)


# ---- 3. Livebearer pursuit + sigmoid display (sim tick) ---------------------

# Returns the steering to add to `desired`, or Vector3.ZERO when the male is
# not pursuing (the caller then carries on with its normal tiers).
static func livebearer_steer(f: Fish, neighbors: Array, dt: float,
		effective_max: float) -> Vector3:
	_seed(f)
	f._lb_display_cool = maxf(0.0, f._lb_display_cool - dt)
	# Hard gates end the pursuit. Real guppy males court through hunger (they
	# spend more time displaying than feeding), so only real hunger stops it.
	var eligible: bool = f.is_livebearer and f.sex == 0 \
		and f.maturity == Fish.MATURITY_ADULT and f.partner == null \
		and f.hunger < 0.72 and f.stress < 0.75
	var tgt: Fish = f._lb_target
	if tgt != null and (not is_instance_valid(tgt) or tgt.is_queued_for_deletion()
			or tgt.get("_dying") == true):
		tgt = null
	if not eligible or (tgt == null and f._lb_target != null):
		_end_pursuit(f)
		return Vector3.ZERO
	# Soft gates pause it: the shoal startles ~30% of the time (probe), and a
	# male that dropped his female at every flinch would never display.
	if f.burst_remaining > 0.0 or f._startle_remaining > 0.0:
		return Vector3.ZERO
	if tgt == null:
		f._lb_cool -= dt
		if f._lb_cool > 0.0:
			return Vector3.ZERO
		f._lb_cool = f._behavior_rng().randf_range(2.0, 6.0)
		tgt = _nearest_female(f, neighbors)
		if tgt == null or f._behavior_rng().randf() > 0.6:
			return Vector3.ZERO
		f._lb_target = tgt
		f._lb_follow_t = f._behavior_rng().randf_range(4.0, 11.0)
	f._lb_follow_t -= dt
	var to_her: Vector3 = tgt.position - f.position
	var dist: float = to_her.length()
	if f._lb_follow_t <= 0.0 or dist > LB_GIVE_UP_R:
		_end_pursuit(f)
		return Vector3.ZERO
	var her_fwd: Vector3 = tgt.heading
	her_fwd.y = 0.0
	her_fwd = her_fwd.normalized() if her_fwd.length_squared() > 1e-4 else Vector3.FORWARD
	var lateral: Vector3 = her_fwd.cross(Vector3.UP)
	var goal: Vector3
	if f._lb_display_t > 0.0:
		f._lb_display_t -= dt
		# Display station: just ahead of her and to one side, across her path.
		goal = tgt.position + her_fwd * 0.26 + lateral * f._lb_side * 0.16
		if f._lb_display_t <= 0.0:
			f._lb_display_cool = f._behavior_rng().randf_range(1.5, 4.0)
	else:
		# Tail her: behind and a little off her flank, a touch below.
		goal = tgt.position - her_fwd * 0.3 + lateral * f._lb_side * 0.12 + Vector3(0, -0.04, 0)
		if dist < 0.6 and f._lb_display_cool <= 0.0 and f._behavior_rng().randf() < dt * 1.5:
			f._lb_display_t = f._behavior_rng().randf_range(0.9, 1.9)
			f._lb_side = -1.0 if f._behavior_rng().randf() < 0.5 else 1.0
			# Most displays are refused: she darts off and he has to catch up.
			if f._behavior_rng().randf() < 0.65:
				tgt.burst_remaining = maxf(tgt.burst_remaining, 0.32)
	var to_goal: Vector3 = goal - f.position
	var gd: float = to_goal.length()
	if gd < 1e-4:
		return Vector3.ZERO
	# Arrive + match her velocity, so he rides with her instead of orbiting.
	var arrive: float = clampf(gd / 0.45, 0.15, 1.0)
	return to_goal / gd * effective_max * 0.9 * arrive + tgt.velocity * 0.6


static func _end_pursuit(f: Fish) -> void:
	f._lb_target = null
	f._lb_display_t = 0.0
	f._lb_follow_t = 0.0
	f._lb_cool = maxf(f._lb_cool, f._behavior_rng().randf_range(3.0, 9.0))


static func _nearest_female(f: Fish, neighbors: Array) -> Fish:
	var best: Fish = null
	var best_d2: float = LB_SEARCH_R * LB_SEARCH_R
	for n in neighbors:
		if not is_instance_valid(n) or not (n is Fish) or n == f:
			continue
		var o: Fish = n
		if o.sex != 1 or o.species != f.species or o.maturity != Fish.MATURITY_ADULT \
				or o.get("_dying") == true:
			continue
		var d2: float = (o.position - f.position).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = o
	return best


# Render envelope for the S-bend: eases in over ~0.25 s, out over ~0.4 s.
static func sigmoid_env(f: Fish, dt: float) -> float:
	var want: float = 1.0 if f._lb_display_t > 0.0 else 0.0
	f._lb_sigmoid = move_toward(f._lb_sigmoid, want, dt * (4.0 if want > 0.5 else 2.5))
	if f._lb_sigmoid > 0.0:
		f._lb_quiver += dt * 19.0
	return f._lb_sigmoid


# ---- 4. Pecking (sim tick) --------------------------------------------------

static func peck_steer(f: Fish, plants: Array, dt: float, effective_max: float,
		daylight: float) -> Vector3:
	_seed(f)
	var rate: float = f._peck_rate if f._peck_rate >= 0.0 \
		else float(PECK_RATE.get(f.species, DEFAULT_PECK_RATE))
	# A flinch abandons the peck but not the habit: short cooldown only.
	if f._peck_state != 0 and (f.burst_remaining > 0.0 or f._startle_remaining > 0.0):
		f._peck_state = 0
		f._peck_t = 0.0
		f._peck_cool = f._behavior_rng().randf_range(1.0, 3.0)
		return Vector3.ZERO
	var eligible: bool = rate > 0.0 and f.partner == null and f._lb_target == null \
		and f.hunger < 0.6 and f.stress < 0.7 and f.burst_remaining <= 0.0 \
		and f._startle_remaining <= 0.0 and daylight > 0.25 \
		and f.maturity >= Fish.MATURITY_JUVENILE and not f.algae_grazer \
		and not f.wood_grazer and not (f.swim_pattern in NO_PECK_PATTERNS)
	if not eligible:
		if f._peck_state != 0:
			_end_peck(f, rate)
		return Vector3.ZERO
	if f._peck_state == 0:
		f._peck_cool -= dt
		if f._peck_cool > 0.0:
			return Vector3.ZERO
		if not _pick_peck_point(f, plants):
			f._peck_cool = f._behavior_rng().randf_range(3.0, 8.0)
			return Vector3.ZERO
		f._peck_state = 1
		f._peck_timeout = 5.0
	# Occluded / removed target: cancel cleanly (Holistic #089).
	if not _peck_target_reachable(f):
		_end_peck(f, rate)
		return Vector3.ZERO
	var to_pt: Vector3 = f._peck_point - f.position
	var d: float = to_pt.length()
	var reach: float = f._body_tank_margin() * 0.55 + 0.06
	# Approach along the surface normal so head and contact agree.
	var approach_dir: Vector3 = to_pt
	if f._peck_normal.length_squared() > 1e-6:
		var nrm: Vector3 = f._peck_normal.normalized()
		# Prefer the component that closes on the surface (into the wall / film).
		var into: Vector3 = -nrm
		if into.dot(to_pt) < 0.0:
			into = nrm
		approach_dir = into * maxf(d, 0.08) + to_pt * 0.35
	if f._peck_state == 1:
		f._peck_timeout -= dt
		if f._peck_timeout <= 0.0:
			_end_peck(f, rate)
			return Vector3.ZERO
		if d <= reach * 1.2:
			f._peck_state = 2
			f._peck_t = f._behavior_rng().randf_range(1.2, 3.0)
			f._peck_phase = 0.0
		elif approach_dir.length_squared() > 1e-6:
			return approach_dir.normalized() * effective_max * clampf(d / 0.8, 0.28, 0.5)
		return Vector3.ZERO
	# Pecking: short jabs along the surface normal, drifting back between them.
	f._peck_t -= dt
	f._peck_phase += dt
	if f._peck_t <= 0.0:
		_end_peck(f, rate)
		return Vector3.ZERO
	if d < 1e-4 and f._peck_normal.length_squared() < 1e-6:
		return Vector3.ZERO
	var jab: bool = fmod(f._peck_phase, 0.42) < 0.14
	var jab_dir: Vector3 = approach_dir
	if jab_dir.length_squared() < 1e-6:
		jab_dir = -f._peck_normal if f._peck_normal.length_squared() > 1e-6 else Vector3.FORWARD
	var push: float = 0.42 if jab else (0.0 if d < reach else 0.12)
	# Never exactly ZERO while pecking, or the caller drops back to cruising.
	return jab_dir.normalized() * effective_max * maxf(push, 0.01) - f.velocity * (0.0 if jab else 0.8)


static func _end_peck(f: Fish, rate: float) -> void:
	f._peck_state = 0
	f._peck_t = 0.0
	f._peck_plant = null
	f._peck_normal = Vector3.ZERO
	f._peck_cool = f._behavior_rng().randf_range(3.0, 10.0) / maxf(rate, 0.05)


static func _peck_target_reachable(f: Fish) -> bool:
	match f._peck_kind:
		1: # surface film — still near the meniscus
			var surf: float = f._water_surface_y()
			return f._peck_point.y <= surf + 0.05 and f._peck_point.y >= surf - 0.45 \
				and f.position.y > surf - maxf(1.4, f.home_y_radius * 2.0)
		2: # plant blade — plant still present and point still on its stalk
			var pl: Variant = f._peck_plant
			if pl == null or not is_instance_valid(pl) or not (pl is Plant):
				return false
			var plant: Plant = pl
			var top_y: float = plant.global_position.y + float(plant.current_height) * Plant.VOXEL_SIZE
			var base_y: float = plant.global_position.y + 0.1
			if f._peck_point.y < base_y - 0.15 or f._peck_point.y > top_y + 0.15:
				return false
			var dxz: Vector2 = Vector2(f._peck_point.x - plant.global_position.x,
				f._peck_point.z - plant.global_position.z)
			return dxz.length_squared() < 0.22 * 0.22
		3: # glass — still near a wall with a matching inward normal
			var bnd: Dictionary = f._lateral_boundary_context(f.global_position)
			var clr: float = float(bnd.get("clearance", 99.0))
			var inward: Vector3 = bnd.get("inward", Vector3.ZERO)
			if clr > 2.2 or inward.length_squared() < 1e-4:
				return false
			if f._peck_normal.length_squared() > 1e-6 \
					and inward.normalized().dot(f._peck_normal.normalized()) < 0.35:
				return false
			return true
		_:
			return false


# Surface film for fish already near the top, else a blade of the nearest
# plant inside the fish's own layer, else the nearest glass. Stores contact
# normal so approach / jab face the reachable surface (Holistic #089).
static func _pick_peck_point(f: Fish, plants: Array) -> bool:
	var r: RandomNumberGenerator = f._behavior_rng()
	f._peck_plant = null
	f._peck_normal = Vector3.ZERO
	f._peck_kind = 0
	var surf: float = f._water_surface_y()
	if f.position.y > surf - maxf(0.9, f.home_y_radius * 1.6) and r.randf() < 0.55:
		f._peck_point = Vector3(f.position.x + r.randf_range(-0.5, 0.5), surf - 0.07,
			f.position.z + r.randf_range(-0.5, 0.5))
		f._peck_normal = Vector3.UP  # film faces down into the water; approach from below
		f._peck_kind = 1
		return true
	var best: Plant = null
	var best_d2: float = 2.4 * 2.4
	var n: int = 0
	# The sim's plant grid when there is one: `plants` is every plant in the tank.
	var near: Array = plants
	if f.sim != null and f.sim.has_method("query_plants_in_radius"):
		near = f.sim.query_plants_in_radius(f.position, 2.4)
	for p in near:
		n += 1
		if n > 48:
			break
		if not is_instance_valid(p) or not (p is Plant):
			continue
		var pl: Plant = p
		var dxz: Vector2 = Vector2(pl.global_position.x - f.position.x, pl.global_position.z - f.position.z)
		if dxz.length_squared() < best_d2:
			var top: float = pl.global_position.y + float(pl.current_height) * Plant.VOXEL_SIZE
			if top > f.position.y - f.home_y_radius:
				best_d2 = dxz.length_squared()
				best = pl
	if best != null and r.randf() < 0.75:
		var base_y: float = best.global_position.y + 0.15
		var top_y: float = best.global_position.y + float(best.current_height) * Plant.VOXEL_SIZE
		var y: float = clampf(f.position.y + r.randf_range(-0.3, 0.3), base_y, maxf(top_y - 0.05, base_y))
		f._peck_point = Vector3(best.global_position.x + r.randf_range(-0.09, 0.09), y,
			best.global_position.z + r.randf_range(-0.09, 0.09))
		var to_blade: Vector3 = f._peck_point - f.position
		to_blade.y *= 0.35
		f._peck_normal = to_blade.normalized() if to_blade.length_squared() > 1e-6 \
			else Vector3(1.0, 0.0, 0.0)
		f._peck_plant = best
		f._peck_kind = 2
		return true
	var bnd: Dictionary = f._lateral_boundary_context(f.global_position)
	var clr: float = float(bnd.get("clearance", 99.0))
	var inward: Vector3 = bnd.get("inward", Vector3.ZERO)
	if clr < 1.6 and inward.length_squared() > 1e-4:
		var nrm: Vector3 = inward.normalized()
		f._peck_point = f.position - nrm * maxf(clr - 0.12, 0.0) \
			+ Vector3(0, r.randf_range(-0.2, 0.2), 0)
		f._peck_normal = nrm  # outward from tank = surface normal into water
		f._peck_kind = 3
		return true
	return false
