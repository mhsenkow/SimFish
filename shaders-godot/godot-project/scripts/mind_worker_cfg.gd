extends RefCounted

# Thread-safe TankConfig snapshot for mind worker batches. No scene-tree reads.
# MindBrainPool fills `snapshot` on the worker thread at batch start; cognition
# modules read via read_bool/read() when not on the main thread.

static var snapshot: Dictionary = {}
static var active: bool = false


static func begin_batch(cfg: Dictionary) -> void:
	snapshot = cfg.duplicate(true)
	active = true


static func end_batch() -> void:
	active = false
	snapshot.clear()


static func read(key: String, default: Variant = null) -> Variant:
	if not active:
		return default
	return snapshot.get(key, default)


static func read_bool(key: String, default: bool) -> bool:
	var v: Variant = read(key, default)
	if v is bool:
		return v
	if v == null:
		return default
	return default if v == false else true
