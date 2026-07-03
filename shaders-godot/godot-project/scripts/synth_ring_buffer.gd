class_name SynthRingBuffer
extends RefCounted

# PERFORMANCE_UNTHROTTLED #89 — lock-free-ish stereo sample ring between synth worker and main.

const CAP: int = 8192

static var _l: PackedFloat32Array = PackedFloat32Array()
static var _r: PackedFloat32Array = PackedFloat32Array()
static var _head: int = 0
static var _tail: int = 0


static func reset_for_test() -> void:
	_l = PackedFloat32Array()
	_r = PackedFloat32Array()
	_l.resize(CAP)
	_r.resize(CAP)
	_l.fill(0.0)
	_r.fill(0.0)
	_head = 0
	_tail = 0


static func _ensure() -> void:
	if _l.is_empty():
		reset_for_test()


static func push_stereo(left: PackedFloat32Array, right: PackedFloat32Array) -> void:
	_ensure()
	var n: int = mini(left.size(), right.size())
	for i in n:
		_l[_head] = left[i]
		_r[_head] = right[i]
		_head = (_head + 1) % CAP
		if _head == _tail:
			_tail = (_tail + 1) % CAP


static func pop_into(playback_l: AudioStreamGeneratorPlayback, _playback_r: AudioStreamGeneratorPlayback,
		max_frames: int) -> int:
	_ensure()
	var written: int = 0
	while written < max_frames and _tail != _head:
		if playback_l != null:
			playback_l.push_frame(Vector2(_l[_tail], _r[_tail]))
		written += 1
		_tail = (_tail + 1) % CAP
	return written


static func filled() -> int:
	_ensure()
	if _head >= _tail:
		return _head - _tail
	return CAP - _tail + _head
