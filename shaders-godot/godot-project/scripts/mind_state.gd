class_name MindState
extends RefCounted

# CONSCIOUSNESS_ENGINEERING §A — unified MindState: the fish's mind as one object.
# fish.gd still owns scalar fields for save compat; MindState syncs each tick.

const SCHEMA_VERSION: int = 4

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
# [{label, salience, coalition}] — cycle-fresh refs from GlobalWorkspace.run_competition();
# commit_workspace_to() deep-copies onto the fish. (PERFORMANCE_UNTHROTTLED #14)
var workspace: Array = []
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
	var ms := MindState.new()
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
	workspace = f._mind_workspace.duplicate(true)
	self_model = f._mind_self_model.duplicate(true)
	thought_stream = f._thought_stream
	thought_age_s = f._thought_stream_age
	eligibility_peak = f._td_eligibility_peak
	writeback_log = f._mind_writeback_log.duplicate(true)
	prediction_error = f._prediction_error
	life_stance = f._life_stance
	self_summary = f._self_summary
	active_plan = f._active_plan.duplicate(true)
	world_model = f._world_model.duplicate(true)
	keeper_pending = f._keeper_pending.duplicate(true)
	episodic_retrieval_hint = f._episodic_retrieval_hint.duplicate(true)
	bid_salience_mods = f._bid_salience_mods.duplicate(true)
	writeback_cd = f._writeback_cd
	felt_self = f._felt_self.duplicate(true)
	sleep_depth = f._sleep_depth
	dream_wisp = f._dream_wisp


# Runtime modules still write Fish directly. Capture their completed work
# before the final commit, while keeping workspace/self-model authority here.
# Borrowing these owned containers is safe until the cycle ends; jobs and
# retained snapshots always detach before crossing an ownership boundary.
func capture_runtime_updates(f: Fish) -> void:
	mood = f.mood
	arousal = f.arousal
	vigilance = f.vigilance
	stress = f.stress
	surprise = f.surprise
	curiosity_drive = f.curiosity_drive
	spooked = f.spooked
	current_intention = f.current_intention
	current_thought = f._current_thought
	thought_stream = f._thought_stream
	thought_age_s = f._thought_stream_age
	eligibility_peak = f._td_eligibility_peak
	writeback_log = f._mind_writeback_log
	prediction_error = f._prediction_error
	life_stance = f._life_stance
	self_summary = f._self_summary
	active_plan = f._active_plan
	world_model = f._world_model
	keeper_pending = f._keeper_pending
	episodic_retrieval_hint = f._episodic_retrieval_hint
	bid_salience_mods = f._bid_salience_mods
	writeback_cd = f._writeback_cd
	felt_self = f._felt_self
	sleep_depth = f._sleep_depth
	dream_wisp = f._dream_wisp


func apply_to_fish(f: Fish, adopt: bool = false) -> void:
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
	f._mind_workspace = workspace if adopt else workspace.duplicate(true)
	f._mind_self_model = self_model if adopt else self_model.duplicate(true)
	f._thought_stream = thought_stream
	f._thought_stream_age = thought_age_s
	f._td_eligibility_peak = eligibility_peak
	f._mind_writeback_log = writeback_log if adopt else writeback_log.duplicate(true)
	f._workspace_ignited = workspace_ignited
	f._prediction_error = prediction_error
	f._life_stance = life_stance
	f._self_summary = self_summary
	f._active_plan = active_plan if adopt else active_plan.duplicate(true)
	f._world_model = world_model if adopt else world_model.duplicate(true)
	f._keeper_pending = keeper_pending if adopt else keeper_pending.duplicate(true)
	f._episodic_retrieval_hint = episodic_retrieval_hint if adopt else episodic_retrieval_hint.duplicate(true)
	f._bid_salience_mods = bid_salience_mods if adopt else bid_salience_mods.duplicate(true)
	f._writeback_cd = writeback_cd
	f._felt_self = felt_self if adopt else felt_self.duplicate(true)
	f._sleep_depth = sleep_depth
	f._dream_wisp = dream_wisp


## Mirror the Global Workspace decision (workspace / focus / ignition) — for which
## MindState is the authority — onto the fish runtime fields the rest of tick()
## still reads. The single typed propagation point (#14/#15 / 0E); as more readers
## move onto MindState these three writes shrink toward nothing.
func commit_workspace_to(f) -> void:
	if f == null:
		return
	f._mind_workspace = workspace.duplicate(true)
	f.attention_focus = attention_focus
	f._workspace_ignited = workspace_ignited


func snapshot() -> Dictionary:
	return _snapshot_values(true)


func _snapshot_values(copy_collections: bool) -> Dictionary:
	return {
		"schema_version": schema_version,
		"mood": mood, "arousal": arousal, "vigilance": vigilance,
		"stress": stress, "hunger": hunger, "surprise": surprise,
		"attention_focus": attention_focus,
		"current_intention": current_intention,
		"workspace": workspace.duplicate(true) if copy_collections else workspace,
		"self_model": self_model.duplicate(true) if copy_collections else self_model,
		"thought_stream": thought_stream,
	}


func diff(prev: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var snap: Dictionary = _snapshot_values(false)
	for k in snap:
		var a: Variant = snap[k]
		var b: Variant = prev.get(k, null)
		if a is float and b is float:
			if absf(float(a) - float(b)) > 0.02:
				out[k] = {"from": b, "to": a}
		elif a != b:
			# Comparison can borrow collections; retained history cannot. Copy
			# only changed values and detach both ends from future mutations.
			out[k] = {"from": _copy_diff_value(b), "to": _copy_diff_value(a)}
	return out


func _copy_diff_value(value: Variant) -> Variant:
	if value is Array or value is Dictionary:
		return value.duplicate(true)
	return value


# Default snapshots remain detached. A worker that is giving up its state can
# transfer the containers it already owns instead of cloning them again.
func to_dict(copy_collections: bool = true) -> Dictionary:
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
		"workspace": workspace.duplicate(true) if copy_collections else workspace,
		"self_model": self_model.duplicate(true) if copy_collections else self_model,
		"meta_states": meta_states.duplicate() if copy_collections else meta_states,
		"thought_stream": thought_stream,
		"thought_age_s": thought_age_s,
		"writeback_log": writeback_log.duplicate(true) if copy_collections else writeback_log,
		"prediction_error": prediction_error,
		"life_stance": life_stance,
		"self_summary": self_summary,
		"active_plan": active_plan.duplicate(true) if copy_collections else active_plan,
		"world_model": world_model.duplicate(true) if copy_collections else world_model,
		"keeper_pending": keeper_pending.duplicate(true) if copy_collections else keeper_pending,
		"felt_self": felt_self.duplicate(true) if copy_collections else felt_self,
		"workspace_ignited": workspace_ignited,
		"system2_pending": system2_pending,
		"eligibility_peak": eligibility_peak,
		"episodic_retrieval_hint": (
			episodic_retrieval_hint.duplicate(true) if copy_collections
			else episodic_retrieval_hint),
		"bid_salience_mods": (
			bid_salience_mods.duplicate(true) if copy_collections
			else bid_salience_mods),
		"writeback_cd": writeback_cd,
		"sleep_depth": sleep_depth,
		"dream_wisp": dream_wisp,
	}


func from_dict(d_in: Dictionary, adopt: bool = false) -> void:
	# META #17 — walk an older save up the migration ladder before reading, so new
	# fields are defaulted explicitly rather than degrading silently.
	# Migration makes one detached copy for normal callers. Its collections
	# already belong to this state; copying each of them again is redundant.
	# adopt=true is reserved for an exclusively owned job/result handoff.
	var d: Dictionary = MindMigration.migrate(d_in, SCHEMA_VERSION, not adopt)
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
		workspace = ws as Array
	var sm: Variant = d.get("self_model", null)
	if sm is Dictionary:
		self_model = sm as Dictionary
	var ms: Variant = d.get("meta_states", null)
	if ms is PackedStringArray:
		meta_states = ms as PackedStringArray
	thought_stream = str(d.get("thought_stream", thought_stream))
	thought_age_s = float(d.get("thought_age_s", thought_age_s))
	var wl: Variant = d.get("writeback_log", null)
	if wl is Array:
		writeback_log = wl as Array
	prediction_error = float(d.get("prediction_error", prediction_error))
	life_stance = str(d.get("life_stance", life_stance))
	self_summary = str(d.get("self_summary", self_summary))
	var ap: Variant = d.get("active_plan", null)
	if ap is Dictionary:
		active_plan = ap as Dictionary
	var wm: Variant = d.get("world_model", null)
	if wm is Dictionary:
		world_model = wm as Dictionary
	var kp: Variant = d.get("keeper_pending", null)
	if kp is Dictionary:
		keeper_pending = kp as Dictionary
	var fs: Variant = d.get("felt_self", null)
	if fs is Dictionary:
		felt_self = fs as Dictionary
	workspace_ignited = bool(d.get("workspace_ignited", workspace_ignited))
	system2_pending = bool(d.get("system2_pending", system2_pending))
	eligibility_peak = float(d.get("eligibility_peak", eligibility_peak))
	var hint: Variant = d.get("episodic_retrieval_hint", null)
	if hint is Dictionary:
		episodic_retrieval_hint = hint as Dictionary
	var mods: Variant = d.get("bid_salience_mods", null)
	if mods is Dictionary:
		bid_salience_mods = mods as Dictionary
	writeback_cd = float(d.get("writeback_cd", writeback_cd))
	sleep_depth = float(d.get("sleep_depth", sleep_depth))
	dream_wisp = str(d.get("dream_wisp", dream_wisp))
