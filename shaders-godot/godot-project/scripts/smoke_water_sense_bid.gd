extends SceneTree

# LOOM #185 — a chemistry bid in the workspace. Assert the water-sense bid is
# silent on healthy water, names the worst felt channel (burn/thin/...), is
# amplified by a worsening trend, and scales with the fish's sensitivity.

const GW = preload("res://scripts/global_workspace.gd")


func _init() -> void:
	var t := TestSupport.Suite.new("smoke_water_sense_bid")

	# Healthy water: no deviation, no bid.
	var healthy := _Sim.new({
		"o2": _row(0.85, 0.85, 0.0, 0.0),
		"toxic_ammonia": _row(0.0, 0.0, 0.0, 0.0),
	})
	t.check(GW._collect_water_sense_bid(_Fish.new(), healthy).is_empty(),
			"healthy water produces no bid")

	# Rising ammonia: a 'burn' bid with real salience.
	var fouling := _Sim.new({
		"toxic_ammonia": _row(0.22, 0.02, 0.2, 0.001),
		"o2": _row(0.85, 0.85, 0.0, 0.0),
	})
	var burn: Dictionary = GW._collect_water_sense_bid(_Fish.new(), fouling)
	t.check(not burn.is_empty(), "rising ammonia bids")
	t.equals(String(burn.get("label", "")), "water_sense", "label is water_sense")
	t.check((burn.get("coalition", []) as Array).has("burn"), "channel is burn")
	t.check(float(burn.get("salience", 0.0)) > 0.3, "burn salience meaningful (%.3f)" % float(burn.get("salience", 0.0)))

	# Thin water felt through the O2 penalty even with the median near normal.
	var thin_sim := _Sim.new({"o2": _row(0.6, 0.65, -0.05, -0.002)})
	var ff := _Fish.new()
	ff._chem_o2_penalty = 0.12
	var thin: Dictionary = GW._collect_water_sense_bid(ff, thin_sim)
	t.check(not thin.is_empty(), "thin felt water bids")
	t.check((thin.get("coalition", []) as Array).has("thin"), "channel is thin")

	# Sensitivity scales the salience.
	var mod := _Sim.new({"toxic_ammonia": _row(0.12, 0.02, 0.1, 0.0), "o2": _row(0.85, 0.85, 0.0, 0.0)})
	var shy := _Fish.new(); shy.water_sensitivity = 1.5
	var hardy := _Fish.new(); hardy.water_sensitivity = 0.5
	var s_shy: float = float(GW._collect_water_sense_bid(shy, mod).get("salience", 0.0))
	var s_hardy: float = float(GW._collect_water_sense_bid(hardy, mod).get("salience", 0.0))
	t.check(s_shy > s_hardy, "a sensitive fish bids harder (%.3f > %.3f)" % [s_shy, s_hardy])

	quit(t.finish())


static func _row(value: float, normal: float, deviation: float, slope: float) -> Dictionary:
	return {"value": value, "normal": normal, "deviation": deviation,
			"short_slope": slope, "long_slope": slope, "confidence": 0.8}


class _Sim:
	extends RefCounted
	var _snap: Dictionary = {}

	func _init(snap: Dictionary) -> void:
		_snap = snap

	func tank_vitals_snapshot() -> Dictionary:
		return _snap


class _Fish:
	extends RefCounted
	# Populated and read by MindBidPool.take() via get()/set(), not in-class.
	@warning_ignore("unused_private_class_variable")
	var _bid_pool: Array = []
	@warning_ignore("unused_private_class_variable")
	var _bid_pool_i: int = 0
	var water_sensitivity: float = 1.0
	var _chem_o2_penalty: float = 0.0
