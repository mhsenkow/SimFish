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
# small flat oval that rides the substrate plane (marine scavenger).
# world.gd's _build_snail_body branches on this.
@export var shell_shape: String = "turbo"
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
var _age: float = 0.0
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
	_age += dt
	# Death by old age. queue_free with a small chance of leaving a shell
	# voxel behind (not done here - just remove).
	if _age >= LIFESPAN_S:
		queue_free()
		return
	# Babies grow into adults over time. _apply_squash() reads is_baby + _age
	# to compute scale, so we just flip the flag here.
	if is_baby and _age >= MATURITY_AGE:
		is_baby = false

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
			if _count_snails() < POPULATION_CAP:
				_lay_egg_sac()
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
	if scan_due:
		_check_waste_nearby(tangent, bitangent)

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
	var gait_speed: float = SPEED * (0.4 + 1.2 * pulse_factor) * speed_mult
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
		else:
			# It's algae - just nibble it away entirely since snails are slow
			if best.has_method("nibble"):
				best.nibble(999)

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
		base = 0.5 + 0.5 * clampf(_age / MATURITY_AGE, 0.0, 1.0)
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
	var pressure: Dictionary = EvolutionPressure.sample_from_sim(_get_sim())
	new_color = EvolutionPressure.apply_snail_shell_color(new_color, pressure)
	var new_size: float = clampf(shell_size + randf_range(-0.08, 0.08), 0.65, 1.5)
	sac.set("inherited_shell_color", new_color)
	sac.set("inherited_shell_size", new_size)
	sac.set("inherited_generation", generation + 1)
	sac.set("inherited_shell_shape", shell_shape)
	sac.set("inherited_parent_lineage", snail_name)
	sac.set("inherited_parent_keys", SpeciesLibrary.parent_keys_for_breeding([get_saved_genome()]))


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
	for f in sim.fish:
		if not is_instance_valid(f):
			continue
		if not bool(f.snail_predator):
			continue
		if f.position.distance_squared_to(position) < radius_sq:
			threat_close = true
			break
	if threat_close:
		_clamped = true
		_clamp_grace_remaining = CLAMP_RELEASE_GRACE
		_pursuing_waste = false
	elif _clamped:
		_clamp_grace_remaining = maxf(0.0, _clamp_grace_remaining - dt)
		if _clamp_grace_remaining <= 0.0:
			_clamped = false


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
		"generation": generation,
		"sex": sex,
		"direction": SaveHelpers.vec2_to_array(_direction),
		"facing": SaveHelpers.vec2_to_array(_facing),
		"wall_anchor_offset": _wall_anchor_offset,
		"age": _age,
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
	generation = int(d.get("generation", 0))
	sex = int(d.get("sex", 0))
	_direction = SaveHelpers.array_to_vec2(d.get("direction", []), Vector2.RIGHT)
	_facing = SaveHelpers.array_to_vec2(d.get("facing", []), Vector2.RIGHT)
	_wall_anchor_offset = float(d.get("wall_anchor_offset", _wall_anchor_offset))
	_age = float(d.get("age", 0.0))
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
