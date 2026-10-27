extends SceneTree

const QueueScript = preload("res://scripts/intro_dialog_queue.gd")
const Guardian = preload("res://scripts/guardian_mind_onboarding.gd")
const Onboarding = preload("res://scripts/onboarding_runtime.gd")

class Host extends Control:
	var dialogs: Node
	var _sim: Node = null
	func queue_intro_dialog(key: String, factory: Callable) -> void:
		dialogs.enqueue(key, factory)
	func _intro_dialog_active() -> bool:
		return dialogs.has_active()

var _opened: Array[String] = []
var _blocked: bool = true
var _closed: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var t := TestSupport.Suite.new("intro_dialog_queue")
	root.size = Vector2i(960, 720)
	var host := Host.new()
	root.add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var queue := QueueScript.new()
	host.add_child(queue)
	host.dialogs = queue
	queue.set_process(false)
	queue.blocked = func() -> bool: return _blocked
	queue.enqueue("welcome", _make_dialog.bind(host, "welcome"))
	queue.enqueue("welcome", _make_dialog.bind(host, "duplicate"))
	queue.enqueue("guardian", _make_dialog.bind(host, "guardian"))
	queue._process(0.0)
	t.check(_opened.is_empty(), "an existing tour blocks startup prompts")
	_blocked = false
	queue._process(0.0)
	await process_frame
	await process_frame
	t.equals(_opened.size(), 1, "only one dialog factory runs")
	queue._process(0.0)
	t.equals(_opened.size(), 1, "active prompt prevents overlap")
	var first: Control = queue._active
	var modal: Node = first.find_child("GuardianMindOnboarding", true, false)
	var button: Button = modal.get("_accept_btn")
	t.check(root.gui_get_focus_owner() != null and first.is_ancestor_of(root.gui_get_focus_owner()), "focus belongs to visible dialog")
	t.check(root.get_visible_rect().encloses(button.get_global_rect()),
		"Guardian action remains inside the viewport")
	# Exercise actual GUI hit testing: the scrim must not intercept its own button.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = button.get_global_rect().get_center()
	click.global_position = click.position
	click.pressed = true
	root.push_input(click, true)
	click = click.duplicate()
	click.pressed = false
	root.push_input(click, true)
	t.equals(_closed, 1, "one click activates the visible Guardian exactly once")
	queue._process(0.0)
	t.equals(_opened.size(), 1, "queued-free modal still owns its dismissal frame")
	await process_frame
	await process_frame
	queue._process(0.0)
	t.equals(_opened.size(), 1, "one frame separates prompts")
	queue._process(0.0)
	t.equals(_opened, ["welcome", "guardian"], "FIFO order and duplicate suppression")
	queue._active.queue_free()
	await process_frame
	await process_frame
	queue._process(0.0)
	# Real onboarding cards must queue, not replace each other in one frame.
	var onboarding := Onboarding.new()
	host.add_child(onboarding)
	onboarding.setup(host)
	onboarding.set_process(false)
	onboarding._show_card("First card", "First body")
	onboarding._show_card("Second card", "Second body")
	queue._process(0.0)
	var card: Control = onboarding._card_overlay
	t.check(is_instance_valid(card), "first tour summary appears")
	onboarding.dismiss_card()
	queue._process(0.0)
	t.check(onboarding._card_overlay == null, "second card does not steal dismissal click")
	await process_frame
	await process_frame
	queue._process(0.0)
	queue._process(0.0)
	t.check(is_instance_valid(onboarding._card_overlay), "second tour summary is retained")
	host.queue_free()
	await process_frame
	await process_frame
	quit(t.finish())


func _make_dialog(host: Control, key: String) -> Control:
	_opened.append(key)
	var layer := PanelTheme.make_modal_root(host, PanelTheme.Z_GUARDIAN)
	var overlay: Control = layer["overlay"]
	var modal := Guardian.open_in(overlay, Guardian.Mode.NORTH_STAR)
	modal.closed.connect(func(_accepted: bool) -> void:
		_closed += 1
		overlay.queue_free())
	return overlay
