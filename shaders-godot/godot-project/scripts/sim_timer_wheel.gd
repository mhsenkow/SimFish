class_name SimTimerWheel
extends RefCounted

# PERFORMANCE_UNTHROTTLED #63 — bucketed timer wheel (replaces linear SimCadence scan).

const WHEEL_SLOTS: int = 256
const MIN_DELAY_S: float = 0.05

static var _slots: Array = []
static var _accum_s: float = 0.0
static var _cursor: int = 0


static func reset_for_test() -> void:
	_slots.clear()
	for i in WHEEL_SLOTS:
		_slots.append([])
	_accum_s = 0.0
	_cursor = 0


static func _ensure() -> void:
	if _slots.is_empty():
		reset_for_test()


static func schedule(delay_s: float, fn: Callable, stagger_s: float = 0.0) -> void:
	_ensure()
	var total: float = maxf(delay_s, MIN_DELAY_S) + maxf(stagger_s, 0.0)
	var ticks: int = maxi(1, int(round(total / MIN_DELAY_S)))
	var slot: int = (_cursor + ticks) % WHEEL_SLOTS
	(_slots[slot] as Array).append({"fn": fn, "period_ticks": ticks, "stagger": stagger_s})


static func tick(dt: float) -> void:
	if dt <= 0.0:
		return
	_ensure()
	_accum_s += dt
	while _accum_s >= MIN_DELAY_S:
		_accum_s -= MIN_DELAY_S
		_cursor = (_cursor + 1) % WHEEL_SLOTS
		var bucket: Array = _slots[_cursor] as Array
		if bucket.is_empty():
			continue
		var carry: Array = []
		for entry in bucket:
			if not (entry is Dictionary):
				continue
			var cb: Callable = entry.get("fn") as Callable
			if cb.is_valid():
				cb.call(MIN_DELAY_S)
			var period: int = int(entry.get("period_ticks", 1))
			if period > 1:
				var next_slot: int = (_cursor + period) % WHEEL_SLOTS
				(_slots[next_slot] as Array).append(entry)
		bucket.clear()
		for e in carry:
			bucket.append(e)
