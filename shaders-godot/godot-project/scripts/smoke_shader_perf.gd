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
	# #86 internal render contract — all fidelity tiers, not a single size
	for tier: Vector2i in _RenderResolutionAuditScript.supported_tiers():
		if not _RenderResolutionAuditScript.internal_size_ok(tier.x, tier.y):
			return _fail("tier %dx%d must be supported" % [tier.x, tier.y])
	if not _RenderResolutionAuditScript.internal_size_ok(512, 288):
		return _fail("512x288 mid tier")
	if not _RenderResolutionAuditScript.internal_size_ok(1024, 576):
		return _fail("1024x576 desktop default tier")
	if _RenderResolutionAuditScript.internal_size_ok(640, 360):
		return _fail("non-tier 640x360 must be rejected")
	if not _RenderResolutionAuditScript.post_matches_3d(1024, 576, 1024, 576):
		return _fail("post must match 3D size")
	if _RenderResolutionAuditScript.post_matches_3d(1024, 576, 1920, 1080):
		return _fail("post must not silently match window size")
	if not _RenderResolutionAuditScript.nearest_upscale_ok(
			int(CanvasItem.TEXTURE_FILTER_NEAREST)):
		return _fail("nearest filter must pass upscale audit")
	if _RenderResolutionAuditScript.nearest_upscale_ok(
			int(CanvasItem.TEXTURE_FILTER_LINEAR)):
		return _fail("linear filter must fail upscale audit")
	if _RenderResolutionAuditScript.tier_label(1024, 576) != "desktop":
		return _fail("desktop tier label")
	if _RenderResolutionAuditScript.DEFAULT_INTERNAL != Vector2i(1024, 576):
		return _fail("shipping default must be 1024x576")
	var same_aspect: Vector2i = _RenderResolutionAuditScript.size_for_window(
		Vector2i(1024, 576), Vector2(1536, 864))
	if same_aspect != Vector2i(1024, 576):
		return _fail("16:9 window must keep the desktop tier")
	var tall: Vector2i = _RenderResolutionAuditScript.size_for_window(
		Vector2i(1024, 576), Vector2(1600, 1000))
	var tall_aspect: float = float(tall.x) / float(tall.y)
	if absf(tall_aspect - 1.6) > 0.03:
		return _fail("16:10 window must match render aspect, got %s" % str(tall))
	if absf(float(tall.x * tall.y) - float(1024 * 576)) / float(1024 * 576) > 0.08:
		return _fail("window fit must keep the tier pixel budget")
	var wide_fov: float = _RenderResolutionAuditScript.vertical_fov_for_window(55.0, 2.2)
	if absf(wide_fov - 55.0) > 0.01:
		return _fail("wider than 16:9 must keep authored fov")
	var tall_fov: float = _RenderResolutionAuditScript.vertical_fov_for_window(55.0, 1.6)
	if tall_fov <= 55.0:
		return _fail("taller than 16:9 must open vertical fov so the frame fills")
	var project_text: String = FileAccess.get_file_as_string("res://project.godot")
	if not project_text.contains('window/stretch/aspect="expand"'):
		return _fail("window stretch must expand without squashing the picture")
	if not project_text.contains('window/stretch/mode="canvas_items"'):
		return _fail("the picture must scale with the screen, not a fixed frame")
	if not project_text.contains("window/size/mode=3"):
		return _fail("the window must open fullscreen")
	if not project_text.contains('window/stretch/scale_mode="fractional"'):
		return _fail("integer window scale leaves black bars")
	if not FileAccess.get_file_as_string("res://scripts/main.gd").contains("STRETCH_SCALE"):
		return _fail("tank display must scale to the full window")
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
