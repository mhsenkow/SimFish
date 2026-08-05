# Residents panel.
#
# A live, scrollable roster of every followable individual in the tank (fish,
# shrimp, snails, clams). Tap a row to follow it in the PiP portal; ★ to
# favorite (persisted in the save). A "Now following" bar mirrors main's follow
# state and drives prev/next cycling + the cycle scope. Non-modal and does NOT
# pause the sim — you watch creatures swim while browsing.
#
# Owned by main.gd; talks back through duck-typed calls (follow_creature /
# cycle_follow / set_cycle_scope / clear_follow) and reads the live roster from
# main._sim (SimDriver: living_creatures / is_favorite / toggle_favorite, plus
# the creature_added/removed/favorites_changed signals).

extends PanelContainer
class_name ResidentsPanel

const EDGE_FADE_SHADER := preload("res://shaders/list_edge_fade.gdshader")
const CreatureNaming = preload("res://scripts/creature_naming.gd")
const FishJournal = preload("res://scripts/fish_journal.gd")
const MindConversation = preload("res://scripts/mind_conversation.gd")

# List type filter.
enum Filter { ALL, FISH, SHRIMP, SNAIL, CLAM, FAV }
# Sort key.
enum Sort { NAME, AGE, SPECIES, ATTENTION, NEWEST }

var main_ref: Node = null
var _sim: Node = null

var _list_vbox: VBoxContainer = null
var _count_lbl: Label = null
var _search: LineEdit = null
var _sort_option: OptionButton = null
var _now_lbl: Label = null
var _scope_option: OptionButton = null
var _filter_buttons: Dictionary = {}   # Filter -> Button
var _lock_btn: Button = null
var _cinema_btn: Button = null

var _filter: int = Filter.ALL
var _sort: int = Sort.NAME
var _query: String = ""

# instance_id -> card Control. Cards carry their creature + sub-widgets in meta.
var _card_by_id: Dictionary = {}
var _highlight_card: Control = null
var _journal_layer: Control = null
var _rebuild_queued: bool = false
var _stat_accum: float = 0.0
var _ui_ticker_bound: bool = false


func _ready() -> void:
	set_process_unhandled_input(true)
	PanelTheme.apply_panel_chrome(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(320, 0)
	_build_ui()
	visible = false
	set_process(false)


func _build_ui() -> void:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(outer)

	# --- Title + live count ---
	var title_row := HBoxContainer.new()
	outer.add_child(title_row)
	title_row.add_child(PanelTheme.make_title("Residents"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(sp)
	_count_lbl = Label.new()
	PanelTheme.as_mono(_count_lbl, PanelTheme.SIZE_CAPTION)
	_count_lbl.add_theme_color_override("font_color", PanelTheme.DIM_FG)
	_count_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(_count_lbl)
	outer.add_child(PanelTheme.make_rule())

	# --- Now following bar ---
	_now_lbl = Label.new()
	_now_lbl.text = "Tap a creature to follow"
	PanelTheme.as_serif(_now_lbl, PanelTheme.SIZE_BODY)
	_now_lbl.add_theme_color_override("font_color", Color8(255, 215, 80))
	_now_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	_now_lbl.clip_text = true
	outer.add_child(_now_lbl)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	outer.add_child(nav)
	var prev_btn := PanelTheme.make_secondary_button("◀")
	prev_btn.tooltip_text = "Previous creature (←)"
	prev_btn.pressed.connect(func(): _call_main("cycle_follow", [-1]))
	nav.add_child(prev_btn)
	var next_btn := PanelTheme.make_secondary_button("▶")
	next_btn.tooltip_text = "Next creature (→)"
	next_btn.pressed.connect(func(): _call_main("cycle_follow", [1]))
	nav.add_child(next_btn)
	var cycle_lbl := Label.new()
	cycle_lbl.text = "Cycle:"
	cycle_lbl.add_theme_color_override("font_color", PanelTheme.LABEL_FG)
	cycle_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nav.add_child(cycle_lbl)
	_scope_option = OptionButton.new()
	_scope_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scope_option.add_item("All", 0)
	_scope_option.add_item("Favorites", 1)
	_scope_option.add_item("Species", 2)
	_scope_option.item_selected.connect(func(i): _call_main("set_cycle_scope", [i]))
	nav.add_child(_scope_option)
	var stop_btn := PanelTheme.make_secondary_button("✕")
	stop_btn.tooltip_text = "Stop following (Esc)"
	stop_btn.pressed.connect(func(): _call_main("clear_follow", []))
	nav.add_child(stop_btn)

	# Tools — view/camera row, then per-creature actions row.
	var tools1 := HBoxContainer.new()
	tools1.add_theme_constant_override("separation", 6)
	outer.add_child(tools1)
	_lock_btn = PanelTheme.make_secondary_button("⤢ Lead")
	_lock_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lock_btn.tooltip_text = "Cinematic framing: Lead (camera leads + lets it roam) vs Lock (centered)"
	_lock_btn.pressed.connect(func():
		_call_main("toggle_follow_lock", [])
		_sync_tool_buttons())
	tools1.add_child(_lock_btn)
	_cinema_btn = PanelTheme.make_secondary_button("🎬 Cinema")
	_cinema_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cinema_btn.tooltip_text = "Auto-tour your creatures — advances every few seconds when idle"
	_cinema_btn.pressed.connect(func():
		_call_main("toggle_cinema_mode", [])
		_sync_tool_buttons())
	tools1.add_child(_cinema_btn)
	tools1.add_child(_tools_btn("🎲 Shuffle", "Follow a random creature in the current scope", "follow_random"))

	var tools2 := HBoxContainer.new()
	tools2.add_theme_constant_override("separation", 6)
	outer.add_child(tools2)
	tools2.add_child(_tools_btn("Species", "View the followed creature's species in the Library", "view_followed_in_library"))
	tools2.add_child(_tools_btn("Lineage", "View the followed creature's ancestry tree", "view_followed_lineage"))
	tools2.add_child(_tools_btn("Share", "Copy the followed creature's strain code to the clipboard", "share_followed_strain"))

	outer.add_child(PanelTheme.make_rule())

	# --- Search ---
	_search = LineEdit.new()
	_search.placeholder_text = "Search name or species…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(t):
		_query = String(t).strip_edges().to_lower()
		_queue_rebuild())
	outer.add_child(_search)

	# --- Type filter chips ---
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 4)
	outer.add_child(chips)
	_add_filter_chip(chips, Filter.ALL, "All")
	_add_filter_chip(chips, Filter.FISH, "🐟")
	_add_filter_chip(chips, Filter.SHRIMP, "🦐")
	_add_filter_chip(chips, Filter.SNAIL, "🐌")
	_add_filter_chip(chips, Filter.CLAM, "🦪")
	_add_filter_chip(chips, Filter.FAV, "★")

	# --- Sort ---
	var sort_row := HBoxContainer.new()
	sort_row.add_theme_constant_override("separation", 8)
	outer.add_child(sort_row)
	var sort_lbl := Label.new()
	sort_lbl.text = "Sort"
	sort_lbl.add_theme_color_override("font_color", PanelTheme.LABEL_FG)
	sort_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sort_row.add_child(sort_lbl)
	_sort_option = OptionButton.new()
	_sort_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sort_option.add_item("Name", Sort.NAME)
	_sort_option.add_item("Age", Sort.AGE)
	_sort_option.add_item("Species", Sort.SPECIES)
	_sort_option.add_item("Needs attention", Sort.ATTENTION)
	_sort_option.add_item("Newest", Sort.NEWEST)
	_sort_option.item_selected.connect(func(i):
		_sort = i
		_queue_rebuild())
	sort_row.add_child(_sort_option)

	# --- Scrollable list with edge fade ---
	var list_wrap := Control.new()
	list_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_wrap.clip_contents = true
	outer.add_child(list_wrap)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_wrap.add_child(scroll)

	_list_vbox = VBoxContainer.new()
	_list_vbox.add_theme_constant_override("separation", 4)
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_vbox)

	list_wrap.add_child(_make_edge_fade(true))
	list_wrap.add_child(_make_edge_fade(false))

	outer.add_child(PanelTheme.make_panel_footer(func(): _hide_panel()))


func _make_edge_fade(top: bool) -> ColorRect:
	var cr := ColorRect.new()
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cr.custom_minimum_size = Vector2(0, 22)
	if top:
		cr.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		cr.offset_bottom = 22
	else:
		cr.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		cr.offset_top = -22
	var mat := ShaderMaterial.new()
	mat.shader = EDGE_FADE_SHADER
	mat.set_shader_parameter("edge_color", PanelTheme.BG)
	mat.set_shader_parameter("flip", 0.0 if top else 1.0)
	cr.material = mat
	return cr


func _add_filter_chip(parent: Node, f: int, label: String) -> void:
	var b := PanelTheme.make_secondary_button(label)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func():
		_filter = f
		_sync_chip_state()
		_queue_rebuild())
	_filter_buttons[f] = b
	parent.add_child(b)


func _sync_chip_state() -> void:
	for f in _filter_buttons:
		var b: Button = _filter_buttons[f]
		b.modulate = Color(1, 1, 1, 1) if f == _filter else Color(0.7, 0.74, 0.82, 0.8)


func _tools_btn(label: String, tip: String, method: String) -> Button:
	var b := PanelTheme.make_secondary_button(label)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.tooltip_text = tip
	b.pressed.connect(func(): _call_main(method, []))
	return b


func _sync_tool_buttons() -> void:
	if main_ref == null:
		return
	if _lock_btn != null and main_ref.has_method("is_follow_lock"):
		_lock_btn.text = "🔒 Lock" if bool(main_ref.is_follow_lock()) else "⤢ Lead"
	if _cinema_btn != null and main_ref.has_method("is_cinema_active"):
		_cinema_btn.modulate = Color(0.5, 1.0, 0.6) if bool(main_ref.is_cinema_active()) else Color(1, 1, 1)


# Called by main when the panel becomes visible.
func sync_from_main() -> void:
	if main_ref == null:
		return
	var sim: Node = main_ref.get("_sim")
	if sim != _sim:
		_disconnect_sim()
		_sim = sim
		_connect_sim()
	if main_ref.has_signal("follow_target_changed") \
			and not main_ref.is_connected("follow_target_changed", _on_follow_changed):
		main_ref.connect("follow_target_changed", _on_follow_changed)
	# Reflect current cycle scope + follow target.
	if _scope_option != null and main_ref.has_method("get_cycle_scope"):
		_scope_option.select(int(main_ref.get_cycle_scope()))
	_sync_chip_state()
	_sync_tool_buttons()
	_rebuild_list()
	_update_now_following(main_ref.get("_follow_target"))
	_bind_ui_ticker(true)


func _bind_ui_ticker(on: bool) -> void:
	var ticker: Node = get_node_or_null("/root/UiTicker")
	if ticker == null:
		set_process(on and visible)
		return
	if on and visible and not _ui_ticker_bound:
		if not ticker.tick.is_connected(_on_ui_ticker):
			ticker.tick.connect(_on_ui_ticker)
		_ui_ticker_bound = true
		set_process(false)
	elif (not on or not visible) and _ui_ticker_bound:
		if ticker.tick.is_connected(_on_ui_ticker):
			ticker.tick.disconnect(_on_ui_ticker)
		_ui_ticker_bound = false


func _on_ui_ticker(delta: float) -> void:
	if not visible:
		return
	_stat_accum += delta
	if _stat_accum < 1.0:
		return
	_stat_accum = 0.0
	_refresh_card_stats()


func _refresh_card_stats() -> void:
	for id in _card_by_id:
		var card: Control = _card_by_id[id]
		if not is_instance_valid(card):
			continue
		var c: Variant = card.get_meta("creature")
		if c == null or not is_instance_valid(c):
			continue
		var sub: Label = card.get_meta("sub_lbl")
		if sub != null:
			sub.text = _sub_text(c)
		var star: Button = card.get_meta("star")
		if star != null:
			star.text = "★" if _is_favorite(c) else "☆"
		var pip: ColorRect = card.get_meta("pip", null)
		if pip != null:
			pip.color = _condition_color(c)


func _connect_sim() -> void:
	if _sim == null:
		return
	if _sim.has_signal("creature_added") and not _sim.is_connected("creature_added", _on_roster_changed):
		_sim.connect("creature_added", _on_roster_changed)
	if _sim.has_signal("creature_removed") and not _sim.is_connected("creature_removed", _on_roster_changed):
		_sim.connect("creature_removed", _on_roster_changed)
	if _sim.has_signal("favorites_changed") and not _sim.is_connected("favorites_changed", _on_favorites_changed):
		_sim.connect("favorites_changed", _on_favorites_changed)


func _disconnect_sim() -> void:
	if _sim == null or not is_instance_valid(_sim):
		return
	if _sim.is_connected("creature_added", _on_roster_changed):
		_sim.disconnect("creature_added", _on_roster_changed)
	if _sim.is_connected("creature_removed", _on_roster_changed):
		_sim.disconnect("creature_removed", _on_roster_changed)
	if _sim.is_connected("favorites_changed", _on_favorites_changed):
		_sim.disconnect("favorites_changed", _on_favorites_changed)


func _on_roster_changed(_c: Node = null) -> void:
	_queue_rebuild()


func _on_favorites_changed() -> void:
	# Favorites affect order + stars; cheapest correct path is a rebuild.
	_queue_rebuild()


func _on_follow_changed(node: Node) -> void:
	_update_now_following(node)


# Coalesce bursts (e.g. loading a tank spawns many creatures) into one rebuild.
func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	call_deferred("_rebuild_list")


func _rebuild_list() -> void:
	_rebuild_queued = false
	if _list_vbox == null:
		return
	for child in _list_vbox.get_children():
		child.queue_free()
	_card_by_id.clear()
	_highlight_card = null

	var roster: Array = _sorted_filtered()
	var fav_n: int = 0
	for c in roster:
		if _is_favorite(c):
			fav_n += 1

	if roster.is_empty():
		_list_vbox.add_child(_make_empty_state())
		if _count_lbl != null:
			_count_lbl.text = "0 residents"
		return

	# Group under "★ Favorites" / "All residents" headers when favorites sort to
	# the top (skipped for the flat worst-first "Needs attention" ordering).
	var grouped: bool = _sort != Sort.ATTENTION and fav_n > 0 and fav_n < roster.size()
	var fav_header := false
	var other_header := false
	for c in roster:
		if grouped:
			var fav := _is_favorite(c)
			if fav and not fav_header:
				_list_vbox.add_child(_make_section_divider("★ Favorites"))
				fav_header = true
			elif not fav and not other_header:
				_list_vbox.add_child(_make_section_divider("All residents"))
				other_header = true
		var card := _make_card(c)
		_list_vbox.add_child(card)
		_card_by_id[c.get_instance_id()] = card
	# Vertical focus neighbors so ↑/↓ navigate the cards (keyboard list nav).
	var cards: Array = _card_by_id.values()
	for i in cards.size():
		var cc: Control = cards[i]
		cc.focus_neighbor_top = (cards[i - 1] as Control).get_path() if i > 0 else cc.get_path()
		cc.focus_neighbor_bottom = (cards[i + 1] as Control).get_path() if i < cards.size() - 1 else cc.get_path()
	if _count_lbl != null:
		var total: int = roster.size()
		_count_lbl.text = "%d resident%s · %d ★" % [total, "" if total == 1 else "s", fav_n]
	# Re-apply the follow highlight to whichever card matches.
	if main_ref != null:
		_update_now_following(main_ref.get("_follow_target"))


func _sorted_filtered() -> Array:
	if _sim == null or not _sim.has_method("living_creatures"):
		return []
	var all: Array = _sim.living_creatures()
	var out: Array = []
	for c in all:
		if _passes_filter(c):
			out.append(c)
	# Favorites always float above non-favorites; within each group apply the sort.
	out.sort_custom(_compare_creatures)
	return out


func _passes_filter(c: Node) -> bool:
	if c == null or not is_instance_valid(c):
		return false
	match _filter:
		Filter.FISH:
			if not (c is Fish):
				return false
		Filter.SHRIMP:
			if not (c is Shrimp):
				return false
		Filter.SNAIL:
			if _type_of(c) != Filter.SNAIL:
				return false
		Filter.CLAM:
			if _type_of(c) != Filter.CLAM:
				return false
		Filter.FAV:
			if not _is_favorite(c):
				return false
	if _query != "":
		var hay: String = (_creature_name(c) + " " + _species_of(c)).to_lower()
		if not hay.contains(_query):
			return false
	return true


func _compare_creatures(a: Node, b: Node) -> bool:
	if _sort == Sort.ATTENTION:
		# Worst condition first, regardless of favorite status — surfaces the
		# starving / ailing creatures so they're easy to find and feed.
		var ca: float = _condition_score(a)
		var cb: float = _condition_score(b)
		if not is_equal_approx(ca, cb):
			return ca < cb
		return _creature_name(a).naturalnocasecmp_to(_creature_name(b)) < 0
	var fa: bool = _is_favorite(a)
	var fb: bool = _is_favorite(b)
	if fa != fb:
		return fa  # favorites first
	match _sort:
		Sort.AGE:
			return _age_of(a) > _age_of(b)  # oldest first
		Sort.NEWEST:
			return _age_of(a) < _age_of(b)  # youngest (recently added) first
		Sort.SPECIES:
			var sa: String = _species_of(a)
			var sb: String = _species_of(b)
			if sa != sb:
				return sa.naturalnocasecmp_to(sb) < 0
			return _creature_name(a).naturalnocasecmp_to(_creature_name(b)) < 0
		_:
			return _creature_name(a).naturalnocasecmp_to(_creature_name(b)) < 0


func _make_card(c: Node) -> Control:
	var card := Button.new()
	card.flat = true
	card.focus_mode = Control.FOCUS_ALL
	card.custom_minimum_size = Vector2(0, 46)
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color(0.18, 0.26, 0.36, 0.5)
	fs.border_color = PanelTheme.SECTION_FG
	fs.set_border_width_all(2)
	fs.set_corner_radius_all(6)
	card.add_theme_stylebox_override("focus", fs)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cref := c
	card.pressed.connect(func(): _on_row_clicked(cref))

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 6
	row.offset_right = -6
	card.add_child(row)

	# Color swatch with species glyph.
	var swatch := ColorRect.new()
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.color = _color_of(c)
	swatch.custom_minimum_size = Vector2(30, 30)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var glyph := Label.new()
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.text = _emoji_of(c)
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 16)
	swatch.add_child(glyph)
	row.add_child(swatch)

	# Name + sub-line.
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 0)
	var name_lbl := Label.new()
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.text = _card_name(c)
	name_lbl.clip_text = true
	PanelTheme.as_sans(name_lbl, PanelTheme.SIZE_BODY, true)
	name_lbl.add_theme_color_override("font_color", PanelTheme.LABEL_FG)
	col.add_child(name_lbl)
	var sub_lbl := Label.new()
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_lbl.text = _sub_text(c)
	PanelTheme.as_mono(sub_lbl, PanelTheme.SIZE_CAPTION)
	sub_lbl.add_theme_color_override("font_color", PanelTheme.DIM_FG)
	col.add_child(sub_lbl)
	row.add_child(col)

	# Condition pip — green/amber/red at-a-glance health (hunger + energy).
	var pip := ColorRect.new()
	pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pip.custom_minimum_size = Vector2(10, 10)
	pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pip.color = _condition_color(c)
	row.add_child(pip)

	if c is Fish and c.fish_journal.size() > 0:
		var journal_btn := Button.new()
		journal_btn.flat = true
		journal_btn.focus_mode = Control.FOCUS_NONE
		journal_btn.custom_minimum_size = Vector2(30, 34)
		journal_btn.text = "📖"
		journal_btn.tooltip_text = "Life journal"
		journal_btn.pressed.connect(func(): _show_fish_journal(cref))
		row.add_child(journal_btn)

	# Favorite star (its own STOP filter so it captures clicks over the row).
	var star := Button.new()
	star.flat = true
	star.focus_mode = Control.FOCUS_NONE
	star.custom_minimum_size = Vector2(34, 34)
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	star.add_theme_font_size_override("font_size", 16)
	star.text = "★" if _is_favorite(c) else "☆"
	star.tooltip_text = "Favorite"
	star.pressed.connect(func(): _on_star_pressed(cref))
	row.add_child(star)

	card.set_meta("creature", cref)
	card.set_meta("sub_lbl", sub_lbl)
	card.set_meta("star", star)
	card.set_meta("pip", pip)
	return card


func _on_row_clicked(c: Node) -> void:
	if c == null or not is_instance_valid(c):
		_queue_rebuild()
		return
	_call_main("follow_creature", [c])


func _on_star_pressed(c: Node) -> void:
	if _sim != null and is_instance_valid(c) and _sim.has_method("toggle_favorite"):
		_sim.toggle_favorite(c)


func _update_now_following(node: Variant) -> void:
	# Update the header label + move the highlight to the matching card.
	if _highlight_card != null and is_instance_valid(_highlight_card):
		_highlight_card.remove_theme_stylebox_override("normal")
	_highlight_card = null
	var n: Node = node as Node
	if n == null or not is_instance_valid(n):
		if _now_lbl != null:
			_now_lbl.text = "Tap a creature to follow"
		return
	if _now_lbl != null:
		_now_lbl.text = "Following  %s" % _creature_name(n)
	var card: Variant = _card_by_id.get(n.get_instance_id())
	if card != null and is_instance_valid(card):
		var hl := StyleBoxFlat.new()
		hl.bg_color = PanelTheme.RAIL_ACTIVE_BG
		hl.corner_radius_top_left = 6
		hl.corner_radius_top_right = 6
		hl.corner_radius_bottom_left = 6
		hl.corner_radius_bottom_right = 6
		card.add_theme_stylebox_override("normal", hl)
		_highlight_card = card


func _process(delta: float) -> void:
	if not visible:
		return
	_stat_accum += delta
	if _stat_accum < 1.0:
		return
	_stat_accum = 0.0
	_refresh_card_stats()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_hide_panel()
		get_viewport().set_input_as_handled()
		return
	# Down arrow enters the card list from the header. Skip while search is focused.
	if event.is_action_pressed("ui_down"):
		if PanelTheme.typing_focus_in_ui(get_viewport()):
			return
		var fo: Control = get_viewport().gui_get_focus_owner()
		if not _card_by_id.values().has(fo) and not _card_by_id.is_empty():
			(_card_by_id.values()[0] as Control).grab_focus()
			get_viewport().set_input_as_handled()


func _hide_panel() -> void:
	visible = false
	_bind_ui_ticker(false)
	set_process(false)


# ---- duck-typed helpers ----

func _call_main(method: String, args: Array) -> void:
	if main_ref != null and main_ref.has_method(method):
		main_ref.callv(method, args)


func _is_favorite(c: Node) -> bool:
	return _sim != null and _sim.has_method("is_favorite") and _sim.is_favorite(c)


# ---- creature data accessors ----

func _creature_name(c: Node) -> String:
	if c == null or not is_instance_valid(c):
		return "?"
	for k in ["fish_name", "shrimp_name", "snail_name", "clam_name", "_display_name"]:
		if c.get(k) != null and String(c.get(k)) != "":
			return String(c.get(k))
	return _species_of(c).capitalize()


func _card_name(c: Node) -> String:
	var nm: String = _creature_name(c)
	var pers: Variant = c.get("personality")
	var label: String = nm
	if pers is Dictionary and not (pers as Dictionary).is_empty():
		var stable_key: String = nm
		if c.get("id") != null and String(c.get("id")) != "":
			stable_key = String(c.get("id"))
		var ep: String = CreatureNaming.epithet_for_personality(pers, stable_key)
		if ep != "":
			label = "%s %s" % [nm, ep]
	if _sim != null and _sim.has_method("is_guardian_creature") \
			and _sim.is_guardian_creature(c):
		return "◆ %s" % label
	return label


func _species_of(c: Node) -> String:
	if c != null and c.get("species") != null:
		return String(c.species)
	return ""


func _age_of(c: Node) -> float:
	if c != null and c.get("age") != null:
		return float(c.age)
	return 0.0


func _sub_text(c: Node) -> String:
	var affect: String = OnboardingLegibility.affect_label(c)
	if c is Fish:
		var bio_line: String = String(c.get_bio_summary()) if c.has_method("get_bio_summary") else ""
		if bio_line != "":
			var base: String = bio_line
			if affect != "":
				base = "%s · %s" % [affect, bio_line]
			var arc: String = MindConversation.bond_arc_label(c)
			if arc != "":
				base = "%s · %s" % [base, arc]
			if c.fish_journal.size() > 0:
				base = "%s · %d journal" % [base, c.fish_journal.size()]
			return base
	var gen := 0
	if c.get("generation") != null:
		gen = int(c.generation)
	var age_s := _age_of(c)
	var age_str := "%dm" % int(age_s / 60.0) if age_s >= 60.0 else "%ds" % int(age_s)
	# Lead with what it's doing right now — the "these are individuals" signal.
	var act := ""
	if main_ref != null and main_ref.has_method("creature_activity_label"):
		act = String(main_ref.creature_activity_label(c))
	if act != "":
		var lead: String = act
		if affect != "":
			lead = "%s · %s" % [affect, act]
		return "%s · Gen %d · %s" % [lead, gen, age_str]
	var sp := _species_of(c).capitalize()
	if sp == "":
		return "Gen %d · %s" % [gen, age_str]
	return "%s · Gen %d · %s" % [sp, gen, age_str]


func _type_of(c: Node) -> int:
	if c is Fish:
		return Filter.FISH
	if c is Shrimp:
		return Filter.SHRIMP
	var scr: Script = c.get_script()
	var p: String = scr.resource_path if scr != null else ""
	if p.ends_with("snail.gd"):
		return Filter.SNAIL
	if p.ends_with("clam.gd"):
		return Filter.CLAM
	return Filter.ALL


func _emoji_of(c: Node) -> String:
	match _type_of(c):
		Filter.FISH:
			return "🐟"
		Filter.SHRIMP:
			return "🦐"
		Filter.SNAIL:
			return "🐌"
		Filter.CLAM:
			return "🦪"
	return "•"


func _color_of(c: Node) -> Color:
	for k in ["base_color", "shell_color", "body_color", "accent_color"]:
		var v: Variant = c.get(k)
		if v is Color:
			return (v as Color)
	return Color(0.45, 0.6, 0.8)


# 0 = critical (starving / near death), 1 = thriving. Uses whichever of
# energy / hunger the creature exposes (clams have no hunger, etc.).
func _condition_score(c: Node) -> float:
	if c == null or not is_instance_valid(c):
		return 1.0
	var e := 1.0
	if c.get("energy") != null:
		e = clampf(float(c.energy), 0.0, 1.0)
	var sated := 1.0
	if c.get("hunger") != null:
		sated = 1.0 - clampf(float(c.hunger), 0.0, 1.0)  # hunger 1 = starving
	return minf(e, sated)


func _condition_color(c: Node) -> Color:
	var s := _condition_score(c)
	if s >= 0.6:
		return Color(0.40, 0.85, 0.45)   # thriving
	if s >= 0.3:
		return Color(0.95, 0.80, 0.35)   # peckish
	return Color(0.95, 0.40, 0.40)       # needs attention


func _make_section_divider(text: String) -> Control:
	return PanelTheme.make_section(text)


func _show_fish_journal(f: Fish) -> void:
	if f == null or not is_instance_valid(f):
		return
	_dismiss_fish_journal()
	var layer := ColorRect.new()
	layer.color = Color(0.0, 0.0, 0.0, 0.45)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if main_ref != null:
		main_ref.add_child(layer)
	else:
		add_child(layer)
	_journal_layer = layer
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 280)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	PanelTheme.apply_panel_chrome(panel)
	layer.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var nm: String = _creature_name(f)
	vb.add_child(PanelTheme.make_title("Journal — %s" % nm))
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = true
	body.custom_minimum_size = Vector2(300, 180)
	body.text = FishJournal.format_bbcode(f.fish_journal, nm)
	vb.add_child(body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	var export_btn := PanelTheme.make_secondary_button("Export")
	export_btn.pressed.connect(func():
		var path: String = "user://journal_%s.txt" % String(f.id)
		var f_out := FileAccess.open(path, FileAccess.WRITE)
		if f_out != null:
			f_out.store_string(FishJournal.export_plain(f.fish_journal, nm))
			f_out.close())
	row.add_child(export_btn)
	var close_btn := PanelTheme.make_secondary_button("Close")
	close_btn.pressed.connect(_dismiss_fish_journal)
	row.add_child(close_btn)
	layer.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_dismiss_fish_journal())


func _dismiss_fish_journal() -> void:
	if _journal_layer != null and is_instance_valid(_journal_layer):
		_journal_layer.queue_free()
	_journal_layer = null


func _make_empty_state() -> Control:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var has_any: bool = _sim != null and _sim.has_method("living_creatures") \
		and not _sim.living_creatures().is_empty()
	var msg := Label.new()
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_color_override("font_color", PanelTheme.DIM_FG)
	msg.text = "No creatures match your filter or search." if has_any \
		else "No residents yet — open Adopt fish to add a few."
	box.add_child(msg)
	return box
