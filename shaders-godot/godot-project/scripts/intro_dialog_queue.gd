# Scene-owned FIFO for first-run dialogs. Factories create UI only when it
# becomes active, so hidden prompts cannot steal focus or intercept clicks.
extends Node

var blocked: Callable
var _pending: Array[Dictionary] = []
var _keys: Dictionary = {}
var _active: Control = null
var _active_key: String = ""


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func enqueue(key: String, factory: Callable) -> void:
	if _keys.has(key):
		return
	_keys[key] = true
	_pending.append({"key": key, "factory": factory})


func has_active() -> bool:
	# Keep input blocked until the queued-free dialog actually leaves the tree.
	return is_instance_valid(_active) or _active_key != ""


func _process(_dt: float) -> void:
	if is_instance_valid(_active):
		return
	if _active_key != "":
		_keys.erase(_active_key)
		_active_key = ""
		# Never open the next dialog during the dismissal event/frame.
		return
	if _pending.is_empty() or (blocked.is_valid() and bool(blocked.call())):
		return
	var entry: Dictionary = _pending.pop_front()
	var factory: Callable = entry["factory"]
	_active_key = entry["key"]
	if factory.is_valid():
		_active = factory.call() as Control
