extends RefCounted
class_name HudLayout

# Top-bar geometry.
#
# THE BUG. The stats bar's left edge was a hard-coded 128 in main.tscn and a
# hard-coded 96 / 88 at runtime, while the menu cluster beside it is a
# PanelContainer that sizes to its own contents. Nothing connected the two,
# so the moment the cluster grew past the guess it slid underneath the
# stats chips and the Menu and fullscreen buttons became unclickable.
#
# The cluster grows for several ordinary reasons: a longer button label, a
# larger UI scale, an added button - and, most of all, TRANSLATION. The
# pseudolocale alone renders "Menu" as a bracketed accented string roughly
# 40% wider, and a real German or Finnish string is longer again. A literal
# cannot survive any of that; a measurement survives all of it.

# Gap between the menu cluster and the first stats chip.
const CLUSTER_GAP: float = 10.0
# Floor, so an unmeasured cluster (first frame, before layout) still leaves
# the bar roughly where it has always been rather than jumping to the edge.
const MIN_INSET: float = 88.0
# Ceiling, so a pathological measurement cannot push the stats off-screen.
const MAX_INSET_FRAC: float = 0.42


# Left edge for the stats bar, given where the menu cluster actually ends.
static func stats_left_inset(cluster_left: float, cluster_width: float,
		safe_pad_x: float, viewport_w: float) -> float:
	var measured: float = cluster_left + maxf(0.0, cluster_width) + CLUSTER_GAP
	var want: float = maxf(MIN_INSET + safe_pad_x, measured)
	if viewport_w > 1.0:
		want = minf(want, viewport_w * MAX_INSET_FRAC)
	return want


# Breakpoint for the whole top bar. Kept here so the thresholds are
# assertable rather than buried in an 11k-line input handler.
static func layout_for(viewport_w: float, is_touch: bool) -> String:
	if viewport_w < 700.0 or (is_touch and viewport_w < 900.0):
		return "compact"
	if viewport_w < 1100.0:
		return "medium"
	return "wide"


# ---- Screen regions ----------------------------------------------------------
#
# THE BUG this replaces. Every panel, strip and toast was placed by its own
# anchor block against the same two literals (HUD_TOP, FOOTER_HEIGHT), neither
# of which matched the real chrome: the top bar ends at ~52 px, not 44, and
# the footer is 56 px tall, not 48. So every side panel slid 8 px under the
# stats bar, the footer hung 8 px off the bottom, and the follow-thought
# strip, the toast stack and the feed/status toasts each picked a spot that
# ignored the others. Nothing said "this corner belongs to X".
#
# regions() is that statement. It takes the MEASURED top-bar bottom, footer
# height and rail cluster edge and carves the screen into named, disjoint
# rects. main.gd places everything into one of them; UiPanelManager keeps each
# column exclusive. The state-dependent part is the bottom band: the stack and
# the centre slot sit beside whichever columns are open, never under them.

const TOP_BAR := "TOP_BAR"
const RAIL := "RAIL"
const BOTTOM_BAR := "BOTTOM_BAR"
const LEFT_COLUMN := "LEFT_COLUMN"
const RIGHT_COLUMN := "RIGHT_COLUMN"
const BOTTOM_LEFT_STACK := "BOTTOM_LEFT_STACK"
const BOTTOM_CENTRE := "BOTTOM_CENTRE"
const CENTRE_MODAL := "CENTRE_MODAL"
# Free work area between chrome and open columns — camera framing fits here
# (HOLISTIC #022), not into the full viewport under an open side panel.
const AVAILABLE_CENTER := "AVAILABLE_CENTER"
# Every Rect2 key regions() returns (CENTRE_MODAL overlaps the rest by design:
# it sits over them behind a scrim). AVAILABLE_CENTER is the unobscured tank
# view; it shrinks when a column opens.
const REGION_KEYS: Array[String] = [TOP_BAR, RAIL, BOTTOM_BAR, LEFT_COLUMN,
	RIGHT_COLUMN, BOTTOM_LEFT_STACK, BOTTOM_CENTRE, CENTRE_MODAL, AVAILABLE_CENTER]
# Bool key: true when both columns cannot be open at once (plus a usable
# centre band) — opening one column must then close the other.
const COLUMNS_EXCLUSIVE := "columns_exclusive"

# Breathing room between neighbouring regions.
const GAP: float = 8.0
# Bottom-left stack (notification toasts + follow-thought strip + say box).
const STACK_W: float = 440.0
const STACK_FRAC: float = 0.45
# Toasts (160) + gap + a strip with name, one body line, history and say box.
const STACK_MIN_H: float = 320.0
const STACK_MAX_FRAC: float = 0.70
# Bottom-centre slot (feed hint, status toast, onboarding nudge): a queue that
# stacks upward, two lanes tall.
const CENTRE_W: float = 460.0
const CENTRE_MIN_W: float = 320.0
const CENTRE_H: float = 112.0
# Modals keep this much of the viewport visible around them.
const MODAL_MARGIN: float = 24.0


# Width of a side column (left or right) for a viewport width.
static func column_width(viewport_w: float) -> float:
	return clampf(viewport_w * 0.33, PanelTheme.PANEL_MIN_W, PanelTheme.PANEL_MAX_W)


# vp: viewport size. safe_pad: (left, top, right, bottom) safe-area insets.
# rail_dock: "right" | "bottom". top_bar_bottom: measured bottom edge of the
# top HUD. footer_h: measured distance from the viewport bottom to the
# footer's top edge. rail_cluster_left: measured left edge of the rail
# cluster (<= 0 = unmeasured). left_open / right_open: which columns are
# occupied, which decides where the bottom band's stack and centre slot go.
# left_extent / right_extent: the open panels' MEASURED outer edges (0 =
# unknown) — a panel wider than its column still pushes the band aside.
static func regions(vp: Vector2, safe_pad: Vector4, rail_dock: String,
		top_bar_bottom: float, footer_h: float, rail_cluster_left: float,
		left_open: bool = false, right_open: bool = false,
		left_extent: float = 0.0, right_extent: float = 0.0) -> Dictionary:
	var out: Dictionary = {}
	var edge_l: float = PanelTheme.EDGE_MARGIN + safe_pad.x
	var edge_r: float = PanelTheme.EDGE_MARGIN + safe_pad.z
	var top_b: float = clampf(top_bar_bottom, 0.0, vp.y * 0.4)
	var footer_top: float = vp.y - clampf(footer_h, 0.0, vp.y * 0.4)
	out[TOP_BAR] = Rect2(0.0, 0.0, vp.x, top_b)
	out[BOTTOM_BAR] = Rect2(0.0, footer_top, vp.x, vp.y - footer_top)
	var work_top: float = top_b + GAP
	var work_bottom: float = footer_top - GAP
	var right_limit: float = vp.x - edge_r
	if rail_dock == "bottom":
		var rail_top: float = work_bottom - PanelTheme.RAIL_BOTTOM_HEIGHT
		out[RAIL] = Rect2(0.0, rail_top, vp.x, work_bottom - rail_top)
		work_bottom = rail_top - GAP
	else:
		var rl: float = rail_cluster_left
		if rl <= 0.0 or rl > vp.x:
			rl = vp.x - edge_r - PanelTheme.RAIL_WIDTH
		rl = clampf(rl, vp.x * 0.5, vp.x)
		out[RAIL] = Rect2(rl, work_top, vp.x - rl, maxf(0.0, work_bottom - work_top))
		right_limit = rl - GAP
	var h: float = maxf(0.0, work_bottom - work_top)
	var col_w: float = minf(column_width(vp.x), maxf(0.0, right_limit - edge_l))
	out[LEFT_COLUMN] = Rect2(edge_l, work_top, col_w, h)
	out[RIGHT_COLUMN] = Rect2(right_limit - col_w, work_top, col_w, h)
	var exclusive: bool = right_limit - edge_l < col_w * 2.0 + GAP * 2.0 + CENTRE_MIN_W
	out[COLUMNS_EXCLUSIVE] = exclusive
	if exclusive and left_open and right_open:
		right_open = false
	var cx0: float = edge_l
	if left_open:
		cx0 = maxf(edge_l + col_w, minf(left_extent, right_limit * 0.75)) + GAP
	var cx1: float = right_limit
	if right_open:
		var rx: float = right_limit - col_w
		if right_extent > 0.0:
			rx = minf(rx, maxf(right_extent, cx0 + CENTRE_MIN_W))
		cx1 = rx - GAP
	var band_w: float = maxf(0.0, cx1 - cx0)
	var stack_h: float = clampf(maxf(h * STACK_FRAC, STACK_MIN_H), 0.0, h * STACK_MAX_FRAC)
	if band_w >= STACK_W + GAP + CENTRE_MIN_W:
		# Wide band: stack at its left, centre slot beside it (centred on the
		# screen when that still clears the stack).
		var free0: float = cx0 + STACK_W + GAP
		var cw: float = minf(CENTRE_W, cx1 - free0)
		var cxc: float = clampf(vp.x * 0.5, free0 + cw * 0.5, cx1 - cw * 0.5)
		out[BOTTOM_CENTRE] = Rect2(cxc - cw * 0.5, work_bottom - CENTRE_H, cw, CENTRE_H)
		out[BOTTOM_LEFT_STACK] = Rect2(cx0, work_bottom - stack_h, STACK_W, stack_h)
	else:
		# Narrow band: centre slot on the bottom, stack above it.
		var cw2: float = minf(CENTRE_W, band_w)
		out[BOTTOM_CENTRE] = Rect2(cx0 + (band_w - cw2) * 0.5, work_bottom - CENTRE_H,
			cw2, CENTRE_H)
		var sh: float = minf(stack_h, maxf(0.0, h - CENTRE_H - GAP))
		out[BOTTOM_LEFT_STACK] = Rect2(cx0, work_bottom - CENTRE_H - GAP - sh,
			minf(STACK_W, band_w), sh)
	# Modals centre in the work area (between top bar and footer, clear of
	# the rail) with a side margin: the scrim dims the chrome, the modal
	# never covers it.
	var mx: float = MODAL_MARGIN
	var m0: float = edge_l + mx
	var m1: float = right_limit - mx
	if m1 - m0 < vp.x * 0.5:
		m0 = edge_l
		m1 = right_limit
	out[CENTRE_MODAL] = Rect2(m0, work_top, maxf(0.0, m1 - m0), h)
	# Usable tank view: full work height, same horizontal band as the bottom
	# stack/centre slot (clears open columns). Feed this into camera framing.
	out[AVAILABLE_CENTER] = Rect2(cx0, work_top, maxf(0.0, cx1 - cx0), h)
	return out


# Aspect of the free tank view. Falls back to the viewport aspect when the
# region is missing or degenerate.
static func available_aspect(regs: Dictionary, fallback_aspect: float = 16.0 / 9.0) -> float:
	var r: Rect2 = regs.get(AVAILABLE_CENTER, Rect2()) as Rect2
	if r.size.y < 1.0 or r.size.x < 1.0:
		return maxf(0.3, fallback_aspect)
	return r.size.x / r.size.y


# How far the free-centre midpoint sits from the viewport midpoint, as a
# fraction of half-viewport (−1..1). Positive X = free centre is to the right
# of screen centre (left panel open) — the camera should bias the tank that way.
static func available_center_bias(regs: Dictionary, vp: Vector2) -> Vector2:
	var r: Rect2 = regs.get(AVAILABLE_CENTER, Rect2()) as Rect2
	if r.size.x < 1.0 or r.size.y < 1.0 or vp.x < 1.0 or vp.y < 1.0:
		return Vector2.ZERO
	var mid: Vector2 = r.get_center()
	return Vector2(
		clampf((mid.x - vp.x * 0.5) / (vp.x * 0.5), -1.0, 1.0),
		clampf((mid.y - vp.y * 0.5) / (vp.y * 0.5), -1.0, 1.0))


# Place `c` at an absolute rect (anchors collapsed to the top-left). A control
# whose own minimum is wider than the rect grows toward `grow_left` side, so a
# right-column panel overflows away from the rail rather than under it.
static func place(c: Control, r: Rect2, grow_left: bool = false) -> void:
	if c == null:
		return
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 0.0
	c.anchor_bottom = 0.0
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN if grow_left \
			else Control.GROW_DIRECTION_END
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.end.x
	c.offset_bottom = r.end.y


# A rect of `want` size centred in `region`, never larger than it.
static func centred_in(region: Rect2, want: Vector2) -> Rect2:
	var s := Vector2(minf(want.x, region.size.x), minf(want.y, region.size.y))
	return Rect2(region.position + (region.size - s) * 0.5, s)
