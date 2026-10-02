extends SceneTree

const Aesthetics := preload("res://scripts/aesthetics_runtime.gd")
const Metrics := preload("res://scripts/frame_metrics.gd")


func _init() -> void:
	assert(Aesthetics.biotope_palette_key_from_preset("amazon_discus") == "amazon_clearwater")
	assert(Aesthetics.biotope_palette_key_from_preset("tanganyika_cichlid") == "tanganyika_rock")
	var sample: Array = [
		"081828", "102838", "183848", "205868", "288898", "40b0c8", "70d0e0", "a8ecf4",
		"081818", "102828", "184038", "205850", "287868", "389878", "50b898", "78d8b8",
		"201008", "382010", "502818", "683820", "805028", "986838", "b08048", "c89858",
		"101018", "202028", "303038", "404048", "505058", "606068", "707078", "808088",
		"ffffff", "f0f8fc", "d0e8f0", "ff4040", "ff8830", "ffe040", "30c868", "4060ff",
		"ff40c0", "ff6088", "000000", "404040", "202020", "101010", "f8fcff", "ffffff",
	]
	assert(sample.size() == 48)
	var remapped: Array = Aesthetics.remap_palette_hexes(sample, "protan")
	assert(remapped.size() == 48)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/palette_quantize.gdshader") as Shader
	assert(sm.shader != null)
	sm.set_shader_parameter("health_grade", 0.72)
	sm.set_shader_parameter("film_grain_strength", 0.06)
	sm.set_shader_parameter("selective_glow", 0.5)
	sm.set_shader_parameter("crt_mode", 1.0)
	assert(load("res://shaders/caustics.gdshader") as Shader != null)
	assert(load("res://shaders/god_ray.gdshader") as Shader != null)

	# HOLISTIC #042 — photo preset keeps palette_lock; UI excluded from aquarium lock.
	assert(float(Aesthetics.PHOTO_MODE_GRADE.get("palette_lock", 0.0)) >= 0.99)
	var contract: Dictionary = Aesthetics.palette_lock_contract()
	assert(contract.get("photo_keeps_lock") == true)
	assert((contract.get("excluded_from_aquarium_lock") as Array).has("ui"))
	assert(String(Metrics.palette_mode_profile("ui").get("scope")) == "ui")
	assert(float(Metrics.palette_mode_profile("night").get("palette_excess_max")) <= 4.0)
	assert(float(Metrics.palette_mode_profile("photo").get("palette_excess_max")) <= 4.5)
	assert(float(Metrics.palette_mode_profile("care").get("palette_excess_max")) <= 4.0)
	assert(float(Metrics.palette_mode_profile("outline").get("palette_excess_max")) <= 4.0)

	# HOLISTIC #046 — red/blue/yellow/green remain distinguishable under tint stacks.
	var red := Color(0.82, 0.18, 0.14)
	var blue := Color(0.22, 0.32, 0.78)
	var yellow := Color(0.86, 0.78, 0.18)
	var green := Color(0.22, 0.62, 0.28)
	var crushed_red := Color(0.35, 0.42, 0.28)  # would flip red→green
	var fixed_red: Color = Aesthetics.protect_color_identity(red, crushed_red)
	assert(fixed_red.r >= fixed_red.g and fixed_red.r >= fixed_red.b)
	assert(Aesthetics.protect_color_identity(blue, blue).b >= 0.7)
	assert(Aesthetics._is_yellow_lead(Aesthetics.protect_color_identity(yellow, yellow)))
	assert(Aesthetics.protect_color_identity(green, green).g >= green.r)
	var stacked: Vector2 = Aesthetics.compose_tint_sat_val(1.30, 0.92, 1.25, 0.90)
	assert(stacked.x <= 1.45 and stacked.x >= 0.55)
	assert(stacked.y <= 1.30)

	# HOLISTIC #048 — blackwater contrast bundle exists; planted does not.
	assert(Aesthetics.blackwater_contrast_bundle("planted").is_empty())
	var bw: Dictionary = Aesthetics.blackwater_contrast_bundle("blackwater")
	assert(not bw.is_empty())
	assert(float(bw.get("extinction_scale")) < 1.0)
	assert(float(bw.get("depth_legibility")) > 2.6)
	assert(float(bw.get("tannin_affinity_min")) >= 0.20)
	assert(Aesthetics.fauna_saturation_mult("blackwater") >= 1.20)

	# Shader include carries identity protection.
	var tint_src: String = FileAccess.get_file_as_string("res://shaders/palette_tint.gdshaderinc")
	assert(tint_src.contains("protect_color_identity"))
	var quant_src: String = FileAccess.get_file_as_string("res://shaders/palette_quantize.gdshader")
	assert(quant_src.contains("water_like") and quant_src.contains("fauna_like"))

	print("smoke_aesthetics: OK")
	quit()
