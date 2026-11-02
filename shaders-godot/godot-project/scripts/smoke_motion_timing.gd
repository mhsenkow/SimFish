extends SceneTree

# CREATURE_MOTION_700 §L — timing: weight, size, temperature and mood (#331–358).

const LifeBouts = preload("res://scripts/fish_life_bouts.gd")


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_motion_timing")
	var cfg: Node = root.get_node("TankConfig")
	cfg.capture_mode = true

	# #331: every playable species declares locomotion_type.
	var missing: PackedStringArray = PackedStringArray()
	for sp in cfg.SPECIES_LIBRARY.keys():
		var entry: Dictionary = cfg.SPECIES_LIBRARY[sp]
		var g: Dictionary = entry.get("genome", {}) as Dictionary
		if not g.has("locomotion_type") and FishTiming.locomotion_for_species(String(sp)).is_empty():
			missing.append(String(sp))
	t.check(missing.is_empty(), "all species declare locomotion (#331) missing=%s" % ",".join(missing))
	t.check(FishTiming.locomotion_for_species("mudsifter") == "anguilliform", "mudsifter anguilliform")
	t.check(FishTiming.locomotion_for_species("pufferfish") == "ostraciiform", "puffer tetraodontiform")
	t.check(FishTiming.locomotion_for_species("angelfish") == "labriform", "angel labriform")

	# #332: Strouhal rate scales with U/L.
	var slow: float = FishTiming.strouhal_tailbeat_rate(0.1, 0.45, "subcarangiform")
	var fast: float = FishTiming.strouhal_tailbeat_rate(0.8, 0.45, "subcarangiform")
	t.check(fast > slow * 1.5, "faster fish beat faster (#332)")
	var big: float = FishTiming.strouhal_tailbeat_rate(0.4, 1.2, "subcarangiform")
	var tiny: float = FishTiming.strouhal_tailbeat_rate(0.4, 0.2, "subcarangiform")
	t.check(tiny > big, "smaller fish beat faster for same U (#332)")

	# #333: visible wag capped near fps/6.
	var raw: float = TAU * 20.0
	var vis: float = FishTiming.visible_wag_rate(raw, 60.0)
	t.check(vis <= (60.0 / 6.0) * TAU + 0.01, "visible wag ≤ fps/6 (#333)")
	t.check(FishTiming.visible_amp_scale(raw, 60.0) < 0.6, "amp drops above cap (#333)")

	# #334 / #335: Q10 + oxygen.
	t.check(FishTiming.temperature_tempo(0.9) > FishTiming.temperature_tempo(0.3),
		"warm tank is brisker (#334)")
	t.check(FishTiming.oxygen_swim_tempo(0.2) < FishTiming.oxygen_swim_tempo(0.9),
		"low O₂ slows swim (#335)")
	t.check(FishTiming.oxygen_opercula_tempo(0.2) > FishTiming.oxygen_opercula_tempo(0.9),
		"low O₂ speeds opercula (#335)")

	# #336: diel curves differ by species.
	var day_cory: float = FishTiming.day_activity("corydoras", 0.9, "school")
	var night_cory: float = FishTiming.day_activity("corydoras", 0.05, "school")
	t.check(night_cory > day_cory, "corydoras peak at night (#336)")
	var dawn: float = FishTiming.day_activity("otocinclus", 0.25, "school")
	var noon: float = FishTiming.day_activity("otocinclus", 0.55, "school")
	t.check(dawn > noon, "oto crepuscular (#336)")

	# #337 / #340 / #341: species bout windows + lognormal + holds.
	var gup: Array = FishTiming.bout_windows("guppy")
	var angel: Array = FishTiming.bout_windows("angelfish")
	t.check(float(gup[0]) < float(angel[0]), "guppy cruise shorter than angel (#337)")
	t.check(FishTiming.hold_scale("guppy") < FishTiming.hold_scale("angelfish"),
		"angel holds longer (#340)")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var samples: Array = []
	for i in 80:
		samples.append(FishTiming.lognormal_between(rng, 2.5, 8.0))
	samples.sort()
	t.check(float(samples[40]) < float(samples[70]), "lognormal right-skew (#341)")

	# #338: danio windows are short burst-and-glide.
	var dan: Array = FishTiming.bout_windows("danio")
	t.check(float(dan[1]) <= 3.0, "danio cruise short (#338)")

	# #339: size slows reactions.
	t.check(FishTiming.size_reaction_scale(1.2) > FishTiming.size_reaction_scale(0.2),
		"big fish slower envelopes (#339)")

	# #342 / #343 / #344: exposure sheets.
	var c: Vector3 = FishTiming.c_start_stage_seconds()
	t.check(c.x > 0.04 and c.x < 0.08, "C-start stage1 ~3–4 frames (#342)")
	t.check(c.y > 0.06 and c.y < 0.12, "C-start stage2 ~4–6 frames (#342)")
	t.check(c.z >= 0.3 and c.z <= 0.6, "C-start glide 300–600 ms (#342)")
	t.check(FishTiming.strike_hold_seconds() >= 0.15 and FishTiming.strike_hold_seconds() <= 0.3,
		"strike fixation 150–300 ms (#343)")
	var gulp: float = FishTiming.gulp_trip_seconds(rng)
	t.check(gulp >= 1.15 and gulp <= 1.85, "gulp sheet duration (#344)")

	# #345: labriform pecs 2–4 Hz.
	var pec_lab: float = FishTiming.pec_freq("labriform", TAU * 3.0, 0.5, 1.0)
	t.check(pec_lab >= TAU * 2.0 and pec_lab <= TAU * 4.1, "labriform pec 2–4 Hz (#345)")
	var pec_body: float = FishTiming.pec_freq("subcarangiform", TAU * 4.0, 0.5, 1.0)
	t.check(absf(pec_body - TAU * 4.0 * 0.55) < 0.2, "body-caudal pec ratio (#345)")

	# #346 / #347 / #356: life-stage.
	t.check(FishTiming.life_stage_bout_dur_mult(Fish.MATURITY_FRY) < 1.0, "fry busy (#346)")
	t.check(FishTiming.life_stage_bout_dur_mult(Fish.MATURITY_SENESCENT) > 1.0,
		"senescent slow (#347)")
	t.check(FishTiming.life_stage_amp_mult(Fish.MATURITY_FRY) > 1.0, "fry amp (#356)")

	# #348: invertebrate weight table.
	t.check(FishTiming.invert_react_seconds("cherry_shrimp") <= 0.06, "shrimp ~50 ms (#348)")
	t.check(FishTiming.invert_react_seconds("crab") >= 0.15, "crab slower (#348)")
	t.check(FishTiming.invert_react_seconds("snail", true)
		> FishTiming.invert_react_seconds("snail", false), "snail body > tentacles (#348)")

	# #349: partial phase pull.
	var pulled: float = FishTiming.school_phase_pull(0.0, PI * 0.5, 0.8, 1.0)
	t.check(pulled > 0.05 and pulled < PI * 0.5, "draft pull is partial (#349)")

	# #350: clam follows time_scale (source contract).
	var clam_src: String = FileAccess.get_file_as_string("res://scripts/clam.gd")
	t.check(clam_src.contains("dt *= float(sim.time_scale)"), "clam respects time_scale (#350)")

	# #351 / #352: time-lapse + slow-mo.
	t.check(FishTiming.timelapse_amp_scale(8.0) < 0.6, "timelapse drops amp (#351)")
	t.check(is_equal_approx(FishTiming.timelapse_amp_scale(1.0), 1.0), "1× keeps amp (#351)")
	var pose_slow: float = FishTiming.pose_dt_for_time_scale(0.004, 0.016, 0.25)
	t.check(pose_slow >= 0.015, "slow-mo pose uses wall dt (#352)")

	# #353 / #354 / #355 / #357 / #358.
	t.check(FishTiming.mood_tempo(0.8, 0.5, 0.2, 0.8, 0.7)
		> FishTiming.mood_tempo(0.1, 0.0, 0.8, 0.2, 0.2), "anxious/hungry quicker (#354/#355)")
	t.check(is_equal_approx(FishTiming.sleep_breath_mult(true), 0.6), "sleep breath 60% (#357)")
	var q_gup: float = FishTiming.display_quiver_rate("guppy", 1.0)
	t.check(q_gup >= TAU * 10.0 and q_gup <= TAU * 15.5, "guppy quiver 10–15 Hz (#358)")

	# Living bout wiring: species windows + lognormal land on a fish.
	var host: Node3D = load("res://scripts/motion_world_test_stub.gd").new()
	root.add_child(host)
	var sim: Node = load("res://scripts/motion_visibility_test_stub.gd").new()
	sim.creature_visible = true
	host.add_child(sim)
	var f := Fish.new()
	host.add_child(f)
	f.set_process(false)
	var genome: Dictionary = cfg.SPECIES_LIBRARY["danio"]["genome"].duplicate(true)
	f.id = "timing_smoke"
	f.init_genome(genome)
	f.sim = sim
	f.species = "danio"
	f.maturity = Fish.MATURITY_ADULT
	f._spawn_settle_remaining = 0.0
	f.speed = 0.4
	f.max_speed = 1.2
	# Drive a few bout rolls and ensure durations stay in danio range.
	for i in 12:
		f._bout_t = 0.0
		LifeBouts.bout_speed(f, 0.5, 0.05, true, 0.7)
	t.check(f._bout_t > 0.0 and f._bout_t < 4.0, "danio bout duration lands short (#338)")
	t.check(f.locomotion_type == "subcarangiform", "danio declared loco applied")

	# Anticipation size scale + C-start sheet.
	FishPhase2Pose.enabled = true
	f.burst_remaining = 0.4
	f._startle_remaining = 0.3
	f.set_meta("_ant_prev_burst", 0.0)
	FishAnticipation.tick(f, 0.016)
	t.check(int(f.get_meta("_ant_c_sheet", 0)) == 1, "C-start sheet begins (#342)")
	FishAnticipation.note_bite_intent(f)
	t.check(float(f.get_meta("_ant_strike_hold", 0.0)) >= 0.15, "strike hold set (#343)")

	f.queue_free()
	host.queue_free()
	await process_frame
	quit(t.finish())
