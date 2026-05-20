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
	_rng.seed = 0xCAFEF155
	# Sim driver first so other builders can register into it.
	sim = SimDriver.new()
	sim.name = "SimDriver"
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
	sim.plants_root = plants_root
	sim.fauna_root = fauna_root
	sim.waste_root = waste_root

	_build_substrate()
	_build_hardscape()
	_build_water_volume()
	_build_glass()
	_build_snails()  # static decor

	_spawn_initial_plants()
	_spawn_initial_fish()
	_spawn_initial_shrimp()
	# Make sure SimDriver can find the snails container for predator AI.
	sim.snails_root = get_node_or_null("Snails")
	# Seed the substrate with some uneven nutrients so plants in nutrient-rich
	# spots immediately start to outpace the others - visible variance.
	_seed_nutrient_hotspots()

	print("[vivarium] world built: ", get_child_count(), " top-level nodes; ",
		  sim.fish.size(), " fish, ", sim.shrimp.size(), " shrimp, ",
		  sim.plants.size(), " plants")


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
	water.material_override = _water_mat()
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
	# Snails get a small CrawlingSnail script that slides them slowly along
	# their wall over time, so the glass-cling life feels alive.
	var positions_and_walls := [
		# pos, wall_normal (which face of the tank they're on)
		[Vector3(-7.95, 3.2, 0.0), Vector3(-1, 0, 0)],
		[Vector3(-7.95, 4.8, -1.5), Vector3(-1, 0, 0)],
		[Vector3(7.95, 2.5, 1.0), Vector3(1, 0, 0)],
		[Vector3(7.95, 4.5, -1.0), Vector3(1, 0, 0)],
		[Vector3(0.0, 2.5, 3.95), Vector3(0, 0, 1)],
		[Vector3(-2.0, 3.8, -3.95), Vector3(0, 0, -1)],
	]
	for pw in positions_and_walls:
		var pos: Vector3 = pw[0]
		var wall_n: Vector3 = pw[1]
		var snail := Node3D.new()
		snail.set_script(load("res://scripts/snail.gd"))
		snail.position = pos
		snail.set("wall_normal", wall_n)
		snail.set("wall_min", Vector3(-TANK_HALF_W + 0.4, SUBSTRATE_DEPTH + 0.4, -TANK_HALF_D + 0.4))
		snail.set("wall_max", Vector3(TANK_HALF_W - 0.4, WATER_HEIGHT - 0.2, TANK_HALF_D - 0.4))
		c.add_child(snail)
		_build_snail_body(snail)


func _build_snail_body(snail: Node3D) -> void:
	var shell_mat := _solid_mat(C_SNAIL_SHELL)
	var shell_dark := _solid_mat(C_SNAIL_SHELL.darkened(0.2))
	var body_mat := _solid_mat(C_SNAIL_BODY)
	# Shell spiral.
	for i in 4:
		var ang: float = i * 0.7
		var r: float = 0.05 + i * 0.06
		var sp := Vector3(cos(ang) * r, sin(ang) * r, 0.0)
		var s: float = 0.16 - i * 0.02
		var mat: Material = shell_mat if (i & 1) == 0 else shell_dark
		_add_cube(snail, sp, Vector3(s, s, s), mat)
	# Foot.
	_add_cube(snail, Vector3(0, -0.12, 0), Vector3(0.24, 0.06, 0.16), body_mat)
	# Tiny eye stalks.
	_add_cube(snail, Vector3(0.10, -0.06, 0.06), Vector3(0.03, 0.10, 0.03), body_mat)
	_add_cube(snail, Vector3(0.10, -0.06, -0.06), Vector3(0.03, 0.10, 0.03), body_mat)


# ---- Initial population ----

func _spawn_initial_plants() -> void:
	# Heavy-planted Walstad-style tank: dense background + midground + carpet.
	# Three plant "flavors":
	#   - Tall back: Vallisneria-style blades, max ~22, slow grow, big sway
	#   - Mid-ground rosette: max ~10, moderate grow
	#   - Foreground carpet: max ~5, fast grow
	# Plus moss on driftwood: small dense clumps on the hardscape.

	# Background blades along the back wall.
	for x_frac in [-0.85, -0.65, -0.45, -0.15, 0.15, 0.45, 0.65, 0.85]:
		var cx: float = x_frac * TANK_HALF_W
		var cz: float = _rng.randf_range(-TANK_HALF_D * 0.95, -TANK_HALF_D * 0.55)
		var n_blades: int = _rng.randi_range(4, 7)
		for i in n_blades:
			var p := Plant.new()
			plants_root.add_child(p)
			p.global_position = Vector3(
				cx + _rng.randf_range(-0.5, 0.5),
				SUBSTRATE_DEPTH,
				cz + _rng.randf_range(-0.4, 0.4)
			)
			p.init(_rng.randi_range(2, 5), {
				"max_height": _rng.randi_range(16, 24),
				"growth_rate": 0.16,
				"sway_amplitude": 0.20,
			})
			sim.register_plant(p)

	# Midground rosettes - shorter, scattered across the middle z band.
	for i in 12:
		var p := Plant.new()
		plants_root.add_child(p)
		p.global_position = Vector3(
			_rng.randf_range(-TANK_HALF_W * 0.85, TANK_HALF_W * 0.85),
			SUBSTRATE_DEPTH,
			_rng.randf_range(-0.5, 1.5),
		)
		p.init(_rng.randi_range(2, 4), {
			"max_height": _rng.randi_range(8, 12),
			"growth_rate": 0.20,
			"sway_amplitude": 0.10,
		})
		sim.register_plant(p)

	# Foreground carpet - many low spreading plants at the front of the tank.
	for i in 24:
		var p := Plant.new()
		plants_root.add_child(p)
		p.global_position = Vector3(
			_rng.randf_range(-TANK_HALF_W * 0.9, TANK_HALF_W * 0.9),
			SUBSTRATE_DEPTH,
			_rng.randf_range(TANK_HALF_D * 0.3, TANK_HALF_D * 0.9),
		)
		p.init(_rng.randi_range(1, 3), {
			"max_height": _rng.randi_range(3, 6),
			"growth_rate": 0.28,
			"sway_amplitude": 0.04,
		})
		sim.register_plant(p)

	# Moss clumps along the driftwood arch (rough x positions matching hardscape).
	for x in [-5.0, -3.0, -1.0, 1.0, 2.8]:
		for off in [Vector3(0, 0.4, 0.2), Vector3(0.2, 0.5, -0.1)]:
			var p := Plant.new()
			plants_root.add_child(p)
			# Roughly match driftwood arc height.
			var arc_y: float = 2.0 + cos(x * 0.4) * 0.6
			p.global_position = Vector3(x + off.x, arc_y, off.z)
			p.init(_rng.randi_range(1, 2), {
				"max_height": _rng.randi_range(2, 4),
				"growth_rate": 0.10,
				"sway_amplitude": 0.02,
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
	for i in 8:
		var g: Dictionary = glassdart_genome.duplicate()
		g["sex"] = i % 2
		g["max_age_s"] += randf_range(-30, 30)
		_spawn_fish_at(g, Vector3(
			randf_range(-5, 5), randf_range(3.0, 4.5), randf_range(-2, 2)
		))
	for i in 3:
		var g: Dictionary = mudsifter_genome.duplicate()
		g["sex"] = i % 2
		_spawn_fish_at(g, Vector3(
			randf_range(-4, 4), randf_range(2.0, 2.8), randf_range(-2, 2)
		))


func _spawn_fish_at(genome: Dictionary, pos: Vector3) -> void:
	var f := Fish.new()
	# Start as an adult so we see breeding sooner; fry would take ages to mature.
	f.age = (genome.get("max_age_s", 240.0)) * 0.35
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
	# 5 reds + 3 ambers, start as adults so breeding kicks in soon.
	for i in 8:
		var g: Dictionary = red_genome.duplicate() if i < 5 else amber_genome.duplicate()
		g["sex"] = i % 2
		g["max_age_s"] += randf_range(-30, 30)
		var sh := Shrimp.new()
		sh.age = g["max_age_s"] * 0.35
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
