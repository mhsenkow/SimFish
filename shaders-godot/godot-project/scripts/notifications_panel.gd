extends PanelContainer
class_name NotificationsPanel

# The notification centre, carved out of main.gd (messaging consolidation).
#
# ~407 lines of notification-panel code lived in main.gd across 18 functions,
# tangled together with the toast lane, the badge and the store. The split
# here is deliberate:
#
#   * main keeps the STORE — pushing, capping, dedup, the unread badge. That
#     is where messages arrive from, and it stays put.
#   * this panel owns PRESENTATION and its own filter/sort state.
#
# It is handed the array on refresh rather than reaching back into main for
# it, so the panel can be exercised on its own (smoke_notifications_panel).
#
# Follows the panel contract enforced by smoke_panel_contract.gd.

signal cleared

const FILTER_ALL := "all"

enum Sort { NEWEST, OLDEST, SEVERITY }

const SEV_INFO := "info"
const SEV_IMPORTANT := "important"
const SEV_CRITICAL := "critical"

var main_ref: Node = null

var _list: VBoxContainer = null
var _kind_opt: OptionButton = null
var _sev_opt: OptionButton = null
var _sort_opt: OptionButton = null

var _filter_kind: String = FILTER_ALL
var _filter_severity: String = FILTER_ALL
var _sort: int = Sort.NEWEST

# Last array handed to refresh(), so a filter change can re-render without
# the caller having to push it again.
var _source: Array = []


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(PanelTheme.PANEL_MIN_W, 360)
	z_index = 110
	PanelTheme.apply_panel_chrome(self)
	_build_ui()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root)

	root.add_child(PanelTheme.make_title(tr("Notifications")))
	root.add_child(PanelTheme.make_rule())

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	root.add_child(controls)

	_kind_opt = OptionButton.new()
	for i in range(CommsInbox.KIND_FILTER_ENTRIES.size()):
		_kind_opt.add_item(String(CommsInbox.KIND_FILTER_ENTRIES[i].get("label", "Kind")), i)
	_kind_opt.item_selected.connect(_on_kind_selected)
	controls.add_child(_kind_opt)

	_sev_opt = OptionButton.new()
	_sev_opt.add_item(tr("Severity: All"), 0)
	_sev_opt.add_item(tr("Severity: Info"), 1)
	_sev_opt.add_item(tr("Severity: Important"), 2)
	_sev_opt.add_item(tr("Severity: Critical"), 3)
	_sev_opt.item_selected.connect(_on_severity_selected)
	controls.add_child(_sev_opt)

	_sort_opt = OptionButton.new()
	_sort_opt.add_item(tr("Sort: Newest"), Sort.NEWEST)
	_sort_opt.add_item(tr("Sort: Oldest"), Sort.OLDEST)
	_sort_opt.add_item(tr("Sort: Severity"), Sort.SEVERITY)
	_sort_opt.item_selected.connect(_on_sort_selected)
	controls.add_child(_sort_opt)

	var clear_btn := PanelTheme.make_secondary_button(tr("Clear all"))
	clear_btn.pressed.connect(func(): cleared.emit())
	controls.add_child(clear_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	root.add_child(PanelTheme.make_panel_footer(_request_close))


# --- Filtering + sorting (pure, so the smoke can check them directly) ------

static func severity_rank(sev: String) -> int:
	match sev:
		SEV_CRITICAL: return 2
		SEV_IMPORTANT: return 1
		_: return 0


# Rows that survive the current filters, in the current sort order.
func visible_rows(source: Array) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for n in source:
		if not (n is Dictionary):
			continue
		var d: Dictionary = n
		if _filter_kind != FILTER_ALL and String(d.get("kind", "system")) != _filter_kind:
			continue
		if _filter_severity != FILTER_ALL \
				and String(d.get("severity", SEV_INFO)) != _filter_severity:
			continue
		rows.append(d)
	var mode: int = _sort
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if mode == Sort.OLDEST:
			return int(a.get("ts", 0)) < int(b.get("ts", 0))
		if mode == Sort.SEVERITY:
			var ar: int = severity_rank(String(a.get("severity", SEV_INFO)))
			var br: int = severity_rank(String(b.get("severity", SEV_INFO)))
			if ar == br:
				return int(a.get("ts", 0)) > int(b.get("ts", 0))
			return ar > br
		return int(a.get("ts", 0)) > int(b.get("ts", 0)))
	return rows


static func format_age(unix_ts: int, now_unix: int = -1) -> String:
	var now: int = now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	var delta: int = maxi(0, now - unix_ts)
	if delta < 60:
		return "%ds ago" % delta
	if delta < 3600:
		return "%dm ago" % int(delta / 60.0)
	var h: int = int(delta / 3600.0)
	if h < 24:
		return "%dh ago" % h
	return "%dd ago" % int(delta / 86400.0)


# --- Rendering -------------------------------------------------------------

func refresh(source: Array) -> void:
	_source = source
	if _list == null:
		return
	for c in _list.get_children():
		c.queue_free()
	var rows: Array[Dictionary] = visible_rows(source)
	if rows.is_empty():
		var empty := Label.new()
		# Distinguish "nothing has happened" from "your filter hides it" —
		# the same message for both is how a filter gets left on by accident.
		empty.text = tr("No notifications yet.") if source.is_empty() \
			else tr("No notifications match this filter.")
		empty.add_theme_color_override("font_color", Color(0.70, 0.76, 0.86, 0.9))
		_list.add_child(empty)
		return
	for n in rows:
		_list.add_child(build_row(n))


func build_row(n: Dictionary) -> Control:
	var row := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.18, 0.78)
	# A severity stripe, matching the toast accents so a message looks the
	# same urgency wherever it is read.
	var lvl: int = Toast.level_for_severity(
		String(n.get("severity", SEV_INFO)), String(n.get("kind", "")))
	style.border_color = Toast.LEVEL_ACCENT.get(lvl, Toast.LEVEL_ACCENT[Toast.Level.INFO])
	style.border_width_left = 3
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_top = 8
	style.content_margin_right = 10
	style.content_margin_bottom = 8
	row.add_theme_stylebox_override("panel", style)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	row.add_child(hb)

	var icon := Label.new()
	icon.text = CommsInbox.kind_icon(String(n.get("kind", "system")))
	icon.custom_minimum_size = Vector2(20, 0)
	hb.add_child(icon)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)

	var title := Label.new()
	# display_title carries the repeat count for coalesced rows — three
	# collapses in a row is one entry reading "(x3)", not three entries
	# (VISUAL_DIRECTIONS #19).
	title.text = "%s · %s" % [CommsInbox.display_title(n),
		format_age(int(n.get("ts", 0)))]
	title.add_theme_color_override("font_color", Color(0.92, 0.95, 0.99))
	title.add_theme_font_size_override("font_size", 12)
	vb.add_child(title)

	var body := Label.new()
	body.text = String(n.get("body", ""))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", Color(0.80, 0.86, 0.94, 0.95))
	body.add_theme_font_size_override("font_size", 11)
	vb.add_child(body)
	return row


# --- Controls --------------------------------------------------------------

func _on_kind_selected(idx: int) -> void:
	_filter_kind = FILTER_ALL
	if idx >= 0 and idx < CommsInbox.KIND_FILTER_ENTRIES.size():
		_filter_kind = String(CommsInbox.KIND_FILTER_ENTRIES[idx].get("id", FILTER_ALL))
	refresh(_source)


func _on_severity_selected(idx: int) -> void:
	match idx:
		1: _filter_severity = SEV_INFO
		2: _filter_severity = SEV_IMPORTANT
		3: _filter_severity = SEV_CRITICAL
		_: _filter_severity = FILTER_ALL
	refresh(_source)


func _on_sort_selected(idx: int) -> void:
	_sort = clampi(idx, Sort.NEWEST, Sort.SEVERITY)
	refresh(_source)


func _request_close() -> void:
	if main_ref != null and is_instance_valid(main_ref) \
			and main_ref.has_method("close_notifications_panel"):
		main_ref.call("close_notifications_panel")
	else:
		visible = false
