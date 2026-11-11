extends SceneTree

# LOOM #196 — the eyes go where the mind is. Assert the new `mind` gaze kind
# sits below keeper but above a curiosity glance / idle, and that offering a
# mind target steers the gaze toward that point.

func _init() -> void:
	var t := TestSupport.Suite.new("smoke_motion_gaze_mind")

	t.check(int(MotionGaze.PRIORITY.get(&"mind", 0)) > int(MotionGaze.PRIORITY.get(&"curiosity", 0)),
			"mind outranks a curiosity glance")
	t.check(int(MotionGaze.PRIORITY.get(&"mind", 0)) < int(MotionGaze.PRIORITY.get(&"keeper", 0)),
			"mind yields to the keeper at the glass")
	t.check(int(MotionGaze.PRIORITY.get(&"food", 0)) > int(MotionGaze.PRIORITY.get(&"mind", 0)),
			"real food still beats the mind glance")

	var g := MotionGaze.new(7)
	# A mind target is accepted over idle.
	t.check(g.look_at_point(&"mind", Vector3(1.0, 0.0, -2.0), 0.8), "mind target accepted from idle")
	t.equals(g.kind, &"mind", "gaze kind is mind")
	t.check(g.has_target, "gaze has a target")

	# Keeper overrides mind while mind is still held.
	t.check(g.look_at_point(&"keeper", Vector3(-1.0, 0.0, -2.0), 1.0), "keeper overrides mind")
	t.equals(g.kind, &"keeper", "keeper now owns the gaze")

	# A fresh curiosity offer does NOT override the held keeper.
	t.check(not g.look_at_point(&"curiosity", Vector3(0.0, 1.0, -2.0), 0.5),
			"curiosity cannot steal the keeper gaze")

	# Stepping toward a mind target yaws the eyes off center.
	var g2 := MotionGaze.new(11)
	g2.look_at_point(&"mind", Vector3(2.0, 0.0, -2.0), 1.0)
	for _i in 30:
		g2.step(0.05, Transform3D.IDENTITY, 1.0)
	t.check(absf(g2.eye_yaw()) > 0.01, "eyes track toward the mind target (yaw=%.3f)" % g2.eye_yaw())

	quit(t.finish())
