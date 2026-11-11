extends SceneTree

# LOOM #301 + #251 — one tank self-model with saved history rings. Assert the
# minute ring bounds, trend slopes carry the right sign, the normal tracks the
# tank's own state, the snapshot exposes every channel, save/load round-trips,
# and the owned stability formula matches the value the sim used to compute
# inline (so making the sim a reader changed no behaviour).

const TV = preload("res://scripts/tank_vitals.gd")


func _init() -> void:
	var t := TestSupport.Suite.new("smoke_tank_vitals")
	var sim := _FakeSim.new()
	var v = TV.new()

	# One sim-minute at the default 360 s day is 0.25 s. Feed a rising O2.
	var minute_s: float = TV.DEFAULT_DAY_LENGTH_S / 1440.0
	for i in 200:
		sim.dissolved_o2 = 0.5 + float(i) * 0.001
		v.observe(sim, minute_s)
	t.check(v.short_slope("o2") > 0.0, "rising O2 gives a positive short slope (%.5f)" % v.short_slope("o2"))

	# Overfill the minute ring; it must stay bounded.
	for i in 1500:
		sim.dissolved_o2 = 0.7
		v.observe(sim, minute_s)
	var snap: Dictionary = v.snapshot()
	t.has_keys(snap, ["o2", "toxic_ammonia", "nitrite", "biomass", "stocking"],
			"snapshot exposes the vital channels")
	t.has_keys(snap["o2"], ["value", "normal", "deviation", "short_slope", "long_slope", "confidence"],
			"each channel carries value/normal/deviation/trend/confidence")
	t.in_range(v.confidence("o2"), 0.0, 1.0, "confidence clamped")
	t.approx(v.value("o2"), 0.7, "latest O2 is the last sample", 0.001)

	# After a long settle at 0.7, the normal should sit near 0.7 and deviation small.
	t.in_range(v.normal("o2"), 0.6, 0.8, "normal tracks the settled value")

	# Stability formula parity with the old inline sim computation.
	sim.dissolved_o2 = 0.65
	sim.water_chemistry.toxic_ammonia = 0.05
	sim.water_chemistry.nitrite = 0.1
	sim.bloom_intensity = 0.2
	var want: float = 1.0
	want -= clampf(0.05 * 4.0, 0.0, 0.5)
	want -= clampf(0.1 * 1.2, 0.0, 0.3)
	want -= clampf(absf(0.65 - 0.65) * 1.2, 0.0, 0.3)
	want -= clampf(0.2 * 0.4, 0.0, 0.25)
	want = clampf(want, 0.0, 1.0)
	t.approx(TV.stability_instant(sim), want, "stability_instant matches old inline formula")

	# Save/load round-trip: the long memory and normals survive.
	var saved: Dictionary = v.to_dict()
	t.has_keys(saved, ["hour", "minute_tail", "normal", "latest"], "save dict shape")
	var v2 = TV.new()
	v2.from_dict(saved)
	t.approx(v2.value("o2"), v.value("o2"), "latest survives save/load", 0.001)
	t.approx(v2.normal("o2"), v.normal("o2"), "normal survives save/load", 0.001)

	quit(t.finish())


class _FakeChem:
	extends RefCounted
	var toxic_ammonia: float = 0.0
	var nitrite: float = 0.0
	var nitrate: float = 0.0


class _FakeSim:
	extends RefCounted
	var dissolved_o2: float = 0.65
	var water_chemistry: _FakeChem = _FakeChem.new()
	var total_plant_biomass: int = 100
	var bloom_intensity: float = 0.0
	var waste: Array = []

	func fish_stocking_ratio() -> float:
		return 0.5

	func _tank_warmth_sample() -> float:
		return 0.55
