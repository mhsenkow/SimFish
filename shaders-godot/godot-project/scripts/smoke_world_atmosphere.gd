extends SceneTree

func _init() -> void:
	var suite := TestSupport.Suite.new("smoke_world_atmosphere")
	var ln: Dictionary = WorldAtmosphere.day_night_lighting(null, null)
	suite.has_keys(ln, ["dl", "dp", "deep_night", "tank_lights_on"], "lighting bundle is complete")
	var column: Dictionary = WorldAtmosphere.water_column_bundle(0.0, 0.0, 0.0,
		null, Color(0.4, 0.6, 0.6), Color(0.04, 0.1, 0.14))
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/water.gdshader")
	WorldAtmosphere.apply_water_shader(material, column, ln, 0.7)
	suite.approx(float(material.get_shader_parameter("ice_lens")), 0.7,
		"cold preset adds its ice lens")
	WorldAtmosphere.apply_water_shader(material, column, ln, 0.0)
	suite.approx(float(material.get_shader_parameter("ice_lens")), 0.0,
		"warm preset clears the previous ice lens")
	suite.approx(float(material.get_shader_parameter("under_glow")), 1.0,
		"underside gain is explicit and source energy is handled by the shader")
	suite.in_range(float(material.get_shader_parameter("surface_spec_power")), 32.0, 80.0,
		"surface reflection is broad enough to filter at low resolution")
	var clear_reflection: float = material.get_shader_parameter("surface_spec_gain")
	var hazy: Dictionary = column.duplicate()
	hazy["transmittance"] = 0.25
	WorldAtmosphere.apply_water_shader(material, hazy, ln, 0.0)
	suite.check(float(material.get_shader_parameter("surface_spec_gain")) < clear_reflection,
		"cloudy water scatters a weaker mirror reflection")
	quit(suite.finish())
