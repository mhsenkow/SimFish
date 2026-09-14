extends SceneTree

# Render panel body layout.
#
# The fidelity hero — tier buttons, frame graph, resolution, MSAA, FXAA,
# deband, creature outline — used to sit directly on the panel's outer VBox,
# ABOVE the tab bar and outside any scroll container. It is ~600 px tall, so
# on a real panel the tab bodies were left a ~90 px slot: the Color theme tab
# existed but its contents could not be reached, because a scroll view that
# short has nowhere to scroll from.
#
# The hero is a tab of its own now. The property that keeps it fixed is not
# "the tabs are tall enough" (that depends on window size, which a headless
# run does not have) but the structural one: the TabContainer is the ONLY
# vertically-expanding child of the panel body, so every pixel the title and
# footer do not use goes to the tab bodies, and each body scrolls.


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_render_panel_tabs")

	# Loaded, not preloaded: render_panel.gd reads the TankConfig autoload,
	# which is not resolvable at this script's compile time.
	var script: GDScript = load("res://scripts/render_panel.gd")
	if not t.check(script != null, "render_panel.gd loads"):
		quit(t.finish())
		return
	var panel: Control = script.new() as Control
	root.add_child(panel)
	await process_frame

	var tabs: TabContainer = _first_of_type(panel, "TabContainer") as TabContainer
	if not t.check(tabs != null, "the render panel body is a TabContainer"):
		quit(t.finish())
		return

	var titles: Array[String] = []
	for i in tabs.get_tab_count():
		titles.append(tabs.get_tab_title(i))
	t.check(titles.has("Fidelity"),
		"the fidelity hero is its own tab, not a block above the tabs: %s"
			% ", ".join(titles))
	t.check(titles.has("Color theme"), "Color theme is a tab: %s" % ", ".join(titles))
	t.check(titles.has("Post-process"), "Post-process is a tab: %s" % ", ".join(titles))

	# Each tab body must be able to scroll, or a tall section is unreachable.
	for i in tabs.get_tab_count():
		var sc := tabs.get_tab_control(i) as ScrollContainer
		t.check(sc != null, "tab '%s' body is a ScrollContainer" % titles[i])
		if sc == null:
			continue
		t.check(sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED,
			"tab '%s' scrolls vertically" % titles[i])
		t.check(sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
			"tab '%s' does not scroll sideways (sliders would fight it)" % titles[i])
		t.check(sc.size_flags_vertical & Control.SIZE_EXPAND != 0,
			"tab '%s' body fills the tab" % titles[i])

	# THE regression guard: nothing else in the body column may expand, or it
	# takes the height back off the tabs.
	var body: Control = tabs.get_parent() as Control
	t.check(tabs.size_flags_vertical & Control.SIZE_EXPAND != 0,
		"the TabContainer expands to take the panel's leftover height")
	var greedy: Array[String] = []
	for child in body.get_children():
		var c := child as Control
		if c == null or c == tabs:
			continue
		if c.size_flags_vertical & Control.SIZE_EXPAND != 0:
			greedy.append(c.get_class())
	t.check(greedy.is_empty(),
		"only the TabContainer may expand vertically in the panel body — "
			+ "these also do and will squeeze the tabs: %s" % ", ".join(greedy))

	# And the duotone control is where a player would look for a color mode.
	var duotone_tab: String = _tab_titled_containing(tabs, "Full color")
	t.equals(duotone_tab, "Color theme",
		"the duotone mode picker lives in the Color theme tab")

	panel.queue_free()
	quit(t.finish())


func _first_of_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found: Node = _first_of_type(child, type_name)
		if found != null:
			return found
	return null


# Title of the tab whose subtree holds an OptionButton with this first item.
func _tab_titled_containing(tabs: TabContainer, first_item: String) -> String:
	for i in tabs.get_tab_count():
		var control: Control = tabs.get_tab_control(i)
		for node in _walk(control):
			var ob := node as OptionButton
			if ob != null and ob.item_count > 0 and ob.get_item_text(0) == first_item:
				return tabs.get_tab_title(i)
	return ""


func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out
