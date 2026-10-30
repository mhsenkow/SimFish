class_name MotionBreath
extends RefCounted

# Breathing as one oscillator (CREATURE_MOTION_700 #54). Rate and depth come
# from oxygen, exertion, temperature and stress; the opercula, the mouth (in
# anti-phase: the buccal pump), a tiny girth pulse and a tiny body bob all
# read the same phase, so a resting fish breathes as one animal instead of
# several unrelated wobbles.
#
# Rates are in breaths per second. A resting fish in good water is around
# 1 Hz; a fish that just sprinted, or one in hypoxic water, pants at 2-3 Hz
# and opens wider.

const REST_HZ: float = 1.0
const MAX_HZ: float = 3.0

var phase: float = 0.0
var rate_hz: float = REST_HZ
var depth: float = 0.3
var _load: float = 0.4


func _init(phase0: float = 0.0) -> void:
	phase = phase0


# o2: dissolved oxygen 0..1 (1 = saturated). exertion: 0..1 recent effort.
# temperature_factor: 1 at the species' comfort temperature, >1 warmer.
func step(dt: float, o2: float, exertion: float, stress: float = 0.0,
		temperature_factor: float = 1.0, asleep: bool = false) -> float:
	if not (dt > 0.0):
		return phase
	var want: float = 0.4 + clampf(exertion, 0.0, 1.0) * 0.6 \
		+ clampf(0.7 - o2, 0.0, 0.7) * 1.6 + clampf(stress, 0.0, 1.0) * 0.4
	want *= clampf(temperature_factor, 0.6, 1.6)
	if asleep:
		want *= 0.6
	_load = MotionEase.damp(_load, clampf(want, 0.25, 2.4), 2.0, dt)
	rate_hz = clampf(REST_HZ * (0.6 + _load), 0.4, MAX_HZ)
	depth = clampf(0.25 + (_load - 0.4) * 0.45, 0.15, 1.0)
	phase = fposmod(phase + TAU * rate_hz * dt, TAU)
	return phase


# 0..1 opening of the gill covers.
func operculum() -> float:
	return (0.5 + 0.5 * sin(phase)) * depth


# 0..1 mouth opening, in anti-phase with the opercula.
func mouth() -> float:
	return (0.5 + 0.5 * sin(phase + PI)) * depth


# Fractional girth change, about ±1% at rest.
func girth() -> float:
	return sin(phase) * 0.01 * depth
