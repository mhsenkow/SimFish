class_name TestSupport
extends RefCounted

# Shared smoke-test harness (BROAD_DIRECTIONS #11).
#
# Before this, 86 of the 155 smoke scripts each defined a byte-identical
# `_assert(failed, cond, msg)` helper, plus 24 defined `_fail` and 13
# `_run_all`. Every file reinvented its own reporting format and exit path.
#
# Deduplication is the least of it. What the copies could not give us:
#
#   1. **A smoke that asserts nothing must fail.** The old pattern was
#      `var failed: Array[String] = []` ... `if failed.is_empty(): quit(0)`.
#      A script whose assertions were all accidentally skipped — an early
#      return, a guard that never opened, a renamed API silently returning
#      null — exits 0 and reads as green. `report()` treats zero checks as
#      a failure, because a test that tested nothing is not a passing test.
#   2. **Uniform output.** One format for every suite, so the runner (#10)
#      can parse results rather than just reading exit codes.
#   3. **Assertions worth having.** approx/in-range/has-keys, each producing
#      a message that says what was expected AND what was found. The old
#      helper could only report the label the author remembered to write.
#
# TWO WAYS TO USE IT
#
# Drop-in, for the existing `failed: Array[String]` style:
#
#   TestSupport.check(failed, cond, "message")
#   ...
#   quit(TestSupport.report("smoke_thing", failed))
#
# Suite, preferred for new tests — counts checks, so `report_suite()` can
# tell "40 passed" from "nothing ran":
#
#   var t := TestSupport.Suite.new("smoke_thing")
#   t.check(cond, "message")
#   t.approx(got, want, "message")
#   quit(t.finish())


# --- Suite -----------------------------------------------------------------

class Suite:
	extends RefCounted

	var suite_name: String = "smoke"
	var failures: Array[String] = []
	var checks: int = 0

	func _init(name: String = "smoke") -> void:
		suite_name = name

	# Returns the condition so a caller can branch on it:
	#   if not t.check(node != null, "node exists"): return
	func check(ok: bool, message: String) -> bool:
		checks += 1
		if not ok:
			failures.append(message)
		return ok

	func fail(message: String) -> void:
		checks += 1
		failures.append(message)

	# Float comparison with an explicit tolerance. Reports both values,
	# which a bare check() cannot.
	func approx(got: float, want: float, message: String,
			tolerance: float = 0.0001) -> bool:
		return check(absf(got - want) <= tolerance,
			"%s (expected %.6f, got %.6f)" % [message, want, got])

	func in_range(got: float, low: float, high: float, message: String) -> bool:
		return check(got >= low and got <= high,
			"%s (expected %.6f..%.6f, got %.6f)" % [message, low, high, got])

	func equals(got: Variant, want: Variant, message: String) -> bool:
		return check(got == want,
			"%s (expected %s, got %s)" % [message, str(want), str(got)])

	# Every key must be present. Reports the missing ones rather than just
	# "shape wrong", which is the difference between a 10-second and a
	# 10-minute diagnosis.
	func has_keys(d: Dictionary, keys: Array, message: String) -> bool:
		var missing: Array[String] = []
		for k in keys:
			if not d.has(k):
				missing.append(str(k))
		return check(missing.is_empty(),
			"%s (missing keys: %s)" % [message, ", ".join(missing)])

	func is_empty_arr(a: Array, message: String) -> bool:
		return check(a.is_empty(),
			"%s (expected empty, got %d: %s)" % [message, a.size(), str(a).left(160)])

	# Print the result and return the process exit code.
	# NB: must qualify with TestSupport — an inner class does not inherit the
	# outer class's scope, so a bare report() does not resolve.
	func finish() -> int:
		return TestSupport.report(suite_name, failures, checks)


# --- Drop-in helpers -------------------------------------------------------

# Matches the `_assert(failed, cond, msg)` shape the smokes already use.
static func check(failed: Array[String], ok: bool, message: String) -> bool:
	if not ok:
		failed.append(message)
	return ok


static func approx(failed: Array[String], got: float, want: float,
		message: String, tolerance: float = 0.0001) -> bool:
	return check(failed, absf(got - want) <= tolerance,
		"%s (expected %.6f, got %.6f)" % [message, want, got])


# --- Reporting -------------------------------------------------------------

# Uniform result line + exit code. `checks` is optional so the drop-in
# callers that do not count can still use it; pass it when you have it and
# a no-op suite becomes detectable.
#
# Output is machine-readable on purpose — the runner in #10 parses it:
#   SMOKE <name> PASS checks=42 failures=0
#   SMOKE <name> FAIL checks=42 failures=3
static func report(suite_name: String, failures: Array[String],
		checks: int = -1) -> int:
	if checks == 0:
		# Not a pass. A suite that ran no assertions has not tested anything,
		# and the most common cause is an early return that skipped the body.
		printerr("SMOKE %s FAIL checks=0 failures=0" % suite_name)
		printerr("  no assertions ran — the suite body was skipped or empty")
		return 1
	var shown: int = checks if checks >= 0 else -1
	if failures.is_empty():
		if shown >= 0:
			print("SMOKE %s PASS checks=%d failures=0" % [suite_name, shown])
		else:
			print("SMOKE %s PASS failures=0" % suite_name)
		return 0
	if shown >= 0:
		printerr("SMOKE %s FAIL checks=%d failures=%d" % [suite_name, shown, failures.size()])
	else:
		printerr("SMOKE %s FAIL failures=%d" % [suite_name, failures.size()])
	for f in failures:
		printerr("  - %s" % f)
	return 1
