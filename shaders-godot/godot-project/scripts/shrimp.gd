# A shrimp. Walks on substrate, climbs plants to nibble their tips, hunts
# detritus and the occasional tiny prey (baby snail / fry).
#
# Movement model is simpler than the fish: shrimp use a directional velocity
# but they're "weighted" - they sink to the substrate when not actively climbing.
# A shrimp targeting a plant gets a strong upward velocity component; once it
# stops climbing, mild gravity pulls it back down.
#
# Food web role:
#   - Detritivore: claims waste particles as food
#   - Herbivore: nibbles tips of tall plants
#   - Opportunistic predator: occasionally catches fry / baby snails
#   - Excretes shrimp-grade waste particles (lighter, smaller than fish)
#
# Life cycle: berried adult → fry (small, vulnerable) → juvenile → adult →
# senescent → dies. Fry can be eaten by fish or other adult shrimp.

extends Node3D
class_name Shrimp

# See fish.gd for why we preload instead of relying on class_name.
const CreatureNaming = preload("res://scripts/creature_naming.gd")
const FaunaVoxelBuilder = preload("res://scripts/fauna_voxel_builder.gd")
const SpeciesLibScript = preload("res://scripts/species_library.gd")

const MATURITY_FRY := 0
const MATURITY_JUVENILE := 1
const MATURITY_ADULT := 2
const MATURITY_SENESCENT := 3

enum Mode { WANDER, FORAGE_WASTE, CLIMB, NIBBLE, HUNT, COURT, REST, CLEAN }

# ---- Genome (set at spawn) ----
var species: String = "shrimp"
var base_color: Color = Color8(180, 90, 70)         # neocaridina red default
var accent_color: Color = Color8(245, 220, 200)     # belly cream
var adult_voxel_scale: float = 0.10                 # smaller than fish
var max_age_s: float = 360.0                        # ~6 minutes lifespan
var max_speed: float = 0.85
var max_turn_rate: float = 4.0                      # nimble
var sex: int = 0

# ---- Lineage ----
var generation: int = 0
var shrimp_name: String = ""
var parent_lineage: String = "Founders"


# ---- State ----
var age: float = 0.0
var hunger: float = 0.3
var energy: float = 1.0
var maturity: int = MATURITY_FRY
var velocity: Vector3 = Vector3.ZERO
var heading: Vector3 = Vector3.FORWARD
var speed: float = 0.0
var _escape_remaining: float = 0.0
var _pleopod_phase: float = 0.0
var _hydro_profile: Dictionary = {}
var current_mode: Mode = Mode.WANDER
var breed_cooldown: float = 0.0

# Climbing target. When non-null, shrimp moves toward this plant and ascends.
var climb_target: Plant = null
var climb_remaining_time: float = 0.0  # countdown before giving up
const CLIMB_GIVE_UP_TIME: float = 18.0  # if can't reach, give up

# Courtship + gravidity (berried-female mechanic).
var partner: Shrimp = null
var court_timer: float = 0.0
const COURT_DURATION: float = 4.0
const GRAVIDITY_DURATION: float = 25.0
var clutch_size: int = 3
# is_gravid: true on females after a completed courtship - they carry the
# egg cluster visibly under their tail for GRAVIDITY_DURATION seconds before
# releasing fry. Real cherry shrimp call this "berried".
var is_gravid: bool = false
var gravid_timer: float = 0.0
var gravid_partner_genome: Dictionary = {}  # cached mate genome at fertilization
var _egg_cluster: Node3D = null
# Molting: shrimp shed their exoskeleton periodically. Real cherry shrimp
# molt every 30-60 days; the sim's compressed time uses 60-120s. A molt
# produces a brief visible "pop" + drops an exuvia (small KIND_SHRIMP
# waste) at the substrate that snails / detritivores can eat.
var _molt_timer: float = 0.0
var _molt_flash: float = 0.0
const MOLT_INTERVAL_MIN: float = 60.0
const MOLT_INTERVAL_MAX: float = 120.0

# Marine / cleaner-shrimp variant (Lysmata amboinensis - skunk cleaner).
# When is_cleaner == true:
#   - body builder uses a red base + a white spine stripe + extra-long
#     white antennae for the distinctive skunk look
#   - tick adds a CLEANING_STATION behavior tier: pause near high-stress
#     fish, reduce their stress, gain a tiny food reward (parasites)
# Set on saltwater spawns; freshwater cherry / amber morphs keep the
# default colour-only body.
var is_cleaner: bool = false
var defense_spines: float = 0.0  # 0..1, visual dorsal spines + anti-predator deterrence
var toxin_level: float = 0.0     # 0..1, warning coloration / distasteful prey
var claw_size: float = 0.25      # 0..1.2, enlarged chelae improve close hunting
var body_length_factor: float = 1.0  # 0.75..1.7, controls long-bodied morphs
# ---- Expanded crustacean architecture (heritable) ----
# body_shape branches the whole silhouette; the rest are continuous/discrete
# refinements. Defaults reproduce the classic caridean shrimp so existing
# saves and founder genomes render unchanged.
#  - body_shape    "caridean" (curl-tail shrimp, default), "crab" (wide flat
#                  carapace, tucked abdomen, splayed legs), "lobster"
#                  (crayfish/lobster — long straight abdomen + big claws),
#                  "mantis" (elongate, raptorial arms, stalked eyes).
#  - rostrum_length 0..1.5 saw-snout spike between the eyes (caridina long).
#  - eye_stalk_length 0..1 raised stalked eyes (crab/mantis); 0 = sessile.
#  - abdomen_curl  0..1 arch of the tail/abdomen (shrimp curl vs straight lobster).
#  - antenna_length_factor 0.5..2.5 (generalises the cleaner-shrimp long antennae).
#  - leg_length_factor 0.5..2.0 walking-leg length.
#  - claw_asymmetry 0..1 one claw enlarged (pistol shrimp, fiddler crab).
#  - filter_fans   bamboo/wood-shrimp feeding fans on the front legs.
#  - pattern_type  0 solid / 1 bands (crystal/bee) / 2 saddle spots / 3 stripe.
var body_shape: String = "caridean"
var rostrum_length: float = 0.3
var eye_stalk_length: float = 0.0
var abdomen_curl: float = 0.6
var antenna_length_factor: float = 1.0
var leg_length_factor: float = 1.0
var claw_asymmetry: float = 0.0
var filter_fans: bool = false
var pattern_type: int = 0
# Continuous pattern modulators (heritable; mirror the fish system). scale sizes
# each band / spot, intensity sets boldness, density adds extra rings / spots.
var pattern_scale: float = 0.5
var pattern_intensity: float = 0.5
var pattern_density: float = 0.5
var shelter_bonus: float = 0.0   # runtime anti-predator cover bonus (read by fish AI)
# Cleaning-station behavior state.
var _clean_target: Node3D = null
var _clean_hold: float = 0.0
const CLEAN_RADIUS: float = 1.4
const CLEAN_HOLD_DURATION: float = 3.0
const CLEAN_COOLDOWN: float = 12.0
var _clean_cooldown: float = 0.0
# SENTIENCE_THE_SPARK B35 — repeat clients at the cleaning station.
var clean_clients: Dictionary = {}
var _shelter_target: Plant = null
const SHELTER_SCAN_RADIUS: float = 3.4
# Tracks how many successful broods this individual has had. Used for
# breeding-partner bias - successful breeders are more attractive (cheap
# stand-in for true sexual selection).
var breed_count: int = 0

# Internal substrate-top reference set by SimDriver via init.
var substrate_top_y: float = 1.6

# Shrimp size growth from feeding. Same mechanic as Fish.growth_factor:
# well-fed adults grow above baseline; chronically hungry shrink. Used for
# cannibalism size comparison.
var growth_factor: float = 1.0
const MAX_GROWTH: float = 1.5


func effective_size() -> float:
	return adult_voxel_scale * _maturity_scale() * growth_factor

# Animation
var _swim_phase: float = 0.0
var _tail_pivot: Node3D = null
var _antenna_pivot: Node3D = null
var _antenna_seg_pivots: Array = []
var _bank_pivot: Node3D = null
var _voxel_builder: FaunaVoxelBuilder = null
var _last_yaw: float = 0.0
var _bank: float = 0.0

# Death animation state. Mirrors fish.gd — when a die event fires the shrimp
# tilts onto its side, drifts to the substrate, fades alpha, then frees and
# drops a mulm waste particle. Predator kills bypass this (kill_prey is still
# instant — the prey reads as eaten, not dying).
var _dying: bool = false
var _dying_timer: float = 0.0
# Wall-clock safety net — see fish.gd for the rationale. Force-frees a
# dying shrimp that's been stuck for too long (dt starvation, repeated
# save/load resets, etc.). 10s wall-clock vs 12s on fish because shrimp
# animation is only 2.5s.
var _dying_wall_start_unix: int = 0
const DEATH_WALL_CLOCK_MAX: int = 10
const DEATH_DURATION: float = 2.5

# Refs
var sim: Node = null


# ---- Save / load ----
# Stable cross-session id and original-genome cache. See fish.gd for the
# rationale — same pattern, applied to shrimp.
var id: String = ""
var _saved_genome: Dictionary = {}

# ---- AIDirector additions: personality + bio + name source ----
# Mirror of fish.gd's pattern. Shrimp skip the feed_heatmap (they forage
# by waste trail / wall crawl — too localized for a 3D heatmap to help)
# but get the same personality scalars and lifetime journal.
var name_source: String = "offline"
var personality: Dictionary = {}
var bio: Dictionary = {}


# ---- Setup ----

func get_saved_genome() -> Dictionary:
	return _saved_genome.duplicate(true)


func init_genome(genome: Dictionary) -> void:
	_saved_genome = genome.duplicate(true)
	if not _saved_genome.has("organism_type"):
		_saved_genome["organism_type"] = "shrimp"
	species = genome.get("species", species)
	base_color = genome.get("base_color", base_color)
	accent_color = genome.get("accent_color", accent_color)
	adult_voxel_scale = genome.get("adult_voxel_scale", adult_voxel_scale)
	max_age_s = genome.get("max_age_s", max_age_s)
	max_speed = genome.get("max_speed", max_speed)
	sex = genome.get("sex", randi() % 2)
	substrate_top_y = genome.get("substrate_top_y", substrate_top_y)
	is_cleaner = not not genome.get("is_cleaner", is_cleaner)
	defense_spines = clampf(float(genome.get("defense_spines", defense_spines)), 0.0, 1.0)
	toxin_level = clampf(float(genome.get("toxin_level", toxin_level)), 0.0, 1.0)
	claw_size = clampf(float(genome.get("claw_size", claw_size)), 0.0, 1.2)
	body_length_factor = clampf(float(genome.get("body_length_factor", body_length_factor)), 0.75, 1.7)
	# Expanded crustacean architecture genes.
	body_shape = String(genome.get("body_shape", body_shape))
	rostrum_length = clampf(float(genome.get("rostrum_length", rostrum_length)), 0.0, 1.5)
	eye_stalk_length = clampf(float(genome.get("eye_stalk_length", eye_stalk_length)), 0.0, 1.0)
	abdomen_curl = clampf(float(genome.get("abdomen_curl", abdomen_curl)), 0.0, 1.0)
	antenna_length_factor = clampf(float(genome.get("antenna_length_factor", antenna_length_factor)), 0.5, 2.5)
	leg_length_factor = clampf(float(genome.get("leg_length_factor", leg_length_factor)), 0.5, 2.0)
	claw_asymmetry = clampf(float(genome.get("claw_asymmetry", claw_asymmetry)), 0.0, 1.0)
	filter_fans = not not genome.get("filter_fans", filter_fans)
	pattern_type = int(genome.get("pattern_type", pattern_type))
	pattern_scale = clampf(float(genome.get("pattern_scale", pattern_scale)), 0.0, 1.0)
	pattern_intensity = clampf(float(genome.get("pattern_intensity", pattern_intensity)), 0.0, 1.0)
	pattern_density = clampf(float(genome.get("pattern_density", pattern_density)), 0.0, 1.0)
	# Body-plan defaults so a minimal founder genome still reads right: crab /
	# mantis carry stalked eyes, crab tucks its abdomen, lobster holds it straight.
	if (body_shape == "crab" or body_shape == "mantis") and not genome.has("eye_stalk_length"):
		eye_stalk_length = maxf(eye_stalk_length, 0.6)
	if body_shape == "crab" and not genome.has("abdomen_curl"):
		abdomen_curl = 1.0
	elif body_shape == "lobster" and not genome.has("abdomen_curl"):
		abdomen_curl = 0.1
	max_speed = clampf(
		max_speed * (1.0 + claw_size * 0.10 - (body_length_factor - 1.0) * 0.18),
		0.35, 1.6)
	generation = int(genome.get("generation", 0))
	
	shrimp_name = genome.get("shrimp_name", "")
	if shrimp_name == "":
		if genome.has("_display_name"):
			shrimp_name = String(genome["_display_name"])
		else:
			# Same offline-or-Ollama path as fish — AIDirector falls back to
			# CreatureNaming when the model is offline.
			var ai: Node = null
			if is_inside_tree():
				ai = get_node_or_null("/root/AIDirector")
			var picked: Dictionary
			if ai != null and ai.has_method("consume_name"):
				picked = ai.consume_name("shrimp", {})
			else:
				picked = {"name": CreatureNaming.generate_name("shrimp", {}), "source": "offline"}
			shrimp_name = String(picked.get("name", "Shrimp"))
			name_source = String(picked.get("source", "offline"))
	parent_lineage = genome.get("parent_lineage", "Founders")
	# Personality + bio (inherit from genome if breeding hook set it).
	var inherited_p: Dictionary = genome.get("personality", {})
	if inherited_p.is_empty():
		personality = CreatureNaming.roll_personality()
	else:
		personality = CreatureNaming.roll_personality(inherited_p)
	if bio.is_empty():
		bio = {
			"birth_unix": int(Time.get_unix_time_from_system()),
			"meals_eaten": 0,
			"offspring": 0,
			"name_source": name_source,
		}
	
	_saved_genome["shrimp_name"] = shrimp_name
	_saved_genome["parent_lineage"] = parent_lineage
	_saved_genome["generation"] = generation
	_saved_genome["defense_spines"] = defense_spines
	_saved_genome["toxin_level"] = toxin_level
	_saved_genome["claw_size"] = claw_size
	_saved_genome["body_length_factor"] = body_length_factor
	_saved_genome["body_shape"] = body_shape
	_saved_genome["rostrum_length"] = rostrum_length
	_saved_genome["eye_stalk_length"] = eye_stalk_length
	_saved_genome["abdomen_curl"] = abdomen_curl
	_saved_genome["antenna_length_factor"] = antenna_length_factor
	_saved_genome["leg_length_factor"] = leg_length_factor
	_saved_genome["claw_asymmetry"] = claw_asymmetry
	_saved_genome["filter_fans"] = filter_fans
	_saved_genome["pattern_type"] = pattern_type
	_saved_genome["pattern_scale"] = pattern_scale
	_saved_genome["pattern_intensity"] = pattern_intensity
	_saved_genome["pattern_density"] = pattern_density
	
	scale = Vector3.ONE * _maturity_scale()
	_build_body()
	# Start each shrimp facing a random horizontal direction.
	var theta: float = randf() * TAU
	heading = Vector3(sin(theta), 0.0, -cos(theta))
	_last_yaw = atan2(heading.x, -heading.z)
	_visual_heading = heading
	# Start with random hunger so they don't all forage at once.
	hunger = randf_range(0.2, 0.5)
	# Make sure babies start at substrate level.
	position.y = substrate_top_y + 0.1


func _maturity_scale() -> float:
	match maturity:
		MATURITY_FRY:        return 0.40
		MATURITY_JUVENILE:   return 0.70
		MATURITY_ADULT:      return 1.0
		MATURITY_SENESCENT:  return 0.95
		_: return 1.0


func _build_body() -> void:
	_voxel_builder = FaunaVoxelBuilder.new()
	# Voxel crustacean facing -Z. body_shape branches the silhouette:
	#   caridean  curl-tailed shrimp (default)
	#   crab      wide flat carapace, tucked abdomen, splayed legs
	#   lobster   long straight abdomen + big claws (crayfish / lobster)
	#   mantis    elongate body, folded raptorial arms, stalked eyes
	var v: float = adult_voxel_scale
	var lenf: float = body_length_factor
	# Shrimp bodies are TRANSLUCENT — real freshwater shrimp (neocaridina,
	# crystal, amano) read as glassy with internal organs faintly visible
	# through the carapace. Body + belly use the translucent voxel shader
	# with alpha baked into the color; eyes/claws/antennae stay opaque so
	# they read as solid against the see-through body.
	var body_color: Color = Color(base_color.r, base_color.g, base_color.b, 0.72)
	var belly_color: Color = Color(accent_color.r, accent_color.g, accent_color.b, 0.65)
	var mat_body := VoxelMat.make_translucent(body_color)
	var mat_belly := VoxelMat.make_translucent(belly_color)
	var mat_eye := VoxelMat.make(Color8(11, 11, 14))
	var mat_dark := VoxelMat.fauna_color_carrier(base_color.darkened(0.3))
	var mat_antenna := VoxelMat.fauna_color_carrier(base_color.darkened(0.15))
	if toxin_level > 0.35:
		var warn: Color = base_color.lerp(Color8(245, 235, 80), clampf(toxin_level * 0.55, 0.0, 0.55))
		# Warning coloration stays translucent — the toxin signal is the
		# yellow lerp, the shrimp is still see-through.
		var warn_color: Color = Color(warn.r, warn.g, warn.b, 0.78)
		mat_body = VoxelMat.make_translucent(warn_color)

	_bank_pivot = Node3D.new()
	_bank_pivot.name = "BankPivot"
	add_child(_bank_pivot)

	# ---- Body-plan core (carapace/thorax + abdomen + eyes + claws + legs +
	# _tail_pivot). Each branch creates _tail_pivot so the shared egg cluster
	# below can attach to it. ----
	match body_shape:
		"crab":
			_build_crab_core(v, lenf, mat_body, mat_belly, mat_eye, mat_dark)
		"lobster":
			_build_lobster_core(v, lenf, mat_body, mat_belly, mat_eye, mat_dark)
		"mantis":
			_build_mantis_core(v, lenf, mat_body, mat_belly, mat_eye, mat_dark)
		_:
			_build_caridean_core(v, lenf, mat_body, mat_belly, mat_eye, mat_dark)

	# ---- Shared appendages & ornaments ----
	# Antennae - thin voxels jutting forward on their own pivot so they twitch.
	# Length scales with antenna_length_factor; cleaner shrimp wave long bright
	# white antennae at fish (the "I'll clean you" cleaning-station signal).
	# Crabs are stubby.
	_antenna_pivot = Node3D.new()
	_antenna_pivot.name = "Antennae"
	_antenna_pivot.position = Vector3(0, v * 0.3, -v * 1.2)
	_bank_pivot.add_child(_antenna_pivot)
	var antenna_mat: Material = mat_antenna
	var antenna_len: float = 0.9 * antenna_length_factor
	if is_cleaner:
		antenna_mat = VoxelMat.fauna_color_carrier(Color8(250, 250, 250))
		antenna_len = maxf(antenna_len, 1.6)
	if body_shape == "crab":
		antenna_len *= 0.4
	_antenna_seg_pivots.clear()
	_build_antenna_chain(_antenna_pivot, 1.0, v, antenna_len, antenna_mat)
	_build_antenna_chain(_antenna_pivot, -1.0, v, antenna_len, antenna_mat)

	# Rostrum - the saw-toothed snout spike between the eyes. Caridina carry a
	# long one; crabs have none.
	if rostrum_length > 0.05 and body_shape != "crab":
		var rost_mat: Material = VoxelMat.fauna_color_carrier(base_color.darkened(0.1))
		_voxel(_bank_pivot, Vector3(0, v * 0.45, -v * (1.3 + rostrum_length * 0.8)),
			Vector3(v * 0.07, v * 0.1, v * (0.4 + rostrum_length * 0.9)), rost_mat)

	# Egg cluster (visible only when is_gravid). Bright yellow-orange spheres
	# carried under the swimmerets; parented to the tail pivot so they bob.
	if _tail_pivot != null:
		_egg_cluster = Node3D.new()
		_egg_cluster.name = "EggCluster"
		_egg_cluster.position = Vector3(0, -v * 0.15, v * 0.3)
		_egg_cluster.visible = false
		_tail_pivot.add_child(_egg_cluster)
		var mat_egg := VoxelMat.make_translucent(Color(0.94, 0.65, 0.24, 0.58))
		for ex in [-0.18, 0.0, 0.18]:
			for ez in [-0.1, 0.1]:
				_voxel(_egg_cluster, Vector3(ex * v, 0.0, ez * v),
					Vector3(v * 0.18, v * 0.18, v * 0.18), mat_egg)

	# Colour banding pattern across the carapace + abdomen.
	if pattern_type > 0:
		_build_shrimp_pattern(v, lenf)

	# Cleaner-shrimp spine stripe: a single bright white voxel running along
	# the top of the body. The signature "skunk" stripe of Lysmata amboinensis.
	if is_cleaner:
		var stripe_mat := VoxelMat.fauna_color_carrier(Color8(252, 252, 252))
		_voxel(_bank_pivot, Vector3(0, v * 0.65, -v * 0.8),
			Vector3(v * 0.16, v * 0.08, v * 0.6), stripe_mat)
		_voxel(_bank_pivot, Vector3(0, v * 0.7, 0),
			Vector3(v * 0.16, v * 0.08, v * 0.85), stripe_mat)
		_voxel(_bank_pivot, Vector3(0, v * 0.65, v * 0.55),
			Vector3(v * 0.16, v * 0.08, v * 0.5), stripe_mat)

	# Defensive dorsal spines (Amano/cherry-style exaggerated trait). Higher
	# values add a more pronounced ridge, acting as visible anti-predator armor.
	if defense_spines > 0.12:
		var spine_mat: Material = VoxelMat.fauna_color_carrier(base_color.lightened(0.12))
		var spine_n: int = clampi(int(round(1.0 + defense_spines * 4.0)), 1, 5)
		for i in spine_n:
			var t: float = float(i) / float(maxi(1, spine_n - 1))
			var z: float = lerpf(-v * 0.65, v * 0.62, t)
			var h: float = v * (0.08 + defense_spines * 0.28) * (1.0 - absf(t - 0.5) * 0.4)
			_voxel(_bank_pivot, Vector3(0.0, v * 0.68 + h * 0.5, z),
				Vector3(v * 0.10, h, v * 0.08), spine_mat)
	# Filter-feeding fans (bamboo/wood shrimp) OR pleopod fan detail on large
	# grown shrimp.
	if filter_fans:
		_build_filter_fans(v)
	elif growth_factor > 1.05 or adult_voxel_scale > 0.12:
		var fan_mat: Material = VoxelMat.fauna_color_carrier(accent_color.lightened(0.05))
		var fan_n: int = clampi(2 + int((growth_factor - 1.0) * 5.0), 2, 5)
		for i in fan_n:
			var t: float = float(i) / float(maxi(1, fan_n - 1))
			var zf: float = lerpf(-v * 0.15, v * 0.95, t)
			_voxel(_bank_pivot, Vector3(v * 0.22, -v * 0.28, zf),
				Vector3(v * 0.09, v * 0.07, v * 0.24), fan_mat)
			_voxel(_bank_pivot, Vector3(-v * 0.22, -v * 0.28, zf),
				Vector3(v * 0.09, v * 0.07, v * 0.24), fan_mat)
	if toxin_level > 0.32:
		var warn_mat: Material = VoxelMat.fauna_color_carrier(base_color.lerp(Color8(250, 228, 110),
			clampf(toxin_level * 0.55, 0.0, 0.55)))
		var flange_h: float = v * (0.10 + toxin_level * 0.20)
		for zf in [-v * 0.35, v * 0.05, v * 0.45]:
			_voxel(_bank_pivot, Vector3(v * 0.56, v * 0.10, zf),
				Vector3(v * 0.08, flange_h, v * 0.16), warn_mat)
			_voxel(_bank_pivot, Vector3(-v * 0.56, v * 0.10, zf),
				Vector3(v * 0.08, flange_h, v * 0.16), warn_mat)

	# Stagger first molt so the population doesn't molt in lock-step.
	_molt_timer = randf_range(MOLT_INTERVAL_MIN, MOLT_INTERVAL_MAX)
	if _voxel_builder != null:
		_voxel_builder.flush_all()


# ---- Body-plan cores ----
# Each builds the carapace/thorax, abdomen (creating _tail_pivot), eyes,
# claws and legs for one crustacean silhouette. Shared ornaments are added
# back in _build_body after the dispatch.

func _build_caridean_core(v: float, lenf: float, mat_body: Material, mat_belly: Material,
		mat_eye: Material, mat_dark: Material) -> void:
	# Classic shrimp: stacked carapace, thick mid, curl-up tail. With the
	# default genes (eye_stalk_length 0, abdomen_curl 0.6, claw_asymmetry 0,
	# leg_length_factor 1) this is byte-equivalent to the original body.
	_voxel(_bank_pivot, Vector3(0, v * 0.3, -v * 0.8 * lenf),
		Vector3(v * 0.9, v * 0.9, v * 0.9 * lenf), mat_body)
	_voxel(_bank_pivot, Vector3(0, -v * 0.3, -v * 0.8 * lenf),
		Vector3(v * 0.7, v * 0.3, v * 0.7 * lenf), mat_belly)
	_build_eyes(v, -v * 1.1, mat_eye, mat_dark)
	# Mid segment (thickest part of carapace).
	_voxel(_bank_pivot, Vector3(0, v * 0.3, 0), Vector3(v * 1.1, v * 1.0, v * 0.9 * lenf), mat_body)
	_voxel(_bank_pivot, Vector3(0, -v * 0.4, 0), Vector3(v * 0.9, v * 0.25, v * 0.7 * lenf), mat_belly)
	# Tail segments (curl upward and back). abdomen_curl scales the arch;
	# 0.6 reproduces the classic shrimp curl.
	_tail_pivot = Node3D.new()
	_tail_pivot.name = "TailPivot"
	_tail_pivot.position = Vector3(0, v * 0.4, v * 0.6 * lenf)
	_bank_pivot.add_child(_tail_pivot)
	var curl: float = abdomen_curl / 0.6
	_voxel(_tail_pivot, Vector3(0, 0, 0), Vector3(v * 0.8, v * 0.7, v * 0.6 * lenf), mat_body)
	_voxel(_tail_pivot, Vector3(0, v * 0.3 * curl, v * 0.5 * lenf),
		Vector3(v * 0.6, v * 0.5, v * 0.5 * lenf), mat_body)
	_voxel(_tail_pivot, Vector3(0, v * 0.5 * curl, v * 1.0 * lenf),
		Vector3(v * 0.7, v * 0.2, v * 0.3 * lenf), mat_dark)
	_build_claws(v, lenf)
	_build_legs(v, mat_dark)


func _build_crab_core(v: float, lenf: float, mat_body: Material, mat_belly: Material,
		mat_eye: Material, mat_dark: Material) -> void:
	# Wide flat carapace (cephalothorax); the abdomen is reduced to a small
	# flap tucked underneath. Walking legs splay to both sides.
	_voxel(_bank_pivot, Vector3(0, v * 0.25, 0),
		Vector3(v * 1.7, v * 0.5, v * 1.25 * lenf), mat_body)
	_voxel(_bank_pivot, Vector3(0, v * 0.5, -v * 0.1),
		Vector3(v * 1.3, v * 0.3, v * 0.9 * lenf), mat_body)
	_voxel(_bank_pivot, Vector3(0, -v * 0.1, 0),
		Vector3(v * 1.4, v * 0.25, v * 1.0 * lenf), mat_belly)
	# Tucked abdomen flap = the _tail_pivot (berried females carry eggs here).
	_tail_pivot = Node3D.new()
	_tail_pivot.name = "TailPivot"
	_tail_pivot.position = Vector3(0, -v * 0.12, v * 0.55 * lenf)
	_bank_pivot.add_child(_tail_pivot)
	_voxel(_tail_pivot, Vector3(0, 0, 0), Vector3(v * 0.5, v * 0.15, v * 0.45), mat_belly)
	_build_eyes(v, -v * 0.55 * lenf, mat_eye, mat_dark)
	_build_claws(v, lenf)
	# Walking legs splayed wide to both sides (4 pairs).
	var ll: float = leg_length_factor
	for i in 4:
		var zf: float = lerpf(-0.5, 0.7, float(i) / 3.0) * lenf
		for x_side in [-1.0, 1.0]:
			_voxel(_bank_pivot, Vector3(x_side * v * 1.05, -v * 0.05, v * zf),
				Vector3(v * 0.7 * ll, v * 0.08, v * 0.1), mat_dark)
			_voxel(_bank_pivot, Vector3(x_side * v * 1.45, -v * 0.25, v * zf),
				Vector3(v * 0.18, v * 0.4 * ll, v * 0.09), mat_dark)


func _build_lobster_core(v: float, lenf: float, mat_body: Material, mat_belly: Material,
		mat_eye: Material, mat_dark: Material) -> void:
	# Cephalothorax then a long STRAIGHT segmented abdomen — the crayfish /
	# lobster silhouette. abdomen_curl (default 0.1 for this plan) keeps it
	# extended rather than tucked.
	_voxel(_bank_pivot, Vector3(0, v * 0.3, -v * 0.9 * lenf),
		Vector3(v * 0.95, v * 0.9, v * 1.1 * lenf), mat_body)
	_voxel(_bank_pivot, Vector3(0, -v * 0.3, -v * 0.9 * lenf),
		Vector3(v * 0.75, v * 0.35, v * 0.9 * lenf), mat_belly)
	_voxel(_bank_pivot, Vector3(0, v * 0.25, 0),
		Vector3(v * 0.85, v * 0.8, v * 0.9 * lenf), mat_body)
	_build_eyes(v, -v * 1.25 * lenf, mat_eye, mat_dark)
	_tail_pivot = Node3D.new()
	_tail_pivot.name = "TailPivot"
	_tail_pivot.position = Vector3(0, v * 0.2, v * 0.5 * lenf)
	_tail_pivot.rotation.x = -abdomen_curl * 0.5
	_bank_pivot.add_child(_tail_pivot)
	for s in 3:
		var sz: float = v * (0.4 + s * 0.7) * lenf
		_voxel(_tail_pivot, Vector3(0, 0, sz),
			Vector3(v * (0.7 - s * 0.1), v * (0.55 - s * 0.08), v * 0.55 * lenf), mat_body)
	# Tail fan (telson) at the end.
	_voxel(_tail_pivot, Vector3(0, 0, v * 2.3 * lenf),
		Vector3(v * 0.9, v * 0.18, v * 0.4 * lenf), mat_dark)
	_build_claws(v, lenf)
	_build_legs(v, mat_dark)


func _build_mantis_core(v: float, lenf: float, mat_body: Material, mat_belly: Material,
		mat_eye: Material, mat_dark: Material) -> void:
	# Elongate strongly-segmented body with folded raptorial appendages under
	# the head and highly mobile stalked eyes.
	_voxel(_bank_pivot, Vector3(0, v * 0.3, -v * 1.0 * lenf),
		Vector3(v * 0.7, v * 0.7, v * 1.0 * lenf), mat_body)
	for s in 4:
		var sz: float = v * (-0.2 + s * 0.7) * lenf
		_voxel(_bank_pivot, Vector3(0, v * 0.28, sz),
			Vector3(v * (0.78 - s * 0.04), v * 0.5, v * 0.6 * lenf), mat_body)
		_voxel(_bank_pivot, Vector3(0, -v * 0.18, sz),
			Vector3(v * 0.6, v * 0.16, v * 0.55 * lenf), mat_belly)
	_build_eyes(v, -v * 1.4 * lenf, mat_eye, mat_dark)
	# Raptorial appendages folded under the head (the smasher/spearer arms).
	var rap_mat: Material = VoxelMat.fauna_color_carrier(base_color.darkened(0.25).lerp(accent_color, 0.2))
	for x_side in [-1.0, 1.0]:
		_voxel(_bank_pivot, Vector3(x_side * v * 0.32, -v * 0.15, -v * 1.35 * lenf),
			Vector3(v * 0.12, v * 0.12, v * 0.5 * lenf), rap_mat)
		_voxel(_bank_pivot, Vector3(x_side * v * 0.32, -v * 0.4, -v * 1.05 * lenf),
			Vector3(v * 0.1, v * 0.32, v * 0.12), rap_mat)
	# Tail fan as the pivot (egg cluster attaches here).
	_tail_pivot = Node3D.new()
	_tail_pivot.name = "TailPivot"
	_tail_pivot.position = Vector3(0, v * 0.25, v * 2.4 * lenf)
	_bank_pivot.add_child(_tail_pivot)
	_voxel(_tail_pivot, Vector3(0, 0, 0), Vector3(v * 0.8, v * 0.16, v * 0.4 * lenf), mat_dark)
	_build_legs(v, mat_dark)


# ---- Shared appendage builders ----

func _build_eyes(v: float, z: float, mat_eye: Material, mat_dark: Material) -> void:
	# Sessile eyes sit on the carapace (eye_stalk_length 0); raised eyes ride
	# short stalks (crab, mantis, some shrimp).
	var stalk: float = eye_stalk_length
	for x_side in [-1.0, 1.0]:
		if stalk > 0.05:
			_voxel(_bank_pivot,
				Vector3(x_side * v * 0.4, v * (0.3 + 0.27 * stalk), z - v * 0.05 * stalk),
				Vector3(v * 0.07, v * (0.2 + 0.45 * stalk), v * 0.07), mat_dark)
		_voxel(_bank_pivot,
			Vector3(x_side * v * 0.4, v * (0.3 + 0.55 * stalk), z - v * 0.1 * stalk),
			Vector3(v * 0.18, v * 0.18, v * 0.18), mat_eye)


func _build_claws(v: float, lenf: float) -> void:
	if claw_size <= 0.05:
		return
	var claw_mat: Material = VoxelMat.fauna_color_carrier(base_color.darkened(0.38).lerp(accent_color, 0.16))
	for side in [-1.0, 1.0]:
		# claw_asymmetry enlarges the right claw and shrinks the left — the
		# pistol shrimp / fiddler crab signature.
		var side_scale: float = 1.0
		if claw_asymmetry > 0.05:
			side_scale = (1.0 + claw_asymmetry * 0.9) if side > 0.0 \
				else maxf(0.25, 1.0 - claw_asymmetry * 0.7)
		var cs: float = claw_size * side_scale
		var claw_len: float = v * (0.40 + cs * 1.05) * lenf
		var claw_thick: float = v * (0.08 + cs * 0.10)
		_voxel(_bank_pivot, Vector3(side * v * 0.62, v * 0.02, -v * (1.18 + cs * 0.26)),
			Vector3(claw_thick, claw_thick, claw_len), claw_mat)
		_voxel(_bank_pivot, Vector3(side * v * 0.70, -v * 0.03, -v * (1.48 + cs * 0.30)),
			Vector3(claw_thick * 0.9, claw_thick * 0.85, claw_len * 0.48), claw_mat)


func _build_legs(v: float, mat_dark: Material) -> void:
	# Small dark voxels under the body (visual interest). leg_length_factor
	# scales their length.
	var ll: float = leg_length_factor
	for i in 3:
		var xside: float = 0.5 - randf() * 0.3
		var zoff: float = -0.4 + i * 0.4
		_voxel(_bank_pivot, Vector3(xside * v, -v * 0.4, zoff * v),
			Vector3(v * 0.1, v * 0.3 * ll, v * 0.1), mat_dark)
		_voxel(_bank_pivot, Vector3(-xside * v, -v * 0.4, zoff * v),
			Vector3(v * 0.1, v * 0.3 * ll, v * 0.1), mat_dark)


func _build_filter_fans(v: float) -> void:
	# Bamboo / wood shrimp hold feathery feeding fans forward of the mouth and
	# sweep the current. Two splayed fan clusters.
	var fan_mat: Material = VoxelMat.fauna_color_carrier(base_color.lightened(0.05))
	for side in [-1.0, 1.0]:
		for k in 3:
			var spread: float = lerpf(0.2, 0.6, float(k) / 2.0)
			_voxel(_bank_pivot,
				Vector3(side * v * spread, v * 0.05, -v * (1.25 + k * 0.18)),
				Vector3(v * 0.07, v * 0.12, v * 0.22), fan_mat)


func _build_shrimp_pattern(v: float, lenf: float) -> void:
	# 1 = bands (crystal/bee red-white rings), 2 = saddle spots (sexy/ghost),
	# 3 = lateral stripe (amano dashes). Continuous modulators reshape each so a
	# colony's markings drift wider / bolder / denser over generations.
	var pat_mat: Material = VoxelMat.fauna_color_carrier(accent_color)
	var sizem: float = 0.6 + pattern_scale * 0.8
	var thickm: float = 0.6 + pattern_intensity * 0.8
	match pattern_type:
		1:
			var bands: Array = ([-v * 0.8 * lenf, 0.0, v * 0.6 * lenf] if pattern_density < 0.6
				else [-v * 0.9 * lenf, -v * 0.3 * lenf, v * 0.2 * lenf, v * 0.7 * lenf])
			for z in bands:
				_voxel(_bank_pivot, Vector3(0, v * 0.55, float(z)),
					Vector3(v * 1.0 * sizem, v * 0.12 * thickm, v * 0.2 * sizem), pat_mat)
		2:
			var spots: Array = ([-0.6, 0.0, 0.6] if pattern_density < 0.6
				else [-0.7, -0.25, 0.2, 0.65])
			for zk in spots:
				_voxel(_bank_pivot, Vector3(0, v * 0.6, v * float(zk) * lenf),
					Vector3(v * 0.3 * sizem, v * 0.18 * sizem, v * 0.22 * sizem), pat_mat)
		3:
			for x_side in [-1.0, 1.0]:
				_voxel(_bank_pivot, Vector3(x_side * v * 0.45, v * 0.2, 0),
					Vector3(v * 0.12 * thickm, v * 0.18 * sizem, v * 1.6 * lenf), pat_mat)


func _voxel(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	if _voxel_builder == null:
		_voxel_builder = FaunaVoxelBuilder.new()
	_voxel_builder.add_voxel(parent, pos, size, mat)


func _is_shelter_plant(p: Plant) -> bool:
	if p == null or not is_instance_valid(p):
		return false
	if not (p is Coral):
		return false
	var form: String = String(p.get("coral_form"))
	return form == "anemone" or form == "sponge" \
		or form == "sponge_fresh" or form == "hydra_fresh"


func _pick_shelter_plant(plants: Array) -> Plant:
	var candidates: Array = []
	var best_score: float = INF
	for p in _nearby_plants(plants, SHELTER_SCAN_RADIUS):
		if not (p is Plant):
			continue
		var pl: Plant = p
		if not _is_shelter_plant(pl):
			continue
		var d2: float = pl.global_position.distance_squared_to(position)
		if d2 > SHELTER_SCAN_RADIUS * SHELTER_SCAN_RADIUS:
			continue
		var score: float = d2 - float(pl.biomass()) * 0.02
		if score < best_score:
			best_score = score
		candidates.append({"plant": pl, "score": score})
	if candidates.is_empty():
		return null
	# Don't send every fleeing shrimp to the same anemone — pick among near-ties.
	var cutoff: float = best_score + 0.8
	var viable: Array = []
	for c in candidates:
		if float((c as Dictionary).get("score", INF)) <= cutoff:
			viable.append(c)
	var pick: Dictionary = viable[int(get_instance_id()) % viable.size()] as Dictionary
	return pick.get("plant", null) as Plant


func _nearby_plants(plants: Array, radius: float) -> Array:
	if sim != null and sim.has_method("query_plants_in_radius"):
		return sim.query_plants_in_radius(position, radius)
	return plants


func _nearby_algae(algae_array: Array, radius: float) -> Array:
	if sim != null and sim.has_method("query_algae_in_radius"):
		return sim.query_algae_in_radius(position, radius)
	return algae_array


func _note_cleaning_familiarity(client: Node3D) -> void:
	if client == null or not is_instance_valid(client):
		return
	var cid: String = String(client.get("id")) if client.get("id") != null else ""
	if cid == "":
		return
	clean_clients[cid] = clampf(float(clean_clients.get(cid, 0.0)) + 0.14, 0.0, 1.0)
	if client is Fish:
		var ff: Fish = client as Fish
		ff.cleaner_familiarity[id] = clampf(float(ff.cleaner_familiarity.get(id, 0.0)) + 0.14, 0.0, 1.0)


func _nearby_fish(radius_sq: float) -> Array:
	if sim != null and sim.has_method("query_fish_in_radius"):
		return sim.query_fish_in_radius(position, radius_sq)
	return sim.fish if sim != null else []


# ---- Brain (10 Hz tick) ----

func tick(dt: float, plants: Array, algae_array: Array, waste: Array, _fry_array: Array, baby_snails: Array,
		  neighbors: Array, world_bounds: AABB) -> Dictionary:
	var events: Dictionary = {}

	# Dying shrimp are inert — no behavior, no events. _process handles
	# the sinking + fading animation and queue_free.
	if _dying:
		return events

	_prev_target_velocity = _target_velocity

	age += dt
	hunger = clampf(hunger + dt * 0.011, 0.0, 1.0)
	energy = clampf(energy - dt * 0.004, 0.0, 1.0)
	breed_cooldown = maxf(0.0, breed_cooldown - dt)
	shelter_bonus = maxf(0.0, shelter_bonus - dt * 0.35)
	if _shelter_target != null and (not is_instance_valid(_shelter_target) \
			or _shelter_target.biomass() <= 0):
		_shelter_target = null

	# Gravidity: if carrying eggs, count down and release fry when ready.
	if is_gravid:
		gravid_timer += dt
		if gravid_timer >= GRAVIDITY_DURATION:
			events["release_fry"] = gravid_partner_genome
			is_gravid = false
			gravid_timer = 0.0
			gravid_partner_genome = {}

	# Molting (adults only - fry are still growing into their first shell).
	if maturity == MATURITY_ADULT:
		_molt_timer = maxf(0.0, _molt_timer - dt)
		if _molt_timer <= 0.0:
			_molt_timer = randf_range(MOLT_INTERVAL_MIN, MOLT_INTERVAL_MAX)
			_molt_flash = 1.0
			_spawn_exuvia()
			# Drop the exuvia at substrate as a small KIND_SHRIMP waste so
			# snails / detritivores can graze it. sim_driver routes
			# waste_at via actor_kind to the right WasteParticle kind.
			events["waste_at"] = Vector3(position.x,
				substrate_top_y + 0.04, position.z)
			events["waste_amount"] = 0.05

	_update_maturity()

	# Death conditions.
	if maturity == MATURITY_SENESCENT and age >= max_age_s * 1.1:
		events["die"] = true
		return events
	if hunger >= 1.0 and energy < 0.1:
		events["die"] = true
		return events

	var target_velocity := Vector3.ZERO
	current_mode = Mode.WANDER

	# Tier 1: wall avoidance always adds.
	target_velocity += _wall_avoid(world_bounds) * 1.5
	# Soft intersection-fiction steering: avoid clipping through nearby shrimp,
	# hardscape cubes, and dense plant anchors.
	target_velocity += _neighbor_clearance_push(neighbors) * 1.1
	target_velocity += _plant_clearance_push(plants) * 0.9
	target_velocity += _hardscape_clearance_push() * 1.0

	# Tier 1.5: anti-predator sheltering. Under nearby fish-predator pressure
	# shrimp run for anemone/sponge/hydra structure and hunker down in cover.
	var predator_pressure: float = 0.0
	if sim != null:
		for f in _nearby_fish(3.4 * 3.4):
			if not is_instance_valid(f):
				continue
			var species_v: Variant = f.get("species")
			var predatory: bool = not not f.get("shrimp_predator") \
				or String(species_v if species_v != null else "") == "betta"
			if not predatory:
				continue
			var d2f: float = f.global_position.distance_squared_to(position)
			if d2f > 3.4 * 3.4:
				continue
			var p: float = clampf(1.0 - sqrt(d2f) / 3.4, 0.0, 1.0)
			predator_pressure = maxf(predator_pressure, p)
	if predator_pressure > 0.08 and hunger < 0.86:
		if _shelter_target == null:
			_shelter_target = _pick_shelter_plant(plants)
		if _shelter_target != null:
			current_mode = Mode.REST
			var shelter_pos: Vector3 = _shelter_target.global_position
			shelter_pos.y = _shelter_target.top_world_y() - 0.12
			var ring: float = _instance_yaw()
			shelter_pos += Vector3(cos(ring), 0.0, sin(ring)) * 0.34
			var to_cover: Vector3 = shelter_pos - position
			if to_cover.length() < 0.55:
				shelter_bonus = maxf(shelter_bonus, 0.45 + predator_pressure * 0.45)
				target_velocity *= 0.30
			else:
				shelter_bonus = maxf(shelter_bonus, 0.22 + predator_pressure * 0.30)
				target_velocity += to_cover.normalized() * max_speed * 1.25
			_apply_target(target_velocity)
			return events

	# Tier 2: already paired - keep courting.
	if partner != null:
		if not is_instance_valid(partner) or partner.maturity != MATURITY_ADULT:
			partner = null
			court_timer = 0.0
		elif hunger > 0.75 or energy < 0.2:
			# CRITICAL HUNGER / EXHAUSTION ESCAPE.
			# Without this, a paired shrimp returned events at the bottom of
			# this branch on every tick — it couldn't break off to forage no
			# matter how starving it got. Pairs of starving adults could
			# starve to death together rather than abandon courtship. Here
			# we cut both partner-links cleanly and fall through to the
			# foraging tiers below.
			if is_instance_valid(partner):
				partner.partner = null
				partner.court_timer = 0.0
			partner = null
			court_timer = 0.0
		else:
			current_mode = Mode.COURT
			var to_p: Vector3 = partner.position - position
			var dist: float = to_p.length()
			# Walk alongside on substrate.
			var side := to_p.cross(Vector3.UP).normalized() * 0.25
			var ct: Vector3 = partner.position + side
			target_velocity += (ct - position).normalized() * max_speed * 0.7
			court_timer += dt
			if dist < 0.8 and court_timer >= COURT_DURATION:
				# Pick the female of the pair to become gravid. We compute
				# the offspring genome NOW (combining both parents) and stash
				# it on the female to release as fry once gravidity completes.
				var female: Shrimp = self if sex == 1 else partner
				var male: Shrimp = partner if sex == 1 else self
				female.is_gravid = true
				female.gravid_timer = 0.0
				female.gravid_partner_genome = female.produce_offspring_genome(male)
				breed_cooldown = 60.0
				energy = maxf(0.0, energy - 0.30)
				partner.breed_cooldown = 60.0
				partner.energy = maxf(0.0, partner.energy - 0.30)
				breed_count += 1
				partner.breed_count += 1
				if not bio.is_empty():
					bio["offspring"] = int(bio.get("offspring", 0)) + 1
				if partner != null and not partner.bio.is_empty():
					partner.bio["offspring"] = int(partner.bio.get("offspring", 0)) + 1
				partner.partner = null
				partner = null
				court_timer = 0.0
			_apply_target(target_velocity)
			return events

	# Tier 2.4: CLEANING STATION (cleaner-shrimp only). Real Lysmata
	# amboinensis set up "cleaning stations" - a fixed perch where fish
	# queue up to be cleaned of parasites and dead tissue. We approximate:
	# the shrimp finds the nearest fish with elevated stress within
	# CLEAN_RADIUS, walks toward it, then holds position for
	# CLEAN_HOLD_DURATION seconds. During the hold, the fish's stress
	# drops; the shrimp gains a small food reward. Cooldown prevents
	# the shrimp from chaining clean → clean → clean forever.
	_clean_cooldown = maxf(0.0, _clean_cooldown - dt)
	if is_cleaner and maturity != MATURITY_FRY and _clean_cooldown <= 0.0 \
			and hunger > 0.2 and sim != null:
		# Validate existing target.
		if _clean_target != null \
				and (not is_instance_valid(_clean_target)
					or _clean_target.position.distance_squared_to(position)
						> CLEAN_RADIUS * CLEAN_RADIUS * 4.0):
			_clean_target = null
			_clean_hold = 0.0
		# Find a target if we don't have one.
		if _clean_target == null:
			var best: Node3D = null
			var best_score: float = 0.45    # require min stress to bother
			for f in _nearby_fish(CLEAN_RADIUS * CLEAN_RADIUS):
				if not is_instance_valid(f) or f.maturity == Fish.MATURITY_FRY:
					continue
				var d2: float = f.position.distance_squared_to(position)
				if d2 > CLEAN_RADIUS * CLEAN_RADIUS:
					continue
				# Score = stress level. Highest-stress fish in range wins.
				var s: float = float(f.stress)
				var fam: float = float(clean_clients.get(String(f.id), 0.0))
				s += fam * 0.35
				if s > best_score:
					best_score = s
					best = f
			_clean_target = best
		if _clean_target != null and is_instance_valid(_clean_target):
			current_mode = Mode.CLEAN
			var to_t: Vector3 = (_clean_target as Node3D).position - position
			var dist: float = to_t.length()
			if dist > 0.35:
				# Approach the fish.
				target_velocity += to_t.normalized() * max_speed * 0.5
			else:
				# At the station - hold position, perform the clean.
				_clean_hold += dt
				# Fish stress drops + small hunger reward for the shrimp.
				if "stress" in _clean_target:
					_clean_target.stress = maxf(0.0,
						float(_clean_target.stress) - dt * 0.20)
				hunger = maxf(0.0, hunger - dt * 0.08)
				if _clean_hold >= CLEAN_HOLD_DURATION:
					_note_cleaning_familiarity(_clean_target)
					_clean_hold = 0.0
					_clean_target = null
					_clean_cooldown = CLEAN_COOLDOWN
			_apply_target(target_velocity)
			return events

	# Tier 2.5: CANNIBALISM. Only kicks in when the population is crowded
	# (>=22 shrimp). Below that, adults spare the fry so the colony can
	# build up. Above the threshold, hungry adults will eat young to keep
	# numbers in check - real cherry-shrimp self-thin this way.
	var shrimp_pop: int = sim.shrimp.size() if sim != null else 0
	if maturity == MATURITY_ADULT and hunger > 0.5 and shrimp_pop >= 22 \
			and randf() < 0.08 and sim != null:
		var claw_reach: float = 0.30 + claw_size * 0.12
		var fry_prey: Shrimp = null
		var best_d2: float = 1.0
		for s in sim.shrimp:
			if not is_instance_valid(s) or s == self:
				continue
			if s.maturity != MATURITY_FRY:
				continue
			# Cannibalism more likely when crowded.
			var d2: float = s.position.distance_squared_to(position)
			if d2 < best_d2:
				best_d2 = d2
				fry_prey = s
		if fry_prey != null:
			current_mode = Mode.HUNT
			var to_p: Vector3 = fry_prey.position - position
			if to_p.length() < claw_reach:
				events["kill_prey"] = fry_prey
				hunger = maxf(0.0, hunger - (0.35 + claw_size * 0.12))
				energy = minf(1.0, energy + 0.12)
				events["waste_at"] = position + Vector3(0, -0.05, 0)
				events["waste_amount"] = 0.10
			else:
				target_velocity += to_p.normalized() * max_speed * 1.2
				_apply_target(target_velocity)
				return events

	# Tier 3: rare predation on baby SNAILS only. Real shrimp don't usually
	# catch fish fry - they're too slow - so we leave fish-fry hunting out
	# of shrimp's repertoire entirely. Otherwise shrimp eat fish fry faster
	# than fish can recruit and the school crashes.
	if maturity == MATURITY_ADULT and hunger > 0.7 and randf() < 0.02:
		var claw_reach_snail: float = 0.40 + claw_size * 0.16
		var prey_pos: Vector3 = Vector3.INF
		var prey_ref: Node3D = null
		var best_d2: float = 1.2 * 1.2
		for s in baby_snails:
			if not is_instance_valid(s):
				continue
			var d2: float = (s as Node3D).global_position.distance_squared_to(position)
			if d2 < best_d2:
				best_d2 = d2
				prey_pos = (s as Node3D).global_position
				prey_ref = s
		if prey_ref != null:
			current_mode = Mode.HUNT
			var to_prey: Vector3 = prey_pos - position
			if to_prey.length() < claw_reach_snail:
				events["kill_prey"] = prey_ref
				hunger = maxf(0.0, hunger - (0.45 + claw_size * 0.10))
				energy = minf(1.0, energy + 0.15)
				events["waste_at"] = position + Vector3(0, -0.05, 0)
				events["waste_amount"] = 0.12
			else:
				target_velocity += to_prey.normalized() * max_speed * 1.3
				_apply_target(target_velocity)
				return events

	# Tier 4: seek breeding partner. Shrimp are happy to breed even when
	# moderately hungry as long as they have energy reserves. Crowding slows
	# reproduction — real colonies self-limit when the glass is full.
	if maturity == MATURITY_ADULT and breed_cooldown <= 0.0 and partner == null \
			and hunger < 0.6 and energy > 0.5 and _detritus_breed_ok():
		var colony_cap: int = 24
		if sim != null:
			var w: Node = sim.get_parent()
			if w != null and w.has_method("shrimp_carrying_capacity"):
				colony_cap = int(w.shrimp_carrying_capacity())
		var overcrowded: bool = sim != null and sim.shrimp.size() >= colony_cap
		if not overcrowded:
			var best_mate: Shrimp = null
			var best_score: float = -INF
			for n in neighbors:
				if not (n is Shrimp):
					continue
				var s: Shrimp = n
				if s == self or s.species != species:
					continue
				if s.sex == sex or s.maturity != MATURITY_ADULT \
						or s.breed_cooldown > 0.0:
					continue
				if s.partner != null and is_instance_valid(s.partner):
					continue
				if s.hunger > 0.6 or s.energy < 0.45:
					continue
				var d2: float = s.position.distance_squared_to(position)
				if d2 > 9.0:
					continue
				var score: float = -d2 * 0.55 + _mate_habitat_score(s) * 1.8 \
					+ clampf(s.growth_factor / MAX_GROWTH, 0.0, 1.0) * 0.9
				if score > best_score:
					best_score = score
					best_mate = s
			if best_mate != null:
				partner = best_mate
				best_mate.partner = self
				court_timer = 0.0
				best_mate.court_timer = 0.0

	# Tier 5: claim nearby waste. The actual eat is resolved by SimDriver.
	var best_w: WasteParticle = null
	var best_w_d2: float = 25.0
	var waste_near: Array = waste
	if sim != null and sim.has_method("query_waste_in_radius"):
		waste_near = sim.query_waste_in_radius(position, 5.0)
	for w in waste_near:
		if not is_instance_valid(w):
			continue
		var d2: float = (w as Node3D).global_position.distance_squared_to(position)
		var max_dist: float = 25.0 if w.kind == 3 else 4.0
		if d2 < max_dist and d2 < best_w_d2:
			best_w_d2 = d2
			best_w = w
	if best_w != null:
		var wpos: Vector3 = best_w.global_position
		var crowd_n: int = 0
		for n in neighbors:
			if not (n is Shrimp) or n == self:
				continue
			if (n as Shrimp).position.distance_squared_to(wpos) < 0.28 * 0.28:
				crowd_n += 1
		if crowd_n < 2:
			current_mode = Mode.FORAGE_WASTE
			var ring: float = _instance_yaw()
			var stand_off: Vector3 = Vector3(cos(ring), 0.0, sin(ring)) * 0.24
			var to_w: Vector3 = (wpos + stand_off) - position
			if to_w.length() < 0.3:
				events["eat_waste"] = best_w
				hunger = maxf(0.0, hunger - 0.30)
			else:
				target_velocity += to_w.normalized() * max_speed * 0.9
				_apply_target(target_velocity)
				return events

	# Tier 5.5: ALGAE - Shrimp are excellent algae eaters.
	if hunger > 0.2:
		var best_a: Node3D = null
		var best_a_d2: float = 4.0
		for a in _nearby_algae(algae_array, 2.0):
			if not is_instance_valid(a) or a.biomass() <= 0:
				continue
			var d2: float = a.global_position.distance_squared_to(position)
			if d2 < best_a_d2:
				best_a_d2 = d2
				best_a = a
		if best_a != null:
			current_mode = Mode.NIBBLE
			var to_a: Vector3 = best_a.global_position - position
			if to_a.length() < 0.4:
				var taken: int = best_a.nibble(2)
				if taken > 0:
					hunger = maxf(0.0, hunger - 0.25 * float(taken))
					energy = minf(1.0, energy + 0.08)
					events["waste_at"] = position + Vector3(0, -0.05, 0)
					events["waste_amount"] = 0.10 * float(taken)
			else:
				target_velocity += to_a.normalized() * max_speed * 1.0
				_apply_target(target_velocity)
				return events

	# Tier 5b: FLOATER ROOT AUFWUCHS (#33). Climb dangling roots before plants.
	if hunger > 0.35 and sim != null:
		var w_sh: Node = sim.get_parent()
		if w_sh != null and w_sh.has_method("query_floaters_in_radius"):
			var best_fp: FloatingPlant = null
			var best_fp_d2: float = 4.0
			for fp in w_sh.query_floaters_in_radius(position, 2.0):
				if not (fp is FloatingPlant) or fp.root_biofilm < 0.12:
					continue
				for rp in fp.root_world_positions():
					var d2r: float = (rp as Vector3).distance_squared_to(position)
					if d2r < best_fp_d2:
						best_fp_d2 = d2r
						best_fp = fp
			if best_fp != null:
				current_mode = Mode.NIBBLE
				var roots: Array = best_fp.root_world_positions()
				var tgt: Vector3 = roots[0] if roots.size() > 0 else best_fp.global_position
				if position.distance_squared_to(tgt) < 0.16:
					var grazed: float = minf(0.15, best_fp.root_biofilm)
					best_fp.root_biofilm = maxf(0.0, best_fp.root_biofilm - grazed)
					hunger = maxf(0.0, hunger - grazed * 1.2)
					energy = minf(1.0, energy + grazed * 0.4)
				else:
					target_velocity += (tgt - position).normalized() * max_speed * 0.9
					_apply_target(target_velocity)
					return events

	# Tier 6: PLANTS - Only if plants are growing well and algae/food is scarce.
	if hunger > 0.4:
		# Corals are fallback forage when detritus/algae are scarce.
		if hunger > 0.65:
			var best_coral: Plant = null
			var best_coral_d2: float = 6.0
			for p in _nearby_plants(plants, 2.5):
				if not is_instance_valid(p) or p.biomass() < 10:
					continue
				if p is Coral:
					var d2c: float = p.global_position.distance_squared_to(position)
					if d2c < best_coral_d2:
						best_coral_d2 = d2c
						best_coral = p
			if best_coral != null:
				current_mode = Mode.NIBBLE
				var coral_top: Vector3 = best_coral.global_position
				coral_top.y = best_coral.top_world_y()
				if coral_top.distance_squared_to(position) < 0.35 * 0.35:
					var ctaken: int = best_coral.nibble(1)
					if ctaken > 0:
						hunger = maxf(0.0, hunger - 0.20 * float(ctaken))
						energy = minf(1.0, energy + 0.05)
						events["waste_at"] = position + Vector3(0, -0.05, 0)
						events["waste_amount"] = 0.09 * float(ctaken)
						_apply_target(target_velocity)
						return events
				else:
					target_velocity += (coral_top - position).normalized() * max_speed * 1.0
					_apply_target(target_velocity)
					return events

		# First: a quick grazing pass for plants right next to us on the floor.
		for p in _nearby_plants(plants, 1.2):
			if not is_instance_valid(p) or p.biomass() < 15:
				continue
			if p.has_method("graze_detritus_fleck") and p.graze_detritus_fleck():
				current_mode = Mode.NIBBLE
				hunger = maxf(0.0, hunger - 0.14)
				energy = minf(1.0, energy + 0.03)
				_apply_target(target_velocity)
				return events
			var pp: Vector3 = p.global_position
			if absf(pp.y - position.y) > 0.6: continue   # only floor-level plants
			var d2: float = pp.distance_squared_to(position)
			if d2 < 0.35 * 0.35:
				var taken: int = p.nibble(1)
				if taken > 0:
					hunger = maxf(0.0, hunger - 0.22 * float(taken))
					energy = minf(1.0, energy + 0.04)
					events["waste_at"] = position + Vector3(0, -0.05, 0)
					events["waste_amount"] = 0.10 * float(taken)
					_apply_target(target_velocity)
					return events

		# Then: pick a tall plant to climb if we have no current target.
		if climb_target == null:
			var w_sh: Node = sim.get_parent() if sim != null else null
			if w_sh != null and w_sh.has_method("query_build_shelter_near") and hunger > 0.2:
				var ledge: Vector3 = w_sh.query_build_shelter_near(position, 2.6)
				if ledge != Vector3.ZERO and absf(ledge.y - position.y) < 1.2:
					target_velocity += (ledge - position).normalized() * max_speed * 0.65
			var best_p: Plant = null
			var best_p_d2: float = 12.0
			for p in plants:
				if not is_instance_valid(p) or p.biomass() < 15:
					continue
				var d2: float = p.global_position.distance_squared_to(position)
				if p.has_method("has_grazeable_flower") and p.has_grazeable_flower():
					d2 *= 0.4
				if d2 < best_p_d2:
					best_p_d2 = d2
					best_p = p
			if best_p != null:
				climb_target = best_p
				climb_remaining_time = CLIMB_GIVE_UP_TIME

	if climb_target != null:
		if not is_instance_valid(climb_target) or climb_target.biomass() <= 0:
			climb_target = null
		else:
			climb_remaining_time -= dt
			current_mode = Mode.CLIMB
			var top: Vector3 = climb_target.global_position
			if climb_target.has_method("graze_target_world_y"):
				top.y = climb_target.graze_target_world_y()
			else:
				top.y = climb_target.top_world_y()
			var to_top: Vector3 = top - position
			if to_top.length() < 0.45:
				current_mode = Mode.NIBBLE
				# Eat 2 voxels per visit - more visible chomp.
				var taken: int = climb_target.nibble(2)
				if taken > 0:
					hunger = maxf(0.0, hunger - 0.22 * float(taken))
					energy = minf(1.0, energy + 0.05)
					events["waste_at"] = position + Vector3(0, -0.05, 0)
					events["waste_amount"] = 0.10 * float(taken)
				climb_target = null
			else:
				target_velocity += to_top.normalized() * max_speed * 1.0
			if climb_remaining_time <= 0.0:
				climb_target = null

	# Default: wander on substrate.
	if current_mode == Mode.WANDER:
		# Cheap wander: drift along heading with mild randomness.
		var wander_dir: Vector3 = heading + Vector3(
			randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3)
		)
		wander_dir.y = 0.0
		target_velocity += wander_dir.normalized() * max_speed * 0.4

	# Night-time dampening - shrimp slow by day; inherit the night when fish sleep (#33).
	if sim != null:
		var dl: float = float(sim.daylight())
		var night_factor: float = 0.35 + 0.65 * dl
		if dl < 0.28 and sim.has_method("tank_mind_snapshot"):
			var asleep: float = float(sim.tank_mind_snapshot().get("asleep_fraction", 0.0))
			if asleep > 0.55:
				night_factor = 0.52 + 0.48 * dl
		target_velocity *= night_factor

	var mr := get_tree().get_first_node_in_group("music_reactive")
	if mr != null and mr.has_method("fauna_behavior_mods"):
		var mods: Dictionary = mr.fauna_behavior_mods(get_instance_id())
		var spd_mul: float = float(mods.get("speed", 1.0))
		target_velocity *= spd_mul
		if bool(mods.get("beat_dart", false)):
			target_velocity *= 1.45

	# Size growth from feeding (mirrors Fish.growth_factor logic).
	if maturity == MATURITY_ADULT:
		if hunger < 0.35:
			growth_factor = minf(growth_factor + 0.0007 * dt, MAX_GROWTH)
		elif hunger > 0.7:
			growth_factor = maxf(growth_factor - 0.0004 * dt, 0.7)

	_apply_target(target_velocity)
	return events


func _apply_target(t: Vector3) -> void:
	_target_velocity = _constrain_velocity_to_tank(t)


func _constrain_velocity_to_tank(vel: Vector3) -> Vector3:
	var w: Node = null
	if sim != null:
		w = sim.get_parent()
	return FaunaBoundary.constrain_velocity(w, global_position, vel, 0.32, 0.58, 0.38)


var _target_velocity: Vector3 = Vector3.ZERO
var _prev_target_velocity: Vector3 = Vector3.ZERO
var _visual_heading: Vector3 = Vector3(0.0, 0.0, -1.0)
var _was_camera_visible: bool = true
const VISUAL_TURN_CAP: float = 5.5


func _look_up_for_direction(d: Vector3) -> Vector3:
	if d.length_squared() < 1e-8:
		return Vector3.UP
	if absf(d.normalized().dot(Vector3.UP)) > 0.95:
		return Vector3.FORWARD
	return Vector3.UP


func _motion_substep(dt: float) -> void:
	if _hydro_profile.is_empty():
		_hydro_profile = Hydrodynamics.profile_for_locomotion("shrimp", 0.14)
	# Gravity-like pull when not climbing. Shrimp tend to stick to surfaces.
	if climb_target == null:
		_target_velocity.y -= 1.2 * dt
	var target_dir: Vector3 = heading
	var target_spd: float = 0.0
	var brain_target: Vector3 = _target_velocity
	if sim != null and sim.has_method("sim_tick_blend"):
		var blend: float = sim.sim_tick_blend()
		brain_target = _prev_target_velocity.lerp(_target_velocity, blend)
	if brain_target.length_squared() > 1e-4:
		target_spd = brain_target.length()
		target_dir = brain_target.normalized()
	target_spd *= _day_activity_mult()
	if target_spd > speed + 0.42 and target_spd > 0.5:
		_escape_remaining = maxf(_escape_remaining, 0.38)
	var constrained: Vector3 = _constrain_velocity_to_tank(target_dir * target_spd)
	if constrained.length_squared() > 1e-6:
		target_dir = constrained.normalized()
		target_spd = constrained.length()
	var angle: float = heading.angle_to(target_dir)
	if angle > 0.0005:
		var axis: Vector3 = heading.cross(target_dir)
		if axis.length_squared() < 1e-6:
			axis = Vector3.UP
		axis = axis.normalized()
		var turn: float = minf(max_turn_rate * dt, angle)
		heading = heading.rotated(axis, turn).normalized()
		if not heading.is_finite() or heading.length_squared() < 0.5:
			heading = Vector3(sin(_last_yaw), 0.0, -cos(_last_yaw))
	var w: Node = sim.get_parent() if sim != null else null
	var flow_vel: Vector3 = Vector3.ZERO
	if w != null and w.has_method("sample_flow"):
		flow_vel = w.sample_flow(global_position)
		target_spd *= Hydrodynamics.upstream_effort(flow_vel, heading)
	if _escape_remaining > 0.0:
		_escape_remaining = maxf(0.0, _escape_remaining - dt)
		heading = (-target_dir if target_dir.length_squared() > 1e-6 else -heading).normalized()
		speed += 2.8 * dt
		target_spd = maxf(target_spd, max_speed * 1.15)
	else:
		var stroke: float = Hydrodynamics.stroke_thrust(
			_swim_phase, _hydro_profile, speed, target_spd, max_speed)
		if climb_target != null or global_position.y > substrate_top_y + 0.35:
			stroke += maxf(0.0, sin(_swim_phase * 2.35)) * 0.18
		var drag_k: float = Hydrodynamics.drag_coeff(0.14, _hydro_profile)
		speed = Hydrodynamics.integrate_speed(
			speed, target_spd, stroke, drag_k, 3.0, dt, true)
	if flow_vel.length_squared() > 1e-6:
		global_position += flow_vel * dt * Hydrodynamics.flow_coupling(0.14)
	# Substrate grip — planted feet when walking, not tail-flipping (#21).
	if climb_target == null and _escape_remaining <= 0.0 \
			and global_position.y <= substrate_top_y + 0.22:
		global_position.y = substrate_top_y + 0.08
		if target_spd < 0.4:
			speed = minf(speed, target_spd + 0.05)
	velocity = heading * speed
	position += velocity * dt
	if w != null and w.has_method("clamp_xyz_in_tank"):
		global_position = w.clamp_xyz_in_tank(global_position, 0.20, 0.14)
	if speed > 0.55 and w != null:
		if w.has_method("deposit_wake"):
			w.deposit_wake(global_position, heading * speed, 0.14)
		if w.has_method("brush_plants_near") and randf() < dt * 0.5:
			w.brush_plants_near(global_position, heading, speed, 0.55)
		if w.has_method("spawn_creature_substrate_dust") and speed > 0.65 and randf() < dt * 0.35:
			w.spawn_creature_substrate_dust(global_position, 1.1)
	# Same non-finite guard as fish.gd — look_at(NaN) corrupts the basis and
	# every child VoxelBatch instance floods instance_set_transform errors.
	if not global_position.is_finite() or not transform.is_finite():
		push_warning("[Shrimp] non-finite motion transform detected; recovering from last yaw.")
		if not global_position.is_finite():
			var safe_y: float = substrate_top_y + 0.1
			var gp_bad: Vector3 = global_position
			var sx: float = gp_bad.x if is_finite(gp_bad.x) else 0.0
			var sz: float = gp_bad.z if is_finite(gp_bad.z) else 0.0
			global_position = Vector3(sx, safe_y, sz)
		heading = Vector3(sin(_last_yaw), 0.0, -cos(_last_yaw))
		var recover_d: Vector3 = heading
		if recover_d.is_finite():
			var up_r: Vector3 = _look_up_for_direction(recover_d)
			transform.basis = Basis.looking_at(recover_d, up_r)
	if speed > 0.04 and heading.length_squared() > 1e-4:
		var d: Vector3 = _visual_heading_for_display(dt, heading)
		if d.is_finite():
			var up: Vector3 = _look_up_for_direction(d)
			look_at(position + d, up)
			if not transform.is_finite():
				transform.basis = Basis.looking_at(d, up)
	var current_yaw: float = atan2(heading.x, -heading.z)
	var yaw_diff: float = wrapf(current_yaw - _last_yaw, -PI, PI)
	_last_yaw = current_yaw
	var yaw_rate: float = yaw_diff / maxf(dt, 0.0001)
	var bank_target: float = clampf(-yaw_rate * 0.2, -0.4, 0.4)
	_bank = lerpf(_bank, bank_target, clampf(dt * 5.0, 0.0, 1.0))
	if _bank_pivot != null:
		_bank_pivot.rotation.z = _bank


func _visual_heading_for_display(dt: float, desired: Vector3) -> Vector3:
	if desired.length_squared() < 1e-6:
		return _visual_heading
	if _visual_heading.length_squared() < 1e-6:
		_visual_heading = desired
		return _visual_heading
	var angle: float = _visual_heading.angle_to(desired)
	if angle < 0.0003:
		_visual_heading = desired
		return _visual_heading
	var axis: Vector3 = _visual_heading.cross(desired)
	if axis.length_squared() < 1e-6:
		_visual_heading = desired
		return _visual_heading
	axis = axis.normalized()
	var step: float = minf(VISUAL_TURN_CAP * dt, angle)
	_visual_heading = _visual_heading.rotated(axis, step).normalized()
	return _visual_heading


func _snap_motion_interp() -> void:
	_prev_target_velocity = _target_velocity
	if heading.length_squared() > 1e-6:
		_visual_heading = heading


func _update_visibility_interp() -> void:
	if sim == null or not sim.has_method("is_creature_visible_to_camera"):
		return
	var vis: bool = sim.is_creature_visible_to_camera(self)
	if vis != _was_camera_visible:
		_snap_motion_interp()
	_was_camera_visible = vis


# ---- Physics + animation (render rate) ----

func _process(dt: float) -> void:
	if sim != null:
		dt *= sim.time_scale
		if dt <= 0.0:
			return

	# Death sequence — tilts, sinks, fades over DEATH_DURATION before
	# the sim_driver actually frees us. Skips the normal motion pipeline.
	if _dying:
		_animate_death(dt)
		return

	_update_visibility_interp()

	# Substep at high time_scale — same stability rationale as fish.gd.
	var n_steps: int = clampi(int(ceil(minf(dt, 0.32) / maxf(0.035 / clampf(speed / maxf(max_speed, 0.12), 0.5, 1.4), 0.022))), 1, 7)
	var sub_dt: float = dt / float(n_steps)
	for _step_i in n_steps:
		_motion_substep(sub_dt)

	var do_body_anim: bool = sim == null or not sim.has_method("is_creature_visible_to_camera") \
		or sim.is_creature_visible_to_camera(self)
	if not do_body_anim:
		return

	# Animation: tail flicks + pleopod paddle + antennae twitch + walking bob.
	_swim_phase += dt * (3.0 + speed * 4.0)
	_pleopod_phase += dt * (4.5 + speed * 5.0)
	# Tail-flick amplitude scales sharply with speed. A calm shrimp barely
	# twitches its tail; a spooked or fleeing shrimp executes the classic
	# big rapid "tail flip" escape - real shrimp use this to shoot
	# backwards away from predators.
	var tail_amp: float = 0.12 + minf(speed * 0.45, 0.45)
	if _escape_remaining > 0.0:
		tail_amp = 0.65 + _escape_remaining * 0.4
	if _tail_pivot != null:
		_tail_pivot.rotation.x = sin(_swim_phase) * tail_amp
	if _antenna_pivot != null:
		for i in _antenna_seg_pivots.size():
			var seg: Node3D = _antenna_seg_pivots[i] as Node3D
			if not is_instance_valid(seg):
				continue
			var lag: float = float(i) * 0.38
			var damp: float = 1.0 / (1.0 + float(i) * 0.45)
			seg.rotation.y = sin(_swim_phase * 1.7 + lag) * 0.24 * damp
			seg.rotation.x = sin(_swim_phase * 2.1 + lag * 1.2) * 0.14 * damp
			seg.rotation.z = sin(_swim_phase * 2.8 + lag * 0.8) * 0.07 * damp
	# Walking bob: a small vertical pulse at twice the tail frequency
	# mimics the alternating-leg gait of crawling. Suppressed at very
	# low speeds (resting) and at high speeds (the shrimp is tail-
	# flipping above substrate, legs aren't doing the work).
	if _bank_pivot != null and _molt_flash <= 0.0:
		var walk_factor: float = clampf(speed * 5.0, 0.0, 1.0) \
			* clampf(1.0 - speed * 0.55, 0.0, 1.0)
		_bank_pivot.position.y = sin(_swim_phase * 2.0) * 0.014 * walk_factor
		if current_mode == Mode.NIBBLE or current_mode == Mode.FORAGE_WASTE:
			var grab: float = 0.5 + 0.5 * sin(_swim_phase * 4.4)
			_bank_pivot.rotation.x = lerpf(_bank_pivot.rotation.x, -0.38 * grab, dt * 7.0)
			_bank_pivot.position.z = lerpf(_bank_pivot.position.z, -0.05 * grab, dt * 5.0)

	# Egg-cluster visibility: visible only during the gravid window.
	if _egg_cluster != null and _egg_cluster.visible != is_gravid:
		_egg_cluster.visible = is_gravid

	# Molt visual: brief size pop on freshly-molted shrimp. _molt_flash is
	# set to 1.0 in tick() when a molt happens and decays here. We apply
	# it via the bank pivot's scale so it stacks cleanly with banking.
	if _molt_flash > 0.0:
		_molt_flash = maxf(0.0, _molt_flash - dt * 1.2)
		if _bank_pivot != null:
			var pop: float = 1.0 + _molt_flash * 0.10
			_bank_pivot.scale = Vector3(pop, pop, pop)
	elif _bank_pivot != null and _bank_pivot.scale != Vector3.ONE:
		_bank_pivot.scale = Vector3.ONE

	# Maturity scale lerps AND growth_factor so well-fed shrimp visibly bulk.
	var scale_target: float = _maturity_scale() * growth_factor
	var mr_s := get_tree().get_first_node_in_group("music_reactive")
	if mr_s != null and mr_s.has_method("fauna_behavior_mods"):
		scale_target *= float(mr_s.fauna_behavior_mods(get_instance_id()).get("scale", 1.0))
	scale = scale.lerp(Vector3.ONE * scale_target, dt * 0.5)

	# Berried-female visual: small yellow egg cluster under the tail.
	if is_gravid and _egg_cluster == null:
		_spawn_egg_cluster()
	elif not is_gravid and _egg_cluster != null:
		_egg_cluster.queue_free()
		_egg_cluster = null


# Day/night activity multiplier. Shrimp are crepuscular — they peak at the
# dawn / dusk transitions and ebb at deep midday and midnight. We model
# this as 1 - |daylight - 0.5|*0.9 so the curve has shallow dips at the
# extremes and a soft plateau through the transition zones. Output range
# roughly [0.55, 1.0]. SimDriver.daylight() returns the 0..1 bell.
func _day_activity_mult() -> float:
	if sim == null:
		return 1.0
	var daylight: float = float(sim.daylight())
	return clampf(1.0 - absf(daylight - 0.5) * 0.9, 0.55, 1.0)


# Detritus-coupled breeding (#36): a scavenger colony booms when there's
# detritus + biofilm to eat and stalls when the tank is clean, so the shrimp
# population self-regulates around the available food instead of a flat timer.
func _detritus_breed_ok() -> bool:
	if sim == null:
		return true
	var waste_n: int = sim.waste.size()
	var bio_amt: float = 0.0
	var w: Node = sim.get_parent()
	if w != null and w.get("biofilm_progress") != null:
		bio_amt = float(w.biofilm_progress)
	var food: float = clampf(float(waste_n) / 30.0 + bio_amt, 0.0, 1.0)
	return randf() < clampf(0.30 + food * 0.70, 0.0, 1.0)


func _mate_habitat_score(s: Shrimp) -> float:
	if sim == null:
		return 0.5
	var world: Node = sim.get_parent()
	if world == null or not world.has_method("habitat_profile_at"):
		return 0.5
	var hv: Variant = world.habitat_profile_at(s.position)
	if not (hv is Dictionary):
		return 0.5
	var h: Dictionary = hv
	var cover: float = float(h.get("cover", 0.0))
	var edge: float = float(h.get("edge", 0.5))
	var substrate_local: float = float(h.get("substrate_local", 0.5))
	var score: float = 0.35 + cover * 0.35 + substrate_local * 0.25
	if edge < 0.3:
		score += 0.08
	return clampf(score, 0.0, 1.0)


# Triggers the death-animation state. Called by SimDriver when a die event
# fires (old age / starvation). Idempotent so multiple die events in the
# same tick don't reset the timer.
func start_dying() -> void:
	if _dying:
		return
	_dying = true
	_dying_timer = DEATH_DURATION
	_dying_wall_start_unix = int(Time.get_unix_time_from_system())
	_target_velocity = Vector3.ZERO
	speed = 0.0


# Death pose: rolls onto its side + curls the tail, drifts to the
# substrate, shrinks toward zero, then frees and drops a mulm waste
# particle. We shrink the bank pivot's scale rather than fading alpha —
# see fish.gd's matching _animate_death for the reason (Node3D has no
# `modulate`, and per-voxel transparency would be heavy for a 2.5-second
# anim). 2.5s here vs the fish's 3.5s because tiny shrimp on their side
# start to look stuck if they linger.
func _animate_death(dt: float) -> void:
	# Wall-clock safety net — see fish.gd. Force-completes if real time
	# elapsed since dying-start exceeds the cap, regardless of dt.
	if _dying_wall_start_unix > 0:
		var elapsed: int = int(Time.get_unix_time_from_system()) - _dying_wall_start_unix
		if elapsed >= DEATH_WALL_CLOCK_MAX:
			_dying_timer = 0.0
	# dt floor: ensure progress even when dt is starved.
	var dt_use: float = maxf(dt, 0.001)
	_dying_timer = maxf(0.0, _dying_timer - dt_use)
	var progress: float = clampf(1.0 - (_dying_timer / DEATH_DURATION), 0.0, 1.0)
	# Curl + tilt the body. Shrimp die-pose is curled tail-under, on their
	# side. We use the bank pivot's z-rotation for the side flop and the
	# tail pivot for a slight curl.
	if _bank_pivot != null:
		var tilt_target: float = PI * 0.5
		var tilt_speed: float = clampf(dt * 2.0, 0.0, 1.0)
		_bank_pivot.rotation.z = lerpf(_bank_pivot.rotation.z, tilt_target, tilt_speed)
		# Withering shrink — see fish.gd notes.
		var shrink: float = lerpf(1.0, 0.15, progress)
		_bank_pivot.scale = Vector3(shrink, shrink, shrink)
	if _tail_pivot != null:
		var curl_target: float = -0.7
		var curl_speed: float = clampf(dt * 1.6, 0.0, 1.0)
		_tail_pivot.rotation.x = lerpf(_tail_pivot.rotation.x, curl_target, curl_speed)
	# Drift to the substrate. Shrimp are negatively buoyant when dead.
	position.y -= 0.12 * dt
	if sim != null and position.y < substrate_top_y + 0.04:
		position.y = substrate_top_y + 0.04
	# End of sequence — drop the mulm and free.
	if _dying_timer <= 0.0:
		if sim != null and sim.has_method("_spawn_waste"):
			sim._spawn_waste(position, 0.25, WasteParticle.KIND_SHRIMP)
		queue_free()


func _spawn_egg_cluster() -> void:
	if _bank_pivot == null:
		return
	_egg_cluster = Node3D.new()
	_egg_cluster.name = "EggCluster"
	# Position under the tail (which sits at z = 0.6v ish in tail_pivot).
	_egg_cluster.position = Vector3(0, -adult_voxel_scale * 0.45, adult_voxel_scale * 0.4)
	_bank_pivot.add_child(_egg_cluster)
	var v: float = adult_voxel_scale
	var c_egg := Color8(245, 220, 110)
	var c_egg_dark := Color8(220, 190, 80)
	var positions: Array[Vector3] = [
		Vector3(0, 0, 0),
		Vector3(v * 0.18, 0, 0),
		Vector3(-v * 0.18, 0, 0),
		Vector3(0, 0, v * 0.18),
		Vector3(v * 0.10, v * 0.05, v * 0.10),
	]
	for i in positions.size():
		var mi := MeshInstance3D.new()
		mi.mesh = VoxelMat.get_box(Vector3(0.12, 0.12, 0.12))
		mi.position = positions[i]
		var egg_col: Color = c_egg if (i & 1) == 0 else c_egg_dark
		mi.material_override = VoxelMat.make_translucent(
			Color(egg_col.r, egg_col.g, egg_col.b, 0.62))
		_egg_cluster.add_child(mi)


func _build_antenna_chain(parent: Node3D, side: float, v: float, total_len: float,
		mat: Material) -> void:
	var segs: int = 3
	var pivot: Node3D = parent
	var seg_len: float = v * total_len / float(segs)
	for i in segs:
		var seg_pivot := Node3D.new()
		seg_pivot.name = "AntSeg%d" % i
		if i == 0:
			seg_pivot.position = Vector3(side * v * 0.2, v * 0.1, 0.0)
		else:
			seg_pivot.position = Vector3(0.0, 0.0, -seg_len * 0.82)
		pivot.add_child(seg_pivot)
		_voxel(seg_pivot, Vector3(0.0, 0.0, -seg_len * 0.42),
			Vector3(v * 0.05, v * 0.05, seg_len), mat)
		_antenna_seg_pivots.append(seg_pivot)
		pivot = seg_pivot


func _spawn_exuvia() -> void:
	var host: Node3D = get_parent() as Node3D
	if host == null:
		return
	var root := Node3D.new()
	root.name = "Exuvia"
	root.position = Vector3(position.x, substrate_top_y + 0.025, position.z)
	root.rotation.y = rotation.y
	host.add_child(root)
	var v: float = adult_voxel_scale * _maturity_scale() * growth_factor
	var ghost := Color(base_color.r, base_color.g, base_color.b, 0.32)
	var mat: ShaderMaterial = VoxelMat.make_translucent(ghost)
	var parts: Array = [
		[Vector3(0, v * 0.3, -v * 0.5), Vector3(v * 0.85, v * 0.85, v * 0.75)],
		[Vector3(0, v * 0.3, 0), Vector3(v * 1.0, v * 0.95, v * 0.8)],
		[Vector3(0, v * 0.35, v * 0.55), Vector3(v * 0.7, v * 0.55, v * 0.5)],
		[Vector3(0, v * 0.55, v * 0.95), Vector3(v * 0.55, v * 0.18, v * 0.22)],
	]
	for p in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = VoxelMat.get_box(p[1])
		mi.position = p[0]
		mi.material_override = mat.duplicate()
		root.add_child(mi)
	const FADE_S: float = 28.0
	var tw := create_tween()
	tw.set_parallel(true)
	for c in root.get_children():
		if c is MeshInstance3D:
			var sm: ShaderMaterial = (c as MeshInstance3D).material_override as ShaderMaterial
			if sm != null:
				var end_col: Color = Color(ghost.r, ghost.g, ghost.b, 0.0)
				tw.tween_property(sm, "shader_parameter/albedo", end_col, FADE_S)
	get_tree().create_timer(FADE_S + 0.5).timeout.connect(root.queue_free)


func _update_maturity() -> void:
	var t: float = age / max_age_s
	if t < 0.1:
		maturity = MATURITY_FRY
	elif t < 0.3:
		maturity = MATURITY_JUVENILE
	elif t < 0.85:
		maturity = MATURITY_ADULT
	else:
		maturity = MATURITY_SENESCENT


func _wall_avoid(_b: AABB) -> Vector3:
	var push := Vector3.ZERO
	var w: Node = null
	if sim != null:
		w = sim.get_parent()
	if w != null and w.has_method("tank_lateral_boundary_info"):
		var body_m: float = 0.38
		var info: Dictionary = w.tank_lateral_boundary_info(global_position, body_m * 0.75 + 0.18)
		var clearance: float = float(info.get("clearance", 99.0))
		var inward: Vector3 = info.get("inward", Vector3.ZERO)
		if inward.length_squared() > 1e-6:
			var repel_dist: float = body_m * 2.2 + 0.35
			if clearance < repel_dist:
				var t: float = 1.0 - clampf(clearance / repel_dist, 0.0, 1.0)
				push += inward * t * t * 0.95
		if w.has_method("tank_vertical_boundary_info"):
			var vert: Dictionary = w.tank_vertical_boundary_info(global_position, 0.22)
			if bool(vert.get("active", false)):
				var v_clear: float = float(vert.get("clearance", 99.0))
				var v_in: Vector3 = vert.get("inward", Vector3.ZERO)
				if v_in.length_squared() > 1e-6 and v_clear < 0.38:
					var vt: float = 1.0 - clampf(v_clear / 0.38, 0.0, 1.0)
					push += v_in * vt * vt * 0.7
		if push.length_squared() > 1e-6:
			return push
	return Vector3.ZERO


func _instance_yaw() -> float:
	return float(get_instance_id() % 1024) / 1024.0 * TAU


func _neighbor_clearance_push(neighbors: Array) -> Vector3:
	const SHRIMP_SPACE: float = 0.21
	var r2: float = SHRIMP_SPACE * SHRIMP_SPACE
	var push := Vector3.ZERO
	for n in neighbors:
		if not (n is Shrimp):
			continue
		var s: Shrimp = n
		var d: Vector3 = position - s.position
		d.y *= 0.55
		var d2: float = d.length_squared()
		if d2 >= r2:
			continue
		if d2 < 1e-6:
			var ang: float = _instance_yaw()
			d = Vector3(cos(ang), 0.0, sin(ang))
			d2 = 1.0
		push += d.normalized() * (SHRIMP_SPACE - sqrt(d2)) * 1.5
	return push


func _plant_clearance_push(plants: Array) -> Vector3:
	const PLANT_SPACE: float = 0.15
	var r2: float = PLANT_SPACE * PLANT_SPACE
	var push := Vector3.ZERO
	var checked: int = 0
	for p in _nearby_plants(plants, PLANT_SPACE * 2.5):
		if not is_instance_valid(p):
			continue
		var d: Vector3 = position - p.global_position
		d.y *= 0.45
		var d2: float = d.length_squared()
		if d2 >= r2:
			continue
		if d2 < 1e-6:
			var ang: float = _instance_yaw() + 0.7
			d = Vector3(cos(ang), 0.0, sin(ang))
			d2 = 1.0
		push += d.normalized() * (PLANT_SPACE - sqrt(d2)) * 1.2
		checked += 1
		if checked >= 8:
			break
	return push


func _hardscape_clearance_push() -> Vector3:
	if sim == null:
		return Vector3.ZERO
	var root: Variant = sim.get("hardscape_root")
	if root == null or not (root is Node3D):
		return Vector3.ZERO
	const CLEAR_R: float = 0.16
	var r2: float = CLEAR_R * CLEAR_R
	var push := Vector3.ZERO
	var checked: int = 0
	for h in (root as Node3D).get_children():
		if not is_instance_valid(h):
			continue
		var d: Vector3 = position - h.global_position
		d.y *= 0.35
		var d2: float = d.length_squared()
		if d2 >= r2:
			continue
		if d2 < 1e-6:
			d = Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1))
			if d.length_squared() < 1e-6:
				d = Vector3(1.0, 0.0, 0.0)
			d2 = maxf(d.length_squared(), 1e-6)
		push += d.normalized() * (CLEAR_R - sqrt(d2)) * 1.25
		checked += 1
		if checked >= 10:
			break
	return push


# META #31 — seeded per-entity genetics stream (deterministic offspring under a
# fixed master seed; mirrors fish.gd's _genetics_rng). Order-independent of other
# entities because the stream is keyed on this shrimp's id.
func _genetics_rng() -> RandomNumberGenerator:
	return MindRng.stream(sim, MindRng.entity_id(self), SimRng.STREAM_GENETICS)


func produce_offspring_genome(other: Shrimp) -> Dictionary:
	# Strong color + size drift so cherry-red colonies slowly diverge into
	# amber, olive, blue, etc. over many generations.
	var _g: RandomNumberGenerator = _genetics_rng()
	var mix := 0.5
	var color_muta := 0.2
	var size_muta := 0.08
	var new_size: float = (adult_voxel_scale + other.adult_voxel_scale) * 0.5 \
		+ _g.randf_range(-size_muta, size_muta) * adult_voxel_scale
	new_size = clampf(new_size, adult_voxel_scale * 0.65, adult_voxel_scale * 1.5)
	var new_spines: float = clampf(
		(defense_spines + other.defense_spines) * 0.5 + _g.randf_range(-0.12, 0.12), 0.0, 1.0)
	var new_toxin: float = clampf(
		(toxin_level + other.toxin_level) * 0.5 + _g.randf_range(-0.10, 0.10), 0.0, 1.0)
	var new_claw_size: float = clampf(
		(claw_size + other.claw_size) * 0.5 + _g.randf_range(-0.14, 0.18), 0.0, 1.2)
	var new_length: float = clampf(
		(body_length_factor + other.body_length_factor) * 0.5 + _g.randf_range(-0.16, 0.16),
		0.75, 1.7)
	# Expanded architecture inheritance (continuous avg + jitter, clamped).
	var new_rostrum: float = clampf(
		(rostrum_length + other.rostrum_length) * 0.5 + _g.randf_range(-0.12, 0.12), 0.0, 1.5)
	var new_eye_stalk: float = clampf(
		(eye_stalk_length + other.eye_stalk_length) * 0.5 + _g.randf_range(-0.10, 0.10), 0.0, 1.0)
	var new_abdomen_curl: float = clampf(
		(abdomen_curl + other.abdomen_curl) * 0.5 + _g.randf_range(-0.10, 0.10), 0.0, 1.0)
	var new_antenna: float = clampf(
		(antenna_length_factor + other.antenna_length_factor) * 0.5 + _g.randf_range(-0.12, 0.12), 0.5, 2.5)
	var new_leg: float = clampf(
		(leg_length_factor + other.leg_length_factor) * 0.5 + _g.randf_range(-0.10, 0.12), 0.5, 2.0)
	var new_claw_asym: float = clampf(
		(claw_asymmetry + other.claw_asymmetry) * 0.5 + _g.randf_range(-0.10, 0.12), 0.0, 1.0)
	var new_filter_fans: bool = (filter_fans if _g.randf() < 0.95
		else (other.filter_fans if _g.randf() < 0.5 else not filter_fans))
	# body_shape stays in the lineage; rare mutation to a sibling plan lets a
	# colony slowly diverge into crabs / crayfish / mantis morphs over time.
	var new_body_shape: String = body_shape if _g.randf() < 0.9 else other.body_shape
	if _g.randf() < 0.04:
		var plans: Array[String] = ["caridean", "crab", "lobster", "mantis"]
		new_body_shape = plans[_g.randi() % plans.size()]
	var new_pattern: int = pattern_type if _g.randf() < 0.85 else other.pattern_type
	if _g.randf() < 0.06:
		new_pattern = _g.randi() % 4
	var new_pat_scale: float = clampf(
		(pattern_scale + other.pattern_scale) * 0.5 + _g.randf_range(-0.12, 0.12), 0.0, 1.0)
	var new_pat_intensity: float = clampf(
		(pattern_intensity + other.pattern_intensity) * 0.5 + _g.randf_range(-0.12, 0.12), 0.0, 1.0)
	var new_pat_density: float = clampf(
		(pattern_density + other.pattern_density) * 0.5 + _g.randf_range(-0.12, 0.12), 0.0, 1.0)
	var g: Dictionary = {
		"organism_type": "shrimp",
		"species": species,
		"base_color": base_color.lerp(other.base_color, mix).lerp(
			Color(_g.randf(), _g.randf(), _g.randf()), color_muta),
		"accent_color": accent_color.lerp(other.accent_color, mix).lerp(
			Color(_g.randf(), _g.randf(), _g.randf()), color_muta * 0.5),
		"adult_voxel_scale": new_size,
		"max_age_s": (max_age_s + other.max_age_s) * 0.5 + _g.randf_range(-30.0, 30.0),
		"max_speed": (max_speed + other.max_speed) * 0.5 + _g.randf_range(-0.08, 0.08),
		"sex": _g.randi() % 2,
		"substrate_top_y": substrate_top_y,
		"is_cleaner": is_cleaner or other.is_cleaner,
		"defense_spines": new_spines,
		"toxin_level": new_toxin,
		"claw_size": new_claw_size,
		"body_length_factor": new_length,
		"body_shape": new_body_shape,
		"rostrum_length": new_rostrum,
		"eye_stalk_length": new_eye_stalk,
		"abdomen_curl": new_abdomen_curl,
		"antenna_length_factor": new_antenna,
		"leg_length_factor": new_leg,
		"claw_asymmetry": new_claw_asym,
		"filter_fans": new_filter_fans,
		"pattern_type": new_pattern,
		"pattern_scale": new_pat_scale,
		"pattern_intensity": new_pat_intensity,
		"pattern_density": new_pat_density,
		"generation": maxi(generation, other.generation) + 1,
		"parent_lineage": "%s & %s" % [shrimp_name, other.shrimp_name],
		"parent_keys": SpeciesLibScript.new().parent_keys_for_breeding([
			get_saved_genome(), other.get_saved_genome(),
		]),
	}
	if sim != null:
		EvolutionPressure.apply_shrimp_offspring(
			g, EvolutionPressure.sample_from_sim(sim, position))
	_apply_shrimp_saltation(g, _g)
	return g


# Rare shrimp "sport" morphs — the prized colony surprises (deep blue, golden,
# snowball, carbon black, jumbo, neon). ~0.4% of fry. Tagged for discovery.
static func _apply_shrimp_saltation(g: Dictionary, rng: RandomNumberGenerator) -> void:
	if rng.randf() > 0.004:
		return
	var kinds: Array[String] = ["blue", "golden", "snowball", "carbon", "jumbo", "neon"]
	var kind: String = kinds[rng.randi() % kinds.size()]
	match kind:
		"blue":
			g["base_color"] = Color(0.12, 0.22, 0.62)
			g["accent_color"] = Color(0.3, 0.5, 0.95)
		"golden":
			g["base_color"] = Color(0.95, 0.72, 0.12)
			g["accent_color"] = Color(1.0, 0.88, 0.4)
		"snowball":
			g["base_color"] = Color(0.93, 0.95, 0.97)
			g["accent_color"] = Color(0.8, 0.9, 1.0)
			g["pattern_intensity"] = 0.2
		"carbon":
			for k in ["base_color", "accent_color"]:
				if g.get(k) is Color:
					g[k] = (g[k] as Color).darkened(0.72)
		"jumbo":
			g["adult_voxel_scale"] = clampf(float(g.get("adult_voxel_scale", 0.1)) * 1.4, 0.06, 0.4)
		"neon":
			g["pattern_density"] = clampf(float(g.get("pattern_density", 0.5)) + 0.4, 0.0, 1.0)
			g["pattern_intensity"] = clampf(float(g.get("pattern_intensity", 0.5)) + 0.35, 0.0, 1.0)
			if g.get("accent_color") is Color:
				g["accent_color"] = (g["accent_color"] as Color).lerp(Color(0.2, 1.0, 0.7), 0.4)
	g["saltation"] = kind


# ---- Save / load ----

static func _genome_to_json(g: Dictionary) -> Dictionary:
	var out: Dictionary = g.duplicate(true)
	for key in ["base_color", "accent_color"]:
		if out.has(key) and out[key] is Color:
			out[key] = SaveHelpers.color_to_array(out[key])
	return out


static func _genome_from_json(g: Dictionary) -> Dictionary:
	var out: Dictionary = g.duplicate(true)
	for key in ["base_color", "accent_color"]:
		if out.has(key) and out[key] is Array:
			out[key] = SaveHelpers.array_to_color(out[key])
	return out


func to_save_dict() -> Dictionary:
	return {
		"id": id,
		"pos": SaveHelpers.vec3_to_array(global_position),
		"genome": _genome_to_json(_saved_genome),
		# Dynamic state
		"age": age,
		"hunger": hunger,
		"energy": energy,
		"maturity": int(maturity),
		"velocity": SaveHelpers.vec3_to_array(velocity),
		"heading": SaveHelpers.vec3_to_array(heading),
		"speed": speed,
		"current_mode": int(current_mode),
		"breed_cooldown": breed_cooldown,
		"breed_count": breed_count,
		"clutch_size": clutch_size,
		"is_gravid": is_gravid,
		"gravid_timer": gravid_timer,
		"gravid_partner_genome": _genome_to_json(gravid_partner_genome),
		"partner_id": _id_of(partner),
		"court_timer": court_timer,
		"growth_factor": growth_factor,
		"generation": generation,
		# Persistent identity (AIDirector pass)
		"display_name": shrimp_name,
		"name_source": name_source,
		"personality": personality.duplicate(),
		"bio": bio.duplicate(),
		# Death animation state — prevents the looping-death bug where a
		# dying shrimp saved mid-animation gets resurrected by load and
		# immediately re-dies (same fix as fish.gd). Wall-clock persisted
		# so the safety timeout doesn't reset on each reload.
		"_dying": _dying,
		"_dying_timer": _dying_timer,
		"_dying_wall_start_unix": _dying_wall_start_unix,
		"clean_clients": clean_clients.duplicate(),
	}


func apply_save_dict(d: Dictionary) -> void:
	id = String(d.get("id", id))
	var g: Dictionary = _genome_from_json(d.get("genome", {}))
	init_genome(g)
	age = float(d.get("age", 0.0))
	hunger = float(d.get("hunger", 0.3))
	energy = float(d.get("energy", 1.0))
	maturity = int(d.get("maturity", MATURITY_FRY))
	velocity = SaveHelpers.array_to_vec3(d.get("velocity", []), Vector3.ZERO)
	heading = SaveHelpers.array_to_vec3(d.get("heading", []), Vector3.FORWARD)
	speed = float(d.get("speed", 0.0))
	current_mode = int(d.get("current_mode", Mode.WANDER)) as Mode
	breed_cooldown = float(d.get("breed_cooldown", 0.0))
	breed_count = int(d.get("breed_count", 0))
	clutch_size = int(d.get("clutch_size", clutch_size))
	is_gravid = not not d.get("is_gravid", false)
	gravid_timer = float(d.get("gravid_timer", 0.0))
	gravid_partner_genome = _genome_from_json(d.get("gravid_partner_genome", {}))
	court_timer = float(d.get("court_timer", 0.0))
	growth_factor = float(d.get("growth_factor", 1.0))
	generation = int(d.get("generation", 0))
	# Persistent identity (AIDirector). When the save predates the AI pass
	# the fields are absent and we keep whatever init_genome rolled.
	if d.has("display_name") and String(d["display_name"]) != "":
		shrimp_name = String(d["display_name"])
	if d.has("name_source"):
		name_source = String(d["name_source"])
	var saved_p: Variant = d.get("personality", null)
	if saved_p is Dictionary and not (saved_p as Dictionary).is_empty():
		personality = (saved_p as Dictionary).duplicate()
	var saved_b: Variant = d.get("bio", null)
	if saved_b is Dictionary and not (saved_b as Dictionary).is_empty():
		bio = (saved_b as Dictionary).duplicate()
	# Restore death-animation state so a dying shrimp doesn't get
	# resurrected on reload only to immediately re-die (the looping
	# death animation bug).
	_dying = bool(d.get("_dying", false))
	_dying_timer = float(d.get("_dying_timer", 0.0))
	_dying_wall_start_unix = int(d.get("_dying_wall_start_unix", 0))
	var saved_clients: Variant = d.get("clean_clients", null)
	if saved_clients is Dictionary:
		clean_clients = (saved_clients as Dictionary).duplicate()
	if _dying and _dying_wall_start_unix == 0:
		_dying_wall_start_unix = int(Time.get_unix_time_from_system())
	if _dying and _dying_timer <= 0.0:
		_dying_timer = 0.1
	# Maturity-dependent scale needs to be re-applied since init_genome ran
	# before we'd set the maturity.
	scale = Vector3.ONE * _maturity_scale()
	climb_target = null  # cheap to re-pick


static func _id_of(n: Node) -> String:
	if n == null or not is_instance_valid(n):
		return ""
	return String(n.get("id"))


func resolve_refs(saved: Dictionary, id_map: Dictionary) -> void:
	var pid: String = String(saved.get("partner_id", ""))
	if pid != "" and id_map.has(pid):
		var p: Node = id_map[pid]
		if p is Shrimp and is_instance_valid(p):
			partner = p
