class_name StoryChronicleBuffer
extends RefCounted

# PERFORMANCE_UNTHROTTLED #93 — buffer chronicle appends; flush on cadence/save.

static var _pending: Array[Dictionary] = []
static var _flush_fn: Callable


static func reset_for_test() -> void:
	_pending.clear()
	_flush_fn = Callable()


static func bind(flush_callable: Callable) -> void:
	_flush_fn = flush_callable


static func append(entry: Dictionary) -> void:
	_pending.append(entry)


static func pending_count() -> int:
	return _pending.size()


static func flush() -> int:
	if _pending.is_empty():
		return 0
	if not _flush_fn.is_valid():
		_pending.clear()
		return 0
	var n: int = _pending.size()
	for e in _pending:
		_flush_fn.call(e)
	_pending.clear()
	return n
