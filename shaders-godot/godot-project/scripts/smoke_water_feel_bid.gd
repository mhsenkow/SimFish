extends SceneTree

# LOOM #179 — tank water_feel bid uses TankVitals deviation, not the always-true
# `o2 < 0.65 or o2 > 0.0` night gate. Healthy water stays silent; fouling bids.

const TankMind = preload("res://scripts/tank_mind.gd")


func _init() -> void:
	var t := TestSupport.Suite.new("smoke_water_feel_bid")

	# Helper itself: no vitals → silent.
	t.approx(TankMind._water_feel_salience(null), 0.0, "null sim is silent")
	t.approx(TankMind._water_feel_salience(_Sim.new({})), 0.0, "empty snapshot is silent")

	var healthy := _Sim.new({
		"o2": _row(0.85, 0.85, 0.0, 0.0),
		"toxic_ammonia": _row(0.0, 0.0, 0.0, 0.0),
		"nitrite": _row(0.0, 0.0, 0.0, 0.0),
	})
	t.approx(TankMind._water_feel_salience(healthy), 0.0, "healthy water is silent")

	var fouling := _Sim.new({
		"toxic_ammonia": _row(0.22, 0.02, 0.2, 0.001),
		"o2": _row(0.85, 0.85, 0.0, 0.0),
	})
	var foul_sal: float = TankMind._water_feel_salience(fouling)
	t.check(foul_sal > 0.2, "fouling ammonia bids (%.3f)" % foul_sal)

	var thin := _Sim.new({"o2": _row(0.45, 0.85, -0.4, -0.01)})
	var thin_sal: float = TankMind._water_feel_salience(thin)
	t.check(thin_sal > 0.2, "thin water bids (%.3f)" % thin_sal)

	# Night collect_bids: healthy night no longer always appends water_feel.
	var night_tm: Dictionary = {"collective_arousal": 0.1, "asleep_fraction": 0.4,
			"solitude": 0.0, "stocking_feel": ""}
	var night_healthy := _NightSim.new(healthy, 0.9, 0.2)
	var bids_ok: Array = TankMind.collect_bids(night_healthy, night_tm, 0.15, 0.0)
	t.check(not _has_label(bids_ok, "water_feel"), "healthy night omits water_feel")

	var night_foul := _NightSim.new(fouling, 0.9, 0.2)
	var bids_foul: Array = TankMind.collect_bids(night_foul, night_tm, 0.15, 0.0)
	t.check(_has_label(bids_foul, "water_feel"), "fouled night includes water_feel")

	quit(t.finish())


static func _row(value: float, normal: float, deviation: float, slope: float) -> Dictionary:
	return {"value": value, "normal": normal, "deviation": deviation,
			"short_slope": slope, "long_slope": slope, "confidence": 0.8}


static func _has_label(bids: Array, label: String) -> bool:
	for b in bids:
		if String(b.get("label", "")) == label:
			return true
	return false


class _Sim:
	extends RefCounted
	var _snap: Dictionary = {}

	func _init(snap: Dictionary) -> void:
		_snap = snap

	func tank_vitals_snapshot() -> Dictionary:
		return _snap


class _NightSim:
	extends RefCounted
	var _inner: RefCounted
	var dissolved_o2: float = 0.9
	var day_phase: float = 0.2
	var stability: float = 1.0
	var story_events: Array = []

	func _init(inner: RefCounted, o2: float, phase: float) -> void:
		_inner = inner
		dissolved_o2 = o2
		day_phase = phase

	func tank_vitals_snapshot() -> Dictionary:
		return _inner.tank_vitals_snapshot()

	func night_rt_f(_key: String, fallback: float = 0.0) -> float:
		return fallback
