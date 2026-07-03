class_name FishSignals
extends RefCounted

# 1D / META #5 — discrete inter-fish signalling (intersubjectivity). Fish emit a
# tiny state-driven vocabulary; nearby fish PERCEIVE the loudest relevant signal,
# which enters the Global Workspace as a bid. A per-fish reliability table learns
# how often each signal preceded a real outcome, so receivers weigh signals by
# their own experience — proto-language, learned locally, NOT the LLM. Honest
# scope: 4 signals, 8u radius, ~3s lingering, frequency-table learning.

const RADIUS: float = 8.0
const RADIUS2: float = RADIUS * RADIUS
const DECAY_S: float = 3.0

const ALARM: String = "alarm"
const FOOD: String = "food_found"
const MATE: String = "mate_call"
const SUBMIT: String = "submit"
const KINDS: Array[String] = [ALARM, FOOD, MATE, SUBMIT]

const _INTERP_MIN: float = 0.3
const _INTERP_MAX: float = 1.3
const _INTERP_DEFAULT: float = 0.7
const _HEARD_RING_CAP: int = 8


static func _state(f) -> Dictionary:
	var existing: Variant = f.get("_signal_state")
	if existing is Dictionary:
		return existing as Dictionary
	var fresh: Dictionary = {}
	if f is Object:
		(f as Object).set("_signal_state", fresh)
	return fresh


# What signal does this fish's state broadcast right now? Priority: danger first.
static func signal_for_state(f) -> String:
	if f._startle_remaining > 0.0 or f.spooked > 0.5:
		return ALARM
	if f.goal_kind == "food" and f.hunger > 0.5:
		return FOOD
	if f.get("has_mate") == true or (f.get("partner") != null and is_instance_valid(f.get("partner"))):
		return MATE
	if f.get("rank_within_species") != null and float(f.rank_within_species) < 0.3 and f.stress > 0.3:
		return SUBMIT
	return ""


# Per-tick: emit the current state's signal (refreshing its linger timer) and
# decay a stale one.
static func tick(f: Fish, dt: float) -> void:
	var st: Dictionary = _state(f)
	var sig: String = signal_for_state(f)
	if sig != "":
		st["sig"] = sig
		st["t"] = DECAY_S
	else:
		var t: float = float(st.get("t", 0.0)) - dt
		if t <= 0.0:
			st["sig"] = ""
			st["t"] = 0.0
		else:
			st["t"] = t
	f._signal_state = st


static func active_signal(f) -> String:
	var st: Dictionary = _state(f)
	return str(st.get("sig", "")) if float(st.get("t", 0.0)) > 0.0 else ""


# Listen: find the nearest neighbour with an active signal and remember it +
# its loudness (closer = louder). Reinforces alarm reliability when a heard alarm
# is followed by this fish's own fear rising (simple local credit assignment).
static func scan(f: Fish, neighbors: Array) -> void:
	var st: Dictionary = _state(f)
	var prev_heard: String = str(st.get("heard", ""))
	var prev_spook: float = float(st.get("prev_spook", f.spooked))
	# Credit assignment: a prior alarm that preceded a real fright was reliable.
	if prev_heard == ALARM and f.spooked > prev_spook + 0.05:
		reinforce(f, ALARM, true)

	var best_sig: String = ""
	var best_d2: float = RADIUS2
	for n in neighbors:
		if not (n is Fish) or n == f:
			continue
		var sig: String = active_signal(n)
		if sig == "":
			continue
		var d2: float = f.position.distance_squared_to(n.position)
		if d2 < best_d2:
			best_d2 = d2
			best_sig = sig
	st["heard"] = best_sig
	st["heard_str"] = (1.0 - sqrt(best_d2) / RADIUS) if best_sig != "" else 0.0
	st["prev_spook"] = f.spooked
	f._signal_state = st
	_record_heard(f, best_sig, float(st["heard_str"]))


static func _record_heard(f, kind: String, strength: float) -> void:
	if kind == "":
		return
	var ring: Array = f._heard_signals
	if not ring.is_empty():
		var last: Variant = ring[ring.size() - 1]
		if last is Dictionary and str((last as Dictionary).get("kind", "")) == kind:
			(last as Dictionary)["str"] = strength
			return
	ring.append({"kind": kind, "str": strength})
	while ring.size() > _HEARD_RING_CAP:
		ring.pop_front()


# Learned reliability of a signal for this receiver, in [_INTERP_MIN, _INTERP_MAX].
static func interpret(f, sig: String) -> float:
	var st: Dictionary = _state(f)
	var learn: Dictionary = st.get("learn", {})
	return float(learn.get(sig, _INTERP_DEFAULT))


# Nudge a signal's learned reliability toward trust (good) or discount (bad).
static func reinforce(f, sig: String, good: bool) -> void:
	var st: Dictionary = _state(f)
	var learn: Dictionary = st.get("learn", {})
	var cur: float = float(learn.get(sig, _INTERP_DEFAULT))
	var target: float = _INTERP_MAX if good else _INTERP_MIN
	learn[sig] = clampf(lerpf(cur, target, 0.12), _INTERP_MIN, _INTERP_MAX)
	st["learn"] = learn
	f._signal_state = st


# The heard signal as a Global Workspace bid (intersubjectivity → attention).
static func collect_signal_bid(f) -> Dictionary:
	var st: Dictionary = _state(f)
	var heard: String = str(st.get("heard", ""))
	if heard == "":
		return {}
	var strn: float = float(st.get("heard_str", 0.0))
	var w: float = strn * interpret(f, heard)
	match heard:
		ALARM:
			return {"label": "threat", "salience": w * 0.6, "coalition": ["threat", "social", "signal"]}
		FOOD:
			return {"label": "food", "salience": w * 0.45, "coalition": ["food", "forage", "social", "signal"]}
		MATE:
			return {"label": "mate", "salience": w * 0.4, "coalition": ["mate", "social", "signal"]}
		SUBMIT:
			return {"label": "social", "salience": w * 0.3, "coalition": ["social", "signal"]}
	return {}
