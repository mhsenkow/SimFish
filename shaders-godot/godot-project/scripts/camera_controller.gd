class_name CameraController
extends RefCounted

# ENGINEERING_EXCELLENCE #2 / OPUS_HANDOFF 0B — orbit/pan/dolly/zoom/deadzone
# camera math extracted from main.gd as pure static functions (the TopdownMotion
# pattern). main.gd keeps the camera STATE (target/radius/yaw/pitch), the
# Camera3D node ref, and the node-dependent steps (MusicContext hero-bias,
# pixel-snap, projection switches); it delegates the pure math here. Behavior is
# identical — values and formulas moved verbatim from main.gd. See
# docs/ARCHITECTURE.md §main.gd carve.
#
# Canonical camera tuning constants live here now; main.gd re-exports them
# (const X := CameraController.X) so its other references — persistence clamps,
# camera-state restore — stay pointed at a single source of truth with no value
# drift.

const SENSITIVITY: float = 0.006            # radians per pixel, orbit drag
const DOLLY_MOUSE_SENSITIVITY: float = 0.012  # log-ish dolly per pixel
const PAN_MOUSE_SENSITIVITY: float = 0.012  # world units per pixel at radius=1
# One mouse-wheel notch, as a radius multiplier. Kept as the reference step
# that WHEEL_NOTCH_LOG below is derived from.
const ZOOM_FACTOR: float = 1.12
# Pinch sensitivity: how much of a macOS magnify gesture becomes zoom.
const MAGNIFY_ZOOM_GAIN: float = 1.55
const MIN_RADIUS: float = 4.0
const MACRO_MIN_RADIUS: float = 2.2  # REAL_TANK_FIDELITY #193
const MAX_RADIUS: float = 55.0
const MIN_PITCH: float = -1.45
const MAX_PITCH: float = 1.45
const DRAG_DEADZONE_PX: float = 8.0
const ORTHO_MIN_SIZE: float = 2.0
const ORTHO_MAX_SIZE: float = 80.0

# Target clamp box — the single convergence box (see eye/clamp_target).
# Sized for the largest template tanks (TankSizing: 30 wide, 13.5 tall) with
# room to pan past the glass; the old +-20 / y 12 box could not reach the
# waterline of a tall tank.
const TARGET_MIN := Vector3(-24.0, -2.0, -24.0)
const TARGET_MAX := Vector3(24.0, 16.0, 24.0)
# Item 38 — allow slightly-too-close corner shots instead of hard-clipping.
const TARGET_MIN_CLOSE := Vector3(-26.0, -2.5, -26.0)


# Deadzone gate: orbit/pan/dolly navigation only commits once the cursor has
# travelled DRAG_DEADZONE_PX since mousedown. A release before that is a tap
# (feed / pick), not a drag — this is the rule the smoke pins.
static func drag_committed(drag_total_px: float) -> bool:
	return drag_total_px >= DRAG_DEADZONE_PX


# Inverse of drag_committed: a release under the deadzone is a tap, not an orbit.
static func is_tap(drag_total_px: float) -> bool:
	return drag_total_px < DRAG_DEADZONE_PX


# Orbit: yaw/pitch follow mouse delta; pitch clamped, yaw free.
# Returns Vector2(yaw, pitch). `sens` overrides SENSITIVITY (HOLISTIC #035).
static func orbit(yaw: float, pitch: float, delta: Vector2,
		sens: float = SENSITIVITY) -> Vector2:
	var s: float = sens if sens > 0.0 else SENSITIVITY
	var ny: float = yaw - delta.x * s
	var np: float = clampf(pitch - delta.y * s, MIN_PITCH, MAX_PITCH)
	return Vector2(ny, np)


# Dolly: radius scales with vertical drag, clamped to the orbit shell.
static func dolly(radius: float, delta_y: float,
		sens: float = DOLLY_MOUSE_SENSITIVITY) -> float:
	var s: float = sens if sens > 0.0 else DOLLY_MOUSE_SENSITIVITY
	return clampf(radius * (1.0 + delta_y * s), MIN_RADIUS, MAX_RADIUS)


# Wheel/pinch zoom — perspective (radius) variant.
static func zoom_radius(radius: float, factor: float) -> float:
	return clampf(radius * factor, MIN_RADIUS, MAX_RADIUS)


# Wheel/pinch zoom — orthographic (camera.size) variant.
static func zoom_ortho(size: float, factor: float) -> float:
	return clampf(size * factor, ORTHO_MIN_SIZE, ORTHO_MAX_SIZE)


# ---- Zoom request accumulation ----------------------------------------------
#
# The old per-event classifier picked between three different step formulas
# depending on the reported factor and how many events had arrived in the last
# 80 ms. A single macOS trackpad flick crosses all three: the first events took
# a 12% bite each (pow(ZOOM_FACTOR, 1.0)), then the burst branch dropped to
# 4.7%, then precise deltas fell to 0.85%. A 14x swing in step size inside one
# gesture is exactly what "jumpy trackpad zoom" feels like, and 4.7% per event
# at the ~90 events/s a trackpad streams is ~60x per second — it hits the clamp
# before you have finished the gesture.
#
# Instead every input converts to a signed amount of *log zoom* and is added to
# a budget that the camera drains at a bounded rate per second. A mouse wheel
# (a few large notches) and a trackpad (a flood of small ones) now produce the
# same total travel for the same physical gesture, and the response is
# continuous — there is no branch to cross mid-flick.

# Log-zoom contributed by one full mouse-wheel notch. ln(1.12) ~= 0.113.
const WHEEL_NOTCH_LOG: float = 0.113
# Ceiling on the queued budget, so spinning the wheel hard cannot bank a zoom
# that keeps running long after you stop. ln(6) ~= 1.79 — about 6x travel.
const ZOOM_BUDGET_MAX: float = 1.79
# How fast the budget drains. Higher = snappier, lower = more glide.
const ZOOM_RESPONSE: float = 12.0
# Hard cap on log-zoom applied per second, so a dense event stream cannot
# outrun the frame rate. e^2.2 ~= 9x per second at full tilt.
const ZOOM_RATE_MAX: float = 2.2


# Log-zoom for one scroll event. `scroll_factor` is InputEventMouseButton.factor:
# macOS precise trackpads report fractional values, a notched wheel reports ~1.
# Positive result = zoom out; the caller negates for wheel-up.
static func scroll_log_zoom(scroll_factor: float) -> float:
	var mag: float = absf(scroll_factor)
	if mag < 0.0001:
		mag = 1.0
	# One continuous curve. Sub-linear so a hard wheel spin (factor > 1) does
	# not scale away, and so precise deltas stay proportional.
	return WHEEL_NOTCH_LOG * sqrt(clampf(mag, 0.02, 4.0))


# Log-zoom for a macOS pinch. InputEventMagnifyGesture.factor is 1 = unchanged.
static func magnify_log_zoom(magnify: float) -> float:
	var m: float = clampf(magnify, 0.5, 2.0)
	return -log(m) * MAGNIFY_ZOOM_GAIN


# Drain `budget` for one frame. Returns [applied_log_zoom, remaining_budget].
static func drain_zoom_budget(budget: float, dt: float) -> Array:
	if absf(budget) < 0.0001:
		return [0.0, 0.0]
	var k: float = clampf(dt * ZOOM_RESPONSE, 0.0, 1.0)
	var applied: float = budget * k
	# Rate cap keeps a flood of events from turning into a teleport.
	var cap: float = ZOOM_RATE_MAX * maxf(dt, 0.0001)
	applied = clampf(applied, -cap, cap)
	return [applied, budget - applied]


static func clamp_zoom_budget(budget: float) -> float:
	return clampf(budget, -ZOOM_BUDGET_MAX, ZOOM_BUDGET_MAX)


# Pan: slide target perpendicular to the view using the camera basis right/up.
# Drag right pushes the scene right (target moves left), matching Figma/PS.
# `sens` overrides PAN_MOUSE_SENSITIVITY (HOLISTIC #035); live `radius` still
# scales world travel so screen-space feel stays constant while zooming.
static func pan_target(target: Vector3, delta: Vector2, cam_right: Vector3,
		cam_up: Vector3, radius: float, sens: float = PAN_MOUSE_SENSITIVITY) -> Vector3:
	var s: float = sens if sens > 0.0 else PAN_MOUSE_SENSITIVITY
	var pan_sc: float = s * radius
	var t: Vector3 = target
	t -= cam_right * (delta.x * pan_sc)
	t += cam_up * (delta.y * pan_sc)
	return t


# Auto-orbit: gentle yaw drift per second (speed is a runtime var in main).
static func auto_orbit_yaw(yaw: float, speed: float, dt: float) -> float:
	return yaw + speed * dt


# Target clamp: the single convergence box so no pan/WASD/follow delta can push
# the target through the camera (breaking look_at) or to ±∞.
static func clamp_target(target: Vector3) -> Vector3:
	return Vector3(
		clampf(target.x, TARGET_MIN.x, TARGET_MAX.x),
		clampf(target.y, TARGET_MIN.y, TARGET_MAX.y),
		clampf(target.z, TARGET_MIN.z, TARGET_MAX.z))


# REAL_TANK_FIDELITY #187–188 — slow handheld drift + slight horizon roll.
static func handheld_offset(t: float, amp: float = 1.0) -> Dictionary:
	var pos := Vector3(
		sin(t * 0.31) * 0.035 + sin(t * 0.17) * 0.018,
		sin(t * 0.23 + 1.1) * 0.022,
		cos(t * 0.27) * 0.028) * amp
	var roll_rad: float = sin(t * 0.19) * deg_to_rad(1.4) * amp
	return {"pos": pos, "roll": roll_rad}


static func min_radius_for_mode(macro: bool) -> float:
	return MACRO_MIN_RADIUS if macro else MIN_RADIUS


# Eye position from spherical orbit coords. +pitch puts the eye above the
# target (y = sin(pitch)); yaw rotates around Y.
# ---- Subject framing (VISUAL_DIRECTIONS #8) ---------------------------------
#
# THE PROBLEM. A fish is roughly 7x4 pixels at the shipped 512x288 internal
# render — under 1% of the tank area for the whole shoal. Two hundred-odd
# fish_* and mind_* scripts drive a creature the player cannot see the face of.
#
# Following one did not help, because CINEMATIC follow only ever moved the
# orbit TARGET. Clicking a fish re-centred the same wide shot on it. The camera
# was pointed at the subject and still 20 units away from a 0.6-unit animal.
#
# So: how close must the camera be for a subject of a given world height to
# occupy `want_frac` of the viewport?
#
#   visible world height at distance d = 2 * d * tan(fov/2)
#   subject_h / visible_h = want_frac   =>   d = subject_h / (2*want_frac*tan(fov/2))
#
# 0.16 of frame height is ~46px at the 288-line internal render — enough for a
# body, a tail beat and a fin, which is the whole point.
const FOLLOW_SUBJECT_FRAC: float = 0.16
# Never smaller than this, whatever the subject: pushing the near plane into a
# fry is a nausea machine, and the glass is in the way anyway.
const FOLLOW_MIN_RADIUS: float = 2.6


# Orbit radius that frames a subject of `subject_h` world units at `want_frac`
# of the viewport height.
#
# Clamped to [FOLLOW_MIN_RADIUS, current_radius]: following may only ever move
# the camera IN. A tiny subject must not fling the camera out past where the
# player had it, and a large one should simply not change the shot.
static func radius_for_subject(subject_h: float, fov_deg: float,
		current_radius: float, want_frac: float = FOLLOW_SUBJECT_FRAC) -> float:
	var frac: float = clampf(want_frac, 0.02, 0.9)
	var half_fov: float = deg_to_rad(clampf(fov_deg, 5.0, 170.0)) * 0.5
	var tan_half: float = maxf(tan(half_fov), 0.001)
	var want: float = maxf(subject_h, 0.02) / (2.0 * frac * tan_half)
	return clampf(want, FOLLOW_MIN_RADIUS, maxf(current_radius, FOLLOW_MIN_RADIUS))


static func eye_position(target: Vector3, yaw: float, pitch: float,
		radius: float) -> Vector3:
	var x: float = cos(pitch) * sin(yaw)
	var y: float = sin(pitch)
	var z: float = cos(pitch) * cos(yaw)
	return target + Vector3(x, y, z) * radius


# Scenario-authored hero pose for the opening / fit view (HOLISTIC #021).
# Keeps TankConfig camera_* as the orbit intent while callers still size
# radius with TankSizing.fit_radius for the live viewport.
static func scenario_hero_orbit(cfg: Object, default_yaw: float,
		default_pitch: float, default_target_y: float) -> Dictionary:
	var yaw_v: float = default_yaw
	var pitch_v: float = default_pitch
	var target := Vector3(0.0, default_target_y, 0.0)
	if cfg == null:
		return {"yaw": yaw_v, "pitch": pitch_v, "target": target}
	if cfg.get("camera_yaw") != null:
		yaw_v = float(cfg.get("camera_yaw"))
	if cfg.get("camera_pitch") != null:
		pitch_v = float(cfg.get("camera_pitch"))
	var tx: float = float(cfg.get("camera_target_x")) if cfg.get("camera_target_x") != null else 0.0
	var tz: float = float(cfg.get("camera_target_z")) if cfg.get("camera_target_z") != null else 0.0
	var ty: float = default_target_y
	if cfg.get("camera_target_y") != null:
		var authored_y: float = float(cfg.get("camera_target_y"))
		# Shared TankConfig default is 2.8; scenarios author above/below that.
		if authored_y > 2.85 or authored_y < 2.75:
			ty = authored_y
	target = Vector3(tx, ty, tz)
	return {"yaw": yaw_v, "pitch": pitch_v, "target": target}


# ---- Hero fit with stand bound (HOLISTIC #023) ------------------------------
#
# A real cabinet is ~30" tall whatever tank sits on it. Framing the full stand
# with a nano makes furniture dominate the picture; ignoring it crops the
# contact shadow that grounds the tank. Cap how much stand may enter the hero
# frame so substrate, waterline and fixture stay primary.

# ~TankSpec.units_for_inches(30) — kept numeric so headless smokes need no TankSpec.
const STAND_WORLD_REF: float = 13.9
# Hard world-unit ceiling on stand visible in the hero shot.
const STAND_FRAME_MAX: float = 1.6
# Never let stand claim more than this fraction of tank height in-frame.
const STAND_FRAME_OF_TANK: float = 0.20


static func stand_allowed_in_frame(tank_h: float,
		stand_h: float = STAND_WORLD_REF) -> float:
	return minf(minf(maxf(0.0, stand_h), STAND_FRAME_MAX),
		maxf(0.0, tank_h) * STAND_FRAME_OF_TANK)


# Orbit radius that frames tank + capped stand at `fill` of the viewport.
# Same geometry as TankSizing.fit_radius, with vertical extent grown by the
# allowed stand below the substrate. User-authored camera views bypass this
# by applying their own radius.
static func hero_fit_radius(half_w: float, half_d: float, tank_h: float,
		fov_deg: float, aspect: float, yaw: float, pitch: float,
		fill: float = 0.68, stand_h: float = STAND_WORLD_REF) -> float:
	var stand_vis: float = stand_allowed_in_frame(tank_h, stand_h)
	var cy: float = absf(cos(yaw))
	var sy: float = absf(sin(yaw))
	var ext_x: float = half_w * cy + half_d * sy
	# Optical centre sits in the water column; include capped stand below.
	var total_h: float = tank_h + stand_vis
	var ext_y: float = total_h * 0.55 * absf(cos(pitch)) + half_d * absf(sin(pitch))
	var tan_v: float = tan(deg_to_rad(clampf(fov_deg, 20.0, 110.0)) * 0.5)
	var tan_h: float = tan_v * maxf(0.3, aspect)
	var r_x: float = ext_x / maxf(0.05, tan_h * fill)
	var r_y: float = ext_y / maxf(0.05, tan_v * fill)
	return maxf(r_x, r_y) + half_d * 0.3


# ---- Usable-centre framing offset (HOLISTIC #022) ---------------------------
#
# Side panels overlay the full-bleed 3D view. Bias the orbit target so the
# tank's projection sits in HudLayout.AVAILABLE_CENTER rather than under the
# panel. `bias` is HudLayout.available_center_bias (−1..1).

static func available_center_target(base_target: Vector3, bias: Vector2,
		cam_right: Vector3, cam_up: Vector3, radius: float, fov_deg: float,
		aspect: float) -> Vector3:
	if bias.length_squared() < 0.0001:
		return base_target
	var half_v: float = tan(deg_to_rad(clampf(fov_deg, 5.0, 170.0)) * 0.5) * maxf(radius, 0.1)
	var half_h: float = half_v * maxf(0.3, aspect)
	# Restrained: move the subject most of the way toward the free centre,
	# not the full bias (keeps the transition gentle).
	var gain: float = 0.72
	return base_target + cam_right * (bias.x * half_h * gain) \
			- cam_up * (bias.y * half_v * gain * 0.55)


# When the free centre is narrower than the viewport, ease the orbit out so
# the tank still clears the remaining band. Returns a radius multiplier ≥ 1.
static func available_center_radius_scale(avail_aspect: float,
		full_aspect: float) -> float:
	var full_a: float = maxf(0.3, full_aspect)
	var avail_a: float = maxf(0.3, avail_aspect)
	if avail_a >= full_a * 0.97:
		return 1.0
	# Cap the pull-back so opening a panel never teleports the camera.
	return clampf(full_a / avail_a, 1.0, 1.28)


# ---- Threshold chatter (HOLISTIC #027) --------------------------------------
#
# Pixel-snap, orbit coast, and follow deadzones fight continuous motion when
# they hard-cross a threshold every few frames. Soften each gate.

# Settle speed (world units / sec) below which pixel-snap may engage. Above
# this the eye tracks continuously so slow pans do not stair-step.
const PIXEL_SNAP_SETTLE: float = 0.12


static func pixel_snap_eye(pos: Vector3, world_per_pixel: float,
		eye_speed: float, settle: float = PIXEL_SNAP_SETTLE) -> Vector3:
	if world_per_pixel <= 0.0001 or eye_speed > settle:
		return pos
	return Vector3(
		snappedf(pos.x, world_per_pixel),
		snappedf(pos.y, world_per_pixel),
		snappedf(pos.z, world_per_pixel))


# Exponential coast with a hard rest floor — once below `rest`, velocity is
# zeroed so the next frame does not re-cross the threshold and chatter.
static func damp_orbit_velocity(v: float, decay: float, rest: float = 0.0005) -> float:
	var n: float = v * decay
	return 0.0 if absf(n) < rest else n


# Follow deadzone with hysteresis. Enter chase above `deadzone`; stop only
# after returning inside `deadzone * exit_frac`. Resting fish no longer shake
# the camera at the boundary. Returns {target, chasing}.
static func follow_deadzone_step(aim: Vector3, current: Vector3,
		deadzone: float, chasing: bool, exit_frac: float = 0.72) -> Dictionary:
	var enter: float = maxf(deadzone, 0.05)
	var exit_r: float = enter * clampf(exit_frac, 0.2, 0.95)
	var d: Vector3 = aim - current
	var dist: float = d.length()
	if chasing:
		if dist <= exit_r:
			return {"target": current, "chasing": false}
		return {"target": aim - d.normalized() * exit_r, "chasing": true}
	if dist > enter:
		return {"target": aim - d.normalized() * enter, "chasing": true}
	return {"target": current, "chasing": false}


# ---- Vessel-scaled input (HOLISTIC #035) ------------------------------------
#
# Compact and Grand tanks should take comparable effort to inspect. Derive a
# stable scale from the vessel's fit radius and footprint — NOT the live zoom —
# so selecting a saved close-up does not suddenly change mouse feel.

const REF_FIT_RADIUS: float = 15.5
const REF_FOOTPRINT: float = 8.0


static func vessel_speed_scale(fit_radius: float, footprint_r: float) -> float:
	var d: float = clampf(fit_radius / REF_FIT_RADIUS, 0.55, 1.7)
	var f: float = clampf(footprint_r / REF_FOOTPRINT, 0.55, 1.7)
	return clampf(sqrt(d * f), 0.65, 1.5)


static func orbit_sensitivity(scale: float) -> float:
	return SENSITIVITY * clampf(scale, 0.65, 1.5)


static func pan_sensitivity(scale: float) -> float:
	# Pan already multiplies by live radius for screen-space constancy; the
	# vessel scale only equalises absolute footprint feel across tank sizes.
	return PAN_MOUSE_SENSITIVITY * clampf(scale, 0.65, 1.5)


static func dolly_sensitivity(scale: float) -> float:
	return DOLLY_MOUSE_SENSITIVITY * clampf(scale, 0.65, 1.5)
