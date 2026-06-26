extends RefCounted

# Two-axis affect substrate (SENTIENT_FISH_IDEAS.md #26).
# fish.gd owns state: mood = valence [-1,1], arousal = calm↔excited [0,1].


static func tick_affect(f: Fish, dt: float) -> void:
	var arousal_target: float = f.stress * 0.55 + f.spooked * 0.45 + f.hunger * 0.25
	arousal_target += clampf(f.mood, 0.0, 1.0) * 0.15
	if f.burst_remaining > 0.0 or f._startle_remaining > 0.0:
		arousal_target += 0.35
	if f.current_mode == Fish.Mode.COURT or f.current_mode == Fish.Mode.SPAWN:
		arousal_target += 0.3
	if f._asleep:
		arousal_target *= 0.2
	else:
		arousal_target += clampf(f.speed * 0.035, 0.0, 0.2)
	f.arousal = lerpf(f.arousal, clampf(arousal_target, 0.0, 1.0), clampf(dt * 0.5, 0.0, 1.0))


static func animation_modifiers(f: Fish) -> Dictionary:
	# Orthogonal valence × arousal reads for swim/fin/breath/color.
	var v: float = f.mood
	var a: float = f.arousal
	var content: float = clampf(v, 0.0, 1.0)
	var distress: float = clampf(-v, 0.0, 1.0)
	return {
		"wag_freq": a * 0.22 - (1.0 - a) * content * 0.10,
		"pec_spread": content * 0.10 + a * 0.12 - distress * 0.06,
		"fin_amp": a * 0.08 - distress * 0.05,
		"breath_calm": (1.0 - a) * content * 0.12,
		"color_flare": a * 0.08,
		"color_pallor": distress * (1.0 - a) * 0.08,
	}


static func nudge_arousal(f: Fish, amount: float) -> void:
	f.arousal = clampf(f.arousal + amount, 0.0, 1.0)
