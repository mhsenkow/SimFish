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

# Preloaded so parse works even before the editor has populated the
# global class_name registry — see ai_director.gd for the same trick.
const CreatureNaming = preload("res://scripts/creature_naming.gd")
const FaunaVoxelBuilder = preload("res://scripts/fauna_voxel_builder.gd")

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
const SURFACE_GULP_O2: float = 0.32
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
# Sexual dimorphism strength 0..1 (heritable). 0 = monomorphic (both sexes look
# the same — the default, so existing fish are unchanged). Higher values make
# males showier (brighter, longer-finned) and females fuller + drabber. When the
# genome leaves it unset it is derived from reproductive strategy (livebearers,
# labyrinth fish and clutch-guarders are the dimorphic groups).
var dimorphism: float = 0.0

# ---- Lineage ----
var generation: int = 0   # max(parents) + 1 on birth; founders are 0
var fish_name: String = ""
var name_source: String = "offline"   # "ai" if AIDirector minted it, else "offline"
var parent_lineage: String = "Founders"

# ---- Personality ----
# Five trait scalars in [0,1]. Set on init_genome via CreatureNaming.roll_personality
# (or inherited from parents on breeding). Tunes existing behavior knobs at
# read time — keeps the per-tick cost flat. Saved/loaded as a flat dict.
#   boldness    -> nearer to glass / less startle, more dart_chance
#   curiosity   -> longer pause-and-look windows, more novelty interest
#   sociability -> tighter schooling, more cleaning-station seeking
#   gluttony    -> stronger food bias, longer feeding hover
#   calm        -> slower base wag freq, less spontaneous stress
var personality: Dictionary = {}

# ---- Lifetime journal ----
# Aggregate stats that survive saves. Surface on hover; the player builds
# attachment by watching numbers grow next to a named fish. Incremented in
# the existing event hooks (eat, breed, fight win, age tick).
#   meals_eaten        every successful nibble/pellet bite
#   offspring          every successful breed event
#   fights_won         every territorial chase where this fish was the chaser
#   age_peak_s         max age reached (in case of senescence rollback via food)
#   longest_friend_id  partner with the most shared time (set on breed pairing)
#   birth_unix         wall-clock seconds at hatch (Time.get_unix_time_from_system)
var bio: Dictionary = {}

# ---- Persistent memory ----
# feed_heatmap: tiny 4×4×4=64 scalar field of "I have eaten here before"
#   weights. Sampled on food search to bias toward proven spots. Decays
#   slowly (5% per minute) so abandoned spots fade. Persisted across saves
#   so a returning fish remembers its favorite corner.
var feed_heatmap: PackedFloat32Array = PackedFloat32Array()
const FEED_HEATMAP_SIZE: int = 4   # 4³ = 64 cells; cheap, plenty of resolution
# grudges: id (other fish stable id) -> remaining seconds. Set on chase
#   events; the predator-avoidance code reads this to give wider berth to
#   the specific bully rather than the bully's whole species.
var grudges: Dictionary = {}
# habituated: stimulus key (string) -> novelty 0..1. 1 = never seen, 0 = bored.
#   Used by the look-at-glass and novelty-pause code so repeated exposures
#   stop drawing attention.
var habituated: Dictionary = {}

# ---- Dominance ----
# Per-fish rank within its species — drifts toward 0.5 (neutral) but updates
# on territorial wins/losses. Higher rank gets first dibs on feed spots and
# breeding partners. Cheap: only updates when a fight resolves.
var rank_within_species: float = 0.5

# ---- Novelty: regions visited ----
# Tiny 4×4×4 bitmap (64 cells, 8 bytes) tracking tank regions this fish
# has been in. When entering an unvisited cell, briefly slow + face the
# new area before resuming. Personality.curiosity tunes how strongly
# unvisited reads as "novel" (and therefore how long the pause lasts).
# Cleared every ~30 minutes of game time so the fish eventually rediscovers
# its tank — fresh play after a long break feels novel again.
const NOVELTY_GRID: int = 4
var visited_regions: PackedByteArray = PackedByteArray()
var _novelty_pause_remaining: float = 0.0
var _novelty_reset_timer: float = 0.0

# ---- Gaze contagion ----
# When this fish is actively investigating something (the glass, a novel
# food cluster), it sets _interest_target to that world position and
# _interest_remaining > 0. Neighbors read these in their cruise tier and
# pick up a small additional steering pull toward the SAME point — so
# when one fish swims over to inspect the player, three more follow a
# beat later. Decays automatically; no per-frame book-keeping needed.
var _interest_target: Vector3 = Vector3.ZERO
var _interest_remaining: float = 0.0

# ---- Gaze target ----
# When the tick code spots a fast-moving neighbor, it sets a target head
# yaw angle (radians) here. The per-frame saccade reader prefers this
# value over a random twitch when it's recent, so a passing fish actually
# turns to look. Decays back to zero in the same lerp as random saccades.
var _gaze_yaw: float = 0.0
var _gaze_remaining: float = 0.0

# ---- Perf: cached autoload refs + decay throttle ----
# Caching the AIDirector node ref at _ready saves the get_node_or_null
# lookup on every tick path that samples intent drift. With 30+ fish at
# 10 Hz that was ~900 lookups/sec for what's almost always a const.
var _ai_director_cached: Node = null
# Decays (grudge, habituation, feed_heatmap, age_peak) don't need to fire
# every 10 Hz tick — every 5 sim-seconds is imperceptible to the player
# and 50× cheaper. _decay_throttle_t counts down; when it hits 0 we run
# the decays in bulk for the elapsed window and reset.
const DECAY_THROTTLE_PERIOD: float = 5.0
var _decay_throttle_t: float = 0.0
# Player-glance + novelty checks throttled similarly — every ~1s.
# The cached glance values are reused between samples so the steering
# pull still applies smoothly each tick.
const GLANCE_CHECK_PERIOD: float = 1.0
var _glance_check_t: float = 0.0
var _cached_glance_strength: float = 0.0
var _cached_glance_point: Vector3 = Vector3.ZERO
# Cached AI intent drift — refreshed on the throttle, applied every tick.
var _cached_ai_drift: Vector3 = Vector3.ZERO
var _ai_drift_check_t: float = 0.0
const AI_DRIFT_CHECK_PERIOD: float = 2.0

# ---- Inner life (the "sentience" layer) ----
# A unified, lightweight cognitive/emotional state that several behaviors and
# the animation layer read so a fish reads as a continuous individual mind
# instead of a per-tick rule evaluator. All scalars are cheap; the heavy
# lifting is reusing the steering hooks already present in the cruise tier.
#
# mood: emotional valence in [-1,1]. <0 = unhappy/anxious, >0 = content/curious.
#   Drifts every tick from satisfaction (low hunger, low stress, company,
#   good water) toward a personality-anchored baseline. Reads out as color
#   vividness, fin spread, swim cadence.
var mood: float = 0.2
# curiosity_drive: an appetite for novelty in [0,1]. Builds when nothing
#   interesting happens; discharged by investigating. Bored fish go exploring.
var curiosity_drive: float = 0.0
# spooked: lingering fear in [0,1] that decays slowly after a scare so the
#   fish stays jumpy and hugs cover for a while, instead of resetting instantly.
var spooked: float = 0.0
# familiarity: how much THIS fish trusts the player, in [0,1]. Rises when fed
#   near the camera; bold fish learn fast, shy fish stay wary. Makes the tank
#   feel like it knows you. Persisted across saves.
var familiarity: float = 0.0
# A committed short-term goal so the fish doesn't re-decide every frame. The
# goal_kind string is diagnostic; goal_point is where it wants to go; goal_timer
# is how long it stays committed before it can pick something new.
var goal_kind: String = ""
var goal_point: Vector3 = Vector3.ZERO
var goal_timer: float = 0.0
var _goal_pick_cooldown: float = 0.0
# Working memory: a tiny ring of recent salient events (bullied/fed/saw player/
# startled). Each entry is {kind, pos, t} with t a countdown. Biases goal
# selection ("I found food over there a moment ago").
var memory: Array = []
const MEMORY_MAX: int = 6
# Reaction shot: brief freeze-and-orient when something surprising appears.
var _reaction_remaining: float = 0.0
var _reaction_point: Vector3 = Vector3.ZERO
# Idle fidget: a queued micro-gesture (shimmy / flash / yawn) and its timer.
var _fidget_kind: int = 0   # 0 none, 1 shimmy, 2 yawn-gape, 3 substrate-flash
var _fidget_remaining: float = 0.0
var _fidget_cooldown: float = 0.0
# Social bonds: other fish ids this individual has chosen to associate with,
# id -> affinity [-1,1] (>0 friend, <0 rival). Built from repeated co-schooling
# and grudges. Cheap to maintain (updated on the decay throttle).
var bonds: Dictionary = {}
# Leadership: a transient role within the local school. >0.5 means this fish is
# currently leading; followers weight cohesion toward it. Hands off over time.
var lead_score: float = 0.0
# Patrol anchors: 0-2 learned favorite spots the fish loops between, instead of
# pure random home drift. Each is a Vector3; _patrol_idx selects the active one.
var patrol_anchors: Array = []
var _patrol_idx: int = 0
var _patrol_retarget_t: float = 0.0
# Relief/escalation tracking for chemistry: remember last-tick chem stress so a
# sudden improvement reads as visible relief and a sudden worsening as alarm.
var _prev_chem_stress: float = 0.0
var _relief_pulse: float = 0.0
# Sleep: a real rest state at night for diurnal species (and inverted for
# nocturnal). Distinct from the cosmetic tilt — lowers sensing + speed and
# parks the fish at a chosen nook until disturbed.
var _asleep: bool = false
var _sleep_nook: Vector3 = Vector3.ZERO
var _sleep_have_nook: bool = false
# Eye highlight target (local yaw the eye-dot looks toward) and blink timer.
var _eye_look: float = 0.0
var _blink_t: float = 0.0
var _blink_remaining: float = 0.0
# Cached content shimmer + breathing load for the animation layer.
var _breath_load: float = 1.0


# ---- State (mutable) ----
var age: float = 0.0
var hunger: float = 0.3        # 0 = full, 1 = starving
var energy: float = 1.0
var stress: float = 0.0
# Nitrite "brown-blood" effect (#28): high nitrite binds the blood so the fish
# perceives less O2 than is dissolved — it gulps at the surface even when the
# water is well-oxygenated. Recomputed each tick from the nitrite reading.
var _chem_o2_penalty: float = 0.0
# Staggered maturation / senescence (#39): a small per-individual lifespan
# offset so siblings born in the same clutch don't all mature and die on the
# exact same tick — smooths the demographic into a believable age pyramid
# instead of synchronized cohort die-offs.
var _life_jitter: float = randf_range(-0.12, 0.15)
# Rest debt (#84): night disturbances accumulate fatigue; a constantly-startled
# fish is sluggish the next day until it catches up on sleep.
var _rest_debt: float = 0.0
# Per-individual growth variance (#89): produces a natural size hierarchy and
# the occasional struggling runt within a single clutch.
var _growth_variance: float = randf_range(0.86, 1.14)
# Personality drift (#82): surviving a real fright leaves a lasting mark — the
# fish grows a little warier over its life.
var _scarred: bool = false
# Mate loyalty (#83): id of the last partner, so a pair preferentially re-bonds
# across spawns instead of re-rolling a random mate each cycle.
var _mate_id: String = ""
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

# ---- Expanded morphology (heritable) — widens real-species coverage ----
# Each defaults to "no change from the original silhouette" so existing
# genomes and saved tanks render byte-for-byte as before. They drift through
# produce_offspring_genome exactly like the older skeleton genes.
#  - body_width_factor   lateral width → _bank_pivot.scale.x. The missing
#                        cross-section axis: <1 = slab-thin (laterally
#                        compressed), >1 = flat-and-wide (rays, flatfish,
#                        plecos, hillstream loaches, gobies).
#  - snout_length_factor 0.5..2.5; long pointed snouts (gar, needlefish,
#                        pipefish, elephantnose).
#  - dorsal_length_factor 0.5..2.2; long-based dorsal fin running down the
#                        back (plecos, bichirs, oscars, knifefish).
#  - nuchal_hump         0..1; forehead / nape bulge (flowerhorn, severum,
#                        humphead wrasse, mature male cichlids).
#  - second_dorsal       spiny + soft dorsal — most perciforms (gobies,
#                        cichlids, bass, the majority of marine fish).
#  - ventral_sucker      ventral disc / sucker mouth (plecos, gobies,
#                        hillstream loaches, remora).
#  - barbel_count        whisker count. -1 sentinel = derive from has_barbels
#                        (0 or 4); 4/6/8 give catfish, 4 gives loaches.
var body_width_factor: float = 1.0
var snout_length_factor: float = 1.0
var dorsal_length_factor: float = 1.0
var nuchal_hump: float = 0.0
var second_dorsal: bool = false
var ventral_sucker: bool = false
var barbel_count: int = -1
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
# Wood-grazer — clings to driftwood + rasps biofilm. Bristlenose plecos
# express this; the AI tier below it biases the fish to spend time
# near hardscape voxels (driftwood, stones) instead of cruising the
# water column.
var wood_grazer: bool = false
# Bioluminescent — body voxels glow softly when the tank is dark.
# Heritable, rare (~3% of new fish). Visually the fish reads as a deep-
# sea lanternfish drifting at night; harmless during the day (no glow).
var is_bioluminescent: bool = false
var _biolum_t: float = 0.0

# Acclimation buffer — new fish (just dropped in via fish store, or
# newly hatched) get ACCLIMATION_DURATION seconds of stress immunity
# while they adjust to the tank. After that, full ammonia / nitrite
# stress accrual kicks in. Real-world quarantine analog.
const ACCLIMATION_DURATION: float = 120.0
var _acclimation_remaining: float = ACCLIMATION_DURATION

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
		tags.append(["F", "R", "L", "S", "C", "P"][clampi(tail_shape, 0, 5)])
	if (not not template.get("has_barbels", false)) != has_barbels:
		tags.append("B" if has_barbels else "b")
	if (not not template.get("armor_plates", false)) != armor_plates:
		tags.append("A" if armor_plates else "a")
	if int(template.get("mouth_orientation", 0)) != mouth_orientation:
		tags.append(["U", "M", "D"][clampi(mouth_orientation + 1, 0, 2)])
	# Body-plan shift away from the species template gets a two-letter code.
	if String(template.get("body_shape", "fusiform")) != body_shape:
		var shape_tag: Dictionary = {
			"compressed": "Kp", "globiform": "Gb", "anguilliform": "An",
			"depressed": "Fl", "sagittiform": "Pk", "ribbon": "Rb",
		}
		if shape_tag.has(body_shape):
			tags.append(shape_tag[body_shape])
	if (not not template.get("second_dorsal", false)) != second_dorsal and second_dorsal:
		tags.append("2D")
	if (not not template.get("ventral_sucker", false)) != ventral_sucker and ventral_sucker:
		tags.append("Su")
	# Continuous trait drift past LARGE thresholds - founders with normal
	# phenotype spread shouldn't trigger; only multi-generation drift should.
	if absf(body_elongation - float(template.get("body_elongation", 1.0))) > 0.45:
		tags.append("E")
	if absf(body_depth_factor - float(template.get("body_depth_factor", 1.0))) > 0.55:
		tags.append("d")
	if absf(eye_size_factor - float(template.get("eye_size_factor", 1.0))) > 0.55:
		tags.append("e")
	if absf(body_width_factor - float(template.get("body_width_factor", 1.0))) > 0.45:
		tags.append("W")
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

# ---- Mouthbrooding ----
# Real cichlids (Cyrtocara, mbuna, jawfish) carry fertilized eggs in
# their throat pouch for several days. Visible throat bulge while the
# female is incubating; fry tumble out when ready. Genome-driven so
# only mouthbrooder species express it.
var is_mouthbrooder: bool = false
var _mouthbrood_progress: float = 0.0       # 0 = empty, 1 = ready to release
var _mouthbrood_genome: Dictionary = {}      # cached offspring genome
var _mouthbrood_count: int = 0
const MOUTHBROOD_DURATION: float = 40.0      # sim seconds of carrying
# Visible throat bulge node attached on demand to the head bone. Sized
# to clutch_size and progress so it visibly fills + recedes.
var _mouthbrood_bulge: MeshInstance3D = null

# ---- Hierarchical territory defense ----
# Some species establish a personal territory and chase conspecific
# intruders out of it. Alpha rank = size_potential × age_factor. The
# higher-ranked individual wins challenges; the lower-ranked one yields.
var is_territorial: bool = false
var _territory_chase_target: Fish = null
var _territory_chase_t: float = 0.0
const TERRITORY_CHASE_DURATION: float = 1.8
const TERRITORY_CHASE_COOLDOWN: float = 3.5
var _territory_cooldown: float = 0.0

# ---- Cleaning station (fish side) ----
# When stressed and a cleaner shrimp/wrasse is nearby, the fish swims
# to the cleaner, slows to a stop, and tilts slightly while being
# cleaned. shrimp.gd already pursues stressed fish; this gates the
# fish to also seek out a clean.
var _seeking_clean: bool = false
var _being_cleaned: float = 0.0              # seconds remaining at station

# ---- Sleep posture (diurnal night rest) ----
# Diurnal fish at night drift gently with a slight body tilt and the
# occasional twitch. Independent from the hide-in-plants pull above —
# this drives the visual posture once the fish has settled near cover.
var _sleep_tilt: float = 0.0                 # smoothed roll for posture
var _sleep_twitch_t: float = 0.0             # countdown to next twitch

# ---- Pre-stress gill flush ----
# A rare gill cough animation that fires when stress is climbing but
# hasn't crossed the visible hide threshold yet. Early-warning visual
# the player can read before the fish actually panics.
var _gill_flush_t: float = 0.0               # animation phase (0 = idle)
var _gill_flush_check: float = 0.0           # countdown to next eligibility check
var _gill_pivot: Node3D = null               # set by _build_body when available

# ---- Pecking-order boldness ----
# Cached personality scalar: bold fish reach food first; timid hang back.
# Computed once per food query from (dart_chance + courage from low stress).
# Higher = more eager to chase distant food.
func _boldness() -> float:
	# dart_chance 0..0.5, stress 0..1, schooling_strength 0..2. Bold =
	# darty + calm + loose schooler. Timid = low dart + stressed + tight
	# schooler. Personality.boldness (0..1) shifts the range another ±0.4 so
	# the player-visible "bold one" and "shy one" reads at a glance.
	var p_bold: float = float(personality.get("boldness", 0.5)) if not personality.is_empty() else 0.5
	return clampf(0.6 + dart_chance * 1.6 - stress * 0.6
		+ (1.5 - schooling_strength) * 0.10
		+ (p_bold - 0.5) * 0.8, 0.4, 1.8)


# Player food subtype preference. Lower = more appealing (reduces effective distance).
func _food_appeal_multiplier(w: WasteParticle) -> float:
	if w.kind != WasteParticle.KIND_FOOD:
		return 1.0
	match w.food_subtype:
		WasteParticle.FOOD_SUB_FLAKE:
			if mouth_orientation == -1:
				return 0.42
			if mouth_orientation == 1:
				return 2.4
			return 0.95
		WasteParticle.FOOD_SUB_PELLET:
			if mouth_orientation == 1:
				return 0.48
			if mouth_orientation == -1:
				return 1.9
			return 0.9
		WasteParticle.FOOD_SUB_WORM:
			if herbivory > 0.55:
				return 2.8
			if herbivory < 0.25:
				return 0.45
			return 1.1
		WasteParticle.FOOD_SUB_WAFER:
			if herbivory > 0.45 or algae_grazer:
				return 0.38
			if herbivory < 0.2:
				return 2.0
			return 1.0
		_:
			return 1.0


# Convenience accessor — returns the personality value or 0.5 default. Used
# by the look-at-glass, gaze-contagion, and pause-and-look code to stay
# fast in the hot loop (no dict null check at every callsite).
func _trait(key: String) -> float:
	return float(personality.get(key, 0.5)) if not personality.is_empty() else 0.5


# Seasonal breeding readiness in roughly [0.7, 1.3] from the real-world month:
# peaks in spring (Mar-May), dips in winter. Matches the seasonal palette drift
# so the tank's look and its biology share one annual rhythm.
func _season_breed_mult() -> float:
	var month: int = Time.get_datetime_dict_from_system().get("month", 6)
	# Phase so April (month 4) sits near the peak.
	return 1.0 + sin((float(month) - 4.0) / 12.0 * TAU) * 0.3


# Logistic fecundity (#31): breeding is suppressed as the population approaches
# carrying capacity, so it asymptotes toward K smoothly instead of overshooting
# and then crashing on stress. Returns a 0..0.9 probability of skipping a
# courtship attempt this tick.
# Mate loyalty (#83): find the previous partner among neighbors if it's still
# adult, single, and ready — so bonded pairs reunite across spawns.
func _find_preferred_mate(neighbors: Array) -> Fish:
	if _mate_id == "":
		return null
	for n in neighbors:
		if not (n is Fish):
			continue
		var f: Fish = n
		if String(f.id) == _mate_id and f.partner == null \
				and f.maturity == MATURITY_ADULT and f.sex != sex \
				and f.breed_cooldown <= 0.0:
			return f
	return null


func _logistic_breed_suppress() -> float:
	if sim == null or not sim.has_method("fish_stocking_ratio"):
		return 0.0
	var r: float = sim.fish_stocking_ratio()
	return clampf((r - 0.6) / 0.4, 0.0, 0.9)


# Push a salient event into working memory. Cheap ring buffer; oldest entry is
# dropped when full. Used to bias goal selection and to seed mood changes.
func remember(kind: String, pos: Vector3, ttl: float = 12.0) -> void:
	memory.append({"kind": kind, "pos": pos, "t": ttl})
	if memory.size() > MEMORY_MAX:
		memory.pop_front()


# Most recent remembered event of a given kind that hasn't expired, or null.
func _recall(kind: String) -> Variant:
	for i in range(memory.size() - 1, -1, -1):
		var e: Dictionary = memory[i]
		if String(e.get("kind", "")) == kind and float(e.get("t", 0.0)) > 0.0:
			return e
	return null


# Maintain the unified inner-life state. Called once per brain tick BEFORE the
# behavior tiers so mood/curiosity/spooked/familiarity are fresh when the
# steering reads them. Returns nothing; mutates state in place. Throttle-safe:
# everything here is O(1) plus a small memory sweep.
func _update_inner_life(dt: float, conspecifics_nearby: int) -> void:
	# Decay working memory.
	if not memory.is_empty():
		var keep: Array = []
		for e in memory:
			e["t"] = float(e.get("t", 0.0)) - dt
			if float(e["t"]) > 0.0:
				keep.append(e)
		memory = keep

	# Spooked decays slowly (lingering after-fear). A fresh startle tops it up.
	if _startle_remaining > 0.0:
		spooked = maxf(spooked, clampf(0.55 + (1.0 - _trait("boldness")) * 0.45, 0.0, 1.0))
	spooked = maxf(0.0, spooked - dt * 0.12)

	# Reaction-shot + fidget timers.
	_reaction_remaining = maxf(0.0, _reaction_remaining - dt)
	_fidget_remaining = maxf(0.0, _fidget_remaining - dt)
	_fidget_cooldown = maxf(0.0, _fidget_cooldown - dt)
	_goal_pick_cooldown = maxf(0.0, _goal_pick_cooldown - dt)
	goal_timer = maxf(0.0, goal_timer - dt)
	_relief_pulse = maxf(0.0, _relief_pulse - dt * 1.5)

	# Curiosity builds when life is calm and uneventful; discharges when the
	# fish is actively investigating (interest set) or recently startled.
	var calm_now: bool = stress < 0.4 and _startle_remaining <= 0.0 and burst_remaining <= 0.0
	if calm_now and _interest_remaining <= 0.0:
		curiosity_drive = clampf(curiosity_drive + dt * (0.02 + _trait("curiosity") * 0.05), 0.0, 1.0)
	else:
		curiosity_drive = maxf(0.0, curiosity_drive - dt * 0.25)

	# Mood: a smoothed read of wellbeing. Satisfaction from full belly, calm,
	# company, oxygen; misery from hunger/stress/spook/isolation. Anchored
	# toward a personality baseline (bold + calm fish sit happier).
	var satisfaction: float = 0.0
	satisfaction += (0.5 - hunger) * 0.6
	satisfaction += (0.5 - stress) * 0.8
	satisfaction -= spooked * 0.6
	if conspecifics_nearby >= 2:
		satisfaction += 0.25
	elif maturity != MATURITY_FRY and schooling_strength > 0.4:
		satisfaction -= 0.25
	if sim != null and sim.get("dissolved_o2") != null:
		satisfaction += (float(sim.dissolved_o2) - 0.6) * 0.4
	var baseline: float = lerpf(-0.1, 0.4, (_trait("calm") + _trait("boldness")) * 0.5)
	var mood_target: float = clampf(baseline + satisfaction, -1.0, 1.0)
	mood = lerpf(mood, mood_target, clampf(dt * 0.4, 0.0, 1.0))

	# Chemistry relief/escalation. Compare this tick's chem stress to last.
	var chem_now: float = 0.0
	if sim != null and sim.get("water_chemistry") != null:
		var nh3c: float = float(sim.water_chemistry.ammonia)
		var no2c: float = float(sim.water_chemistry.nitrite)
		chem_now = maxf(clampf((nh3c - 0.25) / 0.75, 0.0, 1.0),
			clampf((no2c - 0.35) / 0.85, 0.0, 1.0))
	if _prev_chem_stress - chem_now > 0.04:
		_relief_pulse = 1.0   # water just got noticeably better → visible easing
	_prev_chem_stress = chem_now

	# Sleep state. Diurnal species sleep in deep night; nocturnal (shuffle)
	# invert. A scare wakes them. Sets _asleep which the tiers + animation read.
	if sim != null:
		var dl_s: float = float(sim.daylight())
		var wants_sleep: bool
		if swim_pattern == "shuffle":
			wants_sleep = dl_s > 0.82   # nocturnal: rest in bright day
		else:
			wants_sleep = dl_s < 0.14   # diurnal: rest in deep night
		# Hunger / breeding / panic override sleep.
		if hunger > 0.6 or _startle_remaining > 0.0 or partner != null \
				or brooding_remaining > 0.0:
			wants_sleep = false
		_asleep = wants_sleep and maturity != MATURITY_FRY

	# Eye blink cadence — slower when calm, suppressed when active.
	_blink_t -= dt
	_blink_remaining = maxf(0.0, _blink_remaining - dt)
	if _blink_t <= 0.0 and speed < 0.8:
		_blink_t = randf_range(2.0, 6.0)
		_blink_remaining = 0.12

	# Leadership: a confident, high-ranking, mature fish drifts toward leading
	# its local school. A slow random walk lets the role change hands over time
	# so the same individual doesn't lead forever (organic, not rail-fixed).
	var lead_target: float = _trait("boldness") * 0.4 + rank_within_species * 0.4 \
		+ clampf(age / max_age_s, 0.0, 1.0) * 0.2
	lead_target += sin(age * 0.13 + float(get_instance_id() % 100)) * 0.12
	lead_score = lerpf(lead_score, clampf(lead_target, 0.0, 1.0), clampf(dt * 0.2, 0.0, 1.0))


# Record a meal at the current position into both the bio counter and the
# spatial feed_heatmap. Called from every food-consumption site so the
# fish actually learns where it has eaten before. Costs a single int add
# and ~3 float ops — fine in the hot path.
func _trigger_mouth_gape() -> void:
	_mouth_gape = 1.0


func _record_meal_at(pos: Vector3, weight: float = 1.0) -> void:
	_trigger_mouth_gape()
	if bio.is_empty():
		bio["meals_eaten"] = 0
	bio["meals_eaten"] = int(bio.get("meals_eaten", 0)) + 1
	# Working memory + mood: a meal is a happy, salient event. Remember where
	# it happened so the fish can return to a proven spot when hungry again.
	remember("fed", pos, 14.0)
	mood = clampf(mood + 0.12 * weight, -1.0, 1.0)
	# Trust building: being fed while the player is watching teaches the fish
	# that the looming presence at the glass means food. This is the core of
	# "the tank knows you" — hand-fed fish learn to greet you.
	if _cached_glance_strength > 0.25:
		familiarity = clampf(familiarity + 0.03 * weight * (0.5 + _trait("boldness")), 0.0, 1.0)
	if feed_heatmap.size() == 0:
		return
	var w: Node = _world_node()
	if w == null:
		return
	# Tank-relative position. World exposes TANK_HALF_W / D / HEIGHT.
	var hw_v: Variant = w.get("TANK_HALF_W")
	var hd_v: Variant = w.get("TANK_HALF_D")
	var hh_v: Variant = w.get("TANK_HEIGHT")
	if hw_v == null or hd_v == null or hh_v == null:
		return
	var rx: float = clampf((pos.x + float(hw_v)) / (float(hw_v) * 2.0), 0.0, 0.999)
	var ry: float = clampf(pos.y / float(hh_v), 0.0, 0.999)
	var rz: float = clampf((pos.z + float(hd_v)) / (float(hd_v) * 2.0), 0.0, 0.999)
	var ix: int = int(rx * FEED_HEATMAP_SIZE)
	var iy: int = int(ry * FEED_HEATMAP_SIZE)
	var iz: int = int(rz * FEED_HEATMAP_SIZE)
	var idx: int = ix + iy * FEED_HEATMAP_SIZE + iz * FEED_HEATMAP_SIZE * FEED_HEATMAP_SIZE
	feed_heatmap[idx] = minf(1.0, feed_heatmap[idx] + 0.30 * weight)


# Sample the feed_heatmap at a given world position. Returns 0..1 — higher
# means "I've eaten here a lot." Cheap; nearest-neighbor lookup, no interp.
func _feed_memory_at(pos: Vector3) -> float:
	if feed_heatmap.size() == 0:
		return 0.0
	var w: Node = _world_node()
	if w == null:
		return 0.0
	var hw_v: Variant = w.get("TANK_HALF_W")
	var hd_v: Variant = w.get("TANK_HALF_D")
	var hh_v: Variant = w.get("TANK_HEIGHT")
	if hw_v == null or hd_v == null or hh_v == null:
		return 0.0
	var rx: float = clampf((pos.x + float(hw_v)) / (float(hw_v) * 2.0), 0.0, 0.999)
	var ry: float = clampf(pos.y / float(hh_v), 0.0, 0.999)
	var rz: float = clampf((pos.z + float(hd_v)) / (float(hd_v) * 2.0), 0.0, 0.999)
	var ix: int = int(rx * FEED_HEATMAP_SIZE)
	var iy: int = int(ry * FEED_HEATMAP_SIZE)
	var iz: int = int(rz * FEED_HEATMAP_SIZE)
	var idx: int = ix + iy * FEED_HEATMAP_SIZE + iz * FEED_HEATMAP_SIZE * FEED_HEATMAP_SIZE
	return feed_heatmap[idx]


# Render a one-line bio summary for the portal info panel. Format:
#   "Atlas the Bold · 23 meals · 4 offspring · 12m old"
# Returns "" if the fish has no name yet (very early in init).
func get_bio_summary() -> String:
	if fish_name == "":
		return ""
	var epithet: String = CreatureNaming.epithet_for_personality(personality)
	var title: String
	if epithet != "":
		title = "%s %s" % [fish_name, epithet]
	else:
		title = fish_name
	var meals: int = int(bio.get("meals_eaten", 0))
	var kids: int = int(bio.get("offspring", 0))
	var age_min: int = int(age / 60.0)
	var parts: PackedStringArray = PackedStringArray([title])
	if meals > 0:
		parts.append("%d %s" % [meals, "meal" if meals == 1 else "meals"])
	if kids > 0:
		parts.append("%d %s" % [kids, "child" if kids == 1 else "children"])
	if age_min > 0:
		parts.append("%dm old" % age_min)
	return " · ".join(parts)

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
var _belly_flash: float = 0.0
var _mouth_gape: float = 0.0
# Aerial respiration: cories + loaches periodically dart to the surface to
# gulp atmospheric air, then sink back to the substrate. Real Walstad
# behavior - it's a stress signal in healthy tanks but routine in any
# armored catfish. Counts down between trips, becomes negative during a
# trip (the negative value drives the upward bias).
var _aerial_timer: float = -1.0
var _aerial_target_y: float = 0.0
var _aerial_return_y: float = INF
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
# Continuous pattern modulators (heritable). The discrete pattern_type picks the
# macro layout; these floats reshape it so each lineage reads as a unique face:
#   scale     = size of each pattern element (spot / bar / dash)
#   intensity = boldness / thickness of the marking
#   density   = how many repeated elements (spot rows, reticulation rows, bars)
#   coverage  = fraction of the body length the pattern spans (head -> tail)
#   contrast  = how dark / crisp the marking edges read
# A secondary motif (pattern_type_b, blended at pattern_blend) can overlay the
# primary so e.g. stripes + faint spots co-exist. Defaults reproduce the old look.
var pattern_scale: float = 0.5
var pattern_intensity: float = 0.5
var pattern_density: float = 0.5
var pattern_coverage: float = 1.0
var pattern_contrast: float = 0.5
var pattern_type_b: int = -1         # -1 = no secondary motif
var pattern_blend: float = 0.0       # 0..1 strength of the secondary motif
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
# Per-fish wag-frequency jitter — ±12% multiplier on every species' wag_freq
# so a tight school doesn't all tail-flick in lockstep. Combined with the
# already-random _swim_phase initial offset, this keeps phase relationships
# drifting continuously rather than holding fixed offsets.
var _wag_freq_jitter: float = 1.0
# Tight schoolers share tail-wag phase within ±0.1 rad of the tank pulse.
var _school_phase_offset: float = 0.0
# Fry-dart trail emitter cadence. Only used when maturity == MATURITY_FRY and
# the fry is currently in a dart burst (burst_remaining > 0). The trail
# afterimages are world-positioned so the smear visibly trails the fry
# rather than dragging behind in body-local space.
var _fry_trail_timer: float = 0.0
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
var _home_y_drift_timer: float = randf_range(8.0, 24.0)

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
# Wall-clock stamp when the fish entered dying state. Safety net for
# "stuck dying forever" — if real-world time since this exceeds
# DEATH_WALL_CLOCK_MAX, force queue_free regardless of _dying_timer.
# Covers cases where dt gets starved (time_scale flicker, _process gate
# misfire) or repeated save/load resets keep the timer alive.
var _dying_wall_start_unix: int = 0
const DEATH_WALL_CLOCK_MAX: int = 12
const DEATH_DURATION: float = 3.5

# Cached voxel handles (MultiMesh instances). Built once at the end of
# _build_body() and reused by aging tint, maturity color, courtship color
# boost, and restoration.
var _cached_meshes: Array = []
var _voxel_builder: FaunaVoxelBuilder = null

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
	_wag_freq_jitter = randf_range(0.88, 1.12)
	_school_phase_offset = randf_range(-0.1, 0.1)
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

	# Cache the AIDirector autoload ref ONCE at ready so every per-tick
	# AI sample (intent drift, mood) skips a get_node_or_null lookup.
	# Previously this was ~3 lookups per tick per fish × 10 Hz × 30 fish
	# = ~900 autoload lookups/sec. Cached, it's ~0.
	if is_inside_tree():
		_ai_director_cached = get_node_or_null("/root/AIDirector")
	# Decay throttle: stagger so all fish don't decay on the same tick.
	# Each fish picks a random offset so the load smears across time.
	_decay_throttle_t = randf() * DECAY_THROTTLE_PERIOD


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
	if genome.get("mixed_morphs", false):
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
			# AIDirector pulls from the same offline pool when Ollama is
			# off or unreachable, so this works in every mode. Gate on
			# is_inside_tree so a fish constructed before being attached
			# (rare) cleanly falls back to offline.
			var ai: Node = null
			if is_inside_tree():
				ai = get_node_or_null("/root/AIDirector")
			var picked: Dictionary
			if ai != null and ai.has_method("consume_name"):
				picked = ai.consume_name("fish", {})
			else:
				picked = {"name": CreatureNaming.generate_name("fish", {}), "source": "offline"}
			fish_name = String(picked.get("name", "Fish"))
			name_source = String(picked.get("source", "offline"))
	parent_lineage = genome.get("parent_lineage", "Founders")
	# Personality + bio. Inherit personality from parents when present in
	# the genome (set by the breeding hook); otherwise roll fresh. Bio
	# starts as a stat sheet of zeros.
	var inherited: Dictionary = genome.get("personality", {})
	if inherited.is_empty():
		personality = CreatureNaming.roll_personality()
	else:
		personality = CreatureNaming.roll_personality(inherited)
	if bio.is_empty():
		bio = {
			"birth_unix": int(Time.get_unix_time_from_system()),
			"meals_eaten": 0,
			"offspring": 0,
			"fights_won": 0,
			"age_peak_s": 0.0,
			"name_source": name_source,
		}
	# Pre-allocate feed_heatmap on first init.
	if feed_heatmap.size() == 0:
		feed_heatmap.resize(FEED_HEATMAP_SIZE * FEED_HEATMAP_SIZE * FEED_HEATMAP_SIZE)
	# Pre-allocate the novelty bitmap (64 cells, 1 byte each — wasteful
	# vs a bitset but trivial in size and the index math stays simple).
	if visited_regions.size() == 0:
		visited_regions.resize(NOVELTY_GRID * NOVELTY_GRID * NOVELTY_GRID)
	
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
	pattern_scale = clampf(float(genome.get("pattern_scale", pattern_scale)), 0.0, 1.0)
	pattern_intensity = clampf(float(genome.get("pattern_intensity", pattern_intensity)), 0.0, 1.0)
	pattern_density = clampf(float(genome.get("pattern_density", pattern_density)), 0.0, 1.0)
	pattern_coverage = clampf(float(genome.get("pattern_coverage", pattern_coverage)), 0.2, 1.0)
	pattern_contrast = clampf(float(genome.get("pattern_contrast", pattern_contrast)), 0.0, 1.0)
	pattern_type_b = int(genome.get("pattern_type_b", pattern_type_b))
	pattern_blend = clampf(float(genome.get("pattern_blend", pattern_blend)), 0.0, 1.0)
	# Ornamentation phenotypes.
	bar_edged = not not genome.get("bar_edged", bar_edged)
	eye_spot = not not genome.get("eye_spot", eye_spot)
	ventral_feelers = not not genome.get("ventral_feelers", ventral_feelers)
	finnage = float(genome.get("finnage", finnage))
	labyrinth_breather = not not genome.get("labyrinth_breather", labyrinth_breather)
	# Body skeleton phenotypes (heritable - drift in produce_offspring_genome).
	has_barbels = not not genome.get("has_barbels", has_barbels)
	mouth_orientation = int(genome.get("mouth_orientation", mouth_orientation))
	eye_size_factor = float(genome.get("eye_size_factor", eye_size_factor))
	ventral_profile = float(genome.get("ventral_profile", ventral_profile))
	back_arch = float(genome.get("back_arch", back_arch))
	tail_shape = int(genome.get("tail_shape", tail_shape))
	armor_plates = not not genome.get("armor_plates", armor_plates)
	is_livebearer = not not genome.get("is_livebearer", is_livebearer)
	is_mouthbrooder = not not genome.get("is_mouthbrooder", is_mouthbrooder)
	is_territorial = not not genome.get("is_territorial", is_territorial)
	guards_clutch = not not genome.get("guards_clutch", guards_clutch)
	sterile = not not genome.get("sterile", sterile)
	anal_fin_length_factor = float(genome.get("anal_fin_length_factor",
		anal_fin_length_factor))
	adipose_fin = not not genome.get("adipose_fin", adipose_fin)
	snout_pointed = not not genome.get("snout_pointed", snout_pointed)
	body_shape = String(genome.get("body_shape", body_shape))
	# Expanded morphology genes (heritable; default = original silhouette).
	body_width_factor = clampf(float(genome.get("body_width_factor", body_width_factor)), 0.5, 1.8)
	snout_length_factor = clampf(float(genome.get("snout_length_factor", snout_length_factor)), 0.5, 2.5)
	dorsal_length_factor = clampf(float(genome.get("dorsal_length_factor", dorsal_length_factor)), 0.5, 2.2)
	nuchal_hump = clampf(float(genome.get("nuchal_hump", nuchal_hump)), 0.0, 1.0)
	second_dorsal = not not genome.get("second_dorsal", second_dorsal)
	ventral_sucker = not not genome.get("ventral_sucker", ventral_sucker)
	# barbel_count: -1 sentinel means "derive from has_barbels" so legacy
	# genomes (which only carry has_barbels) keep the classic 4-whisker look.
	barbel_count = int(genome.get("barbel_count", -1))
	if barbel_count < 0:
		barbel_count = 4 if has_barbels else 0
	barbel_count = clampi(barbel_count, 0, 8)
	size_potential = clampf(float(genome.get("size_potential", size_potential)), 0.6, 2.4)
	jaw_claw_size = clampf(float(genome.get("jaw_claw_size", jaw_claw_size)), 0.0, 1.2)
	var inherited_max_growth: float = float(genome.get("max_growth", max_growth))
	var size_potential_t: float = clampf((size_potential - 0.6) / 1.8, 0.0, 1.0)
	max_growth = clampf(
		inherited_max_growth * lerpf(0.82, 1.45, size_potential_t),
		1.05, 2.8)
	# Sexual dimorphism. Runs AFTER all genome.get reads above so it applies on
	# top of the final genome-resolved values (the underlying stored genome is
	# untouched, so lineage drift still works). dimorphism (0..1) scales the
	# effect; at 0 both sexes render identically (the back-compat default). When
	# the genome doesn't specify it, derive from reproductive strategy: livebearers
	# (guppies/mollies), labyrinth fish (bettas/gouramis) and clutch-guarders
	# (cichlids) are the strongly dimorphic groups; most shoaling fish are not.
	dimorphism = float(genome.get("dimorphism", -1.0))
	if dimorphism < 0.0:
		dimorphism = 0.0
		if is_livebearer:
			dimorphism = 0.85
		elif labyrinth_breather:
			dimorphism = 0.7
		elif guards_clutch:
			dimorphism = 0.5
	dimorphism = clampf(dimorphism, 0.0, 1.0)
	_saved_genome["dimorphism"] = dimorphism
	if dimorphism > 0.05:
		var d: float = dimorphism
		if sex == 1:
			# Female form: drabber + fuller + shorter-finned, scaled by d.
			base_color = base_color.lerp(Color(0.78, 0.78, 0.80), 0.55 * d)
			if _tail_color_set:
				tail_color = tail_color.lerp(Color(0.7, 0.72, 0.75), 0.6 * d)
			accent_color = accent_color.lerp(Color(0.65, 0.65, 0.70), 0.45 * d)
			adult_voxel_scale *= lerpf(1.0, 1.35, d)
			body_depth_factor *= lerpf(1.0, 1.15, d)
			ventral_profile = clampf(ventral_profile * lerpf(1.0, 1.25, d), 0.55, 1.9)
			fin_length_factor = clampf(fin_length_factor * lerpf(1.0, 0.55, d), 0.5, 1.8)
			dorsal_height_factor = clampf(dorsal_height_factor * lerpf(1.0, 0.7, d), 0.5, 1.8)
		else:
			# Male form: showier — more saturated + brighter body and longer,
			# taller finnage, scaled by d.
			var bc: Color = base_color
			bc.s = minf(1.0, bc.s * (1.0 + 0.45 * d))
			bc.v = minf(1.0, bc.v * (1.0 + 0.14 * d))
			base_color = bc
			var ac: Color = accent_color
			ac.s = minf(1.0, ac.s * (1.0 + 0.4 * d))
			ac.v = minf(1.0, ac.v * (1.0 + 0.16 * d))
			accent_color = ac
			if _tail_color_set:
				var tc: Color = tail_color
				tc.s = minf(1.0, tc.s * (1.0 + 0.4 * d))
				tail_color = tc
			fin_length_factor = clampf(fin_length_factor * lerpf(1.0, 1.32, d), 0.5, 1.9)
			dorsal_height_factor = clampf(dorsal_height_factor * lerpf(1.0, 1.28, d), 0.5, 1.9)
			finnage = clampf(finnage * lerpf(1.0, 1.18, d), 1.0, 2.2)
	# Locomotion derives from body_shape unless explicitly overridden in
	# the genome. The match expresses the real-world correlation between
	# a fish's silhouette and how it produces thrust.
	if genome.has("locomotion_type"):
		locomotion_type = String(genome["locomotion_type"])
	else:
		match body_shape:
			"anguilliform", "ribbon":
				# Ribbon eels / knifefish undulate the whole body like a true eel.
				locomotion_type = "anguilliform"
			"globiform":
				locomotion_type = "ostraciiform"
			"compressed", "depressed":
				# Discs (angelfish/tangs) and flattened benthics (rays, hillstream
				# loaches) both row mainly with their pectorals.
				locomotion_type = "labriform"
			_:
				# fusiform + sagittiform (gar/pike) are body-caudal swimmers.
				locomotion_type = "subcarangiform"
	# Food preferences (species-level, not heritable).
	snail_predator = not not genome.get("snail_predator", snail_predator)
	shrimp_predator = not not genome.get("shrimp_predator", shrimp_predator)
	_apply_predator_morphology()
	algae_grazer = not not genome.get("algae_grazer", algae_grazer)
	wood_grazer = not not genome.get("wood_grazer", wood_grazer)
	# Bioluminescence. Either set explicitly in genome, or rolled fresh at
	# ~3% for first-generation founders so any tank eventually accumulates
	# a few glowing individuals.
	if genome.has("is_bioluminescent"):
		is_bioluminescent = not not genome["is_bioluminescent"]
	elif generation == 0 and randf() < 0.03:
		is_bioluminescent = true
		_saved_genome["is_bioluminescent"] = true
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
		var spread_xz: float = _tank_home_spread_xz()
		home_x = global_position.x + randf_range(-spread_xz, spread_xz)
		home_z = global_position.z + randf_range(-spread_xz, spread_xz)
	if is_inf(home_y):
		home_y = preferred_y + randf_range(-0.6, 0.6)
	if sim != null:
		_reclamp_territory_to_tank()
	# A fry is born tiny - we'll lerp scale as it matures.
	scale = Vector3.ONE * _maturity_scale()
	_build_body()
	# Apply distance-LOD to voxels — tiny details drop out beyond ~8m,
	# secondary details beyond ~14m. Portal PiP camera is close so it
	# still sees full detail; the orbit camera at typical distance keeps
	# silhouettes but skips fin-bone-level voxels.
	_apply_lod_ranges()


# Apply per-pattern defaults. Only fills in fields the genome hasn't already
# overridden (sentinel-style: a default of 1.0 / 2.5 / 0.0 means "use the
# pattern's pick"). Each pattern shapes how the fish wanders + how often it
# darts; the actual schooling weight stays driven by genome.schooling_strength.
func _apply_swim_pattern_defaults() -> void:
	max_turn_rate = 2.6 # default reset
	match swim_pattern:
		"school":
			home_radius = 4.0
			wander_strength = 1.15
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
		# A long body + shrimp-hunting bias reads as a lurking pike/gar ambush
		# predator: sagittiform silhouette with a lengthened pointed snout.
		if not snail_predator and body_elongation > 1.12 \
				and (body_shape == "fusiform" or body_shape == "sagittiform"):
			body_shape = "sagittiform"
			snout_length_factor = maxf(snout_length_factor, 1.3)
			snout_pointed = true
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
	# Marine perciforms almost all carry a spiny + soft two-dorsal arrangement;
	# give most reef morphs a second dorsal plus some lateral-width variety.
	genome["second_dorsal"] = randf() < 0.7
	genome["body_width_factor"] = randf_range(0.7, 1.15)
	# A fifth of reef morphs roll the richer marine patterns: reticulated
	# boxfish net, masked butterflyfish band, ocellated spot rows.
	if randf() < 0.20:
		genome["pattern_type"] = [6, 8, 9][randi() % 3]
	# Rare bold body plans seen on the reef: a flattened ray/flounder or a
	# rounded boxfish.
	var shape_roll: float = randf()
	if shape_roll < 0.06:
		genome["body_shape"] = "depressed"
		genome["body_width_factor"] = randf_range(1.2, 1.6)
		genome["body_depth_factor"] = randf_range(0.6, 0.85)
	elif shape_roll < 0.10:
		genome["body_shape"] = "globiform"
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
	_voxel_builder = FaunaVoxelBuilder.new()
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
	var mat_eye := VoxelMat.make(Color8(11, 26, 34))
	var mat_fin := _make_mat(base_color.darkened(0.15))
	# Tail fin material: defaults to a darker shade of base_color, but if
	# the genome supplied an explicit tail_color we use that (male guppies'
	# bright red/orange fan against a dark body).
	var effective_tail: Color = tail_color if _tail_color_set \
		else base_color.darkened(0.15)
	var mat_tail := VoxelMat.make_translucent(
		Color(effective_tail.r, effective_tail.g, effective_tail.b, 0.52))
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
	# Nuchal hump: a bulging forehead / nape boss that grows up and forward
	# over the head. Defines mature cichlids (flowerhorn, severum, midas) and
	# the humphead wrasse / bumphead parrotfish on the reef.
	if nuchal_hump > 0.05:
		var hump: float = nuchal_hump
		_add_voxel_to(head, Vector3(0, v * (0.7 + 0.5 * hump) * hp, -2.55 * v),
			Vector3(v * 0.55 * hp, v * (0.4 + 0.6 * hump) * hp, v * 0.85 * hp), mat_top)
		_add_voxel_to(head, Vector3(0, v * (0.55 + 0.45 * hump) * hp, -2.95 * v),
			Vector3(v * 0.4 * hp, v * (0.3 + 0.45 * hump) * hp, v * 0.5 * hp), mat_body)
	# Belly under head. ventral_profile pulls it lower for round-bellied
	# species (puffer) or tightens it up for flat-bellied bottom dwellers
	# (cory, loach).
	_add_voxel_to(head, Vector3(0, -v * 0.5 * hp * ventral_profile, -2.5 * v),
		Vector3(v * 0.6 * hp, v * 0.3 * hp, v * hp), mat_belly)
	# Eyes — style-guide 1-voxel + highlight pixel for silhouette clarity.
	var es: float = eye_size_factor
	var eye_core: float = v * 0.14 * hp * es
	var mat_eye_hi := VoxelMat.make(Color8(210, 228, 235))
	for x_side in [-1.0, 1.0]:
		_add_voxel_to(head, Vector3(x_side * v * 0.4 * hp, v * 0.1 * hp, -2.38 * v),
			Vector3(eye_core, eye_core, eye_core), mat_eye)
		_add_voxel_to(head, Vector3(x_side * v * 0.42 * hp, v * 0.14 * hp, -2.44 * v),
			Vector3(v * 0.08 * hp * es, v * 0.08 * hp * es, v * 0.08 * es), mat_eye_hi)
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
	# Elongated snout / beak. Independent of snout_pointed so gar, needlefish,
	# pipefish (long beak) and elephantnose read distinctly. The voxel marches
	# forward from the mouth; the longer the snout the thinner it gets.
	if snout_length_factor > 1.05:
		var snout_ext: float = (snout_length_factor - 1.0) * v * 1.5 * hp
		var snout_thin: float = clampf(1.0 / snout_length_factor, 0.4, 1.0)
		_add_voxel_to(head, Vector3(0, mouth_y * 0.5, -3.15 * v - snout_ext * 0.5),
			Vector3(v * 0.22 * hp * snout_thin, v * 0.2 * hp * snout_thin,
				v * 0.5 * hp + snout_ext), mat_body)
		_add_voxel_to(head, Vector3(0, mouth_y * 0.5 + v * 0.1 * hp, -3.15 * v - snout_ext * 0.5),
			Vector3(v * 0.14 * hp * snout_thin, v * 0.08 * hp,
				v * 0.45 * hp + snout_ext), mat_top)
	# Barbels - catfish/loach whiskers. Two pairs of tiny dark voxels under
	# the mouth, angled forward + down. Only drawn if has_barbels.
	if has_barbels and barbel_count > 0:
		var mat_barbel := _make_mat(base_color.darkened(0.5))
		var barbel_y: float = -v * 0.45 * hp
		var barbel_z: float = -2.9 * v
		# Spread barbel_count whiskers symmetrically under the mouth. Catfish
		# carry 4/6/8, loaches 4; an odd count puts one whisker on the chin.
		@warning_ignore("integer_division")
		var pairs: int = barbel_count / 2
		for p in pairs:
			var x_off: float = 0.24
			if pairs > 1:
				x_off = lerpf(0.16, 0.34, float(p) / float(pairs - 1))
			for x_side in [-1.0, 1.0]:
				_add_voxel_to(head, Vector3(x_side * x_off * v * hp, barbel_y, barbel_z),
					Vector3(v * 0.06, v * 0.08, v * 0.25), mat_barbel)
		if barbel_count % 2 == 1:
			_add_voxel_to(head, Vector3(0, barbel_y - v * 0.05, barbel_z),
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
		"depressed":
			# Dorsoventrally flattened bottom-hugger (rays, flatfish, plecos,
			# hillstream loaches). Wide low lateral shelves run the body length;
			# pairs with a high body_width_factor + low body_depth_factor.
			for i in seg_widths.size():
				var bw_d: float = seg_widths[i]
				var bz_d: float = i * v
				for x_side in [-1.0, 1.0]:
					_add_voxel_to(_body_mid_pivot,
						Vector3(x_side * v * bw_d * 0.55, -v * 0.16, bz_d),
						Vector3(v * bw_d * 0.6, v * 0.26, v * 0.95), mat_body)
			# A broad flat pectoral shelf near the head reads as ray "wings".
			for x_side in [-1.0, 1.0]:
				_add_voxel_to(_body_mid_pivot,
					Vector3(x_side * v * 0.85, -v * 0.1, -v * 0.2),
					Vector3(v * 0.7, v * 0.18, v * 0.9), mat_top)
		"sagittiform":
			# Pike / gar / needlefish: long cylindrical body carrying its mass
			# forward with a long rear taper. Pairs with a long snout + high
			# body_elongation; the dorsal sits far back (see dorsal placement).
			_add_voxel_to(_body_mid_pivot, Vector3(0, 0, v * 3.1),
				Vector3(v * 0.9, v * 0.85, v), mat_body)
			_add_voxel_to(_body_mid_pivot, Vector3(0, 0, v * 4.0),
				Vector3(v * 0.78, v * 0.72, v), mat_body)
		"ribbon":
			# Ribbon eel / knifefish: very long thin near-uniform tube with a
			# continuous low fin ridge instead of discrete dorsal/anal fins.
			for ri in 4:
				_add_voxel_to(_body_mid_pivot, Vector3(0, 0, v * (3.0 + ri * 0.95)),
					Vector3(v * 0.62, v * 0.66, v), mat_body)
			var mat_ribbon := _make_mat(base_color.darkened(0.18))
			for ri in 6:
				var rz: float = v * (0.4 + ri * 0.9)
				_add_voxel_to(_body_mid_pivot, Vector3(0, v * 0.55, rz),
					Vector3(v * 0.08, v * 0.3, v * 0.7), mat_ribbon)
				_add_voxel_to(_body_mid_pivot, Vector3(0, -v * 0.55, rz),
					Vector3(v * 0.08, v * 0.3, v * 0.7), mat_ribbon)
		_:
			pass  # fusiform - no extra voxels
	# Ventral sucker / oral disc: a wide flat pale disc under the front belly.
	# Plecos, gobies, hillstream loaches and remoras anchor to surfaces with it.
	if ventral_sucker:
		var mat_sucker := _make_mat(base_color.darkened(0.28).lerp(accent_color, 0.18))
		_add_voxel_to(_body_mid_pivot, Vector3(0, -v * 0.62 * ventral_profile, -v * 0.4),
			Vector3(v * 1.05, v * 0.16, v * 1.1), mat_sucker)
		_add_voxel_to(_body_mid_pivot, Vector3(0, -v * 0.7 * ventral_profile, -v * 0.4),
			Vector3(v * 0.7, v * 0.12, v * 0.75), mat_belly)

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
		var ornament_n: int = clampi(1 + int(generation / 4.0), 1, 4)
		for i in ornament_n:
			var z: float = (0.25 + float(i) * 0.55) * v
			_add_voxel_to(_body_mid_pivot, Vector3(0, v * 0.95, z),
				Vector3(v * 0.08, v * 0.18, v * 0.16), mat_orn)
	# Scale rows — subtle alternating lateral flecks between macro patterns.
	_paint_scale_rows(_body_mid_pivot, v, seg_widths.size(), mat_marking)
	# Lateral pattern. The discrete pattern_type chooses the macro layout; the
	# continuous modulators (scale / intensity / density / coverage / contrast)
	# reshape it, and an optional secondary motif blends in on top so a lineage
	# can carry two patterns at once (stripes + faint spots, bars + mottling, ...).
	_paint_lateral_pattern(pattern_type, _body_mid_pivot, v, seg_widths.size(),
		mat_accent, mat_marking, 1.0)
	if pattern_type_b >= 0 and pattern_type_b != pattern_type and pattern_blend > 0.12:
		_paint_lateral_pattern(pattern_type_b, _body_mid_pivot, v, seg_widths.size(),
			mat_accent, mat_marking, clampf(pattern_blend, 0.3, 0.85))
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
	var ray_n: int = 4
	for r in ray_n:
		var rz: float = lerpf(-0.15, 0.85, float(r) / float(maxi(1, ray_n - 1))) * v
		var ray_h: float = v * (0.12 + 0.10 * float(r)) * dh
		_add_voxel_to(_dorsal_pivot, Vector3(0, ray_h, rz),
			Vector3(v * 0.07, v * (0.18 + 0.06 * float(r)) * dh, v * 0.32), mat_fin)
	# Long-based dorsal: stretch the dorsal's base fore-and-aft along the back
	# (plecos, bichirs, oscars, knifefish). Scales with dorsal_length_factor.
	if dorsal_length_factor > 1.05:
		var dlen: float = dorsal_length_factor
		var dn: int = clampi(1 + int((dlen - 1.0) * 3.0), 1, 5)
		for i in dn:
			var dz: float = lerpf(-0.5, 1.2, float(i) / float(maxi(1, dn - 1))) * v * dlen
			_add_voxel_to(_dorsal_pivot, Vector3(0, v * 0.18 * dh, dz),
				Vector3(v * 0.12, v * 0.34 * dh, v * 0.5), mat_fin)
	# Second (soft) dorsal: a separate fin block set behind the first. The
	# spiny + soft two-dorsal arrangement of most perciforms — gobies,
	# cichlids, bass, the majority of marine fish. Static (a soft dorsal
	# barely moves), so it needs no animation pivot.
	if second_dorsal:
		var d2 := Node3D.new()
		d2.name = "Dorsal2"
		d2.position = Vector3(0, v * 0.75, v * 1.95)
		_body_mid_pivot.add_child(d2)
		_add_voxel_to(d2, Vector3(0, v * 0.16 * dh, 0),
			Vector3(v * 0.13, v * 0.3 * dh, v * 0.7), mat_fin)
		_add_voxel_to(d2, Vector3(0, v * 0.34 * dh, v * 0.12),
			Vector3(v * 0.1, v * 0.2 * dh, v * 0.4), mat_fin)
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
		# Gourami feelers are translucent in real life — the eye reads
		# them as fine threads where the water column is faintly visible
		# through. Use the translucent voxel material with marking color
		# so the species ID stays clear but the feeler reads delicate.
		var feeler_color: Color = Color(effective_marking.r, effective_marking.g, effective_marking.b, 0.65)
		var mat_feeler := VoxelMat.make_translucent(feeler_color)
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
		4:  # lunate / crescent — fast pelagic cruisers (tuna, jacks)
			# Stiff narrow crescent: long swept tips top + bottom, pinched
			# centre. tail_fork_depth widens the spread of the tips.
			_add_voxel_to(_tail_pivot, Vector3(0, v * (0.9 * fl * tf), v * (1.0 * fl)),
				Vector3(v * 0.12, v * (0.7 * fl), v * (0.45 * fl)), mat_tail)
			_add_voxel_to(_tail_pivot, Vector3(0, v * (-0.9 * fl * tf), v * (1.0 * fl)),
				Vector3(v * 0.12, v * (0.7 * fl), v * (0.45 * fl)), mat_tail)
			_add_voxel_to(_tail_pivot, Vector3(0, v * (1.5 * fl * tf), v * (1.75 * fl)),
				Vector3(v * 0.1, v * (0.5 * fl), v * (0.35 * fl)), mat_tail)
			_add_voxel_to(_tail_pivot, Vector3(0, v * (-1.5 * fl * tf), v * (1.75 * fl)),
				Vector3(v * 0.1, v * (0.5 * fl), v * (0.35 * fl)), mat_tail)
		5:  # lanceolate — single pointed spear (many gobies, blennies, eels)
			_add_voxel_to(_tail_pivot, Vector3(0, 0, v * (0.9 * fl)),
				Vector3(v * 0.15, v * 0.7, v * (0.6 * fl)), mat_tail)
			_add_voxel_to(_tail_pivot, Vector3(0, 0, v * (1.5 * fl)),
				Vector3(v * 0.12, v * 0.32, v * (0.55 * fl)), mat_tail)
			_add_voxel_to(_tail_pivot, Vector3(0, 0, v * (2.0 * fl)),
				Vector3(v * 0.1, v * 0.12, v * (0.45 * fl)), mat_tail)
		_:  # 0 = forked (default)
			for fork_i in 3:
				var fork_y: float = lerpf(0.35, 0.75, float(fork_i) / 2.0) * tf
				var fork_z: float = lerpf(0.75, 1.35, float(fork_i) / 2.0) * fl
				_add_voxel_to(_tail_pivot, Vector3(0, v * fork_y, v * fork_z),
					Vector3(v * 0.10, v * 0.22, v * (0.38 + 0.08 * float(fork_i))), mat_tail)
				_add_voxel_to(_tail_pivot, Vector3(0, -v * fork_y, v * fork_z),
					Vector3(v * 0.10, v * 0.22, v * (0.38 + 0.08 * float(fork_i))), mat_tail)
			_add_voxel_to(_tail_pivot,
				Vector3(0, v * (-0.7 * fl * tf), v * (1.4 * fl)),
				Vector3(v * 0.12, v * (0.3 * fl), v * (0.4 * fl)), mat_tail)
	# Finnage elaboration: flowing veil fins (betta / fancy livebearers). When
	# finnage > 1.0, append long trailing ray voxels to the caudal, dorsal and
	# anal fins so the silhouette reads as billowing drapery rather than a
	# tight functional tail.
	if finnage > 1.0:
		var veil: float = finnage
		# Veil fins use the translucent voxel material so the silhouette
		# reads as "you can see the water behind the trailing rays" — the
		# defining look of betta / fancy livebearer fins. Alpha is set on
		# the color so the cached translucent shader handles it; vibrancy
		# stays at default (no boost) so the veil reads as delicate, not
		# the saturated body color.
		var veil_color: Color = Color(effective_tail.r, effective_tail.g, effective_tail.b, 0.55)
		var mat_veil := VoxelMat.make_translucent(veil_color)
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
		# Lateral width — the third cross-section axis. <1 = slab-thin
		# (laterally compressed), >1 = flat-and-wide (rays, flatfish, plecos).
		_bank_pivot.scale.x = body_width_factor

	if _voxel_builder != null:
		_voxel_builder.flush_all()
		_cached_meshes = _voxel_builder.handles.duplicate()
	_apply_lod_ranges()


func _add_voxel_to(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	if _voxel_builder == null:
		_voxel_builder = FaunaVoxelBuilder.new()
	_voxel_builder.add_voxel(parent, pos, size, mat)


# Walk the body hierarchy once after _build_body and assign per-voxel
# `visibility_range_end` based on size. Smallest voxels (eyes, tiny fin
# bones, barbels) drop out first; larger structural voxels (head, body,
# tail) stay visible at longer distances. Godot's renderer does the
# distance check itself, per camera — so the portal PiP (very close
# camera) still sees full detail.
const _LOD_TINY_MAX_VOXEL: float = 0.07   # under this → tiny detail (barbels, eye glints)
const _LOD_SMALL_MAX_VOXEL: float = 0.13  # under this → secondary detail
# Ranges measured in world units. Default camera radius is 17.5, so the
# LOD threshold must sit well past that to keep fins/eyes visible at the
# normal viewing distance — only fish across the room from the camera
# should drop detail.
const _LOD_TINY_RANGE: float = 22.0       # range_end for tiny voxels
const _LOD_SMALL_RANGE: float = 32.0      # range_end for small voxels
const _LOD_BIG_RANGE: float = 0.0         # 0 = never LOD out (default)


func _apply_lod_ranges() -> void:
	if _voxel_builder == null:
		return
	for batch: VoxelBatch in _voxel_builder.get_batches():
		if batch.mmi != null:
			batch.mmi.visibility_range_begin = 0.0
			batch.mmi.visibility_range_end = _LOD_SMALL_RANGE
			batch.mmi.visibility_range_end_margin = 3.0
	var stack: Array = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c is MeshInstance3D:
				var mi: MeshInstance3D = c
				mi.visibility_range_begin = 0.0
				mi.visibility_range_end = _LOD_TINY_RANGE
				mi.visibility_range_end_margin = 3.0
			if c.get_child_count() > 0:
				stack.push_back(c)


func _make_mat(color: Color) -> ShaderMaterial:
	return VoxelMat.make_fauna(color)


# Spawn a brief afterimage at the fry's current world position. Used by
# the dart-trail path in _process. The smear is a tiny tinted box that
# tweens to zero scale and alpha over ~0.35s, then queue_free's. Color
# matches the fry's body so the smear reads as a streak of the fish
# itself, not a generic puff.
func _spawn_fry_trail_smear() -> void:
	var parent: Node = get_parent()
	if parent == null:
		return
	var mi := MeshInstance3D.new()
	var v: float = 0.10  # fry voxel scale
	mi.mesh = VoxelMat.get_box(Vector3(v, v * 0.6, v * 1.4))
	var smear_color: Color = Color(base_color.r, base_color.g, base_color.b, 0.45)
	var mat: ShaderMaterial = VoxelMat.make_translucent(smear_color).duplicate()
	mi.material_override = mat
	# Order matters: add to the scene tree FIRST so global_position +
	# look_at have a valid global transform to work against. The earlier
	# version called look_at before add_child, which Godot reports as
	# "Node not inside tree" and returns identity Transform3D — that's
	# what was spamming the debugger.
	parent.add_child(mi)
	mi.global_position = global_position
	if heading.length_squared() > 0.001:
		var d: Vector3 = heading.normalized()
		var up := _look_up_for_direction(d)
		mi.look_at_from_position(global_position, global_position + d, up)
	const TRAIL_LIFETIME: float = 0.35
	var tw := create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(0.4, 0.4, 0.2), TRAIL_LIFETIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var faded: Color = Color(smear_color.r, smear_color.g, smear_color.b, 0.0)
	tw.tween_property(mat, "shader_parameter/albedo", faded, TRAIL_LIFETIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


# Locate the closest cleaner shrimp/wrasse within `radius`. Walks
# sim.shrimp + sim.fish (other fish flagged with `is_cleaner` later if
# we add cleaner-wrasse fish). Returns null if none qualify.
func _find_nearest_cleaner(radius: float) -> Node3D:
	if sim == null:
		return null
	var best: Node3D = null
	var best_d2: float = radius * radius
	# Cleaner shrimp.
	for s in sim.shrimp:
		if not is_instance_valid(s):
			continue
		if not s.is_cleaner:
			continue
		if s.maturity == 0:  # MATURITY_FRY
			continue
		var d2: float = (s as Node3D).position.distance_squared_to(position)
		if d2 < best_d2:
			best_d2 = d2
			best = s
	return best


# Update the mouthbrood throat bulge. Lazily allocates a small voxel
# under the head; sized to `_mouthbrood_count` and `_mouthbrood_progress`
# so the bulge visibly grows as the brood matures, then disappears on
# release.
func _update_mouthbrood_bulge() -> void:
	if _mouthbrood_progress <= 0.0:
		if _mouthbrood_bulge != null and is_instance_valid(_mouthbrood_bulge):
			_mouthbrood_bulge.queue_free()
			_mouthbrood_bulge = null
		return
	if _mouthbrood_bulge == null or not is_instance_valid(_mouthbrood_bulge):
		_mouthbrood_bulge = MeshInstance3D.new()
		var v: float = adult_voxel_scale
		# Bulge is a slightly elongated box sitting under and forward of
		# the head pivot; we tuck it into the body-front group so head
		# rotation carries it. Falls back to self if no head pivot found.
		var anchor: Node = get_node_or_null("Bank/BodyMid/BodyFront")
		if anchor == null:
			anchor = self
		_mouthbrood_bulge.mesh = VoxelMat.get_box(
			Vector3(v * 1.9, v * 1.1, v * 2.4))
		_mouthbrood_bulge.material_override = VoxelMat.make_fauna(
			accent_color.lerp(Color(0.92, 0.88, 0.78), 0.55))
		anchor.add_child(_mouthbrood_bulge)
		# Below + slightly forward of the head: real cichlid throat
		# pouches sit under the lower jaw.
		_mouthbrood_bulge.position = Vector3(0.0, -v * 1.2, -v * 1.8)
	# Scale grows from 0.35 → 1.0 with progress + clutch_size weight.
	var prog: float = clampf(_mouthbrood_progress, 0.0, 1.0)
	var clutch_w: float = clampf(float(_mouthbrood_count) / 4.0, 0.4, 1.0)
	var s: float = (0.35 + 0.75 * prog) * clutch_w
	_mouthbrood_bulge.scale = Vector3(s, s, s)


func _apply_belly_flash_uniform(strength: float) -> void:
	for c in get_children():
		if c is MeshInstance3D:
			var sm := (c as MeshInstance3D).material_override as ShaderMaterial
			if sm != null and sm.get_shader_parameter("belly_flash") != null:
				sm.set_shader_parameter("belly_flash", strength)


func _apply_stress_flush() -> void:
	if _cached_meshes.is_empty():
		return
	var k: float = clampf((stress - 0.40) / 0.60, 0.0, 1.0)
	if k <= 0.001:
		for child in _cached_meshes:
			if child is VoxelBatch.Handle:
				var h: VoxelBatch.Handle = child
				h.set_color(FaunaVoxelBuilder.handle_orig_color(h))
		return
	var flush_col: Color = accent_color.lerp(Color8(210, 70, 55), 0.72)
	var base_luma: float = base_color.r * 0.299 + base_color.g * 0.587 + base_color.b * 0.114
	var belly_ref: Color = base_color.darkened(0.35)
	for child in _cached_meshes:
		if not (child is VoxelBatch.Handle):
			continue
		var h2: VoxelBatch.Handle = child
		var orig: Color = FaunaVoxelBuilder.handle_orig_color(h2)
		var luma: float = orig.r * 0.299 + orig.g * 0.587 + orig.b * 0.114
		var d_acc: float = maxf(maxf(absf(orig.r - accent_color.r),
			absf(orig.g - accent_color.g)), absf(orig.b - accent_color.b))
		var d_belly: float = maxf(maxf(absf(orig.r - belly_ref.r),
			absf(orig.g - belly_ref.g)), absf(orig.b - belly_ref.b))
		var fin_or_belly: bool = luma < base_luma - 0.06 \
			or d_acc <= 0.22 or d_belly <= 0.18
		var amt: float = k * (0.62 if fin_or_belly else 0.22)
		h2.set_color(orig.lerp(flush_col, amt))


func _tick_substrate_compaction(dt: float) -> void:
	if sim == null or speed < max_speed * 0.55:
		return
	if position.y > float(sim.substrate_top_y) + 1.35:
		return
	var w := sim.get_parent()
	if w == null:
		return
	var av = w.get_node_or_null("AquariumVisuals")
	if av == null or not av.has_method("record_compaction"):
		return
	if randf() < dt * (0.10 + speed * 0.06):
		av.record_compaction(position.x, position.z, 0.006 + speed * 0.004)


# Push the bioluminescence uniform to every body voxel. VoxelMat caches
# materials by color so a plain set_shader_parameter would leak the glow
# to every fish sharing the color. We duplicate the material per fish on
# the first call so each bioluminescent individual carries its own copy;
# the duplicate is tagged via meta so subsequent calls reuse it.
func _apply_bioluminescence_uniform(strength: float) -> void:
	for c in get_children():
		if not (c is MeshInstance3D):
			continue
		var mi: MeshInstance3D = c
		var sm: ShaderMaterial = mi.material_override as ShaderMaterial
		if sm == null:
			continue
		if sm.get_shader_parameter("bioluminescence") == null:
			continue
		if not mi.has_meta("biolum_owned"):
			mi.material_override = sm.duplicate() as ShaderMaterial
			mi.set_meta("biolum_owned", true)
			sm = mi.material_override as ShaderMaterial
		sm.set_shader_parameter("bioluminescence", strength)
		sm.set_shader_parameter("biolum_color", Vector3(
			accent_color.r, accent_color.g, accent_color.b))


func _add_voxel(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelMat.get_box(size)
	mi.position = pos
	mi.material_override = mat
	add_child(mi)


# ---- Tick (called by SimDriver) ----

func _music_mods() -> Dictionary:
	var mr := get_tree().get_first_node_in_group("music_reactive")
	if mr != null and mr.has_method("fauna_behavior_mods"):
		return mr.fauna_behavior_mods(get_instance_id())
	return {
		"speed": 1.0, "wander": 1.0, "home_radius": 1.0, "home_pull": 1.0,
		"tightness": 1.0, "accel": 1.0, "turn": 1.0, "dart_chance": 0.0,
		"beat_dart": false, "wander_refresh": 1.0, "home_drift": 1.0,
		"wander_amp": 1.0, "sweep": 0.0, "vertical": 0.0, "beat_phase": 0.0,
		"scale": 1.0,
	}


func _music_cross_tank_target(mods: Dictionary, vertical_bias: float = 0.35) -> Vector3:
	var w := _world_node()
	if w == null:
		return position
	var hw: float = float(w.get("TANK_HALF_W") if w.get("TANK_HALF_W") != null else 8.0)
	var hd: float = float(w.get("TANK_HALF_D") if w.get("TANK_HALF_D") != null else 4.0)
	var bot_y: float = float(sim.substrate_top_y if sim != null else 0.0) + 0.5
	var top_y: float = _water_surface_y() - 0.4
	var lane: float = float(mods.get("beat_phase", 0.0)) + float(get_instance_id() % 997) * 0.11
	var vert: float = clampf(float(mods.get("vertical", 0.0)), 0.0, 1.0)
	var ty: float = lerpf(
		bot_y + 0.35,
		top_y - 0.25,
		clampf(0.5 + sin(lane * 1.35) * 0.44, 0.08, 0.92))
	ty = lerpf(home_y, ty, clampf(vertical_bias + vert * 0.65, 0.0, 1.0))
	var target := Vector3(
		sin(lane) * hw * 0.96,
		ty,
		cos(lane * 0.81 + 0.9) * hd * 0.96,
	)
	if w.has_method("clamp_xyz_in_tank"):
		target = w.clamp_xyz_in_tank(target, 0.35, _body_tank_margin() * 0.45)
	return target


func _nudge_home_toward_music_target(target: Vector3, strength: float) -> void:
	if strength <= 0.0:
		return
	home_x = lerpf(home_x, target.x, strength)
	home_z = lerpf(home_z, target.z, strength)
	home_y = lerpf(home_y, target.y, strength * 0.45)


func _apply_music_beat_surge(mods: Dictionary, _effective_max: float) -> void:
	if not bool(mods.get("beat_dart", false)):
		return
	burst_remaining = maxf(burst_remaining, randf_range(0.75, 1.15))
	var target: Vector3 = _music_cross_tank_target(mods, 0.72)
	_nudge_home_toward_music_target(target, 0.58)
	var dart_dir: Vector3 = target - position
	if dart_dir.length_squared() < 0.08:
		dart_dir = Vector3(randf_range(-1.0, 1.0), randf_range(-0.35, 0.45), randf_range(-1.0, 1.0))
	if dart_dir.length_squared() > 1e-6:
		dart_dir = dart_dir.normalized()
		heading_offset = dart_dir * (3.6 + wander_strength * float(mods.get("wander", 1.0)))
		_startle_heading = dart_dir
		_startle_remaining = 0.52


func _apply_music_groove_steering(mods: Dictionary, desired: Vector3, effective_max: float) -> Vector3:
	var sweep: float = float(mods.get("sweep", 0.0))
	if sweep < 0.01:
		return desired
	var target: Vector3 = _music_cross_tank_target(mods, 0.55)
	_nudge_home_toward_music_target(target, 0.08 * sweep)
	var to_target: Vector3 = target - position
	if to_target.length_squared() < 0.06:
		return desired
	var pull: float = effective_max * (0.62 + sweep * 2.35)
	if burst_remaining > 0.05:
		pull *= 1.35
	desired += to_target.normalized() * pull
	return desired


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
	# Memory decay throttle. Bulk-decay grudges / habituation / heatmap once
	# every DECAY_THROTTLE_PERIOD (~5s) instead of every tick. Player-visible
	# behavior is identical (decay values change imperceptibly between ticks)
	# but we drop ~50× the dict iteration and PackedFloat32Array sweep cost.
	_decay_throttle_t -= dt
	if _decay_throttle_t <= 0.0:
		var decay_dt: float = DECAY_THROTTLE_PERIOD - _decay_throttle_t
		_decay_throttle_t = DECAY_THROTTLE_PERIOD
		# Lifetime journal: age_peak only needs to update on the throttle
		# (the difference between current age and peak grows monotonically).
		if not bio.is_empty():
			if age > float(bio.get("age_peak_s", 0.0)):
				bio["age_peak_s"] = age
		if not grudges.is_empty():
			var expired: Array = []
			for k in grudges.keys():
				grudges[k] = float(grudges[k]) - decay_dt
				if float(grudges[k]) <= 0.0:
					expired.append(k)
			for k in expired:
				grudges.erase(k)
		if not habituated.is_empty():
			for k in habituated.keys():
				habituated[k] = clampf(
					float(habituated[k]) + decay_dt * 0.0008, 0.0, 1.0)
		if feed_heatmap.size() > 0:
			# One bulk decay step per throttle window instead of stochastic
			# per-tick. Multiplicative so peaks fade proportionally.
			var heat_decay: float = pow(0.985, decay_dt / 0.1)
			for i in range(feed_heatmap.size()):
				feed_heatmap[i] *= heat_decay
	# Hunger accumulates slowly. Real fish go days without eating; we keep
	# the rate gentle so fish can spend more time on courtship / schooling
	# / exploration than on frantic foraging. 0.006/s = ~165s from sated
	# to starvation if the fish never finds a bite (longer than most
	# fish lifespans, so starvation is a real but uncommon kill switch).
	hunger = clampf(hunger + dt * 0.006, 0.0, 1.0)
	# Walstad balance: well-planted, oxygenated tanks support fish with less
	# supplemental feeding pressure.
	if sim != null and sim.dissolved_o2 > 0.72 and sim.total_plant_biomass > 280:
		hunger = maxf(0.0, hunger - dt * 0.0018)
	# Fry graze microfauna (#42): the base of the food web feeds recruitment, so
	# fry survival depends on a healthy copepod / daphnia bloom — and a tank
	# with no microfauna starves its young.
	if maturity == MATURITY_FRY and sim != null:
		var w_micro: Node = sim.get_parent()
		if w_micro != null and w_micro.has_method("live_microfauna_count"):
			var micro_n: int = w_micro.live_microfauna_count()
			if micro_n > 4:
				hunger = maxf(0.0, hunger - dt * clampf(float(micro_n) / 60.0, 0.0, 1.0) * 0.012)
	var energy_drain := 0.004 + (0.04 if burst_remaining > 0.0 else 0.0)
	energy = clampf(energy - dt * energy_drain, 0.0, 1.0)
	burst_remaining = maxf(0.0, burst_remaining - dt)
	breed_cooldown = maxf(0.0, breed_cooldown - dt)
	nibble_cooldown = maxf(0.0, nibble_cooldown - dt)
	_startle_remaining = maxf(0.0, _startle_remaining - dt)
	# Acclimation: counts down from ACCLIMATION_DURATION when the fish
	# is newly spawned. Caps cycle-spike stress accrual while it ticks.
	_acclimation_remaining = maxf(0.0, _acclimation_remaining - dt)

	# Cycling-stage water-quality stress. Ammonia + nitrite are toxic
	# to fish at elevated concentrations; healthy established tanks read
	# them as near-zero. Fresh tanks during the cycle dump high levels
	# of both. Acclimating fish only feel a fraction of this stress, so
	# the player CAN drop fish into a new tank without immediate
	# panic — but they'll start stressing once acclimation ends if the
	# chemistry hasn't cleared.
	if sim != null and sim.water_chemistry != null and maturity != MATURITY_FRY:
		# Toxic (un-ionized) ammonia is what fish actually feel (#6): the same
		# total ammonia is harmless at low pH and lethal at high pH.
		var nh3: float = float(sim.water_chemistry.ammonia)
		if sim.water_chemistry.has_method("toxic_ammonia_level"):
			nh3 = float(sim.water_chemistry.toxic_ammonia_level())
		var no2: float = float(sim.water_chemistry.nitrite)
		# Toxic NH3: harmless below 0.02, lethal by ~0.2.
		# Nitrite: tolerable below 0.35, panic-inducing at >1.2.
		var nh3_stress: float = clampf((nh3 - 0.02) / 0.18, 0.0, 1.0)
		var no2_stress: float = clampf((no2 - 0.35) / 0.85, 0.0, 1.0)
		var total_chem: float = maxf(nh3_stress, no2_stress * 0.85)
		# Brown-blood (#28): nitrite cuts the O2 the fish can carry, so it gulps
		# at the surface even when dissolved O2 is fine.
		_chem_o2_penalty = no2_stress * 0.22
		# Acclimation discount: at full acclimation, 30% of normal
		# accrual; tapers to 100% once the buffer runs out.
		var accl_frac: float = clampf(
			_acclimation_remaining / ACCLIMATION_DURATION, 0.0, 1.0)
		var accl_mult: float = lerpf(1.0, 0.30, accl_frac)
		stress = clampf(stress + total_chem * accl_mult * dt * 0.045, 0.0, 1.0)
		# Severe + sustained chemistry kills. Real ammonia poisoning is
		# slow; we expose it as the "stress crosses 0.95 with bad chem"
		# branch so the existing die path picks it up naturally.
		if total_chem > 0.7 and stress > 0.95 and randf() < dt * 0.05:
			events["die"] = true
			return events

	# Gestation progress (livebearer females only)
	if is_livebearer and sex == 1 and _gestation_progress > 0.0:
		_gestation_progress += dt / GESTATION_DURATION
		if _gestation_progress >= 1.0:
			events["release_livebearer_fry"] = _gestation_genome.duplicate(true)
			_gestation_progress = 0.0
			_gestation_genome = {}
	# Mouthbrooding: bulge grows for MOUTHBROOD_DURATION, then the
	# female releases her brood. Stress / heavy chase can spit early
	# (real cichlid behavior).
	if _mouthbrood_progress > 0.0:
		_mouthbrood_progress += dt / MOUTHBROOD_DURATION
		# Stressed mothers spit early: stress > 0.7 + recent dart → drop now.
		if stress > 0.72 and burst_remaining > 0.15:
			_mouthbrood_progress = 1.0
		if _mouthbrood_progress >= 1.0:
			events["release_brooded_fry"] = {
				"genome": _mouthbrood_genome.duplicate(true),
				"count": _mouthbrood_count,
			}
			_mouthbrood_progress = 0.0
			_mouthbrood_genome = {}
			_mouthbrood_count = 0

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
				_aerial_return_y = home_y
				_aerial_target_y = _water_surface_y() - 0.2
				# Labyrinth surface association (#34): drift gulp under floater shade.
				if labyrinth_breather and sim != null:
					var w_lab: Node = sim.get_parent()
					if w_lab != null and w_lab.has_method("query_floaters_in_radius"):
						var near_fp: FloatingPlant = _find_nearest_floater(w_lab, 4.0)
						if near_fp != null:
							home_y = near_fp.position.y - 0.35
				_aerial_timer = randf_range(2.0, 3.5)   # trip duration
		else:
			_aerial_timer -= dt
			if _aerial_timer <= 0.0:
				if is_finite(_aerial_return_y):
					home_y = _aerial_return_y
				_aerial_return_y = INF
				_aerial_timer = -0.01

	# Schooling stress climbs if too few conspecifics nearby.
	var conspecifics_nearby: int = 0
	for n in neighbors:
		if n is Fish and (n as Fish).species == species:
			conspecifics_nearby += 1
	# Social need scales with how strong a schooler the species is (#88): a
	# tight schooler kept under-numbered is chronically stressed (teaching
	# "don't keep just one tetra"), while a solitary species is content alone.
	var ideal_shoal: int = int(round(clampf(schooling_strength, 0.0, 2.0) * 2.5))
	if maturity != MATURITY_FRY and ideal_shoal >= 2 and conspecifics_nearby < ideal_shoal:
		var deficit: float = clampf(
			float(ideal_shoal - conspecifics_nearby) / float(ideal_shoal), 0.0, 1.0)
		stress = clampf(stress + dt * 0.05 * deficit, 0.0, 1.0)
	else:
		stress = maxf(0.0, stress - dt * 0.08)
	if sim != null and sim.total_plant_biomass > 320 and sim.dissolved_o2 > 0.65:
		stress = maxf(0.0, stress - dt * 0.025)

	# Rest debt (#84): a fish disturbed at night banks fatigue; sleeping pays it
	# back. High rest debt makes it sluggish the next day (applied to the
	# day-activity multiplier below).
	var dl_rest: float = sim.daylight() if sim != null and sim.has_method("daylight") else 0.5
	if dl_rest < 0.3:
		_rest_debt = clampf(_rest_debt + stress * dt * 0.02, 0.0, 1.0)
		if _asleep:
			_rest_debt = maxf(0.0, _rest_debt - dt * 0.05)
	else:
		_rest_debt = maxf(0.0, _rest_debt - dt * 0.012)

	# Personality drift (#82): surviving a real fright nudges the fish warier
	# (lower boldness) once it calms — a lasting experiential mark, bounded so
	# it's a gentle lifelong arc rather than a runaway.
	if stress > 0.85:
		_scarred = true
	elif _scarred and stress < 0.25:
		_scarred = false
		if personality.has("boldness"):
			personality["boldness"] = clampf(float(personality["boldness"]) - 0.03, 0.05, 1.0)

	# Inner life: mood, curiosity, lingering fear, sleep, relief, blink, memory.
	# Runs before the behavior tiers so steering reads a fresh emotional state.
	_update_inner_life(dt, conspecifics_nearby)

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
	if maturity == MATURITY_SENESCENT and age >= max_age_s * (1.25 + _life_jitter):
		events["die"] = true
		return events
	# Diet-breadth starvation order (#34): narrow-diet specialists (obligate
	# carnivores, snail-hunters) run out of options first when the food web
	# collapses, so a die-off has a believable sequence and generalists outlast
	# specialists.
	var starve_thresh: float = 1.0
	if sim != null and (snail_predator or float(herbivory) < 0.15):
		var food_scarce: float = 1.0 - clampf(float(sim.total_plant_biomass) / 220.0, 0.0, 1.0)
		starve_thresh -= food_scarce * 0.12
	if hunger >= starve_thresh and energy < 0.12:
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
	var music_mods: Dictionary = _music_mods()
	effective_max *= float(music_mods.get("speed", 1.0))
	_apply_music_beat_surge(music_mods, effective_max)
	var fauna_rt: Dictionary = _fauna_runtime()
	current_mode = Mode.CRUISE

	# Tier 0: wall avoidance always runs (additive). Lateral glass only — floor
	# repulsion is handled by vertical band + home_y so fish don't climb the column.
	desired += _wall_avoid(world_bounds) * 4.0
	# Tier 0.1: soft anti-intersection steering. Keeps body volumes from
	# visually occupying the same space (other fish / dense plants /
	# hardscape) while staying subtle enough to preserve schooling.
	var clearance_plants: Array = sim.query_plants_in_radius(position, 0.45) \
		if sim != null and sim.has_method("query_plants_in_radius") else plants
	desired += _local_clearance_push(neighbors, clearance_plants) * 1.25
	desired += _hardscape_clearance_push() * 1.6

	# Tier 0.2: SURFACE GULPING (hypoxia response). Only surface-adapted fish
	# panic-gulp at the meniscus; mid-column species rely on the softer home_y
	# lerp in the cruise tier instead of racing the whole school to the top.
	var eff_o2: float = float(sim.dissolved_o2) - _chem_o2_penalty if sim != null else 1.0
	# Spatial O2 (#23): in an unaerated tank the bottom + dead corners hold
	# less O2, so bottom dwellers feel the squeeze first.
	if sim != null and sim.aeration_air_rate < 0.2 and sim.aeration_flow_rate < 0.2:
		var col_h0: float = maxf(_water_column_height(), 0.5)
		var depth_frac: float = clampf(
			1.0 - (position.y - float(sim.substrate_top_y)) / col_h0, 0.0, 1.0)
		eff_o2 -= depth_frac * 0.08
	if sim != null and eff_o2 < SURFACE_GULP_O2:
		var col_h: float = maxf(_water_column_height(), 0.5)
		var top_frac: float = clampf((preferred_y - float(sim.substrate_top_y)) / col_h, 0.0, 1.0)
		var surface_adapted: bool = mouth_orientation == -1 or labyrinth_breather \
			or top_frac >= 0.62 or swim_pattern == "dart"
		if surface_adapted:
			var surface_y: float = _water_surface_y() - 0.15
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
		# Keep nests below the meniscus — brooding parents shouldn't pin at surface.
		var nest_ceiling: float = _water_surface_y() - 0.55
		if brooding_at.y > nest_ceiling:
			brooding_at.y = nest_ceiling
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
		elif to_nest.length() < 0.6:
			# PARENTAL CARE: with no intruder to chase, the parent hovers over
			# the clutch and fans it — a gentle pectoral-driven shimmy that
			# oxygenates the eggs. Reads as attentive, devoted tending.
			if _fidget_remaining <= 0.0 and randf() < dt * 0.5:
				_fidget_kind = 1   # shimmy = fanning motion
				_fidget_remaining = 0.7
			mood = clampf(mood + dt * 0.08, -1.0, 1.0)   # proud, settled parent
		target_velocity = _apply_target_from_desired(desired, effective_max)
		return events

	# Tier 0.32: TERRITORY DEFENSE. Territorial species enforce a personal
	# zone around home_x/y/z. Same-species intruders inside home_radius
	# get chased out; subordinates (smaller, younger) yield instead. Alpha
	# rank = size_potential × age_factor — bigger and older wins. Real
	# cichlid + betta + gourami behavior.
	_territory_cooldown = maxf(0.0, _territory_cooldown - dt)
	if is_territorial and maturity == MATURITY_ADULT \
			and _territory_cooldown <= 0.0 and brooding_remaining <= 0.0:
		# Validate ongoing chase.
		if _territory_chase_target != null:
			if not is_instance_valid(_territory_chase_target) \
					or _territory_chase_target.maturity == MATURITY_FRY \
					or _territory_chase_target.position.distance_squared_to(position) \
						> (home_radius * 2.5) * (home_radius * 2.5):
				_territory_chase_target = null
				_territory_chase_t = 0.0
				_territory_cooldown = TERRITORY_CHASE_COOLDOWN
		# Pick a new target if needed.
		if _territory_chase_target == null:
			var my_rank: float = size_potential * (0.5 + 0.5 * clampf(age / max_age_s, 0.0, 1.0))
			var best_int: Fish = null
			var best_score: float = 0.0
			for n in neighbors:
				if not (n is Fish):
					continue
				var nf: Fish = n
				if nf == self or nf == partner or nf.species != species:
					continue
				if nf.maturity == MATURITY_FRY:
					continue
				# Is the intruder inside my home zone?
				var dx: float = nf.position.x - home_x
				var dz: float = nf.position.z - home_z
				if dx * dx + dz * dz > home_radius * home_radius:
					continue
				var their_rank: float = nf.size_potential \
					* (0.5 + 0.5 * clampf(nf.age / nf.max_age_s, 0.0, 1.0))
				if their_rank >= my_rank:
					# Subordinate-to-them — we yield rather than chase.
					continue
				# Score = how deep they are inside my radius (closer to my
				# center = higher priority chase).
				var depth: float = home_radius * home_radius - (dx * dx + dz * dz)
				if depth > best_score:
					best_score = depth
					best_int = nf
			if best_int != null:
				_territory_chase_target = best_int
				_territory_chase_t = 0.0
		if _territory_chase_target != null and is_instance_valid(_territory_chase_target):
			_territory_chase_t += dt
			var to_t: Vector3 = _territory_chase_target.position - position
			if to_t.length_squared() > 1e-4:
				desired += to_t.normalized() * effective_max * 1.6
				if burst_remaining < 0.2:
					burst_remaining = 0.2
			# Hit the intruder with a small stress nudge so a chase produces
			# the visible flee response on their end.
			var tgt: Fish = _territory_chase_target
			tgt.stress = clampf(tgt.stress + dt * 0.20, 0.0, 1.0)
			# Grudge formation: the chasee remembers WHO chased it (by id).
			# 10 real-time minutes. The food-finder and home-pull code can
			# read grudges[chaser_id] to give the bully extra berth instead
			# of just "predator-class avoidance".
			if id != "" and not tgt.grudges.has(id):
				tgt.grudges[id] = 600.0
			# End the chase after a short bout — the intruder gets the
			# message; we go on cooldown so chases don't loop forever.
			if _territory_chase_t >= TERRITORY_CHASE_DURATION:
				# Dominance + bio: chaser earns a fight win, both fish drift
				# in rank. The drift is small (0.02) so a single fight doesn't
				# flip the hierarchy — but consistent winners accumulate
				# clear alpha status across many bouts.
				if not bio.is_empty():
					bio["fights_won"] = int(bio.get("fights_won", 0)) + 1
				rank_within_species = clampf(rank_within_species + 0.02, 0.0, 1.0)
				tgt.rank_within_species = clampf(tgt.rank_within_species - 0.02, 0.0, 1.0)
				_territory_chase_target = null
				_territory_chase_t = 0.0
				_territory_cooldown = TERRITORY_CHASE_COOLDOWN
			target_velocity = _apply_target_from_desired(desired, effective_max)
			return events

	# Tier 0.34: CLEANING STATION (fish side). When stress is elevated and
	# a cleaner shrimp/wrasse is within reach, the fish swims over and
	# parks for a clean. Real coral-reef + freshwater behavior — the
	# recipient slows, tilts, and visibly "presents" gills/flanks for
	# parasite-pick service. Shrimp side handles the actual stress drop;
	# this just steers the fish into position.
	if maturity != MATURITY_FRY and stress > 0.45 and sim != null:
		var cleaner: Node3D = _find_nearest_cleaner(3.0)
		if cleaner != null:
			_seeking_clean = true
			var to_c: Vector3 = (cleaner as Node3D).position - position
			var d: float = to_c.length()
			if d > 0.45:
				# Approach the cleaning station — moderate pull so we
				# arrive without overshoot.
				desired += to_c.normalized() * effective_max * 0.65
			else:
				# Parked: damp velocity, hold a small tilt, gain a tiny
				# stress relief (mirrors the shrimp's contribution so
				# fast-disappearing shrimp still produce some calm).
				_being_cleaned = 1.0
				stress = maxf(0.0, stress - dt * 0.18)
				desired *= 0.05
			target_velocity = _apply_target_from_desired(desired, effective_max)
			return events
	else:
		_seeking_clean = false
	# Cleaned-flag decays so the tilt smoothly clears.
	if _being_cleaned > 0.0:
		_being_cleaned = maxf(0.0, _being_cleaned - dt * 1.2)

	# Tier 0.34b: WOOD GRAZER. Bristlenose plecos + similar species
	# spend their lives clinging to driftwood, rasping biofilm. When
	# hungry they actively seek out the nearest log; when satiated they
	# hover near it. Real plecos basically don't leave the wood.
	if wood_grazer and maturity != MATURITY_FRY and sim != null:
		var wood_pos: Vector3 = sim.nearest_driftwood_pos(position)
		if wood_pos != Vector3.ZERO:
			var to_wood: Vector3 = wood_pos - position
			var d_wood: float = to_wood.length()
			# Hungry plecos pull hard; satiated ones gently hold a
			# rest position next to the log.
			var hunger_pull: float = lerpf(0.35, 1.05, clampf(hunger * 1.5, 0.0, 1.0))
			if d_wood > 0.45:
				desired += to_wood.normalized() * effective_max * hunger_pull
			else:
				# At the log — damp velocity, nibble waste/algae locally.
				desired *= 0.25
				# Reading the wood as a meal: low-rate hunger relief
				# proportional to existing biofilm on this driftwood.
				if hunger > 0.2:
					hunger = maxf(0.0, hunger - dt * 0.012)

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
		var candidates: Array = sim.query_plants_in_radius(position, 4.0) \
			if sim != null and sim.has_method("query_plants_in_radius") else plants
		for p in candidates:
			if not is_instance_valid(p):
				continue
			if p.biomass() < 8:
				continue
			var d2: float = p._world_pos.distance_squared_to(position)
			if d2 < shelter_d2:
				shelter_d2 = d2
				shelter = p
		# Fry refuge under floater roots (#32).
		var w_fry: Node = sim.get_parent() if sim != null else null
		var floater_cover: FloatingPlant = null
		if w_fry != null and w_fry.has_method("query_floaters_in_radius"):
			for fp in w_fry.query_floaters_in_radius(position, 3.5):
				if fp is FloatingPlant and (fp as FloatingPlant).is_fry_cover():
					var fd2: float = fp.position.distance_squared_to(position)
					if fd2 < shelter_d2:
						shelter_d2 = fd2
						floater_cover = fp
		if floater_cover != null:
			var to_roots: Vector3 = floater_cover.position - position
			to_roots.y -= floater_cover.root_length_current * 0.4
			if to_roots.length() > 0.5:
				desired += to_roots.normalized() * effective_max * 0.55
			else:
				desired *= 0.12
		elif w_fry != null and w_fry.has_method("query_lily_pads_in_radius"):
			var lily_cover: Node3D = null
			for lp in w_fry.query_lily_pads_in_radius(position, 4.0):
				if not is_instance_valid(lp) or not lp.has_method("fry_shade_factor"):
					continue
				if float(lp.fry_shade_factor()) < 0.2:
					continue
				var lp_pos: Vector3 = lp.global_position
				if lp.has_method("surface_rest_position"):
					lp_pos = lp.surface_rest_position()
				var ld2: float = Vector2(lp_pos.x - position.x, lp_pos.z - position.z).length_squared()
				if ld2 < shelter_d2:
					shelter_d2 = ld2
					lily_cover = lp
			if lily_cover != null:
				var to_pad: Vector3 = lily_cover.global_position - position
				if lily_cover.has_method("surface_rest_position"):
					to_pad = lily_cover.surface_rest_position() - position
				to_pad.y = -0.35
				if to_pad.length() > 0.45:
					desired += to_pad.normalized() * effective_max * 0.5
				else:
					desired *= 0.18
		elif shelter != null:
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
	# Desperation overrides fear (#86): a starving fish braves the open to feed
	# even when stressed — need-arbitration, not a fixed fear response.
	if stress > STRESS_HIDE_THRESHOLD and hunger < 0.85:
		var nearest_cover: Plant = null
		var cover_d2: float = 9.0  # within 3 units to count as reachable
		var cover_candidates: Array = sim.query_plants_in_radius(position, 3.0) \
			if sim != null and sim.has_method("query_plants_in_radius") else plants
		for p in cover_candidates:
			if not is_instance_valid(p):
				continue
			if p.biomass() < 6:
				continue
			var d2: float = p._world_pos.distance_squared_to(position)
			d2 += absf(p._world_pos.y - preferred_y) * 0.35
			if d2 < cover_d2:
				cover_d2 = d2
				nearest_cover = p
		if nearest_cover != null:
			var to_cover: Vector3 = nearest_cover._world_pos - position
			to_cover.y = lerpf(preferred_y, nearest_cover._world_pos.y + 0.4, 0.55)
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
			# REJECTION BEAT. Courtship is a real negotiation, not a timer.
			# Early in the dance the female may reject an unimpressive suitor
			# (low rank/size, or she's stressed/unwell) — she breaks off, darts
			# away, and the male is left displaying to no one. Only fires in the
			# first third of the dance so committed pairs still spawn.
			if sex == 1 and court_timer < COURT_DURATION * 0.33 and court_timer > 0.4:
				var suitor_appeal: float = partner.rank_within_species * 0.5 \
					+ clampf(partner.growth_factor - 0.8, 0.0, 0.6) + mood * 0.2
				var reject_chance: float = clampf(0.06 - suitor_appeal * 0.05 + stress * 0.08, 0.0, 0.12)
				if randf() < reject_chance * dt:
					# She's not interested. Both reset; she flees a beat.
					if is_instance_valid(partner):
						partner.partner = null
						partner.court_timer = 0.0
						partner._courtship_flare = false
						partner.mood = clampf(partner.mood - 0.15, -1.0, 1.0)
					partner = null
					court_timer = 0.0
					_courtship_flare = false
					_courtship_intensity = 0.0
					burst_remaining = 0.35
					return events
			var to_partner: Vector3 = partner.position - position
			var dist: float = to_partner.length()
			# Swim alongside (not into) the partner: target a point slightly to one side.
			var side: Vector3 = to_partner.cross(Vector3.UP).normalized() * 0.4
			var courtship_target: Vector3 = partner.position + side
			courtship_target.y = lerpf(home_y, partner.home_y, 0.5)
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
				# Per-species courtship choreography. Each pattern picks a
				# distinct lateral / vertical envelope so the dance reads
				# differently per fish without needing per-species presets.
				var s_amp: float = lerpf(0.15, 0.45, _courtship_intensity)
				var lateral: Vector3 = to_partner.cross(Vector3.UP).normalized()
				var s_offset: Vector3 = Vector3.ZERO
				match swim_pattern:
					"dart":
						# Jerky lateral flash + brief pauses. Sin-square gives
						# a sharper "snap forward / hold" pulse than smooth sin.
						var snap: float = sign(sin(t_phase))
						s_offset = lateral * snap * s_amp * 1.2
					"hover":
						# Tight vertical figure-8 around the partner — real
						# angelfish + discus court. Adds a Y-component that
						# crosses lateral on a different beat.
						s_offset = lateral * sin(t_phase) * s_amp * 0.55
						s_offset.y += sin(t_phase * 2.0) * s_amp * 0.7
					"meander":
						# Slow wide lateral display — long-fin show species.
						s_offset = lateral * sin(t_phase * 0.6) * s_amp * 1.4
					"cruise":
						# Wide circling — fast open-water species (danios,
						# rainbows). Lateral with a forward push so the
						# orbit reads as forward motion.
						s_offset = lateral * sin(t_phase) * s_amp
						s_offset += to_partner.normalized() * sin(t_phase * 0.5) * s_amp * 0.4
					_:
						# Default school / shoal: side-by-side parallel S-curve.
						s_offset = lateral * sin(t_phase) * s_amp
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
				elif is_mouthbrooder or (partner != null and partner.is_mouthbrooder):
					# Mouthbrooders: the female scoops up the fertilized
					# eggs and incubates them in her throat. Visible bulge
					# grows for MOUTHBROOD_DURATION before fry release.
					var mom: Fish = self if sex == 1 else partner
					var dad: Fish = partner if sex == 1 else self
					if mom != null and dad != null:
						mom._mouthbrood_progress = 0.01
						mom._mouthbrood_genome = mom.produce_offspring_genome(dad)
						mom._mouthbrood_count = mini(mom.clutch_size, 4)
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
				# Bio: both parents log an offspring. Each spawn produces a
				# variable clutch but we count the *event* (one breeding
				# moment) — the player sees "4 offspring" and reads that
				# as four successful breeds, which matches reality better
				# than fry-counted-on-egg-hatch.
				if not bio.is_empty():
					bio["offspring"] = int(bio.get("offspring", 0)) + 1
				if partner != null and not partner.bio.is_empty():
					partner.bio["offspring"] = int(partner.bio.get("offspring", 0)) + 1
				# Pair bond + shared joy. Successful mates form a lasting
				# positive affinity (recorded as longest_friend) and both get
				# a mood lift — relationships you can read across the tank.
				if partner != null:
					if partner.id != "":
						bonds[partner.id] = clampf(float(bonds.get(partner.id, 0.0)) + 0.5, -1.0, 1.0)
					if id != "":
						partner.bonds[id] = clampf(float(partner.bonds.get(id, 0.0)) + 0.5, -1.0, 1.0)
					if not bio.is_empty():
						bio["longest_friend_id"] = partner.id
					if not partner.bio.is_empty():
						partner.bio["longest_friend_id"] = id
					mood = clampf(mood + 0.4, -1.0, 1.0)
					partner.mood = clampf(partner.mood + 0.4, -1.0, 1.0)
					remember("bred", position, 16.0)
					partner.remember("bred", position, 16.0)
				partner.partner = null
				partner = null
				court_timer = 0.0
				_courtship_flare = false
				_courtship_sync = false
				_courtship_intensity = 0.0
			target_velocity = _apply_target_from_desired(desired, effective_max)
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
		# Pecking order at feed events. Bold fish (high dart_chance, low
		# stress) see food from farther away and pursue more aggressively
		# than timid fish, so dropped pellets visibly draw a queue: bold
		# ones up front, timid ones lagging at the back.
		var boldness: float = _boldness()
		var best_w: WasteParticle = null
		# Range scales with boldness: timid fish see ~6u, bold ones see ~14u.
		var awareness: float = 36.0 + boldness * 72.0
		var best_d2: float = awareness
		# Spatial memory of recent feed taps — drag the awareness radius
		# toward recently-fed spots so the fish "remembers" where pellets
		# usually land.
		var memory_bias: Vector3 = Vector3.ZERO
		var memory_pull: float = 0.0
		if sim != null and sim.has_method("recent_feed_spot_bias"):
			var bias: Dictionary = sim.recent_feed_spot_bias(position, 16.0)
			memory_bias = bias.get("offset", Vector3.ZERO)
			memory_pull = float(bias.get("strength", 0.0))
		var waste_near: Array = waste
		if sim != null and sim.has_method("query_waste_in_radius"):
			waste_near = sim.query_waste_in_radius(position, 12.0)
		for w in waste_near:
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
				if y_delta > home_y_radius * 1.5:
					d2 *= 1.0 + clampf((y_delta - home_y_radius * 1.5) * 0.45, 0.0, 1.0)
				d2 *= _food_appeal_multiplier(w)
				# Bold fish discount food cost; timid fish inflate it.
				d2 *= lerpf(1.6, 0.55, clampf(boldness / 1.8, 0.0, 1.0))
			if d2 < max_dist_sq and d2 < best_d2:
				best_d2 = d2
				best_w = w
		# If no food in sight but we remember a recent drop, drift toward
		# the remembered spot so the school converges before the pellets
		# even hit our awareness range.
		if best_w == null and memory_pull > 0.0 and hunger > 0.45:
			desired += memory_bias.normalized() * effective_max * memory_pull * boldness
		if best_w != null:
			current_mode = Mode.FORAGE
			var to_w: Vector3 = best_w.global_position - position
			if to_w.length() < 0.4:
				events["eat_waste"] = best_w
				var is_food: bool = best_w.kind == 3
				_record_meal_at(position, 1.5 if is_food else 0.7)
				hunger = maxf(0.0, hunger - (FOOD_HUNGER_DELTA if is_food else WASTE_HUNGER_DELTA))
				energy = minf(1.0, energy + (FOOD_ENERGY_DELTA if is_food else WASTE_ENERGY_DELTA))
				# All meals rewind the age clock a little.
				age = maxf(0.0, age - max_age_s * MEAL_AGE_REDUCTION_FRAC)
				if is_food:
					# High-quality food stacks an additional big revival.
					age = maxf(0.0, age - max_age_s * FOOD_AGE_REVIVAL_FRAC)
					stress = 0.0
					match best_w.food_subtype:
						WasteParticle.FOOD_SUB_WORM:
							hunger = maxf(0.0, hunger - FOOD_HUNGER_DELTA * 0.35)
							burst_remaining = maxf(burst_remaining, 0.65)
						WasteParticle.FOOD_SUB_FLAKE:
							if mouth_orientation == -1:
								burst_remaining = maxf(burst_remaining, 0.4)
						WasteParticle.FOOD_SUB_WAFER:
							if herbivory > 0.4 or algae_grazer:
								energy = minf(1.0, energy + FOOD_ENERGY_DELTA * 0.25)
					if maturity == MATURITY_SENESCENT and age < max_age_s:
						maturity = MATURITY_ADULT
					if _food_glow != null:
						_food_glow.light_energy = FOOD_GLOW_ENERGY
				# Eating consumes the rest of this tick: apply accumulated
				# steering (wall_avoid + schooling) and return. Without this
				# return, the fish falls through into predation/breeding
				# tiers and can record multiple conflicting events that
				# overwrite each other in the same dict.
				target_velocity = _apply_target_from_desired(desired, effective_max)
				return events
			else:
				var pull: float = 0.9
				if best_w.kind == 3: # FOOD
					var appeal: float = _food_appeal_multiplier(best_w)
					pull = lerpf(1.4, 2.4, 1.0 - clampf(appeal - 0.4, 0.0, 1.6) / 1.6)
					var age_factor: float = clampf(age / max_age_s, 0.0, 1.2)
					pull += age_factor * 1.5
					var frenzy_chance: float = 0.4
					if best_w.food_subtype == WasteParticle.FOOD_SUB_WORM and herbivory < 0.35:
						frenzy_chance = 0.78
					elif best_w.food_subtype == WasteParticle.FOOD_SUB_FLAKE and mouth_orientation == -1:
						frenzy_chance = 0.62
					if burst_remaining <= 0.0 and energy > 0.15 and randf() < frenzy_chance:
						burst_remaining = randf_range(0.4, 0.75) + (age_factor * 0.3)
						_startle_heading = to_w.normalized()
						_startle_remaining = 0.5
				desired += to_w.normalized() * effective_max * pull
				target_velocity = _apply_target_from_desired(desired, effective_max)
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
				# Prey refuge (#33) + Holling-II functional response (#32): a
				# well-planted tank lets prey hide, and the fewer prey remain
				# the harder each is to catch (search time rises). Together
				# these stop a predator from instantly wiping a school and make
				# it starve in a depleted tank — producing real boom/bust cycles.
				var escape: float = 0.0
				if sim != null:
					escape += clampf(float(sim.total_plant_biomass) / 900.0, 0.0, 0.35)
					var prey_n: int = sim.fish.size() + sim.shrimp.size()
					escape += clampf((8.0 - float(prey_n)) / 8.0, 0.0, 0.40)
				if randf() < escape:
					if best_prey is Fish:
						(best_prey as Fish).stress = clampf(
							(best_prey as Fish).stress + 0.10, 0.0, 1.0)
					if burst_remaining <= 0.0 and energy > 0.3:
						burst_remaining = 0.5
					desired += to_prey.normalized() * effective_max * 1.3
					target_velocity = _apply_target_from_desired(desired, effective_max)
					return events
				events["kill_prey"] = best_prey
				_record_meal_at(position, 2.0)
				hunger = maxf(0.0, hunger - 0.50)
				energy = minf(1.0, energy + 0.18)
				age = maxf(0.0, age - max_age_s * MEAL_AGE_REDUCTION_FRAC)
				events["waste_at"] = position + Vector3(0, -0.1, 0)
				events["waste_amount"] = 0.20
				# A successful kill ends the tick. Falling through would
				# overwrite events["kill_prey"] / events["waste_at"] with a
				# later tier's target and drop the actual predation.
				target_velocity = _apply_target_from_desired(desired, effective_max)
				return events
			else:
				if burst_remaining <= 0.0 and energy > 0.3:
					burst_remaining = 0.5
				desired += to_prey.normalized() * effective_max * 1.3
				target_velocity = _apply_target_from_desired(desired, effective_max)
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
				target_velocity = _apply_target_from_desired(desired, effective_max)
				return events
			var to_prey: Vector3 = prey.global_position - position
			if to_prey.length() < 0.35:
				events["kill_prey"] = prey
				var meal_mult: float = clampf(1.0 - repel * 0.65, 0.2, 1.0)
				_record_meal_at(position, meal_mult * 1.5)
				hunger = maxf(0.0, hunger - 0.40 * meal_mult)
				energy = minf(1.0, energy + 0.12 * meal_mult)
				stress = minf(1.0, stress + prey_toxin * 0.16)
				age = maxf(0.0, age - max_age_s * MEAL_AGE_REDUCTION_FRAC)
				events["waste_at"] = position + Vector3(0, -0.1, 0)
				events["waste_amount"] = 0.15
				# Successful baby-shrimp kill: end the tick so events don't
				# get stomped by Tier 1.9 / 2 below.
				target_velocity = _apply_target_from_desired(desired, effective_max)
				return events
			else:
				if burst_remaining <= 0.0 and energy > 0.3:
					burst_remaining = 0.4
				desired += to_prey.normalized() * effective_max * 1.2
				target_velocity = _apply_target_from_desired(desired, effective_max)
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
					target_velocity = _apply_target_from_desired(desired, effective_max)
					return events
				else:
					if burst_remaining <= 0.0 and energy > 0.3:
						burst_remaining = 0.35
					desired += to_snail.normalized() * effective_max * 1.1
					target_velocity = _apply_target_from_desired(desired, effective_max)
					return events
		if herbivory > 0.0 and algae_array.size() > 0:
			var best_alga: Node3D = null
			var best_alga_rank: float = 6.0
			var best_alga_d2: float = 6.0
			var algae_near: Array = algae_array
			if sim != null and sim.has_method("query_algae_in_radius"):
				algae_near = sim.query_algae_in_radius(position, 2.5)
			for a in algae_near:
				if not is_instance_valid(a):
					continue
				var d2: float = (a.global_position - position).length_squared()
				# Grazer-specific control (#59): algae-grazers (otos) prefer the
				# glass films (GSA / GDA / diatoms) so they actually keep those
				# in check; generalist herbivores prefer soft clusters. We bias
				# the RANKING distance, not the real one, so eats still need
				# true contact.
				var rank: float = d2
				if a.has_method("algae_kind"):
					var ak: int = a.algae_kind()
					if algae_grazer:
						if ak == Algae.AlgaeKind.GSA or ak == Algae.AlgaeKind.GDA \
								or ak == Algae.AlgaeKind.DIATOM:
							rank *= 0.45
					elif ak == Algae.AlgaeKind.CLUSTER:
						rank *= 0.7
				if rank < best_alga_rank:
					best_alga_rank = rank
					best_alga_d2 = d2
					best_alga = a
			if best_alga != null:
				current_mode = Mode.FORAGE
				if best_alga_d2 < 0.25:
					events["eat_algae"] = best_alga
					_trigger_mouth_gape()
					hunger = maxf(0.0, hunger - 0.2)
					age = maxf(0.0, age - max_age_s * MEAL_AGE_REDUCTION_FRAC)
					# Algae crop done: return so Tier 2 herbivore plant-nibbling
					# below doesn't add an events["waste_at"] entry for this
					# same tick and double-count nutrients.
					target_velocity = _apply_target_from_desired(desired, effective_max)
					return events
				else:
					var to_alga: Vector3 = best_alga.global_position - position
					desired += to_alga.normalized() * effective_max * 0.9
					target_velocity = _apply_target_from_desired(desired, effective_max)
					return events

	# Tier 1.9: SURFACE FLOATER GRAZE (#31). Herbivores / top feeders crop mats.
	var surface_feeder: bool = preferred_y >= 4.2 or mouth_orientation < 0 or labyrinth_breather
	if herbivory > 0.25 and surface_feeder and hunger > 0.35 and maturity != MATURITY_FRY \
			and nibble_cooldown <= 0.0:
		var w_graze: Node = sim.get_parent() if sim != null else null
		if w_graze != null and w_graze.has_method("query_floaters_in_radius"):
			var target_fp: FloatingPlant = _find_nearest_floater(w_graze, 3.5)
			if target_fp != null:
				current_mode = Mode.FORAGE
				var fp_pos: Vector3 = target_fp.global_position
				fp_pos.y = _water_surface_y() - 0.08
				var fp_d2: float = fp_pos.distance_squared_to(position)
				if fp_d2 < 0.36:
					var ftaken: int = target_fp.nibble(1)
					if ftaken > 0:
						_trigger_mouth_gape()
						hunger = maxf(0.0, hunger - 0.22 * float(ftaken))
						energy = minf(1.0, energy + 0.05 * float(ftaken))
						nibble_cooldown = 0.85
						events["waste_at"] = position + Vector3(0, -0.08, 0)
						events["waste_amount"] = 0.12 * float(ftaken)
				else:
					desired += (fp_pos - position).normalized() * effective_max * 0.85
					target_velocity = _apply_target_from_desired(desired, effective_max)
					return events

	# Surface-feeder shade drift + stress relief (#38, #39) and lily-pad rest (#45).
	if surface_feeder and hunger < 0.5 and stress > 0.08:
		var w_shade: Node = sim.get_parent() if sim != null else null
		if w_shade != null and w_shade.has_method("query_floaters_in_radius"):
			var shade_fp: FloatingPlant = _find_nearest_floater(w_shade, 2.8)
			if shade_fp != null:
				var under: Vector3 = shade_fp.position - position
				under.y = 0.0
				if under.length() > 0.25:
					desired += under.normalized() * effective_max * 0.25
				else:
					stress = maxf(0.0, stress - dt * 0.04)
		if w_shade != null and w_shade.has_method("query_lily_pads_in_radius") \
				and hunger < 0.42 and maturity != MATURITY_FRY:
			var rest_pad: Node3D = null
			var rest_d2: float = 9.0
			for lp in w_shade.query_lily_pads_in_radius(position, 3.2):
				if not is_instance_valid(lp) or not lp.has_method("effective_shade_radius"):
					continue
				if float(lp.effective_shade_radius()) < 0.12:
					continue
				var pad_pos: Vector3 = lp.global_position
				if lp.has_method("surface_rest_position"):
					pad_pos = lp.surface_rest_position()
				var d2: float = Vector2(pad_pos.x - position.x, pad_pos.z - position.z).length_squared()
				if d2 < rest_d2:
					rest_d2 = d2
					rest_pad = lp
			if rest_pad != null:
				var rest_pos: Vector3 = rest_pad.global_position
				if rest_pad.has_method("surface_rest_position"):
					rest_pos = rest_pad.surface_rest_position()
				rest_pos.y = _water_surface_y() - 0.1
				var to_rest: Vector3 = rest_pos - position
				if to_rest.length() > 0.4:
					desired += to_rest.normalized() * effective_max * 0.32
				else:
					desired *= 0.18
					stress = maxf(0.0, stress - dt * 0.035)

	# Tier 2: HUNGRY HERBIVORE. Plants need at least 15 voxels of biomass
	# so fish have more food options before the shrimp graze them
	# down to nothing.
	# Lush-tank cropping bonus: when total plant biomass is high, herbivores
	# graze more eagerly (food is everywhere, less seeking cost). This is
	# the negative-feedback brake on plant overgrowth — without it, plants
	# coast to max_height and never get cropped back into a balanced
	# canopy. The 0.6× lush_bonus shifts both the random gate (up to 80%)
	# and the hunger threshold (down to 0.40) when biomass passes ~450.
	var lush_bonus: float = 0.0
	if sim != null:
		var b: int = int(sim.get("total_plant_biomass") if sim.get("total_plant_biomass") != null else 0)
		lush_bonus = clampf((float(b) - 150.0) / 300.0, 0.0, 0.6)
	var herb_hunger_gate: float = 0.55 - lush_bonus * 0.25
	var herb_random_gate: float = 0.5 + lush_bonus * 0.5
	if herbivory > 0.0 and hunger > herb_hunger_gate and maturity != MATURITY_FRY \
			and randf() < herb_random_gate:
		if target_plant == null or not is_instance_valid(target_plant) \
				or target_plant.biomass() < 15:
			target_plant = _find_nearest_tall_plant(plants, 5.0, 15)
		if target_plant != null:
			current_mode = Mode.FORAGE
			var top: Vector3 = target_plant.global_position
			top.y = _plant_graze_y(target_plant)
			var dist_sq: float = top.distance_squared_to(position)
			if dist_sq < 0.25 and nibble_cooldown <= 0.0:
				var taken := target_plant.nibble(1)
				if taken > 0:
					_trigger_mouth_gape()
					hunger = maxf(0.0, hunger - 0.30 * float(taken))
					energy = minf(1.0, energy + 0.06 * float(taken))
					age = maxf(0.0, age - max_age_s * MEAL_AGE_REDUCTION_FRAC * float(taken))
					nibble_cooldown = 0.9
					events["waste_at"] = position + Vector3(0, -0.1, 0)
					events["waste_amount"] = 0.15 * float(taken)
				target_plant = null
			else:
				if hunger > 0.8 and burst_remaining <= 0.0 and energy > 0.3:
					burst_remaining = 0.6
				desired += (top - position).normalized() * effective_max
				target_velocity = _apply_target_from_desired(desired, effective_max)
				return events

	# Tier 3: SEEK PARTNER. Adult, well-fed, not on cooldown, no current
	# partner. No global population cap — density is limited by food,
	# predation, and territory instead.
	# Livebearer males don't initiate courtship. Real guppy / platy
	# females cruise to sheltered cover and the male follows her there;
	# we approximate that here by letting only the female (sex == 1) of
	# a livebearer species call _find_breeding_partner. The male can
	# still ACCEPT a bond when a female pairs with him (handled by the
	# `candidate.partner = self` line below).
	var female_initiator_only: bool = is_livebearer and sex == 0
	# Seasonal rhythm: fish breed readily in spring and slow in winter, so the
	# population has a living annual cadence (driven by the real-world month,
	# same source as the seasonal palette shift).
	var season_breed: float = _season_breed_mult()
	if not female_initiator_only and maturity == MATURITY_ADULT \
			and breed_cooldown <= 0.0 and partner == null \
			and hunger < 0.5 and energy > 0.65 / season_breed \
			and stress < 0.4 * season_breed \
			and randf() >= _logistic_breed_suppress():
		# Mate loyalty (#83): prefer re-bonding with the previous partner if it's
		# nearby and available, before rolling a fresh mate.
		var candidate: Fish = _find_preferred_mate(neighbors)
		if candidate == null:
			candidate = _find_breeding_partner(neighbors)
		if candidate != null and candidate.partner == null:
			# Mutual pair-bond.
			partner = candidate
			candidate.partner = self
			_mate_id = String(candidate.id)
			candidate._mate_id = String(id)
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
	if burst_remaining <= 0.0:
		effective_max *= float(fauna_rt.get("speed", 1.0))
	# When stressed (too few neighbors), tighten the school dramatically.
	var tightness: float = 1.0 + stress * 1.5
	tightness *= float(music_mods.get("tightness", 1.0))
	# Tank-wide school pulse. Synchronised across every fish that samples
	# sim.school_pulse(), so the entire group visibly breathes in and out.
	if bool(fauna_rt.get("pulse_on", true)) and sim != null and sim.has_method("school_pulse"):
		tightness *= 1.0 + sim.school_pulse() * float(fauna_rt.get("pulse_amp", 0.15))
	# Mourning: when a same-species schoolmate just died nearby, intensify
	# cohesion and dampen our top speed for ~60s.
	var mourning_w: float = 0.0
	if bool(fauna_rt.get("mourning", true)) and sim != null \
			and sim.has_method("mourning_intensity_for"):
		mourning_w = sim.mourning_intensity_for(species, position)
		if mourning_w > 0.01:
			tightness *= 1.0 + mourning_w * 0.8
	# PREDATOR BALLING. When a much larger fish (a potential predator) is
	# close, the school cinches into a tight defensive ball and everyone's
	# fear spikes — the classic baitball response. Cheap manual scan; N small.
	var predator_near: float = 0.0
	for n in neighbors:
		if not (n is Fish):
			continue
		var pf: Fish = n
		if pf == self or pf.species == species:
			continue
		# "Threatening" = noticeably bigger than us (size-based predation uses
		# growth_factor >= 1.3 elsewhere) and within a body-lengths radius.
		if pf.growth_factor * pf.adult_voxel_scale > adult_voxel_scale * 1.25:
			var pd2: float = pf.position.distance_squared_to(position)
			if pd2 < 12.0:
				predator_near = maxf(predator_near, 1.0 - sqrt(pd2) / 3.5)
	if predator_near > 0.01:
		tightness *= 1.0 + predator_near * 1.6
		stress = clampf(stress + predator_near * dt * 0.6, 0.0, 1.0)
		spooked = clampf(spooked + predator_near * 0.3, 0.0, 1.0)
	var fauna_sep: float = float(fauna_rt.get("separation", 1.0))
	var school_w: float = schooling_strength * float(fauna_rt.get("schooling", 1.0))
	if float(music_mods.get("sweep", 0.0)) > 0.2:
		school_w *= maxf(0.22, 1.0 - float(music_mods.get("sweep", 0.0)) * 0.72)
	desired += _boids(neighbors, tightness, fauna_sep) * school_w
	# Soft territorial anchor — even inside home_radius, a gentle pull keeps
	# each schooler loosely tethered to its patrol zone so boids cohesion
	# can't collapse the whole population onto one centroid.
	if swim_pattern == "school" or swim_pattern == "shoal":
		var soft_home: Vector3 = Vector3(home_x - position.x, 0.0, home_z - position.z)
		var soft_d: float = soft_home.length()
		if soft_d > 0.05:
			var anchor_w: float = 0.14 if swim_pattern == "school" else 0.10
			anchor_w *= float(music_mods.get("home_pull", 1.0))
			anchor_w *= maxf(0.02, 1.0 - float(music_mods.get("sweep", 0.0)) * 0.96)
			desired += soft_home.normalized() * effective_max * anchor_w \
				* minf(soft_d / maxf(home_radius * float(music_mods.get("home_radius", 1.0)), 0.5), 1.0)

	# ---- Pre-walk neighbors ONCE ----
	# Four downstream blocks (personal space, gaze contagion, gaze
	# targeting, grudges) all walked `neighbors` independently doing the
	# same is-Fish + self + distance² filtering. We collapse them into a
	# single pre-walk that builds two parallel arrays the blocks read by
	# index. ~4× reduction in neighbor-loop iterations.
	var scan_fish: Array[Fish] = []
	var scan_d2: PackedFloat32Array = PackedFloat32Array()
	var scan_same_species: PackedByteArray = PackedByteArray()
	for n_pre in neighbors:
		if not (n_pre is Fish):
			continue
		var nf_pre: Fish = n_pre
		if nf_pre == self:
			continue
		scan_fish.append(nf_pre)
		scan_d2.append(nf_pre.position.distance_squared_to(position))
		scan_same_species.append(1 if nf_pre.species == species else 0)
	var scan_n: int = scan_fish.size()

	# PERSONAL SPACE. When a fish has many same-species neighbors crowded
	# inside ~2 units, push away from the local centroid. The standard
	# boids separation handles 1-on-1 spacing; this adds a soft "I don't
	# love being in a clump" bias that makes 30-fish schools distribute
	# naturally instead of converging on a single tight ball.
	var crowd_count: int = 0
	var crowd_centroid: Vector3 = Vector3.ZERO
	var crowd_zone_r2: float = 6.25 * fauna_sep * fauna_sep
	for i in scan_n:
		if scan_same_species[i] == 0:
			continue
		if scan_d2[i] < crowd_zone_r2:  # personal-space zone (scales with separation mult)
			crowd_count += 1
			crowd_centroid += scan_fish[i].position
	if crowd_count > 3:
		var center: Vector3 = crowd_centroid / float(crowd_count)
		var away: Vector3 = position - center
		if away.length_squared() > 1e-4:
			var clump_push: float = 0.22 + 0.06 * float(crowd_count - 3)
			desired += away.normalized() * effective_max * clampf(clump_push, 0.22, 0.42)

	# Mourning slowdown — apply to effective_max so the school visibly
	# drifts rather than sprints. Light (~30% top-speed cap at peak
	# intensity) so it reads as solemn, not broken.
	if mourning_w > 0.01:
		effective_max *= 1.0 - mourning_w * 0.30

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
		var dl: float = float(sim.daylight()) if sim.has_method("daylight") else 1.0
		# At deep night, diurnal fish rest and tolerate mildly lower O2 without
		# panic-darting. Keep emergency behavior for truly low values.
		var gulp_threshold: float = lerpf(0.22, SURFACE_GULP_O2, dl)
		if o2 < gulp_threshold:
			var severity: float = clampf((gulp_threshold - o2) / maxf(gulp_threshold, 0.001), 0.0, 1.0)
			var surface_y: float = _water_surface_y()
			target_y = lerpf(home_y, surface_y, severity * 0.65)
			var stress_gain: float = lerpf(0.55, 1.0, dl)
			stress = clampf(stress + dt * severity * 0.05 * stress_gain, 0.0, 1.0)
	# Zero-mean depth wobble — keeps layers alive without drifting up/down.
	target_y += sin(_swim_phase * 0.45 + float(get_instance_id() % 53) * 0.11) \
		* home_y_radius * 0.16
	var dy: float = target_y - position.y
	# Stronger Y pull beyond home_y_radius; gentle within it. Result: fish
	# actively defend their water column layer instead of all sinking to
	# the substrate at night. At night, tighten the band so fish rest in-layer.
	var effective_y_radius: float = home_y_radius
	if sim != null and float(sim.daylight()) < 0.25:
		effective_y_radius *= 0.62
	var dy_outside: float = maxf(0.0, absf(dy) - effective_y_radius)
	desired.y += signf(dy) * (effective_y_radius * 0.55 + dy_outside * 1.65)
	# Don't keep tugging toward the meniscus once the fish is already there —
	# that pins mid-water species sideways under the ceiling.
	if _aerial_timer <= 0.0 and sim != null and _meniscus_headroom() < 0.55:
		var o2_pull: float = float(sim.dissolved_o2) - _chem_o2_penalty \
			if sim.get("dissolved_o2") != null else 1.0
		if o2_pull >= SURFACE_GULP_O2 and desired.y > 0.0:
			desired.y = minf(desired.y, -effective_max * 0.22)

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
			to_hide.y *= 0.35
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
	var eff_home_r: float = home_radius * float(music_mods.get("home_radius", 1.0))
	if dist_home > eff_home_r:
		var pull_strength: float = clampf(
			(dist_home / maxf(eff_home_r, 0.5)) - 1.0, 0.0, 2.0)
		var pull_mult: float = 0.5 * float(music_mods.get("home_pull", 1.0))
		pull_mult *= maxf(0.04, 1.0 - float(music_mods.get("sweep", 0.0)) * 0.92)
		if swim_pattern == "hover":
			pull_mult = 0.15 # gentler pull to avoid centering oscillations / spinning
		# Don't tug fish through glass when a saved home sits outside the footprint.
		if to_home.length_squared() > 1e-6:
			var home_dir: Vector3 = to_home.normalized()
			var bnd: Dictionary = _boundary_context(global_position)
			var inward: Vector3 = bnd.get("inward", Vector3.ZERO)
			if inward.length_squared() > 1e-6 and home_dir.dot(inward) < -0.12:
				pull_strength *= 0.15
		desired += to_home.normalized() * effective_max * pull_mult * pull_strength

	# PLAYER GLANCE. Bold fish drift toward the spot the player is staring
	# at — the real-aquarium moment of fish noticing you've leaned into
	# the glass. Three gates keep this from being annoying:
	#   1. Personality.boldness must clear 0.55 (shy fish stay back)
	#   2. Sim must report a glance strength > 0.30 (player is genuinely
	#      close + holding still, not panning the camera past)
	#   3. Fish must not be in a high-stress mode — flee / spawn / etc.
	#      already short-circuit the tier above this one.
	# Habituation: each time the glance fires for a given fish, novelty
	# decays. After many sessions of being stared at, the fish reads the
	# player as background and stops swimming over. Real fish do this.
	# Throttle the EXPENSIVE sim.get_player_glance() call — the camera
	# doesn't move at 10 Hz so re-sampling that often is wasted Variant
	# ops + Dictionary reads. Refresh once per second, apply the cached
	# values every tick so steering pulls smoothly.
	_glance_check_t -= dt
	if _glance_check_t <= 0.0:
		_glance_check_t = GLANCE_CHECK_PERIOD
		if sim != null and sim.has_method("get_player_glance"):
			var glance: Dictionary = sim.get_player_glance()
			_cached_glance_strength = float(glance.get("strength", 0.0))
			_cached_glance_point = glance.get("point", Vector3.ZERO)
		else:
			_cached_glance_strength = 0.0
	if bool(fauna_rt.get("glance", true)) and _cached_glance_strength > 0.30:
		var b_personality: float = _trait("boldness")
		# RECOGNITION: a fish that trusts the player approaches even when it is
		# not naturally bold. Familiarity effectively lowers the boldness gate
		# and amplifies the pull, so a hand-fed fish learns to come greet you.
		var effective_bold: float = b_personality + familiarity * 0.4
		if effective_bold > 0.55:
			var novelty: float = float(habituated.get("player", 1.0))
			# Trust replaces novelty as the driver once the fish knows you:
			# habituation makes a stranger boring, but familiarity keeps a
			# friend interesting.
			var draw: float = maxf(novelty, familiarity)
			var pull: float = _cached_glance_strength * (effective_bold - 0.55) * 1.4 * draw
			var to_glass: Vector3 = _cached_glance_point - position
			if to_glass.length_squared() > 0.04:
				desired += to_glass.normalized() * effective_max * clampf(pull, 0.0, 0.6)
				_interest_target = _cached_glance_point
				_interest_remaining = 1.2
			# A brand-new strong glance is startling/interesting → reaction shot
			# the first beat, then settles into approach.
			if _reaction_remaining <= 0.0 and float(habituated.get("player", 1.0)) > 0.7:
				_reaction_remaining = 0.5
				_reaction_point = _cached_glance_point
			# Familiarity creeps up slowly while the player holds attention; bold
			# and curious fish bond faster. Capped so it takes real time.
			familiarity = clampf(familiarity + dt * (0.01 + b_personality * 0.02 \
				+ _trait("curiosity") * 0.01), 0.0, 1.0)
			if _recall("saw_player") == null:
				remember("saw_player", _cached_glance_point, 8.0)
	_interest_remaining = maxf(0.0, _interest_remaining - dt)

	# GAZE CONTAGION. When a neighbor of the same species is actively
	# investigating something, this fish picks up a small pull toward
	# the same point. Lower threshold than the originating fish (anyone
	# with boldness > 0.4 follows), so a single curious individual draws
	# a small entourage — the "uh-oh, whatever Atlas is looking at, I
	# should look too" reflex. Reuses the startle-propagation iteration
	# pattern from a few lines below.
	if _trait("boldness") > 0.4:
		var copied: Vector3 = Vector3.ZERO
		var copied_w: float = 0.0
		# Read from the pre-walked scan_fish / scan_d2 arrays — no more
		# per-loop is-Fish + self + distance² checks.
		for i in scan_n:
			if scan_same_species[i] == 0:
				continue
			var nf_g: Fish = scan_fish[i]
			if nf_g._interest_remaining <= 0.0:
				continue
			var d2: float = scan_d2[i]
			if d2 > 16.0:  # ~4 unit eyeshot for gaze contagion
				continue
			var w: float = (1.0 - sqrt(d2) / 4.0) * nf_g._interest_remaining
			copied += (nf_g._interest_target - position) * w
			copied_w += w
		if copied_w > 0.01:
			var pull_dir: Vector3 = (copied / copied_w)
			if pull_dir.length_squared() > 0.04:
				desired += pull_dir.normalized() * effective_max * 0.25 * clampf(copied_w, 0.0, 1.0)
				# CURIOSITY CONTAGION: a neighbor investigating something makes
				# this fish curious too, so one explorer draws a small crowd
				# that lingers even after the leader moves on.
				curiosity_drive = clampf(curiosity_drive + dt * 0.4 * _trait("curiosity"), 0.0, 1.0)
				if _interest_remaining <= 0.0:
					_interest_target = position + pull_dir.normalized() * 2.0
					_interest_remaining = 0.8

	# GAZE TARGETING. When a fast-moving neighbor passes through eyeshot
	# while WE are slow / resting, we turn to look. Sets _gaze_yaw which
	# the per-frame saccade reader uses in place of its random twitch —
	# so a swimming-by fish actually catches the eye of a resting one.
	# Cheap: only runs when our own speed is low and we have a free gaze
	# window. The brain only does the math once per tick.
	_gaze_remaining = maxf(0.0, _gaze_remaining - dt)
	if speed < 0.6 and _gaze_remaining <= 0.0:
		var fast_neighbor: Fish = null
		var best_speed: float = 1.2  # only neighbors faster than this qualify
		# Same pre-walked arrays — no per-loop type checks.
		for i in scan_n:
			var nf2: Fish = scan_fish[i]
			if nf2.speed < best_speed:
				continue
			if scan_d2[i] > 25.0:  # 5 unit eyeshot
				continue
			best_speed = nf2.speed
			fast_neighbor = nf2
		if fast_neighbor != null:
			# Compute the yaw angle from our facing to the neighbor — head
			# turns toward them by that small angle (clamped). This is local
			# yaw, so we project the relative position into our heading basis.
			var to_n: Vector3 = fast_neighbor.position - position
			var fwd: Vector3 = Vector3(-sin(_last_yaw), 0.0, -cos(_last_yaw))
			var right: Vector3 = Vector3(cos(_last_yaw), 0.0, -sin(_last_yaw))
			var local_x: float = to_n.dot(right)
			var local_z: float = to_n.dot(fwd)
			if absf(local_z) > 0.001:
				_gaze_yaw = clampf(atan2(local_x, local_z) * 0.35, -0.35, 0.35)
				_gaze_remaining = randf_range(1.2, 2.4)

	# GRUDGES. A specific neighbor with an active grudge reads as "the
	# bully" — we add a small repulsion vector away from them. Reads on
	# screen as the harassed fish hovering one body-length further from
	# the alpha than other tankmates, which is precisely what real
	# subordinate fish do.
	if not grudges.is_empty():
		var grudge_push: Vector3 = Vector3.ZERO
		# Same pre-walked arrays — type check + self + distance all cached.
		for i in scan_n:
			var nf_gr: Fish = scan_fish[i]
			if nf_gr.id == "" or not grudges.has(nf_gr.id):
				continue
			var d2: float = scan_d2[i]
			if d2 > 9.0:  # 3 unit personal-space radius for grudge bias
				continue
			var dirv: Vector3 = position - nf_gr.position
			if dirv.length_squared() > 1e-4:
				var w: float = 1.0 - sqrt(d2) / 3.0
				grudge_push += dirv.normalized() * w
		if grudge_push.length_squared() > 0.04:
			desired += grudge_push.normalized() * effective_max * 0.30

	# LEAN INTO CURRENT. Fish near the aeration / filter intake brace
	# slightly into the flow — the real-aquarium behavior of fish holding
	# position against the filter outflow. Cheap: just adds a small
	# heading-direction term when within range of the intake. Effect
	# scales with aeration_flow_rate so a barely-on filter doesn't make
	# everyone face the wall.
	if sim != null:
		var intake_pos_v: Variant = sim.get("filter_intake_pos")
		if intake_pos_v is Vector3 and (intake_pos_v as Vector3).length_squared() > 0.01:
			var intake_pos: Vector3 = intake_pos_v
			var to_intake: Vector3 = intake_pos - position
			var intake_d: float = to_intake.length()
			if intake_d < 3.5:
				var flow_strength: float = 0.0
				var afr_v: Variant = sim.get("aeration_flow_rate")
				if afr_v != null:
					flow_strength = clampf(float(afr_v) * 0.7, 0.0, 1.0)
				if flow_strength > 0.05:
					# Bias heading toward the intake (fish face into flow).
					# Magnitude tapers with distance so only fish actually
					# in the current respond.
					var falloff: float = 1.0 - intake_d / 3.5
					desired += to_intake.normalized() * effective_max * 0.18 * flow_strength * falloff

	# AI DIRECTOR INTENT DRIFT. When the LLM is running and has populated
	# its 4×4×4 mood grid, sample the cell our tank-relative position is
	# in and add the tiny drift vector. Magnitude ≤ 0.15 of effective_max
	# so existing steering remains primary.
	#
	# Throttle the sample to every ~2s — the LLM only refreshes the grid
	# every 30-60s anyway, so re-sampling at 10 Hz was 100× over-cost.
	# Cached drift gets applied every tick so steering still composes
	# smoothly.
	var ai_node: Node = _ai_director_cached
	_ai_drift_check_t -= dt
	if _ai_drift_check_t <= 0.0:
		_ai_drift_check_t = AI_DRIFT_CHECK_PERIOD
		_cached_ai_drift = Vector3.ZERO
		if ai_node != null and ai_node.has_method("get_intent_drift"):
			var w_node: Node = _world_node()
			if w_node != null:
				var hw_a: float = float(w_node.get("TANK_HALF_W") if w_node.get("TANK_HALF_W") != null else 8.0)
				var hd_a: float = float(w_node.get("TANK_HALF_D") if w_node.get("TANK_HALF_D") != null else 4.0)
				var hh_a: float = float(w_node.get("TANK_HEIGHT") if w_node.get("TANK_HEIGHT") != null else 7.0)
				var rel: Vector3 = Vector3(
					clampf((position.x + hw_a) / (hw_a * 2.0), 0.0, 0.999),
					clampf(position.y / hh_a, 0.0, 0.999),
					clampf((position.z + hd_a) / (hd_a * 2.0), 0.0, 0.999),
				)
				var cell: Dictionary = ai_node.get_intent_drift(rel)
				var d_drift: Vector3 = cell.get("drift", Vector3.ZERO)
				if d_drift.length_squared() > 1e-5:
					_cached_ai_drift = d_drift
				if id != "" and ai_node.has_method("get_fish_mood_drift"):
					var pf: Vector3 = ai_node.get_fish_mood_drift(id)
					if pf.length_squared() > 1e-5:
						_cached_ai_drift += pf
	if _cached_ai_drift.length_squared() > 1e-5:
		desired += _cached_ai_drift * effective_max

	# NOVELTY: pause-and-look when entering an unvisited tank region.
	# Curious fish (personality.curiosity > 0.5) trigger longer pauses on
	# novel cells. Habituation: every NOVELTY_RESET_S the bitmap clears
	# so well-explored tanks eventually feel fresh again. This makes
	# every fish read as having a small spatial map they're filling in.
	const NOVELTY_RESET_S: float = 1800.0  # 30 min of game time
	_novelty_reset_timer += dt
	if _novelty_reset_timer >= NOVELTY_RESET_S:
		_novelty_reset_timer = 0.0
		for vi in range(visited_regions.size()):
			visited_regions[vi] = 0
	_novelty_pause_remaining = maxf(0.0, _novelty_pause_remaining - dt)
	if visited_regions.size() > 0 and _novelty_pause_remaining <= 0.0 \
			and burst_remaining <= 0.0 and _startle_remaining <= 0.0:
		var w_nov: Node = _world_node()
		if w_nov != null:
			var hw_n: float = float(w_nov.get("TANK_HALF_W") if w_nov.get("TANK_HALF_W") != null else 8.0)
			var hd_n: float = float(w_nov.get("TANK_HALF_D") if w_nov.get("TANK_HALF_D") != null else 4.0)
			var hh_n: float = float(w_nov.get("TANK_HEIGHT") if w_nov.get("TANK_HEIGHT") != null else 7.0)
			var rxn: float = clampf((position.x + hw_n) / (hw_n * 2.0), 0.0, 0.999)
			var ryn: float = clampf(position.y / hh_n, 0.0, 0.999)
			var rzn: float = clampf((position.z + hd_n) / (hd_n * 2.0), 0.0, 0.999)
			var ixn: int = int(rxn * NOVELTY_GRID)
			var iyn: int = int(ryn * NOVELTY_GRID)
			var izn: int = int(rzn * NOVELTY_GRID)
			var idxn: int = ixn + iyn * NOVELTY_GRID + izn * NOVELTY_GRID * NOVELTY_GRID
			if visited_regions[idxn] == 0:
				visited_regions[idxn] = 1
				# Pause-and-look. Curious fish hold longer.
				var curiosity: float = _trait("curiosity")
				if curiosity > 0.35:
					_novelty_pause_remaining = lerpf(0.4, 1.4, curiosity)
	# When pausing, dampen speed so the fish visibly slows + looks around.
	# Other steering terms still apply at reduced strength so wall_avoid
	# can still nudge it out of trouble.
	if _novelty_pause_remaining > 0.0:
		desired *= 0.25

	# FEED ANTICIPATION. When the wall-clock minute matches the player's
	# historical feed times, hungry fish drift upward toward the surface
	# in advance — they "know" food is coming. Cheap: SimDriver checks
	# the time history once and caches the boolean; we just read it here.
	if hunger > 0.4 and sim != null and sim.has_method("feed_anticipation_active") \
			and sim.feed_anticipation_active():
		var headroom: float = _meniscus_headroom()
		if headroom > 0.12:
			var anticipation_bias: float = clampf(headroom * 0.25, -0.5, 1.2)
			desired.y += anticipation_bias * effective_max * 0.35
		# Begging at the glass: familiar fish that associate the player with
		# food crowd toward the last place they saw you and pace expectantly.
		if familiarity > 0.25 and _cached_glance_point.length_squared() > 0.01:
			var to_you: Vector3 = _cached_glance_point - position
			if to_you.length_squared() > 0.25:
				desired += to_you.normalized() * effective_max * 0.3 * familiarity
		mood = clampf(mood + dt * 0.05, -1.0, 1.0)

	# STRESS CONTAGION + STARTLE PROPAGATION. Every fish — not just
	# school/shoal species — picks up the panic of conspecifics in
	# neighborhood range. The signal weakens with distance so a panic
	# ring radiates outward through the population rather than firing
	# simultaneously. Closely-bonded species (school/shoal) copy the
	# heading exactly; looser groupings just dart away from the panic
	# source. Stress itself climbs slightly for every fish near a
	# panicking conspecific, so a single scare ripples through the tank.
	if _startle_remaining <= 0.0 and burst_remaining <= 0.0:
		var nearest_panic: Fish = null
		var nearest_panic_d2: float = 16.0  # 4u influence radius
		for n in neighbors:
			if not (n is Fish):
				continue
			var nf: Fish = n
			if nf == self or nf.species != species:
				continue
			if nf.burst_remaining > 0.2 and nf._startle_heading.length_squared() > 0.01:
				var d2: float = nf.position.distance_squared_to(position)
				if d2 < nearest_panic_d2:
					nearest_panic_d2 = d2
					nearest_panic = nf
		if nearest_panic != null:
			# Stress jumps a little for everyone in earshot, faster the closer
			# the panicking neighbor is. Visible as the school tightening
			# before the dart fires.
			var prox: float = 1.0 - sqrt(nearest_panic_d2) / 4.0
			# Habituation (#81): a fish that's grown familiar with the tank /
			# owner stays calmer in a panic — long-kept fish spook less.
			var calm_fam: float = 1.0 - clampf(float(familiarity), 0.0, 1.0) * 0.4
			stress = clampf(stress + prox * 0.18 * calm_fam, 0.0, 1.0)
			# Lingering fear + memory: a scare isn't forgotten the instant the
			# burst ends. The fish stays jumpy (spooked) and remembers it.
			spooked = clampf(spooked + prox * 0.6, 0.0, 1.0)
			if _recall("startled") == null:
				remember("startled", nearest_panic.position, 10.0)
			# Tight-schoolers copy the heading; loose-groupers flee away.
			var tight: bool = swim_pattern == "school" or swim_pattern == "shoal"
			var sh: Vector3
			if tight:
				sh = nearest_panic._startle_heading
			else:
				# Flee directly away from the panic origin.
				var away: Vector3 = position - nearest_panic.position
				sh = away if away.length_squared() > 1e-4 else Vector3.FORWARD
			sh.y *= 0.22
			if sh.length_squared() > 1e-6:
				_startle_heading = sh.normalized()
			else:
				_startle_heading = Vector3(sh.x, 0.0, sh.z).normalized()
			# Burst scales with proximity so the panic ring weakens as it
			# spreads — closer fish snap, distant fish twitch.
			_startle_remaining = lerpf(0.18, 0.45, prox)
			burst_remaining = lerpf(0.15, 0.40, prox)

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
		# Record startle heading so school-mates can copy it (mostly horizontal).
		_startle_heading = Vector3(dart_dir.x, dart_dir.y * 0.2, dart_dir.z).normalized()
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
			if w != null:
				if w.has_method("spawn_burst_ripple"):
					w.spawn_burst_ripple(position)
				if w.has_method("get_node") and w.get_node_or_null("AquariumVisuals") != null:
					w.get_node("AquariumVisuals").spawn_splash_crown(position)

	# Music-sync darts — any species can get an extra groove-driven burst.
	var music_dart: float = float(music_mods.get("dart_chance", 0.0))
	if music_dart > 0.0 and burst_remaining <= 0.0 and energy > 0.3 \
			and randf() < music_dart * dt:
		burst_remaining = randf_range(0.62, 1.05)
		var dart_target: Vector3 = _music_cross_tank_target(music_mods, 0.65)
		_nudge_home_toward_music_target(dart_target, 0.45)
		var dart_m: Vector3 = dart_target - position
		if dart_m.length_squared() < 0.08:
			var ang_m: float = randf() * TAU
			dart_m = Vector3(sin(ang_m), randf_range(-0.35, 0.45), cos(ang_m))
		if dart_m.length_squared() > 1e-6:
			dart_m = dart_m.normalized()
			heading_offset = dart_m * (2.0 + wander_strength * float(music_mods.get("wander", 1.0)))
			_startle_heading = dart_m
			_startle_remaining = 0.32

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
	# Hysteresis: don't interrupt a committed goal or sleep with a random pause
	# (that flip-flopping is what reads as mechanical). Pause rate is shaped by
	# temperament — curious fish stop to look around more, jumpy fish less.
	var pause_rate: float = dt * lerpf(0.06, 0.18, _trait("curiosity"))
	if float(music_mods.get("sweep", 0.0)) > 0.08:
		pause_rate = 0.0
	if burst_remaining <= 0.0 and _startle_remaining <= 0.0 and goal_timer <= 0.0 \
			and not _asleep and randf() < pause_rate and energy > 0.3:
		# 15% of max speed → enough motion to slide off a wall, slow enough to
		# read as "pausing to look around."
		target_velocity = _apply_target_from_desired(desired, effective_max * 0.15)
		# Pausing to look is the moment the fish notices things — let curiosity
		# discharge into a gaze so neighbors can pick it up.
		if curiosity_drive > 0.3:
			_interest_target = position + heading * 2.0
			_interest_remaining = 1.0
		return events
		
	# PLAYFUL DART (ZOOMIES). Even non-dart species occasionally get a burst of
	# energy if they are well-fed and healthy. Happy fish play more.
	var zoom_rate: float = dt * (0.05 + clampf(mood, 0.0, 1.0) * 0.06)
	if burst_remaining <= 0.0 and energy > 0.7 and hunger < 0.2 and randf() < zoom_rate:
		burst_remaining = randf_range(0.3, 0.6)
		var ang: float = randf() * TAU
		heading_offset = Vector3(sin(ang), randf_range(-0.4, 0.6), cos(ang)) * 1.5

	# IDLE FIDGETS. Small spontaneous gestures (a shimmy, a yawn-gape, a
	# substrate flash) that break the metronome of constant swimming. Only when
	# calm, slow, and not already busy. Cheap: just arms a timer the animation
	# layer reads; the actual motion is applied in _motion_substep.
	if _fidget_cooldown <= 0.0 and _fidget_remaining <= 0.0 and speed < 0.7 \
			and burst_remaining <= 0.0 and _startle_remaining <= 0.0 \
			and not _asleep and randf() < dt * 0.08:
		var r: float = randf()
		if r < 0.45:
			_fidget_kind = 1   # shimmy
			_fidget_remaining = 0.6
		elif r < 0.8:
			_fidget_kind = 2   # yawn-gape
			_fidget_remaining = 0.5
			_trigger_mouth_gape()
		elif position.y < (sim.substrate_top_y + 1.2 if sim != null else 2.0):
			_fidget_kind = 3   # substrate flash (only near the floor)
			_fidget_remaining = 0.5
			# Flashing against the substrate kicks up a little sediment puff —
			# living substrate that reacts to its inhabitants.
			var wf := _world_node()
			if wf != null and wf.has_method("spawn_substrate_dust"):
				wf.spawn_substrate_dust(global_position)
		else:
			_fidget_kind = 1
			_fidget_remaining = 0.5
		_fidget_cooldown = randf_range(5.0, 12.0)

	# PLANT BRUSH: a fish swimming with some pace through foliage deflects it.
	# Throttled to a probabilistic check so dense tanks stay cheap.
	if speed > 0.55 and sim != null and sim.has_method("query_plants_in_radius") \
			and randf() < dt * 0.6:
		var brush_dir: Vector3 = velocity
		if brush_dir.length_squared() > 1e-4:
			brush_dir = brush_dir.normalized()
			for bp in sim.query_plants_in_radius(position, 0.7):
				if is_instance_valid(bp) and bp.has_method("brush"):
					var bd: float = bp._world_pos.distance_to(position)
					bp.brush(brush_dir, (1.0 - bd / 0.7) * speed * 0.12)
					break

	# Wander refresh: periodically rotate heading_offset to a new random
	# direction. Interval is shorter for solo fish (every 4-8s) so they
	# explore actively, longer for tight schoolers (every 15-25s) where
	# the school boids already provide direction variety.
	_wander_refresh_timer -= dt
	if _wander_refresh_timer <= 0.0:
		var interval: float = 8.0 + randf() * 6.0  # schooler default
		if schooling_strength < 0.4:
			interval = 4.0 + randf() * 4.0  # solo fish: much more frequent
		elif swim_pattern == "shuffle":
			interval = 5.0 + randf() * 6.0  # loaches: frequent zig-zags
		interval /= maxf(float(music_mods.get("wander_refresh", 1.0)), 1.0)
		_wander_refresh_timer = interval
		var phase: float = _swim_phase + float(get_instance_id() % 97) * 0.09
		var y_wander: float = 0.15
		if _tank_is_dome() or _water_column_height() > 6.0:
			y_wander = 0.38
		y_wander += float(music_mods.get("vertical", 0.0)) * 0.55
		if swim_pattern == "shuffle":
			y_wander *= 0.55
		heading_offset = Vector3(
			sin(phase) * randf_range(0.35, 0.62),
			sin(phase * 1.37) * y_wander,
			cos(phase * 0.93) * randf_range(0.35, 0.62),
		) * float(music_mods.get("wander", 1.0)) * float(music_mods.get("wander_amp", 1.0))

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
		elif swim_pattern == "school" or swim_pattern == "shoal":
			drift_interval = 20.0 + randf() * 16.0
			drift_radius = 3.2 if swim_pattern == "school" else 4.0
		drift_radius *= float(fauna_rt.get("wander", 1.0))
		drift_radius *= float(music_mods.get("home_radius", 1.0))
		drift_radius += float(music_mods.get("sweep", 0.0)) * 2.8
		drift_interval /= maxf(float(music_mods.get("home_drift", 1.0)), 1.0)
		_home_drift_timer = drift_interval
		var w := _world_node()
		if w != null and w.has_method("clamp_xyz_in_tank"):
			var new_x: float = home_x + randf_range(-drift_radius, drift_radius)
			var new_z: float = home_z + randf_range(-drift_radius, drift_radius)
			var p: Vector3 = w.clamp_xyz_in_tank(
				Vector3(new_x, home_y, new_z), 0.4, _body_tank_margin() * 0.5)
			home_x = p.x
			home_z = p.z

	# Vertical territory drift — dome bowls and tall columns let fish roam, but
	# stay near each individual's preferred water column instead of random full-column hops.
	if _tank_is_dome() or _water_column_height() > 6.5:
		_home_y_drift_timer -= dt
		if _home_y_drift_timer <= 0.0:
			_home_y_drift_timer = 18.0 + randf() * 32.0
			var target_home_y: float
			var w_drift := _world_node()
			if w_drift != null and w_drift.has_method("preferred_y_at"):
				var bot_y: float = float(sim.substrate_top_y if sim != null else 0.0) + 0.45
				var col_h: float = maxf(_water_surface_y() - bot_y, 0.5)
				var pref_frac: float = clampf((preferred_y - bot_y) / col_h, 0.12, 0.88)
				pref_frac = clampf(pref_frac + randf_range(-0.14, 0.14), 0.08, 0.92)
				var floor_y: float = bot_y
				if w_drift.has_method("column_surface_y"):
					floor_y = w_drift.column_surface_y(home_x, home_z)
				target_home_y = w_drift.preferred_y_at(home_x, home_z, pref_frac, floor_y)
			else:
				var top_y: float = _water_surface_y() - 0.35
				var bot_y: float = float(sim.substrate_top_y if sim != null else 0.0) + 0.45
				var col_h: float = maxf(top_y - bot_y, 0.5)
				var pref_frac: float = clampf((preferred_y - bot_y) / col_h, 0.12, 0.88)
				target_home_y = bot_y + col_h * clampf(
					pref_frac + randf_range(-0.14, 0.14), 0.08, 0.92)
			home_y = lerpf(home_y, target_home_y, lerpf(0.18, 0.38, wander_strength))

	# Mild wander via personal heading offset, scaled by wander_strength so
	# meanderers wander more, hoverers wander less. During startle propagation,
	# force the heading to the shared school direction.
	if _startle_remaining > 0.0:
		desired += _startle_heading * effective_max * 0.8
	else:
		var wander_base: float = 0.5
		if float(music_mods.get("sweep", 0.0)) > 0.08:
			wander_base = lerpf(0.75, 1.25, float(music_mods.get("sweep", 0.0)))
		desired += heading_offset * wander_base * wander_strength \
			* float(fauna_rt.get("wander", 1.0)) * float(music_mods.get("wander", 1.0)) \
			* float(music_mods.get("wander_amp", 1.0))

	desired = _apply_music_groove_steering(music_mods, desired, effective_max)

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
		if float(music_mods.get("sweep", 0.0)) > 0.08:
			activity = 1.0
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
			var sleep_candidates: Array = sim.query_plants_in_radius(position, 4.0) \
				if sim != null and sim.has_method("query_plants_in_radius") else plants
			for p in sleep_candidates:
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

	# ---- COMMITTED GOALS + CURIOSITY + PATROL (the "it has a plan" layer) ----
	# A fish that re-evaluates from scratch every tick reads as twitchy. Here it
	# commits to a short-lived goal and steers toward it for several seconds.
	if goal_timer > 0.0 and goal_point.length_squared() > 0.0:
		var to_goal: Vector3 = goal_point - position
		if to_goal.length() < 0.7:
			goal_timer = 0.0   # arrived — free to pick a new goal next window
		elif to_goal.length_squared() > 1e-4:
			desired += to_goal.normalized() * effective_max * 0.5
	elif _goal_pick_cooldown <= 0.0 and burst_remaining <= 0.0 \
			and _startle_remaining <= 0.0 and not _asleep \
			and current_mode == Mode.CRUISE:
		_goal_pick_cooldown = randf_range(3.0, 7.0)
		# Curiosity discharge: if bored, go inspect a remembered spot or a
		# random unexplored point. Otherwise occasionally pick a wander goal.
		if curiosity_drive > 0.6 or randf() < 0.25:
			var picked: bool = false
			var fed: Variant = _recall("fed")
			if fed != null and hunger > 0.45:
				goal_point = (fed as Dictionary).get("pos", position)
				goal_kind = "revisit_food"
				picked = true
			if not picked:
				var w_g: Node = _world_node()
				if w_g != null and w_g.has_method("clamp_xyz_in_tank"):
					var ang_g: float = randf() * TAU
					var reach: float = lerpf(2.0, 5.5, _trait("curiosity"))
					var cand: Vector3 = position + Vector3(
						cos(ang_g) * reach,
						randf_range(-1.0, 1.2),
						sin(ang_g) * reach)
					goal_point = w_g.clamp_xyz_in_tank(cand, 0.5, _body_tank_margin())
					goal_kind = "explore"
					picked = true
			if picked:
				goal_timer = randf_range(2.5, 5.0)
				curiosity_drive = maxf(0.0, curiosity_drive - 0.5)
				_interest_target = goal_point
				_interest_remaining = 1.4   # let neighbors catch the curiosity

	# Patrol anchors: loosely loop between 1-2 learned favorite spots instead of
	# pure random drift. Built lazily from the current home once the fish has
	# settled. Gentle pull so it reads as "doing its rounds", not rail-riding.
	if patrol_anchors.is_empty() and is_finite(home_x) and is_finite(home_y) \
			and randf() < dt * 0.05 and maturity == MATURITY_ADULT:
		patrol_anchors.append(Vector3(home_x, home_y, home_z))
		var w_p: Node = _world_node()
		if w_p != null and w_p.has_method("clamp_xyz_in_tank"):
			var off: Vector3 = Vector3(randf_range(-3.0, 3.0), randf_range(-0.8, 0.8), randf_range(-3.0, 3.0))
			patrol_anchors.append(w_p.clamp_xyz_in_tank(
				Vector3(home_x, home_y, home_z) + off, 0.5, _body_tank_margin()))
	if patrol_anchors.size() >= 2 and goal_timer <= 0.0 and not _asleep:
		_patrol_retarget_t -= dt
		if _patrol_retarget_t <= 0.0:
			_patrol_retarget_t = randf_range(8.0, 16.0)
			_patrol_idx = (_patrol_idx + 1) % patrol_anchors.size()
		var anchor: Vector3 = patrol_anchors[_patrol_idx]
		var to_anchor: Vector3 = anchor - position
		if to_anchor.length() > 1.0 and to_anchor.length_squared() > 1e-4:
			desired += to_anchor.normalized() * effective_max * 0.18

	# Reaction shot: a brief freeze-and-orient when something surprising just
	# appeared. Strongly damps motion so the fish visibly "takes it in".
	if _reaction_remaining > 0.0:
		desired *= 0.2

	# Real sleep: park at a chosen nook, sensing + motion way down. Distinct
	# from the cosmetic night tilt — the fish actually settles.
	if _asleep:
		if not _sleep_have_nook:
			# Prefer the nearest plant/hardscape; fall back to current spot.
			_sleep_nook = position
			_sleep_have_nook = true
			var sd2n: float = 20.0
			var sc: Array = sim.query_plants_in_radius(position, 4.5) \
				if sim != null and sim.has_method("query_plants_in_radius") else plants
			for p in sc:
				if not is_instance_valid(p) or p.biomass() < 5:
					continue
				var d2n: float = p._world_pos.distance_squared_to(position)
				if d2n < sd2n:
					sd2n = d2n
					_sleep_nook = p._world_pos + Vector3(0.0, 0.35, 0.0)
		var to_nook: Vector3 = _sleep_nook - position
		if to_nook.length() > 0.5 and to_nook.length_squared() > 1e-4:
			desired = to_nook.normalized() * effective_max * 0.3
		else:
			desired *= 0.12
		current_mode = Mode.REST
	else:
		_sleep_have_nook = false

	target_velocity = _apply_target_from_desired(desired, effective_max)
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
		# Per-individual growth variance (#89): a faster-growing fish tops out
		# bigger; a runt tops out smaller — a natural size hierarchy within a
		# clutch instead of identical adults.
		var gv: float = _growth_variance
		if hunger < 0.35:
			growth_factor = minf(
				growth_factor + 0.0008 * dt * (0.75 + size_potential * 0.65) * gv,
				max_growth * gv)
		elif hunger > 0.7:
			growth_factor = maxf(
				growth_factor - 0.0004 * dt * (1.18 - size_potential * 0.35), 0.6 * gv)

	# Update body scale across maturity AND growth_factor.
	var scale_target: float = _maturity_scale() * growth_factor
	scale_target *= float(_music_mods().get("scale", 1.0))
	scale = scale.lerp(Vector3.ONE * scale_target, dt * 0.5)

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

	# Fry dart trail — only emit when this fish is actually a fry AND in
	# a burst. The fry-juvenile-play burst sets burst_remaining to 0.4s,
	# so a typical dart spawns 4-6 afterimages. Filtered by speed so
	# slow drifting in a wander phase doesn't spam.
	if maturity == MATURITY_FRY and burst_remaining > 0.0 and speed > max_speed * 0.45:
		_fry_trail_timer -= dt
		if _fry_trail_timer <= 0.0:
			_fry_trail_timer = 0.065
			_spawn_fry_trail_smear()

	# Bioluminescence sweep — only bioluminescent individuals push the
	# uniform, and we update once a second to keep the cost trivial.
	# The pulse animation runs in-shader (TIME based), so we just set
	# the strength scalar; no per-frame work needed beyond the gate.
	if is_bioluminescent:
		_biolum_t += dt
		if _biolum_t > 1.0:
			_biolum_t = 0.0
			var dl: float = 1.0
			if sim != null and sim.has_method("daylight"):
				dl = float(sim.daylight())
			# Strength ramps from 0 (dawn/dusk) to ~1 (midnight). Mute
			# entirely during the day so the fish reads normal then.
			var strength: float = smoothstep(0.32, 0.05, dl)
			if sim != null:
				var dp: float = fposmod(float(sim.day_phase), 1.0)
				strength *= 0.55 + 0.45 * sin(dp * TAU)
				if sim.has_method("_is_saltwater_tank") and sim._is_saltwater_tank():
					var bleach: float = 0.0
					if sim.get("tank_vitals") != null:
						bleach = float(sim.tank_vitals.get("reef_bleach_level", 0.0))
					strength *= (1.0 - bleach) \
						* clampf(float(sim.dissolved_o2) / 0.88, 0.35, 1.0)
			# Light panel master multiplier — 0 hides biolum entirely, >1 over-bright.
			var tc := get_node_or_null("/root/TankConfig")
			if tc != null:
				strength *= clampf(float(tc.biolum_multiplier), 0.0, 3.0)
			_apply_bioluminescence_uniform(strength)

	_update_pheromone_trail()
	if _belly_flash > 0.0:
		_belly_flash = maxf(0.0, _belly_flash - dt * 2.5)
		_apply_belly_flash_uniform(_belly_flash)
	if _mouth_gape > 0.0:
		_mouth_gape = maxf(0.0, _mouth_gape - dt * 5.5)
	_apply_stress_flush()
	_tick_substrate_compaction(dt)

	# Apply pregnancy bulge if gestating
	if _body_mid_pivot != null:
		if is_livebearer and sex == 1 and _gestation_progress > 0.0:
			var bulge := 1.0 + _gestation_progress * 0.35
			_body_mid_pivot.scale = Vector3(bulge * 0.8 + 0.2, bulge, 1.0)
		else:
			_body_mid_pivot.scale = Vector3.ONE
	# Mouthbrooding throat bulge — lazy-created when the female starts
	# incubating; scaled by progress so it visibly fills + recedes.
	_update_mouthbrood_bulge()

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
	var n_steps: int = clampi(int(ceil(dt / maxf(0.05 / clampf(speed / maxf(max_speed, 0.15), 0.55, 1.6), 0.028))), 1, 20)
	var sub_dt: float = dt / float(n_steps)
	for _step in n_steps:
		_motion_substep(sub_dt)

	# Posture overlays. Layered on top of the bank pivot's natural roll
	# from _motion_substep so the cleaning + sleep poses ride on top of
	# whatever motion lean the fish has earned in this frame.
	_apply_posture_overlays(dt)
	_tick_gill_flush(dt)


# Apply two ambient pose adjustments on top of the bank pivot's
# motion-driven roll: cleaning-station tilt (head-down + flank tilt
# while parked at a cleaner) and night-sleep posture (slow roll + tiny
# twitches for diurnal fish at deep night).
func _apply_posture_overlays(dt: float) -> void:
	if _bank_pivot == null:
		return
	# Cleaning tilt — the recipient presents flank to the cleaner.
	if _being_cleaned > 0.05:
		var target_roll: float = 0.42 * sign(sin(get_instance_id() * 0.01))
		_bank_pivot.rotation.z = lerpf(_bank_pivot.rotation.z, target_roll, dt * 3.0)
		_bank_pivot.rotation.x = lerpf(_bank_pivot.rotation.x, -0.18, dt * 3.0)
		return
	# Sleep posture — diurnal species at deep night drift gently with a
	# slight body tilt and occasional twitches.
	if sim != null and swim_pattern != "shuffle":
		var dl: float = float(sim.daylight())
		if dl < 0.18 and maturity != MATURITY_FRY:
			# Smooth toward a small per-fish roll; keep direction stable
			# by deriving from instance id so each sleeper picks a side.
			var side: float = -1.0 if (get_instance_id() % 2 == 0) else 1.0
			var sleep_roll: float = side * 0.22 * (1.0 - clampf(dl / 0.18, 0.0, 1.0))
			_sleep_tilt = lerpf(_sleep_tilt, sleep_roll, dt * 1.5)
			_bank_pivot.rotation.z = lerpf(_bank_pivot.rotation.z,
				_bank_pivot.rotation.z + _sleep_tilt * 0.4, dt * 2.0)
			# Occasional twitch — a small dart that the brain will absorb
			# on the next tick. Real sleeping fish twitch every few minutes.
			_sleep_twitch_t -= dt
			if _sleep_twitch_t <= 0.0:
				_sleep_twitch_t = randf_range(8.0, 25.0)
				if energy > 0.2 and burst_remaining <= 0.0:
					burst_remaining = 0.18
					heading_offset += Vector3(
						randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4))
		else:
			_sleep_tilt = lerpf(_sleep_tilt, 0.0, dt * 2.0)


# Pre-stress gill flush. Periodically rolls a chance to play a short
# "gill cough" animation: a brief outward pulse of the head pivot's
# scale, mimicking the gill flare a real fish does when water quality
# is borderline. Triggers ONLY when stress is climbing (0.30..0.55) and
# either O2 is mid-low or recent waste is high — so the player gets a
# visual early warning before the actual hide-in-plants threshold.
func _tick_gill_flush(dt: float) -> void:
	# Animate any in-flight flush — even if conditions no longer warrant.
	if _gill_flush_t > 0.0:
		_gill_flush_t = maxf(0.0, _gill_flush_t - dt)
		var pivot: Node3D = _gill_pivot if _gill_pivot != null else _head_pivot
		if pivot != null:
			# Phase 0..1 — out at 0..0.5, settle at 0.5..1. Use sin(πt) for
			# a smooth pulse.
			var p: float = 1.0 - _gill_flush_t / 0.5
			var pulse: float = sin(p * PI) * 0.18
			pivot.scale = Vector3(1.0 + pulse, 1.0 + pulse * 0.6, 1.0)
		return
	# Eligibility check at a slow cadence — never per-frame.
	_gill_flush_check -= dt
	if _gill_flush_check > 0.0:
		return
	_gill_flush_check = randf_range(2.5, 5.5)
	if sim == null or maturity == MATURITY_FRY:
		return
	# CONTENT BRANCH: when stress is very low and the fish is essentially
	# parked, fire a relaxed gill pulse occasionally. Reads as the fish
	# breathing visibly while at rest — the most universal "alive" tell.
	# Rate is gated so it doesn't fire during active swimming.
	if stress < 0.10 and speed < 0.5 and energy > 0.4:
		if randf() < 0.35:
			_gill_flush_t = 0.5
		return
	# Pre-stress window — once stress crosses the hide threshold the
	# flee/hide tiers take over and the cough would be lost in the panic.
	if stress < 0.30 or stress > 0.55:
		return
	# Water-quality cue: mildly low O2 OR rising waste density. Both are
	# proxies for "the water is starting to get unpleasant."
	var o2: float = float(sim.dissolved_o2) if sim.get("dissolved_o2") != null else 0.6
	var waste_load: float = float(sim.waste.size()) / 30.0 if sim.get("waste") != null else 0.0
	if o2 > 0.52 and waste_load < 0.4:
		return
	# Rare — about one cough per ~30s under bad water.
	if randf() < 0.5:
		_gill_flush_t = 0.5


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
	# Stamp wall-clock so the safety net in _animate_death can force-free
	# a fish that's been stuck in dying state for too long (e.g. if
	# _process is getting starved or dt is being suppressed somehow).
	_dying_wall_start_unix = int(Time.get_unix_time_from_system())
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
	# Wall-clock safety net — if the fish has been dying for more than
	# DEATH_WALL_CLOCK_MAX seconds of REAL time (independent of sim time
	# scale or dt starvation), force-complete the animation. Catches any
	# scenario where the visual loops because dt never accumulates.
	if _dying_wall_start_unix > 0:
		var elapsed: int = int(Time.get_unix_time_from_system()) - _dying_wall_start_unix
		if elapsed >= DEATH_WALL_CLOCK_MAX:
			_dying_timer = 0.0  # force exit branch below
	# Ensure progress is monotonic even when dt is suspiciously small.
	# This adds a tiny floor so a fish that's been dying for at least a
	# frame always loses a sliver of timer per call.
	var dt_use: float = maxf(dt, 0.001)
	_dying_timer = maxf(0.0, _dying_timer - dt_use)
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
	if sim != null:
		var w: Node = sim.get_parent()
		if w != null and w.has_method("clamp_xyz_in_tank"):
			global_position = w.clamp_xyz_in_tank(global_position, 0.24, _body_tank_margin())
	# At the end of the sequence, drop the mulm and remove the node.
	if _dying_timer <= 0.0:
		if sim != null and sim.has_method("_spawn_waste"):
			var kind: int = WasteParticle.KIND_FISH
			sim._spawn_waste(position, 0.4, kind)
		# Mycelium spawn — pale fungal threads grow on the decaying
		# corpse if the cleanup crew doesn't grab the waste fast enough.
		# About 55% of deaths produce a visible patch.
		if sim != null:
			var w_node: Node = sim.get_parent()
			if w_node != null and w_node.has_method("spawn_mycelium_patch"):
				var mc_pos := Vector3(position.x, sim.substrate_top_y + 0.04, position.z)
				w_node.spawn_mycelium_patch(mc_pos)
		queue_free()


# Single physics integration step. Pulled out of _process so we can call it
# multiple times per frame at high time_scale without the integration
# blowing up. Reads target_velocity (set by the brain at 10 Hz), writes
# heading + position + look_at + bank.
func _look_up_for_direction(d: Vector3) -> Vector3:
	if absf(d.normalized().dot(Vector3.UP)) > 0.95:
		return Vector3.FORWARD
	return Vector3.UP


func _face_direction(d: Vector3) -> void:
	if not d.is_finite() or d.length_squared() < 0.0001:
		return
	var dir := d.normalized()
	var up := _look_up_for_direction(dir)
	look_at(position + dir, up)
	if not transform.is_finite():
		transform.basis = Basis.looking_at(dir, up)


func _motion_substep(dt: float) -> void:
	var music_mm: Dictionary = _music_mods()
	var eff_accel: float = linear_accel * float(music_mm.get("accel", 1.0))
	var eff_turn: float = max_turn_rate * float(music_mm.get("turn", 1.0))
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
	# Rest debt (#84): a sleep-deprived fish moves sluggishly through the day.
	if _rest_debt > 0.05:
		target_spd *= 1.0 - clampf(_rest_debt, 0.0, 1.0) * 0.25
	# Enrichment vs boredom (#85): a barren tank is dull — fish drift listlessly;
	# a complex, well-planted tank keeps them lively and exploring.
	if sim != null:
		var enrich: float = clampf(float(sim.total_plant_biomass) / 300.0, 0.0, 1.0)
		target_spd *= lerpf(0.85, 1.0, enrich)

	var body_m: float = _body_tank_margin()
	var margin: float = 0.22
	var body_r: float = body_m * 0.55

	# Never steer toward the glass — strip outward velocity before turning.
	var constrained: Vector3 = _constrain_velocity_to_tank(target_dir * target_spd)
	if constrained.length_squared() > 1e-6:
		target_dir = constrained.normalized()
		target_spd = constrained.length()
	# Non-surface species resist slow upward creep above their home band.
	if _aerial_timer <= 0.0 and mouth_orientation > -1:
		var o2_ok: bool = sim == null or float(sim.dissolved_o2) >= SURFACE_GULP_O2
		if o2_ok and position.y > home_y + home_y_radius * 1.25 and target_dir.y > 0.12:
			var capped: Vector3 = Vector3(target_dir.x, target_dir.y * 0.3, target_dir.z)
			if capped.length_squared() > 1e-6:
				target_dir = capped.normalized()
				target_spd *= 0.92
	# Surface-pin release. Without this, fish that drift up to the meniscus
	# (e.g. mid-cruise wobble + lateral collision-slide along the ceiling)
	# get stuck swimming sideways at the surface because movement follows
	# heading, which turns slowly, while upward cruise bias keeps fighting
	# the ceiling. Snap heading + target_dir downward so the fish actually
	# leaves the meniscus this tick.
	if _surface_pin_release_active():
		target_dir = _heading_away_from_meniscus(target_dir)
		target_spd = maxf(target_spd, max_speed * 0.55)
		heading = target_dir

	# ---- Rotate heading toward target_dir, bounded by max_turn_rate ----
	var bnd: Dictionary = _lateral_boundary_context(global_position, body_m, target_dir)
	var clearance: float = float(bnd.get("clearance", 99.0))
	var repel_dist: float = body_m * 2.4 + 0.45
	var wall_t: float = 1.0 - clampf(clearance / repel_dist, 0.0, 1.0)
	var angle: float = heading.angle_to(target_dir)
	if angle > 0.0005:
		var axis: Vector3 = heading.cross(target_dir)
		if axis.length_squared() < 1e-6:
			axis = Vector3.UP
		axis = axis.normalized()
		var turn_boost: float = lerpf(1.0, 1.14, wall_t * wall_t)
		var max_step: float = eff_turn * turn_boost * dt
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
	# Limit pitch for mid-water cruisers — real fish rarely climb/dive steeply.
	# Music sync loosens this so groove-driven swoops read vertically.
	if _sift_timer <= 0.0 and mouth_orientation != 1 and swim_pattern != "dart":
		var flat: Vector3 = Vector3(heading.x, 0.0, heading.z)
		if flat.length_squared() > 0.04:
			var max_pitch: float = 0.40 if mouth_orientation == 0 else 0.52
			var vert_lift: float = float(music_mm.get("vertical", 0.0))
			if vert_lift > 0.12:
				max_pitch = lerpf(max_pitch, 0.78, vert_lift)
			if absf(heading.y) > max_pitch:
				heading = Vector3(flat.x, signf(heading.y) * max_pitch, flat.z).normalized()

	# ---- Accelerate speed toward target_spd, bounded by linear_accel ----
	speed = move_toward(speed, target_spd, eff_accel * dt)
	if wall_t > 0.35:
		speed = minf(speed, target_spd * lerpf(1.0, 0.68, wall_t))

	# ---- Move only as far as the tank allows (never swim into glass) ----
	var gp: Vector3 = global_position
	var move_dir: Vector3 = heading
	if move_dir.length_squared() < 1e-6:
		move_dir = target_dir
	# Belt-and-suspenders: if still pinned at the meniscus, don't let a
	# horizontal heading keep skidding along the ceiling.
	if _surface_pin_release_active() and move_dir.y > -0.15:
		move_dir = _heading_away_from_meniscus(move_dir)
		heading = move_dir
		speed = maxf(speed, max_speed * 0.45)
	if move_dir.length_squared() > 1e-6:
		move_dir = move_dir.normalized()
		var want_len: float = speed * dt
		var allowed: float = _max_inside_travel(gp, move_dir, want_len, margin, body_r)
		if allowed < want_len * 0.92:
			var inward: Vector3 = bnd.get("inward", Vector3.ZERO)
			inward.y = 0.0
			# Lateral escape only handled above; also catch the ceiling so fish
			# don't get pinned motionless when pressing against the water surface.
			if inward.length_squared() < 1e-6:
				var vb: Dictionary = _vertical_boundary_context(global_position)
				if bool(vb.get("active", false)) and float(vb.get("clearance", 99.0)) < 0.35:
					inward = vb.get("inward", Vector3.ZERO)
			if inward.length_squared() > 1e-6:
				inward = inward.normalized()
			if inward.length_squared() > 1e-6:
				var outward: Vector3 = -inward
				var out_comp: float = move_dir.dot(outward)
				if out_comp > 0.05:
					var bounced: Vector3 = _reflect_heading_at_wall(move_dir, inward)
					move_dir = heading.lerp(bounced, 0.62).normalized()
					allowed = _max_inside_travel(gp, move_dir, want_len, margin, body_r)
		global_position = gp + move_dir * allowed
		speed = allowed / maxf(dt, 1e-5)
		heading = move_dir
	velocity = move_dir * speed if move_dir.length_squared() > 1e-6 else Vector3.ZERO
	if velocity.y > 0.12:
		_belly_flash = 1.0

	# ---- Face the heading. look_at points local -Z at the target. Body is
	# built so its forward = -Z, so the fish faces its motion correctly.
	# We only re-orient when the fish has meaningful forward speed; when
	# nearly stopped the brain may flip target_velocity direction frame-to-
	# frame and look_at would snap the fish around (read as "spinning"). ----
	#
	# Belt-and-suspenders: guard position + basis here. A non-finite position
	# produces a non-finite look_at target even with a valid heading, and
	# look_at with a NaN target silently corrupts the Transform3D basis,
	# which then propagates to every child MultiMeshInstance3D and floods the
	# console with "instance_set_transform: !v.is_finite()" errors. Checking
	# only global_position misses a corrupted basis that still has a finite
	# origin — children keep spamming until the basis is rebuilt.
	if not global_position.is_finite() or not transform.is_finite():
		push_warning("[Fish] non-finite motion transform detected; recovering from last yaw.")
		if not global_position.is_finite():
			var _safe_y: float = clampf(home_y, 0.5, 8.0) if is_finite(home_y) else 2.5
			global_position = Vector3(0.0, _safe_y, 0.0)
		heading = Vector3(sin(_last_yaw), 0.0, -cos(_last_yaw))
		var recover_d: Vector3 = heading
		if recover_d.is_finite():
			var up := _look_up_for_direction(recover_d)
			transform.basis = Basis.looking_at(recover_d.normalized(), up)
	if speed > 0.04 and heading.length_squared() > 0.0001:
		_face_direction(heading)

	var do_body_anim: bool = sim == null or not sim.has_method("is_creature_visible_to_camera") \
		or sim.is_creature_visible_to_camera(self)

	# ---- Banking into yaw turns ----
	# Compute the world-space yaw of the heading on the XZ plane. The change
	# in yaw between frames is the yaw rate; bank angle is proportional to it.
	var current_yaw: float = atan2(heading.x, -heading.z)
	if do_body_anim:
		var yaw_diff: float = wrapf(current_yaw - _last_yaw, -PI, PI)
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
			elif hunger > 0.5 and velocity.y < -0.12 and current_mode == Mode.FORAGE:
				pitch_target = 0.34   # head-down: diving to forage at the bottom
			elif current_mode == Mode.FORAGE and velocity.y > 0.12:
				pitch_target = -0.18   # head-up: rising to surface-feed
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
	_last_yaw = current_yaw

	if not do_body_anim:
		return

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

	# Mood modulation. Stressed fish visibly beat their tails faster,
	# calm-personality fish beat slower. The effect is subtle (±20%) but
	# stacks across a school — a stressed school reads as restless even
	# when stationary, a calm one as drowsy. Personality.calm is the
	# trait scalar from the AIDirector pass; defaults to 0.5 when absent.
	var mood_freq_mult: float = 1.0 + stress * 0.35
	if not personality.is_empty():
		mood_freq_mult -= float(personality.get("calm", 0.5)) * 0.20 - 0.10
	# Lingering fear quickens the beat; contentment slows it to a lazy drift.
	mood_freq_mult += spooked * 0.4 - clampf(mood, 0.0, 1.0) * 0.15
	wag_freq *= clampf(mood_freq_mult, 0.55, 1.7)

	_swim_phase += dt * wag_freq * _wag_freq_jitter
	if (swim_pattern == "school" or swim_pattern == "shoal") \
			and schooling_strength >= 0.45 and sim != null \
			and sim.has_method("school_pulse_phase"):
		var shared: float = float(sim.school_pulse_phase()) + _school_phase_offset
		var delta: float = wrapf(shared - _swim_phase, -PI, PI)
		_swim_phase += delta * clampf(dt * 5.5, 0.0, 1.0)
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
			# Gaze target — when a fast neighbor just passed, prefer turning
			# toward them. Otherwise random micro-twitch as before. The
			# gaze yaw is set in tick() and decays via _gaze_remaining.
			if _gaze_remaining > 0.0 and absf(_gaze_yaw) > 0.02:
				_saccade_target = _gaze_yaw
			else:
				_saccade_target = randf_range(-0.22, 0.22)
		# Decay the saccade target back toward 0 so the twitch is a brief
		# pulse, not a sustained head-cock.
		_saccade_target = lerpf(_saccade_target, 0.0, clampf(dt * 1.8, 0.0, 1.0))
		# Eye gaze hold: between saccades the gaze settles toward whatever the
		# fish is attending to (a passing neighbor / the watching player), so the
		# head reads as "looking at something" rather than dead-ahead. Smoothed
		# and subtle; the saccade above is the quick flick layered on top.
		var gaze_hold: float = clampf(_gaze_yaw, -0.3, 0.3) if _gaze_remaining > 0.0 else 0.0
		_eye_look = lerpf(_eye_look, gaze_hold * rest_factor, clampf(dt * 2.0, 0.0, 1.0))
		_head_pivot.rotation.y = lerpf(_head_pivot.rotation.y,
			head_target + (_saccade_target + _eye_look * 0.5) * rest_factor,
			clampf(dt * 12.0, 0.0, 1.0))
		# Gill flare at rest. When the fish is barely moving (drifting,
		# sifting, sleeping), the eye reads a subtle head-width pulse as
		# gill-cover breathing — a real fish at rest does this constantly
		# and a still aquarium fish that DOESN'T do it reads as "frozen".
		# Active swimming hides the pulse anyway (wag dominates the visual).
		# Breathing you can see: gill-cover pulse rate + depth scale with
		# exertion and low oxygen. A fish that just sprinted, or one in a
		# starved-for-air tank, visibly pants; a resting fish in good water
		# breathes slow and shallow.
		var o2_now2: float = float(sim.dissolved_o2) if sim != null and sim.get("dissolved_o2") != null else 1.0
		var breath_load: float = clampf(0.4 + speed * 0.5 + (0.7 - o2_now2) * 1.2 + stress * 0.4, 0.4, 2.2)
		_breath_load = lerpf(_breath_load, breath_load, clampf(dt * 3.0, 0.0, 1.0))
		var breath_amp: float = (0.035 + clampf(_breath_load - 1.0, 0.0, 1.2) * 0.05) * maxf(rest_factor, 0.25)
		var breath: float = 1.0 + sin(_swim_phase * 0.9 * _breath_load) * breath_amp
		# Blink: a brief vertical squash of the head reads as an eye-blink at
		# voxel resolution (no separate eyelid geometry needed).
		var blink_sq: float = 1.0 - (0.18 if _blink_remaining > 0.0 else 0.0)
		var gape_z: float = 1.0 + _mouth_gape * 0.28
		_head_pivot.scale = Vector3(breath, blink_sq, gape_z)
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
	# FIN BODY LANGUAGE. Confidence and contentment flare the fins wider;
	# fear and sickness clamp them tight against the body. Continuous so the
	# fish's mood is legible at a glance even when it's holding still.
	var fin_mood: float = clampf(mood, -1.0, 1.0) * 0.18 - spooked * 0.4 - clampf((stress - 0.55) / 0.45, 0.0, 1.0) * 0.3
	pec_amp = maxf(pec_amp + fin_mood, 0.06)
	# A small static spread offset: relaxed fish hold pecs slightly out; clamped
	# fish tuck them in. Applied as a bias on top of the rowing oscillation.
	var pec_spread: float = clampf(0.12 + clampf(mood, 0.0, 1.0) * 0.12 - spooked * 0.18, -0.1, 0.28)
	if _pec_right_pivot != null:
		_pec_right_pivot.rotation.z = sin(_swim_phase * pec_freq / wag_freq) * pec_amp + pec_spread
	if _pec_left_pivot != null:
		_pec_left_pivot.rotation.z = -sin(_swim_phase * pec_freq / wag_freq + PI * 0.5) * pec_amp - pec_spread

	# ---- Idle fidgets: shimmy / substrate-flash micro-gestures ----
	# Applied as transient roll/wiggle on the bank pivot, layered over banking.
	if _fidget_remaining > 0.0 and _bank_pivot != null:
		var fphase: float = _fidget_remaining * 18.0
		if _fidget_kind == 1:      # shimmy: quick low-amplitude body shiver
			_bank_pivot.rotation.z += sin(fphase) * 0.12
		elif _fidget_kind == 3:    # substrate flash: a fast half-roll
			_bank_pivot.rotation.z += sin(fphase * 0.7) * 0.5

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
	# Courtship flare (males build to a vivid flash at spawn) + stress pallor
	# (any fish drains color toward pale grey when badly stressed). Both write the
	# same per-voxel albedo, so they share one writer to avoid fighting over it.
	var flare: float = 0.0
	if _courtship_flare and sex == 0 and _courtship_intensity > 0.05:
		flare = 0.45 if _courtship_sync else _courtship_intensity * 0.30
	# CONTENTMENT SHIMMER + MOOD COLOR. A safe, fed, social fish glows a touch
	# more vivid (positive emotional readout — the game previously only showed
	# negative states). A sudden water-quality improvement adds a brief relief
	# brightening. These ride the same albedo channel as courtship flare.
	flare += clampf(mood, 0.0, 1.0) * 0.16 + _relief_pulse * 0.18
	var pallor: float = clampf((stress - 0.55) / 0.45, 0.0, 1.0) * 0.5
	# Fear + sadness drain color: a frightened or miserable fish goes pale.
	pallor = clampf(pallor + spooked * 0.35 + clampf(-mood, 0.0, 1.0) * 0.25, 0.0, 0.85)
	if flare > 0.001 or pallor > 0.001:
		if not _courtship_color_active:
			_courtship_color_active = true
			_last_courtship_color_step = -999
		var step: int = int(round(flare * 50.0)) * 1000 + int(round(pallor * 50.0))
		if step != _last_courtship_color_step:
			_last_courtship_color_step = step
			for child in _cached_meshes:
				if child is VoxelBatch.Handle:
					var h: VoxelBatch.Handle = child
					var c: Color = FaunaVoxelBuilder.handle_orig_color(h)
					if flare > 0.0:
						c = c.lightened(flare * 0.3)
						c.s = minf(1.0, c.s + flare)
					if pallor > 0.0:
						c.s = maxf(0.0, c.s * (1.0 - pallor))
						c = c.lerp(Color(0.72, 0.74, 0.78), pallor * 0.5)
					h.set_color(c)
	elif _courtship_color_active:
		_courtship_color_active = false
		_last_courtship_color_step = -999
		for child in _cached_meshes:
			if child is VoxelBatch.Handle:
				var h2: VoxelBatch.Handle = child
				h2.set_color(FaunaVoxelBuilder.handle_orig_color(h2))


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

func _boids(neighbors: Array, tightness: float = 1.0, separation_mult: float = 1.0) -> Vector3:
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
	var effective_sep_radius: float = separation_radius * separation_mult / tightness
	var sep_r2: float = effective_sep_radius * effective_sep_radius
	# Leader tracking: weight cohesion toward the highest-lead-score neighbor
	# so a school visibly follows a leader rather than a faceless centroid.
	var best_lead: float = lead_score
	var leader_pos: Vector3 = Vector3.ZERO
	var have_leader: bool = false
	var friend_pull: Vector3 = Vector3.ZERO
	var friend_w: float = 0.0

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
			var sep_push: Vector3 = diff
			if mouth_orientation == 0:
				sep_push.y *= 0.38
			elif mouth_orientation == 1:
				sep_push.y *= 0.55
			# PECKING ORDER: a subordinate yields extra space to a dominant
			# conspecific (and to a fish it bears a grudge against), so the
			# social hierarchy is visible as deferential spacing.
			var defer: float = 1.0
			if f.species == species and f.rank_within_species > rank_within_species + 0.12:
				defer = 1.6
			if not grudges.is_empty() and f.id != "" and grudges.has(f.id):
				defer = maxf(defer, 1.8)
			sep += sep_push.normalized() / maxf(sqrt(d2), 0.1) * defer
		# Alignment + cohesion are conspecific-only and view-cone-gated.
		if f.species != species:
			continue
		# Track the most "leaderly" conspecific in view.
		if f.lead_score > best_lead and d2 < 16.0:
			best_lead = f.lead_score
			leader_pos = f.position + f.velocity * 0.4
			have_leader = true
		# FRIENDSHIP: a fish keeps closer company with a bonded friend (a past
		# mate or frequent companion), so named residents pair off visibly.
		if not bonds.is_empty() and f.id != "":
			var aff: float = float(bonds.get(f.id, 0.0))
			if aff > 0.1 and d2 > 0.36:
				friend_pull += (f.position - position).normalized() * aff
				friend_w += aff
		if absf(diff.y) > maxf(home_y_radius, f.home_y_radius) * 2.4:
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
		# Vertical de-stack: nudge away from conspecifics on the same plane.
		if absf(diff.y) < maxf(home_y_radius, 0.35) * 0.85:
			sep.y += signf(-diff.y) * 0.28

	var steer := sep * 2.85

	if count_conspecific > 0:
		ali /= float(count_conspecific)
		coh /= float(count_conspecific)
		var school_avg_speed: float = school_speed_sum / float(count_conspecific)
		var ali_strength: float = 1.15
		# Dense local groups soften cohesion so the school reads as a loose
		# cloud instead of a single tight ball.
		var density_factor: float = 1.0
		if count_conspecific >= 6:
			density_factor = 0.42
		elif count_conspecific >= 4:
			density_factor = 0.62
		elif count_conspecific >= 3:
			density_factor = 0.80
		var coh_strength: float = 0.82 * tightness * density_factor
		# Alignment: steer toward avg heading.
		if ali.length() > 0.001:
			steer += ali.normalized() * ali_strength
		# Cohesion: steer toward predicted center of mass + a stable personal
		# slot so conspecifics fan out around the group instead of stacking.
		var slot_angle: float = float(get_instance_id() % 360) * 0.174532925
		var slot_r: float = clampf(separation_radius * 2.35 / maxf(tightness, 0.7), 0.7, 2.0)
		var formation_slot: Vector3 = Vector3(
			cos(slot_angle) * slot_r,
			sin(float(get_instance_id() % 127) * 0.11) * slot_r * 0.35,
			sin(slot_angle) * slot_r
		)
		var to_center: Vector3 = coh + formation_slot - position
		to_center.y *= 0.52
		if to_center.length() > 0.001:
			steer += to_center.normalized() * coh_strength
		# Leader following: a follower biases toward the leader's predicted
		# position. The more clearly someone out-leads us, the stronger the pull.
		if have_leader:
			var to_leader: Vector3 = leader_pos - position
			to_leader.y *= 0.5
			if to_leader.length() > 0.6 and to_leader.length_squared() > 1e-4:
				steer += to_leader.normalized() * (best_lead - lead_score) * 0.9
		# Speed matching: nudge in heading direction proportional to school
		# speed delta. If the school is faster than us, accelerate.
		var speed_delta: float = school_avg_speed - speed
		steer += heading * clampf(speed_delta * 0.3, -0.4, 0.4)

	# Friendship cohesion (applies even outside a formal school count).
	if friend_w > 0.01:
		steer += (friend_pull / friend_w).normalized() * clampf(friend_w, 0.0, 1.0) * 0.5

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
		if child is VoxelBatch.Handle:
			var h: VoxelBatch.Handle = child
			var orig_color: Color = FaunaVoxelBuilder.handle_orig_color(h)
			h.set_color(orig_color.lerp(Color8(120, 110, 100), 0.45))


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
	var desat: float = 0.32 * (1.0 - _color_maturity)
	var wash: Color = Color(0.75, 0.75, 0.78)
	for child in _cached_meshes:
		if child is VoxelBatch.Handle:
			var h: VoxelBatch.Handle = child
			var orig_color: Color = FaunaVoxelBuilder.handle_orig_color(h)
			h.set_color(orig_color.lerp(wash, desat))


func _restore_original_colors() -> void:
	for child in _cached_meshes:
		if child is VoxelBatch.Handle:
			var h: VoxelBatch.Handle = child
			h.set_color(FaunaVoxelBuilder.handle_orig_color(h))

func _all_meshes(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is MeshInstance3D:
			out.append(c)
		out.append_array(_all_meshes(c))
	return out


func _world_node() -> Node:
	if sim == null:
		return null
	return sim.get_parent()


func _fauna_runtime() -> Dictionary:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return {
			"schooling": 1.0,
			"separation": 1.0,
			"wander": 1.0,
			"speed": 1.0,
			"pulse_on": true,
			"pulse_amp": 0.15,
			"mourning": true,
			"glance": true,
		}
	return {
		"schooling": float(cfg.fauna_schooling_mult),
		"separation": float(cfg.fauna_separation_mult),
		"wander": float(cfg.fauna_wander_mult),
		"speed": float(cfg.fauna_speed_mult),
		"pulse_on": bool(cfg.fauna_school_pulse_enabled),
		"pulse_amp": float(cfg.fauna_school_pulse_amplitude),
		"mourning": bool(cfg.fauna_mourning_enabled),
		"glance": bool(cfg.fauna_player_glance_enabled),
	}


func _tank_home_spread_xz() -> float:
	# Horizontal jitter for per-fish home anchors — scales with tank width so
	# large footprints seed patrol zones across the whole volume.
	var w := _world_node()
	if w == null:
		return 1.8
	var hw: float = float(w.get("TANK_HALF_W")) if w.get("TANK_HALF_W") != null else 4.0
	var hd: float = float(w.get("TANK_HALF_D")) if w.get("TANK_HALF_D") != null else 4.0
	return clampf(maxf(hw, hd) * 0.22, 1.8, 5.0)


func _tank_is_dome() -> bool:
	var w := _world_node()
	return w != null and String(w.get("TANK_SHAPE")) == "sphere"


func _water_surface_y() -> float:
	var w := _world_node()
	if w != null and w.get("WATER_HEIGHT") != null:
		return float(w.WATER_HEIGHT)
	if sim != null and sim.get("substrate_top_y") != null:
		return float(sim.substrate_top_y) + 5.0
	return home_y + 4.0


func _water_column_height() -> float:
	var w := _world_node()
	if w != null and w.get("WATER_HEIGHT") != null and w.get("SUBSTRATE_DEPTH") != null:
		return maxf(1.0, float(w.WATER_HEIGHT) - float(w.SUBSTRATE_DEPTH))
	if sim != null and sim.get("substrate_top_y") != null:
		return maxf(1.0, 5.0)
	return 5.0


func _wall_avoid(_b: AABB) -> Vector3:
	var push := Vector3.ZERO
	var hint: Vector3 = heading if heading.length_squared() > 1e-6 else target_velocity
	var lat: Dictionary = _lateral_boundary_context(global_position, -1.0, hint)
	var clearance: float = float(lat.get("clearance", 99.0))
	var inward: Vector3 = lat.get("inward", Vector3.ZERO)
	var body_m: float = float(lat.get("body_m", _body_tank_margin()))
	if inward.length_squared() > 1e-6:
		var repel_dist: float = body_m * 2.5 + 0.45
		if clearance < repel_dist:
			var t: float = 1.0 - clampf(clearance / repel_dist, 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			var steer_dir: Vector3 = heading
			if steer_dir.length_squared() < 1e-6 and target_velocity.length_squared() > 1e-6:
				steer_dir = target_velocity.normalized()
			var outward: Vector3 = -inward
			var into_wall: float = maxf(0.0, steer_dir.dot(outward))
			# Fish already cruising along the glass tangent — skip inward shove.
			if into_wall >= 0.12:
				var strength: float = t * (0.55 + into_wall * 0.65)
				push += inward * strength * maxf(max_speed, 0.45)
	var vert: Dictionary = _vertical_boundary_context(global_position)
	if bool(vert.get("active", false)):
		var v_clear: float = float(vert.get("clearance", 99.0))
		var v_in: Vector3 = vert.get("inward", Vector3.ZERO)
		if v_in.length_squared() > 1e-6 and v_clear < 0.42:
			var vt: float = 1.0 - clampf(v_clear / 0.42, 0.0, 1.0)
			push += v_in * vt * vt * maxf(max_speed * 0.55, 0.35)
	return push


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
		d.y *= 0.42 if mouth_orientation == 0 else 0.55
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


func _short_subspecies_tag(subspecies: String) -> String:
	if subspecies == "" or subspecies == species:
		return ""
	var parts: PackedStringArray = subspecies.split(".")
	var tail: String = parts[parts.size() - 1] if parts.size() > 0 else subspecies
	return tail.right(4)


func _founder_divergence_score(genome: Dictionary) -> int:
	var lib = get_tree().root.get_node_or_null("TankConfig")
	if lib == null or not lib.SPECIES_LIBRARY.has(species):
		return 0
	var template: Dictionary = lib.SPECIES_LIBRARY[species].get("genome", {})
	var score: int = 0
	if int(genome.get("tail_shape", 0)) != int(template.get("tail_shape", 0)):
		score += 1
	if (not not genome.get("has_barbels", false)) != (not not template.get("has_barbels", false)):
		score += 1
	if (not not genome.get("armor_plates", false)) != (not not template.get("armor_plates", false)):
		score += 1
	if (not not genome.get("snout_pointed", false)) != (not not template.get("snout_pointed", false)):
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
		1 if genome.get("has_barbels", false) else 0,
		1 if genome.get("armor_plates", false) else 0,
		q_e,
		q_d,
		str(q_eye),
		"h" if genome.get("snout_pointed", false) else "n",
		q_claw,
	]


func _derive_subspecies_id(mate: Fish, child_genome: Dictionary) -> String:
	var base: String = species
	var a: String = subspecies_id if subspecies_id != "" else species
	var b: String = mate.subspecies_id if mate.subspecies_id != "" else species
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


func _plant_graze_y(p: Plant) -> float:
	if p.has_method("graze_target_world_y"):
		return p.graze_target_world_y()
	return p.top_world_y()


func _find_nearest_plant(plants: Array, max_dist: float) -> Plant:
	var best: Plant = null
	var best_d2: float = max_dist * max_dist
	var candidates: Array = sim.query_plants_in_radius(position, max_dist) \
		if sim != null and sim.has_method("query_plants_in_radius") else plants
	for p in candidates:
		if not is_instance_valid(p) or p.biomass() <= 0:
			continue
		var top_pos: Vector3 = (p as Plant).global_position
		top_pos.y = _plant_graze_y(p as Plant)
		var d2: float = top_pos.distance_squared_to(position)
		if d2 < best_d2:
			best_d2 = d2
			best = p
	return best


func _find_nearest_floater(world: Node, max_dist: float) -> FloatingPlant:
	var best: FloatingPlant = null
	var best_d2: float = max_dist * max_dist
	if world == null or not world.has_method("query_floaters_in_radius"):
		return null
	for fp in world.query_floaters_in_radius(position, max_dist):
		if not is_instance_valid(fp) or not (fp is FloatingPlant):
			continue
		var floater: FloatingPlant = fp
		if floater.turion_buried or floater.biomass() < 0.15:
			continue
		if floater.graze_palatability() < 0.2 and randf() > 0.2:
			continue
		var top_pos: Vector3 = floater.global_position
		top_pos.y = _water_surface_y() - 0.06
		var d2: float = top_pos.distance_squared_to(position)
		if d2 < best_d2:
			best_d2 = d2
			best = floater
	return best


func _find_nearest_tall_plant(plants: Array, max_dist: float, min_biomass: int) -> Plant:
	# Fish only nibble plants that are at least min_biomass voxels tall.
	# Spares saplings + carpets. Prefer open canopy flowers when hungry.
	var best: Plant = null
	var best_d2: float = max_dist * max_dist
	var candidates: Array = sim.query_plants_in_radius(position, max_dist) \
		if sim != null and sim.has_method("query_plants_in_radius") else plants
	for p in candidates:
		if not is_instance_valid(p) or p.biomass() < min_biomass:
			continue
		if p.has_method("graze_palatability"):
			if float(p.graze_palatability()) < 0.22 and randf() > 0.15:
				continue
		var top_pos: Vector3 = (p as Plant).global_position
		top_pos.y = _plant_graze_y(p as Plant)
		var d2: float = top_pos.distance_squared_to(position)
		if p.has_method("has_grazeable_flower") and p.has_grazeable_flower():
			d2 *= 0.35
		if d2 < best_d2:
			best_d2 = d2
			best = p
	return best


# Used by SimDriver when this fish breeds with a partner.
@warning_ignore("shadowed_variable")
# Paints one lateral pattern motif onto the body, reshaped by the continuous
# pattern modulators so each lineage reads uniquely. Called once for the primary
# pattern_type and again (faintly) for an optional secondary motif so two motifs
# can co-exist. `strength` (1.0 primary, <1 secondary) scales prominence;
# `seg_count` is the number of body mid-segments.
func _paint_scale_rows(body: Node3D, v: float, seg_count: int, _mat_scale) -> void:
	if seg_count <= 0 or pattern_density < 0.18:
		return
	var interval: int = clampi(int(round(3.0 - pattern_density * 2.0)), 1, 3)
	var scale_col: Color = marking_color if _marking_color_set else accent_color
	var row_mat := _make_mat(scale_col.darkened(0.06))
	for i in seg_count:
		if i % interval != 0:
			continue
		for xs in [-1.0, 1.0]:
			_add_voxel_to(body, Vector3(xs * v * 0.52, v * 0.06, i * v),
				Vector3(v * 0.07, v * 0.10, v * 0.72), row_mat)


func _paint_lateral_pattern(ptype: int, body: Node3D, v: float, seg_count: int,
		mat_a, mat_m, strength: float) -> void:
	if ptype <= 0 or seg_count <= 0:
		return
	var sizem: float = 0.6 + pattern_scale * 0.8
	var thickm: float = (0.58 + pattern_intensity * 0.84) * strength
	var seg: int = clampi(int(ceil(float(seg_count) * pattern_coverage)), 1, seg_count)
	var dens: float = pattern_density
	var mat_edge = _make_mat(base_color.darkened(0.35 + pattern_contrast * 0.45))
	match ptype:
		1:
			# Horizontal stripe; a dense genotype adds a second lower line.
			for i in seg:
				for xs in [-1.0, 1.0]:
					_add_voxel_to(body, Vector3(xs * v * 0.5, 0, i * v),
						Vector3(v * 0.15 * sizem, v * 0.35 * thickm, v * 0.9 * sizem), mat_a)
			if dens > 0.62:
				for i in seg:
					for xs in [-1.0, 1.0]:
						_add_voxel_to(body, Vector3(xs * v * 0.5, -v * 0.32, i * v),
							Vector3(v * 0.12 * sizem, v * 0.22 * thickm, v * 0.85 * sizem), mat_a)
		2:
			# Spots: rows scale with density.
			var rows: int = clampi(1 + int(round(maxf(0.0, dens - 0.34) * 3.0)), 1, 3)
			for i in seg:
				for r in rows:
					var dy: float = (0.0 if rows <= 1
						else (float(r) / float(rows - 1) - 0.5) * v * 0.6)
					for xs in [-1.0, 1.0]:
						_add_voxel_to(body, Vector3(xs * v * 0.5, dy, i * v),
							Vector3(v * 0.15 * sizem, v * 0.3 * sizem, v * 0.3 * sizem), mat_a)
		3:
			# Vertical bars; bar_edged adds crisp borders whose darkness tracks contrast.
			for i in seg:
				for xs in [-1.0, 1.0]:
					_add_voxel_to(body, Vector3(xs * v * 0.5, 0, i * v),
						Vector3(v * 0.15 * sizem, v * 1.0 * thickm, v * 0.25 * sizem), mat_a)
					if bar_edged:
						for zoff_edge in [-v * 0.22 * sizem, v * 0.22 * sizem]:
							_add_voxel_to(body, Vector3(xs * v * 0.5, 0, i * v + zoff_edge),
								Vector3(v * 0.16 * sizem, v * 1.02 * thickm, v * 0.06), mat_edge)
		4:
			# Two-tone lateral band (tetra): bright upper marking + darker lower shadow.
			for i in seg:
				for xs in [-1.0, 1.0]:
					_add_voxel_to(body, Vector3(xs * v * 0.5, v * 0.22, i * v),
						Vector3(v * 0.16 * sizem, v * 0.42 * thickm, v * 0.95 * sizem), mat_m)
					_add_voxel_to(body, Vector3(xs * v * 0.5, -v * 0.28, i * v),
						Vector3(v * 0.15 * sizem, v * 0.38 * thickm, v * 0.95 * sizem), mat_a)
		5:
			# Rear-flank wedge (rasbora): tapering block over the rear segments.
			for i in range(1, seg):
				var wedge_h: float = v * (1.0 - 0.32 * float(i - 1)) * thickm
				for xs in [-1.0, 1.0]:
					_add_voxel_to(body, Vector3(xs * v * 0.46, -v * 0.1, i * v + v * 0.2),
						Vector3(v * 0.16 * sizem, maxf(wedge_h, v * 0.1), v * 0.7 * sizem), mat_m)
		6:
			# Reticulated net: a grid of accent dots; density adds rows.
			var grid: Array = ([-0.3, 0.0, 0.3] if dens < 0.66
				else [-0.36, -0.12, 0.12, 0.36])
			for i in seg:
				for gy in grid:
					var zjit: float = 0.0 if int(roundf(float(gy) * 10.0)) % 2 == 0 else v * 0.3
					for xs in [-1.0, 1.0]:
						_add_voxel_to(body, Vector3(xs * v * 0.5, v * float(gy), i * v + zjit),
							Vector3(v * 0.14 * sizem, v * 0.14 * sizem, v * 0.14 * sizem), mat_a)
		7:
			# Marbled / mottled: irregular blotches; density adds more.
			var blotch: Array = [
				Vector3(0.5, 0.2, 0.1), Vector3(0.5, -0.25, 1.1), Vector3(0.5, 0.05, 2.0),
			]
			if dens > 0.6:
				blotch.append(Vector3(0.5, 0.3, 1.6))
				blotch.append(Vector3(0.5, -0.1, 0.6))
			for b in blotch:
				for xs in [-1.0, 1.0]:
					_add_voxel_to(body,
						Vector3(xs * v * float(b.x), v * float(b.y), v * float(b.z)),
						Vector3(v * 0.16 * sizem, v * 0.34 * sizem, v * 0.4 * sizem), mat_m)
		8:
			# Head-band / mask: a dark bar across the front of the body.
			for xs in [-1.0, 1.0]:
				_add_voxel_to(body, Vector3(xs * v * 0.5, 0, 0),
					Vector3(v * 0.16 * sizem, v * 1.0 * thickm, v * 0.45 * sizem), mat_m)
		9:
			# Ocellated spot-rows: ringed false-eye spots along the flank.
			for i in seg:
				for xs in [-1.0, 1.0]:
					_add_voxel_to(body, Vector3(xs * v * 0.5, v * 0.05, i * v),
						Vector3(v * 0.16 * sizem, v * 0.36 * sizem, v * 0.36 * sizem), mat_a)
					_add_voxel_to(body, Vector3(xs * v * 0.52, v * 0.05, i * v),
						Vector3(v * 0.14 * sizem, v * 0.18 * sizem, v * 0.18 * sizem), mat_m)
		_:
			pass


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
	# Expanded morphology inheritance: continuous traits average + jitter,
	# clamped to the same bounds init_genome enforces.
	var new_body_width: float = clampf(
		(body_width_factor + partner.body_width_factor) * 0.5 + randf_range(-0.10, 0.10),
		0.5, 1.8)
	var new_snout_len: float = clampf(
		(snout_length_factor + partner.snout_length_factor) * 0.5 + randf_range(-0.10, 0.12),
		0.5, 2.5)
	var new_dorsal_len: float = clampf(
		(dorsal_length_factor + partner.dorsal_length_factor) * 0.5 + randf_range(-0.10, 0.12),
		0.5, 2.2)
	var new_nuchal: float = clampf(
		(nuchal_hump + partner.nuchal_hump) * 0.5 + randf_range(-0.08, 0.10),
		0.0, 1.0)
	# Discrete fin / sucker traits stay in the lineage with rare flips.
	var new_second_dorsal: bool = (second_dorsal if randf() < 0.96
		else (partner.second_dorsal if randf() < 0.5 else not second_dorsal))
	var new_ventral_sucker: bool = (ventral_sucker if randf() < 0.97
		else (partner.ventral_sucker if randf() < 0.5 else not ventral_sucker))
	# Barbel count drifts ±1 occasionally; clamped 0..8.
	var new_barbel_count: int = clampi(
		int(round((barbel_count + partner.barbel_count) * 0.5))
		+ ((randi() % 3 - 1) if randf() < 0.12 else 0), 0, 8)
	# Pattern: usually inherits from one parent, small chance to mutate to
	# any pattern (0-9, now incl. reticulated / marbled / mask / ocellated).
	var new_pattern: int = pattern_type if randf() < 0.5 else partner.pattern_type
	if randf() < 0.06:
		new_pattern = randi() % 10
	# Dots: average then small jitter, clamped 0-4.
	var new_dots: int = clampi(
		int((color_dot_count + partner.color_dot_count) * 0.5 + randf_range(-1.0, 1.0)),
		0, 4)
	# Continuous pattern modulators: average parents + jitter, clamped. These let
	# a lineage's markings drift wider/finer/bolder over generations so siblings
	# diverge into visibly distinct faces.
	var new_pat_scale: float = clampf(
		(pattern_scale + partner.pattern_scale) * 0.5 + randf_range(-0.12, 0.12), 0.0, 1.0)
	var new_pat_intensity: float = clampf(
		(pattern_intensity + partner.pattern_intensity) * 0.5 + randf_range(-0.12, 0.12), 0.0, 1.0)
	var new_pat_density: float = clampf(
		(pattern_density + partner.pattern_density) * 0.5 + randf_range(-0.12, 0.12), 0.0, 1.0)
	var new_pat_coverage: float = clampf(
		(pattern_coverage + partner.pattern_coverage) * 0.5 + randf_range(-0.10, 0.10), 0.2, 1.0)
	var new_pat_contrast: float = clampf(
		(pattern_contrast + partner.pattern_contrast) * 0.5 + randf_range(-0.12, 0.12), 0.0, 1.0)
	# Secondary motif: usually inherited from a parent; a rare new overlay can
	# emerge, seeding two-pattern phenotypes that compound over later generations.
	var new_pat_type_b: int = pattern_type_b if randf() < 0.6 else partner.pattern_type_b
	var new_pat_blend: float = clampf(
		(pattern_blend + partner.pattern_blend) * 0.5 + randf_range(-0.08, 0.08), 0.0, 1.0)
	if new_pat_type_b < 0 and randf() < 0.04:
		new_pat_type_b = randi() % 10
		new_pat_blend = randf_range(0.2, 0.5)
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
		var shapes: Array[String] = ["fusiform", "compressed", "globiform",
			"anguilliform", "depressed", "sagittiform", "ribbon"]
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
		"pattern_scale": new_pat_scale,
		"pattern_intensity": new_pat_intensity,
		"pattern_density": new_pat_density,
		"pattern_coverage": new_pat_coverage,
		"pattern_contrast": new_pat_contrast,
		"pattern_type_b": new_pat_type_b,
		"pattern_blend": new_pat_blend,
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
			else randi() % 6),
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
		"dimorphism": clampf((dimorphism + partner.dimorphism) * 0.5 + randf_range(-0.05, 0.05), 0.0, 1.0),
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
		"body_width_factor": new_body_width,
		"snout_length_factor": new_snout_len,
		"dorsal_length_factor": new_dorsal_len,
		"nuchal_hump": new_nuchal,
		"second_dorsal": new_second_dorsal,
		"ventral_sucker": new_ventral_sucker,
		"barbel_count": new_barbel_count,
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
	_apply_saltation(g)
	return g


# Rare, discontinuous "sport" mutations — the gasp moments. ~0.4% of offspring
# get a dramatic jump (albino, melanistic, xanthic, veil-fin, balloon body, or a
# bold disruptive overlay) that gradual drift would never produce. Tagged in the
# genome so discovery + future specimen cards can call them out.
static func _apply_saltation(g: Dictionary) -> void:
	if randf() > 0.004:
		return
	var kinds: Array[String] = ["albino", "melanistic", "xanthic", "veil",
		"balloon", "disruptive"]
	var kind: String = kinds[randi() % kinds.size()]
	match kind:
		"albino":
			var b: Color = g.get("base_color", Color(1, 1, 1))
			g["base_color"] = Color(1.0, 0.88, 0.88).lerp(b, 0.12)
			g["accent_color"] = Color(1.0, 0.74, 0.74)
			g["marking_color"] = Color(1.0, 0.62, 0.56)
			g["pattern_intensity"] = clampf(float(g.get("pattern_intensity", 0.5)) * 0.4, 0.0, 1.0)
		"melanistic":
			for k in ["base_color", "accent_color", "marking_color"]:
				if g.get(k) is Color:
					g[k] = (g[k] as Color).darkened(0.7)
			g["pattern_contrast"] = 0.2
		"xanthic":
			g["base_color"] = Color(1.0, 0.72, 0.12)
			g["accent_color"] = Color(1.0, 0.5, 0.06)
		"veil":
			g["fin_length_factor"] = clampf(float(g.get("fin_length_factor", 1.0)) * 1.5, 0.6, 1.6)
			g["finnage"] = clampf(float(g.get("finnage", 1.0)) + 0.8, 1.0, 2.2)
			g["tail_fork_depth"] = clampf(float(g.get("tail_fork_depth", 1.0)) * 1.3, 0.5, 1.5)
		"balloon":
			g["body_depth_factor"] = clampf(float(g.get("body_depth_factor", 1.0)) * 1.5, 0.7, 1.4)
			g["body_elongation"] = clampf(float(g.get("body_elongation", 1.0)) * 0.7, 0.65, 1.55)
		"disruptive":
			g["pattern_type_b"] = randi() % 10
			g["pattern_blend"] = randf_range(0.55, 0.9)
			g["pattern_contrast"] = clampf(float(g.get("pattern_contrast", 0.5)) + 0.4, 0.0, 1.0)
			g["pattern_density"] = clampf(float(g.get("pattern_density", 0.5)) + 0.3, 0.0, 1.0)
	g["saltation"] = kind


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
		"acclimation_remaining": _acclimation_remaining,
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
		# Persistent identity + memory (added with the AIDirector pass).
		# Names persist so a "Mira" in your tank stays Mira next session.
		# Bio + feed_heatmap give the player a sense of continuity with
		# specific individuals.
		"display_name": fish_name,
		"name_source": name_source,
		"personality": personality.duplicate(),
		"bio": bio.duplicate(),
		"feed_heatmap": Array(feed_heatmap),
		"grudges": grudges.duplicate(),
		"habituated": habituated.duplicate(),
		"rank_within_species": rank_within_species,
		"visited_regions": Array(visited_regions),
		# Inner life persisted so a fish stays the individual you know: it keeps
		# trusting you (familiarity), keeps its friends (bonds), and keeps its
		# emotional baseline (mood) across sessions.
		"familiarity": familiarity,
		"mood": mood,
		"bonds": bonds.duplicate(),
		# Individual-aliveness state (H9): lifelong size/lifespan variance, the
		# wariness scar from past frights, and the bonded mate id so loyalty +
		# the size hierarchy survive a reload.
		"life_jitter": _life_jitter,
		"growth_variance": _growth_variance,
		"scarred": _scarred,
		"mate_id": _mate_id,
		# Death animation state — persisting these means a fish that was
		# mid-death-pose when autosave fired comes back still dying instead
		# of being "resurrected" only to immediately re-die (which reads as
		# a looping death animation to the player). Wall-clock start also
		# persisted so the 12s safety timeout doesn't reset on each reload.
		"_dying": _dying,
		"_dying_timer": _dying_timer,
		"_dying_wall_start_unix": _dying_wall_start_unix,
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
	# Default: fully acclimated on load (assume reloaded fish are
	# already established; this avoids unfair stress for saved tanks).
	_acclimation_remaining = float(d.get("acclimation_remaining", 0.0))
	nibble_cooldown = float(d.get("nibble_cooldown", 0.0))
	breed_count = int(d.get("breed_count", 0))
	growth_factor = float(d.get("growth_factor", 1.0))
	_life_jitter = float(d.get("life_jitter", _life_jitter))
	_growth_variance = float(d.get("growth_variance", _growth_variance))
	_scarred = not not d.get("scarred", false)
	_mate_id = String(d.get("mate_id", ""))
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
	_reclamp_territory_to_tank()
	# Transient refs are NOT restored — they're cheap to re-pick next tick
	# and trying to resolve them across saves is fragile (the plant might
	# have just been nibbled to death). Clear them so the AI starts fresh.
	target_plant = null
	# Persistent identity + memory. init_genome already populated defaults;
	# we overwrite with the saved values when present so the player's named
	# fish keep their stats and personality across sessions.
	if d.has("display_name") and String(d["display_name"]) != "":
		fish_name = String(d["display_name"])
	if d.has("name_source"):
		name_source = String(d["name_source"])
	var saved_personality: Variant = d.get("personality", null)
	if saved_personality is Dictionary and not (saved_personality as Dictionary).is_empty():
		personality = (saved_personality as Dictionary).duplicate()
	var saved_bio: Variant = d.get("bio", null)
	if saved_bio is Dictionary and not (saved_bio as Dictionary).is_empty():
		bio = (saved_bio as Dictionary).duplicate()
	var saved_heatmap: Variant = d.get("feed_heatmap", null)
	if saved_heatmap is Array and (saved_heatmap as Array).size() == feed_heatmap.size():
		for i in range(feed_heatmap.size()):
			feed_heatmap[i] = float((saved_heatmap as Array)[i])
	var saved_grudges: Variant = d.get("grudges", null)
	if saved_grudges is Dictionary:
		grudges = (saved_grudges as Dictionary).duplicate()
	var saved_hab: Variant = d.get("habituated", null)
	if saved_hab is Dictionary:
		habituated = (saved_hab as Dictionary).duplicate()
	rank_within_species = float(d.get("rank_within_species", 0.5))
	familiarity = float(d.get("familiarity", 0.0))
	mood = float(d.get("mood", 0.2))
	var saved_bonds: Variant = d.get("bonds", null)
	if saved_bonds is Dictionary:
		bonds = (saved_bonds as Dictionary).duplicate()
	var saved_visited: Variant = d.get("visited_regions", null)
	if saved_visited is Array and (saved_visited as Array).size() == visited_regions.size():
		for i in range(visited_regions.size()):
			visited_regions[i] = int((saved_visited as Array)[i])
	# Restore death-animation state. Without this, a dying fish reloaded
	# from save comes back at full health and immediately re-dies — the
	# "fish death animation looping" bug.
	_dying = bool(d.get("_dying", false))
	_dying_timer = float(d.get("_dying_timer", 0.0))
	# Persist wall-clock start across reloads. If the save predates this
	# field, treat the fish as "just started dying" (stamp now). Without
	# this the 12s safety timeout would refresh on every reload and the
	# fish could spin forever in dying state.
	_dying_wall_start_unix = int(d.get("_dying_wall_start_unix", 0))
	if _dying and _dying_wall_start_unix == 0:
		_dying_wall_start_unix = int(Time.get_unix_time_from_system())
	# Safety: if the loaded state says we're dying but the timer is past
	# DEATH_DURATION (shouldn't happen, but defends against corrupted saves),
	# clamp to a small positive value so the fish completes the animation.
	if _dying and _dying_timer <= 0.0:
		_dying_timer = 0.1
	# Apply the dying pose immediately so the reloaded fish doesn't pop
	# from swimming to tilted on the first frame.
	if _dying and _bank_pivot != null:
		_bank_pivot.rotation.z = PI * 0.5
		var shrink: float = lerpf(1.0, 0.15, clampf(1.0 - _dying_timer / DEATH_DURATION, 0.0, 1.0))
		_bank_pivot.scale = Vector3(shrink, shrink, shrink)


# Pull body + territory anchors inside the tank footprint. Saved games from
# box tanks (or pre-curved-wall builds) can carry home coords outside a
# cylinder — clamping position alone leaves fish swimming into the void.
func _body_tank_margin() -> float:
	var base: float = clampf(adult_voxel_scale * _maturity_scale() * 2.4 + 0.32, 0.38, 0.65)
	match swim_pattern:
		"hover":
			return base * 0.88
		"dart":
			return base * 0.94
		"school", "shoal":
			return base * 1.04
		"shuffle":
			return base * 1.02
		_:
			return base


func _vertical_bands() -> Vector2:
	var floor_band: float = 0.50
	var ceil_band: float = 0.42
	if mouth_orientation == 1:
		floor_band = 0.72
	elif mouth_orientation == -1:
		ceil_band = 0.58
	if swim_pattern == "shuffle":
		floor_band = 0.85
	return Vector2(floor_band, ceil_band)


func _meniscus_headroom() -> float:
	return _water_surface_y() - position.y


func _surface_niche() -> bool:
	if mouth_orientation == -1 or labyrinth_breather or swim_pattern == "dart":
		return true
	if sim == null:
		return preferred_y >= 4.2
	var col_h: float = maxf(_water_column_height(), 0.5)
	var top_frac: float = clampf(
		(preferred_y - float(sim.substrate_top_y)) / col_h, 0.0, 1.0)
	return top_frac >= 0.62


func _surface_pin_release_active() -> bool:
	if _aerial_timer > 0.0 or brooding_remaining > 0.0 or sim == null:
		return false
	var o2_now: float = float(sim.dissolved_o2) - _chem_o2_penalty \
		if sim.get("dissolved_o2") != null else 1.0
	if o2_now < SURFACE_GULP_O2:
		return false
	var headroom: float = _meniscus_headroom()
	if headroom >= 0.65:
		return false
	if _surface_niche():
		# Top dwellers belong high, but shouldn't skid sideways along the glass.
		return headroom < 0.35
	return position.y > home_y + maxf(home_y_radius * 0.8, 0.4)


func _heading_away_from_meniscus(hz_hint: Vector3) -> Vector3:
	var hx: float = hz_hint.x
	var hz: float = hz_hint.z
	var horiz_len: float = sqrt(hx * hx + hz * hz)
	if horiz_len < 0.15:
		var phase_seed: float = float(get_instance_id() % 360)
		hx = cos(phase_seed)
		hz = sin(phase_seed)
		horiz_len = 1.0
	var down_y: float = -0.55
	var horiz_scale: float = sqrt(maxf(0.0, 1.0 - down_y * down_y))
	return Vector3(
		hx / horiz_len * horiz_scale,
		down_y,
		hz / horiz_len * horiz_scale)


func _reclamp_territory_to_tank() -> void:
	if sim == null:
		return
	var w: Node = sim.get_parent()
	if w == null or not w.has_method("clamp_xyz_in_tank"):
		return
	var m: float = _body_tank_margin()
	# Territory anchors only — body position is integrated in _motion_substep.
	var hp: Vector3 = w.clamp_xyz_in_tank(Vector3(home_x, home_y, home_z), 0.35, m * 0.5)
	home_x = hp.x
	home_y = hp.y
	home_z = hp.z
	if brooding_remaining > 0.0:
		brooding_at = w.clamp_xyz_in_tank(brooding_at, 0.30)


func _apply_target_from_desired(desired: Vector3, max_spd: float) -> Vector3:
	return _constrain_velocity_to_tank(desired.limit_length(max_spd))


func _lateral_boundary_context(gp: Vector3 = global_position, body_m: float = -1.0,
		heading_hint: Vector3 = Vector3.ZERO) -> Dictionary:
	if body_m < 0.0:
		body_m = _body_tank_margin()
	var w := _world_node()
	if w == null or not w.has_method("tank_lateral_boundary_info"):
		return {"clearance": 99.0, "inward": Vector3.ZERO, "body_m": body_m}
	var margin: float = body_m * 0.85 + 0.22
	var info: Dictionary = w.tank_lateral_boundary_info(gp, margin)
	if heading_hint.length_squared() > 0.01:
		var hz: Vector3 = Vector3(heading_hint.x, 0.0, heading_hint.z)
		if hz.length_squared() > 1e-6:
			hz = hz.normalized()
			var ahead: Vector3 = gp + hz * (body_m * 1.2 + 0.42)
			var ahead_info: Dictionary = w.tank_lateral_boundary_info(ahead, margin)
			if float(ahead_info.get("clearance", 99.0)) < float(info.get("clearance", 99.0)):
				info = ahead_info
	info["body_m"] = body_m
	return info


func _vertical_boundary_context(gp: Vector3 = global_position, body_m: float = -1.0) -> Dictionary:
	if body_m < 0.0:
		body_m = _body_tank_margin()
	var w := _world_node()
	if w == null or not w.has_method("tank_vertical_boundary_info"):
		return {"clearance": 99.0, "inward": Vector3.ZERO, "active": false}
	var bands: Vector2 = _vertical_bands()
	return w.tank_vertical_boundary_info(
		gp, body_m * 0.55 + 0.12, bands.x, bands.y)


func _boundary_context(gp: Vector3 = global_position, body_m: float = -1.0) -> Dictionary:
	return _lateral_boundary_context(gp, body_m)


func _max_inside_travel(from: Vector3, dir: Vector3, max_len: float,
		margin: float, body_r: float) -> float:
	var w := _world_node()
	if w == null or not w.has_method("clamp_xyz_in_tank") or max_len <= 0.0:
		return 0.0
	if dir.length_squared() < 1e-8:
		return 0.0
	dir = dir.normalized()
	var lo: float = 0.0
	var hi: float = max_len
	for _i in 14:
		var mid: float = (lo + hi) * 0.5
		var probe: Vector3 = from + dir * mid
		var clamped: Vector3 = w.clamp_xyz_in_tank(probe, margin, body_r)
		if probe.distance_squared_to(clamped) < 1e-10:
			lo = mid
		else:
			hi = mid
	return lo


func _constrain_velocity_to_tank(vel: Vector3) -> Vector3:
	if vel.length_squared() < 1e-8:
		return vel
	vel = _constrain_velocity_lateral(vel)
	vel = _constrain_velocity_vertical(vel)
	return vel


func _constrain_velocity_lateral(vel: Vector3) -> Vector3:
	var hint: Vector3 = vel if vel.length_squared() > 1e-6 else heading
	var bnd: Dictionary = _lateral_boundary_context(global_position, -1.0, hint)
	var clearance: float = float(bnd.get("clearance", 99.0))
	var inward: Vector3 = bnd.get("inward", Vector3.ZERO)
	var body_m: float = float(bnd.get("body_m", _body_tank_margin()))
	if inward.length_squared() < 1e-6:
		return vel
	var h_in: Vector3 = inward
	h_in.y = 0.0
	if h_in.length_squared() < 1e-6:
		return vel
	h_in = h_in.normalized()
	var h_vel: Vector3 = Vector3(vel.x, 0.0, vel.z)
	if h_vel.length_squared() < 1e-8:
		return vel
	var repel_dist: float = body_m * 2.4 + 0.42
	var outward: Vector3 = -h_in
	var out_speed: float = h_vel.dot(outward)
	if out_speed > 0.0:
		if clearance < repel_dist:
			h_vel -= outward * out_speed
		elif clearance < repel_dist * 1.8:
			var fade: float = 1.0 - (clearance - repel_dist) / (repel_dist * 0.8)
			h_vel -= outward * (out_speed * clampf(fade, 0.0, 1.0))
	if clearance < body_m * 0.55:
		var into: float = maxf(0.0, h_vel.dot(outward))
		if into > 0.08:
			h_vel += h_in * (body_m * 0.55 - clearance) * 0.55
	return Vector3(h_vel.x, vel.y, h_vel.z)


func _constrain_velocity_vertical(vel: Vector3) -> Vector3:
	var vert: Dictionary = _vertical_boundary_context(global_position)
	if not bool(vert.get("active", false)):
		return vel
	var clearance: float = float(vert.get("clearance", 99.0))
	var inward: Vector3 = vert.get("inward", Vector3.ZERO)
	if inward.length_squared() < 1e-6:
		return vel
	var outward: Vector3 = -inward
	var out_speed: float = vel.dot(outward)
	if out_speed > 0.0 and clearance < 0.48:
		var fade: float = 1.0 - clampf(clearance / 0.48, 0.0, 1.0)
		vel -= outward * (out_speed * fade)
	if clearance < 0.28:
		vel += inward * (0.28 - clearance) * 0.75
	return vel


func _pick_wall_escape_heading(inward: Vector3, blocked: Vector3) -> Vector3:
	var outward: Vector3 = -inward
	var tangent: Vector3 = blocked - outward * blocked.dot(outward)
	if tangent.length_squared() > 0.06:
		return tangent.normalized()
	if absf(inward.y) < 0.9:
		return Vector3(-inward.z, 0.0, inward.x).normalized()
	return Vector3(1.0, 0.0, 0.0)


# Damped specular bounce off lateral glass (matches floater _resolve_floater_glass).
func _reflect_heading_at_wall(move_dir: Vector3, inward: Vector3) -> Vector3:
	const BOUNCE_DAMP: float = 0.72
	inward.y = 0.0
	if inward.length_squared() < 1e-6:
		return move_dir
	inward = inward.normalized()
	var outward: Vector3 = -inward
	var h_move: Vector3 = Vector3(move_dir.x, 0.0, move_dir.z)
	if h_move.length_squared() < 1e-6:
		return _pick_wall_escape_heading(inward, move_dir)
	h_move = h_move.normalized()
	var vn: float = h_move.dot(outward)
	if vn <= 0.05:
		return move_dir
	var tangent: Vector3 = h_move - outward * vn
	var reflected: Vector3 = tangent - outward * (vn * BOUNCE_DAMP)
	if reflected.length_squared() < 0.04:
		return _pick_wall_escape_heading(inward, move_dir)
	var out: Vector3 = reflected.normalized()
	out.y = clampf(move_dir.y * 0.85, -0.52, 0.52)
	if out.length_squared() < 1e-6:
		return _pick_wall_escape_heading(inward, move_dir)
	return out.normalized()


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
