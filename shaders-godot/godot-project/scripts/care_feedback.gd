# What a care action LOOKS like (VISUAL_DIRECTIONS #16).
#
# THE GAP. Feed, water change, filter rinse, glass wipe — every one of them
# changes the sim, and the strongest visual feedback any of them produced was
# `_pulse_care_dock()`, which flashes the button the player just pressed, plus
# a toast that says in words what happened.
#
# In a game whose entire pitch is a living picture, words are the fallback, not
# the channel. A keeper who changes the water should see the water change.
#
# THE GRAMMAR. Every action answers the same four questions, so the feedback
# reads as one language rather than a pile of one-off effects:
#
#   WHERE   at the place the action touched, not in the corner of the screen
#   WHAT    a particle burst whose kind and colour say which action it was
#   HOW BIG proportional to the effect on the sim, not a constant
#   HOW LONG several seconds — long enough to look at, short enough to end
#
# PURE. Action + magnitude in, a description out. The driver in world.gd spends
# the existing transient particle pool and the existing wipe/disturb hooks on
# it; nothing here touches the scene tree, so the grammar can be asserted
# headlessly and changed without touching the systems it drives.

class_name CareFeedback
extends RefCounted

# Longest any single care event may hold the frame. Past this it stops reading
# as a response to what the player did.
const MAX_DURATION_S: float = 4.5
# …and shortest. Below this a burst is a flicker the eye files as an artefact.
const MIN_DURATION_S: float = 0.9

# Particle kinds the pool already knows how to make.
const KIND_SPLASH: String = "splash"
const KIND_CAVITATION: String = "cavitation"


# A description of one visible care event.
#
#   kind              particle pool kind
#   color             tint for the burst
#   bursts            how many bursts to spend, scaled by magnitude
#   duration_s        how long the whole event reads for
#   glass_wipe        0..1, how much glass film to clear
#   substrate_disturb 0..1, how much silt to lift
#   at_surface        true when the event belongs at the waterline rather
#                     than at the point the player touched
static func event_for(action: String, magnitude: float) -> Dictionary:
	var m: float = clampf(magnitude, 0.0, 1.0)
	match action:
		"water_change":
			# A fresh fill falls from the top and drives a curtain of fine
			# bubbles down the glass. It is the one care action a keeper can
			# see from across the room, so it gets the longest read.
			return _evt(KIND_CAVITATION, Color(0.86, 0.94, 1.0, 0.6),
				2 + int(round(m * 4.0)), lerpf(1.4, 3.6, m), 0.22 * m, 0.10 * m, true)
		"filter_rinse":
			# Flow returns: a puff of trapped detritus off the intake and a
			# surge that lifts silt. Dirtier than a water change on purpose.
			return _evt(KIND_SPLASH, Color(0.72, 0.66, 0.54, 0.7),
				1 + int(round(m * 3.0)), lerpf(1.1, 2.4, m), 0.0, 0.45 * m, false)
		"glass_wipe":
			# The one action whose whole point is that the picture gets
			# clearer, so it spends its budget on the wipe, not on particles.
			return _evt(KIND_CAVITATION, Color(0.90, 0.96, 1.0, 0.45),
				1, lerpf(0.9, 1.8, m), 0.95 * m, 0.0, false)
		"feed":
			# Food already has its own particles and its own fish response;
			# this is the ring at the drop point, not a second food system.
			return _evt(KIND_SPLASH, Color(1.0, 0.94, 0.78, 0.65),
				1 + int(round(m * 2.0)), lerpf(0.9, 1.6, m), 0.0, 0.0, true)
		_:
			return {}


static func _evt(kind: String, color: Color, bursts: int, duration: float,
		wipe: float, disturb: float, at_surface: bool) -> Dictionary:
	return {
		"kind": kind,
		"color": color,
		"bursts": maxi(bursts, 1),
		"duration_s": clampf(duration, MIN_DURATION_S, MAX_DURATION_S),
		"glass_wipe": clampf(wipe, 0.0, 1.0),
		"substrate_disturb": clampf(disturb, 0.0, 1.0),
		"at_surface": at_surface,
	}


static func is_known(action: String) -> bool:
	return not event_for(action, 0.5).is_empty()


# Where the bursts go, spread around the origin so a multi-burst event reads
# as a spreading disturbance rather than a stack of identical puffs.
static func burst_offsets(count: int, spread: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var n: int = maxi(count, 1)
	# Golden-angle spiral: even coverage for any count, without needing a
	# different pattern for 2 puffs than for 6.
	var golden: float = PI * (3.0 - sqrt(5.0))
	for i in n:
		var r: float = spread * sqrt(float(i) + 0.5) / sqrt(float(n))
		var a: float = float(i) * golden
		out.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
	return out
