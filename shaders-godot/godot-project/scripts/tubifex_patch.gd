# Tubifex patch — visible red worm tangle on the substrate.
#
# Real Tubifex tubifex thrive in waters with high organic load, low O2,
# and elevated ammonia. They're the canary of a poorly-cycled tank: when
# you see a red patch, your tank chemistry is rough. As ammonia / nitrite
# drop back to safe, the patch dies off.
#
# Each patch is a tight bundle of 5–8 thin red voxels with a small
# wriggle phase. Visual proof that the player has a chemistry problem,
# and a food source for bottom-dwelling fish (cory, mudsifter, kuhli)
# who graze them down — closing the loop that returns excess substrate
# nitrogen to fish biomass.

class_name TubifexPatch
extends Node3D


const VOXEL_SIZE: float = 0.05
const LIFESPAN_MAX: float = 220.0
const WRIGGLE_FREQ: float = 5.5
const WRIGGLE_AMP: float = 0.024


var sim: Node = null
var substrate_top_y: float = 0.0
var _age: float = 0.0
var _phase: float = 0.0
var _worm_phases: Array[float] = []
var _worms: Array[MeshInstance3D] = []
# Patch dies off when local water chemistry returns to safe values OR
# when the patch is fully grazed by fish. world.gd polls this each
# maintenance cycle and queue_frees patches that report dead.
var _dead: bool = false


func _ready() -> void:
	_phase = randf() * TAU
	# 5–8 thin worms in a tight cluster. Each one has its own wriggle
	# phase + a tiny lateral position offset around the patch centre.
	var worm_count: int = randi_range(5, 8)
	var red_dark := Color8(145, 38, 32)
	var red_mid  := Color8(180, 58, 48)
	var red_light := Color8(210, 90, 70)
	var palette: Array[Color] = [red_dark, red_mid, red_light]
	for i in worm_count:
		var ang: float = randf() * TAU
		var r: float = randf_range(0.0, 0.18)
		var px: float = cos(ang) * r
		var pz: float = sin(ang) * r
		# Worm is a small vertical stack of 2 thin voxels — head + body.
		# Vertical so the worm "stands up" from the substrate like real
		# tubifex feeding from buried tube heads.
		var mi := MeshInstance3D.new()
		mi.mesh = VoxelMat.get_box(Vector3(
			VOXEL_SIZE * 0.7, VOXEL_SIZE * 1.6, VOXEL_SIZE * 0.7))
		mi.material_override = VoxelMat.make_fauna(palette[i % palette.size()])
		mi.position = Vector3(px, VOXEL_SIZE * 0.7, pz)
		add_child(mi)
		_worms.append(mi)
		_worm_phases.append(randf() * TAU)


func _process(dt: float) -> void:
	if _dead:
		return
	var sdt: float = dt
	if sim != null:
		sdt *= float(sim.time_scale)
		if sdt <= 0.0:
			return
	_age += sdt
	_phase += sdt * WRIGGLE_FREQ
	# Wave-like wriggle per worm — each one tilts on a slightly different
	# phase so the patch reads as a writhing tangle, not a stamped grid.
	for i in _worms.size():
		var w: MeshInstance3D = _worms[i]
		if w == null or not is_instance_valid(w):
			continue
		var ph: float = _worm_phases[i] + _phase
		w.rotation.x = sin(ph) * WRIGGLE_AMP * 5.0
		w.rotation.z = cos(ph * 0.83) * WRIGGLE_AMP * 4.0
	# Old patches fade out. The death check itself is handled by
	# world.gd which polls ammonia + nitrite each maintenance cycle and
	# kills patches in cleaned-up zones.
	if _age >= LIFESPAN_MAX:
		_dead = true


# How appealing this patch is to a passing bottom-dweller. Used by the
# fish AI to bias toward dense patches when hungry. Higher = more worms
# still present (i.e. not grazed down yet).
func feed_value() -> int:
	var alive: int = 0
	for w in _worms:
		if w != null and is_instance_valid(w) and w.visible:
			alive += 1
	return alive


# Fish grazes one worm out of the patch — visible voxel disappears and
# the patch's feed_value drops. Patch self-kills when fully grazed.
func graze_one() -> bool:
	for i in _worms.size():
		var w: MeshInstance3D = _worms[i]
		if w != null and is_instance_valid(w) and w.visible:
			w.visible = false
			# If that was the last visible worm, mark the patch dead.
			var any_left: bool = false
			for u in _worms:
				if u != null and is_instance_valid(u) and u.visible:
					any_left = true
					break
			if not any_left:
				_dead = true
			return true
	return false


func is_dead() -> bool:
	return _dead


func mark_dead() -> void:
	_dead = true


# Save/load. Patches are transient (they come and go with chemistry),
# so we just persist position + age and let the maintenance loop
# rebuild the worm list on load.
func to_save_dict() -> Dictionary:
	return {
		"pos": SaveHelpers.vec3_to_array(global_position),
		"age": _age,
		"worm_count": _worms.size(),
	}


func apply_save_dict(d: Dictionary) -> void:
	_age = float(d.get("age", 0.0))
