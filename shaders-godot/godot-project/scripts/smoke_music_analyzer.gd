extends SceneTree

const _Analyzer = preload("res://scripts/music_analyzer.gd")

func _initialize() -> void:
	await process_frame
	var a: RefCounted = _Analyzer.new()
	var out: Dictionary = a.analyze(null, 0.016, 0.5, 0.4, 0.3, 0.45, 128.0)
	assert(out.has("beat_phase"))
	assert(out.has("onsets"))
	for i in 30:
		out = a.analyze(null, 0.016, 0.5 + sin(i * 0.4) * 0.2, 0.35, 0.25, 0.4, 128.0)
	assert(float(out.get("confidence", 0.0)) >= 0.0)
	print("[smoke] music_analyzer OK")
	quit()
