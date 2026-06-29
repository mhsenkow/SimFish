# Generative ambient + trance audio driven by live tank state.
#
# Harmony, tempo, arp patterns, and density track smoothed sim metrics
# (daylight, bloom, O₂, fish, plants, biomass, aeration). Phrases shift when
# the ecosystem meaningfully changes — not a fixed loop.

extends Node

const SAMPLE_RATE: int = 22050
const DELAY_LEN: int = 4096
const MAX_SAMPLES_PER_FRAME: int = 512
const MAX_SAMPLES_CATCHUP: int = 4096
const AUDIO_FILL_BUDGET_US: int = 8000
const BUBBLE_MAX: int = 8
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

# ---- Blues / modal / jazz scales (Sound Studio "Scale" dropdown + personas) ----
# All rooted near A3 (220 Hz) so they sit in the same register as SCALE_MINOR.
# The ♭5 "blue note" + ♭3/♭7 give the bluesy color; the modes/bebop/whole-tone
# add jazz flavor. ~10 entries each so degree indexing (arps, voicings) is safe.
# Minor blues: 1 ♭3 4 ♭5 5 ♭7
const SCALE_BLUES_MINOR: Array[float] = [
	220.00, 261.63, 293.66, 311.13, 329.63,
	392.00, 440.00, 523.25, 587.33, 622.25,
]
# Major blues: 1 2 ♭3 3 5 6
const SCALE_BLUES_MAJOR: Array[float] = [
	220.00, 246.94, 261.63, 277.18, 329.63,
	369.99, 440.00, 493.88, 523.25, 554.37,
]
# Dorian: 1 2 ♭3 4 5 6 ♭7 (minor with a bright 6th)
const SCALE_DORIAN: Array[float] = [
	220.00, 246.94, 261.63, 293.66, 329.63,
	369.99, 392.00, 440.00, 493.88, 523.25,
]
# Mixolydian: 1 2 3 4 5 6 ♭7 (major with a dominant 7th)
const SCALE_MIXOLYDIAN: Array[float] = [
	220.00, 246.94, 277.18, 293.66, 329.63,
	369.99, 392.00, 440.00, 493.88, 554.37,
]
# Bebop dominant: 1 2 3 4 5 6 ♭7 7 (chromatic passing tone)
const SCALE_BEBOP: Array[float] = [
	220.00, 246.94, 277.18, 293.66, 329.63,
	369.99, 392.00, 415.30, 440.00, 493.88,
]
# Whole tone: all whole steps — dreamy, ambiguous (Monk / Debussy color)
const SCALE_WHOLETONE: Array[float] = [
	220.00, 246.94, 277.18, 311.13, 349.23,
	392.00, 440.00, 493.88, 554.37, 622.25,
]
# Typed empty scale returned by _scale_by_name for "auto"/unknown so the caller
# falls through to mood/tank-driven selection.
const EMPTY_SCALE: Array[float] = []

# ---- Musical personas ----
# A persona is a named bundle that biases the SCALE, the rhythm feel (swing /
# humanize / jazziness / off-beat hat / sidechain), the voice balance (supersaw
# lead vs Rhodes/bell), the tempo (bpm_mul), and — via the "event" key — HOW
# tank events reshape the music (see _react_to_event). Selected from the Sound
# Studio "Persona" dropdown; "none" leaves the engine fully tank-driven.
# Vibe values are lerp targets (see _pp), not hard overrides, so the user's
# manual knobs still nudge the result.
const PERSONAS: Dictionary = {
	# Thelonious Monk — angular jazz-blues. Swung, dissonant, sparse; events
	# trigger chord substitutions + Rhodes/bell stabs instead of drops.
	"monk": {
		"scale": "blues_minor", "bpm_mul": 0.72, "swing": 0.6, "humanize": 0.6,
		"jazziness": 0.95, "offbeat_hat": 0.2, "lead_mix": 0.22, "sidechain": 0.3,
		"reverb": 0.4, "event": "jazz",
	},
	# ABGT / Anjuna — uplifting trance. Straight, pumping, supersaw-led; events
	# force builds/drops/breakdowns. Fastest of the set.
	"abgt": {
		"scale": "major", "bpm_mul": 1.16, "swing": 0.0, "humanize": 0.12,
		"jazziness": 0.2, "offbeat_hat": 0.72, "lead_mix": 0.9, "sidechain": 0.92,
		"reverb": 0.5, "event": "trance",
	},
	# Lo-fi / Dilla — dusty, drunk-swung downtempo. Vinyl + tape, Rhodes chords;
	# events are soft, behind-the-beat accents.
	"lofi": {
		"scale": "blues_major", "bpm_mul": 0.6, "swing": 0.62, "humanize": 0.72,
		"jazziness": 0.7, "offbeat_hat": 0.3, "lead_mix": 0.28, "sidechain": 0.45,
		"reverb": 0.5, "vinyl": 0.7, "tape": 0.6, "event": "lofi",
	},
	# Dub techno / deep — spacious, hypnotic. Sparse, big reverb + delay throws;
	# events echo out into the air bus and sweep the filter.
	"dub": {
		"scale": "dorian", "bpm_mul": 0.9, "swing": 0.12, "humanize": 0.3,
		"jazziness": 0.4, "offbeat_hat": 0.5, "lead_mix": 0.24, "sidechain": 0.8,
		"reverb": 0.85, "delay": 0.85, "event": "dub",
	},
}

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
# Classic uplifting / festival progression — root, V, vi, IV.
# Used in trance phrase form so the BUILD/DROP arc lands on familiar harmony.
const CHORD_TRANCE: Array[int] = [0, 4, 5, 3, 0, 4, 5, 3]

# Pad voicings — triad → 7th → 9th → sus2add9 as jazziness climbs.
# Degrees are scale-step offsets into _cached_scale from the chord root.
const PAD_VOICINGS: Array = [
	[0, 4, 7],          # plain triad
	[0, 2, 4, 7],       # add9
	[0, 4, 6, 9],       # maj7+9 ish
	[0, 1, 4, 8],       # sus2 + 9
]
const PAD_VOICINGS_MINOR: Array = [
	[0, 3, 7],
	[0, 3, 6, 9],
	[0, 2, 3, 6],
	[0, 3, 5, 7],
]

# Per-species pitch palette. Small bright fish trend up; predators trend down.
# Unknown species fall back to a deterministic hash offset (see _species_offset).
const SPECIES_PITCH_OFFSET: Dictionary = {
	"glassdart": 7,
	"neon": 5,
	"neon_tetra": 5,
	"cardinal": 5,
	"ember": 4,
	"guppy": 4,
	"endler": 4,
	"rasbora": 5,
	"harlequin": 4,
	"tetra": 2,
	"cory": 0,
	"corydoras": 0,
	"otocinclus": 1,
	"oto": 1,
	"gourami": -3,
	"betta": -2,
	"angelfish": -5,
	"discus": -5,
	"mudsifter": -3,
	"loach": -2,
	"puffer": -7,
	"plecostomus": -7,
	"pleco": -7,
	"shrimp": 9,
	"cherry_shrimp": 9,
	"amano": 7,
	"snail": -9,
	"nerite": -8,
	"mystery_snail": -10,
}

# Detune cents for the 7-voice supersaw. Symmetric around 0 → big stereo width.
const LEAD_DETUNE_CENTS: Array[float] = [-22.0, -14.0, -7.0, 0.0, 7.0, 14.0, 22.0]
const LEAD_PAN: Array[float] = [-0.95, -0.6, -0.3, 0.0, 0.3, 0.6, 0.95]

# Phrase architecture — drives layer gains, riser presence, drop emphasis.
enum PhraseState { VERSE, BUILD, DROP, BREAKDOWN, CHORUS }

# Three streams routing to three buses so each can have its own FX chain:
# Drums (dry comp), Synth (subtle plate reverb), Air (deep reverb + ping-pong).
var _stream_player: AudioStreamPlayer = null      # legacy alias = _player_synth
var _playback: AudioStreamGeneratorPlayback = null # legacy alias = _playback_synth
var _player_drums: AudioStreamPlayer = null
var _player_synth: AudioStreamPlayer = null
var _player_air: AudioStreamPlayer = null
var _playback_drums: AudioStreamGeneratorPlayback = null
var _playback_synth: AudioStreamGeneratorPlayback = null
var _playback_air: AudioStreamGeneratorPlayback = null
var _pending: Array = []
var _bubble_bursts: Array = []
var _plink_lpf: float = 0.0

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
var _cached_beat_time: float = 0.0
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
var _dc_x_prev_r: float = 0.0
var _dc_y_prev_r: float = 0.0
var _kick_pitch_decay: float = 28.0 * INV_SAMPLE_RATE

# Phrase state machine — VERSE/BUILD/DROP/BREAKDOWN/CHORUS.
# Drives per-layer gain envelopes, riser presence, and drop accents.
var _phrase_state: int = PhraseState.VERSE
var _phrase_state_bars_left: int = 4
var _phrase_state_total_bars: int = 4        # set when entering a state; used for bar_pos
var _phrase_state_bar_pos: float = 0.0       # 0..1 progression through current state
var _phrase_force_state: int = -1            # set by events; consumed at next bar boundary
var _last_bar: int = -1

# Supersaw lead — 7 detuned saws with stereo spread.
var _lead_phases: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _lead_increments: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _lead_freq: float = 440.0
var _lead_env: float = 0.0
var _lead_target_env: float = 0.0
var _lead_lpf_l: float = 0.0
var _lead_lpf_r: float = 0.0
var _lead_last_sixteenth: int = -1

# White-noise riser — builds across BUILD bars, slams into DROP.
var _riser_env: float = 0.0
var _riser_lpf: float = 0.0

# Tape wow — fractional-delay pitch wobble on the master bus.
var _wow_buf: PackedFloat32Array = PackedFloat32Array()
var _wow_buf_r: PackedFloat32Array = PackedFloat32Array()
var _wow_pos: int = 0
var _wow_lfo: float = 0.0
var _wow_lfo2: float = 0.0

# Vinyl crackle layer — sparse pops + filtered noise floor.
var _vinyl_noise_lpf: float = 0.0

# ---- Aquatic ambience bed (delicate tank fizz, not a noise wash) ----
# Sparse micro-fizz gated by aeration / pearling; breathes slowly so it reads as
# live water rather than a constant whoosh. Stereo width from per-channel LPF.
var _water_lpf_l: float = 0.0
var _water_lpf_r: float = 0.0
var _water_fizz_lfo: float = 0.0
var _swim_activity: float = 0.0
# Per-fish presence pan in [-1, 1]: the follow camera biases the ambience
# toward where the watched creature sits, so the Portal cam feels intimate.
var _presence_pan: float = 0.0


# Called by the follow camera to position the soundscape toward the creature
# you're watching (x in viewport-normalized [-1,1]; 0 when not following).
func set_presence_pan(p: float) -> void:
	_presence_pan = clampf(p, -1.0, 1.0)
var _vinyl_pop_env: float = 0.0
var _vinyl_pop_freq: float = 1.0
var _vinyl_pop_t: float = 0.0

# Stereo bed — output is now Vector2; arp/pad/lead can pan.
var _delay_buf_r: PackedFloat32Array = PackedFloat32Array()

# Sub bass — pure 40-80 Hz sine an octave below the melodic bass.
var _sub_phase: float = 0.0
var _sub_inc: float = 55.0 * INV_SAMPLE_RATE

# PWM off-beat bass — square with LFO'd pulse width, gated to "&"s of each beat.
var _pwm_phase: float = 0.0
var _pwm_inc: float = 110.0 * INV_SAMPLE_RATE
var _pwm_lfo: float = 0.0
var _pwm_env: float = 0.0
var _pwm_active: bool = false

# Clap + tom + shaker percussion.
var _clap_env: float = 0.0
var _clap_lpf: float = 0.0
var _shaker_env: float = 0.0
var _shaker_lpf: float = 0.0
var _tom_env: float = 0.0
var _tom_phase: float = 0.0
var _tom_pitch: float = 140.0

# Reverse-cymbal swell — linear ramp up across BUILD, hard cut at DROP.
var _rev_cym_env: float = 0.0
var _rev_cym_lpf: float = 0.0
var _rev_cym_active: bool = false

# Snare-roll fill — accelerating noise bursts in the last bar of BUILD.
var _snare_roll_t: float = 0.0
var _snare_roll_env: float = 0.0
var _snare_active: bool = false

# Master breathe — slow LFO modulating the master LPF cutoff over a long arc.
var _breathe_phase: float = 0.0
var _cached_master_cut: float = 6800.0

# Granular pad — ring buffer of past pad output, replayed at offset/pitch.
var _grain_buf: PackedFloat32Array = PackedFloat32Array()
var _grain_pos: int = 0
var _grain_read: float = 0.0
var _grain_inc: float = 1.0   # 1.0 = same pitch; <1 down-pitched
var _grain_size: int = 5512   # ~0.25 s at 22050 Hz

# Wavetable pad — single oscillator scanning sine→saw blend as daylight rises.
var _wt_phase: float = 0.0

# Vocoded "aah" pad — pad output modulated by bubble noise envelope.
var _voc_env: float = 0.0
var _voc_lpf: float = 0.0

# Bitcrush (algae degradation) — sample-and-hold + bit depth reduction.
var _bc_hold_l: float = 0.0
var _bc_hold_r: float = 0.0
var _bc_phase: float = 0.0

# Schooling/feeding visual hooks.
var _last_school_t: float = 0.0

# In-game-day → key modulation.
var _last_day_index: int = 0
var _key_mod_offset: int = 0

# Audio recording — appends mixed master samples to a buffer for WAV export.
var _recording: bool = false
var _recording_buffer: PackedVector2Array = PackedVector2Array()
var _recording_max_samples: int = SAMPLE_RATE * 60 * 4   # 4 minutes max

# Cached deltas refreshed in _refresh_mix_cache.
var _cached_lead_mix: float = 0.0
var _cached_lead_detune: float = 0.55
var _cached_lead_amp: float = 0.0
var _cached_swing: float = 0.0
var _cached_offbeat_hat: float = 0.55
var _cached_jazziness: float = 0.4
var _cached_drop_intensity: float = 0.7
var _cached_breakdown_depth: float = 0.7
var _cached_reverb_send: float = 0.45
var _cached_humanize: float = 0.22
var _cached_vinyl: float = 0.2
var _cached_tape_wow: float = 0.18
var _cached_species_palette: float = 0.75
var _cached_phrase_form: String = "auto"
# Voices.
var _cached_sub_bass_amp: float = 0.04
var _cached_pwm_amp: float = 0.045
var _cached_granular: float = 0.25
var _cached_vocoder: float = 0.25
var _cached_clap_mix: float = 0.45
var _cached_shaker_mix: float = 0.4
# Build dramaturgy / master breathe.
var _cached_build_drama: float = 0.7
var _cached_breathe: float = 0.35
var _pad_stab_gate: float = 1.0      # ramp 0..1 for BUILD chord-stab gating
# Tank-state-driven character.
var _cached_bitcrush: float = 0.0
var _cached_bass_grit: float = 0.0
var _cached_pump_gate: float = 0.6
var _cached_pad_detune: float = 1.0    # 1.0 = no detune; multiplied into pad phase increments
# Harmony.
var _cached_key_mod: float = 0.35
# Phrase-state gain matrix — computed from _phrase_state each refresh.
var _state_kick_gain: float = 1.0
var _state_bass_gain: float = 1.0
var _state_arp_gain: float = 1.0
var _state_pad_gain: float = 1.0
var _state_hat_gain: float = 1.0
var _state_lead_gain: float = 0.0
var _state_riser_gain: float = 0.0


func _ready() -> void:
	process_priority = -128
	# Three streams, three buses. Drums = dry comp, Synth = subtle reverb,
	# Air = deep reverb + ping-pong delay. Falls back gracefully when buses
	# are missing (single Music bus on master).
	_player_drums = _make_stream("Music_Drums", -12.0)
	_player_synth = _make_stream("Music_Synth", -12.0)
	_player_air = _make_stream("Music_Air", -14.0)
	_playback_drums = _player_drums.get_stream_playback() as AudioStreamGeneratorPlayback
	_playback_synth = _player_synth.get_stream_playback() as AudioStreamGeneratorPlayback
	_playback_air = _player_air.get_stream_playback() as AudioStreamGeneratorPlayback
	# Legacy aliases — some external code (sound_panel.gd, etc.) reads these.
	_stream_player = _player_synth
	_playback = _playback_synth

	_delay_buf.resize(DELAY_LEN)
	_delay_buf.fill(0.0)
	_delay_buf_r.resize(DELAY_LEN)
	_delay_buf_r.fill(0.0)
	# Tape-wow fractional delay line — ~25 ms max wobble, comfortable headroom.
	_wow_buf.resize(1024)
	_wow_buf.fill(0.0)
	_wow_buf_r.resize(1024)
	_wow_buf_r.fill(0.0)
	# Granular pad buffer — ~0.25 s of past pad output.
	_grain_buf.resize(_grain_size)
	_grain_buf.fill(0.0)
	_chord_root = 0
	_smooth = _env.duplicate()
	_prev_snap = _env.duplicate()
	_pick_arp_from_tank(true)
	_accent_t = 4.0
	_rebuild_tonal_cache()
	_refresh_mix_cache()


func _make_stream(bus_name: String, vol_db: float) -> AudioStreamPlayer:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = SAMPLE_RATE
	gen.buffer_length = 0.15
	var p := AudioStreamPlayer.new()
	p.stream = gen
	p.volume_db = vol_db
	# Walk up the parent chain Music_Drums → Music_Synth → Music → Master.
	# If the project ships without the new layout, fall back to the single
	# "Music" bus or Master.
	var resolved: String = bus_name
	if AudioServer.get_bus_index(resolved) < 0:
		resolved = "Music"
	if AudioServer.get_bus_index(resolved) < 0:
		resolved = "Master"
	p.bus = resolved
	add_child(p)
	p.play()
	return p


func _cfg() -> Node:
	return get_node_or_null("/root/TankConfig")


func _master_enabled() -> bool:
	var cfg := _cfg()
	return (not not cfg.music_enabled) if cfg != null else true


func _ambient_enabled() -> bool:
	if not _master_enabled():
		return false
	var cfg := _cfg()
	return (not not cfg.music_ambient_enabled) if cfg != null else true


func _events_enabled() -> bool:
	if not _master_enabled():
		return false
	var cfg := _cfg()
	return (not not cfg.music_events_enabled) if cfg != null else true


func _environment_enabled() -> bool:
	if not _master_enabled():
		return false
	var cfg := _cfg()
	return (not not cfg.music_environment_enabled) if cfg != null else true


func _reactivity() -> float:
	var cfg := _cfg()
	return clampf(cfg.music_reactivity, 0.0, 1.0) if cfg != null else 0.65


func _event_gain() -> float:
	var cfg := _cfg()
	return clampf(cfg.music_event_volume, 0.0, 1.0) if cfg != null else 0.75


func _user_volume() -> float:
	var cfg := _cfg()
	var base: float = clampf(cfg.music_volume, 0.0, 1.0) if cfg != null else 0.7
	var mr := get_tree().get_first_node_in_group("music_reactive")
	if mr != null and mr.has_method("is_external_playing") and mr.is_external_playing():
		base *= 0.12
	return base


func _complexity() -> float:
	var cfg := _cfg()
	return clampf(cfg.music_complexity, 0.0, 1.0) if cfg != null else 0.5


func _energy() -> float:
	var cfg := _cfg()
	return clampf(cfg.music_energy, 0.0, 1.0) if cfg != null else 0.55


func _style() -> String:
	var cfg := _cfg()
	return cfg.music_style if cfg != null else "hybrid"


func _scale_cfg() -> String:
	var cfg := _cfg()
	return cfg.music_scale if cfg != null else "auto"


@warning_ignore("shadowed_variable_base_class")
func _scale_by_name(name: String) -> Array[float]:
	match name:
		"major": return SCALE_MAJOR
		"minor": return SCALE_MINOR
		"deep": return SCALE_DEEP
		"blues_minor": return SCALE_BLUES_MINOR
		"blues_major": return SCALE_BLUES_MAJOR
		"dorian": return SCALE_DORIAN
		"mixolydian": return SCALE_MIXOLYDIAN
		"bebop": return SCALE_BEBOP
		"whole_tone": return SCALE_WHOLETONE
		_: return EMPTY_SCALE  # "auto"/unknown → caller falls through


func _persona_key() -> String:
	var cfg := _cfg()
	return cfg.music_persona if cfg != null else "none"


func _active_persona() -> Dictionary:
	return PERSONAS.get(_persona_key(), {})


# Blend a user knob value toward the active persona's value for `key`. With no
# persona (or no such key) the user's value passes through unchanged, so the
# persona biases the vibe without erasing the manual sliders.
func _pp(user_val: float, key: String, strength: float = 0.7) -> float:
	var p: Dictionary = _active_persona()
	if p.has(key):
		return lerpf(user_val, float(p[key]), strength)
	return user_val


func _trance_bed_active() -> bool:
	if not _ambient_enabled() or _complexity() <= 0.06:
		return false
	# Any persona drives the full groove engine (its swing / tempo / sidechain /
	# voicing biases reshape the bed into that vibe) regardless of Style.
	if not _active_persona().is_empty():
		return true
	var st: String = _style()
	return st == "trance" or st == "hybrid"


func _plink_bed_active() -> bool:
	# A persona takes over the bed entirely, so the sparse plink layer steps aside.
	if not _active_persona().is_empty():
		return false
	var st: String = _style()
	return _ambient_enabled() and (st == "ambient" or (st == "hybrid" and _complexity() < 0.45))


func silence_immediately() -> void:
	_pending.clear()
	_bubble_bursts.clear()
	_kick_env = 0.0
	_sidechain = 1.0
	_clap_env = 0.0
	_shaker_env = 0.0
	_tom_env = 0.0
	_rev_cym_env = 0.0
	_snare_roll_env = 0.0
	_riser_env = 0.0
	_lead_env = 0.0
	_lead_target_env = 0.0
	_voc_env = 0.0
	if _player_drums != null:
		_player_drums.volume_db = -80.0
	if _player_synth != null:
		_player_synth.volume_db = -80.0
	if _player_air != null:
		_player_air.volume_db = -80.0


func _drive() -> float:
	return maxf(_cfg_float("music_coupling_floor", 0.55), _reactivity())


func _cfg_float(key: String, default: float) -> float:
	var cfg := _cfg()
	if cfg == null:
		return default
	var v: Variant = cfg.get(key)
	if v == null:
		return default
	if v is float:
		return clampf(v, 0.0, 2.0)
	if v is int:
		var n: float = v
		return clampf(n, 0.0, 2.0)
	return default


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
		_env["saltwater"] = not not cfg.current_substrate_profile().get("is_saltwater", false)


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
	var salt: float = 1.0 if _smooth.get("saltwater", false) else 0.0
	var seed_n: float = _seed_mix(17)
	var idx: int = int(round(vit * float(ARP_BANK.size() - 1)))
	idx = (idx + int(bloom * 2.0) + int(salt * 2.0) + int(seed_n * 3.0)) % ARP_BANK.size()
	if _initial or idx != _active_arp_idx:
		_active_arp_idx = idx


func _active_arp_pattern() -> Array:
	return ARP_BANK[_active_arp_idx % ARP_BANK.size()]


# ---- Festival/lofi accessors (deferred so TankConfig can hot-swap) ----

func _phrase_form_key() -> String:
	var cfg := _cfg()
	return cfg.music_phrase_form if cfg != null else "auto"


func _drop_intensity() -> float:
	return _cfg_float("music_drop_intensity", 0.7)


func _breakdown_depth() -> float:
	return _cfg_float("music_breakdown_depth", 0.7)


func _lead_mix_cfg() -> float:
	return _pp(_cfg_float("music_lead_mix", 0.55), "lead_mix")


func _lead_detune_cfg() -> float:
	return _cfg_float("music_lead_detune", 0.55)


func _vinyl_cfg() -> float:
	return _pp(_cfg_float("music_vinyl_crackle", 0.2), "vinyl")


func _tape_wow_cfg() -> float:
	return _pp(_cfg_float("music_tape_wow", 0.18), "tape")


func _jazziness_cfg() -> float:
	return _pp(_cfg_float("music_jazziness", 0.4), "jazziness")


func _swing_cfg() -> float:
	return _pp(_cfg_float("music_swing", 0.06), "swing")


func _offbeat_hat_cfg() -> float:
	return _pp(_cfg_float("music_offbeat_hat", 0.55), "offbeat_hat")


func _reverb_send_cfg() -> float:
	return _pp(_cfg_float("music_reverb_send", 0.45), "reverb")


func _humanize_cfg() -> float:
	return _pp(_cfg_float("music_humanize", 0.22), "humanize")


func _species_palette_cfg() -> float:
	return _cfg_float("music_species_palette", 0.75)


func _sub_bass_cfg() -> float:
	return _cfg_float("music_sub_bass_mix", 0.55)


func _pwm_bass_cfg() -> float:
	return _cfg_float("music_offbeat_bass_mix", 0.35)


func _granular_cfg() -> float:
	return _cfg_float("music_granular_pad", 0.25)


func _vocoder_cfg() -> float:
	return _cfg_float("music_vocoder_pad", 0.25)


func _shaker_mix_cfg() -> float:
	return _cfg_float("music_shaker_mix", 0.4)


func _clap_mix_cfg() -> float:
	return _cfg_float("music_clap_mix", 0.45)


func _build_drama_cfg() -> float:
	return _cfg_float("music_build_drama", 0.7)


func _bitcrush_algae_cfg() -> float:
	return _cfg_float("music_bitcrush_algae", 0.6)


func _bass_grit_cfg() -> float:
	return _cfg_float("music_bass_grit", 0.5)


func _pump_gate_cfg() -> float:
	return _cfg_float("music_pump_gate", 0.6)


func _key_mod_cfg() -> float:
	return _cfg_float("music_key_mod", 0.35)


func _breathe_cfg() -> float:
	return _cfg_float("music_breathe_lfo", 0.35)


# pH-driven pad detune amount (0..1). Currently reused as "water-quality →
# detune" without needing a separate config knob.
func _pad_ph_quality_amount() -> float:
	# Pad detune sensitivity uses the existing "bass_grit" axis as a proxy —
	# if the user wants "wrongness" they crank the same audible knob.
	return clampf(_cached_bass_grit * 1.5, 0.0, 1.0)


# Long-form: every in-game day, shift the key root by ±1-2 semitones.
# The amount depends on the user's key_mod knob and the daylight curve so
# the modulation only ticks once per cycle.
func _maybe_modulate_key() -> void:
	if _cached_key_mod <= 0.01:
		_key_mod_offset = 0
		return
	if _sim_ref == null:
		return
	# `day_phase` is 0..1 cycling per in-game day; we tick at the wrap point.
	var dp: float = float(_smooth.get("day_phase", 0.25))
	# Detect wrap from ~0.9 back down to ~0.1.
	if dp < 0.15 and _last_day_index >= 0:
		var step: int = 1 if randf() < 0.7 else 2
		if randf() < 0.5:
			step = -step
		_key_mod_offset = clampi(_key_mod_offset + int(step * _cached_key_mod * 2.0), -5, 5)
		_last_day_index = 1
	elif dp > 0.5:
		_last_day_index = 0


# Temperature → reverb tail. Reads world.water_temperature_c if available and
# tweaks the AudioEffectReverb on the Music_Synth bus. Called periodically from
# _process; cheap because we only set when the value changes.
func _apply_temperature_to_reverb() -> void:
	if _world_ref == null or not is_instance_valid(_world_ref):
		return
	var temp_v: Variant = _world_ref.get("water_temperature_c")
	if temp_v == null:
		return
	var temp: float = float(temp_v)
	# Cold tanks (15°C) → long, glassy. Warm (30°C) → tight, intimate room.
	var t: float = clampf((temp - 15.0) / 15.0, 0.0, 1.0)   # 15..30°C → 0..1
	var bus_idx: int = AudioServer.get_bus_index("Music_Synth")
	if bus_idx < 0:
		return
	var fx: AudioEffect = AudioServer.get_bus_effect(bus_idx, 0)
	if fx is AudioEffectReverb:
		var rv: AudioEffectReverb = fx
		# Cold = larger room, lower damping; warm = small + damped.
		rv.room_size = lerpf(0.85, 0.55, t)
		rv.damping = lerpf(0.22, 0.55, t)


# Map species_id → semitone offset. Falls back to a deterministic hash so any
# species sounds consistent across plays.
func _species_offset(species: String) -> int:
	if species.is_empty():
		return 0
	var key: String = species.to_lower()
	if SPECIES_PITCH_OFFSET.has(key):
		return int(SPECIES_PITCH_OFFSET[key])
	# Try the second token (e.g. "neon_tetra" → "tetra").
	var parts: PackedStringArray = key.split("_", false)
	if parts.size() >= 2 and SPECIES_PITCH_OFFSET.has(parts[parts.size() - 1]):
		return int(SPECIES_PITCH_OFFSET[parts[parts.size() - 1]])
	# Stable hash fallback in [-6..+6].
	var h: int = key.hash()
	return int(h % 13) - 6


# How loud each layer should be in the current phrase state. Re-evaluated every
# _refresh_mix_cache so changes feel snappy without per-sample lookups.
func _compute_state_gains() -> void:
	var drop_i: float = _cached_drop_intensity
	var bd: float = _cached_breakdown_depth
	var bar_p: float = _phrase_state_bar_pos
	match _phrase_state:
		PhraseState.VERSE:
			_state_kick_gain = 1.0
			_state_bass_gain = 1.0
			_state_arp_gain = 1.0
			_state_pad_gain = 1.0
			_state_hat_gain = 1.0
			_state_lead_gain = 0.0
			_state_riser_gain = 0.0
		PhraseState.BUILD:
			# Kick & bass thin out, hat density climbs, riser swells. Pad opens
			# but stays at 1.0 — anticipation comes from the riser, not gain.
			var t: float = clampf(bar_p, 0.0, 1.0)
			_state_kick_gain = lerpf(1.0, 0.32, t * drop_i)
			_state_bass_gain = lerpf(1.0, 0.5, t * drop_i)
			_state_arp_gain = lerpf(0.95, 0.65, t * 0.6)
			_state_pad_gain = lerpf(0.95, 1.0, t)
			_state_hat_gain = lerpf(0.95, 1.15, t * drop_i)
			_state_lead_gain = lerpf(0.0, 0.4, t)
			_state_riser_gain = t * drop_i * 0.75
		PhraseState.DROP:
			# Kick punches; other layers stay at 1.0 so we don't pile up dB.
			var d: float = clampf(bar_p, 0.0, 1.0)
			var kick_slam: float = lerpf(1.0 + drop_i * 0.2, 1.0, d * 0.6)
			_state_kick_gain = kick_slam
			_state_bass_gain = 1.0
			_state_arp_gain = 0.95
			_state_pad_gain = 0.85
			_state_hat_gain = 0.9
			# Lead is the headline voice — sized so it sits *on* the mix, not over it.
			_state_lead_gain = lerpf(0.85, 0.6, d * 0.5) * (0.3 + drop_i * 0.5)
			_state_riser_gain = lerpf(0.4, 0.0, d)
		PhraseState.BREAKDOWN:
			# Kick + bass duck; pad swells gently. Use 1 - bd so depth knob cuts.
			var mute: float = 1.0 - bd
			_state_kick_gain = mute * 0.3
			_state_bass_gain = mute * 0.5
			_state_arp_gain = lerpf(0.35, 0.65, bar_p) * (0.55 + 0.45 * mute)
			_state_pad_gain = lerpf(0.85, 1.15, bar_p)
			_state_hat_gain = mute * 0.4
			_state_lead_gain = 0.0
			_state_riser_gain = 0.0
		PhraseState.CHORUS:
			_state_kick_gain = 1.0
			_state_bass_gain = 1.0
			_state_arp_gain = 0.95
			_state_pad_gain = 0.95
			_state_hat_gain = 0.9
			_state_lead_gain = 0.55 + drop_i * 0.25
			_state_riser_gain = 0.0
		_:
			_state_kick_gain = 1.0
			_state_bass_gain = 1.0
			_state_arp_gain = 1.0
			_state_pad_gain = 1.0
			_state_hat_gain = 1.0
			_state_lead_gain = 0.0
			_state_riser_gain = 0.0


func _enter_phrase_state(new_state: int, bars: int) -> void:
	_phrase_state = new_state
	_phrase_state_bars_left = maxi(1, bars)
	_phrase_state_total_bars = _phrase_state_bars_left
	_phrase_state_bar_pos = 0.0
	# Dramaturgy hooks — start/stop reverse cymbal, snare roll, pedal-tone.
	if new_state == PhraseState.BUILD:
		_lead_target_env = 0.5
		_start_reverse_cymbal()
		# Snare roll fires in the last bar only — bar-counter check in
		# _advance_phrase_state_at_bar handles that.
	elif new_state == PhraseState.DROP:
		# Hard-cut reverse cymbal + stop snare roll + reset envelopes.
		_riser_env *= 0.5
		_kick_env = 1.0
		_lead_target_env = 1.0
		_stop_reverse_cymbal()
		_stop_snare_roll()
	elif new_state == PhraseState.BREAKDOWN:
		_kick_env *= 0.3
		_lead_target_env = 0.0
		_riser_env = 0.0
		_stop_reverse_cymbal()
		_stop_snare_roll()
	elif new_state == PhraseState.CHORUS:
		_lead_target_env = 0.8
		_stop_reverse_cymbal()
		_stop_snare_roll()
	else:
		_lead_target_env = 0.0
		_stop_reverse_cymbal()
		_stop_snare_roll()
	_compute_state_gains()


# Called at each bar boundary. Picks the next state from current state + form.
func _advance_phrase_state_at_bar(_bar_num: int) -> void:
	# Pending event override (e.g. spawn → DROP).
	if _phrase_force_state != -1:
		var forced: int = _phrase_force_state
		_phrase_force_state = -1
		var bars: int = 1
		match forced:
			PhraseState.BUILD: bars = 2
			PhraseState.DROP: bars = 4
			PhraseState.BREAKDOWN: bars = 4
			PhraseState.CHORUS: bars = 8
			_: bars = 4
		_enter_phrase_state(forced, bars)
		return

	_phrase_state_bars_left -= 1
	# When BUILD enters its last bar, fire the snare-roll fill.
	if _phrase_state == PhraseState.BUILD and _phrase_state_bars_left == 1:
		_start_snare_roll()
	if _phrase_state_bars_left > 0:
		return

	# Time to transition. The "form" knob picks the next state.
	var form: String = _cached_phrase_form
	if form == "loop":
		# Stay in VERSE forever — chill background mode.
		_enter_phrase_state(PhraseState.VERSE, 8)
		return
	if form == "free":
		# Events drive it; default to verse, only switch when forced.
		_enter_phrase_state(PhraseState.VERSE, 8)
		return

	var rng_seed: int = (_phrase_idx * 1009 + _music_seed()) & 0x7FFFFFFF
	var roll: float = float(rng_seed % 100) / 100.0

	if form == "trance":
		# Strict 16-bar verse / 4-bar build / 16-bar drop / 8-bar break loop.
		match _phrase_state:
			PhraseState.VERSE:
				_enter_phrase_state(PhraseState.BUILD, 4)
			PhraseState.BUILD:
				_enter_phrase_state(PhraseState.DROP, 16)
			PhraseState.DROP:
				_enter_phrase_state(PhraseState.BREAKDOWN, 8)
			PhraseState.BREAKDOWN:
				_enter_phrase_state(PhraseState.VERSE, 16)
			_:
				_enter_phrase_state(PhraseState.VERSE, 16)
		return

	# Auto — drives off vitality. Energetic tanks see drops/chorus more often.
	var vit: float = _tank_vitality
	match _phrase_state:
		PhraseState.VERSE:
			if vit > 0.4 and roll < lerpf(0.25, 0.85, vit) * _cached_drop_intensity:
				_enter_phrase_state(PhraseState.BUILD, clampi(int(lerpf(4, 2, vit)), 2, 4))
			else:
				_enter_phrase_state(PhraseState.VERSE, clampi(int(lerpf(12, 6, vit)), 4, 12))
		PhraseState.BUILD:
			_enter_phrase_state(PhraseState.DROP, clampi(int(lerpf(8, 16, vit)), 6, 16))
		PhraseState.DROP:
			if roll < 0.4:
				_enter_phrase_state(PhraseState.CHORUS, 8)
			else:
				_enter_phrase_state(PhraseState.VERSE, clampi(int(lerpf(10, 5, vit)), 4, 10))
		PhraseState.CHORUS:
			_enter_phrase_state(PhraseState.BREAKDOWN, 4)
		PhraseState.BREAKDOWN:
			_enter_phrase_state(PhraseState.VERSE, 8)
		_:
			_enter_phrase_state(PhraseState.VERSE, 8)


# Compute the 7 supersaw oscillator increments around the target frequency,
# spread by the user's detune param. Stored as phase-per-sample.
func _update_lead_increments(freq: float) -> void:
	var spread: float = _cached_lead_detune
	for i in 7:
		var cents: float = LEAD_DETUNE_CENTS[i] * spread
		var f: float = freq * pow(2.0, cents / 1200.0)
		_lead_increments[i] = f * INV_SAMPLE_RATE


func _react_to_event(event_name: String, _species: String = "") -> void:
	# Most reactions only make sense when the trance bed is live, but we still
	# allow events to nudge phrase state so the visual moment lines up.
	var bed_on: bool = _trance_bed_active()
	# Personas remap how events reshape the music. ABGT (and no persona) keep
	# the default build / drop / breakdown logic below.
	match String(_active_persona().get("event", "")):
		"jazz":
			_react_jazz(event_name)
			return
		"lofi":
			_react_lofi(event_name)
			return
		"dub":
			_react_dub(event_name)
			return
	match event_name:
		"birth":
			if bed_on:
				_chord_root = (_chord_root + 2) % 5
				_phrase_idx += 1
				_rebuild_tonal_cache()
			# Most births are background events — soft chorus lift, not a drop.
			if _phrase_state == PhraseState.VERSE and randf() < 0.18:
				_phrase_force_state = PhraseState.CHORUS
		"spawn":
			if bed_on:
				_chord_root = (_chord_root + 2) % 5
				_phrase_idx += 1
				_rebuild_tonal_cache()
			# Spawning IS the moment — force a build into a drop next bar.
			if _cached_drop_intensity > 0.2:
				_phrase_force_state = PhraseState.BUILD
		"death":
			if bed_on:
				_chord_root = (_chord_root + 5) % 5
				_rebuild_tonal_cache()
			# Breakdown depth knob decides whether death triggers the moment.
			if _cached_breakdown_depth > 0.2 and _phrase_state != PhraseState.BREAKDOWN:
				_phrase_force_state = PhraseState.BREAKDOWN
		"plant":
			_active_arp_idx = (_active_arp_idx + 1) % ARP_BANK.size()
		"eat":
			_arp_octave = mini(_arp_octave + 1, 1)
		"story":
			_phrase_idx += 2
			_apply_ecosystem_shift()


func _react_jazz(event_name: String) -> void:
	# Monk — chord substitutions + angular Rhodes / bell stabs; no festival drops.
	match event_name:
		"birth", "spawn":
			_chord_root = (_chord_root + 3) % 5  # bright substitution
			_rebuild_tonal_cache()
			play_bell_pluck(_scale_freq(4, 0), 0.09, 0.9)
			play_bell_pluck(_scale_freq(7, 0), 0.07, 0.8)
		"death":
			_chord_root = (_chord_root + 4) % 5  # dark substitution
			_rebuild_tonal_cache()
			play_rhodes(_scale_freq(2, -1), 0.10, 1.2)
		"eat":
			play_rhodes(_scale_freq(int(_seed_mix(3) * 4.0), 0), 0.08, 0.55)
		"plant":
			_active_arp_idx = (_active_arp_idx + 1) % ARP_BANK.size()
		"story":
			_phrase_idx += 2
			_apply_ecosystem_shift()


func _react_lofi(event_name: String) -> void:
	# Lo-fi — soft, behind-the-beat Rhodes / bell accents, occasional chord nudge.
	match event_name:
		"birth", "spawn":
			play_rhodes(_scale_freq(4, 0), 0.07, 1.0)
			if randf() < 0.3:
				_chord_root = (_chord_root + 2) % 5
				_rebuild_tonal_cache()
		"death":
			play_rhodes(_scale_freq(0, -1), 0.07, 1.3)
		"eat":
			play_bell_pluck(_scale_freq(7, 0), 0.05, 0.6)
		"plant":
			_active_arp_idx = (_active_arp_idx + 1) % ARP_BANK.size()
		"story":
			_phrase_idx += 1


func _react_dub(event_name: String) -> void:
	# Dub — sparse chord stabs thrown into the reverb / delay air bus + breakdowns.
	match event_name:
		"birth", "spawn":
			play_bell_pluck(_scale_freq(4, 0), 0.08, 1.1)
		"death":
			if _cached_breakdown_depth > 0.2 and _phrase_state != PhraseState.BREAKDOWN:
				_phrase_force_state = PhraseState.BREAKDOWN
		"eat":
			play_rhodes(_scale_freq(5), 0.04, 0.42)
		"plant":
			_active_arp_idx = (_active_arp_idx + 1) % ARP_BANK.size()
		"story":
			_phrase_idx += 1
			_apply_ecosystem_shift()


func _mood_key() -> String:
	var cfg := _cfg()
	return cfg.music_mood if cfg != null else "auto"


func _get_current_scale() -> Array[float]:
	# Explicit "Scale" dropdown wins; then the active persona's scale; then the
	# original mood + tank-driven major/minor selection.
	var forced: Array[float] = _scale_by_name(_scale_cfg())
	if not forced.is_empty():
		return forced
	var persona: Dictionary = _active_persona()
	if persona.has("scale"):
		var ps: Array[float] = _scale_by_name(String(persona["scale"]))
		if not ps.is_empty():
			return ps
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
	var salt: bool = not not _smooth.get("saltwater", false)
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
	# Persona tempo bias (Monk/Lo-fi slow it right down, ABGT pushes it up).
	base *= float(_active_persona().get("bpm_mul", 1.0))
	return clampf(base, 56.0, 142.0)


func _scale_freq(degree: int, octave: int = 0) -> float:
	var idx: int = clampi(_chord_root + degree, 0, _cached_scale.size() - 1)
	var key_shift: float = pow(2.0, float(_key_mod_offset) / 12.0)
	return _cached_scale[idx] * pow(2.0, float(octave)) * key_shift


func _rebuild_tonal_cache() -> void:
	_cached_scale = _get_current_scale()
	# Pick a voicing by jazziness (0..1 → triad..add9..maj9..sus2+9).
	# Minor flag flips to a darker bank when O₂ is low.
	var minor_mode: bool = float(_smooth.get("o2", 0.85)) < 0.45
	var jazz: float = _cached_jazziness
	var voicing_idx: int = clampi(int(round(jazz * 3.0)), 0, 3)
	var voicing: Array = (PAD_VOICINGS_MINOR[voicing_idx] if minor_mode
		else PAD_VOICINGS[voicing_idx])
	for i in 3:
		# Voicing may be 3 or 4 entries — wrap to fit the 3 pad voices.
		var deg: int = int(voicing[i % voicing.size()])
		var idx: int = clampi(_chord_root + deg, 0, _cached_scale.size() - 1)
		_pad_increments[i] = _cached_scale[idx] * INV_SAMPLE_RATE
	_bass_inc = _bass_freq * INV_SAMPLE_RATE
	_arp_inc = _arp_freq * INV_SAMPLE_RATE
	_arp_inc_target = _arp_inc
	# Lead defaults to chord-root upper octave; sequencer will retarget on 16ths.
	_lead_freq = _scale_freq(0, 1)
	_update_lead_increments(_lead_freq)


func _lpf_alpha(cutoff_hz: float) -> float:
	var rc: float = 1.0 / (TAU * maxf(80.0, cutoff_hz))
	return INV_SAMPLE_RATE / (rc + INV_SAMPLE_RATE)


func _refresh_mix_cache() -> void:
	_cached_bpm = _bpm()
	_cached_beat_scale = _cached_bpm / 60.0 * INV_SAMPLE_RATE
	_cached_energy = _energy()
	var vit: float = _tank_vitality
	_cached_vol = _user_volume() * _complexity() * lerpf(0.45, 1.0, _cached_energy) * lerpf(0.65, 1.0, vit)
	# Fallback defaults match TankConfig's defaults exactly so the mix sounds
	# identical whether or not the autoload is mounted (it always is at runtime;
	# this just removes a latent inconsistency for headless / test contexts).
	_cached_kick_mix = _cfg_float("music_kick_mix", 0.5)
	_cached_bass_mix = _cfg_float("music_bass_mix", 0.6)
	_cached_arp_mix = _cfg_float("music_arp_mix", 0.62)
	_cached_pad_mix = _cfg_float("music_pad_mix", 0.78)
	_cached_hat_mix = _cfg_float("music_hat_mix", 0.38)
	var filter_bias: float = _cfg_float("music_filter_open", 0.38)
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

	# Festival / lo-fi knobs cached here too so per-sample math is just a read.
	_cached_lead_mix = _lead_mix_cfg()
	_cached_lead_detune = _lead_detune_cfg()
	_cached_lead_amp = lerpf(0.018, 0.045, vit) * _cached_lead_mix
	_cached_swing = _swing_cfg()
	_cached_offbeat_hat = _offbeat_hat_cfg()
	_cached_jazziness = _jazziness_cfg()
	_cached_drop_intensity = _drop_intensity()
	_cached_breakdown_depth = _breakdown_depth()
	_cached_reverb_send = _reverb_send_cfg()
	_cached_humanize = _humanize_cfg()
	_cached_vinyl = _vinyl_cfg()
	_cached_tape_wow = _tape_wow_cfg()
	_cached_species_palette = _species_palette_cfg()
	_cached_phrase_form = _phrase_form_key()
	# Voices.
	_cached_sub_bass_amp = lerpf(0.0, 0.075, _sub_bass_cfg())
	_cached_pwm_amp = lerpf(0.0, 0.06, _pwm_bass_cfg())
	_cached_granular = _granular_cfg()
	_cached_vocoder = _vocoder_cfg()
	_cached_clap_mix = _clap_mix_cfg()
	_cached_shaker_mix = _shaker_mix_cfg()
	# Dramaturgy / breathe.
	_cached_build_drama = _build_drama_cfg()
	_cached_breathe = _breathe_cfg()
	# Tank-state driven character. Algae bloom adds bitcrush; aggression hardens
	# bass clip; aeration low cuts the kick; pH/water-quality drifts the pad.
	var bloom: float = float(_smooth.get("bloom", 0.0))
	var tannins: float = float(_smooth.get("tannins", 0.0))
	var o2: float = float(_smooth.get("o2", 0.85))
	# Bitcrush only when algae bloom is visibly high — low O₂ already ducks
	# pads/events; crushing the bed on hypoxia read as a digital error tone.
	var sick: float = clampf(tannins * 0.55 + bloom * 0.45, 0.0, 1.0)
	_cached_bitcrush = sick * _bitcrush_algae_cfg() * 0.65
	# Bass grit scales with vitality * energy (high-action tanks distort).
	_cached_bass_grit = _bass_grit_cfg() * clampf(_tank_vitality * 0.5 + _cached_energy * 0.5, 0.0, 1.0)
	_cached_pump_gate = _pump_gate_cfg()
	# Pad pH detune: bad water quality detunes pad voices ±~30 cents.
	var water_quality: float = clampf(o2 - tannins * 0.7, 0.0, 1.0)
	_cached_pad_detune = 1.0 + (1.0 - water_quality) * 0.018 * _pad_ph_quality_amount()
	_cached_key_mod = _key_mod_cfg()
	# Long-form: in-game day index drives key root shifts.
	_maybe_modulate_key()
	_compute_state_gains()
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
	if is_event and attack_time < 0.010:
		attack_time = 0.010
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
	var style: String = _style()
	# Musical voices only — the old bare play_note branch read as UI/error beeps.
	if _trance_bed_active() and not is_event:
		play_bell_pluck(freq, 0.018 + intensity * 0.016, 0.42)
	elif style == "ambient" or _mood_key() == "calm" or style == "hybrid":
		play_rhodes(freq, 0.032 + intensity * 0.028, lerpf(0.55, 0.85, _tank_vitality))
	else:
		play_bell_pluck(freq, 0.028 + intensity * 0.022, 0.62)


func play_aquarium_event(event_name: String, intensity: float = -1.0, species: String = "") -> void:
	if not _events_enabled():
		return
	_react_to_event(event_name, species)
	match event_name:
		"birth":
			play_birth_sfx(species)
		"spawn":
			play_spawn_sfx(species)
		"death":
			play_death_sfx(species)
		"eat":
			var eat_i: float = intensity if intensity >= 0.0 else randf_range(0.35, 0.65)
			play_eat_sfx(eat_i, species)
		"plant":
			play_plant_sfx(intensity if intensity >= 0.0 else randf_range(0.25, 0.55))
		"bubble":
			play_bubble_sfx(intensity if intensity >= 0.0 else randf_range(0.2, 0.5))
		"flow":
			play_flow_sfx()
		"story":
			play_riser_sfx(intensity if intensity >= 0.0 else 0.65)
		_:
			play_rhodes(_scale_freq(4), 0.04, 0.55)


# Returns a (semitone_offset, octave_offset, freq_jitter) tuple based on species.
# Bigger predators trend down an octave; tiny inverts trend up.
func _species_tone(species: String) -> Array:
	if species.is_empty() or _cached_species_palette <= 0.001:
		return [0, 0, 1.0]
	var raw: int = _species_offset(species)
	var palette: float = _cached_species_palette
	# Scale the offset by the palette knob — at 0 every species sounds the same.
	var off: int = int(round(float(raw) * palette))
	var oct: int = 0
	if off >= 8:
		oct = 1
		off -= 7
	elif off <= -8:
		oct = -1
		off += 7
	# Slight tuning jitter for organic feel.
	var jitter: float = 1.0 + (_species_offset(species + "_jit") % 7 - 3) * 0.0015 * palette
	return [off, oct, jitter]


func play_eat_sfx(intensity: float = 0.5, species: String = "") -> void:
	var tone: Array = _species_tone(species)
	var freq: float = _scale_freq(4 + int(tone[0]), int(tone[1])) * float(tone[2])
	if _trance_bed_active():
		play_bell_pluck(freq, 0.022 + intensity * 0.018, 0.22)
	else:
		play_rhodes(freq, 0.038 + intensity * 0.028, 0.38)


func play_plant_sfx(intensity: float = 0.4) -> void:
	var plant_n: int = int(_smooth.get("plants", 0))
	var freq: float = _scale_freq(int(intensity * 3.0) + (plant_n % 3) + 2) \
		* lerpf(0.99, 1.01, float(_smooth.get("biomass", 0)) / 600.0)
	play_bell_pluck(freq, 0.032 + intensity * 0.022, 0.72)
	# Soft low tom — plant events were firing a loud pitch sweep that
	# sounded like an error thud on dense Walstad tanks.
	_trigger_tom(lerpf(145.0, 110.0, intensity), 0.22 + intensity * 0.12)


func play_bubble_sfx(intensity: float = 0.35, pan: float = 99.0) -> void:
	if not _environment_enabled():
		return
	if _bubble_bursts.size() >= BUBBLE_MAX:
		return
	var aer: float = float(_smooth.get("aeration", 0.0))
	var flow: float = float(_smooth.get("flow", 0.0))
	var o2: float = clampf(float(_smooth.get("o2", 0.85)), 0.0, 1.2)
	# Delicate pop — low chirp + airy tail, not a synth beep or wind wash.
	var pearling: float = clampf((o2 - 0.88) * 4.0, 0.0, 1.0)
	var start_hz: float = lerpf(165.0, 420.0, intensity + aer * 0.06 + pearling * 0.08)
	var amp: float = lerpf(0.0014, 0.0042, intensity)
	if _trance_bed_active():
		amp *= 0.38
	var bubble_pan: float = pan if pan < 90.0 else lerpf(-0.55, 0.55, _seed_mix(int(_bubble_bursts.size() + 11)))
	_bubble_bursts.append({
		"phase": _seed_mix(int(_bubble_bursts.size() + 7)),
		"pitch_hz": start_hz,
		"env": 1.0,
		"life": lerpf(0.022, 0.048, intensity + flow * 0.08),
		"amp": amp,
		"pan": bubble_pan,
	})


func play_flow_sfx() -> void:
	play_note(_scale_freq(0, -1), 0.08, 0.32, 1.0, 0.35, 1.5, 0.03, false)


func play_riser_sfx(intensity: float = 0.65) -> void:
	# Story / diary notifications — gentle bell run, not a supersaw alarm stack.
	var degrees: Array = [0, 2, 4, 7]
	for i in degrees.size():
		play_bell_pluck(
			_scale_freq(int(degrees[i])),
			0.028 + intensity * 0.02,
			0.38 + float(i) * 0.06)


func play_birth_sfx(species: String = "") -> void:
	var tone: Array = _species_tone(species)
	var oct_shift: float = pow(2.0, float(tone[1]))
	var freq_jit: float = float(tone[2])
	if _trance_bed_active():
		play_bell_pluck(_scale_freq(0 + int(tone[0])) * oct_shift * freq_jit, 0.055, 0.42)
		play_bell_pluck(_scale_freq(4 + int(tone[0])) * oct_shift * freq_jit, 0.042, 0.36)
		return
	var scale := _get_current_scale()
	var base_idx: int = (int(_smooth.get("fish", 0)) % 4) + int(tone[0])
	for i in 3:
		var note_idx: int = clampi([base_idx, base_idx + 2, base_idx + 4][i], 0, scale.size() - 1)
		var f: float = scale[note_idx] * oct_shift * freq_jit
		play_bell_pluck(f, 0.05, 0.55 + float(i) * 0.06)


func play_death_sfx(species: String = "") -> void:
	var scale := _get_current_scale()
	var tone: Array = _species_tone(species)
	# Death always feels resolved — drop a deeper octave; bigger species → deeper.
	var oct_shift: float = pow(2.0, float(tone[1])) * 0.5
	var base_idx: int = (int(_smooth.get("plants", 0)) % 3) + int(tone[0])
	for i in 3:
		var note_idx: int = clampi([base_idx + 4, base_idx + 2, base_idx][i], 0, scale.size() - 1)
		var f: float = scale[note_idx] * oct_shift * float(tone[2])
		play_rhodes(f, 0.055, 0.75 + float(i) * 0.08)


func play_spawn_sfx(species: String = "") -> void:
	var tone: Array = _species_tone(species)
	var oct_shift: float = pow(2.0, float(tone[1]))
	var freq_jit: float = float(tone[2])
	if _trance_bed_active():
		play_bell_pluck(_scale_freq(2 + int(tone[0])) * oct_shift * freq_jit, 0.048, 0.32)
		play_bell_pluck(_scale_freq(4 + int(tone[0])) * oct_shift * freq_jit, 0.038, 0.28)
		return
	var scale := _get_current_scale()
	var base_idx: int = (int(_smooth.get("plants", 0)) % 3 + 2) + int(tone[0])
	for i in 3:
		var note_idx: int = clampi([base_idx, base_idx + 2, base_idx + 4][i], 0, scale.size() - 1)
		var f: float = scale[note_idx] * oct_shift * freq_jit
		play_bell_pluck(f, 0.042, 0.62)


func _trigger_kick(velocity: float = 1.0) -> void:
	if _kick_env < 0.06:
		_kick_phase = 0.0
	_kick_env = velocity
	_kick_pitch = lerpf(58.0, 72.0, _energy())
	# Sidechain depth scales with phrase state — slammer in DROP.
	var slam_mult: float = 0.85
	if _phrase_state == PhraseState.DROP:
		slam_mult = lerpf(0.7, 0.45, _cached_drop_intensity)
	_sidechain = lerpf(0.72, 0.38, _pp(_cfg_float("music_sidechain", 0.55), "sidechain")) * slam_mult


func _trigger_hat(velocity: float = 1.0) -> void:
	# Probability-gated — every hit has a ~15% mute chance, scaled by humanize.
	var mute_p: float = clampf(0.05 + _cached_humanize * 0.3, 0.0, 0.55)
	if randf() < mute_p:
		return
	_hat_env = velocity


func _trigger_clap(velocity: float = 1.0) -> void:
	if _cached_clap_mix <= 0.001:
		return
	_clap_env = velocity


func _trigger_shaker_grain(velocity: float = 1.0) -> void:
	if _cached_shaker_mix <= 0.001:
		return
	_shaker_env = velocity


func _trigger_tom(pitch_hz: float = 140.0, velocity: float = 1.0) -> void:
	_tom_env = velocity
	_tom_phase = 0.0
	_tom_pitch = pitch_hz


func _start_reverse_cymbal() -> void:
	if _cached_build_drama <= 0.05:
		return
	_rev_cym_active = true
	# Don't reset env if it's already swelling — just keep going.


func _stop_reverse_cymbal() -> void:
	_rev_cym_active = false
	# Env will decay tail in _render_trance_streams.


func _start_snare_roll() -> void:
	if _cached_build_drama <= 0.05:
		return
	_snare_active = true
	_snare_roll_t = 0.0


func _stop_snare_roll() -> void:
	_snare_active = false


func _trigger_pwm_bass(velocity: float = 1.0) -> void:
	if _cached_pwm_amp <= 0.0005:
		return
	_pwm_active = true
	_pwm_env = velocity
	# Use a frequency between the bass root and a fifth above for movement.
	_pwm_inc = (_bass_freq * 1.5) * INV_SAMPLE_RATE


# Fires a layered chord stab — three supersaw notes covering 1-3-5 of current
# chord. Used for schooling-detect events and pad-stab pulses in BUILD.
func play_school_stab(intensity: float = 0.55) -> void:
	if not _events_enabled():
		return
	play_supersaw(_scale_freq(0), 0.07 + intensity * 0.04, 0.45, true)
	play_supersaw(_scale_freq(4), 0.06 + intensity * 0.035, 0.42, true)
	play_supersaw(_scale_freq(7), 0.05 + intensity * 0.03, 0.38, true)


# DX-style bell pluck — high mod ratio + index, long decay. Sits perfectly in
# the lofi / Bonobo palette.
func play_bell_pluck(freq: float, amp: float, dur: float = 0.85) -> void:
	if not _events_enabled():
		return
	play_note(freq, amp, dur, 3.5, 2.4, 1.0, 0.004, true)
	# Layer a quieter octave-down "body" note for warmth.
	play_note(freq * 0.5, amp * 0.45, dur * 0.9, 1.0, 0.6, 1.4, 0.008, true)


# Rhodes-style electric piano — gentle FM, hammer-on attack.
func play_rhodes(freq: float, amp: float, dur: float = 0.7) -> void:
	if not _events_enabled():
		return
	play_note(freq, amp, dur, 1.0, 0.85, 1.8, 0.012, true)
	# Slight bell harmonic on top — DX-like character.
	play_note(freq * 2.0, amp * 0.18, dur * 0.6, 1.4, 1.2, 2.4, 0.012, true)


func _kick_on_quarter(quarter: int) -> bool:
	# Pump gate — when aeration drops below threshold, the kick disappears as
	# if the pump itself was the metronome. Comes back on with the pump.
	if _cached_pump_gate > 0.01:
		var aer: float = float(_smooth.get("aeration", 0.0))
		# At pump_gate=1.0, aer must clear 0.18 for the kick to play.
		var thresh: float = lerpf(0.0, 0.22, _cached_pump_gate)
		if aer < thresh:
			# Allow a "bar opener" pulse so silence has shape.
			return quarter % 16 == 0
	# State-aware gate. Breakdown silences kick, drop guarantees it.
	if _phrase_state == PhraseState.BREAKDOWN:
		return quarter % 16 == 0 and _cached_breakdown_depth < 0.85
	if _phrase_state == PhraseState.DROP:
		return true
	if _phrase_state == PhraseState.BUILD:
		var bar_p: float = _phrase_state_bar_pos
		if bar_p > 0.7:
			return quarter % 2 == 0
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
	if _phrase_state == PhraseState.BREAKDOWN:
		return false
	var aeration: float = float(_smooth.get("aeration", 0.0)) * _influence("music_influence_aeration")
	var fish: float = float(_smooth.get("fish", 0)) * _influence("music_influence_fish")
	var density: float = clampf(aeration * 0.35 + fish / 30.0, 0.0, 1.0)
	return quarter % 2 == 1 and density > lerpf(0.28, 0.08, _cfg_float("music_hat_mix", 0.55))


# Convert raw fractional 16th position → "swung" 16th by delaying odd 16ths.
# Pair [2k, 2k+2] in real time becomes musical [2k, 2k+1, 2k+2] where the second
# 16th lands at real-time position 1+s (s = swing*0.5). Result: shuffle feel.
func _swung_sixteenth_int(raw_16: float) -> int:
	if _cached_swing <= 0.001:
		return int(raw_16)
	var pair_start: int = int(raw_16 / 2.0) * 2
	var local: float = raw_16 - float(pair_start)
	var s: float = _cached_swing * 0.5
	# First half [0..1+s] → musical 0. Second half [1+s..2] → musical 1.
	return pair_start + (0 if local < 1.0 + s else 1)


# Lead frequency follow — slower than the arp so the line sings.
# Re-targets only on downbeat-aligned positions so the legato feels intentional.
func _maybe_retarget_lead(sixteenth: int, pattern: Array) -> void:
	if sixteenth == _lead_last_sixteenth:
		return
	# Every 4th sixteenth = every beat.
	if sixteenth % 4 != 0:
		return
	_lead_last_sixteenth = sixteenth
	var pat_idx: int = sixteenth % pattern.size()
	var degree: int = int(pattern[pat_idx])
	# Lead lives an octave above pad for the big anthem feel.
	_lead_freq = _scale_freq(degree, 1)
	_update_lead_increments(_lead_freq)


func _advance_sequencer(quarter: int, _sixteenth: int, raw_16f: float) -> void:
	var pattern: Array = _active_arp_pattern()
	# Apply swing only at the sixteenth-trigger level (kick stays on the grid).
	var swung_16: int = _swung_sixteenth_int(raw_16f)
	if swung_16 != _last_sixteenth_raw:
		_last_sixteenth_raw = swung_16
		if swung_16 % _sixteenth_div == 0 and swung_16 != _last_sixteenth:
			_last_sixteenth = swung_16
			var pat_idx: int = swung_16 % pattern.size()
			var degree: int = int(pattern[pat_idx])
			var oct: int = _arp_octave if degree > 4 else 0
			if float(_smooth.get("o2", 0.85)) < 0.5:
				oct = maxi(oct - 1, -1)
			_arp_freq = _scale_freq(degree, oct)
			_arp_inc_target = _arp_freq * INV_SAMPLE_RATE
			# Humanize velocity slightly so the line breathes.
			var human: float = 1.0 - _cached_humanize * randf_range(0.0, 0.35)
			_arp_env = lerpf(0.22, 0.58, _tank_vitality) * human
			# Lead picks up the line one beat at a time.
			_maybe_retarget_lead(swung_16, pattern)
		# Off-beat 8th hat — the trance/EDC signature.
		if _cached_offbeat_hat > 0.2 and _phrase_state != PhraseState.BREAKDOWN:
			if swung_16 % 4 == 2 and swung_16 != _last_sixteenth:
				_trigger_hat(_cached_offbeat_hat)
		# PWM off-beat bass on the "&"s — trance "dum-dum-dum-dum" between kicks.
		if _cached_pwm_amp > 0.001 and _phrase_state != PhraseState.BREAKDOWN:
			if swung_16 % 4 == 2:
				_trigger_pwm_bass(0.9)
		# Polyrhythmic shaker — 3-against-4 pattern (16ths 0, 3, 6, 9, 12, 15).
		# Tied to flow (creature movement) so it dies down on calm tanks.
		if _cached_shaker_mix > 0.001:
			var flow_n: float = float(_smooth.get("flow", 0.0))
			if flow_n > 0.18 and (swung_16 % 3 == 0):
				_trigger_shaker_grain(clampf(0.4 + flow_n * 0.6, 0.0, 1.0))
		# Pad-stab gating in BUILD: every 2 beats, gate open briefly; rest of
		# the time, the pad is muted so the build feels punctuated.
		if _phrase_state == PhraseState.BUILD and _cached_build_drama > 0.3:
			var open: bool = swung_16 % 16 == 0 or swung_16 % 16 == 8
			_pad_stab_gate = lerpf(_pad_stab_gate, 1.0 if open else 0.15, 0.045)
		else:
			_pad_stab_gate = lerpf(_pad_stab_gate, 1.0, 0.02)

	if quarter != _last_quarter:
		_last_quarter = quarter
		var bar_num: int = int(quarter / 4.0)
		if bar_num != _last_bar:
			_last_bar = bar_num
			_advance_phrase_state_at_bar(bar_num)
		# bar_pos progresses 0..1 across the state. After enter_state, total =
		# bars_left = N; each bar advance drops bars_left, so done = N - left.
		var total: float = float(maxi(1, _phrase_state_total_bars))
		var done: float = float(_phrase_state_total_bars - _phrase_state_bars_left)
		var q_frac: float = float(quarter % 4) / 4.0
		_phrase_state_bar_pos = clampf((done + q_frac) / total, 0.0, 1.0)
		_compute_state_gains()
		if _kick_on_quarter(quarter):
			# Velocity humanize so even straight 4-on-the-floor breathes.
			var v: float = 1.0 - _cached_humanize * randf_range(0.0, 0.25)
			_trigger_kick(v)
		if _hat_on_quarter(quarter):
			_trigger_hat(1.0)
		# Clap on 2 and 4 — only when the tank is energetic enough.
		if _cached_clap_mix > 0.05 and _tank_vitality > 0.45:
			if (quarter % 4 == 1) or (quarter % 4 == 3):
				_trigger_clap(0.85)
		if quarter % 4 == 0 and quarter > 0:
			var bank: Array = CHORD_DAY if _daylight_zone == 1 else CHORD_NIGHT
			if _cached_phrase_form == "trance":
				bank = CHORD_TRANCE
			var bar_num2: int = int(quarter / 4.0)
			var step: int = (_phrase_idx + (bar_num2 % _bars_per_phrase)) % bank.size()
			_chord_root = int(bank[step]) % 5
			# Pedal-tone bass during BUILD — lock to the dominant (V) so the
			# harmony above strains against it for the classic uplifting tension.
			if _phrase_state == PhraseState.BUILD and _cached_build_drama > 0.25:
				_bass_freq = _scale_freq(4, -1)   # V, octave down
			else:
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


func _render_pending_note(note: Array, env: float) -> float:
	var freq: float = note[0]
	var amp: float = note[2]
	var phase: float = note[3]
	var mod_phase: float = note[4]
	var mod_ratio: float = note[5]
	var mod_index: float = note[6]
	if mod_index > 0.08 and mod_ratio > 0.05:
		mod_phase = fposmod(mod_phase + freq * mod_ratio * INV_SAMPLE_RATE, 1.0)
		note[4] = mod_phase
		var mod_sig: float = sin(mod_phase * TAU)
		phase = fposmod(
			phase + freq * (1.0 + mod_sig * mod_index * 0.065) * INV_SAMPLE_RATE, 1.0)
	else:
		phase = fposmod(phase + freq * INV_SAMPLE_RATE, 1.0)
	note[3] = phase
	var body: float = _soft_wave(phase)
	if mod_index > 0.9:
		body = lerpf(body, sin(phase * TAU),
			clampf((mod_index - 0.9) * 0.22, 0.0, 0.4))
	return body * amp * env


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


func _dc_block_r(sample: float) -> float:
	const coeff: float = 0.996
	var out: float = sample - _dc_x_prev_r + coeff * _dc_y_prev_r
	_dc_x_prev_r = sample
	_dc_y_prev_r = out
	return out


# Vinyl-crackle sample — sparse pops + low-level filtered noise floor.
# Returns a single mono sample; caller decides L/R contribution.
func _vinyl_sample() -> float:
	if _cached_vinyl <= 0.001:
		return 0.0
	# Sparse pop generator — roughly Poisson via decay timer.
	_vinyl_pop_t -= INV_SAMPLE_RATE
	if _vinyl_pop_t <= 0.0:
		# Frequency of pops scales with knob; ~2..18 pops/sec at full.
		var rate_hz: float = lerpf(0.8, 18.0, _cached_vinyl)
		_vinyl_pop_t = lerpf(0.04, 1.2, randf()) / maxf(0.1, rate_hz)
		_vinyl_pop_env = randf_range(0.35, 0.75) * _cached_vinyl
		_vinyl_pop_freq = lerpf(400.0, 1800.0, randf())
	var pop: float = 0.0
	if _vinyl_pop_env > 0.001:
		# Bandpassed noise burst — sine pops at 900–4200 Hz read as UI clicks.
		var pop_raw: float = _noise_sample() * _vinyl_pop_env
		_vinyl_noise_lpf = _one_pole_cached(pop_raw, _vinyl_noise_lpf, _lpf_alpha(2400.0))
		pop = _vinyl_noise_lpf
		_vinyl_pop_env *= 0.968
	# Low-level filtered noise floor — gives that 7" record hiss.
	var hiss_raw: float = _noise_sample()
	_vinyl_noise_lpf = _one_pole_cached(hiss_raw, _vinyl_noise_lpf, _lpf_alpha(3200.0))
	var floor_amp: float = _cached_vinyl * 0.008
	return (pop * 0.032 + _vinyl_noise_lpf * floor_amp)


# Tape-wow — write to ring buffer, read with LFO-modulated position so the
# pitch drifts slightly. Stereo to keep the image alive.
func _apply_tape_wow(in_l: float, in_r: float) -> Vector2:
	if _cached_tape_wow <= 0.001:
		return Vector2(in_l, in_r)
	var buf_len: int = _wow_buf.size()
	_wow_buf[_wow_pos] = in_l
	_wow_buf_r[_wow_pos] = in_r
	_wow_pos = (_wow_pos + 1) % buf_len
	# Two LFOs — slow wow + faster flutter. Aeration nudges the flutter rate.
	var aer: float = float(_smooth.get("flow", 0.0))
	_wow_lfo = fposmod(_wow_lfo + 0.4 * INV_SAMPLE_RATE, 1.0)
	_wow_lfo2 = fposmod(_wow_lfo2 + (3.6 + aer * 2.4) * INV_SAMPLE_RATE, 1.0)
	# Base delay 12 samples; modulate by up to ~10 samples either side.
	var depth: float = _cached_tape_wow * 9.0
	var off_l: float = 12.0 + depth * sin(_wow_lfo * TAU) + depth * 0.35 * sin(_wow_lfo2 * TAU)
	var off_r: float = 12.0 + depth * sin((_wow_lfo + 0.5) * TAU) + depth * 0.35 * sin((_wow_lfo2 + 0.25) * TAU)
	# Fractional read — linear interpolation between two samples.
	var read_l_pos: float = fposmod(float(_wow_pos) - off_l, float(buf_len))
	var read_r_pos: float = fposmod(float(_wow_pos) - off_r, float(buf_len))
	var i_l: int = int(read_l_pos)
	var i_r: int = int(read_r_pos)
	var f_l: float = read_l_pos - float(i_l)
	var f_r: float = read_r_pos - float(i_r)
	var l0: float = _wow_buf[i_l]
	var l1: float = _wow_buf[(i_l + 1) % buf_len]
	var r0: float = _wow_buf_r[i_r]
	var r1: float = _wow_buf_r[(i_r + 1) % buf_len]
	var out_l: float = lerpf(l0, l1, f_l)
	var out_r: float = lerpf(r0, r1, f_r)
	# Mix dry/wet so the wow is subtle at low knob values.
	var mix: float = clampf(_cached_tape_wow, 0.0, 1.0)
	return Vector2(lerpf(in_l, out_l, mix), lerpf(in_r, out_r, mix))


func _mix_bubble_bursts() -> Vector2:
	var out_l: float = 0.0
	var out_r: float = 0.0
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
		var pan: float = float(b.get("pan", 0.0))
		# Quick downward chirp + soft airy tail — a tiny surface pop, not a tone.
		pitch_hz = maxf(90.0, pitch_hz * 0.9988)
		var atk: float = smoothstep(0.0, 1.0, 1.0 - env)
		var chirp: float = sin(phase * TAU) * env * env * atk
		var airy: float = _noise_sample() * env * env * 0.11
		var sample: float = (chirp * 0.16 + airy) * amp
		var pan_l: float = 1.0 - maxf(pan, 0.0) * 0.42
		var pan_r: float = 1.0 + minf(pan, 0.0) * 0.42
		out_l += sample * pan_l
		out_r += sample * pan_r
		b["phase"] = fposmod(phase + pitch_hz * INV_SAMPLE_RATE, 1.0)
		b["pitch_hz"] = pitch_hz
		b["env"] = env * 0.988
		b["life"] = life - INV_SAMPLE_RATE
		_bubble_bursts[i] = b
	return Vector2(out_l, out_r)


# Per-frame output accumulators — written by _render_trance_streams each sample.
# Six floats avoid allocating a Vector2 array per sample.
var _f_drums_l: float = 0.0
var _f_drums_r: float = 0.0
var _f_synth_l: float = 0.0
var _f_synth_r: float = 0.0
var _f_air_l: float = 0.0
var _f_air_r: float = 0.0


func _render_trance_streams() -> void:
	var beat_time: float = float(_sample_clock) * _cached_beat_scale
	_cached_beat_time = beat_time
	var quarter: int = int(beat_time)
	var sixteenth_f: float = beat_time * 4.0
	var sixteenth: int = int(sixteenth_f)
	_advance_sequencer(quarter, sixteenth, sixteenth_f)

	# Sidechain envelope decays toward 1 (released) between kicks.
	_sidechain = lerpf(_sidechain, 1.0, 0.00085)
	var sc: float = _sidechain
	var vol: float = _cached_vol

	# ---- DRUMS BUS ----
	var d_l: float = 0.0
	var d_r: float = 0.0

	if _kick_env > 0.001:
		_kick_phase += _kick_pitch * INV_SAMPLE_RATE
		_kick_pitch = maxf(42.0, _kick_pitch - _kick_pitch_decay)
		var kick_body: float = sin(_kick_phase * TAU) * _kick_env * _kick_env
		var kick_out: float = kick_body * vol * _cached_kick_gain * _cached_kick_mix * _state_kick_gain
		d_l += kick_out
		d_r += kick_out
		_kick_env *= 0.9994

	if _hat_env > 0.001:
		var hat_raw: float = _noise_sample() * _hat_env
		_lpf_hat = _one_pole_cached(hat_raw, _lpf_hat, _lpf_alpha(2800.0))
		var hat_out: float = _lpf_hat * vol * _cached_hat_mul * _state_hat_gain
		# Slight pan to add stereo image to the drums bus.
		d_l += hat_out * 1.05
		d_r += hat_out * 0.95
		_hat_env *= 0.9935

	# Clap — wide noise burst, panned ±, on 2 & 4 in high-energy phases.
	if _clap_env > 0.001:
		var clap_raw: float = _noise_sample() * _clap_env
		_clap_lpf = _one_pole_cached(clap_raw, _clap_lpf, _lpf_alpha(1800.0))
		var clap_out: float = _clap_lpf * vol * _cached_clap_mix * 0.7
		# Stereo width via L/R noise decorrelation.
		d_l += clap_out * 0.9
		d_r += clap_out * 1.1 + _noise_sample() * _clap_env * 0.005
		_clap_env *= 0.985

	# Polyrhythmic shaker — 16th-note presence weighted to creature movement.
	if _shaker_env > 0.001:
		var sk_raw: float = _noise_sample() * _shaker_env
		_shaker_lpf = _one_pole_cached(sk_raw, _shaker_lpf, _lpf_alpha(5200.0))
		var sk_out: float = _shaker_lpf * vol * _cached_shaker_mix * 0.55
		# Slightly off-centre right so it complements the L-biased hat.
		d_l += sk_out * 0.85
		d_r += sk_out
		_shaker_env *= 0.9905

	# Tom roll/fills — sparse, fired by plant events.
	if _tom_env > 0.001:
		_tom_phase += _tom_pitch * INV_SAMPLE_RATE
		var tom_body: float = sin(_tom_phase * TAU) * _tom_env
		_tom_pitch = maxf(70.0, _tom_pitch - 60.0 * INV_SAMPLE_RATE)
		var tom_out: float = tom_body * vol * 0.18
		d_l += tom_out
		d_r += tom_out
		_tom_env *= 0.9988

	# Snare roll — accelerating noise bursts in the last bar of BUILD.
	if _snare_active and _state_riser_gain > 0.05:
		_snare_roll_t -= INV_SAMPLE_RATE
		if _snare_roll_t <= 0.0:
			# Hit rate accelerates from ~8 to ~32 Hz across the build tail.
			var rate: float = lerpf(8.0, 32.0, clampf(_phrase_state_bar_pos, 0.0, 1.0))
			_snare_roll_t = 1.0 / rate
			_snare_roll_env = randf_range(0.55, 0.95)
		if _snare_roll_env > 0.001:
			var sn_raw: float = _noise_sample() * _snare_roll_env
			var sn_out: float = sn_raw * vol * 0.12 * _state_riser_gain
			d_l += sn_out
			d_r += sn_out * 0.95
			_snare_roll_env *= 0.9885
	else:
		_snare_roll_env = 0.0

	_f_drums_l = d_l
	_f_drums_r = d_r

	# ---- SYNTH BUS ----
	var s_l: float = 0.0
	var s_r: float = 0.0

	if _cached_bass_active:
		_bass_phase = fposmod(_bass_phase + _bass_inc, 1.0)
		# Bass-grit hardens the soft-clip based on aggression knob.
		var b_raw: float = _soft_wave(_bass_phase)
		var grit: float = _cached_bass_grit
		var b_clipped: float = tanh(b_raw * (1.0 + grit * 3.0)) * lerpf(1.0, 0.78, grit)
		var bass_out: float = b_clipped * _cached_bass_amp * vol * sc * _state_bass_gain
		s_l += bass_out
		s_r += bass_out

		# Sub-bass — pure sine, 1 octave below the melodic bass.
		_sub_phase = fposmod(_sub_phase + _sub_inc, 1.0)
		var sub: float = sin(_sub_phase * TAU) * _cached_sub_bass_amp * vol * sc * _state_bass_gain
		s_l += sub
		s_r += sub

	# PWM off-beat bass — gated on by sequencer on "&"s.
	if _pwm_active and _pwm_env > 0.001:
		_pwm_phase = fposmod(_pwm_phase + _pwm_inc, 1.0)
		_pwm_lfo = fposmod(_pwm_lfo + 0.6 * INV_SAMPLE_RATE, 1.0)
		# PWM width oscillates 0.35..0.65 → squarish to thin pulse.
		var width: float = 0.5 + sin(_pwm_lfo * TAU) * 0.15
		var sq: float = -1.0 if _pwm_phase < width else 1.0
		# Soft-shape so square edges don't alias too much.
		var sq_soft: float = tanh(sq * 0.9) * 0.7
		var pwm_out: float = sq_soft * _cached_pwm_amp * _pwm_env * vol * sc * _state_bass_gain
		s_l += pwm_out
		s_r += pwm_out
		_pwm_env *= 0.9988

	# Pad — sums three voices, panned via voice 0/2 difference.
	_pad_phases[0] = fposmod(_pad_phases[0] + _pad_increments[0] * _cached_pad_detune, 1.0)
	_pad_phases[1] = fposmod(_pad_phases[1] + _pad_increments[1], 1.0)
	_pad_phases[2] = fposmod(_pad_phases[2] + _pad_increments[2] / _cached_pad_detune, 1.0)
	var pad_v0: float = _soft_wave(_pad_phases[0])
	var pad_v1: float = _soft_wave(_pad_phases[1])
	var pad_v2: float = _soft_wave(_pad_phases[2])
	var pad_mix_raw: float = (pad_v0 + pad_v1 + pad_v2) * 0.333333

	# Wavetable morph — single oscillator blending sine→saw as daylight rises.
	_wt_phase = fposmod(_wt_phase + _pad_increments[1] * 0.5, 1.0)
	var wt_sin: float = sin(_wt_phase * TAU)
	var wt_saw: float = _wt_phase * 2.0 - 1.0
	var wt_blend: float = clampf(float(_smooth.get("daylight", 1.0)), 0.0, 1.0)
	var wt_voice: float = lerpf(wt_sin, wt_saw, wt_blend * 0.7) * 0.4
	pad_mix_raw += wt_voice * 0.5

	_lpf_pad = _one_pole_cached(pad_mix_raw, _lpf_pad, _cached_pad_lpf_alpha)
	# Pad stabs in BUILD — gated rhythmically to add anticipation. The stab
	# gate is computed in _advance_sequencer; we just respect it here.
	var pad_stab_gate: float = lerpf(0.45, 1.0, _pad_stab_gate)
	var pad_out: float = _lpf_pad * _cached_pad_level * vol * sc * _cached_pad_mix * _state_pad_gain * pad_stab_gate

	# Granular pad — re-pitched echoes of pad output.
	var grain_amp: float = _cached_granular
	var pad_l: float = pad_out + (pad_v0 - pad_v2) * 0.18 * _cached_pad_level * vol * _cached_pad_mix
	var pad_r: float = pad_out + (pad_v2 - pad_v0) * 0.18 * _cached_pad_level * vol * _cached_pad_mix
	if grain_amp > 0.01:
		# Write current pad value into the ring buffer.
		_grain_buf[_grain_pos] = pad_mix_raw
		_grain_pos = (_grain_pos + 1) % _grain_size
		# Read at a pitch-shifted position — sin LFO modulates the offset.
		_grain_read = fposmod(_grain_read + _grain_inc, float(_grain_size))
		var gi: int = int(_grain_read)
		var gf: float = _grain_read - float(gi)
		var gn: int = (gi + 1) % _grain_size
		var grain_sample: float = lerpf(_grain_buf[gi], _grain_buf[gn], gf)
		# Bloom drives shimmer amplitude.
		var bl: float = float(_smooth.get("bloom", 0.0))
		var shimmer: float = grain_sample * grain_amp * (0.5 + bl * 1.5) * _cached_pad_level * vol * _cached_pad_mix
		pad_l += shimmer * 0.85
		pad_r += shimmer * 1.15

	# Vocoded "aah" — pad output modulated by bubble-noise envelope.
	if _cached_vocoder > 0.01:
		var voc_target: float = float(_smooth.get("aeration", 0.0)) * 0.55 + float(_smooth.get("bloom", 0.0)) * 0.4
		_voc_env = lerpf(_voc_env, voc_target, 0.00012)
		var voc_raw: float = _noise_sample() * _voc_env
		_voc_lpf = _one_pole_cached(voc_raw, _voc_lpf, _lpf_alpha(900.0))
		# Multiply (ring-mod) by pad output so we get a vowel "aah" character.
		var voc_voice: float = _voc_lpf * pad_mix_raw * _cached_vocoder * vol * 0.6
		pad_l += voc_voice * 0.85
		pad_r += voc_voice * 1.15

	s_l += pad_l
	s_r += pad_r

	# Arp — also gets sidechain. Slight stereo via dotted-eighth feel.
	_arp_inc = lerpf(_arp_inc, _arp_inc_target, 0.0018)
	if _arp_env > 0.0005:
		_arp_phase = fposmod(_arp_phase + _arp_inc, 1.0)
		var arp_raw: float = _soft_wave(_arp_phase)
		_lpf_arp = _one_pole_cached(arp_raw, _lpf_arp, _cached_arp_lpf_alpha)
		var arp_out: float = _lpf_arp * _arp_env * _cached_arp_level * vol * sc * _state_arp_gain
		s_l += arp_out * 0.78
		s_r += arp_out * 1.22
		_arp_env *= _cached_arp_decay

	# Supersaw lead — 7 detuned saws with stereo spread + envelope follower.
	_lead_env = lerpf(_lead_env, _lead_target_env, 0.0035)
	if _lead_env > 0.001 and _state_lead_gain > 0.001:
		var lead_l: float = 0.0
		var lead_r: float = 0.0
		for i in 7:
			_lead_phases[i] = fposmod(_lead_phases[i] + _lead_increments[i], 1.0)
			var saw: float = _lead_phases[i] * 2.0 - 1.0
			var pan: float = LEAD_PAN[i]
			lead_l += saw * (0.5 - pan * 0.5)
			lead_r += saw * (0.5 + pan * 0.5)
		lead_l *= 0.18
		lead_r *= 0.18
		var cutoff_open: float = lerpf(900.0, 7400.0,
			_state_lead_gain * (0.4 + _phrase_state_bar_pos * 0.6))
		var lalpha: float = _lpf_alpha(cutoff_open)
		_lead_lpf_l = _one_pole_cached(lead_l, _lead_lpf_l, lalpha)
		_lead_lpf_r = _one_pole_cached(lead_r, _lead_lpf_r, lalpha)
		var lead_amp: float = _cached_lead_amp * _lead_env * _state_lead_gain * vol * sc
		s_l += _lead_lpf_l * lead_amp
		s_r += _lead_lpf_r * lead_amp

	# White-noise riser.
	var riser_target: float = _state_riser_gain
	_riser_env = lerpf(_riser_env, riser_target, 0.0015)
	if _riser_env > 0.001:
		var n_l: float = _noise_sample() * _riser_env
		var n_r: float = _noise_sample() * _riser_env
		var sweep: float = lerpf(380.0, 9200.0, _phrase_state_bar_pos)
		var ralpha: float = _lpf_alpha(sweep)
		_riser_lpf = _one_pole_cached(n_l, _riser_lpf, ralpha)
		var ramp: float = 0.018 + _phrase_state_bar_pos * 0.06
		var amp: float = ramp * vol * _cached_drop_intensity
		s_l += _riser_lpf * amp
		s_r += _riser_lpf * amp + n_r * ramp * 0.4 * vol * _cached_drop_intensity

	# Reverse cymbal swell — envelope climbs while active, hard-cut by DROP.
	if _rev_cym_active and _rev_cym_env < 1.0:
		_rev_cym_env = minf(1.0, _rev_cym_env + 0.0000115)   # ~6 s ramp
		var rc_raw: float = _noise_sample() * _rev_cym_env
		_rev_cym_lpf = _one_pole_cached(rc_raw, _rev_cym_lpf,
			_lpf_alpha(lerpf(1200.0, 9200.0, _rev_cym_env)))
		var rc_out: float = _rev_cym_lpf * _rev_cym_env * vol * 0.18 * _cached_drop_intensity
		s_l += rc_out
		s_r += rc_out * 1.05
	elif _rev_cym_env > 0.001:
		# Tail after a DROP-triggered cut — fast decay so it doesn't linger.
		_rev_cym_env *= 0.92

	# Master LPF cutoff modulated by breathe LFO and BUILD filter sweep.
	_breathe_phase = fposmod(_breathe_phase + (1.0 / 75.0) * INV_SAMPLE_RATE, 1.0)
	var breathe: float = sin(_breathe_phase * TAU)
	var build_open: float = 0.0
	if _phrase_state == PhraseState.BUILD:
		build_open = _phrase_state_bar_pos
	var base_cut: float = lerpf(2400.0, 9800.0, build_open)
	base_cut *= lerpf(1.0 - _cached_breathe * 0.45, 1.0 + _cached_breathe * 0.45,
		breathe * 0.5 + 0.5)
	_cached_master_cut = base_cut
	_lpf_master = _one_pole_cached((s_l + s_r) * 0.5, _lpf_master, _lpf_alpha(_cached_master_cut))
	# Mix some of the LPF into each channel — keeps stereo width but tames highs.
	var centre_blend: float = 0.18
	s_l = lerpf(s_l, _lpf_master, centre_blend)
	s_r = lerpf(s_r, _lpf_master, centre_blend)

	_lfo_phase = fposmod(_lfo_phase + _cached_lfo_hz * INV_SAMPLE_RATE, 1.0)
	_f_synth_l = s_l
	_f_synth_r = s_r

	# Air bus is rendered separately in _process (it depends on _pending notes
	# and bubble bursts which are managed there). We zero it here so the
	# accumulators don't carry stale data between frames.
	_f_air_l = 0.0
	_f_air_r = 0.0


func _playback_headroom() -> int:
	if _playback_drums == null or _playback_synth == null or _playback_air == null:
		return 0
	return mini(
		_playback_drums.get_frames_available(),
		mini(_playback_synth.get_frames_available(), _playback_air.get_frames_available()))


func _fill_playback_buffers(batch: int) -> void:
	if batch <= 0:
		return
	var trance_on: bool = _trance_bed_active()
	var delay_amt: float = _cfg_float("music_delay_amount", 0.35)
	var delay_fb: float = lerpf(0.14, 0.28, _cached_energy) if trance_on else 0.0
	var delay_mix: float = lerpf(0.06, 0.16, _cached_energy) * delay_amt if trance_on else 0.0
	var pending_n: int = _pending.size()
	var vinyl_active: bool = _cached_vinyl > 0.001
	var wow_active: bool = _cached_tape_wow > 0.001
	var bitcrush_active: bool = _cached_bitcrush > 0.001

	for _f in batch:
		# ---- Drums + Synth bed (multi-stream renderer writes _f_*) ----
		if trance_on:
			_render_trance_streams()
		else:
			_f_drums_l = 0.0
			_f_drums_r = 0.0
			_f_synth_l = 0.0
			_f_synth_r = 0.0
			_f_air_l = 0.0
			_f_air_r = 0.0

		# ---- Pending event notes (plinks) ----
		var plinks: float = 0.0
		for j in range(pending_n - 1, -1, -1):
			var note = _pending[j]
			var dur: float = note[1]
			if dur <= INV_SAMPLE_RATE:
				_pending.remove_at(j)
				pending_n -= 1
				continue

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

			plinks += _render_pending_note(note, env)

			note[1] = dur - INV_SAMPLE_RATE
			_pending[j] = note

		_plink_lpf = _one_pole_cached(plinks, _plink_lpf, _lpf_alpha(3800.0))
		plinks = _plink_lpf

		var bubbles: Vector2 = _mix_bubble_bursts()
		var event_vol: float = _cached_vol
		_f_air_l = (plinks + bubbles.x) * event_vol
		_f_air_r = (plinks + bubbles.y) * event_vol

		# Ping-pong delay on the air bus (synth bed already has bus reverb).
		if trance_on and delay_mix > 0.0:
			var delayed_l: float = _delay_buf[_delay_pos]
			var delayed_r: float = _delay_buf_r[_delay_pos]
			_delay_buf[_delay_pos] = _f_air_r + delayed_r * delay_fb
			_delay_buf_r[_delay_pos] = _f_air_l + delayed_l * delay_fb
			_delay_pos = (_delay_pos + 1) % DELAY_LEN
			_f_air_l = _f_air_l * (1.0 - delay_mix) + delayed_l * delay_mix
			_f_air_r = _f_air_r * (1.0 - delay_mix) + delayed_r * delay_mix

		# Vinyl crackle goes onto the Air bus (envelope/dust character).
		if vinyl_active:
			var vinyl: float = _vinyl_sample()
			_f_air_l += vinyl
			_f_air_r += vinyl * 0.78 + _noise_sample() * _cached_vinyl * 0.004

		# ---- Aquatic ambience bed ----
		var aer_smooth: float = float(_smooth.get("aeration", 0.0))
		var o2_amb: float = clampf(float(_smooth.get("o2", 0.85)), 0.0, 1.2)
		var pearl_amb: float = clampf((o2_amb - 0.87) * 3.0, 0.0, 1.0)
		var fizz_drive: float = maxf(aer_smooth - 0.06, 0.0) * 0.85 + pearl_amb * 0.35
		if fizz_drive > 0.012:
			_water_fizz_lfo = fposmod(_water_fizz_lfo + 0.38 * INV_SAMPLE_RATE, 1.0)
			var breathe: float = 0.35 + 0.65 * (0.5 + 0.5 * sin(_water_fizz_lfo * TAU))
			var amb_level: float = fizz_drive * breathe * 0.0032
			_water_lpf_l = _one_pole_cached(_noise_sample(), _water_lpf_l, _lpf_alpha(920.0))
			_water_lpf_r = _one_pole_cached(_noise_sample(), _water_lpf_r, _lpf_alpha(1080.0))
			_f_air_l += (_water_lpf_l * 0.72 + _water_lpf_r * 0.08) * amb_level
			_f_air_r += (_water_lpf_r * 0.72 + _water_lpf_l * 0.08) * amb_level

		# Per-fish presence pan: bias the whole air bus toward the watched fish.
		if _presence_pan != 0.0:
			var pan_l: float = 1.0 - maxf(_presence_pan, 0.0) * 0.5
			var pan_r: float = 1.0 + minf(_presence_pan, 0.0) * 0.5
			_f_air_l *= pan_l
			_f_air_r *= pan_r

		# Tape wow — applied to the synth bus only so drums stay rhythmically tight.
		if wow_active:
			var w: Vector2 = _apply_tape_wow(_f_synth_l, _f_synth_r)
			_f_synth_l = w.x
			_f_synth_r = w.y

		# Bitcrush from algae/sick tank — sample-and-hold reduces resolution.
		if bitcrush_active:
			_bc_phase += _cached_bitcrush * 0.18
			if _bc_phase >= 1.0:
				_bc_phase = 0.0
				_bc_hold_l = _f_synth_l
				_bc_hold_r = _f_synth_r
			else:
				_f_synth_l = lerpf(_f_synth_l, _bc_hold_l, _cached_bitcrush)
				_f_synth_r = lerpf(_f_synth_r, _bc_hold_r, _cached_bitcrush)

		# Per-stream DC block + soft clip.
		var drums_l: float = _soft_clip(_f_drums_l)
		var drums_r: float = _soft_clip(_f_drums_r)
		var synth_l: float = _soft_clip(_dc_block(_f_synth_l))
		var synth_r: float = _soft_clip(_dc_block_r(_f_synth_r))
		var air_l: float = _soft_clip(_f_air_l)
		var air_r: float = _soft_clip(_f_air_r)

		_playback_drums.push_frame(Vector2(drums_l, drums_r))
		_playback_synth.push_frame(Vector2(synth_l, synth_r))
		_playback_air.push_frame(Vector2(air_l, air_r))

		# Recording — write the summed pre-bus mix to the recording buffer.
		if _recording and _recording_buffer.size() < _recording_max_samples:
			_recording_buffer.push_back(Vector2(
				clampf(drums_l + synth_l + air_l, -1.0, 1.0),
				clampf(drums_r + synth_r + air_r, -1.0, 1.0)))

		_sample_clock += 1


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
				_accent_t = lerpf(24.0, 4.2, vit * _cfg_float("music_accent_density", 0.5)) * lerpf(1.2, 0.75, dl)
				var accent_i: float = clampf(
					vit * 0.55 + float(_smooth.get("bloom", 0.0)) * 0.2, 0.08, 0.75)
				play_rhodes(_scale_freq(2 + int(accent_i * 3.0)), 0.028 + accent_i * 0.02, 0.48)

	if _environment_enabled() and _sim_ref != null:
		var aeration: float = float(_smooth.get("aeration", 0.0))
		var flow: float = float(_smooth.get("flow", 0.0))
		var o2: float = clampf(float(_smooth.get("o2", 0.85)), 0.0, 1.2)
		var pearling: float = clampf((o2 - 0.86) * 3.5, 0.0, 1.0)
		var activity: float = maxf(flow, _swim_activity)
		var bubble_rate: float = (
			aeration * 0.42 + flow * 0.18 + pearling * 0.22 + activity * 0.12) * _drive()
		if bubble_rate > 0.025:
			_bubble_t -= sim_dt
			if _bubble_t <= 0.0:
				var interval: float = lerpf(5.5, 0.45, clampf(bubble_rate, 0.0, 1.0))
				interval *= lerpf(1.25, 0.82, _tank_vitality)
				if _trance_bed_active():
					interval *= 1.55
				_bubble_t = interval
				var pop_i: float = clampf(
					bubble_rate * 0.28 + aeration * 0.14 + pearling * 0.1, 0.1, 0.55)
				play_bubble_sfx(pop_i)
				# Aeration / pearling sometimes throws a tiny cluster instead of one pop.
				if bubble_rate > 0.35 and randf() < aeration * 0.22 + pearling * 0.18:
					play_bubble_sfx(pop_i * randf_range(0.65, 0.92), randf_range(-0.4, 0.4))
	_swim_activity = lerpf(_swim_activity, 0.0, clampf(sim_dt * 1.6, 0.0, 0.4))

	var user_volume: float = _user_volume()
	# Apply same dynamic volume_db to all three streams. Bus-level volumes in
	# default_bus_layout.tres handle the drums-vs-synth-vs-air balance.
	var target_db: float = -80.0
	if user_volume > 0.01:
		var dl: float = float(_smooth.get("daylight", 1.0))
		# Slightly lower ceiling than the old single-stream path because three
		# streams sum into the Master bus.
		var max_db: float = lerpf(-32.0, -10.0, user_volume)
		var min_db: float = lerpf(-42.0, -17.0, user_volume)
		target_db = lerpf(min_db, max_db, dl)
		if TopdownMotion.pond_active:
			target_db += 2.0
			target_db = lerpf(target_db, max_db, 0.18)
	if _player_drums != null:
		_player_drums.volume_db = target_db
	if _player_synth != null:
		_player_synth.volume_db = target_db
	if _player_air != null:
		_player_air.volume_db = target_db - 0.5   # air sits under music, not on top

	# Periodically refresh the bus-level reverb damping from water temperature.
	if Engine.get_process_frames() % 60 == 0:
		_apply_temperature_to_reverb()

	# Procedural synth — tempo is sample-clock driven, so we must keep the
	# generator fed even when the 3D pass drops FPS (High fidelity + dense tanks).
	var fill_start_us: int = Time.get_ticks_usec()
	while true:
		var headroom: int = _playback_headroom()
		if headroom <= 0:
			break
		var batch: int = mini(headroom, MAX_SAMPLES_CATCHUP)
		if headroom <= MAX_SAMPLES_PER_FRAME:
			batch = headroom
		_fill_playback_buffers(batch)
		if Time.get_ticks_usec() - fill_start_us >= AUDIO_FILL_BUDGET_US:
			break
		if _playback_headroom() <= MAX_SAMPLES_PER_FRAME:
			break


func get_live_status() -> Dictionary:
	var beat_phase: float = fposmod(_cached_beat_time, 1.0)
	var bar_phase: float = fposmod(_cached_beat_time / 4.0, 1.0)
	var scale_mode: String = "major"
	if TankConfig.music_mood in ["calm", "deep"]:
		scale_mode = "minor"
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
		"phrase_state": _phrase_state,
		"phrase_state_name": _phrase_state_name(),
		"phrase_state_bars_left": _phrase_state_bars_left,
		"phrase_state_progress": _phrase_state_bar_pos,
		"beat_phase": beat_phase,
		"bar_phase": bar_phase,
		"bar_count": maxi(0, _last_bar),
		"swing": _cached_swing,
		"humanize": _cached_humanize,
		"scale_mode": scale_mode,
	}


func _phrase_state_name() -> String:
	match _phrase_state:
		PhraseState.VERSE: return "verse"
		PhraseState.BUILD: return "build"
		PhraseState.DROP: return "drop"
		PhraseState.BREAKDOWN: return "breakdown"
		PhraseState.CHORUS: return "chorus"
	return "?"


func randomize_performance() -> void:
	_phrase_idx += 3
	_chord_root = int(_seed_mix(41) * 5.0) % 5
	_pick_arp_from_tank(false)
	_apply_ecosystem_shift()
	_accent_t = 0.5
	_refresh_mix_cache()


# ===================== Audio recording (export to WAV) ======================

# Begin recording the mixed master output. Returns true when actually started.
func start_recording() -> bool:
	if _recording:
		return false
	_recording_buffer.clear()
	_recording = true
	return true


func is_recording() -> bool:
	return _recording


# Returns recording length in seconds.
func recording_length() -> float:
	return float(_recording_buffer.size()) * INV_SAMPLE_RATE


# Stop recording and save to user://recordings/{name}.wav. Returns the path
# saved to (or empty string on failure).
func stop_recording_and_save() -> String:
	if not _recording:
		return ""
	_recording = false
	if _recording_buffer.is_empty():
		return ""
	# Ensure directory exists.
	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists("recordings"):
		dir.make_dir("recordings")
	var time_dict: Dictionary = Time.get_datetime_dict_from_system()
	var stamp: String = "%04d%02d%02d_%02d%02d%02d" % [
		int(time_dict.get("year", 0)),
		int(time_dict.get("month", 0)),
		int(time_dict.get("day", 0)),
		int(time_dict.get("hour", 0)),
		int(time_dict.get("minute", 0)),
		int(time_dict.get("second", 0)),
	]
	var path: String = "user://recordings/iaquarium_%s.wav" % stamp
	if _write_wav(path):
		var saved_path: String = path
		_recording_buffer.clear()
		return saved_path
	return ""


# Write the buffered Vector2 samples as a 16-bit stereo PCM WAV.
func _write_wav(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("AmbientAudio: failed to open " + path + " for writing")
		return false
	var n: int = _recording_buffer.size()
	var bytes_per_sample: int = 2
	var channels: int = 2
	var data_size: int = n * channels * bytes_per_sample
	var file_size: int = 36 + data_size
	# RIFF header.
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(file_size)
	f.store_buffer("WAVE".to_ascii_buffer())
	# fmt chunk.
	f.store_buffer("fmt ".to_ascii_buffer())
	f.store_32(16)   # fmt chunk size
	f.store_16(1)    # PCM
	f.store_16(channels)
	f.store_32(SAMPLE_RATE)
	f.store_32(SAMPLE_RATE * channels * bytes_per_sample)   # byte_rate
	f.store_16(channels * bytes_per_sample)                  # block_align
	f.store_16(bytes_per_sample * 8)                         # bits_per_sample
	# data chunk.
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(data_size)
	# Samples as int16 LE, interleaved L/R.
	for i in n:
		var s: Vector2 = _recording_buffer[i]
		var l: int = clampi(int(s.x * 32767.0), -32768, 32767)
		var r: int = clampi(int(s.y * 32767.0), -32768, 32767)
		f.store_16(l & 0xFFFF)
		f.store_16(r & 0xFFFF)
	f.close()
	return true


# ===================== Creature-behaviour event hooks ======================

# Sim-driver fires this when a fish cluster is detected. The audio side
# responds with a unison chord stab.
func play_schooling_event(intensity: float = 0.55) -> void:
	# Throttle so big schools don't fire constantly.
	var now: float = float(_sample_clock) * INV_SAMPLE_RATE
	if now - _last_school_t < 4.0:
		return
	_last_school_t = now
	play_school_stab(intensity)


# Sim-driver fires this on food drop. Sends the bed into a 2-bar BUILD that
# resolves on the next bar with whatever lands on play_eat_sfx.
func play_feeding_event() -> void:
	if _cached_drop_intensity > 0.2:
		_phrase_force_state = PhraseState.BUILD


# Sim-driver can fire this with cause_of_death info for richer death notes.
# `cause` ∈ "starvation" | "hypoxia" | "age" | "predation" | ""
func play_aquarium_event_extended(event_name: String, species: String = "",
		intensity: float = -1.0, age01: float = -1.0, cause: String = "") -> void:
	if event_name == "death":
		# Age-coded death — young = higher minor7; old = tonic resolved.
		# (We don't have age in the standard signature so route here when set.)
		_react_to_event("death", species)
		var scale := _get_current_scale()
		var tone: Array = _species_tone(species)
		var base_idx: int = (int(_smooth.get("plants", 0)) % 3) + int(tone[0])
		var oct_shift: float = pow(2.0, float(tone[1])) * 0.5
		# Adjust degree by age: 0 (young) → +5 (minor 7 up), 1 (old) → 0 (root).
		var age_degree_bias: int = 0
		if age01 >= 0.0:
			age_degree_bias = clampi(int(round((1.0 - age01) * 4.0)), 0, 4)
		# Cause shifts: starvation → flat 2 (dim), hypoxia → flat 5.
		var cause_bias: int = 0
		if cause == "starvation":
			cause_bias = -1
		elif cause == "hypoxia":
			cause_bias = -2
		for i in 3:
			var deg: int = [base_idx + 4 + age_degree_bias + cause_bias,
				base_idx + 2 + age_degree_bias,
				base_idx + age_degree_bias][i]
			var note_idx: int = clampi(deg, 0, scale.size() - 1)
			var f: float = scale[note_idx] * oct_shift * float(tone[2])
			play_rhodes(f, 0.055, 0.75 + float(i) * 0.08)
		return
	# Fall through to the regular event handler.
	play_aquarium_event(event_name, intensity, species)


# Convenience: bias the shaker by a swim-speed sample. Sim driver calls this
# at low frequency (~once per second) with the current average creature speed.
func note_swim_activity(speed_0_1: float) -> void:
	# Map 0..1 to a "flow" boost so the shaker layer reacts immediately rather
	# than waiting for the smoothed env to catch up.
	var act: float = clampf(speed_0_1, 0.0, 1.0)
	_smooth["flow"] = clampf(maxf(float(_smooth.get("flow", 0.0)), act), 0.0, 1.0)
	# Occasional delicate pops when creatures dart — reads as stirred water.
	if act > 0.42 and _environment_enabled() and randf() < act * 0.09:
		play_bubble_sfx(clampf(act * 0.22, 0.08, 0.28))
	_swim_activity = lerpf(_swim_activity, act, 0.35)
