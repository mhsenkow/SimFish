class_name MindDriveSoA
extends RefCounted

# PERFORMANCE_UNTHROTTLED #51 — column-major hunger/energy/stress integration.

static func integrate_fish(fish_arr: Array, dt: float, sim: Node) -> void:
	if fish_arr.is_empty() or dt <= 0.0:
		return
	var dl: float = 0.75
	if sim != null and sim.has_method("daylight"):
		dl = clampf(float(sim.daylight()), 0.0, 1.0)
	var hunger_rate: float = dt * lerpf(0.006, 0.009, 1.0 - dl)
	var energy_drain: float = dt * (0.004 + lerpf(0.0, 0.002, 1.0 - dl))
	var walstad_bonus: bool = false
	if sim != null and sim.get("dissolved_o2") != null and sim.get("total_plant_biomass") != null:
		walstad_bonus = float(sim.dissolved_o2) > 0.72 and float(sim.total_plant_biomass) > 280.0
	for f in fish_arr:
		if not is_instance_valid(f) or f.get("_dying") == true:
			continue
		f._drive_soa_integrated = true
		f.hunger = clampf(float(f.hunger) + hunger_rate, 0.0, 1.0)
		if walstad_bonus:
			f.hunger = maxf(0.0, float(f.hunger) - dt * 0.0018)
		var burst: float = float(f.get("burst_remaining") if f.get("burst_remaining") != null else 0.0)
		var drain: float = energy_drain + (0.04 * dt if burst > 0.0 else 0.0)
		f.energy = clampf(float(f.energy) - drain, 0.0, 1.0)


static func clear_flags(fish_arr: Array) -> void:
	for f in fish_arr:
		if is_instance_valid(f):
			f._drive_soa_integrated = false
