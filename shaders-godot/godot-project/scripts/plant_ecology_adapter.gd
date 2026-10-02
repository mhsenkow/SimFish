extends RefCounted

const ECOLOGY_INTERVAL_S: float = 2.0
const MAX_BIOMASS: float = 512.0

var _host: WeakRef
var _ecology_t: float = 0.0


func _init(host: Node) -> void:
	_host = weakref(host)


func is_alive() -> bool:
	return _node() != null


# Holistic #141 — single authoritative biomass for visual mass + ecology.
# Prefer ecology_biomass(); fall back to biomass() for legacy hosts.
func biomass() -> float:
	var host: Node = _node()
	if host == null:
		return 0.0
	if host.has_method("ecology_biomass"):
		return clampf(float(host.call("ecology_biomass")), 0.0, MAX_BIOMASS)
	if host.has_method("biomass"):
		return clampf(float(host.call("biomass")), 0.0, MAX_BIOMASS)
	return 0.0


func nutrient_demand() -> float:
	var host: Node = _node()
	if host == null:
		return 0.0
	if host.has_method("ecology_nutrient_demand"):
		return clampf(float(host.call("ecology_nutrient_demand")), 0.0, 1.0)
	if host.get("nutrient_demand") != null:
		return clampf(float(host.get("nutrient_demand")), 0.0, 1.0)
	return 0.0


func tick(dt: float, substrate: SubstrateGrid, sim: Node = null) -> void:
	var host: Node = _node()
	if host == null or substrate == null:
		return
	_ecology_t += maxf(0.0, dt)
	if _ecology_t < ECOLOGY_INTERVAL_S:
		return
	var elapsed: float = _ecology_t
	_ecology_t = 0.0
	var demand: float = nutrient_demand() * biomass() * 0.001 * elapsed
	if demand > 0.0 and host is Node3D:
		# Floaters already draw the water-column nitrate pool in SimDriver;
		# do not also debit substrate roots (one budget, one sink).
		if host is FloatingPlant:
			return
		var taken: float = substrate.consume_root_uptake(
			host.get_instance_id(), (host as Node3D).global_position, demand)
		# Holistic #121 — name plant uptake on the most recent deposit chain.
		if taken > 0.0 and sim != null and sim.has_method("trace_food_web"):
			var chain_id: int = int(sim.get("_last_deposit_chain_id")) \
				if sim.get("_last_deposit_chain_id") != null else -1
			if chain_id > 0:
				sim.call("trace_food_web", chain_id, "plant_uptake", taken,
					host.get_class())


func graze(amount: int) -> int:
	var host: Node = _node()
	if host == null:
		return 0
	if host.has_method("ecology_graze"):
		return maxi(0, int(host.call("ecology_graze", maxi(0, amount))))
	if host.has_method("nibble"):
		return maxi(0, int(host.call("nibble", maxi(0, amount))))
	return 0


func die(substrate: SubstrateGrid) -> void:
	var host: Node = _node()
	if host == null:
		return
	var bm: float = biomass()
	if substrate != null and host is Node3D:
		substrate.deposit_litter_at(
			(host as Node3D).global_position, bm * 0.02)
	if host.has_method("ecology_die"):
		host.call("ecology_die")
	else:
		host.queue_free()


func _node() -> Node:
	if _host == null:
		return null
	var host: Variant = _host.get_ref()
	return host as Node if is_instance_valid(host) and host is Node else null
