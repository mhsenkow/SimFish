# Frame metrics — what a rendered frame measures, as numbers.
#
# VISUAL_DIRECTIONS #20. The visual idea docs grade themselves against a
# "capture set", and until now that grading was done by eye against images
# produced by a harness that did not render the shipped look (see
# dev/visual_capture.gd for why). An eye cannot tell you that the room wall
# and the mid-water sit four luminance levels apart; it can only tell you the
# picture feels flat.
#
# So: the frame becomes numbers, the numbers get thresholds, and a visual
# regression becomes a failing assertion instead of a slow drift nobody
# notices.
#
# EVERYTHING HERE IS PURE. Image in, Dictionary out, no scene tree, no
# rendering — so smoke_frame_metrics.gd can assert the maths against
# synthetic images headlessly, and dev/visual_capture.gd can apply the same
# functions to a real capture.
#
# The metrics are deliberately REGION-FREE where possible. A hand-picked crop
# ("the room wall is this rectangle") is only valid for one camera angle and
# rots the moment the framing changes. The global statistics below measure the
# *disease* rather than one symptom: a frame with no value structure has a
# huge midtone mass and no highlight headroom no matter where you crop it.

class_name FrameMetrics
extends RefCounted

# Luma coefficients — must match the shaders (palette_quantize.gdshader
# luma_of, voxel_mat.gd _room_calm_color) so a threshold here means the same
# thing a threshold there does.
const LUMA_R: float = 0.299
const LUMA_G: float = 0.587
const LUMA_B: float = 0.114

# Half-width of the "midtone" band around the median, in 0-255 levels. A
# frame where more than MIDTONE_MASS_MAX of pixels fall inside ±12 of the
# median has collapsed into a single value — which is exactly the state the
# 2026-09-13 baseline measured (p50 135, p75 148, p90 151).
const MIDTONE_BAND: int = 12

# ---- Thresholds -------------------------------------------------------------
#
# These are the contract. Each is a number the 2026-09-13 baseline FAILED, set
# where a frame stops reading as flat. They are deliberately not set to
# "slightly better than today" — a threshold you already pass buys nothing.

# Fraction of pixels allowed inside the midtone band. Baseline: 0.62.
const MIDTONE_MASS_MAX: float = 0.45
# The frame must contain a genuine highlight.
#
# THIS THRESHOLD WAS CHANGED AFTER THE FACT, and the reason belongs on the
# record. It began as "p99 >= 200" — the 2026-09-13 baseline measured 158 — and
# that is the wrong shape of test. A specular is SMALL by nature: the wet band
# under a light bar, a glint on a rim. Demanding it occupy the top one percent
# of the frame is demanding a bright frame, not a frame with a highlight, and
# at the hero camera angle the water surface is nearly edge-on so no amount of
# surface specular can ever fill a percentile.
#
# So the metric now measures the property directly: does a real fraction of the
# frame reach a genuinely bright level? It still discriminates — the flat
# baseline reached 158 at its very brightest, so its highlight fraction is
# zero — and it stops rewarding "make everything brighter", which is the
# opposite of what a value structure needs.
# …and the level is PALETTE-RELATIVE, not absolute.
#
# A night capture exposed the last flaw in the absolute form: the night palette
# LUT tops out around luma 154 by construction — that is what makes it a night
# palette — so "reach 200" is unreachable at midnight however bright the
# specular is. Grading a palette-locked renderer against an absolute level asks
# a frame to leave its own palette.
#
# So the contract is "the frame reaches near the top of what its palette can
# express". HIGHLIGHT_LEVEL is the fallback when the palette maximum is not
# known; pass the real one to `read()` and `grade()`.
const HIGHLIGHT_LEVEL: float = 200.0
const HIGHLIGHT_OF_PALETTE_MAX: float = 0.78
const HIGHLIGHT_FRACTION_MIN: float = 0.0015


## The luminance a frame has to reach to count as carrying a highlight, given
## the brightest colour its palette can produce.
static func highlight_level_for(palette_max_luma: float) -> float:
	if palette_max_luma <= 1.0:
		return HIGHLIGHT_LEVEL
	return maxf(60.0, clampf(palette_max_luma, 0.0, 255.0) * HIGHLIGHT_OF_PALETTE_MAX)
# …and a genuine shadow inside the subject. Baseline p05: 56.
const SHADOW_P05_MAX: int = 40
# Unique colours allowed, as a multiple of the palette size. Two dither
# candidates per fragment plus the odd blend is ~2x; the 2026-09-13 baseline
# measured 15,535 against a 48-entry palette, i.e. 324x.
const PALETTE_EXCESS_MAX: float = 4.0
# Fraction of adjacent pixel PAIRS allowed to differ — the dither budget
# (VISUAL_DIRECTIONS #7).
#
# Once the palette lock landed, "unique colours" stopped being able to see this:
# a frame is 40 colours whether those 40 are laid down in calm fields or in
# salt-and-pepper. What matters for noise is SPATIAL — how often a pixel
# differs from its neighbour.
#
# Only ALTERNATING pairs count (A B A), so a silhouette edge — which is
# supposed to differ from its background — is not scored as noise. Within a
# fully-dithered region every pair alternates, so it reads 1.0; a frame of flat
# fields with hard edges reads near 0.
const STIPPLE_MAX: float = 0.55
# Mean luminance step between two pixels that DO differ — how loud each grain
# of the stipple is, as opposed to how much of it there is.
#
# The first measurement of the frame put stipple at 0.36, comfortably inside
# budget, against an eye that read the substrate and the room wall as static.
# Both were right: the dither's DENSITY was fine and its CONTRAST was not.
# Before the palette lock the post chain smeared each pair together; snapped,
# two adjacent rungs of a 48-colour palette can be 35 luminance levels apart,
# and a checkerboard of those is texture, not a blend.
#
# 26 is about where a two-rung alternation stops reading as a tone and starts
# reading as a pattern at the shipped 3x upscale.
const STIPPLE_CONTRAST_MAX: float = 26.0
# Minimum luminance gap between a background surface and the subject it sits
# behind. VISUAL_POLISH #27 asked for "room never brighter than mid-water" and
# was satisfied at a gap of 4, which is invisible. This is what it should have
# said.
const BACKGROUND_SEPARATION_MIN: float = 40.0


static func luma8(c: Color) -> float:
	return (c.r * LUMA_R + c.g * LUMA_G + c.b * LUMA_B) * 255.0


# Percentile from a PRE-SORTED array. Split out so callers that want several
# percentiles sort once.
static func percentile_of_sorted(sorted_v: PackedFloat32Array, p: float) -> float:
	var n: int = sorted_v.size()
	if n == 0:
		return 0.0
	var idx: int = clampi(int(float(n) * clampf(p, 0.0, 1.0)), 0, n - 1)
	return sorted_v[idx]


# Core reader. Walks the image once (optionally a sub-rect), returns the
# luminance distribution, the saturation distribution and the colour count.
#
# `step` samples every Nth pixel in each axis — a 512x288 frame is 147k
# pixels and every metric here is distribution-shaped, so step 1 is affordable
# and step 2 is exact enough for a 4x speedup on window-resolution captures.
# `neighbor_stride` is the distance in IMAGE pixels between two logically
# adjacent RENDER pixels. On a window capture of a 512x288 internal render
# upscaled 3x with nearest filtering, two out of every three neighbours are
# identical by construction, and a stride of 1 would understate the stipple by
# exactly that factor. Pass the upscale factor.
static func read(img: Image, rect: Rect2i = Rect2i(), step: int = 1,
		highlight_level: float = HIGHLIGHT_LEVEL,
		neighbor_stride: int = 1) -> Dictionary:
	if img == null:
		return {}
	var full := Rect2i(0, 0, img.get_width(), img.get_height())
	var r: Rect2i = full if rect.size == Vector2i.ZERO else rect.intersection(full)
	if r.size.x <= 0 or r.size.y <= 0:
		return {}
	var st: int = maxi(step, 1)
	var lumas := PackedFloat32Array()
	var sats := PackedFloat32Array()
	var seen: Dictionary = {}
	var stride: int = maxi(neighbor_stride, 1)
	var pairs: int = 0
	var diff_pairs: int = 0
	var diff_luma_sum: float = 0.0
	var y: int = r.position.y
	while y < r.position.y + r.size.y:
		var x: int = r.position.x
		while x < r.position.x + r.size.x:
			var c: Color = img.get_pixel(x, y)
			lumas.append(luma8(c))
			var mx: float = maxf(maxf(c.r, c.g), c.b)
			var mn: float = minf(minf(c.r, c.g), c.b)
			sats.append(0.0 if mx <= 0.0001 else (mx - mn) / mx)
			# Quantize to 8-bit before counting: the capture is an 8-bit PNG
			# but Image.get_pixel hands back floats, and float noise would
			# inflate the count with colours no display can show.
			var key: int = (int(c.r * 255.0) << 16) | (int(c.g * 255.0) << 8) | int(c.b * 255.0)
			seen[key] = true
			# Right and below, one render pixel away.
			# DITHER, NOT EDGES. A neighbour that differs is not by itself
			# noise — a silhouette is supposed to differ from its background,
			# and counting boundaries would make a frame with strong shapes
			# score as static. Ordered dither alternates: A B A. An edge does
			# not: A B B. So a pair only counts when the pixel two steps on
			# comes back to the first value.
			var l_here: float = luma8(c)
			if x + stride * 2 < r.position.x + r.size.x:
				var cr: Color = img.get_pixel(x + stride, y)
				if _key_of(img.get_pixel(x + stride * 2, y)) == key:
					pairs += 1
					if _key_of(cr) != key:
						diff_pairs += 1
						diff_luma_sum += absf(l_here - luma8(cr))
			if y + stride * 2 < r.position.y + r.size.y:
				var cd: Color = img.get_pixel(x, y + stride)
				if _key_of(img.get_pixel(x, y + stride * 2)) == key:
					pairs += 1
					if _key_of(cd) != key:
						diff_pairs += 1
						diff_luma_sum += absf(l_here - luma8(cd))
			x += st
		y += st
	lumas.sort()
	sats.sort()
	var median: float = percentile_of_sorted(lumas, 0.50)
	var lo: float = median - float(MIDTONE_BAND)
	var hi: float = median + float(MIDTONE_BAND)
	var in_band: int = 0
	var bright: int = 0
	var brightest: float = 0.0
	for l in lumas:
		if l >= lo and l <= hi:
			in_band += 1
		if l >= highlight_level:
			bright += 1
		if l > brightest:
			brightest = l
	var n: int = lumas.size()
	return {
		"samples": n,
		"p01": percentile_of_sorted(lumas, 0.01),
		"p05": percentile_of_sorted(lumas, 0.05),
		"p25": percentile_of_sorted(lumas, 0.25),
		"p50": median,
		"p75": percentile_of_sorted(lumas, 0.75),
		"p95": percentile_of_sorted(lumas, 0.95),
		"p99": percentile_of_sorted(lumas, 0.99),
		"mean": _mean(lumas),
		"sat_p50": percentile_of_sorted(sats, 0.50),
		"sat_p95": percentile_of_sorted(sats, 0.95),
		"unique_colors": seen.size(),
		"midtone_mass": 0.0 if n == 0 else float(in_band) / float(n),
		"highlight_fraction": 0.0 if n == 0 else float(bright) / float(n),
		"highlight_level": highlight_level,
		"max_luma": brightest,
		"stipple": 0.0 if pairs == 0 else float(diff_pairs) / float(pairs),
		"stipple_contrast": 0.0 if diff_pairs == 0 else diff_luma_sum / float(diff_pairs),
	}


static func _key_of(c: Color) -> int:
	return (int(c.r * 255.0) << 16) | (int(c.g * 255.0) << 8) | int(c.b * 255.0)


static func _mean(v: PackedFloat32Array) -> float:
	if v.is_empty():
		return 0.0
	var acc: float = 0.0
	for x in v:
		acc += x
	return acc / float(v.size())


# Spread between the 5th and 95th percentile — the working tonal range of the
# frame, ignoring the handful of outlier pixels at each end.
static func tonal_spread(report: Dictionary) -> float:
	return float(report.get("p95", 0.0)) - float(report.get("p05", 0.0))


# How far the brightest content sits below white. A frame with no specular,
# no wet glint and a linear tonemap leaves 97 levels of headroom unused.
static func highlight_headroom(report: Dictionary) -> float:
	return 255.0 - float(report.get("p99", 0.0))


# Ratio of colours actually emitted to colours the palette declares. 1.0 means
# perfect palette lock; ordered dither between two neighbours pushes it to ~2.
static func palette_excess(report: Dictionary, palette_size: int) -> float:
	if palette_size <= 0:
		return 0.0
	return float(report.get("unique_colors", 0)) / float(palette_size)


# Signed separation: how much darker `back` is than `front`. Positive means
# the background is correctly the darker of the two.
static func separation(front: Dictionary, back: Dictionary) -> float:
	return float(front.get("p50", 0.0)) - float(back.get("p50", 0.0))


# Readable dark steps inside a subject crop (HOLISTIC #050) — cavities, leaf
# overlaps, wood undersides — without demanding hero-view room blacks.
# Measured as median-minus-p05 so a uniformly grey close-up scores near 0.
static func shadow_structure(report: Dictionary) -> float:
	return float(report.get("p50", 0.0)) - float(report.get("p05", 0.0))


# ---- Palette lock modes (HOLISTIC #042) --------------------------------------
#
# The aquarium render is graded under palette_excess at the final lock stage.
# UI chrome and explicitly alternate grades (duotone) are documented separately
# so a HUD swatch or a two-ramp photo look is not mistaken for a lock failure.

## Per-mode excess ceiling. `ui` returns -1 (not graded as aquarium lock).
static func palette_mode_profile(mode: String) -> Dictionary:
	var m: String = mode.strip_edges().to_lower()
	match m:
		"night":
			return {
				"mode": "night",
				"palette_excess_max": PALETTE_EXCESS_MAX,
				"scope": "aquarium",
				"notes": "night LUT + bloom burnthrough; final snap still locks",
			}
		"care", "health":
			return {
				"mode": "care",
				"palette_excess_max": PALETTE_EXCESS_MAX,
				"scope": "aquarium",
				"notes": "health_grade runs before quantize; palette_lock re-snaps",
			}
		"outline":
			return {
				"mode": "outline",
				"palette_excess_max": PALETTE_EXCESS_MAX,
				"scope": "aquarium",
				"notes": "outline/creature ink darken then snap_to_palette",
			}
		"photo", "photo_up", "signature":
			return {
				"mode": "photo",
				# Slight headroom for sensor grain before the final snap; lock
				# itself stays on (AestheticsRuntime.PHOTO_MODE_GRADE).
				"palette_excess_max": PALETTE_EXCESS_MAX + 0.5,
				"scope": "aquarium",
				"notes": "photo preset keeps palette_lock; UI not included",
			}
		"duotone":
			return {
				"mode": "duotone",
				"palette_excess_max": 2.5,
				"scope": "alternate",
				"notes": "explicit two-ramp mode — not the 48-slot biotope lock",
			}
		"ui", "hud", "chrome":
			return {
				"mode": "ui",
				"palette_excess_max": -1.0,
				"scope": "ui",
				"notes": "UI chrome evaluated separately from aquarium render",
			}
		_:
			return {
				"mode": "day",
				"palette_excess_max": PALETTE_EXCESS_MAX,
				"scope": "aquarium",
				"notes": "default day / hero aquarium lock",
			}


# ---- Camera-aware grading (HOLISTIC #003) ------------------------------------
#
# The universal hero-view shadow floor is the right test for a composed room
# shot and the wrong test for a close underwater photo: surface / photo /
# photo_up frames intentionally omit the dark room, so failing them solely on
# p05<=40 produces false disease signals (see output/holistic_review_20261001).
#
# View profiles keep the disease checks that still apply (washed-out midtones,
# palette lock, stipple) while relaxing room-only expectations. Named regions
# are fractional frame rects for optional regional reads — not mandatory crops
# that rot when framing changes.

## Fractional rects of the frame, origin top-left, values in 0..1.
## Callers convert with `region_rect(img, name)`.
static func regions() -> Dictionary:
	return {
		# Lower band where the stand / room floor usually sits in hero/fit.
		"room_floor": Rect2(0.05, 0.78, 0.90, 0.18),
		# Central water column used for subject readability.
		"water_column": Rect2(0.18, 0.22, 0.64, 0.50),
		# Upper third: canopy / surface / fixture.
		"canopy": Rect2(0.10, 0.02, 0.80, 0.28),
		# Tight centre crop for close / photo subject checks.
		"subject_center": Rect2(0.28, 0.28, 0.44, 0.44),
		# Full frame alias.
		"full": Rect2(0.0, 0.0, 1.0, 1.0),
	}


static func region_rect(img: Image, region_name: String) -> Rect2i:
	if img == null:
		return Rect2i()
	var regs: Dictionary = regions()
	var r: Rect2 = regs.get(region_name, regs["full"]) as Rect2
	var w: int = img.get_width()
	var h: int = img.get_height()
	return Rect2i(
		clampi(int(floor(r.position.x * float(w))), 0, maxi(w - 1, 0)),
		clampi(int(floor(r.position.y * float(h))), 0, maxi(h - 1, 0)),
		maxi(int(round(r.size.x * float(w))), 1),
		maxi(int(round(r.size.y * float(h))), 1))


## Per-view expectations. Missing keys inherit the hero/universal defaults.
static func view_profile(view: String) -> Dictionary:
	var v: String = view.strip_edges().to_lower()
	# Hero / fit / front: full room-inclusive contract.
	var hero := {
		"view": "hero",
		"require_shadow_floor": true,
		"shadow_p05_max": float(SHADOW_P05_MAX),
		"midtone_mass_max": MIDTONE_MASS_MAX,
		"stipple_max": STIPPLE_MAX,
		"stipple_contrast_max": STIPPLE_CONTRAST_MAX,
		"palette_excess_max": PALETTE_EXCESS_MAX,
		"highlight_fraction_min": HIGHLIGHT_FRACTION_MIN,
		# Washed-out subject: tonal spread too small inside the water column.
		"min_tonal_spread": 35.0,
		"subject_region": "water_column",
	}
	match v:
		"hero", "fit", "front", "":
			return hero
		"close":
			var close_p: Dictionary = hero.duplicate()
			close_p["view"] = "close"
			close_p["require_shadow_floor"] = false
			close_p["shadow_p05_max"] = 130.0
			close_p["subject_region"] = "subject_center"
			close_p["min_tonal_spread"] = 28.0
			# HOLISTIC #050 — demand local dark steps in the subject crop, not
			# manufactured whole-frame blacks for the hero histogram.
			close_p["require_shadow_structure"] = true
			close_p["min_shadow_structure"] = 16.0
			return close_p
		"surface":
			var surface_p: Dictionary = hero.duplicate()
			surface_p["view"] = "surface"
			surface_p["require_shadow_floor"] = false
			surface_p["shadow_p05_max"] = 160.0
			surface_p["subject_region"] = "canopy"
			surface_p["min_tonal_spread"] = 24.0
			# Looking onto the surface compresses values; allow a slightly
			# louder stipple step without blessing salt-and-pepper.
			surface_p["stipple_contrast_max"] = 30.0
			return surface_p
		"photo", "photo_up":
			var photo_p: Dictionary = hero.duplicate()
			photo_p["view"] = v
			photo_p["require_shadow_floor"] = false
			photo_p["shadow_p05_max"] = 150.0
			photo_p["subject_region"] = "subject_center"
			photo_p["min_tonal_spread"] = 30.0
			photo_p["stipple_contrast_max"] = 32.0
			return photo_p
		"custom":
			var custom_p: Dictionary = hero.duplicate()
			custom_p["view"] = "custom"
			custom_p["require_shadow_floor"] = false
			return custom_p
		_:
			var other: Dictionary = hero.duplicate()
			other["view"] = v
			other["require_shadow_floor"] = false
			return other


# The whole contract in one call. Returns a list of {name, ok, value, want}
# so callers can print a table and fail on the first false.
#
# `view` selects camera-intent expectations (HOLISTIC #003). Pass "" / "hero"
# for the historical universal grade. Optional `subject_report` is a regional
# read used for the washed-out-subject check; when empty, the full-frame
# tonal spread is used instead.
static func grade(report: Dictionary, palette_size: int, view: String = "hero",
		subject_report: Dictionary = {}) -> Array[Dictionary]:
	var profile: Dictionary = view_profile(view)
	var out: Array[Dictionary] = []
	var mid_max: float = float(profile.get("midtone_mass_max", MIDTONE_MASS_MAX))
	out.append({
		"name": "midtone_mass",
		"value": float(report.get("midtone_mass", 1.0)),
		"want": "<= %.2f" % mid_max,
		"ok": float(report.get("midtone_mass", 1.0)) <= mid_max,
	})
	var hf_min: float = float(profile.get("highlight_fraction_min", HIGHLIGHT_FRACTION_MIN))
	var hf: float = float(report.get("highlight_fraction", 0.0))
	out.append({
		"name": "highlight",
		"value": hf,
		"want": ">= %.4f @%.0f" % [hf_min,
			float(report.get("highlight_level", HIGHLIGHT_LEVEL))],
		"ok": hf >= hf_min,
	})
	var shadow_max: float = float(profile.get("shadow_p05_max", float(SHADOW_P05_MAX)))
	var require_shadow: bool = bool(profile.get("require_shadow_floor", true))
	var p05: float = float(report.get("p05", 255.0))
	if require_shadow:
		out.append({
			"name": "p05 (shadow)",
			"value": p05,
			"want": "<= %.0f" % shadow_max,
			"ok": p05 <= shadow_max,
		})
	else:
		# Still recorded as evidence, but not a hard fail: a close-up lacking
		# the dark room is informative, not diseased. A truly crushed black
		# frame (p05 at 0 with no structure) is caught by midtone/spread.
		out.append({
			"name": "p05 (shadow)",
			"value": p05,
			"want": "info <= %.0f (view=%s)" % [shadow_max, String(profile.get("view", view))],
			"ok": true,
		})
	var stip_max: float = float(profile.get("stipple_max", STIPPLE_MAX))
	var stip: float = float(report.get("stipple", 0.0))
	out.append({
		"name": "stipple",
		"value": stip,
		"want": "<= %.2f" % stip_max,
		"ok": stip <= stip_max,
	})
	var stipc_max: float = float(profile.get("stipple_contrast_max", STIPPLE_CONTRAST_MAX))
	var stipc: float = float(report.get("stipple_contrast", 0.0))
	out.append({
		"name": "stipple step",
		"value": stipc,
		"want": "<= %.0f" % stipc_max,
		"ok": stipc <= stipc_max,
	})
	var excess_max: float = float(profile.get("palette_excess_max", PALETTE_EXCESS_MAX))
	var excess: float = palette_excess(report, palette_size)
	out.append({
		"name": "palette_excess",
		"value": excess,
		"want": "<= %.1fx" % excess_max,
		"ok": excess <= excess_max,
	})
	# Washed-out subject evidence: even when the room shadow floor is waived,
	# a frame with no tonal structure still fails.
	var subject: Dictionary = subject_report if not subject_report.is_empty() else report
	var spread: float = tonal_spread(subject)
	var min_spread: float = float(profile.get("min_tonal_spread", 35.0))
	out.append({
		"name": "tonal_spread",
		"value": spread,
		"want": ">= %.0f" % min_spread,
		"ok": spread >= min_spread,
	})
	# Close-range shadow structure (HOLISTIC #050): cavities / overlaps must
	# keep a readable dark step inside the subject without a room-black floor.
	if bool(profile.get("require_shadow_structure", false)):
		var struct_v: float = shadow_structure(subject)
		var min_struct: float = float(profile.get("min_shadow_structure", 16.0))
		out.append({
			"name": "shadow_structure",
			"value": struct_v,
			"want": ">= %.0f" % min_struct,
			"ok": struct_v >= min_struct,
		})
	return out


# Pretty-print a report as one aligned line per metric. Used by the capture
# harness so a run's output is diffable between commits.
static func format_report(label: String, report: Dictionary) -> String:
	if report.is_empty():
		return "%-16s (empty)" % label
	return ("%-16s p05 %5.1f  p50 %5.1f  p95 %5.1f  p99 %5.1f  spread %5.1f  "
			+ "sat50 %.3f  uniq %6d  midmass %.3f  hilite %.4f  "
			+ "stipple %.3f/%.0f") % [
		label,
		float(report["p05"]), float(report["p50"]), float(report["p95"]),
		float(report["p99"]), tonal_spread(report), float(report["sat_p50"]),
		int(report["unique_colors"]), float(report["midtone_mass"]),
		float(report["highlight_fraction"]),
		float(report.get("stipple", 0.0)),
		float(report.get("stipple_contrast", 0.0)),
	]
