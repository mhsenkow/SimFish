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

var _logged_ammonia: bool = false
var _logged_nitrite: bool = false
var _logged_established: bool = false


func tick(dt: float, sim: SimDriver, world: Node, plant_biomass: int,
		waste_ammonia: float) -> void:
	var biofilm: float = 0.0
	if world != null and world.get("biofilm_progress") != null:
		biofilm = clampf(float(world.biofilm_progress), 0.0, 1.0)
	var bacteria: float = clampf(biofilm * 0.6 + 0.15, 0.05, 1.0)
	# Planted Walstad tanks cycle faster — roots + biofilm host nitrifiers.
	var plant_boost: float = clampf(float(plant_biomass) / 420.0, 0.0, 1.0)
	bacteria = clampf(bacteria + plant_boost * 0.35, 0.05, 1.35)
	# Microfauna boost: a dense swarm of paramecia, copepods, and rotifers
	# represents an active microbial loop. Their grazing on free bacteria
	# keeps the colony young and reproducing (counter-intuitive but real —
	# steady cropping prevents senescence). Caps at +20% so the swarm
	# can't outrun the biofilm / plant bonuses.
	if world != null and world.has_method("live_microfauna_count"):
		var micro_boost: float = clampf(float(world.live_microfauna_count()) / 90.0, 0.0, 0.20)
		bacteria = clampf(bacteria + micro_boost, 0.05, 1.55)
	ammonia += waste_ammonia * dt
	ammonia += dt * 0.0016
	# Plants assimilate dissolved N directly from the water column. Real
	# planted tanks prefer ammonium (NH4+) over nitrate by ~5× because
	# assimilating NO3 costs extra energy to reduce — this is exactly why
	# a heavily planted Walstad tank can "skip" the visible ammonia phase
	# of a cycle. Plants race the bacteria to the NH3 and usually win.
	var plant_uptake: float = clampf(float(plant_biomass) / 500.0, 0.0, 1.0)
	var plant_nh3_uptake: float = ammonia * plant_uptake * 0.42 * dt
	ammonia = maxf(0.0, ammonia - plant_nh3_uptake)
	var plant_no2_uptake: float = nitrite * plant_uptake * 0.18 * dt
	nitrite = maxf(0.0, nitrite - plant_no2_uptake)
	var nh3_to_no2: float = ammonia * bacteria * 0.35 * dt
	ammonia = maxf(0.0, ammonia - nh3_to_no2)
	nitrite += nh3_to_no2
	var no2_to_no3: float = nitrite * bacteria * 0.28 * dt
	nitrite = maxf(0.0, nitrite - no2_to_no3)
	nitrate += no2_to_no3
	nitrate = maxf(0.0, nitrate - plant_uptake * 0.055 * dt)
	nitrate = maxf(0.0, nitrate - dt * 0.0012)
	ammonia = clampf(ammonia, 0.0, 2.0)
	nitrite = clampf(nitrite, 0.0, 2.0)
	nitrate = clampf(nitrate, 0.0, 3.0)
	_update_phase(sim, plant_biomass)


func _update_phase(sim: SimDriver, plant_biomass: int) -> void:
	var runtime: float = sim.elapsed_runtime_s if sim != null else 0.0
	var sim_day: float = runtime / SIM_DAY_S
	if ammonia < 0.05 and nitrite < 0.05 and plant_biomass > 120:
		cycle_phase = CyclePhase.ESTABLISHED
	elif nitrite > 0.25 and sim_day > 0.5:
		cycle_phase = CyclePhase.NITRITE_SPIKE
	elif ammonia > 0.2 and sim_day > 0.15:
		cycle_phase = CyclePhase.AMMONIA_SPIKE
	elif runtime > 60.0:
		cycle_phase = CyclePhase.CYCLING
	else:
		cycle_phase = CyclePhase.NEW_TANK
	if sim == null:
		return
	if cycle_phase == CyclePhase.AMMONIA_SPIKE and not _logged_ammonia:
		_logged_ammonia = true
		sim.log_story_event("Cycle: ammonia rising — bacteria colony forming.")
	if cycle_phase == CyclePhase.NITRITE_SPIKE and not _logged_nitrite:
		_logged_nitrite = true
		sim.log_story_event("Cycle: nitrite spike — keep plants growing.")
	if cycle_phase == CyclePhase.ESTABLISHED and not _logged_established:
		_logged_established = true
		sim.log_story_event("Tank cycled — biofilter online.")


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


func to_save_dict() -> Dictionary:
	return {
		"ammonia": ammonia,
		"nitrite": nitrite,
		"nitrate": nitrate,
		"cycle_phase": cycle_phase,
	}


func apply_save_dict(d: Dictionary, version: int) -> void:
	if d.is_empty() and version < 2:
		ammonia = 0.02
		nitrite = 0.01
		nitrate = 0.08
		cycle_phase = CyclePhase.ESTABLISHED
		return
	ammonia = float(d.get("ammonia", ammonia))
	nitrite = float(d.get("nitrite", nitrite))
	nitrate = float(d.get("nitrate", nitrate))
	cycle_phase = int(d.get("cycle_phase", cycle_phase))
