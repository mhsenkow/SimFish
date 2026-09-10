class_name PerfGovernor
extends RefCounted

# PERFORMANCE_REALTIME #2, #97, #98 — frame budget + subsystem attribution.
# Rolling p95 frame time → budget_pressure 0..1 for MindLOD; µs scopes for the perf HUD.

const FRAME_RING: int = 60
# Fallback budget when nothing has capped the frame rate: 60 fps.
const TARGET_FRAME_MS: float = 16.6
const SPIKE_MS: float = 28.0
# A spike is a frame that overruns the budget by this much.
const SPIKE_RATIO: float = SPIKE_MS / TARGET_FRAME_MS

# Live frame budget. This USED to be the 16.6 ms constant, which quietly broke
# every capped-frame-rate device: mobile defaults to fps_cap = 30, so a
# perfectly healthy 33 ms frame read as a 100% budget overrun. budget_pressure
# pinned at 1.0 forever, which meant MindLOD demoted every fish to its lowest
# cognition tier and the adaptive scaler ratcheted shader cost to maximum —
# on hardware that was hitting its target exactly. The budget now follows
# Engine.max_fps.
static var target_frame_ms: float = TARGET_FRAME_MS
static var spike_ms: float = SPIKE_MS
static var _target_cap_seen: int = -1

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

# record_frame() runs on literally every rendered frame, so it must not
# allocate. _sort_scratch is a single reused buffer for the p95 percentile;
# the percentile itself only needs recomputing every PRESSURE_STRIDE frames
# (budget_pressure feeds MindLOD tiers and the adaptive-resolution ladder,
# both of which move on ~1 s timescales), with an immediate escalation path so
# a real spike is never smoothed away.
const PRESSURE_STRIDE: int = 6
const ALLOC_STRIDE: int = 15
static var _sort_scratch: PackedFloat32Array = PackedFloat32Array()
static var _stride_tick: int = 0


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


# Re-read the engine frame cap and recompute the budget. Cheap (one int
# compare in the common case), called from record_frame so a mid-session
# change in Settings -> Performance takes effect immediately.
static func refresh_target() -> void:
	var cap: int = Engine.max_fps
	if cap == _target_cap_seen:
		return
	_target_cap_seen = cap
	if cap > 0:
		# Never claim a budget looser than 60 fps' worth of slack when the cap
		# is very low; a 15 fps cap should still flag a 200 ms hitch.
		target_frame_ms = clampf(1000.0 / float(cap), TARGET_FRAME_MS, 50.0)
	else:
		target_frame_ms = TARGET_FRAME_MS
	spike_ms = target_frame_ms * SPIKE_RATIO


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
	_sort_scratch = PackedFloat32Array()
	_stride_tick = 0
	target_frame_ms = TARGET_FRAME_MS
	spike_ms = SPIKE_MS
	_target_cap_seen = -1


static func record_frame(dt_sec: float) -> void:
	var ms: float = dt_sec * 1000.0
	last_frame_ms = ms
	if _frame_ring.size() < FRAME_RING:
		_frame_ring.resize(FRAME_RING)
	_frame_ring[_frame_head] = ms
	_frame_head = (_frame_head + 1) % FRAME_RING
	_frame_count = mini(_frame_count + 1, FRAME_RING)
	_stride_tick += 1
	refresh_target()
	var spiking: bool = ms >= spike_ms
	if spiking or _stride_tick % PRESSURE_STRIDE == 0 or _frame_count <= PRESSURE_STRIDE:
		budget_pressure = _pressure_from_ring()
	else:
		# Between percentile refreshes, let a single bad frame push pressure up
		# straight away — never down. Recovery waits for the real p95.
		budget_pressure = maxf(budget_pressure, _pressure_from_ms(ms))
	if spiking:
		last_spike_subsystem = _top_scope_name()
	_scope_active.clear()
	# get_static_memory_usage() is a debug-HUD readout, not a control signal.
	# Polling it every frame cost more than the number was worth.
	if _stride_tick % ALLOC_STRIDE == 0 or _alloc_baseline < 0:
		var prev_alloc: int = _alloc_last_frame
		_alloc_last_frame = OS.get_static_memory_usage()
		if _alloc_baseline < 0:
			_alloc_baseline = _alloc_last_frame
		elif _alloc_last_frame > prev_alloc + 4096:
			_alloc_scope_tag = _top_scope_name()


static func _pressure_from_ms(ms: float) -> float:
	return clampf((ms - target_frame_ms * 0.85) / (target_frame_ms * 1.1), 0.0, 1.0)


static func _pressure_from_ring() -> float:
	if _frame_count <= 0:
		return 0.0
	# Reused scratch — resize() on a PackedArray that is already the right
	# length is a no-op, so the steady state is allocation-free.
	if _sort_scratch.size() != _frame_count:
		_sort_scratch.resize(_frame_count)
	for i in _frame_count:
		_sort_scratch[i] = _frame_ring[i]
	_sort_scratch.sort()
	var p95_idx: int = clampi(int(ceil(float(_frame_count) * 0.95)) - 1, 0, _frame_count - 1)
	return _pressure_from_ms(_sort_scratch[p95_idx])


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
	if last_spike_subsystem != "" and last_frame_ms >= spike_ms:
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
