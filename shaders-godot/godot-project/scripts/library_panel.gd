# Life Library overlay.
#
# Full-screen modal that lists every genotype the player has discovered
# across fish, shrimp, snails, and plants.
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
const SHRIMP_PREVIEW_SCALE: float = 2.8
const SNAIL_PREVIEW_SCALE: float = 1.6

# Tabs -----------------------------------------------------------------------

enum Scope { TANK, GLOBAL }
enum TypeFilter { ALL, FISH, SHRIMP, SNAIL, PLANT }
enum ViewMode { LIST, TREE }

var _scope: int = Scope.TANK
var _type_filter: int = TypeFilter.ALL
var _view_mode: int = ViewMode.LIST

# UI refs (resolved in _build_ui) --------------------------------------------

var _list_root: VBoxContainer = null
var _list_host: Control = null
var _lineage_layer: Control = null
var _row_by_key: Dictionary = {}
var _lineage_edges: Array = []
var _filter_all: Button = null
var _filter_fish: Button = null
var _filter_shrimp: Button = null
var _filter_snail: Button = null
var _filter_plant: Button = null
var _view_list_btn: Button = null
var _view_tree_btn: Button = null
var _list_panel: Control = null
var _tree_scroll: ScrollContainer = null
var _lineage_tree: LineageTreeView = null
var _tab_tank: Button = null
var _tab_global: Button = null

var _preview_viewport: SubViewport = null
var _preview_root: Node3D = null
var _preview_pivot: Node3D = null
var _preview_creature: Node3D = null
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
	_close_panel()
	_build_ui()
	_build_preview_world()
	_apply_mobile_layout()
	var lib := get_node_or_null("/root/SpeciesLibrary")
	if lib != null:
		lib.library_changed.connect(_on_library_changed)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if visible:
		return
	visible = true
	show()
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 200
	_apply_mobile_layout()
	_backfill_discoveries_from_tank()
	_refresh_list()
	set_process(true)
	_resume_preview_rendering()


func close() -> void:
	if not visible:
		_close_panel()
		return
	_close_panel()


func _close_panel() -> void:
	visible = false
	hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 0
	set_process(false)
	_pause_preview_rendering()
	if _preview_texture_rect != null:
		_preview_texture_rect.visible = false


func _apply_mobile_layout() -> void:
	if not (OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")):
		return
	# Full-screen on phones so the modal reads clearly and the preview
	# SubViewport cannot sit as a stray black rect in the corner.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_offsets_preset(Control.PRESET_FULL_RECT)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed:
		var k: InputEventKey = event
		if k.keycode == KEY_ESCAPE:
			close()
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

	var title := PanelTheme.make_title("Life Library")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_tab_tank = _make_tab_button("This Tank", true)
	_tab_tank.pressed.connect(func(): _set_scope(Scope.TANK))
	header.add_child(_tab_tank)
	_tab_global = _make_tab_button("Global  📌", false)
	_tab_global.pressed.connect(func(): _set_scope(Scope.GLOBAL))
	header.add_child(_tab_global)

	var close_btn := PanelTheme.make_secondary_button("CLOSE")
	close_btn.pressed.connect(close)
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
	v.custom_minimum_size = Vector2(240, 0)
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)

	v.add_child(PanelTheme.make_section("Discovered"))

	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 4)
	v.add_child(filter_row)
	_filter_all = _make_filter_button("All", true)
	_filter_all.pressed.connect(func(): _set_type_filter(TypeFilter.ALL))
	filter_row.add_child(_filter_all)
	_filter_fish = _make_filter_button("Fish", false)
	_filter_fish.pressed.connect(func(): _set_type_filter(TypeFilter.FISH))
	filter_row.add_child(_filter_fish)
	_filter_shrimp = _make_filter_button("Shrimp", false)
	_filter_shrimp.pressed.connect(func(): _set_type_filter(TypeFilter.SHRIMP))
	filter_row.add_child(_filter_shrimp)
	_filter_snail = _make_filter_button("Snails", false)
	_filter_snail.pressed.connect(func(): _set_type_filter(TypeFilter.SNAIL))
	filter_row.add_child(_filter_snail)
	_filter_plant = _make_filter_button("Plants", false)
	_filter_plant.pressed.connect(func(): _set_type_filter(TypeFilter.PLANT))
	filter_row.add_child(_filter_plant)

	var view_row := HBoxContainer.new()
	view_row.add_theme_constant_override("separation", 4)
	v.add_child(view_row)
	_view_list_btn = _make_filter_button("List", true)
	_view_list_btn.pressed.connect(func(): _set_view_mode(ViewMode.LIST))
	view_row.add_child(_view_list_btn)
	_view_tree_btn = _make_filter_button("Tree", false)
	_view_tree_btn.pressed.connect(func(): _set_view_mode(ViewMode.TREE))
	view_row.add_child(_view_tree_btn)

	_list_panel = VBoxContainer.new()
	_list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_panel.add_theme_constant_override("separation", 6)
	v.add_child(_list_panel)

	var lineage_hint := Label.new()
	lineage_hint.text = "Lines link offspring → parents"
	lineage_hint.add_theme_font_size_override("font_size", 9)
	lineage_hint.add_theme_color_override("font_color", PanelTheme.DIM_FG)
	_list_panel.add_child(lineage_hint)

	_list_host = Control.new()
	_list_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_host.custom_minimum_size = Vector2(0, 120)
	_list_panel.add_child(_list_host)

	_lineage_layer = Control.new()
	_lineage_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lineage_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lineage_layer.draw.connect(_draw_lineage_overlay)
	_list_host.add_child(_lineage_layer)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_host.add_child(scroll)

	_list_root = VBoxContainer.new()
	_list_root.add_theme_constant_override("separation", 4)
	_list_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_root)

	_tree_scroll = ScrollContainer.new()
	_tree_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_tree_scroll.visible = false
	v.add_child(_tree_scroll)

	_lineage_tree = LineageTreeView.new()
	_lineage_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lineage_tree.entry_selected.connect(_select_entry)
	_tree_scroll.add_child(_lineage_tree)

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
	# Do not parent until the panel opens — SubViewport has no `visible`
	# property, and an idle viewport in the tree can show as a black square
	# on Android. _resume_preview_rendering() adds it when needed.

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
	if _preview_viewport == null:
		return
	if _preview_viewport.get_parent() != self:
		add_child(_preview_viewport)
		move_child(_preview_viewport, 0)
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if _preview_texture_rect != null:
		_preview_texture_rect.texture = _preview_viewport.get_texture()
		_preview_texture_rect.visible = true


func _pause_preview_rendering() -> void:
	if _preview_viewport == null:
		return
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _preview_viewport.get_parent() == self:
		remove_child(_preview_viewport)


# ---- List + scope -----------------------------------------------------------

func _set_scope(s: int) -> void:
	if _scope == s:
		return
	_scope = s
	_tab_tank.button_pressed = s == Scope.TANK
	_tab_global.button_pressed = s == Scope.GLOBAL
	_refresh_list()


func _set_type_filter(f: int) -> void:
	if _type_filter == f:
		return
	_type_filter = f
	if _filter_all != null:
		_filter_all.button_pressed = f == TypeFilter.ALL
		_filter_fish.button_pressed = f == TypeFilter.FISH
		_filter_shrimp.button_pressed = f == TypeFilter.SHRIMP
		_filter_snail.button_pressed = f == TypeFilter.SNAIL
		_filter_plant.button_pressed = f == TypeFilter.PLANT
	_refresh_list()


func _set_view_mode(mode: int) -> void:
	if _view_mode == mode:
		return
	_view_mode = mode
	if _view_list_btn != null:
		_view_list_btn.button_pressed = mode == ViewMode.LIST
		_view_tree_btn.button_pressed = mode == ViewMode.TREE
	if _list_panel != null:
		_list_panel.visible = mode == ViewMode.LIST
	if _tree_scroll != null:
		_tree_scroll.visible = mode == ViewMode.TREE
	_refresh_list()


func _make_filter_button(text: String, active: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = active
	b.add_theme_font_size_override("font_size", 10)
	b.add_theme_color_override("font_color", PanelTheme.LABEL_FG)
	b.add_theme_color_override("font_pressed_color", PanelTheme.TITLE_FG)
	return b


func _make_tab_button(text: String, active: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = active
	b.add_theme_color_override("font_color", PanelTheme.LABEL_FG)
	b.add_theme_color_override("font_pressed_color", PanelTheme.TITLE_FG)
	b.add_theme_color_override("font_hover_color", PanelTheme.TITLE_FG)
	return b


func _backfill_discoveries_from_tank() -> void:
	var sim := get_tree().root.find_child("SimDriver", true, false)
	if sim != null and sim.has_method("sync_species_discoveries"):
		sim.sync_species_discoveries()


func _on_library_changed() -> void:
	if visible:
		_refresh_list()


func _refresh_list() -> void:
	if _list_root == null:
		return
	for c in _list_root.get_children():
		c.queue_free()
	_row_by_key.clear()
	_lineage_edges.clear()
	var entries: Array = _filter_entries(_current_scope_entries())
	if entries.is_empty():
		var empty := Label.new()
		empty.text = (
			"No discoveries yet.\nFish, shrimp, snails, and plants appear here as they breed,\nevolve, and spread in the tank."
			if _scope == Scope.TANK else
			"No global pins yet.\nOpen 'This Tank' and pin lineages you want to keep."
		)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", PanelTheme.DIM_FG)
		empty.add_theme_font_size_override("font_size", 11)
		_list_root.add_child(empty)
		_select_entry({})
		return
	# Sort by generation (founders first) then newest discovery — reads as a tree.
	entries.sort_custom(func(a, b):
		var ga: int = int(a.get("generation", 0))
		var gb: int = int(b.get("generation", 0))
		if ga != gb:
			return ga < gb
		return int(a.get("first_seen_unix", 0)) > int(b.get("first_seen_unix", 0)))
	for entry in entries:
		var item: Control = _make_list_item(entry)
		_list_root.add_child(item)
		var k: String = String(entry.get("species_key", ""))
		if k != "":
			_row_by_key[k] = item
	if _view_mode == ViewMode.LIST:
		_build_lineage_edges(entries)
		call_deferred("_sync_lineage_overlay")
	if _lineage_tree != null:
		_lineage_tree.set_entries(entries, _selected_key)
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


func _filter_entries(entries: Array) -> Array:
	if _type_filter == TypeFilter.ALL:
		return entries
	var want: String = {
		TypeFilter.FISH: SpeciesLibrary.ORGANISM_FISH,
		TypeFilter.SHRIMP: SpeciesLibrary.ORGANISM_SHRIMP,
		TypeFilter.SNAIL: SpeciesLibrary.ORGANISM_SNAIL,
		TypeFilter.PLANT: SpeciesLibrary.ORGANISM_PLANT,
	}.get(_type_filter, "")
	var out: Array = []
	for e in entries:
		if e is Dictionary:
			var otype: String = String(e.get("organism_type", SpeciesLibrary.ORGANISM_FISH))
			if otype == want:
				out.append(e)
	return out


func _build_lineage_edges(entries: Array) -> void:
	_lineage_edges.clear()
	var keys_in_view: Dictionary = {}
	for e in entries:
		if e is Dictionary:
			keys_in_view[String(e.get("species_key", ""))] = true
	for e in entries:
		if not (e is Dictionary):
			continue
		var child_key: String = String(e.get("species_key", ""))
		if child_key == "":
			continue
		var pks: Variant = e.get("parent_keys", [])
		if not (pks is Array):
			continue
		for pk in pks:
			var parent_key: String = String(pk)
			if parent_key != "" and keys_in_view.has(parent_key):
				_lineage_edges.append({"from": parent_key, "to": child_key})


func _sync_lineage_overlay() -> void:
	if _lineage_layer != null:
		_lineage_layer.queue_redraw()


func _draw_lineage_overlay() -> void:
	if _lineage_layer == null or _lineage_edges.is_empty():
		return
	var line_col := Color(0.45, 0.72, 0.95, 0.55)
	for edge in _lineage_edges:
		var from_key: String = String(edge.get("from", ""))
		var to_key: String = String(edge.get("to", ""))
		if not _row_by_key.has(from_key) or not _row_by_key.has(to_key):
			continue
		var from_ctrl: Control = _row_by_key[from_key] as Control
		var to_ctrl: Control = _row_by_key[to_key] as Control
		if from_ctrl == null or to_ctrl == null:
			continue
		var p_from: Vector2 = _control_center_in_layer(from_ctrl)
		var p_to: Vector2 = _control_center_in_layer(to_ctrl)
		_lineage_layer.draw_line(p_from, p_to, line_col, 2.0, true)
		_lineage_layer.draw_circle(p_from, 3.0, Color(0.55, 0.85, 1.0, 0.75))


func _control_center_in_layer(ctrl: Control) -> Vector2:
	var rect: Rect2 = ctrl.get_global_rect()
	var center: Vector2 = rect.position + rect.size * 0.5
	return _lineage_layer.get_global_transform().affine_inverse() * center


func _find_entry_in_list(arr: Array, key: String) -> Dictionary:
	for e in arr:
		if e is Dictionary and String(e.get("species_key", "")) == key:
			return e
	return {}


func _make_list_item(entry: Dictionary) -> Control:
	var btn := Button.new()
	var key: String = String(entry.get("species_key", ""))
	var display: String = String(entry.get("display_name", "creature"))
	var otype: String = String(entry.get("organism_type", SpeciesLibrary.ORGANISM_FISH))
	var gen: int = int(entry.get("generation", 0))
	var is_pin: bool = false
	var lib := get_node_or_null("/root/SpeciesLibrary")
	if lib != null and _scope == Scope.TANK:
		is_pin = lib.is_pinned(key)
	var icon: String = _organism_icon(otype)
	var indent: String = "  ".repeat(mini(gen, 6))
	var marker: String = " 📌" if is_pin else ""
	btn.text = "%s%s %s · g%d%s" % [indent, icon, display, gen, marker]
	var lineage: String = String(entry.get("parent_lineage", ""))
	btn.tooltip_text = "%s · gen %d\nfrom: %s" % [otype, gen, lineage]
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
	btn.pressed.connect(_on_list_item_pressed.bind(key))
	return btn


func _on_list_item_pressed(species_key: String) -> void:
	var entries: Array = _filter_entries(_current_scope_entries())
	_select_entry(_find_entry_in_list(entries, species_key))


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
		_clear_preview_creature()
		return

	_selected_key = String(entry.get("species_key", ""))
	if _lineage_tree != null:
		_lineage_tree.set_selected_key(_selected_key)
	var genome_raw: Dictionary = entry.get("genome", {})
	var genome: Dictionary = SpeciesLibrary.genome_from_serialisable(genome_raw)
	var otype: String = String(entry.get("organism_type", SpeciesLibrary.organism_type(genome)))

	_detail_name.text = "%s %s" % [_organism_icon(otype), String(entry.get("display_name", "?"))]
	var src: String = String(entry.get("source", ""))
	var src_label: String = {
		"founder": "Founder cohort",
		"store": "Store purchase",
		"evolved": "Bred in tank",
	}.get(src, src)
	var gen: int = int(entry.get("generation", 0))
	var lineage: String = String(entry.get("parent_lineage", "Founders"))
	_detail_source_badge.text = "%s · %s · gen %d · seen %d" % [
		otype, src_label, gen, int(entry.get("count_seen", 1)),
	]

	_clear_children(_detail_swatches)
	_populate_swatches(genome, otype)

	_clear_children(_detail_traits)
	_add_trait("Type", otype)
	_add_trait("Lineage", lineage)
	var pks: Variant = entry.get("parent_keys", [])
	if pks is Array and (pks as Array).size() > 0:
		_add_trait("Parent keys", ", ".join(pks))
	_populate_traits(genome, otype)

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

	call_deferred("_load_preview_creature", genome, otype)


func _organism_icon(otype: String) -> String:
	match otype:
		SpeciesLibrary.ORGANISM_SHRIMP:
			return "🦐"
		SpeciesLibrary.ORGANISM_SNAIL:
			return "🐌"
		SpeciesLibrary.ORGANISM_PLANT:
			return "🌿"
		_:
			return "🐟"


func _populate_swatches(genome: Dictionary, otype: String) -> void:
	match otype:
		SpeciesLibrary.ORGANISM_SNAIL:
			_add_swatch(genome.get("shell_color", Color.WHITE), 32)
		SpeciesLibrary.ORGANISM_PLANT:
			var ramp: Variant = genome.get("ramp_override", [])
			if ramp is Array:
				var step: int = maxi(1, int((ramp as Array).size() / 4.0))
				for i in range(0, (ramp as Array).size(), step):
					_add_swatch((ramp as Array)[i], 22)
		_:
			_add_swatch(genome.get("base_color", Color.WHITE), 32)
			_add_swatch(genome.get("accent_color", Color.GRAY), 18)
			if otype == SpeciesLibrary.ORGANISM_FISH:
				_add_swatch(genome.get("tail_color", genome.get("accent_color", Color.GRAY)), 18)


func _populate_traits(genome: Dictionary, otype: String) -> void:
	match otype:
		SpeciesLibrary.ORGANISM_SHRIMP:
			_add_trait("Species", String(genome.get("species", "shrimp")))
			_add_trait("Size", "%.2f" % float(genome.get("adult_voxel_scale", 0.1)))
			_add_trait("Max speed", "%.2f" % float(genome.get("max_speed", 0.85)))
			if bool(genome.get("is_cleaner", false)):
				_add_trait("Role", "cleaner shrimp")
		SpeciesLibrary.ORGANISM_SNAIL:
			_add_trait("Shell shape", String(genome.get("shell_shape", "turbo")))
			_add_trait("Shell size", "%.2f" % float(genome.get("shell_size", 1.0)))
		SpeciesLibrary.ORGANISM_PLANT:
			_add_trait("Form", String(genome.get("leaf_form", "column")))
			_add_trait("Max height", str(int(genome.get("max_height", 12))))
			_add_trait("Growth", "%.2f" % float(genome.get("growth_rate", 0.18)))
		_:
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


func _on_pin_pressed() -> void:
	var lib := get_node_or_null("/root/SpeciesLibrary")
	if lib == null or _selected_key == "":
		return
	if lib.is_pinned(_selected_key):
		lib.unpin_from_global(_selected_key)
	else:
		lib.pin_to_global(_selected_key)


# ---- Preview creature lifecycle ---------------------------------------------

func _clear_preview_creature() -> void:
	if _preview_creature != null and is_instance_valid(_preview_creature):
		_preview_creature.queue_free()
	_preview_creature = null


func _load_preview_creature(genome: Dictionary, otype: String) -> void:
	_clear_preview_creature()
	if _preview_pivot == null or genome.is_empty():
		return
	var g: Dictionary = genome.duplicate(true)
	match otype:
		SpeciesLibrary.ORGANISM_SHRIMP:
			_preview_creature = _spawn_preview_shrimp(g)
		SpeciesLibrary.ORGANISM_SNAIL:
			_preview_creature = _spawn_preview_snail(g)
		SpeciesLibrary.ORGANISM_PLANT:
			_preview_creature = _spawn_preview_plant(g)
		_:
			_preview_creature = _spawn_preview_fish(g)


func _spawn_preview_fish(g: Dictionary) -> Fish:
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
	f.look_at(f.position + Vector3(0, 0, -1), Vector3.UP)
	_freeze_preview_creature(f)
	return f


func _spawn_preview_shrimp(g: Dictionary) -> Shrimp:
	var s := Shrimp.new()
	_preview_pivot.add_child(s)
	s.position = Vector3(0, 0.05, 0)
	# init_genome builds the body at current maturity — fry scale is invisible
	# in the preview sphere.
	s.maturity = Shrimp.MATURITY_ADULT
	s.init_genome(g)
	s.position = Vector3(0, 0.05, 0)
	s.scale = Vector3.ONE * SHRIMP_PREVIEW_SCALE
	s.velocity = Vector3.ZERO
	s.speed = 0.0
	s.heading = Vector3(0, 0, -1)
	_freeze_preview_creature(s)
	return s


func _spawn_preview_snail(g: Dictionary) -> Node3D:
	# Plain Node3D — do NOT attach snail.gd or _process will crawl the mesh
	# off-screen / queue_free in the isolated preview world.
	var sn := Node3D.new()
	sn.name = "PreviewSnail"
	_preview_pivot.add_child(sn)
	sn.position = Vector3(0, 0.05, 0)
	sn.rotation.y = PI * 0.5
	sn.scale = Vector3.ONE * SNAIL_PREVIEW_SCALE
	_build_preview_snail_shell(sn, g)
	return sn


func _freeze_preview_creature(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)


func _build_preview_snail_shell(snail: Node3D, g: Dictionary) -> void:
	var shell_color: Color = _preview_color(g.get("shell_color", Color8(135, 44, 176)))
	var shell_size: float = float(g.get("shell_size", 1.0))
	var shell_shape: String = String(g.get("shell_shape", "turbo"))
	var shell_dark := shell_color.darkened(0.22)
	var body := Color8(44, 31, 21)
	var shell_mat := VoxelMat.make(shell_color)
	var shell_dark_mat := VoxelMat.make(shell_dark)
	var body_mat := VoxelMat.make(body)
	match shell_shape:
		"trochus":
			for i in 6:
				var y: float = 0.04 + i * 0.045 * shell_size
				var s: float = (0.18 - i * 0.025) * shell_size
				var mat: Material = shell_mat if (i & 1) == 0 else shell_dark_mat
				var mi := MeshInstance3D.new()
				mi.mesh = VoxelMat.get_box(Vector3(s, s * 0.85, s))
				mi.position = Vector3(0, y, 0)
				mi.material_override = mat
				snail.add_child(mi)
		"nassarius":
			var mi := MeshInstance3D.new()
			mi.mesh = VoxelMat.get_box(Vector3(0.14 * shell_size, 0.08 * shell_size, 0.18 * shell_size))
			mi.material_override = shell_mat
			snail.add_child(mi)
		_:
			for i in 4:
				var ang: float = i * 0.7
				var r: float = (0.05 + i * 0.06) * shell_size
				var sp := Vector3(cos(ang) * r, sin(ang) * r, 0.0)
				var s: float = (0.16 - i * 0.02) * shell_size
				var mat: Material = shell_mat if (i & 1) == 0 else shell_dark_mat
				var mi := MeshInstance3D.new()
				mi.mesh = VoxelMat.get_box(Vector3(s, s, s))
				mi.position = sp
				mi.material_override = mat
				snail.add_child(mi)
	var foot := MeshInstance3D.new()
	foot.mesh = VoxelMat.get_box(Vector3(0.24 * shell_size, 0.06 * shell_size, 0.16 * shell_size))
	foot.position = Vector3(0, -0.12 * shell_size, 0)
	foot.material_override = body_mat
	snail.add_child(foot)


func _preview_color(c: Variant) -> Color:
	if c is Color:
		return c
	if c is Array and (c as Array).size() >= 3:
		var a: Array = c
		return Color(float(a[0]), float(a[1]), float(a[2]),
			float(a[3]) if a.size() >= 4 else 1.0)
	return Color8(135, 44, 176)


func _spawn_preview_plant(g: Dictionary) -> Plant:
	var p := Plant.new()
	_preview_pivot.add_child(p)
	p.position = Vector3(0, -0.5, 0)
	var ramp: Variant = g.get("ramp_override", [])
	if ramp is Array and (ramp as Array).size() == 6:
		p.ramp_override = (ramp as Array).duplicate()
	p.init(mini(6, int(g.get("max_height", 8))), {
		"max_height": int(g.get("max_height", 12)),
		"growth_rate": float(g.get("growth_rate", 0.18)),
		"sway_amplitude": float(g.get("sway_amplitude", 0.25)),
		"leaf_form": String(g.get("leaf_form", "column")),
		"leaf_length": int(g.get("leaf_length", 4)),
	})
	_freeze_preview_creature(p)
	return p


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
		return "%dm" % int(secs / 60.0)
	if secs < 86400:
		return "%dh" % int(secs / 3600.0)
	return "%dd" % int(secs / 86400.0)
