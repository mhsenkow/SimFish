class_name MindState
extends RefCounted

# CONSCIOUSNESS_ENGINEERING §A — unified MindState: the fish's mind as one object.
# fish.gd still owns scalar fields for save compat; MindState syncs each tick.

const SCHEMA_VERSION: int = 3

var schema_version: int = SCHEMA_VERSION
var full_fidelity: bool = true

# Affect & drives
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

# Neuromodulators
var dopamine: float = 0.45
var serotonin: float = 0.5
var cortisol: float = 0.2
var noradrenaline: float = 0.25

# Cognitive labels
var attention_focus: String = ""
var current_intention: String = ""
var current_thought: String = ""
var goal_kind: String = ""

# Workspace + self (§B, §G)
var workspace: Array = []  # [{label, salience, coalition}]
var workspace_ignited: bool = false
var self_model: Dictionary = {}
var meta_states: PackedStringArray = PackedStringArray()

# Stream of consciousness (§C)
var thought_stream: String = ""
var thought_age_s: float = 0.0
var system2_pending: bool = false

# Eligibility trace for TD (#28)
var eligibility_peak: float = 0.0

# Write-back audit (#H)
var writeback_log: Array = []

# Extended channel fields (§14 — mind modules read via MindState, not f.get)
var prediction_error: float = 0.0
var life_stance: String = ""
var self_summary: String = ""
var active_plan: Dictionary = {}
var world_model: Dictionary = {}
var keeper_pending: Dictionary = {}
var episodic_retrieval_hint: Dictionary = {}
var bid_salience_mods: Dictionary = {}
var writeback_cd: float = 0.0
var felt_self: Dictionary = {}
var sleep_depth: float = 0.0
var dream_wisp: String = ""


static func for_fish(f: Fish, rich: bool):
	var ms = load("res://scripts/mind_state.gd").new()
	ms.full_fidelity = rich
	ms.sync_from_fish(f)
	return ms


func sync_from_fish(f: Fish) -> void:
	if f == null:
		return
	mood = f.mood
	arousal = f.arousal
	vigilance = f.vigilance
	stress = f.stress
	hunger = f.hunger
	surprise = f.surprise
	curiosity_drive = f.curiosity_drive
	spooked = f.spooked
	familiarity = f.familiarity
	mood_disposition = f.mood_disposition
	dopamine = f.dopamine
	serotonin = f.serotonin
	cortisol = f.cortisol
	noradrenaline = f.noradrenaline
	attention_focus = f.attention_focus
	current_intention = f.current_intention
	current_thought = f._current_thought
	goal_kind = f.goal_kind
	workspace_ignited = f._workspace_ignited
	if f._mind_workspace is Array:
		workspace = (f._mind_workspace as Array).duplicate(true)
	if f._mind_self_model is Dictionary:
		self_model = (f._mind_self_model as Dictionary).duplicate(true)
	thought_stream = f._thought_stream
	thought_age_s = float(f._thought_stream_age if f._thought_stream_age != null else 0.0)
	eligibility_peak = float(f._td_eligibility_peak if f._td_eligibility_peak != null else 0.0)
	if f._mind_writeback_log is Array:
		writeback_log = (f._mind_writeback_log as Array).duplicate(true)
	prediction_error = float(f._prediction_error if f._prediction_error != null else 0.0)
	life_stance = str(f._life_stance if f._life_stance != null else "")
	self_summary = str(f._self_summary if f._self_summary != null else "")
	if f._active_plan is Dictionary:
		active_plan = (f._active_plan as Dictionary).duplicate(true)
	if f._world_model is Dictionary:
		world_model = (f._world_model as Dictionary).duplicate(true)
	if f._keeper_pending is Dictionary:
		keeper_pending = (f._keeper_pending as Dictionary).duplicate(true)
	if f._episodic_retrieval_hint is Dictionary:
		episodic_retrieval_hint = (f._episodic_retrieval_hint as Dictionary).duplicate(true)
	if f._bid_salience_mods is Dictionary:
		bid_salience_mods = (f._bid_salience_mods as Dictionary).duplicate(true)
	writeback_cd = float(f._writeback_cd if f._writeback_cd != null else 0.0)
	if f._felt_self is Dictionary:
		felt_self = (f._felt_self as Dictionary).duplicate(true)
	sleep_depth = float(f._sleep_depth if f._sleep_depth != null else 0.0)
	dream_wisp = str(f._dream_wisp if f._dream_wisp != null else "")


func apply_to_fish(f: Fish) -> void:
	if f == null:
		return
	f.mood = mood
	f.arousal = arousal
	f.vigilance = vigilance
	f.stress = stress
	f.surprise = surprise
	f.curiosity_drive = curiosity_drive
	f.spooked = spooked
	f.attention_focus = attention_focus
	f.current_intention = current_intention
	f._current_thought = current_thought
	f._mind_workspace = workspace.duplicate(true)
	f._mind_self_model = self_model.duplicate(true)
	f._thought_stream = thought_stream
	f._thought_stream_age = thought_age_s
	f._td_eligibility_peak = eligibility_peak
	f._mind_writeback_log = writeback_log.duplicate(true)
	f._workspace_ignited = workspace_ignited
	f._prediction_error = prediction_error
	f._life_stance = life_stance
	f._self_summary = self_summary
	f._active_plan = active_plan.duplicate(true)
	f._world_model = world_model.duplicate(true)
	f._keeper_pending = keeper_pending.duplicate(true)
	f._episodic_retrieval_hint = episodic_retrieval_hint.duplicate(true)
	f._bid_salience_mods = bid_salience_mods.duplicate(true)
	f._writeback_cd = writeback_cd
	f._felt_self = felt_self.duplicate(true)
	f._sleep_depth = sleep_depth
	f._dream_wisp = dream_wisp


func snapshot() -> Dictionary:
	return {
		"schema_version": schema_version,
		"mood": mood, "arousal": arousal, "vigilance": vigilance,
		"stress": stress, "hunger": hunger, "surprise": surprise,
		"attention_focus": attention_focus,
		"current_intention": current_intention,
		"workspace": workspace.duplicate(true),
		"self_model": self_model.duplicate(true),
		"thought_stream": thought_stream,
	}


func diff(prev: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var snap: Dictionary = snapshot()
	for k in snap.keys():
		var a: Variant = snap[k]
		var b: Variant = prev.get(k, null)
		if a is float and b is float:
			if absf(float(a) - float(b)) > 0.02:
				out[k] = {"from": b, "to": a}
		elif a != b:
			out[k] = {"from": b, "to": a}
	return out


func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"full_fidelity": full_fidelity,
		"mood": mood, "arousal": arousal, "vigilance": vigilance,
		"stress": stress, "hunger": hunger, "surprise": surprise,
		"curiosity_drive": curiosity_drive, "spooked": spooked,
		"familiarity": familiarity, "mood_disposition": mood_disposition,
		"dopamine": dopamine, "serotonin": serotonin,
		"cortisol": cortisol, "noradrenaline": noradrenaline,
		"attention_focus": attention_focus,
		"current_intention": current_intention,
		"current_thought": current_thought,
		"goal_kind": goal_kind,
		"workspace": workspace.duplicate(true),
		"self_model": self_model.duplicate(true),
		"meta_states": meta_states.duplicate(),
		"thought_stream": thought_stream,
		"thought_age_s": thought_age_s,
		"writeback_log": writeback_log.duplicate(true),
		"prediction_error": prediction_error,
		"life_stance": life_stance,
		"self_summary": self_summary,
		"active_plan": active_plan.duplicate(true),
		"world_model": world_model.duplicate(true),
		"keeper_pending": keeper_pending.duplicate(true),
		"felt_self": felt_self.duplicate(true),
	}


func from_dict(d: Dictionary) -> void:
	schema_version = int(d.get("schema_version", SCHEMA_VERSION))
	full_fidelity = bool(d.get("full_fidelity", true))
	mood = float(d.get("mood", mood))
	arousal = float(d.get("arousal", arousal))
	vigilance = float(d.get("vigilance", vigilance))
	stress = float(d.get("stress", stress))
	hunger = float(d.get("hunger", hunger))
	surprise = float(d.get("surprise", surprise))
	curiosity_drive = float(d.get("curiosity_drive", curiosity_drive))
	spooked = float(d.get("spooked", spooked))
	familiarity = float(d.get("familiarity", familiarity))
	mood_disposition = float(d.get("mood_disposition", mood_disposition))
	dopamine = float(d.get("dopamine", dopamine))
	serotonin = float(d.get("serotonin", serotonin))
	cortisol = float(d.get("cortisol", cortisol))
	noradrenaline = float(d.get("noradrenaline", noradrenaline))
	attention_focus = str(d.get("attention_focus", attention_focus))
	current_intention = str(d.get("current_intention", current_intention))
	current_thought = str(d.get("current_thought", current_thought))
	goal_kind = str(d.get("goal_kind", goal_kind))
	var ws: Variant = d.get("workspace", null)
	if ws is Array:
		workspace = (ws as Array).duplicate(true)
	var sm: Variant = d.get("self_model", null)
	if sm is Dictionary:
		self_model = (sm as Dictionary).duplicate(true)
	var ms: Variant = d.get("meta_states", null)
	if ms is PackedStringArray:
		meta_states = ms as PackedStringArray
	thought_stream = str(d.get("thought_stream", thought_stream))
	thought_age_s = float(d.get("thought_age_s", thought_age_s))
	var wl: Variant = d.get("writeback_log", null)
	if wl is Array:
		writeback_log = (wl as Array).duplicate(true)
	prediction_error = float(d.get("prediction_error", prediction_error))
	life_stance = str(d.get("life_stance", life_stance))
	self_summary = str(d.get("self_summary", self_summary))
	var ap: Variant = d.get("active_plan", null)
	if ap is Dictionary:
		active_plan = (ap as Dictionary).duplicate(true)
	var wm: Variant = d.get("world_model", null)
	if wm is Dictionary:
		world_model = (wm as Dictionary).duplicate(true)
	var kp: Variant = d.get("keeper_pending", null)
	if kp is Dictionary:
		keeper_pending = (kp as Dictionary).duplicate(true)
	var fs: Variant = d.get("felt_self", null)
	if fs is Dictionary:
		felt_self = (fs as Dictionary).duplicate(true)
