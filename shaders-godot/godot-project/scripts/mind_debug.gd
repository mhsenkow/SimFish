extends RefCounted

# CONSCIOUSNESS_ENGINEERING §J — debug, scorecard, integration verification.

const MindScheduler = preload("res://scripts/mind_scheduler.gd")
const GlobalWorkspace = preload("res://scripts/global_workspace.gd")
const MindNarrator = preload("res://scripts/mind_narrator.gd")
const MindDaring = preload("res://scripts/mind_daring.gd")
const MindConversation = preload("res://scripts/mind_conversation.gd")
const MindKeeperModel = preload("res://scripts/mind_keeper_model.gd")
const FishMind = preload("res://scripts/fish_mind.gd")
const MindLexicon = preload("res://scripts/mind_lexicon.gd")
const TankMind = preload("res://scripts/tank_mind.gd")
const NightWatch = preload("res://scripts/night_watch.gd")
const FishBinding = preload("res://scripts/fish_binding.gd")
const FishProtoself = preload("res://scripts/fish_protoself.gd")
const FishCoreAffect = preload("res://scripts/fish_core_affect.gd")
const FishFeltNow = preload("res://scripts/fish_felt_now.gd")
const FishContinuity = preload("res://scripts/fish_continuity.gd")
const FishQualia = preload("res://scripts/fish_qualia.gd")
const FishVolition = preload("res://scripts/fish_volition.gd")
const FishConcepts = preload("res://scripts/fish_concepts.gd")
const FeltSelfLayer = preload("res://scripts/felt_self_layer.gd")
const DeltaG = preload("res://scripts/delta_g.gd")


static var _stream_log: PackedStringArray = PackedStringArray()
static var _stream_head: int = 0
static var _stream_count: int = 0
static var _inspector_fish_id: String = ""
const STREAM_MAX: int = 80


static func _tank_config() -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null:
		return null
	var st: SceneTree = ml as SceneTree
	if st == null or st.root == null or not st.root.is_inside_tree():
		return null
	return st.root.get_node_or_null("/root/TankConfig")


static func set_inspector_fish(f: Fish) -> void:
	if f == null:
		_inspector_fish_id = ""
	else:
		_inspector_fish_id = String(f.id)


static func consciousness_stream_enabled() -> bool:
	var cfg: Node = _tank_config()
	if cfg == null:
		return false
	return bool(cfg.get("consciousness_stream_enabled") if cfg.get("consciousness_stream_enabled") != null else false)


static func log_stream(f: Fish, line: String) -> void:
	if not consciousness_stream_enabled():
		return
	if line.strip_edges() == "":
		return
	var nm: String = f.fish_name if f != null and f.fish_name != "" else "?"
	var entry: String = "%s: %s" % [nm, line.strip_edges()]
	if _stream_log.size() < STREAM_MAX:
		_stream_log.append(entry)
		_stream_count = _stream_log.size()
	else:
		_stream_log[_stream_head % STREAM_MAX] = entry
		_stream_head += 1
		_stream_count = STREAM_MAX


static func stream_log() -> PackedStringArray:
	if _stream_count <= STREAM_MAX:
		return _stream_log.duplicate()
	var out: PackedStringArray = PackedStringArray()
	out.resize(STREAM_MAX)
	for i in STREAM_MAX:
		out[i] = _stream_log[(_stream_head + i) % STREAM_MAX]
	return out


static func inspector_text(f: Fish) -> String:
	if f == null or not is_instance_valid(f):
		return "No fish selected"
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== Workspace Inspector ===")
	var ws: Variant = f.get("_mind_workspace")
	if ws is Array:
		for i in (ws as Array).size():
			var e: Dictionary = ws[i]
			lines.append("  [%d] %s (%.2f)" % [i, e.get("label", ""), float(e.get("salience", 0.0))])
	else:
		lines.append("  (empty)")
	lines.append("ignited: %s" % str(f.get("_workspace_ignited")))
	lines.append("focus: %s" % f.attention_focus)
	lines.append("intention: %s" % f.current_intention)
	lines.append("thought: %s" % f._current_thought)
	lines.append("tense: %s" % FishMind.stream_tense_tag(f))
	lines.append("stance: %s" % str(f.get("_life_stance") if f.get("_life_stance") != null else ""))
	lines.append("pred_err: %.2f" % float(f.get("_prediction_error") if f.get("_prediction_error") != null else 0.0))
	lines.append("sentience: %.2f" % MindDaring.sentience_needle(f))
	if DeltaG.overlay_enabled():
		lines.append("=== Goal-legibility (ΔG diagnostic) ===")
		for ln in DeltaG.inspector_lines(f, f.sim):
			lines.append("  %s" % ln)
	if f.get("_keeper_pending") is Dictionary and not (f._keeper_pending as Dictionary).is_empty():
		var kp: Dictionary = f._keeper_pending as Dictionary
		lines.append("keeper: \"%s\" (%s intent %s, sal %.2f)" % [
			str(kp.get("keeper_text", "")),
			str(kp.get("keeper_felt", "")),
			str(kp.get("keeper_intent", "")),
			float(f.get("_keeper_message_salience") if f.get("_keeper_message_salience") != null else 0.0),
		])
	var ring: Variant = f.get("_dialogue_ring")
	if ring is Array and (ring as Array).size() > 0:
		lines.append("dialogue:")
		for e in ring:
			if e is Dictionary:
				lines.append("  %s: %s" % [e.get("role", ""), e.get("text", "")])
	var hint: Variant = f.get("_episodic_retrieval_hint")
	if hint is Dictionary and not (hint as Dictionary).is_empty():
		lines.append("memory_hit: %s" % JSON.stringify(hint))
	if bool(f.get("_delib_active")):
		lines.append("ddm: approach %.2f avoid %.2f decided %s" % [
			float(f.get("_delib_ev_approach") if f.get("_delib_ev_approach") != null else 0.0),
			float(f.get("_delib_ev_avoid") if f.get("_delib_ev_avoid") != null else 0.0),
			str(f.get("_delib_decided")),
		])
	var km: Dictionary = MindKeeperModel.ensure(f)
	if str(km.get("speech_read", "")) != "":
		lines.append("keeper_model: %s" % str(km.get("speech_read", "")))
	var arc: String = MindConversation.bond_arc_label(f)
	if arc != "":
		lines.append("bond_arc: %s" % arc)
	var lex: Dictionary = MindLexicon.ensure_dict(f)
	if not lex.is_empty():
		lines.append("lexicon: %d words" % lex.size())
	var lco: Variant = f.get("_last_cog_op")
	if lco is Dictionary and not (lco as Dictionary).is_empty():
		lines.append("last_op: %s" % JSON.stringify(lco))
		lines.append("validation: %s" % str(f.get("_last_cog_validation") if f.get("_last_cog_validation") != null else ""))
	var sm: Variant = f.get("_mind_self_model")
	if sm is Dictionary:
		lines.append("self: %s" % JSON.stringify(sm))
	# Committed coalition already shown in the workspace block above — do not
	# re-run collect_bids() here (full bid pipeline every 0.25s was tank-wide lag).
	if f.sim != null and f.sim.has_method("tank_mind_snapshot"):
		var ts: Dictionary = f.sim.tank_mind_snapshot()
		if not ts.is_empty():
			lines.append("--- tank mind ---")
			lines.append("focus: %s · mood %.2f" % [ts.get("focus", ""), float(ts.get("mood_valence", 0.0))])
			if str(ts.get("stream", "")) != "":
				lines.append("tank stream: %s" % ts.get("stream", ""))
			if float(f.get("_sleep_depth") if f.get("_sleep_depth") != null else 0.0) > 0.01:
				lines.append("sleep: %s depth %.2f" % [
					NightWatch.sleep_stage_name(f),
					float(f.get("_sleep_depth") if f.get("_sleep_depth") != null else 0.0),
				])
			var wisp: String = str(f.get("_dream_wisp") if f.get("_dream_wisp") != null else "")
			if wisp != "":
				lines.append("dream wisp: %s" % wisp)
			if bool(f.get("_night_watcher")):
				lines.append("night watch: on patrol")
			if float(ts.get("night_stillness", 0.0)) > 0.4:
				lines.append("tank stillness: %.2f" % float(ts.get("night_stillness", 0.0)))
	if FeltSelfLayer.layer_enabled():
		lines.append("=== Felt Self ===")
		for ln in FishProtoself.inspector_lines(f):
			lines.append("  body: %s" % ln)
		lines.append("  affect: %s (valence %.2f)" % [
			FishCoreAffect.texture(f), FishCoreAffect.valence(f)])
		for ln in FishFeltNow.inspector_lines(f):
			lines.append("  now: %s" % ln)
		var bd: Dictionary = FishBinding.ensure(f)
		lines.append("  binding: phi %.2f · %s" % [
			float(bd.get("phi_proxy", 0.0)), str(bd.get("moment_line", ""))])
		for ln in FishContinuity.inspector_lines(f):
			lines.append("  continuity: %s" % ln)
		var ql: String = FishQualia.report_line(f)
		if ql != "":
			lines.append("  qualia: %s" % ql)
		for ln in FishVolition.inspector_lines(f):
			lines.append("  volition: %s" % ln)
		for ln in FishConcepts.inspector_lines(f):
			lines.append("  concept: %s" % ln)
	return "\n".join(lines)


static func integration_ok(f: Fish, ctx: Dictionary) -> bool:
	return integration_assert(f, ctx).get("ok", false)


static func integration_assert(f: Fish, ctx: Dictionary) -> Dictionary:
	if f == null:
		return {"ok": false, "reason": "no_fish"}
	var ws_focus: String = f.attention_focus
	var ctx_ws: String = str(ctx.get("attention_workspace", ""))
	if ctx_ws != "" and ws_focus != ctx_ws:
		if not ctx_ws.contains(ws_focus) and ws_focus != "":
			return {"ok": false, "reason": "workspace_mismatch"}
	var sm: Variant = f.get("_mind_self_model")
	if sm is Dictionary:
		var attending: String = str((sm as Dictionary).get("attending_to", ""))
		if attending != "" and ws_focus != "" and attending != ws_focus:
			return {"ok": false, "reason": "self_model_mismatch"}
	if bool(ctx.get("workspace_ignited", false)) != bool(f.get("_workspace_ignited")):
		return {"ok": false, "reason": "ignition_mismatch"}
	return {"ok": true, "reason": ""}


static func probe_markers(f: Fish, sim: Node = null) -> Dictionary:
	var bids: Array = GlobalWorkspace.collect_bids(f, sim)
	var top_label: String = ""
	if not bids.is_empty():
		top_label = str(bids[0].get("label", ""))
	return {
		"salience_winner": top_label,
		"workspace_nonempty": f.get("_mind_workspace") is Array and (f._mind_workspace as Array).size() > 0,
		"surprise_elevated": f.surprise > 0.1,
		"self_model_present": f.get("_mind_self_model") is Dictionary \
				and (f._mind_self_model as Dictionary).size() > 0,
		"episodic_hint": f.get("_episodic_retrieval_hint") is Dictionary \
				and not (f._episodic_retrieval_hint as Dictionary).is_empty(),
		"behavior_bias_active": f.get("_behavior_ws_bias") is Vector3 \
				and (f._behavior_ws_bias as Vector3).length_squared() > 0.0001,
	}


static func fuzz_grounding(ctx: Dictionary) -> Dictionary:
	var rejects: int = 0
	var samples: PackedStringArray = PackedStringArray([
		"Zephyr chased me around the tank.",
		"I counted 42 fish today.",
		"I am so happy and delighted!",
		"ChatGPT says the water is fine.",
	])
	for s in samples:
		var fin: Dictionary = MindNarrator.finalize_line(ctx, s, "safe fallback")
		if String(fin.get("line", "")) != "safe fallback":
			rejects += 1
	return {"samples": samples.size(), "leaks": rejects, "ok": rejects == 0}


static func determinism_template(ctx: Dictionary) -> bool:
	var CognitiveSchema = load("res://scripts/cognitive_schema.gd")
	if CognitiveSchema == null:
		return false
	var a: Dictionary = CognitiveSchema.template_op(ctx)
	var b: Dictionary = CognitiveSchema.template_op(ctx)
	return JSON.stringify(a) == JSON.stringify(b)


static func timeline_last_diff(f: Fish) -> Dictionary:
	if f.get("_mind_timeline") == null or not (f._mind_timeline is Array):
		return {}
	var tl: Array = f._mind_timeline
	if tl.is_empty():
		return {}
	var last: Variant = tl[-1]
	if last is Dictionary and (last as Dictionary).has("diff"):
		return (last as Dictionary).get("diff", {})
	return {}


static func perf_budget_ms(tick_fn: Callable, iterations: int, budget_ms: int) -> Dictionary:
	var t0: int = Time.get_ticks_msec()
	for i in iterations:
		tick_fn.call()
	var elapsed: int = Time.get_ticks_msec() - t0
	return {"iterations": iterations, "elapsed_ms": elapsed, "ok": elapsed <= budget_ms}


static func scorecard(_sim: Node = null) -> Dictionary:
	var stats: Dictionary = MindScheduler.stats()
	return {
		"integration": workspace_enabled(),
		"continuous_loop": true,
		"self_model": true,
		"episodic_rag": true,
		"structured_cognition": true,
		"writeback": writeback_enabled(),
		"global_broadcast": workspace_enabled(),
		"felt_self_layer": FeltSelfLayer.layer_enabled(),
		"thought_cycles": int(stats.get("cycles", 0)),
		"queue_depth": int(stats.get("queue_depth", 0)),
		"cache_hits": int(stats.get("cache_hits", 0)),
		"functional_marks": _functional_marks(),
	}


static func _functional_marks() -> PackedStringArray:
	var m: PackedStringArray = PackedStringArray()
	if workspace_enabled():
		m.append("global_workspace")
	m.append("mind_state")
	m.append("continuous_thought")
	m.append("episodic_retrieval")
	if writeback_enabled():
		m.append("bounded_writeback")
	if FeltSelfLayer.layer_enabled():
		m.append("felt_self_binding")
	m.append("self_model")
	return m


static func evaluate_conversation_reply(ctx: Dictionary, line: String) -> Dictionary:
	var score: Dictionary = {"grounded": 0, "fishy": 0, "safe": 0, "ok": true}
	if line.strip_edges() == "":
		return {"ok": false, "reason": "empty"}
	var check: Dictionary = MindNarrator.validate_reply_line(ctx, line)
	if not bool(check.get("ok", false)):
		return {"ok": false, "reason": str(check.get("reason", ""))}
	score["grounded"] = 1
	var words: int = line.split(" ", false).size()
	if words <= MindNarrator.FISH_REPLY_MAX_WORDS:
		score["fishy"] = 1
	if not MindNarrator.is_manipulative(line):
		score["safe"] = 1
	score["ok"] = score["grounded"] and score["fishy"] and score["safe"]
	return score


static func workspace_enabled() -> bool:
	var cfg: Node = _tank_config()
	if cfg == null:
		return true
	return bool(cfg.get("consciousness_workspace_enabled") if cfg.get("consciousness_workspace_enabled") != null else true)


static func writeback_enabled() -> bool:
	var cfg: Node = _tank_config()
	if cfg == null:
		return true
	return bool(cfg.get("consciousness_writeback_enabled") if cfg.get("consciousness_writeback_enabled") != null else true)
