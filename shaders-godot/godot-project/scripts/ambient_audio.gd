# Generative ambient audio.
#
# Uses AudioStreamGenerator (Godot's procedural-sample stream) to emit short
# sine-wave plinks on a small pentatonic scale. Triggered sparsely by world
# events (plant new-leaf, fish dart, bubble pop) so a healthy mature tank
# sounds calmer + more melodic; a fresh/chaotic tank sounds sparser + dissonant.
#
# Attach to a Node child of Main; call play_event_plink() from anywhere.

extends Node


const SAMPLE_RATE: int = 44100
const PENTATONIC_HZ: Array[float] = [
	261.63, 293.66, 329.63, 392.00, 440.00,  # C4, D4, E4, G4, A4
	523.25, 587.33, 659.25, 783.99, 880.00,  # one octave up
]

var _stream_player: AudioStreamPlayer = null
var _playback: AudioStreamGeneratorPlayback = null
var _pending: Array = []  # queue of (freq_hz, duration_s, amplitude) to play


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = SAMPLE_RATE
	gen.buffer_length = 0.2
	_stream_player = AudioStreamPlayer.new()
	_stream_player.stream = gen
	_stream_player.volume_db = -8.0
	add_child(_stream_player)
	_stream_player.play()
	_playback = _stream_player.get_stream_playback() as AudioStreamGeneratorPlayback


func play_event_plink(intensity: float = 0.5) -> void:
	# Pick a pitch on the pentatonic scale; gentle events play lower notes,
	# excited events play higher. Amplitude scales with intensity but stays
	# small so the soundscape never gets loud.
	var note_idx: int = clampi(int(intensity * float(PENTATONIC_HZ.size())),
		0, PENTATONIC_HZ.size() - 1)
	var freq: float = PENTATONIC_HZ[note_idx] * (0.95 + randf() * 0.10)
	var dur: float = 0.35 + randf() * 0.2
	var amp: float = 0.06 + intensity * 0.10
	_pending.append([freq, dur, amp])


func _process(_dt: float) -> void:
	if _playback == null:
		return
	# Service the audio buffer: synthesize as many samples as the generator
	# is willing to accept this frame. We mix all pending plinks together.
	var frames_available: int = _playback.get_frames_available()
	if frames_available <= 0:
		return
	for i in frames_available:
		var v: float = 0.0
		# Each pending note: advance its phase, add its contribution, decrement
		# its remaining duration. Drop when expired.
		for j in range(_pending.size() - 1, -1, -1):
			var note = _pending[j]
			var freq: float = note[0]
			var dur: float = note[1]
			var amp: float = note[2]
			if dur <= 0.0:
				_pending.remove_at(j)
				continue
			# Phase index stored as a 4th array element on first use.
			if note.size() < 4:
				note.append(0.0)
				_pending[j] = note
			var phase: float = note[3]
			# Simple decay envelope: amplitude tapers as dur counts down.
			var env: float = clampf(dur * 2.5, 0.0, 1.0)
			v += sin(phase * TAU) * amp * env
			note[3] = fposmod(phase + freq / float(SAMPLE_RATE), 1.0)
			note[1] = dur - 1.0 / float(SAMPLE_RATE)
			_pending[j] = note
		v = clampf(v, -1.0, 1.0)
		_playback.push_frame(Vector2(v, v))
