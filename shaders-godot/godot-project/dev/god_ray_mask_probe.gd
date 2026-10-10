# GPU regression: particulate light obeys every beam mask, with correct HG sign.
# scripts/dev_run.sh --script res://dev/god_ray_mask_probe.gd
extends SceneTree

var _viewport: SubViewport
var _camera: Camera3D
var _material: ShaderMaterial
var _patch_position: Vector3
var _output: String
var _rows: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("TankConfig").capture_mode = true
	_output = OS.get_environment("GOD_RAY_MASK_OUT")
	if _output.is_empty():
		_output = "user://god_ray_mask_probe"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(128, 128)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var scene := Node3D.new()
	_viewport.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	scene.add_child(environment)
	_patch_position = Vector3(PI / 22.0, PI / 17.0, PI / 20.0)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 0.08
	scene.add_child(_camera)
	_set_view(false)
	var patch := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.08, 0.08)
	patch.mesh = plane
	patch.position = _patch_position
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/god_ray.gdshader")
	_material.set_shader_parameter("beam_color", Color(1, 0.8, 0.55, 0.08))
	_material.set_shader_parameter("speed", 0.0)
	_material.set_shader_parameter("dust_mote_density", 1.0)
	_material.set_shader_parameter("water_surface_y", 5.0)
	_material.set_shader_parameter("beam_posterize", 0.0)
	_material.set_shader_parameter("caustic_baked", 0.0)
	_material.set_shader_parameter("tank_plane_count", 0)
	_material.set_shader_parameter("canopy_attenuation", 0.0)
	_material.set_shader_parameter("occluder_strength", 1.0)
	patch.material_override = _material
	scene.add_child(patch)
	RenderingServer.global_shader_parameter_set("iaq_beam_origin", _patch_position + Vector3.UP * 4.0)
	RenderingServer.global_shader_parameter_set("iaq_beam_dir", Vector3.DOWN)
	RenderingServer.global_shader_parameter_set("iaq_beam_axis", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("iaq_beam_cone", Vector4(0.5, 0.9, 20, 1))
	var tests := TestSupport.Suite.new("god_ray_mask_probe")
	var bright: float = await _sample("unmasked_dust")
	tests.check(bright > 0.05, "the diagnostic patch exercises actual particulate light")
	var planes: Array[Vector4] = []
	planes.resize(8)
	planes.fill(Vector4.ZERO)
	planes[0] = Vector4(1, 0, -1, 0)
	_material.set_shader_parameter("tank_planes", planes)
	_material.set_shader_parameter("tank_plane_count", 1)
	var clipped: float = await _sample("outside_tank")
	tests.check(clipped < 0.005, "dust cannot bypass the tank footprint mask")
	_material.set_shader_parameter("tank_plane_count", 0)
	var canopy_image := Image.create(1, 1, false, Image.FORMAT_R8)
	canopy_image.fill(Color.WHITE)
	var canopy_texture := ImageTexture.create_from_image(canopy_image)
	_material.set_shader_parameter("canopy_density_tex", canopy_texture)
	_material.set_shader_parameter("canopy_attenuation", 1.0)
	var canopy: float = await _sample("opaque_canopy")
	tests.check(canopy < 0.005, "dust cannot bypass an opaque floating canopy")
	_material.set_shader_parameter("canopy_attenuation", 0.0)
	var occluders: Array[Vector4] = []
	occluders.resize(8)
	occluders.fill(Vector4.ZERO)
	occluders[0] = Vector4(_patch_position.x, _patch_position.y, _patch_position.z, 1.0)
	_material.set_shader_parameter("occluders", occluders)
	var fish: float = await _sample("inside_fish")
	tests.check(fish < 0.005, "dust cannot bypass fish occlusion")
	occluders.fill(Vector4.ZERO)
	_material.set_shader_parameter("occluders", occluders)
	_material.set_shader_parameter("beam_color", Color(1, 0.8, 0.55, 0))
	var off: float = await _sample("off")
	tests.check(off < 0.005, "a zero-power lamp produces no beam or motes")
	_material.set_shader_parameter("beam_color", Color(1, 0.8, 0.55, 0.02))
	var dim: float = await _sample("dim")
	_material.set_shader_parameter("beam_color", Color(1, 0.8, 0.55, 0.021))
	var next_dim: float = await _sample("next_dim")
	tests.check(next_dim >= dim - 0.003 && next_dim - dim < 0.015,
		"nearby powers have a continuous beam response")
	_material.set_shader_parameter("dust_mote_density", 0.0)
	_material.set_shader_parameter("forward_scatter", 0.8)
	_material.set_shader_parameter("beam_color", Color(1, 0.8, 0.55, 0.1))
	var backscatter: float = await _sample("camera_above_backscatter")
	_set_view(true)
	var forward: float = await _sample("camera_below_forward_scatter")
	tests.check(forward > backscatter + 0.03,
		"forward scatter is stronger when photons continue toward an observer below the lamp")
	for row: Dictionary in _rows:
		tests.in_range(float(row["luma"]), 0.0, 1.0, "finite masked beam output")
	var file := FileAccess.open(_output.path_join("measurements.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_rows, "\t"))
	file.close()
	print("[god_ray_mask_probe] ", JSON.stringify(_rows))
	var result: int = tests.finish()
	_viewport.queue_free()
	await process_frame
	quit(result)


func _set_view(below: bool) -> void:
	_camera.position = _patch_position + Vector3(0, -3 if below else 3, 0)
	_camera.look_at(_patch_position, Vector3.FORWARD)


func _sample(label_text: String) -> float:
	await process_frame
	await RenderingServer.frame_post_draw
	var pixels: Image = _viewport.get_texture().get_image()
	var luma: float = 0.0
	for y in range(62, 66):
		for x in range(62, 66):
			luma += pixels.get_pixel(x, y).get_luminance() / 16.0
	pixels.save_png(_output.path_join(label_text + ".png"))
	_rows.append({"label": label_text, "luma": luma})
	return luma
