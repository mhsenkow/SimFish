# Mycelium patch — pale white fungal filaments that emerge on decaying
# organic matter (dead fish corpses + driftwood lesions). The visible
# white fuzz that real aquariums get when something dies and isn't
# cleaned up quickly. Shrimp + snails graze them down over time.
#
# Visual: 4–7 thin white voxel filaments fanning radially from a
# centerpoint, with a slight droop. They grow over the first 15 sim
# seconds to full size, then slowly retract as they're consumed.
#
# Ecological role:
#   - Spawns when a fish dies + isn't eaten quickly
#   - Indicates "the cleanup crew can't keep up" or "ammonia spike from
#     decomposition incoming"
#   - Grazed by shrimp (high preference) — closes the decay loop
#   - Self-dissolves after MAX_AGE if nothing eats them

class_name MyceliumPatch
extends Node3D


const VOXEL_SIZE: float = 0.035
const FILAMENT_COUNT_MIN: int = 4
const FILAMENT_COUNT_MAX: int = 7
const GROW_DURATION_S: float = 15.0
const MAX_AGE_S: float = 110.0
const WAVE_FREQ: float = 1.8
const WAVE_AMP: float = 0.05


var sim: Node = null
var _age: float = 0.0
var _phase: float = 0.0
var _filaments: Array[MeshInstance3D] = []
var _filament_base_lengths: Array[float] = []
var _filament_target_y: Array[float] = []
var _dead: bool = false


func _ready() -> void:
	_phase = randf() * TAU
	var count: int = randi_range(FILAMENT_COUNT_MIN, FILAMENT_COUNT_MAX)
	var palette: Array[Color] = [
		Color8(245, 240, 230),
		Color8(232, 226, 215),
		Color8(252, 248, 240),
	]
	for i in count:
		var ang: float = float(i) / float(count) * TAU + randf_range(-0.2, 0.2)
		var lean: float = randf_range(0.18, 0.32)   # how far from vertical
		var height: float = randf_range(VOXEL_SIZE * 4.0, VOXEL_SIZE * 7.0)
		var mi := MeshInstance3D.new()
		mi.mesh = VoxelMat.get_box(Vector3(
			VOXEL_SIZE * 0.45, height, VOXEL_SIZE * 0.45))
		mi.material_override = VoxelMat.make_fauna(
			palette[i % palette.size()])
		# Position fans radially from the centerpoint; bottom of the
		# filament sits at y=0 (the spawn surface).
		var px: float = cos(ang) * VOXEL_SIZE * 0.5 * (1.0 + lean * 2.0)
		var pz: float = sin(ang) * VOXEL_SIZE * 0.5 * (1.0 + lean * 2.0)
		mi.position = Vector3(px, height * 0.5, pz)
		# Tilt outward so the filament leans away from center.
		mi.rotation = Vector3(lean * sin(ang), 0.0, -lean * cos(ang))
		# Start small — they grow over GROW_DURATION_S.
		mi.scale = Vector3(0.1, 0.1, 0.1)
		add_child(mi)
		_filaments.append(mi)
		_filament_base_lengths.append(height)
		_filament_target_y.append(height * 0.5)


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
	# Grow factor: 0..1 over the first GROW_DURATION_S seconds, then
	# starts shrinking back toward zero over the rest of MAX_AGE_S.
	var grow_factor: float
	if _age < GROW_DURATION_S:
		grow_factor = _age / GROW_DURATION_S
	else:
		var remaining: float = clampf(
			(MAX_AGE_S - _age) / (MAX_AGE_S - GROW_DURATION_S), 0.0, 1.0)
		grow_factor = 0.85 + 0.15 * remaining   # taper from 1.0 down
	for i in _filaments.size():
		var f: MeshInstance3D = _filaments[i]
		if f == null or not is_instance_valid(f):
			continue
		# Subtle sway in water currents.
		var sway: float = sin(_phase + float(i) * 0.7) * WAVE_AMP
		f.rotation.x = sway
		# Apply grow factor uniformly.
		var s: float = clampf(grow_factor, 0.1, 1.0)
		f.scale = Vector3(s, s, s)
	# Natural senescence — when fully aged, fade out.
	if _age >= MAX_AGE_S:
		_dead = true


# Called by shrimp / snail brain when they reach the patch and graze.
# Pops one filament; if none left, mark dead.
func graze_one() -> bool:
	for i in _filaments.size():
		var f: MeshInstance3D = _filaments[i]
		if f != null and is_instance_valid(f) and f.visible:
			f.visible = false
			var any_alive: bool = false
			for u in _filaments:
				if u != null and is_instance_valid(u) and u.visible:
					any_alive = true
					break
			if not any_alive:
				_dead = true
			return true
	return false


func is_dead() -> bool:
	return _dead


func mark_dead() -> void:
	_dead = true


func to_save_dict() -> Dictionary:
	return {
		"pos": SaveHelpers.vec3_to_array(global_position),
		"age": _age,
	}


func apply_save_dict(d: Dictionary) -> void:
	_age = float(d.get("age", 0.0))
