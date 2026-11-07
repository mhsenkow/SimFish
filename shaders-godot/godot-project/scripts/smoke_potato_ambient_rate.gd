extends SceneTree

# SENTIENCE_THE_LOOM_THAT_THINKS #9 — potato bed timebase matches play rate.




func _initialize() -> void:
	var t := TestSupport.Suite.new("smoke_potato_ambient_rate")
	var bed_src: String = FileAccess.get_file_as_string("res://scripts/potato_ambient_bed.gd")
	var audio_src: String = FileAccess.get_file_as_string("res://scripts/ambient_audio.gd")

	t.check(not bed_src.contains("/ 44100"),
			"potato bed must not synthesize against 44100 Hz time")
	t.check(bed_src.contains("SAMPLE_RATE"),
			"potato bed declares SAMPLE_RATE")
	t.check(audio_src.contains("const SAMPLE_RATE: int = 22050"),
			"ambient_audio plays at 22050 Hz")

	PotatoAmbientBed.reset_for_test()
	PotatoAmbientBed.ensure_built()
	t.equals(PotatoAmbientBed.SAMPLE_RATE, 22050,
			"potato SAMPLE_RATE matches ambient_audio")
	t.equals(PotatoAmbientBed.LOOP_SAMPLES, PotatoAmbientBed.SAMPLE_RATE,
			"one-second loop at the play rate")

	# One second of playback advances exactly one loop (pitch-correct).
	var first: Vector2 = PotatoAmbientBed.next_stereo()
	for _i in PotatoAmbientBed.LOOP_SAMPLES - 1:
		PotatoAmbientBed.next_stereo()
	var again: Vector2 = PotatoAmbientBed.next_stereo()
	t.approx(again.x, first.x, "loop wraps seamlessly after SAMPLE_RATE samples", 1e-6)
	t.approx(again.y, first.y, "loop wraps seamlessly (R)", 1e-6)

	quit(t.finish())
