extends RefCounted

# Fish social graph: friendships, rivalries, mates, parent/offspring,
# shoal-mates, and the remembered "that one chased me".
#
# Builds on state that already existed rather than duplicating it:
#   - `Fish.bonds` (id -> affinity -1..1) stays the CANONICAL affinity. The
#     boids friend-pull, FishMind.bond_seek_steer, mind_soul_pass2/3,
#     mind_daring and mind_context all read it, so every relationship this
#     module grows is immediately visible to that existing behaviour. Before
#     this module the only writer was the breeding pair-bond, so the "built
#     from repeated co-schooling and grudges" comment on `bonds` was untrue.
#   - `Fish.grudges` (id -> seconds) is still written by the territorial chase.
#     We DETECT new grudge keys as chase events, and keep a grudge alive for a
#     settled rival so the existing grudge-avoid steering keeps them apart.
#
# Everything else lives in one per-fish dictionary, `Fish.social`:
#   rel:    {other_id: {fam 0..1, ev last_event, t unix, tags [..], n name}}
#   grief:  {id, n, lvl 0..1, at [x,y,z]}   (absent when not grieving)
#   gseen:  {grudge_id: true}               grudge keys seen last tick
#   spawn_t unix of this fish's last spawn  (parent detection for fry)
#   meals / offs: last-seen bio counters    (event detection by delta)
#   ate:    ticks-seconds of last detected meal (transient, not saved)
#
# Cost: `tick()` runs on the fish's existing 5 s decay throttle, which is
# already phase-staggered per fish. One linear pass over the roster per fish
# per tick (no per-frame work, no O(n^2) per frame). Maps are bounded to
# MAX_REL entries. The only per-frame read is grief_level(), a dict lookup.
#
# No class_name on purpose: fish.gd preloads this, and a new class_name would
# need an editor rescan before fish.gd compiled headlessly. Consumers:
#   const FishSocial = preload("res://scripts/fish_social.gd")

const EpisodicMemory = preload("res://scripts/episodic_memory.gd")

const MAX_REL: int = 12

const FRIEND_AFF: float = 0.3
const CLOSE_AFF: float = 0.6
const RIVAL_AFF: float = -0.3
const GRIEF_AFF: float = 0.45

const SCHOOL_R2: float = 4.0          # 2 units: swimming together
const SCHOOL_ALIGN: float = 0.7       # heading dot to count as schooling
const SCHOOL_GAIN: float = 0.035      # per tick, for the 3 closest shoal-mates
const SCHOOL_MAX_PARTNERS: int = 3
const SLEEP_R2: float = 2.25
const SLEEP_GAIN: float = 0.04
const MEAL_R2: float = 2.25
const MEAL_WINDOW_S: float = 6.0
const SHARE_GAIN: float = 0.03
const STEAL_LOSS: float = 0.05
const CHASED_LOSS: float = 0.25       # victim's opinion of the chaser
const CHASER_LOSS: float = 0.08       # chaser's opinion of the victim
const SPAWN_GAIN: float = 0.2
const KIN_GAIN: float = 0.35
const GUARD_GAIN: float = 0.02
const KIN_FLOOR: float = 0.15         # kin/mates never drift fully neutral
const KIN_WINDOW_S: int = 600         # fry adopt a parent that spawned within this
const FRY_ADOPT_AGE_S: float = 120.0
const RIVAL_GRUDGE_S: float = 20.0

const AFF_DECAY: float = 0.0015       # per second toward 0, damped by familiarity
const FAM_DECAY: float = 0.0004       # per second
const FAM_GAIN: float = 0.02          # per co-presence tick

const GRIEF_DECAY: float = 0.0035     # per second: a close loss lasts ~4-5 min
const GRIEF_SLOW: float = 0.35        # top-speed cut at full grief
const GRIEF_PULL: float = 0.18        # steer weight toward the loss spot


# --- Core state ---------------------------------------------------------------

static func state(f) -> Dictionary:
	var s: Variant = f.get("social")
	if not (s is Dictionary):
		s = {}
		f.social = s
	return s as Dictionary


static func _rels(f) -> Dictionary:
	var s: Dictionary = state(f)
	if not (s.get("rel") is Dictionary):
		s["rel"] = {}
	return s["rel"] as Dictionary


static func _entry(f, oid: String) -> Dictionary:
	var rels: Dictionary = _rels(f)
	if not rels.has(oid):
		rels[oid] = {"fam": 0.0, "ev": "", "t": 0, "tags": [], "n": ""}
	return rels[oid] as Dictionary


static func affinity(f, oid: String) -> float:
	if f == null or oid == "":
		return 0.0
	return float(f.bonds.get(oid, 0.0))


static func _unix() -> int:
	return int(Time.get_unix_time_from_system())


static func _now_s() -> float:
	return Time.get_ticks_msec() / 1000.0


static func name_of(f) -> String:
	if f == null or not is_instance_valid(f):
		return ""
	var nm: String = String(f.get("fish_name")) if f.get("fish_name") != null else ""
	if nm != "":
		return nm
	var sp: String = String(f.get("species")) if f.get("species") != null else ""
	return ("a " + sp.capitalize().to_lower()) if sp != "" else "another fish"


# Apply one social event from `f`'s point of view toward `other`.
# `other` may be a Fish or a String id. Returns the new affinity.
static func record_event(f, other, kind: String, delta_aff: float,
		tag: String = "", fam_gain: float = FAM_GAIN) -> float:
	if f == null:
		return 0.0
	var oid: String = ""
	var nm: String = ""
	if typeof(other) == TYPE_STRING:
		oid = String(other)
	elif other != null and is_instance_valid(other):
		oid = String(other.id)
		nm = name_of(other)
	if oid == "" or oid == String(f.id):
		return 0.0
	var e: Dictionary = _entry(f, oid)
	var before: float = affinity(f, oid)
	var after: float = clampf(before + delta_aff, -1.0, 1.0)
	f.bonds[oid] = after
	e["fam"] = clampf(float(e.get("fam", 0.0)) + fam_gain, 0.0, 1.0)
	e["ev"] = kind
	e["t"] = _unix()
	if nm != "":
		e["n"] = nm
	if tag != "":
		var tags: Array = e.get("tags", []) as Array
		if not tags.has(tag):
			tags.append(tag)
			e["tags"] = tags
	_note_crossing(f, oid, before, after, e)
	_enforce_bound(f)
	return after


static func has_tag(f, oid: String, tag: String) -> bool:
	var rels: Dictionary = _rels(f)
	if not rels.has(oid):
		return false
	return ((rels[oid] as Dictionary).get("tags", []) as Array).has(tag)


# Threshold crossings become episodic memories - rate-limited by nature,
# since a crossing happens once per relationship arc.
static func _note_crossing(f, _oid: String, before: float, after: float, e: Dictionary) -> void:
	var nm: String = String(e.get("n", ""))
	if nm == "":
		nm = "another fish"
	if before < GRIEF_AFF and after >= GRIEF_AFF:
		_episode(f, "befriended", "%s became my friend" % nm, 0.5)
	elif before > RIVAL_AFF - 0.1 and after <= RIVAL_AFF - 0.1:
		_episode(f, "rival", "%s is my rival" % nm, 0.55)


static func _episode(f, kind: String, text: String, salience: float) -> void:
	if f == null or not is_instance_valid(f):
		return
	if not (f is Fish):
		return
	EpisodicMemory.encode_episode(f, kind, text, salience, f.position)


# Keep both `rel` and `bonds` within MAX_REL. Weakest relationships go first;
# kin and mates get a protection bonus, the dead are remembered but cheap.
static func _enforce_bound(f) -> void:
	var rels: Dictionary = _rels(f)
	var guard: int = 0
	while (rels.size() > MAX_REL or f.bonds.size() > MAX_REL) and guard < 64:
		guard += 1
		var worst: String = ""
		var worst_score: float = INF
		var keys: Array = rels.keys()
		for k in f.bonds.keys():
			if not rels.has(k):
				keys.append(k)
		for k in keys:
			var e: Dictionary = rels.get(k, {}) as Dictionary
			var sc: float = absf(float(f.bonds.get(k, 0.0))) * 0.7 + float(e.get("fam", 0.0)) * 0.3
			var tags: Array = e.get("tags", []) as Array
			if tags.has("mate") or tags.has("kin"):
				sc += 0.5
			if tags.has("dead"):
				sc -= 0.2
			if String(state(f).get("grief", {}).get("id", "")) == String(k):
				sc += 2.0
			if sc < worst_score:
				worst_score = sc
				worst = String(k)
		if worst == "":
			break
		rels.erase(worst)
		f.bonds.erase(worst)


# --- Periodic tick (called from the fish's 5 s decay throttle) ----------------

static func tick(f, dt: float) -> void:
	if f == null or f.get("_dying") == true:
		return
	var others: Array = []
	var sim: Variant = f.get("sim")
	if sim != null and is_instance_valid(sim) and sim.get("fish") != null:
		others = sim.fish
	tick_among(f, dt, others, _now_s(), _unix())


static func tick_among(f, dt: float, others: Array, now_s: float, now_unix: int) -> void:
	var s: Dictionary = state(f)
	var my_id: String = String(f.id)
	# Migration: a fish loaded from an older save has grudges but no record of
	# having seen them - adopt them silently instead of replaying old chases.
	if not s.has("gseen"):
		s["gseen"] = _grudge_keys(f)
	_detect_self_events(f, s, now_s, now_unix)
	_detect_chases(f, s, others)
	if my_id != "":
		_scan_neighbours(f, s, others, now_s, now_unix)
	_decay(f, dt)
	_tick_grief(f, s, dt)
	_keep_rivals_apart(f, others)
	s["gseen"] = _grudge_keys(f)


static func _detect_self_events(f, s: Dictionary, now_s: float, now_unix: int) -> void:
	var bio: Dictionary = f.bio if f.get("bio") is Dictionary else {}
	var meals: int = int(bio.get("meals_eaten", 0))
	if s.has("meals") and meals > int(s["meals"]):
		s["ate"] = now_s
	s["meals"] = meals
	var offs: int = int(bio.get("offspring", 0))
	if s.has("offs") and offs > int(s["offs"]):
		s["spawn_t"] = now_unix
		var mate = f.get("partner")
		if mate != null and is_instance_valid(mate):
			record_event(f, mate, "spawned together", SPAWN_GAIN, "mate", 0.2)
			_episode(f, "spawned", "spawned with %s" % name_of(mate), 0.6)
		elif String(f.get("_mate_id")) != "":
			record_event(f, String(f._mate_id), "spawned together", SPAWN_GAIN, "mate", 0.2)
	s["offs"] = offs


static func _grudge_keys(f) -> Dictionary:
	var out: Dictionary = {}
	for k in f.grudges.keys():
		out[String(k)] = true
	return out


# A grudge key we did not see last tick = someone just chased us.
static func _detect_chases(f, s: Dictionary, others: Array) -> void:
	if f.grudges.is_empty():
		return
	var seen: Dictionary = s.get("gseen", {}) as Dictionary
	for k in f.grudges.keys():
		var cid: String = String(k)
		if seen.has(cid):
			continue
		var chaser = _find(others, cid)
		var first: bool = not has_tag(f, cid, "chased_me")
		record_event(f, chaser if chaser != null else cid, "chased me",
			-CHASED_LOSS, "chased_me", 0.05)
		if first:
			var nm: String = name_of(chaser) if chaser != null else "a bigger fish"
			_episode(f, "bullied", "%s chased me" % nm, 0.55)
		if chaser != null and chaser.get("social") is Dictionary:
			record_event(chaser, f, "chased them off", -CHASER_LOSS, "chased", 0.03)


static func _find(others: Array, oid: String):
	for o in others:
		if o != null and is_instance_valid(o) and String(o.id) == oid:
			return o
	return null


static func _scan_neighbours(f, s: Dictionary, others: Array, now_s: float, now_unix: int) -> void:
	var pos: Vector3 = f.position
	var hdg: Vector3 = f.heading if f.get("heading") is Vector3 else Vector3.ZERO
	var i_ate: bool = now_s - float(s.get("ate", -999.0)) < MEAL_WINDOW_S
	var hungry: bool = float(f.get("hunger")) > 0.55
	var asleep: bool = f.get("_asleep") == true
	var is_fry: bool = int(f.maturity) == Fish.MATURITY_FRY and float(f.age) < FRY_ADOPT_AGE_S
	var need_parent: bool = is_fry and not _has_any_tag(f, "parent")
	var best_parent = null
	var best_parent_d2: float = 9.0
	# Up to SCHOOL_MAX_PARTNERS closest aligned shoal-mates, so a school of 30
	# grows a few real friendships instead of 30 identical lukewarm ones.
	var school: Array = []
	var school_d2: Array = []
	for o in others:
		if o == f or o == null or not is_instance_valid(o) or o.get("_dying") == true:
			continue
		if String(o.id) == "":
			continue
		var d2: float = pos.distance_squared_to(o.position)
		if d2 > 9.0:
			continue
		var same: bool = String(o.species) == String(f.species)
		var os: Dictionary = o.social if o.get("social") is Dictionary else {}
		# Keep the cached name fresh (the keeper can rename a fish).
		var rels: Dictionary = _rels(f)
		if rels.has(String(o.id)):
			(rels[String(o.id)] as Dictionary)["n"] = name_of(o)
		if same and d2 < SCHOOL_R2 and not asleep:
			var ohdg: Vector3 = o.heading if o.get("heading") is Vector3 else Vector3.ZERO
			if hdg.length_squared() > 1e-4 and ohdg.length_squared() > 1e-4 \
					and hdg.normalized().dot(ohdg.normalized()) > SCHOOL_ALIGN:
				_insert_closest(school, school_d2, o, d2)
		if asleep and o.get("_asleep") == true and d2 < SLEEP_R2:
			record_event(f, o, "slept beside me", SLEEP_GAIN, "", 0.03)
		if d2 < MEAL_R2:
			var o_ate: bool = now_s - float(os.get("ate", -999.0)) < MEAL_WINDOW_S
			if o_ate and i_ate:
				record_event(f, o, "shared a meal", SHARE_GAIN, "", 0.02)
			elif o_ate and not i_ate and hungry and d2 < 1.0:
				record_event(f, o, "took my food", -STEAL_LOSS, "food_thief", 0.01)
		if need_parent and same and int(o.maturity) != Fish.MATURITY_FRY and d2 < best_parent_d2:
			var st: int = int(os.get("spawn_t", 0))
			if st > 0 and _unix_now_cached(now_unix) - st < KIN_WINDOW_S:
				best_parent = o
				best_parent_d2 = d2
		# Parent guarding its fry: the bond grows on both sides.
		if not is_fry and float(f.get("brooding_remaining")) > 0.0 \
				and has_tag(f, String(o.id), "offspring"):
			record_event(f, o, "guarded", GUARD_GAIN, "", 0.02)
			record_event(o, f, "guarded me", GUARD_GAIN, "", 0.02)
	for i in school.size():
		record_event(f, school[i], "schooled together", SCHOOL_GAIN, "shoal", FAM_GAIN)
	if best_parent != null:
		record_event(f, best_parent, "my parent", KIN_GAIN, "parent", 0.3)
		_add_tag(f, String(best_parent.id), "kin")
		record_event(best_parent, f, "my offspring", KIN_GAIN, "offspring", 0.3)
		_add_tag(best_parent, String(f.id), "kin")
		_episode(best_parent, "offspring", "%s hatched from my clutch" % name_of(f), 0.5)


static func _add_tag(f, oid: String, tag: String) -> void:
	var e: Dictionary = _entry(f, oid)
	var tags: Array = e.get("tags", []) as Array
	if not tags.has(tag):
		tags.append(tag)
	e["tags"] = tags


static func _unix_now_cached(v: int) -> int:
	return v if v > 0 else _unix()


static func _insert_closest(arr: Array, d2s: Array, o, d2: float) -> void:
	var i: int = 0
	while i < d2s.size() and float(d2s[i]) <= d2:
		i += 1
	if i >= SCHOOL_MAX_PARTNERS:
		return
	arr.insert(i, o)
	d2s.insert(i, d2)
	if arr.size() > SCHOOL_MAX_PARTNERS:
		arr.resize(SCHOOL_MAX_PARTNERS)
		d2s.resize(SCHOOL_MAX_PARTNERS)


static func _has_any_tag(f, tag: String) -> bool:
	var rels: Dictionary = _rels(f)
	for k in rels:
		if ((rels[k] as Dictionary).get("tags", []) as Array).has(tag):
			return true
	return false


# Affinity relaxes toward 0 (the old bond-arc decay subtracted a constant,
# which drove every RIVAL toward -1 over time). Familiar pairs relax slower;
# kin and mates keep a small positive floor while still familiar.
static func _decay(f, dt: float) -> void:
	var rels: Dictionary = _rels(f)
	var drop: Array = []
	for k in f.bonds.keys():
		var oid: String = String(k)
		var aff: float = float(f.bonds[k])
		var e: Dictionary = rels.get(oid, {}) as Dictionary
		var fam: float = float(e.get("fam", 0.0))
		var step: float = AFF_DECAY * dt * (1.0 - 0.6 * fam)
		if aff > 0.0:
			aff = maxf(0.0, aff - step)
		else:
			aff = minf(0.0, aff + step)
		var tags: Array = e.get("tags", []) as Array
		if (tags.has("kin") or tags.has("mate")) and fam > 0.2 and not tags.has("dead"):
			aff = maxf(aff, KIN_FLOOR)
		f.bonds[k] = aff
		if absf(aff) < 0.01 and fam < 0.05 and tags.is_empty():
			drop.append(oid)
	for k in rels.keys():
		var e2: Dictionary = rels[k] as Dictionary
		e2["fam"] = maxf(0.0, float(e2.get("fam", 0.0)) - FAM_DECAY * dt)
		if not f.bonds.has(k) and float(e2["fam"]) <= 0.0:
			drop.append(String(k))
	for oid in drop:
		f.bonds.erase(oid)
		rels.erase(oid)
	_enforce_bound(f)


# A settled rival keeps a short grudge alive so the existing grudge-avoid
# steering (and boids separation defer) keeps the two apart. A rival close by
# also raises arousal - the posture of two fish that do not get along.
static func _keep_rivals_apart(f, others: Array) -> void:
	for k in f.bonds.keys():
		if float(f.bonds[k]) > RIVAL_AFF:
			continue
		var oid: String = String(k)
		if has_tag(f, oid, "dead"):
			continue
		f.grudges[oid] = maxf(float(f.grudges.get(oid, 0.0)), RIVAL_GRUDGE_S)
	if f.get("arousal") != null and not others.is_empty():
		var r: Dictionary = rival(f)
		if not r.is_empty() and bool(r.get("alive", false)):
			var o = _find(others, String(r["id"]))
			if o != null and o.position.distance_squared_to(f.position) < 4.0:
				f.arousal = clampf(float(f.arousal) + 0.06, 0.0, 1.0)


# --- Death + grief ------------------------------------------------------------

# Called once when `dead` starts dying (before partner refs are cleared).
static func on_death(dead) -> void:
	if dead == null:
		return
	var sim: Variant = dead.get("sim")
	if sim == null or not is_instance_valid(sim) or sim.get("fish") == null:
		return
	on_death_among(dead, sim.fish)


static func on_death_among(dead, others: Array) -> void:
	var did: String = String(dead.id)
	if did == "":
		return
	var dname: String = name_of(dead)
	var mate_id: String = String(dead.get("_mate_id")) if dead.get("_mate_id") != null else ""
	var partner = dead.get("partner")
	for o in others:
		if o == dead or o == null or not is_instance_valid(o) or o.get("_dying") == true:
			continue
		if not o.bonds.has(did) and not _rels(o).has(did):
			continue
		var aff: float = affinity(o, did)
		var is_mate: bool = has_tag(o, did, "mate") or String(o.id) == mate_id \
				or (partner != null and is_instance_valid(partner) and partner == o)
		var is_kin: bool = has_tag(o, did, "kin")
		var e: Dictionary = _entry(o, did)
		e["n"] = dname
		e["ev"] = "died"
		e["t"] = _unix()
		var tags: Array = e.get("tags", []) as Array
		if not tags.has("dead"):
			tags.append("dead")
			e["tags"] = tags
		var lvl: float = 0.0
		if aff >= GRIEF_AFF:
			lvl = clampf(aff * 1.1, 0.0, 1.0)
		if is_mate and aff > 0.1:
			lvl = maxf(lvl, clampf(aff + 0.35, 0.0, 1.0))
		elif is_kin and aff > 0.1:
			lvl = maxf(lvl, clampf(aff + 0.2, 0.0, 1.0))
		if lvl < 0.3:
			continue
		var s: Dictionary = state(o)
		var cur: Dictionary = s.get("grief", {}) as Dictionary
		if float(cur.get("lvl", 0.0)) >= lvl:
			continue
		s["grief"] = {"id": did, "n": dname, "lvl": lvl,
			"at": [dead.position.x, dead.position.y, dead.position.z]}
		o.mood = clampf(float(o.mood) - 0.3 * lvl, -1.0, 1.0)
		var what: String = "my mate" if is_mate else ("my kin" if is_kin else "my friend")
		_episode(o, "loss", "%s, %s, is gone" % [dname, what], clampf(0.5 + lvl * 0.4, 0.0, 1.0))


static func _tick_grief(f, s: Dictionary, dt: float) -> void:
	if not s.has("grief"):
		return
	var g: Dictionary = s["grief"] as Dictionary
	var lvl: float = float(g.get("lvl", 0.0)) - GRIEF_DECAY * dt
	if lvl <= 0.02:
		s.erase("grief")
		return
	g["lvl"] = lvl
	# A grieving fish's mood cannot settle high while the loss is fresh.
	if f.get("mood") != null:
		f.mood = minf(float(f.mood), lerpf(0.6, -0.4, lvl))


# Per-brain-tick reads. Cheap: one dict lookup when not grieving.
static func grief_level(f) -> float:
	var s: Variant = f.get("social")
	if not (s is Dictionary) or not (s as Dictionary).has("grief"):
		return 0.0
	return float(((s as Dictionary)["grief"] as Dictionary).get("lvl", 0.0))


# Unit direction toward where the lost companion died, or ZERO once there
# (the fish lingers at the spot rather than orbiting it).
static func grief_pull(f) -> Vector3:
	var s: Variant = f.get("social")
	if not (s is Dictionary) or not (s as Dictionary).has("grief"):
		return Vector3.ZERO
	var at: Variant = ((s as Dictionary)["grief"] as Dictionary).get("at", null)
	if not (at is Array) or (at as Array).size() < 3:
		return Vector3.ZERO
	var p := Vector3(float(at[0]), float(at[1]), float(at[2]))
	var to: Vector3 = p - f.position
	if to.length_squared() < 0.64:
		return Vector3.ZERO
	return to.normalized()


# --- Speech-ready getters -----------------------------------------------------

static func _relation_dict(f, oid: String) -> Dictionary:
	var e: Dictionary = _rels(f).get(oid, {}) as Dictionary
	var tags: Array = e.get("tags", []) as Array
	var nm: String = String(e.get("n", ""))
	return {
		"id": oid,
		"name": nm if nm != "" else "another fish",
		"affinity": affinity(f, oid),
		"familiarity": float(e.get("fam", 0.0)),
		"last_event": String(e.get("ev", "")),
		"tags": tags.duplicate(),
		"alive": not tags.has("dead"),
	}


static func _ranked(f, want_friend: bool) -> Array:
	var out: Array = []
	if f == null or not is_instance_valid(f) or not (f.get("bonds") is Dictionary):
		return out
	for k in f.bonds.keys():
		var oid: String = String(k)
		var aff: float = float(f.bonds[k])
		if has_tag(f, oid, "dead"):
			continue
		if want_friend and aff >= FRIEND_AFF:
			out.append([aff, oid])
		elif not want_friend and aff <= RIVAL_AFF:
			out.append([-aff, oid])
	out.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	return out


# {id, name, affinity, familiarity, last_event, tags, alive} or {} if none.
static func best_friend(f) -> Dictionary:
	var r: Array = _ranked(f, true)
	return {} if r.is_empty() else _relation_dict(f, String(r[0][1]))


static func friends(f, limit: int = 3) -> Array:
	var out: Array = []
	for row in _ranked(f, true):
		if out.size() >= limit:
			break
		out.append(_relation_dict(f, String(row[1])))
	return out


static func rival(f) -> Dictionary:
	var r: Array = _ranked(f, false)
	return {} if r.is_empty() else _relation_dict(f, String(r[0][1]))


# {id, name, level} while grieving, else {}.
static func grieving_for(f) -> Dictionary:
	if f == null or not is_instance_valid(f):
		return {}
	var s: Variant = f.get("social")
	if not (s is Dictionary) or not (s as Dictionary).has("grief"):
		return {}
	var g: Dictionary = (s as Dictionary)["grief"] as Dictionary
	return {"id": String(g.get("id", "")), "name": String(g.get("n", "")),
		"level": float(g.get("lvl", 0.0))}


# First-person phrase for how `f` sees `other` (Fish or id), e.g.
# "my mate Mira", "my rival Kip, who chased me", "a fish I barely know".
static func describe_relation(f, other) -> String:
	if f == null:
		return ""
	var is_id: bool = typeof(other) == TYPE_STRING
	var oid: String = ""
	if is_id:
		oid = String(other)
	elif other != null and is_instance_valid(other):
		oid = String(other.id)
	if oid == "":
		return ""
	var rels: Dictionary = _rels(f)
	if not rels.has(oid) and not f.bonds.has(oid):
		var nm0: String = "that fish" if is_id else name_of(other)
		return "%s, a fish I don't know" % nm0
	var d: Dictionary = _relation_dict(f, oid)
	var nm: String = String(d["name"])
	if not is_id and other != null and is_instance_valid(other):
		nm = name_of(other)
	var aff: float = float(d["affinity"])
	var tags: Array = d["tags"] as Array
	var role: String = ""
	if tags.has("mate"):
		role = "my mate"
	elif tags.has("parent"):
		role = "my parent"
	elif tags.has("offspring"):
		role = "my young"
	elif aff >= CLOSE_AFF:
		role = "my close friend"
	elif aff >= FRIEND_AFF:
		role = "my friend"
	elif aff <= RIVAL_AFF:
		role = "my rival"
	elif tags.has("shoal") or float(d["familiarity"]) > 0.3:
		role = "a shoal-mate"
	else:
		role = "a fish I barely know"
	var s: String = "%s %s" % [role, nm]
	if not bool(d["alive"]):
		s = "%s, who is gone" % s
	elif tags.has("chased_me") and aff < 0.0:
		s = "%s, who chased me" % s
	return s


# Short panel line: "Friends: Mira, Kip · Rival: Bo" ("" when nothing to say).
static func summary_line(f) -> String:
	var parts: Array[String] = []
	var fr: Array = friends(f, 2)
	if not fr.is_empty():
		var names: Array[String] = []
		for d in fr:
			names.append(String(d["name"]))
		parts.append("Friends: " + ", ".join(names))
	var r: Dictionary = rival(f)
	if not r.is_empty():
		parts.append("Rival: " + String(r["name"]))
	var g: Dictionary = grieving_for(f)
	if not g.is_empty() and float(g["level"]) > 0.15:
		parts.append("Missing " + String(g["name"]))
	return " · ".join(parts)


# --- Persistence --------------------------------------------------------------

static func to_save(f) -> Dictionary:
	var s: Dictionary = state(f)
	var out: Dictionary = {}
	var rels: Dictionary = {}
	for k in _rels(f).keys():
		var e: Dictionary = _rels(f)[k] as Dictionary
		rels[String(k)] = {
			"fam": snappedf(float(e.get("fam", 0.0)), 0.001),
			"ev": String(e.get("ev", "")),
			"t": int(e.get("t", 0)),
			"tags": (e.get("tags", []) as Array).duplicate(),
			"n": String(e.get("n", "")),
		}
	out["rel"] = rels
	if s.has("grief"):
		out["grief"] = (s["grief"] as Dictionary).duplicate(true)
	if s.has("gseen"):
		out["gseen"] = (s["gseen"] as Dictionary).duplicate()
	for k in ["spawn_t", "meals", "offs"]:
		if s.has(k):
			out[k] = int(s[k])
	return out


# Schema-safe: anything missing or malformed loads as an empty graph, so
# saves from before this module migrate to "no relationships yet".
static func from_save(f, v: Variant) -> void:
	var s: Dictionary = {}
	var rels: Dictionary = {}
	if v is Dictionary:
		var d: Dictionary = v as Dictionary
		var rv: Variant = d.get("rel", null)
		if rv is Dictionary:
			for k in (rv as Dictionary).keys():
				var e: Variant = (rv as Dictionary)[k]
				if not (e is Dictionary) or String(k) == "":
					continue
				var ed: Dictionary = e as Dictionary
				var tags: Array = []
				if ed.get("tags") is Array:
					for t in ed["tags"]:
						tags.append(String(t))
				rels[String(k)] = {
					"fam": clampf(SaveHelpers._num(ed.get("fam", 0.0), 0.0), 0.0, 1.0),
					"ev": String(ed.get("ev", "")),
					"t": int(SaveHelpers._num(ed.get("t", 0), 0.0)),
					"tags": tags,
					"n": String(ed.get("n", "")),
				}
		var gv: Variant = d.get("grief", null)
		if gv is Dictionary and (gv as Dictionary).has("id"):
			var g: Dictionary = (gv as Dictionary).duplicate(true)
			g["lvl"] = clampf(SaveHelpers._num(g.get("lvl", 0.0), 0.0), 0.0, 1.0)
			if float(g["lvl"]) > 0.02:
				s["grief"] = g
		if d.get("gseen") is Dictionary:
			s["gseen"] = (d["gseen"] as Dictionary).duplicate()
		for k in ["spawn_t", "meals", "offs"]:
			if d.has(k):
				s[k] = int(SaveHelpers._num(d[k], 0.0))
	s["rel"] = rels
	f.social = s
	_enforce_bound(f)
