# Biofilm patch — pale slime on hardscape (driftwood + rocks).
#
# Distinct from:
#   - The driftwood biofilm shader tint (world.gd's _apply_biofilm_tints),
#     which is a static color shift on the wood voxels themselves.
#   - Algae (algae.gd), which is green and substrate-borne.
#
# These are PHYSICAL voxel patches anchored to hardscape that grow over
# time and get grazed down by snails + shrimp. Real planted-tank biofilm
# is one of the most under-appreciated food sources for the cleanup crew
# — it's where most of the substrate carbon turnover actually happens.
#
# Visual: a small lattice of 4–6 thin pale voxels (slight yellow-white)
# sitting just above the hardscape surface. Slow micro-sway. Despawns
# when fully grazed or after MAX_AGE.

class_name BiofilmPatch
extends Node3D


const VOXEL_SIZE: float = 0.05
const SHEET_COUNT_MIN: int = 4
const SHEET_COUNT_MAX: int = 6
const MAX_AGE_S: float = 240.0
const WAVE_FREQ: float = 0.9
const WAVE_AMP: float = 0.025


var sim: Node = null
var _age: float = 0.0
var _phase: float = 0.0
var _sheets: Array[MeshInstance3D] = []
var _dead: bool = false


func _ready() -> void:
	add_to_group("biofilm_patches")
	_phase = randf() * TAU
	var count: int = randi_range(SHEET_COUNT_MIN, SHEET_COUNT_MAX)
	# Pale palette — biofilm in real tanks is off-white with a hint of
	# yellow or pink depending on the bacterial / archaeal species mix.
	var palette: Array[Color] = [
		Color8(238, 232, 218),
		Color8(225, 220, 200),
		Color8(232, 225, 210),
	]
	for i in count:
		var ang: float = float(i) / float(count) * TAU + randf_range(-0.18, 0.18)
		var radius: float = randf_range(VOXEL_SIZE * 0.4, VOXEL_SIZE * 1.1)
		var mi := MeshInstance3D.new()
		# Flat sheet-like shape — wider than tall — anchored just above
		# the hardscape surface.
		mi.mesh = VoxelMat.get_box(Vector3(
			VOXEL_SIZE * 0.5,
			VOXEL_SIZE * 0.15,
			VOXEL_SIZE * 0.5))
		mi.material_override = VoxelMat.make_fauna(
			palette[i % palette.size()])
		mi.position = Vector3(
			cos(ang) * radius,
			VOXEL_SIZE * 0.08,
			sin(ang) * radius)
		add_child(mi)
		_sheets.append(mi)


func _process(dt: float) -> void:
	if _dead:
		return
	var sdt: float = dt
	if sim != null:
		sdt *= float(sim.time_scale)
		if sdt <= 0.0:
			return
	_age += sdt
	_phase += sdt * WAVE_FREQ
	# Tiny lateral sway in current flow.
	for i in _sheets.size():
		var s: MeshInstance3D = _sheets[i]
		if s == null or not is_instance_valid(s):
			continue
		s.rotation.z = sin(_phase + float(i) * 0.7) * WAVE_AMP
	if _age >= MAX_AGE_S:
		_dead = true


# Reduce one sheet from the patch. Called by grazing shrimp / snails.
# Returns true if a sheet was actually removed.
func graze_one() -> bool:
	for i in _sheets.size():
		var s: MeshInstance3D = _sheets[i]
		if s != null and is_instance_valid(s) and s.visible:
			s.visible = false
			var any_left: bool = false
			for u in _sheets:
				if u != null and is_instance_valid(u) and u.visible:
					any_left = true
					break
			if not any_left:
				_dead = true
			return true
	return false


# How much food is left in this patch — used by the grazer AI as a
# tie-breaker between nearby patches.
func food_value() -> int:
	var n: int = 0
	for s in _sheets:
		if s != null and is_instance_valid(s) and s.visible:
			n += 1
	return n


func is_dead() -> bool:
	return _dead


func mark_dead() -> void:
	_dead = true


func to_save_dict() -> Dictionary:
	return {
		"pos": SaveHelpers.vec3_to_array(global_position),
		"age": _age,
		"sheet_count": _sheets.size(),
	}


func apply_save_dict(d: Dictionary) -> void:
	_age = float(d.get("age", 0.0))
