extends SceneTree

# SENTIENCE_THE_LOOM_THAT_THINKS Phase 0 extras: #96, #355, #368, #370.


const TankMind = preload("res://scripts/tank_mind.gd")
const MakeItThere = preload("res://scripts/make_it_there.gd")
const NightWatchExtras = preload("res://scripts/night_watch_extras.gd")


class FakeSim:
	extends Node
	var day_phase: float = 0.5
	var fish: Array = []
	@warning_ignore("unused_private_class_variable")
	var _tank_mind: Variant = null
	var _night_runtime: Dictionary = {}
	var _day: int = 0
	var dawn_spark_calls: int = 0

	func night_rt_f(key: String, fallback: float = 0.0) -> float:
		return float(_night_runtime.get(key, fallback))

	func set_night_rt_f(key: String, value: float) -> void:
		_night_runtime[key] = value

	func night_rt_b(key: String, fallback: bool = false) -> bool:
		return bool(_night_runtime.get(key, fallback))

	func set_night_rt_b(key: String, value: bool) -> void:
		_night_runtime[key] = value

	func daylight() -> float:
		var raw: float = 0.5 + 0.5 * cos((day_phase - 0.25) * TAU)
		return raw * raw * (3.0 - 2.0 * raw)

	func trigger_dawn_spark(_duration: float = 12.0) -> void:
		dawn_spark_calls += 1
		set_night_rt_f("dawn_spark_t", 12.0)

	func sim_day() -> int:
		return _day


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_loom_phase0_extras")
	var sim := FakeSim.new()
	root.add_child(sim)
	await process_frame

	# --- #96 mood_arousal tracks arousal, mood_strain tracks stress ---
	var tm: Dictionary = TankMind.ensure(sim)
	var happy: Fish = Fish.new()
	root.add_child(happy)
	happy.arousal = 0.9
	happy.stress = 0.05
	happy.mood = 0.5
	var stressed: Fish = Fish.new()
	root.add_child(stressed)
	stressed.arousal = 0.1
	stressed.stress = 0.9
	stressed.mood = -0.4
	sim.fish = [happy, stressed]
	for _i in 40:
		TankMind._aggregate_fish(sim, tm, 0.8)
	# Means: arousal ~0.5, stress ~0.475 — after lerp they should both rise,
	# and with more extreme inputs arousal (0.9/0.1) vs stress (0.05/0.9)
	# stay distinguishable from the old bug (both tracking stress).
	t.check(float(tm.get("mood_arousal", 0.0)) > 0.3,
			"mood_arousal follows mean arousal (#96)")
	t.check(float(tm.get("mood_strain", 0.0)) > 0.3,
			"mood_strain follows mean stress (#96)")
	# Excited-happy fish alone: high arousal, low stress.
	sim.fish = [happy]
	tm["mood_arousal"] = 0.18
	tm["mood_strain"] = 0.0
	for _i in 40:
		TankMind._aggregate_fish(sim, tm, 0.8)
	t.check(float(tm.get("mood_arousal", 0.0)) > 0.5,
			"excited fish raise mood_arousal (#96)")
	t.check(float(tm.get("mood_strain", 0.0)) < 0.2,
			"excited-happy fish keep mood_strain low (#96)")

	# --- #355 dawn spark fires on rising edge through 0.3 ---
	sim.day_phase = 0.75  # night
	sim.set_night_rt_f("dawn_spark_prev_dl", sim.daylight())
	sim.set_night_rt_f("dawn_spark_t", 0.0)
	sim.dawn_spark_calls = 0
	var fired: bool = false
	for step in 80:
		sim.day_phase = fposmod(0.75 + float(step) * 0.01, 1.0)
		NightWatchExtras._tick_dawn_spark(sim, 0.1)
		if sim.dawn_spark_calls > 0:
			fired = true
			break
	t.check(fired, "dawn spark fires on rising edge through 0.3 (#355)")
	t.equals(sim.dawn_spark_calls, 1, "dawn spark fires once per crossing (#355)")

	# --- #370 elegy / recent_loss clears after sim-days ---
	var arc: Dictionary = {"spark": {}}
	# Mark loss without needing music_context in the tree.
	var sp: Dictionary = MakeItThere.ensure_spark(arc)
	sp["last_loss_day"] = 0
	MakeItThere.spark_mark(arc, "recent_loss")
	t.check(MakeItThere.spark_has(arc, "recent_loss"), "loss marks recent_loss")
	sim._day = 3
	MakeItThere._tick_grief_decay(sim, arc, MakeItThere.ensure_spark(arc))
	t.check(not MakeItThere.spark_has(arc, "recent_loss"),
			"recent_loss clears after 3 sim-days (#370)")

	# --- #368 source contract: main no longer reads _sim.calm ---
	var main_src: String = FileAccess.get_file_as_string("res://scripts/main.gd")
	t.check(not main_src.contains('_sim.get("calm")') and not main_src.contains("_sim.calm"),
			"main ambient breath no longer reads nonexistent calm (#368)")
	t.check(main_src.contains("mood_valence") and main_src.contains("mood_arousal"),
			"main ambient breath reads TankMind mood (#368)")

	happy.queue_free()
	stressed.queue_free()
	sim.queue_free()
	quit(t.finish())
