class_name FishTiming
extends RefCounted

# CREATURE_MOTION_700 §L — timing: weight, size, temperature and mood (#331–358).


const STROUHAL: float = 0.30
const AMP_FRAC: float = 0.20  # A ≈ 0.2 · L
const VISIBLE_HZ_CAP_DIV: float = 6.0  # visible beat ≤ fps/6 (#333)

# #331: declared locomotion per playable species (overrides body_shape inference).
const SPECIES_LOCOMOTION: Dictionary = {
	"glassdart": "subcarangiform",
	"danio": "subcarangiform",
	"rummy_nose": "subcarangiform",
	"ember_tetra": "subcarangiform",
	"harlequin_rasbora": "subcarangiform",
	"guppy": "subcarangiform",
	"endler": "subcarangiform",
	"killifish": "subcarangiform",
	"corydoras": "subcarangiform",
	"reef_fish": "subcarangiform",
	"freshwater_gar": "thunniform",
	"mudsifter": "anguilliform",
	"betta": "labriform",
	"angelfish": "labriform",
	"severum": "labriform",
	"dwarf_gourami": "labriform",
	"pufferfish": "ostraciiform",  # tetraodontiform → rigid-body scull
	"hillstream_loach": "labriform",  # adherent glide
	"otocinclus": "labriform",
	"goby": "subcarangiform",  # saltatory via swim_pattern sit/dart
	"bristlenose_pleco": "subcarangiform",  # burst-and-rest via bouts
}

# #337 / #340: per-species bout duration windows [cruise_lo, cruise_hi, hover_lo, hover_hi, dart_lo, dart_hi]
# and hold pause scale (#340).
const SPECIES_BOUTS: Dictionary = {
	"guppy": [1.8, 5.5, 0.8, 2.2, 0.35, 0.7, 0.35],
	"endler": [1.5, 4.5, 0.7, 2.0, 0.3, 0.65, 0.3],
	"danio": [0.9, 2.8, 0.4, 1.2, 0.45, 1.1, 0.25],  # #338 burst-and-glide
	"glassdart": [2.2, 7.0, 1.0, 3.0, 0.35, 0.7, 0.55],
	"angelfish": [3.5, 10.0, 2.0, 5.5, 0.5, 0.9, 1.8],
	"severum": [3.2, 9.0, 1.8, 5.0, 0.5, 0.9, 1.5],
	"betta": [2.5, 8.0, 1.5, 4.5, 0.4, 0.85, 1.2],
	"dwarf_gourami": [2.8, 8.5, 1.6, 4.8, 0.4, 0.8, 1.3],
	"corydoras": [2.0, 6.0, 1.2, 3.5, 0.35, 0.75, 0.7],
	"bristlenose_pleco": [4.0, 12.0, 2.5, 7.0, 0.6, 1.2, 2.0],  # long rests
	"pufferfish": [2.5, 7.5, 1.8, 5.0, 0.4, 0.8, 1.1],
	"goby": [1.5, 4.0, 1.5, 4.5, 0.25, 0.55, 0.9],
	"mudsifter": [2.0, 7.0, 1.0, 3.5, 0.3, 0.65, 0.8],
}

# #336: crepuscular / nocturnal activity curves. "night" peaks when daylight is low.
const SPECIES_DIEL: Dictionary = {
	"corydoras": "night",
	"bristlenose_pleco": "night",
	"mudsifter": "night",
	"otocinclus": "crepuscular",
	"hillstream_loach": "crepuscular",
	"goby": "crepuscular",
	"killifish": "crepuscular",
}


static func locomotion_for_species(species: String) -> String:
	return String(SPECIES_LOCOMOTION.get(species, ""))


# #332: f = St · U / A → rad/s, with locomotion colouring.
static func strouhal_tailbeat_rate(speed: float, body_length: float, locomotion: String) -> float:
	var L: float = maxf(body_length, 0.12)
	var A: float = maxf(L * AMP_FRAC, 0.035)
	var U: float = maxf(speed, 0.015)
	var f_hz: float = STROUHAL * U / A
	match locomotion:
		"anguilliform": f_hz *= 0.85
		"ostraciiform": f_hz *= 1.15
		"thunniform": f_hz *= 1.05
		"labriform": f_hz *= 0.7  # pecs carry more of the beat
	return clampf(f_hz * TAU, 1.0, 26.0)


# #333: cap the *visible* wag rate; physics clock may run faster.
static func visible_wag_rate(rate_rad_s: float, fps: float = 60.0) -> float:
	var cap: float = (maxf(fps, 24.0) / VISIBLE_HZ_CAP_DIV) * TAU
	return minf(rate_rad_s, cap)


static func visible_amp_scale(rate_rad_s: float, fps: float = 60.0) -> float:
	# Above the visible cap, drop amplitude so the shader ripple carries the rest.
	var cap: float = (maxf(fps, 24.0) / VISIBLE_HZ_CAP_DIV) * TAU
	if rate_rad_s <= cap:
		return 1.0
	return clampf(cap / rate_rad_s, 0.35, 1.0)


# #334: Q10 ≈ 2 around comfort warmth 0.55.
static func temperature_tempo(warmth: float) -> float:
	var dw: float = clampf(warmth, 0.2, 1.0) - 0.55
	return clampf(pow(2.0, dw / 0.35), 0.55, 1.7)


# #335: low O₂ slows swimming tempo (opercula sped separately).
static func oxygen_swim_tempo(o2: float) -> float:
	return lerpf(0.55, 1.0, clampf(o2 / 0.75, 0.0, 1.0))


static func oxygen_opercula_tempo(o2: float) -> float:
	return lerpf(1.7, 1.0, clampf(o2 / 0.75, 0.0, 1.0))


# #336: per-species day/night activity.
static func day_activity(species: String, daylight: float, swim_pattern: String) -> float:
	var dl: float = clampf(daylight, 0.0, 1.0)
	var mode: String = String(SPECIES_DIEL.get(species, ""))
	if mode.is_empty() and swim_pattern == "shuffle":
		mode = "night"
	match mode:
		"night":
			return lerpf(0.75, 1.15, 1.0 - dl)
		"crepuscular":
			# Peak at dusk/dawn (dl ≈ 0.25 and 0.75).
			var dusk: float = 1.0 - absf(dl - 0.25) / 0.35
			var dawn: float = 1.0 - absf(dl - 0.75) / 0.35
			var peak: float = clampf(maxf(dusk, dawn), 0.0, 1.0)
			return lerpf(0.55, 1.2, peak)
		_:
			return lerpf(0.55, 1.0, dl)


# #341: right-skewed bout lengths.
static func lognormal_between(rng: RandomNumberGenerator, lo: float, hi: float) -> float:
	var a: float = maxf(lo, 0.05)
	var b: float = maxf(hi, a + 0.05)
	var med: float = sqrt(a * b)
	var sigma: float = 0.42
	var v: float = med * exp(rng.randfn(0.0, 1.0) * sigma)
	return clampf(v, a * 0.65, b * 1.45)


static func bout_windows(species: String) -> Array:
	return SPECIES_BOUTS.get(species, [2.5, 8.0, 1.2, 3.8, 0.4, 0.8, 0.7]) as Array


static func hold_scale(species: String) -> float:
	var w: Array = bout_windows(species)
	return float(w[6]) if w.size() > 6 else 0.7


# #339: reaction / envelope scale ∝ L^(1/3).
static func size_reaction_scale(body_length: float, ref_length: float = 0.45) -> float:
	return clampf(pow(maxf(body_length, 0.12) / ref_length, 1.0 / 3.0), 0.7, 1.45)


# Maturity ints match Fish.MATURITY_* (avoid class_name Fish dependency here so
# invertebrates can call FishTiming without pulling fish.gd into their load).
const MATURITY_FRY: int = 0
const MATURITY_SENESCENT: int = 3


# #346 / #347 / #356: life-stage bout tempo (duration mult; <1 = busier).
static func life_stage_bout_dur_mult(maturity: int) -> float:
	match maturity:
		MATURITY_FRY:
			return 0.55
		MATURITY_SENESCENT:
			return 1.55
		_:
			return 1.0


static func life_stage_amp_mult(maturity: int) -> float:
	match maturity:
		MATURITY_FRY:
			return 1.12
		MATURITY_SENESCENT:
			return 0.78
		_:
			return 1.0


# #354 / #355: arousal + hunger tempo.
static func mood_tempo(stress: float, spooked: float, mood: float, hunger: float,
		arousal: float = 0.0) -> float:
	var m: float = 1.0 + stress * 0.28 + spooked * 0.22 + arousal * 0.18
	m -= clampf(mood, 0.0, 1.0) * 0.12
	m += clampf(hunger - 0.35, 0.0, 0.65) * 0.25  # hungry patrols
	m -= clampf(0.45 - hunger, 0.0, 0.45) * 0.2  # satiety loafs
	return clampf(m, 0.55, 1.75)


# #357
static func sleep_breath_mult(asleep: bool) -> float:
	return 0.6 if asleep else 1.0


# #345: labriform pecs 2–4 Hz; body-caudal keep a fixed ratio to the tail.
static func pec_freq(locomotion: String, tail_rate_rad: float, speed: float, max_speed: float) -> float:
	var u: float = clampf(speed / maxf(max_speed, 0.1), 0.0, 1.0)
	if locomotion == "labriform" or locomotion == "ostraciiform":
		return lerpf(TAU * 2.2, TAU * 4.0, u)
	# ~0.55× the tail clock for body-caudal schoolers.
	return maxf(tail_rate_rad * 0.55, TAU * 1.5)


# #344: gulp exposure sheet (rise / hold / dive seconds).
static func gulp_trip_seconds(rng: RandomNumberGenerator) -> float:
	# rise 0.6–1.2 + gulp 0.15 + dive 0.4 ≈ 1.15–1.75; keep a little linger.
	return rng.randf_range(1.15, 1.85)


# #342 / #343: exposure sheet stage fractions for anticipation timers.
static func c_start_stage_seconds() -> Vector3:
	# stage1 (~3.5 frames), stage2 (~5 frames), glide (~450 ms)
	return Vector3(3.5 / 60.0, 5.0 / 60.0, 0.45)


static func strike_hold_seconds() -> float:
	return 0.22  # fixation mid of 150–300 ms


# #348: invertebrate reaction latency (seconds).
const INVERT_REACT_S: Dictionary = {
	"cherry_shrimp": 0.05,
	"shrimp": 0.05,
	"amano_shrimp": 0.06,
	"crab": 0.22,
	"lobster": 0.25,
	"snail": 0.15,  # tentacles; body ~0.30 via body_mult
	"trumpet_snail": 0.15,
	"ramshorn": 0.15,
	"nerite": 0.16,
}


static func invert_react_seconds(kind: String, body: bool = false) -> float:
	var base: float = float(INVERT_REACT_S.get(kind, 0.15))
	return base * (2.0 if body else 1.0)


# #349: partial phase lock when drafting a conspecific wake.
static func school_phase_pull(own_phase: float, neighbor_phase: float,
		draft: float, schooling: float) -> float:
	var w: float = clampf(draft, 0.0, 1.0) * clampf(schooling, 0.0, 1.5) * 0.35
	if w < 0.02:
		return own_phase
	var d: float = wrapf(neighbor_phase - own_phase, -PI, PI)
	return own_phase + d * w


# #351: above 4×, drop visual wag amp so fish don't vibrate.
static func timelapse_amp_scale(time_scale: float) -> float:
	if time_scale <= 4.0:
		return 1.0
	return clampf(4.0 / time_scale, 0.15, 1.0)


# #352: pose clock at full frame rate under slow-mo (wall dt, not sim dt).
static func pose_dt_for_time_scale(sim_dt: float, wall_dt: float, time_scale: float) -> float:
	if time_scale > 0.0 and time_scale < 0.4:
		return maxf(wall_dt, 1.0 / 120.0)
	return sim_dt


# #358: courtship quiver Hz cap by species (shown as amp above visible wag cap).
const DISPLAY_QUIVER_HZ: Dictionary = {
	"guppy": 12.5,
	"endler": 13.0,
	"betta": 8.0,
	"dwarf_gourami": 7.5,
	"angelfish": 6.0,
	"severum": 5.5,
}


static func display_quiver_rate(species: String, intensity: float) -> float:
	var hz: float = float(DISPLAY_QUIVER_HZ.get(species, 8.0))
	return lerpf(TAU * 4.0, TAU * hz, clampf(intensity, 0.0, 1.0))
