extends SceneTree

# FrameMetrics contract (VISUAL_DIRECTIONS #20).
#
# The point of FrameMetrics is that a visual regression becomes a failing
# number instead of a slow drift nobody notices. That only holds if the
# numbers are right, so these assert the maths against synthetic images whose
# answers are known by construction — including one built to reproduce the
# 2026-09-13 baseline failure (a frame collapsed into a single mid-grey) and
# one built to pass.


const Metrics = preload("res://scripts/frame_metrics.gd")


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_frame_metrics")

	# --- Luma matches the shader coefficients ---
	t.approx(Metrics.luma8(Color(1, 1, 1)), 255.0, "white is 255", 0.01)
	t.approx(Metrics.luma8(Color(0, 0, 0)), 0.0, "black is 0", 0.01)
	t.approx(Metrics.luma8(Color(0, 1, 0)), 255.0 * 0.587,
		"green carries the 0.587 coefficient", 0.5)

	# --- A flat image has no spread and total midtone mass ---
	var flat := _solid(64, 64, Color(0.55, 0.55, 0.55))
	var flat_r: Dictionary = Metrics.read(flat)
	t.equals(int(flat_r["samples"]), 64 * 64, "reads every pixel at step 1")
	t.equals(int(flat_r["unique_colors"]), 1, "one colour in a solid image")
	t.approx(Metrics.tonal_spread(flat_r), 0.0, "solid image has no spread", 0.01)
	t.approx(float(flat_r["midtone_mass"]), 1.0,
		"every pixel of a solid image is in the midtone band", 0.001)
	t.approx(float(flat_r["sat_p50"]), 0.0, "grey is unsaturated", 0.001)

	# --- Percentiles track a known ramp ---
	# A vertical greyscale ramp: row y has value y/(h-1). p50 must land mid.
	var ramp := _ramp(1, 256)
	var ramp_r: Dictionary = Metrics.read(ramp)
	t.in_range(float(ramp_r["p50"]), 120.0, 136.0, "ramp median sits mid-scale")
	t.in_range(float(ramp_r["p05"]), 0.0, 20.0, "ramp p05 is near black")
	t.in_range(float(ramp_r["p99"]), 235.0, 255.0, "ramp p99 is near white")
	t.check(float(ramp_r["midtone_mass"]) < 0.25,
		"a full ramp is not midtone-massed (got %.3f)" % float(ramp_r["midtone_mass"]))

	# --- step subsamples without moving the distribution ---
	var ramp_step: Dictionary = Metrics.read(ramp, Rect2i(), 4)
	t.equals(int(ramp_step["samples"]), 64, "step 4 on a 256-row image takes 64 rows")
	t.approx(float(ramp_step["p50"]), float(ramp_r["p50"]),
		"subsampling does not move the median", 6.0)

	# --- rect restricts the read ---
	var split := _solid(32, 32, Color(0.1, 0.1, 0.1))
	for y in 32:
		for x in range(16, 32):
			split.set_pixel(x, y, Color(0.9, 0.9, 0.9))
	var left: Dictionary = Metrics.read(split, Rect2i(0, 0, 16, 32))
	var right: Dictionary = Metrics.read(split, Rect2i(16, 0, 16, 32))
	t.approx(float(left["p50"]), 25.5, "left half reads dark", 1.5)
	t.approx(float(right["p50"]), 229.5, "right half reads light", 1.5)
	t.approx(Metrics.separation(right, left), 204.0,
		"separation is front minus back", 3.0)

	# --- The 2026-09-13 baseline must FAIL the grade ---
	# Reproduces the measured disease: everything inside a narrow band around
	# luma 143, no highlight, no shadow, and far more colours than the palette.
	var sick := _noisy_band(160, 90, 143.0, 12.0, 4096)
	var sick_r: Dictionary = Metrics.read(sick)
	var sick_grade: Array[Dictionary] = Metrics.grade(sick_r, 48)
	var sick_failures: int = 0
	for row in sick_grade:
		if not bool(row["ok"]):
			sick_failures += 1
	t.check(sick_failures >= 3,
		"a flat mid-grey frame must fail at least 3 of the 4 grades (failed %d)"
			% sick_failures)
	t.check(float(sick_r["midtone_mass"]) > Metrics.MIDTONE_MASS_MAX,
		"flat frame is midtone-massed")
	t.approx(float(sick_r["highlight_fraction"]), 0.0,
		"a frame whose brightest pixel is 155 has no highlight at all", 0.0001)

	# The highlight metric must still discriminate after being redefined.
	# A frame with a small genuine specular passes; a uniformly brighter frame
	# with no specular does not — that is the property the first version of
	# this threshold (p99 >= 200) got backwards.
	var bright_flat := _noisy_band(160, 90, 190.0, 6.0, 512)
	var bf: Dictionary = Metrics.read(bright_flat)
	t.approx(float(bf["highlight_fraction"]), 0.0,
		"a merely BRIGHT flat frame still has no highlight", 0.0001)
	var speckled := _solid(160, 90, Color(0.45, 0.48, 0.5))
	for i in 40:
		speckled.set_pixel(20 + i, 30, Color(0.98, 0.97, 0.94))
	var sp: Dictionary = Metrics.read(speckled)
	t.check(float(sp["highlight_fraction"]) >= Metrics.HIGHLIGHT_FRACTION_MIN,
		"40 blown pixels in 14,400 is a highlight (got %.4f)"
			% float(sp["highlight_fraction"]))

	# --- A frame with real structure must PASS ---
	var well := _structured(160, 90)
	var well_r: Dictionary = Metrics.read(well)
	for row in Metrics.grade(well_r, 48):
		t.check(bool(row["ok"]),
			"structured frame should pass %s (got %.3f, want %s)"
				% [row["name"], float(row["value"]), row["want"]])

	# --- The highlight level follows the palette, not an absolute ---
	# A night palette tops out around 154 by construction; demanding 200 of it
	# asks the frame to leave its own palette.
	t.approx(Metrics.highlight_level_for(255.0), 255.0 * Metrics.HIGHLIGHT_OF_PALETTE_MAX,
		"a full-range palette gets the full-range level", 0.5)
	var night_level: float = Metrics.highlight_level_for(154.0)
	t.check(night_level < 200.0,
		"a night palette's level must be reachable within it (got %.0f)" % night_level)
	t.check(night_level > 60.0, "…but not so low that any midtone counts")
	t.approx(Metrics.highlight_level_for(0.0), Metrics.HIGHLIGHT_LEVEL,
		"an unknown palette falls back to the absolute level", 0.01)
	t.check(Metrics.highlight_level_for(-50.0) > 0.0,
		"a nonsense palette maximum does not produce a negative level")
	# The level actually changes what read() counts.
	var half := _solid(20, 20, Color(0.6, 0.6, 0.6))  # luma ~153
	t.approx(float(Metrics.read(half, Rect2i(), 1, 200.0)["highlight_fraction"]), 0.0,
		"153 is not a highlight against a 200 level", 0.001)
	t.approx(float(Metrics.read(half, Rect2i(), 1, 120.0)["highlight_fraction"]), 1.0,
		"153 is a highlight against a 120 level", 0.001)
	t.approx(float(Metrics.read(half)["max_luma"]), 153.0,
		"the report carries the brightest sample", 1.5)

	# --- Stipple measures spatial noise, which colour count cannot ---
	# Once the palette is locked a frame is 40 colours whether they are laid
	# down in calm fields or as salt-and-pepper. Only adjacency can tell.
	t.approx(float(Metrics.read(flat)["stipple"]), 0.0,
		"a solid field has no stipple", 0.001)
	var checker := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			checker.set_pixel(x, y, Color.WHITE if (x + y) % 2 == 0 else Color.BLACK)
	t.approx(float(Metrics.read(checker)["stipple"]), 1.0,
		"a checkerboard is entirely stipple", 0.001)
	t.check(float(Metrics.read(checker)["stipple"]) > Metrics.STIPPLE_MAX,
		"a checkerboard must fail the dither budget")
	var bands_r: Dictionary = Metrics.read(_structured(160, 90))
	t.approx(float(bands_r["stipple"]), 0.0,
		"hard EDGES are not stipple — a frame of flat bands scores ~0", 0.02)
	t.check(float(bands_r["stipple"]) < Metrics.STIPPLE_MAX,
		"a frame of flat bands passes the density budget")
	# Two frames of identical colour COUNT, opposite noise — the case the
	# colour-count metric is blind to.
	t.equals(int(Metrics.read(checker)["unique_colors"]),
		int(Metrics.read(_halves(64, 64))["unique_colors"]),
		"checkerboard and split field have the same colour count")
	t.check(float(Metrics.read(checker)["stipple"])
			> float(Metrics.read(_halves(64, 64))["stipple"]) + 0.9,
		"…and completely different stipple")
	t.approx(float(Metrics.read(_halves(64, 64))["stipple"]), 0.0,
		"one hard edge down the middle is not stipple", 0.01)

	# --- Stipple CONTRAST is the other half: how loud each grain is ---
	t.approx(float(Metrics.read(checker)["stipple_contrast"]), 255.0,
		"a black/white checkerboard is maximum-contrast stipple", 1.0)
	var soft := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			soft.set_pixel(x, y,
				Color(0.50, 0.50, 0.50) if (x + y) % 2 == 0 else Color(0.54, 0.54, 0.54))
	var soft_r: Dictionary = Metrics.read(soft)
	t.approx(float(soft_r["stipple"]), 1.0,
		"a fine dither is dense by construction", 0.001)
	t.check(float(soft_r["stipple_contrast"]) <= Metrics.STIPPLE_CONTRAST_MAX,
		"…but a small step passes the loudness budget (got %.1f)"
			% float(soft_r["stipple_contrast"]))
	# The pair the density metric alone cannot separate.
	t.check(float(Metrics.read(checker)["stipple_contrast"])
			> float(soft_r["stipple_contrast"]) + 100.0,
		"equal density, opposite loudness")
	t.approx(float(Metrics.read(flat)["stipple_contrast"]), 0.0,
		"no differing pairs means no step, not a divide by zero", 0.001)

	# --- neighbor_stride compares render pixels, not upscaled duplicates ---
	# A 3x nearest upscale of a checkerboard: at stride 1 only a third of
	# neighbours differ; at stride 3 all of them do.
	var up := Image.create(96, 96, false, Image.FORMAT_RGB8)
	for y in 96:
		for x in 96:
			up.set_pixel(x, y,
				Color.WHITE if ((x / 3) + (y / 3)) % 2 == 0 else Color.BLACK)
	var naive: float = float(Metrics.read(up, Rect2i(), 1, Metrics.HIGHLIGHT_LEVEL, 1)["stipple"])
	var strided: float = float(Metrics.read(up, Rect2i(), 1, Metrics.HIGHLIGHT_LEVEL, 3)["stipple"])
	t.check(naive < 0.4,
		"stride 1 on a 3x upscale understates stipple (got %.3f)" % naive)
	t.approx(strided, 1.0, "stride 3 recovers the true stipple", 0.02)

	# --- palette_excess is a ratio, and guards divide-by-zero ---
	t.approx(Metrics.palette_excess({"unique_colors": 96}, 48), 2.0,
		"96 colours against a 48 palette is 2x", 0.001)
	t.approx(Metrics.palette_excess({"unique_colors": 96}, 0), 0.0,
		"zero palette size is not a crash", 0.001)

	# --- Empty / degenerate inputs return empty, not garbage ---
	t.check(Metrics.read(null).is_empty(), "null image reads empty")
	t.check(Metrics.read(flat, Rect2i(200, 200, 10, 10)).is_empty(),
		"a rect entirely outside the image reads empty")
	t.check(Metrics.format_report("x", {}).contains("empty"),
		"empty report formats without crashing")

	quit(t.finish())


# Same two colours as the checkerboard, arranged as two blocks.
func _halves(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, Color.WHITE if x < w / 2 else Color.BLACK)
	return img


func _solid(w: int, h: int, c: Color) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(c)
	return img


# Vertical greyscale ramp, one column wide.
func _ramp(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		var v: float = float(y) / float(maxi(h - 1, 1))
		for x in w:
			img.set_pixel(x, y, Color(v, v, v))
	return img


# A frame whose values all sit inside +/- `half` of `centre`, spread over
# `colors` distinct greys — the shape of the measured baseline.
func _noisy_band(w: int, h: int, centre: float, half: float, colors: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260913
	for y in h:
		for x in w:
			var step: int = rng.randi_range(0, maxi(colors - 1, 1))
			var v: float = (centre + (float(step) / float(maxi(colors - 1, 1)) - 0.5)
				* 2.0 * half) / 255.0
			# Tiny per-channel jitter so the colour count is high, the way a
			# post chain that runs grain and FXAA after quantize makes it high.
			img.set_pixel(x, y, Color(v, v + 0.002 * float(step % 3),
				v - 0.002 * float(step % 5)))
	return img


# A frame with a value structure: four well-separated values in roughly equal
# measure, a true shadow and a true highlight. Not a picture — the point is
# that a legibly-staged frame passes the same grade the flat one fails.
func _structured(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var bands: Array[Color] = [
		Color(0.09, 0.10, 0.13),  # background / shadow
		Color(0.38, 0.43, 0.46),  # mid ground
		Color(0.66, 0.70, 0.69),  # lit subject
		Color(0.95, 0.96, 0.92),  # highlight
	]
	for y in h:
		var band: int = clampi(int(float(y) / float(h) * float(bands.size())),
			0, bands.size() - 1)
		for x in w:
			img.set_pixel(x, y, bands[band])
	return img
