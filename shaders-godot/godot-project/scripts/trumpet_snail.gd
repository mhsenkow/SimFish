# Malaysian trumpet snail.
#
# Burrowing snails (Melanoides tuberculata) that spend most of the day
# buried in the substrate and emerge at night to graze. Their tube-shaped
# shells stick up out of the gravel like tiny spirals when they're
# surface-active; during the day they're mostly hidden, with just a
# shell tip visible.
#
# Ecological role:
#  - Aerates substrate from below — slowly mixes nutrients in the
#    cells they pass through (a real benefit in Walstad / dirted tanks
#    where the floor can otherwise turn anaerobic).
#  - Eats settled detritus + decaying plant matter.
#  - Population caps tight + breeds slowly: real MTS can explode in
#    nutrient-rich tanks, but a controlled small colony is what most
#    aquarists want.
#
# Distinct from snail.gd (which crawls on glass): MTS sit on/in the
# substrate. They reuse Plant.gd's spot-on-substrate placement and
# tick at a slow cadence — purely visual + a small substrate.consume_at
# touch each tick to model the aeration.

class_name TrumpetSnail
extends Node3D


const SHELL_HEIGHT: float = 0.18
const SHELL_BASE_RADIUS: float = 0.05
const SHELL_SEGMENTS: int = 3
const SURFACE_EMERGE_DEPTH: float = 0.08
const BURIED_EMERGE_DEPTH: float = 0.22
const CRAWL_SPEED: float = 0.05
const REJITTER_INTERVAL_MIN: float = 4.0
const REJITTER_INTERVAL_MAX: float = 9.0
const LIFESPAN_S: float = 360.0


var sim: Node = null
var substrate_top_y: float = 0.0
var _age: float = 0.0
var _drift: Vector3 = Vector3.ZERO
var _next_jitter_t: float = 0.0
var _segments: Array[MeshInstance3D] = []
var _is_emerged: bool = false


func _ready() -> void:
	add_to_group("trumpet_snails")
	# Build a tapering spiral shell — three small voxel segments stacked
	# with diminishing size + a slight curl so the silhouette reads as
	# a tube snail rather than a stacked tower.
	var shell_palette: Array = [
		Color8(150, 122, 84),
		Color8(170, 142, 102),
		Color8(190, 162, 122),
	]
	for i in SHELL_SEGMENTS:
		var t: float = float(i) / float(maxi(1, SHELL_SEGMENTS - 1))
		var radius: float = lerpf(SHELL_BASE_RADIUS, SHELL_BASE_RADIUS * 0.35, t)
		var seg := MeshInstance3D.new()
		seg.mesh = VoxelMat.get_box(Vector3(radius * 2.0, SHELL_HEIGHT / SHELL_SEGMENTS, radius * 2.0))
		seg.material_override = VoxelMat.make_fauna(
			shell_palette[i % shell_palette.size()])
		# Slight curl to one side for the spiral look.
		seg.position = Vector3(
			sin(t * PI) * 0.012,
			(SHELL_HEIGHT / SHELL_SEGMENTS) * float(i) + (SHELL_HEIGHT / SHELL_SEGMENTS) * 0.5,
			0.0)
		add_child(seg)
		_segments.append(seg)
	_next_jitter_t = randf_range(REJITTER_INTERVAL_MIN, REJITTER_INTERVAL_MAX)
	_drift = Vector3(
		randf_range(-CRAWL_SPEED, CRAWL_SPEED),
		0.0,
		randf_range(-CRAWL_SPEED, CRAWL_SPEED))


func _process(dt: float) -> void:
	var sdt: float = dt
	if sim != null:
		sdt *= float(sim.time_scale)
		if sdt <= 0.0:
			return
	_age += sdt
	if _age >= LIFESPAN_S:
		queue_free()
		return

	# Emergence cycle — surface at night, bury during the day. Real MTS
	# is photophobic; coming out at night is the easy-to-read signal.
	var dl: float = 1.0
	if sim != null and sim.has_method("daylight"):
		dl = float(sim.daylight())
	_is_emerged = dl < 0.35
	var visible_depth: float = -SURFACE_EMERGE_DEPTH if _is_emerged else -BURIED_EMERGE_DEPTH
	# Lerp the shell Y toward the target depth so the surface/burrow
	# transition is smooth, not a teleport.
	position.y = lerpf(position.y, substrate_top_y + visible_depth, sdt * 0.6)

	# Slow crawl across substrate while emerged. Re-jitter direction
	# periodically so the snail doesn't head off the edge of the tank.
	if _is_emerged:
		position.x += _drift.x * sdt
		position.z += _drift.z * sdt
	_next_jitter_t -= sdt
	if _next_jitter_t <= 0.0:
		_next_jitter_t = randf_range(REJITTER_INTERVAL_MIN, REJITTER_INTERVAL_MAX)
		_drift = Vector3(
			randf_range(-CRAWL_SPEED, CRAWL_SPEED),
			0.0,
			randf_range(-CRAWL_SPEED, CRAWL_SPEED))

	# Substrate aeration: nudge the cell directly under the snail by a
	# tiny diffusion event. Doesn't consume nutrients — just lifts a
	# fraction toward the local average so the bed doesn't go stagnant.
	# Throttled per-snail so a colony doesn't overdrive the substrate.
	if sim != null and sim.substrate != null and randf() < sdt * 0.4:
		sim.substrate.add_at(global_position, 0.01)


func to_save_dict() -> Dictionary:
	return {
		"pos": SaveHelpers.vec3_to_array(global_position),
		"age": _age,
	}


func apply_save_dict(d: Dictionary) -> void:
	_age = float(d.get("age", 0.0))
