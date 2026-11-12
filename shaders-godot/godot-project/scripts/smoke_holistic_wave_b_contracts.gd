extends SceneTree

# Wave B contract smoke — wiring asserts for Pass 3–6 holistic closes.


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_holistic_wave_b_contracts")

	var glass: String = FileAccess.get_file_as_string("res://shaders/glass.gdshader")
	t.check(glass.contains("HOLISTIC #055") or glass.contains("band_w"),
		"glass shader has shape-aware band weights")
	t.check(glass.contains("alpha_cap"), "prism alpha cap present")

	var world: String = FileAccess.get_file_as_string("res://scripts/world.gd")
	t.check(world.contains("face_veil"), "world pushes face_veil by shape")
	t.check(world.contains("HOLISTIC #061") or world.contains("slope_hint"),
		"substrate strata uses terrain slope sampling")
	t.check(world.contains("0.52"), "wall haze quieted for #072")

	var visuals: String = FileAccess.get_file_as_string("res://scripts/aquarium_visuals.gd")
	t.check(not visuals.contains("maxf(float(_glass_mat.get_shader_parameter(\"screen_reflection\")"),
		"#067 cosmetics no longer floors screen_reflection")
	t.check(not visuals.contains("fr.glass_dust = 0.22"),
		"#065 no bio-seed dust wash")

	var grain: String = FileAccess.get_file_as_string("res://shaders/substrate_grain.gdshaderinc")
	t.check(grain.contains("HOLISTIC #062") or grain.contains("phase"),
		"gravel phase jitter for #062")

	var fish: String = FileAccess.get_file_as_string("res://scripts/fish.gd")
	t.check(fish.contains("_depth_excursion"), "#096 depth excursion present")
	t.check(fish.contains("HOLISTIC #096"), "#096 documented")

	var capture: String = FileAccess.get_file_as_string("res://dev/visual_capture.gd")
	t.check(capture.contains("VISUAL_CAPTURE_ANIMATE_DAY"),
		"#060 animate-day capture harness")

	var matrix: String = _read_repo("scripts/visual_baseline_matrix.sh")
	t.check(matrix.contains("dawn:0") and matrix.contains("dusk:0.5"),
		"#060 matrix defaults include dawn/dusk")

	var habitat: String = _read_repo("scripts/habitat_mature_series.sh")
	t.check(habitat.contains("habitat_080") or habitat.contains("HOLISTIC #080"),
		"#080 mature habitat series runner ships")

	var fid: String = FileAccess.get_file_as_string("res://scripts/tank_fidelity_runtime.gd")
	t.check(fid.contains("dust_panel_bias = clampf"),
		"#065 dust_panel_bias tracks light")

	quit(t.finish())


func _read_repo(rel: String) -> String:
	# Walk up from the project (or smoke scratch copy) until the file exists.
	var dir: String = ProjectSettings.globalize_path("res://").rstrip("/")
	for _i in 8:
		var path: String = dir.path_join(rel)
		if FileAccess.file_exists(path):
			return FileAccess.get_file_as_string(path)
		var parent: String = dir.get_base_dir()
		if parent == dir or parent.is_empty():
			break
		dir = parent
	return ""
