class_name MindCacheStats
extends RefCounted

# REFINEMENT_II #17 — cache hit/miss counters for the perf HUD.

static var competition_hits: int = 0
static var competition_misses: int = 0
static var broadcast_skips: int = 0
static var broadcast_sends: int = 0
static var retrieval_hits: int = 0
static var retrieval_misses: int = 0


static func reset_for_test() -> void:
	competition_hits = 0
	competition_misses = 0
	broadcast_skips = 0
	broadcast_sends = 0
	retrieval_hits = 0
	retrieval_misses = 0


static func snapshot() -> Dictionary:
	return {
		"competition_hits": competition_hits,
		"competition_misses": competition_misses,
		"broadcast_skips": broadcast_skips,
		"broadcast_sends": broadcast_sends,
		"retrieval_hits": retrieval_hits,
		"retrieval_misses": retrieval_misses,
	}


static func hud_suffix() -> String:
	var parts: PackedStringArray = PackedStringArray()
	var ch: int = competition_hits
	var cm: int = competition_misses
	if ch + cm > 0:
		parts.append("ws %d/%d" % [ch, ch + cm])
	var rh: int = retrieval_hits
	var rm: int = retrieval_misses
	if rh + rm > 0:
		parts.append("ep %d/%d" % [rh, rh + rm])
	if broadcast_skips + broadcast_sends > 0:
		parts.append("bc %d skip" % broadcast_skips)
	if parts.is_empty():
		return ""
	return " · " + ", ".join(parts)
