class_name AccessibilityRuntime
extends RefCounted

# SYSTEMIC #86 — reduced-motion gates for sim + render motion.


static func reduced_motion_enabled() -> bool:
	var cfg := _cfg()
	if cfg != null and bool(cfg.get("reduced_motion")):
		return true
	return false


static func motion_scale() -> float:
	return 0.0 if reduced_motion_enabled() else 1.0


static func plant_sway_mult(base: float = 1.0) -> float:
	return base * motion_scale()


static func fauna_pulse_enabled(default_on: bool) -> bool:
	if reduced_motion_enabled():
		return false
	return default_on


static func allow_auto_orbit(requested: bool) -> bool:
	if reduced_motion_enabled():
		return false
	return requested


# motion_scale() is read from world.gd's per-frame sway tick, so the autoload
# handle is memoised rather than re-resolved from the scene path each call.
static var _cfg_cache: Node = null


static func reset_cache_for_test() -> void:
	_cfg_cache = null


static func _cfg() -> Node:
	if _cfg_cache != null and is_instance_valid(_cfg_cache):
		return _cfg_cache
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null:
		return null
	var st: SceneTree = ml as SceneTree
	if st == null or st.root == null:
		return null
	_cfg_cache = st.root.get_node_or_null("TankConfig")
	return _cfg_cache
