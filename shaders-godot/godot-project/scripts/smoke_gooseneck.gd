extends SceneTree

# Clip-on gooseneck shape (Gooseneck) and the lamp-dominance rule.
#
# The lamp used to move as one rigid piece, so dragging it carried the rim
# clamp out over the open water with the cable trailing off into the room.
# A real gooseneck keeps the clamp bitten to the rim and bends its neck;
# these are the constraints that make that true.

const G := preload("res://scripts/gooseneck.gd")
const R := preload("res://scripts/lighting_rig.gd")

const HEX: Array = [
	Vector3(5.0, 0.0, 0.0), Vector3(2.5, 0.0, 5.0), Vector3(-2.5, 0.0, 5.0),
	Vector3(-5.0, 0.0, 0.0), Vector3(-2.5, 0.0, -5.0), Vector3(2.5, 0.0, -5.0)]
const BOX: Array = [
	Vector3(6.0, 0.0, 4.0), Vector3(-6.0, 0.0, 4.0),
	Vector3(-6.0, 0.0, -4.0), Vector3(6.0, 0.0, -4.0)]


func _init() -> void:
	var t := TestSupport.Suite.new("gooseneck")
	var rim := 11.05

	# --- the clamp stays on the rim ---------------------------------------
	# Wherever the head goes, the clamp must land ON the perimeter - never
	# floating over the water, which is the bug this replaces.
	for shape in [HEX, BOX]:
		for i in 16:
			var a: float = TAU * float(i) / 16.0
			var head := Vector3(cos(a) * 9.0, rim, sin(a) * 9.0)
			var cp: Vector3 = G.clamp_point(head, shape, rim)
			t.approx(cp.y, rim, "clamp sits at rim height")
			# On the perimeter means: on one of the edges, within epsilon.
			var on_edge: bool = false
			for k in shape.size():
				var p1: Vector3 = shape[k]
				var p2: Vector3 = shape[(k + 1) % shape.size()]
				var d: float = _dist_to_seg(
					Vector2(cp.x, cp.z), Vector2(p1.x, p1.z), Vector2(p2.x, p2.z))
				if d < 0.01:
					on_edge = true
					break
			t.check(on_edge,
				"clamp is on the rim, not floating (%.0f deg, %d corners)"
				% [rad_to_deg(a), shape.size()])
	# Degenerate input must not crash or return a wild point.
	t.approx(G.clamp_point(Vector3(1.0, rim, 2.0), [], rim).x, 1.0,
		"no footprint falls back to the head's own xz")

	# --- the cable hangs OUTSIDE the glass ---------------------------------
	var clamp_back: Vector3 = G.clamp_point(Vector3(0.0, rim, -9.0), HEX, rim)
	var out_n: Vector3 = G.outward_at(clamp_back, HEX)
	t.approx(out_n.length(), 1.0, "outward normal is a unit vector")
	t.check(out_n.z < 0.0, "at the back of the tank, outward points backward")
	t.approx(out_n.y, 0.0, "outward is horizontal - a cable does not fly")
	var cable: Array[Vector3] = G.cable_samples(clamp_back, out_n, 6.0)
	t.check(cable.size() >= 2, "cable has samples")
	t.approx(cable[0].distance_to(clamp_back), 0.0,
		"the cable starts AT the clamp - it stays connected", 0.01)
	t.check(cable[cable.size() - 1].y < clamp_back.y - 1.0,
		"and falls away down the outside")
	var prev_y: float = INF
	for p in cable:
		t.check(p.y <= prev_y + 1e-6, "the cable only ever descends")
		prev_y = p.y

	# --- the neck reaches, and bows ---------------------------------------
	var head2 := Vector3(1.0, rim + 0.6, 1.0)
	var clamp2: Vector3 = G.clamp_point(head2, HEX, rim)
	var arm: Array[Vector3] = G.arm_samples(clamp2, head2)
	t.check(arm.size() >= 3, "the neck has segments")
	t.approx(arm[0].distance_to(clamp2), 0.0,
		"the neck starts at the clamp", 0.01)
	t.approx(arm[arm.size() - 1].distance_to(head2), 0.0,
		"and ends at the head - no gap at either end", 0.01)
	var peak: float = -INF
	for p in arm:
		peak = maxf(peak, p.y)
	t.check(peak > maxf(clamp2.y, head2.y) + 0.05,
		"the neck bows UP over the water rather than running taut")
	# Even a head parked right next to its clamp must still arc.
	var near_arm: Array[Vector3] = G.arm_samples(clamp2, clamp2 + Vector3(0.05, 0.0, 0.0))
	var near_peak: float = -INF
	for p in near_arm:
		near_peak = maxf(near_peak, p.y)
	t.check(near_peak > clamp2.y + 0.05, "a short neck still bends")

	# --- reach ------------------------------------------------------------
	var reach: float = G.max_reach(5.0, 5.0)
	t.check(reach > 1.0, "a lamp can reach out over the water")
	var far := Vector3(40.0, rim, 40.0)
	var pulled: Vector3 = G.constrain_head(far, clamp2, reach)
	t.approx(pulled.distance_to(clamp2), reach,
		"a head dragged across the room is pulled back to arm's length", 0.01)
	var close := clamp2 + Vector3(0.3, 0.0, 0.0)
	t.approx(G.constrain_head(close, clamp2, reach).distance_to(clamp2), 0.3,
		"a head within reach is left exactly where it was", 0.001)

	# --- darkness counts as night -----------------------------------------
	# A blacked-out room lost its beam every morning: the shaft's daytime
	# energy reads global_energy, which room_darkness had just crushed.
	t.approx(R.lamp_dominance(0.0, 0.0), 0.0, "lit room, daytime: sun rules")
	t.approx(R.lamp_dominance(1.0, 0.0), 1.0, "lit room, deep night: lamp rules")
	t.approx(R.lamp_dominance(0.0, 0.97), 0.97,
		"dark room at dawn: the LAMP rules, not the sun")
	t.approx(R.lamp_dominance(0.6, 0.2), 0.6, "whichever is stronger wins")
	for d in [-1.0, 0.0, 0.5, 1.0, 9.0]:
		t.in_range(R.lamp_dominance(d, 0.5), 0.0, 1.0,
			"dominance stays a fraction at %.1f" % d)

	quit(t.finish())


func _dist_to_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var l2: float = ab.length_squared()
	if l2 < 1e-8:
		return p.distance_to(a)
	var tt: float = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * tt)
