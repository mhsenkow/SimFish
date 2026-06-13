# Lite nitrogen cycle for Walstad-style tank progression.
class_name WaterChemistry
extends RefCounted

enum CyclePhase {
	NEW_TANK,
	AMMONIA_SPIKE,
	NITRITE_SPIKE,
	CYCLING,
	ESTABLISHED,
}

const SIM_DAY_S: float = 864.0

var ammonia: float = 0.0
var nitrite: float = 0.0
var nitrate: float = 0.0
var cycle_phase: int = CyclePhase.NEW_TANK
# Nitrifier colony strength 0..1 — grows independently of visible biofilm so
# a planted tank can still show a believable ammonia phase before bacteria win.
var bacteria_colony: float = 0.08
# Reef proxy chemistry — not a full Ca/alk sim; drives coral growth + HUD.
var alkalinity_proxy: float = 8.0
var reef_nutrients: float = 0.35

var _logged_ammonia: bool = false
var _logged_reef_stress: bool = false
var _logged_nitrite: bool = false
var _logged_established: bool = false
var _logged_cycling: bool = false


func apply_fresh_start() -> void:
	ammonia = 0.12
	nitrite = 0.02
	nitrate = 0.04
	bacteria_colony = 0.06
	cycle_phase = CyclePhase.NEW_TANK
	_logged_ammonia = false
	_logged_nitrite = false
	_logged_established = false
	_logged_cycling = false


func apply_established_start() -> void:
	ammonia = 0.02
	nitrite = 0.01
	nitrate = 0.14
	bacteria_colony = 0.82
	alkalinity_proxy = 8.2
	reef_nutrients = 0.42
	cycle_phase = CyclePhase.ESTABLISHED
	_logged_ammonia = true
	_logged_nitrite = true
	_logged_established = true
	_logged_cycling = true


func apply_reef_start() -> void:
	ammonia = 0.01
	nitrite = 0.005
	nitrate = 0.06
	bacteria_colony = 0.55
	alkalinity_proxy = 8.0
	reef_nutrients = 0.38
	cycle_phase = CyclePhase.ESTABLISHED
	_logged_ammonia = true
	_logged_nitrite = true
	_logged_established = true
	_logged_cycling = true
	_logged_reef_stress = false


func tick(dt: float, sim: SimDriver, world: Node, plant_biomass: int,
		waste_ammonia: float, pore_nitrate: float = 0.0,
		is_saltwater: bool = false) -> void:
	if is_saltwater:
		_tick_reef(dt, sim, world, plant_biomass, waste_ammonia)
		return
	var biofilm: float = 0.0
	if world != null and world.get("biofilm_progress") != null:
		biofilm = clampf(float(world.biofilm_progress), 0.0, 1.0)
	# Bacteria colony grows with biofilm + time + detritivore activity.
	var tank_age: float = sim.tank_age_s if sim != null else 0.0
	var sim_day: float = tank_age / SIM_DAY_S
	var age_growth: float = clampf(sim_day / 21.0, 0.0, 1.0) * 0.55
	bacteria_colony = clampf(
		bacteria_colony + dt * (0.0018 + biofilm * 0.004 + age_growth * 0.0006),
		0.04, 1.0)
	var bacteria: float = clampf(
		bacteria_colony * 0.75 + biofilm * 0.35 + 0.08, 0.05, 1.45)
	var plant_boost: float = clampf(float(plant_biomass) / 420.0, 0.0, 1.0)
	bacteria = clampf(bacteria + plant_boost * 0.22, 0.05, 1.35)
	if world != null and world.has_method("live_microfauna_count"):
		var micro_boost: float = clampf(float(world.live_microfauna_count()) / 90.0, 0.0, 0.20)
		bacteria = clampf(bacteria + micro_boost, 0.05, 1.55)
	ammonia += waste_ammonia * dt
	ammonia += dt * 0.0014
	nitrate += pore_nitrate * dt
	var plant_uptake: float = clampf(float(plant_biomass) / 500.0, 0.0, 1.0)
	var plant_nh3_uptake: float = ammonia * plant_uptake * 0.38 * dt
	ammonia = maxf(0.0, ammonia - plant_nh3_uptake)
	var plant_no2_uptake: float = nitrite * plant_uptake * 0.16 * dt
	nitrite = maxf(0.0, nitrite - plant_no2_uptake)
	var nh3_to_no2: float = ammonia * bacteria * 0.32 * dt
	ammonia = maxf(0.0, ammonia - nh3_to_no2)
	nitrite += nh3_to_no2
	var no2_to_no3: float = nitrite * bacteria * 0.26 * dt
	nitrite = maxf(0.0, nitrite - no2_to_no3)
	nitrate += no2_to_no3
	nitrate = maxf(0.0, nitrate - plant_uptake * 0.052 * dt)
	nitrate = maxf(0.0, nitrate - dt * 0.0010)
	ammonia = clampf(ammonia, 0.0, 2.0)
	nitrite = clampf(nitrite, 0.0, 2.0)
	nitrate = clampf(nitrate, 0.0, 3.0)
	_update_phase(sim, plant_biomass, sim_day)


func _tick_reef(dt: float, sim: SimDriver, world: Node, plant_biomass: int,
		waste_ammonia: float) -> void:
	# Saltwater: damp NH₃/NO₂ drama; track alk + nutrients for coral instead.
	ammonia += waste_ammonia * dt * 0.35
	ammonia += dt * 0.0004
	ammonia = maxf(0.0, ammonia - dt * 0.008)
	nitrite = maxf(0.0, nitrite - dt * 0.006)
	nitrate = maxf(0.0, nitrate - dt * 0.002)
	ammonia = clampf(ammonia, 0.0, 0.35)
	nitrite = clampf(nitrite, 0.0, 0.18)
	nitrate = clampf(nitrate, 0.0, 0.45)
	var uptake: float = clampf(float(plant_biomass) / 380.0, 0.0, 1.0)
	reef_nutrients = clampf(
		reef_nutrients + dt * (0.0012 + waste_ammonia * 0.08) - uptake * 0.0016,
		0.08, 1.0)
	var warmth: float = 0.55
	if sim != null:
		var cfg := sim.get_node_or_null("/root/TankConfig")
		if cfg != null and cfg.get("light_warmth") != null:
			warmth = float(cfg.light_warmth)
		if world != null and world.has_method("effective_warmth_at"):
			warmth = float(world.effective_warmth_at(Vector3.ZERO))
	var alk_target: float = 8.0 - clampf((warmth - 0.72) * 2.5, 0.0, 1.2)
	alkalinity_proxy = lerpf(alkalinity_proxy, alk_target, clampf(dt * 0.04, 0.0, 1.0))
	alkalinity_proxy = clampf(alkalinity_proxy, 6.5, 9.5)
	cycle_phase = CyclePhase.ESTABLISHED
	if sim == null:
		return
	if alkalinity_proxy < 7.2 and not _logged_reef_stress:
		_logged_reef_stress = true
		sim.emit_eco_event("reef", "Reef alkalinity dipping — corals may stress.", 2)


func _update_phase(sim: SimDriver, plant_biomass: int, sim_day: float) -> void:
	if ammonia < 0.05 and nitrite < 0.05 and nitrate < 0.45 \
			and bacteria_colony > 0.55 and sim_day > 2.5 \
			and plant_biomass > 80:
		cycle_phase = CyclePhase.ESTABLISHED
	elif nitrite > 0.22 and sim_day > 0.35 and bacteria_colony > 0.12:
		cycle_phase = CyclePhase.NITRITE_SPIKE
	elif ammonia > 0.16 and sim_day > 0.08:
		cycle_phase = CyclePhase.AMMONIA_SPIKE
	elif sim_day > 0.05 or bacteria_colony > 0.15:
		cycle_phase = CyclePhase.CYCLING
	else:
		cycle_phase = CyclePhase.NEW_TANK
	if sim == null:
		return
	var day_n: int = maxi(1, int(sim_day) + 1)
	if cycle_phase == CyclePhase.AMMONIA_SPIKE and not _logged_ammonia:
		_logged_ammonia = true
		sim.emit_eco_event("cycle", "Day %d: ammonia rising — bacteria colony forming." % day_n, 2)
	if cycle_phase == CyclePhase.NITRITE_SPIKE and not _logged_nitrite:
		_logged_nitrite = true
		sim.emit_eco_event("cycle", "Day %d: nitrite spike — keep plants growing." % day_n, 2)
	if cycle_phase == CyclePhase.CYCLING and not _logged_cycling and sim_day > 0.4:
		_logged_cycling = true
		sim.emit_eco_event("cycle", "Day %d: tank cycling — biofilter waking up." % day_n, 1)
	if cycle_phase == CyclePhase.ESTABLISHED and not _logged_established:
		_logged_established = true
		sim.emit_eco_event("cycle", "Day %d: tank cycled — biofilter online." % day_n, 1)


static func phase_label(phase: int) -> String:
	match phase:
		CyclePhase.NEW_TANK:
			return "setting up"
		CyclePhase.AMMONIA_SPIKE:
			return "ammonia spike"
		CyclePhase.NITRITE_SPIKE:
			return "nitrites"
		CyclePhase.CYCLING:
			return "cycling"
		CyclePhase.ESTABLISHED:
			return "cycled"
	return "cycling"


static func phase_banner(phase: int, sim_day: float) -> String:
	var day_n: int = maxi(1, int(sim_day) + 1)
	match phase:
		CyclePhase.NEW_TANK:
			return "Day %d: new tank — soil leaching, plants rooting" % day_n
		CyclePhase.AMMONIA_SPIKE:
			return "Day %d: ammonia spike — normal for a fresh Walstad start" % day_n
		CyclePhase.NITRITE_SPIKE:
			return "Day %d: nitrite spike — bacteria catching up" % day_n
		CyclePhase.CYCLING:
			return "Day %d: cycling — watch O₂ and plant growth" % day_n
		CyclePhase.ESTABLISHED:
			return ""
	return ""


static func hud_mode(phase: int, sim_day: float, saltwater: bool = false) -> String:
	if saltwater:
		return "reef"
	if phase >= CyclePhase.ESTABLISHED or sim_day >= 14.0:
		return "established"
	if sim_day >= 5.0 or phase >= CyclePhase.CYCLING:
		return "growth"
	return "cycle"


static func reef_phase_label() -> String:
	return "reef stable"


func to_save_dict() -> Dictionary:
	return {
		"ammonia": ammonia,
		"nitrite": nitrite,
		"nitrate": nitrate,
		"cycle_phase": cycle_phase,
		"bacteria_colony": bacteria_colony,
		"alkalinity_proxy": alkalinity_proxy,
		"reef_nutrients": reef_nutrients,
		"logged_ammonia": _logged_ammonia,
		"logged_nitrite": _logged_nitrite,
		"logged_established": _logged_established,
		"logged_cycling": _logged_cycling,
		"logged_reef_stress": _logged_reef_stress,
	}


func apply_save_dict(d: Dictionary, version: int) -> void:
	if d.is_empty() and version < 3:
		apply_established_start()
		return
	ammonia = float(d.get("ammonia", ammonia))
	nitrite = float(d.get("nitrite", nitrite))
	nitrate = float(d.get("nitrate", nitrate))
	cycle_phase = int(d.get("cycle_phase", cycle_phase))
	bacteria_colony = float(d.get("bacteria_colony", bacteria_colony))
	alkalinity_proxy = float(d.get("alkalinity_proxy", alkalinity_proxy))
	reef_nutrients = float(d.get("reef_nutrients", reef_nutrients))
	_logged_reef_stress = not not d.get("logged_reef_stress", _logged_reef_stress)
	if version < 3 and not d.has("bacteria_colony"):
		match cycle_phase:
			CyclePhase.ESTABLISHED:
				bacteria_colony = 0.82
			CyclePhase.NITRITE_SPIKE, CyclePhase.CYCLING:
				bacteria_colony = 0.35
			CyclePhase.AMMONIA_SPIKE:
				bacteria_colony = 0.12
			_:
				bacteria_colony = 0.08
	_logged_ammonia = not not d.get("logged_ammonia", _logged_ammonia)
	_logged_nitrite = not not d.get("logged_nitrite", _logged_nitrite)
	_logged_established = not not d.get("logged_established", _logged_established)
	_logged_cycling = not not d.get("logged_cycling", _logged_cycling)
