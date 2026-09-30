extends RefCounted

# Thread-safe TankConfig snapshot for mind worker batches. No scene-tree reads.
#
# Contract (this used to be a shared mutable dict that the worker filled at
# batch start and CLEARED at batch end — when two batches overlapped, one
# thread's clear() freed the storage another was reading: signal 11 in
# Dictionary::get, surfacing first as a bogus "propagate_notification() from
# the wrong thread" error off the corrupted pointer):
#   * publish() runs on the MAIN thread only, and only while no worker batch is
#     in flight (MindBrainPool.flush_tick joins the previous batch first).
#   * The published dict is a deep copy made read-only; it is replaced
#     wholesale, never mutated or cleared, so a worker that grabbed a reference
#     keeps a valid immutable snapshot for its whole batch.
#   * Workers only read. Main-thread callers must read live TankConfig instead.

static var _snapshot: Dictionary = {}
static var active: bool = false


static func publish(cfg: Dictionary) -> void:
	assert(Thread.is_main_thread(), "MindWorkerCfg.publish is main-thread only")
	var snap: Dictionary = cfg.duplicate(true)
	snap.make_read_only()
	_snapshot = snap
	active = true


static func snapshot() -> Dictionary:
	return _snapshot


static func read(key: String, default: Variant = null) -> Variant:
	if not active:
		return default
	# Local reference pins this batch's snapshot even if a later publish swaps it.
	var snap: Dictionary = _snapshot
	return snap.get(key, default)


static func read_bool(key: String, default: bool) -> bool:
	var v: Variant = read(key, default)
	if v is bool:
		return v
	if v == null:
		return default
	return default if v == false else true
