extends SceneTree

const Pigment = preload("res://scripts/fish_pigment.gd")
const Presence = preload("res://scripts/make_it_there.gd")

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_fish_pigment")
	var cfg: Node = root.get_node("TankConfig")
	cfg.capture_mode = true
	cfg.music_enabled = false
	for original in [Color8(220,32,50), Color8(70,185,245), Color8(230,142,30),
			Color8(32,150,95), Color8(24,28,32), Color(0.85,0.13,0.25,0.62)]:
		for state in [Vector4(1,0,0,0), Vector4(0,0,0,0.75),
				Vector4(1,1,0.58,0.75), Vector4(0,0,0.58,0)]:
			var color: Color = Pigment.compose(original, state, 0.0, Color.CORAL, original)
			t.approx(color.h, original.h, "life and emotion preserve pigment hue", 0.001)
			t.check(color.s >= original.s * 0.45, "wash retains colored markings")
			t.check(color.v <= original.v * 1.05, "wash cannot bleach a fish toward white")
			t.approx(color.a, original.a, "thin tissue retains its density")
	var blue: Color = Color8(70,185,245)
	var flushed: Color = Pigment.compose(blue, Vector4.ZERO, 1.0, Color.CORAL, Color.RED)
	t.check(flushed.is_equal_approx(blue), "stress flush leaves the blue stripe intact")
	var fish := Fish.new()
	root.add_child(fish)
	fish.set_process(false)
	fish.age = 80.0
	fish.max_age_s = 240.0
	fish.stress = 0.0
	fish.mood = 0.2
	fish.init_genome({"species":"glassdart", "is_bioluminescent":false,
		"base_color": Color8(220,32,50), "marking_color":blue,
		"accent_color":Color8(190,26,42), "pattern_type":4})
	var handle: VoxelBatch.Handle = _body_handle(fish)
	t.check(handle != null, "real fish has a colored body voxel")
	if handle != null:
		var start: Color = _uploaded(handle)
		fish.stress = 1.0
		fish.spooked = 1.0
		fish.mood = -1.0
		var previous: Color = start
		var largest_jump: float = 0.0
		for frame in 120:
			# Mix real biological ticks (10 Hz) with color frames (60 Hz).
			# The former used to restore full pigment between pallor writes.
			if frame % 6 == 0:
				fish.tick(0.1, [], [], [], [], [], AABB(Vector3(-15,0,-6), Vector3(30,8,12)))
			fish._tick_fauna_body_color(1.0 / 60.0)
			var current: Color = _uploaded(handle)
			largest_jump = maxf(largest_jump, _color_delta(previous, current))
			previous = current
		t.check(largest_jump < 0.045, "stress changes ease across asynchronous biology/render ticks")
		t.check(_color_delta(start, previous) > 0.015, "emotional pigment response is still visible")
		t.check(previous.s > start.s * 0.65, "a stressed adult retains its chromatic identity")
		fish.age = 1.0
		fish.stress = 0.0
		fish.spooked = 0.0
		fish.mood = 0.2
		fish._update_maturity()
		fish._apply_maturity_color()
		var young: Color = _uploaded(handle)
		t.check(young.s < start.s and young.s > start.s * 0.65, "fry are subtly softer without a silver-white overlay")
		var snapshot: Dictionary = fish.to_save_dict()
		t.check(snapshot.has("color_variation"), "individual color roll is saved")
		t.check(not (snapshot["genome"] as Dictionary).has("color_variation"),
			"cosmetic variation does not become a heritable mutation")
		var restored := Fish.new()
		root.add_child(restored)
		restored.set_process(false)
		restored.apply_save_dict(snapshot)
		var restored_handle: VoxelBatch.Handle = _body_handle(restored)
		t.check(restored_handle != null, "restored fish has its body")
		if restored_handle != null:
			t.check(_color_delta(_uploaded(restored_handle), young) < 0.001,
				"save restore initializes the correct pigment before the first frame")
		restored.free()
		var legacy: Dictionary = snapshot.duplicate(true)
		legacy.erase("color_variation")
		var older_a := Fish.new()
		var older_b := Fish.new()
		root.add_child(older_a)
		root.add_child(older_b)
		older_a.set_process(false)
		older_b.set_process(false)
		older_a.apply_save_dict(legacy)
		older_b.apply_save_dict(legacy)
		t.check(older_a.base_color.is_equal_approx(older_b.base_color),
			"old saves derive repeatable individual pigment from identity")
		older_a.free()
		older_b.free()
	var membranes: int = 0
	for h: VoxelBatch.Handle in fish._voxel_builder.handles:
		var original: Color = h.get_meta("orig_color")
		if original.a < 0.98:
			membranes += 1
			t.approx(_uploaded(h).a, original.a, "live pigment preserves fin membranes")
	t.check(membranes > 0, "real fish exercises membrane pigment")
	# Exercise the senescent branch that ordinary adult captures never reach.
	# 60 s makes the rare grace event certain, so a missing-property error
	# cannot silently return from this helper while the smoke still passes.
	fish.age = fish.max_age_s * 0.90
	fish._update_maturity()
	fish.mood = 0.0
	fish.bio.erase("luminous_farewell")
	Presence._tick_breaking_beauty(fish, 60.0)
	t.approx(fish.mood, 0.03, "senescent grace uses life stage without an obsolete color flag")
	fish.age = fish.max_age_s * 0.50
	fish._update_maturity()
	fish.mood = 0.0
	Presence._tick_breaking_beauty(fish, 60.0)
	t.approx(fish.mood, 0.0, "senescent grace does not affect younger adults")
	fish.free()
	quit(t.finish())


func _body_handle(fish: Fish) -> VoxelBatch.Handle:
	var best: float = INF
	var result: VoxelBatch.Handle = null
	for handle: VoxelBatch.Handle in fish._voxel_builder.handles:
		var original: Color = handle.get_meta("orig_color")
		if original.a < 0.98:
			continue
		var error: float = _color_delta(original, fish.base_color)
		if error < best:
			best = error
			result = handle
	return result


func _uploaded(handle: VoxelBatch.Handle) -> Color:
	return handle.batch._colors[handle.index]


func _color_delta(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b))
