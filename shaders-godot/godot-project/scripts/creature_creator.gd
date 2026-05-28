# Creature Creator.
#
# A sandbox modal that lets the player dial in the parameters of a fish,
# shrimp, snail, or plant - colors, body proportions, ornamentation, swim
# pattern - watch a live 3D preview update, then drop a batch (1 / 3 / 5)
# of that exact design straight into the active tank.
#
# The preview reuses the same isolated-SubViewport pattern as the Life
# Library: an own-world viewport renders the actual creature class
# (Fish / Shrimp / Plant) or a small voxel shell (snail) built from the
# current genome dict. Spawning routes through World.spawn_library_entry()
# which already knows how to place every organism type.

extends PanelContainer

# Preview world tuning -------------------------------------------------------
const PREVIEW_SIZE := Vector2i(360, 360)
const PREVIEW_CAM_DISTANCE: float = 4.0
const PREVIEW_CAM_HEIGHT: float = 0.6
const AUTO_ORBIT_SPEED: float = 0.45
const DRAG_SENSITIVITY: float = 0.012
const PREVIEW_FRAME_INTERVAL: float = 1.0 / 12.0
const SPHERE_RADIUS: float = 1.55
const SHRIMP_PREVIEW_SCALE: float = 2.8
const SNAIL_PREVIEW_SCALE: float = 1.6

enum Kind { FISH, SHRIMP, SNAIL, PLANT, FLOATING }

const SWIM_PATTERNS: Array = [
	["School", "school"], ["Shoal", "shoal"], ["Dart", "dart"],
	["Hover", "hover"], ["Cruise", "cruise"], ["Meander", "meander"],
	["Shuffle", "shuffle"],
]
const BODY_SHAPES: Array = [
	["Fusiform (torpedo)", "fusiform"], ["Compressed (disc)", "compressed"],
	["Globiform (round)", "globiform"], ["Anguilliform (eel)", "anguilliform"],
]
const TAIL_SHAPES: Array = [
	["Forked", 0], ["Fan", 1], ["Lyre", 2], ["Square", 3],
]
const PATTERNS: Array = [
	["Solid", 0], ["Lateral stripe", 1], ["Spots", 2], ["Vertical bars", 3],
	["Two-tone band", 4], ["Rear wedge", 5],
]
const SHELL_SHAPES: Array = [
	["Turbo (round)", "turbo"], ["Trochus (cone)", "trochus"],
	["Nassarius (small)", "nassarius"], ["Apple (globose)", "apple"],
]
const LEAF_FORMS: Array = [
	["Ribbon", "ribbon"], ["Paddle", "paddle"], ["Lance", "lance"],
	["Needle", "needle"], ["Column", "column"],
]
const FLOAT_MORPHS: Array = [
	["Duckweed", "duckweed"], ["Frogbit", "frogbit"],
	["Salvinia", "salvinia"], ["Water lettuce", "water_lettuce"],
]

var _kind: int = Kind.FISH
# The live genome the controls edit. Colors stay as Color objects; they're
# consumed directly by each organism's init_genome().
var _genome: Dictionary = {}

# UI refs ---------------------------------------------------------------------
var _controls_root: VBoxContainer = null
var _status: Label = null
var _tab_buttons: Dictionary = {}

# Preview state ---------------------------------------------------------------
var _preview_viewport: SubViewport = null
var _preview_root: Node3D = null
var _preview_pivot: Node3D = null
var _preview_cam: Camera3D = null
var _preview_creature: Node3D = null
var _preview_texture_rect: TextureRect = null
var _preview_yaw: float = 0.6
var _preview_pitch: float = 0.1
# Per-kind camera framing so small creatures (snails, shrimp) fill the
# preview instead of floating tiny in the middle. Set in _select_kind.
var _cam_distance: float = PREVIEW_CAM_DISTANCE
var _cam_target_y: float = PREVIEW_CAM_HEIGHT * 0.3
var _preview_auto: bool = true
var _preview_dragging: bool = false
var _preview_drag_last: Vector2 = Vector2.ZERO
var _preview_frame_accum: float = 0.0

var _world: Node3D = null


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	_build_ui()
	_build_preview_world()
	_select_kind(Kind.FISH, true)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


# Open the creator focused on a specific organism type. Used by the guided
# walkthrough to jump straight to the right tab.
func open_to_kind(kind_str: String) -> void:
	var k: int = Kind.FISH
	match kind_str:
		"shrimp": k = Kind.SHRIMP
		"snail": k = Kind.SNAIL
		"plant": k = Kind.PLANT
		_: k = Kind.FISH
	if not visible:
		open()
	_select_kind(k, true)


func open() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 200
	set_process(true)
	_resume_preview_rendering()
	_reload_preview()


func close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	_pause_preview_rendering()


# ---- UI construction --------------------------------------------------------

func _build_ui() -> void:
	custom_minimum_size = Vector2(800, 560)
	PanelTheme.apply_panel_chrome(self)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)

	var title := Label.new()
	title.text = "✦ CREATURE CREATOR ✦"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color8(120, 230, 200))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "design a custom organism, then stock the tank with it"
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", Color8(180, 200, 225))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(subtitle)

	# Type tabs.
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 6)
	outer.add_child(tabs)
	_add_tab(tabs, Kind.FISH, "🐟 Fish")
	_add_tab(tabs, Kind.SHRIMP, "🦐 Shrimp")
	_add_tab(tabs, Kind.SNAIL, "🐌 Snail")
	_add_tab(tabs, Kind.PLANT, "🌿 Plant")
	_add_tab(tabs, Kind.FLOATING, "🪷 Floating")

	outer.add_child(PanelTheme.make_rule())

	# Body: preview on the left, scrollable controls on the right.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)

	var preview_frame := PanelContainer.new()
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.04, 0.05, 0.09, 0.95)
	pstyle.border_color = Color8(80, 200, 190)
	pstyle.set_border_width_all(2)
	pstyle.set_corner_radius_all(8)
	preview_frame.add_theme_stylebox_override("panel", pstyle)
	preview_frame.custom_minimum_size = Vector2(300, 300)
	preview_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_frame.size_flags_stretch_ratio = 1.0
	body.add_child(preview_frame)

	_preview_texture_rect = TextureRect.new()
	_preview_texture_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_texture_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_texture_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview_texture_rect.gui_input.connect(_on_preview_input)
	preview_frame.add_child(_preview_texture_rect)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.25
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)

	_controls_root = VBoxContainer.new()
	_controls_root.add_theme_constant_override("separation", 6)
	_controls_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_controls_root)

	outer.add_child(PanelTheme.make_rule())

	_status = Label.new()
	_status.text = "Pick a type and tune the sliders."
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Color8(140, 240, 160))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(_status)

	# Footer.
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	outer.add_child(footer)
	var randomize := PanelTheme.make_secondary_button("🎲 Randomize")
	randomize.pressed.connect(_randomize)
	footer.add_child(randomize)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	for n in [1, 3, 5]:
		var add_btn := PanelTheme.make_primary_button("Add %d" % n)
		add_btn.pressed.connect(_add_to_tank.bind(n))
		footer.add_child(add_btn)
	var close_btn := PanelTheme.make_secondary_button("Close")
	close_btn.pressed.connect(close)
	footer.add_child(close_btn)


func _add_tab(parent: Node, kind: int, label: String) -> void:
	var b := Button.new()
	b.text = label
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(110, 32)
	b.pressed.connect(func(): _select_kind(kind))
	parent.add_child(b)
	_tab_buttons[kind] = b


func _select_kind(kind: int, force: bool = false) -> void:
	if kind == _kind and not force:
		return
	_kind = kind
	for k in _tab_buttons.keys():
		(_tab_buttons[k] as Button).button_pressed = (k == kind)
	# Frame the camera for the creature's size so it fills the preview.
	match kind:
		Kind.SHRIMP:
			_cam_distance = 2.7
			_cam_target_y = 0.05
		Kind.SNAIL:
			_cam_distance = 2.2
			_cam_target_y = 0.0
		Kind.PLANT:
			_cam_distance = 4.3
			_cam_target_y = 0.55
		Kind.FLOATING:
			_cam_distance = 2.4
			_cam_target_y = 0.0
		_:
			_cam_distance = 3.6
			_cam_target_y = PREVIEW_CAM_HEIGHT * 0.3
	_genome = _default_genome_for(kind)
	_rebuild_controls()
	_apply_preview_camera()
	_reload_preview()


# ---- Per-type default genomes ----------------------------------------------

func _default_genome_for(kind: int) -> Dictionary:
	match kind:
		Kind.SHRIMP:
			return {
				"base_color": Color8(220, 80, 80),
				"accent_color": Color8(255, 235, 205),
				"adult_voxel_scale": 0.12,
				"max_age_s": 360.0,
				"max_speed": 0.9,
				"body_length_factor": 1.0,
				"claw_size": 0.25,
				"defense_spines": 0.0,
				"toxin_level": 0.0,
				"is_cleaner": false,
			}
		Kind.SNAIL:
			return {
				"shell_color": Color8(150, 95, 55),
				"shell_accent_color": Color8(95, 55, 30),
				"body_color": Color8(60, 44, 32),
				"shell_size": 1.0,
				"shell_shape": "turbo",
				"shell_spines": 0.0,
				"toxin_level": 0.0,
				"crawl_speed": 1.0,
				"appetite": 1.0,
				"max_age_s": 720.0,
			}
		Kind.PLANT:
			return {
				"max_height": 14.0,
				"growth_rate": 0.22,
				"sway_amplitude": 0.25,
				"leaf_form": "ribbon",
				"leaf_length": 5.0,
				"max_roots": 5.0,
				"_ramp_base": Color8(35, 120, 55),
				"_ramp_tip": Color8(155, 220, 95),
			}
		Kind.FLOATING:
			return {
				"morph": "frogbit",
				"leaf_size": 0.38,
				"leaf_count": 6.0,
				"root_length": 0.45,
				"spread_rate": 1.0,
				"base_color": Color8(65, 135, 65),
				"tip_color": Color8(125, 195, 100),
			}
		_:
			return {
				"base_color": Color8(70, 150, 230),
				"accent_color": Color8(245, 220, 90),
				"tail_color": Color8(245, 120, 60),
				"marking_color": Color8(250, 250, 250),
				"adult_voxel_scale": 0.18,
				"max_age_s": 240.0,
				"max_speed": 1.6,
				"schooling_strength": 1.0,
				"separation_radius": 0.55,
				"preferred_y": 4.0,
				"body_elongation": 1.0,
				"body_depth_factor": 1.0,
				"fin_length_factor": 1.0,
				"finnage": 1.0,
				"swim_pattern": "school",
				"body_shape": "fusiform",
				"tail_shape": 0,
				"pattern_type": 1,
				"bar_edged": false,
				"eye_spot": false,
				"ventral_feelers": false,
				"has_barbels": false,
				"armor_plates": false,
				"adipose_fin": false,
			}


# ---- Controls (rebuilt per type) -------------------------------------------

func _rebuild_controls() -> void:
	for c in _controls_root.get_children():
		c.queue_free()
	match _kind:
		Kind.FISH:    _build_fish_controls()
		Kind.SHRIMP:  _build_shrimp_controls()
		Kind.SNAIL:   _build_snail_controls()
		Kind.PLANT:   _build_plant_controls()
		Kind.FLOATING: _build_floating_controls()


func _build_fish_controls() -> void:
	_controls_root.add_child(PanelTheme.make_section("Colors"))
	_add_color("Body", "base_color")
	_add_color("Accent", "accent_color")
	_add_color("Tail", "tail_color")
	_add_color("Marking", "marking_color")
	_controls_root.add_child(PanelTheme.make_section("Body"))
	_add_slider("Size", "adult_voxel_scale", 0.10, 0.34, 0.01)
	_add_slider("Elongation", "body_elongation", 0.6, 1.6, 0.01)
	_add_slider("Depth", "body_depth_factor", 0.6, 1.8, 0.01)
	_add_slider("Fin length", "fin_length_factor", 0.6, 2.0, 0.01)
	_add_slider("Finnage (veil)", "finnage", 1.0, 2.0, 0.05)
	_add_slider("Max speed", "max_speed", 0.5, 2.6, 0.05)
	_add_slider("Preferred depth", "preferred_y", 1.8, 5.4, 0.1)
	_controls_root.add_child(PanelTheme.make_section("Form & pattern"))
	_add_dropdown("Swim pattern", "swim_pattern", SWIM_PATTERNS)
	_add_dropdown("Body shape", "body_shape", BODY_SHAPES)
	_add_dropdown("Tail shape", "tail_shape", TAIL_SHAPES)
	_add_dropdown("Pattern", "pattern_type", PATTERNS)
	_controls_root.add_child(PanelTheme.make_section("Ornamentation"))
	_add_check("Edged bars", "bar_edged")
	_add_check("Eye-spot", "eye_spot")
	_add_check("Ventral feelers", "ventral_feelers")
	_add_check("Barbels", "has_barbels")
	_add_check("Armor plates", "armor_plates")
	_add_check("Adipose fin", "adipose_fin")


func _build_shrimp_controls() -> void:
	_controls_root.add_child(PanelTheme.make_section("Colors"))
	_add_color("Body", "base_color")
	_add_color("Accent", "accent_color")
	_controls_root.add_child(PanelTheme.make_section("Body"))
	_add_slider("Size", "adult_voxel_scale", 0.06, 0.30, 0.01)
	_add_slider("Length", "body_length_factor", 0.75, 1.7, 0.01)
	_add_slider("Claw size", "claw_size", 0.0, 1.2, 0.02)
	_add_slider("Max speed", "max_speed", 0.4, 1.6, 0.05)
	_controls_root.add_child(PanelTheme.make_section("Defenses & role"))
	_add_slider("Defense spines", "defense_spines", 0.0, 1.0, 0.02)
	_add_slider("Toxin level", "toxin_level", 0.0, 1.0, 0.02)
	_add_check("Cleaner shrimp", "is_cleaner")


func _build_snail_controls() -> void:
	_controls_root.add_child(PanelTheme.make_section("Shell"))
	_add_color("Shell color", "shell_color")
	_add_color("Shell banding", "shell_accent_color")
	_add_slider("Shell size", "shell_size", 0.5, 1.6, 0.02)
	_add_dropdown("Shell shape", "shell_shape", SHELL_SHAPES)
	_add_slider("Shell spines", "shell_spines", 0.0, 1.0, 0.02)
	_add_slider("Toxin level", "toxin_level", 0.0, 1.0, 0.02)
	_controls_root.add_child(PanelTheme.make_section("Body & behavior"))
	_add_color("Body color", "body_color")
	_add_slider("Crawl speed", "crawl_speed", 0.4, 2.0, 0.05)
	_add_slider("Appetite", "appetite", 0.5, 1.8, 0.05)
	_add_slider("Lifespan (s)", "max_age_s", 300.0, 1200.0, 10.0, "%.0f")


func _build_plant_controls() -> void:
	_controls_root.add_child(PanelTheme.make_section("Foliage color"))
	_add_color("Base", "_ramp_base")
	_add_color("Tip", "_ramp_tip")
	_controls_root.add_child(PanelTheme.make_section("Growth"))
	_add_slider("Max height", "max_height", 4.0, 30.0, 1.0, "%.0f")
	_add_slider("Growth rate", "growth_rate", 0.06, 0.55, 0.01)
	_add_slider("Sway", "sway_amplitude", 0.0, 1.0, 0.02)
	_add_slider("Leaf length", "leaf_length", 1.0, 12.0, 1.0, "%.0f")
	_add_slider("Roots", "max_roots", 2.0, 12.0, 1.0, "%.0f")
	_controls_root.add_child(PanelTheme.make_section("Form"))
	_add_dropdown("Leaf form", "leaf_form", LEAF_FORMS)


func _build_floating_controls() -> void:
	_controls_root.add_child(PanelTheme.make_section("Floating plant"))
	_add_dropdown("Type", "morph", FLOAT_MORPHS)
	_add_color("Leaf color", "base_color")
	_add_color("Leaf tip", "tip_color")
	_add_slider("Leaf size", "leaf_size", 0.12, 0.7, 0.02)
	_add_slider("Leaf count", "leaf_count", 1.0, 9.0, 1.0, "%.0f")
	_add_slider("Root length", "root_length", 0.05, 1.4, 0.05)
	_add_slider("Spread rate", "spread_rate", 0.2, 2.5, 0.05)


# ---- Control widget builders -----------------------------------------------

func _add_slider(label: String, key: String, mn: float, mx: float,
		step: float, fmt: String = "%.2f") -> void:
	var vl := Label.new()
	var s: HSlider = PanelTheme.add_slider_row(_controls_root, label, mn, mx, step, vl)
	s.value = clampf(float(_genome.get(key, mn)), mn, mx)
	vl.text = fmt % s.value
	s.value_changed.connect(func(v: float):
		_genome[key] = v
		vl.text = fmt % v
		_on_param_changed())


func _add_dropdown(label: String, key: String, options: Array) -> void:
	var ob: OptionButton = PanelTheme.add_dropdown_row(_controls_root, label)
	var cur: Variant = _genome.get(key)
	for i in options.size():
		ob.add_item(String(options[i][0]))
		ob.set_item_metadata(i, options[i][1])
		if options[i][1] == cur:
			ob.select(i)
	ob.item_selected.connect(func(idx: int):
		_genome[key] = ob.get_item_metadata(idx)
		_on_param_changed())


func _add_check(label: String, key: String) -> void:
	var cb := CheckBox.new()
	cb.text = label
	cb.button_pressed = bool(_genome.get(key, false))
	cb.add_theme_color_override("font_color", PanelTheme.LABEL_FG)
	cb.toggled.connect(func(p: bool):
		_genome[key] = p
		_on_param_changed())
	_controls_root.add_child(cb)


func _add_color(label: String, key: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_controls_root.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(160, 0)
	l.add_theme_color_override("font_color", PanelTheme.LABEL_FG)
	row.add_child(l)
	var cp := ColorPickerButton.new()
	cp.custom_minimum_size = Vector2(0, 28)
	cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cp.edit_alpha = false
	cp.color = _genome.get(key, Color.WHITE)
	cp.color_changed.connect(func(c: Color):
		_genome[key] = c
		_on_param_changed())
	row.add_child(cp)


func _on_param_changed() -> void:
	_reload_preview()


# ---- Genome assembly --------------------------------------------------------

func _otype_string() -> String:
	match _kind:
		Kind.SHRIMP: return "shrimp"
		Kind.SNAIL:  return "snail"
		Kind.PLANT:  return "plant"
		Kind.FLOATING: return "plant"
		_:           return "fish"


# Build the genome dict handed to the spawner / preview. Strips editor-only
# keys (the plant ramp endpoints) and materialises derived fields.
func _current_genome() -> Dictionary:
	var g: Dictionary = _genome.duplicate(true)
	var otype: String = _otype_string()
	g["organism_type"] = otype
	match _kind:
		Kind.FISH:
			g["species"] = "custom_fish"
			g["_display_name"] = "Designer Fish"
		Kind.SHRIMP:
			g["species"] = "custom_shrimp"
			g["_display_name"] = "Designer Shrimp"
		Kind.SNAIL:
			g["species"] = "custom_snail"
			g["snail_name"] = "Designer Snail"
		Kind.PLANT:
			g["species"] = "custom_plant"
			g["plant_name"] = "Designer Plant"
			g["ramp_override"] = _plant_ramp()
			g.erase("_ramp_base")
			g.erase("_ramp_tip")
		Kind.FLOATING:
			g["floating"] = true
			g["species"] = "floating_" + String(g.get("morph", "duckweed"))
			g["plant_name"] = "Designer floating plant"
	return g


func _plant_ramp() -> Array:
	var base: Color = _genome.get("_ramp_base", Color8(35, 120, 55))
	var tip: Color = _genome.get("_ramp_tip", Color8(155, 220, 95))
	var ramp: Array = []
	for i in 6:
		ramp.append(base.lerp(tip, float(i) / 5.0))
	return ramp


# ---- Randomize --------------------------------------------------------------

func _randomize() -> void:
	match _kind:
		Kind.FISH:
			var h: float = randf()
			_genome["base_color"] = Color.from_hsv(h, randf_range(0.6, 1.0), randf_range(0.7, 1.0))
			_genome["accent_color"] = Color.from_hsv(fposmod(h + 0.5, 1.0), randf_range(0.6, 1.0), randf_range(0.8, 1.0))
			_genome["tail_color"] = Color.from_hsv(fposmod(h + 0.33, 1.0), randf_range(0.7, 1.0), randf_range(0.8, 1.0))
			_genome["marking_color"] = Color.from_hsv(fposmod(h + 0.15, 1.0), randf_range(0.3, 0.9), randf_range(0.85, 1.0))
			_genome["adult_voxel_scale"] = randf_range(0.12, 0.30)
			_genome["body_elongation"] = randf_range(0.7, 1.5)
			_genome["body_depth_factor"] = randf_range(0.7, 1.7)
			_genome["fin_length_factor"] = randf_range(0.7, 1.8)
			_genome["finnage"] = 1.0 if randf() < 0.6 else randf_range(1.2, 1.9)
			_genome["max_speed"] = randf_range(0.8, 2.4)
			_genome["preferred_y"] = randf_range(2.2, 5.2)
			_genome["swim_pattern"] = SWIM_PATTERNS[randi() % SWIM_PATTERNS.size()][1]
			_genome["body_shape"] = BODY_SHAPES[randi() % BODY_SHAPES.size()][1]
			_genome["tail_shape"] = TAIL_SHAPES[randi() % TAIL_SHAPES.size()][1]
			_genome["pattern_type"] = PATTERNS[randi() % PATTERNS.size()][1]
			_genome["bar_edged"] = randf() < 0.35
			_genome["eye_spot"] = randf() < 0.3
			_genome["ventral_feelers"] = randf() < 0.2
			_genome["has_barbels"] = randf() < 0.25
			_genome["armor_plates"] = randf() < 0.15
			_genome["adipose_fin"] = randf() < 0.35
		Kind.SHRIMP:
			_genome["base_color"] = Color.from_hsv(randf(), randf_range(0.5, 1.0), randf_range(0.7, 1.0))
			_genome["accent_color"] = Color.from_hsv(randf(), randf_range(0.2, 0.8), randf_range(0.85, 1.0))
			_genome["adult_voxel_scale"] = randf_range(0.07, 0.26)
			_genome["body_length_factor"] = randf_range(0.8, 1.6)
			_genome["claw_size"] = randf_range(0.0, 1.1)
			_genome["max_speed"] = randf_range(0.5, 1.5)
			_genome["defense_spines"] = randf_range(0.0, 1.0)
			_genome["toxin_level"] = randf_range(0.0, 1.0)
			_genome["is_cleaner"] = randf() < 0.4
		Kind.SNAIL:
			var sh: float = randf()
			_genome["shell_color"] = Color.from_hsv(sh, randf_range(0.4, 1.0), randf_range(0.6, 1.0))
			_genome["shell_accent_color"] = Color.from_hsv(fposmod(sh + randf_range(-0.1, 0.1), 1.0), randf_range(0.4, 1.0), randf_range(0.25, 0.7))
			_genome["body_color"] = Color.from_hsv(randf(), randf_range(0.2, 0.7), randf_range(0.2, 0.6))
			_genome["shell_size"] = randf_range(0.55, 1.55)
			_genome["shell_shape"] = SHELL_SHAPES[randi() % SHELL_SHAPES.size()][1]
			_genome["shell_spines"] = randf_range(0.0, 1.0)
			_genome["toxin_level"] = randf_range(0.0, 1.0)
			_genome["crawl_speed"] = randf_range(0.5, 1.8)
			_genome["appetite"] = randf_range(0.6, 1.6)
			_genome["max_age_s"] = float(randi_range(360, 1100))
		Kind.PLANT:
			_genome["_ramp_base"] = Color.from_hsv(randf_range(0.2, 0.45), randf_range(0.5, 1.0), randf_range(0.4, 0.8))
			_genome["_ramp_tip"] = Color.from_hsv(randf_range(0.12, 0.5), randf_range(0.4, 1.0), randf_range(0.7, 1.0))
			_genome["max_height"] = float(randi_range(6, 28))
			_genome["growth_rate"] = randf_range(0.1, 0.5)
			_genome["sway_amplitude"] = randf_range(0.05, 0.8)
			_genome["leaf_length"] = float(randi_range(2, 11))
			_genome["max_roots"] = float(randi_range(3, 11))
			_genome["leaf_form"] = LEAF_FORMS[randi() % LEAF_FORMS.size()][1]
		Kind.FLOATING:
			var fh: float = randf_range(0.22, 0.38)
			_genome["morph"] = FLOAT_MORPHS[randi() % FLOAT_MORPHS.size()][1]
			_genome["base_color"] = Color.from_hsv(fh, randf_range(0.45, 0.75), randf_range(0.4, 0.62))
			_genome["tip_color"] = Color.from_hsv(fposmod(fh - 0.03, 1.0), randf_range(0.4, 0.7), randf_range(0.62, 0.9))
			_genome["leaf_size"] = randf_range(0.16, 0.6)
			_genome["leaf_count"] = float(randi_range(2, 8))
			_genome["root_length"] = randf_range(0.15, 1.1)
			_genome["spread_rate"] = randf_range(0.5, 2.0)
	_rebuild_controls()
	_reload_preview()


# ---- Spawning into the tank -------------------------------------------------

func _resolve_world() -> void:
	if _world != null and is_instance_valid(_world):
		return
	_world = get_tree().current_scene.get_node_or_null("SubViewport/World")
	if _world == null:
		var found: Node = get_tree().root.find_child("World", true, false)
		if found is Node3D:
			_world = found


func _add_to_tank(count: int) -> void:
	_resolve_world()
	if _world == null or not _world.has_method("spawn_library_entry"):
		_status.text = "Tank not available right now."
		return
	var otype: String = _otype_string()
	var added: int = 0
	for i in count:
		if bool(_world.spawn_library_entry(_current_genome(), otype)):
			added += 1
	if added > 0:
		_status.text = "Added %d %s to the tank." % [added, _kind_plural(added)]
	else:
		_status.text = "Could not place any (tank may be full)."


func _kind_plural(n: int) -> String:
	match _kind:
		Kind.SHRIMP: return "shrimp"
		Kind.SNAIL:  return "snail" if n == 1 else "snails"
		Kind.PLANT:  return "plant" if n == 1 else "plants"
		Kind.FLOATING: return "floating plant" if n == 1 else "floating plants"
		_:           return "fish"


# ---- Live preview -----------------------------------------------------------

func _build_preview_world() -> void:
	_preview_viewport = SubViewport.new()
	_preview_viewport.size = PREVIEW_SIZE
	_preview_viewport.transparent_bg = true
	_preview_viewport.own_world_3d = true
	_preview_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

	_preview_root = Node3D.new()
	_preview_root.name = "PreviewRoot"
	_preview_viewport.add_child(_preview_root)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.04, 0.08, 1.0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.78, 0.85, 0.96, 1.0)
	e.ambient_light_energy = 0.9
	env.environment = e
	_preview_root.add_child(env)

	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.96, 0.88, 1.0)
	key.light_energy = 0.8
	key.transform = Transform3D(Basis().rotated(Vector3.RIGHT, -0.6).rotated(Vector3.UP, -0.7), Vector3.ZERO)
	_preview_root.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.5, 0.62, 0.88, 1.0)
	fill.light_energy = 0.35
	fill.transform = Transform3D(Basis().rotated(Vector3.RIGHT, 0.4).rotated(Vector3.UP, 2.6), Vector3.ZERO)
	_preview_root.add_child(fill)

	var sphere_mat := StandardMaterial3D.new()
	sphere_mat.albedo_color = Color(0.45, 0.65, 0.95, 0.08)
	sphere_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	sphere_mat.emission_enabled = true
	sphere_mat.emission = Color(0.30, 0.50, 0.80, 1.0)
	sphere_mat.emission_energy_multiplier = 0.35
	var sphere := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = SPHERE_RADIUS
	sphere_mesh.height = SPHERE_RADIUS * 2.0
	sphere_mesh.radial_segments = 32
	sphere_mesh.rings = 16
	sphere.mesh = sphere_mesh
	sphere.material_override = sphere_mat
	_preview_root.add_child(sphere)

	_preview_pivot = Node3D.new()
	_preview_pivot.name = "Pivot"
	_preview_root.add_child(_preview_pivot)

	_preview_cam = Camera3D.new()
	_preview_cam.fov = 35.0
	_preview_cam.near = 0.05
	_preview_cam.far = 50.0
	_preview_root.add_child(_preview_cam)
	_apply_preview_camera()


func _apply_preview_camera() -> void:
	if _preview_cam == null:
		return
	var x: float = sin(_preview_yaw) * cos(_preview_pitch) * _cam_distance
	var z: float = cos(_preview_yaw) * cos(_preview_pitch) * _cam_distance
	var y: float = sin(_preview_pitch) * _cam_distance + PREVIEW_CAM_HEIGHT
	var origin := Vector3(x, y, z)
	var target := Vector3(0, _cam_target_y, 0)
	_preview_cam.position = origin
	var dir := target - origin
	if dir.length_squared() < 0.0001:
		return
	_preview_cam.basis = Basis.looking_at(dir.normalized(), Vector3.UP)


func _clear_preview_creature() -> void:
	if _preview_creature != null and is_instance_valid(_preview_creature):
		_preview_creature.queue_free()
	_preview_creature = null


func _reload_preview() -> void:
	if _preview_pivot == null or not visible:
		return
	_clear_preview_creature()
	var g: Dictionary = _current_genome()
	match _kind:
		Kind.SHRIMP: _preview_creature = _spawn_preview_shrimp(g)
		Kind.SNAIL:  _preview_creature = _spawn_preview_snail(g)
		Kind.PLANT:  _preview_creature = _spawn_preview_plant(g)
		Kind.FLOATING: _preview_creature = _spawn_preview_floating(g)
		_:           _preview_creature = _spawn_preview_fish(g)
	_request_preview_frame()


func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)


func _spawn_preview_fish(g: Dictionary) -> Node3D:
	var f := Fish.new()
	_preview_pivot.add_child(f)
	f.position = Vector3.ZERO
	g.erase("preferred_y_frac")
	f.init_genome(g)
	f.maturity = Fish.MATURITY_ADULT
	f.scale = Vector3.ONE
	f.target_velocity = Vector3.ZERO
	f.speed = 0.0
	f.heading = Vector3(3, 0, -1)
	f.basis = Basis.looking_at(Vector3(0, 0, -1), Vector3.UP)
	_freeze(f)
	return f


func _spawn_preview_shrimp(g: Dictionary) -> Node3D:
	var s := Shrimp.new()
	_preview_pivot.add_child(s)
	s.maturity = Shrimp.MATURITY_ADULT
	s.init_genome(g)
	s.position = Vector3(0, 0.05, 0)
	s.scale = Vector3.ONE * SHRIMP_PREVIEW_SCALE
	s.velocity = Vector3.ZERO
	s.speed = 0.0
	s.heading = Vector3(0, 0, -1)
	_freeze(s)
	return s


func _spawn_preview_plant(g: Dictionary) -> Node3D:
	var p := Plant.new()
	_preview_pivot.add_child(p)
	p.position = Vector3(0, -0.7, 0)
	var ramp: Variant = g.get("ramp_override", [])
	if ramp is Array and (ramp as Array).size() == 6:
		p.ramp_override = (ramp as Array).duplicate()
	p.init(mini(6, int(g.get("max_height", 8))), {
		"max_height": int(g.get("max_height", 12)),
		"growth_rate": float(g.get("growth_rate", 0.18)),
		"sway_amplitude": float(g.get("sway_amplitude", 0.25)),
		"leaf_form": String(g.get("leaf_form", "ribbon")),
		"leaf_length": int(g.get("leaf_length", 4)),
	})
	_freeze(p)
	return p


func _spawn_preview_floating(g: Dictionary) -> Node3D:
	var fp := FloatingPlant.new()
	_preview_pivot.add_child(fp)
	fp.position = Vector3(0, 0.1, 0)
	# Scale up so the small surface plant fills the preview sphere.
	fp.scale = Vector3.ONE * 2.6
	fp.init_genome(g)
	return fp


# Snail: a plain Node3D with a small voxel shell (do NOT attach snail.gd —
# its _process would crawl the mesh out of the preview sphere).
func _spawn_preview_snail(g: Dictionary) -> Node3D:
	var sn := Node3D.new()
	sn.name = "PreviewSnail"
	_preview_pivot.add_child(sn)
	sn.position = Vector3(0, 0.0, 0)
	sn.rotation.y = PI * 0.5
	sn.scale = Vector3.ONE * SNAIL_PREVIEW_SCALE
	var shell_color: Color = g.get("shell_color", Color8(150, 95, 55))
	var shell_size: float = float(g.get("shell_size", 1.0))
	var shell_shape: String = String(g.get("shell_shape", "turbo"))
	var accent_v: Variant = g.get("shell_accent_color", null)
	var shell_dark: Color = accent_v if (accent_v is Color and (accent_v as Color).a > 0.5) \
		else shell_color.darkened(0.22)
	var body_v: Variant = g.get("body_color", null)
	var body_color: Color = body_v if body_v is Color else Color8(44, 31, 21)
	var shell_mat := VoxelMat.make(shell_color)
	var shell_dark_mat := VoxelMat.make(shell_dark)
	var body_mat := VoxelMat.make(body_color)
	match shell_shape:
		"trochus":
			for i in 6:
				var y: float = 0.04 + i * 0.045 * shell_size
				var s: float = (0.18 - i * 0.025) * shell_size
				_snail_box(sn, Vector3(0, y, 0), Vector3(s, s * 0.85, s),
					shell_mat if (i & 1) == 0 else shell_dark_mat)
		"nassarius":
			_snail_box(sn, Vector3.ZERO,
				Vector3(0.14 * shell_size, 0.08 * shell_size, 0.18 * shell_size), shell_mat)
		"apple":
			_snail_box(sn, Vector3(0, 0.05 * shell_size, 0.0),
				Vector3(0.24 * shell_size, 0.21 * shell_size, 0.24 * shell_size), shell_mat)
			_snail_box(sn, Vector3(0, 0.17 * shell_size, -0.04 * shell_size),
				Vector3(0.12 * shell_size, 0.10 * shell_size, 0.12 * shell_size), shell_dark_mat)
		_:
			for i in 4:
				var ang: float = i * 0.7
				var r: float = (0.05 + i * 0.06) * shell_size
				var s2: float = (0.16 - i * 0.02) * shell_size
				_snail_box(sn, Vector3(cos(ang) * r, sin(ang) * r, 0.0),
					Vector3(s2, s2, s2), shell_mat if (i & 1) == 0 else shell_dark_mat)
	# Shell spines: small protruding dark spikes.
	var spines: float = float(g.get("shell_spines", 0.0))
	if spines > 0.05:
		for i in 4:
			var a: float = i * (PI * 0.5)
			_snail_box(sn, Vector3(cos(a) * 0.16 * shell_size, 0.06 * shell_size, sin(a) * 0.16 * shell_size),
				Vector3(0.03, 0.04 + 0.08 * spines, 0.03) * shell_size, shell_dark_mat)
	var foot_size: Vector3 = Vector3(0.24 * shell_size, 0.06 * shell_size, 0.16 * shell_size)
	_snail_box(sn, Vector3(0, -0.12 * shell_size, 0), foot_size, body_mat)
	return sn


func _snail_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelMat.get_box(size)
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


# ---- Preview rendering control ----------------------------------------------

func _process(dt: float) -> void:
	if not visible:
		return
	if _preview_auto:
		_preview_frame_accum += dt
		if _preview_frame_accum >= PREVIEW_FRAME_INTERVAL:
			_preview_frame_accum = 0.0
			_preview_yaw -= PREVIEW_FRAME_INTERVAL * AUTO_ORBIT_SPEED
			_apply_preview_camera()
			_request_preview_frame()


func _resume_preview_rendering() -> void:
	if _preview_viewport == null:
		return
	if _preview_viewport.get_parent() != self:
		add_child(_preview_viewport)
		move_child(_preview_viewport, 0)
	if _preview_texture_rect != null:
		_preview_texture_rect.texture = _preview_viewport.get_texture()
	_apply_preview_camera()
	_preview_frame_accum = 0.0
	_request_preview_frame()


func _pause_preview_rendering() -> void:
	if _preview_viewport == null:
		return
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _preview_viewport.get_parent() == self:
		remove_child(_preview_viewport)


func _request_preview_frame() -> void:
	if _preview_viewport == null:
		return
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_preview_dragging = mb.pressed
			_preview_drag_last = mb.position
			if mb.pressed:
				_preview_auto = false
	elif event is InputEventMouseMotion and _preview_dragging:
		var mm := event as InputEventMouseMotion
		var delta: Vector2 = mm.position - _preview_drag_last
		_preview_drag_last = mm.position
		_preview_yaw -= delta.x * DRAG_SENSITIVITY
		_preview_pitch = clampf(_preview_pitch + delta.y * DRAG_SENSITIVITY, -1.2, 1.2)
		_apply_preview_camera()
		_request_preview_frame()
