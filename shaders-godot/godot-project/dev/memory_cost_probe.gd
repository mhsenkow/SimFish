extends SceneTree

const Memory = preload("res://scripts/episodic_memory.gd")
const WorldModel = preload("res://scripts/mind_world_model.gd")

func _initialize() -> void:
	await process_frame
	var fish := Fish.new()
	fish.id = "memory-cost"
	for i in 64:
		Memory.encode_episode(fish, "food" if i % 2 == 0 else "threat",
			"remembered place %d" % i, 0.6, Vector3(i, 1, 0))
	var query: PackedFloat32Array = Memory.embed("food", "remembered place")
	var state: MindState = MindChannel.for_cycle(fish)
	state.felt_self = {"history": fish._episodic_store.duplicate(true)}
	var packed: Dictionary = state.to_dict()
	var times: Array[float] = []
	for _repeat in 5:
		var start: int = Time.get_ticks_usec()
		for _i in 500:
			Memory.retrieve(fish, query, 3)
		times.append(float(Time.get_ticks_usec() - start) / 500.0)
	times.sort()
	var result: Dictionary = {"retrieve_64_us": times[2]}
	times.clear()
	for _repeat in 5:
		var start: int = Time.get_ticks_usec()
		for _i in 500:
			var restored := MindState.new()
			restored.from_dict(packed)
		times.append(float(Time.get_ticks_usec() - start) / 500.0)
	times.sort()
	result["restore_snapshot_us"] = times[2]
	times.clear()
	for _repeat in 5:
		var start: int = Time.get_ticks_usec()
		for _i in 500:
			var restored := MindState.new()
			restored.from_dict(packed, true)
		times.append(float(Time.get_ticks_usec() - start) / 500.0)
	times.sort()
	result["adopt_snapshot_us"] = times[2]
	times.clear()
	for _repeat in 5:
		var start: int = Time.get_ticks_usec()
		for _i in 500:
			WorldModel.tick(fish, null, 0.2)
		times.append(float(Time.get_ticks_usec() - start) / 500.0)
	times.sort()
	result["prediction_tick_us"] = times[2]
	print(JSON.stringify(result))
	var path: String = OS.get_environment("MEMORY_PROBE_OUT")
	if not path.is_empty():
		var out := FileAccess.open(path, FileAccess.WRITE)
		out.store_string(JSON.stringify(result, "\t"))
	fish.free()
	quit()
