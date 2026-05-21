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
# Tail tint - a SEPARATE bright color zone applied to the tail fin voxels
# instead of falling back to a darkened base_color. This is what gives male
# guppies their dramatic "dark body, brilliant red tail" silhouette. If
# the genome doesn't supply one, we derive it from accent_color at build
# time (no behavior change for older fish).
var tail_color: Color = Color8(0, 0, 0)
var _tail_color_set: bool = false
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

# ---- Body skeleton (heritable) ----
# These augment the existing body_elongation / body_depth_factor / head_proportion
# so the same skeleton can produce visually distinct silhouettes:
#  - barbels       whisker voxels under the head (catfish, loach, cory)
#  - mouth_orientation
#                  0 = horizontal (default), +1 = downturned (bottom feeder),
#                  -1 = upturned (surface feeder)
#  - eye_size_factor  0.6 (beady) to 1.6 (puffer / killifish bug-eyes)
#  - ventral_profile  1.0 = symmetric, <1 = flat-bellied (bottom dweller),
#                   >1 = round-bellied (puffer, gravid)
#  - back_arch     1.0 = symmetric, >1 = hump-backed (angelfish, gourami)
#  - tail_shape    0=forked, 1=fan/round, 2=lyre (long top+bottom), 3=square
#  - armor_plates  cory-style lateral plate accents (dark vertical stripes
#                  drawn over the body sides)
var has_barbels: bool = false
var mouth_orientation: int = 0
var eye_size_factor: float = 1.0
var ventral_profile: float = 1.0
var back_arch: float = 1.0
var tail_shape: int = 0
var armor_plates: bool = false

# ---- Food preferences (per-species, not heritable) ----
# Walstad ecosystem wiring: which species hunt which prey beyond the
# generic boids brain. The fish brain checks these flags before deciding
# what to chase.
#   snail_predator   loach + puffer types preferentially target baby snails
#   algae_grazer     cory + small herbivores graze algae clusters
var snail_predator: bool = false
var algae_grazer: bool = false

# ---- Territory / swim pattern (heritable) ----
# Each fish has a "home point" it loosely orbits, plus a swim_pattern that
# controls HOW it moves around that home. Without this, every fish settles
# at the tank centroid because every brain agrees the centroid is optimal,
# so the whole population clumps. Giving each fish a different home spreads
# them across the tank realistically.
#
# All heritable, so lineages can split into different territorial niches
# over generations.
var home_x: float = INF                  # INF = set lazily from spawn pos
var home_y: float = INF                  # vertical territory anchor; INF = use preferred_y
var home_z: float = INF
var home_radius: float = 2.5             # how far the fish wanders from home (XZ)
var home_y_radius: float = 0.8           # how far the fish strays vertically from home_y
var wander_strength: float = 1.0         # heading_offset magnitude multiplier
var dart_chance: float = 0.0             # per-second probability of darting
var dart_speed_mult: float = 1.6         # multiplier on speed during a dart
# Pattern dispatch - used to derive defaults + influence the brain. Patterns:
#   "school"   tight cohesive group (default)
#   "shoal"    loose group, wider territory
#   "dart"     surface dart-and-pause (killifish)
#   "hover"    station-keeps near home (angelfish)
#   "cruise"   slow long arcs (betta, large fish)
#   "meander"  slow random wander (pufferfish)
#   "shuffle"  bottom-hugging slow group (corydoras, mudsifter)
var swim_pattern: String = "school"


# ---- Emergent speciation ----
# Compare this fish's heritable skeleton genes against its species'
# template in TankConfig.SPECIES_LIBRARY. Fish that differ on discrete
# traits (tail_shape, has_barbels, armor_plates, mouth_orientation) OR
# drift past a percentage threshold on continuous traits (body_elongation,
# body_depth_factor, eye_size_factor) get a morph suffix like "sp. A".
#
# This is the simplest "new species" rule that's actually visible to the
# user: when a lineage drifts so far that it doesn't match the founder
# silhouette anymore, the HUD shows it as a separate morph.
func morph_label() -> String:
	var lib = get_tree().root.get_node_or_null("TankConfig")
	if lib == null or not lib.SPECIES_LIBRARY.has(species):
		return species
	var template: Dictionary = lib.SPECIES_LIBRARY[species].get("genome", {})
	var tags: Array[String] = []
	# Discrete trait changes - each maps to a single distinct morph letter.
	if int(template.get("tail_shape", 0)) != tail_shape:
		tags.append(["F", "R", "L", "S"][clampi(tail_shape, 0, 3)])
	if bool(template.get("has_barbels", false)) != has_barbels:
		tags.append("B" if has_barbels else "b")
	if bool(template.get("armor_plates", false)) != armor_plates:
		tags.append("A" if armor_plates else "a")
	if int(template.get("mouth_orientation", 0)) != mouth_orientation:
		tags.append(["U", "M", "D"][clampi(mouth_orientation + 1, 0, 2)])
	# Continuous trait drift past LARGE thresholds - founders with normal
	# phenotype spread shouldn't trigger; only multi-generation drift should.
	if absf(body_elongation - float(template.get("body_elongation", 1.0))) > 0.45:
		tags.append("E")
	if absf(body_depth_factor - float(template.get("body_depth_factor", 1.0))) > 0.55:
		tags.append("d")
	if absf(eye_size_factor - float(template.get("eye_size_factor", 1.0))) > 0.55:
		tags.append("e")
	if tags.is_empty():
		return species
	return "%s sp. %s" % [species, "".join(tags)]
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
# Flips to true while in MALE courtship display - drives the renderer to
# flare the tail wag and over-bank into the S-curve dance. Cleared
# automatically when courtship ends or the fish moves out of display
# range.
var _courtship_flare: bool = false
# Aerial respiration: cories + loaches periodically dart to the surface to
# gulp atmospheric air, then sink back to the substrate. Real Walstad
# behavior - it's a stress signal in healthy tanks but routine in any
# armored catfish. Counts down between trips, becomes negative during a
# trip (the negative value drives the upward bias).
var _aerial_timer: float = -1.0
var _aerial_target_y: float = 0.0
# Substrate sifting: "shuffle" species (cory, loach) periodically tilt
# nose-down at the substrate and stay put for a couple of seconds, working
# their barbels through the mulm. Real Walstad behavior - the alternative
# is constant scuttling, which looks unrealistic at rest. Counts down
# between sift events; while > 0 the fish almost stops and applies a
# downward pitch tilt.
var _sift_timer: float = 0.0
var _sift_cooldown: float = 0.0
# Startle: one fish triggering a burst can cause its school-mates to
# panic in the SAME direction (classic predator-evasion behavior).
# When _startle_remaining > 0, the dart heading is forced to match the
# group's startle vector.
var _startle_remaining: float = 0.0
var _startle_heading: Vector3 = Vector3.ZERO

# Size growth from feeding. Well-fed adults slowly grow above their starting
# size; chronically hungry ones shrink. effective_size() is the property
# used for size-based predation (bigger fish hunt smaller ones).
var growth_factor: float = 1.0
var max_growth: float = 1.4     # apex species (betta) override higher (~2.0)

# Visible phenotypes - heritable traits affecting body proportions + pattern.
# Drift over generations and create lineages that look distinct.
var fin_length_factor: float = 1.0   # multiplier on tail / dorsal / anal fin extent (0.6-1.6)
var body_elongation: float = 1.0     # body length stretch factor (0.85-1.15)
var body_depth_factor: float = 1.0   # body height stretch factor (0.7-1.4) - puffer vs minnow
var head_proportion: float = 1.0     # head size relative to body (0.7-1.3)
var dorsal_height_factor: float = 1.0  # dorsal fin height multiplier (0.6-1.6)
var tail_fork_depth: float = 1.0     # how spread the top/bottom prongs are (0.5-1.5)
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
	if genome.has("tail_color"):
		tail_color = genome["tail_color"]
		_tail_color_set = true
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
	# Sexual dimorphism for species that have it. Guppies are the obvious
	# case: males are tiny, brightly colored, and grow long flowing tails;
	# females are larger, dull silver, and have small tails. The genome
	# carries a base template; if dimorphism is enabled, we override the
	# visible traits for this individual based on sex BEFORE building the
	# body. Drift-through-generations still works because the underlying
	# stored values are shared.
	if bool(genome.get("dimorphic", false)) and sex == 1:
		# Female form: drop saturation, enlarge body, shrink fins.
		base_color = Color(base_color.r, base_color.g, base_color.b) \
			.lerp(Color(0.78, 0.78, 0.80), 0.55)   # silvery wash
		if _tail_color_set:
			tail_color = tail_color.lerp(Color(0.7, 0.72, 0.75), 0.6)
		accent_color = accent_color.lerp(Color(0.65, 0.65, 0.70), 0.45)
		# Bigger, dumpier body.
		adult_voxel_scale *= 1.35
		body_depth_factor *= 1.15
		ventral_profile = clampf(ventral_profile * 1.25, 0.55, 1.9)
		# Smaller, drabber fins.
		fin_length_factor = clampf(fin_length_factor * 0.55, 0.5, 1.8)
		dorsal_height_factor = clampf(dorsal_height_factor * 0.7, 0.5, 1.8)
	generation = genome.get("generation", 0)
	fin_length_factor = genome.get("fin_length_factor", fin_length_factor)
	body_elongation = genome.get("body_elongation", body_elongation)
	body_depth_factor = genome.get("body_depth_factor", body_depth_factor)
	head_proportion = genome.get("head_proportion", head_proportion)
	dorsal_height_factor = genome.get("dorsal_height_factor", dorsal_height_factor)
	tail_fork_depth = genome.get("tail_fork_depth", tail_fork_depth)
	pattern_type = int(genome.get("pattern_type", pattern_type))
	color_dot_count = int(genome.get("color_dot_count", color_dot_count))
	# Body skeleton phenotypes (heritable - drift in produce_offspring_genome).
	has_barbels = bool(genome.get("has_barbels", has_barbels))
	mouth_orientation = int(genome.get("mouth_orientation", mouth_orientation))
	eye_size_factor = float(genome.get("eye_size_factor", eye_size_factor))
	ventral_profile = float(genome.get("ventral_profile", ventral_profile))
	back_arch = float(genome.get("back_arch", back_arch))
	tail_shape = int(genome.get("tail_shape", tail_shape))
	armor_plates = bool(genome.get("armor_plates", armor_plates))
	# Food preferences (species-level, not heritable).
	snail_predator = bool(genome.get("snail_predator", snail_predator))
	algae_grazer = bool(genome.get("algae_grazer", algae_grazer))
	# Swim pattern + territory (heritable).
	swim_pattern = String(genome.get("swim_pattern", swim_pattern))
	# Apply pattern-derived defaults FIRST so explicit genome values can
	# override them on the next reads below.
	_apply_swim_pattern_defaults()
	home_x = float(genome.get("home_x", home_x))
	home_y = float(genome.get("home_y", home_y))
	home_z = float(genome.get("home_z", home_z))
	home_radius = float(genome.get("home_radius", home_radius))
	home_y_radius = float(genome.get("home_y_radius", home_y_radius))
	wander_strength = float(genome.get("wander_strength", wander_strength))
	dart_chance = float(genome.get("dart_chance", dart_chance))
	dart_speed_mult = float(genome.get("dart_speed_mult", dart_speed_mult))
	# Lazy initialization of home: if the genome didn't supply one, anchor
	# to the spawn position (XZ) and to preferred_y (Y) plus jitter. Each
	# fish ends up with its own 3D territory rather than every fish
	# converging on the tank centroid AT preferred_y.
	if is_inf(home_x):
		home_x = global_position.x + randf_range(-1.5, 1.5)
		home_z = global_position.z + randf_range(-1.5, 1.5)
	if is_inf(home_y):
		home_y = preferred_y + randf_range(-0.6, 0.6)
	# A fry is born tiny - we'll lerp scale as it matures.
	scale = Vector3.ONE * _maturity_scale()
	_build_body()


# Apply per-pattern defaults. Only fills in fields the genome hasn't already
# overridden (sentinel-style: a default of 1.0 / 2.5 / 0.0 means "use the
# pattern's pick"). Each pattern shapes how the fish wanders + how often it
# darts; the actual schooling weight stays driven by genome.schooling_strength.
func _apply_swim_pattern_defaults() -> void:
	match swim_pattern:
		"school":
			home_radius = 2.5
			wander_strength = 1.0
			dart_chance = 0.005
		"shoal":
			home_radius = 4.5
			wander_strength = 1.3
			dart_chance = 0.01
		"dart":
			home_radius = 3.0
			wander_strength = 0.7
			dart_chance = 0.045
			dart_speed_mult = 1.9
		"hover":
			home_radius = 0.9
			wander_strength = 0.35
			dart_chance = 0.002
		"cruise":
			home_radius = 6.0
			wander_strength = 0.55
			dart_chance = 0.003
		"meander":
			home_radius = 3.5
			wander_strength = 1.5
			dart_chance = 0.0
		"shuffle":
			home_radius = 2.0
			wander_strength = 0.5
			dart_chance = 0.012
			dart_speed_mult = 1.4


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
	# Tail fin material: defaults to a darker shade of base_color, but if
	# the genome supplied an explicit tail_color we use that (male guppies'
	# bright red/orange fan against a dark body).
	var effective_tail: Color = tail_color if _tail_color_set \
		else base_color.darkened(0.15)
	var mat_tail := _make_mat(effective_tail)

	_bank_pivot = Node3D.new()
	_bank_pivot.name = "BankPivot"
	add_child(_bank_pivot)

	# ---- HEAD (rigid, at z = -2.5v, the front of the fish) ----
	# head_proportion scales the head's overall size relative to the body,
	# so small-headed minnow types contrast against big-headed cichlids.
	var hp: float = head_proportion
	var head := Node3D.new()
	head.name = "Head"
	_bank_pivot.add_child(head)
	_add_voxel_to(head, Vector3(0, 0, -2.5 * v),
		Vector3(v * 0.95 * hp, v * 0.9 * hp, v * hp), mat_body)
	# Forehead - lighter. Lifts on hump-backed phenotypes (angelfish, gourami).
	_add_voxel_to(head, Vector3(0, v * 0.5 * hp * back_arch, -2.5 * v),
		Vector3(v * 0.6 * hp, v * 0.3 * hp, v * hp), mat_top)
	# Belly under head. ventral_profile pulls it lower for round-bellied
	# species (puffer) or tightens it up for flat-bellied bottom dwellers
	# (cory, loach).
	_add_voxel_to(head, Vector3(0, -v * 0.5 * hp * ventral_profile, -2.5 * v),
		Vector3(v * 0.6 * hp, v * 0.3 * hp, v * hp), mat_belly)
	# Eyes - scaled by eye_size_factor. Killifish + puffer get bigger eyes
	# (1.4+), corydoras + loach get small beady eyes (~0.7).
	var es: float = eye_size_factor
	_add_voxel_to(head, Vector3(v * 0.4 * hp, v * 0.1 * hp, -2.4 * v),
		Vector3(v * 0.2 * hp * es, v * 0.25 * hp * es, v * 0.25 * es), mat_eye)
	_add_voxel_to(head, Vector3(-v * 0.4 * hp, v * 0.1 * hp, -2.4 * v),
		Vector3(v * 0.2 * hp * es, v * 0.25 * hp * es, v * 0.25 * es), mat_eye)
	# Mouth indicator: a small accent voxel positioned by mouth_orientation.
	# +1 = downturned (sifters), -1 = upturned (surface feeders), 0 = neutral.
	var mouth_y: float = -v * 0.25 * hp * float(mouth_orientation) - v * 0.1 * hp
	_add_voxel_to(head, Vector3(0, mouth_y, -3.0 * v),
		Vector3(v * 0.35 * hp, v * 0.2 * hp, v * 0.2 * hp), mat_belly)
	# Barbels - catfish/loach whiskers. Two pairs of tiny dark voxels under
	# the mouth, angled forward + down. Only drawn if has_barbels.
	if has_barbels:
		var mat_barbel := _make_mat(base_color.darkened(0.5))
		var barbel_y: float = -v * 0.45 * hp
		var barbel_z: float = -2.9 * v
		for x_side in [-0.30, -0.18, 0.18, 0.30]:
			_add_voxel_to(head, Vector3(x_side * v * hp, barbel_y, barbel_z),
				Vector3(v * 0.06, v * 0.08, v * 0.25), mat_barbel)

	# ---- BODY MID (gentle counter-wag) - thickest part of the fish ----
	_body_mid_pivot = Node3D.new()
	_body_mid_pivot.name = "BodyMid"
	_body_mid_pivot.position = Vector3(0, 0, -1.5 * v)
	_bank_pivot.add_child(_body_mid_pivot)
	# Segments at z offsets 0, v, 2v (back along the body from the pivot).
	# ventral_profile shifts the belly center DOWN for round-bellied species
	# (puffer); back_arch lifts the top center UP for hump-backed species
	# (angelfish). Together these let one skeleton produce visibly different
	# silhouettes.
	var seg_widths: Array[float] = [1.15, 1.20, 1.0]
	for i in seg_widths.size():
		var bw: float = seg_widths[i]
		var bs: float = v * bw
		var bz: float = i * v
		# Main body voxel. Slightly off-center if ventral_profile != back_arch.
		var body_y_offset: float = (back_arch - ventral_profile) * v * 0.15
		_add_voxel_to(_body_mid_pivot, Vector3(0, body_y_offset, bz),
			Vector3(bs * 0.95, bs, v), mat_body)
		# Top accent - pushed up by back_arch.
		_add_voxel_to(_body_mid_pivot, Vector3(0, bs * 0.5 * back_arch, bz),
			Vector3(bs * 0.55, v * 0.25, v), mat_top)
		# Belly accent - pushed down by ventral_profile.
		_add_voxel_to(_body_mid_pivot, Vector3(0, -bs * 0.5 * ventral_profile, bz),
			Vector3(bs * 0.55, v * 0.25, v), mat_belly)
	# Armor plates: cory-style lateral plating. Drawn as 4 thin dark vertical
	# bars across the lateral midline. Stacks ON TOP of pattern_type, so a
	# cory with vertical bars + armor reads as a peppered fish in armor.
	if armor_plates:
		var mat_armor := _make_mat(base_color.darkened(0.55))
		for i in seg_widths.size():
			for x_side in [-1.0, 1.0]:
				_add_voxel_to(_body_mid_pivot, Vector3(x_side * v * 0.52, 0, i * v),
					Vector3(v * 0.08, v * 0.95, v * 0.22), mat_armor)
				_add_voxel_to(_body_mid_pivot,
					Vector3(x_side * v * 0.52, 0, i * v + v * 0.45),
					Vector3(v * 0.08, v * 0.95, v * 0.22), mat_armor)
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
	# Height scaled by dorsal_height_factor so long-dorsal phenotype is visible.
	var dh: float = dorsal_height_factor
	_dorsal_pivot = Node3D.new()
	_dorsal_pivot.name = "DorsalPivot"
	_dorsal_pivot.position = Vector3(0, v * 0.75, v * 1.0)
	_body_mid_pivot.add_child(_dorsal_pivot)
	_add_voxel_to(_dorsal_pivot, Vector3(0, v * 0.2 * dh, 0),
		Vector3(v * 0.15, v * 0.4 * dh, v * 1.2), mat_fin)
	_add_voxel_to(_dorsal_pivot, Vector3(0, v * 0.45 * dh, v * 0.2),
		Vector3(v * 0.12, v * 0.25 * dh, v * 0.6), mat_fin)
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
	# Tail fin shape - one of four templates picked by `tail_shape`. Each
	# uses fin_length_factor for overall size + tail_fork_depth for the
	# fork separation, but the silhouette differs.
	#   0 = forked     (default - tuna / glassdart - top + bottom prongs)
	#   1 = fan        (round paddle - guppy / goldfish)
	#   2 = lyre       (long upper + lower trailing rays - betta / angelfish)
	#   3 = square     (paddle - corydoras / loach)
	var fl: float = fin_length_factor
	var tf: float = tail_fork_depth
	# Tail voxels use mat_tail (the bright zone). Dorsal / anal / pectorals
	# above continue to use mat_fin.
	match tail_shape:
		1:  # fan / round
			for ang in [-0.75, -0.25, 0.25, 0.75]:
				_add_voxel_to(_tail_pivot,
					Vector3(0, v * ang * 0.6, v * (0.95 * fl)),
					Vector3(v * 0.15, v * 0.4, v * (0.55 * fl)), mat_tail)
		2:  # lyre - long top + bottom trailing rays
			_add_voxel_to(_tail_pivot, Vector3(0, v * 0.35 * tf, v * (0.8 * fl)),
				Vector3(v * 0.13, v * 0.35, v * (0.5 * fl)), mat_tail)
			_add_voxel_to(_tail_pivot, Vector3(0, -v * 0.35 * tf, v * (0.8 * fl)),
				Vector3(v * 0.13, v * 0.35, v * (0.5 * fl)), mat_tail)
			_add_voxel_to(_tail_pivot,
				Vector3(0, v * (1.1 * fl * tf), v * (1.7 * fl)),
				Vector3(v * 0.12, v * (0.5 * fl), v * (0.7 * fl)), mat_tail)
			_add_voxel_to(_tail_pivot,
				Vector3(0, v * (-1.1 * fl * tf), v * (1.7 * fl)),
				Vector3(v * 0.12, v * (0.5 * fl), v * (0.7 * fl)), mat_tail)
		3:  # square paddle
			_add_voxel_to(_tail_pivot, Vector3(0, 0, v * (0.95 * fl)),
				Vector3(v * 0.15, v * 1.0, v * (0.7 * fl)), mat_tail)
		_:  # 0 = forked (default)
			_add_voxel_to(_tail_pivot, Vector3(0, v * 0.45 * tf, v * (0.9 * fl)),
				Vector3(v * 0.15, v * 0.4, v * (0.6 * fl)), mat_tail)
			_add_voxel_to(_tail_pivot, Vector3(0, -v * 0.45 * tf, v * (0.9 * fl)),
				Vector3(v * 0.15, v * 0.4, v * (0.6 * fl)), mat_tail)
			_add_voxel_to(_tail_pivot,
				Vector3(0, v * (0.7 * fl * tf), v * (1.4 * fl)),
				Vector3(v * 0.12, v * (0.3 * fl), v * (0.4 * fl)), mat_tail)
			_add_voxel_to(_tail_pivot,
				Vector3(0, v * (-0.7 * fl * tf), v * (1.4 * fl)),
				Vector3(v * 0.12, v * (0.3 * fl), v * (0.4 * fl)), mat_tail)
	# Apply body elongation + depth scaling. The bank pivot's local Y stretches
	# the body height (puffer = 1.4, minnow = 0.7), Z stretches length.
	if _bank_pivot != null:
		_bank_pivot.scale.z = body_elongation
		_bank_pivot.scale.y = body_depth_factor


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

func tick(dt: float, neighbors: Array, plants: Array, algae_array: Array, waste: Array,
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
	_startle_remaining = maxf(0.0, _startle_remaining - dt)

	# Substrate sifting (shuffle species only). Slow countdown to next
	# sift. While _sift_timer > 0 the brain damps velocity to almost
	# zero AND we tilt nose-down via _process. Sifts happen near the
	# substrate (don't sift if home_y is mid-water).
	if swim_pattern == "shuffle" and home_y < 3.0:
		_sift_cooldown = maxf(0.0, _sift_cooldown - dt)
		_sift_timer = maxf(0.0, _sift_timer - dt)
		if _sift_timer <= 0.0 and _sift_cooldown <= 0.0 \
				and burst_remaining <= 0.0 and randf() < dt * 0.4:
			_sift_timer = randf_range(1.5, 3.0)
			_sift_cooldown = randf_range(6.0, 12.0)

	# Cory / loach aerial respiration. Every ~25-40 sim seconds, a
	# "shuffle" pattern fish darts to the surface, gulps, and sinks back.
	# The trip is implemented by overriding home_y temporarily via the
	# _aerial_timer + _aerial_target_y fields - see Y-enforcement block.
	if swim_pattern == "shuffle":
		if _aerial_timer <= 0.0:
			# Idle - count down to next trip OR start a trip.
			_aerial_timer -= dt
			if _aerial_timer < -randf_range(25.0, 40.0):
				# Begin the gulp trip - target Y just below water surface.
				var surface_y: float = 0.0
				if sim != null and sim.get("substrate_top_y") != null:
					surface_y = float(sim.substrate_top_y) + 5.0
				else:
					surface_y = home_y + 4.0
				_aerial_target_y = surface_y - 0.2
				_aerial_timer = randf_range(2.0, 3.5)   # trip duration
		else:
			_aerial_timer -= dt

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
	# Burst speed uses the fish's own dart_speed_mult (heritable) when a dart
	# is active; falls back to a sensible 1.5 for non-dart-pattern bursts
	# (flee, chase) which still trigger burst_remaining.
	var burst_mult: float = dart_speed_mult if dart_speed_mult > 1.0 else 1.5
	var effective_max := max_speed * (burst_mult if burst_remaining > 0.0 else 1.0)
	current_mode = Mode.CRUISE

	# Tier 0: wall avoidance always runs (additive).
	desired += _wall_avoid(world_bounds) * 3.0

	# Tier 0.5: TERRITORIAL DEFENSE. swim_pattern "hover" species (angelfish)
	# claim a small territory around home_x/home_z and chase off conspecifics
	# OR similar-sized neighbors that enter it. Real angelfish behaviour - a
	# mated pair claims a corner of the tank and herds intruders out.
	if swim_pattern == "hover" and maturity == MATURITY_ADULT:
		for n in neighbors:
			if not (n is Fish):
				continue
			var intruder: Fish = n
			# Don't chase your own partner or fry.
			if intruder == partner:
				continue
			if intruder.maturity == MATURITY_FRY:
				continue
			# Is the intruder INSIDE my territory? Use home_radius.
			var dx: float = intruder.position.x - home_x
			var dz: float = intruder.position.z - home_z
			var d2: float = dx * dx + dz * dz
			if d2 < home_radius * home_radius:
				# Push outward, with the chasing fish pursuing the intruder
				# in the direction AWAY from home. Visible aggressive lunge.
				var to_intruder: Vector3 = intruder.position - position
				if to_intruder.length_squared() > 0.04:
					desired += to_intruder.normalized() * effective_max * 0.9
					if burst_remaining <= 0.0 and energy > 0.4:
						burst_remaining = 0.3

	# Tier 1: COURTSHIP. Already paired? Continue the dance toward spawn.
	if partner != null:
		if not is_instance_valid(partner) or partner.maturity != MATURITY_ADULT:
			partner = null
			court_timer = 0.0
			_courtship_flare = false
		else:
			current_mode = Mode.COURT
			var to_partner: Vector3 = partner.position - position
			var dist: float = to_partner.length()
			# Swim alongside (not into) the partner: target a point slightly to one side.
			var side: Vector3 = to_partner.cross(Vector3.UP).normalized() * 0.4
			var courtship_target: Vector3 = partner.position + side
			# MALE COURTING DISPLAY. Real male guppies + bettas parade
			# alongside the female in a tight S-curve, flaring their tail
			# fins to maximum spread. We simulate this by adding a
			# sinusoidal lateral offset (the S-curve) when the male is
			# close enough to display, scaled by the courtship sequence
			# duration so the dance accelerates as the spawn approaches.
			if sex == 0 and dist < 1.8:
				var t_phase: float = court_timer * 4.5
				var s_offset: Vector3 = to_partner.cross(Vector3.UP).normalized() \
					* sin(t_phase) * 0.35
				desired += (courtship_target + s_offset - position).normalized() \
					* effective_max * 0.85
				# Mark the renderer flag - _apply_render() uses it to flare the
				# tail wag amplitude AND temporarily boost the bank angle so
				# the dance reads visually.
				_courtship_flare = true
			else:
				desired += (courtship_target - position).normalized() * effective_max * 0.7
				_courtship_flare = false
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
				_courtship_flare = false
			target_velocity = desired.limit_length(effective_max)
			return events

	# Tier 1b: SCAVENGE WASTE. Fish opportunistically eat waste particles
	# that drift past. Cheaper than chasing live food. Applies to all fish,
	# herbivores or not, when even slightly hungry.
	if hunger > 0.3 and maturity != MATURITY_FRY:
		var best_w: WasteParticle = null
		var best_d2: float = 144.0  # 12.0^2 max range for food! High awareness.
		for w in waste:
			if not is_instance_valid(w):
				continue
			# Fish prefer fresh-fallen waste in mid-water, not settled.
			if w.settled and randf() > 0.4:
				continue
			var d2: float = (w as Node3D).global_position.distance_squared_to(position)
			var max_dist_sq: float = 144.0 if w.kind == 3 else 16.0 # 3=FOOD, 16.0=4.0^2 for regular waste
			if d2 < max_dist_sq and d2 < best_d2:
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
				var pull: float = 0.9
				if best_w.kind == 3: # FOOD
					pull = 1.9 # Intently swim to it
					# Dart towards food and trigger a feeding frenzy!
					if burst_remaining <= 0.0 and energy > 0.15 and randf() < 0.4:
						burst_remaining = randf_range(0.4, 0.7)
						# This fish bolting for food will spook/alert the school!
						_startle_heading = to_w.normalized()
						_startle_remaining = 0.5
				desired += to_w.normalized() * effective_max * pull
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

	# Tier 1.9: SPECIALIST DIET. Loach + puffer hunt baby snails preferentially;
	# corydoras + algae_grazer species crop algae clusters before they touch
	# rooted plants. This is the Walstad-style species-specific food web:
	# different fish fill different niches and prevent any one prey type
	# (snails, algae) from running away with the tank.
	if hunger > 0.4 and maturity == MATURITY_ADULT and burst_remaining <= 0.0:
		if snail_predator and sim != null and sim.get("snails_root") != null:
			var best_snail: Node3D = null
			var best_snail_d2: float = 9.0
			for s in sim.snails_root.get_children():
				if not is_instance_valid(s) or s.get("is_baby") != true:
					continue
				var d2: float = (s.global_position - position).length_squared()
				if d2 < best_snail_d2:
					best_snail_d2 = d2
					best_snail = s
			if best_snail != null:
				current_mode = Mode.FORAGE
				var to_snail: Vector3 = best_snail.global_position - position
				if best_snail_d2 < 0.25:
					events["kill_snail"] = best_snail
					hunger = maxf(0.0, hunger - 0.35)
				else:
					if burst_remaining <= 0.0 and energy > 0.3:
						burst_remaining = 0.35
					desired += to_snail.normalized() * effective_max * 1.1
					target_velocity = desired.limit_length(effective_max)
					return events
		if herbivory > 0.0 and algae_array.size() > 0:
			var best_alga: Node3D = null
			var best_alga_d2: float = 6.0
			for a in algae_array:
				if not is_instance_valid(a):
					continue
				var d2: float = (a.global_position - position).length_squared()
				if d2 < best_alga_d2:
					best_alga_d2 = d2
					best_alga = a
			if best_alga != null:
				current_mode = Mode.FORAGE
				if best_alga_d2 < 0.25:
					events["eat_algae"] = best_alga
					hunger = maxf(0.0, hunger - 0.2)
				else:
					var to_alga: Vector3 = best_alga.global_position - position
					desired += to_alga.normalized() * effective_max * 0.9
					target_velocity = desired.limit_length(effective_max)
					return events

	# Tier 2: HUNGRY HERBIVORE. Plants need at least 15 voxels of biomass
	# so fish have more food options before the shrimp graze them
	# down to nothing.
	if herbivory > 0.0 and hunger > 0.55 and maturity != MATURITY_FRY \
			and randf() < 0.5:
		if target_plant == null or not is_instance_valid(target_plant) \
				or target_plant.biomass() < 15:
			target_plant = _find_nearest_tall_plant(plants, 5.0, 15)
		if target_plant != null:
			current_mode = Mode.FORAGE
			var top: Vector3 = target_plant.global_position
			top.y = target_plant.top_world_y()
			var dist_sq: float = top.distance_squared_to(position)
			if dist_sq < 0.25 and nibble_cooldown <= 0.0:
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

	# Drift toward this fish's vertical territory (home_y). Each fish has
	# its own anchor (not just the species preferred_y) so 30 cory don't
	# stack on the same plane. Pull strength scales with how far past
	# home_y_radius the fish is, so close-to-layer doesn't fight wander but
	# wrong-layer is firm.
	#
	# If dissolved O2 is low, override: every fish biases up toward the
	# surface to gulp - the real-world "fish at the surface" symptom of an
	# under-aerated tank.
	var target_y: float = home_y
	# Aerial respiration trip overrides home_y for its duration.
	if _aerial_timer > 0.0:
		target_y = _aerial_target_y
	if sim != null and sim.get("dissolved_o2") != null:
		var o2: float = float(sim.dissolved_o2)
		if o2 < 0.4:
			var severity: float = clampf((0.4 - o2) / 0.4, 0.0, 1.0)
			var surface_y: float = float(sim.get("substrate_top_y")) + 5.0
			target_y = lerpf(home_y, surface_y, severity)
			stress = clampf(stress + dt * severity * 0.05, 0.0, 1.0)
	var dy: float = target_y - position.y
	# Stronger Y pull beyond home_y_radius; gentle within it. Result: fish
	# actively defend their water column layer instead of all sinking to
	# the substrate at night.
	var dy_outside: float = maxf(0.0, absf(dy) - home_y_radius)
	desired.y += signf(dy) * (home_y_radius * 0.4 + dy_outside * 1.4)

	# FRY HIDE-AT-LOG. Baby fish in real Walstad tanks survive by clinging
	# to driftwood, dense plants, or moss - anywhere larger fish can't
	# reach. We approximate this by pulling MATURITY_FRY individuals
	# toward the nearest hardscape voxel (driftwood or stone) on the
	# world's Hardscape + Aquascape containers. Once they grow into
	# juveniles the bias drops away. This dramatically improves fry
	# survival under predation pressure - matches the real "the babies
	# cling to the log" behavior the user observes in their tank.
	if maturity == MATURITY_FRY and sim != null:
		var hide_target: Vector3 = Vector3(INF, 0, 0)
		var best_d2: float = 16.0   # 4 unit search radius
		var hardscape = sim.get("hardscape_root")
		if hardscape != null:
			for h in hardscape.get_children():
				if not is_instance_valid(h):
					continue
				var d2: float = (h.global_position - position).length_squared()
				if d2 < best_d2:
					best_d2 = d2
					hide_target = h.global_position
		if not is_inf(hide_target.x):
			var to_hide: Vector3 = hide_target - position
			# Pull toward the log, but stop ~0.3 units short so the fry
			# hovers next to it rather than penetrating the voxel.
			var dist: float = to_hide.length()
			if dist > 0.3:
				desired += to_hide.normalized() * effective_max * 0.8

	# HOME-PULL. Each fish has its own home_x / home_z territory; if the fish
	# wanders past home_radius, pull it back. This is the single biggest fix
	# for "all the fish clump at the tank centroid" - without a per-fish
	# preferred horizontal position, the boids tier converges on the average
	# position of every neighbor, which IS the centroid.
	#
	# The pull strength scales with how far past home_radius the fish is, so
	# close-to-home doesn't fight wander but far-from-home is firm.
	var to_home: Vector3 = Vector3(home_x - position.x, 0.0, home_z - position.z)
	var dist_home: float = to_home.length()
	if dist_home > home_radius:
		var pull_strength: float = clampf(
			(dist_home / maxf(home_radius, 0.5)) - 1.0, 0.0, 2.0)
		desired += to_home.normalized() * effective_max * 0.5 * pull_strength

	# STARTLE PROPAGATION. School / shoal species are prey - in nature they
	# evade predators by all flipping the same direction at once. If any
	# CONSPECIFIC neighbor just started a dart burst, copy its heading.
	# This is what creates the dramatic "the whole school turns at once"
	# moment when something spooks them.
	if _startle_remaining <= 0.0 and burst_remaining <= 0.0 \
			and (swim_pattern == "school" or swim_pattern == "shoal"):
		for n in neighbors:
			if not (n is Fish):
				continue
			var nf: Fish = n
			if nf.species != species:
				continue
			if nf.burst_remaining > 0.2 and nf._startle_heading.length_squared() > 0.01:
				# Conspecific bolted recently - join the panic in their direction.
				_startle_remaining = 0.4
				_startle_heading = nf._startle_heading
				burst_remaining = 0.35
				break

	# DART TRIGGER. swim_pattern "dart" fish (killifish, shrimp-hunters) burst
	# unpredictably, breaking the tank's overall motion rhythm. dart_chance
	# is heritable so lineages can drift toward calmer or twitchier.
	if dart_chance > 0.0 and burst_remaining <= 0.0 \
			and randf() < dart_chance * dt * 10.0 and energy > 0.25:
		burst_remaining = randf_range(0.25, 0.45)
		# Snap heading_offset to a new random direction so the dart goes
		# somewhere new (not just "faster in current direction").
		var ang: float = randf() * TAU
		var dart_dir := Vector3(sin(ang), randf_range(-0.15, 0.15), cos(ang))
		heading_offset = dart_dir * (1.0 + wander_strength)
		# Record startle heading so school-mates can copy it.
		_startle_heading = dart_dir
		_startle_remaining = 0.4

	# HOVER / INVESTIGATE TRIGGER. Any fish might occasionally stop mid-water to
	# look around. This breaks up the constant swimming and adds lifelike personality.
	if burst_remaining <= 0.0 and _startle_remaining <= 0.0 and randf() < dt * 0.12 and energy > 0.3:
		# Temporarily stop swimming
		desired = Vector3.ZERO
		target_velocity = Vector3.ZERO
		return events
		
	# PLAYFUL DART (ZOOMIES). Even non-dart species occasionally get a burst of
	# energy if they are well-fed and healthy.
	if burst_remaining <= 0.0 and energy > 0.7 and hunger < 0.2 and randf() < dt * 0.05:
		burst_remaining = randf_range(0.3, 0.6)
		var ang: float = randf() * TAU
		heading_offset = Vector3(sin(ang), randf_range(-0.4, 0.6), cos(ang)) * 1.5

	# Mild wander via personal heading offset, scaled by wander_strength so
	# meanderers wander more, hoverers wander less. During startle propagation,
	# force the heading to the shared school direction.
	if _startle_remaining > 0.0:
		desired += _startle_heading * effective_max * 0.8
	else:
		desired += heading_offset * 0.5 * wander_strength

	# Diurnal / nocturnal / crepuscular activity. The generic "everyone slows
	# at night" was wrong - real freshwater fish split by activity period.
	# Each swim_pattern picks a different scaling of day-vs-night activity:
	#   shuffle   nocturnal   - cory + loach are MOST active in the dark
	#   school    diurnal     - tetras + danios doze at night, blast at day
	#   shoal     diurnal     - guppies likewise
	#   dart      crepuscular - killifish peak at dawn / dusk
	#   cruise    crepuscular - betta patrols dawn / dusk most
	#   meander   diurnal-mild  - puffer slow either way
	#   hover     ambient     - angelfish steady throughout
	if sim != null:
		var dl: float = float(sim.daylight())  # 1=midday, 0=midnight
		# Crepuscular factor: peaks at 0.5 daylight (transitions), drops at
		# extremes. = 1 - (2*dl - 1)^2 maps to a smooth bell.
		var crep: float = 1.0 - pow(2.0 * dl - 1.0, 2.0)
		var activity: float = 1.0
		match swim_pattern:
			"shuffle":
				# Nocturnal: 1.0 at night, 0.35 at noon.
				activity = 0.35 + 0.65 * (1.0 - dl)
			"school", "shoal":
				# Diurnal: 1.0 at noon, 0.25 at midnight.
				activity = 0.25 + 0.75 * dl
			"dart", "cruise":
				# Crepuscular: peaks at dawn/dusk, dips at extremes.
				activity = 0.4 + 0.6 * crep
			"meander":
				# Mostly diurnal but mild range.
				activity = 0.5 + 0.4 * dl
			"hover":
				# Steady; just a small night dip.
				activity = 0.7 + 0.3 * dl
			_:
				activity = 0.3 + 0.7 * dl
		desired *= activity

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
	# Sifting fish (cory mid-graze) almost stop while the timer is active.
	var target_dir: Vector3 = heading
	var target_spd: float = 0.0
	if target_velocity.length_squared() > 0.0001:
		target_spd = target_velocity.length()
		target_dir = target_velocity.normalized()
	if _sift_timer > 0.0:
		target_spd *= 0.15

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
		# Sifting nose-down tilt. While _sift_timer > 0 we apply a pitch
		# rotation around X so the fish's head points down at the
		# substrate - the classic cory grazing pose. Lerp in + out for
		# smoothness; courtship-display males ALSO tilt slightly for the
		# parade swim.
		var pitch_target: float = 0.0
		if _sift_timer > 0.0:
			pitch_target = 0.55
		elif _courtship_flare:
			pitch_target = -0.12   # nose slightly up for the parade swim
		_bank_pivot.rotation.x = lerpf(_bank_pivot.rotation.x, pitch_target,
			clampf(dt * 4.0, 0.0, 1.0))

	# ---- Swim animation ----
	# Tail wag scales with speed. Hovering fish pulse slowly, dashing fast.
	# Independent fin pivots add full-body life: pectoral fins flutter at a
	# faster frequency offset by 90 degrees for left/right (rowing motion),
	# dorsal/anal fins sway gently with the body's counter-wag.
	# Courtship-display fish wag faster + flare wider so the dance reads.
	var wag_freq: float = 2.5 + speed * 5.5
	var wag_amp_extra: float = 0.0
	if _courtship_flare:
		wag_freq *= 1.4
		wag_amp_extra = 0.25
	_swim_phase += dt * wag_freq
	if _tail_pivot != null:
		_tail_pivot.rotation.y = sin(_swim_phase) * (0.35 + wag_amp_extra \
			+ minf(speed * 0.18, 0.25))
	if _body_mid_pivot != null:
		_body_mid_pivot.rotation.y = -sin(_swim_phase) * (0.10 + wag_amp_extra * 0.4)
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
	var best_d2: float = max_dist * max_dist
	for p in plants:
		if not is_instance_valid(p) or p.biomass() <= 0:
			continue
		var top_pos: Vector3 = (p as Plant).global_position
		top_pos.y = (p as Plant).top_world_y()
		var d2: float = top_pos.distance_squared_to(position)
		if d2 < best_d2:
			best_d2 = d2
			best = p
	return best


func _find_nearest_tall_plant(plants: Array, max_dist: float, min_biomass: int) -> Plant:
	# Fish only nibble plants that are at least min_biomass voxels tall.
	# Spares saplings + carpets.
	var best: Plant = null
	var best_d2: float = max_dist * max_dist
	for p in plants:
		if not is_instance_valid(p) or p.biomass() < min_biomass:
			continue
		var top_pos: Vector3 = (p as Plant).global_position
		top_pos.y = (p as Plant).top_world_y()
		var d2: float = top_pos.distance_squared_to(position)
		if d2 < best_d2:
			best_d2 = d2
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
	var new_depth: float = clampf(
		(body_depth_factor + partner.body_depth_factor) * 0.5 + randf_range(-0.10, 0.10),
		0.7, 1.4)
	var new_head: float = clampf(
		(head_proportion + partner.head_proportion) * 0.5 + randf_range(-0.08, 0.08),
		0.7, 1.3)
	var new_dorsal: float = clampf(
		(dorsal_height_factor + partner.dorsal_height_factor) * 0.5 + randf_range(-0.12, 0.12),
		0.6, 1.6)
	var new_fork: float = clampf(
		(tail_fork_depth + partner.tail_fork_depth) * 0.5 + randf_range(-0.10, 0.10),
		0.5, 1.5)
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
		# Tail color inherits like the others if either parent had one set.
		"tail_color": (tail_color if _tail_color_set else accent_color).lerp(
			partner.tail_color if partner._tail_color_set else partner.accent_color,
			mix).lerp(Color(randf(), randf(), randf()), color_muta * 0.5),
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
		"body_depth_factor": new_depth,
		"head_proportion": new_head,
		"dorsal_height_factor": new_dorsal,
		"tail_fork_depth": new_fork,
		"pattern_type": new_pattern,
		"color_dot_count": new_dots,
		# Swim pattern + territory inheritance. Pattern usually stays in the
		# lineage; ~5% chance a fry tries a different niche. home_x/z drift
		# from the midpoint of the parents so siblings spread radially,
		# colonising different parts of the tank over generations.
		"swim_pattern": (swim_pattern if randf() < 0.95 else partner.swim_pattern),
		"home_x": clampf((home_x + partner.home_x) * 0.5 + randf_range(-2.0, 2.0),
			-10.0, 10.0),
		"home_y": clampf((home_y + partner.home_y) * 0.5 + randf_range(-0.4, 0.4),
			0.5, 7.5),
		"home_y_radius": clampf((home_y_radius + partner.home_y_radius) * 0.5
			+ randf_range(-0.12, 0.12), 0.3, 2.5),
		"home_z": clampf((home_z + partner.home_z) * 0.5 + randf_range(-2.0, 2.0),
			-8.0, 8.0),
		"home_radius": clampf((home_radius + partner.home_radius) * 0.5
			+ randf_range(-0.4, 0.4), 0.6, 7.0),
		"wander_strength": clampf((wander_strength + partner.wander_strength) * 0.5
			+ randf_range(-0.15, 0.15), 0.2, 2.0),
		"dart_chance": clampf((dart_chance + partner.dart_chance) * 0.5
			+ randf_range(-0.005, 0.005), 0.0, 0.08),
		"dart_speed_mult": clampf((dart_speed_mult + partner.dart_speed_mult) * 0.5
			+ randf_range(-0.10, 0.10), 1.0, 2.5),
		# Skeleton phenotype inheritance. Most params drift continuously;
		# the booleans (barbels, armor) flip at ~3% mutation rate so lineages
		# can occasionally lose / gain those features (driven speciation).
		"has_barbels": (has_barbels if randf() < 0.97
			else (partner.has_barbels if randf() < 0.5 else not has_barbels)),
		"armor_plates": (armor_plates if randf() < 0.97
			else (partner.armor_plates if randf() < 0.5 else not armor_plates)),
		"mouth_orientation": (mouth_orientation if randf() < 0.93
			else partner.mouth_orientation if randf() < 0.5
			else clampi(mouth_orientation + (1 if randf() < 0.5 else -1), -1, 1)),
		"tail_shape": (tail_shape if randf() < 0.94
			else partner.tail_shape if randf() < 0.5
			else randi() % 4),
		"eye_size_factor": clampf((eye_size_factor + partner.eye_size_factor) * 0.5
			+ randf_range(-0.10, 0.10), 0.55, 1.7),
		"ventral_profile": clampf((ventral_profile + partner.ventral_profile) * 0.5
			+ randf_range(-0.08, 0.08), 0.55, 1.7),
		"back_arch": clampf((back_arch + partner.back_arch) * 0.5
			+ randf_range(-0.08, 0.08), 0.65, 1.6),
		# Food preferences inherited as-is (species-defining, not really mutable).
		"snail_predator": snail_predator,
		"algae_grazer": algae_grazer,
	}
	return g
