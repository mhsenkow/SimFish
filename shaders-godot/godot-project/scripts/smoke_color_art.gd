extends SceneTree

const Art = preload("res://scripts/aesthetics_runtime.gd")

func _initialize() -> void:
	var t := TestSupport.Suite.new("smoke_color_art")
	for color in [Color8(180, 35, 48), Color8(36, 80, 175), Color8(28, 145, 95),
		Color8(204, 169, 40), Color8(164, 53, 125), Color.WHITE, Color.BLACK]:
		var hi: Color = Art.fauna_highlight_color(color)
		var lo: Color = Art.fauna_shadow_color(color)
		t.check(hi.v >= color.v, "sculpted highlight remains brighter than pigment")
		t.check(lo.v <= color.v, "sculpted shadow remains below pigment")
		t.in_range(hi.v, 0.0, 1.0, "highlight stays in gamut")
		if color.s > 0.2:
			t.approx(hi.h, color.h, "highlight preserves the animal's pigment hue", 0.001)
			t.check(hi.s >= color.s * 0.8, "highlight retains pigment chroma")
			t.approx(lo.h, color.h, "shadow preserves the animal's pigment hue", 0.001)
	var hexes: Array = Art.PLANTED_PALETTE
	t.equals(hexes.size(), 48, "planted palette retains all 48 slots")
	var image: Image = Image.load_from_file("res://palettes/planted_48.png")
	t.check(image != null, "bundled palette data loads")
	if image != null:
		t.equals(image.get_width(), 48, "bundled palette has the contracted width")
		for i in 48:
			t.equals(image.get_pixel(i, 0).to_html(false), String(hexes[i]),
				"runtime and bundled palette agree at slot %d" % i)
	var night: Image = Image.load_from_file("res://palettes/planted_48_night.png")
	t.check(night != null, "bundled moonlit palette loads")
	if night != null:
		for i in 48:
			var expected: Color = Art.night_palette_color(Color("#" + String(hexes[i])))
			t.approx(night.get_pixel(i, 0).r, expected.r, "moonlit red matches runtime", 0.004)
			t.approx(night.get_pixel(i, 0).g, expected.g, "moonlit green matches runtime", 0.004)
			t.approx(night.get_pixel(i, 0).b, expected.b, "moonlit blue matches runtime", 0.004)
	for i in range(9, 16):
		t.check(Color("#" + String(hexes[i])).get_luminance() > Color("#" + String(hexes[i-1])).get_luminance(),
			"foliage ramp increases in lightness")
	quit(t.finish())
