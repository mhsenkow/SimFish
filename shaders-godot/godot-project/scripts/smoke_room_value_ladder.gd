extends SceneTree

# The room must stay behind the tank, in value (VISUAL_DIRECTIONS #2).
#
# VISUAL_POLISH #27 already asked for this — "never render the room brighter
# than the tank's mid-water value" — and was ticked done. A capture on
# 2026-09-13 then measured the room wall at p50 143 against mid-water at 147.
# The rule was satisfied, by four luminance levels out of 255, which is not a
# separation anyone can see. It was satisfied because it was written as an
# inequality and checked by eye.
#
# The reason it drifted is worth pinning too: world.gd authors the wall at
# roughly luma 87, and then the room's aerial-perspective haze — added later,
# for depth — mixed it 42% toward a target derived from the LIGHT FIXTURE at
# luma 229, landing it at ~147. Two visual systems, both reasonable, and the
# newer one silently won.
#
# So the contract here is a GAP, not an ordering, and it is enforced at the
# one place the uniform is written rather than trusted at each call site.

const RoomBuilder = preload("res://scripts/world_room_builder.gd")
const Metrics = preload("res://scripts/frame_metrics.gd")
const ConfigScript = preload("res://scripts/tank_config.gd")

# The measured mid-water value from the 2026-09-13 baseline capture, in 0..1.
# Used as the reference the room has to stay clear of.
const MIDWATER_REFERENCE: float = 147.0 / 255.0
# Widest plausible view distance for room geometry at the hero camera. The
# haze fog factor saturates well before this, so testing here is the worst
# case for brightness.
const FAR_VIEW_Z: float = 60.0


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_room_value_ladder")

	# --- The ceiling actually buys a visible separation ---
	var gap: float = (MIDWATER_REFERENCE - RoomBuilder.ROOM_HAZE_LUMA_CEILING) * 255.0
	t.check(gap >= Metrics.BACKGROUND_SEPARATION_MIN,
		"room haze ceiling must sit >= %.0f luma below mid-water (gap %.1f)"
			% [Metrics.BACKGROUND_SEPARATION_MIN, gap])

	# --- clamp_luma lowers value without eating hue ---
	var warm := Color(1.0, 0.85, 0.62)
	var capped: Color = RoomBuilder.clamp_luma(warm, 0.42)
	t.approx(RoomBuilder.luma_of(capped), 0.42, "clamp_luma hits the ceiling", 0.002)
	t.approx(capped.r / maxf(capped.g, 0.0001), warm.r / warm.g,
		"clamp_luma preserves the r:g ratio", 0.01)
	t.approx(capped.g / maxf(capped.b, 0.0001), warm.g / warm.b,
		"clamp_luma preserves the g:b ratio", 0.01)
	var already_dark := Color(0.1, 0.09, 0.08)
	t.approx(RoomBuilder.luma_of(RoomBuilder.clamp_luma(already_dark, 0.42)),
		RoomBuilder.luma_of(already_dark),
		"clamp_luma leaves an already-dark colour alone", 0.0001)
	t.check(RoomBuilder.luma_of(RoomBuilder.clamp_luma(Color.BLACK, 0.42)) <= 0.0001,
		"clamp_luma does not divide by zero on black")

	# --- Every shipped room preset stays under the ceiling ---
	var checked: int = 0
	for key: String in ConfigScript.ENVIRONMENT_PRESETS:
		var preset: Dictionary = ConfigScript.ENVIRONMENT_PRESETS[key]
		if not preset.has("light_color") or not preset.has("desk_color"):
			continue  # "void" has no room
		checked += 1
		var lamp: Color = _rgb(preset["light_color"])
		var desk: Color = _rgb(preset["desk_color"])
		var target: Color = RoomBuilder.haze_target(lamp, desk)
		var tl: float = RoomBuilder.luma_of(target)
		t.check(tl <= RoomBuilder.ROOM_HAZE_LUMA_CEILING + 0.001,
			"preset '%s' haze target %.3f exceeds ceiling %.3f"
				% [key, tl, RoomBuilder.ROOM_HAZE_LUMA_CEILING])
		# …and the surface it is applied to cannot be lifted through the
		# ceiling at any distance, which is the property that actually matters.
		var wall_luma: float = RoomBuilder.luma_of(_authored_wall(preset))
		var hazed: float = RoomBuilder.hazed_luma(wall_luma, tl, 0.65, FAR_VIEW_Z)
		t.check(hazed <= RoomBuilder.ROOM_HAZE_LUMA_CEILING + 0.001,
			"preset '%s' wall hazes to %.3f, over the ceiling" % [key, hazed])
		t.check((MIDWATER_REFERENCE - hazed) * 255.0 >= Metrics.BACKGROUND_SEPARATION_MIN,
			"preset '%s' wall ends %.1f luma below mid-water, want >= %.0f"
				% [key, (MIDWATER_REFERENCE - hazed) * 255.0,
					Metrics.BACKGROUND_SEPARATION_MIN])
	t.check(checked >= 2, "found %d room presets to check" % checked)

	# --- Haze may only ever DARKEN ---
	# The whole failure mode was a "depth" effect that raised value. Assert the
	# direction of the operator, not just its current tuning.
	var lamp_bright := Color(1.0, 0.98, 0.94)
	var desk_dark := Color(0.30, 0.22, 0.16)
	var tgt: Color = RoomBuilder.haze_target(lamp_bright, desk_dark)
	for surface_luma: float in [0.20, 0.35, 0.50, 0.70, 0.90]:
		var out: float = RoomBuilder.hazed_luma(surface_luma,
			RoomBuilder.luma_of(tgt), 0.65, FAR_VIEW_Z)
		t.check(out <= maxf(surface_luma, RoomBuilder.ROOM_HAZE_LUMA_CEILING) + 0.001,
			"haze raised a surface from %.2f to %.3f" % [surface_luma, out])

	# --- The pre-fix formula is pinned as a regression ---
	# This is what world.gd used to compute, and what put the wall at 147.
	var old_target := Color(
		lamp_bright.r * 0.92 + 0.08,
		lamp_bright.g * 0.86 + 0.06,
		lamp_bright.b * 0.78 + 0.04)
	t.check(RoomBuilder.luma_of(old_target) > RoomBuilder.ROOM_HAZE_LUMA_CEILING,
		"the pre-fix haze target should be over the ceiling — if this passes, "
			+ "the ceiling has been raised back to where the bug lived")

	# --- The shader mirror agrees with the shader ---
	# smoothstep(8, 28, z) * strength, then mix. Endpoints are the easy cases.
	t.approx(RoomBuilder.hazed_luma(0.8, 0.2, 0.65, 4.0), 0.8,
		"no haze in front of the near plane", 0.0001)
	t.approx(RoomBuilder.hazed_luma(0.8, 0.2, 0.65, 40.0), lerpf(0.8, 0.2, 0.65),
		"full fog factor past the far plane is just `strength`", 0.0001)
	t.approx(RoomBuilder.hazed_luma(0.8, 0.2, 0.65, 18.0), lerpf(0.8, 0.2, 0.325),
		"midpoint of the smoothstep is half strength", 0.001)
	t.approx(RoomBuilder.hazed_luma(0.8, 0.2, 0.0, 40.0), 0.8,
		"zero strength is a no-op", 0.0001)

	quit(t.finish())


func _rgb(arr: Variant) -> Color:
	var a: Array = arr as Array
	return Color8(int(a[0]), int(a[1]), int(a[2]))


# Reproduce world.gd's authored wall colour: the ladder darken/desaturate, then
# make_room's palette_value trim. Kept here rather than exported from world.gd
# because world.gd is a 10k-line Node3D and this is four multiplications.
func _authored_wall(preset: Dictionary) -> Color:
	var wall: Color = _rgb(preset["wall_color"])
	var out: Color = wall.darkened(0.44)
	var l: float = RoomBuilder.luma_of(out)
	out = out.lerp(Color(l, l, l), 0.42)
	# VoxelMat.make_room sets palette_value 0.82 on room materials.
	return Color(out.r * 0.82, out.g * 0.82, out.b * 0.82)
