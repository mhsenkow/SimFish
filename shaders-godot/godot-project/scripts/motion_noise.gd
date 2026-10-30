class_name MotionNoise
extends RefCounted

# Smooth 1D noise for wander, fin flicker and antenna sway (CREATURE_MOTION_700
# #74). Two or three summed sines beat visibly over a few minutes; value
# noise with a smootherstep blend doesn't repeat. Deterministic for a seed, so
# captures replay.


static func _hash(seed_value: int, i: int) -> float:
	var h: int = (i * 374761393 + seed_value * 668265263) & 0x7fffffff
	h = (h ^ (h >> 13)) * 1274126177
	h = h & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65535.0 * 2.0 - 1.0


# Smooth value noise in [-1, 1] with features about 1 unit of t apart.
static func value1(seed_value: int, t: float) -> float:
	var i: int = floori(t)
	var f: float = t - float(i)
	var u: float = f * f * f * (f * (f * 6.0 - 15.0) + 10.0)
	return lerpf(_hash(seed_value, i), _hash(seed_value, i + 1), u)


# Fractal sum of octaves, normalised back to roughly [-1, 1].
static func fbm1(seed_value: int, t: float, octaves: int = 3, lacunarity: float = 2.03,
		gain: float = 0.5) -> float:
	var sum: float = 0.0
	var amp: float = 1.0
	var norm: float = 0.0
	var freq: float = 1.0
	for o in maxi(octaves, 1):
		sum += value1(seed_value + o * 131, t * freq) * amp
		norm += amp
		amp *= gain
		freq *= lacunarity
	return sum / maxf(norm, 1e-6)
