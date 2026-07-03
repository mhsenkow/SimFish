class_name PerfGovernor
extends RefCounted

# PERFORMANCE_REALTIME #2, #97, #98 — frame budget + subsystem attribution.
# Rolling p95 frame time → budget_pressure 0..1 for MindLOD; µs scopes for the perf HUD.

const FRAME_RING: int = 60
const TARGET_FRAME_MS: float = 16.6
const SPIKE_MS: float = 28.0

const _MindTickScript = preload("res://scripts/mind_tick.gd")
const _MindCacheStatsScript = preload("res://scripts/mind_cache_stats.gd")
const MindSoulPass2 = preload("res://scripts/mind_soul_pass2.gd")

static var _frame_ring: PackedFloat32Array = PackedFloat32Array()
static var _frame_head: int = 0
static var _frame_count: int = 0
static var budget_pressure: float = 0.0
static var last_frame_ms: float = 0.0
static var last_spike_subsystem: String = ""

static var _scopes: Dictionary = {}
static var _scope_active: Dictionary = {}
static var _alloc_baseline: int = -1
static var _alloc_last_frame: int = 0
static var _alloc_scope_tag: String = ""
static var _ledger: Dictionary = {}


static func alloc_scope_tag() -> String:
	return _alloc_scope_tag


static func record_ledger(item_id: int, before_us: int, after_us: int) -> void:
	_ledger[str(item_id)] = {"before_us": before_us, "after_us": after_us}


static func ledger_snapshot() -> Dictionary:
	return _ledger.duplicate(true)


static func ledger_hud_suffix(max_items: int = 3) -> String:
	if _ledger.is_empty():
		return ""
	var keys: Array = _ledger.keys()
	keys.sort()
	var parts: PackedStringArray = PackedStringArray()
	for i in mini(keys.size(), max_items):
		var k: String = str(keys[i])
		var row: Dictionary = _ledger[k]
		var saved_us: int = int(row.get("before_us", 0)) - int(row.get("after_us", 0))
		if saved_us > 0:
			parts.append("#%s −%.1fms" % [k, float(saved_us) / 1000.0])
	return "" if parts.is_empty() else " · " + ", ".join(parts)


static func reset_for_test() -> void:
	_frame_ring = PackedFloat32Array()
	_frame_head = 0
	_frame_count = 0
	budget_pressure = 0.0
	last_frame_ms = 0.0
	last_spike_subsystem = ""
	_scopes.clear()
	_scope_active.clear()
	_alloc_baseline = -1
	_alloc_last_frame = 0
	_alloc_scope_tag = ""
	_ledger.clear()


static func record_frame(dt_sec: float) -> void:
	var ms: float = dt_sec * 1000.0
	last_frame_ms = ms
	if _frame_ring.size() < FRAME_RING:
		_frame_ring.resize(FRAME_RING)
	_frame_ring[_frame_head] = ms
	_frame_head = (_frame_head + 1) % FRAME_RING
	_frame_count = mini(_frame_count + 1, FRAME_RING)
	budget_pressure = _pressure_from_ring()
	if ms >= SPIKE_MS:
		last_spike_subsystem = _top_scope_name()
	_scope_active.clear()
	var prev_alloc: int = _alloc_last_frame
	_alloc_last_frame = OS.get_static_memory_usage()
	if _alloc_baseline < 0:
		_alloc_baseline = _alloc_last_frame
	elif _alloc_last_frame > prev_alloc + 4096:
		_alloc_scope_tag = _top_scope_name()


static func _pressure_from_ring() -> float:
	if _frame_count <= 0:
		return 0.0
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(_frame_count)
	for i in _frame_count:
		samples[i] = _frame_ring[i]
	samples.sort()
	var p95_idx: int = clampi(int(ceil(float(_frame_count) * 0.95)) - 1, 0, _frame_count - 1)
	var p95: float = samples[p95_idx]
	return clampf((p95 - TARGET_FRAME_MS * 0.85) / (TARGET_FRAME_MS * 1.1), 0.0, 1.0)


# #63 — bias adaptive resolution down when the governor is stressed.
static func adaptive_fps_penalty() -> float:
	return budget_pressure * 14.0


static func governor_step_down() -> bool:
	return budget_pressure > 0.66


static func governor_step_up_block() -> bool:
	return budget_pressure > 0.33


static func scope_begin(name: String) -> void:
	_scope_active[name] = Time.get_ticks_usec()


static func scope_end(name: String) -> void:
	var t0: Variant = _scope_active.get(name, null)
	if t0 == null:
		return
	_scope_active.erase(name)
	var dt_us: int = Time.get_ticks_usec() - int(t0)
	_scopes[name] = int(_scopes.get(name, 0)) + dt_us


static func scope_reset_frame() -> void:
	_scopes.clear()


static func scopes_snapshot() -> Dictionary:
	return _scopes.duplicate()


static func alloc_delta_since_baseline() -> int:
	if _alloc_baseline < 0:
		return 0
	return _alloc_last_frame - _alloc_baseline


static func _top_scope_name() -> String:
	var best: String = ""
	var best_us: int = 0
	for k in _scopes:
		var v: int = int(_scopes[k])
		if v > best_us:
			best_us = v
			best = str(k)
	return best if best != "" else "unknown"


static func hud_line(fish_n: int, draw_n: int) -> String:
	var fps: float = 1000.0 / maxf(last_frame_ms, 0.001)
	var line: String = "fps %.0f · fish %d · draw %d · p95 %.1fms · lod %.2f" % [
		fps, fish_n, draw_n, last_frame_ms, budget_pressure]
	if _MindTickScript.enabled():
		var tgt: float = _MindTickScript.target_hz()
		var got: float = _MindTickScript.achieved_hz_per_fish()
		line += " · mind %.1f/%.0f Hz" % [got, tgt]
		var habit: Dictionary = MindSoulPass2.habit_stats()
		if int(habit.get("attempts", 0)) > 20:
			line += " · habit %.0f%%" % [float(habit.get("rate", 0.0)) * 100.0]
	var cache_suffix: String = _MindCacheStatsScript.hud_suffix()
	if cache_suffix != "":
		line += cache_suffix
	line += ledger_hud_suffix()
	var alloc_d: int = alloc_delta_since_baseline()
	if alloc_d != 0:
		var tag: String = _alloc_scope_tag
		if tag != "":
			line += " · alloc %+d (%s)" % [alloc_d, tag]
		else:
			line += " · alloc %+d" % alloc_d
	if last_spike_subsystem != "" and last_frame_ms >= SPIKE_MS:
		line += " · spike:%s" % last_spike_subsystem
	var scopes: Dictionary = scopes_snapshot()
	if not scopes.is_empty():
		var parts: PackedStringArray = PackedStringArray()
		for k in scopes:
			parts.append("%s %.2fms" % [k, float(scopes[k]) / 1000.0])
		parts.sort()
		if parts.size() > 0:
			line += "\n" + ", ".join(parts)
	return line
