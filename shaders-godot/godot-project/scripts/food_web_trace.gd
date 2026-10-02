extends RefCounted
class_name FoodWebTrace

# Holistic #121 — diagnostic event chain for one meal through the food web.
# Stages name transfers; documented_loss records heat/evaporation explicitly.
# Callers must not double-book nutrient value across produced/consumed/lost.

const STAGE_SPAWN := "spawn"
const STAGE_CONSUME := "consume"
const STAGE_ABSORB := "absorb"
const STAGE_METABOLIC_WASTE := "metabolic_waste"
const STAGE_SETTLE_DEPOSIT := "settle_deposit"
const STAGE_PLANT_UPTAKE := "plant_uptake"
const STAGE_DOCUMENTED_LOSS := "documented_loss"

const MAX_EVENTS: int = 64
const MAX_CHAINS: int = 24

var _next_id: int = 1
var events: Array[Dictionary] = []
var _chain_totals: Dictionary = {}  # id -> {spawned, absorbed, deposited, uptake, lost}


func begin_chain(source: String, amount: float, subtype: int = -1) -> int:
	var id: int = _next_id
	_next_id += 1
	_chain_totals[id] = {
		"spawned": 0.0,
		"absorbed": 0.0,
		"deposited": 0.0,
		"uptake": 0.0,
		"lost": 0.0,
		"source": source,
		"subtype": subtype,
	}
	_prune_chains()
	record(id, STAGE_SPAWN, amount, source)
	return id


func record(chain_id: int, stage: String, amount: float, note: String = "") -> void:
	if chain_id <= 0 or amount < 0.0:
		return
	var row := {
		"chain": chain_id,
		"stage": stage,
		"amount": amount,
		"note": note,
		"t": Time.get_ticks_msec(),
	}
	events.append(row)
	while events.size() > MAX_EVENTS:
		events.pop_front()
	var totals: Dictionary = _chain_totals.get(chain_id, {}) as Dictionary
	if totals.is_empty():
		totals = {
			"spawned": 0.0, "absorbed": 0.0, "deposited": 0.0,
			"uptake": 0.0, "lost": 0.0, "source": "", "subtype": -1,
		}
		_chain_totals[chain_id] = totals
	match stage:
		STAGE_SPAWN:
			totals["spawned"] = float(totals.get("spawned", 0.0)) + amount
		STAGE_ABSORB:
			totals["absorbed"] = float(totals.get("absorbed", 0.0)) + amount
		STAGE_SETTLE_DEPOSIT:
			totals["deposited"] = float(totals.get("deposited", 0.0)) + amount
		STAGE_PLANT_UPTAKE:
			totals["uptake"] = float(totals.get("uptake", 0.0)) + amount
		STAGE_DOCUMENTED_LOSS:
			totals["lost"] = float(totals.get("lost", 0.0)) + amount
		STAGE_METABOLIC_WASTE, STAGE_CONSUME:
			pass


func chain_summary(chain_id: int) -> Dictionary:
	return (_chain_totals.get(chain_id, {}) as Dictionary).duplicate(true)


func recent_events(limit: int = 16) -> Array:
	var n: int = mini(limit, events.size())
	return events.slice(events.size() - n, events.size())


# Conservation check: spawned ≈ absorbed + deposited + lost + open waste.
# Plant uptake draws from the deposited pool, so it is not added again.
static func conservation_gap(totals: Dictionary, open_waste: float = 0.0) -> float:
	var spawned: float = float(totals.get("spawned", 0.0))
	var accounted: float = float(totals.get("absorbed", 0.0)) \
		+ float(totals.get("deposited", 0.0)) \
		+ float(totals.get("lost", 0.0)) \
		+ maxf(0.0, open_waste)
	return spawned - accounted


func _prune_chains() -> void:
	if _chain_totals.size() <= MAX_CHAINS:
		return
	var keys: Array = _chain_totals.keys()
	keys.sort()
	var drop: int = keys.size() - MAX_CHAINS
	for i in drop:
		_chain_totals.erase(keys[i])
