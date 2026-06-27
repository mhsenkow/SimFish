extends SceneTree

func _initialize() -> void:
	await process_frame
	var mc := get_root().get_node_or_null("MusicContext")
	if mc == null:
		push_error("[smoke] MusicContext autoload missing")
		quit(1)
		return
	assert(MusicChoreography.ease_in_out_cubic(0.5) > 0.4)
	assert(MusicChoreography.classify_genre(80.0, 0.3, 0.4, 0.5) == "ambient")
	assert(MusicChoreography.pick_move("drop", 0.8, "trance", 3) == "fountain")
	assert(MusicChoreography.pick_formation("chorus", "trance", "sweep", 0) == "heart")
	assert(MusicChoreography.pick_formation("chorus", "trance", "fountain", 0) == "mirror")
	assert(MusicChoreography.section_leader_lag(8) == 0.5)
	assert(MusicChoreography.section_leader_lag(0) == 0.0)
	assert(MusicChoreography.species_band("neon_tetra", "dart") == "high")
	var role: Dictionary = MusicChoreography.assign_music_role(
		{"species": "neon_tetra", "swim_pattern": "dart", "growth_factor": 0.7,
			"preferred_y": 5.5, "y_min": 0.5, "y_max": 8.0, "base_color": Color(0.05, 0.15, 0.95),
			"lead_score": 0.8, "color_vibrancy": 0.75, "finnage": 1.0, "mouth_orientation": 0,
			"boldness": 0.6}, 42)
	assert(role.get("color_band") == "treble")
	var loco: Dictionary = MusicChoreography.universal_locomotion_mods(
		{"tempo": 128.0, "bass": 0.6, "mid": 0.4, "high": 0.5, "energy_env": 0.5,
			"beat_phase": 0.1, "downbeat": true, "swing": 0.0, "onsets": [
				{"strength": 0.9}, {"strength": 0.5}, {"strength": 0.3}]},
		role, 0.8)
	assert(float(loco.get("wag_freq_target", 0.0)) > 1.0)
	var mods: Dictionary = mc.fauna_behavior_mods(42, {"swim_pattern": "dart", "lead_score": 0.8, "species": "neon"})
	assert(mods.has("move"))
	assert(mods.has("anticipation"))
	var ctx: Dictionary = mc.get_context()
	assert(ctx.has("beat_phase"))
	print("[smoke] music_context OK")
	quit()
