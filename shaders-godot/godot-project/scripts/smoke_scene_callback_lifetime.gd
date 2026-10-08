extends SceneTree

# Attach the real controller after ready to skip unrelated scene onready paths.
func _new_host(count: Dictionary) -> Node:
	var host := Node.new()
	root.add_child(host)
	host.set_script(load("res://scripts/voice_callback_test_ui_host.gd"))
	host.set("deliveries", count)
	return host


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_scene_callback_lifetime")
	var delivered := {"count": 0}
	var live := _new_host(delivered)
	live.call("schedule")
	await create_timer(0.12).timeout
	t.equals(delivered.count, 1, "live scene delivers delayed voice exactly once")
	live.free()

	var cancelled := {"count": 0}
	var freed := _new_host(cancelled)
	freed.call("schedule")
	freed.free()
	await create_timer(0.12).timeout
	t.equals(cancelled.count, 0, "freed scene cancels pending voice without calling its lambda")

	var detached := _new_host(cancelled)
	detached.call("schedule")
	root.remove_child(detached)
	await create_timer(0.12).timeout
	t.equals(cancelled.count, 0, "detached scene skips pending voice")
	detached.call("schedule")
	detached.free()

	var layer := Control.new()
	t.check(ToastStack.present(layer, {"body": "Detached"}) == null,
		"detached layer rejects new toasts before requesting its tree")
	root.add_child(layer)
	var toast := ToastStack.present(layer, {"body": "Transient"})
	t.check(toast != null, "live layer accepts toast")
	# Free during the two-frame layout wait, as happens on settings reload.
	layer.free()
	for i in 4:
		await process_frame
	t.equals(cancelled.count, 0, "teardown stays quiet after all pending frames")
	quit(t.finish())
