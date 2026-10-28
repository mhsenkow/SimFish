extends SceneTree

# Headless timing + sanity run of the WaterCurrent solver.
#   ./scripts/godot.sh --headless --path shaders-godot/godot-project --script res://dev/water_current_bench.gd

const WC := preload("res://scripts/water_current.gd")


func _init() -> void:
	for dims in [Vector3(8.0, 6.5, 4.0), Vector3(10.0, 9.0, 7.0), Vector3(4.0, 5.0, 4.0)]:
		var f: WaterCurrent = WC.new()
		var floor_y: float = 1.6
		f.build(dims.x, dims.z, floor_y, dims.y, func(p: Vector3) -> bool:
			return p.y < floor_y + 0.2)
		f.add_plume(Vector3(-dims.x * 0.6, floor_y + 0.4, -dims.z * 0.5), 2.2, 0.35)
		f.add_filter(Vector3(dims.x * 0.8, dims.y - 0.6, -dims.z * 0.7), Vector3(-1, -0.15, 0.25),
			2.4, Vector3(dims.x * 0.8, floor_y + 1.2, -dims.z * 0.7), 0.35)
		var t0: int = Time.get_ticks_usec()
		var steps: int = 60
		for s in steps:
			f.step(1.0 / 12.0)
		var us: float = float(Time.get_ticks_usec() - t0) / steps
		var st: Dictionary = f.stats()
		print("[wc-bench] grid %dx%dx%d (%d cells, cell %.2f): %.2f ms/step  max %.2f mean %.3f u/s  resid_div %.3f" % [
			f.nx, f.ny, f.nz, f.cell_count(), f.cell, us / 1000.0,
			float(st["max"]), float(st["mean"]), f.residual_divergence()])
		var mid := Vector3(0.0, (floor_y + dims.y) * 0.5, 0.0)
		print("[wc-bench]   v(mid)=", f.velocity_at(mid), " v(plume top)=",
			f.velocity_at(Vector3(-dims.x * 0.6, dims.y - 0.5, -dims.z * 0.5)),
			" v(far glass low)=", f.velocity_at(Vector3(dims.x * 0.7, floor_y + 0.8, dims.z * 0.6)))
	quit(0)
