class_name MindBidPool
extends RefCounted

# PERFORMANCE_UNTHROTTLED #15 — reusable bid slots (no per-collect dict alloc).

const POOL_SIZE: int = 32


static func ensure(f) -> void:
	if f == null:
		return
	if f.get("_bid_pool") is Array and (f._bid_pool as Array).size() >= POOL_SIZE:
		return
	var pool: Array = []
	for _i in POOL_SIZE:
		pool.append({
			"label": "",
			"salience": 0.0,
			"coalition": [],
			"coal_mask": 0,
			"efe_sourced": false,
		})
	f._bid_pool = pool
	f._bid_pool_i = 0


static func take(f, label: String, salience: float, coalition: Array, coal_mask: int,
		efe_sourced: bool = false) -> Dictionary:
	ensure(f)
	var pool: Array = f._bid_pool as Array
	var i: int = int(f._bid_pool_i if f.get("_bid_pool_i") != null else 0) % pool.size()
	f._bid_pool_i = (i + 1) % pool.size()
	var b: Dictionary = pool[i] as Dictionary
	b["label"] = label
	b["salience"] = salience
	b["coalition"] = coalition
	b["coal_mask"] = coal_mask
	b["efe_sourced"] = efe_sourced
	return b
