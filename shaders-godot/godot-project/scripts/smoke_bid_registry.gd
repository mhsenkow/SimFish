extends SceneTree

# META #12 — bid-generator registry (plugin attention). A new drive registers a
# Callable(f, sim) -> Array[bid] instead of editing the kernel. Verifies a plugin
# bid reaches the workspace additively (built-ins unchanged), registration is
# idempotent, a malformed generator is skipped without crashing the cycle, and
# unregister removes it.

const GlobalWorkspace = preload("res://scripts/global_workspace.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	GlobalWorkspace.clear_bid_generators()

	var f: Fish = Fish.new()
	root.add_child(f)
	f.id = "plug"
	f.hunger = 0.8   # a built-in food bid is present

	_assert(failed, not _has(GlobalWorkspace.collect_bids(f, null), "play_drive"),
			"no plugin bid before registration")
	_assert(failed, _has(GlobalWorkspace.collect_bids(f, null), "food"),
			"built-in food bid present")

	# Register a plugin drive.
	var gen: Callable = func(_fish, _sim): return [{"label": "play_drive", "salience": 0.6, "coalition": ["play"]}]
	GlobalWorkspace.register_bid_generator(gen)
	var bids: Array = GlobalWorkspace.collect_bids(f, null)
	_assert(failed, _has(bids, "play_drive"), "registered plugin bid appears in the workspace")
	_assert(failed, _has(bids, "food"), "built-in bids unchanged (additive)")

	# Idempotent: registering the same generator twice doesn't duplicate.
	GlobalWorkspace.register_bid_generator(gen)
	var n: int = 0
	for b in GlobalWorkspace.collect_bids(f, null):
		if str(b.get("label", "")) == "play_drive":
			n += 1
	_assert(failed, n == 1, "double registration doesn't duplicate the bid")

	# A malformed generator (non-Array return) is skipped, cycle survives.
	var bad: Callable = func(_fish, _sim): return 42
	GlobalWorkspace.register_bid_generator(bad)
	_assert(failed, _has(GlobalWorkspace.collect_bids(f, null), "play_drive"),
			"a malformed generator is skipped and the cycle still runs")

	# Unregister.
	GlobalWorkspace.unregister_bid_generator(gen)
	GlobalWorkspace.unregister_bid_generator(bad)
	_assert(failed, not _has(GlobalWorkspace.collect_bids(f, null), "play_drive"),
			"unregistered plugin bid is gone")

	GlobalWorkspace.clear_bid_generators()

	if failed.is_empty():
		print("[smoke] bid_registry OK")
		quit(0)
	else:
		for m in failed:
			push_error("[smoke] " + m)
		quit(1)


func _has(bids: Array, label: String) -> bool:
	for b in bids:
		if str(b.get("label", "")) == label:
			return true
	return false


func _assert(failed: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		failed.append(msg)
