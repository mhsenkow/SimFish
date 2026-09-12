extends PanelContainer
class_name VesselPicker

# Choose a tank the way you would in a shop (tank realism pass).
#
# Picking a vessel was a dropdown of names buried in Settings → Tank, listing
# abstract game units. You could not see that a 20 long is wide and low, that
# a column is tall and narrow, or that a nano is a fraction of a 75 — the
# three things that actually decide which tank you want.
#
# So: cards, grouped by size, each with a to-scale silhouette drawn against a
# SHARED reference (see vessel_silhouette.gd), the real dimensions, the real
# volume, and what it will hold. The silhouettes are the point; the text
# confirms what the picture already told you.
#
# Follows the panel contract enforced by smoke_panel_contract.gd: a Close
# control, a close path main can drive, and pad-focusable cards.

signal vessel_chosen(key: String)

# Size bands, coarse enough to be useful and ordered small -> large. Volume
# thresholds in US gallons.
const BANDS: Array[Dictionary] = [
	{"label": "Nano — desk scale", "max_gal": 12.0},
	{"label": "Small — a first community", "max_gal": 32.0},
	{"label": "Mid — room to aquascape", "max_gal": 60.0},
	{"label": "Large — a piece of furniture", "max_gal": 1000.0},
]

# Shaped vessels are grouped by character, not volume: someone choosing a
# bowl or a column is choosing a look, not a capacity.
const SHAPED_LABEL := "Shaped — chosen for their look"

var main_ref: Node = null

var _cards_by_key: Dictionary = {}
var _selected: String = ""


func _ready() -> void:
	PanelTheme.apply_panel_chrome(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(560, 0)
	_build_ui()
	visible = false


func _build_ui() -> void:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)

	outer.add_child(PanelTheme.make_title(tr("Choose a tank")))
	var sub := PanelTheme.make_description()
	sub.text = tr(
		"Every tank is drawn to the same scale, so you can see how they "
		+ "compare. The orange mark is one small fish."
	)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(sub)
	outer.add_child(PanelTheme.make_rule())

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	for group in _grouped():
		body.add_child(PanelTheme.make_section(String(group["label"])))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(grid)
		for spec in group["specs"]:
			grid.add_child(_build_card(spec))

	outer.add_child(PanelTheme.make_panel_footer(_request_close))


# Catalogue split into bands. Shaped vessels last, as a character group.
func _grouped() -> Array[Dictionary]:
	var shaped: Array[Dictionary] = []
	var by_band: Dictionary = {}
	for spec in TankSpec.CATALOGUE:
		if String(spec["shape"]) in ["cylinder", "sphere", "hex"]:
			shaped.append(spec)
			continue
		var gal: float = float(spec["nominal_gal"])
		for i in BANDS.size():
			if gal <= float(BANDS[i]["max_gal"]):
				if not by_band.has(i):
					by_band[i] = []
				(by_band[i] as Array).append(spec)
				break
	var out: Array[Dictionary] = []
	for i in BANDS.size():
		if not by_band.has(i):
			continue
		var arr: Array = by_band[i]
		arr.sort_custom(func(a, b): return float(a["nominal_gal"]) < float(b["nominal_gal"]))
		out.append({"label": String(BANDS[i]["label"]), "specs": arr})
	if not shaped.is_empty():
		shaped.sort_custom(func(a, b): return float(a["nominal_gal"]) < float(b["nominal_gal"]))
		out.append({"label": SHAPED_LABEL, "specs": shaped})
	return out


func _build_card(spec: Dictionary) -> Control:
	var key: String = String(spec["key"])
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PanelTheme.apply_shelf_card_chrome(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)

	var sil := VesselSilhouette.new()
	sil.custom_minimum_size = Vector2(0, 156)
	sil.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sil.configure(spec)
	vb.add_child(sil)

	var name_lbl := Label.new()
	name_lbl.text = String(spec["label"])
	PanelTheme.as_serif(name_lbl, PanelTheme.SIZE_ITEM, true)
	vb.add_child(name_lbl)

	var facts := Label.new()
	facts.text = "%s\n%s" % [TankSpec.volume_label(key), TankSpec.dimensions_label(key)]
	facts.add_theme_font_size_override("font_size", PanelTheme.SIZE_CAPTION)
	vb.add_child(facts)

	var g: Dictionary = TankSpec.geometry(key)
	var stock := Label.new()
	stock.text = TankSpec.stocking_hint(
		String(g["tank_shape"]), float(g["tank_half_w"]),
		float(g["tank_half_d"]), float(g["tank_height"]), 0.93)
	stock.add_theme_font_size_override("font_size", PanelTheme.SIZE_CAPTION)
	stock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stock.add_theme_color_override("font_color", Color8(150, 175, 200))
	vb.add_child(stock)

	var blurb := PanelTheme.make_description()
	blurb.text = String(spec["blurb"])
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(blurb)

	var pick := PanelTheme.make_primary_button(tr("Use this tank"))
	pick.pressed.connect(func(): _choose(key))
	vb.add_child(pick)

	_cards_by_key[key] = card
	return card


func _choose(key: String) -> void:
	_selected = key
	if not TankSpec.has_spec(key):
		return
	TankConfig.begin_settings_batch()
	TankConfig.apply_vessel_preset(key)
	# Footprint changed, so the terrain must be rebuilt or plants sit in mid-air.
	TankConfig.rebuild_terrain_on_load = true
	TankConfig.end_settings_batch()
	TankConfig.request_save_to_disk()
	vessel_chosen.emit(key)
	var lg: Node = get_node_or_null("/root/AppLog")
	if lg != null and lg.has_method("info"):
		lg.info("vessel", "chose %s (%s)" % [key, TankSpec.volume_label(key)])
	_request_close()


func selected_key() -> String:
	return _selected


# Highlight whatever the tank currently is, so opening the picker shows you
# where you already are rather than an undifferentiated grid.
func sync_from_config() -> void:
	var current: String = String(TankConfig.vessel_preset)
	for key in _cards_by_key.keys():
		var card: PanelContainer = _cards_by_key[key]
		if not is_instance_valid(card):
			continue
		card.modulate = Color(1, 1, 1, 1) if String(key) == current \
			else Color(1, 1, 1, 0.82)


func _request_close() -> void:
	if main_ref != null and is_instance_valid(main_ref) \
			and main_ref.has_method("close_vessel_picker"):
		main_ref.call("close_vessel_picker")
	else:
		visible = false
