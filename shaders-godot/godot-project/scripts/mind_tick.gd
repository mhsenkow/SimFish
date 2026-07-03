class_name MindTick
extends RefCounted

# PERFORMANCE_UNTHROTTLED #1/#6/#7/#25 — fixed-rate mind cadence, stagger, output lerp.

const DEFAULT_HZ: float = 15.0
const SLOW_LANE_SCALE: float = 0.5  # #25 idle-tank half cadence
const MindSoulPass2 = preload("res://scripts/mind_soul_pass2.gd")

static var _snap_hz: float = -1.0
static var _snap_idle_mult: float = 1.0

static var _stats: Dictionary = {
	"ticks": 0, "skipped_frames": 0, "hz_target": DEFAULT_HZ,
}
static var _achieved_window_ms: int = 0
static var _achieved_ticks: int = 0
static var _achieved_hz: float = 0.0
static var _eligible_fish: int = 1


static func reset_stats_for_test() -> void:
	_stats = {"ticks": 0, "skipped_frames": 0, "hz_target": DEFAULT_HZ}
	_achieved_window_ms = 0
	_achieved_ticks = 0
	_achieved_hz = 0.0
	_eligible_fish = 1
	_snap_hz = -1.0
	_snap_idle_mult = 1.0


static func apply_ambient_snap(d: Dictionary) -> void:
	if d.is_empty():
		return
	_snap_hz = float(d.get("mind_cadence_hz", DEFAULT_HZ))
	_snap_idle_mult = float(d.get("mind_idle_mult", 1.0))


static func set_eligible_fish(n: int) -> void:
	_eligible_fish = maxi(n, 1)


static func achieved_hz() -> float:
	return _achieved_hz


static func achieved_hz_per_fish() -> float:
	if _eligible_fish <= 0:
		return 0.0
	return _achieved_hz / float(_eligible_fish)


static func _note_mind_tick() -> void:
	var now: int = Time.get_ticks_msec()
	_achieved_ticks += 1
	if _achieved_window_ms <= 0:
		_achieved_window_ms = now
		return
	var elapsed: int = now - _achieved_window_ms
	if elapsed >= 1000:
		_achieved_hz = float(_achieved_ticks) * 1000.0 / float(elapsed)
		_achieved_ticks = 0
		_achieved_window_ms = now


static func stats() -> Dictionary:
	var out: Dictionary = _stats.duplicate()
	out["achieved_hz"] = _achieved_hz
	out["achieved_hz_per_fish"] = achieved_hz_per_fish()
	out["habit"] = MindSoulPass2.habit_stats()
	return out


static func target_hz() -> float:
	if _snap_hz >= 0.0:
		return _snap_hz
	var ml: MainLoop = Engine.get_main_loop()
	if ml is SceneTree and (ml as SceneTree).root != null:
		var cfg: Node = (ml as SceneTree).root.get_node_or_null("/root/TankConfig")
		if cfg != null and cfg.get("mind_cadence_hz") != null:
			return maxf(0.0, float(cfg.mind_cadence_hz))
	return DEFAULT_HZ


static func mind_dt() -> float:
	var hz: float = target_hz()
	return 1.0 / hz if hz > 0.0 else 0.0


static func enabled() -> bool:
	return target_hz() > 0.0


static func idle_slow_mult(sim: Node) -> float:
	if _snap_idle_mult > 0.0 and _snap_idle_mult < 1.0:
		return _snap_idle_mult
	if sim == null or sim.get("_room_idle_s") == null:
		return 1.0
	var idle: float = float(sim._room_idle_s)
	if idle < 30.0:
		return 1.0
	return SLOW_LANE_SCALE


static func init_fish(f) -> void:
	if f.get("_mind_stagger") == null:
		var hz: float = maxf(target_hz(), 1.0)
		var slot: int = absi(hash(str(f.id))) % int(hz)
		f._mind_stagger = float(slot) / hz
		f._mind_accum = f._mind_stagger * mind_dt()


static func advance(f, sim, dt: float) -> Dictionary:
	if not enabled():
		return {"run": true, "mind_dt": dt}
	init_fish(f)
	var step: float = mind_dt() * idle_slow_mult(sim)
	if f.is_guardian or (f.get("fish_name") != null and str(f.fish_name) != ""):
		step = mind_dt()
	f._mind_accum = float(f._mind_accum) + dt
	var run: bool = false
	var used_dt: float = dt
	if f._mind_accum >= step:
		f._mind_accum -= step
		run = true
		used_dt = step
		_stats["ticks"] = int(_stats.get("ticks", 0)) + 1
		_note_mind_tick()
		f._bid_slow_accum = float(f.get("_bid_slow_accum") if f.get("_bid_slow_accum") != null else 0.0) + step
		if f._bid_slow_accum >= 1.0 / 3.0:
			f._bid_slow_accum = 0.0
			f._bid_slow_due = true
	else:
		_stats["skipped_frames"] = int(_stats.get("skipped_frames", 0)) + 1
	return {"run": run, "mind_dt": used_dt}


static func capture_ws_bias(f) -> void:
	if f.get("_behavior_ws_bias") is Vector3:
		f._ws_bias_lerp_to = f._behavior_ws_bias as Vector3
	if f.get("_ws_bias_lerp_from") == null:
		f._ws_bias_lerp_from = f._ws_bias_lerp_to


static func lerp_visuals(f, _dt: float) -> void:
	if not enabled():
		return
	var from_v: Vector3 = f._ws_bias_lerp_from if f.get("_ws_bias_lerp_from") is Vector3 else Vector3.ZERO
	var to_v: Vector3 = f._ws_bias_lerp_to if f.get("_ws_bias_lerp_to") is Vector3 else from_v
	var step: float = mind_dt()
	if step <= 0.0:
		return
	var t: float = clampf(float(f._mind_accum) / step, 0.0, 1.0)
	var lerped: Vector3 = from_v.lerp(to_v, t)
	f._behavior_ws_bias = lerped


static func on_mind_tick_start(f) -> void:
	if not enabled():
		return
	f._ws_bias_lerp_from = f._behavior_ws_bias if f.get("_behavior_ws_bias") is Vector3 else Vector3.ZERO


static func on_mind_tick_end(f) -> void:
	if not enabled():
		return
	capture_ws_bias(f)
