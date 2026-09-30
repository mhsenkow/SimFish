extends RefCounted

# ONBOARDING_LEGIBILITY — "you can talk to the tank".
#
# The tank talk channel (no fish followed -> a "the tank" box bottom-left,
# Enter focuses it) is the game's most surprising feature and nothing points
# at it. Once, after the tank has settled, the tank mind speaks first and the
# box pulses. It never repeats: not after it has fired once, and not at all
# for a player who has already spoken to the tank on their own.
#
# Pure decision logic here (smoke-tested); onboarding_runtime.gd feeds it the
# live state and does the showing. Flags persist in OnboardingLegibility's
# global prefs, so they span every tank slot.

const PREF_SPOKEN: String = "has_spoken_to_tank"
const PREF_PROMPTED: String = "tank_talk_prompted"
# Seconds of *settled, uncluttered* live time before the tank speaks first:
# long enough that the player has looked around, short enough to land inside
# the first minutes.
const SETTLE_S: float = 75.0
const LINE: String = "…you're watching us. press enter, and speak."

enum Decision { WAIT, FIRE, NEVER }


# state keys (all optional; missing = the permissive default):
#   spoken (bool), prompted (bool)    persisted flags
#   voice_off (bool)                  sentience voice off / voice UI hidden
#   channel_available (bool)          the tank box is on screen right now
#   blocked (bool)                    walkthrough, card, nudge, creator, following a fish
#   settled_s (float)                 accumulated unblocked live seconds
static func decide(state: Dictionary) -> int:
	if bool(state.get("spoken", false)) or bool(state.get("prompted", false)):
		return Decision.NEVER
	if bool(state.get("voice_off", false)):
		return Decision.WAIT
	if bool(state.get("blocked", false)) or not bool(state.get("channel_available", false)):
		return Decision.WAIT
	if float(state.get("settled_s", 0.0)) < SETTLE_S:
		return Decision.WAIT
	return Decision.FIRE


# Settle time only accrues while nothing else is asking for attention, so a
# player busy with the walkthrough or a card is never interrupted by it.
static func accrue(settled_s: float, dt: float, blocked: bool) -> float:
	if blocked:
		return settled_s
	return settled_s + maxf(dt, 0.0)


# Did the keeper talk to the tank? The conversation log in main.gd tags the
# keeper's tank lines "you → the tank".
static func history_has_tank_line(history: Array) -> bool:
	for e in history:
		if e is Dictionary and str((e as Dictionary).get("who", "")).begins_with("you → the tank"):
			return true
	return false
