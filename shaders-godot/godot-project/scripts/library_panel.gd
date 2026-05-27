# Species Library overlay.
#
# Full-screen modal that lists every species the player has discovered
# (per-tank + globally pinned), shows one selected species spinning inside
# a faint containment sphere in its own SubViewport, and exposes a genome
# readout. Per the design pass this is read-only — no live param sliders,
# no spawn buttons — those land in a later iteration.
#
# Layout:
#   [ tabs: This Tank | Global ]
#   ┌──────────┬─────────────────────┬───────────────┐
#   │ species  │      preview        │   genome      │
#   │   list   │   (SubViewport)     │   readout +   │
#   │          │   floating fish     │   pin button  │
#   │          │   in sphere         │               │
#   └──────────┴─────────────────────┴───────────────┘
#
# The preview SubViewport owns its own 3D world (so it doesn't share env /
# lighting with the main tank), runs at 384×384, and contains:
#   - a transparent containment sphere mesh
#   - a Pivot Node3D that we rotate (mouse drag / auto-orbit)
#   - one Fish instance, added to Pivot, never registered with a SimDriver
#     so it has no behavior — just its passive swim animation (fins + tail
#     wiggle from _motion_substep when sim is null).

extends PanelContainer

# Visual constants -----------------------------------------------------------

const PREVIEW_SIZE := Vector2i(384, 384)
const PREVIEW_CAM_DISTANCE: float = 4.0
const PREVIEW_CAM_HEIGHT: float = 0.6
const SPHERE_RADIUS: float = 1.55
const AUTO_ORBIT_SPEED: float = 0.35   # rad/s
const DRAG_SENSITIVITY: float = 0.012

# Tabs -----------------------------------------------------------------------

enum Scope { TANK, GLOBAL }
var _scope: int = Scope.TANK

# UI refs (resolved in _build_ui) --------------------------------------------

var _list_root: VBoxContainer = null
var _tab_tank: Button = null
var _tab_global: Button = null

var _preview_viewport: SubViewport = null
var _preview_root: Node3D = null
var _preview_pivot: Node3D = null
var _preview_fish: Fish = null
var _preview_cam: Camera3D = null
var _preview_texture_rect: TextureRect = null
var _preview_yaw: float = 0.6
var _preview_pitch: float = 0.05
var _preview_auto: bool = true
var _preview_dragging: bool = false
var _preview_drag_last: Vector2 = Vector2.ZERO

var _detail_name: Label = null
var _detail_source_badge: Label = null
var _detail_meta: Label = null
var _detail_swatches: HBoxContainer = null
var _detail_traits: VBoxContainer = null
var _pin_button: Button = null

var _selected_key: String = ""


func _ready() -> void:
	visible = false
	# Full-screen modal that catches input. Anchors set in main.tscn cover the
	# whole viewport; we just make sure mouse events stop here.
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_build_preview_world()
	var lib := get_node_or_null("/root/SpeciesLibrary")
	if lib != null:
		lib.library_changed.connect(_on_library_changed)


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh_list()
		set_process(true)
		_resume_preview_rendering()
	else:
		set_process(false)
		_pause_preview_rendering()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		var k: InputEventKey = event
		if k.keycode == KEY_ESCAPE:
			toggle()
			get_viewport().set_input_as_handled()


# ---- Layout -----------------------------------------------------------------


func _build_ui() -> void:
	# Background dim. We render a ColorRect filling the whole panel before any
	# content so the underlying tank reads as "behind glass" rather than fully
	# obscured — players still get a sense the sim is alive back there.
	PanelTheme.apply_panel_chrome(self)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(outer)

	# ---- Header (title + tabs + close) ----
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	outer.add_child(header)

	var title := PanelTheme.make_title("Species Library")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_tab_tank = _make_tab_button("This Tank", true)
	_tab_tank.pressed.connect(func(): _set_scope(Scope.TANK))
	header.add_child(_tab_tank)
	_tab_global = _make_tab_button("Global  📌", false)
	_tab_global.pressed.connect(func(): _set_scope(Scope.GLOBAL))
	header.add_child(_tab_global)

	var close_btn := PanelTheme.make_secondary_button("CLOSE")
	close_btn.pressed.connect(func(): toggle())
	header.add_child(close_btn)

	outer.add_child(PanelTheme.make_rule())

	# ---- Body (three columns) ----
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)

	body.add_child(_build_list_column())
	body.add_child(_build_preview_column())
	body.add_child(_build_detail_column())


# ---- Column 1: species list ----

func _build_list_column() -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(220, 0)
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)

	v.add_child(PanelTheme.make_section("Discovered"))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)

	_list_root = VBoxContainer.new()
	_list_root.add_theme_constant_override("separation", 4)
	_list_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_root)
	# Initial placeholder gets replaced on first _refresh_list call; we still
	# put one here so a panel that opens before _refresh_list (defensive) has
	# something readable in the list slot.
	var placeholder := Label.new()
	placeholder.text = "Loading…"
	placeholder.add_theme_color_override("font_color", PanelTheme.DIM_FG)
	placeholder.add_theme_font_size_override("font_size", 11)
	_list_root.add_child(placeholder)

	return v


# ---- Column 2: preview viewport ----

func _build_preview_column() -> Control:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)

	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.09, 0.95)
	style.border_color = PanelTheme.BORDER
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	frame.add_theme_stylebox_override("panel", style)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(frame)

	# We host the SubViewport off the visible tree so it renders in isolation,
	# and route its texture into a TextureRect inside the panel. This is the
	# same pattern as the PortalViewport in main.tscn.
	_preview_viewport = SubViewport.new()
	_preview_viewport.size = PREVIEW_SIZE
	_preview_viewport.transparent_bg = true
	_preview_viewport.own_world_3d = true
	_preview_viewport.msaa_3d = Viewport.MSAA_2X
	# Start disabled — panel opens hidden, no reason to render until toggle().
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# Parent to the panel itself; the SubViewport renders regardless of where
	# it sits in the canvas tree so this is safe.
	add_child(_preview_viewport)

	_preview_texture_rect = TextureRect.new()
	_preview_texture_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_texture_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_texture_rect.texture = _preview_viewport.get_texture()
	_preview_texture_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview_texture_rect.gui_input.connect(_on_preview_input)
	frame.add_child(_preview_texture_rect)

	# Controls strip beneath the preview.
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(controls)

	var auto := CheckBox.new()
	auto.text = "Auto-rotate"
	auto.button_pressed = _preview_auto
	auto.toggled.connect(func(p): _preview_auto = p)
	auto.add_theme_color_override("font_color", PanelTheme.LABEL_FG)
	controls.add_child(auto)

	var reset := PanelTheme.make_secondary_button("Reset View")
	reset.pressed.connect(_reset_preview_view)
	controls.add_child(reset)

	var hint := Label.new()
	hint.text = "drag preview to rotate"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", PanelTheme.DIM_FG)
	controls.add_child(hint)

	return v


# ---- Column 3: detail readout ----

func _build_detail_column() -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(260, 0)
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)

	_detail_name = Label.new()
	_detail_name.text = "Select a species"
	_detail_name.add_theme_font_size_override("font_size", 18)
	_detail_name.add_theme_color_override("font_color", PanelTheme.TITLE_FG)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_detail_name)

	_detail_source_badge = Label.new()
	_detail_source_badge.text = ""
	_detail_source_badge.add_theme_font_size_override("font_size", 11)
	_detail_source_badge.add_theme_color_override("font_color", PanelTheme.SECTION_FG)
	v.add_child(_detail_source_badge)

	_detail_swatches = HBoxContainer.new()
	_detail_swatches.add_theme_constant_override("separation", 4)
	v.add_child(_detail_swatches)

	v.add_child(PanelTheme.make_rule())
	v.add_child(PanelTheme.make_section("Genome"))

	_detail_traits = VBoxContainer.new()
	_detail_traits.add_theme_constant_override("separation", 2)
	v.add_child(_detail_traits)

	v.add_child(PanelTheme.make_rule())

	_detail_meta = Label.new()
	_detail_meta.text = ""
	_detail_meta.add_theme_font_size_override("font_size", 11)
	_detail_meta.add_theme_color_override("font_color", PanelTheme.DIM_FG)
	_detail_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_detail_meta)

	# Spacer pushes the pin button to the bottom.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)

	_pin_button = PanelTheme.make_primary_button("Pin to Global")
	_pin_button.pressed.connect(_on_pin_pressed)
	_pin_button.disabled = true
	v.add_child(_pin_button)
	return v


# ---- Preview 3D world -------------------------------------------------------

func _build_preview_world() -> void:
	if _preview_viewport == null:
		return
	_preview_root = Node3D.new()
	_preview_root.name = "PreviewRoot"
	_preview_viewport.add_child(_preview_root)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.04, 0.08, 1.0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.82, 0.95, 1.0)
	e.ambient_light_energy = 0.85
	e.glow_enabled = true
	e.glow_intensity = 0.6
	env.environment = e
	_preview_root.add_child(env)

	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.96, 0.88, 1.0)
	key.light_energy = 0.7
	key.transform = Transform3D(Basis().rotated(Vector3.RIGHT, -0.6).rotated(Vector3.UP, -0.7), Vector3.ZERO)
	_preview_root.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.5, 0.62, 0.88, 1.0)
	fill.light_energy = 0.35
	fill.transform = Transform3D(Basis().rotated(Vector3.RIGHT, 0.4).rotated(Vector3.UP, 2.6), Vector3.ZERO)
	_preview_root.add_child(fill)

	# Containment sphere — translucent, faint emission rim so it reads as a
	# physical glass orb rather than a flat overlay. The fish floats inside.
	var sphere_mat := StandardMaterial3D.new()
	sphere_mat.albedo_color = Color(0.45, 0.65, 0.95, 0.10)
	sphere_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	sphere_mat.emission_enabled = true
	sphere_mat.emission = Color(0.35, 0.55, 0.85, 1.0)
	sphere_mat.emission_energy_multiplier = 0.4
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
	var x: float = sin(_preview_yaw) * cos(_preview_pitch) * PREVIEW_CAM_DISTANCE
	var z: float = cos(_preview_yaw) * cos(_preview_pitch) * PREVIEW_CAM_DISTANCE
	var y: float = sin(_preview_pitch) * PREVIEW_CAM_DISTANCE + PREVIEW_CAM_HEIGHT
	_preview_cam.position = Vector3(x, y, z)
	_preview_cam.look_at(Vector3(0, PREVIEW_CAM_HEIGHT * 0.4, 0), Vector3.UP)


func _reset_preview_view() -> void:
	_preview_yaw = 0.6
	_preview_pitch = 0.05
	_preview_auto = true
	_apply_preview_camera()


# ---- Preview interaction ----

func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_preview_dragging = mb.pressed
			_preview_drag_last = mb.position
			if _preview_dragging:
				_preview_auto = false
	elif event is InputEventMouseMotion and _preview_dragging:
		var mm: InputEventMouseMotion = event
		var dx: float = mm.position.x - _preview_drag_last.x
		var dy: float = mm.position.y - _preview_drag_last.y
		_preview_drag_last = mm.position
		_preview_yaw -= dx * DRAG_SENSITIVITY
		_preview_pitch = clampf(_preview_pitch + dy * DRAG_SENSITIVITY, -1.2, 1.2)
		_apply_preview_camera()


func _process(dt: float) -> void:
	if not visible:
		return
	if _preview_auto:
		_preview_yaw -= dt * AUTO_ORBIT_SPEED
		_apply_preview_camera()


func _resume_preview_rendering() -> void:
	if _preview_viewport != null:
		_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _pause_preview_rendering() -> void:
	if _preview_viewport != null:
		_preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


# ---- List + scope -----------------------------------------------------------

func _set_scope(s: int) -> void:
	if _scope == s:
		return
	_scope = s
	_tab_tank.button_pressed = s == Scope.TANK
	_tab_global.button_pressed = s == Scope.GLOBAL
	_refresh_list()


func _make_tab_button(text: String, active: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = active
	b.add_theme_color_override("font_color", PanelTheme.LABEL_FG)
	b.add_theme_color_override("font_pressed_color", PanelTheme.TITLE_FG)
	b.add_theme_color_override("font_hover_color", PanelTheme.TITLE_FG)
	return b


func _on_library_changed() -> void:
	if visible:
		_refresh_list()


func _refresh_list() -> void:
	if _list_root == null:
		return
	for c in _list_root.get_children():
		c.queue_free()
	var entries: Array = _current_scope_entries()
	if entries.is_empty():
		var empty := Label.new()
		empty.text = (
			"No discoveries yet.\nBuy fish from the store, breed in the tank,\nor let founders settle in to populate."
			if _scope == Scope.TANK else
			"No global pins yet.\nOpen 'This Tank' and pin species you want to keep."
		)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", PanelTheme.DIM_FG)
		empty.add_theme_font_size_override("font_size", 11)
		_list_root.add_child(empty)
		_select_entry({})
		return
	# Sort by first_seen so newest discoveries float to the top — the player
	# just made something happen, that's what they want to see.
	entries.sort_custom(func(a, b):
		return int(a.get("first_seen_unix", 0)) > int(b.get("first_seen_unix", 0)))
	for entry in entries:
		_list_root.add_child(_make_list_item(entry))
	# Auto-select first entry if nothing currently selected, or the previously
	# selected one if it's still around.
	var keep: Dictionary = _find_entry_in_list(entries, _selected_key)
	if keep.is_empty():
		_select_entry(entries[0])
	else:
		_select_entry(keep)


func _current_scope_entries() -> Array:
	var lib := get_node_or_null("/root/SpeciesLibrary")
	if lib == null:
		return []
	return lib.get_tank_entries() if _scope == Scope.TANK else lib.get_global_entries()


func _find_entry_in_list(arr: Array, key: String) -> Dictionary:
	for e in arr:
		if e is Dictionary and String(e.get("species_key", "")) == key:
			return e
	return {}


func _make_list_item(entry: Dictionary) -> Control:
	var btn := Button.new()
	var key: String = String(entry.get("species_key", ""))
	var display: String = String(entry.get("display_name", "fish"))
	var source: String = String(entry.get("source", ""))
	var is_pin: bool = false
	var lib := get_node_or_null("/root/SpeciesLibrary")
	if lib != null and _scope == Scope.TANK:
		is_pin = lib.is_pinned(key)
	# Compact one-line label: NAME (source) + optional pin marker. We use a
	# button so the whole row is hittable; styling matches the side rails.
	var marker: String = " 📌" if is_pin else ""
	btn.text = "%s%s" % [display, marker]
	btn.tooltip_text = "source: %s\nspecies: %s" % [source, entry.get("species", "?")]
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 28)
	btn.add_theme_color_override("font_color", PanelTheme.LABEL_FG)
	btn.add_theme_color_override("font_hover_color", PanelTheme.TITLE_FG)
	btn.add_theme_color_override("font_pressed_color", PanelTheme.PRIMARY_FG)
	# Highlight the selected one.
	if key == _selected_key:
		var sel := StyleBoxFlat.new()
		sel.bg_color = Color(0.18, 0.32, 0.55, 0.5)
		sel.corner_radius_top_left = 4
		sel.corner_radius_top_right = 4
		sel.corner_radius_bottom_left = 4
		sel.corner_radius_bottom_right = 4
		sel.content_margin_left = 8
		sel.content_margin_right = 8
		sel.content_margin_top = 4
		sel.content_margin_bottom = 4
		btn.add_theme_stylebox_override("normal", sel)
	btn.pressed.connect(func(): _select_entry(entry))
	return btn


# ---- Detail panel -----------------------------------------------------------

func _select_entry(entry: Dictionary) -> void:
	if entry.is_empty():
		_selected_key = ""
		_detail_name.text = "Select a species"
		_detail_source_badge.text = ""
		_detail_meta.text = ""
		_clear_children(_detail_swatches)
		_clear_children(_detail_traits)
		_pin_button.disabled = true
		_clear_preview_fish()
		return

	_selected_key = String(entry.get("species_key", ""))
	var genome_raw: Dictionary = entry.get("genome", {})
	var genome: Dictionary = SpeciesLibrary.genome_from_serialisable(genome_raw)

	_detail_name.text = String(entry.get("display_name", "?"))
	var src: String = String(entry.get("source", ""))
	var src_label: String = {
		"founder": "Founder cohort",
		"store": "Store purchase",
		"evolved": "Bred in tank",
	}.get(src, src)
	var gen: int = int(entry.get("generation", 0))
	_detail_source_badge.text = "%s · gen %d · seen %d" % [
		src_label, gen, int(entry.get("count_seen", 1)),
	]

	_clear_children(_detail_swatches)
	_add_swatch(genome.get("base_color", Color.WHITE), 32)
	_add_swatch(genome.get("accent_color", Color.GRAY), 18)
	_add_swatch(genome.get("tail_color", genome.get("accent_color", Color.GRAY)), 18)

	_clear_children(_detail_traits)
	_add_trait("Species", String(genome.get("species", "?")))
	_add_trait("Swim", String(genome.get("swim_pattern", "?")))
	_add_trait("Body", String(genome.get("body_shape", "(default)")))
	_add_trait("Locomotion", _infer_locomotion(genome))
	_add_trait("Layer", _layer_label(float(genome.get("preferred_y", 3.5))))
	_add_trait("Size", "%.2f" % float(genome.get("adult_voxel_scale", 0.18)))
	_add_trait("Elongation", "%.2f" % float(genome.get("body_elongation", 1.0)))
	_add_trait("Depth", "%.2f" % float(genome.get("body_depth_factor", 1.0)))
	_add_trait("Schooling", "%.2f" % float(genome.get("schooling_strength", 1.0)))
	_add_trait("Max speed", "%.2f" % float(genome.get("max_speed", 1.8)))
	_add_trait("Herbivory", "%.2f" % float(genome.get("herbivory", 0.0)))
	_add_trait("Fecundity", "%.2f" % float(genome.get("fecundity", 0.7)))
	var traits_tags: Array[String] = []
	if bool(genome.get("has_barbels", false)):
		traits_tags.append("barbels")
	if bool(genome.get("armor_plates", false)):
		traits_tags.append("armored")
	if bool(genome.get("adipose_fin", false)):
		traits_tags.append("adipose fin")
	var mo: int = int(genome.get("mouth_orientation", 0))
	if mo > 0:
		traits_tags.append("sifter mouth")
	elif mo < 0:
		traits_tags.append("upturned mouth")
	if bool(genome.get("snail_predator", false)):
		traits_tags.append("snail predator")
	if bool(genome.get("algae_grazer", false)):
		traits_tags.append("algae grazer")
	if bool(genome.get("is_livebearer", false)):
		traits_tags.append("livebearer")
	if traits_tags.is_empty():
		_add_trait("Traits", "—")
	else:
		_add_trait("Traits", ", ".join(traits_tags))

	var first_unix: int = int(entry.get("first_seen_unix", 0))
	if first_unix > 0:
		_detail_meta.text = "First seen %s ago" % _format_elapsed(
			int(Time.get_unix_time_from_system()) - first_unix)
	else:
		_detail_meta.text = ""

	# Pin button reflects current pin state.
	var lib := get_node_or_null("/root/SpeciesLibrary")
	var pinned: bool = lib != null and lib.is_pinned(_selected_key)
	if _scope == Scope.GLOBAL:
		_pin_button.text = "Unpin from Global"
		_pin_button.disabled = false
	else:
		_pin_button.text = "Unpin from Global" if pinned else "Pin to Global"
		_pin_button.disabled = false

	_load_preview_fish(genome)


func _on_pin_pressed() -> void:
	var lib := get_node_or_null("/root/SpeciesLibrary")
	if lib == null or _selected_key == "":
		return
	if lib.is_pinned(_selected_key):
		lib.unpin_from_global(_selected_key)
	else:
		lib.pin_to_global(_selected_key)


# ---- Preview fish lifecycle -------------------------------------------------

func _clear_preview_fish() -> void:
	if _preview_fish != null and is_instance_valid(_preview_fish):
		_preview_fish.queue_free()
	_preview_fish = null


func _load_preview_fish(genome: Dictionary) -> void:
	_clear_preview_fish()
	if _preview_pivot == null or genome.is_empty():
		return
	var f := Fish.new()
	_preview_pivot.add_child(f)
	f.position = Vector3.ZERO
	# init_genome reads many keys; we feed it a duplicate so the original
	# library entry is never mutated by the side effects inside init_genome
	# (e.g. mixed_morphs rolls, sexual dimorphism overrides).
	var g: Dictionary = genome.duplicate(true)
	# Force an adult preview — fry are tiny and the player wants to see the
	# species at its display size.
	g.erase("preferred_y_frac")
	f.init_genome(g)
	f.maturity = Fish.MATURITY_ADULT
	f.scale = Vector3.ONE
	# Hold position: target_velocity stays zero, speed never accelerates, so
	# _motion_substep doesn't translate the fish but still ticks fin/tail
	# wiggle animations. We just need a known facing.
	f.target_velocity = Vector3.ZERO
	f.speed = 0.0
	f.heading = Vector3(0, 0, -1)
	f.look_at(f.position + Vector3(0, 0, -1), Vector3.UP)
	_preview_fish = f


# ---- Detail helpers ---------------------------------------------------------

func _add_swatch(c: Variant, width: int) -> void:
	var s := ColorRect.new()
	s.custom_minimum_size = Vector2(width, 28)
	if c is Color:
		s.color = c
	elif c is Array and (c as Array).size() >= 3:
		var a: Array = c
		s.color = Color(float(a[0]), float(a[1]), float(a[2]))
	else:
		s.color = Color.WHITE
	_detail_swatches.add_child(s)


func _add_trait(label: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", PanelTheme.SECTION_FG)
	l.custom_minimum_size = Vector2(96, 0)
	row.add_child(l)
	var v := Label.new()
	v.text = value
	v.add_theme_font_size_override("font_size", 11)
	v.add_theme_color_override("font_color", PanelTheme.VALUE_FG)
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	_detail_traits.add_child(row)


func _clear_children(parent: Node) -> void:
	for c in parent.get_children():
		c.queue_free()


func _layer_label(py: float) -> String:
	if py >= 4.6:
		return "top"
	if py <= 2.5:
		return "bottom"
	return "mid"


# Mirror fish.gd's locomotion selection so the readout matches what the fish
# actually does. Cheap duplication; pulling the rule out into a shared helper
# isn't worth coupling library_panel to fish.gd internals.
func _infer_locomotion(g: Dictionary) -> String:
	if g.has("locomotion_type"):
		return String(g["locomotion_type"])
	match String(g.get("body_shape", "")):
		"anguilliform":
			return "anguilliform"
		"globiform":
			return "ostraciiform"
		"compressed":
			return "labriform"
		_:
			return "subcarangiform"


func _format_elapsed(secs: int) -> String:
	if secs < 60:
		return "%ds" % secs
	if secs < 3600:
		return "%dm" % (secs / 60)
	if secs < 86400:
		return "%dh" % (secs / 3600)
	return "%dd" % (secs / 86400)
