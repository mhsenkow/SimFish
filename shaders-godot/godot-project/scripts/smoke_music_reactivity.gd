extends SceneTree

# How the tank drives the ambient bed (MusicReactivity).
#
# MEASURED BEFORE: over 16 s per tank state the mix moved 0.6 dB between a
# dying tank and a thriving one, and the synth bus - most of what you hear -
# was static to within 0.4 dB. Over 45 s the level held within 3.3 dB on a
# ~6 second repeat. A soundtrack sold as reactive that sounds the same
# whether the fish are thriving or suffocating is a loop.
#
# MEASURED AFTER (dev/audio_probe.tscn, which writes a WAV):
#   dead -> thriving   6.1 dB level, 337 Hz brightness, air +15.3 dB
#   night -> day       3.7 dB level, 6.7 -> 24.5 notes/sec, air inverted
#
# These assert the SHAPE of those mappings; the probe measures the result.

const R := preload("res://scripts/music_reactivity.gd")


func _init() -> void:
	var t := TestSupport.Suite.new("music_reactivity")

	# --- health ------------------------------------------------------------
	var dead: float = R.health(0.05, 0.15, 0.2, 0.8, 0.9)
	var thriving: float = R.health(0.95, 0.95, 0.95, 0.1, 0.1)
	t.check(thriving > dead + 0.5,
		"a thriving tank reads far healthier than a dying one (%.2f vs %.2f)"
		% [thriving, dead])
	t.in_range(dead, 0.0, 0.25, "a dying tank bottoms out")
	t.in_range(thriving, 0.75, 1.0, "a thriving tank tops out")
	# Algae and nitrate must pull DOWN, or a choking tank sounds fine.
	t.check(R.health(0.9, 0.9, 0.9, 0.9, 0.9) < R.health(0.9, 0.9, 0.9, 0.0, 0.0),
		"a technically-alive but choking tank sounds worse")
	# Oxygen is what the player is managing; it must matter.
	t.check(R.health(0.8, 0.1, 0.8, 0.1, 0.1) < R.health(0.8, 0.9, 0.8, 0.1, 0.1) - 0.2,
		"oxygen moves the needle")
	for v in [-1.0, 0.0, 0.5, 1.0, 2.0]:
		t.in_range(R.health(v, v, v, v, v), 0.0, 1.0,
			"health stays a fraction at %.1f" % v)

	# --- the bed must actually move ---------------------------------------
	var sick: Dictionary = R.bed_params(0.05, 0.15, 0.2, 0.8, 0.9)
	var well: Dictionary = R.bed_params(0.95, 0.95, 0.95, 0.1, 0.1)
	t.check(float(well["cutoff"]) > float(sick["cutoff"]) * 3.0,
		"a healthy tank is dramatically brighter (%.0f vs %.0f Hz)"
		% [well["cutoff"], sick["cutoff"]])
	t.check(float(sick["cutoff"]) > 200.0,
		"but a sick tank is muffled, not silent - it must sound wrong, "
		+ "not broken")
	t.check(float(well["synth_gain"]) > float(sick["synth_gain"]) * 1.4,
		"and louder")
	t.check(float(well["air_gain"]) > float(sick["air_gain"]) * 3.0,
		"and the sense of space collapses when the tank is in trouble")
	t.check(float(sick["synth_gain"]) > 0.3,
		"a sick bed is still audible - a player must not think it broke")

	# Monotonic: a tank getting better must never sound worse.
	var prev_c: float = -1.0
	var prev_g: float = -1.0
	for i in 21:
		var h: float = float(i) / 20.0
		var c: float = R.synth_cutoff(h)
		var g: float = R.synth_gain(h)
		t.check(c >= prev_c - 0.01, "brightness rises with health at %.2f" % h)
		t.check(g >= prev_g - 0.001, "level rises with health at %.2f" % h)
		prev_c = c
		prev_g = g

	# --- day arc -----------------------------------------------------------
	t.check(R.day_level(1.0) > R.day_level(0.0),
		"day is fuller than night")
	t.check(R.day_air(0.0) > R.day_air(1.0),
		"night is MORE reverberant, not just quieter - space is what opens "
		+ "up when everything else settles")
	t.check(R.day_density(1.0) > R.day_density(0.0) * 1.8,
		"night is emptier, not merely quieter")
	t.check(R.day_level(0.0) > 0.4,
		"night still plays - silence reads as a bug")
	for d in [-1.0, 0.0, 0.5, 1.0, 3.0]:
		t.in_range(R.day_level(d), 0.3, 1.2, "day level sane at %.1f" % d)
		t.in_range(R.day_density(d), 0.2, 1.0, "density sane at %.1f" % d)

	# --- note thinning -----------------------------------------------------
	# Halving the rate is a musical relationship; an arbitrary skip is not.
	t.equals(R.step_stride(1.0), 1, "full density plays every step")
	t.equals(R.step_stride(0.7), 2, "mid density halves the note rate")
	t.equals(R.step_stride(0.3), 4, "low density halves it again")
	var prev_s: int = 0
	for i in 21:
		var d2: float = float(i) / 20.0
		var st: int = R.step_stride(d2)
		t.check(st in [1, 2, 4], "stride is a musical division at %.2f" % d2)
		t.check(st <= prev_s or prev_s == 0 or st <= prev_s,
			"stride never increases as density rises")
		prev_s = st

	# --- combined ----------------------------------------------------------
	var night_sick: Dictionary = R.full_params(0.1, 0.2, 0.2, 0.8, 0.8, 0.0)
	var day_well: Dictionary = R.full_params(0.95, 0.95, 0.95, 0.1, 0.1, 1.0)
	t.check(float(day_well["synth_gain"]) > float(night_sick["synth_gain"]) * 2.0,
		"the two axes compound rather than cancelling")
	t.check(float(night_sick["synth_gain"]) > 0.0,
		"the worst case is still audible")

	# --- wiring ------------------------------------------------------------
	var a: String = _read("res://scripts/ambient_audio.gd")
	t.check(a.contains("MusicReactivity.full_params("),
		"the bed reads both health and time of day")
	t.check(a.contains("_cached_bed_cutoff") and a.contains("_one_pole_cached"),
		"the reactive filter is applied to the synth bus")
	t.check(a.contains("MusicReactivity.step_stride("),
		"note thinning is wired into the sequencer")
	t.check(a.contains("BUS_TRIM_SYNTH") and a.contains("BUS_TRIM_AIR"),
		"gain staging is explicit, not emergent")
	t.check(not a.contains("_user_volume() * _complexity() *"),
		"complexity is no longer a level multiplier - it is an arrangement "
		+ "control and cost 6 dB for no musical reason")

	quit(t.finish())


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt: String = f.get_as_text()
	f.close()
	return txt
