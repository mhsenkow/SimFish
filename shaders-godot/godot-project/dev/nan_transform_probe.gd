# Headless sweep for Node3D / MultiMesh transforms that go non-finite.
# Reproduces the debugger flood: instance_set_transform "!v.is_finite()".
#
#   GODOT_ISOLATE=1 ./scripts/godot.sh --headless --path shaders-godot/godot-project \
#     --script res://dev/nan_transform_probe.gd
extends SceneTree

const WARMUP_FRAMES: int = 240
const SAMPLE_FRAMES: int = 180


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_ps: PackedScene = load("res://main.tscn") as PackedScene
	if main_ps == null:
		push_error("nan_transform_probe: cannot load main.tscn")
		quit(1)
		return
	var main: Node = main_ps.instantiate()
	root.add_child(main)
	var hits: Dictionary = {}  # path -> count
	var first_detail: Dictionary = {}
	for i in range(WARMUP_FRAMES + SAMPLE_FRAMES):
		await process_frame
		if i < WARMUP_FRAMES:
			continue
		_sweep(root, hits, first_detail)
	print("=== nan_transform_probe ===")
	print("unique bad paths: %d" % hits.size())
	var keys: Array = hits.keys()
	keys.sort_custom(func(a, b): return int(hits[a]) > int(hits[b]))
	var shown: int = 0
	for k in keys:
		print("%5d  %s" % [hits[k], k])
		if first_detail.has(k):
			print("       %s" % first_detail[k])
		shown += 1
		if shown >= 40:
			break
	var code: int = 0 if hits.is_empty() else 2
	quit(code)


func _sweep(n: Node, hits: Dictionary, first_detail: Dictionary) -> void:
	if n is Node3D:
		var n3: Node3D = n as Node3D
		if n3.is_inside_tree():
			var gt: Transform3D = n3.global_transform
			if not gt.is_finite():
				var path: String = str(n3.get_path())
				hits[path] = int(hits.get(path, 0)) + 1
				if not first_detail.has(path):
					var parent_n: Node = n3.get_parent()
					var parent_name: String = String(parent_n.name) if parent_n != null else "?"
					first_detail[path] = "origin=%s scale=%s class=%s parent=%s" % [
						gt.origin, n3.scale, n3.get_class(), parent_name]
			if n3 is MultiMeshInstance3D:
				var mmi: MultiMeshInstance3D = n3 as MultiMeshInstance3D
				var mm: MultiMesh = mmi.multimesh
				if mm != null:
					var vis: int = mm.visible_instance_count
					var lim: int = mm.instance_count if vis < 0 else mini(vis, mm.instance_count)
					lim = mini(lim, 64)
					for j in range(lim):
						var xf: Transform3D = mm.get_instance_transform(j)
						if not xf.is_finite():
							var mp: String = "%s#mm[%d]" % [str(n3.get_path()), j]
							hits[mp] = int(hits.get(mp, 0)) + 1
							if not first_detail.has(mp):
								first_detail[mp] = "origin=%s" % xf.origin
	for c in n.get_children():
		_sweep(c, hits, first_detail)
