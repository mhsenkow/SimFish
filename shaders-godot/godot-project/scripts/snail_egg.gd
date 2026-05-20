# A snail egg sac. Sits on the glass for ~60 sim seconds, then hatches into
# a baby snail. Visible as a small pale-yellow cluster.

extends Node3D

@export var wall_normal: Vector3 = Vector3.RIGHT
@export var wall_min: Vector3 = Vector3.ZERO
@export var wall_max: Vector3 = Vector3.ZERO

const HATCH_TIME: float = 60.0

var _age: float = 0.0


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
		var bm := BoxMesh.new()
		bm.size = Vector3(0.04, 0.04, 0.04)
		mi.mesh = bm
		mi.position = positions[i]
		mi.material_override = VoxelMat.make(c if (i & 1) == 0 else c2)
		add_child(mi)


func _process(dt: float) -> void:
	_age += dt
	if _age >= HATCH_TIME:
		_hatch()


func _hatch() -> void:
	# Spawn a baby snail on the same wall, at this position.
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
	# Manually build the baby's body since snail.gd doesn't auto-build.
	_build_baby_body(baby)
	queue_free()


func _build_baby_body(snail: Node3D) -> void:
	# Mirror the body-building logic from world.gd's _build_snail_body so the
	# new baby snail has visible geometry.
	var shell := Color8(135, 44, 176)
	var shell_dark := Color8(135, 44, 176).darkened(0.2)
	var body := Color8(44, 31, 21)
	var shell_mat := VoxelMat.make(shell)
	var shell_dark_mat := VoxelMat.make(shell_dark)
	var body_mat := VoxelMat.make(body)
	for i in 4:
		var ang: float = i * 0.7
		var r: float = 0.05 + i * 0.06
		var sp := Vector3(cos(ang) * r, sin(ang) * r, 0.0)
		var s: float = 0.16 - i * 0.02
		var mat: Material = shell_mat if (i & 1) == 0 else shell_dark_mat
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(s, s, s)
		mi.mesh = bm
		mi.position = sp
		mi.material_override = mat
		snail.add_child(mi)
	# Foot.
	var foot := MeshInstance3D.new()
	var foot_bm := BoxMesh.new()
	foot_bm.size = Vector3(0.24, 0.06, 0.16)
	foot.mesh = foot_bm
	foot.position = Vector3(0, -0.12, 0)
	foot.material_override = body_mat
	snail.add_child(foot)
