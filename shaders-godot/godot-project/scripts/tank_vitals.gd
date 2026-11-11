class_name TankVitals
extends RefCounted

# SENTIENCE_THE_LOOM_THAT_THINKS_500 #301 + #251 — one tank self-model.
#
# Before this, "the tank" was computed four disagreeing ways: the sim's
# smoothed `stability` (sim_driver.gd), `KeeperCare.mood_score`,
# `ColonyMind.water_stress`, and AmbientAudio's vitality. A mind cannot know
# itself through four instruments that do not agree.
#
# TankVitals is the single owner of the tank's vitals, each with its normal
# (a rolling median — the tank's own normal, #305), its deviation from that
# normal, a short and a long trend slope (#251), and a confidence. It keeps a
# bounded, saved history ring per vital: one sample per sim-minute over the
# last 24 sim-hours, and one per sim-hour over the last 14 sim-days. The long
# ring is persisted so the tank remembers across sessions; the minute ring
# rebuilds quickly in play.
#
# `snapshot()` is the canonical read. `stability_instant(sim)` owns the single
# chemistry->stability formula that used to live inline in sim_driver; the sim
# now reads it from here, making the first of the four computations a reader.

# One sim-minute is day_length / 1440; one sim-hour is day_length / 24. At the
# default 360 s day that is ~0.25 s and ~15 s of real time.
const DEFAULT_DAY_LENGTH_S: float = 360.0
const MINUTE_CAP: int = 1440   # 24 sim-hours at 1 / sim-minute
const HOUR_CAP: int = 336      # 14 sim-days at 1 / sim-hour
const SLOPE_WINDOW: int = 20   # samples each side of the short-slope split

# The vitals, grouped as a body (#302): breath, blood, warmth, digestion,
# growth. A channel absent from the sim is simply not tracked.
const CHANNELS: PackedStringArray = [
	"o2", "toxic_ammonia", "nitrite", "nitrate",
	"temperature", "biomass", "stocking", "bloom", "waste",
]

var _minute: Dictionary = {}   # channel -> Array[float] (newest at end)
var _hour: Dictionary = {}     # channel -> Array[float]
var _normal: Dictionary = {}   # channel -> rolling median of the hour ring
var _latest: Dictionary = {}   # channel -> last sampled value
var _min_t: float = 0.0
var _hour_t: float = 0.0
var _min_accum: Dictionary = {}  # channel -> running sum this sim-hour
var _min_accum_n: int = 0


# --- Sampling --------------------------------------------------------------

# Advance the model by `dt` real seconds, reading `sim`. Samples the minute
# ring at the sim-minute cadence and the hour ring at the sim-hour cadence.
func observe(sim: Object, dt: float) -> void:
	if sim == null or dt <= 0.0:
		return
	var day_len: float = _day_length()
	var minute_s: float = maxf(0.05, day_len / 1440.0)
	var hour_s: float = maxf(1.0, day_len / 24.0)
	_min_t += dt
	_hour_t += dt
	if _min_t < minute_s:
		return
	_min_t = 0.0
	var vals: Dictionary = _read_channels(sim)
	for ch in vals.keys():
		var v: float = float(vals[ch])
		_latest[ch] = v
		var ring: Array = _minute.get(ch, [])
		ring.append(v)
		while ring.size() > MINUTE_CAP:
			ring.pop_front()
		_minute[ch] = ring
		_min_accum[ch] = float(_min_accum.get(ch, 0.0)) + v
	_min_accum_n += 1
	if _hour_t >= hour_s:
		_hour_t = 0.0
		var n: int = maxi(1, _min_accum_n)
		for ch in _min_accum.keys():
			var mean: float = float(_min_accum[ch]) / float(n)
			var hring: Array = _hour.get(ch, [])
			hring.append(mean)
			while hring.size() > HOUR_CAP:
				hring.pop_front()
			_hour[ch] = hring
			_normal[ch] = _median(hring)
		_min_accum.clear()
		_min_accum_n = 0


func _day_length() -> float:
	var ml: MainLoop = Engine.get_main_loop()
	if ml is SceneTree:
		var cfg: Node = (ml as SceneTree).root.get_node_or_null("/root/TankConfig")
		if cfg != null and cfg.get("day_length_s") != null:
			return maxf(15.0, float(cfg.get("day_length_s")))
	return DEFAULT_DAY_LENGTH_S


func _read_channels(sim: Object) -> Dictionary:
	var out: Dictionary = {}
	out["o2"] = clampf(float(_sv(sim, "dissolved_o2", 0.85)), 0.0, 2.0)
	var wc: Variant = sim.get("water_chemistry") if sim != null else null
	if wc is Object and wc != null:
		var tox: Variant = (wc as Object).get("toxic_ammonia")
		if tox == null and (wc as Object).has_method("toxic_ammonia_level"):
			tox = (wc as Object).call("toxic_ammonia_level")
		out["toxic_ammonia"] = float(tox) if tox != null else 0.0
		var no2: Variant = (wc as Object).get("nitrite")
		out["nitrite"] = float(no2) if no2 != null else 0.0
		var no3: Variant = (wc as Object).get("nitrate")
		out["nitrate"] = float(no3) if no3 != null else 0.0
	if sim.has_method("_tank_warmth_sample"):
		out["temperature"] = float(sim.call("_tank_warmth_sample"))
	out["biomass"] = float(_sv(sim, "total_plant_biomass", 0))
	if sim.has_method("fish_stocking_ratio"):
		out["stocking"] = float(sim.call("fish_stocking_ratio"))
	out["bloom"] = float(_sv(sim, "bloom_intensity", 0.0))
	var waste: Variant = sim.get("waste") if sim != null else null
	if waste is Array:
		out["waste"] = float((waste as Array).size())
	return out


static func _sv(sim: Object, key: String, default_v: Variant) -> Variant:
	if sim == null:
		return default_v
	var v: Variant = sim.get(key)
	return v if v != null else default_v


# --- The owned stability formula (#301, moved from sim_driver:1512-1517) ----

# Instantaneous tank stability, 0 (crashing) .. 1 (serene). This is the single
# source of the chemistry->stability relationship; sim_driver reads it rather
# than recomputing inline.
static func stability_instant(sim: Object) -> float:
	var inst: float = 1.0
	var wc: Variant = sim.get("water_chemistry") if sim != null else null
	if wc is Object and wc != null:
		var tox: Variant = (wc as Object).get("toxic_ammonia")
		var no2: Variant = (wc as Object).get("nitrite")
		inst -= clampf(float(tox if tox != null else 0.0) * 4.0, 0.0, 0.5)
		inst -= clampf(float(no2 if no2 != null else 0.0) * 1.2, 0.0, 0.3)
	var o2: float = float(_sv(sim, "dissolved_o2", 0.65))
	inst -= clampf(absf(o2 - 0.65) * 1.2, 0.0, 0.3)
	inst -= clampf(float(_sv(sim, "bloom_intensity", 0.0)) * 0.4, 0.0, 0.25)
	return clampf(inst, 0.0, 1.0)


# --- Reads -----------------------------------------------------------------

func value(channel: String) -> float:
	return float(_latest.get(channel, 0.0))


func normal(channel: String) -> float:
	if _normal.has(channel):
		return float(_normal[channel])
	# Before the first sim-hour, the normal is the mean of what we have.
	var ring: Array = _minute.get(channel, [])
	if ring.is_empty():
		return value(channel)
	var s: float = 0.0
	for v in ring:
		s += float(v)
	return s / float(ring.size())


func deviation(channel: String) -> float:
	return value(channel) - normal(channel)


# Short slope: change per sim-minute over the recent minute ring. Long slope:
# change per sim-hour over the hour ring. Sign is what matters (#252).
func short_slope(channel: String) -> float:
	return _slope(_minute.get(channel, []))


func long_slope(channel: String) -> float:
	return _slope(_hour.get(channel, []))


# Confidence 0..1: how much history backs this channel. A channel with a full
# day of minute samples and a settled normal is trusted; a fresh tank is not.
func confidence(channel: String) -> float:
	var mc: float = clampf(float((_minute.get(channel, []) as Array).size()) / 120.0, 0.0, 1.0)
	var hc: float = clampf(float((_hour.get(channel, []) as Array).size()) / 24.0, 0.0, 1.0)
	return clampf(mc * 0.4 + hc * 0.6, 0.0, 1.0)


# The canonical snapshot every "the tank" reader consumes.
func snapshot() -> Dictionary:
	var out: Dictionary = {}
	for ch in _latest.keys():
		out[ch] = {
			"value": value(ch),
			"normal": normal(ch),
			"deviation": deviation(ch),
			"short_slope": short_slope(ch),
			"long_slope": long_slope(ch),
			"confidence": confidence(ch),
		}
	return out


# --- Math ------------------------------------------------------------------

func _slope(ring: Array) -> float:
	var n: int = ring.size()
	if n < 4:
		return 0.0
	@warning_ignore("integer_division")
	var w: int = mini(SLOPE_WINDOW, n / 2)
	var early: float = 0.0
	var late: float = 0.0
	for i in w:
		early += float(ring[i])
		late += float(ring[n - 1 - i])
	return (late - early) / (float(w) * float(maxi(1, n - w)))


static func _median(arr: Array) -> float:
	var n: int = arr.size()
	if n == 0:
		return 0.0
	var sorted: Array = arr.duplicate()
	sorted.sort()
	@warning_ignore("integer_division")
	var mid: int = n / 2
	if n % 2 == 1:
		return float(sorted[mid])
	return (float(sorted[mid - 1]) + float(sorted[mid])) * 0.5


# --- Persistence (#251: bounded and saved) ---------------------------------

# The long (hour) ring and the normals are saved so the tank remembers across
# sessions. The minute ring is short-term and rebuilds in play; only a small
# tail is kept so slopes are not blank on load.
func to_dict() -> Dictionary:
	var hour_out: Dictionary = {}
	for ch in _hour.keys():
		hour_out[ch] = PackedFloat32Array(_hour[ch])
	var min_tail: Dictionary = {}
	for ch in _minute.keys():
		var ring: Array = _minute[ch]
		var tail: Array = ring.slice(maxi(0, ring.size() - SLOPE_WINDOW * 2))
		min_tail[ch] = PackedFloat32Array(tail)
	return {
		"hour": hour_out,
		"minute_tail": min_tail,
		"normal": _normal.duplicate(),
		"latest": _latest.duplicate(),
	}


func from_dict(d: Variant) -> void:
	if d is not Dictionary:
		return
	var dd: Dictionary = d
	_hour.clear()
	_minute.clear()
	_normal.clear()
	_latest.clear()
	var hour_in: Variant = dd.get("hour", {})
	if hour_in is Dictionary:
		for ch in (hour_in as Dictionary).keys():
			_hour[ch] = Array(hour_in[ch])
	var min_in: Variant = dd.get("minute_tail", {})
	if min_in is Dictionary:
		for ch in (min_in as Dictionary).keys():
			_minute[ch] = Array(min_in[ch])
	var norm_in: Variant = dd.get("normal", {})
	if norm_in is Dictionary:
		for ch in (norm_in as Dictionary).keys():
			_normal[ch] = float(norm_in[ch])
	var lat_in: Variant = dd.get("latest", {})
	if lat_in is Dictionary:
		for ch in (lat_in as Dictionary).keys():
			_latest[ch] = float(lat_in[ch])
