extends Node

# Renders the ambient bed to a WAV so it can be measured - and listened to.
#
# Args (after --):
#   seconds=N        how long to render (default 20)
#   state=NAME       dead | healthy | stressed | thriving
#   fullbed          force the full synth bed even if the stub is selected
#   out=NAME         output basename under user://
#
# The three buses carry reverb/delay as AudioServer effects, which this does
# not capture: what lands in the file is the dry sum at bus gains.

const BUS_GAIN := {"drums": 0.251, "synth": 0.251, "air": 0.200}  # -12/-12/-14 dB

var _daylight_override: float = 1.0

const STATES := {
	"dead": {"aeration": 0.0, "o2": 0.15, "vitality": 0.05, "fish": 0.1,
		"plants": 0.1, "clarity": 0.2, "nitrate": 0.9, "algae": 0.8,
		"activity": 0.05, "temp": 0.5, "ph": 0.4},
	"stressed": {"aeration": 0.25, "o2": 0.35, "vitality": 0.35, "fish": 0.4,
		"plants": 0.3, "clarity": 0.4, "nitrate": 0.7, "algae": 0.6,
		"activity": 0.3, "temp": 0.55, "ph": 0.45},
	"healthy": {"aeration": 0.7, "o2": 0.8, "vitality": 0.7, "fish": 0.6,
		"plants": 0.6, "clarity": 0.8, "nitrate": 0.25, "algae": 0.2,
		"activity": 0.6, "temp": 0.5, "ph": 0.5},
	"thriving": {"aeration": 0.95, "o2": 0.95, "vitality": 0.95, "fish": 0.85,
		"plants": 0.9, "clarity": 0.95, "nitrate": 0.1, "algae": 0.1,
		"activity": 0.9, "temp": 0.5, "ph": 0.5},
}


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var n: Node = get_node_or_null("/root/AudioProbe/AmbientAudio")
	if n == null:
		print("[audio] node missing"); get_tree().quit(1); return

	var args: PackedStringArray = OS.get_cmdline_user_args()
	var seconds: float = 20.0
	var state: String = "healthy"
	var out_name: String = "ambient_probe"
	var force_full: bool = false
	for a in args:
		if a.begins_with("seconds="):
			seconds = float(a.split("=")[1])
		elif a.begins_with("state="):
			state = a.split("=")[1]
		elif a.begins_with("out="):
			out_name = a.split("=")[1]
		elif a == "fullbed":
			force_full = true
		elif a.begins_with("daylight="):
			_daylight_override = float(a.split("=")[1])

	if STATES.has(state):
		var sm: Dictionary = n.get("_smooth")
		sm["daylight"] = _daylight_override
		for k in STATES[state].keys():
			sm[k] = STATES[state][k]
		n.set("_smooth", sm)
		n.set("_prev_snap", sm.duplicate())
		n.set("_tank_vitality", float(STATES[state].get("vitality", 0.5)))
	# _refresh_mix_cache is what turns _smooth into the cached snapshot the
	# synth worker reads. _process normally calls it on an interval, right
	# after refreshing the environment from the sim - which this must NOT do,
	# since there is no sim and it would wipe the state set above.
	n.call("_refresh_mix_cache")

	var rate: int = n.get("SAMPLE_RATE") if n.get("SAMPLE_RATE") != null else 22050
	var total: int = int(seconds * float(rate))
	var mix := PackedFloat32Array()
	var mix_r := PackedFloat32Array()
	var per_bus := {"drums": PackedFloat32Array(), "synth": PackedFloat32Array(),
		"air": PackedFloat32Array()}
	var done: int = 0
	var batch: int = 2048
	while done < total:
		n.call("_refresh_mix_cache")
		if force_full:
			n.set("_cached_potato_bed", false)
		n.call("_run_synth_batch", batch)
		var qd = n.get("_synth_queue_drums")
		var qs = n.get("_synth_queue_synth")
		var qa = n.get("_synth_queue_air")
		var cnt: int = mini(qd.size(), mini(qs.size(), qa.size()))
		for i in cnt:
			var d: Vector2 = qd[i]
			var sy: Vector2 = qs[i]
			var ai: Vector2 = qa[i]
			per_bus["drums"].append(d.x)
			per_bus["synth"].append(sy.x)
			per_bus["air"].append(ai.x)
			mix.append(d.x * BUS_GAIN["drums"] + sy.x * BUS_GAIN["synth"]
				+ ai.x * BUS_GAIN["air"])
			mix_r.append(d.y * BUS_GAIN["drums"] + sy.y * BUS_GAIN["synth"]
				+ ai.y * BUS_GAIN["air"])
		done += cnt
		n.call("_drain_synth_queues", -1)
		if cnt == 0:
			break

	_write_wav("user://%s.wav" % out_name, mix, mix_r, rate)
	for k in per_bus.keys():
		_write_wav("user://%s_%s.wav" % [out_name, k],
			per_bus[k], per_bus[k], rate)
	print("[audio] state=%s frames=%d rate=%d -> %s" % [
		state, mix.size(), rate, ProjectSettings.globalize_path("user://")])
	get_tree().quit(0)


func _write_wav(path: String, l: PackedFloat32Array, r: PackedFloat32Array,
		rate: int) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	var n: int = l.size()
	var data_bytes: int = n * 4
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + data_bytes)
	f.store_buffer("WAVE".to_ascii_buffer())
	f.store_buffer("fmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(2)
	f.store_32(rate)
	f.store_32(rate * 4)
	f.store_16(4)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(data_bytes)
	for i in n:
		f.store_16(int(clampf(l[i], -1.0, 1.0) * 32767.0))
		f.store_16(int(clampf(r[i] if i < r.size() else l[i], -1.0, 1.0) * 32767.0))
	f.close()
