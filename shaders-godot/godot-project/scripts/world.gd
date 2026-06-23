# walstad loom 3D voxel world.
#
# Builds the static environment (substrate, hardscape, water volume, glass)
# and the initial population (plants, fish, snails). Then hands off to a
# SimDriver child for ongoing generative behavior.
#
# Subsystems extracted to WorldWaterVisuals + WorldFloaterManager helpers.

extends Node3D

const RealSpeciesLibrary = preload("res://scripts/real_species_library.gd")
const MicrofaunaSwarm = preload("res://scripts/microfauna_swarm.gd")

# How much tannin has leached into the water (0..1). Driftwood releases it
# slowly; visible as a brown tint in the water material.
var tannins: float = 0.0
var _water_mesh: MeshInstance3D = null
var _water_material_ref: ShaderMaterial = null
var _visuals: AquariumVisuals = null
var _glass_material_ref: ShaderMaterial = null
var _caustics_mat: ShaderMaterial = null
var _mulm_voxels: Array = []
var _film_voxels: Array = []
var _film_root: Node3D = null
var _film_maintain_t: float = 0.0
var _understory_t: float = 48.0
var algae_root: Node3D = null
var clams_root: Node3D = null
# Driftwood voxels captured in _build_hardscape so the biofilm tick can
# tint a growing fraction over time. Real driftwood develops a fuzzy
# white biofilm in the first 1-2 weeks of a new tank, then settles back
# as bacteria balance out and shrimp / otos graze it.
var _driftwood_voxels: Array[MeshInstance3D] = []
# Substrate ripple-sculpting state. Phase walks forward in sim-time so the
# sand bed's ripple pattern evolves over sim-minutes. Strength + direction
# are static per session; aeration angle drives the direction so flow
# direction is visible in the substrate texture.
var _substrate_ripple_phase: float = 0.0
var _substrate_ripple_strength: float = 0.18
var _substrate_ripple_dir: Vector2 = Vector2(1.0, 0.35)
# Rock voxels — captured so epiphytes (java fern, anubias) can attach to
# rock surfaces, not just driftwood. We pick from upper-surface voxels at
# spawn time so the plant sits visibly on top of a stone.
var _rock_voxels: Array[MeshInstance3D] = []
var _hardscape_occupancy: Dictionary = {}
const HARDSCAPE_CELL_SIZE: float = 0.55
const VOXEL_SIZE: float = 0.32
# Glass mineral spots — tiny pale voxels that accumulate at the waterline
# over time, mimicking the calcium / hard-water spots that real tanks
# develop after a few weeks. Caps at MINERAL_SPOT_CAP so the glass
# doesn't get fully encrusted.
var _mineral_spots: Array[MeshInstance3D] = []
var _mineral_progress_t: float = 0.0
const MINERAL_SPOT_CAP: int = 35
var _heater_world_pos: Vector3 = Vector3.ZERO
var _heater_glow: OmniLight3D = null
# Biofilm progress 0..1. Climbs slowly over the first few real-time
# minutes, peaks around 0.65, then decays back toward a balanced level
# as the "biofilm gets grazed" — the visible bloom-and-settle that all
# new tanks show. Saved/loaded via TankConfig if we ever want to
# persist it across sessions; for now it's per-session.
var biofilm_progress: float = 0.0
var _biofilm_apply_t: float = 0.0
# Microfauna swarm + detrital worm carpet. Both are pure-visual entity
# populations maintained by _process below — they're not part of the
# brain tick loop because nothing makes decisions about them, they just
# drift and squirm. Adds tank-feel at small scale (real Walstad tanks
# always have a teeming film of copepods + worms).
var microfauna_root: MicrofaunaSwarm = null
var tubifex_root: Node3D = null
var _tubifex_check_t: float = 0.0
var mycelium_root: Node3D = null
var _mycelium_check_t: float = 0.0
var biofilm_root: Node3D = null
var _biofilm_check_t: float = 0.0
var motion_debug: MotionDebugOverlay = null
var wriggle_root: Node3D = null
# Worms spawn proportional to mulm carpet density — no fixed ceiling.
const WRIGGLE_PER_MULM_FRAC: float = 0.55
# Maintenance cadence — refilling every frame is fine cost-wise but the
# RNG variance reads better when we batch into 0.8 s slices.
var _wriggle_refill_t: float = 0.0
var _tiny_life_scalar_cache: Dictionary = {"micro": 1.0, "wriggle": 1.0}
var _tiny_life_scalar_ttl: float = 0.0
var _life_bounds_timer: float = 0.0
const LIFE_BOUNDS_INTERVAL: float = 0.22

# Coarse environment field — light penetration + warmth sampled on a 1 m grid
# and refreshed ~4 Hz so hundreds of plant ticks don't each query floaters.
const ENV_FIELD_CELL: float = 1.0
const ENV_FIELD_REBUILD_S: float = 0.25
var _env_field_t: float = 0.0
var _env_light: Dictionary = {}
var _env_warmth: Dictionary = {}
var _env_field_ready: bool = false

# Shared pearling emitter pool (replaces per-plant GPUParticles3D nodes).
var _pearling_pool: Array[GPUParticles3D] = []
var _pearling_pool_root: Node3D = null
const PEARLING_POOL_SIZE: int = 22

# Tank dimensions read from TankConfig at _ready so the user can resize.
# Treated as plain vars (was const) so settings can change them.
var TANK_HALF_W: float = 8.0
var TANK_HALF_D: float = 4.0
var TANK_HEIGHT: float = 7.0
var WATER_HEIGHT: float = 6.5
var SUBSTRATE_DEPTH: float = 1.6
# Substrate color ramp (overridden by TankConfig substrate profile).
var ACTIVE_SOIL_RAMP: Array = []
# Active substrate profile resolved at _ready (honors preset.substrate
# overrides like the reef preset's ocean_sand). Used to decide between
# plant vs coral spawn paths via the is_saltwater flag.
var _active_substrate_profile: Dictionary = {}
# Coral recruitment timer (saltwater only). Ticks down in _process; when
# zero, spawns a tiny new coral somewhere on the substrate via larval-
# drift analogy. Reset to a random value in CORAL_RECRUIT_MIN..MAX.
var _coral_recruit_timer: float = 30.0   # first recruit after ~30s
const CORAL_RECRUIT_MIN: float = 22.0
const CORAL_RECRUIT_MAX: float = 42.0
# Tank shape: "box" / "cube" / "hex" / "triangle" / "cylinder" / "sphere". Read from TankConfig.
var TANK_SHAPE: String = "box"
var _footprint_cache: TankFootprint = null

# ---- Palette (chosen so the quantize shader has good targets) ----
const C_WATER_DEEP    := Color(0.04, 0.10, 0.14)
const C_WATER_SHALLOW := Color(0.42, 0.62, 0.66)
const C_GLASS         := Color(0.93, 0.97, 0.98)
const C_SOIL_RAMP := [
	Color8(26, 18, 12),
	Color8(44, 31, 21),
	Color8(67, 47, 31),
	Color8(93, 65, 40),
	Color8(120, 85, 56),
	Color8(149, 113, 78),
]
const C_GRAVEL := Color8(85, 85, 96)
const C_DRIFTWOOD_DARK := Color8(44, 31, 21)
const C_DRIFTWOOD_LIGHT := Color8(93, 65, 40)
const C_SNAIL_SHELL := Color8(165, 55, 210)
const C_SNAIL_BODY := Color8(55, 38, 28)
const C_STONE_DARK := Color8(42, 42, 48)
const C_STONE_LIGHT := Color8(85, 85, 96)

var _rng := RandomNumberGenerator.new()
var sim: SimDriver = null
var substrate_grid: SubstrateGrid = null
var terrain_grid: TerrainVoxelGrid = null
var _substrate_container: Node3D = null
var fauna_root: Node3D = null
var plants_root: Node3D = null
var waste_root: Node3D = null


func _ready() -> void:
	# Pull tank dimensions + substrate profile from the autoload config.
	# Settings panel writes here and reloads the scene to apply.
	var cfg := get_node_or_null("/root/TankConfig")
	_cfg_node = cfg
	# Active substrate profile - normally driven by cfg.substrate_type, but
	# certain presets (e.g. "reef") declare a substrate override that wins
	# without writing back to the saved config. We resolve once here and
	# reuse below + later in _ready.
	_active_substrate_profile = {}
	if cfg != null:
		TANK_HALF_W = float(cfg.tank_half_w)
		TANK_HALF_D = float(cfg.tank_half_d)
		TANK_HEIGHT = float(cfg.tank_height)
		# Cube shape: enforce equal W=D (use the smaller of the two so it fits).
		TANK_SHAPE = String(cfg.tank_shape)
		_footprint_cache = null
		if TANK_SHAPE == "cube":
			var m: float = minf(TANK_HALF_W, TANK_HALF_D)
			TANK_HALF_W = m
			TANK_HALF_D = m
		elif TANK_SHAPE == "cylinder" or TANK_SHAPE == "sphere":
			var rad: float = minf(TANK_HALF_W, TANK_HALF_D)
			TANK_HALF_W = rad
			TANK_HALF_D = rad
		WATER_HEIGHT = TANK_HEIGHT * float(cfg.water_surface_fraction)
		SUBSTRATE_DEPTH = TANK_HEIGHT * float(cfg.substrate_depth_fraction)
		_active_substrate_profile = cfg.current_substrate_profile()
		# Preset-driven substrate override (reef preset → ocean_sand).
		var preset_for_substrate: Dictionary = cfg.current_tank_preset()
		var preset_substrate: String = String(preset_for_substrate.get("substrate", ""))
		if preset_substrate != "":
			var override_profile: Dictionary = TankConfig.SUBSTRATE_PROFILES.get(
				preset_substrate, {})
			if not override_profile.is_empty():
				_active_substrate_profile = override_profile
		ACTIVE_SOIL_RAMP = _active_substrate_profile.get("colors", C_SOIL_RAMP)
	else:
		ACTIVE_SOIL_RAMP = C_SOIL_RAMP

	# Seed comes from env var WALSTAD_LOOM_SEED if set, otherwise default. Lets
	# users replay a specific tank by exporting the env var before launch.
	var seed_env: String = OS.get_environment("WALSTAD_LOOM_SEED")
	var seed_value: int = 0xCAFEF155
	if seed_env != "":
		seed_value = seed_env.hash() if not seed_env.is_valid_int() else int(seed_env)
	_rng.seed = seed_value
	# Sim driver first so other builders can register into it.
	sim = SimDriver.new()
	sim.name = "SimDriver"
	sim.tank_seed = seed_value
	add_child(sim)
	# Pipe AIDirector chronicle lines into the sim's story_events log so
	# they surface in the existing story dialog. Cheap connection; fires
	# at most every 18 seconds when AI chronicle is on, never otherwise.
	var ai_d: Node = get_node_or_null("/root/AIDirector")
	if ai_d != null and ai_d.has_signal("chronicle_line"):
		ai_d.chronicle_line.connect(func(text: String, _tags: PackedStringArray):
			if sim != null and sim.has_method("log_story_event"):
				sim.log_story_event(text))
	substrate_grid = SubstrateGrid.new()
	substrate_grid.name = "SubstrateGrid"
	add_child(substrate_grid)
	var fp_grid := TankFootprint.from_values(TANK_SHAPE, TANK_HALF_W, TANK_HALF_D)
	fp_grid.substrate_y = SUBSTRATE_DEPTH
	fp_grid.water_y = WATER_HEIGHT
	fp_grid.tank_height = TANK_HEIGHT
	var grid_ext: Vector2 = fp_grid.bounding_half_extents(0.5)
	substrate_grid.init(grid_ext.x, grid_ext.y, 1.0)
	# Apply substrate fertility from the resolved active profile (honors
	# any preset.substrate override - see top of _ready).
	if not _active_substrate_profile.is_empty():
		substrate_grid.baseline_override = float(
			_active_substrate_profile.get("nutrient_baseline", 0.30))
		substrate_grid.reservoir_leak_override = float(
			_active_substrate_profile.get("reservoir_leak", 0.00015))
	sim.substrate = substrate_grid
	sim.substrate_top_y = SUBSTRATE_DEPTH
	sim.world_bounds = AABB(
		Vector3(-grid_ext.x + 0.3, SUBSTRATE_DEPTH + 0.2, -grid_ext.y + 0.3),
		Vector3((grid_ext.x - 0.3) * 2.0, WATER_HEIGHT - SUBSTRATE_DEPTH - 0.4,
				(grid_ext.y - 0.3) * 2.0)
	)
	sim.world = self

	plants_root = Node3D.new(); plants_root.name = "Plants"; add_child(plants_root)
	fauna_root = Node3D.new(); fauna_root.name = "Fauna"; add_child(fauna_root)
	waste_root = Node3D.new(); waste_root.name = "Waste"; add_child(waste_root)
	algae_root = Node3D.new(); algae_root.name = "Algae"; add_child(algae_root)
	clams_root = Node3D.new(); clams_root.name = "Clams"; add_child(clams_root)
	microfauna_root = MicrofaunaSwarm.new(); microfauna_root.name = "Microfauna"; add_child(microfauna_root)
	microfauna_root.sim = sim
	tubifex_root = Node3D.new(); tubifex_root.name = "Tubifex"; add_child(tubifex_root)
	mycelium_root = Node3D.new(); mycelium_root.name = "Mycelium"; add_child(mycelium_root)
	biofilm_root = Node3D.new(); biofilm_root.name = "BiofilmPatches"; add_child(biofilm_root)
	wriggle_root = Node3D.new(); wriggle_root.name = "WriggleWorms"; add_child(wriggle_root)
	motion_debug = MotionDebugOverlay.new()
	motion_debug.name = "MotionDebug"
	motion_debug.sim = sim
	add_child(motion_debug)
	sim.plants_root = plants_root
	sim.fauna_root = fauna_root
	sim.waste_root = waste_root
	sim.algae_root = algae_root
	sim.clams_root = clams_root

	# Stagger the build across frames so the GPU command buffer can drain
	# between resource batches. Doing everything synchronously hammered Metal
	# on macOS and tripped fence timeouts during the first render frame.
	# Spawn functions themselves also yield internally (see each function).
	# Initialize caustics material early so _build_substrate() can apply it
	# as next_pass on top-row MultiMesh materials during the build phase.
	if _caustics_mat == null:
		_caustics_mat = ShaderMaterial.new()
		_caustics_mat.shader = load("res://shaders/caustics.gdshader")
	_build_substrate()
	# Empty / guided tanks (walkthrough): start the tank completely bare so
	# the player stocks plants, fauna, snails, and hardscape themselves.
	var cfg_empty := get_node_or_null("/root/TankConfig")
	var start_empty: bool = cfg_empty != null and String(cfg_empty.tank_preset) == "empty"
	_build_hardscape(not start_empty)
	_build_water_volume()
	_build_glass()
	sim.snails_root = _build_snails(not start_empty)
	_build_light_fixture()
	_setup_caustics()
	await get_tree().process_frame

	# When the active tank has a saved state.json AND that save is compatible
	# with the current tank settings (specifically substrate type — saltwater
	# saves can't restore into a freshwater tank because corals and freshwater
	# plants aren't interchangeable), skip the procedural stocking entirely.
	# SimDriver.load_state() will restock from disk right after _ready
	# completes. If the save is INCOMPATIBLE (substrate type changed between
	# sessions), we silently delete it and run the initial spawn instead —
	# the user's substrate choice wins.
	# Reset the SpeciesLibrary's per-tank discovery list. The autoload is a
	# singleton that survives scene reloads, so if the player returns from
	# menu into a different tank, last-tank's discoveries would otherwise
	# leak. The loading branch overwrites this with the saved set; the
	# fresh-spawn branch starts from zero and accumulates as founders enter.
	var lib_for_reset := get_node_or_null("/root/SpeciesLibrary")
	if lib_for_reset != null:
		lib_for_reset.clear_tank()

	var saves := get_node_or_null("/root/TankSaves")
	var loading_from_save: bool = false
	if saves != null:
		if saves.has_state_for_active_slot() and not saves.is_active_save_compatible():
			var cfg_for_log := get_node_or_null("/root/TankConfig")
			var cur_sub: String = String(cfg_for_log.substrate_type) if cfg_for_log != null else "?"
			print_verbose("[walstad_loom] save substrate mismatch (saved=%s, current=%s); discarding state.json" % [
				saves.peek_saved_substrate_type(), cur_sub,
			])
			saves.clear_active_state()
		loading_from_save = saves.has_state_for_active_slot()

	# Saltwater branch: ocean_sand substrate replaces freshwater plants
	# with a reef of corals. Floaters / lily pads / math plants don't
	# exist in saltwater either (they're freshwater forms) so we skip
	# them entirely. Shrimp are also skipped further down via the same
	# is_saltwater check.
	if start_empty:
		# Guided/empty tank: spawn nothing. The player builds it up via the
		# walkthrough using the creature creator + aquascape tools.
		pass
	elif not loading_from_save:
		if _active_substrate_profile.get("is_saltwater", false):
			await _spawn_initial_corals()
			await get_tree().process_frame
		else:
			await _spawn_initial_plants()
			await get_tree().process_frame

			_spawn_floaters()
			_spawn_lily_pads()
			_spawn_math_plants()
			await get_tree().process_frame

		await _spawn_initial_fish()
		if _stocking_shrimp_count() > 0:
			if _active_substrate_profile.get("is_saltwater", false):
				await _spawn_marine_shrimp()
			else:
				await _spawn_initial_shrimp()
		_build_clams()
		_build_trumpet_snails()
		_build_bristle_worms()
		_build_sea_cucumbers()
		await get_tree().process_frame
	else:
		# Lily pads + math plants restored via SimDriver.load_state → restore_ambient.
		pass

	_spawn_aeration_system()
	_spawn_mulm_layer()
	_spawn_water_ambience()
	_visuals = AquariumVisuals.new()
	_visuals.name = "AquariumVisuals"
	add_child(_visuals)
	_visuals.setup(self, sim)
	var glass_node := get_node_or_null("Glass")
	if glass_node != null and _glass_material_ref != null:
		_visuals.register_glass(glass_node, _glass_material_ref)
	# Tank heater — a small red rod tucked behind the substrate with a
	# faint warm glow. Cheap visual cue that the tank is "running."
	_build_heater()
	# Room environment: desk + wall + lamp + books that the tank "sits on."
	# Lifts the scene from "voxels in void" to "aquarium in a room." Defaults
	# to "void" (no room) so existing tanks open unchanged.
	_build_room_environment()
	# Seed the microfauna swarm to roughly the steady-state target so the
	# tank reads as "alive at small scale" from the first second instead of
	# fading in over the first 30s. _process maintains the count from here.
	if not start_empty:
		_spawn_initial_microfauna(microfauna_carrying_capacity())
	# Rebind in case anything recreated the container during stocking.
	if sim.snails_root == null or not is_instance_valid(sim.snails_root):
		sim.snails_root = _find_snails_container()
	# Snails spawn before clear_tank(); fish/shrimp register on spawn. Sync
	# once so founders of every type appear in the Life Library.
	if sim.has_method("sync_species_discoveries"):
		sim.sync_species_discoveries()
	# Hardscape container - fry hide-at-log behavior reads this.
	sim.hardscape_root = get_node_or_null("Hardscape")
	# Seed the substrate with some uneven nutrients so plants in nutrient-rich
	# spots immediately start to outpace the others - visible variance.
	_seed_nutrient_hotspots()
	# Instant-mature cold start: make a freshly-stocked tank read as established
	# (patina + lineage depth + mixed ages) instead of brand-new. Fresh spawn only.
	if not start_empty and not loading_from_save and TankConfig.start_matured:
		_apply_mature_cold_start()
	if not start_empty and not loading_from_save and sim != null \
			and sim.has_method("apply_cycle_start_from_config"):
		sim.apply_cycle_start_from_config()

	# Find the directional light so we can dim it on the day/night cycle.
	# The light is a sibling under SubViewport/World, accessible by name.
	_directional_light = get_parent().get_node_or_null("DirectionalLight3D")
	_world_environment = get_parent().get_node_or_null("WorldEnvironment")

	# Toggle volumetric beams based on TankConfig.light_volumetric.
	var we := get_parent().get_node_or_null("WorldEnvironment")
	if we != null and we.environment != null and cfg != null:
		# Disable heavy built-in volumetric fog to avoid macOS fence timeouts / performance degradation.
		# The light beams are now drawn via super-performant shader meshes.
		we.environment.volumetric_fog_enabled = false

	print_verbose("[walstad_loom] world built: ", get_child_count(), " top-level nodes; ",
		  sim.fish.size(), " fish, ", sim.shrimp.size(), " shrimp, ",
		  sim.plants.size(), " plants")



var _directional_light: DirectionalLight3D = null
var _world_environment: WorldEnvironment = null
# Optional accent / moonlight nodes — created on first _update_accent_lights
# call so they only exist when the user enables them. Each is an OmniLight3D
# positioned mid-water; moonlight is a faint cool DirectionalLight3D that
# only contributes at deep night.
var _moonlight: DirectionalLight3D = null
var _accent1_light: OmniLight3D = null
var _accent2_light: OmniLight3D = null
const _ENV_AMBIENT_DAY: float = 0.5
const _ENV_AMBIENT_NIGHT: float = 0.035

# Lofi room environment dynamic variables
var _room_sky_mat: ShaderMaterial = null
var _room_window_state: Dictionary = {}
var _room_stars: Array[MeshInstance3D] = []
var _room_tank_spill: OmniLight3D = null
var _room_wall_bounce: OmniLight3D = null
var _room_side_light: OmniLight3D = null
var _room_desk_rim: SpotLight3D = null
var _room_window_glow: OmniLight3D = null
var _room_haze_base: Color = Color(0.92, 0.84, 0.74)
var _room_clock_hour_pivot: Node3D = null
var _room_clock_min_pivot: Node3D = null
var _room_record_disc: MeshInstance3D = null
var _room_record_speed: float = 0.0
var _room_lava_lamp_blobs: Array[MeshInstance3D] = []
var _room_lava_lamp_light: OmniLight3D = null
var _room_time_passed: float = 0.0

# Day/night light + caustics + god-ray shader-parameter writes are
# throttled to 10 Hz. The daylight cycle takes 360 s, so the values being
# pushed to shaders change by <1% per tenth of a second — writing them
# every render frame is pure waste and shows up under profiling as one
# of the larger per-frame costs in a populated tank.
const LIGHT_CYCLE_INTERVAL: float = 0.1
var _light_cycle_accum: float = 0.0
var _last_caustic_intensity: float = -1.0
var _last_caustic_color: Color = Color(-1.0, -1.0, -1.0, -1.0)
var _cached_lighting: Dictionary = {}
var _cached_water_column: Dictionary = {}

# Cosmetic ambient animation (stars, clock hands, vinyl disc, lava lamp, water
# tint, floater drift, math-plant / lily-pad sway) is throttled to 10 Hz. It's
# purely visual and slow enough that 10 Hz is indistinguishable from per-frame,
# but at 60+ fps the sin/cos/sqrt loops + Vector3 allocations were a measurable
# per-frame cost in a populated tank. The accumulated dt (`adt`) is passed in so
# phase-based motion advances at exactly the same rate as before.
const AMBIENT_VISUAL_INTERVAL: float = 0.1
var _ambient_accum: float = 0.0
# Reused across frames so the floater-drift cleanup never allocates a fresh Array.
var _dead_floaters_scratch: Array = []
# Cached TankConfig autoload — never moves, so the per-frame /root/TankConfig
# path lookups in _process are wasteful. Resolved once in _ready.
var _cfg_node: Node = null


func _refresh_atmosphere_caches(adt: float) -> void:
	if sim == null:
		return
	_cached_lighting = WorldAtmosphere.day_night_lighting(sim, _cfg_node)
	var bloom: float = float(sim.bloom_intensity)
	var wc = sim.water_chemistry if sim.get("water_chemistry") != null else null
	var atm: Dictionary = _cached_lighting.get("atmosphere", {})
	_cached_water_column = WorldAtmosphere.water_column_bundle(
		tannins, bloom, floater_coverage(), wc,
		C_WATER_SHALLOW, C_WATER_DEEP, float(atm.get("tannin_affinity", 0.0)))
	if tannins < 0.55:
		tannins = minf(0.55, tannins + 0.00007 * adt)


func _process(dt: float) -> void:
	var sdt: float = dt
	if sim != null:
		sdt = dt * float(sim.time_scale)

	# Update lofi room environment animations
	_room_time_passed += sdt

	# Substrate ripple sculpting — walk the ripple_phase forward at a slow
	# rate (about 1 unit per sim-minute) so the sand-bed pattern visibly
	# evolves over many minutes of play. Strength + direction picked once
	# at world startup (the aeration system dictates flow direction).
	_substrate_ripple_phase += sdt * 0.018
	if Engine.get_process_frames() % 30 == 0:
		VoxelMat.update_substrate_ripple(
			_substrate_ripple_phase, _substrate_ripple_strength, _substrate_ripple_dir)

	# Cosmetic ambient visuals (sky/stars/clock/disc/lava/water tint/floater
	# drift/sway) are throttled to 10 Hz. `_ambient_due` gates each block below;
	# `adt` is the sim-scaled time elapsed since the last cosmetic update so
	# phase- and rate-based motion advances exactly as it did per-frame.
	_ambient_accum += dt
	var _ambient_due: bool = _ambient_accum >= AMBIENT_VISUAL_INTERVAL
	var adt: float = sdt
	if _ambient_due:
		var _amb_ts: float = float(sim.time_scale) if sim != null else 1.0
		adt = _ambient_accum * _amb_ts
		_ambient_accum = 0.0

	if _ambient_due and sim != null:
		_refresh_atmosphere_caches(adt)
		var ln: Dictionary = _cached_lighting
		var dl: float = ln["dl"]
		var sunset_hour: float = ln["sunset_hour"]
		var deep_night: float = ln["deep_night"]
		if _heater_glow != null and _cfg_node != null:
			var hon: bool = not not _cfg_node.heater_enabled
			_heater_glow.light_energy = 0.6 if hon else 0.04
			_heater_glow.visible = hon

		# 1. Update Sky Color
		if _room_sky_mat != null:
			var sky_col: Color
			var golden: Color = Color8(245, 168, 108)
			var dusk_orange: Color = Color8(210, 175, 155)
			var day_blue: Color = Color8(145, 188, 228)
			var night_dark: Color = Color8(22, 24, 36)
			if dl > 0.65:
				sky_col = dusk_orange.lerp(day_blue, (dl - 0.65) / 0.35)
			elif dl > 0.2:
				sky_col = night_dark.lerp(dusk_orange, (dl - 0.2) / 0.45)
			else:
				sky_col = night_dark
			if sunset_hour > 0.01:
				sky_col = sky_col.lerp(golden, sunset_hour * 0.48)
			if deep_night > 0.45:
				sky_col = sky_col.lerp(night_dark, smoothstep(0.45, 1.0, deep_night) * 0.62)
			if not _room_window_state.is_empty():
				sky_col = WorldRoomBuilder.tick_window(
					_room_window_state, ln, _room_time_passed, sky_col)
				_room_sky_mat = _room_window_state.get("sky_mat", _room_sky_mat)
			else:
				_room_sky_mat.set_shader_parameter("albedo", sky_col)
				var show_stars: bool = (dl < 0.25)
				for star in _room_stars:
					if is_instance_valid(star):
						star.visible = show_stars
						if show_stars:
							var offset_phase: float = star.position.x * 12.3 + star.position.y * 7.9
							var scale_factor: float = 0.7 + 0.3 * sin(_room_time_passed * 3.5 + offset_phase)
							star.scale = Vector3(scale_factor, scale_factor, scale_factor)

		# Tank fixture bleed onto desk + back wall.
		if _room_tank_spill != null or _room_wall_bounce != null:
			var fix_col: Color = Color(1.0, 0.95, 0.85)
			var fix_e: float = 0.5
			if _cfg_node != null:
				fix_col = _cfg_node.tank_fixture_color
				fix_e = float(_cfg_node.tank_fixture_intensity)
			WorldRoomBuilder.tick_room_lights(
				_room_tank_spill, _room_wall_bounce, _room_side_light,
				_room_desk_rim, _room_window_glow, ln,
				fix_col, fix_e, ln["tank_lights_on"], -0.6, _room_haze_base)

	# 3. Update Clock hands (sim day-phase or wall time per room preset)
	if _ambient_due and _room_clock_hour_pivot != null and _room_clock_min_pivot != null:
		var clk: Dictionary = WorldAtmosphere.clock_hand_rotations(_cfg_node, sim)
		_room_clock_hour_pivot.rotation.z = clk["hour_z"]
		_room_clock_min_pivot.rotation.z = clk["min_z"]

	# 4. Update spinning vinyl record disc (synced to music state)
	if _ambient_due and _room_record_disc != null:
		var cfg_player := _cfg_node
		var target_speed: float = 1.5 if (cfg_player != null and cfg_player.music_enabled) else 0.0
		var mr_rec := get_tree().get_first_node_in_group("music_reactive")
		if mr_rec != null and mr_rec.has_method("is_external_playing") and mr_rec.is_external_playing():
			var drive: Dictionary = mr_rec.get_drive() if mr_rec.has_method("get_drive") else {}
			target_speed = 2.2 + float(drive.get("energy", 0.5)) * 1.8
		_room_record_speed = lerpf(_room_record_speed, target_speed, adt * 2.0)
		if _room_record_speed > 0.001:
			_room_record_disc.rotate_y(-adt * _room_record_speed)

	# 5. Update Lava Lamp blobs & glow
	if _ambient_due and _room_lava_lamp_blobs.size() >= 2:
		var blob1 := _room_lava_lamp_blobs[0]
		if is_instance_valid(blob1):
			var b1_y: float = -0.6 + 0.35 + sin(_room_time_passed * 0.45) * 0.20
			blob1.position.y = b1_y
			var b1_vel: float = cos(_room_time_passed * 0.45) * 0.20 * 0.45
			var stretch_y: float = 1.0 + absf(b1_vel) * 0.8
			var stretch_xz: float = 1.0 / sqrt(stretch_y)
			blob1.scale = Vector3(stretch_xz, stretch_y, stretch_xz)
			
		var blob2 := _room_lava_lamp_blobs[1]
		if is_instance_valid(blob2):
			var b2_y: float = -0.6 + 0.65 + cos(_room_time_passed * 0.35 + 0.8) * 0.20
			blob2.position.y = b2_y
			var b2_vel: float = -sin(_room_time_passed * 0.35 + 0.8) * 0.20 * 0.35
			var stretch_y: float = 1.0 + absf(b2_vel) * 0.8
			var stretch_xz: float = 1.0 / sqrt(stretch_y)
			blob2.scale = Vector3(stretch_xz, stretch_y, stretch_xz)
			
		if is_instance_valid(_room_lava_lamp_light):
			_room_lava_lamp_light.light_energy = 0.12 + 0.08 * sin(_room_time_passed * 2.2)

	# Keep the microfauna swarm + detrital worms topped up. Cheap (one
	# child_count + a handful of conditional spawns per ~1 s window).
	_maintain_microfauna(sdt)
	_maintain_wriggle_worms(sdt)
	_maintain_tubifex_patches(sdt)
	_maintain_mycelium_patches(sdt)
	_maintain_biofilm_patches(sdt)
	_refresh_environment_field(sdt)
	_life_bounds_timer = maxf(0.0, _life_bounds_timer - sdt)
	if _life_bounds_timer <= 0.0:
		_life_bounds_timer = LIFE_BOUNDS_INTERVAL
		_enforce_all_life_bounds()
	_maintain_substrate_film(sdt)
	_understory_t = maxf(0.0, _understory_t - sdt)
	if _understory_t <= 0.0:
		_understory_t = randf_range(42.0, 72.0)
		_maybe_walstad_understory()
	# Mineral spots on glass. One slow accumulator tick — every 20-40
	# sim seconds we add a single pale voxel at the waterline on a
	# random wall. Capped so the glass doesn't fully crust over.
	_mineral_progress_t -= sdt
	if _mineral_progress_t <= 0.0:
		_mineral_progress_t = randf_range(20.0, 40.0)
		_maybe_add_mineral_spot()
	# Driftwood biofilm: rises over the first ~5 sim-minutes to ~0.65
	# then very slowly decays as if grazed. We refresh the tints every
	# 2 s rather than per-frame since the change is glacial.
	_biofilm_apply_t -= sdt
	if _biofilm_apply_t <= 0.0:
		_biofilm_apply_t = 2.0
		var target: float = 0.65
		if sim != null:
			target += clampf(float(sim.bloom_intensity), 0.0, 1.0) * 0.08
		# Slow rise (~5 min to reach 0.6), then very slow decay past 0.65.
		var delta: float = (target - biofilm_progress) * sdt * 0.004 + sdt * 0.0008
		biofilm_progress = clampf(biofilm_progress + delta, 0.0, 0.7)
		_apply_biofilm_tints()
		_apply_driftwood_wet_lines()
	# Coral recruitment (saltwater tanks only). Larval settlement is limited
	# by substrate space and competition, not a global count cap.
	if _active_substrate_profile.get("is_saltwater", false):
		_coral_recruit_timer = maxf(0.0, _coral_recruit_timer - sdt)
		if _coral_recruit_timer <= 0.0:
			_coral_recruit_timer = randf_range(CORAL_RECRUIT_MIN, CORAL_RECRUIT_MAX)
			_maybe_recruit_coral()
	if _ambient_due and _visuals != null:
		_visuals.tick(adt, true)
	if _ambient_due and _water_material_ref != null and not _cached_water_column.is_empty():
		var column: Dictionary = _cached_water_column
		var ln_w: Dictionary = _cached_lighting if not _cached_lighting.is_empty() \
			else WorldAtmosphere.day_night_lighting(sim, _cfg_node)
		var atm: Dictionary = ln_w.get("atmosphere", {})
		var ice: float = WorldAtmosphere.ice_lens_uniform(ln_w, atm)
		WorldAtmosphere.apply_water_shader(_water_material_ref, column, ln_w, ice)
		if sim != null and _visuals != null:
			var dp: float = ln_w["dp"]
			var trans: float = float(column.get("transmittance", 1.0))
			var bact: float = float(column.get("bacterial_bloom", 0.0))
			var caust_base: float = _last_caustic_intensity if _last_caustic_intensity >= 0.0 else 0.55
			var caust_i: float = WorldAtmosphere.modulate_caustic_intensity(
				caust_base, trans, bact)
			# Duckweed / lily mats steal surface light — dim caustics tank-wide
			# and sell the "shaded column" read under dense floaters.
			caust_i *= (1.0 - floater_coverage() * 0.42)
			_visuals.sync_aquatic_uniforms(caust_i, _last_caustic_color, WATER_HEIGHT, dp, 0.35)
			var fixture_glow_amb: float = ln_w["deep_night"] * (1.0 if ln_w["tank_lights_on"] else 0.0)
			var foliage_light: float = maxf(ln_w["dl"], fixture_glow_amb * 0.82)
			var bloom: float = float(column.get("bloom_haze", 0.0))
			_visuals.sync_foliage_uniforms(
				clampf(bloom * 0.5 + 0.15, 0.0, 0.65), WATER_HEIGHT, foliage_light)
			VoxelMat.update_fixture_glow(
				fixture_glow_amb, _last_caustic_color, WATER_HEIGHT, SUBSTRATE_DEPTH)

	# Day/night light cycle. The DirectionalLight gives soft ambient room
	# light; the SpotLight3Ds in the fixture give the focused aquarium beam.
	# Both are dimmed by the day/night cycle. Throttled to 10 Hz using
	# real-time dt (not sim-scaled) — at 16× fast-forward we still only
	# write shader parameters 10 times a second, which is plenty for an
	# arc that takes seconds to visibly change.
	_light_cycle_accum += dt
	if sim != null and _light_cycle_accum >= LIGHT_CYCLE_INTERVAL:
		_light_cycle_accum = 0.0
		if _cached_lighting.is_empty() or _cached_water_column.is_empty():
			_refresh_atmosphere_caches(0.0)
		var ln: Dictionary = _cached_lighting
		var dl: float = ln["dl"]
		var sunset_hour: float = ln["sunset_hour"]
		var deep_night: float = ln["deep_night"]
		var tank_lights_on: bool = ln["tank_lights_on"]
		var cfg2 := _cfg_node
		# Split controls (see TankConfig comments): global_* drives sun + room
		# colour, tank_fixture_* drives the artificial overhead.
		var global_energy: float = 0.5
		var global_warmth: float = 0.6
		var fixture_energy: float = 0.5
		var fixture_color: Color = Color(1.0, 0.95, 0.85)
		var sunset_drama: float = 1.0
		if cfg2 != null:
			global_energy = float(cfg2.global_intensity)
			global_warmth = float(cfg2.global_warmth)
			fixture_energy = float(cfg2.tank_fixture_intensity)
			fixture_color = cfg2.tank_fixture_color
			sunset_drama = float(cfg2.sunset_drama)
		var mr := get_tree().get_first_node_in_group("music_reactive")
		if mr != null and mr.has_method("light_fixture_mul"):
			fixture_energy *= float(mr.light_fixture_mul())
			var warm_mix: float = float(mr.light_beam_warmth_mix())
			if warm_mix > 0.001:
				fixture_color = fixture_color.lerp(Color(1.0, 0.72, 0.48), warm_mix)
		# Sunset drama amplifies dusk warmth + how deep night dips. 0 flattens
		# the cycle to a steady mid-day, 2 makes sunset golden and midnight
		# truly dark. Clamped so users can't crash deep_night past 1.0.
		sunset_drama = clampf(sunset_drama, 0.0, 2.5)
		sunset_hour = clampf(sunset_hour * sunset_drama, 0.0, 1.5)
		deep_night = clampf(deep_night * lerpf(0.55, 1.25, sunset_drama * 0.45), 0.0, 1.0)
		# Master kill switch: zero out energies so every downstream multiplier
		# collapses to ~0 (directional/spot/fill all read from these).
		var master_on: bool = cfg2 == null or bool(cfg2.light_master_enabled)
		if not master_on:
			global_energy = 0.0
			fixture_energy = 0.0
			tank_lights_on = false
		var day_beam: Color = Color(0.55, 0.65, 0.95).lerp(
			Color(1.0, 0.95, 0.80), global_warmth)
		var sunset_beam: Color = Color(1.0, 0.78, 0.58)
		var night_beam: Color = Color(1.0, 0.96, 0.88).lerp(
			Color(1.0, 0.94, 0.78), global_warmth * 0.55)
		var beam_color: Color = day_beam
		if sunset_hour > 0.01:
			beam_color = day_beam.lerp(sunset_beam, minf(sunset_hour, 1.0))
		if deep_night > 0.35:
			beam_color = beam_color.lerp(night_beam, smoothstep(0.35, 1.0, deep_night))
		if mr != null and mr.has_method("light_beam_warmth_mix"):
			var beam_warm: float = float(mr.light_beam_warmth_mix())
			if beam_warm > 0.001:
				beam_color = beam_color.lerp(Color(1.0, 0.55, 0.38), beam_warm * 0.45)
		# Room fill fades at night; sunset keeps a warm wash in the room.
		var room_dl: float = dl * (1.0 - deep_night * 0.94) + sunset_hour * 0.18
		room_dl = clampf(room_dl, 0.0, 1.0)
		var room_warm: Color = Color(1.0, 0.82, 0.68)
		var room_color: Color = beam_color.lerp(room_warm, minf(sunset_hour, 1.0) * 0.38)
		# Room mood: the weather outside the window bleeds into the tank. An
		# overcast/rainy day cools and dims the room fill so the whole vivarium
		# shares the gloom; clear/sunset days stay warm. Cheap dict read.
		var weather: String = String(_room_window_state.get("weather", "clear"))
		if weather == "rain" or weather == "overcast" or weather == "storm":
			var gloom: float = 0.5 if weather == "storm" else 0.32
			room_color = room_color.lerp(Color(0.62, 0.70, 0.85), gloom)
			room_dl *= (1.0 - gloom * 0.45)
		if _directional_light != null:
			_directional_light.light_color = room_color
		# Tank fixture: tracks daylight during the day, stays bright at night
		# when the player leaves tank_lights_on enabled. Uses the user-picked
		# fixture color (not the global beam color) so reef-blue, planted-pink,
		# etc. read correctly.
		var spot_day: float = 0.4 + dl * (fixture_energy * 6.0)
		var spot_night: float = fixture_energy * 8.0 if tank_lights_on else 0.0
		var spot_energy: float = lerpf(spot_day, spot_night, deep_night)
		var sphere_soft: bool = TANK_SHAPE == "sphere"
		if sphere_soft:
			spot_energy *= 0.68
		# Fixture spotlights take the user's RGB at night; day blends toward
		# the global beam so the cycle still feels like a sun arc.
		var fixture_lit: Color = fixture_color.lerp(beam_color, 1.0 - deep_night)
		for spot in _light_fixture_spots:
			if not is_instance_valid(spot):
				continue
			spot.light_color = fixture_lit
			spot.light_energy = spot_energy
		if _sphere_fill_light != null and is_instance_valid(_sphere_fill_light):
			_sphere_fill_light.light_color = fixture_lit
			var fill_day: float = 0.08 + dl * (fixture_energy * 0.55)
			var fill_night: float = fixture_energy * 0.42 if tank_lights_on else 0.0
			var fill_e: float = lerpf(fill_day, fill_night, deep_night)
			if sphere_soft:
				fill_e *= 1.35
			_sphere_fill_light.light_energy = fill_e
		if _directional_light != null:
			var dir_e: float = 0.012 + room_dl * (global_energy * 0.48)
			if sphere_soft:
				dir_e *= 1.28
			_directional_light.light_energy = dir_e
			# Sun direction — yaw 0..1 maps to full circle, pitch 0..1 maps from
			# top-down (-90°) to horizontal (0°). Now actually drives the sun
			# instead of just biasing plant phototropism.
			if cfg2 != null:
				var yaw_deg: float = (float(cfg2.light_yaw) - 0.5) * 360.0
				var pitch_deg: float = lerpf(-90.0, -10.0, clampf(float(cfg2.light_pitch), 0.0, 1.0))
				_directional_light.rotation = Vector3(
					deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0.0)
		_update_accent_lights(cfg2, deep_night, master_on)
		var fixture_glow: float = deep_night * (1.0 if tank_lights_on else 0.0)
		if _world_environment != null and _world_environment.environment != null:
			var env: Environment = _world_environment.environment
			if master_on:
				var base_amb: float = lerpf(
					_ENV_AMBIENT_DAY, _ENV_AMBIENT_NIGHT, deep_night)
				# Ambient floor lifts the night minimum so dark scenes stay legible
				# without the user having to crank intensity. 0 = legacy (very dark).
				var floor_v: float = 0.0
				if cfg2 != null:
					floor_v = clampf(float(cfg2.ambient_floor), 0.0, 1.0) * 0.6
				env.ambient_light_energy = maxf(base_amb, floor_v)
				var amb_day := Color(0.7, 0.75, 0.82)
				var amb_night := Color(0.12, 0.10, 0.18)
				env.ambient_light_color = amb_day.lerp(amb_night, deep_night)
			else:
				env.ambient_light_energy = 0.0
		# Fixture wash uses the user-picked fixture color at night so a blue
		# reef fixture lights the water blue from the top down.
		var glow_color: Color = fixture_color.lerp(beam_color, 1.0 - deep_night)
		VoxelMat.update_fixture_glow(fixture_glow, glow_color, WATER_HEIGHT, SUBSTRATE_DEPTH)

		# Sync caustics material — global_energy drives the daytime caustic
		# intensity, fixture_energy gates the night-time pattern when tank lights
		# stay on.
		if _caustics_mat != null:
			var show_caustics: bool = true
			if cfg2 != null:
				show_caustics = not not cfg2.light_caustics

			var intensity: float = 0.0
			if show_caustics:
				var caust_day: float = clampf(dl * global_energy * 2.0, 0.0, 1.0)
				var caust_night: float = clampf(fixture_energy * 1.25, 0.0, 1.0) \
					if tank_lights_on else 0.0
				intensity = lerpf(caust_day, caust_night, deep_night)
				if cfg2 != null:
					intensity *= clampf(float(cfg2.caustic_intensity_user), 0.0, 2.0)
				var trans: float = float(_cached_water_column.get("transmittance", 1.0))
				var bact: float = float(_cached_water_column.get("bacterial_bloom", 0.0))
				intensity = WorldAtmosphere.modulate_caustic_intensity(intensity, trans, bact)
			if mr != null and mr.has_method("caustic_mul"):
				intensity *= float(mr.caustic_mul())
			var caustics_changed: bool = absf(intensity - _last_caustic_intensity) > 0.02 \
				or absf(beam_color.r - _last_caustic_color.r) > 0.04 \
				or absf(beam_color.g - _last_caustic_color.g) > 0.04 \
				or absf(beam_color.b - _last_caustic_color.b) > 0.04
			if caustics_changed:
				_last_caustic_intensity = intensity
				_last_caustic_color = beam_color
				if show_caustics:
					_caustics_mat.set_shader_parameter("caustic_intensity", intensity)
					_caustics_mat.set_shader_parameter("light_color", beam_color)
				else:
					_caustics_mat.set_shader_parameter("caustic_intensity", 0.0)
				VoxelMat.update_caustic_uniforms(intensity if show_caustics else 0.0, beam_color)
				if _water_material_ref != null:
					_water_material_ref.set_shader_parameter(
						"caustic_intensity", intensity if show_caustics else 0.0)
					_water_material_ref.set_shader_parameter("light_color", beam_color)
					_water_material_ref.set_shader_parameter("day_phase_offset",
						float(sim.day_phase) if sim != null else 0.0)
				if _glass_material_ref != null:
					var shape_id: float = 0.0
					if TANK_SHAPE == "cylinder":
						shape_id = 1.0
					elif TANK_SHAPE == "sphere":
						shape_id = 2.0
					_glass_material_ref.set_shader_parameter("tank_shape_id", shape_id)
					var fixture_glow_g: float = deep_night * (1.0 if tank_lights_on else 0.0)
					_glass_material_ref.set_shader_parameter(
						"shape_band", 0.45 + dl * 0.35 + fixture_glow_g * 0.55)
					_glass_material_ref.set_shader_parameter(
						"reflection_strength", 0.15 + dl * 0.12 + fixture_glow_g * 0.22)
					_glass_material_ref.set_shader_parameter(
						"sparkle", fixture_glow_g * 0.9)
					_glass_material_ref.set_shader_parameter(
						"rim_chrome", 0.55 + fixture_glow_g * 0.35)
					_glass_material_ref.set_shader_parameter("water_surface_y", WATER_HEIGHT)

		# Sync god ray materials to the light cycle and Render panel parameters.
		var density: float = 0.02
		var anisotropy: float = 0.3
		if cfg2 != null:
			density = float(cfg2.fog_density)
			anisotropy = float(cfg2.fog_anisotropy)
		
		# Base beam opacity scales with daylight + user density settings.
		# At deep night only the aquarium fixture contributes — no moonlight floor.
		var base_alpha: float = density * 10.0
		var ray_day: float = dl * 0.75
		var ray_night: float = 1.05 if tank_lights_on else 0.0
		var ray_mix: float = lerpf(ray_day, ray_night, deep_night)
		# God-ray opacity blends day side (global) with night side (fixture).
		var ray_energy_mix: float = lerpf(global_energy, fixture_energy, deep_night)
		var ray_alpha: float = base_alpha * ray_mix * (ray_energy_mix / 0.5)
		if TANK_SHAPE == "sphere":
			ray_alpha *= 0.52
		var trans_ray: float = float(_cached_water_column.get("transmittance", 1.0))
		ray_alpha = WorldAtmosphere.modulate_god_ray_alpha(ray_alpha, trans_ray)
		var ray_color := Color(beam_color.r, beam_color.g, beam_color.b, ray_alpha)
		# Matches the range used in _add_god_ray_beam — lowered from
		# 1.5..4.0 to 1.0..2.4 so even the most anisotropic config still
		# gives a beam wide enough to read as a shaft.
		var exponent: float = lerp(1.0, 2.4, (anisotropy + 0.9) / 1.8)

		for mat in _god_ray_materials:
			if mat != null:
				mat.set_shader_parameter("beam_color", ray_color)
				mat.set_shader_parameter("falloff_exponent", exponent)
		# Soft fish occluders + substrate blob shadows share one fish[] scan.
		_update_fish_lighting_contributors()

	# Floater drift + surface-plant sway are cosmetic and slow; run them on the
	# 10 Hz ambient cadence with accumulated dt so motion looks identical.
	if _ambient_due:
		_drift_floaters(adt)
		_sway_surface_plants(adt)

	# Floating-plant growth: a light + nutrient + grazing driven step that
	# spreads the surface mat when conditions favor it and thins it back when
	# crowded, grazed, or dark. See _floater_growth_step.
	_duckweed_accum += sdt
	if _duckweed_accum >= FLOATER_GROWTH_INTERVAL:
		_duckweed_accum = 0.0
		_floater_growth_step()


func _floater_glass_margin(fp: FloatingPlant) -> float:
	return _FLOATER_SURFACE_MARGIN + fp.leaf_size * 0.38


# Soft steering + step clamp so mats drift away from glass before a hard hit.
func _constrain_floater_drift(vel: Vector3, pos: Vector3, margin: float) -> Vector3:
	var push: Vector3 = FaunaBoundary.lateral_push(self, pos, margin, 0.62, vel)
	if push.length_squared() > 1e-6:
		var h_vel: Vector3 = Vector3(vel.x, 0.0, vel.z)
		var outward: Vector3 = -push.normalized()
		var out_spd: float = h_vel.dot(outward)
		if out_spd > 0.0:
			h_vel -= outward * out_spd
		vel = Vector3(h_vel.x, vel.y, h_vel.z)
	var lat: Dictionary = tank_lateral_boundary_info(pos, margin)
	var clearance: float = float(lat.get("clearance", 99.0))
	var inward: Vector3 = lat.get("inward", Vector3.ZERO)
	inward.y = 0.0
	if inward.length_squared() > 1e-6 and clearance < margin * 0.55:
		inward = inward.normalized()
		var nudge: float = (margin * 0.55 - clearance) * 0.55
		vel.x += inward.x * nudge
		vel.z += inward.z * nudge
	var step: float = Vector2(vel.x, vel.z).length()
	if step > 1e-6:
		var ahead: Vector3 = pos + Vector3(vel.x, 0.0, vel.z)
		var ahead_clear: float = float(
			tank_lateral_boundary_info(ahead, margin).get("clearance", 99.0))
		if ahead_clear < step * 0.85:
			var step_scale: float = clampf(ahead_clear / maxf(step * 0.85, 0.01), 0.12, 1.0)
			vel.x *= step_scale
			vel.z *= step_scale
	return vel


# Hard clamp + specular bounce; tangential motion slides along curved glass.
func _resolve_floater_glass(pos: Vector3, vel: Vector3, margin: float,
		surface_y: float) -> Dictionary:
	var px: float = pos.x
	var pz: float = pos.z
	var clamped: Vector2 = clamp_xz_in_tank(px, pz, margin, surface_y)
	var hit: bool = absf(clamped.x - px) > 0.0004 or absf(clamped.y - pz) > 0.0004
	var out_pos: Vector3 = pos
	out_pos.x = clamped.x
	out_pos.z = clamped.y
	var lat: Dictionary = tank_lateral_boundary_info(out_pos, margin)
	var wall_n: Vector3 = lat.get("inward", Vector3.ZERO)
	wall_n.y = 0.0
	if wall_n.length_squared() < 1e-6:
		var xz: Vector2 = Vector2(out_pos.x, out_pos.z)
		if xz.length_squared() > 1e-6:
			wall_n = Vector3(-xz.x, 0.0, -xz.y) / xz.length()
		else:
			wall_n = Vector3(1.0, 0.0, 0.0)
	else:
		wall_n = wall_n.normalized()
	var clearance: float = float(lat.get("clearance", 99.0))
	var h_vel: Vector3 = Vector3(vel.x, 0.0, vel.z)
	if hit or clearance < margin * 0.2:
		var vn: float = h_vel.dot(wall_n)
		if vn < 0.0:
			var tangent: Vector3 = h_vel - wall_n * vn
			h_vel = tangent + wall_n * (-vn * _FLOATER_BOUNCE_DAMP)
		elif hit:
			h_vel += wall_n * lerpf(0.012, 0.038, 1.0 - clampf(clearance / margin, 0.0, 1.0))
	var out_vel: Vector3 = Vector3(h_vel.x, vel.y, h_vel.z)
	if not out_pos.is_finite():
		out_pos = Vector3(clamped.x, pos.y, clamped.y)
	if not out_vel.is_finite():
		out_vel = Vector3.ZERO
	return {"position": out_pos, "vel": out_vel}


# Floaters v2 surface physics: meniscus drift, raft cohesion, soft collision,
# glass bounce, filter shove, ripple bob, daughter tether. 10 Hz + adt.
func _drift_floaters(adt: float) -> void:
	_floater_t += adt
	var surface_y: float = WATER_HEIGHT - 0.05
	_sanitize_floater_positions()
	_rebuild_floater_grid()
	_dead_floaters_scratch.clear()
	# Global surface current: filter return + slow room air drift.
	var drift_vec: Vector3 = Vector3.ZERO
	if sim != null and sim.filter_intake_pos != Vector3.ZERO:
		var jet: Vector3 = sim.filter_intake_pos
		jet.y = 0.0
		if jet.length_squared() > 1e-4:
			# Return jet pushes mats away from the intake corner.
			drift_vec = -jet.normalized() * 0.028
	drift_vec += Vector3(sin(_floater_t * 0.08), 0, cos(_floater_t * 0.06)) * 0.018
	for f in _floaters:
		if not is_instance_valid(f):
			_dead_floaters_scratch.append(f)
			continue
		if not (f is FloatingPlant):
			continue
		var fp: FloatingPlant = f
		if fp.turion_buried:
			continue
		var margin: float = _floater_glass_margin(fp)
		var iid: int = fp.get_instance_id()
		var vel: Vector3 = _floater_vel.get(iid, Vector3.ZERO)
		var ph: float = fp.get_meta("phase", 0.0)
		vel += drift_vec * adt
		var neighbors: Array = query_floaters_in_radius(fp.position, 0.75, true)
		# Surface-tension cohesion — drift toward raft centroid, not tank center.
		if neighbors.size() > 1 and neighbors.size() < 14:
			var centroid: Vector3 = Vector3.ZERO
			var n_n: int = 0
			for nb in neighbors:
				if nb == fp:
					continue
				var nb_pos: Vector3 = (nb as FloatingPlant).position
				if not nb_pos.is_finite():
					continue
				centroid += nb_pos
				n_n += 1
			if n_n > 0:
				centroid /= float(n_n)
				var to_c: Vector3 = centroid - fp.position
				to_c.y = 0.0
				var dist_c: float = to_c.length()
				var pack: float = clampf(float(neighbors.size()) / 10.0, 0.0, 1.0)
				if dist_c > 0.14 and dist_c < 1.6 and to_c.length_squared() > 1e-6:
					var cohesion: float = lerpf(0.14, 0.03, pack) * fp.vitality
					vel += to_c.normalized() * adt * cohesion
		# Soft meniscus collision — floaters push apart instead of stacking.
		for nb in neighbors:
			if nb == fp:
				continue
			var other: FloatingPlant = nb
			if not other.position.is_finite():
				continue
			var sep: Vector3 = fp.position - other.position
			sep.y = 0.0
			var dist: float = sep.length()
			var min_sep: float = maxf(0.14, (fp.leaf_size + other.leaf_size) * 0.52)
			if fp.morph in ["duckweed", "azolla"]:
				min_sep = maxf(min_sep, 0.22)
			if dist < min_sep and dist > 1e-4:
				var push: Vector3 = sep.normalized() * (min_sep - dist)
				fp.position.x += push.x * 0.72
				fp.position.z += push.z * 0.72
				vel += push * (3.4 * adt)
			elif dist <= 1e-4:
				var jitter := Vector3(randf() - 0.5, 0.0, randf() - 0.5)
				if jitter.length_squared() > 1e-6:
					jitter = jitter.normalized() * min_sep * 0.35
					fp.position.x += jitter.x
					fp.position.z += jitter.z
		if sim != null and sim.filter_intake_pos != Vector3.ZERO:
			var to_out: Vector3 = fp.position - sim.filter_intake_pos
			to_out.y = 0.0
			var d_out: float = to_out.length()
			if d_out < 1.2 and d_out > 0.01:
				vel += to_out.normalized() * adt * (1.2 - d_out) * 0.42
		var snagged: bool = _hardscape_cover_density(fp.position.x, fp.position.z, 0.3) > 0.35
		if snagged:
			vel *= 0.12
		else:
			vel.x += sin(_floater_t * 0.15 + ph) * 0.022 * adt
			vel.z += cos(_floater_t * 0.12 + ph * 1.3) * 0.022 * adt
		# Daughter tether — spring to bud offset, not a fixed corner bias.
		if fp.linked_parent_id != "" and fp.tether_timer < 4.5:
			fp.tether_timer += adt
			var parent_v: Variant = _floater_by_id.get(fp.linked_parent_id)
			if parent_v is FloatingPlant and is_instance_valid(parent_v):
				var parent: FloatingPlant = parent_v
				if parent.position.is_finite():
					var rest: Vector3 = fp.get_meta("tether_offset", Vector3.ZERO)
					if rest.length_squared() < 1e-6:
						rest = fp.position - parent.position
						rest.y = 0.0
						fp.set_meta("tether_offset", rest)
					var anchor: Vector3 = parent.position + rest
					anchor.y = surface_y
					var spring: float = clampf(fp.tether_timer / 2.8, 0.0, 1.0)
					var to_anchor: Vector3 = anchor - fp.position
					to_anchor.y = 0.0
					if to_anchor.length_squared() > 1e-6:
						vel += to_anchor.normalized() * adt * lerpf(1.0, 0.35, spring)
		vel = _constrain_floater_drift(vel, fp.position, margin)
		if not vel.is_finite():
			vel = Vector3.ZERO
		fp.position.x += vel.x
		fp.position.z += vel.z
		var glass: Dictionary = _resolve_floater_glass(
			fp.position, vel, margin, surface_y)
		fp.position = glass["position"]
		vel = glass["vel"]
		if vel is Vector3 and not (vel as Vector3).is_finite():
			vel = Vector3.ZERO
		vel *= _FLOATER_DRAG
		var ripple_bob: float = sin(_floater_t * 0.7 + ph + fp.position.x * 0.4) * 0.015
		fp.position.y = surface_y - fp.surface_sink() + ripple_bob
		if fp.spin_rate > 0.0:
			fp.rotation.y += adt * fp.spin_rate
		_sanitize_floater_node(fp, surface_y)
		_floater_vel[iid] = vel
	for df in _dead_floaters_scratch:
		_floaters.erase(df)
		_floater_vel.erase(df.get_instance_id() if is_instance_valid(df) else 0)


# Lily-pad + math-plant (nautilus / cattail / moss) sway. Their tick() advances
# an internal sin phase, so running at 10 Hz with accumulated dt keeps the sway
# rate identical — slow sway reads as perfectly smooth at 10 Hz.
func _sway_surface_plants(adt: float) -> void:
	var sway_dt: float = adt
	var mr := get_tree().get_first_node_in_group("music_reactive")
	if mr != null and mr.has_method("plant_sway_mult"):
		sway_dt *= float(mr.plant_sway_mult())
	for mp in _math_plants:
		if not is_instance_valid(mp):
			continue
		if mp.has_method("tick"):
			mp.tick(sway_dt)
	_lily_pad_t += adt
	for lp in _lily_pads:
		if not is_instance_valid(lp):
			continue
		if lp.has_method("tick"):
			lp.tick(sway_dt)


# ---- Materials ----

func _solid_mat(color: Color, _emission_strength: float = 0.55) -> ShaderMaterial:
	return VoxelMat.make(color)


func _fauna_mat(color: Color) -> ShaderMaterial:
	return VoxelMat.make_fauna(color)


func _glass_mat() -> ShaderMaterial:
	var shape_id: float = 0.0
	if TANK_SHAPE == "cylinder":
		shape_id = 1.0
	elif TANK_SHAPE == "sphere":
		shape_id = 2.0
	_glass_material_ref = VoxelMat.make_glass(shape_id, WATER_HEIGHT)
	return _glass_material_ref


func _water_mat() -> ShaderMaterial:
	var shallow := Color(C_WATER_SHALLOW.r, C_WATER_SHALLOW.g, C_WATER_SHALLOW.b, 0.12)
	var deep := Color(C_WATER_DEEP.r, C_WATER_DEEP.g, C_WATER_DEEP.b, 0.20)
	var m := VoxelMat.make_water(shallow, deep, SUBSTRATE_DEPTH, WATER_HEIGHT)
	m.set_shader_parameter("wave_amplitude", 0.028)
	m.set_shader_parameter("caustic_intensity", 0.55)
	var shape_id: float = 0.0
	if TANK_SHAPE == "cylinder":
		shape_id = 1.0
	elif TANK_SHAPE == "sphere":
		shape_id = 2.0
	m.set_shader_parameter("tank_shape_id", shape_id)
	return m


# Shape-aware particle emission — box tanks use rectangular extents; curved
# tanks use ring/sphere so ripples and haze don't spawn in the void outside glass.
func configure_meniscus_emission(pm: ParticleProcessMaterial, band_height: float = 0.02) -> void:
	if TANK_SHAPE == "cylinder":
		var r: float = _footprint().effective_radius(0.5)
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_radius = r
		pm.emission_ring_inner_radius = 0.0
		pm.emission_ring_height = band_height
	elif TANK_SHAPE == "sphere":
		var r: float = _footprint().effective_radius(0.45)
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = r * 0.88
	else:
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(
			TANK_HALF_W - 0.5, band_height, TANK_HALF_D - 0.5)


func configure_column_emission(pm: ParticleProcessMaterial, half_height: float,
		inset: float = 0.65) -> void:
	if TANK_SHAPE == "cylinder":
		var r: float = _footprint().effective_radius(inset)
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_radius = r
		pm.emission_ring_inner_radius = 0.0
		pm.emission_ring_height = half_height
	elif TANK_SHAPE == "sphere":
		var r: float = _footprint().effective_radius(inset)
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = r * 0.72
	else:
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(
			TANK_HALF_W - 0.8, half_height, TANK_HALF_D - 0.8)


# ---- Static environment builders ----

func _add_cube(parent: Node, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelMat.get_box(size)
	mi.position = pos
	if mat != null:
		mi.material_override = mat
	parent.add_child(mi)
	return mi


# Public so main.gd / aquascape mode can clamp clicks to the tank footprint.
func is_inside_tank(x: float, z: float, margin: float = 0.0, world_y: float = NAN) -> bool:
	if is_nan(world_y):
		world_y = SUBSTRATE_DEPTH
	return _footprint().is_inside(x, z, margin, world_y)


func clamp_xz_in_tank(x: float, z: float, margin: float = 0.25,
		world_y: float = NAN) -> Vector2:
	return _footprint().clamp_inside(x, z, margin, world_y)


func fits_plant_at(x: float, z: float, radius: float, margin: float = 0.25,
		world_y: float = NAN) -> bool:
	if is_nan(world_y):
		world_y = column_surface_y(x, z)
	return _footprint().fits_point_with_radius(x, z, radius, margin, world_y)


func lateral_room_at(x: float, z: float, margin: float = 0.25,
		world_y: float = NAN) -> float:
	if is_nan(world_y):
		world_y = column_surface_y(x, z)
	return _footprint().lateral_room(x, z, margin, world_y)


func tank_boundary_info(p: Vector3, margin: float = 0.25) -> Dictionary:
	return _footprint().boundary_info(p.x, p.y, p.z, margin)


func tank_lateral_boundary_info(p: Vector3, margin: float = 0.25) -> Dictionary:
	return _footprint().lateral_boundary_info(p.x, p.y, p.z, margin)


func tank_vertical_boundary_info(p: Vector3, margin: float = 0.25,
		floor_band: float = -1.0, ceil_band: float = -1.0) -> Dictionary:
	var fb: float = 0.50 if floor_band < 0.0 else floor_band
	var cb: float = 0.42 if ceil_band < 0.0 else ceil_band
	return _footprint().vertical_boundary_info(p.x, p.y, p.z, margin, fb, cb)


func preferred_y_at(x: float, z: float, frac: float, floor_y: float = NAN) -> float:
	return _footprint().column_fraction_to_y(x, z, frac, 0.35, floor_y)


func toggle_motion_debug() -> bool:
	if motion_debug == null:
		return false
	motion_debug.toggle()
	return motion_debug.enabled


func clamp_plant_site(x: float, z: float, radius: float, margin: float = 0.25,
		world_y: float = NAN) -> Vector2:
	if is_nan(world_y):
		world_y = column_surface_y(x, z)
	var fp := _footprint()
	var xz: Vector2 = fp.clamp_inside(x, z, margin + radius, world_y)
	if fp.fits_point_with_radius(xz.x, xz.y, radius, margin, world_y):
		return xz
	for t in [0.15, 0.3, 0.45, 0.6, 0.75, 0.9]:
		var q: Vector2 = xz.lerp(Vector2.ZERO, t)
		if fp.fits_point_with_radius(q.x, q.y, radius, margin, world_y):
			return q
	return fp.clamp_inside(0.0, 0.0, margin + radius, world_y)


func clamp_xyz_in_tank(p: Vector3, margin: float = 0.25,
		body_radius: float = 0.0) -> Vector3:
	var total_margin: float = margin + maxf(0.0, body_radius)
	var c: Vector3 = _footprint().clamp_inside_3d(p, total_margin)
	if p.y <= WATER_HEIGHT + 0.12:
		c.y = minf(c.y, WATER_HEIGHT - total_margin)
	if body_radius > 0.0 and not _footprint().fits_point_with_radius(
			c.x, c.z, body_radius, margin, c.y):
		var xz: Vector2 = _footprint().clamp_inside(p.x, p.z, margin + body_radius, c.y)
		c.x = xz.x
		c.z = xz.y
		c = _footprint().clamp_inside_3d(c, total_margin)
	return c


func enforce_entity_in_tank(node: Node3D, margin: float = 0.25,
		body_radius: float = 0.0) -> void:
	if node == null or not is_instance_valid(node):
		return
	var total_m: float = margin + maxf(0.0, body_radius)
	var c: Vector3 = clamp_xyz_in_tank(node.global_position, margin, body_radius)
	node.global_position = c
	if is_inside_tank_volume(c.x, c.y, c.z, total_m * 0.5):
		return
	# Curved / polygon tanks can still fail the volume probe after clamp.
	# Slide onto the nearest wall — never snap to tank center (reads as a bounce).
	var info: Dictionary = tank_lateral_boundary_info(c, total_m * 0.55)
	var inward: Vector3 = info.get("inward", Vector3.ZERO)
	inward.y = 0.0
	if inward.length_squared() > 1e-6:
		node.global_position = boundary_point_on_wall(
			c.y, inward.normalized(), total_m * 0.45)
	else:
		node.global_position = clamp_xyz_in_tank(c, margin + 0.08, body_radius)


func _enforce_all_life_bounds() -> void:
	if sim == null:
		return
	# Fauna bounds (fish, shrimp, snails, eggs, waste) are enforced on the
	# same cadence by sim_driver._enforce_all_fauna_in_tank — skip here to
	# avoid walking the same arrays twice every ~0.22 s.
	for a in sim.algae:
		if is_instance_valid(a) and a is Node3D:
			enforce_entity_in_tank(a as Node3D, 0.22, 0.12)
	# Microfauna self-clamp inside the MicrofaunaSwarm tick — no per-node pass.
	if wriggle_root != null:
		for w in wriggle_root.get_children():
			if is_instance_valid(w) and w is Node3D:
				enforce_entity_in_tank(w as Node3D, 0.20, 0.06)


func is_inside_tank_volume(x: float, y: float, z: float, margin: float = 0.0) -> bool:
	return _footprint().is_inside_3d(x, y, z, margin)


func clamp_to_tank(p: Vector3, margin: float = 0.2) -> Vector3:
	return clamp_xyz_in_tank(p, margin)


func clamp_emergent_in_tank(p: Vector3, margin: float = 0.25) -> Vector3:
	# Canopy / flowers may rise above the water line (sphere bowl opening).
	if TANK_SHAPE == "sphere":
		return _footprint().clamp_inside_3d(p, margin)
	return clamp_xyz_in_tank(p, margin)


func _footprint() -> TankFootprint:
	if _footprint_cache == null:
		_footprint_cache = TankFootprint.from_values(TANK_SHAPE, TANK_HALF_W, TANK_HALF_D)
		_footprint_cache.substrate_y = SUBSTRATE_DEPTH
		_footprint_cache.water_y = WATER_HEIGHT
		_footprint_cache.tank_height = TANK_HEIGHT
	return _footprint_cache


# Public XZ sampler. Used by SimDriver when it needs a random tank-interior
# position for algae or anything else spawned at runtime, without exposing
# the private RNG / sampling internals.
func sample_xz_in_tank(margin: float = 0.4) -> Vector2:
	return _footprint().random_point(margin, _rng)


func _is_inside_tank(x: float, z: float, margin: float = 0.0) -> bool:
	return _footprint().is_inside(x, z, margin)


func _substrate_voxel_ok(x: float, y: float, z: float, margin: float) -> bool:
	if TANK_SHAPE == "sphere":
		return _sphere_substrate_voxel_ok(x, y, z, margin)
	return _footprint().is_substrate_voxel(x, y, z, margin)


# Aquascape sculpting: allow stacking above the default substrate depth up to
# the water line, as long as XZ stays inside the tank footprint.
func _sculpt_voxel_ok(x: float, y: float, z: float, margin: float) -> bool:
	if y < -0.05 or y > WATER_HEIGHT - 0.35:
		return false
	if TANK_SHAPE == "sphere":
		return _sphere_sculpt_voxel_ok(x, y, z, margin)
	return _footprint().is_inside(x, z, margin)


func _sphere_sculpt_voxel_ok(x: float, y: float, z: float, margin: float) -> bool:
	var bowl: Dictionary = _sphere_bowl_params()
	if bowl.is_empty():
		return false
	var R: float = float(bowl["R"]) - margin - 0.14
	var cy: float = float(bowl["cy"])
	if y < 0.0 or y > WATER_HEIGHT - 0.35:
		return false
	var r_max: float = _bowl_ring_radius(R, cy, y)
	if y < cy - 0.05:
		var dy_below: float = cy - y
		if dy_below > R:
			return false
		r_max = minf(r_max, sqrt(maxf(0.0, R * R - dy_below * dy_below)))
	return x * x + z * z <= r_max * r_max


func _terrain_cell_ok(x: float, y: float, z: float, margin: float) -> bool:
	if y <= SUBSTRATE_DEPTH + TerrainVoxelGrid.CELL_SIZE * 0.6:
		return _substrate_voxel_ok(x, y, z, margin)
	return _sculpt_voxel_ok(x, y, z, margin)


func _sample_point_in_tank(y_min: float, y_max: float, margin: float = 0.35) -> Vector3:
	return _footprint().random_point_in_volume(y_min, y_max, margin, _rng)


# Shape-aware 3D spawn for fish — spreads schools through the water column,
# critical for dome bowls where the usable XZ ring shrinks with height.
func _apply_founding_cohort_spread(g: Dictionary, i: int, count: int) -> void:
	if count <= 1:
		return
	# Vertical spread on every tank shape — schools shouldn't seed as one slab.
	g["preferred_y_frac"] = clampf(
		float(i) / float(maxi(count - 1, 1)) * 0.76 + 0.10
		+ randf_range(-0.06, 0.06), 0.08, 0.92)
	# Ring-seed home territories so patrol zones cover the footprint from day one.
	var fp := _footprint()
	var ring_a: float = TAU * float(i) / float(count) + randf_range(-0.3, 0.3)
	var ring_r: float = fp.effective_radius(0.35) * randf_range(0.32, 0.78)
	g["home_x"] = cos(ring_a) * ring_r
	g["home_z"] = sin(ring_a) * ring_r


func _sample_fish_spawn_pos(g: Dictionary = {}) -> Vector3:
	var y_min: float = SUBSTRATE_DEPTH + 0.35
	var y_max: float = WATER_HEIGHT - 0.45
	var col: float = maxf(0.5, y_max - y_min)
	var col_frac: float = randf()
	if g.has("preferred_y_frac"):
		col_frac = clampf(float(g["preferred_y_frac"]), 0.05, 0.95)
	elif g.has("preferred_y"):
		col_frac = clampf((float(g["preferred_y"]) - SUBSTRATE_DEPTH) / col, 0.05, 0.95)
	col_frac = clampf(col_frac + randf_range(-0.1, 0.1), 0.05, 0.95)
	if TANK_SHAPE == "sphere" or TANK_SHAPE == "cylinder":
		var target_y: float = lerpf(y_min, y_max, col_frac)
		for _attempt in 36:
			var pt: Vector3 = _sample_point_in_tank(
				target_y - col * 0.08, target_y + col * 0.08, 0.35)
			if is_inside_tank_volume(pt.x, pt.y, pt.z, 0.32):
				return clamp_xyz_in_tank(pt, 0.35)
	return clamp_xyz_in_tank(_sample_point_in_tank(y_min, y_max, 0.35), 0.35)


func _substrate_edge_bias(default: float = 0.48) -> float:
	if TANK_SHAPE == "sphere":
		return default
	if TANK_SHAPE == "cylinder":
		return default * 0.45
	return 0.0


# Ecology-driven carrying capacities (soft limits from tank volume + state).
func _tank_volume_proxy() -> float:
	var fp := _footprint()
	var r: float = fp.effective_radius(0.35)
	var col: float = maxf(1.0, WATER_HEIGHT - SUBSTRATE_DEPTH)
	return r * r * col


func algae_carrying_capacity() -> int:
	var bloom: float = float(sim.bloom_intensity) if sim != null else 0.0
	return maxi(24, int(_tank_volume_proxy() * (1.8 + bloom * 2.2)))


func snail_carrying_capacity() -> int:
	return maxi(4, int(_tank_volume_proxy() * 0.22))


func shrimp_carrying_capacity() -> int:
	return maxi(6, int(_tank_volume_proxy() * 0.38))


func boundary_point_on_wall(y: float, wall_n: Vector3, inset: float = 0.07) -> Vector3:
	var n: Vector3 = wall_n.normalized()
	if n.dot(Vector3.UP) > 0.85:
		var xz: Vector2 = _sample_substrate_xz(0.35, 0.18, 0.15)
		return clamp_xyz_in_tank(
			Vector3(xz.x, SUBSTRATE_DEPTH + 0.08, xz.y), 0.32, 0.08)
	var fp := _footprint()
	var from := Vector3(0.0, y, 0.0)
	var dir: Vector3 = -n
	if dir.length_squared() < 1e-6:
		dir = Vector3(1.0, 0.0, 0.0)
	dir = dir.normalized()
	var max_scan: float = maxf(fp.half_w, fp.half_d) * 2.4
	var step: float = maxf(0.08, max_scan / 56.0)
	var last_good: Vector3 = from
	var dist: float = 0.0
	while dist <= max_scan:
		var q: Vector3 = from + dir * dist
		if fp.is_inside_3d(q.x, q.y, q.z, 0.22):
			last_good = q
		elif dist > step:
			return clamp_xyz_in_tank(last_good - n * inset, 0.30, 0.08)
		dist += step
	return clamp_xyz_in_tank(last_good - n * inset, 0.30, 0.08)


func _snail_founder_layout(is_saltwater: bool) -> Array:
	var wall_dirs: Array = [
		Vector3(-1, 0, 0), Vector3(1, 0, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1),
	]
	var y_fracs: Array = [0.32, 0.52, 0.28, 0.46, 0.38, 0.58]
	var shapes_fw: Array = ["turbo", "apple", "turbo", "turbo", "apple", "turbo"]
	var out: Array = []
	var count: int = 8 if is_saltwater else 6
	for i in count:
		var wn: Vector3 = wall_dirs[i % wall_dirs.size()]
		var shape: String = shapes_fw[i % shapes_fw.size()]
		var yf: float = float(y_fracs[i % y_fracs.size()])
		if is_saltwater and i >= 5:
			wn = Vector3.UP
			shape = "nassarius"
			yf = 0.0
		var y: float = SUBSTRATE_DEPTH + 0.08 if wn.dot(Vector3.UP) > 0.85 \
			else lerpf(SUBSTRATE_DEPTH + 0.35, WATER_HEIGHT - 0.28, yf)
		var pos: Vector3 = boundary_point_on_wall(y, wn)
		out.append([pos, wn, shape])
	return out


func _configure_snail_node(snail: Node3D, pos: Vector3, wall_n: Vector3,
		shape: String, palette: Array, palette_i: int) -> void:
	snail.position = pos
	snail.set("wall_normal", wall_n)
	snail.set("wall_min", Vector3(-TANK_HALF_W + 0.4, SUBSTRATE_DEPTH + 0.05,
		-TANK_HALF_D + 0.4))
	snail.set("wall_max", Vector3(TANK_HALF_W - 0.4, WATER_HEIGHT - 0.2,
		TANK_HALF_D - 0.4))
	snail.set("shell_color", palette[palette_i % palette.size()])
	snail.set("shell_size", _rng.randf_range(0.85, 1.15))
	snail.set("generation", 0)
	snail.set("shell_shape", shape)
	snail.set("shell_spines", _rng.randf_range(0.0, 0.45))
	snail.set("toxin_level", _rng.randf_range(0.0, 0.35))
	# Founder shell variety: most keep their layout shape, but a quarter roll
	# one of the expanded shells so a starting colony shows the range and can
	# drift further. Spire / whorl / pattern get matching variety.
	var rolled_shape: String = shape
	if _rng.randf() < 0.25:
		var pool: Array = ["ramshorn", "tower", "trochus", "limpet", "conch"]
		rolled_shape = pool[_rng.randi() % pool.size()]
		snail.set("shell_shape", rolled_shape)
	snail.set("spire_height",
		_rng.randf_range(0.7, 1.6) if rolled_shape == "tower" else _rng.randf_range(0.7, 1.25))
	snail.set("whorl_count",
		_rng.randi_range(5, 8) if rolled_shape == "tower" else _rng.randi_range(3, 6))
	snail.set("shell_pattern", _rng.randi() % 4)
	snail.set("operculum", _rng.randf() < 0.4)
	snail.set("aperture_flare",
		_rng.randf_range(0.4, 0.9) if rolled_shape == "conch" else _rng.randf_range(0.0, 0.3))


# Detritivore feedback: snails / shrimp / fish that consume a waste particle
# call this with the consumed nutrient_value. The food feeds soil bacteria
# (small biofilm_progress bump) which then ripples through the N-cycle via
# water_chemistry.bacteria. Clamped so a feeding frenzy can't slam biofilm
# to 1.0 in seconds — biofilm growth is still a slow process; the cleanup
# crew just makes it not-quite-so-slow when a tank is well-cycled.
# Instant-mature cold start. Make a freshly-stocked tank read as established
# within the first second: biofilm patina on glass + driftwood, founders that
# already carry a couple of generations of lineage depth, and a spread of ages
# rather than one synchronized cohort. Aesthetic; persists via the normal save.
func _apply_mature_cold_start() -> void:
	biofilm_progress = maxf(biofilm_progress, 0.5)
	if has_method("_apply_biofilm_tints"):
		_apply_biofilm_tints()
	if sim == null:
		return
	_mature_creatures(sim.fish)
	_mature_creatures(sim.shrimp)
	if sim.snails_root != null and is_instance_valid(sim.snails_root):
		_mature_creatures(sim.snails_root.get_children())


# Bump lineage depth + spread ages on a set of founder creatures. Static + duck-
# typed (works on fish / shrimp / snails) so it can be unit-tested in isolation.
static func _mature_creatures(creatures: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for c in creatures:
		if c == null or not is_instance_valid(c):
			continue
		if c.get("generation") != null:
			c.set("generation", maxi(int(c.get("generation")), 2))
			# Fish/shrimp cache their genome; keep its generation in sync so the
			# Life Library + breeding parent keys reflect the lineage depth.
			var sg: Variant = c.get("_saved_genome")
			if sg is Dictionary:
				(sg as Dictionary)["generation"] = int(c.get("generation"))
		var max_age_v: Variant = c.get("max_age_s")
		if max_age_v != null and c.get("age") != null:
			# Mid-life band: established-looking, clear of senescence so no founder
			# spawns about to die.
			c.set("age", rng.randf_range(0.2, 0.5) * float(max_age_v))


func boost_biofilm(amount: float) -> void:
	biofilm_progress = clampf(biofilm_progress + amount * 0.06, 0.0, 0.7)


# Live count of swarming microfauna. Used by water_chemistry to give a
# tiny extra bacteria multiplier — a dense swarm of paramecia / copepods
# / rotifers indicates an active microbial layer and accelerates
# nitrification past what biofilm_progress alone implies.
func live_microfauna_count() -> int:
	if microfauna_root == null:
		return 0
	return microfauna_root.count()


func microfauna_carrying_capacity() -> int:
	var tiny_scale: float = float(_library_tiny_life_scalars().get("micro", 1.0))
	var base: float = _tank_volume_proxy() * 0.42
	var mulm: float = float(_mulm_voxels.size()) * 0.55
	var bio: float = biofilm_progress * 140.0
	var bloom: float = float(sim.bloom_intensity) * 90.0 if sim != null else 0.0
	var floater_bio: float = 0.0
	for f in _floaters:
		if f is FloatingPlant and (f as FloatingPlant).root_biofilm > 0.3:
			floater_bio += 12.0
	return maxi(4, int((base + mulm + bio + bloom + floater_bio) * tiny_scale))


func wriggle_carrying_capacity() -> int:
	var tiny_scale: float = float(_library_tiny_life_scalars().get("wriggle", 1.0))
	return int(float(_mulm_voxels.size()) * WRIGGLE_PER_MULM_FRAC * tiny_scale)


func _mulm_carrying_capacity() -> int:
	return maxi(60, int(_tank_volume_proxy() * 3.2))


func _surface_floater_capacity() -> int:
	var area: float = _footprint().usable_surface_area(0.35, WATER_HEIGHT - 0.05)
	# Larger divisor = fewer nominal slots; duckweed clumps are visually wider than
	# 0.26u so count-based coverage was hitting 80% at hundreds of nodes.
	var base: int = maxi(8, int(area / 0.38))
	return WorldFloaterManager.scaled_surface_capacity(base, TANK_SHAPE)


# Sample XZ on the substrate disk. edge_bias 0 = uniform area; higher = rim.
func _sample_substrate_xz(margin: float = 0.35, edge_bias: float = -1.0,
		min_lateral_room: float = 0.0) -> Vector2:
	if edge_bias < 0.0:
		edge_bias = _substrate_edge_bias()
	if TANK_SHAPE == "sphere" or TANK_SHAPE == "cylinder":
		var fp := _footprint()
		var rad: float = fp.radius_at_height(SUBSTRATE_DEPTH, margin) * 0.90
		for _attempt in 32:
			var ang: float = _rng.randf() * TAU
			var u: float = _rng.randf()
			var dist: float = lerpf(sqrt(u), u, edge_bias) * rad
			var xz := Vector2(cos(ang) * dist, sin(ang) * dist)
			if not fp.is_inside(xz.x, xz.y, margin, SUBSTRATE_DEPTH):
				continue
			if min_lateral_room > 0.0 \
					and fp.lateral_room(xz.x, xz.y, margin, SUBSTRATE_DEPTH) < min_lateral_room:
				continue
			return xz
		return fp.random_point(margin, _rng)
	return _footprint().random_point(margin, _rng)


func _sample_surface_xz(margin: float = 0.35, edge_bias: float = -1.0) -> Vector2:
	if edge_bias < 0.0:
		edge_bias = _substrate_edge_bias(0.32)
	var y: float = WATER_HEIGHT - 0.05
	if TANK_SHAPE == "sphere" or TANK_SHAPE == "cylinder":
		var fp := _footprint()
		var rad: float = fp.radius_at_height(y, margin) * 0.88
		for _attempt in 32:
			var ang: float = _rng.randf() * TAU
			var u: float = _rng.randf()
			var dist: float = lerpf(sqrt(u), u, edge_bias) * rad
			var xz := Vector2(cos(ang) * dist, sin(ang) * dist)
			if fp.is_inside(xz.x, xz.y, margin, y):
				return xz
		return fp.clamp_inside(0.0, 0.0, margin, y)
	return _sample_substrate_xz(margin, edge_bias)


func _random_inside_tank(margin: float = 0.4) -> Vector3:
	var xz: Vector2 = _footprint().random_point(margin, _rng)
	return Vector3(xz.x, 0.0, xz.y)


func _random_xz_in_band(z_min: float, z_max: float, margin: float = 0.4,
		min_lateral_room: float = 0.0, edge_bias: float = -1.0) -> Vector2:
	if TANK_SHAPE == "sphere" or TANK_SHAPE == "cylinder":
		return _sample_substrate_xz(margin, edge_bias, min_lateral_room)
	return _footprint().random_point_in_band(
		z_min, z_max, margin, _rng, min_lateral_room)


func _spawn_z_band(role: String) -> Vector2:
	# Triangle apex is at +Z — keep dense carpets on the wide base, not the point.
	match TANK_SHAPE:
		"triangle":
			match role:
				"background":
					return Vector2(-TANK_HALF_D * 0.95, -TANK_HALF_D * 0.45)
				"mid":
					return Vector2(-TANK_HALF_D * 0.55, TANK_HALF_D * 0.05)
				"foreground":
					return Vector2(-TANK_HALF_D * 0.88, -TANK_HALF_D * 0.30)
				"scatter":
					return Vector2(-TANK_HALF_D * 0.75, TANK_HALF_D * 0.12)
		"sphere", "cylinder":
			# Full disk — bowl footprint is circular, not a front-to-back strip.
			var rim: float = TANK_HALF_D * 0.82
			return Vector2(-rim, rim)
		_:
			match role:
				"background":
					return Vector2(-TANK_HALF_D * 0.95, -TANK_HALF_D * 0.45)
				"mid":
					return Vector2(-TANK_HALF_D * 0.5, TANK_HALF_D * 1.5)
				"foreground":
					return Vector2(TANK_HALF_D * 0.2, TANK_HALF_D * 0.95)
				"scatter":
					return Vector2(-TANK_HALF_D * 0.8, TANK_HALF_D * 0.5)
	return Vector2(-TANK_HALF_D * 0.5, TANK_HALF_D * 0.5)


func _fit_xz_inside_tank(x: float, z: float, margin: float = 0.25) -> Vector2:
	return _footprint().clamp_inside(x, z, margin)


func _hardscape_cell_key(x: float, z: float) -> String:
	var cx: int = int(floor(x / HARDSCAPE_CELL_SIZE))
	var cz: int = int(floor(z / HARDSCAPE_CELL_SIZE))
	return "%d:%d" % [cx, cz]


func _mark_hardscape_occupancy(center: Vector3, size: Vector3) -> void:
	var radius_x: float = size.x * 0.5 + 0.25
	var radius_z: float = size.z * 0.5 + 0.25
	var x0: float = center.x - radius_x
	var x1: float = center.x + radius_x
	var z0: float = center.z - radius_z
	var z1: float = center.z + radius_z
	var x: float = x0
	while x <= x1:
		var z: float = z0
		while z <= z1:
			if _is_inside_tank(x, z, 0.15):
				_hardscape_occupancy[_hardscape_cell_key(x, z)] = true
			z += HARDSCAPE_CELL_SIZE
		x += HARDSCAPE_CELL_SIZE


func _is_hardscape_occupied(x: float, z: float, clearance: float = 0.6) -> bool:
	var r: float = maxf(0.15, clearance)
	var x0: float = x - r
	var x1: float = x + r
	var z0: float = z - r
	var z1: float = z + r
	var sx: float = HARDSCAPE_CELL_SIZE
	var xq: float = x0
	while xq <= x1:
		var zq: float = z0
		while zq <= z1:
			if _hardscape_occupancy.has(_hardscape_cell_key(xq, zq)):
				return true
			zq += sx
		xq += sx
	return false


func _sample_clear_xz_in_band(
		z_min: float, z_max: float, margin: float = 0.4,
		clearance: float = 0.6, tries: int = 36,
		lateral_radius: float = 0.0, edge_bias: float = -1.0) -> Vector2:
	for _i in tries:
		var xz: Vector2 = _random_xz_in_band(
			z_min, z_max, margin, lateral_radius, edge_bias)
		if lateral_radius > 0.0 and not _footprint().fits_point_with_radius(
				xz.x, xz.y, lateral_radius, margin):
			continue
		if not _is_hardscape_occupied(xz.x, xz.y, clearance):
			return xz
	for shrink in [lateral_radius * 0.55, lateral_radius * 0.25, 0.0]:
		for _i in tries:
			var xz: Vector2 = _random_xz_in_band(
				z_min, z_max, margin, shrink, edge_bias)
			if shrink > 0.0 and not _footprint().fits_point_with_radius(
					xz.x, xz.y, shrink, margin):
				continue
			if not _is_hardscape_occupied(xz.x, xz.y, clearance):
				return xz
	var fallback: Vector2 = _random_xz_in_band(z_min, z_max, margin, 0.0, edge_bias)
	return _footprint().clamp_inside(fallback.x, fallback.y, margin)


func _pick_ecology_site(is_saltwater: bool, z_min: float, z_max: float,
		margin: float = 0.4, clearance: float = 0.6, edge_bias: float = -1.0) -> Vector2:
	# Candidate scoring so settlement responds to local habitat and to
	# the creature-driven nutrient mosaic, rather than pure RNG.
	var best: Vector2 = _sample_clear_xz_in_band(
		z_min, z_max, margin, clearance, 36, 0.0, edge_bias)
	var best_score: float = -INF
	for _i in 14:
		var c: Vector2 = _sample_clear_xz_in_band(
			z_min, z_max, margin, clearance, 36, 0.0, edge_bias)
		var h: Dictionary = habitat_profile_at(
			Vector3(c.x, column_surface_y(c.x, c.y), c.y))
		var substrate_local: float = float(h.get("substrate_local", 0.5))
		var cover: float = float(h.get("cover", 0.0))
		var edge: float = float(h.get("edge", 0.5))
		var score: float
		if is_saltwater:
			score = cover * 0.55 + (1.0 - absf(edge - 0.35)) * 0.35 + substrate_local * 0.10
		else:
			score = substrate_local * 0.65 + cover * 0.15 + (1.0 - absf(edge - 0.45)) * 0.20
		score += randf_range(-0.04, 0.04)
		if score > best_score:
			best_score = score
			best = c
	return best


func habitat_profile_at(pos: Vector3) -> Dictionary:
	# Local habitat fingerprint used by behavior + evolution systems.
	# Values are normalized to 0..1 so callers can blend them directly.
	var x: float = pos.x
	var z: float = pos.z
	var y: float = pos.y
	var cover: float = _hardscape_cover_density(x, z, 1.0)
	var edge: float = _edge_proximity(x, z)
	var col_h: float = maxf(0.5, WATER_HEIGHT - SUBSTRATE_DEPTH)
	var floor_y: float = column_surface_y(x, z)
	var depth: float = clampf((y - floor_y) / col_h, 0.0, 1.0)
	var substrate_richness: float = 0.5
	if substrate_grid != null:
		var raw: float = substrate_grid.get_at(Vector3(x, floor_y, z))
		substrate_richness = clampf(
			(raw - substrate_grid.NUTRIENT_BASELINE) / 0.5, 0.0, 1.0)
	return {
		"cover": cover,
		"edge": edge,
		"depth": depth,
		"substrate_local": substrate_richness,
	}


func _hardscape_cover_density(x: float, z: float, radius: float) -> float:
	var occupied: float = 0.0
	var samples: float = 0.0
	var step: float = HARDSCAPE_CELL_SIZE
	var x0: float = x - radius
	var x1: float = x + radius
	var z0: float = z - radius
	var z1: float = z + radius
	var sx: float = x0
	while sx <= x1:
		var sz: float = z0
		while sz <= z1:
			if _is_inside_tank(sx, sz, 0.1):
				samples += 1.0
				if _hardscape_occupancy.has(_hardscape_cell_key(sx, sz)):
					occupied += 1.0
			sz += step
		sx += step
	if samples <= 0.0:
		return 0.0
	return clampf(occupied / samples, 0.0, 1.0)


func _edge_proximity(x: float, z: float) -> float:
	# 0 = center/open interior, 1 = right up against the walls.
	var clear: float = 0.0
	var m: float = 0.1
	while m <= 2.2:
		if not _is_inside_tank(x, z, m):
			break
		clear = m
		m += 0.1
	return clampf(1.0 - (clear / 2.2), 0.0, 1.0)


func _setup_caustics() -> void:
	pass # All caustics are now computed in a single opaque shader pass.


func _sphere_substrate_column_floor(x: float, z: float, bowl: Dictionary) -> float:
	var R: float = float(bowl["R"])
	var cy: float = float(bowl["cy"])
	var xz2: float = x * x + z * z
	if xz2 >= R * R:
		return cy
	return maxf(0.0, cy - sqrt(maxf(0.0, R * R - xz2)))


func _sphere_substrate_voxel_ok(x: float, y: float, z: float, margin: float) -> bool:
	# Fill each XZ column from the curved bowl floor up to the opening plane (cy).
	var bowl: Dictionary = _sphere_bowl_params()
	if bowl.is_empty():
		return false
	var R: float = float(bowl["R"]) - margin - 0.14
	var cy: float = float(bowl["cy"])
	var floor_y: float = _sphere_substrate_column_floor(x, z, bowl) - margin * 0.35
	if y < floor_y - TerrainVoxelGrid.CELL_SIZE * 0.45 or y > cy + 0.02:
		return false
	var r_max: float = _bowl_ring_radius(R, cy, y)
	if y < cy - 0.05:
		var dy_below: float = cy - y
		if dy_below > R:
			return false
		r_max = minf(r_max, sqrt(maxf(0.0, R * R - dy_below * dy_below)))
	return x * x + z * z <= r_max * r_max


func _build_substrate() -> void:
	_substrate_container = Node3D.new()
	_substrate_container.name = "Substrate"
	add_child(_substrate_container)

	terrain_grid = TerrainVoxelGrid.new()
	var voxel_size: float = TerrainVoxelGrid.CELL_SIZE
	var ext: Vector2 = _footprint().bounding_half_extents(voxel_size * 0.15)
	var grid_hw: float = TANK_HALF_W
	var grid_hd: float = TANK_HALF_D
	var floor_y: float = 0.0
	var top_y: float = SUBSTRATE_DEPTH
	if TANK_SHAPE == "sphere":
		var bowl: Dictionary = _sphere_bowl_params()
		if not bowl.is_empty():
			var build_rad: float = float(bowl["R"]) - 0.12
			ext = Vector2(build_rad, build_rad)
			grid_hw = build_rad
			grid_hd = build_rad
			top_y = float(bowl["cy"])
			floor_y = top_y - float(bowl["R"]) + 0.08
	elif TANK_SHAPE == "cylinder":
		var grid_r: float = _footprint().effective_radius(0.12)
		ext = Vector2(grid_r, grid_r)
		grid_hw = grid_r
		grid_hd = grid_r
	var default_cap: int = TerrainVoxelGrid.CellMaterial.AQUASOIL
	var cfg := _cfg_node if _cfg_node != null else get_node_or_null("/root/TankConfig")
	if cfg != null:
		default_cap = TerrainVoxelGrid.material_from_substrate_type(String(cfg.substrate_type))

	terrain_grid.configure(grid_hw, grid_hd, top_y, ext.x, ext.y, floor_y)
	var bowl_params: Dictionary = _sphere_bowl_params() if TANK_SHAPE == "sphere" else {}
	terrain_grid.populate_initial(
		func(x: float, y: float, z: float, margin: float) -> bool:
			return _substrate_voxel_ok(x, y, z, margin),
		default_cap,
		_rng,
		TANK_SHAPE,
		bowl_params,
	)
	# Apply per-scenario terrain relief: digs divots, places extra
	# substrate piles to suggest hills, all keyed by `terrain_relief`
	# entries on the active tank preset. Hills use `place_brush` which
	# stacks cells above the cap, then settle_gravity packs them.
	_apply_scenario_terrain_relief(default_cap)
	rebuild_substrate_mesh()


# Sculpt the substrate bed based on the active scenario's
# `terrain_relief` entries. Each entry is `{x, z, radius, mode}` where
# x/z are FRACTIONS of half-extents (-1..1), radius is in cells, and
# mode is "dig" (lower the surface) or "raise" (stack cells higher).
func _apply_scenario_terrain_relief(default_cap: int) -> void:
	var cfg := _cfg_node if _cfg_node != null else get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
	var preset: Dictionary = cfg.current_tank_preset()
	var relief: Array = preset.get("terrain_relief", [])
	if relief.is_empty():
		return
	var voxel_ok: Callable = func(x: float, y: float, z: float, margin: float) -> bool:
		return _substrate_voxel_ok(x, y, z, margin)
	for entry_v in relief:
		if not (entry_v is Dictionary):
			continue
		var entry: Dictionary = entry_v
		var fx: float = clampf(float(entry.get("x", 0.0)), -1.0, 1.0)
		var fz: float = clampf(float(entry.get("z", 0.0)), -1.0, 1.0)
		var radius_cells: int = clampi(int(entry.get("radius", 2)), 1, 8)
		var mode: String = String(entry.get("mode", "raise"))
		# Translate fractional coords to world XZ. Half-extents pulled
		# from the live tank — works for box / cube / hex / cylinder
		# / sphere (sphere just shrinks the active radius itself).
		var wx: float = fx * TANK_HALF_W * 0.7
		var wz: float = fz * TANK_HALF_D * 0.7
		if mode == "dig":
			terrain_grid.dig_brush(wx, wz, radius_cells)
		else:
			# "raise": stack additional cells on top of the existing
			# column. Real hills should taper, so we do a smaller
			# second pass at the centre.
			terrain_grid.place_brush(wx, wz, radius_cells, default_cap, voxel_ok)
			terrain_grid.place_brush(wx, wz, maxi(1, radius_cells - 2),
				default_cap, voxel_ok)
	# Let any unstable stacked cells settle into a natural slope.
	terrain_grid.settle_gravity(voxel_ok)


func rebuild_substrate_mesh() -> void:
	if terrain_grid == null or _substrate_container == null:
		return
	for child in _substrate_container.get_children():
		child.queue_free()
	var voxel_size: float = TerrainVoxelGrid.CELL_SIZE
	var buckets: Dictionary = terrain_grid.build_render_buckets(
		SUBSTRATE_DEPTH,
		2,
		func(x: float, y: float, z: float, margin: float) -> bool:
			return _terrain_cell_ok(x, y, z, margin),
	)
	var box_mesh: BoxMesh = VoxelMat.get_box(Vector3(voxel_size, voxel_size, voxel_size))
	for b_key in buckets:
		var bucket: Dictionary = buckets[b_key]
		var positions: Array = bucket["transforms"]
		if positions.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = box_mesh
		mm.instance_count = positions.size()
		mm.visible_instance_count = positions.size()
		for i in positions.size():
			var t := Transform3D()
			t.origin = positions[i]
			# Guard: skip non-finite origins (shouldn't happen with terrain grid
			# arithmetic, but saves a console flood if a cell_center goes bad).
			if not t.is_finite():
				push_warning("rebuild_substrate_mesh: non-finite origin at index %d, skipping." % i)
				continue
			mm.set_instance_transform(i, t)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		# Substrate voxels are small; default MultiMesh AABB can frustum-cull rows.
		mmi.custom_aabb = AABB(
			Vector3(-TANK_HALF_W - 1.0, -0.5, -TANK_HALF_D - 1.0),
			Vector3(TANK_HALF_W * 2.0 + 2.0, WATER_HEIGHT + 1.0, TANK_HALF_D * 2.0 + 2.0),
		)
		var mat: ShaderMaterial
		var mat_id: int = int(bucket.get("material_id", 0))
		if bucket["caustic"]:
			mat = VoxelMat.make_substrate_caustic(bucket["color"], mat_id)
		else:
			mat = VoxelMat.make_substrate_opaque(bucket["color"], mat_id)
		mmi.material_override = mat
		_substrate_container.add_child(mmi)
	if substrate_grid != null:
		terrain_grid.sync_nutrients_to_substrate(substrate_grid)


func column_surface_y(x: float, z: float) -> float:
	if terrain_grid != null:
		return terrain_grid.surface_y_at(x, z)
	return SUBSTRATE_DEPTH


func floor_at(x: float, z: float) -> Vector3:
	return Vector3(x, column_surface_y(x, z), z)


func spawn_position_on_floor(x: float, z: float, y_offset: float = 0.0) -> Vector3:
	var margin: float = 0.28
	var floor_y: float = column_surface_y(x, z)
	var xz: Vector2 = _footprint().clamp_inside(x, z, margin, floor_y)
	floor_y = column_surface_y(xz.x, xz.y)
	return clamp_xyz_in_tank(Vector3(xz.x, floor_y + y_offset, xz.y), margin, 0.08)


func _terrain_sculpt_ok() -> Callable:
	return func(px: float, py: float, pz: float, margin: float) -> bool:
		return _sculpt_voxel_ok(px, py, pz, margin)


func terrain_place_tool(x: float, z: float, tool: String) -> Dictionary:
	if terrain_grid == null or not TerrainVoxelGrid.tool_is_terrain(tool):
		return {}
	var mat: int = TerrainVoxelGrid.material_from_tool(tool)
	var sculpt_ok: Callable = _terrain_sculpt_ok()
	var undo: Dictionary = terrain_grid.place_at_column(x, z, mat, sculpt_ok)
	if not undo.is_empty() and TerrainVoxelGrid.is_fallable(mat):
		terrain_grid.settle_gravity(sculpt_ok)
	return undo


func terrain_place_brush(x: float, z: float, radius_cells: int, tool: String) -> Array:
	if terrain_grid == null or not TerrainVoxelGrid.tool_is_terrain(tool):
		return []
	var mat: int = TerrainVoxelGrid.material_from_tool(tool)
	var sculpt_ok: Callable = _terrain_sculpt_ok()
	var undos: Array = terrain_grid.place_brush(x, z, radius_cells, mat, sculpt_ok)
	if not undos.is_empty() and TerrainVoxelGrid.is_fallable(mat):
		terrain_grid.settle_gravity(sculpt_ok)
	return undos


func terrain_dig(x: float, z: float) -> Dictionary:
	if terrain_grid == null:
		return {}
	var undo: Dictionary = terrain_grid.dig_at_column(x, z)
	if not undo.is_empty():
		terrain_grid.settle_gravity(_terrain_sculpt_ok())
	return undo


func terrain_dig_brush(x: float, z: float, radius_cells: int) -> Array:
	if terrain_grid == null:
		return []
	var undos: Array = terrain_grid.dig_brush(x, z, radius_cells)
	if not undos.is_empty():
		terrain_grid.settle_gravity(_terrain_sculpt_ok())
	return undos


func terrain_restore_cell(rec: Dictionary) -> void:
	if terrain_grid == null:
		return
	terrain_grid.restore_cell(rec)


func terrain_to_save_dict() -> Dictionary:
	if terrain_grid == null:
		return {}
	return terrain_grid.to_save_dict()


func terrain_apply_save_dict(d: Dictionary) -> bool:
	if terrain_grid == null or d.is_empty():
		return false
	var ok: bool = terrain_grid.apply_save_dict(d)
	if ok:
		rebuild_substrate_mesh()
	return ok


func sync_terrain_nutrients() -> void:
	if terrain_grid == null or substrate_grid == null:
		return
	terrain_grid.sync_nutrients_to_substrate(substrate_grid)
	var peat_n: int = terrain_grid.count_exposed_peat()
	if peat_n > 0:
		tannins = clampf(tannins + float(peat_n) * 0.000002, 0.0, 1.0)


func _build_hardscape(populate: bool = true) -> void:
	var c := Node3D.new()
	c.name = "Hardscape"
	add_child(c)
	_hardscape_occupancy.clear()
	# Empty / guided tanks start with no procedural hardscape - the player
	# sculpts their own. We still create the (empty) Hardscape container so
	# fry-hide behavior and aquascape placement have a parent to attach to.
	if not populate:
		return

	# Read the scenario's hardscape style + density knobs from the active
	# preset. Defaults reproduce the legacy "default" layout (bezier
	# driftwood + Iwagumi stones + pebbles).
	var hs_style: String = "default"
	var hs_driftwood_mult: float = 1.0
	var hs_stones_mult: float = 1.0
	var hs_pebbles_mult: float = 1.0
	var cfg_hs := _cfg_node if _cfg_node != null else get_node_or_null("/root/TankConfig")
	if cfg_hs != null:
		var preset_hs: Dictionary = cfg_hs.current_tank_preset()
		hs_style = String(preset_hs.get("hardscape_style", "default"))
	match hs_style:
		"iwagumi":
			hs_driftwood_mult = 0.0   # no wood — stones tell the story
			hs_stones_mult = 1.0
			hs_pebbles_mult = 1.5
		"blackwater_heavy_wood":
			hs_driftwood_mult = 1.6   # thick tangle dominates
			hs_stones_mult = 0.35
			hs_pebbles_mult = 0.3
		"boulder_field":
			hs_driftwood_mult = 0.0   # rock plateaus only
			hs_stones_mult = 1.6
			hs_pebbles_mult = 1.4
		"polyp_jar":
			hs_driftwood_mult = 0.35  # one short stub
			hs_stones_mult = 0.40
			hs_pebbles_mult = 0.5
		"predator_corners":
			hs_driftwood_mult = 0.55  # corners get small piles
			hs_stones_mult = 0.9
			hs_pebbles_mult = 0.4
		"twin_logs":
			hs_driftwood_mult = 1.25
			hs_stones_mult = 0.55
			hs_pebbles_mult = 0.5
		_:
			pass  # default

	var add_hardscape_cube: Callable = func(center: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
		var fit: Vector2 = _fit_xz_inside_tank(center.x, center.z, 0.2)
		var p: Vector3 = Vector3(fit.x, center.y, fit.y)
		# Keep hardscape inside the active water volume.
		p.y = clampf(p.y, SUBSTRATE_DEPTH - 0.25, WATER_HEIGHT - 0.35)
		if not is_inside_tank_volume(p.x, p.y, p.z, 0.2):
			return null
		var mi := _add_cube(c, p, size, mat)
		_mark_hardscape_occupancy(p, size)
		return mi

	# 1. Procedural Driftwood Spline (Bezier Curve)
	var bezier: Callable = func(c0: Vector3, c1: Vector3, c2: Vector3, c3: Vector3, t: float) -> Vector3:
		var q0 := c0.lerp(c1, t)
		var q1 := c1.lerp(c2, t)
		var q2 := c2.lerp(c3, t)
		var r0 := q0.lerp(q1, t)
		var r1 := q1.lerp(q2, t)
		return r0.lerp(r1, t)

	var p0 := Vector3(-TANK_HALF_W * 0.8, SUBSTRATE_DEPTH - 0.25, -TANK_HALF_D * 0.4)
	var p1 := Vector3(-TANK_HALF_W * 0.4, SUBSTRATE_DEPTH + 1.25, TANK_HALF_D * 0.2)
	var p2 := Vector3(TANK_HALF_W * 0.1, SUBSTRATE_DEPTH + 1.55, TANK_HALF_D * 0.3)
	var p3 := Vector3(TANK_HALF_W * 0.65, SUBSTRATE_DEPTH + 0.05, -TANK_HALF_D * 0.2)

	var mat_dark := VoxelMat.make_substrate_caustic(C_DRIFTWOOD_DARK)
	var mat_light := VoxelMat.make_substrate_caustic(C_DRIFTWOOD_LIGHT)
	
	_driftwood_voxels.clear()
	_rock_voxels.clear()

	# Main Trunk — number of steps scales with the driftwood multiplier
	# so scenarios can ship a chunkier tangle (blackwater) or a thin
	# stub (polyp jar) without rewriting the bezier. Iwagumi /
	# boulder_field skip the wood entirely (multiplier=0).
	var build_driftwood: bool = hs_driftwood_mult > 0.001
	var steps := int(round(80.0 * hs_driftwood_mult)) if build_driftwood else 0
	for s in (range(steps + 1) if build_driftwood else []):
		var t := float(s) / float(steps)
		var p: Vector3 = bezier.call(p0, p1, p2, p3, t)
		var size := lerpf(0.62, 0.25, t)
		
		# Spawn dark wood core voxel
		var mi_d: MeshInstance3D = add_hardscape_cube.call(p, Vector3(size, size, size), mat_dark)
		if mi_d != null:
			_driftwood_voxels.append(mi_d)
		
		# Calculate curve tangent for bark accent alignment
		var next_t := minf(t + 0.01, 1.0)
		var prev_t := maxf(t - 0.01, 0.0)
		var tangent: Vector3 = (bezier.call(p0, p1, p2, p3, next_t) - bezier.call(p0, p1, p2, p3, prev_t)).normalized()
		
		# Find orthogonal normal vector in XZ plane
		var normal: Vector3 = Vector3(-tangent.z, 0.0, tangent.x).normalized()
		if normal.length_squared() < 0.1:
			normal = Vector3.BACK
		
		# Spawn light wood bark accent voxels on side walls perpendicular to growth
		for dx in [-1, 1]:
			var offset: Vector3 = Vector3(0.0, size * 0.4, 0.0) + normal * dx * size * 0.38
			var mi_l: MeshInstance3D = add_hardscape_cube.call(
				p + offset, Vector3(size * 0.58, size * 0.58, size * 0.58), mat_light)
			if mi_l != null:
				_driftwood_voxels.append(mi_l)

	# Side Twigs — only when we actually built a main trunk above.
	var twig_configs: Array = []
	if build_driftwood:
		twig_configs = [
			{"t_start": 0.28, "length": 7, "angle_y": -0.65, "angle_z": 0.45, "scale_mult": 0.55},
			{"t_start": 0.52, "length": 6, "angle_y": 0.85, "angle_z": 0.55, "scale_mult": 0.50},
			{"t_start": 0.74, "length": 5, "angle_y": -0.35, "angle_z": 0.65, "scale_mult": 0.45}
		]

	for tc in twig_configs:
		var t_start: float = tc["t_start"]
		var p_start: Vector3 = bezier.call(p0, p1, p2, p3, t_start)
		var size_start: float = lerpf(0.62, 0.25, t_start) * tc["scale_mult"]
		
		# Get tangent and normal to decide branch direction
		var next_t := minf(t_start + 0.01, 1.0)
		var prev_t := maxf(t_start - 0.01, 0.0)
		var tangent: Vector3 = (bezier.call(p0, p1, p2, p3, next_t) - bezier.call(p0, p1, p2, p3, prev_t)).normalized()
		var normal: Vector3 = Vector3(-tangent.z, 0.0, tangent.x).normalized()
		if normal.length_squared() < 0.1:
			normal = Vector3.BACK
		
		var twig_dir: Vector3 = (tangent.rotated(Vector3.UP, tc["angle_y"]) + Vector3.UP * tc["angle_z"]).normalized()
		
		var twig_p: Vector3 = p_start
		var twig_len: int = tc["length"]
		for j in twig_len:
			var jt := float(j) / float(twig_len - 1)
			var size := lerpf(size_start, 0.15, jt)
			
			var step_offset: Vector3 = twig_dir * 0.26
			step_offset += Vector3(sin(float(j) * 1.5) * 0.04, cos(float(j) * 1.2) * 0.03, sin(float(j) * 0.8) * 0.04)
			twig_p += step_offset
			
			var mi_d: MeshInstance3D = add_hardscape_cube.call(
				twig_p, Vector3(size, size, size), mat_dark)
			if mi_d != null:
				_driftwood_voxels.append(mi_d)
			
			if size > 0.22:
				var mi_l: MeshInstance3D = add_hardscape_cube.call(
					twig_p + Vector3(0.0, size * 0.42, 0.0),
					Vector3(size * 0.58, size * 0.58, size * 0.58), mat_light)
				if mi_l != null:
					_driftwood_voxels.append(mi_l)

	# 2. Japanese Iwagumi Rock Clusters
	# Multiplier gates how aggressive the stone work is: boulder_field
	# scales up, polyp_jar/spartan scales down, predator_corners
	# rearranges into two opposing piles handled below.
	var stone_mat := VoxelMat.make_substrate_caustic(C_STONE_LIGHT)
	var stone_dark := VoxelMat.make_substrate_caustic(C_STONE_DARK)

	var add_rock_voxel: Callable = func(center: Vector3, offset: Vector3, size: Vector3, is_dark: bool, rot: Vector3) -> MeshInstance3D:
		var m := stone_dark if is_dark else stone_mat
		var b_rot := Basis.from_euler(rot)
		var rotated_offset := b_rot * offset
		var mi: MeshInstance3D = add_hardscape_cube.call(center + rotated_offset, size, m)
		if mi == null:
			return null
		mi.basis = b_rot * Basis.from_euler(Vector3(_rng.randf_range(-0.06, 0.06), _rng.randf_range(-0.06, 0.06), _rng.randf_range(-0.06, 0.06)))
		_rock_voxels.append(mi)
		return mi

	# Style-specific rock arrangements. predator_corners replaces the
	# classic Iwagumi with two opposing corner piles; boulder_field
	# adds six small clusters scattered across the floor (cichlid
	# scenario). polyp_jar / spartan keep the classic but scaled down
	# — handled by the hs_stones_mult check below.
	if hs_style == "predator_corners":
		for side in [-1.0, 1.0]:
			var pc := Vector3(TANK_HALF_W * 0.65 * side, SUBSTRATE_DEPTH, TANK_HALF_D * 0.55 * side)
			var pc_tilt := Vector3(0.15 * side, -0.3, 0.2 * side)
			add_rock_voxel.call(pc, Vector3(0.0, -0.08, 0.0), Vector3(1.1, 0.65, 1.1), true, pc_tilt)
			add_rock_voxel.call(pc, Vector3(-0.10 * side, 0.45, 0.0), Vector3(0.85, 0.65, 0.85), false, pc_tilt)
			add_rock_voxel.call(pc, Vector3(-0.20 * side, 0.95, 0.05 * side), Vector3(0.55, 0.55, 0.55), true, pc_tilt)
	elif hs_style == "boulder_field":
		var bf_positions: Array = [
			Vector3(-TANK_HALF_W * 0.55, SUBSTRATE_DEPTH, -TANK_HALF_D * 0.30),
			Vector3( TANK_HALF_W * 0.55, SUBSTRATE_DEPTH,  TANK_HALF_D * 0.30),
			Vector3(-TANK_HALF_W * 0.20, SUBSTRATE_DEPTH,  TANK_HALF_D * 0.60),
			Vector3( TANK_HALF_W * 0.20, SUBSTRATE_DEPTH, -TANK_HALF_D * 0.60),
			Vector3(-TANK_HALF_W * 0.70, SUBSTRATE_DEPTH,  TANK_HALF_D * 0.10),
			Vector3( TANK_HALF_W * 0.65, SUBSTRATE_DEPTH, -TANK_HALF_D * 0.05),
		]
		for bf_i in bf_positions.size():
			var bc: Vector3 = bf_positions[bf_i]
			var bt := Vector3(_rng.randf_range(-0.25, 0.25),
				_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.25, 0.25))
			var bd: bool = (bf_i % 2 == 0)
			add_rock_voxel.call(bc, Vector3(0.0, -0.08, 0.0), Vector3(0.85, 0.55, 0.85), bd, bt)
			add_rock_voxel.call(bc, Vector3(0.0, 0.32, 0.0), Vector3(0.62, 0.55, 0.62), not bd, bt)
			add_rock_voxel.call(bc, Vector3(0.05, 0.72, -0.05), Vector3(0.40, 0.42, 0.40), bd, bt)
	elif hs_stones_mult > 0.01:
		_build_iwagumi_clusters(add_rock_voxel, add_hardscape_cube,
			stone_mat, stone_dark, hs_pebbles_mult)

	# Publish hardscape contact-AO footprints to the substrate shaders.
	# We pick the 8 lowest hardscape voxels (those nearest the substrate
	# surface) as proxy contact points — driftwood/rock that sits ON the
	# sand. Real AO would project from full mesh footprints; this proxy
	# darkens a soft circle on the substrate beneath each anchor, which
	# is the visible cue the player reads ("the wood is resting on the
	# bed, not floating above it"). Radius scaled by voxel size so a
	# wide rock base AOs over a wider patch than a thin twig.
	_publish_substrate_contact_ao()
	# Publish the filter intake position as the flow-origin so the
	# substrate_caustic ripple-deepening kicks in. sim.filter_intake_pos
	# is set later in the bootstrap flow, so we publish a zero-gain
	# default now and let sim_driver re-publish when it's ready.
	VoxelMat.update_substrate_flow_origin(Vector3.ZERO, 0.0)


# Pick up to 8 hardscape voxels closest to the substrate surface and
# publish their xz positions + a radius as contact-AO footprints. Called
# at end of _build_hardscape; safe to call again if hardscape changes.
func _publish_substrate_contact_ao() -> void:
	# Score = how close the voxel sits to substrate top; lower is better.
	var pool: Array = []
	for mi in _driftwood_voxels:
		if not is_instance_valid(mi):
			continue
		var p: Vector3 = mi.position
		# Only voxels within 0.4 m of the substrate top count as "contact" —
		# anything higher is mid-trunk wood and shouldn't cast AO down.
		if p.y > SUBSTRATE_DEPTH + 0.40:
			continue
		var bm := mi.mesh as BoxMesh
		var size: float = 0.5
		if bm != null:
			size = (bm.size.x + bm.size.z) * 0.5
		pool.append({"y": p.y, "x": p.x, "z": p.z, "r": maxf(size * 1.4, 0.45)})
	for mi in _rock_voxels:
		if not is_instance_valid(mi):
			continue
		var p: Vector3 = mi.position
		if p.y > SUBSTRATE_DEPTH + 0.45:
			continue
		var bm := mi.mesh as BoxMesh
		var size: float = 0.6
		if bm != null:
			size = (bm.size.x + bm.size.z) * 0.5
		pool.append({"y": p.y, "x": p.x, "z": p.z, "r": maxf(size * 1.5, 0.55)})
	pool.sort_custom(func(a, b): return a["y"] < b["y"])
	var pts: Array = []
	for i in mini(8, pool.size()):
		var e = pool[i]
		pts.append(Vector4(e["x"], e["y"], e["z"], e["r"]))
	VoxelMat.update_substrate_contact_ao(pts)


# Original three-island Iwagumi (Oyaishi / Fukuishi / Soishi) + pebble
# accents. Pulled into a helper so style branches can opt out cleanly.
# `add_rock_voxel` and `add_hardscape_cube` are closures captured from
# _build_hardscape; we pass them in rather than redeclaring globally.
func _build_iwagumi_clusters(add_rock_voxel: Callable,
		add_hardscape_cube: Callable,
		stone_mat: Material, stone_dark: Material, pebbles_mult: float) -> void:
	# --- Main Island (Right side, off-center) ---
	var right_center := Vector3(TANK_HALF_W * 0.45, SUBSTRATE_DEPTH, TANK_HALF_D * 0.10)
	var right_tilt := Vector3(0.2, -0.3, 0.35)
	# Oyaishi (Main Stone)
	add_rock_voxel.call(right_center, Vector3(0.0, -0.1, 0.0), Vector3(1.3, 0.8, 1.3), true, right_tilt)
	add_rock_voxel.call(right_center, Vector3(-0.15, 0.5, 0.1), Vector3(1.1, 0.8, 1.1), false, right_tilt)
	add_rock_voxel.call(right_center, Vector3(-0.3, 1.1, -0.05), Vector3(0.85, 0.9, 0.85), true, right_tilt)
	add_rock_voxel.call(right_center, Vector3(-0.45, 1.7, -0.1), Vector3(0.55, 0.65, 0.55), false, right_tilt)
	add_rock_voxel.call(right_center, Vector3(0.45, 0.1, -0.35), Vector3(0.7, 0.6, 0.7), false, right_tilt)
	add_rock_voxel.call(right_center, Vector3(-0.45, 0.25, 0.35), Vector3(0.6, 0.7, 0.6), true, right_tilt)

	# Fukuishi (Secondary Stone)
	var fuku_center := Vector3(TANK_HALF_W * 0.60, SUBSTRATE_DEPTH, TANK_HALF_D * 0.01)
	var fuku_tilt := Vector3(0.15, -0.25, 0.3)
	add_rock_voxel.call(fuku_center, Vector3(0.0, -0.1, 0.0), Vector3(0.9, 0.7, 0.9), false, fuku_tilt)
	add_rock_voxel.call(fuku_center, Vector3(-0.1, 0.45, 0.08), Vector3(0.75, 0.75, 0.75), true, fuku_tilt)
	add_rock_voxel.call(fuku_center, Vector3(-0.2, 0.95, 0.0), Vector3(0.5, 0.6, 0.5), false, fuku_tilt)
	add_rock_voxel.call(fuku_center, Vector3(0.28, 0.1, 0.22), Vector3(0.5, 0.55, 0.5), true, fuku_tilt)

	# Soishi (Tertiary Stone)
	var soishi_center := Vector3(TANK_HALF_W * 0.31, SUBSTRATE_DEPTH, TANK_HALF_D * 0.19)
	var soishi_tilt := Vector3(0.25, -0.4, 0.1)
	add_rock_voxel.call(soishi_center, Vector3(0.0, -0.08, 0.0), Vector3(0.68, 0.58, 0.68), true, soishi_tilt)
	add_rock_voxel.call(soishi_center, Vector3(0.08, 0.35, -0.08), Vector3(0.5, 0.5, 0.5), false, soishi_tilt)
	add_rock_voxel.call(soishi_center, Vector3(-0.18, 0.05, 0.18), Vector3(0.42, 0.42, 0.42), true, soishi_tilt)

	# Suteishi (Accents)
	var pebble_positions := [
		Vector3(TANK_HALF_W * 0.24, SUBSTRATE_DEPTH - 0.08, TANK_HALF_D * 0.29),
		Vector3(TANK_HALF_W * 0.39, SUBSTRATE_DEPTH - 0.08, -TANK_HALF_D * 0.11),
		Vector3(TANK_HALF_W * 0.64, SUBSTRATE_DEPTH - 0.08, TANK_HALF_D * 0.21),
	]
	var pebble_sizes := [0.45, 0.38, 0.42]
	var pebble_rots := [Vector3(0.12, 1.4, -0.15), Vector3(-0.25, 0.4, 0.18), Vector3(0.3, -0.8, -0.22)]
	var pebble_n: int = clampi(int(round(pebble_positions.size() * pebbles_mult)),
		0, pebble_positions.size())
	for i in pebble_n:
		var mi: MeshInstance3D = add_hardscape_cube.call(
			pebble_positions[i], Vector3(pebble_sizes[i], pebble_sizes[i], pebble_sizes[i]),
			stone_dark if (i & 1) == 0 else stone_mat)
		if mi != null:
			mi.rotation = pebble_rots[i]

	# --- Secondary Island (Left side, balancing) ---
	var left_center := Vector3(-TANK_HALF_W * 0.69, SUBSTRATE_DEPTH, TANK_HALF_D * 0.15)
	var left_tilt := Vector3(0.12, 0.3, -0.28)
	# Left Fukuishi
	add_rock_voxel.call(left_center, Vector3(0.0, -0.08, 0.0), Vector3(0.85, 0.68, 0.85), false, left_tilt)
	add_rock_voxel.call(left_center, Vector3(0.08, 0.4, -0.08), Vector3(0.68, 0.68, 0.68), true, left_tilt)
	add_rock_voxel.call(left_center, Vector3(0.15, 0.82, 0.0), Vector3(0.48, 0.55, 0.48), false, left_tilt)

	# Left Soishi
	var left_soishi := Vector3(-TANK_HALF_W * 0.55, SUBSTRATE_DEPTH, TANK_HALF_D * 0.06)
	var left_soishi_tilt := Vector3(0.2, 0.25, -0.12)
	add_rock_voxel.call(left_soishi, Vector3(0.0, -0.08, 0.0), Vector3(0.62, 0.52, 0.62), true, left_soishi_tilt)
	add_rock_voxel.call(left_soishi, Vector3(0.06, 0.32, 0.06), Vector3(0.45, 0.45, 0.45), false, left_soishi_tilt)

	# Left Suteishi (Accents)
	var left_pebbles := [
		Vector3(-TANK_HALF_W * 0.77, SUBSTRATE_DEPTH - 0.08, TANK_HALF_D * 0.24),
		Vector3(-TANK_HALF_W * 0.48, SUBSTRATE_DEPTH - 0.08, TANK_HALF_D * 0.11),
		Vector3(-TANK_HALF_W * 0.61, SUBSTRATE_DEPTH - 0.08, -TANK_HALF_D * 0.09),
	]
	var left_pebble_n: int = clampi(int(round(left_pebbles.size() * pebbles_mult)),
		0, left_pebbles.size())
	for i in left_pebble_n:
		var mi: MeshInstance3D = add_hardscape_cube.call(
			left_pebbles[i], Vector3(0.40, 0.40, 0.40),
			stone_mat if (i & 1) == 0 else stone_dark)
		if mi != null:
			mi.rotation = Vector3(
				_rng.randf_range(-0.3, 0.3), _rng.randf_range(0, PI),
				_rng.randf_range(-0.3, 0.3))


func _build_water_volume() -> void:
	match TANK_SHAPE:
		"cylinder":
			_build_cylinder_water()
			return
		"sphere":
			_build_sphere_water()
			return
	# Water volume as a polygon prism extruded from the tank footprint. The
	# old version was a fixed BoxMesh which poked through hex/triangle glass
	# walls and visibly broke the illusion of a non-rectangular tank.
	#
	# The mesh is generated from _tank_footprint_corners(): we shrink the
	# polygon by INSET so the water sits snugly inside the glass, then build
	# a closed prism (top cap + bottom cap + side quads) with outward normals.
	const INSET: float = 0.1
	var corners: Array[Vector3] = _tank_footprint_corners()
	var n: int = corners.size()
	if n < 3:
		return
	# Compute polygon centroid; we'll use it to shrink each corner inward.
	var cen: Vector3 = Vector3.ZERO
	for c in corners:
		cen += c
	cen /= float(n)
	var inset_corners: Array[Vector3] = []
	for c in corners:
		var dir: Vector3 = c - cen
		var d: float = dir.length()
		if d > INSET * 1.05:
			dir = dir.normalized() * (d - INSET)
		inset_corners.append(cen + dir)

	var y_bot: float = SUBSTRATE_DEPTH
	var y_top: float = WATER_HEIGHT
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Top cap (triangle fan from centroid, normal +Y so it's visible from
	# above the tank).
	for i in n:
		var a: Vector3 = inset_corners[i]
		var b: Vector3 = inset_corners[(i + 1) % n]
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(cen.x, y_top, cen.z))
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(a.x, y_top, a.z))
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(b.x, y_top, b.z))

	# Bottom cap (triangle fan, normal -Y - faces down so it's hidden inside
	# the substrate but still part of the closed volume).
	for i in n:
		var a: Vector3 = inset_corners[i]
		var b: Vector3 = inset_corners[(i + 1) % n]
		st.set_normal(Vector3.DOWN)
		st.add_vertex(Vector3(cen.x, y_bot, cen.z))
		st.set_normal(Vector3.DOWN)
		st.add_vertex(Vector3(b.x, y_bot, b.z))
		st.set_normal(Vector3.DOWN)
		st.add_vertex(Vector3(a.x, y_bot, a.z))

	# Side walls: one quad per edge, outward normal (away from centroid).
	for i in n:
		var a: Vector3 = inset_corners[i]
		var b: Vector3 = inset_corners[(i + 1) % n]
		# Outward normal: vector from centroid to edge midpoint, projected
		# onto the XZ plane. Always points outward regardless of corner
		# winding order so this code is robust across tank shapes.
		var mid: Vector3 = (a + b) * 0.5
		var out_n: Vector3 = Vector3(mid.x - cen.x, 0, mid.z - cen.z).normalized()
		# Two triangles per quad. Wind CCW when viewed from outside.
		st.set_normal(out_n)
		st.add_vertex(Vector3(a.x, y_bot, a.z))
		st.set_normal(out_n)
		st.add_vertex(Vector3(b.x, y_bot, b.z))
		st.set_normal(out_n)
		st.add_vertex(Vector3(b.x, y_top, b.z))
		st.set_normal(out_n)
		st.add_vertex(Vector3(a.x, y_bot, a.z))
		st.set_normal(out_n)
		st.add_vertex(Vector3(b.x, y_top, b.z))
		st.set_normal(out_n)
		st.add_vertex(Vector3(a.x, y_top, a.z))

	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = st.commit()
	_water_material_ref = _water_mat()
	water.material_override = _water_material_ref
	_water_mesh = water
	add_child(water)


func _build_cylinder_water() -> void:
	var rad: float = _footprint().effective_radius(0.12)
	var depth: float = maxf(0.2, WATER_HEIGHT - SUBSTRATE_DEPTH)
	var cyl := CylinderMesh.new()
	cyl.top_radius = rad
	cyl.bottom_radius = rad
	cyl.height = depth
	cyl.radial_segments = 32
	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = cyl
	_water_material_ref = _water_mat()
	water.material_override = _water_material_ref
	_water_mesh = water
	add_child(water)
	water.position = Vector3(0.0, SUBSTRATE_DEPTH + depth * 0.5, 0.0)


func _build_sphere_water() -> void:
	var bowl: Dictionary = _sphere_bowl_params()
	var mesh: ArrayMesh = _build_sphere_bowl_mesh(
		bowl, bowl["y_water"], 0.14, 32, 22, true, false)
	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = mesh
	_water_material_ref = _water_mat()
	water.material_override = _water_material_ref
	_water_mesh = water
	add_child(water)


func _build_glass() -> void:
	var c := Node3D.new()
	c.name = "Glass"
	add_child(c)
	var glass := _glass_mat()
	match TANK_SHAPE:
		"cylinder":
			_build_cylinder_glass(c, glass)
			return
		"sphere":
			_build_sphere_glass(c, glass)
			return
	# Build a polygon of glass walls around the tank's footprint. The
	# footprint is approximated as N corner points; each adjacent pair is
	# connected by a thin wall mesh.
	var corners: Array[Vector3] = _tank_footprint_corners()
	for i in corners.size():
		var p1: Vector3 = corners[i]
		var p2: Vector3 = corners[(i + 1) % corners.size()]
		_add_wall_between(c, p1, p2, TANK_HEIGHT, glass)


func _tank_footprint_corners() -> Array[Vector3]:
	return _footprint().footprint_corners()


func _add_wall_between(parent: Node3D, p1: Vector3, p2: Vector3,
		height: float, mat: Material) -> void:
	var length: float = p1.distance_to(p2)
	if length < 0.01:
		return
	var mid: Vector3 = (p1 + p2) * 0.5
	mid.y = height * 0.5
	var wall := MeshInstance3D.new()
	wall.mesh = VoxelMat.get_box(Vector3(length, height, 0.1))
	wall.material_override = mat
	parent.add_child(wall)
	wall.global_position = mid
	# Rotate so the wall's local +X axis lies along (p1 -> p2).
	wall.rotation.y = -atan2(p2.z - p1.z, p2.x - p1.x)


func _sphere_bowl_params() -> Dictionary:
	var fp := _footprint()
	var opening: float = fp.effective_radius(0.06)
	var dy_w: float = maxf(0.05, WATER_HEIGHT - SUBSTRATE_DEPTH)
	var R: float = sqrt(opening * opening + dy_w * dy_w)
	return {
		"R": R,
		"opening": opening,
		"cy": SUBSTRATE_DEPTH,
		"y_sub": SUBSTRATE_DEPTH,
		"y_water": WATER_HEIGHT,
	}


func _bowl_ring_radius(R: float, cy: float, y: float) -> float:
	var dy: float = maxf(0.0, y - cy)
	return sqrt(maxf(0.0, R * R - dy * dy))


func _build_sphere_bowl_mesh(bowl: Dictionary, y_top: float, inset: float,
		segs: int, rings: int, cap_bottom: bool, add_rim: bool) -> ArrayMesh:
	var R: float = float(bowl["R"]) - inset
	var cy: float = float(bowl["cy"])
	var y_bot: float = float(bowl["y_sub"]) + inset * 0.5
	y_top = maxf(y_bot + 0.05, y_top - inset * 0.35)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for ri in rings:
		var t_a: float = float(ri) / float(rings)
		var t_b: float = float(ri + 1) / float(rings)
		var y_a: float = lerpf(y_bot, y_top, t_a)
		var y_b: float = lerpf(y_bot, y_top, t_b)
		var r_a: float = _bowl_ring_radius(R, cy, y_a)
		var r_b: float = _bowl_ring_radius(R, cy, y_b)
		for si in segs:
			var ang_a: float = (float(si) / float(segs)) * TAU
			var ang_b: float = (float(si + 1) / float(segs)) * TAU
			var pa := Vector3(cos(ang_a) * r_a, y_a, sin(ang_a) * r_a)
			var pb := Vector3(cos(ang_b) * r_a, y_a, sin(ang_b) * r_a)
			var pc := Vector3(cos(ang_b) * r_b, y_b, sin(ang_b) * r_b)
			var pd := Vector3(cos(ang_a) * r_b, y_b, sin(ang_a) * r_b)
			var na: Vector3 = Vector3(pa.x, pa.y - cy, pa.z).normalized()
			var nb: Vector3 = Vector3(pb.x, pb.y - cy, pb.z).normalized()
			var nc: Vector3 = Vector3(pc.x, pc.y - cy, pc.z).normalized()
			var nd: Vector3 = Vector3(pd.x, pd.y - cy, pd.z).normalized()
			st.set_normal(na)
			st.add_vertex(pa)
			st.set_normal(nb)
			st.add_vertex(pb)
			st.set_normal(nc)
			st.add_vertex(pc)
			st.set_normal(na)
			st.add_vertex(pa)
			st.set_normal(nc)
			st.add_vertex(pc)
			st.set_normal(nd)
			st.add_vertex(pd)

	if cap_bottom:
		var r_base: float = _bowl_ring_radius(R, cy, y_bot)
		var cen := Vector3(0.0, y_bot, 0.0)
		for si in segs:
			var ang_a: float = (float(si) / float(segs)) * TAU
			var ang_b: float = (float(si + 1) / float(segs)) * TAU
			var pa := Vector3(cos(ang_a) * r_base, y_bot, sin(ang_a) * r_base)
			var pb := Vector3(cos(ang_b) * r_base, y_bot, sin(ang_b) * r_base)
			st.set_normal(Vector3.DOWN)
			st.add_vertex(cen)
			st.set_normal(Vector3.DOWN)
			st.add_vertex(pb)
			st.set_normal(Vector3.DOWN)
			st.add_vertex(pa)

	if add_rim:
		var y_rim: float = float(bowl["y_water"])
		var r_outer: float = _bowl_ring_radius(R + inset * 0.6, cy, y_rim)
		var r_inner: float = maxf(0.05, r_outer - 0.14)
		for si in segs:
			var ang_a: float = (float(si) / float(segs)) * TAU
			var ang_b: float = (float(si + 1) / float(segs)) * TAU
			var pa_o := Vector3(cos(ang_a) * r_outer, y_rim, sin(ang_a) * r_outer)
			var pb_o := Vector3(cos(ang_b) * r_outer, y_rim, sin(ang_b) * r_outer)
			var pa_i := Vector3(cos(ang_a) * r_inner, y_rim, sin(ang_a) * r_inner)
			var pb_i := Vector3(cos(ang_b) * r_inner, y_rim, sin(ang_b) * r_inner)
			st.set_normal(Vector3.UP)
			st.add_vertex(pa_i)
			st.set_normal(Vector3.UP)
			st.add_vertex(pb_o)
			st.set_normal(Vector3.UP)
			st.add_vertex(pa_o)
			st.set_normal(Vector3.UP)
			st.add_vertex(pa_i)
			st.set_normal(Vector3.UP)
			st.add_vertex(pb_i)
			st.set_normal(Vector3.UP)
			st.add_vertex(pb_o)

	return st.commit()


func _build_cylinder_glass(parent: Node3D, mat: Material) -> void:
	var rad: float = _footprint().effective_radius(0.05)
	var cyl := CylinderMesh.new()
	cyl.top_radius = rad
	cyl.bottom_radius = rad
	cyl.height = TANK_HEIGHT
	cyl.radial_segments = 32
	var wall := MeshInstance3D.new()
	wall.mesh = cyl
	wall.material_override = mat
	parent.add_child(wall)
	wall.position = Vector3(0.0, TANK_HEIGHT * 0.5, 0.0)


func _build_sphere_glass(parent: Node3D, mat: Material) -> void:
	var bowl: Dictionary = _sphere_bowl_params()
	var y_lip: float = float(bowl["y_water"]) + 0.07
	var mesh: ArrayMesh = _build_sphere_bowl_mesh(
		bowl, y_lip, 0.05, 32, 24, false, true)
	var wall := MeshInstance3D.new()
	wall.mesh = mesh
	wall.material_override = mat
	parent.add_child(wall)


# Remove every Snails container immediately. queue_free() leaves a stale empty
# node in the tree for a frame; get_node("Snails") then binds stats/predator
# AI to the dying container while a new populated one sits beside it (HUD 0,
# tank still full).
func _destroy_snails_container() -> void:
	if sim != null:
		sim.snails_root = null
	var doomed: Array[Node] = []
	for child in get_children():
		if child.name == "Snails":
			doomed.append(child)
	for node in doomed:
		remove_child(node)
		node.free()


func _find_snails_container() -> Node3D:
	var best: Node3D = null
	var best_n: int = -1
	for child in get_children():
		if child.name == "Snails" and is_instance_valid(child):
			var n: int = child.get_child_count()
			if n > best_n:
				best_n = n
				best = child as Node3D
	return best


func _build_snails(populate: bool = true) -> Node3D:
	_destroy_snails_container()
	var c := Node3D.new()
	c.name = "Snails"
	add_child(c)
	# Empty / guided tanks get an empty snail container (the player adds
	# snails via the creature creator during the walkthrough).
	if not populate:
		return c
	# Saltwater branches into a marine snail mix (turbo / trochus on the
	# glass, plus nassarius scavengers on the substrate). Freshwater
	# keeps the original purple-leaning founder palette.
	var is_saltwater: bool = not not _active_substrate_profile.get("is_saltwater", false)
	var founder_palette: Array[Color]
	if is_saltwater:
		# Marine palette: pearl whites, sand creams, dark banding.
		founder_palette = [
			Color8(245, 235, 210),   # pearl cream
			Color8(220, 200, 165),   # sand
			Color8(60, 50, 45),      # near-black banding
			Color8(180, 155, 110),   # tan
			Color8(230, 220, 195),   # pale ivory
			Color8(95, 75, 60),      # dark sepia
		]
	else:
		founder_palette = [
			Color8(135, 44, 176),   # classic purple
			Color8(180, 70, 90),    # warm rose
			Color8(80, 100, 180),   # cool blue
			Color8(160, 130, 60),   # amber
			Color8(70, 140, 110),   # teal
			Color8(190, 160, 60),   # ochre
		]
	var positions_and_walls: Array = _snail_founder_layout(is_saltwater)
	for i in positions_and_walls.size():
		var pw = positions_and_walls[i]
		var pos: Vector3 = pw[0]
		var wall_n: Vector3 = pw[1]
		var shape: String = String(pw[2])
		var snail := Node3D.new()
		snail.set_script(load("res://scripts/snail.gd"))
		_configure_snail_node(snail, pos, wall_n, shape, founder_palette, i)
		c.add_child(snail)
		_build_snail_body(snail)
		if sim != null:
			sim.register_snail(snail)
	return c


const SnailShell = preload("res://scripts/snail_shell.gd")


func _build_snail_body(snail: Node3D) -> void:
	# Shell + foot geometry is built by the shared SnailShell module so the
	# live snail and the creature-creator preview render from one source of
	# truth. Eye-stalks are added here (snail.gd animates the named pivot).
	var shell_size: float = float(snail.get("shell_size"))
	var body_v: Variant = snail.get("body_color") if "body_color" in snail else null
	var body_color: Color = body_v if body_v is Color else C_SNAIL_BODY
	var body_mat := _fauna_mat(body_color)
	var g: Dictionary = {
		"shell_color": snail.get("shell_color") if snail.get("shell_color") is Color else Color8(135, 44, 176),
		"shell_accent_color": snail.get("shell_accent_color") if "shell_accent_color" in snail else null,
		"body_color": body_color,
		"shell_size": shell_size,
		"shell_shape": String(snail.get("shell_shape") if "shell_shape" in snail else "turbo"),
		"spire_height": float(snail.get("spire_height")) if "spire_height" in snail else 1.0,
		"whorl_count": int(snail.get("whorl_count")) if "whorl_count" in snail else 4,
		"aperture_flare": float(snail.get("aperture_flare")) if "aperture_flare" in snail else 0.0,
		"operculum": (snail.get("operculum") if "operculum" in snail else false),
		"shell_pattern": int(snail.get("shell_pattern")) if "shell_pattern" in snail else 0,
		"shell_spines": float(snail.get("shell_spines")) if "shell_spines" in snail else 0.0,
		"toxin_level": float(snail.get("toxin_level")) if "toxin_level" in snail else 0.0,
		"generation": int(snail.get("generation")) if "generation" in snail else 0,
	}
	var add_box := func(par: Node3D, pos: Vector3, size: Vector3, col: Color) -> void:
		_add_cube(par, pos, size, _fauna_mat(col))
	SnailShell.build(snail, g, add_box)
	# Eye stalks - wrapped in a named pivot so snail.gd can animate them
	# (slow sway, periodic retraction). Keep size fixed for visibility.
	# Pivot sits at the stalk base so rotation tilts the eyes naturally.
	var eye_stalks := Node3D.new()
	eye_stalks.name = "EyeStalks"
	eye_stalks.position = Vector3(0.10, -0.06 * shell_size, 0)
	snail.add_child(eye_stalks)
	_add_cube(eye_stalks, Vector3(0.0, 0.05 * shell_size, 0.06),
		Vector3(0.03, 0.10 * shell_size, 0.03), body_mat)
	_add_cube(eye_stalks, Vector3(0.0, 0.05 * shell_size, -0.06),
		Vector3(0.03, 0.10 * shell_size, 0.03), body_mat)


# ---- Initial population ----

func _respawn_extinct_fauna() -> void:
	# Called by SimDriver if the auto-respawn toggle is checked and the tank
	# has been completely devoid of fauna for 5 seconds. Rebuilds the current
	# preset but forces a count of 10 for every species.
	var cfg = get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
		
	var stocking: Dictionary = {}
	if cfg.tank_preset == "custom":
		stocking = {
			"glassdart": 10,
			"mudsifter": 10,
			"betta": 10,
			"shrimp": 10
		}
	else:
		var preset: Dictionary = cfg.current_tank_preset()
		stocking = preset.get("stocking", {}).duplicate()
		for key in stocking.keys():
			stocking[key] = 10
			
	if stocking.is_empty():
		stocking = {"glassdart": 10, "mudsifter": 10, "shrimp": 10}

	var phenotype_mult: float = _initial_phenotype_spread()

	# Spawn Fish via _spawn_fish_at — this is the same path the initial
	# population uses, and crucially it calls _apply_water_column_scale on
	# the genome so respawned fish get their preferred_y / home_y_radius
	# rescaled to this tank's water column. The old manual `Fish.new()`
	# path skipped that, so on tall tanks every respawned fish pinned to
	# the bottom (preferred_y was the reference-tank value of ~3.5
	# regardless of actual substrate height).
	for species_name in stocking.keys():
		if species_name == "shrimp" or species_name == "snails":
			continue
		var count: int = int(stocking[species_name])
		if count <= 0:
			continue
		var entry: Dictionary = TankConfig.SPECIES_LIBRARY.get(species_name, {})
		if entry.is_empty():
			continue
		var template: Dictionary = entry.get("genome", {})
		for i in count:
			var g: Dictionary = template.duplicate(true)
			g["sex"] = i % 2
			g["max_age_s"] = float(g.get("max_age_s", 240.0)) + randf_range(-30, 30)
			_apply_initial_phenotype_spread(g, phenotype_mult)
			_apply_founding_cohort_spread(g, i, count)
			_spawn_fish_at(g, _sample_fish_spawn_pos(g))

	# Shrimp: only when the preset stocking dict includes them.
	var is_saltwater: bool = not not _active_substrate_profile.get("is_saltwater", false)
	if _stocking_shrimp_count() > 0:
		if is_saltwater:
			_spawn_marine_shrimp(false)
		elif stocking.has("shrimp"):
			var shrimp_count: int = int(stocking["shrimp"])
			for i in shrimp_count:
				var xz: Vector2 = _sample_clear_xz_in_band(
					-TANK_HALF_D * 0.85, TANK_HALF_D * 0.85, 0.6, 0.45, 36, 0.0, 0.44)
				var sp := clamp_xyz_in_tank(spawn_position_on_floor(xz.x, xz.y, 0.1), 0.3)
				var s := Shrimp.new()
				fauna_root.add_child(s)
				s.global_position = sp
				s.base_color = Color.from_hsv(randf(), randf_range(0.6, 0.9), randf_range(0.5, 0.9))
				s.max_speed = randf_range(0.4, 0.6)
				s.max_age_s = randf_range(120.0, 180.0)
				s.age = randf_range(10.0, 40.0)
				s.maturity = Shrimp.MATURITY_ADULT
				sim.register_shrimp(s)

	sim.snails_root = _build_snails()
	_build_clams()
	_build_trumpet_snails()
	_build_bristle_worms()
	_build_sea_cucumbers()
	if sim.has_method("sync_species_discoveries"):
		sim.sync_species_discoveries()


# Spawn a small starting colony of Malaysian trumpet snails — burrowing
# substrate dwellers that emerge at night. Skipped on saltwater tanks
# (MTS are strictly freshwater).
func _build_trumpet_snails() -> void:
	if _active_substrate_profile.get("is_saltwater", false):
		return
	if sim == null or sim.snails_root == null:
		return
	var count: int = _rng.randi_range(4, 7)
	for i in count:
		var xz: Vector2 = _sample_substrate_xz(0.45, 0.35)
		var pos: Vector3 = spawn_position_on_floor(xz.x, xz.y, 0.04)
		if not is_inside_tank_volume(pos.x, pos.y, pos.z, 0.25):
			continue
		var ts: Node3D = preload("res://scripts/trumpet_snail.gd").new()
		sim.snails_root.add_child(ts)
		ts.global_position = pos
		ts.sim = sim
		ts.substrate_top_y = SUBSTRATE_DEPTH
		# Stagger ages so the colony doesn't synchronously die-off.
		ts._age = _rng.randf_range(0.0, 120.0)


# Spawn pale secretive bristle worms — substrate detritivores that
# emerge mostly at night. Lower count than trumpet snails since they're
# meant to be a rare reveal.
func _build_bristle_worms() -> void:
	if _active_substrate_profile.get("is_saltwater", false):
		# Saltwater bristle worms ARE real (Eunice / Hermodice), but
		# we ship them as part of the saltwater cleanup crew separately.
		# For now, freshwater-only.
		return
	if wriggle_root == null or sim == null:
		return
	var count: int = _rng.randi_range(2, 4)
	for i in count:
		var xz: Vector2 = _sample_substrate_xz(0.45, 0.35)
		var pos: Vector3 = spawn_position_on_floor(xz.x, xz.y, 0.04)
		if not is_inside_tank_volume(pos.x, pos.y, pos.z, 0.25):
			continue
		var bw: Node3D = preload("res://scripts/bristle_worm.gd").new()
		wriggle_root.add_child(bw)
		bw.global_position = pos
		bw.sim = sim
		bw.substrate_top_y = SUBSTRATE_DEPTH
		bw._age = _rng.randf_range(0.0, 60.0)


# Spawn sea cucumbers — slow-moving saltwater floor-sifters. Skipped on
# freshwater tanks.
func _build_sea_cucumbers() -> void:
	if not _active_substrate_profile.get("is_saltwater", false):
		return
	if fauna_root == null or sim == null:
		return
	var count: int = _rng.randi_range(2, 3)
	for i in count:
		var xz: Vector2 = _sample_substrate_xz(0.45, 0.40)
		var pos: Vector3 = spawn_position_on_floor(xz.x, xz.y, 0.05)
		if not is_inside_tank_volume(pos.x, pos.y, pos.z, 0.30):
			continue
		var sc: Node3D = preload("res://scripts/sea_cucumber.gd").new()
		fauna_root.add_child(sc)
		sc.global_position = pos
		sc.sim = sim
		sc.substrate_top_y = SUBSTRATE_DEPTH
		sc._age = _rng.randf_range(0.0, 180.0)


# Spawn a small starting population of freshwater clams. Sessile filter
# feeders parked on the substrate; sim_driver.tick() drives their
# feeding cycle and lifecycle. Skipped on saltwater tanks (we'd want
# saltwater-specific clam art / behavior to do them justice).
func _build_clams() -> void:
	if clams_root == null or sim == null:
		return
	if _active_substrate_profile.get("is_saltwater", false):
		return
	var count: int = _rng.randi_range(3, 6)
	for i in count:
		var band: Vector2 = _spawn_z_band("foreground")
		var xz: Vector2 = _sample_clear_xz_in_band(
			band.x, band.y, 0.35, 0.55, 24, 0.3, 0.40)
		var pos: Vector3 = spawn_position_on_floor(xz.x, xz.y, 0.05)
		if not is_inside_tank_volume(pos.x, pos.y, pos.z, 0.25):
			continue
		var cl: Node = preload("res://scripts/clam.gd").new()
		clams_root.add_child(cl)
		cl.global_position = pos
		# Subtle per-clam variation so a cluster doesn't look like
		# stamped copies. Shell color ranges over tan / olive / chalk.
		var shell_hue: float = _rng.randf_range(0.06, 0.14)
		var sc: Color = Color.from_hsv(
			shell_hue,
			_rng.randf_range(0.18, 0.36),
			_rng.randf_range(0.55, 0.78))
		var bc: Color = Color.from_hsv(
			_rng.randf_range(0.95, 1.05) * 0.04 + 0.95,
			_rng.randf_range(0.22, 0.45),
			_rng.randf_range(0.74, 0.92))
		cl.init_genome({
			"shell_color": sc,
			"body_color": bc,
			"siphon_color": bc.darkened(0.18),
			"shell_size": _rng.randf_range(0.82, 1.18),
			"max_age_s": _rng.randf_range(200.0, 320.0),
			"filter_radius": _rng.randf_range(1.3, 1.9),
		})
		# Stagger ages so the starting clams don't all rest in unison.
		cl.age = _rng.randf_range(0.0, 30.0)
		if cl.age >= cl.BABY_DURATION_S:
			cl.maturity = cl.MATURITY_ADULT
			cl.scale = Vector3.ONE
		sim.register_clam(cl)


func _spawn_initial_plants() -> void:
	# Walstad jungle: dense, varied. Five species flavors keyed by zone +
	# growth params. Each species has a color ramp + max_height + grow rate.
	#   1. valli  - tall back blades, blue-greens, slow
	#   2. crypt  - midground rosettes, warm greens
	#   3. carpet - foreground, light greens, fast
	#   4. red_stem - red-tinted accent plants, midground
	#   5. moss   - tiny clumps on hardscape
	# Some plants land on the driftwood (epiphytes) too.

	var species_specs: Array[Dictionary] = [
		{"name": "valli",    "max": [14, 22], "rate": 0.18, "sway": 0.22,
		 "leaf_form": "ribbon", "leaf_length": 8, "max_roots": 4,
		 "ramp": [Color8(16, 38, 20), Color8(29, 59, 34), Color8(44, 90, 48),
				  Color8(62, 127, 64), Color8(87, 162, 83), Color8(121, 192, 105)]},
		{"name": "crypt",    "max": [9, 14],  "rate": 0.20, "sway": 0.10,
		 "leaf_form": "paddle", "leaf_length": 5, "max_roots": 6,
		 "ramp": [Color8(34, 60, 28), Color8(54, 88, 38), Color8(78, 119, 53),
				  Color8(110, 152, 73), Color8(140, 178, 95), Color8(170, 200, 120)]},
		{"name": "carpet",   "max": [3, 6],   "rate": 0.30, "sway": 0.04,
		 "leaf_form": "needle", "leaf_length": 3, "max_roots": 3,
		 "ramp": [Color8(40, 90, 35), Color8(60, 122, 52), Color8(82, 152, 70),
				  Color8(110, 180, 92), Color8(145, 205, 118), Color8(180, 225, 145)]},
		{"name": "red_stem", "max": [11, 18], "rate": 0.18, "sway": 0.16,
		 "leaf_form": "lance", "leaf_length": 3, "max_roots": 4,
		 "ramp": [Color8(78, 32, 30), Color8(115, 50, 40), Color8(155, 70, 52),
				  Color8(180, 95, 72), Color8(200, 125, 90), Color8(215, 160, 120)]},
		{"name": "moss",     "max": [2, 4],   "rate": 0.10, "sway": 0.02,
		 "leaf_form": "column", "leaf_length": 2, "max_roots": 2,
		 "is_epiphyte": true,
		 "ramp": [Color8(28, 50, 24), Color8(48, 80, 40), Color8(72, 110, 58),
				  Color8(98, 140, 78), Color8(125, 168, 100), Color8(150, 190, 125)]},
		# Java fern: epiphyte attaching to rock and driftwood, taller and
		# more architectural than moss. Paddle leaves emerging from a
		# rhizome — never roots into substrate.
		{"name": "java_fern", "max": [5, 9],  "rate": 0.12, "sway": 0.08,
		 "leaf_form": "paddle", "leaf_length": 4, "max_roots": 2,
		 "is_epiphyte": true,
		 "ramp": [Color8(22, 48, 26), Color8(38, 74, 36), Color8(58, 102, 48),
				  Color8(82, 130, 62), Color8(110, 158, 84), Color8(140, 188, 110)]},
	]

	# Per-scenario plant palette. Each preset can override the density
	# multiplier for each species so themed tanks read differently
	# (Iwagumi gets only carpet, blackwater gets moss-heavy, polyp lab
	# gets a single moss-and-grass tuft, etc.). Missing keys → 1.0.
	var preset: Dictionary = {}
	var cfg_for_palette := get_node_or_null("/root/TankConfig")
	if cfg_for_palette != null:
		preset = cfg_for_palette.current_tank_preset()
	var palette: Dictionary = preset.get("plant_palette", {})
	var m_valli: float = float(palette.get("valli", 1.0))
	var m_crypt: float = float(palette.get("crypt", 1.0))
	var m_red: float = float(palette.get("red_stem", 1.0))
	var m_carpet: float = float(palette.get("carpet", 1.0))
	var m_moss: float = float(palette.get("moss", 1.0))
	var m_fern: float = float(palette.get("java_fern", 1.0))

	# --- Background wall: valli forest (shape-aware placement) ---
	# Cluster jitter widened to 0.55 + per-blade fit check enforced so
	# blades don't pile on top of each other.
	var bg_band: Vector2 = _spawn_z_band("background")
	var bg_rows: int = maxi(0, int(round(8.0 * m_valli)))
	for _row in bg_rows:
		var xz: Vector2 = _sample_clear_xz_in_band(
			bg_band.x, bg_band.y, 0.55, 0.70, 36, 0.40, 0.40)
		var n_blades: int = _rng.randi_range(2, 4)
		for i in n_blades:
			var px: float = xz.x + _rng.randf_range(-0.55, 0.55)
			var pz: float = xz.y + _rng.randf_range(-0.55, 0.55)
			var fit: Vector2 = clamp_plant_site(px, pz, 0.45, 0.45)
			if not fits_plant_at(fit.x, fit.y, 0.45, 0.45):
				continue
			_spawn_plant(species_specs[0], spawn_position_on_floor(fit.x, fit.y),
				_rng.randi_range(2, 5))
	await get_tree().process_frame

	# --- Midground rosettes (crypts) + red accent stems scattered ---
	var mid_band: Vector2 = _spawn_z_band("mid")
	var mid_crypts: int = maxi(0, int(round(18.0 * m_crypt)))
	for i in mid_crypts:
		var xz: Vector2 = _sample_clear_xz_in_band(
			mid_band.x, mid_band.y, 0.45, 0.70, 36, 0.55, 0.50)
		_spawn_plant(species_specs[1], spawn_position_on_floor(xz.x, xz.y),
			_rng.randi_range(2, 4))
	await get_tree().process_frame
	var mid_reds: int = maxi(0, int(round(9.0 * m_red)))
	for i in mid_reds:
		var xz: Vector2 = _sample_clear_xz_in_band(
			mid_band.x, mid_band.y, 0.45, 0.70, 36, 0.55, 0.50)
		_spawn_plant(species_specs[3], spawn_position_on_floor(xz.x, xz.y),
			_rng.randi_range(2, 4))
	await get_tree().process_frame

	# --- Foreground carpet: medium density. The carpet relies on later
	# runner propagation (Vallisneria-style stolons) to fill in over
	# play time rather than spawning everything packed at start.
	var fg_band: Vector2 = _spawn_z_band("foreground")
	var fg_carpet: int = maxi(0, int(round(30.0 * m_carpet)))
	for i in fg_carpet:
		var xz: Vector2 = _sample_clear_xz_in_band(
			fg_band.x, fg_band.y, 0.40, 0.55, 36, 0.30, 0.58)
		_spawn_plant(species_specs[2], spawn_position_on_floor(xz.x, xz.y),
			_rng.randi_range(1, 3))
		if i == 15:
			await get_tree().process_frame
	await get_tree().process_frame

	# --- Moss on driftwood epiphyte points ---
	var moss_n: int = maxi(0, int(round(10.0 * m_moss * _epiphyte_spawn_scalar())))
	for i in moss_n:
		if _driftwood_voxels.is_empty():
			break
		var anchor: MeshInstance3D = _driftwood_voxels[_rng.randi_range(
			0, _driftwood_voxels.size() - 1)]
		if anchor == null or not is_instance_valid(anchor):
			continue
		var off := Vector3(
			_rng.randf_range(-0.15, 0.15),
			_rng.randf_range(0.20, 0.48),
			_rng.randf_range(-0.15, 0.15))
		var moss_pos: Vector3 = anchor.global_position + off
		if not is_inside_tank_volume(moss_pos.x, moss_pos.y, moss_pos.z, 0.2):
			continue
		_spawn_plant(species_specs[4], moss_pos, _rng.randi_range(1, 2))
	await get_tree().process_frame

	# --- Java fern on rock + driftwood ---
	# Pick from the upper voxels of each hardscape pool so the fern sits
	# visibly on top of the surface rather than embedded in it.
	var epiphyte_hosts: Array[MeshInstance3D] = []
	for v in _rock_voxels:
		if v != null and is_instance_valid(v) and v.global_position.y > SUBSTRATE_DEPTH + 0.1:
			epiphyte_hosts.append(v)
	for v in _driftwood_voxels:
		if v != null and is_instance_valid(v) and v.global_position.y > SUBSTRATE_DEPTH + 0.35:
			epiphyte_hosts.append(v)
	var fern_n: int = maxi(0, int(round(8.0 * m_fern * _epiphyte_spawn_scalar())))
	for i in fern_n:
		if epiphyte_hosts.is_empty():
			break
		var host: MeshInstance3D = epiphyte_hosts[_rng.randi_range(
			0, epiphyte_hosts.size() - 1)]
		if host == null or not is_instance_valid(host):
			continue
		var jf_off := Vector3(
			_rng.randf_range(-0.12, 0.12),
			_rng.randf_range(0.30, 0.55),
			_rng.randf_range(-0.12, 0.12))
		var jf_pos: Vector3 = host.global_position + jf_off
		if not is_inside_tank_volume(jf_pos.x, jf_pos.y, jf_pos.z, 0.2):
			continue
		_spawn_plant(species_specs[5], jf_pos, _rng.randi_range(1, 2))
	await get_tree().process_frame

	# --- Spiral plants: 6 scattered, voxels arranged in golden-angle
	# phyllotaxis. Visibly mathematical (sunflower / aloe pattern).
	var spiral_ramps: Array = [
		[Color8(40, 70, 30), Color8(60, 100, 45), Color8(85, 130, 60),
		 Color8(110, 160, 78), Color8(140, 190, 100), Color8(180, 220, 140)],
		[Color8(70, 30, 30), Color8(100, 50, 50), Color8(140, 80, 75),
		 Color8(170, 110, 100), Color8(200, 140, 130), Color8(220, 175, 160)],
	]
	for i in 6:
		var sp := SpiralPlant.new()
		plants_root.add_child(sp)
		var scatter_band: Vector2 = _spawn_z_band("scatter")
		var sp_xz: Vector2 = _sample_clear_xz_in_band(
			scatter_band.x, scatter_band.y, 0.55, 0.7, 36, 0.55, 0.50)
		sp_xz = clamp_plant_site(sp_xz.x, sp_xz.y, 0.55, 0.5)
		sp.global_position = spawn_position_on_floor(sp_xz.x, sp_xz.y)
		sp.ramp_override = spiral_ramps[i % spiral_ramps.size()]
		sp.water_surface_y = WATER_HEIGHT
		sp.generation = 0
		var wall_slack: float = lateral_room_at(sp_xz.x, sp_xz.y, 0.55)
		sp.max_horizontal_extent = clampf(wall_slack * 0.72, 0.03, 0.12)
		sp.tank_wall_margin = 0.55
		sp.init(_rng.randi_range(3, 5), {
			"max_height": _rng.randi_range(8, 14),
			"growth_rate": 0.16,
			"sway_amplitude": 0.0,
		})
		sim.register_plant(sp)
	await get_tree().process_frame

	# --- Branching ferns: 8 scattered, each grows into a small tree shape
	# via L-system side branches. Visible mathematical structure.
	var fern_ramp: Array = [
		Color8(20, 50, 28), Color8(34, 78, 42), Color8(52, 110, 60),
		Color8(76, 142, 82), Color8(108, 175, 110), Color8(150, 210, 145),
	]
	for i in 8:
		var bp := BranchPlant.new()
		plants_root.add_child(bp)
		var bp_xz: Vector2 = _sample_clear_xz_in_band(
			-TANK_HALF_D * 0.85, TANK_HALF_D * 0.7, 0.4, 0.6, 36, 0.40, 0.46)
		bp.global_position = spawn_position_on_floor(bp_xz.x, bp_xz.y)
		bp.ramp_override = fern_ramp
		bp.water_surface_y = WATER_HEIGHT
		bp.generation = 0
		bp.branch_chance = _rng.randf_range(0.3, 0.45)
		bp.branch_interval = _rng.randi_range(2, 4)
		bp.branch_angle_deg = _rng.randf_range(28.0, 45.0)
		bp.init(_rng.randi_range(2, 4), {
			"max_height": _rng.randi_range(8, 13),
			"growth_rate": 0.18,
			"sway_amplitude": 0.18,
		})
		sim.register_plant(bp)
	await get_tree().process_frame

	# --- Freshwater sessile fauna analogs ---
	# Hydra-like polyps and freshwater sponges add reef-like structure to
	# freshwater tanks while staying ecologically distinct.
	for i in 8:
		var xz: Vector2 = _pick_ecology_site(
			false, -TANK_HALF_D * 0.8, TANK_HALF_D * 0.8, 0.4, 0.45)
		var c := Coral.new()
		plants_root.add_child(c)
		c.global_position = spawn_position_on_floor(xz.x, xz.y)
		c.coral_form = "hydra_fresh" if randf() < 0.55 else "sponge_fresh"
		if c.coral_form == "hydra_fresh":
			c.ramp_override = [
				Color8(35, 68, 44), Color8(52, 98, 60), Color8(74, 130, 81),
				Color8(98, 156, 108), Color8(125, 182, 132), Color8(156, 212, 162),
			]
			c.tip_color = Color8(196, 244, 210)
			c.init(_rng.randi_range(2, 4), {
				"max_height": _rng.randi_range(8, 16),
				"growth_rate": 0.18,
				"sway_amplitude": 0.22,
			})
		else:
			c.ramp_override = [
				Color8(72, 86, 58), Color8(96, 112, 74), Color8(126, 142, 94),
				Color8(154, 170, 118), Color8(184, 198, 148), Color8(216, 224, 182),
			]
			c.tip_color = Color8(228, 236, 204)
			c.init(_rng.randi_range(1, 3), {
				"max_height": _rng.randi_range(7, 13),
				"growth_rate": 0.14,
				"sway_amplitude": 0.06,
			})
		c.water_surface_y = WATER_HEIGHT
		c.generation = 0
		sim.register_plant(c)

	# --- Marimo moss balls ---
	# Spherical algae colonies. 2–3 per tank, dropped at scattered
	# floor positions. They draw nitrate fast (real marimo are nitrate
	# sponges), grow extremely slowly, and sit immovably on the substrate.
	for i in _rng.randi_range(2, 3):
		var mx: Vector2 = _pick_ecology_site(
			false, -TANK_HALF_D * 0.75, TANK_HALF_D * 0.75, 0.5, 0.5)
		var marimo := Coral.new()
		plants_root.add_child(marimo)
		marimo.global_position = spawn_position_on_floor(mx.x, mx.y, 0.04)
		marimo.coral_form = "marimo"
		marimo.ramp_override = [
			Color8(28, 56, 30), Color8(42, 78, 42), Color8(58, 102, 56),
			Color8(76, 124, 70), Color8(96, 148, 85), Color8(118, 172, 100),
		]
		marimo.tip_color = Color8(140, 192, 120)
		marimo.init(_rng.randi_range(18, 30), {
			"max_height": _rng.randi_range(38, 60),
			"growth_rate": 0.05,        # marimo grow ~5 mm / YEAR in real life
			"sway_amplitude": 0.02,     # they barely move
			"nutrient_demand": 0.10,    # heavy nitrate uptake
		})
		marimo.water_surface_y = WATER_HEIGHT
		marimo.generation = 0
		sim.register_plant(marimo)

	# --- Riccia pearling carpet ---
	# Bright lime-green liverwort patches. Each produces dramatic O2
	# pearling under good light — visible bubble columns that read as
	# "this tank is healthy." 3–5 small carpets at random foreground
	# positions.
	for i in _rng.randi_range(3, 5):
		var rxz: Vector2 = _pick_ecology_site(
			false, -TANK_HALF_D * 0.6, TANK_HALF_D * 0.6, 0.35, 0.45)
		var riccia := Coral.new()
		plants_root.add_child(riccia)
		riccia.global_position = spawn_position_on_floor(rxz.x, rxz.y, 0.04)
		riccia.coral_form = "riccia"
		riccia.ramp_override = [
			Color8(58, 110, 42), Color8(82, 140, 58), Color8(110, 168, 78),
			Color8(140, 195, 100), Color8(170, 218, 125), Color8(195, 235, 150),
		]
		riccia.tip_color = Color8(215, 245, 170)
		riccia.init(_rng.randi_range(6, 10), {
			"max_height": _rng.randi_range(14, 22),
			"growth_rate": 0.22,        # moderate carpet spread
			"sway_amplitude": 0.04,     # carpet barely moves
			"nutrient_demand": 0.06,
		})
		riccia.water_surface_y = WATER_HEIGHT
		riccia.generation = 0
		sim.register_plant(riccia)


# Reef-tank coral spawn (called instead of _spawn_initial_plants when
# the substrate profile is_saltwater). Lays out a layered reef:
#   background:  staghorn branching forest along the back wall
#   midground:   brain/boulder domes scattered through center
#   foreground:  table corals + feathery soft corals near the front
# Each coral form has its own palette + max_height range so the reef
# reads as a complex multi-species community.
func _spawn_initial_corals() -> void:
	# Coral palettes, each a 6-color ramp (dark base → bright polyp tip).
	# Six base palettes - enough variety that two corals adjacent rarely
	# share an exact ramp.
	var coral_palettes: Array = [
		# 0: orange-pink staghorn (Acropora millepora)
		[Color8(120, 55, 50), Color8(160, 85, 70), Color8(200, 120, 95),
		 Color8(225, 155, 130), Color8(245, 185, 165), Color8(255, 215, 195)],
		# 1: purple staghorn
		[Color8(60, 35, 90), Color8(85, 55, 130), Color8(115, 85, 170),
		 Color8(150, 120, 205), Color8(185, 160, 225), Color8(215, 195, 240)],
		# 2: green-tan brain coral
		[Color8(45, 70, 50), Color8(75, 105, 70), Color8(110, 140, 95),
		 Color8(145, 170, 120), Color8(180, 195, 150), Color8(215, 220, 180)],
		# 3: red-cream brain coral
		[Color8(110, 45, 35), Color8(145, 70, 55), Color8(180, 100, 80),
		 Color8(210, 135, 110), Color8(235, 175, 150), Color8(250, 220, 200)],
		# 4: lavender soft coral
		[Color8(75, 50, 100), Color8(105, 75, 140), Color8(140, 110, 180),
		 Color8(175, 145, 215), Color8(205, 180, 235), Color8(230, 215, 250)],
		# 5: yellow-amber plate coral
		[Color8(105, 75, 30), Color8(140, 105, 45), Color8(180, 140, 60),
		 Color8(210, 175, 85), Color8(235, 210, 130), Color8(250, 235, 180)],
	]

	# --- Background: staghorn forest (shape-aware) ---
	for _row in 10:
		var xz: Vector2 = _sample_clear_xz_in_band(
			-TANK_HALF_D * 0.95, -TANK_HALF_D * 0.55, 0.4, 0.55, 36, 0.35, 0.52)
		var c := Coral.new()
		plants_root.add_child(c)
		c.global_position = spawn_position_on_floor(xz.x, xz.y)
		c.coral_form = "branching" if _rng.randf() < 0.6 else "staghorn_fern"
		var pal: Array = coral_palettes[_rng.randi() % 2]  # palettes 0 or 1
		c.ramp_override = pal
		c.tip_color = pal[pal.size() - 1]
		c.water_surface_y = WATER_HEIGHT
		c.generation = 0
		c.init(_rng.randi_range(3, 5), {
			"max_height": _rng.randi_range(14, 22),
			"growth_rate": 0.18,
			"sway_amplitude": 0.04,
		})
		sim.register_plant(c)
	await get_tree().process_frame
 
	# --- Midground: brain coral domes ---
	for i in 14:
		var xz: Vector2 = _sample_clear_xz_in_band(-0.5, 1.0, 0.4, 0.45, 36, 0.0, 0.40)
		var c := Coral.new()
		plants_root.add_child(c)
		c.global_position = spawn_position_on_floor(xz.x, xz.y)
		c.coral_form = "dome" if _rng.randf() < 0.5 else "brain"
		var pal: Array = coral_palettes[2 + _rng.randi() % 2]  # palettes 2 or 3
		c.ramp_override = pal
		c.tip_color = pal[pal.size() - 1]
		c.water_surface_y = WATER_HEIGHT
		c.generation = 0
		c.init(_rng.randi_range(4, 7), {
			"max_height": _rng.randi_range(16, 28),
			"growth_rate": 0.14,
			"sway_amplitude": 0.0,    # domes don't sway
		})
		sim.register_plant(c)
	await get_tree().process_frame
 
	# --- Soft corals: tall feathery / sea-fan, scattered through midground ---
	for i in 12:
		var xz: Vector2 = _sample_clear_xz_in_band(-1.5, 1.5, 0.5, 0.5, 36, 0.0, 0.44)
		var c := Coral.new()
		plants_root.add_child(c)
		c.global_position = spawn_position_on_floor(xz.x, xz.y)
		c.coral_form = "feathery"
		c.ramp_override = coral_palettes[4]   # lavender
		c.tip_color = coral_palettes[4][5]
		c.water_surface_y = WATER_HEIGHT
		c.generation = 0
		c.init(_rng.randi_range(2, 4), {
			"max_height": _rng.randi_range(14, 22),
			"growth_rate": 0.20,
			"sway_amplitude": 0.22,
		})
		sim.register_plant(c)
	await get_tree().process_frame
 
	# --- Foreground: table corals on small pedestals ---
	for i in 9:
		var xz: Vector2 = _sample_clear_xz_in_band(
			TANK_HALF_D * 0.25, TANK_HALF_D * 0.95, 0.4, 0.45, 36, 0.30, 0.56)
		var c := Coral.new()
		plants_root.add_child(c)
		c.global_position = spawn_position_on_floor(xz.x, xz.y)
		c.coral_form = "plate"
		c.ramp_override = coral_palettes[5]   # yellow-amber
		c.tip_color = coral_palettes[5][5]
		c.water_surface_y = WATER_HEIGHT
		c.generation = 0
		c.init(_rng.randi_range(3, 5), {
			"max_height": _rng.randi_range(12, 18),
			"growth_rate": 0.18,
			"sway_amplitude": 0.0,
		})
		sim.register_plant(c)
	await get_tree().process_frame

	# --- Invertebrate layer: anemones, clams, and sponges ---
	for i in 18:
		var xz: Vector2 = _pick_ecology_site(
			true, -TANK_HALF_D * 0.7, TANK_HALF_D * 0.85, 0.45, 0.45, 0.48)
		var c := Coral.new()
		plants_root.add_child(c)
		c.global_position = spawn_position_on_floor(xz.x, xz.y)
		var form_roll: float = randf()
		if form_roll < 0.45:
			c.coral_form = "anemone"
			c.ramp_override = [
				Color8(82, 60, 118), Color8(110, 86, 150), Color8(142, 116, 186),
				Color8(174, 148, 216), Color8(205, 182, 236), Color8(234, 214, 248),
			]
			c.tip_color = Color8(255, 235, 220)
			c.init(_rng.randi_range(2, 4), {
				"max_height": _rng.randi_range(10, 20),
				"growth_rate": 0.18,
				"sway_amplitude": 0.26,
			})
		elif form_roll < 0.75:
			c.coral_form = "sponge"
			c.ramp_override = [
				Color8(146, 106, 68), Color8(170, 126, 84), Color8(194, 148, 102),
				Color8(214, 170, 123), Color8(229, 194, 148), Color8(242, 216, 176),
			]
			c.tip_color = Color8(248, 230, 204)
			c.init(_rng.randi_range(1, 2), {
				"max_height": _rng.randi_range(8, 14),
				"growth_rate": 0.14,
				"sway_amplitude": 0.05,
			})
		else:
			c.coral_form = "clam"
			c.ramp_override = [
				Color8(88, 76, 98), Color8(118, 104, 132), Color8(148, 136, 166),
				Color8(180, 166, 198), Color8(210, 196, 222), Color8(234, 224, 240),
			]
			c.tip_color = Color8(116, 224, 178)
			c.init(_rng.randi_range(1, 2), {
				"max_height": _rng.randi_range(6, 10),
				"growth_rate": 0.12,
				"sway_amplitude": 0.0,
			})
		c.water_surface_y = WATER_HEIGHT
		c.generation = 0
		sim.register_plant(c)
	await get_tree().process_frame
 
 
func _maybe_recruit_coral() -> void:
	# Spawn fresh-larvae-sized coral on open substrate. Form is weighted
	# toward smaller varieties since real recruits start small and dome-shaped.
	if plants_root == null or sim == null:
		return
	var current_coral_count: int = 0
	var existing_corals: Array[Coral] = []
	for p in sim.plants:
		if p is Coral:
			current_coral_count += 1
			existing_corals.append(p as Coral)
	# Random palette - same set the initial spawn uses.
	var palettes: Array = [
		[Color8(120, 55, 50), Color8(160, 85, 70), Color8(200, 120, 95),
		 Color8(225, 155, 130), Color8(245, 185, 165), Color8(255, 215, 195)],
		[Color8(60, 35, 90), Color8(85, 55, 130), Color8(115, 85, 170),
		 Color8(150, 120, 205), Color8(185, 160, 225), Color8(215, 195, 240)],
		[Color8(45, 70, 50), Color8(75, 105, 70), Color8(110, 140, 95),
		 Color8(145, 170, 120), Color8(180, 195, 150), Color8(215, 220, 180)],
		[Color8(110, 45, 35), Color8(145, 70, 55), Color8(180, 100, 80),
		 Color8(210, 135, 110), Color8(235, 175, 150), Color8(250, 220, 200)],
		[Color8(75, 50, 100), Color8(105, 75, 140), Color8(140, 110, 180),
		 Color8(175, 145, 215), Color8(205, 180, 235), Color8(230, 215, 250)],
		[Color8(105, 75, 30), Color8(140, 105, 45), Color8(180, 140, 60),
		 Color8(210, 175, 85), Color8(235, 210, 130), Color8(250, 235, 180)],
	]
	# Recruit in mini-pulses while the reef is still establishing.
	var bloom: float = float(sim.bloom_intensity)
	var recruits: int = 1
	if current_coral_count < 30 and randf() < 0.62 + bloom * 0.25:
		recruits += 1
	if current_coral_count < 18 and randf() < 0.35 + bloom * 0.20:
		recruits += 1
	for i in recruits:
		# Weighted form pick: recruits start small/simple more often, with
		# occasional specialist morphs (anemone/sponge/clam) for diversity.
		var roll: float = randf()
		var form: String = "dome"
		if roll < 0.22:
			form = "dome"
		elif roll < 0.37:
			form = "brain"
		elif roll < 0.56:
			form = "branching"
		elif roll < 0.69:
			form = "staghorn_fern"
		elif roll < 0.82:
			form = "feathery"
		elif roll < 0.90:
			form = "anemone"
		elif roll < 0.96:
			form = "sponge"
		else:
			form = "clam"
		# Pick a substrate position biased by local habitat quality. Most recruits
		# settle near existing reefs to create visible patch expansion fronts.
		var xz: Vector2 = _pick_ecology_site(
			true, -TANK_HALF_D * 0.85, TANK_HALF_D * 0.85, 0.4, 0.5)
		if not existing_corals.is_empty() and randf() < 0.72:
			var anchor: Coral = existing_corals[_rng.randi() % existing_corals.size()]
			if anchor != null and is_instance_valid(anchor):
				var ang: float = randf() * TAU
				var rad: float = randf_range(0.35, 1.35)
				var clustered: Vector2 = _fit_xz_inside_tank(
					anchor.global_position.x + cos(ang) * rad,
					anchor.global_position.z + sin(ang) * rad, 0.35)
				if not _is_hardscape_occupied(clustered.x, clustered.y, 0.45):
					xz = clustered
		var pal: Array = palettes[_rng.randi() % palettes.size()].duplicate(true)
		for j in pal.size():
			pal[j] = pal[j].lerp(Color(randf(), randf(), randf()),
				0.04 + bloom * 0.08)
		var c := Coral.new()
		plants_root.add_child(c)
		c.global_position = spawn_position_on_floor(xz.x, xz.y)
		c.coral_form = form
		c.ramp_override = pal
		c.tip_color = pal[pal.size() - 1].lightened(0.08)
		c.water_surface_y = WATER_HEIGHT
		c.generation = 1 + int(randf() * 2.0)
		c.init(1, {
			"max_height": _rng.randi_range(9, 20),
			"growth_rate": clampf(0.16 + bloom * 0.08 + randf_range(-0.02, 0.05), 0.10, 0.34),
			"sway_amplitude": 0.20 if (form == "feathery" or form == "anemone") else 0.03,
		})
		sim.register_plant(c)


func _plant_youth_scale() -> float:
	if _cfg_node != null and String(_cfg_node.get("cycle_start_mode")) == "fresh":
		var raw: Variant = _cfg_node.get("plant_youth_scale")
		return clampf(float(raw) if raw != null else 0.52, 0.25, 1.0)
	return 1.0


func _spawn_plant(spec: Dictionary, pos: Vector3, initial_height: int) -> void:
	initial_height = maxi(1, int(round(float(initial_height) * _plant_youth_scale())))
	var is_epiphyte: bool = not not spec.get("is_epiphyte", false)
	var reach: float = float(spec.get("leaf_length", 4)) * VOXEL_SIZE * 0.55
	# Epiphytes anchor to driftwood / rock above the substrate — skip the
	# floor-fit and hardscape-collision checks, those guard against ground
	# plants colliding with stones.
	if not is_epiphyte:
		var fit: Vector2 = clamp_plant_site(pos.x, pos.z, reach, 0.28)
		if not fits_plant_at(fit.x, fit.y, reach, 0.28):
			return
		pos.x = fit.x
		pos.z = fit.y
		if pos.y <= SUBSTRATE_DEPTH + 0.15 and _is_hardscape_occupied(pos.x, pos.z, 0.45):
			return
		pos = clamp_xyz_in_tank(pos, 0.3)
		# Reject spawn if it lands inside another plant's footprint —
		# stops the visible vertical pile-up where dense initial scatter
		# planted 5+ stems on the same square inch.
		if plants_root != null:
			var spacing: float = maxf(0.32, reach * 0.55)
			var sp2: float = spacing * spacing
			for sibling in plants_root.get_children():
				if not (sibling is Plant) or not is_instance_valid(sibling):
					continue
				var op: Plant = sibling
				if op.is_epiphyte:
					continue
				var dx: float = op.global_position.x - pos.x
				var dz: float = op.global_position.z - pos.z
				if dx * dx + dz * dz < sp2:
					return
	var p := Plant.new()
	plants_root.add_child(p)
	p.global_position = pos
	p.ramp_override = spec["ramp"]
	p.water_surface_y = WATER_HEIGHT
	p.generation = 0
	var max_range: Array = spec["max"]
	p.init(initial_height, {
		"max_height": _rng.randi_range(int(max_range[0]), int(max_range[1])),
		"growth_rate": float(spec["rate"]),
		"sway_amplitude": float(spec["sway"]),
		"leaf_form": spec.get("leaf_form", "column"),
		"leaf_length": int(spec.get("leaf_length", 4)),
		"max_roots": int(spec.get("max_roots", 5)),
		"is_epiphyte": is_epiphyte,
	})
	sim.register_plant(p)


# Called by Plant.gd when an emergent (above-water) plant casts a seed.
# Return a hardscape voxel position close to `near_pos` suitable for
# epiphyte attachment, or Vector3.ZERO if no hardscape is available.
# Used by spawn_library_entry for Anubias/Buce/Java fern style species.
# Apply a curated aquascape template — drops a coordinated planting layout
# matching a real aquascaping style. Called from the settings panel. Each
# template specifies a foreground carpet, midground rosettes, background
# stems, and hardscape epiphytes pulled from RealSpeciesLibrary.
func apply_aquascape_template(template_name: String) -> int:
	if sim == null:
		return 0
	# Predefined recipes — IDs reference RealSpeciesLibrary entries.
	# (count, species_id, zone) zones: "fg" = front strip, "mg" = mid band,
	# "bg" = back row, "epi" = on hardscape.
	var recipes: Dictionary = {
		"nature": [
			[8, "monte_carlo", "fg"],
			[3, "crypt_wendtii_green", "mg"],
			[3, "rotala_rotundifolia", "bg"],
			[2, "anubias_nana", "epi"],
			[1, "java_fern", "epi"],
		],
		"iwagumi": [
			[12, "dwarf_hairgrass", "fg"],
			[1, "blyxa_japonica", "mg"],
		],
		"dutch": [
			[2, "crypt_wendtii_brown", "mg"],
			[4, "rotala_hra", "bg"],
			[3, "ludwigia_super_red", "bg"],
			[2, "alternanthera_reineckii", "mg"],
			[1, "java_fern", "epi"],
		],
		"jungle": [
			[2, "amazon_sword", "bg"],
			[4, "vallisneria_spiralis", "bg"],
			[3, "anubias_barteri", "epi"],
			[5, "dwarf_sag", "fg"],
		],
		"shrimp_tank": [
			[6, "monte_carlo", "fg"],
			[2, "buce_kedagang", "epi"],
			[1, "java_fern_windelov", "epi"],
			[2, "anubias_petite", "epi"],
			[3, "christmas_moss", "epi"],
		],
	}
	if not recipes.has(template_name):
		return 0
	var species_dict: Dictionary = RealSpeciesLibrary.by_id()
	var planted: int = 0
	for entry in recipes[template_name]:
		var n: int = int(entry[0])
		var sid: String = String(entry[1])
		# zone (foreground/midground/background/epiphyte) is encoded in the
		# recipe for future targeted-placement, but the current spawn path
		# auto-selects placement from genome.is_epiphyte / is_carpet so we
		# don't read it yet — underscore-prefix to silence the warning.
		var _zone: String = String(entry[2])
		if not species_dict.has(sid):
			continue
		var sp: Dictionary = species_dict[sid]
		var genome: Dictionary = sp.get("genome", {}).duplicate(true)
		genome["organism_type"] = "plant"
		genome["latin_name"] = String(sp.get("latin_name", ""))
		genome["common_name"] = String(sp.get("common_name", ""))
		genome["species_id"] = sid
		for i in n:
			if spawn_library_entry(genome.duplicate(true), "plant"):
				planted += 1
	return planted


func _find_nearest_hardscape_anchor(near_pos: Vector3) -> Vector3:
	if _driftwood_voxels.is_empty():
		var hs: Node = get_node_or_null("Hardscape")
		if hs == null:
			return Vector3.ZERO
		# Scan hardscape root children as fallback (rocks are stored there).
		var best_stone: MeshInstance3D = null
		var best_stone_d2: float = INF
		for c in hs.get_children():
			if not (c is MeshInstance3D):
				continue
			var d2: float = (c.global_position - near_pos).length_squared()
			if d2 < best_stone_d2:
				best_stone_d2 = d2
				best_stone = c
		return Vector3.ZERO if best_stone == null else best_stone.global_position
	# Driftwood: pick the closest top-side voxel so the rhizome rests on
	# the wood surface and the leaves emerge upward.
	var best: MeshInstance3D = null
	var best_d2: float = INF
	for mi in _driftwood_voxels:
		if mi == null or not is_instance_valid(mi):
			continue
		var d2: float = (mi.global_position - near_pos).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = mi
	if best == null:
		return Vector3.ZERO
	# Offset slightly upward so the epiphyte rhizome sits on top of the wood.
	return best.global_position + Vector3(0, 0.25, 0)


func propagate_plant(source: Plant) -> bool:
	if source == null or not is_instance_valid(source) or sim == null:
		return false
	if source.health < 0.55 or source.biomass() < 4:
		return false
	var g: Dictionary = PlantGenome.from_plant(source)
	g["no_mutate"] = true
	g["generation"] = source.generation
	var ramp: Array = source.ramp_override if source.ramp_override.size() == 6 else []
	var offset: Vector3 = Vector3(randf_range(-0.8, 0.8), 0.0, randf_range(-0.8, 0.8))
	spawn_seedling(source.global_position + offset, ramp, source.generation, g)
	return true


func spawn_seedling(pos: Vector3, ramp: Array, generation: int, seed_config: Dictionary) -> void:
	if plants_root == null or sim == null:
		return
	var is_saltwater: bool = not not _active_substrate_profile.get("is_saltwater", false)
	var seed_reach: float = float(seed_config.get("leaf_length", 4)) * VOXEL_SIZE * 0.55
	if seed_config.has("max_horizontal_extent"):
		seed_reach = maxf(seed_reach, float(seed_config["max_horizontal_extent"]) + 0.08)
	var fit: Vector2 = clamp_plant_site(pos.x, pos.z, seed_reach, 0.25)
	var sp: Vector3 = spawn_position_on_floor(fit.x, fit.y)
	if not fits_plant_at(sp.x, sp.z, seed_reach, 0.25) or _is_hardscape_occupied(sp.x, sp.z, 0.45):
		var alt_band: Vector2 = _spawn_z_band("scatter")
		var alt: Vector2 = _pick_ecology_site(
			is_saltwater, alt_band.x, alt_band.y, 0.35, 0.45)
		alt = clamp_plant_site(alt.x, alt.y, seed_reach, 0.25)
		sp.x = alt.x
		sp.z = alt.y
	var script: Script = seed_config.get("script", load("res://scripts/plant.gd"))
	var p = script.new()
	plants_root.add_child(p)
	p.global_position = sp
	if ramp.size() == 6:
		var evolved_ramp: Array = ramp.duplicate(true)
		var burst_mult: float = 0.04 + minf(0.16, float(generation) * 0.01)
		if sim != null:
			burst_mult += clampf(float(sim.bloom_intensity), 0.0, 1.0) * 0.06
		for i in evolved_ramp.size():
			evolved_ramp[i] = (evolved_ramp[i] as Color).lerp(
				Color(randf(), randf(), randf()), burst_mult)
		p.ramp_override = evolved_ramp
	p.water_surface_y = WATER_HEIGHT
	p.generation = generation
	
	# Inherit properties from parent and slightly mutate max_height. Library
	# spawns set no_mutate so the preset reads exactly — emergent seedlings
	# go through the jitter path so generations actually drift.
	var child_cfg: Dictionary = PlantGenome.enrich(seed_config.duplicate())
	if not bool(seed_config.get("no_mutate", false)):
		var parent_max: int = seed_config.get("max_height", 10)
		child_cfg["max_height"] = clampi(parent_max + _rng.randi_range(-2, 2), 4, 30)
		child_cfg["growth_rate"] = clampf(
			float(child_cfg.get("growth_rate", 0.18)) * randf_range(1.00, 1.18),
			0.06, 0.55)
	
	# Initialize the child plant using the parent's genetic traits
	p.init(1, child_cfg)
	if child_cfg.has("generation"):
		p.generation = int(child_cfg["generation"])
	if child_cfg.has("parent_lineage"):
		p.parent_lineage = String(child_cfg["parent_lineage"])
	var pk: Variant = child_cfg.get("parent_keys", [])
	if pk is Array:
		p._parent_keys = pk.duplicate()
	
	# Apply specialized traits if they exist in the config
	if "branch_chance" in child_cfg:
		p.branch_chance = child_cfg["branch_chance"]
		p.branch_interval = child_cfg["branch_interval"]
		p.branch_angle_deg = child_cfg["branch_angle_deg"]
	if "radius_step" in child_cfg:
		p.radius_step = child_cfg["radius_step"]
		p.height_step = child_cfg["height_step"]
		p.radius_cap = child_cfg["radius_cap"]
	if p is SpiralPlant:
		if "max_horizontal_extent" in child_cfg:
			p.max_horizontal_extent = child_cfg["max_horizontal_extent"]
		if "tank_wall_margin" in child_cfg:
			p.tank_wall_margin = child_cfg["tank_wall_margin"]
		
	sim.register_plant(p)


func _initial_phenotype_spread() -> float:
	# How widely the founding cohort's phenotypes are scattered. Pulled from
	# the active TankConfig.tank_preset. 0 = clones, 2.5 = highly diverse.
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return 1.0
	var preset: Dictionary = cfg.current_tank_preset()
	return float(preset.get("phenotype_spread", 1.0))


func _spread_around(base: float, spread: float, mult: float) -> float:
	# Helper: pick a value `base ± (spread * mult)`. mult scales with preset.
	return base + _rng.randf_range(-spread, spread) * mult


func _apply_initial_phenotype_spread(genome: Dictionary, mult: float) -> void:
	# Scatter the heritable visible phenotypes AROUND THEIR SPECIES-DEFINED
	# BASELINE rather than overwriting back to 1.0. Previously this function
	# wiped distinguishing skeletal traits the species library carefully set
	# (loach body_elongation 1.45, puffer body_depth_factor 1.55, etc.),
	# which is why every fish looked like a generic tetra.
	#
	# Higher mult = wider initial diversity around each species' baseline.
	# mult=0 means every founder is an EXACT clone of the species template.
	var base_fin: float = float(genome.get("fin_length_factor", 1.0))
	var base_elong: float = float(genome.get("body_elongation", 1.0))
	var base_depth: float = float(genome.get("body_depth_factor", 1.0))
	var base_head: float = float(genome.get("head_proportion", 1.0))
	var base_dorsal: float = float(genome.get("dorsal_height_factor", 1.0))
	var base_fork: float = float(genome.get("tail_fork_depth", 1.0))
	var base_size: float = float(genome.get("adult_voxel_scale", 0.18))
	var base_size_potential: float = float(genome.get("size_potential", 1.0))
	var base_jaw_claw: float = float(genome.get("jaw_claw_size", 0.0))
	if mult <= 0.0:
		# Pure clones - just keep the species template values, no jitter.
		# (The library already supplies all the right numbers.)
		return
	genome["fin_length_factor"] = clampf(
		base_fin + _rng.randf_range(-0.2, 0.2) * mult, 0.6, 1.8)
	genome["body_elongation"] = clampf(
		base_elong + _rng.randf_range(-0.08, 0.08) * mult, 0.55, 1.65)
	genome["body_depth_factor"] = clampf(
		base_depth + _rng.randf_range(-0.15, 0.15) * mult, 0.55, 1.85)
	genome["head_proportion"] = clampf(
		base_head + _rng.randf_range(-0.12, 0.12) * mult, 0.7, 1.4)
	genome["dorsal_height_factor"] = clampf(
		base_dorsal + _rng.randf_range(-0.20, 0.20) * mult, 0.6, 1.8)
	genome["tail_fork_depth"] = clampf(
		base_fork + _rng.randf_range(-0.18, 0.18) * mult, 0.3, 1.5)
	genome["adult_voxel_scale"] = clampf(
		base_size + _rng.randf_range(-0.025, 0.025) * mult, 0.08, 0.36)
	genome["size_potential"] = clampf(
		base_size_potential + _rng.randf_range(-0.18, 0.22) * mult, 0.6, 2.4)
	genome["jaw_claw_size"] = clampf(
		base_jaw_claw + _rng.randf_range(-0.20, 0.28) * mult, 0.0, 1.2)
	# Pattern + dots: only override if the species template didn't specify
	# them (so killifish stay spotted etc.). Use sentinel "has" check.
	if not genome.has("pattern_type"):
		if mult >= 1.5:
			genome["pattern_type"] = _rng.randi_range(0, 3)
		elif mult >= 0.7:
			genome["pattern_type"] = 1 if _rng.randf() < 0.55 else _rng.randi_range(0, 3)
		else:
			genome["pattern_type"] = 1
	if not genome.has("color_dot_count"):
		genome["color_dot_count"] = clampi(int(_rng.randf_range(0, 2.5) * mult), 0, 4)


func _current_stocking_dict() -> Dictionary:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return {}
	if cfg.tank_preset == "custom":
		return {
			"glassdart": int(cfg.custom_glassdart_count),
			"mudsifter": int(cfg.custom_mudsifter_count),
			"betta": 1,
			"shrimp": int(cfg.custom_shrimp_count),
		}
	return cfg.current_tank_preset().get("stocking", {})


func _stocking_shrimp_count() -> int:
	var stocking: Dictionary = _current_stocking_dict()
	if not stocking.has("shrimp"):
		return 0
	return maxi(0, int(stocking["shrimp"]))


func _spawn_initial_fish() -> void:
	# Read the preset's "stocking" dict (species_name -> count) then look up
	# each species' genome template in TankConfig.SPECIES_LIBRARY. New species
	# added to the library appear automatically; no code change here required.
	var cfg := get_node_or_null("/root/TankConfig")
	var stocking: Dictionary = {}
	if cfg != null:
		if cfg.tank_preset == "custom":
			# Custom preset honors the legacy hand-set counts on TankConfig.
			# (Custom UI hasn't yet been expanded to all species; users who
			# want the new fish should pick one of the preset mixes.)
			stocking = {
				"glassdart": int(cfg.custom_glassdart_count),
				"mudsifter": int(cfg.custom_mudsifter_count),
				"betta": 1,
			}
		else:
			var preset: Dictionary = cfg.current_tank_preset()
			stocking = preset.get("stocking", {})
	if stocking.is_empty():
		stocking = {"glassdart": 14, "mudsifter": 5, "betta": 1}

	var phenotype_mult: float = _initial_phenotype_spread()
	# Each fish builds ~30-50 voxel MeshInstance3Ds (more with the new
	# body_shape additions). Spawning all in one frame hammered Metal -
	# we yield every 4 fish so the GPU command buffer can flush.
	var _fish_built: int = 0
	for species_name in stocking.keys():
		# Shrimp + any non-fish key is handled separately.
		if species_name == "shrimp":
			continue
		var count: int = int(stocking[species_name])
		if count <= 0:
			continue
		var entry: Dictionary = TankConfig.SPECIES_LIBRARY.get(species_name, {})
		if entry.is_empty():
			push_warning("[walstad_loom] unknown species in stocking: " + species_name)
			continue
		var template: Dictionary = entry.get("genome", {})
		for i in count:
			var g: Dictionary = template.duplicate(true)
			g["sex"] = i % 2
			# Jitter lifespan so the cohort doesn't synchronise its die-off.
			g["max_age_s"] = float(g.get("max_age_s", 240.0)) + randf_range(-30, 30)
			# Founding phenotype spread - varies by preset.
			_apply_initial_phenotype_spread(g, phenotype_mult)
			_apply_founding_cohort_spread(g, i, count)
			_spawn_fish_at(g, _sample_fish_spawn_pos(g))
			_fish_built += 1
			if _fish_built % 4 == 0:
				await get_tree().process_frame


var _light_fixture_root: Node3D = null
var _light_fixture_spots: Array[SpotLight3D] = []
var _sphere_fill_light: OmniLight3D = null
var _god_ray_materials: Array[ShaderMaterial] = []


func _build_light_fixture() -> void:
	# Build a visible voxel fixture above the tank with SpotLight3Ds inside.
	# "bar" type: long horizontal box of dark voxels with light-colored
	#   emissive panels underneath. Multiple SpotLights spaced along it.
	# "spotlight" type: single circular pendant with one SpotLight.
	var cfg := get_node_or_null("/root/TankConfig")
	var fixture_type: String = "bar"
	var height_above: float = 1.4
	var size_frac: float = 0.75
	if cfg != null:
		fixture_type = String(cfg.light_fixture)
		height_above = float(cfg.light_height)
		size_frac = float(cfg.light_size)

	_god_ray_materials.clear()

	_light_fixture_root = Node3D.new()
	_light_fixture_root.name = "LightFixture"
	add_child(_light_fixture_root)
	_light_fixture_root.position = Vector3(0, TANK_HEIGHT + height_above, 0)

	var dark := VoxelMat.make(Color8(28, 28, 32))
	var panel := VoxelMat.make(Color8(245, 240, 220))   # warm panel face
	var panel_emit := VoxelMat.make_emissive(Color(1.22, 1.16, 0.98))

	if fixture_type == "spotlight":
		var radius: float = size_frac * TANK_HALF_W * 0.5
		# Center body (square-ish pendant).
		_add_cube(_light_fixture_root, Vector3(0, 0.0, 0),
			Vector3(radius * 1.2, 0.25, radius * 1.2), dark)
		# Light-emitting panel face on the underside.
		_add_cube(_light_fixture_root, Vector3(0, -0.15, 0),
			Vector3(radius * 1.0, 0.04, radius * 1.0), panel_emit)
		# Add a glow ring around the panel.
		for ang_idx in 8:
			var ang: float = (ang_idx / 8.0) * TAU
			_add_cube(_light_fixture_root, Vector3(cos(ang) * radius * 0.7, -0.12, sin(ang) * radius * 0.7),
				Vector3(0.12, 0.04, 0.12), panel)
		# Cord up to the ceiling (just for grounding the eye).
		_add_cube(_light_fixture_root, Vector3(0, 0.4, 0),
			Vector3(0.06, 0.6, 0.06), dark)
		# Single SpotLight pointing down.
		var spot := SpotLight3D.new()
		spot.position = Vector3(0, -0.2, 0)
		spot.rotation_degrees = Vector3(-90, 0, 0)
		spot.spot_range = TANK_HEIGHT + height_above + 3.0
		spot.spot_angle = 38.0
		spot.spot_attenuation = 1.4
		if TANK_SHAPE == "sphere":
			spot.spot_angle = 56.0
			spot.spot_attenuation = 0.9
		spot.shadow_enabled = false
		_light_fixture_root.add_child(spot)
		_light_fixture_spots.append(spot)

		if cfg != null and cfg.light_volumetric:
			_add_god_ray_beam(_light_fixture_root, spot, spot.spot_angle, height_above)
	else:
		# Bar - long thin housing across the tank width.
		var bar_length: float = size_frac * TANK_HALF_W * 2.0
		var bar_width: float = minf(0.8, TANK_HALF_D * 0.3)
		# Main bar body.
		_add_cube(_light_fixture_root, Vector3(0, 0.0, 0),
			Vector3(bar_length, 0.22, bar_width), dark)
		# End caps (slightly raised).
		_add_cube(_light_fixture_root, Vector3(bar_length * 0.5, 0.05, 0),
			Vector3(0.18, 0.32, bar_width * 1.1), dark)
		_add_cube(_light_fixture_root, Vector3(-bar_length * 0.5, 0.05, 0),
			Vector3(0.18, 0.32, bar_width * 1.1), dark)
		# Emissive panel running along the underside.
		_add_cube(_light_fixture_root, Vector3(0, -0.13, 0),
			Vector3(bar_length * 0.9, 0.05, bar_width * 0.65), panel_emit)
		# Fixture bloom — overbright pixel where beam meets housing.
		_add_cube(_light_fixture_root, Vector3(0, -0.17, 0),
			Vector3(bar_length * 0.12, 0.03, bar_width * 0.2),
			VoxelMat.make_emissive(Color(1.28, 1.24, 1.05)))
		# Suspension cords at both ends.
		_add_cube(_light_fixture_root, Vector3(bar_length * 0.35, 0.4, 0),
			Vector3(0.05, 0.6, 0.05), dark)
		_add_cube(_light_fixture_root, Vector3(-bar_length * 0.35, 0.4, 0),
			Vector3(0.05, 0.6, 0.05), dark)
		# Multiple SpotLights spaced along the bar for even illumination.
		var n_spots: int = 4
		for i in n_spots:
			var t: float = float(i + 0.5) / float(n_spots)
			var sx: float = -bar_length * 0.45 + t * bar_length * 0.9
			var spot := SpotLight3D.new()
			spot.position = Vector3(sx, -0.2, 0)
			spot.rotation_degrees = Vector3(-90, 0, 0)
			spot.spot_range = TANK_HEIGHT + height_above + 3.0
			spot.spot_angle = 42.0
			spot.spot_attenuation = 1.2
			if TANK_SHAPE == "sphere":
				spot.spot_angle = 58.0
				spot.spot_attenuation = 0.88
			spot.shadow_enabled = false
			_light_fixture_root.add_child(spot)
			_light_fixture_spots.append(spot)

			if cfg != null and cfg.light_volumetric:
				_add_god_ray_beam(_light_fixture_root, spot, spot.spot_angle, height_above)

	if TANK_SHAPE == "sphere":
		_apply_sphere_aquarium_lighting()


# Moonlight + 2 accent point lights. All optional; created lazily the first
# time the user toggles them on. deep_night gates the moonlight ramp so it
# only adds its tint when the sun is actually below the horizon.
func _update_accent_lights(cfg2: Node, deep_night: float, master_on: bool) -> void:
	# Moonlight — fades in past deep_night > 0.4 so dusk doesn't get a double-source feel.
	var moon_on: bool = master_on and cfg2 != null \
		and bool(cfg2.moonlight_enabled) and deep_night > 0.05
	if moon_on:
		if _moonlight == null:
			_moonlight = DirectionalLight3D.new()
			_moonlight.name = "Moonlight"
			_moonlight.shadow_enabled = false
			# Aim from above and slightly forward so it grazes the tank top.
			_moonlight.rotation = Vector3(deg_to_rad(-72.0), deg_to_rad(28.0), 0)
			add_child(_moonlight)
		_moonlight.visible = true
		_moonlight.light_color = cfg2.moonlight_color
		var moon_ramp: float = smoothstep(0.05, 0.85, deep_night)
		_moonlight.light_energy = float(cfg2.moonlight_intensity) * moon_ramp * 0.6
	elif _moonlight != null:
		_moonlight.visible = false

	# Accent point lights — independent, always on (no day/night gate) so the
	# user can use them as plant-tank stage lighting that runs 24/7.
	_apply_accent(_accent1_light, "Accent1",
		Vector3(-2.6, SUBSTRATE_DEPTH + (WATER_HEIGHT - SUBSTRATE_DEPTH) * 0.55, -2.4),
		cfg2 != null and master_on and bool(cfg2.accent1_enabled),
		float(cfg2.accent1_intensity) if cfg2 != null else 0.6,
		cfg2.accent1_color if cfg2 != null else Color.WHITE,
		1)
	_apply_accent(_accent2_light, "Accent2",
		Vector3(2.6, SUBSTRATE_DEPTH + (WATER_HEIGHT - SUBSTRATE_DEPTH) * 0.55, 2.4),
		cfg2 != null and master_on and bool(cfg2.accent2_enabled),
		float(cfg2.accent2_intensity) if cfg2 != null else 0.6,
		cfg2.accent2_color if cfg2 != null else Color.WHITE,
		2)


func _apply_accent(existing: OmniLight3D, light_name: String, pos: Vector3,
		on: bool, intensity: float, color: Color, slot: int) -> void:
	if not on:
		if existing != null and is_instance_valid(existing):
			existing.visible = false
		return
	var node: OmniLight3D = existing
	if node == null:
		node = OmniLight3D.new()
		node.name = light_name
		node.position = pos
		node.omni_range = 5.5
		node.omni_attenuation = 1.2
		node.shadow_enabled = false
		add_child(node)
		if slot == 1:
			_accent1_light = node
		else:
			_accent2_light = node
	node.visible = true
	node.light_color = color
	node.light_energy = intensity * 1.4


func _apply_sphere_aquarium_lighting() -> void:
	# Wider beams + internal fill so the bowl rim isn't harsh spotlight pools.
	for spot in _light_fixture_spots:
		if not is_instance_valid(spot):
			continue
		spot.spot_angle = minf(spot.spot_angle + 22.0, 72.0)
		spot.spot_attenuation = 0.85
	# Soft omni fill at mid-water — reads as light bouncing in the curved glass.
	_sphere_fill_light = OmniLight3D.new()
	_sphere_fill_light.name = "SphereFill"
	_sphere_fill_light.position = Vector3(0, SUBSTRATE_DEPTH + (WATER_HEIGHT - SUBSTRATE_DEPTH) * 0.52, 0)
	_sphere_fill_light.omni_range = _footprint().effective_radius(0.2) * 2.2 + WATER_HEIGHT * 0.35
	_sphere_fill_light.omni_attenuation = 1.1
	_sphere_fill_light.shadow_enabled = false
	_sphere_fill_light.light_energy = 0.12
	_sphere_fill_light.light_color = Color(0.92, 0.96, 1.0)
	add_child(_sphere_fill_light)


func _add_god_ray_beam(parent: Node3D, spot: SpotLight3D, spot_angle: float, height_above: float) -> void:
	# Calculate height from spotlight down to substrate.
	var spot_y: float = TANK_HEIGHT + height_above + spot.position.y
	var dist: float = spot_y - SUBSTRATE_DEPTH
	if dist <= 0.1:
		return

	# Create a CylinderMesh.
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.05
	# Widen bottom radius to match spotlight visual angle.
	mesh.bottom_radius = dist * tan(deg_to_rad(spot_angle * 0.45))
	mesh.height = dist
	mesh.cap_top = false
	mesh.cap_bottom = false
	mesh.radial_segments = 16
	mesh.rings = 4

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	
	# Position the mesh. CylinderMesh is centered, so offset down by half height.
	mi.position = Vector3(spot.position.x, spot.position.y - dist * 0.5, spot.position.z)
	
	# Load the shader and create a material.
	var shader := load("res://shaders/god_ray.gdshader") as Shader
	if shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		
		# Set initial parameters. beam_color.a is overwritten every frame
		# from the daylight curve in the _process loop; the initial 0 is
		# just so the first frame before the loop runs doesn't flash.
		mat.set_shader_parameter("beam_color", Color(1.0, 0.95, 0.80, 0.0))
		mat.set_shader_parameter("speed", 1.2)
		mat.set_shader_parameter("noise_scale", 1.8)
		# Tight top/bottom seal — the asymmetric depth dissipation handles
		# the gradient falloff now, so the explicit edge fade only needs
		# to hide the cylinder cap, not also dim the middle.
		mat.set_shader_parameter("edge_fade", 0.06)
		mat.set_shader_parameter("forward_scatter", 0.55)
		mat.set_shader_parameter("depth_dissipation", 0.72)

		# Falloff exponent is overwritten each frame from TankConfig fog
		# anisotropy. Lowered base range (1.0..2.4 from 1.5..4.0) so the
		# beam is visible across more viewing angles, not only side-on.
		var exponent: float = 1.4
		if TankConfig != null:
			exponent = lerp(1.0, 2.4, (TankConfig.fog_anisotropy + 0.9) / 1.8)
		mat.set_shader_parameter("falloff_exponent", exponent)
		
		mi.material_override = mat
		_god_ray_materials.append(mat)

	parent.add_child(mi)

	# Dust motes inside the beam volume. The eye reads "volumetric" mostly
	# from the suspended particulates drifting through the light, not from
	# the shaft surface itself — so a denser, brighter particle system per
	# beam carries most of the visual impact. After the palette quantizer
	# these read as crisp 1-2 pixel sparkles drifting through the shaft.
	var motes := GPUParticles3D.new()
	motes.name = "DustMotes"
	motes.amount = 32
	motes.lifetime = 9.0
	motes.preprocess = motes.lifetime * 0.5
	motes.randomness = 0.45
	motes.local_coords = false
	motes.visibility_aabb = AABB(
		Vector3(-mesh.bottom_radius * 1.2, -dist * 0.55, -mesh.bottom_radius * 1.2),
		Vector3(mesh.bottom_radius * 2.4, dist * 1.1, mesh.bottom_radius * 2.4))
	motes.position = mi.position
	var mote_pm := ParticleProcessMaterial.new()
	mote_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# Emission box covers most of the beam cone's footprint, top-loaded
	# slightly via the directional bias below so motes appear denser near
	# the lamp and disperse as they drift down.
	mote_pm.emission_box_extents = Vector3(
		mesh.bottom_radius * 0.75, dist * 0.48, mesh.bottom_radius * 0.75)
	# Motes drift slowly downward with a gentle lateral wobble — gravity
	# tiny so they sway in the simulated water column instead of falling
	# like terrestrial dust. Initial velocity adds a wisp of horizontal
	# drift; turbulence gives the random-walk look that sells suspended
	# particulates rather than rigid sprites.
	mote_pm.gravity = Vector3(0.0, -0.05, 0.0)
	mote_pm.initial_velocity_min = 0.03
	mote_pm.initial_velocity_max = 0.14
	mote_pm.direction = Vector3(0.0, -1.0, 0.0)
	mote_pm.spread = 40.0
	mote_pm.turbulence_enabled = true
	mote_pm.turbulence_noise_strength = 0.24
	mote_pm.turbulence_noise_speed_random = 0.5
	mote_pm.turbulence_noise_scale = 2.0
	# Larger motes — 0.035..0.075 — render as bright single pixels after
	# the palette quantizer instead of getting sub-pixel-averaged into the
	# beam color. This is the difference between "the beam has texture"
	# and "I can see specks floating in the beam."
	mote_pm.scale_min = 0.035
	mote_pm.scale_max = 0.075
	# Alpha curve holds the bright plateau longer + at higher value so
	# motes are clearly visible. Fade in fast, hold, fade out as they
	# descend below the active beam region.
	var alpha_curve := CurveTexture.new()
	var ac := Curve.new()
	ac.add_point(Vector2(0.0, 0.0))
	ac.add_point(Vector2(0.10, 0.85))
	ac.add_point(Vector2(0.70, 0.80))
	ac.add_point(Vector2(1.0, 0.0))
	alpha_curve.curve = ac
	mote_pm.alpha_curve = alpha_curve
	motes.process_material = mote_pm
	var mote_mesh := SphereMesh.new()
	mote_mesh.radius = 0.020
	mote_mesh.height = 0.040
	mote_mesh.radial_segments = 4
	mote_mesh.rings = 2
	# Warm-white scatter color, alpha bumped from 0.34 → 0.60 so individual
	# motes have presence rather than dissolving into the cone's wash.
	mote_mesh.material = VoxelMat.make_bubble(Color(1.0, 0.97, 0.84, 0.60))
	motes.draw_pass_1 = mote_mesh
	parent.add_child(motes)


# Sample the 8 closest fish to the camera and push their positions +
# silhouette radii into every active god_ray material. Cheap: a partial
# sort over fish[] capped at the slot count, run once per ambient tick.
const _GOD_RAY_OCCLUDER_SLOTS: int = 8
const _BLOB_SHADOW_SLOTS: int = 8
var _occluder_buf: Array = []
var _blob_buf: Array = []


func _insert_bounded_fish(buf: Array, fish: Node3D, sort_key: float, max_n: int) -> void:
	var inserted: bool = false
	for i in buf.size():
		if sort_key < float(buf[i][1]):
			buf.insert(i, [fish, sort_key])
			inserted = true
			break
	if not inserted and buf.size() < max_n:
		buf.append([fish, sort_key])
	if buf.size() > max_n:
		buf.resize(max_n)


func _find_tank_camera() -> Camera3D:
	var sv: Node = get_parent()
	while sv != null:
		if sv is SubViewport:
			break
		sv = sv.get_parent()
	if sv != null:
		for c in (sv as SubViewport).get_children():
			if c is Node3D:
				var cn: Camera3D = (c as Node3D).get_node_or_null("Camera3D") as Camera3D
				if cn != null:
					return cn
	return null


func _update_fish_lighting_contributors() -> void:
	if sim == null:
		return
	var need_god_rays: bool = not _god_ray_materials.is_empty()
	var need_blobs: bool = true
	if not need_god_rays and not need_blobs:
		return
	var cam: Camera3D = _find_tank_camera()
	var cam_pos: Vector3 = cam.global_position if cam != null else Vector3.ZERO
	var have_cam: bool = cam != null
	var bed_y: float = sim.substrate_top_y
	_occluder_buf.clear()
	_blob_buf.clear()
	for f in sim.fish:
		if not is_instance_valid(f):
			continue
		if f.get("_dying") == true:
			continue
		if have_cam and need_god_rays:
			var d2: float = (f.global_position - cam_pos).length_squared()
			_insert_bounded_fish(_occluder_buf, f, d2, _GOD_RAY_OCCLUDER_SLOTS)
		if need_blobs:
			var h: float = f.global_position.y - bed_y
			if h >= 0.0 and h <= 4.5:
				_insert_bounded_fish(_blob_buf, f, h, _BLOB_SHADOW_SLOTS)
	if need_god_rays:
		var packed: Array[Vector4] = []
		for i in _GOD_RAY_OCCLUDER_SLOTS:
			if i < _occluder_buf.size():
				var entry: Array = _occluder_buf[i]
				var fish_node: Node3D = entry[0]
				var radius: float = 0.4
				var advoxv: Variant = fish_node.get("adult_voxel_scale")
				if advoxv != null:
					radius = clampf(float(advoxv) * 2.6, 0.25, 0.85)
				packed.append(Vector4(
					fish_node.global_position.x,
					fish_node.global_position.y,
					fish_node.global_position.z,
					radius))
			else:
				packed.append(Vector4.ZERO)
		for mat in _god_ray_materials:
			if mat != null:
				mat.set_shader_parameter("occluders", packed)
	if need_blobs:
		var blob_packed: Array[Vector4] = []
		for i in _BLOB_SHADOW_SLOTS:
			if i < _blob_buf.size():
				var fish_node: Node3D = _blob_buf[i][0]
				var radius: float = 0.4
				var advoxv: Variant = fish_node.get("adult_voxel_scale")
				if advoxv != null:
					radius = clampf(float(advoxv) * 3.4, 0.3, 1.1)
				blob_packed.append(Vector4(
					fish_node.global_position.x,
					fish_node.global_position.y,
					fish_node.global_position.z,
					radius))
			else:
				blob_packed.append(Vector4.ZERO)
		VoxelMat.update_substrate_blob_shadows(blob_packed)


func _spawn_floaters() -> void:
	# Floating surface plants. Each is a parametric FloatingPlant (duckweed /
	# frogbit / salvinia / water lettuce) that drifts, photosynthesises, casts
	# shade, and propagates based on light + nutrients + grazing pressure.
	var container := Node3D.new()
	container.name = "Floaters"
	add_child(container)
	var bloom: float = float(sim.bloom_intensity) if sim != null else 0.0
	var count: int = WorldFloaterManager.initial_spawn_count(sim, bloom, TANK_SHAPE)
	for i in count:
		var f_xz: Vector2 = _sample_surface_xz(0.4, 0.36)
		_add_floater_at(
			clamp_xyz_in_tank(Vector3(f_xz.x, WATER_HEIGHT - 0.05, f_xz.y), 0.35),
			_random_floater_genome())


var _floaters: Array = []
var _floater_t: float = 0.0
var _duckweed_accum: float = 0.0
var _floater_vel: Dictionary = {}  # instance_id -> Vector3 xz velocity
var _floater_grid: Dictionary = {}   # cell_key -> Array[FloatingPlant]
var _floater_by_id: Dictionary = {}  # id -> FloatingPlant (tether lookup)
const _FLOATER_CELL: float = 1.2
const _FLOATER_SURFACE_MARGIN: float = 0.35
const _FLOATER_BOUNCE_DAMP: float = 0.74
const _FLOATER_DRAG: float = 0.91
# Surface coverage reference for floaters — scales with tank surface area.
const FLOATER_GROWTH_INTERVAL: float = 3.0
var _lily_pads: Array = []
var _lily_pad_t: float = 0.0
var _math_plants: Array = []


# Spawn the three new mathematical plant types:
#   - 2-3 nautilus log-spirals (Bernoulli's spira mirabilis curl)
#   - 2-4 cattail / reed clusters (vertical with seed head)
#   - 6-10 fractal moss patches (recursive L-system clusters)
# All shape-validated for non-rectangular tanks. New plant species are
# self-contained Node3Ds with their own tick(); they're stored in
# _math_plants so _process can drive their animation each frame.
func _spawn_math_plants() -> void:
	var container := Node3D.new()
	container.name = "MathPlants"
	add_child(container)
	var green_ramp: Array = [
		Color8(20, 60, 30), Color8(40, 95, 50), Color8(60, 130, 70),
		Color8(90, 170, 95), Color8(140, 210, 130),
	]
	var red_ramp: Array = [
		Color8(70, 30, 30), Color8(110, 50, 50), Color8(160, 80, 80),
		Color8(200, 120, 120), Color8(230, 170, 165),
	]

	# Nautilus spirals.
	var nautilus_script := load("res://scripts/nautilus_plant.gd")
	for i in _rng.randi_range(2, 3):
		var xz: Vector2 = _random_xz_in_band(-TANK_HALF_D * 0.8, TANK_HALF_D * 0.5, 0.6)
		var p = nautilus_script.new()
		container.add_child(p)
		var ramp_choice: Array = green_ramp if randf() < 0.7 else red_ramp
		p.a = _rng.randf_range(0.03, 0.05)
		p.b = _rng.randf_range(0.09, 0.13)
		p.total_turns = _rng.randf_range(3.0, 3.8)
		p.y_per_turn = _rng.randf_range(0.6, 0.85)
		p.init_at(clamp_xyz_in_tank(spawn_position_on_floor(xz.x, xz.y, 0.1), 0.35), ramp_choice)
		p.set_meta("math_kind", "nautilus")
		_math_plants.append(p)

	# Cattail reeds.
	var cattail_script := load("res://scripts/cattail_plant.gd")
	for i in _rng.randi_range(2, 4):
		# Reeds prefer the back band (background-plant style).
		var xz: Vector2 = _random_xz_in_band(-TANK_HALF_D * 0.95, -TANK_HALF_D * 0.4, 0.5)
		var p = cattail_script.new()
		container.add_child(p)
		p.height_voxels = _rng.randi_range(18, 26)
		p.lean_amplitude = _rng.randf_range(0.4, 0.8)
		p.head_voxels = _rng.randi_range(4, 6)
		p.water_surface_y = WATER_HEIGHT
		p.init_at(clamp_xyz_in_tank(spawn_position_on_floor(xz.x, xz.y, 0.05), 0.35),
			Color8(110, 145, 75),
			Color8(110, 78, 48),
			Color8(95, 140, 75))
		p.set_meta("math_kind", "cattail")
		_math_plants.append(p)

	# Fractal moss patches.
	var moss_script := load("res://scripts/fractal_moss.gd")
	var moss_ramp: Array = [
		Color8(25, 65, 40), Color8(45, 95, 55), Color8(75, 130, 70),
		Color8(110, 170, 95), Color8(150, 200, 125),
	]
	for i in _rng.randi_range(6, 10):
		var xz: Vector2 = _random_xz_in_band(
			-TANK_HALF_D * 0.85, TANK_HALF_D * 0.85, 0.4)
		var p = moss_script.new()
		container.add_child(p)
		p.depth = _rng.randi_range(2, 3)
		p.children = _rng.randi_range(3, 5)
		# Moss settles on the substrate OR on existing logs at random
		# heights - we anchor to substrate here; future "moss on log"
		# pass could parent these to a hardscape log instead.
		var y_jitter: float = randf_range(0.1, 0.6)
		p.init_at(clamp_xyz_in_tank(spawn_position_on_floor(xz.x, xz.y, y_jitter), 0.35), moss_ramp)
		p.set_meta("math_kind", "moss")
		_math_plants.append(p)


# Spawn a small bed of lily pads (Nymphaea) - mathematical radial plants
# arranged via Vogel's spiral on the water surface. Each has its own stem
# down to the substrate. 3-5 pads scattered, shape-validated for hex /
# triangle tanks. See lily_pad.gd for the math.
func _spawn_lily_pads() -> void:
	var container := Node3D.new()
	container.name = "LilyPads"
	add_child(container)
	var n: int = _rng.randi_range(3, 5)
	for i in n:
		var xz: Vector2 = _random_xz_in_band(
			-TANK_HALF_D * 0.7, TANK_HALF_D * 0.7, 1.0)
		# Skip if too close to an existing pad - lily pads have territorial
		# spread, they don't stack.
		var too_close: bool = false
		for existing in _lily_pads:
			if not is_instance_valid(existing):
				continue
			var dx: float = existing.global_position.x - xz.x
			var dz: float = existing.global_position.z - xz.y
			if dx * dx + dz * dz < 4.0:
				too_close = true
				break
		if too_close:
			continue
		var pad_script := load("res://scripts/lily_pad.gd")
		if pad_script == null:
			continue
		var pad = pad_script.new()
		container.add_child(pad)
		pad.global_position = Vector3(xz.x, WATER_HEIGHT - 0.1, xz.y)
		pad.pad_radius = _rng.randf_range(0.75, 1.15)
		pad.pad_voxels = _rng.randi_range(20, 34)
		pad.init_at(pad.global_position, SUBSTRATE_DEPTH)
		_lily_pads.append(pad)


# Spawn a single floating-plant clump from a genome dict at a world-space
# position. Used by initial stocking, propagation, save-restore, and the
# Creature Creator. Registered into _floaters so it drifts + propagates.
func _add_floater_at(pos: Vector3, genome: Dictionary = {}) -> FloatingPlant:
	var container := get_node_or_null("Floaters")
	if container == null:
		container = Node3D.new()
		container.name = "Floaters"
		add_child(container)
	var g: Dictionary = FloaterGenome.enrich(genome if not genome.is_empty() else _random_floater_genome())
	var fp := FloatingPlant.new()
	container.add_child(fp)
	fp.position = pos
	fp.init_genome(g)
	fp.set_meta("phase", randf() * TAU)
	if g.has("id"):
		fp.id = String(g.id)
	if g.has("linked_parent_id"):
		fp.linked_parent_id = String(g.linked_parent_id)
		fp.tether_timer = float(g.get("tether_timer", 0.0))
	if g.has("rot_y"):
		fp.rotation.y = float(g.rot_y)
	if g.has("chain_siblings"):
		fp.chain_siblings = int(g.chain_siblings)
	_floaters.append(fp)
	_floater_vel[fp.get_instance_id()] = Vector3.ZERO
	return fp


# Public entry point for the Creature Creator: drop a custom floating plant
# at a random surface spot. Creates the Floaters container if it's missing
# (e.g. on an empty / guided tank).
func spawn_floating_plant(genome: Dictionary) -> bool:
	# Player placement — allow packing the surface fairly tight; natural
	# propagation uses a lower threshold in _floater_growth_step().
	if floater_coverage() > 0.92:
		return false
	var xz: Vector2 = _sample_surface_xz(0.4, 0.34)
	_add_floater_at(
		clamp_xyz_in_tank(Vector3(xz.x, WATER_HEIGHT - 0.05, xz.y), 0.35),
		genome.duplicate(true))
	return true


func spawn_coral_from_genome(genome: Dictionary) -> bool:
	if plants_root == null or sim == null:
		return false
	var reach: float = 0.45
	var xz: Vector2 = _sample_substrate_xz(0.35, 0.50, reach)
	var fit: Vector2 = clamp_plant_site(xz.x, xz.y, reach, 0.28)
	if not fits_plant_at(fit.x, fit.y, reach, 0.28):
		return false
	if _is_hardscape_occupied(fit.x, fit.y, 0.45):
		return false
	var pos: Vector3 = clamp_xyz_in_tank(spawn_position_on_floor(fit.x, fit.y), 0.3)
	var c := Coral.new()
	plants_root.add_child(c)
	c.global_position = pos
	c.coral_form = String(genome.get("coral_form", "dome"))
	c.tip_color = genome.get("tip_color", Color8(255, 245, 215))
	if genome.get("ramp_override") is Array and (genome["ramp_override"] as Array).size() == 6:
		c.ramp_override = (genome["ramp_override"] as Array).duplicate()
	c.water_surface_y = WATER_HEIGHT
	c.generation = int(genome.get("generation", 0))
	c.init(1, {
		"max_height": int(genome.get("max_height", 12)),
		"growth_rate": float(genome.get("growth_rate", 0.18)),
		"sway_amplitude": float(genome.get("sway_amplitude", 0.08)),
	})
	sim.register_plant(c)
	return true


func _random_floater_genome() -> Dictionary:
	var roll: float = randf()
	var morph: String = "duckweed"
	if roll < 0.14:
		morph = "frogbit"
	elif roll < 0.24:
		morph = "salvinia"
	elif roll < 0.30:
		morph = "water_lettuce"
	elif roll < 0.34:
		morph = "red_root"
	elif roll < 0.38:
		morph = "azolla"
	elif roll < 0.41:
		morph = "water_hyacinth"
	elif roll < 0.44:
		morph = "water_spangle"
	var hue: float = _rng.randf_range(0.22, 0.36)
	var base_c: Color = Color.from_hsv(hue, _rng.randf_range(0.45, 0.72), _rng.randf_range(0.40, 0.60))
	var tip_c: Color = Color.from_hsv(fposmod(hue - 0.03, 1.0), _rng.randf_range(0.40, 0.65), _rng.randf_range(0.62, 0.85))
	var leaf_size: float = 0.2
	var leaf_count: int = 3
	match morph:
		"frogbit":
			leaf_size = _rng.randf_range(0.34, 0.46)
			leaf_count = _rng.randi_range(5, 7)
		"salvinia", "water_spangle":
			leaf_size = _rng.randf_range(0.24, 0.32)
			leaf_count = _rng.randi_range(4, 6)
		"water_lettuce", "water_hyacinth":
			leaf_size = _rng.randf_range(0.34, 0.44)
			leaf_count = _rng.randi_range(6, 8)
		"azolla":
			leaf_size = _rng.randf_range(0.14, 0.20)
			leaf_count = _rng.randi_range(3, 5)
		"red_root":
			leaf_size = _rng.randf_range(0.22, 0.30)
			leaf_count = _rng.randi_range(2, 4)
		_:
			leaf_size = _rng.randf_range(0.16, 0.22)
			leaf_count = _rng.randi_range(1, 3)
	return FloaterGenome.enrich({
		"morph": morph,
		"leaf_size": leaf_size * randf_range(0.85, 1.15),
		"leaf_count": leaf_count,
		"root_length": _rng.randf_range(0.25, 0.6),
		"base_color": base_c,
		"tip_color": tip_c,
		"spread_rate": _rng.randf_range(0.8, 1.2),
	})


func _mutate_floater_genome(g: Dictionary) -> Dictionary:
	var gen: int = int(g.get("generation", 0)) + 1
	var out: Dictionary = FloaterGenome.duplicate_mutate(g, gen)
	out["base_color"] = FloatingPlant._to_color(g.get("base_color", Color8(70, 130, 60))).lerp(
		Color(randf(), randf() * 0.6 + 0.3, randf() * 0.5), 0.07)
	out["tip_color"] = FloatingPlant._to_color(g.get("tip_color", Color8(120, 180, 90))).lerp(
		Color(randf(), randf() * 0.7 + 0.3, randf() * 0.5), 0.07)
	out["parent_lineage"] = String(g.get("plant_name", g.get("morph", "floater")))
	return out


func _floater_cell_key(x: float, z: float) -> String:
	var cx: int = int(floor(x / _FLOATER_CELL))
	var cz: int = int(floor(z / _FLOATER_CELL))
	return "%d_%d" % [cx, cz]


func _rebuild_floater_grid() -> void:
	_floater_grid.clear()
	_floater_by_id.clear()
	for f in _floaters:
		if not is_instance_valid(f) or not (f is FloatingPlant):
			continue
		var fp: FloatingPlant = f
		if fp.id != "":
			_floater_by_id[fp.id] = fp
		var key: String = _floater_cell_key(fp.position.x, fp.position.z)
		if not _floater_grid.has(key):
			_floater_grid[key] = []
		(_floater_grid[key] as Array).append(fp)


func _is_active_floater(fp: FloatingPlant) -> bool:
	return is_instance_valid(fp) and fp.is_surface_active()


func query_floaters_in_radius(pos: Vector3, radius: float, active_only: bool = false) -> Array:
	var out: Array = []
	var r_cells: int = int(ceil(radius / _FLOATER_CELL)) + 1
	var cx: int = int(floor(pos.x / _FLOATER_CELL))
	var cz: int = int(floor(pos.z / _FLOATER_CELL))
	var r2: float = radius * radius
	for dx in range(-r_cells, r_cells + 1):
		for dz in range(-r_cells, r_cells + 1):
			var key: String = "%d_%d" % [cx + dx, cz + dz]
			if not _floater_grid.has(key):
				continue
			for fp in _floater_grid[key]:
				if not is_instance_valid(fp):
					continue
				if active_only and fp is FloatingPlant and not _is_active_floater(fp):
					continue
				var d2: float = (fp.position - pos).length_squared()
				if d2 <= r2:
					out.append(fp)
	return out


# Nudge a budding spawn away from neighbors so daughters don't stack on parents.
func _floater_spawn_position(anchor: Vector3, offset: Vector3) -> Vector3:
	var pos: Vector3 = anchor + offset
	pos.y = WATER_HEIGHT - 0.05
	var base_r: float = maxf(0.22, offset.length())
	for attempt in 6:
		var crowded: bool = false
		for nb in query_floaters_in_radius(pos, 0.3, true):
			var other: FloatingPlant = nb
			var sep: Vector3 = pos - other.position
			sep.y = 0.0
			if sep.length_squared() < 0.09:
				crowded = true
				break
		if not crowded:
			break
		var ang: float = randf() * TAU
		var r: float = base_r + 0.16 + float(attempt) * 0.14
		pos = anchor + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		pos.y = WATER_HEIGHT - 0.05
	return clamp_xyz_in_tank(pos, 0.35)


# Disturbed-mat scatter (#40): outward impulse on feed drop / large ripple.
func scatter_floaters_at(pos: Vector3, radius: float, strength: float = 1.0) -> void:
	for fp in query_floaters_in_radius(pos, radius):
		if not (fp is FloatingPlant):
			continue
		var away: Vector3 = (fp as FloatingPlant).position - pos
		away.y = 0.0
		if away.length_squared() < 1e-4:
			away = Vector3(randf() - 0.5, 0, randf() - 0.5)
		var iid: int = fp.get_instance_id()
		_floater_vel[iid] = _floater_vel.get(iid, Vector3.ZERO) + away.normalized() * strength * 0.35


# Per-clump growth orchestration (Floaters v2). Replaces aggregate dieback.
func _sanitize_floater_positions() -> void:
	var surface_y: float = WATER_HEIGHT - 0.05
	for f in _floaters:
		if not is_instance_valid(f) or not (f is FloatingPlant):
			continue
		_sanitize_floater_node(f as FloatingPlant, surface_y)


func _sanitize_floater_node(fp: FloatingPlant, surface_y: float) -> void:
	fp.ensure_finite_transform()
	var iid: int = fp.get_instance_id()
	if not is_finite(fp.position.x) or not is_finite(fp.position.y) or not is_finite(fp.position.z):
		var xz: Vector2 = _sample_surface_xz(0.35, 0.34)
		fp.position = Vector3(xz.x, surface_y, xz.y)
		_floater_vel.erase(iid)
	var margin: float = _floater_glass_margin(fp)
	var clamped: Vector2 = clamp_xz_in_tank(fp.position.x, fp.position.z, margin, surface_y)
	fp.position.x = clamped.x
	fp.position.z = clamped.y
	fp.position.y = surface_y - fp.surface_sink()
	var vel: Variant = _floater_vel.get(iid, Vector3.ZERO)
	if vel is Vector3 and not (vel as Vector3).is_finite():
		_floater_vel[iid] = Vector3.ZERO
	fp.ensure_finite_transform()


func _floater_growth_step() -> void:
	_sanitize_floater_positions()
	var live: Array = []
	for f in _floaters:
		if is_instance_valid(f):
			live.append(f)
	_floaters = live
	if live.is_empty():
		return
	for fp_flags in live:
		if fp_flags is FloatingPlant and not fp_flags.get_meta("render_flags", false):
			(fp_flags as FloatingPlant).apply_render_flags()
			fp_flags.set_meta("render_flags", true)
			(fp_flags as FloatingPlant).ensure_finite_transform()
	var cap: int = WorldFloaterManager.duckweed_cap(sim, _surface_floater_capacity())
	var active_n: int = 0
	for fp0 in live:
		if fp0 is FloatingPlant and _is_active_floater(fp0):
			active_n += 1
	var coverage: float = clampf(float(active_n) / float(maxi(1, cap)), 0.0, 1.0)
	var compact: float = clampf((coverage - 0.5) / 0.5, 0.0, 1.0)
	var dt_step: float = FLOATER_GROWTH_INTERVAL
	var to_remove: Array = []
	var spawn_queue: Array = []
	# Over-cap mats: drop dormant turions immediately instead of letting hundreds
	# of invisible nodes accumulate (mesh + tick cost with no visual payoff).
	if live.size() > cap:
		for fp_purge in live:
			if fp_purge is FloatingPlant and (fp_purge as FloatingPlant).turion_buried:
				to_remove.append(fp_purge)
	_rebuild_floater_grid()
	for fp in live:
		if not (fp is FloatingPlant):
			continue
		var floater: FloatingPlant = fp
		if floater.turion_buried:
			floater.turion_age_s += dt_step
			if floater.turion_age_s > 90.0 or floater.should_remove():
				to_remove.append(floater)
			continue
		# Neighbor density for self-shade + edge bronze (#16, #50)
		var neighbors: Array = query_floaters_in_radius(
			floater.position, floater.effective_shade_radius(), true)
		floater.set_neighbor_density(clampf(float(neighbors.size()) / 6.0, 0.0, 1.0))
		floater.tick(dt_step, self, sim)
		if floater.should_remove():
			to_remove.append(floater)
			continue
		if floater.has_pending_bud():
			var bud: Dictionary = floater.consume_pending_bud()
			var bud_offset: Vector3 = bud.get("offset", Vector3(0.5, 0, 0.5))
			if compact > 0.0:
				# Crowded mats should spread outward, not spawn on top of parents.
				bud_offset *= lerpf(1.0, 1.55, compact)
			var child_g: Dictionary = _mutate_floater_genome(bud.get("genome", floater.get_genome()))
			child_g["linked_parent_id"] = String(bud.get("parent_id", floater.id))
			child_g["chain_siblings"] = int(bud.get("chain", 0))
			child_g["tether_timer"] = 0.0
			spawn_queue.append({
				"pos": _floater_spawn_position(floater.position, bud_offset),
				"genome": child_g,
				"tether_offset": bud_offset,
			})
	# Nutrient bloom burst (#15) — duckweed morph spreads faster at high nutrients
	if sim != null and float(sim.get("bloom_intensity")) > 0.82:
		for fp2 in live:
			if fp2 is FloatingPlant and (fp2 as FloatingPlant).morph == "duckweed":
				(fp2 as FloatingPlant).vitality = minf(1.0, (fp2 as FloatingPlant).vitality + 0.008)
	# Evapotranspiration haze (#29)
	if coverage > 0.65 and randf() < 0.08:
		_maybe_add_mineral_spot()
	# Thin overcrowded mats before spawning more (legacy saves, bloom bursts).
	if active_n > cap:
		var thin: Array = []
		for fp_thin in live:
			if fp_thin is FloatingPlant and _is_active_floater(fp_thin) \
					and not to_remove.has(fp_thin):
				thin.append(fp_thin)
		thin.sort_custom(func(a, b): return (a as FloatingPlant).vitality < (b as FloatingPlant).vitality)
		var excess: int = mini(thin.size(), active_n - cap)
		for ti in excess:
			var doomed: FloatingPlant = thin[ti]
			doomed.vitality = 0.0
			to_remove.append(doomed)
		coverage = clampf(float(active_n - excess) / float(maxi(1, cap)), 0.0, 1.0)
	# Spawn children under cap
	var n: int = active_n
	for victim in to_remove:
		if victim is FloatingPlant and _is_active_floater(victim):
			n -= 1
	var spawn_cap_coverage: float = WorldFloaterManager.PROPAGATION_COVERAGE_MAX
	for sq in spawn_queue:
		if n >= cap or coverage > spawn_cap_coverage:
			break
		var sp: Vector3 = sq.pos
		sp.y = WATER_HEIGHT - 0.05
		if _is_inside_tank(sp.x, sp.z, 0.4):
			var child_fp: FloatingPlant = _add_floater_at(sp, sq.genome)
			if sq.has("tether_offset"):
				child_fp.set_meta("tether_offset", sq.tether_offset)
			n += 1
			coverage = clampf(float(n) / float(maxi(1, cap)), 0.0, 1.0)
	for victim in to_remove:
		if victim is FloatingPlant:
			var vid: String = (victim as FloatingPlant).id
			if vid != "":
				_floater_by_id.erase(vid)
		_floaters.erase(victim)
		_floater_vel.erase(victim.get_instance_id())
		victim.queue_free()


# Live surface-active floater count + coverage (turion-buried clumps excluded).
func floater_count() -> int:
	var n: int = 0
	for f in _floaters:
		if f is FloatingPlant and _is_active_floater(f):
			n += 1
	return n


func floater_total() -> int:
	var n: int = 0
	for f in _floaters:
		if is_instance_valid(f):
			n += 1
	return n


func floater_coverage() -> float:
	var cap: int = WorldFloaterManager.duckweed_cap(sim, _surface_floater_capacity())
	if cap <= 0:
		return 0.0
	return clampf(float(floater_count()) / float(cap), 0.0, 1.0)


func light_penetration_at(world_pos: Vector3) -> float:
	if _env_field_ready:
		var cell := _env_cell(world_pos)
		if _env_light.has(cell):
			return float(_env_light[cell])
	return _light_penetration_uncached(world_pos)


func effective_warmth_at(world_pos: Vector3) -> float:
	if _env_field_ready:
		var cell := _env_cell(world_pos)
		if _env_warmth.has(cell):
			return float(_env_warmth[cell])
	return _warmth_uncached(world_pos)


func _env_cell(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / ENV_FIELD_CELL)),
		int(floor(world_pos.z / ENV_FIELD_CELL)))


func _refresh_environment_field(sdt: float) -> void:
	_env_field_t += sdt
	if _env_field_t < ENV_FIELD_REBUILD_S and _env_field_ready:
		return
	_env_field_t = 0.0
	_env_field_ready = true
	_env_light.clear()
	_env_warmth.clear()
	var dl: float = 1.0
	if sim != null and sim.has_method("daylight"):
		dl = float(sim.daylight())
	var heater_on: bool = true
	if _cfg_node != null and _cfg_node.get("heater_enabled") != null:
		heater_on = not not _cfg_node.heater_enabled
	var sample_y: float = WATER_HEIGHT * 0.42
	var x0: int = int(floor(-TANK_HALF_W / ENV_FIELD_CELL))
	var x1: int = int(ceil(TANK_HALF_W / ENV_FIELD_CELL))
	var z0: int = int(floor(-TANK_HALF_D / ENV_FIELD_CELL))
	var z1: int = int(ceil(TANK_HALF_D / ENV_FIELD_CELL))
	for ix in range(x0, x1 + 1):
		for iz in range(z0, z1 + 1):
			var wx: float = (float(ix) + 0.5) * ENV_FIELD_CELL
			var wz: float = (float(iz) + 0.5) * ENV_FIELD_CELL
			if not _is_inside_tank(wx, wz, 0.25):
				continue
			var cell := Vector2i(ix, iz)
			var pos := Vector3(wx, sample_y, wz)
			_env_light[cell] = _light_penetration_uncached(pos)
			_env_warmth[cell] = WorldWaterVisuals.effective_warmth_at(
				pos, sim, _cfg_node, _heater_world_pos, dl, heater_on)


func _light_penetration_uncached(world_pos: Vector3) -> float:
	var bloom: float = float(sim.bloom_intensity) if sim != null else 0.0
	var nearby: Array = query_floaters_in_radius(
		world_pos, WorldWaterVisuals.LOCAL_SHADE_RADIUS, true)
	var local_shade: float = WorldWaterVisuals.local_floater_shade_at(world_pos, nearby)
	return WorldWaterVisuals.light_penetration(
		local_shade, floater_coverage(), bloom, tannins)


func _warmth_uncached(world_pos: Vector3) -> float:
	var dl: float = 1.0
	if sim != null and sim.has_method("daylight"):
		dl = float(sim.daylight())
	var heater_on: bool = true
	if _cfg_node != null and _cfg_node.get("heater_enabled") != null:
		heater_on = not not _cfg_node.heater_enabled
	return WorldWaterVisuals.effective_warmth_at(
		world_pos, sim, _cfg_node, _heater_world_pos, dl, heater_on)


func _ensure_pearling_pool() -> void:
	if _pearling_pool_root == null:
		_pearling_pool_root = Node3D.new()
		_pearling_pool_root.name = "PearlingPool"
		add_child(_pearling_pool_root)
	while _pearling_pool.size() < PEARLING_POOL_SIZE:
		var p := GPUParticles3D.new()
		p.emitting = false
		p.amount = 6
		p.lifetime = 4.0
		p.local_coords = false
		p.visible = false
		p.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 8, 4))
		_pearling_pool_root.add_child(p)
		_pearling_pool.append(p)


func _pearling_owner_of(emitter: GPUParticles3D) -> Variant:
	if emitter.has_meta(&"pearling_owner"):
		return emitter.get_meta(&"pearling_owner")
	return null


func claim_pearling_emitter(plant: Node3D) -> GPUParticles3D:
	if plant == null:
		return null
	_ensure_pearling_pool()
	for e in _pearling_pool:
		if _pearling_owner_of(e) == plant:
			e.visible = true
			return e
	for e in _pearling_pool:
		var pool_owner: Variant = _pearling_owner_of(e)
		if pool_owner == null or not is_instance_valid(pool_owner):
			e.set_meta(&"pearling_owner", plant)
			e.visible = true
			if e.get_parent() != plant:
				e.reparent(plant)
			return e
	return null


func release_pearling_emitter(plant: Node3D) -> void:
	if plant == null:
		return
	for e in _pearling_pool:
		if _pearling_owner_of(e) == plant:
			e.emitting = false
			e.visible = false
			e.remove_meta(&"pearling_owner")
			if _pearling_pool_root != null and e.get_parent() != _pearling_pool_root:
				e.reparent(_pearling_pool_root)
			break


func surface_warmth_at(world_pos: Vector3) -> float:
	var dl: float = 1.0
	if sim != null and sim.has_method("daylight"):
		dl = float(sim.daylight())
	var heater_on: bool = true
	if _cfg_node != null and _cfg_node.get("heater_enabled") != null:
		heater_on = not not _cfg_node.heater_enabled
	return WorldWaterVisuals.surface_warmth_at(
		world_pos, _cfg_node, _heater_world_pos, dl, heater_on)


func _epiphyte_spawn_scalar() -> float:
	var base: float = biofilm_progress
	if base < 0.08 and _cfg_node != null:
		var mode: String = String(_cfg_node.get("cycle_start_mode") if _cfg_node.get("cycle_start_mode") != null else "fresh")
		base = 0.42 if mode == "established" else 0.14
	return clampf(base / 0.42, 0.10, 1.0)


# ---- Ambient world save / restore (save v4) ----

func ambient_to_save() -> Dictionary:
	var minerals: Array = []
	for spot in _mineral_spots:
		if is_instance_valid(spot):
			minerals.append(SaveHelpers.vec3_to_array(spot.position))
	var lilies: Array = []
	for lp in _lily_pads:
		if not is_instance_valid(lp):
			continue
		lilies.append({
			"pos": SaveHelpers.vec3_to_array(lp.global_position),
			"pad_radius": float(lp.pad_radius) if lp.get("pad_radius") != null else 0.95,
			"pad_voxels": int(lp.pad_voxels) if lp.get("pad_voxels") != null else 28,
			"stem_y": float(lp.stem_y) if lp.get("stem_y") != null else 1.6,
		})
	var math_out: Array = []
	for mp in _math_plants:
		if not is_instance_valid(mp):
			continue
		var entry: Dictionary = {
			"pos": SaveHelpers.vec3_to_array(mp.global_position),
			"kind": String(mp.get_meta("math_kind", "")),
		}
		if mp.get("a") != null:
			entry["a"] = float(mp.a)
			entry["b"] = float(mp.b)
			entry["total_turns"] = float(mp.total_turns)
			entry["y_per_turn"] = float(mp.y_per_turn)
		if mp.get("height_voxels") != null:
			entry["height_voxels"] = int(mp.height_voxels)
			entry["head_voxels"] = int(mp.head_voxels)
		if mp.get("depth") != null:
			entry["depth"] = int(mp.depth)
			entry["children"] = int(mp.children)
		math_out.append(entry)
	return {
		"tannins": tannins,
		"biofilm_progress": biofilm_progress,
		"mineral_spots": minerals,
		"lily_pads": lilies,
		"math_plants": math_out,
	}


func restore_ambient(d: Variant) -> void:
	if _active_substrate_profile.get("is_saltwater", false):
		return
	var had_data: bool = d is Dictionary and not (d as Dictionary).is_empty()
	if had_data:
		var amb: Dictionary = d
		tannins = clampf(float(amb.get("tannins", tannins)), 0.0, 1.0)
		biofilm_progress = clampf(float(amb.get("biofilm_progress", biofilm_progress)), 0.0, 0.7)
		_clear_mineral_spots()
		for pos_a in amb.get("mineral_spots", []):
			if pos_a is Array:
				_add_mineral_spot_at(SaveHelpers.array_to_vec3(pos_a, Vector3.ZERO))
		_restore_lily_pads_from_save(amb.get("lily_pads", []))
		_restore_math_plants_from_save(amb.get("math_plants", []))
		_apply_biofilm_tints()
	elif _lily_pads.is_empty() and _math_plants.is_empty():
		_spawn_lily_pads()
		_spawn_math_plants()


func backfill_legacy_ambient(tank_age_s: float) -> void:
	if _active_substrate_profile.get("is_saltwater", false):
		return
	if tank_age_s < WaterChemistry.SIM_DAY_S * 3.0:
		return
	if not _driftwood_voxels.is_empty() or tannins > 0.02:
		var age_days: float = tank_age_s / WaterChemistry.SIM_DAY_S
		tannins = maxf(tannins, clampf(age_days / 30.0, 0.12, 0.42))
	biofilm_progress = maxf(biofilm_progress,
		clampf(tank_age_s / (WaterChemistry.SIM_DAY_S * 14.0) * 0.52, 0.15, 0.55))
	_apply_biofilm_tints()


func _clear_mineral_spots() -> void:
	for spot in _mineral_spots:
		if is_instance_valid(spot):
			spot.queue_free()
	_mineral_spots.clear()


func _add_mineral_spot_at(pos: Vector3) -> void:
	if _mineral_spots.size() >= MINERAL_SPOT_CAP:
		return
	var glass_root := get_node_or_null("Glass")
	if glass_root == null:
		return
	var spot := MeshInstance3D.new()
	spot.mesh = VoxelMat.get_box(Vector3(0.10, 0.06, 0.10))
	spot.material_override = VoxelMat.make(Color8(225, 230, 235))
	spot.position = pos
	glass_root.add_child(spot)
	_mineral_spots.append(spot)


func _restore_lily_pads_from_save(arr: Variant) -> void:
	if not (arr is Array) or (arr as Array).is_empty():
		return
	var container := get_node_or_null("LilyPads")
	if container == null:
		container = Node3D.new()
		container.name = "LilyPads"
		add_child(container)
	var pad_script := load("res://scripts/lily_pad.gd")
	for e in arr:
		if not (e is Dictionary):
			continue
		var d: Dictionary = e
		var pad = pad_script.new()
		container.add_child(pad)
		pad.pad_radius = float(d.get("pad_radius", 0.95))
		pad.pad_voxels = int(d.get("pad_voxels", 28))
		var pos: Vector3 = SaveHelpers.array_to_vec3(d.get("pos", []), Vector3.ZERO)
		pad.global_position = clamp_xyz_in_tank(pos, 0.35)
		pad.init_at(pad.global_position, float(d.get("stem_y", SUBSTRATE_DEPTH)))
		_lily_pads.append(pad)


func _restore_math_plants_from_save(arr: Variant) -> void:
	if not (arr is Array) or (arr as Array).is_empty():
		return
	var container := get_node_or_null("MathPlants")
	if container == null:
		container = Node3D.new()
		container.name = "MathPlants"
		add_child(container)
	for e in arr:
		if not (e is Dictionary):
			continue
		var d: Dictionary = e
		var kind: String = String(d.get("kind", ""))
		var pos: Vector3 = SaveHelpers.array_to_vec3(d.get("pos", []), Vector3.ZERO)
		pos = clamp_xyz_in_tank(pos, 0.35)
		if kind == "nautilus":
			var p = load("res://scripts/nautilus_plant.gd").new()
			container.add_child(p)
			p.a = float(d.get("a", 0.04))
			p.b = float(d.get("b", 0.11))
			p.total_turns = float(d.get("total_turns", 3.4))
			p.y_per_turn = float(d.get("y_per_turn", 0.72))
			p.set_meta("math_kind", "nautilus")
			var ramp: Array = [
				Color8(20, 60, 30), Color8(40, 95, 50), Color8(60, 130, 70),
				Color8(90, 170, 95), Color8(140, 210, 130),
			]
			p.init_at(pos, ramp)
			_math_plants.append(p)
		elif kind == "cattail":
			var p = load("res://scripts/cattail_plant.gd").new()
			container.add_child(p)
			p.height_voxels = int(d.get("height_voxels", 22))
			p.head_voxels = int(d.get("head_voxels", 5))
			p.water_surface_y = WATER_HEIGHT
			p.set_meta("math_kind", "cattail")
			p.init_at(pos, Color8(110, 145, 75), Color8(110, 78, 48), Color8(95, 140, 75))
			_math_plants.append(p)
		elif kind == "moss":
			var p = load("res://scripts/fractal_moss.gd").new()
			container.add_child(p)
			p.depth = int(d.get("depth", 2))
			p.children = int(d.get("children", 4))
			p.set_meta("math_kind", "moss")
			var moss_ramp: Array = [
				Color8(25, 65, 40), Color8(45, 95, 55), Color8(75, 130, 70),
				Color8(110, 170, 95), Color8(150, 200, 125),
			]
			p.init_at(pos, moss_ramp)
			_math_plants.append(p)


# ---- Floater save / restore (called by SimDriver save_state / load_state) ----

func floaters_to_save() -> Array:
	var out: Array = []
	for f in _floaters:
		if is_instance_valid(f) and f is FloatingPlant:
			out.append((f as FloatingPlant).to_state())
	return out


func restore_floaters(arr: Variant) -> void:
	# Pre-feature saves have no floater data — fall back to a default spawn so
	# old tanks don't suddenly lose their surface plants.
	if arr == null or not (arr is Array) or (arr as Array).is_empty():
		if _floaters.is_empty():
			_spawn_floaters()
		return
	for e in arr:
		if not (e is Dictionary):
			continue
		var d: Dictionary = FloaterGenome.enrich(e)
		var pos: Vector3 = SaveHelpers.array_to_vec3(d.get("pos", []), Vector3.ZERO)
		if pos.length_squared() < 1e-4:
			var xz: Vector2 = _sample_surface_xz(0.35, 0.34)
			pos = Vector3(xz.x, WATER_HEIGHT - 0.05, xz.y)
		elif absf(pos.y) < 0.01:
			pos.y = WATER_HEIGHT - 0.05
		var fp: FloatingPlant = _add_floater_at(pos, d)
		if d.has("vitality"):
			fp.vitality = clampf(float(d.vitality), 0.0, 1.0)
		if d.has("id"):
			fp.id = String(d.id)


# One-shot expanding ripple ring at the surface. Called by fish.gd when a
# fish bursts near the meniscus (a startle dart that breaches the surface
# tension). Voxel-styled: a thin flat box that scales outward via Tween
# and fades. Cheap; we cap concurrent ripples informally via short
# lifespan rather than an explicit pool.
func spawn_burst_ripple(pos: Vector3, intensity: float = 1.0) -> void:
	# Intensity scales the final ring size + alpha so different event types
	# can fire visually distinct ripples without each caller building its
	# own MeshInstance3D. Predation strikes near surface → 1.4; fish
	# breach → 1.0; food drop → 1.2; bubble pop on surface → 0.55.
	intensity = clampf(intensity, 0.25, 2.0)
	if _visuals != null:
		_visuals.spawn_pop_spray(pos)
	var ring := MeshInstance3D.new()
	ring.mesh = VoxelMat.get_box(Vector3(0.45, 0.04, 0.45))
	ring.material_override = VoxelMat.make(Color8(225, 240, 245))
	ring.position = Vector3(pos.x, WATER_HEIGHT - 0.04, pos.z)
	add_child(ring)
	var ring_size: float = 4.0 * intensity
	var final_scale: Vector3 = Vector3(ring_size, 0.6, ring_size)
	var duration: float = 0.75 * sqrt(intensity)
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", final_scale, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Material albedo fade — duplicate first so we don't tint the shared
	# cached material for every other ripple in the tank.
	var fade_mat: ShaderMaterial = ring.material_override.duplicate() as ShaderMaterial
	ring.material_override = fade_mat
	# Initial alpha scales with intensity so a small bubble-pop ripple is
	# fainter than a fish breach.
	var start_c := Color8(225, 240, 245)
	start_c.a = clampf(intensity, 0.4, 1.0)
	fade_mat.set_shader_parameter("albedo", start_c)
	var faded := start_c
	faded.a = 0.0
	tw.tween_method(_set_ripple_albedo.bind(fade_mat),
		start_c, faded, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(ring.queue_free)


# Glass tap — concentric meniscus rings expanding from the strike point.
func spawn_glass_tap_ripples(pos: Vector3) -> void:
	spawn_burst_ripple(pos, 1.75)
	_spawn_tap_ripple_ring(pos, 0.10, 0.95, 2.4)
	_spawn_tap_ripple_ring(pos, 0.26, 0.78, 3.8)
	_spawn_tap_ripple_ring(pos, 0.44, 0.58, 5.2)


func _spawn_tap_ripple_ring(pos: Vector3, delay: float, alpha: float, end_size: float) -> void:
	var ring := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.0, 1.0)
	qm.orientation = PlaneMesh.FACE_Y
	ring.mesh = qm
	var base_col := Color(0.90, 0.96, 1.0, alpha)
	var mat := VoxelMat.make_surface_ripple(base_col).duplicate() as ShaderMaterial
	mat.set_shader_parameter("ripple_color", base_col)
	mat.set_shader_parameter("ring_strength", 0.88)
	ring.material_override = mat
	ring.position = Vector3(pos.x, WATER_HEIGHT - 0.025, pos.z)
	ring.scale = Vector3(0.3, 1.0, 0.3)
	add_child(ring)
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(end_size, 1.0, end_size), 0.95) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var faded := base_col
	faded.a = 0.0
	tw.tween_method(_set_surface_ripple_color.bind(mat), base_col, faded, 0.95) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(ring.queue_free)


func _set_surface_ripple_color(c: Color, mat: ShaderMaterial) -> void:
	if mat != null and is_instance_valid(mat):
		mat.set_shader_parameter("ripple_color", c)


# tween_method passes the interpolated Color first; .bind(mat) appends it.
func _set_ripple_albedo(c: Color, mat: ShaderMaterial) -> void:
	if mat == null or not is_instance_valid(mat):
		return
	mat.set_shader_parameter("albedo", c)


func _spawn_water_ambience() -> void:
	_spawn_surface_ripples()
	_spawn_ambient_bubbles()


func _spawn_surface_ripples() -> void:
	# Sparse ripples on the meniscus — flat shader quads that expand and fade.
	var p := GPUParticles3D.new()
	p.name = "SurfaceRipples"
	p.amount = 18
	p.lifetime = 2.4
	p.preprocess = 1.2
	p.local_coords = false
	p.position = Vector3(0, WATER_HEIGHT - 0.05, 0)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, 0)
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.gravity = Vector3(0, 0, 0)
	pm.spread = 0.0
	pm.scale_min = 0.35
	pm.scale_max = 1.35
	configure_meniscus_emission(pm, 0.02)
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.15))
	scale_curve.add_point(Vector2(0.35, 1.0))
	scale_curve.add_point(Vector2(1.0, 1.45))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	pm.scale_curve = scale_tex
	var alpha_curve := Curve.new()
	alpha_curve.add_point(Vector2(0.0, 0.0))
	alpha_curve.add_point(Vector2(0.12, 0.55))
	alpha_curve.add_point(Vector2(0.65, 0.35))
	alpha_curve.add_point(Vector2(1.0, 0.0))
	var alpha_tex := CurveTexture.new()
	alpha_tex.curve = alpha_curve
	pm.alpha_curve = alpha_tex
	p.process_material = pm
	var bm := QuadMesh.new()
	bm.size = Vector2(0.55, 0.55)
	bm.orientation = PlaneMesh.FACE_Y
	bm.material = VoxelMat.make_surface_ripple()
	p.draw_pass_1 = bm
	add_child(p)


func _spawn_ambient_bubbles() -> void:
	# Suspended micro-bubbles — one cheap emitter for the whole column.
	var p := GPUParticles3D.new()
	p.name = "AmbientBubbles"
	p.amount = 14
	p.lifetime = 9.0
	p.preprocess = 4.5
	p.local_coords = false
	var col_h: float = maxf(0.5, WATER_HEIGHT - SUBSTRATE_DEPTH)
	p.position = Vector3(0.0, SUBSTRATE_DEPTH + col_h * 0.5, 0.0)
	var pm := _make_bubble_process_material(
		Vector3(0, 1, 0), 0.12, 0.28, 0.22, 0.55, 14.0)
	configure_column_emission(pm, col_h * 0.45, 0.65)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.35
	pm.turbulence_noise_scale = 2.4
	pm.turbulence_influence_min = 0.12
	pm.turbulence_influence_max = 0.55
	pm.turbulence_influence_over_life = _bubble_turbulence_curve()
	p.process_material = pm
	var bm := SphereMesh.new()
	bm.radius = 0.035
	bm.height = 0.07
	bm.radial_segments = 5
	bm.rings = 3
	bm.material = VoxelMat.make_bubble(Color(0.82, 0.94, 0.98, 0.28))
	p.draw_pass_1 = bm
	add_child(p)


func _make_bubble_process_material(direction: Vector3, vel_min: float, vel_max: float,
		gravity_y: float, spread: float, turbulence_strength: float = 0.0) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.direction = direction.normalized()
	pm.initial_velocity_min = vel_min
	pm.initial_velocity_max = vel_max
	pm.gravity = Vector3(0, gravity_y, 0)
	pm.spread = spread
	pm.scale_min = 0.55
	pm.scale_max = 1.25
	pm.damping_min = 0.08
	pm.damping_max = 0.22
	pm.linear_accel_min = 0.05
	pm.linear_accel_max = 0.18
	if turbulence_strength > 0.0:
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = turbulence_strength
		pm.turbulence_noise_scale = 3.2
		pm.turbulence_influence_min = 0.18
		pm.turbulence_influence_max = 0.85
		pm.turbulence_influence_over_life = _bubble_turbulence_curve()
	var merge_curve := Curve.new()
	merge_curve.add_point(Vector2(0.0, 0.75))
	merge_curve.add_point(Vector2(0.55, 1.05))
	merge_curve.add_point(Vector2(1.0, 1.35))
	var merge_tex := CurveTexture.new()
	merge_tex.curve = merge_curve
	pm.scale_curve = merge_tex
	return pm


func _bubble_turbulence_curve() -> CurveTexture:
	var infl := Curve.new()
	infl.add_point(Vector2(0.0, 0.25))
	infl.add_point(Vector2(0.45, 0.85))
	infl.add_point(Vector2(1.0, 0.35))
	var tex := CurveTexture.new()
	tex.curve = infl
	return tex


# Top-level aeration dispatcher. Looks at TankConfig and builds the chosen
# fixture (disk / stick / filter / none) as a child node tree containing the
# visible equipment voxels plus the GPU particle emitters for the bubble
# stream + surface pops. Stores the resulting air injection rate on the
# SimDriver so dissolved-O2 simulation can respond.
func _spawn_aeration_system() -> void:
	var container := Node3D.new()
	container.name = "Aeration"
	add_child(container)

	var cfg := get_node_or_null("/root/TankConfig")
	var fixture: String = "disk"
	var strength: float = 0.6
	var x_frac: float = 0.0
	if cfg != null:
		fixture = String(cfg.aeration_type)
		strength = float(cfg.aeration_strength)
		x_frac = float(cfg.aeration_x_frac)
	# Anchor lateral position to tank width, keeping a margin from glass.
	var anchor_x: float = clampf(x_frac, -1.0, 1.0) * (TANK_HALF_W - 1.2)

	# Air injection rate fed into the sim: base profile rate * user strength.
	var profile: Dictionary = {"air_rate": 0.0, "flow_rate": 0.0}
	if cfg != null:
		profile = cfg.current_aeration_profile()
	var air_rate: float = float(profile.get("air_rate", 0.0)) * strength
	var flow_rate: float = float(profile.get("flow_rate", 0.0)) * strength

	match fixture:
		"disk":
			_build_disk_aerator(container, anchor_x, flow_rate)
		"stick":
			_build_stick_aerator(container, anchor_x, flow_rate)
		"filter":
			_build_filter_aerator(container, anchor_x, flow_rate)
		"none":
			pass
		_:
			_build_disk_aerator(container, anchor_x, flow_rate)

	# Push the computed rates onto the SimDriver so it can run the O2 model.
	if sim != null:
		sim.set("aeration_air_rate", air_rate)
		sim.set("aeration_flow_rate", flow_rate)
		sim.set("aeration_fixture", fixture)


func _configure_substrate_flow(origin: Vector3, jet: Vector3, flow_rate: float) -> void:
	var flow: Dictionary = WorldAtmosphere.substrate_flow_from_jet(origin, jet, flow_rate)
	_substrate_ripple_dir = flow["dir"]
	_substrate_ripple_strength = flow["strength"]
	VoxelMat.update_substrate_flow_origin(origin, clampf(flow_rate * 0.75, 0.25, 0.55))


# --- Bubble disk ---
# Round porous air-stone sitting on the substrate. Dense column of fine
# bubbles rises straight up to the surface. The disk itself is 5 dark gray
# voxels arranged in a + pattern with a thin air-line snaking back to the
# back wall.
func _build_disk_aerator(parent: Node, anchor_x: float, flow_rate: float) -> void:
	var sz: float = -TANK_HALF_D * 0.65        # tuck close to back wall
	if not _is_inside_tank(anchor_x, sz, 0.5):
		# Tank shape too narrow at the back - bring it forward.
		sz = -TANK_HALF_D * 0.3
		if not _is_inside_tank(anchor_x, sz, 0.5):
			sz = 0.0
	var disk_y: float = SUBSTRATE_DEPTH + 0.06
	# Disk body: cross pattern of dark voxels with a paler centre.
	var disk_color := Color8(35, 35, 42)
	var disk_center := Color8(70, 70, 78)
	var offs := [Vector3.ZERO, Vector3(0.3, 0, 0), Vector3(-0.3, 0, 0),
				 Vector3(0, 0, 0.3), Vector3(0, 0, -0.3)]
	for i in offs.size():
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.32, 0.1, 0.32)
		mi.mesh = bm
		mi.material_override = VoxelMat.make(disk_center if i == 0 else disk_color)
		mi.position = Vector3(anchor_x + (offs[i] as Vector3).x, disk_y,
			sz + (offs[i] as Vector3).z)
		parent.add_child(mi)
	# Air line: a thin trail of small dark voxels from the disk to the back
	# upper-right of the tank, suggesting the tube going up to a pump.
	var line_end := Vector3(anchor_x, WATER_HEIGHT + 0.4, -TANK_HALF_D + 0.15)
	_add_air_line(parent, Vector3(anchor_x, disk_y + 0.1, sz), line_end)
	# Bubble emitter: dense column emitting straight up from the disk surface.
	var rise_dist: float = WATER_HEIGHT - disk_y
	_emit_rising_bubbles(parent, Vector3(anchor_x, disk_y + 0.08, sz),
		Vector3(0.22, 0.02, 0.22), rise_dist, 18, 0.06)
	# Surface pop ripples at the meniscus directly above the disk.
	_spawn_surface_pop_emitter(parent, Vector3(anchor_x, WATER_HEIGHT - 0.05, sz),
		clampf(rise_dist / 1.3, 2.5, 6.0), 18)
	var surface_jet := Vector3(anchor_x, WATER_HEIGHT - 0.05, sz + 0.35)
	_configure_substrate_flow(Vector3(anchor_x, disk_y, sz), surface_jet, flow_rate)


# --- Bubble stick (wand) ---
# Long thin air-stone bar lying flat along the back wall. Wide, even bubble
# curtain. Visually about 60% of tank width.
func _build_stick_aerator(parent: Node, anchor_x: float, flow_rate: float) -> void:
	var sz: float = -TANK_HALF_D * 0.78
	# Make sure both ends of the bar are inside the tank for hex/triangle.
	var half_bar: float = TANK_HALF_W * 0.45
	var left_x: float = clampf(anchor_x - half_bar, -TANK_HALF_W + 1.0, TANK_HALF_W - 1.0)
	var right_x: float = clampf(anchor_x + half_bar, -TANK_HALF_W + 1.0, TANK_HALF_W - 1.0)
	if not _is_inside_tank(left_x, sz, 0.4) or not _is_inside_tank(right_x, sz, 0.4):
		sz = -TANK_HALF_D * 0.3
		if not _is_inside_tank(left_x, sz, 0.4):
			left_x = -TANK_HALF_W * 0.6
			right_x = TANK_HALF_W * 0.6
	var bar_y: float = SUBSTRATE_DEPTH + 0.06
	# Build the bar as a series of small dark voxels with bright caps at the
	# ends (where the air line connects).
	var n_segments: int = int((right_x - left_x) / 0.32) + 1
	for i in n_segments:
		var t: float = float(i) / float(maxi(1, n_segments - 1))
		var x: float = lerpf(left_x, right_x, t)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.3, 0.18, 0.18)
		mi.mesh = bm
		var is_cap: bool = (i == 0 or i == n_segments - 1)
		mi.material_override = VoxelMat.make(
			Color8(80, 80, 88) if is_cap else Color8(40, 40, 48))
		mi.position = Vector3(x, bar_y, sz)
		parent.add_child(mi)
	# Air line from one cap of the bar up the back wall.
	_add_air_line(parent, Vector3(right_x, bar_y + 0.1, sz),
		Vector3(right_x, WATER_HEIGHT + 0.4, -TANK_HALF_D + 0.15))
	# Bubble curtain: BOX emission shape stretched along X covers the whole bar.
	var center_x: float = (left_x + right_x) * 0.5
	var span: float = (right_x - left_x) * 0.5
	var rise_dist: float = WATER_HEIGHT - bar_y
	_emit_rising_bubbles(parent, Vector3(center_x, bar_y + 0.12, sz),
		Vector3(span, 0.02, 0.08), rise_dist, 28, 0.05)
	# Surface pops along the bar.
	_spawn_surface_pop_emitter(parent, Vector3(center_x, WATER_HEIGHT - 0.05, sz),
		clampf(rise_dist / 1.3, 2.5, 6.0), 24)
	_configure_substrate_flow(
		Vector3(center_x, bar_y, sz),
		Vector3(center_x, WATER_HEIGHT - 0.05, sz + 0.5), flow_rate)


# --- Filter (hang-on-back) ---
# Vertical intake/return tube. Bottom strainer sits just above the substrate;
# the tube rises through the water column to just above the surface where a
# horizontal spout pushes water (and a trickle of air-entrained bubbles)
# outward into the tank.
func _build_filter_aerator(parent: Node, anchor_x: float, flow_rate: float) -> void:
	var sz: float = -TANK_HALF_D * 0.82       # mount on the back wall
	if not _is_inside_tank(anchor_x, sz, 0.4):
		sz = -TANK_HALF_D * 0.3
	var tube_color := Color8(40, 42, 50)
	var trim := Color8(95, 95, 105)
	var spout_color := Color8(60, 62, 70)
	# Vertical tube: stack thin voxels from substrate to just above water.
	var base_y: float = SUBSTRATE_DEPTH + 0.2
	var top_y: float = WATER_HEIGHT + 0.3
	var n_seg: int = int((top_y - base_y) / 0.4) + 1
	for i in n_seg:
		var t: float = float(i) / float(maxi(1, n_seg - 1))
		var y: float = lerpf(base_y, top_y, t)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.32, 0.42, 0.32)
		mi.mesh = bm
	# Top + bottom voxels are accent colored.
		var col: Color = trim if (i == 0 or i == n_seg - 1) else tube_color
		if i == n_seg - 1:
			col = Color(1.14, 1.12, 1.06)  # emissive cap — night burnthrough
		mi.material_override = VoxelMat.make_emissive(col) if i == n_seg - 1 \
			else VoxelMat.make(col)
		mi.position = Vector3(anchor_x, y, sz)
		parent.add_child(mi)
	# Power LED + emissive status strip on the housing (night burnthrough source).
	var led := MeshInstance3D.new()
	var lbm := BoxMesh.new()
	lbm.size = Vector3(0.10, 0.08, 0.06)
	led.mesh = lbm
	led.material_override = VoxelMat.make_emissive(Color(1.18, 1.05, 0.72))
	led.position = Vector3(anchor_x + 0.22, top_y - 0.08, sz + 0.12)
	parent.add_child(led)
	for j in 3:
		var strip := MeshInstance3D.new()
		var sbm := BoxMesh.new()
		sbm.size = Vector3(0.06, 0.04, 0.28)
		strip.mesh = sbm
		strip.material_override = VoxelMat.make_emissive(Color(1.12, 1.14, 1.08))
		strip.position = Vector3(anchor_x, base_y + 0.35 + j * 0.55, sz + 0.18)
		parent.add_child(strip)
	# Intake strainer at the bottom - a wider voxel with little slots (just one
	# bigger box for visual chunk; the "slots" come from the palette dither).
	var intake := MeshInstance3D.new()
	var ibm := BoxMesh.new()
	ibm.size = Vector3(0.55, 0.32, 0.45)
	intake.mesh = ibm
	intake.material_override = VoxelMat.make(trim)
	intake.position = Vector3(anchor_x, base_y - 0.05, sz)
	parent.add_child(intake)
	# Publish the intake world position so microfauna + waste particles can
	# drift toward it and despawn — the visible "filter is doing something"
	# loop. Only set when this fixture is the active one; disk/stick/none
	# leave sim.filter_intake_pos at Vector3.ZERO (microfauna_swarm.gd treats
	# that as "no intake, ignore").
	if sim != null:
		sim.filter_intake_pos = intake.position
	# Continuous bubble column rising from the intake to the surface.
	# Distinct from substrate gas-escape: this is a steady, fine stream of
	# pale micro-bubbles that curl gently downstream (toward the spout end
	# of the tank) on their way up. Sells "the intake is alive" even
	# without any extra geometry around it.
	_emit_filter_intake_stream(parent, intake.position)
	# Horizontal spout near the top, sticking forward (toward +Z, away from
	# the back wall). 3-4 voxels.
	var spout_y: float = WATER_HEIGHT - 0.05
	for j in 4:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.3, 0.3, 0.34)
		mi.mesh = bm
		mi.material_override = VoxelMat.make(spout_color)
		mi.position = Vector3(anchor_x, spout_y, sz + 0.32 + j * 0.32)
		parent.add_child(mi)
	# Output stream: bubbles + flow emitting forward from the spout end.
	var spout_end := Vector3(anchor_x, spout_y, sz + 0.32 + 3.5 * 0.32)
	_configure_substrate_flow(intake.position, spout_end, flow_rate)
	_emit_filter_outflow(parent, spout_end)
	# Surface pop ripples downstream of the spout end.
	_spawn_surface_pop_emitter(parent,
		Vector3(spout_end.x, WATER_HEIGHT - 0.05, spout_end.z + 0.4),
		1.6, 16)


# A thin trail of dark voxels representing an air line / silicone tube. Used
# by the disk + stick aerators to make the supply visible behind the tank.
func _add_air_line(parent: Node, a: Vector3, b: Vector3) -> void:
	var steps: int = int(a.distance_to(b) / 0.35) + 1
	for i in steps:
		var t: float = float(i) / float(maxi(1, steps - 1))
		var p: Vector3 = a.lerp(b, t)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.1, 0.1, 0.1)
		mi.mesh = bm
		mi.material_override = VoxelMat.make(Color8(20, 20, 24))
		mi.position = p
		parent.add_child(mi)


# Shared bubble emitter helper. Creates a GPUParticles3D rising straight up
# from `base_pos` with emission box `extents` (half-extents on X/Y/Z).
func _emit_rising_bubbles(parent: Node, base_pos: Vector3, extents: Vector3,
		rise_distance: float, amount: int, bubble_radius: float) -> void:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = clampf(rise_distance / 1.1, 2.8, 7.0)
	p.preprocess = p.lifetime * 0.5
	p.local_coords = false
	p.position = base_pos
	var pm := _make_bubble_process_material(
		Vector3(0, 1, 0), 0.45, 0.95, 0.95, 8.0, 18.0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	p.process_material = pm
	var bm := SphereMesh.new()
	bm.radius = bubble_radius
	bm.height = bubble_radius * 2.0
	bm.radial_segments = 5
	bm.rings = 3
	bm.material = VoxelMat.make_bubble(Color(0.92, 0.98, 1.05, 0.48), 1.22)
	p.draw_pass_1 = bm
	parent.add_child(p)


# Continuous bubble column from the filter intake. Fine micro-bubbles
# rising in a slow vertical column with a small downstream curl so the
# stream visibly bends as it ascends — sells "current pulled into the
# strainer and re-released as micro-bubbles." Distinct from the heavier
# substrate gas_escape emitter, which originates lower down and uses
# bigger bubbles.
func _emit_filter_intake_stream(parent: Node, intake_pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 22
	p.lifetime = clampf((WATER_HEIGHT - intake_pos.y) / 0.5, 3.0, 7.0)
	p.preprocess = p.lifetime * 0.4
	p.local_coords = false
	# Origin sits just above the strainer voxel — bubbles emerge from the
	# grate face.
	p.position = intake_pos + Vector3(0, 0.10, 0.02)
	var pm := _make_bubble_process_material(
		Vector3(0.0, 1.0, 0.0), 0.34, 0.62, 0.6, 5.0, 14.0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# Narrow rectangular emission patch matching the strainer face — wider
	# in X than Z so the stream reads as a thin sheet, not a point.
	pm.emission_box_extents = Vector3(0.20, 0.04, 0.05)
	# Side drift bends the column toward the front of the tank as it
	# rises (downstream of the spout outflow). Sized small so the curl is
	# subtle, not wind-blown.
	pm.gravity = Vector3(0.0, 0.65, 0.20)
	# Visibility AABB grows from intake to surface so the engine doesn't
	# cull mid-rise.
	p.visibility_aabb = AABB(
		Vector3(-0.5, 0.0, -0.3),
		Vector3(1.0, WATER_HEIGHT - intake_pos.y + 0.2, 0.8))
	p.process_material = pm
	var bm := SphereMesh.new()
	bm.radius = 0.045
	bm.height = 0.09
	bm.radial_segments = 4
	bm.rings = 2
	bm.material = VoxelMat.make_bubble(Color(0.94, 0.99, 1.06, 0.35), 1.20)
	p.draw_pass_1 = bm
	parent.add_child(p)


# Filter outflow: a horizontal-ish jet of bubbles + flow streaks coming out
# of the spout. Bubbles have less buoyancy and more forward velocity so the
# stream curves down into the tank before rising again.
func _emit_filter_outflow(parent: Node, spout_end: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 16
	p.lifetime = 2.4
	p.preprocess = 0.6
	p.local_coords = false
	p.position = spout_end
	var pm := _make_bubble_process_material(
		Vector3(0, -0.2, 1), 0.85, 1.35, 0.75, 14.0, 12.0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.05, 0.08, 0.02)
	p.process_material = pm
	var bm := SphereMesh.new()
	bm.radius = 0.07
	bm.height = 0.14
	bm.radial_segments = 5
	bm.rings = 3
	bm.material = VoxelMat.make_bubble(Color(0.88, 0.96, 1.04, 0.44), 1.18)
	p.draw_pass_1 = bm
	parent.add_child(p)


# Spawn a tiny ring-of-flat-voxels particle emitter at the surface position.
# Roughly aligns with where the corresponding bubble stream's bubbles will
# pop. Visible as little expanding pale squares that fade out, suggesting
# a ring spreading from the pop.
func _spawn_surface_pop_emitter(parent: Node, pos: Vector3, bubble_lifetime: float,
		bubble_amount: int) -> void:
	var ring := GPUParticles3D.new()
	ring.amount = bubble_amount
	ring.lifetime = 0.55
	ring.local_coords = false
	# Stagger emission to match bubble cadence approximately.
	ring.speed_scale = 1.0
	ring.explosiveness = 0.0
	ring.position = pos
	# Sync the emission rate to the bubble lifetime so we get ~one pop per
	# bubble. amount / lifetime = emission rate.
	ring.lifetime = 0.55
	# Use a delay matching the bubble's transit time so pops happen after a
	# bubble would have actually arrived.
	ring.preprocess = bubble_lifetime
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.ZERO
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.gravity = Vector3.ZERO
	pm.spread = 0.0
	pm.scale_min = 0.4
	pm.scale_max = 1.0
	# Each pop scales up over its lifetime - looks like a spreading ring.
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.2))
	scale_curve.add_point(Vector2(0.4, 1.0))
	scale_curve.add_point(Vector2(1.0, 1.4))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	pm.scale_curve = scale_tex
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.05, 0.0, 0.05)
	# Fade out via color ramp at end of lifetime.
	var alpha_curve := Curve.new()
	alpha_curve.add_point(Vector2(0.0, 1.0))
	alpha_curve.add_point(Vector2(0.7, 0.7))
	alpha_curve.add_point(Vector2(1.0, 0.0))
	var grad := Gradient.new()
	grad.set_color(0, Color(0.95, 0.99, 1.0, 1.0))
	grad.set_color(1, Color(0.95, 0.99, 1.0, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	pm.color_ramp = grad_tex
	ring.process_material = pm
	var rm := QuadMesh.new()
	rm.size = Vector2(0.55, 0.55)
	rm.orientation = PlaneMesh.FACE_Y
	rm.material = VoxelMat.make_surface_ripple(Color(0.92, 0.97, 1.0, 0.62))
	ring.draw_pass_1 = rm
	parent.add_child(ring)


# Add a single mineral spot at a random spot near the waterline on a
# random wall. Real tanks develop these calcium / hard-water spots as
# splash and evaporation deposit minerals. We just sprinkle pale voxels
# at the meniscus over time so the glass visibly "ages."
func _maybe_add_mineral_spot() -> void:
	if _mineral_spots.size() >= MINERAL_SPOT_CAP:
		return
	var glass_root := get_node_or_null("Glass")
	if glass_root == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pos: Vector3 = WorldAtmosphere.pick_glass_mineral_position(
		_footprint(), WATER_HEIGHT, TANK_HALF_W, TANK_HALF_D, rng)
	if pos == Vector3.ZERO:
		return
	var spot := MeshInstance3D.new()
	spot.mesh = VoxelMat.get_box(Vector3(0.10, 0.06, 0.10))
	spot.material_override = VoxelMat.make(Color8(225, 230, 235))
	spot.position = pos
	glass_root.add_child(spot)
	_mineral_spots.append(spot)


# ---- Heater ----
# Builds a small red voxel heater rod tucked at the back-right corner of
# the tank with a faint warm OmniLight. Reads as "this tank is running"
# — every glass-aquarium photo you see has a heater in it. Always built;
# no preset switch (a heater is universal kit). Position is chosen so
# the heater clears typical plant placement zones.
func _build_heater() -> void:
	var c := Node3D.new()
	c.name = "Heater"
	add_child(c)
	var heater_x: float = TANK_HALF_W - 0.6
	var heater_z: float = -TANK_HALF_D + 0.6
	var heater_base_y: float = SUBSTRATE_DEPTH + 0.2
	# Rod itself — thin black-glass column with a dull red core showing
	# through. We approximate with two stacked voxel boxes (outer dark,
	# inner red) since transparency in the voxel shader is heavy.
	var rod_h: float = 1.8
	var outer_mat: ShaderMaterial = VoxelMat.make(Color8(20, 20, 26))
	var rod := MeshInstance3D.new()
	rod.mesh = VoxelMat.get_box(Vector3(0.22, rod_h, 0.22))
	rod.material_override = outer_mat
	rod.position = Vector3(heater_x, heater_base_y + rod_h * 0.5, heater_z)
	c.add_child(rod)
	# Visible red filament strip running up the middle.
	var core_mat: ShaderMaterial = VoxelMat.make(Color8(220, 70, 40))
	var core := MeshInstance3D.new()
	core.mesh = VoxelMat.get_box(Vector3(0.06, rod_h * 0.85, 0.06))
	core.material_override = core_mat
	core.position = Vector3(heater_x, heater_base_y + rod_h * 0.5, heater_z)
	c.add_child(core)
	# Top cap with the suction-cup mount marker.
	var cap := MeshInstance3D.new()
	cap.mesh = VoxelMat.get_box(Vector3(0.3, 0.12, 0.3))
	cap.material_override = outer_mat
	cap.position = Vector3(heater_x, heater_base_y + rod_h + 0.06, heater_z)
	c.add_child(cap)
	# Subtle warm glow. Tiny range so it doesn't bleed into the rest of
	# the tank — just a hint of heat near the rod.
	var glow := OmniLight3D.new()
	glow.light_color = Color8(255, 120, 60)
	glow.light_energy = 0.6
	glow.omni_range = 1.4
	glow.omni_attenuation = 2.4
	glow.position = Vector3(heater_x, heater_base_y + rod_h * 0.5, heater_z)
	c.add_child(glow)
	_heater_glow = glow
	_heater_world_pos = Vector3(heater_x, heater_base_y + rod_h * 0.5, heater_z)


# ---- Room environment ----
#
# Builds optional geometry around the tank — wooden desk surface, back
# wall, lamp, books, plant — based on TankConfig.environment_preset.
# The default "void" preset is a no-op (preserves the classic isolated-
# tank look). Other presets read their color palette from
# TankConfig.ENVIRONMENT_PRESETS so swapping in new themes is just a
# data change. Everything voxelizes through the same palette quantizer
# as the tank so the room feels of-a-piece, not pasted on.
func _build_room_environment() -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
	var preset_name: String = String(cfg.environment_preset)
	if preset_name == "void" or preset_name == "":
		return
	var preset: Dictionary = cfg.current_environment_profile()
	if preset.is_empty() or preset.get("label") == "Void (no room)":
		return

	var room := Node3D.new()
	room.name = "RoomEnvironment"
	add_child(room)

	# Resolve colors. Each preset stores RGB int arrays we convert to Color8.
	var desk_rgb: Array = preset.get("desk_color", [120, 90, 60])
	var wall_rgb: Array = preset.get("wall_color", [200, 190, 175])
	var accent_rgb: Array = preset.get("accent_color", [220, 165, 90])
	var light_rgb: Array = preset.get("light_color", [255, 235, 200])
	var desk_color: Color = Color8(desk_rgb[0], desk_rgb[1], desk_rgb[2])
	var wall_color: Color = Color8(wall_rgb[0], wall_rgb[1], wall_rgb[2])
	var accent_color: Color = Color8(accent_rgb[0], accent_rgb[1], accent_rgb[2])
	var light_color: Color = Color8(light_rgb[0], light_rgb[1], light_rgb[2])
	# Cache four shades of the desk colour so the surface reads as
	# organic wood grain instead of a 2-tone checkerboard. Hash-noise
	# below picks one of these per cell so the pattern looks irregular.
	# Use VoxelMat.make_room so the desk + wall fade toward the warm
	# haze colour with view distance — pushes the room geometry back
	# behind the tank visually.
	var haze_tint: Color = Color(
		light_color.r * 0.92 + 0.08,
		light_color.g * 0.86 + 0.06,
		light_color.b * 0.78 + 0.04)
	_room_haze_base = haze_tint
	var desk_mat: ShaderMaterial = VoxelMat.make_room(desk_color, 0.55, haze_tint)
	var desk_dark_mat: ShaderMaterial = VoxelMat.make_room(desk_color.darkened(0.18), 0.55, haze_tint)
	var desk_mid_mat: ShaderMaterial = VoxelMat.make_room(desk_color.darkened(0.08), 0.55, haze_tint)
	var desk_light_mat: ShaderMaterial = VoxelMat.make_room(desk_color.lightened(0.10), 0.55, haze_tint)
	var wall_mat: ShaderMaterial = VoxelMat.make_room(wall_color, 0.65, haze_tint)
	var accent_mat: ShaderMaterial = VoxelMat.make_room(accent_color, 0.50, haze_tint)

	# Desk surface. Three-ish-voxel-thick wooden slab the tank sits on,
	# extending out from the tank footprint on all sides so the bottom of
	# the glass reads as resting on a real surface, not levitating.
	var desk_y: float = -0.6
	var desk_half_w: float = TANK_HALF_W + 5.0
	var desk_half_d: float = TANK_HALF_D + 4.0
	var desk_thickness: float = 1.2
	# Build the desk as a 2D grid of "plank" voxels. Material per voxel is
	# picked by a hash of (ix, iz) running through four shade bands —
	# light, default, mid, dark — so the surface looks like irregular
	# wood grain instead of the previous rigid alternating checkerboard
	# (which read as a wallpaper or pink lattice in warmer presets).
	var plank_size: float = 0.7
	var nx: int = int(desk_half_w * 2.0 / plank_size) + 1
	var nz: int = int(desk_half_d * 2.0 / plank_size) + 1
	for ix in nx:
		for iz in nz:
			var px: float = -desk_half_w + (float(ix) + 0.5) * plank_size
			var pz: float = -desk_half_d + (float(iz) + 0.5) * plank_size
			# Hash-noise: cheap deterministic per-cell value in [0..1].
			var h: float = fposmod(
				sin(float(ix) * 12.9898 + float(iz) * 78.233) * 43758.5453, 1.0)
			var mat: Material
			if h < 0.18:
				mat = desk_dark_mat
			elif h < 0.46:
				mat = desk_mid_mat
			elif h < 0.78:
				mat = desk_mat
			else:
				mat = desk_light_mat
			var mi := MeshInstance3D.new()
			mi.mesh = VoxelMat.get_box(Vector3(plank_size * 0.96,
				desk_thickness, plank_size * 0.96))
			mi.material_override = mat
			mi.position = Vector3(px, desk_y - desk_thickness * 0.5, pz)
			room.add_child(mi)
	# Front lip of the desk: a slightly raised edge to suggest a real
	# table edge in front of the camera.
	for ix in nx:
		var px2: float = -desk_half_w + (float(ix) + 0.5) * plank_size
		var lip := MeshInstance3D.new()
		lip.mesh = VoxelMat.get_box(Vector3(plank_size * 0.96, 0.12, 0.2))
		lip.material_override = desk_dark_mat
		lip.position = Vector3(px2, desk_y + 0.02, desk_half_d - 0.1)
		room.add_child(lip)

	# Back wall. Stands behind the tank, extending up past the camera's
	# pitch range. Built as a flat grid of voxels for the same palette
	# coherence as the desk.
	var wall_z: float = -desk_half_d - 0.4
	var wall_half_w: float = desk_half_w + 1.0
	var wall_height: float = 16.0
	var wall_y_min: float = desk_y - 1.0
	var brick_h: float = 1.0
	var brick_w: float = 1.5
	var rows: int = int(wall_height / brick_h) + 1
	var cols: int = int(wall_half_w * 2.0 / brick_w) + 1
	
	# Wall cutout coordinates for window
	var include_window: bool = not not preset.get("include_window", false)
	var window_w_half: float = 3.5
	var window_h_half: float = 2.5
	var window_center_y: float = desk_y + 4.5
	
	# Wall shade variation. The previous (r*3 + col) % 5 pattern produced
	# visible diagonal stripes; we replace it with hash-noise + a
	# subtle vertical lightness gradient (darker near the floor, lighter
	# near the ceiling — simulates indirect light spilling down from a
	# room light above). The wall now reads as an actual painted surface.
	var wall_dim_mat: ShaderMaterial = VoxelMat.make_room(wall_color.darkened(0.10), 0.65, haze_tint)
	var wall_light_mat: ShaderMaterial = VoxelMat.make_room(wall_color.lightened(0.07), 0.65, haze_tint)
	for r in rows:
		for col in cols:
			var bx: float = -wall_half_w + (float(col) + 0.5) * brick_w
			var by: float = wall_y_min + (float(r) + 0.5) * brick_h

			if include_window:
				var brick_left: float = bx - brick_w * 0.5
				var brick_right: float = bx + brick_w * 0.5
				var brick_bottom: float = by - brick_h * 0.5
				var brick_top: float = by + brick_h * 0.5
				# If brick overlaps window rectangle, skip spawning it
				if brick_right > -window_w_half and brick_left < window_w_half and \
				   brick_top > (window_center_y - window_h_half) and brick_bottom < (window_center_y + window_h_half):
					continue
			# Hash-noise + vertical lightness gradient. h ∈ [0..1] picks
			# a shade; vfac (0 at floor, 1 at ceiling) biases brighter
			# voxels toward the top of the wall.
			var h: float = fposmod(
				sin(float(col) * 17.317 + float(r) * 39.713) * 12961.7, 1.0)
			var vfac: float = clampf(float(r) / float(maxi(1, rows - 1)), 0.0, 1.0)
			var biased: float = clampf(h + (vfac - 0.5) * 0.20, 0.0, 1.0)
			var bmat: Material
			if biased < 0.08:
				bmat = accent_mat       # rare warm accent brick
			elif biased < 0.40:
				bmat = wall_dim_mat
			elif biased < 0.82:
				bmat = wall_mat
			else:
				bmat = wall_light_mat
			var brick := MeshInstance3D.new()
			brick.mesh = VoxelMat.get_box(Vector3(brick_w * 0.96, brick_h * 0.96, 0.4))
			brick.material_override = bmat
			brick.position = Vector3(bx, by, wall_z)
			room.add_child(brick)

	# Build window frame/sky if active
	if include_window:
		_build_room_window(room, wall_z, wall_mat, desk_dark_mat, preset)

	# Soft warm room light from the side — simulates a window or lamp.
	var room_light := OmniLight3D.new()
	room_light.name = "RoomSideFill"
	room_light.light_color = light_color
	room_light.light_energy = 0.18
	room_light.omni_range = 36.0
	room_light.omni_attenuation = 1.6
	room_light.position = Vector3(desk_half_w + 2.0, desk_y + 6.0, wall_z + 4.0)
	room.add_child(room_light)
	_room_side_light = room_light

	# Tank-cast warm light — desk spill synced to fixture color in _process.
	var tank_spill := OmniLight3D.new()
	tank_spill.name = "TankSpill"
	tank_spill.light_color = Color(1.0, 0.92, 0.78)
	tank_spill.light_energy = 0.45
	tank_spill.omni_range = maxf(TANK_HALF_W, TANK_HALF_D) * 2.8 + 4.0
	tank_spill.omni_attenuation = 1.4
	tank_spill.shadow_enabled = false
	tank_spill.position = Vector3(0.0, desk_y + 0.05, 0.0)
	room.add_child(tank_spill)
	_room_tank_spill = tank_spill

	# Back-wall bounce — picks up reef blue / planted pink at night.
	var wall_bounce := OmniLight3D.new()
	wall_bounce.name = "TankWallBounce"
	wall_bounce.light_color = light_color
	wall_bounce.light_energy = 0.08
	wall_bounce.omni_range = desk_half_w * 1.6
	wall_bounce.omni_attenuation = 1.8
	wall_bounce.shadow_enabled = false
	wall_bounce.position = Vector3(0.0, desk_y + 4.5, wall_z + 1.2)
	room.add_child(wall_bounce)
	_room_wall_bounce = wall_bounce

	# Front desk rim — visible pool of fixture color on the surface at night.
	var desk_rim := SpotLight3D.new()
	desk_rim.name = "TankDeskRim"
	desk_rim.spot_range = maxf(TANK_HALF_W, TANK_HALF_D) * 2.2 + 3.0
	desk_rim.spot_angle = 68.0
	desk_rim.spot_attenuation = 1.2
	desk_rim.light_energy = 0.0
	desk_rim.shadow_enabled = false
	desk_rim.position = Vector3(0.0, desk_y + 0.15, TANK_HALF_D * 0.25)
	desk_rim.rotation_degrees = Vector3(-82.0, 0.0, 0.0)
	room.add_child(desk_rim)
	_room_desk_rim = desk_rim

	# Soft wash on the wall around the window from the tank at night.
	var window_glow := OmniLight3D.new()
	window_glow.name = "TankWindowGlow"
	window_glow.light_energy = 0.0
	window_glow.omni_range = desk_half_w * 1.2
	window_glow.omni_attenuation = 1.9
	window_glow.shadow_enabled = false
	window_glow.position = Vector3(0.0, desk_y + 4.2, wall_z + 0.6)
	room.add_child(window_glow)
	_room_window_glow = window_glow

	# Contact shadow under the tank — implemented by RECOLORING the desk
	# planks that fall inside the tank's footprint, NOT by adding a
	# separate layer of shadow voxels. The previous version laid down a
	# 6×6 grid of dark cells which from a low camera angle read as a
	# tiled mosaic of dark trapezoids ("weird reflections"). Recoloring
	# the existing planks keeps the desk seamless — the shadow IS the
	# desk grain at that location.
	var shadow_r2: float = (maxf(TANK_HALF_W, TANK_HALF_D) + 0.35) * (maxf(TANK_HALF_W, TANK_HALF_D) + 0.35)
	var shadow_mat: ShaderMaterial = VoxelMat.make_room(
		Color(desk_color.r * 0.45, desk_color.g * 0.42, desk_color.b * 0.40),
		0.30, haze_tint)
	# Edge-softened shadow: at the centre the plank is the full shadow
	# colour; near the radius edge we lerp back toward the original
	# plank material. We accomplish this by walking the desk children
	# we just spawned and substituting materials inside the footprint.
	# The desk planks are the last children we added before this — walk
	# `room`'s children backward until we hit a non-plank child.
	for ci in range(room.get_child_count() - 1, -1, -1):
		var pn: Node = room.get_child(ci)
		if not (pn is MeshInstance3D):
			break
		var pp: Vector3 = (pn as MeshInstance3D).position
		# Only top-of-desk planks (the front lip sits at desk_y + 0.02,
		# planks sit at desk_y - desk_thickness * 0.5).
		if absf(pp.y - (desk_y - desk_thickness * 0.5)) > 0.05:
			continue
		var d2: float = pp.x * pp.x + pp.z * pp.z
		if d2 < shadow_r2:
			# Soft edge: keep full shadow inside 0.85 of the radius;
			# fade back to a mid-shade in the outer 0.15.
			(pn as MeshInstance3D).material_override = shadow_mat

	# Room dust motes. Sparse slow-drifting particles in the air above
	# the desk for ambient atmosphere. Distinct from the in-beam motes
	# inside the tank (those live INSIDE the god-ray cones); these are
	# in the room volume and visible against the wall + ceiling.
	var room_motes := GPUParticles3D.new()
	room_motes.name = "RoomDustMotes"
	room_motes.amount = 18
	room_motes.lifetime = 14.0
	room_motes.preprocess = room_motes.lifetime * 0.5
	room_motes.randomness = 0.55
	room_motes.local_coords = false
	room_motes.visibility_aabb = AABB(
		Vector3(-desk_half_w, desk_y, wall_z),
		Vector3(desk_half_w * 2.0, 12.0, desk_half_d * 2.0 + 4.0))
	room_motes.position = Vector3(0.0, desk_y + 5.0, wall_z + desk_half_d)
	var room_pm := ParticleProcessMaterial.new()
	room_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	room_pm.emission_box_extents = Vector3(desk_half_w, 3.5, desk_half_d)
	# Very gentle downdrift — room dust slowly settles. Turbulence
	# makes the path organic.
	room_pm.gravity = Vector3(0.0, -0.02, 0.0)
	room_pm.initial_velocity_min = 0.01
	room_pm.initial_velocity_max = 0.05
	room_pm.direction = Vector3(0.0, -1.0, 0.0)
	room_pm.spread = 90.0
	room_pm.turbulence_enabled = true
	room_pm.turbulence_noise_strength = 0.08
	room_pm.turbulence_noise_speed_random = 0.4
	room_pm.turbulence_noise_scale = 1.4
	room_pm.scale_min = 0.025
	room_pm.scale_max = 0.060
	var room_alpha := CurveTexture.new()
	var rac := Curve.new()
	rac.add_point(Vector2(0.0, 0.0))
	rac.add_point(Vector2(0.15, 0.45))
	rac.add_point(Vector2(0.75, 0.40))
	rac.add_point(Vector2(1.0, 0.0))
	room_alpha.curve = rac
	room_pm.alpha_curve = room_alpha
	room_motes.process_material = room_pm
	var rmote_mesh := SphereMesh.new()
	rmote_mesh.radius = 0.018
	rmote_mesh.height = 0.036
	rmote_mesh.radial_segments = 4
	rmote_mesh.rings = 2
	rmote_mesh.material = VoxelMat.make_bubble(Color(0.98, 0.92, 0.80, 0.38))
	room_motes.draw_pass_1 = rmote_mesh
	room.add_child(room_motes)

	# Lamp (preset-controlled). Tall thin stand + a glowing shade on the
	# left side of the desk, just outside the tank's footprint.
	if preset.get("include_lamp", false):
		_build_room_lamp(room, Vector3(-desk_half_w + 2.0, desk_y, -desk_half_d + 1.6),
			accent_color, light_color)

	# Book stack on the right side of the desk.
	if preset.get("include_books", false):
		_build_room_books(room, Vector3(desk_half_w - 2.4, desk_y + 0.05,
			-desk_half_d + 1.4))

	# Small house plant in front of the wall, to one side.
	if preset.get("include_plant", false):
		_build_room_plant(room, Vector3(-desk_half_w + 2.0, desk_y + 0.05,
			-desk_half_d + 2.6))

	# Cozy Steaming Coffee/Tea Mug
	if preset.get("include_mug", false):
		_build_room_mug(room, Vector3(desk_half_w - 3.4, desk_y, -desk_half_d + 1.8), accent_color)

	# Vintage Alarm Clock (Functioning)
	if preset.get("include_clock", false):
		_build_room_clock(room, Vector3(desk_half_w - 1.2, desk_y, -desk_half_d + 1.8), accent_color)

	# Interactive Record Player
	if preset.get("include_record_player", false):
		_build_room_record_player(room, Vector3(-desk_half_w + 4.2, desk_y, -desk_half_d + 1.8))

	# Dynamic Lava Lamp
	if preset.get("include_lava_lamp", false):
		_build_room_lava_lamp(room, Vector3(-desk_half_w + 2.0, desk_y, -desk_half_d + 1.6),
			Color8(160, 160, 165), accent_color)



func _build_room_window(parent: Node3D, wall_z: float, _wall_mat: Material,
		frame_mat: Material, preset: Dictionary) -> void:
	var desk_y: float = -0.6
	_room_window_state = WorldRoomBuilder.build_window(
		parent, wall_z, desk_y, preset, frame_mat)
	_room_sky_mat = _room_window_state.get("sky_mat", null)
	_room_stars.clear()
	for s in _room_window_state.get("stars", []):
		if s is MeshInstance3D:
			_room_stars.append(s)


func _build_room_mug(parent: Node3D, base_pos: Vector3, ceramic_color: Color) -> void:
	var mug_mat := VoxelMat.make(ceramic_color)
	
	# Mug Body
	var body := MeshInstance3D.new()
	body.mesh = VoxelMat.get_box(Vector3(0.35, 0.4, 0.35))
	body.material_override = mug_mat
	body.position = base_pos + Vector3(0.0, 0.2, 0.0)
	parent.add_child(body)
	
	# Mug Handle
	var handle := MeshInstance3D.new()
	handle.mesh = VoxelMat.get_box(Vector3(0.1, 0.22, 0.08))
	handle.material_override = mug_mat
	handle.position = base_pos + Vector3(0.2, 0.2, 0.0)
	parent.add_child(handle)
	
	# Coffee Liquid
	var liquid := MeshInstance3D.new()
	liquid.mesh = VoxelMat.get_box(Vector3(0.28, 0.02, 0.28))
	liquid.material_override = VoxelMat.make(Color8(65, 40, 25)) # coffee brown
	liquid.position = base_pos + Vector3(0.0, 0.38, 0.0)
	parent.add_child(liquid)
	
	# Steam Particles: GPUParticles3D
	var steam := GPUParticles3D.new()
	steam.amount = 5
	steam.lifetime = 1.8
	steam.preprocess = 0.9
	steam.local_coords = false
	steam.position = base_pos + Vector3(0.0, 0.4, 0.0)
	
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.08, 1.0, 0.0).normalized()
	pm.initial_velocity_min = 0.18
	pm.initial_velocity_max = 0.3
	pm.gravity = Vector3(0, 0.08, 0)
	pm.spread = 10.0
	pm.scale_min = 0.8
	pm.scale_max = 1.3
	steam.process_material = pm
	
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.05, 0.05)
	bm.material = VoxelMat.make(Color8(230, 230, 230))
	steam.draw_pass_1 = bm
	parent.add_child(steam)


func _build_room_clock(parent: Node3D, base_pos: Vector3, clock_color: Color) -> void:
	var body_mat := VoxelMat.make(clock_color)
	var metal_mat := VoxelMat.make(Color8(165, 165, 170))
	var face_mat := VoxelMat.make(Color8(240, 238, 225))
	var hand_mat := VoxelMat.make(Color8(30, 30, 32))
	
	# Stand Support
	var stand := MeshInstance3D.new()
	stand.mesh = VoxelMat.get_box(Vector3(0.3, 0.05, 0.2))
	stand.material_override = metal_mat
	stand.position = base_pos + Vector3(0, 0.025, 0)
	parent.add_child(stand)
	
	# Clock Body
	var body := MeshInstance3D.new()
	body.mesh = VoxelMat.get_box(Vector3(0.46, 0.46, 0.16))
	body.material_override = body_mat
	body.position = base_pos + Vector3(0, 0.28, 0)
	parent.add_child(body)
	
	# Twin Bells
	var bell_l := MeshInstance3D.new()
	bell_l.mesh = VoxelMat.get_box(Vector3(0.12, 0.12, 0.12))
	bell_l.material_override = metal_mat
	bell_l.position = base_pos + Vector3(-0.16, 0.54, 0)
	parent.add_child(bell_l)
	
	var bell_r := MeshInstance3D.new()
	bell_r.mesh = VoxelMat.get_box(Vector3(0.12, 0.12, 0.12))
	bell_r.material_override = metal_mat
	bell_r.position = base_pos + Vector3(0.16, 0.54, 0)
	parent.add_child(bell_r)
	
	# Face Plate
	var face := MeshInstance3D.new()
	face.mesh = VoxelMat.get_box(Vector3(0.38, 0.38, 0.02))
	face.material_override = face_mat
	face.position = base_pos + Vector3(0, 0.28, 0.09)
	parent.add_child(face)
	
	# Hour Hand Pivot
	_room_clock_hour_pivot = Node3D.new()
	_room_clock_hour_pivot.position = base_pos + Vector3(0, 0.28, 0.102)
	parent.add_child(_room_clock_hour_pivot)
	
	var hr_mesh := MeshInstance3D.new()
	hr_mesh.mesh = VoxelMat.get_box(Vector3(0.04, 0.12, 0.015))
	hr_mesh.material_override = hand_mat
	hr_mesh.position = Vector3(0, 0.06, 0)
	_room_clock_hour_pivot.add_child(hr_mesh)
	
	# Minute Hand Pivot
	_room_clock_min_pivot = Node3D.new()
	_room_clock_min_pivot.position = base_pos + Vector3(0, 0.28, 0.104)
	parent.add_child(_room_clock_min_pivot)
	
	var min_mesh := MeshInstance3D.new()
	min_mesh.mesh = VoxelMat.get_box(Vector3(0.03, 0.17, 0.015))
	min_mesh.material_override = hand_mat
	min_mesh.position = Vector3(0, 0.085, 0)
	_room_clock_min_pivot.add_child(min_mesh)


func _build_room_record_player(parent: Node3D, base_pos: Vector3) -> void:
	var wood_mat := VoxelMat.make(Color8(95, 60, 45))
	var platter_mat := VoxelMat.make(Color8(160, 160, 165))
	var vinyl_mat := VoxelMat.make(Color8(28, 28, 30))
	var label_mat := VoxelMat.make(Color8(210, 175, 55))
	var arm_mat := VoxelMat.make(Color8(120, 120, 125))
	
	# Base cabinet
	var base := MeshInstance3D.new()
	base.mesh = VoxelMat.get_box(Vector3(0.75, 0.18, 0.75))
	base.material_override = wood_mat
	base.position = base_pos + Vector3(0.0, 0.09, 0.0)
	parent.add_child(base)
	
	# Platter
	var platter := MeshInstance3D.new()
	platter.mesh = VoxelMat.get_box(Vector3(0.60, 0.03, 0.60))
	platter.material_override = platter_mat
	platter.position = base_pos + Vector3(0.0, 0.195, 0.0)
	parent.add_child(platter)
	
	# Vinyl Record
	_room_record_disc = MeshInstance3D.new()
	_room_record_disc.mesh = VoxelMat.get_box(Vector3(0.55, 0.02, 0.55))
	_room_record_disc.material_override = vinyl_mat
	_room_record_disc.position = base_pos + Vector3(0.0, 0.22, 0.0)
	parent.add_child(_room_record_disc)
	
	# Spindle/Center Label
	var label := MeshInstance3D.new()
	label.mesh = VoxelMat.get_box(Vector3(0.16, 0.005, 0.16))
	label.material_override = label_mat
	label.position = Vector3(0, 0.011, 0)
	_room_record_disc.add_child(label)
	
	# Tone Arm
	var arm_base := MeshInstance3D.new()
	arm_base.mesh = VoxelMat.get_box(Vector3(0.08, 0.15, 0.08))
	arm_base.material_override = arm_mat
	arm_base.position = base_pos + Vector3(0.24, 0.255, -0.24)
	parent.add_child(arm_base)
	
	var arm_bar := MeshInstance3D.new()
	arm_bar.mesh = VoxelMat.get_box(Vector3(0.04, 0.04, 0.35))
	arm_bar.material_override = arm_mat
	arm_bar.position = base_pos + Vector3(0.18, 0.315, -0.1)
	arm_bar.rotation.y = -0.3
	parent.add_child(arm_bar)


func _build_room_lava_lamp(parent: Node3D, base_pos: Vector3,
		metal_color: Color, neon_color: Color) -> void:
	var metal_mat := VoxelMat.make(metal_color)
	var neon_mat := VoxelMat.make(neon_color)
	
	# Base cap
	var base_cap := MeshInstance3D.new()
	base_cap.mesh = VoxelMat.get_box(Vector3(0.35, 0.24, 0.35))
	base_cap.material_override = metal_mat
	base_cap.position = base_pos + Vector3(0, 0.12, 0)
	parent.add_child(base_cap)
	
	# Top cap
	var top_cap := MeshInstance3D.new()
	top_cap.mesh = VoxelMat.get_box(Vector3(0.24, 0.12, 0.24))
	top_cap.material_override = metal_mat
	top_cap.position = base_pos + Vector3(0, 0.85, 0)
	parent.add_child(top_cap)
	
	# Corner structural rods
	var rod_positions := [
		Vector3(-0.14, 0.51, -0.14),
		Vector3(0.14, 0.51, -0.14),
		Vector3(-0.14, 0.51, 0.14),
		Vector3(0.14, 0.51, 0.14),
	]
	var rod_mat := VoxelMat.make(Color8(120, 120, 125))
	for r_pos in rod_positions:
		var rod := MeshInstance3D.new()
		rod.mesh = VoxelMat.get_box(Vector3(0.03, 0.58, 0.03))
		rod.material_override = rod_mat
		rod.position = base_pos + r_pos
		parent.add_child(rod)
		
	# Static wax pools
	var bottom_pool := MeshInstance3D.new()
	bottom_pool.mesh = VoxelMat.get_box(Vector3(0.24, 0.06, 0.24))
	bottom_pool.material_override = neon_mat
	bottom_pool.position = base_pos + Vector3(0, 0.25, 0)
	parent.add_child(bottom_pool)
	
	var top_pool := MeshInstance3D.new()
	top_pool.mesh = VoxelMat.get_box(Vector3(0.20, 0.06, 0.20))
	top_pool.material_override = neon_mat
	top_pool.position = base_pos + Vector3(0, 0.76, 0)
	parent.add_child(top_pool)
	
	# Floating Blobs
	_room_lava_lamp_blobs.clear()
	
	var blob1 := MeshInstance3D.new()
	blob1.mesh = VoxelMat.get_box(Vector3(0.16, 0.18, 0.16))
	blob1.material_override = neon_mat
	blob1.position = base_pos + Vector3(0, 0.35, 0)
	parent.add_child(blob1)
	_room_lava_lamp_blobs.append(blob1)
	
	var blob2 := MeshInstance3D.new()
	blob2.mesh = VoxelMat.get_box(Vector3(0.14, 0.15, 0.14))
	blob2.material_override = neon_mat
	blob2.position = base_pos + Vector3(0, 0.65, 0)
	parent.add_child(blob2)
	_room_lava_lamp_blobs.append(blob2)
	
	# OmniLight3D
	_room_lava_lamp_light = OmniLight3D.new()
	_room_lava_lamp_light.light_color = neon_color
	_room_lava_lamp_light.light_energy = 0.25
	_room_lava_lamp_light.omni_range = 6.0
	_room_lava_lamp_light.omni_attenuation = 2.0
	_room_lava_lamp_light.position = base_pos + Vector3(0, 0.5, 0)
	parent.add_child(_room_lava_lamp_light)


func _build_room_lamp(parent: Node3D, base_pos: Vector3,

		accent: Color, light_col: Color) -> void:
	var stand_mat: ShaderMaterial = VoxelMat.make(Color8(45, 40, 38))
	var shade_mat: ShaderMaterial = VoxelMat.make(accent.lightened(0.15))
	# Base disc.
	var base := MeshInstance3D.new()
	base.mesh = VoxelMat.get_box(Vector3(0.6, 0.12, 0.6))
	base.material_override = stand_mat
	base.position = base_pos + Vector3(0, 0.06, 0)
	parent.add_child(base)
	# Stem.
	var stem := MeshInstance3D.new()
	stem.mesh = VoxelMat.get_box(Vector3(0.16, 2.2, 0.16))
	stem.material_override = stand_mat
	stem.position = base_pos + Vector3(0, 1.2, 0)
	parent.add_child(stem)
	# Shade (slightly conical via two stacked boxes — voxel-aesthetic friendly).
	var shade_bottom := MeshInstance3D.new()
	shade_bottom.mesh = VoxelMat.get_box(Vector3(0.95, 0.35, 0.95))
	shade_bottom.material_override = shade_mat
	shade_bottom.position = base_pos + Vector3(0, 2.45, 0)
	parent.add_child(shade_bottom)
	var shade_top := MeshInstance3D.new()
	shade_top.mesh = VoxelMat.get_box(Vector3(0.7, 0.25, 0.7))
	shade_top.material_override = shade_mat
	shade_top.position = base_pos + Vector3(0, 2.78, 0)
	parent.add_child(shade_top)
	# Lamp light — small omni for the warm pool of light at the base.
	var lamp_light := OmniLight3D.new()
	lamp_light.light_color = light_col
	lamp_light.light_energy = 0.25
	lamp_light.omni_range = 8.0
	lamp_light.omni_attenuation = 2.4
	lamp_light.position = base_pos + Vector3(0, 2.55, 0)
	parent.add_child(lamp_light)


func _build_room_books(parent: Node3D, base_pos: Vector3) -> void:
	# A short stack of 3-4 voxel "books," each a different palette color.
	var colors := [
		Color8(140, 70, 80),   # dusty red
		Color8(80, 100, 130),  # blue-gray
		Color8(180, 140, 80),  # tan
		Color8(70, 90, 70),    # forest green
	]
	var n: int = randi_range(3, 4)
	var y: float = base_pos.y
	for i in n:
		var col: Color = colors[i % colors.size()]
		var w: float = randf_range(0.7, 1.0)
		var h: float = randf_range(0.28, 0.4)
		var d: float = randf_range(0.55, 0.7)
		var b := MeshInstance3D.new()
		b.mesh = VoxelMat.get_box(Vector3(w, h, d))
		b.material_override = VoxelMat.make(col)
		# Slight per-book offset so the stack isn't a ruler-straight column.
		b.position = base_pos + Vector3(randf_range(-0.04, 0.04),
			y - base_pos.y + h * 0.5, randf_range(-0.06, 0.06))
		b.rotation.y = randf_range(-0.06, 0.06)
		parent.add_child(b)
		y += h


func _build_room_plant(parent: Node3D, base_pos: Vector3) -> void:
	# A small terracotta pot with a clump of dark-green voxel leaves on top.
	var pot_mat: ShaderMaterial = VoxelMat.make(Color8(170, 90, 65))
	var pot := MeshInstance3D.new()
	pot.mesh = VoxelMat.get_box(Vector3(0.85, 0.6, 0.85))
	pot.material_override = pot_mat
	pot.position = base_pos + Vector3(0, 0.3, 0)
	parent.add_child(pot)
	# Soil top — thin dark band at the rim.
	var soil := MeshInstance3D.new()
	soil.mesh = VoxelMat.get_box(Vector3(0.7, 0.08, 0.7))
	soil.material_override = VoxelMat.make(Color8(40, 30, 24))
	soil.position = base_pos + Vector3(0, 0.62, 0)
	parent.add_child(soil)
	# Leaves — half a dozen short voxel clusters in a fan.
	var leaf_mats := [
		VoxelMat.make(Color8(64, 110, 60)),
		VoxelMat.make(Color8(48, 90, 50)),
		VoxelMat.make(Color8(80, 130, 72)),
	]
	for i in 7:
		var ang: float = float(i) / 7.0 * TAU
		var lean_x: float = cos(ang) * 0.18
		var lean_z: float = sin(ang) * 0.18
		var height: float = randf_range(0.5, 0.95)
		var leaf := MeshInstance3D.new()
		leaf.mesh = VoxelMat.get_box(Vector3(0.18, height, 0.12))
		leaf.material_override = leaf_mats[i % leaf_mats.size()]
		leaf.position = base_pos + Vector3(lean_x, 0.65 + height * 0.5, lean_z)
		leaf.rotation = Vector3(cos(ang) * 0.4, ang, sin(ang) * 0.4)
		parent.add_child(leaf)


func _spawn_mulm_layer() -> void:
	# Mulm = soft dark detritus on the substrate surface. Grows as waste settles.
	var container := Node3D.new()
	container.name = "Mulm"
	add_child(container)
	var initial_n: int = 55 if TANK_SHAPE == "sphere" else 40
	for i in initial_n:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.20, 0.07, 0.20)
		mi.mesh = bm
		var m_xz: Vector2 = _sample_substrate_xz(0.2, 0.44)
		mi.position = Vector3(m_xz.x, column_surface_y(m_xz.x, m_xz.y) + 0.05, m_xz.y)
		mi.material_override = VoxelMat.make(Color8(34, 26, 18))
		container.add_child(mi)
		_mulm_voxels.append(mi)
	_film_root = Node3D.new()
	_film_root.name = "SubstrateFilm"
	add_child(_film_root)
	for i in 18:
		_spawn_substrate_film_voxel()


# Apply a deterministic biofilm tint pattern across the driftwood voxels.
# Uses each voxel's index hash modulo a denominator that shrinks with
# biofilm_progress — at 0 nothing is tinted; at 0.65 roughly two-thirds
# of voxels carry the cream/white biofilm tint. Deterministic so the
# pattern doesn't shimmer between updates (a voxel that's tinted at
# 0.40 stays tinted at 0.65).
#
# We can't use instance_shader_parameter — that allocates a per-instance
# slot in the global-shader-params buffer, and with thousands of voxels
# the buffer overflows. Instead duplicate the material per tinted voxel.
# Biofilm only touches ~30-50 driftwood voxels max, so the per-tinted-
# voxel material cost is negligible.
func _apply_biofilm_tints() -> void:
	if _driftwood_voxels.is_empty():
		return
	var cream: Color = Color(1.28, 1.22, 1.10)  # warm-white biofilm (mid+upper logs)
	# Green/black algae tone for the substrate-joint band. Real driftwood
	# carries a stripe of moss + algae where it meets the gravel — the
	# wood stays damp there, light scrapes the bottom, and grazers can't
	# reach it as easily. Cream biofilm dominates higher up.
	var algae_tint: Color = Color(0.55, 0.86, 0.52)
	# Higher progress → smaller denominator → more voxels tinted.
	# At progress=0.0, denom≈20 → ~5% tinted.
	# At progress=0.65, denom≈2 → ~half tinted.
	var denom: int = maxi(1, int(round(20.0 - biofilm_progress * 28.0)))
	# Joint band: voxels within JOINT_BAND of substrate top get the green
	# algae bias. Outside it, normal cream biofilm distribution.
	const JOINT_BAND: float = 0.6
	for i in _driftwood_voxels.size():
		var vx: MeshInstance3D = _driftwood_voxels[i]
		if not is_instance_valid(vx):
			continue
		var dy: float = vx.global_position.y - SUBSTRATE_DEPTH
		var in_joint: bool = dy < JOINT_BAND
		# Inside the joint band, double the tint density (smaller denom)
		# so the dark green stripe reads as dense moss/algae.
		var local_denom: int = maxi(1, int(denom / 2.0)) if in_joint else denom
		var tinted: bool = (hash(i * 73 + 13) % local_denom) == 0
		if tinted:
			var t_progress: float = clampf(biofilm_progress / 0.65, 0.0, 1.0)
			var t: Color
			if in_joint:
				# Lerp from base (no tint) toward algae color. Strength is
				# proportional to how close to the substrate the voxel sits
				# AND to overall biofilm progress.
				var band_w: float = 1.0 - clampf(dy / JOINT_BAND, 0.0, 1.0)
				t = Color(1, 1, 1).lerp(algae_tint, t_progress * (0.55 + 0.45 * band_w))
			else:
				t = Color(1, 1, 1).lerp(cream, t_progress)
			_apply_driftwood_biofilm(vx, t)
		else:
			_clear_driftwood_biofilm(vx)


func _apply_driftwood_wet_lines() -> void:
	for vx in _driftwood_voxels:
		if not is_instance_valid(vx):
			continue
		var y: float = vx.global_position.y
		if absf(y - WATER_HEIGHT) > 0.38:
			continue
		var sm: ShaderMaterial = vx.material_override as ShaderMaterial
		if sm == null:
			continue
		var orig: Color
		if vx.has_meta("base_albedo"):
			var stored: Variant = vx.get_meta("base_albedo")
			orig = stored as Color if stored is Color else Color.WHITE
		else:
			orig = VoxelMat.read_albedo(sm)
			vx.set_meta("base_albedo", orig)
		var wet: float = 1.0 - smoothstep(0.0, 0.35, absf(y - WATER_HEIGHT))
		sm.set_shader_parameter("albedo", orig.lerp(orig.darkened(0.22), wet * 0.65))


func _apply_driftwood_biofilm(vx: MeshInstance3D, tint: Color) -> void:
	var sm: ShaderMaterial = vx.material_override as ShaderMaterial
	if sm == null:
		return
	var orig: Color
	if vx.has_meta("base_albedo"):
		var stored: Variant = vx.get_meta("base_albedo")
		orig = stored as Color if stored is Color else Color.WHITE
	else:
		orig = VoxelMat.read_albedo(sm)
		vx.set_meta("base_albedo", orig)
	if not vx.has_meta("tint_mat"):
		vx.material_override = sm.duplicate() as ShaderMaterial
		vx.set_meta("tint_mat", true)
	(vx.material_override as ShaderMaterial).set_shader_parameter(
		"albedo", orig * tint)


func _clear_driftwood_biofilm(vx: MeshInstance3D) -> void:
	if not vx.has_meta("tint_mat"):
		return
	var stored: Variant = vx.get_meta("base_albedo")
	var orig: Color = stored as Color if stored is Color else Color.WHITE
	vx.material_override = VoxelMat.make_substrate_caustic(orig)
	vx.remove_meta("tint_mat")


# Spawn a brief dust burst at `pos` — 4-5 tiny dark voxels that puff up
# and outward, fading via Tween over ~1.4 seconds. Called from fish.gd
# when a shuffle-pattern fish (cory, mudsifter) starts a sift, layered
# on top of the persistent mulm voxel that already drops there. Sells
# the "kicked up the substrate" moment that the static voxel alone can't.
func spawn_substrate_dust(pos: Vector3) -> void:
	var container := get_node_or_null("Mulm")
	if container == null:
		return
	# Cap per-burst at 5 voxels and global concurrent dust at ~30 to keep
	# the scene clean during a school of cory all sifting at once.
	if container.get_child_count() > 175:
		return
	var n: int = randi_range(3, 5)
	for i in n:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.07, 0.07, 0.07)
		mi.mesh = bm
		mi.material_override = VoxelMat.make(Color8(38, 30, 22))
		# Random spread around the dig point. Slight upward bias so the
		# burst reads as "puffing up" not "spilling sideways."
		var spread := Vector3(
			randf_range(-0.18, 0.18),
			randf_range(0.02, 0.10),
			randf_range(-0.18, 0.18),
		)
		mi.position = clamp_xyz_in_tank(pos + spread, 0.25, 0.06)
		container.add_child(mi)
		# Tween: rise 0.25 units further + drift outward + shrink + free.
		var rise: Vector3 = mi.position + Vector3(
			spread.x * 1.5, 0.25, spread.z * 1.5)
		var tw: Tween = create_tween().set_parallel(true)
		tw.tween_property(mi, "position", rise, 1.4) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3(0.2, 0.2, 0.2), 1.4) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(mi.queue_free)


# Called by sim_driver when a waste particle settles. Mulm depth scales with
# tank volume instead of a fixed voxel count.
func add_mulm_voxel(pos: Vector3) -> void:
	if _mulm_voxels.size() >= _mulm_carrying_capacity():
		return
	var container := get_node_or_null("Mulm")
	if container == null:
		return
	# Detritus settling (#12): nudge toward the lower of nearby spots so mulm
	# pools in dug hollows / leaf-litter beds the way real detritus collects in
	# the low points of the bed instead of spreading evenly.
	var best_y: float = column_surface_y(pos.x, pos.z)
	for off in [Vector3(0.7, 0, 0), Vector3(-0.7, 0, 0), Vector3(0, 0, 0.7), Vector3(0, 0, -0.7)]:
		var sy: float = column_surface_y(pos.x + off.x, pos.z + off.z)
		if sy < best_y - 0.05:
			best_y = sy
			pos = Vector3(pos.x + off.x, pos.y, pos.z + off.z)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.20, 0.07, 0.20)
	mi.mesh = bm
	var clamped: Vector3 = clamp_xyz_in_tank(
		Vector3(pos.x, column_surface_y(pos.x, pos.z) + 0.05, pos.z), 0.25, 0.08)
	mi.position = clamped
	var corner_dark: float = 0.0
	if not is_inside_tank(clamped.x, clamped.z, 1.2, clamped.y):
		corner_dark = 0.15
	var flow_shade: float = clampf(absf(clamped.x) / maxf(TANK_HALF_W, 0.1), 0.0, 1.0) * 0.08
	var mulm_col := Color8(34, 26, 18).darkened(corner_dark + flow_shade)
	mi.material_override = VoxelMat.make(mulm_col)
	container.add_child(mi)
	_mulm_voxels.append(mi)
	if substrate_grid != null:
		substrate_grid.add_at(
			Vector3(clamped.x, SUBSTRATE_DEPTH, clamped.z), 0.0035)


func add_root_tab(pos: Vector3) -> void:
	# Root tab (#14): a slow-release fertilizer pellet pushed into the bed gives
	# a local nutrient bump so sand / inert-gravel tanks can keep root-feeders
	# alive instead of slowly losing them.
	if substrate_grid == null:
		return
	substrate_grid.add_root_tab_at(Vector3(pos.x, SUBSTRATE_DEPTH, pos.z), 1.4)
	if has_method("spawn_substrate_dust"):
		spawn_substrate_dust(Vector3(pos.x, column_surface_y(pos.x, pos.z), pos.z))


func tint_substrate_cell(x: float, z: float, _color: Color, strength: float) -> void:
	if substrate_grid == null or strength <= 0.001:
		return
	substrate_grid.add_at(Vector3(x, SUBSTRATE_DEPTH, z), 0.001 * strength)


func begin_screenshot_boost(duration: float = 3.0) -> void:
	if _visuals != null:
		_visuals.begin_screenshot_boost(duration)


func get_water_surface_y() -> float:
	return WATER_HEIGHT


func _film_carrying_capacity() -> int:
	var bloom: float = float(sim.bloom_intensity) if sim != null else 0.0
	var nutrients: float = 0.0
	if substrate_grid != null:
		nutrients = clampf(substrate_grid.total_above_baseline() / 8.0, 0.0, 1.0)
	elif sim != null and sim.substrate != null:
		nutrients = clampf(sim.substrate.total_above_baseline() / 8.0, 0.0, 1.0)
	return maxi(8, int(
		biofilm_progress * 90.0 + bloom * 70.0 + float(_mulm_voxels.size()) * 0.35
		+ nutrients * 45.0 + _tank_volume_proxy() * 0.15))


func _spawn_substrate_film_voxel() -> void:
	if _film_root == null:
		return
	var xz: Vector2 = _sample_substrate_xz(0.22, 0.46)
	if _is_hardscape_occupied(xz.x, xz.y, 0.35):
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.22, 0.04, 0.22)
	mi.mesh = bm
	mi.position = Vector3(xz.x, column_surface_y(xz.x, xz.y) + 0.08, xz.y)
	var bloom: float = float(sim.bloom_intensity) if sim != null else 0.0
	var green: Color = Color8(72, 118, 58)
	var brown: Color = Color8(88, 72, 44)
	var col: Color = green.lerp(brown, clampf(biofilm_progress * 0.6 + bloom * 0.35, 0.0, 1.0))
	col = col.lerp(Color8(140, 165, 95), bloom * 0.25)
	mi.material_override = VoxelMat.make(col)
	_film_root.add_child(mi)
	_film_voxels.append(mi)


func _maintain_substrate_film(sdt: float) -> void:
	_film_maintain_t = maxf(0.0, _film_maintain_t - sdt)
	if _film_maintain_t > 0.0:
		return
	_film_maintain_t = 1.4
	var target: int = _film_carrying_capacity()
	# Prune excess when the tank clears (post-crash or heavy grazing).
	while _film_voxels.size() > target + 6:
		var old: MeshInstance3D = _film_voxels.pop_back()
		if is_instance_valid(old):
			old.queue_free()
	var deficit: int = target - _film_voxels.size()
	var to_spawn: int = mini(deficit, 4)
	for i in to_spawn:
		_spawn_substrate_film_voxel()


func _maybe_walstad_understory() -> void:
	# Slow carpet + moss recruitment on open substrate — especially bowl rims.
	if plants_root == null or sim == null:
		return
	var plant_n: int = sim.plants.size()
	var density_target: int = maxi(24, int(_tank_volume_proxy() * 0.55))
	if plant_n >= density_target * 2:
		return
	var need_fill: bool = plant_n < int(density_target * 0.72)
	if not need_fill and randf() > 0.35:
		return
	var carpet_ramp: Array = [
		Color8(40, 90, 35), Color8(60, 122, 52), Color8(82, 152, 70),
		Color8(110, 180, 92), Color8(145, 205, 118), Color8(180, 225, 145),
	]
	var cfg: Dictionary = {
		"max_height": _rng.randi_range(3, 7),
		"growth_rate": randf_range(0.24, 0.38),
		"sway_amplitude": 0.05,
		"leaf_form": "needle",
		"leaf_length": 3,
		"max_roots": 3,
	}
	var n_spawn: int = 1 if need_fill else 1
	if TANK_SHAPE == "sphere":
		n_spawn = _rng.randi_range(1, 3)
	for i in n_spawn:
		var xz: Vector2 = _sample_substrate_xz(0.28, 0.52, 0.22)
		if _is_hardscape_occupied(xz.x, xz.y, 0.4):
			continue
		spawn_seedling(
			spawn_position_on_floor(xz.x, xz.y),
			carpet_ramp, _rng.randi_range(1, 4), cfg)


# ---- Microfauna swarm ------------------------------------------------------
# Seeds the tank with N tiny drifting copepod / daphnia-like entities. Called
# once at end of _ready to fill the swarm immediately; _process then keeps
# it topped up via _maintain_microfauna() as individuals age out or get
# pulled into the filter intake.
func _spawn_initial_microfauna(count: int) -> void:
	# The MicrofaunaSwarm self-populates toward its target (fast cold-start fill,
	# then a trickle), so we just seed a visible base + set the target capacity.
	if microfauna_root == null:
		return
	microfauna_root.set_target(count)
	microfauna_root.seed(mini(count, 16))


# Wriggle worms — proportional to current mulm carpet. As mulm accumulates,
# more worms appear. As mulm caps out, the worm count caps too. Aged-out
# worms (via _process in the WriggleWorm script) are auto-replaced here.
func _spawn_one_wriggle() -> void:
	if wriggle_root == null:
		return
	if _mulm_voxels.is_empty():
		return
	# Pick a random existing mulm voxel and place the worm near it.
	var idx: int = randi() % _mulm_voxels.size()
	var anchor: Node3D = _mulm_voxels[idx]
	if not is_instance_valid(anchor):
		return
	var p: Vector3 = anchor.position
	# Small offset so the worm doesn't sit dead-center on the mulm voxel.
	p.x += randf_range(-0.12, 0.12)
	p.z += randf_range(-0.12, 0.12)
	var w := WriggleWorm.new()
	wriggle_root.add_child(w)
	w.sim = sim
	w.substrate_top_y = SUBSTRATE_DEPTH
	w.position = clamp_xyz_in_tank(p, 0.25)


func _library_tiny_life_scalars() -> Dictionary:
	# Tie tiny-life carrying capacity to discovered library traits so
	# microfauna/worm density co-evolves with the current ecosystem's
	# structural complexity.
	if _tiny_life_scalar_ttl > 0.0:
		return _tiny_life_scalar_cache
	_tiny_life_scalar_ttl = 3.0
	var lib := get_node_or_null("/root/SpeciesLibrary")
	if lib == null or not lib.has_method("analyze_organism"):
		_tiny_life_scalar_cache = {"micro": 1.0, "wriggle": 1.0}
		return _tiny_life_scalar_cache
	var fish_a: Dictionary = lib.analyze_organism("fish", true)
	var plant_a: Dictionary = lib.analyze_organism("plant", true)
	var snail_a: Dictionary = lib.analyze_organism("snail", true)
	var pred_p: float = 0.0
	if int(fish_a.get("entry_count", 0)) > 0:
		pred_p = clampf(
			(float(fish_a.get("snail_predator_ratio", 0.0))
				+ float(fish_a.get("shrimp_predator_ratio", 0.0))) * 0.5,
			0.0, 1.0)
	var habitat: float = 0.0
	if int(plant_a.get("entry_count", 0)) > 0:
		var root_score: float = clampf(float(plant_a.get("avg_max_roots", 6.0)) / 12.0, 0.0, 1.0)
		var frond_score: float = clampf(float(plant_a.get("avg_leaf_length", 4.0)) / 10.0, 0.0, 1.0)
		habitat = (root_score + frond_score) * 0.5
	var grazer_complexity: float = 0.0
	if int(snail_a.get("entry_count", 0)) > 0:
		grazer_complexity = clampf(float(snail_a.get("avg_spines", 0.0)) * 0.6
			+ float(snail_a.get("avg_toxin", 0.0)) * 0.4, 0.0, 1.0)
	_tiny_life_scalar_cache = {
		"micro": clampf(0.85 + habitat * 0.28 - pred_p * 0.18, 0.65, 1.35),
		"wriggle": clampf(0.86 + habitat * 0.16 + grazer_complexity * 0.12, 0.65, 1.45),
	}
	return _tiny_life_scalar_cache


# Per-tick maintenance: refills both populations back to their targets. Cheap
# — counts a child list once per refill window, doesn't iterate per entity.
func _maintain_microfauna(sdt: float) -> void:
	_tiny_life_scalar_ttl = maxf(0.0, _tiny_life_scalar_ttl - sdt)
	# The MicrofaunaSwarm refills + manages its own presence in its tick; we just
	# feed it the current target capacity (tank volume / mulm / biofilm / bloom).
	if microfauna_root != null:
		microfauna_root.set_target(microfauna_carrying_capacity())


func _maintain_wriggle_worms(sdt: float) -> void:
	_wriggle_refill_t = maxf(0.0, _wriggle_refill_t - sdt)
	if _wriggle_refill_t > 0.0:
		return
	_wriggle_refill_t = 1.6
	if wriggle_root == null:
		return
	# Target tracks mulm carpet density — sparse mulm means few worms.
	var target: int = wriggle_carrying_capacity()
	var have: int = wriggle_root.get_child_count()
	var to_spawn: int = mini(target - have, 2)
	for i in to_spawn:
		_spawn_one_wriggle()


# Tubifex patch maintenance. Patches spawn when ammonia / nitrite are
# elevated (poor cycling) and despawn as soon as chemistry clears. Read
# the visual cue: red patches on the substrate = your tank has unprocessed
# nitrogen. Each patch is a small bundle of writhing red worms.
const _TUBIFEX_TARGET_MAX: int = 8
const _TUBIFEX_NH3_TRIGGER: float = 0.40
const _TUBIFEX_NO2_TRIGGER: float = 0.55


func _maintain_tubifex_patches(sdt: float) -> void:
	_tubifex_check_t = maxf(0.0, _tubifex_check_t - sdt)
	if _tubifex_check_t > 0.0:
		return
	_tubifex_check_t = randf_range(3.5, 5.5)
	if tubifex_root == null or sim == null:
		return
	# Reap dead patches from natural aging or fish grazing.
	var to_free: Array = []
	for c in tubifex_root.get_children():
		if c is TubifexPatch and (c as TubifexPatch).is_dead():
			to_free.append(c)
	for c in to_free:
		c.queue_free()
	# Read chemistry — patches only thrive in dirty water.
	var nh3: float = 0.0
	var no2: float = 0.0
	if sim.water_chemistry != null:
		nh3 = float(sim.water_chemistry.ammonia)
		no2 = float(sim.water_chemistry.nitrite)
	var pressure: float = 0.0
	if nh3 > _TUBIFEX_NH3_TRIGGER:
		pressure += (nh3 - _TUBIFEX_NH3_TRIGGER) * 1.8
	if no2 > _TUBIFEX_NO2_TRIGGER:
		pressure += (no2 - _TUBIFEX_NO2_TRIGGER) * 1.4
	pressure = clampf(pressure, 0.0, 1.6)
	var target: int = clampi(int(round(pressure * _TUBIFEX_TARGET_MAX)),
		0, _TUBIFEX_TARGET_MAX)
	# Decay any surplus toward target by marking older patches dead.
	# Reverse iteration so the visibly-oldest (first-spawned) dies first.
	var have: int = tubifex_root.get_child_count()
	if have > target:
		var kill_n: int = mini(have - target, 2)
		var children: Array = tubifex_root.get_children()
		for i in kill_n:
			var p = children[i] if i < children.size() else null
			if p is TubifexPatch:
				(p as TubifexPatch).mark_dead()
	elif have < target:
		# Spawn one patch per cycle so the population grows visibly,
		# not all-at-once.
		var p2 := TubifexPatch.new()
		p2.sim = sim
		var xz: Vector2 = _sample_substrate_xz(0.45, 0.4)
		p2.global_position = spawn_position_on_floor(xz.x, xz.y, 0.05)
		p2.substrate_top_y = SUBSTRATE_DEPTH
		tubifex_root.add_child(p2)


# Mycelium patch maintenance. Patches don't self-spawn (they're emitted
# from death events via spawn_mycelium_patch); the maintenance loop's
# only job is reaping aged-out / fully-grazed patches.
func _maintain_mycelium_patches(sdt: float) -> void:
	_mycelium_check_t = maxf(0.0, _mycelium_check_t - sdt)
	if _mycelium_check_t > 0.0:
		return
	_mycelium_check_t = 6.5
	if mycelium_root == null:
		return
	for c in mycelium_root.get_children():
		if c is MyceliumPatch and (c as MyceliumPatch).is_dead():
			c.queue_free()


# Biofilm patch maintenance. Patches grow on driftwood + rock voxels
# over time, peaking once the tank has matured (~5 sim-minutes), then
# get grazed down by snails / shrimp. Target count tracks the
# `biofilm_progress` value the driftwood-aging system already runs so
# the visible patches line up with the wood's biofilm tint.
const _BIOFILM_TARGET_MAX: int = 14


func _maintain_biofilm_patches(sdt: float) -> void:
	_biofilm_check_t = maxf(0.0, _biofilm_check_t - sdt)
	if _biofilm_check_t > 0.0:
		return
	_biofilm_check_t = randf_range(4.5, 6.5)
	if biofilm_root == null:
		return
	# Reap dead / fully-grazed patches.
	for c in biofilm_root.get_children():
		if c is BiofilmPatch and (c as BiofilmPatch).is_dead():
			c.queue_free()
	# Grow toward target. biofilm_progress is 0..0.65 from the
	# driftwood-aging system; we scale that to a target patch count.
	var target: int = clampi(int(round(
		biofilm_progress / 0.65 * float(_BIOFILM_TARGET_MAX))),
		0, _BIOFILM_TARGET_MAX)
	var have: int = biofilm_root.get_child_count()
	if have < target:
		_spawn_one_biofilm_patch()


func _spawn_one_biofilm_patch() -> void:
	if biofilm_root == null:
		return
	# Pick a host voxel from driftwood OR rock. Driftwood gets ~70 %
	# of patches because real biofilm prefers wood (more organic
	# substrate to colonize).
	var hosts: Array = []
	if randf() < 0.7 and not _driftwood_voxels.is_empty():
		hosts = _driftwood_voxels
	elif not _rock_voxels.is_empty():
		hosts = _rock_voxels
	elif not _driftwood_voxels.is_empty():
		hosts = _driftwood_voxels
	if hosts.is_empty():
		return
	var host: MeshInstance3D = hosts[randi() % hosts.size()]
	if host == null or not is_instance_valid(host):
		return
	# Place the patch on top of the host voxel with a small jitter.
	var p := BiofilmPatch.new()
	p.sim = sim
	biofilm_root.add_child(p)
	p.global_position = host.global_position + Vector3(
		randf_range(-0.08, 0.08),
		host.scale.y * 0.18 + 0.04,
		randf_range(-0.08, 0.08))


# Spawn a mycelium patch at the given world position. Called by fish /
# shrimp / snail death finalizers when a body dissolves on the
# substrate. Returns the new patch (or null if no container).
func spawn_mycelium_patch(at: Vector3) -> Node3D:
	if mycelium_root == null:
		return null
	# Cap so a mass extinction doesn't carpet the floor.
	if mycelium_root.get_child_count() >= 12:
		return null
	# Only ~55% of deaths produce a visible mycelium patch — most
	# decompose cleanly via the shrimp / snail / waste loop.
	if randf() > 0.55:
		return null
	var p := MyceliumPatch.new()
	p.sim = sim
	mycelium_root.add_child(p)
	p.global_position = at
	# Decomposer bloom (#48): a decomposing body enriches the bed and briefly
	# spikes ammonia as bacteria break it down — death visibly feeds the soil
	# and the nitrogen cycle, closing the loop.
	if substrate_grid != null:
		substrate_grid.add_at(Vector3(at.x, SUBSTRATE_DEPTH, at.z), 0.12)
	if sim != null and sim.water_chemistry != null:
		sim.water_chemistry.ammonia = clampf(
			float(sim.water_chemistry.ammonia) + 0.02, 0.0, 2.0)
	return p


# Public entry point for the retro fish store. Picks a sensible spawn
# position near the top-center (so the new arrival drops in visibly), then
# delegates to the private spawn helper. The fish_store.gd panel calls
# this; nothing else does.
func spawn_library_entry(genome: Dictionary, organism_type: String = "") -> bool:
	if sim == null or fauna_root == null:
		return false
	var otype: String = organism_type
	if otype == "":
		otype = String(genome.get("organism_type", "fish"))
	match otype:
		"fish":
			var g_copy: Dictionary = genome.duplicate(true)
			if TANK_SHAPE == "sphere":
				g_copy["preferred_y_frac"] = randf_range(0.08, 0.92)
			_spawn_fish_at(g_copy, _sample_fish_spawn_pos(g_copy))
			return true
		"shrimp":
			var sh_xz: Vector2 = _sample_substrate_xz(0.45, 0.35)
			_spawn_shrimp_at(genome.duplicate(true), spawn_position_on_floor(sh_xz.x, sh_xz.y, 0.15))
			return true
		"snail":
			var sn_xz: Vector2 = _sample_substrate_xz(0.45, 0.38)
			_spawn_snail_at(genome.duplicate(true), spawn_position_on_floor(sn_xz.x, sn_xz.y, 0.12))
			return true
		"coral":
			return spawn_coral_from_genome(genome.duplicate(true))
		"clam":
			# Drop a custom-designed clam from the creature creator onto
			# the substrate. Reuses the existing clams_root + sim.register_clam
			# path so save/load + tick wiring work transparently.
			if clams_root == null or sim == null:
				return false
			var cxz: Vector2 = _sample_substrate_xz(0.45, 0.40)
			var cpos: Vector3 = spawn_position_on_floor(cxz.x, cxz.y, 0.05)
			if not is_inside_tank_volume(cpos.x, cpos.y, cpos.z, 0.25):
				return false
			var cl_script: Script = load("res://scripts/clam.gd")
			if cl_script == null:
				return false
			var cl: Node = cl_script.new()
			clams_root.add_child(cl)
			cl.global_position = cpos
			cl.init_genome(genome.duplicate(true))
			# Spawn as an adult so the player sees their design immediately.
			cl.maturity = 1
			cl.scale = Vector3.ONE
			sim.register_clam(cl)
			return true
		"plant":
			if genome.get("floating", false):
				return spawn_floating_plant(genome)
			var p_xz: Vector2 = _sample_substrate_xz(0.35, 0.46, 0.45)
			# Forward the entire genome dict as the seed config so all new
			# trait fields (variegation, quilted, wavy_edges, iridescence,
			# red_potential, co2_demand, melt_susceptibility, has_plantlets,
			# is_carpet, whorled_leaves, leaf_size_mult, underside_tone,
			# latin_name, common_name, species_id, is_epiphyte) reach
			# plant.init() without needing per-field plumbing.
			var cfg: Dictionary = PlantGenome.enrich(genome.duplicate(true))
			cfg["generation"] = int(genome.get("generation", 0)) + 1
			if not cfg.has("parent_lineage"):
				cfg["parent_lineage"] = String(genome.get("plant_name", "Library stock"))
			# Library spawns are exact presets — no mutation jitter.
			cfg["no_mutate"] = true
			# Epiphytes need a host: drop them onto the nearest driftwood/
			# rock instead of the substrate. We translate via the helper
			# below; if no hardscape exists yet, fall back to substrate
			# placement which will still render but not feel right.
			var spawn_pos: Vector3 = spawn_position_on_floor(p_xz.x, p_xz.y)
			if bool(cfg.get("is_epiphyte", false)):
				var anchor: Vector3 = _find_nearest_hardscape_anchor(spawn_pos)
				if anchor != Vector3.ZERO:
					spawn_pos = anchor
			spawn_seedling(spawn_pos,
				genome.get("ramp_override", []), int(cfg["generation"]), cfg)
			return true
		_:
			return false


func spawn_purchased_fish(genome: Dictionary) -> void:
	var g: Dictionary = genome.duplicate(true)
	if TANK_SHAPE == "sphere":
		g["preferred_y_frac"] = randf_range(0.1, 0.9)
	_spawn_fish_at(g, _sample_fish_spawn_pos(g))


func _spawn_fish_at(genome: Dictionary, pos: Vector3) -> void:
	var f := Fish.new()
	# Spread initial ages so the founding generation doesn't all die at once.
	# Some are juvenile-fresh, some are nearly senescent. This creates rolling
	# generations from frame zero rather than synchronised crashes.
	var lifespan: float = genome.get("max_age_s", 240.0)
	f.age = randf_range(0.15, 0.65) * lifespan
	# Apex species (e.g. betta) can grow bigger than schooling species but
	# not tank-monster huge.
	if genome.get("species", "") == "betta":
		f.max_growth = 2.0
	# Remap preferred_y + home_y_radius to the actual water column.
	# Species library values were calibrated for the default 5-unit
	# column; in a tall reef tank without this remap every fish would
	# pin to the bottom 1-2 units. Mutates the genome in place so the
	# subsequent init_genome() reads the corrected values.
	_apply_water_column_scale(genome)
	_apply_shape_aware_preferred_y(genome, pos.x, pos.z)
	fauna_root.add_child(f)
	# Size-aware spawn margin. The old fixed 0.35 left big fish (custom
	# library creatures, apex species at growth 2.0) clipping into the
	# glass on spawn because their voxel bodies extend well past the
	# centre. body_margin ≈ half-body-length; a typical fish is ~12
	# voxels long, so 6 × voxel_scale × max_growth covers the
	# silhouette plus a small safety pad.
	var voxel_scale: float = float(genome.get("adult_voxel_scale", 0.18))
	var max_g: float = float(genome.get("max_growth", f.max_growth))
	var body_margin: float = clampf(voxel_scale * 7.5 * max_g, 0.45, 1.6)
	f.global_position = clamp_xyz_in_tank(pos, body_margin)
	# If the position is still uncomfortably close to a wall AND we have
	# the lateral-boundary helper, nudge inward along the inward normal
	# so the body has clearance to swim before the brain can react.
	if has_method("tank_lateral_boundary_info"):
		var info: Dictionary = tank_lateral_boundary_info(f.global_position, 0.0)
		var clearance: float = float(info.get("clearance", 99.0))
		var inward: Vector3 = info.get("inward", Vector3.ZERO)
		if clearance < body_margin and inward.length_squared() > 0.1:
			f.global_position += inward.normalized() * (body_margin - clearance + 0.05)
			f.global_position = clamp_xyz_in_tank(f.global_position, body_margin * 0.9)
		# Bias the random initial heading away from the nearest wall.
		# Fish._ready picks a random theta which could face them straight
		# at a wall — combined with a near-wall spawn position, they'd
		# embed in the glass before the brain's first tick could react.
		# Forcing the X/Z heading to point inward at spawn fixes that.
		if inward.length_squared() > 0.1:
			var current_heading: Vector3 = f.get("heading") if "heading" in f else Vector3.ZERO
			if current_heading.length_squared() < 0.01 \
					or current_heading.dot(inward) < -0.15:
				# Random angle within ±70° of inward to avoid every fish
				# at the same wall facing the exact same direction.
				var inward_xz: Vector3 = Vector3(inward.x, 0.0, inward.z).normalized()
				if inward_xz.length_squared() < 0.5:
					inward_xz = Vector3.FORWARD
				var twist: float = randf_range(-PI * 0.4, PI * 0.4)
				var biased: Vector3 = inward_xz.rotated(Vector3.UP, twist)
				f.set("heading", biased)
	f.init_genome(genome)
	sim.register_fish(f)


func _spawn_shrimp_at(genome: Dictionary, pos: Vector3) -> void:
	var g: Dictionary = genome.duplicate(true)
	if not g.has("organism_type"):
		g["organism_type"] = "shrimp"
	if not g.has("substrate_top_y"):
		g["substrate_top_y"] = SUBSTRATE_DEPTH
	var sh := Shrimp.new()
	sh.age = float(g.get("max_age_s", 360.0)) * randf_range(0.05, 0.35)
	fauna_root.add_child(sh)
	sh.global_position = clamp_xyz_in_tank(pos, 0.3)
	sh.init_genome(g)
	sim.register_shrimp(sh)


func _spawn_snail_at(genome: Dictionary, pos: Vector3) -> void:
	var sn_root: Node = null
	if sim != null:
		if sim.has_method("ensure_snails_root"):
			sn_root = sim.ensure_snails_root()
		elif sim.snails_root != null and is_instance_valid(sim.snails_root):
			sn_root = sim.snails_root
	if sn_root == null:
		sn_root = _find_snails_container()
	if sn_root == null:
		sim.snails_root = _build_snails()
		sn_root = sim.snails_root
	var sn := Node3D.new()
	sn.set_script(load("res://scripts/snail.gd"))
	var wall_n: Vector3 = Vector3.UP
	var spawn_pos: Vector3 = clamp_xyz_in_tank(pos, 0.32, 0.08)
	if spawn_pos.y > SUBSTRATE_DEPTH + 0.25:
		wall_n = Vector3(0, 0, 1)
		spawn_pos = boundary_point_on_wall(spawn_pos.y, wall_n)
	# Library genomes store colors as [r,g,b,a] arrays (SaveHelpers.color_to_array).
	# Convert back to Color before handing to _configure_snail_node — passing an
	# Array directly would crash the typed `shell_color: Color` field on the
	# snail node ("Trying to assign value of type 'Array' to ... 'Color'").
	var sc_raw: Variant = genome.get("shell_color", Color8(135, 44, 176))
	var shell_c: Color
	if sc_raw is Color:
		shell_c = sc_raw
	elif sc_raw is Array:
		shell_c = SaveHelpers.array_to_color(sc_raw, Color8(135, 44, 176))
	else:
		shell_c = Color8(135, 44, 176)
	_configure_snail_node(sn, spawn_pos, wall_n,
		String(genome.get("shell_shape", "turbo")),
		[shell_c], 0)
	if sn.has_method("apply_genome_metadata"):
		sn.apply_genome_metadata(genome)
	sn_root.add_child(sn)
	_build_snail_body(sn)
	sim.register_snail(sn)


# Reference dimensions the species library was originally tuned against
# (default tank: half-height 8, substrate at ~1.6, water surface at ~6.5,
# water column ~5 units). Any preferred_y / home_y_radius in the library
# is interpreted as if it sits in this column, then re-projected onto
# the actual tank's column.
const _REF_SUBSTRATE_Y: float = 1.6
const _REF_COLUMN_HEIGHT: float = 5.0


func _apply_water_column_scale(genome: Dictionary) -> void:
	# Actual water column for this tank (SUBSTRATE_DEPTH .. WATER_HEIGHT).
	var col: float = maxf(1.0, WATER_HEIGHT - SUBSTRATE_DEPTH)

	# Vertical anchor:
	#   preferred_y_frac (0..1) - new key, takes priority. Mixed-morph
	#     reef fish use this to spread across the column.
	#   preferred_y - legacy absolute Y. Remap as a fraction of the
	#     reference column, then project onto the actual column.
	var frac: float
	if genome.has("preferred_y_frac"):
		frac = clampf(float(genome["preferred_y_frac"]), 0.05, 0.95)
	else:
		var legacy: float = float(genome.get("preferred_y", 3.5))
		frac = clampf((legacy - _REF_SUBSTRATE_Y) / _REF_COLUMN_HEIGHT, 0.05, 0.95)
	genome["preferred_y_frac"] = frac
	# Nominal column Y — refined per-spawn in _apply_shape_aware_preferred_y.
	genome["preferred_y"] = SUBSTRATE_DEPTH + frac * col

	# Vertical territory radius:
	#   The library's home_y_radius was 16-25% of the reference column.
	#   Scale by the same factor so taller tanks get larger territories.
	var col_ratio: float = col / _REF_COLUMN_HEIGHT
	if genome.has("home_y_radius"):
		genome["home_y_radius"] = float(genome["home_y_radius"]) * col_ratio
	# If not set, fish.gd defaults to 0.8 - scale that too via an explicit set.
	else:
		genome["home_y_radius"] = 0.8 * col_ratio
	# Dome bowls taper inward with height — give fish wider vertical roam.
	if TANK_SHAPE == "sphere":
		genome["home_y_radius"] = float(genome.get("home_y_radius", 0.8)) * 1.65
		genome["home_radius"] = float(genome.get("home_radius", 2.5)) * 0.9


func _apply_shape_aware_preferred_y(genome: Dictionary, x: float, z: float) -> void:
	var frac: float = clampf(float(genome.get("preferred_y_frac", 0.5)), 0.05, 0.95)
	var floor_y: float = column_surface_y(x, z)
	genome["preferred_y"] = preferred_y_at(x, z, frac, floor_y)
	var local_col: float = _footprint().local_column_height(x, z, 0.35, floor_y)
	var global_col: float = maxf(1.0, WATER_HEIGHT - SUBSTRATE_DEPTH)
	var local_ratio: float = clampf(local_col / global_col, 0.55, 1.35)
	if genome.has("home_y_radius"):
		genome["home_y_radius"] = float(genome["home_y_radius"]) * local_ratio


func _spawn_initial_shrimp() -> void:
	# Neocaridina-style shrimp. Two color morphs for visual interest.
	var red_genome: Dictionary = {
		"organism_type": "shrimp",
		"species": "shrimp",
		"base_color": Color8(195, 65, 55),    # cherry red
		"accent_color": Color8(245, 220, 200),
		"adult_voxel_scale": 0.11,
		"max_age_s": 360.0,
		"max_speed": 0.85,
		"substrate_top_y": SUBSTRATE_DEPTH,
		"defense_spines": 0.20,
		"toxin_level": 0.15,
		"claw_size": 0.30,
		"body_length_factor": 1.05,
	}
	var amber_genome: Dictionary = {
		"organism_type": "shrimp",
		"species": "shrimp",
		"base_color": Color8(195, 145, 70),   # amber/honey
		"accent_color": Color8(245, 220, 200),
		"adult_voxel_scale": 0.11,
		"max_age_s": 360.0,
		"max_speed": 0.85,
		"substrate_top_y": SUBSTRATE_DEPTH,
		"defense_spines": 0.12,
		"toxin_level": 0.22,
		"claw_size": 0.22,
		"body_length_factor": 0.96,
	}
	# Number from TankConfig preset stocking dict.
	var shrimp_n: int = _stocking_shrimp_count()
	if shrimp_n <= 0:
		return
	var phenotype_mult: float = _initial_phenotype_spread()
	# Roughly 2/3 reds + 1/3 ambers. Start as adults so breeding kicks in soon.
	var red_n: int = int(shrimp_n * 2.0 / 3.0)
	# Flag ~1 in 6 shrimp as freshwater amano-style cleaners so the
	# default tank visibly demonstrates the cleaning symbiosis behavior
	# tier. Cleaners hunt high-stress fish; non-cleaner cherries scavenge
	# detritus. Guaranteed at least one if the colony is large enough.
	# Cast to float for the divide, floor back to int — silences the
	# integer-division precision warning while keeping the intent.
	var cleaner_target: int = maxi(1, int(floor(float(shrimp_n) / 6.0))) if shrimp_n >= 4 else 0
	var cleaner_picked: int = 0
	for i in shrimp_n:
		var g: Dictionary = red_genome.duplicate() if i < red_n else amber_genome.duplicate()
		g["sex"] = i % 2
		g["max_age_s"] += randf_range(-30, 30)
		g["defense_spines"] = clampf(float(g.get("defense_spines", 0.0)) + randf_range(-0.10, 0.16), 0.0, 1.0)
		g["toxin_level"] = clampf(float(g.get("toxin_level", 0.0)) + randf_range(-0.10, 0.14), 0.0, 1.0)
		g["claw_size"] = clampf(
			float(g.get("claw_size", 0.25)) + randf_range(-0.18, 0.24) * phenotype_mult,
			0.0, 1.2)
		g["body_length_factor"] = clampf(
			float(g.get("body_length_factor", 1.0)) + randf_range(-0.20, 0.24) * phenotype_mult,
			0.75, 1.7)
		g["adult_voxel_scale"] = clampf(
			float(g.get("adult_voxel_scale", 0.11)) + randf_range(-0.02, 0.03) * phenotype_mult,
			0.07, 0.24)
		# Founder morph variety: most stay classic neocaridina (caridean), but a
		# minority roll the distinctive freshwater body plans so a colony shows
		# off the expanded architecture and can drift further over generations.
		g["rostrum_length"] = clampf(0.3 + randf_range(-0.15, 0.45) * phenotype_mult, 0.0, 1.5)
		if randf() < 0.35:
			g["pattern_type"] = randi() % 4
		var morph_roll: float = randf()
		if morph_roll < 0.08:
			# Bamboo / wood shrimp — big filter-feeder with fan hands.
			g["filter_fans"] = true
			g["adult_voxel_scale"] = clampf(float(g.get("adult_voxel_scale", 0.11)) * 1.5, 0.07, 0.3)
			g["body_length_factor"] = clampf(float(g.get("body_length_factor", 1.0)) + 0.3, 0.75, 1.7)
			g["base_color"] = Color8(150, 110, 80)
		elif morph_roll < 0.13:
			# Crayfish — long straight body + big claws.
			g["body_shape"] = "lobster"
			g["claw_size"] = clampf(float(g.get("claw_size", 0.3)) + 0.5, 0.0, 1.2)
			g["adult_voxel_scale"] = clampf(float(g.get("adult_voxel_scale", 0.11)) * 1.4, 0.07, 0.3)
			g["base_color"] = Color8(90, 110, 70)
		elif morph_roll < 0.16:
			# Freshwater fiddler-style crab — one oversize claw.
			g["body_shape"] = "crab"
			g["claw_size"] = clampf(float(g.get("claw_size", 0.3)) + 0.4, 0.0, 1.2)
			g["claw_asymmetry"] = randf_range(0.5, 0.9)
		# Promote a handful to cleaner duty. Spread across the cohort so
		# they don't cluster — every (shrimp_n / cleaner_target)-th index
		# gets the flag.
		if cleaner_target > 0 and cleaner_picked < cleaner_target \
				and (i % maxi(1, int(floor(float(shrimp_n) / float(cleaner_target))))) == 0:
			g["is_cleaner"] = true
			# Cleaner cherries are slightly larger + paler than the
			# scavengers so the player can read them at a glance.
			g["base_color"] = Color8(220, 180, 200)
			g["accent_color"] = Color8(245, 235, 220)
			g["claw_size"] = clampf(float(g.get("claw_size", 0.30)) + 0.18, 0.0, 1.2)
			g["body_length_factor"] = clampf(
				float(g.get("body_length_factor", 1.05)) + 0.10, 0.75, 1.7)
			cleaner_picked += 1
		var sh := Shrimp.new()
		# Spread initial ages so we don't get a synchronised die-off.
		sh.age = g["max_age_s"] * randf_range(0.15, 0.6)
		fauna_root.add_child(sh)
		var sh_xz: Vector2 = _random_xz_in_band(-TANK_HALF_D * 0.7, TANK_HALF_D * 0.7, 0.4)
		sh.global_position = spawn_position_on_floor(sh_xz.x, sh_xz.y, 0.15)
		sh.init_genome(g)
		sim.register_shrimp(sh)
		# Yield every 4 shrimp - each builds ~15 voxels + an egg cluster.
		if (i + 1) % 4 == 0:
			await get_tree().process_frame


func _spawn_marine_shrimp(yield_during: bool = true) -> void:
	# Skunk cleaner shrimp (Lysmata amboinensis) - bright red carapace
	# with a stark white spine stripe and oversize white antennae.
	# Cleaning-station behavior tier in shrimp.gd handles the gameplay.
	var cleaner_genome: Dictionary = {
		"organism_type": "shrimp",
		"species": "shrimp",
		"base_color": Color8(195, 50, 45),       # deep tomato red
		"accent_color": Color8(245, 230, 215),   # cream belly
		"adult_voxel_scale": 0.13,                # slightly bigger than cherry
		"max_age_s": 400.0,
		"max_speed": 0.90,
		"substrate_top_y": SUBSTRATE_DEPTH,
		"is_cleaner": true,
		"defense_spines": 0.34,
		"toxin_level": 0.12,
		"claw_size": 0.38,
		"body_length_factor": 1.18,
	}
	var n: int = 6                                  # small cleaning crew
	for i in n:
		var g: Dictionary = cleaner_genome.duplicate()
		g["sex"] = i % 2
		g["max_age_s"] += randf_range(-30, 30)
		g["defense_spines"] = clampf(float(g.get("defense_spines", 0.0)) + randf_range(-0.08, 0.12), 0.0, 1.0)
		g["toxin_level"] = clampf(float(g.get("toxin_level", 0.0)) + randf_range(-0.08, 0.10), 0.0, 1.0)
		g["claw_size"] = clampf(float(g.get("claw_size", 0.38)) + randf_range(-0.10, 0.14), 0.0, 1.2)
		g["body_length_factor"] = clampf(float(g.get("body_length_factor", 1.18)) + randf_range(-0.14, 0.16), 0.75, 1.7)
		# Marine variety: most of the crew stay skunk cleaners (with long
		# antennae + rostrum genes set so they can drift), but a couple roll
		# into bolder reef morphs — a mantis shrimp or a small reef crab.
		var mvar: float = randf()
		if mvar < 0.12:
			g["body_shape"] = "mantis"
			g["is_cleaner"] = false
			g["base_color"] = Color8(60, 180, 120)
			g["accent_color"] = Color8(240, 120, 60)
			g["claw_size"] = clampf(float(g.get("claw_size", 0.38)) + 0.3, 0.0, 1.2)
			g["body_length_factor"] = clampf(float(g.get("body_length_factor", 1.18)) + 0.25, 0.75, 1.7)
			g["pattern_type"] = 2
		elif mvar < 0.20:
			g["body_shape"] = "crab"
			g["is_cleaner"] = false
			g["base_color"] = Color8(200, 90, 70)
			g["claw_size"] = clampf(float(g.get("claw_size", 0.38)) + 0.35, 0.0, 1.2)
			g["claw_asymmetry"] = randf_range(0.3, 0.8)
		else:
			g["antenna_length_factor"] = randf_range(1.4, 2.1)
			g["rostrum_length"] = randf_range(0.4, 0.9)
		var sh := Shrimp.new()
		sh.age = g["max_age_s"] * randf_range(0.15, 0.6)
		fauna_root.add_child(sh)
		var sh_xz: Vector2 = _random_xz_in_band(
			-TANK_HALF_D * 0.7, TANK_HALF_D * 0.7, 0.4)
		sh.global_position = spawn_position_on_floor(sh_xz.x, sh_xz.y, 0.15)
		sh.init_genome(g)
		sim.register_shrimp(sh)
		if yield_during and (i + 1) % 3 == 0:
			await get_tree().process_frame


func _seed_nutrient_hotspots() -> void:
	# Uneven fertility so plants patch and spread like a real soil cap.
	var n_spots: int = 8 if TANK_SHAPE == "sphere" else 5
	for i in n_spots:
		var edge: float = 0.48 if TANK_SHAPE == "sphere" else 0.0
		var hs_xz: Vector2 = _sample_substrate_xz(0.35, edge)
		substrate_grid.add_at(Vector3(hs_xz.x, SUBSTRATE_DEPTH, hs_xz.y), randf_range(1.2, 2.0))
