class_name PotatoAmbientBed
extends RefCounted

# PERFORMANCE_UNTHROTTLED #91 — pre-rendered seamless ambient bed for potato tier.
# Must match AmbientAudio.SAMPLE_RATE (22050). Synthesizing at 44.1 kHz time while
# playing at 22.05 kHz ran the bed an octave down (SENTIENCE_THE_LOOM #9).

const SAMPLE_RATE: int = 22050
const LOOP_SAMPLES: int = 22050  # 1.0 s @ SAMPLE_RATE

static var _loop_l: PackedFloat32Array = PackedFloat32Array()
static var _loop_r: PackedFloat32Array = PackedFloat32Array()
static var _pos: int = 0


static func reset_for_test() -> void:
	_loop_l = PackedFloat32Array()
	_loop_r = PackedFloat32Array()
	_pos = 0


static func ensure_built() -> void:
	if _loop_l.size() == LOOP_SAMPLES:
		return
	_loop_l.resize(LOOP_SAMPLES)
	_loop_r.resize(LOOP_SAMPLES)
	for i in LOOP_SAMPLES:
		var t: float = float(i) / float(SAMPLE_RATE)
		var l: float = sin(t * 62.0 * TAU) * 0.012 + sin(t * 31.0 * TAU) * 0.008
		var r: float = sin(t * 58.0 * TAU + 0.4) * 0.012 + sin(t * 33.0 * TAU) * 0.007
		_loop_l[i] = l
		_loop_r[i] = r


static func next_stereo() -> Vector2:
	ensure_built()
	var v := Vector2(_loop_l[_pos], _loop_r[_pos])
	_pos = (_pos + 1) % LOOP_SAMPLES
	return v
