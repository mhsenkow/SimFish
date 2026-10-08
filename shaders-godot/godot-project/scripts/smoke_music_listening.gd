extends SceneTree

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_music_listening")
	var cfg: Node = root.get_node("TankConfig")
	cfg.capture_mode = true
	cfg.reset_to_defaults()
	var ambient: Node = load("res://scripts/ambient_audio.gd").new()
	ambient.set_process(false)
	root.add_child(ambient)
	ambient.set("_cached_beat_time", 0.25)
	ambient.set("_cached_beat_scale", 0.001)
	t.approx(ambient.call("_advance_musical_clock"), 0.25, "clock reads the accumulated beat")
	ambient.set("_cached_beat_scale", 0.002)
	t.approx(ambient.call("_advance_musical_clock"), 0.251, "tempo change does not re-time past samples")
	t.approx(ambient.get("_cached_beat_time"), 0.253, "new tempo changes only the next increment")
	var first: Dictionary = ambient.call("get_live_status")
	t.approx(first.energy, cfg.music_energy, "music energy reports musical drive rather than tank health")
	ambient.set("_cached_beat_time", 0.75)
	await process_frame
	var second: Dictionary = ambient.call("get_live_status")
	t.check(first.beat_phase != second.beat_phase, "beat updates within the same bar")
	ambient.set("_cached_drop_intensity", 0.9)
	ambient.set("_cached_lofi", true)
	ambient.set("_phrase_force_state", -1)
	ambient.play_feeding_event()
	t.equals(ambient.get("_phrase_force_state"), -1, "feeding preserves the lo-fi phrase")
	cfg.music_events_enabled = false
	ambient.set("_cached_lofi", false)
	ambient.play_feeding_event()
	t.equals(ambient.get("_phrase_force_state"), -1, "disabled events cannot force a build")
	var chord_before: int = ambient.get("_chord_root")
	ambient.play_aquarium_event_extended("death")
	t.equals(ambient.get("_chord_root"), chord_before, "disabled death cues preserve harmony")
	cfg.music_events_enabled = true
	ambient.queue_free()
	await process_frame
	var mc: Node = root.get_node("MusicContext")
	mc.set_process(false)
	var context: Dictionary = mc.get("_ctx")
	context.merge({"active": true, "source": "generative", "genre": "lofi", "energy_env": 0.7,
		"energy": 0.7, "tempo": 76.0, "swing": 0.5, "confidence": 1.0}, true)
	cfg.music_reactivity = 0.0
	var neutral: Dictionary = mc.fauna_behavior_mods(1)
	t.approx(neutral.speed, 1.0, "zero reactivity cannot speed fish up at slow tempos")
	cfg.music_reactivity = 0.65
	mc.set("_dance_blend", 1.0)
	var sleeping: Dictionary = mc.fauna_behavior_mods(1, {"sleep_depth": 1.0})
	t.approx(sleeping.speed, 1.0, "sleeping fish retain their baseline speed")
	t.approx(sleeping.sweep, 0.0, "sleeping fish do not sweep to lo-fi")
	t.check(not sleeping.beat_dart, "lo-fi does not induce sudden beat darts")
	context.active = false
	t.approx(mc.fauna_behavior_mods(1).speed, 1.0, "silence has no choreography")
	t.equals(mc.describe_now_playing(), "", "silent music is absent from thoughts")
	context.active = true
	t.check(mc.describe_now_playing().contains("swung"), "lo-fi perception describes its rhythm")
	context.arousal = 0.5
	mc.call("_derive_understanding", 0.0)
	t.approx(context.arousal, 0.5, "semantic smoothing respects elapsed time")
	mc.call("_derive_understanding", 1.0)
	t.check(not is_equal_approx(context.arousal, 0.5), "generative features produce an affect signal")
	cfg.music_volume = 0.0
	t.check(not mc.call("_generative_live", null), "muted score is not perceived as playing")
	cfg.music_volume = 0.7
	var studio: Node = load("res://scripts/sound_panel.gd").new()
	root.add_child(studio)
	var presets: Array = studio.get("PRESETS")
	for preset in presets:
		if preset.key == "lofi":
			studio.call("_apply_preset", preset)
	t.equals(cfg.music_persona, "lofi", "lo-fi selects its groove engine")
	t.equals(cfg.music_style, "hybrid", "lo-fi includes a musical bed")
	studio.call("_apply_preset", {"values": {"music_dance_style": "sway"}})
	t.equals(cfg.music_persona, "lofi", "dance controls preserve the selected score")
	for preset in presets:
		if preset.key == "ambient":
			studio.call("_apply_preset", preset)
	t.equals(cfg.music_persona, "none", "another preset clears the previous persona")
	studio.queue_free()
	await process_frame
	quit(t.finish())
