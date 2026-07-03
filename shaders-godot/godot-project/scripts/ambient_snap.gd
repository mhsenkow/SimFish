class_name AmbientSnap
extends RefCounted

# PERFORMANCE_UNTHROTTLED #12 — one ambient snapshot per sim tick for bid sources.

var daylight: float = 1.0
var day_phase: float = 0.25
var dissolved_o2: float = 0.8
var tank_age_s: float = 0.0
var music_sweep: float = 0.0
var music_beat_phase: float = 0.0
var mind_cadence_hz: float = 15.0
var mind_idle_mult: float = 1.0


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
	var cfg: Node = null
	if sim is Node and (sim as Node).is_inside_tree():
		cfg = (sim as Node).get_node_or_null("/root/TankConfig")
	else:
		var ml: MainLoop = Engine.get_main_loop()
		if ml is SceneTree and (ml as SceneTree).root != null:
			cfg = (ml as SceneTree).root.get_node_or_null("/root/TankConfig")
	if cfg != null and cfg.get("mind_cadence_hz") != null:
		snap.mind_cadence_hz = maxf(0.0, float(cfg.mind_cadence_hz))
	if sim != null and sim.get("_room_idle_s") != null:
		var idle: float = float(sim._room_idle_s)
		snap.mind_idle_mult = 0.5 if idle >= 30.0 else 1.0
	return snap.to_dict()


static func from_dict(d: Dictionary) -> RefCounted:
	var snap: RefCounted = load("res://scripts/ambient_snap.gd").new()
	snap.daylight = float(d.get("daylight", 1.0))
	snap.day_phase = float(d.get("day_phase", 0.25))
	snap.dissolved_o2 = float(d.get("dissolved_o2", 0.8))
	snap.tank_age_s = float(d.get("tank_age_s", 0.0))
	snap.music_sweep = float(d.get("music_sweep", 0.0))
	snap.music_beat_phase = float(d.get("music_beat_phase", 0.0))
	snap.mind_cadence_hz = float(d.get("mind_cadence_hz", 15.0))
	snap.mind_idle_mult = float(d.get("mind_idle_mult", 1.0))
	return snap


func to_dict() -> Dictionary:
	return {
		"daylight": daylight,
		"day_phase": day_phase,
		"dissolved_o2": dissolved_o2,
		"tank_age_s": tank_age_s,
		"music_sweep": music_sweep,
		"music_beat_phase": music_beat_phase,
		"mind_cadence_hz": mind_cadence_hz,
		"mind_idle_mult": mind_idle_mult,
	}
