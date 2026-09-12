extends RefCounted
class_name MusicReactivity

# How the tank drives the ambient bed.
#
# THE PROBLEM THIS SOLVES. Measured over 16 s per state, the bed moved 0.6 dB
# between a dying tank and a thriving one. The drum bed reacted (an aeration
# gate silences the kick when the pump is weak, an 11 dB swing) but the synth
# - which is most of what you actually hear - was static to within 0.4 dB.
# A soundtrack advertised as reactive that sounds identical whether the fish
# are thriving or suffocating is not reactive; it is a loop.
#
# WHY TIMBRE AND NOT JUST LEVEL. Turning a bed down when the tank is sick is
# the crude version, and it fights the player: they turn the volume up and
# then get deafened by the next UI sound. Opening and closing a filter is how
# this is done musically - a struggling tank sounds muffled and airless, a
# thriving one opens up and starts to sparkle - and it reads clearly even
# when the level barely changes.

# Filter range. The low end is deliberately muffled rather than silent: a
# sick tank should sound like something is wrong, not like the audio broke.
const CUTOFF_SICK: float = 700.0
const CUTOFF_WELL: float = 7200.0

# Level swing. Modest on the synth (it carries the tune and should stay
# present), wide on air (the sense of SPACE is what collapses when a tank
# is in trouble, and it is the most expressive axis available).
const SYNTH_GAIN_SICK: float = 0.62
const SYNTH_GAIN_WELL: float = 1.12
const AIR_GAIN_SICK: float = 0.20
const AIR_GAIN_WELL: float = 1.35


# One number for "how well is this tank doing", 0..1.
#
# Oxygen and vitality dominate because they are what the player is actually
# managing; clarity is the visible proxy for the same thing. Algae and
# nitrate subtract, so a tank that is technically alive but choking still
# sounds like it is struggling.
static func health(vitality: float, o2: float, clarity: float,
		algae: float, nitrate: float) -> float:
	var good: float = (
		clampf(vitality, 0.0, 1.0) * 0.40
		+ clampf(o2, 0.0, 1.0) * 0.38
		+ clampf(clarity, 0.0, 1.0) * 0.22)
	var bad: float = (
		clampf(algae, 0.0, 1.0) * 0.22
		+ clampf(nitrate, 0.0, 1.0) * 0.18)
	return clampf(good - bad, 0.0, 1.0)


# Perceptual, not linear: most tanks live in the healthy end of the range, so
# a linear map would spend most of its travel where nothing is happening and
# leave the interesting part - a tank starting to slip - barely audible.
static func curve(h: float) -> float:
	var x: float = clampf(h, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func synth_cutoff(h: float) -> float:
	return lerpf(CUTOFF_SICK, CUTOFF_WELL, curve(h))


static func synth_gain(h: float) -> float:
	return lerpf(SYNTH_GAIN_SICK, SYNTH_GAIN_WELL, curve(h))


static func air_gain(h: float) -> float:
	return lerpf(AIR_GAIN_SICK, AIR_GAIN_WELL, curve(h))


# Everything the bed needs, in one call, so the audio thread reads a
# snapshot rather than recomputing per sample.
static func bed_params(vitality: float, o2: float, clarity: float,
		algae: float, nitrate: float) -> Dictionary:
	var h: float = health(vitality, o2, clarity, algae, nitrate)
	return {
		"health": h,
		"cutoff": synth_cutoff(h),
		"synth_gain": synth_gain(h),
		"air_gain": air_gain(h),
	}


# --- Day arc -------------------------------------------------------------
#
# Measured over 45 s, the bed's level held within 3.3 dB and repeated on a
# ~6 second cycle. Timbre moved (the arp comes and goes) but nothing
# breathed: there was no arc longer than a phrase, so it read as a loop you
# were left alone with rather than music that was going somewhere.
#
# Rather than bolt on a free-running LFO, the arc follows the tank's own day
# cycle. That gives a genuinely long form - a full day is many minutes - and
# it means the music is about the thing the player is looking at. Night
# hushes and opens out into reverb; daylight fills in and closes up.
const NIGHT_LEVEL: float = 0.58
const DAY_LEVEL: float = 1.0
const NIGHT_AIR: float = 1.45
const DAY_AIR: float = 0.85
const NIGHT_DENSITY: float = 0.45
const DAY_DENSITY: float = 1.0


# `daylight` is 0 at night, 1 at full day. Eased so dawn and dusk are
# gradual and midday is a plateau, which is how the light itself behaves -
# a linear ramp reads as a fader being pushed.
static func day_curve(daylight: float) -> float:
	var d: float = clampf(daylight, 0.0, 1.0)
	return d * d * (3.0 - 2.0 * d)


static func day_level(daylight: float) -> float:
	return lerpf(NIGHT_LEVEL, DAY_LEVEL, day_curve(daylight))


static func day_air(daylight: float) -> float:
	return lerpf(NIGHT_AIR, DAY_AIR, day_curve(daylight))


# How busy the bed is. Night should not just be quieter, it should be
# EMPTIER - fewer notes, more space between them. Volume alone reads as
# someone turning a dial; density reads as the tank settling down.
static func day_density(daylight: float) -> float:
	return lerpf(NIGHT_DENSITY, DAY_DENSITY, day_curve(daylight))


# Everything the bed needs, health and time of day together.
static func full_params(vitality: float, o2: float, clarity: float,
		algae: float, nitrate: float, daylight: float) -> Dictionary:
	var p: Dictionary = bed_params(vitality, o2, clarity, algae, nitrate)
	p["synth_gain"] = float(p["synth_gain"]) * day_level(daylight)
	p["air_gain"] = float(p["air_gain"]) * day_air(daylight)
	p["density"] = day_density(daylight)
	p["daylight"] = clampf(daylight, 0.0, 1.0)
	return p


# How many sixteenths to skip between arp notes, for a given density.
#
# Thinning by SKIPPING NOTES rather than by lowering their volume is the
# whole point: a quiet busy line still sounds busy, and at night what you
# want is space. Stepping 1 -> 2 -> 4 halves the note rate each time, which
# is a musical relationship rather than an arbitrary one, and keeps the
# notes that survive on the strong beats.
static func step_stride(density: float) -> int:
	var d: float = clampf(density, 0.0, 1.0)
	if d >= 0.88:
		return 1
	if d >= 0.58:
		return 2
	return 4
