extends SceneTree

# Creature voices, the lofi defaults, and the "talk to the tank" prompt.
#
#   - voice params / samples are a pure function of the seed
#   - small fish speak higher than big ones; bold fish are brighter
#   - every rendered voice stays under a fixed peak and starts/ends silent
#   - the rate limiter caps concurrent voices and bloops
#   - the tank mind's mood maps calm -> wider/softer, stress -> tenser, never brighter
#   - the default groove is lofi (no shaker/clap/off-beat hat/build drama) and
#     saves holding the old EDM defaults migrate, hand-set values do not
#   - the onboarding prompt fires once, and never once the flag is set
#
# dev/audio_probe.tscn -- voices measures the actual levels against the bed.

const V := preload("res://scripts/tank_voice_audio.gd")
const Prompt := preload("res://scripts/tank_talk_prompt.gd")
const Cfg := preload("res://scripts/tank_config.gd")


func _init() -> void:
	var t := TestSupport.Suite.new("voice_onboarding")
	_voice_params(t)
	_render(t)
	_rate_limit(t)
	_mood(t)
	_lofi_defaults(t)
	_prompt(t)
	quit(t.finish())


func _voice_params(t: TestSupport.Suite) -> void:
	var a: Dictionary = V.voice_params("fish", 4242, 40, 0.3, 0.6)
	var b: Dictionary = V.voice_params("fish", 4242, 40, 0.3, 0.6)
	t.check(a == b, "fish voice params are deterministic per seed")
	t.check(a != V.voice_params("fish", 4243, 40, 0.3, 0.6), "a different seed is a different voice")
	t.check(V.voice_params("tank", 7, 30) == V.voice_params("tank", 7, 30), "tank breath deterministic")
	t.check(V.voice_params("nonsense", 1).is_empty(), "unknown kind -> no sound")
	var v0: Dictionary = V.voice_params("fish", 9, 40, 0.3, 0.6, 0)
	var v1: Dictionary = V.voice_params("fish", 9, 40, 0.3, 0.6, 5)
	t.approx(float(v0["base_hz"]), float(v1["base_hz"]), "variant keeps the fish's pitch")
	for s in [1, 77, 1234, 99999]:
		var small: Dictionary = V.voice_params("fish", s, 40, 0.05, 0.5)
		var big: Dictionary = V.voice_params("fish", s, 40, 0.95, 0.5)
		t.check(float(small["base_hz"]) > float(big["base_hz"]) * 1.8,
			"seed %d: small fish (%.0f Hz) well above big fish (%.0f Hz)" % [
				s, float(small["base_hz"]), float(big["base_hz"])])
		var shy: Dictionary = V.voice_params("fish", s, 40, 0.5, 0.0)
		var bold: Dictionary = V.voice_params("fish", s, 40, 0.5, 1.0)
		t.check(float(bold["brightness"]) > float(shy["brightness"]), "seed %d: bold is brighter" % s)
		t.check(float(bold["lpf_hz"]) <= 4500.0, "seed %d: even bold stays under 4.5 kHz" % s)
	t.check(V.duration_s(V.voice_params("fish", 3, 90)) > V.duration_s(V.voice_params("fish", 3, 10)),
		"a longer reply babbles longer")
	t.check(V.duration_s(V.voice_params("tank", 3, 120)) > V.duration_s(V.voice_params("tank", 3, 5)),
		"a longer tank line breathes longer")
	t.in_range(V.duration_s(V.voice_params("tank", 3, 400)), 1.0, 2.8, "tank breath capped")
	t.check(V.sound_class("fish") == "voice" and V.sound_class("gulp") == "bloop", "classes")


func _render(t: TestSupport.Suite) -> void:
	var p: Dictionary = V.voice_params("fish", 555, 30, 0.2, 0.8)
	var s1: PackedFloat32Array = V.render(p)
	var s2: PackedFloat32Array = V.render(p)
	t.check(s1 == s2, "rendered samples are deterministic")
	var kinds: Array = ["tank", "fish", "bloop", "gulp", "plop", "snail", "ignite", "bubble_rise"]
	for k in kinds:
		for seed_v in [3, 31337]:
			var smp: PackedFloat32Array = V.render(V.voice_params(k, seed_v, 50, 0.4, 0.9))
			var peak: float = 0.0
			for x in smp:
				peak = maxf(peak, absf(x))
			t.check(smp.size() > 100, "%s renders" % k)
			t.check(peak <= V.PEAK_CEILING + 0.0001 and peak > 0.01,
				"%s/%d peak %.3f within (0.01, %.2f]" % [k, seed_v, peak, V.PEAK_CEILING])
			t.check(absf(smp[0]) < 0.001 and absf(smp[smp.size() - 1]) < 0.001,
				"%s/%d starts and ends silent (no click)" % [k, seed_v])
			# Soft onset/offset: the first and last 3 ms stay well under the peak.
			var edge: int = mini(66, smp.size() >> 2)
			var edge_peak: float = 0.0
			for i in edge:
				edge_peak = maxf(edge_peak, maxf(absf(smp[i]), absf(smp[smp.size() - 1 - i])))
			t.check(edge_peak < peak * 0.35,
				"%s/%d fades in and out (edge %.3f vs peak %.3f)" % [k, seed_v, edge_peak, peak])


func _rate_limit(t: TestSupport.Suite) -> void:
	# Not added to the tree: no players, no _process - the limiter's own
	# clock is driven by tick(), which is exactly what is under test.
	var va: Node = V.new()
	var accepted: int = 0
	for i in 10:
		if va.request(V.voice_params("fish", 100 + i, 30, 0.5, 0.5), -10.0):
			accepted += 1
	t.check(va.active_count("voice") <= V.MAX_ACTIVE_VOICES,
		"concurrent voices capped (%d)" % va.active_count("voice"))
	t.check(va.queued_count() <= V.MAX_QUEUE, "queue capped (%d)" % va.queued_count())
	t.check(accepted <= V.MAX_ACTIVE_VOICES + V.MAX_QUEUE, "extras dropped (%d accepted)" % accepted)
	t.check(va.is_talking(), "talking while voices are live")
	var max_seen: int = 0
	for _i in 60:
		va.tick(0.05)
		max_seen = maxi(max_seen, va.active_count("voice"))
	t.check(max_seen <= V.MAX_ACTIVE_VOICES, "voices never exceed the cap while draining (%d)" % max_seen)
	for _i in 100:
		va.tick(0.1)
	t.check(va.active_count() == 0 and va.queued_count() == 0, "everything drains")
	t.check(not va.is_talking(), "quiet after draining")
	var bl: int = 0
	for i in 10:
		if va.request(V.voice_params("bloop", i, 0, 0.5), -10.0):
			bl += 1
	t.check(va.active_count("bloop") <= V.MAX_ACTIVE_BLOOPS, "bloops capped")
	t.check(bl <= 2, "bloop spam mostly dropped (%d accepted)" % bl)
	t.check(va.request(V.voice_params("fish", 1, 20), -10.0) or va.queued_count() > 0,
		"a reply is never blocked by bloop chatter")
	va.stop_all()
	va.free()


func _mood(t: TestSupport.Suite) -> void:
	var calm: Dictionary = MusicReactivity.mind_mood(0.7, 0.05)
	var tense: Dictionary = MusicReactivity.mind_mood(-0.8, 0.9)
	var neutral: Dictionary = MusicReactivity.mind_mood(0.0, 0.35)
	t.check(float(calm["width"]) > 1.2, "calm tank widens the bed")
	t.check(float(calm["cutoff_mul"]) < 1.0, "calm tank softens the tone")
	t.check(float(calm["gain_db"]) < 0.0, "calm tank sits a touch quieter")
	t.check(float(tense["detune_add"]) > 0.0 and float(tense["lfo_mul"]) > 1.0,
		"stressed tank gets tenser (beating + motion)")
	t.check(float(tense["cutoff_mul"]) <= MusicReactivity.MOOD_CUTOFF_MAX_MUL,
		"stress never opens the filter past %.2f" % MusicReactivity.MOOD_CUTOFF_MAX_MUL)
	t.check(float(tense["gain_db"]) <= 0.0, "stress never gets louder")
	t.check(float(calm["detune_add"]) < float(tense["detune_add"]), "calm beats less than stress")
	t.in_range(float(neutral["cutoff_mul"]), 0.85, MusicReactivity.MOOD_CUTOFF_MAX_MUL, "neutral in range")


func _lofi_defaults(t: TestSupport.Suite) -> void:
	# ambient_audio.gd needs autoloads to compile, so read its constant as text.
	var trim: float = _const_float("res://scripts/ambient_audio.gd", "BUS_TRIM_DRUMS")
	t.check(trim > 0.0 and trim <= 2.5, "drums trim is modest (x%.1f; was x4.2)" % trim)
	var c: Node = Cfg.new()
	t.check(float(c.music_offbeat_hat) < 0.2, "off-beat hat off by default")
	t.check(float(c.music_shaker_mix) <= 0.001, "shaker off by default (the tsh-tsh)")
	t.check(float(c.music_clap_mix) <= 0.001, "clap off by default")
	t.check(float(c.music_build_drama) <= 0.05, "no snare rolls / reverse cymbals by default")
	t.check(float(c.music_drop_intensity) <= 0.2, "no feeding builds by default")
	t.check(String(c.music_phrase_form) == "loop", "default form is the calm loop")
	c.music_shaker_mix = 0.4        # the old default: never touched
	c.music_offbeat_hat = 0.55      # old default
	c.music_clap_mix = 0.8          # chosen by hand
	c.music_phrase_form = "auto"    # old default
	c.call("_migrate_music_lofi_defaults")
	t.approx(float(c.music_shaker_mix), 0.0, "old shaker default migrates")
	t.approx(float(c.music_offbeat_hat), 0.0, "old hat default migrates")
	t.approx(float(c.music_clap_mix), 0.8, "a hand-set value is kept")
	t.check(String(c.music_phrase_form) == "loop", "old phrase form migrates")
	c.music_shaker_mix = 0.7
	c.reset_to_defaults()
	t.approx(float(c.music_shaker_mix), 0.0, "reset lands on the lofi defaults")
	c.free()


func _prompt(t: TestSupport.Suite) -> void:
	var ready_state: Dictionary = {"channel_available": true, "settled_s": Prompt.SETTLE_S + 1.0}
	t.equals(Prompt.decide(ready_state), Prompt.Decision.FIRE, "fires once settled + visible")
	var early: Dictionary = ready_state.duplicate()
	early["settled_s"] = 10.0
	t.equals(Prompt.decide(early), Prompt.Decision.WAIT, "waits for the tank to settle")
	var blocked: Dictionary = ready_state.duplicate()
	blocked["blocked"] = true
	t.equals(Prompt.decide(blocked), Prompt.Decision.WAIT, "never over the walkthrough / cards")
	var hidden: Dictionary = ready_state.duplicate()
	hidden["channel_available"] = false
	t.equals(Prompt.decide(hidden), Prompt.Decision.WAIT, "needs the box on screen")
	var voice_off: Dictionary = ready_state.duplicate()
	voice_off["voice_off"] = true
	t.equals(Prompt.decide(voice_off), Prompt.Decision.WAIT, "respects voice-off")
	var spoken: Dictionary = ready_state.duplicate()
	spoken["spoken"] = true
	t.equals(Prompt.decide(spoken), Prompt.Decision.NEVER, "never once the player has spoken")
	var prompted: Dictionary = ready_state.duplicate()
	prompted["prompted"] = true
	t.equals(Prompt.decide(prompted), Prompt.Decision.NEVER, "never twice")
	# Simulated session: fires exactly once over ten minutes.
	var fired: int = 0
	var st: Dictionary = {"channel_available": true, "settled_s": 0.0}
	for i in 600:
		st["settled_s"] = Prompt.accrue(float(st["settled_s"]), 1.0, i < 30)
		if Prompt.decide(st) == Prompt.Decision.FIRE:
			fired += 1
			st["prompted"] = true
	t.equals(fired, 1, "fires exactly once per player")
	t.approx(Prompt.accrue(5.0, 1.0, true), 5.0, "blocked time does not count")
	t.check(Prompt.history_has_tank_line([{"who": "you → the tank", "text": "hi"}]),
		"sees the keeper's tank line")
	t.check(not Prompt.history_has_tank_line([{"who": "you → Pip", "text": "hi"}, {"who": "the tank", "text": "we"}]),
		"a fish chat or the tank's own line is not the keeper speaking to the tank")
	t.check(Prompt.LINE.contains("enter"), "the line says how")


func _const_float(path: String, name: String) -> float:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1.0
	var prefix: String = "const %s: float = " % name
	for line in f.get_as_text().split("\n"):
		if line.begins_with(prefix):
			return float(line.substr(prefix.length()).strip_edges())
	return -1.0
