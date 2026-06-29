extends SceneTree

# META #13 — the cognitive spine as a validated DAG. Verifies the real spine is
# acyclic, every module ticks after its prerequisites, the key endpoints are
# anchored (protoself first, binding after its deps, encode last), cycles and
# dangling prereqs are rejected, and a newly-added module slots in correctly.


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	var order: Array = MindModuleGraph.topo_order()
	_assert(failed, order.size() == MindModuleGraph.DEPS.size() and not order.is_empty(),
			"the real spine topo-sorts (acyclic, all nodes ordered)")

	# Every declared prerequisite ticks before its dependent.
	var ok_deps := true
	for node in MindModuleGraph.DEPS.keys():
		for pre in MindModuleGraph.DEPS[node]:
			if not MindModuleGraph.is_before(order, str(pre), str(node)):
				ok_deps = false
	_assert(failed, ok_deps, "every prerequisite precedes its dependent in the order")

	# Anchored endpoints.
	_assert(failed, order[0] == "protoself", "protoself ticks first (%s)" % str(order[0]))
	_assert(failed, order[order.size() - 1] == "encode", "encode ticks last")
	_assert(failed, MindModuleGraph.is_before(order, "core_affect", "binding")
			and MindModuleGraph.is_before(order, "felt_now", "binding")
			and MindModuleGraph.is_before(order, "qualia", "binding"),
			"binding ticks after the modules it integrates")

	# A dependency cycle is rejected (not silently ordered).
	_assert(failed, MindModuleGraph.topo_sort({"a": ["b"], "b": ["a"]}).is_empty(),
			"a cycle yields no order")
	_assert(failed, not MindModuleGraph.is_valid({"a": ["a"]}), "a self-edge is invalid")
	# A dangling prerequisite is rejected.
	_assert(failed, MindModuleGraph.topo_sort({"a": ["ghost"]}).is_empty(),
			"a dangling prerequisite is invalid")

	# Adding a module with a dependency places it after that dependency.
	var ext: Dictionary = MindModuleGraph.DEPS.duplicate(true)
	ext["mood_weather"] = ["binding"]   # a hypothetical new module after binding
	var ext_order: Array = MindModuleGraph.topo_sort(ext)
	_assert(failed, not ext_order.is_empty() and MindModuleGraph.is_before(ext_order, "binding", "mood_weather"),
			"a newly-added module is ordered after its declared dependency")

	if failed.is_empty():
		print("[smoke] module_graph OK")
		quit(0)
	else:
		for m in failed:
			push_error("[smoke] " + m)
		quit(1)


func _assert(failed: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		failed.append(msg)
