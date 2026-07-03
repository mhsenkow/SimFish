extends SceneTree

# SYSTEMIC #19–21 + PERFORMANCE_UNTHROTTLED #80–88 shader receipts.

const _VoxelMatScript = preload("res://scripts/voxel_mat.gd")
const _ShadowAuditScript = preload("res://scripts/shadow_audit.gd")
const _ShaderWarmCaptureScript = preload("res://scripts/shader_warm_capture.gd")
const _BakedCausticsScript = preload("res://scripts/baked_caustics.gd")
const _RenderResolutionAuditScript = preload("res://scripts/render_resolution_audit.gd")
const _QuantizePotatoShader = preload("res://shaders/palette_quantize_potato.gdshader")
const _WaterShader = preload("res://shaders/water.gdshader")


func _initialize() -> void:
	if not _run_all():
		quit(1)
		return
	print("[smoke_shader_perf] OK")
	quit(0)


func _fail(msg: String) -> bool:
	push_error(msg)
	return false


func _run_all() -> bool:
	_ShaderWarmCaptureScript.reset_for_test()
	_VoxelMatScript.set_shader_perf_tier(2)
	if _VoxelMatScript.shader_perf_tier() != 2:
		return _fail("set_shader_perf_tier failed")
	var mat: ShaderMaterial = _VoxelMatScript.make_substrate_caustic(Color(0.5, 0.4, 0.3))
	if int(mat.get_shader_parameter("blob_shadow_max")) != 16:
		return _fail("potato tier must cap blob shadows at 16")
	_VoxelMatScript.set_shader_perf_tier(0)
	var mat2: ShaderMaterial = _VoxelMatScript.make_substrate_caustic(Color(0.6, 0.5, 0.4))
	if int(mat2.get_shader_parameter("blob_shadow_max")) != 32:
		return _fail("full tier must use 32 blob shadows")
	# #80 — gameplay lights stay shadowless
	var lights := Node3D.new()
	root.add_child(lights)
	var ok_light := OmniLight3D.new()
	ok_light.shadow_enabled = false
	lights.add_child(ok_light)
	if not _ShadowAuditScript.smoke_ok(lights):
		return _fail("shadow audit must pass for shadowless scene")
	var bad := DirectionalLight3D.new()
	bad.shadow_enabled = true
	lights.add_child(bad)
	if _ShadowAuditScript.smoke_ok(lights):
		return _fail("shadow audit must fail when shadows enabled")
	# #83 baked caustics texture
	_BakedCausticsScript.reset_for_test()
	var caustic_tex: Texture2D = _BakedCausticsScript.texture()
	if caustic_tex.get_width() < 32:
		return _fail("baked caustics texture missing")
	# #84 blob data texture path
	_VoxelMatScript.update_substrate_blob_shadows([Vector4(1.0, 2.0, 3.0, 0.5)])
	# #86 internal render contract
	if not _RenderResolutionAuditScript.internal_size_ok(512, 288):
		return _fail("512x288 internal contract")
	# #87 warm list populated by tier + warm pass
	_VoxelMatScript.warm_shader_variants(null)
	if _ShaderWarmCaptureScript.count() < 2:
		return _fail("shader warm capture list empty")
	if _ShaderWarmCaptureScript.replay_warm() < 1:
		return _fail("shader warm replay failed")
	var potato_src: String = FileAccess.get_file_as_string(_QuantizePotatoShader.resource_path)
	if potato_src.contains("outline_strength") or potato_src.contains("crt_strength"):
		return _fail("potato quantize must compile features out")
	if not ResourceLoader.exists(_QuantizePotatoShader.resource_path):
		return _fail("palette_quantize_potato.gdshader missing")
	# #88 water waves live in vertex stage
	var water_src: String = _WaterShader.resource_path
	var water_code: String = FileAccess.get_file_as_string(water_src)
	if not water_code.contains("void vertex()") or not water_code.contains("surface_lift"):
		return _fail("water shader must displace in vertex stage")
	var frag_idx: int = water_code.find("void fragment()")
	var frag_tail: String = water_code.substr(frag_idx) if frag_idx >= 0 else water_code
	if frag_tail.contains("wave_amplitude"):
		return _fail("water waves must not be recomputed in fragment")
	return true
