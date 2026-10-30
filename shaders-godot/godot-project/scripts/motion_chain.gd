class_name MotionChain
extends RefCounted

# An n-link follow-through chain (CREATURE_MOTION_700 #43): caudal fins, veils,
# barbels, feelers, antennae, tentacles. Each link springs toward its parent's
# absolute angle, so a swing at the root travels down the chain with a lag and
# rings out at the tip. Output is each link's angle RELATIVE to its parent,
# ready to write to a chain of pivots.
#
# Stiffness falls off toward the tip (falloff < 1 makes the tip floppier),
# which is what makes a veil billow while its base stays firm.

var links: int = 3
var _springs: Array[MotionSpring] = []
var _abs: PackedFloat32Array = PackedFloat32Array()
var _rel: PackedFloat32Array = PackedFloat32Array()


func _init(link_count: int = 3, tissue: String = "fin", falloff: float = 0.75) -> void:
	links = maxi(link_count, 1)
	var p: Array = MotionSpring.TISSUE.get(tissue, MotionSpring.TISSUE["fin"])
	for i in links:
		var f: float = float(p[0]) * pow(clampf(falloff, 0.2, 1.5), float(i))
		_springs.append(MotionSpring.new(f, float(p[1]), float(p[2])))
	_abs.resize(links)
	_rel.resize(links)


func reset(root_angle: float = 0.0) -> void:
	for i in links:
		_springs[i].reset(root_angle)
		_abs[i] = root_angle
		_rel[i] = 0.0


# root_angle: the absolute angle of whatever the chain hangs from (a pivot's
# yaw, a body bend). bias adds a static rest curl along the chain.
func step(dt: float, root_angle: float, bias: float = 0.0) -> PackedFloat32Array:
	var parent: float = root_angle
	for i in links:
		_abs[i] = _springs[i].step(dt, parent + bias)
		_rel[i] = _abs[i] - parent
		parent = _abs[i]
	return _rel


func tip_angle() -> float:
	return _abs[links - 1] if links > 0 else 0.0


func relative() -> PackedFloat32Array:
	return _rel
