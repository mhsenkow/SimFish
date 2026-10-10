extends SceneTree

const Fixture = preload("res://scripts/schooling_fixture_test_stub.gd")
const BASELINE: String = "res://dev/fixtures/schooling_cpu_baseline.json"

func _initialize() -> void:
	var t := TestSupport.Suite.new("smoke_schooling_force_equivalence")
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASELINE))
	for count in [16, 64, 128, 256]:
		Fixture.prepare(count)
		MindBoidsCompute._cpu_dispatch(count)
		var got: Array = Fixture.snapshot()
		var want: Array = expected[str(count)]
		t.equals(got.size(), want.size(), "fixture fish count %d" % count)
		for i in count:
			for k in 9:
				t.approx(got[i][k], want[i][k], "force %d/%d/%d" % [count, i, k], 0.00001)
			for k in range(9, 18):
				t.equals(int(got[i][k]), int(want[i][k]), "count, speed or neighbor %d/%d/%d" % [count, i, k])
		Fixture.release()
	_check_selector(t)
	quit(t.finish())

func _check_selector(t: TestSupport.Suite) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 314159
	for stream in 32:
		var reference := PackedFloat32Array()
		reference.resize(MindBoidsBuffer.N_TOPO)
		var actual := reference.duplicate()
		var ref_indices := PackedInt32Array()
		ref_indices.resize(MindBoidsBuffer.N_TOPO)
		var indices := ref_indices.duplicate()
		var selection := Vector2i.ZERO
		var count: int = 0
		for candidate in 160:
			# Repeated ties, sub-float32 differences and partner-weighted distances.
			var distance: float = rng.randi_range(0, 36) + (1e-8 if candidate % 7 == 0 else 0.0)
			if candidate % 4 == 0:
				distance *= 0.72
			if count < MindBoidsBuffer.N_TOPO:
				reference[count] = distance
				ref_indices[count] = candidate
				count += 1
			else:
				var worst: int = 0
				for k in range(1, MindBoidsBuffer.N_TOPO):
					if reference[k] > reference[worst]:
						worst = k
				if distance < reference[worst]:
					reference[worst] = distance
					ref_indices[worst] = candidate
			selection = MindBoidsCompute._insert_topo_cached(actual, indices, selection, distance, candidate)
			t.check(selection.x == count and actual == reference and indices == ref_indices,
				"cached selection preserves ties and slots %d/%d" % [stream, candidate])
