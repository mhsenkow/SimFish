# Crawling snail. Slides slowly along a tank-glass wall.
#
# The snail picks a direction in the tangent plane of its wall and inches that
# way. Periodically it pauses or turns. It clamps to a rectangle on the wall
# so it can't slide off into geometry.

extends Node3D

const CreatureNaming = preload("res://scripts/creature_naming.gd")

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
# ---- Expanded shell architecture (heritable) ----
# Defaults reproduce the original turbo spiral so existing saves are unchanged.
# spire_height stretches the spire vertically (low turbo → tall tower/cerith),
# whorl_count sets the number of coil segments, aperture_flare adds a flared
# lip (conch/apple), operculum draws the trapdoor disc (nerite/turbo), and
# shell_pattern picks the banding style.
@export var spire_height: float = 1.0      # 0.4..2.0 vertical stretch of the spire
@export var whorl_count: int = 4           # 3..8 number of shell coil segments
@export var aperture_flare: float = 0.0    # 0..1 flared aperture lip (conch / apple)
@export var operculum: bool = false        # trapdoor disc at the foot opening
@export var shell_pattern: int = 0         # 0 plain / 1 bands / 2 spots / 3 zigzag (nerite)
# Continuous shell-pattern modulators: scale sizes each band / spot, density adds
# more of them. Toxic lineages drift toward denser, bolder markings (aposematism).
@export var shell_pattern_scale: float = 0.5
@export var shell_pattern_density: float = 0.5
var snail_name: String = ""
var parent_lineage: String = "Founders"
var _parent_keys: Array = []

const SPEED: float = 0.18                  # units per second; ~3 minutes coast-to-coast
const TURN_INTERVAL_MIN: float = 6.0
const TURN_INTERVAL_MAX: float = 14.0
# Halved from 0.30 — the old chance produced multi-second freezes every
# few turns, which read as "broken" rather than "resting." 0.15 keeps
# the resting-pause behavior occasional, and PAUSE_DURATION_* below
# caps each pause to a short interval so motion resumes quickly.
const PAUSE_CHANCE: float = 0.15
const PAUSE_DURATION_MIN: float = 1.0
const PAUSE_DURATION_MAX: float = 4.0

# Breeding + lifecycle. Snails are prolific; reproduction is gated on
# energy/hunger and limited by food supply, predators, and finite lifespan.
const BREEDING_INTERVAL_MIN: float = 120.0
const BREEDING_INTERVAL_MAX: float = 240.0
const MATURITY_AGE: float = 60.0          # baby -> adult after a minute
const LIFESPAN_S: float = 720.0           # 12-minute lifespan; senescence at end

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
var _crawl_speed_smoothed: float = 0.0      # eased scalar speed (avoids pulse stutter)
var _spacing_push: Vector3 = Vector3.ZERO   # soft overlap resolve, decayed per frame
var _t_until_turn: float = 0.0
var _paused: bool = false
# True when ANY fish is hovering close above us — even a non-predator fish.
# Snails freeze entirely (no crawl, no breeding) until the fish moves on.
# Kept separate from _paused so the other pause reasons (turn-pause, food
# break, etc.) aren't disrupted by adding/removing this signal.
var _fish_hover_freeze: bool = false
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
var _operculum_pivot: Node3D = null
var _operculum_ext: float = 0.0
var _eye_phase: float = 0.0
var _eye_retract_timer: float = 0.0
var _eye_retract_remaining: float = 0.0
# Eye scan saccade — when paused, the snail twitches its stalks toward a
# random target every ~2.4 s, then drifts back. The brief look-around
# read is the difference between "alive but resting" and "frozen voxel."
var _eye_scan_t: float = 0.0
var _eye_scan_target: Vector2 = Vector2.ZERO
# Stuck detection — accumulates when the snail tries to crawl but barely
# moves. Catches hardscape collisions, corner clipping, and any other
# obstruction generically without per-voxel hardscape scanning. Reset on
# successful progress; when it crosses STUCK_THRESHOLD the snail picks
# a fresh heading and a short re-orient pause.
var _stuck_timer: float = 0.0
var _last_progress_pos: Vector3 = Vector3.ZERO
const STUCK_THRESHOLD: float = 1.4
const STUCK_PROGRESS_MIN_SQ: float = 0.008 * 0.008  # ~8 mm minimum progress
# Cooldown between wall transitions so a snail at the substrate-glass
# corner doesn't oscillate between climbing and descending each scan
# tick. 1.5 s is enough for the snail to crawl meaningfully away from
# the corner on its new wall before another transition can fire.
var _wall_transition_cooldown: float = 0.0
const WALL_TRANSITION_COOLDOWN: float = 1.5
# Set when the snail is attached to a CURVED tank wall (cylinder or
# sphere). Curved walls don't have a single fixed inward normal —
# wall_normal varies continuously around the surface. When this is
# true, _reclamp_to_footprint recomputes wall_normal each tick from
# the current radial direction and snaps the snail back to the curve
# instead of constraining it to a fixed plane via _wall_anchor_offset.
var _curved_attached: bool = false
# When the snail is climbing a plant trunk, hold a weak ref to that
# plant so _reclamp_to_footprint can project the snail back to the
# trunk surface each tick (the trunk is a per-plant cylinder, not a
# tank-level curve — tank_lateral_boundary_info doesn't help here).
# Cleared whenever the snail transitions to a different surface.
var _attached_plant: Node3D = null
# Eating pulse — set whenever the snail consumes something (waste, algae,
# biofilm, plant rasp). Drives a 1.2 s amplified body wave so the bite
# reads visually instead of being silent. Decays per tick.
var _eating_pulse_remaining: float = 0.0
const EATING_PULSE_DURATION: float = 1.2
# Wander heading drift — every tick we rotate _direction by a small
# random angle so the crawl curves naturally instead of straight-lining
# between major turns. Phase carried so the drift isn't pure noise.
var _wander_phase: float = 0.0
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
const MAX_STEP_DT: float = 0.05             # stabilizes motion at high time_scale
const FACING_TURN_RATE: float = 5.5
const STEER_RATE: float = 4.0               # food / retreat heading blend
const ORIENT_RATE: float = 6.0
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
		"spire_height": spire_height,
		"whorl_count": whorl_count,
		"aperture_flare": aperture_flare,
		"operculum": operculum,
		"shell_pattern": shell_pattern,
		"shell_pattern_scale": shell_pattern_scale,
		"shell_pattern_density": shell_pattern_density,
		"generation": generation,
		"snail_name": snail_name,
		"parent_lineage": parent_lineage,
		"parent_keys": _parent_keys.duplicate(),
	}


func apply_genome_metadata(g: Dictionary) -> void:
	if g.is_empty():
		return
	# Library + save data store colors as [r,g,b,a] arrays. Convert before
	# assigning to the typed Color fields — passing the Array directly
	# crashes ("Trying to assign value of type 'Array' to 'Color'").
	shell_color = _coerce_color(g.get("shell_color", shell_color), shell_color)
	shell_size = float(g.get("shell_size", shell_size))
	shell_shape = String(g.get("shell_shape", shell_shape))
	shell_spines = clampf(float(g.get("shell_spines", shell_spines)), 0.0, 1.0)
	toxin_level = clampf(float(g.get("toxin_level", toxin_level)), 0.0, 1.0)
	body_color = _coerce_color(g.get("body_color", body_color), body_color)
	shell_accent_color = _coerce_color(g.get("shell_accent_color", shell_accent_color), shell_accent_color)
	crawl_speed = clampf(float(g.get("crawl_speed", crawl_speed)), 0.3, 2.5)
	appetite = clampf(float(g.get("appetite", appetite)), 0.4, 2.0)
	max_age_s = maxf(60.0, float(g.get("max_age_s", max_age_s)))
	spire_height = clampf(float(g.get("spire_height", spire_height)), 0.4, 2.0)
	whorl_count = clampi(int(g.get("whorl_count", whorl_count)), 3, 8)
	aperture_flare = clampf(float(g.get("aperture_flare", aperture_flare)), 0.0, 1.0)
	operculum = not not g.get("operculum", operculum)
	shell_pattern = int(g.get("shell_pattern", shell_pattern))
	shell_pattern_scale = clampf(float(g.get("shell_pattern_scale", shell_pattern_scale)), 0.0, 1.0)
	shell_pattern_density = clampf(float(g.get("shell_pattern_density", shell_pattern_density)), 0.0, 1.0)
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
	# AIDirector path (with offline fallback). Snails don't carry
	# personality or bio — they're too uniform behaviorally for the
	# personality vector to read as anything — but they still get
	# AI-flavored names when Ollama is on.
	var ai: Node = null
	if is_inside_tree():
		ai = get_node_or_null("/root/AIDirector")
	if ai != null and ai.has_method("consume_name"):
		var picked: Dictionary = ai.consume_name("snail", {})
		snail_name = String(picked.get("name", "Snail"))
	else:
		snail_name = CreatureNaming.generate_name("snail", {})


# Coerce any color-shaped value (Color, [r,g,b,a] Array, or other) into a
# Color. Centralised because the library/save layer hands us arrays
# while runtime callers hand us Colors, and a typed assign of an Array
# crashes the engine.
func _coerce_color(v: Variant, default_c: Color) -> Color:
	if v is Color:
		return v
	if v is Array:
		return SaveHelpers.array_to_color(v, default_c)
	return default_c


func _ready() -> void:
	# Join the "snails" group so neighbor scans (local spacing, overlap
	# resolution) can identify sibling snails with a fast group check instead
	# of comparing each sibling's script resource_path string.
	add_to_group("snails")
	_ensure_named()
	_choose_new_direction()
	_facing = _direction
	_crawl_speed_smoothed = SPEED * crawl_speed
	_t_until_breed = randf_range(BREEDING_INTERVAL_MIN, BREEDING_INTERVAL_MAX)
	_pulse_phase = randf() * TAU
	_eye_phase = randf() * TAU
	_eye_retract_timer = randf_range(EYE_RETRACT_INTERVAL_MIN, EYE_RETRACT_INTERVAL_MAX)
	_eye_stalks = get_node_or_null("EyeStalks") as Node3D
	_operculum_pivot = get_node_or_null("Operculum") as Node3D
	if _operculum_pivot != null:
		_operculum_pivot.visible = false
	if is_baby:
		scale = Vector3.ONE * 0.5
	# Lock the wall plane to the spawn position. World.gd places snails on a
	# specific wall (back glass, side glass, or substrate floor); we want
	# motion to stay on that exact plane forever, regardless of what the
	# wall_min / wall_max box-clamp would otherwise permit.
	_wall_anchor_offset = wall_normal.dot(position)
	call_deferred("_sync_initial_orientation")


func _process(dt: float) -> void:
	# Honor sim time_scale so pause/fast-forward affect snails too.
	var sim := _get_sim()
	if sim != null:
		dt *= float(sim.time_scale)
		if dt <= 0.0:
			return
	dt = minf(dt, MAX_STEP_DT)
	age += dt
	# Death by old age. queue_free with a small chance of leaving a shell
	# voxel behind (not done here - just remove). Lifespan is genome-driven
	# (max_age_s), defaulting to the class LIFESPAN_S.
	if age >= max_age_s:
		_return_shell_minerals()
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
		# Freeze-under-fish: even a harmless fish hovering close makes the
		# snail go still. Re-checks every scan tick so it un-freezes the
		# moment the fish drifts away.
		_check_fish_hover_freeze()
		# Wall transition checks — try every scan tick if we just haven't
		# recently transitioned. Cooldown prevents a snail at the
		# substrate-glass corner from oscillating climb/descend every
		# scan tick.
		_wall_transition_cooldown = maxf(0.0, _wall_transition_cooldown - scan_dt)
		if _retreat_remaining <= 0.0 and not _clamped and _wall_transition_cooldown <= 0.0:
			# Glass → substrate descent for snails on vertical glass.
			if _try_descend_to_substrate():
				_wall_transition_cooldown = WALL_TRANSITION_COOLDOWN
			# Substrate → glass climb for snails on the floor near a
			# wall. The boundary-bounce hook this used to live in
			# never actually fires (the reclamp keeps substrate snails
			# >0.34 from any wall, well clear of the bounce trigger),
			# so the climb has to be proactive on a proximity check.
			elif _try_climb_onto_glass():
				_wall_transition_cooldown = WALL_TRANSITION_COOLDOWN
			# Hardscape attach — climb onto rocks / driftwood when
			# crawling close to one.
			elif _try_attach_to_hardscape():
				_wall_transition_cooldown = WALL_TRANSITION_COOLDOWN
			# Plant attach — climb up a stem to graze canopy algae.
			elif _try_attach_to_plant():
				_wall_transition_cooldown = WALL_TRANSITION_COOLDOWN

	# Fast-path predator retract — checked every tick (not gated by the
	# 0.3 s scan accumulator). The 0.3 s latency of _check_predator_threat
	# was reading as "frozen, not responsive" when a fast fish darted past;
	# this gives an immediate stalk-pull while leaving the heavier clamp
	# decision on the throttled scan. Cheap: bails when no predators exist.
	_check_immediate_predator_retract()
	# Eye stalk animation runs in every state (clamped, paused, crawling).
	# Slow sway is the resting wiggle real snails do as they sense around;
	# periodic retraction is the brief stalk-pull when they reset their
	# field of view. While the body is clamped into the shell, the stalks
	# are pulled in entirely (scale 0). Movement-state independent so the
	# tank doesn't go visually dead when snails pause.
	_tick_eye_stalks(dt)
	_tick_operculum(dt)

	# When clamped we suspend movement entirely - foot's pulled in, no
	# crawling, no foraging, no breeding decision needed. Skip the rest
	# of the tick.
	if _clamped:
		_apply_squash(0.35)  # body flattened into shell
		return

	# Fish-hover freeze: even harmless tankmates make the snail go still
	# while they hover overhead. Skip movement/breed/feed decisions until
	# the fish drifts away — eye stalks already retracted in the check.
	if _fish_hover_freeze:
		_apply_squash(0.55)  # body slightly tucked
		return

	# Decay the eating-pulse amplifier. Set in _check_waste_nearby on a
	# consume event; _apply_squash reads it to amplify the body wave for
	# the duration so the bite has visible weight.
	if _eating_pulse_remaining > 0.0:
		_eating_pulse_remaining = maxf(0.0, _eating_pulse_remaining - dt)

	# Post-threat behavior: once we un-clamp, continue a short retreat toward
	# nearby hardscape so snail-predator encounters produce visible "hide"
	# movement rather than immediate normal grazing.
	if _retreat_remaining > 0.0:
		_retreat_remaining = maxf(0.0, _retreat_remaining - dt)

	_t_until_turn -= dt
	if _t_until_turn <= 0.0:
		_choose_new_direction()

	# Breeding: lay an egg sac once the timer expires when well-fed. Predators,
	# starvation, and substrate competition keep the colony in check.
	#
	# Predator-rebound: when no snail-hunters (loach / puffer) are in the
	# tank, snail breeding accelerates — the visible "no predators, snail
	# boom" dynamic you see in real tanks after a loach dies. We halve the
	# next breeding interval, doubling the laying rate. When a hunter is
	# present, intervals are normal and hunger/energy gates keep growth in check.
	if not is_baby:
		_t_until_breed -= dt
		if _t_until_breed <= 0.0:
			var w := _world_node()
			var at_cap: bool = false
			if w != null and w.has_method("snail_carrying_capacity"):
				var sim_n := _get_sim()
				if sim_n != null:
					at_cap = _count_snails() >= int(w.snail_carrying_capacity())
			if not at_cap and energy >= BREED_ENERGY_MIN and hunger <= BREED_HUNGER_MAX:
				_lay_egg_sac()
				energy = clampf(energy - 0.2, 0.0, 1.0)
				hunger = clampf(hunger + 0.15, 0.0, 1.0)
			var rebound: float = 1.0
			var sim_n2 := _get_sim()
			if sim_n2 != null and int(sim_n2.snail_predator_count) == 0:
				rebound = 0.5
			# Food-crash coupling (#37): when detritus runs low the colony's
			# breeding slows sharply well before starvation, so the classic
			# snail boom-then-bust plays out instead of a flat population.
			var food_mult: float = 1.0
			if sim_n2 != null:
				food_mult = lerpf(2.4, 1.0,
					clampf(float(sim_n2.waste.size()) / 24.0, 0.0, 1.0))
			_t_until_breed = randf_range(BREEDING_INTERVAL_MIN,
				BREEDING_INTERVAL_MAX) * rebound * food_mult

	# Build tangent + bitangent vectors for this wall. Both must lie IN the
	# wall plane (perpendicular to wall_normal); using `up` as the second axis
	# was broken for floor/ceiling walls (where wall_normal ≈ up), because
	# then the "vertical" move on the wall actually pushed the snail through
	# the wall normal — straight out of the glass.
	var tangent: Vector3
	if absf(wall_normal.dot(Vector3.UP)) > 0.95:
		tangent = Vector3.RIGHT
	else:
		tangent = wall_normal.cross(Vector3.UP).normalized()
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
		_check_waste_nearby(tangent, bitangent, dt)
	elif _retreat_remaining > 0.0 and _retreat_target != Vector3.INF:
		var to_cover: Vector3 = _retreat_target - global_position
		var rx: float = to_cover.dot(tangent)
		var ry: float = to_cover.dot(bitangent)
		var retreat_dir := Vector2(rx, ry)
		if retreat_dir.length() > 0.01:
			_steer_direction(retreat_dir.normalized(), dt)
			_paused = false

	# Wander drift — tiny continuous heading perturbation between major
	# turns so the crawl path curves naturally instead of straight-lining
	# from one turn to the next. The drift is sin-driven so it visibly
	# wanders S-shaped on a long crawl, with a small random component on
	# top so two snails on the same wall don't trace identical paths.
	# Skipped while pursuing food (we want a direct line) or retreating.
	if not _pursuing_waste and _retreat_remaining <= 0.0:
		_wander_phase += dt * 0.8
		var wander_amp: float = 0.018 * dt * 60.0  # framerate-independent
		var wander_angle: float = sin(_wander_phase) * wander_amp \
			+ randf_range(-wander_amp * 0.4, wander_amp * 0.4)
		_direction = _direction.rotated(wander_angle)
		if _direction.length_squared() > 1e-6:
			_direction = _direction.normalized()

	# Smoothly turn crawl heading toward the target direction.
	_facing = _facing.lerp(_direction, clampf(dt * FACING_TURN_RATE, 0.0, 1.0))
	if _facing.length_squared() > 1e-6:
		_facing = _facing.normalized()

	# Foot-pulse motion. Phase advances at ~1.5 Hz; speed and shell-vertical
	# squash are modulated by sin(phase), creating a "creep" gait. Snails
	# move noticeably only on the forward stroke of the pulse.
	if _paused:
		# Still pulse a little when paused (breathing).
		_pulse_phase += dt * 0.6
		var idle_squash: float = 1.0 + sin(_pulse_phase) * 0.04
		_apply_squash(idle_squash)
		_apply_wall_orientation(tangent * _facing.x + bitangent * _facing.y, dt)
		return

	# Pulse rate jumps when pursuing detritus - the snail visibly speeds up
	# toward food, which is the real "cleaner crew converging" pattern.
	var pulse_rate: float = 2.2 if _pursuing_waste else 1.35
	_pulse_phase += dt * pulse_rate
	var pulse_factor: float = 0.5 + 0.5 * sin(_pulse_phase)  # 0..1
	var speed_mult: float = 1.25 if _pursuing_waste else 1.0
	if _retreat_remaining > 0.0:
		speed_mult *= RETREAT_SPEED_MULT
	# Keep crawl speed mostly steady; pulse drives the foot wave, not stop-go.
	var target_speed: float = SPEED * crawl_speed * speed_mult
	_crawl_speed_smoothed = move_toward(
		_crawl_speed_smoothed, target_speed, 0.45 * dt)
	var gait_speed: float = _crawl_speed_smoothed * (0.94 + 0.06 * pulse_factor)
	var crawl_dir: Vector3 = tangent * _facing.x + bitangent * _facing.y
	if crawl_dir.length_squared() > 1e-6:
		crawl_dir = crawl_dir.normalized()
		var pre_move: Vector3 = position
		position += crawl_dir * gait_speed * dt
		_apply_wall_orientation(crawl_dir, dt)
		_handle_boundary_bounce(tangent, bitangent, pre_move)
		# Stuck-detection. If the snail wanted to move (gait_speed
		# meaningful) but the boundary bounce / reclamp / hardscape pulled
		# us back to almost-the-same position, accumulate the stuck timer
		# and eventually force a turn. This generic version replaces
		# per-voxel hardscape scanning — catches any obstacle.
		if gait_speed > 0.02:
			var actual_move_sq: float = (position - pre_move).length_squared()
			if actual_move_sq < STUCK_PROGRESS_MIN_SQ:
				_stuck_timer += dt
				if _stuck_timer > STUCK_THRESHOLD:
					_stuck_timer = 0.0
					_choose_new_direction()
					# Force unpause if _choose rolled a pause — being
					# stuck and then deciding to sit still reads as
					# broken; we want a heading change.
					_paused = false
					# Quick re-attempt so we don't sit still again.
					_t_until_turn = randf_range(0.4, 1.2)
			else:
				_stuck_timer = maxf(0.0, _stuck_timer - dt * 1.5)
	else:
		_apply_wall_orientation(tangent, dt)

	# Visual squash: subtle foot wave (decoupled from translation speed).
	var squash: float = 1.0 + (pulse_factor - 0.5) * 0.12
	_apply_squash(squash)

	# Soft spacing nudge (accumulated on scan ticks, eased here every frame).
	if _spacing_push.length_squared() > 1e-8:
		position += _spacing_push * clampf(dt * 14.0, 0.0, 1.0)
		_spacing_push = _spacing_push.lerp(Vector3.ZERO, clampf(dt * 10.0, 0.0, 1.0))

	_reclamp_to_footprint()
	if not _paused and gait_speed > 0.02:
		var wn := _world_node()
		if wn != null:
			var av = _aquarium_visuals()
			if av != null:
				# State-driven slime intensity. Real snails produce more
				# mucus when feeding (the rasping radula needs lubrication)
				# and less when just transiting. Pursuit-of-food mode
				# bumps the rate ~2×, recent eating pulse bumps it ~3×,
				# normal crawl uses the baseline rate.
				var rate: float = 0.32
				if _pursuing_waste:
					rate = 0.55
				if _eating_pulse_remaining > 0.0:
					rate = 0.90
				if randf() < dt * rate:
					av.spawn_snail_slime(global_position, wall_normal)
					av.record_compaction(global_position.x, global_position.z)
				if randf() < dt * 0.012:
					av.spawn_snail_bubble(global_position + wall_normal * 0.05)
	# Local spacing so wall snails don't visually stack into one clump. Runs on
	# the same 0.3 s scan cadence as the predator/food scans — it iterates all
	# sibling snails, so per-frame was wasteful; snails crawl slowly enough that
	# 0.3 s spacing updates are visually identical.
	if scan_due:
		_apply_local_spacing(tangent, bitangent)


func _check_waste_nearby(tangent: Vector3, bitangent: Vector3, dt: float) -> void:
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
	# Lush-tank bonus: when the tank's planted area is dense, snails crop
	# more aggressively (more food in arm's reach, less wandering cost).
	# This is the negative-feedback brake against monoculture takeover —
	# without it, fast-growing stems just hit max_height and sit there.
	var lush_plant_gate: float = 0.45
	var lush_biomass: int = int(sim.get("total_plant_biomass") if sim.get("total_plant_biomass") != null else 0)
	if lush_biomass > 250:
		lush_plant_gate = clampf(0.45 + (float(lush_biomass) - 250.0) / 500.0, 0.45, 0.85)
	if best == null and sim.get("plants") != null and randf() < lush_plant_gate:
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
	# Rare climb floater roots (#36).
	if best == null and sim != null and randf() < 0.06:
		var w_sn: Node = sim.get_parent()
		if w_sn != null and w_sn.has_method("query_floaters_in_radius"):
			for fp in w_sn.query_floaters_in_radius(global_position, 1.8):
				if fp is FloatingPlant and (fp as FloatingPlant).root_length_current > 0.25:
					var d2f: float = fp.global_position.distance_squared_to(global_position)
					if d2f < best_d2:
						best_d2 = d2f
						best = fp

	if best == null:
		_pursuing_waste = false
		return
	# Compare in global space consistently — both endpoints in global, so
	# the snail's parent transform doesn't skew the comparison.
	var to_w: Vector3 = best.global_position - global_position
	# Consume if very close.
	if to_w.length() < 0.25:
		if best is WasteParticle:
			# It's waste — type-checked so we never try to erase a non-waste
			# node (algae / plant / floater) from the typed waste array.
			var nv_consumed: float = float(best.get("nutrient_value") if best.get("nutrient_value") != null else 0.1)
			sim.waste.erase(best)
			(best as Node3D).queue_free()
			hunger = clampf(hunger - FEED_WASTE, 0.0, 1.0)
			# Detritivore → biofilm feedback. The snail's rasping breaks
			# the waste into bacteria-accessible fragments — biofilm grows
			# slightly faster, which in turn speeds the N-cycle. This is
			# the trophic level that makes a Walstad tank work.
			var wn_bio := _world_node()
			if wn_bio != null and wn_bio.has_method("boost_biofilm"):
				wn_bio.boost_biofilm(nv_consumed)
		else:
			# It's algae, plant, coral, or floater.
			if best is FloatingPlant:
				(best as FloatingPlant).nibble(1)
				hunger = clampf(hunger - FEED_PLANT, 0.0, 1.0)
			elif best.has_method("nibble"):
				if best.has_method("top_world_y"):
					best.nibble(1)   # rooted plant/coral: slow rasping
					hunger = clampf(hunger - FEED_PLANT, 0.0, 1.0)
				else:
					best.nibble(999) # algae cluster: can clear quickly
					hunger = clampf(hunger - FEED_ALGAE, 0.0, 1.0)
		# Trigger the visible eating pulse — _apply_squash amplifies the
		# body wave for EATING_PULSE_DURATION so the bite reads as a
		# distinct beat instead of a silent consume.
		_eating_pulse_remaining = EATING_PULSE_DURATION
		# Tiny snail pellet on the substrate at our position.
		if sim.has_method("_spawn_waste"):
			sim._spawn_waste(global_position + Vector3(0, -0.05, 0), 0.04,
				WasteParticle.KIND_SNAIL)
		# Squeeze of slime at the bite point — real snails leave a thicker
		# mucus deposit where they've been actively rasping.
		var wn := _world_node()
		if wn != null:
			var av = _aquarium_visuals()
			if av != null and av.has_method("spawn_snail_slime"):
				av.spawn_snail_slime(global_position, wall_normal)
		return
	# Project the to_w vector into wall-tangent space and override direction.
	var dx: float = to_w.dot(tangent)
	var dy: float = to_w.dot(bitangent)
	var dir := Vector2(dx, dy)
	if dir.length() > 0.01:
		_steer_direction(dir.normalized(), dt)
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


func _sync_initial_orientation() -> void:
	var tangent: Vector3
	if absf(wall_normal.dot(Vector3.UP)) > 0.95:
		tangent = Vector3.RIGHT
	else:
		tangent = wall_normal.cross(Vector3.UP).normalized()
	var bitangent: Vector3 = tangent.cross(wall_normal).normalized()
	_apply_wall_orientation(tangent * _facing.x + bitangent * _facing.y, 1.0)


# Wall transition probability. A snail that hits a corner only climbs /
# descends most of the time — sometimes they turn back, which keeps the
# population spread across multiple surfaces rather than draining onto
# the glass.
const WALL_TRANSITION_CHANCE: float = 0.80
# When transitioning, how far to nudge the snail onto the new wall so
# it doesn't immediately re-trigger the boundary handler.
const WALL_TRANSITION_NUDGE: float = 0.10


# Try to climb from the substrate onto an adjacent vertical glass wall.
# Returns true if a transition happened. Called from the crawl path
# whenever the snail is within CLIMB_PROXIMITY of a tank wall — earlier
# this was hooked into _handle_boundary_bounce, but that path only
# triggers when the snail has pushed PAST the lateral boundary, and the
# reclamp keeps them clear of that boundary entirely. Proximity-based
# triggering means a substrate snail walking near the glass will reach
# the corner and start climbing as expected.
const CLIMB_PROXIMITY: float = 0.32

func _try_climb_onto_glass() -> bool:
	# Only meaningful for substrate snails.
	if absf(wall_normal.dot(Vector3.UP)) < 0.95:
		return false
	var w := _world_node()
	if w == null or not w.has_method("tank_lateral_boundary_info"):
		return false
	# `inward` points perpendicular to the closest tank wall, INTO the
	# tank interior. For an axis-aligned tank this is one of (±1,0,0) /
	# (0,0,±1); for cylinder/sphere it's the radial direction from the
	# tank's central axis to the wall surface.
	var info: Dictionary = w.tank_lateral_boundary_info(global_position, 0.0)
	var inward: Vector3 = info.get("inward", Vector3.ZERO)
	var clearance: float = float(info.get("clearance", 99.0))
	if inward.length_squared() < 0.1:
		return false
	# Only climb when we're within CLIMB_PROXIMITY of the wall.
	if clearance > CLIMB_PROXIMITY:
		return false
	inward = inward.normalized()
	# Detect curved vs flat walls. For axis-aligned (box) tanks `inward`
	# is close to a cardinal direction; for cylinder/sphere it points
	# radially at any angle.
	var max_axis: float = maxf(maxf(absf(inward.x), absf(inward.y)), absf(inward.z))
	var is_curved: bool = max_axis < 0.92
	if is_curved:
		# Only accept curved climbs on tank shapes that actually have a
		# well-defined curved wall surface — cylinder + sphere. Other
		# polygon tanks fall through to the flat-wall test instead.
		var shape_v: Variant = w.get("TANK_SHAPE")
		var shape: String = String(shape_v) if shape_v != null else "box"
		if shape != "cylinder" and shape != "sphere":
			return false
	if randf() > WALL_TRANSITION_CHANCE:
		return false

	# Commit the transition.
	wall_normal = inward
	_curved_attached = is_curved
	_attached_plant = null  # leaving any plant trunk attachment
	# Snap Y just above the substrate so the snail visibly sits on the
	# glass right above the substrate-glass corner. The lateral X/Z
	# stay where they are (we were already at the boundary).
	var substrate_y: float = 1.6
	var sub_v: Variant = w.get("SUBSTRATE_DEPTH")
	if sub_v != null:
		substrate_y = float(sub_v)
	global_position.y = substrate_y + WALL_TRANSITION_NUDGE
	# Re-anchor the plane. _wall_anchor_offset is the projection of
	# position onto the new wall_normal — for flat walls this is the
	# fixed plane offset. For curved walls it's recomputed every tick
	# in _reclamp_to_footprint, but we set a sensible initial value.
	_wall_anchor_offset = wall_normal.dot(global_position)
	# For curved attaches, snap the snail to the actual wall surface
	# first by stepping outward (opposite of inward) by the clearance.
	if is_curved:
		global_position -= inward * clearance
	# Set heading to "climb up." On any vertical glass wall:
	#   tangent  = horizontal-in-wall  (depends on wall_normal)
	#   bitangent = world UP
	# so _facing.y > 0 → upward motion.
	_direction = Vector2(randf_range(-0.20, 0.20), 1.0).normalized()
	_facing = _direction
	# Reset stuck timer + force orientation re-sync immediately (not
	# deferred — the next crawl tick needs the correct basis).
	_stuck_timer = 0.0
	_last_progress_pos = global_position
	_sync_initial_orientation()
	return true


# Try to descend from a vertical glass wall down onto the substrate.
# Called periodically (scan_due) — a glass snail crawling along the
# substrate-glass corner doesn't go OUTSIDE the tank, so boundary_bounce
# never fires for them; this is the path that catches that case.
func _try_descend_to_substrate() -> bool:
	# Only meaningful for snails on vertical glass.
	if absf(wall_normal.dot(Vector3.UP)) > 0.55:
		return false
	var w := _world_node()
	if w == null:
		return false
	var substrate_y: float = 1.6
	var sub_v: Variant = w.get("SUBSTRATE_DEPTH")
	if sub_v != null:
		substrate_y = float(sub_v)
	# Only descend when we're already very close to the substrate floor.
	if global_position.y > substrate_y + 0.18:
		return false
	if randf() > WALL_TRANSITION_CHANCE:
		return false

	# Commit the transition.
	var old_wall_normal: Vector3 = wall_normal
	wall_normal = Vector3.UP
	_curved_attached = false  # substrate is flat
	_attached_plant = null
	# Land just above the substrate, and nudge slightly AWAY from the
	# old glass so the next tick doesn't immediately re-trigger climb.
	global_position.y = substrate_y + WALL_TRANSITION_NUDGE
	global_position += old_wall_normal * WALL_TRANSITION_NUDGE
	# Re-clamp inside the tank in case the nudge pushed us out.
	if w.has_method("clamp_xyz_in_tank"):
		global_position = w.clamp_xyz_in_tank(global_position, 0.30, 0.10)
	_wall_anchor_offset = wall_normal.dot(global_position)
	# On the substrate: tangent = RIGHT, bitangent = RIGHT × UP = (0,0,-1).
	# We want to head AWAY from the glass we just descended from. The
	# old wall_normal was the perpendicular-into-tank direction of that
	# glass, so moving in +old_wall_normal moves us into the tank.
	var new_tangent: Vector3 = Vector3.RIGHT
	var new_bitangent: Vector3 = new_tangent.cross(Vector3.UP).normalized()
	_direction = Vector2(
		old_wall_normal.dot(new_tangent),
		old_wall_normal.dot(new_bitangent))
	if _direction.length_squared() < 1e-6:
		_direction = Vector2(1.0, 0.0)
	_direction = _direction.normalized()
	_facing = _direction
	_stuck_timer = 0.0
	_last_progress_pos = global_position
	_sync_initial_orientation()
	return true


# Try to attach to a hardscape voxel (rock or driftwood) the snail is
# crawling near. Picks the closest hardscape voxel within HARDSCAPE_PROX,
# determines which face the snail is approaching from, and re-anchors
# wall_normal to that face's outward normal. Returns true on transition.
#
# Real freshwater snails (especially nerites, ramshorns) spend most of
# their grazing time on hardscape — that's where the biofilm + algae
# coats actually accumulate in a planted tank. Without this path the
# snails were stuck on the glass + substrate even when food was on the
# wood right next to them.
const HARDSCAPE_PROX: float = 0.42

func _try_attach_to_hardscape() -> bool:
	# Eligible from any starting wall. We skip if already on a curved
	# surface; "is on glass / substrate" is the only case currently.
	var sim := _get_sim()
	if sim == null:
		return false
	var root_v: Variant = sim.get("hardscape_root")
	if root_v == null or not (root_v is Node3D):
		return false
	var root: Node3D = root_v as Node3D
	if not is_instance_valid(root):
		return false
	# Walk hardscape voxels, find the closest one whose surface is within
	# HARDSCAPE_PROX of us. Capped iteration so a large hardscape doesn't
	# burn the tick.
	var children: Array = root.get_children()
	var n: int = mini(children.size(), 96)
	if n <= 0:
		return false
	var best: Node3D = null
	var best_d2: float = HARDSCAPE_PROX * HARDSCAPE_PROX
	for i in n:
		var h: Node3D = children[i] as Node3D
		if h == null or not is_instance_valid(h):
			continue
		var d2: float = (h.global_position - global_position).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = h
	if best == null:
		return false
	if randf() > WALL_TRANSITION_CHANCE:
		return false

	# Figure out which face we're nearest. Treat the voxel as a box;
	# whichever component of (snail - voxel) has the largest absolute
	# value points to the dominant face.
	var rel: Vector3 = global_position - best.global_position
	var ax: float = absf(rel.x)
	var ay: float = absf(rel.y)
	var az: float = absf(rel.z)
	var face_normal: Vector3
	if ay >= ax and ay >= az:
		# Top or bottom face — snails almost always sit on the top, so
		# bias UP when the relative Y is near zero (avoid hanging from
		# the underside of a driftwood log).
		if rel.y >= -0.02:
			face_normal = Vector3.UP
		else:
			face_normal = Vector3.DOWN
	elif ax >= az:
		face_normal = Vector3.RIGHT if rel.x >= 0.0 else Vector3.LEFT
	else:
		face_normal = Vector3.BACK if rel.z >= 0.0 else Vector3.FORWARD

	# Snap onto that face. Approximate voxel half-size from its mesh; we
	# don't read the BoxMesh.size directly because Plant voxels could be
	# multimeshed (no per-voxel mesh) — fall back to 0.25 as a typical
	# hardscape cube extent if we can't introspect.
	var voxel_half: float = 0.25
	var mi: MeshInstance3D = best as MeshInstance3D
	if mi != null and mi.mesh is BoxMesh:
		var bm: BoxMesh = mi.mesh as BoxMesh
		# Pick the half-size on the dominant axis.
		if face_normal.y != 0.0:
			voxel_half = bm.size.y * 0.5
		elif face_normal.x != 0.0:
			voxel_half = bm.size.x * 0.5
		else:
			voxel_half = bm.size.z * 0.5
	# New attach point: voxel center + face_normal * (half + small offset
	# so the snail's foot sits on the face surface, not inside it).
	var snail_offset: float = shell_size * 0.10 + 0.02
	var attach_pos: Vector3 = best.global_position + face_normal * (voxel_half + snail_offset)

	wall_normal = face_normal
	_curved_attached = false  # hardscape voxels have flat box faces
	_attached_plant = null
	global_position = attach_pos
	_wall_anchor_offset = wall_normal.dot(global_position)
	# Pick a sensible initial heading on the new face. For top faces use
	# substrate-like tangent (RIGHT); for side faces, climb up first.
	if absf(face_normal.dot(Vector3.UP)) > 0.95:
		# Top of a rock — head in a random tangent direction.
		var ang: float = randf() * TAU
		_direction = Vector2(cos(ang), sin(ang))
	else:
		# Side face — head upward (positive bitangent ≡ UP for vertical
		# face_normals), with a small lateral random component.
		_direction = Vector2(randf_range(-0.30, 0.30), 1.0).normalized()
	_facing = _direction
	_stuck_timer = 0.0
	_last_progress_pos = global_position
	_sync_initial_orientation()
	return true


# Try to attach to a plant the snail is crawling near. Treats each plant
# as a vertical cylinder (trunk) at plant.global_position; the snail
# attaches to the radial outward face when close enough. Once attached
# the wall_normal is the horizontal direction from the trunk axis toward
# the snail's position, so the snail crawls AROUND the stem (positive
# tangent) or UP/DOWN it (bitangent = UP for vertical wall normals).
const PLANT_PROX: float = 0.36
const PLANT_TRUNK_RADIUS: float = 0.18

func _try_attach_to_plant() -> bool:
	var sim := _get_sim()
	if sim == null:
		return false
	var plants_v: Variant = sim.get("plants")
	if plants_v == null or not (plants_v is Array):
		return false
	var plants_arr: Array = plants_v
	if plants_arr.is_empty():
		return false
	var best: Node3D = null
	var best_d2: float = PLANT_PROX * PLANT_PROX
	# Cap to avoid scanning hundreds of plants per scan tick.
	var n: int = mini(plants_arr.size(), 64)
	for i in n:
		var p_v: Variant = plants_arr[i]
		if not is_instance_valid(p_v) or not (p_v is Node3D):
			continue
		var p: Node3D = p_v as Node3D
		# Project distance into the horizontal plane only — vertical
		# clearance is unbounded along the trunk's length.
		var dx: float = p.global_position.x - global_position.x
		var dz: float = p.global_position.z - global_position.z
		var d2_xz: float = dx * dx + dz * dz
		# Snail must also be within the plant's vertical extent (trunk
		# height). Read current_height if available; fall back to 4 voxels.
		var trunk_top: float = p.global_position.y + 0.32 * 4.0
		var ch_v: Variant = p.get("current_height")
		if ch_v != null:
			trunk_top = p.global_position.y + 0.32 * float(int(ch_v))
		if global_position.y < p.global_position.y - 0.2 or global_position.y > trunk_top + 0.1:
			continue
		if d2_xz < best_d2:
			best_d2 = d2_xz
			best = p
	if best == null:
		return false
	if randf() > WALL_TRANSITION_CHANCE:
		return false

	# Compute the outward radial direction from trunk axis to snail.
	var radial: Vector3 = Vector3(
		global_position.x - best.global_position.x,
		0.0,
		global_position.z - best.global_position.z)
	if radial.length_squared() < 1e-4:
		# Snail is essentially ON the trunk axis — pick a random outward
		# direction so the new wall_normal is well-defined.
		var ang: float = randf() * TAU
		radial = Vector3(cos(ang), 0.0, sin(ang))
	radial = radial.normalized()

	# Wall normal = the outward radial direction (snail's shell points
	# outward from the trunk). The trunk is a per-plant cylinder, so
	# we track _attached_plant + clear _curved_attached (which is for
	# tank curves). _reclamp_to_footprint handles the plant case
	# separately by projecting back to the trunk surface each tick.
	wall_normal = radial
	_curved_attached = false
	_attached_plant = best
	# Snap snail position to the trunk surface at the current Y.
	var snail_offset: float = shell_size * 0.10 + 0.02
	global_position = Vector3(
		best.global_position.x + radial.x * (PLANT_TRUNK_RADIUS + snail_offset),
		global_position.y,
		best.global_position.z + radial.z * (PLANT_TRUNK_RADIUS + snail_offset))
	_wall_anchor_offset = wall_normal.dot(global_position)
	# Head upward along the stem with a tiny lateral wobble — snails
	# climbing a plant typically work upward to reach the canopy where
	# the freshest algae lives.
	_direction = Vector2(randf_range(-0.25, 0.25), 1.0).normalized()
	_facing = _direction
	_stuck_timer = 0.0
	_last_progress_pos = global_position
	_sync_initial_orientation()
	return true


func _steer_direction(target: Vector2, dt: float) -> void:
	if target.length_squared() < 1e-6:
		return
	_direction = _direction.lerp(target, clampf(dt * STEER_RATE, 0.0, 1.0))
	if _direction.length_squared() > 1e-6:
		_direction = _direction.normalized()


func _shell_up() -> Vector3:
	# Dorsal axis: world-up on the substrate, INTO the tank on vertical
	# glass. wall_normal is stored as the inward normal of the glass
	# (perpendicular pointing INTO the tank from the wall surface), and
	# Basis.looking_at(forward, up) aligns local +Y with `up`. The snail
	# body builds its shell at local +Y, so shell_up must equal the
	# inward normal = wall_normal itself, NOT its negation.
	#
	# The previous version returned -wall_normal, which put the shell on
	# the OUTWARD side of the snail — i.e. embedded in the glass with
	# the foot pointing INTO the tank. Reads as "snail facing wrong way."
	if absf(wall_normal.dot(Vector3.UP)) > 0.95:
		return Vector3.UP
	return wall_normal.normalized()


func _apply_wall_orientation(crawl_hint: Vector3, dt: float) -> void:
	var crawl_dir: Vector3 = crawl_hint
	if crawl_dir.length_squared() < 1e-6:
		return
	crawl_dir = crawl_dir.normalized()
	var up: Vector3 = _shell_up()
	if absf(crawl_dir.dot(up)) > 0.92:
		var tangent: Vector3 = wall_normal.cross(Vector3.UP)
		if tangent.length_squared() < 1e-6:
			tangent = Vector3.RIGHT
		crawl_dir = tangent.normalized()
	var target_basis: Basis = Basis.looking_at(crawl_dir, up)
	var current: Basis = transform.basis.orthonormalized()
	transform.basis = current.slerp(target_basis, clampf(dt * ORIENT_RATE, 0.0, 1.0))


var _av_cached: Node = null


# Cached AquariumVisuals node — the per-tick string lookup (slime / compaction
# while crawling) is resolved once; the node is stable for the tank's life.
func _aquarium_visuals() -> Node:
	if _av_cached != null and is_instance_valid(_av_cached):
		return _av_cached
	var wn := _world_node()
	if wn != null:
		_av_cached = wn.get_node_or_null("AquariumVisuals")
	return _av_cached


func _world_node() -> Node:
	var sim := _get_sim()
	if sim == null:
		return null
	return sim.get_parent()


# Shape-aware bounds: the legacy wall_min/wall_max AABB lies outside hex,
# triangle, cylinder, and sphere glass. Crawl stays on the spawn wall plane
# but X/Y/Z are pulled back inside the tank footprint every frame.
func _reclamp_to_footprint() -> void:
	var w := _world_node()
	# Tighter clamp margin so snails can actually crawl right up to the
	# glass surface (and approach hardscape voxels close enough to attach).
	# The previous 0.28 + shell_size*0.08 ≈ 0.34 kept them too far from
	# any wall to ever trigger the climb transition. Snail bodies are
	# small (shell_size * 0.20 across) so a margin matched to body_r is
	# plenty to keep voxels visibly inside the glass.
	var body_r: float = shell_size * 0.10
	var margin: float = body_r + 0.04
	if w == null:
		return
	# Plant-attached path: the trunk is a per-plant cylinder, so we
	# project back onto its surface at the snail's current Y. Walk away
	# from this branch if the plant has been freed (grazed down, died,
	# tank reset). When that happens, drop the snail to substrate so it
	# doesn't get stuck in air.
	if _attached_plant != null:
		if not is_instance_valid(_attached_plant):
			_attached_plant = null
		else:
			var pp: Vector3 = _attached_plant.global_position
			# Outward radial direction from trunk axis to snail (XZ only).
			var rad: Vector3 = Vector3(
				global_position.x - pp.x, 0.0, global_position.z - pp.z)
			if rad.length_squared() < 1e-4:
				# Snail wandered into the trunk axis (rare). Pick the
				# old wall_normal direction as outward.
				rad = Vector3(wall_normal.x, 0.0, wall_normal.z)
				if rad.length_squared() < 1e-4:
					rad = Vector3.RIGHT
			rad = rad.normalized()
			# Snap XZ to the trunk surface.
			global_position.x = pp.x + rad.x * PLANT_TRUNK_RADIUS
			global_position.z = pp.z + rad.z * PLANT_TRUNK_RADIUS
			# Keep Y inside the trunk's vertical extent — if the snail
			# climbed off the top, treat it as a drop and clear the
			# attachment so the next scan tick can pick a new surface.
			var trunk_top: float = pp.y + 0.32 * 4.0
			var ch_v: Variant = _attached_plant.get("current_height")
			if ch_v != null:
				trunk_top = pp.y + 0.32 * float(int(ch_v))
			if global_position.y > trunk_top + 0.05:
				_attached_plant = null  # off the top
			elif global_position.y < pp.y - 0.1:
				_attached_plant = null  # off the bottom
			else:
				wall_normal = rad
				_wall_anchor_offset = wall_normal.dot(global_position)
				return
	# Curved-wall path: the wall normal isn't fixed — it points radially
	# inward at every position on the curve. Snap the snail to the
	# nearest point on the tank's curved surface and recompute
	# wall_normal from the local inward direction. tank_lateral_boundary
	# _info gives us both: `clearance` is the distance from the snail to
	# the wall surface, and `inward` is the radial inward unit vector
	# at the snail's location.
	if _curved_attached and w.has_method("tank_lateral_boundary_info"):
		var info: Dictionary = w.tank_lateral_boundary_info(global_position, 0.0)
		var inward: Vector3 = info.get("inward", Vector3.ZERO)
		var clearance: float = float(info.get("clearance", 0.0))
		if inward.length_squared() > 0.01:
			inward = inward.normalized()
			# Project the snail onto the curve. clearance > 0 means we
			# drifted inward away from the wall; clearance < 0 means we
			# pushed through to the outside. Either way, subtract
			# `inward * clearance` to land on the surface.
			global_position -= inward * clearance
			wall_normal = inward
			# Maintain the scalar projection so any code reading
			# _wall_anchor_offset (mostly save/load) sees a consistent
			# value. For curved walls this scalar is only meaningful at
			# THIS instant — it gets recomputed next tick.
			_wall_anchor_offset = wall_normal.dot(global_position)
		# Clamp Y so we don't burrow into the substrate or break the
		# surface. Y stays whatever the crawl set it to within these
		# limits.
		var substrate_y_v: Variant = w.get("SUBSTRATE_DEPTH")
		var sub_y: float = 1.6 if substrate_y_v == null else float(substrate_y_v)
		var water_y_v: Variant = w.get("WATER_HEIGHT")
		var water_y: float = 6.5 if water_y_v == null else float(water_y_v)
		global_position.y = clampf(global_position.y, sub_y + 0.05, water_y - 0.10)
		return
	# Flat-wall + substrate path (unchanged): the wall is a fixed plane,
	# so we project onto _wall_anchor_offset and rely on clamp_xyz_in_tank
	# for tank-volume containment.
	if w.has_method("clamp_xyz_in_tank"):
		var plane_drift: float = wall_normal.dot(global_position) - _wall_anchor_offset
		if absf(plane_drift) > 1e-5:
			global_position -= wall_normal * plane_drift
		global_position = w.clamp_xyz_in_tank(global_position, margin, body_r)
		plane_drift = wall_normal.dot(global_position) - _wall_anchor_offset
		global_position -= wall_normal * plane_drift
		if w.has_method("is_inside_tank_volume") \
				and not w.is_inside_tank_volume(
					global_position.x, global_position.y, global_position.z, margin * 0.35):
			var safe: Vector3 = w.clamp_xyz_in_tank(
				Vector3(0.0, global_position.y, 0.0), margin, body_r)
			global_position = safe
			global_position -= wall_normal * (
				wall_normal.dot(global_position) - _wall_anchor_offset)
		return


func _handle_boundary_bounce(_tangent: Vector3, _bitangent: Vector3, _pre_move: Vector3) -> void:
	var w := _world_node()
	if w != null and w.has_method("is_inside_tank_volume"):
		var margin: float = 0.28 + shell_size * 0.06
		if w.is_inside_tank_volume(
				global_position.x, global_position.y, global_position.z, margin * 0.35):
			return
		# (Substrate→glass climbing now lives on the scan-tick proximity
		# check, not here — the reclamp keeps substrate snails far enough
		# from the boundary that this branch never fires for them. This
		# path now only handles curved-tank wall slides.)
		# Hit the curved / polygon wall — slide along the glass tangent.
		var plane_slide := Vector2(_direction.x, _direction.y)
		if w.has_method("tank_lateral_boundary_info"):
			var info: Dictionary = w.tank_lateral_boundary_info(global_position, margin * 0.55)
			var inward: Vector3 = info.get("inward", Vector3.ZERO)
			inward.y = 0.0
			if inward.length_squared() > 1e-6:
				inward = inward.normalized()
				var tangent3: Vector3 = Vector3(-inward.z, 0.0, inward.x)
				if tangent3.dot(_tangent * _direction.x + _bitangent * _direction.y) < 0.0:
					tangent3 = -tangent3
				plane_slide = Vector2(
					tangent3.dot(_tangent),
					tangent3.dot(_bitangent))
		if plane_slide.length_squared() < 1e-6:
			plane_slide = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
		# Soften the boundary reflection. The previous 90° flip made every
		# wall hit read as a hard snap turn; a smaller randomized angle
		# (45..80°) on whichever side actually points back inward gives
		# the snail a smooth curl along the curved glass instead of a
		# right-angle clip.
		var turn_sign: float = 1.0 if randf() > 0.5 else -1.0
		var turn_angle: float = randf_range(PI * 0.25, PI * 0.45) * turn_sign
		plane_slide = plane_slide.rotated(turn_angle)
		if plane_slide.length_squared() > 1e-6:
			# Lerp the new heading in rather than snapping — _facing's
			# slerp will catch up, but the underlying _direction also
			# eases so the next few ticks don't fight the old direction.
			_direction = _direction.lerp(plane_slide.normalized(), 0.65)
			if _direction.length_squared() > 1e-6:
				_direction = _direction.normalized()
		_t_until_turn = minf(_t_until_turn, randf_range(2.5, 5.0))
		return
	if w == null:
		return


func _apply_squash(squash_y: float) -> void:
	# Foot-wave creep — instead of a single uniform Y squash (which read
	# as "bouncing block"), modulate three axes so the body visibly
	# COMPRESSES on the back stroke and STRETCHES forward on the push.
	# Real snail crawl is a wave of muscular contraction running tail →
	# head; we approximate by tying Z stretch to the same _pulse_phase
	# but at quarter-period offset so the body lengthens just as the foot
	# pushes down. X jitters slightly out of phase for the side-to-side
	# inching feel.
	var base: float = 0.5 if is_baby else 1.0
	if is_baby:
		base = 0.5 + 0.5 * clampf(age / MATURITY_AGE, 0.0, 1.0)
	# Eating pulse — bigger compress/release during a consumption beat.
	var eat_amp: float = 1.0
	if _eating_pulse_remaining > 0.0:
		var ep_t: float = 1.0 - (_eating_pulse_remaining / EATING_PULSE_DURATION)
		# Bell curve over the eating window — peak amplitude mid-pulse.
		eat_amp = 1.0 + 0.30 * sin(clampf(ep_t, 0.0, 1.0) * PI)
	# Z creep: stretches forward on push (sin of phase + π/2), squashes back.
	var creep_z: float = 1.0 + sin(_pulse_phase + PI * 0.5) * 0.10 * eat_amp
	# X side-shimmy: tiny lateral wobble for body weight transfer.
	var shimmy_x: float = 1.0 + sin(_pulse_phase * 0.65 + 0.7) * 0.04 * eat_amp
	# Y squash: the original foot pulse, amplified by eating.
	var y_axis: float = 1.0 + (squash_y - 1.0) * eat_amp
	scale = Vector3(base * shimmy_x, base * y_axis, base * creep_z)


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
	var w := _world_node()
	if w != null and w.has_method("clamp_xyz_in_tank"):
		sac.global_position = w.clamp_xyz_in_tank(
			sac.global_position, 0.30, shell_size * 0.08)
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
	# Environmental nudge: saltwater occasionally favors tall marine spires
	# (cerith / trumpet) or a flared conch lip; rich substrate grows shells
	# with more whorls.
	var is_salt: bool = bool(pressure.get("saltwater", false))
	if is_salt and randf() < 0.05:
		new_shape = "tower" if randf() < 0.6 else "conch"
	var sub: float = float(pressure.get("substrate", 0.5))
	var new_spines: float = clampf(shell_spines + randf_range(-0.12, 0.12), 0.0, 1.0)
	var new_toxin: float = clampf(toxin_level + randf_range(-0.10, 0.10), 0.0, 1.0)
	var new_spire: float = clampf(spire_height + randf_range(-0.12, 0.12)
		+ (0.25 if new_shape == "tower" else 0.0), 0.4, 2.0)
	var new_flare: float = clampf(aperture_flare + randf_range(-0.10, 0.10)
		+ (0.3 if new_shape == "conch" else 0.0), 0.0, 1.0)
	var new_whorls: int = clampi(whorl_count + ((randi() % 3 - 1) if randf() < 0.15 else 0)
		+ (1 if sub > 0.6 and randf() < 0.3 else 0), 3, 8)
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
	# Expanded shell architecture drifts down the lineage too (pressure-nudged).
	sac.set("inherited_spire_height", new_spire)
	sac.set("inherited_whorl_count", new_whorls)
	sac.set("inherited_aperture_flare", new_flare)
	sac.set("inherited_operculum", operculum if randf() < 0.95 else not operculum)
	sac.set("inherited_shell_pattern", shell_pattern if randf() < 0.9 else randi() % 4)
	sac.set("inherited_shell_pattern_scale",
		clampf(shell_pattern_scale + randf_range(-0.1, 0.1), 0.0, 1.0))
	# Aposematism: toxic lineages drift toward denser, bolder shell markings.
	sac.set("inherited_shell_pattern_density",
		clampf(shell_pattern_density + randf_range(-0.1, 0.1) + new_toxin * 0.12, 0.0, 1.0))
	sac.set("inherited_parent_lineage", snail_name)
	sac.set("inherited_parent_keys", SpeciesLibrary.parent_keys_for_breeding([get_saved_genome()]))


func _mutate_shell_shape(base_shape: String) -> String:
	var shape: String = base_shape
	# Rare shape mutation keeps local lineages mostly coherent while allowing
	# long-run emergence of visibly distinct shell classes.
	if randf() < 0.08:
		var options: Array[String] = ["turbo", "trochus", "nassarius", "apple",
			"ramshorn", "tower", "limpet", "conch"]
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
	# Base sway — slow resting wiggle, suppressed during retraction.
	var sway_y: float = sin(_eye_phase) * 0.18 * ext
	var sway_x: float = sin(_eye_phase * 0.7 + 1.1) * 0.10 * ext
	# Crawl bias — when actively crawling, the eye stalks lean forward
	# (negative X pitch on the EyeStalks pivot, which is offset along
	# local +X from the head). Stronger lean during fast pursuit-of-food
	# crawl so the snail visibly "leans into" the chase.
	if not _paused and not _clamped and _crawl_speed_smoothed > 0.02:
		var lean_strength: float = (0.30 if _pursuing_waste else 0.18) * ext
		sway_x -= lean_strength
		# Yaw bias toward heading curve — if the snail is mid-turn the
		# stalks pre-point in the new direction, like a real snail
		# orienting before the body catches up.
		var turn_lean: float = clampf(_direction.x - _facing.x, -1.0, 1.0)
		sway_y += turn_lean * 0.22 * ext
	else:
		# Paused: wider scan amplitude — looking around for food / threats.
		# Random saccades stacked on the base sway every ~2.4 s.
		_eye_scan_t -= dt
		if _eye_scan_t <= 0.0:
			_eye_scan_t = randf_range(1.8, 3.4)
			_eye_scan_target = Vector2(
				randf_range(-0.32, 0.32),
				randf_range(-0.15, 0.18))
		# Decay scan target toward 0 so the saccade is a brief twitch
		# rather than a permanent head-cock.
		_eye_scan_target = _eye_scan_target.lerp(Vector2.ZERO, clampf(dt * 1.2, 0.0, 1.0))
		sway_y += _eye_scan_target.x * ext
		sway_x += _eye_scan_target.y * ext
	_eye_stalks.rotation.y = sway_y
	_eye_stalks.rotation.x = sway_x
	# Scale the stalks along Y so they visually pull into the body
	# during retraction. Width stays steady so they don't look thinner.
	_eye_stalks.scale = Vector3(1.0, lerpf(0.1, 1.0, ext), 1.0)


func _tick_operculum(dt: float) -> void:
	if _operculum_pivot == null or not operculum:
		return
	var target: float = 1.0 if _clamped else (0.55 if _fish_hover_freeze else 0.0)
	_operculum_ext = lerpf(_operculum_ext, target, clampf(dt * 9.0, 0.0, 1.0))
	_operculum_pivot.visible = _operculum_ext > 0.04
	_operculum_pivot.scale = Vector3(
		lerpf(0.65, 1.08, _operculum_ext),
		lerpf(0.4, 1.0, _operculum_ext),
		lerpf(0.35, 1.0, _operculum_ext),
	)


# Fast per-tick check for a predator inside the immediate-retract radius.
# Only the cheap distance loop here — the heavier "should clamp" decision
# stays on the 0.3 s scan tick in _check_predator_threat. Triggers an
# instant eye-stalk pull-in so a fish darting past gets a reactive read.
const _IMMEDIATE_RETRACT_RADIUS_SQ: float = 0.7 * 0.7

func _check_immediate_predator_retract() -> void:
	# Already retracting / clamped → nothing to do.
	if _clamped or _eye_retract_remaining > 0.0:
		return
	var sim := _get_sim()
	if sim == null:
		return
	# Bail fast when no snail-hunting fish are in the tank at all.
	var predator_count_v: Variant = sim.get("snail_predator_count")
	if predator_count_v != null and int(predator_count_v) == 0:
		return
	var self_pos: Vector3 = global_position
	for f in sim.fish:
		if not is_instance_valid(f):
			continue
		var is_pred_v: Variant = f.get("snail_predator")
		if is_pred_v == null or not bool(is_pred_v):
			continue
		var d2: float = (f.global_position - self_pos).length_squared()
		if d2 < _IMMEDIATE_RETRACT_RADIUS_SQ:
			_eye_retract_remaining = EYE_RETRACT_DURATION
			return


# Set _fish_hover_freeze when any (non-darting) fish is hovering close.
# Snails freeze entirely while this is true — separate from the predator
# clamp so a non-snail-eating tetra hovering above still triggers the
# "stay still until it moves on" reflex real snails have. Cheap: walks
# sim.fish but bails on first match; called only when scan_due fires.
const _HOVER_FREEZE_RADIUS_SQ: float = 1.2 * 1.2
const _HOVER_FREEZE_MAX_FISH_SPEED: float = 0.85

func _check_fish_hover_freeze() -> void:
	var sim := _get_sim()
	if sim == null:
		_fish_hover_freeze = false
		return
	var self_pos: Vector3 = global_position
	for f in sim.fish:
		if not is_instance_valid(f):
			continue
		# Only hovering fish (not zooming past) trigger the freeze.
		var sp_v: Variant = f.get("speed")
		if sp_v == null or float(sp_v) > _HOVER_FREEZE_MAX_FISH_SPEED:
			continue
		# Skip fry — too small to read as a threat.
		var mat_v: Variant = f.get("maturity")
		if mat_v != null and int(mat_v) == 0:  # MATURITY_FRY
			continue
		var d2: float = (f.global_position - self_pos).length_squared()
		if d2 < _HOVER_FREEZE_RADIUS_SQ:
			_fish_hover_freeze = true
			# Also pull the stalks in so the visual reads as "noticed it."
			if _eye_retract_remaining <= 0.0:
				_eye_retract_remaining = EYE_RETRACT_DURATION * 0.6
			return
	_fish_hover_freeze = false


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
		if not f.snail_predator:
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
	_return_shell_minerals()
	queue_free()


# Dissolving shell slowly returns calcium carbonate to the water + bed (#19).
func _return_shell_minerals() -> void:
	var sim := _get_sim()
	if sim == null:
		return
	if sim.water_chemistry != null and sim.water_chemistry.has_method("add_gh"):
		sim.water_chemistry.add_gh(0.01 if is_baby else 0.05)
	if sim.substrate != null:
		sim.substrate.add_at(global_position, 0.02)


func _choose_new_direction() -> void:
	# Clear cleaner-crew pursuit flag - if there was a waste trail nearby
	# we'd still be locked onto it via _check_waste_nearby. By the time
	# we get here we've either eaten the target or lost it.
	_pursuing_waste = false
	_t_until_turn = randf_range(TURN_INTERVAL_MIN, TURN_INTERVAL_MAX)
	_paused = randf() < PAUSE_CHANCE
	if _paused:
		# Cap the pause to a short interval so it reads as "resting" not
		# "frozen." When the timer expires we run _choose_new_direction
		# again, which usually rolls a new heading rather than another
		# pause.
		_t_until_turn = randf_range(PAUSE_DURATION_MIN, PAUSE_DURATION_MAX)
		return
	# Bias the new heading toward the current heading so the turn reads
	# as a gentle redirection rather than a 180° flip. We rotate the old
	# direction by a moderate random angle instead of picking pure uniform
	# random — keeps the crawl path coherent.
	var turn: float = randf_range(-PI * 0.55, PI * 0.55)
	# Occasionally (~25%) take a bigger turn, including the rare reversal.
	if randf() < 0.25:
		turn = randf_range(-PI, PI)
	if _direction.length_squared() < 1e-6:
		var ang := randf() * TAU
		_direction = Vector2(cos(ang), sin(ang))
	else:
		_direction = _direction.rotated(turn)
		_direction = _direction.normalized()


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
		var merged: Vector2 = _direction + dir2 * 0.55
		if merged.length_squared() > 1e-6:
			_direction = merged.normalized()
		_spacing_push += (tangent * dir2.x + bitangent * dir2.y) \
			* (SPACE_R - sqrt(d2)) * 0.35
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
		"spire_height": spire_height,
		"whorl_count": whorl_count,
		"aperture_flare": aperture_flare,
		"operculum": operculum,
		"shell_pattern": shell_pattern,
		"shell_pattern_scale": shell_pattern_scale,
		"shell_pattern_density": shell_pattern_density,
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
		# Curved-tank flag — _reclamp_to_footprint uses it to decide
		# whether to project to a fixed plane or to the curved surface.
		# Plant attachment isn't saved (it's a node ref, which doesn't
		# survive save/load); on load the snail starts on whatever wall
		# its wall_normal indicates and the next scan tick can reattach.
		"curved_attached": _curved_attached,
	}


func apply_save_dict(d: Dictionary) -> void:
	id = String(d.get("id", id))
	wall_normal = SaveHelpers.array_to_vec3(d.get("wall_normal", []), wall_normal)
	wall_min = SaveHelpers.array_to_vec3(d.get("wall_min", []), wall_min)
	wall_max = SaveHelpers.array_to_vec3(d.get("wall_max", []), wall_max)
	is_baby = not not d.get("is_baby", is_baby)
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
	spire_height = clampf(float(d.get("spire_height", spire_height)), 0.4, 2.0)
	whorl_count = clampi(int(d.get("whorl_count", whorl_count)), 3, 8)
	aperture_flare = clampf(float(d.get("aperture_flare", aperture_flare)), 0.0, 1.0)
	operculum = not not d.get("operculum", operculum)
	shell_pattern = int(d.get("shell_pattern", shell_pattern))
	shell_pattern_scale = clampf(float(d.get("shell_pattern_scale", shell_pattern_scale)), 0.0, 1.0)
	shell_pattern_density = clampf(float(d.get("shell_pattern_density", shell_pattern_density)), 0.0, 1.0)
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
	_paused = not not d.get("paused", false)
	_pursuing_waste = not not d.get("pursuing_waste", false)
	_clamped = not not d.get("clamped", false)
	_clamp_grace_remaining = float(d.get("clamp_grace_remaining", 0.0))
	_eye_retract_remaining = float(d.get("eye_retract_remaining", 0.0))
	_eye_retract_timer = float(d.get("eye_retract_timer", _eye_retract_timer))
	_curved_attached = not not d.get("curved_attached", false)
	_attached_plant = null  # plant refs don't survive save/load
	if is_baby:
		scale = Vector3.ONE * 0.5
	_reclamp_to_footprint()
	# Re-apply orientation so the loaded snail snaps to its saved wall
	# pose immediately. Without this, the basis stays at engine-default
	# until the next crawl tick, and a paused snail visibly "lays on its
	# side" for a frame or two before the orientation catches up. The
	# call is deferred to next-frame so the parent transform is settled.
	_last_progress_pos = global_position
	call_deferred("_sync_initial_orientation")
