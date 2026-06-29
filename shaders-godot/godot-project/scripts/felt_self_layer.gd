extends RefCounted

# SENTIENCE_THE_FELT_SELF — layer toggle (no module deps; breaks preload cycles).

const HONEST_FRAME: String = "Functional phenomenology — structure of self-reported feeling, not a claim of inner experience."


static func _tank_config() -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null:
		return null
	var st: SceneTree = ml as SceneTree
	if st == null or st.root == null or not st.root.is_inside_tree():
		return null
	return st.root.get_node_or_null("/root/TankConfig")


static func layer_enabled() -> bool:
	var cfg: Node = _tank_config()
	if cfg == null:
		return true
	if bool(cfg.get("sentience_voice_off")):
		return false
	return bool(cfg.get("felt_self_enabled") if cfg.get("felt_self_enabled") != null else true)
