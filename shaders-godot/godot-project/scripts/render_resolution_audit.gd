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


## Display path must nearest-neighbor upscale the internal buffer. A non-nearest
## filter on the post TextureRect would blur pixel edges when the window resizes.
static func nearest_upscale_ok(texture_filter: int) -> bool:
	return texture_filter == int(CanvasItem.TEXTURE_FILTER_NEAREST) \
		or texture_filter == int(CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS)
