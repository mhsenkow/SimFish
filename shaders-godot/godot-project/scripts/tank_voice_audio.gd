extends Node

# Procedural creature voices: the tank mind's low "breath" and the fishes'
# tiny bubble babble, plus the quiet bloops that mark thoughts and small
# real events (a gulp at the surface, food touching the water, a snail
# letting go of a stem).
#
# Owned by AmbientAudio (it creates this as a child and gates it on the
# music/event settings); nothing else should instance it.
#
# WHY PRE-RENDERED ONE-SHOTS AND NOT THE SYNTH THREAD. The ambient bed is a
# sample-clock synth on a worker thread with a fixed voice budget. A voice is
# a short, self-contained sound that has to start exactly when a line of
# text appears - so it is rendered once into an AudioStreamWAV (deterministic
# per seed, cached) and played on a small pool of players. That keeps the
# bed's hot loop untouched and makes every voice testable as plain samples.
#
# NOTHING HARSH. Every voice has a smooth sin^n envelope (no clicks at either
# end), a one-pole low-pass at or under ~4.5 kHz, and is normalised to a
# fixed peak so no seed can come out louder than another.

const RATE: int = 22050
const INV_RATE: float = 1.0 / 22050.0

# Budget. Voices (tank + fish replies) and bloops have separate caps so a
# chatter of thought-bloops can never block a reply someone is reading.
const MAX_ACTIVE_VOICES: int = 2
const MAX_ACTIVE_BLOOPS: int = 2
const MAX_QUEUE: int = 3
const QUEUE_STALE_S: float = 2.5
const MIN_VOICE_GAP_S: float = 0.22
const MIN_BLOOP_GAP_S: float = 0.9
const POOL_SIZE: int = 4
const CACHE_MAX: int = 16

# Level. Rendered peaks are normalised to `amp` (never above PEAK_CEILING);
# the player then sits VOICE_TRIM_DB under the user's music x event gain so a
# voice lands roughly level with the bed's peaks - present, never on top.
const PEAK_CEILING: float = 0.4
const VOICE_TRIM_DB: float = -12.0

const VOICE_KINDS: PackedStringArray = ["tank", "fish"]
const BLOOP_KINDS: PackedStringArray = [
	"bloop", "gulp", "plop", "snail", "ignite", "bubble_rise",
]

var _players: Array[AudioStreamPlayer] = []
var _active: Array = []   # [{class, end_s}]
var _queue: Array = []    # [{params, class, at_s, gain_db}]
var _cache: Dictionary = {}
var _cache_order: Array = []
var _renders: Array = []  # [{task, holder, key, vol}] in-flight worker renders
var _now_s: float = 0.0
var _last_start: Dictionary = {"voice": -100.0, "bloop": -100.0}
var _bus: String = "Master"


func _ready() -> void:
	_bus = _resolve_bus(["Music_Synth", "Music", "Master"])
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = _bus
		p.name = "Voice%d" % i
		add_child(p)
		_players.append(p)


func _process(dt: float) -> void:
	tick(dt)


# ---------------------------------------------------------------------------
# Public API (called by AmbientAudio)
# ---------------------------------------------------------------------------

# Queue a sound. `gain_db` is the user's music x event gain in dB (AmbientAudio
# computes it and refuses to call at all when audio is muted). Returns false
# when the request was dropped by the rate limiter.
func request(params: Dictionary, gain_db: float) -> bool:
	if params.is_empty():
		return false
	var cls: String = sound_class(String(params.get("kind", "")))
	if _can_start(cls):
		_start(params, cls, gain_db)
		return true
	if _queue.size() >= MAX_QUEUE:
		return false
	# One queued bloop at a time: bloops are texture, not content.
	if cls == "bloop":
		for q in _queue:
			if String(q["class"]) == "bloop":
				return false
	_queue.append({"params": params, "class": cls, "at_s": _now_s, "gain_db": gain_db})
	return true


func active_count(cls: String = "") -> int:
	var n: int = 0
	for a in _active:
		if cls == "" or String(a["class"]) == cls:
			n += 1
	return n


func queued_count() -> int:
	return _queue.size()


# True while any voice (not bloop) is sounding or waiting: AmbientAudio ducks
# the bed under a conversation.
func is_talking() -> bool:
	return active_count("voice") > 0 or not _queue.filter(
		func(q): return String(q["class"]) == "voice").is_empty()


func stop_all() -> void:
	for r in _renders:
		WorkerThreadPool.wait_for_task_completion(int(r["task"]))
	_renders.clear()
	_queue.clear()
	_active.clear()
	for p in _players:
		if is_instance_valid(p):
			p.stop()


# Advances the limiter clock. Driven by _process in the game; smokes call it
# directly so rate limiting is testable without an audio device.
func tick(dt: float) -> void:
	_now_s += maxf(dt, 0.0)
	_poll_renders()
	for i in range(_active.size() - 1, -1, -1):
		if float(_active[i]["end_s"]) <= _now_s:
			_active.remove_at(i)
	for i in range(_queue.size() - 1, -1, -1):
		if _now_s - float(_queue[i]["at_s"]) > QUEUE_STALE_S:
			_queue.remove_at(i)
	var i2: int = 0
	while i2 < _queue.size():
		var q: Dictionary = _queue[i2]
		if _can_start(String(q["class"])):
			_queue.remove_at(i2)
			_start(q["params"], String(q["class"]), float(q["gain_db"]))
		else:
			i2 += 1


# ---------------------------------------------------------------------------
# Pure, deterministic parameter + sample generation (smoke-tested)
# ---------------------------------------------------------------------------

static func sound_class(kind: String) -> String:
	return "voice" if kind in VOICE_KINDS else "bloop"


# Integer hash -> 0..1. Deterministic across runs and platforms (no randf).
static func h01(seed_v: int, salt: int) -> float:
	var x: int = (seed_v * 73856093) ^ (salt * 19349663) ^ 0x5bd1e995
	x = (x ^ (x >> 13)) * 1274126177
	x = x ^ (x >> 16)
	return float(x & 0xFFFF) / 65535.0


# size01: 0 = tiny fish, 1 = big fish. bold01: 0 = shy, 1 = bold.
# length: characters in the line being spoken (scales the babble).
# variant: reshuffles the syllable contour without moving the fish's pitch,
# so one fish keeps a recognisable voice while no two replies sound alike.
static func voice_params(kind: String, seed_v: int, length: int = 24,
		size01: float = 0.5, bold01: float = 0.5, variant: int = 0) -> Dictionary:
	var cs: int = seed_v + variant * 7919
	var sz: float = clampf(size01, 0.0, 1.0)
	var bd: float = clampf(bold01, 0.0, 1.0)
	var ln: int = clampi(length, 0, 400)
	var p: Dictionary = {
		"kind": kind, "seed": seed_v, "base_hz": 440.0, "brightness": 0.0,
		"syllables": [], "noise": 0.0, "amp": 0.2, "lpf_hz": 3200.0,
		"breath": false, "trim_db": 0.0, "variant": variant,
	}
	match kind:
		"tank":
			# A slow in-out swell on a low fundamental with two soft partials
			# and a breath of filtered air - felt more than heard.
			var dur: float = clampf(1.1 + float(ln) * 0.018, 1.2, 2.6)
			p["base_hz"] = lerpf(62.0, 84.0, h01(seed_v, 1))
			p["breath"] = true
			p["noise"] = 0.16
			p["amp"] = 0.36
			p["lpf_hz"] = 900.0
			p["trim_db"] = 1.5   # low frequencies read quieter
			p["syllables"] = [{"t": 0.0, "len": dur, "mult": 1.0, "glide": -0.03}]
		"fish":
			# Small fish are higher, big fish lower; bold fish are brighter
			# (more FM sparkle) and talk with shorter gaps.
			p["base_hz"] = lerpf(1250.0, 330.0, sz) * lerpf(0.93, 1.07, h01(seed_v, 1))
			p["brightness"] = lerpf(0.05, 0.55, bd)
			p["lpf_hz"] = lerpf(2600.0, 4500.0, bd)
			p["amp"] = 0.3
			p["noise"] = 0.05
			var count: int = clampi(int(round(float(ln) / 9.0)), 2, 7)
			var syl_len: float = lerpf(0.055, 0.1, sz) * lerpf(0.9, 1.1, h01(seed_v, 2))
			var gap: float = lerpf(0.06, 0.03, bd)
			var t: float = 0.0
			var syls: Array = []
			for i in count:
				syls.append({
					"t": t,
					"len": syl_len * lerpf(0.8, 1.2, h01(cs, 20 + i)),
					"mult": lerpf(0.85, 1.2, h01(cs, 10 + i)),
					"glide": lerpf(-0.25, 0.15, h01(cs, 30 + i)),
				})
				t += syl_len + gap * lerpf(0.7, 1.4, h01(cs, 40 + i))
			p["syllables"] = syls
		"bloop":
			# A fish had a thought: one tiny rising bloop.
			p["base_hz"] = lerpf(900.0, 380.0, sz) * lerpf(0.94, 1.06, h01(seed_v, 1))
			p["amp"] = 0.16
			p["lpf_hz"] = 2400.0
			p["trim_db"] = -3.0
			p["syllables"] = [{"t": 0.0, "len": 0.09, "mult": 1.0, "glide": 0.35}]
		"gulp":
			p["base_hz"] = lerpf(560.0, 300.0, sz) * lerpf(0.94, 1.06, h01(seed_v, 1))
			p["amp"] = 0.14
			p["lpf_hz"] = 2200.0
			p["noise"] = 0.08
			p["trim_db"] = -4.0
			p["syllables"] = [
				{"t": 0.0, "len": 0.06, "mult": 1.0, "glide": 0.5},
				{"t": 0.09, "len": 0.05, "mult": 1.25, "glide": 0.4},
			]
		"plop":
			# Food touching the water: a low rising plop with a little splash.
			p["base_hz"] = lerpf(240.0, 300.0, h01(seed_v, 1))
			p["amp"] = 0.18
			p["lpf_hz"] = 2000.0
			p["noise"] = 0.14
			p["trim_db"] = -3.0
			p["syllables"] = [{"t": 0.0, "len": 0.12, "mult": 1.0, "glide": 0.8}]
		"snail":
			p["base_hz"] = lerpf(160.0, 200.0, h01(seed_v, 1))
			p["amp"] = 0.15
			p["lpf_hz"] = 1400.0
			p["trim_db"] = -4.0
			p["syllables"] = [{"t": 0.0, "len": 0.14, "mult": 1.0, "glide": -0.2}]
		"ignite":
			# The whole tank noticed something: two soft low tones, a fifth apart.
			p["base_hz"] = lerpf(200.0, 240.0, h01(seed_v, 1))
			p["amp"] = 0.14
			p["lpf_hz"] = 1600.0
			p["trim_db"] = -3.0
			p["syllables"] = [
				{"t": 0.0, "len": 0.16, "mult": 1.0, "glide": 0.05},
				{"t": 0.14, "len": 0.2, "mult": 1.5, "glide": 0.0},
			]
		"bubble_rise":
			# A little column of bubbles letting go: pops climbing in pitch.
			var n: int = 4 + int(h01(seed_v, 2) * 2.99)
			p["base_hz"] = lerpf(620.0, 820.0, h01(seed_v, 1))
			p["amp"] = 0.08
			p["lpf_hz"] = 3000.0
			p["noise"] = 0.06
			p["trim_db"] = -6.0
			var tt: float = 0.0
			var pops: Array = []
			for i in n:
				pops.append({"t": tt, "len": 0.035, "mult": 1.0 + 0.12 * float(i),
					"glide": 0.3})
				tt += lerpf(0.05, 0.14, h01(seed_v, 50 + i))
			p["syllables"] = pops
		_:
			return {}
	p["amp"] = minf(float(p["amp"]), PEAK_CEILING)
	return p


static func duration_s(p: Dictionary) -> float:
	var end: float = 0.0
	for s in p.get("syllables", []):
		end = maxf(end, float(s["t"]) + float(s["len"]))
	return end + 0.02


# Mono float samples in -amp..amp. Pure function of the params.
static func render(p: Dictionary, rate: int = RATE) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if p.is_empty():
		return out
	var n: int = maxi(1, int(duration_s(p) * float(rate)))
	out.resize(n)
	out.fill(0.0)
	var inv: float = 1.0 / float(rate)
	var base: float = float(p["base_hz"])
	var bright: float = float(p["brightness"])
	var noise_amt: float = float(p["noise"])
	var breath: bool = bool(p["breath"])
	var noise_state: int = int(p["seed"]) * 2654435761 + 1
	var noise_lpf: float = 0.0
	var noise_a: float = _alpha(420.0 if breath else 1800.0, rate)
	for s in p["syllables"]:
		var t0: int = int(float(s["t"]) * float(rate))
		var len_n: int = maxi(8, int(float(s["len"]) * float(rate)))
		var f0: float = base * float(s["mult"])
		var glide: float = float(s["glide"])
		var phase: float = 0.0
		var mod_phase: float = 0.0
		for k in len_n:
			var idx: int = t0 + k
			if idx >= n:
				break
			var u: float = float(k) / float(len_n)
			var f: float = f0 * (1.0 + glide * u)
			phase = fposmod(phase + f * inv, 1.0)
			var env: float
			var body: float
			if breath:
				# Faster in, slower out, with a gentle 0.35 Hz waver.
				var shaped: float = pow(u, 0.7)
				env = pow(sin(PI * shaped), 2.0) * (1.0 + 0.12 * sin(TAU * 0.35 * float(k) * inv))
				body = sin(phase * TAU) + 0.35 * sin(phase * TAU * 2.0) \
					+ 0.12 * sin(phase * TAU * 3.01)
				body *= 0.68
			else:
				env = pow(sin(PI * u), 1.6)
				mod_phase = fposmod(mod_phase + f * 2.0 * inv, 1.0)
				body = sin(phase * TAU + sin(mod_phase * TAU) * bright * 1.6) \
					+ 0.18 * sin(phase * TAU * 2.0)
			var ns: float = 0.0
			if noise_amt > 0.0:
				noise_state = (noise_state * 1103515245 + 12345) & 0x7FFFFFFF
				var white: float = float(noise_state & 0xFFFF) / 32767.5 - 1.0
				noise_lpf += (white - noise_lpf) * noise_a
				ns = noise_lpf * noise_amt * 3.0
			out[idx] += (body + ns) * env
	# Tone: one-pole low-pass (cheap tape warmth), then normalise to amp.
	var a: float = _alpha(float(p["lpf_hz"]), rate)
	var y: float = 0.0
	var peak: float = 0.0
	for i in n:
		y += (out[i] - y) * a
		out[i] = y
		peak = maxf(peak, absf(y))
	if peak > 1e-6:
		var g: float = float(p["amp"]) / peak
		for i in n:
			out[i] *= g
	# Guarantee silence at both ends (no click on start/stop).
	var fade: int = mini(64, n >> 1)
	for i in fade:
		var w: float = float(i) / float(fade)
		out[i] *= w
		out[n - 1 - i] *= w
	return out


static func _alpha(cutoff_hz: float, rate: int) -> float:
	var rc: float = 1.0 / (TAU * maxf(40.0, cutoff_hz))
	var dt: float = 1.0 / float(rate)
	return dt / (rc + dt)


static func to_wav(samples: PackedFloat32Array, rate: int = RATE) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _can_start(cls: String) -> bool:
	var cap: int = MAX_ACTIVE_VOICES if cls == "voice" else MAX_ACTIVE_BLOOPS
	var gap: float = MIN_VOICE_GAP_S if cls == "voice" else MIN_BLOOP_GAP_S
	return active_count(cls) < cap and _now_s - float(_last_start.get(cls, -100.0)) >= gap


func _start(params: Dictionary, cls: String, gain_db: float) -> void:
	_last_start[cls] = _now_s
	_active.append({"class": cls, "end_s": _now_s + duration_s(params) + 0.05})
	var vol: float = clampf(gain_db + VOICE_TRIM_DB + float(params.get("trim_db", 0.0)),
		-80.0, 0.0)
	var key: String = _cache_key(params)
	if _cache.has(key):
		_play(_cache[key], vol)
		return
	# Render off the main thread: a 2.5 s tank breath is ~30 ms of GDScript,
	# a visible hitch while someone is typing. It starts a frame or two late
	# instead, which nobody can hear.
	var holder: Dictionary = {"samples": PackedFloat32Array()}
	var task: int = WorkerThreadPool.add_task(func() -> void:
		holder["samples"] = render(params))
	_renders.append({"task": task, "holder": holder, "key": key, "vol": vol})


func _poll_renders() -> void:
	for i in range(_renders.size() - 1, -1, -1):
		var r: Dictionary = _renders[i]
		if not WorkerThreadPool.is_task_completed(int(r["task"])):
			continue
		WorkerThreadPool.wait_for_task_completion(int(r["task"]))
		_renders.remove_at(i)
		var w: AudioStreamWAV = to_wav(r["holder"]["samples"])
		_cache_put(String(r["key"]), w)
		_play(w, float(r["vol"]))


func _play(w: AudioStreamWAV, vol: float) -> void:
	var player: AudioStreamPlayer = _free_player()
	if player == null:
		return
	player.stream = w
	player.volume_db = vol
	player.play()


func _exit_tree() -> void:
	for r in _renders:
		WorkerThreadPool.wait_for_task_completion(int(r["task"]))
	_renders.clear()


func _free_player() -> AudioStreamPlayer:
	for p in _players:
		if is_instance_valid(p) and not p.playing:
			return p
	return null


func _cache_key(params: Dictionary) -> String:
	return "%s|%d|%d|%d|%.2f|%.3f" % [
		String(params["kind"]), int(params["seed"]), int(params.get("variant", 0)),
		(params["syllables"] as Array).size(), float(params["base_hz"]),
		float(params["brightness"])]


func _cache_put(key: String, w: AudioStreamWAV) -> void:
	if not _cache.has(key):
		_cache_order.append(key)
	_cache[key] = w
	while _cache_order.size() > CACHE_MAX:
		_cache.erase(_cache_order.pop_front())


func _resolve_bus(names: Array) -> String:
	for b in names:
		if AudioServer.get_bus_index(String(b)) >= 0:
			return String(b)
	return "Master"
