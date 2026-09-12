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
