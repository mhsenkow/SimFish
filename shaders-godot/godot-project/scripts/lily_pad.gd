# Lily pad - radial surface plant.
#
# === Dynamic growth ===
# Now grows incrementally: starts as a small 4-voxel pad that expands over
# time by adding new phyllotaxis-arranged leaf voxels. The stem grows first
# (reaching from substrate to the surface), then the pad expands. Flower
# buds appear once the pad reaches maturity and open into the layered bloom.
# Mature pads can produce runner stems that spawn new pads nearby.
#
# Mathematical structure: Vogel's spiral / sunflower phyllotaxis for the pad
# voxels, with golden angle spacing for maximally even coverage.

extends Node3D
class_name LilyPad

const VOXEL_SIZE: float = 0.18

@export var pad_radius: float = 0.95
@export var pad_voxels: int = 28
@export var stem_y: float = 1.6

var _t: float = 0.0
var _phase: float = 0.0
var pad_top: Color = Color8(90, 145, 70)
var pad_bot: Color = Color8(45, 90, 50)
var has_flower: bool = false

# ---- Dynamic growth state ----
var _current_pad_voxels: int = 0
var _growth_timer: float = 0.0
var _growth_interval: float = 3.0
var _stem_built: bool = false
var _pad_voxel_nodes: Array[MeshInstance3D] = []
var _pad_voxel_meta: Array[Dictionary] = []
enum FlowerStage { NONE, BUD, OPENING, FULL, FADING }
var _flower_stage: int = FlowerStage.NONE
var _flower_timer: float = 0.0
var _flower_open_frac: float = 0.0
var _flower_nodes: Array[MeshInstance3D] = []
var _runner_timer: float = 0.0
var _has_run: bool = false

# ---- Motion state (#1–#10) ----
var _base_y: float = 0.0
var _spin_rate: float = 0.0
var _tilt: Vector2 = Vector2.ZERO
var _ripple_rock: float = 0.0
var _pad_offset: Vector3 = Vector3.ZERO
var _stem_node: MeshInstance3D = null
var _pad_motion: Node3D = null
var _flower_holder: Node3D = null
var _age_s: float = 0.0
var _shed_timer: float = 0.0

const GOLDEN_ANGLE: float = 2.39996322972865332


func init_at(world_pos: Vector3, base_y: float) -> void:
	global_position = Vector3(world_pos.x, world_pos.y, world_pos.z)
	_base_y = global_position.y
	stem_y = base_y
	_phase = randf() * TAU
	_spin_rate = randf_range(-0.025, 0.025)
	_pad_motion = Node3D.new()
	_pad_motion.name = "PadMotion"
	add_child(_pad_motion)
	_flower_holder = Node3D.new()
	_flower_holder.name = "FlowerHolder"
	_pad_motion.add_child(_flower_holder)
	_build_stem()
	for i in 4:
		_add_pad_voxel()


func _build_stem() -> void:
	if _stem_built:
		return
	_stem_built = true
	var stem_top_y: float = global_position.y - VOXEL_SIZE * 0.5
	var stem_h: float = stem_top_y - stem_y
	if stem_h > 0.0:
		var stem := MeshInstance3D.new()
		var stem_mesh := BoxMesh.new()
		stem_mesh.size = Vector3(VOXEL_SIZE * 0.45, stem_h, VOXEL_SIZE * 0.45)
		stem.mesh = stem_mesh
		stem.material_override = _make_mat(Color8(70, 90, 50), 0.04)
		stem.position = Vector3(0, -stem_h * 0.5, 0)
		add_child(stem)
		_stem_node = stem


func _add_pad_voxel() -> void:
	if _current_pad_voxels >= pad_voxels:
		return
	var i: int = _current_pad_voxels
	var t: float = float(i + 1) / float(pad_voxels)
	var r: float = sqrt(t) * pad_radius
	var theta: float = float(i) * GOLDEN_ANGLE
	var x: float = cos(theta) * r
	var z: float = sin(theta) * r
	var is_new: bool = (_current_pad_voxels > pad_voxels * 0.7)
	var top_color: Color = pad_top.lightened(0.1) if is_new else pad_top
	var top := MeshInstance3D.new()
	var top_mesh := BoxMesh.new()
	top_mesh.size = Vector3(VOXEL_SIZE * 1.5, VOXEL_SIZE * 0.45, VOXEL_SIZE * 1.5)
	top.mesh = top_mesh
	top.material_override = _make_mat(top_color, 0.10 if t < 0.55 else 0.07)
	top.position = Vector3(x, 0.0, z)
	_pad_motion.add_child(top)
	_pad_voxel_nodes.append(top)
	_pad_voxel_meta.append({
		"t": t, "phase": randf() * TAU, "base_y": 0.0,
		"is_edge": t > 0.55,
	})
	if t > 0.55:
		var under := MeshInstance3D.new()
		var under_mesh := BoxMesh.new()
		under_mesh.size = Vector3(VOXEL_SIZE * 1.3, VOXEL_SIZE * 0.20, VOXEL_SIZE * 1.3)
		under.mesh = under_mesh
		under.material_override = _make_mat(pad_bot, 0.05)
		under.position = Vector3(x, -VOXEL_SIZE * 0.3, z)
		_pad_motion.add_child(under)
	_current_pad_voxels += 1


func tick(dt: float) -> void:
	_t += dt
	_age_s += dt

	# Surface bob (#1).
	var bob: float = sin(_t * 0.45 + _phase) * 0.014
	position.y = _base_y + bob

	# Slow yaw drift (#2).
	rotation.y += dt * _spin_rate

	# Tilt with surface current (#3).
	var drift: Vector3 = _surface_drift_vec()
	if drift.length_squared() > 1e-6:
		var target_tilt := Vector2(drift.x, drift.z) * 0.18
		_tilt = _tilt.lerp(target_tilt, clampf(dt * 0.55, 0.0, 1.0))
	else:
		_tilt = _tilt.lerp(Vector2.ZERO, clampf(dt * 0.4, 0.0, 1.0))
	# Ripple rock from fish (#4) — springs back.
	if _ripple_rock > 1e-5:
		_ripple_rock = lerpf(_ripple_rock, 0.0, clampf(dt * 3.2, 0.0, 1.0))
	var rock: float = sin(_t * 1.35 + _phase) * _ripple_rock
	_pad_motion.rotation.x = _tilt.y * 0.12 + rock
	_pad_motion.rotation.z = -_tilt.x * 0.12 + rock * 0.55

	# Flexible stem — pad drifts laterally off anchor (#6).
	var spring_target: Vector3 = Vector3(_tilt.x * 0.05, 0.0, _tilt.y * 0.05)
	_pad_offset = _pad_offset.lerp(spring_target, clampf(dt * 1.6, 0.0, 1.0))
	_pad_motion.position = _pad_offset

	# Edge undulation (#5) + aging color (#9).
	for vi in _pad_voxel_nodes.size():
		var node: MeshInstance3D = _pad_voxel_nodes[vi]
		if not is_instance_valid(node):
			continue
		var meta: Dictionary = _pad_voxel_meta[vi]
		var edge: bool = bool(meta.get("is_edge", false))
		var wiggle: float = 0.0
		if edge:
			wiggle = sin(_t * 0.72 + float(meta.get("phase", 0.0))) * 0.006
		node.position.y = float(meta.get("base_y", 0.0)) + wiggle
		if _age_s > 90.0:
			var age_frac: float = clampf((_age_s - 90.0) / 240.0, 0.0, 1.0)
			var mat: ShaderMaterial = node.material_override as ShaderMaterial
			if mat != null:
				var aged: Color = pad_top.lerp(Color8(130, 145, 55), age_frac * 0.35)
				if edge:
					aged = aged.lerp(Color8(95, 75, 40), age_frac * 0.25)
				mat.set_shader_parameter("albedo", VoxelMat.boost_foliage_color(aged))

	# Dew / wet sheen on bob (#8).
	var sheen: float = 0.08 + absf(sin(_t * 0.6 + _phase)) * 0.06
	for node in _pad_voxel_nodes:
		if is_instance_valid(node):
			var mat: ShaderMaterial = node.material_override as ShaderMaterial
			if mat != null:
				mat.set_shader_parameter("color_vibrancy", 1.18 + sheen)

	_growth_timer += dt
	if _current_pad_voxels < pad_voxels and _growth_timer >= _growth_interval:
		_growth_timer = 0.0
		_add_pad_voxel()

	if _flower_stage == FlowerStage.NONE \
			and _current_pad_voxels >= int(pad_voxels * 0.7) \
			and randf() < 0.002:
		_begin_flower()
	_tick_flower(dt)

	if _current_pad_voxels >= pad_voxels:
		_runner_timer += dt
		if not _has_run and _runner_timer > 45.0 and randf() < 0.15:
			_has_run = true
			_try_propagate()

	# Occasional edge voxel shed on old pads (#9).
	if _current_pad_voxels > 10 and _age_s > 120.0:
		_shed_timer += dt
		if _shed_timer > 55.0 and randf() < 0.08:
			_shed_timer = 0.0
			_shed_edge_voxel()


func nudge_ripple(intensity: float = 1.0) -> void:
	_ripple_rock = clampf(_ripple_rock + intensity * 0.14, 0.0, 0.22)


func effective_shade_radius() -> float:
	if _current_pad_voxels < int(pad_voxels * 0.45):
		return 0.0
	return pad_radius * clampf(float(_current_pad_voxels) / float(pad_voxels), 0.35, 1.0)


func surface_rest_position() -> Vector3:
	return global_position + _pad_offset


func fry_shade_factor() -> float:
	return clampf(effective_shade_radius() / maxf(pad_radius, 0.01), 0.0, 1.0) * 0.55


func _surface_drift_vec() -> Vector3:
	var n: Node = get_parent()
	while n != null:
		if n.get("surface_drift_vec") != null:
			return n.surface_drift_vec
		n = n.get_parent()
	return Vector3.ZERO


func _shed_edge_voxel() -> void:
	if _pad_voxel_nodes.is_empty():
		return
	var idx: int = _pad_voxel_nodes.size() - 1
	while idx >= 0:
		if bool(_pad_voxel_meta[idx].get("is_edge", false)):
			var node: MeshInstance3D = _pad_voxel_nodes[idx]
			if is_instance_valid(node):
				node.queue_free()
			_pad_voxel_nodes.remove_at(idx)
			_pad_voxel_meta.remove_at(idx)
			_current_pad_voxels = _pad_voxel_nodes.size()
			return
		idx -= 1


func _find_world() -> Node:
	var n: Node = get_parent()
	while n != null:
		if n.has_method("light_penetration_at"):
			return n
		n = n.get_parent()
	return null


func _begin_flower() -> void:
	_flower_stage = FlowerStage.BUD
	_flower_timer = 0.0
	var bud := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(VOXEL_SIZE * 0.5, VOXEL_SIZE * 0.5, VOXEL_SIZE * 0.5)
	bud.mesh = bm
	bud.material_override = _make_mat(pad_top.darkened(0.1), 0.05)
	bud.position = Vector3(0, VOXEL_SIZE * 0.3, 0)
	_flower_holder.add_child(bud)
	_flower_nodes.append(bud)
	var sim_gate: Node = _find_sim_driver()
	if sim_gate != null and sim_gate.has_method("log_story_event"):
		sim_gate.log_story_event("A lily pad opened its bloom on the surface.")
	if sim_gate != null and sim_gate.has_method("emit_eco_event"):
		sim_gate.emit_eco_event("flora", "Lily pad flowering on the surface.", 1)
	var amb: Node = get_node_or_null("/root/AmbientAudio")
	if amb != null and amb.has_method("play_aquarium_event"):
		amb.play_aquarium_event("story", 0.55)


func _tick_flower(dt: float) -> void:
	if _flower_stage == FlowerStage.NONE:
		return
	_flower_timer += dt
	match _flower_stage:
		FlowerStage.BUD:
			if _flower_timer > 6.0:
				_flower_stage = FlowerStage.OPENING
				_flower_timer = 0.0
				_flower_open_frac = 0.0
				_build_flower_meshes()
		FlowerStage.OPENING:
			_flower_open_frac = clampf(_flower_timer / 5.0, 0.0, 1.0)
			_update_flower(_flower_open_frac)
			if _flower_timer > 5.0:
				_flower_stage = FlowerStage.FULL
				_flower_timer = 0.0
		FlowerStage.FULL:
			# Petal flutter (#10) — oscillate around the open pose, never accumulate.
			var flutter: float = sin(_t * 1.15 + _phase) * 0.011
			var n_petals: int = mini(6, _flower_nodes.size())
			for i in n_petals:
				var fn: Node3D = _flower_nodes[i]
				if not is_instance_valid(fn):
					continue
				var base_z: float = float(fn.get_meta("base_rot_z", 0.0))
				var base_x: float = float(fn.get_meta("base_rot_x", 0.0))
				var wobble: float = flutter * (0.75 + sin(_phase + float(i) * 0.85) * 0.25)
				fn.rotation.z = base_z + wobble
				fn.rotation.x = base_x + wobble * 0.4
			if _flower_timer > 30.0:
				_flower_stage = FlowerStage.FADING
				_flower_timer = 0.0
		FlowerStage.FADING:
			var fade: float = clampf(_flower_timer / 8.0, 0.0, 1.0)
			for fn in _flower_nodes:
				if is_instance_valid(fn):
					fn.scale = Vector3.ONE * (1.0 - fade * 0.4)
			if _flower_timer > 8.0:
				_clear_flower()
				_flower_stage = FlowerStage.NONE


func _build_flower_meshes() -> void:
	_clear_flower()
	var palette: Array[Color] = [
		Color8(245, 220, 220),
		Color8(255, 245, 220),
		Color8(245, 195, 100),
	]
	var n_petals: int = 6
	for i in n_petals:
		var f := MeshInstance3D.new()
		var petal_size: float = VOXEL_SIZE * (0.7 - float(i % 2) * 0.15)
		f.mesh = VoxelMat.get_box(Vector3(petal_size, VOXEL_SIZE * 0.2, petal_size * 0.8))
		var petal_color: Color = palette[0] if i % 2 == 0 else palette[1]
		f.material_override = _make_flower_mat(petal_color)
		_flower_holder.add_child(f)
		_flower_nodes.append(f)
	var center := MeshInstance3D.new()
	center.mesh = VoxelMat.get_box(Vector3(VOXEL_SIZE * 0.4, VOXEL_SIZE * 0.25, VOXEL_SIZE * 0.4))
	center.material_override = _make_flower_mat(palette[2])
	center.position = Vector3(0, VOXEL_SIZE * 0.4, 0)
	_flower_holder.add_child(center)
	_flower_nodes.append(center)
	_update_flower(0.0)


func _update_flower(open_frac: float) -> void:
	var n_petals: int = 6
	if _flower_nodes.size() < n_petals:
		return
	for i in n_petals:
		var angle: float = float(i) / float(n_petals) * TAU
		var petal_spread: float = open_frac * VOXEL_SIZE * 0.9
		var f: Node3D = _flower_nodes[i]
		if is_instance_valid(f):
			f.position = Vector3(
				cos(angle) * petal_spread,
				VOXEL_SIZE * 0.35,
				sin(angle) * petal_spread,
			)
			f.rotation.z = cos(angle) * open_frac * 0.3
			f.rotation.x = sin(angle) * open_frac * 0.3
			f.set_meta("base_rot_z", f.rotation.z)
			f.set_meta("base_rot_x", f.rotation.x)


func _clear_flower() -> void:
	for fn in _flower_nodes:
		if is_instance_valid(fn):
			fn.queue_free()
	_flower_nodes.clear()


func _try_propagate() -> void:
	var parent_node: Node = get_parent()
	if parent_node == null:
		return
	var new_pos: Vector3 = global_position
	var found: bool = false
	for _attempt in 6:
		var offset := Vector3(
			randf_range(-2.0, 2.0),
			0.0,
			randf_range(-2.0, 2.0),
		)
		var candidate: Vector3 = global_position + offset
		if _is_inside_tank_xz(candidate.x, candidate.z, 0.6):
			new_pos = candidate
			found = true
			break
	if not found:
		return
	_lay_runner_trail(global_position, new_pos, parent_node)
	var new_pad := LilyPad.new()
	parent_node.add_child(new_pad)
	new_pad.pad_radius = pad_radius * randf_range(0.75, 1.0)
	new_pad.pad_voxels = maxi(12, int(pad_voxels * randf_range(0.6, 0.9)))
	new_pad.init_at(new_pos, stem_y)


func _lay_runner_trail(a: Vector3, b: Vector3, parent_node: Node) -> void:
	var segs: int = clampi(int(round((b - a).length() / 0.4)), 4, 8)
	var runner_color := Color8(60, 90, 45)
	for i in segs:
		var t: float = float(i + 1) / float(segs + 1)
		var p: Vector3 = a.lerp(b, t)
		p.y = a.y - 0.02
		p.x += sin(t * PI * 1.5) * 0.06
		p.z += cos(t * PI * 1.3) * 0.06
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 0.05, 0.12)
		mi.mesh = bm
		mi.material_override = VoxelMat.make_foliage(runner_color)
		mi.position = p
		parent_node.add_child(mi)


func _is_inside_tank_xz(x: float, z: float, margin: float) -> bool:
	var n: Node = get_parent()
	while n != null:
		if n.has_method("_is_inside_tank"):
			return n._is_inside_tank(x, z, margin)
		n = n.get_parent()
	return true


func _make_flower_mat(c: Color) -> Material:
	return VoxelMat.make_flower_foliage(c)


func _make_mat(c: Color, sway: float = 0.08) -> Material:
	var m: ShaderMaterial = VoxelMat.make_foliage(c).duplicate() as ShaderMaterial
	m.set_shader_parameter("sway_amplitude", sway)
	m.set_shader_parameter("sway_speed", 0.9 + randf() * 0.4)
	m.set_shader_parameter("flutter_amplitude", sway * 0.35)
	return m


func _find_sim_driver() -> Node:
	var p: Node = get_parent()
	while p != null:
		var s: Node = p.get_node_or_null("SimDriver")
		if s != null:
			return s
		p = p.get_parent()
	return null
