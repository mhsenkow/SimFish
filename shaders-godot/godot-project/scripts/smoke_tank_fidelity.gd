extends SceneTree

# Pins REAL_TANK_FIDELITY_200 foundations — stratified substrate, glass dust,
# reference snail boosts, gooseneck fixture, photo bundle, cap auto-tune.


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	var fidelity_script: GDScript = load("res://scripts/tank_fidelity_runtime.gd") as GDScript
	_assert(failed, fidelity_script != null, "tank_fidelity_runtime.gd loads")
	var Fidelity = fidelity_script

	var strata: Dictionary = Fidelity.strata_from_profile({
		"cap_fraction": 0.72,
		"soil_color": [32, 24, 16],
		"cap_color": [196, 174, 118],
		"colors": [Color8(32, 24, 16), Color8(196, 174, 118)],
	}, 0.0, 1.8, 6.0, 0.4)
	_assert(failed, float(strata.get("cap_fraction", 0.0)) > 0.5, "gravel cap fraction thick")
	_assert(failed, strata.has("soil_color") and strata.has("bed_top_y"), "strata fields present")

	var boost: Dictionary = Fidelity.reference_snail_boost("snail_bar")
	_assert(failed, int(boost.get("glass", 0)) >= 20, "snail_bar glass founders boosted")
	_assert(failed, int(boost.get("trumpet", 0)) >= 10, "snail_bar MTS boosted")
	var valli: Dictionary = Fidelity.reference_snail_boost("valli_jungle")
	_assert(failed, float(valli.get("ramshorn_bias", 0.0)) > 0.5, "valli ramshorn bias")

	var mat: Dictionary = Fidelity.reference_floater_recipe("counter_nano")
	_assert(failed, int(mat.get("duckweed", 0)) >= 40, "counter_nano duckweed dense")
	_assert(failed, int(mat.get("water_hyacinth", 0)) >= 1, "hyacinth in mat")

	var photo: Dictionary = Fidelity.photo_mode_bundle()
	_assert(failed, bool(photo.get("handheld_drift", false)), "photo handheld on")
	_assert(failed, float(photo.get("horizon_roll_deg", 0.0)) > 0.5, "horizon roll")

	var fr = fidelity_script.new()
	fr.record_graze_track(Vector3(1, 2, 3), 0.2)
	_assert(failed, fr.track_uniform_array().size() == 24, "24 track slots")
	fr.wipe_glass(1.0)
	_assert(failed, fr.glass_dust <= 0.01, "wipe clears dust")
	fr.spike_turbidity(0.6)
	_assert(failed, fr.turbidity_spike > 0.5, "turbidity spike")

	var scale: float = Fidelity.auto_tune_cap_scale(0.9, 1.0)
	_assert(failed, scale < 1.0, "pressure decays caps")
	var recover: float = Fidelity.auto_tune_cap_scale(0.2, 0.7)
	_assert(failed, recover >= 0.7, "low pressure recovers caps")

	var cam: GDScript = load("res://scripts/camera_controller.gd") as GDScript
	_assert(failed, cam != null, "camera_controller loads")
	var held: Dictionary = CameraController.handheld_offset(1.5, 1.0)
	_assert(failed, held.has("pos") and held.has("roll"), "handheld offset dict")
	_assert(failed, CameraController.min_radius_for_mode(true) < 3.0, "macro min radius")

	var gravel: Dictionary = TankConfig.SUBSTRATE_PROFILES["inert_gravel"]
	_assert(failed, float(gravel.get("cap_fraction", 0.0)) > 0.6, "inert_gravel profile cap")
	var soil: Dictionary = TankConfig.SUBSTRATE_PROFILES["aquasoil"]
	_assert(failed, float(soil.get("cap_fraction", 1.0)) < 0.4, "aquasoil thin cap")

	var cfg_script: Resource = load("res://scripts/tank_config.gd")
	_assert(failed, cfg_script != null, "tank_config.gd parses")
	var cfg: Node = (cfg_script as GDScript).new()
	_assert(failed, int(cfg.get("pop_cap_snail")) >= 90, "snail hard ceiling raised")
	_assert(failed, cfg.get("equipment_in_frame") != null, "equipment_in_frame exists")
	cfg.set("equipment_in_frame", false)
	_assert(failed, bool(cfg.get("equipment_in_frame")) == false, "equipment_in_frame toggles")
	cfg.free()

	var shader: Shader = load("res://shaders/substrate_opaque.gdshader") as Shader
	_assert(failed, shader != null, "substrate_opaque shader loads")
	var glass: Shader = load("res://shaders/glass.gdshader") as Shader
	_assert(failed, glass != null, "glass shader loads")
	var voxel: Shader = load("res://shaders/voxel.gdshader") as Shader
	_assert(failed, voxel != null, "voxel shader loads")
	var voxel_src: String = voxel.code if voxel != null else ""
	_assert(failed, voxel_src.find("grain_variation") >= 0, "voxel room grain uniform")
	var quant: Shader = load("res://shaders/palette_quantize.gdshader") as Shader
	_assert(failed, quant != null, "palette_quantize loads")
	var qsrc: String = quant.code if quant != null else ""
	_assert(failed, qsrc.find("highlight_rolloff") >= 0 and qsrc.find("sensor_noise") >= 0,
		"photo rolloff/noise uniforms")
	var glass_src: String = glass.code if glass != null else ""
	_assert(failed, glass_src.find("scum_line") >= 0, "glass scum_line uniform")
	_assert(failed, TankConfig.LIGHTING_PRESETS.has("backlit_jungle"), "backlit_jungle preset")
	var bl: Dictionary = TankConfig.LIGHTING_PRESETS["backlit_jungle"]
	_assert(failed, bool(bl.get("backlight_enabled", false)), "backlit enables rear fill")

	if failed.is_empty():
		print("[smoke] tank_fidelity OK")
		quit(0)
	else:
		for f in failed:
			push_error("[smoke] FAIL: %s" % f)
		print("[smoke] tank_fidelity FAILED (%d)" % failed.size())
		quit(1)


func _assert(failed: Array[String], cond: bool, msg: String) -> void:
	if not cond:
		failed.append(msg)
