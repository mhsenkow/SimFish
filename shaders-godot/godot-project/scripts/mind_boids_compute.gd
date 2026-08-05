class_name MindBoidsCompute
extends RefCounted

# PERFORMANCE_UNTHROTTLED #57 — GPU compute pass with CPU fallback.

const SHADER_PATH := "res://shaders/mind_boids.glsl"
const WORKGROUP: int = 64
const CELL_SIZE: float = 3.0
const _CELL_OFFS: Array[int] = [-1, 0, 1]

static var _rd: RenderingDevice = null
static var _shader: RID = RID()
static var _pipeline: RID = RID()
static var _gpu_ready: bool = false
static var _gpu_failed: bool = false


static func reset_for_test() -> void:
	_gpu_ready = false
	_gpu_failed = false
	if _rd != null:
		if _pipeline.is_valid() and _rd.compute_pipeline_is_valid(_pipeline):
			_rd.free_rid(_pipeline)
		if _shader.is_valid():
			_rd.free_rid(_shader)
	_rd = null
	_shader = RID()
	_pipeline = RID()


static func run() -> void:
	var n: int = MindBoidsBuffer.count
	if n <= 0:
		MindBoidsBuffer.backend = "none"
		return
	# Topological schooling uses the CPU path until the GPU shader catches up.
	if _try_gpu(n) and not _needs_topo_cpu(n):
		MindBoidsBuffer.backend = "gpu"
		return
	_cpu_dispatch(n)
	MindBoidsBuffer.backend = "cpu"


static func _needs_topo_cpu(n: int) -> bool:
	for i in n:
		if MindBoidsBuffer.uses_topo_at(i):
			return true
	return false


static func _try_gpu(n: int) -> bool:
	# Extra local RenderingDevice + MultiMesh load on Metal fences badly.
	if _gpu_failed or DisplayServer.get_name() == "headless" or OS.get_name() == "macOS":
		return false
	if not _ensure_gpu():
		return false
	var params := PackedFloat32Array([
		float(n), MindBoidsBuffer.RADIUS_SQ, MindBoidsBuffer.VIEW_DOT, MindBoidsBuffer.LOOKAHEAD, 0.0,
	])
	var pos_buf := _pack_positions(n)
	var vel_buf := _pack_vec4(MindBoidsBuffer.velocities, n)
	var head_buf := _pack_vec4(MindBoidsBuffer.headings, n)
	var species_buf := PackedInt32Array()
	species_buf.resize(n)
	for i in n:
		species_buf[i] = MindBoidsBuffer.species_hash[i]
	var meta_buf := _pack_meta(n)
	var sep_out := _zero_vec4(n)
	var ali_out := _zero_vec4(n)
	var coh_out := _zero_vec4(n)
	var stats_out := PackedInt32Array()
	stats_out.resize(n * 4)
	stats_out.fill(0)

	var params_rid := _rd.storage_buffer_create(params.to_byte_array().size(), params.to_byte_array())
	var pos_rid := _rd.storage_buffer_create(pos_buf.size(), pos_buf)
	var vel_rid := _rd.storage_buffer_create(vel_buf.size(), vel_buf)
	var head_rid := _rd.storage_buffer_create(head_buf.size(), head_buf)
	var species_rid := _rd.storage_buffer_create(species_buf.to_byte_array().size(), species_buf.to_byte_array())
	var meta_rid := _rd.storage_buffer_create(meta_buf.size(), meta_buf)
	var sep_rid := _rd.storage_buffer_create(sep_out.size(), sep_out)
	var ali_rid := _rd.storage_buffer_create(ali_out.size(), ali_out)
	var coh_rid := _rd.storage_buffer_create(coh_out.size(), coh_out)
	var stats_rid := _rd.storage_buffer_create(stats_out.to_byte_array().size(), stats_out.to_byte_array())

	var uniforms: Array[RDUniform] = []
	for binding in 10:
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u.binding = binding
		match binding:
			0: u.add_id(params_rid)
			1: u.add_id(pos_rid)
			2: u.add_id(vel_rid)
			3: u.add_id(head_rid)
			4: u.add_id(species_rid)
			5: u.add_id(meta_rid)
			6: u.add_id(sep_rid)
			7: u.add_id(ali_rid)
			8: u.add_id(coh_rid)
			9: u.add_id(stats_rid)
		uniforms.append(u)
	var uniform_set := _rd.uniform_set_create(uniforms, _shader, 0)
	if not _rd.uniform_set_is_valid(uniform_set):
		_free_gpu_dispatch_resources(RID(), [
			params_rid, pos_rid, vel_rid, head_rid, species_rid, meta_rid,
			sep_rid, ali_rid, coh_rid, stats_rid,
		])
		return false
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pipeline)
	_rd.compute_list_bind_uniform_set(cl, uniform_set, 0)
	var groups: int = int(ceil(float(n) / float(WORKGROUP)))
	_rd.compute_list_dispatch(cl, groups, 1, 1)
	_rd.compute_list_end()
	_rd.submit()
	_rd.sync()

	_unpack_gpu_results(sep_rid, ali_rid, coh_rid, stats_rid, n)
	_free_gpu_dispatch_resources(uniform_set, [
		params_rid, pos_rid, vel_rid, head_rid, species_rid, meta_rid,
		sep_rid, ali_rid, coh_rid, stats_rid,
	])
	return true


static func _free_gpu_dispatch_resources(uniform_set: RID, buffer_rids: Array) -> void:
	if _rd == null:
		return
	# Free the uniform set before its storage buffers — freeing a bound buffer
	# first auto-invalidates the set (Godot #103073) and later free_rid calls
	# print "Attempted to free invalid ID". RID.is_valid() is not enough for sets.
	if _rd.uniform_set_is_valid(uniform_set):
		_rd.free_rid(uniform_set)
	for rid in buffer_rids:
		if rid is RID and (rid as RID).is_valid():
			_rd.free_rid(rid)


static func _ensure_gpu() -> bool:
	if _gpu_ready:
		return true
	if _gpu_failed:
		return false
	_rd = RenderingServer.create_local_rendering_device()
	if _rd == null:
		_gpu_failed = true
		return false
	if not ResourceLoader.exists(SHADER_PATH):
		_gpu_failed = true
		return false
	var shader_file: RDShaderFile = load(SHADER_PATH) as RDShaderFile
	if shader_file == null:
		_gpu_failed = true
		return false
	var spirv: RDShaderSPIRV = shader_file.get_spirv()
	if spirv == null:
		_gpu_failed = true
		return false
	_shader = _rd.shader_create_from_spirv(spirv)
	if not _shader.is_valid():
		_gpu_failed = true
		return false
	_pipeline = _rd.compute_pipeline_create(_shader)
	if not _pipeline.is_valid():
		_gpu_failed = true
		return false
	_gpu_ready = true
	return true


static func _cpu_dispatch(n: int) -> void:
	var grid: Dictionary = _build_index_grid(n)
	var inv_cell: float = 1.0 / CELL_SIZE
	var topo_d2: PackedFloat32Array = PackedFloat32Array()
	topo_d2.resize(MindBoidsBuffer.N_TOPO)
	var topo_idx: PackedInt32Array = PackedInt32Array()
	topo_idx.resize(MindBoidsBuffer.N_TOPO)
	for i in n:
		var pos_i: Vector3 = MindBoidsBuffer.positions[i]
		var head_i: Vector3 = MindBoidsBuffer.headings[i]
		var sp_i: int = MindBoidsBuffer.species_hash[i]
		var home_y: float = MindBoidsBuffer.home_y_radii[i]
		var sep_r: float = MindBoidsBuffer.separation_radii[i]
		var sep_r2: float = sep_r * sep_r
		var use_topo: bool = MindBoidsBuffer.uses_topo_at(i)
		var sep := Vector3.ZERO
		var ali := Vector3.ZERO
		var coh := Vector3.ZERO
		var speed_sum: float = 0.0
		var nc: int = 0
		for t in MindBoidsBuffer.N_TOPO:
			topo_neighbors_store(i, t, -1)
		if use_topo:
			for t in MindBoidsBuffer.N_TOPO:
				topo_d2[t] = 1e9
				topo_idx[t] = -1
			var topo_n: int = 0
			var cell_i := Vector2i(
				int(floor(pos_i.x * inv_cell)), int(floor(pos_i.z * inv_cell)))
			for ox in range(-2, 3):
				for oz in range(-2, 3):
					var bucket: Array = grid.get(cell_i + Vector2i(ox, oz), [])
					for j_v in bucket:
						var j: int = int(j_v)
						if j == i:
							continue
						var diff: Vector3 = pos_i - MindBoidsBuffer.positions[j]
						var d2: float = diff.length_squared()
						if d2 < 1e-4 or d2 > MindBoidsBuffer.MAX_CANDIDATE_R2:
							continue
						if MindBoidsBuffer.species_hash[j] != sp_i:
							if d2 < sep_r2:
								var push: Vector3 = diff
								push.y *= 0.45
								sep += push.normalized() / maxf(sqrt(d2), 0.1)
							continue
						if absf(diff.y) > home_y * 2.4:
							continue
						var to_n: Vector3 = -diff
						if head_i.dot(to_n.normalized()) < MindBoidsBuffer.VIEW_DOT:
							continue
						topo_n = _insert_topo(topo_d2, topo_idx, topo_n, _buddy_topo_d2(i, j, d2), j)
			if topo_n < MindBoidsBuffer.N_TOPO and n <= 64:
				for j in n:
					if j == i:
						continue
					var diff2: Vector3 = pos_i - MindBoidsBuffer.positions[j]
					var d2b: float = diff2.length_squared()
					if d2b < 1e-4 or d2b > MindBoidsBuffer.MAX_CANDIDATE_R2:
						continue
					if MindBoidsBuffer.species_hash[j] != sp_i:
						continue
					if absf(diff2.y) > home_y * 2.4:
						continue
					var to_nb: Vector3 = -diff2
					if head_i.dot(to_nb.normalized()) < MindBoidsBuffer.VIEW_DOT:
						continue
					topo_n = _insert_topo(topo_d2, topo_idx, topo_n, _buddy_topo_d2(i, j, d2b), j)
			nc = topo_n
			for t in range(topo_n):
				var j: int = topo_idx[t]
				if j < 0:
					continue
				topo_neighbors_store(i, t, j)
				var diff: Vector3 = pos_i - MindBoidsBuffer.positions[j]
				var d2: float = diff.length_squared()
				var to_n: Vector3 = -diff
				var flank_w: float = _flank_weight(head_i, to_n)
				if d2 < sep_r2:
					var push: Vector3 = diff
					push.y *= 0.45
					var ang_sep: float = 1.0 / maxf(sqrt(d2), 0.12)
					sep += push.normalized() * ang_sep * flank_w
				var predicted: Vector3 = MindBoidsBuffer.positions[j] \
						+ MindBoidsBuffer.velocities[j] * MindBoidsBuffer.LOOKAHEAD
				ali += MindBoidsBuffer.headings[j] * flank_w
				coh += predicted * flank_w
				speed_sum += MindBoidsBuffer.velocities[j].length() * flank_w
				if absf(diff.y) < home_y * 0.85:
					sep.y += signf(-diff.y) * 0.28 * flank_w
		else:
			var cell_i := Vector2i(
				int(floor(pos_i.x * inv_cell)), int(floor(pos_i.z * inv_cell)))
			for ox in _CELL_OFFS:
				for oz in _CELL_OFFS:
					var bucket: Array = grid.get(cell_i + Vector2i(ox, oz), [])
					for j_v in bucket:
						var j: int = int(j_v)
						if j == i:
							continue
						var diff: Vector3 = pos_i - MindBoidsBuffer.positions[j]
						var d2: float = diff.length_squared()
						if d2 < 1e-4:
							continue
						if d2 < sep_r2:
							var push: Vector3 = diff
							push.y *= 0.45
							sep += push.normalized() / maxf(sqrt(d2), 0.1)
						if MindBoidsBuffer.species_hash[j] != sp_i:
							continue
						if absf(diff.y) > home_y * 2.4:
							continue
						var to_n: Vector3 = -diff
						if head_i.dot(to_n.normalized()) < MindBoidsBuffer.VIEW_DOT:
							continue
						var predicted: Vector3 = MindBoidsBuffer.positions[j] \
								+ MindBoidsBuffer.velocities[j] * MindBoidsBuffer.LOOKAHEAD
						ali += MindBoidsBuffer.headings[j]
						coh += predicted
						speed_sum += MindBoidsBuffer.velocities[j].length()
						nc += 1
						if absf(diff.y) < home_y * 0.85:
							sep.y += signf(-diff.y) * 0.28
		MindBoidsBuffer.sep_accum[i] = sep
		MindBoidsBuffer.ali_accum[i] = ali
		MindBoidsBuffer.coh_center[i] = coh
		MindBoidsBuffer.neighbor_counts[i] = nc
		MindBoidsBuffer.school_speed_milli[i] = int(speed_sum * 1000.0)


static func topo_neighbors_store(fish_idx: int, slot: int, neighbor_idx: int) -> void:
	var flat: int = fish_idx * MindBoidsBuffer.N_TOPO + slot
	if flat >= 0 and flat < MindBoidsBuffer.topo_neighbors.size():
		MindBoidsBuffer.topo_neighbors[flat] = neighbor_idx


static func _buddy_topo_d2(fish_i: int, fish_j: int, d2: float) -> float:
	if fish_i < 0 or fish_j < 0 or fish_i >= MindBoidsBuffer.count or fish_j >= MindBoidsBuffer.count:
		return d2
	var fi: Node = MindBoidsBuffer.fish_refs[fish_i]
	var fj: Node = MindBoidsBuffer.fish_refs[fish_j]
	if fi != null and fj != null and fi.get("partner") == fj:
		return d2 * 0.72
	return d2


static func _insert_topo(dists: PackedFloat32Array, indices: PackedInt32Array,
		count: int, d2: float, j: int) -> int:
	var n_topo: int = MindBoidsBuffer.N_TOPO
	if count < n_topo:
		dists[count] = d2
		indices[count] = j
		return count + 1
	var worst: int = 0
	for k in range(1, n_topo):
		if dists[k] > dists[worst]:
			worst = k
	if d2 >= dists[worst]:
		return count
	dists[worst] = d2
	indices[worst] = j
	return n_topo


static func _flank_weight(head: Vector3, to_neighbor: Vector3) -> float:
	if to_neighbor.length_squared() < 1e-6:
		return 1.0
	var align: float = absf(head.normalized().dot(to_neighbor.normalized()))
	return 1.0 + MindBoidsBuffer.flank_bias * (1.0 - align)


static func _build_index_grid(n: int) -> Dictionary:
	var grid: Dictionary = {}
	var inv_cell: float = 1.0 / CELL_SIZE
	for i in n:
		var p: Vector3 = MindBoidsBuffer.positions[i]
		var cell := Vector2i(int(floor(p.x * inv_cell)), int(floor(p.z * inv_cell)))
		if grid.has(cell):
			(grid[cell] as Array).append(i)
		else:
			grid[cell] = [i]
	return grid


static func _pack_positions(n: int) -> PackedByteArray:
	var buf := PackedFloat32Array()
	buf.resize(n * 4)
	for i in n:
		var p: Vector3 = MindBoidsBuffer.positions[i]
		buf[i * 4 + 0] = p.x
		buf[i * 4 + 1] = p.y
		buf[i * 4 + 2] = p.z
		buf[i * 4 + 3] = MindBoidsBuffer.separation_radii[i]
	return buf.to_byte_array()


static func _pack_vec4(src: PackedVector3Array, n: int) -> PackedByteArray:
	var buf := PackedFloat32Array()
	buf.resize(n * 4)
	for i in n:
		var v: Vector3 = src[i]
		buf[i * 4 + 0] = v.x
		buf[i * 4 + 1] = v.y
		buf[i * 4 + 2] = v.z
		buf[i * 4 + 3] = 0.0
	return buf.to_byte_array()


static func _pack_meta(n: int) -> PackedByteArray:
	var buf := PackedFloat32Array()
	buf.resize(n * 4)
	for i in n:
		buf[i * 4 + 0] = MindBoidsBuffer.home_y_radii[i]
		buf[i * 4 + 1] = MindBoidsBuffer.lead_scores[i]
		buf[i * 4 + 2] = 0.0
		buf[i * 4 + 3] = 0.0
	return buf.to_byte_array()


static func _zero_vec4(n: int) -> PackedByteArray:
	var buf := PackedFloat32Array()
	buf.resize(n * 4)
	buf.fill(0.0)
	return buf.to_byte_array()


static func _unpack_gpu_results(sep_rid: RID, ali_rid: RID, coh_rid: RID, stats_rid: RID, n: int) -> void:
	var sep_f := _rd.buffer_get_data(sep_rid).to_float32_array()
	var ali_f := _rd.buffer_get_data(ali_rid).to_float32_array()
	var coh_f := _rd.buffer_get_data(coh_rid).to_float32_array()
	var stats_i := _rd.buffer_get_data(stats_rid).to_int32_array()
	for i in n:
		MindBoidsBuffer.sep_accum[i] = Vector3(sep_f[i * 4], sep_f[i * 4 + 1], sep_f[i * 4 + 2])
		MindBoidsBuffer.ali_accum[i] = Vector3(ali_f[i * 4], ali_f[i * 4 + 1], ali_f[i * 4 + 2])
		MindBoidsBuffer.coh_center[i] = Vector3(coh_f[i * 4], coh_f[i * 4 + 1], coh_f[i * 4 + 2])
		MindBoidsBuffer.neighbor_counts[i] = stats_i[i * 4]
		MindBoidsBuffer.school_speed_milli[i] = stats_i[i * 4 + 1]


static func smoke_ok() -> bool:
	MindBoidsBuffer.reset_for_test()
	var parent := Node3D.new()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.root.add_child(parent)
	var a := Fish.new()
	parent.add_child(a)
	a.id = "boid_a"
	a.species = "glassdart"
	a.position = Vector3.ZERO
	a.heading = Vector3.FORWARD
	a.velocity = Vector3(0.1, 0.0, 0.0)
	var b := Fish.new()
	parent.add_child(b)
	b.id = "boid_b"
	b.species = "glassdart"
	b.position = Vector3(0.8, 0.0, 0.0)
	b.heading = Vector3.FORWARD
	b.velocity = Vector3(0.1, 0.0, 0.0)
	MindBoidsBuffer.capture([a, b], 1)
	run()
	var ok: bool = MindBoidsBuffer.backend != "none" \
		and MindBoidsBuffer.neighbor_counts[0] >= 1 \
		and MindBoidsBuffer.neighbor_counts[1] >= 1
	if tree != null and is_instance_valid(parent):
		parent.queue_free()
	return ok
