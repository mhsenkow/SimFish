# Shared URLs and a small "Info & links" popup used from the tank menu and
# in-game System rail.
class_name AppLinks
extends RefCounted

const GITHUB_REPO := "https://github.com/mhsenkow/SimFish"
const GITHUB_ISSUES := "https://github.com/mhsenkow/SimFish/issues"
const GITHUB_PAGES := "https://mhsenkow.github.io/SimFish/"


static func open_repo() -> void:
	OS.shell_open(GITHUB_REPO)


static func open_issues() -> void:
	OS.shell_open(GITHUB_ISSUES)


static func open_pages() -> void:
	OS.shell_open(GITHUB_PAGES)


static func show_info_popup(parent: Node) -> void:
	if parent == null:
		return
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 500
	parent.add_child(overlay)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(bg)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -240
	panel.offset_top = -170
	panel.offset_right = 240
	panel.offset_bottom = 170
	PanelTheme.apply_panel_chrome(panel)
	overlay.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	vb.add_child(PanelTheme.make_title("walstad loom"))
	vb.add_child(PanelTheme.make_rule())

	var body := PanelTheme.make_description()
	body.text = "Generative pixel-art Walstad aquarium. Source is on GitHub; report bugs and read install notes on the project site."
	body.add_theme_font_size_override("font_size", PanelTheme.SIZE_BODY)
	vb.add_child(body)

	var site_btn := Button.new()
	site_btn.text = "Open project website"
	site_btn.tooltip_text = GITHUB_PAGES
	site_btn.custom_minimum_size = Vector2(0, 44)
	site_btn.pressed.connect(func():
		open_pages()
		overlay.queue_free())
	vb.add_child(site_btn)

	var issues_btn := Button.new()
	issues_btn.text = "Report an issue on GitHub"
	issues_btn.tooltip_text = GITHUB_ISSUES
	issues_btn.custom_minimum_size = Vector2(0, 44)
	issues_btn.pressed.connect(func():
		open_issues()
		overlay.queue_free())
	vb.add_child(issues_btn)

	var repo_btn := Button.new()
	repo_btn.text = "View source repository"
	repo_btn.tooltip_text = GITHUB_REPO
	repo_btn.custom_minimum_size = Vector2(0, 40)
	repo_btn.flat = true
	repo_btn.pressed.connect(func():
		open_repo()
		overlay.queue_free())
	vb.add_child(repo_btn)

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): overlay.queue_free())
	vb.add_child(close)
