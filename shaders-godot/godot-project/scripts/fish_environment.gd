class_name FishEnvironment
extends RefCounted

# Fish <-> environment interaction ("the fish live IN the tank, not just in
# front of it").
#
# Every few seconds (staggered per fish) a fish looks around and may pick an
# ENVIRONMENT INTENT driven by its backstory (FishBackstory likes/fears) and
# personality:
#
#   rest      - settle by its favourite spot (a specific plant species, the
#               driftwood, the cave, the lily pads, a corner...). Arriving
#               drifts its home range toward that spot, so over time the fish
#               visibly "lives" there.
#   shelter   - tuck in by driftwood / stones / cave / lily pads (shy or
#               stressed fish, and everyone at night).
#   nibble    - pick at plant leaves / biofilm (herbivores, grazers, hungry).
#   rub       - flash / rub along the substrate.
#   play      - ride the filter current.
#   bask      - hang in the lamp's light pool under the surface.
#   follow    - keep near a liked tankmate (often a parent).
#   investigate - swim over to a NEWLY PLACED object (GOALS #3 open item:
#               hardscape children / lily pads appearing are detected here).
#
# and ALWAYS steers away from its fear object when close to it.
#
# Cost model: the landmark catalogue is built once per ~10 s for the whole
# tank (static, shared by every fish) from arrays the world already keeps
# (sim.plants, world._driftwood_voxels, _rock_voxels, _build_shelter_points,
# _lily_pads, hardscape children). Per fish, a scan runs every 3-5.5 s; the
# per-tick work is one or two distance checks against cached points. No
# get_nodes_in_group anywhere.
#
# Notable moments are recorded as salient/episodic memories ("slept under the
# driftwood again") so the speech code can bring them up.
#
# fish.gd hook (tier 0, additive):  desired += FishEnvironment.steer(self, dt, effective_max)

const EpisodicMemoryScript = preload("res://scripts/episodic_memory.gd")
const SimRngScript = preload("res://scripts/sim_rng.gd")
const _Backstory = preload("res://scripts/fish_backstory.gd")

const INTENT_NONE := ""
const INTENT_REST := "rest"
const INTENT_SHELTER := "shelter"
const INTENT_NIBBLE := "nibble"
const INTENT_RUB := "rub"
const INTENT_PLAY := "play"
const INTENT_BASK := "bask"
const INTENT_FOLLOW := "follow"
const INTENT_INVESTIGATE := "investigate"

const SCAN_MIN_S: float = 3.0
const SCAN_JITTER_S: float = 2.5
const LANDMARK_REFRESH_MS: int = 10000
const NOVELTY_POLL_MS: int = 2000
const NOVELTY_TTL_MS: int = 45000
# Loading a save restores placed objects a moment after the world builds;
# don't mistake that for the keeper placing something new.
const NOVELTY_ARM_DELAY_MS: int = 15000
const NOVELTY_RADIUS: float = 10.0
const EPISODE_COOLDOWN_S: float = 45.0
const HOME_DRIFT_CAP: float = 3.0
const HOME_DRIFT_CAP_SCHOOL: float = 1.8
const DEFAULT_BOUNDS := AABB(Vector3(-8, 1.6, -4), Vector3(16, 5, 8))

# Fish.Mode ints (FLEE, COURT, SPAWN) — duck-typed to avoid a class cycle.
const _MODE_COURT := 2
const _MODE_SPAWN := 3
const _MODE_FLEE := 4

static var _lm_world_id: int = 0
static var _lm_list: Array = []
static var _lm_next_ms: int = 0
static var _nov_next_ms: int = 0
static var _nov_arm_ms: int = 0
static var _nov_hs_count: int = -1
static var _nov_lily_count: int = -1
static var _nov_list: Array = []   # {kind,label,key,pos,t_ms}
static var _test_landmarks: Variant = null


# ---------------------------------------------------------------------------
# Test hooks
# ---------------------------------------------------------------------------

static func set_landmarks_for_test(arr: Variant) -> void:
	_test_landmarks = arr
	_nov_list.clear()


static func clear_for_test() -> void:
	_test_landmarks = null
	_lm_world_id = 0
	_lm_list.clear()
	_lm_next_ms = 0
	_nov_list.clear()
	_nov_hs_count = -1
	_nov_lily_count = -1


# Public: anything that places an object (aquascape tools, future spawners)
# may announce it directly; the child-count poll below catches the rest.
static func register_novel(pos: Vector3, label: String, kind: String = "ornament") -> void:
	if not pos.is_finite():
		return
	_nov_list.append({"kind": kind, "label": label, "key": "novel:%s:%d" % [kind, Time.get_ticks_msec() + _nov_list.size()],
		"pos": pos, "t_ms": Time.get_ticks_msec()})
	while _nov_list.size() > 8:
		_nov_list.pop_front()


# ---------------------------------------------------------------------------
# Landmark catalogue (shared, throttled)
# ---------------------------------------------------------------------------

static func _world_of(sim: Variant) -> Node:
	if sim == null or not is_instance_valid(sim) or not (sim is Node):
		return null
	var w: Variant = (sim as Node).get("world")
	if is_instance_valid(w) and w is Node:
		return w as Node
	return (sim as Node).get_parent()


static func landmarks(sim: Variant) -> Array:
	if _test_landmarks is Array:
		return _test_landmarks as Array
	var w: Node = _world_of(sim)
	if w == null:
		return []
	var now: int = Time.get_ticks_msec()
	if w.get_instance_id() != _lm_world_id:
		_lm_world_id = w.get_instance_id()
		_lm_next_ms = 0
		_nov_hs_count = -1
		_nov_lily_count = -1
		_nov_list.clear()
		_nov_arm_ms = now + NOVELTY_ARM_DELAY_MS
	if now >= _lm_next_ms:
		_lm_list = _build_landmarks(sim as Node, w)
		_lm_next_ms = now + LANDMARK_REFRESH_MS
	if now >= _nov_next_ms:
		_nov_next_ms = now + NOVELTY_POLL_MS
		_poll_novelty(sim as Node, w, now)
	return _lm_list


static func _node_pos(n: Variant) -> Vector3:
	if n == null or not is_instance_valid(n) or not (n is Node3D):
		return Vector3.INF
	var n3: Node3D = n as Node3D
	return n3.global_position if n3.is_inside_tree() else n3.position


static func _plant_label(p: Object) -> String:
	var cn: Variant = p.get("common_name")
	if cn != null and String(cn) != "":
		return String(cn)
	var pn: Variant = p.get("plant_name")
	if pn != null and String(pn) != "":
		return String(pn)
	return "plants"


static func _build_landmarks(sim: Node, w: Node) -> Array:
	var out: Array = []
	# Plants: up to 3 instances per species label so "the Java Fern" resolves
	# to the nearest one of that kind.
	var per_key: Dictionary = {}
	var plants_v: Variant = sim.get("plants")
	if plants_v is Array:
		for p in plants_v:
			if p == null or not is_instance_valid(p) or not p.has_method("biomass"):
				continue
			if int(p.biomass()) < 6:
				continue
			var label: String = _plant_label(p)
			var sid: Variant = p.get("species_id")
			var key: String = "plant:" + (String(sid) if sid != null and String(sid) != "" else label.to_lower())
			var n: int = int(per_key.get(key, 0))
			if n >= 3:
				continue
			per_key[key] = n + 1
			var wp: Variant = p.get("_world_pos")
			var pos: Vector3 = (wp as Vector3) if wp is Vector3 else _node_pos(p)
			if not pos.is_finite():
				continue
			out.append({"kind": "plant", "label": label, "key": key, "pos": pos + Vector3(0, 0.45, 0)})
	_append_sampled(out, w.get("_driftwood_voxels"), 5, "driftwood", "driftwood", "driftwood", 0.35)
	_append_sampled(out, w.get("_rock_voxels"), 3, "stones", "stones", "stones", 0.35)
	var caves: Variant = w.get("_build_shelter_points")
	if caves is Array:
		var c_n: int = 0
		for cp in caves:
			if cp is Vector3 and c_n < 4:
				out.append({"kind": "cave", "label": "cave", "key": "cave", "pos": cp})
				c_n += 1
	# Keeper-placed hardscape (aquascape tools tag their nodes).
	var hs: Variant = sim.get("hardscape_root")
	if is_instance_valid(hs) and hs is Node and (hs as Node).get_child_count() < 600:
		var placed_n: int = 0
		for c in (hs as Node).get_children():
			if placed_n >= 8:
				break
			if not c.has_meta("aquascape_tool"):
				continue
			var e: Dictionary = _placed_entry(c)
			if not e.is_empty():
				out.append(e)
				placed_n += 1
	var pads: Variant = w.get("_lily_pads")
	if pads is Array:
		var l_n: int = 0
		for lp in pads:
			if l_n >= 4 or lp == null or not is_instance_valid(lp):
				continue
			var lpos: Vector3 = _node_pos(lp)
			if lp.has_method("surface_rest_position"):
				lpos = lp.surface_rest_position()
			if lpos.is_finite():
				out.append({"kind": "lily", "label": "lily pads", "key": "lily", "pos": lpos - Vector3(0, 0.5, 0)})
				l_n += 1
	if w.has_method("light_fixture_head_world"):
		var head: Vector3 = w.light_fixture_head_world()
		if head.is_finite():
			var b: AABB = _bounds(sim)
			var lamp_pos := Vector3(head.x, b.end.y - 0.6, head.z)
			out.append({"kind": "lamp", "label": "lamp", "key": "lamp", "pos": _clamp_in(sim, lamp_pos)})
	var intake: Variant = sim.get("filter_intake_pos")
	if intake is Vector3 and (intake as Vector3) != Vector3.ZERO:
		out.append({"kind": "filter", "label": "filter current", "key": "filter",
			"pos": _clamp_in(sim, (intake as Vector3) + Vector3(0, 0, 0))})
	return out


static func _append_sampled(out: Array, arr_v: Variant, max_n: int, kind: String,
		label: String, key: String, lift: float) -> void:
	if not (arr_v is Array):
		return
	var arr: Array = arr_v
	if arr.is_empty():
		return
	var stride: int = maxi(1, int(float(arr.size()) / float(max_n)))
	var n: int = 0
	var i: int = 0
	while i < arr.size() and n < max_n:
		var pos: Vector3 = _node_pos(arr[i])
		if pos.is_finite():
			out.append({"kind": kind, "label": label, "key": key, "pos": pos + Vector3(0, lift, 0)})
			n += 1
		i += stride


static func _placed_entry(c: Node) -> Dictionary:
	var pos: Vector3 = _node_pos(c)
	if not pos.is_finite():
		return {}
	var tool_s: String = String(c.get_meta("aquascape_tool", ""))
	match tool_s:
		"wood":
			return {"kind": "driftwood", "label": "driftwood", "key": "driftwood", "pos": pos + Vector3(0, 0.4, 0)}
		"stone":
			return {"kind": "stones", "label": "stones", "key": "stones", "pos": pos + Vector3(0, 0.4, 0)}
		"object":
			var oid: String = String(c.get_meta("aquascape_object_id", "ornament"))
			var lbl: String = oid.replace("_", " ").strip_edges()
			return {"kind": "ornament", "label": lbl if lbl != "" else "ornament",
				"key": "ornament:" + oid, "pos": pos + Vector3(0, 0.4, 0)}
	return {}


# "Newly placed object" detection: poll cheap child counts; the tail of the
# hardscape container is what just got added.
static func _poll_novelty(sim: Node, w: Node, now: int) -> void:
	for i in range(_nov_list.size() - 1, -1, -1):
		if now - int(_nov_list[i].get("t_ms", 0)) > NOVELTY_TTL_MS:
			_nov_list.remove_at(i)
	var hs: Variant = sim.get("hardscape_root")
	if is_instance_valid(hs) and hs is Node:
		var hn: Node = hs as Node
		var cnt: int = hn.get_child_count()
		if _nov_hs_count >= 0 and cnt > _nov_hs_count and now >= _nov_arm_ms \
				and cnt - _nov_hs_count <= 12:
			for idx in range(_nov_hs_count, cnt):
				var c: Node = hn.get_child(idx)
				var e: Dictionary = _placed_entry(c) if c.has_meta("aquascape_tool") else {}
				if e.is_empty():
					var p: Vector3 = _node_pos(c)
					if not p.is_finite():
						continue
					e = {"kind": "ornament", "label": "new stone", "key": "ornament", "pos": p + Vector3(0, 0.4, 0)}
				register_novel(e["pos"], "new " + String(e["label"]), String(e["kind"]))
		_nov_hs_count = cnt
	var pads: Variant = w.get("_lily_pads")
	if pads is Array:
		var pn: int = (pads as Array).size()
		if _nov_lily_count >= 0 and pn > _nov_lily_count and now >= _nov_arm_ms and pn - _nov_lily_count <= 4:
			var lp: Variant = (pads as Array)[pn - 1]
			var lpos: Vector3 = _node_pos(lp)
			if lpos.is_finite():
				register_novel(lpos - Vector3(0, 0.5, 0), "new lily pad", "lily")
		_nov_lily_count = pn


static func novel_objects() -> Array:
	return _nov_list


# Candidate like/fear subjects present in this tank (for FishBackstory).
# Unique by key, sorted by key so generation is deterministic.
static func candidates(sim: Variant) -> Array:
	var seen: Dictionary = {}
	for e in landmarks(sim):
		var k: String = String(e.get("key", ""))
		if k == "" or seen.has(k):
			continue
		seen[k] = {"kind": String(e.get("kind", "")), "label": String(e.get("label", "")), "key": k}
	for g in [
			{"kind": "surface", "label": "surface", "key": "surface"},
			{"kind": "substrate", "label": _substrate_label(), "key": "substrate"},
			{"kind": "corner", "label": "quiet corner", "key": "corner"}]:
		if not seen.has(g["key"]):
			seen[g["key"]] = g
	var keys: Array = seen.keys()
	keys.sort()
	var out: Array = []
	for k in keys:
		out.append(seen[k])
	return out


static func _substrate_label() -> String:
	var ml: MainLoop = Engine.get_main_loop()
	if ml is SceneTree and (ml as SceneTree).root != null:
		var cfg: Node = (ml as SceneTree).root.get_node_or_null("/root/TankConfig")
		if cfg != null and cfg.get("substrate_type") != null:
			var st: String = String(cfg.substrate_type)
			if st.contains("sand"):
				return "sand"
			if st.contains("gravel"):
				return "gravel"
	return "substrate"


# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------

static func _bounds(sim: Variant) -> AABB:
	if sim != null and is_instance_valid(sim) and sim is Object:
		var b: Variant = (sim as Object).get("world_bounds")
		if b is AABB:
			return b as AABB
	return DEFAULT_BOUNDS


static func _clamp_in(sim: Variant, p: Vector3) -> Vector3:
	var w: Node = _world_of(sim)
	if w != null and w.has_method("clamp_xyz_in_tank"):
		var c: Variant = w.clamp_xyz_in_tank(p, 0.45)
		if c is Vector3 and (c as Vector3).is_finite():
			return c as Vector3
	var b: AABB = _bounds(sim)
	return Vector3(
		clampf(p.x, b.position.x + 0.5, b.end.x - 0.5),
		clampf(p.y, b.position.y + 0.2, b.end.y - 0.35),
		clampf(p.z, b.position.z + 0.5, b.end.z - 0.5))


static func _pos(f: Object) -> Vector3:
	var p: Variant = f.get("position")
	if p is Vector3:
		return p as Vector3
	return Vector3.ZERO


static func _home_of(f: Object) -> Vector3:
	var pos: Vector3 = _pos(f)
	var hx: Variant = f.get("home_x")
	var hz: Variant = f.get("home_z")
	if hx != null and hz != null and is_finite(float(hx)) and is_finite(float(hz)):
		return Vector3(float(hx), pos.y, float(hz))
	return pos


# World position for a like/fear/landmark subject, relative to this fish.
# Vector3.INF when it cannot be resolved (e.g. that plant died out).
static func resolve_pos(f: Object, subject: Dictionary) -> Vector3:
	if f == null or subject.is_empty():
		return Vector3.INF
	var sim: Variant = f.get("sim")
	var kind: String = String(subject.get("kind", ""))
	var key: String = String(subject.get("key", ""))
	var pos: Vector3 = _pos(f)
	var b: AABB = _bounds(sim)
	match kind:
		"tankmate":
			var mate: Node = _find_mate(f, String(subject.get("id", "")))
			return _node_pos(mate) if mate != null else Vector3.INF
		"surface":
			var home: Vector3 = _home_of(f)
			return _clamp_in(sim, Vector3(home.x, b.end.y - 0.55, home.z))
		"substrate":
			return _clamp_in(sim, Vector3(pos.x, b.position.y + 0.25, pos.z))
		"corner":
			var h: Vector3 = _home_of(f)
			var cx: float = b.position.x + 1.1 if h.x < b.get_center().x else b.end.x - 1.1
			var cz: float = b.position.z + 1.0 if h.z < b.get_center().z else b.end.z - 1.0
			return _clamp_in(sim, Vector3(cx, lerpf(b.position.y, b.end.y, 0.3), cz))
	var anchor: Vector3 = _home_of(f)
	var best: Vector3 = Vector3.INF
	var best_d2: float = INF
	for e in landmarks(sim):
		if String(e.get("key", "")) != key:
			continue
		var p: Variant = e.get("pos")
		if not (p is Vector3):
			continue
		var d2: float = Vector2((p as Vector3).x - anchor.x, (p as Vector3).z - anchor.z).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = p as Vector3
	return best


static func _nearest_of_kinds(f: Object, kinds: Array, exclude_key: String = "") -> Dictionary:
	var pos: Vector3 = _pos(f)
	var best: Dictionary = {}
	var best_d2: float = INF
	for e in landmarks(f.get("sim")):
		if not (String(e.get("kind", "")) in kinds):
			continue
		if exclude_key != "" and String(e.get("key", "")) == exclude_key:
			continue
		var p: Vector3 = e.get("pos", Vector3.INF)
		var d2: float = p.distance_squared_to(pos)
		if d2 < best_d2:
			best_d2 = d2
			best = e
	return best


static func _find_mate(f: Object, mate_id: String) -> Node:
	if mate_id == "":
		return null
	var st: Dictionary = state(f)
	var ref: Variant = st.get("mate_ref", null)
	if ref is WeakRef:
		var n: Variant = (ref as WeakRef).get_ref()
		if n != null and is_instance_valid(n) and n.get("_dying") != true:
			return n as Node
	var sim: Variant = f.get("sim")
	if sim == null or not is_instance_valid(sim):
		return null
	var fish_v: Variant = (sim as Object).get("fish")
	if not (fish_v is Array):
		return null
	for o in fish_v:
		if o != null and is_instance_valid(o) and String(o.get("id")) == mate_id:
			st["mate_ref"] = weakref(o)
			return o as Node
	return null


# ---------------------------------------------------------------------------
# Per-fish state
# ---------------------------------------------------------------------------

static func state(f: Object) -> Dictionary:
	var st_v: Variant = f.get("env_state")
	if st_v is Dictionary:
		var st: Dictionary = st_v
		if not st.is_empty():
			return st
		_init_state(f, st)
		return st
	var tmp: Dictionary = {}
	f.set("env_state", tmp)
	_init_state(f, tmp)
	return tmp


static func _init_state(f: Object, st: Dictionary) -> void:
	var fid: String = String(f.get("id")) if f.get("id") != null else ""
	var rng := RandomNumberGenerator.new()
	rng.seed = SimRngScript.stream_seed(0xE11F1504, "env|" + fid + "|" + str(f.get_instance_id() if fid == "" else 0))
	st["rng"] = rng
	# Stagger: fish spread their scans across the whole window.
	st["t_scan"] = rng.randf_range(0.2, SCAN_MIN_S + SCAN_JITTER_S)
	st["intent"] = INTENT_NONE
	st["target"] = Vector3.INF
	st["label"] = ""
	st["until"] = 0.0
	st["arrived"] = false
	st["fear_pos"] = Vector3.INF
	st["fear_r"] = 0.0
	st["fear_kind"] = ""
	st["fear_logged_t"] = -9999.0
	st["episode_t"] = -9999.0
	st["clock"] = 0.0
	st["seen_novel"] = {}
	st["home0"] = Vector3.INF
	st["last_episode"] = ""


static func _personality(f: Object, key: String) -> float:
	var p: Variant = f.get("personality")
	if p is Dictionary:
		return clampf(float((p as Dictionary).get(key, 0.5)), 0.0, 1.0)
	return 0.5


static func _story(f: Object) -> Dictionary:
	var b: Variant = f.get("backstory")
	return b as Dictionary if b is Dictionary else {}


# ---------------------------------------------------------------------------
# Per-tick steering (called from fish.tick)
# ---------------------------------------------------------------------------

static func steer(f: Object, dt: float, eff_max: float) -> Vector3:
	if f == null or dt <= 0.0:
		return Vector3.ZERO
	var st: Dictionary = state(f)
	st["clock"] = float(st.get("clock", 0.0)) + dt
	st["t_scan"] = float(st.get("t_scan", 0.0)) - dt
	if float(st["t_scan"]) <= 0.0:
		scan(f)
		var rng: RandomNumberGenerator = st["rng"]
		st["t_scan"] = SCAN_MIN_S + rng.randf() * SCAN_JITTER_S
	var maturity: Variant = f.get("maturity")
	if maturity != null and int(maturity) == 0:
		return Vector3.ZERO   # fry run their own plant-shelter tier
	var pos: Vector3 = _pos(f)
	var v := Vector3.ZERO
	v += fear_push(f, pos, eff_max)
	var intent: String = String(st.get("intent", ""))
	if intent == INTENT_NONE:
		return v
	st["until"] = float(st.get("until", 0.0)) - dt
	if float(st["until"]) <= 0.0:
		_end_intent(st)
		return v
	if _busy(f):
		return v
	var target: Vector3 = st.get("target", Vector3.INF)
	if not target.is_finite():
		return v
	var to_t: Vector3 = target - pos
	var d: float = to_t.length()
	var arrive_r: float = 0.7 if intent != INTENT_FOLLOW else 1.2
	if d > arrive_r:
		var w: float = _intent_weight(intent)
		v += to_t / maxf(d, 0.001) * eff_max * w * clampf(d / 1.5, 0.35, 1.0)
		return v
	if not bool(st.get("arrived", false)):
		st["arrived"] = true
		_on_arrive(f, st)
	# Holding at the spot: bleed off speed so it reads as settling in, with
	# a little intent-specific motion.
	var vel: Variant = f.get("velocity")
	if vel is Vector3:
		v -= (vel as Vector3) * (0.55 if intent != INTENT_PLAY else 0.15)
	match intent:
		INTENT_RUB:
			var clock: float = float(st.get("clock", 0.0))
			v += Vector3(sin(clock * 5.0), -0.3, cos(clock * 3.3)) * eff_max * 0.35
		INTENT_PLAY:
			var clock2: float = float(st.get("clock", 0.0))
			v += Vector3(cos(clock2 * 1.7), sin(clock2 * 2.3) * 0.3, sin(clock2 * 1.7)) * eff_max * 0.45
		INTENT_NIBBLE:
			var rng2: RandomNumberGenerator = st["rng"]
			if rng2.randf() < dt * 0.6 and f.has_method("_trigger_mouth_gape"):
				f.call("_trigger_mouth_gape")
	return v


static func _intent_weight(intent: String) -> float:
	match intent:
		INTENT_INVESTIGATE:
			return 0.6
		INTENT_SHELTER:
			return 0.5
		INTENT_FOLLOW:
			return 0.35
		INTENT_PLAY, INTENT_BASK:
			return 0.45
	return 0.4


static func _busy(f: Object) -> bool:
	if float(f.get("stress") if f.get("stress") != null else 0.0) > 0.75:
		return true
	if float(f.get("hunger") if f.get("hunger") != null else 0.0) > 0.75:
		return true
	var mode: Variant = f.get("current_mode")
	if mode != null and int(mode) in [_MODE_FLEE, _MODE_COURT, _MODE_SPAWN]:
		return true
	return false


# Steering away from the backstory fear when inside its radius.
static func fear_push(f: Object, pos: Vector3, eff_max: float) -> Vector3:
	var st: Dictionary = state(f)
	var fp: Vector3 = st.get("fear_pos", Vector3.INF)
	var r: float = float(st.get("fear_r", 0.0))
	if not fp.is_finite() or r <= 0.0:
		return Vector3.ZERO
	var kind: String = String(st.get("fear_kind", ""))
	var away: Vector3
	match kind:
		"surface":
			if pos.y < fp.y - r:
				return Vector3.ZERO
			away = Vector3.DOWN
		"substrate":
			if pos.y > fp.y + r:
				return Vector3.ZERO
			away = Vector3.UP
		_:
			away = pos - fp
			away.y *= 0.4
	var d: float = away.length() if kind != "surface" and kind != "substrate" else absf(pos.y - fp.y)
	if kind != "surface" and kind != "substrate" and d >= r:
		return Vector3.ZERO
	var k: float = clampf(1.0 - d / r, 0.0, 1.0)
	if away.length_squared() < 1e-6:
		away = Vector3.RIGHT
	var clock: float = float(st.get("clock", 0.0))
	if k > 0.15 and clock - float(st.get("fear_logged_t", -9999.0)) > 180.0:
		st["fear_logged_t"] = clock
		var fear: Dictionary = _Backstory.fears(f) if f.get("backstory") != null else {}
		if not fear.is_empty():
			_record(f, st, "scared", "kept well away from %s" % _Backstory.phrase(fear), 0.34, pos, false)
	return away.normalized() * eff_max * (0.35 + k * 0.85)


# ---------------------------------------------------------------------------
# Scan: refresh fear, pick / refresh intent
# ---------------------------------------------------------------------------

static func scan(f: Object) -> void:
	var st: Dictionary = state(f)
	var sim: Variant = f.get("sim")
	landmarks(sim)   # keeps the shared catalogue + novelty poll warm
	var home: Vector3 = _home_of(f)
	if not (st.get("home0", Vector3.INF) as Vector3).is_finite() and home.is_finite():
		st["home0"] = home
	# Fear subject.
	var fear: Dictionary = _Backstory.fears(f)
	if not fear.is_empty():
		st["fear_kind"] = String(fear.get("kind", ""))
		st["fear_pos"] = resolve_pos(f, fear)
		st["fear_r"] = _fear_radius(String(fear.get("kind", "")), f)
	else:
		st["fear_pos"] = Vector3.INF
	var intent: String = String(st.get("intent", ""))
	# Moving targets (tankmates) re-resolve each scan.
	if intent == INTENT_FOLLOW:
		var like: Dictionary = _Backstory.likes(f)
		var tp: Vector3 = resolve_pos(f, like)
		if tp.is_finite():
			st["target"] = tp
		else:
			_end_intent(st)
	# Novelty preempts anything but an investigation already underway.
	var nov: Dictionary = _pick_novel(f, st)
	if not nov.is_empty() and intent != INTENT_INVESTIGATE:
		var cur: float = _personality(f, "curiosity")
		var bold: float = _personality(f, "boldness")
		var rng: RandomNumberGenerator = st["rng"]
		if rng.randf() < 0.35 + cur * 0.55 - (0.25 if bold < 0.3 else 0.0):
			(st["seen_novel"] as Dictionary)[String(nov.get("key", ""))] = true
			_begin(st, INTENT_INVESTIGATE, nov.get("pos"), String(nov.get("label", "new thing")),
				rng.randf_range(8.0, 14.0))
			return
		(st["seen_novel"] as Dictionary)[String(nov.get("key", ""))] = true
	if intent != INTENT_NONE and float(st.get("until", 0.0)) > 0.0:
		return
	choose_intent(f)


static func _fear_radius(kind: String, f: Object) -> float:
	var shy: float = 1.0 - _personality(f, "boldness")
	match kind:
		"surface", "substrate":
			return 0.9 + shy * 0.5
		"lamp":
			return 2.2 + shy * 0.8
		"tankmate":
			return 1.4 + shy * 0.6
		"filter":
			return 1.8 + shy * 0.6
	return 1.5 + shy * 0.7


static func _pick_novel(f: Object, st: Dictionary) -> Dictionary:
	if _nov_list.is_empty():
		return {}
	var pos: Vector3 = _pos(f)
	var seen: Dictionary = st.get("seen_novel", {})
	for i in range(_nov_list.size() - 1, -1, -1):
		var e: Dictionary = _nov_list[i]
		if seen.has(String(e.get("key", ""))):
			continue
		var p: Vector3 = e.get("pos", Vector3.INF)
		if p.is_finite() and p.distance_to(pos) <= NOVELTY_RADIUS:
			return e
	return {}


static func _begin(st: Dictionary, intent: String, target: Variant, label: String, dur: float) -> void:
	st["intent"] = intent
	st["target"] = target if target is Vector3 else Vector3.INF
	st["label"] = label
	st["until"] = dur
	st["arrived"] = false


static func _end_intent(st: Dictionary) -> void:
	st["intent"] = INTENT_NONE
	st["target"] = Vector3.INF
	st["label"] = ""
	st["until"] = 0.0
	st["arrived"] = false


static func _like_intent(kind: String) -> String:
	match kind:
		"lamp":
			return INTENT_BASK
		"filter":
			return INTENT_PLAY
		"substrate":
			return INTENT_RUB
		"tankmate":
			return INTENT_FOLLOW
	return INTENT_REST


static func _is_night(f: Object) -> bool:
	var sim: Variant = f.get("sim")
	if sim != null and is_instance_valid(sim) and (sim as Object).has_method("daylight"):
		return float(sim.daylight()) < 0.2
	return false


# Weighted pick among the intents this tank + this fish make possible.
# Deliberately leaves a large "nothing special" share: environment
# moments punctuate normal schooling/foraging rather than replacing them.
static func choose_intent(f: Object) -> String:
	var st: Dictionary = state(f)
	var rng: RandomNumberGenerator = st["rng"]
	var bold: float = _personality(f, "boldness")
	var calm: float = _personality(f, "calm")
	var cur: float = _personality(f, "curiosity")
	var soc: float = _personality(f, "sociability")
	var stress: float = float(f.get("stress") if f.get("stress") != null else 0.0)
	var hunger: float = float(f.get("hunger") if f.get("hunger") != null else 0.3)
	var herb: float = float(f.get("herbivory") if f.get("herbivory") != null else 0.0)
	if f.get("algae_grazer") == true or f.get("wood_grazer") == true:
		herb = maxf(herb, 0.6)
	var night: bool = _is_night(f)
	var fear: Dictionary = _Backstory.fears(f)
	var fear_key: String = String(fear.get("key", ""))
	var like: Dictionary = _Backstory.likes(f)
	var opts: Array = []   # [intent, weight, target, label]
	opts.append([INTENT_NONE, 2.2 if not night else 0.8, Vector3.INF, ""])
	if not like.is_empty():
		var lp: Vector3 = resolve_pos(f, like)
		if lp.is_finite():
			var li: String = _like_intent(String(like.get("kind", "")))
			var lw: float = 0.9 + calm * 0.5
			if night:
				lw = 2.4 if li == INTENT_REST else 0.3
			if li == INTENT_FOLLOW:
				lw = 0.6 + soc * 0.8
			opts.append([li, lw, lp, _Backstory.phrase(like)])
	var shelter: Dictionary = _nearest_of_kinds(f, ["driftwood", "cave", "stones", "lily"], fear_key)
	if not shelter.is_empty():
		var sw: float = 0.15 + (1.0 - bold) * 0.5 + stress * 1.2
		if night:
			sw += 1.4
		opts.append([INTENT_SHELTER, sw, shelter.get("pos"), "the " + String(shelter.get("label", ""))])
	var plant: Dictionary = _nearest_of_kinds(f, ["plant"], fear_key)
	if not plant.is_empty() and not night:
		opts.append([INTENT_NIBBLE, 0.1 + herb * 0.7 + hunger * 0.35, plant.get("pos"),
			"the " + String(plant.get("label", ""))])
	if fear_key != "filter" and not night:
		var filt: Dictionary = _nearest_of_kinds(f, ["filter"])
		if not filt.is_empty():
			opts.append([INTENT_PLAY, 0.08 + bold * 0.35 + cur * 0.15, filt.get("pos"), "the filter current"])
	if fear_key != "substrate" and not night:
		var sub_pos: Vector3 = resolve_pos(f, {"kind": "substrate", "key": "substrate"})
		opts.append([INTENT_RUB, 0.1 + (0.1 if calm < 0.4 else 0.0), sub_pos, "the " + _substrate_label()])
	var total: float = 0.0
	for o in opts:
		total += float(o[1])
	var roll: float = rng.randf() * total
	var pick: Array = opts[0]
	for o in opts:
		roll -= float(o[1])
		if roll <= 0.0:
			pick = o
			break
	var intent: String = String(pick[0])
	if intent == INTENT_NONE or not (pick[2] is Vector3) or not (pick[2] as Vector3).is_finite():
		_end_intent(st)
		return INTENT_NONE
	var dur: float = rng.randf_range(9.0, 22.0)
	if night and (intent == INTENT_REST or intent == INTENT_SHELTER):
		dur *= 2.0
	_begin(st, intent, pick[2], String(pick[3]), dur)
	return intent


# ---------------------------------------------------------------------------
# Arrival: episodes, home-range drift
# ---------------------------------------------------------------------------

static func _on_arrive(f: Object, st: Dictionary) -> void:
	var intent: String = String(st.get("intent", ""))
	var label: String = String(st.get("label", ""))
	var pos: Vector3 = _pos(f)
	var night: bool = _is_night(f)
	var story: Dictionary = _story(f)
	match intent:
		INTENT_REST:
			var visits: int = int(story.get("fav_visits", 0)) + 1
			if not story.is_empty():
				story["fav_visits"] = visits
			_drift_home(f, st, st.get("target", Vector3.INF))
			var verb: String = "slept by" if night else "rested by"
			var text: String = "%s %s%s" % [verb, label, " again" if visits > 1 else ""]
			_record(f, st, "place", text, 0.42 if visits <= 1 else 0.3, pos, visits == 1)
			if visits == 1:
				_journal(f, "found a favourite spot by %s" % label, ["place", "home"])
		INTENT_SHELTER:
			_drift_home(f, st, st.get("target", Vector3.INF), 0.12)
			_record(f, st, "place", "%s under %s" % ["slept" if night else "sheltered", label], 0.36, pos, false)
		INTENT_NIBBLE:
			_record(f, st, "food", "nibbled at %s leaves" % label, 0.3, pos, false)
		INTENT_RUB:
			_record(f, st, "place", "flashed along %s" % label, 0.26, pos, false)
		INTENT_PLAY:
			_record(f, st, "place", "played in %s" % label, 0.4, pos, false)
		INTENT_BASK:
			_record(f, st, "place", "basked in the light under %s" % label, 0.34, pos, false)
		INTENT_FOLLOW:
			_record(f, st, "place", "swam alongside %s" % label, 0.3, pos, false)
		INTENT_INVESTIGATE:
			var t2: String = "inspected the %s" % label
			_record(f, st, "novelty", t2, 0.5, pos, true)
			_journal(f, t2, ["novelty"])
			var cd: Variant = f.get("curiosity_drive")
			if cd != null:
				f.set("curiosity_drive", maxf(0.0, float(cd) - 0.25))


static func _drift_home(f: Object, st: Dictionary, target: Variant, gain: float = 0.25) -> void:
	if not (target is Vector3) or not (target as Vector3).is_finite():
		return
	var hx: Variant = f.get("home_x")
	var hz: Variant = f.get("home_z")
	if hx == null or hz == null or not is_finite(float(hx)) or not is_finite(float(hz)):
		return
	var t: Vector3 = target
	var nx: float = lerpf(float(hx), t.x, gain)
	var nz: float = lerpf(float(hz), t.z, gain)
	var h0: Vector3 = st.get("home0", Vector3.INF)
	if h0.is_finite():
		var pat: String = String(f.get("swim_pattern")) if f.get("swim_pattern") != null else ""
		var cap: float = HOME_DRIFT_CAP_SCHOOL if pat == "school" or pat == "shoal" else HOME_DRIFT_CAP
		var off := Vector2(nx - h0.x, nz - h0.z)
		if off.length() > cap:
			off = off.normalized() * cap
			nx = h0.x + off.x
			nz = h0.z + off.y
	f.set("home_x", nx)
	f.set("home_z", nz)


static func _record(f: Object, st: Dictionary, kind: String, text: String, salience: float,
		pos: Vector3, force: bool) -> void:
	var clock: float = float(st.get("clock", 0.0))
	if not force and clock - float(st.get("episode_t", -9999.0)) < EPISODE_COOLDOWN_S:
		return
	if text == String(st.get("last_episode", "")) and clock - float(st.get("episode_t", -9999.0)) < 300.0:
		return
	st["episode_t"] = clock
	st["last_episode"] = text
	if not is_instance_valid(f) or not (f is Node):
		return
	EpisodicMemoryScript.encode_episode(f, kind, text, salience, pos)


static func _journal(f: Object, text: String, tags: Array) -> void:
	var sim: Variant = f.get("sim")
	if sim == null or not is_instance_valid(sim) or not (sim as Object).has_method("append_fish_journal_entry"):
		return
	sim.append_fish_journal_entry(f, text, PackedStringArray(tags))


# ---------------------------------------------------------------------------
# Readers for speech / UI
# ---------------------------------------------------------------------------

static func current_intent(f: Object) -> String:
	var st_v: Variant = f.get("env_state")
	if not (st_v is Dictionary):
		return INTENT_NONE
	return String((st_v as Dictionary).get("intent", INTENT_NONE))


# "resting by the Java Fern", "investigating the new stone", or "".
static func current_activity(f: Object) -> String:
	var st_v: Variant = f.get("env_state")
	if not (st_v is Dictionary):
		return ""
	var st: Dictionary = st_v
	var label: String = String(st.get("label", ""))
	match String(st.get("intent", "")):
		INTENT_REST:
			return "resting by %s" % label
		INTENT_SHELTER:
			return "sheltering under %s" % label
		INTENT_NIBBLE:
			return "nibbling %s" % label
		INTENT_RUB:
			return "flashing on %s" % label
		INTENT_PLAY:
			return "playing in %s" % label
		INTENT_BASK:
			return "basking under %s" % label
		INTENT_FOLLOW:
			return "keeping close to %s" % label
		INTENT_INVESTIGATE:
			return "investigating the %s" % label
	return ""


# Most recent environment moment this session ("slept under the driftwood").
static func last_interaction(f: Object) -> String:
	var st_v: Variant = f.get("env_state")
	if not (st_v is Dictionary):
		return ""
	return String((st_v as Dictionary).get("last_episode", ""))
