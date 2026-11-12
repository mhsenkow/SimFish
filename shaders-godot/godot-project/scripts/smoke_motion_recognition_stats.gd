extends SceneTree

# HOLISTIC #100 — statistical proxy that schooling / hover / surface / bottom
# archetypes remain separable by swim_pattern + depth band centre. Not a
# perceptual gate; unlabeled human clips still required for Done review.

const DepthBands := preload("res://scripts/fish_depth_bands.gd")


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_motion_recognition_stats")
	var cfg: Node = root.get_node("TankConfig")
	var lib: Dictionary = cfg.SPECIES_LIBRARY

	var school_g: Dictionary = (lib.get("glassdart", {}) as Dictionary).get("genome", {})
	var hover_g: Dictionary = (lib.get("angelfish", {}) as Dictionary).get("genome", {})
	var surf_g: Dictionary = (lib.get("betta", {}) as Dictionary).get("genome", {})
	var bot_g: Dictionary = (lib.get("corydoras", {}) as Dictionary).get("genome", {})
	t.check(not school_g.is_empty() and not hover_g.is_empty()
			and not surf_g.is_empty() and not bot_g.is_empty(),
		"four motion archetypes present in SPECIES_LIBRARY")
	t.check(String(school_g.get("swim_pattern", "")) == "school",
		"glassdart schools")
	t.check(String(hover_g.get("swim_pattern", "")) == "hover",
		"angelfish hovers")
	t.check(bool(surf_g.get("labyrinth_breather", false)),
		"betta is a surface labyrinth breather")
	t.check(String(bot_g.get("swim_pattern", "")) == "shuffle",
		"corydoras shuffles the bed")

	var col_h: float = 5.0
	var mid_school: float = DepthBands.centre_frac(school_g, 1.6, col_h)
	var mid_hover: float = DepthBands.centre_frac(hover_g, 1.6, col_h)
	var mid_surf: float = DepthBands.centre_frac(surf_g, 1.6, col_h)
	var mid_bot: float = DepthBands.centre_frac(bot_g, 1.6, col_h)
	t.check(mid_bot < mid_school - 0.05 or mid_bot < mid_hover - 0.05,
		"bottom depth preference sits below mid-water (%.2f vs %.2f/%.2f)" % [
			mid_bot, mid_school, mid_hover])
	t.check(mid_surf > mid_bot + 0.08,
		"surface preference sits above bottom (%.2f vs %.2f)" % [mid_surf, mid_bot])
	t.check(String(school_g.get("swim_pattern", "")) != String(bot_g.get("swim_pattern", "")),
		"school vs bottom swim_patterns differ")
	t.check(String(hover_g.get("swim_pattern", "")) != String(school_g.get("swim_pattern", "")),
		"hover vs school swim_patterns differ")

	t.check(FileAccess.file_exists("res://dev/visual_capture.gd"),
		"visual_capture path exists for unlabeled fit clips")
	t.check(FileAccess.file_exists("res://dev/motion_lab.gd")
			or FileAccess.file_exists("res://dev/swimming_capture.gd"),
		"motion capture helper exists for per-type clips")
	var matrix: String = ""
	for cand in [
		"res://../../scripts/fish_probe_fps_matrix.sh",
		ProjectSettings.globalize_path("res://").path_join("../scripts/fish_probe_fps_matrix.sh"),
		ProjectSettings.globalize_path("res://").path_join("../../scripts/fish_probe_fps_matrix.sh"),
	]:
		matrix = FileAccess.get_file_as_string(cand)
		if not matrix.is_empty():
			break
	t.check(matrix.contains("HOLISTIC #099") or matrix.contains("FISH_PROBE_MAX_FPS")
			or FileAccess.file_exists("res://dev/fish_behaviour_probe.gd"),
		"fps matrix runner or behaviour probe ships for paired locomotion checks")

	quit(t.finish())
