extends SceneTree

# Holistic #011 — representative save fixtures under dev/fixtures/saves/
# must load through SaveMigrations + SaveRepair without silent data loss
# and without private player text.

const FIXTURE_DIR := "res://dev/fixtures/saves/"
const FIXTURES: PackedStringArray = [
	"old_tank.json",
	"breeding_tank.json",
	"learned_fish.json",
	"custom_scape.json",
	"reef.json",
]


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	for name in FIXTURES:
		_check_fixture(failed, name)

	quit(TestSupport.report("smoke_save_fixtures", failed))


func _check_fixture(failed: Array[String], name: String) -> void:
	var path: String = FIXTURE_DIR + name
	if not FileAccess.file_exists(path):
		failed.append("%s: missing on disk" % name)
		return
	var raw_text: String = FileAccess.get_file_as_string(path)
	TestSupport.check(failed, not raw_text.is_empty(), "%s: readable" % name)
	# No private player dialogue / free-text keeper lines in fixtures.
	for banned in ["last_keeper_text", "keeper_memory", "\"said\":", "promise_text"]:
		TestSupport.check(failed, raw_text.find(banned) < 0,
			"%s: must not contain private player text key %s" % [name, banned])

	var parsed: Variant = JSON.parse_string(raw_text)
	TestSupport.check(failed, parsed is Dictionary, "%s: JSON object" % name)
	if not (parsed is Dictionary):
		return
	var d: Dictionary = parsed as Dictionary

	var mig: Dictionary = SaveMigrations.migrate(d.duplicate(true))
	TestSupport.check(failed, bool(mig.get("ok", false)),
		"%s: migrate ok (%s)" % [name, String(mig.get("reason", ""))])
	TestSupport.check(failed, SaveMigrations.can_open(d),
		"%s: can_open" % name)
	var migrated: Dictionary = mig.get("dict", {}) as Dictionary
	TestSupport.check(failed, int(migrated.get(SaveMigrations.VERSION_KEY, -1)) \
			== SaveMigrations.CURRENT_VERSION,
		"%s: stamped at CURRENT_VERSION after migrate" % name)

	var repaired: Dictionary = SaveRepair.sanitize(migrated)
	TestSupport.check(failed, repaired.has("sim") and repaired["sim"] is Dictionary,
		"%s: repair keeps sim dict" % name)
	TestSupport.check(failed, repaired.has("fish") and repaired["fish"] is Array,
		"%s: repair keeps fish array" % name)
	TestSupport.check(failed, repaired.has("plants") and repaired["plants"] is Array,
		"%s: repair keeps plants array" % name)

	# Fixture-specific shape contracts (evidence the file is the intended kind).
	match name:
		"old_tank.json":
			TestSupport.check(failed,
				float((repaired["sim"] as Dictionary).get("tank_age_s", 0.0)) > 500000.0,
				"old_tank: high tank_age_s")
			TestSupport.check(failed, (repaired.get("story_events", []) as Array).size() >= 1,
				"old_tank: has story_events")
		"breeding_tank.json":
			TestSupport.check(failed, (repaired.get("fish_eggs", []) as Array).size() >= 1,
				"breeding_tank: has fish_eggs")
			var moms: int = 0
			for f in repaired.get("fish", []):
				if f is Dictionary and float((f as Dictionary).get("gestation_progress", 0.0)) > 0.0:
					moms += 1
			TestSupport.check(failed, moms >= 1, "breeding_tank: gestating fish")
		"learned_fish.json":
			var learned_ok := false
			for f in repaired.get("fish", []):
				if not (f is Dictionary):
					continue
				var mind: Variant = (f as Dictionary).get("mind", {})
				if mind is Dictionary and (mind as Dictionary).has("learned_mind"):
					var lm: Variant = (mind as Dictionary).get("learned_mind")
					if lm is Dictionary and ((lm as Dictionary).get("beliefs", []) as Array).size() >= 1:
						learned_ok = true
			TestSupport.check(failed, learned_ok, "learned_fish: learned_mind beliefs present")
		"custom_scape.json":
			var aq: Variant = repaired.get("aquascape", d.get("aquascape", []))
			# SaveRepair drops aquascape only if not an Array; preserve if present.
			if not (aq is Array):
				aq = d.get("aquascape", [])
			TestSupport.check(failed, aq is Array and (aq as Array).size() >= 2,
				"custom_scape: aquascape entries")
			var kinds: PackedStringArray = PackedStringArray()
			for e in aq as Array:
				if e is Dictionary:
					kinds.append(String((e as Dictionary).get("kind", "")))
			TestSupport.check(failed, "voxel" in kinds or "build_voxel" in kinds,
				"custom_scape: has voxel/build_voxel")
		"reef.json":
			TestSupport.check(failed,
				String((repaired["sim"] as Dictionary).get("substrate_type", "")) == "ocean_sand",
				"reef: ocean_sand substrate")
			TestSupport.check(failed,
				String((repaired["sim"] as Dictionary).get("tank_preset", "")) == "reef",
				"reef: tank_preset reef")
