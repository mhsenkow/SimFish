extends SceneTree

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_audio_texture")
	var cfg: Node = root.get_node("TankConfig")
	cfg.capture_mode = true
	cfg.reset_to_defaults()
	cfg.music_persona = "lofi"
	cfg.music_vinyl_crackle = 0.0
	cfg.music_tape_wow = 0.0
	var ambient: Node = load("res://scripts/ambient_audio.gd").new()
	ambient.set_process(false)
	root.add_child(ambient)
	t.approx(ambient.call("_vinyl_cfg"), 0.0, "zero vinyl stays off with a lo-fi persona")
	t.approx(ambient.call("_tape_wow_cfg"), 0.0, "zero tape stays off with a lo-fi persona")
	ambient.set("_cached_vinyl", 0.6)
	ambient.set("_vinyl_pop_t", 100.0)
	var floor_peak: float = 0.0
	for i in 512:
		floor_peak = maxf(floor_peak, absf(ambient.call("_vinyl_sample")))
	t.approx(floor_peak, 0.0, "lo-fi vinyl has no continuous hiss between accents")
	cfg.music_hat_mix = 0.0
	cfg.music_kick_mix = 0.0
	cfg.music_shaker_mix = 0.0
	cfg.music_clap_mix = 0.0
	ambient.call("_refresh_mix_cache")
	ambient.set("_clap_env", 1.0)
	var drum_peak: float = 0.0
	for i in 256:
		ambient.call("_render_trance_streams")
		drum_peak = maxf(drum_peak, maxf(absf(ambient.get("_f_drums_l")), absf(ambient.get("_f_drums_r"))))
	t.approx(drum_peak, 0.0, "muted percussion cannot leak clap stereo noise")
	var queued := PackedVector2Array()
	for i in 6:
		queued.append(Vector2(float(i) * 0.001, float(i) * 0.001))
	for key in ["_synth_queue_drums", "_synth_queue_synth", "_synth_queue_air"]:
		ambient.set(key, queued.duplicate())
	t.equals(ambient.call("_drain_synth_queues", 0), 0, "zero frame budget writes no samples")
	t.equals(ambient.get("_synth_queue_synth").size(), 6, "zero frame budget retains queued samples")
	t.equals(ambient.call("_drain_synth_queues", 2), 2, "partial drain obeys the frame budget")
	for key in ["_synth_queue_drums", "_synth_queue_synth", "_synth_queue_air"]:
		var tail: PackedVector2Array = ambient.get(key)
		t.equals(tail.size(), 4, "partial drain preserves the remaining " + key)
		t.approx(tail[0].x, 0.002, "remaining samples preserve order " + key)
	var studio: Node = load("res://scripts/sound_panel.gd").new()
	root.add_child(studio)
	cfg.music_vinyl_crackle = 0.4
	cfg.music_hat_mix = 0.4
	cfg.music_shaker_mix = 0.4
	var melody: float = cfg.music_arp_mix
	studio.call("_on_clean_texture")
	t.approx(cfg.music_vinyl_crackle, 0.0, "clean texture removes vinyl")
	t.approx(cfg.music_hat_mix, 0.0, "clean texture removes hats")
	t.approx(cfg.music_shaker_mix, 0.0, "clean texture removes shaker")
	t.approx(cfg.music_arp_mix, melody, "clean texture preserves melody")
	t.equals(cfg.music_persona, "lofi", "clean texture preserves musical style")
	studio.queue_free()
	ambient.queue_free()
	await process_frame
	quit(t.finish())
