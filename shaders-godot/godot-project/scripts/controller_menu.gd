class_name ControllerMenu
extends RefCounted

# Pad "Options" menu destination contract.
#
# Valve build review (BuildID #24083947, failure 3) rejected the store's
# **Full Controller Support** category because a pad could not reach every
# function without keyboard/mouse. The menu order lives here — rather than
# inline in main._open_gamepad_menu() — so that
# `smoke_controller_coverage.gd` can assert the contract headlessly and CI
# catches a regression before the next resubmission does.
#
# main.gd owns the Callables; this owns the labels and their order.

# Destinations Valve's checklist walks. Removing any of these from the pad
# menu re-breaks Full Controller Support, so the smoke treats it as fatal.
#
#   - Open tank → play → Options → Quit          ("Settings", "Quit game")
#   - Tank list → New tank → enter tank on pad   ("Tank list")
#   - Settings / Adopt / Help open+close with ○  ("Settings", "Adopt fish", "Help")
const REQUIRED_DESTINATIONS: Array[String] = [
	"Settings",
	"Adopt fish",
	"Help",
	"Tank list",
	"Quit game",
]

# Label used for the aquascape toggle, which flips with mode.
const AQUASCAPE_ENTER := "Aquascape"
const AQUASCAPE_EXIT := "Exit Aquascape"

# Everything before the aquascape toggle.
const _HEAD: Array[String] = [
	"Settings",
	"Choose tank",
	"Residents",
	"Mind",
	"Camera views",
	"Adopt fish",
	"Library",
	"Sound",
	"Rendering",
]

# Everything after it.
const _TAIL: Array[String] = [
	"Copy tank code",
	"Help",
	"Pause / Resume",
	"Tank list",
	"Quit game",
	"Close menu",
]


# Ordered pad-menu labels. When aquascape is active its toggle is hoisted to
# the top — it is the easiest couch escape after ○ / △.
static func destination_labels(aquascape_active: bool) -> PackedStringArray:
	var out := PackedStringArray()
	var aqua: String = AQUASCAPE_EXIT if aquascape_active else AQUASCAPE_ENTER
	if aquascape_active:
		out.append(aqua)
	out.append_array(_HEAD)
	if not aquascape_active:
		out.append(aqua)
	out.append_array(_TAIL)
	return out


# Labels present in neither ordering — i.e. a destination that would be
# unreachable on a pad. Empty means the contract holds.
static func missing_required(labels: PackedStringArray) -> PackedStringArray:
	var missing := PackedStringArray()
	for want in REQUIRED_DESTINATIONS:
		if not labels.has(want):
			missing.append(want)
	return missing
