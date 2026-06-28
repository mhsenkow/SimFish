extends RefCounted

# class_name intentionally omitted — callers preload this script as
# `const MindDaring = preload(...)`.

# SENTIENCE_THE_DARING_MIND — orchestration hub (Sections F–J helpers + tick glue).

const KeeperInput = preload("res://scripts/keeper_input.gd")
const MindLexicon = preload("res://scripts/mind_lexicon.gd")
const MindWorldModel = preload("res://scripts/mind_world_model.gd")
const MindWriteback = preload("res://scripts/mind_writeback.gd")
const CognitiveSchema = preload("res://scripts/cognitive_schema.gd")
const FishMind = preload("res://scripts/fish_mind.gd")
const EpisodicMemory = preload("res://scripts/episodic_memory.gd")
const MindSelfModel = preload("res://scripts/mind_self_model.gd")

const STANCES: Array[String] = ["trusting", "wary", "playful", "steadfast", "curious"]
const PLAN_VERBS: Array[String] = ["go_to_nook", "wait_for_feed", "shadow_mate", "watch", "rest"]


static func tick(f: Fish, sim: Node, dt: float, neighbors: Array) -> void:
	if f == null:
		return
	MindLexicon.tick_decay(f, dt)
	MindWorldModel.tick(f, sim, dt)
	_tick_stress_mend(f, dt)
	_tick_keeper_decay(f, dt)
	_tick_plan(f, sim, dt)
	_tick_stance(f, dt)
	_tick_mend(f, dt)
	_tick_longing(f, dt)
	_tick_curiosity_keeper(f, sim, dt)
	_tick_reconciliation(f, neighbors, dt)
	_tick_empathy(f, neighbors, dt)
	_tick_aesthetic(f, sim, dt)
	if f._asleep and f._dreaming:
		_dream_rollout(f, sim)


static func _tick_stress_mend(f: Fish, _dt: float) -> void:
	if f.stress > 0.5:
		f._peak_stress_recent = maxf(float(f.get("_peak_stress_recent") if f.get("_peak_stress_recent") != null else 0.0), f.stress)
	elif f.stress < 0.32 and float(f.get("_peak_stress_recent") if f.get("_peak_stress_recent") != null else 0.0) > 0.48:
		f._mend_pending = true
		f._peak_stress_recent = 0.0


static func _tick_keeper_decay(f: Fish, dt: float) -> void:
	if f.get("_keeper_message_salience") == null:
		return
	f._keeper_message_salience = maxf(0.0, float(f._keeper_message_salience) - dt * 0.35)


static func _tick_plan(f: Fish, sim: Node, dt: float) -> void:
	var plan: Variant = f.get("_active_plan")
	if plan == null or not (plan is Dictionary) or (plan as Dictionary).is_empty():
		return
	var p: Dictionary = plan as Dictionary
	var step: String = str(p.get("step", ""))
	var remaining: float = float(p.get("remaining", 0.0)) - dt
	if remaining <= 0.0:
		var steps: Array = p.get("steps", [])
		var idx: int = int(p.get("idx", 0)) + 1
		if idx >= steps.size():
			f._active_plan = {}
			return
		p["idx"] = idx
		p["step"] = str(steps[idx])
		p["remaining"] = 4.0
	else:
		p["remaining"] = remaining
	f._active_plan = p
	match step:
		"wait_for_feed":
			if sim != null and sim.has_method("feed_anticipation_active") \
					and bool(sim.feed_anticipation_active()):
				f.current_intention = "waiting to feed"
		"shadow_mate":
			if f.partner != null and is_instance_valid(f.partner):
				f.current_intention = "staying near mate"
		"go_to_nook":
			f.current_intention = "exploring a nook"
		"watch":
			f.current_intention = "watching"
		"rest":
			f.current_intention = "resting"


static func _tick_stance(f: Fish, dt: float) -> void:
	if f.get("_life_stance") == null or str(f._life_stance) == "":
		f._life_stance = _infer_stance(f)
	var target: String = _infer_stance(f)
	if target != str(f._life_stance):
		f._stance_drift_t = float(f.get("_stance_drift_t") if f.get("_stance_drift_t") != null else 0.0) + dt
		if float(f._stance_drift_t) > 28.0:
			FishMind.record_salient(f, "self", "I've become %s" % target, 0.42, f.position)
			f._life_stance = target
			f._stance_drift_t = 0.0
	else:
		f._stance_drift_t = 0.0


static func _infer_stance(f: Fish) -> String:
	if f._trait("boldness") > 0.62 and f._trait("curiosity") > 0.55:
		return "playful"
	if f.stress > 0.55 or f.vigilance > 0.6:
		return "wary"
	if f._trait("curiosity") > 0.58:
		return "curious"
	if f.mood > 0.25 and f.stress < 0.35:
		return "trusting"
	return "steadfast"


static func _tick_mend(f: Fish, dt: float) -> void:
	if f.stress > 0.45:
		f._mend_trust = maxf(0.0, float(f.get("_mend_trust") if f.get("_mend_trust") != null else 0.0) - dt * 0.02)
		return
	if f.get("_mend_pending") == true and f.stress < 0.32:
		f._mend_trust = clampf(float(f.get("_mend_trust") if f.get("_mend_trust") != null else 0.0) + dt * 0.08, 0.0, 1.0)
		if float(f._mend_trust) > 0.72:
			f._mend_pending = false
			FishMind.record_salient(f, "self", "I chose to trust again", 0.55, f.position)
			f.vigilance = maxf(0.0, f.vigilance - 0.15)


static func _tick_longing(f: Fish, dt: float) -> void:
	var lr: float = float(f.get("_longing_residue") if f.get("_longing_residue") != null else 0.0)
	if lr <= 0.0:
		return
	f._longing_residue = maxf(0.0, lr - dt * 0.015)
	f.mood = clampf(f.mood - dt * lr * 0.04, -1.0, 1.0)


static func on_goal_lost(f: Fish, reason: String) -> void:
	f._longing_residue = clampf(float(f.get("_longing_residue") if f.get("_longing_residue") != null else 0.0) + 0.35, 0.0, 1.0)
	FishMind.record_salient(f, "loss", reason, 0.62, f.position)


static func _tick_curiosity_keeper(f: Fish, _sim: Node, dt: float) -> void:
	if f.familiarity < 0.35 or f._trait("boldness") < 0.45:
		return
	var ck: float = float(f.get("_curiosity_about_keeper") if f.get("_curiosity_about_keeper") != null else 0.0)
	if KeeperInput.gaze_fish_id == str(f.id) and KeeperInput.gaze_seconds > 4.0:
		ck = clampf(ck + dt * 0.05, 0.0, 1.0)
		f._curiosity_about_keeper = ck
		if ck > 0.65 and randf() < dt * 0.08:
			f.curiosity_drive = clampf(f.curiosity_drive + 0.12, 0.0, 1.0)


static func _tick_reconciliation(f: Fish, neighbors: Array, dt: float) -> void:
	if f.grudges.is_empty():
		return
	for n in neighbors:
		if not (n is Fish):
			continue
		var o: Fish = n
		if not f.grudges.has(o.id):
			continue
		if o.position.distance_squared_to(f.position) > 2.25:
			continue
		var g: float = float(f.grudges[o.id])
		f.grudges[o.id] = maxf(0.0, g - dt * 0.04)
		if g > 0.2 and float(f.grudges[o.id]) < 0.08:
			FishMind.record_salient(f, "social", "made peace with %s" % o.species, 0.38, f.position)


static func _tick_empathy(f: Fish, neighbors: Array, dt: float) -> void:
	for n in neighbors:
		if not (n is Fish):
			continue
		var o: Fish = n
		if not f.bonds.has(o.id) or float(f.bonds[o.id]) < 0.35:
			continue
		if o.stress < 0.55:
			continue
		f.stress = clampf(f.stress + o.stress * dt * 0.04, 0.0, 1.0)
		f.mood = clampf(f.mood - o.stress * dt * 0.03, -1.0, 1.0)
		break


static func _tick_aesthetic(f: Fish, _sim: Node, dt: float) -> void:
	if f.get("_aesthetic_hue") == null:
		f._aesthetic_hue = randf()
	var linger: float = float(f.get("_aesthetic_linger") if f.get("_aesthetic_linger") != null else 0.0)
	if f.speed < 0.25 and f.stress < 0.4:
		linger += dt
	else:
		linger = maxf(0.0, linger - dt * 0.5)
	f._aesthetic_linger = linger
	if linger > 8.0 and randf() < dt * 0.02:
		f.mood = clampf(f.mood + 0.02, -1.0, 1.0)


static func _dream_rollout(f: Fish, _sim: Node) -> void:
	if randf() > 0.04:
		return
	EpisodicMemory.consolidate_sleep(f)
	var note: String = "dreaming of %s" % str(f.attention_focus if f.attention_focus != "" else "the day")
	FishMind.record_salient(f, "dream", note, 0.32, f.position)


static func apply_model_op(f: Fish, op: Dictionary, ctx: Dictionary) -> bool:
	f._last_cog_op = op.duplicate(true)
	var ok: bool = CognitiveSchema.validate_op(op, ctx)
	f._last_cog_validation = "accepted" if ok else "rejected"
	if not ok:
		return false
	if op.has("choice") and f._delib_active and not f._delib_decided:
		if str(op.get("choice")) == "approach":
			f._delib_choice = 1
		elif str(op.get("choice")) == "avoid":
			f._delib_choice = 2
		f._delib_decided = true
	if op.has("plan") and op.get("plan") is Array:
		var steps: Array = []
		for s in op["plan"]:
			var verb: String = str(s)
			if PLAN_VERBS.has(verb):
				steps.append(verb)
		if not steps.is_empty():
			f._active_plan = {"steps": steps, "idx": 0, "step": str(steps[0]), "remaining": 4.0}
	if op.has("bid_weight"):
		var bw: Variant = op.get("bid_weight")
		if bw is Dictionary:
			f._bid_salience_mods = (bw as Dictionary).duplicate(true)
	var certainty: float = float(op.get("certainty", 1.0))
	if certainty < 0.45:
		f.max_turn_rate *= 0.88
		FishMind.maybe_double_take(f, f.curiosity_drive)
	return MindWriteback.apply_op(f, op, ctx, "model")


static func sentience_needle(f: Fish) -> float:
	var ign: float = 1.0 if bool(f.get("_workspace_ignited")) else 0.35
	var wm: float = 1.0 - clampf(float(f.get("_prediction_error") if f.get("_prediction_error") != null else 0.3), 0.0, 1.0)
	var mem: float = clampf(float(f.salient_memories.size()) / 8.0, 0.0, 1.0)
	return clampf(ign * 0.4 + wm * 0.35 + mem * 0.25, 0.0, 1.0)


static func self_authored_goal(f: Fish) -> void:
	if f.stress > 0.45 or f.hunger > 0.55:
		return
	if f.get("_contentment") != null and float(f._contentment) < 0.55:
		return
	if randf() > 0.002:
		return
	var goals: Array[String] = ["circle the plants", "follow a friend", "defend this corner", "patrol the open"]
	f.current_intention = goals[randi() % goals.size()]
	FishMind.record_salient(f, "goal", "I want to %s" % f.current_intention, 0.4, f.position)
