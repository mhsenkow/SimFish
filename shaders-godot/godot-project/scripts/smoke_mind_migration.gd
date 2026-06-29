extends SceneTree

# META #17 — MindState schema migration ladder. Verifies an old save walks up to
# the current version with new fields explicitly defaulted, a current save is
# untouched, a newer save is never downgraded, and MindState.from_dict applies it.

const MindMigration = preload("res://scripts/mind_migration.gd")
const MindStateScript = preload("res://scripts/mind_state.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	var cur: int = MindStateScript.SCHEMA_VERSION

	# A v2 save (pre-extended-fields) upgrades to current, defaulting new fields.
	var old := {"schema_version": 2, "mood": 0.3, "attention_focus": "food"}
	var up: Dictionary = MindMigration.migrate(old, cur)
	_assert(failed, int(up.get("schema_version", -1)) == cur, "v2 save migrates to current (%d)" % cur)
	_assert(failed, up.has("world_model") and up.has("life_stance") and up.has("prediction_error"),
			"migration defaults the v4 extended-channel fields")
	_assert(failed, is_equal_approx(float(up.get("mood", 0.0)), 0.3) and str(up.get("attention_focus", "")) == "food",
			"migration preserves existing values")

	# A current save is a no-op.
	var cur_save := {"schema_version": cur, "mood": -0.1}
	var same: Dictionary = MindMigration.migrate(cur_save, cur)
	_assert(failed, int(same.get("schema_version", -1)) == cur, "current save stays current")

	# A newer save is never downgraded.
	var future := {"schema_version": cur + 3, "mood": 0.5}
	var fwd: Dictionary = MindMigration.migrate(future, cur)
	_assert(failed, int(fwd.get("schema_version", -1)) == cur + 3, "a newer save is not downgraded")

	# from_dict applies the ladder end-to-end.
	var ms = MindStateScript.new()
	ms.from_dict({"schema_version": 2, "mood": 0.42, "stress": 0.2})
	_assert(failed, ms.schema_version == cur, "from_dict upgrades schema_version")
	_assert(failed, is_equal_approx(ms.mood, 0.42), "from_dict keeps migrated values")

	if failed.is_empty():
		print("[smoke] mind_migration OK")
		quit(0)
	else:
		for m in failed:
			push_error("[smoke] " + m)
		quit(1)


func _assert(failed: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		failed.append(msg)
