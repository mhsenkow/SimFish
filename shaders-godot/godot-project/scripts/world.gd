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
var _mulm_voxels: Array = []
var algae_root: Node3D = null

# Tank dimensions read from TankConfig at _ready so the user can resize.
# Treated as plain vars (was const) so settings can change them.
var TANK_HALF_W: float = 8.0
var TANK_HALF_D: float = 4.0
var TANK_HEIGHT: float = 7.0
var WATER_HEIGHT: float = 6.5
var SUBSTRATE_DEPTH: float = 1.6
# Substrate color ramp (overridden by TankConfig substrate profile).
var ACTIVE_SOIL_RAMP: Array = []
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
		var profile: Dictionary = cfg.current_substrate_profile()
		ACTIVE_SOIL_RAMP = profile.get("colors", C_SOIL_RAMP)
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
	# Apply substrate fertility from the active profile.
	var cfg2 := get_node_or_null("/root/TankConfig")
	if cfg2 != null:
		var profile: Dictionary = cfg2.current_substrate_profile()
		substrate_grid.baseline_override = float(profile.get("nutrient_baseline", 0.30))
		substrate_grid.reservoir_leak_override = float(profile.get("reservoir_leak", 0.00015))
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

	_build_light_fixture()
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

	# Toggle volumetric beams based on TankConfig.light_volumetric.
	var we := get_parent().get_node_or_null("WorldEnvironment")
	if we != null and we.environment != null and cfg != null:
		we.environment.volumetric_fog_enabled = bool(cfg.light_volumetric)

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

	# Day/night light cycle. The DirectionalLight gives soft ambient room
	# light; the SpotLight3Ds in the fixture give the focused aquarium beam.
	# Both are dimmed by the day/night cycle.
	if sim != null:
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


# Public so main.gd / aquascape mode can clamp clicks to the tank footprint.
func is_inside_tank(x: float, z: float, margin: float = 0.0) -> bool:
	return _is_inside_tank(x, z, margin)


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
	# Water volume box that fits inside the tank's bounding rect. For
	# hex/triangle shapes the glass walls clip the visible water at the
	# diagonals so we don't need a perfectly-shaped water mesh.
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
	var bm := BoxMesh.new()
	bm.size = Vector3(length, height, 0.1)
	wall.mesh = bm
	wall.material_override = mat
	parent.add_child(wall)
	wall.global_position = mid
	# Rotate so the wall's local +X axis lies along (p1 -> p2).
	wall.rotation.y = -atan2(p2.z - p1.z, p2.x - p1.x)


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
			var px: float = cx + _rng.randf_range(-0.5, 0.5)
			var pz: float = cz + _rng.randf_range(-0.5, 0.5)
			# Skip if the jittered position pokes outside non-rect tank shapes.
			if not _is_inside_tank(px, pz, 0.3):
				continue
			_spawn_plant(species_specs[0], Vector3(px, SUBSTRATE_DEPTH, pz),
				_rng.randi_range(2, 5))

	# --- Midground rosettes (crypts) + red accent stems scattered ---
	for i in 28:
		var xz: Vector2 = _random_xz_in_band(-0.5, 1.5, 0.3)
		_spawn_plant(species_specs[1], Vector3(xz.x, SUBSTRATE_DEPTH, xz.y),
			_rng.randi_range(2, 4))
	for i in 14:
		var xz: Vector2 = _random_xz_in_band(-1.5, 1.5, 0.3)
		_spawn_plant(species_specs[3], Vector3(xz.x, SUBSTRATE_DEPTH, xz.y),
			_rng.randi_range(2, 4))

	# --- Foreground carpet: very dense ---
	for i in 55:
		var xz: Vector2 = _random_xz_in_band(TANK_HALF_D * 0.2, TANK_HALF_D * 0.95, 0.3)
		_spawn_plant(species_specs[2], Vector3(xz.x, SUBSTRATE_DEPTH, xz.y),
			_rng.randi_range(1, 3))

	# --- Moss on the driftwood arch (epiphytes) ---
	for x in [-5.5, -4.0, -2.5, -1.0, 0.5, 1.8, 3.2, 4.5]:
		for off in [Vector3(0, 0.4, 0.2), Vector3(0.2, 0.5, -0.1), Vector3(-0.15, 0.45, 0.3)]:
			var arc_y: float = 2.0 + cos(x * 0.4) * 0.6
			_spawn_plant(species_specs[4], Vector3(x + off.x, arc_y, off.z),
				_rng.randi_range(1, 2))

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
		var sp_xz: Vector2 = _random_xz_in_band(-TANK_HALF_D * 0.8, TANK_HALF_D * 0.5, 0.4)
		sp.global_position = Vector3(sp_xz.x, SUBSTRATE_DEPTH, sp_xz.y)
		sp.ramp_override = spiral_ramps[i % spiral_ramps.size()]
		sp.water_surface_y = WATER_HEIGHT
		sp.generation = 0
		sp.radius_step = _rng.randf_range(0.05, 0.08)
		sp.height_step = _rng.randf_range(0.14, 0.22)
		sp.init(_rng.randi_range(3, 6), {
			"max_height": _rng.randi_range(20, 40),
			"growth_rate": 0.20,
			"sway_amplitude": 0.06,
		})
		sim.register_plant(sp)

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


func _initial_phenotype_spread() -> float:
	# How widely the founding cohort's phenotypes are scattered. Pulled from
	# the active TankConfig.tank_preset. 0 = clones, 2.5 = highly diverse.
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return 1.0
	var preset: Dictionary = cfg.current_tank_preset()
	return float(preset.get("phenotype_spread", 1.0))


func _spread_around(base: float, range: float, mult: float) -> float:
	# Helper: pick a value `base ± (range * mult)`. mult scales with preset.
	return base + _rng.randf_range(-range, range) * mult


func _apply_initial_phenotype_spread(genome: Dictionary, mult: float) -> void:
	# Scatter the heritable visible phenotypes around their defaults. Higher
	# mult = wider initial diversity. mult=0 means every founder is identical
	# (the "single species clones" preset).
	if mult <= 0.0:
		genome["fin_length_factor"] = 1.0
		genome["body_elongation"] = 1.0
		genome["body_depth_factor"] = 1.0
		genome["head_proportion"] = 1.0
		genome["dorsal_height_factor"] = 1.0
		genome["tail_fork_depth"] = 1.0
		genome["pattern_type"] = 1
		genome["color_dot_count"] = 0
		return
	genome["fin_length_factor"] = clampf(1.0 + _rng.randf_range(-0.2, 0.2) * mult, 0.6, 1.6)
	genome["body_elongation"] = clampf(1.0 + _rng.randf_range(-0.08, 0.08) * mult, 0.85, 1.15)
	genome["body_depth_factor"] = clampf(1.0 + _rng.randf_range(-0.15, 0.15) * mult, 0.7, 1.4)
	genome["head_proportion"] = clampf(1.0 + _rng.randf_range(-0.12, 0.12) * mult, 0.7, 1.3)
	genome["dorsal_height_factor"] = clampf(1.0 + _rng.randf_range(-0.20, 0.20) * mult, 0.6, 1.6)
	genome["tail_fork_depth"] = clampf(1.0 + _rng.randf_range(-0.18, 0.18) * mult, 0.5, 1.5)
	# Pattern: pick from {solid, stripe, spots, bars} with bias toward stripe
	# at low spread, more variety at high spread.
	if mult >= 1.5:
		genome["pattern_type"] = _rng.randi_range(0, 3)
	elif mult >= 0.7:
		genome["pattern_type"] = 1 if _rng.randf() < 0.55 else _rng.randi_range(0, 3)
	else:
		genome["pattern_type"] = 1
	genome["color_dot_count"] = clampi(int(_rng.randf_range(0, 2.5) * mult), 0, 4)


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
	# Read counts from TankConfig preset (or custom override).
	var cfg := get_node_or_null("/root/TankConfig")
	var glassdart_n: int = 14
	var mudsifter_n: int = 5
	var betta_n: int = 1
	if cfg != null:
		var preset: Dictionary = cfg.current_tank_preset()
		if cfg.tank_preset == "custom":
			glassdart_n = int(cfg.custom_glassdart_count)
			mudsifter_n = int(cfg.custom_mudsifter_count)
			betta_n = 1
		else:
			glassdart_n = int(preset.get("glassdarts", 14))
			mudsifter_n = int(preset.get("mudsifters", 5))
			betta_n = int(preset.get("betta", 1))
	var phenotype_mult: float = _initial_phenotype_spread()

	for i in glassdart_n:
		var g: Dictionary = glassdart_genome.duplicate()
		g["sex"] = i % 2
		g["max_age_s"] += randf_range(-30, 30)
		# Founding phenotype spread - wider for "diverse" preset, zero for clones.
		_apply_initial_phenotype_spread(g, phenotype_mult)
		# Clamp to tank footprint so hex/triangle shapes don't get fish in the
		# corners outside the glass.
		var gd_xz: Vector2 = _random_xz_in_band(-2.0, 2.0, 0.5)
		_spawn_fish_at(g, Vector3(gd_xz.x, randf_range(3.0, 4.5), gd_xz.y))
	for i in mudsifter_n:
		var g: Dictionary = mudsifter_genome.duplicate()
		g["sex"] = i % 2
		_apply_initial_phenotype_spread(g, phenotype_mult)
		var ms_xz: Vector2 = _random_xz_in_band(-2.0, 2.0, 0.5)
		_spawn_fish_at(g, Vector3(ms_xz.x, randf_range(2.0, 2.8), ms_xz.y))

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
	for b in betta_n:
		var bg: Dictionary = betta_genome.duplicate()
		bg["sex"] = randi() % 2
		var bt_xz: Vector2 = _random_xz_in_band(-1.0, 1.0, 0.6)
		_spawn_fish_at(bg, Vector3(bt_xz.x, 4.0, bt_xz.y))


var _light_fixture_root: Node3D = null
var _light_fixture_spots: Array[SpotLight3D] = []


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
	# 3-4 anaerobic bubble streams. Each rises bubbles to the meniscus, then
	# a paired pop-ripple emitter spawns small expanding rings at the surface
	# directly above. Bubble lifetime is tuned so the visual disappear lines
	# up with the surface depth.
	var n_streams: int = _rng.randi_range(3, 5)
	var container := Node3D.new()
	container.name = "BubbleStreams"
	add_child(container)
	for i in n_streams:
		var b_xz: Vector2 = _random_xz_in_band(-TANK_HALF_D * 0.85, TANK_HALF_D * 0.85, 0.4)
		var sx: float = b_xz.x
		var sz: float = b_xz.y
		# --- Rising bubbles from the substrate ---
		var p := GPUParticles3D.new()
		p.amount = 6
		# Tune lifetime so a bubble rises ~from substrate to surface.
		# bubble_speed (~0.6) * lifetime = distance, want ~(WATER_HEIGHT-SUBSTRATE)
		var rise_distance: float = WATER_HEIGHT - SUBSTRATE_DEPTH
		p.lifetime = clampf(rise_distance / 1.3, 2.5, 6.0)
		p.preprocess = p.lifetime * 0.5
		p.local_coords = false
		p.position = Vector3(sx, SUBSTRATE_DEPTH + 0.1, sz)
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

		# --- Pop ripples at the surface directly above ---
		_spawn_surface_pop_emitter(container, Vector3(sx, WATER_HEIGHT - 0.05, sz),
			p.lifetime, p.amount)


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


func _seed_nutrient_hotspots() -> void:
	# Push extra nutrients into a few cells so plants near them get a visible
	# head start. Without this, all plants would grow uniformly which is boring.
	for i in 5:
		var hs_xz: Vector2 = _random_xz_in_band(-TANK_HALF_D * 0.8, TANK_HALF_D * 0.8, 0.4)
		substrate_grid.add_at(Vector3(hs_xz.x, SUBSTRATE_DEPTH, hs_xz.y), 1.5)
