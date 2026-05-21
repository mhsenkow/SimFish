# Logarithmic-spiral aquatic plant (nautilus-shell-style frond).
#
# Voxels are placed along a logarithmic spiral r = a * exp(b*theta) rising
# along Y as theta progresses. This is the same math as a nautilus shell
# or the curl of a fiddlehead fern - both real-world plants in similar
# environments. Visible mathematical structure: each voxel sits at a
# bigger radius AND a higher Y than the last, producing a 3D corkscrew
# that opens outward as it climbs.
#
# Parameters (set on construction, all heritable in a future evolution
# pass that targets non-fish lifeforms):
#   a            initial radius
#   b            spiral tightness; smaller = tighter coil
#   total_turns  how many radians to sweep (~3-5 visible coils)
#   y_per_turn   vertical rise per full revolution

extends Node3D
class_name NautilusPlant

const VOXEL_SIZE: float = 0.18

@export var a: float = 0.05
@export var b: float = 0.22
@export var total_turns: float = 3.5
@export var y_per_turn: float = 0.55

var _t: float = 0.0
var _phase: float = 0.0
var ramp: Array = []   # 5-color green ramp


func init_at(world_pos: Vector3, color_ramp: Array) -> void:
	global_position = world_pos
	ramp = color_ramp
	_phase = randf() * TAU
	_build()


func _build() -> void:
	# Step theta in fine increments so the spiral reads smoothly. Each
	# step plants a single voxel; sizes shrink slightly along the path
	# so the tip is finer than the base, matching how new growth on a
	# fern is smaller than the mature inner coils.
	var theta: float = 0.0
	var max_theta: float = total_turns * TAU
	var step: float = TAU / 14.0   # 14 voxels per revolution
	var i: int = 0
	while theta < max_theta:
		var r: float = a * exp(b * theta)
		var x: float = cos(theta) * r
		var z: float = sin(theta) * r
		var y: float = (theta / TAU) * y_per_turn
		var t_frac: float = theta / max_theta
		# Voxel scale tapers from base (1.0) to tip (0.55).
		var s: float = 0.55 + (1.0 - t_frac) * 0.45
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(VOXEL_SIZE * s, VOXEL_SIZE * s, VOXEL_SIZE * s)
		mi.mesh = bm
		mi.position = Vector3(x, y, z)
		var color: Color
		if ramp.size() >= 5:
			# Ramp index goes from base (dark) toward tip (bright).
			var idx: int = clampi(int(t_frac * float(ramp.size())), 0, ramp.size() - 1)
			color = ramp[idx]
		else:
			color = Color8(60, 130, 70)
		mi.material_override = _make_mat(color)
		add_child(mi)
		theta += step
		i += 1


func tick(dt: float) -> void:
	# Whole spiral gently bobs around its base. Each voxel inherits the
	# parent's transform so animating this transform animates everything.
	_t += dt
	rotation.z = sin(_t * 0.5 + _phase) * 0.05
	rotation.x = cos(_t * 0.45 + _phase * 1.2) * 0.04


func _make_mat(c: Color) -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
