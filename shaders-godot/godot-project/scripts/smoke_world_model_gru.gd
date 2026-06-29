extends SceneTree

# 1B / META #3 — GRU-lite (MGU) recurrent world model. Verifies: deterministic
# under a fixed id + input sequence (replay-safe), stable (error/variance/gru_error
# stay bounded over 100 ticks), the hidden state actually evolves (recurrence is
# live), save round-trip preserves it, and old saves migrate cleanly.

const MindWorldModel = preload("res://scripts/mind_world_model.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	# Determinism + stability: two same-id fish fed an identical varying input
	# sequence must track identically, and the signals must stay bounded.
	var a: Fish = _mk("det")
	var b: Fish = _mk("det")
	for i in 100:
		var hv: float = 0.5 + 0.3 * sin(i * 0.3)
		var sv: float = 0.4 + 0.2 * cos(i * 0.21)
		for fsh in [a, b]:
			fsh.hunger = hv
			fsh.stress = sv
			fsh.curiosity_drive = 0.6
			MindWorldModel.tick(fsh, null, 0.1)
		var m: Dictionary = a._world_model
		var e: float = float(m["error"])
		var v: float = float(m["variance"])
		var g: float = float(m["gru_error"])
		if not (is_finite(e) and is_finite(v) and is_finite(g)) \
				or e < 0.0 or e > 1.5 or v < 0.05 or v > 1.0 or g < 0.0 or g > 1.0:
			failed.append("signals out of bounds at tick %d (e=%.3f v=%.3f g=%.3f)" % [i, e, v, g])
			break

	_assert(failed, is_equal_approx(float(a._world_model["gru_error"]), float(b._world_model["gru_error"])),
			"same-id GRU is deterministic across 100 ticks")

	var hsum: float = 0.0
	for x in (a._world_model["h"] as PackedFloat32Array):
		hsum += absf(x)
	_assert(failed, hsum > 0.01, "GRU hidden state evolves (recurrence is live, not stuck at 0)")

	# Save round-trip: restore a's model into a fresh fish; identical inputs after
	# restore must keep identical trajectories (hidden + gru_pred preserved).
	var snap: Dictionary = MindWorldModel.to_dict(a)
	var c: Fish = _mk("det")
	MindWorldModel.from_dict(c, snap)
	for _i in 10:
		for fsh in [a, c]:
			fsh.hunger = 0.55
			fsh.stress = 0.3
			fsh.curiosity_drive = 0.6
			MindWorldModel.tick(fsh, null, 0.1)
	_assert(failed, is_equal_approx(float(a._world_model["gru_error"]), float(c._world_model["gru_error"])),
			"save round-trip preserves the GRU (identical trajectory after restore)")

	# Migration: a legacy save (linear dict, no GRU) backfills the GRU fields.
	var legacy := {"weights": [], "predicted": [0.0, 0.0, 0.0], "error": 0.0, "variance": 0.35, "updates": 5}
	var d: Fish = _mk("legacy")
	MindWorldModel.from_dict(d, legacy)
	_assert(failed, d._world_model.has("h") and d._world_model.has("gw"),
			"legacy save backfills GRU fields (migration)")
	MindWorldModel.tick(d, null, 0.1)   # must not crash on a migrated model
	_assert(failed, is_finite(float(d._world_model["gru_error"])), "migrated model ticks cleanly")

	if failed.is_empty():
		print("[smoke] world_model_gru OK")
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


func _assert(failed: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		failed.append(msg)
