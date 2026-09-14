extends SceneTree

# Duotone render mode — the ramp the shader depends on.
#
# palette_quantize.gdshader projects source luma onto the straight segment
# between palette index 0 and palette_size-1, then quantizes against the
# uploaded rungs. That only lands on the ladder if the rungs ARE the segment:
# evenly spaced, monotone, endpoints exact. These checks pin that contract —
# the shader half can only be eyeballed, so the math half is tested here.

const HEX_STEP: float = 1.0 / 255.0


func _initialize() -> void:
	var t := TestSupport.Suite.new("smoke_duotone_mode")

	t.check(AestheticsRuntime.duotone_hexes("none", 6).is_empty(),
		"'none' yields no ramp (full biotope palette stays in play)")
	t.check(AestheticsRuntime.duotone_hexes("not_a_ramp", 6).is_empty(),
		"an unknown ramp key falls back to full color rather than black")
	t.check(not AestheticsRuntime.duotone_active("none"),
		"duotone_active('none') is false")

	for mode in AestheticsRuntime.DUOTONE_RAMPS.keys():
		var key := String(mode)
		t.check(AestheticsRuntime.duotone_active(key), "%s is active" % key)
		var hexes: Array = AestheticsRuntime.duotone_hexes(key, 6)
		t.check(hexes.size() == 6, "%s: 6 levels requested, got %d" % [key, hexes.size()])
		var ends: Array = AestheticsRuntime.DUOTONE_RAMPS[key]
		var lo := Color.from_string("#" + String(ends[0]), Color.BLACK)
		var hi := Color.from_string("#" + String(ends[1]), Color.WHITE)
		var first := Color.from_string("#" + String(hexes[0]), Color.RED)
		var last := Color.from_string("#" + String(hexes[hexes.size() - 1]), Color.RED)
		t.check(first.is_equal_approx(lo), "%s: rung 0 is the shadow endpoint" % key)
		t.check(last.is_equal_approx(hi), "%s: last rung is the highlight endpoint" % key)
		t.check(lo.get_luminance() < hi.get_luminance(),
			"%s: shadow is darker than highlight (ramp must climb)" % key)

		# Monotone climb + on-segment: both are what keep the two nearest
		# rungs adjacent, which is what the ordered dither interpolates between.
		var prev_lum: float = -1.0
		for i in hexes.size():
			var c := Color.from_string("#" + String(hexes[i]), Color.RED)
			t.check(c.get_luminance() > prev_lum,
				"%s: rung %d brightens over its predecessor" % [key, i])
			prev_lum = c.get_luminance()
			var want := lo.lerp(hi, float(i) / float(hexes.size() - 1))
			# Tolerance is one 8-bit step: the ramp round-trips through hex.
			t.approx(c.r, want.r, "%s rung %d red on-segment" % [key, i], HEX_STEP)
			t.approx(c.g, want.g, "%s rung %d green on-segment" % [key, i], HEX_STEP)
			t.approx(c.b, want.b, "%s rung %d blue on-segment" % [key, i], HEX_STEP)

	# Level clamping — 1 rung has no segment, and the palette texture the
	# shader samples is capped at 48 wide.
	t.check(AestheticsRuntime.duotone_hexes("ink", 1).size()
			== AestheticsRuntime.DUOTONE_LEVELS_MIN,
		"levels below the floor clamp up to %d" % AestheticsRuntime.DUOTONE_LEVELS_MIN)
	t.check(AestheticsRuntime.duotone_hexes("ink", 999).size()
			== AestheticsRuntime.DUOTONE_LEVELS_MAX,
		"levels above the ceiling clamp down to %d" % AestheticsRuntime.DUOTONE_LEVELS_MAX)
	t.check(AestheticsRuntime.duotone_hexes("ink", 2).size() == 2,
		"2 tones is legal — that is the hard 1-bit look")

	# The render panel's OptionButton is index-ordered; a key that no longer
	# resolves would silently select "full color".
	# Loaded, not preloaded: render_panel.gd touches the TankConfig autoload,
	# which does not exist at this script's compile time.
	var panel: GDScript = load("res://scripts/render_panel.gd")
	var modes: Array = panel.DUOTONE_MODES
	t.check(String(modes[0]) == "none", "option 0 is the full-color default")
	for i in range(1, modes.size()):
		t.check(AestheticsRuntime.DUOTONE_RAMPS.has(String(modes[i])),
			"render panel option '%s' names a real ramp" % String(modes[i]))
	t.check(panel.DUOTONE_LABELS.size() == modes.size(),
		"every duotone option has a label")

	quit(t.finish())
