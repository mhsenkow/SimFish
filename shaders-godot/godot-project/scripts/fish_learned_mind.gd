extends RefCounted

# SENTIENCE Round 2: the learning mind. A fish that learns over its life
# and turns into a particular self.
#
#   observe()           the day's events (keeper feeds, meals, frights, chases,
#                       kind or sharp words) go into a small ring with the
#                       day-phase and light-cycle stamp they happened at.
#   consolidate_night() runs once per light cycle while the fish sleeps. It
#                       replays the ring plus the strongest episodic memories
#                       into BELIEFS that carry confidence ("you come when the
#                       light goes gold", "the low left corner is safe",
#                       "Rex chases near the right side"), then applies the
#                       day's lived experience as slow, bounded trait drift.
#   tick_at()           checks each belief against what happens (prediction
#                       error): a feed that arrives confirms the belief, a
#                       missed one weakens it, surprises the fish, sends it
#                       to inspect the spot, and gets said out loud ("you didn't
#                       come today"). Confident beliefs make the fish anticipate:
#                       it gathers at the feeding spot before feeding time and
#                       swims around learned danger.
#   novelty()/expose()  per-stimulus habituation curve with spontaneous
#                       recovery. Repeated surprises and repeated frights mean
#                       less each time, and it wears off after nights away.
#   milestones          identity continuity: "I was small when you first fed me".
#
# State: Fish._learned_mind (bounded, JSON-safe, schema-versioned; saved via
# FishMind.mind_to_dict under "learned_mind"). Fish._belief_cue is a transient
# per-second read model (anticipation/inspection target + danger points) that
# the workspace and steering read cheaply; it is never saved.
# Main-thread only. Everything is O(ring) at most once a second, and the
# night pass runs once per cycle per fish.

const FishMind = preload("res://scripts/fish_mind.gd")
const MindSelfModel = preload("res://scripts/mind_self_model.gd")
const _MindDirtySaveScript = preload("res://scripts/mind_dirty_save.gd")
const _FishBackstory = preload("res://scripts/fish_backstory.gd")

const SCHEMA_VERSION: int = 1
const EVENTS_MAX: int = 48
const BELIEFS_MAX: int = 8
const DRIFT_LOG_MAX: int = 8
const MILESTONES_MAX: int = 10
const HAB_MAX: int = 16
const GRUDGE_SEEN_MAX: int = 16
const PHASE_BUCKETS: int = 8
const TICK_S: float = 1.0
const EVENT_DEDUP_PHASE: float = 0.02
const EVENT_WINDOW_CYCLES: int = 7

const BELIEF_FORM_CONF: float = 0.35
const BELIEF_DROP_CONF: float = 0.1
const BELIEF_VOICE_CONF: float = 0.45
const ANTICIPATE_CONF: float = 0.4
const CONFIRM_GAIN: float = 0.14
const VIOLATE_LOSS: float = 0.22
const EXTINCTION_LOSS: float = 0.05
const NIGHT_FORGET: float = 0.02

const DRIFT_NIGHT_MAX: float = 0.03
const DRIFT_TOTAL_MAX: float = 0.25
const TRAIT_KEYS: Array[String] = ["boldness", "curiosity", "sociability", "calm"]
const DRIFT_MILESTONE_STEP: float = 0.08

const DANGER_RADIUS: float = 3.0
const SAFE_RADIUS: float = 2.5
const HAB_GAIN: float = 0.8
const HAB_RECOVERY: float = 0.6

const PHASE_NAMES: Array[String] = [
	"at first light", "in the morning", "at midday", "when the light goes gold",
	"as the light goes out", "in the early dark", "in the deep night",
	"before the light comes",
]

static var _tick_acc: Dictionary = {}  # instance id -> seconds since last tick


# ---- state ----

static func _prop(f, key: String) -> Variant:
	if f == null:
		return null
	return f.get(key)


static func _fresh() -> Dictionary:
	return {
		"v": SCHEMA_VERSION,
		"cycle": 0,
		"last_phase": -1.0,
		"night_c": -1,
		"events": [],
		"beliefs": [],
		"exp": {},
		"birth": {},
		"drift_log": [],
		"milestones": [],
		"hab": {},
		"gseen": [],
		"voice_c": -1,
		"voice_n": 0,
		"maturity": -1,
	}


static func ensure(f) -> Dictionary:
	var cur: Variant = _prop(f, "_learned_mind")
	if cur is Dictionary and int((cur as Dictionary).get("v", 0)) == SCHEMA_VERSION:
		return cur as Dictionary
	var st: Dictionary = _fresh()
	if f != null:
		f.set("_learned_mind", st)
	return st


static func _mark(f) -> void:
	if f != null and f.get("id") != null:
		_MindDirtySaveScript.mark(f, "learned_mind")


static func _ensure_birth(f, st: Dictionary) -> void:
	var birth: Dictionary = st.get("birth", {}) as Dictionary
	if not birth.is_empty():
		return
	var pers: Variant = f.get("personality")
	if not (pers is Dictionary) or (pers as Dictionary).is_empty():
		return
	for k in TRAIT_KEYS:
		birth[k] = clampf(float((pers as Dictionary).get(k, 0.5)), 0.05, 1.0)
	st["birth"] = birth


static func _sim_phase(f) -> float:
	var sim: Variant = _prop(f, "sim")
	if sim == null or not is_instance_valid(sim):
		return 0.25
	var ph: Variant = (sim as Object).get("day_phase")
	if ph == null:
		return 0.25
	return fposmod(float(ph), 1.0)


static func _advance_clock(st: Dictionary, phase: float) -> void:
	var last: float = float(st.get("last_phase", -1.0))
	if last >= 0.0 and phase < last - 0.5:
		st["cycle"] = int(st.get("cycle", 0)) + 1
	st["last_phase"] = phase


static func bucket_of(phase: float) -> int:
	return clampi(int(floorf(fposmod(phase, 1.0) * PHASE_BUCKETS)), 0, PHASE_BUCKETS - 1)


static func _bucket_dist(a: int, b: int) -> int:
	var d: int = absi(a - b) % PHASE_BUCKETS
	return mini(d, PHASE_BUCKETS - d)


static func phase_name(bucket: int) -> String:
	return PHASE_NAMES[clampi(bucket, 0, PHASE_BUCKETS - 1)]


static func _pos_arr(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]


static func _arr_pos(a: Variant) -> Variant:
	if a is Array and (a as Array).size() >= 3:
		var v := Vector3(float((a as Array)[0]), float((a as Array)[1]), float((a as Array)[2]))
		if v.is_finite():
			return v
	return null


static func pos_of(f) -> Vector3:
	var p: Variant = _prop(f, "position")
	if p is Vector3:
		return p as Vector3
	return Vector3.ZERO


# ---- habituation curve (#3) ----

# 1 = never met, falls toward 0 with each exposure; recovers across cycles
# without exposure (spontaneous recovery), so a fright that stopped happening
# becomes startling again, and a daily non-event goes dull.
static func novelty(f, key: String) -> float:
	var st: Dictionary = ensure(f)
	var h: Variant = (st.get("hab", {}) as Dictionary).get(key, null)
	if not (h is Dictionary):
		return 1.0
	return 1.0 / (1.0 + HAB_GAIN * _hab_n_eff(h as Dictionary, int(st.get("cycle", 0))))


static func _hab_n_eff(h: Dictionary, cycle: int) -> float:
	var gap: int = maxi(0, cycle - int(h.get("c", cycle)))
	return float(h.get("n", 0.0)) * pow(HAB_RECOVERY, float(gap))


static func expose(f, key: String) -> float:
	var st: Dictionary = ensure(f)
	var hab: Dictionary = st.get("hab", {}) as Dictionary
	var cycle: int = int(st.get("cycle", 0))
	var nov: float = novelty(f, key)
	var n_eff: float = 0.0
	if hab.get(key) is Dictionary:
		n_eff = _hab_n_eff(hab[key] as Dictionary, cycle)
	hab[key] = {"n": snappedf(n_eff + 1.0, 0.001), "c": cycle}
	while hab.size() > HAB_MAX:
		var oldest: String = ""
		var oldest_c: int = 1 << 30
		for k in hab.keys():
			var c: int = int((hab[k] as Dictionary).get("c", 0)) if hab[k] is Dictionary else -1
			if c < oldest_c:
				oldest_c = c
				oldest = str(k)
		hab.erase(oldest)
	st["hab"] = hab
	return nov


# ---- experience accumulation ----

static func accumulate(f, key: String, amount: float) -> void:
	if f == null or amount == 0.0:
		return
	var st: Dictionary = ensure(f)
	var ex: Dictionary = st.get("exp", {}) as Dictionary
	ex[key] = snappedf(float(ex.get(key, 0.0)) + amount, 0.0001)
	st["exp"] = ex


# ---- observation (hooks call this) ----

static func observe(f, kind: String, pos: Vector3, subject: String = "", subject_name: String = "") -> void:
	if f == null:
		return
	observe_at(f, kind, pos, _sim_phase(f), subject, subject_name)


static func observe_at(f, kind: String, pos: Vector3, phase: float,
		subject: String = "", subject_name: String = "") -> void:
	if f == null or kind == "" or kind == "graze":
		return
	var st: Dictionary = ensure(f)
	_advance_clock(st, phase)
	var cycle: int = int(st.get("cycle", 0))
	var events: Array = st.get("events", []) as Array
	for i in range(events.size() - 1, maxi(-1, events.size() - 6), -1):
		var e: Dictionary = events[i] as Dictionary
		if str(e.get("k", "")) == kind and str(e.get("s", "")) == subject \
				and int(e.get("c", -1)) == cycle \
				and absf(float(e.get("ph", 0.0)) - phase) < EVENT_DEDUP_PHASE:
			return
	var ev: Dictionary = {"k": kind, "ph": snappedf(phase, 0.001), "c": cycle}
	if pos.is_finite():
		ev["p"] = _pos_arr(pos)
	if subject != "":
		ev["s"] = subject
		ev["n"] = subject_name
	events.append(ev)
	while events.size() > EVENTS_MAX:
		events.pop_front()
	st["events"] = events
	match kind:
		"startled":
			# A habituated fright teaches less fear.
			accumulate(f, "startled", expose(f, "startle"))
		"chased":
			accumulate(f, "chased", 1.0)
		"keeper_feed":
			accumulate(f, "keeper_feed", 1.0)
		"food":
			accumulate(f, "fed", 1.0)
			var glance: Variant = f.get("_cached_glance_strength")
			if glance != null and float(glance) > 0.25:
				accumulate(f, "hand_fed", 1.0)
		"kind_word":
			accumulate(f, "kind", 1.0)
		"harsh_word":
			accumulate(f, "harsh", 1.0)
	_confirm_beliefs(f, st, ev, pos)
	_first_time_milestone(f, st, kind, subject_name)
	_mark(f)


static func _confirm_beliefs(f, st: Dictionary, ev: Dictionary, pos: Vector3) -> void:
	var kind: String = str(ev.get("k", ""))
	var cycle: int = int(st.get("cycle", 0))
	for b in (st.get("beliefs", []) as Array):
		var bd: Dictionary = b as Dictionary
		if int(bd.get("hit_c", -1)) == cycle:
			continue
		var hit: bool = false
		match str(bd.get("kind", "")):
			"feed_time":
				hit = kind == "keeper_feed" \
						and _bucket_dist(bucket_of(float(ev.get("ph", 0.0))), int(bd.get("phase", 0))) <= 1
			"danger":
				var bp: Variant = _arr_pos(bd.get("p", null))
				hit = kind in ["startled", "chased"] and bp is Vector3 and pos.is_finite() \
						and pos.distance_to(bp as Vector3) < DANGER_RADIUS
			"chaser":
				hit = kind == "chased" and str(ev.get("s", "")) == str(bd.get("subj", ""))
		if hit:
			_strengthen(bd, CONFIRM_GAIN)
			bd["hit_c"] = cycle
			bd["ok"] = int(bd.get("ok", 0)) + 1
			if f != null and f.get("surprise") != null:
				# A confirmed prediction is the opposite of surprise.
				f.surprise = maxf(0.0, float(f.surprise) - 0.1)


static func _strengthen(bd: Dictionary, gain: float) -> void:
	var c: float = float(bd.get("conf", 0.0))
	bd["conf"] = snappedf(clampf(c + gain * (1.0 - c), 0.0, 0.98), 0.001)


static func _weaken(bd: Dictionary, loss: float) -> void:
	var c: float = float(bd.get("conf", 0.0))
	bd["conf"] = snappedf(clampf(c - loss * c - 0.02, 0.0, 1.0), 0.001)


# ---- identity continuity (#4) ----

static func _stage_word(maturity: int) -> String:
	if maturity == Fish.MATURITY_FRY:
		return "small"
	if maturity == Fish.MATURITY_JUVENILE:
		return "young"
	if maturity == Fish.MATURITY_SENESCENT:
		return "old"
	return ""


static func _add_milestone(f, st: Dictionary, tag: String, line: String) -> bool:
	var ms: Array = st.get("milestones", []) as Array
	for m in ms:
		if str((m as Dictionary).get("tag", "")) == tag:
			return false
	var mat: int = int(f.get("maturity")) if f.get("maturity") != null else Fish.MATURITY_ADULT
	ms.append({"tag": tag, "line": line, "c": int(st.get("cycle", 0)), "mat": mat})
	while ms.size() > MILESTONES_MAX:
		ms.pop_front()
	st["milestones"] = ms
	return true


static func _first_time_milestone(f, st: Dictionary, kind: String, subject_name: String) -> void:
	match kind:
		"keeper_feed":
			_add_milestone(f, st, "first_keeper_feed", "you first fed me")
		"chased":
			var who: String = subject_name if subject_name != "" else "a bigger fish"
			_add_milestone(f, st, "first_chased", "%s first chased me" % who)
		"bred":
			_add_milestone(f, st, "first_bred", "I first spawned")
		"kind_word":
			_add_milestone(f, st, "first_kind_word", "you first spoke softly to me")


static func _tick_maturity(f, st: Dictionary) -> void:
	if f.get("maturity") == null:
		return
	var mat: int = int(f.get("maturity"))
	var prev: int = int(st.get("maturity", -1))
	st["maturity"] = mat
	if prev < 0 or mat == prev:
		return
	if mat == Fish.MATURITY_JUVENILE:
		_add_milestone(f, st, "outgrew_fry", "I'm not small anymore")
	elif mat == Fish.MATURITY_ADULT:
		_add_milestone(f, st, "grown", "I'm grown now")
	elif mat == Fish.MATURITY_SENESCENT:
		_add_milestone(f, st, "aging", "I'm slower than I was")
	_mark(f)


# "I was small when you first fed me": a milestone from an earlier life stage.
static func life_line(f) -> String:
	var st: Dictionary = ensure(f)
	var now_mat: int = int(f.get("maturity")) if f.get("maturity") != null else Fish.MATURITY_ADULT
	var ms: Array = st.get("milestones", []) as Array
	for m in ms:
		var md: Dictionary = m as Dictionary
		var then_mat: int = int(md.get("mat", now_mat))
		var word: String = _stage_word(then_mat)
		if then_mat < now_mat and word != "" and str(md.get("tag", "")).begins_with("first_"):
			return "I was %s when %s" % [word, str(md.get("line", ""))]
	# Occasionally (every other cycle) the self reaches back past this tank's
	# events to the story it arrived with (FishBackstory, grounded + seeded).
	if f is Object and int(st.get("cycle", 0)) % 2 == 0 and _FishBackstory.has_story(f as Object):
		var topic: String = "memory" if int(st.get("cycle", 0)) % 4 == 0 else "origin"
		var bl: String = _FishBackstory.speech_line(f as Object, topic).trim_suffix(".")
		if bl != "":
			return bl
	if not ms.is_empty():
		var last: Dictionary = ms[ms.size() - 1] as Dictionary
		if not str(last.get("tag", "")).begins_with("first_"):
			return str(last.get("line", ""))
	return ""


# How the fish has changed from the self it was born with.
static func self_change_line(f) -> String:
	var st: Dictionary = ensure(f)
	var birth: Dictionary = st.get("birth", {}) as Dictionary
	var pers: Variant = f.get("personality")
	if birth.is_empty() or not (pers is Dictionary):
		return ""
	var best_k: String = ""
	var best_d: float = 0.0
	for k in ["boldness", "calm", "sociability"]:
		var d: float = float((pers as Dictionary).get(k, 0.5)) - float(birth.get(k, 0.5))
		if absf(d) > absf(best_d):
			best_d = d
			best_k = k
	if absf(best_d) < DRIFT_MILESTONE_STEP:
		return ""
	var why: String = _dominant_cause(st, best_k, best_d > 0.0)
	var base: String = ""
	match best_k:
		"boldness":
			base = "braver than I was" if best_d > 0.0 else "warier than I used to be"
		"calm":
			base = "calmer than I was" if best_d > 0.0 else "jumpier than I used to be"
		"sociability":
			base = "I like company more now" if best_d > 0.0 else "I keep to myself more now"
	return "%s, %s" % [base, why] if why != "" else base


static func _dominant_cause(st: Dictionary, trait_key: String, up: bool) -> String:
	var counts: Dictionary = {}
	for e in (st.get("drift_log", []) as Array):
		var ed: Dictionary = e as Dictionary
		if str(ed.get("t", "")) != trait_key or (float(ed.get("d", 0.0)) > 0.0) != up:
			continue
		var w: String = str(ed.get("why", ""))
		counts[w] = int(counts.get(w, 0)) + 1
	var best: String = ""
	var best_n: int = 0
	for cause in counts.keys():
		if int(counts[cause]) > best_n:
			best_n = int(counts[cause])
			best = str(cause)
	match best:
		"chased":
			return "since I was chased"
		"startled":
			return "after the frights"
		"hand_fed":
			return "since you fed me by hand"
		"kind":
			return "since your soft voice"
		"harsh":
			return "since your sharp voice"
		"calm_days":
			return "after quiet days"
	return ""


# ---- per-second tick: prediction error, anticipation, extinction ----

static func tick(f, sim: Node, dt: float) -> void:
	if f == null or not (f is Fish):
		return
	var iid: int = f.get_instance_id()
	var acc: float = float(_tick_acc.get(iid, 0.0)) + dt
	if acc < TICK_S:
		_tick_acc[iid] = acc
		return
	_tick_acc[iid] = 0.0
	var phase: float = 0.25
	if sim != null and sim.get("day_phase") != null:
		phase = fposmod(float(sim.get("day_phase")), 1.0)
	tick_at(f, phase, acc, sim)


static func tick_at(f, phase: float, dt: float, sim: Node = null) -> void:
	var st: Dictionary = ensure(f)
	_advance_clock(st, phase)
	_ensure_birth(f, st)
	_tick_maturity(f, st)
	_scan_grudges(f, st, sim)
	var cycle: int = int(st.get("cycle", 0))
	var bucket: int = bucket_of(phase)
	var asleep: bool = f.get("_asleep") == true
	var cue: Dictionary = {}
	var prev_cue: Variant = f.get("_belief_cue")
	if prev_cue is Dictionary and str((prev_cue as Dictionary).get("label", "")) == "inspect" \
			and float((prev_cue as Dictionary).get("t", 0.0)) > dt:
		cue = (prev_cue as Dictionary).duplicate()
		cue["t"] = float(cue["t"]) - dt
	var danger: Array = []
	var best_anticip: float = 0.0
	var changed: bool = false
	for b in (st.get("beliefs", []) as Array):
		var bd: Dictionary = b as Dictionary
		var conf: float = float(bd.get("conf", 0.0))
		var bp: Variant = _arr_pos(bd.get("p", null))
		match str(bd.get("kind", "")):
			"feed_time":
				var bph: int = int(bd.get("phase", 0))
				var fed_today: bool = int(bd.get("hit_c", -1)) == cycle
				# Prediction error: the window (+1 bucket grace) has closed with no feed.
				if not fed_today and bucket == (bph + 2) % PHASE_BUCKETS \
						and int(bd.get("chk_c", -1)) != cycle and int(bd.get("formed_c", cycle)) < cycle:
					bd["chk_c"] = cycle
					if not asleep:
						var icue: Dictionary = _on_feed_violated(f, st, bd, bp, conf, sim)
						if not icue.is_empty():
							cue = icue
						changed = true
				# Anticipation: the learned window is approaching or open.
				var lead: float = fposmod(float(bph) / PHASE_BUCKETS - phase, 1.0)
				var in_window: bool = bucket == bph or lead < 0.07
				if not fed_today and in_window and conf >= ANTICIPATE_CONF and not asleep:
					var hunger: float = float(f.get("hunger")) if f.get("hunger") != null else 0.3
					var sal: float = clampf(0.25 + conf * 0.45 + hunger * 0.2, 0.0, 0.85)
					if sal > best_anticip and str(cue.get("label", "")) != "inspect":
						best_anticip = sal
						cue = {"label": "anticipate", "sal": sal, "t": TICK_S * 2.0,
								"line": belief_line(f, bd)}
						if bp is Vector3:
							cue["pos"] = bp
			"danger", "chaser":
				if not (bp is Vector3) or conf < 0.25:
					continue
				danger.append({"p": bp, "w": conf})
				# Extinction: calm time spent inside a feared zone weakens the fear.
				var stress: float = float(f.get("stress")) if f.get("stress") != null else 0.0
				if str(bd.get("kind", "")) == "danger" \
						and pos_of(f).distance_to(bp as Vector3) < DANGER_RADIUS and stress < 0.35:
					bd["safe_s"] = float(bd.get("safe_s", 0.0)) + dt
					if float(bd["safe_s"]) >= 20.0 and int(bd.get("ext_c", -1)) != cycle:
						bd["ext_c"] = cycle
						bd["safe_s"] = 0.0
						_weaken(bd, EXTINCTION_LOSS * (0.5 + novelty(f, "calm_in:" + str(bd.get("id", "")))))
						expose(f, "calm_in:" + str(bd.get("id", "")))
						changed = true
	if not danger.is_empty():
		cue["danger"] = danger
	var old_label: String = str((prev_cue as Dictionary).get("label", "")) if prev_cue is Dictionary else ""
	f.set("_belief_cue", cue)
	if old_label != str(cue.get("label", "")) and f.get("_bid_dirty") != null:
		f.set("_bid_dirty", int(f.get("_bid_dirty")) | 4)
	# Night pass: once per light cycle, while (or as if) asleep in the dark.
	if int(st.get("night_c", -1)) != cycle and phase >= 0.6 and phase < 0.98 \
			and (asleep or phase >= 0.8):
		consolidate_night(f, sim)
		changed = true
	if changed:
		_mark(f)


# Returns the inspection cue ({} when the surprise has habituated away).
static func _on_feed_violated(f, st: Dictionary, bd: Dictionary, bp: Variant,
		conf_before: float, sim: Node) -> Dictionary:
	_weaken(bd, VIOLATE_LOSS)
	bd["miss"] = int(bd.get("miss", 0)) + 1
	var key: String = "absent:" + str(bd.get("id", ""))
	var nov: float = expose(f, key)
	var surprise: float = clampf(conf_before * (0.4 + 0.6 * nov), 0.0, 1.0)
	if f.get("surprise") != null:
		f.surprise = maxf(float(f.surprise), surprise * 0.8)
	if f.get("curiosity_drive") != null:
		f.curiosity_drive = clampf(float(f.curiosity_drive) + surprise * 0.25, 0.0, 1.0)
	if f.get("mood") != null:
		f.mood = clampf(float(f.mood) - surprise * 0.08, -1.0, 1.0)
	accumulate(f, "missed_feed", 1.0)
	# Curiosity response: go look where it should have happened. Habituates:
	# the third empty evening in a row barely draws a glance.
	var cue: Dictionary = {}
	if nov > 0.2:
		cue = {"label": "inspect", "sal": clampf(surprise * nov * 0.85, 0.0, 0.8),
				"t": 18.0 * nov}
		if bp is Vector3:
			cue["pos"] = bp
	if conf_before >= 0.4:
		var line: String = "you didn't come today" if bool(bd.get("keeper", true)) \
				else "no food %s today" % phase_name(int(bd.get("phase", 0)))
		if int(bd.get("miss", 0)) >= 3 and float(bd.get("conf", 0.0)) < 0.3:
			line = "you don't come %s anymore" % phase_name(int(bd.get("phase", 0)))
		_voice(f, st, sim, line, "surprise", surprise)
	return cue


static func _scan_grudges(f, st: Dictionary, sim: Node) -> void:
	var g: Variant = f.get("grudges")
	if not (g is Dictionary):
		return
	var seen: Array = st.get("gseen", []) as Array
	var now_keys: Array = []
	for k in (g as Dictionary).keys():
		var cid: String = str(k)
		now_keys.append(cid)
		if seen.has(cid):
			continue
		var nm: String = ""
		var cpos: Vector3 = pos_of(f)
		if sim != null and sim.get("fish") is Array:
			for o in (sim.get("fish") as Array):
				if o != null and is_instance_valid(o) and str(o.id) == cid:
					nm = str(o.fish_name) if str(o.fish_name) != "" else "the %s" % str(o.species)
					break
		observe(f, "chased", cpos, cid, nm)
	while now_keys.size() > GRUDGE_SEEN_MAX:
		now_keys.pop_front()
	st["gseen"] = now_keys


# ---- night consolidation (#1): episodic -> semantic ----

static func consolidate_night(f, sim: Node = null) -> void:
	var st: Dictionary = ensure(f)
	var cycle: int = int(st.get("cycle", 0))
	st["night_c"] = cycle
	_ensure_birth(f, st)
	var events: Array = st.get("events", []) as Array
	# Tonight's sleeping spot is evidence for "safe here" when nothing scared us near it.
	if f.get("_asleep") == true:
		var here: Vector3 = pos_of(f)
		var scared_near: bool = false
		for e in events:
			var ed: Dictionary = e as Dictionary
			var ep: Variant = _arr_pos(ed.get("p", null))
			if str(ed.get("k", "")) in ["startled", "chased"] and ep is Vector3 \
					and cycle - int(ed.get("c", 0)) <= 3 and here.distance_to(ep as Vector3) < SAFE_RADIUS:
				scared_near = true
				break
		if not scared_near:
			observe_at(f, "slept", here, float(st.get("last_phase", 0.8)))
			events = st.get("events", []) as Array
	var recent: Array = []
	for e in events:
		if cycle - int((e as Dictionary).get("c", 0)) <= EVENT_WINDOW_CYCLES:
			recent.append(e)
	var supported: Dictionary = {}
	_form_feed_beliefs(f, st, recent, supported)
	_form_place_beliefs(f, st, recent, "danger", supported)
	_form_place_beliefs(f, st, recent, "safe", supported)
	_form_chaser_beliefs(f, st, recent, supported)
	_form_keeper_tone(f, st, recent, supported)
	_replay_episodes(f)
	# Unsupported beliefs fade slowly; the weakest fall away.
	var keep: Array = []
	for b in (st.get("beliefs", []) as Array):
		var bd: Dictionary = b as Dictionary
		if not supported.has(str(bd.get("id", ""))) and str(bd.get("kind", "")) != "feed_time":
			_weaken(bd, NIGHT_FORGET)
		if float(bd.get("conf", 0.0)) >= BELIEF_DROP_CONF:
			keep.append(bd)
		else:
			_forget_semantic(f, str(bd.get("said_line", "")))
	keep.sort_custom(func(a, b): return float(a.get("conf", 0.0)) > float(b.get("conf", 0.0)))
	st["beliefs"] = keep.slice(0, mini(BELIEFS_MAX, keep.size()))
	for b in (st["beliefs"] as Array):
		var bd2: Dictionary = b as Dictionary
		if float(bd2.get("conf", 0.0)) >= BELIEF_VOICE_CONF and not bool(bd2.get("said", false)):
			bd2["said"] = true
			var line: String = belief_line(f, bd2)
			bd2["said_line"] = line
			_remember_semantic(f, line)
			_voice(f, st, sim, line, "belief", float(bd2.get("conf", 0.5)))
	apply_night_drift(f, sim)
	_mark(f)


# `fresh`: the evidence includes something that happened THIS cycle. Old
# evidence still in the ring must not re-strengthen a belief every night (a
# violated "you come at dusk" would be propped back up by last week's feeds).
# `form_ok`: enough to create a belief that does not exist yet.
static func _upsert(st: Dictionary, id: String, fields: Dictionary, support: float,
		supported: Dictionary, fresh: bool, form_ok: bool) -> Dictionary:
	var beliefs: Array = st.get("beliefs", []) as Array
	for b in beliefs:
		var bd: Dictionary = b as Dictionary
		if str(bd.get("id", "")) == id:
			if not fresh:
				return bd
			supported[id] = true
			for k in fields.keys():
				bd[k] = fields[k]
			if int(bd.get("last_c", -1)) != int(st.get("cycle", 0)):
				_strengthen(bd, 0.1 * clampf(support, 0.0, 2.0))
			bd["last_c"] = int(st.get("cycle", 0))
			return bd
	if not form_ok:
		return {}
	supported[id] = true
	var nb: Dictionary = {"id": id, "conf": snappedf(clampf(BELIEF_FORM_CONF + 0.08 * (support - 1.0), 0.2, 0.7), 0.001),
			"formed_c": int(st.get("cycle", 0)), "last_c": int(st.get("cycle", 0)),
			"ok": 0, "miss": 0}
	for k in fields.keys():
		nb[k] = fields[k]
	beliefs.append(nb)
	st["beliefs"] = beliefs
	return nb


static func _form_feed_beliefs(_f, st: Dictionary, recent: Array, supported: Dictionary) -> void:
	var by_bucket: Dictionary = {}  # bucket -> {cycle: true}
	for e in recent:
		var ed: Dictionary = e as Dictionary
		if str(ed.get("k", "")) != "keeper_feed":
			continue
		var bk: int = bucket_of(float(ed.get("ph", 0.0)))
		if not by_bucket.has(bk):
			by_bucket[bk] = {}
		(by_bucket[bk] as Dictionary)[int(ed.get("c", 0))] = true
	var used: Array = []
	for _pass in 2:
		var best_b: int = -1
		var best_n: int = 1
		for bk in by_bucket.keys():
			if used.has(int(bk)):
				continue
			var cycles: Dictionary = (by_bucket[bk] as Dictionary).duplicate()
			for nb in [(int(bk) + 1) % PHASE_BUCKETS, (int(bk) + PHASE_BUCKETS - 1) % PHASE_BUCKETS]:
				if by_bucket.has(nb):
					cycles.merge(by_bucket[nb] as Dictionary)
			if cycles.size() > best_n or (cycles.size() == best_n and best_b >= 0 \
					and (by_bucket[bk] as Dictionary).size() > (by_bucket[best_b] as Dictionary).size()):
				best_n = cycles.size()
				best_b = int(bk)
		if best_b < 0:
			return
		used.append(best_b)
		used.append((best_b + 1) % PHASE_BUCKETS)
		used.append((best_b + PHASE_BUCKETS - 1) % PHASE_BUCKETS)
		var fields: Dictionary = {"kind": "feed_time", "phase": best_b, "keeper": true}
		# Where the food turned up in that window: the spot to gather at.
		var sum: Vector3 = Vector3.ZERO
		var n: int = 0
		for e in recent:
			var ed: Dictionary = e as Dictionary
			var ep: Variant = _arr_pos(ed.get("p", null))
			if str(ed.get("k", "")) == "food" and ep is Vector3 \
					and _bucket_dist(bucket_of(float(ed.get("ph", 0.0))), best_b) <= 1:
				sum += ep as Vector3
				n += 1
		if n > 0:
			fields["p"] = _pos_arr(sum / float(n))
		var today: bool = (by_bucket[best_b] as Dictionary).has(int(st.get("cycle", 0)))
		for nbk in [(best_b + 1) % PHASE_BUCKETS, (best_b + PHASE_BUCKETS - 1) % PHASE_BUCKETS]:
			if by_bucket.has(nbk) and (by_bucket[nbk] as Dictionary).has(int(st.get("cycle", 0))):
				today = true
		_upsert(st, "feed@%d" % best_b, fields, float(best_n) - 1.0, supported, today, today)


static func _form_place_beliefs(f, st: Dictionary, recent: Array, kind: String,
		supported: Dictionary) -> void:
	var pts: Array = []
	var kinds: Array = ["startled", "chased"] if kind == "danger" else ["slept"]
	for e in recent:
		var ed: Dictionary = e as Dictionary
		var ep: Variant = _arr_pos(ed.get("p", null))
		if str(ed.get("k", "")) in kinds and ep is Vector3:
			pts.append({"p": ep, "c": int(ed.get("c", 0))})
	if kind == "danger":
		# Episodic replay: strong remembered frights count as evidence too.
		var store: Variant = f.get("_episodic_store")
		if store is Array:
			for e in (store as Array):
				if not (e is Dictionary):
					continue
				var ed2: Dictionary = e as Dictionary
				var p2: Variant = ed2.get("pos", null)
				if str(ed2.get("kind", "")) in ["startled", "bullied", "threat"] and p2 is Vector3 \
						and float(ed2.get("weight", 0.0)) >= 0.35:
					pts.append({"p": p2, "c": -1})
	var radius: float = DANGER_RADIUS if kind == "danger" else SAFE_RADIUS
	var taken: Array = []
	for i in pts.size():
		if taken.has(i):
			continue
		var center: Vector3 = (pts[i] as Dictionary)["p"] as Vector3
		var members: Array = []
		var cycles: Dictionary = {}
		for j in pts.size():
			if taken.has(j):
				continue
			var pj: Vector3 = (pts[j] as Dictionary)["p"] as Vector3
			if pj.distance_to(center) < radius:
				members.append(j)
				cycles[int((pts[j] as Dictionary)["c"])] = true
		var need: int = 2
		if members.size() < need or (kind == "safe" and cycles.size() < 2):
			continue
		var sum: Vector3 = Vector3.ZERO
		for j in members:
			sum += (pts[j] as Dictionary)["p"] as Vector3
			taken.append(j)
		var c: Vector3 = sum / float(members.size())
		var region: String = region_name(f, c)
		# One belief per named region, so repeated frights reinforce, not duplicate.
		var today: bool = cycles.has(int(st.get("cycle", 0)))
		_upsert(st, "%s@%s" % [kind, region], {"kind": kind, "p": _pos_arr(c), "region": region},
				float(members.size()) - 1.0, supported, today, today or cycles.has(-1))


static func _form_chaser_beliefs(f, st: Dictionary, recent: Array, supported: Dictionary) -> void:
	var by_subj: Dictionary = {}
	for e in recent:
		var ed: Dictionary = e as Dictionary
		if str(ed.get("k", "")) != "chased" or str(ed.get("s", "")) == "":
			continue
		var sid: String = str(ed["s"])
		if not by_subj.has(sid):
			by_subj[sid] = {"n": 0, "sum": Vector3.ZERO, "np": 0, "name": str(ed.get("n", "")), "today": false}
		var rec: Dictionary = by_subj[sid] as Dictionary
		rec["n"] = int(rec["n"]) + 1
		if int(ed.get("c", -1)) == int(st.get("cycle", 0)):
			rec["today"] = true
		var ep: Variant = _arr_pos(ed.get("p", null))
		if ep is Vector3:
			rec["sum"] = (rec["sum"] as Vector3) + (ep as Vector3)
			rec["np"] = int(rec["np"]) + 1
	for sid in by_subj.keys():
		var rec: Dictionary = by_subj[sid] as Dictionary
		if int(rec["n"]) < 2:
			continue
		var fields: Dictionary = {"kind": "chaser", "subj": str(sid), "who": str(rec["name"])}
		if int(rec["np"]) > 0:
			var c: Vector3 = (rec["sum"] as Vector3) / float(int(rec["np"]))
			fields["p"] = _pos_arr(c)
			fields["region"] = region_name(f, c)
		_upsert(st, "chaser:%s" % str(sid), fields, float(int(rec["n"])) - 1.0, supported,
				bool(rec["today"]), bool(rec["today"]))


static func _form_keeper_tone(_f, st: Dictionary, recent: Array, supported: Dictionary) -> void:
	var soft: int = 0
	var sharp: int = 0
	var today: bool = false
	for e in recent:
		var k: String = str((e as Dictionary).get("k", ""))
		if k in ["kind_word", "harsh_word"] and int((e as Dictionary).get("c", -1)) == int(st.get("cycle", 0)):
			today = true
		if k == "kind_word":
			soft += 1
		elif k == "harsh_word":
			sharp += 1
	if soft >= 2 and soft >= sharp * 3:
		_upsert(st, "keeper_gentle", {"kind": "keeper_gentle"}, float(soft - 1), supported, today, today)
	elif sharp >= 2 and sharp >= soft * 3:
		_upsert(st, "keeper_harsh", {"kind": "keeper_harsh"}, float(sharp - 1), supported, today, today)


# Sleep replay: the memories that fed a belief tonight are rehearsed.
static func _replay_episodes(f) -> void:
	var store: Variant = f.get("_episodic_store")
	if not (store is Array):
		return
	var n: int = 0
	for e in (store as Array):
		if n >= 4 or not (e is Dictionary):
			continue
		var ed: Dictionary = e as Dictionary
		if str(ed.get("kind", "")) in ["fed", "food", "startled", "bullied", "keeper_word", "player"] \
				and float(ed.get("weight", 0.0)) >= 0.35:
			ed["weight"] = minf(1.0, float(ed["weight"]) + 0.02)
			n += 1


static func _remember_semantic(f, line: String) -> void:
	var sm: Variant = f.get("semantic_memory")
	if line == "" or not (sm is Array):
		return
	var fact: String = "believe: %s" % line
	if (sm as Array).has(fact):
		return
	(sm as Array).append(fact)
	while (sm as Array).size() > 16:
		(sm as Array).pop_front()


static func _forget_semantic(f, line: String) -> void:
	var sm: Variant = f.get("semantic_memory")
	if line != "" and sm is Array:
		(sm as Array).erase("believe: %s" % line)


# ---- trait drift (#2) ----

static func apply_night_drift(f, sim: Node = null) -> Dictionary:
	var st: Dictionary = ensure(f)
	_ensure_birth(f, st)
	var pers: Variant = f.get("personality")
	var ex: Dictionary = st.get("exp", {}) as Dictionary
	st["exp"] = {}
	if not (pers is Dictionary) or (pers as Dictionary).is_empty():
		return {}
	var chased: float = minf(float(ex.get("chased", 0.0)), 3.0)
	var startled: float = minf(float(ex.get("startled", 0.0)), 3.0)
	var hand_fed: float = minf(float(ex.get("hand_fed", 0.0)), 3.0)
	var soft: float = minf(float(ex.get("kind", 0.0)), 3.0)
	var sharp: float = minf(float(ex.get("harsh", 0.0)), 3.0)
	var fed: float = float(ex.get("fed", 0.0)) + float(ex.get("keeper_feed", 0.0))
	var warm: float = minf(float(ex.get("warm_s", 0.0)) / 30.0, 3.0)
	var fear: float = minf(float(ex.get("fear_s", 0.0)) / 30.0, 3.0)
	var curious: float = minf(float(ex.get("curious_s", 0.0)) / 30.0, 3.0)
	var rank_pull: float = clampf(float(ex.get("rank_pull", 0.0)), -0.01, 0.01)
	var quiet: bool = chased + startled < 0.5 and fear < 0.5 and fed > 0.0
	var deltas: Dictionary = {
		"boldness": 0.006 * hand_fed + 0.004 * soft + 0.002 * warm
				- 0.008 * chased - 0.005 * startled - 0.004 * sharp - 0.003 * fear + rank_pull,
		"calm": (0.004 if quiet else 0.0) - 0.004 * (chased + startled) - 0.002 * fear - 0.002 * sharp,
		"sociability": 0.004 * soft + 0.002 * warm + 0.002 * hand_fed - 0.003 * sharp,
		"curiosity": 0.003 * curious - 0.002 * startled,
	}
	var causes: Dictionary = {
		"chased": 0.008 * chased, "startled": 0.005 * startled + 0.003 * fear,
		"hand_fed": 0.006 * hand_fed + 0.002 * warm, "kind": 0.004 * soft,
		"harsh": 0.004 * sharp, "calm_days": 0.004 if quiet else 0.0,
	}
	var birth: Dictionary = st.get("birth", {}) as Dictionary
	var log_arr: Array = st.get("drift_log", []) as Array
	var applied: Dictionary = {}
	for k in TRAIT_KEYS:
		var d: float = clampf(float(deltas.get(k, 0.0)), -DRIFT_NIGHT_MAX, DRIFT_NIGHT_MAX)
		if absf(d) < 0.0005:
			continue
		var cur: float = float((pers as Dictionary).get(k, 0.5))
		var b0: float = float(birth.get(k, cur))
		var nv: float = clampf(cur + d, maxf(0.05, b0 - DRIFT_TOTAL_MAX), minf(1.0, b0 + DRIFT_TOTAL_MAX))
		var real_d: float = nv - cur
		if absf(real_d) < 0.0005:
			continue
		(pers as Dictionary)[k] = snappedf(nv, 0.0001)
		applied[k] = real_d
		if absf(real_d) >= 0.004:
			log_arr.append({"c": int(st.get("cycle", 0)), "t": k, "d": snappedf(real_d, 0.0001),
					"why": _pick_cause(causes, real_d > 0.0)})
		_drift_milestone(f, st, k, cur - b0, nv - b0, sim)
	while log_arr.size() > DRIFT_LOG_MAX:
		log_arr.pop_front()
	st["drift_log"] = log_arr
	return applied


static func _pick_cause(causes: Dictionary, up: bool) -> String:
	var pos_keys: Array = ["hand_fed", "kind", "calm_days"]
	var best: String = ""
	var best_v: float = 0.0
	for k in causes.keys():
		if pos_keys.has(k) != up:
			continue
		if float(causes[k]) > best_v:
			best_v = float(causes[k])
			best = str(k)
	return best


static func _drift_milestone(f, st: Dictionary, trait_key: String, before: float, after: float,
		sim: Node) -> void:
	if trait_key not in ["boldness", "calm", "sociability"]:
		return
	var step_before: int = int(floorf(absf(before) / DRIFT_MILESTONE_STEP))
	var step_after: int = int(floorf(absf(after) / DRIFT_MILESTONE_STEP))
	if step_after <= step_before:
		return
	var line: String = self_change_line(f)
	if line == "":
		return
	if _add_milestone(f, st, "drift_%s_%d%s" % [trait_key, step_after, "u" if after > 0.0 else "d"], line):
		if f is Fish:
			MindSelfModel.update_self_summary(f as Fish, line, sim)


# ---- voice & context ----

static func belief_line(_f, bd: Dictionary) -> String:
	var conf: float = float(bd.get("conf", 0.0))
	match str(bd.get("kind", "")):
		"feed_time":
			var when: String = phase_name(int(bd.get("phase", 0)))
			if int(bd.get("miss", 0)) >= 2 and conf < 0.35:
				return "you used to come %s" % when
			return "you come %s" % when
		"danger":
			return "%s isn't safe" % str(bd.get("region", "that place"))
		"safe":
			return "%s is safe" % str(bd.get("region", "my spot"))
		"chaser":
			var who: String = str(bd.get("who", ""))
			if who == "":
				who = "that one"
			if bd.has("region"):
				return "%s chases near %s" % [who, str(bd["region"])]
			return "%s chases me" % who
		"keeper_gentle":
			return "your voice is soft"
		"keeper_harsh":
			return "your voice is sharp"
	return ""


static func _voice(f, st: Dictionary, sim: Node, line: String, tag: String, strength: float) -> void:
	if line == "":
		return
	var cycle: int = int(st.get("cycle", 0))
	if int(st.get("voice_c", -1)) != cycle:
		st["voice_c"] = cycle
		st["voice_n"] = 0
	if int(st.get("voice_n", 0)) >= 2:
		return
	st["voice_n"] = int(st.get("voice_n", 0)) + 1
	if f is Fish:
		FishMind.record_salient(f, tag, line, clampf(0.35 + strength * 0.3, 0.1, 0.8), pos_of(f))
	var voiced: bool = (f.get("fish_name") != null and str(f.get("fish_name")) != "") \
			or f.get("is_guardian") == true \
			or (f.get("familiarity") != null and float(f.get("familiarity")) > 0.3)
	if not voiced:
		return
	f.set("_current_thought", line)
	f.set("_thought_stream", line)
	f.set("_thought_stream_age", 0.0)
	var s: Node = sim
	if s == null:
		var fs: Variant = f.get("sim")
		if fs != null and is_instance_valid(fs) and fs is Node:
			s = fs as Node
	if s != null and is_instance_valid(s) and s.has_method("append_fish_journal_entry"):
		s.append_fish_journal_entry(f, line, PackedStringArray(["learned", tag]))


static func strongest_beliefs(f, n: int = 3) -> Array:
	var st: Dictionary = ensure(f)
	var arr: Array = (st.get("beliefs", []) as Array).duplicate()
	arr.sort_custom(func(a, b): return float(a.get("conf", 0.0)) > float(b.get("conf", 0.0)))
	return arr.slice(0, mini(n, arr.size()))


static func belief_conf(f, id: String) -> float:
	for b in (ensure(f).get("beliefs", []) as Array):
		if str((b as Dictionary).get("id", "")) == id:
			return float((b as Dictionary).get("conf", 0.0))
	return 0.0


# Voice grounding for MindContext (template voice + LLM prompt).
static func context_for(f) -> Dictionary:
	var out: Dictionary = {}
	if f == null or not (f.get("_learned_mind") is Dictionary):
		return out
	var lines: PackedStringArray = PackedStringArray()
	for b in strongest_beliefs(f, 3):
		if float((b as Dictionary).get("conf", 0.0)) < 0.3:
			continue
		var l: String = belief_line(f, b as Dictionary)
		if l != "":
			lines.append(l)
	if not lines.is_empty():
		out["beliefs"] = lines
		out["belief_line"] = lines[0]
	var cue: Variant = f.get("_belief_cue")
	if cue is Dictionary and str((cue as Dictionary).get("label", "")) == "anticipate":
		out["anticipating"] = str((cue as Dictionary).get("line", "food soon"))
	var sc: String = self_change_line(f)
	if sc != "":
		out["self_change"] = sc
	var ll: String = life_line(f)
	if ll != "":
		out["life_line"] = ll
	return out


# ---- workspace + steering reads (cheap: cue is rebuilt once a second) ----

static func collect_bid(f) -> Dictionary:
	var cue: Variant = _prop(f, "_belief_cue")
	if not (cue is Dictionary):
		return {}
	var label: String = str((cue as Dictionary).get("label", ""))
	var sal: float = float((cue as Dictionary).get("sal", 0.0))
	if label == "" or sal <= 0.05:
		return {}
	var coal: Array = ["belief", "food", "anticipation"] if label == "anticipate" \
			else ["belief", "novelty", "surprise"]
	return {"label": label, "salience": sal, "coalition": coal}


static func cue_target(f) -> Variant:
	var cue: Variant = _prop(f, "_belief_cue")
	if cue is Dictionary and (cue as Dictionary).get("pos") is Vector3:
		return (cue as Dictionary)["pos"]
	return null


# Unnormalized push away from learned danger (confidence-weighted).
static func danger_push(f, at_pos: Vector3) -> Vector3:
	var cue: Variant = _prop(f, "_belief_cue")
	if not (cue is Dictionary) or not (cue as Dictionary).has("danger"):
		return Vector3.ZERO
	var push: Vector3 = Vector3.ZERO
	for d in ((cue as Dictionary)["danger"] as Array):
		var dd: Dictionary = d as Dictionary
		var away: Vector3 = at_pos - (dd["p"] as Vector3)
		away.y *= 0.3
		var dist: float = away.length()
		if dist < 0.05 or dist > DANGER_RADIUS:
			continue
		push += away / dist * (1.0 - dist / DANGER_RADIUS) * float(dd.get("w", 0.0))
	return push


static func region_name(f, p: Vector3) -> String:
	var hw: float = 8.0
	var hh: float = 7.0
	if f != null and f is Fish:
		var w: Node = (f as Fish)._world_node()
		if w != null:
			if w.get("TANK_HALF_W") != null:
				hw = float(w.get("TANK_HALF_W"))
			if w.get("TANK_HEIGHT") != null:
				hh = float(w.get("TANK_HEIGHT"))
	var side: String = ""
	if p.x < -hw / 3.0:
		side = "left"
	elif p.x > hw / 3.0:
		side = "right"
	var level: String = ""
	if p.y < hh * 0.3:
		level = "low"
	elif p.y > hh * 0.7:
		level = "high"
	if side != "":
		match level:
			"low":
				return "the low %s corner" % side
			"high":
				return "up top on the %s" % side
		return "the %s side" % side
	match level:
		"low":
			return "the bottom"
		"high":
			return "up near the surface"
	return "the open middle"


# ---- save / load (bounded + migrating) ----

static func to_dict(f) -> Dictionary:
	var cur: Variant = _prop(f, "_learned_mind")
	if not (cur is Dictionary):
		return {}
	return (cur as Dictionary).duplicate(true)


static func from_dict(f, d: Variant) -> void:
	if f == null:
		return
	var st: Dictionary = _fresh()
	if not (d is Dictionary) or (d as Dictionary).is_empty():
		# Old save (no learned mind yet): start fresh. The birth personality is
		# captured lazily at the first tick, and the first night pass replays
		# the loaded episodic store for danger evidence.
		f.set("_learned_mind", st)
		return
	var src: Dictionary = d as Dictionary
	st["cycle"] = maxi(0, int(SaveHelpers._num(src.get("cycle", 0), 0.0)))
	st["night_c"] = int(SaveHelpers._num(src.get("night_c", -1), -1.0))
	st["maturity"] = int(SaveHelpers._num(src.get("maturity", -1), -1.0))
	st["voice_c"] = int(SaveHelpers._num(src.get("voice_c", -1), -1.0))
	st["voice_n"] = int(SaveHelpers._num(src.get("voice_n", 0), 0.0))
	st["events"] = _clean_list(src.get("events", null), EVENTS_MAX, "k")
	var beliefs: Array = _clean_list(src.get("beliefs", null), BELIEFS_MAX, "id")
	for b in beliefs:
		var bd: Dictionary = b as Dictionary
		bd["conf"] = clampf(SaveHelpers._num(bd.get("conf", 0.3), 0.3), 0.0, 0.98)
		if bd.has("phase"):
			bd["phase"] = clampi(int(SaveHelpers._num(bd["phase"], 0.0)), 0, PHASE_BUCKETS - 1)
		for ik in ["formed_c", "last_c", "hit_c", "chk_c", "ext_c", "ok", "miss"]:
			if bd.has(ik):
				bd[ik] = int(SaveHelpers._num(bd[ik], 0.0))
		if bd.has("p") and not (_arr_pos(bd["p"]) is Vector3):
			bd.erase("p")
	st["beliefs"] = beliefs
	st["drift_log"] = _clean_list(src.get("drift_log", null), DRIFT_LOG_MAX, "t")
	st["milestones"] = _clean_list(src.get("milestones", null), MILESTONES_MAX, "tag")
	var ex: Dictionary = {}
	if src.get("exp") is Dictionary:
		for k in (src["exp"] as Dictionary).keys():
			ex[str(k)] = clampf(SaveHelpers._num((src["exp"] as Dictionary)[k], 0.0), -1000.0, 100000.0)
	st["exp"] = ex
	var birth: Dictionary = {}
	if src.get("birth") is Dictionary:
		for k in TRAIT_KEYS:
			if (src["birth"] as Dictionary).has(k):
				birth[k] = clampf(SaveHelpers._num((src["birth"] as Dictionary)[k], 0.5), 0.05, 1.0)
	st["birth"] = birth
	var hab: Dictionary = {}
	if src.get("hab") is Dictionary:
		for k in (src["hab"] as Dictionary).keys():
			var h: Variant = (src["hab"] as Dictionary)[k]
			if h is Dictionary and hab.size() < HAB_MAX:
				hab[str(k)] = {"n": maxf(0.0, SaveHelpers._num((h as Dictionary).get("n", 0.0), 0.0)),
						"c": int(SaveHelpers._num((h as Dictionary).get("c", 0), 0.0))}
	st["hab"] = hab
	var gs: Array = []
	if src.get("gseen") is Array:
		for g in (src["gseen"] as Array):
			if gs.size() < GRUDGE_SEEN_MAX:
				gs.append(str(g))
	st["gseen"] = gs
	# The sim's day_phase is saved too, so keeping last_phase lets a wrap that
	# happens across the load still advance the life clock.
	var lp: float = SaveHelpers._num(src.get("last_phase", -1.0), -1.0)
	st["last_phase"] = lp if lp >= 0.0 and lp < 1.0 else -1.0
	f.set("_learned_mind", st)


static func _clean_list(v: Variant, cap: int, required_key: String) -> Array:
	var out: Array = []
	if not (v is Array):
		return out
	for e in (v as Array):
		if e is Dictionary and (e as Dictionary).has(required_key):
			out.append((e as Dictionary).duplicate(true))
	while out.size() > cap:
		out.pop_front()
	return out


static func clear_for_test() -> void:
	_tick_acc.clear()
