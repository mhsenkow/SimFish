extends SceneTree

# Continuous fish growth curve (FishGrowth).
#
# The property that matters visually is CONTINUITY: no two fish of slightly
# different age may render the same size, and the curve must never step.
# The old discrete version failed both and is what this replaces.

const G := preload("res://scripts/fish_growth.gd")


func _init() -> void:
	var t := TestSupport.Suite.new("fish_growth")

	# --- endpoints -------------------------------------------------------
	t.approx(G.scale_for(0.0), G.NEWBORN, "newborn is tiny")
	t.check(G.scale_for(0.0) < 0.3,
		"a just-dropped fry is well under a third of its mother")
	t.approx(G.scale_for(0.45), 1.0, "fully grown by mid-life")
	t.approx(G.scale_for(0.60), 1.0, "adults hold full size")
	t.approx(G.scale_for(1.0), G.SENESCENT_END, "senescent shrink")
	# Fish can outlive max_age_s on good food; the curve must not run away.
	t.approx(G.scale_for(1.5), G.SENESCENT_END, "past max age holds the floor")
	t.approx(G.scale_for(-1.0), G.NEWBORN, "negative age clamps to newborn")

	# --- monotonic growth then a single taper ----------------------------
	var prev: float = -1.0
	var samples: int = 200
	for i in range(0, int(0.45 * float(samples)) + 1):
		var a: float = float(i) / float(samples)
		var v: float = G.scale_for(a)
		t.check(v >= prev - 1e-6, "growth never reverses at t=%.3f" % a)
		prev = v

	# --- no visible steps ------------------------------------------------
	# The old curve jumped 0.35 -> 0.65 in one frame at t=0.10. Nothing may
	# change body size by more than a few percent over 1% of a lifetime.
	var worst: float = 0.0
	var worst_at: float = 0.0
	for i in samples:
		var a0: float = float(i) / float(samples)
		var a1: float = float(i + 1) / float(samples)
		var d: float = absf(G.scale_for(a1) - G.scale_for(a0))
		if d > worst:
			worst = d
			worst_at = a0
	t.check(worst < 0.05,
		"no step in the curve (worst %.4f at t=%.3f)" % [worst, worst_at])

	# --- the point of the whole thing: a spread of sizes coexists --------
	# Sample a population spread across the lifespan and count distinct
	# rendered sizes. The old curve produced 4; a continuum must produce
	# many more.
	var seen: Dictionary = {}
	for i in 40:
		var a: float = float(i) / 40.0
		seen[snappedf(G.scale_for(a), 0.01)] = true
	t.check(seen.size() >= 15,
		"a mixed-age population shows many sizes, got %d" % seen.size())

	# --- always a sane scale --------------------------------------------
	for i in 120:
		var a: float = float(i) / 60.0
		t.in_range(G.scale_for(a), 0.1, 1.05, "scale sane at t=%.3f" % a)

	quit(t.finish())
