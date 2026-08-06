# Headless smoke: plant-green swatches must classify to cool bank (greens 8–15).
# Mirrors classify_bank() in palette_quantize.gdshader — update both if logic changes.
extends SceneTree

const COOL_BANK := 0
const NEUTRAL_BANK := 1
const WARM_BANK := 2

# Representative leaf greens (sRGB-ish) that must NOT quantize to neutral mud.
const LEAF_SWATCHES: Array[Color] = [
	Color8(56, 152, 88),
	Color8(72, 176, 96),
	Color8(40, 128, 72),
	Color8(88, 184, 104),
	Color8(48, 136, 80),
]


static func classify_bank(c: Color) -> int:
	var r: float = c.r
	var g: float = c.g
	var b: float = c.b
	var maxc: float = maxf(maxf(r, g), b)
	var minc: float = minf(minf(r, g), b)
	var sat: float = (maxc - minc) / maxf(maxc, 0.001)
	var luma: float = r * 0.299 + g * 0.587 + b * 0.114
	if sat < 0.22:
		return NEUTRAL_BANK
	if r > b and g > b * 0.92 and g < r * 1.08 and g >= r * 0.42 and sat < 0.82 and luma < 0.78:
		return NEUTRAL_BANK
	if r > g and r > b and (r - g) < 0.18 and (g - b) > 0.02 and sat < 0.55 and luma < 0.70:
		return NEUTRAL_BANK
	if b > r and b >= g * 0.85:
		return COOL_BANK
	if r > b and r >= g * 0.92 and (r - g) > 0.12:
		return WARM_BANK
	if g > b * 1.15:
		if sat >= 0.25 and g >= r * 0.92:
			return COOL_BANK
		return NEUTRAL_BANK
	return COOL_BANK


static func rgb_to_hue_deg(c: Color) -> float:
	var r: float = c.r
	var g: float = c.g
	var b: float = c.b
	var maxc: float = maxf(maxf(r, g), b)
	var minc: float = minf(minf(r, g), b)
	if maxc - minc < 0.001:
		return 0.0
	var h: float = 0.0
	if maxc == r:
		h = (g - b) / (maxc - minc)
	elif maxc == g:
		h = 2.0 + (b - r) / (maxc - minc)
	else:
		h = 4.0 + (r - g) / (maxc - minc)
	h *= 60.0
	if h < 0.0:
		h += 360.0
	return h


func _init() -> void:
	var failed: PackedStringArray = []
	for sw in LEAF_SWATCHES:
		var bank: int = classify_bank(sw)
		if bank != COOL_BANK:
			failed.append("leaf %s classified bank %d (want cool/0)" % [sw, bank])
		var hue: float = rgb_to_hue_deg(sw)
		if hue < 90.0 or hue > 165.0:
			failed.append("leaf %s hue %.1f outside 90–165°" % [sw, hue])
	if not failed.is_empty():
		for line in failed:
			push_error(line)
		quit(1)
		return
	print("smoke_palette_green: OK")
	quit()
