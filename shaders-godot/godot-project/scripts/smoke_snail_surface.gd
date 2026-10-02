extends SceneTree

# Surface-film glide + waterline band geometry (SnailSurface).
#
# The bug this is really guarding: _shell_up() used to collapse any vertical
# wall normal to Vector3.UP via absf(). That is correct on the substrate and
# WRONG under the surface film, where it stands the snail upright on top of
# the water instead of hanging it beneath. The sign test is one character
# and silently produces a plausible-looking wrong result, so it is asserted.

const S := preload("res://scripts/snail_surface.gd")


func _init() -> void:
	var t := TestSupport.Suite.new("snail_surface")

	# --- which way up ----------------------------------------------------
	t.equals(S.shell_up_for(Vector3.UP), Vector3.UP,
		"substrate snail stands up")
	t.equals(S.shell_up_for(Vector3.DOWN), Vector3.DOWN,
		"film snail hangs inverted (NOT up)")
	# Vertical glass: the normal passes through unchanged.
	t.equals(S.shell_up_for(Vector3.RIGHT), Vector3.RIGHT,
		"glass snail's shell points into the tank")
	# Degenerate input must not produce a non-finite basis.
	t.equals(S.shell_up_for(Vector3.ZERO), Vector3.UP,
		"zero normal falls back to up")
	# Un-normalised input still resolves to a unit axis.
	t.equals(S.shell_up_for(Vector3(0.0, -4.0, 0.0)), Vector3.DOWN,
		"un-normalised down normal still inverts")
	# Every result must be usable as a Basis up-vector.
	for n in [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.BACK,
			Vector3.ZERO, Vector3(0.3, -0.9, 0.1)]:
		var up: Vector3 = S.shell_up_for(n)
		t.approx(up.length(), 1.0, "shell_up is unit for %s" % str(n), 0.001)

	t.check(S.is_film_normal(Vector3.DOWN), "DOWN is a film normal")
	t.check(not S.is_film_normal(Vector3.UP), "UP is not a film normal")
	t.check(not S.is_film_normal(Vector3.RIGHT), "glass is not a film normal")

	# --- film plane ------------------------------------------------------
	# Must sit BELOW the water line, never on or above it, or the shell
	# renders poking out of the surface.
	var water_y := 6.5
	t.approx(S.film_plane_y(water_y, 0.05), 6.45, "film plane is submerged")
	t.check(S.film_plane_y(water_y, 0.05) < water_y,
		"film plane is strictly below the water surface")
	t.approx(S.film_plane_y(water_y, -1.0), water_y,
		"negative submerge cannot push the snail above water")

	# --- waterline band --------------------------------------------------
	var band := 0.55
	t.check(S.in_waterline_band(6.5, water_y, band), "at the surface is in band")
	t.check(S.in_waterline_band(6.0, water_y, band), "just under is in band")
	t.check(not S.in_waterline_band(5.5, water_y, band), "1.0 down is out of band")
	t.check(not S.in_waterline_band(6.8, water_y, band),
		"above the water is NOT in band (would strand a snail in air)")

	# --- attach chance ---------------------------------------------------
	var base := 0.55
	var pen := 0.45
	t.approx(S.film_attach_chance(base, 1.0, pen), base,
		"an average shell uses the base chance")
	t.check(S.film_attach_chance(base, 2.0, pen)
			< S.film_attach_chance(base, 1.0, pen),
		"a heavier shell takes the film less often")
	t.check(S.film_attach_chance(base, 5.0, pen) > 0.0,
		"even the largest shell still surfaces sometimes")
	# Monotonic and always a valid probability.
	var prev := 1.1
	for i in 12:
		var sz: float = 0.5 + float(i) * 0.25
		var c: float = S.film_attach_chance(base, sz, pen)
		t.in_range(c, 0.0, 1.0, "chance is a probability at size %.2f" % sz)
		t.check(c <= prev + 1e-6, "chance is non-increasing at size %.2f" % sz)
		prev = c

	# --- Holistic #126 corner continuity (box + hex) ----------------------
	var box_a := Vector3.RIGHT
	var box_b := Vector3.FORWARD
	t.check(S.should_transfer_wall(box_a, box_b, 0.12),
		"box corner within band triggers transfer")
	t.check(not S.should_transfer_wall(box_a, box_a, 0.12),
		"same face does not transfer")
	t.check(not S.should_transfer_wall(box_a, box_b, 0.80),
		"far from corner does not transfer")
	# Hex faces meet at ~60° — normals still diverge enough.
	var hex_a := Vector3(1.0, 0.0, 0.0)
	var hex_b := Vector3(0.5, 0.0, 0.866).normalized()
	t.check(S.should_transfer_wall(hex_a, hex_b, 0.18),
		"hex corner within band triggers transfer")
	var pos := Vector3(3.0, 2.5, 3.0)
	var wrapped: Vector3 = S.wrap_position_around_corner(pos, box_a, box_b, 0.06)
	t.approx(wrapped.y, pos.y, "corner wrap preserves height")
	t.check(wrapped.distance_to(pos) < 0.35,
		"corner wrap is a short seam step, not a jump (%.3f)" % wrapped.distance_to(pos))
	var blended: Vector3 = S.blend_wall_normal(box_a, box_b, 0.5)
	t.approx(blended.length(), 1.0, "blended normal is unit")
	t.check(blended.dot(box_a) > 0.3 and blended.dot(box_b) > 0.3,
		"blended normal sits between faces")
	# Slime trail must not emit a single interior chord across a corner hop.
	var far := pos + Vector3(-0.8, 0.0, -0.8)
	var anchors: Array = S.slime_trail_anchors(pos, box_a, far, box_b, 0.4)
	t.check(anchors.size() >= 2,
		"corner hop emits glass-side intermediate slime marks")
	var interior_hits: int = 0
	for a in anchors:
		var ap: Vector3 = a as Vector3
		# A mark deep in +inward of both walls would be interior paint.
		if ap.dot(box_a) < pos.dot(box_a) - 0.2 and ap.dot(box_b) < pos.dot(box_b) - 0.2:
			interior_hits += 1
	t.equals(interior_hits, 0, "slime anchors do not paint the aquarium interior")

	quit(t.finish())
