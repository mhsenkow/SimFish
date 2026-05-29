# Crawling snail. Slides slowly along a tank-glass wall.
#
# The snail picks a direction in the tangent plane of its wall and inches that
# way. Periodically it pauses or turns. It clamps to a rectangle on the wall
# so it can't slide off into geometry.

extends Node3D

@export var wall_normal: Vector3 = Vector3.RIGHT
@export var wall_min: Vector3 = Vector3(-7.6, 2.0, -3.6)
@export var wall_max: Vector3 = Vector3(7.6, 6.0, 3.6)
@export var is_baby: bool = false     # baby snails are 0.5x scale until they grow up

# ---- Heritable genome ----
# Shell color + size are passed parent -> egg -> baby with mutation. Bigger
# shells eat more (slower hunger climb but slower movement). Color drifts
# over generations.
@export var shell_color: Color = Color8(135, 44, 176)
@export var shell_size: float = 1.0   # multiplier on body voxel sizes
@export var generation: int = 0
@export var sex: int = 0   # 0/1 - used for snail breeding later if added
# Shell silhouette. "turbo" = freshwater default (round low spiral),
# "trochus" = tall pointed cone (marine algae grazer), "nassarius" =
# small flat oval that rides the substrate plane (marine scavenger),
# "apple" = big rounded globose shell.
# world.gd's _build_snail_body branches on this.
@export var shell_shape: String = "turbo"
@export var shell_spines: float = 0.0  # 0..1 shell protrusions; deters predators
@export var toxin_level: float = 0.0   # 0..1 warning chemistry / bright pattern
# Body (foot + eye-stalk) tint. Defaults to the classic dark snail flesh.
@export var body_color: Color = Color8(44, 31, 21)
# Shell banding / accent color used for the alternating shell whorls. Alpha 0
# is a sentinel meaning "unset" — the renderer then auto-derives a darker
# shade of shell_color (the original look). Anything with alpha > 0 overrides
# it, giving two-tone banded shells.
@export var shell_accent_color: Color = Color(0, 0, 0, 0)
# Crawl speed multiplier on the base SPEED. <1 = sluggish, >1 = brisk.
@export var crawl_speed: float = 1.0
# Appetite: multiplier on how fast hunger climbs. Hungrier snails graze more
# (clear detritus/algae faster) but starve sooner when food is scarce.
@export var appetite: float = 1.0
# Genome-overridable lifespan (seconds). Defaults to the class lifespan.
@export var max_age_s: float = 720.0
var snail_name: String = ""
var parent_lineage: String = "Founders"
var _parent_keys: Array = []

const SPEED: float = 0.18                  # units per second; ~3 minutes coast-to-coast
const TURN_INTERVAL_MIN: float = 6.0
const TURN_INTERVAL_MAX: float = 14.0
const PAUSE_CHANCE: float = 0.3            # when turning, sometimes just sit still

# Breeding + lifecycle. Snails are prolific in real tanks; unchecked their
# voxel footprint smothers the whole substrate. We cap population and give
# them a finite lifespan so the system stays bounded.
const BREEDING_INTERVAL_MIN: float = 120.0
const BREEDING_INTERVAL_MAX: float = 240.0
const MATURITY_AGE: float = 60.0          # baby -> adult after a minute
const LIFESPAN_S: float = 720.0           # 12-minute lifespan; senescence at end
const POPULATION_CAP: int = 38            # global cap. Above this, no laying.

# Hunger / energy. Snails are grazers: hunger climbs steadily and is only
# pushed back down by eating detritus, algae, or biofilm/plant tissue. If
# hunger stays pinned (no food in reach) the snail's body condition (energy)
# drains and it eventually starves. This couples the snail population to the
# tank's food supply, so a clean, algae-free tank starves the colony down
# while a detritus-rich tank lets it boom - the real Walstad feedback loop.
const HUNGER_RATE: float = 0.011          # /s hunger climb (~75s fed -> hungry)
const STARVE_HUNGER: float = 0.85         # above this, energy drains
const STARVE_DRAIN: float = 0.030         # /s energy lost while starving (~110s empty -> dead)
const ENERGY_REGEN: float = 0.06          # /s energy regained when well-fed
const FEED_WASTE: float = 0.55            # hunger relief from a waste particle
const FEED_ALGAE: float = 0.5             # hunger relief from algae
const FEED_PLANT: float = 0.28            # hunger relief from rasping plant/coral
const BREED_ENERGY_MIN: float = 0.55      # body condition needed to lay eggs
const BREED_HUNGER_MAX: float = 0.7       # too hungry to breed above this

var _direction: Vector2 = Vector2.RIGHT     # in wall-tangent space
var _facing: Vector2 = Vector2.RIGHT        # smoothed direction the body points
var _t_until_turn: float = 0.0
var _paused: bool = false
# Wall-plane anchor. Captured in _ready from the spawn position projected
# onto wall_normal — i.e. the snail's "depth into the wall." After motion,
# we re-project position onto this plane so floating-point drift in the
# wall-normal axis can't accumulate and walk the snail off the glass.
var _wall_anchor_offset: float = 0.0
# Cleaner-crew pursuit: true while we're tracking a waste particle. The
# crawl pulse runs faster while this is set, so the snail visibly
# accelerates on the food trail.
var _pursuing_waste: bool = false
# Public so the inspector / portal HUD can read it (it queries `age`).
var age: float = 0.0
# Hunger: 0 = just fed, 1 = starving (same convention as Fish.hunger).
var hunger: float = 0.25
# Energy / body condition: 1 = healthy, drops while starving, regenerates
# when well-fed. Hitting 0 kills the snail (starvation).
var energy: float = 1.0
var _t_until_breed: float = 0.0
# Foot-pulse phase: snails locomote by rhythmic muscular waves through their
# foot. We mimic this by oscillating the body's vertical scale + a tiny
# forward "step" added to the slide velocity. The fast-moving snails have
# more visible pulses; paused snails don't pulse.
var _pulse_phase: float = 0.0
# Eye-stalk animation. Found by name in _ready (the world's
# _build_snail_body creates a Node3D named "EyeStalks" wrapping the two
# stalk voxels). Stalks sway gently with a slow phase, and occasionally
# retract briefly — mimicking the real-life "stalk pull" snails do when
# disturbed or while reorienting.
var _eye_stalks: Node3D = null
var _eye_phase: float = 0.0
var _eye_retract_timer: float = 0.0
var _eye_retract_remaining: float = 0.0
const EYE_RETRACT_INTERVAL_MIN: float = 6.0
const EYE_RETRACT_INTERVAL_MAX: float = 14.0
const EYE_RETRACT_DURATION: float = 0.8
# Shell-retraction defense. Real snails clamp the foot into the shell and
# go still when a predator brushes past. Set true while a snail_predator
# (loach / puffer) is within CLAMP_RADIUS. Movement is suspended and the
# body squashes flat against the wall.
var _clamped: bool = false
const CLAMP_RADIUS: float = 1.6
const CLAMP_RELEASE_GRACE: float = 0.7   # extra time clamped after threat leaves
var _clamp_grace_remaining: float = 0.0
const RETREAT_DURATION: float = 8.0
const RETREAT_SPEED_MULT: float = 1.45
var _retreat_remaining: float = 0.0
var _retreat_target: Vector3 = Vector3.INF

# Predator + food scans throttled to ~3 Hz. A real snail's chemosense is
# slow (it's tasting the water column, not seeing); the visible result
# of running these scans every render frame vs every 0.3 s is identical,
# but the cost drops from 60 Hz × N fish/waste to 3 Hz × N. Eye-stalk
# wiggle, foot pulse, facing lerp etc. all still update per frame so the
# motion stays smooth.
const SCAN_INTERVAL: float = 0.3
var _scan_accum: float = 0.0

# Save/load id (see fish.gd for rationale).
var id: String = ""


func get_saved_genome() -> Dictionary:
	_ensure_named()
	return {
		"organism_type": "snail",
		"species": "snail",
		"shell_color": shell_color,
		"shell_size": shell_size,
		"shell_shape": shell_shape,
		"shell_spines": shell_spines,
		"toxin_level": toxin_level,
		"body_color": body_color,
		"shell_accent_color": shell_accent_color,
		"crawl_speed": crawl_speed,
		"appetite": appetite,
		"max_age_s": max_age_s,
		"generation": generation,
		"snail_name": snail_name,
		"parent_lineage": parent_lineage,
		"parent_keys": _parent_keys.duplicate(),
	}


func apply_genome_metadata(g: Dictionary) -> void:
	if g.is_empty():
		return
	shell_color = g.get("shell_color", shell_color)
	shell_size = float(g.get("shell_size", shell_size))
	shell_shape = String(g.get("shell_shape", shell_shape))
	shell_spines = clampf(float(g.get("shell_spines", shell_spines)), 0.0, 1.0)
	toxin_level = clampf(float(g.get("toxin_level", toxin_level)), 0.0, 1.0)
	body_color = g.get("body_color", body_color)
	shell_accent_color = g.get("shell_accent_color", shell_accent_color)
	crawl_speed = clampf(float(g.get("crawl_speed", crawl_speed)), 0.3, 2.5)
	appetite = clampf(float(g.get("appetite", appetite)), 0.4, 2.0)
	max_age_s = maxf(60.0, float(g.get("max_age_s", max_age_s)))
	generation = int(g.get("generation", generation))
	snail_name = String(g.get("snail_name", snail_name))
	parent_lineage = String(g.get("parent_lineage", parent_lineage))
	var pk: Variant = g.get("parent_keys", [])
	if pk is Array:
		_parent_keys = pk.duplicate()
	_ensure_named()


func _ensure_named() -> void:
	if snail_name != "":
		return
	var adjs := ["Spiral", "Glass", "Pearl", "Moss", "Ivory", "Copper", "Jade", "Dusk"]
	var nouns := ["Crawler", "Glider", "Wanderer", "Drifter", "Pacer", "Rambler"]
	snail_name = "%s %s" % [adjs[randi() % adjs.size()], nouns[randi() % nouns.size()]]


func _ready() -> void:
	# Join the "snails" group so neighbor scans (local spacing, overlap
	# resolution) can identify sibling snails with a fast group check instead
	# of comparing each sibling's script resource_path string.
	add_to_group("snails")
	_ensure_named()
	_choose_new_direction()
	_facing = _direction
	_t_until_breed = randf_range(BREEDING_INTERVAL_MIN, BREEDING_INTERVAL_MAX)
	_pulse_phase = randf() * TAU
	_eye_phase = randf() * TAU
	_eye_retract_timer = randf_range(EYE_RETRACT_INTERVAL_MIN, EYE_RETRACT_INTERVAL_MAX)
	_eye_stalks = get_node_or_null("EyeStalks") as Node3D
	if is_baby:
		scale = Vector3.ONE * 0.5
	# Lock the wall plane to the spawn position. World.gd places snails on a
	# specific wall (back glass, side glass, or substrate floor); we want
	# motion to stay on that exact plane forever, regardless of what the
	# wall_min / wall_max box-clamp would otherwise permit.
	_wall_anchor_offset = wall_normal.dot(position)


func _process(dt: float) -> void:
	# Honor sim time_scale so pause/fast-forward affect snails too.
	var sim := _get_sim()
	if sim != null:
		dt *= float(sim.time_scale)
		if dt <= 0.0:
			return
	age += dt
	# Death by old age. queue_free with a small chance of leaving a shell
	# voxel behind (not done here - just remove). Lifespan is genome-driven
	# (max_age_s), defaulting to the class LIFESPAN_S.
	if age >= max_age_s:
		queue_free()
		return
	# Babies grow into adults over time. _apply_squash() reads is_baby + age
	# to compute scale, so we just flip the flag here.
	if is_baby and age >= MATURITY_AGE:
		is_baby = false

	# Hunger + body condition. Hunger climbs every tick; eating (handled in
	# _check_waste_nearby) pushes it back down. When hunger is pinned high
	# the snail burns body condition and eventually starves; when well-fed it
	# recovers. Babies are buffered by yolk reserves so they don't instantly
	# starve before they can forage.
	hunger = clampf(hunger + HUNGER_RATE * appetite * dt, 0.0, 1.0)
	if hunger >= STARVE_HUNGER:
		energy = clampf(energy - STARVE_DRAIN * dt, 0.0, 1.0)
	elif hunger < 0.5:
		energy = clampf(energy + ENERGY_REGEN * dt, 0.0, 1.0)
	if energy <= 0.0 and not is_baby:
		_die_starved()
		return

	# Scan cadence: predator + food scans iterate sim.fish / sim.waste /
	# sim.algae linearly, so per-frame runs were the single biggest CPU
	# hit in a populated tank. Gate both behind a 0.3 s accumulator and
	# pass the accumulated dt so the clamp-release grace counter ticks
	# down at the same wall-clock rate as before.
	_scan_accum += dt
	var scan_due: bool = _scan_accum >= SCAN_INTERVAL
	var scan_dt: float = _scan_accum
	if scan_due:
		_scan_accum = 0.0

	# Predator scan: clamp into the shell when a snail-hunter is close.
	# Real snails go still + retract so soft body parts aren't exposed.
	# Throttled — 0.3 s detection latency reads as natural reaction time.
	if scan_due:
		_check_predator_threat(scan_dt)

	# Eye stalk animation runs in every state (clamped, paused, crawling).
	# Slow sway is the resting wiggle real snails do as they sense around;
	# periodic retraction is the brief stalk-pull when they reset their
	# field of view. While the body is clamped into the shell, the stalks
	# are pulled in entirely (scale 0). Movement-state independent so the
	# tank doesn't go visually dead when snails pause.
	_tick_eye_stalks(dt)

	# When clamped we suspend movement entirely - foot's pulled in, no
	# crawling, no foraging, no breeding decision needed. Skip the rest
	# of the tick.
	if _clamped:
		_apply_squash(0.35, Vector3.UP)  # body flattened into shell
		return

	# Post-threat behavior: once we un-clamp, continue a short retreat toward
	# nearby hardscape so snail-predator encounters produce visible "hide"
	# movement rather than immediate normal grazing.
	if _retreat_remaining > 0.0:
		_retreat_remaining = maxf(0.0, _retreat_remaining - dt)

	_t_until_turn -= dt
	if _t_until_turn <= 0.0:
		_choose_new_direction()

	# Breeding: lay an egg sac once the timer expires, BUT only if the global
	# snail population is below the cap. Otherwise just reset and try again
	# later. Without this guard, snails carpet the entire tank floor in
	# minutes - they're nature's r-strategists.
	#
	# Predator-rebound: when no snail-hunters (loach / puffer) are in the
	# tank, snail breeding accelerates — the visible "no predators, snail
	# boom" dynamic you see in real tanks after a loach dies. We halve the
	# next breeding interval, doubling the laying rate. When a hunter is
	# present, intervals are normal and the cap-driven equilibrium holds.
	if not is_baby:
		_t_until_breed -= dt
		if _t_until_breed <= 0.0:
			# Breeding now costs body condition and is gated on it: a snail
			# only lays when it's well-fed (energy high, hunger low). Starving
			# colonies stop reproducing, so the population busts when food runs
			# out instead of breeding blindly on a timer.
			if _count_snails() < POPULATION_CAP \
					and energy >= BREED_ENERGY_MIN and hunger <= BREED_HUNGER_MAX:
				_lay_egg_sac()
				energy = clampf(energy - 0.2, 0.0, 1.0)
				hunger = clampf(hunger + 0.15, 0.0, 1.0)
			var rebound: float = 1.0
			if sim != null and int(sim.snail_predator_count) == 0:
				rebound = 0.5
			_t_until_breed = randf_range(BREEDING_INTERVAL_MIN,
				BREEDING_INTERVAL_MAX) * rebound

	# Smoothly turn the visual "facing" toward the target direction. Snails
	# don't snap directions; they pivot slowly.
	_facing = _facing.lerp(_direction, clampf(dt * 1.2, 0.0, 1.0))

	# Build tangent + bitangent vectors for this wall. Both must lie IN the
	# wall plane (perpendicular to wall_normal); using `up` as the second axis
	# was broken for floor/ceiling walls (where wall_normal ≈ up), because
	# then the "vertical" move on the wall actually pushed the snail through
	# the wall normal — straight out of the glass.
	var up := Vector3.UP
	var tangent: Vector3
	if absf(wall_normal.dot(up)) > 0.95:
		tangent = Vector3.RIGHT
	else:
		tangent = wall_normal.cross(up).normalized()
	# bitangent completes a right-handed frame inside the wall plane. For
	# vertical walls this resolves to ±UP (preserving the old "+y = climb up
	# the glass" semantic); for floor/ceiling walls it resolves to ±FORWARD,
	# so the snail moves along the plane instead of out of it.
	var bitangent: Vector3 = tangent.cross(wall_normal).normalized()

	# Detritus seeking: if there's a waste particle near our wall, steer
	# toward it (within tangent-plane). Snails are the cleanup crew - they
	# detect detritus from a moderate distance and slow-crawl over to consume.
	# Same throttle as the predator scan — _direction stays set between
	# scans, so the snail continues crawling toward the last-detected target.
	if scan_due and _retreat_remaining <= 0.0:
		_check_waste_nearby(tangent, bitangent)
	elif _retreat_remaining > 0.0 and _retreat_target != Vector3.INF:
		var to_cover: Vector3 = _retreat_target - global_position
		var rx: float = to_cover.dot(tangent)
		var ry: float = to_cover.dot(bitangent)
		var retreat_dir := Vector2(rx, ry)
		if retreat_dir.length() > 0.01:
			_direction = retreat_dir.normalized()
			_paused = false

	# Foot-pulse motion. Phase advances at ~1.5 Hz; speed and shell-vertical
	# squash are modulated by sin(phase), creating a "creep" gait. Snails
	# move noticeably only on the forward stroke of the pulse.
	if _paused:
		# Still pulse a little when paused (breathing).
		_pulse_phase += dt * 0.6
		var idle_squash: float = 1.0 + sin(_pulse_phase) * 0.04
		_apply_squash(idle_squash, up)
		return

	# Pulse rate jumps when pursuing detritus - the snail visibly speeds up
	# toward food, which is the real "cleaner crew converging" pattern.
	var pulse_rate: float = 2.4 if _pursuing_waste else 1.5
	_pulse_phase += dt * pulse_rate
	# Pulse-driven forward velocity: peaks at +SPEED * 1.6, dips to ~0.
	var pulse_factor: float = 0.5 + 0.5 * sin(_pulse_phase)  # 0..1
	var speed_mult: float = 1.4 if _pursuing_waste else 1.0
	if _retreat_remaining > 0.0:
		speed_mult *= RETREAT_SPEED_MULT
	var gait_speed: float = SPEED * crawl_speed * (0.4 + 1.2 * pulse_factor) * speed_mult
	# Move along the wall plane: tangent for "horizontal" on the wall,
	# bitangent for "vertical." Both are perpendicular to wall_normal so
	# there is no in-axis motion component pushing us out of the glass.
	var delta: Vector3 = tangent * _facing.x + bitangent * _facing.y
	position += delta * gait_speed * dt

	# Visual squash: shell expands then compresses through the pulse, like the
	# body wave passing through it.
	var squash: float = 1.0 + (pulse_factor - 0.5) * 0.18
	_apply_squash(squash, up)

	# Clamp to wall rectangle (per-axis box clamp; this is the gross "stay in
	# the rect" bound).
	position.x = clampf(position.x, wall_min.x, wall_max.x)
	position.y = clampf(position.y, wall_min.y, wall_max.y)
	position.z = clampf(position.z, wall_min.z, wall_max.z)
	# Then re-project onto the spawn-time wall plane. The basis fix above
	# already keeps motion in-plane, but float drift over thousands of ticks
	# (and the box-clamp above on a corner-adjacent snail) can nudge us
	# fractionally off. Snapping back here is a defensive, near-zero-cost
	# safety net — if you spawn a snail on the right glass at x=7.6 it
	# stays at x=7.6 for the lifetime of the run.
	var plane_drift: float = wall_normal.dot(position) - _wall_anchor_offset
	if absf(plane_drift) > 0.0001:
		position -= wall_normal * plane_drift
	# Local spacing so wall snails don't visually stack into one clump. Runs on
	# the same 0.3 s scan cadence as the predator/food scans — it iterates all
	# sibling snails, so per-frame was wasteful; snails crawl slowly enough that
	# 0.3 s spacing updates are visually identical.
	if scan_due:
		_apply_local_spacing(tangent, bitangent)


func _check_waste_nearby(tangent: Vector3, bitangent: Vector3) -> void:
	# Scan the world for waste particles near our wall. If one is close
	# enough, point our motion toward it in the wall-tangent plane. When we
	# get very close, consume it (produces a tiny snail pellet).
	#
	# Cleaner-crew sequencing: snails can detect detritus from much further
	# than they used to (~5 units now) and they accelerate the crawl when
	# they're on a trail. The result is a visible "drift toward the corpse"
	# pattern with multiple snails converging on the same particle - real
	# Walstad cleanup behavior.
	var sim := _get_sim()
	if sim == null:
		return
	# Reject waste that's deep on the wrong side of our wall plane.
	# Without this, side-glass snails get lured by floor waste and vice
	# versa — the snail steers in the wall plane but the target is 5+
	# units away in the wall_normal axis, so they crawl uselessly toward
	# the projection. 1.5 units off-plane matches the comment that used
	# to claim this filter existed.
	const OFF_PLANE_MAX: float = 1.5
	var best: Node3D = null
	var best_d2: float = 5.0 * 5.0
	for w in sim.waste:
		if not is_instance_valid(w):
			continue
		var to_w_pos: Vector3 = (w as Node3D).global_position - global_position
		if absf(wall_normal.dot(to_w_pos)) > OFF_PLANE_MAX:
			continue
		var d2: float = to_w_pos.length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = w

	# If no waste is found, check for algae. Snails love algae!
	if best == null and sim.get("algae") != null:
		best_d2 = 5.0 * 5.0
		for a in sim.algae:
			if not is_instance_valid(a):
				continue
			var to_a_pos: Vector3 = (a as Node3D).global_position - global_position
			if absf(wall_normal.dot(to_a_pos)) > OFF_PLANE_MAX:
				continue
			var d2: float = to_a_pos.length_squared()
			if d2 < best_d2:
				best_d2 = d2
				best = a
	# If food is scarce, snails rasp soft plant/coral tissue too (slowly).
	if best == null and sim.get("plants") != null and randf() < 0.45:
		best_d2 = 2.8 * 2.8
		for p in sim.plants:
			if not is_instance_valid(p):
				continue
			if not p.has_method("nibble") or p.biomass() < 8:
				continue
			var to_p_pos: Vector3 = (p as Node3D).global_position - global_position
			if absf(wall_normal.dot(to_p_pos)) > OFF_PLANE_MAX:
				continue
			var d2p: float = to_p_pos.length_squared()
			if d2p < best_d2:
				best_d2 = d2p
				best = p

	if best == null:
		return
	# Compare in global space consistently — both endpoints in global, so
	# the snail's parent transform doesn't skew the comparison.
	var to_w: Vector3 = best.global_position - global_position
	# Consume if very close.
	if to_w.length() < 0.25:
		if best.get("kind") != null:
			# It's waste
			sim.waste.erase(best)
			(best as Node3D).queue_free()
			hunger = clampf(hunger - FEED_WASTE, 0.0, 1.0)
		else:
			# It's algae - just nibble it away entirely since snails are slow
			if best.has_method("nibble"):
				if best.has_method("top_world_y"):
					best.nibble(1)   # rooted plant/coral: slow rasping
					hunger = clampf(hunger - FEED_PLANT, 0.0, 1.0)
				else:
					best.nibble(999) # algae cluster: can clear quickly
					hunger = clampf(hunger - FEED_ALGAE, 0.0, 1.0)

		# Tiny snail pellet on the substrate at our position.
		if sim.has_method("_spawn_waste"):
			sim._spawn_waste(global_position + Vector3(0, -0.05, 0), 0.04,
				WasteParticle.KIND_SNAIL)
		return
	# Project the to_w vector into wall-tangent space and override direction.
	var dx: float = to_w.dot(tangent)
	var dy: float = to_w.dot(bitangent)
	var dir := Vector2(dx, dy)
	if dir.length() > 0.01:
		_direction = dir.normalized()
		_paused = false
		# Trail-mode flag: while pursuing, the foot pulse goes faster so the
		# snail visibly speeds up toward food. Reset by _choose_new_direction
		# once we lose sight of waste.
		_pursuing_waste = true


var _sim_driver_ref: Node = null

func _get_sim() -> Node:
	if _sim_driver_ref != null and is_instance_valid(_sim_driver_ref):
		return _sim_driver_ref
	var n: Node = get_parent()
	while n != null:
		var d := n.get_node_or_null("SimDriver")
		if d != null:
			_sim_driver_ref = d
			return d
		n = n.get_parent()
	return null


func _apply_squash(squash_y: float, _up: Vector3) -> void:
	# Apply vertical squash by scaling on the wall-normal axis (which is the
	# snail's "up" relative to its wall). Use absolute scale (preserve current
	# baby/adult size factor).
	var base: float = 0.5 if is_baby else 1.0
	# Animate growth from 0.5 -> 1.0 for babies as they age.
	if is_baby:
		base = 0.5 + 0.5 * clampf(age / MATURITY_AGE, 0.0, 1.0)
	# Squash along wall_normal direction (the "thickness" of the snail).
	# Approximation: just scale on Y if wall is vertical-ish.
	scale = Vector3(base, base * squash_y, base)


func _count_snails() -> int:
	# Count all Snail siblings under our parent (the Snails container).
	# Includes egg sacs - we don't want to lay more if the wall is already
	# covered in pending eggs.
	var parent := get_parent()
	if parent == null:
		return 0
	return parent.get_child_count()


func _lay_egg_sac() -> void:
	# Spawn an egg sac that inherits our shell genome with mutation. The baby
	# that hatches will look like a drifted-color child of this snail.
	var sac := Node3D.new()
	sac.set_script(load("res://scripts/snail_egg.gd"))
	get_parent().add_child(sac)
	sac.position = position + wall_normal * 0.04
	sac.set("wall_normal", wall_normal)
	sac.set("wall_min", wall_min)
	sac.set("wall_max", wall_max)
	# Inherit shell traits with mutation. Color drift ~0.18 per generation;
	# size mutation small so the trend is mostly visual.
	var color_muta := 0.18
	var new_color: Color = shell_color.lerp(
		Color(randf(), randf() * 0.6 + 0.2, randf()), color_muta)
	var pressure: Dictionary = EvolutionPressure.sample_from_sim(_get_sim(), position)
	new_color = EvolutionPressure.apply_snail_shell_color(new_color, pressure)
	var new_size: float = clampf(shell_size + randf_range(-0.08, 0.08), 0.65, 1.5)
	var new_shape: String = _mutate_shell_shape(shell_shape)
	var new_spines: float = clampf(shell_spines + randf_range(-0.12, 0.12), 0.0, 1.0)
	var new_toxin: float = clampf(toxin_level + randf_range(-0.10, 0.10), 0.0, 1.0)
	sac.set("inherited_shell_color", new_color)
	sac.set("inherited_shell_size", new_size)
	sac.set("inherited_generation", generation + 1)
	sac.set("inherited_shell_shape", new_shape)
	sac.set("inherited_shell_spines", new_spines)
	sac.set("inherited_toxin_level", new_toxin)
	# New heritable traits: body color drifts slightly; banding color, crawl
	# speed, appetite, and lifespan pass through with small mutation so a
	# designed lineage stays recognisable but still evolves.
	sac.set("inherited_body_color", body_color.lerp(
		Color(randf() * 0.5, randf() * 0.4, randf() * 0.4), 0.08))
	sac.set("inherited_shell_accent_color", shell_accent_color)
	sac.set("inherited_crawl_speed", clampf(crawl_speed + randf_range(-0.1, 0.1), 0.3, 2.5))
	sac.set("inherited_appetite", clampf(appetite + randf_range(-0.08, 0.08), 0.4, 2.0))
	sac.set("inherited_max_age_s", maxf(60.0, max_age_s + randf_range(-30.0, 30.0)))
	sac.set("inherited_parent_lineage", snail_name)
	sac.set("inherited_parent_keys", SpeciesLibrary.parent_keys_for_breeding([get_saved_genome()]))


func _mutate_shell_shape(base_shape: String) -> String:
	var shape: String = base_shape
	# Rare shape mutation keeps local lineages mostly coherent while allowing
	# long-run emergence of visibly distinct shell classes.
	if randf() < 0.08:
		var options: Array[String] = ["turbo", "trochus", "nassarius", "apple"]
		for _attempt in 5:
			var candidate: String = options[randi() % options.size()]
			if candidate != base_shape:
				shape = candidate
				break
	return shape


func _tick_eye_stalks(dt: float) -> void:
	if _eye_stalks == null:
		return
	_eye_phase += dt * 1.8
	# Scheduled retraction: every EYE_RETRACT_INTERVAL_*, briefly pull
	# the stalks in over EYE_RETRACT_DURATION before letting them re-
	# extend. Don't restart the cycle while we're already in a retract.
	if _eye_retract_remaining > 0.0:
		_eye_retract_remaining = maxf(0.0, _eye_retract_remaining - dt)
	else:
		_eye_retract_timer = maxf(0.0, _eye_retract_timer - dt)
		if _eye_retract_timer <= 0.0:
			_eye_retract_remaining = EYE_RETRACT_DURATION
			_eye_retract_timer = randf_range(
				EYE_RETRACT_INTERVAL_MIN, EYE_RETRACT_INTERVAL_MAX)
	# Stalk extension factor.
	#   1.0  fully extended (default)
	#   0.0  fully retracted (clamped or mid-pull)
	# When predator-clamped, force-retract for the duration of the clamp.
	# During a scheduled retract, ease in/out so the pull reads as a
	# smooth pinch rather than a snap.
	var ext: float = 1.0
	if _clamped:
		ext = 0.0
	elif _eye_retract_remaining > 0.0:
		var t: float = 1.0 - (_eye_retract_remaining / EYE_RETRACT_DURATION)
		# Bell-shape: 0 → 1 → 0 over the duration, so we retract then re-extend.
		ext = 1.0 - sin(t * PI)
		ext = maxf(0.15, ext)
	# Slow sway (resting wiggle), suppressed during retraction.
	var sway_y: float = sin(_eye_phase) * 0.18 * ext
	var sway_x: float = sin(_eye_phase * 0.7 + 1.1) * 0.10 * ext
	_eye_stalks.rotation.y = sway_y
	_eye_stalks.rotation.x = sway_x
	# Scale the stalks along Y so they visually pull into the body
	# during retraction. Width stays steady so they don't look thinner.
	_eye_stalks.scale = Vector3(1.0, lerpf(0.1, 1.0, ext), 1.0)


func _check_predator_threat(dt: float) -> void:
	# Find the nearest fish with snail_predator == true (loach, puffer).
	# Clamp if any are inside CLAMP_RADIUS; otherwise tick down the
	# release grace so the snail doesn't instantly un-clamp when a fish
	# briefly passes by.
	var sim := _get_sim()
	if sim == null:
		_clamped = false
		return
	var threat_close: bool = false
	var radius_sq: float = CLAMP_RADIUS * CLAMP_RADIUS
	var nearest_threat: Node3D = null
	var nearest_d2: float = INF
	for f in sim.fish:
		if not is_instance_valid(f):
			continue
		if not bool(f.snail_predator):
			continue
		var d2: float = f.position.distance_squared_to(position)
		if d2 < nearest_d2:
			nearest_d2 = d2
			nearest_threat = f
		if d2 < radius_sq:
			threat_close = true
	if threat_close:
		_clamped = true
		_clamp_grace_remaining = CLAMP_RELEASE_GRACE
		_pursuing_waste = false
		_retreat_remaining = RETREAT_DURATION
		_retreat_target = _pick_hardscape_retreat_point(sim)
		if _retreat_target == Vector3.INF and nearest_threat != null:
			var away: Vector3 = (global_position - nearest_threat.global_position).normalized()
			if away.length_squared() > 0.001:
				_retreat_target = global_position + away * 1.2
	elif _clamped:
		_clamp_grace_remaining = maxf(0.0, _clamp_grace_remaining - dt)
		if _clamp_grace_remaining <= 0.0:
			_clamped = false


func _die_starved() -> void:
	# Starvation death. The decomposing snail drops a small detritus pellet
	# back into the system (returning its nutrients), then frees itself.
	var sim := _get_sim()
	if sim != null and sim.has_method("_spawn_waste"):
		sim._spawn_waste(global_position + Vector3(0, -0.05, 0), 0.05,
			WasteParticle.KIND_SNAIL)
	queue_free()


func _choose_new_direction() -> void:
	# Clear cleaner-crew pursuit flag - if there was a waste trail nearby
	# we'd still be locked onto it via _check_waste_nearby. By the time
	# we get here we've either eaten the target or lost it.
	_pursuing_waste = false
	_t_until_turn = randf_range(TURN_INTERVAL_MIN, TURN_INTERVAL_MAX)
	_paused = randf() < PAUSE_CHANCE
	if _paused:
		return
	var ang := randf() * TAU
	_direction = Vector2(cos(ang), sin(ang))


func _pick_hardscape_retreat_point(sim: Node) -> Vector3:
	var root: Variant = sim.get("hardscape_root")
	if root == null or not is_instance_valid(root):
		return Vector3.INF
	var best: Vector3 = Vector3.INF
	var best_d2: float = INF
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n == root:
			continue
		if not (n is Node3D):
			continue
		var p: Vector3 = (n as Node3D).global_position
		var d2: float = p.distance_squared_to(global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = p
	return best


func _apply_local_spacing(tangent: Vector3, bitangent: Vector3) -> void:
	var sim := _get_sim()
	if sim == null:
		return
	var root: Variant = sim.get("snails_root")
	if root == null or not (root is Node3D):
		return
	const SPACE_R: float = 0.22
	var pushed: int = 0
	for s in (root as Node3D).get_children():
		if s == self or not is_instance_valid(s):
			continue
		# Fast group check instead of per-sibling script resource_path string
		# compare. Snails join the "snails" group in _ready.
		if not s.is_in_group("snails"):
			continue
		var to_other: Vector3 = global_position - (s as Node3D).global_position
		# Only repel neighbors on roughly the same wall plane.
		if absf(wall_normal.dot(to_other)) > 0.22:
			continue
		var dx: float = to_other.dot(tangent)
		var dy: float = to_other.dot(bitangent)
		var d2: float = dx * dx + dy * dy
		if d2 < 1e-6 or d2 >= SPACE_R * SPACE_R:
			continue
		var dir2 := Vector2(dx, dy).normalized()
		var merged: Vector2 = _direction + dir2 * 0.9
		if merged.length_squared() > 1e-6:
			_direction = merged.normalized()
		position += (tangent * dir2.x + bitangent * dir2.y) \
			* (SPACE_R - sqrt(d2)) * 0.55
		pushed += 1
		if pushed >= 4:
			break


# ---- Save / load ----

func to_save_dict() -> Dictionary:
	return {
		"id": id,
		"pos": SaveHelpers.vec3_to_array(global_position),
		"wall_normal": SaveHelpers.vec3_to_array(wall_normal),
		"wall_min": SaveHelpers.vec3_to_array(wall_min),
		"wall_max": SaveHelpers.vec3_to_array(wall_max),
		"is_baby": is_baby,
		"shell_color": SaveHelpers.color_to_array(shell_color),
		"shell_size": shell_size,
		"shell_shape": shell_shape,
		"shell_spines": shell_spines,
		"toxin_level": toxin_level,
		"body_color": SaveHelpers.color_to_array(body_color),
		"shell_accent_color": SaveHelpers.color_to_array(shell_accent_color),
		"crawl_speed": crawl_speed,
		"appetite": appetite,
		"max_age_s": max_age_s,
		"generation": generation,
		"sex": sex,
		"direction": SaveHelpers.vec2_to_array(_direction),
		"facing": SaveHelpers.vec2_to_array(_facing),
		"wall_anchor_offset": _wall_anchor_offset,
		"age": age,
		"hunger": hunger,
		"energy": energy,
		"t_until_breed": _t_until_breed,
		"t_until_turn": _t_until_turn,
		"paused": _paused,
		"pursuing_waste": _pursuing_waste,
		"clamped": _clamped,
		"clamp_grace_remaining": _clamp_grace_remaining,
		"eye_retract_remaining": _eye_retract_remaining,
		"eye_retract_timer": _eye_retract_timer,
	}


func apply_save_dict(d: Dictionary) -> void:
	id = String(d.get("id", id))
	wall_normal = SaveHelpers.array_to_vec3(d.get("wall_normal", []), wall_normal)
	wall_min = SaveHelpers.array_to_vec3(d.get("wall_min", []), wall_min)
	wall_max = SaveHelpers.array_to_vec3(d.get("wall_max", []), wall_max)
	is_baby = bool(d.get("is_baby", is_baby))
	shell_color = SaveHelpers.array_to_color(d.get("shell_color", []), shell_color)
	shell_size = float(d.get("shell_size", shell_size))
	shell_shape = String(d.get("shell_shape", shell_shape))
	shell_spines = clampf(float(d.get("shell_spines", shell_spines)), 0.0, 1.0)
	toxin_level = clampf(float(d.get("toxin_level", toxin_level)), 0.0, 1.0)
	body_color = SaveHelpers.array_to_color(d.get("body_color", []), body_color)
	shell_accent_color = SaveHelpers.array_to_color(d.get("shell_accent_color", []), shell_accent_color)
	crawl_speed = clampf(float(d.get("crawl_speed", crawl_speed)), 0.3, 2.5)
	appetite = clampf(float(d.get("appetite", appetite)), 0.4, 2.0)
	max_age_s = maxf(60.0, float(d.get("max_age_s", max_age_s)))
	generation = int(d.get("generation", 0))
	sex = int(d.get("sex", 0))
	_direction = SaveHelpers.array_to_vec2(d.get("direction", []), Vector2.RIGHT)
	_facing = SaveHelpers.array_to_vec2(d.get("facing", []), Vector2.RIGHT)
	_wall_anchor_offset = float(d.get("wall_anchor_offset", _wall_anchor_offset))
	age = float(d.get("age", 0.0))
	hunger = clampf(float(d.get("hunger", hunger)), 0.0, 1.0)
	energy = clampf(float(d.get("energy", energy)), 0.0, 1.0)
	_t_until_breed = float(d.get("t_until_breed", _t_until_breed))
	_t_until_turn = float(d.get("t_until_turn", _t_until_turn))
	_paused = bool(d.get("paused", false))
	_pursuing_waste = bool(d.get("pursuing_waste", false))
	_clamped = bool(d.get("clamped", false))
	_clamp_grace_remaining = float(d.get("clamp_grace_remaining", 0.0))
	_eye_retract_remaining = float(d.get("eye_retract_remaining", 0.0))
	_eye_retract_timer = float(d.get("eye_retract_timer", _eye_retract_timer))
	if is_baby:
		scale = Vector3.ONE * 0.5
