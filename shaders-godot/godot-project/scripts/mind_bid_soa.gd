extends RefCounted

# PERFORMANCE_UNTHROTTLED #18 — structure-of-arrays bid lane for packed competition.

var count: int = 0
var saliences: PackedFloat32Array = PackedFloat32Array()
var coal_masks: PackedInt32Array = PackedInt32Array()
var efe_flags: PackedByteArray = PackedByteArray()
var labels: PackedStringArray = PackedStringArray()
var _sources: Array = []


func load_from_bids(bids: Array) -> void:
	_sources = bids
	count = bids.size()
	saliences.resize(count)
	coal_masks.resize(count)
	efe_flags.resize(count)
	labels.resize(count)
	for i in count:
		var b: Dictionary = bids[i] as Dictionary
		saliences[i] = float(b.get("salience", 0.0))
		coal_masks[i] = int(b.get("coal_mask", 0))
		efe_flags[i] = 1 if bool(b.get("efe_sourced", false)) else 0
		labels[i] = str(b.get("label", ""))


func source_at(i: int) -> Dictionary:
	if i < 0 or i >= count:
		return {}
	return _sources[i] as Dictionary
