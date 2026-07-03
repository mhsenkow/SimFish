class_name BakedCaustics
extends RefCounted

# PERFORMANCE_UNTHROTTLED #83 — tileable caustic scroll texture for potato tier.

const TILE: int = 64

static var _tex: ImageTexture = null


static func reset_for_test() -> void:
	_tex = null


static func texture() -> ImageTexture:
	if _tex != null:
		return _tex
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	for y in TILE:
		for x in TILE:
			var u: float = float(x) / float(TILE)
			var v: float = float(y) / float(TILE)
			var c1: float = sin(u * 17.3 + v * 11.7) * 0.5 + 0.5
			var c2: float = sin(u * 31.1 - v * 23.4 + 1.7) * 0.5 + 0.5
			var bright: float = clampf(c1 * c2 * 1.35, 0.0, 1.0)
			img.set_pixel(x, y, Color(bright, bright, bright * 0.92, 1.0))
	_tex = ImageTexture.create_from_image(img)
	return _tex


static func apply_to_material(mat: ShaderMaterial, shader_tier: int = 0) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("baked_caustics_tex", texture())
	mat.set_shader_parameter("caustic_baked", 1.0 if shader_tier >= 2 else 0.0)
