extends PanelContainer

# Guardian mind onboarding — no text input.
#   DOWNLOAD: agree before a one-time ~250MB download (slim/dev builds).
#   BUNDLED_INFO: one-time OK for Steam builds that already include the model.

signal closed(accepted: bool)

const PRIVACY_NOTE: String = (
	"Runs on your device only — private and offline. Nothing leaves your machine. "
	+ "Turn off anytime in Settings → AI.")

enum Mode { DOWNLOAD, BUNDLED_INFO, NORTH_STAR }

var _mode: int = Mode.DOWNLOAD
var _accept_btn: Button
var _decline_btn: Button


func _ready() -> void:
	custom_minimum_size = Vector2(PanelTheme.PANEL_MIN_W, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func _build_ui() -> void:
	# Shared modal chrome (was a hand-built stylebox with its own radius).
	PanelTheme.apply_modal_chrome(self)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)

	# House header: title + ×. The × is "not now" on the consent step and
	# "got it" on the info steps — closing never opts the player in.
	var header := PanelTheme.make_panel_header(tr("Give your Guardian a voice?"),
		_on_header_close)
	header.get_child(0).name = "TitleLabel"
	v.add_child(header)
	v.add_child(PanelTheme.make_rule())

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

	_accept_btn = PanelTheme.make_primary_button("Continue")
	_accept_btn.pressed.connect(_on_accept)
	_decline_btn = PanelTheme.make_secondary_button("Not now")
	_decline_btn.pressed.connect(_on_decline)
	# Actions footer, primary rightmost.
	var row := PanelTheme.make_panel_footer(Callable(), _accept_btn, [_decline_btn])
	row.name = "ButtonRow"
	v.add_child(row)

	_apply_mode(_mode)


func setup(mode: int) -> void:
	_mode = mode
	if is_node_ready():
		_apply_mode(_mode)


func _apply_mode(mode: int) -> void:
	var body: Label = find_child("BodyLabel", true, false) as Label
	var row: Control = find_child("ButtonRow", true, false) as Control
	var title: Label = find_child("TitleLabel", true, false) as Label
	if body == null or row == null:
		return
	match mode:
		Mode.NORTH_STAR:
			if title != null:
				title.text = tr("Small minds, private voice")
			body.text = (
				"This tank simulates real inner lives — moods, wants, memory — in every fish. "
				+ "Optionally, your device turns that into quiet diary text. Nothing is sent anywhere; "
				+ "the model only voices what the simulation already knows. We never claim consciousness — "
				+ "only patterns your machine imagines, privately, for you. "
				+ "You're not a perfect creator — just someone making a soul anyway.")
			_accept_btn.text = tr("Got it")
			_decline_btn.visible = false
		Mode.BUNDLED_INFO:
			if title != null:
				title.text = tr("A fish here can develop a voice")
			body.text = (
				"One fish in your tank can speak in its own words — a small model bundled with "
				+ "the game, private and offline. Template thoughts still work if you skip this.")
			_accept_btn.text = tr("Got it")
			_decline_btn.visible = false
		_:
			if title != null:
				title.text = tr("A fish here can develop a voice")
			body.text = (
				"One fish here can develop a voice — it runs on your device, private. "
				+ "This one-time download is about 250MB to your save folder, then works offline. "
				+ "Want that?")
			_accept_btn.text = tr("Yes — download & enable")
			_decline_btn.visible = true
			_decline_btn.text = tr("Not now — template voice only")


func _on_header_close() -> void:
	if _decline_btn != null and _decline_btn.visible:
		_on_decline()
	else:
		_on_accept()


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
