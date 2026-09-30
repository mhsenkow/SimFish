class_name BakedCaustics
extends RefCounted

# Tileable caustic web, baked once on the CPU and sampled by every caustic
# surface (substrate, substrate next-pass, the water volume's floor web and
# surface ceiling).
#
# PERFORMANCE_UNTHROTTLED #83 started this as a potato-tier stand-in: a 64 px
# product of two sines, which read as a sine grid rather than light. The live
# path it stood in for evaluated a 3x3 Worley search (9 hash + sin taps) two or
# three times per fragment — on the water volume, up to five times, over most
# of the screen. That is the single most expensive thing the tank shaders did,
# for a pattern that is periodic anyway.
#
# So the bake is now the real thing: periodic Worley F2-F1 (the classic
# caustic filament web), two uncorrelated layers in R and G with different
# cell counts so their sum never visibly repeats. Shaders scroll the two
# layers in different directions at different scales and combine them, which
# is what makes the web morph instead of slide — and costs two texture reads.
# `caustic_baked` = 1 selects it on every tier; 0 keeps the procedural Worley
# path for anything that has not bound the texture.

const TILE: int = 64
# Cells per tile edge for each channel. Coprime so R and G tile at different
# periods; 4 cells over 64 px keeps a filament ~2-3 px wide after the gamma.
const CELLS_R: int = 4
const CELLS_G: int = 5

static var _tex: ImageTexture = null


static func reset_for_test() -> void:
	_tex = null


# Pure: periodic F2-F1 at pixel (x, y) for a tile with `cells` feature cells
# per edge. Feature points are hashed per cell and wrap, so the result tiles.
static func web_at(x: int, y: int, cells: int, seed_v: int) -> float:
	var cell_px: float = float(TILE) / float(cells)
	var fx: float = (float(x) + 0.5) / cell_px
	var fy: float = (float(y) + 0.5) / cell_px
	var gx: int = int(floor(fx))
	var gy: int = int(floor(fy))
	var d1: float = 8.0
	var d2: float = 8.0
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var cx: int = gx + ox
			var cy: int = gy + oy
			var wx: int = posmod(cx, cells)
			var wy: int = posmod(cy, cells)
			var h: int = hash(Vector3i(wx, wy, seed_v))
			var px: float = float(cx) + 0.12 + 0.76 * float(h & 1023) / 1023.0
			var py: float = float(cy) + 0.12 + 0.76 * float((h >> 10) & 1023) / 1023.0
			var d: float = Vector2(px - fx, py - fy).length()
			if d < d1:
				d2 = d1
				d1 = d
			elif d < d2:
				d2 = d
	# Invert so the cell boundaries (d2 ~ d1) are bright filaments and the cell
	# interiors are dark, then sharpen: real caustics are thin bright lines.
	var edge: float = clampf(1.0 - (d2 - d1) * 2.2, 0.0, 1.0)
	return pow(edge, 3.2)


static func texture() -> ImageTexture:
	if _tex != null:
		return _tex
	var data := PackedByteArray()
	data.resize(TILE * TILE * 4)
	var i: int = 0
	for y in TILE:
		for x in TILE:
			var r: float = web_at(x, y, CELLS_R, 17)
			var g: float = web_at(x, y, CELLS_G, 91)
			data[i] = int(r * 255.0)
			data[i + 1] = int(g * 255.0)
			# B keeps the legacy single-channel read (potato path sampled .r):
			# the two layers crossed, which is where caustics are brightest.
			data[i + 2] = int(clampf(r * 0.6 + r * g * 1.4, 0.0, 1.0) * 255.0)
			data[i + 3] = 255
			i += 4
	var img := Image.create_from_data(TILE, TILE, false, Image.FORMAT_RGBA8, data)
	_tex = ImageTexture.create_from_image(img)
	return _tex


# Binds the tile. `shader_tier` is kept for callers; the bake is used on every
# tier now because it is both cheaper and closer to a caustic than the live
# Worley search it replaced.
static func apply_to_material(mat: ShaderMaterial, _shader_tier: int = 0) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("baked_caustics_tex", texture())
	mat.set_shader_parameter("caustic_baked", 1.0)
