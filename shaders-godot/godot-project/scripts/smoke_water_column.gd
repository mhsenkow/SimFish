extends SceneTree

# Pins the water-column extinction contract.
#
# Water is not a blue filter over the picture — it is a medium that eats the
# long wavelengths first. That is what separates "looking through water" from
# "objects in air with a tint", and it gives the tank free atmospheric
# perspective. The curve has to stay gentle: the palette quantizer downstream
# only has 48 slots, and an over-strong absorption pushes every deep pixel into
# the same cyan corner of the ramp.

const _Vox := preload("res://scripts/voxel_mat.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	# ---- Absorption is wavelength-ordered ------------------------------------
	var clear: Vector3 = _Vox.WATER_ABSORB_CLEAR
	_assert(failed, clear.x > clear.y and clear.y > clear.z,
		"clear water absorbs red > green > blue (%s)" % clear)
	_assert(failed, clear.x / maxf(clear.z, 0.0001) > 3.0,
		"red is absorbed several times harder than blue")
	# Tannins invert it — blackwater keeps amber and loses blue.
	var tan: Vector3 = _Vox.WATER_ABSORB_TANNIN
	_assert(failed, tan.z > tan.x,
		"tannin water absorbs blue hardest — what survives is amber (%s)" % tan)

	# ---- The packed uniforms are shaped right ---------------------------------
	# Asserted through the pure builder, not by reading the globals back: the
	# headless dummy renderer does not store them, so a read after set() is null.
	var u: Array = _Vox.water_column_uniforms(6.5, 0.62, 0.0, 0.0)
	var abs4: Vector4 = u[0]
	var body4: Vector4 = u[1]
	_assert(failed, is_equal_approx(abs4.w, 0.62), "strength rides in absorb.a")
	_assert(failed, is_equal_approx(body4.w, 6.5), "water surface Y rides in body.a")
	_assert(failed, abs4.x > abs4.y and abs4.y > abs4.z,
		"packed absorption keeps the wavelength order")
	# The shader short-circuits on absorb.a, so 0 must survive the clamp.
	var offu: Array = _Vox.water_column_uniforms(6.5, 0.0)
	_assert(failed, is_equal_approx((offu[0] as Vector4).w, 0.0),
		"strength 0 packs as 0 so every shader short-circuits")
	# And it must be bounded — a bad config value cannot black the tank out.
	var hot: Array = _Vox.water_column_uniforms(6.5, 99.0)
	_assert(failed, (hot[0] as Vector4).w <= 2.0, "strength is clamped")

	# ---- Tannins and turbidity move it the right way -------------------------
	var tannu: Vector4 = _Vox.water_column_uniforms(6.5, 0.62, 1.0, 0.0)[1]
	_assert(failed, tannu.x > tannu.z,
		"tannin water body colour is warm (%.3f vs %.3f)" % [tannu.x, tannu.z])
	var tanna: Vector4 = _Vox.water_column_uniforms(6.5, 0.62, 1.0, 0.0)[0]
	_assert(failed, tanna.z > tanna.x,
		"tannin water eats blue hardest — blackwater keeps amber")
	var murk: Vector4 = _Vox.water_column_uniforms(6.5, 0.62, 0.0, 1.0)[0]
	_assert(failed, murk.x > abs4.x and murk.z > abs4.z,
		"turbidity attenuates broadly, not selectively")
	var murk_body: Vector4 = _Vox.water_column_uniforms(6.5, 0.62, 0.0, 1.0)[1]
	_assert(failed, murk_body.z < body4.z + 0.12 and murk_body.x > body4.x,
		"a murky tank reads milky rather than bluer")

	# ---- The curve stays in the tasteful band --------------------------------
	# The palette quantizer downstream only has 48 slots; an over-strong
	# absorption pushes every deep pixel into the same cyan corner of the ramp.
	var kr: float = clear.x
	var kb: float = clear.z
	var near_r: float = _Vox.water_transmittance(kr, 1.0, 11.0, 0.62)
	var deep_r: float = _Vox.water_transmittance(kr, 4.9, 16.0, 0.62)
	var far_r: float = _Vox.water_transmittance(kr, 4.9, 22.0, 0.62)
	_assert(failed, near_r > 0.85,
		"a near fish keeps most of its red (%.2f) — no cyan wash" % near_r)
	_assert(failed, deep_r < near_r and far_r < deep_r,
		"red falls off monotonically with depth and distance")
	_assert(failed, far_r > 0.6,
		"even the far corner stays readable, not drowned (%.2f)" % far_r)
	var far_b: float = _Vox.water_transmittance(kb, 4.9, 22.0, 0.62)
	_assert(failed, far_b - far_r > 0.1,
		"the far corner shifts toward blue, it does not just dim (%.2f vs %.2f)"
			% [far_b, far_r])
	# Above the waterline and with the effect off, transmittance is exactly 1.
	_assert(failed, is_equal_approx(_Vox.water_transmittance(kr, 0.0, 20.0, 0.62), 1.0),
		"nothing above the waterline is touched")
	_assert(failed, is_equal_approx(_Vox.water_transmittance(kr, 5.0, 20.0, 0.0), 1.0),
		"strength 0 is a true no-op")

	# ---- Above the waterline is untouched ------------------------------------
	# depth <= 0 short-circuits in the shader; mirror that expectation here so a
	# future edit that drops the guard trips this.
	var inc: String = FileAccess.get_file_as_string("res://shaders/palette_tint.gdshaderinc")
	_assert(failed, inc.contains("if (depth <= 0.0)"),
		"emergent growth and floaters skip the water column")
	_assert(failed, inc.contains("if (strength < 0.001)"),
		"the effect short-circuits when disabled")
	_assert(failed, inc.contains("view_dist * 0.35"),
		"the view term stays weighted down — most of that path is air")

	# ---- Wiring --------------------------------------------------------------
	# world._push_water_column() used to read only its cached _cfg_node, which
	# is null on some boot paths — and then silently fell back to the constant,
	# ignoring whatever the player had set.
	var wsrc: String = FileAccess.get_file_as_string("res://scripts/world.gd")
	_assert(failed, wsrc.contains("cfg = get_node_or_null(\"/root/TankConfig\")"),
		"world resolves TankConfig even when its cached node is null")
	_assert(failed, wsrc.contains("_push_water_column()"),
		"world pushes the water column on its ambient tick")
	var cfg_src: String = FileAccess.get_file_as_string("res://scripts/tank_config.gd")
	_assert(failed, cfg_src.contains("water_extinction"),
		"the strength is a persisted setting, not a hardcoded constant")
	_assert(failed, cfg_src.contains('cfg.set_value("render", "water_extinction"'),
		"the setting is saved")

	# ---- Every in-tank surface applies it ------------------------------------
	# If one shader misses it, that surface floats free of the depth cue and the
	# illusion breaks — the substrate staying bright is the obvious tell.
	for sh in ["voxel", "voxel_mm", "voxel_fauna_mm", "foliage", "foliage_mm",
			"substrate_opaque", "substrate_caustic"]:
		var src: String = FileAccess.get_file_as_string("res://shaders/%s.gdshader" % sh)
		_assert(failed, src.contains("apply_water_column("),
			"%s.gdshader applies the water column" % sh)

	_Vox.disable_water_column()

	if failed.is_empty():
		print("[smoke] water_column OK")
		quit(0)
	else:
		for f in failed:
			push_error("[smoke] FAIL: %s" % f)
		print("[smoke] water_column FAILED (%d)" % failed.size())
		quit(1)


func _transmit(k: float, depth: float, view: float, strength: float) -> float:
	return exp(-k * (depth + view * 0.35) * strength)


func _assert(failed: Array[String], cond: bool, label: String) -> void:
	if not cond:
		failed.append(label)
