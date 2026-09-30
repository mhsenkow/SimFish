extends RefCounted
class_name LightingRig

# Aimable spot rig + room darkness.
#
# WHAT THIS UNLOCKS. A single clip-on lamp over one corner of an otherwise
# black room: a hard-edged cone raking down and across the tank, a visible
# shaft in the water, everything outside the cone falling to nothing. The
# machinery for that already existed in world.gd - SpotLight3D with a cone
# angle, and _add_god_ray_beam for the shaft - but every number was a
# literal in the fixture builder, so no preset could reach it, the spot
# always hung at a fixed spot pointing a fixed way, and its shaft was
# always a vertical cylinder no matter which way the light aimed.
#
# So: the numbers move out here, presets drive them, and the beam follows
# the light. Everything below is pure so it can be asserted headlessly.
#
# ROOM DARKNESS is deliberately a separate axis from global_intensity.
# Intensity dims the sun; darkness crushes the *room* - sun, ambient and
# background - while leaving the tank fixture untouched, which is what
# makes the tank the only lit object in the frame instead of a slightly
# brighter part of a dim scene.

# Sentinel meaning "leave the fixture's own value alone". Presets set a real
# number to override; everything else keeps the per-fixture defaults so
# adding these knobs cannot silently restyle existing tanks.
const INHERIT: float = -1.0

# Hard bounds. spot_angle above ~80 stops being a cone; attenuation below
# 0.1 is a flat wash with no edge.
const ANGLE_MIN: float = 4.0
const ANGLE_MAX: float = 80.0
const ATTEN_MIN: float = 0.1
const ATTEN_MAX: float = 8.0
const TILT_MAX: float = 75.0

# How far room darkness can crush each channel at 1.0. Ambient keeps a
# sliver so silhouettes stay readable rather than becoming pure black holes.
const DARK_GLOBAL_FLOOR: float = 0.02
const DARK_AMBIENT_FLOOR: float = 0.012


static func resolve_angle(override_deg: float, fixture_default: float) -> float:
	if override_deg <= INHERIT + 0.001:
		return fixture_default
	return clampf(override_deg, ANGLE_MIN, ANGLE_MAX)


static func resolve_attenuation(override_v: float, fixture_default: float) -> float:
	if override_v <= INHERIT + 0.001:
		return fixture_default
	return clampf(override_v, ATTEN_MIN, ATTEN_MAX)


# Where the lamp head sits. Offsets are -1..1 fractions of the tank's own
# half-extent, so a preset reads the same on a nano cube and a 6-footer.
static func head_position(half_w: float, half_d: float, tank_height: float,
		height_above: float, offset_x: float, offset_z: float) -> Vector3:
	return Vector3(
		clampf(offset_x, -1.0, 1.0) * half_w,
		tank_height + height_above,
		clampf(offset_z, -1.0, 1.0) * half_d)


# Spot rotation. Godot's SpotLight3D shines down its local -Z, so straight
# down is a -90 degree X rotation; tilt walks it back toward the horizon and
# yaw swings it around.
static func aim_rotation_deg(tilt_deg: float, yaw_deg: float) -> Vector3:
	var tilt: float = clampf(tilt_deg, -TILT_MAX, TILT_MAX)
	return Vector3(-90.0 + tilt, wrapf(yaw_deg, -180.0, 180.0), 0.0)


# Sentinel for "no aim target set" - fall back to tilt/yaw.
const AIM_OFF: float = -999.0


static func has_aim(aim_x: float, aim_z: float) -> bool:
	return aim_x > AIM_OFF + 1.0 and aim_z > AIM_OFF + 1.0


# Where the cone centre should land, from fractions of the tank's own
# half-extent. (0,0) is the middle of the substrate.
static func aim_target(half_w: float, half_d: float, substrate_y: float,
		aim_x: float, aim_z: float) -> Vector3:
	return Vector3(
		clampf(aim_x, -1.0, 1.0) * half_w,
		substrate_y,
		clampf(aim_z, -1.0, 1.0) * half_d)


# Rotation that points a SpotLight3D's cone at `target`.
#
# WHY THIS REPLACED EULER COMPOSITION. tilt/yaw were ADDED to whatever rake
# a fixture already had baked in - the gooseneck carried (-78, -18) tuned
# for its original hard-coded position. Move the lamp to a corner and those
# same angles now point it out through the back wall, because a rotation
# offset cannot know where the lamp ended up. Aiming at a point is
# self-correcting: it works for any head position, tank size or shape.
static func look_rotation_deg(head: Vector3, target: Vector3) -> Vector3:
	var dir: Vector3 = target - head
	if dir.length_squared() < 1e-6:
		return Vector3(-90.0, 0.0, 0.0)
	dir = dir.normalized()
	# A perfectly vertical direction is degenerate for looking_at's up
	# vector; straight down is exactly what -90 on X already means.
	if absf(dir.dot(Vector3.UP)) > 0.9995:
		return Vector3(-90.0 if dir.y < 0.0 else 90.0, 0.0, 0.0)
	# Basis.looking_at aligns -Z with dir, which is where a spot shines.
	var b := Basis.looking_at(dir, Vector3.UP)
	var e: Vector3 = b.get_euler()
	return Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z))


# Unit direction from a head to an aim target.
static func aim_direction_to(head: Vector3, target: Vector3) -> Vector3:
	var d: Vector3 = target - head
	if d.length_squared() < 1e-8:
		return Vector3.DOWN
	return d.normalized()


# Unit direction the cone points, for the shaft mesh to follow.
static func aim_direction(tilt_deg: float, yaw_deg: float) -> Vector3:
	var rot: Vector3 = aim_rotation_deg(tilt_deg, yaw_deg)
	var b := Basis.from_euler(Vector3(
		deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
	return (-b.z).normalized()


# The direction a spot actually shines: its own -Z axis. Reading the basis
# is exact for any rotation, including look-at rotations with a non-zero
# roll that a tilt/yaw reconstruction would drop.
static func spot_forward(spot: Node3D) -> Vector3:
	if spot == null:
		return Vector3.DOWN
	var f: Vector3 = -spot.transform.basis.z
	if f.length_squared() < 1e-8:
		return Vector3.DOWN
	return f.normalized()


# Tank footprint as inward half-planes for the shaft shader: a point p is
# inside when dot(plane.xy, p.xz) <= plane.z. Up to 8, matching the shader's
# array size; more corners than that fall back to no clipping rather than
# silently clipping against a partial polygon.
static func footprint_planes(corners: Array) -> Array[Plane]:
	var out: Array[Plane] = []
	var n: int = corners.size()
	if n < 3 or n > 8:
		return out
	# Centroid, so each edge normal can be pointed outward consistently.
	var cx: float = 0.0
	var cz: float = 0.0
	for c in corners:
		cx += c.x
		cz += c.z
	cx /= float(n)
	cz /= float(n)
	for i in n:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % n]
		var e := Vector2(b.x - a.x, b.z - a.z)
		if e.length_squared() < 1e-8:
			continue
		var nrm := Vector2(e.y, -e.x).normalized()
		if nrm.dot(Vector2(a.x - cx, a.z - cz)) < 0.0:
			nrm = -nrm
		out.append(Plane(nrm.x, 0.0, nrm.y, nrm.dot(Vector2(a.x, a.z))))
	return out


# Packed for the shader uniform: (nx, nz, d, 0).
static func footprint_plane_vec4s(corners: Array) -> Array[Vector4]:
	var out: Array[Vector4] = []
	for p in footprint_planes(corners):
		out.append(Vector4(p.normal.x, p.normal.z, p.d, 0.0))
	while out.size() < 8:
		out.append(Vector4.ZERO)
	return out


# Is this xz point inside the footprint? Shares the plane maths with the
# shader so the CPU and GPU cannot disagree about where the glass is.
static func inside_footprint(x: float, z: float, corners: Array,
		slack: float = 0.0) -> bool:
	var planes: Array[Plane] = footprint_planes(corners)
	if planes.is_empty():
		return true
	for p in planes:
		if Vector2(p.normal.x, p.normal.z).dot(Vector2(x, z)) - p.d > slack:
			return false
	return true


# Orientation for the visible shaft mesh.
#
# CylinderMesh runs along local +Y, and god_ray.gdshader reads its gradient
# off UV.y with 0 at the cylinder's TOP - the lamp end, where the shaft is
# brightest and sealed. So local -Y must point ALONG the beam and local +Y
# back at the lamp. Mapping +Y onto the beam instead puts the bright sealed
# end on the gravel and fades it upward, which renders as a shaft starting
# at the bottom of the tank and shining up.
static func beam_basis(aim: Vector3) -> Basis:
	if aim.length_squared() < 1e-8:
		return Basis()
	var a: Vector3 = aim.normalized()
	# Near-vertical: leave the cylinder upright. +Y is already world-up,
	# i.e. already pointing back at the lamp.
	if absf(a.dot(Vector3.UP)) >= 0.999:
		return Basis()
	return Basis.looking_at(-a, Vector3.UP) \
		* Basis(Vector3.RIGHT, deg_to_rad(-90.0))


# Beam length along an explicit direction (the vector form of beam_length).
static func beam_span(head_y: float, substrate_y: float, dir: Vector3,
		max_len: float) -> float:
	var drop: float = head_y - substrate_y
	if drop <= 0.05:
		return 0.0
	if dir.y > -0.08:
		return max_len
	return minf(drop / -dir.y, max_len)


# Distance from the lamp head to the substrate along the aim direction. A
# tilted beam travels further before it lands than a vertical one, and a
# beam aimed at or above the horizon never lands at all.
static func beam_length(head_y: float, substrate_y: float,
		tilt_deg: float, yaw_deg: float, max_len: float) -> float:
	var drop: float = head_y - substrate_y
	if drop <= 0.05:
		return 0.0
	var dir: Vector3 = aim_direction(tilt_deg, yaw_deg)
	if dir.y > -0.08:
		return max_len
	return minf(drop / -dir.y, max_len)


# Radius of the cone where it lands. spot_angle is the full cone width, so
# the half-angle is what opens the triangle.
static func beam_end_radius(length: float, angle_deg: float) -> float:
	return maxf(0.02, length * tan(deg_to_rad(
		clampf(angle_deg, ANGLE_MIN, ANGLE_MAX) * 0.5)))


# Room light after darkness. Never negative, and never quite zero so a
# fully dark room still resolves shapes rather than clipping to a void.
static func darkened(energy: float, darkness: float) -> float:
	var d: float = clampf(darkness, 0.0, 1.0)
	return maxf(energy * (1.0 - d), DARK_GLOBAL_FLOOR)


static func darkened_ambient(energy: float, cap: float, darkness: float) -> float:
	var d: float = clampf(darkness, 0.0, 1.0)
	return maxf(minf(energy, cap) * (1.0 - d), DARK_AMBIENT_FLOOR)


# --- Room lights --------------------------------------------------------
#
# The room carries five lights of its own (side fill, wall bounce, tank
# spill, desk rim, window glow) built in world_room_builder.gd and driven
# off the daylight curve. room_darkness originally missed all of them,
# which is why a "dark room" still rendered a brightly lit wall that was
# the brightest thing in frame - the exact opposite of the intent.
#
# They split into two kinds and must be treated differently:
#
#   room fill  - ambient light that exists whether or not the tank is on.
#                A dark room has none of this, so darkness crushes it.
#   tank spill - light thrown BY the tank onto its surroundings. A lit tank
#                in a black room still glows onto the desk and wall; killing
#                this makes the tank look pasted on rather than present in
#                the room, so darkness only trims it.
const SPILL_KEEP: float = 0.45


static func room_fill(energy: float, darkness: float) -> float:
	return maxf(0.0, energy) * (1.0 - clampf(darkness, 0.0, 1.0))


static func tank_spill(energy: float, darkness: float) -> float:
	var d: float = clampf(darkness, 0.0, 1.0)
	return maxf(0.0, energy) * (1.0 - d * (1.0 - SPILL_KEEP))


# Visible shaft opacity. Darkness helps the beam read - a shaft is only
# visible against a dark surround - so it lifts with the room going down.
static func beam_alpha(base_alpha: float, strength: float,
		darkness: float) -> float:
	var lift: float = 1.0 + clampf(darkness, 0.0, 1.0) * 0.85
	return clampf(base_alpha * maxf(0.0, strength) * lift, 0.0, 1.0)


# --- Analytic cone for the unshaded voxel pipeline ----------------------
#
# Every voxel/foliage shader is `render_mode unshaded`, so nothing in the
# tank responds to a light on its own - a plant renders the same whether
# the lamp points at it or at the far wall, and turning shadows on in the
# spot changes nothing. The cone is therefore evaluated in-shader from
# these globals (see shaders/beam_cone.gdshaderinc).

# How dark the world goes OUTSIDE the cone at full darkness. Not 0 - the
# unlit half must still read as shape rather than a hole in the frame.
const CONE_AMBIENT_FLOOR: float = 0.30
# Softness of the cone rim as a fraction of its half-angle.
const CONE_INNER_FRAC: float = 0.55

# How dark the world goes outside the cone in a NORMALLY LIT room, i.e. at
# room_darkness 0 (VISUAL_DIRECTIONS #1).
#
# This used to be 1.0, which meant the cone multiplied everything by exactly
# one and the analytic light model - the only light model the unshaded
# pipeline has - did nothing at all unless the player went and turned room
# darkness up. Sixteen lights in world.gd, 343 lines of rig, and at default
# settings a plant under the lamp rendered identically to a plant in the far
# corner. A 2026-09-13 capture measured the whole tank inside a 23-level
# luminance band for exactly this reason.
#
# 0.74 is a lit room with a lamp in it: a clear pool under the fixture,
# corners that fall away, nothing crushed. room_darkness still walks it the
# rest of the way down to CONE_AMBIENT_FLOOR.
const CONE_SHAPING_FLOOR: float = 0.74


# Collapse a fixture's spot positions into the segment the shader should treat
# as the light source: {origin, axis, is_line}.
#
# A bar fixture is built as four SpotLights spaced along the housing and only
# the first was ever published to the shader globals, so the commonest fixture
# in the game lit the tank from one end. Taking the extremes of the set gives
# the housing back its length; a single-spot fixture returns a zero axis and
# the shader's segment maths collapses to a point.
static func beam_segment(positions: Array) -> Dictionary:
	var out: Dictionary = {
		"origin": Vector3.ZERO, "axis": Vector3.ZERO, "is_line": false,
	}
	if positions.is_empty():
		return out
	var lo: Vector3 = positions[0]
	var hi: Vector3 = positions[0]
	for p in positions:
		var v: Vector3 = p
		lo = Vector3(minf(lo.x, v.x), minf(lo.y, v.y), minf(lo.z, v.z))
		hi = Vector3(maxf(hi.x, v.x), maxf(hi.y, v.y), maxf(hi.z, v.z))
	out["origin"] = (lo + hi) * 0.5
	var axis: Vector3 = (hi - lo) * 0.5
	# Below a few centimetres the "bar" is a point and the extra branch in the
	# shader buys nothing.
	out["is_line"] = axis.length() > 0.15
	out["axis"] = axis if out["is_line"] else Vector3.ZERO
	return out


# (cos_outer, cos_inner, range, energy) for the shader global.
static func cone_params(angle_deg: float, reach: float,
		energy: float) -> Vector4:
	var half: float = clampf(angle_deg, ANGLE_MIN, ANGLE_MAX) * 0.5
	var cos_outer: float = cos(deg_to_rad(half))
	var cos_inner: float = cos(deg_to_rad(half * CONE_INNER_FRAC))
	return Vector4(cos_outer, cos_inner, maxf(0.1, reach),
		maxf(0.0, energy))


# (r, g, b, ambient_outside). Darkness drives how far the unlit half falls,
# so the same lamp reads as a gentle pool in a lit room and as the only
# light source in a dark one.
static func cone_tint(color: Color, darkness: float,
		shaping: float = 1.0) -> Vector4:
	var d: float = clampf(darkness, 0.0, 1.0)
	# `shaping` (TankConfig.light_shaping) scales how much the cone is allowed
	# to shape a lit room. 0 restores the pre-VISUAL_DIRECTIONS behaviour where
	# the lamp only mattered once the room was blacked out.
	var lit_floor: float = lerpf(1.0, CONE_SHAPING_FLOOR, clampf(shaping, 0.0, 1.0))
	var ambient: float = lerpf(lit_floor, CONE_AMBIENT_FLOOR, d)
	return Vector4(color.r, color.g, color.b, ambient)


# How much the tank's own lamp owns the scene, 0..1.
#
# WHY THIS IS NOT JUST deep_night. The fixture and its visible shaft blend
# between a "daytime" term driven by the SUN and a "night" term driven by
# the lamp, using deep_night as the mix. That is right in a normal room and
# wrong the moment room_darkness is turned up: the daytime term reads
# global_energy, which darkness has just crushed to nothing, so a blacked
# out room lost its beam every morning and the lamp appeared to switch off.
#
# A 0.97-dark room IS night as far as the tank is concerned, whatever the
# clock says. Taking the max means darkness alone can hand the scene to the
# lamp without touching the day cycle the rest of the sim runs on.
static func lamp_dominance(deep_night: float, darkness: float) -> float:
	return clampf(maxf(clampf(deep_night, 0.0, 1.0),
		clampf(darkness, 0.0, 1.0)), 0.0, 1.0)


# How far NIGHT alone is allowed to crush the room, before the player's own
# room_darkness setting is considered (VISUAL_DIRECTIONS #15).
#
# The day/night machinery is genuinely good — a second night palette LUT, a
# smooth blend driven by daylight(), highlight burnthrough so emissives stay
# bright against the moonlit field. It is all TINT. The composition at midnight
# is identical to the composition at noon: the same surfaces, lit the same way,
# in different colours.
#
# In a real room the difference is not the colour of the light, it is WHERE the
# light is. At night the room stops being lit and the tank becomes the only
# light source in it, and everything not in the tank falls away. That inversion
# needs the room to darken on the clock, not only when a player finds a slider.
#
# Not 1.0: a pitch-black room is a deliberate choice (room_darkness is still
# there for it), not what an unattended tank looks like at 2am with a street
# lamp outside.
const NIGHT_ROOM_DARKNESS: float = 0.72


# The darkness the room should actually be rendered at: the player's setting,
# or what the clock implies, whichever is deeper. Taking the max rather than
# adding means a player who has set 0.9 does not get pushed to 1.0 at midnight,
# and a player who has set 0 still gets a night.
static func effective_room_darkness(player_darkness: float,
		deep_night: float) -> float:
	return clampf(maxf(clampf(player_darkness, 0.0, 1.0),
		clampf(deep_night, 0.0, 1.0) * NIGHT_ROOM_DARKNESS), 0.0, 1.0)


# --- The lit tank in a dim room (2026-09-29 alive pass) -----------------
#
# THE BUG. global_intensity is the SUN/ROOM axis, but the only place it turned
# into brightness was the post pass's palette_tint, which multiplies the whole
# frame. The post pass cannot tell the room from the tank, so a preset that
# asks for a dim room around a lit tank (backlit_jungle: global 0.32) dimmed
# the tank with it - a measured x0.69 on every pixel. The raw 3D frame of the
# Vallisneria jungle sat at a photo-like median of 145; the shipped frame at
# 103, with nothing brighter than 140 anywhere.
#
# So the dimming is split. The post tint keeps the part the lit tank is not
# spared from, and the rest moves into the cone's AMBIENT term through the
# iaq_room_light global (beam_cone.gdshaderinc): outside the cone - the room,
# the tank's shadows - lands exactly as dark as before, inside it the tank
# renders at its lamp's brightness. A pool of light in a dim room.

# The legacy post-tint curve, anchored at 0.5 -> 1.0 so saved tanks keep their
# look: dims toward 0.15 below the anchor, lifts to 1.25 above it.
static func global_brightness(global_intensity: float) -> float:
	var e: float = clampf(global_intensity, 0.0, 1.0)
	if e <= 0.5:
		return 0.15 + (e / 0.5) * 0.85
	return 1.0 + ((e - 0.5) / 0.5) * 0.25


# How much of the room's dimness a lit tank is spared, 0..1. A fixture at a
# quarter of its range already owns the tank's brightness; one that is off
# spares nothing, and the whole frame dims with the room as it always did.
static func lamp_hold(tank_lit: bool, fixture_energy: float) -> float:
	if not tank_lit:
		return 0.0
	return smoothstep(0.0, 0.25, maxf(fixture_energy, 0.0))


# Brightness the post tint applies to the whole frame. Never brighter than the
# sun already made it - the hold only takes dimming away, it adds no light.
static func frame_brightness(global_b: float, hold: float) -> float:
	if global_b >= 1.0:
		return global_b
	return lerpf(global_b, 1.0, clampf(hold, 0.0, 1.0))


# What the room geometry must still multiply by so that, after the post tint,
# it lands where the legacy single tint put it.
static func room_light(global_b: float, frame_b: float) -> float:
	return clampf(global_b / maxf(frame_b, 0.001), 0.0, 1.0)


# --- Light tint (TankConfig.light_tint_rgb) ----------------------------
#
# The LED's own spectrum, separate from tank_fixture_color because every
# lighting preset rewrites the fixture colour while a tank's lamp does not
# change when the player picks "Golden hour". Normalised so the brightest
# channel keeps its value: a pink full-spectrum LED is a pink light of the
# same strength, not a dimmer white one. White is the identity.
static func config_light_tint(cfg: Object) -> Color:
	if cfg == null:
		return Color.WHITE
	var v: Variant = cfg.get("light_tint_rgb")
	return v if v is Color else Color.WHITE


static func tint_light(color: Color, tint: Color) -> Color:
	var m: float = maxf(maxf(tint.r, tint.g), maxf(tint.b, 0.001))
	return Color(color.r * tint.r / m, color.g * tint.g / m,
		color.b * tint.b / m, color.a)


# --- Rear backlight as shader globals ----------------------------------
#
# The OmniLight's light_energy is backlight_intensity * 1.15 (world.gd); the
# shaders want 0..1-ish so a jungle preset's rear lamp lifts a lit leaf edge
# without blowing the palette. Clamped: a slider pushed past its range must
# not turn the back of the tank into a white sheet.
static func backlight_energy(light_energy: float) -> float:
	return clampf(light_energy / 1.15, 0.0, 1.5)


# att = 1 / (1 + k d^2) with 0.5 at half range and 0.2 at full range.
static func backlight_falloff(omni_range: float) -> float:
	return 4.0 / maxf(omni_range * omni_range, 0.01)


# --- Lit in-scatter (iaq_scatter_light) --------------------------------
#
# The water column's haze was a fixed teal (iaq_water_body), so distance
# greyed everything toward teal whatever the lamp was. Real haze is the lamp's
# light scattered back at the eye: pink under a pink LED, cream under warm
# white. rgb = the lamp colour normalised to its brightest channel, a = how far
# the haze takes that colour (0 = legacy teal). Scaled by energy so a dimmed
# lamp scatters less of itself, and by shaping so 0 restores the old look.
static func scatter_light(color: Color, energy: float, shaping: float = 1.0) -> Vector4:
	var m: float = maxf(maxf(color.r, color.g), maxf(color.b, 0.001))
	var amount: float = 0.7 * smoothstep(0.0, 0.3, maxf(energy, 0.0)) \
		* clampf(shaping, 0.0, 1.0)
	return Vector4(color.r / m, color.g / m, color.b / m, amount)
