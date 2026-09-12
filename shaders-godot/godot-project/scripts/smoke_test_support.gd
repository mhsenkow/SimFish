extends SceneTree

# The shared harness testing itself (BROAD_DIRECTIONS #11).
#
# Worth having because 154 other suites now depend on it: a silent bug in
# report()'s exit code would turn the whole suite advisory, which is exactly
# the failure mode #10 and #11 exist to end.


func _initialize() -> void:
	var t := TestSupport.Suite.new("smoke_test_support")

	# --- Suite.check counts and records ---
	t.check(true, "a passing check must not record a failure")
	var probe := TestSupport.Suite.new("probe")
	probe.check(true, "ok")
	t.equals(probe.checks, 1, "check() increments the counter")
	t.equals(probe.failures.size(), 0, "a passing check records nothing")
	probe.check(false, "deliberate")
	t.equals(probe.checks, 2, "a failing check still counts")
	t.equals(probe.failures.size(), 1, "a failing check records its message")
	t.check(probe.failures[0] == "deliberate", "the recorded message is the one given")

	# check() returns its condition, so callers can early-out on it.
	t.check(probe.check(true, "x") == true, "check() returns true when passing")
	t.check(probe.check(false, "y") == false, "check() returns false when failing")

	# --- fail() ---
	var pf := TestSupport.Suite.new("p")
	pf.fail("explicit")
	t.equals(pf.failures.size(), 1, "fail() records unconditionally")
	t.equals(pf.checks, 1, "fail() counts as a check")

	# --- approx ---
	var pa := TestSupport.Suite.new("p")
	pa.approx(1.0, 1.0, "exact")
	t.equals(pa.failures.size(), 0, "approx passes on equal values")
	pa.approx(1.0, 2.0, "way off")
	t.equals(pa.failures.size(), 1, "approx fails outside tolerance")
	t.check(pa.failures[0].contains("expected 2.000000")
			and pa.failures[0].contains("got 1.000000"),
		"approx must report BOTH expected and actual: %s" % pa.failures[0])
	# Tolerance is honoured, and is inclusive at the boundary.
	var pt := TestSupport.Suite.new("p")
	pt.approx(1.0, 1.05, "within tolerance", 0.1)
	t.equals(pt.failures.size(), 0, "approx respects a custom tolerance")

	# --- in_range ---
	var pr := TestSupport.Suite.new("p")
	pr.in_range(5.0, 0.0, 10.0, "inside")
	t.equals(pr.failures.size(), 0, "in_range passes inside the band")
	pr.in_range(0.0, 1.0, 10.0, "below")
	pr.in_range(11.0, 1.0, 10.0, "above")
	t.equals(pr.failures.size(), 2, "in_range fails on both sides")
	# Bounds are inclusive.
	var pb := TestSupport.Suite.new("p")
	pb.in_range(1.0, 1.0, 2.0, "at low bound")
	pb.in_range(2.0, 1.0, 2.0, "at high bound")
	t.equals(pb.failures.size(), 0, "in_range bounds are inclusive")

	# --- has_keys names what is missing ---
	var pk := TestSupport.Suite.new("p")
	pk.has_keys({"a": 1, "b": 2}, ["a", "b"], "all present")
	t.equals(pk.failures.size(), 0, "has_keys passes when all keys exist")
	pk.has_keys({"a": 1}, ["a", "b", "c"], "some missing")
	t.equals(pk.failures.size(), 1, "has_keys fails when a key is absent")
	t.check(pk.failures[0].contains("b") and pk.failures[0].contains("c"),
		"has_keys must name the missing keys: %s" % pk.failures[0])

	# --- Drop-in statics match the Suite semantics ---
	var failed: Array[String] = []
	TestSupport.check(failed, true, "ok")
	t.equals(failed.size(), 0, "static check records nothing on pass")
	TestSupport.check(failed, false, "nope")
	t.equals(failed.size(), 1, "static check records on fail")
	t.check(TestSupport.check(failed, true, "z") == true,
		"static check returns its condition")

	# --- report() exit codes: the contract 154 suites rely on ---
	t.equals(TestSupport.report("t", [] as Array[String], 5), 0,
		"a clean suite with checks must exit 0")
	t.equals(TestSupport.report("t", ["a"] as Array[String], 5), 1,
		"a suite with failures must exit 1")
	t.equals(TestSupport.report("t", [] as Array[String], -1), 0,
		"an uncounted clean suite must still exit 0")

	# THE important one: a suite that ran ZERO checks is not a pass. This is
	# the bug class the old copy-pasted helpers could not catch — an early
	# return skipped the body and the smoke exited 0 having tested nothing.
	t.equals(TestSupport.report("t", [] as Array[String], 0), 1,
		"a suite that ran no assertions must FAIL, not pass")

	# --- Suite.finish() agrees with report() ---
	var pass_suite := TestSupport.Suite.new("all_good")
	pass_suite.check(true, "fine")
	t.equals(pass_suite.finish(), 0, "finish() returns 0 for a clean suite")
	var fail_suite := TestSupport.Suite.new("has_fail")
	fail_suite.check(false, "bad")
	t.equals(fail_suite.finish(), 1, "finish() returns 1 for a failed suite")
	var empty_suite := TestSupport.Suite.new("ran_nothing")
	t.equals(empty_suite.finish(), 1, "finish() returns 1 for a suite with no checks")

	quit(t.finish())
