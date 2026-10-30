class_name MotionPersonality
extends RefCounted

# Per-individual motion signature (CREATURE_MOTION_700 #57, #58): tempo,
# amplitude, fin carriage, laterality, boldness and fidgetiness, seeded once
# and saved with the creature, so two fish of one species don't move as twins.
#
# Laterality: real fish favour one escape direction and one eye for inspecting
# novel things. -1 is a left-hander, +1 a right-hander; most fish sit near 0.

var tempo: float = 1.0          # multiplies tail-beat and bout rates (0.88..1.12)
var amplitude: float = 1.0      # multiplies stroke amplitude (0.82..1.18)
var fin_carriage: float = 0.0   # -1 clamped-ish .. +1 flared at rest
var laterality: float = 0.0     # -1 left .. +1 right
var boldness: float = 0.5       # 0 shy .. 1 bold, for path length and holds
var fidget: float = 0.5         # 0 placid .. 1 fidgety, for idle gestures
var seed_value: int = 0


static func from_seed(s: int) -> MotionPersonality:
	var p := MotionPersonality.new()
	var r := RandomNumberGenerator.new()
	r.seed = s
	p.seed_value = s
	p.tempo = r.randf_range(0.88, 1.12)
	p.amplitude = r.randf_range(0.82, 1.18)
	p.fin_carriage = r.randf_range(-0.4, 0.4)
	# Laterality clusters near zero with a few strongly lateralised fish.
	var lat: float = r.randfn(0.0, 0.35)
	p.laterality = clampf(lat, -1.0, 1.0)
	p.boldness = clampf(r.randfn(0.5, 0.18), 0.0, 1.0)
	p.fidget = clampf(r.randfn(0.5, 0.2), 0.0, 1.0)
	return p


# Pick a side for an ambiguous choice (escape, turn round an obstacle).
# Returns -1 or +1; the bias makes lateralised fish favour their side.
func choose_side(r: RandomNumberGenerator) -> float:
	return 1.0 if r.randf() < 0.5 + laterality * 0.35 else -1.0


func to_dict() -> Dictionary:
	return {
		"tempo": tempo, "amplitude": amplitude, "fin_carriage": fin_carriage,
		"laterality": laterality, "boldness": boldness, "fidget": fidget,
		"seed": seed_value,
	}


static func from_dict(d: Dictionary) -> MotionPersonality:
	var p := MotionPersonality.new()
	p.tempo = float(d.get("tempo", 1.0))
	p.amplitude = float(d.get("amplitude", 1.0))
	p.fin_carriage = float(d.get("fin_carriage", 0.0))
	p.laterality = float(d.get("laterality", 0.0))
	p.boldness = float(d.get("boldness", 0.5))
	p.fidget = float(d.get("fidget", 0.5))
	p.seed_value = int(d.get("seed", 0))
	return p
