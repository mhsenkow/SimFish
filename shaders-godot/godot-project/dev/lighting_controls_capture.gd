# Exercise the shipped UI callbacks on one stable populated tank, then capture
# each live lighting state. Always run through scripts/dev_run.sh.
extends "res://dev/visual_capture.gd"

var _running_controls: bool = false

func _process(_dt: float) -> void:
	_force_live_render()
	_pin_clock()
	if not _world_ready:
		return
	_hide_chrome()
	_release_camera_modes()
	_main.set("_hud_idle_seconds", 0.0)
	_apply_angle(0)
	if not _running_controls:
		_running_controls = true
		_run_controls.call_deferred()


func _run_controls() -> void:
	var cfg: Node = get_node("/root/TankConfig")
	var world_node: Node3D = _main.get("world")
	var sim_node: Node = _main.get("_sim")
	_main.call("_ensure_light_panel")
	sim_node.set_physics_process(false)
	for entity: Variant in sim_node.fish:
		if is_instance_valid(entity):
			entity.set_process(false)
	var population: int = sim_node.fish.size()
	var t := TestSupport.Suite.new("lighting_controls_capture")
	var rows: Array[Dictionary] = []
	for state: Dictionary in [
		{"name": "warm_lamp", "phase": 0.25, "preset": "cozy_shop", "auto": false,
			"on": true, "color": Color(1, 0.88, 0.68), "intensity": 0.5},
		{"name": "blue_lamp", "phase": 0.25, "preset": "cozy_shop", "auto": false,
			"on": true, "color": Color(0.25, 0.55, 1), "intensity": 0.5},
		{"name": "fixture_off", "phase": 0.25, "preset": "cozy_shop", "auto": false,
			"on": false, "color": Color(1, 0.88, 0.68), "intensity": 0.5},
		{"name": "automatic_night", "phase": 0.75, "preset": "cozy_shop", "auto": true,
			"on": true, "color": Color(1, 0.88, 0.68), "intensity": 0.5},
		{"name": "manual_night", "phase": 0.75, "preset": "cozy_shop", "auto": false,
			"on": true, "color": Color(1, 0.88, 0.68), "intensity": 0.5},
		{"name": "clip_spot", "phase": 0.75, "preset": "clip_spot_night", "auto": false,
			"on": true, "color": Color(1, 0.84, 0.42), "intensity": 0.7},
		{"name": "clip_no_shaft", "phase": 0.75, "preset": "clip_spot_night", "auto": false,
			"on": true, "color": Color(1, 0.84, 0.42), "intensity": 0.7, "shafts": false},
	]:
		_day_phase = float(state["phase"])
		cfg.apply_lighting_preset(String(state["preset"]))
		_main.call("_on_fixture_cycle_toggled", bool(state["auto"]))
		_main.call("_on_light_tank_toggled", bool(state["on"]))
		_main.call("_on_fixture_color_changed", state["color"])
		_main.call("_on_fixture_intensity_changed", float(state["intensity"]))
		cfg.light_volumetric = bool(state.get("shafts", true))
		if state["preset"] == "cozy_shop":
			cfg.room_darkness = 0.50
			cfg.global_intensity = 0.22
		await get_tree().create_timer(2.5).timeout
		await RenderingServer.frame_post_draw
		_shoot({"name": state["name"]})
		var energy: float = Rig.fixture_output(cfg, sim_node.daylight())
		var expected: int = 4 if cfg.light_fixture == "bar" else 1
		t.check(world_node._light_fixture_spots.size() == expected,
			"%s actual geometry follows preset" % state["name"])
		t.check(sim_node.fish.size() == population, "lighting control preserves the ecosystem")
		if state["name"] in ["fixture_off", "automatic_night"]:
			t.approx(energy, 0.0, "%s has no overhead power" % state["name"])
		else:
			t.check(energy > 0.0, "%s powers the actual lamp" % state["name"])
		rows.append({"state": state["name"], "output": energy, "spot_count": expected,
			"day_phase": sim_node.day_phase, "irradiance": sim_node.irradiance()})
	var file := FileAccess.open(OUT_DIR.path_join("controls.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "\t"))
	file.close()
	_write_metadata()
	print("[lighting_controls_capture] ", JSON.stringify(rows))
	get_tree().quit(t.finish())


const Rig = preload("res://scripts/lighting_rig.gd")
