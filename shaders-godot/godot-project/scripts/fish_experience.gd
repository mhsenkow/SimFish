extends RefCounted

# Main-thread experience learning. Bounded, slow, and separate from worker snapshots.
const LIMIT: int = 12
const Saves = preload("res://scripts/save_helpers.gd")

static func cue(song: Dictionary) -> String:
	if not bool(song.get("active", false)) or float(song.get("confidence", 0.0)) < 0.35:
		return ""
	# Broad acoustic families, not claims to recognize an individual recording.
	var pace: String = "slow" if float(song.get("tempo", 100.0)) < 95.0 else "brisk"
	return "%s:%s:%s:%s" % [song.get("source", "none"), song.get("genre", "ambient"), song.get("mode", "major"), pace]

static func listening_enabled(f) -> bool:
	var cfg: Node = f.tank_cfg()
	var mc: Node = f.music_ctx()
	if cfg == null or mc == null or not bool(cfg.music_sync_fish) or not mc.is_active():
		return false
	if mc.source_name() == "external":
		return bool(cfg.music_sync_enabled) and float(cfg.music_sync_intensity) > 0.001
	return float(cfg.music_reactivity) > 0.001

static func tick(f, dt: float) -> void:
	if not is_finite(dt) or dt <= 0.0:
		return
	f._experience_elapsed += dt
	if f._experience_elapsed < 1.0:
		return
	var elapsed: float = minf(f._experience_elapsed, 5.0)
	f._experience_elapsed = fmod(f._experience_elapsed, 1.0)
	f._experience_response = {}
	f._experience_memory.clock = float(f._experience_memory.get("clock", 0.0)) + elapsed
	# Forget slowly; a frightening passage can become safe through later experience.
	for key in f._experience_memory.get("songs", {}):
		var old_entry: Dictionary = f._experience_memory.songs[key]
		old_entry.food = float(old_entry.get("food", 0.0)) * exp(-elapsed / 1800.0)
		old_entry.alarm = float(old_entry.get("alarm", 0.0)) * exp(-elapsed / 900.0)
	if f._sleep_depth > 0.55 and f.stress < 0.3:
		var rest: Dictionary = f._experience_memory.get("rest", {})
		var pos: Vector3 = position_from(rest.get("pos", []))
		if rest.is_empty() or pos.distance_squared_to(f.position) > 4.0:
			rest = {"pos": Saves.vec3_to_array(f.position), "confidence": 0.0}
		rest.confidence = minf(1.0, float(rest.confidence) + elapsed / 120.0)
		f._experience_memory.rest = rest
	if not listening_enabled(f) or f._sleep_depth > 0.55:
		return
	var song: Dictionary = f.music_ctx().now_playing()
	var key: String = cue(song)
	if key == "":
		return
	var entry: Dictionary = ensure_song(f, key)
	if f.stress < 0.3 and f.spooked < 0.15:
		var learning: float = lerpf(0.7, 1.3, f._trait("calm"))
		entry.familiar = minf(1.0, float(entry.familiar) + elapsed * learning / 240.0)
		entry.comfort = minf(1.0, float(entry.comfort) + elapsed * learning / 480.0)
		entry.alarm = float(entry.alarm) * exp(-elapsed / 180.0)
	entry.exposure = minf(86400.0, float(entry.exposure) + elapsed)
	var confidence: float = clampf(float(entry.exposure) / 30.0, 0.0, 1.0)
	var food: float = float(entry.food) * confidence
	var alarm: float = float(entry.alarm) * confidence
	f._experience_response = {"cue": key, "familiar": entry.familiar,
		"comfort": float(entry.comfort) * confidence, "food": food, "alarm": alarm,
		"confidence": confidence, "food_pos": entry.get("food_pos", [])}
	if alarm > 0.2:
		f._experience_response.reason = "a familiar sound; I remember a fright"
	elif food > 0.2 and f.hunger > 0.4:
		f._experience_response.reason = "this sound has accompanied food here"
	elif float(entry.familiar) > 0.2:
		f._experience_response.reason = "familiar sound; the water has been safe"

static func ensure_song(f, key: String) -> Dictionary:
	if not f._experience_memory.has("songs"):
		f._experience_memory.songs = {}
	var songs: Dictionary = f._experience_memory.songs
	if not songs.has(key):
		if songs.size() >= LIMIT:
			var weakest: String = ""
			var score: float = INF
			for old in songs:
				var value: float = float(songs[old].get("exposure", 0.0))
				if value < score:
					score = value
					weakest = old
			songs.erase(weakest)
		songs[key] = {"familiar": 0.0, "comfort": 0.0, "food": 0.0, "alarm": 0.0, "exposure": 0.0}
	return songs[key]

static func observe(f, kind: String, pos: Vector3) -> void:
	if not listening_enabled(f) or f._sleep_depth > 0.55:
		return
	var key: String = cue(f.music_ctx().now_playing())
	if key == "":
		return
	# A mouthful of several pellets or repeated startle callbacks is one encounter.
	var token: String = "experience_" + kind
	var clock: float = float(f._experience_memory.get("clock", 0.0)) + f._experience_elapsed
	if float(f._experience_memory.get(token, -100.0)) + 8.0 > clock:
		return
	f._experience_memory[token] = clock
	var entry: Dictionary = ensure_song(f, key)
	entry.exposure = minf(86400.0, float(entry.exposure) + 5.0)
	if kind == "food":
		entry.food = lerpf(float(entry.food), 1.0, 0.22)
		entry.food_pos = Saves.vec3_to_array(pos)
	elif kind == "alarm":
		entry.alarm = lerpf(float(entry.alarm), 1.0, 0.28)

static func steer(f, desired: Vector3, pace: float) -> Vector3:
	if f._experience_memory.is_empty():
		return desired
	if f.current_mode != f.Mode.CRUISE and f.current_mode != f.Mode.REST:
		return desired
	if f.stress > 0.4 or f.spooked > 0.2 or f.burst_remaining > 0.0 or f.goal_timer > 0.0:
		return desired
	var target: Vector3 = f.position
	var weight: float = 0.0
	var rest: Dictionary = f._experience_memory.get("rest", {})
	if f._sleep_depth > 0.25 and float(rest.get("confidence", 0.0)) > 0.25 and valid_position(rest.get("pos")):
		target = position_from(rest.get("pos", []))
		weight = float(rest.confidence) * 0.18
	elif f._sleep_depth < 0.2 and not f._experience_response.is_empty() and listening_enabled(f):
		var response: Dictionary = f._experience_response
		if float(response.get("food", 0.0)) > 0.2 and f.hunger > 0.4 and float(response.get("alarm", 0.0)) < 0.2 and valid_position(response.get("food_pos")):
			target = position_from(response.get("food_pos", []))
			weight = float(response.food) * minf(f.hunger, 0.8) * 0.16
	var offset: Vector3 = target - f.position
	# Ignore obsolete points far beyond the current territory; arrival fades smoothly.
	if offset.length_squared() > 144.0 or offset.length_squared() < 0.01:
		return desired
	return desired + offset.normalized() * pace * weight * minf(offset.length() / 0.8, 1.0)

static func valid_position(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for component in value:
		if not is_finite(Saves._num(component, NAN)):
			return false
	return true

static func position_from(value: Variant) -> Vector3:
	if value is Array and value.size() == 3:
		var p := Vector3(Saves._num(value[0], 0.0), Saves._num(value[1], 0.0), Saves._num(value[2], 0.0))
		if p.is_finite():
			return p
	return Vector3.ZERO

static func restore(f, value: Variant) -> void:
	f._experience_elapsed = 0.0
	f._experience_memory = {}
	f._experience_response = {}
	if not value is Dictionary:
		return
	var songs: Variant = value.get("songs", {})
	if songs is Dictionary:
		for key in songs:
			if f._experience_memory.get("songs", {}).size() >= LIMIT:
				break
			if not songs[key] is Dictionary or str(key).length() > 96:
				continue
			var entry: Dictionary = ensure_song(f, str(key))
			for field in ["familiar", "comfort", "food", "alarm"]:
				entry[field] = clampf(Saves._num(songs[key].get(field, 0.0), 0.0), 0.0, 1.0)
			entry.exposure = clampf(Saves._num(songs[key].get("exposure", 0.0), 0.0), 0.0, 86400.0)
			if valid_position(songs[key].get("food_pos")):
				entry.food_pos = Saves.vec3_to_array(position_from(songs[key].food_pos))
	var rest: Variant = value.get("rest", null)
	if rest is Dictionary and valid_position(rest.get("pos")):
		f._experience_memory.rest = {"pos": Saves.vec3_to_array(position_from(rest.pos)),
			"confidence": clampf(Saves._num(rest.get("confidence", 0.0), 0.0), 0.0, 1.0)}
	for key in ["clock", "experience_food", "experience_alarm"]:
		if value.has(key):
			f._experience_memory[key] = Saves._num(value[key], -100.0)
