extends SceneTree

const Aesthetics := preload("res://scripts/aesthetics_runtime.gd")


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
	print("smoke_aesthetics: OK")
	quit()
