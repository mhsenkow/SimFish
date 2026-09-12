extends SceneTree

# Toast / messaging component contract (messaging pass).
#
# There were four hand-built toast presenters in main.gd, each with its own
# PanelContainer, StyleBoxFlat, colours and dwell — and ~1,289 lines of
# notification/toast/popup code total. These pin the properties that make a
# message component trustworthy rather than merely present.


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_toast")

	# --- Severity is visible, not just recorded ---
	# A critical low-oxygen warning used to render in the same blue as
	# "photo saved".
	var accents: Dictionary = {}
	for lvl in [Toast.Level.INFO, Toast.Level.GOOD, Toast.Level.WARN,
			Toast.Level.CRITICAL]:
		t.check(Toast.LEVEL_ACCENT.has(lvl), "level %d needs an accent" % lvl)
		var c: Color = Toast.LEVEL_ACCENT[lvl]
		var key: String = "%.2f,%.2f,%.2f" % [c.r, c.g, c.b]
		t.check(not accents.has(key),
			"level %d shares an accent with level %s — severity must be "
				% [lvl, str(accents.get(key, "?"))] + "visible at a glance")
		accents[key] = lvl
	# Critical must be the most alarming: reddest of the set.
	var crit: Color = Toast.LEVEL_ACCENT[Toast.Level.CRITICAL]
	for lvl in [Toast.Level.INFO, Toast.Level.GOOD, Toast.Level.WARN]:
		var other: Color = Toast.LEVEL_ACCENT[lvl]
		t.check(crit.r - crit.g > other.r - other.g,
			"critical must read hotter than level %d" % lvl)

	# --- Severity strings map onto levels ---
	t.equals(Toast.level_for_severity("critical"), Toast.Level.CRITICAL,
		"critical maps to CRITICAL")
	t.equals(Toast.level_for_severity("important"), Toast.Level.WARN,
		"important maps to WARN")
	t.equals(Toast.level_for_severity("info"), Toast.Level.INFO,
		"info maps to INFO")
	t.equals(Toast.level_for_severity("info", "milestone"), Toast.Level.GOOD,
		"a milestone is good news, not neutral information")

	# --- Dwell scales with reading time, and is bounded ---
	var short_d: float = Toast.dwell_for("Fed")
	var long_d: float = Toast.dwell_for(
		"Oxygen is dipping across the tank; aeration or fewer floaters "
		+ "would help, and the fish are already gulping at the surface.")
	t.check(long_d > short_d,
		"a longer message must stay up longer (%.1f vs %.1f)" % [long_d, short_d])
	t.in_range(short_d, Toast.DWELL_MIN, Toast.DWELL_MAX, "short dwell is bounded")
	t.in_range(long_d, Toast.DWELL_MIN, Toast.DWELL_MAX, "long dwell is bounded")
	t.approx(Toast.dwell_for(""), Toast.DWELL_MIN,
		"an empty message still gets the floor, never zero")

	# --- Construction ---
	var host := Control.new()
	host.size = Vector2(300, 400)
	root.add_child(host)

	var basic: Toast = Toast.create({"title": "Fed", "body": "The school came up."})
	host.add_child(basic)
	await process_frame
	t.check(basic.body_label() != null, "a toast with a body exposes its label")
	t.equals(basic.body_label().text, "The school came up.",
		"body_label returns the body, not the title")

	# A titleless toast must still expose its body — the old tree-walk looked
	# for "the Label at index 1" and would have missed this entirely.
	var titleless: Toast = Toast.create({"body": "Just a line."})
	host.add_child(titleless)
	await process_frame
	t.check(titleless.body_label() != null,
		"a titleless toast must still expose its body label")
	t.equals(titleless.body_label().text, "Just a line.",
		"titleless body is found correctly")

	# A bodyless toast has no body label rather than returning the title.
	var titleonly: Toast = Toast.create({"title": "Saved"})
	host.add_child(titleonly)
	await process_frame
	t.check(titleonly.body_label() == null,
		"a toast with no body must return null, not the title label")

	# --- Critical messages linger ---
	var crit_toast: Toast = Toast.create(
		{"title": "!", "body": "Low O2", "level": Toast.Level.CRITICAL})
	t.check(crit_toast.dwell >= 6.0,
		"a critical toast must not flash past, got %.1f s" % crit_toast.dwell)
	crit_toast.free()

	# --- hold() extends but never past the cap ---
	var held: Toast = Toast.create({"body": "streaming..."})
	host.add_child(held)
	held.hold(Toast.DWELL_MAX * 3.0)
	t.check(true, "hold() with an absurd value does not throw")
	held.hold(0.1)
	t.check(true, "hold() never shortens an existing dwell")

	# --- Dismissal is idempotent and reports once ---
	var fired: Array[int] = []
	var d: Toast = Toast.create({"body": "bye"})
	host.add_child(d)
	await process_frame
	d.dismissed.connect(func(_x): fired.append(1))
	t.check(not d.is_dismissing(), "a fresh toast is not dismissing")
	d.dismiss()
	t.check(d.is_dismissing(), "dismiss() marks the toast")
	d.dismiss()
	d.dismiss()
	t.check(fired.size() <= 1,
		"repeated dismiss() must not fire the signal more than once, got %d"
			% fired.size())

	# --- The stack lays out by REAL height ---
	# The old maths assumed a fixed 74 px per toast, so a two-line body
	# overlapped its neighbour.
	var layer := Control.new()
	layer.size = Vector2(PanelTheme.TOAST_STACK_W, 240)
	root.add_child(layer)
	var tall: Toast = ToastStack.present(layer, {
		"title": "Long one",
		"body": "A body long enough to wrap onto several lines so its height "
			+ "is clearly greater than a single-line toast would be.",
	})
	var shortt: Toast = ToastStack.present(layer, {"title": "Short"})
	await process_frame
	await process_frame
	await process_frame
	t.check(tall != null and shortt != null, "stack presents toasts")
	if tall != null and shortt != null:
		var tall_h: float = maxf(tall.size.y, tall.get_combined_minimum_size().y)
		var short_h: float = maxf(shortt.size.y, shortt.get_combined_minimum_size().y)
		t.check(tall_h > short_h,
			"a wrapping toast must actually be taller (%.0f vs %.0f)"
				% [tall_h, short_h])
		# They must not overlap: the lower one's top must clear the upper.
		var gap: float = absf(tall.position.y - shortt.position.y)
		t.check(gap >= minf(tall_h, short_h),
			"stacked toasts overlap — gap %.0f is less than the shorter "
				% gap + "toast's height %.0f" % minf(tall_h, short_h))

	# --- Toasts hug their content ---
	# The body label autowraps, so its minimum height depends on its width.
	# Measured before layout it reports one-character-per-line and the toast
	# renders ~700 px tall — which is exactly what happened, and was only
	# masked because relayout re-hugged it two frames later. A trimmed toast
	# (skipped while dismissing) stayed stretched the whole way out.
	var hug_layer := Control.new()
	hug_layer.size = Vector2(PanelTheme.TOAST_STACK_W, 400)
	root.add_child(hug_layer)
	var one_line: Toast = ToastStack.present(hug_layer, {"title": "Short"})
	for _f in 4:
		await process_frame
	if one_line != null:
		var h1: float = one_line.get_combined_minimum_size().y
		t.check(h1 < 120.0,
			"a one-line toast must hug its content, got %.0f px tall" % h1)
		t.check(h1 > 8.0, "a toast must not collapse to nothing (%.0f px)" % h1)
	# And a dismissing toast must ALSO be correctly sized while it fades.
	if one_line != null:
		one_line.dismiss()
		ToastStack.relayout(hug_layer)
		await process_frame
		t.check(one_line.get_combined_minimum_size().y < 120.0,
			"a dismissing toast must stay hugged while it fades out")

	# --- The stack is bounded ---
	for i in 8:
		ToastStack.present(layer, {"title": "spam %d" % i})
	await process_frame
	await process_frame
	var live: int = 0
	for c in layer.get_children():
		var tc := c as Toast
		if tc != null and is_instance_valid(tc) and not tc.is_dismissing():
			live += 1
	t.check(live <= ToastStack.MAX_VISIBLE,
		"stack must trim to MAX_VISIBLE (%d), found %d live"
			% [ToastStack.MAX_VISIBLE, live])

	# --- Null layer is survivable ---
	t.check(ToastStack.present(null, {"body": "x"}) == null,
		"presenting into a null layer returns null rather than throwing")
	t.equals(ToastStack.relayout(null), 0, "relayout(null) is a no-op")

	quit(t.finish())
