# Vivarium 3D voxel world.
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
var algae_root: Node3D = null
# Driftwood voxels captured in _build_hardscape so the biofilm tick can
# tint a growing fraction over time. Real driftwood develops a fuzzy
# white biofilm in the first 1-2 weeks of a new tank, then settles back
# as bacteria balance out and shrimp / otos graze it.
var _driftwood_voxels: Array[MeshInstance3D] = []
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
const MICROFAUNA_TARGET: int = 90
# Worms spawn at roughly half the mulm-voxel rate so a fresh tank has
# almost no worms and a long-running one develops a visible carpet.
const WRIGGLE_PER_MULM_FRAC: float = 0.55
const WRIGGLE_MAX: int = 90
# Maintenance cadence — refilling every frame is fine cost-wise but the
# RNG variance reads better when we batch into 0.8 s slices.
var _microfauna_refill_t: float = 0.0
var _wriggle_refill_t: float = 0.0

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
const CORAL_RECRUIT_MIN: float = 35.0
const CORAL_RECRUIT_MAX: float = 65.0
const CORAL_MAX: int = 60                 # cap so reefs don't carpet
# Tank shape: "box" / "cube" / "hex" / "triangle". Read from TankConfig.
var TANK_SHAPE: String = "box"

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
var fauna_root: Node3D = null
var plants_root: Node3D = null
var waste_root: Node3D = null


func _ready() -> void:
	# Pull tank dimensions + substrate profile from the autoload config.
	# Settings panel writes here and reloads the scene to apply.
	var cfg := get_node_or_null("/root/TankConfig")
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
		if TANK_SHAPE == "cube":
			var m: float = minf(TANK_HALF_W, TANK_HALF_D)
			TANK_HALF_W = m
			TANK_HALF_D = m
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

	# Seed comes from env var VIVARIUM_SEED if set, otherwise default. Lets
	# users replay a specific tank by exporting the env var before launch.
	var seed_env: String = OS.get_environment("VIVARIUM_SEED")
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
	substrate_grid.init(TANK_HALF_W, TANK_HALF_D, 1.0)
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
		Vector3(-TANK_HALF_W + 0.3, SUBSTRATE_DEPTH + 0.2, -TANK_HALF_D + 0.3),
		Vector3((TANK_HALF_W - 0.3) * 2.0, WATER_HEIGHT - SUBSTRATE_DEPTH - 0.4,
				(TANK_HALF_D - 0.3) * 2.0)
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
	_build_hardscape()
	_build_water_volume()
	_build_glass()
	_build_snails()  # static decor
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
			print_verbose("[vivarium] save substrate mismatch (saved=%s, current=%s); discarding state.json" % [
				saves.peek_saved_substrate_type(), cur_sub,
			])
			saves.clear_active_state()
		loading_from_save = saves.has_state_for_active_slot()

	# Saltwater branch: ocean_sand substrate replaces freshwater plants
	# with a reef of corals. Floaters / lily pads / math plants don't
	# exist in saltwater either (they're freshwater forms) so we skip
	# them entirely. Shrimp are also skipped further down via the same
	# is_saltwater check.
	if not loading_from_save:
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
		# If loading from save, we still need to spawn the procedural freshwater floaters,
		# lily pads, and math plants since they are not saved in the save file.
		if not bool(_active_substrate_profile.get("is_saltwater", false)):
			_spawn_floaters()
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
	_spawn_initial_microfauna(MICROFAUNA_TARGET)
	# Make sure SimDriver can find the snails container for predator AI.
	sim.snails_root = get_node_or_null("Snails")
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

	print_verbose("[vivarium] world built: ", get_child_count(), " top-level nodes; ",
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



func _process(dt: float) -> void:
	var sdt: float = dt
	if sim != null:
		sdt = dt * float(sim.time_scale)

	# Update lofi room environment animations
	_room_time_passed += sdt
	
	if sim != null:
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
	if _room_clock_hour_pivot != null and _room_clock_min_pivot != null:
		var sys_time := Time.get_time_dict_from_system()
		var hr: float = float(sys_time.hour)
		var mn: float = float(sys_time.minute)
		var sc: float = float(sys_time.second)
		
		_room_clock_hour_pivot.rotation.z = -((int(hr) % 12) + mn / 60.0 + sc / 3600.0) * (TAU / 12.0)
		_room_clock_min_pivot.rotation.z = -(mn + sc / 60.0) * (TAU / 60.0)

	# 4. Update spinning vinyl record disc (synced to music state)
	if _room_record_disc != null:
		var cfg_player := get_node_or_null("/root/TankConfig")
		var target_speed: float = 1.5 if (cfg_player != null and cfg_player.music_enabled) else 0.0
		_room_record_speed = lerpf(_room_record_speed, target_speed, sdt * 2.0)
		if _room_record_speed > 0.001:
			_room_record_disc.rotate_y(-sdt * _room_record_speed)

	# 5. Update Lava Lamp blobs & glow
	if _room_lava_lamp_blobs.size() >= 2:
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
		# Slow rise (~5 min to reach 0.6), then very slow decay past 0.65.
		var delta: float = (target - biofilm_progress) * sdt * 0.004 + sdt * 0.0008
		biofilm_progress = clampf(biofilm_progress + delta, 0.0, 0.7)
		_apply_biofilm_tints()
	# Coral recruitment (saltwater tanks only). Every CORAL_RECRUIT_INTERVAL
	# sim-seconds a fresh polyp appears somewhere on the substrate, mimicking
	# the larval-drift-and-settle mechanism that keeps real reefs replenished
	# even as older corals get grazed or die. Capped at CORAL_MAX so the
	# reef can't carpet the entire tank.
	if bool(_active_substrate_profile.get("is_saltwater", false)):
		_coral_recruit_timer = maxf(0.0, _coral_recruit_timer - sdt)
		if _coral_recruit_timer <= 0.0:
			_coral_recruit_timer = randf_range(CORAL_RECRUIT_MIN, CORAL_RECRUIT_MAX)
			_maybe_recruit_coral()
	# Tannins: slow rise toward a cap (driftwood + leaves leak organics into
	# the water column). Visible as a warm brown tint that deepens over time.
	if tannins < 0.35:
		tannins = minf(0.35, tannins + 0.00005 * sdt)
	if _water_material_ref != null:
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
		var cfg2 := get_node_or_null("/root/TankConfig")
		var max_energy: float = 0.5
		var warmth: float = 0.6
		if cfg2 != null:
			max_energy = float(cfg2.light_energy)
			warmth = float(cfg2.light_warmth)
		var beam_color: Color = Color(0.55, 0.65, 0.95).lerp(
			Color(1.0, 0.95, 0.80), warmth)
		# Ambient room light: low energy, broad.
		if _directional_light != null:
			_directional_light.light_color = beam_color
			_directional_light.light_energy = 0.05 + dl * (max_energy * 0.45)
		# Fixture spot lights: strong focused beam.
		var spot_energy: float = 0.4 + dl * (max_energy * 6.0)
		for spot in _light_fixture_spots:
			if not is_instance_valid(spot):
				continue
			spot.light_color = beam_color
			spot.light_energy = spot_energy

		# Sync caustics material.
		if _caustics_mat != null:
			var show_caustics: bool = true
			if cfg2 != null:
				show_caustics = bool(cfg2.light_caustics)
			
			var intensity: float = 0.0
			if show_caustics:
				# Scale caustics intensity by daylight and max energy.
				intensity = clampf(dl * max_energy * 2.0, 0.0, 1.0)
				_caustics_mat.set_shader_parameter("caustic_intensity", intensity)
				_caustics_mat.set_shader_parameter("light_color", beam_color)
			else:
				_caustics_mat.set_shader_parameter("caustic_intensity", 0.0)
			
			# Propagate these dynamic updates to all cached substrate/hardscape caustics materials
			VoxelMat.update_caustic_uniforms(intensity, beam_color)

		# Sync god ray materials to the light cycle and Render panel parameters.
		var density: float = 0.02
		var anisotropy: float = 0.3
		if cfg2 != null:
			density = float(cfg2.fog_density)
			anisotropy = float(cfg2.fog_anisotropy)
		
		# Base beam opacity scales with daylight + user density settings
		var base_alpha: float = density * 4.0
		var ray_alpha: float = base_alpha * (0.15 + dl * 0.85) * (max_energy / 0.5)
		var ray_color := Color(beam_color.r, beam_color.g, beam_color.b, ray_alpha)
		var exponent: float = lerp(1.5, 4.0, (anisotropy + 0.9) / 1.8)
		
		for mat in _god_ray_materials:
			if mat != null:
				mat.set_shader_parameter("beam_color", ray_color)
				mat.set_shader_parameter("falloff_exponent", exponent)

	# Floater drift: each surface plant wanders gently on a sin curve.
	# Filter out queue_freed floaters (e.g. eaten by surface-feeding guppies).
	_floater_t += sdt
	var dead_floaters: Array = []
	for f in _floaters:
		if not is_instance_valid(f):
			dead_floaters.append(f)
			continue
		var fn: Node3D = f
		var ph: float = fn.get_meta("phase", 0.0)
		fn.position.x += sin(_floater_t * 0.15 + ph) * 0.05 * sdt
		fn.position.z += cos(_floater_t * 0.12 + ph * 1.3) * 0.05 * sdt
		# Slight bob.
		fn.position.y = WATER_HEIGHT - 0.05 + sin(_floater_t * 0.7 + ph) * 0.015
		# Soft clamp inside the tank.
		fn.position.x = clampf(fn.position.x, -TANK_HALF_W * 0.9, TANK_HALF_W * 0.9)
		fn.position.z = clampf(fn.position.z, -TANK_HALF_D * 0.9, TANK_HALF_D * 0.9)
	for df in dead_floaters:
		_floaters.erase(df)

	# Lily pad gentle sway. Each pad runs its own _t-based sin curve.
	# Math plants - their tick is what makes the nautilus / cattail / moss
	# nodes visibly sway. Filter dead refs in case any get queue_freed (eg
	# eaten by future grazer pass).
	for mp in _math_plants:
		if not is_instance_valid(mp):
			continue
		if mp.has_method("tick"):
			mp.tick(sdt)
	_lily_pad_t += sdt
	for lp in _lily_pads:
		if not is_instance_valid(lp):
			continue
		if lp.has_method("tick"):
			lp.tick(sdt)

	# Duckweed propagation. Every DUCKWEED_PROP_INTERVAL sim seconds, IF the
	# population is below DUCKWEED_CAP, spawn a fresh clump near a randomly
	# chosen existing floater. Duckweed in a real Walstad tank doubles every
	# ~3 days; we tune it to feel similar in compressed sim time. Density is
	# capped so the surface doesn't fully block out the light beams.
	const DUCKWEED_PROP_INTERVAL: float = 18.0
	const DUCKWEED_CAP: int = 42
	_duckweed_accum += sdt
	if _duckweed_accum >= DUCKWEED_PROP_INTERVAL and _floaters.size() < DUCKWEED_CAP \
			and _floaters.size() > 0:
		_duckweed_accum = 0.0
		var parent: Node3D = _floaters[_rng.randi_range(0, _floaters.size() - 1)]
		if is_instance_valid(parent):
			# New clump appears 0.5-1.0 unit from parent in a random direction.
			var ang: float = _rng.randf_range(0.0, TAU)
			var r: float = _rng.randf_range(0.5, 1.0)
			var nx: float = parent.position.x + cos(ang) * r
			var nz: float = parent.position.z + sin(ang) * r
			if _is_inside_tank(nx, nz, 0.4):
				_add_floater_at(Vector3(nx, WATER_HEIGHT - 0.05, nz))


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
func is_inside_tank(x: float, z: float, margin: float = 0.0) -> bool:
	return _is_inside_tank(x, z, margin)


# Public XZ sampler. Used by SimDriver when it needs a random tank-interior
# position for algae or anything else spawned at runtime, without exposing
# the private RNG / sampling internals.
func sample_xz_in_tank(margin: float = 0.4) -> Vector2:
	return _random_xz_in_band(-TANK_HALF_D + margin, TANK_HALF_D - margin, margin)


func _is_inside_tank(x: float, z: float, margin: float = 0.0) -> bool:
	# Point-in-shape test for the tank footprint. margin > 0 returns true
	# only for points well inside the shape (used for spawn placement).
	var hw: float = TANK_HALF_W - margin
	var hd: float = TANK_HALF_D - margin
	if hw <= 0.0 or hd <= 0.0:
		return false
	match TANK_SHAPE:
		"hex":
			# Regular hexagon inscribed in 2*hw x 2*hd rect. Use normalised
			# coords; standard point-in-hex test.
			var q: float = absf(x) / hw
			var r: float = absf(z) / hd
			return q + r * 0.5 < 1.0 and r < 1.0
		"triangle":
			# Equilateral triangle pointing in +Z direction. Apex at z=+hd,
			# base at z=-hd between x=-hw..hw.
			if z > hd or z < -hd:
				return false
			var base_half: float = hw * (hd - z) / (2.0 * hd)
			return absf(x) <= base_half
		_:
			# box / cube - axis-aligned rectangle.
			return absf(x) <= hw and absf(z) <= hd


func _random_inside_tank(margin: float = 0.4) -> Vector3:
	# Rejection sampling to spawn inside non-rectangular shapes safely.
	for _i in 32:
		var x: float = _rng.randf_range(-TANK_HALF_W, TANK_HALF_W)
		var z: float = _rng.randf_range(-TANK_HALF_D, TANK_HALF_D)
		if _is_inside_tank(x, z, margin):
			return Vector3(x, 0, z)
	return Vector3.ZERO


# Like _random_inside_tank but allows constraining Z to a band (e.g. background
# strip, foreground carpet). Resamples until the (x, z) is inside the tank
# shape, falling back to (0, mid-of-band) if nothing fits in 32 tries (tiny
# triangle case).
func _random_xz_in_band(z_min: float, z_max: float, margin: float = 0.4) -> Vector2:
	for _i in 32:
		var x: float = _rng.randf_range(-TANK_HALF_W, TANK_HALF_W)
		var z: float = _rng.randf_range(z_min, z_max)
		if _is_inside_tank(x, z, margin):
			return Vector2(x, z)
	return Vector2(0.0, clampf((z_min + z_max) * 0.5, -TANK_HALF_D, TANK_HALF_D))


func _setup_caustics() -> void:
	pass # All caustics are now computed in a single opaque shader pass.


func _build_substrate() -> void:
	var container := Node3D.new()
	container.name = "Substrate"
	add_child(container)

	var voxel_size := 0.4
	var rows: int = int(SUBSTRATE_DEPTH / voxel_size)
	var cols: int = int((TANK_HALF_W * 2.0) / voxel_size)
	var depths: int = int((TANK_HALF_D * 2.0) / voxel_size)

	# First pass: collect transforms grouped by snapped color key and caustic status.
	# Each bucket is key -> {transforms: Array[Vector3], caustic: bool, color: Color}
	var buckets: Dictionary = {}
	var soil_rows: int = int(rows * 0.7)
	for r in rows:
		for c in cols:
			for d in depths:
				var x: float = -TANK_HALF_W + (c + 0.5) * voxel_size
				var z: float = -TANK_HALF_D + (d + 0.5) * voxel_size
				var y: float = (r + 0.5) * voxel_size
				# Skip voxels outside the tank shape (hex / triangle clip).
				if not _is_inside_tank(x, z, voxel_size * 0.25):
					continue
				if r == rows - 1 and _rng.randf() < 0.15:
					continue
				var color: Color
				var ramp: Array = ACTIVE_SOIL_RAMP if ACTIVE_SOIL_RAMP.size() == 6 else C_SOIL_RAMP
				if r < rows - soil_rows:
					color = C_GRAVEL.lerp(ramp[0], _rng.randf() * 0.4)
				else:
					var rel: float = float(r - (rows - soil_rows)) / float(maxi(1, soil_rows))
					var idx: int = clampi(int(rel * 5.0 + _rng.randf() * 1.5), 0, 5)
					color = ramp[idx]
				# Snap color to match VoxelMat cache granularity.
				var key := Color(snappedf(color.r, 0.01), snappedf(color.g, 0.01), snappedf(color.b, 0.01))
				var is_caustic: bool = (r >= rows - 2)
				var bucket_key := "%s_%d" % [key.to_html(false), 1 if is_caustic else 0]
				if not buckets.has(bucket_key):
					buckets[bucket_key] = {"transforms": [], "caustic": is_caustic, "color": key}
				buckets[bucket_key]["transforms"].append(Vector3(x, y, z))

	# Second pass: create one MultiMeshInstance3D per bucket (color + caustic status).
	var box_mesh: BoxMesh = VoxelMat.get_box(Vector3(voxel_size, voxel_size, voxel_size))
	for b_key in buckets:
		var bucket: Dictionary = buckets[b_key]
		var positions: Array = bucket["transforms"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = box_mesh
		mm.instance_count = positions.size()
		for i in positions.size():
			var t := Transform3D()
			t.origin = positions[i]
			mm.set_instance_transform(i, t)

		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		# Use the dedicated opaque/caustic substrate shaders to avoid transparency sorting/flickering.
		var mat: ShaderMaterial
		if bucket["caustic"]:
			mat = VoxelMat.make_substrate_caustic(bucket["color"])
		else:
			mat = VoxelMat.make_substrate_opaque(bucket["color"])
		mmi.material_override = mat
		container.add_child(mmi)



func _build_hardscape() -> void:
	var c := Node3D.new()
	c.name = "Hardscape"
	add_child(c)

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
		var mi_d := _add_cube(c, p, Vector3(size, size, size), mat_dark)
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
			var mi_l := _add_cube(c, p + offset, Vector3(size * 0.58, size * 0.58, size * 0.58), mat_light)
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
			
			var mi_d := _add_cube(c, twig_p, Vector3(size, size, size), mat_dark)
			_driftwood_voxels.append(mi_d)
			
			if size > 0.22:
				var mi_l := _add_cube(c, twig_p + Vector3(0.0, size * 0.42, 0.0), Vector3(size * 0.58, size * 0.58, size * 0.58), mat_light)
				_driftwood_voxels.append(mi_l)

	# 2. Japanese Iwagumi Rock Clusters
	var stone_mat := VoxelMat.make_substrate_caustic(C_STONE_LIGHT)
	var stone_dark := VoxelMat.make_substrate_caustic(C_STONE_DARK)

	var add_rock_voxel: Callable = func(center: Vector3, offset: Vector3, size: Vector3, is_dark: bool, rot: Vector3) -> MeshInstance3D:
		var m := stone_dark if is_dark else stone_mat
		var b_rot := Basis.from_euler(rot)
		var rotated_offset := b_rot * offset
		var mi := _add_cube(c, center + rotated_offset, size, m)
		mi.basis = b_rot * Basis.from_euler(Vector3(_rng.randf_range(-0.06, 0.06), _rng.randf_range(-0.06, 0.06), _rng.randf_range(-0.06, 0.06)))
		return mi

	# --- Main Island (Right side, off-center) ---
	var right_center := Vector3(3.6, SUBSTRATE_DEPTH, 0.4)
	var right_tilt := Vector3(0.2, -0.3, 0.35)
	# Oyaishi (Main Stone)
	add_rock_voxel.call(right_center, Vector3(0.0, -0.1, 0.0), Vector3(1.3, 0.8, 1.3), true, right_tilt)
	add_rock_voxel.call(right_center, Vector3(-0.15, 0.5, 0.1), Vector3(1.1, 0.8, 1.1), false, right_tilt)
	add_rock_voxel.call(right_center, Vector3(-0.3, 1.1, -0.05), Vector3(0.85, 0.9, 0.85), true, right_tilt)
	add_rock_voxel.call(right_center, Vector3(-0.45, 1.7, -0.1), Vector3(0.55, 0.65, 0.55), false, right_tilt)
	add_rock_voxel.call(right_center, Vector3(0.45, 0.1, -0.35), Vector3(0.7, 0.6, 0.7), false, right_tilt)
	add_rock_voxel.call(right_center, Vector3(-0.45, 0.25, 0.35), Vector3(0.6, 0.7, 0.6), true, right_tilt)

	# Fukuishi (Secondary Stone)
	var fuku_center := Vector3(4.8, SUBSTRATE_DEPTH, 0.05)
	var fuku_tilt := Vector3(0.15, -0.25, 0.3)
	add_rock_voxel.call(fuku_center, Vector3(0.0, -0.1, 0.0), Vector3(0.9, 0.7, 0.9), false, fuku_tilt)
	add_rock_voxel.call(fuku_center, Vector3(-0.1, 0.45, 0.08), Vector3(0.75, 0.75, 0.75), true, fuku_tilt)
	add_rock_voxel.call(fuku_center, Vector3(-0.2, 0.95, 0.0), Vector3(0.5, 0.6, 0.5), false, fuku_tilt)
	add_rock_voxel.call(fuku_center, Vector3(0.28, 0.1, 0.22), Vector3(0.5, 0.55, 0.5), true, fuku_tilt)

	# Soishi (Tertiary Stone)
	var soishi_center := Vector3(2.5, SUBSTRATE_DEPTH, 0.75)
	var soishi_tilt := Vector3(0.25, -0.4, 0.1)
	add_rock_voxel.call(soishi_center, Vector3(0.0, -0.08, 0.0), Vector3(0.68, 0.58, 0.68), true, soishi_tilt)
	add_rock_voxel.call(soishi_center, Vector3(0.08, 0.35, -0.08), Vector3(0.5, 0.5, 0.5), false, soishi_tilt)
	add_rock_voxel.call(soishi_center, Vector3(-0.18, 0.05, 0.18), Vector3(0.42, 0.42, 0.42), true, soishi_tilt)

	# Suteishi (Accents)
	var pebble_positions := [
		Vector3(1.9, SUBSTRATE_DEPTH - 0.08, 1.15),
		Vector3(3.1, SUBSTRATE_DEPTH - 0.08, -0.45),
		Vector3(5.15, SUBSTRATE_DEPTH - 0.08, 0.85)
	]
	var pebble_sizes := [0.45, 0.38, 0.42]
	var pebble_rots := [Vector3(0.12, 1.4, -0.15), Vector3(-0.25, 0.4, 0.18), Vector3(0.3, -0.8, -0.22)]
	for i in pebble_positions.size():
		var mi := _add_cube(c, pebble_positions[i], Vector3(pebble_sizes[i], pebble_sizes[i], pebble_sizes[i]), stone_dark if (i & 1) == 0 else stone_mat)
		mi.rotation = pebble_rots[i]

	# --- Secondary Island (Left side, balancing) ---
	var left_center := Vector3(-5.5, SUBSTRATE_DEPTH, 0.6)
	var left_tilt := Vector3(0.12, 0.3, -0.28)
	# Left Fukuishi
	add_rock_voxel.call(left_center, Vector3(0.0, -0.08, 0.0), Vector3(0.85, 0.68, 0.85), false, left_tilt)
	add_rock_voxel.call(left_center, Vector3(0.08, 0.4, -0.08), Vector3(0.68, 0.68, 0.68), true, left_tilt)
	add_rock_voxel.call(left_center, Vector3(0.15, 0.82, 0.0), Vector3(0.48, 0.55, 0.48), false, left_tilt)

	# Left Soishi
	var left_soishi := Vector3(-4.4, SUBSTRATE_DEPTH, 0.25)
	var left_soishi_tilt := Vector3(0.2, 0.25, -0.12)
	add_rock_voxel.call(left_soishi, Vector3(0.0, -0.08, 0.0), Vector3(0.62, 0.52, 0.62), true, left_soishi_tilt)
	add_rock_voxel.call(left_soishi, Vector3(0.06, 0.32, 0.06), Vector3(0.45, 0.45, 0.45), false, left_soishi_tilt)

	# Left Suteishi (Accents)
	var left_pebbles := [
		Vector3(-6.15, SUBSTRATE_DEPTH - 0.08, 0.95),
		Vector3(-3.85, SUBSTRATE_DEPTH - 0.08, 0.45),
		Vector3(-4.85, SUBSTRATE_DEPTH - 0.08, -0.35)
	]
	for i in left_pebbles.size():
		var mi := _add_cube(c, left_pebbles[i], Vector3(0.40, 0.40, 0.40), stone_mat if (i & 1) == 0 else stone_dark)
		mi.rotation = Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(0, PI), _rng.randf_range(-0.3, 0.3))


func _build_water_volume() -> void:
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


func _build_glass() -> void:
	var c := Node3D.new()
	c.name = "Glass"
	add_child(c)
	var glass := _glass_mat()
	# Build a polygon of glass walls around the tank's footprint. The
	# footprint is approximated as N corner points; each adjacent pair is
	# connected by a thin wall mesh.
	var corners: Array[Vector3] = _tank_footprint_corners()
	for i in corners.size():
		var p1: Vector3 = corners[i]
		var p2: Vector3 = corners[(i + 1) % corners.size()]
		_add_wall_between(c, p1, p2, TANK_HEIGHT, glass)


func _tank_footprint_corners() -> Array[Vector3]:
	# Return the corner points of the tank footprint at Y=0 in world space.
	# Order is CCW so wall normals point outward.
	var pts: Array[Vector3] = []
	match TANK_SHAPE:
		"hex":
			# Hexagon inscribed in the (2*hw) x (2*hd) box. 6 evenly spaced
			# points around the center.
			for i in 6:
				var a: float = (float(i) / 6.0) * TAU
				pts.append(Vector3(cos(a) * TANK_HALF_W, 0, sin(a) * TANK_HALF_D))
		"triangle":
			# Equilateral-ish triangle pointing in +Z.
			pts.append(Vector3(0, 0, TANK_HALF_D))
			pts.append(Vector3(-TANK_HALF_W, 0, -TANK_HALF_D))
			pts.append(Vector3(TANK_HALF_W, 0, -TANK_HALF_D))
		_:
			# Box / cube - 4 corners.
			pts.append(Vector3(TANK_HALF_W, 0, TANK_HALF_D))
			pts.append(Vector3(-TANK_HALF_W, 0, TANK_HALF_D))
			pts.append(Vector3(-TANK_HALF_W, 0, -TANK_HALF_D))
			pts.append(Vector3(TANK_HALF_W, 0, -TANK_HALF_D))
	return pts


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


func _build_snails() -> void:
	var c := Node3D.new()
	c.name = "Snails"
	add_child(c)
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
	# Freshwater = 6 turbos on the glass walls. Marine = mix of turbo,
	# trochus, and nassarius (the nassarius ride the substrate plane
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
			[Vector3(-7.95, 4.8, -1.5), Vector3(-1, 0, 0), "turbo"],
			[Vector3(7.95, 2.5, 1.0), Vector3(1, 0, 0), "turbo"],
			[Vector3(7.95, 4.5, -1.0), Vector3(1, 0, 0), "turbo"],
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
		c.add_child(snail)
		_build_snail_body(snail)
		if sim != null:
			sim.register_snail(snail)


func _build_snail_body(snail: Node3D) -> void:
	# Read heritable traits and shell silhouette. shell_shape branches
	# the construction into one of three forms:
	#   turbo      classic round low spiral (default, freshwater + marine)
	#   trochus    tall pointed cone (marine algae grazer)
	#   nassarius  small flat oval that lives on the substrate (marine
	#              scavenger; sits flatter and lower than a turbo)
	var shell_color: Color = snail.get("shell_color")
	var shell_size: float = snail.get("shell_size")
	var shell_shape: String = String(snail.get("shell_shape") if "shell_shape" in snail else "turbo")
	var shell_dark: Color = shell_color.darkened(0.22)
	var body_color: Color = C_SNAIL_BODY
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
		_:
			# turbo: round low spiral (the original snail shape).
			for i in 4:
				var ang: float = i * 0.7
				var r: float = (0.05 + i * 0.06) * shell_size
				var sp := Vector3(cos(ang) * r, sin(ang) * r, 0.0)
				var s: float = (0.16 - i * 0.02) * shell_size
				var mat: Material = shell_mat if (i & 1) == 0 else shell_dark_mat
				_add_cube(snail, sp, Vector3(s, s, s), mat)

	# Foot scales with shell. Nassarius foot is wider + flatter since they
	# crawl on substrate rather than glass.
	var foot_y: float = -0.05 * shell_size if shell_shape == "nassarius" else -0.12 * shell_size
	var foot_size: Vector3
	if shell_shape == "nassarius":
		foot_size = Vector3(0.28 * shell_size, 0.04 * shell_size, 0.20 * shell_size)
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

	# Tear down the old Snails container entirely rather than just freeing
	# its children — `sim.snails_root` was still pointing at that drained
	# container, so predator AI (fish.gd's snail_predator scan) and
	# `_emit_stats` would keep reading the dying container while
	# `_build_snails()` below added a NEW sibling named "Snails" that they
	# couldn't see. Free the parent and rebind sim.snails_root to the
	# freshly-built container at the end.
	if sim.snails_root != null and is_instance_valid(sim.snails_root):
		sim.snails_root.queue_free()
		sim.snails_root = null

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
			# Jitter spawn Y around the genome's preferred_y so respawned
			# schools don't all sit at exactly the same depth. _spawn_fish_at
			# will rescale this to the actual water column.
			var pref_y: float = float(g.get("preferred_y", 3.5))
			var spawn_y: float = pref_y + randf_range(-0.6, 0.6)
			var xz: Vector2 = _random_xz_in_band(-TANK_HALF_D * 0.85, TANK_HALF_D * 0.85, 0.6)
			_spawn_fish_at(g, Vector3(xz.x, spawn_y, xz.y))

	# Spawn Shrimp
	if stocking.has("shrimp"):
		var shrimp_count: int = stocking["shrimp"]
		for i in shrimp_count:
			var xz: Vector2 = _random_xz_in_band(-TANK_HALF_D * 0.85, TANK_HALF_D * 0.85, 0.6)
			var sp := Vector3(xz.x, SUBSTRATE_DEPTH + 0.1, xz.y)
			var s := Shrimp.new()
			fauna_root.add_child(s)
			s.global_position = sp
			s.base_color = Color.from_hsv(randf(), randf_range(0.6, 0.9), randf_range(0.5, 0.9))
			s.max_speed = randf_range(0.4, 0.6)
			s.max_age_s = randf_range(120.0, 180.0)
			s.age = randf_range(10.0, 40.0)
			s.maturity = Shrimp.MATURITY_ADULT
			sim.register_shrimp(s)

	# Snails: rebuild the container fresh, then rebind sim.snails_root to
	# point at it (the initial setup at line 186 does the same).
	_build_snails()
	sim.snails_root = get_node_or_null("Snails")
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
		{"name": "valli",    "max": [18, 26], "rate": 0.16, "sway": 0.22,
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

	# --- Background wall: thick valli forest ---
	for x_frac in [-0.92, -0.78, -0.65, -0.52, -0.38, -0.22, -0.08, 0.08,
				   0.22, 0.38, 0.52, 0.65, 0.78, 0.92]:
		var cx: float = x_frac * TANK_HALF_W
		var cz: float = _rng.randf_range(-TANK_HALF_D * 0.95, -TANK_HALF_D * 0.5)
		var n_blades: int = _rng.randi_range(5, 9)
		for i in n_blades:
			var px: float = cx + _rng.randf_range(-0.5, 0.5)
			var pz: float = cz + _rng.randf_range(-0.5, 0.5)
			# Skip if the jittered position pokes outside non-rect tank shapes.
			if not _is_inside_tank(px, pz, 0.3):
				continue
			_spawn_plant(species_specs[0], Vector3(px, SUBSTRATE_DEPTH, pz),
				_rng.randi_range(2, 5))
	await get_tree().process_frame

	# --- Midground rosettes (crypts) + red accent stems scattered ---
	for i in 28:
		var xz: Vector2 = _random_xz_in_band(-0.5, 1.5, 0.3)
		_spawn_plant(species_specs[1], Vector3(xz.x, SUBSTRATE_DEPTH, xz.y),
			_rng.randi_range(2, 4))
	await get_tree().process_frame
	for i in 14:
		var xz: Vector2 = _random_xz_in_band(-1.5, 1.5, 0.3)
		_spawn_plant(species_specs[3], Vector3(xz.x, SUBSTRATE_DEPTH, xz.y),
			_rng.randi_range(2, 4))
	await get_tree().process_frame

	# --- Foreground carpet: very dense ---
	for i in 55:
		var xz: Vector2 = _random_xz_in_band(TANK_HALF_D * 0.2, TANK_HALF_D * 0.95, 0.3)
		_spawn_plant(species_specs[2], Vector3(xz.x, SUBSTRATE_DEPTH, xz.y),
			_rng.randi_range(1, 3))
		# Yield mid-carpet too - this is the densest single block (55 plants).
		if i == 27:
			await get_tree().process_frame
	await get_tree().process_frame

	# --- Moss on the driftwood arch (epiphytes) ---
	for x in [-5.5, -4.0, -2.5, -1.0, 0.5, 1.8, 3.2, 4.5]:
		for off in [Vector3(0, 0.4, 0.2), Vector3(0.2, 0.5, -0.1), Vector3(-0.15, 0.45, 0.3)]:
			var arc_y: float = 2.0 + cos(x * 0.4) * 0.6
			_spawn_plant(species_specs[4], Vector3(x + off.x, arc_y, off.z),
				_rng.randi_range(1, 2))
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
		var sp_xz: Vector2 = _random_xz_in_band(-TANK_HALF_D * 0.8, TANK_HALF_D * 0.5, 0.55)
		sp.global_position = Vector3(sp_xz.x, SUBSTRATE_DEPTH, sp_xz.y)
		sp.ramp_override = spiral_ramps[i % spiral_ramps.size()]
		sp.water_surface_y = WATER_HEIGHT
		sp.generation = 0
		# Per-spawn horizontal budget: stay inside glass even near walls.
		var wall_x: float = TANK_HALF_W - absf(sp_xz.x) - 0.55
		var wall_z: float = TANK_HALF_D - absf(sp_xz.y) - 0.55
		sp.max_horizontal_extent = clampf(minf(wall_x, wall_z) * 0.85, 0.06, 0.12)
		sp.tank_wall_margin = 0.55
		sp.init(_rng.randi_range(3, 6), {
			"max_height": _rng.randi_range(14, 24),
			"growth_rate": 0.18,
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
		var bp_xz: Vector2 = _random_xz_in_band(-TANK_HALF_D * 0.85, TANK_HALF_D * 0.7, 0.4)
		bp.global_position = Vector3(bp_xz.x, SUBSTRATE_DEPTH, bp_xz.y)
		bp.ramp_override = fern_ramp
		bp.water_surface_y = WATER_HEIGHT
		bp.generation = 0
		bp.branch_chance = _rng.randf_range(0.3, 0.45)
		bp.branch_interval = _rng.randi_range(2, 4)
		bp.branch_angle_deg = _rng.randf_range(28.0, 45.0)
		bp.init(_rng.randi_range(2, 4), {
			"max_height": _rng.randi_range(10, 16),
			"growth_rate": 0.16,
			"sway_amplitude": 0.18,
		})
		sim.register_plant(bp)


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

	# --- Background: staghorn forest ---
	for x_frac in [-0.88, -0.62, -0.38, -0.12, 0.12, 0.38, 0.62, 0.88]:
		var cx: float = x_frac * TANK_HALF_W
		var cz: float = _rng.randf_range(-TANK_HALF_D * 0.95, -TANK_HALF_D * 0.55)
		if not _is_inside_tank(cx, cz, 0.4):
			continue
		var c := Coral.new()
		plants_root.add_child(c)
		c.global_position = Vector3(cx, SUBSTRATE_DEPTH, cz)
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
	for i in 10:
		var xz: Vector2 = _random_xz_in_band(-0.5, 1.0, 0.4)
		var c := Coral.new()
		plants_root.add_child(c)
		c.global_position = Vector3(xz.x, SUBSTRATE_DEPTH, xz.y)
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
	for i in 8:
		var xz: Vector2 = _random_xz_in_band(-1.5, 1.5, 0.5)
		var c := Coral.new()
		plants_root.add_child(c)
		c.global_position = Vector3(xz.x, SUBSTRATE_DEPTH, xz.y)
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
	for i in 6:
		var xz: Vector2 = _random_xz_in_band(TANK_HALF_D * 0.25, TANK_HALF_D * 0.95, 0.4)
		var c := Coral.new()
		plants_root.add_child(c)
		c.global_position = Vector3(xz.x, SUBSTRATE_DEPTH, xz.y)
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
 
 
func _maybe_recruit_coral() -> void:
	# Spawn a single fresh-larvae-sized coral somewhere on the substrate.
	# Respects CORAL_MAX so the reef doesn't carpet the tank. Form is
	# weighted toward the smaller varieties (dome / plate) since real
	# reef recruits start small and dome-shaped.
	if plants_root == null or sim == null:
		return
	var current_coral_count: int = 0
	for p in sim.plants:
		if p is Coral:
			current_coral_count += 1
	if current_coral_count >= CORAL_MAX:
		return
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
	# Weighted form pick: domes most common, then branching, occasionally feathery.
	var roll: float = randf()
	var form: String = "dome"
	if roll < 0.35:
		form = "dome"
	elif roll < 0.55:
		form = "brain"
	elif roll < 0.75:
		form = "branching"
	elif roll < 0.90:
		form = "staghorn_fern"
	else:
		form = "feathery"
	# Pick a substrate position inside the tank footprint.
	var xz: Vector2 = _random_xz_in_band(
		-TANK_HALF_D * 0.85, TANK_HALF_D * 0.85, 0.4)
	var pal: Array = palettes[_rng.randi() % palettes.size()]
	var c := Coral.new()
	plants_root.add_child(c)
	c.global_position = Vector3(xz.x, SUBSTRATE_DEPTH, xz.y)
	c.coral_form = form
	c.ramp_override = pal
	c.tip_color = pal[pal.size() - 1]
	c.water_surface_y = WATER_HEIGHT
	c.generation = 1
	c.init(1, {
		"max_height": _rng.randi_range(10, 18),
		"growth_rate": 0.15,
		"sway_amplitude": 0.04 if form == "feathery" else 0.0,
	})
	sim.register_plant(c)


func _spawn_plant(spec: Dictionary, pos: Vector3, initial_height: int) -> void:
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
# Spawns a tiny new plant nearby with the parent's mutated ramp + same
# rough max_height target. Capped via plants_alive size so we don't grow
# the field infinitely.
func spawn_seedling(pos: Vector3, ramp: Array, generation: int, seed_config: Dictionary) -> void:
	if plants_root == null or sim == null:
		return
	if sim.plants.size() >= 320:
		return
	# Clamp to substrate level and tank bounds.
	var sp: Vector3 = Vector3(
		clampf(pos.x, -TANK_HALF_W * 0.95, TANK_HALF_W * 0.95),
		SUBSTRATE_DEPTH,
		clampf(pos.z, -TANK_HALF_D * 0.95, TANK_HALF_D * 0.95),
	)
	var script: Script = seed_config.get("script", load("res://scripts/plant.gd"))
	var p = script.new()
	plants_root.add_child(p)
	p.global_position = sp
	if ramp.size() == 6:
		p.ramp_override = ramp
	p.water_surface_y = WATER_HEIGHT
	p.generation = generation
	
	# Inherit properties from parent and slightly mutate max_height
	var child_cfg: Dictionary = seed_config.duplicate()
	var parent_max: int = seed_config.get("max_height", 10)
	child_cfg["max_height"] = clampi(parent_max + _rng.randi_range(-2, 2), 4, 30)
	
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
			push_warning("[vivarium] unknown species in stocking: " + species_name)
			continue
		var template: Dictionary = entry.get("genome", {})
		for i in count:
			var g: Dictionary = template.duplicate(true)
			g["sex"] = i % 2
			# Jitter lifespan so the cohort doesn't synchronise its die-off.
			g["max_age_s"] = float(g.get("max_age_s", 240.0)) + randf_range(-30, 30)
			# Founding phenotype spread - varies by preset.
			_apply_initial_phenotype_spread(g, phenotype_mult)
			# Spawn at the species' preferred depth (plus jitter) and inside
			# the tank's footprint via shape-aware rejection sampling. Use
			# the FULL tank depth (not a narrow center band) so every fish
			# starts with a unique home_x / home_z - this is what spreads
			# the school across the tank instead of clumping at center.
			# NOTE: g["preferred_y"] is still the LEGACY value here; the
			# remap happens later inside _spawn_fish_at. To get the jitter
			# scaled to the actual column we precompute the column height
			# locally.
			var pref_y: float = float(g.get("preferred_y", 3.5))
			var _col: float = maxf(1.0, WATER_HEIGHT - SUBSTRATE_DEPTH)
			var _ref_frac: float = clampf(
				(pref_y - _REF_SUBSTRATE_Y) / _REF_COLUMN_HEIGHT, 0.05, 0.95)
			var pref_y_actual: float = SUBSTRATE_DEPTH + _ref_frac * _col
			# Jitter 12% of column on either side - in a 13.6-unit reef
			# column that's ~1.6 units of vertical spread per fish at
			# spawn, instead of the old absolute ±0.6.
			var spawn_y: float = pref_y_actual + randf_range(-0.12, 0.12) * _col
			var xz: Vector2 = _random_xz_in_band(
				-TANK_HALF_D * 0.85, TANK_HALF_D * 0.85, 0.6)
			_spawn_fish_at(g, Vector3(xz.x, spawn_y, xz.y))
			_fish_built += 1
			if _fish_built % 4 == 0:
				await get_tree().process_frame


var _light_fixture_root: Node3D = null
var _light_fixture_spots: Array[SpotLight3D] = []
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
		spot.shadow_enabled = false
		_light_fixture_root.add_child(spot)
		_light_fixture_spots.append(spot)

		if cfg != null and bool(cfg.light_volumetric):
			_add_god_ray_beam(_light_fixture_root, spot, 38.0, height_above)
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
			spot.shadow_enabled = false
			_light_fixture_root.add_child(spot)
			_light_fixture_spots.append(spot)

			if cfg != null and bool(cfg.light_volumetric):
				_add_god_ray_beam(_light_fixture_root, spot, 42.0, height_above)


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
	# Floating surface plants (frogbit / duckweed style). Small green disks
	# sitting at the water surface, drifting slowly. They cast subtle shade
	# but don't actively grow in this sim - just decorative.
	var container := Node3D.new()
	container.name = "Floaters"
	add_child(container)
	for i in 18:
		var disk := Node3D.new()
		container.add_child(disk)
		var f_xz: Vector2 = _random_xz_in_band(-TANK_HALF_D * 0.85, TANK_HALF_D * 0.85, 0.4)
		disk.position = Vector3(f_xz.x, WATER_HEIGHT - 0.05, f_xz.y)
		# Cluster of 3-5 small green voxels in a rough circle.
		var n_leaves: int = _rng.randi_range(3, 5)
		var leaf_color := Color8(70, 130, 60)
		var leaf_color_dark := Color8(50, 100, 45)
		for j in n_leaves:
			var ang: float = float(j) / float(n_leaves) * TAU
			var r: float = _rng.randf_range(0.15, 0.32)
			var mi := MeshInstance3D.new()
			mi.mesh = VoxelMat.get_box(Vector3(0.28, 0.08, 0.28))
			mi.position = Vector3(cos(ang) * r, 0, sin(ang) * r)
			mi.material_override = VoxelMat.make(leaf_color if (j & 1) == 0 else leaf_color_dark)
			disk.add_child(mi)
		# Small dangling root (one dark voxel under center).
		var root_mi := MeshInstance3D.new()
		root_mi.mesh = VoxelMat.get_box(Vector3(0.08, 0.4, 0.08))
		root_mi.position = Vector3(0, -0.2, 0)
		root_mi.material_override = VoxelMat.make(Color8(45, 70, 40))
		disk.add_child(root_mi)
		# Store a phase offset so each drifts independently.
		disk.set_meta("phase", randf() * TAU)
		_floaters.append(disk)


var _floaters: Array = []
var _floater_t: float = 0.0
var _duckweed_accum: float = 0.0
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
		p.init_at(Vector3(xz.x, SUBSTRATE_DEPTH + 0.1, xz.y), ramp_choice)
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
		p.init_at(Vector3(xz.x, SUBSTRATE_DEPTH + 0.05, xz.y),
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
		p.init_at(Vector3(xz.x, SUBSTRATE_DEPTH + y_jitter, xz.y), moss_ramp)
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


# Spawn a single duckweed clump at the given world-space position. Extracted
# from _spawn_floaters so the propagation tick can call it. Each clump is a
# Node3D with 3-5 leaf voxels + a tiny dangling root, registered into the
# _floaters array so it drifts + gets propagated like the originals.
func _add_floater_at(pos: Vector3) -> void:
	var container := get_node_or_null("Floaters")
	if container == null:
		return
	var disk := Node3D.new()
	container.add_child(disk)
	disk.position = pos
	var n_leaves: int = _rng.randi_range(3, 5)
	var leaf_color := Color8(70, 130, 60)
	var leaf_color_dark := Color8(50, 100, 45)
	for j in n_leaves:
		var ang: float = float(j) / float(n_leaves) * TAU
		var r: float = float(j) * 0.12
		var mi := MeshInstance3D.new()
		mi.mesh = VoxelMat.get_box(Vector3(0.35, 0.1, 0.35))
		mi.position = Vector3(cos(ang) * r, 0, sin(ang) * r)
		mi.material_override = VoxelMat.make(leaf_color if (j & 1) == 0 else leaf_color_dark)
		disk.add_child(mi)
	var root_mi := MeshInstance3D.new()
	root_mi.mesh = VoxelMat.get_box(Vector3(0.1, 0.6, 0.1))
	root_mi.position = Vector3(0, -0.3, 0)
	root_mi.material_override = VoxelMat.make(Color8(45, 70, 40))
	disk.add_child(root_mi)
	disk.set_meta("phase", randf() * TAU)
	_floaters.append(disk)


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
	tw.tween_method(func(c: Color):
			fade_mat.set_shader_parameter("albedo", c),
		Color8(225, 240, 245), faded, 0.75) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(ring.queue_free)


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
	# Mulm = soft dark detritus accumulating on top of the substrate. We just
	# scatter ~40 tiny dark voxels across the surface to suggest the layer.
	# Over time, WasteParticles that settle ADD to this visually (via
	# add_mulm_voxel) so the layer grows.
	var container := Node3D.new()
	container.name = "Mulm"
	add_child(container)
	for i in 40:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.18, 0.06, 0.18)
		mi.mesh = bm
		var m_xz: Vector2 = _random_xz_in_band(-TANK_HALF_D * 0.95, TANK_HALF_D * 0.95, 0.2)
		mi.position = Vector3(m_xz.x, SUBSTRATE_DEPTH + 0.04, m_xz.y)
		mi.material_override = VoxelMat.make(Color8(28, 22, 16))
		container.add_child(mi)
		_mulm_voxels.append(mi)


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


# Called by sim_driver when a waste particle settles. Adds another tiny
# voxel to the mulm layer at the same spot. Capped at ~150 voxels so the
# scene doesn't get out of hand.
func add_mulm_voxel(pos: Vector3) -> void:
	if _mulm_voxels.size() > 150:
		return
	var container := get_node_or_null("Mulm")
	if container == null:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.16, 0.05, 0.16)
	mi.mesh = bm
	mi.position = Vector3(pos.x, SUBSTRATE_DEPTH + 0.03, pos.z)
	mi.material_override = VoxelMat.make(Color8(28, 22, 16))
	container.add_child(mi)
	_mulm_voxels.append(mi)


# ---- Microfauna swarm ------------------------------------------------------
# Seeds the tank with N tiny drifting copepod / daphnia-like entities. Called
# once at end of _ready to fill the swarm immediately; _process then keeps
# it topped up via _maintain_microfauna() as individuals age out or get
# pulled into the filter intake.
func _spawn_initial_microfauna(count: int) -> void:
	for i in count:
		_spawn_one_microfauna()


func _spawn_one_microfauna() -> void:
	if microfauna_root == null or sim == null:
		return
	var b: AABB = sim.world_bounds
	# Reject samples outside the (possibly non-rectangular) tank shape, so
	# hex / triangle tanks don't get microfauna floating in the corner air.
	# Tries up to 6 times before giving up — at 90 microfauna a single
	# missed spawn isn't visible.
	for _attempt in 6:
		var x: float = randf_range(b.position.x, b.position.x + b.size.x)
		var z: float = randf_range(b.position.z, b.position.z + b.size.z)
		if not _is_inside_tank(x, z, 0.3):
			continue
		var y: float = randf_range(b.position.y, b.position.y + b.size.y)
		var m := Microfauna.new()
		microfauna_root.add_child(m)
		m.sim = sim
		m.position = Vector3(x, y, z)
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
	w.position = p


# Per-tick maintenance: refills both populations back to their targets. Cheap
# — counts a child list once per refill window, doesn't iterate per entity.
func _maintain_microfauna(sdt: float) -> void:
	_microfauna_refill_t = maxf(0.0, _microfauna_refill_t - sdt)
	if _microfauna_refill_t > 0.0:
		return
	_microfauna_refill_t = 0.8  # next refill in ~0.8 sim-seconds
	if microfauna_root == null:
		return
	var have: int = microfauna_root.get_child_count()
	# Spawn up to ~4 per window so the swarm refreshes gradually rather
	# than popping in a burst whenever a few age out simultaneously.
	var deficit: int = MICROFAUNA_TARGET - have
	var to_spawn: int = mini(deficit, 4)
	for i in to_spawn:
		_spawn_one_microfauna()


func _maintain_wriggle_worms(sdt: float) -> void:
	_wriggle_refill_t = maxf(0.0, _wriggle_refill_t - sdt)
	if _wriggle_refill_t > 0.0:
		return
	_wriggle_refill_t = 1.6
	if wriggle_root == null:
		return
	# Target count tracks mulm carpet density — a fresh tank with few
	# settled waste voxels has few worms; a mature tank with 150 mulm
	# voxels has the full carpet.
	var target: int = mini(WRIGGLE_MAX, int(_mulm_voxels.size() * WRIGGLE_PER_MULM_FRAC))
	var have: int = wriggle_root.get_child_count()
	var to_spawn: int = mini(target - have, 2)
	for i in to_spawn:
		_spawn_one_wriggle()


# Public entry point for the retro fish store. Picks a sensible spawn
# position near the top-center (so the new arrival drops in visibly), then
# delegates to the private spawn helper. The fish_store.gd panel calls
# this; nothing else does.
func spawn_purchased_fish(genome: Dictionary) -> void:
	var pref_y: float = float(genome.get("preferred_y", 3.8))
	var spawn_y: float = clampf(pref_y + 0.4, SUBSTRATE_DEPTH + 0.5, WATER_HEIGHT - 0.4)
	var xz: Vector2 = _random_xz_in_band(-TANK_HALF_D * 0.6, TANK_HALF_D * 0.6, 0.8)
	_spawn_fish_at(genome, Vector3(xz.x, spawn_y, xz.y))


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
	f.global_position = pos
	f.init_genome(genome)
	sim.register_fish(f)


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
	# Roughly 2/3 reds + 1/3 ambers. Start as adults so breeding kicks in soon.
	var red_n: int = int(shrimp_n * 2.0 / 3.0)
	for i in shrimp_n:
		var g: Dictionary = red_genome.duplicate() if i < red_n else amber_genome.duplicate()
		g["sex"] = i % 2
		g["max_age_s"] += randf_range(-30, 30)
		var sh := Shrimp.new()
		# Spread initial ages so we don't get a synchronised die-off.
		sh.age = g["max_age_s"] * randf_range(0.15, 0.6)
		fauna_root.add_child(sh)
		var sh_xz: Vector2 = _random_xz_in_band(-TANK_HALF_D * 0.7, TANK_HALF_D * 0.7, 0.4)
		sh.global_position = Vector3(sh_xz.x, SUBSTRATE_DEPTH + 0.15, sh_xz.y)
		sh.init_genome(g)
		sim.register_shrimp(sh)
		# Yield every 4 shrimp - each builds ~15 voxels + an egg cluster.
		if (i + 1) % 4 == 0:
			await get_tree().process_frame


func _spawn_marine_shrimp() -> void:
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
	}
	var n: int = 6                                  # small cleaning crew
	for i in n:
		var g: Dictionary = cleaner_genome.duplicate()
		g["sex"] = i % 2
		g["max_age_s"] += randf_range(-30, 30)
		var sh := Shrimp.new()
		sh.age = g["max_age_s"] * randf_range(0.15, 0.6)
		fauna_root.add_child(sh)
		var sh_xz: Vector2 = _random_xz_in_band(
			-TANK_HALF_D * 0.7, TANK_HALF_D * 0.7, 0.4)
		sh.global_position = Vector3(sh_xz.x, SUBSTRATE_DEPTH + 0.15, sh_xz.y)
		sh.init_genome(g)
		sim.register_shrimp(sh)
		if (i + 1) % 3 == 0:
			await get_tree().process_frame


func _seed_nutrient_hotspots() -> void:
	# Push extra nutrients into a few cells so plants near them get a visible
	# head start. Without this, all plants would grow uniformly which is boring.
	for i in 5:
		var hs_xz: Vector2 = _random_xz_in_band(-TANK_HALF_D * 0.8, TANK_HALF_D * 0.8, 0.4)
		substrate_grid.add_at(Vector3(hs_xz.x, SUBSTRATE_DEPTH, hs_xz.y), 1.5)
