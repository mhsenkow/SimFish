extends SceneTree

# 1D / META #5 — inter-fish signalling. Verifies emission from state, reception
# within radius (and the range cutoff), the heard signal becoming a workspace bid,
# learned reliability (trust grows/shrinks with reinforcement and moves the bid
# salience), and integration into collect_bids.

const GlobalWorkspace = preload("res://scripts/global_workspace.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	# --- Emission from state.
	var a: Fish = _mk("alarm-src")
	a.position = Vector3(0, 2, 0)
	a.spooked = 0.8
	FishSignals.tick(a, 0.1)
	_assert(failed, FishSignals.active_signal(a) == FishSignals.ALARM, "spooked fish emits ALARM")

	var mfish: Fish = _mk("mate-src")
	mfish.partner = _mk("partner")
	FishSignals.tick(mfish, 0.1)
	_assert(failed, FishSignals.active_signal(mfish) == FishSignals.MATE, "paired fish emits MATE")

	# --- Reception within radius → heard + a threat bid.
	var b: Fish = _mk("listener")
	b.position = Vector3(3, 2, 0)   # 3u from a, inside the 8u radius
	FishSignals.scan(b, [a])
	_assert(failed, str(FishSignals._state(b).get("heard", "")) == FishSignals.ALARM,
			"a near fish hears the alarm")
	var bid: Dictionary = FishSignals.collect_signal_bid(b)
	_assert(failed, str(bid.get("label", "")) == "threat" and float(bid.get("salience", 0.0)) > 0.0,
			"a heard alarm becomes a threat bid")

	# --- Range cutoff.
	var far: Fish = _mk("far")
	far.position = Vector3(50, 2, 0)
	FishSignals.scan(far, [a])
	_assert(failed, str(FishSignals._state(far).get("heard", "")) == "",
			"a fish beyond the radius hears nothing")

	# --- Learning: trust grows with reliable signals and lifts the bid salience.
	var sal0: float = float(FishSignals.collect_signal_bid(b).get("salience", 0.0))
	for _i in 30:
		FishSignals.reinforce(b, FishSignals.ALARM, true)
	_assert(failed, FishSignals.interpret(b, FishSignals.ALARM) > 1.0,
			"repeated reliable alarms raise learned trust")
	FishSignals.scan(b, [a])   # refresh heard with the new trust
	var sal1: float = float(FishSignals.collect_signal_bid(b).get("salience", 0.0))
	_assert(failed, sal1 > sal0, "learned trust raises the heard-alarm bid salience")

	# --- Distrust pulls a signal's weight down.
	for _j in 60:
		FishSignals.reinforce(b, FishSignals.FOOD, false)
	_assert(failed, FishSignals.interpret(b, FishSignals.FOOD) < 0.5,
			"discounted signals lose trust")

	# --- Integration: a heard alarm shows up in collect_bids (intersubjectivity).
	FishSignals.scan(b, [a])
	_assert(failed, _has_bid(GlobalWorkspace.collect_bids(b, null), "threat"),
			"heard alarm enters the Global Workspace via collect_bids")

	if failed.is_empty():
		print("[smoke] fish_signals OK")
		quit(0)
	else:
		for msg in failed:
			push_error("[smoke] " + msg)
		quit(1)


func _mk(id: String) -> Fish:
	var f: Fish = Fish.new()
	root.add_child(f)
	f.id = id
	return f


func _has_bid(bids: Array, label: String) -> bool:
	for bd in bids:
		if str(bd.get("label", "")) == label:
			return true
	return false


func _assert(failed: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		failed.append(msg)
