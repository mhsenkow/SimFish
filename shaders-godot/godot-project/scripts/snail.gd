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

const SPEED: float = 0.18                  # units per second; ~3 minutes coast-to-coast
const TURN_INTERVAL_MIN: float = 6.0
const TURN_INTERVAL_MAX: float = 14.0
const PAUSE_CHANCE: float = 0.3            # when turning, sometimes just sit still

# Breeding + lifecycle. Snails are prolific in real tanks; unchecked their
# voxel footprint smothers the whole substrate. We cap population and give
# them a finite lifespan so the system stays bounded.
const BREEDING_INTERVAL_MIN: float = 180.0
const BREEDING_INTERVAL_MAX: float = 360.0
const MATURITY_AGE: float = 60.0          # baby -> adult after a minute
const LIFESPAN_S: float = 720.0           # 12-minute lifespan; senescence at end
const POPULATION_CAP: int = 28            # global cap. Above this, no laying.

var _direction: Vector2 = Vector2.RIGHT     # in wall-tangent space
var _facing: Vector2 = Vector2.RIGHT        # smoothed direction the body points
var _t_until_turn: float = 0.0
var _paused: bool = false
var _age: float = 0.0
var _t_until_breed: float = 0.0
# Foot-pulse phase: snails locomote by rhythmic muscular waves through their
# foot. We mimic this by oscillating the body's vertical scale + a tiny
# forward "step" added to the slide velocity. The fast-moving snails have
# more visible pulses; paused snails don't pulse.
var _pulse_phase: float = 0.0


func _ready() -> void:
	_choose_new_direction()
	_facing = _direction
	_t_until_breed = randf_range(BREEDING_INTERVAL_MIN, BREEDING_INTERVAL_MAX)
	_pulse_phase = randf() * TAU
	if is_baby:
		scale = Vector3.ONE * 0.5


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

	_t_until_turn -= dt
	if _t_until_turn <= 0.0:
		_choose_new_direction()

	# Breeding: lay an egg sac once the timer expires, BUT only if the global
	# snail population is below the cap. Otherwise just reset and try again
	# later. Without this guard, snails carpet the entire tank floor in
	# minutes - they're nature's r-strategists.
	if not is_baby:
		_t_until_breed -= dt
		if _t_until_breed <= 0.0:
			if _count_snails() < POPULATION_CAP:
				_lay_egg_sac()
			_t_until_breed = randf_range(BREEDING_INTERVAL_MIN, BREEDING_INTERVAL_MAX)

	# Smoothly turn the visual "facing" toward the target direction. Snails
	# don't snap directions; they pivot slowly.
	_facing = _facing.lerp(_direction, clampf(dt * 1.2, 0.0, 1.0))

	# Build tangent vectors for this wall.
	var up := Vector3.UP
	var tangent: Vector3
	if absf(wall_normal.dot(up)) > 0.95:
		tangent = Vector3.RIGHT
	else:
		tangent = wall_normal.cross(up).normalized()

	# Detritus seeking: if there's a waste particle near our wall, steer
	# toward it (within tangent-plane). Snails are the cleanup crew - they
	# detect detritus from a moderate distance and slow-crawl over to consume.
	_check_waste_nearby(tangent, up)

	# Foot-pulse motion. Phase advances at ~1.5 Hz; speed and shell-vertical
	# squash are modulated by sin(phase), creating a "creep" gait. Snails
	# move noticeably only on the forward stroke of the pulse.
	if _paused:
		# Still pulse a little when paused (breathing).
		_pulse_phase += dt * 0.6
		var idle_squash: float = 1.0 + sin(_pulse_phase) * 0.04
		_apply_squash(idle_squash, up)
		return

	_pulse_phase += dt * 1.5
	# Pulse-driven forward velocity: peaks at +SPEED * 1.6, dips to ~0.
	var pulse_factor: float = 0.5 + 0.5 * sin(_pulse_phase)  # 0..1
	var gait_speed: float = SPEED * (0.4 + 1.2 * pulse_factor)
	var delta: Vector3 = tangent * _facing.x + up * _facing.y
	position += delta * gait_speed * dt

	# Visual squash: shell expands then compresses through the pulse, like the
	# body wave passing through it.
	var squash: float = 1.0 + (pulse_factor - 0.5) * 0.18
	_apply_squash(squash, up)

	# Clamp to wall rectangle.
	position.x = clampf(position.x, wall_min.x, wall_max.x)
	position.y = clampf(position.y, wall_min.y, wall_max.y)
	position.z = clampf(position.z, wall_min.z, wall_max.z)


func _check_waste_nearby(tangent: Vector3, up: Vector3) -> void:
	# Scan the world for waste particles near our wall. If one is close enough,
	# point our motion toward it in the wall-tangent plane. When we get very
	# close, consume it (produces a tiny snail pellet).
	var sim := _get_sim()
	if sim == null:
		return
	var best: Node3D = null
	var best_d2: float = 2.0 * 2.0
	for w in sim.waste:
		if not is_instance_valid(w):
			continue
		# Only consider waste roughly on or near our wall (within 1.5 units in
		# the wall_normal direction). Most waste is on the substrate so the
		# substrate floor naturally satisfies this for floor-walking snails.
		var d2: float = (w as Node3D).global_position.distance_squared_to(position)
		if d2 < best_d2:
			best_d2 = d2
			best = w
	if best == null:
		return
	var to_w: Vector3 = best.global_position - position
	# Consume if very close.
	if to_w.length() < 0.25:
		# Snails eat detritus -> tiny pellet output (recycle).
		sim.waste.erase(best)
		(best as Node3D).queue_free()
		# Tiny snail pellet on the substrate at our position.
		if sim.has_method("_spawn_waste"):
			sim._spawn_waste(global_position + Vector3(0, -0.05, 0), 0.04,
				WasteParticle.KIND_SNAIL)
		return
	# Project the to_w vector into wall-tangent space and override direction.
	var dx: float = to_w.dot(tangent)
	var dy: float = to_w.dot(up)
	var dir := Vector2(dx, dy)
	if dir.length() > 0.01:
		_direction = dir.normalized()
		_paused = false


func _get_sim() -> Node:
	# Walk up the scene tree to find the SimDriver. Cheap - happens at sim
	# rate but only when the snail considers a turn (rare).
	var n: Node = get_parent()
	while n != null:
		var d := n.get_node_or_null("SimDriver")
		if d != null:
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
	var new_size: float = clampf(shell_size + randf_range(-0.08, 0.08), 0.65, 1.5)
	sac.set("inherited_shell_color", new_color)
	sac.set("inherited_shell_size", new_size)
	sac.set("inherited_generation", generation + 1)


func _choose_new_direction() -> void:
	_t_until_turn = randf_range(TURN_INTERVAL_MIN, TURN_INTERVAL_MAX)
	_paused = randf() < PAUSE_CHANCE
	if _paused:
		return
	var ang := randf() * TAU
	_direction = Vector2(cos(ang), sin(ang))
