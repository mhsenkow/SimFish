extends RefCounted

const ECOLOGY_INTERVAL_S: float = 2.0
const MAX_BIOMASS: float = 512.0

var _host: WeakRef
var _ecology_t: float = 0.0


func _init(host: Node) -> void:
	_host = weakref(host)


func is_alive() -> bool:
	return _node() != null


func biomass() -> float:
	var host: Node = _node()
	if host == null or not host.has_method("ecology_biomass"):
		return 0.0
	return clampf(float(host.call("ecology_biomass")), 0.0, MAX_BIOMASS)


func nutrient_demand() -> float:
	var host: Node = _node()
	if host == null or not host.has_method("ecology_nutrient_demand"):
		return 0.0
	return clampf(float(host.call("ecology_nutrient_demand")), 0.0, 1.0)


func tick(dt: float, substrate: SubstrateGrid) -> void:
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
		substrate.consume_root_uptake(
			host.get_instance_id(), (host as Node3D).global_position, demand)


func graze(amount: int) -> int:
	var host: Node = _node()
	if host == null or not host.has_method("ecology_graze"):
		return 0
	return maxi(0, int(host.call("ecology_graze", maxi(0, amount))))


func die(substrate: SubstrateGrid) -> void:
	var host: Node = _node()
	if host == null:
		return
	if substrate != null and host is Node3D:
		substrate.deposit_litter_at(
			(host as Node3D).global_position, biomass() * 0.02)
	if host.has_method("ecology_die"):
		host.call("ecology_die")
	else:
		host.queue_free()


func _node() -> Node:
	if _host == null:
		return null
	var host: Variant = _host.get_ref()
	return host as Node if is_instance_valid(host) and host is Node else null
