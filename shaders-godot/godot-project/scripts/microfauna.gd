# Microfauna — copepods / daphnia / tiny crustaceans drifting in the water
# column. Pure decoration with light ecological hooks:
#
#  - About 80–150 individuals at any time, maintained by world.gd's refill
#    loop so the swarm doesn't fade out over a long session.
#  - Each one wanders with re-jittered Brownian-ish drift + a slow vertical
#    bob. Faint emission so they read as tiny living dots against the
#    dark water rather than getting eaten by the palette.
#  - Lifespan ~3 sim minutes — they "live and die" so the swarm constantly
#    refreshes its composition.
#  - Filter intake: if sim.filter_intake_pos is set and a microfauna drifts
#    within FILTER_PULL_RADIUS, it accelerates toward the intake and is
#    "filtered out" on arrival. Closes the visible loop "tiny life → filter".
#
# Performance: each one is a single MeshInstance3D with a shared StandardMaterial3D
# (created in _ready). 100 of them at the default render rate is cheap
# relative to fish (which build dozens of voxels each).

class_name Microfauna
extends Node3D


const SCALE_MIN: float = 0.020
const SCALE_MAX: float = 0.038
const DRIFT_SPEED: float = 0.06
const BOB_SPEED: float = 1.4
const BOB_AMP: float = 0.010
const REJITTER_INTERVAL_MIN: float = 0.5
const REJITTER_INTERVAL_MAX: float = 1.6
const LIFESPAN_S: float = 180.0
const FILTER_PULL_RADIUS: float = 0.6
const FILTER_PULL_STRENGTH: float = 0.55  # m/s toward intake
const FILTER_CONSUME_DIST: float = 0.10
const APPENDAGE_ANIM_STEP: int = 2
const MOTION_STEP: float = 1.0 / 30.0


var sim: Node = null
var _age: float = 0.0
var _drift: Vector3 = Vector3.ZERO
var _next_jitter_t: float = 0.0
var _bob_phase: float = 0.0
var _body_root: Node3D = null
var _appendages: Array[Node3D] = []
var _morph_kind: int = 0
var _anim_tick: int = 0
var _step_accum: float = 0.0
static var _piece_material_cache: Dictionary = {}


var visibility_scale: float = 1.0


func set_swarm_presence(fill: float) -> void:
	visibility_scale = lerpf(1.0, 1.85, clampf(fill, 0.0, 1.0))
	if _body_root != null:
		_body_root.scale = Vector3.ONE * visibility_scale


func _ready() -> void:
	_bob_phase = randf() * TAU
	_next_jitter_t = randf_range(REJITTER_INTERVAL_MIN, REJITTER_INTERVAL_MAX)
	_seed_drift()
	# Morph variants (copepod / daphnia / larval) with modular appendages so
	# the tiny-life layer has visible architecture diversity.
	var scale_v: float = randf_range(SCALE_MIN, SCALE_MAX)
	_morph_kind = randi() % 3
	var body_col: Color = Color8(232, 228, 215)
	var glow_col: Color = Color8(200, 200, 180)
	if _morph_kind == 1:
		body_col = Color8(190, 215, 225)
		glow_col = Color8(150, 180, 200)
	elif _morph_kind == 2:
		body_col = Color8(208, 226, 196)
		glow_col = Color8(176, 206, 160)
	_anim_tick = randi() % APPENDAGE_ANIM_STEP
	_build_morphology(scale_v, body_col, glow_col)
	if visibility_scale != 1.0:
		_body_root.scale = Vector3.ONE * visibility_scale


func _seed_drift() -> void:
	var base := Vector3(
		randf_range(-1, 1),
		randf_range(-0.4, 0.4),
		randf_range(-1, 1),
	)
	if base.length_squared() < 1e-6:
		base = Vector3(1.0, 0.0, 0.0)
	_drift = base.normalized() * DRIFT_SPEED * randf_range(0.7, 1.3)


func _make_piece(size: Vector3, color: Color, emission: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	# Shared mesh/material resources are critical here: 90-120 microfauna,
	# each with multiple pieces, can otherwise trigger Metal fence stalls.
	mi.mesh = VoxelMat.get_box(size)
	mi.material_override = _piece_mat(color, emission)
	return mi


func _piece_mat(color: Color, emission: Color) -> Material:
	var key: String = "%s|%s" % [
		Color(snappedf(color.r, 0.02), snappedf(color.g, 0.02), snappedf(color.b, 0.02), 1.0).to_html(false),
		Color(snappedf(emission.r, 0.02), snappedf(emission.g, 0.02), snappedf(emission.b, 0.02), 1.0).to_html(false),
	]
	if _piece_material_cache.has(key):
		return _piece_material_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission = emission
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 0.35
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_piece_material_cache[key] = mat
	return mat


func _build_morphology(scale_v: float, body_col: Color, glow_col: Color) -> void:
	_body_root = Node3D.new()
	_body_root.name = "MorphRoot"
	add_child(_body_root)
	var core := _make_piece(Vector3.ONE * scale_v, body_col, glow_col)
	_body_root.add_child(core)
	_appendages.clear()
	match _morph_kind:
		0:
			# Copepod-like: head nub + two antenna arms.
			var head := _make_piece(Vector3(scale_v * 0.65, scale_v * 0.55, scale_v * 0.45),
				body_col.lightened(0.08), glow_col)
			head.position = Vector3(0, scale_v * 0.15, -scale_v * 0.48)
			_body_root.add_child(head)
			for x_side in [-1.0, 1.0]:
				var arm := Node3D.new()
				arm.position = Vector3(x_side * scale_v * 0.32, scale_v * 0.08, -scale_v * 0.24)
				var seg := _make_piece(Vector3(scale_v * 0.16, scale_v * 0.12, scale_v * 0.55),
					body_col.darkened(0.08), glow_col.darkened(0.12))
				seg.position = Vector3(0, 0, -scale_v * 0.22)
				arm.add_child(seg)
				_body_root.add_child(arm)
				_appendages.append(arm)
		1:
			# Daphnia-like shell: side wings.
			for x_side in [-1.0, 1.0]:
				var wing := _make_piece(
					Vector3(scale_v * 0.25, scale_v * 0.58, scale_v * 0.72),
					body_col.lightened(0.10), glow_col.lightened(0.05))
				wing.position = Vector3(x_side * scale_v * 0.42, 0, scale_v * 0.02)
				_body_root.add_child(wing)
			var tail := Node3D.new()
			tail.position = Vector3(0, -scale_v * 0.08, scale_v * 0.38)
			var tseg := _make_piece(Vector3(scale_v * 0.14, scale_v * 0.12, scale_v * 0.5),
				body_col.darkened(0.12), glow_col.darkened(0.15))
			tseg.position = Vector3(0, 0, scale_v * 0.24)
			tail.add_child(tseg)
			_body_root.add_child(tail)
			_appendages.append(tail)
		_:
			# Larval crustacean style: segmented body chain.
			var prev_z: float = -scale_v * 0.16
			for i in 3:
				var seg := _make_piece(
					Vector3(scale_v * (0.78 - float(i) * 0.16),
						scale_v * (0.72 - float(i) * 0.14),
						scale_v * 0.46),
					body_col.lerp(body_col.darkened(0.16), float(i) * 0.25),
					glow_col)
				seg.position = Vector3(0, 0, prev_z + i * scale_v * 0.34)
				_body_root.add_child(seg)
			for x_side in [-1.0, 1.0]:
				var fin := Node3D.new()
				fin.position = Vector3(x_side * scale_v * 0.30, 0, scale_v * 0.28)
				var fseg := _make_piece(Vector3(scale_v * 0.13, scale_v * 0.10, scale_v * 0.42),
					body_col.lightened(0.06), glow_col.darkened(0.08))
				fin.add_child(fseg)
				_body_root.add_child(fin)
				_appendages.append(fin)


func _process(dt: float) -> void:
	if sim != null:
		dt *= sim.time_scale
		if dt <= 0.0:
			return
	dt = minf(dt, 0.08)
	_step_accum += dt
	var steps: int = 0
	while _step_accum >= MOTION_STEP and steps < 3:
		_step_accum -= MOTION_STEP
		_sim_step(MOTION_STEP)
		steps += 1


func _sim_step(dt: float) -> void:
	_age += dt
	if _age >= LIFESPAN_S:
		queue_free()
		return
	position += _drift * dt
	_bob_phase += dt * BOB_SPEED
	position.y += sin(_bob_phase) * BOB_AMP * dt * 6.0
	_next_jitter_t -= dt
	if _next_jitter_t <= 0.0:
		_seed_drift()
		_next_jitter_t = randf_range(REJITTER_INTERVAL_MIN, REJITTER_INTERVAL_MAX)
	if _body_root != null:
		_body_root.rotation.y = sin(_bob_phase * 0.6) * 0.30
	_anim_tick = (_anim_tick + 1) % APPENDAGE_ANIM_STEP
	if _anim_tick == 0:
		for i in _appendages.size():
			var ap: Node3D = _appendages[i]
			if ap == null or not is_instance_valid(ap):
				continue
			ap.rotation.y = sin(_bob_phase * 1.9 + float(i) * 1.3) * 0.55
			ap.rotation.x = cos(_bob_phase * 1.5 + float(i) * 0.7) * 0.25
	if sim != null and sim.get("filter_intake_pos") != null:
		var intake: Vector3 = sim.filter_intake_pos
		if intake != Vector3.ZERO:
			var to_intake: Vector3 = intake - position
			var d2: float = to_intake.length_squared()
			if d2 < FILTER_PULL_RADIUS * FILTER_PULL_RADIUS:
				if d2 < 1e-8:
					queue_free()
					return
				var d: float = sqrt(d2)
				var dir: Vector3 = to_intake / d
				var pull: float = FILTER_PULL_STRENGTH * (1.0 - d / FILTER_PULL_RADIUS) + 0.15
				position += dir * pull * dt
				if d < FILTER_CONSUME_DIST:
					queue_free()
					return
	if sim != null:
		var w: Node = sim.get_parent()
		if w != null and w.has_method("clamp_xyz_in_tank"):
			position = w.clamp_xyz_in_tank(position, 0.15)
		else:
			var b: AABB = sim.world_bounds
			position.x = clampf(position.x, b.position.x, b.position.x + b.size.x)
			position.y = clampf(position.y, b.position.y, b.position.y + b.size.y)
			position.z = clampf(position.z, b.position.z, b.position.z + b.size.z)
	if not position.is_finite():
		queue_free()
