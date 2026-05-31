# walstad loom 3D voxel world.
#
# Builds the static environment (substrate, hardscape, water volume, glass)
# and the initial population (plants, fish, snails). Then hands off to a
# SimDriver child for ongoing generative behavior.
#
# Coordinate system: Y is up. The tank floor is at y=0. Tank box spans
# x in [-tank_half_w, +tank_half_w], z in [-tank_half_d, +tank_half_d].
# Water surface sits at y=water_height.

extends Node3D

# How much tannin has leached into the water (0..1). Driftwood releases it
# slowly; visible as a brown tint in the water material.
var tannins: float = 0.0
var _water_mesh: MeshInstance3D = null
var _water_material_ref: StandardMaterial3D = null
var _caustic_meshes: Array[MeshInstance3D] = []
var _caustics_mat: ShaderMaterial = null
var _mulm_voxels: Array = []
var _film_voxels: Array = []
var _film_root: Node3D = null
var _film_maintain_t: float = 0.0
var _understory_t: float = 48.0
var algae_root: Node3D = null
# Driftwood voxels captured in _build_hardscape so the biofilm tick can
# tint a growing fraction over time. Real driftwood develops a fuzzy
# white biofilm in the first 1-2 weeks of a new tank, then settles back
# as bacteria balance out and shrimp / otos graze it.
var _driftwood_voxels: Array[MeshInstance3D] = []
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
var microfauna_root: Node3D = null
var wriggle_root: Node3D = null
# Worms spawn proportional to mulm carpet density — no fixed ceiling.
const WRIGGLE_PER_MULM_FRAC: float = 0.55
# Maintenance cadence — refilling every frame is fine cost-wise but the
# RNG variance reads better when we batch into 0.8 s slices.
var _microfauna_refill_t: float = 0.0
var _wriggle_refill_t: float = 0.0
var _microfauna_bootstrap_remaining: int = 0
var _tiny_life_scalar_cache: Dictionary = {"micro": 1.0, "wriggle": 1.0}
var _tiny_life_scalar_ttl: float = 0.0

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
const C_SNAIL_SHELL := Color8(135, 44, 176)
const C_SNAIL_BODY := Color8(44, 31, 21)
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

	plants_root = Node3D.new(); plants_root.name = "Plants"; add_child(plants_root)
	fauna_root = Node3D.new(); fauna_root.name = "Fauna"; add_child(fauna_root)
	waste_root = Node3D.new(); waste_root.name = "Waste"; add_child(waste_root)
	algae_root = Node3D.new(); algae_root.name = "Algae"; add_child(algae_root)
	microfauna_root = Node3D.new(); microfauna_root.name = "Microfauna"; add_child(microfauna_root)
	wriggle_root = Node3D.new(); wriggle_root.name = "WriggleWorms"; add_child(wriggle_root)
	sim.plants_root = plants_root
	sim.fauna_root = fauna_root
	sim.waste_root = waste_root
	sim.algae_root = algae_root

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
		if bool(_active_substrate_profile.get("is_saltwater", false)):
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
		if bool(_active_substrate_profile.get("is_saltwater", false)):
			await _spawn_marine_shrimp()
		else:
			await _spawn_initial_shrimp()
		await get_tree().process_frame
	else:
		# Loading from save: lily pads + math plants aren't persisted, so
		# respawn them. Floaters ARE persisted now (custom designs survive)
		# and are restored by SimDriver.load_state -> restore_floaters, which
		# falls back to a default spawn for pre-feature saves.
		if not bool(_active_substrate_profile.get("is_saltwater", false)):
			_spawn_lily_pads()
			_spawn_math_plants()
			await get_tree().process_frame

	_spawn_aeration_system()
	_spawn_mulm_layer()
	_spawn_surface_ripples()
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

	# Find the directional light so we can dim it on the day/night cycle.
	# The light is a sibling under SubViewport/World, accessible by name.
	_directional_light = get_parent().get_node_or_null("DirectionalLight3D")

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

# Lofi room environment dynamic variables
var _room_sky_mat: ShaderMaterial = null
var _room_stars: Array[MeshInstance3D] = []
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



func _process(dt: float) -> void:
	var sdt: float = dt
	if sim != null:
		sdt = dt * float(sim.time_scale)

	# Update lofi room environment animations
	_room_time_passed += sdt

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
		var dl: float = sim.daylight()

		# 1. Update Sky Color
		if _room_sky_mat != null:
			var sky_col: Color
			if dl > 0.65:
				sky_col = Color8(235, 110, 85).lerp(Color8(115, 185, 245), (dl - 0.65) / 0.35)
			elif dl > 0.2:
				sky_col = Color8(12, 10, 24).lerp(Color8(235, 110, 85), (dl - 0.2) / 0.45)
			else:
				sky_col = Color8(12, 10, 24)
			_room_sky_mat.set_shader_parameter("albedo", sky_col)
			
		# 2. Update Twinkling stars
		var show_stars: bool = (dl < 0.25)
		for star in _room_stars:
			if is_instance_valid(star):
				star.visible = show_stars
				if show_stars:
					var offset_phase: float = star.position.x * 12.3 + star.position.y * 7.9
					var scale_factor: float = 0.7 + 0.3 * sin(_room_time_passed * 3.5 + offset_phase)
					star.scale = Vector3(scale_factor, scale_factor, scale_factor)

	# 3. Update Clock hands (real-world local time)
	if _ambient_due and _room_clock_hour_pivot != null and _room_clock_min_pivot != null:
		var sys_time := Time.get_time_dict_from_system()
		var hr: float = float(sys_time.hour)
		var mn: float = float(sys_time.minute)
		var sc: float = float(sys_time.second)
		
		_room_clock_hour_pivot.rotation.z = -((int(hr) % 12) + mn / 60.0 + sc / 3600.0) * (TAU / 12.0)
		_room_clock_min_pivot.rotation.z = -(mn + sc / 60.0) * (TAU / 60.0)

	# 4. Update spinning vinyl record disc (synced to music state)
	if _ambient_due and _room_record_disc != null:
		var cfg_player := _cfg_node
		var target_speed: float = 1.5 if (cfg_player != null and cfg_player.music_enabled) else 0.0
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
	# Coral recruitment (saltwater tanks only). Larval settlement is limited
	# by substrate space and competition, not a global count cap.
	if bool(_active_substrate_profile.get("is_saltwater", false)):
		_coral_recruit_timer = maxf(0.0, _coral_recruit_timer - sdt)
		if _coral_recruit_timer <= 0.0:
			_coral_recruit_timer = randf_range(CORAL_RECRUIT_MIN, CORAL_RECRUIT_MAX)
			_maybe_recruit_coral()
	# Tannins: slow rise toward a cap (driftwood + leaves leak organics into
	# the water column). Visible as a warm brown tint that deepens over time.
	if _ambient_due and tannins < 0.35:
		tannins = minf(0.35, tannins + 0.00005 * adt)
	if _ambient_due and _water_material_ref != null:
		var tannin_color := Color(0.83, 0.55, 0.25)
		var base_water := Color(C_WATER_SHALLOW.r, C_WATER_SHALLOW.g, C_WATER_SHALLOW.b)
		# Tannin tint first (slow brown shift from driftwood).
		var tinted: Color = base_water.lerp(tannin_color, tannins * 0.55)
		# Algae bloom tint: lerp toward a soft green proportional to
		# sim.bloom_intensity. The green also boosts opacity — a fully
		# bloomed tank reads as cloudy / green-water, not just slightly
		# tinted. Capped at 0.55 lerp so the worst-case still shows the
		# fish silhouettes through the haze.
		var bloom: float = 0.0
		if sim != null:
			bloom = float(sim.bloom_intensity)
		if bloom > 0.01:
			var algae_green := Color(0.36, 0.62, 0.32)
			tinted = tinted.lerp(algae_green, bloom * 0.55)
		tinted.a = 0.10 + tannins * 0.10 + bloom * 0.18
		_water_material_ref.albedo_color = tinted

	# Day/night light cycle. The DirectionalLight gives soft ambient room
	# light; the SpotLight3Ds in the fixture give the focused aquarium beam.
	# Both are dimmed by the day/night cycle. Throttled to 10 Hz using
	# real-time dt (not sim-scaled) — at 16× fast-forward we still only
	# write shader parameters 10 times a second, which is plenty for an
	# arc that takes seconds to visibly change.
	_light_cycle_accum += dt
	if sim != null and _light_cycle_accum >= LIGHT_CYCLE_INTERVAL:
		_light_cycle_accum = 0.0
		var dl: float = sim.daylight()
		var cfg2 := _cfg_node
		var max_energy: float = 0.5
		var warmth: float = 0.6
		if cfg2 != null:
			max_energy = float(cfg2.light_energy)
			warmth = float(cfg2.light_warmth)
		var beam_color: Color = Color(0.55, 0.65, 0.95).lerp(
			Color(1.0, 0.95, 0.80), warmth)
		# Fixture spot lights: strong focused beam (softened on sphere bowls).
		if _directional_light != null:
			_directional_light.light_color = beam_color
		var spot_energy: float = 0.4 + dl * (max_energy * 6.0)
		var sphere_soft: bool = TANK_SHAPE == "sphere"
		if sphere_soft:
			spot_energy *= 0.68
		for spot in _light_fixture_spots:
			if not is_instance_valid(spot):
				continue
			spot.light_color = beam_color
			spot.light_energy = spot_energy
		if _sphere_fill_light != null and is_instance_valid(_sphere_fill_light):
			_sphere_fill_light.light_color = beam_color
			var fill_e: float = 0.08 + dl * (max_energy * 0.55)
			if sphere_soft:
				fill_e *= 1.35
			_sphere_fill_light.light_energy = fill_e
		# Ambient room light: low energy, broad — extra fill for curved glass.
		if _directional_light != null:
			var dir_e: float = 0.05 + dl * (max_energy * 0.45)
			if sphere_soft:
				dir_e *= 1.28
			_directional_light.light_energy = dir_e

		# Sync caustics material.
		if _caustics_mat != null:
			var show_caustics: bool = true
			if cfg2 != null:
				show_caustics = bool(cfg2.light_caustics)
			
			var intensity: float = 0.0
			if show_caustics:
				intensity = clampf(dl * max_energy * 2.0, 0.0, 1.0)
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

		# Sync god ray materials to the light cycle and Render panel parameters.
		var density: float = 0.02
		var anisotropy: float = 0.3
		if cfg2 != null:
			density = float(cfg2.fog_density)
			anisotropy = float(cfg2.fog_anisotropy)
		
		# Base beam opacity scales with daylight + user density settings
		var base_alpha: float = density * 4.0
		var ray_alpha: float = base_alpha * (0.15 + dl * 0.85) * (max_energy / 0.5)
		if TANK_SHAPE == "sphere":
			ray_alpha *= 0.52
		var ray_color := Color(beam_color.r, beam_color.g, beam_color.b, ray_alpha)
		var exponent: float = lerp(1.5, 4.0, (anisotropy + 0.9) / 1.8)
		
		for mat in _god_ray_materials:
			if mat != null:
				mat.set_shader_parameter("beam_color", ray_color)
				mat.set_shader_parameter("falloff_exponent", exponent)

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


# Gentle sin-curve wander for surface floaters. Runs at 10 Hz with accumulated
# dt (`adt`); the displacement is rate-correct so it looks the same as the old
# per-frame version. Reuses `_dead_floaters_scratch` to avoid a per-call Array.
func _drift_floaters(adt: float) -> void:
	_floater_t += adt
	_dead_floaters_scratch.clear()
	for f in _floaters:
		if not is_instance_valid(f):
			_dead_floaters_scratch.append(f)
			continue
		var fn: Node3D = f
		var ph: float = fn.get_meta("phase", 0.0)
		fn.position.x += sin(_floater_t * 0.15 + ph) * 0.05 * adt
		fn.position.z += cos(_floater_t * 0.12 + ph * 1.3) * 0.05 * adt
		# Slight bob.
		fn.position.y = WATER_HEIGHT - 0.05 + sin(_floater_t * 0.7 + ph) * 0.015
		# Keep floaters inside the actual tank footprint, not the bounding box.
		var xz: Vector2 = clamp_xz_in_tank(fn.position.x, fn.position.z, 0.35)
		fn.position.x = xz.x
		fn.position.z = xz.y
	for df in _dead_floaters_scratch:
		_floaters.erase(df)


# Lily-pad + math-plant (nautilus / cattail / moss) sway. Their tick() advances
# an internal sin phase, so running at 10 Hz with accumulated dt keeps the sway
# rate identical — slow sway reads as perfectly smooth at 10 Hz.
func _sway_surface_plants(adt: float) -> void:
	for mp in _math_plants:
		if not is_instance_valid(mp):
			continue
		if mp.has_method("tick"):
			mp.tick(adt)
	_lily_pad_t += adt
	for lp in _lily_pads:
		if not is_instance_valid(lp):
			continue
		if lp.has_method("tick"):
			lp.tick(adt)


# ---- Materials ----

func _solid_mat(color: Color, _emission_strength: float = 0.55) -> ShaderMaterial:
	# Use the faceted voxel shader so cubes self-light. `_emission_strength` is
	# accepted for backwards compatibility with old call sites but ignored.
	return VoxelMat.make(color)


func _glass_mat() -> StandardMaterial3D:
	# Nearly invisible - voxels behind shouldn't be masked.
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.7, 0.85, 0.9, 0.04)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic = 0.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _water_mat() -> StandardMaterial3D:
	# Faint blue wash. Heavy water alpha was making everything murky; the
	# palette handles the underwater mood from the limited palette set.
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(C_WATER_SHALLOW.r, C_WATER_SHALLOW.g, C_WATER_SHALLOW.b, 0.10)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	m.metallic = 0.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


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


func clamp_xz_in_tank(x: float, z: float, margin: float = 0.25) -> Vector2:
	return _footprint().clamp_inside(x, z, margin)


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


func clamp_xyz_in_tank(p: Vector3, margin: float = 0.25) -> Vector3:
	var c: Vector3 = _footprint().clamp_inside_3d(p, margin)
	if p.y <= WATER_HEIGHT + 0.12:
		c.y = minf(c.y, WATER_HEIGHT - margin)
	return c


func is_inside_tank_volume(x: float, y: float, z: float, margin: float = 0.0) -> bool:
	return _footprint().is_inside_3d(x, y, z, margin)


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
				return pt
	return _sample_point_in_tank(y_min, y_max, 0.35)


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


func microfauna_carrying_capacity() -> int:
	var scale: float = float(_library_tiny_life_scalars().get("micro", 1.0))
	var base: float = _tank_volume_proxy() * 0.42
	var mulm: float = float(_mulm_voxels.size()) * 0.55
	var bio: float = biofilm_progress * 140.0
	var bloom: float = float(sim.bloom_intensity) * 90.0 if sim != null else 0.0
	return maxi(4, int((base + mulm + bio + bloom) * scale))


func wriggle_carrying_capacity() -> int:
	var scale: float = float(_library_tiny_life_scalars().get("wriggle", 1.0))
	return int(float(_mulm_voxels.size()) * WRIGGLE_PER_MULM_FRAC * scale)


func _mulm_carrying_capacity() -> int:
	return maxi(60, int(_tank_volume_proxy() * 3.2))


func _surface_floater_capacity() -> int:
	var r: float = _footprint().radius_at_height(WATER_HEIGHT - 0.05, 0.35)
	return maxi(8, int(PI * r * r / 0.26))


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
	return _random_xz_in_band(z_min, z_max, margin, 0.0, edge_bias)


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
	# Soil stack under the bowl floor (y <= cy), clipped to the same hull as the glass.
	var bowl: Dictionary = _sphere_bowl_params()
	var R: float = float(bowl["R"]) - margin - 0.14
	var cy: float = float(bowl["cy"])
	if y < 0.0 or y > cy + 0.02:
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
	if TANK_SHAPE == "sphere":
		var bowl: Dictionary = _sphere_bowl_params()
		if not bowl.is_empty():
			var build_rad: float = float(bowl["R"]) - 0.12
			ext = Vector2(build_rad, build_rad)
	var default_cap: int = TerrainVoxelGrid.CellMaterial.AQUASOIL
	var cfg := _cfg_node if _cfg_node != null else get_node_or_null("/root/TankConfig")
	if cfg != null:
		default_cap = TerrainVoxelGrid.material_from_substrate_type(String(cfg.substrate_type))

	terrain_grid.configure(TANK_HALF_W, TANK_HALF_D, SUBSTRATE_DEPTH, ext.x, ext.y)
	var bowl_params: Dictionary = _sphere_bowl_params() if TANK_SHAPE == "sphere" else {}
	terrain_grid.populate_initial(
		func(x: float, y: float, z: float, margin: float) -> bool:
			return _substrate_voxel_ok(x, y, z, margin),
		default_cap,
		_rng,
		TANK_SHAPE,
		bowl_params,
	)
	rebuild_substrate_mesh()


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
	return Vector3(x, column_surface_y(x, z) + y_offset, z)


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
	var bezier: Callable = func(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
		var q0 := p0.lerp(p1, t)
		var q1 := p1.lerp(p2, t)
		var q2 := p2.lerp(p3, t)
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

	# Main Trunk
	var steps := 80
	for s in range(steps + 1):
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

	# Side Twigs
	var twig_configs := [
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
		return mi

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
	for i in pebble_positions.size():
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
	for i in left_pebbles.size():
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
	var is_saltwater: bool = bool(_active_substrate_profile.get("is_saltwater", false))
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
	# Position list. Each entry: [position, wall_normal, shell_shape].
	# Freshwater = mixed turbo + apple shells on the glass walls.
	# Marine = mix of turbo, trochus, and nassarius (the nassarius ride the substrate plane
	# with wall_normal pointing UP so they "stick" to the floor).
	var positions_and_walls: Array
	if is_saltwater:
		positions_and_walls = [
			# Glass-walking algae grazers (mix turbo + trochus).
			[Vector3(-7.95, 3.2, 0.0), Vector3(-1, 0, 0), "turbo"],
			[Vector3(-7.95, 4.8, -1.5), Vector3(-1, 0, 0), "trochus"],
			[Vector3(7.95, 2.5, 1.0), Vector3(1, 0, 0), "trochus"],
			[Vector3(7.95, 4.5, -1.0), Vector3(1, 0, 0), "turbo"],
			[Vector3(0.0, 2.5, 3.95), Vector3(0, 0, 1), "turbo"],
			# Nassarius scavengers riding the substrate floor.
			[Vector3(-3.0, SUBSTRATE_DEPTH + 0.1, 1.5), Vector3(0, 1, 0), "nassarius"],
			[Vector3(2.5, SUBSTRATE_DEPTH + 0.1, -2.0), Vector3(0, 1, 0), "nassarius"],
			[Vector3(0.0, SUBSTRATE_DEPTH + 0.1, 0.5), Vector3(0, 1, 0), "nassarius"],
		]
	else:
		positions_and_walls = [
			[Vector3(-7.95, 3.2, 0.0), Vector3(-1, 0, 0), "turbo"],
			[Vector3(-7.95, 4.8, -1.5), Vector3(-1, 0, 0), "apple"],
			[Vector3(7.95, 2.5, 1.0), Vector3(1, 0, 0), "turbo"],
			[Vector3(7.95, 4.5, -1.0), Vector3(1, 0, 0), "apple"],
			[Vector3(0.0, 2.5, 3.95), Vector3(0, 0, 1), "turbo"],
			[Vector3(-2.0, 3.8, -3.95), Vector3(0, 0, -1), "turbo"],
		]
	for i in positions_and_walls.size():
		var pw = positions_and_walls[i]
		var pos: Vector3 = pw[0]
		var wall_n: Vector3 = pw[1]
		var shape: String = String(pw[2]) if pw.size() > 2 else "turbo"
		var snail := Node3D.new()
		snail.set_script(load("res://scripts/snail.gd"))
		snail.position = pos
		snail.set("wall_normal", wall_n)
		snail.set("wall_min", Vector3(-TANK_HALF_W + 0.4, SUBSTRATE_DEPTH + 0.4, -TANK_HALF_D + 0.4))
		snail.set("wall_max", Vector3(TANK_HALF_W - 0.4, WATER_HEIGHT - 0.2, TANK_HALF_D - 0.4))
		snail.set("shell_color", founder_palette[i % founder_palette.size()])
		snail.set("shell_size", _rng.randf_range(0.85, 1.15))
		snail.set("generation", 0)
		snail.set("shell_shape", shape)
		snail.set("shell_spines", _rng.randf_range(0.0, 0.45))
		snail.set("toxin_level", _rng.randf_range(0.0, 0.35))
		c.add_child(snail)
		_build_snail_body(snail)
		if sim != null:
			sim.register_snail(snail)
	return c


func _build_snail_body(snail: Node3D) -> void:
	# Read heritable traits and shell silhouette. shell_shape branches
	# the construction into one of four forms:
	#   turbo      classic round low spiral (default, freshwater + marine)
	#   trochus    tall pointed cone (marine algae grazer)
	#   nassarius  small flat oval that lives on the substrate (marine
	#              scavenger; sits flatter and lower than a turbo)
	#   apple      rounded globose shell (freshwater apple-snail style)
	var shell_color: Color = snail.get("shell_color")
	var shell_size: float = snail.get("shell_size")
	var shell_shape: String = String(snail.get("shell_shape") if "shell_shape" in snail else "turbo")
	var shell_spines: float = clampf(float(snail.get("shell_spines") if "shell_spines" in snail else 0.0), 0.0, 1.0)
	var toxin_level: float = clampf(float(snail.get("toxin_level") if "toxin_level" in snail else 0.0), 0.0, 1.0)
	if toxin_level > 0.35:
		shell_color = shell_color.lerp(Color8(246, 220, 64), toxin_level * 0.35)
	# Shell banding color: use the genome's shell_accent_color when supplied
	# (alpha > 0), otherwise auto-derive a darker shade (original look).
	var accent_v: Variant = snail.get("shell_accent_color") if "shell_accent_color" in snail else null
	var shell_dark: Color
	if accent_v is Color and (accent_v as Color).a > 0.5:
		shell_dark = accent_v
	else:
		shell_dark = shell_color.darkened(0.22)
	# Body (foot + eye-stalk) tint is genome-driven; fall back to the classic
	# dark flesh color for any snail that didn't set one.
	var body_v: Variant = snail.get("body_color") if "body_color" in snail else null
	var body_color: Color = body_v if body_v is Color else C_SNAIL_BODY
	var shell_mat := _solid_mat(shell_color)
	var shell_dark_mat := _solid_mat(shell_dark)
	var body_mat := _solid_mat(body_color)

	match shell_shape:
		"trochus":
			# Pointed cone: 6 voxels stacked vertically, shrinking toward
			# the tip. Banded with alternating dark/light for the classic
			# trochus stripe look.
			for i in 6:
				var y: float = 0.04 + i * 0.045 * shell_size
				var s: float = (0.18 - i * 0.025) * shell_size
				var mat: Material = shell_mat if (i & 1) == 0 else shell_dark_mat
				_add_cube(snail, Vector3(0, y, 0), Vector3(s, s * 0.85, s), mat)
		"nassarius":
			# Small flat oval - a stubby low egg shape. Two voxels:
			# main body + a smaller cap.
			_add_cube(snail, Vector3(0, 0.0, 0),
				Vector3(0.18 * shell_size, 0.10 * shell_size,
					0.22 * shell_size), shell_mat)
			_add_cube(snail, Vector3(0, 0.06 * shell_size, -0.04),
				Vector3(0.10 * shell_size, 0.06 * shell_size,
					0.12 * shell_size), shell_dark_mat)
		"apple":
			# Rounded globose shell with a broad body whorl and small apex.
			_add_cube(snail, Vector3(0, 0.05 * shell_size, 0.0),
				Vector3(0.24 * shell_size, 0.21 * shell_size,
					0.24 * shell_size), shell_mat)
			_add_cube(snail, Vector3(0, 0.17 * shell_size, -0.04 * shell_size),
				Vector3(0.12 * shell_size, 0.10 * shell_size,
					0.12 * shell_size), shell_dark_mat)
			_add_cube(snail, Vector3(0.03 * shell_size, 0.03 * shell_size, 0.08 * shell_size),
				Vector3(0.08 * shell_size, 0.06 * shell_size,
					0.08 * shell_size), shell_dark_mat)
		_:
			# turbo: round low spiral (the original snail shape).
			for i in 4:
				var ang: float = i * 0.7
				var r: float = (0.05 + i * 0.06) * shell_size
				var sp := Vector3(cos(ang) * r, sin(ang) * r, 0.0)
				var s: float = (0.16 - i * 0.02) * shell_size
				var mat: Material = shell_mat if (i & 1) == 0 else shell_dark_mat
				_add_cube(snail, sp, Vector3(s, s, s), mat)

	# Defensive shell spines: sparse ridges that make snail morphs visibly
	# distinct and slightly less appealing to fish predators.
	if shell_spines > 0.12:
		var spine_mat := _solid_mat(shell_dark.lightened(0.08))
		var spine_count: int = clampi(int(round(2.0 + shell_spines * 6.0)), 2, 8)
		for i in spine_count:
			var t: float = float(i) / float(maxi(1, spine_count - 1))
			var ang: float = lerpf(-1.2, 1.2, t)
			var r: float = (0.10 + 0.14 * shell_spines) * shell_size
			var h: float = (0.03 + 0.08 * shell_spines) * shell_size
			var spike_pos := Vector3(cos(ang) * r, 0.09 * shell_size + sin(ang) * r * 0.55, sin(ang) * r * 0.2)
			_add_cube(snail, spike_pos, Vector3(0.03 * shell_size, h, 0.03 * shell_size), spine_mat)
	# Mantle ornaments from defense chemistry / lineage age:
	#   - toxic snails expose bright mantle frills (warning signal)
	#   - older generations gain subtle growth-ring ridges
	if toxin_level > 0.28:
		var mantle_mat := _solid_mat(shell_color.lerp(Color8(246, 230, 128),
			clampf(toxin_level * 0.42, 0.0, 0.42)))
		var frill_n: int = clampi(3 + int(toxin_level * 4.0), 3, 7)
		for i in frill_n:
			var t: float = float(i) / float(maxi(1, frill_n - 1))
			var ang: float = lerpf(-1.1, 1.1, t)
			var r2: float = (0.12 + shell_size * 0.10) * shell_size
			_add_cube(snail,
				Vector3(cos(ang) * r2, -0.01 * shell_size, sin(ang) * r2 * 0.35),
				Vector3(0.035 * shell_size, 0.028 * shell_size, 0.040 * shell_size),
				mantle_mat)
	var gen_v: Variant = snail.get("generation")
	var gen_n: int = int(gen_v if gen_v != null else 0)
	if gen_n >= 3:
		var ring_mat := _solid_mat(shell_dark.lightened(0.18))
		var ring_count: int = clampi(1 + int(gen_n / 3), 1, 4)
		for i in ring_count:
			var frac: float = float(i + 1) / float(ring_count + 1)
			var ry: float = 0.02 * shell_size + frac * 0.16 * shell_size
			var rs: float = (0.20 - frac * 0.04) * shell_size
			_add_cube(snail, Vector3(0, ry, -0.02 * shell_size),
				Vector3(rs, 0.016 * shell_size, rs), ring_mat)

	# Foot scales with shell. Nassarius foot is wider + flatter since they
	# crawl on substrate rather than glass.
	var foot_y: float = -0.05 * shell_size if shell_shape == "nassarius" else -0.12 * shell_size
	var foot_size: Vector3
	if shell_shape == "nassarius":
		foot_size = Vector3(0.28 * shell_size, 0.04 * shell_size, 0.20 * shell_size)
	elif shell_shape == "apple":
		foot_size = Vector3(0.30 * shell_size, 0.07 * shell_size, 0.22 * shell_size)
	else:
		foot_size = Vector3(0.24 * shell_size, 0.06 * shell_size, 0.16 * shell_size)
	_add_cube(snail, Vector3(0, foot_y, 0), foot_size, body_mat)
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
			if TANK_SHAPE == "sphere" and count > 1:
				g["preferred_y_frac"] = clampf(float(i) / float(count - 1), 0.08, 0.92)
			_spawn_fish_at(g, _sample_fish_spawn_pos(g))

	# Shrimp: reef tanks use the marine cleaning crew, not freshwater stocking.
	var is_saltwater: bool = bool(_active_substrate_profile.get("is_saltwater", false))
	if is_saltwater:
		_spawn_marine_shrimp(false)
	elif stocking.has("shrimp"):
		var shrimp_count: int = int(stocking["shrimp"])
		for i in shrimp_count:
			var xz: Vector2 = _sample_clear_xz_in_band(
				-TANK_HALF_D * 0.85, TANK_HALF_D * 0.85, 0.6, 0.45, 36, 0.0, 0.44)
			var sp := spawn_position_on_floor(xz.x, xz.y, 0.1)
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
	if sim.has_method("sync_species_discoveries"):
		sim.sync_species_discoveries()


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
		 "ramp": [Color8(28, 50, 24), Color8(48, 80, 40), Color8(72, 110, 58),
				  Color8(98, 140, 78), Color8(125, 168, 100), Color8(150, 190, 125)]},
	]

	# --- Background wall: thick valli forest (shape-aware placement) ---
	var bg_band: Vector2 = _spawn_z_band("background")
	for _row in 12:
		var xz: Vector2 = _sample_clear_xz_in_band(
			bg_band.x, bg_band.y, 0.35, 0.55, 36, 0.35, 0.38)
		var n_blades: int = _rng.randi_range(4, 7)
		for i in n_blades:
			var px: float = xz.x + _rng.randf_range(-0.35, 0.35)
			var pz: float = xz.y + _rng.randf_range(-0.35, 0.35)
			var fit: Vector2 = clamp_plant_site(px, pz, 0.35, 0.3)
			if not fits_plant_at(fit.x, fit.y, 0.35, 0.3):
				continue
			_spawn_plant(species_specs[0], spawn_position_on_floor(fit.x, fit.y),
				_rng.randi_range(2, 5))
	await get_tree().process_frame

	# --- Midground rosettes (crypts) + red accent stems scattered ---
	var mid_band: Vector2 = _spawn_z_band("mid")
	for i in 28:
		var xz: Vector2 = _sample_clear_xz_in_band(
			mid_band.x, mid_band.y, 0.3, 0.55, 36, 0.45, 0.48)
		_spawn_plant(species_specs[1], spawn_position_on_floor(xz.x, xz.y),
			_rng.randi_range(2, 4))
	await get_tree().process_frame
	for i in 14:
		var xz: Vector2 = _sample_clear_xz_in_band(
			mid_band.x, mid_band.y, 0.3, 0.55, 36, 0.45, 0.48)
		_spawn_plant(species_specs[3], spawn_position_on_floor(xz.x, xz.y),
			_rng.randi_range(2, 4))
	await get_tree().process_frame

	# --- Foreground carpet: very dense ---
	var fg_band: Vector2 = _spawn_z_band("foreground")
	for i in 55:
		var xz: Vector2 = _sample_clear_xz_in_band(
			fg_band.x, fg_band.y, 0.3, 0.45, 36, 0.25, 0.58)
		_spawn_plant(species_specs[2], spawn_position_on_floor(xz.x, xz.y),
			_rng.randi_range(1, 3))
		# Yield mid-carpet too - this is the densest single block (55 plants).
		if i == 27:
			await get_tree().process_frame
	await get_tree().process_frame

	# --- Moss on driftwood epiphyte points ---
	for i in 20:
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


func _spawn_plant(spec: Dictionary, pos: Vector3, initial_height: int) -> void:
	var reach: float = float(spec.get("leaf_length", 4)) * VOXEL_SIZE * 0.55
	var fit: Vector2 = clamp_plant_site(pos.x, pos.z, reach, 0.28)
	if not fits_plant_at(fit.x, fit.y, reach, 0.28):
		return
	pos.x = fit.x
	pos.z = fit.y
	if pos.y <= SUBSTRATE_DEPTH + 0.15 and _is_hardscape_occupied(pos.x, pos.z, 0.45):
		return
	pos = clamp_xyz_in_tank(pos, 0.3)
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
	})
	sim.register_plant(p)


# Called by Plant.gd when an emergent (above-water) plant casts a seed.
func spawn_seedling(pos: Vector3, ramp: Array, generation: int, seed_config: Dictionary) -> void:
	if plants_root == null or sim == null:
		return
	var is_saltwater: bool = bool(_active_substrate_profile.get("is_saltwater", false))
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
	
	# Inherit properties from parent and slightly mutate max_height
	var child_cfg: Dictionary = seed_config.duplicate()
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
			if TANK_SHAPE == "sphere" and count > 1:
				g["preferred_y_frac"] = clampf(float(i) / float(count - 1), 0.08, 0.92)
			_spawn_fish_at(g, _sample_fish_spawn_pos(g))
			_fish_built += 1
			if _fish_built % 4 == 0:
				await get_tree().process_frame


var _light_fixture_root: Node3D = null
var _light_fixture_spots: Array[SpotLight3D] = []
var _sphere_fill_light: OmniLight3D = null
var _god_ray_materials: Array[ShaderMaterial] = []
var _microfauna_vis_t: float = 0.0


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
	var panel_emit := VoxelMat.make(Color8(255, 250, 210))

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

		if cfg != null and bool(cfg.light_volumetric):
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

			if cfg != null and bool(cfg.light_volumetric):
				_add_god_ray_beam(_light_fixture_root, spot, spot.spot_angle, height_above)

	if TANK_SHAPE == "sphere":
		_apply_sphere_aquarium_lighting()


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
		
		# Set initial parameters
		mat.set_shader_parameter("beam_color", Color(1.0, 0.95, 0.80, 0.0))
		mat.set_shader_parameter("speed", 1.2)
		mat.set_shader_parameter("noise_scale", 1.8)
		mat.set_shader_parameter("edge_fade", 0.15)
		
		var exponent: float = 2.0
		if TankConfig != null:
			exponent = lerp(1.5, 4.0, (TankConfig.fog_anisotropy + 0.9) / 1.8)
		mat.set_shader_parameter("falloff_exponent", exponent)
		
		mi.material_override = mat
		_god_ray_materials.append(mat)
		
	parent.add_child(mi)


func _spawn_floaters() -> void:
	# Floating surface plants. Each is a parametric FloatingPlant (duckweed /
	# frogbit / salvinia / water lettuce) that drifts, photosynthesises, casts
	# shade, and propagates based on light + nutrients + grazing pressure.
	# The default tank gets a duckweed-dominant mix with a few frogbit.
	var container := Node3D.new()
	container.name = "Floaters"
	add_child(container)
	for i in 14:
		var f_xz: Vector2 = _sample_surface_xz(0.4, 0.36)
		_add_floater_at(
			clamp_xyz_in_tank(Vector3(f_xz.x, WATER_HEIGHT - 0.05, f_xz.y), 0.35),
			_random_floater_genome())


var _floaters: Array = []
var _floater_t: float = 0.0
var _duckweed_accum: float = 0.0
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
func _add_floater_at(pos: Vector3, genome: Dictionary = {}) -> void:
	var container := get_node_or_null("Floaters")
	if container == null:
		container = Node3D.new()
		container.name = "Floaters"
		add_child(container)
	var g: Dictionary = genome if not genome.is_empty() else _random_floater_genome()
	var fp := FloatingPlant.new()
	container.add_child(fp)
	fp.position = pos
	fp.init_genome(g)
	fp.set_meta("phase", randf() * TAU)
	_floaters.append(fp)


# Public entry point for the Creature Creator: drop a custom floating plant
# at a random surface spot. Creates the Floaters container if it's missing
# (e.g. on an empty / guided tank).
func spawn_floating_plant(genome: Dictionary) -> bool:
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
	if roll < 0.18:
		morph = "frogbit"
	elif roll < 0.30:
		morph = "salvinia"
	var hue: float = _rng.randf_range(0.22, 0.36)
	var base_c: Color = Color.from_hsv(hue, _rng.randf_range(0.45, 0.72), _rng.randf_range(0.40, 0.60))
	var tip_c: Color = Color.from_hsv(fposmod(hue - 0.03, 1.0), _rng.randf_range(0.40, 0.65), _rng.randf_range(0.62, 0.85))
	var leaf_size: float = 0.2
	var leaf_count: int = 3
	match morph:
		"frogbit":
			leaf_size = _rng.randf_range(0.34, 0.46)
			leaf_count = _rng.randi_range(5, 7)
		"salvinia":
			leaf_size = _rng.randf_range(0.24, 0.32)
			leaf_count = _rng.randi_range(4, 6)
		"water_lettuce":
			leaf_size = _rng.randf_range(0.34, 0.44)
			leaf_count = _rng.randi_range(6, 8)
		_:
			leaf_size = _rng.randf_range(0.16, 0.22)
			leaf_count = _rng.randi_range(1, 3)
	return {
		"morph": morph,
		"leaf_size": leaf_size,
		"leaf_count": leaf_count,
		"root_length": _rng.randf_range(0.25, 0.6),
		"base_color": base_c,
		"tip_color": tip_c,
		"spread_rate": _rng.randf_range(0.8, 1.2),
	}


func _mutate_floater_genome(g: Dictionary) -> Dictionary:
	var out: Dictionary = g.duplicate(true)
	out["base_color"] = FloatingPlant._to_color(g.get("base_color", Color8(70, 130, 60))).lerp(
		Color(randf(), randf() * 0.6 + 0.3, randf() * 0.5), 0.07)
	out["tip_color"] = FloatingPlant._to_color(g.get("tip_color", Color8(120, 180, 90))).lerp(
		Color(randf(), randf() * 0.7 + 0.3, randf() * 0.5), 0.07)
	out["leaf_size"] = clampf(float(g.get("leaf_size", 0.3)) + randf_range(-0.02, 0.02), 0.12, 0.7)
	out["root_length"] = clampf(float(g.get("root_length", 0.4)) + randf_range(-0.05, 0.05), 0.05, 1.4)
	out["spread_rate"] = clampf(float(g.get("spread_rate", 1.0)) + randf_range(-0.08, 0.08), 0.2, 2.5)
	return out


# Light + nutrient + grazing driven growth step (replaces the old fixed-timer
# duckweed doubling). Excess nutrients + light grow the mat; herbivorous /
# surface fish graze it; crowding and darkness thin it back out.
func _floater_growth_step() -> void:
	var live: Array = []
	for f in _floaters:
		if is_instance_valid(f):
			live.append(f)
		# Prune dead refs lazily.
	_floaters = live
	var n: int = live.size()
	if n == 0:
		return
	var light: float = 1.0
	var nutrients: float = 0.6
	var graze: float = 0.0
	if sim != null:
		if sim.has_method("daylight"):
			light = float(sim.daylight())
		nutrients = 0.35 + 0.65 * clampf(float(sim.get("bloom_intensity")), 0.0, 1.0)
		for fsh in sim.fish:
			if not is_instance_valid(fsh):
				continue
			var herb: float = clampf(float(fsh.herbivory), 0.0, 1.0)
			var surface: float = 1.0 if (float(fsh.preferred_y) >= 4.2 or int(fsh.mouth_orientation) < 0) else 0.25
			graze += herb * surface
		graze = clampf(graze * 0.06, 0.0, 0.8)
	var coverage: float = float(n) / float(_surface_floater_capacity())
	# Average spread_rate of the colony.
	var sr: float = 0.0
	for fp in live:
		sr += float(fp.spread_rate) if fp is FloatingPlant else 1.0
	sr = clampf(sr / float(n), 0.4, 2.0)
	var spread_p: float = 0.55 * light * nutrients * (1.0 - coverage) * sr - graze
	if randf() < spread_p:
		var parent: Node3D = live[_rng.randi_range(0, n - 1)]
		var ang: float = randf() * TAU
		var r: float = randf_range(0.5, 1.0)
		var nx: float = parent.position.x + cos(ang) * r
		var nz: float = parent.position.z + sin(ang) * r
		if _is_inside_tank(nx, nz, 0.4):
			var child_g: Dictionary = parent.get_genome() if parent is FloatingPlant else _random_floater_genome()
			_add_floater_at(Vector3(nx, WATER_HEIGHT - 0.05, nz), _mutate_floater_genome(child_g))
	# Die-back from crowding, grazing, or prolonged darkness.
	var dieback_p: float = graze * 0.5
	if coverage > 0.82:
		dieback_p += (coverage - 0.82) * 1.5
	if light < 0.25:
		dieback_p += 0.10
	if n > 3 and randf() < dieback_p:
		var victim: Node3D = live[_rng.randi_range(0, n - 1)]
		_floaters.erase(victim)
		victim.queue_free()


# Live floating-plant count + surface coverage fraction (read by SimDriver
# for floater photosynthesis O2 and algae shading).
func floater_count() -> int:
	var n: int = 0
	for f in _floaters:
		if is_instance_valid(f):
			n += 1
	return n


func floater_coverage() -> float:
	return clampf(float(floater_count()) / float(_surface_floater_capacity()), 0.0, 1.0)


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
		var d: Dictionary = e
		var pos: Vector3 = SaveHelpers.array_to_vec3(
			d.get("pos", []), Vector3(0, WATER_HEIGHT - 0.05, 0))
		_add_floater_at(pos, d)


# One-shot expanding ripple ring at the surface. Called by fish.gd when a
# fish bursts near the meniscus (a startle dart that breaches the surface
# tension). Voxel-styled: a thin flat box that scales outward via Tween
# and fades. Cheap; we cap concurrent ripples informally via short
# lifespan rather than an explicit pool.
func spawn_burst_ripple(pos: Vector3) -> void:
	var ring := MeshInstance3D.new()
	ring.mesh = VoxelMat.get_box(Vector3(0.45, 0.04, 0.45))
	ring.material_override = VoxelMat.make(Color8(225, 240, 245))
	ring.position = Vector3(pos.x, WATER_HEIGHT - 0.04, pos.z)
	add_child(ring)
	var final_scale: Vector3 = Vector3(4.0, 0.6, 4.0)
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", final_scale, 0.75) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Material albedo fade — duplicate first so we don't tint the shared
	# cached material for every other ripple in the tank.
	var fade_mat: ShaderMaterial = ring.material_override.duplicate() as ShaderMaterial
	ring.material_override = fade_mat
	var faded := Color8(225, 240, 245)
	faded.a = 0.0
	tw.tween_method(_set_ripple_albedo.bind(fade_mat),
		Color8(225, 240, 245), faded, 0.75) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(ring.queue_free)


# tween_method passes the interpolated Color first; .bind(mat) appends it.
func _set_ripple_albedo(c: Color, mat: ShaderMaterial) -> void:
	if mat == null or not is_instance_valid(mat):
		return
	mat.set_shader_parameter("albedo", c)


func _spawn_surface_ripples() -> void:
	# Sparse, slow ripples on the water surface - tiny pale voxels that
	# appear briefly and fade. Cheap stand-in for proper surface-tension
	# rendering. Emits from a particles3D at the meniscus.
	var p := GPUParticles3D.new()
	p.name = "SurfaceRipples"
	p.amount = 14
	p.lifetime = 2.0
	p.preprocess = 1.0
	p.local_coords = false
	p.position = Vector3(0, WATER_HEIGHT - 0.05, 0)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, 0)
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.gravity = Vector3(0, 0, 0)
	pm.spread = 0.0
	pm.scale_min = 0.4
	pm.scale_max = 1.2
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(TANK_HALF_W - 0.5, 0.02, TANK_HALF_D - 0.5)
	p.process_material = pm
	var bm := BoxMesh.new()
	bm.size = Vector3(0.4, 0.04, 0.4)
	bm.material = VoxelMat.make(Color8(220, 235, 240))
	p.draw_pass_1 = bm
	add_child(p)


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
			_build_disk_aerator(container, anchor_x)
		"stick":
			_build_stick_aerator(container, anchor_x)
		"filter":
			_build_filter_aerator(container, anchor_x)
		"none":
			pass
		_:
			_build_disk_aerator(container, anchor_x)

	# Push the computed rates onto the SimDriver so it can run the O2 model.
	if sim != null:
		sim.set("aeration_air_rate", air_rate)
		sim.set("aeration_flow_rate", flow_rate)
		sim.set("aeration_fixture", fixture)


# --- Bubble disk ---
# Round porous air-stone sitting on the substrate. Dense column of fine
# bubbles rises straight up to the surface. The disk itself is 5 dark gray
# voxels arranged in a + pattern with a thin air-line snaking back to the
# back wall.
func _build_disk_aerator(parent: Node, anchor_x: float) -> void:
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


# --- Bubble stick (wand) ---
# Long thin air-stone bar lying flat along the back wall. Wide, even bubble
# curtain. Visually about 60% of tank width.
func _build_stick_aerator(parent: Node, anchor_x: float) -> void:
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


# --- Filter (hang-on-back) ---
# Vertical intake/return tube. Bottom strainer sits just above the substrate;
# the tube rises through the water column to just above the surface where a
# horizontal spout pushes water (and a trickle of air-entrained bubbles)
# outward into the tank.
func _build_filter_aerator(parent: Node, anchor_x: float) -> void:
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
		mi.material_override = VoxelMat.make(col)
		mi.position = Vector3(anchor_x, y, sz)
		parent.add_child(mi)
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
	# leave sim.filter_intake_pos at Vector3.ZERO (Microfauna.gd treats
	# that as "no intake, ignore").
	if sim != null:
		sim.filter_intake_pos = intake.position
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
	p.lifetime = clampf(rise_distance / 1.3, 2.5, 6.0)
	p.preprocess = p.lifetime * 0.5
	p.local_coords = false
	p.position = base_pos
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3(0, 0.9, 0)
	pm.spread = 5.0
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	p.process_material = pm
	var bm := SphereMesh.new()
	bm.radius = bubble_radius
	bm.height = bubble_radius * 2.0
	bm.radial_segments = 5
	bm.rings = 3
	bm.material = VoxelMat.make(Color8(200, 230, 235))
	p.draw_pass_1 = bm
	parent.add_child(p)


# Filter outflow: a horizontal-ish jet of bubbles + flow streaks coming out
# of the spout. Bubbles have less buoyancy and more forward velocity so the
# stream curves down into the tank before rising again.
func _emit_filter_outflow(parent: Node, spout_end: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 14
	p.lifetime = 2.0
	p.preprocess = 0.5
	p.local_coords = false
	p.position = spout_end
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -0.2, 1).normalized()
	pm.initial_velocity_min = 0.9
	pm.initial_velocity_max = 1.3
	pm.gravity = Vector3(0, 0.7, 0)         # buoyancy reasserts itself
	pm.spread = 12.0
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.05, 0.08, 0.02)
	p.process_material = pm
	var bm := SphereMesh.new()
	bm.radius = 0.07
	bm.height = 0.14
	bm.radial_segments = 5
	bm.rings = 3
	bm.material = VoxelMat.make(Color8(200, 230, 235))
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
	# Flat ring mesh - just a thin box that scales up.
	var rm := BoxMesh.new()
	rm.size = Vector3(0.55, 0.04, 0.55)
	rm.material = VoxelMat.make(Color8(220, 235, 240))
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
	# Pick a random wall and a position along it just below the waterline.
	var wall_pick: int = randi() % 4
	var x: float = 0.0
	var z: float = 0.0
	match wall_pick:
		0:  # back wall
			x = randf_range(-TANK_HALF_W + 0.5, TANK_HALF_W - 0.5)
			z = -TANK_HALF_D + 0.04
		1:  # front wall
			x = randf_range(-TANK_HALF_W + 0.5, TANK_HALF_W - 0.5)
			z = TANK_HALF_D - 0.04
		2:  # left wall
			x = -TANK_HALF_W + 0.04
			z = randf_range(-TANK_HALF_D + 0.5, TANK_HALF_D - 0.5)
		_:  # right wall
			x = TANK_HALF_W - 0.04
			z = randf_range(-TANK_HALF_D + 0.5, TANK_HALF_D - 0.5)
	# Y just below the meniscus, with a small vertical jitter so the
	# spots distribute as a smear along the waterline rather than a
	# perfect line.
	var y: float = WATER_HEIGHT - randf_range(0.04, 0.4)
	var spot := MeshInstance3D.new()
	spot.mesh = VoxelMat.get_box(Vector3(0.10, 0.06, 0.10))
	spot.material_override = VoxelMat.make(Color8(225, 230, 235))
	spot.position = Vector3(x, y, z)
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
	var desk_mat: ShaderMaterial = VoxelMat.make(desk_color)
	var desk_dark_mat: ShaderMaterial = VoxelMat.make(desk_color.darkened(0.18))
	var wall_mat: ShaderMaterial = VoxelMat.make(wall_color)
	var accent_mat: ShaderMaterial = VoxelMat.make(accent_color)

	# Desk surface. Three-ish-voxel-thick wooden slab the tank sits on,
	# extending out from the tank footprint on all sides so the bottom of
	# the glass reads as resting on a real surface, not levitating.
	var desk_y: float = -0.6
	var desk_half_w: float = TANK_HALF_W + 5.0
	var desk_half_d: float = TANK_HALF_D + 4.0
	var desk_thickness: float = 1.2
	# Build the desk as a 2D grid of "plank" voxels with light grain.
	# Each row alternates dark / light so the wood has a visible grain
	# without a custom texture.
	var plank_size: float = 0.7
	var nx: int = int(desk_half_w * 2.0 / plank_size) + 1
	var nz: int = int(desk_half_d * 2.0 / plank_size) + 1
	for ix in nx:
		for iz in nz:
			var px: float = -desk_half_w + (float(ix) + 0.5) * plank_size
			var pz: float = -desk_half_d + (float(iz) + 0.5) * plank_size
			var grain: bool = (ix + iz) % 2 == 0
			var mi := MeshInstance3D.new()
			mi.mesh = VoxelMat.get_box(Vector3(plank_size * 0.96,
				desk_thickness, plank_size * 0.96))
			mi.material_override = desk_mat if grain else desk_dark_mat
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
	var include_window: bool = bool(preset.get("include_window", false))
	var window_w_half: float = 3.5
	var window_h_half: float = 2.5
	var window_center_y: float = desk_y + 4.5
	
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
					
			var subtle: bool = ((r * 3 + col) % 5) == 0
			var brick := MeshInstance3D.new()
			brick.mesh = VoxelMat.get_box(Vector3(brick_w * 0.96, brick_h * 0.96, 0.4))
			brick.material_override = accent_mat if subtle else wall_mat
			brick.position = Vector3(bx, by, wall_z)
			room.add_child(brick)

	# Build window frame/sky if active
	if include_window:
		_build_room_window(room, wall_z, wall_mat, desk_dark_mat, preset)

	# Soft warm room light from the side — simulates a window or lamp.
	# Energy is low (0.18) so it doesn't blow out the tank's own fixture.
	var room_light := OmniLight3D.new()
	room_light.light_color = light_color
	room_light.light_energy = 0.18
	room_light.omni_range = 36.0
	room_light.omni_attenuation = 1.6
	room_light.position = Vector3(desk_half_w + 2.0, desk_y + 6.0, wall_z + 4.0)
	room.add_child(room_light)

	# Lamp (preset-controlled). Tall thin stand + a glowing shade on the
	# left side of the desk, just outside the tank's footprint.
	if bool(preset.get("include_lamp", false)):
		_build_room_lamp(room, Vector3(-desk_half_w + 2.0, desk_y, -desk_half_d + 1.6),
			accent_color, light_color)

	# Book stack on the right side of the desk.
	if bool(preset.get("include_books", false)):
		_build_room_books(room, Vector3(desk_half_w - 2.4, desk_y + 0.05,
			-desk_half_d + 1.4))

	# Small house plant in front of the wall, to one side.
	if bool(preset.get("include_plant", false)):
		_build_room_plant(room, Vector3(-desk_half_w + 2.0, desk_y + 0.05,
			-desk_half_d + 2.6))

	# Cozy Steaming Coffee/Tea Mug
	if bool(preset.get("include_mug", false)):
		_build_room_mug(room, Vector3(desk_half_w - 3.4, desk_y, -desk_half_d + 1.8), accent_color)

	# Vintage Alarm Clock (Functioning)
	if bool(preset.get("include_clock", false)):
		_build_room_clock(room, Vector3(desk_half_w - 1.2, desk_y, -desk_half_d + 1.8), accent_color)

	# Interactive Record Player
	if bool(preset.get("include_record_player", false)):
		_build_room_record_player(room, Vector3(-desk_half_w + 4.2, desk_y, -desk_half_d + 1.8))

	# Dynamic Lava Lamp
	if bool(preset.get("include_lava_lamp", false)):
		_build_room_lava_lamp(room, Vector3(-desk_half_w + 2.0, desk_y, -desk_half_d + 1.6),
			Color8(160, 160, 165), accent_color)



func _build_room_window(parent: Node3D, wall_z: float, wall_mat: Material,
		frame_mat: Material, preset: Dictionary) -> void:
	# Sky Backing: placed slightly behind the wall.
	# Size: 7.0 wide, 5.0 tall, 0.1 deep.
	var sky_w := 7.0
	var sky_h := 5.0
	var sky_y := -0.6 + 4.5 # desk_y + 4.5 = 3.9
	
	var sky := MeshInstance3D.new()
	sky.mesh = VoxelMat.get_box(Vector3(sky_w, sky_h, 0.1))
	
	# Create sky material (duplicated so we can change its color in _process)
	var sky_base_col_rgb: Array = preset.get("light_color", [255, 235, 200])
	var sky_base_col := Color8(sky_base_col_rgb[0], sky_base_col_rgb[1], sky_base_col_rgb[2])
	_room_sky_mat = VoxelMat.make(sky_base_col).duplicate()
	sky.material_override = _room_sky_mat
	sky.position = Vector3(0.0, sky_y, wall_z - 0.2)
	parent.add_child(sky)
	
	# Spawn stars outside the window (Z = wall_z - 0.15).
	# Star meshes are tiny white voxel boxes.
	_room_stars.clear()
	var star_positions := [
		Vector3(-2.2, sky_y + 1.6, wall_z - 0.18),
		Vector3(-1.1, sky_y + 0.8, wall_z - 0.18),
		Vector3(0.4, sky_y + 2.0, wall_z - 0.18),
		Vector3(1.8, sky_y + 1.2, wall_z - 0.18),
		Vector3(2.5, sky_y + 0.4, wall_z - 0.18),
	]
	var star_mat := VoxelMat.make(Color8(255, 255, 240)) # unshaded white
	for pos in star_positions:
		var star := MeshInstance3D.new()
		star.mesh = VoxelMat.get_box(Vector3(0.08, 0.08, 0.08))
		star.material_override = star_mat
		star.position = pos
		star.visible = false # starts hidden during daylight
		parent.add_child(star)
		_room_stars.append(star)
		
	# Window Frame (Z = wall_z):
	# Outer frame: left, right, top, bottom border.
	# We construct this from boxes to keep the voxel style clean.
	var frame_thickness := 0.25
	var frame_depth := 0.5
	
	# Left vertical frame
	var f_left := MeshInstance3D.new()
	f_left.mesh = VoxelMat.get_box(Vector3(frame_thickness, sky_h + frame_thickness, frame_depth))
	f_left.material_override = frame_mat
	f_left.position = Vector3(-sky_w * 0.5 - frame_thickness * 0.5, sky_y, wall_z)
	parent.add_child(f_left)
	
	# Right vertical frame
	var f_right := MeshInstance3D.new()
	f_right.mesh = VoxelMat.get_box(Vector3(frame_thickness, sky_h + frame_thickness, frame_depth))
	f_right.material_override = frame_mat
	f_right.position = Vector3(sky_w * 0.5 + frame_thickness * 0.5, sky_y, wall_z)
	parent.add_child(f_right)
	
	# Top horizontal frame
	var f_top := MeshInstance3D.new()
	f_top.mesh = VoxelMat.get_box(Vector3(sky_w + frame_thickness * 2.0, frame_thickness, frame_depth))
	f_top.material_override = frame_mat
	f_top.position = Vector3(0.0, sky_y + sky_h * 0.5 + frame_thickness * 0.5, wall_z)
	parent.add_child(f_top)
	
	# Bottom horizontal frame (sill)
	var f_bottom := MeshInstance3D.new()
	f_bottom.mesh = VoxelMat.get_box(Vector3(sky_w + frame_thickness * 2.0, frame_thickness * 1.5, frame_depth * 1.2))
	f_bottom.material_override = frame_mat
	f_bottom.position = Vector3(0.0, sky_y - sky_h * 0.5 - frame_thickness * 0.75, wall_z + frame_depth * 0.05)
	parent.add_child(f_bottom)
	
	# Mullions / Inner grid frames:
	# We can do a vertical bar in the center and a horizontal bar.
	var m_vert := MeshInstance3D.new()
	m_vert.mesh = VoxelMat.get_box(Vector3(0.12, sky_h, frame_depth * 0.7))
	m_vert.material_override = frame_mat
	m_vert.position = Vector3(0.0, sky_y, wall_z + 0.05)
	parent.add_child(m_vert)
	
	var m_horiz := MeshInstance3D.new()
	m_horiz.mesh = VoxelMat.get_box(Vector3(sky_w, 0.12, frame_depth * 0.7))
	m_horiz.material_override = frame_mat
	m_horiz.position = Vector3(0.0, sky_y, wall_z + 0.05)
	parent.add_child(m_horiz)


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
	var cream: Color = Color(1.28, 1.22, 1.10)  # warm-white biofilm
	# Higher progress → smaller denominator → more voxels tinted.
	# At progress=0.0, denom≈20 → ~5% tinted.
	# At progress=0.65, denom≈2 → ~half tinted.
	var denom: int = maxi(1, int(round(20.0 - biofilm_progress * 28.0)))
	for i in _driftwood_voxels.size():
		var vx: MeshInstance3D = _driftwood_voxels[i]
		if not is_instance_valid(vx):
			continue
		var tinted: bool = (hash(i * 73 + 13) % denom) == 0
		if tinted:
			# Tint strength rises with overall biofilm progress so the
			# pattern intensifies over time rather than just flipping on.
			var t: Color = Color(1, 1, 1).lerp(
				cream, clampf(biofilm_progress / 0.65, 0.0, 1.0))
			_apply_driftwood_biofilm(vx, t)
		else:
			_clear_driftwood_biofilm(vx)


func _apply_driftwood_biofilm(vx: MeshInstance3D, tint: Color) -> void:
	var sm: ShaderMaterial = vx.material_override as ShaderMaterial
	if sm == null:
		return
	var orig: Color
	if vx.has_meta("base_albedo"):
		orig = vx.get_meta("base_albedo")
	else:
		orig = sm.get_shader_parameter("albedo")
		vx.set_meta("base_albedo", orig)
	if not vx.has_meta("tint_mat"):
		vx.material_override = sm.duplicate() as ShaderMaterial
		vx.set_meta("tint_mat", true)
	(vx.material_override as ShaderMaterial).set_shader_parameter(
		"albedo", orig * tint)


func _clear_driftwood_biofilm(vx: MeshInstance3D) -> void:
	if not vx.has_meta("tint_mat"):
		return
	var orig: Color = vx.get_meta("base_albedo")
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
		mi.position = pos + spread
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
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.20, 0.07, 0.20)
	mi.mesh = bm
	mi.position = Vector3(pos.x, column_surface_y(pos.x, pos.z) + 0.05, pos.z)
	mi.material_override = VoxelMat.make(Color8(34, 26, 18))
	container.add_child(mi)
	_mulm_voxels.append(mi)


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
	# Bootstrap in two phases to avoid a startup GPU spike on Metal:
	# seed a visible base population immediately, then refill the rest
	# through the normal maintenance cadence.
	var initial_seed: int = mini(count, 16)
	_microfauna_bootstrap_remaining = maxi(0, count - initial_seed)
	for i in initial_seed:
		_spawn_one_microfauna()


func _microfauna_swarm_fill() -> float:
	if microfauna_root == null:
		return 0.0
	var cap: int = maxi(1, microfauna_carrying_capacity())
	return clampf(float(microfauna_root.get_child_count()) / float(cap), 0.0, 1.0)


func _refresh_microfauna_visibility() -> void:
	if microfauna_root == null:
		return
	var fill: float = _microfauna_swarm_fill()
	for child in microfauna_root.get_children():
		if child is Microfauna:
			(child as Microfauna).set_swarm_presence(fill)


func _spawn_one_microfauna() -> void:
	if microfauna_root == null or sim == null:
		return
	var fill: float = _microfauna_swarm_fill()
	var b: AABB = sim.world_bounds
	# Reject samples outside the (possibly non-rectangular) tank shape, so
	# hex / triangle tanks don't get microfauna floating in the corner air.
	# Tries up to 6 times before giving up — at 90 microfauna a single
	# missed spawn isn't visible.
	for _attempt in 16:
		var pt: Vector3 = _sample_point_in_tank(
			b.position.y, b.position.y + b.size.y, 0.35)
		if not is_inside_tank_volume(pt.x, pt.y, pt.z, 0.35):
			continue
		var m := Microfauna.new()
		m.set_swarm_presence(fill)
		microfauna_root.add_child(m)
		m.sim = sim
		m.position = pt
		# Stagger initial age so the population doesn't all die at once.
		m._age = randf_range(0.0, Microfauna.LIFESPAN_S * 0.6)
		return


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
	_microfauna_refill_t = maxf(0.0, _microfauna_refill_t - sdt)
	if _microfauna_refill_t > 0.0:
		return
	_microfauna_refill_t = 0.8  # next refill in ~0.8 sim-seconds
	if microfauna_root == null:
		return
	var have: int = microfauna_root.get_child_count()
	var target: int = microfauna_carrying_capacity()
	# Spawn up to ~4 per window so the swarm refreshes gradually rather
	# than popping in a burst whenever a few age out simultaneously.
	if _microfauna_bootstrap_remaining > 0:
		target = maxi(target, have + mini(_microfauna_bootstrap_remaining, 4))
	var deficit: int = target - have
	var to_spawn: int = mini(deficit, 3)
	for i in to_spawn:
		_spawn_one_microfauna()
	if _microfauna_bootstrap_remaining > 0:
		_microfauna_bootstrap_remaining = maxi(0, _microfauna_bootstrap_remaining - to_spawn)
	_microfauna_vis_t = maxf(0.0, _microfauna_vis_t - sdt)
	if _microfauna_vis_t <= 0.0:
		_microfauna_vis_t = 2.5
		_refresh_microfauna_visibility()


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
		"plant":
			if bool(genome.get("floating", false)):
				return spawn_floating_plant(genome)
			var p_xz: Vector2 = _sample_substrate_xz(0.35, 0.46, 0.45)
			var cfg: Dictionary = {
				"max_height": int(genome.get("max_height", 12)),
				"growth_rate": float(genome.get("growth_rate", 0.18)),
				"sway_amplitude": float(genome.get("sway_amplitude", 0.25)),
				"leaf_form": String(genome.get("leaf_form", "column")),
				"leaf_length": int(genome.get("leaf_length", 4)),
				"max_roots": int(genome.get("max_roots", 5)),
				"generation": int(genome.get("generation", 0)) + 1,
				"parent_lineage": String(genome.get("plant_name", "Library stock")),
			}
			spawn_seedling(spawn_position_on_floor(p_xz.x, p_xz.y),
				genome.get("ramp_override", []), cfg["generation"], cfg)
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
	fauna_root.add_child(f)
	f.global_position = clamp_xyz_in_tank(pos, 0.35)
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
	sn.position = pos
	sn.set("wall_normal", Vector3.UP)
	sn.set("wall_min", Vector3(-TANK_HALF_W + 0.4, SUBSTRATE_DEPTH + 0.05, -TANK_HALF_D + 0.4))
	sn.set("wall_max", Vector3(TANK_HALF_W - 0.4, WATER_HEIGHT - 0.2, TANK_HALF_D - 0.4))
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
	# Number from TankConfig preset.
	var sh_cfg := get_node_or_null("/root/TankConfig")
	var shrimp_n: int = 12
	if sh_cfg != null:
		var preset: Dictionary = sh_cfg.current_tank_preset()
		if sh_cfg.tank_preset == "custom":
			shrimp_n = int(sh_cfg.custom_shrimp_count)
		else:
			shrimp_n = int(preset.get("shrimp", 12))
	var phenotype_mult: float = _initial_phenotype_spread()
	# Roughly 2/3 reds + 1/3 ambers. Start as adults so breeding kicks in soon.
	var red_n: int = int(shrimp_n * 2.0 / 3.0)
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
