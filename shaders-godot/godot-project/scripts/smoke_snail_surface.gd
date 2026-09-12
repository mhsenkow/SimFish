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

	quit(t.finish())
