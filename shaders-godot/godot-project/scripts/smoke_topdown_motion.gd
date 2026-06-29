extends SceneTree

# Pure-function golden tests for TopdownMotion (ENGINEERING_EXCELLENCE §43).
# Fast — no world/autoload setup required.


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	_assert(failed, TopdownMotion.is_overhead_from("top_down_ortho", 0.0),
			"ortho projection is overhead")
	_assert(failed, not TopdownMotion.is_overhead_from("perspective", 0.5),
			"low pitch side view is not overhead")
	_assert(failed, TopdownMotion.is_overhead_from("perspective", 1.2),
			"steep pitch counts as overhead")

	for vertical in TopdownMotion.VERTICAL_MOVES:
		var twin: String = TopdownMotion.effective_move(vertical, true)
		if twin == vertical:
			failed.append("effective_move should remap vertical %s" % vertical)
		if TopdownMotion.move_legibility(twin) < 0.85:
			failed.append("twin %s for %s should be legible" % [twin, vertical])

	var morph_start: float = TopdownMotion.formation_morph_blend(8, 0.0, 0.0)
	if morph_start > 0.05:
		failed.append("formation_morph_blend should start near 0 (got %.3f)" % morph_start)
	var morph_mid: float = TopdownMotion.formation_morph_blend(4, 0.5, 0.5)
	if morph_mid < 0.2 or morph_mid > 0.8:
		failed.append("formation_morph_blend mid phrase should be ~0.5 (got %.3f)" % morph_mid)
	if TopdownMotion.formation_morph_blend(0, 0.0, 1.0) < 0.999:
		failed.append("formation_morph_blend should finish at 1 when bars_left=0")
	if TopdownMotion.formation_morph_blend(1, 1.0, 0.85) < 0.99:
		failed.append("formation_morph_blend should snap on last downbeat")

	var geo: TopdownMotion.KeyGeometry = TopdownMotion.key_geometry_bias(0, "major")
	if geo.radius < 1.0 or geo.tightness > 1.0:
		failed.append("major key geometry should expand")
	var geo_min: TopdownMotion.KeyGeometry = TopdownMotion.key_geometry_bias(1, "minor")
	if geo_min.radius >= geo.radius:
		failed.append("minor key geometry should contract vs major")

	var eel: TopdownMotion.PathSignature = TopdownMotion.plan_path_signature("anguilliform", "meander")
	var tuna: TopdownMotion.PathSignature = TopdownMotion.plan_path_signature("thunniform", "cruise")
	if eel.wander_amp <= tuna.wander_amp:
		failed.append("anguilliform should wander more than thunniform")
	if eel.turn_mult <= tuna.turn_mult:
		failed.append("anguilliform should turn sharper than thunniform")

	var spill: TopdownMotion.ColorSpill = TopdownMotion.aggregate_color_spill([Color.RED, Color.BLUE])
	if spill.gain < 0.01 or spill.rgb.length_squared() < 0.01:
		failed.append("aggregate_color_spill should return rgb+gain")

	var conduct: TopdownMotion.ConductResult = TopdownMotion.conduct_from_stroke([
		Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 0.1),
	])
	if conduct.move.is_empty() or conduct.formation.is_empty():
		failed.append("conduct_from_stroke line should infer move+formation")
	if conduct.move != "sweep":
		failed.append("conduct_from_stroke line expected sweep got %s" % conduct.move)

	if TopdownMotion.phrase_to_string(TopdownMotion.phrase_from_string("drop")) != "drop":
		failed.append("phrase enum round-trip failed")
	var treble_r: float = TopdownMotion.visual_eq_radius_mult_enum(TopdownMotion.EqColumn.TREBLE)
	var bass_r: float = TopdownMotion.visual_eq_radius_mult_enum(TopdownMotion.EqColumn.BASS)
	if treble_r <= bass_r:
		failed.append("treble EQ radius should exceed bass")

	if failed.is_empty():
		print("[smoke] topdown_motion OK")
		quit(0)
	else:
		for f in failed:
			push_error("[smoke] " + f)
		quit(1)


func _assert(failed: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		failed.append(msg)
