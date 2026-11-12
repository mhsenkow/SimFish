extends SceneTree

# CREATURE_MOTION #681 — school waves fire on phrase change, not sweep delta.


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_music_phrase_wave")
	MotionWave.reset_for_test()
	var parent := Node3D.new()
	root.add_child(parent)
	var leader := Fish.new()
	parent.add_child(leader)
	leader.species = "glassdart"
	leader.swim_pattern = "school"
	leader.schooling_strength = 1.4
	leader.lead_score = 0.92
	leader.motion_agitation = 0.0
	leader.motion_turn_intent = Vector3.ZERO
	var school: Array = [leader]

	MotionWave.tick_music_sweep(school, 0.4, 0.0, "verse", false)
	var after_enter: float = leader.motion_agitation
	t.check(after_enter > 0.0, "first phrase assignment can inject")

	MotionWave.tick_music_sweep(school, 0.48, 0.12, "verse", false)
	t.approx(leader.motion_agitation, after_enter, "same phrase does not inject again")

	MotionWave.tick_music_sweep(school, 0.48, 0.0, "drop", false)
	t.check(leader.motion_agitation > after_enter + 0.05,
		"phrase change with sweep>0.2 injects on the leader")

	var after_drop: float = leader.motion_agitation
	MotionWave.tick_music_sweep(school, 0.5, 0.0, "drop", true)
	t.check(leader.motion_agitation > after_drop,
		"bar-line downbeat while sweeping injects")

	t.check(MusicChoreography.dance_bank_cap("hover") <= 0.45 + 0.001,
		"hover bank cap is tighter than school")
	t.check(MusicChoreography.dance_bank_cap("school") >= 0.7,
		"school bank cap stays readable")

	t.equals(String(MusicChoreography.species_modifiers("hover").get("vocab", "")), "glide",
		"hover dance vocab is glide")
	t.equals(String(MusicChoreography.species_modifiers("school", "danio").get("vocab", "")),
		"burst", "danio overlay dances in bursts")
	var clock: Dictionary = {
		"tempo": 120.0, "energy_env": 0.6, "bass": 0.7, "mid": 0.4, "high": 0.3,
		"beat_phase": 0.0, "downbeat": true, "onsets": [
			{"band": "bass", "strength": 0.8},
			{"band": "mid", "strength": 0.3},
		],
	}
	var hover_role: Dictionary = {
		"color_band": "bass", "stroke_subdiv": 1.0, "expressive": 0.7,
	}
	hover_role.merge(MusicChoreography.species_modifiers("hover"), true)
	var dart_role: Dictionary = {
		"color_band": "bass", "stroke_subdiv": 1.0, "expressive": 0.7,
	}
	dart_role.merge(MusicChoreography.species_modifiers("dart"), true)
	var hover_loco: Dictionary = MusicChoreography.universal_locomotion_mods(clock, hover_role, 0.8)
	var dart_loco: Dictionary = MusicChoreography.universal_locomotion_mods(clock, dart_role, 0.8)
	t.check(float(dart_loco.get("kick_thump", 0.0)) >= float(hover_loco.get("kick_thump", 0.0)),
		"burst vocab kicks at least as hard as glide")
	var fish_src: String = FileAccess.get_file_as_string("res://scripts/fish.gd")
	t.check(fish_src.contains("CREATURE_MOTION #677"),
		"dance freeze keeps a moving pec/eye hold")

	parent.queue_free()
	await process_frame
	quit(t.finish())
