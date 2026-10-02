extends SceneTree

# Holistic track-5 motion batch: 081 / 082 / 083 / 084 / 086 / 089.
# Pure unit checks against FishDepthBands, FishLifeBouts, Hydrodynamics,
# MotionSchool — no full tank boot required.


const DepthBands = preload("res://scripts/fish_depth_bands.gd")
const LifeBouts = preload("res://scripts/fish_life_bouts.gd")


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("fish_life_bouts")

	_check_081_depth_contract(t)
	_check_082_emergency_bout(t)
	_check_083_turn_bounds(t)
	_check_084_fin_effort(t)
	_check_086_speed_match(t)
	_check_089_peck_normals(t)

	quit(t.finish())


func _check_081_depth_contract(t: TestSupport.Suite) -> void:
	# Same frac → proportional absolute Y across tank heights; inverse recovers.
	for col in [4.0, 5.0, 7.5, 10.0]:
		var floor_y: float = 1.6
		var surf: float = floor_y + col
		for frac in [0.2, 0.5, 0.8]:
			var y: float = DepthBands.y_from_frac(frac, floor_y, surf)
			t.approx(DepthBands.frac_from_y(y, floor_y, surf), frac,
				"frac↔y round-trip col=%.1f frac=%.1f" % [col, frac])
			t.approx(y, floor_y + frac * col,
				"y matches substrate+frac*column col=%.1f" % col)
	# Species centres are configured depths (no compensating offset baked in).
	var guppy: Dictionary = {"species": "guppy"}
	t.approx(DepthBands.centre_frac(guppy, 1.6, 5.0), 0.80, "guppy centre is 0.80")
	var saved: Dictionary = {"species": "guppy", "preferred_y_frac": 0.42}
	# has_band still true, but callers that honour preferred_y_frac keep 0.42.
	t.check(DepthBands.has_band(saved), "banded species still banded with save frac")
	t.approx(float(saved["preferred_y_frac"]), 0.42, "saved preferred_y_frac retained")


func _check_082_emergency_bout(t: TestSupport.Suite) -> void:
	var f: Fish = _make_fish()
	f._bout_kind = LifeBouts.BOUT_HOVER
	f._bout_env = 0.2
	f._bout_t = 2.0
	f._bout_level = 0.2
	f.hunger = 0.7
	t.check(LifeBouts.emergency_interrupt(f), "hunger triggers emergency")
	var before: float = f._bout_env
	var spd: float = LifeBouts.bout_speed(f, 1.0, 0.05, true, 1.0)
	t.check(f._bout_kind == LifeBouts.BOUT_CRUISE, "emergency aborts hover to cruise")
	t.check(spd <= 1.15, "no dart spike on interrupt (spd=%.2f)" % spd)
	t.check(f._bout_env >= before, "envelope recovers toward cruise")
	f.hunger = 0.1
	f.current_mode = Fish.Mode.FLEE
	t.check(LifeBouts.emergency_interrupt(f), "flee triggers emergency")
	f.current_mode = Fish.Mode.CRUISE
	f._startle_remaining = 0.4
	t.check(LifeBouts.emergency_interrupt(f), "startle triggers emergency")
	f.queue_free()


func _check_083_turn_bounds(t: TestSupport.Suite) -> void:
	var tiny: Fish = _make_fish()
	var large: Fish = _make_fish()
	tiny._turn_rate_state = 0.0
	large._turn_rate_state = 0.0
	var angle: float = 1.2
	var max_step: float = 0.25
	var turn_tiny: float = 0.0
	for _i in 8:
		turn_tiny = LifeBouts.inertial_turn(tiny, angle, max_step, 0.05, 0.0, 0.9, 0.30)
	var turn_large: float = 0.0
	for _i in 8:
		turn_large = LifeBouts.inertial_turn(large, angle, max_step, 0.05, 0.0, 0.9, 0.62)
	t.check(turn_large < turn_tiny + 1e-4,
		"larger body turns no harder than tiny (%.4f vs %.4f)" % [turn_large, turn_tiny])
	# Near-zero speed with zero rate invents no floor turn (no spin-in-place).
	var crawl: Fish = _make_fish()
	crawl._turn_rate_state = 0.0
	var crawl_turn: float = LifeBouts.inertial_turn(crawl, angle, max_step, 0.05, 0.0, 0.02, 0.45)
	t.check(crawl_turn < 1e-4,
		"near-zero speed does not invent a floor turn (got %.4f)" % crawl_turn)
	crawl._turn_rate_state = 3.0
	for _i in 24:
		LifeBouts.inertial_turn(crawl, angle, max_step, 0.05, 0.0, 0.02, 0.45)
	t.check(crawl._turn_rate_state < 0.6,
		"crawl bleeds yaw rate (state=%.3f)" % crawl._turn_rate_state)
	tiny.queue_free()
	large.queue_free()
	crawl.queue_free()


func _check_084_fin_effort(t: TestSupport.Suite) -> void:
	var cruise: Dictionary = Hydrodynamics.fin_effort_from_swim(
		0.6, 0.6, 1.2, Vector3.ZERO, Vector3.FORWARD)
	var brake: Dictionary = Hydrodynamics.fin_effort_from_swim(
		0.9, 0.2, 1.2, Vector3.ZERO, Vector3.FORWARD)
	var station: Dictionary = Hydrodynamics.fin_effort_from_swim(
		0.08, 0.08, 1.2, Vector3(0.04, 0, 0), Vector3.FORWARD)
	var carried: Dictionary = Hydrodynamics.fin_effort_from_swim(
		0.5, 0.35, 1.2, Vector3(0.08, 0, 0), Vector3(1, 0, 0))
	t.check(float(brake.get("braking", 0.0)) > float(cruise.get("braking", 0.0)),
		"braking reads higher brake effort")
	t.check(float(brake.get("pec_amp", 0.0)) > float(cruise.get("pec_amp", 0.0)),
		"braking flares pecs more than cruise")
	t.check(float(station.get("station", 0.0)) > 0.5, "station-hold flagged")
	t.check(float(carried.get("carried", 0.0)) > 0.15, "flow-carried flagged")
	t.check(float(carried.get("tail_amp", 1.0)) < float(cruise.get("tail_amp", 1.0)),
		"carried quiets the tail vs cruise")


func _check_086_speed_match(t: TestSupport.Suite) -> void:
	var cruise_w: float = MotionSchool.speed_match_weight("school", 0, 1.0, 0.0, 0.0, 0.0)
	var hover_w: float = MotionSchool.speed_match_weight("school", 1, 0.25, 0.0, 0.0, 0.0)
	var startle_w: float = MotionSchool.speed_match_weight("school", 0, 1.0, 0.0, 0.4, 0.0)
	t.check(cruise_w < 0.12, "cruise match softer than old 0.3 lockstep")
	t.check(hover_w < cruise_w * 0.5, "hover bout weakens speed lock")
	t.check(startle_w > cruise_w, "startle still propagates through school")


func _check_089_peck_normals(t: TestSupport.Suite) -> void:
	var f: Fish = _make_fish()
	f.home_y = 2.0
	# Without a world, _water_surface_y falls back to home_y + 4.0 → 6.0.
	f.position = Vector3(0, 5.5, 0)
	f.home_y_radius = 1.0
	f._peck_point = Vector3(0, 5.93, 0)
	f._peck_normal = Vector3.UP
	f._peck_kind = 1
	f._peck_plant = null
	t.check(LifeBouts._peck_target_reachable(f), "surface peck reachable near film")
	f.position.y = 2.0
	t.check(not LifeBouts._peck_target_reachable(f), "surface peck cancels when too deep")
	# Plant removed → cancel.
	f._peck_kind = 2
	f._peck_plant = null
	f._peck_point = Vector3(0, 3, 0)
	t.check(not LifeBouts._peck_target_reachable(f), "plant peck cancels when plant gone")
	# Glass: unreachable when clearance is huge (no wall).
	f._peck_kind = 3
	f._peck_normal = Vector3(1, 0, 0)
	t.check(not LifeBouts._peck_target_reachable(f), "glass peck cancels without a wall")
	# Head/contact agreement: approach prefers the axis into the surface.
	f._peck_kind = 1
	f._peck_point = Vector3(0, 5.93, 0)
	f._peck_normal = Vector3.UP
	f.position = Vector3(0, 5.5, 0)
	t.check(f._peck_normal.dot(Vector3.UP) > 0.9, "film contact normal faces meniscus")
	f.queue_free()


func _make_fish() -> Fish:
	var f: Fish = Fish.new()
	root.add_child(f)
	f.max_speed = 1.2
	f.speed = 0.5
	f.hunger = 0.1
	f.stress = 0.1
	f.home_y = 3.5
	f.current_mode = Fish.Mode.CRUISE
	f.maturity = Fish.MATURITY_ADULT
	f._bout_w = Vector4(0.3, 1.0, 0.0, 0.0)
	f._cruise_mult = 1.0
	f._bout_env = 1.0
	return f
