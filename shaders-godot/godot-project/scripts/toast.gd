class_name Toast
extends PanelContainer

# The one toast component (messaging pass).
#
# There were four separate hand-built toast presenters in main.gd —
# notification, feed, guardian and photo — each constructing its own
# PanelContainer and StyleBoxFlat, each with slightly different colours,
# padding and dwell. ~1,289 lines of notification/toast/popup code lived in
# main.gd across ~25 functions.
#
# This is the single implementation. What the best of the four was missing,
# and what a message component actually needs:
#
#   * **Severity variants.** A critical low-oxygen warning rendered in the
#     same blue as "photo saved". Level now drives the accent.
#   * **Dismiss on click.** There was no way to get rid of one early.
#   * **Pause on hover.** The old dwell ran regardless, so a toast could fade
#     while you were still reading it.
#   * **Dwell that scales with length.** A fixed 4.2 s gave a six-word toast
#     the same time as a two-line one.
#   * **An optional action.** Messages that suggest something ("aeration
#     might help") should be actionable from the toast.
#   * **Honest height.** Stacking assumed a fixed 74 px per toast, so a
#     two-line body overlapped its neighbour. Toasts now report their real
#     height and the stack reads it.

signal dismissed(toast: Toast)

enum Level { INFO, GOOD, WARN, CRITICAL }

# Accent per level. The border and the leading rule take this; the body
# stays neutral so text contrast never depends on severity.
const LEVEL_ACCENT: Dictionary = {
	Level.INFO: Color(0.42, 0.60, 0.82, 0.85),
	Level.GOOD: Color(0.42, 0.78, 0.55, 0.85),
	Level.WARN: Color(0.90, 0.68, 0.32, 0.90),
	Level.CRITICAL: Color(0.92, 0.40, 0.38, 0.95),
}

const BG: Color = Color(0.09, 0.12, 0.19, 0.96)

# Reading time. Roughly 12 characters per second is a comfortable skim rate;
# clamped so nothing flashes past or overstays.
const DWELL_MIN: float = 3.0
const DWELL_MAX: float = 9.0
const CHARS_PER_SECOND: float = 12.0

const ENTER_S: float = 0.28
const EXIT_S: float = 0.5

var level: int = Level.INFO
var dwell: float = DWELL_MIN

var _remaining: float = 0.0
var _hovered: bool = false
var _dismissing: bool = false
var _action: Callable = Callable()
# Kept so callers can stream text into a live toast (the guardian recap does)
# without walking the node tree by assumed child index.
var _body_label: Label = null


# Build a toast. `cfg` keys, all optional except body:
#   title, body, icon, level, action_label, action (Callable), dwell
static func create(cfg: Dictionary) -> Toast:
	var t := Toast.new()
	t._configure(cfg)
	return t


static func dwell_for(text: String) -> float:
	return clampf(float(text.length()) / CHARS_PER_SECOND, DWELL_MIN, DWELL_MAX)


func _configure(cfg: Dictionary) -> void:
	level = int(cfg.get("level", Level.INFO))
	var title: String = String(cfg.get("title", ""))
	var body: String = String(cfg.get("body", ""))
	var icon: String = String(cfg.get("icon", ""))
	_action = cfg.get("action", Callable())
	dwell = float(cfg.get("dwell", dwell_for(title + body)))
	# A critical message should not vanish quickly.
	if level == Level.CRITICAL:
		dwell = maxf(dwell, 6.0)
	_remaining = dwell

	custom_minimum_size = Vector2(PanelTheme.TOAST_STACK_W - 8.0, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	modulate.a = 0.0
	scale = Vector2(0.96, 0.96)

	var accent: Color = LEVEL_ACCENT.get(level, LEVEL_ACCENT[Level.INFO])
	var style := StyleBoxFlat.new()
	style.bg_color = BG
	style.border_color = accent
	style.set_border_width_all(1)
	# A thicker leading edge in the accent colour reads as severity at a
	# glance without tinting the text.
	style.border_width_left = 3
	style.set_corner_radius_all(10)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	add_theme_stylebox_override("panel", style)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vb)

	if not title.is_empty():
		var title_lbl := Label.new()
		title_lbl.text = ("%s %s" % [icon, title]).strip_edges()
		title_lbl.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
		title_lbl.add_theme_font_size_override("font_size", 12)
		title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(title_lbl)

	if not body.is_empty():
		var body_lbl := Label.new()
		body_lbl.text = body
		body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body_lbl.add_theme_color_override("font_color", Color(0.80, 0.88, 0.96, 0.95))
		body_lbl.add_theme_font_size_override("font_size", 10)
		body_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(body_lbl)
		_body_label = body_lbl

	var action_label: String = String(cfg.get("action_label", ""))
	if not action_label.is_empty() and _action.is_valid():
		var btn := Button.new()
		btn.text = action_label
		btn.add_theme_font_size_override("font_size", 10)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_action)
		vb.add_child(btn)

	mouse_entered.connect(func(): _hovered = true)
	mouse_exited.connect(func(): _hovered = false)


func _ready() -> void:
	set_process(true)
	# Shrink to content. A PanelContainer parented to a plain Control keeps
	# whatever rect it was given, so without this a toast filled its whole
	# layer — the old code hid the problem behind a fixed 64 px height, which
	# in turn is why a wrapping body used to overlap its neighbour.
	# ORDER AND TIMING BOTH MATTER. The body label autowraps, so its minimum
	# height depends on its width; measured before the width is known it
	# reports one-character-per-line and the toast renders ~700 px tall.
	#
	# Pinning the width is necessary but NOT sufficient — at _ready the
	# layout has not run, so the label has not re-wrapped yet. Waiting a
	# frame before shrinking is what actually fixes it. The first version
	# only looked right because ToastStack.relayout re-hugged it two frames
	# later; any toast that never got relayouted (a trimmed one, which is
	# skipped while dismissing) stayed stretched the whole way out.
	custom_minimum_size.x = PanelTheme.TOAST_STACK_W - 8.0
	size.x = custom_minimum_size.x
	_hug_content()
	var tw := create_tween()
	tw.set_parallel(true)
	position.x = PanelTheme.TOAST_STACK_W
	tw.tween_property(self, "modulate:a", 1.0, ENTER_S) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, ENTER_S) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position:x", 0.0, ENTER_S + 0.04) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if _dismissing:
		return
	# Hovering holds the toast open — you should never lose a message you
	# are actively reading.
	if _hovered:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		dismiss()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		dismiss()
		accept_event()


func _on_action() -> void:
	if _action.is_valid():
		_action.call()
	dismiss()


func dismiss() -> void:
	if _dismissing:
		return
	_dismissing = true
	set_process(false)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, EXIT_S) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "position:x", 28.0, EXIT_S) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.set_parallel(false)
	tw.tween_callback(func() -> void:
		dismissed.emit(self)
		queue_free())


func is_dismissing() -> bool:
	return _dismissing


# Map the project's severity strings onto a level.
static func level_for_severity(severity: String, kind: String = "") -> int:
	match severity:
		"critical":
			return Level.CRITICAL
		"important":
			return Level.WARN
		_:
			# A few kinds are positive news rather than neutral information.
			if kind in ["milestone", "discovery", "population"]:
				return Level.GOOD
			return Level.INFO


# The body label, for callers that stream text into a live toast. Returns
# null when the toast has no body.
#
# This replaces a tree-walk that looked for "the Label at child index 1" —
# which happened to work only because every toast had a title above it. A
# titleless toast, or one with an action button, would have silently found
# the wrong node or nothing at all.
func body_label() -> Label:
	return _body_label if is_instance_valid(_body_label) else null


# Extend the dwell — used when a toast's text grows while it is on screen.
func hold(extra_seconds: float) -> void:
	_remaining = maxf(_remaining, minf(extra_seconds, DWELL_MAX))


# Shrink to fit, once the layout has had a frame to wrap the body text.
func _hug_content() -> void:
	var tree: SceneTree = get_tree()
	if tree != null:
		await tree.process_frame
	if not is_instance_valid(self):
		return
	custom_minimum_size.x = PanelTheme.TOAST_STACK_W - 8.0
	size.x = custom_minimum_size.x
	reset_size()
