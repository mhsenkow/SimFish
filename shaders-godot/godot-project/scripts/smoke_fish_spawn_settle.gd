extends SceneTree

const SpawnSettle = preload("res://scripts/fish_spawn_settle.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	var host := Node3D.new()
	root.add_child(host)

	# Pure smoothstep envelope: bounded, monotonic, and exactly established.
	var previous: float = -1.0
	for i in 13:
		var remaining: float = SpawnSettle.FRESH_DURATION * (1.0 - float(i) / 12.0)
		var value: float = SpawnSettle.factor(remaining, SpawnSettle.FRESH_DURATION)
		_assert(failed, value >= previous, "settle factor monotonic at step %d" % i)
		_assert(failed, value >= 0.0 and value <= 1.0, "settle factor bounded")
		previous = value
	_assert(failed, SpawnSettle.factor(0.0, SpawnSettle.FRESH_DURATION) == 1.0,
		"established factor exactly one")

	# Fresh production-shaped setup anchors its territory and hydro hover to
	# the final spawn depth, while retaining the species preferred layer.
	var fresh := Fish.new()
	host.add_child(fresh)
	fresh.global_position = Vector3(1.0, 4.2, -0.5)
	fresh.init_genome({"species": "settle_test", "preferred_y": 2.4,
		"swim_pattern": "cruise", "max_speed": 1.4})
	_assert(failed, absf(fresh.home_y - 4.2) < 0.001, "fresh home matches spawn Y")
	_assert(failed, absf(fresh._hover_depth - 4.2) < 0.001, "fresh hover matches spawn Y")
	_assert(failed, absf(fresh.preferred_y - 2.4) < 0.001, "species depth retained")

	# A wall-safe supplied heading survives variation and facing is synced.
	var safe_heading := Vector3(0.8, 0.0, -0.2).normalized()
	fresh.set_spawn_heading(safe_heading)
	var seeded := RandomNumberGenerator.new()
	seeded.seed = 1234
	fresh.apply_spawn_variation(seeded)
	_assert(failed, fresh.heading.distance_to(safe_heading) < 0.001,
		"spawner heading preserved")
	_assert(failed, -fresh.global_basis.z.normalized().dot(safe_heading) > 0.999,
		"facing synced to final heading")
	_assert(failed, fresh.target_velocity.length() > 0.01,
		"initial propulsion intent avoids freeze")

	var other := Fish.new()
	host.add_child(other)
	var seeded_other := RandomNumberGenerator.new()
	seeded_other.seed = 4321
	other.apply_spawn_variation(seeded_other)
	_assert(failed, absf(fresh._breath_phase - other._breath_phase) > 0.001,
		"breath oscillators desynchronized")
	_assert(failed, absf(fresh._buoy_bob_t - other._buoy_bob_t) > 0.001,
		"buoy oscillators desynchronized")

	# Fry inherit their mother's layer first and retain a gradual species target.
	var fry := Fish.new()
	host.add_child(fry)
	fry.preferred_y = 2.1
	fry.global_position.y = 4.0
	fry.begin_fry_spawn(3.95, Vector3.RIGHT)
	_assert(failed, absf(fry.home_y - 3.95) < 0.001, "fry inherits mother depth")
	_assert(failed, absf(fry._spawn_depth_target_y - 2.1) < 0.001,
		"fry keeps species migration target")

	# Breath + buoy integration should agree closely at common frame rates.
	var d30: float = _integrated_vertical_displacement(30)
	var d60: float = _integrated_vertical_displacement(60)
	var d120: float = _integrated_vertical_displacement(120)
	_assert(failed, absf(d30 - d60) < 0.003 and absf(d60 - d120) < 0.003,
		"30/60/120 FPS vertical displacement agrees: %.5f %.5f %.5f" % [d30, d60, d120])
	var probe := Fish.new()
	probe._breath_phase = 0.73
	probe._breath_load = 1.2
	var first_delta: float = probe._breath_motion_delta(1.0 / 30.0)
	_assert(failed, absf(first_delta) < 0.02, "initial frame delta bounded")

	# Save/restore preserves hover and oscillator state, then uses the shorter
	# restore envelope. Legacy saves safely anchor hover at their saved depth.
	fresh._hover_depth = 4.15
	fresh._spawn_settle_remaining = 0.31
	var saved: Dictionary = fresh.to_save_dict()
	var restored := Fish.new()
	host.add_child(restored)
	restored.global_position = fresh.global_position
	restored.apply_save_dict(saved)
	_assert(failed, absf(restored._hover_depth - 4.15) < 0.001, "hover depth restores")
	_assert(failed, restored._spawn_settle_duration == SpawnSettle.RESTORE_DURATION,
		"restore uses short envelope")
	_assert(failed, restored._spawn_settle_remaining > 0.0, "settle progress restores")
	var legacy: Dictionary = saved.duplicate(true)
	for key in ["hover_depth", "buoy_bob_t", "breath_phase", "breath_y_offset",
			"spawn_settle_remaining", "spawn_settle_duration", "spawn_depth_target_y"]:
		legacy.erase(key)
	var legacy_fish := Fish.new()
	host.add_child(legacy_fish)
	legacy_fish.global_position = fresh.global_position
	legacy_fish.apply_save_dict(legacy)
	_assert(failed, absf(legacy_fish._hover_depth - legacy_fish.global_position.y) < 0.001,
		"legacy hover defaults to saved depth")
	_assert(failed, legacy_fish.spawn_settle_factor() < 1.0, "legacy restore eases in")

	fresh._spawn_settle_remaining = 0.0
	_assert(failed, fresh.spawn_settle_factor() == 1.0,
		"normal full behavior restored after envelope")

	if failed.is_empty():
		print("SMOKE_FISH_SPAWN_SETTLE_OK")
		quit(0)
	else:
		for message in failed:
			push_error(message)
		print("SMOKE_FISH_SPAWN_SETTLE_FAIL count=%d" % failed.size())
		quit(1)


func _integrated_vertical_displacement(fps: int) -> float:
	var fish := Fish.new()
	fish._breath_phase = 0.217
	fish._breath_load = 1.15
	fish.max_speed = 1.4
	var profile: Dictionary = Hydrodynamics.profile_for_locomotion("subcarangiform", 0.4)
	var bob_t: float = 1.31
	var displacement: float = 0.0
	var dt: float = 1.0 / float(fps)
	var steps: int = int(round(0.9 * float(fps)))
	for i in steps:
		var remaining: float = maxf(0.0, SpawnSettle.FRESH_DURATION - float(i + 1) * dt)
		var settle: float = SpawnSettle.factor(remaining, SpawnSettle.FRESH_DURATION)
		displacement += fish._breath_motion_delta(dt) * settle
		var buoy: Dictionary = Hydrodynamics.buoyancy_step(
			3.0, 3.0, 0.2, 0.4, dt, bob_t, profile)
		displacement += float(buoy.y_delta) * settle
		bob_t = float(buoy.bob_t)
	fish.free()
	return displacement


func _assert(failed: Array[String], condition: bool, message: String) -> void:
	if not condition:
		failed.append(message)
