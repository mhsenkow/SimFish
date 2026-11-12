extends SceneTree

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_music_listening")
	var cfg: Node = root.get_node("TankConfig")
	cfg.capture_mode = true
	cfg.reset_to_defaults()
	var ambient: Node = load("res://scripts/ambient_audio.gd").new()
	ambient.set_process(false)
	root.add_child(ambient)
	ambient.set("_cached_beat_time", 0.25)
	ambient.set("_cached_beat_scale", 0.001)
	t.approx(ambient.call("_advance_musical_clock"), 0.25, "clock reads the accumulated beat")
	ambient.set("_cached_beat_scale", 0.002)
	t.approx(ambient.call("_advance_musical_clock"), 0.251, "tempo change does not re-time past samples")
	t.approx(ambient.get("_cached_beat_time"), 0.253, "new tempo changes only the next increment")
	var first: Dictionary = ambient.call("get_live_status")
	t.approx(first.energy, cfg.music_energy, "music energy reports musical drive rather than tank health")
	ambient.set("_cached_beat_time", 0.75)
	await process_frame
	var second: Dictionary = ambient.call("get_live_status")
	t.check(first.beat_phase != second.beat_phase, "beat updates within the same bar")
	ambient.set("_cached_drop_intensity", 0.9)
	ambient.set("_cached_lofi", true)
	ambient.set("_phrase_force_state", -1)
	ambient.play_feeding_event()
	t.equals(ambient.get("_phrase_force_state"), -1, "feeding preserves the lo-fi phrase")
	cfg.music_events_enabled = false
	ambient.set("_cached_lofi", false)
	ambient.play_feeding_event()
	t.equals(ambient.get("_phrase_force_state"), -1, "disabled events cannot force a build")
	var chord_before: int = ambient.get("_chord_root")
	ambient.play_aquarium_event_extended("death")
	t.equals(ambient.get("_chord_root"), chord_before, "disabled death cues preserve harmony")
	cfg.music_events_enabled = true
	ambient.queue_free()
	await process_frame
	var mc: Node = root.get_node("MusicContext")
	mc.set_process(false)
	var context: Dictionary = mc.get("_ctx")
	context.merge({"active": true, "source": "generative", "genre": "lofi", "energy_env": 0.7,
		"energy": 0.7, "tempo": 76.0, "swing": 0.5, "confidence": 1.0}, true)
	cfg.music_reactivity = 0.0
	var neutral: Dictionary = mc.fauna_behavior_mods(1)
	t.approx(neutral.speed, 1.0, "zero reactivity cannot speed fish up at slow tempos")
	cfg.music_reactivity = 0.65
	mc.set("_dance_blend", 1.0)
	var sleeping: Dictionary = mc.fauna_behavior_mods(1, {"sleep_depth": 1.0})
	t.approx(sleeping.speed, 1.0, "sleeping fish retain their baseline speed")
	t.approx(sleeping.sweep, 0.0, "sleeping fish do not sweep to lo-fi")
	t.check(not sleeping.beat_dart, "lo-fi does not induce sudden beat darts")
	# Global sleep gate — trance/external genres also stay quiet.
	context.genre = "trance"
	context.source = "external"
	var sleep_trance: Dictionary = mc.fauna_behavior_mods(2, {"sleep_depth": 1.0})
	t.approx(sleep_trance.sweep, 0.0, "sleeping fish stay quiet on trance too")
	t.check(not bool(sleep_trance.get("participating", true)),
		"deep sleep opts out of dance participation")
	var shrimp_sleep: Dictionary = mc.fauna_behavior_mods(3, {
		"swim_pattern": "shuffle", "sleep_depth": 1.0, "stress": 0.0,
	})
	t.check(not bool(shrimp_sleep.get("participating", true)),
		"sleeping shrimp opt out of dance participation")
	t.approx(float(shrimp_sleep.get("scale", 1.0)), 1.0, "sleeping shrimp keep baseline scale")
	context.genre = "lofi"
	context.source = "generative"
	# Generative onsets unlock kick/snare locomotion accents.
	ambient = load("res://scripts/ambient_audio.gd").new()
	ambient.set_process(false)
	root.add_child(ambient)
	ambient.set("_cached_beat_time", 0.0)
	ambient.set("_swim_activity", 0.6)
	mc.call("_populate_generative", ambient, 0.016)
	var ons: Array = context.get("onsets", [])
	t.check(ons.size() >= 3, "generative path synthesizes kick/snare/hat onsets")
	if ons.size() >= 1 and ons[0] is Dictionary:
		t.check(float(ons[0].get("strength", 0.0)) > 0.2,
			"downbeat generative kick onset is audible to locomotion")
	context["swim_busy"] = 0.6
	var loco: Dictionary = MusicChoreography.universal_locomotion_mods(
		context, {"color_band": "bass", "stroke_subdiv": 1.0, "expressive": 0.7}, 0.8)
	t.check(float(loco.get("kick_thump", 0.0)) > 0.05
			or float(loco.get("downbeat_pulse", 0.0)) > 0.0,
		"generative onsets drive body accents")
	var quiet_ctx: Dictionary = context.duplicate(true)
	quiet_ctx["swim_busy"] = 0.0
	var loco_quiet: Dictionary = MusicChoreography.universal_locomotion_mods(
		quiet_ctx, {"color_band": "bass", "stroke_subdiv": 1.0, "expressive": 0.7}, 0.8)
	t.check(float(loco.get("kick_thump", 0.0)) >= float(loco_quiet.get("kick_thump", 0.0)),
		"busy tank amplifies kick accents vs quiet")
	# External clock fuses the same swim_busy lift (Spotify/sync players).
	var quiet_amb: Node = load("res://scripts/ambient_audio.gd").new()
	quiet_amb.set_process(false)
	root.add_child(quiet_amb)
	quiet_amb.set("_swim_activity", 0.0)
	var fake_ext := _FakeMusicReactive.new()
	root.add_child(fake_ext)
	mc.call("_populate_external", fake_ext, 0.016, quiet_amb)
	t.approx(float(context.get("swim_busy", -1.0)), 0.0, "quiet external has no swim_busy")
	var loco_ext_quiet: Dictionary = MusicChoreography.universal_locomotion_mods(
		context, {"color_band": "bass", "stroke_subdiv": 1.0, "expressive": 0.7}, 0.8)
	quiet_amb.set("_swim_activity", 0.7)
	mc.call("_populate_external", fake_ext, 0.016, quiet_amb)
	t.approx(float(context.get("swim_busy", 0.0)), 0.7, "external path records swim_busy")
	t.check((context.get("onsets", []) as Array).size() >= 3,
		"empty analyzer onsets synthesize kick/snare/hat")
	var loco_ext_busy: Dictionary = MusicChoreography.universal_locomotion_mods(
		context, {"color_band": "bass", "stroke_subdiv": 1.0, "expressive": 0.7}, 0.8)
	t.check(float(loco_ext_busy.get("kick_thump", 0.0)) >= float(loco_ext_quiet.get("kick_thump", 0.0)),
		"busy tank amplifies external kick accents vs quiet")
	quiet_amb.queue_free()
	fake_ext.queue_free()
	ambient.queue_free()
	context.merge({"active": true, "source": "generative", "genre": "lofi",
		"tempo": 76.0, "swing": 0.5, "confidence": 1.0, "mode": "major"}, true)
	mc.set("_dance_blend", 0.85)
	mc.set("_bow_blend", 0.6)
	context.active = false
	var exit_mods: Dictionary = mc.fauna_behavior_mods(1)
	t.check(float(exit_mods.get("dance_blend", 0.0)) > 0.02
			or float(exit_mods.get("bow", 0.0)) > 0.02,
		"music exit keeps decaying dance mods")
	t.check(absf(float(exit_mods.get("speed", 1.0)) - 1.0) > 0.02
			or float(exit_mods.get("bow", 0.0)) > 0.02,
		"music exit does not snap speed/bow to silence")
	mc.set("_dance_blend", 0.0)
	mc.set("_bow_blend", 0.0)
	t.approx(mc.fauna_behavior_mods(1).speed, 1.0, "silence has no choreography")
	context.active = true
	mc.set("_dance_blend", 1.0)
	mc.set("_env_dt", 0.016)
	mc.set("_dance_envelopes", {})
	var burst_frames: PackedInt32Array = MusicChoreography.dance_envelope_frames("dart", "burst")
	t.equals(int(burst_frames[0]) if burst_frames.size() > 0 else 0, 4, "burst windup is 4 frames")
	context.merge({"source": "generative", "genre": "pop", "energy_env": 0.7,
		"energy": 0.7, "downbeat": true, "onsets": [
			{"band": "bass", "strength": 0.85},
			{"band": "mid", "strength": 0.4},
		]}, true)
	var env_mods: Dictionary = mc.fauna_behavior_mods(99, {"swim_pattern": "dart"})
	var env_recs: Dictionary = mc.get("_dance_envelopes")
	t.check(env_recs.has(99), "dance accent envelope is cached per fish")
	var env: MotionEnvelope = env_recs[99].get("env") as MotionEnvelope
	t.check(env != null and env.stage == MotionEnvelope.Stage.WINDUP,
		"synthetic downbeat starts in wind-up")
	t.check(int(env_mods.get("dance_envelope_stage", -1)) == MotionEnvelope.Stage.WINDUP,
		"mods report the wind-up stage")
	var env_again: Dictionary = mc.fauna_behavior_mods(99, {"swim_pattern": "dart"})
	t.equals(int(env_again.get("dance_envelope_stage", -1)), MotionEnvelope.Stage.WINDUP,
		"same-frame fauna mods do not double-step the envelope")
	env.step(0.08)
	t.equals(env.stage, MotionEnvelope.Stage.ACTION, "envelope reaches the action peak")
	context.active = false
	t.equals(mc.describe_now_playing(), "", "silent music is absent from thoughts")
	context.merge({"active": true, "source": "generative", "genre": "lofi",
		"tempo": 76.0, "swing": 0.5, "confidence": 1.0, "mode": "major"}, true)
	t.check(mc.describe_now_playing().contains("swung"), "lo-fi perception describes its rhythm")
	context.arousal = 0.5
	mc.call("_derive_understanding", 0.0)
	t.approx(context.arousal, 0.5, "semantic smoothing respects elapsed time")
	mc.call("_derive_understanding", 1.0)
	t.check(not is_equal_approx(context.arousal, 0.5), "generative features produce an affect signal")
	cfg.music_volume = 0.0
	t.check(not mc.call("_generative_live", null), "muted score is not perceived as playing")
	cfg.music_volume = 0.7
	var studio: Node = load("res://scripts/sound_panel.gd").new()
	root.add_child(studio)
	var presets: Array = studio.get("PRESETS")
	for preset in presets:
		if preset.key == "lofi":
			studio.call("_apply_preset", preset)
	t.equals(cfg.music_persona, "lofi", "lo-fi selects its groove engine")
	t.equals(cfg.music_style, "hybrid", "lo-fi includes a musical bed")
	studio.call("_apply_preset", {"values": {"music_dance_style": "sway"}})
	t.equals(cfg.music_persona, "lofi", "dance controls preserve the selected score")
	for preset in presets:
		if preset.key == "ambient":
			studio.call("_apply_preset", preset)
	t.equals(cfg.music_persona, "none", "another preset clears the previous persona")
	studio.queue_free()
	await process_frame
	quit(t.finish())


class _FakeMusicReactive extends Node:
	func get_drive() -> Dictionary:
		return {
			"tempo": 120.0, "energy": 0.6, "bass": 0.55, "mid": 0.4, "high": 0.3,
			"beat": 0.2, "danceability": 0.55, "beat_phase": 0.0,
		}

	func get_music_clock() -> Dictionary:
		return {
			"beat_phase": 0.0, "bar_phase": 0.0, "downbeat": true,
			"phrase_state": "drop", "confidence": 0.8, "onsets": [],
		}

	func get_analysis() -> Dictionary:
		return {}
