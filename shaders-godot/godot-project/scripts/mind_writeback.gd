extends RefCounted

# CONSCIOUSNESS_ENGINEERING §H + DARING §B — bounded model→sim write-back.

const CognitiveSchema = preload("res://scripts/cognitive_schema.gd")
const MindSelfModel = preload("res://scripts/mind_self_model.gd")

const MOOD_NUDGE_MAX: float = 0.1
const WRITE_COOLDOWN_S: float = 12.0
const LOG_MAX: int = 24


static func _tank_config() -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null:
		return null
	var st: SceneTree = ml as SceneTree
	if st == null or st.root == null or not st.root.is_inside_tree():
		return null
	return st.root.get_node_or_null("/root/TankConfig")


static func writeback_enabled() -> bool:
	var cfg: Node = _tank_config()
	if cfg == null:
		return true
	if bool(cfg.get("sentience_voice_off")):
		return false
	return bool(cfg.get("consciousness_writeback_enabled") if cfg.get("consciousness_writeback_enabled") != null else true)


static func apply_op(f: Fish, op: Dictionary, ctx: Dictionary, reason: String = "") -> bool:
	if not writeback_enabled() or f == null:
		return false
	if not CognitiveSchema.validate_op(op, ctx):
		return false
	var cd: float = float(f.get("_writeback_cd") if f.get("_writeback_cd") != null else 0.0)
	if cd > 0.0:
		return false
	f._writeback_cd = WRITE_COOLDOWN_S
	var wb_log: Array = f._mind_writeback_log if f.get("_mind_writeback_log") is Array else []
	# Mood nudge (#73)
	var nudge: float = clampf(float(op.get("mood_nudge", 0.0)), -MOOD_NUDGE_MAX, MOOD_NUDGE_MAX)
	if absf(nudge) > 0.001:
		f.mood = clampf(f.mood + nudge, -1.0, 1.0)
		wb_log.append({"t": Time.get_ticks_msec(), "field": "mood", "delta": nudge, "reason": reason})
	# Keeper felt → mood (never moves body)
	if op.has("keeper_felt"):
		var felt: String = str(op.get("keeper_felt", "neutral"))
		var kv: float = float(ctx.get("keeper_valence", 0.0))
		if kv == 0.0:
			match felt:
				"greeting", "comfort", "name":
					kv = 0.12
				"scold":
					kv = -0.15
				"question":
					kv = 0.04
		f.mood = clampf(f.mood + clampf(kv * 0.35, -MOOD_NUDGE_MAX, MOOD_NUDGE_MAX), -1.0, 1.0)
		wb_log.append({"t": Time.get_ticks_msec(), "field": "keeper_felt", "value": felt, "reason": reason})
	# Belief as hypothesis (#74 / #13)
	if op.has("new_belief"):
		var belief: String = str(op.get("new_belief", ""))
		if belief != "":
			var cell: String = "reflect|%s" % belief.substr(0, 24)
			f._hypotheses[cell] = {"guess": belief, "confidence": 0.25, "source": "model"}
			wb_log.append({"t": Time.get_ticks_msec(), "field": "hypothesis", "value": belief, "reason": reason})
	# Bid salience mods (#14)
	if op.has("bid_weight") and op.get("bid_weight") is Dictionary:
		var bw: Dictionary = (op["bid_weight"] as Dictionary).duplicate(true)
		for k in bw:
			bw[k] = clampf(float(bw[k]), -0.2, 0.25)
		f._bid_salience_mods = bw
		wb_log.append({"t": Time.get_ticks_msec(), "field": "bid_weight", "value": bw, "reason": reason})
	# Memory keep flag (#75) — boost salience, never invent
	if bool(op.get("memory_keep", false)) and f.salient_memories.size() > 0:
		var last: Dictionary = f.salient_memories[-1]
		last["weight"] = clampf(float(last.get("weight", 0.5)) + 0.15, 0.0, 1.0)
		wb_log.append({"t": Time.get_ticks_msec(), "field": "memory_keep", "reason": reason})
	# Intention proposal (#72) — procedural validates
	var intent: String = str(op.get("intention", "none"))
	if intent != "none" and intent != "":
		match intent:
			"seek_food":
				if f.hunger > 0.3:
					f.current_intention = "seeking food"
			"seek_safety":
				if f.stress > 0.35:
					f.current_intention = "staying wary"
			"explore":
				f.current_intention = "exploring"
			"rest":
				f.current_intention = "resting"
			"watch":
				f.current_intention = "watching"
	# Self-summary from line
	var line: String = str(op.get("line", ""))
	if line != "":
		MindSelfModel.update_self_summary(f, line)
	while wb_log.size() > LOG_MAX:
		wb_log.pop_front()
	f._mind_writeback_log = wb_log
	return true


static func never_moves_body(f: Fish, pos_before: Vector3) -> bool:
	if f == null:
		return true
	return f.position.is_equal_approx(pos_before)


static func tick_cooldown(f: Fish, dt: float) -> void:
	if f.get("_writeback_cd") == null:
		f._writeback_cd = 0.0
	f._writeback_cd = maxf(0.0, float(f._writeback_cd) - dt)
	# Decay bid salience mods
	if f.get("_bid_salience_mods") is Dictionary and not (f._bid_salience_mods as Dictionary).is_empty():
		var mods: Dictionary = (f._bid_salience_mods as Dictionary).duplicate(true)
		var dead: Array[String] = []
		for k in mods:
			mods[k] = float(mods[k]) - dt * 0.015
			if float(mods[k]) <= 0.005:
				dead.append(k)
		for k in dead:
			mods.erase(k)
		f._bid_salience_mods = mods
