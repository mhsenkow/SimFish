extends SceneTree

# CREATURE_MOTION_700 anticipation smokes (#143–#170 cluster).

const FishSparkBehavior = preload("res://scripts/fish_spark_behavior.gd")


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_motion_anticipation")
	var cfg: Node = root.get_node("TankConfig")
	cfg.capture_mode = true
	var host: Node3D = load("res://scripts/motion_world_test_stub.gd").new()
	root.add_child(host)
	var sim: Node = load("res://scripts/motion_visibility_test_stub.gd").new()
	sim.creature_visible = true
	host.add_child(sim)

	MotionEvents.clear()
	var f := Fish.new()
	host.add_child(f)
	f.set_process(false)
	var g: Dictionary = cfg.SPECIES_LIBRARY["guppy"]["genome"].duplicate(true)
	f.id = "ant_smoke"
	f.init_genome(g)
	f.sim = sim
	f.heading = Vector3.FORWARD
	f.target_velocity = Vector3(1, 0, -1).normalized() * 0.9
	f.global_position = Vector3(0, 3, 0)
	f.speed = 0.4
	f._spawn_settle_remaining = 0.0
	f._fin_tail_activity = 0.8

	# #143 / #154: turn intent writes head + bank lead.
	FishAnticipation.note_turn_intent(f, Vector3(1, 0, 0), 0.05)
	t.check(absf(FishAnticipation.head_lead_yaw(f)) > 0.05, "head lead arms on turn intent")
	t.check(absf(FishAnticipation.bank_lead(f)) > 0.05, "bank lead arms on turn intent")

	# #147 / #148: burst rising edge arms scull + tail cock + dart event.
	f.burst_remaining = 0.0
	FishAnticipation.tick(f, 0.05)
	f.burst_remaining = 0.4
	FishAnticipation.tick(f, 0.05)
	t.check(float(f.get_meta("_ant_scull", 0.0)) > 0.5, "pec scull arms before dart")
	t.check(float(f.get_meta("_ant_tail_cock", 0.0)) > 0.5, "tail cock arms before dart")
	t.check(MotionEvents.recent(&"dart_started").size() >= 1, "dart_started event fires")

	# #149: bite intent converges + slows.
	FishAnticipation.note_bite_intent(f)
	t.check(float(f.get_meta("_ant_fixate", 0.0)) > 0.5, "fixation before bite")
	t.check(MotionEvents.recent(&"strike").size() >= 1, "strike event fires")

	# #150: feed anticipation drift helper is callable.
	t.check(FishSparkBehavior.feed_anticipation_drift(f, null) == Vector3.ZERO,
		"feed drift is quiet without an active schedule")

	# #155: effort amp after burst arm.
	t.check(FishAnticipation.effort_amp(f) > 0.05, "effort rises before speed")

	# #156: brake scale drops inside stopping distance.
	f.speed = 1.2
	var far: float = FishAnticipation.brake_arrival_scale(f, 5.0, 2.0)
	var near: float = FishAnticipation.brake_arrival_scale(f, 0.15, 2.0)
	t.check(far > 0.95, "far from goal: no brake")
	t.check(near < 0.65, "near goal: brake scale drops (%.3f)" % near)

	# #157 / #158 / #166 / #167 / #168 poses arm.
	var partner := Fish.new()
	host.add_child(partner)
	partner.set_process(false)
	partner.init_genome(g)
	partner.global_position = f.global_position + Vector3(1, 0, 0)
	FishAnticipation.note_court_notice(f, partner)
	t.check(float(f.get_meta("_ant_court", 0.0)) > 0.5, "court notice arms")
	FishAnticipation.note_threat_display(f)
	t.check(float(f.get_meta("_ant_threat", 0.0)) > 0.5, "threat display arms")
	FishAnticipation.note_bottom_takeoff(f)
	t.check(float(f.get_meta("_ant_takeoff", 0.0)) > 0.5, "bottom takeoff arms")
	f.labyrinth_breather = true
	FishAnticipation.note_pre_gulp(f)
	t.check(float(f.get_meta("_ant_pre_gulp", 0.0)) > 0.5, "pre-gulp arms")
	f.species = "gar"
	FishAnticipation.note_stalk_stillness(f)
	t.check(float(f.get_meta("_ant_stalk", 0.0)) > 0.5, "stalk stillness arms")

	# #145 / #146: C-start and S-start leave finite pivots.
	f.set_meta("_ant_c_stage", 1.0)
	f._startle_heading = Vector3(1, 0, 0)
	FishAnticipation.apply_c_start(f)
	f.set_meta("_ant_s_stage", 1.0)
	FishAnticipation.apply_s_start(f)

	# #170: wind-up is live for at least one tick before peak speed.
	f.burst_remaining = 0.0
	f.speed = 0.2
	f.set_meta("_ant_prev_burst", 0.0)
	f._startle_remaining = 0.0
	FishAnticipation.tick(f, 0.05)
	f.burst_remaining = 0.5
	var speed_before: float = f.speed
	FishAnticipation.tick(f, 0.05)
	var windup: float = float(f.get_meta("_ant_scull", 0.0)) \
		+ float(f.get_meta("_ant_tail_cock", 0.0)) + float(f.get_meta("_ant_effort", 0.0))
	t.check(windup > 0.5, "wind-up state present before peak speed")
	t.check(f.speed <= speed_before + 0.05, "speed has not jumped on wind-up frame")

	# Pose path applies leads without crashing.
	for i in 20:
		f._motion_substep(1.0 / 60.0, 1.0 / 60.0)
	t.check(f._head_pivot != null and is_finite(f._head_pivot.rotation.y), "head pose stays finite")

	# #322 slice: bubble-nest steers a calm male labyrinth breeder.
	f.labyrinth_breather = true
	f.sex = 0
	f.maturity = Fish.MATURITY_ADULT
	f.stress = 0.1
	f.hunger = 0.2
	f.energy = 0.9
	f._bubble_nest_cooldown = 0.0
	f._bubble_nest_t = 0.0
	# Force a bout by seeding nest state.
	f._bubble_nest_pos = f.global_position + Vector3(0.8, 0.2, 0.0)
	f._bubble_nest_t = 5.0
	var desired := Vector3.ZERO
	desired = f._tick_bubble_nest(0.1, desired, 1.0)
	t.check(desired.length() > 0.1, "bubble nest steers toward nest")

	partner.queue_free()
	f.queue_free()
	host.queue_free()
	await process_frame
	quit(t.finish())
