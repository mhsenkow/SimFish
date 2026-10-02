extends Node

# Renders the ambient bed to a WAV so it can be measured - and listened to.
#
# Args (after --):
#   seconds=N        how long to render (default 20)
#   state=NAME       dead | healthy | stressed | thriving
#   fullbed          force the full synth bed even if the stub is selected
#   simplebed        force the potato/simple bed
#   daylight=F       override daylight smooth (1=day, ~0.1=night)
#   out=NAME         output basename under user:// (or AUDIO_PROBE_OUT)
#   legacy           apply the pre-lofi EDM groove defaults (hat/shaker/clap/
#                    build/lead) in memory, for before/after comparisons
#   voices           also mix a tank breath + three fish replies + bloops into
#                    the mix at their runtime gain, to check voice levels
#
# Prints peak / RMS / silence fraction per bus. States carry "flow"
# (creature movement): the shaker only plays above flow 0.18, so a state
# without it never exercised the percussion that was actually bothering
# players. HOLISTIC #009 — scripts/audio_baseline.sh drives the matrix.
#
# The three buses carry reverb/delay as AudioServer effects, which this does
# not capture: what lands in the file is the dry sum at bus gains.

const BUS_GAIN := {"drums": 0.251, "synth": 0.251, "air": 0.200}  # -12/-12/-14 dB

var _daylight_override: float = 1.0
var _with_voices: bool = false

const LEGACY_GROOVE := {
	"music_kick_mix": 0.5, "music_hat_mix": 0.38, "music_sidechain": 0.55,
	"music_phrase_form": "auto", "music_drop_intensity": 0.7, "music_lead_mix": 0.55,
	"music_swing": 0.06, "music_offbeat_hat": 0.55, "music_offbeat_bass_mix": 0.35,
	"music_shaker_mix": 0.4, "music_clap_mix": 0.45, "music_build_drama": 0.7,
}


func _apply_legacy_groove() -> void:
	var cfg: Node = get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
	for k in LEGACY_GROOVE.keys():
		cfg.set(k, LEGACY_GROOVE[k])

const STATES := {
	"dead": {"aeration": 0.0, "o2": 0.15, "vitality": 0.05, "fish": 0.1,
		"plants": 0.1, "clarity": 0.2, "nitrate": 0.9, "algae": 0.8,
		"activity": 0.05, "temp": 0.5, "ph": 0.4},
	"stressed": {"aeration": 0.25, "o2": 0.35, "vitality": 0.35, "fish": 0.4,
		"plants": 0.3, "clarity": 0.4, "nitrate": 0.7, "algae": 0.6,
		"activity": 0.3, "temp": 0.55, "ph": 0.45, "flow": 0.3},
	"healthy": {"aeration": 0.7, "o2": 0.8, "vitality": 0.7, "fish": 0.6,
		"plants": 0.6, "clarity": 0.8, "nitrate": 0.25, "algae": 0.2,
		"activity": 0.6, "temp": 0.5, "ph": 0.5, "flow": 0.45},
	"thriving": {"aeration": 0.95, "o2": 0.95, "vitality": 0.95, "fish": 0.85,
		"plants": 0.9, "clarity": 0.95, "nitrate": 0.1, "algae": 0.1,
		"activity": 0.9, "temp": 0.5, "ph": 0.5, "flow": 0.7},
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
	var force_simple: bool = false
	for a in args:
		if a.begins_with("seconds="):
			seconds = float(a.split("=")[1])
		elif a.begins_with("state="):
			state = a.split("=")[1]
		elif a.begins_with("out="):
			out_name = a.split("=")[1]
		elif a == "fullbed":
			force_full = true
		elif a == "simplebed":
			force_simple = true
		elif a.begins_with("daylight="):
			_daylight_override = float(a.split("=")[1])
		elif a == "legacy":
			_apply_legacy_groove()
		elif a == "voices":
			_with_voices = true

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
		elif force_simple:
			n.set("_cached_potato_bed", true)
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

	if _with_voices:
		_mix_voices(n, mix, mix_r, rate)
	var out_root: String = OS.get_environment("AUDIO_PROBE_OUT").strip_edges()
	if out_root == "":
		out_root = "user://"
	elif not out_root.ends_with("/") and not out_root.ends_with("://"):
		out_root += "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_root))
	_write_wav("%s%s.wav" % [out_root, out_name], mix, mix_r, rate)
	for k in per_bus.keys():
		_write_wav("%s%s_%s.wav" % [out_root, out_name, k],
			per_bus[k], per_bus[k], rate)
	for k in per_bus.keys():
		_print_stats(k, per_bus[k], BUS_GAIN[k])
	_print_stats("mix", mix, 1.0)
	print("[audio] state=%s frames=%d rate=%d daylight=%.2f full=%s simple=%s -> %s" % [
		state, mix.size(), rate, _daylight_override, force_full, force_simple,
		ProjectSettings.globalize_path(out_root)])
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


# Mix voices in at the gain the game would give them (player volume_db =
# music x event gain + trim), relative to the bed's -12 dB player gain.
func _mix_voices(n: Node, mix: PackedFloat32Array, mix_r: PackedFloat32Array,
		rate: int) -> void:
	var V: GDScript = load("res://scripts/tank_voice_audio.gd")
	var gain_db: float = float(n.call("_voice_gain_db"))
	var plan: Array = [
		[2.0, V.voice_params("tank", 1, 60)],
		[4.0, V.voice_params("fish", 11, 40, 0.1, 0.8)],
		[5.5, V.voice_params("fish", 22, 40, 0.5, 0.5)],
		[7.0, V.voice_params("fish", 33, 40, 0.9, 0.2)],
		[9.0, V.voice_params("bloop", 44, 0, 0.4)],
		[10.0, V.voice_params("plop", 55, 0)],
		[11.0, V.voice_params("bubble_rise", 66, 0)],
		[12.0, V.voice_params("gulp", 77, 0, 0.6)],
	]
	var voice_only := PackedFloat32Array()
	voice_only.resize(mix.size())
	voice_only.fill(0.0)
	for e in plan:
		var p: Dictionary = e[1]
		var g: float = db_to_linear(gain_db + float(V.VOICE_TRIM_DB) + float(p.get("trim_db", 0.0)))
		var smp: PackedFloat32Array = V.render(p, rate)
		var at: int = int(float(e[0]) * float(rate))
		for i in smp.size():
			if at + i >= mix.size():
				break
			mix[at + i] += smp[i] * g
			mix_r[at + i] += smp[i] * g
			voice_only[at + i] += smp[i] * g
		var seg := smp.duplicate()
		for i in seg.size():
			seg[i] *= g
		_print_stats("voice:" + String(p["kind"]), seg, 1.0)
	_print_stats("voices", voice_only, 1.0)


func _print_stats(label: String, buf: PackedFloat32Array, gain: float) -> void:
	var peak: float = 0.0
	var acc: float = 0.0
	var cnt: int = 0
	var silent: int = 0
	for v in buf:
		var x: float = v * gain
		peak = maxf(peak, absf(x))
		if absf(x) > 1e-7:
			acc += x * x
			cnt += 1
		else:
			silent += 1
	var rms: float = sqrt(acc / float(maxi(cnt, 1)))
	var silence_frac: float = float(silent) / float(maxi(buf.size(), 1))
	print("[audio] %-18s peak %6.1f dBFS  rms %6.1f dBFS  silence_frac %.3f (active samples)" % [
		label, linear_to_db(maxf(peak, 1e-9)), linear_to_db(maxf(rms, 1e-9)), silence_frac])
