class_name MindContagion
extends RefCounted

# META #10 — emotional contagion. A fish's affect drifts toward its neighbours'
# (the school's "mood weather"): excitement and calm spread, weighted by proximity
# and the fish's social susceptibility. It is a DAMPED pull toward the local mean
# (not self-amplifying), so a fright ripples through the shoal and then settles
# instead of exploding. The affective complement to the discrete 1D signal bus:
# 1D carries "alarm!", this carries the ambient vibe.

const RADIUS: float = 6.0
const RADIUS2: float = RADIUS * RADIUS


# Nudge f.arousal (fast) and f.mood (slower) toward the proximity-weighted mean of
# nearby conspecifics, scaled by how socially susceptible this fish is.
static func tick(f: Fish, neighbors: Array, dt: float) -> void:
	if neighbors.is_empty():
		return
	var sum_ar: float = 0.0
	var sum_mood: float = 0.0
	var sum_w: float = 0.0
	for n in neighbors:
		if not (n is Fish) or n == f:
			continue
		var d2: float = f.position.distance_squared_to(n.position)
		if d2 >= RADIUS2:
			continue
		var w: float = 1.0 - sqrt(d2) / RADIUS   # closer neighbours weigh more
		sum_ar += n.arousal * w
		sum_mood += n.mood * w
		sum_w += w
	if sum_w < 0.01:
		return
	var avg_ar: float = sum_ar / sum_w
	var avg_mood: float = sum_mood / sum_w
	var rate: float = clampf(dt * 0.6 * susceptibility(f), 0.0, 0.5)
	# Damped pull toward the local mean — converges, never overshoots past it.
	f.arousal = clampf(lerpf(f.arousal, avg_ar, rate), 0.0, 1.0)
	f.mood = clampf(lerpf(f.mood, avg_mood, rate * 0.5), -1.0, 1.0)


# Social, tight-schooling, non-bold fish absorb the school's mood more strongly.
static func susceptibility(f: Fish) -> float:
	var soc: float = f._trait("sociability")
	var bold: float = f._trait("boldness")
	return clampf(0.25 + soc * 0.5 + f.schooling_strength * 0.3 - bold * 0.25, 0.05, 0.9)
