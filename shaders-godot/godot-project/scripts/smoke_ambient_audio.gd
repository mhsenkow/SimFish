extends SceneTree

# The ambient music bed.
#
# WHAT WENT WRONG. The reactive synth was being swapped for a cheap looping
# stub whenever shader_perf_tier >= 2 - and shader_perf_tier is set by the
# GRAPHICS fidelity preset. So picking "potato" graphics for a weak GPU
# silently replaced the soundtrack with something that hard-zeroed the drum
# bus and ignored the tank entirely. Measured over 5 s of generated audio:
#
#   full bed    drums -20.8 dBFS   synth -26.8 dBFS
#   potato bed  drums SILENT       synth -39.6 dBFS
#
# and the potato output was byte-identical for a dead tank and a healthy
# one, which is what gave it away.
#
# The generator itself cannot run under the --script smoke runner (it needs
# autoloads), so this asserts the wiring. dev/audio_probe.tscn measures the
# actual samples.

const Cfg := preload("res://scripts/tank_config.gd")


func _init() -> void:
	var t := TestSupport.Suite.new("ambient_audio")

	var probe := Cfg.new()
	t.check("music_simple_bed" in probe,
		"the simple bed is its own audio setting")
	t.check(not bool(probe.music_simple_bed),
		"and is off by default - the full bed is the normal experience")
	for k in ["music_enabled", "music_ambient_enabled", "music_events_enabled",
			"music_environment_enabled", "music_volume", "music_style"]:
		t.check(k in probe, "audio gate %s exists" % k)
	t.check(bool(probe.music_enabled) and bool(probe.music_ambient_enabled),
		"audio is on by default")
	probe.free()

	var src: String = _read("res://scripts/ambient_audio.gd")
	t.check(not src.is_empty(), "ambient_audio.gd readable")

	# THE BUG: a GPU fidelity setting must not decide what the music sounds
	# like. The synth runs on a CPU worker; the GPU tier is unrelated.
	# The assignment spans several lines, so take the whole statement rather
	# than the first line of it.
	var potato_line: String = ""
	var lines: PackedStringArray = src.split("\n")
	for i in lines.size():
		if lines[i].contains("_cached_potato_bed =") and not lines[i].contains("var "):
			potato_line = ""
			for j in range(i, mini(i + 4, lines.size())):
				potato_line += lines[j] + " "
				if lines[j].strip_edges().ends_with(")") \
						or lines[j].strip_edges().ends_with("2"):
					break
	t.check(not potato_line.is_empty(), "the simple-bed switch is assigned")
	t.check(not potato_line.contains("shader_perf_tier"),
		"the music bed is NOT gated on the graphics tier: %s" % potato_line.strip_edges())
	t.check(potato_line.contains("music_simple_bed"),
		"it reads the audio setting instead")

	# The stub must be levelled against the bed it stands in for, or even
	# when it is playing it reads as "the sound is broken".
	t.check(not src.contains("blk_synth[i] = bed * 0.55"),
		"the simple bed is no longer 13 dB below the real one")
	t.check(src.contains("_fill_playback_buffers_potato"),
		"a simple bed still exists for genuinely low-end devices")

	# A worker task that outlives the node writes to a half-freed object.
	t.check(src.contains("func _exit_tree()")
			and src.contains("wait_for_task_completion"),
		"a synth batch in flight is awaited before teardown")

	# The three buses must still be built and started.
	for bus in ["Music_Drums", "Music_Synth", "Music_Air"]:
		t.check(src.contains(bus), "the %s bus is wired" % bus)
	t.check(src.contains("p.play()"), "the generator players are started")

	quit(t.finish())


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt: String = f.get_as_text()
	f.close()
	return txt
