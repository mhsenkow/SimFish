extends SceneTree

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_music_response_cache")
	var cfg: Node = root.get_node("TankConfig")
	cfg.reset_to_defaults()
	cfg.capture_mode = true
	var mc: Node = root.get_node("MusicContext")
	mc.set_process(false)
	var context: Dictionary = mc.get("_ctx")
	context.merge({"active": true, "source": "generative", "genre": "lofi", "confidence": 1.0,
		"tempo": 76.0, "energy_env": 0.6, "energy": 0.6}, true)
	mc.set("_dance_blend", 1.0)
	var fish := Fish.new()
	root.add_child(fish)
	fish.set_process(false)
	var sim := SimDriver.new()
	var first: Dictionary = fish._music_mods()
	t.check(is_same(first, fish._music_mods()), "repeated frame reads reuse the music response")
	t.check(is_same(first, sim.music_mods_for(fish)), "simulation and animation share the same response")
	fish._sleep_depth = 1.0
	await process_frame
	var sleeping: Dictionary = sim.music_mods_for(fish)
	t.check(not is_same(first, sleeping), "a new frame refreshes the response")
	t.approx(sleeping.speed, 1.0, "simulation respects sleep rather than using incomplete traits")
	t.approx(sleeping.sweep, 0.0, "sleeping fish cannot receive a separate simulation dance sweep")
	cfg.music_sync_fish = false
	await process_frame
	var quiet: Dictionary = fish._music_mods()
	t.approx(quiet.speed, 1.0, "disabling response produces neutral motion on the next frame")
	fish._music_mods_render_stamp = -1
	var refreshed: Dictionary = fish._music_mods()
	t.check(not is_same(quiet, refreshed), "life ticks can invalidate stale same-frame traits")
	fish.queue_free()
	sim.free()
	await process_frame
	quit(t.finish())
