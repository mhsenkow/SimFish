extends SceneTree

# Direct light manipulation (LightHandle) and its wiring.
#
# Hover the lamp, press to grab it, drag to move it. The maths is
# pure; the wiring is asserted by source inspection because a helper that
# nothing calls is the failure mode that has already shipped twice here.

const H := preload("res://scripts/light_handle.gd")
const R := preload("res://scripts/lighting_rig.gd")


func _init() -> void:
	var t := TestSupport.Suite.new("light_handle")

	# --- grabbing ---------------------------------------------------------
	t.check(H.grab_radius(true) > H.grab_radius(false),
		"a finger gets a fatter target than a mouse")
	var handle := Vector2(400.0, 300.0)
	t.check(H.hit_test(Vector2(410.0, 305.0), handle, H.GRAB_RADIUS_PX),
		"near the lamp grabs it")
	t.check(not H.hit_test(Vector2(700.0, 300.0), handle, H.GRAB_RADIUS_PX),
		"far from the lamp does not")
	t.check(not H.hit_test(Vector2(400.0, 300.0), Vector2.INF, H.GRAB_RADIUS_PX),
		"an off-screen lamp cannot be grabbed")

	# --- ray to plane -----------------------------------------------------
	var hit: Vector3 = H.ray_plane_xz(
		Vector3(0.0, 20.0, 0.0), Vector3(0.2, -1.0, 0.1).normalized(), 10.0)
	t.approx(hit.y, 10.0, "the drag lands on the plane")
	t.check(hit.x > 0.0 and hit.z > 0.0, "and in the direction dragged")
	# A ray that would only meet the plane BEHIND the camera must not move
	# the lamp - otherwise dragging past the horizon teleports it.
	t.equals(H.ray_plane_xz(Vector3(0.0, 20.0, 0.0), Vector3(0.0, 1.0, 0.0), 10.0),
		Vector3.INF, "an upward ray never lands")
	t.equals(H.ray_plane_xz(Vector3(0.0, 5.0, 0.0), Vector3(0.0, -1.0, 0.0), 10.0),
		Vector3.INF, "a plane behind the camera is refused")
	t.equals(H.ray_plane_xz(Vector3(0.0, 20.0, 0.0), Vector3(1.0, 0.0, 0.0), 10.0),
		Vector3.INF, "a parallel ray is refused, not a division by zero")

	# --- offsets ----------------------------------------------------------
	var hw := 5.0
	var hd := 5.0
	var mid: Vector2 = H.offsets_from_world(Vector3(2.5, 11.0, -5.0), hw, hd)
	t.approx(mid.x, 0.5, "world x maps to a half-extent fraction")
	t.approx(mid.y, -1.0, "world z maps to a half-extent fraction")
	# The lamp may overhang the rim a little - a clip light really does -
	# but must not end up across the room.
	var far: Vector2 = H.offsets_from_world(Vector3(500.0, 11.0, -500.0), hw, hd)
	t.approx(far.x, H.HEAD_OVERHANG, "a wild drag clamps to the overhang")
	t.approx(far.y, -H.HEAD_OVERHANG, "in both directions")
	t.check(H.HEAD_OVERHANG > 1.0, "a clip lamp is allowed to overhang the rim")

	# The AIM is stricter: a cone aimed outside the tank is the exact bug
	# the whole rig exists to prevent, so a drag can never produce one.
	var wild: Vector2 = H.aim_from_world(Vector3(900.0, 0.0, -900.0), hw, hd)
	t.check(absf(wild.x) < 1.0 and absf(wild.y) < 1.0,
		"a wild aim drag stays inside the glass")
	var _hex: Array = [
		Vector3(5.0, 0.0, 0.0), Vector3(2.5, 0.0, 5.0), Vector3(-2.5, 0.0, 5.0),
		Vector3(-5.0, 0.0, 0.0), Vector3(-2.5, 0.0, -5.0), Vector3(2.5, 0.0, -5.0)]
	for i in 24:
		var a: float = TAU * float(i) / 24.0
		var probe := Vector3(cos(a) * 40.0, 0.0, sin(a) * 40.0)
		var clamped: Vector2 = H.aim_from_world(probe, hw, hd)
		var tgt: Vector3 = R.aim_target(hw, hd, 2.2, clamped.x, clamped.y)
		t.check(absf(tgt.x) <= hw and absf(tgt.z) <= hd,
			"aim from any drag direction stays in bounds (%.0f deg)"
			% rad_to_deg(a))

	# --- head position agrees with the rig --------------------------------
	# If these two ever disagree, the grab handle floats away from the lamp
	# it is supposed to be attached to.
	for ox in [-1.0, -0.3, 0.0, 0.55, 1.0]:
		for oz in [-1.0, 0.0, 0.8]:
			var a1: Vector3 = H.head_world(hw, hd, 11.0, 0.05, ox, oz)
			var a2: Vector3 = R.head_position(hw, hd, 11.0, 0.05, ox, oz)
			t.approx(a1.x, a2.x, "handle and rig agree on x (%.2f)" % ox, 0.001)
			t.approx(a1.z, a2.z, "handle and rig agree on z (%.2f)" % oz, 0.001)
			t.approx(a1.y, a2.y, "handle and rig agree on height", 0.001)

	t.approx(H.quantise(0.123456), 0.12, "values settle to two decimals")
	t.check(H.describe(0.55, -1.0, -0.22, 0.3).contains("aim"),
		"the log line names both halves")

	# --- progressive disclosure -------------------------------------------
	# Handles that are always on clutter the tank; handles that never show
	# are never found. They fade up as the cursor approaches.
	var lamp := Vector2(400.0, 300.0)
	# The invariant that keeps tightening these safe: a handle must never be
	# grabbable while still fading in, or you click something half-drawn.
	t.check(H.REVEAL_NEAR_PX >= H.GRAB_RADIUS_PX,
		"fully revealed before it can be grabbed by mouse")
	t.check(H.REVEAL_NEAR_PX >= H.GRAB_RADIUS_PX_TOUCH,
		"fully revealed before it can be grabbed by touch")
	t.check(H.REVEAL_FAR_PX > H.REVEAL_NEAR_PX,
		"there is a fade band, not a hard pop")
	t.approx(H.reveal(lamp, lamp), 1.0, "on the lamp, fully revealed")
	t.approx(H.reveal(lamp + Vector2(H.GRAB_RADIUS_PX_TOUCH, 0.0), lamp), 1.0,
		"at the very edge of the grab radius it is already at full strength")
	t.approx(H.reveal(lamp + Vector2(H.REVEAL_NEAR_PX - 5.0, 0.0), lamp), 1.0,
		"inside the near radius, fully revealed")
	t.approx(H.reveal(lamp + Vector2(H.REVEAL_FAR_PX + 50.0, 0.0), lamp), 0.0,
		"far away, hidden")
	t.approx(H.reveal(Vector2(0.0, 0.0), Vector2.INF), 0.0,
		"an off-screen lamp reveals nothing")
	var mid_r: float = H.reveal(
		lamp + Vector2((H.REVEAL_NEAR_PX + H.REVEAL_FAR_PX) * 0.5, 0.0), lamp)
	t.in_range(mid_r, 0.2, 0.8, "it fades rather than snapping on")
	# Monotonic: approaching the lamp must never make the gizmo dimmer.
	var prev_r: float = -1.0
	for i in range(30, -1, -1):
		var d: float = float(i) / 30.0 * (H.REVEAL_FAR_PX + 60.0)
		var rv: float = H.reveal(lamp + Vector2(d, 0.0), lamp)
		t.check(rv >= prev_r - 1e-6, "reveal rises as you approach (%.0f px)" % d)
		prev_r = rv

	# --- picking ----------------------------------------------------------
	var aim := Vector2(520.0, 460.0)
	t.equals(H.pick(lamp, lamp, aim, H.GRAB_RADIUS_PX), H.LAMP, "lamp picked")
	t.equals(H.pick(aim, lamp, aim, H.GRAB_RADIUS_PX), H.AIM, "aim picked")
	t.equals(H.pick(Vector2(50.0, 50.0), lamp, aim, H.GRAB_RADIUS_PX), H.NONE,
		"empty space picks nothing, so the camera still gets the drag")
	# On a top-down camera the two rings can land on top of each other. The
	# lamp must win, because it is the thing people reach for.
	t.equals(H.pick(lamp, lamp, lamp, H.GRAB_RADIUS_PX), H.LAMP,
		"overlapping handles resolve to the lamp")
	t.equals(H.pick(lamp, Vector2.INF, lamp, H.GRAB_RADIUS_PX), H.AIM,
		"with no lamp on screen the aim is still grabbable")
	t.equals(H.handle_label(H.LAMP), "Lamp", "handles are nameable")
	t.equals(H.handle_label(H.AIM), "Aim", "both of them")

	# --- cancel -----------------------------------------------------------
	# A drag you cannot undo is a drag people are afraid to try.
	var snap: Dictionary = H.snapshot(0.55, -1.0, -0.22, 0.30)
	t.check(not H.snapshot_changed(snap, 0.55, -1.0, -0.22, 0.30),
		"an unmoved drag is not a change, so it is not saved")
	t.check(H.snapshot_changed(snap, 0.20, -1.0, -0.22, 0.30),
		"moving the lamp counts as a change")
	t.check(H.snapshot_changed(snap, 0.55, -1.0, 0.40, 0.30),
		"moving the aim counts as a change")
	t.check(not H.snapshot_changed({}, 0.1, 0.2, 0.3, 0.4),
		"no snapshot means nothing to compare, not a spurious save")

	# --- wiring -----------------------------------------------------------
	# --- drag model (bug B: the lamp flew around the room) ----------------
	# A click without a move changes nothing: the grab offset is kept.
	var st := Vector3(1.0, 9.0, -2.0)
	var gh := Vector3(1.3, 9.0, -1.6)
	t.check(H.dragged(st, gh, gh).is_equal_approx(st),
		"pressing on the lamp does not snap it to the cursor")
	t.check(H.dragged(st, gh, gh + Vector3(0.5, 0.0, 0.25)).is_equal_approx(
		st + Vector3(0.5, 0.0, 0.25)), "the lamp moves by exactly the cursor's travel")
	# Grazing view: a flat-plane hit explodes, the upright surface does not.
	var cam := Vector3(0.0, 9.2, 14.0)
	var d1 := Vector3(0.0, -0.02, -1.0).normalized()
	var d2 := Vector3(0.0, -0.03, -1.0).normalized()
	t.check(H.choose_surface(d1) == H.SURFACE_UPRIGHT,
		"a near edge-on view drags on the upright surface")
	t.check(H.choose_surface(Vector3(0.1, -0.8, -0.5).normalized()) == H.SURFACE_FLAT,
		"a steep view drags on the lamp's own plane")
	var flat_jump: float = H.ray_plane_xz(cam, d1, 9.0).distance_to(
		H.ray_plane_xz(cam, d2, 9.0))
	var view: Vector3 = H.view_flat(d1)
	var anc := Vector3(0.0, 9.0, 0.0)
	var up_jump: float = H.surface_hit(H.SURFACE_UPRIGHT, cam, d1, 9.0, anc, view) \
		.distance_to(H.surface_hit(H.SURFACE_UPRIGHT, cam, d2, 9.0, anc, view))
	t.check(flat_jump > 3.0 and up_jump < 0.5,
		"a one-pixel move at a grazing angle no longer slams the lamp "
		+ "(flat %.2f vs upright %.2f)" % [flat_jump, up_jump])
	t.check(is_finite(H.surface_hit(H.SURFACE_UPRIGHT, cam, d1, 9.0, anc, view).x),
		"the upright surface always lands")
	# One head position for build and drag.
	var home: Vector2 = H.fixture_home("gooseneck")
	var hw0: Vector3 = H.head_world(10.0, 5.0, 8.0, H.mount_above("gooseneck", 1.4),
		home.x + 0.2, home.y + 0.1)
	t.approx(hw0.y, 8.0 + H.GOOSENECK_MOUNT_ABOVE, "the gooseneck head hangs at its rim mount")
	var back: Vector2 = H.offsets_relative(Vector2(hw0.x, hw0.z), 10.0, 5.0, home)
	t.check(back.is_equal_approx(Vector2(0.2, 0.1)),
		"offsets round-trip through the fixture home (the drag dropped it)")
	# Footprint-aware clamp: a hex corner is not a rectangle corner.
	var hex: Array = []
	for i in 6:
		var a: float = TAU * float(i) / 6.0
		hex.append(Vector3(cos(a) * 10.0, 0.0, sin(a) * 10.0))
	var corner := Vector2(9.5, 8.5)  # inside the bounding box, outside the hex
	var cl: Vector2 = H.clamp_to_footprint(corner, hex, H.AIM_INSET)
	var hex2 := PackedVector2Array()
	for c in hex:
		hex2.append(Vector2((c as Vector3).x, (c as Vector3).z))
	t.check(Geometry2D.is_point_in_polygon(cl, hex2)
			and not Geometry2D.is_point_in_polygon(corner, hex2),
		"the aim is pulled inside a hex, not just its bounding box")
	t.check(H.clamp_to_footprint(Vector2(1.0, -2.0), hex, H.AIM_INSET)
		.is_equal_approx(Vector2(1.0, -2.0)), "a point already inside is left alone")

	var m: String = _read("res://scripts/main.gd")
	t.check(m.contains("_handle_light_handle_input("),
		"main.gd routes input to the light handle")
	# No modes. Dragging starts on press, straight from hover.
	t.check(not m.contains("_light_adjust_active"),
		"the old double-click-to-enter-a-mode flow is gone")
	t.check(not m.contains("mb.double_click and _light"),
		"grabbing is not gated behind a double-click")
	t.check(m.contains("_begin_light_drag(") and m.contains("_end_light_drag("),
		"press begins a drag and release ends it")
	t.check(m.contains("_cancel_light_drag()"),
		"a drag can be cancelled")
	t.check(m.contains("MOUSE_BUTTON_RIGHT") and m.contains("_cancel_light_drag"),
		"right-click aborts mid-drag, not just Escape")
	t.check(m.contains("_persist_light_placement()"),
		"a move is saved, not lost on reload")
	t.check(m.contains("snapshot_changed("),
		"an unmoved drag does not write a save")
	t.check(m.contains("CURSOR_POINTING_HAND"),
		"the cursor says the handle is grabbable")
	t.check(m.contains("_refresh_light_gizmo("),
		"the gizmo follows the mouse")
	t.check(m.contains("_viewport_to_window("),
		"world positions are mapped out of the SubViewport for the overlay")

	var g: String = _read("res://scripts/light_gizmo.gd")
	t.check(g.contains("MOUSE_FILTER_IGNORE"),
		"the overlay never eats a click - it would block the whole tank")
	t.check(g.contains("func refresh("),
		"the gizmo repaints only when something changed")
	# A handle whose anchor is off to the side unprojects to a large FINITE
	# position, so an INF check alone let the old lamp-to-aim link draw a
	# long stray line straight across the tank.
	t.check(g.contains("func _on_screen("),
		"handles are bounds-checked, not just INF-checked")
	t.check(g.contains("is_finite(p.x)"),
		"and non-finite positions are rejected")
	t.check(not g.contains("_draw_link"),
		"the lamp-to-aim line is gone - it read as an artifact, not a cue")

	var w: String = _read("res://scripts/world.gd")
	for fn in ["func set_light_head_offset(", "func set_light_aim(",
			"func light_fixture_head_world(", "func has_movable_light(",
			"func light_aim_world(", "func set_light_highlight("]:
		t.check(w.contains(fn), "world.gd exposes %s" % fn.trim_prefix("func "))
	t.check(w.contains("_update_light_beams()")
			and not w.contains("_rebuild_light_beam"),
		"moving the lamp updates its shafts in place (the per-event rebuild leaked cones)")
	# Dragging for a few seconds must not leave a fan of stale cones and
	# particle emitters behind.
	t.check(w.contains("BEAM_SPOT_META") and w.contains("BEAM_MOTES_META"),
		"each shaft carries its spot and motes - no name matching")
	var bd: String = m.substr(m.find("func _begin_light_drag("), 2600)
	t.check(bd.contains("_suppress_drag_until_release = true"),
		"grabbing the light holds the POLLED camera orbit off until release")
	t.check(not bd.contains("spot_aim_x = 0.0"),
		"grabbing no longer forces the aim to the tank centre")
	t.check(not bd.contains("_light_drag_to("),
		"pressing does not move anything; only motion does")
	t.check(m.contains("_window_to_viewport_exact("),
		"the drag reads the cursor through the inverse of the ring's mapping")
	t.check(w.contains("_light_highlight_on")
			and w.contains("LIGHT_HIGHLIGHT_BOOST"),
		"the hover highlight rides inside the per-frame emissive sync, "
		+ "which would otherwise clobber it")

	quit(t.finish())


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt: String = f.get_as_text()
	f.close()
	return txt
