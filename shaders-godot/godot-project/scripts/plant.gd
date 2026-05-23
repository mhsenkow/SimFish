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
# "column" = legacy 1-voxel stacking (backward compat)
# "paddle" = rosette leaves (Crypts, Swords)
# "ribbon" = blade leaves (Vallisneria)
# "lance"  = stem plant paired leaves (Ludwigia, Rotala)
# "needle" = carpet grasses (Eleocharis)
var leaf_form: String = "column"
# How many voxels make up each leaf structure.
var leaf_length: int = 4

var current_height: int = 0
var growth_progress: float = 0.0
var voxels: Array[MeshInstance3D] = []
var has_flower: bool = false
var has_emerged: bool = false   # true once tip has reached the water surface
var bloom_voxels: Array[MeshInstance3D] = []
var seed_timer: float = 0.0
@warning_ignore("unused_private_class_variable")
var _flower_voxel: MeshInstance3D = null
var _phase: float = 0.0
var _t: float = 0.0
var _world_pos: Vector3 = Vector3.ZERO
# Surface for "emerged"/seeding check. Set by world.gd from WATER_HEIGHT
# at spawn so plant.gd doesn't need to know world geometry constants.
var water_surface_y: float = 6.5
var generation: int = 0

# ---- Root system ----
var root_voxels: Array[MeshInstance3D] = []
var _root_count: int = 0
var _max_roots: int = 5
var _root_growth_counter: int = 0  # grows one root per N stem voxels

# ---- Health & nutrient response ----
var health: float = 1.0  # 1.0 = thriving, 0.0 = dying
var _health_smooth: float = 1.0  # low-pass filtered for visual changes
var _starvation_timer: float = 0.0
var _has_pinholes: bool = false

# ---- Flowering lifecycle ----
enum FlowerStage { NONE, BUD, OPENING, MATURE, SEED_POD, RELEASING }
var flower_stage: int = FlowerStage.NONE
var _flower_timer: float = 0.0
var _flower_open_frac: float = 0.0
var _flower_node: Node3D = null
var _flower_petal_color: Color = Color.WHITE
var _flower_center_color: Color = Color.YELLOW

# ---- Decay state ----
var is_dying: bool = false
var _decay_timer: float = 0.0
var _melt_active: bool = false  # crypt melt in progress
var _melt_regrow_timer: float = 0.0
var _pre_melt_height: int = 0

# ---- Pearling particles ----
var _pearling_particles: GPUParticles3D = null
var _pearling_active: bool = false

# ---- Leaf structure tracking ----
# Each "growth unit" can be a leaf node containing multiple voxels.
var _leaf_nodes: Array[Node3D] = []
var _leaf_ages: Array[float] = []  # birth time per leaf for aging

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


func init(initial_height: int = 1, params: Dictionary = {}) -> void:
	max_height = params.get("max_height", max_height)
	growth_rate = params.get("growth_rate", growth_rate)
	nutrient_demand = params.get("nutrient_demand", nutrient_demand)
	sway_amplitude = params.get("sway_amplitude", sway_amplitude)
	leaf_form = params.get("leaf_form", leaf_form)
	leaf_length = params.get("leaf_length", leaf_length)
	_max_roots = params.get("max_roots", _max_roots)
	# Build initial roots.
	_build_initial_roots()
	for i in initial_height:
		_grow_one()


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
			"max_roots": _max_roots,
		},
		"ramp_override": SaveHelpers.colors_to_array(ramp_override),
		"water_surface_y": water_surface_y,
		"current_height": current_height,
		"growth_progress": growth_progress,
		"has_flower": has_flower,
		"has_emerged": has_emerged,
		"seed_timer": seed_timer,
		"health": health,
		"_health_smooth": _health_smooth,
		"flower_stage": int(flower_stage),
		"_flower_timer": _flower_timer,
		"_flower_open_frac": _flower_open_frac,
		"_flower_petal_color": SaveHelpers.color_to_array(_flower_petal_color),
		"_flower_center_color": SaveHelpers.color_to_array(_flower_center_color),
		"is_dying": is_dying,
		"generation": generation,
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
	has_flower = bool(d.get("has_flower", false))
	has_emerged = bool(d.get("has_emerged", false))
	seed_timer = float(d.get("seed_timer", 0.0))
	health = float(d.get("health", 1.0))
	_health_smooth = float(d.get("_health_smooth", health))
	flower_stage = int(d.get("flower_stage", 0)) as FlowerStage
	_flower_timer = float(d.get("_flower_timer", 0.0))
	_flower_open_frac = float(d.get("_flower_open_frac", 0.0))
	_flower_petal_color = SaveHelpers.array_to_color(d.get("_flower_petal_color", []), _flower_petal_color)
	_flower_center_color = SaveHelpers.array_to_color(d.get("_flower_center_color", []), _flower_center_color)
	is_dying = bool(d.get("is_dying", false))
	generation = int(d.get("generation", 0))


func _ready() -> void:
	_phase = float(get_instance_id() % 1000) * 0.013
	_world_pos = global_position
	# Set up pearling particle system.
	_setup_pearling()


func _build_initial_roots() -> void:
	var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
	var root_ramp: Array = [ramp[0].darkened(0.3), ramp[0].darkened(0.15)]
	var initial_roots: int = _rng_range(2, mini(3, _max_roots))
	for i in initial_roots:
		_add_root(root_ramp)


func _add_root(root_ramp: Array) -> void:
	if _root_count >= _max_roots:
		return
	var angle: float = float(_root_count) / float(maxi(1, _max_roots)) * TAU
	angle += randf_range(-0.4, 0.4)  # jitter
	var depth: int = _rng_range(2, 4)
	var root_color: Color = root_ramp[0] if root_ramp.size() > 0 else Color8(60, 45, 30)
	var root_light: Color = root_ramp[1] if root_ramp.size() > 1 else Color8(80, 60, 40)
	for j in depth:
		var t: float = float(j) / float(depth)
		var spread: float = t * VOXEL_SIZE * 1.2
		var mi := MeshInstance3D.new()
		var taper: float = 1.0 - t * 0.4
		mi.mesh = VoxelMat.get_box(Vector3(
			VOXEL_SIZE * 0.22 * taper,
			VOXEL_SIZE * 0.55,
			VOXEL_SIZE * 0.22 * taper,
		))
		mi.material_override = VoxelMat.make(root_color.lerp(root_light, t * 0.3))
		mi.position = Vector3(
			cos(angle) * spread,
			-float(j) * VOXEL_SIZE * 0.5,
			sin(angle) * spread,
		)
		add_child(mi)
		root_voxels.append(mi)
	_root_count += 1


func _setup_pearling() -> void:
	# Pearling = O2 micro-bubbles clinging to leaves in bright light. Should
	# read as a faint shimmer, never confused with the chunky opaque aerator
	# stream. Kept small in count, scale, and alpha intentionally.
	_pearling_particles = GPUParticles3D.new()
	_pearling_particles.name = "Pearling"
	_pearling_particles.emitting = false
	_pearling_particles.amount = 4
	_pearling_particles.lifetime = 4.0
	_pearling_particles.local_coords = false
	_pearling_particles.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 8, 4))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.45
	pm.gravity = Vector3(0, 0.15, 0)  # bubbles rise slowly
	pm.spread = 12.0
	pm.scale_min = 0.2
	pm.scale_max = 0.55
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	# Gentle alpha curve: fade in, hold faint, fade out. Never opaque.
	var alpha_curve := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.15, 0.6))
	curve.add_point(Vector2(0.7, 0.5))
	curve.add_point(Vector2(1.0, 0.0))
	alpha_curve.curve = curve
	pm.alpha_curve = alpha_curve
	_pearling_particles.process_material = pm
	# Tiny near-clear sphere mesh for the bubbles. Base alpha is the cap
	# the curve scales against, so keep it well below the aerator's opaque
	# look.
	var bubble_mesh := SphereMesh.new()
	bubble_mesh.radius = 0.028
	bubble_mesh.height = 0.056
	bubble_mesh.radial_segments = 4
	bubble_mesh.rings = 2
	var bubble_mat := StandardMaterial3D.new()
	bubble_mat.albedo_color = Color(0.92, 0.96, 1.0, 0.35)
	bubble_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bubble_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bubble_mesh.material = bubble_mat
	_pearling_particles.draw_pass_1 = bubble_mesh
	add_child(_pearling_particles)


func _grow_one() -> bool:
	if current_height >= max_height:
		return false
	if is_dying or _melt_active:
		return false

	var rel: float = float(current_height) / float(maxi(1, max_height - 1))
	var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
	var age_frac: float = 0.0  # new growth = age 0

	# Apply health-based color shift.
	var effective_ramp: Array = ramp
	if _health_smooth < 0.7:
		effective_ramp = _build_stressed_ramp(ramp)

	# Phototropism: bias the new voxel's lateral offset toward the light.
	var photo_offset: Vector2 = _phototropic_offset()

	match leaf_form:
		"paddle":
			_grow_paddle_leaf(effective_ramp, age_frac, rel, photo_offset)
		"ribbon":
			_grow_ribbon_leaf(effective_ramp, age_frac, rel, photo_offset)
		"lance":
			_grow_lance_pair(effective_ramp, age_frac, rel, photo_offset)
		"needle":
			_grow_needle_leaf(effective_ramp, age_frac, rel, photo_offset)
		_:
			_grow_column_voxel(effective_ramp, rel, photo_offset)

	current_height += 1

	# Root growth: add a root every 3-4 stem voxels.
	_root_growth_counter += 1
	if _root_growth_counter >= 3 and _root_count < _max_roots:
		_root_growth_counter = 0
		var root_ramp: Array = [ramp[0].darkened(0.3), ramp[0].darkened(0.15)]
		_add_root(root_ramp)

	return true


func _grow_column_voxel(ramp: Array, rel: float, photo_offset: Vector2) -> void:
	# Legacy single-voxel growth for backward compatibility.
	var ramp_idx: int = clampi(int(rel * 5.0), 0, 5)
	var color: Color = ramp[ramp_idx]
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelMat.get_box(Vector3(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE))
	mi.material_override = VoxelMat.make(color)
	var lat: float = sin(rel * PI * 0.6) * sway_amplitude * 0.6
	mi.position = Vector3(
		lat + photo_offset.x,
		current_height * VOXEL_SIZE + VOXEL_SIZE * 0.5,
		photo_offset.y,
	)
	add_child(mi)
	voxels.append(mi)


func _grow_paddle_leaf(ramp: Array, age_frac: float, rel: float,
		photo_offset: Vector2) -> void:
	var leaf_node := Node3D.new()
	leaf_node.name = "Leaf_%d" % current_height
	add_child(leaf_node)
	# Position along the stem with phototropism.
	var lat: float = sin(rel * PI * 0.6) * sway_amplitude * 0.6
	leaf_node.position = Vector3(
		lat + photo_offset.x,
		current_height * VOXEL_SIZE * 0.9 + VOXEL_SIZE * 0.5,
		photo_offset.y,
	)
	# Fan outward from center, alternating sides.
	var side: float = 1.0 if (current_height % 2 == 0) else -1.0
	leaf_node.rotation.y = side * 0.4 + rel * 0.2
	# Build the paddle leaf.
	var leaf_voxels: Array = LeafShapes.build_paddle(
		clampi(leaf_length, 2, 6), ramp, age_frac, 2, 0.5)
	for v in leaf_voxels:
		leaf_node.add_child(v)
		voxels.append(v)
	_leaf_nodes.append(leaf_node)
	_leaf_ages.append(_t)


func _grow_ribbon_leaf(ramp: Array, age_frac: float, _rel: float,
		photo_offset: Vector2) -> void:
	var leaf_node := Node3D.new()
	leaf_node.name = "Blade_%d" % current_height
	add_child(leaf_node)
	leaf_node.position = Vector3(
		photo_offset.x + randf_range(-0.1, 0.1),
		VOXEL_SIZE * 0.3,
		photo_offset.y + randf_range(-0.1, 0.1),
	)
	# Each blade emerges from the base and goes up. For ribbon plants,
	# current_height tracks number of blades, not individual voxels.
	var blade_len: int = clampi(leaf_length + _rng_range(-1, 2), 4, 14)
	var sway_seed: float = randf() * TAU
	var leaf_voxels: Array = LeafShapes.build_ribbon(
		blade_len, ramp, age_frac, sway_seed)
	for v in leaf_voxels:
		leaf_node.add_child(v)
		voxels.append(v)
	_leaf_nodes.append(leaf_node)
	_leaf_ages.append(_t)


func _grow_lance_pair(ramp: Array, age_frac: float, rel: float,
		photo_offset: Vector2) -> void:
	# Stem voxel first.
	var stem_mi := MeshInstance3D.new()
	stem_mi.mesh = VoxelMat.get_box(Vector3(VOXEL_SIZE * 0.35, VOXEL_SIZE * 0.9, VOXEL_SIZE * 0.35))
	var stem_color: Color = ramp[0] if ramp.size() > 0 else Color8(40, 70, 30)
	stem_mi.material_override = VoxelMat.make(stem_color.darkened(0.1))
	var lat: float = sin(rel * PI * 0.6) * sway_amplitude * 0.6
	stem_mi.position = Vector3(
		lat + photo_offset.x,
		current_height * VOXEL_SIZE * 0.85 + VOXEL_SIZE * 0.5,
		photo_offset.y,
	)
	add_child(stem_mi)
	voxels.append(stem_mi)
	# Leaf pair every 2nd node.
	if current_height % 2 == 0:
		var leaf_node := Node3D.new()
		leaf_node.name = "LeafPair_%d" % current_height
		leaf_node.position = stem_mi.position
		add_child(leaf_node)
		@warning_ignore("integer_division")
		var leaf_voxels: Array = LeafShapes.build_lance_pair(
			ramp, age_frac, current_height / 2)
		for v in leaf_voxels:
			leaf_node.add_child(v)
			voxels.append(v)
		_leaf_nodes.append(leaf_node)
		_leaf_ages.append(_t)


func _grow_needle_leaf(ramp: Array, age_frac: float, _rel: float,
		photo_offset: Vector2) -> void:
	var leaf_node := Node3D.new()
	leaf_node.name = "Needle_%d" % current_height
	add_child(leaf_node)
	leaf_node.position = Vector3(
		photo_offset.x + randf_range(-0.05, 0.05),
		VOXEL_SIZE * 0.2,
		photo_offset.y + randf_range(-0.05, 0.05),
	)
	var needle_len: int = clampi(leaf_length, 2, 6)
	var leaf_voxels: Array = LeafShapes.build_needle(needle_len, ramp, age_frac)
	for v in leaf_voxels:
		leaf_node.add_child(v)
		voxels.append(v)
	_leaf_nodes.append(leaf_node)
	_leaf_ages.append(_t)


func _build_stressed_ramp(base_ramp: Array) -> Array:
	var stressed: Array = []
	var stress_amt: float = clampf(1.0 - _health_smooth, 0.0, 1.0)
	for c in base_ramp:
		var sc: Color = LeafShapes.stress_color(c as Color, stress_amt, STRESS_RAMP)
		stressed.append(sc)
	return stressed


func biomass() -> int:
	return current_height


# Called by SimDriver each tick.
func tick(dt: float, substrate: SubstrateGrid) -> void:
	_t += dt

	# ---- Flow-based sway ----
	# Base sway + asymmetric flow bias from aeration direction.
	var flow_bias: float = _get_flow_bias()
	var sway: float = sin(_t * 0.7 + _phase) * 0.08
	sway += flow_bias * 0.04  # downstream lean
	rotation.z = sway
	# Leaf flutter: individual leaves get micro-oscillation.
	_flutter_leaves(dt)

	# ---- Health tracking ----
	var available: float = substrate.get_at(_world_pos)
	var nutrient_mult: float = clampf(
		(available - substrate.NUTRIENT_BASELINE) / 0.4, 0.0, 1.0)
	# Health trends toward nutrient satisfaction, with slow decay when starved.
	var target_health: float = 0.35 + 0.65 * nutrient_mult
	health = lerpf(health, target_health, dt * 0.03) # slower health changes
	_health_smooth = lerpf(_health_smooth, health, dt * 0.05)

	# ---- Deficiency symptoms ----
	if _health_smooth < 0.4 and not _has_pinholes and voxels.size() > 4:
		_apply_pinholes()
	if _health_smooth < 0.2 and not is_dying:
		_begin_dying()

	# ---- Starvation → leaf shedding ----
	if _health_smooth < 0.45:
		_starvation_timer += dt
		if _starvation_timer > 25.0 and not _leaf_nodes.is_empty():
			_starvation_timer = 0.0
			_shed_oldest_leaf()

	# ---- Crypt melt recovery ----
	if _melt_active:
		_melt_regrow_timer += dt
		if _melt_regrow_timer > 40.0:  # ~40 sim seconds to recover
			_melt_active = false
			_melt_regrow_timer = 0.0
			# Regrow from the rhizome.
			is_dying = false
			health = 0.5
			_health_smooth = 0.5
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
	if current_height >= max_height:
		# Mature: manage flowering + seeding.
		_tick_flowering(dt)
		_tick_seeding(dt)
		_tick_pearling(dt)
		
		# Indeterminate slow growth
		var eff_rate: float = growth_rate * (0.05 + 0.15 * nutrient_mult)
		growth_progress += eff_rate * dt
		if growth_progress >= 1.0:
			growth_progress = 0.0
			# Tentatively raise the cap, then attempt to grow into the new
			# space. If `_grow_one()` fails (plant is dying / melting / has
			# some other hard veto), REVERT the cap raise. Without this
			# revert, `max_height` ratcheted up on every failed grow attempt,
			# which over a long-running tank let dying plants record
			# preposterously large maximum heights that affected leaf
			# placement math later on.
			max_height += 1
			if _grow_one():
				substrate.consume_at(_world_pos, nutrient_demand)
			else:
				max_height -= 1
		else:
			# Maintenance
			substrate.consume_at(_world_pos, nutrient_demand * 0.1 * dt)
		return

	var effective_rate: float = growth_rate * (0.4 + 0.8 * nutrient_mult)
	growth_progress += effective_rate * dt
	if growth_progress >= 1.0:
		growth_progress = 0.0
		if _grow_one():
			substrate.consume_at(_world_pos, nutrient_demand)

	# ---- Pearling ----
	_tick_pearling(dt)

	# ---- Flowering trigger ----
	if not has_flower and current_height >= max_height - 1 and randf() < 0.0005:
		_begin_flowering()

	# Emergent check.
	if not has_emerged and top_world_y() >= water_surface_y - 0.15:
		_emerge_above_water()

	# Seeding.
	_tick_seeding(dt)

	# Vegetative spread via runners (ribbon-form plants only).
	_tick_runner(dt)


# Ribbon-form plants extend a horizontal stolon along the substrate that
# matures into a daughter plant at its tip. The chain grows one voxel
# every RUNNER_SEGMENT_TIME seconds so the player can watch the runner
# stretch. Skips if not mature enough, the cooldown is still active, or
# this individual is already running one.
func _tick_runner(dt: float) -> void:
	if leaf_form != "ribbon":
		return
	if _runner_active:
		_advance_runner(dt)
		return
	_runner_cooldown = maxf(0.0, _runner_cooldown - dt)
	if _runner_cooldown > 0.0:
		return
	if current_height < 8 or is_dying:
		return
	# Don't endlessly spam runners if the parent plant is unhealthy.
	if health < 0.55:
		return
	_begin_runner()


func _begin_runner() -> void:
	# Pick a random horizontal direction + distance. The runner stays
	# parallel to the substrate (no Y change). _runner_target is in this
	# plant's LOCAL space - we don't want the chain to drift when the
	# plant sways.
	var theta: float = randf() * TAU
	var dist: float = randf_range(RUNNER_DISTANCE_MIN, RUNNER_DISTANCE_MAX)
	_runner_origin = Vector3(0.0, 0.0, 0.0)
	_runner_target = Vector3(cos(theta) * dist, 0.0, sin(theta) * dist)
	_runner_active = true
	_runner_progress = 0.0
	_runner_voxels.clear()


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
		rv.material_override = VoxelMat.make(ramp[1])  # darker green, runner is woody
		rv.position = local_pos
		add_child(rv)
		_runner_voxels.append(rv)
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
			w.spawn_seedling(world_pos, mutated_ramp, generation + 1, get_seed_config())
	_runner_active = false
	_runner_progress = 0.0
	_runner_cooldown = randf_range(RUNNER_COOLDOWN_MIN, RUNNER_COOLDOWN_MAX)


# ---- Flowering lifecycle ----

func _begin_flowering() -> void:
	if flower_stage != FlowerStage.NONE:
		return
	flower_stage = FlowerStage.BUD
	_flower_timer = 0.0
	has_flower = true
	# Choose flower colors.
	var palettes: Array = [
		[Color8(230, 130, 200), Color8(245, 220, 90)],   # pink + gold
		[Color8(245, 220, 90), Color8(255, 180, 60)],    # daffodil
		[Color8(170, 130, 220), Color8(200, 180, 60)],   # lavender + gold
		[Color8(240, 240, 240), Color8(245, 195, 100)],  # white + gold
		[Color8(220, 100, 100), Color8(230, 200, 60)],   # red + yellow
	]
	var pal: Array = palettes[randi() % palettes.size()]
	_flower_petal_color = pal[0]
	_flower_center_color = pal[1]
	# Build bud.
	_flower_node = Node3D.new()
	_flower_node.name = "Flower"
	_flower_node.position = Vector3(0, current_height * VOXEL_SIZE + VOXEL_SIZE * 1.2, 0)
	add_child(_flower_node)
	var bud_voxels: Array = LeafShapes.build_bud(_flower_petal_color.darkened(0.3))
	for v in bud_voxels:
		_flower_node.add_child(v)
		bloom_voxels.append(v)


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
			# Open over 4 seconds.
			_flower_open_frac = clampf(_flower_timer / 4.0, 0.0, 1.0)
			LeafShapes.update_flower(bloom_voxels, 5, _flower_open_frac)
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
			# Release 1-3 seeds over a few seconds.
			if _flower_timer > 2.0:
				_cast_seed()
				_clear_bloom()
				if _flower_node != null and is_instance_valid(_flower_node):
					_flower_node.queue_free()
					_flower_node = null
				flower_stage = FlowerStage.NONE
				has_flower = false


func _build_flower_meshes_once() -> void:
	if _flower_node == null or not is_instance_valid(_flower_node):
		return
	var flower_voxels: Array = LeafShapes.build_flower(
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

func _tick_pearling(_dt: float) -> void:
	var sim_driver: Node = _find_sim()
	if sim_driver == null:
		return
	var o2: float = float(sim_driver.get("dissolved_o2"))
	var daylight: float = 1.0
	if sim_driver.has_method("daylight"):
		daylight = sim_driver.daylight()
	# Pearl when: high O2 + bright light + plant is healthy + actively growing.
	var should_pearl: bool = o2 > 0.85 and daylight > 0.5 and health > 0.6 \
		and current_height > 3
	if should_pearl and not _pearling_active:
		_pearling_active = true
		_pearling_particles.emitting = true
		# Position at the top of the plant.
		_pearling_particles.position = Vector3(0, current_height * VOXEL_SIZE * 0.8, 0)
	elif not should_pearl and _pearling_active:
		_pearling_active = false
		_pearling_particles.emitting = false
	elif _pearling_active:
		# Update position to follow growth.
		_pearling_particles.position = Vector3(0, current_height * VOXEL_SIZE * 0.8, 0)


# ---- Seeding ----

func _tick_seeding(dt: float) -> void:
	seed_timer += dt
	if has_emerged:
		if seed_timer >= 18.0 and randf() < 0.5:
			seed_timer = 0.0
			_cast_seed()
	elif current_height >= max_height and seed_timer >= 60.0 and randf() < 0.25:
		seed_timer = 0.0
		_cast_seed()


# ---- Decay & death ----

func _begin_dying() -> void:
	if is_dying:
		return
	is_dying = true
	_decay_timer = 0.0
	# Stop pearling.
	if _pearling_active:
		_pearling_active = false
		_pearling_particles.emitting = false


func _decay_one_voxel() -> void:
	if voxels.is_empty():
		return
	# Remove from the top (tips die first).
	var v: MeshInstance3D = voxels.pop_back()
	if is_instance_valid(v):
		# Spawn a tiny waste particle at the voxel's world position.
		_spawn_decay_waste(v.global_position)
		v.queue_free()
	_recalc_height()


func _shed_oldest_leaf() -> void:
	# Drop the oldest (bottom) leaf node, creating detritus.
	if _leaf_nodes.is_empty():
		return
	var oldest: Node3D = _leaf_nodes.pop_front()
	if _leaf_ages.size() > 0:
		_leaf_ages.pop_front()
	if is_instance_valid(oldest):
		# Remove its voxels from the main array too.
		for child in oldest.get_children():
			if child is MeshInstance3D:
				voxels.erase(child)
		_spawn_decay_waste(oldest.global_position)
		oldest.queue_free()


func trigger_crypt_melt() -> void:
	# Dramatic melt: all leaves dissolve rapidly, but roots persist.
	_melt_active = true
	_melt_regrow_timer = 0.0
	_pre_melt_height = current_height
	# Burst: remove all leaf voxels rapidly.
	for v in voxels:
		if is_instance_valid(v):
			_spawn_decay_waste(v.global_position)
			v.queue_free()
	voxels.clear()
	_leaf_nodes.clear()
	_leaf_ages.clear()
	current_height = 0
	_clear_bloom()
	has_flower = false
	flower_stage = FlowerStage.NONE
	# Roots stay! They're the rhizome that will regrow.


func _spawn_decay_waste(at: Vector3) -> void:
	var sim_driver: Node = _find_sim()
	if sim_driver == null:
		return
	if sim_driver.has_method("_spawn_waste"):
		# WasteParticle.KIND_FISH = 0 used as generic plant detritus.
		sim_driver._spawn_waste(at, 0.06, 0)


# ---- Leaf flutter ----

func _flutter_leaves(dt: float) -> void:
	# IMPORTANT: this sets the *absolute* per-frame rotation from a sinusoid,
	# it doesn't add a delta. The previous `+=` version was an unintended
	# integrator — `dt * 60` framerate-normalised the increment so the math
	# looks like an "amount per frame at 60fps," but the underlying value
	# accumulated forever. Over an hour-long session leaves drifted to
	# pretzel angles. Using `=` snaps them back to a bounded oscillation
	# around their build-time orientation each frame.
	# (`dt` is still here as a no-op tag in case we ever switch to a true
	# damped-spring model, where dt would matter again.)
	var _ignored_dt: float = dt
	for i in _leaf_nodes.size():
		if not is_instance_valid(_leaf_nodes[i]):
			continue
		var leaf: Node3D = _leaf_nodes[i]
		var ph: float = _phase + float(i) * 1.7
		# Very subtle micro-rotation. Amplitudes (~4-5°) match the steady-state
		# excursion the previous accumulator settled at after a few seconds of
		# integration — chosen so existing tanks visually look the same on
		# average, just without the unbounded drift.
		leaf.rotation.z = sin(_t * 2.5 + ph) * 0.072
		leaf.rotation.x = cos(_t * 2.2 + ph * 1.3) * 0.048


# ---- Flow response ----

func _get_flow_bias() -> float:
	# Sample a rough flow direction from the aeration system's position.
	# Plants on the same side as the aerator get pushed away; plants on the
	# opposite side barely feel it.
	var sim_driver: Node = _find_sim()
	if sim_driver == null:
		return 0.0
	var aeration_x: float = 0.0
	var cfg := sim_driver.get_node_or_null("/root/TankConfig")
	if cfg != null:
		aeration_x = float(cfg.get("aeration_x_frac")) * 8.0  # rough world space
	var dx: float = _world_pos.x - aeration_x
	# Strength falls off with distance.
	var strength: float = clampf(1.0 - absf(dx) / 12.0, 0.0, 0.5)
	return sign(dx) * strength


# ---- Pinholes (potassium deficiency symptom) ----

func _apply_pinholes() -> void:
	_has_pinholes = true
	# Make some voxels in the middle of the plant invisible (gaps in leaves).
	@warning_ignore("integer_division")
	var n_holes: int = maxi(1, voxels.size() / 6)
	for i in n_holes:
		var idx: int = randi() % maxi(1, voxels.size())
		if idx < voxels.size() and is_instance_valid(voxels[idx]):
			voxels[idx].visible = false


# Fish nibbling: remove up to `amount` voxels from the top. Returns the
# number removed (= food value the fish gained).
func nibble(amount: int) -> int:
	var removed: int = 0
	for i in amount:
		if voxels.is_empty():
			break
		var v: MeshInstance3D = voxels.pop_back()
		if is_instance_valid(v):
			v.queue_free()
		removed += 1
		# Reset growth progress so the regrow doesn't snap a new voxel in instantly.
		growth_progress = 0.0
		
	_recalc_height()
	
	if current_height <= 0 and voxels.is_empty():
		_on_death()
		queue_free()
	return removed


func _recalc_height() -> void:
	var max_local_y: float = 0.0
	for v in voxels:
		if is_instance_valid(v) and not v.is_queued_for_deletion():
			var ly = v.global_position.y - global_position.y
			max_local_y = maxf(max_local_y, ly)
	current_height = maxi(0, int(max_local_y / VOXEL_SIZE))


func _on_death() -> void:
	# When a plant is fully eaten, its roots + decay matter return some
	# nutrients to the substrate. Closes the cycle: without this the nutrient
	# pool drifts down over time because waste gets eaten before settling.
	# We add directly to the substrate grid since the plant's about to free.
	var sim_driver: Node = _find_sim()
	if sim_driver != null and sim_driver.substrate != null:
		sim_driver.substrate.add_at(global_position, 0.35)


func _emerge_above_water() -> void:
	has_emerged = true
	_begin_flowering()


func _flower() -> void:
	# Legacy single-voxel flower for backward compatibility.
	_begin_flowering()


func _cast_seed() -> void:
	# Drop a small seed voxel nearby. SimDriver picks it up via a Plant.gd
	# tick check - we rely on the world spawning a new plant at the seed
	# position. Cheap approach: directly request the world spawn a child
	# plant near us, inheriting the parent's ramp_override with mutation.
	var sim_driver: Node = _find_sim()
	if sim_driver == null:
		return
	var world: Node = sim_driver.get_parent()
	if world == null or not world.has_method("spawn_seedling"):
		return
	var seed_pos: Vector3 = global_position + Vector3(
		randf_range(-1.5, 1.5),
		0.0,
		randf_range(-1.5, 1.5),
	)
	# Mutated ramp = parent's ramp lerped toward a random color slightly.
	var mutated_ramp: Array = ramp_override.duplicate()
	if mutated_ramp.size() == 6:
		var muta: float = 0.10
		var jitter := Color(randf(), randf(), randf())
		for i in mutated_ramp.size():
			mutated_ramp[i] = (mutated_ramp[i] as Color).lerp(jitter, muta)
	world.spawn_seedling(seed_pos, mutated_ramp, generation + 1, get_seed_config())


# Returns a dictionary of heritable traits so seedlings spawn as the same species.
func get_seed_config() -> Dictionary:
	return {
		"script": get_script(),
		"max_height": max_height,
		"growth_rate": growth_rate,
		"sway_amplitude": sway_amplitude,
		"leaf_form": leaf_form,
		"leaf_length": leaf_length,
		"max_roots": _max_roots,
	}



func _phototropic_offset() -> Vector2:
	var cfg := _find_sim()
	if cfg == null:
		return Vector2.ZERO
	var tc := cfg.get_node("/root/TankConfig") if cfg.has_node("/root/TankConfig") else null
	if tc == null:
		return Vector2.ZERO
	var yaw_rad: float = float(tc.light_yaw) * TAU
	var photo_strength: float = 0.04
	var height_factor: float = float(current_height) / float(maxi(1, max_height))
	var bias: float = photo_strength * height_factor
	return Vector2(sin(yaw_rad) * bias, cos(yaw_rad) * bias)


# Quick world-space height of the top voxel (for fish to target nibbling).
func top_world_y() -> float:
	return global_position.y + current_height * VOXEL_SIZE


# ---- Utility ----

func _rng_range(lo: int, hi: int) -> int:
	return lo + randi() % maxi(1, hi - lo + 1)
