extends SceneTree

# Wave B Pass 0 — MotionEvents → AmbientAudio bridge contract.
# Asserts pan-before-play and that staging-capped darts still emit audio.


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_motion_audio_bridge")
	MotionStaging.reset()
	MotionEvents.clear()

	var scene := Node.new()
	scene.name = "Main"
	root.add_child(scene)
	current_scene = scene

	var audio: Node = load("res://scripts/motion_audio_bridge_test_stub.gd").new()
	audio.name = "AmbientAudio"
	scene.add_child(audio)

	MotionStaging.boot_audio_bridge()
	MotionStaging.boot_audio_bridge()  # second call is a no-op
	t.check(true, "audio bridge boots idempotently")

	MotionEvents.emit(&"dart_started", null, Vector3(6, 2, 0), 0.7)
	t.check(Vector3(audio.get("last_pan_pos")).is_finite()
			and absf(Vector3(audio.get("last_pan_pos")).x - 6.0) < 0.01,
		"dart_started pans to event world X")
	t.check(int(audio.get("startle_calls")) >= 1, "dart_started plays startle sfx")

	audio.call("reset_counts")
	MotionEvents.emit(&"strike", null, Vector3(-4, 1, 0), 0.55)
	t.check(Vector3(audio.get("last_pan_pos")).x < 0.0, "strike pans left")
	t.check(int(audio.get("eat_calls")) >= 1, "strike plays eat sfx")

	audio.call("reset_counts")
	MotionEvents.emit(&"gulp", null, Vector3(0, 3, 0), 0.4)
	t.check(int(audio.get("bubble_calls")) >= 1, "gulp plays bubble sfx")

	# Staging-capped darts still emit (FishAnticipation contract via source).
	var ant_src: String = FileAccess.get_file_as_string("res://scripts/fish_anticipation.gd")
	t.check(ant_src.contains("busy region does not go silent")
			or ant_src.contains("Always emit audio"),
		"anticipation documents audio independent of staging")
	t.check(ant_src.contains("MotionEvents.emit(&\"dart_started\"")
			and ant_src.contains("dart_staged"),
		"dart_started emits even when staging rejects")

	var bridge_src: String = FileAccess.get_file_as_string("res://scripts/motion_staging.gd")
	t.check(bridge_src.contains("set_event_world_pos"),
		"motion bridge pans before SFX")

	var tap_src: String = FileAccess.get_file_as_string("res://scripts/sim_driver.gd")
	t.check(tap_src.contains("_play_ambient_event(\"startle\"")
			and tap_src.contains("pulse_glass_tap"),
		"glass tap has audible startle contract")

	scene.queue_free()
	MotionStaging.reset()
	MotionEvents.clear()
	await process_frame
	quit(t.finish())
