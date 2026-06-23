# Surface floater ecology scaling extracted from world.gd.
class_name WorldFloaterManager
extends RefCounted

const ESTABLISHED_SPAWN: int = 8
const CYCLE_SPAWN_MIN: int = 4
const CYCLE_SPAWN_MAX: int = 6
const CYCLE_DUCKWEED_CAP: int = 12
# Established tanks: cap clump *count* well below surface slots. Each node is a
# visible mat patch; hundreds of tiny duckweed clumps tank perf without filling
# the surface any faster than ~80 patches would.
const ESTABLISHED_ACTIVE_CAP_FRAC: float = 0.24
const ESTABLISHED_ACTIVE_CAP_MAX: int = 96
const ESTABLISHED_ACTIVE_CAP_MIN: int = 18
# Stop natural propagation once the weighted mat reaches this coverage.
const PROPAGATION_COVERAGE_MAX: float = 0.58


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
	if ecology_mode(sim) == "cycle":
		return mini(CYCLE_DUCKWEED_CAP, surface_capacity)
	return clampi(
		int(round(float(surface_capacity) * ESTABLISHED_ACTIVE_CAP_FRAC)),
		ESTABLISHED_ACTIVE_CAP_MIN,
		mini(ESTABLISHED_ACTIVE_CAP_MAX, surface_capacity))


static func morph_spread_bias(morph: String) -> float:
	match morph:
		"duckweed", "azolla":
			return 0.92
		"water_hyacinth":
			return 0.75
		_:
			return 1.0


static func flora_coverage_sublabel(coverage: float) -> String:
	if coverage > 0.15:
		return " · floaters %d%%" % int(round(coverage * 100.0))
	return ""
