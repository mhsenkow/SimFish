extends SceneTree

# Aimable spot rig + room darkness (LightingRig), and the preset contract
# that surrounds it.
#
# Two failure modes this exists for, both silent:
#
#  1. A shaft that does not follow its light. The god-ray mesh used to be a
#     vertical cylinder positioned under the spot regardless of which way
#     the spot pointed, so a raked beam lit one wall while its visible
#     shaft went somewhere else. aim_direction/beam_length are the maths
#     that keeps them together.
#  2. A preset that is a diff rather than a look. apply_lighting_preset
#     only ever SET the keys a preset declared, so selecting a dark spot
#     preset and then "Window daylight" left room_darkness at 0.92 and
#     rendered daylight as a black room.

const R := preload("res://scripts/lighting_rig.gd")
const Cfg := preload("res://scripts/tank_config.gd")


func _init() -> void:
	var t := TestSupport.Suite.new("lighting_rig")

	# --- inherit sentinel ------------------------------------------------
	# Adding these knobs must not restyle tanks that never opted in.
	t.approx(R.resolve_angle(R.INHERIT, 22.0), 22.0, "inherit keeps fixture angle")
	t.approx(R.resolve_attenuation(R.INHERIT, 1.8), 1.8, "inherit keeps fixture falloff")
	t.approx(R.resolve_angle(30.0, 22.0), 30.0, "an override wins")
	t.approx(R.resolve_angle(500.0, 22.0), R.ANGLE_MAX, "absurd angle clamps")
	t.approx(R.resolve_angle(0.5, 22.0), R.ANGLE_MIN, "sub-minimum angle clamps")
	t.approx(R.resolve_attenuation(99.0, 1.8), R.ATTEN_MAX, "falloff clamps")

	# --- head placement --------------------------------------------------
	# Offsets are fractions of the tank's own half-extent, so one preset
	# frames the same way on a nano cube and a six-footer.
	var small: Vector3 = R.head_position(4.0, 4.0, 6.0, 1.0, 0.55, -0.15)
	var big: Vector3 = R.head_position(12.0, 7.0, 9.0, 1.0, 0.55, -0.15)
	t.approx(small.x / 4.0, big.x / 12.0, "offset is proportional, not absolute")
	t.approx(small.y, 7.0, "head sits above the rim")
	t.check(absf(small.x) <= 4.0, "head stays over the tank in x")
	var clamped: Vector3 = R.head_position(4.0, 4.0, 6.0, 1.0, 9.0, -9.0)
	t.approx(clamped.x, 4.0, "runaway offset clamps to the glass")
	t.approx(clamped.z, -4.0, "runaway negative offset clamps too")

	# --- aim -------------------------------------------------------------
	# Godot spots shine down local -Z, so straight down is -90 on X.
	var down: Vector3 = R.aim_direction(0.0, 0.0)
	t.approx(down.y, -1.0, "zero tilt points straight down", 0.001)
	var raked: Vector3 = R.aim_direction(40.0, 0.0)
	t.check(raked.y < 0.0, "a raked beam still points downward")
	t.check(raked.y > down.y, "rake lifts the beam off vertical")
	t.approx(raked.length(), 1.0, "aim is a unit vector", 0.001)
	for tilt in [-90.0, -30.0, 0.0, 30.0, 74.0, 200.0]:
		for yaw in [-400.0, -90.0, 0.0, 137.0, 359.0]:
			var d: Vector3 = R.aim_direction(tilt, yaw)
			t.approx(d.length(), 1.0,
				"aim unit at tilt %.0f yaw %.0f" % [tilt, yaw], 0.001)
	t.approx(R.aim_rotation_deg(999.0, 0.0).x, -90.0 + R.TILT_MAX,
		"tilt cannot flip the light upside down")

	# --- beam length follows the aim -------------------------------------
	var vert: float = R.beam_length(10.0, 2.0, 0.0, 0.0, 100.0)
	t.approx(vert, 8.0, "vertical beam lands on the substrate")
	var tilted: float = R.beam_length(10.0, 2.0, 45.0, 0.0, 100.0)
	t.check(tilted > vert,
		"a raked beam travels further before it lands (%.2f vs %.2f)"
		% [tilted, vert])
	t.approx(tilted, 8.0 / cos(deg_to_rad(45.0)), "and by the right amount", 0.01)
	# A beam aimed at the horizon never lands; it must be capped, not infinite.
	var flat: float = R.beam_length(10.0, 2.0, R.TILT_MAX, 0.0, 40.0)
	t.check(is_finite(flat) and flat <= 40.0,
		"a near-horizontal beam is capped, not infinite (%.2f)" % flat)
	t.approx(R.beam_length(2.0, 2.0, 0.0, 0.0, 100.0), 0.0,
		"no beam when the lamp is at substrate level")

	# --- cone footprint ---------------------------------------------------
	var narrow: float = R.beam_end_radius(8.0, 20.0)
	var wide: float = R.beam_end_radius(8.0, 60.0)
	t.check(wide > narrow, "a wider cone lands a wider pool")
	t.check(narrow > 0.0, "a cone always has some footprint")

	# --- darkness ---------------------------------------------------------
	t.approx(R.darkened(0.5, 0.0), 0.5, "darkness 0 leaves the room alone")
	t.check(R.darkened(0.5, 0.92) < 0.05, "darkness 0.92 crushes the room")
	t.approx(R.darkened(0.5, 1.0), R.DARK_GLOBAL_FLOOR,
		"full darkness bottoms out at the floor, not below")
	var prev: float = 999.0
	for i in 21:
		var d: float = float(i) / 20.0
		var v: float = R.darkened(0.6, d)
		t.check(v <= prev + 1e-6, "darkness is monotonic at %.2f" % d)
		t.check(v >= 0.0, "darkness never goes negative at %.2f" % d)
		prev = v
	t.check(R.darkened_ambient(0.9, 0.32, 0.0) <= 0.32,
		"ambient still respects the room cap")
	t.check(R.darkened_ambient(0.9, 0.32, 0.95) < 0.05,
		"a dark room has almost no ambient")
	t.check(R.darkened_ambient(0.9, 0.32, 1.0) > 0.0,
		"but never pure black, or silhouettes disappear")

	# --- AIM AT A POINT ---------------------------------------------------
	# THE BUG THIS CATCHES, and it shipped: tilt/yaw were ADDED to whatever
	# rake a fixture already had baked in. The gooseneck carries (-78, -18),
	# tuned for its original fixed position. Move the head to a back corner
	# and add a tilt, and the beam points out through the back wall - it
	# landed at (6.08, -6.72) on a tank whose glass ends at 5.0, lighting
	# the room instead of the water. A rotation offset cannot know where the
	# lamp ended up; an aim target is self-correcting.
	t.check(not R.has_aim(R.AIM_OFF, R.AIM_OFF), "unset aim falls back to tilt/yaw")
	t.check(R.has_aim(0.0, 0.0), "a centre aim counts as set")
	t.check(R.has_aim(-0.22, 0.30), "an off-centre aim counts as set")

	var hw := 5.0
	var hd := 5.0
	var sub := 2.2
	var tgt: Vector3 = R.aim_target(hw, hd, sub, -0.22, 0.30)
	t.approx(tgt.x, -1.1, "aim x is a fraction of half-width")
	t.approx(tgt.z, 1.5, "aim z is a fraction of half-depth")
	t.approx(tgt.y, sub, "the cone lands on the substrate")
	var far: Vector3 = R.aim_target(hw, hd, sub, 9.0, -9.0)
	t.check(absf(far.x) <= hw and absf(far.z) <= hd,
		"a runaway aim still targets inside the glass")

	# The load-bearing property: from ANY head position over the tank, the
	# beam must land where it was aimed - inside the glass.
	for hx in [-0.9, -0.4, 0.0, 0.45, 0.9]:
		for hz in [-0.9, 0.0, 0.9]:
			var head := Vector3(hx * hw, 11.0, hz * hd)
			var target: Vector3 = R.aim_target(hw, hd, sub, -0.22, 0.30)
			var rot: Vector3 = R.look_rotation_deg(head, target)
			var b := Basis.from_euler(Vector3(
				deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
			var dir: Vector3 = (-b.z).normalized()
			t.check(dir.y < 0.0,
				"beam points downward from head (%.1f, %.1f)" % [hx, hz])
			var travel: float = (head.y - sub) / -dir.y
			var land := Vector2(head.x + dir.x * travel, head.z + dir.z * travel)
			t.approx(land.x, target.x,
				"lands on target x from head (%.1f, %.1f)" % [hx, hz], 0.02)
			t.approx(land.y, target.z,
				"lands on target z from head (%.1f, %.1f)" % [hx, hz], 0.02)
			t.check(absf(land.x) <= hw and absf(land.y) <= hd,
				"lands INSIDE the glass from head (%.1f, %.1f)" % [hx, hz])

	# The exact shipped failure, reproduced as a regression case: head at the
	# back-right corner must not light the back wall.
	var bad_head := Vector3(3.08, 10.97, -3.15)
	var good_rot: Vector3 = R.look_rotation_deg(
		bad_head, R.aim_target(hw, hd, sub, -0.22, 0.30))
	var gb := Basis.from_euler(Vector3(deg_to_rad(good_rot.x),
		deg_to_rad(good_rot.y), deg_to_rad(good_rot.z)))
	var gd: Vector3 = (-gb.z).normalized()
	t.check(gd.x < 0.0, "from the RIGHT corner the beam travels LEFT")
	t.check(gd.z > 0.0, "from the BACK corner the beam travels FORWARD")
	# Straight down must stay a valid, non-degenerate rotation.
	var down_rot: Vector3 = R.look_rotation_deg(
		Vector3(0.0, 10.0, 0.0), Vector3(0.0, 2.0, 0.0))
	t.approx(down_rot.x, -90.0, "a vertical aim is straight down")
	t.check(R.look_rotation_deg(Vector3.ZERO, Vector3.ZERO).x == -90.0,
		"a degenerate aim does not produce a non-finite basis")

	# --- beam_span works off a direction vector ---------------------------
	t.approx(R.beam_span(10.0, 2.0, Vector3.DOWN, 100.0), 8.0,
		"vertical span reaches the substrate")
	var raked_dir: Vector3 = Vector3(0.707, -0.707, 0.0).normalized()
	t.approx(R.beam_span(10.0, 2.0, raked_dir, 100.0), 8.0 / 0.707,
		"a raked span is longer", 0.01)
	t.check(R.beam_span(10.0, 2.0, Vector3(1.0, 0.0, 0.0), 40.0) <= 40.0,
		"a horizontal span is capped")

	# --- the beam must come FROM the lamp --------------------------------
	# _add_god_ray_beam computed the lamp height as
	#   TANK_HEIGHT + height_above + spot.position.y
	# which assumes every fixture root sits at TANK_HEIGHT + height_above.
	# True for the pendant and the bar, FALSE for the gooseneck: its clamp
	# sits on the rim at TANK_HEIGHT + 0.05, so with the default light_height
	# of 1.4 the shaft was built from a phantom lamp 1.35 units above the
	# one you can see. The shaft has to read the real fixture.
	var w2: String = _read("res://scripts/world.gd")
	t.check(w2.contains("var spot_y: float = parent.position.y + spot.position.y"),
		"the shaft height comes from the real fixture, not a nominal one")
	t.check(not w2.contains("TANK_HEIGHT + height_above + spot.position.y"),
		"the phantom-lamp height is gone")

	# --- the shaft must START at the lamp --------------------------------
	# god_ray.gdshader reads its gradient off UV.y, 0 = the cylinder's TOP =
	# the lamp end, where the shaft is brightest and sealed. Mapping local
	# +Y onto the beam direction put that end on the substrate, so a raked
	# beam rendered its bright sealed end on the gravel and faded UPWARD -
	# it looked like a shaft rising out of the bottom of the tank.
	for a in [Vector3(-0.388, -0.814, 0.432), Vector3(0.5, -0.6, -0.62),
			Vector3(0.0, -1.0, 0.0), Vector3(-0.1, -0.99, 0.02)]:
		var aim_n: Vector3 = a.normalized()
		var bb: Basis = R.beam_basis(aim_n)
		t.check(bb.is_finite(), "beam basis is finite for %s" % str(a))
		# local -Y runs along the beam; local +Y points back at the lamp.
		var down_axis: Vector3 = (bb * Vector3.DOWN).normalized()
		t.approx(down_axis.dot(aim_n), 1.0,
			"local -Y runs along the beam for %s" % str(a), 0.002)
		var up_axis: Vector3 = (bb * Vector3.UP).normalized()
		t.check(up_axis.dot(aim_n) < -0.99,
			"local +Y (UV.y=0, the bright end) points back at the lamp")

	# End to end: the bright end of the shaft must sit AT the lamp head and
	# the faded end on the substrate - never the other way round.
	var lamp := Vector3(3.08, 10.97, -3.15)
	var beam_aim: Vector3 = Vector3(-0.388, -0.814, 0.432).normalized()
	var span: float = R.beam_span(lamp.y, 2.2, beam_aim, 40.0)
	var mesh_basis: Basis = R.beam_basis(beam_aim)
	var centre: Vector3 = lamp + beam_aim * (span * 0.5)
	var bright_end: Vector3 = centre + (mesh_basis * Vector3.UP).normalized() * (span * 0.5)
	var faded_end: Vector3 = centre + (mesh_basis * Vector3.DOWN).normalized() * (span * 0.5)
	t.approx(bright_end.distance_to(lamp), 0.0,
		"the shaft's bright end is at the lamp head", 0.02)
	t.check(bright_end.y > faded_end.y,
		"the shaft runs downward from the lamp (%.2f -> %.2f)"
		% [bright_end.y, faded_end.y])
	t.approx(faded_end.y, 2.2, "the faded end lands on the substrate", 0.05)
	# A vertical beam must stay upright rather than being flipped by the
	# degenerate branch.
	var vb: Basis = R.beam_basis(Vector3.DOWN)
	t.approx((vb * Vector3.UP).normalized().y, 1.0,
		"a straight-down beam keeps +Y up")

	# --- the shaft must not draw outside the glass ------------------------
	# The shaft is a cone that widens from the lamp toward the substrate,
	# and nothing constrained it to the tank: a probe of a real hex build
	# found the CylinderMesh reaching 1.18 units past the back wall, which
	# renders as a bright straight line cutting across the corner. These
	# planes are what the shader clips against.
	var hex: Array = [
		Vector3(5.0, 0.0, 0.0), Vector3(2.5, 0.0, 5.0), Vector3(-2.5, 0.0, 5.0),
		Vector3(-5.0, 0.0, 0.0), Vector3(-2.5, 0.0, -5.0), Vector3(2.5, 0.0, -5.0)]
	t.equals(R.footprint_planes(hex).size(), 6, "a hex yields six planes")
	t.equals(R.footprint_plane_vec4s(hex).size(), 8,
		"the packed array always fills the shader's 8 slots")
	# Inside / outside, including the exact case the probe caught: the
	# corner of the bounding box is NOT inside a hex.
	t.check(R.inside_footprint(0.0, 0.0, hex), "the centre is inside")
	t.check(R.inside_footprint(4.9, 0.0, hex), "near the side vertex is inside")
	t.check(not R.inside_footprint(4.9, 4.9, hex),
		"the AABB corner is OUTSIDE a hex - this is the whole bug")
	t.check(not R.inside_footprint(0.0, -6.18, hex),
		"the shaft's far reach at z=-6.18 is outside")
	t.check(R.inside_footprint(-1.10, 1.50, hex),
		"the Night Lamp aim point is inside")
	# Every vertex of the polygon is on the boundary, never outside it.
	for c in hex:
		t.check(R.inside_footprint(c.x, c.z, hex, 0.001),
			"corner (%.1f, %.1f) is on the boundary" % [c.x, c.z])
	# A square footprint must behave too.
	var box: Array = [
		Vector3(5.0, 0.0, 3.0), Vector3(-5.0, 0.0, 3.0),
		Vector3(-5.0, 0.0, -3.0), Vector3(5.0, 0.0, -3.0)]
	t.equals(R.footprint_planes(box).size(), 4, "a box yields four planes")
	t.check(R.inside_footprint(4.9, 2.9, box), "box corner region is inside")
	t.check(not R.inside_footprint(5.6, 0.0, box), "past the box wall is outside")
	# Winding must not matter: a reversed polygon has to clip identically,
	# or half the tank shapes would clip themselves away entirely.
	var rev: Array = []
	for i in range(hex.size() - 1, -1, -1):
		rev.append(hex[i])
	t.check(R.inside_footprint(0.0, 0.0, rev), "reversed winding still encloses")
	t.check(not R.inside_footprint(4.9, 4.9, rev),
		"reversed winding still excludes the AABB corner")
	# Degenerate input disables clipping rather than clipping everything.
	t.check(R.footprint_planes([]).is_empty(), "no corners, no planes")
	t.check(R.inside_footprint(99.0, 99.0, []),
		"with no footprint nothing is clipped away")
	var too_many: Array = []
	for i in 12:
		var a: float = TAU * float(i) / 12.0
		too_many.append(Vector3(cos(a) * 5.0, 0.0, sin(a) * 5.0))
	t.check(R.footprint_planes(too_many).is_empty(),
		"more corners than the shader can hold disables clipping, "
		+ "rather than clipping against a partial polygon")

	# --- analytic cone for the unshaded pipeline -------------------------
	# Every voxel/foliage shader is `render_mode unshaded`, so nothing in the
	# tank responds to a light and turning on spot shadows changes nothing.
	# The cone is evaluated in-shader from globals instead.
	var cone: Vector4 = R.cone_params(30.0, 20.0, 1.15)
	t.check(cone.x < cone.y,
		"cos_outer is the wider edge (%.4f < %.4f)" % [cone.x, cone.y])
	t.approx(cone.x, cos(deg_to_rad(15.0)), "outer edge is the half-angle")
	t.approx(cone.w, 1.15, "energy passes through")
	var wide_cone: Vector4 = R.cone_params(60.0, 20.0, 1.0)
	t.check(wide_cone.x < cone.x, "a wider cone has a smaller outer cosine")
	t.approx(R.cone_params(30.0, 20.0, -5.0).w, 0.0,
		"negative energy cannot invert the cone")
	t.check(R.cone_params(30.0, -99.0, 1.0).z > 0.0,
		"reach is always positive")

	var tint_dark: Vector4 = R.cone_tint(Color(1.0, 0.84, 0.42), 0.97)
	var tint_lit: Vector4 = R.cone_tint(Color(1.0, 0.84, 0.42), 0.0)
	# WAS: t.approx(tint_lit.w, 1.0, "no darkness leaves the unlit half alone").
	# That assertion pinned a no-op. An out-of-cone floor of exactly 1.0 means
	# the cone multiplies every fragment by one, so the project's only light
	# model did nothing at default settings — VISUAL_DIRECTIONS #1. The
	# contract is now that a lit room is still SHAPED, and that
	# light_shaping 0 is the opt-out that restores the old flat behaviour.
	t.approx(tint_lit.w, R.CONE_SHAPING_FLOOR,
		"a lit room is still shaped by the cone")
	t.approx(R.cone_tint(Color.WHITE, 0.0, 0.0).w, 1.0,
		"light_shaping 0 restores the unshaped behaviour")
	t.check(tint_dark.w < tint_lit.w,
		"darkness drops what is outside the cone (%.3f < %.3f)"
		% [tint_dark.w, tint_lit.w])
	t.check(tint_dark.w > 0.0,
		"but never to nothing - the unlit half must read as shape, not a hole")
	t.approx(tint_dark.x, 1.0, "lamp colour rides in rgb")
	for d in [0.0, 0.25, 0.5, 0.75, 1.0]:
		t.in_range(R.cone_tint(Color.WHITE, d).w, R.CONE_AMBIENT_FLOOR, 1.0,
			"ambient stays in range at darkness %.2f" % d)

	# Wiring: the globals must actually be registered and pushed, and the
	# foliage shaders must consume them - a correct helper that nothing
	# calls is exactly the failure mode that shipped last round.
	t.check(w2.contains("_sync_beam_cone_globals("),
		"world.gd pushes the cone into the shader globals")
	t.check(w2.contains("iaq_beam_origin"),
		"world.gd sets the beam origin global")
	var proj: String = _read("res://project.godot")
	for g in ["iaq_beam_origin", "iaq_beam_dir", "iaq_beam_cone", "iaq_beam_tint"]:
		t.check(proj.contains(g), "%s is registered in project.godot" % g)
	var inc: String = _read("res://shaders/beam_cone.gdshaderinc")
	t.check(inc.contains("global uniform vec4 iaq_beam_cone"),
		"the include declares the cone global")
	for sh in ["res://shaders/foliage.gdshader", "res://shaders/foliage_mm.gdshader"]:
		var src: String = _read(sh)
		t.check(src.contains("beam_cone.gdshaderinc"),
			"%s includes the cone" % sh.get_file())
		# Either form counts: iaq_beam_light_n is the directional variant that
		# took over these call sites when the cone gained a normal.
		t.check(src.contains("iaq_beam_light(") or src.contains("iaq_beam_light_n("),
			"%s actually applies the cone to its albedo" % sh.get_file())

	# --- room lights obey darkness ---------------------------------------
	# THE BUG THIS CATCHES. room_darkness originally only touched the sun and
	# the ambient term. The room carries five lights of its own, all driven
	# off the daylight curve, and none of them obeyed it - so a "dark room"
	# rendered a brightly lit wall that was the brightest thing in frame,
	# the exact opposite of what the setting is for.
	t.approx(R.room_fill(0.5, 0.0), 0.5, "darkness 0 leaves room fill alone")
	t.approx(R.room_fill(0.5, 1.0), 0.0, "full darkness kills room fill")
	t.check(R.room_fill(0.44, 0.97) < 0.02,
		"a 0.97-dark room has essentially no ambient fill")
	# Tank spill is the opposite: a lit tank in a black room still glows onto
	# the desk. Killing it makes the tank look pasted into a void.
	t.approx(R.tank_spill(0.5, 0.0), 0.5, "darkness 0 leaves spill alone")
	t.check(R.tank_spill(0.5, 1.0) > 0.0,
		"a lit tank still spills onto a fully dark room")
	t.approx(R.tank_spill(0.5, 1.0), 0.5 * R.SPILL_KEEP,
		"and keeps the documented fraction")
	t.check(R.tank_spill(0.5, 0.97) > R.room_fill(0.5, 0.97),
		"tank spill always outlives ambient fill")
	for i in 11:
		var dk: float = float(i) / 10.0
		t.check(R.room_fill(0.6, dk) >= 0.0, "room fill never negative at %.1f" % dk)
		t.check(R.tank_spill(0.6, dk) <= 0.6 + 1e-6,
			"spill never brightens the room at %.1f" % dk)
		t.check(R.room_fill(0.6, dk) <= R.tank_spill(0.6, dk) + 1e-6,
			"fill is crushed at least as hard as spill at %.1f" % dk)

	# --- shaft opacity lifts as the room darkens --------------------------
	t.check(R.beam_alpha(0.3, 1.0, 0.9) > R.beam_alpha(0.3, 1.0, 0.0),
		"a shaft reads more strongly against a dark room")
	t.approx(R.beam_alpha(0.3, 0.0, 0.9), 0.0, "strength 0 hides the shaft")
	for a in [0.0, 0.4, 1.0]:
		for st in [0.0, 1.0, 4.0]:
			t.in_range(R.beam_alpha(a, st, 1.0), 0.0, 1.0,
				"alpha stays a valid alpha (%.1f,%.1f)" % [a, st])

	# --- presets are complete looks, not diffs ----------------------------
	var probe := Cfg.new()
	for slug in Cfg.LIGHTING_PRESETS.keys():
		var preset: Dictionary = Cfg.LIGHTING_PRESETS[slug]
		for key in preset.keys():
			if key == "label":
				continue
			t.check(String(key) in probe,
				"lighting preset %s key '%s' is a real property" % [slug, key])
	# The reset table is what stops a preset leaking into the next one.
	for key in Cfg.LIGHTING_RIG_DEFAULTS.keys():
		t.check(String(key) in probe,
			"rig reset key '%s' is a real property" % key)
	# Applying a spot preset then a plain one must leave no residue.
	probe.apply_lighting_preset("clip_spot_night")
	t.check(float(probe.room_darkness) > 0.5, "spot preset darkens the room")
	t.check(bool(probe.spot_shadows), "spot preset turns shadows on")
	probe.apply_lighting_preset("sunny")
	t.approx(float(probe.room_darkness), 0.0,
		"switching to daylight clears the darkness")
	t.check(not bool(probe.spot_shadows),
		"switching to daylight clears the shaped cone")
	t.approx(float(probe.spot_angle_deg), -1.0,
		"and returns the cone to the fixture default")

	# --- the two spot presets are genuinely different shapes --------------
	var clip: Dictionary = Cfg.LIGHTING_PRESETS["clip_spot_night"]
	var pend: Dictionary = Cfg.LIGHTING_PRESETS["pendant_pool"]
	# The clip lamp rakes because it is AIMED across the tank from an
	# off-centre head, not because of a tilt offset - that is the whole
	# point of the aim model. So assert the rake it actually produces.
	t.check(R.has_aim(float(clip["spot_aim_x"]), float(clip["spot_aim_z"])),
		"the clip lamp aims at a point")
	t.check(absf(float(clip["spot_offset_x"])) > 0.2,
		"the clip lamp sits off to one side")
	var clip_head := Vector3(
		float(clip["spot_offset_x"]) * hw, 11.0,
		float(clip["spot_offset_z"]) * hd)
	var clip_dir: Vector3 = R.aim_direction_to(clip_head,
		R.aim_target(hw, hd, sub, float(clip["spot_aim_x"]),
			float(clip["spot_aim_z"])))
	t.check(absf(clip_dir.y) < 0.97,
		"the clip lamp rakes rather than dropping straight (y=%.3f)"
		% clip_dir.y)
	t.check(not R.has_aim(float(pend.get("spot_aim_x", R.AIM_OFF)),
			float(pend.get("spot_aim_z", R.AIM_OFF)))
		or absf(float(pend["spot_aim_x"])) < 0.01,
		"the pendant drops straight down the middle")
	t.approx(float(pend["spot_tilt_deg"]), 0.0, "the pendant has no rake")
	for slug in ["clip_spot_night", "pendant_pool"]:
		var pr: Dictionary = Cfg.LIGHTING_PRESETS[slug]
		t.check(float(pr["room_darkness"]) > 0.5, "%s darkens the room" % slug)
		t.check(bool(pr["spot_shadows"]),
			"%s casts shadows (no shadows, no contrast)" % slug)
		t.check(bool(pr["light_volumetric"]), "%s shows its beam" % slug)
		t.in_range(float(pr["spot_angle_deg"]), R.ANGLE_MIN, R.ANGLE_MAX,
			"%s cone angle in range" % slug)

	# --- WIRING (source inspection) --------------------------------------
	# The helpers above being correct proved nothing about the bug that
	# actually shipped: room_darkness existed, was tested, and simply was
	# not APPLIED to five of the room's lights. A pure test cannot see that,
	# so assert the call sites directly.
	var rb: String = _read("res://scripts/world_room_builder.gd")
	t.check(not rb.is_empty(), "world_room_builder.gd readable")
	# Every light_energy assignment in the room tick must route through a
	# darkness helper, or that light stays lit in a dark room.
	for line in rb.split("\n"):
		var ls: String = line.strip_edges()
		if not ls.contains(".light_energy ="):
			continue
		t.check(ls.contains("LightingRig.room_fill")
				or ls.contains("LightingRig.tank_spill")
				or ls.contains("LightingRig."),
			"room light obeys darkness: %s" % ls.left(72))
	t.check(rb.contains("darkness: float = 0.0"),
		"tick_room_lights takes a darkness argument")

	var w: String = _read("res://scripts/world.gd")
	t.check(not w.is_empty(), "world.gd readable")
	t.check(w.contains("room_dark"),
		"world.gd passes room_darkness into the room light tick")
	# The sun and the ambient term must be darkened too.
	t.check(w.contains("LightingRig.darkened(global_energy"),
		"world.gd darkens the sun")
	t.check(w.contains("LightingRig.darkened_ambient("),
		"world.gd darkens the ambient term")
	# And the shaft must follow the light rather than hanging straight down.
	t.check(w.contains("LightingRig.beam_span("),
		"the god-ray shaft derives its length from the aim direction")
	t.check(w.contains("LightingRig.spot_forward(spot)"),
		"the shaft reads the light's real basis, not reconstructed euler")
	t.check(w.contains("LightingRig.look_rotation_deg("),
		"fixtures aim at a target rather than composing euler offsets")
	t.check(w.contains("LightingRig.has_aim("),
		"an unset aim still falls back to the fixture's own rake")

	probe.free()
	quit(t.finish())


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt: String = f.get_as_text()
	f.close()
	return txt
