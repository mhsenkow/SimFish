# Interactive lineage graph for the Life Library.
# Lays discoveries out in generation columns with edges parent → child.

extends Control
class_name LineageTreeView

signal entry_selected(entry: Dictionary)

const COL_WIDTH: float = 148.0
const ROW_HEIGHT: float = 40.0
const NODE_PAD: float = 8.0
const MARGIN: float = 16.0

var _entries: Array = []
var _positions: Dictionary = {}   # species_key -> Vector2 (node center, local)
var _key_to_entry: Dictionary = {}
var _selected_key: String = ""
var _content_size: Vector2 = Vector2(320, 120)
var _node_layer: Control = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_node_layer = Control.new()
	_node_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_node_layer)
	custom_minimum_size = _content_size
	size = _content_size


func set_entries(entries: Array, selected_key: String = "") -> void:
	_entries = entries.duplicate()
	_selected_key = selected_key
	_key_to_entry.clear()
	_positions.clear()
	_layout_graph()
	_rebuild_node_buttons()
	custom_minimum_size = _content_size
	size = _content_size
	queue_redraw()


func set_selected_key(key: String) -> void:
	if _selected_key == key:
		return
	_selected_key = key
	_rebuild_node_buttons()


func _layout_graph() -> void:
	var by_gen: Dictionary = {}
	var max_gen: int = 0
	for e in _entries:
		if not (e is Dictionary):
			continue
		var gen: int = int(e.get("generation", 0))
		max_gen = maxi(max_gen, gen)
		if not by_gen.has(gen):
			by_gen[gen] = []
		(by_gen[gen] as Array).append(e)
		var k: String = String(e.get("species_key", ""))
		if k != "":
			_key_to_entry[k] = e

	var max_col_h: float = MARGIN
	var col_x: float = MARGIN
	for gen in range(max_gen + 1):
		var col: Array = by_gen.get(gen, [])
		col.sort_custom(func(a, b):
			return String(a.get("display_name", "")) < String(b.get("display_name", "")))
		var y: float = MARGIN
		for e in col:
			var k: String = String(e.get("species_key", ""))
			if k == "":
				continue
			_positions[k] = Vector2(col_x + COL_WIDTH * 0.5, y + ROW_HEIGHT * 0.5)
			y += ROW_HEIGHT
		max_col_h = maxf(max_col_h, y)
		col_x += COL_WIDTH

	_content_size = Vector2(col_x + MARGIN, max_col_h + MARGIN)
	if _node_layer != null:
		_node_layer.custom_minimum_size = _content_size
		_node_layer.size = _content_size


func _rebuild_node_buttons() -> void:
	if _node_layer == null:
		return
	for c in _node_layer.get_children():
		c.queue_free()
	for k in _positions.keys():
		var e: Dictionary = _key_to_entry.get(k, {})
		if e.is_empty():
			continue
		var center: Vector2 = _positions[k]
		var btn := Button.new()
		var otype: String = String(e.get("organism_type", "fish"))
		var icon: String = _icon_for(otype)
		btn.text = "%s %s" % [icon, String(e.get("display_name", "?"))]
		btn.tooltip_text = "gen %d · %s" % [
			int(e.get("generation", 0)), String(e.get("parent_lineage", "")),
		]
		btn.custom_minimum_size = Vector2(COL_WIDTH - NODE_PAD * 2, ROW_HEIGHT - 6)
		btn.position = center - btn.custom_minimum_size * 0.5
		btn.add_theme_font_size_override("font_size", 10)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.clip_text = true
		if k == _selected_key:
			var sel := StyleBoxFlat.new()
			sel.bg_color = Color(0.18, 0.32, 0.55, 0.65)
			sel.corner_radius_top_left = 4
			sel.corner_radius_top_right = 4
			sel.corner_radius_bottom_left = 4
			sel.corner_radius_bottom_right = 4
			btn.add_theme_stylebox_override("normal", sel)
		btn.pressed.connect(_on_node_pressed.bind(k))
		_node_layer.add_child(btn)


func _on_node_pressed(species_key: String) -> void:
	var entry: Variant = _key_to_entry.get(species_key, {})
	if entry is Dictionary:
		entry_selected.emit(entry)


func _draw() -> void:
	# Generation column guides
	var max_gen: int = 0
	for e in _entries:
		if e is Dictionary:
			max_gen = maxi(max_gen, int(e.get("generation", 0)))
	var col_x: float = MARGIN
	for gen in range(max_gen + 1):
		var label_pos: Vector2 = Vector2(col_x + 4, 2)
		draw_string(ThemeDB.fallback_font, label_pos, "g%d" % gen,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.62, 0.75, 0.9))
		draw_line(
			Vector2(col_x, MARGIN - 4),
			Vector2(col_x, _content_size.y - 4),
			Color(0.25, 0.32, 0.45, 0.35), 1.0)
		col_x += COL_WIDTH

	var edge_col := Color(0.42, 0.68, 0.92, 0.5)
	for e in _entries:
		if not (e is Dictionary):
			continue
		var child_key: String = String(e.get("species_key", ""))
		if child_key == "" or not _positions.has(child_key):
			continue
		var p_child: Vector2 = _positions[child_key]
		var pks: Variant = e.get("parent_keys", [])
		if not (pks is Array):
			continue
		for pk in pks:
			var parent_key: String = String(pk)
			if parent_key == "" or not _positions.has(parent_key):
				continue
			var p_parent: Vector2 = _positions[parent_key]
			var mid: Vector2 = (p_parent + p_child) * 0.5
			draw_line(p_parent, mid, edge_col, 2.0, true)
			draw_line(mid, p_child, edge_col, 2.0, true)
			draw_circle(p_parent, 3.0, Color(0.5, 0.8, 1.0, 0.7))


static func _icon_for(otype: String) -> String:
	match otype:
		"shrimp": return "🦐"
		"snail": return "🐌"
		"plant": return "🌿"
		_: return "🐟"
