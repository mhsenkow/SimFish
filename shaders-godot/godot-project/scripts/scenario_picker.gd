# New-tank scenario picker.
#
# A self-contained modal that pops up before the player creates a new tank.
# Shows a grid of cards — Default + several themed combos that mix the
# substrate / aeration / preset / lighting axes into recognisable real-world
# vibes (Walstad jungle, Iwagumi stone garden, blackwater biotope, reef,
# cichlid rockwork, freshwater polyp lab, nature aquarium showcase, apex
# predator tank).
#
# Picking a card resolves to a `Dictionary` of TankConfig field overrides,
# applied right after `saves.new_tank()` mints a fresh slot. The picker is
# instantiated by `tank_menu.gd._on_new_pressed`; once a scenario is chosen
# the picker emits `scenario_chosen` and frees itself.
#
# Designed so adding a new scenario is one entry in the SCENARIOS array —
# no UI plumbing required.

extends Control
class_name ScenarioPicker

signal scenario_chosen(scenario: Dictionary)
signal canceled

# Each scenario describes the field overrides that get applied to
# TankConfig after the new slot is created. Fields not present here are
# left at the autoload's defaults (or whatever the slot already saved).
# `name` ends up in the tank name; everything else is a TankConfig assignment.
# Each scenario specifies a FULL set of tank dimensions + shape + lighting
# + substrate + stocking. The point is that every scenario produces a
# visibly DIFFERENT tank — not just the species, but the silhouette of
# the glass itself.
#
# `config` keys map 1:1 to TankConfig fields. `name` ends up in the tank
# title. Half-width / half-depth / height let each tank express the
# right footprint for its theme:
#   wide-shallow → Iwagumi (room to breathe)
#   tall-narrow  → Blackwater column (vertical wood)
#   cube         → Reef
#   hex          → Cichlid show tank
#   sphere       → Polyp lab biosphere
#   cylinder     → Nature aquarium column
const SCENARIOS: Array[Dictionary] = [
	{
		"id": "walstad",
		"name": "Walstad Jungle",
		"tagline": "Dense planted community, mouthbrooding gourami, cleaner shrimp",
		"body": "Standard rectangular box, aquasoil + hang-on-back filter. Cardinal tetras school the back wall, harlequin rasbora shoal mid-water, corydoras shuffle the bottom, and a dwarf gourami pair guard their territory + carry fry visibly in their throats. Cherry-shrimp cleanup crew includes amano-style cleaners that station near stressed fish.",
		"accent_color": Color8(120, 195, 110),
		"config": {
			"tank_preset": "classic_community",
			"substrate_type": "aquasoil",
			"aeration_type": "filter",
			"tank_shape": "box",
			"tank_half_w": 8.0,
			"tank_half_d": 4.0,
			"tank_height": 7.0,
			"water_surface_fraction": 0.93,
			"substrate_depth_fraction": 0.23,
			"light_fixture": "bar",
			"environment_preset": "bedroom_desk",
			"lighting_preset": "cozy_shop",
		},
	},
	{
		"id": "iwagumi",
		"name": "Iwagumi Stone Garden",
		"tagline": "Wide shallow box · sand · single tetra school · bright sun",
		"body": "Long shallow rectangle (11×3 with low ceiling) so the negative space dominates. Bright cool lighting + sand floor + no aeration. Three asymmetric stones, no driftwood, almost no plants. A single tight cardinal tetra school is the only living motion. Sunlit-window room.",
		"accent_color": Color8(220, 215, 200),
		"config": {
			"tank_preset": "iwagumi_school",
			"substrate_type": "sand",
			"aeration_type": "none",
			"tank_shape": "box",
			"tank_half_w": 11.0,
			"tank_half_d": 3.0,
			"tank_height": 5.0,
			"water_surface_fraction": 0.92,
			"substrate_depth_fraction": 0.18,
			"light_fixture": "bar",
			"environment_preset": "sunny_window",
			"lighting_preset": "sunny",
		},
	},
	{
		"id": "blackwater",
		"name": "Blackwater Biotope",
		"tagline": "Tall narrow column · driftwood-stained water · dim warm",
		"body": "Tall narrow column tank (6×3 with a 9-unit ceiling) so the vertical driftwood and column dimness read. Aquasoil floor, filter intake, warm dim pendant. Killifish dart at the surface, corydoras shuffle the leaf litter, guppies hold mid-water. Tannins lerp the water tea-brown over real-time hours. Dark-cabinet room.",
		"accent_color": Color8(135, 95, 60),
		"config": {
			"tank_preset": "blackwater_biotope",
			"substrate_type": "aquasoil",
			"aeration_type": "filter",
			"tank_shape": "box",
			"tank_half_w": 6.0,
			"tank_half_d": 3.0,
			"tank_height": 9.0,
			"water_surface_fraction": 0.94,
			"substrate_depth_fraction": 0.18,
			"light_fixture": "spotlight",
			"environment_preset": "dark_cabinet",
			"lighting_preset": "dim_warm",
		},
	},
	{
		"id": "reef",
		"name": "Coral Reef Cube",
		"tagline": "Cube tank · ocean sand · corals + clams + mixed reef school",
		"body": "Saltwater rimless cube (7×7 footprint, 7 tall — equal sides for a proper coral-cube aesthetic). Ocean-sand substrate spawns corals, anemones, clams, sponges instead of plants. Coral tips pulse + bleach + glow at night; anemones ribbon-wave. Mixed reef fish — each individual rolls a unique tropical morph (clownfish, tangs, chromis, anthias).",
		"accent_color": Color8(255, 150, 110),
		"config": {
			"tank_preset": "reef",
			"substrate_type": "ocean_sand",
			"aeration_type": "stick",
			"tank_shape": "cube",
			"tank_half_w": 6.5,
			"tank_half_d": 6.5,
			"tank_height": 7.0,
			"water_surface_fraction": 0.95,
			"substrate_depth_fraction": 0.14,
			"light_fixture": "spotlight",
			"environment_preset": "sunny_window",
			"lighting_preset": "reef",
		},
	},
	{
		"id": "cichlid_rock",
		"name": "Cichlid Hex Showtank",
		"tagline": "Hexagonal show · sand + stones · two territorial pairs",
		"body": "A hexagonal show tank (six glass walls) so each territorial pair claims a wedge of the floor. Sand substrate, heavy stone arrangement, filter return for current. Angelfish + dwarf gourami pairs both defend their patches (alpha chases conspecific intruders) and incubate fry in their throats. Cory team patrols the centre.",
		"accent_color": Color8(220, 180, 220),
		"config": {
			"tank_preset": "cichlid_pairs",
			"substrate_type": "sand",
			"aeration_type": "filter",
			"tank_shape": "hex",
			"tank_half_w": 7.0,
			"tank_half_d": 7.0,
			"tank_height": 8.0,
			"water_surface_fraction": 0.93,
			"substrate_depth_fraction": 0.22,
			"light_fixture": "spotlight",
			"environment_preset": "bedroom_desk",
			"lighting_preset": "cozy_shop",
		},
	},
	{
		"id": "polyp_lab",
		"name": "Polyp Biosphere",
		"tagline": "Spherical bowl · NO fish · hydra colonies + clams + shrimp",
		"body": "Speculative dome biosphere — a literal sphere tank, no fish at all. The detrital loop IS the entertainment: dense cherry shrimp colony, filter-feeding clams in the substrate, and freshwater hydra polyps (real Hydra viridis-style organisms) seeded as the sessile centerpiece. Eco-complete floor, no equipment flow, neutral light. Watch the bloom-and-crash cycles instead of the fauna drama.",
		"accent_color": Color8(180, 230, 140),
		"config": {
			"tank_preset": "polyp_lab",
			"substrate_type": "eco_complete",
			"aeration_type": "none",
			"tank_shape": "sphere",
			"tank_half_w": 5.0,
			"tank_half_d": 5.0,
			"tank_height": 6.0,
			"water_surface_fraction": 0.90,
			"substrate_depth_fraction": 0.26,
			"light_fixture": "spotlight",
			"environment_preset": "forest_window",
			"lighting_preset": "planted",
		},
	},
	{
		"id": "nature_aquarium",
		"name": "Nature Aquarium Column",
		"tagline": "Cylindrical column · lush plants · every behavior on display",
		"body": "Cylindrical column tank (rounded glass, no corners). Aquasoil + filter + bright neutral light. Curated stocking puts the simulation's full vocabulary on screen at once: angelfish + dwarf gourami pairs (territorial mouthbrooders), killifish surface darts, guppy parallel-display courtship, corydoras substrate-shuffle. Amano-style cleaners station with stressed fish. Lush plants + java fern epiphytes on driftwood.",
		"accent_color": Color8(160, 220, 200),
		"config": {
			"tank_preset": "showcase",
			"substrate_type": "aquasoil",
			"aeration_type": "filter",
			"tank_shape": "cylinder",
			"tank_half_w": 5.5,
			"tank_half_d": 5.5,
			"tank_height": 8.0,
			"water_surface_fraction": 0.94,
			"substrate_depth_fraction": 0.20,
			"light_fixture": "spotlight",
			"environment_preset": "bedroom_desk",
			"lighting_preset": "planted",
		},
	},
	{
		"id": "apex_predator",
		"name": "Apex Predator Den",
		"tagline": "Cozy box · eco-rich · betta vs. puffer territories",
		"body": "Small dim box (6×4×6) — the cramped footprint forces the betta and dwarf puffer to actually contest corners. Eco-complete substrate so plants stay sparse and the fish silhouettes dominate. Filter for flow. Dark-cabinet room, warm dim light. Glassdart school and a few guppies try to stay in the middle where neither apex can reach.",
		"accent_color": Color8(220, 100, 100),
		"config": {
			"tank_preset": "apex_tank",
			"substrate_type": "eco_complete",
			"aeration_type": "filter",
			"tank_shape": "box",
			"tank_half_w": 6.0,
			"tank_half_d": 4.0,
			"tank_height": 6.0,
			"water_surface_fraction": 0.92,
			"substrate_depth_fraction": 0.24,
			"light_fixture": "spotlight",
			"environment_preset": "dark_cabinet",
			"lighting_preset": "dim_warm",
		},
	},
]


# Build the modal procedurally so we don't have to ship a .tscn for it.
# Layout: dim backdrop covers the whole viewport, a centered PanelContainer
# holds the title + scenario grid + cancel button.
func _ready() -> void:
	# Cover the full viewport so the backdrop catches clicks behind cards.
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Backdrop dim layer.
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.65)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(func(ev: InputEvent):
		# Click outside the panel cancels the modal.
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			_cancel())
	add_child(backdrop)

	# Centered panel.
	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 580)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Stop click propagation so clicking inside the panel doesn't fall
	# through to the backdrop's cancel handler.
	panel.gui_input.connect(func(_e): pass)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(vb)

	# Title + tagline.
	var title := Label.new()
	title.text = "Pick a tank scenario"
	title.add_theme_font_size_override("font_size", 22)
	vb.add_child(title)

	var sub := Label.new()
	sub.text = "Themed combinations of substrate, plants/coral, fish, and lighting."
	sub.add_theme_color_override("font_color", Color(0.7, 0.78, 0.92, 1.0))
	sub.add_theme_font_size_override("font_size", 13)
	vb.add_child(sub)

	# Scrollable grid of scenario cards.
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	for sc in SCENARIOS:
		grid.add_child(_build_card(sc))

	# Footer with Cancel.
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 8)
	vb.add_child(footer)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(120, 40)
	cancel.pressed.connect(_cancel)
	footer.add_child(cancel)


# Build a single scenario card with title bar (accent color), tagline,
# description body, and an "Open this tank" button.
func _build_card(sc: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(330, 230)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	card.add_child(vb)

	# Accent-color title band so each scenario has a glance-recognisable
	# identity in the grid.
	var band := PanelContainer.new()
	var band_sb := StyleBoxFlat.new()
	band_sb.bg_color = sc.get("accent_color", Color(0.6, 0.7, 0.8, 1.0))
	band_sb.content_margin_left = 10
	band_sb.content_margin_right = 10
	band_sb.content_margin_top = 6
	band_sb.content_margin_bottom = 6
	band_sb.corner_radius_top_left = 4
	band_sb.corner_radius_top_right = 4
	band.add_theme_stylebox_override("panel", band_sb)
	var title := Label.new()
	title.text = String(sc.get("name", "Scenario"))
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color(0.06, 0.07, 0.10, 1.0))
	band.add_child(title)
	vb.add_child(band)

	# Tagline (one line) + body (description).
	var tag := Label.new()
	tag.text = String(sc.get("tagline", ""))
	tag.add_theme_color_override("font_color", Color(0.86, 0.90, 0.95, 1.0))
	tag.add_theme_font_size_override("font_size", 13)
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(tag)

	var body := Label.new()
	body.text = String(sc.get("body", ""))
	body.add_theme_color_override("font_color", Color(0.70, 0.76, 0.85, 1.0))
	body.add_theme_font_size_override("font_size", 12)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(body)

	# Pick button.
	var pick := Button.new()
	pick.text = "Open this tank"
	pick.custom_minimum_size = Vector2(0, 40)
	pick.add_theme_font_size_override("font_size", 14)
	pick.pressed.connect(func(): _pick(sc))
	vb.add_child(pick)

	return card


func _pick(sc: Dictionary) -> void:
	# Emit a duplicate so the caller can't accidentally mutate the
	# global SCENARIOS constant.
	scenario_chosen.emit(sc.duplicate(true))
	queue_free()


func _cancel() -> void:
	canceled.emit()
	queue_free()


# Apply a chosen scenario's config dict to the TankConfig autoload. Idempotent
# field-by-field assignment — any keys not in the scenario are left alone.
static func apply_scenario(scenario: Dictionary, cfg: Node) -> void:
	if cfg == null:
		return
	var config: Dictionary = scenario.get("config", {})
	var lighting_slug: String = ""
	for key in config.keys():
		if key == "lighting_preset":
			lighting_slug = String(config[key])
			continue
		cfg.set(String(key), config[key])
	if lighting_slug != "" and cfg.has_method("apply_lighting_preset"):
		cfg.apply_lighting_preset(lighting_slug)
