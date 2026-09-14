extends SceneTree

# Following a creature must actually get close to it (VISUAL_DIRECTIONS #8).
#
# A fish is roughly 7x4 pixels at the shipped 512x288 internal render, and the
# whole shoal occupies under 1% of the tank area. Two hundred-odd fish_* and
# mind_* scripts drive something the player cannot see the face of.
#
# Clicking one did not help: CINEMATIC follow moved the orbit TARGET and never
# the radius, so it re-centred the same wide shot on a 0.6-unit animal from 20
# units away. The camera pointed at the subject and stayed exactly as far from
# it as it had been.

const CC = preload("res://scripts/camera_controller.gd")


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_subject_framing")

	# --- The framing maths is the framing maths ---
	# At distance d the visible height is 2*d*tan(fov/2); check the round trip.
	var fov: float = 45.0
	var subject: float = 0.6
	var r: float = CC.radius_for_subject(subject, fov, 40.0, 0.16)
	var visible: float = 2.0 * r * tan(deg_to_rad(fov) * 0.5)
	t.approx(subject / visible, 0.16,
		"the subject lands at the requested fraction of frame height", 0.005)

	# --- A follow must bring the camera IN, hard ---
	var wide: float = 20.0
	var followed: float = CC.radius_for_subject(0.6, 45.0, wide)
	t.check(followed < wide * 0.5,
		"following a 0.6-unit fish from 20 units must more than halve the "
			+ "radius, got %.2f" % followed)

	# --- …and may never push it OUT ---
	# A tiny subject asks for an impossibly close radius; a large one asks for
	# a far one. Neither may exceed the shot the player already had.
	for subj: float in [0.05, 0.3, 1.0, 3.0, 12.0]:
		var got: float = CC.radius_for_subject(subj, 45.0, 9.0)
		t.check(got <= 9.0 + 0.001,
			"subject %.2f must not push the camera past the player's 9.0 "
				% subj + "(got %.2f)" % got)
		t.check(got >= CC.FOLLOW_MIN_RADIUS - 0.001,
			"subject %.2f must not breach the near floor (got %.2f)" % [subj, got])

	# --- Bigger subject, bigger distance ---
	var prev: float = -1.0
	for i in 12:
		var subj: float = 0.2 + float(i) * 0.25
		var got: float = CC.radius_for_subject(subj, 45.0, 60.0)
		t.check(got >= prev - 0.0001,
			"a larger subject is framed from further back (at %.2f)" % subj)
		prev = got

	# --- Wider lens, closer camera, same framing ---
	var narrow: float = CC.radius_for_subject(0.6, 25.0, 60.0)
	var wide_lens: float = CC.radius_for_subject(0.6, 75.0, 60.0)
	t.check(wide_lens < narrow,
		"a wider field of view needs a closer camera for the same subject "
			+ "size (%.2f vs %.2f)" % [wide_lens, narrow])

	# --- Degenerate inputs do not produce a camera inside the fish ---
	t.check(CC.radius_for_subject(0.0, 45.0, 20.0) >= CC.FOLLOW_MIN_RADIUS,
		"a zero-height subject still yields a sane radius")
	t.check(CC.radius_for_subject(-5.0, 45.0, 20.0) >= CC.FOLLOW_MIN_RADIUS,
		"a negative height does not invert the camera")
	t.check(CC.radius_for_subject(0.6, 0.0, 20.0) > 0.0,
		"a zero fov clamps rather than dividing by zero")
	t.check(CC.radius_for_subject(0.6, 45.0, 0.0) >= CC.FOLLOW_MIN_RADIUS,
		"a zero current radius still respects the near floor")
	t.check(CC.radius_for_subject(0.6, 45.0, 20.0, 0.0) > 0.0,
		"a zero requested fraction clamps rather than exploding")
	t.check(CC.radius_for_subject(0.6, 45.0, 20.0, 5.0) >= CC.FOLLOW_MIN_RADIUS,
		"an over-unity fraction clamps")

	# --- The frame fraction is worth having ---
	# At the shipped 288-line internal render, the target must put a real
	# number of pixels on the creature.
	var px: float = CC.FOLLOW_SUBJECT_FRAC * 288.0
	t.check(px >= 32.0,
		"the follow framing must give a creature at least 32 internal pixels "
			+ "of height (got %.0f) — below that no expression survives" % px)

	# --- main.gd restores the shot afterwards ---
	var src: String = _read("res://scripts/main.gd")
	t.check(src.contains("_follow_saved_radius"),
		"main.gd remembers the pre-follow radius")
	t.check(src.contains("radius = _follow_saved_radius"),
		"…and puts the player back where they were when the follow ends")
	t.check(src.contains("CameraController.radius_for_subject"),
		"the cinematic follow tick actually uses the framing helper")

	quit(t.finish())


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s: String = f.get_as_text()
	f.close()
	return s
