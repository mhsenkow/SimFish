extends PanelContainer

# Guardian mind onboarding — no text input.
#   DOWNLOAD: agree before a one-time ~250MB download (slim/dev builds).
#   BUNDLED_INFO: one-time OK for Steam builds that already include the model.

signal closed(accepted: bool)

const PRIVACY_NOTE: String = (
	"Runs 100% on your device. Nothing you say in the tank is sent anywhere. "
	+ "Turn off anytime in Settings → AI.")

enum Mode { DOWNLOAD, BUNDLED_INFO }

var _mode: int = Mode.DOWNLOAD
var _accept_btn: Button
var _decline_btn: Button


func _ready() -> void:
	custom_minimum_size = Vector2(460, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


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
	title.text = "Give your Guardian a voice?"
	PanelTheme.as_serif(title, PanelTheme.SIZE_ITEM, true)
	title.add_theme_color_override("font_color", Color8(255, 215, 110))
	v.add_child(title)

	var body := Label.new()
	body.name = "BodyLabel"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 12)
	body.add_theme_color_override("font_color", Color8(210, 220, 240))
	v.add_child(body)

	var privacy := Label.new()
	privacy.text = PRIVACY_NOTE
	privacy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	privacy.add_theme_font_size_override("font_size", 11)
	privacy.add_theme_color_override("font_color", Color8(140, 200, 150))
	v.add_child(privacy)

	var row := HBoxContainer.new()
	row.name = "ButtonRow"
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)

	_accept_btn = PanelTheme.make_primary_button("Continue")
	_accept_btn.pressed.connect(_on_accept)
	row.add_child(_accept_btn)

	_decline_btn = PanelTheme.make_secondary_button("Not now")
	_decline_btn.pressed.connect(_on_decline)
	row.add_child(_decline_btn)

	_apply_mode(_mode)


func setup(mode: int) -> void:
	_mode = mode
	if is_node_ready():
		_apply_mode(_mode)


func _apply_mode(mode: int) -> void:
	var body: Label = find_child("BodyLabel", true, false) as Label
	var row: HBoxContainer = find_child("ButtonRow", true, false) as HBoxContainer
	if body == null or row == null:
		return
	match mode:
		Mode.BUNDLED_INFO:
			body.text = (
				"Your Guardian can speak in its own words — a small AI bundled with the game, "
				+ "private and offline. Template lines still work if you skip this.")
			_accept_btn.text = "Got it"
			_decline_btn.visible = false
		_:
			body.text = (
				"Your Guardian can speak in its own words — a small AI that runs inside the game. "
				+ "This one-time download is about 250MB to your save folder, then works offline.")
			_accept_btn.text = "Yes — download & enable"
			_decline_btn.visible = true
			_decline_btn.text = "Not now — template voice only"


func _on_accept() -> void:
	_finish(true)


func _on_decline() -> void:
	_finish(false)


func _finish(accepted: bool) -> void:
	emit_signal("closed", accepted)
	queue_free()


static func open_in(parent: Node, mode: int = Mode.DOWNLOAD) -> PanelContainer:
	var script: GDScript = load("res://scripts/guardian_mind_onboarding.gd") as GDScript
	var w: PanelContainer = script.new()
	w.setup(mode)
	parent.add_child(w)
	if parent is Control:
		var host := parent as Control
		w.set_anchors_preset(Control.PRESET_CENTER)
		w.position = (host.size - w.custom_minimum_size) * 0.5
	else:
		var vp: Vector2 = parent.get_viewport().get_visible_rect().size
		w.position = (vp - w.custom_minimum_size) * 0.5
	return w
