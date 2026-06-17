# Render parameters panel.
#
# Sibling to settings_panel.gd - exposes the 3D rendering pipeline knobs:
# SubViewport resolution, dither strength, palette toggle, fog parameters,
# camera FOV, MSAA. Most apply via scene reload (Apply button); a few like
# fog density + FOV update live as you drag.

extends PanelContainer


var _res_option: OptionButton
var _film_option: OptionButton
var _dither: HSlider
var _dither_label: Label
var _palette_check: CheckBox
var _region_aware_check: CheckBox
var _experimental_check: CheckBox
var _matured_check: CheckBox
var _bank_lock_check: CheckBox
var _outline: HSlider
var _outline_label: Label
var _crt: HSlider
var _crt_label: Label
var _integer_upscale_check: CheckBox
var _pixel_snap_check: CheckBox
var _follow_dof_check: CheckBox
var _fog_density: HSlider
var _fog_density_label: Label
var _fog_anisotropy: HSlider
var _fog_anisotropy_label: Label
var _fog_ambient: HSlider
var _fog_ambient_label: Label
var _fov: HSlider
var _fov_label: Label
var _msaa_option: OptionButton
var _adaptive_check: CheckBox
var _adaptive_target: HSlider
var _adaptive_target_label: Label
var _save_status: Label
# Frame-time mini-sparkline drawn as a Control with a custom _draw.
var _frame_graph: Control = null
var _frame_graph_label: Label = null
var _mat_hue: HSlider
var _mat_hue_label: Label
var _mat_sat: HSlider
var _mat_sat_label: Label
var _mat_warmth: HSlider
var _mat_warmth_label: Label
var _mat_value: HSlider
var _mat_value_label: Label
var _mat_w_fauna: HSlider
var _mat_w_fauna_label: Label
var _mat_w_foliage: HSlider
var _mat_w_foliage_label: Label
var _mat_w_substrate: HSlider
var _mat_w_substrate_label: Label
var _mat_w_hardscape: HSlider
var _mat_w_hardscape_label: Label
var _mat_w_water: HSlider
var _mat_w_water_label: Label

const RESOLUTIONS: Array = [
	{"label": "256x144 (chunky)", "w": 256, "h": 144},
	{"label": "384x216", "w": 384, "h": 216},
	{"label": "512x288 (default)", "w": 512, "h": 288},
	{"label": "768x432", "w": 768, "h": 432},
	{"label": "1024x576 (smooth)", "w": 1024, "h": 576},
]
const MSAA_LABELS: Array[String] = ["Off", "2x", "4x", "8x"]


func _ready() -> void:
	_build_ui()
	_pull_from_config()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		get_viewport().set_input_as_handled()
		return
	# R toggles this panel. (O toggles the settings panel.) We use unhandled
	# input so the corner button can still toggle programmatically.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			var main: Node = get_tree().current_scene
			if main != null and main.has_method("_ui_toggle_side"):
				main.call("_ui_toggle_side", "render")
			else:
				toggle()


func toggle() -> void:
	visible = not visible
	if visible:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_pull_from_config()
	else:
		mouse_filter = Control.MOUSE_FILTER_IGNORE


func _build_ui() -> void:
	custom_minimum_size = Vector2(420, 0)
	PanelTheme.apply_panel_chrome(self)

	# Outer layout: title + rule at top, scrolling section list in the middle,
	# pinned Close / Apply footer at the bottom.
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)

	outer.add_child(PanelTheme.make_title("Rendering"))
	outer.add_child(PanelTheme.make_rule())

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(tabs)

	var render_scroll := ScrollContainer.new()
	render_scroll.name = "Rendering"
	render_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	render_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	render_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(render_scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	render_scroll.add_child(vbox)

	var color_scroll := ScrollContainer.new()
	color_scroll.name = "Color theme"
	color_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	color_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(color_scroll)

	var vbox_color := VBoxContainer.new()
	vbox_color.add_theme_constant_override("separation", 8)
	vbox_color.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_scroll.add_child(vbox_color)

	_build_rendering_tab(vbox)
	_build_color_tab(vbox_color)

	# Footer buttons — attached to `outer` (NOT tab bodies) so Close + Save +
	# Apply stay pinned at the bottom of the panel below the scroll area.
	#
	# Three buttons:
	#   Close  — dismiss the panel, no persistence step (changes already
	#            apply live but won't survive next launch).
	#   Save   — persist current TankConfig render fields to disk WITHOUT
	#            reloading the scene. Use this when you've found a dither
	#            / pixel-art combo you like and want it to stick across
	#            sessions while keeping your tank state intact.
	#   Apply  — save + reload the scene (required for resolution / MSAA
	#            changes; optional for everything else).
	outer.add_child(PanelTheme.make_rule())
	_save_status = Label.new()
	_save_status.add_theme_font_size_override("font_size", 10)
	_save_status.add_theme_color_override("font_color", Color8(150, 230, 150))
	_save_status.text = ""
	outer.add_child(_save_status)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", 8)
	outer.add_child(hb)
	var close := PanelTheme.make_secondary_button("Close")
	close.pressed.connect(func(): visible = false)
	hb.add_child(close)
	var save_btn := PanelTheme.make_secondary_button("Save (no reload)")
	save_btn.pressed.connect(_on_save_only)
	hb.add_child(save_btn)
	var apply := PanelTheme.make_primary_button("Apply (reload)")
	apply.pressed.connect(_on_apply)
	hb.add_child(apply)


func _build_rendering_tab(vbox: VBoxContainer) -> void:
	_add_section(vbox, "Resolution")
	_res_option = OptionButton.new()
	_res_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_res_option.custom_minimum_size = Vector2(0, 30)
	for r in RESOLUTIONS:
		_res_option.add_item(String(r["label"]))
	_res_option.item_selected.connect(func(idx): _on_resolution(idx))
	vbox.add_child(_res_option)

	_add_section(vbox, "Palette quantize")
	_palette_check = CheckBox.new()
	_palette_check.text = "Enable palette quantization"
	_palette_check.toggled.connect(func(v): TankConfig.palette_enabled = v)
	vbox.add_child(_palette_check)
	_dither_label = Label.new()
	_dither = PanelTheme.add_slider_row(vbox, "Dither strength", 0.0, 1.0, 0.05, _dither_label)
	_dither.value_changed.connect(func(v): _on_dither(v))
	_region_aware_check = CheckBox.new()
	_region_aware_check.text = "Region-aware dither (recommended)"
	_region_aware_check.toggled.connect(func(v): TankConfig.dither_region_aware = v)
	vbox.add_child(_region_aware_check)
	_experimental_check = CheckBox.new()
	_experimental_check.text = "Amplify fauna sheen (stronger SSS + iridescence)"
	_experimental_check.toggled.connect(func(v): TankConfig.experimental_visuals = v)
	vbox.add_child(_experimental_check)
	var exp_desc := PanelTheme.make_description()
	exp_desc.text = "Adds subsurface glow + view-angle shimmer to fish & shrimp. Click Apply to rebuild."
	vbox.add_child(exp_desc)
	_matured_check = CheckBox.new()
	_matured_check.text = "New tanks start established (skip the cycle)"
	_matured_check.toggled.connect(func(v):
		TankConfig.start_matured = v
		TankConfig.cycle_start_mode = "established" if v else "fresh")
	vbox.add_child(_matured_check)
	var mat_desc := PanelTheme.make_description()
	mat_desc.text = "Applies when you create a NEW tank: cycled chemistry, biofilm patina, mixed ages. Off = fresh Walstad cycle with visible ammonia phase."
	vbox.add_child(mat_desc)
	var rad_desc := PanelTheme.make_description()
	rad_desc.text = "Smart dither: more on muted colors, less on saturated. Disable for uniform stippling."
	vbox.add_child(rad_desc)
	_bank_lock_check = CheckBox.new()
	_bank_lock_check.text = "Palette bank lock (8-bit feel)"
	_bank_lock_check.toggled.connect(func(v): TankConfig.palette_bank_lock = v)
	vbox.add_child(_bank_lock_check)
	var bl_desc := PanelTheme.make_description()
	bl_desc.text = "Restricts each pixel to nearby palette colors. Off = smoother gradients across the whole palette."
	vbox.add_child(bl_desc)

	_add_section(vbox, "Pixel art polish")
	_outline_label = Label.new()
	_outline = PanelTheme.add_slider_row(vbox, "Outline strength", 0.0, 1.0, 0.05, _outline_label)
	_outline.value_changed.connect(func(v):
		TankConfig.outline_strength = v
		_outline_label.text = "%.2f" % v)
	var ol_desc := PanelTheme.make_description()
	ol_desc.text = "Dark line at color discontinuities — adds NES-style readability."
	vbox.add_child(ol_desc)
	_crt_label = Label.new()
	_crt = PanelTheme.add_slider_row(vbox, "CRT scanlines", 0.0, 1.0, 0.05, _crt_label)
	_crt.value_changed.connect(func(v):
		TankConfig.crt_strength = v
		_crt_label.text = "%.2f" % v)
	var crt_desc := PanelTheme.make_description()
	crt_desc.text = "Faint horizontal scanlines for a retro CRT feel. Off by default."
	vbox.add_child(crt_desc)
	_integer_upscale_check = CheckBox.new()
	_integer_upscale_check.text = "Integer upscale (eliminate sub-pixel shimmer)"
	_integer_upscale_check.toggled.connect(func(v):
		TankConfig.integer_upscale = v
		var main: Node = get_tree().current_scene
		if main != null and main.has_method("_apply_display_layout"):
			main.call("_apply_display_layout"))
	vbox.add_child(_integer_upscale_check)
	var iu_desc := PanelTheme.make_description()
	iu_desc.text = "Snaps render to nearest integer scale (2×, 3×…). Auto-falls back to stretched if integer scale would shrink the tank below 70% of the window."
	vbox.add_child(iu_desc)
	_pixel_snap_check = CheckBox.new()
	_pixel_snap_check.text = "Pixel-snap camera"
	_pixel_snap_check.toggled.connect(func(v): TankConfig.pixel_snap_camera = v)
	vbox.add_child(_pixel_snap_check)
	var ps_desc := PanelTheme.make_description()
	ps_desc.text = "Snaps camera to world-pixel units. Stops sub-pixel jitter on fish, may feel rigid."
	vbox.add_child(ps_desc)
	_follow_dof_check = CheckBox.new()
	_follow_dof_check.text = "Follow depth-of-field"
	_follow_dof_check.toggled.connect(func(v): TankConfig.follow_depth_of_field = v)
	vbox.add_child(_follow_dof_check)
	var dof_desc := PanelTheme.make_description()
	dof_desc.text = "When following a creature, blurs the rest of the tank into a dreamy haze. A stylised look — off by default."
	vbox.add_child(dof_desc)

	_add_section(vbox, "Volumetric fog")
	_fog_density_label = Label.new()
	_fog_density = PanelTheme.add_slider_row(vbox, "Density", 0.0, 0.08, 0.005, _fog_density_label)
	_fog_density.value_changed.connect(func(v): _on_fog_density(v))
	_fog_anisotropy_label = Label.new()
	_fog_anisotropy = PanelTheme.add_slider_row(vbox, "Anisotropy", -0.9, 0.9, 0.05, _fog_anisotropy_label)
	_fog_anisotropy.value_changed.connect(func(v): _on_fog_anisotropy(v))
	_fog_ambient_label = Label.new()
	_fog_ambient = PanelTheme.add_slider_row(vbox, "Ambient inject", 0.0, 0.5, 0.02, _fog_ambient_label)
	_fog_ambient.value_changed.connect(func(v): _on_fog_ambient(v))

	_add_section(vbox, "Camera")
	_fov_label = Label.new()
	_fov = PanelTheme.add_slider_row(vbox, "Field of view", 30.0, 90.0, 1.0, _fov_label)
	_fov.value_changed.connect(func(v): _on_fov(v))

	_add_section(vbox, "Quality")
	_msaa_option = PanelTheme.add_dropdown_row(vbox, "MSAA")
	for label in MSAA_LABELS:
		_msaa_option.add_item(label)
	_msaa_option.item_selected.connect(func(idx): TankConfig.msaa = idx)

	_add_section(vbox, "Frame budget")
	_frame_graph_label = Label.new()
	_frame_graph_label.text = "—"
	vbox.add_child(_frame_graph_label)
	_frame_graph = Control.new()
	_frame_graph.custom_minimum_size = Vector2(0, 48)
	_frame_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_frame_graph.draw.connect(_draw_frame_graph)
	vbox.add_child(_frame_graph)
	_adaptive_check = CheckBox.new()
	_adaptive_check.text = "Adaptive quality (auto-step resolution)"
	_adaptive_check.toggled.connect(func(v): TankConfig.adaptive_quality = v)
	vbox.add_child(_adaptive_check)
	_adaptive_target_label = Label.new()
	_adaptive_target = PanelTheme.add_slider_row(
		vbox, "Target FPS", 30.0, 120.0, 5.0, _adaptive_target_label)
	_adaptive_target.value_changed.connect(func(v):
		TankConfig.adaptive_quality_target_fps = int(v)
		_adaptive_target_label.text = "%d" % int(v))


func _build_color_tab(vbox: VBoxContainer) -> void:
	var hint := PanelTheme.make_description()
	hint.text = "Global material tint overlay — does not change saved fish or plant genomes. Preview is live."
	vbox.add_child(hint)

	_add_section(vbox, "Film stock")
	var film_hint := PanelTheme.make_description()
	film_hint.text = "One-tap mood presets — set tint, dither, vignette and bloom together. Save to keep."
	vbox.add_child(film_hint)
	_film_option = OptionButton.new()
	for k in TankConfig.FILM_STOCKS.keys():
		var stock: Dictionary = TankConfig.FILM_STOCKS[k]
		_film_option.add_item(String(stock.get("label", k)))
		_film_option.set_item_metadata(_film_option.item_count - 1, String(k))
	_film_option.item_selected.connect(_on_film_stock_selected)
	vbox.add_child(_film_option)

	_add_section(vbox, "Global tint")
	_mat_hue_label = Label.new()
	_mat_hue = PanelTheme.add_slider_row(vbox, "Hue shift", -0.5, 0.5, 0.01, _mat_hue_label)
	_mat_hue.value_changed.connect(func(v):
		TankConfig.material_hue_shift = v
		_mat_hue_label.text = "%.2f" % v
		_apply_material_palette())
	_mat_sat_label = Label.new()
	_mat_sat = PanelTheme.add_slider_row(vbox, "Saturation", 0.5, 1.5, 0.01, _mat_sat_label)
	_mat_sat.value_changed.connect(func(v):
		TankConfig.material_saturation = v
		_mat_sat_label.text = "%.2f" % v
		_apply_material_palette())
	_mat_warmth_label = Label.new()
	_mat_warmth = PanelTheme.add_slider_row(vbox, "Warmth", -1.0, 1.0, 0.01, _mat_warmth_label)
	_mat_warmth.value_changed.connect(func(v):
		TankConfig.material_warmth = v
		_mat_warmth_label.text = "%.2f" % v
		_apply_material_palette())
	_mat_value_label = Label.new()
	_mat_value = PanelTheme.add_slider_row(vbox, "Brightness", 0.7, 1.3, 0.01, _mat_value_label)
	_mat_value.value_changed.connect(func(v):
		TankConfig.material_value = v
		_mat_value_label.text = "%.2f" % v
		_apply_material_palette())

	_add_section(vbox, "Category blend")
	var blend_hint := PanelTheme.make_description()
	blend_hint.text = "How strongly the global tint affects each material family (0 = unchanged)."
	vbox.add_child(blend_hint)
	_mat_w_fauna_label = Label.new()
	_mat_w_fauna = PanelTheme.add_slider_row(vbox, "Fauna", 0.0, 1.0, 0.01, _mat_w_fauna_label)
	_mat_w_fauna.value_changed.connect(func(v):
		TankConfig.material_weight_fauna = v
		_mat_w_fauna_label.text = "%.2f" % v
		_apply_material_palette())
	_mat_w_foliage_label = Label.new()
	_mat_w_foliage = PanelTheme.add_slider_row(vbox, "Plants", 0.0, 1.0, 0.01, _mat_w_foliage_label)
	_mat_w_foliage.value_changed.connect(func(v):
		TankConfig.material_weight_foliage = v
		_mat_w_foliage_label.text = "%.2f" % v
		_apply_material_palette())
	_mat_w_substrate_label = Label.new()
	_mat_w_substrate = PanelTheme.add_slider_row(vbox, "Substrate", 0.0, 1.0, 0.01, _mat_w_substrate_label)
	_mat_w_substrate.value_changed.connect(func(v):
		TankConfig.material_weight_substrate = v
		_mat_w_substrate_label.text = "%.2f" % v
		_apply_material_palette())
	_mat_w_hardscape_label = Label.new()
	_mat_w_hardscape = PanelTheme.add_slider_row(vbox, "Hardscape", 0.0, 1.0, 0.01, _mat_w_hardscape_label)
	_mat_w_hardscape.value_changed.connect(func(v):
		TankConfig.material_weight_hardscape = v
		_mat_w_hardscape_label.text = "%.2f" % v
		_apply_material_palette())
	_mat_w_water_label = Label.new()
	_mat_w_water = PanelTheme.add_slider_row(vbox, "Water", 0.0, 1.0, 0.01, _mat_w_water_label)
	_mat_w_water.value_changed.connect(func(v):
		TankConfig.material_weight_water = v
		_mat_w_water_label.text = "%.2f" % v
		_apply_material_palette())


# Persist render settings to disk without rebuilding the scene.
func _on_save_only() -> void:
	TankConfig.save_to_disk()
	if _save_status != null:
		_save_status.text = "✓ Saved. Settings will persist across reloads."


# Section header with a 4-px spacer above so each group reads as a chunk
# instead of running into the previous slider row.
func _add_section(parent: Node, label: String) -> void:
	parent.add_child(PanelTheme.make_spacer(4))
	parent.add_child(PanelTheme.make_section(label))


func _pull_from_config() -> void:
	# Resolution match.
	for i in RESOLUTIONS.size():
		var r: Dictionary = RESOLUTIONS[i]
		if int(r["w"]) == TankConfig.render_width and int(r["h"]) == TankConfig.render_height:
			_res_option.select(i)
			break
	_dither.value = TankConfig.dither_strength
	_palette_check.button_pressed = TankConfig.palette_enabled
	if _experimental_check != null:
		_experimental_check.button_pressed = TankConfig.experimental_visuals
	if _matured_check != null:
		_matured_check.button_pressed = TankConfig.start_matured
	# Pixel-art polish controls — block signals so set_pressed doesn't
	# bounce back through the toggled callback and overwrite TankConfig.
	if _region_aware_check != null:
		_region_aware_check.set_block_signals(true)
		_region_aware_check.button_pressed = TankConfig.dither_region_aware
		_region_aware_check.set_block_signals(false)
	if _bank_lock_check != null:
		_bank_lock_check.set_block_signals(true)
		_bank_lock_check.button_pressed = TankConfig.palette_bank_lock
		_bank_lock_check.set_block_signals(false)
	if _outline != null:
		_outline.set_block_signals(true)
		_outline.value = TankConfig.outline_strength
		_outline.set_block_signals(false)
		if _outline_label != null:
			_outline_label.text = "%.2f" % TankConfig.outline_strength
	if _crt != null:
		_crt.set_block_signals(true)
		_crt.value = TankConfig.crt_strength
		_crt.set_block_signals(false)
		if _crt_label != null:
			_crt_label.text = "%.2f" % TankConfig.crt_strength
	if _integer_upscale_check != null:
		_integer_upscale_check.set_block_signals(true)
		_integer_upscale_check.button_pressed = TankConfig.integer_upscale
		_integer_upscale_check.set_block_signals(false)
	if _pixel_snap_check != null:
		_pixel_snap_check.set_block_signals(true)
		_pixel_snap_check.button_pressed = TankConfig.pixel_snap_camera
		_pixel_snap_check.set_block_signals(false)
	if _follow_dof_check != null:
		_follow_dof_check.set_block_signals(true)
		_follow_dof_check.button_pressed = TankConfig.follow_depth_of_field
		_follow_dof_check.set_block_signals(false)
	_fog_density.value = TankConfig.fog_density
	_fog_anisotropy.value = TankConfig.fog_anisotropy
	_fog_ambient.value = TankConfig.fog_ambient_inject
	_fov.value = TankConfig.camera_fov
	_msaa_option.select(int(TankConfig.msaa))
	if _adaptive_check != null:
		_adaptive_check.button_pressed = TankConfig.adaptive_quality
	if _adaptive_target != null:
		_adaptive_target.value = float(TankConfig.adaptive_quality_target_fps)
	if _adaptive_target_label != null:
		_adaptive_target_label.text = "%d" % TankConfig.adaptive_quality_target_fps
	_sync_material_sliders()
	_update_labels()


func _sync_material_sliders() -> void:
	if _mat_hue == null:
		return
	_mat_hue.set_block_signals(true)
	_mat_hue.value = TankConfig.material_hue_shift
	_mat_hue.set_block_signals(false)
	_mat_hue_label.text = "%.2f" % TankConfig.material_hue_shift
	_mat_sat.set_block_signals(true)
	_mat_sat.value = TankConfig.material_saturation
	_mat_sat.set_block_signals(false)
	_mat_sat_label.text = "%.2f" % TankConfig.material_saturation
	_mat_warmth.set_block_signals(true)
	_mat_warmth.value = TankConfig.material_warmth
	_mat_warmth.set_block_signals(false)
	_mat_warmth_label.text = "%.2f" % TankConfig.material_warmth
	_mat_value.set_block_signals(true)
	_mat_value.value = TankConfig.material_value
	_mat_value.set_block_signals(false)
	_mat_value_label.text = "%.2f" % TankConfig.material_value
	_mat_w_fauna.set_block_signals(true)
	_mat_w_fauna.value = TankConfig.material_weight_fauna
	_mat_w_fauna.set_block_signals(false)
	_mat_w_fauna_label.text = "%.2f" % TankConfig.material_weight_fauna
	_mat_w_foliage.set_block_signals(true)
	_mat_w_foliage.value = TankConfig.material_weight_foliage
	_mat_w_foliage.set_block_signals(false)
	_mat_w_foliage_label.text = "%.2f" % TankConfig.material_weight_foliage
	_mat_w_substrate.set_block_signals(true)
	_mat_w_substrate.value = TankConfig.material_weight_substrate
	_mat_w_substrate.set_block_signals(false)
	_mat_w_substrate_label.text = "%.2f" % TankConfig.material_weight_substrate
	_mat_w_hardscape.set_block_signals(true)
	_mat_w_hardscape.value = TankConfig.material_weight_hardscape
	_mat_w_hardscape.set_block_signals(false)
	_mat_w_hardscape_label.text = "%.2f" % TankConfig.material_weight_hardscape
	_mat_w_water.set_block_signals(true)
	_mat_w_water.value = TankConfig.material_weight_water
	_mat_w_water.set_block_signals(false)
	_mat_w_water_label.text = "%.2f" % TankConfig.material_weight_water


func _process(_dt: float) -> void:
	# Repaint the sparkline while the panel is visible. Cheap (custom
	# _draw, polyline only) and the user is presumably watching it.
	if visible and _frame_graph != null:
		_frame_graph.queue_redraw()
		_update_frame_graph_label()


func _update_frame_graph_label() -> void:
	if _frame_graph_label == null:
		return
	var main := get_tree().current_scene
	if main == null or not main.has_method("get_frame_history_ordered"):
		return
	var hist: PackedFloat32Array = main.get_frame_history_ordered()
	var sum: float = 0.0
	var n: int = 0
	var worst: float = 0.0
	for v in hist:
		if v > 0.0001:
			sum += v
			n += 1
			if v > worst:
				worst = v
	if n == 0:
		_frame_graph_label.text = "—"
		return
	var avg_dt: float = sum / float(n)
	var avg_fps: float = 1.0 / avg_dt
	var worst_fps: float = 1.0 / maxf(worst, 0.0001)
	_frame_graph_label.text = "avg %.0f fps · 1%% low %.0f fps" % [avg_fps, worst_fps]


func _draw_frame_graph() -> void:
	if _frame_graph == null:
		return
	var main := get_tree().current_scene
	if main == null or not main.has_method("get_frame_history_ordered"):
		return
	var hist: PackedFloat32Array = main.get_frame_history_ordered()
	var w: float = _frame_graph.size.x
	var h: float = _frame_graph.size.y
	if w <= 4 or h <= 4 or hist.size() == 0:
		return
	# Background.
	_frame_graph.draw_rect(Rect2(Vector2.ZERO, _frame_graph.size),
		Color(0.06, 0.07, 0.12, 0.6), true)
	# Budget reference line at 1/target_fps frame time (the "good" line).
	var target_fps: float = float(TankConfig.adaptive_quality_target_fps)
	var budget_dt: float = 1.0 / maxf(target_fps, 10.0)
	# Y axis maps 0..2× budget to bottom..top. >2× budget = pinned to top.
	var y_max_dt: float = budget_dt * 2.0
	var budget_y: float = h - clampf(budget_dt / y_max_dt, 0.0, 1.0) * h
	_frame_graph.draw_line(
		Vector2(0, budget_y), Vector2(w, budget_y),
		Color(0.55, 0.85, 0.55, 0.45), 1.0)
	# Sample line.
	var pts: PackedVector2Array = PackedVector2Array()
	for i in hist.size():
		var dt_v: float = hist[i]
		if dt_v <= 0.0:
			dt_v = 0.0
		var x: float = float(i) / float(maxi(1, hist.size() - 1)) * w
		var ynorm: float = clampf(dt_v / y_max_dt, 0.0, 1.0)
		var y: float = h - ynorm * h
		pts.append(Vector2(x, y))
	if pts.size() >= 2:
		_frame_graph.draw_polyline(pts, Color(0.85, 0.92, 0.55, 0.95), 1.2)


func _update_labels() -> void:
	_dither_label.text = "%.2f" % _dither.value
	_fog_density_label.text = "%.3f" % _fog_density.value
	_fog_anisotropy_label.text = "%.2f" % _fog_anisotropy.value
	_fog_ambient_label.text = "%.2f" % _fog_ambient.value
	_fov_label.text = "%d°" % int(_fov.value)


func _on_resolution(idx: int) -> void:
	var r: Dictionary = RESOLUTIONS[idx]
	TankConfig.render_width = int(r["w"])
	TankConfig.render_height = int(r["h"])


func _on_dither(v: float) -> void:
	TankConfig.dither_strength = v
	_dither_label.text = "%.2f" % v
	# Live update: push into the active display shader so the user sees it.
	var main := get_tree().current_scene
	if main != null:
		var display := main.get_node_or_null("Display")
		if display != null and display.material is ShaderMaterial:
			(display.material as ShaderMaterial).set_shader_parameter("dither_strength", v)


func _on_fog_density(v: float) -> void:
	TankConfig.fog_density = v
	_fog_density_label.text = "%.3f" % v
	_apply_fog_live()


func _on_fog_anisotropy(v: float) -> void:
	TankConfig.fog_anisotropy = v
	_fog_anisotropy_label.text = "%.2f" % v
	_apply_fog_live()


func _on_fog_ambient(v: float) -> void:
	TankConfig.fog_ambient_inject = v
	_fog_ambient_label.text = "%.2f" % v
	_apply_fog_live()


func _apply_fog_live() -> void:
	var main := get_tree().current_scene
	if main == null:
		return
	var we := main.get_node_or_null("SubViewport/World/WorldEnvironment")
	if we != null and we.environment != null:
		we.environment.volumetric_fog_density = TankConfig.fog_density
		we.environment.volumetric_fog_anisotropy = TankConfig.fog_anisotropy
		we.environment.volumetric_fog_ambient_inject = TankConfig.fog_ambient_inject


func _on_fov(v: float) -> void:
	TankConfig.camera_fov = v
	_fov_label.text = "%d°" % int(v)
	# Live: update the active camera.
	var main := get_tree().current_scene
	if main == null:
		return
	var cam := main.get_node_or_null("SubViewport/World/Camera3D")
	if cam != null:
		cam.fov = v


func _on_film_stock_selected(idx: int) -> void:
	if _film_option == null:
		return
	TankConfig.apply_film_stock(String(_film_option.get_item_metadata(idx)))
	# Tint applies on demand; the post knobs (dither/vignette/bloom) are pushed
	# every frame from TankConfig, so just refresh the panel + material tint.
	_apply_material_palette()
	_sync_material_sliders()
	if _dither != null:
		_dither.value = TankConfig.dither_strength
	_update_labels()


func _apply_material_palette() -> void:
	var main := get_tree().current_scene
	if main != null and main.has_method("apply_material_palette"):
		main.call("apply_material_palette")


func _on_apply() -> void:
	# Preserve current camera view before the scene reload.
	var main := get_tree().current_scene
	if main != null and main.has_method("save_camera_state"):
		main.save_camera_state()
	TankConfig.save_to_disk()
	# Reload scene so resolution + MSAA + palette toggle take effect.
	get_tree().reload_current_scene()
