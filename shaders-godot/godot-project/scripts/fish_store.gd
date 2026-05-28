# Retro "Buy New Fish" store.
#
# When the population crashes (or just for fun) the user clicks a corner
# button and gets three procedurally-generated unique fish. They can take
# home up to two of them; each one becomes a real spawn into the world.
#
# Visual vibe: arcade pet shop. Neon borders, monospace text, big shouty
# header. The actual fish-card content (color swatches, traits) is built
# dynamically so the generator and the rendering aren't coupled.

extends PanelContainer


# 3 generated genome dicts. Each entry gets one card.
var _options: Array = []
var _purchased: int = 0
const MAX_PURCHASES: int = 2

# Reference to the world for spawning. Resolved lazily.
var _world: Node3D = null

var _cards_container: VBoxContainer = null
var _status_label: Label = null

# Pools used by the genome generator. Picking from these gives the random
# fish a recognisable shape rather than a uniform-distribution slurry.
const SWIM_POOL: Array[String] = [
	"school", "shoal", "dart", "hover", "cruise", "meander", "shuffle"
]
const NAME_ADJ: Array[String] = [
	"Neon", "Crimson", "Lazuli", "Sunlit", "Twilight", "Lunar", "Ember",
	"Coral", "Frost", "Onyx", "Citrine", "Verdant", "Pearl", "Mirage",
]
const NAME_NOUN: Array[String] = [
	"Darter", "Glider", "Nibbler", "Shimmer", "Spike", "Wisp", "Crest",
	"Tang", "Sprite", "Slip", "Drake", "Veil", "Mote", "Lance",
]


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		get_viewport().set_input_as_handled()


func toggle() -> void:
	visible = not visible
	if visible:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_regenerate()
	else:
		mouse_filter = Control.MOUSE_FILTER_IGNORE


func _build_ui() -> void:
	custom_minimum_size = Vector2(420, 0)
	# Use the shared dark rounded chrome so the store reads as part of the
	# same panel family. Cards inside keep their arcade-cyan border so the
	# shop still feels like a destination, not just another settings page.
	PanelTheme.apply_panel_chrome(self)

	# Outer layout — title, subtitle, status, cards, footer.
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)

	# Retro neon header. The double-bar glyphs frame the title without
	# needing a font with built-in flourishes.
	var title := Label.new()
	title.text = "═══ FISH STORE ═══"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color8(255, 110, 200))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "select up to 2 of 3"
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", Color8(180, 230, 255))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(subtitle)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color8(140, 240, 140))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(_status_label)

	outer.add_child(PanelTheme.make_rule())

	# Cards container — rebuilt on each open so each visit shows fresh stock.
	# Generous 10-px row gap so the bordered cards have visual room and
	# don't look like they're stacked on top of each other.
	_cards_container = VBoxContainer.new()
	_cards_container.add_theme_constant_override("separation", 10)
	outer.add_child(_cards_container)

	# Footer: reroll + close. Reroll is the primary action (it's why the
	# player is here); close is secondary.
	outer.add_child(PanelTheme.make_rule())
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", 8)
	outer.add_child(hb)
	var close := PanelTheme.make_secondary_button("CLOSE")
	close.pressed.connect(func(): visible = false)
	hb.add_child(close)
	var reroll := PanelTheme.make_primary_button("REROLL")
	reroll.pressed.connect(_regenerate)
	hb.add_child(reroll)


func _regenerate() -> void:
	_purchased = 0
	_options.clear()
	for i in 3:
		_options.append(_random_genome(i))
	_status_label.text = "0 / %d caught" % MAX_PURCHASES
	_rebuild_cards()


func _rebuild_cards() -> void:
	# Tear down old cards.
	for c in _cards_container.get_children():
		c.queue_free()
	for i in _options.size():
		_cards_container.add_child(_make_card(i))


func _make_card(idx: int) -> Control:
	var g: Dictionary = _options[idx]
	# Outer card frame. Cyan-on-dark-blue is the arcade "shop card" look —
	# kept intentionally distinct from the muted panel chrome so the cards
	# read as merchandise rather than form rows. Rounded corners + thicker
	# padding lift the card off the panel background.
	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.16, 0.92)
	style.border_color = Color8(60, 200, 255)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	frame.add_theme_stylebox_override("panel", style)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	frame.add_child(hb)

	# Color swatch. Three vertical rects showing base + accent + tail tints
	# so the player can preview the fish's palette at a glance.
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(44, 64)
	swatch.color = g.get("base_color", Color.WHITE)
	hb.add_child(swatch)
	var accent_swatch := ColorRect.new()
	accent_swatch.custom_minimum_size = Vector2(12, 64)
	accent_swatch.color = g.get("accent_color", Color.GRAY)
	hb.add_child(accent_swatch)
	var tail_swatch := ColorRect.new()
	tail_swatch.custom_minimum_size = Vector2(12, 64)
	tail_swatch.color = g.get("tail_color", g.get("accent_color", Color.GRAY))
	hb.add_child(tail_swatch)

	# Text block — name on top, trait line beneath with looser leading
	# (separation 4) so the description doesn't crowd the name.
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(vbox)
	var name_label := Label.new()
	name_label.text = String(g.get("_display_name", "fish"))
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", Color8(255, 220, 80))
	vbox.add_child(name_label)
	var desc := Label.new()
	desc.text = _describe(g)
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color8(200, 210, 225))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	# Buy button. Styled bright cyan-on-dark to match the card border so
	# tapping feels like clicking the bezel itself.
	var buy := Button.new()
	buy.text = "BUY"
	buy.custom_minimum_size = Vector2(64, 32)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.add_theme_color_override("font_color", Color8(20, 28, 36))
	buy.add_theme_color_override("font_hover_color", Color8(20, 28, 36))
	buy.add_theme_color_override("font_pressed_color", Color8(20, 28, 36))
	var buy_normal := StyleBoxFlat.new()
	buy_normal.bg_color = Color8(60, 200, 255)
	buy_normal.corner_radius_top_left = 4
	buy_normal.corner_radius_top_right = 4
	buy_normal.corner_radius_bottom_left = 4
	buy_normal.corner_radius_bottom_right = 4
	buy_normal.content_margin_left = 12
	buy_normal.content_margin_right = 12
	buy_normal.content_margin_top = 6
	buy_normal.content_margin_bottom = 6
	buy.add_theme_stylebox_override("normal", buy_normal)
	var buy_hover := buy_normal.duplicate() as StyleBoxFlat
	buy_hover.bg_color = Color8(120, 230, 255)
	buy.add_theme_stylebox_override("hover", buy_hover)
	var buy_pressed := buy_normal.duplicate() as StyleBoxFlat
	buy_pressed.bg_color = Color8(40, 170, 220)
	buy.add_theme_stylebox_override("pressed", buy_pressed)
	# Capture idx; pressed.connect lambda needs to bind it.
	var captured_idx: int = idx
	buy.pressed.connect(func(): _on_buy(captured_idx, frame, buy))
	hb.add_child(buy)
	return frame


# Returns a short trait line for the card body.
func _describe(g: Dictionary) -> String:
	var pattern: String = String(g.get("swim_pattern", "school"))
	var py: float = float(g.get("preferred_y", 3.5))
	var layer: String = "mid"
	if py >= 4.6:
		layer = "top"
	elif py <= 2.5:
		layer = "bottom"
	var size_class: String
	var sz: float = float(g.get("adult_voxel_scale", 0.18))
	if sz < 0.14:
		size_class = "tiny"
	elif sz < 0.20:
		size_class = "small"
	elif sz < 0.25:
		size_class = "medium"
	else:
		size_class = "large"
	var tags: Array[String] = [pattern, layer, size_class]
	if g.get("has_barbels", false):
		tags.append("barbels")
	if g.get("armor_plates", false):
		tags.append("armored")
	if int(g.get("mouth_orientation", 0)) > 0:
		tags.append("sifter")
	elif int(g.get("mouth_orientation", 0)) < 0:
		tags.append("surface-feeder")
	return " · ".join(tags)


# Random genome builder. Pulls from continuous + discrete pools so each
# slot in the store is a unique combination of skeleton + colors. Each
# fish gets a synthetic species name + a heritable trait set.
func _random_genome(slot_idx: int) -> Dictionary:
	var swim: String = SWIM_POOL[randi() % SWIM_POOL.size()]
	# Pick body params that match the swim pattern's archetype so the
	# generator doesn't produce a "cory that schools at the surface".
	var pref_y: float
	var depth: float
	var elong: float
	match swim:
		"school", "shoal":
			pref_y = randf_range(3.6, 5.0)
			depth = randf_range(0.7, 1.0)
			elong = randf_range(1.0, 1.3)
		"dart":
			pref_y = randf_range(4.5, 5.4)
			depth = randf_range(0.7, 1.0)
			elong = randf_range(1.0, 1.3)
		"hover":
			pref_y = randf_range(3.2, 4.4)
			depth = randf_range(1.2, 1.8)
			elong = randf_range(0.8, 1.0)
		"cruise":
			pref_y = randf_range(3.0, 4.4)
			depth = randf_range(0.9, 1.3)
			elong = randf_range(1.0, 1.3)
		"meander":
			pref_y = randf_range(2.6, 3.6)
			depth = randf_range(1.3, 1.7)
			elong = randf_range(0.6, 0.9)
		"shuffle":
			pref_y = randf_range(1.8, 2.6)
			depth = randf_range(0.9, 1.2)
			elong = randf_range(1.05, 1.5)
		_:
			pref_y = 3.5; depth = 1.0; elong = 1.0

	# Colors: pull a vivid base + complementary accent + a contrasting tail.
	# tail_color is what gives male guppies their dramatic body/tail split.
	var hue: float = randf()
	var base_c: Color = Color.from_hsv(hue,
		randf_range(0.65, 1.0), randf_range(0.7, 1.0))
	var accent_c: Color = Color.from_hsv(fposmod(hue + 0.5, 1.0),
		randf_range(0.7, 1.0), randf_range(0.8, 1.0))
	# Tail tends to be the BRIGHT show piece - high saturation, possibly
	# the complementary hue (50% chance) or a triadic hue.
	var tail_hue: float = fposmod(hue + (0.5 if randf() < 0.5 else 0.333), 1.0)
	var tail_c: Color = Color.from_hsv(tail_hue,
		randf_range(0.85, 1.0), randf_range(0.85, 1.0))

	# Discrete skeleton picks.
	var tail_shape: int = randi() % 4
	var has_barbels: bool = swim == "shuffle" or randf() < 0.15
	var armor: bool = (swim == "shuffle" and randf() < 0.5) or randf() < 0.08
	var mouth: int = 0
	if swim == "shuffle":
		mouth = 1
	elif swim == "dart":
		mouth = -1

	var display_name: String = "%s %s" % [
		NAME_ADJ[randi() % NAME_ADJ.size()],
		NAME_NOUN[randi() % NAME_NOUN.size()],
	]
	return {
		"species": "stranger_%d" % slot_idx,
		"_display_name": display_name,
		"base_color": base_c,
		"accent_color": accent_c,
		"tail_color": tail_c,
		"adult_voxel_scale": randf_range(0.13, 0.27),
		"max_age_s": randf_range(180, 320),
		"max_speed": randf_range(0.8, 2.2),
		"schooling_strength": randf_range(0.0, 1.5),
		"separation_radius": randf_range(0.4, 1.0),
		"herbivory": randf_range(0.0, 1.0),
		"fecundity": randf_range(0.4, 1.2),
		"clutch_size": randi_range(1, 3),
		"preferred_y": pref_y,
		"swim_pattern": swim,
		"body_elongation": elong,
		"body_depth_factor": depth,
		"head_proportion": randf_range(0.85, 1.25),
		"eye_size_factor": randf_range(0.7, 1.5),
		"ventral_profile": randf_range(0.7, 1.4),
		"back_arch": randf_range(0.85, 1.35),
		"tail_shape": tail_shape,
		"fin_length_factor": randf_range(0.8, 1.7),
		"dorsal_height_factor": randf_range(0.75, 1.5),
		"tail_fork_depth": randf_range(0.5, 1.3),
		"pattern_type": randi() % 4,
		"color_dot_count": randi_range(0, 3),
		"has_barbels": has_barbels,
		"armor_plates": armor,
		"mouth_orientation": mouth,
	}


func _on_buy(idx: int, card_frame: PanelContainer, buy_btn: Button) -> void:
	if _purchased >= MAX_PURCHASES:
		return
	if _world == null:
		_world = get_tree().current_scene.get_node_or_null("SubViewport/World")
	if _world == null or not _world.has_method("spawn_purchased_fish"):
		return
	var g: Dictionary = _options[idx]
	_world.spawn_purchased_fish(g)
	_purchased += 1
	buy_btn.disabled = true
	buy_btn.text = "ADDED"
	# Dim the card.
	card_frame.modulate = Color(0.6, 0.6, 0.6, 1.0)
	_status_label.text = "%d / %d caught" % [_purchased, MAX_PURCHASES]
	if _purchased >= MAX_PURCHASES:
		_status_label.text = "%d / %d caught - SOLD OUT" % [_purchased, MAX_PURCHASES]
		# Disable other buy buttons.
		for c in _cards_container.get_children():
			for sub in c.get_children():
				_disable_children(sub)


func _disable_children(node: Node) -> void:
	if node is Button and (node as Button).text == "BUY":
		(node as Button).disabled = true
	for c in node.get_children():
		_disable_children(c)
