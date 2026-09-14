extends SceneTree

# A dying tank must not look like a thriving one (VISUAL_DIRECTIONS #14).
#
# The whole visual response to tank health was water clarity, mapped to a 4%
# cool shift and at most a 38% desaturation. A capture of a tank that had
# suffered total fish extirpation, a shrimp-colony collapse and an algae bloom
# was indistinguishable from a healthy one — the two "Population collapse"
# toasts on screen were the only signal.
#
# Clarity is the wrong sole input because a tank can die perfectly clear: a
# heater failure or an ammonia spike takes the stock without clouding the
# water. These pin the four-axis grade, and in particular pin that ONE
# catastrophic axis is enough — a weighted mean would let three healthy
# signals hide a wipeout.

const Aesthetics = preload("res://scripts/aesthetics_runtime.gd")


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_tank_health_grade")

	# --- Endpoints ---
	t.approx(Aesthetics.health_grade_from_state(1.0, 1.0, 1.0, 1.0), 1.0,
		"everything healthy grades 1", 0.001)
	t.approx(Aesthetics.health_grade_from_state(0.0, 0.0, 0.0, 0.0), 0.0,
		"everything dead grades 0", 0.001)

	# --- One catastrophic axis must dominate ---
	# This is the regression the whole direction is about: a perfectly clear,
	# algae-free, well-planted tank with no animals left in it is NOT healthy.
	var wipeout: float = Aesthetics.health_grade_from_state(1.0, 0.0, 1.0, 1.0)
	t.check(wipeout < 0.55,
		"a total fauna loss in clear water must read as sick, got %.3f" % wipeout)
	var mean_only: float = 1.0 - float(Aesthetics.HEALTH_WEIGHTS["fauna"])
	t.check(wipeout < mean_only - 0.1,
		"the worst axis must pull the grade below a plain weighted mean "
			+ "(%.3f vs %.3f)" % [wipeout, mean_only])

	# …and it holds for each axis in turn.
	for axis in ["clarity", "fauna", "algae", "plants"]:
		var v: Dictionary = {"clarity": 1.0, "fauna": 1.0, "algae": 1.0, "plants": 1.0}
		v[axis] = 0.0
		var g: float = Aesthetics.health_grade_from_state(
			v["clarity"], v["fauna"], v["algae"], v["plants"])
		t.check(g < 0.75,
			"a dead '%s' axis must move the grade, got %.3f" % [axis, g])

	# --- Monotonic in every axis ---
	for axis in ["clarity", "fauna", "algae", "plants"]:
		var prev: float = -1.0
		for i in 11:
			var x: float = float(i) / 10.0
			var v: Dictionary = {"clarity": 0.5, "fauna": 0.5, "algae": 0.5, "plants": 0.5}
			v[axis] = x
			var g: float = Aesthetics.health_grade_from_state(
				v["clarity"], v["fauna"], v["algae"], v["plants"])
			t.check(g >= prev - 0.0001,
				"grade must not fall as '%s' improves (at %.1f)" % [axis, x])
			prev = g

	# --- Weights are a real distribution ---
	var total: float = 0.0
	for k: String in Aesthetics.HEALTH_WEIGHTS:
		var w: float = float(Aesthetics.HEALTH_WEIGHTS[k])
		t.check(w > 0.0, "weight '%s' is positive" % k)
		total += w
	t.approx(total, 1.0, "health weights sum to 1", 0.001)
	t.check(float(Aesthetics.HEALTH_WEIGHTS["fauna"])
			> float(Aesthetics.HEALTH_WEIGHTS["algae"]),
		"losing animals must weigh more than algae cover")

	# --- Inputs are clamped, not trusted ---
	t.approx(Aesthetics.health_grade_from_state(5.0, 5.0, 5.0, 5.0), 1.0,
		"out-of-range highs clamp to healthy", 0.001)
	t.approx(Aesthetics.health_grade_from_state(-3.0, -3.0, -3.0, -3.0), 0.0,
		"out-of-range lows clamp to dead", 0.001)
	var nan_safe: float = Aesthetics.health_grade_from_state(0.5, 0.5, 0.5, 0.5)
	t.in_range(nan_safe, 0.0, 1.0, "a mid tank grades inside range")

	# --- The clarity remap still behaves ---
	t.approx(Aesthetics.health_grade_from_transmittance(0.98), 1.0,
		"clear water is grade 1", 0.001)
	t.approx(Aesthetics.health_grade_from_transmittance(0.72), 0.0,
		"the bottom of the cycled band is grade 0", 0.001)
	t.check(Aesthetics.health_grade_from_transmittance(0.5) <= 0.0,
		"below the band clamps rather than going negative")

	# --- The shader consumes it with enough authority to be seen ---
	# A grade the picture ignores is the bug this direction exists for, so the
	# response is pinned in the source rather than left to a tuning pass.
	var src: String = _read("res://shaders/palette_quantize.gdshader")
	t.check(src.contains("VISUAL_DIRECTIONS #14"),
		"the quantize shader documents the health grade")
	t.check(src.contains("murk"),
		"stress must apply a green-grey murk cast, not just a cool shift — "
			+ "a cool shift reads as evening, which is the opposite of alarming")
	t.check(not src.contains("src = mix(src, src * vec3(0.92, 0.96, 1.04), stress * 0.55);"),
		"the old 4%-cool-shift grade should be gone")

	quit(t.finish())


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s: String = f.get_as_text()
	f.close()
	return s
