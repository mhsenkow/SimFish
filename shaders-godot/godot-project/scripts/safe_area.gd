# Shared display safe-area insets (notch / punch-hole / home indicator).
#
# Godot reports the device safe area in *screen* pixels via
# DisplayServer.get_display_safe_area(). Every HUD element in this game is
# laid out in *viewport* pixels, and on mobile the two differ (content scale,
# render-scale, letterboxing). Before this module only mobile_hud.gd did the
# conversion, so the top stats bar slid under the notch and the footer sat
# under the iOS home indicator / Android gesture pill.
#
# Usage (all values are viewport pixels, always >= 0):
#
#     var pad := SafeArea.insets(get_viewport())
#     stats_bar.offset_top = 4.0 + pad.y
#     footer.offset_bottom = -pad.w
#
# The result is memoised on (viewport size, screen size, screen index) so the
# per-frame callers pay a Vector2 compare, not a DisplayServer round-trip.
#
# Desktop returns ZERO insets — get_display_safe_area() reports the whole
# screen there, so the maths below collapses to 0 on its own; the explicit
# `supported()` gate just skips the work.

class_name SafeArea
extends RefCounted

# left, top, right, bottom — packed so callers can cache one value.
const ZERO: Vector4 = Vector4(0.0, 0.0, 0.0, 0.0)

# Cap the reported inset so a bogus DisplayServer answer (or a device with a
# genuinely enormous cutout) can never eat the whole HUD.
const MAX_INSET_FRACTION: float = 0.18

static var _cache_key: Vector4i = Vector4i(-1, -1, -1, -1)
static var _cache_val: Vector4 = ZERO
static var _override_active: bool = false
static var _override_val: Vector4 = ZERO


# Headless smokes have no display server geometry — this lets a test pin a
# synthetic notch and assert the HUD moves. Pass ZERO-with-active to model a
# device that has no cutout at all.
static func set_test_override(pad: Vector4) -> void:
	_override_active = true
	_override_val = Vector4(
		maxf(0.0, pad.x), maxf(0.0, pad.y),
		maxf(0.0, pad.z), maxf(0.0, pad.w))


static func clear_test_override() -> void:
	_override_active = false
	_override_val = ZERO
	_cache_key = Vector4i(-1, -1, -1, -1)


static func supported() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


static func insets(vp: Viewport) -> Vector4:
	if _override_active:
		return _override_val
	if vp == null or not supported():
		return ZERO
	var view: Vector2 = vp.get_visible_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		return ZERO
	var screen: Vector2i = DisplayServer.screen_get_size()
	var key := Vector4i(int(view.x), int(view.y), screen.x, screen.y)
	if key == _cache_key:
		return _cache_val
	_cache_key = key
	_cache_val = _compute(view, screen)
	return _cache_val


static func _compute(view: Vector2, screen: Vector2i) -> Vector4:
	if screen.x <= 0 or screen.y <= 0:
		return ZERO
	var area: Rect2i = DisplayServer.get_display_safe_area()
	if area.size.x <= 0 or area.size.y <= 0:
		return ZERO
	# Screen -> viewport scale. These differ whenever the game renders at a
	# different resolution than the panel (render scale, stretch mode).
	var sx: float = view.x / float(screen.x)
	var sy: float = view.y / float(screen.y)
	var left: float = float(area.position.x) * sx
	var top: float = float(area.position.y) * sy
	var right: float = float(screen.x - (area.position.x + area.size.x)) * sx
	var bottom: float = float(screen.y - (area.position.y + area.size.y)) * sy
	var cap_x: float = view.x * MAX_INSET_FRACTION
	var cap_y: float = view.y * MAX_INSET_FRACTION
	return Vector4(
		clampf(left, 0.0, cap_x),
		clampf(top, 0.0, cap_y),
		clampf(right, 0.0, cap_x),
		clampf(bottom, 0.0, cap_y))


# Convenience: the safe rect in viewport space. mobile_hud.gd wants this form.
static func rect(vp: Viewport) -> Rect2:
	if vp == null:
		return Rect2()
	var view: Vector2 = vp.get_visible_rect().size
	var pad: Vector4 = insets(vp)
	return Rect2(pad.x, pad.y,
		maxf(0.0, view.x - pad.x - pad.z),
		maxf(0.0, view.y - pad.y - pad.w))
