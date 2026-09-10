# A single growing plant (one stem/blade).
#
# Each plant owns a chain of voxels stacked vertically. It grows over time when
# given access to nutrients from the substrate grid below it. Fish can nibble
# the top of the plant, removing voxels and gaining food. If a plant is reduced
# to 0 voxels, it dies (queues itself for removal).
#
# === Realism systems ===
#   Leaf shapes    — multi-voxel leaves per form type (paddle/ribbon/lance/needle)
#   Root system    — visible root voxels anchoring into substrate
#   Nutrient health — deficiency symptoms (yellowing, pinholes, melting)
#   Pearling       — O2 bubbles on healthy leaves in bright light
#   Flowering      — bud → open → seed pod → seed release lifecycle
#   Canopy cycle   — emergent stems stop at water surface, flower, seed,
#                    senesce (monocarpic) or reflower (perennial)
#   Decay          — gradual browning, leaf detachment, crypt melt
#   Flow response  — asymmetric bending, leaf flutter

extends Node3D
class_name Plant

const PLANT_RAMP: Array[Color] = [
	Color8(16, 38, 20),
	Color8(29, 59, 34),
	Color8(44, 90, 48),
	Color8(62, 127, 64),
	Color8(87, 162, 83),
	Color8(121, 192, 105),
]
const VOXEL_SIZE: float = 0.32

# Stress palette for nutrient deficiency (yellowing / browning).
const STRESS_RAMP: Array[Color] = [
	Color8(140, 160, 60),   # slight chlorosis
	Color8(180, 170, 50),   # yellow
	Color8(190, 150, 70),   # yellow-brown
	Color8(160, 110, 60),   # brown
	Color8(120, 80, 45),    # dead brown
]

# Optional per-species ramp override. World assigns this before init() so each
# species reads a different color band.
var ramp_override: Array = []

# Per-plant params (set on spawn).
var max_height: int = 22
var growth_rate: float = 0.18  # voxels per second at saturated nutrients
var nutrient_demand: float = 0.05  # nutrients consumed per voxel grown
var sway_amplitude: float = 0.25

# Leaf form type: determines which LeafShapes builder is used.
# "column"     = legacy 1-voxel stacking (backward compat)
# "paddle"     = rosette leaves (Crypts, Swords)
# "ribbon"     = blade leaves (Vallisneria)
# "lance"      = stem plant paired leaves (Ludwigia, Rotala)
# "needle"     = carpet grasses (Eleocharis)
# "spade"      = broad rounded spade (Anubias barteri)
# "cordate"    = heart shape (Red Root Floater)
# "pinnate"    = fern-divided (Hygrophila pinnatifida, Bolbitis)
# "starburst"  = radial rosette (Eriocaulon, Blyxa)
# "four_leaf"  = Marsilea clover
# "fingered"   = branched-tip lance (Java Fern Windelov, Trident)
# "downy"      = crinkled mini rosette (Pogostemon helferi)
# "round"      = circular pad (lily pads)
# "lobed"      = irregular Java Fern broad blades
var leaf_form: String = "column"
# How many voxels make up each leaf structure.
var leaf_length: int = 4
# Uniform scale modifier for leaf builders (1.0 = default; <1 smaller, >1 bigger).
# Lets a Bucephalandra mini and a Bucephalandra brownie share leaf_form but
# read as different scales.
var leaf_size_mult: float = 1.0

# ---- Textural modifiers (read by leaf builders) ----
# variegation: per-voxel chance of rendering white/cream (Anubias Stardust,
#   Pinto, variegated mosses). 0..1.
# quilted: small per-voxel vertical jitter — reads as hammered/bullate texture
#   (Anubias coffeefolia, Crypt balansae).
# wavy_edges: sine-offset along leaf width (Crypt wendtii ruffled, Buce
#   wavy green).
# iridescence: shader param 0..1 — view-angle-dependent blue/purple sheen
#   for Bucephalandra. Threaded through to foliage_mm shader via material.
# underside_tone: optional Color rendered at the leaf-tip extreme — used as
#   a venation / under-leaf tint slot. Null = ignored.
var variegation: float = 0.0
var quilted: bool = false
var wavy_edges: bool = false
var iridescence: float = 0.0
var underside_tone: Variant = null

# ---- Behavioral traits (driven by new mechanics layered on top) ----
# red_potential: 0..1, how much a plant shifts toward red/purple under
#   strong light + low nitrogen. Rotala H'ra ~1.0, Anubias ~0.0.
# co2_demand: 0..1, plant's preferred CO2 level. Higher demand = penalty
#   to growth + color when the tank's CO2 dosing is low; reward when high.
# melt_susceptibility: 0..1, Crypt-melt likelihood per chemistry crash.
# has_plantlets: when true, mature leaves randomly spawn baby plantlets
#   (Java fern + Echinodorus signature).
# is_carpet: true for carpet species — multi-runner spread + flat habit.
# whorled_leaves: stem-plant leaves emerge in whorls/pairs (Rotala) vs
#   single-side alternate (Ludwigia).
var red_potential: float = 0.0
var co2_demand: float = 0.3
var melt_susceptibility: float = 0.0
var has_plantlets: bool = false
var is_carpet: bool = false
var whorled_leaves: bool = false

# ---- Plants v2 genome traits ----
var palatability: float = 0.65
var leaf_thickness: float = 0.5
var temp_opt: float = 0.55
var allelopathy_strength: float = 0.0
var allelopathy_family: String = ""
var allelopathy_resistance: float = 0.0
var emersed_leaf_form: String = ""
var dormancy_type: String = PlantGenome.DORMANCY_NONE
var repro_mode: String = PlantGenome.REPRO_SEED
var asymmetry_seed: int = 0
# Leaf arrangement around the stem — see _phyllotaxis_yaw(). Left empty in the
# genome means "derive from the other traits" (whorled_leaves -> whorled,
# otherwise the golden-angle spiral that most stem plants use).
var phyllotaxis: String = ""
var whorl_count: int = 3
var ls_angle: float = 35.0
var ls_ratio: float = 0.72
var ls_depth: int = 2
var etiolation_sensitivity: float = 0.0
var auxin_dominance: float = 0.0
var vascular_transport_rate: float = 0.0
var growth_curve_establishment: float = 1.0
var growth_curve_acceleration: float = 0.0
var growth_curve_plateau: float = 1.0
var juvenile_leaf_form: String = ""
var adult_leaf_form: String = ""
var heteroblasty_node: int = 0
var _heteroblasty_adult: bool = false
var reiteration_loss_threshold: float = 0.0
var reiteration_capacity: int = 0
var _reiterations_used: int = 0
var _reiteration_pending_node: int = -1
var _damage_episode_active: bool = false
var _peak_biomass: int = 0
var root_foraging: float = 0.0
var bulb_photoperiod_min: float = -1.0
var bulb_photoperiod_max: float = -1.0
var bulb_temp_min: float = -1.0
var bulb_temp_max: float = -1.0
var bulb_max_dormancy_s: float = 0.0
var _internode_extension_y: float = 0.0
var _auxin_by_node: PackedFloat32Array = PackedFloat32Array()
var _auxin_rebuild_count: int = 0
var _root_reserve: float = 0.0
var _shoot_reserve: float = 0.0
const RESOURCE_RESERVOIR_CAP: float = 0.6
var _submersed_leaf_form: String = ""
var plant_age_s: float = 0.0
var _starch: float = 0.35
var _light_avg: float = 0.5
var _grazing_pressure: float = 0.0
var _lifetime_grazing_pressure: float = 0.0
var _heritable_palatability: float = 0.65
var _pollen_ready: bool = false
var _pollination_cooldown_s: float = 0.0
const POLLINATION_RADIUS: float = 3.0
const POLLINATION_COOLDOWN_S: float = 45.0
const MAX_POLLINATION_CANDIDATES: int = 16
var _heterophylly_applied: bool = false
# Circumnutation (#5): growing tips trace a slow circle over minutes. Seeded
# per-plant so a bed of stems doesn't nod in lockstep.
var _circumnutation_phase: float = randf() * TAU
var _flow_stress_timer: float = 0.0
var _dormant_timer: float = 0.0
var _bulb_buried: bool = false
var _leaf_states: Array = []  # parallel to _leaf_groups: Dictionary per leaf
var _visual_tick_t: float = 0.0
const AGE_SENESCENCE_S: float = 180.0
const TRANSPLANT_MELT_AGE_S: float = 30.0

# Naturalism #41 — per-leaf lifecycle. Bud → expand → mature → senesce → shed.
# Ages are sim-seconds; real aquatic leaves last days–weeks, compressed here so
# a watching player sees turnover within a session.
enum LeafPhase { BUD, EXPANDING, MATURE, SENESCENT, SHED }
const LEAF_EXPAND_S: float = 8.0
const LEAF_MATURE_S: float = 95.0
const LEAF_SENESCE_S: float = 28.0
const _SENESCE_TIP_COLOR: Color = Color(0.55, 0.48, 0.22)

# Naturalism #1 — persistent desire direction for new voxel placement.
# Combines phototropism (lamp), gravitropism (up), and flow lean. Refreshed
# a few times a second; placement samples the xz of this vector.
var _tropism: Vector3 = Vector3.UP
var _tropism_refresh_t: float = 0.0
const TROPISM_REFRESH_S: float = 0.45

# Latin + common name (set by real-species library, "" for emergent plants
# which fall back to plant_name's auto-generated handle).
var latin_name: String = ""
var common_name: String = ""
# Real-species library key (matches RealSpeciesLibrary entry id), or "" when
# the plant was emergent / hand-tuned.
var species_id: String = ""

# ---- Perf: cached substrate boost ----
# Computed once at init from TankConfig.substrate_type. Substrate doesn't
# change without scene reload so polling it every tick × 100 plants × 10 Hz
# was 1000 wasted lookups/sec. 1.0 = neutral, 1.20 = aquasoil boost for
# heavy feeders, 0.80 = sand penalty.
var _substrate_boost: float = 1.0
# Throttle the crypt-melt chemistry check — water chemistry doesn't crash
# in a single tick, checking once every 5 sec is plenty.
var _melt_check_t: float = 0.0
const MELT_CHECK_PERIOD: float = 5.0

# ---- Emersed → submersed transition ----
# Real aquarium plants ship in their EMERSED (above-water) form — bigger,
# glossier, slightly warmer-colored leaves. Once submerged they spend the
# first ~minute of game time melting their emersed leaves off and growing
# their submersed form. We approximate by: applying a +15% leaf_size_mult
# and a warmer-ramp shift while _emersed_remaining > 0, then linearly
# fading back to genome values as the timer drains.
const EMERSED_DURATION_S: float = 60.0
var _emersed_remaining: float = EMERSED_DURATION_S

var current_height: int = 0
var growth_progress: float = 0.0
var _growth_load_hold_s: float = 0.0
# Stable handles for structural stem voxels. They retain the old individually
# addressable semantics without retaining one MeshInstance3D per segment.
var voxels: Array[VoxelBatch.Handle] = []
var has_flower: bool = false
var has_emerged: bool = false   # true once tip has reached the water surface
var bloom_voxels: Array[MeshInstance3D] = []
var seed_timer: float = 0.0

# Epiphyte: plant anchors to a host (driftwood, rock) rather than the
# substrate. Skips root growth, doesn't draw nutrients from the substrate
# grid, and gets a modest fixed nutrient_mult (water-column micros). Set
# by world.gd at spawn for moss / java fern style species.
var is_epiphyte: bool = false
const EPIPHYTE_NUTRIENT_MULT: float = 0.55

# Trim-response branching: when fish nibble a stem voxel, we record the
# cut height. The next growth tick sprouts a small side shoot from that
# node — real plant response to grazing (apical dominance lost → lateral
# buds activate). Cleared once the side shoot is placed so each cut
# produces one branch, not an endless cascade.
var _pending_trim_nodes: Array[int] = []
const MAX_PENDING_TRIM_NODES: int = 4
var _trim_recoil_t: float = 0.0
var _trim_regrowth_boost: float = 0.0

# Canopy life cycle: vegetative growth stops at the water surface, then
# flower/seed/senescence closes the Walstad nutrient loop.
enum LifePhase { VEGETATIVE, CANOPY, SENESCENT, DORMANT_BULB }
var life_phase: int = LifePhase.VEGETATIVE
var emergent_growth: bool = true   # tall stems/corals stop at water_surface_y
var uses_flowering: bool = true    # corals override to false (planula instead)
var monocarpic: bool = false       # die after one reproductive cycle
var _canopy_timer: float = 0.0
## Infinite meniscus bob — must be killed before stem voxels are freed, or Godot
## reports "Infinite loop detected" when the PropertyTweener target vanishes.
var _canopy_bob_tween: Tween = null
var _seeds_cast_this_cycle: int = 0
const MAX_SEEDS_PER_CYCLE: int = 3
const SEED_SITE_NUTRIENT_MIN: float = 0.08  # above SubstrateGrid baseline
const SURFACE_MARGIN: float = 0.15
@warning_ignore("unused_private_class_variable")
var _flower_voxel: MeshInstance3D = null
var _phase: float = 0.0
var _t: float = 0.0
var _world_pos: Vector3 = Vector3.ZERO
# Transient bend (radians) from a fish brushing past; springs back in tick().
var _brush_bend: Vector2 = Vector2.ZERO
var _brush_bend_vel: Vector2 = Vector2.ZERO
# Last-tick growth diagnostics — surfaced by tap-a-plant inspector (#21).
var _growth_diag: Dictionary = {}
var _stem_limit_history: PackedByteArray = PackedByteArray()
const LIMIT_FACTOR_NAMES: Array[String] = [
	"balanced", "light", "nutrient", "co2", "starch", "temperature", "transport",
]
var _gust_tilt: Vector2 = Vector2.ZERO
var _mood_pulse_t: float = 0.0
var _height_ghost_y: float = -1.0
var _height_ghost_timer: float = 0.0
var _height_ghost_marker: MeshInstance3D = null
var _root_bubble_t: float = 0.0
var _detritus_fleck_nodes: Array[MeshInstance3D] = []
const GROWTH_FLOOR: float = 0.022
const MIN_HEALTH_FOR_FLOOR: float = 0.4


# Called by a passing fish to deflect the plant. world_dir is the fish's
# horizontal travel direction; amount scales with its speed/size.
func brush(world_dir: Vector3, amount: float) -> void:
	wake_plant("damage")
	var add := Vector2(world_dir.x, world_dir.z) * clampf(amount, 0.65, 0.72)
	_brush_bend = (_brush_bend + add).limit_length(0.55)
	if amount > 0.22 and _health_smooth > 0.55 and randf() < 0.35:
		_release_brush_bubbles()
# Surface for "emerged"/seeding check. Set by world.gd from WATER_HEIGHT
# at spawn so plant.gd doesn't need to know world geometry constants.
var water_surface_y: float = 6.5
var generation: int = 0
var plant_name: String = ""
var parent_lineage: String = "Founders"
var _parent_keys: Array = []

# ---- Root system ----
var root_voxels: Array[MeshInstance3D] = []
var _root_count: int = 0
var _max_roots: int = 5
var _root_growth_counter: int = 0  # grows one root per N stem voxels

# ---- Health & nutrient response ----
var health: float = 1.0  # 1.0 = thriving, 0.0 = dying
var _health_smooth: float = 1.0  # low-pass filtered for visual changes
var _starvation_timer: float = 0.0

# ---- Shade competition ----
# Refreshed every few seconds (not per-tick — the answer changes slowly
# and a per-tick neighbor scan would be O(plants²) hot path). Cached
# value is multiplied into nutrient_mult so a shaded plant grows slower
# without needing a separate growth_rate field. 1.0 = full sun, <1.0 =
# shaded by a taller neighbor within SHADE_RADIUS.
var _shade_mult: float = 1.0
var _shade_check_t: float = 0.0
var _floater_shade_melt_t: float = 0.0
const SHADE_RADIUS: float = 1.4
const SHADE_HEIGHT_DELTA: int = 2  # neighbor must be at least this much taller
const SHADE_PENALTY: float = 0.55  # multiplier on nutrient_mult when shaded

# ---- Deficiency tinting ----
# Refreshed every 2.5-4 s. Grounded in the root cell's pore-water channels.
var _deficiency_check_t: float = 0.0
var _deficiency_active: String = ""  # "", "co2", "iron"
var _root_iron_available: float = SubstrateGrid.IRON_LEGACY_DEFAULT
var _root_co2_available: float = SubstrateGrid.CO2_LEGACY_DEFAULT
var _has_pinholes: bool = false

# ---- Flowering lifecycle ----
enum FlowerStage { NONE, BUD, OPENING, MATURE, SEED_POD, RELEASING }
var flower_stage: int = FlowerStage.NONE
var _flower_timer: float = 0.0
var _flower_open_frac: float = 0.0
var _flower_node: Node3D = null
var _flower_silhouette: String = "default"
var _flower_petal_color: Color = Color.WHITE
var _flower_center_color: Color = Color.YELLOW

# ---- Decay state ----
var is_dying: bool = false
var _decay_timer: float = 0.0
var _melt_active: bool = false  # crypt melt in progress
var _melt_regrow_timer: float = 0.0
var _melt_cycled: bool = false  # one-shot detritus+ammonia shed per melt (#57)
var _pre_melt_height: int = 0
# Crypt melt scheduling — when chemistry crashes / replant happens, the
# susceptible plant enters MELTING phase: leaves drop over MELT_SHED_S,
# then regrow over MELT_REGROW_S. Once per real-world crash event, gated
# on melt_susceptibility (set per species in real_species_library.gd).
const MELT_SHED_S: float = 30.0
const MELT_REGROW_S: float = 240.0
const MELT_TRIGGER_AMMONIA: float = 1.2
const MELT_TRIGGER_STRESS: float = 0.9
# Set true after the plant has finished its first melt — we don't melt
# twice from the same chemistry event, only re-trigger after a clear period.
var _last_melt_unix: int = 0
const MELT_REARM_S: int = 300
static var _melt_cluster_times: Array = []
static var _melt_wave_headline_unix: int = 0

# ---- Pearling particles ----
var _pearling_particles: GPUParticles3D = null
var _pearling_active: bool = false
var _pearling_eligible: bool = false
var _pearling_opacity: float = 0.18
var _pearling_strength: float = 1.0
static var _shared_pearling_material: ParticleProcessMaterial = null
static var _shared_pearling_mesh: SphereMesh = null
static var _shared_pearling_mesh_medium: SphereMesh = null

# ---- Leaf structure tracking ----
# Leaf voxels render through a single per-plant MultiMesh (one draw call for all
# of a plant's leaves) instead of one MeshInstance3D node each. _leaf_groups
# holds, per leaf/accessory, the list of VoxelBatch handles that make it up, so
# a whole leaf can be shed/decayed as a unit. _leaf_ages stays parallel.
var _foliage_batch: VoxelBatch = null
var _foliage_mat: ShaderMaterial = null
var _stem_batch: VoxelBatch = null
var _stem_mat: ShaderMaterial = null
var _blush_last_sat: float = -1.0
var _blush_last_warmth: float = -99.0
var _blush_last_sss: float = -1.0
var _blush_last_vibrancy: float = -1.0
const PLANT_LOD_BASE_RANGE: float = 38.0
const PLANT_LOD_HEIGHT_BONUS_MAX: float = 12.0
const PLANT_LOD_FADE_MARGIN: float = 4.0
var _leaf_groups: Array = []        # Array[Array[VoxelBatch.Handle]]
var _leaf_ages: Array[float] = []  # birth time per leaf for aging
var _crown_density_cells: Dictionary = {}
const CROWN_DENSITY_CELL_CAP: int = 512
const LEAF_BAKE_DEFER_THRESHOLD: int = 16
const LEAF_BAKE_CHUNK_SIZE: int = 12
const STATIC_SLEEP_AFTER_S: float = 5.0
const STATIC_SLEEP_CHEMISTRY_S: float = 2.0
var _static_sleeping: bool = false
var _static_sleep_stable_s: float = 0.0
var _static_sleep_accum_s: float = 0.0
var _static_sleep_dirty: bool = true
var _static_sleep_env_signature: int = 0
var _leaf_lod_reduced: bool = false
var _leaf_lod_hidden: Array[VoxelBatch.Handle] = []
# Last wilt level we wrote into the leaf-tip handles. Tracked so the
# per-tick wilt pass only touches the multimesh when health has moved
# noticeably — repaint cost stays near-zero when nothing's changing.
var _wilt_applied: float = 0.0
# Subclasses (SpiralPlant) still use a node-based leaf model and reference this;
# base Plant leaves go through _leaf_groups / the foliage MultiMesh instead.
var _leaf_nodes: Array[Node3D] = []


func _exit_tree() -> void:
	if _foliage_batch != null:
		_foliage_batch.dispose()
		_foliage_batch = null
	if _stem_batch != null:
		_stem_batch.dispose()
		_stem_batch = null


# ---- Runner propagation ----
# Vegetative spread (stolons). Ribbon-form plants (Vallisneria) periodically
# send out a horizontal runner along the substrate; the runner grows over a
# few seconds as a thin chain of voxels, then spawns a daughter plant at
# its tip. Real Walstad mechanism for low-light ribbon plants - they
# colonize floor space without needing to flower.
var _runner_target: Vector3 = Vector3.ZERO
var _runner_origin: Vector3 = Vector3.ZERO  # plant-local start of the chain
var _runner_active: bool = false
var _runner_progress: float = 0.0           # voxels placed along the chain
var _runner_voxels: Array[MeshInstance3D] = []
var _runner_cooldown: float = 0.0            # ticks down to 0 then a runner can start
const RUNNER_VOXEL_COUNT: int = 6
const RUNNER_SEGMENT_TIME: float = 0.6        # seconds per voxel placed
const RUNNER_COOLDOWN_MIN: float = 120.0
const RUNNER_COOLDOWN_MAX: float = 240.0
const RUNNER_DISTANCE_MIN: float = 1.4
const RUNNER_DISTANCE_MAX: float = 2.1


func get_plant_genome() -> Dictionary:
	_ensure_plant_named()
	var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
	var g: Dictionary = PlantGenome.from_plant(self)
	g["organism_type"] = "plant"
	g["species"] = _save_kind()
	g["ramp_override"] = ramp.duplicate()
	return g


func _ensure_plant_named() -> void:
	if plant_name != "":
		return
	var forms: Dictionary = {
		"column": "Stem",
		"paddle": "Rosette",
		"ribbon": "Blade",
		"lance": "Sprig",
		"needle": "Carpet",
	}
	var base: String = forms.get(leaf_form, "Plant")
	plant_name = "%s %d" % [base, randi() % 900 + 100]


func init(initial_height: int = 1, params: Dictionary = {}) -> void:
	var enriched: Dictionary = PlantGenome.enrich(params)
	PlantGenome.apply_to_plant(self, enriched)
	_heritable_palatability = palatability
	if params.has("ramp_override") and params.ramp_override is Array:
		ramp_override = params.ramp_override
	_submersed_leaf_form = leaf_form
	if emersed_leaf_form == "":
		emersed_leaf_form = leaf_form
	if asymmetry_seed == 0:
		asymmetry_seed = randi()
	_resolve_phyllotaxis()
	_refresh_tropism()
	# Cache substrate boost computed below — read TankConfig ONCE here so
	# the per-tick path can skip the autoload lookup × 100 plants × 10 Hz.
	_substrate_boost = _compute_substrate_boost()
	var pk: Variant = params.get("parent_keys", [])
	if pk is Array:
		_parent_keys = (pk as Array).duplicate()
	# Naturalism #441 — register into the world's lineage book when present.
	var w: Node = get_parent()
	if w != null and w.get("plant_lineages") != null:
		var reg: Variant = w.get("plant_lineages")
		if reg is PlantLineageRegistry:
			(reg as PlantLineageRegistry).register_genome(
				PlantGenome.from_plant(self), get_instance_id())
	if params.has("emergent_growth"):
		emergent_growth = not not params["emergent_growth"]
	if params.has("monocarpic"):
		monocarpic = not not params["monocarpic"]
	if params.has("uses_flowering"):
		uses_flowering = not not params["uses_flowering"]
	else:
		_apply_default_growth_strategy()
	if params.has("is_epiphyte"):
		is_epiphyte = not not params["is_epiphyte"]
	# Transplant shock (#8): young plants melt briefly after spawn.
	if plant_age_s < TRANSPLANT_MELT_AGE_S and melt_susceptibility > 0.2:
		_melt_active = true
		_melt_regrow_timer = 0.0
	_ensure_plant_named()
	# Epiphytes don't grow roots into substrate — they cling to a host.
	# Subclasses (Coral) also no-op _build_initial_roots, so this composes
	# cleanly without subclass-specific knowledge.
	if not is_epiphyte:
		_build_initial_roots()
	else:
		_build_holdfast_anchor()
	for i in initial_height:
		_grow_one()
	_warm_start_growth_vitals()
	_apply_sway_personality()
	_apply_rooted_visibility_ranges()


# Fill in the leaf arrangement when the genome does not state one. Derived
# from traits the species data already carries, so no existing plant entry has
# to be edited to get a correct-looking rosette.
func _resolve_phyllotaxis() -> void:
	whorl_count = clampi(whorl_count, 2, 6)
	if phyllotaxis != "":
		return
	if whorled_leaves:
		phyllotaxis = PHYLLO_WHORLED
		return
	match leaf_form:
		"ribbon":
			# Vallisneria and friends fan from the crown in two ranks.
			phyllotaxis = PHYLLO_DISTICHOUS
		"needle", "pinnate":
			phyllotaxis = PHYLLO_WHORLED
			whorl_count = 4
		"round", "four_leaf", "starburst":
			# Rosettes and pads: even radial spacing beats a spiral here.
			phyllotaxis = PHYLLO_WHORLED
			whorl_count = 5
		_:
			phyllotaxis = PHYLLO_SPIRAL


# Pull TankConfig.substrate_type once and translate it into the per-plant
# nutrient multiplier. Heavy root feeders (max_height >= 12, non-carpet)
# get +20% in aquasoil / eco_complete and −20% in sand / inert gravel;
# epiphytes are unaffected; small plants don't care.
func _compute_substrate_boost() -> float:
	if is_epiphyte:
		return 1.0
	if max_height < 12 or is_carpet:
		return 1.0
	var cfg: Node = get_node_or_null("/root/TankConfig")
	if cfg == null:
		return 1.0
	var st_v: Variant = cfg.get("substrate_type")
	if st_v == null:
		return 1.0
	match String(st_v):
		"aquasoil", "eco_complete":
			return 1.20
		"sand", "inert_gravel":
			return 0.80
		_:
			return 1.0


# ---- Save / load ----

# Subclass identifier — the loader uses this to instantiate the right script.
# Subclasses override; base Plant returns "plant".
func _save_kind() -> String:
	return "plant"


# Stable cross-session id (see fish.gd). Plants are referenced by
# fish.target_plant during nibble cycles but we don't currently restore that
# ref — kept here for future-proofing and consistency.
var id: String = ""


func to_save_dict() -> Dictionary:
	return {
		"subclass": _save_kind(),
		"id": id,
		"pos": SaveHelpers.vec3_to_array(global_position),
		"init_params": {
			"max_height": max_height,
			"growth_rate": growth_rate,
			"nutrient_demand": nutrient_demand,
			"sway_amplitude": sway_amplitude,
			"leaf_form": leaf_form,
			"leaf_length": leaf_length,
			"leaf_size_mult": leaf_size_mult,
			"max_roots": _max_roots,
			"is_epiphyte": is_epiphyte,
			"variegation": variegation,
			"quilted": quilted,
			"wavy_edges": wavy_edges,
			"iridescence": iridescence,
			# Underside tone is optional — empty array means "no override".
			# Using [] instead of null avoids a ternary-type-mismatch warning
			# (Array vs Variant null can't unify under static typing).
			"underside_tone": (SaveHelpers.color_to_array(underside_tone) if underside_tone is Color else []),
			"red_potential": red_potential,
			"co2_demand": co2_demand,
			"melt_susceptibility": melt_susceptibility,
			"has_plantlets": has_plantlets,
			"is_carpet": is_carpet,
			"whorled_leaves": whorled_leaves,
			"latin_name": latin_name,
			"common_name": common_name,
			"species_id": species_id,
			"palatability": palatability,
			"leaf_thickness": leaf_thickness,
			"temp_opt": temp_opt,
			"allelopathy_strength": allelopathy_strength,
			"allelopathy_family": allelopathy_family,
			"allelopathy_resistance": allelopathy_resistance,
			"emersed_leaf_form": emersed_leaf_form,
			"dormancy_type": dormancy_type,
			"repro_mode": repro_mode,
			"asymmetry_seed": asymmetry_seed,
			"ls_angle": ls_angle,
			"ls_ratio": ls_ratio,
			"ls_depth": ls_depth,
			"etiolation_sensitivity": etiolation_sensitivity,
			"auxin_dominance": auxin_dominance,
			"vascular_transport_rate": vascular_transport_rate,
			"growth_curve_establishment": growth_curve_establishment,
			"growth_curve_acceleration": growth_curve_acceleration,
			"growth_curve_plateau": growth_curve_plateau,
			"juvenile_leaf_form": juvenile_leaf_form,
			"adult_leaf_form": adult_leaf_form,
			"heteroblasty_node": heteroblasty_node,
			"reiteration_loss_threshold": reiteration_loss_threshold,
			"reiteration_capacity": reiteration_capacity,
			"root_foraging": root_foraging,
			"bulb_photoperiod_min": bulb_photoperiod_min,
			"bulb_photoperiod_max": bulb_photoperiod_max,
			"bulb_temp_min": bulb_temp_min,
			"bulb_temp_max": bulb_temp_max,
			"bulb_max_dormancy_s": bulb_max_dormancy_s,
		},
		"ramp_override": SaveHelpers.colors_to_array(ramp_override),
		"water_surface_y": water_surface_y,
		"current_height": current_height,
		"growth_progress": growth_progress,
		"has_flower": has_flower,
		"has_emerged": has_emerged,
		"seed_timer": seed_timer,
		"life_phase": int(life_phase),
		"emergent_growth": emergent_growth,
		"uses_flowering": uses_flowering,
		"monocarpic": monocarpic,
		"_canopy_timer": _canopy_timer,
		"_seeds_cast_this_cycle": _seeds_cast_this_cycle,
		"health": health,
		"_health_smooth": _health_smooth,
		"flower_stage": int(flower_stage),
		"_flower_timer": _flower_timer,
		"_flower_open_frac": _flower_open_frac,
		"_flower_petal_color": SaveHelpers.color_to_array(_flower_petal_color),
		"_flower_center_color": SaveHelpers.color_to_array(_flower_center_color),
		"is_dying": is_dying,
		"generation": generation,
		"plant_age_s": plant_age_s,
		"_starch": _starch,
		"_grazing_pressure": _grazing_pressure,
		"_lifetime_grazing_pressure": _lifetime_grazing_pressure,
		"_heritable_palatability": _heritable_palatability,
		"_pollination_cooldown_s": _pollination_cooldown_s,
		"_submersed_leaf_form": _submersed_leaf_form,
		"_heterophylly_applied": _heterophylly_applied,
		"_bulb_buried": _bulb_buried,
		"_dormant_timer": _dormant_timer,
		"_light_avg": _light_avg,
		"_leaf_light_doses": _leaf_light_doses_snapshot(),
		"_stem_limit_history": _stem_history_snapshot(),
		"_internode_extension_y": _internode_extension_y,
		"_root_reserve": _root_reserve,
		"_shoot_reserve": _shoot_reserve,
		"_heteroblasty_adult": _heteroblasty_adult,
		"_reiterations_used": _reiterations_used,
		"_damage_episode_active": _damage_episode_active,
		"_peak_biomass": _peak_biomass,
	}


# Restore the plant's full state. Caller (SimDriver.load_state) has already
# add_child'd this node and set its global_position, so we don't touch position
# here — we use the saved position to verify but the node is already placed.
func apply_save_dict(d: Dictionary) -> void:
	id = String(d.get("id", id))
	# ramp_override must be set BEFORE init() because the voxel-color path
	# reads from it as each voxel is built.
	ramp_override = SaveHelpers.array_to_colors(d.get("ramp_override", []))
	water_surface_y = float(d.get("water_surface_y", water_surface_y))
	# Rebuild voxels at the saved height in one shot.
	var params: Dictionary = d.get("init_params", {})
	var h: int = int(d.get("current_height", 1))
	init(h, params)
	# Patch dynamic state AFTER init so init() doesn't clobber it.
	growth_progress = float(d.get("growth_progress", 0.0))
	has_flower = not not d.get("has_flower", false)
	has_emerged = not not d.get("has_emerged", false)
	seed_timer = float(d.get("seed_timer", 0.0))
	life_phase = int(d.get("life_phase", LifePhase.VEGETATIVE if not has_emerged else LifePhase.CANOPY))
	emergent_growth = not not d.get("emergent_growth", emergent_growth)
	uses_flowering = not not d.get("uses_flowering", uses_flowering)
	monocarpic = not not d.get("monocarpic", monocarpic)
	_canopy_timer = float(d.get("_canopy_timer", 0.0))
	_seeds_cast_this_cycle = int(d.get("_seeds_cast_this_cycle", 0))
	health = float(d.get("health", 1.0))
	_health_smooth = float(d.get("_health_smooth", health))
	flower_stage = int(d.get("flower_stage", 0)) as FlowerStage
	_flower_timer = float(d.get("_flower_timer", 0.0))
	_flower_open_frac = float(d.get("_flower_open_frac", 0.0))
	_flower_petal_color = SaveHelpers.array_to_color(d.get("_flower_petal_color", []), _flower_petal_color)
	_flower_center_color = SaveHelpers.array_to_color(d.get("_flower_center_color", []), _flower_center_color)
	is_dying = not not d.get("is_dying", false)
	generation = int(d.get("generation", 0))
	plant_age_s = float(d.get("plant_age_s", plant_age_s))
	_starch = float(d.get("_starch", _starch))
	_grazing_pressure = float(d.get("_grazing_pressure", _grazing_pressure))
	_lifetime_grazing_pressure = clampf(
		float(d.get("_lifetime_grazing_pressure", 0.0)), 0.0, 1.0)
	_heritable_palatability = clampf(
		float(d.get("_heritable_palatability", palatability)), 0.05, 1.0)
	_pollination_cooldown_s = maxf(
		0.0, float(d.get("_pollination_cooldown_s", 0.0)))
	_submersed_leaf_form = String(d.get("_submersed_leaf_form", _submersed_leaf_form))
	_heterophylly_applied = not not d.get("_heterophylly_applied", false)
	_bulb_buried = not not d.get("_bulb_buried", false)
	_dormant_timer = float(d.get("_dormant_timer", 0.0))
	_light_avg = float(d.get("_light_avg", _light_avg))
	_restore_leaf_light_doses(d.get("_leaf_light_doses", []))
	var saved_limits: Array = d.get("_stem_limit_history", [])
	if not saved_limits.is_empty():
		_stem_limit_history.resize(mini(saved_limits.size(), voxels.size()))
		for i in _stem_limit_history.size():
			var code: int = clampi(int(saved_limits[i]), 0, LIMIT_FACTOR_NAMES.size() - 1)
			_stem_limit_history[i] = code
			voxels[i].growth_limit_code = code
	_internode_extension_y = maxf(0.0, float(d.get("_internode_extension_y", 0.0)))
	_root_reserve = clampf(float(d.get("_root_reserve", 0.0)), 0.0, RESOURCE_RESERVOIR_CAP)
	_shoot_reserve = clampf(float(d.get("_shoot_reserve", 0.0)), 0.0, RESOURCE_RESERVOIR_CAP)
	_heteroblasty_adult = bool(d.get(
		"_heteroblasty_adult", heteroblasty_node > 0 and current_height >= heteroblasty_node))
	_reiterations_used = clampi(int(d.get("_reiterations_used", 0)), 0, reiteration_capacity)
	_damage_episode_active = bool(d.get("_damage_episode_active", false))
	_peak_biomass = maxi(int(d.get("_peak_biomass", current_height)), current_height)
	# Loaded plants are established — no emersed-form display. Setting to
	# 0 skips the size/color boost we apply to brand-new spawns.
	_emersed_remaining = 0.0
	_growth_load_hold_s = 0.35
	_reconcile_life_phase_from_geometry()


func _reconcile_life_phase_from_geometry() -> void:
	var top_y: float = global_position.y + float(current_height) * VOXEL_SIZE * 0.95
	if top_y > water_surface_y - 0.25:
		if life_phase < LifePhase.CANOPY:
			life_phase = LifePhase.CANOPY
			has_emerged = true
	elif life_phase >= LifePhase.CANOPY and top_y < water_surface_y - 0.6:
		life_phase = LifePhase.VEGETATIVE
		has_emerged = false


func _ready() -> void:
	_phase = float(get_instance_id() % 1000) * 0.013
	_world_pos = global_position
	# Pearling is lazy + shared — about 1/5 plants are eligible to allocate
	# a GPUParticles3D. Raised from 1/8 because the visible pearling stream
	# is one of the strongest "this tank is alive and oxygenating" cues, and
	# the global pearling_slot throttle in sim_driver keeps total particle
	# budget bounded regardless of how many plants are eligible.
	_pearling_eligible = (get_instance_id() % 5) == 0
	_pearling_opacity = randf_range(0.12, 0.28)
	_pearling_strength = randf_range(0.45, 1.0)
	_warm_start_growth_vitals()
	_apply_sway_personality()


func _warm_start_growth_vitals() -> void:
	_starch = maxf(_starch, 0.4)
	var sim_v: Node = _find_sim()
	if sim_v == null:
		return
	var w: Node = sim_v.get_parent()
	if w == null or not w.has_method("light_penetration_at"):
		return
	var dl: float = float(sim_v.daylight()) if sim_v.has_method("daylight") else 0.5
	var lp: float = float(w.light_penetration_at(_world_pos if _world_pos != Vector3.ZERO else global_position))
	_light_avg = maxf(_light_avg, lp * dl * 0.85)


func _softmin2(a: float, b: float, k: float = 0.12) -> float:
	var ea: float = exp(-clampf(a, 0.0, 1.0) / k)
	var eb: float = exp(-clampf(b, 0.0, 1.0) / k)
	return -k * log(ea + eb)


func _softmin_chain(factors: Array, k: float = 0.10) -> float:
	if factors.is_empty():
		return 1.0
	var acc: float = clampf(float(factors[0]), 0.0, 1.0)
	for i in range(1, factors.size()):
		acc = _softmin2(acc, clampf(float(factors[i]), 0.0, 1.0), k)
	return acc


func _shade_light_stack(light_pen: float) -> float:
	var shade_light: float = light_pen * _shade_mult
	if _floater_shade_melt_t > 8.0:
		shade_light *= lerpf(1.0, 0.62, clampf((_floater_shade_melt_t - 8.0) / 12.0, 0.0, 1.0))
	return clampf(shade_light, 0.22, 1.0)


func _compute_growth_rate(growth_nutrient: float, light_pen: float, sim_v: Node) -> Dictionary:
	var shade_light: float = _shade_light_stack(light_pen)
	var f_light: float = clampf(_light_avg / 0.48, 0.18, 1.0) * shade_light
	var f_nutrient: float = clampf(0.35 + 0.65 * growth_nutrient, 0.0, 1.0)
	var f_co2: float = 1.0
	if not is_epiphyte and co2_demand > 0.3 and sim_v != null \
			and sim_v.has_method("dissolved_co2_level"):
		var co2v: float = float(sim_v.dissolved_co2_level())
		f_co2 = clampf(co2v / (co2v + co2_demand * 0.5), 0.2, 1.0)
	var f_starch: float = lerpf(0.55, 1.0, clampf(_starch / 0.2, 0.0, 1.0))
	var f_transport: float = 1.0
	if vascular_transport_rate > 0.0:
		f_transport = clampf(_shoot_reserve / maxf(nutrient_demand, 0.001), 0.12, 1.0)
	var f_temp: float = 1.0
	if sim_v != null:
		var w_temp: Node = sim_v.get_parent()
		if w_temp != null and w_temp.has_method("effective_warmth_at"):
			var warmth: float = float(w_temp.effective_warmth_at(_world_pos))
			f_temp = clampf(1.0 - absf(warmth - temp_opt) * 1.4, 0.35, 1.15)
	var core: float = _softmin_chain([f_nutrient, f_light, f_co2, f_starch, f_temp, f_transport])
	var curve_mult: float = _species_growth_curve_multiplier()
	var effective_rate: float = growth_rate * core * curve_mult
	if sim_v != null and sim_v.has_method("sim_day"):
		var mature: float = clampf(float(sim_v.sim_day()) / 30.0, 0.0, 1.0)
		if growth_rate > 0.20 and not is_epiphyte and not is_carpet:
			effective_rate *= lerpf(1.25, 0.80, mature)
		elif is_epiphyte or is_carpet or growth_rate < 0.12:
			effective_rate *= lerpf(0.80, 1.20, mature)
	if health > MIN_HEALTH_FOR_FLOOR:
		effective_rate = maxf(effective_rate, GROWTH_FLOOR)
	var limiting: String = "balanced"
	var mins: Dictionary = {
		"light": f_light, "nutrient": f_nutrient, "co2": f_co2,
		"starch": f_starch, "temperature": f_temp,
		"transport": f_transport,
	}
	var worst: float = 2.0
	for key in mins:
		var v: float = float(mins[key])
		if v < worst:
			worst = v
			limiting = key
	var diag: Dictionary = {
		"effective_rate": effective_rate,
		"seconds_per_voxel": 1.0 / maxf(effective_rate, 1e-6),
		"nutrient_mult": growth_nutrient,
		"f_light": f_light,
		"f_co2": f_co2,
		"f_starch": f_starch,
		"f_temp": f_temp,
		"f_transport": f_transport,
		"growth_curve_mult": curve_mult,
		"limiting_factor": limiting,
		"shade_light": shade_light,
		"growth_progress": growth_progress,
		"health": health,
	}
	_growth_diag = diag
	return diag


func _species_growth_curve_multiplier() -> float:
	if growth_curve_acceleration <= 0.0:
		return 1.0
	var maturity: float = clampf(float(current_height) / float(maxi(1, max_height)), 0.0, 1.0)
	var sigmoid: float = 1.0 / (1.0 + exp(-growth_curve_acceleration * (maturity - 0.5)))
	return lerpf(growth_curve_establishment, growth_curve_plateau, sigmoid)


func get_growth_inspector() -> Dictionary:
	var label: String = common_name if common_name != "" else plant_name
	var lim: String = String(_growth_diag.get("limiting_factor", "balanced"))
	var lim_text: String = lim
	match lim:
		"light": lim_text = "light-limited"
		"nutrient": lim_text = "needs richer substrate"
		"co2": lim_text = "CO₂-starved"
		"starch": lim_text = "building reserves"
		"temperature": lim_text = "temperature-stressed"
		"transport": lim_text = "vascular capacity limited"
	return {
		"species": label,
		"health": health,
		"growth_pct": growth_progress * 100.0,
		"limiting_factor": lim,
		"limiting_text": lim_text,
		"diag": _growth_diag.duplicate(),
		"stem_history": get_stem_growth_history(),
	}


func get_stem_growth_history() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in voxels.size():
		var code: int = voxels[i].growth_limit_code
		out.append({
			"height": voxels[i].local_pos.y,
			"code": code,
			"factor": LIMIT_FACTOR_NAMES[clampi(code, 0, LIMIT_FACTOR_NAMES.size() - 1)],
		})
	return out


func _stem_history_snapshot() -> Array:
	var out: Array = []
	for handle in voxels:
		out.append(handle.growth_limit_code)
	return out


func _current_limit_code() -> int:
	var factor: String = String(_growth_diag.get("limiting_factor", "balanced"))
	var index: int = LIMIT_FACTOR_NAMES.find(factor)
	return index if index >= 0 else 0


func _apply_sway_personality() -> void:
	# Per-habit motion so the tank isn't one uniform mass (#29 / #32 / #33).
	# Swords stay almost stiff; stems bend mid-column; carpets shimmer; ribbons
	# tip-weight without thrashing.
	var amp: float = sway_amplitude
	var flutter: float = 0.028
	var tip_mult: float = 1.55
	var flutter_speed: float = 2.4
	var sway_speed: float = 1.55
	match leaf_form:
		"paddle", "spade", "lobed", "oval":
			# Swords / crypts — almost stiff.
			amp = minf(amp, 0.08)
			flutter = 0.012
			tip_mult = 1.15
			sway_speed = 1.1
		"lance", "pinnate", "fingered":
			# Stem plants — flexible mid-column, soft tip.
			amp = clampf(amp, 0.12, 0.20)
			flutter = 0.022
			tip_mult = 1.65
			sway_speed = 1.35
		"ribbon":
			# Vallisneria — clear tip-weighted curve, no whip.
			amp = maxf(amp, 0.18)
			flutter = 0.018
			tip_mult = 2.05 if max_height >= 10 else 1.75
			sway_speed = 1.25
		"needle", "downy":
			# Fine leaves — lawn shimmer (#33).
			amp = minf(maxf(amp, 0.06), 0.10)
			flutter = 0.055
			flutter_speed = 4.2
			tip_mult = 1.25
			sway_speed = 2.0
		"column":
			amp = minf(amp, 0.09)
			flutter = 0.016
			tip_mult = 1.35
		"round", "four_leaf", "starburst":
			amp = minf(amp, 0.07)
			flutter = 0.014
			tip_mult = 1.1
	if is_carpet:
		amp = minf(maxf(amp, 0.05), 0.09)
		flutter = 0.06
		flutter_speed = 4.6
		tip_mult = 1.05
		sway_speed = 2.2
	if is_epiphyte:
		# Cling to host — leaf flutter, almost no root lean.
		amp = minf(amp, 0.06)
		flutter = maxf(flutter, 0.04)
		flutter_speed = maxf(flutter_speed, 3.4)
		tip_mult = minf(tip_mult, 1.2)
		sway_speed = 1.4
	var height_w: float = lerpf(0.85, 1.18, float(current_height) / float(maxi(max_height, 1)))
	if life_phase == LifePhase.SENESCENT or is_dying:
		amp *= 0.55
		flutter *= 0.7
		height_w *= 0.72
	# Tip bloom present — calm the Multimesh tip under the flower so it
	# doesn't thrash beneath a stabilizing bloom.
	if has_flower and flower_stage != FlowerStage.NONE:
		amp *= 0.72
		tip_mult *= 0.55
		flutter *= 0.65
	tip_mult *= height_w
	# Global calm: alive but smooth — lazy current, not thrash.
	const CALM_AMP: float = 0.62
	const CALM_FLUTTER: float = 0.55
	const CALM_TIP: float = 0.78
	const CALM_SPEED: float = 0.72
	if _foliage_mat != null:
		_foliage_mat.set_shader_parameter("sway_amplitude", amp * CALM_AMP)
		_foliage_mat.set_shader_parameter("flutter_amplitude", flutter * CALM_FLUTTER)
		_foliage_mat.set_shader_parameter("tip_sway_mult", tip_mult * CALM_TIP)
		_foliage_mat.set_shader_parameter("sway_speed", sway_speed / height_w * CALM_SPEED)
		_foliage_mat.set_shader_parameter("flutter_speed", flutter_speed)
		_foliage_mat.set_shader_parameter("sss_strength", 0.42)
		var hue_nudge: float = fposmod(float(get_instance_id()) * 0.017, 1.0) * 0.08 - 0.04
		_foliage_mat.set_shader_parameter("palette_hue_shift", hue_nudge)


func _visual_youth_scale() -> float:
	var cfg: Node = get_node_or_null("/root/TankConfig")
	var youth: float = 1.0
	if cfg != null and String(cfg.get("cycle_start_mode")) == "fresh":
		youth = clampf(float(cfg.get("plant_youth_scale")), 0.25, 1.0)
	var maturity: float = clampf(float(current_height) / float(maxi(1, max_height)), 0.0, 1.0)
	return lerpf(youth, 1.0, pow(maturity, 0.55))


func _release_brush_bubbles() -> void:
	if not _pearling_eligible:
		return
	if _pearling_particles == null:
		_setup_pearling()
	if _pearling_particles != null:
		_pearling_particles.restart()
		_pearling_particles.emitting = true


func _spawn_growth_sparkle() -> void:
	var spark := MeshInstance3D.new()
	spark.mesh = VoxelMat.get_box(Vector3(0.06, 0.06, 0.06))
	var col := Color8(180, 240, 150, 0.9)
	spark.material_override = VoxelMat.make_foliage(col)
	spark.position = Vector3(0, _get_stem_top() + VOXEL_SIZE * 0.2, 0)
	add_child(spark)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(spark, "position", spark.position + Vector3(0, 0.12, 0), 0.45)
	var mat: ShaderMaterial = spark.material_override as ShaderMaterial
	if mat != null:
		var end := Color(col.r, col.g, col.b, 0.0)
		tw.tween_method(func(c: Color): mat.set_shader_parameter("albedo", c), col, end, 0.45)
	tw.chain().tween_callback(spark.queue_free)


func _tick_plant_mood(dt: float) -> void:
	if is_dying or _melt_active:
		return
	_mood_pulse_t += dt
	if health > 0.82 and _mood_pulse_t > randf_range(18.0, 32.0):
		_mood_pulse_t = 0.0
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector3.ONE * 1.03, 0.8) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "scale", Vector3.ONE, 1.2) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	elif health < 0.35:
		rotation.x = lerpf(rotation.x, 0.08, dt * 0.6)


func apply_gust_tilt(vec: Vector2, strength: float) -> void:
	wake_plant("environment")
	_gust_tilt = (_gust_tilt + vec * strength).limit_length(0.12)


func _update_height_ghost_marker() -> void:
	if _height_ghost_y < 0.0:
		return
	if _height_ghost_marker == null:
		_height_ghost_marker = MeshInstance3D.new()
		_height_ghost_marker.mesh = VoxelMat.get_box(Vector3(0.22, 0.04, 0.22))
		var ghost_mat: ShaderMaterial = VoxelMat.make_foliage(Color(0.5, 0.8, 0.5, 0.22))
		_height_ghost_marker.material_override = ghost_mat
		add_child(_height_ghost_marker)
	_height_ghost_marker.position = Vector3(0, _height_ghost_y - global_position.y, 0)


func _build_initial_roots() -> void:
	var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
	var root_ramp: Array = [ramp[0].darkened(0.3), ramp[0].darkened(0.15)]
	var initial_roots: int = _rng_range(2, mini(3, _max_roots))
	for i in initial_roots:
		_add_root(root_ramp)


# Epiphyte holdfast / rhizome: real anubias, buce, java fern, bolbitis
# grow as a horizontal rhizome along a wood/rock surface with leaves
# emerging perpendicular every ~voxel and pale white-cream root hairs
# anchoring the rhizome to the host. We build the rhizome as a short
# voxel trunk extending along the X axis at base, with the root hairs
# tucked under it. The leaf-spawn path in _grow_shaped_leaf reads
# _rhizome_attach_points to position leaves along the trunk instead of
# stacking them on a single column.
var _rhizome_attach_points: PackedVector3Array = PackedVector3Array()
var _rhizome_voxels: Array[MeshInstance3D] = []
# Direction the rhizome creeps along its host, and how far it has got. An
# epiphyte does not gain height like a stem plant — it travels. Keeping the
# heading lets growth extend the same runner instead of rebuilding it.
var _rhizome_dir: Vector3 = Vector3.RIGHT
var _rhizome_segments: int = 0
const RHIZOME_MAX_SEGMENTS: int = 14
const RHIZOME_STEP: float = VOXEL_SIZE * 0.55

func _build_holdfast_anchor() -> void:
	var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
	# Rhizome length scales with max_height — small petite anubias get 3-4
	# segments, full-size barteri get 6-7. Cap so it doesn't run past the
	# host driftwood voxel.
	# Cast through float to skip the int-division-loses-precision warning.
	var rhizome_len: int = clampi(int(float(max_height) / 3.0) + 2, 3, 7)
	# Rhizome direction: a randomized axis in the XZ plane so multiple
	# epiphytes on the same wood look like they spread in different
	# directions, not all parallel.
	var dir_angle: float = randf() * TAU
	var dir: Vector3 = Vector3(cos(dir_angle), 0.0, sin(dir_angle))
	_rhizome_dir = dir
	var rhizome_color: Color = (ramp[0] as Color).darkened(0.15)
	# Pale root-hair color — slightly cream-tinted off-white, the visible
	# signal that "this plant has rhizome roots on display."
	var hair_color: Color = Color(0.86, 0.84, 0.74)
	for i in rhizome_len:
		# Trunk segment.
		var seg := MeshInstance3D.new()
		seg.mesh = VoxelMat.get_box(Vector3(
			VOXEL_SIZE * 0.55, VOXEL_SIZE * 0.32, VOXEL_SIZE * 0.45))
		seg.material_override = VoxelMat.make_foliage(rhizome_color)
		var seg_pos: Vector3 = dir * float(i) * VOXEL_SIZE * 0.55
		seg.position = seg_pos
		add_child(seg)
		_rhizome_voxels.append(seg)
		# Leaf attachment point — store for the leaf-spawn path.
		_rhizome_attach_points.append(seg_pos)
		# Root hairs underneath each segment — 2 tiny pale voxels splayed
		# outward + downward. These are the iconic "wispy white root hairs"
		# that hobbyists recognize as "this is a healthy rhizome plant."
		for side in [-1.0, 1.0]:
			var hair := MeshInstance3D.new()
			hair.mesh = VoxelMat.get_box(Vector3(
				VOXEL_SIZE * 0.10, VOXEL_SIZE * 0.18, VOXEL_SIZE * 0.10))
			hair.material_override = VoxelMat.make_foliage(hair_color)
			# Cross direction of the rhizome so hairs splay sideways.
			var cross: Vector3 = Vector3(-dir.z, 0.0, dir.x)
			hair.position = seg_pos + cross * side * VOXEL_SIZE * 0.30 \
				+ Vector3(0.0, -VOXEL_SIZE * 0.20, 0.0)
			# Tilt the hair so it looks pulled down by gravity.
			hair.rotation.z = -side * 0.35
			add_child(hair)
			root_voxels.append(hair)
		# Tiny anchor stub between segment and host surface.
		var anchor := MeshInstance3D.new()
		anchor.mesh = VoxelMat.get_box(Vector3(
			VOXEL_SIZE * 0.16, VOXEL_SIZE * 0.12, VOXEL_SIZE * 0.16))
		anchor.material_override = VoxelMat.make_foliage(hair_color.darkened(0.20))
		anchor.position = seg_pos + Vector3(0.0, -VOXEL_SIZE * 0.30, 0.0)
		add_child(anchor)
		root_voxels.append(anchor)
	_rhizome_segments = rhizome_len
	_root_count = root_voxels.size()


# This individual's persistent rhizome curl, radians per segment. Always at
# least RHIZOME_CURL_MIN so the runner arcs across its host rather than
# occasionally drawing a straight line.
const RHIZOME_CURL_MIN: float = 0.07
const RHIZOME_CURL_MAX: float = 0.19


func _rhizome_curl() -> float:
	var h: int = (asymmetry_seed ^ 0x5F3759DF) & 0x7FFFFFFF
	var mag: float = lerpf(RHIZOME_CURL_MIN, RHIZOME_CURL_MAX,
		float(h % 1000) / 1000.0)
	return mag if (h & 1) == 0 else -mag


# Extend the rhizome one segment further along the host. Called from growth
# instead of adding stem height: a rhizome plant answers good conditions by
# creeping further across its wood or rock, which is what makes an old
# anubias sprawl over a branch instead of standing taller. The heading drifts
# slightly each step so the runner curves with the surface rather than
# marching in a straight line.
func _extend_rhizome() -> bool:
	if _rhizome_segments >= RHIZOME_MAX_SEGMENTS:
		return false
	var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
	var rhizome_color: Color = (ramp[0] as Color).darkened(0.15)
	var hair_color: Color = Color(0.86, 0.84, 0.74)
	# Curve the runner. A symmetric jitter alone can land on ~0 for a given
	# seed, which produces a rhizome marching in a dead-straight line — the
	# exact machined look this is meant to avoid. So each plant gets a
	# persistent curl (direction and magnitude from its seed, with a floor)
	# and the jitter only wobbles around it. Deterministic per plant, so a
	# reload retraces the same path.
	var bend: float = _rhizome_curl() + _node_jitter(_rhizome_segments, 0.10)
	_rhizome_dir = _rhizome_dir.rotated(Vector3.UP, bend).normalized()
	var seg_pos: Vector3 = _clamp_growth_offset(
		_rhizome_dir * float(_rhizome_segments) * RHIZOME_STEP)
	var seg := MeshInstance3D.new()
	seg.mesh = VoxelMat.get_box(Vector3(
		VOXEL_SIZE * 0.55, VOXEL_SIZE * 0.32, VOXEL_SIZE * 0.45))
	seg.material_override = VoxelMat.make_foliage(rhizome_color)
	seg.position = seg_pos
	add_child(seg)
	_rhizome_voxels.append(seg)
	_rhizome_attach_points.append(seg_pos)
	var cross: Vector3 = Vector3(-_rhizome_dir.z, 0.0, _rhizome_dir.x)
	for side in [-1.0, 1.0]:
		var hair := MeshInstance3D.new()
		hair.mesh = VoxelMat.get_box(Vector3(
			VOXEL_SIZE * 0.10, VOXEL_SIZE * 0.18, VOXEL_SIZE * 0.10))
		hair.material_override = VoxelMat.make_foliage(hair_color)
		hair.position = seg_pos + cross * side * VOXEL_SIZE * 0.30 \
			+ Vector3(0.0, -VOXEL_SIZE * 0.20, 0.0)
		hair.rotation.z = -side * 0.35
		add_child(hair)
		root_voxels.append(hair)
	_rhizome_segments += 1
	_root_count = root_voxels.size()
	return true


func _add_root(root_ramp: Array) -> void:
	if _root_count >= _max_roots:
		return
	# Distribute angles around the full circle. As _root_count grows past
	# the original cap of 5, subsequent roots fan out into the gaps via
	# the golden-angle stride so they don't stack on the radial axes the
	# first few roots already claimed. This is the visible "established
	# plant has a denser root mat" effect.
	var angle: float
	angle = _nutrient_seeking_root_angle()
	angle += randf_range(-0.4, 0.4)  # jitter
	# Lateral spread: later-grown roots reach further from the stem,
	# giving the mature plant a wider root halo just under the substrate
	# instead of all roots stacking under the trunk.
	var lateral_bias: float = 1.0 + clampf(float(_root_count) / 8.0, 0.0, 0.8)
	var depth: int = _rng_range(2, 4)
	var root_color: Color = root_ramp[0] if root_ramp.size() > 0 else Color8(60, 45, 30)
	var root_light: Color = root_ramp[1] if root_ramp.size() > 1 else Color8(80, 60, 40)
	for j in depth:
		var t: float = float(j) / float(depth)
		var spread: float = t * VOXEL_SIZE * 1.2 * lateral_bias
		var mi := MeshInstance3D.new()
		var taper: float = 1.0 - t * 0.4
		mi.mesh = VoxelMat.get_box(Vector3(
			VOXEL_SIZE * 0.22 * taper,
			VOXEL_SIZE * 0.55,
			VOXEL_SIZE * 0.22 * taper,
		))
		mi.material_override = VoxelMat.make_foliage(root_color.lerp(root_light, t * 0.3))
		mi.position = Vector3(
			cos(angle) * spread,
			-float(j) * VOXEL_SIZE * 0.5,
			sin(angle) * spread,
		)
		add_child(mi)
		root_voxels.append(mi)
		# Root-hair fuzz — 2 pale horizontal sub-voxels at the anchor tip.
		if j == depth - 1:
			var cross_x: float = cos(angle + PI * 0.5)
			var cross_z: float = sin(angle + PI * 0.5)
			for side in [-1.0, 1.0]:
				var hair := MeshInstance3D.new()
				hair.mesh = VoxelMat.get_box(Vector3(
					VOXEL_SIZE * 0.12, VOXEL_SIZE * 0.07, VOXEL_SIZE * 0.12))
				hair.material_override = VoxelMat.make_foliage(root_light.lightened(0.12))
				hair.position = mi.position + Vector3(
					cross_x * side * VOXEL_SIZE * 0.14,
					-VOXEL_SIZE * 0.06,
					cross_z * side * VOXEL_SIZE * 0.14,
				)
				add_child(hair)
				root_voxels.append(hair)
	_root_count += 1


func _nutrient_seeking_root_angle(substrate_override: SubstrateGrid = null) -> float:
	var fallback: float = float(_root_count) / 5.0 * TAU \
		if _root_count < 5 else float(_root_count) * 2.39996
	if root_foraging <= 0.0:
		return fallback
	var substrate: SubstrateGrid = substrate_override
	if substrate == null:
		var sim: Node = _find_sim()
		if sim == null or sim.get("substrate") == null:
			return fallback
		substrate = sim.substrate
	var center: float = substrate.get_at(_world_pos)
	var best_value: float = center
	var best_angle: float = fallback
	for i in 8:
		var angle: float = float(i) / 8.0 * TAU
		var probe: Vector3 = _world_pos + Vector3(cos(angle), 0.0, sin(angle)) * substrate.cell_size
		var value: float = substrate.get_at(probe)
		if value > best_value:
			best_value = value
			best_angle = angle
	if best_value - center < 0.015:
		return fallback
	return lerp_angle(fallback, best_angle, root_foraging)


func _ensure_shared_pearling_assets() -> void:
	if _shared_pearling_material != null and _shared_pearling_mesh != null \
			and _shared_pearling_mesh_medium != null:
		return
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	# Slower initial velocity so bubbles linger on leaves before ascending —
	# the giveaway of real planted-tank pearling is the brief "stuck on the
	# leaf" moment before the bubble breaks free. Combined with a wider
	# spread so a few bubbles drift sideways and bounce off neighbouring
	# voxels rather than all rocketing straight up.
	pm.initial_velocity_min = 0.06
	pm.initial_velocity_max = 0.22
	pm.gravity = Vector3(0, 0.10, 0)
	pm.spread = 22.0
	# Gentle turbulence so rising bubbles waver and weave instead of tracking
	# perfectly straight lines — the believable "wobble" of real pearling.
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.18
	pm.turbulence_noise_scale = 1.6
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.18
	# ±1px lateral wobble as bubbles rise (style guide §4, #135).
	pm.orbit_velocity_min = 0.14
	pm.orbit_velocity_max = 0.42
	# Tiny bubbles so the palette quantizer locks them into single sharp
	# pixel specks rather than soft blobs. After quantization a 0.06 scale
	# bubble at typical camera distance reads as a 1-2 pixel highlight —
	# exactly the classic pixel-art pearling look.
	# Style-guide bubble ladder: micro (pass 1) + medium (pass 2 when pearling hard).
	pm.scale_min = 0.06
	pm.scale_max = 0.12
	# Wider emission column so bubbles appear along the whole canopy rather
	# than only at the topmost tip. _setup_pearling positions the emitter
	# at the stem top; the sphere radius extends down into the foliage.
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.32
	var alpha_curve := CurveTexture.new()
	var curve := Curve.new()
	# Hold the "stuck on leaf" frame longer (high alpha plateau between 0.15
	# and 0.8 of lifetime) before the bubble fades as it ascends past the
	# canopy. Two distinct breath-out beats per emit cycle.
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.12, 0.55))
	curve.add_point(Vector2(0.55, 0.42))
	curve.add_point(Vector2(0.85, 0.22))
	curve.add_point(Vector2(1.0, 0.0))
	alpha_curve.curve = curve
	pm.alpha_curve = alpha_curve
	_shared_pearling_material = pm
	var bubble_mesh := SphereMesh.new()
	bubble_mesh.radius = 0.012
	bubble_mesh.height = 0.024
	bubble_mesh.radial_segments = 4
	bubble_mesh.rings = 2
	bubble_mesh.material = VoxelMat.make_bubble(
		Color(1.06, 1.12, 1.18, 0.30), 1.28)
	_shared_pearling_mesh = bubble_mesh
	var medium_mesh := SphereMesh.new()
	medium_mesh.radius = 0.032
	medium_mesh.height = 0.064
	medium_mesh.radial_segments = 4
	medium_mesh.rings = 2
	medium_mesh.material = VoxelMat.make_bubble(
		Color(1.08, 1.14, 1.20, 0.26), 1.32)
	_shared_pearling_mesh_medium = medium_mesh


func _configure_pearling_emitter(particles: GPUParticles3D) -> void:
	_ensure_shared_pearling_assets()
	if particles.process_material != _shared_pearling_material:
		particles.process_material = _shared_pearling_material
	var bubble_mesh: SphereMesh = _shared_pearling_mesh.duplicate()
	var bubble_mat: ShaderMaterial = bubble_mesh.material.duplicate()
	bubble_mat.set_shader_parameter("bubble_color", Color(
		randf_range(0.88, 0.96), randf_range(0.93, 0.99), 1.0, _pearling_opacity))
	bubble_mesh.material = bubble_mat
	particles.draw_pass_1 = bubble_mesh
	particles.draw_passes = 1


func _setup_pearling() -> void:
	# Pearling = O2 micro-bubbles clinging to leaves in bright light.
	if _pearling_particles != null or not _pearling_eligible:
		return
	var sim_driver: Node = _find_sim()
	var w: Node = sim_driver.get_parent() if sim_driver != null else null
	if w != null and w.has_method("claim_pearling_emitter"):
		_pearling_particles = w.claim_pearling_emitter(self)
		if _pearling_particles == null:
			return
		_configure_pearling_emitter(_pearling_particles)
		return
	_ensure_shared_pearling_assets()
	_pearling_particles = GPUParticles3D.new()
	_pearling_particles.name = "Pearling"
	_pearling_particles.emitting = false
	# Slightly denser stream than the old amount=3 — the per-particle scale
	# dropped to 0.06..0.18 so total visible pixel coverage stays modest,
	# but the eye reads a 6-bubble fountain as "really pearling" where 3
	# bubbles felt incidental.
	_pearling_particles.amount = 6
	_pearling_particles.lifetime = randf_range(3.4, 5.0)
	_pearling_particles.local_coords = false
	_pearling_particles.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 8, 4))
	_configure_pearling_emitter(_pearling_particles)
	add_child(_pearling_particles)


func _apply_default_growth_strategy() -> void:
	# Habit-aware flowering: carpets / fine needles / plain columns stay leafy;
	# emergents, crypts/paddles, and ribbons that reach the surface may bloom.
	match leaf_form:
		"paddle", "spade", "lobed", "oval":
			# Crypts / swords — rare spathe blooms, not tip daisies.
			emergent_growth = false
			uses_flowering = true
		"needle", "downy":
			emergent_growth = false
			uses_flowering = false
		"column":
			emergent_growth = true
			uses_flowering = false
		"ribbon":
			emergent_growth = true
			uses_flowering = true
		"lance", "pinnate", "fingered":
			emergent_growth = true
			# Stem plants flower as a rare canopy event, not a permanent hat.
			uses_flowering = true
		_:
			emergent_growth = true
	if is_carpet:
		uses_flowering = false
		emergent_growth = false
	if species_id.contains("cattail"):
		uses_flowering = true
		emergent_growth = true


# Snap the tip bloom onto the real stem tip (XZ wander included). Ride the
# plant lean with the tip — do not counter-rotate, or petals float off-axis.
func _stabilize_flower_against_lean() -> void:
	if _flower_node == null or not is_instance_valid(_flower_node):
		return
	if flower_stage == FlowerStage.NONE:
		return
	_flower_node.rotation = Vector3.ZERO
	_flower_node.position = _tip_bloom_local_pos()


# Local position of the growing tip — last stem voxel when present, else the
# lean-aware height used by growth. Nest slightly into the tip so the bloom
# reads as attached, not hovering above a thin green line.
func _tip_bloom_local_pos() -> Vector3:
	for i in range(voxels.size() - 1, -1, -1):
		var tip: VoxelBatch.Handle = voxels[i]
		if tip != null and tip.alive:
			return tip.local_pos + Vector3(0.0, VOXEL_SIZE * 0.12, 0.0)
	var rel: float = 1.0
	var lean: Vector2 = _stem_lean_offset(rel)
	return Vector3(lean.x, _get_stem_top() - VOXEL_SIZE * 0.05, lean.y)


func _at_surface_cap() -> bool:
	return top_world_y() >= water_surface_y - SURFACE_MARGIN


func _enter_canopy() -> void:
	if life_phase == LifePhase.CANOPY:
		return
	life_phase = LifePhase.CANOPY
	has_emerged = true
	max_height = current_height
	_canopy_timer = 0.0
	# Heterophylly (#1): swap to emersed leaf morphology at surface.
	if not _heterophylly_applied and emersed_leaf_form != "" \
			and emersed_leaf_form != _submersed_leaf_form:
		leaf_form = emersed_leaf_form
		leaf_thickness = minf(leaf_thickness + 0.15, 1.0)
		_heterophylly_applied = true
	_spawn_meniscus_break()
	if uses_flowering and flower_stage == FlowerStage.NONE:
		_begin_flowering()
	elif not uses_flowering and has_method("_spawn_canopy_propagule"):
		call("_spawn_canopy_propagule")
	_apply_canopy_layover()


func _stop_canopy_bob() -> void:
	if _canopy_bob_tween != null:
		if is_instance_valid(_canopy_bob_tween):
			_canopy_bob_tween.kill()
		_canopy_bob_tween = null


func _apply_canopy_layover() -> void:
	# REAL_TANK_FIDELITY #113 — valli / ribbon blades that reach the surface
	# bend at the waterline and lie along it for a long run, instead of a
	# short tip lean. Other emergents keep the lighter meniscus layover.
	if voxels.is_empty():
		return
	_stop_canopy_bob()
	var surface_local_y: float = water_surface_y - global_position.y
	var ribbon: bool = leaf_form == "ribbon" or species_id.contains("valli") \
		or species_id.contains("vallisneria") or species_id.contains("cattail")
	var lay_n: int = mini(voxels.size(), 14 if ribbon else 3)
	var lie_dir: float = 1.0 if fmod(absf(global_position.x * 12.7 + global_position.z * 3.1), 1.0) > 0.5 else -1.0
	for i in lay_n:
		var vi: int = voxels.size() - 1 - i
		var v: VoxelBatch.Handle = voxels[vi]
		if v == null or not v.alive:
			continue
		if not ribbon and v.local_pos.y < surface_local_y - VOXEL_SIZE * 0.45:
			continue
		var t: float = float(i) / float(maxi(1, lay_n - 1))
		var lean: float
		var along: float
		if ribbon:
			# Bend to nearly horizontal, then slide along the surface.
			lean = lerpf(0.35, 1.45, t)
			along = VOXEL_SIZE * lerpf(0.15, 2.8, t * t)
		else:
			lean = lerpf(0.22, 0.68, t)
			along = VOXEL_SIZE * lerpf(0.06, 0.14, t)
		var xform: Transform3D = v.transform
		xform.basis = Basis(Vector3.RIGHT, -lean * lie_dir) * xform.basis
		var target_y: float = surface_local_y + VOXEL_SIZE * lerpf(0.02, 0.10, t) if ribbon \
			else v.local_pos.y + VOXEL_SIZE * lerpf(0.06, 0.14, t)
		xform.origin.y = target_y
		if ribbon:
			xform.origin.x += along * lie_dir
			xform.basis = Basis(Vector3.FORWARD, lerpf(0.0, 0.35, t) * lie_dir) * xform.basis
		v.set_transform(xform)
	if _stem_batch != null:
		_stem_batch.flush()


func _spawn_meniscus_break() -> void:
	# 1–2 emergent stem voxels above the meniscus — wet sheen read.
	if not emergent_growth:
		return
	var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
	var surface_local_y: float = water_surface_y - global_position.y
	var stem_top: float = _get_stem_top()
	if stem_top >= surface_local_y + VOXEL_SIZE * 1.6:
		return
	var break_count: int = 2 + (1 if randf() < 0.35 else 0)
	var wet_col: Color = (ramp[4] if ramp.size() > 4 else ramp[-1] as Color).lightened(0.16)
	for i in break_count:
		var y: float = maxf(stem_top, surface_local_y - VOXEL_SIZE * 0.12) \
			+ float(i + 1) * VOXEL_SIZE * 0.82
		var mi := MeshInstance3D.new()
		mi.mesh = VoxelMat.get_box(Vector3(
			VOXEL_SIZE * (0.88 if i < break_count - 1 else 0.96),
			VOXEL_SIZE * (0.88 if i < break_count - 1 else 1.05),
			VOXEL_SIZE * (0.88 if i < break_count - 1 else 0.96)))
		mi.material_override = VoxelMat.make_foliage(wet_col)
		if i == break_count - 1:
			var rim: ShaderMaterial = (mi.material_override as ShaderMaterial).duplicate()
			rim.set_shader_parameter("color_vibrancy", 1.42)
			mi.material_override = rim
		mi.position = Vector3(
			randf_range(-VOXEL_SIZE * 0.06, VOXEL_SIZE * 0.06),
			y,
			randf_range(-VOXEL_SIZE * 0.06, VOXEL_SIZE * 0.06),
		)
		_register_stem_voxel(mi)
		current_height += 1


func _enter_senescence() -> void:
	if life_phase == LifePhase.SENESCENT or is_dying:
		return
	if dormancy_type != PlantGenome.DORMANCY_NONE:
		_enter_dormant_bulb()
		return
	life_phase = LifePhase.SENESCENT
	sway_amplitude *= 0.42
	_apply_sway_personality()
	if _pearling_active and _pearling_particles != null:
		_pearling_active = false
		_pearling_particles.emitting = false
		if _pearling_particles.draw_passes > 1:
			_pearling_particles.draw_passes = 1
	_begin_dying()


func _finish_reproduction_cycle() -> void:
	if monocarpic:
		_enter_senescence()
	else:
		has_flower = false
		flower_stage = FlowerStage.NONE
		_canopy_timer = 0.0
		_seeds_cast_this_cycle = 0


func _grow_one() -> bool:
	if current_height >= max_height:
		return false
	if emergent_growth and _at_surface_cap():
		return false
	if is_dying or _melt_active:
		return false

	var rel: float = float(current_height) / float(maxi(1, max_height - 1))
	var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
	var age_frac: float = 0.0  # new growth = age 0
	# Etiolation is applied only to tissue placed from this point onward.
	# Existing handles are never transformed, so a light change cannot teleport
	# a mature stem. Old genomes have sensitivity=0 and retain exact spacing.
	var etiolation: float = _current_etiolation()
	var base_leaf_scale: float = leaf_size_mult
	var base_leaf_form: String = leaf_form
	if heteroblasty_node > 0:
		_heteroblasty_adult = _heteroblasty_adult or current_height >= heteroblasty_node
		var stage_form: String = adult_leaf_form if _heteroblasty_adult else juvenile_leaf_form
		if stage_form != "":
			leaf_form = stage_form
	leaf_size_mult *= lerpf(1.0, 0.62, etiolation)

	# Apply health-based color shift.
	var effective_ramp: Array = ramp
	if _health_smooth < 0.7:
		effective_ramp = _build_stressed_ramp(ramp)
	# Red intensification — plants with red_potential > 0 shift their bright
	# half of the ramp toward red/orange/magenta as light + CO2 + low-N drive
	# anthocyanin synthesis in real life. The visible result is the
	# "advanced planted tank" look: Rotala H'ra tips going orange, Ludwigia
	# Super Red staying solid red, Alternanthera reineckii blushing pink.
	if red_potential > 0.0:
		effective_ramp = _red_boosted_ramp(effective_ramp)

	# Tropism vector field (#1): light + up + flow → lateral placement lean.
	var photo_offset: Vector2 = _tropism_lateral_offset()

	# Trim response: if a recent nibble cut the top off, this growth tick
	# spawns a side shoot from the cut node instead of resuming vertical
	# growth. The lateral cluster reads as the plant pushing a branch
	# where its apical bud was lost. current_height is NOT incremented —
	# we let the main stem resume from the next tick.
	if _reiteration_pending_node >= 0:
		_grow_side_shoot_at(effective_ramp, _reiteration_pending_node, photo_offset)
		_reiteration_pending_node = -1
		leaf_size_mult = base_leaf_scale
		leaf_form = base_leaf_form
		return true
	if not _pending_trim_nodes.is_empty():
		var cut_y: int = _pending_trim_nodes.pop_front()
		_grow_side_shoot_at(effective_ramp, cut_y, photo_offset)
		leaf_size_mult = base_leaf_scale
		leaf_form = base_leaf_form
		return true

	match leaf_form:
		"paddle":
			_grow_paddle_leaf(effective_ramp, age_frac, rel, photo_offset)
		"ribbon":
			_grow_ribbon_leaf(effective_ramp, age_frac, rel, photo_offset)
		"lance":
			_grow_lance_pair(effective_ramp, age_frac, rel, photo_offset)
		"needle":
			_grow_needle_leaf(effective_ramp, age_frac, rel, photo_offset)
		"spade":
			_grow_shaped_leaf(effective_ramp, age_frac, rel, photo_offset, "spade")
		"cordate":
			_grow_shaped_leaf(effective_ramp, age_frac, rel, photo_offset, "cordate")
		"pinnate":
			_grow_shaped_leaf(effective_ramp, age_frac, rel, photo_offset, "pinnate")
		"starburst":
			_grow_shaped_leaf(effective_ramp, age_frac, rel, photo_offset, "starburst")
		"four_leaf":
			_grow_shaped_leaf(effective_ramp, age_frac, rel, photo_offset, "four_leaf")
		"fingered":
			_grow_shaped_leaf(effective_ramp, age_frac, rel, photo_offset, "fingered")
		"downy":
			_grow_shaped_leaf(effective_ramp, age_frac, rel, photo_offset, "downy")
		"round":
			_grow_shaped_leaf(effective_ramp, age_frac, rel, photo_offset, "round")
		"oval":
			_grow_shaped_leaf(effective_ramp, age_frac, rel, photo_offset, "oval")
		"lobed":
			_grow_shaped_leaf(effective_ramp, age_frac, rel, photo_offset, "lobed")
		_:
			_grow_column_voxel(effective_ramp, rel, photo_offset)
	leaf_size_mult = base_leaf_scale
	leaf_form = base_leaf_form
	# Morphological elaboration from lineage + health:
	# mature, thriving lineages occasionally add accessory modules
	# (side fronds / branchlets / nodules) so architecture complexity
	# becomes visibly heritable over short runs.
	if generation >= 2 and _health_smooth > 0.58:
		var evo_chance: float = clampf(0.07 + float(generation) * 0.015, 0.07, 0.24)
		if randf() < evo_chance:
			_add_evolutionary_accessory(effective_ramp, rel, photo_offset)

	current_height += 1
	_peak_biomass = maxi(_peak_biomass, biomass())
	if _damage_episode_active and biomass() >= int(float(_peak_biomass) * 0.9):
		_damage_episode_active = false
	_internode_extension_y += VOXEL_SIZE * 0.65 * etiolation
	_rebuild_auxin_profile()
	_cast_root_shadow()

	# Root growth: add a root every 3-4 stem voxels. As the plant matures
	# (current_height climbs), bump the root cap so the root mat keeps
	# spreading laterally — established planted-tank specimens visibly
	# carpet the substrate under their stem with roots, not just have
	# a tight bundle directly below.
	_root_growth_counter += 1
	# Epiphytes spend growth travelling, not rooting: every third node the
	# rhizome creeps one more segment across its host, so a mature anubias
	# sprawls along the branch it was tied to instead of piling leaves on one
	# spot. Once the runner hits its span it goes back to thickening up.
	if is_epiphyte:
		if _root_growth_counter >= 3:
			_root_growth_counter = 0
			_extend_rhizome()
		return true
	# Lift the cap to 5 + ceil(height/4), maxing at 12. So a 4-voxel
	# sapling has the original 5-root cap; a 28-voxel sword can grow up
	# to 12 root columns spreading well past the stem.
	_max_roots = clampi(5 + int(ceil(float(current_height) / 4.0)), 5, 12)
	if _root_growth_counter >= 3 and _root_count < _max_roots:
		_root_growth_counter = 0
		var root_ramp: Array = [ramp[0].darkened(0.3), ramp[0].darkened(0.15)]
		_add_root(root_ramp)

	return true


func _grow_column_voxel(ramp: Array, rel: float, photo_offset: Vector2) -> void:
	# The plainest growth form — moss, and the fallback for any leaf form that
	# bails. It used to be a perfectly straight stack of identical cubes all
	# bowing along +X, which is the most obviously procedural thing in the
	# tank. Three cheap corrections: taper toward the tip, wander a little,
	# and lean the way this individual leans.
	var ramp_idx: int = clampi(int(rel * 5.0), 0, 5)
	var color: Color = _micro_vary_color(ramp[ramp_idx] as Color, current_height)
	var mi := MeshInstance3D.new()
	# Quantised to 4 steps so VoxelMat's box cache stays small — a continuous
	# taper would mint a new mesh per node.
	var taper_step: int = clampi(int(rel * 4.0), 0, 3)
	var thickness: float = VOXEL_SIZE * (1.0 - 0.11 * float(taper_step))
	mi.mesh = VoxelMat.get_box(Vector3(thickness, VOXEL_SIZE, thickness))
	mi.material_override = VoxelMat.make_foliage(color)
	var lean: Vector2 = _stem_lean_offset(rel)
	var wander: float = VOXEL_SIZE * 0.16
	mi.position = _clamp_growth_offset(Vector3(
		lean.x + photo_offset.x + _node_jitter(current_height, wander),
		# Y spacing stays exactly one voxel: _recalc_height() reads the column
		# index straight back out of local_y / VOXEL_SIZE.
		current_height * VOXEL_SIZE + _internode_extension_y + VOXEL_SIZE * 0.5,
		lean.y + photo_offset.y + _node_jitter(current_height + 7919, wander),
	))
	_register_stem_voxel(mi)


func _current_etiolation() -> float:
	if etiolation_sensitivity <= 0.0:
		return 0.0
	var low_light: float = clampf((0.48 - _light_avg) / 0.38, 0.0, 1.0)
	return low_light * etiolation_sensitivity


func _rebuild_auxin_profile(apex_present: bool = true) -> void:
	# Called only when architecture changes; never from tick().
	_auxin_by_node.resize(current_height)
	for i in current_height:
		var distance: int = current_height - 1 - i
		_auxin_by_node[i] = auxin_dominance * exp(-float(distance) * 0.55) \
			if apex_present else 0.0
	_auxin_rebuild_count += 1


func auxin_at_node(node_index: int) -> float:
	if node_index < 0 or node_index >= _auxin_by_node.size():
		return 0.0
	return _auxin_by_node[node_index]


# Naturalism #761 — per-voxel hue/value jitter keyed off asymmetry_seed.
# Kept tiny (± one palette-ish step) so clumps read organic, not noisy.
func _micro_vary_color(base: Color, voxel_key: int) -> Color:
	var h: int = (asymmetry_seed ^ (voxel_key * 2654435761) ^ 0x9E3779B9) & 0x7FFFFFFF
	var dh: float = (float(h % 2000) / 1000.0 - 1.0) * 0.018
	var dv: float = (float(int(float(h) / 2000.0) % 2000) / 1000.0 - 1.0) * 0.035
	var c: Color = base
	c.h = wrapf(c.h + dh, 0.0, 1.0)
	c.v = clampf(c.v + dv, 0.05, 1.0)
	return c


# Lateral shoot pushed from a cut node after a fish nibbles the apex.
# Spawns 2-3 angled voxels off to one side at the cut height, plus a
# tip leaf cluster baked into the foliage MultiMesh so the side shoot
# is visibly alive (not just a stub). Doesn't change current_height —
# the main stem regrows on subsequent ticks.
func _grow_side_shoot_at(ramp: Array, cut_y: int, photo_offset: Vector2) -> void:
	var theta: float = randf() * TAU
	var dx: float = cos(theta)
	var dz: float = sin(theta)
	var ramp_idx: int = clampi(maxi(2, int(cut_y / 3.0)), 0, ramp.size() - 1)
	var stem_color: Color = ramp[ramp_idx]
	var shoot_len: int = 2 + (1 if randf() < 0.5 else 0)
	var base_y: float = float(cut_y) * VOXEL_SIZE
	for j in shoot_len:
		var t: float = float(j) / float(maxi(1, shoot_len))
		var mi := MeshInstance3D.new()
		var thickness: float = lerpf(0.38, 0.26, t)
		mi.mesh = VoxelMat.get_box(Vector3(
			VOXEL_SIZE * thickness,
			VOXEL_SIZE * 0.65,
			VOXEL_SIZE * thickness))
		mi.material_override = VoxelMat.make_foliage(stem_color)
		var reach: float = VOXEL_SIZE * 0.5 * float(j + 1)
		mi.position = _clamp_growth_offset(Vector3(
			photo_offset.x + dx * reach,
			base_y + VOXEL_SIZE * 0.3 * float(j + 1),
			photo_offset.y + dz * reach))
		_register_stem_voxel(mi)
	# Tip cluster — a couple of leaf voxels baked into the foliage batch
	# so the side shoot reads as a sprouting twig with new growth.
	var tip_node := Node3D.new()
	tip_node.position = _clamp_growth_offset(Vector3(
		photo_offset.x + dx * VOXEL_SIZE * 0.5 * float(shoot_len + 1),
		base_y + VOXEL_SIZE * 0.3 * float(shoot_len + 1),
		photo_offset.y + dz * VOXEL_SIZE * 0.5 * float(shoot_len + 1)))
	tip_node.rotation.y = theta
	var leaf_color: Color = ramp[clampi(ramp.size() - 2, 0, ramp.size() - 1)]
	var tip_voxels: Array = []
	for k in 3:
		var lv := MeshInstance3D.new()
		lv.mesh = VoxelMat.get_box(Vector3(
			VOXEL_SIZE * 0.32, VOXEL_SIZE * 0.22, VOXEL_SIZE * 0.32))
		lv.material_override = VoxelMat.make_foliage(leaf_color.lightened(0.04 * float(k)))
		lv.position = Vector3(
			VOXEL_SIZE * 0.18 * float(k),
			VOXEL_SIZE * 0.18 * float(k),
			0.0)
		tip_voxels.append(lv)
	_leaf_groups.append(_bake_leaf(tip_node, tip_voxels))
	_leaf_ages.append(_t)
	_register_leaf_age(_t)
	tip_node.free()


# Animate a freshly-spawned leaf node from a curled-up start (small scale,
# tilted forward like a rolled-up shoot) into its full open pose. Real
# aquatic plants unfurl new leaves over a day or two; we compress that to
# ~1.6 sim seconds so the player visibly sees fresh growth "opening." Uses
# a Tween so each leaf manages its own animation lifecycle — no per-frame
# bookkeeping in tick().
func _animate_leaf_unfurl(leaf_node: Node3D) -> void:
	if leaf_node == null:
		return
	var final_scale: Vector3 = leaf_node.scale
	leaf_node.scale = Vector3(0.15, 0.25, 0.15)
	# Tiny initial forward pitch — the rolled-up shoot pose. Pivot is at
	# the leaf base since LeafShapes builds the leaf extending outward
	# from there, so a pitch tilts it inward toward the stem and reads as
	# "still rolled."
	var orig_rot: Vector3 = leaf_node.rotation
	leaf_node.rotation = orig_rot + Vector3(deg_to_rad(-35.0), 0.0, 0.0)
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(leaf_node, "scale", final_scale, 1.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(leaf_node, "rotation", orig_rot, 1.4) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# Lazily create the per-plant foliage MultiMesh batch (one draw call for all of
# this plant's leaf voxels). The foliage_mm shader keeps the GPU current-sway.
func _ensure_foliage_batch() -> VoxelBatch:
	if _foliage_batch == null:
		if _foliage_mat == null:
			_foliage_mat = ShaderMaterial.new()
			_foliage_mat.shader = load("res://shaders/foliage_mm.gdshader") as Shader
			_foliage_mat.set_shader_parameter("sway_phase_offset", _phase)
			_foliage_mat.set_shader_parameter("red_potential", red_potential)
			VoxelMat.register_foliage_mm(_foliage_mat)
		_apply_sway_personality()
		# RGBA custom data is the bounded per-leaf visual channel. R starts with
		# geometric thickness; later channels remain available without materials.
		_foliage_batch = VoxelBatch.new(self, _foliage_mat, 256, true)
		_apply_visibility_range_to(_foliage_batch.mmi)
	return _foliage_batch


# Bake a freshly-built leaf into the foliage MultiMesh. LeafShapes returns
# MeshInstance3D *templates* (positioned relative to leaf_node, never added to
# the tree); we read each one's transform, box size and color, fold in
# leaf_node's orientation, push it into the batch as an instance, then free the
# template. Returns the list of handles so the leaf can be shed as a unit. The
# leaf_node itself is a transient transform holder — the caller frees it.
func _bake_leaf(leaf_node: Node3D, leaf_voxels: Array) -> Array:
	var batch := _ensure_foliage_batch()
	var leaf_xform: Transform3D = leaf_node.transform
	var group: Array = []
	var leaf_phase: float = _stable_leaf_phase(leaf_xform.origin, _leaf_groups.size())
	var voxel_i: int = 0
	for v in leaf_voxels:
		var mi: MeshInstance3D = v as MeshInstance3D
		if mi == null:
			continue
		var size := Vector3(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE)
		var bm := mi.mesh as BoxMesh
		if bm != null:
			size = bm.size
		var col: Color = Color(1, 1, 1, 1)
		var sm := mi.material_override as ShaderMaterial
		if sm != null:
			var a = sm.get_shader_parameter("albedo")
			if a != null:
				col = a
		var inst_xform: Transform3D = leaf_xform * mi.transform
		var scaled := Transform3D(inst_xform.basis.scaled(size), inst_xform.origin)
		var baked_color: Color = _apply_baked_self_occlusion(
			_voxel_depth_jitter(col, inst_xform.origin), inst_xform.origin)
		var handle: VoxelBatch.Handle = batch.add(scaled, baked_color)
		handle.set_custom_data(Color(_leaf_thickness(size, voxel_i, leaf_voxels.size()), leaf_phase, 0.0, 1.0))
		group.append(handle)
		voxel_i += 1
		mi.queue_free()
	batch.flush()
	return group


# Bake a leaf from a LeafShapes data-only template (PLANT_SYSTEMS_50 #23).
# Identical output to _bake_leaf minus the throwaway MeshInstance3D, BoxMesh
# lookup and ShaderMaterial round-trip per voxel: the shared template carries
# the local transform and box size, and the base color resolves here so this
# plant's live ramp, leaf age and per-leaf variegation roll stay out of the
# cache.
func _bake_leaf_template(leaf_xform: Transform3D, template: Array,
		ramp: Array, age_frac: float, mods: Dictionary) -> Array:
	var batch := _ensure_foliage_batch()
	var group: Array = []
	var leaf_phase: float = _stable_leaf_phase(leaf_xform.origin, _leaf_groups.size())
	var defer_upload: bool = template.size() >= LEAF_BAKE_DEFER_THRESHOLD
	var voxel_i: int = 0
	for v in template:
		var lv: LeafShapes.LeafVoxel = v
		var inst_xform: Transform3D = leaf_xform * lv.xform
		var scaled := Transform3D(inst_xform.basis.scaled(lv.size), inst_xform.origin)
		var color: Color = _voxel_depth_jitter(
			lv.base_color(ramp, age_frac, mods), inst_xform.origin)
		color = _apply_baked_self_occlusion(color, inst_xform.origin)
		var handle: VoxelBatch.Handle = batch.add_deferred(scaled, color) if defer_upload \
			else batch.add(scaled, color)
		handle.set_custom_data(Color(
			_leaf_thickness(lv.size, voxel_i, template.size()), leaf_phase, 0.0, 1.0))
		group.append(handle)
		voxel_i += 1
	if defer_upload:
		# The growth step that admitted this leaf pays for its first bounded
		# chunk. Remaining chunks consume later tank-wide growth slots.
		batch.process_deferred_writes(LEAF_BAKE_CHUNK_SIZE)
	else:
		batch.flush()
	return group


func _leaf_thickness(size: Vector3, voxel_i: int, voxel_count: int) -> float:
	# Geometry provides the baseline; the middle of a leaf/petiole receives a
	# small deterministic boost so its fake transmission cannot look paper-thin.
	var sorted_dims: Array[float] = [absf(size.x), absf(size.y), absf(size.z)]
	sorted_dims.sort()
	var geometric: float = clampf(sorted_dims[0] / maxf(VOXEL_SIZE * 0.55, 0.001), 0.0, 1.0)
	var center: float = 1.0 - absf((float(voxel_i) + 0.5) / maxf(float(voxel_count), 1.0) * 2.0 - 1.0)
	return clampf(maxf(geometric, center * 0.62), 0.0, 1.0)


func _stable_leaf_phase(origin: Vector3, leaf_index: int) -> float:
	# Pure hash of persistent geometry/order: stable across frames and save
	# rebuilds, with one phase shared by all voxels belonging to a leaf.
	var seed_value: float = origin.x * 12.9898 + origin.y * 37.719 \
		+ origin.z * 19.913 + float(leaf_index) * 7.123 + float(asymmetry_seed) * 0.001
	return fposmod(sin(seed_value) * 43758.5453, 1.0)


func _apply_baked_self_occlusion(color: Color, origin: Vector3) -> Color:
	var cell := Vector3i(
		floori(origin.x / 0.36), floori(origin.y / 0.36), floori(origin.z / 0.36))
	var local_density: int = 0
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				local_density += int(_crown_density_cells.get(
					cell + Vector3i(dx, dy, dz), 0))
	var shade: float = lerpf(1.0, 0.72, clampf(float(local_density) / 12.0, 0.0, 1.0))
	if _crown_density_cells.has(cell):
		_crown_density_cells[cell] = mini(int(_crown_density_cells[cell]) + 1, 6)
	elif _crown_density_cells.size() < CROWN_DENSITY_CELL_CAP:
		_crown_density_cells[cell] = 1
	return Color(color.r * shade, color.g * shade, color.b * shade, color.a)


func _process_leaf_bake_queue() -> void:
	if _foliage_batch == null or not _foliage_batch.has_deferred_writes():
		return
	if _try_consume_growth_budget():
		_foliage_batch.process_deferred_writes(LEAF_BAKE_CHUNK_SIZE)


# Per-voxel value jitter (#101) — depth within a plant mass.
func _voxel_depth_jitter(col: Color, origin: Vector3) -> Color:
	var h: float = fmod(sin(origin.x * 12.9898 + origin.y * 37.233
			+ origin.z * 78.233) * 43758.5453, 1.0)
	if h < 0.0:
		h += 1.0
	var val_mult: float = 0.86 + h * 0.22
	return Color(col.r * val_mult, col.g * val_mult, col.b * val_mult, col.a)


func _grow_paddle_leaf(ramp: Array, age_frac: float, rel: float,
		photo_offset: Vector2) -> void:
	# leaf_node is a transient transform holder (never added to the tree); its
	# orientation is baked into the foliage MultiMesh by _bake_leaf.
	var leaf_node := Node3D.new()
	# Position along the stem with phototropism, leaning the way this
	# individual leans rather than always along +X.
	var lean: Vector2 = _stem_lean_offset(rel)
	leaf_node.position = _clamp_growth_offset(Vector3(
		lean.x + photo_offset.x,
		current_height * VOXEL_SIZE * 0.9 + _internode_extension_y + VOXEL_SIZE * 0.5,
		lean.y + photo_offset.y,
	))
	# Set around the stem by the species' divergence angle, not a flip-flop.
	leaf_node.rotation.y = _leaf_yaw(current_height, 0.10)
	leaf_node.rotation.x = _shade_pitch()
	# Build the paddle leaf. Shade leaves run larger; mid-stem leaves are the
	# biggest on the plant.
	var span: float = _shade_size_mult() * _node_size_gradient(rel)
	var template: Array = LeafShapes.get_leaf_template("paddle", {
		"length": clampi(int(round(float(leaf_length) * span)), 2, 6),
		"width": 2, "flatten": 0.5, "quilted": quilted, "wavy": wavy_edges,
	})
	_leaf_groups.append(_bake_leaf_template(
		leaf_node.transform, template, ramp, age_frac, _leaf_mods()))
	_leaf_ages.append(_t)
	_register_leaf_age(_t)
	leaf_node.free()


func _grow_ribbon_leaf(ramp: Array, age_frac: float, _rel: float,
		photo_offset: Vector2) -> void:
	var leaf_node := Node3D.new()
	leaf_node.position = _clamp_growth_offset(Vector3(
		photo_offset.x + randf_range(-0.1, 0.1),
		VOXEL_SIZE * 0.3,
		photo_offset.y + randf_range(-0.1, 0.1),
	))
	# Each blade emerges from the base and goes up. For ribbon plants,
	# current_height tracks number of blades, not individual voxels.
	var blade_len: int = clampi(leaf_length + _rng_range(-1, 2), 4, 14)
	# The S-curve seed quantizes to one of LeafShapes' sway buckets so a bed
	# of Vallisneria shares templates instead of minting one per blade.
	var sway_seed: float = randf() * TAU
	var template: Array = LeafShapes.get_leaf_template("ribbon", {
		"length": blade_len, "sway_seed": sway_seed, "wavy": wavy_edges,
	})
	_leaf_groups.append(_bake_leaf_template(
		leaf_node.transform, template, ramp, age_frac, _leaf_mods()))
	_leaf_ages.append(_t)
	_register_leaf_age(_t)
	leaf_node.free()


func _grow_lance_pair(ramp: Array, age_frac: float, rel: float,
		photo_offset: Vector2) -> void:
	# Stem voxel first — stays a real MeshInstance3D node (it's structural, in
	# the `voxels` array, and drives height / nibble / tint).
	var stem_mi := MeshInstance3D.new()
	stem_mi.mesh = VoxelMat.get_box(Vector3(VOXEL_SIZE * 0.35, VOXEL_SIZE * 0.9, VOXEL_SIZE * 0.35))
	var stem_color: Color = ramp[0] if ramp.size() > 0 else Color8(40, 70, 30)
	stem_mi.material_override = VoxelMat.make_foliage(stem_color.darkened(0.1))
	var lean_l: Vector2 = _stem_lean_offset(rel)
	stem_mi.position = _clamp_growth_offset(Vector3(
		lean_l.x + photo_offset.x,
		current_height * VOXEL_SIZE * 0.85 + _internode_extension_y + VOXEL_SIZE * 0.5,
		lean_l.y + photo_offset.y,
	))
	var stem_pos: Vector3 = stem_mi.position
	_register_stem_voxel(stem_mi)
	if current_height % 2 == 0:
		var leaf_node := Node3D.new()
		leaf_node.position = stem_pos
		var template: Array = LeafShapes.get_leaf_template("lance", {
			"pair_index": int(current_height / 2.0),
		})
		_leaf_groups.append(_bake_leaf_template(
			leaf_node.transform, template, ramp, age_frac, _leaf_mods()))
		_leaf_ages.append(_t)
		_register_leaf_age(_t)
		leaf_node.free()


func _grow_needle_leaf(ramp: Array, age_frac: float, _rel: float,
		photo_offset: Vector2) -> void:
	var leaf_node := Node3D.new()
	leaf_node.position = _clamp_growth_offset(Vector3(
		photo_offset.x + randf_range(-0.05, 0.05),
		VOXEL_SIZE * 0.2,
		photo_offset.y + randf_range(-0.05, 0.05),
	))
	var needle_len: int = clampi(leaf_length, 2, 6)
	var template: Array = LeafShapes.get_leaf_template("needle", {
		"length": needle_len,
	})
	_leaf_groups.append(_bake_leaf_template(
		leaf_node.transform, template, ramp, age_frac, {}))
	_leaf_ages.append(_t)
	_register_leaf_age(_t)
	leaf_node.free()


# Compose the modifier Dictionary handed to the leaf builders. Populated
# from genome traits set in init() — variegation, quilted, wavy_edges, the
# optional underside tone. The builders accept missing keys (default 0/false).
func _leaf_mods() -> Dictionary:
	return {
		"variegation": variegation,
		"quilted": quilted,
		"wavy": wavy_edges,
		"tone_under": underside_tone,
		"iridescence": iridescence,
		"asymmetry_seed": asymmetry_seed,
		"leaf_thickness": leaf_thickness,
	}


# Unified grow path for the new (post-expansion) leaf forms. Each shape has
# a sensible default node placement; the builder is dispatched on `kind`.
# Returns the placed leaf_node's voxel array via _bake_leaf into _leaf_groups.
func _grow_shaped_leaf(ramp: Array, age_frac: float, rel: float,
		photo_offset: Vector2, kind: String) -> void:
	var leaf_node := Node3D.new()
	var yaw: float = _leaf_yaw(current_height)
	# Epiphytes with a rhizome trunk attach each new leaf at the next
	# attachment point along the trunk, cycling through. Reads as the
	# rhizome producing leaves along its length — not all stacked at base.
	# Non-epiphytes use the legacy vertical stacking.
	if is_epiphyte and _rhizome_attach_points.size() > 0:
		var attach: Vector3 = _rhizome_attach_points[
			current_height % _rhizome_attach_points.size()]
		leaf_node.position = attach + Vector3(
			photo_offset.x * 0.4,
			VOXEL_SIZE * 0.35,
			photo_offset.y * 0.4,
		)
		# Leaves emerge around the rhizome by the same divergence angle.
		leaf_node.rotation.y = yaw
	else:
		var lean_s: Vector2 = _stem_lean_offset(rel) * 0.92
		leaf_node.position = _clamp_growth_offset(Vector3(
			lean_s.x + photo_offset.x,
			current_height * VOXEL_SIZE * 0.85 + _internode_extension_y + VOXEL_SIZE * 0.4,
			lean_s.y + photo_offset.y,
		))
		leaf_node.rotation.y = yaw
	leaf_node.rotation.x = _shade_pitch()
	# Apply emersed-form size boost when the plant is still in its first
	# minute. Linear fade so the transition reads as growth changing form.
	var emersed_k: float = clampf(_emersed_remaining / EMERSED_DURATION_S, 0.0, 1.0)
	var lsm: float = clampf(leaf_size_mult * _visual_youth_scale()
		* (1.0 + emersed_k * 0.15) * _shade_size_mult() * _node_size_gradient(rel),
		0.5, 1.8)
	var mods: Dictionary = _leaf_mods()
	# Stem internode — visible thin stem segment for whorled-leaf plants
	# (Rotala, Limnophila). Without this they read as a stack of leaves
	# with no stem connecting them. Skipped for epiphytes (the rhizome IS
	# the visible structural element).
	if whorled_leaves and not is_epiphyte:
		var stem_color: Color = (ramp[1] as Color).darkened(0.05) \
			if ramp.size() > 1 else Color8(60, 80, 40)
		var stem_mi := MeshInstance3D.new()
		stem_mi.mesh = VoxelMat.get_box(Vector3(
			VOXEL_SIZE * 0.18, VOXEL_SIZE * 0.85, VOXEL_SIZE * 0.18))
		stem_mi.material_override = VoxelMat.make_foliage(stem_color)
		stem_mi.position = leaf_node.position + Vector3(0.0, -VOXEL_SIZE * 0.30, 0.0)
		_register_stem_voxel(stem_mi)
	# Deterministic forms come from the shared data-only template cache (#23);
	# the randomized ones below still build throwaway nodes, since their
	# geometry is rolled per leaf and must not be shared.
	var template: Array = []
	var leaf_voxels: Array = []
	match kind:
		"spade":
			var sl: int = clampi(int(leaf_length * lsm), 3, 8)
			var sw: int = clampi(int(3.0 * lsm + 0.5), 2, 5)
			template = LeafShapes.get_leaf_template("spade", {
				"length": sl, "width": sw,
				"quilted": quilted, "wavy": wavy_edges,
			})
		"cordate":
			# Cordate leaves stay flat-ish, but still spaced by divergence.
			leaf_node.rotation.y = yaw
			leaf_node.rotation.x = _shade_pitch() * 0.5
			template = LeafShapes.get_leaf_template("cordate", {
				"quilted": quilted, "wavy": wavy_edges,
			})
		"pinnate":
			var pl: int = clampi(int(leaf_length * lsm), 3, 7)
			template = LeafShapes.get_leaf_template("pinnate", {
				"length": pl, "quilted": quilted,
			})
		"starburst":
			# Starburst is a one-time rosette; only build at very low height
			# (the rosette IS the plant) — otherwise it stacks weirdly.
			if current_height > 2:
				_grow_column_voxel(ramp, rel, photo_offset)
				leaf_node.free()
				return
			var blades: int = clampi(int(7.0 * lsm), 5, 12)
			var blade_len: int = clampi(int(leaf_length * lsm), 3, 7)
			leaf_voxels = LeafShapes.build_starburst(
				blades, blade_len, ramp, age_frac, mods)
		"four_leaf":
			# Marsilea is a carpet rosette; only one cross per "plant".
			if current_height > 1:
				_grow_column_voxel(ramp, rel, photo_offset)
				leaf_node.free()
				return
			template = LeafShapes.get_leaf_template("four_leaf")
		"fingered":
			var fl: int = clampi(int(leaf_length * lsm), 4, 8)
			template = LeafShapes.get_leaf_template("fingered", {
				"length": fl, "fingers": 3, "quilted": quilted,
			})
		"downy":
			leaf_voxels = LeafShapes.build_downy(ramp, age_frac, mods)
		"round":
			# Pads sit flat on the surface plane, rotated only about Y so a
			# raft of them does not share one orientation.
			leaf_node.rotation = Vector3(0.0, yaw, 0.0)
			var radius: int = clampi(int(2.0 * lsm), 2, 4)
			leaf_voxels = LeafShapes.build_round_pad(radius, ramp, age_frac, mods)
		"oval":
			template = LeafShapes.get_leaf_template("oval")
		"lobed":
			var ll: int = clampi(int(leaf_length * lsm), 3, 8)
			template = LeafShapes.get_leaf_template("lobed", {"length": ll})
		_:
			_grow_column_voxel(ramp, rel, photo_offset)
			leaf_node.free()
			return
	if not template.is_empty():
		_leaf_groups.append(_bake_leaf_template(
			leaf_node.transform, template, ramp, age_frac, mods))
		_leaf_ages.append(_t)
		_register_leaf_age(_t)
		leaf_node.free()
		return
	if leaf_voxels.is_empty():
		leaf_node.free()
		return
	_leaf_groups.append(_bake_leaf(leaf_node, leaf_voxels))
	_leaf_ages.append(_t)
	_register_leaf_age(_t)
	leaf_node.free()


func _add_evolutionary_accessory(ramp: Array, rel: float, photo_offset: Vector2) -> void:
	var accent: Color = ramp[clampi(int(rel * 5.0), 0, 5)]
	# n is a transient transform holder; accessory voxels bake into the foliage
	# MultiMesh just like leaves.
	var n := Node3D.new()
	var y: float = current_height * VOXEL_SIZE * 0.82 + _internode_extension_y + VOXEL_SIZE * 0.45
	# Accessories sit on the divergence spiral too, one half-step off the
	# leaf at this node so they read as a branchlet beside it.
	var acc_yaw: float = _phyllotaxis_yaw(current_height) + PI * 0.5
	var side: float = cos(acc_yaw)
	n.position = _clamp_growth_offset(Vector3(
		photo_offset.x + side * VOXEL_SIZE * randf_range(0.45, 1.2),
		y,
		photo_offset.y + randf_range(-VOXEL_SIZE * 0.5, VOXEL_SIZE * 0.5),
	))
	var acc_voxels: Array = []
	match leaf_form:
		"ribbon":
			for i in 2 + int(randf() < 0.45):
				var mi := MeshInstance3D.new()
				mi.mesh = VoxelMat.get_box(Vector3(VOXEL_SIZE * 0.22, VOXEL_SIZE * 0.45, VOXEL_SIZE * 0.28))
				mi.material_override = VoxelMat.make_foliage(accent.lightened(0.04 * float(i)))
				mi.position = Vector3(side * VOXEL_SIZE * 0.18 * float(i), VOXEL_SIZE * 0.28 * float(i), 0)
				acc_voxels.append(mi)
		"needle":
			for x_side in [-1.0, 1.0]:
				var mi2 := MeshInstance3D.new()
				mi2.mesh = VoxelMat.get_box(Vector3(VOXEL_SIZE * 0.18, VOXEL_SIZE * 0.22, VOXEL_SIZE * 0.36))
				mi2.material_override = VoxelMat.make_foliage(accent.lightened(0.08))
				mi2.position = Vector3(x_side * VOXEL_SIZE * 0.16, VOXEL_SIZE * 0.1, 0)
				acc_voxels.append(mi2)
		"lance":
			for i in 2:
				var mi3 := MeshInstance3D.new()
				mi3.mesh = VoxelMat.get_box(Vector3(VOXEL_SIZE * 0.22, VOXEL_SIZE * 0.34, VOXEL_SIZE * 0.20))
				mi3.material_override = VoxelMat.make_foliage(accent.lerp(Color8(225, 205, 120), 0.05))
				mi3.position = Vector3(side * VOXEL_SIZE * 0.18, VOXEL_SIZE * 0.24 * float(i), VOXEL_SIZE * 0.16 * float(i))
				acc_voxels.append(mi3)
		_:
			var mi4 := MeshInstance3D.new()
			mi4.mesh = VoxelMat.get_box(Vector3(VOXEL_SIZE * 0.28, VOXEL_SIZE * 0.28, VOXEL_SIZE * 0.28))
			mi4.material_override = VoxelMat.make_foliage(accent.lightened(0.10))
			acc_voxels.append(mi4)
	_leaf_groups.append(_bake_leaf(n, acc_voxels))
	_leaf_ages.append(_t)
	_register_leaf_age(_t)
	n.free()


func _build_stressed_ramp(base_ramp: Array) -> Array:
	var stressed: Array = []
	var stress_amt: float = clampf(1.0 - _health_smooth, 0.0, 1.0)
	for c in base_ramp:
		var sc: Color = LeafShapes.stress_color(c as Color, stress_amt, STRESS_RAMP)
		stressed.append(sc)
	return stressed


# Compute the "anthocyanin response" ramp — the brighter half of the ramp
# (sun-facing leaves) is lerped toward a red/orange/magenta target color
# proportional to:
#   red_potential * light * (1 - shade) * (0.6 + 0.4 * co2_met)
# Where co2_met = co2_level >= co2_demand (smooth).
# Real-tank parallel: red plants need high light + CO2 + lean nitrogen to
# produce visible anthocyanin. We approximate the lean-N requirement via
# the health/stress system implicitly — plants under nutrient stress get
# less green chlorophyll showing, letting the red drive through.
func _red_boosted_ramp(base_ramp: Array) -> Array:
	if base_ramp.size() < 4 or red_potential <= 0.0:
		return base_ramp
	var sim_d: Node = _find_sim()
	var light: float = 1.0
	if sim_d != null and sim_d.has_method("daylight"):
		light = clampf(float(sim_d.daylight()), 0.0, 1.0)
	var shade_term: float = clampf(_shade_mult, 0.5, 1.0)
	var co2_now: float = 0.0
	if sim_d != null and sim_d.has_method("co2_level"):
		co2_now = sim_d.co2_level()
	# Smooth co2_met: 0 when CO2 << demand, 1 when CO2 >= demand
	var co2_met: float = clampf((co2_now - co2_demand * 0.3) / maxf(co2_demand, 0.001), 0.0, 1.0)
	# Light spectrum multiplier — warm bulbs (>0.5) boost reds, cool bulbs
	# (<0.5) dampen them. Effect is mild (±35%) so it composes with the
	# bigger drivers (red_potential × light × co2_met).
	var spectrum: float = 0.5
	if sim_d != null and sim_d.has_method("light_spectrum"):
		spectrum = sim_d.light_spectrum()
	var spectrum_mult: float = 0.65 + spectrum * 0.7
	var k: float = red_potential * light * shade_term * (0.55 + 0.45 * co2_met) * spectrum_mult
	# Trace iron (#58): reds fade when the iron pool is drawn down — a heavy
	# red planting needs richer substrate or dosing to hold its color.
	if sim_d != null and sim_d.get("water_chemistry") != null \
			and sim_d.water_chemistry.has_method("iron_level"):
		k *= clampf(float(sim_d.water_chemistry.iron_level()) / 0.6, 0.3, 1.0)
	if k < 0.05:
		return base_ramp
	# Red target reads from the ramp's existing top color and lerps toward
	# a saturated red/magenta — we want "this plant's red", not arbitrary.
	# When ramp_override already has red bias (e.g. Ludwigia Super Red),
	# the lerp is gentle; when ramp is green, the lerp transforms.
	var hot: Color = Color(0.92, 0.32, 0.32)
	# Tinted hot: pull toward whatever the ramp's top color suggests so a
	# magenta-leaning ramp goes magenta and a peach-leaning ramp goes
	# orange. 30% of "hot" comes from ramp_top, 70% from our default.
	var top: Color = base_ramp[base_ramp.size() - 1]
	hot = hot.lerp(Color(top.r * 1.2, top.g * 0.55, top.b * 0.55), 0.30)
	var out: Array = []
	for i in base_ramp.size():
		var rel: float = float(i) / float(base_ramp.size() - 1)
		# Only the bright half (rel > 0.4) shifts — base / shade voxels keep
		# their original tone, giving the gradient a visible "red on top,
		# green at base" silhouette like a real Rotala H'ra stem.
		var per_voxel_k: float = k * smoothstep(0.4, 1.0, rel)
		var c: Color = (base_ramp[i] as Color).lerp(hot, per_voxel_k)
		out.append(c)
	return out


func biomass() -> int:
	return current_height


func _vitals_growth_mult(sim_driver: Node) -> float:
	if sim_driver == null or sim_driver.get("tank_vitals") == null:
		return 1.0
	var vitals: Dictionary = sim_driver.tank_vitals
	var mult: float = 1.0
	match int(vitals.get("cycle_phase", 0)):
		WaterChemistry.CyclePhase.CYCLING, WaterChemistry.CyclePhase.ESTABLISHED:
			mult = 1.08
		WaterChemistry.CyclePhase.AMMONIA_SPIKE, WaterChemistry.CyclePhase.NITRITE_SPIKE:
			mult = 0.82
		WaterChemistry.CyclePhase.NEW_TANK:
			mult = 0.92
	var bloom: float = float(vitals.get("bloom_pressure", 0.0))
	mult *= 1.0 - bloom * 0.22
	return clampf(mult, 0.55, 1.15)


func _biofilm_spread_factor() -> float:
	if not is_epiphyte and not has_plantlets:
		return 1.0
	var sim_driver: Node = _find_sim()
	if sim_driver == null:
		return 1.0
	var w: Node = sim_driver.get_parent()
	if w == null or w.get("biofilm_progress") == null:
		return 0.5
	var bio: float = clampf(float(w.biofilm_progress), 0.0, 0.7)
	var graze: float = 0.0
	if w.has_method("live_microfauna_count"):
		graze = clampf(float(w.live_microfauna_count()) / 120.0, 0.0, 0.35)
	return clampf(bio / 0.42 - graze * 0.4, 0.08, 1.0)


static func _record_melt_cluster(sim_d: Node) -> void:
	var now: int = int(Time.get_unix_time_from_system())
	_melt_cluster_times.append(now)
	while _melt_cluster_times.size() > 0 and now - int(_melt_cluster_times[0]) > 60:
		_melt_cluster_times.pop_front()
	if _melt_cluster_times.size() >= 3 and now - _melt_wave_headline_unix > 90:
		_melt_wave_headline_unix = now
		if sim_d.has_method("emit_eco_event"):
			sim_d.emit_eco_event("flora",
				"Plant melt wave — cycling stress across the crypts.", 2, true)


# Scan sibling plants under plants_root for the tallest one within
# SHADE_RADIUS. If at least one is meaningfully taller (SHADE_HEIGHT_DELTA),
# this plant is shaded and grows slower. Called from tick() every few
# seconds, not per-tick, since the answer is slow-moving.
func _recompute_shade() -> void:
	_shade_mult = 1.0
	var sim_driver: Node = _find_sim()
	var candidates: Array = []
	if sim_driver != null and sim_driver.has_method("query_plants_in_radius"):
		candidates = sim_driver.query_plants_in_radius(_world_pos, SHADE_RADIUS)
	else:
		var parent := get_parent()
		if parent == null:
			return
		for child in parent.get_children():
			if child is Plant:
				candidates.append(child)
	var rad2: float = SHADE_RADIUS * SHADE_RADIUS
	for child in candidates:
		if child == self or not (child is Plant):
			continue
		var op: Plant = child
		if not is_instance_valid(op):
			continue
		var dx: float = op._world_pos.x - _world_pos.x
		var dz: float = op._world_pos.z - _world_pos.z
		if dx * dx + dz * dz > rad2:
			continue
		if op.current_height > current_height + SHADE_HEIGHT_DELTA:
			_shade_mult = SHADE_PENALTY
			return


# Compute & apply pale (CO₂) or yellow (iron) tint to the topmost voxels.
# Reads sim.daylight() and uses growth_progress as an indirect "stalled
# photosynthesis" signal. We tint the top quartile of voxels because
# deficiencies show first on new growth in real plants (carbon demand
# and iron mobility both favor the youngest tissue).
func _apply_deficiency_tints(nutrient_mult: float) -> void:
	if voxels.is_empty():
		return
	var sim_driver: Node = _find_sim()
	var daylight: float = 1.0
	if sim_driver != null and sim_driver.has_method("daylight"):
		daylight = float(sim_driver.daylight())
	# Symptoms now report measured local availability. Environmental guards
	# keep the cues readable: carbon demand matters under light, and iron
	# chlorosis appears on otherwise viable tissue.
	var co2_stressed: bool = daylight > 0.55 \
		and _root_co2_available < maxf(0.16, co2_demand * 0.55) \
		and _health_smooth > 0.5
	var iron_stressed: bool = _root_iron_available < 0.24 \
		and nutrient_mult > 0.2 and _health_smooth > 0.5
	if sim_driver != null and sim_driver.get("tank_vitals") != null:
		var phase: int = int(sim_driver.tank_vitals.get("cycle_phase", 0))
		if phase == WaterChemistry.CyclePhase.AMMONIA_SPIKE:
			iron_stressed = false
			co2_stressed = false
		elif phase >= WaterChemistry.CyclePhase.ESTABLISHED \
				and nutrient_mult > 0.25 and nutrient_mult < 0.55:
			iron_stressed = true
	var new_state: String = ""
	if co2_stressed:
		new_state = "co2"
	elif iron_stressed:
		new_state = "iron"
	# Idempotent: skip re-applying if nothing changed since last check.
	if new_state == _deficiency_active:
		return
	_deficiency_active = new_state

	var tint: Color = Color(1, 1, 1, 1)
	if new_state == "co2":
		tint = Color(0.88, 0.95, 0.84)   # pale, slightly chlorotic
	elif new_state == "iron":
		tint = Color(1.05, 1.0, 0.55)    # yellow new-growth chlorosis
	# Apply to the top quartile of voxels (newest growth). We can't use
	# `instance uniform` for this — Godot 4 allocates a buffer slot for
	# every instance using that shader, and the tank has thousands of
	# voxels, so it blows past the global-shader-params buffer. Instead,
	# duplicate the material per tinted voxel and bake the tint into
	# its `albedo`. Original colors are recovered by re-fetching from
	# the per-voxel `base_color` meta we set at build time (see
	# VoxelMat callers), or by leaving the duplicated material in place
	# on the lucky few that already had a unique mat.
	var n: int = voxels.size()
	var cutoff: int = maxi(1, n - int(ceil(float(n) * 0.25)))
	for i in n:
		var vx: VoxelBatch.Handle = voxels[i]
		if vx == null or not vx.alive:
			continue
		if i >= cutoff and new_state != "":
			_apply_voxel_tint(vx, tint)
		else:
			_clear_voxel_tint(vx)


# Per-tick leaf wilt + recovery. Walks _leaf_groups and recolors only
# each leaf's last (tip) handle by lerping its base color toward a dull
# yellow-brown when _health_smooth drops, and back when it rises. The
# rest of the leaf voxels stay their original tint, so a struggling
# plant reads as "tips browning first" — the way real aquatic plants
# show stress. Cost is one set_color() per leaf only when the target
# wilt level moves more than a small epsilon from the last applied
# level, so a steady-state healthy plant pays nothing per tick.
const _WILT_TIP_COLOR: Color = Color(0.46, 0.39, 0.22)

func _apply_leaf_wilt() -> void:
	if _leaf_groups.is_empty():
		return
	# Target wilt: 0 at health >= 0.65, climbs to 1 as health falls to 0.10.
	# Smoothstep gives an easing rather than a hard knee.
	# REAL_TANK_FIDELITY #115/#118 — older leaves brown tips even when healthy.
	var age_wilt: float = 0.0
	if not _leaf_ages.is_empty():
		var oldest: float = _t - _leaf_ages[0]
		age_wilt = clampf(oldest / 180.0, 0.0, 0.55)
	var target_wilt: float = maxf(smoothstep(0.65, 0.10, _health_smooth), age_wilt * 0.7)
	# Only repaint if the change is meaningful — keeps a healthy plant
	# from re-writing the multimesh every tick.
	if absf(target_wilt - _wilt_applied) < 0.06:
		return
	_wilt_applied = target_wilt
	for group in _leaf_groups:
		var arr: Array = group as Array
		if arr.is_empty():
			continue
		# Tip = last handle in the leaf's bake order. LeafShapes builds
		# outward from base to tip, so this maps cleanly to the most
		# distal voxel — what the eye reads as "the tip."
		var tip: VoxelBatch.Handle = arr[arr.size() - 1] as VoxelBatch.Handle
		if tip == null or not tip.alive:
			continue
		var wilted: Color = tip.base_color.lerp(_WILT_TIP_COLOR, target_wilt * 0.70)
		tip.set_color(wilted)


# Apply a multiplicative tint to a voxel by duplicating its (cached, shared)
# ShaderMaterial and rewriting albedo on the copy. Stores the original
# albedo in a meta so _clear_voxel_tint can restore it. Idempotent — if
# the voxel already has a tinted-copy material, just update the albedo.
func _apply_voxel_tint(vx: VoxelBatch.Handle, tint: Color) -> void:
	if vx != null and vx.alive:
		vx.set_color(vx.base_color * tint)


# Restore a voxel's original (cached, shared) material. Cheap when the
# voxel was never tinted (no-op).
func _clear_voxel_tint(vx: VoxelBatch.Handle) -> void:
	if vx != null and vx.alive:
		vx.set_color(vx.base_color)


var _footprint_enforce_timer: float = 0.0


func _footprint_world() -> Node:
	var n: Node = self
	while n != null:
		if n.has_method("clamp_xz_in_tank"):
			return n
		n = n.get_parent()
	return null


func _plant_lateral_reach() -> float:
	match leaf_form:
		"ribbon":
			return float(clampi(leaf_length, 4, 14)) * VOXEL_SIZE * 0.45
		"paddle":
			return float(clampi(leaf_length, 2, 6)) * VOXEL_SIZE * 0.55
		"lance":
			return VOXEL_SIZE * 1.4
		"needle":
			return float(clampi(leaf_length, 2, 6)) * VOXEL_SIZE * 0.35
		_:
			return VOXEL_SIZE * 0.9


func _clamp_growth_offset(local: Vector3, reach: float = -1.0) -> Vector3:
	if reach < 0.0:
		reach = _plant_lateral_reach()
	var w := _footprint_world()
	if w == null:
		return local
	var g: Vector3 = global_position
	var wx: float = g.x + local.x
	var wy: float = g.y + local.y
	var wz: float = g.z + local.z
	if w.has_method("fits_plant_at") and w.fits_plant_at(wx, wz, reach, 0.22, wy):
		return local
	var clamped: Vector2 = w.clamp_xz_in_tank(wx, wz, 0.22 + reach)
	var out := Vector3(clamped.x - g.x, local.y, clamped.y - g.z)
	for _i in 8:
		var test_y: float = g.y + out.y
		if w.fits_plant_at(g.x + out.x, g.z + out.z, reach, 0.22, test_y):
			return out
		out.x *= 0.68
		out.z *= 0.68
	return Vector3(0.0, local.y, 0.0)


func _clamp_root_to_footprint() -> void:
	var w := _footprint_world()
	if w == null or is_epiphyte:
		return
	var reach: float = _plant_lateral_reach()
	var g: Vector3 = global_position
	var floor_y: float = g.y
	if w.has_method("column_surface_y"):
		floor_y = float(w.call("column_surface_y", g.x, g.z))
	var xz: Vector2 = Vector2(g.x, g.z)
	if w.has_method("clamp_plant_site"):
		xz = w.clamp_plant_site(g.x, g.z, reach, 0.2, floor_y)
	elif w.has_method("clamp_xz_in_tank"):
		xz = w.clamp_xz_in_tank(g.x, g.z, 0.2 + reach, floor_y)
	# Always snap the crown to the sculpted substrate surface — saved Y from a
	# smaller tank or a flat rebuild must not leave stems buried or floating.
	global_position = Vector3(xz.x, floor_y, xz.y)


func _clamp_node_xz_to_footprint(node: Node3D, margin: float = 0.22) -> void:
	var w := _footprint_world()
	if w == null:
		return
	# Reclamp in plant-local offsets so moving the crown doesn't scatter voxels.
	var plant_g: Vector3 = global_position
	var offset: Vector3 = node.global_position - plant_g
	var wx: float = plant_g.x + offset.x
	var wy: float = plant_g.y + offset.y
	var wz: float = plant_g.z + offset.z
	if wy > water_surface_y - 0.08 and w.has_method("clamp_emergent_in_tank"):
		node.global_position = w.clamp_emergent_in_tank(Vector3(wx, wy, wz), margin)
		return
	var xz: Vector2 = w.clamp_xz_in_tank(wx, wz, margin)
	node.global_position = Vector3(xz.x, wy, xz.y)


func _ensure_stem_batch() -> VoxelBatch:
	if _stem_batch == null:
		if _stem_mat == null:
			_stem_mat = ShaderMaterial.new()
			_stem_mat.shader = load("res://shaders/foliage_mm.gdshader") as Shader
			_stem_mat.set_shader_parameter("sway_amplitude", 0.0)
			VoxelMat.register_foliage_mm(_stem_mat)
		_stem_batch = VoxelBatch.new(self, _stem_mat, 64)
		_stem_batch.set_bounds_margin(Vector3(0.35, 0.25, 0.35))
		_apply_visibility_range_to(_stem_batch.mmi)
	return _stem_batch


func _register_stem_voxel(mi: MeshInstance3D, margin: float = 0.22) -> void:
	# Keep builders as cheap templates, just like leaf baking. They are never
	# retained in the scene tree after their transform/color is extracted.
	add_child(mi)
	_clamp_node_xz_to_footprint(mi, margin)
	var size := Vector3(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE)
	var box := mi.mesh as BoxMesh
	if box != null:
		size = box.size
	var color: Color = Color.WHITE
	var shader_mat := mi.material_override as ShaderMaterial
	if shader_mat != null:
		color = VoxelMat.read_albedo(shader_mat, color)
	var final_xform := Transform3D(mi.transform.basis.scaled(size), mi.position)
	remove_child(mi)
	mi.free()
	var tiny_xform := Transform3D(
		final_xform.basis.scaled(Vector3.ONE * 0.02), final_xform.origin)
	var handle: VoxelBatch.Handle = _ensure_stem_batch().add(tiny_xform, color)
	# Logical transform is final from birth; the short tween only controls the
	# shared batch instance reveal and never allocates a voxel Node3D.
	handle.transform = final_xform
	handle.local_pos = final_xform.origin
	handle.growth_limit_code = _current_limit_code()
	voxels.append(handle)
	_stem_limit_history.append(handle.growth_limit_code)
	var tw := create_tween()
	tw.tween_method(func(k: float) -> void:
		if handle.alive:
			handle.set_transform(Transform3D(
				final_xform.basis.scaled(Vector3.ONE * k), final_xform.origin)),
		0.02, 1.0, 0.95).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		if handle.alive:
			handle.set_transform(final_xform)
			if _stem_batch != null:
				_stem_batch.flush())
	_stem_batch.flush()


func _plant_visibility_range() -> float:
	var height_bonus: float = minf(
		float(max_height) * VOXEL_SIZE * 1.5, PLANT_LOD_HEIGHT_BONUS_MAX)
	return PLANT_LOD_BASE_RANGE + height_bonus


func canopy_shadow_sphere() -> Vector4:
	# One conservative crown summary replaces all leaf voxels in floor-shadow
	# selection. Radius is bounded so dense tanks never inflate shader work.
	var live_biomass: float = float(maxi(1, biomass()))
	var radius: float = clampf(sqrt(live_biomass) * VOXEL_SIZE * 0.34, 0.22, 1.25)
	var center_y: float = global_position.y + minf(
		float(current_height) * VOXEL_SIZE * 0.62, maxf(0.25, water_surface_y - global_position.y))
	return Vector4(global_position.x, center_y, global_position.z, radius)


# Transition-only reversible LOD. Per-group extrema define the coarse
# silhouette; only stable interior candidates are zero-scaled.
func set_leaf_lod_reduced(reduced: bool) -> void:
	if _leaf_lod_reduced == reduced:
		return
	_leaf_lod_reduced = reduced
	if not reduced:
		for h in _leaf_lod_hidden:
			if h != null and h.alive:
				h.set_lod_visible(true)
		_leaf_lod_hidden.clear()
		if _foliage_batch != null:
			_foliage_batch.flush()
		return

	_leaf_lod_hidden.clear()
	for group_v in _leaf_groups:
		var group: Array = group_v
		if group.size() < 5:
			continue
		var keep: Dictionary = {}
		for axis in 3:
			var min_h: VoxelBatch.Handle = null
			var max_h: VoxelBatch.Handle = null
			for value in group:
				var h: VoxelBatch.Handle = value
				if h == null or not h.alive:
					continue
				if min_h == null or h.local_pos[axis] < min_h.local_pos[axis]:
					min_h = h
				if max_h == null or h.local_pos[axis] > max_h.local_pos[axis]:
					max_h = h
			if min_h != null:
				keep[min_h] = true
			if max_h != null:
				keep[max_h] = true
		for value in group:
			var h: VoxelBatch.Handle = value
			if h == null or not h.alive or keep.has(h):
				continue
			if hash([asymmetry_seed, h.index]) & 1 == 0:
				h.set_lod_visible(false)
				_leaf_lod_hidden.append(h)
	if _foliage_batch != null:
		_foliage_batch.flush()


func _apply_visibility_range_to(geometry: GeometryInstance3D) -> void:
	if geometry == null:
		return
	geometry.visibility_range_begin = 0.0
	geometry.visibility_range_end = _plant_visibility_range()
	geometry.visibility_range_end_margin = PLANT_LOD_FADE_MARGIN
	geometry.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _apply_rooted_visibility_ranges() -> void:
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			if child is GeometryInstance3D:
				_apply_visibility_range_to(child as GeometryInstance3D)
			if child.get_child_count() > 0:
				stack.append(child)


func _reclamp_voxels_to_footprint() -> void:
	if _footprint_world() == null:
		return
	var world := _footprint_world()
	for h in voxels:
		if h == null or not h.alive:
			continue
		var world_pos: Vector3 = global_transform * h.local_pos
		var xz: Vector2 = world.clamp_xz_in_tank(world_pos.x, world_pos.z, 0.2)
		var local_pos: Vector3 = to_local(Vector3(xz.x, world_pos.y, xz.y))
		var xform: Transform3D = h.transform
		xform.origin = local_pos
		h.set_transform(xform)
	if _stem_batch != null:
		_stem_batch.flush()
	for leaf in _leaf_nodes:
		if leaf != null and is_instance_valid(leaf):
			_clamp_node_xz_to_footprint(leaf, 0.28)
			for child in leaf.get_children():
				if child is Node3D:
					_clamp_node_xz_to_footprint(child, 0.2)
	for v in bloom_voxels:
		if is_instance_valid(v):
			_clamp_node_xz_to_footprint(v, 0.18)
	# Root voxels hang below the crown in local -Y; reclamp only the stem/leaf
	# canopy so glass poke-through is fixed without scattering buried roots.


# Called by SimDriver each tick.
func tick_sleep_aware(dt: float, substrate: SubstrateGrid) -> void:
	var env_signature: int = _sleep_environment_signature(substrate)
	if _static_sleeping:
		_static_sleep_accum_s += dt
		if env_signature != _static_sleep_env_signature:
			wake_plant("environment")
		if not _static_sleep_dirty \
				and _static_sleep_accum_s < STATIC_SLEEP_CHEMISTRY_S:
			return
		var elapsed: float = _static_sleep_accum_s
		_static_sleep_accum_s = 0.0
		_static_sleep_dirty = false
		_static_sleep_env_signature = env_signature
		tick(elapsed, substrate)
		if not _static_sleep_eligible():
			_static_sleeping = false
			_static_sleep_stable_s = 0.0
		return

	tick(dt, substrate)
	if _static_sleep_eligible():
		_static_sleep_stable_s += dt
		if _static_sleep_stable_s >= STATIC_SLEEP_AFTER_S:
			_static_sleeping = true
			_static_sleep_dirty = false
			_static_sleep_accum_s = 0.0
			_static_sleep_env_signature = env_signature
	else:
		_static_sleep_stable_s = 0.0


func wake_plant(_reason: String = "") -> void:
	_static_sleep_dirty = true


func _static_sleep_eligible() -> bool:
	return current_height >= max_height and not is_dying and not _melt_active \
		and life_phase == LifePhase.VEGETATIVE and flower_stage == FlowerStage.NONE \
		and _pending_trim_nodes.is_empty() and _brush_bend.length_squared() < 1e-6 \
		and _gust_tilt.length_squared() < 1e-6 and health >= 0.65 \
		and (_foliage_batch == null or not _foliage_batch.has_deferred_writes())


func _sleep_environment_signature(substrate: SubstrateGrid) -> int:
	var nutrient_bucket: int = 0
	if substrate != null and not is_epiphyte:
		nutrient_bucket = int(round(substrate.get_at(global_position) * 20.0))
	var sim: Node = _find_sim()
	var daylight_bucket: int = int(round(sim.daylight() * 8.0)) \
		if sim != null and sim.has_method("daylight") else 4
	var flow_bucket: int = int(round(_get_flow_bias() * 10.0))
	return hash([nutrient_bucket, daylight_bucket, flow_bucket])


func tick(dt: float, substrate: SubstrateGrid) -> void:
	_process_leaf_bake_queue()
	if _foliage_batch != null:
		_foliage_batch.consider_compaction(dt)
	if _stem_batch != null:
		_stem_batch.consider_compaction(dt)
	# Refresh world-space anchor every tick. _ready() captures _world_pos
	# from global_position, but several spawn paths (base Plant, BranchPlant,
	# Coral, and the save-load _spawn_plant_from_dict path) assign
	# global_position AFTER add_child() has already fired _ready(). The
	# result was _world_pos stuck at (0,0,0) for most plants, so every
	# substrate.get_at() and consume_at() call hit cell (0,0) instead of
	# the plant's actual cell — collapsing the spatial nutrient model.
	# Spiral plants worked because their init() override re-captured.
	# Doing it here on every tick is one Vector3 read; trivial cost, and
	# robust against future spawn paths.
	_world_pos = global_position
	_clamp_root_to_footprint()
	plant_age_s += dt
	_pollination_cooldown_s = maxf(0.0, _pollination_cooldown_s - dt)
	if life_phase == LifePhase.DORMANT_BULB:
		_tick_dormant_bulb(dt, substrate)
		return
	_footprint_enforce_timer -= dt
	if _footprint_enforce_timer <= 0.0:
		_footprint_enforce_timer = 1.0 if _footprint_world() != null else 2.5
		_reclamp_voxels_to_footprint()
	_t += dt
	_tropism_refresh_t -= dt
	if _tropism_refresh_t <= 0.0:
		_tropism_refresh_t = TROPISM_REFRESH_S
		_refresh_tropism()

	# ---- Flow-based sway ----
	# Dynamic time-based sway lives on the GPU (foliage_mm). CPU only applies a
	# soft root lean so the plant isn't a rigid stick — leaf motion stays on GPU.
	var flow_bias: float = _get_flow_bias()
	# Brush bend: a fish that swam through the foliage left a transient push
	# that springs back over ~1s, so the scenery visibly reacts to its
	# inhabitants instead of ignoring them.
	if _brush_bend.length_squared() > 1e-6:
		var spring_k: float = 8.5
		var damp: float = 3.2
		_brush_bend_vel += (-_brush_bend * spring_k - _brush_bend_vel * damp) * dt
		_brush_bend += _brush_bend_vel * dt
		if _brush_bend.length() < 0.004 and _brush_bend_vel.length() < 0.02:
			_brush_bend = Vector2.ZERO
			_brush_bend_vel = Vector2.ZERO
	if _trim_recoil_t > 0.0:
		_trim_recoil_t = maxf(0.0, _trim_recoil_t - dt)
		_brush_bend_vel += Vector2(
			sin(_trim_recoil_t * 9.0) * 0.12 * _trim_recoil_t,
			cos(_trim_recoil_t * 7.5) * 0.08 * _trim_recoil_t) * dt
	if _trim_regrowth_boost > 1.01:
		_trim_regrowth_boost = maxf(1.0, _trim_regrowth_boost - dt * 0.07)
	if _gust_tilt.length_squared() > 1e-6:
		_gust_tilt = _gust_tilt.lerp(Vector2.ZERO, clampf(dt * 1.8, 0.0, 1.0))
	# Circumnutation (#5): a very slow elliptical nod of the growing tip,
	# strongest while the plant is still putting on height, negligible once it
	# caps. Subtle (~0.6°) so it reads as "alive and reaching," not wobbling.
	_circumnutation_phase += dt * 0.18
	var nutation: float = 0.012 if current_height < max_height else 0.004
	if has_flower and flower_stage >= FlowerStage.OPENING:
		nutation *= 0.2
	# Epiphytes barely lean at the root; carpets even less.
	var lean_scale: float = 0.55
	if is_epiphyte:
		lean_scale = 0.22
	elif is_carpet:
		lean_scale = 0.28
	elif leaf_form in ["paddle", "spade", "lobed", "oval"]:
		lean_scale = 0.38
	rotation.z = (flow_bias * 0.025 + _brush_bend.x * 0.7 + _gust_tilt.x * 0.65
			+ sin(_circumnutation_phase) * nutation) * lean_scale
	rotation.x = (_brush_bend.y * 0.7 + _gust_tilt.y * 0.65
			+ cos(_circumnutation_phase) * nutation * 0.7) * lean_scale
	_stabilize_flower_against_lean()
	_height_ghost_timer += dt
	if _height_ghost_timer > 180.0:
		_height_ghost_timer = 0.0
		_height_ghost_y = global_position.y + _get_stem_top()
		_update_height_ghost_marker()
	_tick_plant_mood(dt)

	# ---- Health tracking ----
	# Epiphytes don't tap the substrate grid — they cling to a host and
	# pull micros from the water column. We give them a modest, constant
	# nutrient_mult so they grow steadily but slowly, and skip the
	# substrate.consume_at() call further down so they don't drain the
	# soil under wherever they happen to be hovering.
	var nutrient_mult: float
	var growth_nutrient: float
	if is_epiphyte:
		nutrient_mult = EPIPHYTE_NUTRIENT_MULT
		growth_nutrient = EPIPHYTE_NUTRIENT_MULT
	else:
		var available: float = substrate.get_at(_world_pos)
		growth_nutrient = clampf(
			(available - substrate.NUTRIENT_BASELINE) / 0.4, 0.0, 1.0)
		nutrient_mult = growth_nutrient

	# Shade competition. Refresh every ~4-6 sim seconds (cheap to scan
	# sibling plants, but no need to do it per tick — taller neighbors
	# don't appear suddenly). Reduces effective nutrient_mult so a shaded
	# plant visibly grows slower than its taller crowd-out neighbor.
	# Real Walstad tanks show this constantly: fast stems block carpet
	# plants until you trim them.
	_shade_check_t -= dt
	if _shade_check_t <= 0.0:
		_shade_check_t = randf_range(4.0, 6.0)
		_recompute_shade()
	nutrient_mult *= _shade_mult
	growth_nutrient *= _shade_mult

	var sim_v: Node = _find_sim()
	var light_pen: float = 1.0
	if sim_v != null:
		var w: Node = sim_v.get_parent()
		if w != null and w.has_method("light_penetration_at"):
			light_pen = float(w.light_penetration_at(_world_pos))
		# Submerged melt from floater shade (#22).
		if light_pen < 0.35:
			_floater_shade_melt_t += dt
		else:
			_floater_shade_melt_t = maxf(0.0, _floater_shade_melt_t - dt * 0.5)
		if _floater_shade_melt_t > 8.0:
			nutrient_mult *= lerpf(1.0, 0.62, clampf((_floater_shade_melt_t - 8.0) / 12.0, 0.0, 1.0))
			_shade_mult = minf(_shade_mult, 0.72)
		nutrient_mult *= light_pen
		if is_epiphyte and w != null and w.get("biofilm_progress") != null:
			var bio: float = clampf(float(w.biofilm_progress), 0.0, 0.7)
			nutrient_mult *= lerpf(0.72, 1.12, bio / 0.65)
		nutrient_mult *= _vitals_growth_mult(sim_v)
		if not is_epiphyte and sim_v.get("water_chemistry") != null:
			var wc: Variant = sim_v.water_chemistry
			var water_iron: float = float(wc.iron_level()) \
				if wc.has_method("iron_level") else SubstrateGrid.IRON_LEGACY_DEFAULT
			var water_co2: float = float(wc.dissolved_co2_level()) \
				if wc.has_method("dissolved_co2_level") else SubstrateGrid.CO2_LEGACY_DEFAULT
			substrate.exchange_water_availability_at(
				_world_pos, water_iron, water_co2, dt)
			_root_iron_available = substrate.get_iron_availability_at(_world_pos)
			_root_co2_available = substrate.get_co2_availability_at(_world_pos)

	# Substrate boost cached at init time — substrate type doesn't change
	# without a scene reload, so re-reading TankConfig every tick × 100
	# plants × 10 Hz was 1000 autoload lookups/sec for a constant.
	# CO2 still polled live (the user can change it at runtime via slider).
	if not is_epiphyte and _substrate_boost != 1.0:
		nutrient_mult *= _substrate_boost
		growth_nutrient *= _substrate_boost
	if not is_epiphyte and co2_demand > 0.4:
		var sim_d_n: Node = _find_sim()
		if sim_d_n != null:
			var co2_n: float = 0.35
			if sim_d_n.has_method("dissolved_co2_level"):
				co2_n = sim_d_n.dissolved_co2_level()
			elif sim_d_n.has_method("co2_level"):
				co2_n = sim_d_n.co2_level()
			if co2_n > 0.3:
				nutrient_mult *= 1.0 + minf(co2_n - 0.3, 0.4) * 0.3
			elif co2_n < 0.25:
				nutrient_mult *= 0.82
	# Water-column uptake (#18): in lean substrates (sand / inert gravel) plants
	# fall back on dissolved nitrate, so fish load or column dosing can keep
	# them alive instead of a slow decline to nothing.
	if not is_epiphyte and _substrate_boost <= 0.85 and sim_v != null \
			and sim_v.water_chemistry != null:
		var no3_wc: float = float(sim_v.water_chemistry.nitrate)
		nutrient_mult += clampf(no3_wc / 1.5, 0.0, 1.0) * 0.45
		growth_nutrient += clampf(no3_wc / 1.5, 0.0, 1.0) * 0.45
	if not is_epiphyte:
		nutrient_mult = clampf(nutrient_mult, 0.0, 1.5)
		growth_nutrient = clampf(growth_nutrient, 0.0, 1.5)

	# Allelopathy + root oxygenation (#37, #38)
	if not is_epiphyte:
		var allelo: float = substrate.get_allelopathy_pressure_at(
			_world_pos, allelopathy_family, allelopathy_resistance)
		if allelo > 0.05:
			var allelo_pen: float = 1.0 - clampf(allelo * 0.45, 0.0, 0.35)
			nutrient_mult *= allelo_pen
			growth_nutrient *= allelo_pen
		var root_o2: float = substrate.get_root_oxygen_at(_world_pos)
		if root_o2 > 0.1:
			var o2_boost: float = 1.0 + root_o2 * 0.12
			nutrient_mult *= o2_boost
			growth_nutrient *= o2_boost
		if allelopathy_strength > 0.05:
			substrate.add_family_allelochemical_at(
				_world_pos, allelopathy_family, allelopathy_strength * dt * 0.04)
		if _root_count > 2:
			substrate.add_root_oxygen_at(_world_pos, float(_root_count) * dt * 0.002)
			substrate.release_anaerobic_at(_world_pos, float(_root_count) * dt * 0.001)

	# Temperature-gated growth (#10)
	if sim_v != null:
		var w_temp: Node = sim_v.get_parent()
		if w_temp != null and w_temp.has_method("effective_warmth_at"):
			var warmth: float = float(w_temp.effective_warmth_at(_world_pos))
			var temp_mult: float = 1.0 - absf(warmth - temp_opt) * 1.4
			nutrient_mult *= clampf(temp_mult, 0.35, 1.15)

	# Diel starch + light average (#3, #2)
	_light_avg = lerpf(_light_avg, light_pen * (sim_v.daylight() if sim_v != null and sim_v.has_method("daylight") else 0.5), dt * 0.08)
	var dl_s: float = sim_v.daylight() if sim_v != null and sim_v.has_method("daylight") else 0.5
	if dl_s > 0.35:
		_starch = clampf(_starch + dt * light_pen * 0.06, 0.0, 1.0)
	else:
		_starch = maxf(0.0, _starch - dt * 0.02)
	if _starch < 0.12 and dl_s < 0.25:
		nutrient_mult *= 0.55

	# Induced defense (#29)
	if _grazing_pressure > 0.35:
		nutrient_mult *= 1.0 - clampf((_grazing_pressure - 0.35) * 0.4, 0.0, 0.25)
		_grazing_pressure = maxf(0.0, _grazing_pressure - dt * 0.015)
		palatability = clampf(palatability - dt * 0.002, 0.05, 1.0)

	# Thigmomorphogenesis (#4)
	var flow_mag: float = absf(_get_flow_bias())
	if flow_mag > 0.08:
		_flow_stress_timer += dt
	else:
		_flow_stress_timer = maxf(0.0, _flow_stress_timer - dt * 0.5)
	if _flow_stress_timer > 8.0:
		max_height = maxi(4, int(float(max_height) * 0.995))

	_tick_leaf_ecology(dt, substrate, sim_v)
	_tick_age_senescence(dt)
	_tick_resource_transport(dt)

	# Health trends toward nutrient satisfaction, with slow decay when starved.
	var target_health: float = 0.35 + 0.65 * nutrient_mult
	if sim_v != null and sim_v.get("tank_vitals") != null:
		var vitals: Dictionary = sim_v.tank_vitals
		if int(vitals.get("cycle_phase", 0)) == WaterChemistry.CyclePhase.AMMONIA_SPIKE:
			target_health = minf(1.0, target_health + 0.08 * nutrient_mult)
	health = lerpf(health, target_health, dt * (0.05 if target_health > health else 0.025))
	_health_smooth = lerpf(_health_smooth, health, dt * 0.05)

	# Environmental adaptation: well-fed plants slowly tune growth to local
	# nutrients (phenotypic plasticity, distinct from seedling genetic mutation).
	if health > 0.85 and nutrient_mult > 0.45 and randf() < 0.0002:
		growth_rate = clampf(
			growth_rate + (nutrient_mult - 0.5) * randf_range(-0.012, 0.018),
			0.06, 0.42)

	# ---- Deficiency symptoms ----
	if _health_smooth < 0.4 and not _has_pinholes and voxels.size() > 4:
		_apply_pinholes()
	if _health_smooth < 0.2 and not is_dying:
		_begin_dying()

	# Local iron/CO₂ availability drives the existing new-growth cues.
	_deficiency_check_t -= dt
	if _deficiency_check_t <= 0.0:
		_deficiency_check_t = randf_range(2.5, 4.0)
		_apply_deficiency_tints(nutrient_mult)

	# Per-leaf wilt + recovery on the tip voxel. Reads _health_smooth
	# (low-pass-filtered health) so the visible droop tracks several
	# seconds behind the underlying state — wilting is gradual, recovery
	# more so. Only the tip handle of each leaf is tinted; the rest of
	# the leaf stays its base color so a plant that's recovering reads as
	# "healthy stem, struggling new growth" rather than uniformly dull.
	_apply_leaf_wilt()

	# ---- Starvation → leaf shedding ----
	# Throttled (25s → 60s) AND gated on global waste pressure. With many
	# stressed plants and no cleanup crew, each shed dropped a waste
	# particle, producing 5+ particles/sec across the tank — read as a
	# constant rain of falling stuff. Now most plants skip the shed when
	# the tank is already drowning in detritus.
	if _health_smooth < 0.45:
		_starvation_timer += dt
		if _starvation_timer > 60.0 and not _leaf_groups.is_empty():
			_starvation_timer = 0.0
			# Skip shed when global waste pile is over half cap. The leaf
			# stays attached (still wilted via _apply_leaf_wilt) but no new
			# waste particle joins the falling-rain effect.
			var sim_w: Node = _find_sim()
			var skip_shed: bool = false
			if sim_w != null:
				var w_arr: Variant = sim_w.get("waste")
				if w_arr is Array and (w_arr as Array).size() > 120:
					skip_shed = true
			if not skip_shed:
				_shed_oldest_leaf()

	# ---- Crypt melt recovery ----
	if _melt_active:
		# New-plant melt mini-cycle (#57): melting tissue sheds detritus and a
		# little ammonia — the authentic "new plant melt" nutrient pulse that
		# nudges a fresh tank's cycle.
		if not _melt_cycled:
			_melt_cycled = true
			var sim_m: Node = _find_sim()
			if sim_m != null:
				if sim_m.water_chemistry != null:
					sim_m.water_chemistry.ammonia = clampf(
						float(sim_m.water_chemistry.ammonia) + 0.04, 0.0, 2.0)
				_spawn_decay_waste(_world_pos)
		_melt_regrow_timer += dt
		if _melt_regrow_timer > 40.0:  # ~40 sim seconds to recover
			_melt_active = false
			_melt_regrow_timer = 0.0
			_melt_cycled = false
			is_dying = false
			health = 0.5
			_health_smooth = 0.5
			var sim_rec: Node = _find_sim()
			if sim_rec != null and sim_rec.has_method("emit_eco_event"):
				var rlabel: String = common_name if common_name != "" else plant_name
				if rlabel != "":
					sim_rec.emit_eco_event("flora",
						"%s recovering from melt — new leaves emerging." % rlabel, 1)
		return  # Don't grow during melt recovery.

	# ---- Decay ----
	if is_dying:
		_decay_timer += dt
		if _decay_timer > 2.0:
			_decay_timer = 0.0
			_decay_one_voxel()
		if voxels.is_empty():
			_on_death()
			queue_free()
		return

	# ---- Growth ----
	if emergent_growth and life_phase == LifePhase.VEGETATIVE and _at_surface_cap():
		_enter_canopy()

	if life_phase == LifePhase.CANOPY or current_height >= max_height:
		_tick_canopy(dt, nutrient_mult, substrate)
		return

	var growth_diag: Dictionary = _compute_growth_rate(growth_nutrient, light_pen, sim_v)
	var effective_rate: float = float(growth_diag.get("effective_rate", growth_rate * 0.5))
	effective_rate *= _trim_regrowth_boost
	if _growth_load_hold_s > 0.0:
		_growth_load_hold_s = maxf(0.0, _growth_load_hold_s - dt)
	else:
		growth_progress += effective_rate * dt
	if growth_progress >= 1.0:
		growth_progress = 0.0
		if _starch < 0.06:
			return
		if _try_consume_growth_budget() and _grow_one():
			_starch = maxf(0.0, _starch - 0.05)
			_spawn_growth_sparkle()
			if not is_epiphyte:
				if vascular_transport_rate > 0.0:
					var taken: float = substrate.consume_root_uptake(
						get_instance_id(), _world_pos, nutrient_demand)
					_root_reserve = minf(RESOURCE_RESERVOIR_CAP, _root_reserve + taken)
					_shoot_reserve = maxf(0.0, _shoot_reserve - nutrient_demand)
				else:
					substrate.consume_root_uptake(
						get_instance_id(), _world_pos, nutrient_demand)
				substrate.consume_iron_at(
					_world_pos, nutrient_demand * (0.025 + red_potential * 0.025))
				substrate.consume_co2_at(
					_world_pos, nutrient_demand * (0.04 + co2_demand * 0.04))
			_notify_growth_audio()
			if emergent_growth and _at_surface_cap():
				_enter_canopy()

	# ---- Pearling ----
	_tick_pearling(dt)

	# Submerged plants can still flower at genetic max height — rare event.
	if uses_flowering and not emergent_growth and not has_flower \
			and current_height >= max_height - 1 and randf() < 0.00008:
		_begin_flowering()

	# Seeding (submerged mature plants).
	_tick_seeding(dt)

	# Vegetative spread via runners (ribbon-form plants only).
	_tick_runner(dt)

	# Emersed → submersed transition. Skipped entirely once the timer
	# has run out (which is the case for any plant older than ~1 minute).
	if _emersed_remaining > 0.0:
		_emersed_remaining = maxf(0.0, _emersed_remaining - dt)

	# Crypt melt trigger throttled to every 5 sec. Water chemistry doesn't
	# crash in a single tick, so checking it every 0.1s was wasteful. The
	# trigger probability is scaled by the throttle period so the overall
	# rate of melts matches the un-throttled version.
	if melt_susceptibility >= 0.4 and not _melt_active:
		_melt_check_t -= dt
		if _melt_check_t <= 0.0:
			_melt_check_t = MELT_CHECK_PERIOD
			var now_unix: int = int(Time.get_unix_time_from_system())
			if now_unix - _last_melt_unix >= MELT_REARM_S:
				var sim_d: Node = _find_sim()
				if sim_d != null and sim_d.get("water_chemistry") != null:
					var nh3: float = float(sim_d.water_chemistry.ammonia)
					var no2: float = float(sim_d.water_chemistry.nitrite)
					if nh3 + no2 > MELT_TRIGGER_AMMONIA \
							and randf() < melt_susceptibility * MELT_CHECK_PERIOD * 0.5:
						_last_melt_unix = now_unix
						trigger_crypt_melt()
						if sim_d.has_method("emit_eco_event"):
							var label: String = common_name if common_name != "" \
								else (plant_name if plant_name != "" else "A crypt")
							sim_d.emit_eco_event("flora",
								"%s is melting — leaves dropping, will regrow from the rhizome."
								% label, 2)
							_record_melt_cluster(sim_d)


func _tick_resource_transport(dt: float) -> void:
	if vascular_transport_rate <= 0.0:
		return
	var capacity: float = vascular_transport_rate * dt * (0.5 + 0.5 * health)
	var moved: float = minf(_root_reserve, minf(capacity, RESOURCE_RESERVOIR_CAP - _shoot_reserve))
	_root_reserve -= moved
	_shoot_reserve += moved


func _tick_canopy(dt: float, _nutrient_mult: float, substrate: SubstrateGrid) -> void:
	_tick_flowering(dt)
	_tick_seeding(dt)
	_tick_pearling(dt)
	_tick_runner(dt)
	if life_phase == LifePhase.CANOPY and not has_flower and uses_flowering \
			and not monocarpic and not is_dying:
		_canopy_timer += dt
		# Reflower as a seasonal event (~2+ min), not a permanent tip hat.
		if _canopy_timer >= 140.0:
			_canopy_timer = 0.0
			_begin_flowering()
	if not is_epiphyte:
		substrate.consume_root_uptake(
			get_instance_id(), _world_pos, nutrient_demand * 0.08 * dt)


# Ribbon-form plants extend a horizontal stolon along the substrate that
# matures into a daughter plant at its tip. The chain grows one voxel
# every RUNNER_SEGMENT_TIME seconds so the player can watch the runner
# stretch. Skips if not mature enough, the cooldown is still active, or
# this individual is already running one.
func _tick_runner(dt: float) -> void:
	# Ribbon plants (Vallisneria/Sag) and carpet species (MC/HC/hairgrass)
	# both spread by runner — carpets fire faster + at lower minimum height
	# so a Monte Carlo tile actually fills its zone in reasonable time.
	# Plantlet plants (Java fern, Echinodorus) also use this path, gated
	# on has_plantlets — the visual is "a baby growing on a leaf tip,
	# detaching, rooting nearby" rather than a long horizontal stolon.
	var eligible: bool = false
	if leaf_form == "ribbon" and current_height >= 8:
		eligible = true
	if is_carpet and current_height >= 1:
		eligible = true
	if has_plantlets and current_height >= 4:
		eligible = true
	if not eligible:
		return
	if _runner_active:
		_advance_runner(dt)
		return
	_runner_cooldown = maxf(0.0, _runner_cooldown - dt)
	if _runner_cooldown > 0.0:
		return
	if is_dying:
		return
	if health < 0.55:
		return
	if is_epiphyte or has_plantlets:
		var spread_f: float = _biofilm_spread_factor()
		if spread_f < 0.12:
			return
		if randf() > spread_f:
			return
	_begin_runner()


func _begin_runner() -> void:
	var best_dir: Vector3 = _pick_runner_direction()
	var dist: float = randf_range(RUNNER_DISTANCE_MIN, RUNNER_DISTANCE_MAX)
	_runner_origin = Vector3(0.0, 0.0, 0.0)
	_runner_target = best_dir * dist
	_runner_active = true
	_runner_progress = 0.0
	_runner_voxels.clear()


func _pick_runner_direction() -> Vector3:
	var sim_d: Node = _find_sim()
	var substrate: SubstrateGrid = null
	if sim_d != null and sim_d.get("substrate") != null:
		substrate = sim_d.substrate
	var best: Vector3 = Vector3(cos(randf() * TAU), 0.0, sin(randf() * TAU))
	var best_n: float = -1.0
	for _i in 8:
		var theta: float = randf() * TAU
		var dir := Vector3(cos(theta), 0.0, sin(theta))
		var probe: Vector3 = _world_pos + dir * 1.6
		var n_val: float = 0.35
		if substrate != null:
			n_val = substrate.get_at(probe)
		if n_val > best_n:
			best_n = n_val
			best = dir.normalized()
	return best


func _advance_runner(dt: float) -> void:
	# Each placed voxel represents 1/RUNNER_VOXEL_COUNT of the chain.
	_runner_progress += dt / RUNNER_SEGMENT_TIME
	var placed: int = _runner_voxels.size()
	var should_have: int = mini(int(_runner_progress), RUNNER_VOXEL_COUNT)
	while placed < should_have:
		var t: float = (float(placed) + 1.0) / float(RUNNER_VOXEL_COUNT)
		var local_pos: Vector3 = _runner_origin.lerp(_runner_target, t)
		var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
		var rv := MeshInstance3D.new()
		rv.mesh = VoxelMat.get_box(Vector3(
			VOXEL_SIZE * 0.45,
			VOXEL_SIZE * 0.30,
			VOXEL_SIZE * 0.45,
		))
		rv.material_override = VoxelMat.make_foliage(ramp[1])  # darker green, runner is woody
		rv.position = local_pos
		add_child(rv)
		_runner_voxels.append(rv)
		for side in [-1.0, 1.0]:
			var rhizome_hair := MeshInstance3D.new()
			rhizome_hair.mesh = VoxelMat.get_box(Vector3(
				VOXEL_SIZE * 0.14, VOXEL_SIZE * 0.08, VOXEL_SIZE * 0.14))
			rhizome_hair.material_override = VoxelMat.make_foliage(ramp[0].darkened(0.08))
			rhizome_hair.position = local_pos + Vector3(
				side * VOXEL_SIZE * 0.20, -VOXEL_SIZE * 0.10, 0.0)
			add_child(rhizome_hair)
			_runner_voxels.append(rhizome_hair)
		placed += 1
	if placed >= RUNNER_VOXEL_COUNT:
		_finalize_runner()


func _finalize_runner() -> void:
	# Convert the runner tip into a daughter plant via world.spawn_seedling.
	# The runner voxels are left visible as the connecting stolon - they
	# stay attached to this plant and decay with it. The daughter is a
	# brand-new independent plant registered with SimDriver.
	var sim_driver: Node = _find_sim()
	if sim_driver != null:
		var w: Node = sim_driver.get_parent()
		if w != null and w.has_method("spawn_seedling"):
			# Convert local target → world for spawn. Y snaps to substrate
			# in spawn_seedling via the plant's own _ready logic.
			var world_pos: Vector3 = global_position + _runner_target
			# Inherit ramp but with very mild drift so the daughter is
			# clearly the same species.
			var mutated_ramp: Array = ramp_override.duplicate() if ramp_override.size() == 6 else PLANT_RAMP.duplicate()
			# Carry full genome including new traits via get_seed_config,
			# AND mark no_mutate for carpet/plantlet propagation so the
			# daughter reads as the same species rather than slowly drifting
			# into something else.
			var cfg: Dictionary = get_seed_config()
			# Autonomous spread: if the daughter's spot is already crowded, the
			# runner should just not produce a plant there — NOT relocate it into
			# open water. This lets density self-limit instead of filling the tank.
			cfg["autonomous_spread"] = true
			if is_carpet or has_plantlets:
				cfg["no_mutate"] = true
			cfg["variegation"] = variegation
			cfg["quilted"] = quilted
			cfg["wavy_edges"] = wavy_edges
			cfg["iridescence"] = iridescence
			cfg["red_potential"] = red_potential
			cfg["co2_demand"] = co2_demand
			cfg["melt_susceptibility"] = melt_susceptibility
			cfg["has_plantlets"] = has_plantlets
			cfg["is_carpet"] = is_carpet
			cfg["whorled_leaves"] = whorled_leaves
			cfg["leaf_size_mult"] = leaf_size_mult
			cfg["latin_name"] = latin_name
			cfg["common_name"] = common_name
			cfg["species_id"] = species_id
			w.spawn_seedling(world_pos, mutated_ramp, generation + 1, cfg)
	_runner_active = false
	_runner_progress = 0.0
	# Carpet species fire more often than vallisneria — that's what makes
	# them carpet. Plantlets sit between the two.
	# Longer cooldowns keep runner spread from packing the tank into a wall of
	# foliage over play time — carpets still fill in, just more slowly.
	if is_carpet:
		_runner_cooldown = randf_range(60.0, 110.0)
	elif has_plantlets:
		_runner_cooldown = randf_range(90.0, 160.0)
	else:
		_runner_cooldown = randf_range(RUNNER_COOLDOWN_MIN, RUNNER_COOLDOWN_MAX)


# ---- Flowering lifecycle ----

func _begin_flowering() -> void:
	wake_plant("reproduction")
	if not uses_flowering:
		return
	if flower_stage != FlowerStage.NONE:
		return
	var sim_gate: Node = _find_sim()
	if sim_gate != null and sim_gate.get("tank_vitals") != null:
		var vitals: Dictionary = sim_gate.tank_vitals
		if int(vitals.get("cycle_phase", 0)) < WaterChemistry.CyclePhase.CYCLING:
			return
	if _health_smooth < 0.6:
		return
	var first_flower: bool = not has_flower
	_pollen_ready = true
	flower_stage = FlowerStage.BUD
	_flower_timer = 0.0
	has_flower = true
	_pick_flower_palette()
	_flower_silhouette = _resolve_flower_silhouette()
	# Build bud.
	_flower_node = Node3D.new()
	_flower_node.name = "Flower"
	_flower_node.position = _tip_bloom_local_pos()
	add_child(_flower_node)
	_stabilize_flower_against_lean()
	var bud_voxels: Array = _build_flower_bud_voxels()
	for v in bud_voxels:
		_flower_node.add_child(v)
		bloom_voxels.append(v)
	_apply_sway_personality()
	if first_flower and sim_gate != null and sim_gate.has_method("emit_eco_event"):
		var fl: String = common_name if common_name != "" else plant_name
		if fl != "":
			sim_gate.emit_eco_event("flora", "%s flowering — tank cycle paying off." % fl, 1)
	var amb: Node = get_node_or_null("/root/AmbientAudio")
	if amb != null and amb.has_method("play_aquarium_event"):
		amb.play_aquarium_event("story", 0.55)


func _resolve_flower_silhouette() -> String:
	if species_id.contains("cattail") or (emergent_growth and leaf_form == "ribbon"):
		return "spike"
	if leaf_form in ["paddle", "spade", "lobed", "oval", "downy"] \
			or species_id.contains("crypt"):
		return "crypt"
	# Lance / stem / column — small spathe rather than a big radial daisy.
	if leaf_form in ["lance", "pinnate", "fingered", "column"]:
		return "crypt"
	return "default"


func _build_flower_bud_voxels() -> Array:
	match _flower_silhouette:
		"spike":
			return LeafShapes.build_spike_bud(_flower_petal_color.darkened(0.35))
		"crypt":
			return LeafShapes.build_crypt_bud(_flower_petal_color.darkened(0.25))
		_:
			return LeafShapes.build_bud(_flower_petal_color.darkened(0.3))


# Pick a petal + center color pair, biased by the current tank's light /
# warmth / saltwater / substrate so blooms feel like an event tied to the
# environment instead of a random sticker. ~14 palettes — players still
# see fresh tints after many seasons. A small "rare bloom" branch (~6 %
# chance) produces saturated jewel tones that have no environment bias.
func _pick_flower_palette() -> void:
	# Sample environment. Falls back to neutral defaults if no sim found.
	var sim_n: Node = _find_sim()
	var pressure: Dictionary = {
		"light": 0.5, "warmth": 0.6, "saltwater": false,
		"substrate": 0.5, "cover": 0.0, "edge": 0.5, "depth": 0.5,
		"substrate_local": 0.5, "o2": 0.55,
	}
	if sim_n != null:
		pressure = EvolutionPressure.sample_from_sim(sim_n, global_position)
	var light: float = float(pressure.get("light", 0.5))
	var warmth: float = float(pressure.get("warmth", 0.6))
	var sub: float = float(pressure.get("substrate", 0.5))
	var salt: bool = not not pressure.get("saltwater", false)

	# Rare-bloom branch: full-saturation tropical tones, no env bias.
	# Fires ~6 % of blooms — visible as a clear "wow, look at that one"
	# event without overwhelming the more common environment-fitted tints.
	if randf() < 0.06:
		var rare_palettes: Array = [
			[Color8(255, 70, 130),  Color8(255, 240, 90)],   # hot magenta + bright gold
			[Color8(110, 70, 220),  Color8(245, 220, 140)],  # vivid violet + cream
			[Color8(40, 220, 200),  Color8(245, 220, 100)],  # cyan teal + gold
			[Color8(255, 130, 30),  Color8(255, 230, 110)],  # tangerine + sunlight
			[Color8(255, 245, 240), Color8(255, 110, 110)],  # pale blush + ember
		]
		var rare: Array = rare_palettes[randi() % rare_palettes.size()]
		_flower_petal_color = rare[0]
		_flower_center_color = rare[1]
		return

	# Build a weighted candidate list. Weights reflect how well a hue
	# pair fits the current tank — bright light favors golds and oranges,
	# warm tanks favor reds and corals, cool tanks favor whites and blues,
	# saltwater shifts toward violet / aqua, rich substrate biases dense
	# pinks.
	var palettes: Array = [
		[Color8(230, 130, 200), Color8(245, 220, 90)],   # pink + gold
		[Color8(245, 220, 90),  Color8(255, 180, 60)],   # daffodil
		[Color8(170, 130, 220), Color8(200, 180, 60)],   # lavender + gold
		[Color8(240, 240, 240), Color8(245, 195, 100)],  # white + gold
		[Color8(220, 100, 100), Color8(230, 200, 60)],   # red + yellow
		[Color8(255, 165, 80),  Color8(240, 100, 60)],   # tangerine + ember (warm)
		[Color8(255, 215, 130), Color8(235, 145, 60)],   # apricot + amber (sunlit)
		[Color8(120, 195, 230), Color8(245, 230, 140)],  # ice-blue + soft gold (cool)
		[Color8(155, 120, 195), Color8(220, 195, 220)],  # mauve + pale lilac
		[Color8(85, 145, 200),  Color8(220, 230, 255)],  # cornflower + frost (salt)
		[Color8(95, 200, 175),  Color8(245, 245, 200)],  # aqua + pale cream (salt)
		[Color8(245, 165, 195), Color8(255, 240, 200)],  # peony pink + cream
		[Color8(200, 60, 80),   Color8(255, 220, 150)],  # crimson + buttercream (rich sub)
		[Color8(80, 160, 100),  Color8(245, 235, 130)],  # mint + gold (mild)
	]
	var weights: Array[float] = [
		1.0, 1.0, 1.0, 1.0, 1.0,
		warmth * 1.4 + 0.2,           # tangerine
		light * 1.6 + warmth * 0.4,   # apricot
		(1.0 - warmth) * 1.3 + 0.2,   # ice-blue
		(1.0 - light) * 0.8 + 0.4,    # mauve
		(2.0 if salt else 0.05),      # cornflower (salt-only)
		(1.6 if salt else 0.05),      # aqua (salt-only)
		sub * 1.2 + 0.4,              # peony
		sub * 1.4 + warmth * 0.3,     # crimson
		0.6 + (1.0 - warmth) * 0.4,   # mint
	]
	var total: float = 0.0
	for w in weights:
		total += w
	var pick: float = randf() * total
	var idx: int = 0
	for i in weights.size():
		pick -= weights[i]
		if pick <= 0.0:
			idx = i
			break
	var pal: Array = palettes[idx]
	# Small per-bloom hue jitter so even repeated picks vary.
	var jitter := Color(randf_range(-0.04, 0.04), randf_range(-0.04, 0.04), randf_range(-0.04, 0.04))
	_flower_petal_color = (pal[0] as Color) + jitter
	_flower_petal_color = Color(
		clampf(_flower_petal_color.r, 0.0, 1.0),
		clampf(_flower_petal_color.g, 0.0, 1.0),
		clampf(_flower_petal_color.b, 0.0, 1.0))
	_flower_center_color = pal[1]


func _tick_flowering(dt: float) -> void:
	if flower_stage == FlowerStage.NONE:
		return
	_flower_timer += dt
	match flower_stage:
		FlowerStage.BUD:
			# Bud grows for ~5 seconds, then starts opening.
			if _flower_timer > 5.0:
				flower_stage = FlowerStage.OPENING
				_flower_timer = 0.0
				_flower_open_frac = 0.0
				# Clear bud voxels and build the flower meshes once.
				_clear_bloom()
				_build_flower_meshes_once()
		FlowerStage.OPENING:
			_flower_open_frac = clampf(_flower_timer / 4.0, 0.0, 1.0)
			if _flower_silhouette == "default":
				LeafShapes.update_flower(bloom_voxels, 5, _flower_open_frac)
			elif _flower_node != null and is_instance_valid(_flower_node):
				_flower_node.scale = Vector3.ONE.lerp(Vector3(1.08, 1.12, 1.08), _flower_open_frac)
			if _flower_timer > 4.0:
				flower_stage = FlowerStage.MATURE
				_flower_timer = 0.0
		FlowerStage.MATURE:
			# Stay open for 20-40 seconds, then transition to seed pod.
			if _flower_timer > 25.0:
				flower_stage = FlowerStage.SEED_POD
				_flower_timer = 0.0
				_clear_bloom()
				# Build seed pod.
				var pod_voxels: Array = LeafShapes.build_seed_pod(_flower_center_color)
				if _flower_node != null and is_instance_valid(_flower_node):
					for v in pod_voxels:
						_flower_node.add_child(v)
						bloom_voxels.append(v)
		FlowerStage.SEED_POD:
			# Mature for 10 seconds, then release seeds.
			if _flower_timer > 10.0:
				flower_stage = FlowerStage.RELEASING
				_flower_timer = 0.0
		FlowerStage.RELEASING:
			# Release seeds, then senesce (monocarpic) or rest (perennial).
			if _flower_timer > 2.0:
				_cast_seed()
				_clear_bloom()
				if _flower_node != null and is_instance_valid(_flower_node):
					_flower_node.queue_free()
					_flower_node = null
				flower_stage = FlowerStage.NONE
				has_flower = false
				_apply_sway_personality()
				_finish_reproduction_cycle()


func _build_flower_meshes_once() -> void:
	if _flower_node == null or not is_instance_valid(_flower_node):
		return
	var flower_voxels: Array
	match _flower_silhouette:
		"spike":
			flower_voxels = LeafShapes.build_spike_flower(
				_flower_petal_color.darkened(0.2), _flower_center_color)
		"crypt":
			flower_voxels = LeafShapes.build_crypt_flower(
				_flower_petal_color, _flower_center_color)
		_:
			flower_voxels = LeafShapes.build_flower(
				_flower_petal_color, _flower_center_color, 5, 0.0)
	for v in flower_voxels:
		_flower_node.add_child(v)
		bloom_voxels.append(v)


func _clear_bloom() -> void:
	for v in bloom_voxels:
		if is_instance_valid(v):
			v.queue_free()
	bloom_voxels.clear()

var _sim_driver_ref: Node = null
# Cached TankConfig autoload — resolved once, reused. _get_flow_bias runs in the
# per-tick plant tick(), so the old per-call "/root/TankConfig" lookup cost one
# autoload resolve per plant per tick.
var _cfg_ref: Node = null

func _notify_growth_audio() -> void:
	if randf() > 0.12:
		return
	var sim_driver: Node = _find_sim()
	if sim_driver != null and sim_driver.has_method("_play_ambient_event"):
		var intensity: float = clampf(float(current_height) / float(maxi(max_height, 1)), 0.2, 0.9)
		sim_driver._play_ambient_event("plant", intensity)


func _find_sim() -> Node:
	if _sim_driver_ref != null and is_instance_valid(_sim_driver_ref):
		return _sim_driver_ref
	var p: Node = get_parent()
	while p != null:
		var s := p.get_node_or_null("SimDriver")
		if s != null:
			_sim_driver_ref = s
			return s
		p = p.get_parent()
	return null


# ---- Pearling ----

func _try_consume_growth_budget() -> bool:
	var sim_driver: Node = _find_sim()
	if sim_driver != null and sim_driver.has_method("try_consume_plant_growth"):
		return not not sim_driver.try_consume_plant_growth()
	return true


func _cast_root_shadow() -> void:
	var sim_driver: Node = _find_sim()
	if sim_driver == null:
		return
	var w: Node = sim_driver.get_parent()
	if w != null and w.has_method("tint_substrate_cell"):
		w.tint_substrate_cell(global_position.x, global_position.z,
			Color(0.16, 0.20, 0.12), 0.22)


func _tick_pearling(_dt: float) -> void:
	# CO2-met plants become pearling-eligible even when the genome rng didn't
	# pick them at spawn time — that's how real CO2-injected tanks light up
	# half their stems with champagne bubbles instead of the random subset.
	var sim_driver: Node = _find_sim()
	if sim_driver == null:
		return
	var co2_now: float = 0.0
	if sim_driver.has_method("co2_level"):
		co2_now = sim_driver.co2_level()
	var co2_met: float = clampf((co2_now - co2_demand * 0.3) / maxf(co2_demand, 0.001), 0.0, 1.0)
	if not _pearling_eligible and co2_met > 0.6 and randf() < 0.04:
		# Promote this plant into the pearling pool when CO2 is dosed. The
		# random gate spreads the promotion across ticks so a sudden CO2
		# bump doesn't turn every plant on simultaneously.
		_pearling_eligible = true
		_pearling_strength = randf_range(0.6, 1.1)
	if not _pearling_eligible:
		return
	var o2: float = float(sim_driver.get("dissolved_o2"))
	var daylight: float = 1.0
	if sim_driver.has_method("daylight"):
		daylight = sim_driver.daylight()
	# Pearl when: O2 super-saturated + bright light + plant healthy + tall
	# enough that you'd actually see the bubble stream. CO2-met plants
	# get a multiplicative boost so a dosed tank reads dramatically — the
	# difference between an okay tank and an aquascaping-magazine tank is
	# visible bubble streams on most of the stems.
	var pearl_factor: float = clampf((o2 - 0.78) / 0.22, 0.0, 1.0) \
		* clampf((daylight - 0.45) / 0.55, 0.0, 1.0) \
		* clampf((health - 0.55) / 0.45, 0.0, 1.0) \
		* clampf(float(current_height - 3) / 12.0, 0.0, 1.0)
	# CO2 multiplier: 1.0 at no-CO2, up to 2.2× when fully dosed AND the
	# plant's co2_demand is being met. Pearling cranks visibly under good
	# conditions, fades to subtle under poor ones.
	pearl_factor *= (1.0 + co2_met * 1.2)
	var w: Node = sim_driver.get_parent()
	if w != null and w.has_method("light_penetration_at"):
		pearl_factor *= float(w.light_penetration_at(global_position))
	var global_damp: float = 1.0
	var should_pearl: bool = pearl_factor > 0.10
	if should_pearl and pearl_factor > 0.25:
		pearl_factor = minf(1.0, pearl_factor * 1.22)
	if should_pearl and sim_driver.has_method("try_claim_pearling_slot"):
		global_damp = float(sim_driver.try_claim_pearling_slot(pearl_factor))
		should_pearl = global_damp > 0.02
	if should_pearl:
		if _pearling_particles == null:
			_setup_pearling()
		if _pearling_particles == null:
			return
		if not _pearling_active:
			_pearling_active = true
			_pearling_particles.emitting = true
		var amount_ratio: float = clampf(
			(0.12 + pearl_factor * 0.55) * _pearling_strength * global_damp,
			0.06, 0.62)
		_pearling_particles.set("amount_ratio", amount_ratio)
		# Bubble size ladder — micro specks at low O₂, larger pass-2 bubbles when
		# pearling hard (style-guide 1px → 2×2 → 3×3 tiers after quantize).
		var pm: ParticleProcessMaterial = _pearling_particles.process_material as ParticleProcessMaterial
		if pm != null:
			if w != null and w.has_method("sample_flow"):
				var flow_v: Vector3 = w.sample_flow(global_position)
				var rise: Vector3 = Vector3(flow_v.x * 0.35, 1.0, flow_v.z * 0.35).normalized()
				pm.direction = rise
				pm.gravity = Vector3(flow_v.x * 0.12, 0.10, flow_v.z * 0.12)
			if pearl_factor > 0.72:
				pm.scale_min = 0.10
				pm.scale_max = 0.22
			elif pearl_factor > 0.38:
				pm.scale_min = 0.08
				pm.scale_max = 0.16
			else:
				pm.scale_min = 0.06
				pm.scale_max = 0.12
		if pearl_factor > 0.55 and _shared_pearling_mesh_medium != null:
			if _pearling_particles.draw_passes < 2:
				var med: SphereMesh = _shared_pearling_mesh_medium.duplicate()
				med.material = VoxelMat.make_bubble(
					Color(1.08, 1.14, 1.20, _pearling_opacity * 0.85), 1.32)
				_pearling_particles.draw_passes = 2
				_pearling_particles.draw_pass_2 = med
		elif _pearling_particles.draw_passes > 1:
			_pearling_particles.draw_passes = 1
		# Position at canopy tips for pearling hotspots.
		var tip_y: float = _get_stem_top()
		if leaf_form in ["paddle", "lily", "pad"]:
			tip_y += VOXEL_SIZE * 0.8
		_pearling_particles.position = Vector3(0, tip_y, 0)
	elif _pearling_active:
		_pearling_active = false
		if _pearling_particles != null:
			_pearling_particles.emitting = false
			if _pearling_particles.draw_passes > 1:
				_pearling_particles.draw_passes = 1
		if w != null and w.has_method("release_pearling_emitter"):
			w.release_pearling_emitter(self)
		_pearling_particles = null


# ---- Seeding ----

func _tick_seeding(dt: float) -> void:
	seed_timer += dt
	# Germinate buried seeds (#14).
	var sim_d: Node = _find_sim()
	if sim_d != null and sim_d.substrate != null:
		var bank: float = sim_d.substrate.get_seed_bank_at(_world_pos)
		if bank > 0.2 and seed_timer > 12.0:
			var dl: float = sim_d.daylight() if sim_d.has_method("daylight") else 0.5
			if dl > 0.45 and substrate_nutrient_ok(sim_d.substrate):
				var lot: Dictionary = sim_d.substrate.take_eligible_seed_lot_at(
					_world_pos, 0.25, {
						"daylight": dl,
						"nutrient_ok": true,
					})
				if float(lot.get("quantity", 0.0)) > 0.1:
					_germinate_seed_at(_world_pos, sim_d, lot.get("genome", {}))
					seed_timer = 0.0
	if has_emerged:
		if seed_timer >= 18.0 and randf() < 0.5:
			seed_timer = 0.0
			if _cast_seed():
				_seeds_cast_this_cycle += 1
				if _seeds_cast_this_cycle >= MAX_SEEDS_PER_CYCLE:
					_finish_reproduction_cycle()
	elif current_height >= max_height and seed_timer >= 60.0 and randf() < 0.25:
		seed_timer = 0.0
		_cast_seed()


# ---- Decay & death ----

func _begin_dying() -> void:
	wake_plant("damage")
	if is_dying:
		return
	is_dying = true
	_decay_timer = 0.0
	# Stop pearling.
	if _pearling_active:
		_pearling_active = false
		if _pearling_particles != null:
			_pearling_particles.emitting = false
			if _pearling_particles.draw_passes > 1:
				_pearling_particles.draw_passes = 1


func _decay_one_voxel() -> void:
	if voxels.is_empty():
		return
	# Tip dies first — that tip is also the canopy bob target.
	_stop_canopy_bob()
	# Remove from the top (tips die first).
	var v: VoxelBatch.Handle = voxels.pop_back()
	if v != null and v.alive:
		# Spawn a tiny waste particle at the voxel's world position.
		_spawn_decay_waste(global_transform * v.local_pos)
		v.hide()
	if _stem_batch != null:
		_stem_batch.flush()
	_recalc_height()


# Aquascape trim tool — remove top fraction of stem, return snapshot for undo.
func trim_for_aquascape(frac: float, mode: String = "all") -> Dictionary:
	wake_plant("damage")
	if is_dying or voxels.is_empty():
		return {}
	_stop_canopy_bob()
	var snap: Dictionary = to_save_dict()
	var amount: float = clampf(frac, 0.05, 0.75)
	match mode:
		"top":
			var remove_n: int = maxi(1, int(ceil(float(voxels.size()) * amount * 0.55)))
			_spawn_stem_fragment(maxi(2, remove_n))
			for _i in remove_n:
				if voxels.is_empty():
					break
				_decay_one_voxel()
		"sides":
			var remove_s: int = maxi(1, int(ceil(float(voxels.size()) * amount * 0.35)))
			for _i in remove_s:
				if voxels.is_empty():
					break
				var v: VoxelBatch.Handle = voxels.pop_front()
				if v != null and v.alive:
					_spawn_decay_waste(global_transform * v.local_pos)
					v.hide()
				if _stem_batch != null:
					_stem_batch.flush()
				_recalc_height()
		"mow":
			if is_carpet:
				var cut: int = maxi(1, int(float(current_height) * amount))
				current_height = maxi(1, current_height - cut)
			var remove_m: int = maxi(1, int(ceil(float(voxels.size()) * amount * 0.4)))
			for _i in remove_m:
				if voxels.is_empty():
					break
				_decay_one_voxel()
		_:
			var remove_n: int = maxi(1, int(ceil(float(voxels.size()) * amount)))
			_spawn_stem_fragment(maxi(2, remove_n))
			for _i in remove_n:
				if voxels.is_empty():
					break
				_decay_one_voxel()
	_trigger_trim_recoil()
	return snap


func _trigger_trim_recoil() -> void:
	# LIVING_MOTION #68 — keeper trim echoes as spring-back + regrowth burst.
	_trim_recoil_t = 1.35
	_trim_regrowth_boost = 1.85
	_brush_bend_vel += Vector2(randf_range(-0.42, 0.42), randf_range(-0.28, 0.32))


func _shed_oldest_leaf() -> void:
	# Drop the oldest (bottom) leaf, creating detritus. Leaves are MultiMesh
	# instances now, so we hide the whole handle group instead of freeing a node.
	if _leaf_groups.is_empty():
		return
	var oldest: Array = _leaf_groups.pop_front()
	if _leaf_ages.size() > 0:
		_leaf_ages.pop_front()
	if _leaf_states.size() > 0:
		_leaf_states.pop_front()
	for h in oldest:
		h.hide()
	_spawn_decay_waste(global_position)


func trigger_crypt_melt() -> void:
	# Dramatic melt: all leaves dissolve rapidly, but roots persist.
	_melt_active = true
	_melt_regrow_timer = 0.0
	_pre_melt_height = current_height
	var top_y: float = _get_stem_top()
	var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
	for i in mini(6, maxi(1, current_height)):
		_spawn_melt_ghost(Vector3(
			randf_range(-VOXEL_SIZE * 0.55, VOXEL_SIZE * 0.55),
			top_y + randf_range(-VOXEL_SIZE * 0.35, VOXEL_SIZE * 0.65),
			randf_range(-VOXEL_SIZE * 0.55, VOXEL_SIZE * 0.55),
		), ramp[clampi(int(randf() * 5.0), 0, 5)] as Color)
	# Burst: remove all stem voxels rapidly + clear the foliage MultiMesh.
	_stop_canopy_bob()
	for v in voxels:
		if v != null and v.alive:
			_spawn_melt_ghost(v.local_pos, v.base_color)
			_spawn_decay_waste(global_transform * v.local_pos)
			v.hide()
	voxels.clear()
	if _stem_batch != null:
		_stem_batch.clear()
	if _foliage_batch != null:
		_foliage_batch.clear()
	_leaf_groups.clear()
	_leaf_ages.clear()
	_leaf_states.clear()
	current_height = 0
	_clear_bloom()
	has_flower = false
	flower_stage = FlowerStage.NONE
	# Roots stay! They're the rhizome that will regrow.


func _spawn_melt_ghost(local_pos: Vector3, col: Color) -> void:
	var ghost := MeshInstance3D.new()
	ghost.mesh = VoxelMat.get_box(Vector3(
		VOXEL_SIZE * randf_range(0.35, 0.75),
		VOXEL_SIZE * randf_range(0.35, 0.75),
		VOXEL_SIZE * randf_range(0.25, 0.55),
	))
	var mat: ShaderMaterial = VoxelMat.make_foliage(col).duplicate()
	ghost.material_override = mat
	ghost.position = local_pos
	add_child(ghost)
	var end_col: Color = Color(col.r, col.g, col.b, 0.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ghost, "position", local_pos + Vector3(
		randf_range(-0.08, 0.08), -VOXEL_SIZE * 0.45, randf_range(-0.08, 0.08)), 1.35)
	tw.tween_property(mat, "shader_parameter/albedo", end_col, 1.35)
	tw.chain().tween_callback(ghost.queue_free)


func _spawn_decay_waste(at: Vector3) -> void:
	var sim_driver: Node = _find_sim()
	if sim_driver == null:
		return
	if sim_driver.has_method("_spawn_waste"):
		# The visual settles before entering mulm; it no longer grants an
		# immediate dissolved-nutrient pulse.
		sim_driver._spawn_waste(at, 0.06, WasteParticle.KIND_PLANT)
	elif sim_driver.get("substrate") != null \
			and sim_driver.substrate.has_method("deposit_litter_at"):
		sim_driver.substrate.deposit_litter_at(at, 0.06)


# ---- Leaf flutter ----

func _flutter_leaves(_dt: float) -> void:
	pass


# ---- Flow response ----

func _get_flow_bias() -> float:
	var w: Node = get_parent()
	if w != null and w.has_method("sample_flow"):
		var flow: Vector3 = w.sample_flow(_world_pos)
		return clampf(flow.x * 0.55 + flow.z * 0.35, -0.65, 0.65)
	var sim_driver: Node = _find_sim()
	if sim_driver == null:
		return 0.0
	var aeration_x: float = 0.0
	if _cfg_ref == null or not is_instance_valid(_cfg_ref):
		_cfg_ref = sim_driver.get_node_or_null("/root/TankConfig")
	var cfg := _cfg_ref
	if cfg != null:
		aeration_x = float(cfg.get("aeration_x_frac")) * 8.0  # rough world space
	var dx: float = _world_pos.x - aeration_x
	# Strength falls off with distance.
	var strength: float = clampf(1.0 - absf(dx) / 12.0, 0.0, 0.5)
	return sign(dx) * strength


# ---- Pinholes (potassium deficiency symptom) ----

func _apply_pinholes() -> void:
	_has_pinholes = true
	# REAL_TANK_FIDELITY #116 — torn / holed blades: prefer mid-leaf voxels on
	# ribbons so tips stay, leaving ragged gaps rather than random salt.
	var n_holes: int = maxi(1, int(voxels.size() / 6.0))
	var ribbon: bool = leaf_form == "ribbon" or species_id.contains("valli")
	for i in n_holes:
		var idx: int
		if ribbon and voxels.size() > 4:
			# Mid-blade band (avoid base + tip).
			var lo: int = int(float(voxels.size()) * 0.25)
			var hi: int = int(float(voxels.size()) * 0.85)
			idx = clampi(lo + randi() % maxi(1, hi - lo), 0, voxels.size() - 1)
		else:
			idx = randi() % maxi(1, voxels.size())
		if idx < voxels.size() and voxels[idx] != null and voxels[idx].alive:
			voxels[idx].set_visible(false)
			# Neighboring nibble for a torn edge read.
			if ribbon and idx + 1 < voxels.size() and randf() < 0.45 \
					and voxels[idx + 1] != null and voxels[idx + 1].alive:
				voxels[idx + 1].set_visible(false)
	if _stem_batch != null:
		_stem_batch.flush()


# Fish nibbling: remove up to `amount` bites from flower or stem tip.
# Return value = food units gained (flowers count double).
func has_grazeable_flower() -> bool:
	return has_flower and flower_stage >= FlowerStage.MATURE \
		and not bloom_voxels.is_empty()


func graze_target_world_y() -> float:
	if has_flower and not bloom_voxels.is_empty() \
			and _flower_node != null and is_instance_valid(_flower_node):
		return _flower_node.global_position.y + VOXEL_SIZE * 0.2
	return top_world_y()


func _nibble_flower(amount: int) -> int:
	var food: int = 0
	for _i in amount:
		if bloom_voxels.is_empty():
			break
		var v: MeshInstance3D = bloom_voxels.pop_back()
		if is_instance_valid(v):
			v.queue_free()
		if flower_stage >= FlowerStage.MATURE:
			food += 2
		else:
			food += 1
	if bloom_voxels.is_empty():
		_on_flower_consumed()
	return food


func _on_flower_consumed() -> void:
	_clear_bloom()
	if _flower_node != null and is_instance_valid(_flower_node):
		_flower_node.queue_free()
		_flower_node = null
	has_flower = false
	flower_stage = FlowerStage.NONE
	if monocarpic:
		_finish_reproduction_cycle()
	else:
		_canopy_timer = 0.0


func nibble(amount: int) -> int:
	wake_plant("damage")
	_grazing_pressure = clampf(_grazing_pressure + float(amount) * 0.08, 0.0, 1.0)
	_lifetime_grazing_pressure = clampf(
		_lifetime_grazing_pressure + float(amount) * 0.025, 0.0, 1.0)
	# Aufwuchs grazing (#30): eat leaf biofilm without always removing tissue.
	if _graze_leaf_biofilm(amount):
		return amount
	if has_flower and not bloom_voxels.is_empty() \
			and flower_stage >= FlowerStage.BUD:
		return _nibble_flower(amount)
	var removed: int = 0
	var any_stem_lost: bool = false
	var stem_before: int = voxels.size()
	if amount > 0 and not voxels.is_empty():
		_stop_canopy_bob()
	for i in amount:
		if not voxels.is_empty():
			var v: VoxelBatch.Handle = voxels.pop_back()
			if v != null and v.alive:
				v.hide()
			removed += 1
			any_stem_lost = true
		elif _take_youngest_leaf_voxel():
			removed += 1
		elif _rasp_leaf_scar():
			removed += 1
		else:
			break
		growth_progress = 0.0
	if _stem_batch != null:
		_stem_batch.flush()
	# Fragment-to-plant (#13)
	if stem_before >= 2 and voxels.size() < stem_before - 1:
		_spawn_stem_fragment(stem_before - voxels.size())

	_recalc_height()
	var loss_fraction: float = float(stem_before - voxels.size()) / float(maxi(1, _peak_biomass))
	if reiteration_loss_threshold > 0.0 and loss_fraction >= reiteration_loss_threshold \
			and not _damage_episode_active and _reiterations_used < reiteration_capacity \
			and current_height > 0:
		_damage_episode_active = true
		_reiterations_used += 1
		_reiteration_pending_node = clampi(current_height / 2, 0, current_height - 1)
	# Real plants respond to apical loss by activating lateral buds — when
	# fish bite the top off, side shoots push from the cut node on the
	# next growth tick. We record the height at the cut so _grow_one can
	# place a lateral cluster there. Capped so a flock of grazers doesn't
	# queue up dozens of branches.
	if any_stem_lost and current_height > 0 \
			and _pending_trim_nodes.size() < MAX_PENDING_TRIM_NODES:
		_rebuild_auxin_profile(false)
		_pending_trim_nodes.append(current_height)
		_trigger_trim_recoil()

	if current_height <= 0 and voxels.is_empty() and not _has_live_leaf_voxel():
		_on_death()
		queue_free()
	return removed


func _register_leaf_age(birth_t: float) -> void:
	_leaf_states.append({
		"age_s": 0.0,
		"birth_t": birth_t,
		"phase": LeafPhase.EXPANDING,  # unfurl tween covers BUD → EXPANDING
		"damage": 0.0,
		"light_dose": 0.0,
		"dose_visual": -1.0,
		"biofilm": 0.0,
		"gsa": 0.0,
		"mobile_n": 0.0,
		"nyctinasty": 0.0,
		"senesce_paint": 0.0,
	})


func _take_youngest_leaf_voxel() -> bool:
	if _leaf_groups.is_empty():
		return false
	var best_idx: int = _leaf_groups.size() - 1
	var best_age: float = INF
	for i in _leaf_groups.size():
		var age: float = _leaf_ages[i] if i < _leaf_ages.size() else _t
		if age < best_age:
			best_age = age
			best_idx = i
	var grp: Array = _leaf_groups[best_idx]
	while not grp.is_empty():
		var h = grp.pop_back()
		if h != null and h.alive:
			h.hide()
			if grp.is_empty():
				_leaf_groups.remove_at(best_idx)
				if best_idx < _leaf_ages.size():
					_leaf_ages.remove_at(best_idx)
				if best_idx < _leaf_states.size():
					_leaf_states.remove_at(best_idx)
			return true
	if grp.is_empty():
		_leaf_groups.remove_at(best_idx)
	return false


func _rasp_leaf_scar() -> bool:
	if _leaf_states.is_empty():
		return false
	var st: Dictionary = _leaf_states[_leaf_states.size() - 1]
	st.damage = clampf(float(st.get("damage", 0.0)) + 0.22, 0.0, 1.0)
	if st.damage < 0.85:
		return true
	return _take_youngest_leaf_voxel()


func _graze_leaf_biofilm(amount: int) -> bool:
	var grazed: int = 0
	for i in mini(amount, _leaf_states.size()):
		var idx: int = _leaf_states.size() - 1 - i
		var st: Dictionary = _leaf_states[idx]
		var bio: float = float(st.get("biofilm", 0.0))
		if bio < 0.08:
			continue
		st.biofilm = maxf(0.0, bio - 0.35)
		if float(st.get("gsa", 0.0)) > 0.05:
			st.gsa = maxf(0.0, float(st.get("gsa", 0.0)) - 0.25)
		grazed += 1
	return grazed >= amount


func graze_detritus_fleck() -> bool:
	if _detritus_fleck_nodes.is_empty():
		return false
	var fleck: MeshInstance3D = _detritus_fleck_nodes.pop_back()
	if is_instance_valid(fleck):
		fleck.queue_free()
	return true


func _tick_leaf_ecology(dt: float, substrate: SubstrateGrid, sim_v: Node) -> void:
	var shed_indices: Array[int] = []
	for i in _leaf_states.size():
		var st: Dictionary = _leaf_states[i]
		st.age_s = float(st.get("age_s", 0.0)) + dt
		st.biofilm = clampf(float(st.get("biofilm", 0.0)) + dt * 0.012, 0.0, 1.0)
		if leaf_form in ["paddle", "spade", "lobed"]:
			st.gsa = clampf(float(st.get("gsa", 0.0)) + dt * 0.007, 0.0, 1.0)
		# REAL_TANK_FIDELITY #73/#117 — hair algae accumulates on old ribbon leaves.
		if leaf_form == "ribbon" or species_id.contains("valli"):
			var age_s: float = float(st.get("age_s", 0.0))
			if age_s > 45.0:
				st.hair = clampf(float(st.get("hair", 0.0)) + dt * 0.008, 0.0, 1.0)
		if leaf_form in ["needle", "downy", "pinnate"] and sim_v != null:
			var waste_arr: Variant = sim_v.get("waste")
			if waste_arr is Array and (waste_arr as Array).size() > 0 and randf() < dt * 0.15:
				substrate.add_at(_world_pos, 0.002)
			_tick_detritus_flecks(dt, sim_v)
		# Naturalism #41 — advance leaf lifecycle phase.
		_advance_leaf_phase(st, i)
		if int(st.get("phase", LeafPhase.MATURE)) == LeafPhase.SHED:
			shed_indices.append(i)
		elif int(st.get("phase", LeafPhase.MATURE)) == LeafPhase.SENESCENT:
			_paint_leaf_senescence(i, st)
	# Shed oldest-first so parallel indices stay valid while popping.
	shed_indices.reverse()
	for si in shed_indices:
		_shed_leaf_at(si)
	_tick_leaf_light_dose(dt, sim_v)
	_tick_root_bubbles(dt, substrate)
	_visual_tick_t -= dt
	if _visual_tick_t <= 0.0:
		_visual_tick_t = 0.25
		_tick_nyctinasty(sim_v)
		_tick_dynamic_blush(sim_v)
		_tick_leaf_hair_visuals()
		if _foliage_mat != null and leaf_form in ["paddle", "spade", "lobed"]:
			var film_avg: float = 0.0
			var gsa_avg: float = 0.0
			for st2 in _leaf_states:
				film_avg += float(st2.get("biofilm", 0.0))
				gsa_avg += float(st2.get("gsa", 0.0))
			if not _leaf_states.is_empty():
				film_avg /= float(_leaf_states.size())
				gsa_avg /= float(_leaf_states.size())
				var film_mix: float = clampf(film_avg * 0.4 + gsa_avg * 0.55, 0.0, 0.65)
				_foliage_mat.set_shader_parameter("palette_saturation",
					lerpf(float(_foliage_mat.get_shader_parameter("palette_saturation")),
						0.72, film_mix))
				_foliage_mat.set_shader_parameter("palette_warmth",
					float(_foliage_mat.get_shader_parameter("palette_warmth")) + gsa_avg * 0.18)


func _tick_leaf_light_dose(dt: float, sim_v: Node) -> void:
	if red_potential <= 0.0 or _leaf_states.is_empty():
		return
	var daylight_now: float = clampf(
		float(sim_v.daylight()) if sim_v != null and sim_v.has_method("daylight") else 0.5,
		0.0, 1.0)
	for i in mini(_leaf_states.size(), _leaf_groups.size()):
		var state: Dictionary = _leaf_states[i]
		var canopy_position: float = float(i + 1) / float(maxi(1, _leaf_states.size()))
		var exposure: float = daylight_now * lerpf(0.35, 1.0, canopy_position)
		var dose: float = clampf(lerpf(float(state.get("light_dose", 0.0)),
			exposure, clampf(dt / 45.0, 0.0, 1.0)), 0.0, 1.0)
		state.light_dose = dose
		if absf(dose - float(state.get("dose_visual", -1.0))) < 0.02:
			continue
		state.dose_visual = dose
		for handle_v in _leaf_groups[i]:
			var handle: VoxelBatch.Handle = handle_v
			if handle != null and handle.alive:
				var custom: Color = handle.custom_data
				custom.b = dose
				handle.set_custom_data(custom)


func _leaf_light_doses_snapshot() -> Array:
	var doses: Array = []
	for state_v in _leaf_states:
		doses.append(clampf(float((state_v as Dictionary).get("light_dose", 0.0)), 0.0, 1.0))
	return doses


func _restore_leaf_light_doses(saved: Variant) -> void:
	if not saved is Array:
		return
	var values: Array = saved
	for i in mini(values.size(), _leaf_states.size()):
		var dose: float = clampf(float(values[i]), 0.0, 1.0)
		var state: Dictionary = _leaf_states[i]
		state.light_dose = dose
		state.dose_visual = -1.0


func _advance_leaf_phase(st: Dictionary, _idx: int) -> void:
	var age_s: float = float(st.get("age_s", 0.0))
	var phase: int = int(st.get("phase", LeafPhase.EXPANDING))
	# Stress and health shorten mature life — starving plants turn over faster.
	var life_scale: float = lerpf(0.55, 1.0, clampf(_health_smooth, 0.0, 1.0))
	var mature_end: float = LEAF_EXPAND_S + LEAF_MATURE_S * life_scale
	var senesce_end: float = mature_end + LEAF_SENESCE_S
	match phase:
		LeafPhase.BUD:
			st.phase = LeafPhase.EXPANDING
		LeafPhase.EXPANDING:
			if age_s >= LEAF_EXPAND_S:
				st.phase = LeafPhase.MATURE
		LeafPhase.MATURE:
			if age_s >= mature_end:
				st.phase = LeafPhase.SENESCENT
		LeafPhase.SENESCENT:
			if age_s >= senesce_end:
				st.phase = LeafPhase.SHED


func _paint_leaf_senescence(idx: int, st: Dictionary) -> void:
	if idx < 0 or idx >= _leaf_groups.size():
		return
	var prev: float = float(st.get("senesce_paint", 0.0))
	var age_s: float = float(st.get("age_s", 0.0))
	var life_scale: float = lerpf(0.55, 1.0, clampf(_health_smooth, 0.0, 1.0))
	var mature_end: float = LEAF_EXPAND_S + LEAF_MATURE_S * life_scale
	var t: float = clampf((age_s - mature_end) / maxf(LEAF_SENESCE_S, 0.01), 0.0, 1.0)
	if absf(t - prev) < 0.08:
		return
	st.senesce_paint = t
	var grp: Array = _leaf_groups[idx] as Array
	if grp.is_empty():
		return
	# Tip first, then work inward — classic leaf dieback.
	var tip: VoxelBatch.Handle = grp[grp.size() - 1] as VoxelBatch.Handle
	if tip != null and tip.alive:
		tip.set_color(tip.base_color.lerp(_SENESCE_TIP_COLOR, t * 0.85))
	if t > 0.45 and grp.size() > 2:
		var mid: VoxelBatch.Handle = grp[int(float(grp.size()) * 0.55)] as VoxelBatch.Handle
		if mid != null and mid.alive:
			mid.set_color(mid.base_color.lerp(_SENESCE_TIP_COLOR, (t - 0.45) * 1.2))


func _shed_leaf_at(idx: int) -> void:
	if idx < 0 or idx >= _leaf_groups.size():
		return
	var grp: Array = _leaf_groups[idx] as Array
	_leaf_groups.remove_at(idx)
	if idx < _leaf_ages.size():
		_leaf_ages.remove_at(idx)
	if idx < _leaf_states.size():
		_leaf_states.remove_at(idx)
	for h in grp:
		if h != null and h.alive:
			h.hide()
	_spawn_decay_waste(global_position)


var _leaf_hair_nodes: Array = []


func _tick_leaf_hair_visuals() -> void:
	# Spawn sparse filament voxels on aged ribbon leaves (#73/#117).
	if not (leaf_form == "ribbon" or species_id.contains("valli")):
		return
	if voxels.is_empty() or _leaf_hair_nodes.size() >= 8:
		return
	var hair_avg: float = 0.0
	for st in _leaf_states:
		hair_avg += float(st.get("hair", 0.0))
	if not _leaf_states.is_empty():
		hair_avg /= float(_leaf_states.size())
	if hair_avg < 0.25 or randf() > hair_avg * 0.55:
		return
	var idx: int = clampi(int(float(voxels.size()) * randf_range(0.35, 0.9)), 0, voxels.size() - 1)
	var host: VoxelBatch.Handle = voxels[idx]
	if host == null or not host.alive or not host.visible:
		return
	var fil := MeshInstance3D.new()
	fil.name = "LeafHair"
	fil.mesh = VoxelMat.get_box(Vector3(0.04, randf_range(0.18, 0.38), 0.04))
	fil.material_override = VoxelMat.make_foliage(Color8(70, 110, 55))
	fil.position = host.local_pos + Vector3(randf_range(-0.06, 0.06), 0.02, randf_range(-0.06, 0.06))
	fil.rotation = Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.5, 0.5))
	add_child(fil)
	_leaf_hair_nodes.append(fil)


func _tick_root_bubbles(dt: float, substrate: SubstrateGrid) -> void:
	if is_epiphyte or _root_count < 3 or is_dying:
		return
	var root_o2: float = substrate.get_root_oxygen_at(_world_pos)
	if root_o2 < 0.12 or _health_smooth < 0.45:
		return
	_root_bubble_t += dt
	if _root_bubble_t < randf_range(2.5, 5.5):
		return
	_root_bubble_t = 0.0
	var bubble := MeshInstance3D.new()
	bubble.mesh = VoxelMat.get_box(Vector3(0.05, 0.05, 0.05))
	bubble.material_override = VoxelMat.make_bubble()
	bubble.position = Vector3(
		randf_range(-0.12, 0.12), -VOXEL_SIZE * 0.4, randf_range(-0.12, 0.12))
	add_child(bubble)
	var tw := create_tween()
	tw.tween_property(bubble, "position", bubble.position + Vector3(0, 0.35, 0), 1.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(bubble, "scale", Vector3.ZERO, 1.8)
	tw.chain().tween_callback(bubble.queue_free)


func _tick_detritus_flecks(dt: float, sim_v: Node) -> void:
	if _health_smooth < 0.25:
		return
	var waste_arr: Variant = sim_v.get("waste")
	if not (waste_arr is Array) or (waste_arr as Array).is_empty():
		return
	if _detritus_fleck_nodes.size() >= 3:
		return
	if randf() > dt * 0.08:
		return
	var fleck := MeshInstance3D.new()
	fleck.mesh = VoxelMat.get_box(Vector3(0.05, 0.04, 0.05))
	fleck.material_override = VoxelMat.make_foliage(Color8(75, 60, 40))
	var y_off: float = _get_stem_top() * randf_range(0.2, 0.75)
	fleck.position = Vector3(randf_range(-0.15, 0.15), y_off, randf_range(-0.15, 0.15))
	add_child(fleck)
	_detritus_fleck_nodes.append(fleck)
	var tw := create_tween()
	tw.tween_interval(randf_range(8.0, 18.0))
	tw.tween_callback(func():
		if is_instance_valid(fleck):
			fleck.queue_free()
		_detritus_fleck_nodes.erase(fleck))


func _tick_age_senescence(dt: float) -> void:
	if _leaf_ages.is_empty() or is_dying:
		return
	if _leaf_ages[0] < AGE_SENESCENCE_S:
		return
	if randf() < dt * 0.04:
		_shed_oldest_leaf()


func _tick_dormant_bulb(dt: float, substrate: SubstrateGrid) -> void:
	_dormant_timer += dt
	if _dormant_timer < 120.0:
		return
	var n: float = substrate.get_at(_world_pos)
	var daylight: float = 0.5
	var warmth: float = temp_opt
	var sim: Node = _find_sim()
	if sim != null:
		if sim.has_method("daylight"):
			daylight = float(sim.daylight())
		var world: Node = sim.get_parent()
		if world != null and world.has_method("effective_warmth_at"):
			warmth = float(world.effective_warmth_at(_world_pos))
	if not _bulb_wake_allowed(daylight, warmth, n):
		return
	life_phase = LifePhase.VEGETATIVE
	_dormant_timer = 0.0
	_bulb_buried = false
	current_height = 0
	for _i in 2:
		_grow_one()


func _bulb_wake_allowed(daylight: float, warmth: float, nutrient: float) -> bool:
	if bulb_max_dormancy_s > 0.0 and _dormant_timer >= bulb_max_dormancy_s:
		return true
	if nutrient < SubstrateGrid.NUTRIENT_BASELINE + 0.1:
		return false
	# Negative windows are the legacy rich-substrate timer path.
	if bulb_photoperiod_min < 0.0 or bulb_photoperiod_max < 0.0:
		return true
	if daylight < bulb_photoperiod_min or daylight > bulb_photoperiod_max:
		return false
	if bulb_temp_min >= 0.0 and warmth < bulb_temp_min:
		return false
	if bulb_temp_max >= 0.0 and warmth > bulb_temp_max:
		return false
	return true


func _enter_dormant_bulb() -> void:
	if dormancy_type == PlantGenome.DORMANCY_NONE:
		_begin_dying()
		return
	life_phase = LifePhase.DORMANT_BULB
	_bulb_buried = true
	_dormant_timer = 0.0
	_stop_canopy_bob()
	for v in voxels:
		if v != null and v.alive:
			v.hide()
	voxels.clear()
	if _stem_batch != null:
		_stem_batch.clear()
	current_height = 0


func _spawn_stem_fragment(units: int) -> void:
	if units < 2:
		return
	var sim: Node = _find_sim()
	if sim == null or not sim.has_method("spawn_plant_fragment"):
		return
	var g: Dictionary = PlantGenome.from_plant(self)
	var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
	var origin: Vector3 = global_position + Vector3(0, VOXEL_SIZE, 0)
	for i in range(voxels.size() - 1, -1, -1):
		var h: VoxelBatch.Handle = voxels[i]
		if h != null and h.alive:
			origin = global_transform * h.local_pos
			break
	sim.spawn_plant_fragment(
		origin + Vector3(randf_range(-0.2, 0.2), 0.0, randf_range(-0.2, 0.2)),
		g, ramp, units, Vector3(randf_range(-0.08, 0.08), 0.0, randf_range(-0.08, 0.08)))


func _tick_nyctinasty(sim_v: Node) -> void:
	var dl: float = sim_v.daylight() if sim_v != null and sim_v.has_method("daylight") else 0.5
	var fold: float = lerpf(0.0, -0.26, 1.0 - dl)
	rotation.x = _brush_bend.y + fold * 0.15


func _apply_limiting_factor_tint() -> void:
	var cfg: Node = get_node_or_null("/root/TankConfig")
	if cfg == null or not bool(cfg.get("plant_limit_overlay")):
		return
	if _foliage_mat == null:
		return
	var lim: String = String(_growth_diag.get("limiting_factor", ""))
	var tint: Color = Color.WHITE
	match lim:
		"light": tint = Color(0.82, 0.88, 1.12)
		"co2": tint = Color(1.12, 0.82, 0.82)
		"nutrient": tint = Color(1.08, 0.92, 0.78)
		_: return
	_foliage_mat.set_shader_parameter("palette_warmth", (tint.r - 1.0) * 0.35)


func _tick_dynamic_blush(sim_v: Node) -> void:
	_apply_limiting_factor_tint()
	if _foliage_mat == null:
		return
	var w: Node = sim_v.get_parent() if sim_v != null else null
	var depth: float = 0.5
	if w != null and w.get("WATER_HEIGHT") != null:
		depth = clampf((_world_pos.y - float(w.SUBSTRATE_DEPTH)) / maxf(float(w.WATER_HEIGHT) - float(w.SUBSTRATE_DEPTH), 0.5), 0.0, 1.0)
	var mature: float = 0.0
	if sim_v != null:
		mature = clampf(float(sim_v.tank_age_s) / 3600.0, 0.0, 1.0)
	var sat: float = lerpf(1.0, 0.78, depth * 0.55)
	var warmth: float = mature * 0.12 - depth * 0.1
	if absf(sat - _blush_last_sat) > 0.05:
		_foliage_mat.set_shader_parameter("palette_saturation", sat)
		_blush_last_sat = sat
	if absf(warmth - _blush_last_warmth) > 0.05:
		_foliage_mat.set_shader_parameter("palette_warmth", warmth)
		_blush_last_warmth = warmth
	if red_potential < 0.05:
		return
	var dl: float = sim_v.daylight() if sim_v != null and sim_v.has_method("daylight") else 0.5
	var blush: float = clampf(red_potential * dl * _shade_mult, 0.0, 1.0)
	if dl < 0.35:
		blush *= 0.35
	if _shade_mult < 0.8 and red_potential > 0.15:
		var green_back: float = clampf((1.0 - _shade_mult) * red_potential, 0.0, 0.4)
		var vib: float = 1.0 - green_back * 0.22
		if absf(vib - _blush_last_vibrancy) > 0.05:
			_foliage_mat.set_shader_parameter("color_vibrancy", vib)
			_blush_last_vibrancy = vib
	var sss: float = lerpf(0.35, 0.85, blush) * (1.1 - leaf_thickness * 0.4)
	if absf(sss - _blush_last_sss) > 0.05:
		_foliage_mat.set_shader_parameter("sss_strength", sss)
		_blush_last_sss = sss


func graze_palatability() -> float:
	return palatability


func is_spawn_substrate() -> bool:
	return leaf_form in ["paddle", "spade", "lobed", "oval"] and _grazing_pressure < 0.5


# Hide one leaf voxel from the most-recent non-empty leaf group; pops the group
# once fully eaten. Returns false when no leaf voxels remain.
func _take_one_leaf_voxel() -> bool:
	while not _leaf_groups.is_empty():
		var grp: Array = _leaf_groups[_leaf_groups.size() - 1]
		while not grp.is_empty():
			var h = grp.pop_back()
			if h != null and h.alive:
				h.hide()
				return true
		# Group fully consumed — drop it and its parallel age entry.
		_leaf_groups.pop_back()
		if _leaf_ages.size() > 0:
			_leaf_ages.pop_back()
		if _leaf_states.size() > 0:
			_leaf_states.pop_back()
	return false


func _has_live_leaf_voxel() -> bool:
	for group in _leaf_groups:
		for h in group:
			if h != null and h.alive:
				return true
	return false


func _recalc_height() -> void:
	# Stem handles retain their plant-local position after moving into a batch.
	var max_local_y: float = 0.0
	for h in voxels:
		if h != null and h.alive:
			max_local_y = maxf(max_local_y, h.local_pos.y)
	# Base-Plant leaf voxels live in the foliage MultiMesh (not the `voxels` node
	# array), so fold their baked plant-local heights in too — many plant forms
	# (paddle / ribbon / needle) grow only leaves and have no stem voxels at all.
	for group in _leaf_groups:
		for h in group:
			if h.alive:
				max_local_y = maxf(max_local_y, h.local_pos.y)
	current_height = maxi(0, int(max_local_y / VOXEL_SIZE))


func _on_death() -> void:
	var sim_driver: Node = _find_sim()
	if sim_driver != null and sim_driver.substrate != null:
		sim_driver.substrate.deposit_litter_at(global_position, 0.35)
		sim_driver.substrate.note_disturbance_at(global_position, 0.2)
	var world: Node = get_parent()
	if world != null and world.get("plant_lineages") is PlantLineageRegistry:
		(world.plant_lineages as PlantLineageRegistry).unregister_plant(
			get_instance_id())


func _emerge_above_water() -> void:
	_enter_canopy()


func _seed_site_viable(seed_pos: Vector3, sim_driver: Node) -> bool:
	if sim_driver == null or sim_driver.get("substrate") == null:
		return true
	var sub: SubstrateGrid = sim_driver.substrate
	var n: float = sub.get_at(Vector3(seed_pos.x, 0.0, seed_pos.z))
	var baseline: float = SubstrateGrid.NUTRIENT_BASELINE
	if sub.baseline_override >= 0.0:
		baseline = sub.baseline_override
	return n >= baseline + SEED_SITE_NUTRIENT_MIN


func _spawn_failed_seed_waste(at: Vector3, sim_driver: Node) -> void:
	if sim_driver != null and sim_driver.has_method("_spawn_waste"):
		sim_driver._spawn_waste(at, 0.04, 0)


func substrate_nutrient_ok(sub: SubstrateGrid) -> bool:
	return sub.get_at(_world_pos) >= SubstrateGrid.NUTRIENT_BASELINE + SEED_SITE_NUTRIENT_MIN


func _germinate_seed_at(pos: Vector3, sim_d: Node, seed_genome: Dictionary = {}) -> void:
	var world: Node = sim_d.get_parent()
	if world == null or not world.has_method("spawn_seedling"):
		return
	var mutated_ramp: Array = ramp_override.duplicate()
	if mutated_ramp.size() == 6:
		EvolutionPressure.apply_plant_ramp(
			mutated_ramp, EvolutionPressure.sample_from_sim(sim_d, pos))
	var cfg: Dictionary = seed_genome.duplicate(true) \
		if not seed_genome.is_empty() else get_seed_config()
	cfg["from_seed_bank"] = true
	world.spawn_seedling(pos, mutated_ramp, int(cfg.get("generation", generation + 1)), cfg)


func _cast_seed() -> bool:
	var sim_driver: Node = _find_sim()
	if sim_driver == null:
		return false
	var world: Node = sim_driver.get_parent()
	if world == null:
		return false
	if sim_driver.substrate != null and world.has_method("begin_seed_drift"):
		var seed_genome: Dictionary = get_seed_config()
		var start: Vector3 = global_position + Vector3(0, _get_stem_top() * 0.5, 0)
		return bool(world.begin_seed_drift(start, seed_genome, {
			"type": String(seed_genome.get("dormancy_type", dormancy_type)),
		}))
	return false


func _spawn_visible_seed_drift(seed_pos: Vector3) -> void:
	var w: Node = _find_sim()
	if w == null:
		return
	var world: Node = w.get_parent()
	if world == null:
		return
	var start: Vector3 = global_position + Vector3(0, _get_stem_top() * 0.5, 0)
	var drift_vis := MeshInstance3D.new()
	drift_vis.mesh = VoxelMat.get_box(Vector3(0.05, 0.05, 0.05))
	drift_vis.material_override = VoxelMat.make_foliage(Color8(120, 90, 45))
	world.add_child(drift_vis)
	drift_vis.global_position = start
	var land: Vector3 = Vector3(seed_pos.x, float(world.get("SUBSTRATE_DEPTH")) + 0.08, seed_pos.z)
	var tw := world.create_tween()
	tw.tween_property(drift_vis, "global_position", land, randf_range(2.5, 4.5)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(drift_vis.queue_free)


func _flower() -> void:
	# Legacy single-voxel flower for backward compatibility.
	_begin_flowering()
func get_seed_config() -> Dictionary:
	_ensure_plant_named()
	var my_key: String = ""
	var lib := get_node_or_null("/root/SpeciesLibrary")
	if lib != null and lib.has_method("make_species_key"):
		my_key = String(lib.make_species_key(get_plant_genome()))
	var base_g: Dictionary = PlantGenome.from_plant(self)
	# Acclimation changes the live plant's palatability, but selection starts
	# from the inherited value and is applied only to produced offspring.
	base_g["palatability"] = _heritable_palatability
	base_g["parent_lineage"] = plant_name
	base_g["parent_keys"] = [my_key] if my_key != "" else []
	base_g["plant_name"] = ""
	base_g["script"] = get_script()
	var cfg: Dictionary = {}
	var partner: Plant = _find_pollination_partner()
	if partner != null:
		var partner_g: Dictionary = PlantGenome.from_plant(partner)
		partner_g["palatability"] = partner._heritable_palatability
		cfg = PlantGenome.outcross(base_g, partner_g,
			maxi(generation, partner.generation) + 1)
		cfg["script"] = get_script()
		_pollination_cooldown_s = POLLINATION_COOLDOWN_S
		partner._pollination_cooldown_s = POLLINATION_COOLDOWN_S
	else:
		cfg = PlantGenome.duplicate_mutate(base_g, generation + 1)
	var selection_pressure: float = _lifetime_grazing_pressure
	if partner != null:
		selection_pressure = (_lifetime_grazing_pressure
			+ partner._lifetime_grazing_pressure) * 0.5
	cfg = PlantGenome.apply_grazing_selection(cfg, selection_pressure)
	var sim_n: Node = _find_sim()
	if sim_n != null:
		EvolutionPressure.apply_plant_seed_config(
			cfg, EvolutionPressure.sample_from_sim(sim_n, global_position))
	return cfg


func _find_pollination_partner() -> Plant:
	if _pollination_cooldown_s > 0.0:
		return null
	var sim_n: Node = _find_sim()
	if sim_n == null or not sim_n.has_method("query_plants_in_radius"):
		return null
	var checked: int = 0
	var best: Plant = null
	var best_d2: float = POLLINATION_RADIUS * POLLINATION_RADIUS
	for candidate_v in sim_n.query_plants_in_radius(global_position, POLLINATION_RADIUS):
		if checked >= MAX_POLLINATION_CANDIDATES:
			break
		checked += 1
		if not (candidate_v is Plant):
			continue
		var candidate: Plant = candidate_v
		if candidate == self or not is_instance_valid(candidate):
			continue
		if candidate.flower_stage != FlowerStage.MATURE \
				or not candidate._pollen_ready \
				or candidate._pollination_cooldown_s > 0.0:
			continue
		if not _flowers_compatible(candidate):
			continue
		var d2: float = global_position.distance_squared_to(candidate.global_position)
		if d2 <= best_d2:
			best_d2 = d2
			best = candidate
	return best


func _flowers_compatible(other: Plant) -> bool:
	if other == null or other.repro_mode != PlantGenome.REPRO_SEED:
		return false
	if species_id != "" and other.species_id != "":
		return species_id == other.species_id
	return leaf_form == other.leaf_form



# ---- Phyllotaxis ------------------------------------------------------------
#
# Every leaf used to be placed by `side = ±1` off `current_height % 2`, which
# put the whole plant into two opposing planes: from any angle it read as a
# flat stack of the same leaf, and two specimens of a species were identical.
# Real plants set each successive leaf at a species-typical divergence angle
# around the stem:
#
#   spiral / alternate  ~137.5°  the golden angle — most stem plants, swords
#   distichous           180°    two-ranked (Vallisneria, some cryptocorynes)
#   decussate             90°    opposite pairs rotating 90° per node (Rotala)
#   whorled            360/n     n leaves at one node (Limnophila, Egeria)
#
# The divergence is what produces the packed, non-repeating rosette look, and
# because each plant also carries a per-individual phase offset, a clump of
# one species no longer lines up leaf-for-leaf.
const GOLDEN_ANGLE: float = 2.39996323  # 137.507° in radians

# Light heading in radians, refreshed by _phototropic_offset(). NAN until the
# first growth step resolves TankConfig (headless tests never do).
var _light_yaw_cache: float = NAN

# How far a leaf may twist off its divergence angle to face the lamp. Real
# plants do this at the petiole — it is what produces a "leaf mosaic", the
# non-overlapping tiling you see looking down on a shade plant. Kept well
# under half so the underlying arrangement still reads.
const LEAF_MOSAIC_BIAS: float = 0.3

const PHYLLO_SPIRAL: String = "spiral"
const PHYLLO_DISTICHOUS: String = "distichous"
const PHYLLO_DECUSSATE: String = "decussate"
const PHYLLO_WHORLED: String = "whorled"


# Stable 0..TAU phase so two plants of one species do not present the same
# leaf face. Derived from asymmetry_seed, so it survives save/load and is
# inherited-with-drift exactly like the rest of the genome.
func _phyllotaxis_phase() -> float:
	return float(asymmetry_seed % 3600) / 3600.0 * TAU


# Yaw for the leaf at node index `node`, in radians.
func _phyllotaxis_yaw(node: int) -> float:
	var phase: float = _phyllotaxis_phase()
	match phyllotaxis:
		PHYLLO_DISTICHOUS:
			return phase + float(node % 2) * PI
		PHYLLO_DECUSSATE:
			# Opposite pairs, each pair rotated a quarter turn from the last.
			@warning_ignore("integer_division")
			var pair: int = node / 2
			return phase + float(pair) * (PI * 0.5) + float(node % 2) * PI
		PHYLLO_WHORLED:
			var n: int = maxi(2, whorl_count)
			@warning_ignore("integer_division")
			var ring: int = node / n
			# Successive whorls half-step so leaves are not stacked in columns.
			return phase + float(node % n) * (TAU / float(n)) \
				+ float(ring) * (TAU / float(n)) * 0.5
		_:
			return phase + float(node) * GOLDEN_ANGLE


# Final leaf heading: the species' divergence angle, twisted part-way toward
# the light. Under a strongly side-lit tank the whole plant visibly turns to
# face the lamp without collapsing into a single plane.
func _leaf_yaw(node: int, jitter_spread: float = 0.09) -> float:
	var yaw: float = _phyllotaxis_yaw(node) + _node_jitter(node, jitter_spread)
	if is_nan(_light_yaw_cache):
		return yaw
	# Shaded plants reach harder for what light there is.
	var bias: float = LEAF_MOSAIC_BIAS * (0.6 + 0.4 * _shade_leaf_factor())
	var delta: float = wrapf(_light_yaw_cache - yaw, -PI, PI)
	return yaw + delta * bias


# Small deterministic per-node wobble. Perfect divergence angles read as
# machined; a couple of degrees of scatter is what makes it read as grown.
func _node_jitter(node: int, spread: float) -> float:
	var h: int = (asymmetry_seed ^ (node * 2654435761)) & 0x7FFFFFFF
	return (float(h % 2000) / 1000.0 - 1.0) * spread


# The direction this individual leans. The old fixed `sin(rel)` arc bent every
# plant along +X, so a row of stems all bowed the same way.
func _lean_dir() -> Vector2:
	var a: float = _phyllotaxis_phase()
	return Vector2(cos(a), sin(a))


# Lateral offset of the node at `rel` (0 = base, 1 = tip) along the lean.
func _stem_lean_offset(rel: float) -> Vector2:
	return _lean_dir() * (sin(rel * PI * 0.6) * sway_amplitude * 0.6)


# ---- Light-driven leaf plasticity --------------------------------------------
#
# A shade leaf and a sun leaf of the same species are different organs: the
# shade leaf is larger, thinner and held closer to horizontal to catch what
# little light there is, the sun leaf is smaller and steeper. Because leaves
# are baked at growth time, a plant that spent its life under a taller
# neighbour keeps that record in its geometry — you can read a plant's light
# history off its silhouette.
func _shade_leaf_factor() -> float:
	# 0 = full light, 1 = deep shade.
	var lit: float = clampf(_light_avg / 0.48, 0.0, 1.0)
	if _shade_mult < 1.0:
		lit *= 0.6
	return clampf(1.0 - lit, 0.0, 1.0)


# Size multiplier: shade leaves run up to ~28% larger.
func _shade_size_mult() -> float:
	return 1.0 + _shade_leaf_factor() * 0.28


# Pitch in radians: shade leaves lie flatter to present more area upward.
func _shade_pitch() -> float:
	return -_shade_leaf_factor() * 0.42


# Leaf area along the stem. Real stems carry their largest leaves in the
# mid-canopy: the apex is still expanding and the base is shaded out by
# everything above it. A flat size for every node is one of the strongest
# "procedural" tells.
func _node_size_gradient(rel: float) -> float:
	# Peaks ~0.62 up the stem, tapering to 0.78x at the base and 0.72x at the tip.
	var t: float = clampf(rel, 0.0, 1.0)
	return lerpf(0.78, 1.0, smoothstep(0.0, 0.62, t)) \
		- smoothstep(0.62, 1.0, t) * 0.28


func _phototropic_offset() -> Vector2:
	# Kept as a thin alias so older call sites / smokes still compile; new
	# growth goes through _tropism_lateral_offset() (Naturalism #1).
	return _tropism_lateral_offset()


# Naturalism #1 — desire direction: lamp heading + up + local flow.
func _refresh_tropism() -> void:
	var up_w: float = 0.72
	var light_w: float = 0.42
	var flow_w: float = 0.22
	var light_dir: Vector3 = Vector3.ZERO
	var cfg := _find_sim()
	var tc: Node = null
	if cfg != null and cfg.has_node("/root/TankConfig"):
		tc = cfg.get_node("/root/TankConfig")
	if tc != null:
		var yaw_rad: float = float(tc.light_yaw) * TAU
		_light_yaw_cache = yaw_rad
		# Lamp is above; lateral component points toward the light azimuth.
		light_dir = Vector3(sin(yaw_rad), 0.35, cos(yaw_rad)).normalized()
	var flow_dir: Vector3 = Vector3.ZERO
	var w: Node = get_parent()
	if w != null and w.has_method("sample_flow"):
		flow_dir = w.sample_flow(_world_pos if _world_pos != Vector3.ZERO else global_position)
		if flow_dir.length_squared() > 1e-8:
			flow_dir = flow_dir.normalized()
	# Shade-stressed plants lean harder into light; healthy plants stay upright.
	var shade: float = _shade_leaf_factor()
	light_w = lerpf(0.28, 0.55, shade)
	up_w = lerpf(0.82, 0.55, shade)
	var desire: Vector3 = Vector3.UP * up_w + light_dir * light_w + flow_dir * flow_w
	if desire.length_squared() < 1e-8:
		desire = Vector3.UP
	_tropism = desire.normalized()


func _tropism_lateral_offset() -> Vector2:
	if _tropism.length_squared() < 1e-8:
		_refresh_tropism()
	# Strength grows with height — tips reach harder than the base.
	var height_factor: float = float(current_height) / float(maxi(1, max_height))
	var bias: float = 0.045 * height_factor * (0.7 + 0.5 * _shade_leaf_factor())
	return Vector2(_tropism.x, _tropism.z) * bias


func _get_stem_top() -> float:
	var factor := 1.0
	if leaf_form == "paddle":
		factor = 0.9
	elif leaf_form == "lance":
		factor = 0.85
	return current_height * VOXEL_SIZE * factor + _internode_extension_y


# Quick world-space height of the top voxel (for fish to target nibbling).
func top_world_y() -> float:
	return global_position.y + _get_stem_top()


# ---- Utility ----

func _rng_range(lo: int, hi: int) -> int:
	return lo + randi() % maxi(1, hi - lo + 1)
