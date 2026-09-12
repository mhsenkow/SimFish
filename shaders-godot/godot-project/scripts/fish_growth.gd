extends RefCounted
class_name FishGrowth

# Continuous body-size growth curve.
#
# WHY. _maturity_scale() used to switch on the discrete maturity enum and
# return one of four fixed numbers - 0.35 fry, 0.65 juvenile, 1.0 adult,
# 0.95 senescent. Every fry in the tank was therefore *exactly* the same
# size, and so was every adult, so a breeding population rendered as three
# rubber-stamped sizes. A real livebearer tank reads as a continuum: newly
# dropped fry are a fraction of their mother, and every size in between is
# present at once.
#
# The curve keeps adults at full size for the bulk of adult life, so the
# average fish is unchanged; what it adds is a genuine ramp through the
# young stages and a much smaller newborn.
#
# Input is t = age / max_age_s, the same value that drives the maturity
# enum, so the two can never disagree.

# Breakpoints as (t, scale). Piecewise-linear between them.
const NEWBORN: float = 0.22       # just dropped - tiny
const FRY_END: float = 0.45       # t = 0.10, becoming a juvenile
const JUVENILE_END: float = 0.80  # t = 0.30, becoming an adult
const ADULT_FULL: float = 1.00    # t = 0.45, done growing
const SENESCENT_END: float = 0.95 # t = 1.00+, slight shrink with age

const T_FRY_END: float = 0.10
const T_JUVENILE_END: float = 0.30
const T_ADULT_FULL: float = 0.45
const T_SENESCENT: float = 0.85


# Body scale as a fraction of adult size, for age fraction `t`.
static func scale_for(t: float) -> float:
	var a: float = maxf(0.0, t)
	if a < T_FRY_END:
		return lerpf(NEWBORN, FRY_END, a / T_FRY_END)
	if a < T_JUVENILE_END:
		return lerpf(FRY_END, JUVENILE_END,
			(a - T_FRY_END) / (T_JUVENILE_END - T_FRY_END))
	if a < T_ADULT_FULL:
		return lerpf(JUVENILE_END, ADULT_FULL,
			(a - T_JUVENILE_END) / (T_ADULT_FULL - T_JUVENILE_END))
	if a < T_SENESCENT:
		return ADULT_FULL
	# Past senescence, taper - and hold the floor for fish living on past
	# max_age_s (meals can carry them to t > 1.0).
	return lerpf(ADULT_FULL, SENESCENT_END,
		clampf((a - T_SENESCENT) / (1.0 - T_SENESCENT), 0.0, 1.0))
