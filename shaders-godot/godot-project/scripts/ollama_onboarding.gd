extends PanelContainer

# (No class_name — settings_panel.gd preloads this script directly to
# avoid a race with the global class_name registry on first run.)

# Self-contained onboarding modal that walks a brand-new user from zero
# to "Ollama installed, model pulled, AIDirector connected" without
# leaving the settings panel. Built entirely in code so it can be
# instantiated anywhere; the settings panel pops it via .open().
#
# Flow:
#   1. Download Ollama (platform-detected button to ollama.com)
#   2. Pull the model (one-line copy-paste terminal command)
#   3. Test Connection (calls AIDirector.test_connection)
#   4. Done
#
# The privacy note is prominent on every step — this is the single most
# common question players ask before turning on anything labelled "AI".

signal closed()

const PRIVACY_NOTE: String = "Runs 100% on your computer. No data leaves your machine. You can turn this off anytime."

var _ai: Node = null
var _step_label: Label
var _action_button: Button
var _status_label: Label
var _model_field: LineEdit
var _close_button: Button
var _step: int = 0


func _ready() -> void:
	_ai = get_node_or_null("/root/AIDirector")
	custom_minimum_size = Vector2(480, 0)
	_build_ui()
	if _ai != null and _ai.has_signal("connection_tested"):
		_ai.connection_tested.connect(_on_connection_tested)
	_show_step(0)


func _build_ui() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.16, 0.97)
	style.border_color = Color(0.42, 0.62, 0.95, 0.7)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	add_theme_stylebox_override("panel", style)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)

	var title := Label.new()
	title.text = "Bring your tank to life"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color8(255, 215, 110))
	v.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Optional: install Ollama for AI-generated names, moods, and tank narration."
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color8(210, 220, 240))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(subtitle)

	var privacy := Label.new()
	privacy.text = PRIVACY_NOTE
	privacy.add_theme_font_size_override("font_size", 11)
	privacy.add_theme_color_override("font_color", Color8(140, 200, 150))
	privacy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(privacy)

	var hr := HSeparator.new()
	v.add_child(hr)

	_step_label = Label.new()
	_step_label.add_theme_font_size_override("font_size", 13)
	_step_label.add_theme_color_override("font_color", Color8(240, 240, 240))
	_step_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_step_label)

	# Model name editor (used in step 2)
	var model_row := HBoxContainer.new()
	model_row.add_theme_constant_override("separation", 6)
	v.add_child(model_row)
	var ml := Label.new()
	ml.text = "Model:"
	ml.add_theme_font_size_override("font_size", 11)
	ml.add_theme_color_override("font_color", Color8(180, 195, 220))
	model_row.add_child(ml)
	_model_field = LineEdit.new()
	_model_field.text = (String(_ai.model) if _ai != null else "qwen2.5:3b")
	_model_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_model_field.placeholder_text = "qwen2.5:3b"
	_model_field.text_changed.connect(_on_model_changed)
	model_row.add_child(_model_field)

	_action_button = Button.new()
	_action_button.pressed.connect(_on_action_pressed)
	v.add_child(_action_button)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.add_theme_color_override("font_color", Color8(180, 195, 220))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status_label)

	var hr2 := HSeparator.new()
	v.add_child(hr2)

	var footer := HBoxContainer.new()
	v.add_child(footer)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_close_button = Button.new()
	_close_button.text = "Skip for now"
	_close_button.pressed.connect(_on_close)
	footer.add_child(_close_button)


func _on_model_changed(text: String) -> void:
	if _ai != null:
		_ai.model = text.strip_edges()
	# Re-render step 2 command so the displayed pull line matches.
	if _step == 1:
		_show_step(1)


func _show_step(idx: int) -> void:
	_step = idx
	match idx:
		0:
			_step_label.text = "Step 1 of 3 — Download Ollama for your OS. It's a small CLI; the installer takes about a minute."
			_action_button.text = "Open ollama.com/download"
			_status_label.text = ""
		1:
			var m: String = (String(_ai.model) if _ai != null else "qwen2.5:3b")
			_step_label.text = "Step 2 of 3 — Open a terminal and run:\n\n    ollama pull %s\n\n(This downloads ~2GB once. The model stays on your computer.)" % m
			_action_button.text = "Copy command"
			_status_label.text = ""
		2:
			_step_label.text = "Step 3 of 3 — Make sure Ollama is running (`ollama serve` in another terminal, or it auto-starts on Mac/Windows). Then click below."
			_action_button.text = "Test Connection"
			_status_label.text = ""
		3:
			_step_label.text = "All set. Your fish will start getting AI-flavored names within a few seconds. You can come back here any time to switch the model or turn AI off."
			_action_button.text = "Done"
			_status_label.text = ""
		_:
			pass


func _on_action_pressed() -> void:
	match _step:
		0:
			OS.shell_open("https://ollama.com/download")
			_show_step(1)
		1:
			var m: String = (String(_ai.model) if _ai != null else "qwen2.5:3b")
			DisplayServer.clipboard_set("ollama pull " + m)
			_status_label.add_theme_color_override("font_color", Color8(150, 230, 150))
			_status_label.text = "Copied to clipboard."
			_show_step(2)
		2:
			if _ai != null:
				_ai.enabled = true
				_ai.test_connection()
				_status_label.add_theme_color_override("font_color", Color8(180, 195, 220))
				_status_label.text = "Testing connection..."
			else:
				_status_label.add_theme_color_override("font_color", Color8(230, 120, 120))
				_status_label.text = "AIDirector unavailable. Restart the app and try again."
		3:
			_on_close()


func _on_connection_tested(success: bool, message: String) -> void:
	if _step != 2:
		return
	if success:
		_status_label.add_theme_color_override("font_color", Color8(150, 230, 150))
		_status_label.text = message
		_show_step(3)
	else:
		_status_label.add_theme_color_override("font_color", Color8(230, 120, 120))
		_status_label.text = message


func _on_close() -> void:
	if _step >= 3 and _ai != null and bool(_ai.enabled):
		var cfg := get_node_or_null("/root/TankConfig")
		if cfg != null:
			cfg.ai_enabled = true
			cfg.save_to_disk()
	emit_signal("closed")
	queue_free()


# Static helper: build + add to a parent, return the instance so caller
# can wire its `closed` signal. Centers in the parent's rect.
static func open_in(parent: Control) -> PanelContainer:
	var script: GDScript = load("res://scripts/ollama_onboarding.gd")
	var w: PanelContainer = script.new()
	parent.add_child(w)
	w.anchors_preset = Control.PRESET_CENTER
	w.position = (parent.size - w.size) * 0.5
	return w
