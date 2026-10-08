extends SceneTree
const Experience = preload("res://scripts/fish_experience.gd")

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_fish_experience")
	var cfg: Node = root.get_node("TankConfig")
	cfg.reset_to_defaults()
	cfg.capture_mode = true
	var mc: Node = root.get_node("MusicContext")
	mc.set_process(false)
	var context: Dictionary = mc.get("_ctx")
	context.merge({"active": true, "source": "generative", "genre": "lofi", "mode": "major",
		"tempo": 76.0, "confidence": 1.0}, true)
	var f := Fish.new()
	f.id = "experience_test"
	root.add_child(f)
	f.set_process(false)
	f.position = Vector3(1, 3, 2)
	f.hunger = 0.8
	f.stress = 0.0
	f.spooked = 0.0
	f.age = 100.0
	for i in 120:
		Experience.tick(f, 1.0)
	t.check(float(f._experience_response.get("familiar", 0.0)) > 0.4, "safe listening builds individual familiarity")
	t.check(float(f._experience_response.get("comfort", 0.0)) > 0.2, "safe listening acquires comfort")
	var key: String = Experience.cue(mc.now_playing())
	for i in 4:
		f._experience_memory.clock = float(f._experience_memory.get("clock", 0.0)) + 10.0
		Experience.observe(f, "food", Vector3(3, 3, 2))
	Experience.tick(f, 1.0)
	t.check(float(f._experience_response.food) > 0.5, "repeated meals build an association")
	var before: float = f._experience_response.food
	Experience.observe(f, "food", f.position)
	Experience.tick(f, 1.0)
	t.check(float(f._experience_response.food) <= before, "same feeding encounter cannot farm learning")
	f.current_mode = Fish.Mode.CRUISE
	var pull: Vector3 = Experience.steer(f, Vector3.ZERO, 1.0)
	t.check(pull.x > 0.03 and pull.length() < 0.16, "hungry fish gently approach the associated food location")
	f.current_mode = Fish.Mode.FLEE
	t.check(Experience.steer(f, Vector3.ZERO, 1.0) == Vector3.ZERO, "memory cannot override fleeing")
	f.current_mode = Fish.Mode.CRUISE
	f.goal_timer = 2.0
	t.check(Experience.steer(f, Vector3.ZERO, 1.0) == Vector3.ZERO, "memory respects committed goals")
	f.goal_timer = 0.0
	cfg.music_sync_fish = false
	t.check(Experience.steer(f, Vector3.ZERO, 1.0) == Vector3.ZERO, "disabling music response immediately removes food attraction")
	var frozen: float = f._experience_memory.songs[key].familiar
	Experience.tick(f, 1.0)
	t.approx(f._experience_memory.songs[key].familiar, frozen, "disabled music cannot teach familiarity")
	t.check(f._experience_response.is_empty(), "disabled listening clears transient thoughts")
	cfg.music_sync_fish = true
	f._experience_memory.clock = float(f._experience_memory.get("clock", 0.0)) + 10.0
	Experience.observe(f, "alarm", f.position)
	f._experience_memory.clock = float(f._experience_memory.get("clock", 0.0)) + 10.0
	Experience.observe(f, "alarm", f.position)
	Experience.tick(f, 1.0)
	t.check(str(f._experience_response.get("reason", "")).contains("fright"), "alarm memories explain caution")
	t.check(Experience.steer(f, Vector3.ZERO, 1.0) == Vector3.ZERO, "alarm suppresses musical feeding anticipation")
	var alarm: float = f._experience_response.alarm
	for i in 120:
		Experience.tick(f, 1.0)
	t.check(float(f._experience_response.alarm) < alarm, "later safe listening softens alarm associations")
	f._sleep_depth = 0.8
	for i in 60:
		Experience.tick(f, 1.0)
	t.check(float(f._experience_memory.rest.confidence) > 0.4, "rest establishes a favourite sleeping place")
	f.position = Vector3(2, 3, 2)
	t.check(Experience.steer(f, Vector3.ZERO, 1.0).x < 0.0, "resting fish can return to their learned refuge")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(f.to_save_dict()))
	var other := Fish.new()
	Experience.restore(other, saved.experience)
	t.approx(other._experience_memory.songs[key].food, f._experience_memory.songs[key].food, "food associations survive real save serialization")
	t.check(Experience.position_from(other._experience_memory.rest.pos) == Vector3(1, 3, 2), "resting place survives JSON")
	other._experience_memory.songs[key].food = 0.0
	t.check(f._experience_memory.songs[key].food > 0.0, "restored memories have independent ownership")
	for i in 30:
		Experience.ensure_song(other, "cue_%d" % i)
	t.check(other._experience_memory.songs.size() == Experience.LIMIT, "learning has a fixed memory budget")
	Experience.restore(other, {"songs": {"bad": {"food": 200, "alarm": "bad", "exposure": -1}},
		"rest": {"pos": [0, 1, 2], "confidence": -10}})
	t.approx(other._experience_memory.songs.bad.food, 1.0, "restoration bounds learned strengths")
	t.approx(other._experience_memory.songs.bad.alarm, 0.0, "invalid numbers do not enter learning")
	t.approx(other._experience_memory.rest.confidence, 0.0, "restoration bounds refuge confidence")
	t.check(not Experience.valid_position(["broken", 0, 0]), "invalid remembered coordinates cannot become an origin attraction")
	f._experience_response = {"food": 1.0}
	f._sleep_depth = 0.0
	t.check(Experience.steer(f, Vector3.ZERO, 1.0) == Vector3.ZERO, "missing feeding coordinates cannot lure fish to the origin")
	Experience.restore(other, null)
	t.check(other._experience_memory.is_empty(), "older saves start with no invented experiences")
	context.confidence = 0.1
	t.equals(Experience.cue(mc.now_playing()), "", "uncertain music cannot create a false identity")
	f.queue_free()
	other.free()
	await process_frame
	quit(t.finish())
