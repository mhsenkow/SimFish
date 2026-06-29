class_name MindModuleGraph
extends RefCounted

# META #13 — the cognitive spine as DATA, not hand-ordered calls. Each module
# declares its prerequisites; `topo_order()` produces a validated tick order via
# Kahn's algorithm (deterministic, cycle-detecting). This makes the order
# inspectable + testable, so adding a module or introducing a dependency cycle is
# caught by a test instead of silently corrupting the felt-self spine.
#
# Scope note: this is the declarative SPEC + guard for the order the cycle runs
# (perceive→attend→bind→encode in mind_cycle.gd). Turning it into the live
# dispatcher (data-driven tick) is a follow-up; this pins the contract first.

const DEPS: Dictionary = {
	# perceive
	"protoself": [],
	"core_affect": ["protoself"],
	# attend
	"relevance": ["core_affect"],
	"workspace": ["relevance"],
	# bind (the bind phase runs after attention, so it hangs off workspace)
	"felt_now": ["workspace"],
	"generative_self": ["felt_now"],
	"concepts": ["felt_now"],
	"qualia": ["felt_now"],
	"volition": ["core_affect"],
	"continuity": ["felt_now"],
	"binding": ["protoself", "core_affect", "relevance", "felt_now", "qualia", "volition", "continuity"],
	# encode
	"encode": ["binding"],
}


# Kahn's algorithm. Returns a topological order, or [] if `deps` has a cycle or a
# dangling prerequisite. Deterministic: ready nodes are taken in sorted order.
static func topo_sort(deps: Dictionary) -> Array:
	var indeg: Dictionary = {}
	var dependents: Dictionary = {}
	for node in deps.keys():
		indeg[node] = 0
		dependents[node] = []
	for node in deps.keys():
		for pre in deps[node]:
			if not deps.has(pre):
				return []   # dangling prerequisite — invalid graph
			indeg[node] = int(indeg[node]) + 1
			(dependents[pre] as Array).append(node)
	var queue: Array = []
	for node in deps.keys():
		if int(indeg[node]) == 0:
			queue.append(node)
	var out: Array = []
	while not queue.is_empty():
		queue.sort()
		var n: Variant = queue.pop_front()
		out.append(n)
		for d in (dependents[n] as Array):
			indeg[d] = int(indeg[d]) - 1
			if int(indeg[d]) == 0:
				queue.append(d)
	if out.size() != deps.size():
		return []   # cycle
	return out


# The validated tick order for the real spine.
static func topo_order() -> Array:
	return topo_sort(DEPS)


# True if `deps` is a valid DAG (acyclic + no dangling prereqs).
static func is_valid(deps: Dictionary = DEPS) -> bool:
	return not topo_sort(deps).is_empty()


# True if `a` is ticked before `b` in the given order.
static func is_before(order: Array, a: String, b: String) -> bool:
	return order.find(a) < order.find(b) and order.has(a) and order.has(b)
