class_name SimCadence
extends RefCounted

# PERFORMANCE_REALTIME #93 — named cadence bus; #63 timer wheel backend.

const _PERIODS: Array = [0.2, 0.5, 1.0, 5.0]
const _SimTimerWheelScript = preload("res://scripts/sim_timer_wheel.gd")

static var _entries: Array[Dictionary] = []
static var _use_wheel: bool = true


static func reset_for_test() -> void:
	_entries.clear()
	_SimTimerWheelScript.reset_for_test()


static func every(period_s: float, fn: Callable, stagger_s: float = 0.0) -> void:
	var entry: Dictionary = {
		"period": maxf(period_s, 0.05),
		"fn": fn,
		"stagger": maxf(stagger_s, 0.0),
		"t": stagger_s,
	}
	_entries.append(entry)
	if _use_wheel:
		_SimTimerWheelScript.schedule(entry["period"], fn, stagger_s)


static func tick(dt: float) -> void:
	if dt <= 0.0:
		return
	if _use_wheel:
		_SimTimerWheelScript.tick(dt)
		return
	for e in _entries:
		e["t"] = float(e.get("t", 0.0)) + dt
		var period: float = float(e.get("period", 1.0))
		if float(e["t"]) >= period:
			e["t"] = float(e["t"]) - period
			var cb: Callable = e.get("fn") as Callable
			if cb.is_valid():
				cb.call(dt)


static func nearest_period(target: float) -> float:
	var best: float = 0.2
	var best_d: float = 999.0
	for p in _PERIODS:
		var d: float = absf(p - target)
		if d < best_d:
			best_d = d
			best = p
	return best
