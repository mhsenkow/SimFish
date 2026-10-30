class_name MotionLod
extends RefCounted

# Motion level of detail and pixel legibility (CREATURE_MOTION_700 #59, #60,
# #78). Each tier declares which motion features run, so expensive secondary
# motion (chains, gaze, opercula) is spent where it can be seen. The pixel
# helpers answer "how big is this motion on screen?", which decides both what
# to skip (under half a pixel) and how much a key pose may be exaggerated.

enum Tier { HERO, NEAR, FAR, OFFSCREEN }

const FEATURES: Dictionary = {
	Tier.HERO: {"chains": true, "gaze": true, "breath": true, "face": true, "shader_ripple": true},
	Tier.NEAR: {"chains": true, "gaze": true, "breath": true, "face": false, "shader_ripple": true},
	Tier.FAR: {"chains": false, "gaze": false, "breath": false, "face": false, "shader_ripple": true},
	Tier.OFFSCREEN: {"chains": false, "gaze": false, "breath": false, "face": false, "shader_ripple": false},
}

# Distances in tank units (a tank is about 16 wide). Hero is the followed or
# selected creature regardless of distance.
const NEAR_MAX: float = 9.0
const EXAGGERATION_CAP: float = 1.3


static func tier_for(distance: float, visible: bool, is_hero: bool) -> int:
	if not visible:
		return Tier.OFFSCREEN
	if is_hero:
		return Tier.HERO
	return Tier.NEAR if distance <= NEAR_MAX else Tier.FAR


static func has(tier: int, feature: String) -> bool:
	return bool((FEATURES.get(tier, FEATURES[Tier.FAR]) as Dictionary).get(feature, false))


# Screen pixels per world unit at a point, for a perspective or orthographic
# camera rendering viewport_h pixel rows.
static func px_per_unit(cam: Camera3D, world_pos: Vector3, viewport_h: float) -> float:
	if cam == null or viewport_h <= 0.0:
		return 0.0
	if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return viewport_h / maxf(cam.size, 1e-4)
	var depth: float = maxf(-(cam.global_transform.affine_inverse() * world_pos).z, 0.01)
	var visible_h: float = 2.0 * depth * tan(deg_to_rad(cam.fov) * 0.5)
	return viewport_h / maxf(visible_h, 1e-4)


static func amplitude_px(amplitude_units: float, ppu: float) -> float:
	return absf(amplitude_units) * ppu


# Gain that lifts a key channel to target_px, never past the cap (#359).
static func legibility_gain(amplitude_units: float, ppu: float, target_px: float = 2.0,
		cap: float = EXAGGERATION_CAP) -> float:
	var px: float = amplitude_px(amplitude_units, ppu)
	if px <= 1e-4:
		return 1.0
	var g: float = clampf(target_px / px, 1.0, cap)
	return 1.0 + (g - 1.0) * exaggeration_scale()


# A channel smaller than this is invisible and not worth computing.
static func worth_animating(amplitude_units: float, ppu: float, min_px: float = 0.5) -> bool:
	return amplitude_px(amplitude_units, ppu) >= min_px


# Reduced motion (#78): exaggeration and fast flicker drop by 60%.
static func exaggeration_scale() -> float:
	return 0.4 if AccessibilityRuntime.reduced_motion_enabled() else 1.0
