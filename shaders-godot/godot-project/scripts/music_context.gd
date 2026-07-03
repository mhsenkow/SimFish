# Unified musical clock + analysis snapshot for choreography and visuals.
extends Node

const _FAUNA_NEUTRAL: Dictionary = {
	"speed": 1.0, "wander": 1.0, "home_radius": 1.0, "home_pull": 1.0,
	"tightness": 1.0, "accel": 1.0, "turn": 1.0, "dart_chance": 0.0,
	"beat_dart": false, "wander_refresh": 1.0, "home_drift": 1.0,
	"wander_amp": 1.0, "sweep": 0.0, "vertical": 0.0, "beat_phase": 0.0,
	"scale": 1.0, "move": "sweep", "formation": "scatter",
	"anticipation": 0.0, "drop_tension": 0.0, "dance_blend": 0.0,
	"dance_bank": 0.0, "soloist": false, "participating": true,
}

var _ctx: Dictionary = {
	"source": "none", "active": false, "tempo": 120.0,
	"beat_phase": 0.0, "bar_phase": 0.0, "downbeat": false, "bar_count": 0,
	"phrase_state": "verse", "phrase_progress": 0.0, "phrase_bars_left": 0,
	"section": "verse", "key": 0, "mode": "major", "genre": "pop", "mood": "neutral",
	"energy": 0.0, "energy_env": 0.0, "bass": 0.0, "mid": 0.0, "high": 0.0,
	"beat": 0.0, "valence": 0.5, "arousal": 0.5, "danceability": 0.5,
	"swing": 0.0, "humanize": 0.0, "confidence": 0.0, "onsets": [],
	"move": "sweep", "formation": "scatter", "drop_flash": 0.0,
	"centroid": 0.5, "brightness": 0.5, "timbre_sharp": 0.5,
}

func _main_scene() -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).current_scene
	return null


func _world_node() -> Node:
	var scene: Node = _main_scene()
	if scene == null:
		return null
	return scene.get_node_or_null("SubViewport/World")


var _dance_blend: float = 0.0
var _drop_tension: float = 0.0
var _drop_flash: float = 0.0
var _current_move: String = "sweep"
var _current_formation: String = "scatter"
var _last_phrase_state: String = ""
var _phrase_epoch: int = 0
var _drop_pulse: bool = false
var _conduct_until: float = 0.0
var _conduct_move: String = ""
var _palette_smooth: Dictionary = {"hue": 0.0, "sat": 1.0, "warmth": 0.0, "val": 1.0}
var _tank_mood_overlay: Dictionary = {}
var _shimmer_smooth: float = 0.0
var _conduct_formation: String = ""
var _prev_formation: String = "scatter"
var _formation_morph: float = 1.0
var _overhead_view: bool = false
var _life_emphasis: Dictionary = {}
var _bow_blend: float = 0.0
var _track_was_active: bool = false
var _spark_calm: float = 0.0
var _spark_liturgy: String = ""


func _ready() -> void:
	add_to_group("music_context")
	process_priority = -80
	set_process(true)


func _process(dt: float) -> void:
	_refresh(dt)


func get_context() -> Dictionary:
	return _ctx.duplicate()


# A compact "what the game understands about the song right now" snapshot.
# Pure read of already-computed signals — safe to call cheaply, e.g. when
# building a fish/Guardian thought, or to drive an ambient mood nudge.
func now_playing() -> Dictionary:
	return {
		"active": bool(_ctx.active),
		"source": String(_ctx.source),
		"mood": String(_ctx.mood),
		"valence": float(_ctx.valence),
		"arousal": float(_ctx.get("arousal", 0.5)),
		"energy": float(_ctx.energy_env),
		"tempo": float(_ctx.tempo),
		"mode": String(_ctx.mode),
		"genre": String(_ctx.genre),
		"section": String(_ctx.section),
		"descriptor": describe_now_playing(),
	}


# One short, grounded phrase — what a fish or the Guardian could "say" about the
# music. Empty when nothing is playing (the honest default).
func describe_now_playing() -> String:
	if not bool(_ctx.active):
		return ""
	var tempo: float = float(_ctx.tempo)
	var feel: String = "slow" if tempo < 80.0 else (
		"steady" if tempo < 110.0 else ("upbeat" if tempo < 140.0 else "driving"))
	return "a %s, %s %s-key song" % [feel, String(_ctx.mood), String(_ctx.mode)]


# Map the raw features into valence (sad↔happy), arousal (calm↔energetic), and a
# mood label. Smoothed so the read is stable, not jittery frame-to-frame.
func _derive_understanding() -> void:
	var mode_term: float = 0.18 if String(_ctx.mode) == "major" else -0.18
	var bright: float = float(_ctx.brightness)
	var tempo_norm: float = clampf((float(_ctx.tempo) - 60.0) / 120.0, 0.0, 1.0)
	var energy: float = float(_ctx.energy_env)
	var onset_density: float = 0.0
	for o in _ctx.onsets:
		if o is Dictionary:
			onset_density += float(o.get("strength", 0.0))
	onset_density = clampf(onset_density / 3.0, 0.0, 1.0)
	var valence_target: float = clampf(
		0.5 + mode_term + (bright - 0.5) * 0.30 + (tempo_norm - 0.45) * 0.12, 0.0, 1.0)
	var arousal_target: float = clampf(
		energy * 0.5 + tempo_norm * 0.3 + onset_density * 0.2, 0.0, 1.0)
	_ctx.valence = lerpf(float(_ctx.valence), valence_target, 0.1)
	_ctx.arousal = lerpf(float(_ctx.get("arousal", 0.5)), arousal_target, 0.1)
	_ctx.mood = _mood_label(float(_ctx.valence), float(_ctx.arousal))


func _mood_label(v: float, a: float) -> String:
	if v > 0.58:
		if a > 0.66:
			return "triumphant"
		return "joyful" if a > 0.4 else "tender"
	if v < 0.42:
		return "tense" if a > 0.55 else "melancholy"
	return "bright" if a > 0.5 else "calm"


func get_clock() -> Dictionary:
	return {
		"beat_phase": float(_ctx.beat_phase),
		"bar_phase": float(_ctx.bar_phase),
		"downbeat": bool(_ctx.downbeat),
		"phrase_state": String(_ctx.phrase_state),
		"tempo": float(_ctx.tempo),
	}


func is_active() -> bool:
	return bool(_ctx.active)


func set_spark_overlay(calm: float, liturgy: String = "") -> void:
	_spark_calm = clampf(calm, 0.0, 1.0)
	if liturgy != "":
		_spark_liturgy = liturgy


func spark_liturgy() -> String:
	return _spark_liturgy


func source_name() -> String:
	return String(_ctx.source)


func conduct(move: String, formation: String = "") -> void:
	_conduct_move = move
	_conduct_formation = formation if not formation.is_empty() else _current_formation
	_conduct_until = 6.0
	_current_move = move
	_current_formation = _conduct_formation
	_ctx.move = move
	_ctx.formation = _conduct_formation


func on_life_event(instance_id: int) -> void:
	if not bool(_ctx.active):
		return
	if bool(_ctx.downbeat) or float(_ctx.beat_phase) < 0.18 or float(_ctx.beat_phase) > 0.92:
		_life_emphasis[instance_id] = 1.35


func life_emphasis(instance_id: int) -> float:
	var v: float = float(_life_emphasis.get(instance_id, 1.0))
	if v > 1.01:
		_life_emphasis[instance_id] = maxf(1.0, v - 0.02)
	return v


func fauna_behavior_mods(instance_id: int, traits: Dictionary = {}) -> Dictionary:
	if not _should_dance():
		return _FAUNA_NEUTRAL.duplicate()
	if not _fish_participates(instance_id):
		return _participation_neutral(instance_id)

	var swim_pattern: String = String(traits.get("swim_pattern", "school"))
	var lead_score: float = float(traits.get("lead_score", 0.0))
	var boldness: float = float(traits.get("boldness", 0.5))
	var calm: float = float(traits.get("calm", 0.5))
	var gluttony: float = float(traits.get("gluttony", 0.5))

	var i: float = _dance_intensity() * _tank_health_mult()
	var confidence: float = clampf(float(_ctx.confidence), 0.0, 1.0)
	if confidence < 0.38:
		i = minf(i, 0.28)
	var role: Dictionary = MusicChoreography.assign_music_role(traits, instance_id)
	i *= MusicChoreography.cast_emphasis_for_genre(_resolved_genre(), role)
	var showiness: float = _showiness()
	var arc: float = MusicChoreography.arc_intensity(String(_ctx.phrase_state), float(_ctx.phrase_progress))
	var life_boost: float = life_emphasis(instance_id)
	var band_drive: float = MusicChoreography.role_band_drive(
		role, float(_ctx.bass), float(_ctx.mid), float(_ctx.high))
	var bass: float = maxf(float(_ctx.bass) * band_drive, 0.12)
	var mid: float = maxf(float(_ctx.mid), 0.10)
	var high: float = maxf(float(_ctx.high), 0.08)
	var energy: float = maxf(float(_ctx.energy) * band_drive, 0.18) * arc * life_boost
	var dance: float = float(_ctx.danceability)
	var genre_profile: Dictionary = MusicChoreography.profile_for_genre(_resolved_genre())
	var tempo_scale: float = float(genre_profile.get("tempo_scale", 1.0))
	var tempo_factor: float = clampf(float(_ctx.tempo) / 120.0, 0.55, 1.65) * tempo_scale

	var species_mods: Dictionary = MusicChoreography.species_modifiers(swim_pattern)
	var persona: Dictionary = MusicChoreography.personality_modifiers(boldness, calm, gluttony)
	lead_score = clampf(lead_score + float(persona.get("solo_bias", 0.0)), 0.0, 1.0)

	var global_beat: float = float(_ctx.beat_phase)
	var latency_ms: float = _effective_latency_ms()
	var latency_beats: float = latency_ms / 60000.0 * float(_ctx.tempo)
	global_beat = fposmod(global_beat + latency_beats, 1.0)
	var fish_phase: float = fposmod(global_beat + float(instance_id % 997) * 0.013, 1.0)
	var swung_phase: float = MusicChoreography.swing_offset(fish_phase, float(_ctx.swing))
	var anticipation: float = MusicChoreography.beat_anticipation(swung_phase)
	var eased_energy: float = MusicChoreography.ease_in_out_cubic(energy)

	var groove: float = clampf(bass * 0.5 + mid * 0.35 + energy * 0.4 + dance * 0.3, 0.0, 1.0)
	groove = maxf(groove, 0.22)

	var phrase: String = String(_ctx.phrase_state)
	var drop_t: float = _drop_tension
	var sweep_base: float = float(genre_profile.get("sweep", 0.55)) * float(species_mods.get("sweep", 1.0)) * float(persona.get("sweep", 1.0))
	var vert_base: float = float(genre_profile.get("vertical", 0.35)) * float(species_mods.get("vertical", 1.0))

	var tightness_bonus: float = 0.0
	var vert_bonus: float = 0.0
	var speed_bonus: float = 0.0

	var choir: int = int(role.get("choir", MusicChoreography.choir_for_instance(instance_id)))
	var choir_on: bool = MusicChoreography.choir_active(choir, float(_ctx.bar_phase))
	var soloist: bool = MusicChoreography.is_soloist(lead_score, phrase) \
		or String(role.get("role", "")) == "soloist"
	var corps_member: bool = String(role.get("role", "")) == "corps" \
		or swim_pattern in ["school", "shoal"]
	var principal: bool = swim_pattern in ["hover", "cruise", "meander"] \
		or String(role.get("role", "")) == "soloist"

	var timbre_sharp: float = float(_ctx.get("timbre_sharp", 0.5))
	var wander_jitter: float = lerpf(0.85, 1.35, timbre_sharp)
	var sweep_timbre: float = lerpf(0.88, 1.18, timbre_sharp)
	var show: float = lerpf(0.22, 0.78, showiness)

	if corps_member and not soloist:
		tightness_bonus += 0.18
		sweep_base *= 0.88
	elif principal and not corps_member:
		sweep_base *= 1.14
		wander_jitter *= 1.08

	match phrase:
		"build":
			tightness_bonus = drop_t * 0.55
			vert_bonus = drop_t * 0.82
			speed_bonus = drop_t * 0.35
		"drop":
			tightness_bonus = -0.25
			speed_bonus = 0.45
			sweep_base = maxf(sweep_base, 0.92)
		"breakdown":
			sweep_base *= 0.42
			vert_base *= 0.5

	var leader_lag: float = MusicChoreography.section_leader_lag(instance_id)
	var ensemble_dim: float = 1.0
	if phrase == "chorus" and not soloist:
		ensemble_dim = 0.72

	var dance_freeze: float = 0.0
	if phrase == "breakdown" and float(_ctx.energy_env) < 0.28:
		dance_freeze = clampf(1.0 - float(_ctx.energy_env) * 3.6, 0.0, 1.0)

	var sweep_floor: float = 0.14 if float(_ctx.energy_env) > 0.18 else 0.08
	var sweep: float = clampf(
		(sweep_base + groove * 0.38 + anticipation * 0.38) * i * _dance_blend * show * arc * sweep_timbre,
		sweep_floor, 0.88)
	var vertical: float = clampf(
		(vert_base + mid * 0.2 + high * 0.28 + vert_bonus) * i * _dance_blend
		+ MusicChoreography.column_vertical_bias(role, float(_ctx.energy_env), float(_ctx.brightness)),
		0.0, 1.0)
	if soloist:
		sweep = maxf(sweep, 0.78)
		vertical = maxf(vertical, 0.62)

	var beat_dart: bool = anticipation > 0.84 or (bool(_ctx.downbeat) and phrase == "drop" and drop_t > 0.55)
	var dance_bank: float = clampf(sweep * anticipation * show * 0.85, 0.0, 0.55)
	if float(role.get("improv", 0.5)) > 0.72:
		dance_bank = minf(dance_bank * 1.18, 0.62)

	var loco_ctx: Dictionary = _ctx.duplicate()
	loco_ctx["instance_id"] = instance_id
	loco_ctx["move"] = _current_move
	var loco: Dictionary = MusicChoreography.universal_locomotion_mods(loco_ctx, role, i * _dance_blend * show)
	var loco_scale: float = float(loco.get("scale_pulse", 0.0))
	var motion_trail: float = clampf(sweep * float(_ctx.energy) * 0.55, 0.0, 0.42) if sweep > 0.62 else 0.0
	if _overhead_view:
		motion_trail = maxf(motion_trail, clampf(sweep * float(_ctx.energy) * 0.82, 0.0, 0.75))

	return {
		"speed": (1.0 + groove * 1.25 * i + anticipation * 0.65 * i + speed_bonus * i) / tempo_factor * float(species_mods.get("speed", 1.0)),
		"wander": (1.0 + mid * 1.15 * i + eased_energy * 0.45 * i) * float(species_mods.get("wander", 1.0)) * wander_jitter,
		"wander_amp": 1.0 + groove * 1.05 * i + anticipation * 0.28 * i,
		"home_radius": 1.0 + energy * 2.8 * i + dance * 1.1 * i - drop_t * 0.35 * i,
		"home_pull": maxf(0.05, (1.0 - groove * 0.72 * i - drop_t * 0.25 * i)
			* lerpf(1.0, 0.38, clampf(sweep, 0.0, 1.0))),
		"tightness": maxf(0.12, (1.0 - mid * 0.62 * i - tightness_bonus * i) * float(persona.get("tightness", 1.0))),
		"accel": (1.0 + bass * 1.15 * i + anticipation * 0.62 * i) / sqrt(tempo_factor),
		"turn": 1.0 + high * 0.85 * i + anticipation * 0.42 * i + dance_bank * 0.35,
		"dart_chance": (groove * 0.38 * i + anticipation * 0.22 * i) * float(persona.get("dart_chance", 1.0)),
		"sweep": sweep,
		"vertical": vertical,
		"beat_phase": swung_phase * TAU + float(instance_id % 997) * 0.11,
		"beat_dart": beat_dart,
		"wander_refresh": 1.0 + groove * 2.8 * i,
		"home_drift": 1.0 + groove * 3.2 * i,
		"scale": (_scale_pulse(instance_id, anticipation) + loco_scale) * life_boost,
		"move": _current_move,
		"formation": _current_formation,
		"choir_active": choir_on or soloist,
		"soloist": soloist,
		"anticipation": anticipation,
		"drop_tension": drop_t,
		"dance_blend": _dance_blend,
		"dance_bank": dance_bank,
		"genre": String(_ctx.genre),
		"participating": true,
		"music_role": role,
		"wag_freq_target": float(loco.get("wag_freq_target", 0.0)),
		"tail_amp_extra": float(loco.get("tail_amp_extra", 0.0)),
		"pec_flutter": float(loco.get("pec_flutter", 0.0)),
		"downbeat_pulse": float(loco.get("downbeat_pulse", 0.0)),
		"kick_thump": float(loco.get("kick_thump", 0.0)),
		"snare_flick": float(loco.get("snare_flick", 0.0)),
		"glide_hold": float(loco.get("glide_hold", 0.0)),
		"fin_flare": float(loco.get("fin_flare", 0.0)),
		"wave_tail": float(loco.get("wave_tail", 0.0)),
		"eye_flash": float(loco.get("eye_flash", 0.0)),
		"leader_lag": leader_lag,
		"ensemble_dim": ensemble_dim,
		"dance_freeze": dance_freeze,
		"bow": _bow_blend,
		"motion_trail": motion_trail,
		"bass_radius": TopdownMotion.bass_formation_radius(bass),
		"treble_shimmer": TopdownMotion.treble_edge_shimmer(high),
		"swing_sway": clampf(float(_ctx.swing) * groove, 0.0, 1.0),
		"overhead_view": _overhead_view,
	}


func compute_dance_target(
	instance_id: int,
	mods: Dictionary,
	tank_half_w: float,
	tank_half_d: float,
	y_min: float,
	y_max: float,
	home_y: float,
	camera_yaw: float = 0.0,
	fish_count: int = 24,
) -> Vector3:
	var role: Dictionary = mods.get("music_role", {})
	var mouth: int = int(role.get("mouth", 0))
	var move: String = String(mods.get("move", "sweep"))
	var formation: String = String(mods.get("formation", _current_formation))
	if _formation_morph < 0.995 and _prev_formation != formation:
		var slots: int = TopdownMotion.formation_slot_count(fish_count)
		var slot: int = instance_id % slots
		var y_stage: float = MusicChoreography.depth_stage_y(
			String(_ctx.phrase_state), float(_ctx.phrase_progress),
			y_min, y_max, home_y, float(mods.get("vertical", 0.0)), mouth)
		var br: float = float(mods.get("bass_radius", 1.0))
		var hw: float = tank_half_w * 0.96 * br
		var hd: float = tank_half_d * 0.96 * br
		var morphed: Vector3 = MusicChoreography.formation_offset(
			_prev_formation, slot, slots, hw, hd, y_stage, false, fish_count).lerp(
			MusicChoreography.formation_offset(
				formation, slot, slots, hw, hd, y_stage, false, fish_count),
			clampf(_formation_morph, 0.0, 1.0))
		return MusicChoreography.rotate_xz(morphed, camera_yaw)
	return MusicChoreography.dance_target(
		move,
		instance_id,
		float(mods.get("beat_phase", 0.0)) / TAU,
		float(_ctx.bar_phase),
		String(_ctx.phrase_state),
		float(_ctx.phrase_progress),
		formation,
		bool(mods.get("choir_active", true)),
		bool(mods.get("soloist", false)),
		tank_half_w,
		tank_half_d,
		y_min,
		y_max,
		home_y,
		float(mods.get("sweep", 0.0)),
		float(mods.get("vertical", 0.0)),
		float(mods.get("drop_tension", 0.0)),
		camera_yaw,
		_drop_flash,
		role,
		float(mods.get("leader_lag", 0.0)),
		float(mods.get("ensemble_dim", 1.0)),
		mouth,
		int(_ctx.bar_count),
		fish_count,
		_overhead_view,
		float(mods.get("bass_radius", 1.0)),
		float(mods.get("treble_shimmer", 0.0)),
	)


func visual_mix() -> Dictionary:
	if not bool(_ctx.active):
		return {}
	var i: float = _dance_intensity() * _dance_blend
	var color_gain: float = 0.42
	if "music_sync_intensity" in TankConfig:
		color_gain *= clampf(float(TankConfig.music_sync_intensity), 0.0, 1.0)
	# Slow envelope for color — never raw bass/beat (avoids strobe on kicks).
	var env: float = float(_ctx.energy_env) * i * color_gain
	var pal: Dictionary = MusicChoreography.mood_palette(
		float(_ctx.valence), String(_ctx.mode), env, int(_ctx.key))
	pal = _gentle_palette(pal)
	var light_boost: float = float(_ctx.energy_env) * 0.14 * i
	if _drop_flash > 0.25:
		light_boost += _drop_flash * 0.18
	var plant_boost: float = float(_ctx.energy_env) * 0.22 * i
	var caustic_boost: float = float(_ctx.energy_env) * 0.15 * i + _drop_flash * 0.12
	return {
		"light_mul": 1.0 + light_boost,
		"light_warmth": clampf((float(_ctx.valence) - 0.4) * 0.22, -0.1, 0.28) * color_gain,
		"plant_sway": 1.0 + plant_boost,
		"caustic_mul": 1.0 + caustic_boost,
		"bubble_burst": _drop_flash > 0.55,
		"bubble_rate": 1.0 + float(_ctx.energy_env) * 0.65 * i + _drop_flash * 0.45,
		"palette": pal,
		"shimmer": clampf(float(_ctx.energy_env) * 0.22 + _drop_flash * 0.12, 0.0, 0.28) * i * color_gain,
		"drop_flash": _drop_flash,
	}


static func _gentle_palette(pal: Dictionary) -> Dictionary:
	return {
		"hue": float(pal.get("hue", 0.0)) * 0.5,
		"sat": lerpf(1.0, float(pal.get("sat", 1.0)), 0.28),
		"warmth": float(pal.get("warmth", 0.0)) * 0.45,
		"val": lerpf(1.0, float(pal.get("val", 1.0)), 0.18),
	}


func light_fixture_mul() -> float:
	var mix: Dictionary = visual_mix()
	return float(mix.get("light_mul", 1.0))


func light_beam_warmth_mix() -> float:
	var mix: Dictionary = visual_mix()
	return float(mix.get("light_warmth", 0.0))


func plant_sway_mult() -> float:
	if String(_ctx.source) == "external" and not TankConfig.music_sync_plants:
		return 1.0
	var mix: Dictionary = visual_mix()
	return float(mix.get("plant_sway", 1.0))


func caustic_mul() -> float:
	var mix: Dictionary = visual_mix()
	return float(mix.get("caustic_mul", 1.0))


func palette_overlay() -> Dictionary:
	var mix: Dictionary = visual_mix()
	if mix.is_empty():
		return {"hue": 0.0, "sat": 1.0, "warmth": 0.0, "val": 1.0}
	return mix.get("palette", {})


func aquatic_shimmer() -> float:
	var mix: Dictionary = visual_mix()
	return float(mix.get("shimmer", 0.0))


func bubble_rate_mult() -> float:
	var mix: Dictionary = visual_mix()
	return float(mix.get("bubble_rate", 1.0))


func should_bubble_burst() -> bool:
	return bool(visual_mix().get("bubble_burst", false))


func _participation_neutral(instance_id: int) -> Dictionary:
	var neutral: Dictionary = _FAUNA_NEUTRAL.duplicate()
	neutral.participating = false
	neutral.beat_phase = float(instance_id % 997) * 0.11
	return neutral


func _fish_participates(instance_id: int) -> bool:
	var threshold: float = clampf(float(_ctx.energy_env) * 0.95 + 0.08, 0.12, 1.0)
	if String(_ctx.phrase_state) in ["drop", "chorus", "build"]:
		threshold = maxf(threshold, 0.55)
	var slot: float = float(instance_id % 1000) / 1000.0
	return slot < threshold


func _showiness() -> float:
	if "music_showiness" in TankConfig:
		return clampf(float(TankConfig.music_showiness), 0.0, 1.0)
	return 0.65


func _should_dance() -> bool:
	if String(_ctx.source) == "external":
		return bool(TankConfig.music_sync_fish)
	return bool(TankConfig.music_enabled)


func _dance_intensity() -> float:
	if String(_ctx.source) == "external":
		return clampf(float(TankConfig.music_sync_intensity), 0.0, 1.0)
	return clampf(float(TankConfig.music_reactivity) * 1.15, 0.0, 1.0)


func _scale_pulse(instance_id: int, anticipation: float) -> float:
	if not _should_dance():
		return 1.0
	var i: float = _dance_intensity() * _showiness()
	var wobble: float = sin(float(_ctx.bar_phase) * TAU + float(instance_id % 50) * 0.31) * 0.5 + 0.5
	return 1.0 + anticipation * 0.18 * i + wobble * float(_ctx.bass) * 0.12 * i + _drop_flash * 0.08


func _refresh(dt: float) -> void:
	var was_active: bool = bool(_ctx.active)
	var ext := _music_reactive()
	var amb := _ambient_audio()
	var ext_live: bool = ext != null and ext.has_method("is_active") and ext.is_active()
	var gen_live: bool = amb != null and _generative_live(amb)

	if ext_live:
		_populate_external(ext, dt)
	elif gen_live:
		_populate_generative(amb)
	else:
		_idle_decay(dt)

	if was_active and not bool(_ctx.active):
		_bow_blend = 1.0
	_bow_blend = maxf(0.0, _bow_blend - dt * 0.32)
	_track_was_active = bool(_ctx.active)

	_update_drop_tension(dt)
	_update_drop_flash(dt)
	_conduct_until = maxf(0.0, _conduct_until - dt)
	_update_phrase_choreography(dt)
	_update_dance_blend(dt)
	_apply_visual_uniforms(dt)
	_maybe_drop_bubbles(dt)


func _populate_generative(amb: Node) -> void:
	var status: Dictionary = amb.get_live_status() if amb.has_method("get_live_status") else {}
	var persona_key: String = String(TankConfig.music_persona) if "music_persona" in TankConfig else "none"
	var persona: Dictionary = amb.PERSONAS.get(persona_key, {}) if "PERSONAS" in amb else {}

	_ctx.source = "generative"
	_ctx.active = true
	_ctx.tempo = float(status.get("bpm", 110.0))
	_ctx.beat_phase = float(status.get("beat_phase", 0.0))
	_ctx.bar_phase = float(status.get("bar_phase", 0.0))
	_ctx.downbeat = _ctx.beat_phase < 0.06
	_ctx.bar_count = int(status.get("bar_count", 0))
	_ctx.phrase_state = String(status.get("phrase_state_name", "verse"))
	_ctx.phrase_progress = float(status.get("phrase_state_progress", 0.0))
	_ctx.phrase_bars_left = int(status.get("phrase_state_bars_left", 0))
	_ctx.section = _ctx.phrase_state
	_ctx.key = int(status.get("chord_root", 0))
	_ctx.mode = String(status.get("scale_mode", "major"))
	_ctx.swing = float(status.get("swing", persona.get("swing", 0.0)))
	_ctx.humanize = float(status.get("humanize", persona.get("humanize", 0.0)))
	_ctx.energy = clampf(float(status.get("vitality", 0.5)), 0.0, 1.0)
	_ctx.energy_env = lerpf(float(_ctx.energy_env), _ctx.energy, 0.08)
	_ctx.bass = clampf(_ctx.energy * 0.85, 0.0, 1.0)
	_ctx.mid = clampf(_ctx.energy * 0.7, 0.0, 1.0)
	_ctx.high = clampf(_ctx.energy * 0.55, 0.0, 1.0)
	_ctx.beat = maxf(0.0, cos(float(_ctx.beat_phase) * TAU) * 0.5 + 0.5) * 0.2
	_ctx.valence = 0.62 if _ctx.mode == "major" else 0.38
	_ctx.danceability = clampf(_ctx.energy * 0.75 + 0.2, 0.0, 1.0)
	_ctx.confidence = 1.0
	_ctx.onsets = []
	_ctx.genre = _genre_from_persona(persona_key, persona)
	_ctx.mood = "bright" if _ctx.mode == "major" else "moody"
	_ctx.timbre_sharp = lerpf(0.35, 0.55, float(_ctx.energy))


func _populate_external(mr: Node, dt: float) -> void:
	var drive: Dictionary = mr.get_drive() if mr.has_method("get_drive") else {}
	var clock: Dictionary = mr.get_music_clock() if mr.has_method("get_music_clock") else {}
	var analysis: Dictionary = mr.get_analysis() if mr.has_method("get_analysis") else {}
	if not analysis.is_empty():
		clock = analysis

	_ctx.source = "external"
	_ctx.active = true
	_ctx.tempo = float(drive.get("tempo", 120.0))
	_ctx.beat_phase = float(clock.get("beat_phase", drive.get("beat_phase", 0.0)))
	_ctx.bar_phase = float(clock.get("bar_phase", 0.0))
	_ctx.downbeat = bool(clock.get("downbeat", false))
	_ctx.bar_count = int(clock.get("bar_count", 0))
	var ext_phrase: String = String(clock.get("phrase_state", "verse"))
	if bool(clock.get("drop_detected", false)):
		ext_phrase = "drop"
	_ctx.phrase_state = ext_phrase
	_ctx.phrase_progress = float(clock.get("phrase_progress", _ctx.bar_phase))
	_ctx.section = _ctx.phrase_state
	_ctx.bass = float(drive.get("bass", 0.0))
	_ctx.mid = float(drive.get("mid", 0.0))
	_ctx.high = float(drive.get("high", 0.0))
	_ctx.energy = float(drive.get("energy", 0.0))
	_ctx.beat = float(drive.get("beat", 0.0))
	_ctx.danceability = float(drive.get("danceability", 0.5))
	_ctx.energy_env = lerpf(float(_ctx.energy_env), _ctx.energy, clampf(dt * 4.0, 0.0, 1.0))
	_ctx.confidence = float(clock.get("confidence", 0.65))
	_ctx.onsets = clock.get("onsets", [])
	_ctx.swing = 0.0
	_ctx.humanize = 0.0
	_ctx.key = int(clock.get("key", 0))
	_ctx.mode = String(clock.get("mode", "major" if _ctx.valence > 0.5 else "minor"))
	_ctx.centroid = float(clock.get("centroid", 0.5))
	_ctx.brightness = float(clock.get("brightness", 0.5))
	_ctx.timbre_sharp = clampf(_ctx.centroid * 0.62 + float(clock.get("rolloff", 0.5)) * 0.38, 0.0, 1.0)
	_ctx.section = String(clock.get("section", _ctx.phrase_state))
	# Fuse the raw features into a slow, stable semantic read (valence / arousal /
	# mood) the rest of the game can "understand" — cheap arithmetic, smoothed.
	_derive_understanding()
	_ctx.genre = MusicChoreography.classify_genre(
		_ctx.tempo, _ctx.energy, _ctx.danceability, _ctx.valence)

	if _ctx.confidence < 0.28:
		_ctx.phrase_state = "verse"
		_ctx.genre = "pop"


func hero_camera_bias() -> Dictionary:
	if not bool(_ctx.active):
		return {"yaw": 0.0, "pitch": 0.0, "blend": 0.0}
	var blend: float = 0.0
	if String(_ctx.phrase_state) in ["drop", "chorus"] and _drop_flash > 0.12:
		blend = clampf(_drop_flash + float(_ctx.energy) * 0.35, 0.0, 0.52)
	elif _bow_blend > 0.15:
		blend = _bow_blend * 0.42
	return {"yaw": -0.14, "pitch": 0.09, "blend": blend}


func _idle_decay(dt: float) -> void:
	_ctx.source = "none"
	_ctx.active = false
	for key in ["bass", "mid", "high", "energy", "beat", "energy_env"]:
		_ctx[key] = maxf(0.0, float(_ctx[key]) - dt * 1.6)
	_drop_tension = lerpf(_drop_tension, 0.0, clampf(dt * 3.0, 0.0, 1.0))


func _update_drop_tension(dt: float) -> void:
	var target: float = 0.0
	match String(_ctx.phrase_state):
		"build":
			target = clampf(float(_ctx.phrase_progress) * 1.05, 0.0, 1.0)
		"drop":
			target = 0.0
	_drop_tension = lerpf(_drop_tension, target, clampf(dt * 5.0, 0.0, 1.0))
	_ctx.drop_tension = _drop_tension


func _update_drop_flash(dt: float) -> void:
	if _drop_pulse:
		_drop_flash = maxf(_drop_flash, 0.38)
		_drop_pulse = false
	elif String(_ctx.phrase_state) == "drop" and bool(_ctx.downbeat):
		_drop_flash = maxf(_drop_flash, 0.22)
	if bool(_ctx.downbeat) and _overhead_view and bool(_ctx.active):
		_pulse_overhead_beat()
	_drop_flash = lerpf(_drop_flash, 0.0, clampf(dt * 2.0, 0.0, 1.0))
	_ctx.drop_flash = _drop_flash


func _pulse_overhead_beat() -> void:
	var world: Node = _world_node()
	if world == null:
		return
	var sim: Node = world.get_node_or_null("SimDriver")
	if sim != null and sim.has_method("pulse_sync_turn"):
		sim.pulse_sync_turn(Vector3(1, 0, 0), Vector3.ZERO)
	if world.has_method("spawn_glass_tap_ripples"):
		var wh: float = float(world.get("WATER_HEIGHT")) if world.get("WATER_HEIGHT") != null else 6.5
		world.spawn_glass_tap_ripples(Vector3(0.0, wh, 0.0))


func notify_drop_pulse() -> void:
	_drop_pulse = true


func _update_phrase_choreography(dt: float = 0.016) -> void:
	if not bool(_ctx.active):
		return
	_overhead_view = TopdownMotion.pond_active
	var main_node: Node = _main_scene()
	if not _overhead_view and main_node != null:
		_overhead_view = TopdownMotion.is_overhead(main_node)
	if _conduct_until > 0.0 and not _conduct_move.is_empty():
		_current_move = _conduct_move
		if not _conduct_formation.is_empty():
			_current_formation = _conduct_formation
		_ctx.move = _current_move
		_ctx.formation = _current_formation
		return
	var phrase: String = String(_ctx.phrase_state)
	if phrase != _last_phrase_state:
		_prev_formation = _current_formation
		_formation_morph = 0.0
		_last_phrase_state = phrase
		_phrase_epoch += 1
		if float(_ctx.confidence) < 0.42:
			_current_move = "breathe"
			_current_formation = "scatter"
		else:
			var geo: TopdownMotion.KeyGeometry = TopdownMotion.key_geometry_bias(
				int(_ctx.key), String(_ctx.mode))
			_current_move = MusicChoreography.pick_move(
				phrase, float(_ctx.energy), String(_ctx.genre), _phrase_epoch, _overhead_view)
			_current_formation = MusicChoreography.pick_formation(
				phrase, String(_ctx.genre), _current_move, _phrase_epoch,
				_overhead_view, float(_ctx.valence))
			if geo.tightness > 1.05 and _current_formation == "scatter":
				_current_formation = "circle"
			if phrase == "drop":
				_current_move = "radial_bloom" if _overhead_view else "starburst"
				_current_formation = "scatter"
			elif phrase == "build" and _overhead_view:
				_current_move = "spiral"
				_current_formation = "ring"
	else:
		var target_morph: float = TopdownMotion.formation_morph_blend(
			int(_ctx.phrase_bars_left), float(_ctx.bar_phase), float(_ctx.phrase_progress))
		_formation_morph = lerpf(_formation_morph, target_morph, minf(1.0, dt * 5.5))
	_ctx.move = _current_move
	_ctx.formation = _current_formation


func _update_dance_blend(dt: float) -> void:
	var baseline: float = 0.14 if bool(_ctx.active) and _should_dance() else 0.0
	var target: float = baseline
	if bool(_ctx.active) and _should_dance():
		if float(_ctx.confidence) >= 0.42:
			target = 1.0
		else:
			target = maxf(baseline, 0.22)
	var rate: float = 1.6 if target > _dance_blend else 1.2
	var world: Node = _world_node()
	var sim_hush: Node = world.get_node_or_null("SimDriver") if world != null else null
	if sim_hush != null and sim_hush.has_method("daylight") and float(sim_hush.daylight()) < 0.28:
		target *= 0.48
	_dance_blend = lerpf(_dance_blend, target, clampf(dt * rate, 0.0, 1.0))
	if baseline > 0.0:
		_dance_blend = maxf(_dance_blend, baseline * 0.85)


func set_tank_mood_overlay(overlay: Dictionary) -> void:
	_tank_mood_overlay = overlay if overlay is Dictionary else {}


func _apply_visual_uniforms(dt: float = 0.016) -> void:
	if not bool(_ctx.active):
		if _tank_mood_overlay.is_empty():
			return
		var pal_night: Dictionary = _tank_mood_overlay.duplicate()
		VoxelMat.apply_music_sync_overlay(pal_night, 0.08)
		return
	var mix: Dictionary = visual_mix()
	if mix.is_empty():
		return
	var intensity: float = _dance_intensity() * _dance_blend
	var shimmer_target: float = float(mix.get("shimmer", 0.0))
	var smooth_rate: float = clampf(dt * 1.8, 0.0, 1.0)
	_shimmer_smooth = lerpf(_shimmer_smooth, shimmer_target, smooth_rate)
	if not bool(TankConfig.music_sync_color):
		_palette_smooth = {"hue": 0.0, "sat": 1.0, "warmth": 0.0, "val": 1.0}
		_shimmer_smooth = lerpf(_shimmer_smooth, 0.0, smooth_rate)
		if intensity < 0.04 and _shimmer_smooth < 0.01 and _tank_mood_overlay.is_empty():
			return
		var pal_off: Dictionary = _palette_smooth.duplicate()
		if not _tank_mood_overlay.is_empty():
			for key in ["hue", "sat", "warmth", "val"]:
				pal_off[key] = float(pal_off.get(key, 0.0)) + float(_tank_mood_overlay.get(key, 0.0))
		VoxelMat.apply_music_sync_overlay(pal_off, _shimmer_smooth)
		return
	var target_pal: Dictionary = mix.get("palette", {})
	for key in ["hue", "sat", "warmth", "val"]:
		var tv: float = float(target_pal.get(key, _palette_smooth.get(key, 0.0)))
		var cv: float = float(_palette_smooth.get(key, tv))
		_palette_smooth[key] = lerpf(cv, tv, smooth_rate)
	if intensity < 0.04 and _shimmer_smooth < 0.01 and _tank_mood_overlay.is_empty():
		return
	var pal: Dictionary = _palette_smooth.duplicate()
	if not _tank_mood_overlay.is_empty():
		for key in ["hue", "sat", "warmth", "val"]:
			pal[key] = float(pal.get(key, 0.0)) + float(_tank_mood_overlay.get(key, 0.0))
	VoxelMat.apply_music_sync_overlay(pal, _shimmer_smooth)


func _maybe_drop_bubbles(_dt: float) -> void:
	if not should_bubble_burst():
		return
	if not TankConfig.music_sync_bubbles and String(_ctx.source) == "external":
		return
	if not bool(TankConfig.music_enabled) and String(_ctx.source) == "generative":
		return
	var world: Node = _world_node()
	if world == null:
		return
	var visuals: Node = world.get_node_or_null("AquariumVisuals")
	if visuals == null or not visuals.has_method("spawn_snail_bubble"):
		return
	var half_w: float = 4.0
	if "TANK_HALF_W" in world:
		half_w = float(world.TANK_HALF_W)
	var water_y: float = 5.0
	if "WATER_HEIGHT" in world:
		water_y = float(world.WATER_HEIGHT)
	for _i in 4:
		var pos := Vector3(randf_range(-half_w * 0.8, half_w * 0.8), water_y - 0.15, randf_range(-2.5, 2.5))
		visuals.spawn_snail_bubble(pos)


func _genre_from_persona(persona_key: String, persona: Dictionary) -> String:
	match persona_key:
		"lofi": return "lofi"
		"abgt": return "trance"
		"dub": return "ambient"
		"monk": return "orchestral"
	if persona.has("bpm_mul"):
		var mul: float = float(persona.get("bpm_mul", 1.0))
		if mul < 0.75:
			return "lofi"
		if mul > 1.05:
			return "trance"
	var style: String = String(TankConfig.music_style) if "music_style" in TankConfig else "hybrid"
	match style:
		"ambient": return "ambient"
		"trance": return "trance"
	return "pop"


func _generative_live(_amb: Node) -> bool:
	return bool(TankConfig.music_enabled)


func _resolved_genre() -> String:
	if "music_dance_style" in TankConfig:
		var locked: String = MusicChoreography.dance_style_genre(String(TankConfig.music_dance_style))
		if not locked.is_empty():
			return locked
	return String(_ctx.genre)


func _tank_health_mult() -> float:
	var world: Node = _world_node()
	if world == null or world.get("sim") == null:
		return 1.0
	var sim: Node = world.sim
	if sim == null:
		return 1.0
	var o2: float = float(sim.dissolved_o2) if "dissolved_o2" in sim else 0.85
	var stability: float = float(sim.stability) if "stability" in sim else 0.7
	var bloom: float = float(sim.bloom_intensity) if "bloom_intensity" in sim else 0.0
	var health: float = clampf(o2 * 0.45 + stability * 0.4 + (1.0 - bloom) * 0.15, 0.0, 1.0)
	var mult: float = lerpf(0.55, 1.08, health)
	match _spark_liturgy:
		"vespers":
			mult *= lerpf(1.0, 0.42, _spark_calm)
		"elegy":
			mult *= 0.62
		"hymn":
			mult *= 1.12
	return mult


func _music_reactive() -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).get_first_node_in_group("music_reactive")
	return null


func _effective_latency_ms() -> float:
	if "music_sync_latency_ms" in TankConfig:
		var base: float = float(TankConfig.music_sync_latency_ms)
		var mr := _music_reactive()
		if mr != null and mr.has_method("session_latency_ms"):
			return float(mr.session_latency_ms())
		return base
	return 80.0


func _ambient_audio() -> Node:
	var scene: Node = _main_scene()
	if scene == null:
		return null
	return scene.get_node_or_null("AmbientAudio")
