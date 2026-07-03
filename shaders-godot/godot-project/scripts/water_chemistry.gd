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


static func soft_ceil(v: float, cap: float) -> float:
	# REFINEMENT_II #58 — asymptotic ceiling so keeper actions still move the needle.
	v = maxf(0.0, v)
	if v <= cap:
		return v
	var over: float = v - cap
	return cap + over / (1.0 + over * 0.65)


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
# Plants v2 — biogenic carbonate chemistry (freshwater tanks).
var dissolved_co2: float = 0.42
var ph: float = 7.2
# Living-balance pass (H1) — carbonate + general hardness + toxic-NH3 fraction.
# kh (carbonate hardness) buffers the diel pH swing: soft water (low kh) swings
# hard, hard water stays flat. gh (general hardness / mineral pool) is slowly
# drawn down by plant uptake + snail shell building and is not replenished
# except by a water change — the gentle nudge behind "old tank syndrome".
# toxic_ammonia is the un-ionized NH3 fraction the fish actually feel; it rises
# sharply with pH, so the same ammonia reading is benign at pH 6.6 and lethal
# at pH 8.5.
var kh: float = 4.0
var gh: float = 6.0
var toxic_ammonia: float = 0.0
# Trace iron (#58): red / demanding plants draw iron down; it's not replenished
# except by dosing or a water change. Low iron mutes red coloration, so a
# red-plant Dutch tank needs richer substrate or dosing to hold its color.
var iron: float = 0.7

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
	dissolved_co2 = 0.48
	ph = 7.0
	kh = 4.0
	gh = 6.5
	iron = 0.7
	toxic_ammonia = 0.0
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
	dissolved_co2 = 0.28
	ph = 7.4
	kh = 4.0
	# Mature tanks have drawn down minerals — a little softer than a fresh fill.
	gh = 5.5
	iron = 0.55
	toxic_ammonia = 0.0
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
	# Saltwater is hard + heavily buffered.
	kh = 8.0
	gh = 10.0
	toxic_ammonia = 0.0
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
	# Mulm feeds the biofilter (#15): a detritus-rich Walstad soil hosts more
	# nitrifying bacteria, so a "dirty" planted tank cycles faster — exactly
	# why Walstad keepers don't vacuum the substrate.
	var mulm_boost: float = 0.0
	if sim != null and sim.substrate != null:
		mulm_boost = clampf(sim.substrate.total_above_baseline() / 20.0, 0.0, 1.0)
	bacteria_colony = clampf(
		bacteria_colony + dt * (0.0018 + biofilm * 0.004 + age_growth * 0.0006
			+ mulm_boost * 0.003),
		0.04, 1.0)
	var dl: float = float(sim.daylight()) if sim != null and sim.has_method("daylight") else 1.0
	if dl < 0.28:
		bacteria_colony = clampf(bacteria_colony + dt * 0.00032, 0.04, 1.0)
	# Bacteria die-back (#2): a starved biofilter slowly shrinks. When there's
	# essentially nothing to nitrify, the colony loses ground so a long-idle
	# tank gives a believable mini-cycle when it's re-stocked.
	if ammonia + nitrite < 0.04:
		bacteria_colony = maxf(0.04, bacteria_colony - dt * 0.0006)
	var bacteria: float = clampf(
		bacteria_colony * 0.75 + biofilm * 0.35 + 0.08, 0.05, 1.45)
	var plant_boost: float = clampf(float(plant_biomass) / 420.0, 0.0, 1.0)
	bacteria = clampf(bacteria + plant_boost * 0.22, 0.05, 1.35)
	if world != null and world.has_method("live_microfauna_count"):
		var micro_boost: float = clampf(float(world.live_microfauna_count()) / 90.0, 0.0, 0.20)
		bacteria = clampf(bacteria + micro_boost, 0.05, 1.55)
	# Temperature + O2 gating (#3, #4). Nitrifiers are warm-loving aerobes:
	# cold water slows them, and when dissolved O2 crashes they nearly stall,
	# so a hypoxia event causes a believable ammonia rebound.
	var warmth: float = 0.55
	if world != null and world.has_method("effective_warmth_at"):
		warmth = float(world.effective_warmth_at(Vector3.ZERO))
	var temp_act: float = clampf(0.45 + warmth * 0.95, 0.45, 1.4)
	var o2_now: float = sim.dissolved_o2 if sim != null else 0.7
	var o2_act: float = clampf(o2_now / 0.45, 0.22, 1.0)
	var nitri_act: float = temp_act * o2_act
	ammonia += waste_ammonia * dt
	ammonia += dt * 0.0014
	nitrate += pore_nitrate * dt
	var plant_uptake: float = clampf(float(plant_biomass) / 500.0, 0.0, 1.0)
	var plant_nh3_uptake: float = ammonia * plant_uptake * 0.38 * dt
	ammonia = maxf(0.0, ammonia - plant_nh3_uptake)
	var plant_no2_uptake: float = nitrite * plant_uptake * 0.16 * dt
	nitrite = maxf(0.0, nitrite - plant_no2_uptake)
	var nh3_to_no2: float = ammonia * bacteria * 0.32 * nitri_act * dt
	ammonia = maxf(0.0, ammonia - nh3_to_no2)
	nitrite += nh3_to_no2
	var no2_to_no3: float = nitrite * bacteria * 0.26 * nitri_act * dt
	nitrite = maxf(0.0, nitrite - no2_to_no3)
	nitrate += no2_to_no3
	# Old-tank nitrate creep (#8): part of the bioload mineralizes all the way
	# to nitrate over time. Only plant/floater uptake + substrate
	# denitrification take it back out, so a lightly-planted mature tank
	# slowly accrues nitrate — the nudge toward a water change.
	nitrate += waste_ammonia * 0.10 * dt
	nitrate = maxf(0.0, nitrate - plant_uptake * 0.052 * dt)
	# Denitrification (#5): anaerobic pockets deep in the substrate reduce
	# nitrate to N2 gas. Planted-soil tanks get a real nitrate sink the way a
	# deep Walstad soil bed does.
	if sim != null and sim.substrate != null \
			and sim.substrate.has_method("total_anaerobic"):
		var anaer: float = float(sim.substrate.total_anaerobic())
		nitrate = maxf(0.0, nitrate - clampf(anaer * 0.0006, 0.0, 0.004) * dt)
	nitrate = maxf(0.0, nitrate - dt * 0.0006)
	ammonia = soft_ceil(ammonia, 2.0)
	nitrite = soft_ceil(nitrite, 2.0)
	nitrate = soft_ceil(nitrate, 3.0)
	# General hardness slowly drawn down by plant uptake (#9). Not replenished
	# except by a water change; surfaces as soft-water drift over a long tank.
	gh = maxf(1.0, gh - clampf(float(plant_biomass) / 6000.0, 0.0, 0.0006) * dt)
	# Trace iron (#58): drawn down by planting (reds especially), trickle back
	# from substrate but slower than a heavy red tank consumes it.
	iron = clampf(
		iron - clampf(float(plant_biomass) / 5000.0, 0.0, 0.0007) * dt + dt * 0.00018,
		0.05, 1.0)
	# Blackwater chemical identity (#66): driftwood tannins acidify + soften the
	# water, so a tannin-stained biotope drifts to a low-KH, low-pH state that
	# swings more and reads distinctly on the water chip — not just brown.
	if world != null and world.get("tannins") != null:
		var tannin_amt: float = clampf(float(world.tannins), 0.0, 1.0)
		if tannin_amt > 0.05:
			var kh_target: float = lerpf(4.0, 1.2, tannin_amt)
			kh = lerpf(kh, kh_target, clampf(dt * 0.01, 0.0, 1.0))
	_tick_carbonate(dt, sim, plant_biomass)
	# Toxic (un-ionized) ammonia fraction (#6) — rises steeply with pH.
	var tox_frac: float = clampf(
		0.02 + pow(clampf((ph - 6.6) / 2.4, 0.0, 1.0), 1.6) * 0.92, 0.02, 0.95)
	toxic_ammonia = ammonia * tox_frac
	_update_phase(sim, plant_biomass, sim_day)


# Un-ionized NH3 the fish actually feel — what stress/death should read.
func toxic_ammonia_level() -> float:
	return toxic_ammonia


func iron_level() -> float:
	return iron


# Snails / shell-builders pull calcium carbonate out of the water column.
func draw_gh(amount: float) -> void:
	gh = maxf(0.5, gh - maxf(0.0, amount))


# Dissolving shells / molts slowly return calcium carbonate to the water (#19).
func add_gh(amount: float) -> void:
	gh = clampf(gh + maxf(0.0, amount), 0.5, 18.0)
	# Carbonate also lifts the buffer a touch.
	kh = clampf(kh + maxf(0.0, amount) * 0.4, 0.5, 12.0)


# Player water change — refresh minerals + dilute nitrate/organics.
func apply_water_change(fraction: float = 0.35) -> void:
	var f: float = clampf(fraction, 0.0, 0.9)
	nitrate = nitrate * (1.0 - f)
	ammonia = ammonia * (1.0 - f * 0.7)
	nitrite = nitrite * (1.0 - f * 0.7)
	gh = lerpf(gh, 7.0, f)
	kh = lerpf(kh, 4.0, f * 0.8)
	iron = lerpf(iron, 0.7, f)


func _tick_carbonate(dt: float, sim: SimDriver, plant_biomass: int) -> void:
	if sim == null:
		return
	var dl: float = sim.daylight() if sim.has_method("daylight") else 0.5
	var biomass_f: float = clampf(float(plant_biomass) / 420.0, 0.0, 1.2)
	var photo_draw: float = dl * biomass_f * 0.0018 * dt
	var night_resp: float = (1.0 - dl) * biomass_f * 0.0012 * dt
	dissolved_co2 = clampf(
		dissolved_co2 - photo_draw + night_resp + dt * 0.00025, 0.08, 0.95)
	var aeration_strip: float = sim.aeration_air_rate * 0.0016 * dt
	dissolved_co2 = maxf(0.08, dissolved_co2 - aeration_strip)
	var co2_target: float = lerpf(0.55, 0.22, dl)
	# pH buffering from dense floater mats (#30).
	var floater_cov: float = 0.0
	var w: Node = sim.get_parent() if sim != null else null
	if w != null and w.has_method("floater_coverage"):
		floater_cov = float(w.floater_coverage())
	var co2_damp: float = clampf(dt * 0.04 * (1.0 + floater_cov * 0.8), 0.0, 1.0)
	dissolved_co2 = lerpf(dissolved_co2, co2_target, co2_damp)
	# Carbonate-hardness buffering (#7). Soft water (low kh) swings hard around
	# the diel CO2 curve; hard water barely moves. We center on ~7.4 and scale
	# the CO2-driven swing by how soft the water is.
	var kh_damp: float = clampf(4.0 / maxf(1.0, kh), 0.45, 2.3)
	var swing: float = (0.42 - dissolved_co2) * 0.85 * kh_damp
	var ph_target: float = 7.4 + swing
	# Heavily-buffered water also resists fast pH movement.
	var ph_rate: float = clampf(dt * 0.06 * (4.0 / maxf(1.0, kh)), 0.0, 1.0)
	ph = lerpf(ph, ph_target, ph_rate)
	ph = clampf(ph, 6.0, 8.4)


func dissolved_co2_level() -> float:
	return dissolved_co2


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
	# Saltwater runs at high pH (~8.2), so most ammonia is the toxic form.
	toxic_ammonia = ammonia * 0.5
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
		"dissolved_co2": dissolved_co2,
		"ph": ph,
		"kh": kh,
		"gh": gh,
		"iron": iron,
		"toxic_ammonia": toxic_ammonia,
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
	dissolved_co2 = float(d.get("dissolved_co2", dissolved_co2))
	ph = float(d.get("ph", ph))
	kh = float(d.get("kh", kh))
	gh = float(d.get("gh", gh))
	iron = float(d.get("iron", iron))
	toxic_ammonia = float(d.get("toxic_ammonia", toxic_ammonia))
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
