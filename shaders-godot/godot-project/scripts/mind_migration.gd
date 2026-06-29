class_name MindMigration
extends RefCounted

# META #17 — MindState schema migration ladder. A v_n save is walked up to the
# current SCHEMA_VERSION one explicit step at a time, so new kernel fields are
# defaulted DELIBERATELY (not silently via dict.get) and the upgrade path is
# inspectable and testable. Never downgrades a newer save.


# Walk d from its stored schema_version up to `current`, applying each step.
static func migrate(d: Dictionary, current: int) -> Dictionary:
	var out: Dictionary = d.duplicate(true)
	var v: int = int(out.get("schema_version", 1))
	# Guard against a malformed/missing version and runaway loops.
	if v < 1:
		v = 1
	while v < current:
		out = _step(out, v)
		v += 1
		out["schema_version"] = v
	return out


# One version step (from_v → from_v + 1). Add new fields with explicit defaults.
static func _step(d: Dictionary, from_v: int) -> Dictionary:
	match from_v:
		1, 2:
			# Pre-v3: workspace/self-model became first-class.
			_default(d, {"workspace": [], "self_model": {}, "thought_stream": ""})
		3:
			# v3 → v4: the extended cognition-channel fields are now first-class
			# (they were appended ad-hoc to MindState; default them on old saves
			# instead of leaning on per-field .get fallbacks).
			_default(d, {
				"prediction_error": 0.0, "writeback_cd": 0.0, "sleep_depth": 0.0,
				"life_stance": "", "self_summary": "", "dream_wisp": "", "goal_kind": "",
				"active_plan": {}, "world_model": {}, "keeper_pending": {},
				"felt_self": {}, "episodic_retrieval_hint": {}, "bid_salience_mods": {},
			})
		_:
			pass
	return d


static func _default(d: Dictionary, defaults: Dictionary) -> void:
	for k in defaults.keys():
		if not d.has(k):
			d[k] = defaults[k]
