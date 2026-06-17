# Surface floater ecology scaling extracted from world.gd.
class_name WorldFloaterManager
extends RefCounted

const ESTABLISHED_SPAWN: int = 14
const CYCLE_SPAWN_MIN: int = 4
const CYCLE_SPAWN_MAX: int = 6
const CYCLE_DUCKWEED_CAP: int = 12


static func ecology_mode(sim: Node) -> String:
	if sim == null:
		return "established"
	if sim.has_method("hud_ecology_mode"):
		return String(sim.hud_ecology_mode())
	return "established"


static func shape_capacity_multiplier(shape: String) -> float:
	match shape:
		"sphere":
			return 0.68
		"cylinder":
			return 0.82
		"triangle":
			return 0.78
		"hex":
			return 0.88
		_:
			return 1.0


static func scaled_surface_capacity(base_capacity: int, shape: String) -> int:
	return maxi(4, int(round(float(base_capacity) * shape_capacity_multiplier(shape))))


static func initial_spawn_count(sim: Node, bloom: float = 0.0, shape: String = "box") -> int:
	var mode: String = ecology_mode(sim)
	var n: int = ESTABLISHED_SPAWN
	if mode == "cycle":
		n = randi_range(CYCLE_SPAWN_MIN, CYCLE_SPAWN_MAX)
		n = maxi(3, n - int(round(clampf(bloom, 0.0, 1.0) * 2.0)))
	return maxi(2, int(round(float(n) * shape_capacity_multiplier(shape))))


static func duckweed_cap(sim: Node, surface_capacity: int) -> int:
	var cap: int = surface_capacity
	if ecology_mode(sim) == "cycle":
		cap = mini(CYCLE_DUCKWEED_CAP, surface_capacity)
	# Azolla colonies can pack tighter; duckweed mats use full surface cap.
	return cap


static func morph_spread_bias(morph: String) -> float:
	match morph:
		"duckweed", "azolla":
			return 1.18
		"water_hyacinth":
			return 0.75
		_:
			return 1.0


static func flora_coverage_sublabel(coverage: float) -> String:
	if coverage > 0.15:
		return " · floaters %d%%" % int(round(coverage * 100.0))
	return ""
