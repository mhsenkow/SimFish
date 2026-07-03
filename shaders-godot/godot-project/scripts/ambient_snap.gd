class_name AmbientSnap
extends RefCounted

# PERFORMANCE_UNTHROTTLED #12 — one ambient snapshot per sim tick for bid sources.

var daylight: float = 1.0
var day_phase: float = 0.25
var dissolved_o2: float = 0.8
var tank_age_s: float = 0.0
var music_sweep: float = 0.0
var music_beat_phase: float = 0.0


static func capture(sim: Node) -> Dictionary:
	var snap: RefCounted = load("res://scripts/ambient_snap.gd").new()
	if sim == null:
		return snap.to_dict()
	if sim.has_method("daylight"):
		snap.daylight = float(sim.daylight())
	if sim.get("day_phase") != null:
		snap.day_phase = float(sim.day_phase)
	if sim.get("dissolved_o2") != null:
		snap.dissolved_o2 = float(sim.dissolved_o2)
	if sim.get("tank_age_s") != null:
		snap.tank_age_s = float(sim.tank_age_s)
	var mc: Node = null
	if sim is Node and (sim as Node).is_inside_tree():
		mc = (sim as Node).get_node_or_null("/root/MusicContext")
	if mc != null and mc.has_method("tank_ambient_scalar"):
		snap.music_sweep = float(mc.call("tank_ambient_scalar", "sweep"))
		snap.music_beat_phase = float(mc.call("tank_ambient_scalar", "beat_phase"))
	return snap.to_dict()


static func from_dict(d: Dictionary) -> RefCounted:
	var snap: RefCounted = load("res://scripts/ambient_snap.gd").new()
	snap.daylight = float(d.get("daylight", 1.0))
	snap.day_phase = float(d.get("day_phase", 0.25))
	snap.dissolved_o2 = float(d.get("dissolved_o2", 0.8))
	snap.tank_age_s = float(d.get("tank_age_s", 0.0))
	snap.music_sweep = float(d.get("music_sweep", 0.0))
	snap.music_beat_phase = float(d.get("music_beat_phase", 0.0))
	return snap


func to_dict() -> Dictionary:
	return {
		"daylight": daylight,
		"day_phase": day_phase,
		"dissolved_o2": dissolved_o2,
		"tank_age_s": tank_age_s,
		"music_sweep": music_sweep,
		"music_beat_phase": music_beat_phase,
	}
