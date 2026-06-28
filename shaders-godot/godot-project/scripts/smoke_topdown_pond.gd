extends SceneTree

# Headless integration smoke for pond mode + top-down dance/motion plumbing.


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	if TopdownMotion.effective_move("fountain", true) != "radial_bloom":
		failed.append("effective_move: fountain -> radial_bloom")
	if TopdownMotion.effective_move("curtain", true) != "planar_ring":
		failed.append("effective_move: curtain -> planar_ring")
	var oh_move: String = TopdownMotion.pick_move_overhead("drop", 0.9, "trance", 0)
	if oh_move in ["fountain", "curtain", "cascade"]:
		failed.append("pick_move_overhead drop should avoid vertical (%s)" % oh_move)
	if TopdownMotion.formation_slot_count(40) < 24:
		failed.append("formation_slot_count should scale up for 40 fish")
	var calm: float = TopdownMotion.surface_calm_factor(0.05, true)
	if calm < 0.5:
		failed.append("surface_calm_factor should settle high at night/rest")
	var flash: float = TopdownMotion.shadow_flash_strength(0.8, 0.7)
	if flash < 0.5:
		failed.append("shadow_flash_strength should spike on sync turn")
	var leg_drop: String = TopdownMotion.pick_move_overhead("drop", 0.9, "trance", 2)
	if TopdownMotion.move_legibility(leg_drop) < 0.85:
		failed.append("pick_move_overhead drop should prefer legible moves (%s)" % leg_drop)
	if TopdownMotion.lerp_formation_offset("circle", "star", 0, 8, 5.0, 4.0, 3.0, 0.5, 12).length_squared() < 0.01:
		failed.append("lerp_formation_offset should blend formations")
	if TopdownMotion.startle_radial_dir(Vector3(2, 1, 0), Vector3.ZERO, Vector3.FORWARD).x < 0.5:
		failed.append("startle_radial_dir should point away from origin")
	if TopdownMotion.caustic_beat_pulse(true, 0.8, 0.6) < 0.4:
		failed.append("caustic_beat_pulse downbeat too weak")
	if TopdownMotion.conduct_from_stroke([Vector3(0, 0, 0), Vector3(3, 0, 0), Vector3(3, 0, 3)]).get("move", "") == "":
		failed.append("conduct_from_stroke should infer move")
	if TopdownMotion.plan_path_signature("anguilliform", "meander").get("wander_amp", 0.0) < 1.2:
		failed.append("anguilliform should weave more in plan view")
	if TopdownMotion.density_wave_sep_push(1.0, 1.0, 0.8) <= 0.0:
		failed.append("density_wave_sep_push at front should push")
	if TopdownMotion.symmetry_snap_xz(Vector3(1.1, 0.0, 0.2)).length_squared() < 0.5:
		failed.append("symmetry_snap_xz should preserve radius")
	if TopdownMotion.visual_eq_radius_mult("treble") <= TopdownMotion.visual_eq_radius_mult("bass"):
		failed.append("visual_eq treble should expand vs bass")
	var spill: Dictionary = TopdownMotion.aggregate_color_spill([Color.RED, Color.BLUE])
	if float(spill.get("gain", 0.0)) < 0.01:
		failed.append("aggregate_color_spill should return gain")

	var side_move: String = MusicChoreography.pick_move("drop", 0.8, "trance", 3, false)
	if side_move != "fountain":
		failed.append("side pick_move drop expected fountain got %s" % side_move)
	var pond_move: String = MusicChoreography.pick_move("drop", 0.8, "trance", 3, true)
	if pond_move == "fountain":
		failed.append("overhead pick_move drop should not pick fountain")
	var pond_form: String = MusicChoreography.pick_formation(
		"chorus", "pop", "mandala", 1, true, 0.7)
	if pond_form not in ["heart", "star", "ring", "circle", "v", "mirror"]:
		failed.append("overhead formation unexpected: %s" % pond_form)

	for move in ["mandala", "radial_bloom", "planar_ring", "pinwheel", "spiral"]:
		var p: Vector3 = MusicChoreography.dance_target(
			move, 7, 0.25, 0.5, "drop", 0.6, "star", true, false,
			8.0, 4.0, 0.5, 6.5, 3.5, 0.7, 0.4, 0.5, 0.0, 0.0, {}, 0.0, 1.0, 0, 4, 24, true)
		if not p.is_finite() or absf(p.x) > 20.0 or absf(p.z) > 20.0:
			failed.append("dance_target %s bad pos %s" % [move, p])

	var mc := get_root().get_node_or_null("MusicContext")
	if mc == null:
		failed.append("MusicContext autoload missing")
	else:
		TopdownMotion.pond_active = true
		mc._last_phrase_state = ""
		mc._ctx["active"] = true
		mc._ctx["confidence"] = 0.9
		mc._ctx["phrase_state"] = "drop"
		mc._ctx["energy"] = 0.85
		mc._ctx["genre"] = "trance"
		mc._ctx["valence"] = 0.6
		mc._update_phrase_choreography()
		var drop_move: String = String(mc.get_context().get("move", ""))
		if drop_move in ["fountain", "curtain"]:
			failed.append("MusicContext overhead drop move vertical: %s" % drop_move)
		TopdownMotion.pond_active = false

	var world_script: Script = load("res://scripts/world.gd")
	var w: Node3D = world_script.new() as Node3D
	w.name = "SmokePondWorld"
	root.add_child(w)
	await process_frame
	await process_frame
	var sim: Node = w.get_node_or_null("SimDriver")
	if sim == null:
		failed.append("SimDriver missing on world")
	else:
		sim.pulse_sync_turn(Vector3(1, 0, 0), Vector3.ZERO)
		if not sim.sync_turn_active():
			failed.append("pulse_sync_turn should activate wave")
		sim.pulse_startle_bolt(Vector3(1, 3, 1))
		if not sim.startle_bolt_active():
			failed.append("pulse_startle_bolt should activate radial bolt")
		var bias: Vector3 = sim.sync_turn_heading_for(Vector3(2, 3, 0), 42)
		if bias.length_squared() < 1e-4:
			failed.append("sync_turn_heading_for should return steering near origin")
	w.queue_free()
	await process_frame

	if failed.is_empty():
		print("[smoke] topdown pond OK")
		quit(0)
	else:
		for f in failed:
			push_error("[smoke] " + f)
		quit(1)
