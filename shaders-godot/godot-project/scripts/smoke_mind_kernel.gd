extends SceneTree

# PERFORMANCE_UNTHROTTLED #49/#50 — mind kernel boot self-test + SoA parity.

const MindKernel = preload("res://scripts/mind_kernel.gd")
const GlobalWorkspace = preload("res://scripts/global_workspace.gd")


func _initialize() -> void:
	MindKernel.reset_for_test()
	if not MindKernel.boot_self_test():
		push_error("[smoke] mind_kernel boot self-test failed (backend=%s)" % MindKernel.backend_name())
		quit(1)
		return
	if not GlobalWorkspace.run_competition_smoke_parity():
		push_error("[smoke] workspace/kernel competition parity failed")
		quit(1)
		return
	print("[smoke] mind_kernel OK (%s)" % MindKernel.backend_name())
	quit(0)
