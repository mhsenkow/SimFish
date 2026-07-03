class_name MindSimSnap
extends RefCounted

# PERFORMANCE_REALTIME #95 — sim scalars for worker-side cognition (no Node access).

var daylight: float = 1.0
var dissolved_o2: float = 0.8
var day_phase: float = 0.25
var total_plant_biomass: int = 0
var feed_anticipated: bool = false
var tank_society: Dictionary = {}


static func capture(sim: Node) -> Dictionary:
	var snap := MindSimSnap.new()
	if sim == null:
		return snap.to_dict()
	if sim.has_method("daylight"):
		snap.daylight = float(sim.daylight())
	if sim.get("dissolved_o2") != null:
		snap.dissolved_o2 = float(sim.dissolved_o2)
	if sim.get("day_phase") != null:
		snap.day_phase = float(sim.day_phase)
	if sim.get("total_plant_biomass") != null:
		snap.total_plant_biomass = int(sim.total_plant_biomass)
	if sim.has_method("feed_anticipation_active"):
		snap.feed_anticipated = bool(sim.feed_anticipation_active())
	if sim.has_method("tank_society_snapshot"):
		var ts: Variant = sim.tank_society_snapshot()
		if ts is Dictionary:
			snap.tank_society = (ts as Dictionary).duplicate(true)
	if sim.get("_ambient_snap") is Dictionary:
		var amb: Dictionary = sim._ambient_snap as Dictionary
		snap.daylight = float(amb.get("daylight", snap.daylight))
		snap.day_phase = float(amb.get("day_phase", snap.day_phase))
		snap.dissolved_o2 = float(amb.get("dissolved_o2", snap.dissolved_o2))
	return snap.to_dict()


static func from_dict(d: Dictionary) -> MindSimSnap:
	var snap := MindSimSnap.new()
	snap.daylight = float(d.get("daylight", 1.0))
	snap.dissolved_o2 = float(d.get("dissolved_o2", 0.8))
	snap.day_phase = float(d.get("day_phase", 0.25))
	snap.total_plant_biomass = int(d.get("total_plant_biomass", 0))
	snap.feed_anticipated = bool(d.get("feed_anticipated", false))
	var ts: Variant = d.get("tank_society", null)
	if ts is Dictionary:
		snap.tank_society = (ts as Dictionary).duplicate(true)
	return snap


func to_dict() -> Dictionary:
	return {
		"daylight": daylight,
		"dissolved_o2": dissolved_o2,
		"day_phase": day_phase,
		"total_plant_biomass": total_plant_biomass,
		"feed_anticipated": feed_anticipated,
		"tank_society": tank_society.duplicate(true),
	}


static func daylight_of(sim: Variant) -> float:
	if sim is MindSimSnap:
		return (sim as MindSimSnap).daylight
	if sim is Dictionary:
		return float(sim.get("daylight", 1.0))
	if sim is Node and sim.has_method("daylight"):
		return float(sim.daylight())
	return 1.0
