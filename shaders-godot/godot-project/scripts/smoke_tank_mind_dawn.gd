extends SceneTree

# SENTIENCE_THE_LOOM_THAT_THINKS #369 — _note_dawn fires once per dawn, not every tick.


const TankMind = preload("res://scripts/tank_mind.gd")


class FakeSim:
	extends Node
	var day_phase: float = 0.12
	var dissolved_o2: float = 0.8
	var stability: float = 0.8
	var fish: Array = []
	@warning_ignore("unused_private_class_variable")
	var _tank_mind: Variant = null
	var _night_runtime: Dictionary = {}

	func night_rt_f(key: String, fallback: float = 0.0) -> float:
		return float(_night_runtime.get(key, fallback))

	func set_night_rt_f(key: String, value: float) -> void:
		_night_runtime[key] = value

	func night_rt_b(key: String, fallback: bool = false) -> bool:
		return bool(_night_runtime.get(key, fallback))

	func set_night_rt_b(key: String, value: bool) -> void:
		_night_runtime[key] = value

	func daylight() -> float:
		# Force the dawn window: dl > 0.45 with phase in 0.08..0.18.
		if day_phase > 0.08 and day_phase < 0.18:
			return 0.55
		if day_phase > 0.5:
			return 0.15  # night
		return 0.7


func _initialize() -> void:
	var t := TestSupport.Suite.new("smoke_tank_mind_dawn")
	var sim := FakeSim.new()
	root.add_child(sim)

	# Spend time at night so duration_since_dusk arms the latch.
	sim.day_phase = 0.75
	for _i in 5:
		TankMind.tick(sim, 1.0)
	var tm: Dictionary = TankMind.ensure(sim)
	t.check(float(tm.get("duration_since_dusk", 0.0)) > 0.0,
			"night accumulates duration_since_dusk")
	t.check(not bool(tm.get("dawn_noted", true)), "dawn latch armed at night")
	var nights_before: int = int(tm.get("nights_tended", 0))

	# Enter dawn window and tick many times — nights_tended must rise by 1.
	sim.day_phase = 0.12
	for _i in 20:
		TankMind.tick(sim, 0.5)
	tm = TankMind.ensure(sim)
	t.equals(int(tm.get("nights_tended", -1)), nights_before + 1,
			"dawn notes exactly once across a multi-tick dawn window")
	t.check(bool(tm.get("dawn_noted", false)), "dawn latch stays set through daybreak")
	var ledger: Array = tm.get("night_ledger", [])
	var dawn_lines: int = 0
	for line in ledger:
		if String(line).begins_with("dawn —"):
			dawn_lines += 1
	t.equals(dawn_lines, 1, "ledger gets one dawn line, not one per tick")

	sim.queue_free()
	quit(t.finish())
