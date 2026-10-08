# Rendered integration probe; must run through scripts/dev_run.sh.
extends SceneTree
const Photos = preload("res://scripts/tank_thumbnail.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if OS.get_environment("GODOT_DEV_SCRATCH_NAME").is_empty() or DisplayServer.get_name() == "headless":
		push_error("thumbnail probe requires an isolated rendered run")
		quit(1)
		return
	var cfg: Node = root.get_node("TankConfig")
	cfg.capture_mode = true
	cfg.reset_to_defaults()
	cfg.music_enabled = false
	var saves: Node = root.get_node("TankSaves")
	var slot: int = saves.new_tank("Thumbnail lifecycle probe")
	saves.active_slot = slot
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	var ready: Dictionary = await CaptureReadiness.await_world(self, main)
	if not ready.ok:
		push_error("thumbnail probe: World did not finish")
		quit(1)
		return
	var t := TestSupport.Suite.new("thumbnail_lifecycle_probe")
	cfg.capture_mode = false
	var path: String = saves.thumbnail_path(slot)
	var deadline: int = Time.get_ticks_msec() + 10000
	while not FileAccess.file_exists(path) and Time.get_ticks_msec() < deadline:
		await process_frame
	t.check(Photos.load_image(path) != null, "first visit produces a photo without a five-minute autosave")
	main.set("_viewport_capture_busy", true)
	var retry: String = "user://thumbnail_retry.png"
	main.call("_save_thumbnail", retry)
	await process_frame
	t.check(not FileAccess.file_exists(retry), "busy readback defers shelf photo")
	main.set("_viewport_capture_busy", false)
	deadline = Time.get_ticks_msec() + 10000
	while not FileAccess.file_exists(retry) and Time.get_ticks_msec() < deadline:
		await process_frame
	t.check(Photos.load_image(retry) != null, "deferred shelf photo is eventually saved")
	await main.call("_save_active_tank_with_thumbnail")
	t.check(Photos.load_image(path) != null, "exit photo remains usable")
	var out: String = OS.get_environment("THUMBNAIL_PROBE_OUT")
	if not out.is_empty():
		Photos.load_image(path).save_png(out)
	main.queue_free()
	await process_frame
	quit(t.finish())
