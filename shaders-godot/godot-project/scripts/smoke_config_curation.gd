extends SceneTree

# Config curation gate (BROAD_DIRECTIONS #18).
#
# The manifest is only worth having if it cannot rot. TankConfig reached 284
# properties precisely because nothing forced a decision when a knob was
# added, so the load-bearing assertion here is COMPLETENESS: every property
# on TankConfig must be classified, or this goes red.
#
# If you add a knob and this fails, that is the feature. Add it to
# ConfigCuration.MANIFEST with a tier and a domain.


func _initialize() -> void:
	var t := TestSupport.Suite.new("smoke_config_curation")

	# TankConfig's real property list, read from source: it is an autoload,
	# and a --script run does not mount autoloads.
	var src: String = FileAccess.get_file_as_string("res://scripts/tank_config.gd")
	if not t.check(not src.is_empty(), "tank_config.gd source readable"):
		quit(t.finish())
		return

	var declared: Array[String] = []
	for line in src.split("\n"):
		if not line.begins_with("var "):
			continue
		var rest: String = line.substr(4)
		var name: String = ""
		for i in rest.length():
			var c: String = rest[i]
			if c == ":" or c == " " or c == "=":
				break
			name += c
		if not name.is_empty():
			declared.append(name)

	t.check(declared.size() > 200,
		"sanity: expected TankConfig to declare 200+ properties, found %d"
			% declared.size())

	# --- COMPLETENESS: every property is classified ---
	var unclassified: Array[String] = []
	for prop in declared:
		if not ConfigCuration.is_curated(prop):
			unclassified.append(prop)
	t.check(unclassified.is_empty(),
		"%d TankConfig properties are not in ConfigCuration.MANIFEST — "
			% unclassified.size()
		+ "triage them with a tier and domain: %s" % ", ".join(unclassified))

	# --- NO ROT: the manifest names nothing that no longer exists ---
	var stale: Array[String] = []
	for prop in ConfigCuration.MANIFEST.keys():
		if not declared.has(String(prop)):
			stale.append(String(prop))
	t.check(stale.is_empty(),
		"MANIFEST lists %d properties TankConfig no longer declares — "
			% stale.size()
		+ "delete them: %s" % ", ".join(stale))

	t.equals(ConfigCuration.MANIFEST.size(), declared.size(),
		"the manifest and TankConfig must have the same property count")

	# --- Every entry is well-formed ---
	for prop in ConfigCuration.MANIFEST.keys():
		var name: String = String(prop)
		var tier: int = ConfigCuration.tier_of(name)
		t.in_range(float(tier), 0.0, float(ConfigCuration.TIER_NAMES.size() - 1),
			"%s has an out-of-range tier" % name)
		t.check(not ConfigCuration.domain_of(name).is_empty(),
			"%s has no domain" % name)

	# --- State and internals are never offered as settings ---
	# Letting a player edit save bookkeeping or camera_yaw from a settings
	# screen is a bug, not a feature.
	for prop in ConfigCuration.properties_in_tier(ConfigCuration.TIER_STATE):
		t.check(not ConfigCuration.is_setting(prop),
			"%s is TIER_STATE and must not count as a setting" % prop)
	for prop in ConfigCuration.properties_in_tier(ConfigCuration.TIER_INTERNAL):
		t.check(not ConfigCuration.is_setting(prop),
			"%s is TIER_INTERNAL and must not count as a setting" % prop)
	# Anything starting with "_" is bookkeeping by convention.
	for prop in declared:
		if prop.begins_with("_"):
			t.check(ConfigCuration.tier_of(prop) == ConfigCuration.TIER_INTERNAL,
				"%s starts with _ so it must be TIER_INTERNAL" % prop)

	# --- Modes are nested, not arbitrary sets ---
	# Simple must be a strict subset of Advanced, which must be a subset of
	# Expert; otherwise "more advanced" could HIDE something, which is
	# exactly the confusion this layer is meant to remove.
	var simple: Dictionary = ConfigCuration.properties_for_mode(ConfigCuration.MODE_SIMPLE)
	var advanced: Dictionary = ConfigCuration.properties_for_mode(ConfigCuration.MODE_ADVANCED)
	var expert: Dictionary = ConfigCuration.properties_for_mode(ConfigCuration.MODE_EXPERT)
	var s_all: Array[String] = _flatten(simple)
	var a_all: Array[String] = _flatten(advanced)
	var e_all: Array[String] = _flatten(expert)
	for p in s_all:
		t.check(a_all.has(p), "simple-mode property %s must also appear in advanced" % p)
	for p in a_all:
		t.check(e_all.has(p), "advanced-mode property %s must also appear in expert" % p)
	t.check(s_all.size() < a_all.size(), "advanced must show more than simple")
	t.check(a_all.size() < e_all.size(), "expert must show more than advanced")

	# --- Simple mode is actually simple ---
	# The whole point is a first-session surface a person can read. If this
	# creeps past ~25 the curation has failed and needs re-tightening.
	t.in_range(float(s_all.size()), 5.0, 25.0,
		"simple mode should show 5-25 knobs, shows %d" % s_all.size())

	# --- No STATE/INTERNAL leaks into any mode ---
	for p in e_all:
		t.check(ConfigCuration.is_setting(p),
			"%s leaked into a UI mode but is not a setting" % p)

	# --- Domains are ordered, and every used domain is known ---
	for domain in simple.keys():
		t.check(ConfigCuration.DOMAIN_ORDER.has(String(domain)),
			"domain '%s' is used but missing from DOMAIN_ORDER" % String(domain))

	# --- Unknown properties default to hidden, not shown ---
	t.equals(ConfigCuration.tier_of("not_a_real_property"),
		ConfigCuration.TIER_EXPERT,
		"an unknown property must default to EXPERT (hidden), never ESSENTIAL")
	t.check(not ConfigCuration.is_curated("not_a_real_property"),
		"is_curated is false for an unknown property")

	# --- Summary is coherent ---
	var sm: Dictionary = ConfigCuration.summary()
	t.equals(int(sm["total"]), declared.size(), "summary total matches TankConfig")
	t.check(int(sm["settings"]) < int(sm["total"]),
		"settings count must exclude state/internal")
	t.has_keys(sm, ["total", "settings", "by_tier"], "summary shape")

	print("[config_curation] %d properties = %d real settings + %d state/internal"
		% [int(sm["total"]), int(sm["settings"]),
			int(sm["total"]) - int(sm["settings"])])
	print("[config_curation] simple=%d advanced=%d expert=%d"
		% [s_all.size(), a_all.size(), e_all.size()])

	quit(t.finish())


func _flatten(grouped: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for d in grouped.keys():
		for p in grouped[d]:
			out.append(String(p))
	return out
