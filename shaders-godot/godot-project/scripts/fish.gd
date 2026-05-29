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

# ---- Food reward tuning ----
# Hunger drop and energy gain per bite. FOOD_* applies to high-quality food
# pellets (kind == 3); WASTE_* applies to scavenged regular waste particles.
const FOOD_HUNGER_DELTA: float = 0.50
const FOOD_ENERGY_DELTA: float = 0.25
const WASTE_HUNGER_DELTA: float = 0.25
const WASTE_ENERGY_DELTA: float = 0.06
# Eating high-quality food rewinds age by this fraction of max_age_s ("back to life").
const FOOD_AGE_REVIVAL_FRAC: float = 0.08
# OmniLight3D energy applied to the food-glow halo on a food bite.
const FOOD_GLOW_ENERGY: float = 2.0

# Dissolved-O₂ threshold below which fish swim to the surface to gulp
# atmospheric oxygen. Real-world threshold for most freshwater species is
# ~3 mg/L (about 35% saturation); we use 0.45 (45% of saturated 1.0) so
# the visible response kicks in before fish actually start dying — the
# behavior is meant to read as "something's wrong, look at your aerator".
const SURFACE_GULP_O2: float = 0.45
# Stress threshold above which fish actively seek plant cover to hide.
# Real fish under chronic stress (pheromones, predators, water-quality
# spikes) retreat to shaded foliage; the response sells the "tank in
# distress" reading without needing a separate calm/scared animation.
const STRESS_HIDE_THRESHOLD: float = 0.65
# Every successful meal (waste, algae, plant nibble, predation) rewinds
# the fish's age by this fraction of max_age_s. Stacks with the larger
# FOOD_AGE_REVIVAL_FRAC bonus on auto-feeder pellets. Result: well-fed
# fish live well past max_age_s; starving fish hit senescence on schedule.
const MEAL_AGE_REDUCTION_FRAC: float = 0.012

# Behavior modes - what the fish is doing right now. Visible in the HUD if we
# add per-fish debug labels.
enum Mode { CRUISE, FORAGE, COURT, SPAWN, FLEE, REST }

# ---- Genome (set at spawn, immutable for this individual) ----
var species: String = "glassdart"
var subspecies_id: String = ""
var base_color: Color = Color8(195, 59, 59)
var accent_color: Color = Color8(230, 201, 42)
# Tail tint - a SEPARATE bright color zone applied to the tail fin voxels
# instead of falling back to a darkened base_color. This is what gives male
# guppies their dramatic "dark body, brilliant red tail" silhouette. If
# the genome doesn't supply one, we derive it from accent_color at build
# time (no behavior change for older fish).
var tail_color: Color = Color8(0, 0, 0)
var _tail_color_set: bool = false
# Marking tint - a SECONDARY marking color zone, distinct from base/accent.
# Used by the two-tone lateral band (cardinal tetra blue-over-red), the
# rear-flank wedge (harlequin rasbora), the caudal eye-spot ring, and the
# gourami two-tone flank. If the genome doesn't supply one we fall back to
# accent_color at build time (no behavior change for fish without it).
var marking_color: Color = Color8(0, 0, 0)
var _marking_color_set: bool = false
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
var fish_name: String = ""
var parent_lineage: String = "Founders"


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

var _food_glow: OmniLight3D = null

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

# ---- Extended silhouette traits (heritable) ----
# These let species read as themselves at a glance:
#  - anal_fin_length_factor   matches dorsal_height_factor for angelfish /
#                             betta where the anal fin is a long trailing
#                             mirror of the dorsal. 0.5 = vestigial nub
#                             (default), 1.5+ = full trailing mirror.
#  - adipose_fin              small extra dorsal nub between dorsal + tail.
#                             Defines the tetra silhouette (and a few
#                             other catfish-relatives).
#  - snout_pointed            adds an extra forward voxel to the head so
#                             cichlid-style faces (angelfish) read as
#                             pointed instead of round-blunt.
#  - body_shape               coarse silhouette branch on top of the
#                             elongation / depth scalars:
#                               "fusiform"      torpedo (default)
#                               "compressed"    tall thin disc (angelfish)
#                               "globiform"     spherical (puffer)
#                               "anguilliform"  eel-like (loach)
var anal_fin_length_factor: float = 0.5
var adipose_fin: bool = false
var snout_pointed: bool = false
var body_shape: String = "fusiform"
# Swimming style. Derived from body_shape at init unless the genome
# overrides explicitly. Drives the per-frame animation amplitudes so
# different body silhouettes move in physically appropriate ways:
#   "subcarangiform"  Default. Rear half undulates, head stays mostly
#                     still. Tetras, danios, glassdarts, killifish.
#   "anguilliform"    Eel-like whole-body traveling wave from head to
#                     tail. Loaches, kuhlis, mudsifters.
#   "ostraciiform"    Rigid body, only the tail oscillates. Boxfish
#                     style — pufferfish in this sim.
#   "labriform"       Pectoral-fin rowing as the primary thrust;
#                     tail/body subdued. Reef tang / angelfish style
#                     where the laterally-compressed body relies on
#                     pec-fin strokes.
#   "thunniform"      Stiff body, narrow high-frequency tail. Tuna-
#                     style cruisers. Not assigned by default but
#                     available for custom genomes.
var locomotion_type: String = "subcarangiform"

# ---- Food preferences (per-species, not heritable) ----
# Walstad ecosystem wiring: which species hunt which prey beyond the
# generic boids brain. The fish brain checks these flags before deciding
# what to chase.
#   snail_predator   loach + puffer types preferentially target baby snails
#   shrimp_predator  niche that preferentially crops shrimp fry
#   algae_grazer     cory + small herbivores graze algae clusters
var snail_predator: bool = false
var shrimp_predator: bool = false
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
	if subspecies_id != "" and subspecies_id != species:
		var sid: String = _short_subspecies_tag(subspecies_id)
		if sid != "":
			tags.append(sid)
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

# Livebearer flag (genome-driven). Real guppies, mollies, platies are
# viviparous - females release free-swimming fry instead of laying eggs.
# sim_driver._lay_eggs branches on this so the breeding event skips the
# FishEgg pipeline and spawns juveniles directly at the mother.
var is_livebearer: bool = false

# Livebearer gestation state. After courtship completion, livebearer females
# don't release fry immediately — they enter a visible pregnancy period where
# the belly gradually swells (ventral_profile scaled up) before dropping fry.
# _gestation_progress 0.0 = not pregnant, 0.01..1.0 = gestating, >= 1.0 = birth.
# _gestation_genome caches the offspring genome (like shrimp.gravid_partner_genome).
var _gestation_progress: float = 0.0
var _gestation_genome: Dictionary = {}
const GESTATION_DURATION: float = 25.0  # sim seconds of visible pregnancy

# Clutch guarding flag (genome-driven). Species that guard their eggs after
# spawning (angelfish, corydoras, killifish). When true, both parents enter
# brooding mode after laying eggs, even if they aren't "hover" pattern.
var guards_clutch: bool = false

# Sterile flag (genome-driven). When true, any offspring produced by this
# fish are marked non-viable (eggs dissolve instead of hatching). Used for
# hybrid crosses and genetic realism.
var sterile: bool = false

# Egg-guarding / brooding state. Set on both parents post-spawn for
# pair-bonding species (currently swim_pattern == "hover": angelfish).
# While brooding_remaining > 0 the fish hovers near brooding_at and
# chases the nearest non-partner intruder within range.
var brooding_at: Vector3 = Vector3.ZERO
var brooding_remaining: float = 0.0
const BROODING_DURATION: float = 90.0    # ~1.5 sim minutes of guarding
const BROODING_DURATION_LIGHT: float = 45.0  # lighter guarding for non-hover species
const BROODING_RADIUS: float = 1.2       # how far intruders trip a chase

# Burst mode: when fleeing or chasing food, fish can momentarily exceed
# max_speed by burst_multiplier. Drains energy faster.
var burst_remaining: float = 0.0
# Flips to true while in MALE courtship display - drives the renderer to
# flare the tail wag and over-bank into the S-curve dance. Cleared
# automatically when courtship ends or the fish moves out of display
# range.
var _courtship_flare: bool = false
# Sync pulse window — true only during the final pre-spawn beats. Both
# fish puff up + flare in unison so the moment the eggs drop reads as
# its own visual event (rather than ambient swimming → eggs appearing).
var _courtship_sync: bool = false
# Independent phase for courtship body pulses so the "puff up" shimmer
# isn't locked to the swim-tail wag rhythm.
var _courtship_pulse_phase: float = 0.0
# Courtship intensity ramp (0.0 → 1.0 over COURT_DURATION). Drives the
# gradual ramping of S-curve dance amplitude, fin flare, and color
# saturation boost so the courtship BUILDS to a flash at the spawn moment
# rather than being an on/off display.
var _courtship_intensity: float = 0.0
var _courtship_color_active: bool = false
# Last quantized courtship saturation step actually pushed to the shader; lets
# the per-voxel albedo writes skip frames/substeps where the boost is unchanged.
var _last_courtship_color_step: int = -999
# Pheromone trail: GPUParticles3D that trails a receptive female to
# visually signal she's in heat. Created on demand, freed when she's
# no longer receptive.
var _pheromone_trail: GPUParticles3D = null
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
var size_potential: float = 1.0
var jaw_claw_size: float = 0.0

# Visible phenotypes - heritable traits affecting body proportions + pattern.
# Drift over generations and create lineages that look distinct.
var fin_length_factor: float = 1.0   # multiplier on tail / dorsal / anal fin extent (0.6-1.6)
var body_elongation: float = 1.0     # body length stretch factor (0.85-1.15)
var body_depth_factor: float = 1.0   # body height stretch factor (0.7-1.4) - puffer vs minnow
var head_proportion: float = 1.0     # head size relative to body (0.7-1.3)
var dorsal_height_factor: float = 1.0  # dorsal fin height multiplier (0.6-1.6)
var tail_fork_depth: float = 1.0     # how spread the top/bottom prongs are (0.5-1.5)
var pattern_type: int = 1            # 0=solid, 1=lateral stripe, 2=spots, 3=vertical bars,
									 # 4=two-tone band (tetra), 5=rear-flank wedge (rasbora)
var color_dot_count: int = 0         # extra accent dots (0-4)
# Ornamentation flags / factors (heritable; render-only beyond the breather).
var bar_edged: bool = false          # crisp dark-edged vertical bars (clownfish/angelfish)
var eye_spot: bool = false           # caudal ocellus near the tail base
var ventral_feelers: bool = false    # gourami pelvic feeler threads
var finnage: float = 1.0             # fin elaboration multiplier (>1 = flowing veil, betta)
var labyrinth_breather: bool = false # anabantid periodic surface-gulp mannerism
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
var _head_pivot: Node3D = null
var _dorsal_pivot: Node3D = null
var _pec_left_pivot: Node3D = null
var _pec_right_pivot: Node3D = null
var _anal_pivot: Node3D = null
var _swim_phase: float = 0.0
var _last_yaw: float = 0.0
var _bank: float = 0.0
# Eye-saccade state. Drives a brief micro-yaw on _head_pivot when the
# fish is at rest. Tick-counted timer + a decaying target angle so the
# twitch reads as a "glance" rather than a sustained head-turn. Each
# fish's saccade is independently timed so the school doesn't twitch
# in sync.
var _saccade_t: float = 0.0
var _saccade_target: float = 0.0
# Wander refresh: periodically rotate heading_offset to a new random
# direction so the fish explores different patrol paths around its home.
# Without this, solo/low-schooling fish (betta, angelfish) repeat the
# same tight orbit forever because heading_offset is set once at _ready.
var _wander_refresh_timer: float = 0.0
# Home-drift timer: bottom-dwellers and solo fish periodically shift their
# home_x/home_z within the tank so they roam new territory. Real kuhli
# loaches explore the entire bottom over hours; bettas patrol different
# corners. Timer counts down, refreshes to a random interval.
var _home_drift_timer: float = 0.0

# Heading + speed motion model (separates direction from magnitude). Real
# fish accelerate forward via tail thrust and steer via slow heading changes,
# they can't slide sideways. This gives us proper momentum + turn-radius.
var heading: Vector3 = Vector3.FORWARD  # unit vector, faces -Z initially
var speed: float = 0.0
var max_turn_rate: float = 2.6   # radians/sec - how fast the fish can yaw
var linear_accel: float = 2.5    # units/sec^2 - how fast speed changes

# Death animation state. When a die event fires (old age / starvation), we
# don't queue_free immediately — we set _dying so the fish drifts sideways,
# tilts onto its flank, sinks, and fades over DEATH_DURATION before the
# sim_driver actually frees it and drops the mulm waste particle. Predator
# kills bypass this (the kill_prey event still frees instantly so it reads
# as eaten rather than dying of natural causes).
var _dying: bool = false
var _dying_timer: float = 0.0
const DEATH_DURATION: float = 3.5

# Cached list of all MeshInstance3D descendants. Built once at the end of
# _build_body() and reused by aging tint, maturity color, courtship color
# boost, and restoration — avoids a recursive DFS tree walk every time.
var _cached_meshes: Array = []

# ---- Refs ----
var sim: Node = null

# ---- Save/load ----
# Stable cross-session id minted by SimDriver. Used to resolve partner / target
# refs after a load. Empty string means "not yet assigned" — first save will
# fill it.
var id: String = ""
# Cached original genome dict that was passed to init_genome. We re-apply this
# on restore so dimorphic transformations + body_shape derivations run again
# from the same starting point (saving the post-transformation fields and
# replaying init_genome on them would double-transform).
var _saved_genome: Dictionary = {}


# Public accessor for the cached genome dict. SpeciesLibrary reads this on
# registration to record discoveries; we return a deep copy so the library
# can serialise it without our mutations leaking back in.
func get_saved_genome() -> Dictionary:
	return _saved_genome.duplicate(true)


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
	
	_food_glow = OmniLight3D.new()
	_food_glow.light_color = Color.WHITE
	_food_glow.light_energy = 0.0
	_food_glow.omni_range = 1.8
	_food_glow.omni_attenuation = 2.0
	add_child(_food_glow)


# ---- Setup ----

# Coerce a genome color value to a Color regardless of how it arrived. Breeding
# produces Colors, save/load round-trips through Arrays, but a genome that has
# passed through JSON.stringify comes back with colors as the string "(r, g, b, a)"
# — assigning that straight to a typed Color field throws "Invalid color name"
# on every hatch and floods the remote debugger. This accepts Color, [r,g,b,a],
# or that stringified form and falls back cleanly.
static func _coerce_color(v: Variant, fallback: Color) -> Color:
	if v is Color:
		return v
	if v is Array and (v as Array).size() >= 3:
		var arr: Array = v
		var aa: float = float(arr[3]) if arr.size() >= 4 else 1.0
		return Color(float(arr[0]), float(arr[1]), float(arr[2]), aa)
	if v is String:
		var s: String = (v as String).strip_edges()
		if s.begins_with("(") and s.ends_with(")"):
			var parts: PackedStringArray = s.substr(1, s.length() - 2).split(",")
			if parts.size() >= 3:
				var sa: float = parts[3].to_float() if parts.size() >= 4 else 1.0
				return Color(parts[0].to_float(), parts[1].to_float(), parts[2].to_float(), sa)
		if Color.html_is_valid(s):
			return Color.html(s)
	return fallback


func init_genome(genome: Dictionary) -> void:
	# Cache the genome that built this fish so we can replay init_genome on
	# load. We duplicate(true) so later mutation by the caller doesn't reach
	# back into our cached copy.
	_saved_genome = genome.duplicate(true)
	if not _saved_genome.has("organism_type"):
		_saved_genome["organism_type"] = "fish"
	# mixed_morphs (reef tank): each individual rolls a fresh tropical
	# colour + body + pattern + tail combo at spawn so a single species
	# entry produces a school that reads as a mixed reef community
	# (clownfish, tang, chromis, anthias, etc.). Applied BEFORE color
	# extraction so the rolled values land in the genome dict that the
	# rest of init_genome reads from.
	if bool(genome.get("mixed_morphs", false)):
		_apply_mixed_morph_jitter(genome)
		# Re-cache after jitter so the post-jitter genome (specific colour /
		# body roll for THIS fish) is what we replay on restore.
		_saved_genome = genome.duplicate(true)
	species = genome.get("species", species)
	subspecies_id = String(genome.get("subspecies_id", species))
	if subspecies_id == "":
		subspecies_id = species
	base_color = _coerce_color(genome.get("base_color", base_color), base_color)
	accent_color = _coerce_color(genome.get("accent_color", accent_color), accent_color)
	if genome.has("tail_color"):
		tail_color = _coerce_color(genome["tail_color"], tail_color)
		_tail_color_set = true
	if genome.has("marking_color"):
		marking_color = _coerce_color(genome["marking_color"], marking_color)
		_marking_color_set = true
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
	
	fish_name = genome.get("fish_name", "")
	if fish_name == "":
		if genome.has("_display_name"):
			fish_name = String(genome["_display_name"])
		else:
			var adjs := ["Neon", "Crimson", "Lazuli", "Sunlit", "Twilight", "Lunar", "Ember", "Coral", "Frost", "Onyx", "Citrine", "Verdant", "Pearl", "Mirage"]
			var nouns := ["Darter", "Glider", "Nibbler", "Shimmer", "Spike", "Wisp", "Crest", "Tang", "Sprite", "Slip", "Drake", "Veil", "Mote", "Lance"]
			fish_name = "%s %s" % [adjs[randi() % adjs.size()], nouns[randi() % nouns.size()]]
	parent_lineage = genome.get("parent_lineage", "Founders")
	
	_saved_genome["fish_name"] = fish_name
	_saved_genome["parent_lineage"] = parent_lineage
	_saved_genome["generation"] = generation
	_saved_genome["subspecies_id"] = subspecies_id

	fin_length_factor = genome.get("fin_length_factor", fin_length_factor)
	body_elongation = genome.get("body_elongation", body_elongation)
	body_depth_factor = genome.get("body_depth_factor", body_depth_factor)
	head_proportion = genome.get("head_proportion", head_proportion)
	dorsal_height_factor = genome.get("dorsal_height_factor", dorsal_height_factor)
	tail_fork_depth = genome.get("tail_fork_depth", tail_fork_depth)
	pattern_type = int(genome.get("pattern_type", pattern_type))
	color_dot_count = int(genome.get("color_dot_count", color_dot_count))
	# Ornamentation phenotypes.
	bar_edged = bool(genome.get("bar_edged", bar_edged))
	eye_spot = bool(genome.get("eye_spot", eye_spot))
	ventral_feelers = bool(genome.get("ventral_feelers", ventral_feelers))
	finnage = float(genome.get("finnage", finnage))
	labyrinth_breather = bool(genome.get("labyrinth_breather", labyrinth_breather))
	# Body skeleton phenotypes (heritable - drift in produce_offspring_genome).
	has_barbels = bool(genome.get("has_barbels", has_barbels))
	mouth_orientation = int(genome.get("mouth_orientation", mouth_orientation))
	eye_size_factor = float(genome.get("eye_size_factor", eye_size_factor))
	ventral_profile = float(genome.get("ventral_profile", ventral_profile))
	back_arch = float(genome.get("back_arch", back_arch))
	tail_shape = int(genome.get("tail_shape", tail_shape))
	armor_plates = bool(genome.get("armor_plates", armor_plates))
	is_livebearer = bool(genome.get("is_livebearer", is_livebearer))
	guards_clutch = bool(genome.get("guards_clutch", guards_clutch))
	sterile = bool(genome.get("sterile", sterile))
	anal_fin_length_factor = float(genome.get("anal_fin_length_factor",
		anal_fin_length_factor))
	adipose_fin = bool(genome.get("adipose_fin", adipose_fin))
	snout_pointed = bool(genome.get("snout_pointed", snout_pointed))
	body_shape = String(genome.get("body_shape", body_shape))
	size_potential = clampf(float(genome.get("size_potential", size_potential)), 0.6, 2.4)
	jaw_claw_size = clampf(float(genome.get("jaw_claw_size", jaw_claw_size)), 0.0, 1.2)
	var inherited_max_growth: float = float(genome.get("max_growth", max_growth))
	var size_potential_t: float = clampf((size_potential - 0.6) / 1.8, 0.0, 1.0)
	max_growth = clampf(
		inherited_max_growth * lerpf(0.82, 1.45, size_potential_t),
		1.05, 2.8)
	# Sexual dimorphism. Must run AFTER all genome.get reads above — earlier
	# the block sat before the genome reads, so any female overrides to
	# fin_length_factor / body_depth_factor / dorsal_height_factor /
	# ventral_profile got immediately stomped by the subsequent
	# `genome.get(...)` calls and every female rendered as a male. The block
	# now correctly applies on top of the final genome-resolved values.
	# Drift-through-generations still works because the underlying stored
	# values are shared at the genome level.
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
	# Locomotion derives from body_shape unless explicitly overridden in
	# the genome. The match expresses the real-world correlation between
	# a fish's silhouette and how it produces thrust.
	if genome.has("locomotion_type"):
		locomotion_type = String(genome["locomotion_type"])
	else:
		match body_shape:
			"anguilliform":
				locomotion_type = "anguilliform"
			"globiform":
				locomotion_type = "ostraciiform"
			"compressed":
				locomotion_type = "labriform"
			_:
				locomotion_type = "subcarangiform"
	# Food preferences (species-level, not heritable).
	snail_predator = bool(genome.get("snail_predator", snail_predator))
	shrimp_predator = bool(genome.get("shrimp_predator", shrimp_predator))
	_apply_predator_morphology()
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
	max_turn_rate = float(genome.get("max_turn_rate", max_turn_rate))
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
	max_turn_rate = 2.6 # default reset
	match swim_pattern:
		"school":
			home_radius = 2.5
			wander_strength = 1.0
			dart_chance = 0.005
			max_turn_rate = 2.6
		"shoal":
			home_radius = 4.5
			wander_strength = 1.3
			dart_chance = 0.01
			max_turn_rate = 2.5
		"dart":
			home_radius = 3.0
			wander_strength = 0.7
			dart_chance = 0.045
			dart_speed_mult = 1.9
			max_turn_rate = 3.2
		"hover":
			home_radius = 2.2 # increased from 0.9 for wider, more natural hovering area
			wander_strength = 0.35
			dart_chance = 0.002
			max_turn_rate = 1.1 # slow, elegant centerpiece turns
		"cruise":
			home_radius = 6.0
			wander_strength = 0.55
			dart_chance = 0.003
			max_turn_rate = 1.8
		"meander":
			home_radius = 3.5
			wander_strength = 1.5
			dart_chance = 0.0
			max_turn_rate = 1.5
		"shuffle":
			home_radius = 5.0
			wander_strength = 1.2
			dart_chance = 0.012
			dart_speed_mult = 1.4
			max_turn_rate = 2.2


func _apply_predator_morphology() -> void:
	# Predator niches nudge visible morphology so predator lineages diverge
	# from grazing/generalist branches in a way the player can spot quickly.
	if not snail_predator and not shrimp_predator:
		return
	if snail_predator:
		mouth_orientation = clampi(maxi(mouth_orientation, 0), -1, 1)
		snout_pointed = true
		head_proportion = clampf(head_proportion * 1.08, 0.7, 1.5)
		body_depth_factor = clampf(body_depth_factor * 1.06, 0.7, 1.6)
		jaw_claw_size = clampf(jaw_claw_size + 0.16, 0.0, 1.2)
		if body_shape == "fusiform":
			body_shape = "anguilliform"
	if shrimp_predator:
		mouth_orientation = clampi(mini(mouth_orientation, 0), -1, 1)
		eye_size_factor = clampf(eye_size_factor * 1.05, 0.55, 1.8)
		body_elongation = clampf(body_elongation * 1.05, 0.85, 1.4)
		jaw_claw_size = clampf(jaw_claw_size + 0.12, 0.0, 1.2)
		if not snail_predator and body_shape == "compressed":
			body_shape = "fusiform"
	if snail_predator and shrimp_predator:
		body_shape = "globiform"
		armor_plates = true
		jaw_claw_size = clampf(jaw_claw_size + 0.20, 0.0, 1.2)


func _maturity_scale() -> float:
	match maturity:
		MATURITY_FRY:        return 0.35
		MATURITY_JUVENILE:   return 0.65
		MATURITY_ADULT:      return 1.0
		MATURITY_SENESCENT:  return 0.95
		_: return 1.0


# Mixed-morph spawn: when a reef-style species has mixed_morphs=true,
# this overwrites the genome's color + shape keys with a randomly-rolled
# tropical combination so each individual reads as a different species
# of reef fish even though they share one library entry. Mutates `genome`
# in place; init_genome reads the post-mutation values below.
func _apply_mixed_morph_jitter(genome: Dictionary) -> void:
	# Curated tropical color palette - inspired by clownfish, tangs,
	# chromis, anthias, royal grammas. Each entry is (base, accent).
	# Accent is the contrasting bar / lateral stripe color.
	var palettes: Array = [
		[Color8(245, 110, 30), Color8(255, 255, 255)],  # clownfish orange + white
		[Color8(255, 215, 40), Color8(45, 35, 25)],     # yellow tang + dark mask
		[Color8(35, 95, 220), Color8(255, 230, 30)],    # blue tang + yellow tail
		[Color8(60, 170, 215), Color8(245, 245, 245)],  # chromis blue-cyan + white
		[Color8(230, 70, 130), Color8(255, 235, 90)],   # anthias pink + amber
		[Color8(110, 60, 180), Color8(255, 220, 70)],   # royal gramma purple + yellow
		[Color8(245, 245, 245), Color8(35, 35, 50)],    # damselfish pearl + black
		[Color8(220, 60, 50), Color8(255, 245, 180)],   # squirrelfish red + cream
		[Color8(40, 80, 60), Color8(255, 200, 90)],     # moorish idol dark + yellow
	]
	var palette_idx: int = randi() % palettes.size()
	var p: Array = palettes[palette_idx]
	genome["base_color"] = p[0]
	genome["accent_color"] = p[1]
	# The accent doubles as marking_color so morph patterns (two-tone band,
	# rear wedge, edged bars) read in the morph's own contrasting hue.
	genome["marking_color"] = p[1]
	# Tail color: 50/50 chance to be a third contrasting hue or match
	# accent. Real reef fish often have a bright tail flash.
	if randf() < 0.5:
		genome["tail_color"] = p[1]
	else:
		genome["tail_color"] = Color(randf(), randf() * 0.6 + 0.3, randf())
	# Body shape: most reef fish are compressed (laterally flat) like
	# tangs / angelfish. Smaller chance of fusiform (anthias / chromis).
	genome["body_shape"] = "compressed" if randf() < 0.65 else "fusiform"
	# Pattern: random pick. Vertical bars (clownfish, damselfish),
	# horizontal stripes, spots, or solid. The clownfish palette (index 0)
	# is forced to crisp edged white vertical bars - the unmistakable
	# Amphiprion look - rather than a random pattern.
	if palette_idx == 0:
		genome["pattern_type"] = 3
		genome["bar_edged"] = true
	else:
		genome["pattern_type"] = randi() % 4
		genome["bar_edged"] = randf() < 0.25
	# Tail shape: square paddle (tang / chromis), fan (anthias), or
	# forked (chromis); avoid lyre (cichlid).
	genome["tail_shape"] = [0, 1, 3][randi() % 3]
	# Skeletal variation. Body depth + elongation jitter heavy so some
	# reef morphs read as nearly-disc tang while others read as torpedo.
	genome["body_elongation"] = randf_range(0.78, 1.20)
	genome["body_depth_factor"] = randf_range(0.95, 1.65)
	genome["fin_length_factor"] = randf_range(0.7, 1.4)
	genome["dorsal_height_factor"] = randf_range(0.7, 1.4)
	genome["size_potential"] = randf_range(0.8, 2.2)
	genome["jaw_claw_size"] = randf_range(0.0, 0.9)
	# Anal fin matches dorsal-ish for the symmetric tang look.
	genome["anal_fin_length_factor"] = randf_range(0.5, 1.5)
	# Random dot count (some morphs have peppered flanks).
	genome["color_dot_count"] = randi_range(0, 4)
	# Preferred Y as a FRACTION of the actual water column (0=substrate,
	# 1=surface). World.gd's _apply_water_column_scale converts this to
	# absolute Y at spawn based on the tank's real dimensions, so the
	# reef school spans the full column whether the tank is 5 units or
	# 15 units tall. Range 0.10..0.90 keeps every fish well inside the
	# water and gives the school maximum vertical diversity.
	genome["preferred_y_frac"] = randf_range(0.10, 0.90)
	# Reef fish are less territorially layered than freshwater
	# schoolers - they cruise more of the column. Give each one a
	# bigger vertical wander radius (25% of column, scaled in world).
	genome["home_y_radius"] = 1.25  # interpreted as 25% of ref column = 1.25
	# Trophic niche: roughly 30% of the school rolls polyp-grazer (high
	# herbivory like butterflyfish / tangs - actively nibble corals once
	# they're large enough). The other 70% read as planktivores /
	# carnivores: low herbivory, swim past corals without biting. This
	# gives the reef a believable mix where most fish ignore corals and
	# only a few specialists eat them - matching real reef behaviour.
	if randf() < 0.30:
		genome["herbivory"] = randf_range(0.65, 0.90)
	else:
		genome["herbivory"] = randf_range(0.05, 0.25)


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
	# Marking material: the secondary ornament color zone (tetra blue band,
	# rasbora rear wedge, gourami flank, eye-spot ring). Falls back to accent
	# when the genome supplies no explicit marking_color.
	var effective_marking: Color = marking_color if _marking_color_set \
		else accent_color
	var mat_marking := _make_mat(effective_marking)

	_bank_pivot = Node3D.new()
	_bank_pivot.name = "BankPivot"
	add_child(_bank_pivot)

	# ---- HEAD (animatable via _head_pivot) ----
	# head_proportion scales the head's overall size relative to the body,
	# so small-headed minnow types contrast against big-headed cichlids.
	# Anguilliform locomotion drives _head_pivot.rotation.y through a
	# head-leading sine wave so the whole body undulates head-to-tail.
	# Pivot stays at the bank_pivot origin; head voxels are 2.5v ahead,
	# so a small Y rotation makes the head swing laterally — exactly
	# the eel head-shake motion.
	var hp: float = head_proportion
	_head_pivot = Node3D.new()
	_head_pivot.name = "Head"
	_bank_pivot.add_child(_head_pivot)
	var head: Node3D = _head_pivot
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
	if jaw_claw_size > 0.08:
		var mat_claw := _make_mat(base_color.darkened(0.35).lerp(accent_color, 0.22))
		var hook_len: float = v * (0.12 + jaw_claw_size * 0.28) * hp
		var hook_thickness: float = v * (0.05 + jaw_claw_size * 0.06) * hp
		var hook_span: float = v * (0.18 + jaw_claw_size * 0.10) * hp
		for side in [-1.0, 1.0]:
			_add_voxel_to(head, Vector3(side * hook_span, mouth_y - v * 0.02, -3.12 * v),
				Vector3(hook_thickness, hook_thickness, hook_len), mat_claw)
			_add_voxel_to(head, Vector3(side * hook_span * 0.78, mouth_y - v * 0.10, -3.00 * v),
				Vector3(hook_thickness * 0.9, hook_thickness * 0.9, hook_len * 0.55), mat_claw)
	# Pointed snout: cichlid-style face (angelfish). Adds a slim forward
	# voxel ahead of the mouth so the profile reads as wedge / pointed
	# instead of blunt-round. Skipped for blunt species (puffer, cory).
	if snout_pointed:
		_add_voxel_to(head, Vector3(0, mouth_y * 0.4, -3.35 * v),
			Vector3(v * 0.32 * hp, v * 0.35 * hp, v * 0.45 * hp), mat_body)
		# Upper jaw highlight - lighter top of the snout reads as the
		# forehead carrying forward.
		_add_voxel_to(head, Vector3(0, mouth_y * 0.4 + v * 0.18 * hp, -3.3 * v),
			Vector3(v * 0.22 * hp, v * 0.12 * hp, v * 0.35 * hp), mat_top)
	# Barbels - catfish/loach whiskers. Two pairs of tiny dark voxels under
	# the mouth, angled forward + down. Only drawn if has_barbels.
	if has_barbels:
		var mat_barbel := _make_mat(base_color.darkened(0.5))
		var barbel_y: float = -v * 0.45 * hp
		var barbel_z: float = -2.9 * v
		for x_side in [-0.30, -0.18, 0.18, 0.30]:
			_add_voxel_to(head, Vector3(x_side * v * hp, barbel_y, barbel_z),
				Vector3(v * 0.06, v * 0.08, v * 0.25), mat_barbel)
	# Predator specializations:
	# - snail_predator: thicker crusher jaw / head profile
	# - shrimp_predator: longer rostrum for pecking in tight cover
	if snail_predator:
		var mat_jaw := _make_mat(accent_color.lightened(0.08))
		_add_voxel_to(head, Vector3(0, mouth_y - v * 0.08, -3.02 * v),
			Vector3(v * 0.50 * hp, v * 0.24 * hp, v * 0.28 * hp), mat_jaw)
		_add_voxel_to(head, Vector3(0, mouth_y + v * 0.12, -2.98 * v),
			Vector3(v * 0.42 * hp, v * 0.14 * hp, v * 0.25 * hp), mat_jaw)
	if shrimp_predator:
		var mat_rostrum := _make_mat(base_color.lightened(0.20))
		_add_voxel_to(head, Vector3(0, mouth_y * 0.3, -3.45 * v),
			Vector3(v * 0.18 * hp, v * 0.16 * hp, v * 0.55 * hp), mat_rostrum)

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
	# Body-shape silhouette pass. Adds extra voxels ON TOP of the standard
	# seg_widths skeleton to push the silhouette into one of four classic
	# fish shapes:
	#   compressed   tall narrow disc (angelfish - vertical extension
	#                voxels above + below the body center)
	#   globiform    spherical (puffer - wraparound voxels filling out
	#                the front/rear hemispheres into a ball)
	#   anguilliform eel-like (loach - extra tail-ward filler so the
	#                long body reads continuous, not segmented)
	#   fusiform     default torpedo - no extras (do nothing)
	match body_shape:
		"compressed":
			# Disc body: stack tall thin voxels above and below the mid
			# segments. Combined with body_depth_factor >= 1.7 this
			# produces the angelfish's iconic flat silhouette.
			for i in seg_widths.size():
				var bw_c: float = seg_widths[i]
				var bz_c: float = i * v
				_add_voxel_to(_body_mid_pivot,
					Vector3(0, v * (0.85 * back_arch + 0.25), bz_c),
					Vector3(v * bw_c * 0.7, v * 0.6, v * 0.85), mat_top)
				_add_voxel_to(_body_mid_pivot,
					Vector3(0, -v * (0.85 * ventral_profile + 0.20), bz_c),
					Vector3(v * bw_c * 0.7, v * 0.55, v * 0.85), mat_belly)
		"globiform":
			# Sphere body: add front + rear cap voxels plus lateral
			# bulge voxels so the puffer reads round instead of as 3
			# stacked boxes.
			_add_voxel_to(_body_mid_pivot, Vector3(0, 0, -v * 0.8),
				Vector3(v * 1.35, v * 1.25, v * 0.9), mat_body)
			_add_voxel_to(_body_mid_pivot, Vector3(0, 0, v * 2.6),
				Vector3(v * 1.15, v * 1.05, v * 0.8), mat_body)
			# Top + bottom caps.
			_add_voxel_to(_body_mid_pivot, Vector3(0, v * 0.85, v * 1.0),
				Vector3(v * 1.1, v * 0.35, v * 1.7), mat_top)
			_add_voxel_to(_body_mid_pivot, Vector3(0, -v * 0.85, v * 1.0),
				Vector3(v * 1.1, v * 0.35, v * 1.7), mat_belly)
			# Lateral cheeks for that puffed-out width.
			_add_voxel_to(_body_mid_pivot, Vector3(v * 0.9, 0, v * 1.0),
				Vector3(v * 0.3, v * 1.0, v * 1.7), mat_body)
			_add_voxel_to(_body_mid_pivot, Vector3(-v * 0.9, 0, v * 1.0),
				Vector3(v * 0.3, v * 1.0, v * 1.7), mat_body)
		"anguilliform":
			# Eel-like: extend the body further rearward with two extra
			# tail-ward segments so the loach silhouette reads as a
			# continuous tube, not 3 boxes + a tail.
			_add_voxel_to(_body_mid_pivot, Vector3(0, 0, v * 3.2),
				Vector3(v * 0.85, v * 0.85, v), mat_body)
			_add_voxel_to(_body_mid_pivot, Vector3(0, 0, v * 4.2),
				Vector3(v * 0.7, v * 0.7, v), mat_body)
		_:
			pass  # fusiform - no extra voxels

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
	if snail_predator or shrimp_predator:
		var mat_pred := _make_mat(accent_color.lightened(0.18))
		var ridge_y: float = v * (0.52 if snail_predator else 0.42)
		for i in seg_widths.size():
			_add_voxel_to(_body_mid_pivot, Vector3(0, ridge_y, i * v),
				Vector3(v * 0.12, v * 0.12, v * 0.55), mat_pred)
	# Morphological elaboration from existing architecture genes:
	#   - long fins => trailing flank streamers
	#   - fast cruisers => caudal keels near peduncle
	#   - older lineages => dorsal ornament nubs
	if fin_length_factor > 1.15:
		var mat_stream := _make_mat(accent_color.lightened(0.10))
		var streamer_n: int = 1 + int(clampf((fin_length_factor - 1.15) * 2.0, 0.0, 2.0))
		for i in streamer_n:
			var zf: float = lerpf(0.1, 1.8, float(i) / float(maxi(1, streamer_n)))
			for x_side in [-1.0, 1.0]:
				_add_voxel_to(_body_mid_pivot, Vector3(x_side * v * 0.68, -v * 0.02, zf * v),
					Vector3(v * 0.06, v * 0.18, v * 0.55), mat_stream)
	if max_speed > 1.75 or dart_speed_mult > 1.85:
		var mat_keel := _make_mat(base_color.darkened(0.40))
		for x_side in [-1.0, 1.0]:
			_add_voxel_to(_body_mid_pivot, Vector3(x_side * v * 0.56, 0, v * 2.35),
				Vector3(v * 0.08, v * 0.32, v * 0.55), mat_keel)
	if generation >= 3 and dorsal_height_factor > 1.05:
		var mat_orn := _make_mat(accent_color.lightened(0.20))
		var ornament_n: int = clampi(1 + int(generation / 4), 1, 4)
		for i in ornament_n:
			var z: float = (0.25 + float(i) * 0.55) * v
			_add_voxel_to(_body_mid_pivot, Vector3(0, v * 0.95, z),
				Vector3(v * 0.08, v * 0.18, v * 0.16), mat_orn)
	# Lateral pattern - varies by pattern_type genotype.
	# 0 = solid (no accents), 1 = horizontal stripe, 2 = spots, 3 = vertical bars,
	# 4 = two-tone lateral band (tetra), 5 = rear-flank wedge (rasbora)
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
		# bar_edged adds a thin dark border voxel fore + aft of each bar so
		# the bars read crisp against a pale body (clownfish white bars with
		# black edging, angelfish black bars).
		var mat_bar_edge := _make_mat(base_color.darkened(0.55))
		for i in seg_widths.size():
			for x_side in [-1.0, 1.0]:
				_add_voxel_to(_body_mid_pivot, Vector3(x_side * v * 0.5, 0, i * v),
					Vector3(v * 0.15, v * 1.0, v * 0.25), mat_accent)
				if bar_edged:
					for zoff_edge in [-v * 0.22, v * 0.22]:
						_add_voxel_to(_body_mid_pivot,
							Vector3(x_side * v * 0.5, 0, i * v + zoff_edge),
							Vector3(v * 0.16, v * 1.02, v * 0.06), mat_bar_edge)
	elif pattern_type == 4:
		# Two-tone lateral band: the iconic cardinal/neon tetra look. A bright
		# marking_color stripe runs along the UPPER flank while a darker accent
		# shadow rides the LOWER flank, so the body reads split top/bottom.
		for i in seg_widths.size():
			for x_side in [-1.0, 1.0]:
				_add_voxel_to(_body_mid_pivot, Vector3(x_side * v * 0.5, v * 0.22, i * v),
					Vector3(v * 0.16, v * 0.42, v * 0.95), mat_marking)
				_add_voxel_to(_body_mid_pivot, Vector3(x_side * v * 0.5, -v * 0.28, i * v),
					Vector3(v * 0.15, v * 0.38, v * 0.95), mat_accent)
	elif pattern_type == 5:
		# Rear-flank wedge: harlequin rasbora black triangle. A marking_color
		# block over the rear two segments, tapering toward the tail.
		for i in range(1, seg_widths.size()):
			var wedge_h: float = v * (1.0 - 0.32 * float(i - 1))
			for x_side in [-1.0, 1.0]:
				_add_voxel_to(_body_mid_pivot,
					Vector3(x_side * v * 0.46, -v * 0.1, i * v + v * 0.2),
					Vector3(v * 0.16, wedge_h, v * 0.7), mat_marking)
	# Caudal eye-spot (ocellus): a ringed marking near the tail base. Many
	# cichlids + some tetras carry one as a false-eye predator deterrent.
	if eye_spot:
		var mat_ocellus_ring := _make_mat(base_color.darkened(0.6))
		for x_side in [-1.0, 1.0]:
			_add_voxel_to(_body_mid_pivot, Vector3(x_side * v * 0.5, v * 0.05, v * 2.35),
				Vector3(v * 0.16, v * 0.46, v * 0.46), mat_ocellus_ring)
			_add_voxel_to(_body_mid_pivot, Vector3(x_side * v * 0.52, v * 0.05, v * 2.35),
				Vector3(v * 0.14, v * 0.26, v * 0.26), mat_marking)
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
	# Anal fin (bottom). Default = small nub (anal_fin_length_factor < 1.0).
	# When the factor is high, build a long trailing fin that mirrors the
	# dorsal - this is what defines the angelfish + betta silhouette where
	# the dorsal and anal fins extend symmetrically into long fans.
	_anal_pivot = Node3D.new()
	_anal_pivot.name = "AnalPivot"
	_anal_pivot.position = Vector3(0, -v * 0.65, v * 1.6)
	_body_mid_pivot.add_child(_anal_pivot)
	var afl: float = anal_fin_length_factor
	_add_voxel_to(_anal_pivot, Vector3(0, -v * 0.2 * afl, 0),
		Vector3(v * 0.12, v * 0.35 * afl, v * 0.7), mat_fin)
	if afl >= 1.0:
		# Trailing voxels stretch BACK along Z, sweeping downward with the
		# magnitude of afl. Two segments give the fin a tapered profile.
		_add_voxel_to(_anal_pivot, Vector3(0, -v * 0.45 * afl, v * 0.3),
			Vector3(v * 0.11, v * 0.4 * afl, v * 0.65), mat_fin)
		_add_voxel_to(_anal_pivot, Vector3(0, -v * 0.85 * afl, v * 0.65),
			Vector3(v * 0.10, v * 0.45 * afl, v * 0.5), mat_fin)
	# Adipose fin: small lobe between dorsal and tail, on the dorsal line.
	# Defines the tetra silhouette (also present on catfish, salmonids,
	# corydoras relatives). Tiny - just a marker voxel.
	if adipose_fin:
		_add_voxel_to(_body_mid_pivot, Vector3(0, v * 0.72, v * 2.2),
			Vector3(v * 0.10, v * 0.25, v * 0.4), mat_fin)
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
	# Ventral feelers: gouramis (and other anabantids) have their pelvic fins
	# reduced to long thread-like "feelers" that trail well below the body.
	# Two slim voxel filaments hanging from the front belly, swept slightly
	# back. Tinted with the marking color so they read as a distinct feature.
	if ventral_feelers:
		var mat_feeler := _make_mat(effective_marking)
		for x_side in [-1.0, 1.0]:
			_add_voxel_to(_body_mid_pivot,
				Vector3(x_side * v * 0.18, -v * 0.95, -v * 0.1),
				Vector3(v * 0.06, v * 0.9, v * 0.08), mat_feeler)
			_add_voxel_to(_body_mid_pivot,
				Vector3(x_side * v * 0.18, -v * 1.6, v * 0.15),
				Vector3(v * 0.05, v * 0.75, v * 0.07), mat_feeler)

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
	# Finnage elaboration: flowing veil fins (betta / fancy livebearers). When
	# finnage > 1.0, append long trailing ray voxels to the caudal, dorsal and
	# anal fins so the silhouette reads as billowing drapery rather than a
	# tight functional tail.
	if finnage > 1.0:
		var veil: float = finnage
		var mat_veil := _make_mat(effective_tail)
		# Caudal veil streamers sweeping back well past the tail template.
		for ang in [-1.0, -0.4, 0.4, 1.0]:
			_add_voxel_to(_tail_pivot,
				Vector3(0, v * ang * 0.7 * veil, v * (1.6 * fl * veil)),
				Vector3(v * 0.11, v * (0.45 * veil), v * (0.9 * fl * veil)), mat_veil)
		_add_voxel_to(_tail_pivot,
			Vector3(0, 0, v * (2.3 * fl * veil)),
			Vector3(v * 0.10, v * (1.0 * veil), v * (0.7 * fl)), mat_veil)
		# Dorsal + anal veil trails (the sweeping top + bottom fans).
		if _dorsal_pivot != null:
			_add_voxel_to(_dorsal_pivot, Vector3(0, v * 0.75 * dorsal_height_factor, v * 0.7),
				Vector3(v * 0.10, v * (0.7 * veil), v * (1.1 * veil)), mat_veil)
		if _anal_pivot != null:
			_add_voxel_to(_anal_pivot, Vector3(0, -v * 0.7 * veil, v * 0.9),
				Vector3(v * 0.10, v * (0.7 * veil), v * (1.0 * veil)), mat_veil)
	# Apply body elongation + depth scaling. The bank pivot's local Y stretches
	# the body height (puffer = 1.4, minnow = 0.7), Z stretches length.
	if _bank_pivot != null:
		_bank_pivot.scale.z = body_elongation
		_bank_pivot.scale.y = body_depth_factor

	# Cache mesh list now that the body is fully built. All subsequent
	# tint / color operations read from _cached_meshes instead of
	# re-walking the node tree.
	_cached_meshes = _all_meshes(self)


func _add_voxel_to(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelMat.get_box(size)
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


func _make_mat(color: Color) -> ShaderMaterial:
	return VoxelMat.make(color)


func _add_voxel(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelMat.get_box(size)
	mi.position = pos
	mi.material_override = mat
	add_child(mi)


# ---- Tick (called by SimDriver) ----

func tick(dt: float, neighbors: Array, plants: Array, algae_array: Array, waste: Array,
		  baby_shrimp: Array, world_bounds: AABB) -> Dictionary:
	# Returns events for the SimDriver to act on (lay egg, eat waste,
	# kill prey, spawn waste, die).
	var events: Dictionary = {}

	# Dying fish are inert — no behavior, no events. _process handles the
	# sinking + fading animation and queue_free at the end of DEATH_DURATION.
	if _dying:
		return events

	age += dt
	# Hunger accumulates slowly. Real fish go days without eating; we keep
	# the rate gentle so fish can spend more time on courtship / schooling
	# / exploration than on frantic foraging. 0.006/s = ~165s from sated
	# to starvation if the fish never finds a bite (longer than most
	# fish lifespans, so starvation is a real but uncommon kill switch).
	hunger = clampf(hunger + dt * 0.006, 0.0, 1.0)
	var energy_drain := 0.004 + (0.04 if burst_remaining > 0.0 else 0.0)
	energy = clampf(energy - dt * energy_drain, 0.0, 1.0)
	burst_remaining = maxf(0.0, burst_remaining - dt)
	breed_cooldown = maxf(0.0, breed_cooldown - dt)
	nibble_cooldown = maxf(0.0, nibble_cooldown - dt)
	_startle_remaining = maxf(0.0, _startle_remaining - dt)

	# Gestation progress (livebearer females only)
	if is_livebearer and sex == 1 and _gestation_progress > 0.0:
		_gestation_progress += dt / GESTATION_DURATION
		if _gestation_progress >= 1.0:
			events["release_livebearer_fry"] = _gestation_genome.duplicate(true)
			_gestation_progress = 0.0
			_gestation_genome = {}

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
			# Substrate dig: a persistent mulm voxel for the carpet, plus a
			# brief dust burst that rises + fades over ~1.4s. The dust is
			# the visible "kicked up the substrate" moment that just adding
			# a static voxel can't sell on its own. World caps the mulm
			# carpet so the persistent voxels don't balloon.
			if sim != null and position.y < sim.substrate_top_y + 1.0:
				var w := get_tree().current_scene.get_node_or_null("SubViewport/World")
				if w != null:
					if w.has_method("add_mulm_voxel"):
						w.add_mulm_voxel(global_position)
					if w.has_method("spawn_substrate_dust"):
						w.spawn_substrate_dust(global_position)

	# Surface air-gulping. Two niches use the same machinery:
	#   - "shuffle" cory/loach aerial respiration (~25-40s between trips)
	#   - labyrinth_breather anabantids (gourami, betta) that breathe
	#     atmospheric air at the surface far more habitually (~15-28s).
	# A trip darts the fish to just under the water surface, then it sinks
	# back. Implemented by overriding home_y via _aerial_timer +
	# _aerial_target_y - see the Y-enforcement block.
	if swim_pattern == "shuffle" or labyrinth_breather:
		if _aerial_timer <= 0.0:
			# Idle - count down to next trip OR start a trip.
			_aerial_timer -= dt
			var next_trip: float = randf_range(15.0, 28.0) if labyrinth_breather \
				else randf_range(25.0, 40.0)
			if _aerial_timer < -next_trip:
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
	# Juvenile color deepening: fry + juveniles are desaturated, gradually
	# gaining vibrancy as they approach adulthood (#14 in GOALS).
	elif maturity <= MATURITY_JUVENILE:
		_apply_maturity_color()
	else:
		_restore_original_colors()

	# Death conditions.
	# Old fish can hang on for 25% past max_age_s. Meal-driven age
	# reductions stack against this clock, so a well-fed senescent fish
	# can hold its place for a long time before finally dying of old age.
	if maturity == MATURITY_SENESCENT and age >= max_age_s * 1.25:
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
	# Tier 0.1: soft anti-intersection steering. Keeps body volumes from
	# visually occupying the same space (other fish / dense plants /
	# hardscape) while staying subtle enough to preserve schooling.
	desired += _local_clearance_push(neighbors, plants) * 1.25
	desired += _hardscape_clearance_push() * 1.6

	# Tier 0.2: SURFACE GULPING (hypoxia response). When dissolved O₂ drops
	# below SURFACE_GULP_O2, fish swim to the meniscus and hold there. Real
	# fish gulp atmospheric oxygen at the surface when the water is hypoxic
	# — it's the most recognizable "this tank is in trouble" body language
	# in the hobby. Highest priority after wall avoid since asphyxiation
	# trumps every other goal.
	if sim != null and float(sim.dissolved_o2) < SURFACE_GULP_O2:
		var surface_y: float = world_bounds.position.y + world_bounds.size.y - 0.15
		var gulp_dir: Vector3 = Vector3(0, surface_y - position.y, 0)
		# Add a small lateral random walk so the school of gulpers doesn't
		# converge to one column.
		gulp_dir.x += sin(_swim_phase * 0.7 + float(get_instance_id() % 100)) * 0.6
		desired += gulp_dir.normalized() * effective_max * 1.4
		current_mode = Mode.FORAGE
		# Don't return — let wall avoid still mix in so we don't pin to glass.

	# Tier 0.3: EGG-GUARDING / BROODING. Pair-bonding species (currently
	# the "hover" pattern, i.e. angelfish) stay near the egg cluster for
	# BROODING_DURATION after spawning. Behavior:
	#   - Hover within ~0.4u of brooding_at.
	#   - Chase the nearest non-partner intruder within BROODING_RADIUS,
	#     producing visible territorial defense.
	#   - Other tiers (food, partner-seeking) are suppressed via early
	#     return so the parents don't wander off mid-watch.
	if brooding_remaining > 0.0:
		brooding_remaining = maxf(0.0, brooding_remaining - dt)
		current_mode = Mode.COURT  # closest mode we have to "guarding"
		# Hold position at the nest. Damp velocity so the fish actually
		# settles instead of orbiting.
		var to_nest: Vector3 = brooding_at - position
		desired += to_nest * 1.5
		# Find the closest non-partner intruder to chase off.
		var threat: Fish = null
		var threat_d2: float = BROODING_RADIUS * BROODING_RADIUS
		for n in neighbors:
			if not (n is Fish):
				continue
			var nf: Fish = n
			if nf == partner or nf == self:
				continue
			if nf.maturity == MATURITY_FRY:
				continue
			var d2: float = nf.position.distance_squared_to(position)
			if d2 < threat_d2:
				threat_d2 = d2
				threat = nf
		if threat != null:
			var to_t: Vector3 = threat.position - position
			if to_t.length_squared() > 1e-4:
				desired += to_t.normalized() * effective_max * 1.8
				if burst_remaining < 0.25:
					burst_remaining = 0.25
		target_velocity = desired.limit_length(effective_max)
		return events

	# Tier 0.35: FRY PLANT SHELTER. Fresh fry seek the densest nearby plant
	# patch and hold position inside it until they hit juvenile stage. Real
	# fry do this instinctively — the foliage hides them from adult
	# predation and gives them first access to infusoria growing on leaves.
	# Once within ~0.5 units the fry dampens its velocity so it "nestles"
	# in the plant rather than orbiting around it. Play (tier 3.8) and
	# food (tier 1b) still fire when their conditions are met — this only
	# provides a default resting bias.
	if maturity == MATURITY_FRY:
		var shelter: Plant = null
		var shelter_d2: float = 16.0  # within 4 units
		for p in plants:
			if not is_instance_valid(p):
				continue
			if p.biomass() < 8:
				continue
			var d2: float = p._world_pos.distance_squared_to(position)
			if d2 < shelter_d2:
				shelter_d2 = d2
				shelter = p
		if shelter != null:
			var to_plant: Vector3 = shelter._world_pos - position
			to_plant.y += 0.3  # aim for mid-plant, not substrate base
			var dist: float = to_plant.length()
			if dist > 0.5:
				# Steer toward the plant at a gentle pace.
				desired += to_plant.normalized() * effective_max * 0.6
			else:
				# Inside the plant — dampen velocity to hold position.
				desired *= 0.15

	# Tier 0.4: FRY FLEE FROM ADULT CONSPECIFICS. Real fry instinctively dart
	# away from larger same-species fish that might cannibalize them. We
	# add a strong repulsion vector from any non-fry conspecific within
	# ~1.5 units. Burst is triggered so the flee reads as a panic dart
	# rather than steady drift.
	if maturity == MATURITY_FRY:
		var flee_threat: Fish = null
		var flee_d2_best: float = 2.25  # 1.5^2
		for n in neighbors:
			if not (n is Fish):
				continue
			var nf: Fish = n
			if nf.species != species or nf.maturity == MATURITY_FRY:
				continue
			var d2: float = nf.position.distance_squared_to(position)
			if d2 < flee_d2_best:
				flee_d2_best = d2
				flee_threat = nf
		if flee_threat != null:
			current_mode = Mode.FLEE
			var away: Vector3 = position - flee_threat.position
			if away.length_squared() > 1e-4:
				desired += away.normalized() * effective_max * 2.0
				if burst_remaining < 0.3:
					burst_remaining = 0.3
				stress = clampf(stress + 0.15, 0.0, 1.0)

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

	# Tier 0.6: STRESS HIDE-IN-PLANTS. When stress crosses STRESS_HIDE_THRESHOLD
	# (chronic distress — repeated predator scares, hypoxia, etc.), the fish
	# breaks off courtship / foraging and steers into the densest plant
	# patch. Real fish do exactly this; reads as "this one is scared and
	# wants out of the open." Big plants only (≥6 voxels) so a wisp of
	# fresh growth doesn't count as cover.
	if stress > STRESS_HIDE_THRESHOLD:
		var nearest_cover: Plant = null
		var cover_d2: float = 9.0  # within 3 units to count as reachable
		for p in plants:
			if not is_instance_valid(p):
				continue
			if p.biomass() < 6:
				continue
			var d2: float = p._world_pos.distance_squared_to(position)
			if d2 < cover_d2:
				cover_d2 = d2
				nearest_cover = p
		if nearest_cover != null:
			var to_cover: Vector3 = nearest_cover._world_pos - position
			to_cover.y += 0.4  # aim for mid-plant height, not the substrate
			desired += to_cover.normalized() * effective_max * 0.7
			current_mode = Mode.FLEE

	# Tier 1: COURTSHIP. Already paired? Continue the dance toward spawn.
	if partner != null:
		if not is_instance_valid(partner) or partner.maturity != MATURITY_ADULT:
			partner = null
			court_timer = 0.0
			_courtship_flare = false
			_courtship_sync = false
			_courtship_intensity = 0.0
		else:
			current_mode = Mode.COURT
			var to_partner: Vector3 = partner.position - position
			var dist: float = to_partner.length()
			# Swim alongside (not into) the partner: target a point slightly to one side.
			var side: Vector3 = to_partner.cross(Vector3.UP).normalized() * 0.4
			var courtship_target: Vector3 = partner.position + side
			# Courtship intensity ramp: builds from 0 to 1 over the full
			# COURT_DURATION. Drives the gradual acceleration of the S-curve
			# dance, fin flare, and color saturation boost so the display
			# crescendos toward the spawn flash.
			_courtship_intensity = clampf(court_timer / COURT_DURATION, 0.0, 1.0)
			# MALE COURTING DISPLAY. Real male guppies + bettas parade
			# alongside the female in a tight S-curve, flaring their tail
			# fins to maximum spread. We simulate this by adding a
			# sinusoidal lateral offset (the S-curve) when the male is
			# close enough to display, scaled by the courtship sequence
			# duration so the dance accelerates as the spawn approaches.
			if sex == 0 and dist < 1.8:
				# Phase speed ramps from 3.0 → 6.0 as intensity builds.
				var t_phase: float = court_timer * lerpf(3.0, 6.0, _courtship_intensity)
				# S-curve amplitude ramps from 0.15 → 0.45.
				var s_amp: float = lerpf(0.15, 0.45, _courtship_intensity)
				var s_offset: Vector3 = to_partner.cross(Vector3.UP).normalized() \
					* sin(t_phase) * s_amp
				desired += (courtship_target + s_offset - position).normalized() \
					* effective_max * 0.85
				# Mark the renderer flag - _apply_render() uses it to flare the
				# tail wag amplitude AND temporarily boost the bank angle so
				# the dance reads visually.
				_courtship_flare = true
			else:
				desired += (courtship_target - position).normalized() * effective_max * 0.7
				_courtship_flare = false
			# Female receptivity. While the male flashes side-by-side, the
			# female slows + holds station (real fish behavior - she's
			# evaluating the male's display). Subtle pull-back so she
			# isn't chasing.
			if sex == 1 and dist < 1.5:
				desired *= 0.55
			court_timer += dt
			# Final-beat sync window: both fish puff up + flare in unison
			# in the last 0.5s before egg drop. The render pass picks
			# this up as a bigger pulse so the spawn moment reads visually.
			var pre_spawn: bool = court_timer >= COURT_DURATION - 0.5 and dist < 1.6
			_courtship_sync = pre_spawn
			if pre_spawn and partner != null:
				partner._courtship_sync = true
			# Spawn when we've been close enough for long enough.
			if dist < 1.2 and court_timer >= COURT_DURATION:
				current_mode = Mode.SPAWN
				if is_livebearer:
					var female: Fish = self if sex == 1 else partner
					var male: Fish = partner if sex == 1 else self
					if female != null and male != null:
						female._gestation_progress = 0.01
						female._gestation_genome = female.produce_offspring_genome(male)
				else:
					events["lay_egg_with"] = partner
				breed_cooldown = 35.0
				energy = maxf(0.0, energy - 0.35)
				# Post-spawn burst: both fish dart apart visibly. Gives
				# the moment a clean "and we're done" punctuation
				# instead of cleanly resuming cruise.
				burst_remaining = 0.4
				partner.breed_cooldown = 35.0
				partner.energy = maxf(0.0, partner.energy - 0.35)
				partner.burst_remaining = 0.4
				breed_count += 1
				partner.breed_count += 1
				partner.partner = null
				partner = null
				court_timer = 0.0
				_courtship_flare = false
				_courtship_sync = false
				_courtship_intensity = 0.0
			target_velocity = desired.limit_length(effective_max)
			return events

	# Tier 1b: SCAVENGE WASTE. Fish opportunistically eat waste particles
	# that drift past. Cheaper than chasing live food. Applies to all fish,
	# herbivores or not, when even slightly hungry.
	#
	# Surface-skim feeding: top-dwellers (preferred_y >= 4.5) get a vertical-
	# affinity bonus on KIND_FOOD that bobs on the surface — the real-world
	# behavior of killifish / danios / hatchetfish racing each other to the
	# top of the tank when flakes land. Implemented as a score penalty on
	# food that's BELOW the fish's preferred Y, so surface dwellers ignore
	# sunk pellets and grab surface ones first, while bottom dwellers do
	# the opposite (loaches and cory hoover sunk food).
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
			# Y-affinity bias: penalize food in the WRONG water column for
			# this fish. Effect is mild (×1.5 at maximum penalty) so a
			# truly hungry fish still chases anything, but in normal play
			# the top-dwellers win the surface flakes and bottom-dwellers
			# clean up settled pellets.
			if w.kind == 3:
				var w_y: float = (w as Node3D).global_position.y
				var y_delta: float = absf(w_y - preferred_y)
				d2 *= 1.0 + clampf(y_delta * 0.18, 0.0, 0.5)
			if d2 < max_dist_sq and d2 < best_d2:
				best_d2 = d2
				best_w = w
		if best_w != null:
			current_mode = Mode.FORAGE
			var to_w: Vector3 = best_w.global_position - position
			if to_w.length() < 0.4:
				events["eat_waste"] = best_w
				var is_food: bool = best_w.kind == 3
				hunger = maxf(0.0, hunger - (FOOD_HUNGER_DELTA if is_food else WASTE_HUNGER_DELTA))
				energy = minf(1.0, energy + (FOOD_ENERGY_DELTA if is_food else WASTE_ENERGY_DELTA))
				# All meals rewind the age clock a little.
				age = maxf(0.0, age - max_age_s * MEAL_AGE_REDUCTION_FRAC)
				if is_food:
					# High-quality food stacks an additional big revival.
					age = maxf(0.0, age - max_age_s * FOOD_AGE_REVIVAL_FRAC)
					stress = 0.0
					if maturity == MATURITY_SENESCENT and age < max_age_s:
						maturity = MATURITY_ADULT
					if _food_glow != null:
						_food_glow.light_energy = FOOD_GLOW_ENERGY
				# Eating consumes the rest of this tick: apply accumulated
				# steering (wall_avoid + schooling) and return. Without this
				# return, the fish falls through into predation/breeding
				# tiers and can record multiple conflicting events that
				# overwrite each other in the same dict.
				target_velocity = desired.limit_length(effective_max)
				return events
			else:
				var pull: float = 0.9
				if best_w.kind == 3: # FOOD
					pull = 1.9
					# Older fish try harder to get food!
					var age_factor: float = clampf(age / max_age_s, 0.0, 1.2)
					pull += age_factor * 1.5
					
					# Dart towards food and trigger a feeding frenzy!
					if burst_remaining <= 0.0 and energy > 0.15 and randf() < 0.4:
						burst_remaining = randf_range(0.4, 0.7) + (age_factor * 0.3)
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
		var kill_advantage: float = clampf(1.95 - jaw_claw_size * 0.35, 1.45, 2.05)
		var kill_reach: float = 0.45 + jaw_claw_size * 0.16
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
			if my_size > of.effective_size() * kill_advantage:
				var d2: float = of.position.distance_squared_to(position)
				if d2 < best_prey_d2:
					best_prey_d2 = d2
					best_prey = of
		# Adult shrimp only become prey to very large predators (3x advantage).
		# This effectively limits adult-shrimp predation to a well-grown betta
		# - otherwise the school strips shrimp before they can recruit. Dying
		# shrimp are skipped so a predator doesn't snap-eat a fading corpse
		# mid-death animation.
		if sim != null:
			for s in sim.shrimp:
				if not is_instance_valid(s) or s.maturity != Shrimp.MATURITY_ADULT:
					continue
				if s.get("_dying") == true:
					continue
				if my_size > s.adult_voxel_scale * (3.0 - jaw_claw_size * 0.45):
					var d2: float = s.position.distance_squared_to(position)
					if d2 < best_prey_d2:
						best_prey_d2 = d2
						best_prey = s
		if best_prey != null and is_instance_valid(best_prey):
			current_mode = Mode.FORAGE
			var to_prey: Vector3 = (best_prey as Node3D).global_position - position
			if to_prey.length() < kill_reach:
				events["kill_prey"] = best_prey
				hunger = maxf(0.0, hunger - 0.50)
				energy = minf(1.0, energy + 0.18)
				age = maxf(0.0, age - max_age_s * MEAL_AGE_REDUCTION_FRAC)
				events["waste_at"] = position + Vector3(0, -0.1, 0)
				events["waste_amount"] = 0.20
				# A successful kill ends the tick. Falling through would
				# overwrite events["kill_prey"] / events["waste_at"] with a
				# later tier's target and drop the actual predation.
				target_velocity = desired.limit_length(effective_max)
				return events
			else:
				if burst_remaining <= 0.0 and energy > 0.3:
					burst_remaining = 0.5
				desired += to_prey.normalized() * effective_max * 1.3
				target_velocity = desired.limit_length(effective_max)
				return events

	# Tier 1c: PREDATION on baby shrimp.
	# shrimp_predator lineages are much more likely to pursue shrimp fry.
	var predation_chance: float = 0.10 if (species == "betta" or shrimp_predator) else 0.02
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
			var prey_spines: float = 0.0
			var prey_toxin: float = 0.0
			var prey_shelter: float = 0.0
			var sp_v: Variant = prey.get("defense_spines")
			var tx_v: Variant = prey.get("toxin_level")
			var sh_v: Variant = prey.get("shelter_bonus")
			if sp_v != null:
				prey_spines = clampf(float(sp_v), 0.0, 1.0)
			if tx_v != null:
				prey_toxin = clampf(float(tx_v), 0.0, 1.0)
			if sh_v != null:
				prey_shelter = clampf(float(sh_v), 0.0, 1.0)
			var repel: float = clampf(
				prey_spines * 0.45 + prey_toxin * 0.55 + prey_shelter * 0.65,
				0.0, 0.94)
			if randf() < repel * 0.55:
				stress = minf(1.0, stress + repel * 0.08)
				target_velocity = desired.limit_length(effective_max)
				return events
			var to_prey: Vector3 = prey.global_position - position
			if to_prey.length() < 0.35:
				events["kill_prey"] = prey
				var meal_mult: float = clampf(1.0 - repel * 0.65, 0.2, 1.0)
				hunger = maxf(0.0, hunger - 0.40 * meal_mult)
				energy = minf(1.0, energy + 0.12 * meal_mult)
				stress = minf(1.0, stress + prey_toxin * 0.16)
				age = maxf(0.0, age - max_age_s * MEAL_AGE_REDUCTION_FRAC)
				events["waste_at"] = position + Vector3(0, -0.1, 0)
				events["waste_amount"] = 0.15
				# Successful baby-shrimp kill: end the tick so events don't
				# get stomped by Tier 1.9 / 2 below.
				target_velocity = desired.limit_length(effective_max)
				return events
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
				var shell_spines: float = 0.0
				var toxin: float = 0.0
				var ss: Variant = s.get("shell_spines")
				var tx: Variant = s.get("toxin_level")
				if ss != null:
					shell_spines = clampf(float(ss), 0.0, 1.0)
				if tx != null:
					toxin = clampf(float(tx), 0.0, 1.0)
				var danger: float = shell_spines * 0.55 + toxin * 0.6
				if randf() < danger * 0.42:
					continue
				var d2: float = (s.global_position - position).length_squared()
				if d2 < best_snail_d2:
					best_snail_d2 = d2
					best_snail = s
			if best_snail != null:
				current_mode = Mode.FORAGE
				var to_snail: Vector3 = best_snail.global_position - position
				if best_snail_d2 < 0.25:
					var shell_spines: float = 0.0
					var toxin: float = 0.0
					var ss2: Variant = best_snail.get("shell_spines")
					var tx2: Variant = best_snail.get("toxin_level")
					if ss2 != null:
						shell_spines = clampf(float(ss2), 0.0, 1.0)
					if tx2 != null:
						toxin = clampf(float(tx2), 0.0, 1.0)
					var meal_mult: float = clampf(1.0 - (shell_spines * 0.45 + toxin * 0.65), 0.18, 1.0)
					events["kill_snail"] = best_snail
					hunger = maxf(0.0, hunger - 0.35 * meal_mult)
					stress = minf(1.0, stress + toxin * 0.18)
					age = maxf(0.0, age - max_age_s * MEAL_AGE_REDUCTION_FRAC)
					# Snail-snap done: return so the algae loop below doesn't
					# overwrite events["kill_snail"] with an eat_algae target.
					target_velocity = desired.limit_length(effective_max)
					return events
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
					age = maxf(0.0, age - max_age_s * MEAL_AGE_REDUCTION_FRAC)
					# Algae crop done: return so Tier 2 herbivore plant-nibbling
					# below doesn't add an events["waste_at"] entry for this
					# same tick and double-count nutrients.
					target_velocity = desired.limit_length(effective_max)
					return events
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
					age = maxf(0.0, age - max_age_s * MEAL_AGE_REDUCTION_FRAC * float(taken))
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
	# Livebearer males don't initiate courtship. Real guppy / platy
	# females cruise to sheltered cover and the male follows her there;
	# we approximate that here by letting only the female (sex == 1) of
	# a livebearer species call _find_breeding_partner. The male can
	# still ACCEPT a bond when a female pairs with him (handled by the
	# `candidate.partner = self` line below).
	var female_initiator_only: bool = is_livebearer and sex == 0
	if not female_initiator_only and maturity == MATURITY_ADULT \
			and breed_cooldown <= 0.0 and partner == null \
			and hunger < 0.5 and energy > 0.65 and stress < 0.4 \
			and current_fish_pop < FISH_POPULATION_CAP:
		var candidate: Fish = _find_breeding_partner(neighbors)
		if candidate != null and candidate.partner == null:
			# Mutual pair-bond.
			partner = candidate
			candidate.partner = self
			court_timer = 0.0
			candidate.court_timer = 0.0

	# Tier 3.8: JUVENILE PLAY (fry only). Fry chase each other in short
	# bursts — purely social motion, not foraging. Real fry do this
	# constantly between feeds and it reads as "alive" instantly. Skips
	# if the fry is hungry / stressed / out of energy.
	if maturity == MATURITY_FRY and hunger < 0.6 and stress < 0.5 \
			and energy > 0.45 and burst_remaining <= 0.0:
		# Roll the dice each tick for a brief play burst — every ~20 sim
		# seconds on average per fry (dt * 0.05).
		if randf() < dt * 0.05:
			var playmate: Fish = null
			var pd2: float = 4.0  # within 2 units
			for n in neighbors:
				if not (n is Fish):
					continue
				var nf: Fish = n
				if nf.maturity != MATURITY_FRY or nf == self:
					continue
				var d2: float = nf.position.distance_squared_to(position)
				if d2 < pd2:
					pd2 = d2
					playmate = nf
			if playmate != null:
				var to_mate: Vector3 = playmate.position - position
				if to_mate.length_squared() > 1e-4:
					desired += to_mate.normalized() * effective_max * 1.2
					burst_remaining = 0.4

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
		var pull_mult: float = 0.5
		if swim_pattern == "hover":
			pull_mult = 0.15 # gentler pull to avoid centering oscillations / spinning
		desired += to_home.normalized() * effective_max * pull_mult * pull_strength

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
	#
	# `dart_chance` is a per-second probability; multiply by `dt` to get the
	# per-tick probability (SIM_DT=0.1 → 0.1× scaling). The previous code had
	# an extra `* 10.0` that canceled the dt scaling, so every fish darted at
	# 10× the heritable rate — schools twitched constantly.
	if dart_chance > 0.0 and burst_remaining <= 0.0 \
			and randf() < dart_chance * dt and energy > 0.25:
		burst_remaining = randf_range(0.25, 0.45)
		# Snap heading_offset to a new random direction so the dart goes
		# somewhere new (not just "faster in current direction").
		var ang: float = randf() * TAU
		var dart_dir := Vector3(sin(ang), randf_range(-0.15, 0.15), cos(ang))
		heading_offset = dart_dir * (1.0 + wander_strength)
		# Record startle heading so school-mates can copy it.
		_startle_heading = dart_dir
		_startle_remaining = 0.4
		# Surface ripple — if the fish darts near the meniscus, the
		# motion breaks surface tension and we spawn an expanding ring
		# at the surface above its current position. Top-water schools
		# (killifish, danios at preferred_y ≥ 4.5) trigger this often;
		# bottom dwellers basically never. World caps via short ripple
		# lifespan, no explicit pool.
		if position.y > home_y * 0.85 and preferred_y >= 4.0 \
				and sim != null and sim.has_method("get_parent"):
			var w := sim.get_parent()
			if w != null and w.has_method("spawn_burst_ripple"):
				w.spawn_burst_ripple(position)

	# HOVER / INVESTIGATE TRIGGER. Any fish might occasionally stop mid-water to
	# look around. This breaks up the constant swimming and adds lifelike personality.
	#
	# Previously this zeroed `desired` AND `target_velocity` then returned —
	# which threw away the Tier-0 wall_avoid contribution. With dt=0.1 and a
	# ~12% per-second trigger rate, a fish near the glass had ~12% chance per
	# second to LOCK itself against the wall (no avoidance force, no motion).
	# The fix preserves the wall-avoid (and schooling/home_pull) contributions
	# already in `desired`, just heavily damped — fish drifts slowly while
	# "investigating" instead of freezing.
	if burst_remaining <= 0.0 and _startle_remaining <= 0.0 and randf() < dt * 0.12 and energy > 0.3:
		# 15% of max speed → enough motion to slide off a wall, slow enough to
		# read as "pausing to look around."
		target_velocity = desired.limit_length(effective_max * 0.15)
		return events
		
	# PLAYFUL DART (ZOOMIES). Even non-dart species occasionally get a burst of
	# energy if they are well-fed and healthy.
	if burst_remaining <= 0.0 and energy > 0.7 and hunger < 0.2 and randf() < dt * 0.05:
		burst_remaining = randf_range(0.3, 0.6)
		var ang: float = randf() * TAU
		heading_offset = Vector3(sin(ang), randf_range(-0.4, 0.6), cos(ang)) * 1.5

	# Wander refresh: periodically rotate heading_offset to a new random
	# direction. Interval is shorter for solo fish (every 4-8s) so they
	# explore actively, longer for tight schoolers (every 15-25s) where
	# the school boids already provide direction variety.
	_wander_refresh_timer -= dt
	if _wander_refresh_timer <= 0.0:
		var interval: float = 15.0 + randf() * 10.0  # schooler default
		if schooling_strength < 0.4:
			interval = 4.0 + randf() * 4.0  # solo fish: much more frequent
		elif swim_pattern == "shuffle":
			interval = 5.0 + randf() * 6.0  # loaches: frequent zig-zags
		_wander_refresh_timer = interval
		var ang: float = randf() * TAU
		heading_offset = Vector3(
			sin(ang) * randf_range(0.3, 0.6),
			randf_range(-0.15, 0.15),
			cos(ang) * randf_range(0.3, 0.6),
		)

	# Home-point drift: bottom-dwellers (shuffle) and solo/low-schooling fish
	# periodically shift their home_x/home_z so they roam the tank over time
	# instead of circling the same spot. Real kuhli loaches explore the
	# entire substrate; bettas patrol different territories.
	_home_drift_timer -= dt
	if _home_drift_timer <= 0.0:
		var drift_interval: float = 30.0 + randf() * 30.0  # default: 30-60s
		var drift_radius: float = 1.5
		if swim_pattern == "shuffle":
			drift_interval = 15.0 + randf() * 15.0  # loaches: faster roaming
			drift_radius = 3.0  # cover more ground
		elif schooling_strength < 0.4:
			drift_interval = 20.0 + randf() * 15.0  # solo fish: moderate drift
			drift_radius = 2.5
		_home_drift_timer = drift_interval
		# Nudge home within tank bounds. The world_bounds AABB keeps
		# the drift from pushing home outside the tank.
		home_x = clampf(home_x + randf_range(-drift_radius, drift_radius),
			world_bounds.position.x + 1.0, world_bounds.end.x - 1.0)
		home_z = clampf(home_z + randf_range(-drift_radius, drift_radius),
			world_bounds.position.z + 1.0, world_bounds.end.z - 1.0)

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

		# Sleep shelter-seeking. When daylight drops below 0.18 (deep
		# night) AND the species is diurnal (low pattern types), bias
		# the fish gently toward the nearest large plant — like real
		# tetras / killis / guppies tucking into the foliage to sleep.
		# Only kicks in if no higher-priority drive is already set
		# (hungry / breeding fish keep moving). Soft pull so it reads
		# as drifting, not herding.
		if dl < 0.18 and current_mode == Mode.CRUISE \
				and (swim_pattern == "school" or swim_pattern == "shoal" \
					or swim_pattern == "hover" or swim_pattern == "meander"):
			var shelter: Plant = null
			var sd2: float = 16.0  # within 4 units
			for p in plants:
				if not is_instance_valid(p):
					continue
				if p.biomass() < 6:
					continue
				var d2: float = p._world_pos.distance_squared_to(position)
				if d2 < sd2:
					sd2 = d2
					shelter = p
			if shelter != null:
				var to_shelter: Vector3 = shelter._world_pos - position
				to_shelter.y += 0.5
				desired += to_shelter.normalized() * effective_max * 0.35
				current_mode = Mode.REST

	target_velocity = desired.limit_length(effective_max)
	# Position + facing now updated in _process at render rate.

	# Senescence speeds hunger a little but no longer punishes; meals
	# can still meaningfully rewind the age clock even for old fish.
	if maturity == MATURITY_SENESCENT:
		hunger = clampf(hunger + dt * 0.007, 0.0, 1.0)

	# Starvation kills.
	if hunger >= 1.0 and energy < 0.1:
		events["die"] = true

	# Size growth from feeding history. Adults that maintain low hunger
	# slowly grow; ones that stay starved shrink toward 0.6x. This is what
	# makes well-fed populations produce bigger fish over time and creates
	# the size-based predation dynamic.
	if maturity == MATURITY_ADULT:
		if hunger < 0.35:
			growth_factor = minf(
				growth_factor + 0.0008 * dt * (0.75 + size_potential * 0.65), max_growth)
		elif hunger > 0.7:
			growth_factor = maxf(
				growth_factor - 0.0004 * dt * (1.18 - size_potential * 0.35), 0.6)

	# Update body scale across maturity AND growth_factor.
	scale = scale.lerp(Vector3.ONE * _maturity_scale() * growth_factor, dt * 0.5)

	return events


# Per-frame: bounded-turn-rate steering + speed acceleration + banking. The
# brain (tick at 10Hz) produces target_velocity; this physics layer translates
# it into smooth heading + speed changes that respect momentum.
#
# Fish can't slide sideways, can't 180° in place, and bank into yaw turns.
func _process(dt: float) -> void:
	if _food_glow != null and _food_glow.light_energy > 0.0:
		_food_glow.light_energy = maxf(0.0, _food_glow.light_energy - dt * 1.5)

	if sim != null:
		dt *= sim.time_scale
		if dt <= 0.0:
			return  # paused

	_update_pheromone_trail()

	# Apply pregnancy bulge if gestating
	if _body_mid_pivot != null:
		if is_livebearer and sex == 1 and _gestation_progress > 0.0:
			var bulge := 1.0 + _gestation_progress * 0.35
			_body_mid_pivot.scale = Vector3(bulge * 0.8 + 0.2, bulge, 1.0)
		else:
			_body_mid_pivot.scale = Vector3.ONE

	# Death sequence — drifts sideways, sinks, fades over DEATH_DURATION
	# before the sim_driver actually frees us. Skips the normal motion
	# pipeline so a dying fish doesn't fight the death pose.
	if _dying:
		_animate_death(dt)
		return

	# Substep at high time_scale. With time_scale=16 and a 60-fps render
	# frame, a single naive step gets dt ≈ 0.27 s — long enough that the
	# fish translates past its steering target, the brain inverts the
	# desired velocity next frame, and the fish ping-pongs in place
	# (the "spinning stupidly" bug). Splitting into ≤ 0.05 s sub-steps
	# keeps Euler integration stable while preserving the nominal sim
	# rate. One sub-step at 1× time_scale (the common case) so there's
	# no cost when it doesn't matter.
	var n_steps: int = clampi(int(ceil(dt / 0.05)), 1, 16)
	var sub_dt: float = dt / float(n_steps)
	for _step in n_steps:
		_motion_substep(sub_dt)


# Day/night activity multiplier. 1.0 = nominal speed, <1 = drowsy / asleep
# behavior, >1 = nocturnal alertness. SimDriver.daylight() peaks at 1.0 at
# midday and bottoms at 0.0 at midnight. Bottom-dwellers (shuffle swim
# pattern: corydoras + mudsifter / kuhli loaches) invert the curve because
# real loaches forage at night. Result: at midnight, top-water tetras
# barely cruise while the bottom group is actively shuffling — a tiny
# touch but exactly what makes a tank feel alive 24h.
func _day_activity_mult() -> float:
	if sim == null:
		return 1.0
	var daylight: float = float(sim.daylight())
	if swim_pattern == "shuffle":
		return lerpf(0.75, 1.15, 1.0 - daylight)
	return lerpf(0.55, 1.0, daylight)


# Triggers the death-animation state. Called by SimDriver when a die event
# fires (old age / starvation). Idempotent so multiple die events in the
# same tick don't reset the timer.
func start_dying() -> void:
	if _dying:
		return
	_dying = true
	_dying_timer = DEATH_DURATION
	# Stop all forward motion + steering targets so the brain's last
	# commanded velocity doesn't keep the corpse swimming.
	target_velocity = Vector3.ZERO
	speed = 0.0
	burst_remaining = 0.0


# Death pose: tilts onto its side, drifts slowly downward, shrinks toward
# zero, then frees the node. We shrink the bank pivot's scale rather than
# fading alpha because Node3D has no `modulate` (that's a CanvasItem 2D
# property) and the voxel body is dozens of MeshInstance3Ds — touching
# their materials would mean turning transparency on per-voxel for a
# 3-second animation. Scaling reads as "withering" and is one Vector3
# write per frame. Combined with the sink + tilt + final mulm drop, the
# visual story is: tip, drift, dissolve.
func _animate_death(dt: float) -> void:
	_dying_timer = maxf(0.0, _dying_timer - dt)
	var progress: float = clampf(1.0 - (_dying_timer / DEATH_DURATION), 0.0, 1.0)
	# Tilt: rotate onto right flank over the first ~30% of the death
	# duration. Real fish flip belly-up or onto a flank when they die; the
	# bank pivot already exists so we just push its z-rotation to PI/2.
	if _bank_pivot != null:
		var tilt_target: float = PI * 0.5
		var tilt_speed: float = clampf(dt * 1.8, 0.0, 1.0)
		_bank_pivot.rotation.z = lerpf(_bank_pivot.rotation.z, tilt_target, tilt_speed)
		# Reset the live pitch toward zero so the dying pose isn't still
		# nosing down from sift / senescence.
		_bank_pivot.rotation.x = lerpf(_bank_pivot.rotation.x, 0.0, tilt_speed)
		# Shrink toward 0.15× over the death duration. Keeps a faint
		# silhouette through ~70% of the animation, then drops fast at
		# the end so the queue_free is visually motivated.
		var shrink: float = lerpf(1.0, 0.15, progress)
		_bank_pivot.scale = Vector3(shrink, shrink, shrink)
	# Sink slowly — real dead fish drop to the substrate as buoyancy fails.
	position.y -= 0.18 * dt
	# Stop above substrate so the corpse rests on the bottom rather than
	# clipping through it. SimDriver's substrate_top_y is the floor.
	if sim != null and position.y < sim.substrate_top_y + 0.1:
		position.y = sim.substrate_top_y + 0.1
	# At the end of the sequence, drop the mulm and remove the node.
	if _dying_timer <= 0.0:
		if sim != null and sim.has_method("_spawn_waste"):
			var kind: int = WasteParticle.KIND_FISH
			sim._spawn_waste(position, 0.4, kind)
		queue_free()


# Single physics integration step. Pulled out of _process so we can call it
# multiple times per frame at high time_scale without the integration
# blowing up. Reads target_velocity (set by the brain at 10 Hz), writes
# heading + position + look_at + bank.
func _motion_substep(dt: float) -> void:
	# Decompose the brain's target into a desired direction + desired speed.
	# Sifting fish (cory mid-graze) almost stop while the timer is active.
	var target_dir: Vector3 = heading
	var target_spd: float = 0.0
	if target_velocity.length_squared() > 0.0001:
		target_spd = target_velocity.length()
		target_dir = target_velocity.normalized()
	if _sift_timer > 0.0:
		target_spd *= 0.15
	# Senescent fish swim noticeably slower - tired old animals drift
	# instead of darting. Stress also damps speed (chronically distressed
	# fish move less, hold still in cover).
	if maturity == MATURITY_SENESCENT:
		target_spd *= 0.4
	elif stress > 0.6:
		target_spd *= 0.75
	# Day/night activity modulation. Diurnal species (tetras, bettas, etc.)
	# slow at night to half-speed; bottom-dwellers with the shuffle swim
	# pattern (cory, mudsifter) are nocturnal in real tanks and become
	# noticeably MORE active when the lights go down. Subtle by design —
	# the tank should never feel frozen, even at deep midnight.
	target_spd *= _day_activity_mult()

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
		# Defensive NaN guard: if axis was degenerate in a way the checks
		# above missed, the rotation can leak NaN into heading. Restore from
		# _last_yaw so the fish doesn't enter a spin-forever orientation
		# (look_at(NaN) silently corrupts the transform basis).
		if not heading.is_finite() or heading.length_squared() < 0.5:
			heading = Vector3(sin(_last_yaw), 0.0, -cos(_last_yaw))

	# ---- Accelerate speed toward target_spd, bounded by linear_accel ----
	speed = move_toward(speed, target_spd, linear_accel * dt)

	# ---- Apply translation ----
	velocity = heading * speed
	position += velocity * dt
	# Soft-brain wall avoidance can still overshoot on high timescale + burst.
	# Hard clamp keeps bodies from visibly intersecting glass geometry.
	if sim != null:
		var b: AABB = sim.world_bounds
		position.x = clampf(position.x, b.position.x + 0.20, b.end.x - 0.20)
		position.y = clampf(position.y,
			maxf(b.position.y + 0.20, sim.substrate_top_y + 0.08),
			b.end.y - 0.20)
		position.z = clampf(position.z, b.position.z + 0.20, b.end.z - 0.20)

	# ---- Face the heading. look_at points local -Z at the target. Body is
	# built so its forward = -Z, so the fish faces its motion correctly.
	# We only re-orient when the fish has meaningful forward speed; when
	# nearly stopped the brain may flip target_velocity direction frame-to-
	# frame and look_at would snap the fish around (read as "spinning"). ----
	if speed > 0.04 and heading.length_squared() > 0.0001:
		var d: Vector3 = heading
		# Avoid look_at singularity when heading is straight up/down.
		# Nudge by 0.05 (not 0.0001) so the resulting d is meaningfully
		# off-axis — a sub-millimeter nudge can still confuse look_at on
		# certain platforms.
		if absf(d.dot(Vector3.UP)) > 0.95:
			d = (d + Vector3(0.05, 0, 0)).normalized()
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
		elif _courtship_flare and sex == 0:
			pitch_target = -0.14   # male: nose up for the parade display
		elif partner != null and sex == 1:
			# Female receptivity tilt: slight nose-down + look toward the
			# courting male. Real females signal acceptance with a head-
			# down "approach me" pose during the dance.
			pitch_target = 0.05
		elif maturity == MATURITY_SENESCENT:
			# Old fish lose buoyancy control - nose tips downward as they
			# drift toward the substrate, a recognisable "dying fish" pose
			# before queue_free. Stronger tilt than the stress slump below.
			pitch_target = 0.22
		elif stress > 0.6:
			# Chronic stress: shoulders-down body language. Subtle compared
			# to sifting / dying so the player reads it as mood, not action.
			pitch_target = 0.08
		_bank_pivot.rotation.x = lerpf(_bank_pivot.rotation.x, pitch_target,
			clampf(dt * 4.0, 0.0, 1.0))

	# ---- Swim animation ----
	# Per-locomotion amplitudes + phase relationships. Real fish use very
	# different propulsion strategies based on body shape; we drive the
	# three-segment chain (head → body_mid → tail) and the pectoral fins
	# differently per locomotion_type so loaches actually undulate like
	# eels, puffers stiffly paddle their tails, reef tangs row with
	# their pec fins, and the default schoolers carangiform-wag.
	var wag_freq: float = 2.5 + speed * 5.5
	var wag_amp_extra: float = 0.0
	var pec_amp_extra: float = 0.0
	if _courtship_flare:
		wag_freq *= 1.0 + _courtship_intensity * 0.5
		# Wag and pec amplitudes ramp with courtship intensity so the
		# display crescendos from a subtle shimmy to a dramatic flare.
		wag_amp_extra = 0.10 + _courtship_intensity * 0.25
		# Pectoral fins flare wider during display - real courting fish
		# spread their pec fins maximally to look bigger / fitter.
		pec_amp_extra = 0.10 + _courtship_intensity * 0.30
	# Pre-spawn sync window: both fish puff up + flare in unison the
	# beat before egg drop. Drives the body pulse and a brief extra
	# pec spread so the spawn moment reads as a flash.
	if _courtship_sync:
		wag_amp_extra += 0.20
		pec_amp_extra += 0.25

	# Per-locomotion tuning. Phase offsets are measured FROM the tail's
	# sin(phase) reference. Positive offset = that segment leads the tail.
	# A traveling head→tail wave needs head leading, body mid leading by
	# half, tail trailing — values below produce that for anguilliform.
	var tail_amp: float = 0.35
	var body_amp: float = 0.10
	var body_phase: float = PI       # default = counter-wag (180° out of phase)
	var head_amp: float = 0.0
	var head_phase: float = 0.0
	var pec_amp_base: float = 0.45
	var pec_freq_base: float = 4.5 + speed * 3.0
	match locomotion_type:
		"anguilliform":
			# Eel / loach style: whole-body traveling sine wave. Head
			# leads, body mid follows ~50° behind, tail trails ~100°
			# behind the head. Slower base frequency, larger amplitudes.
			wag_freq = 1.8 + speed * 3.5
			tail_amp = 0.55
			body_amp = 0.40
			body_phase = -0.55 * PI    # body lags tail by 100° → traveling wave
			head_amp = 0.30
			head_phase = -1.1 * PI     # head leads tail by ~80°
			pec_amp_base = 0.20        # pec fins almost still on eels
		"ostraciiform":
			# Boxfish / puffer: rigid body, only the tail oscillates.
			# Higher tail frequency to make up for the small amplitude
			# and lack of body assist. Pec fins do most of the steering.
			wag_freq = 3.5 + speed * 6.0
			tail_amp = 0.42
			body_amp = 0.02
			head_amp = 0.0
			pec_amp_base = 0.80
		"labriform":
			# Reef tang / angelfish: pectoral fins are the primary
			# thrust, tail subdued. Pec fins beat at a higher
			# frequency independent of the body wag.
			tail_amp = 0.18
			body_amp = 0.04
			head_amp = 0.0
			pec_amp_base = 1.05
			pec_freq_base = 5.5 + speed * 4.5
		"thunniform":
			# Tuna cruiser: stiff body, narrow but fast tail.
			wag_freq = 3.0 + speed * 7.0
			tail_amp = 0.25
			body_amp = 0.03
			head_amp = 0.0
			pec_amp_base = 0.30
		_:
			# subcarangiform default — current schooler behavior.
			pass

	_swim_phase += dt * wag_freq
	if _tail_pivot != null:
		_tail_pivot.rotation.y = sin(_swim_phase) * (tail_amp + wag_amp_extra \
			+ minf(speed * 0.18, 0.25))
	if _body_mid_pivot != null:
		_body_mid_pivot.rotation.y = sin(_swim_phase + body_phase) \
			* (body_amp + wag_amp_extra * 0.4)
	if _head_pivot != null:
		# Smooth head rotation in to avoid pop when locomotion changes.
		var head_target: float = sin(_swim_phase + head_phase) * head_amp
		# Eye saccades: at rest, the head occasionally micro-turns. Fish
		# don't have movable eyeballs (most species) so they redirect
		# gaze by twitching the whole head a few degrees. Combined with
		# the gill-flare scale pulse below, this is the difference
		# between a "frozen voxel" and a "fish that's alive but holding
		# position." Triggered randomly so each fish's twitches stay
		# out of sync with its school-mates.
		var rest_factor: float = 1.0 - clampf(speed * 2.5, 0.0, 1.0)
		_saccade_t -= dt
		if rest_factor > 0.5 and _saccade_t <= 0.0:
			_saccade_t = randf_range(2.5, 5.5)
			_saccade_target = randf_range(-0.22, 0.22)
		# Decay the saccade target back toward 0 so the twitch is a brief
		# pulse, not a sustained head-cock.
		_saccade_target = lerpf(_saccade_target, 0.0, clampf(dt * 1.8, 0.0, 1.0))
		_head_pivot.rotation.y = lerpf(_head_pivot.rotation.y,
			head_target + _saccade_target * rest_factor,
			clampf(dt * 12.0, 0.0, 1.0))
		# Gill flare at rest. When the fish is barely moving (drifting,
		# sifting, sleeping), the eye reads a subtle head-width pulse as
		# gill-cover breathing — a real fish at rest does this constantly
		# and a still aquarium fish that DOESN'T do it reads as "frozen".
		# Active swimming hides the pulse anyway (wag dominates the visual).
		var breath_amp: float = 0.035 * rest_factor
		var breath: float = 1.0 + sin(_swim_phase * 0.9) * breath_amp
		_head_pivot.scale = Vector3(breath, 1.0, 1.0)
	# Dorsal: small sway with the body counter-wag, faster small flutter on top.
	if _dorsal_pivot != null:
		_dorsal_pivot.rotation.x = sin(_swim_phase * 1.3) * 0.08
		_dorsal_pivot.rotation.z = -sin(_swim_phase) * 0.05
	if _anal_pivot != null:
		_anal_pivot.rotation.x = -sin(_swim_phase * 1.3) * 0.10
	# Pectoral fins: faster rowing flutter. Each side offset by PI/2 so the
	# motion looks like a continuous paddle. Labriform / ostraciiform get
	# bigger amplitude because their bodies don't propel — the pecs do.
	var pec_freq: float = pec_freq_base
	var pec_amp: float = pec_amp_base + pec_amp_extra - minf(speed * 0.12, 0.30)
	pec_amp = maxf(pec_amp, 0.10)
	if _pec_right_pivot != null:
		_pec_right_pivot.rotation.z = sin(_swim_phase * pec_freq / wag_freq) * pec_amp
	if _pec_left_pivot != null:
		_pec_left_pivot.rotation.z = -sin(_swim_phase * pec_freq / wag_freq + PI * 0.5) * pec_amp

	# ---- Courtship body pulse ----
	# Subtle scale shimmy that reads as "puffing up" during display.
	# Independent of swim_phase so the pulse doesn't lock to the tail
	# wag. Stronger for males during display, biggest during the sync
	# window. Amplitude now scales with _courtship_intensity so the
	# puffing builds gradually toward the spawn flash.
	if _bank_pivot != null:
		var display_amp: float = 0.0
		if _courtship_flare:
			var base_amp: float = 0.03 if sex == 0 else 0.015
			display_amp = base_amp + _courtship_intensity * (0.05 if sex == 0 else 0.025)
		if _courtship_sync:
			display_amp += 0.08
		if display_amp > 0.0:
			_courtship_pulse_phase += dt * 7.0
			var pulse: float = 1.0 + sin(_courtship_pulse_phase) * display_amp
			# Apply differentially: width swells more than length so the
			# fish reads as fuller-bodied, not stretched.
			_bank_pivot.scale = Vector3(pulse, pulse * 0.6 + 0.4, 1.0)
		elif not is_equal_approx(_bank_pivot.scale.x, 1.0):
			# Ease back to normal scale when not displaying.
			_bank_pivot.scale = _bank_pivot.scale.lerp(Vector3.ONE,
				clampf(dt * 6.0, 0.0, 1.0))

	# ---- Courtship color saturation boost ----
	# Males get progressively more vivid as courtship intensity builds.
	# This is the "color pulse" from GOALS.md #11 — the fish visibly
	# brightens from "interested" to "climax flash" at spawn. Applied
	# by temporarily saturating the shader albedo on all mesh children.
	if _courtship_flare and sex == 0 and _courtship_intensity > 0.05:
		var sat_boost: float = _courtship_intensity * 0.30
		if _courtship_sync:
			sat_boost = 0.45

		# Ensure we duplicate materials before modifying their parameters,
		# otherwise we modify cached shared materials!
		if not _courtship_color_active:
			_courtship_color_active = true
			_last_courtship_color_step = -999  # force the first apply below
			for child in _cached_meshes:
				var mi: MeshInstance3D = child
				var m: Material = mi.material_override
				if m is ShaderMaterial:
					if not mi.has_meta("orig_mat"):
						mi.set_meta("orig_mat", m)
					mi.material_override = m.duplicate()

		# Quantize the boost to discrete steps and skip the per-voxel albedo
		# writes when it hasn't moved. _courtship_intensity only changes at tick
		# rate (10 Hz), so this drops the writes from per-voxel-per-motion-substep
		# (up to 16×/frame at high time-scale) to at most a handful per second,
		# with no visible difference. Mirrors _apply_maturity_color's step guard.
		var step: int = int(round(sat_boost * 50.0))
		if step != _last_courtship_color_step:
			_last_courtship_color_step = step
			for child in _cached_meshes:
				var mi: MeshInstance3D = child
				if mi.has_meta("orig_mat"):
					var orig_mat = mi.get_meta("orig_mat")
					if orig_mat is ShaderMaterial:
						var orig_color: Color = orig_mat.get_shader_parameter("albedo")
						var vivid: Color = orig_color.lightened(sat_boost * 0.3)
						vivid.s = minf(1.0, vivid.s + sat_boost)
						(mi.material_override as ShaderMaterial).set_shader_parameter("albedo", vivid)
	elif _courtship_color_active:
		# Restore original colors when courtship ends
		_courtship_color_active = false
		_last_courtship_color_step = -999
		for child in _cached_meshes:
			var mi: MeshInstance3D = child
			if mi.has_meta("orig_mat"):
				var orig = mi.get_meta("orig_mat")
				if orig != null:
					mi.material_override = orig
				mi.remove_meta("orig_mat")


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
	# Color maturity: smooth ramp from 0 (newborn, pale) to 1 (full adult
	# coloration). Fry start at 0, reach ~0.5 at juvenile stage boundary,
	# and hit 1.0 well before adulthood. The curve front-loads color gain
	# so the transition from "washed out" to "getting color" is visible
	# early and the last 30% of juvenile life looks nearly adult.
	_color_maturity = clampf(t / 0.28, 0.0, 1.0)


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
	# Walk all MeshInstance3D descendants and tint their material to the
	# faded color. Cheap since fish are small.
	for child in _cached_meshes:
		var mi: MeshInstance3D = child
		var m: Material = mi.material_override
		if m is ShaderMaterial:
			var orig_mat: Material = null
			if mi.has_meta("orig_mat"):
				orig_mat = mi.get_meta("orig_mat")
			if orig_mat == null:
				orig_mat = m
				mi.set_meta("orig_mat", orig_mat)
			
			var orig_color: Color = (orig_mat as ShaderMaterial).get_shader_parameter("albedo")
			var fade: Color = orig_color.lerp(Color8(120, 110, 100), 0.45)
			
			if mi.material_override == orig_mat:
				mi.material_override = (orig_mat as ShaderMaterial).duplicate()
			(mi.material_override as ShaderMaterial).set_shader_parameter("albedo", fade)


var _aged_applied: bool = false

# ---- Juvenile color deepening ----
# Tracks how far along the fry-→-adult color ramp this fish is. 0.0 = freshly
# hatched (pale silvery wash), 1.0 = full genome color. Updated every tick by
# _update_maturity(). _last_maturity_color_step tracks the last rounded step
# so we don’t re-walk the mesh tree every single frame (expensive on big fish).
var _color_maturity: float = 0.0
var _last_maturity_color_step: int = -1


func _apply_maturity_color() -> void:
	# Quantise to 10 steps so we only re-walk the mesh tree ~10 times over
	# the entire fry→juvenile→adult ramp, not every tick.
	var step: int = int(_color_maturity * 10.0)
	if step == _last_maturity_color_step:
		return
	_last_maturity_color_step = step
	# Desaturation factor: at _color_maturity 0 the fish is 45% washed
	# toward a pale silvery tone. At 1.0 it’s at full genome color.
	var desat: float = 0.45 * (1.0 - _color_maturity)
	var wash: Color = Color(0.75, 0.75, 0.78)
	for child in _cached_meshes:
		var mi: MeshInstance3D = child
		var m: Material = mi.material_override
		if m is ShaderMaterial:
			var orig_mat: Material = null
			if mi.has_meta("orig_mat"):
				orig_mat = mi.get_meta("orig_mat")
			if orig_mat == null:
				orig_mat = m
				mi.set_meta("orig_mat", orig_mat)
			
			var orig_color: Color = (orig_mat as ShaderMaterial).get_shader_parameter("albedo")
			var tinted: Color = orig_color.lerp(wash, desat)
			
			if mi.material_override == orig_mat:
				mi.material_override = (orig_mat as ShaderMaterial).duplicate()
			(mi.material_override as ShaderMaterial).set_shader_parameter("albedo", tinted)


func _restore_original_colors() -> void:
	for child in _cached_meshes:
		var mi: MeshInstance3D = child
		if mi.has_meta("orig_mat"):
			var orig = mi.get_meta("orig_mat")
			if orig != null:
				mi.material_override = orig
			mi.remove_meta("orig_mat")

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


func _local_clearance_push(neighbors: Array, plants: Array) -> Vector3:
	var push := Vector3.ZERO
	const FISH_PERSONAL_SPACE: float = 0.26
	const PLANT_CLEARANCE: float = 0.20
	var fish_r2: float = FISH_PERSONAL_SPACE * FISH_PERSONAL_SPACE
	var plant_r2: float = PLANT_CLEARANCE * PLANT_CLEARANCE
	for n in neighbors:
		if not (n is Fish):
			continue
		var nf: Fish = n
		var d: Vector3 = position - nf.position
		var d2: float = d.length_squared()
		if d2 < 1e-6 or d2 >= fish_r2:
			continue
		push += d.normalized() * (FISH_PERSONAL_SPACE - sqrt(d2)) * 1.9
	for p in plants:
		if not is_instance_valid(p):
			continue
		var to_p: Vector3 = position - p._world_pos
		to_p.y *= 0.55
		var d2p: float = to_p.length_squared()
		if d2p < 1e-6 or d2p >= plant_r2:
			continue
		push += to_p.normalized() * (PLANT_CLEARANCE - sqrt(d2p)) * 1.3
	return push


func _hardscape_clearance_push() -> Vector3:
	if sim == null:
		return Vector3.ZERO
	var root: Variant = sim.get("hardscape_root")
	if root == null or not (root is Node3D):
		return Vector3.ZERO
	const CLEAR_R: float = 0.26
	var clear_r2: float = CLEAR_R * CLEAR_R
	var push := Vector3.ZERO
	var count: int = 0
	for h in (root as Node3D).get_children():
		if not is_instance_valid(h):
			continue
		var d: Vector3 = position - h.global_position
		d.y *= 0.45
		var d2: float = d.length_squared()
		if d2 >= clear_r2:
			continue
		if d2 < 1e-6:
			d = Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1))
			if d.length_squared() < 1e-6:
				d = Vector3(1.0, 0.0, 0.0)
			d2 = maxf(d.length_squared(), 1e-6)
		push += d.normalized() * (CLEAR_R - sqrt(d2)) * 1.4
		count += 1
		if count >= 10:
			break
	return push


func _find_breeding_partner(neighbors: Array) -> Fish:
	# Same-species, opposite sex, available, healthy, within 3 units.
	# Among valid candidates, prefer the one with the best *attractiveness*
	# score = local fitness + lower distance bonus + breed_count bias.
	# This strengthens selection pressure: robust, less-stressed, well-fed
	# fish pair more often and pass those traits forward.
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
		# Assortative mating: lineages prefer their own subspecies.
		if subspecies_id != "" and f.subspecies_id != "" and subspecies_id != f.subspecies_id:
			if randf() > 0.06:
				continue
		if f.hunger > 0.5 or f.energy < 0.55 or f.stress > 0.4:
			continue
		var d2: float = f.position.distance_squared_to(position)
		if d2 > 9.0:
			continue
		# Lower distance is better, more breed_count is better, and fitter
		# candidates have a stronger mate-choice advantage.
		var fitness: float = _mate_fitness_score(f)
		var score: float = -d2 * 0.6 + sqrt(float(f.breed_count)) * 0.4 + fitness * 2.5
		if score > best_score:
			best_score = score
			best = f
	return best


func _mate_fitness_score(f: Fish) -> float:
	var stress_score: float = 1.0 - clampf(f.stress, 0.0, 1.0)
	var hunger_score: float = 1.0 - clampf(f.hunger, 0.0, 1.0)
	var energy_score: float = clampf(f.energy, 0.0, 1.0)
	var size_score: float = clampf(
		f.growth_factor / maxf(0.01, f.max_growth), 0.0, 1.0)
	var vivid_score: float = (_color_vibrancy(f.base_color)
		+ _color_vibrancy(f.accent_color)) * 0.5
	var habitat_score: float = _habitat_trait_match_score(f)
	return stress_score * 0.35 + energy_score * 0.25 + hunger_score * 0.20 \
		+ size_score * 0.10 + vivid_score * 0.03 + habitat_score * 0.07


func _color_vibrancy(c: Color) -> float:
	var cmax: float = maxf(c.r, maxf(c.g, c.b))
	var cmin: float = minf(c.r, minf(c.g, c.b))
	if cmax <= 0.0001:
		return 0.0
	return clampf((cmax - cmin) / cmax, 0.0, 1.0)


func _habitat_trait_match_score(f: Fish) -> float:
	if sim == null:
		return 0.5
	var world: Node = sim.get_parent()
	if world == null or not world.has_method("habitat_profile_at"):
		return 0.5
	var hv: Variant = world.habitat_profile_at(f.position)
	if not (hv is Dictionary):
		return 0.5
	var h: Dictionary = hv
	var cover: float = float(h.get("cover", 0.0))
	var edge: float = float(h.get("edge", 0.5))
	var depth: float = float(h.get("depth", 0.5))
	var score: float = 0.5
	if cover > 0.45:
		if f.armor_plates:
			score += 0.16
		if f.has_barbels:
			score += 0.09
		if f.body_shape == "compressed" or f.body_shape == "anguilliform":
			score += 0.08
	if edge < 0.35:
		if f.body_shape == "fusiform":
			score += 0.10
		if f.schooling_strength > 0.9:
			score += 0.10
	if depth > 0.65 and f.mouth_orientation == 1:
		score += 0.12
	elif depth < 0.35 and f.mouth_orientation == -1:
		score += 0.12
	return clampf(score, 0.0, 1.0)


func _short_subspecies_tag(id: String) -> String:
	if id == "" or id == species:
		return ""
	var parts: PackedStringArray = id.split(".")
	var tail: String = parts[parts.size() - 1] if parts.size() > 0 else id
	return tail.right(4)


func _founder_divergence_score(genome: Dictionary) -> int:
	var lib = get_tree().root.get_node_or_null("TankConfig")
	if lib == null or not lib.SPECIES_LIBRARY.has(species):
		return 0
	var template: Dictionary = lib.SPECIES_LIBRARY[species].get("genome", {})
	var score: int = 0
	if int(genome.get("tail_shape", 0)) != int(template.get("tail_shape", 0)):
		score += 1
	if bool(genome.get("has_barbels", false)) != bool(template.get("has_barbels", false)):
		score += 1
	if bool(genome.get("armor_plates", false)) != bool(template.get("armor_plates", false)):
		score += 1
	if bool(genome.get("snout_pointed", false)) != bool(template.get("snout_pointed", false)):
		score += 1
	if String(genome.get("body_shape", "fusiform")) != String(template.get("body_shape", "fusiform")):
		score += 1
	if absf(float(genome.get("body_elongation", 1.0))
			- float(template.get("body_elongation", 1.0))) > 0.25:
		score += 1
	if absf(float(genome.get("body_depth_factor", 1.0))
			- float(template.get("body_depth_factor", 1.0))) > 0.35:
		score += 1
	if absf(float(genome.get("eye_size_factor", 1.0))
			- float(template.get("eye_size_factor", 1.0))) > 0.35:
		score += 1
	if absf(float(genome.get("jaw_claw_size", 0.0))
			- float(template.get("jaw_claw_size", 0.0))) > 0.25:
		score += 1
	if absf(float(genome.get("size_potential", 1.0))
			- float(template.get("size_potential", 1.0))) > 0.28:
		score += 1
	return score


func _subspecies_signature(genome: Dictionary) -> String:
	var q_e: int = int(round(clampf(float(genome.get("body_elongation", 1.0)), 0.55, 1.7) * 10.0))
	var q_d: int = int(round(clampf(float(genome.get("body_depth_factor", 1.0)), 0.55, 1.9) * 10.0))
	var q_eye: int = int(round(clampf(float(genome.get("eye_size_factor", 1.0)), 0.5, 1.8) * 10.0))
	var q_claw: int = int(round(clampf(float(genome.get("jaw_claw_size", 0.0)), 0.0, 1.2) * 10.0))
	return "%s%d%d%d%d%d%s%s%d" % [
		String(genome.get("body_shape", "f")).left(1),
		int(genome.get("tail_shape", 0)),
		1 if bool(genome.get("has_barbels", false)) else 0,
		1 if bool(genome.get("armor_plates", false)) else 0,
		q_e,
		q_d,
		str(q_eye),
		"h" if bool(genome.get("snout_pointed", false)) else "n",
		q_claw,
	]


func _derive_subspecies_id(partner: Fish, child_genome: Dictionary) -> String:
	var base: String = species
	var a: String = subspecies_id if subspecies_id != "" else species
	var b: String = partner.subspecies_id if partner.subspecies_id != "" else species
	if a == b and randf() < 0.92:
		base = a
	elif randf() < 0.55:
		base = a
	else:
		base = b
	var divergence: int = _founder_divergence_score(child_genome)
	if divergence >= 3:
		return "%s.%s" % [species, _subspecies_signature(child_genome)]
	return base


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
@warning_ignore("shadowed_variable")
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
		(body_elongation + partner.body_elongation) * 0.5 + randf_range(-0.10, 0.10),
		0.65, 1.55)
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
	var new_size_potential: float = clampf(
		(size_potential + partner.size_potential) * 0.5 + randf_range(-0.12, 0.15),
		0.6, 2.4)
	var new_jaw_claw: float = clampf(
		(jaw_claw_size + partner.jaw_claw_size) * 0.5 + randf_range(-0.12, 0.18),
		0.0, 1.2)
	# Pattern: usually inherits from one parent, small chance to mutate to
	# a different pattern entirely.
	var new_pattern: int = pattern_type if randf() < 0.5 else partner.pattern_type
	if randf() < 0.06:
		new_pattern = randi() % 4
	# Dots: average then small jitter, clamped 0-4.
	var new_dots: int = clampi(
		int((color_dot_count + partner.color_dot_count) * 0.5 + randf_range(-1.0, 1.0)),
		0, 4)
	# Previously species-locked silhouette/lifestyle genes can now drift at
	# low rates, letting lineages branch into visibly new forms over long runs.
	var prey_pressure: float = 0.0
	if sim != null:
		var fish_n: float = maxf(1.0, float(sim.fish.size()))
		var shrimp_n: float = float(sim.shrimp.size())
		var snail_n: float = 0.0
		var sn_root: Variant = sim.get("snails_root")
		if sn_root != null and is_instance_valid(sn_root):
			snail_n = float((sn_root as Node).get_child_count())
		prey_pressure = clampf((shrimp_n * 0.7 + snail_n * 0.9) / (fish_n * 3.2), 0.0, 1.0)
	var predator_mut_boost: float = prey_pressure * 0.08
	var new_snail_predator: bool = (snail_predator if randf() < (0.985 - predator_mut_boost)
		else (partner.snail_predator if randf() < 0.5 else not snail_predator))
	var new_shrimp_predator: bool = (shrimp_predator if randf() < (0.985 - predator_mut_boost)
		else (partner.shrimp_predator if randf() < 0.5 else not shrimp_predator))
	var new_algae_grazer: bool = (algae_grazer if randf() < 0.985
		else (partner.algae_grazer if randf() < 0.5 else not algae_grazer))
	var new_livebearer: bool = (is_livebearer if randf() < 0.995
		else partner.is_livebearer)
	var new_guards_clutch: bool = (guards_clutch if randf() < 0.97
		else (partner.guards_clutch if randf() < 0.5 else not guards_clutch))
	var new_adipose_fin: bool = (adipose_fin if randf() < 0.985
		else (partner.adipose_fin if randf() < 0.5 else not adipose_fin))
	var new_snout_pointed: bool = (snout_pointed if randf() < 0.985
		else (partner.snout_pointed if randf() < 0.5 else not snout_pointed))
	var new_body_shape: String = body_shape if randf() < 0.86 else partner.body_shape
	if randf() < 0.04:
		var shapes: Array[String] = ["fusiform", "compressed", "globiform", "anguilliform"]
		new_body_shape = shapes[randi() % shapes.size()]
	var new_mouth_orientation: int = (mouth_orientation if randf() < 0.93
		else partner.mouth_orientation if randf() < 0.5
		else clampi(mouth_orientation + (1 if randf() < 0.5 else -1), -1, 1))
	# Predator-branch morphology pressure. As prey pressure rises, predator
	# lineages get stronger selection toward specialized mouth/body forms.
	if new_snail_predator:
		new_mouth_orientation = clampi(
			maxi(new_mouth_orientation, 0)
			+ (1 if randf() < 0.45 + prey_pressure * 0.30 else 0),
			-1, 1)
		new_snout_pointed = new_snout_pointed or randf() < 0.58 + prey_pressure * 0.18
		new_head = clampf(new_head + randf_range(0.02, 0.07), 0.7, 1.5)
		if randf() < 0.50 + prey_pressure * 0.22:
			new_body_shape = "anguilliform"
	if new_shrimp_predator:
		if not new_snail_predator:
			new_mouth_orientation = clampi(
				mini(new_mouth_orientation, 0)
				- (1 if randf() < 0.32 + prey_pressure * 0.28 else 0),
				-1, 1)
		new_elong = clampf(new_elong + randf_range(0.01, 0.06), 0.85, 1.25)
		if randf() < 0.42 + prey_pressure * 0.20:
			new_body_shape = "fusiform"
	if new_snail_predator and new_shrimp_predator and randf() < 0.42 + prey_pressure * 0.25:
		new_body_shape = "globiform"
		new_snout_pointed = true
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
		# Marking color inherits the same way - keeps tetra bands / rasbora
		# wedges / gourami flanks coherent down a lineage.
		"marking_color": (marking_color if _marking_color_set else accent_color).lerp(
			partner.marking_color if partner._marking_color_set else partner.accent_color,
			mix).lerp(Color(randf(), randf(), randf()), color_muta * 0.5),
		"adult_voxel_scale": new_size,
		"size_potential": new_size_potential,
		"max_growth": clampf((max_growth + partner.max_growth) * 0.5 * randf_range(0.94, 1.06), 1.05, 2.8),
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
		"parent_lineage": "%s & %s" % [fish_name, partner.fish_name],
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
		"mouth_orientation": new_mouth_orientation,
		"tail_shape": (tail_shape if randf() < 0.94
			else partner.tail_shape if randf() < 0.5
			else randi() % 4),
		"eye_size_factor": clampf((eye_size_factor + partner.eye_size_factor) * 0.5
			+ randf_range(-0.10, 0.10), 0.55, 1.7),
		"ventral_profile": clampf((ventral_profile + partner.ventral_profile) * 0.5
			+ randf_range(-0.08, 0.08), 0.55, 1.7),
		"back_arch": clampf((back_arch + partner.back_arch) * 0.5
			+ randf_range(-0.08, 0.08), 0.65, 1.6),
		# Lifestyle traits can mutate slowly to support niche shifts.
		"snail_predator": new_snail_predator,
		"shrimp_predator": new_shrimp_predator,
		"algae_grazer": new_algae_grazer,
		"is_livebearer": new_livebearer,
		"guards_clutch": new_guards_clutch,
		"sterile": sterile or partner.sterile or (randf() < 0.01),
		"viable": not (sterile or partner.sterile or (species != partner.species) or (randf() < 0.03)),
		# Silhouette traits. Most drift continuously; select booleans + shape
		# now mutate rarely to create emergent long-run morphology splits.
		"anal_fin_length_factor": clampf(
			(anal_fin_length_factor + partner.anal_fin_length_factor) * 0.5
			+ randf_range(-0.10, 0.10), 0.3, 2.0),
		"adipose_fin": new_adipose_fin,
		"snout_pointed": new_snout_pointed,
		"body_shape": new_body_shape,
		"jaw_claw_size": new_jaw_claw,
		# Ornamentation traits stay in the lineage with rare flips so a
		# bar-edged or eye-spotted founder line keeps its look but can drift.
		"bar_edged": (bar_edged if randf() < 0.97
			else (partner.bar_edged if randf() < 0.5 else not bar_edged)),
		"eye_spot": (eye_spot if randf() < 0.97
			else (partner.eye_spot if randf() < 0.5 else not eye_spot)),
		"ventral_feelers": (ventral_feelers if randf() < 0.98
			else (partner.ventral_feelers if randf() < 0.5 else not ventral_feelers)),
		"finnage": clampf((finnage + partner.finnage) * 0.5
			+ randf_range(-0.08, 0.08), 1.0, 2.2),
		"labyrinth_breather": (labyrinth_breather if randf() < 0.99
			else partner.labyrinth_breather),
		"organism_type": "fish",
		"parent_keys": SpeciesLibrary.parent_keys_for_breeding([
			get_saved_genome(), partner.get_saved_genome(),
		]),
	}
	g["subspecies_id"] = _derive_subspecies_id(partner, g)
	if sim != null:
		EvolutionPressure.apply_fish_offspring(
			g, EvolutionPressure.sample_from_sim(sim, position))
	return g


# ---- Save / load ----

# Convert all Color-valued genome entries to JSON-friendly Arrays. Used both
# when saving and as a static utility from the loader side.
static func _genome_to_json(g: Dictionary) -> Dictionary:
	var out: Dictionary = g.duplicate(true)
	for key in ["base_color", "accent_color", "tail_color", "marking_color"]:
		if out.has(key) and out[key] is Color:
			out[key] = SaveHelpers.color_to_array(out[key])
	return out


static func _genome_from_json(g: Dictionary) -> Dictionary:
	var out: Dictionary = g.duplicate(true)
	for key in ["base_color", "accent_color", "tail_color", "marking_color"]:
		if out.has(key) and out[key] is Array:
			out[key] = SaveHelpers.array_to_color(out[key])
	return out


func to_save_dict() -> Dictionary:
	return {
		"id": id,
		"pos": SaveHelpers.vec3_to_array(global_position),
		"genome": _genome_to_json(_saved_genome),
		# Dynamic state. velocity + heading are derived from each other in
		# the locomotion code, so we save both for fidelity; speed is the
		# magnitude. partner_id is resolved post-load by SimDriver._resolve_refs.
		"age": age,
		"hunger": hunger,
		"energy": energy,
		"stress": stress,
		"maturity": int(maturity),
		"velocity": SaveHelpers.vec3_to_array(velocity),
		"heading": SaveHelpers.vec3_to_array(heading),
		"speed": speed,
		"current_mode": int(current_mode),
		"breed_cooldown": breed_cooldown,
		"nibble_cooldown": nibble_cooldown,
		"breed_count": breed_count,
		"growth_factor": growth_factor,
		"heading_offset": SaveHelpers.vec3_to_array(heading_offset),
		"partner_id": _id_of(partner),
		"court_timer": court_timer,
		"brooding_at": SaveHelpers.vec3_to_array(brooding_at),
		"brooding_remaining": brooding_remaining,
		"burst_remaining": burst_remaining,
		"gestation_progress": _gestation_progress,
		"gestation_genome": _genome_to_json(_gestation_genome),
		"home": [home_x, home_y, home_z],
	}


# Restore a fish from a saved dict. Caller has already add_child'd this node
# and assigned its global_position. partner ref is resolved by SimDriver in
# a second pass after every entity has its id assigned.
func apply_save_dict(d: Dictionary) -> void:
	id = String(d.get("id", id))
	# Replay init_genome with the saved genome — this re-derives all the
	# phenotype fields including the dimorphic transformation.
	var g: Dictionary = _genome_from_json(d.get("genome", {}))
	init_genome(g)
	# Patch dynamic state AFTER init so init_genome doesn't clobber it.
	age = float(d.get("age", 0.0))
	hunger = float(d.get("hunger", 0.3))
	energy = float(d.get("energy", 1.0))
	stress = float(d.get("stress", 0.0))
	maturity = int(d.get("maturity", MATURITY_FRY))
	velocity = SaveHelpers.array_to_vec3(d.get("velocity", []), Vector3.ZERO)
	heading = SaveHelpers.array_to_vec3(d.get("heading", []), Vector3.FORWARD)
	speed = float(d.get("speed", 0.0))
	current_mode = int(d.get("current_mode", Mode.CRUISE)) as Mode
	breed_cooldown = float(d.get("breed_cooldown", 0.0))
	nibble_cooldown = float(d.get("nibble_cooldown", 0.0))
	breed_count = int(d.get("breed_count", 0))
	growth_factor = float(d.get("growth_factor", 1.0))
	heading_offset = SaveHelpers.array_to_vec3(d.get("heading_offset", []), Vector3.ZERO)
	court_timer = float(d.get("court_timer", 0.0))
	brooding_at = SaveHelpers.array_to_vec3(d.get("brooding_at", []), Vector3.ZERO)
	brooding_remaining = float(d.get("brooding_remaining", 0.0))
	burst_remaining = float(d.get("burst_remaining", 0.0))
	_gestation_progress = float(d.get("gestation_progress", 0.0))
	_gestation_genome = _genome_from_json(d.get("gestation_genome", {}))
	var home: Array = d.get("home", [])
	if home.size() >= 3:
		home_x = float(home[0])
		home_y = float(home[1])
		home_z = float(home[2])
	# Transient refs are NOT restored — they're cheap to re-pick next tick
	# and trying to resolve them across saves is fragile (the plant might
	# have just been nibbled to death). Clear them so the AI starts fresh.
	target_plant = null


static func _id_of(n: Node) -> String:
	if n == null or not is_instance_valid(n):
		return ""
	return String(n.get("id"))


# Second-pass ref resolution. Called by SimDriver._resolve_refs after every
# entity has been spawned and registered in id_map. Maps the saved partner_id
# string back into a Fish reference.
func resolve_refs(saved: Dictionary, id_map: Dictionary) -> void:
	var pid: String = String(saved.get("partner_id", ""))
	if pid != "" and id_map.has(pid):
		var p: Node = id_map[pid]
		if p is Fish and is_instance_valid(p):
			partner = p


func _update_pheromone_trail() -> void:
	var is_receptive: bool = (
		maturity == MATURITY_ADULT
		and sex == 1
		and breed_cooldown <= 0.0
		and hunger < 0.5
		and energy > 0.65
		and stress < 0.4
		and partner == null
		and not _dying
	)

	if is_receptive:
		if _pheromone_trail == null:
			_pheromone_trail = GPUParticles3D.new()
			_pheromone_trail.amount = 8
			_pheromone_trail.lifetime = 2.5
			_pheromone_trail.local_coords = false

			var proc_mat := ParticleProcessMaterial.new()
			proc_mat.gravity = Vector3(0, -0.05, 0)
			proc_mat.direction = Vector3.ZERO
			proc_mat.spread = 180.0
			proc_mat.initial_velocity_min = 0.02
			proc_mat.initial_velocity_max = 0.1
			proc_mat.scale_min = 0.3
			proc_mat.scale_max = 0.8
			proc_mat.color = Color(1.0, 0.8, 0.65, 0.25)

			_pheromone_trail.process_material = proc_mat

			var quad := QuadMesh.new()
			quad.size = Vector2(0.06, 0.06)

			var mat := StandardMaterial3D.new()
			mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
			mat.vertex_color_use_as_albedo = true
			mat.billboard_mode = StandardMaterial3D.BILLBOARD_PARTICLES

			quad.material = mat
			_pheromone_trail.draw_passes = 1
			_pheromone_trail.set_draw_pass_mesh(0, quad)

			_pheromone_trail.position = Vector3(0, 0, 0.3)
			add_child(_pheromone_trail)
			_pheromone_trail.emitting = true
	else:
		if _pheromone_trail != null:
			_pheromone_trail.queue_free()
			_pheromone_trail = null
