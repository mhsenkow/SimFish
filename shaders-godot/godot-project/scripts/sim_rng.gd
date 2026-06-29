class_name SimRng
extends RefCounted

# META_ENGINEERING #31 — authoritative seeded RNG with named streams.
# Same master seed + stream name → same sequence, independent of call order
# in other streams.

const STREAM_DEFAULT := "default"
const STREAM_GENETICS := "genetics"
const STREAM_BEHAVIOR := "behavior"
const STREAM_EVENTS := "events"
const STREAM_SPAWN := "spawn"
const STREAM_COGNITION := "cognition"

var _master_seed: int = 0
var _streams: Dictionary = {}


static func stream_seed(master: int, stream_name: String) -> int:
	var h: int = master & 0x7fffffff
	for i in stream_name.length():
		h = ((h * 31) + stream_name.unicode_at(i)) & 0x7fffffff
	return h if h != 0 else 1


static func entity_stream_name(base: String, entity_id: String) -> String:
	if entity_id.strip_edges() == "":
		return base
	return "%s:%s" % [base, entity_id]


func reset(seed_value: int) -> void:
	_master_seed = seed_value
	_streams.clear()


func master_seed() -> int:
	return _master_seed


func stream(name: String) -> RandomNumberGenerator:
	var key: String = name if name != "" else STREAM_DEFAULT
	if not _streams.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = stream_seed(_master_seed, key)
		_streams[key] = rng
	return _streams[key] as RandomNumberGenerator


func randf(stream_name: String = STREAM_DEFAULT) -> float:
	return stream(stream_name).randf()


func randf_range(from: float, to: float, stream_name: String = STREAM_DEFAULT) -> float:
	return stream(stream_name).randf_range(from, to)


func randi(stream_name: String = STREAM_DEFAULT) -> int:
	return stream(stream_name).randi()


func randi_range(from: int, to: int, stream_name: String = STREAM_DEFAULT) -> int:
	return stream(stream_name).randi_range(from, to)
