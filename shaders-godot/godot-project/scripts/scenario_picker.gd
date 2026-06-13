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
			"cycle_start_mode": "fresh",
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
			"co2_level": 0.3,
			"light_spectrum": 0.55,
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
			"co2_level": 0.6,
			"light_spectrum": 0.35,
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
			"vessel_preset": "column_blackwater",
			"light_fixture": "spotlight",
			"environment_preset": "dark_cabinet",
			"lighting_preset": "dim_warm",
			"co2_level": 0.0,
			"light_spectrum": 0.80,
		},
	},
	{
		"id": "reef",
		"name": "Coral Reef Cube",
		"tagline": "Cube tank · ocean sand · corals + clams · bleaching + night biolum",
		"body": "Saltwater rimless cube (7×7 footprint, 7 tall — equal sides for a proper coral-cube aesthetic). Ocean-sand substrate spawns corals, anemones, clams, sponges instead of plants. Coral tips pulse + bleach under heat stress + glow in sync at night; anemones ribbon-wave. Mixed reef fish — each individual rolls a unique tropical morph (clownfish, tangs, chromis, anthias).",
		"accent_color": Color8(255, 150, 110),
		"config": {
			"tank_preset": "reef",
			"substrate_type": "ocean_sand",
			"aeration_type": "stick",
			"vessel_preset": "reef_cube",
			"light_fixture": "spotlight",
			"environment_preset": "sunny_window",
			"lighting_preset": "reef",
			"co2_level": 0.0,
			"light_spectrum": 0.20,
			"cycle_start_mode": "established",
			"light_warmth": 0.72,
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
			"co2_level": 0.2,
			"light_spectrum": 0.50,
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
			"co2_level": 0.0,
			"light_spectrum": 0.45,
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
			"cycle_start_mode": "established",
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
			"co2_level": 0.6,
			"light_spectrum": 0.60,
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
			"co2_level": 0.0,
			"light_spectrum": 0.65,
		},
	},
	# ---- New scenarios (added with the plant-realism + AI pass) ----
	{
		"id": "shrimp_sanctuary",
		"name": "Shrimp Sanctuary",
		"tagline": "Small planted box · cherry colony · no fish predators",
		"body": "Nano shrimp-focused tank — small footprint (5×4×5), dense Monte Carlo carpet + bucephalandra on small stones, Christmas moss on a tiny driftwood branch. No predator fish, just a heavy cherry shrimp colony with amano cleaners + a few snails. Eco-complete fertile substrate, gentle disk aeration, planted-spectrum LED for the carpet.",
		"accent_color": Color8(220, 90, 110),
		"config": {
			"tank_preset": "polyp_lab",
			"substrate_type": "eco_complete",
			"aeration_type": "disk",
			"tank_shape": "box",
			"tank_half_w": 5.0,
			"tank_half_d": 4.0,
			"tank_height": 5.0,
			"water_surface_fraction": 0.94,
			"substrate_depth_fraction": 0.24,
			"light_fixture": "bar",
			"environment_preset": "bedroom_desk",
			"lighting_preset": "planted",
			"co2_level": 0.45,
			"light_spectrum": 0.55,
		},
	},
	{
		"id": "dutch_competition",
		"name": "Dutch Competition",
		"tagline": "Wide tank · pressurized CO2 · red-plant heaven",
		"body": "Aquascaping-competition Dutch street. Wide footprint (10×4×8) showcases parallel rows of red plants — Rotala H'ra, Ludwigia Super Red, Alternanthera reineckii — vivid against deep green Crypts. High CO2 + warm-spectrum bulb push the reds. Filter for flow, aquasoil substrate. Centerpiece fish: a small cardinal tetra school + corydoras team to keep the carpet clean.",
		"accent_color": Color8(230, 110, 90),
		"config": {
			"tank_preset": "tetra_school",
			"substrate_type": "aquasoil",
			"aeration_type": "filter",
			"tank_shape": "box",
			"tank_half_w": 10.0,
			"tank_half_d": 4.0,
			"tank_height": 8.0,
			"water_surface_fraction": 0.94,
			"substrate_depth_fraction": 0.22,
			"light_fixture": "bar",
			"environment_preset": "sunny_window",
			"lighting_preset": "planted",
			"co2_level": 0.85,
			"light_spectrum": 0.75,
		},
	},
	{
		"id": "nano_reef",
		"name": "Nano Reef",
		"tagline": "Tiny cube · high warmth · bleaching tutorial tank",
		"body": "Pico-reef cube (4×4×5). Warm LEDs + minimal aeration — corals glow at night but heat stress can bleach colonies if you don't manage warmth. One clownfish hosts in anemones. Turn the heater off in the lights panel to watch warmth drop near the rod.",
		"accent_color": Color8(255, 175, 95),
		"config": {
			"tank_preset": "reef",
			"substrate_type": "ocean_sand",
			"aeration_type": "none",
			"tank_shape": "cube",
			"tank_half_w": 4.0,
			"tank_half_d": 4.0,
			"tank_height": 5.0,
			"water_surface_fraction": 0.94,
			"substrate_depth_fraction": 0.16,
			"light_fixture": "spotlight",
			"environment_preset": "bedroom_desk",
			"lighting_preset": "reef",
			"co2_level": 0.0,
			"light_spectrum": 0.20,
			"cycle_start_mode": "established",
			"light_warmth": 0.82,
			"heater_enabled": false,
		},
	},
	# ---- Wildcard: AI-or-random tank generation ----
	# When AIDirector is enabled + connected, this scenario opens a text
	# input dialog ("Describe your dream tank…") and asks Ollama to design
	# a coherent set of TankConfig overrides. Without AI it rolls a random
	# valid combination from constrained pools. The "config" dict here is
	# only used as a fallback if both AI and random paths fail; normally
	# the scenario chosen handler overwrites it with the generated config
	# before applying.
	{
		"id": "wildcard",
		"name": "✨ Surprise Me",
		"tagline": "Random tank — or AI-designed if Ollama is connected",
		"body": "Roll the dice on a fresh tank. If you have AI enabled, this asks Ollama to design a coherent tank around a short prompt you type in ('zen carpet only', 'chaotic alien biosphere', 'red plant showcase'). Otherwise it picks a valid combination at random — substrate, shape, dimensions, stocking, lighting — that won't crash but might surprise you.",
		"accent_color": Color8(220, 200, 255),
		"is_wildcard": true,
		"config": {
			"tank_preset": "community",
			"substrate_type": "aquasoil",
			"aeration_type": "filter",
			"tank_shape": "box",
			"tank_half_w": 8.0,
			"tank_half_d": 4.0,
			"tank_height": 7.0,
			"water_surface_fraction": 0.93,
			"substrate_depth_fraction": 0.22,
			"light_fixture": "bar",
			"environment_preset": "bedroom_desk",
			"lighting_preset": "cozy_shop",
		},
	},
]


# Pool of valid options the wildcard random path samples from. Tuned so
# every combination produces a coherent (non-broken) tank.
const _WILD_SUBSTRATES: Array = ["aquasoil", "sand", "eco_complete", "inert_gravel"]
const _WILD_SHAPES: Array = ["box", "cylinder", "cube", "hex"]
const _WILD_PRESETS: Array = ["classic_community", "community", "tetra_school",
	"showcase", "apex_tank", "blackwater_biotope", "cichlid_pairs", "polyp_lab"]
const _WILD_AERATIONS: Array = ["filter", "disk", "stick", "none"]
const _WILD_LIGHTING: Array = ["planted", "cozy_shop", "sunny", "dim_warm", "reef"]
const _WILD_ENVS: Array = ["bedroom_desk", "sunny_window", "dark_cabinet", "forest_window"]


# Roll a random scenario config. Picks coherent values from the pools
# above and stamps them into a fresh config Dictionary. Tank dimensions
# are constrained to a sensible footprint so we don't spawn a 1×40×1
# noodle. Saltwater substrate forces reef preset to avoid plants-on-
# coral-sand mismatch.
static func random_wildcard_config() -> Dictionary:
	var sub: String = _WILD_SUBSTRATES[randi() % _WILD_SUBSTRATES.size()]
	# 20% chance to upgrade to saltwater reef.
	if randf() < 0.2:
		sub = "ocean_sand"
	var preset: String = "reef" if sub == "ocean_sand" \
		else _WILD_PRESETS[randi() % _WILD_PRESETS.size()]
	var shape: String = _WILD_SHAPES[randi() % _WILD_SHAPES.size()]
	# Dimensions: small to large, but always plausible for the shape.
	var half_w: float = randf_range(4.5, 11.0)
	var half_d: float = randf_range(3.5, 7.0) if shape == "box" else half_w
	var height: float = randf_range(5.0, 9.0)
	# CO2 + spectrum pair sensibly: high CO2 + warm spectrum for planted,
	# zero CO2 + cool spectrum for reef.
	var co2: float = 0.0 if sub == "ocean_sand" else randf_range(0.0, 0.9)
	var spectrum: float = 0.25 if sub == "ocean_sand" else randf_range(0.4, 0.8)
	return {
		"tank_preset": preset,
		"substrate_type": sub,
		"aeration_type": _WILD_AERATIONS[randi() % _WILD_AERATIONS.size()],
		"tank_shape": shape,
		"tank_half_w": half_w,
		"tank_half_d": half_d,
		"tank_height": height,
		"water_surface_fraction": randf_range(0.88, 0.95),
		"substrate_depth_fraction": randf_range(0.16, 0.26),
		"light_fixture": "spotlight" if randf() < 0.4 else "bar",
		"environment_preset": _WILD_ENVS[randi() % _WILD_ENVS.size()],
		"lighting_preset": _WILD_LIGHTING[randi() % _WILD_LIGHTING.size()],
		"co2_level": co2,
		"light_spectrum": spectrum,
	}


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
	PanelTheme.as_serif(title, PanelTheme.SIZE_TITLE, true)
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
	PanelTheme.as_serif(title, PanelTheme.SIZE_ITEM, true)
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
	# Wildcard branch — either roll random or pop a prompt for AI.
	if bool(sc.get("is_wildcard", false)):
		_pick_wildcard(sc)
		return
	# Emit a duplicate so the caller can't accidentally mutate the
	# global SCENARIOS constant.
	scenario_chosen.emit(sc.duplicate(true))
	queue_free()


# Wildcard click handler. If AIDirector is enabled + connected, pop a
# small prompt input dialog and ask Ollama to design a tank around the
# user's description. Otherwise (or if AI fails) generate a random valid
# combination via random_wildcard_config().
func _pick_wildcard(sc: Dictionary) -> void:
	var ai: Node = get_node_or_null("/root/AIDirector")
	var ai_ready: bool = ai != null and bool(ai.enabled) \
		and int(ai.conn_state) == int(ai.ConnState.OK)
	if not ai_ready:
		# Pure random path. Replace the config with a freshly-rolled one,
		# then emit as if the user had clicked a normal scenario card.
		var rolled: Dictionary = sc.duplicate(true)
		rolled["config"] = random_wildcard_config()
		rolled["name"] = "✨ Surprise tank"
		rolled["body"] = "Randomly generated. " + String(rolled["body"])
		scenario_chosen.emit(rolled)
		queue_free()
		return
	# AI path — pop a tiny input dialog over the picker. The user types
	# a description, we ask Ollama to translate it into a config dict,
	# then emit. Falls back to random on any failure.
	_open_ai_prompt(sc, ai)


# Build a small text-input modal layered above the picker. On submit we
# call AIDirector to translate the prompt into a config dict; on cancel
# we drop back to the picker.
func _open_ai_prompt(sc: Dictionary, ai: Node) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(540, 0)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "✨ Describe your dream tank"
	PanelTheme.as_serif(title, PanelTheme.SIZE_SECTION, true)
	vb.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Ollama (%s) will design a tank around your description." % String(ai.model)
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(subtitle)
	var hint := Label.new()
	hint.text = "Examples: 'red plant showcase', 'zen carpet only', 'chaotic alien biosphere', 'shrimp paradise'."
	hint.add_theme_font_size_override("font_size", 10)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hint)

	var input := LineEdit.new()
	input.placeholder_text = "your tank vibe…"
	input.custom_minimum_size = Vector2(0, 32)
	vb.add_child(input)
	var status := Label.new()
	status.add_theme_font_size_override("font_size", 11)
	status.add_theme_color_override("font_color", Color8(180, 195, 220))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(status)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_END
	btns.add_theme_constant_override("separation", 8)
	vb.add_child(btns)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	btns.add_child(cancel_btn)
	var roll_btn := Button.new()
	roll_btn.text = "Skip AI — roll random"
	btns.add_child(roll_btn)
	var go_btn := Button.new()
	go_btn.text = "Design tank"
	btns.add_child(go_btn)

	# Cancel just removes the prompt overlay; user can pick another card.
	cancel_btn.pressed.connect(func():
		dim.queue_free()
		center.queue_free())
	# Skip AI → random path (same as the no-AI branch in _pick_wildcard).
	roll_btn.pressed.connect(func():
		var rolled: Dictionary = sc.duplicate(true)
		rolled["config"] = random_wildcard_config()
		rolled["name"] = "✨ Surprise tank"
		scenario_chosen.emit(rolled)
		queue_free())
	# Design via AI: send the prompt to AIDirector.design_tank.
	go_btn.pressed.connect(func():
		var prompt: String = input.text.strip_edges()
		if prompt == "":
			status.text = "Type a few words first, or hit 'Skip AI'."
			return
		status.add_theme_color_override("font_color", Color8(180, 195, 220))
		status.text = "Asking %s to design your tank…" % String(ai.model)
		go_btn.disabled = true
		_request_ai_design(sc, ai, prompt, status, go_btn))


# Fire the AI design request. AIDirector.design_tank emits a one-shot
# `tank_designed(config)` signal back when the LLM response lands; we
# subscribe with CONNECT_ONE_SHOT so the picker doesn't accumulate
# listeners across retries.
func _request_ai_design(sc: Dictionary, ai: Node, prompt: String,
		status: Label, go_btn: Button) -> void:
	if not ai.has_method("design_tank"):
		# Fallback: roll random if the director doesn't have the helper.
		status.text = "AI design helper missing — rolling random instead."
		var rolled: Dictionary = sc.duplicate(true)
		rolled["config"] = random_wildcard_config()
		scenario_chosen.emit(rolled)
		queue_free()
		return
	if not ai.is_connected("tank_designed", _on_ai_tank_designed):
		ai.tank_designed.connect(_on_ai_tank_designed.bind(sc, status, go_btn), CONNECT_ONE_SHOT)
	ai.design_tank(prompt)


# AIDirector emits tank_designed when the LLM returns a config. Apply
# defaults for any missing fields (the LLM may omit some) before emitting.
func _on_ai_tank_designed(config: Dictionary, sc: Dictionary, status: Label, go_btn: Button) -> void:
	if config.is_empty():
		status.add_theme_color_override("font_color", Color8(230, 165, 120))
		status.text = "AI returned an empty design — rolling random instead."
		if go_btn != null:
			go_btn.disabled = false
		var rolled: Dictionary = sc.duplicate(true)
		rolled["config"] = random_wildcard_config()
		scenario_chosen.emit(rolled)
		queue_free()
		return
	var rolled2: Dictionary = sc.duplicate(true)
	# Merge AI-supplied fields over the wildcard defaults so any missing
	# keys (LLM partial output) get a safe baseline.
	var merged: Dictionary = rolled2.get("config", {}).duplicate(true)
	for k in config.keys():
		merged[k] = config[k]
	rolled2["config"] = merged
	rolled2["name"] = "✨ AI-designed tank"
	scenario_chosen.emit(rolled2)
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
	if config.has("vessel_preset") and cfg.has_method("apply_vessel_preset"):
		cfg.apply_vessel_preset(String(config["vessel_preset"]))
	for key in config.keys():
		if key == "vessel_preset":
			continue
		if key == "lighting_preset":
			lighting_slug = String(config[key])
			continue
		cfg.set(String(key), config[key])
	if lighting_slug != "" and cfg.has_method("apply_lighting_preset"):
		cfg.apply_lighting_preset(lighting_slug)
	if config.has("cycle_start_mode"):
		cfg.start_matured = (String(cfg.cycle_start_mode) == "established")
