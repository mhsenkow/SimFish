extends RefCounted

# SENTIENCE_THE_FELT_SELF — layer toggle (no module deps; breaks preload cycles).

const HONEST_FRAME: String = "Functional phenomenology — structure of self-reported feeling, not a claim of inner experience."

const MindWorkerCfg = preload("res://scripts/mind_worker_cfg.gd")

static var _worker_felt_self_override: Variant = null


static func _coerce_bool(v: Variant, default: bool) -> bool:
	if v is bool:
		return v
	if v == null:
		return default
	return default if v == false else true


static func set_worker_felt_self_override(v: Variant) -> void:
	_worker_felt_self_override = v


static func _tank_config() -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null:
		return null
	var st: SceneTree = ml as SceneTree
	if st == null or st.root == null or not st.root.is_inside_tree():
		return null
	return st.root.get_node_or_null("/root/TankConfig")


static func layer_enabled() -> bool:
	# Worker batch: never touch /root/TankConfig (propagate_notification is main-thread only).
	if not Thread.is_main_thread():
		if MindWorkerCfg.active and MindWorkerCfg.read_bool("sentience_voice_off", false):
			return false
		if _worker_felt_self_override != null:
			return _coerce_bool(_worker_felt_self_override, true)
		if MindWorkerCfg.active:
			return MindWorkerCfg.read_bool("felt_self_enabled", true)
		return true
	# Main thread always reads live TankConfig (ignore worker snapshot).
	var cfg: Node = _tank_config()
	if cfg == null:
		return true
	if _coerce_bool(cfg.get("sentience_voice_off"), false):
		return false
	return _coerce_bool(cfg.get("felt_self_enabled"), true)
