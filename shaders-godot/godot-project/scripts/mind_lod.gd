class_name MindLOD
extends RefCounted

# META #20 — cognition LOD tiers as a first-class concept. Each fish is assigned a
# thinking depth from status (guardian/named/familiar), visibility, and a global
# budget pressure, so the tank thinks hard where it matters and cheaply elsewhere.
# This is the principled scheduler input that should replace sim_driver's ad-hoc
# off-frustum phase hack, and the gate #19 uses to graduate the richer generative
# model to high-tier fish.
#
#   T0 reflex-only · T1 +Global Workspace · T2 +world-model · T3 +LLM voice
#
# Scope: this is the pure tier model + assignment (tested). Wiring sim_driver /
# mind_cycle to actually skip phases by tier is the follow-up integration.

const T0_REFLEX: int = 0
const T1_WORKSPACE: int = 1
const T2_WORLD_MODEL: int = 2
const T3_VOICE: int = 3


# Status weight: guardian > named > familiar > anonymous.
static func status_rank(f) -> int:
	if f.is_guardian:
		return 3
	if f.fish_name != "":
		return 2
	if f.familiarity > 0.4:
		return 1
	return 0


# Assign a cognition tier. budget_pressure 0 = idle, 1 = overloaded (demotes all).
static func tier_for(f, visible: bool, budget_pressure: float = 0.0) -> int:
	var status: int = status_rank(f)
	var base: int
	if visible:
		# On-screen fish think deeply; named/guardian on-screen earn a voice.
		base = T3_VOICE if status >= 2 else T2_WORLD_MODEL
	elif status >= 2:
		base = T2_WORLD_MODEL    # off-screen protagonists keep their world model
	elif status >= 1:
		base = T1_WORKSPACE      # off-screen familiars keep attention
	else:
		base = T0_REFLEX         # a distant nobody runs reflex only
	# Budget pressure caps the tier — the tank sheds depth under load.
	if budget_pressure > 0.66:
		base = mini(base, T1_WORKSPACE)
	elif budget_pressure > 0.33:
		base = mini(base, T2_WORLD_MODEL)
	return clampi(base, T0_REFLEX, T3_VOICE)


static func runs_workspace(tier: int) -> bool:
	return tier >= T1_WORKSPACE


static func runs_world_model(tier: int) -> bool:
	return tier >= T2_WORLD_MODEL


static func runs_voice(tier: int) -> bool:
	return tier >= T3_VOICE


const TIER_HYSTERESIS_S: float = 0.5


# PERFORMANCE_UNTHROTTLED #9 — debounce tier transitions at frustum edges.
static func tier_for_hysteresis(f, visible: bool, budget_pressure: float, dt: float,
		current_tier: int) -> int:
	var target: int = tier_for(f, visible, budget_pressure)
	if f == null:
		return target
	if target == current_tier:
		f._lod_tier_hold_s = 0.0
		return current_tier
	var hold: float = f._lod_tier_hold_s
	hold += maxf(dt, 0.0)
	f._lod_tier_hold_s = hold
	if hold < TIER_HYSTERESIS_S:
		return current_tier
	f._lod_tier_hold_s = 0.0
	return target
