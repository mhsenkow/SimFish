# Logarithmic-spiral aquatic plant (nautilus-shell-style frond).
#
# === Dynamic growth ===
# Now grows incrementally: the spiral extends by adding new voxels at the
# tip over time, rather than building the full coil at spawn. New voxels
# at the growing tip are slightly brighter and larger (new growth effect).
# The mature inner coils darken as they age.
#
# Voxels are placed along a logarithmic spiral r = a * exp(b*theta) rising
# along Y as theta progresses. This is the same math as a nautilus shell
# or the curl of a fiddlehead fern.
#
# Parameters:
#   a            initial radius
#   b            spiral tightness; smaller = tighter coil
#   total_turns  how many radians to sweep (~3-5 visible coils)
#   y_per_turn   vertical rise per full revolution

extends Node3D
class_name NautilusPlant

const VOXEL_SIZE: float = 0.18

@export var a: float = 0.04
@export var b: float = 0.11
@export var total_turns: float = 3.2
@export var y_per_turn: float = 0.75

var _t: float = 0.0
var _phase: float = 0.0
var ramp: Array = []   # 5-color green ramp

# ---- Dynamic growth state ----
var _current_theta: float = 0.0
var _max_theta: float = 0.0
var _step: float = 0.0
var _growth_timer: float = 0.0
var _growth_interval: float = 2.2   # seconds per voxel (was 1.5 — gentler GPU load)
var _all_voxels: Array[MeshInstance3D] = []
var _voxel_birth_times: Array[float] = []  # for aging color shift


func init_at(world_pos: Vector3, color_ramp: Array) -> void:
	global_position = world_pos
	ramp = color_ramp
	_phase = randf() * TAU
	_max_theta = total_turns * TAU
	_step = TAU / 14.0   # 14 voxels per revolution
	_current_theta = 0.0
	# Start with a few initial voxels so it's not invisible at spawn.
	for i in 4:
		_add_spiral_voxel()


func _add_spiral_voxel() -> void:
	if _current_theta >= _max_theta:
		return
	var theta: float = _current_theta
	var r: float = a * exp(b * theta)
	var x: float = cos(theta) * r
	var z: float = sin(theta) * r
	var y: float = (theta / TAU) * y_per_turn
	var t_frac: float = theta / _max_theta
	# Voxel scale tapers from base (1.0) to tip (0.55).
	# But NEW growth at the tip is slightly larger (unfurling frond effect).
	var is_tip: bool = (_max_theta - theta) < _step * 3.0
	var s: float = 0.55 + (1.0 - t_frac) * 0.45
	if is_tip:
		s *= 1.15  # new growth slightly bigger
	var mi := MeshInstance3D.new()
	# Reuse the shared unit box mesh + scale — unique BoxMesh per voxel was
	# triggering GPU fence timeouts on macOS when several spirals grew.
	mi.mesh = VoxelMat.get_box(Vector3(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE))
	mi.scale = Vector3(s, s, s)
	mi.position = Vector3(x, y, z)
	var color: Color
	if ramp.size() >= 5:
		# New growth at the tip is brighter (higher ramp index).
		var ramp_t: float = t_frac
		if is_tip:
			ramp_t = minf(ramp_t + 0.2, 1.0)  # shift brighter
		var idx: int = clampi(int(ramp_t * float(ramp.size())), 0, ramp.size() - 1)
		color = ramp[idx]
		if is_tip:
			color = color.lightened(0.12)
	else:
		color = Color8(60, 130, 70)
	mi.material_override = VoxelMat.make_foliage(color)
	mi.set_meta("base_color", color)
	mi.set_meta("aged", false)
	add_child(mi)
	_all_voxels.append(mi)
	_voxel_birth_times.append(_t)
	_current_theta += _step


func tick(dt: float) -> void:
	_t += dt

	# ---- Incremental spiral growth ----
	_growth_timer += dt
	if _current_theta < _max_theta and _growth_timer >= _growth_interval:
		_growth_timer = 0.0
		_add_spiral_voxel()
		# Age older voxels: darken slightly over time for visual depth.
		_age_voxels()


func _age_voxels() -> void:
	# Older inner-coil voxels gradually darken, making the growth front
	# visually pop against the mature interior.
	if ramp.size() < 5:
		return
	for i in _all_voxels.size():
		if not is_instance_valid(_all_voxels[i]):
			continue
		if _all_voxels[i].get_meta("aged", false):
			continue
		var age: float = _t - _voxel_birth_times[i]
		if age > 5.0:
			var darken: float = clampf((age - 5.0) / 5.0, 0.0, 0.15)
			var base_col: Color = _all_voxels[i].get_meta("base_color", Color.WHITE)
			_all_voxels[i].material_override = VoxelMat.make_foliage(base_col.darkened(darken * 0.15))
			_all_voxels[i].set_meta("aged", true)


func _make_mat(c: Color) -> Material:
	return VoxelMat.make_foliage(c)
