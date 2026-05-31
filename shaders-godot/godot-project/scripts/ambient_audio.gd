# Generative ambient + trance audio driven by live tank state.
#
# Harmony, tempo, arp patterns, and density track smoothed sim metrics
# (daylight, bloom, O₂, fish, plants, biomass, aeration). Phrases shift when
# the ecosystem meaningfully changes — not a fixed loop.

extends Node

const SAMPLE_RATE: int = 22050
const DELAY_LEN: int = 4096
const MAX_SAMPLES_PER_FRAME: int = 512
const BUBBLE_MAX: int = 5
const ENV_REFRESH_INTERVAL: float = 0.1
const INV_SAMPLE_RATE: float = 1.0 / 22050.0

const SCALE_MAJOR: Array[float] = [
	261.63, 293.66, 329.63, 392.00, 440.00,
	523.25, 587.33, 659.25, 783.99, 880.00,
]

const SCALE_MINOR: Array[float] = [
	220.00, 261.63, 293.66, 329.63, 392.00,
	440.00, 523.25, 587.33, 659.25, 783.99,
]

const SCALE_DEEP: Array[float] = [
	110.00, 130.81, 146.83, 164.81, 196.00,
	220.00, 261.63, 293.66, 329.63, 392.00,
]

# Arp banks — pattern picked from current tank character.
const ARP_BANK: Array = [
	[0, 4, 7, 4, 2, 7, 4, 0, 0, 4, 9, 4, 2, 7, 4, 2],
	[0, 2, 4, 7, 4, 2, 0, 2, 4, 7, 9, 7, 4, 2, 0, 0],
	[0, 7, 4, 0, 2, 4, 7, 2, 0, 4, 2, 7, 4, 0, 2, 4],
	[0, 0, 4, 4, 7, 7, 4, 2, 0, 4, 7, 4, 2, 2, 0, 0],
	[0, 5, 3, 7, 5, 3, 0, 5, 7, 3, 5, 0, 7, 5, 3, 0],
	[0, 4, 2, 4, 7, 4, 2, 0, 3, 5, 7, 5, 3, 2, 0, 4],
]

const CHORD_DAY: Array[int] = [0, 4, 2, 5, 3, 0, 2, 4]
const CHORD_NIGHT: Array[int] = [0, 5, 3, 4, 2, 5, 0, 3]

var _stream_player: AudioStreamPlayer = null
var _playback: AudioStreamGeneratorPlayback = null
var _pending: Array = []
var _bubble_bursts: Array = []

var _bubble_t: float = 0.0
var _accent_t: float = 0.0
var _sim_ref: Node = null
var _world_ref: Node = null

var _env: Dictionary = {
	"daylight": 1.0,
	"day_phase": 0.25,
	"bloom": 0.0,
	"o2": 0.85,
	"aeration": 0.0,
	"flow": 0.0,
	"fish": 0,
	"plants": 0,
	"biomass": 0,
	"saltwater": false,
	"tannins": 0.0,
}

var _smooth: Dictionary = {}
var _prev_snap: Dictionary = {}
var _tank_vitality: float = 0.35
var _active_arp_idx: int = 0
var _phrase_idx: int = 0
var _bars_per_phrase: int = 4
var _daylight_zone: int = 1
var _arp_octave: int = 0
var _sixteenth_div: int = 1

# Trance bed state (sample-accurate timing).
var _sample_clock: int = 0
var _last_quarter: int = -1
var _last_sixteenth: int = -1
var _last_sixteenth_raw: int = -1
var _chord_root: int = 0
var _kick_env: float = 0.0
var _kick_phase: float = 0.0
var _kick_pitch: float = 68.0
var _sidechain: float = 1.0
var _arp_env: float = 0.0
var _arp_freq: float = 440.0
var _arp_phase: float = 0.0
var _bass_phase: float = 0.0
var _bass_freq: float = 110.0
var _hat_env: float = 0.0
var _pad_phases: Array[float] = [0.0, 0.0, 0.0]
var _lpf_arp: float = 0.0
var _lpf_pad: float = 0.0
var _lpf_hat: float = 0.0
var _lpf_master: float = 0.0
var _lfo_phase: float = 0.0
var _delay_buf: PackedFloat32Array = PackedFloat32Array()
var _delay_pos: int = 0
var _noise_seed: int = 12345
var _env_accum: float = 0.0

# Cached mix params — refreshed ~20 Hz, not per audio sample.
var _cached_scale: Array[float] = SCALE_MAJOR
var _pad_increments: Array[float] = [0.0, 0.0, 0.0]
var _cached_bpm: float = 110.0
var _cached_beat_scale: float = 110.0 / 60.0 * INV_SAMPLE_RATE
var _cached_vol: float = 0.35
var _cached_kick_mix: float = 0.65
var _cached_bass_mix: float = 0.75
var _cached_arp_mix: float = 0.85
var _cached_pad_mix: float = 0.7
var _cached_hat_mix: float = 0.55
var _cached_kick_gain: float = 0.3
var _cached_bass_amp: float = 0.1
var _cached_pad_level: float = 0.025
var _cached_arp_level: float = 0.08
var _cached_hat_mul: float = 0.05
var _cached_pad_lpf_alpha: float = 0.08
var _cached_arp_lpf_alpha: float = 0.12
var _cached_lfo_hz: float = 0.08
var _cached_energy: float = 0.55
var _cached_arp_decay: float = 0.995
var _cached_bass_active: bool = true
var _arp_inc: float = 440.0 * INV_SAMPLE_RATE
var _arp_inc_target: float = 440.0 * INV_SAMPLE_RATE
var _bass_inc: float = 110.0 * INV_SAMPLE_RATE
var _dc_x_prev: float = 0.0
var _dc_y_prev: float = 0.0
var _kick_pitch_decay: float = 28.0 * INV_SAMPLE_RATE


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = SAMPLE_RATE
	gen.buffer_length = 0.1
	_stream_player = AudioStreamPlayer.new()
	_stream_player.stream = gen
	_stream_player.volume_db = -12.0
	add_child(_stream_player)
	_stream_player.play()
	_playback = _stream_player.get_stream_playback() as AudioStreamGeneratorPlayback
	_delay_buf.resize(DELAY_LEN)
	_delay_buf.fill(0.0)
	_chord_root = 0
	_smooth = _env.duplicate()
	_prev_snap = _env.duplicate()
	_pick_arp_from_tank(true)
	_accent_t = 4.0
	_rebuild_tonal_cache()
	_refresh_mix_cache()


func _cfg() -> Node:
	return get_node_or_null("/root/TankConfig")


func _master_enabled() -> bool:
	var cfg := _cfg()
	return bool(cfg.music_enabled) if cfg != null else true


func _ambient_enabled() -> bool:
	if not _master_enabled():
		return false
	var cfg := _cfg()
	return bool(cfg.music_ambient_enabled) if cfg != null else true


func _events_enabled() -> bool:
	if not _master_enabled():
		return false
	var cfg := _cfg()
	return bool(cfg.music_events_enabled) if cfg != null else true


func _environment_enabled() -> bool:
	if not _master_enabled():
		return false
	var cfg := _cfg()
	return bool(cfg.music_environment_enabled) if cfg != null else true


func _reactivity() -> float:
	var cfg := _cfg()
	return clampf(float(cfg.music_reactivity), 0.0, 1.0) if cfg != null else 0.65


func _event_gain() -> float:
	var cfg := _cfg()
	return clampf(float(cfg.music_event_volume), 0.0, 1.0) if cfg != null else 0.75


func _user_volume() -> float:
	var cfg := _cfg()
	return clampf(float(cfg.music_volume), 0.0, 1.0) if cfg != null else 0.7


func _complexity() -> float:
	var cfg := _cfg()
	return clampf(float(cfg.music_complexity), 0.0, 1.0) if cfg != null else 0.5


func _energy() -> float:
	var cfg := _cfg()
	return clampf(float(cfg.music_energy), 0.0, 1.0) if cfg != null else 0.55


func _style() -> String:
	var cfg := _cfg()
	return String(cfg.music_style) if cfg != null else "hybrid"


func _trance_bed_active() -> bool:
	if not _ambient_enabled() or _complexity() <= 0.06:
		return false
	var st: String = _style()
	return st == "trance" or st == "hybrid"


func _plink_bed_active() -> bool:
	var st: String = _style()
	return _ambient_enabled() and (st == "ambient" or (st == "hybrid" and _complexity() < 0.45))


func silence_immediately() -> void:
	_pending.clear()
	_bubble_bursts.clear()
	_kick_env = 0.0
	_sidechain = 1.0
	if _stream_player != null:
		_stream_player.volume_db = -80.0


func _drive() -> float:
	return maxf(_cfg_float("music_coupling_floor", 0.55), _reactivity())


func _cfg_float(key: String, default: float) -> float:
	var cfg := _cfg()
	if cfg == null:
		return default
	var v = cfg.get(key)
	if v == null:
		return default
	return clampf(float(v), 0.0, 2.0)


func _influence(key: String) -> float:
	return clampf(_cfg_float(key, 1.0), 0.0, 2.0)


func _music_seed() -> int:
	var cfg := _cfg()
	return int(cfg.music_seed) if cfg != null else 1


func _seed_mix(salt: int) -> float:
	var s: int = (_music_seed() * 1103515245 + salt * 12345) & 0x7FFFFFFF
	return float(s % 1000) / 1000.0


func _refresh_environment() -> void:
	if _sim_ref == null or not is_instance_valid(_sim_ref):
		return
	if _sim_ref.has_method("daylight"):
		_env["daylight"] = float(_sim_ref.daylight())
	if "day_phase" in _sim_ref:
		_env["day_phase"] = float(_sim_ref.day_phase)
	if "bloom_intensity" in _sim_ref:
		_env["bloom"] = clampf(float(_sim_ref.bloom_intensity), 0.0, 1.0)
	if "dissolved_o2" in _sim_ref:
		_env["o2"] = clampf(float(_sim_ref.dissolved_o2), 0.0, 1.2)
	if "aeration_air_rate" in _sim_ref:
		_env["aeration"] = clampf(float(_sim_ref.aeration_air_rate), 0.0, 2.0)
	if "aeration_flow_rate" in _sim_ref:
		_env["flow"] = clampf(float(_sim_ref.aeration_flow_rate), 0.0, 2.0)
	if "fish" in _sim_ref:
		_env["fish"] = int(_sim_ref.fish.size()) if _sim_ref.fish is Array else 0
	if "plants" in _sim_ref:
		_env["plants"] = int(_sim_ref.plants.size()) if _sim_ref.plants is Array else 0
	if "total_plant_biomass" in _sim_ref:
		_env["biomass"] = int(_sim_ref.total_plant_biomass)
	if _world_ref != null and is_instance_valid(_world_ref) and "tannins" in _world_ref:
		_env["tannins"] = clampf(float(_world_ref.tannins), 0.0, 1.0)
	var cfg := _cfg()
	if cfg != null and cfg.has_method("current_substrate_profile"):
		_env["saltwater"] = bool(cfg.current_substrate_profile().get("is_saltwater", false))


func _smooth_environment(dt: float) -> void:
	var smooth_k: float = _cfg_float("music_smooth_rate", 0.55)
	var rate: float = clampf(dt * lerpf(1.2, 6.5, smooth_k * _drive()), 0.0, 1.0)
	for key in _env.keys():
		var target: float = float(_env[key]) if typeof(_env[key]) in [TYPE_FLOAT, TYPE_INT] else 0.0
		if typeof(_env[key]) == TYPE_BOOL:
			target = 1.0 if _env[key] else 0.0
		if not _smooth.has(key):
			_smooth[key] = target
		else:
			_smooth[key] = lerpf(float(_smooth[key]), target, rate)
	_tank_vitality = _compute_vitality()
	_update_performance_params()
	if _ecosystem_shifted():
		_apply_ecosystem_shift()


func _compute_vitality() -> float:
	var fish_n: float = clampf(float(_smooth.get("fish", 0)) / 28.0, 0.0, 1.0) * _influence("music_influence_fish")
	var plant_n: float = clampf(float(_smooth.get("plants", 0)) / 90.0, 0.0, 1.0) * _influence("music_influence_plants")
	var bio_n: float = clampf(float(_smooth.get("biomass", 0)) / 520.0, 0.0, 1.0) * _influence("music_influence_biomass")
	var bloom: float = float(_smooth.get("bloom", 0.0)) * _influence("music_influence_bloom")
	var o2: float = clampf(float(_smooth.get("o2", 0.85)), 0.0, 1.0) * _influence("music_influence_o2")
	var total_w: float = 0.28 + 0.24 + 0.22 + 0.16 + 0.10
	return clampf(
		(fish_n * 0.28 + plant_n * 0.24 + bio_n * 0.22 + bloom * 0.16 + o2 * 0.10) / total_w,
		0.0, 1.0)


func _update_performance_params() -> void:
	var vit: float = _tank_vitality
	_bars_per_phrase = clampi(int(lerpf(8, 2, vit)), 2, 8)
	_sixteenth_div = 1 if vit > 0.55 else (2 if vit > 0.28 else 4)
	var dl: float = float(_smooth.get("daylight", 1.0))
	var zone: int = 1 if dl > 0.38 else 0
	if zone != _daylight_zone:
		_daylight_zone = zone
		_apply_ecosystem_shift()
	_arp_octave = 1 if vit > 0.62 and float(_smooth.get("bloom", 0.0)) > 0.35 else 0


func _ecosystem_shifted() -> bool:
	var churn: float = _cfg_float("music_phrase_churn", 0.5)
	var fish_thresh: float = lerpf(4.0, 1.0, churn)
	var plant_thresh: float = lerpf(8.0, 2.0, churn)
	var bio_thresh: float = lerpf(70.0, 15.0, churn)
	var bloom_thresh: float = lerpf(0.18, 0.04, churn)
	var o2_thresh: float = lerpf(0.14, 0.04, churn)
	var dl_thresh: float = lerpf(0.35, 0.08, churn)
	var fish_d: float = absf(float(_smooth.get("fish", 0)) - float(_prev_snap.get("fish", 0)))
	var plant_d: float = absf(float(_smooth.get("plants", 0)) - float(_prev_snap.get("plants", 0)))
	var bio_d: float = absf(float(_smooth.get("biomass", 0)) - float(_prev_snap.get("biomass", 0)))
	var bloom_d: float = absf(float(_smooth.get("bloom", 0)) - float(_prev_snap.get("bloom", 0)))
	var o2_d: float = absf(float(_smooth.get("o2", 0)) - float(_prev_snap.get("o2", 0)))
	var dl_d: float = absf(float(_smooth.get("daylight", 0)) - float(_prev_snap.get("daylight", 0)))
	var shifted: bool = fish_d >= fish_thresh or plant_d >= plant_thresh or bio_d >= bio_thresh \
		or bloom_d >= bloom_thresh or o2_d >= o2_thresh or dl_d >= dl_thresh
	if shifted:
		for key in _smooth.keys():
			_prev_snap[key] = _smooth[key]
	return shifted


func _apply_ecosystem_shift() -> void:
	_pick_arp_from_tank(false)
	_phrase_idx += 1
	var bank: Array = CHORD_DAY if _daylight_zone == 1 else CHORD_NIGHT
	var fish_n: int = int(_smooth.get("fish", 0))
	var plant_n: int = int(_smooth.get("plants", 0))
	_chord_root = int(bank[(_phrase_idx + fish_n + plant_n) % bank.size()]) % 5
	_bass_freq = _scale_freq(0, -1)
	_rebuild_tonal_cache()


func _pick_arp_from_tank(_initial: bool) -> void:
	var vit: float = _tank_vitality
	var bloom: float = float(_smooth.get("bloom", 0.0)) * _influence("music_influence_bloom")
	var salt: float = 1.0 if bool(_smooth.get("saltwater", false)) else 0.0
	var seed_n: float = _seed_mix(17)
	var idx: int = int(round(vit * float(ARP_BANK.size() - 1)))
	idx = (idx + int(bloom * 2.0) + int(salt * 2.0) + int(seed_n * 3.0)) % ARP_BANK.size()
	if _initial or idx != _active_arp_idx:
		_active_arp_idx = idx


func _active_arp_pattern() -> Array:
	return ARP_BANK[_active_arp_idx % ARP_BANK.size()]


func _react_to_event(event_name: String) -> void:
	if not _trance_bed_active():
		return
	match event_name:
		"birth", "spawn":
			_chord_root = (_chord_root + 2) % 5
			_phrase_idx += 1
			_rebuild_tonal_cache()
		"death":
			_chord_root = (_chord_root + 5) % 5
			_rebuild_tonal_cache()
		"plant":
			_active_arp_idx = (_active_arp_idx + 1) % ARP_BANK.size()
		"eat":
			_arp_octave = mini(_arp_octave + 1, 1)
		"story":
			_phrase_idx += 2
			_apply_ecosystem_shift()


func _mood_key() -> String:
	var cfg := _cfg()
	return String(cfg.music_mood) if cfg != null else "auto"


func _get_current_scale() -> Array[float]:
	var mood: String = _mood_key()
	if mood == "calm":
		return SCALE_MINOR
	if mood == "bright":
		return SCALE_MAJOR
	if mood == "deep":
		return SCALE_DEEP

	var react: float = _drive()
	var dl: float = float(_smooth.get("daylight", _env.get("daylight", 1.0))) * _influence("music_influence_day")
	var bloom: float = float(_smooth.get("bloom", 0.0)) * _influence("music_influence_bloom")
	var o2: float = float(_smooth.get("o2", 0.85)) * _influence("music_influence_o2")
	var salt: bool = bool(_smooth.get("saltwater", false))
	var tannins: float = float(_smooth.get("tannins", 0.0))

	var major_weight: float = clampf(dl, 0.0, 1.0)
	major_weight = lerpf(major_weight, 1.0, bloom * react * 0.55)
	major_weight = lerpf(major_weight, 0.0, (1.0 - clampf(o2, 0.0, 1.0)) * react * 0.7)
	major_weight = lerpf(major_weight, 0.25, react * 0.35 if salt else 0.0)
	major_weight = lerpf(major_weight, 0.2, tannins * react * 0.5)

	if major_weight > 0.58:
		return SCALE_MAJOR
	if major_weight < 0.38:
		return SCALE_MINOR
	return SCALE_MAJOR if dl > 0.45 else SCALE_MINOR


func _bpm() -> float:
	var e: float = _energy()
	var vit: float = _tank_vitality
	var tempo_follow: float = _cfg_float("music_tempo_follow", 0.72)
	var bloom: float = float(_smooth.get("bloom", 0.0)) * _influence("music_influence_bloom")
	var dl: float = float(_smooth.get("daylight", 1.0)) * _influence("music_influence_day")
	var fish: float = float(_smooth.get("fish", 0)) * _influence("music_influence_fish")
	var base: float = lerpf(78.0, 128.0, e * 0.5 + vit * tempo_follow * 0.4)
	base *= lerpf(0.92, 1.08, bloom * _drive())
	base *= lerpf(0.94, 1.06, dl)
	base += clampf(fish * 0.35, 0.0, 8.0)
	if float(_smooth.get("o2", 0.85)) < 0.45:
		base *= 0.88
	return clampf(base, 72.0, 138.0)


func _scale_freq(degree: int, octave: int = 0) -> float:
	var idx: int = clampi(_chord_root + degree, 0, _cached_scale.size() - 1)
	return _cached_scale[idx] * pow(2.0, float(octave))


func _rebuild_tonal_cache() -> void:
	_cached_scale = _get_current_scale()
	var pad_degrees: Array[int] = [0, 4, 7]
	if float(_smooth.get("o2", 0.85)) < 0.45:
		pad_degrees = [0, 3, 7]
	for i in 3:
		var idx: int = clampi(_chord_root + pad_degrees[i], 0, _cached_scale.size() - 1)
		_pad_increments[i] = _cached_scale[idx] * INV_SAMPLE_RATE
	_bass_inc = _bass_freq * INV_SAMPLE_RATE
	_arp_inc = _arp_freq * INV_SAMPLE_RATE
	_arp_inc_target = _arp_inc


func _lpf_alpha(cutoff_hz: float) -> float:
	var rc: float = 1.0 / (TAU * maxf(80.0, cutoff_hz))
	return INV_SAMPLE_RATE / (rc + INV_SAMPLE_RATE)


func _refresh_mix_cache() -> void:
	_cached_bpm = _bpm()
	_cached_beat_scale = _cached_bpm / 60.0 * INV_SAMPLE_RATE
	_cached_energy = _energy()
	var vit: float = _tank_vitality
	_cached_vol = _user_volume() * _complexity() * lerpf(0.45, 1.0, _cached_energy) * lerpf(0.65, 1.0, vit)
	_cached_kick_mix = _cfg_float("music_kick_mix", 0.65)
	_cached_bass_mix = _cfg_float("music_bass_mix", 0.75)
	_cached_arp_mix = _cfg_float("music_arp_mix", 0.85)
	_cached_pad_mix = _cfg_float("music_pad_mix", 0.7)
	_cached_hat_mix = _cfg_float("music_hat_mix", 0.55)
	var filter_bias: float = _cfg_float("music_filter_open", 0.5)
	_cached_kick_gain = lerpf(0.14, 0.28, clampf(
		float(_smooth.get("fish", 0)) / 24.0 + float(_smooth.get("bloom", 0.0)) * 0.4, 0.0, 1.0))
	_cached_bass_amp = 0.10 * _cached_bass_mix * lerpf(1.0, 0.68, float(_smooth.get("o2", 0.85)))
	_cached_pad_level = lerpf(0.012, 0.026, clampf(float(_smooth.get("biomass", 0)) / 400.0, 0.0, 1.0))
	_cached_arp_level = lerpf(0.035, 0.08, vit) * _cached_arp_mix
	_cached_hat_mul = lerpf(0.015, 0.04, float(_smooth.get("aeration", 0.0))) * _cached_hat_mix
	_cached_lfo_hz = lerpf(0.03, 0.18, float(_smooth.get("aeration", 0.0)) * 0.5 + vit * 0.5)
	_cached_arp_decay = lerpf(0.9984, 0.9945, _cached_energy)
	var pad_cutoff: float = lerpf(500.0, 5200.0, float(_smooth.get("daylight", 1.0)))
	pad_cutoff *= lerpf(0.85, 1.15, float(_smooth.get("bloom", 0.0)))
	pad_cutoff *= lerpf(0.75, 1.35, filter_bias)
	pad_cutoff *= lerpf(0.8, 1.3, sin(_lfo_phase * TAU) * 0.5 + 0.5)
	_cached_pad_lpf_alpha = _lpf_alpha(pad_cutoff)
	var arp_open: float = lerpf(0.25, 1.0, float(_smooth.get("bloom", 0.0)) * 0.6 + vit * 0.4)
	arp_open = lerpf(arp_open * 0.65, arp_open, filter_bias)
	var arp_cut: float = lerpf(520.0, 6200.0, arp_open * (sin(_lfo_phase * 0.5 * TAU) * 0.5 + 0.5))
	_cached_arp_lpf_alpha = _lpf_alpha(arp_cut)
	_cached_bass_active = int(float(_sample_clock) * _cached_beat_scale) % 2 == 0
	_rebuild_tonal_cache()


func _note_gain(base: float, is_event: bool = false) -> float:
	var gain: float = base
	if is_event:
		gain *= _event_gain()
	var react: float = _drive()
	if react > 0.05:
		gain *= lerpf(0.88, 1.08, float(_smooth.get("bloom", 0.0)) * react)
		gain *= lerpf(1.0, 0.72, maxf(0.0, 0.55 - float(_smooth.get("o2", 0.85))) * react * 2.0)
	return gain


func play_note(freq: float, amp: float, dur: float, mod_ratio: float = 2.01,
		mod_index: float = 1.5, decay_speed: float = 2.5, attack_time: float = 0.0,
		is_event: bool = false) -> void:
	if not _master_enabled():
		return
	if _pending.size() > 8:
		return
	var final_amp: float = _note_gain(amp, is_event)
	if final_amp <= 0.001:
		return
	_pending.append([
		freq, dur, final_amp, 0.0, 0.0, mod_ratio, mod_index,
		decay_speed, attack_time, dur,
	])


func play_supersaw(freq: float, amp: float, dur: float, is_event: bool = false) -> void:
	play_note(freq * 0.996, amp * 0.32, dur, 1.0, 0.0, 1.4, 0.018, is_event)
	play_note(freq * 1.004, amp * 0.32, dur, 1.0, 0.0, 1.4, 0.018, is_event)


func play_event_plink(intensity: float = 0.5, is_event: bool = false) -> void:
	if not _plink_bed_active() and not is_event:
		return
	if is_event and not _events_enabled():
		return
	var scale := _get_current_scale()
	var idx_bias: float = float(_smooth.get("bloom", 0.0)) * _drive() * 2.0
	var fish_bias: float = clampf(float(_smooth.get("fish", 0)) / 20.0, 0.0, 1.0)
	var note_idx: int = clampi(
		int((intensity * 0.55 + fish_bias * 0.25 + _tank_vitality * 0.2) * float(scale.size()) + idx_bias),
		0, scale.size() - 1)
	var detune: float = lerpf(0.985, 1.015, float(_smooth.get("daylight", 1.0)))
	var freq: float = scale[note_idx] * detune
	if _trance_bed_active() and not is_event:
		play_note(freq, 0.02 + intensity * 0.025, 0.28, 2.4, 1.2, 4.5, 0.006, false)
	else:
		var mod_idx: float = lerpf(1.2, 2.2, float(_smooth.get("daylight", 1.0)))
		var dur: float = lerpf(0.55, 0.85, _tank_vitality)
		play_note(freq, 0.03 + intensity * 0.04, dur, 2.01, mod_idx, 1.6, 0.012, is_event)


func play_aquarium_event(event_name: String, intensity: float = -1.0) -> void:
	if not _events_enabled():
		return
	_react_to_event(event_name)
	match event_name:
		"birth":
			play_birth_sfx()
		"spawn":
			play_spawn_sfx()
		"death":
			play_death_sfx()
		"eat":
			var eat_i: float = intensity if intensity >= 0.0 else randf_range(0.35, 0.65)
			play_eat_sfx(eat_i)
		"plant":
			play_plant_sfx(intensity if intensity >= 0.0 else randf_range(0.25, 0.55))
		"bubble":
			play_bubble_sfx(intensity if intensity >= 0.0 else randf_range(0.2, 0.5))
		"flow":
			play_flow_sfx()
		"story":
			play_riser_sfx(intensity if intensity >= 0.0 else 0.65)
		_:
			play_event_plink(intensity if intensity >= 0.0 else 0.5, true)


func play_eat_sfx(intensity: float = 0.5) -> void:
	var scale := _get_current_scale()
	var note_idx: int = clampi(int(intensity * 4.0) + int(float(_smooth.get("fish", 0)) * 0.15) + 5, 0, scale.size() - 1)
	var freq: float = scale[note_idx] * lerpf(0.99, 1.01, float(_smooth.get("bloom", 0.0)))
	if _trance_bed_active():
		play_note(freq, 0.035 + intensity * 0.03, 0.14, 1.0, 0.4, 4.0, 0.01, true)
	else:
		play_note(freq, 0.07 + intensity * 0.05, 0.18, 1.0, 0.5, 5.5, 0.0, true)


func play_plant_sfx(intensity: float = 0.4) -> void:
	var plant_n: int = int(_smooth.get("plants", 0))
	var freq: float = _scale_freq(int(intensity * 3.0) + (plant_n % 3) + 2) * lerpf(0.99, 1.01, float(_smooth.get("biomass", 0)) / 600.0)
	play_note(freq, 0.05 + intensity * 0.04, 0.14, 2.4, 1.1, 3.2, 0.01, true)


func play_bubble_sfx(intensity: float = 0.35) -> void:
	if not _environment_enabled():
		return
	if _bubble_bursts.size() >= BUBBLE_MAX:
		return
	var aer: float = float(_smooth.get("aeration", 0.0))
	var flow: float = float(_smooth.get("flow", 0.0))
	# Soft noise chirp — not a scale-tone ping that fights the trance bed.
	var start_hz: float = lerpf(520.0, 980.0, intensity + aer * 0.08)
	var amp: float = lerpf(0.006, 0.014, intensity)
	if _trance_bed_active():
		amp *= 0.42
	_bubble_bursts.append({
		"phase": _seed_mix(int(_bubble_bursts.size() + 7)),
		"pitch_hz": start_hz,
		"env": 1.0,
		"life": lerpf(0.035, 0.065, intensity + flow * 0.1),
		"amp": amp,
	})


func play_flow_sfx() -> void:
	play_note(_scale_freq(0, -1), 0.08, 0.32, 1.0, 0.35, 1.5, 0.03, false)


func play_riser_sfx(intensity: float = 0.65) -> void:
	var scale := _get_current_scale()
	var base_idx: int = clampi(int(intensity * 3.0), 0, scale.size() - 3)
	for i in 4:
		var freq: float = scale[base_idx + i] * lerpf(0.92, 1.08, float(i) / 3.0)
		play_supersaw(freq, 0.06 + intensity * 0.05, 0.45 + float(i) * 0.08, true)


func play_birth_sfx() -> void:
	if _trance_bed_active():
		play_supersaw(_scale_freq(0), 0.12, 0.55, true)
		play_supersaw(_scale_freq(4), 0.10, 0.48, true)
		play_supersaw(_scale_freq(7), 0.09, 0.42, true)
		return
	var scale := _get_current_scale()
	var base_idx: int = int(_smooth.get("fish", 0)) % 4
	for i in 3:
		var note_idx: int = clampi([base_idx, base_idx + 2, base_idx + 4][i], 0, scale.size() - 1)
		play_note(scale[note_idx], 0.09, 0.65, 2.01, 1.8, 2.2, float(i) * 0.08, true)


func play_death_sfx() -> void:
	var scale := _get_current_scale()
	var base_idx: int = int(_smooth.get("plants", 0)) % 3
	for i in 3:
		var note_idx: int = clampi([base_idx + 4, base_idx + 2, base_idx][i], 0, scale.size() - 1)
		play_note(scale[note_idx] * 0.5, 0.12, 1.0, 1.0, 0.6, 1.6, float(i) * 0.12, true)


func play_spawn_sfx() -> void:
	if _trance_bed_active():
		play_supersaw(_scale_freq(2), 0.11, 0.38, true)
		play_supersaw(_scale_freq(4), 0.09, 0.34, true)
		play_supersaw(_scale_freq(7), 0.08, 0.30, true)
		return
	var scale := _get_current_scale()
	var base_idx: int = int(_smooth.get("plants", 0)) % 3 + 2
	for i in 3:
		var note_idx: int = clampi([base_idx, base_idx + 2, base_idx + 4][i], 0, scale.size() - 1)
		play_note(scale[note_idx], 0.07, 0.95, 2.01, 2.2, 1.8, 0.0, true)


func _trigger_kick() -> void:
	if _kick_env < 0.06:
		_kick_phase = 0.0
	_kick_env = 1.0
	_kick_pitch = lerpf(58.0, 72.0, _energy())
	_sidechain = lerpf(0.72, 0.38, _cfg_float("music_sidechain", 0.55))


func _trigger_hat() -> void:
	_hat_env = 1.0


func _kick_on_quarter(quarter: int) -> bool:
	var vit: float = _tank_vitality
	var flow: float = float(_smooth.get("flow", 0.0))
	if vit < 0.2:
		return quarter % 4 == 0
	if vit < 0.45:
		return quarter % 2 == 0
	if flow > 0.35 and quarter % 4 == 2:
		return false
	return true


func _hat_on_quarter(quarter: int) -> bool:
	var aeration: float = float(_smooth.get("aeration", 0.0)) * _influence("music_influence_aeration")
	var fish: float = float(_smooth.get("fish", 0)) * _influence("music_influence_fish")
	var density: float = clampf(aeration * 0.35 + fish / 30.0, 0.0, 1.0)
	return quarter % 2 == 1 and density > lerpf(0.28, 0.08, _cfg_float("music_hat_mix", 0.55))


func _advance_sequencer(quarter: int, sixteenth: int) -> void:
	var pattern: Array = _active_arp_pattern()
	if sixteenth != _last_sixteenth_raw:
		_last_sixteenth_raw = sixteenth
		if sixteenth % _sixteenth_div == 0 and sixteenth != _last_sixteenth:
			_last_sixteenth = sixteenth
			var pat_idx: int = sixteenth % pattern.size()
			var degree: int = int(pattern[pat_idx])
			var oct: int = _arp_octave if degree > 4 else 0
			if float(_smooth.get("o2", 0.85)) < 0.5:
				oct = maxi(oct - 1, -1)
			_arp_freq = _scale_freq(degree, oct)
			_arp_inc_target = _arp_freq * INV_SAMPLE_RATE
			_arp_env = lerpf(0.22, 0.58, _tank_vitality)

	if quarter != _last_quarter:
		_last_quarter = quarter
		if _kick_on_quarter(quarter):
			_trigger_kick()
		if _hat_on_quarter(quarter):
			_trigger_hat()
		if quarter % 4 == 0 and quarter > 0:
			var bank: Array = CHORD_DAY if _daylight_zone == 1 else CHORD_NIGHT
			var bar_num: int = quarter / 4
			var step: int = (_phrase_idx + (bar_num % _bars_per_phrase)) % bank.size()
			_chord_root = int(bank[step]) % 5
			_bass_freq = _scale_freq(0, -1 if float(_smooth.get("bloom", 0.0)) < 0.4 else 0)
			_bass_inc = _bass_freq * INV_SAMPLE_RATE
			_rebuild_tonal_cache()
		_cached_bass_active = quarter % 2 == 0


func _noise_sample() -> float:
	_noise_seed = (_noise_seed * 1103515245 + 12345) & 0x7FFFFFFF
	return (float(_noise_seed) / 2147483647.0) * 2.0 - 1.0


func _one_pole_cached(input: float, state: float, alpha: float) -> float:
	return state + alpha * (input - state)


func _soft_wave(phase: float) -> float:
	# Triangle-ish blend — warmer than a naked sine, less buzzy than a square.
	var s: float = sin(phase * TAU)
	var t: float = 2.0 * absf(2.0 * phase - 1.0) - 1.0
	return lerpf(s, t, 0.38)


func _soft_clip(sample: float) -> float:
	# Gentle saturation before the hard DAC clamp.
	return tanh(sample * 1.15) * 0.78


func _dc_block(sample: float) -> float:
	# High-pass DC blocker — stops low-frequency thumps when layers stack.
	const coeff: float = 0.996
	var out: float = sample - _dc_x_prev + coeff * _dc_y_prev
	_dc_x_prev = sample
	_dc_y_prev = out
	return out


func _mix_bubble_bursts() -> float:
	var out: float = 0.0
	var n: int = _bubble_bursts.size()
	for i in range(n - 1, -1, -1):
		var b: Dictionary = _bubble_bursts[i]
		var life: float = float(b["life"])
		if life <= INV_SAMPLE_RATE:
			_bubble_bursts.remove_at(i)
			continue
		var env: float = float(b["env"])
		var pitch_hz: float = float(b["pitch_hz"])
		var phase: float = float(b["phase"])
		var amp: float = float(b["amp"])
		# Downward chirp + airy noise reads as a bubble, not a synth note.
		pitch_hz = maxf(180.0, pitch_hz * 0.9994)
		var chirp: float = sin(phase * TAU) * env * env
		var airy: float = _noise_sample() * env * 0.28
		out += (chirp * 0.38 + airy) * amp
		b["phase"] = fposmod(phase + pitch_hz * INV_SAMPLE_RATE, 1.0)
		b["pitch_hz"] = pitch_hz
		b["env"] = env * 0.991
		b["life"] = life - INV_SAMPLE_RATE
		_bubble_bursts[i] = b
	return out


func _mix_trance_sample() -> float:
	var beat_time: float = float(_sample_clock) * _cached_beat_scale
	var quarter: int = int(beat_time)
	var sixteenth: int = int(beat_time * 4.0)
	_advance_sequencer(quarter, sixteenth)

	_sidechain = lerpf(_sidechain, 1.0, 0.00085)
	var sc: float = _sidechain
	var vol: float = _cached_vol
	var out: float = 0.0

	if _kick_env > 0.001:
		_kick_phase += _kick_pitch * INV_SAMPLE_RATE
		_kick_pitch = maxf(42.0, _kick_pitch - _kick_pitch_decay)
		var kick_body: float = sin(_kick_phase * TAU) * _kick_env * _kick_env
		out += kick_body * vol * _cached_kick_gain * _cached_kick_mix
		_kick_env *= 0.9994

	if _cached_bass_active:
		_bass_phase = fposmod(_bass_phase + _bass_inc, 1.0)
		out += _soft_wave(_bass_phase) * _cached_bass_amp * vol * sc

	if _hat_env > 0.001:
		var hat_raw: float = _noise_sample() * _hat_env
		_lpf_hat = _one_pole_cached(hat_raw, _lpf_hat, _lpf_alpha(2800.0))
		out += _lpf_hat * vol * _cached_hat_mul
		_hat_env *= 0.9935

	var pad_raw: float = 0.0
	for i in 3:
		_pad_phases[i] = fposmod(_pad_phases[i] + _pad_increments[i], 1.0)
		pad_raw += _soft_wave(_pad_phases[i])
	pad_raw *= 0.333333
	_lpf_pad = _one_pole_cached(pad_raw, _lpf_pad, _cached_pad_lpf_alpha)
	out += _lpf_pad * _cached_pad_level * vol * sc * _cached_pad_mix

	_arp_inc = lerpf(_arp_inc, _arp_inc_target, 0.0018)
	if _arp_env > 0.0005:
		_arp_phase = fposmod(_arp_phase + _arp_inc, 1.0)
		var arp_raw: float = _soft_wave(_arp_phase)
		_lpf_arp = _one_pole_cached(arp_raw, _lpf_arp, _cached_arp_lpf_alpha)
		out += _lpf_arp * _arp_env * _cached_arp_level * vol * sc
		_arp_env *= _cached_arp_decay

	_lfo_phase = fposmod(_lfo_phase + _cached_lfo_hz * INV_SAMPLE_RATE, 1.0)
	_lpf_master = _one_pole_cached(out, _lpf_master, _lpf_alpha(6800.0))
	return _lpf_master


func _process(_dt: float) -> void:
	if _playback == null:
		return

	if _sim_ref == null or not is_instance_valid(_sim_ref):
		var scene := get_tree().current_scene
		if scene != null:
			_sim_ref = scene.get_node_or_null("SubViewport/World/SimDriver")
			_world_ref = scene.get_node_or_null("SubViewport/World")

	if not _master_enabled():
		return

	_env_accum += _dt
	var sim_dt: float = _dt
	if _sim_ref != null and "time_scale" in _sim_ref:
		sim_dt = _dt * float(_sim_ref.time_scale)
	if _env_accum >= ENV_REFRESH_INTERVAL:
		_env_accum = 0.0
		_refresh_environment()
		_smooth_environment(sim_dt)
		_refresh_mix_cache()
	else:
		_smooth_environment(sim_dt * 0.35)

	if _plink_bed_active() and _sim_ref != null and not _trance_bed_active():
		_accent_t -= sim_dt
		if _accent_t <= 0.0:
			var vit: float = _tank_vitality
			if vit > 0.08 and _pending.size() < 4:
				var dl: float = float(_smooth.get("daylight", 1.0))
				_accent_t = lerpf(18.0, 2.4, vit * _cfg_float("music_accent_density", 0.5)) * lerpf(1.2, 0.75, dl)
				var accent_i: float = clampf(
					vit * 0.7 + float(_smooth.get("bloom", 0.0)) * 0.25, 0.1, 0.95)
				play_event_plink(accent_i, false)

	if _environment_enabled() and _sim_ref != null:
		var aeration: float = float(_smooth.get("aeration", 0.0))
		var flow: float = float(_smooth.get("flow", 0.0))
		var bubble_rate: float = (aeration * 0.55 + flow * 0.25) * _drive()
		if bubble_rate > 0.04:
			_bubble_t -= sim_dt
			if _bubble_t <= 0.0:
				var interval: float = lerpf(2.8, 0.28, clampf(bubble_rate, 0.0, 1.0))
				interval *= lerpf(1.15, 0.85, _tank_vitality)
				if _trance_bed_active():
					interval *= 1.65
				_bubble_t = interval
				play_bubble_sfx(clampf(bubble_rate * 0.35 + aeration * 0.2, 0.15, 0.65))

	if _stream_player != null:
		var user_volume: float = _user_volume()
		if user_volume <= 0.01:
			_stream_player.volume_db = -80.0
		else:
			var dl: float = float(_smooth.get("daylight", 1.0))
			var max_db: float = lerpf(-32.0, -8.0, user_volume)
			var min_db: float = lerpf(-42.0, -16.0, user_volume)
			_stream_player.volume_db = lerpf(min_db, max_db, dl)

	var frames_available: int = mini(_playback.get_frames_available(), MAX_SAMPLES_PER_FRAME)
	if frames_available <= 0:
		return

	var trance_on: bool = _trance_bed_active()
	var delay_amt: float = _cfg_float("music_delay_amount", 0.35)
	var delay_fb: float = lerpf(0.14, 0.28, _cached_energy) if trance_on else 0.0
	var delay_mix: float = lerpf(0.06, 0.16, _cached_energy) * delay_amt if trance_on else 0.0
	var pending_n: int = _pending.size()

	for _f in frames_available:
		var bed: float = 0.0
		if trance_on:
			bed = _mix_trance_sample()
			bed = _dc_block(bed)

		var plinks: float = 0.0
		for j in range(pending_n - 1, -1, -1):
			var note = _pending[j]
			var dur: float = note[1]
			if dur <= INV_SAMPLE_RATE:
				_pending.remove_at(j)
				pending_n -= 1
				continue

			var freq: float = note[0]
			var amp: float = note[2]
			var phase: float = note[3]
			var decay_speed: float = note[7]
			var attack_time: float = note[8]
			var initial_dur: float = note[9]

			var env: float = 1.0
			var elapsed: float = initial_dur - dur
			if attack_time > 0.0 and elapsed < attack_time:
				var atk_denom: float = maxf(attack_time, INV_SAMPLE_RATE * 4.0)
				env = smoothstep(0.0, 1.0, elapsed / atk_denom)
			else:
				var rel: float = clampf(dur * decay_speed, 0.0, 1.0)
				env = rel * rel * (3.0 - 2.0 * rel)

			plinks += _soft_wave(phase) * amp * env

			note[3] = fposmod(phase + freq * INV_SAMPLE_RATE, 1.0)
			note[1] = dur - INV_SAMPLE_RATE
			_pending[j] = note

		var bubbles: float = _mix_bubble_bursts()
		var v: float = bed + plinks + bubbles

		if trance_on and delay_mix > 0.0:
			var delayed: float = _delay_buf[_delay_pos]
			_delay_buf[_delay_pos] = bed + delayed * delay_fb
			_delay_pos = (_delay_pos + 1) % DELAY_LEN
			v = bed * (1.0 - delay_mix) + delayed * delay_mix + plinks + bubbles

		v = _soft_clip(v)
		_playback.push_frame(Vector2(v, v))
		_sample_clock += 1


func get_live_status() -> Dictionary:
	return {
		"bpm": _cached_bpm,
		"vitality": _tank_vitality,
		"chord_root": _chord_root,
		"arp_idx": _active_arp_idx,
		"phrase": _phrase_idx,
		"day_zone": _daylight_zone,
		"fish": int(_smooth.get("fish", 0)),
		"plants": int(_smooth.get("plants", 0)),
		"bloom": float(_smooth.get("bloom", 0.0)),
		"o2": float(_smooth.get("o2", 0.85)),
		"daylight": float(_smooth.get("daylight", 1.0)),
		"biomass": int(_smooth.get("biomass", 0)),
		"aeration": float(_smooth.get("aeration", 0.0)),
	}


func randomize_performance() -> void:
	_phrase_idx += 3
	_chord_root = int(_seed_mix(41) * 5.0) % 5
	_pick_arp_from_tank(false)
	_apply_ecosystem_shift()
	_accent_t = 0.5
	_refresh_mix_cache()
