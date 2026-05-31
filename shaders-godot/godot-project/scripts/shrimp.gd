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
var shelter_bonus: float = 0.0   # runtime anti-predator cover bonus (read by fish AI)
# Cleaning-station behavior state.
var _clean_target: Node3D = null
var _clean_hold: float = 0.0
const CLEAN_RADIUS: float = 1.4
const CLEAN_HOLD_DURATION: float = 3.0
const CLEAN_COOLDOWN: float = 12.0
var _clean_cooldown: float = 0.0
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
var _bank_pivot: Node3D = null
var _last_yaw: float = 0.0
var _bank: float = 0.0

# Death animation state. Mirrors fish.gd — when a die event fires the shrimp
# tilts onto its side, drifts to the substrate, fades alpha, then frees and
# drops a mulm waste particle. Predator kills bypass this (kill_prey is still
# instant — the prey reads as eaten, not dying).
var _dying: bool = false
var _dying_timer: float = 0.0
const DEATH_DURATION: float = 2.5

# Refs
var sim: Node = null


# ---- Save / load ----
# Stable cross-session id and original-genome cache. See fish.gd for the
# rationale — same pattern, applied to shrimp.
var id: String = ""
var _saved_genome: Dictionary = {}


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
	is_cleaner = bool(genome.get("is_cleaner", is_cleaner))
	defense_spines = clampf(float(genome.get("defense_spines", defense_spines)), 0.0, 1.0)
	toxin_level = clampf(float(genome.get("toxin_level", toxin_level)), 0.0, 1.0)
	claw_size = clampf(float(genome.get("claw_size", claw_size)), 0.0, 1.2)
	body_length_factor = clampf(float(genome.get("body_length_factor", body_length_factor)), 0.75, 1.7)
	max_speed = clampf(
		max_speed * (1.0 + claw_size * 0.10 - (body_length_factor - 1.0) * 0.18),
		0.35, 1.6)
	generation = int(genome.get("generation", 0))
	
	shrimp_name = genome.get("shrimp_name", "")
	if shrimp_name == "":
		if genome.has("_display_name"):
			shrimp_name = String(genome["_display_name"])
		else:
			var adjs := ["Cherry", "Ghost", "Crystal", "Velvet", "Sunkist", "Blue", "Amano", "Cardinal", "Bamboo", "Bee"]
			var nouns := ["Scuttler", "Picker", "Pincher", "Nibbler", "Rover", "Crawler", "Glider", "Skitter"]
			shrimp_name = "%s %s" % [adjs[randi() % adjs.size()], nouns[randi() % nouns.size()]]
	parent_lineage = genome.get("parent_lineage", "Founders")
	
	_saved_genome["shrimp_name"] = shrimp_name
	_saved_genome["parent_lineage"] = parent_lineage
	_saved_genome["generation"] = generation
	_saved_genome["defense_spines"] = defense_spines
	_saved_genome["toxin_level"] = toxin_level
	_saved_genome["claw_size"] = claw_size
	_saved_genome["body_length_factor"] = body_length_factor
	
	scale = Vector3.ONE * _maturity_scale()
	_build_body()
	# Start each shrimp facing a random horizontal direction.
	var theta: float = randf() * TAU
	heading = Vector3(sin(theta), 0.0, -cos(theta))
	_last_yaw = atan2(heading.x, -heading.z)
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
	# Voxel shrimp facing -Z. Components:
	#   - Carapace (front body): 2 stacked voxels with eyes on sides
	#   - Mid segment: thickest
	#   - Tail segments: 2 voxels arching upward (the classic shrimp curl)
	#   - Antennae: thin voxels projecting forward (animated to twitch)
	#   - Legs (visual only): tiny voxels under the body
	var v: float = adult_voxel_scale
	var lenf: float = body_length_factor
	var mat_body := VoxelMat.make(base_color)
	var mat_belly := VoxelMat.make(accent_color)
	var mat_eye := VoxelMat.make(Color8(11, 11, 14))
	var mat_dark := VoxelMat.make(base_color.darkened(0.3))
	var mat_antenna := VoxelMat.make(base_color.darkened(0.15))
	if toxin_level > 0.35:
		var warn: Color = base_color.lerp(Color8(245, 235, 80), clampf(toxin_level * 0.55, 0.0, 0.55))
		mat_body = VoxelMat.make(warn)

	_bank_pivot = Node3D.new()
	_bank_pivot.name = "BankPivot"
	add_child(_bank_pivot)

	# Carapace - front segment.
	_voxel(_bank_pivot, Vector3(0, v * 0.3, -v * 0.8 * lenf),
		Vector3(v * 0.9, v * 0.9, v * 0.9 * lenf), mat_body)
	_voxel(_bank_pivot, Vector3(0, -v * 0.3, -v * 0.8 * lenf),
		Vector3(v * 0.7, v * 0.3, v * 0.7 * lenf), mat_belly)
	# Eyes (small dark dots on the sides of the carapace).
	_voxel(_bank_pivot, Vector3(v * 0.4, v * 0.3, -v * 1.1), Vector3(v * 0.18, v * 0.18, v * 0.18), mat_eye)
	_voxel(_bank_pivot, Vector3(-v * 0.4, v * 0.3, -v * 1.1), Vector3(v * 0.18, v * 0.18, v * 0.18), mat_eye)

	# Antennae - thin voxels jutting forward. We'll animate the pivot.
	# Cleaner shrimp get noticeably longer + bright white antennae - one
	# of the species' most recognisable features (they wave them at fish
	# as a "I'll clean you" signal at cleaning stations).
	_antenna_pivot = Node3D.new()
	_antenna_pivot.name = "Antennae"
	_antenna_pivot.position = Vector3(0, v * 0.3, -v * 1.2)
	_bank_pivot.add_child(_antenna_pivot)
	var antenna_mat: Material = mat_antenna
	var antenna_len: float = 0.9
	if is_cleaner:
		antenna_mat = VoxelMat.make(Color8(250, 250, 250))
		antenna_len = 1.6
	_voxel(_antenna_pivot, Vector3(v * 0.2, v * 0.1, -v * antenna_len * 0.45),
		Vector3(v * 0.06, v * 0.06, v * antenna_len), antenna_mat)
	_voxel(_antenna_pivot, Vector3(-v * 0.2, v * 0.1, -v * antenna_len * 0.45),
		Vector3(v * 0.06, v * 0.06, v * antenna_len), antenna_mat)

	# Mid segment (thickest part of carapace).
	_voxel(_bank_pivot, Vector3(0, v * 0.3, 0), Vector3(v * 1.1, v * 1.0, v * 0.9 * lenf), mat_body)
	_voxel(_bank_pivot, Vector3(0, -v * 0.4, 0), Vector3(v * 0.9, v * 0.25, v * 0.7 * lenf), mat_belly)

	# Tail segments (curl upward and back).
	_tail_pivot = Node3D.new()
	_tail_pivot.name = "TailPivot"
	_tail_pivot.position = Vector3(0, v * 0.4, v * 0.6 * lenf)
	_bank_pivot.add_child(_tail_pivot)
	_voxel(_tail_pivot, Vector3(0, 0, 0), Vector3(v * 0.8, v * 0.7, v * 0.6 * lenf), mat_body)
	_voxel(_tail_pivot, Vector3(0, v * 0.3, v * 0.5 * lenf),
		Vector3(v * 0.6, v * 0.5, v * 0.5 * lenf), mat_body)
	# Tail fan (flat).
	_voxel(_tail_pivot, Vector3(0, v * 0.5, v * 1.0 * lenf),
		Vector3(v * 0.7, v * 0.2, v * 0.3 * lenf), mat_dark)

	if claw_size > 0.05:
		var claw_mat: Material = VoxelMat.make(base_color.darkened(0.38).lerp(accent_color, 0.16))
		var claw_len: float = v * (0.40 + claw_size * 1.05) * lenf
		var claw_thick: float = v * (0.08 + claw_size * 0.10)
		for side in [-1.0, 1.0]:
			_voxel(_bank_pivot, Vector3(side * v * 0.62, v * 0.02, -v * (1.18 + claw_size * 0.26)),
				Vector3(claw_thick, claw_thick, claw_len), claw_mat)
			_voxel(_bank_pivot, Vector3(side * v * 0.70, -v * 0.03, -v * (1.48 + claw_size * 0.30)),
				Vector3(claw_thick * 0.9, claw_thick * 0.85, claw_len * 0.48), claw_mat)

	# Legs (small dark voxels under the body - visual interest only).
	for i in 3:
		var xside: float = 0.5 - randf() * 0.3
		var zoff: float = -0.4 + i * 0.4
		_voxel(_bank_pivot, Vector3(xside * v, -v * 0.4, zoff * v),
			   Vector3(v * 0.1, v * 0.3, v * 0.1), mat_dark)
		_voxel(_bank_pivot, Vector3(-xside * v, -v * 0.4, zoff * v),
			   Vector3(v * 0.1, v * 0.3, v * 0.1), mat_dark)

	# Egg cluster (visible only when is_gravid). Real cherry-shrimp eggs
	# are 25-30 bright yellow-orange spheres carried under the swimmerets.
	# We approximate with a small voxel cluster parented under the tail
	# pivot so it bobs naturally with the tail wag.
	_egg_cluster = Node3D.new()
	_egg_cluster.name = "EggCluster"
	_egg_cluster.position = Vector3(0, -v * 0.15, v * 0.3)
	_egg_cluster.visible = false
	_tail_pivot.add_child(_egg_cluster)
	var mat_egg := VoxelMat.make(Color8(240, 165, 60))
	for ex in [-0.18, 0.0, 0.18]:
		for ez in [-0.1, 0.1]:
			_voxel(_egg_cluster, Vector3(ex * v, 0.0, ez * v),
				   Vector3(v * 0.18, v * 0.18, v * 0.18), mat_egg)

	# Cleaner-shrimp spine stripe: a single bright white voxel running
	# along the top of the body from carapace through mid through tail.
	# The signature "skunk" stripe that ID's Lysmata amboinensis.
	if is_cleaner:
		var stripe_mat := VoxelMat.make(Color8(252, 252, 252))
		# Three segments along the spine, matching the three body
		# segments. Y offset puts the stripe on the very top.
		_voxel(_bank_pivot, Vector3(0, v * 0.65, -v * 0.8),
			Vector3(v * 0.16, v * 0.08, v * 0.6), stripe_mat)
		_voxel(_bank_pivot, Vector3(0, v * 0.7, 0),
			Vector3(v * 0.16, v * 0.08, v * 0.85), stripe_mat)
		_voxel(_bank_pivot, Vector3(0, v * 0.65, v * 0.55),
			Vector3(v * 0.16, v * 0.08, v * 0.5), stripe_mat)

	# Defensive dorsal spines (Amano/cherry-style exaggerated trait). Higher
	# values add a more pronounced ridge, acting as visible anti-predator armor.
	if defense_spines > 0.12:
		var spine_mat: Material = VoxelMat.make(base_color.lightened(0.12))
		var spine_n: int = clampi(int(round(1.0 + defense_spines * 4.0)), 1, 5)
		for i in spine_n:
			var t: float = float(i) / float(maxi(1, spine_n - 1))
			var z: float = lerpf(-v * 0.65, v * 0.62, t)
			var h: float = v * (0.08 + defense_spines * 0.28) * (1.0 - absf(t - 0.5) * 0.4)
			_voxel(_bank_pivot, Vector3(0.0, v * 0.68 + h * 0.5, z),
				Vector3(v * 0.10, h, v * 0.08), spine_mat)
	# Morphology elaboration from existing architecture traits:
	#   - large/grown shrimp gain pleopod fan detail
	#   - toxic lines gain lateral warning flanges
	if growth_factor > 1.05 or adult_voxel_scale > 0.12:
		var fan_mat: Material = VoxelMat.make(accent_color.lightened(0.05))
		var fan_n: int = clampi(2 + int((growth_factor - 1.0) * 5.0), 2, 5)
		for i in fan_n:
			var t: float = float(i) / float(maxi(1, fan_n - 1))
			var zf: float = lerpf(-v * 0.15, v * 0.95, t)
			_voxel(_bank_pivot, Vector3(v * 0.22, -v * 0.28, zf),
				Vector3(v * 0.09, v * 0.07, v * 0.24), fan_mat)
			_voxel(_bank_pivot, Vector3(-v * 0.22, -v * 0.28, zf),
				Vector3(v * 0.09, v * 0.07, v * 0.24), fan_mat)
	if toxin_level > 0.32:
		var warn_mat: Material = VoxelMat.make(base_color.lerp(Color8(250, 228, 110),
			clampf(toxin_level * 0.55, 0.0, 0.55)))
		var flange_h: float = v * (0.10 + toxin_level * 0.20)
		for zf in [-v * 0.35, v * 0.05, v * 0.45]:
			_voxel(_bank_pivot, Vector3(v * 0.56, v * 0.10, zf),
				Vector3(v * 0.08, flange_h, v * 0.16), warn_mat)
			_voxel(_bank_pivot, Vector3(-v * 0.56, v * 0.10, zf),
				Vector3(v * 0.08, flange_h, v * 0.16), warn_mat)

	# Stagger first molt so the population doesn't molt in lock-step.
	_molt_timer = randf_range(MOLT_INTERVAL_MIN, MOLT_INTERVAL_MAX)


func _voxel(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelMat.get_box(size)
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


func _is_shelter_plant(p: Plant) -> bool:
	if p == null or not is_instance_valid(p):
		return false
	if not (p is Coral):
		return false
	var form: String = String(p.get("coral_form"))
	return form == "anemone" or form == "sponge" \
		or form == "sponge_fresh" or form == "hydra_fresh"


func _pick_shelter_plant(plants: Array) -> Plant:
	var best: Plant = null
	var best_score: float = INF
	for p in plants:
		if not (p is Plant):
			continue
		var pl: Plant = p
		if not _is_shelter_plant(pl):
			continue
		var d2: float = pl.global_position.distance_squared_to(position)
		if d2 > SHELTER_SCAN_RADIUS * SHELTER_SCAN_RADIUS:
			continue
		# Favor larger sessile forms as better refuge.
		var score: float = d2 - float(pl.biomass()) * 0.02
		if score < best_score:
			best_score = score
			best = pl
	return best


# ---- Brain (10 Hz tick) ----

func tick(dt: float, plants: Array, algae_array: Array, waste: Array, _fry_array: Array, baby_snails: Array,
		  neighbors: Array, world_bounds: AABB) -> Dictionary:
	var events: Dictionary = {}

	# Dying shrimp are inert — no behavior, no events. _process handles
	# the sinking + fading animation and queue_free.
	if _dying:
		return events

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
		for f in sim.fish:
			if not is_instance_valid(f):
				continue
			var species_v: Variant = f.get("species")
			var predatory: bool = bool(f.get("shrimp_predator")) \
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
			for f in sim.fish:
				if not is_instance_valid(f) or f.maturity == Fish.MATURITY_FRY:
					continue
				var d2: float = f.position.distance_squared_to(position)
				if d2 > CLEAN_RADIUS * CLEAN_RADIUS:
					continue
				# Score = stress level. Highest-stress fish in range wins.
				var s: float = float(f.stress)
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
	# moderately hungry as long as they have energy reserves. Crowding is
	# handled by cannibalism and food competition, not a hard cap.
	if maturity == MATURITY_ADULT and breed_cooldown <= 0.0 and partner == null \
			and hunger < 0.6 and energy > 0.5:
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
			# `s.partner != null` was the only check before — a freed-but-
			# not-yet-cleaned-up partner reference is non-null in Godot,
			# so `s` looked permanently paired and was skipped forever
			# (until its own tick ran the validity-cleanup at line 317).
			# In a fast-dying colony this silently killed breeding for the
			# survivors. Validate the partner ref properly here.
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
	for w in waste:
		if not is_instance_valid(w):
			continue
		var d2: float = (w as Node3D).global_position.distance_squared_to(position)
		var max_dist: float = 25.0 if w.kind == 3 else 4.0
		if d2 < max_dist and d2 < best_w_d2:
			best_w_d2 = d2
			best_w = w
	if best_w != null:
		current_mode = Mode.FORAGE_WASTE
		var to_w: Vector3 = best_w.global_position - position
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
		for a in algae_array:
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

	# Tier 6: PLANTS - Only if plants are growing well and algae/food is scarce.
	if hunger > 0.4:
		# Corals are fallback forage when detritus/algae are scarce.
		if hunger > 0.65:
			var best_coral: Plant = null
			var best_coral_d2: float = 6.0
			for p in plants:
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
		for p in plants:
			if not is_instance_valid(p) or p.biomass() < 15:
				continue
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

	# Night-time dampening - shrimp also slow at night.
	if sim != null:
		var dl: float = float(sim.daylight())
		var night_factor: float = 0.35 + 0.65 * dl
		target_velocity *= night_factor

	# Size growth from feeding (mirrors Fish.growth_factor logic).
	if maturity == MATURITY_ADULT:
		if hunger < 0.35:
			growth_factor = minf(growth_factor + 0.0007 * dt, MAX_GROWTH)
		elif hunger > 0.7:
			growth_factor = maxf(growth_factor - 0.0004 * dt, 0.7)

	_apply_target(target_velocity)
	return events


func _apply_target(t: Vector3) -> void:
	# Cache for physics step in _process.
	_target_velocity = t


var _target_velocity: Vector3 = Vector3.ZERO


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

	# Cap per-step dt for integration stability. At time_scale=16 a single
	# frame's dt would otherwise be ~0.27 s — large enough that the shrimp's
	# Euler-integrated position overshoots its steering target, the brain
	# inverts target_velocity next frame, and the shrimp ping-pongs in place
	# (the "spinning" symptom shared with fish.gd). Slightly conservative
	# 0.04 s here because shrimp have a higher turn rate than fish, so they
	# need a tighter step to stay stable.
	dt = minf(dt, 0.04)
	# Gravity-like pull when not climbing. Shrimp tend to stick to surfaces.
	if climb_target == null:
		_target_velocity.y -= 1.2 * dt

	# Decompose into heading + speed.
	var target_dir: Vector3 = heading
	var target_spd: float = 0.0
	if _target_velocity.length_squared() > 1e-4:
		target_spd = _target_velocity.length()
		target_dir = _target_velocity.normalized()
	# Day/night activity. Shrimp are crepuscular — most active at dawn /
	# dusk, calmer at midday and dim at midnight. We compute a soft bell
	# centered on day_phase 0.0 and 0.5 (the dawn / dusk transitions).
	target_spd *= _day_activity_mult()

	# Bounded turn (shrimp are nimble - higher turn rate than fish).
	var angle: float = heading.angle_to(target_dir)
	if angle > 0.0005:
		var axis: Vector3 = heading.cross(target_dir)
		if axis.length_squared() < 1e-6:
			axis = Vector3.UP
		axis = axis.normalized()
		var turn: float = minf(max_turn_rate * dt, angle)
		heading = heading.rotated(axis, turn).normalized()
		# NaN guard — see fish.gd's matching guard for the failure mode.
		if not heading.is_finite() or heading.length_squared() < 0.5:
			heading = Vector3(sin(_last_yaw), 0.0, -cos(_last_yaw))

	# Linear accel toward target speed.
	speed = move_toward(speed, target_spd, 3.0 * dt)

	velocity = heading * speed
	position += velocity * dt
	# Keep shrimp comfortably inside the tank volume; wall_avoid is soft and
	# this clamp prevents occasional geometry intersections on fast timesteps.
	if sim != null:
		var w: Node = sim.get_parent()
		if w != null and w.has_method("clamp_xyz_in_tank"):
			position = w.clamp_xyz_in_tank(position, 0.2)
		else:
			var b: AABB = sim.world_bounds
			position.x = clampf(position.x, b.position.x + 0.18, b.end.x - 0.18)
			position.z = clampf(position.z, b.position.z + 0.18, b.end.z - 0.18)
		position.y = maxf(position.y, substrate_top_y + 0.05)
		if w != null and w.has_method("column_surface_y"):
			var floor_y: float = w.column_surface_y(position.x, position.z)
			position.y = maxf(position.y, floor_y + 0.05)

	# Face heading (look_at with body built facing -Z). Skip when nearly
	# stationary — the brain may flip target_velocity direction frame-to-
	# frame at low speed and look_at would snap the shrimp around.
	if speed > 0.04 and heading.length_squared() > 1e-4:
		var d: Vector3 = heading
		if absf(d.dot(Vector3.UP)) > 0.95:
			d = (d + Vector3(0.05, 0, 0)).normalized()
		look_at(position + d, Vector3.UP)

	# Banking on yaw rate (shrimp lean into turns less than fish).
	var current_yaw: float = atan2(heading.x, -heading.z)
	var yaw_diff: float = wrapf(current_yaw - _last_yaw, -PI, PI)
	_last_yaw = current_yaw
	var yaw_rate: float = yaw_diff / maxf(dt, 0.0001)
	var bank_target: float = clampf(-yaw_rate * 0.2, -0.4, 0.4)
	_bank = lerpf(_bank, bank_target, clampf(dt * 5.0, 0.0, 1.0))
	if _bank_pivot != null:
		_bank_pivot.rotation.z = _bank

	# Animation: tail flicks + antennae twitch + walking bob.
	_swim_phase += dt * (3.0 + speed * 4.0)
	# Tail-flick amplitude scales sharply with speed. A calm shrimp barely
	# twitches its tail; a spooked or fleeing shrimp executes the classic
	# big rapid "tail flip" escape - real shrimp use this to shoot
	# backwards away from predators.
	var tail_amp: float = 0.12 + minf(speed * 0.45, 0.45)
	if _tail_pivot != null:
		_tail_pivot.rotation.x = sin(_swim_phase) * tail_amp
	if _antenna_pivot != null:
		_antenna_pivot.rotation.y = sin(_swim_phase * 1.7) * 0.20
		_antenna_pivot.rotation.x = sin(_swim_phase * 2.1) * 0.10
	# Walking bob: a small vertical pulse at twice the tail frequency
	# mimics the alternating-leg gait of crawling. Suppressed at very
	# low speeds (resting) and at high speeds (the shrimp is tail-
	# flipping above substrate, legs aren't doing the work).
	if _bank_pivot != null and _molt_flash <= 0.0:
		var walk_factor: float = clampf(speed * 5.0, 0.0, 1.0) \
			* clampf(1.0 - speed * 0.55, 0.0, 1.0)
		_bank_pivot.position.y = sin(_swim_phase * 2.0) * 0.014 * walk_factor

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
	scale = scale.lerp(Vector3.ONE * _maturity_scale() * growth_factor, dt * 0.5)

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
	_dying_timer = maxf(0.0, _dying_timer - dt)
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
		mi.material_override = VoxelMat.make(c_egg if (i & 1) == 0 else c_egg_dark)
		_egg_cluster.add_child(mi)


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


func _wall_avoid(b: AABB) -> Vector3:
	var margin := 0.8
	var v := Vector3.ZERO
	if position.x < b.position.x + margin:
		v.x += 1.0
	if position.x > b.position.x + b.size.x - margin:
		v.x -= 1.0
	if position.z < b.position.z + margin:
		v.z += 1.0
	if position.z > b.position.z + b.size.z - margin:
		v.z -= 1.0
	return v


func _neighbor_clearance_push(neighbors: Array) -> Vector3:
	const SHRIMP_SPACE: float = 0.14
	var r2: float = SHRIMP_SPACE * SHRIMP_SPACE
	var push := Vector3.ZERO
	for n in neighbors:
		if not (n is Shrimp):
			continue
		var s: Shrimp = n
		var d: Vector3 = position - s.position
		d.y *= 0.55
		var d2: float = d.length_squared()
		if d2 < 1e-6 or d2 >= r2:
			continue
		push += d.normalized() * (SHRIMP_SPACE - sqrt(d2)) * 1.5
	return push


func _plant_clearance_push(plants: Array) -> Vector3:
	const PLANT_SPACE: float = 0.15
	var r2: float = PLANT_SPACE * PLANT_SPACE
	var push := Vector3.ZERO
	var checked: int = 0
	for p in plants:
		if not is_instance_valid(p):
			continue
		var d: Vector3 = position - p.global_position
		d.y *= 0.45
		var d2: float = d.length_squared()
		if d2 < 1e-6 or d2 >= r2:
			continue
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


func produce_offspring_genome(other: Shrimp) -> Dictionary:
	# Strong color + size drift so cherry-red colonies slowly diverge into
	# amber, olive, blue, etc. over many generations.
	var mix := 0.5
	var color_muta := 0.2
	var size_muta := 0.08
	var new_size: float = (adult_voxel_scale + other.adult_voxel_scale) * 0.5 \
		+ randf_range(-size_muta, size_muta) * adult_voxel_scale
	new_size = clampf(new_size, adult_voxel_scale * 0.65, adult_voxel_scale * 1.5)
	var new_spines: float = clampf(
		(defense_spines + other.defense_spines) * 0.5 + randf_range(-0.12, 0.12), 0.0, 1.0)
	var new_toxin: float = clampf(
		(toxin_level + other.toxin_level) * 0.5 + randf_range(-0.10, 0.10), 0.0, 1.0)
	var new_claw_size: float = clampf(
		(claw_size + other.claw_size) * 0.5 + randf_range(-0.14, 0.18), 0.0, 1.2)
	var new_length: float = clampf(
		(body_length_factor + other.body_length_factor) * 0.5 + randf_range(-0.16, 0.16),
		0.75, 1.7)
	var g: Dictionary = {
		"organism_type": "shrimp",
		"species": species,
		"base_color": base_color.lerp(other.base_color, mix).lerp(
			Color(randf(), randf(), randf()), color_muta),
		"accent_color": accent_color.lerp(other.accent_color, mix).lerp(
			Color(randf(), randf(), randf()), color_muta * 0.5),
		"adult_voxel_scale": new_size,
		"max_age_s": (max_age_s + other.max_age_s) * 0.5 + randf_range(-30.0, 30.0),
		"max_speed": (max_speed + other.max_speed) * 0.5 + randf_range(-0.08, 0.08),
		"sex": randi() % 2,
		"substrate_top_y": substrate_top_y,
		"is_cleaner": is_cleaner or other.is_cleaner,
		"defense_spines": new_spines,
		"toxin_level": new_toxin,
		"claw_size": new_claw_size,
		"body_length_factor": new_length,
		"generation": maxi(generation, other.generation) + 1,
		"parent_lineage": "%s & %s" % [shrimp_name, other.shrimp_name],
		"parent_keys": SpeciesLibrary.parent_keys_for_breeding([
			get_saved_genome(), other.get_saved_genome(),
		]),
	}
	if sim != null:
		EvolutionPressure.apply_shrimp_offspring(
			g, EvolutionPressure.sample_from_sim(sim, position))
	return g


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
	is_gravid = bool(d.get("is_gravid", false))
	gravid_timer = float(d.get("gravid_timer", 0.0))
	gravid_partner_genome = _genome_from_json(d.get("gravid_partner_genome", {}))
	court_timer = float(d.get("court_timer", 0.0))
	growth_factor = float(d.get("growth_factor", 1.0))
	generation = int(d.get("generation", 0))
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
