extends SceneTree

# SENTIENCE_THE_NIGHT_WATCH — TankMind, sleep, away-life smoke.
# Anti-Truman (#54): away gap uses TankMind.tick_coarse(away=true), same rules as live tick.

const NightWatch = preload("res://scripts/night_watch.gd")
const TankMind = preload("res://scripts/tank_mind.gd")
const Stub = preload("res://scripts/smoke_night_watch_stub.gd")


func _initialize() -> void:
	if not _run_all():
		quit(1)
		return
	print("[smoke] night watch OK")
	quit(0)


func _run_all() -> bool:
	_test_tank_mind_tick()
	_test_sleep_stages()
	_test_away_gap()
	_test_persistence()
	_test_mood_overlay()
	return true


func _mock_sim() -> RefCounted:
	return Stub.new()


func _test_tank_mind_tick() -> void:
	var sim: RefCounted = _mock_sim()
	var f: Fish = Fish.new()
	f.arousal = 0.2
	f.stress = 0.15
	f.mood = 0.1
	f._asleep = true
	sim.fish = [f]
	for _i in 24:
		TankMind.tick(sim, 5.0, 60.0)
	var snap: Dictionary = TankMind.snapshot(sim)
	assert(str(snap.get("focus", "")) != "", "tank focus set")
	assert(float(snap.get("asleep_fraction", 0.0)) > 0.0, "asleep fraction tracked")


func _test_sleep_stages() -> void:
	var sim: RefCounted = _mock_sim()
	var f: Fish = Fish.new()
	f.maturity = 2
	f.swim_pattern = "school"
	f.hunger = 0.2
	f.stress = 0.1
	for _i in 120:
		NightWatch.tick_sleep(f, sim, 0.5)
	assert(f._asleep or f._sleep_depth > 0.0, "sleep engages at night phase")


func _test_away_gap() -> void:
	var sim: RefCounted = _mock_sim()
	var events: PackedStringArray = NightWatch.simulate_away_gap(sim, 7200)
	assert(events.size() >= 1, "away gap produces events")
	var extra: Dictionary = NightWatch.away_summary_extra(sim, 7200)
	assert(extra.has("tank_focus") or extra.has("night_quality"), "away extra context")


func _test_persistence() -> void:
	var sim: RefCounted = _mock_sim()
	TankMind.tick(sim, 8.0, 30.0)
	var saved: Dictionary = TankMind.to_dict(sim)
	var sim2: RefCounted = _mock_sim()
	TankMind.from_dict(sim2, saved)
	var a: Dictionary = TankMind.ensure(sim)
	var b: Dictionary = TankMind.ensure(sim2)
	assert(str(a.get("self_summary", "")) == str(b.get("self_summary", "")), "tank soul persists")


func _test_mood_overlay() -> void:
	var sim: RefCounted = _mock_sim()
	TankMind.ensure(sim)["mood_valence"] = 0.4
	var ov: Dictionary = TankMind.mood_overlay(sim)
	assert(ov.has("hue") and ov.has("val"), "mood overlay keys")
