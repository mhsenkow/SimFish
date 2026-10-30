extends SceneTree

# CREATURE_MOTION_700 Phase 1 fish integration: one stroke clock (#49, #13),
# the per-draw wave phase (#50, #11), the quiet level (#10), crustacean bend
# (#12), motion data (#63), poses (#45, #77), cosmetic-only expression (#17),
# body proportions (#7) and frame-rate equivalence (#72, #104).

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_motion_phase1")
	var cfg: Node = root.get_node("TankConfig")
	cfg.capture_mode = true
	cfg.music_enabled = false
	cfg.music_sync_fish = false
	var host: Node3D = load("res://scripts/motion_world_test_stub.gd").new()
	root.add_child(host)
	_clock(t, host)
	_quiet_and_wave(t, host)
	_crustacean(t, host)
	_data(t)
	_expression(t, host)
	_proportions(t, host)
	_framerate(t, host)
	host.queue_free()
	await process_frame
	quit(t.finish())


func _swimmer(host: Node3D, visible: bool = true, species: String = "") -> Fish:
	var sim: Node = load("res://scripts/motion_visibility_test_stub.gd").new()
	sim.creature_visible = visible
	host.add_child(sim)
	var f := Fish.new()
	host.add_child(f)
	f.set_process(false)
	if species != "":
		var g: Dictionary = root.get_node("TankConfig").SPECIES_LIBRARY[species]["genome"].duplicate(true)
		g["sex"] = 0
		f.init_genome(g)
	f.sim = sim
	f.heading = Vector3.FORWARD
	f.target_velocity = Vector3.FORWARD * 0.8
	f.global_position = Vector3(0, 3, 0)
	f.home_y = 3.0
	f._hover_depth = 3.0
	f.speed = 0.4
	f.hunger = 0.8
	f.current_mode = Fish.Mode.FLEE
	f._spawn_settle_remaining = 0.0
	f._wag_freq_jitter = 1.0
	f._motor_phase = 0.3
	f._swim_phase = 0.3
	return f


func _swim(f: Fish, seconds: float, hz: float = 60.0) -> void:
	var dt: float = 1.0 / hz
	for i in int(round(seconds * hz)):
		f._motion_substep(dt, dt)


func _clock(t: TestSupport.Suite, host: Node3D) -> void:
	var f := _swimmer(host)
	_swim(f, 0.05)
	t.check(f._swim_phase > 0.3, "the first visible pose continues the spawn phase")
	_swim(f, 8.0)
	var off: float = wrapf(f._swim_phase - (f._motor_phase - PI * 0.5), -PI, PI)
	t.approx(off, 0.0, "the visible tail re-locks to the stroke clock a quarter cycle back", 0.05)
	var calm := _swimmer(host)
	var tense := _swimmer(host)
	tense.stress = 0.9
	tense._beat_mood_mult = tense._compute_beat_mood_mult()
	calm._beat_mood_mult = calm._compute_beat_mood_mult()
	t.check(tense._beat_mood_mult > calm._beat_mood_mult, "stress quickens the beat in the shared clock")
	var p0: float = tense._motor_phase
	var c0: float = calm._motor_phase
	_swim(tense, 1.0)
	_swim(calm, 1.0)
	t.check(tense._motor_phase - p0 > calm._motor_phase - c0, "a tense fish strokes faster, seen or culled")
	var culled := _swimmer(host, false)
	culled.stress = 0.9
	culled._beat_mood_mult = culled._compute_beat_mood_mult()
	var seen := _swimmer(host, true)
	seen.stress = 0.9
	seen._beat_mood_mult = seen._compute_beat_mood_mult()
	_swim(culled, 2.0)
	_swim(seen, 2.0)
	t.approx(culled._motor_phase, seen._motor_phase, "mood in the clock keeps culled and seen physics identical")
	t.check(culled.global_position.distance_to(seen.global_position) < 1e-4, "and the same path")


func _quiet_and_wave(t: TestSupport.Suite, host: Node3D) -> void:
	var f := _swimmer(host, true, "guppy")
	_swim(f, 1.0)
	t.in_range(float(f._motion_quiet_q), 0.0, 6.0, "a swimming fish keeps its shader ripple")
	t.check(not f._wave_instances.is_empty(), "an unbatched fish exposes its pivot draws")
	var gi: GeometryInstance3D = f._wave_instances[0]
	t.approx(float(gi.get_instance_shader_parameter(&"fauna_wave_phase")), fposmod(f._swim_phase, TAU),
		"the shader wave phase follows the tail phase", 1e-3)
	f._asleep = true
	_swim(f, 0.1)
	t.equals(f._motion_quiet_q, 14, "a sleeping fish stills the ripple and its fin flutter")
	f._asleep = false
	f.start_dying()
	t.equals(f._motion_quiet_q, 15, "a corpse doesn't ripple")
	var any_quiet: bool = false
	for h in f._cached_meshes:
		if h is VoxelBatch.Handle and floori((h as VoxelBatch.Handle).custom_data.a) == 15:
			any_quiet = true
			break
	t.check(any_quiet, "the quiet level reaches the voxels' instance data")


func _crustacean(t: TestSupport.Suite, host: Node3D) -> void:
	var sh: Node3D = load("res://scripts/shrimp.gd").new()
	host.add_child(sh)
	sh.set_process(false)
	sh.init_genome({})
	var max_bend: float = 0.0
	for h in sh.get("_voxel_builder").handles:
		max_bend = maxf(max_bend, float((h as VoxelBatch.Handle).get_meta("fauna_bend", 0.0)))
	t.approx(max_bend, 0.0, "crustacean voxels carry no lateral fish wave")
	var fish := _swimmer(host, true, "guppy")
	var fish_tail: float = 0.0
	for h in fish._cached_meshes:
		fish_tail = maxf(fish_tail, float((h as VoxelBatch.Handle).get_meta("fauna_bend", 0.0)))
	t.check(fish_tail > 0.9, "fish tails keep their full bend weight")
	var view: Dictionary = MotionCreatureView.of(sh)
	t.equals(view["kind"], "shrimp", "the creature view recognises a shrimp")
	t.equals(MotionCreatureView.of(fish)["kind"], "fish", "and a fish")


func _data(t: TestSupport.Suite) -> void:
	FishMotionProfiles.reload_data()
	var sub: Dictionary = FishMotionProfiles.get_profile("subcarangiform")
	t.approx(float(sub["tail_amp"]), 0.35, "subcarangiform tail amplitude unchanged by the data move")
	t.approx(float(sub["body_phase"]), PI, "subcarangiform keeps its counter-wag phase", 1e-4)
	var ang: Dictionary = FishMotionProfiles.get_profile("anguilliform")
	t.approx(float(ang["head_phase"]), -1.1 * PI, "anguilliform head phase from data", 1e-4)
	t.approx(float(FishMotionProfiles.get_profile("labriform")["pec_freq_base"]), 5.5, "labriform pectoral rate")
	t.approx(float(FishMotionProfiles.get_profile("nonsense")["tail_amp"]), 0.35, "unknown types fall back")
	t.equals(FishMotionProfiles.reload_data(), 5, "the data file overrides all five types")
	MotionPoseLibrary.reload_data()
	var rest: Dictionary = MotionPoseLibrary.rest_pose("guppy")
	t.has_keys(rest, ["fin_carriage", "caudal_spread", "dorsal_raise"], "every species has a rest pose")
	t.approx(float(MotionPoseLibrary.rest_pose("betta")["fin_carriage"]), 0.35, "a betta rests with fins half out")
	var disp: Dictionary = MotionPoseLibrary.get_pose("betta", "display")
	t.check(float(disp["caudal_spread"]) > float(MotionPoseLibrary.get_pose("guppy", "display")["caudal_spread"]),
		"a betta's display flares further than the default")
	t.check(MotionPoseLibrary.get_pose("guppy", "clamped").has("head_pitch"), "poses inherit rest channels")
	var times: Vector2 = MotionPoseLibrary.blend_times("guppy", "clamped")
	t.check(times.x < times.y, "alarm postures snap in and let go slowly")
	var b := MotionPoseLibrary.Blend.new(0.1, 1.0)
	b.set_on(true)
	for i in 12:
		b.step(1.0 / 60.0)
	t.approx(b.weight, 1.0, "a pose blends in on its in-time")
	b.set_on(false)
	for i in 12:
		b.step(1.0 / 60.0)
	t.check(b.weight > 0.5, "and out on its (longer) out-time")


func _expression(t: TestSupport.Suite, host: Node3D) -> void:
	var plain := _swimmer(host, true, "guppy")
	var playful := _swimmer(host, true, "guppy")
	playful._spark_motion = {"tail_amp": 1.14, "fin_spread": 1.18, "stillness": 0.0,
		"speed_scale": 2.0, "turn_scale": 2.0, "wander_scale": 2.0}
	_swim(plain, 3.0)
	_swim(playful, 3.0)
	t.check(plain.global_position.distance_to(playful.global_position) < 1e-4,
		"expression is cosmetic: steering ignores speed, turn and wander scales")
	t.check(playful._spark_tail > 1.1 and playful._spark_fins > 1.1, "a playful stance swings wider and flares")


func _proportions(t: TestSupport.Suite, host: Node3D) -> void:
	var f := _swimmer(host, true, "angelfish")
	var built: Vector3 = f._bank_pivot.scale
	_swim(f, 2.0)
	f._courtship_flare = true
	f._courtship_intensity = 0.8
	_swim(f, 2.0)
	f._courtship_flare = false
	_swim(f, 4.0)
	t.check(f._bank_pivot.scale.distance_to(built) < 0.01, "an angelfish keeps its depth after courting")
	f.answer_affect_cue("flare")
	t.check(f._body_proportions.is_equal_approx(built), "affect cues never touch the body proportions")


func _framerate(t: TestSupport.Suite, host: Node3D) -> void:
	var results: Array = []
	for hz in [30.0, 60.0, 120.0]:
		var f := _swimmer(host)
		_swim(f, 2.0, hz)
		results.append([f.global_position, f.speed])
	var p30: Vector3 = results[0][0]
	var p60: Vector3 = results[1][0]
	var p120: Vector3 = results[2][0]
	t.check(p60.distance_to(p120) < 0.03, "a fish covers the same path at 60 and 120 Hz")
	t.check(p30.distance_to(p120) < 0.06, "and at 30 Hz")
	t.approx(float(results[0][1]), float(results[2][1]), "speed matches across frame rates", 0.03)
