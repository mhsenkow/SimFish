extends RefCounted

# Startup-only motion shaping. Established fish bypass this through Fish's
# remaining-time branch, so the normal locomotion path stays unchanged.

const FRESH_DURATION: float = 0.60
const FRY_DURATION: float = 0.45
const RESTORE_DURATION: float = 0.24


static func factor(remaining: float, duration: float) -> float:
	if remaining <= 0.0:
		return 1.0
	var safe_duration: float = maxf(duration, 0.001)
	var t: float = clampf(1.0 - remaining / safe_duration, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func oscillator_delta(previous_phase: float, next_phase: float,
		amplitude: float) -> float:
	return (sin(next_phase * TAU) - sin(previous_phase * TAU)) * amplitude


static func seeded_phase(identity: String, salt: int) -> float:
	var h: int = hash(identity + ":" + str(salt))
	return float(posmod(h, 10007)) / 10007.0
