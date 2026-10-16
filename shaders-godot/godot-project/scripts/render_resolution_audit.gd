class_name RenderResolutionAudit
extends RefCounted

# HOLISTIC #043 / PERFORMANCE_UNTHROTTLED #86 — post chain must quantize at the
# active internal fidelity tier, not the window size. Nearest-neighbor display
# upscale keeps chunky pixels; bilinear would silently blur edges on resize.

# Supported internal grids (16:9). Matches main._ADAPTIVE_RES_TIERS and
# TankConfig / STYLE_GUIDE. First-launch beauty defaults may seed mid (512×288);
# the shipping TankConfig default is high desktop (1024×576).
const TIER_POTATO := Vector2i(256, 144)
const TIER_COMPACT := Vector2i(384, 216)  # style-guide design-intent compact grid
const TIER_MID := Vector2i(512, 288)
const TIER_HIGH := Vector2i(768, 432)
const TIER_DESKTOP := Vector2i(1024, 576)

const DEFAULT_INTERNAL := TIER_DESKTOP
const BEAUTY_DEFAULT_INTERNAL := TIER_MID

## Historical single-size constants — prefer `supported_tiers()` / `internal_size_ok`.
## Kept so older call sites compiling against INTERNAL_W/H still resolve.
const INTERNAL_W: int = 512
const INTERNAL_H: int = 288


static func supported_tiers() -> Array[Vector2i]:
	return [
		TIER_POTATO,
		TIER_COMPACT,
		TIER_MID,
		TIER_HIGH,
		TIER_DESKTOP,
	]


static func tier_label(w: int, h: int) -> String:
	var key := Vector2i(w, h)
	if key == TIER_POTATO:
		return "potato"
	if key == TIER_COMPACT:
		return "compact"
	if key == TIER_MID:
		return "mid"
	if key == TIER_HIGH:
		return "high"
	if key == TIER_DESKTOP:
		return "desktop"
	return "custom"


static func internal_size_ok(w: int, h: int) -> bool:
	for t: Vector2i in supported_tiers():
		if t.x == w and t.y == h:
			return true
	return false


static func post_matches_3d(render_w: int, render_h: int, post_w: int, post_h: int) -> bool:
	return post_w == render_w and post_h == render_h


# Design frame. The project viewport starts here; stretch/aspect=expand grows
# one axis so a 16:10 desktop (or a 4:3 iPad) is not letterboxed in black.
const DESIGN_ASPECT: float = 1536.0 / 864.0


# Keep the chosen tier's pixel count, but match the window so the nearest
# blit is not a stretch and the root viewport has no empty bars.
static func size_for_window(base: Vector2i, window: Vector2) -> Vector2i:
	if base.x < 2 or base.y < 2 or window.x < 2.0 or window.y < 2.0:
		return base
	var window_aspect: float = window.x / window.y
	var base_aspect: float = float(base.x) / float(base.y)
	if absf(window_aspect - base_aspect) < 0.015:
		return base
	var area: float = float(base.x) * float(base.y)
	var h: float = sqrt(area / window_aspect)
	var wi: int = maxi(64, int(round(h * window_aspect)))
	var hi: int = maxi(64, int(round(h)))
	if wi % 2 == 1:
		wi += 1
	if hi % 2 == 1:
		hi += 1
	return Vector2i(wi, hi)


# Vertical fov that keeps the 16:9 width when the window is taller, so the
# extra space shows room instead of cropping the tank. Wider windows keep
# the authored fov and reveal more to the sides.
static func vertical_fov_for_window(base_fov: float, window_aspect: float) -> float:
	var fov: float = clampf(base_fov, 20.0, 110.0)
	if window_aspect >= DESIGN_ASPECT - 0.02:
		return fov
	var aspect: float = maxf(0.4, window_aspect)
	var half: float = deg_to_rad(fov) * 0.5
	var half_adj: float = atan(tan(half) * DESIGN_ASPECT / aspect)
	return clampf(rad_to_deg(half_adj * 2.0), 20.0, 110.0)


## Display path must nearest-neighbor upscale the internal buffer. A non-nearest
## filter on the post TextureRect would blur pixel edges when the window resizes.
static func nearest_upscale_ok(texture_filter: int) -> bool:
	return texture_filter == int(CanvasItem.TEXTURE_FILTER_NEAREST) \
		or texture_filter == int(CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS)
