# A fish agent.
#
# Holds genome + state, builds its own voxel body, runs a small behavior tree
# every sim tick. Behaviors (in priority order):
#   1. Flee tank wall if too close
#   2. Breed if adult, healthy, near a conspecific of opposite sex with low hunger
#   3. Eat if hungry (herbivores seek plants; carnivores skipped here)
#   4. School: cohesion + alignment + separation with conspecifics
#   5. Wander
#
# Lifecycle: fry -> juvenile -> adult -> senescent -> dies (queue_free).
# Dying decomposes into a waste particle (so the loop closes nutrient-wise).

extends Node3D
class_name Fish

const MATURITY_FRY := 0
const MATURITY_JUVENILE := 1
const MATURITY_ADULT := 2
const MATURITY_SENESCENT := 3

# Behavior modes - what the fish is doing right now. Visible in the HUD if we
# add per-fish debug labels.
enum Mode { CRUISE, FORAGE, COURT, SPAWN, FLEE, REST }

# ---- Genome (set at spawn, immutable for this individual) ----
var species: String = "glassdart"
var base_color: Color = Color8(195, 59, 59)
var accent_color: Color = Color8(230, 201, 42)
var adult_voxel_scale: float = 0.18
var max_age_s: float = 240.0            # ~4 minutes lifespan for visible cycles
var max_speed: float = 1.8
var schooling_strength: float = 1.0
var separation_radius: float = 0.55
var herbivory: float = 0.0              # >0 means eats plants
var fecundity: float = 0.7
var clutch_size: int = 2
var preferred_y: float = 3.5            # mid-water by default
var sex: int = 0                        # 0 male, 1 female

# ---- Lineage ----
var generation: int = 0   # max(parents) + 1 on birth; founders are 0

# ---- State (mutable) ----
var age: float = 0.0
var hunger: float = 0.3        # 0 = full, 1 = starving
var energy: float = 1.0
var stress: float = 0.0
var maturity: int = MATURITY_FRY
var velocity: Vector3 = Vector3.ZERO
var breed_cooldown: float = 0.0
var nibble_cooldown: float = 0.0
var target_plant: Plant = null
var heading_offset: Vector3 = Vector3.ZERO  # personal randomness in schooling
var current_mode: Mode = Mode.CRUISE

# Courtship state machine:
#   partner: who we're trying to spawn with (or null)
#   court_timer: time spent courting (need to reach threshold to spawn)
#   pair_bond_timer: shared time post-spawn before the bond dissolves
var partner: Fish = null
var court_timer: float = 0.0
const COURT_DURATION: float = 6.0  # sim seconds of swimming together before spawn

# Burst mode: when fleeing or chasing food, fish can momentarily exceed
# max_speed by burst_multiplier. Drains energy faster.
var burst_remaining: float = 0.0

# Size growth from feeding. Well-fed adults slowly grow above their starting
# size; chronically hungry ones shrink. effective_size() is the property
# used for size-based predation (bigger fish hunt smaller ones).
var growth_factor: float = 1.0
var max_growth: float = 1.4     # apex species (betta) override higher (~2.0)

# Visible phenotypes - heritable traits affecting body proportions + pattern.
# Drift over generations and create lineages that look distinct.
var fin_length_factor: float = 1.0   # multiplier on tail / dorsal / anal fin extent (0.6-1.6)
var body_elongation: float = 1.0     # body length stretch factor (0.85-1.15)
var pattern_type: int = 1            # 0=solid, 1=lateral stripe, 2=spots, 3=vertical bars
var color_dot_count: int = 0         # extra accent dots (0-4)
# Lifetime breed count - successful breeders are slightly more attractive.
var breed_count: int = 0


func effective_size() -> float:
	return adult_voxel_scale * _maturity_scale() * growth_factor

# Velocity has two parts: target (set by tick at 10Hz) and current (smoothed
# at render rate in _process). This keeps motion smooth even though the
# brain ticks slowly.
var target_velocity: Vector3 = Vector3.ZERO

# Animation + transform pivots.
#   _bank_pivot wraps the body and rotates around its local Z (forward axis)
#   to roll/bank into turns.
#   _tail_pivot wags side-to-side.
#   _body_mid_pivot counter-wags.
var _bank_pivot: Node3D = null
var _tail_pivot: Node3D = null
var _body_mid_pivot: Node3D = null
var _dorsal_pivot: Node3D = null
var _pec_left_pivot: Node3D = null
var _pec_right_pivot: Node3D = null
var _anal_pivot: Node3D = null
var _swim_phase: float = 0.0
var _last_yaw: float = 0.0
var _bank: float = 0.0

# Heading + speed motion model (separates direction from magnitude). Real
# fish accelerate forward via tail thrust and steer via slow heading changes,
# they can't slide sideways. This gives us proper momentum + turn-radius.
var heading: Vector3 = Vector3.FORWARD  # unit vector, faces -Z initially
var speed: float = 0.0
var max_turn_rate: float = 2.6   # radians/sec - how fast the fish can yaw
var linear_accel: float = 2.5    # units/sec^2 - how fast speed changes

# ---- Refs ----
var sim: Node = null


func _ready() -> void:
	heading_offset = Vector3(
		randf_range(-0.5, 0.5),
		randf_range(-0.2, 0.2),
		randf_range(-0.5, 0.5),
	)
	_swim_phase = randf() * TAU
	# Start each fish facing a random horizontal direction so newborn fry
	# don't all stare the same way.
	var theta: float = randf() * TAU
	heading = Vector3(sin(theta), 0.0, -cos(theta))
	_last_yaw = atan2(heading.x, -heading.z)
	speed = 0.0


# ---- Setup ----

func init_genome(genome: Dictionary) -> void:
	species = genome.get("species", species)
	base_color = genome.get("base_color", base_color)
	accent_color = genome.get("accent_color", accent_color)
	adult_voxel_scale = genome.get("adult_voxel_scale", adult_voxel_scale)
	max_age_s = genome.get("max_age_s", max_age_s)
	max_speed = genome.get("max_speed", max_speed)
	schooling_strength = genome.get("schooling_strength", schooling_strength)
	separation_radius = genome.get("separation_radius", separation_radius)
	herbivory = genome.get("herbivory", herbivory)
	fecundity = genome.get("fecundity", fecundity)
	clutch_size = genome.get("clutch_size", clutch_size)
	preferred_y = genome.get("preferred_y", preferred_y)
	sex = genome.get("sex", randi() % 2)
	generation = genome.get("generation", 0)
	fin_length_factor = genome.get("fin_length_factor", fin_length_factor)
	body_elongation = genome.get("body_elongation", body_elongation)
	pattern_type = int(genome.get("pattern_type", pattern_type))
	color_dot_count = int(genome.get("color_dot_count", color_dot_count))
	# A fry is born tiny - we'll lerp scale as it matures.
	scale = Vector3.ONE * _maturity_scale()
	_build_body()


func _maturity_scale() -> float:
	match maturity:
		MATURITY_FRY:        return 0.35
		MATURITY_JUVENILE:   return 0.65
		MATURITY_ADULT:      return 1.0
		MATURITY_SENESCENT:  return 0.95
		_: return 1.0


func _build_body() -> void:
	# Voxel fish facing -Z (Godot's default "forward"). With look_at, the fish
	# faces its velocity correctly without extra rotation tricks.
	#
	# Hierarchy:
	#   Fish (this Node3D - look_at faces velocity, position updates each frame)
	#   └── BankPivot (rolls around local Z to bank into turns)
	#       ├── Head (rigid)
	#       ├── BodyMid (gentle counter-wag around Y)
	#       └── TailPivot (strong wag around Y at the tail base)
	#
	# Axes:
	#   -Z = forward (head direction)
	#   +X = right (lateral, where stripes and pectorals go)
	#   +Y = up
	var v: float = adult_voxel_scale
	var mat_body := _make_mat(base_color)
	var mat_top := _make_mat(base_color.lightened(0.15))
	var mat_belly := _make_mat(base_color.darkened(0.35))
	var mat_accent := _make_mat(accent_color)
	var mat_eye := _make_mat(Color8(11, 26, 34))
	var mat_fin := _make_mat(base_color.darkened(0.15))

	_bank_pivot = Node3D.new()
	_bank_pivot.name = "BankPivot"
	add_child(_bank_pivot)

	# ---- HEAD (rigid, at z = -2.5v, the front of the fish) ----
	var head := Node3D.new()
	head.name = "Head"
	_bank_pivot.add_child(head)
	_add_voxel_to(head, Vector3(0, 0, -2.5 * v), Vector3(v * 0.95, v * 0.9, v), mat_body)
	# Forehead - lighter, catches the top face shading.
	_add_voxel_to(head, Vector3(0, v * 0.5, -2.5 * v), Vector3(v * 0.6, v * 0.3, v), mat_top)
	# Belly under head.
	_add_voxel_to(head, Vector3(0, -v * 0.5, -2.5 * v), Vector3(v * 0.6, v * 0.3, v), mat_belly)
	# Eyes - one on each lateral side of the head.
	_add_voxel_to(head, Vector3(v * 0.4, v * 0.1, -2.4 * v),
		Vector3(v * 0.2, v * 0.25, v * 0.25), mat_eye)
	_add_voxel_to(head, Vector3(-v * 0.4, v * 0.1, -2.4 * v),
		Vector3(v * 0.2, v * 0.25, v * 0.25), mat_eye)

	# ---- BODY MID (gentle counter-wag) - thickest part of the fish ----
	_body_mid_pivot = Node3D.new()
	_body_mid_pivot.name = "BodyMid"
	_body_mid_pivot.position = Vector3(0, 0, -1.5 * v)
	_bank_pivot.add_child(_body_mid_pivot)
	# Segments at z offsets 0, v, 2v (back along the body from the pivot).
	var seg_widths: Array[float] = [1.15, 1.20, 1.0]
	for i in seg_widths.size():
		var bw: float = seg_widths[i]
		var bs: float = v * bw
		var bz: float = i * v
		_add_voxel_to(_body_mid_pivot, Vector3(0, 0, bz),
			Vector3(bs * 0.95, bs, v), mat_body)
		# Top + belly accents.
		_add_voxel_to(_body_mid_pivot, Vector3(0, bs * 0.5, bz),
			Vector3(bs * 0.55, v * 0.25, v), mat_top)
		_add_voxel_to(_body_mid_pivot, Vector3(0, -bs * 0.5, bz),
			Vector3(bs * 0.55, v * 0.25, v), mat_belly)
	# Lateral pattern - varies by pattern_type genotype.
	# 0 = solid (no accents), 1 = horizontal stripe, 2 = spots, 3 = vertical bars
	if pattern_type == 1:
		# Horizontal stripe along both sides.
		for i in seg_widths.size():
			_add_voxel_to(_body_mid_pivot, Vector3(v * 0.5, 0, i * v),
				Vector3(v * 0.15, v * 0.35, v * 0.9), mat_accent)
			_add_voxel_to(_body_mid_pivot, Vector3(-v * 0.5, 0, i * v),
				Vector3(v * 0.15, v * 0.35, v * 0.9), mat_accent)
	elif pattern_type == 2:
		# Spots: 3 small dots along each side.
		for i in seg_widths.size():
			var dy: float = (-1.0 if i == 1 else 1.0) * v * 0.25
			_add_voxel_to(_body_mid_pivot, Vector3(v * 0.5, dy, i * v),
				Vector3(v * 0.15, v * 0.3, v * 0.3), mat_accent)
			_add_voxel_to(_body_mid_pivot, Vector3(-v * 0.5, dy, i * v),
				Vector3(v * 0.15, v * 0.3, v * 0.3), mat_accent)
	elif pattern_type == 3:
		# Vertical bars: tall thin accent stripes across the body height.
		for i in seg_widths.size():
			_add_voxel_to(_body_mid_pivot, Vector3(v * 0.5, 0, i * v),
				Vector3(v * 0.15, v * 1.0, v * 0.25), mat_accent)
			_add_voxel_to(_body_mid_pivot, Vector3(-v * 0.5, 0, i * v),
				Vector3(v * 0.15, v * 1.0, v * 0.25), mat_accent)
	# Extra dots scattered on top of the body (independent decorative trait).
	for i in color_dot_count:
		var zoff: float = (float(i) / float(maxi(1, color_dot_count - 1)) - 0.5) * v * 2.0
		var xside: float = (-1.0 if i % 2 == 0 else 1.0) * v * 0.55
		_add_voxel_to(_body_mid_pivot, Vector3(xside, v * 0.35, zoff),
			Vector3(v * 0.2, v * 0.2, v * 0.2), mat_accent)
	# Dorsal fin (top) - pivoted at its base so it can sway lazily.
	_dorsal_pivot = Node3D.new()
	_dorsal_pivot.name = "DorsalPivot"
	_dorsal_pivot.position = Vector3(0, v * 0.75, v * 1.0)
	_body_mid_pivot.add_child(_dorsal_pivot)
	_add_voxel_to(_dorsal_pivot, Vector3(0, v * 0.2, 0),
		Vector3(v * 0.15, v * 0.4, v * 1.2), mat_fin)
	_add_voxel_to(_dorsal_pivot, Vector3(0, v * 0.45, v * 0.2),
		Vector3(v * 0.12, v * 0.25, v * 0.6), mat_fin)
	# Anal fin (bottom) - smaller mirror of dorsal, also pivoted.
	_anal_pivot = Node3D.new()
	_anal_pivot.name = "AnalPivot"
	_anal_pivot.position = Vector3(0, -v * 0.65, v * 1.6)
	_body_mid_pivot.add_child(_anal_pivot)
	_add_voxel_to(_anal_pivot, Vector3(0, -v * 0.2, 0),
		Vector3(v * 0.12, v * 0.35, v * 0.7), mat_fin)
	# Pectoral fins on both sides - each gets its own pivot so they can
	# flutter independently like a real fish's hovering stroke.
	_pec_right_pivot = Node3D.new()
	_pec_right_pivot.name = "PecRight"
	_pec_right_pivot.position = Vector3(v * 0.55, -v * 0.1, v * 0.2)
	_body_mid_pivot.add_child(_pec_right_pivot)
	_add_voxel_to(_pec_right_pivot, Vector3(v * 0.1, 0, 0),
		Vector3(v * 0.12, v * 0.25, v * 0.5), mat_fin)
	_pec_left_pivot = Node3D.new()
	_pec_left_pivot.name = "PecLeft"
	_pec_left_pivot.position = Vector3(-v * 0.55, -v * 0.1, v * 0.2)
	_body_mid_pivot.add_child(_pec_left_pivot)
	_add_voxel_to(_pec_left_pivot, Vector3(-v * 0.1, 0, 0),
		Vector3(v * 0.12, v * 0.25, v * 0.5), mat_fin)

	# ---- TAIL (strong wag) - tail base at the rear of the body ----
	_tail_pivot = Node3D.new()
	_tail_pivot.name = "TailPivot"
	_tail_pivot.position = Vector3(0, 0, 1.5 * v)
	_bank_pivot.add_child(_tail_pivot)
	# Tail peduncle (narrow connector).
	_add_voxel_to(_tail_pivot, Vector3(0, 0, 0),
		Vector3(v * 0.5, v * 0.6, v), mat_body)
	# Forked tail fin - top + bottom prongs. Extent scales with fin_length_factor:
	# long-finned individuals have visibly trailing fins; short-finned are stubby.
	var fl: float = fin_length_factor
	_add_voxel_to(_tail_pivot, Vector3(0, v * 0.45, v * (0.9 * fl)),
		Vector3(v * 0.15, v * 0.4, v * (0.6 * fl)), mat_fin)
	_add_voxel_to(_tail_pivot, Vector3(0, -v * 0.45, v * (0.9 * fl)),
		Vector3(v * 0.15, v * 0.4, v * (0.6 * fl)), mat_fin)
	# Outer fin tips, further back.
	_add_voxel_to(_tail_pivot, Vector3(0, v * (0.7 * fl), v * (1.4 * fl)),
		Vector3(v * 0.12, v * (0.3 * fl), v * (0.4 * fl)), mat_fin)
	_add_voxel_to(_tail_pivot, Vector3(0, v * (-0.7 * fl), v * (1.4 * fl)),
		Vector3(v * 0.12, v * (0.3 * fl), v * (0.4 * fl)), mat_fin)
	# Apply body elongation by stretching the bank pivot's local Z scale.
	# This makes some fish look more eel-like (1.15) and others stubbier (0.85).
	if _bank_pivot != null:
		_bank_pivot.scale.z = body_elongation


func _add_voxel_to(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


func _make_mat(color: Color) -> ShaderMaterial:
	return VoxelMat.make(color)


func _add_voxel(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)


# ---- Tick (called by SimDriver) ----

func tick(dt: float, neighbors: Array, plants: Array, waste: Array,
		  baby_shrimp: Array, world_bounds: AABB) -> Dictionary:
	# Returns events for the SimDriver to act on (lay egg, eat waste,
	# kill prey, spawn waste, die).
	var events: Dictionary = {}

	age += dt
	# Hunger accumulates slower so fish have more time to find food. Real
	# fish go days without eating; the sim was forcing starvation in ~80s.
	hunger = clampf(hunger + dt * 0.008, 0.0, 1.0)
	var energy_drain := 0.004 + (0.04 if burst_remaining > 0.0 else 0.0)
	energy = clampf(energy - dt * energy_drain, 0.0, 1.0)
	burst_remaining = maxf(0.0, burst_remaining - dt)
	breed_cooldown = maxf(0.0, breed_cooldown - dt)
	nibble_cooldown = maxf(0.0, nibble_cooldown - dt)

	# Schooling stress climbs if too few conspecifics nearby.
	var conspecifics_nearby: int = 0
	for n in neighbors:
		if n is Fish and (n as Fish).species == species:
			conspecifics_nearby += 1
	if conspecifics_nearby < 2 and maturity != MATURITY_FRY:
		stress = clampf(stress + dt * 0.05, 0.0, 1.0)
	else:
		stress = maxf(0.0, stress - dt * 0.08)

	_update_maturity()

	# Senescent fish: slowly fade their colors.
	if maturity == MATURITY_SENESCENT:
		_apply_aging_tint()

	# Death conditions.
	if maturity == MATURITY_SENESCENT and age >= max_age_s * 1.15:
		events["die"] = true
		return events
	if hunger >= 1.0 and energy < 0.1:
		events["die"] = true
		return events

	# Behavior priority - higher tier wins. Each tier produces a desired velocity
	# (or events) for the brain.
	var desired := Vector3.ZERO
	var effective_max := max_speed * (1.6 if burst_remaining > 0.0 else 1.0)
	current_mode = Mode.CRUISE

	# Tier 0: wall avoidance always runs (additive).
	desired += _wall_avoid(world_bounds) * 3.0

	# Tier 1: COURTSHIP. Already paired? Continue the dance toward spawn.
	if partner != null:
		if not is_instance_valid(partner) or partner.maturity != MATURITY_ADULT:
			partner = null
			court_timer = 0.0
		else:
			current_mode = Mode.COURT
			var to_partner: Vector3 = partner.position - position
			var dist: float = to_partner.length()
			# Swim alongside (not into) the partner: target a point slightly to one side.
			var side: Vector3 = to_partner.cross(Vector3.UP).normalized() * 0.4
			var courtship_target: Vector3 = partner.position + side
			desired += (courtship_target - position).normalized() * effective_max * 0.7
			court_timer += dt
			# Spawn when we've been close enough for long enough.
			if dist < 1.2 and court_timer >= COURT_DURATION:
				current_mode = Mode.SPAWN
				events["lay_egg_with"] = partner
				breed_cooldown = 35.0
				energy = maxf(0.0, energy - 0.35)
				partner.breed_cooldown = 35.0
				partner.energy = maxf(0.0, partner.energy - 0.35)
				breed_count += 1
				partner.breed_count += 1
				partner.partner = null
				partner = null
				court_timer = 0.0
			target_velocity = desired.limit_length(effective_max)
			return events

	# Tier 1b: SCAVENGE WASTE. Fish opportunistically eat waste particles
	# that drift past. Cheaper than chasing live food. Applies to all fish,
	# herbivores or not, when even slightly hungry.
	if hunger > 0.3 and maturity != MATURITY_FRY:
		var best_w: WasteParticle = null
		var best_d2: float = 2.5 * 2.5
		for w in waste:
			if not is_instance_valid(w):
				continue
			# Fish prefer fresh-fallen waste in mid-water, not settled.
			if w.settled and randf() > 0.4:
				continue
			var d2: float = (w as Node3D).global_position.distance_squared_to(position)
			if d2 < best_d2:
				best_d2 = d2
				best_w = w
		if best_w != null:
			current_mode = Mode.FORAGE
			var to_w: Vector3 = best_w.global_position - position
			if to_w.length() < 0.4:
				events["eat_waste"] = best_w
				hunger = maxf(0.0, hunger - 0.25)
				energy = minf(1.0, energy + 0.06)
			else:
				desired += to_w.normalized() * effective_max * 0.9
				target_velocity = desired.limit_length(effective_max)
				return events

	# Tier 1b2: SIZE-BASED PREDATION on smaller fish + adult shrimp. Gated so
	# only "predator-class" fish hunt - either grown above 1.3x their base
	# size (well-fed adult that's earned it), or a carnivore species (betta).
	# Otherwise the betta at spawn is already 1.56x a glassdart's base size
	# and starts wiping the school day-one.
	var is_predator_class: bool = growth_factor >= 1.3 or species == "betta"
	if is_predator_class and maturity == MATURITY_ADULT and hunger > 0.45 and randf() < 0.10:
		var my_size: float = effective_size()
		var best_prey: Node3D = null
		var best_prey_d2: float = 4.5 * 4.5
		# Smaller fish
		for n in neighbors:
			if not (n is Fish) or n == self:
				continue
			var of: Fish = n
			if of.species == species and of.maturity == MATURITY_FRY:
				# Same-species fry: only ~25% of fish will eat their own kind's
				# young (real species vary - we just model species-specific
				# cannibalism as a "betta only" thing).
				if species != "betta":
					continue
			# Need a stronger size advantage now (1.8x). At spawn the betta
			# is only 1.56x a glassdart - it has to grow before it can hunt.
			if my_size > of.effective_size() * 1.8:
				var d2: float = of.position.distance_squared_to(position)
				if d2 < best_prey_d2:
					best_prey_d2 = d2
					best_prey = of
		# Adult shrimp only become prey to very large predators (3x advantage).
		# This effectively limits adult-shrimp predation to a well-grown betta
		# - otherwise the school strips shrimp before they can recruit.
		if sim != null:
			for s in sim.shrimp:
				if not is_instance_valid(s) or s.maturity != Shrimp.MATURITY_ADULT:
					continue
				if my_size > s.adult_voxel_scale * 3.0:
					var d2: float = s.position.distance_squared_to(position)
					if d2 < best_prey_d2:
						best_prey_d2 = d2
						best_prey = s
		if best_prey != null and is_instance_valid(best_prey):
			current_mode = Mode.FORAGE
			var to_prey: Vector3 = (best_prey as Node3D).global_position - position
			if to_prey.length() < 0.45:
				events["kill_prey"] = best_prey
				hunger = maxf(0.0, hunger - 0.50)
				energy = minf(1.0, energy + 0.18)
				events["waste_at"] = position + Vector3(0, -0.1, 0)
				events["waste_amount"] = 0.20
			else:
				if burst_remaining <= 0.0 and energy > 0.3:
					burst_remaining = 0.5
				desired += to_prey.normalized() * effective_max * 1.3
				target_velocity = desired.limit_length(effective_max)
				return events

	# Tier 1c: PREDATION on baby shrimp by any fish (smaller-target case the
	# size check above might miss). VERY rare for normal fish - high fish
	# populations were stripping shrimp fry faster than shrimp could recruit.
	# Betta still 4x more aggressive than schoolers.
	var predation_chance: float = 0.08 if species == "betta" else 0.02
	if maturity == MATURITY_ADULT and hunger > 0.65 and not baby_shrimp.is_empty() \
			and randf() < predation_chance:
		var prey: Shrimp = null
		var best_d2: float = 1.2 * 1.2
		for s in baby_shrimp:
			if not is_instance_valid(s):
				continue
			var d2: float = (s as Node3D).global_position.distance_squared_to(position)
			if d2 < best_d2:
				best_d2 = d2
				prey = s
		if prey != null:
			current_mode = Mode.FORAGE
			var to_prey: Vector3 = prey.global_position - position
			if to_prey.length() < 0.35:
				events["kill_prey"] = prey
				hunger = maxf(0.0, hunger - 0.40)
				energy = minf(1.0, energy + 0.12)
				events["waste_at"] = position + Vector3(0, -0.1, 0)
				events["waste_amount"] = 0.15
			else:
				if burst_remaining <= 0.0 and energy > 0.3:
					burst_remaining = 0.4
				desired += to_prey.normalized() * effective_max * 1.2
				target_velocity = desired.limit_length(effective_max)
				return events

	# Tier 2: HUNGRY HERBIVORE. Plants need at least 6 voxels of biomass
	# (was 12) so fish have more food options before the shrimp graze them
	# down to nothing.
	if herbivory > 0.0 and hunger > 0.55 and maturity != MATURITY_FRY \
			and randf() < 0.5:
		if target_plant == null or not is_instance_valid(target_plant) \
				or target_plant.biomass() < 6:
			target_plant = _find_nearest_tall_plant(plants, 5.0, 6)
		if target_plant != null:
			current_mode = Mode.FORAGE
			var top: Vector3 = target_plant.global_position
			top.y = target_plant.top_world_y()
			var dist: float = top.distance_to(position)
			if dist < 0.5 and nibble_cooldown <= 0.0:
				var taken := target_plant.nibble(1)
				if taken > 0:
					hunger = maxf(0.0, hunger - 0.30 * float(taken))
					energy = minf(1.0, energy + 0.06)
					nibble_cooldown = 0.9
					events["waste_at"] = position + Vector3(0, -0.1, 0)
					events["waste_amount"] = 0.15 * float(taken)
				target_plant = null
			else:
				if hunger > 0.8 and burst_remaining <= 0.0 and energy > 0.3:
					burst_remaining = 0.6
				desired += (top - position).normalized() * effective_max
				target_velocity = desired.limit_length(effective_max)
				return events

	# Tier 3: SEEK PARTNER. Adult, well-fed, not on cooldown, no current
	# partner. Cap includes eggs-in-flight (otherwise the 30s incubation
	# pipeline overflows the cap by a factor of 4-5x).
	const FISH_POPULATION_CAP: int = 35
	var current_fish_pop: int = 0
	if sim != null:
		current_fish_pop = sim.fish.size() + sim.eggs.size()
	if maturity == MATURITY_ADULT and breed_cooldown <= 0.0 and partner == null \
			and hunger < 0.5 and energy > 0.65 and stress < 0.4 \
			and current_fish_pop < FISH_POPULATION_CAP:
		var candidate: Fish = _find_breeding_partner(neighbors)
		if candidate != null and candidate.partner == null:
			# Mutual pair-bond.
			partner = candidate
			candidate.partner = self
			court_timer = 0.0
			candidate.court_timer = 0.0

	# Tier 4: SCHOOL. Default behavior - boids with dynamic tightness.
	current_mode = Mode.CRUISE
	# When stressed (too few neighbors), tighten the school dramatically.
	var tightness: float = 1.0 + stress * 1.5
	desired += _boids(neighbors, tightness) * schooling_strength

	# Drift toward preferred Y layer, more strongly when far from it.
	var dy: float = preferred_y - position.y
	desired.y += dy * 0.6

	# Mild wander via personal heading offset.
	desired += heading_offset * 0.5

	# Night-time dampening: at low daylight fish slow down and stop seeking.
	# Real Walstad tanks: most species visibly sleep at night, hovering near
	# plants or substrate. We scale the desired velocity by daylight.
	if sim != null:
		var dl: float = float(sim.daylight())
		var night_factor: float = 0.25 + 0.75 * dl
		desired *= night_factor

	target_velocity = desired.limit_length(effective_max)
	# Position + facing now updated in _process at render rate.

	# Senescence speeds death.
	if maturity == MATURITY_SENESCENT:
		hunger = clampf(hunger + dt * 0.01, 0.0, 1.0)

	# Starvation kills.
	if hunger >= 1.0 and energy < 0.1:
		events["die"] = true

	# Size growth from feeding history. Adults that maintain low hunger
	# slowly grow; ones that stay starved shrink toward 0.6x. This is what
	# makes well-fed populations produce bigger fish over time and creates
	# the size-based predation dynamic.
	if maturity == MATURITY_ADULT:
		if hunger < 0.35:
			growth_factor = minf(growth_factor + 0.0008 * dt, max_growth)
		elif hunger > 0.7:
			growth_factor = maxf(growth_factor - 0.0004 * dt, 0.6)

	# Update body scale across maturity AND growth_factor.
	scale = scale.lerp(Vector3.ONE * _maturity_scale() * growth_factor, dt * 0.5)

	return events


# Per-frame: bounded-turn-rate steering + speed acceleration + banking. The
# brain (tick at 10Hz) produces target_velocity; this physics layer translates
# it into smooth heading + speed changes that respect momentum.
#
# Fish can't slide sideways, can't 180° in place, and bank into yaw turns.
func _process(dt: float) -> void:
	if sim != null:
		dt *= sim.time_scale
		if dt <= 0.0:
			return  # paused
	# Decompose the brain's target into a desired direction + desired speed.
	var target_dir: Vector3 = heading
	var target_spd: float = 0.0
	if target_velocity.length_squared() > 0.0001:
		target_spd = target_velocity.length()
		target_dir = target_velocity.normalized()

	# ---- Rotate heading toward target_dir, bounded by max_turn_rate ----
	var angle: float = heading.angle_to(target_dir)
	if angle > 0.0005:
		var axis: Vector3 = heading.cross(target_dir)
		if axis.length_squared() < 1e-6:
			# Heading and target are antiparallel - pick a sensible axis.
			axis = Vector3.UP
		axis = axis.normalized()
		var max_step: float = max_turn_rate * dt
		# Fish turn slower vertically than horizontally - real fish have a hard
		# time pitching up/down sharply. Project the turn onto a mostly-horizontal
		# axis by reducing its UP component.
		var horizontal_axis: Vector3 = axis
		horizontal_axis.y *= 0.5
		if horizontal_axis.length_squared() > 1e-6:
			axis = horizontal_axis.normalized()
		var turn: float = minf(max_step, angle)
		heading = heading.rotated(axis, turn).normalized()

	# ---- Accelerate speed toward target_spd, bounded by linear_accel ----
	speed = move_toward(speed, target_spd, linear_accel * dt)

	# ---- Apply translation ----
	velocity = heading * speed
	position += velocity * dt

	# ---- Face the heading. look_at points local -Z at the target. Body is
	# built so its forward = -Z, so the fish faces its motion correctly. ----
	if heading.length_squared() > 0.0001:
		var d: Vector3 = heading
		# Avoid look_at singularity when heading is straight up/down.
		if absf(d.dot(Vector3.UP)) > 0.95:
			d = (d + Vector3(0.0001, 0, 0)).normalized()
		look_at(position + d, Vector3.UP)

	# ---- Banking into yaw turns ----
	# Compute the world-space yaw of the heading on the XZ plane. The change
	# in yaw between frames is the yaw rate; bank angle is proportional to it.
	var current_yaw: float = atan2(heading.x, -heading.z)
	var yaw_diff: float = wrapf(current_yaw - _last_yaw, -PI, PI)
	_last_yaw = current_yaw
	var yaw_rate: float = yaw_diff / maxf(dt, 0.0001)
	var bank_target: float = clampf(-yaw_rate * 0.35, -0.6, 0.6)
	_bank = lerpf(_bank, bank_target, clampf(dt * 5.0, 0.0, 1.0))
	if _bank_pivot != null:
		_bank_pivot.rotation.z = _bank

	# ---- Swim animation ----
	# Tail wag scales with speed. Hovering fish pulse slowly, dashing fast.
	# Independent fin pivots add full-body life: pectoral fins flutter at a
	# faster frequency offset by 90 degrees for left/right (rowing motion),
	# dorsal/anal fins sway gently with the body's counter-wag.
	var wag_freq: float = 2.5 + speed * 5.5
	_swim_phase += dt * wag_freq
	if _tail_pivot != null:
		_tail_pivot.rotation.y = sin(_swim_phase) * (0.35 + minf(speed * 0.18, 0.25))
	if _body_mid_pivot != null:
		_body_mid_pivot.rotation.y = -sin(_swim_phase) * 0.10
	# Dorsal: small sway with the body counter-wag, faster small flutter on top.
	if _dorsal_pivot != null:
		_dorsal_pivot.rotation.x = sin(_swim_phase * 1.3) * 0.08
		_dorsal_pivot.rotation.z = -sin(_swim_phase) * 0.05
	if _anal_pivot != null:
		_anal_pivot.rotation.x = -sin(_swim_phase * 1.3) * 0.10
	# Pectoral fins: faster rowing flutter. Each side offset by PI/2 so the
	# motion looks like a continuous paddle, more visible at low speeds when
	# the fish is hovering (real fish use pectorals to hover/brake).
	var pec_freq: float = 4.5 + speed * 3.0
	var pec_amp: float = 0.45 - minf(speed * 0.12, 0.30)
	if _pec_right_pivot != null:
		_pec_right_pivot.rotation.z = sin(_swim_phase * pec_freq / wag_freq) * pec_amp
	if _pec_left_pivot != null:
		_pec_left_pivot.rotation.z = -sin(_swim_phase * pec_freq / wag_freq + PI * 0.5) * pec_amp


func _update_maturity() -> void:
	var t := age / max_age_s
	if t < 0.1:
		maturity = MATURITY_FRY
	elif t < 0.3:
		maturity = MATURITY_JUVENILE
	elif t < 0.85:
		maturity = MATURITY_ADULT
	else:
		maturity = MATURITY_SENESCENT


# ---- Boids ----

func _boids(neighbors: Array, tightness: float = 1.0) -> Vector3:
	# Improved schooling. Three rules (sep + ali + coh) with three upgrades:
	#   1. View cone - a fish ignores conspecifics outside ~120° of its forward
	#      heading. You can't school with fish behind you.
	#   2. Position prediction - alignment + cohesion target where neighbors
	#      WILL be (current pos + velocity * lookahead), not where they ARE.
	#      This causes the school to anticipate turns and look more cohesive.
	#   3. Speed matching - the fish drives toward the school's average speed
	#      so the whole group cruises together.
	#
	# Returns a steering vector that, added to the brain's target_velocity,
	# nudges this fish into formation. The vector's magnitude scales with how
	# urgently the fish needs to school (tightness).
	if neighbors.is_empty():
		return Vector3.ZERO

	const LOOKAHEAD: float = 0.4         # seconds of future-prediction
	const VIEW_DOT_THRESHOLD: float = -0.4  # cos(~115°) - rear blind spot

	var sep := Vector3.ZERO
	var ali := Vector3.ZERO
	var coh := Vector3.ZERO
	var school_speed_sum: float = 0.0
	var count_conspecific: int = 0
	var effective_sep_radius: float = separation_radius / tightness
	var sep_r2: float = effective_sep_radius * effective_sep_radius

	for n in neighbors:
		if not n is Fish or n == self:
			continue
		var f: Fish = n
		var diff: Vector3 = position - f.position
		var d2: float = diff.length_squared()
		if d2 < 1e-4:
			continue
		# Separation considers all species (you don't want to swim into anyone).
		if d2 < sep_r2:
			sep += diff.normalized() / maxf(sqrt(d2), 0.1)
		# Alignment + cohesion are conspecific-only and view-cone-gated.
		if f.species != species:
			continue
		var to_neighbor: Vector3 = -diff  # f.position - position
		var dot_v: float = heading.dot(to_neighbor.normalized())
		if dot_v < VIEW_DOT_THRESHOLD:
			continue  # behind us, ignore
		var predicted_pos: Vector3 = f.position + f.velocity * LOOKAHEAD
		ali += f.heading
		coh += predicted_pos
		school_speed_sum += f.speed
		count_conspecific += 1

	var steer := sep * 2.4

	if count_conspecific > 0:
		ali /= float(count_conspecific)
		coh /= float(count_conspecific)
		var school_avg_speed: float = school_speed_sum / float(count_conspecific)
		var ali_strength: float = 0.9
		var coh_strength: float = 0.7 * tightness
		# Alignment: steer toward avg heading.
		if ali.length() > 0.001:
			steer += ali.normalized() * ali_strength
		# Cohesion: steer toward predicted center of mass.
		var to_center: Vector3 = coh - position
		if to_center.length() > 0.001:
			steer += to_center.normalized() * coh_strength
		# Speed matching: nudge in heading direction proportional to school
		# speed delta. If the school is faster than us, accelerate.
		var speed_delta: float = school_avg_speed - speed
		steer += heading * clampf(speed_delta * 0.3, -0.4, 0.4)

	return steer


func _apply_aging_tint() -> void:
	# Senescent fish fade their voxel materials toward a desaturated, darker
	# version of base_color. We only need to do this once when entering
	# senescence; track via _aged_applied to avoid repeated work.
	if _aged_applied:
		return
	_aged_applied = true
	var fade: Color = base_color.lerp(Color8(120, 110, 100), 0.45)
	# Walk all MeshInstance3D descendants and tint their material to the
	# faded color. Cheap since fish are small.
	for child in _all_meshes(self):
		var mi: MeshInstance3D = child
		var m: Material = mi.material_override
		if m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter("albedo", fade)


var _aged_applied: bool = false

func _all_meshes(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is MeshInstance3D:
			out.append(c)
		out.append_array(_all_meshes(c))
	return out


func _wall_avoid(b: AABB) -> Vector3:
	var margin := 1.0
	var v := Vector3.ZERO
	if position.x < b.position.x + margin:
		v.x += 1.0
	if position.x > b.position.x + b.size.x - margin:
		v.x -= 1.0
	if position.y < b.position.y + margin:
		v.y += 1.0
	if position.y > b.position.y + b.size.y - margin:
		v.y -= 1.0
	if position.z < b.position.z + margin:
		v.z += 1.0
	if position.z > b.position.z + b.size.z - margin:
		v.z -= 1.0
	return v


func _find_breeding_partner(neighbors: Array) -> Fish:
	# Same-species, opposite sex, available, healthy, within 3 units.
	# Among valid candidates, prefer the one with the best *attractiveness*
	# score = lower distance bonus + breed_count bias (successful breeders
	# are more attractive). This creates very mild sexual selection -
	# lineages with successful ancestors get picked slightly more often.
	var best: Fish = null
	var best_score: float = -INF
	for n in neighbors:
		if not n is Fish or n == self:
			continue
		var f: Fish = n
		if f.species != species or f.sex == sex:
			continue
		if f.maturity != MATURITY_ADULT or f.breed_cooldown > 0.0:
			continue
		if f.partner != null:
			continue
		if f.hunger > 0.5 or f.energy < 0.55 or f.stress > 0.4:
			continue
		var d2: float = f.position.distance_squared_to(position)
		if d2 > 9.0:
			continue
		# Lower distance is better, more breed_count is better.
		var score: float = -d2 + sqrt(float(f.breed_count)) * 0.5
		if score > best_score:
			best_score = score
			best = f
	return best


func _find_nearest_plant(plants: Array, max_dist: float) -> Plant:
	var best: Plant = null
	var best_d: float = max_dist
	for p in plants:
		if not is_instance_valid(p) or p.biomass() <= 0:
			continue
		var top_pos: Vector3 = (p as Plant).global_position
		top_pos.y = (p as Plant).top_world_y()
		var d: float = top_pos.distance_to(position)
		if d < best_d:
			best_d = d
			best = p
	return best


func _find_nearest_tall_plant(plants: Array, max_dist: float, min_biomass: int) -> Plant:
	# Fish only nibble plants that are at least min_biomass voxels tall.
	# Spares saplings + carpets.
	var best: Plant = null
	var best_d: float = max_dist
	for p in plants:
		if not is_instance_valid(p) or p.biomass() < min_biomass:
			continue
		var top_pos: Vector3 = (p as Plant).global_position
		top_pos.y = (p as Plant).top_world_y()
		var d: float = top_pos.distance_to(position)
		if d < best_d:
			best_d = d
			best = p
	return best


# Used by SimDriver when this fish breeds with a partner.
func produce_offspring_genome(partner: Fish) -> Dictionary:
	# Mix parental traits with moderate mutation so color + size drift is
	# visible across 3-5 generations. Heritable: color, accent color,
	# voxel scale (size), max_speed, lifespan, preferred Y layer.
	var mix := 0.5
	var color_muta := 0.18   # noticeable hue jiggle per generation
	var size_muta := 0.06    # size drift; capped within reasonable bounds
	var lerp_random_base := Color(randf(), randf(), randf())
	var lerp_random_accent := Color(randf(), randf(), randf())
	var new_size: float = (adult_voxel_scale + partner.adult_voxel_scale) * 0.5 \
		+ randf_range(-size_muta, size_muta) * adult_voxel_scale
	# Hold size in a reasonable band so mutation can't shrink/grow the species
	# unboundedly across generations.
	new_size = clampf(new_size, adult_voxel_scale * 0.6, adult_voxel_scale * 1.5)
	# Phenotype inheritance: average parents + small mutation, clamped.
	var new_fin: float = clampf(
		(fin_length_factor + partner.fin_length_factor) * 0.5 + randf_range(-0.12, 0.12),
		0.6, 1.6)
	var new_elong: float = clampf(
		(body_elongation + partner.body_elongation) * 0.5 + randf_range(-0.05, 0.05),
		0.85, 1.15)
	# Pattern: usually inherits from one parent, small chance to mutate to
	# a different pattern entirely.
	var new_pattern: int = pattern_type if randf() < 0.5 else partner.pattern_type
	if randf() < 0.06:
		new_pattern = randi() % 4
	# Dots: average then small jitter, clamped 0-4.
	var new_dots: int = clampi(
		int((color_dot_count + partner.color_dot_count) * 0.5 + randf_range(-1.0, 1.0)),
		0, 4)
	var g: Dictionary = {
		"species": species,
		"base_color": base_color.lerp(partner.base_color, mix).lerp(
			lerp_random_base, color_muta),
		"accent_color": accent_color.lerp(partner.accent_color, mix).lerp(
			lerp_random_accent, color_muta * 0.7),
		"adult_voxel_scale": new_size,
		"max_age_s": (max_age_s + partner.max_age_s) * 0.5 + randf_range(-25.0, 25.0),
		"max_speed": (max_speed + partner.max_speed) * 0.5 + randf_range(-0.15, 0.15),
		"schooling_strength": (schooling_strength + partner.schooling_strength) * 0.5,
		"separation_radius": separation_radius,
		"herbivory": herbivory,
		"fecundity": fecundity,
		"clutch_size": clutch_size,
		"preferred_y": preferred_y + randf_range(-0.4, 0.4),
		"sex": randi() % 2,
		"generation": maxi(generation, partner.generation) + 1,
		"fin_length_factor": new_fin,
		"body_elongation": new_elong,
		"pattern_type": new_pattern,
		"color_dot_count": new_dots,
	}
	return g
