# A snail egg sac. Sits on the glass for ~60 sim seconds, then hatches into
# a baby snail. Visible as a small pale-yellow cluster.

extends Node3D

@export var wall_normal: Vector3 = Vector3.RIGHT
@export var wall_min: Vector3 = Vector3.ZERO
@export var wall_max: Vector3 = Vector3.ZERO

# Inherited from parent snail at lay time. Defaults are the founder values
# for any snail that's not actually a child (e.g. test spawning).
@export var inherited_shell_color: Color = Color8(135, 44, 176)
@export var inherited_shell_size: float = 1.0
@export var inherited_generation: int = 0
@export var inherited_shell_shape: String = "turbo"
@export var inherited_parent_lineage: String = "Founders"
@export var inherited_parent_keys: Array = []

const HATCH_TIME: float = 60.0

var _age: float = 0.0
# Latch so _hatch() only ever runs once. _process keeps firing between when we
# call queue_free() and when the node actually leaves the tree (deferred to end
# of frame). Without this guard each sac spawned 2-3 baby snails before
# disappearing — the populations exploded.
var _hatched: bool = false


# ---- Save / load ----

func to_save_dict() -> Dictionary:
	return {
		"pos": SaveHelpers.vec3_to_array(global_position),
		"wall_normal": SaveHelpers.vec3_to_array(wall_normal),
		"wall_min": SaveHelpers.vec3_to_array(wall_min),
		"wall_max": SaveHelpers.vec3_to_array(wall_max),
		"inherited_shell_color": SaveHelpers.color_to_array(inherited_shell_color),
		"inherited_shell_size": inherited_shell_size,
		"inherited_generation": inherited_generation,
		"age": _age,
	}


func apply_save_dict(d: Dictionary) -> void:
	wall_normal = SaveHelpers.array_to_vec3(d.get("wall_normal", []), wall_normal)
	wall_min = SaveHelpers.array_to_vec3(d.get("wall_min", []), wall_min)
	wall_max = SaveHelpers.array_to_vec3(d.get("wall_max", []), wall_max)
	inherited_shell_color = SaveHelpers.array_to_color(d.get("inherited_shell_color", []), inherited_shell_color)
	inherited_shell_size = float(d.get("inherited_shell_size", inherited_shell_size))
	inherited_generation = int(d.get("inherited_generation", 0))
	_age = float(d.get("age", 0.0))


func _ready() -> void:
	_build_visual()


func _build_visual() -> void:
	# Smaller, less obtrusive sac than before - just 2 tiny voxels so the
	# tank doesn't get visually polluted with pending eggs.
	var c := Color8(235, 220, 170)
	var c2 := Color8(215, 200, 150)
	var positions: Array[Vector3] = [
		Vector3(0, 0, 0),
		Vector3(0.04, 0.02, 0),
	]
	for i in positions.size():
		var mi := MeshInstance3D.new()
		mi.mesh = VoxelMat.get_box(Vector3(0.06, 0.06, 0.06))
		mi.position = positions[i]
		mi.material_override = VoxelMat.make(c if (i & 1) == 0 else c2)
		add_child(mi)


func _process(dt: float) -> void:
	if _hatched:
		return
	# Honor sim.time_scale so pause/fast-forward affect egg incubation the
	# same way they affect snail / shrimp / fish lifecycles. Without this,
	# eggs continued ticking while everything else paused.
	var sim := _get_sim()
	if sim != null:
		dt *= float(sim.time_scale)
		if dt <= 0.0:
			return
	_age += dt
	if _age >= HATCH_TIME:
		_hatch()


# Walk up the scene tree to find a SimDriver. Cached on first hit.
var _sim_driver_ref: Node = null

func _get_sim() -> Node:
	if _sim_driver_ref != null and is_instance_valid(_sim_driver_ref):
		return _sim_driver_ref
	var n: Node = get_parent()
	while n != null:
		var d := n.get_node_or_null("SimDriver")
		if d != null:
			_sim_driver_ref = d
			return d
		n = n.get_parent()
	return null


func _hatch() -> void:
	# Latch immediately so re-entry from a subsequent _process tick (between
	# queue_free and actual node removal) is a no-op.
	if _hatched:
		return
	_hatched = true
	# Spawn a baby snail on the same wall with the inherited shell genome.
	var parent := get_parent()
	if parent == null:
		queue_free()
		return
	var baby := Node3D.new()
	baby.set_script(load("res://scripts/snail.gd"))
	parent.add_child(baby)
	baby.position = position
	baby.set("wall_normal", wall_normal)
	baby.set("wall_min", wall_min)
	baby.set("wall_max", wall_max)
	baby.set("is_baby", true)
	baby.set("shell_color", inherited_shell_color)
	baby.set("shell_size", inherited_shell_size)
	baby.set("generation", inherited_generation)
	baby.set("shell_shape", inherited_shell_shape)
	baby.set("parent_lineage", inherited_parent_lineage)
	baby.set("_parent_keys", inherited_parent_keys.duplicate())
	if baby.has_method("_ensure_named"):
		baby._ensure_named()
	# Build the baby's body using the inherited shell color + size.
	_build_baby_body(baby, inherited_shell_color, inherited_shell_size)
	var sim := _get_sim()
	if sim != null and sim.has_method("register_snail"):
		sim.register_snail(baby)
	queue_free()


func _build_baby_body(snail: Node3D, shell_color: Color, shell_size: float) -> void:
	# Mirror world.gd's _build_snail_body but with the heritable shell color
	# + size scaling each voxel by shell_size. Bigger shells = bigger snail.
	var shell_dark := shell_color.darkened(0.22)
	var body := Color8(44, 31, 21)
	var shell_mat := VoxelMat.make(shell_color)
	var shell_dark_mat := VoxelMat.make(shell_dark)
	var body_mat := VoxelMat.make(body)
	for i in 4:
		var ang: float = i * 0.7
		var r: float = (0.05 + i * 0.06) * shell_size
		var sp := Vector3(cos(ang) * r, sin(ang) * r, 0.0)
		var s: float = (0.16 - i * 0.02) * shell_size
		var mat: Material = shell_mat if (i & 1) == 0 else shell_dark_mat
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(s, s, s)
		mi.mesh = bm
		mi.position = sp
		mi.material_override = mat
		snail.add_child(mi)
	# Foot scales with shell.
	var foot := MeshInstance3D.new()
	var foot_bm := BoxMesh.new()
	foot_bm.size = Vector3(0.24 * shell_size, 0.06 * shell_size, 0.16 * shell_size)
	foot.mesh = foot_bm
	foot.position = Vector3(0, -0.12 * shell_size, 0)
	foot.material_override = body_mat
	snail.add_child(foot)
