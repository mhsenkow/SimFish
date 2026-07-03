class_name MindFishProxy
extends RefCounted

# PERFORMANCE_REALTIME #95 — thread-safe fish mind host for worker cognition ticks.

var id: String = ""
var species: String = "glassdart"
var fish_name: String = ""
var is_guardian: bool = false
var generation: int = 0
var age: float = 0.0
var max_age_s: float = 1.0
var maturity: int = 2
var position: Vector3 = Vector3.ZERO

var mood: float = 0.0
var arousal: float = 0.0
var vigilance: float = 0.0
var stress: float = 0.0
var hunger: float = 0.0
var surprise: float = 0.0
var curiosity_drive: float = 0.0
var spooked: float = 0.0
var familiarity: float = 0.0
var mood_disposition: float = 0.0
var dopamine: float = 0.45
var serotonin: float = 0.5
var cortisol: float = 0.2
var noradrenaline: float = 0.25
var attention_focus: String = ""
var current_intention: String = ""
var goal_kind: String = ""
var goal_point: Vector3 = Vector3.ZERO
var speed: float = 0.0
var heading: Vector3 = Vector3(0.0, 0.0, -1.0)
var energy: float = 1.0
var current_mode: int = 0
var brooding_remaining: float = 0.0
var semantic_memory: Array = []
var salient_memories: Array = []
var _salient_ring_head: int = 0
var _salient_top_cache: PackedStringArray = PackedStringArray()

var personality: Dictionary = {}
var bonds: Dictionary = {}
var grudges: Dictionary = {}
var bio: Dictionary = {}
var memory: Array = []
var quirks: Array = []
var inferred_states: Dictionary = {}
var _hypotheses: Dictionary = {}

var partner: Fish = null
var has_mate: bool = false

var _asleep: bool = false
var _dreaming: bool = false
var _sleep_depth: float = 0.0
var _dream_wisp: String = ""
var _startle_remaining: float = 0.0
var _cached_glance_strength: float = 0.0
var _behavior_ws_bias: Vector3 = Vector3.ZERO
var _last_winning_affordance: String = ""
var _cached_glance_point: Vector3 = Vector3.ZERO
var _prediction_error: float = 0.0
var _world_model: Dictionary = {}
var _episodic_retrieval_hint: Dictionary = {}
var _bid_salience_mods: Dictionary = {}
var _bid_slow_cache: Array = []
var _bid_slow_accum: float = 0.0
var _bid_dirty: int = 0
var _bid_slow_due: bool = true
var _bid_last_daylight: float = 1.0
var _bid_pool: Array = []
var _bid_pool_i: int = 0
var _meta_ring: Array = []
var _meta_ring_head: int = 0
var _keeper_pending: Dictionary = {}
var _mind_workspace: Array = []
var _mind_self_model: Dictionary = {}
var _workspace_ignited: bool = false
@warning_ignore("unused_private_class_variable")
var _ws_bids_digest: int = -1
var _ws_broadcast_digest: int = -2
var _ws_competition_cache: Dictionary = {}
var _cycle_bias_cache: Dictionary = {}
@warning_ignore("unused_private_class_variable")
var _salient_prune_t: float = 0.0
@warning_ignore("unused_private_class_variable")
var _lod_tier_hold_s: float = 0.0
var _self_model_cache: Dictionary = {}
var _self_model_key: String = ""
var _current_thought: String = ""
var _thought_stream: String = ""
var _thought_stream_age: float = 0.0
var _episodic_store: Array = []
var _felt_self: Dictionary = {}
var _life_stance: String = ""
var _self_summary: String = ""
var _active_plan: Dictionary = {}
var _writeback_cd: float = 0.0
var _mind_writeback_log: Array = []
var _td_eligibility_peak: float = 0.0
var _semantic_schemas: Array = []
var _heard_signals: Array = []
var _signal_state: Dictionary = {}
var _prospective: Dictionary = {}
var _keeper_model: Dictionary = {}
var _homeostasis: Dictionary = {}
var _homeostatic_feed_point: Vector3 = Vector3.ZERO
var _contentment: float = 0.0
var _rest_debt: float = 0.0
var _last_ws_encode_label: String = ""
var _delib_approach_s: float = 0.0
var _delib_avoid_s: float = 0.0
var _longing_residue: float = 0.0
var _soul_mind: Dictionary = {}
var _cycle_lod_tier: int = 2
var _mind_lod_tier: int = 2


func _trait(key: String) -> float:
	return float(personality.get(key, 0.5)) if not personality.is_empty() else 0.5


func _world_node() -> Node:
	return null


func try_mark_workspace_encode(label: String) -> bool:
	if label.strip_edges() == "" or label == _last_ws_encode_label:
		return false
	_last_ws_encode_label = label
	return true


static func capture(f: Fish) -> Dictionary:
	var p := MindFishProxy.new()
	if f == null:
		return p.to_dict()
	p.id = str(f.id)
	p.species = str(f.species)
	p.fish_name = str(f.fish_name)
	p.is_guardian = f.is_guardian
	p.generation = f.generation
	p.age = f.age
	p.max_age_s = f.max_age_s
	p.maturity = f.maturity
	p.position = f.position
	p.mood = f.mood
	p.arousal = f.arousal
	p.vigilance = f.vigilance
	p.stress = f.stress
	p.hunger = f.hunger
	p.surprise = f.surprise
	p.curiosity_drive = f.curiosity_drive
	p.spooked = f.spooked
	p.familiarity = f.familiarity
	p.mood_disposition = f.mood_disposition
	p.dopamine = f.dopamine
	p.serotonin = f.serotonin
	p.cortisol = f.cortisol
	p.noradrenaline = f.noradrenaline
	p.attention_focus = f.attention_focus
	p.current_intention = f.current_intention
	p.goal_kind = f.goal_kind
	p.goal_point = f.goal_point
	p.speed = f.speed
	p.heading = f.heading
	p.energy = f.energy
	p.current_mode = int(f.current_mode)
	p.brooding_remaining = f.brooding_remaining
	if f.semantic_memory is Array:
		p.semantic_memory = (f.semantic_memory as Array).duplicate(true)
	p.salient_memories = _fish_array(f, "salient_memories")
	p._salient_ring_head = int(_fish_float(f, "_salient_ring_head"))
	var stc: Variant = f.get("_salient_top_cache")
	if stc is PackedStringArray:
		p._salient_top_cache = (stc as PackedStringArray).duplicate()
	elif stc is Array:
		p._salient_top_cache = PackedStringArray(stc as Array)
	if f.personality is Dictionary:
		p.personality = (f.personality as Dictionary).duplicate(true)
	if f.bonds is Dictionary:
		p.bonds = (f.bonds as Dictionary).duplicate(true)
	if f.grudges is Dictionary:
		p.grudges = (f.grudges as Dictionary).duplicate(true)
	if f.bio is Dictionary:
		p.bio = (f.bio as Dictionary).duplicate(true)
	if f.memory is Array:
		p.memory = (f.memory as Array).duplicate(true)
	if f.quirks is Array:
		p.quirks = (f.quirks as Array).duplicate(true)
	if f.inferred_states is Dictionary:
		p.inferred_states = (f.inferred_states as Dictionary).duplicate(true)
	var hyp: Variant = f.get("_hypotheses")
	if hyp is Dictionary:
		p._hypotheses = (hyp as Dictionary).duplicate(true)
	p.has_mate = f.partner != null and is_instance_valid(f.partner)
	p._asleep = _fish_bool(f, "_asleep")
	p._dreaming = _fish_bool(f, "_dreaming")
	p._sleep_depth = _fish_float(f, "_sleep_depth")
	p._dream_wisp = _fish_str(f, "_dream_wisp")
	p._startle_remaining = _fish_float(f, "_startle_remaining")
	p._cached_glance_strength = _fish_float(f, "_cached_glance_strength")
	var glance_pt: Variant = f.get("_cached_glance_point")
	if glance_pt is Vector3:
		p._cached_glance_point = glance_pt as Vector3
	var ws_bias: Variant = f.get("_behavior_ws_bias")
	if ws_bias is Vector3:
		p._behavior_ws_bias = ws_bias as Vector3
	p._last_winning_affordance = _fish_str(f, "_last_winning_affordance")
	p._prediction_error = _fish_float(f, "_prediction_error")
	p._world_model = _fish_dict(f, "_world_model")
	p._episodic_retrieval_hint = _fish_dict(f, "_episodic_retrieval_hint")
	p._bid_salience_mods = _fish_dict(f, "_bid_salience_mods")
	p._bid_slow_cache = _fish_array(f, "_bid_slow_cache")
	p._bid_slow_accum = _fish_float(f, "_bid_slow_accum")
	p._bid_dirty = int(_fish_float(f, "_bid_dirty"))
	p._bid_slow_due = _fish_bool(f, "_bid_slow_due", true)
	p._bid_last_daylight = _fish_float(f, "_bid_last_daylight", 1.0)
	p._bid_pool = _fish_array(f, "_bid_pool")
	p._bid_pool_i = int(_fish_float(f, "_bid_pool_i"))
	p._meta_ring = _fish_array(f, "_meta_ring")
	p._meta_ring_head = int(_fish_float(f, "_meta_ring_head"))
	p._keeper_pending = _fish_dict(f, "_keeper_pending")
	p._mind_workspace = _fish_array(f, "_mind_workspace")
	p._mind_self_model = _fish_dict(f, "_mind_self_model")
	p._workspace_ignited = _fish_bool(f, "_workspace_ignited")
	p._ws_bids_digest = int(_fish_float(f, "_ws_bids_digest", -1.0))
	p._ws_broadcast_digest = int(_fish_float(f, "_ws_broadcast_digest", -2.0))
	p._ws_competition_cache = _fish_dict(f, "_ws_competition_cache")
	p._cycle_bias_cache = _fish_dict(f, "_cycle_bias_cache")
	p._self_model_cache = _fish_dict(f, "_self_model_cache")
	p._self_model_key = _fish_str(f, "_self_model_key")
	p._current_thought = _fish_str(f, "_current_thought")
	p._thought_stream = _fish_str(f, "_thought_stream")
	p._thought_stream_age = _fish_float(f, "_thought_stream_age")
	p._episodic_store = _fish_array(f, "_episodic_store")
	p._felt_self = _fish_dict(f, "_felt_self")
	p._life_stance = _fish_str(f, "_life_stance")
	p._self_summary = _fish_str(f, "_self_summary")
	p._active_plan = _fish_dict(f, "_active_plan")
	p._writeback_cd = _fish_float(f, "_writeback_cd")
	p._mind_writeback_log = _fish_array(f, "_mind_writeback_log")
	p._td_eligibility_peak = _fish_float(f, "_td_eligibility_peak")
	p._semantic_schemas = _fish_array(f, "_semantic_schemas")
	p._heard_signals = _capture_heard_signals(f)
	p._signal_state = _fish_dict(f, "_signal_state")
	p._prospective = _fish_dict(f, "_prospective")
	p._keeper_model = _fish_dict(f, "_keeper_model")
	p._homeostasis = _fish_dict(f, "_homeostasis")
	var feed_pt: Variant = f.get("_homeostatic_feed_point")
	if feed_pt is Vector3:
		p._homeostatic_feed_point = feed_pt as Vector3
	p._contentment = _fish_float(f, "_contentment")
	p._rest_debt = _fish_float(f, "_rest_debt")
	p._last_ws_encode_label = _fish_str(f, "_last_ws_encode_label")
	p._delib_approach_s = _fish_float(f, "_delib_approach_s")
	p._delib_avoid_s = _fish_float(f, "_delib_avoid_s")
	p._longing_residue = _fish_float(f, "_longing_residue")
	p._soul_mind = _fish_dict(f, "_soul_mind")
	p._cycle_lod_tier = int(_fish_float(f, "_mind_lod_tier", 2.0))
	p._mind_lod_tier = p._cycle_lod_tier
	return p.to_dict()


static func _fish_dict(f: Fish, key: String) -> Dictionary:
	var v: Variant = f.get(key)
	if v is Dictionary:
		return (v as Dictionary).duplicate(true)
	return {}


static func _fish_array(f: Fish, key: String) -> Array:
	var v: Variant = f.get(key)
	if v is Array:
		return (v as Array).duplicate(true)
	return []


static func _fish_float(f: Fish, key: String, default: float = 0.0) -> float:
	var v: Variant = f.get(key)
	return float(v) if v != null else default


static func _fish_str(f: Fish, key: String, default: String = "") -> String:
	var v: Variant = f.get(key)
	return str(v) if v != null else default


static func _fish_bool(f: Fish, key: String, default: bool = false) -> bool:
	var v: Variant = f.get(key)
	return bool(v) if v != null else default


static func _capture_heard_signals(f: Fish) -> Array:
	var hs: Variant = f.get("_heard_signals")
	if hs is Array and not (hs as Array).is_empty():
		return (hs as Array).duplicate(true)
	var out: Array = []
	var st: Variant = f.get("_signal_state")
	if st is Dictionary:
		var heard: String = str((st as Dictionary).get("heard", ""))
		if heard != "":
			out.append({
				"kind": heard,
				"str": float((st as Dictionary).get("heard_str", 0.0)),
			})
	return out


static func from_dict(d: Dictionary) -> MindFishProxy:
	var p := MindFishProxy.new()
	p.id = str(d.get("id", ""))
	p.species = str(d.get("species", "glassdart"))
	p.fish_name = str(d.get("fish_name", ""))
	p.is_guardian = bool(d.get("is_guardian", false))
	p.generation = int(d.get("generation", 0))
	p.age = float(d.get("age", 0.0))
	p.max_age_s = float(d.get("max_age_s", 1.0))
	p.maturity = int(d.get("maturity", 2))
	var pos: Variant = d.get("position", null)
	if pos is Vector3:
		p.position = pos as Vector3
	elif pos is Array and (pos as Array).size() >= 3:
		var pa: Array = pos as Array
		p.position = Vector3(float(pa[0]), float(pa[1]), float(pa[2]))
	p.mood = float(d.get("mood", 0.0))
	p.arousal = float(d.get("arousal", 0.0))
	p.vigilance = float(d.get("vigilance", 0.0))
	p.stress = float(d.get("stress", 0.0))
	p.hunger = float(d.get("hunger", 0.0))
	p.surprise = float(d.get("surprise", 0.0))
	p.curiosity_drive = float(d.get("curiosity_drive", 0.0))
	p.spooked = float(d.get("spooked", 0.0))
	p.familiarity = float(d.get("familiarity", 0.0))
	p.mood_disposition = float(d.get("mood_disposition", 0.0))
	p.dopamine = float(d.get("dopamine", 0.45))
	p.serotonin = float(d.get("serotonin", 0.5))
	p.cortisol = float(d.get("cortisol", 0.2))
	p.noradrenaline = float(d.get("noradrenaline", 0.25))
	p.attention_focus = str(d.get("attention_focus", ""))
	p.current_intention = str(d.get("current_intention", ""))
	p.goal_kind = str(d.get("goal_kind", ""))
	var gp: Variant = d.get("goal_point", null)
	if gp is Vector3:
		p.goal_point = gp as Vector3
	elif gp is Array and (gp as Array).size() >= 3:
		var gpa: Array = gp as Array
		p.goal_point = Vector3(float(gpa[0]), float(gpa[1]), float(gpa[2]))
	p.speed = float(d.get("speed", 0.0))
	var hd: Variant = d.get("heading", null)
	if hd is Vector3:
		p.heading = hd as Vector3
	elif hd is Array and (hd as Array).size() >= 3:
		var hda: Array = hd as Array
		p.heading = Vector3(float(hda[0]), float(hda[1]), float(hda[2]))
	p.energy = float(d.get("energy", 1.0))
	p.current_mode = int(d.get("current_mode", 0))
	p.brooding_remaining = float(d.get("brooding_remaining", 0.0))
	_copy_array_field(d, "semantic_memory", p, "semantic_memory")
	_copy_array_field(d, "salient_memories", p, "salient_memories")
	p._salient_ring_head = int(d.get("_salient_ring_head", 0))
	var stc: Variant = d.get("_salient_top_cache", null)
	if stc is PackedStringArray:
		p._salient_top_cache = (stc as PackedStringArray).duplicate()
	elif stc is Array:
		p._salient_top_cache = PackedStringArray(stc as Array)
	_copy_dict_field(d, "personality", p, "personality")
	_copy_dict_field(d, "bonds", p, "bonds")
	_copy_dict_field(d, "grudges", p, "grudges")
	_copy_dict_field(d, "bio", p, "bio")
	_copy_array_field(d, "memory", p, "memory")
	_copy_array_field(d, "quirks", p, "quirks")
	_copy_dict_field(d, "inferred_states", p, "inferred_states")
	_copy_dict_field(d, "_hypotheses", p, "_hypotheses")
	p.has_mate = bool(d.get("has_mate", false))
	p._asleep = bool(d.get("_asleep", false))
	p._dreaming = bool(d.get("_dreaming", false))
	p._sleep_depth = float(d.get("_sleep_depth", 0.0))
	p._dream_wisp = str(d.get("_dream_wisp", ""))
	p._startle_remaining = float(d.get("_startle_remaining", 0.0))
	p._cached_glance_strength = float(d.get("_cached_glance_strength", 0.0))
	var cgp: Variant = d.get("_cached_glance_point", null)
	if cgp is Vector3:
		p._cached_glance_point = cgp as Vector3
	elif cgp is Array and (cgp as Array).size() >= 3:
		var cga: Array = cgp as Array
		p._cached_glance_point = Vector3(float(cga[0]), float(cga[1]), float(cga[2]))
	var bwb: Variant = d.get("_behavior_ws_bias", null)
	if bwb is Vector3:
		p._behavior_ws_bias = bwb as Vector3
	elif bwb is Array and (bwb as Array).size() >= 3:
		var bwa: Array = bwb as Array
		p._behavior_ws_bias = Vector3(float(bwa[0]), float(bwa[1]), float(bwa[2]))
	p._last_winning_affordance = str(d.get("_last_winning_affordance", ""))
	p._prediction_error = float(d.get("_prediction_error", 0.0))
	_copy_dict_field(d, "_world_model", p, "_world_model")
	_copy_dict_field(d, "_episodic_retrieval_hint", p, "_episodic_retrieval_hint")
	_copy_dict_field(d, "_bid_salience_mods", p, "_bid_salience_mods")
	_copy_array_field(d, "_bid_slow_cache", p, "_bid_slow_cache")
	p._bid_slow_accum = float(d.get("_bid_slow_accum", 0.0))
	p._bid_dirty = int(d.get("_bid_dirty", 0))
	p._bid_slow_due = bool(d.get("_bid_slow_due", true))
	p._bid_last_daylight = float(d.get("_bid_last_daylight", 1.0))
	_copy_array_field(d, "_bid_pool", p, "_bid_pool")
	p._bid_pool_i = int(d.get("_bid_pool_i", 0))
	_copy_array_field(d, "_meta_ring", p, "_meta_ring")
	p._meta_ring_head = int(d.get("_meta_ring_head", 0))
	_copy_dict_field(d, "_keeper_pending", p, "_keeper_pending")
	_copy_array_field(d, "_mind_workspace", p, "_mind_workspace")
	_copy_dict_field(d, "_mind_self_model", p, "_mind_self_model")
	p._workspace_ignited = bool(d.get("_workspace_ignited", false))
	p._ws_bids_digest = int(d.get("_ws_bids_digest", -1))
	p._ws_broadcast_digest = int(d.get("_ws_broadcast_digest", -2))
	_copy_dict_field(d, "_ws_competition_cache", p, "_ws_competition_cache")
	_copy_dict_field(d, "_cycle_bias_cache", p, "_cycle_bias_cache")
	_copy_dict_field(d, "_self_model_cache", p, "_self_model_cache")
	p._self_model_key = str(d.get("_self_model_key", ""))
	p._current_thought = str(d.get("_current_thought", ""))
	p._thought_stream = str(d.get("_thought_stream", ""))
	p._thought_stream_age = float(d.get("_thought_stream_age", 0.0))
	_copy_array_field(d, "_episodic_store", p, "_episodic_store")
	_copy_dict_field(d, "_felt_self", p, "_felt_self")
	p._life_stance = str(d.get("_life_stance", ""))
	p._self_summary = str(d.get("_self_summary", ""))
	_copy_dict_field(d, "_active_plan", p, "_active_plan")
	p._writeback_cd = float(d.get("_writeback_cd", 0.0))
	_copy_array_field(d, "_mind_writeback_log", p, "_mind_writeback_log")
	p._td_eligibility_peak = float(d.get("_td_eligibility_peak", 0.0))
	_copy_array_field(d, "_semantic_schemas", p, "_semantic_schemas")
	_copy_array_field(d, "_heard_signals", p, "_heard_signals")
	_copy_dict_field(d, "_signal_state", p, "_signal_state")
	_copy_dict_field(d, "_prospective", p, "_prospective")
	_copy_dict_field(d, "_keeper_model", p, "_keeper_model")
	_copy_dict_field(d, "_homeostasis", p, "_homeostasis")
	var hfp: Variant = d.get("_homeostatic_feed_point", null)
	if hfp is Vector3:
		p._homeostatic_feed_point = hfp as Vector3
	elif hfp is Array and (hfp as Array).size() >= 3:
		var hfpa: Array = hfp as Array
		p._homeostatic_feed_point = Vector3(float(hfpa[0]), float(hfpa[1]), float(hfpa[2]))
	p._contentment = float(d.get("_contentment", 0.0))
	p._rest_debt = float(d.get("_rest_debt", 0.0))
	p._last_ws_encode_label = str(d.get("_last_ws_encode_label", ""))
	p._delib_approach_s = float(d.get("_delib_approach_s", 0.0))
	p._delib_avoid_s = float(d.get("_delib_avoid_s", 0.0))
	p._longing_residue = float(d.get("_longing_residue", 0.0))
	_copy_dict_field(d, "_soul_mind", p, "_soul_mind")
	p._cycle_lod_tier = int(d.get("_cycle_lod_tier", 2))
	p._mind_lod_tier = int(d.get("_mind_lod_tier", p._cycle_lod_tier))
	return p


static func _copy_dict_field(src: Dictionary, key: String, dst: Object, prop: String) -> void:
	var v: Variant = src.get(key, null)
	if v is Dictionary:
		dst.set(prop, (v as Dictionary).duplicate(true))


static func _copy_array_field(src: Dictionary, key: String, dst: Object, prop: String) -> void:
	var v: Variant = src.get(key, null)
	if v is Array:
		dst.set(prop, (v as Array).duplicate(true))


func to_dict() -> Dictionary:
	return {
		"id": id,
		"species": species,
		"fish_name": fish_name,
		"is_guardian": is_guardian,
		"generation": generation,
		"age": age,
		"max_age_s": max_age_s,
		"maturity": maturity,
		"position": [position.x, position.y, position.z],
		"mood": mood,
		"arousal": arousal,
		"vigilance": vigilance,
		"stress": stress,
		"hunger": hunger,
		"surprise": surprise,
		"curiosity_drive": curiosity_drive,
		"spooked": spooked,
		"familiarity": familiarity,
		"mood_disposition": mood_disposition,
		"dopamine": dopamine,
		"serotonin": serotonin,
		"cortisol": cortisol,
		"noradrenaline": noradrenaline,
		"attention_focus": attention_focus,
		"current_intention": current_intention,
		"goal_kind": goal_kind,
		"goal_point": [goal_point.x, goal_point.y, goal_point.z],
		"speed": speed,
		"heading": [heading.x, heading.y, heading.z],
		"energy": energy,
		"current_mode": current_mode,
		"brooding_remaining": brooding_remaining,
		"semantic_memory": semantic_memory.duplicate(true),
		"salient_memories": salient_memories.duplicate(true),
		"_salient_ring_head": _salient_ring_head,
		"_salient_top_cache": _salient_top_cache.duplicate(),
		"personality": personality.duplicate(true),
		"bonds": bonds.duplicate(true),
		"grudges": grudges.duplicate(true),
		"bio": bio.duplicate(true),
		"memory": memory.duplicate(true),
		"quirks": quirks.duplicate(true),
		"inferred_states": inferred_states.duplicate(true),
		"_hypotheses": _hypotheses.duplicate(true),
		"has_mate": has_mate,
		"_asleep": _asleep,
		"_dreaming": _dreaming,
		"_sleep_depth": _sleep_depth,
		"_dream_wisp": _dream_wisp,
		"_startle_remaining": _startle_remaining,
		"_cached_glance_strength": _cached_glance_strength,
		"_cached_glance_point": [_cached_glance_point.x, _cached_glance_point.y, _cached_glance_point.z],
		"_behavior_ws_bias": [_behavior_ws_bias.x, _behavior_ws_bias.y, _behavior_ws_bias.z],
		"_last_winning_affordance": _last_winning_affordance,
		"_prediction_error": _prediction_error,
		"_world_model": _world_model.duplicate(true),
		"_episodic_retrieval_hint": _episodic_retrieval_hint.duplicate(true),
		"_bid_salience_mods": _bid_salience_mods.duplicate(true),
		"_bid_slow_cache": _bid_slow_cache.duplicate(true),
		"_bid_slow_accum": _bid_slow_accum,
		"_bid_dirty": _bid_dirty,
		"_bid_slow_due": _bid_slow_due,
		"_bid_last_daylight": _bid_last_daylight,
		"_bid_pool": _bid_pool.duplicate(true),
		"_bid_pool_i": _bid_pool_i,
		"_meta_ring": _meta_ring.duplicate(true),
		"_meta_ring_head": _meta_ring_head,
		"_keeper_pending": _keeper_pending.duplicate(true),
		"_mind_workspace": _mind_workspace.duplicate(true),
		"_mind_self_model": _mind_self_model.duplicate(true),
		"_workspace_ignited": _workspace_ignited,
		"_ws_bids_digest": _ws_bids_digest,
		"_ws_broadcast_digest": _ws_broadcast_digest,
		"_ws_competition_cache": _ws_competition_cache.duplicate(true),
		"_cycle_bias_cache": _cycle_bias_cache.duplicate(true),
		"_self_model_cache": _self_model_cache.duplicate(true),
		"_self_model_key": _self_model_key,
		"_current_thought": _current_thought,
		"_thought_stream": _thought_stream,
		"_thought_stream_age": _thought_stream_age,
		"_episodic_store": _episodic_store.duplicate(true),
		"_felt_self": _felt_self.duplicate(true),
		"_life_stance": _life_stance,
		"_self_summary": _self_summary,
		"_active_plan": _active_plan.duplicate(true),
		"_writeback_cd": _writeback_cd,
		"_mind_writeback_log": _mind_writeback_log.duplicate(true),
		"_td_eligibility_peak": _td_eligibility_peak,
		"_semantic_schemas": _semantic_schemas.duplicate(true),
		"_heard_signals": _heard_signals.duplicate(true),
		"_signal_state": _signal_state.duplicate(true),
		"_prospective": _prospective.duplicate(true),
		"_keeper_model": _keeper_model.duplicate(true),
		"_homeostasis": _homeostasis.duplicate(true),
		"_homeostatic_feed_point": [_homeostatic_feed_point.x, _homeostatic_feed_point.y, _homeostatic_feed_point.z],
		"_contentment": _contentment,
		"_rest_debt": _rest_debt,
		"_last_ws_encode_label": _last_ws_encode_label,
		"_delib_approach_s": _delib_approach_s,
		"_delib_avoid_s": _delib_avoid_s,
		"_longing_residue": _longing_residue,
		"_soul_mind": _soul_mind.duplicate(true),
		"_cycle_lod_tier": _cycle_lod_tier,
		"_mind_lod_tier": _mind_lod_tier,
	}


func apply_mind_to(f: Fish) -> void:
	if f == null:
		return
	f.attention_focus = attention_focus
	f.current_intention = current_intention
	f._current_thought = _current_thought
	f._mind_workspace = _mind_workspace.duplicate(true)
	f._mind_self_model = _mind_self_model.duplicate(true)
	f._workspace_ignited = _workspace_ignited
	f._ws_bids_digest = _ws_bids_digest
	f._ws_broadcast_digest = _ws_broadcast_digest
	f._ws_competition_cache = _ws_competition_cache.duplicate(true)
	f._cycle_bias_cache = _cycle_bias_cache.duplicate(true)
	f._self_model_cache = _self_model_cache.duplicate(true)
	f._self_model_key = _self_model_key
	f._thought_stream = _thought_stream
	f._thought_stream_age = _thought_stream_age
	f._prediction_error = _prediction_error
	f._life_stance = _life_stance
	f._self_summary = _self_summary
	f._active_plan = _active_plan.duplicate(true)
	f._world_model = _world_model.duplicate(true)
	f._keeper_pending = _keeper_pending.duplicate(true)
	f._episodic_retrieval_hint = _episodic_retrieval_hint.duplicate(true)
	f._bid_salience_mods = _bid_salience_mods.duplicate(true)
	f._bid_slow_cache = _bid_slow_cache.duplicate(true)
	f._bid_slow_accum = _bid_slow_accum
	f._bid_dirty = _bid_dirty
	f._bid_slow_due = _bid_slow_due
	f._bid_last_daylight = _bid_last_daylight
	f._bid_pool = _bid_pool.duplicate(true)
	f._bid_pool_i = _bid_pool_i
	f._meta_ring = _meta_ring.duplicate(true)
	f._meta_ring_head = _meta_ring_head
	f._writeback_cd = _writeback_cd
	f._mind_writeback_log = _mind_writeback_log.duplicate(true)
	f._felt_self = _felt_self.duplicate(true)
	f._td_eligibility_peak = _td_eligibility_peak
	f._episodic_store = _episodic_store.duplicate(true)
	f.surprise = surprise
	f.curiosity_drive = curiosity_drive
	f._cached_glance_point = _cached_glance_point
	f._behavior_ws_bias = _behavior_ws_bias
	f._last_winning_affordance = _last_winning_affordance
	f._homeostasis = _homeostasis.duplicate(true)
	f._homeostatic_feed_point = _homeostatic_feed_point
	f._contentment = _contentment
	f._rest_debt = _rest_debt
	f._last_ws_encode_label = _last_ws_encode_label
	f._delib_approach_s = _delib_approach_s
	f._delib_avoid_s = _delib_avoid_s
	f._longing_residue = _longing_residue
	f._signal_state = _signal_state.duplicate(true)
	f._prospective = _prospective.duplicate(true)
	f._keeper_model = _keeper_model.duplicate(true)
	f._soul_mind = _soul_mind.duplicate(true)
	f.salient_memories = salient_memories.duplicate(true)
	f._salient_ring_head = _salient_ring_head
	f._salient_top_cache = _salient_top_cache.duplicate()


func is_voiced_individual() -> bool:
	return fish_name != "" or is_guardian or familiarity > 0.45


func workspace_thought_for(label: String) -> String:
	if label.strip_edges() == "":
		return ""
	return "mind on %s" % label.replace("_", " ")
