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
var _dither_world_check: CheckBox
var _blue_noise: HSlider
var _blue_noise_label: Label
var _experimental_check: CheckBox
var _pixel_purity_check: CheckBox
var _colorblind_option: OptionButton
var _palette_inspector: PaletteInspector
var _photo_mode_check: CheckBox
var _signature_shot_btn: Button
var _matured_check: CheckBox
var _bank_lock_check: CheckBox
var _outline: HSlider
var _outline_label: Label
var _crt: HSlider
var _crt_label: Label
var _integer_upscale_check: CheckBox
var _pixel_snap_check: CheckBox
var _follow_dof_check: CheckBox
var _follow_dof_near_check: CheckBox
var _follow_dof_strength: HSlider
var _follow_dof_strength_label: Label
var _follow_dof_far_soft: HSlider
var _follow_dof_far_soft_label: Label
var _follow_dof_near_soft: HSlider
var _follow_dof_near_soft_label: Label
var _follow_dof_focus: HSlider
var _follow_dof_focus_label: Label
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
var _fidelity_buttons: Array[Button] = []
var _fidelity_summary: Label
var _adaptive_block: VBoxContainer

const FIDELITY_PRESETS: Array = [
	{
		"key": "potato",
		"label": "Potato",
		"w": 256, "h": 144, "msaa": 0,
		"shader_tier": 2,
		"tip": "256×144 — integrated GPU / low-end (reduced shader cost)",
	},
	{
		"key": "chunky",
		"label": "Chunky",
		"w": 256, "h": 144, "msaa": 0,
		"tip": "256×144 — deliberate chunky pixel-art (extra dither)",
	},
	{
		"key": "balanced",
		"label": "Balanced",
		"w": 512, "h": 288, "msaa": 0,
		"tip": "512×288 — classic walstad loom pixel scale",
	},
	{
		"key": "sharp",
		"label": "Sharp",
		"w": 768, "h": 432, "msaa": 1,
		"tip": "768×432 with 2× MSAA",
	},
	{
		"key": "high",
		"label": "High",
		"w": 1024, "h": 576, "msaa": 2,
		"tip": "1024×576 with 4× MSAA — default desktop fidelity",
	},
]
const RESOLUTIONS: Array = [
	{"label": "256×144", "w": 256, "h": 144},
	{"label": "384×216", "w": 384, "h": 216},
	{"label": "512×288", "w": 512, "h": 288},
	{"label": "768×432", "w": 768, "h": 432},
	{"label": "1024×576 (high default)", "w": 1024, "h": 576},
]
const MSAA_LABELS: Array[String] = ["Off", "2x", "4x", "8x"]


func _ready() -> void:
	set_process_unhandled_input(true)
	_build_ui()
	_pull_from_config()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _unhandled_input(event: InputEvent) -> void:
	if PanelTheme.typing_focus_in_ui(get_viewport()):
		return
	if visible and event.is_action_pressed("ui_cancel"):
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		get_viewport().set_input_as_handled()
		return
	# R toggles this panel. (O toggles the settings panel.) Unhandled input
	# lets LineEdit/TextEdit consume typed keys first.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			var main: Node = get_tree().current_scene
			if main != null and main.has_method("_ui_toggle_side"):
				main.call("_ui_toggle_side", "render")
			else:
				toggle()
			get_viewport().set_input_as_handled()


func toggle() -> void:
	visible = not visible
	if visible:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_pull_from_config()
		_refresh_palette_inspector()
	else:
		mouse_filter = Control.MOUSE_FILTER_IGNORE


func _refresh_palette_inspector() -> void:
	if _palette_inspector == null:
		return
	var main: Node = get_tree().current_scene
	_palette_inspector.refresh_from_main(main)


func _build_ui() -> void:
	custom_minimum_size = Vector2(420, 0)
	PanelTheme.apply_panel_chrome(self)

	# Outer layout: title + rule at top, scrolling section list in the middle,
	# pinned Close / Apply footer at the bottom.
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)

	outer.add_child(PanelTheme.make_title("Rendering"))
	outer.add_child(PanelTheme.make_subtitle(
		"Pick a fidelity tier, then tune the look. Apply reloads for resolution / MSAA."))
	outer.add_child(PanelTheme.make_rule())

	_build_quality_hero(outer)

	outer.add_child(PanelTheme.make_rule())

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(tabs)

	var render_scroll := ScrollContainer.new()
	render_scroll.name = "Post-process"
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
	_save_status = Label.new()
	_save_status.add_theme_font_size_override("font_size", 10)
	_save_status.add_theme_color_override("font_color", Color8(150, 230, 150))
	_save_status.text = ""
	outer.add_child(_save_status)
	var save_btn := PanelTheme.make_secondary_button("Save (no reload)")
	save_btn.pressed.connect(_on_save_only)
	var apply := PanelTheme.make_primary_button("Apply (reload)")
	apply.pressed.connect(_on_apply)
	outer.add_child(PanelTheme.make_panel_footer(func(): visible = false, apply, [save_btn]))


func _build_quality_hero(parent: VBoxContainer) -> void:
	_add_section(parent, "Fidelity")
	var hero_hint := PanelTheme.make_description()
	hero_hint.text = "One tap sets render resolution + MSAA. Use Apply to rebuild the viewport."
	parent.add_child(hero_hint)

	var fidelity_row := HBoxContainer.new()
	fidelity_row.add_theme_constant_override("separation", 6)
	parent.add_child(fidelity_row)
	_fidelity_buttons.clear()
	for preset in FIDELITY_PRESETS:
		var btn := PanelTheme.make_secondary_button(String(preset["label"]))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.tooltip_text = String(preset["tip"])
		var p: Dictionary = preset
		btn.pressed.connect(func(): _apply_fidelity_preset(p))
		PanelTheme.style_hud_toggle_button(btn, false)
		fidelity_row.add_child(btn)
		_fidelity_buttons.append(btn)

	_fidelity_summary = PanelTheme.make_description()
	parent.add_child(_fidelity_summary)

	_adaptive_block = VBoxContainer.new()
	_adaptive_block.add_theme_constant_override("separation", 6)
	parent.add_child(_adaptive_block)

	_adaptive_check = CheckBox.new()
	_adaptive_check.text = "Auto-adjust fidelity to hit target FPS"
	_adaptive_check.button_pressed = false
	_adaptive_check.tooltip_text = "Steps resolution down when the GPU can't keep up, back up when there's headroom."
	_adaptive_check.toggled.connect(func(v):
		TankConfig.adaptive_quality = v
		_sync_adaptive_controls())
	_adaptive_block.add_child(_adaptive_check)

	_frame_graph_label = Label.new()
	_frame_graph_label.text = "—"
	PanelTheme.as_mono(_frame_graph_label, PanelTheme.SIZE_CAPTION)
	_adaptive_block.add_child(_frame_graph_label)
	var spark_hint := PanelTheme.make_description()
	spark_hint.text = "Green line = target frame budget; spikes above = hitch frames."
	_adaptive_block.add_child(spark_hint)

	_frame_graph = Control.new()
	_frame_graph.custom_minimum_size = Vector2(0, 48)
	_frame_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_frame_graph.draw.connect(_draw_frame_graph)
	_adaptive_block.add_child(_frame_graph)

	_adaptive_target_label = Label.new()
	_adaptive_target = PanelTheme.add_slider_row(
		_adaptive_block, "Target FPS", 30.0, 120.0, 5.0, _adaptive_target_label)
	_adaptive_target.value_changed.connect(func(v):
		TankConfig.adaptive_quality_target_fps = int(v)
		_adaptive_target_label.text = "%d" % int(v))

	_add_section(parent, "Exact resolution")
	_res_option = OptionButton.new()
	_res_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_res_option.custom_minimum_size = Vector2(0, 30)
	for r in RESOLUTIONS:
		_res_option.add_item(String(r["label"]))
	_res_option.item_selected.connect(func(idx): _on_resolution(idx))
	parent.add_child(_res_option)
	var res_hint := PanelTheme.make_description()
	res_hint.text = "Fine-tune between tiers — overrides the fidelity buttons above."
	parent.add_child(res_hint)

	_msaa_option = PanelTheme.add_dropdown_row(parent, "MSAA")
	for label in MSAA_LABELS:
		_msaa_option.add_item(label)
	_msaa_option.item_selected.connect(func(idx):
		TankConfig.msaa = idx
		_sync_fidelity_buttons()
		_update_fidelity_summary())


func _build_rendering_tab(vbox: VBoxContainer) -> void:
	var palette_body := _make_fold_section(vbox, "Palette & quantize", true)
	_palette_check = CheckBox.new()
	_palette_check.text = "Enable palette quantization"
	_palette_check.toggled.connect(func(v): TankConfig.palette_enabled = v)
	palette_body.add_child(_palette_check)
	_dither_label = Label.new()
	_dither = PanelTheme.add_slider_row(palette_body, "Dither strength", 0.0, 1.0, 0.05, _dither_label)
	_dither.value_changed.connect(func(v): _on_dither(v))
	_region_aware_check = CheckBox.new()
	_region_aware_check.text = "Region-aware dither (recommended)"
	_region_aware_check.toggled.connect(func(v): TankConfig.dither_region_aware = v)
	palette_body.add_child(_region_aware_check)
	_dither_world_check = CheckBox.new()
	_dither_world_check.text = "World-space dither lock (less shimmer on pan)"
	_dither_world_check.toggled.connect(func(v):
		TankConfig.dither_world_lock = v
		_push_live_quantize())
	palette_body.add_child(_dither_world_check)
	_blue_noise_label = Label.new()
	_blue_noise = PanelTheme.add_slider_row(palette_body, "Blue-noise blend", 0.0, 1.0, 0.05, _blue_noise_label)
	_blue_noise.value_changed.connect(func(v):
		TankConfig.blue_noise_amount = v
		_blue_noise_label.text = "%.2f" % v
		_push_live_quantize())
	_bank_lock_check = CheckBox.new()
	_bank_lock_check.text = "Palette bank lock (8-bit feel)"
	_bank_lock_check.toggled.connect(func(v): TankConfig.palette_bank_lock = v)
	palette_body.add_child(_bank_lock_check)
	var rad_desc := PanelTheme.make_description()
	rad_desc.text = "Smart dither: heavier on muted water/fog, lighter on saturated fauna."
	palette_body.add_child(rad_desc)
	var bl_desc := PanelTheme.make_description()
	bl_desc.text = "Bank lock restricts each pixel to a local palette slice for a truer 8-bit look."
	palette_body.add_child(bl_desc)
	_palette_inspector = PaletteInspector.new()
	palette_body.add_child(_palette_inspector)

	var capture_body := _make_fold_section(vbox, "Capture & photo", false)
	_photo_mode_check = CheckBox.new()
	_photo_mode_check.text = "Photo mode grade on screenshots"
	_photo_mode_check.tooltip_text = "Boosts bloom, vignette, and glow while saving a capture."
	_photo_mode_check.toggled.connect(func(v): TankConfig.photo_mode_enhanced = v)
	capture_body.add_child(_photo_mode_check)
	var photo_desc := PanelTheme.make_description()
	photo_desc.text = "F12 saves a clean capture; Shift+F12 runs the signature poster preset."
	capture_body.add_child(photo_desc)
	_signature_shot_btn = PanelTheme.make_secondary_button("Signature shot (Shift+F12)")
	_signature_shot_btn.pressed.connect(func():
		var main: Node = get_tree().current_scene
		if main != null and main.has_method("_take_signature_shot"):
			main.call("_take_signature_shot"))
	capture_body.add_child(_signature_shot_btn)

	var polish_body := _make_fold_section(vbox, "Pixel-art polish", false)
	_outline_label = Label.new()
	_outline = PanelTheme.add_slider_row(polish_body, "Outline strength", 0.0, 1.0, 0.05, _outline_label)
	_outline.value_changed.connect(func(v):
		TankConfig.outline_strength = v
		_outline_label.text = "%.2f" % v)
	_crt_label = Label.new()
	_crt = PanelTheme.add_slider_row(polish_body, "CRT scanlines", 0.0, 1.0, 0.05, _crt_label)
	_crt.value_changed.connect(func(v):
		TankConfig.crt_strength = v
		_crt_label.text = "%.2f" % v)
	_integer_upscale_check = CheckBox.new()
	_integer_upscale_check.text = "Integer upscale (eliminate sub-pixel shimmer)"
	_integer_upscale_check.toggled.connect(func(v):
		TankConfig.integer_upscale = v
		var main: Node = get_tree().current_scene
		if main != null and main.has_method("_apply_display_layout"):
			main.call("_apply_display_layout"))
	polish_body.add_child(_integer_upscale_check)
	_pixel_snap_check = CheckBox.new()
	_pixel_snap_check.text = "Pixel-snap camera"
	_pixel_snap_check.toggled.connect(func(v): TankConfig.pixel_snap_camera = v)
	polish_body.add_child(_pixel_snap_check)
	_pixel_purity_check = CheckBox.new()
	_pixel_purity_check.text = "True 8-bit purity (bank-lock + heavy dither)"
	_pixel_purity_check.toggled.connect(func(v):
		TankConfig.pixel_purity = v
		var main: Node = get_tree().current_scene
		if main != null and main.has_method("_apply_render_config"):
			main.call("_apply_render_config"))
	polish_body.add_child(_pixel_purity_check)
	_colorblind_option = OptionButton.new()
	_colorblind_option.add_item("Standard palette", 0)
	_colorblind_option.add_item("Protanopia-friendly", 1)
	_colorblind_option.add_item("Deuteranopia-friendly", 2)
	_colorblind_option.add_item("Tritanopia-friendly", 3)
	_colorblind_option.item_selected.connect(func(idx: int):
		match idx:
			1: TankConfig.colorblind_palette = "protan"
			2: TankConfig.colorblind_palette = "deutan"
			3: TankConfig.colorblind_palette = "tritan"
			_: TankConfig.colorblind_palette = "none"
		var main: Node = get_tree().current_scene
		if main != null and main.has_method("_apply_render_config"):
			main.call("_apply_render_config"))
	polish_body.add_child(_colorblind_option)

	var effects_body := _make_fold_section(vbox, "Fauna & tank startup", false)
	_experimental_check = CheckBox.new()
	_experimental_check.text = "Amplify fauna sheen (SSS + iridescence)"
	_experimental_check.toggled.connect(func(v): TankConfig.experimental_visuals = v)
	effects_body.add_child(_experimental_check)
	var exp_desc := PanelTheme.make_description()
	exp_desc.text = "Rebuilds fauna materials — click Apply after toggling."
	effects_body.add_child(exp_desc)
	_matured_check = CheckBox.new()
	_matured_check.text = "New tanks start established (skip the cycle)"
	_matured_check.toggled.connect(func(v):
		TankConfig.start_matured = v
		TankConfig.cycle_start_mode = "established" if v else "fresh")
	effects_body.add_child(_matured_check)
	var mat_desc := PanelTheme.make_description()
	mat_desc.text = "Applies to newly created tanks only — cycled chemistry, biofilm patina, mixed ages."
	effects_body.add_child(mat_desc)

	var dof_body := _make_fold_section(vbox, "Follow depth-of-field", false)
	_follow_dof_check = CheckBox.new()
	_follow_dof_check.text = "Blur background while following a creature"
	_follow_dof_check.toggled.connect(func(v):
		TankConfig.follow_depth_of_field = v
		_sync_follow_dof_controls())
	dof_body.add_child(_follow_dof_check)
	_follow_dof_strength_label = Label.new()
	_follow_dof_strength = PanelTheme.add_slider_row(dof_body, "DOF strength", 0.0, 0.25, 0.005, _follow_dof_strength_label)
	_follow_dof_strength.value_changed.connect(func(v):
		TankConfig.follow_dof_blur_strength = v
		_follow_dof_strength_label.text = "%.3f" % v)
	_follow_dof_focus_label = Label.new()
	_follow_dof_focus = PanelTheme.add_slider_row(dof_body, "Focus margin", 0.2, 4.0, 0.1, _follow_dof_focus_label)
	_follow_dof_focus.value_changed.connect(func(v):
		TankConfig.follow_dof_focus_margin = v
		_follow_dof_focus_label.text = "%.1f" % v)
	_follow_dof_far_soft_label = Label.new()
	_follow_dof_far_soft = PanelTheme.add_slider_row(dof_body, "Far softness", 0.3, 8.0, 0.1, _follow_dof_far_soft_label)
	_follow_dof_far_soft.value_changed.connect(func(v):
		TankConfig.follow_dof_far_softness = v
		_follow_dof_far_soft_label.text = "%.1f" % v)
	_follow_dof_near_soft_label = Label.new()
	_follow_dof_near_soft = PanelTheme.add_slider_row(dof_body, "Near softness", 0.3, 8.0, 0.1, _follow_dof_near_soft_label)
	_follow_dof_near_soft.value_changed.connect(func(v):
		TankConfig.follow_dof_near_softness = v
		_follow_dof_near_soft_label.text = "%.1f" % v)
	_follow_dof_near_check = CheckBox.new()
	_follow_dof_near_check.text = "Blur foreground (near DOF)"
	_follow_dof_near_check.toggled.connect(func(v): TankConfig.follow_dof_near_enabled = v)
	dof_body.add_child(_follow_dof_near_check)

	var fog_body := _make_fold_section(vbox, "Volumetric fog", true)
	_fog_density_label = Label.new()
	_fog_density = PanelTheme.add_slider_row(fog_body, "Density", 0.0, 0.08, 0.005, _fog_density_label)
	_fog_density.value_changed.connect(func(v): _on_fog_density(v))
	_fog_anisotropy_label = Label.new()
	_fog_anisotropy = PanelTheme.add_slider_row(fog_body, "Anisotropy", -0.9, 0.9, 0.05, _fog_anisotropy_label)
	_fog_anisotropy.value_changed.connect(func(v): _on_fog_anisotropy(v))
	_fog_ambient_label = Label.new()
	_fog_ambient = PanelTheme.add_slider_row(fog_body, "Ambient inject", 0.0, 0.5, 0.02, _fog_ambient_label)
	_fog_ambient.value_changed.connect(func(v): _on_fog_ambient(v))

	var camera_body := _make_fold_section(vbox, "Camera", true)
	_fov_label = Label.new()
	_fov = PanelTheme.add_slider_row(camera_body, "Field of view", 30.0, 90.0, 1.0, _fov_label)
	_fov.value_changed.connect(func(v): _on_fov(v))


func _make_fold_section(parent: VBoxContainer, title: String, start_open: bool) -> VBoxContainer:
	parent.add_child(PanelTheme.make_spacer(4))
	var section_root := VBoxContainer.new()
	section_root.add_theme_constant_override("separation", 6)
	parent.add_child(section_root)
	var header := Button.new()
	header.focus_mode = Control.FOCUS_NONE
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.text = ("%s  %s" % ["▼", title]) if start_open else ("%s  %s" % ["▶", title])
	PanelTheme.as_sans(header, PanelTheme.SIZE_CAPTION, true)
	header.add_theme_color_override("font_color", PanelTheme.SECTION_FG)
	var header_normal := StyleBoxFlat.new()
	header_normal.bg_color = Color(0, 0, 0, 0)
	header_normal.border_color = PanelTheme.BORDER
	header_normal.border_width_bottom = 1
	header_normal.content_margin_left = 8
	header_normal.content_margin_right = 8
	header_normal.content_margin_top = 6
	header_normal.content_margin_bottom = 6
	var header_hover := header_normal.duplicate()
	header_hover.bg_color = Color(0.14, 0.18, 0.26, 0.55)
	header.add_theme_stylebox_override("normal", header_normal)
	header.add_theme_stylebox_override("hover", header_hover)
	header.add_theme_stylebox_override("pressed", header_hover)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.visible = start_open
	section_root.add_child(header)
	section_root.add_child(body)
	header.pressed.connect(func():
		body.visible = not body.visible
		header.text = ("%s  %s" % ["▼", title]) if body.visible else ("%s  %s" % ["▶", title]))
	return body


func _apply_fidelity_preset(preset: Dictionary) -> void:
	TankConfig.render_width = int(preset["w"])
	TankConfig.render_height = int(preset["h"])
	TankConfig.msaa = int(preset["msaa"])
	TankConfig.shader_perf_tier = int(preset.get("shader_tier", 0))
	var key: String = String(preset.get("key", ""))
	if key == "potato":
		TankConfig.dither_strength = maxf(TankConfig.dither_strength, 0.88)
		TankConfig.integer_upscale = true
		TankConfig.outline_strength = 0.0
		TankConfig.crt_strength = 0.0
	elif key == "chunky":
		TankConfig.dither_strength = maxf(TankConfig.dither_strength, 0.92)
		TankConfig.integer_upscale = true
		TankConfig.shader_perf_tier = maxi(TankConfig.shader_perf_tier, 1)
	elif key in ["sharp", "high"]:
		TankConfig.shader_perf_tier = 0
	_pull_resolution_option()
	if _msaa_option != null:
		_msaa_option.select(int(TankConfig.msaa))
	_sync_fidelity_buttons()
	_update_fidelity_summary()


func _fidelity_preset_index() -> int:
	for i in FIDELITY_PRESETS.size():
		var p: Dictionary = FIDELITY_PRESETS[i]
		if int(p["w"]) == TankConfig.render_width \
				and int(p["h"]) == TankConfig.render_height \
				and int(p["msaa"]) == int(TankConfig.msaa) \
				and int(p.get("shader_tier", 0)) == int(TankConfig.shader_perf_tier):
			return i
	return -1


func _sync_fidelity_buttons() -> void:
	var active_idx: int = _fidelity_preset_index()
	for i in _fidelity_buttons.size():
		PanelTheme.style_hud_toggle_button(_fidelity_buttons[i], i == active_idx)
	_update_fidelity_summary()


func _update_fidelity_summary() -> void:
	if _fidelity_summary == null:
		return
	var msaa_label: String = MSAA_LABELS[clampi(int(TankConfig.msaa), 0, MSAA_LABELS.size() - 1)]
	var tier_label: String = "Custom"
	var idx: int = _fidelity_preset_index()
	if idx >= 0:
		tier_label = String(FIDELITY_PRESETS[idx]["label"])
	var adaptive_note: String = ""
	if TankConfig.adaptive_quality:
		adaptive_note = " · auto-adjust on (%d fps target)" % TankConfig.adaptive_quality_target_fps
	_fidelity_summary.text = "Active: %s — %d×%d · MSAA %s%s" % [
		tier_label,
		TankConfig.render_width,
		TankConfig.render_height,
		msaa_label,
		adaptive_note,
	]


func _sync_adaptive_controls() -> void:
	var on: bool = TankConfig.adaptive_quality
	if _adaptive_check != null:
		_adaptive_check.set_block_signals(true)
		_adaptive_check.button_pressed = on
		_adaptive_check.set_block_signals(false)
	for ctrl in [_adaptive_target, _frame_graph]:
		if ctrl != null:
			ctrl.modulate.a = 1.0 if on else 0.45
			if ctrl is Range:
				(ctrl as Range).editable = on
	if _adaptive_target_label != null:
		_adaptive_target_label.modulate.a = 1.0 if on else 0.45
	if _frame_graph_label != null:
		_frame_graph_label.modulate.a = 1.0 if on else 0.45
	_update_fidelity_summary()


func _pull_resolution_option() -> void:
	if _res_option == null:
		return
	_res_option.set_block_signals(true)
	for i in RESOLUTIONS.size():
		var r: Dictionary = RESOLUTIONS[i]
		if int(r["w"]) == TankConfig.render_width and int(r["h"]) == TankConfig.render_height:
			_res_option.select(i)
			break
	_res_option.set_block_signals(false)


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
	_pull_resolution_option()
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
	if _dither_world_check != null:
		_dither_world_check.set_block_signals(true)
		_dither_world_check.button_pressed = TankConfig.dither_world_lock
		_dither_world_check.set_block_signals(false)
	if _blue_noise != null:
		_blue_noise.set_block_signals(true)
		_blue_noise.value = TankConfig.blue_noise_amount
		_blue_noise.set_block_signals(false)
		if _blue_noise_label != null:
			_blue_noise_label.text = "%.2f" % TankConfig.blue_noise_amount
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
	if _pixel_purity_check != null:
		_pixel_purity_check.set_block_signals(true)
		_pixel_purity_check.button_pressed = TankConfig.pixel_purity
		_pixel_purity_check.set_block_signals(false)
	if _colorblind_option != null:
		_colorblind_option.select(
			1 if TankConfig.colorblind_palette == "protan"
			else 2 if TankConfig.colorblind_palette == "deutan"
			else 3 if TankConfig.colorblind_palette == "tritan"
			else 0)
	if _photo_mode_check != null:
		_photo_mode_check.set_block_signals(true)
		_photo_mode_check.button_pressed = TankConfig.photo_mode_enhanced
		_photo_mode_check.set_block_signals(false)
	_refresh_palette_inspector()
	if _follow_dof_check != null:
		_follow_dof_check.set_block_signals(true)
		_follow_dof_check.button_pressed = TankConfig.follow_depth_of_field
		_follow_dof_check.set_block_signals(false)
	if _follow_dof_strength != null:
		_follow_dof_strength.set_block_signals(true)
		_follow_dof_strength.value = TankConfig.follow_dof_blur_strength
		_follow_dof_strength.set_block_signals(false)
		_follow_dof_strength_label.text = "%.3f" % TankConfig.follow_dof_blur_strength
	if _follow_dof_focus != null:
		_follow_dof_focus.set_block_signals(true)
		_follow_dof_focus.value = TankConfig.follow_dof_focus_margin
		_follow_dof_focus.set_block_signals(false)
		_follow_dof_focus_label.text = "%.1f" % TankConfig.follow_dof_focus_margin
	if _follow_dof_far_soft != null:
		_follow_dof_far_soft.set_block_signals(true)
		_follow_dof_far_soft.value = TankConfig.follow_dof_far_softness
		_follow_dof_far_soft.set_block_signals(false)
		_follow_dof_far_soft_label.text = "%.1f" % TankConfig.follow_dof_far_softness
	if _follow_dof_near_soft != null:
		_follow_dof_near_soft.set_block_signals(true)
		_follow_dof_near_soft.value = TankConfig.follow_dof_near_softness
		_follow_dof_near_soft.set_block_signals(false)
		_follow_dof_near_soft_label.text = "%.1f" % TankConfig.follow_dof_near_softness
	if _follow_dof_near_check != null:
		_follow_dof_near_check.set_block_signals(true)
		_follow_dof_near_check.button_pressed = TankConfig.follow_dof_near_enabled
		_follow_dof_near_check.set_block_signals(false)
	_sync_follow_dof_controls()
	_fog_density.value = TankConfig.fog_density
	_fog_anisotropy.value = TankConfig.fog_anisotropy
	_fog_ambient.value = TankConfig.fog_ambient_inject
	_fov.set_block_signals(true)
	_fov.value = TankConfig.camera_fov
	_fov.set_block_signals(false)
	_msaa_option.select(int(TankConfig.msaa))
	_sync_fidelity_buttons()
	_sync_adaptive_controls()
	if _adaptive_target != null:
		_adaptive_target.value = float(TankConfig.adaptive_quality_target_fps)
	if _adaptive_target_label != null:
		_adaptive_target_label.text = "%d" % TankConfig.adaptive_quality_target_fps
	_sync_material_sliders()
	_update_labels()


func _sync_follow_dof_controls() -> void:
	var on: bool = TankConfig.follow_depth_of_field
	for ctrl in [_follow_dof_strength, _follow_dof_focus, _follow_dof_far_soft, _follow_dof_near_soft]:
		if ctrl != null:
			ctrl.editable = on
			ctrl.modulate.a = 1.0 if on else 0.45
	if _follow_dof_near_check != null:
		_follow_dof_near_check.disabled = not on
		_follow_dof_near_check.modulate.a = 1.0 if on else 0.45


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
	_sync_fidelity_buttons()
	_update_fidelity_summary()


func _on_dither(v: float) -> void:
	TankConfig.dither_strength = v
	_dither_label.text = "%.2f" % v
	_push_live_quantize_param("dither_strength", v)


func _push_live_quantize() -> void:
	var main := get_tree().current_scene
	if main == null:
		return
	var display := main.get_node_or_null("Display")
	if display == null or not (display.material is ShaderMaterial):
		return
	var sm := display.material as ShaderMaterial
	sm.set_shader_parameter("dither_world_lock", 1.0 if TankConfig.dither_world_lock else 0.0)
	sm.set_shader_parameter("blue_noise_amount", float(TankConfig.blue_noise_amount))
	sm.set_shader_parameter("dither_world_origin",
			Vector2(float(TankConfig.camera_target_x), float(TankConfig.camera_target_z)))


func _push_live_quantize_param(param_name: String, value: Variant) -> void:
	var main := get_tree().current_scene
	if main != null:
		var display := main.get_node_or_null("Display")
		if display != null and display.material is ShaderMaterial:
			(display.material as ShaderMaterial).set_shader_parameter(param_name, value)


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
