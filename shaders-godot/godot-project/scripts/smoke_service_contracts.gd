extends SceneTree

# Service-contract gate (BROAD_DIRECTIONS #8).
#
# THE POINT. GDScript cannot type-check a call across a module seam reached
# as a bare `Node`, so renaming `SimDriver.daylight()` used to break 77 call
# sites with zero parse errors — each one silently taking its fallback,
# leaving the tank behaving as if permanently noon. This suite is the
# missing check: every method declared in SimGate.CONTRACT must actually
# exist, with the right arity, on the real provider.
#
# If this goes red, do NOT "fix" it by editing the contract. Either restore
# the method or migrate the callers — the red build is the whole feature.
#
# NB: the providers are inspected as SOURCE TEXT, not via preload(). Both
# world.gd and sim_driver.gd reference autoload globals (TankConfig et al.)
# that a `--script` run does not mount, so preloading them fails to compile
# and Godot then boots the main scene and hangs. Source inspection is also
# closer to what we actually want to assert: is the method declared in the
# file that owns the contract?

const PROVIDER_SOURCES: Dictionary = {
	"SimDriver": "res://scripts/sim_driver.gd",
	"World": "res://scripts/world.gd",
}


func _initialize() -> void:
	var t := TestSupport.Suite.new("smoke_service_contracts")

	# --- Every contract entry exists on its real provider ---
	for provider_name in SimGate.CONTRACT.keys():
		var pname: String = String(provider_name)
		if not t.check(PROVIDER_SOURCES.has(pname),
				"CONTRACT names provider '%s' but the smoke has no source path for it"
					% pname):
			continue
		var path: String = String(PROVIDER_SOURCES[pname])
		var src: String = FileAccess.get_file_as_string(path)
		if not t.check(not src.is_empty(), "%s source unreadable at %s" % [pname, path]):
			continue
		var declared: Dictionary = _declared_methods(src)
		var required: Dictionary = SimGate.CONTRACT[provider_name]
		for method_name in required.keys():
			var mname: String = String(method_name)
			if not t.check(declared.has(mname),
					"%s.%s() is declared in SimGate.CONTRACT but does not exist in %s — "
						% [pname, mname, path]
					+ "every caller is silently using its fallback"):
				continue
			# The provider must accept at least the contracted arity. More is
			# fine — several of these have optional params with defaults.
			var have: int = int(declared[mname])
			var want: int = int(required[method_name])
			t.check(have >= want,
				"%s.%s() accepts %d params but the contract passes %d"
					% [pname, mname, have, want])

	# --- SimGate has an accessor for everything it declares ---
	# A contract entry with no accessor is dead weight; an accessor with no
	# contract entry is not covered by this gate.
	var gate_src: String = FileAccess.get_file_as_string("res://scripts/sim_gate.gd")
	t.check(not gate_src.is_empty(), "sim_gate.gd source readable")
	for provider_name in SimGate.CONTRACT.keys():
		for method_name in (SimGate.CONTRACT[provider_name] as Dictionary).keys():
			t.check(gate_src.contains("static func %s(" % String(method_name)),
				"SimGate.CONTRACT declares %s.%s() but SimGate has no accessor"
					% [String(provider_name), String(method_name)])

	# --- Accessors are null-safe and return the CALLER's fallback ---
	# Null is normal: headless tests, teardown, a panel built before the
	# world exists. It must be silent and predictable, never an error.
	SimGate.reset_reports()
	t.approx(SimGate.daylight(null, 1.0), 1.0, "daylight(null) returns the fallback")
	t.approx(SimGate.daylight(null, 0.5), 0.5,
		"daylight(null) honours a 0.5 fallback (callers differ deliberately)")
	t.is_empty_arr(SimGate.query_plants_in_radius(null, Vector3.ZERO, 1.0),
		"query_plants_in_radius(null) returns empty")
	# Returning ZERO here would teleport creatures to the tank centre, which
	# is far more visible than leaving them briefly out of bounds.
	var p := Vector3(1.0, 2.0, 3.0)
	t.check(SimGate.clamp_xyz_in_tank(null, p).is_equal_approx(p),
		"clamp_xyz_in_tank(null) returns the point unchanged, not ZERO")
	t.approx(SimGate.column_surface_y(null, 0.0, 0.0, 4.0), 4.0,
		"column_surface_y(null) returns the fallback")
	t.check(SimGate.sample_flow(null, Vector3.ZERO) == Vector3.ZERO,
		"sample_flow(null) returns no flow")
	t.approx(SimGate.effective_warmth_at(null, Vector3.ZERO, 0.25), 0.25,
		"effective_warmth_at(null) returns the fallback")
	# Defaulting false would strand every creature against invisible walls.
	t.check(SimGate.is_inside_tank(null, 0.0, 0.0),
		"is_inside_tank(null) must default to true, not false")

	# --- A live provider that lacks the method falls back, loudly but safely ---
	# The push_error below is EXPECTED output for this case.
	SimGate.reset_reports()
	var stub := Node.new()
	root.add_child(stub)
	t.approx(SimGate.daylight(stub, 0.75), 0.75,
		"a provider without daylight() still returns the fallback")
	t.check(SimGate.clamp_xyz_in_tank(stub, p).is_equal_approx(p),
		"a provider without clamp_xyz_in_tank() returns the point unchanged")
	t.check(SimGate.is_inside_tank(stub, 0.0, 0.0),
		"a provider without is_inside_tank() still defaults true")
	stub.free()

	# --- A working provider is actually used, not bypassed ---
	# Guards against an accessor that always returns its fallback.
	var live := _StubSim.new()
	root.add_child(live)
	SimGate.reset_reports()
	t.approx(SimGate.daylight(live, -1.0), 0.42,
		"a provider WITH daylight() must be called, not fallen back on")
	t.check(SimGate.sample_flow(live, Vector3.ZERO) == Vector3(1.0, 0.0, 0.0),
		"sample_flow must return the provider's value")
	t.check(SimGate.is_inside_tank(live, 0.0, 0.0) == false,
		"is_inside_tank must return the provider's answer, not the default")
	t.equals(SimGate.query_plants_in_radius(live, Vector3.ZERO, 5.0).size(), 2,
		"query_plants_in_radius must return the provider's array")
	live.free()

	quit(t.finish())


# Minimal stand-in that satisfies the contract with known values, so the
# accessors can be proven to actually delegate.
class _StubSim:
	extends Node

	func daylight() -> float:
		return 0.42

	func sample_flow(_pos: Vector3) -> Vector3:
		return Vector3(1.0, 0.0, 0.0)

	func is_inside_tank(_x: float, _z: float, _margin: float = 0.0,
			_world_y: float = NAN) -> bool:
		return false

	func query_plants_in_radius(_pos: Vector3, _max_dist: float) -> Array:
		return ["a", "b"]


# method name -> declared parameter count, parsed from source. Handles the
# multi-line signatures this codebase uses (clamp_xyz_in_tank wraps).
func _declared_methods(src: String) -> Dictionary:
	var out: Dictionary = {}
	var lines: PackedStringArray = src.split("\n")
	for i in lines.size():
		var ln: String = lines[i]
		if not (ln.begins_with("func ") or ln.begins_with("static func ")):
			continue
		var open: int = ln.find("(")
		if open < 0:
			continue
		var head: String = ln.substr(0, open)
		var name: String = head.replace("static func ", "").replace("func ", "").strip_edges()
		# Gather the signature, following continuation lines until parens close.
		var sig: String = ln.substr(open + 1)
		var depth: int = 1
		var j: int = i
		while j < lines.size():
			var seg: String = sig if j == i else lines[j]
			var closed: bool = false
			for c in seg.length():
				var ch: String = seg[c]
				if ch == "(":
					depth += 1
				elif ch == ")":
					depth -= 1
					if depth == 0:
						sig = sig if j == i else sig + " " + seg
						closed = true
						break
			if closed:
				break
			if j > i:
				sig += " " + seg
			j += 1
			if j - i > 6:
				break
		# Count params by top-level commas, ignoring those inside nested
		# parens/brackets (default values like Vector3(0, 0, 0)).
		var body: String = sig.split(")")[0] if sig.contains(")") else sig
		var count: int = 0
		var nest: int = 0
		var seen_any: bool = false
		for c in body.length():
			var ch2: String = body[c]
			if ch2 == "(" or ch2 == "[" or ch2 == "{":
				nest += 1
			elif ch2 == ")" or ch2 == "]" or ch2 == "}":
				nest -= 1
			elif ch2 == "," and nest == 0:
				count += 1
			elif ch2 != " " and ch2 != "\t":
				seen_any = true
		out[name] = (count + 1) if seen_any else 0
	return out
