class_name MindCompetition
extends RefCounted

# Shared workspace competition (#13/#18) — no fish/sim deps (breaks kernel↔workspace cycle).

const CAPACITY: int = 3
const IGNITION_THRESHOLD: float = 0.42
const COALITION_BONUS: float = 0.12
const COMP_TOP_K: int = CAPACITY * 2


static func insert_top_bid(top: Array, b: Dictionary) -> void:
	var s: float = float(b.get("salience", 0.0))
	var pos: int = top.size()
	for i in top.size():
		if s > float(top[i].get("salience", 0.0)):
			pos = i
			break
	if top.size() < COMP_TOP_K:
		top.insert(pos, b)
	elif pos < COMP_TOP_K:
		top.insert(pos, b)
		top.resize(COMP_TOP_K)


static func coalitions_overlap(mask_a: int, mask_b: int, coal_a: Array, coal_b: Array) -> bool:
	if mask_a != 0 and mask_b != 0:
		return (mask_a & mask_b) != 0
	for c in coal_a:
		if coal_b.has(c):
			return true
	return false


static func from_sorted(sorted: Array) -> Dictionary:
	var winners: Array = []
	var top_s: float = 0.0
	for b in sorted:
		var s: float = float(b.get("salience", 0.0))
		if winners.is_empty():
			winners.append(b)
			top_s = s
		elif winners.size() < CAPACITY and s >= IGNITION_THRESHOLD * 0.65:
			var coal: Array = b.get("coalition", [])
			var coal_mask: int = int(b.get("coal_mask", 0))
			var merged: bool = false
			for w in winners:
				var wc: Array = w.get("coalition", [])
				var w_mask: int = int(w.get("coal_mask", 0))
				if coalitions_overlap(coal_mask, w_mask, coal, wc):
					w["salience"] = float(w.get("salience", 0.0)) + s * COALITION_BONUS
					merged = true
					break
			if not merged:
				winners.append(b)
		if winners.size() >= CAPACITY:
			break
	var ignited: bool = top_s >= IGNITION_THRESHOLD
	return {"contents": winners, "ignited": ignited, "top_salience": top_s}


static func run(bids: Array) -> Dictionary:
	var sorted: Array = []
	for b in bids:
		if b is Dictionary:
			insert_top_bid(sorted, b as Dictionary)
	return from_sorted(sorted)
