class_name FishExaggeration
extends RefCounted

# CREATURE_MOTION_700 §M — exaggeration with restraint (#359–374).
# Key channels may grow for legibility; realism anchors stay biological.


const CAP: float = 1.3  # #359 hard ceiling (music may lift to 1.4 — #369)
const MUSIC_CAP: float = 1.4

# #367: channels that must never receive the legibility gain.
const DO_NOT_EXAGGERATE: PackedStringArray = [
	"cruise_tail_amp",
	"school_spacing",
	"swim_speed",
	"snail_speed",
]

# #374: ledger — real → game → reason (values are multipliers unless noted).
const LEDGER: Array[Dictionary] = [
	{"channel": "fin_erection", "real": 1.0, "game": 1.3, "reason": "reads at 22 px (#359)"},
	{"channel": "c_start_duration", "real": 1.0, "game": 1.2, "reason": "hold the curl (#360/#342)"},
	{"channel": "c_start_angle", "real": 1.0, "game": 1.0, "reason": "keep 90–120° biological (#360)"},
	{"channel": "display_fin_area", "real": 1.0, "game": 1.2, "reason": "display flare (#361)"},
	{"channel": "display_hold", "real": 1.0, "game": 1.5, "reason": "display hold (#361)"},
	{"channel": "strike_stretch", "real": 1.0, "game": 1.15, "reason": "bite reads (#362/#123)"},
	{"channel": "clamp_fin_scale", "real": 0.7, "game": 0.6, "reason": "stress at 22 px (#363)"},
	{"channel": "clamp_darken", "real": 0.0, "game": 0.18, "reason": "stress pigment (#363)"},
	{"channel": "gulp_gape", "real": 1.0, "game": 1.3, "reason": "surface gulp (#364)"},
	{"channel": "pre_action_hold_s", "real": 0.0, "game": 0.2, "reason": "contrast hold (#365)"},
	{"channel": "tail_recoil", "real": 1.0, "game": 1.25, "reason": "big-tail pull (#371/#250)"},
	{"channel": "hypoxia_opercula", "real": 1.0, "game": 1.5, "reason": "keeper-readable (#372)"},
	{"channel": "sickness_list", "real": 1.0, "game": 1.2, "reason": "listing steeper (#373)"},
]


static func is_anchor(channel: String) -> bool:
	return DO_NOT_EXAGGERATE.has(channel)


# #368: 0% macro, ~15% default, ~30% wide — scales how much of the (k−1) we keep.
static func distance_mix(ppu: float) -> float:
	# High ppu = macro (close / zoomed); low ppu = wide.
	if ppu >= 40.0:
		return 0.0
	if ppu >= 18.0:
		return lerpf(0.15, 0.0, clampf((ppu - 18.0) / 22.0, 0.0, 1.0))
	if ppu >= 8.0:
		return lerpf(0.30, 0.15, clampf((ppu - 8.0) / 10.0, 0.0, 1.0))
	return 0.30


# #359 / #368 / #369: legibility gain for a named key channel.
static func gain(channel: String, amplitude_units: float, ppu: float,
		dance_blend: float = 0.0, target_px: float = 2.0) -> float:
	if is_anchor(channel):
		return 1.0
	var cap: float = lerpf(CAP, MUSIC_CAP, clampf(dance_blend, 0.0, 1.0))
	var raw: float = MotionLod.legibility_gain(amplitude_units, ppu, target_px, cap)
	var mix: float = distance_mix(ppu)
	# Apply only the exaggerated portion, scaled by distance mix.
	return 1.0 + (raw - 1.0) * mix * MotionLod.exaggeration_scale()


static func ppu_for(f: Fish, cam: Camera3D = null, viewport_h: float = 576.0) -> float:
	if cam == null:
		var ml: MainLoop = Engine.get_main_loop()
		if ml is SceneTree:
			var vp: Viewport = (ml as SceneTree).root
			if vp != null:
				cam = vp.get_camera_3d()
				viewport_h = float(vp.get_visible_rect().size.y)
	if cam == null:
		return 22.0
	return MotionLod.px_per_unit(cam, f.global_position, viewport_h)


static func dance_blend_of(f: Fish) -> float:
	if f == null:
		return 0.0
	var mm: Variant = f.get("_music_mods_cache")
	if mm is Dictionary:
		return float((mm as Dictionary).get("dance_blend", 0.0))
	return 0.0


# #361
static func display_fin_mult(intensity: float) -> float:
	return lerpf(1.0, 1.2, clampf(intensity, 0.0, 1.0))


static func display_hold_mult(intensity: float) -> float:
	return lerpf(1.0, 1.5, clampf(intensity, 0.0, 1.0))


# #363
static func clamp_fin_scale(stress: float, spooked: float) -> float:
	var t: float = clampf(maxf(stress - 0.45, 0.0) / 0.55 + spooked * 0.5, 0.0, 1.0)
	return lerpf(1.0, 0.6, t)


static func clamp_darken(stress: float, spooked: float) -> float:
	var t: float = clampf(maxf(stress - 0.45, 0.0) / 0.55 + spooked * 0.4, 0.0, 1.0)
	return t * 0.18


# #364
static func gulp_gape_mult(at_surface: bool) -> float:
	return 1.3 if at_surface else 1.0


# #365: stillness window before a big action (seconds).
static func pre_action_hold_seconds() -> float:
	return 0.2


# #371
static func tail_recoil_mult(finnage: float) -> float:
	return lerpf(1.0, 1.25, clampf((finnage - 1.0) / 0.8, 0.0, 1.0))


# #372
static func hypoxia_opercula_mult(o2: float) -> float:
	if o2 >= 0.55:
		return 1.0
	return lerpf(1.5, 1.0, clampf(o2 / 0.55, 0.0, 1.0))


static func hypoxia_gape(o2: float) -> float:
	if o2 >= 0.45:
		return 0.0
	return lerpf(0.55, 0.0, clampf(o2 / 0.45, 0.0, 1.0))


# #373
static func sickness_list_mult(sick: float) -> float:
	return lerpf(1.0, 1.2, clampf(sick, 0.0, 1.0))


# #366: only exaggerate if the region event budget allows (shares #175).
static func region_allows(pos: Vector3, kind: StringName = &"exaggeration") -> bool:
	return MotionStaging.begin_big_event(pos, kind, 0.8)


static func ledger() -> Array[Dictionary]:
	return LEDGER
