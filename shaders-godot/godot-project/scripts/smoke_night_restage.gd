extends SceneTree

# Night restages the picture; it does not tint it (VISUAL_DIRECTIONS #15).
#
# The day/night machinery here is good — a second night palette LUT, a smooth
# blend driven by daylight(), highlight burnthrough so emissive content stays
# bright against a moonlit field, sunset warmth, moonlight. All of it is TINT.
# The composition at midnight was identical to the composition at noon: the
# same surfaces, lit the same way, in a different colour.
#
# In a real room the difference is not the colour of the light, it is where the
# light is. At night the room stops being lit and the tank becomes the only
# light source in it. That inversion has to happen on the clock, not only when
# a player goes looking for the room_darkness slider — which defaults to 0, so
# by default it never happened at all.

const R = preload("res://scripts/lighting_rig.gd")


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_night_restage")

	# --- Night darkens the room on its own ---
	var day: float = R.effective_room_darkness(0.0, 0.0)
	var night: float = R.effective_room_darkness(0.0, 1.0)
	t.approx(day, 0.0, "midday leaves the room alone", 0.001)
	t.check(night > 0.5,
		"deep night must crush the room with room_darkness at its default 0 "
			+ "(got %.2f) — otherwise the cycle is a tint" % night)
	t.approx(night, R.NIGHT_ROOM_DARKNESS, "and reaches the night constant", 0.001)

	# --- The player's setting is a floor, never a ceiling ---
	t.approx(R.effective_room_darkness(0.9, 0.0), 0.9,
		"a player who wants a dark room gets one at noon", 0.001)
	t.approx(R.effective_room_darkness(0.9, 1.0), 0.9,
		"…and midnight does not push them past what they asked for", 0.001)
	t.check(R.effective_room_darkness(0.3, 1.0) >= 0.3,
		"night never makes the room lighter than the player set it")

	# --- Monotonic and bounded ---
	var prev: float = -1.0
	for i in 11:
		var dn: float = float(i) / 10.0
		var v: float = R.effective_room_darkness(0.1, dn)
		t.in_range(v, 0.0, 1.0, "effective darkness stays in range at %.1f" % dn)
		t.check(v >= prev - 0.0001, "deepens monotonically toward night at %.1f" % dn)
		prev = v
	t.approx(R.effective_room_darkness(5.0, 5.0), 1.0, "inputs clamp high", 0.001)
	t.approx(R.effective_room_darkness(-5.0, -5.0), 0.0, "inputs clamp low", 0.001)

	# --- Night is not a blackout ---
	# room_darkness 1.0 is a deliberate choice; an unattended tank at 2am is not.
	t.check(R.NIGHT_ROOM_DARKNESS < 1.0,
		"the automatic night must leave the room readable — a full blackout "
			+ "is something the player opts into, not the default 2am")

	# --- …and the cone actually responds to it ---
	# The chain only works if darkness reaches the out-of-cone floor, which is
	# the thing that makes the tank the only lit object.
	var lit_amb: float = R.cone_tint(Color.WHITE, R.effective_room_darkness(0.0, 0.0), 1.0).w
	var night_amb: float = R.cone_tint(Color.WHITE, R.effective_room_darkness(0.0, 1.0), 1.0).w
	t.check(night_amb < lit_amb - 0.15,
		"the world outside the cone must be markedly darker at night "
			+ "(%.3f vs %.3f)" % [night_amb, lit_amb])

	quit(t.finish())
