extends SceneTree

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_ready_defaults")
	var cfg: Node = root.get_node("TankConfig")
	cfg.capture_mode = true
	cfg.reset_to_defaults()
	t.equals(cfg.music_persona, "lofi", "a new tank starts with the soft score engine")
	t.equals(cfg.music_phrase_form, "loop", "default score avoids dramatic build/drop cycles")
	t.approx(cfg.music_vinyl_crackle, 0.0, "new tanks have clean texture")
	t.approx(cfg.music_bitcrush_algae, 0.0, "algae cannot make the default score gritty")
	t.approx(cfg.music_shaker_mix, 0.0, "defaults do not require taming the shaker")
	t.check(cfg.music_showiness < 0.25, "default movement remains restrained")
	t.check(cfg.auto_feed_fauna, "a fresh aquarium feeds its residents automatically")
	t.equals(cfg.cycle_start_mode, "established", "a fresh tank has an established cycle")
	t.equals(cfg.environment_preset, "bedroom_desk", "new tanks have a furnished setting")
	var first_menu: Control = load("res://tank_menu.tscn").instantiate()
	root.add_child(first_menu)
	await process_frame
	await process_frame
	t.check(first_menu.find_child("ScenarioPicker", true, false) == null, "first launch shows the ready menu without forcing template setup")
	first_menu.queue_free()
	await process_frame
	# Verify loading an existing choice takes priority over the new defaults.
	cfg.music_persona = "none"
	cfg.music_volume = 0.0
	cfg.auto_feed_fauna = false
	cfg.environment_preset = "void"
	# Use the real config serializer synchronously; capture mode suppresses runtime autosaves.
	var saves: Node = root.get_node("TankSaves")
	saves.new_tank("Saved choices test")
	var saved_config: ConfigFile = cfg.call("_build_save_config_file")
	t.equals(saved_config.save(cfg.call("_current_save_path")), OK, "fixture config writes successfully")
	cfg.reset_to_defaults()
	cfg.load_from_disk()
	t.equals(cfg.music_persona, "none", "saved musical choices survive loading")
	t.approx(cfg.music_volume, 0.0, "saved silence remains silence")
	t.check(not cfg.auto_feed_fauna, "manual feeding remains a saved choice")
	t.equals(cfg.environment_preset, "void", "saved room choice is respected")
	var menu: Control = load("res://tank_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	t.check((menu.get("_new_btn") as Button).text.contains("Living tank"), "primary menu action offers a ready aquarium")
	var templates: bool = false
	for child in menu.find_children("*", "Button", true, false):
		if child.text == "Templates":
			templates = true
	t.check(templates, "themed templates remain directly accessible")
	menu.queue_free()
	await process_frame
	quit(t.finish())
