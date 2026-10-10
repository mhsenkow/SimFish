extends SceneTree

class ClockFixture extends SimDriver:
	var ecology_time: float = 0.0
	var tick_count: int = 0
	func _tick(dt: float) -> void:
		ecology_time += dt
		tick_count += 1


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_sim_cycle_clock")
	var cfg: Node = root.get_node("TankConfig")
	var original_enabled: bool = cfg.day_cycle_enabled
	var original_length: float = cfg.day_length_s
	cfg.day_cycle_enabled = true
	cfg.day_length_s = 360.0
	var sim := ClockFixture.new()
	root.add_child(sim)
	sim.set_physics_process(false)
	var dawn: float = sim.day_phase
	sim._physics_process(2.0)
	t.equals(sim.tick_count, 4, "large hitch retains the bounded four-tick budget")
	t.approx(sim.ecology_time, 0.4, "ecology consumes only accepted hitch time")
	t.approx((sim.day_phase - dawn) * 360.0, sim.ecology_time,
		"daylight never advances through discarded simulation debt")
	sim.time_scale = 0.0
	var paused_phase: float = sim.day_phase
	sim._physics_process(1.0)
	t.approx(sim.day_phase, paused_phase, "paused daylight remains fixed")
	t.equals(sim.tick_count, 4, "paused ecology remains fixed")
	sim.time_scale = 1.0
	cfg.day_cycle_enabled = false
	sim._physics_process(0.1)
	t.approx(sim.day_phase, paused_phase, "keeper can freeze daylight independently")
	t.equals(sim.tick_count, 5, "ecology continues under frozen daylight")
	cfg.day_cycle_enabled = true
	var before: float = sim.day_phase
	sim.time_scale = 16.0
	sim._physics_process(0.1)
	t.approx((sim.day_phase - before) * 360.0, 0.4,
		"fast-forward light shares the ecology catch-up limit")
	var busy := ClockFixture.new()
	root.add_child(busy)
	busy.set_physics_process(false)
	busy._last_tick_usec = SimDriver.SIM_RENDER_WORK_BUDGET_USEC + 1
	var busy_phase: float = busy.day_phase
	busy._physics_process(2.0)
	t.equals(busy.tick_count, 1, "expensive ticks reduce catch-up work")
	t.approx((busy.day_phase - busy_phase) * 360.0, busy.ecology_time,
		"expensive catch-up keeps daylight and ecology aligned")
	busy._sim_work_usec = SimDriver.SIM_RENDER_WORK_BUDGET_USEC
	var accepted: float = busy.ecology_time
	var accepted_phase: float = busy.day_phase
	busy._physics_process(1.0 / 60.0)
	t.approx(busy.ecology_time, accepted, "same rendered frame does not repeat exhausted work")
	t.approx(busy.day_phase, accepted_phase, "discarded overload time does not age the light")
	busy.free()
	sim.free()
	cfg.day_cycle_enabled = original_enabled
	cfg.day_length_s = original_length
	quit(t.finish())
