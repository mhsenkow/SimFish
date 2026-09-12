extends SceneTree

# Save schema versioning (BROAD_DIRECTIONS #4).
#
# The bug: STATE_VERSION was declared and never written or read, so saves
# carried no version and a newer-format save loaded silently into an older
# build. These assertions are the contract that keeps that closed.


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	# --- Stamping ---
	var d: Dictionary = {"sim": {"time_scale": 1.0}}
	TestSupport.check(failed, SaveMigrations.is_unstamped(d),
		"a bare dict must read as unstamped")
	SaveMigrations.stamp(d)
	TestSupport.check(failed, not SaveMigrations.is_unstamped(d),
		"stamp() must mark the dict")
	TestSupport.check(failed, d.has(SaveMigrations.VERSION_KEY),
		"stamp() must write the '%s' key" % SaveMigrations.VERSION_KEY)
	TestSupport.check(failed, int(d[SaveMigrations.VERSION_KEY]) == SaveMigrations.CURRENT_VERSION,
		"stamp() must write CURRENT_VERSION")
	TestSupport.check(failed, SaveMigrations.version_of(d) == SaveMigrations.CURRENT_VERSION,
		"version_of() must read back what stamp() wrote")
	# Stamping is idempotent — autosave runs it on every write.
	SaveMigrations.stamp(d)
	SaveMigrations.stamp(d)
	TestSupport.check(failed, int(d[SaveMigrations.VERSION_KEY]) == SaveMigrations.CURRENT_VERSION,
		"stamp() must be idempotent")
	# It must not disturb the rest of the save.
	TestSupport.check(failed, d.has("sim") and float(d["sim"]["time_scale"]) == 1.0,
		"stamp() must not touch unrelated keys")

	# --- TankSaves alias tracks the single source of truth ---
	var saves: Node = root.get_node_or_null("TankSaves")
	if saves != null:
		TestSupport.check(failed, int(saves.STATE_VERSION) == SaveMigrations.CURRENT_VERSION,
			"TankSaves.STATE_VERSION must equal SaveMigrations.CURRENT_VERSION")

	# --- Legacy unstamped saves still open ---
	# This is the shape every save on disk before #4 has. It MUST load: these
	# are real player tanks, and they are structurally version 1 already.
	var legacy: Dictionary = {"sim": {}, "fish": [], "plants": []}
	var lm: Dictionary = SaveMigrations.migrate(legacy)
	TestSupport.check(failed, bool(lm.get("ok", false)),
		"an unstamped legacy save must still load: %s" % String(lm.get("reason", "")))
	TestSupport.check(failed, int(lm.get("from", -1)) == SaveMigrations.UNSTAMPED_ASSUMED_VERSION,
		"unstamped saves must report the assumed version")
	TestSupport.check(failed, SaveMigrations.can_open(legacy),
		"can_open() must accept a legacy save")
	# And must not be mangled on the way through.
	var lmd: Dictionary = lm.get("dict", {})
	TestSupport.check(failed, lmd.has("fish") and lmd.has("plants"),
		"migration must preserve a legacy save's contents")

	# --- Current-version saves pass straight through ---
	var cur: Dictionary = SaveMigrations.stamp({"sim": {}})
	var cm: Dictionary = SaveMigrations.migrate(cur)
	TestSupport.check(failed, bool(cm.get("ok", false)), "a current-version save must load")
	TestSupport.check(failed, int(cm.get("from", -1)) == int(cm.get("to", -2)),
		"a current save must not report a version change")

	# --- A newer-format save is REFUSED, not half-loaded ---
	# This is the whole point: loading it would drop the newer build's fields
	# and the next autosave would write that loss back over the tank.
	var future: Dictionary = {"sim": {}, "fish": [{"id": "a"}]}
	future[SaveMigrations.VERSION_KEY] = SaveMigrations.CURRENT_VERSION + 1
	var fm: Dictionary = SaveMigrations.migrate(future)
	TestSupport.check(failed, not bool(fm.get("ok", true)),
		"a save from a newer build must be refused")
	TestSupport.check(failed, String(fm.get("refused", "")) == "future",
		"refusal code must be 'future', got '%s'" % String(fm.get("refused", "")))
	TestSupport.check(failed, not String(fm.get("reason", "")).is_empty(),
		"a refusal must carry a player-readable reason")
	TestSupport.check(failed, not SaveMigrations.can_open(future),
		"can_open() must reject a future save")
	# Refusing must leave the dict untouched — the caller may still back it up.
	TestSupport.check(failed, future.has("fish") and (future["fish"] as Array).size() == 1,
		"a refused save must not be mutated")
	# Far-future too, not just +1.
	var far: Dictionary = {"sim": {}}
	far[SaveMigrations.VERSION_KEY] = SaveMigrations.CURRENT_VERSION + 99
	TestSupport.check(failed, not SaveMigrations.can_open(far),
		"a far-future save must also be refused")

	# --- Garbage stamps are refused, and distinguishable from unstamped ---
	for junk in [{"v": "banana"}, {"v": []}, {"v": {}}, {"v": true}]:
		var bad: Dictionary = {"sim": {}}
		bad[SaveMigrations.VERSION_KEY] = junk["v"]
		TestSupport.check(failed, SaveMigrations.version_of(bad) == -1,
			"a nonsense stamp (%s) must report -1, not a version" % typeof(junk["v"]))
		var bm: Dictionary = SaveMigrations.migrate(bad)
		TestSupport.check(failed, not bool(bm.get("ok", true)),
			"a nonsense stamp must be refused")
		TestSupport.check(failed, String(bm.get("refused", "")) == "unknown_version",
			"a nonsense stamp must refuse as 'unknown_version'")

	# JSON round-trips ints as floats; an integral float stamp is valid.
	var floaty: Dictionary = {"sim": {}}
	floaty[SaveMigrations.VERSION_KEY] = float(SaveMigrations.CURRENT_VERSION)
	TestSupport.check(failed, SaveMigrations.version_of(floaty) == SaveMigrations.CURRENT_VERSION,
		"an integral float stamp must be accepted (JSON round-trip)")
	var fracty: Dictionary = {"sim": {}}
	fracty[SaveMigrations.VERSION_KEY] = 1.5
	TestSupport.check(failed, SaveMigrations.version_of(fracty) == -1,
		"a fractional stamp is nonsense and must report -1")
	# A numeric string is what a hand-edited save looks like.
	var stringy: Dictionary = {"sim": {}}
	stringy[SaveMigrations.VERSION_KEY] = str(SaveMigrations.CURRENT_VERSION)
	TestSupport.check(failed, SaveMigrations.version_of(stringy) == SaveMigrations.CURRENT_VERSION,
		"a numeric string stamp must be accepted")

	# --- The stamp survives the real serialisation path ---
	# SaveHelpers.sanitize_for_json runs between stamp() and the disk write,
	# so prove the key is not dropped by it or by a JSON round-trip.
	var payload: Variant = SaveHelpers.sanitize_for_json(
		SaveMigrations.stamp({"sim": {"time_scale": 2.0}}))
	var text: String = JSON.stringify(payload)
	var parsed: Variant = JSON.parse_string(text)
	TestSupport.check(failed, parsed is Dictionary, "save payload must round-trip as a Dictionary")
	if parsed is Dictionary:
		TestSupport.check(failed, SaveMigrations.version_of(parsed) == SaveMigrations.CURRENT_VERSION,
			"the stamp must survive sanitize_for_json + JSON round-trip")

	# --- Migration table integrity (guards future steps) ---
	# Every registered step must advance, and there must be a path from every
	# version we claim to support up to current.
	for v in range(SaveMigrations.UNSTAMPED_ASSUMED_VERSION,
			SaveMigrations.CURRENT_VERSION + 1):
		var probe: Dictionary = {"sim": {}}
		probe[SaveMigrations.VERSION_KEY] = v
		var pm: Dictionary = SaveMigrations.migrate(probe)
		TestSupport.check(failed, bool(pm.get("ok", false)),
			"no migration path from supported version %d: %s"
				% [v, String(pm.get("reason", ""))])
		TestSupport.check(failed, int(pm.get("to", -1)) == SaveMigrations.CURRENT_VERSION,
			"version %d must migrate all the way to current" % v)

	quit(TestSupport.report("smoke_save_versioning", failed))
