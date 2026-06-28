# Live 48-color biotope swatch grid — day + night preview (#2).
class_name PaletteInspector
extends VBoxContainer

var _day_row: HBoxContainer
var _night_row: HBoxContainer
var _key_label: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_key_label = PanelTheme.as_mono(Label.new(), PanelTheme.SIZE_CAPTION)
	_key_label.modulate = PanelTheme.DIM_FG
	add_child(_key_label)
	var day_l := PanelTheme.as_sans(Label.new(), PanelTheme.SIZE_CAPTION)
	day_l.text = "Day"
	add_child(day_l)
	_day_row = HBoxContainer.new()
	_day_row.add_theme_constant_override("separation", 1)
	add_child(_day_row)
	var night_l := PanelTheme.as_sans(Label.new(), PanelTheme.SIZE_CAPTION)
	night_l.text = "Night"
	add_child(night_l)
	_night_row = HBoxContainer.new()
	_night_row.add_theme_constant_override("separation", 1)
	add_child(_night_row)


func refresh_from_main(main: Node) -> void:
	if main == null or not main.has_method("_biotope_palette_textures"):
		return
	var cfg := get_node_or_null("/root/TankConfig")
	var key: String = AestheticsRuntime.biotope_palette_key(cfg)
	_key_label.text = "Biotope: %s" % key
	var texs: Array = main.call("_biotope_palette_textures", key)
	if texs.size() < 2:
		return
	_fill_row(_day_row, texs[0] as Texture2D, false)
	_fill_row(_night_row, texs[1] as Texture2D, true)


func _fill_row(row: HBoxContainer, tex: Texture2D, _night: bool) -> void:
	for c in row.get_children():
		c.queue_free()
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img == null or img.get_width() < 48:
		return
	for i in 48:
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(5, 14)
		sw.color = img.get_pixel(i, 0)
		sw.tooltip_text = "#%s" % sw.color.to_html(false)
		row.add_child(sw)
