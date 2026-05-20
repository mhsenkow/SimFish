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
# Mulm voxels (small dark blocks accumulating on top of the substrate from
# settled waste). We keep a flat array so we can stir them when something
# disturbs the layer.
var _mulm_voxels: Array = []
var algae_root: Node3D = null

const TANK_HALF_W: float = 8.0
const TANK_HALF_D: float = 4.0
const TANK_HEIGHT: float = 7.0
const WATER_HEIGHT: float = 6.5
const SUBSTRATE_DEPTH: float = 1.6

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
	sim.plants_root = plants_root
	sim.fauna_root = fauna_root
	sim.waste_root = waste_root
	sim.algae_root = algae_root

	_build_substrate()
	_build_hardscape()
	_build_water_volume()
	_build_glass()
	_build_snails()  # static decor

	_spawn_initial_plants()
	_spawn_floaters()
	_spawn_initial_fish()
	_spawn_initial_shrimp()
	_spawn_bubble_streams()
	_spawn_mulm_layer()
	_spawn_surface_ripples()
	# Make sure SimDriver can find the snails container for predator AI.
	sim.snails_root = get_node_or_null("Snails")
	# Seed the substrate with some uneven nutrients so plants in nutrient-rich
	# spots immediately start to outpace the others - visible variance.
	_seed_nutrient_hotspots()

	# Find the directional light so we can dim it on the day/night cycle.
	# The light is a sibling under SubViewport/World, accessible by name.
	_directional_light = get_parent().get_node_or_null("DirectionalLight3D")

	print("[vivarium] world built: ", get_child_count(), " top-level nodes; ",
		  sim.fish.size(), " fish, ", sim.shrimp.size(), " shrimp, ",
		  sim.plants.size(), " plants")


var _directional_light: DirectionalLight3D = null


func _process(dt: float) -> void:
	var sdt: float = dt
	if sim != null:
		sdt = dt * float(sim.time_scale)
	# Tannins: slow rise toward a cap (driftwood + leaves leak organics into
	# the water column). Visible as a warm brown tint that deepens over time.
	if tannins < 0.35:
		tannins = minf(0.35, tannins + 0.00005 * sdt)
	if _water_material_ref != null:
		var tannin_color := Color(0.83, 0.55, 0.25)
		var base_water := Color(C_WATER_SHALLOW.r, C_WATER_SHALLOW.g, C_WATER_SHALLOW.b)
		var tinted: Color = base_water.lerp(tannin_color, tannins * 0.55)
		tinted.a = 0.10 + tannins * 0.10
		_water_material_ref.albedo_color = tinted

	# Day/night light cycle: directional energy + ambient mod.
	if _directional_light != null and sim != null:
		var dl: float = sim.daylight()
		_directional_light.light_energy = 0.05 + dl * 0.45
		_directional_light.light_color = Color(0.55, 0.65, 0.95).lerp(
			Color(1.0, 0.95, 0.80), dl)

	# Floater drift: each surface plant wanders gently on a sin curve.
	_floater_t += sdt
	for f in _floaters:
		var fn: Node3D = f
		var ph: float = fn.get_meta("phase", 0.0)
		fn.position.x += sin(_floater_t * 0.15 + ph) * 0.05 * sdt
		fn.position.z += cos(_floater_t * 0.12 + ph * 1.3) * 0.05 * sdt
		# Slight bob.
		fn.position.y = WATER_HEIGHT - 0.05 + sin(_floater_t * 0.7 + ph) * 0.015
		# Soft clamp inside the tank.
		fn.position.x = clampf(fn.position.x, -TANK_HALF_W * 0.9, TANK_HALF_W * 0.9)
		fn.position.z = clampf(fn.position.z, -TANK_HALF_D * 0.9, TANK_HALF_D * 0.9)


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
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _build_substrate() -> void:
	var container := Node3D.new()
	container.name = "Substrate"
	add_child(container)

	var voxel_size := 0.4
	var rows: int = int(SUBSTRATE_DEPTH / voxel_size)
	var cols: int = int((TANK_HALF_W * 2.0) / voxel_size)
	var depths: int = int((TANK_HALF_D * 2.0) / voxel_size)

	var soil_rows: int = int(rows * 0.7)
	for r in rows:
		for c in cols:
			for d in depths:
				var x: float = -TANK_HALF_W + (c + 0.5) * voxel_size
				var z: float = -TANK_HALF_D + (d + 0.5) * voxel_size
				var y: float = (r + 0.5) * voxel_size
				if r == rows - 1 and _rng.randf() < 0.15:
					continue
				var color: Color
				if r < rows - soil_rows:
					color = C_GRAVEL.lerp(C_SOIL_RAMP[0], _rng.randf() * 0.4)
				else:
					var rel: float = float(r - (rows - soil_rows)) / float(maxi(1, soil_rows))
					var idx: int = clampi(int(rel * 5.0 + _rng.randf() * 1.5), 0, 5)
					color = C_SOIL_RAMP[idx]
				_add_cube(container, Vector3(x, y, z), Vector3(voxel_size, voxel_size, voxel_size),
						  _solid_mat(color))


func _build_hardscape() -> void:
	var c := Node3D.new()
	c.name = "Hardscape"
	add_child(c)

	var points := [
		Vector3(-6.5, 1.3, -1.0),
		Vector3(-5.0, 2.0, -0.5),
		Vector3(-3.0, 2.6, 0.0),
		Vector3(-1.0, 3.0, 0.3),
		Vector3(1.0, 2.8, 0.0),
		Vector3(2.8, 2.2, -0.4),
		Vector3(4.0, 1.6, -0.6),
	]
	var mat_dark := _solid_mat(C_DRIFTWOOD_DARK)
	var mat_light := _solid_mat(C_DRIFTWOOD_LIGHT)
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var steps: int = int(a.distance_to(b) / 0.35) + 1
		for s in steps:
			var t: float = float(s) / float(steps)
			var p: Vector3 = a.lerp(b, t)
			var size: float = 0.55
			_add_cube(c, p, Vector3(size, size, size), mat_dark)
			for dx in [-1, 1]:
				_add_cube(c, p + Vector3(0, size * 0.5, dx * size * 0.4),
						  Vector3(size * 0.6, size * 0.6, size * 0.6), mat_light)

	var stone_mat := _solid_mat(C_STONE_LIGHT)
	var stone_dark := _solid_mat(C_STONE_DARK)
	var stone_positions := [Vector3(5.5, 1.0, 1.5), Vector3(-7.0, 0.9, 1.5)]
	for sp in stone_positions:
		for i in 4:
			var jitter := Vector3(_rng.randf_range(-0.4, 0.4),
								  _rng.randf_range(0, 0.6),
								  _rng.randf_range(-0.4, 0.4))
			var size := _rng.randf_range(0.7, 1.1)
			var m: Material = stone_mat if (i & 1) == 0 else stone_dark
			var mi := _add_cube(c, sp + jitter, Vector3(size, size, size), m)
			mi.rotation = Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(0, PI),
								  _rng.randf_range(-0.3, 0.3))


func _build_water_volume() -> void:
	var water := MeshInstance3D.new()
	water.name = "Water"
	var bm := BoxMesh.new()
	bm.size = Vector3(TANK_HALF_W * 2.0 - 0.2, WATER_HEIGHT - SUBSTRATE_DEPTH,
					  TANK_HALF_D * 2.0 - 0.2)
	water.mesh = bm
	water.position = Vector3(0, SUBSTRATE_DEPTH + (WATER_HEIGHT - SUBSTRATE_DEPTH) * 0.5, 0)
	_water_material_ref = _water_mat()
	water.material_override = _water_material_ref
	_water_mesh = water
	add_child(water)


func _build_glass() -> void:
	var c := Node3D.new()
	c.name = "Glass"
	add_child(c)
	var glass := _glass_mat()
	var thick := 0.1
	var sides := [
		[Vector3(0, TANK_HEIGHT * 0.5, TANK_HALF_D + thick * 0.5),
		 Vector3(TANK_HALF_W * 2, TANK_HEIGHT, thick)],
		[Vector3(0, TANK_HEIGHT * 0.5, -TANK_HALF_D - thick * 0.5),
		 Vector3(TANK_HALF_W * 2, TANK_HEIGHT, thick)],
		[Vector3(TANK_HALF_W + thick * 0.5, TANK_HEIGHT * 0.5, 0),
		 Vector3(thick, TANK_HEIGHT, TANK_HALF_D * 2)],
		[Vector3(-TANK_HALF_W - thick * 0.5, TANK_HEIGHT * 0.5, 0),
		 Vector3(thick, TANK_HEIGHT, TANK_HALF_D * 2)],
	]
	for s in sides:
		_add_cube(c, s[0], s[1], glass)


func _build_snails() -> void:
	var c := Node3D.new()
	c.name = "Snails"
	add_child(c)
	# Founders get varied starting colors so the colony has visible diversity
	# from frame zero. Mutation drift will further spread these over generations.
	var founder_palette: Array[Color] = [
		Color8(135, 44, 176),   # classic purple
		Color8(180, 70, 90),    # warm rose
		Color8(80, 100, 180),   # cool blue
		Color8(160, 130, 60),   # amber
		Color8(70, 140, 110),   # teal
		Color8(190, 160, 60),   # ochre
	]
	var positions_and_walls := [
		[Vector3(-7.95, 3.2, 0.0), Vector3(-1, 0, 0)],
		[Vector3(-7.95, 4.8, -1.5), Vector3(-1, 0, 0)],
		[Vector3(7.95, 2.5, 1.0), Vector3(1, 0, 0)],
		[Vector3(7.95, 4.5, -1.0), Vector3(1, 0, 0)],
		[Vector3(0.0, 2.5, 3.95), Vector3(0, 0, 1)],
		[Vector3(-2.0, 3.8, -3.95), Vector3(0, 0, -1)],
	]
	for i in positions_and_walls.size():
		var pw = positions_and_walls[i]
		var pos: Vector3 = pw[0]
		var wall_n: Vector3 = pw[1]
		var snail := Node3D.new()
		snail.set_script(load("res://scripts/snail.gd"))
		snail.position = pos
		snail.set("wall_normal", wall_n)
		snail.set("wall_min", Vector3(-TANK_HALF_W + 0.4, SUBSTRATE_DEPTH + 0.4, -TANK_HALF_D + 0.4))
		snail.set("wall_max", Vector3(TANK_HALF_W - 0.4, WATER_HEIGHT - 0.2, TANK_HALF_D - 0.4))
		snail.set("shell_color", founder_palette[i % founder_palette.size()])
		snail.set("shell_size", _rng.randf_range(0.85, 1.15))
		snail.set("generation", 0)
		c.add_child(snail)
		_build_snail_body(snail)


func _build_snail_body(snail: Node3D) -> void:
	# Read the snail's heritable shell_color + shell_size (set above) and
	# build the body voxels with those traits.
	var shell_color: Color = snail.get("shell_color")
	var shell_size: float = snail.get("shell_size")
	var shell_dark: Color = shell_color.darkened(0.22)
	var body_color: Color = C_SNAIL_BODY
	var shell_mat := _solid_mat(shell_color)
	var shell_dark_mat := _solid_mat(shell_dark)
	var body_mat := _solid_mat(body_color)
	for i in 4:
		var ang: float = i * 0.7
		var r: float = (0.05 + i * 0.06) * shell_size
		var sp := Vector3(cos(ang) * r, sin(ang) * r, 0.0)
		var s: float = (0.16 - i * 0.02) * shell_size
		var mat: Material = shell_mat if (i & 1) == 0 else shell_dark_mat
		_add_cube(snail, sp, Vector3(s, s, s), mat)
	# Foot scales with shell.
	_add_cube(snail, Vector3(0, -0.12 * shell_size, 0),
		Vector3(0.24 * shell_size, 0.06 * shell_size, 0.16 * shell_size), body_mat)
	# Eye stalks - keep them at a fixed small size for visibility.
	_add_cube(snail, Vector3(0.10, -0.06 * shell_size, 0.06),
		Vector3(0.03, 0.10 * shell_size, 0.03), body_mat)
	_add_cube(snail, Vector3(0.10, -0.06 * shell_size, -0.06),
		Vector3(0.03, 0.10 * shell_size, 0.03), body_mat)


# ---- Initial population ----

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
		 "ramp": [Color8(16, 38, 20), Color8(29, 59, 34), Color8(44, 90, 48),
				  Color8(62, 127, 64), Color8(87, 162, 83), Color8(121, 192, 105)]},
		{"name": "crypt",    "max": [9, 14],  "rate": 0.20, "sway": 0.10,
		 "ramp": [Color8(34, 60, 28), Color8(54, 88, 38), Color8(78, 119, 53),
				  Color8(110, 152, 73), Color8(140, 178, 95), Color8(170, 200, 120)]},
		{"name": "carpet",   "max": [3, 6],   "rate": 0.30, "sway": 0.04,
		 "ramp": [Color8(40, 90, 35), Color8(60, 122, 52), Color8(82, 152, 70),
				  Color8(110, 180, 92), Color8(145, 205, 118), Color8(180, 225, 145)]},
		{"name": "red_stem", "max": [11, 18], "rate": 0.18, "sway": 0.16,
		 "ramp": [Color8(78, 32, 30), Color8(115, 50, 40), Color8(155, 70, 52),
				  Color8(180, 95, 72), Color8(200, 125, 90), Color8(215, 160, 120)]},
		{"name": "moss",     "max": [2, 4],   "rate": 0.10, "sway": 0.02,
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
			_spawn_plant(species_specs[0], Vector3(
				cx + _rng.randf_range(-0.5, 0.5),
				SUBSTRATE_DEPTH,
				cz + _rng.randf_range(-0.5, 0.5)
			), _rng.randi_range(2, 5))

	# --- Midground rosettes (crypts) + red accent stems scattered ---
	for i in 28:
		_spawn_plant(species_specs[1], Vector3(
			_rng.randf_range(-TANK_HALF_W * 0.9, TANK_HALF_W * 0.9),
			SUBSTRATE_DEPTH,
			_rng.randf_range(-0.5, 1.5)
		), _rng.randi_range(2, 4))
	for i in 14:
		_spawn_plant(species_specs[3], Vector3(
			_rng.randf_range(-TANK_HALF_W * 0.85, TANK_HALF_W * 0.85),
			SUBSTRATE_DEPTH,
			_rng.randf_range(-1.5, 1.5)
		), _rng.randi_range(2, 4))

	# --- Foreground carpet: very dense ---
	for i in 55:
		_spawn_plant(species_specs[2], Vector3(
			_rng.randf_range(-TANK_HALF_W * 0.95, TANK_HALF_W * 0.95),
			SUBSTRATE_DEPTH,
			_rng.randf_range(TANK_HALF_D * 0.2, TANK_HALF_D * 0.95)
		), _rng.randi_range(1, 3))

	# --- Moss on the driftwood arch (epiphytes) ---
	for x in [-5.5, -4.0, -2.5, -1.0, 0.5, 1.8, 3.2, 4.5]:
		for off in [Vector3(0, 0.4, 0.2), Vector3(0.2, 0.5, -0.1), Vector3(-0.15, 0.45, 0.3)]:
			var arc_y: float = 2.0 + cos(x * 0.4) * 0.6
			_spawn_plant(species_specs[4], Vector3(x + off.x, arc_y, off.z),
				_rng.randi_range(1, 2))


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
	})
	sim.register_plant(p)


# Called by Plant.gd when an emergent (above-water) plant casts a seed.
# Spawns a tiny new plant nearby with the parent's mutated ramp + same
# rough max_height target. Capped via plants_alive size so we don't grow
# the field infinitely.
func spawn_seedling(pos: Vector3, ramp: Array, generation: int, parent_max: int) -> void:
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
	var p := Plant.new()
	plants_root.add_child(p)
	p.global_position = sp
	if ramp.size() == 6:
		p.ramp_override = ramp
	p.water_surface_y = WATER_HEIGHT
	p.generation = generation
	# Inherit a small range around the parent's max so the lineage diverges.
	p.init(1, {
		"max_height": clampi(parent_max + _rng.randi_range(-2, 2), 4, 26),
		"growth_rate": 0.16,
		"sway_amplitude": 0.18,
	})
	sim.register_plant(p)


func _spawn_initial_fish() -> void:
	# Two species. Glassdarts (mid-water schoolers, mild herbivory). Mudsifters
	# (bottom-loving, stronger herbivory, fewer of them).
	var glassdart_genome: Dictionary = {
		"species": "glassdart",
		"base_color": Color8(195, 59, 59),
		"accent_color": Color8(230, 201, 42),
		"adult_voxel_scale": 0.18,
		"max_age_s": 220.0,
		"max_speed": 2.0,
		"schooling_strength": 1.4,
		"separation_radius": 0.6,
		"herbivory": 0.4,
		"fecundity": 0.8,
		"clutch_size": 2,
		"preferred_y": 4.0,
	}
	var mudsifter_genome: Dictionary = {
		"species": "mudsifter",
		"base_color": Color8(120, 85, 56),
		"accent_color": Color8(205, 176, 136),
		"adult_voxel_scale": 0.22,
		"max_age_s": 280.0,
		"max_speed": 1.2,
		"schooling_strength": 0.5,
		"separation_radius": 0.7,
		"herbivory": 1.0,
		"fecundity": 0.5,
		"clutch_size": 3,
		"preferred_y": 2.4,
	}
	# Larger founding cohort so the "valley" between founders dying and
	# first-generation maturing doesn't drop the whole population to 0.
	for i in 14:
		var g: Dictionary = glassdart_genome.duplicate()
		g["sex"] = i % 2
		g["max_age_s"] += randf_range(-30, 30)
		_spawn_fish_at(g, Vector3(
			randf_range(-5, 5), randf_range(3.0, 4.5), randf_range(-2, 2)
		))
	for i in 5:
		var g: Dictionary = mudsifter_genome.duplicate()
		g["sex"] = i % 2
		_spawn_fish_at(g, Vector3(
			randf_range(-4, 4), randf_range(2.0, 2.8), randf_range(-2, 2)
		))

	# One solo apex: betta-like - bigger, brighter, more territorial. Hunts
	# baby shrimp + fry more often (high herbivory_priority via aggression).
	var betta_genome: Dictionary = {
		"species": "betta",
		"base_color": Color8(80, 50, 170),       # iridescent purple-blue
		"accent_color": Color8(230, 130, 200),
		"adult_voxel_scale": 0.28,                # noticeably larger
		"max_age_s": 420.0,
		"max_speed": 1.6,
		"schooling_strength": 0.0,                # loner
		"separation_radius": 1.0,
		"herbivory": 0.0,                         # carnivore
		"fecundity": 0.0,                         # no breeding here (solo)
		"clutch_size": 0,
		"preferred_y": 3.8,
	}
	betta_genome["sex"] = randi() % 2
	_spawn_fish_at(betta_genome, Vector3(0, 4.0, 0))


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
		disk.position = Vector3(
			_rng.randf_range(-TANK_HALF_W * 0.85, TANK_HALF_W * 0.85),
			WATER_HEIGHT - 0.05,
			_rng.randf_range(-TANK_HALF_D * 0.85, TANK_HALF_D * 0.85),
		)
		# Cluster of 3-5 small green voxels in a rough circle.
		var n_leaves: int = _rng.randi_range(3, 5)
		var leaf_color := Color8(70, 130, 60)
		var leaf_color_dark := Color8(50, 100, 45)
		for j in n_leaves:
			var ang: float = float(j) / float(n_leaves) * TAU
			var r: float = _rng.randf_range(0.15, 0.32)
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.28, 0.08, 0.28)
			mi.mesh = bm
			mi.position = Vector3(cos(ang) * r, 0, sin(ang) * r)
			mi.material_override = VoxelMat.make(leaf_color if (j & 1) == 0 else leaf_color_dark)
			disk.add_child(mi)
		# Small dangling root (one dark voxel under center).
		var root_mi := MeshInstance3D.new()
		var root_bm := BoxMesh.new()
		root_bm.size = Vector3(0.06, 0.3, 0.06)
		root_mi.mesh = root_bm
		root_mi.position = Vector3(0, -0.2, 0)
		root_mi.material_override = VoxelMat.make(Color8(45, 70, 40))
		disk.add_child(root_mi)
		# Store a phase offset so each drifts independently.
		disk.set_meta("phase", randf() * TAU)
		_floaters.append(disk)


var _floaters: Array = []
var _floater_t: float = 0.0


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


func _spawn_bubble_streams() -> void:
	# 3-4 randomly placed anaerobic-pocket bubble streams. Each is a
	# GPUParticles3D that drifts bubbles up to the surface. They run slowly
	# and add ambient life to the tank.
	var n_streams: int = _rng.randi_range(3, 5)
	var container := Node3D.new()
	container.name = "BubbleStreams"
	add_child(container)
	for i in n_streams:
		var p := GPUParticles3D.new()
		p.amount = 6
		p.lifetime = 5.0
		p.preprocess = 2.0
		p.local_coords = false
		p.position = Vector3(
			_rng.randf_range(-TANK_HALF_W * 0.85, TANK_HALF_W * 0.85),
			SUBSTRATE_DEPTH + 0.1,
			_rng.randf_range(-TANK_HALF_D * 0.85, TANK_HALF_D * 0.85),
		)
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 1, 0)
		pm.initial_velocity_min = 0.4
		pm.initial_velocity_max = 0.7
		pm.gravity = Vector3(0, 0.9, 0)
		pm.spread = 5.0
		pm.scale_min = 0.7
		pm.scale_max = 1.3
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(0.1, 0.02, 0.1)
		p.process_material = pm
		var bm := SphereMesh.new()
		bm.radius = 0.08
		bm.height = 0.16
		bm.radial_segments = 5
		bm.rings = 3
		bm.material = VoxelMat.make(Color8(200, 230, 235))
		p.draw_pass_1 = bm
		container.add_child(p)


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
		mi.position = Vector3(
			_rng.randf_range(-TANK_HALF_W * 0.95, TANK_HALF_W * 0.95),
			SUBSTRATE_DEPTH + 0.04,
			_rng.randf_range(-TANK_HALF_D * 0.95, TANK_HALF_D * 0.95),
		)
		mi.material_override = VoxelMat.make(Color8(28, 22, 16))
		container.add_child(mi)
		_mulm_voxels.append(mi)


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
	fauna_root.add_child(f)
	f.global_position = pos
	f.init_genome(genome)
	sim.register_fish(f)


func _spawn_initial_shrimp() -> void:
	# Neocaridina-style shrimp. Two color morphs for visual interest.
	var red_genome: Dictionary = {
		"species": "shrimp",
		"base_color": Color8(195, 65, 55),    # cherry red
		"accent_color": Color8(245, 220, 200),
		"adult_voxel_scale": 0.11,
		"max_age_s": 360.0,
		"max_speed": 0.85,
		"substrate_top_y": SUBSTRATE_DEPTH,
	}
	var amber_genome: Dictionary = {
		"species": "shrimp",
		"base_color": Color8(195, 145, 70),   # amber/honey
		"accent_color": Color8(245, 220, 200),
		"adult_voxel_scale": 0.11,
		"max_age_s": 360.0,
		"max_speed": 0.85,
		"substrate_top_y": SUBSTRATE_DEPTH,
	}
	# 8 reds + 4 ambers, start as adults so breeding kicks in soon.
	for i in 12:
		var g: Dictionary = red_genome.duplicate() if i < 8 else amber_genome.duplicate()
		g["sex"] = i % 2
		g["max_age_s"] += randf_range(-30, 30)
		var sh := Shrimp.new()
		# Spread initial ages so we don't get a synchronised die-off.
		sh.age = g["max_age_s"] * randf_range(0.15, 0.6)
		fauna_root.add_child(sh)
		sh.global_position = Vector3(
			randf_range(-TANK_HALF_W * 0.8, TANK_HALF_W * 0.8),
			SUBSTRATE_DEPTH + 0.15,
			randf_range(-TANK_HALF_D * 0.7, TANK_HALF_D * 0.7),
		)
		sh.init_genome(g)
		sim.register_shrimp(sh)


func _seed_nutrient_hotspots() -> void:
	# Push extra nutrients into a few cells so plants near them get a visible
	# head start. Without this, all plants would grow uniformly which is boring.
	for i in 5:
		var x: float = _rng.randf_range(-TANK_HALF_W * 0.8, TANK_HALF_W * 0.8)
		var z: float = _rng.randf_range(-TANK_HALF_D * 0.8, TANK_HALF_D * 0.8)
		substrate_grid.add_at(Vector3(x, SUBSTRATE_DEPTH, z), 1.5)
