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
	var support: float = forage_support(sim)
	for f in fish_arr:
		if not is_instance_valid(f) or f.get("_dying") == true:
			continue
		f._drive_soa_integrated = true
		f.hunger = clampf(float(f.hunger) + hunger_rate, 0.0, 1.0)
		var burst: float = float(f.get("burst_remaining") if f.get("burst_remaining") != null else 0.0)
		var drain: float = energy_drain + (BURST_ENERGY_PER_S * dt if burst > 0.0 else 0.0)
		f.energy = clampf(float(f.energy) - drain, 0.0, 1.0)
		apply_forage_and_reserves(f, dt, support)


# Shared with Fish.tick's non-SoA fallback.
#
# Natural forage: a planted, oxygenated tank feeds its fish on biofilm,
# microfauna and detritus - the base of a Walstad food web. It used to lower
# hunger only (and only when O2 > 0.72), so an unfed Walstad tank's fish felt
# sated while energy drained to zero: the auto-feeder (sized from hunger)
# stayed quiet, adults sat at "Needs rest", and the template went extinct in
# about ten minutes even at real time. Forage now carries energy, converting
# like food (FOOD_HUNGER_DELTA : FOOD_ENERGY_DELTA = 2 : 1), and is shared:
# the tank's carrying capacity is literally how many fish it can feed, so
# past capacity each fish gets less and the population settles instead of
# booming and crashing. Full support slightly exceeds the resting drain
# (0.004-0.006/s) so a tank at capacity keeps adults in breeding condition;
# bursts, spawning and growth still need real meals.
#
# Reserves: a fish whose energy is low is hungry no matter what it last ate,
# so it goes looking for food and the feeder counts it. The target sits above
# the breeding gate (0.45-0.65 energy): at 0.6, fish stopped eating right
# where breeding needs them to be, and adults idled at "Needs rest".
const FORAGE_ENERGY_PER_S: float = 0.0075
# Extra drain while darting. It was 0.04/s: fish burst ~20% of the day (dart
# species, startles, courtship), which alone cost twice the resting
# metabolism, so adults never regained breeding condition even when fed.
const BURST_ENERGY_PER_S: float = 0.015
const FORAGE_MIN_BIOMASS: float = 280.0
const FORAGE_MIN_O2: float = 0.45
const RESERVE_HUNGER_ENERGY: float = 0.8


# 0..1 share of a fish's resting metabolism the tank's own food web covers.
static func forage_support(sim: Node) -> float:
	if sim == null or sim.get("dissolved_o2") == null or sim.get("total_plant_biomass") == null:
		return 0.0
	if float(sim.dissolved_o2) < FORAGE_MIN_O2 \
			or float(sim.total_plant_biomass) < FORAGE_MIN_BIOMASS:
		return 0.0
	var fish_n: int = (sim.get("fish") as Array).size() if sim.get("fish") is Array else 0
	if fish_n <= 0 or not sim.has_method("fish_carrying_capacity_smoothed"):
		return 1.0
	return clampf(float(sim.fish_carrying_capacity_smoothed()) / float(fish_n), 0.0, 1.0)


static func apply_forage_and_reserves(f, dt: float, support: float) -> void:
	if support > 0.0:
		var gain: float = dt * FORAGE_ENERGY_PER_S * support
		f.energy = minf(1.0, float(f.energy) + gain)
		f.hunger = maxf(0.0, float(f.hunger) - gain * 2.0)
	var reserve_hunger: float = clampf(
		(RESERVE_HUNGER_ENERGY - float(f.energy)) * 1.2, 0.0, 0.9)
	f.hunger = maxf(float(f.hunger), reserve_hunger)


static func clear_flags(fish_arr: Array) -> void:
	for f in fish_arr:
		if is_instance_valid(f):
			f._drive_soa_integrated = false
