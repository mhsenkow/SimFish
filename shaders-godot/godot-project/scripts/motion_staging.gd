class_name MotionStaging
extends RefCounted

# CREATURE_MOTION_700 Staging (171–192): make important motion unmistakable
# at pixel scale. Static helpers consulted from Fish / main / camera.


static var enabled: bool = true
static var silhouette_mode: bool = false  # #176: flat black fauna outline QA

# #175: at most a few big actions per screen region.
const BIG_EVENT_CAP: int = 3
const BIG_EVENT_RADIUS: float = 4.5
static var _big_events: Array[Dictionary] = []  # {pos, until_ms, kind}

# #187: tank-wide activity budget — keep at least one animal resting.
static var _active_count: int = 0
static var _rest_count: int = 0
static var _budget_frame: int = -1

# #180: per-actor rim boost while a hero event is live.
static var _rim_boosts: Dictionary = {}  # instance_id -> until_ms


static var _audio_booted: bool = false


static func reset() -> void:
	_big_events.clear()
	_active_count = 0
	_rest_count = 0
	_budget_frame = -1
	_rim_boosts.clear()
	silhouette_mode = false
	_audio_booted = false


static func boot_audio_bridge() -> void:
	# #189: gulp / dart / strike / startle mark the beat via AmbientAudio.
	if _audio_booted:
		return
	_audio_booted = true
	MotionEvents.subscribe(&"gulp", _on_motion_sfx)
	MotionEvents.subscribe(&"dart_started", _on_motion_sfx)
	MotionEvents.subscribe(&"strike", _on_motion_sfx)
	MotionEvents.subscribe(&"startled", _on_motion_sfx)


static func _on_motion_sfx(ev: Dictionary) -> void:
	var ml: MainLoop = Engine.get_main_loop()
	if not (ml is SceneTree):
		return
	var scene: Node = (ml as SceneTree).current_scene
	if scene == null:
		return
	var audio: Node = scene.get_node_or_null("AmbientAudio")
	if audio == null:
		return
	var kind: StringName = ev.get("kind", &"")
	var strength: float = float(ev.get("strength", 0.4))
	match kind:
		&"gulp":
			if audio.has_method("play_bubble_sfx"):
				audio.play_bubble_sfx(clampf(strength * 0.35, 0.08, 0.3))
		&"dart_started", &"startled":
			if audio.has_method("play_startle_sfx"):
				audio.play_startle_sfx(clampf(strength * 0.55, 0.2, 0.7))
		&"strike":
			if audio.has_method("play_eat_sfx"):
				audio.play_eat_sfx(clampf(strength * 0.4, 0.15, 0.55))


static func apply_silhouette(f: Fish) -> void:
	# #176: flat black fauna so pose reads by outline alone.
	if not silhouette_mode or f == null or f._bank_pivot == null:
		return
	for child in f._bank_pivot.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = child as MeshInstance3D
		if mi == null or not (mi.material_override is ShaderMaterial):
			continue
		var sm: ShaderMaterial = mi.material_override as ShaderMaterial
		if sm.get_shader_parameter("albedo") != null:
			sm.set_shader_parameter("albedo", Color(0, 0, 0))
		sm.set_shader_parameter("fauna_rim", 0.0)


static func legibility_scale(f: Fish, amp_units: float, cam: Camera3D = null,
		viewport_h: float = 576.0) -> float:
	# #171 / #359 / #368 / #369: key channels reach ≥2 px, capped, distance-mixed.
	if not enabled or f == null:
		return 1.0
	var ppu: float = 22.0  # ~576p at default framing (doc estimate)
	if cam != null:
		ppu = MotionLod.px_per_unit(cam, f.global_position, viewport_h)
	if ppu <= 1e-4:
		return 1.0
	# Default path is the cruise tail (#367 realism anchor) — no gain.
	# Callers that need key-channel lift pass through FishExaggeration.gain.
	return FishExaggeration.gain("cruise_tail_amp", amp_units, ppu,
		FishExaggeration.dance_blend_of(f), 2.0)


static func camera_relative_tail_boost(f: Fish, cam: Camera3D) -> Dictionary:
	# #172: when the lateral bend axis is foreshortened, lift caudal spread + heave.
	var out := {"spread": 0.0, "heave": 0.0, "amp": 1.0}
	if not enabled or f == null or cam == null:
		return out
	var to_cam: Vector3 = cam.global_position - f.global_position
	to_cam.y = 0.0
	if to_cam.length_squared() < 1e-4 or f.heading.length_squared() < 1e-4:
		return out
	var flat_h: Vector3 = Vector3(f.heading.x, 0.0, f.heading.z).normalized()
	var side: Vector3 = Vector3(-flat_h.z, 0.0, flat_h.x)
	var align: float = absf(side.normalized().dot(to_cam.normalized()))
	# align≈1 → bend axis points at camera → foreshortened.
	if align > 0.65:
		var t: float = smoothstep(0.65, 0.95, align)
		out["spread"] = t * 0.35
		out["heave"] = t * 0.08
		out["amp"] = lerpf(1.0, 0.72, t)  # quiet the invisible lateral amp
	return out


static func prefer_camera_broadside(f: Fish, partner: Node3D, cam: Camera3D) -> Vector3:
	# #173: when either flank faces the receiver, pick the camera-facing side.
	if not enabled or f == null or partner == null or cam == null:
		return Vector3.ZERO
	var to_p: Vector3 = partner.global_position - f.global_position
	to_p.y = 0.0
	if to_p.length_squared() < 1e-4:
		return Vector3.ZERO
	var right: Vector3 = Vector3(-to_p.z, 0.0, to_p.x).normalized()
	var left: Vector3 = -right
	var cam_dir: Vector3 = cam.global_position - f.global_position
	cam_dir.y = 0.0
	if cam_dir.length_squared() < 1e-4:
		return right
	cam_dir = cam_dir.normalized()
	return right if right.dot(cam_dir) >= left.dot(cam_dir) else left


static func begin_big_event(pos: Vector3, kind: StringName, duration_s: float = 1.2) -> bool:
	# #175: returns false if the region is already saturated.
	if not enabled:
		return true
	_prune_big_events()
	var n: int = 0
	for ev in _big_events:
		if (ev["pos"] as Vector3).distance_squared_to(pos) < BIG_EVENT_RADIUS * BIG_EVENT_RADIUS:
			n += 1
	if n >= BIG_EVENT_CAP:
		return false
	_big_events.append({
		"pos": pos,
		"until_ms": Time.get_ticks_msec() + int(duration_s * 1000.0),
		"kind": kind,
	})
	return true


static func region_busy(pos: Vector3) -> bool:
	if not enabled:
		return false
	_prune_big_events()
	var n: int = 0
	for ev in _big_events:
		if (ev["pos"] as Vector3).distance_squared_to(pos) < BIG_EVENT_RADIUS * BIG_EVENT_RADIUS:
			n += 1
	return n >= BIG_EVENT_CAP


static func yield_field(f: Fish, event_pos: Vector3, strength: float = 0.55) -> Vector3:
	# #174: non-participants drift away from a key event.
	if not enabled or f == null:
		return Vector3.ZERO
	var away: Vector3 = f.global_position - event_pos
	away.y *= 0.2
	if away.length_squared() < 0.25 or away.length_squared() > 36.0:
		return Vector3.ZERO
	return away.normalized() * strength


static func note_activity(is_resting: bool) -> void:
	# #187: counted once per process frame across the tank.
	var fr: int = Engine.get_process_frames()
	if fr != _budget_frame:
		_budget_frame = fr
		_active_count = 0
		_rest_count = 0
	if is_resting:
		_rest_count += 1
	else:
		_active_count += 1


static func should_force_rest() -> bool:
	# When everything is busy, ask one more animal to settle.
	if not enabled:
		return false
	return _rest_count < 1 and _active_count >= 6


static func light_actor(f: Fish, duration_s: float = 0.9) -> void:
	# #180: raise fauna_rim on this actor for the event.
	if not enabled or f == null:
		return
	_rim_boosts[f.get_instance_id()] = Time.get_ticks_msec() + int(duration_s * 1000.0)
	_apply_rim(f, VoxelMat.FAUNA_RIM * 1.35)


static func tick_rim(f: Fish) -> void:
	if f == null:
		return
	var id: int = f.get_instance_id()
	var until_v: Variant = _rim_boosts.get(id, 0)
	var until: int = int(until_v)
	if until <= 0:
		return
	if Time.get_ticks_msec() >= until:
		_rim_boosts.erase(id)
		_apply_rim(f, VoxelMat.FAUNA_RIM)


static func follow_lead_aim(aim: Vector3, heading: Vector3, lead_frac: float = 0.18) -> Vector3:
	# #178: offset the follow target ahead of travel.
	if heading.length_squared() < 1e-4:
		return aim
	return aim + heading.normalized() * (2.2 * lead_frac)


static func follow_deadzone_for_speed(base: float, burst: float, startle: float) -> float:
	# #179: widen deadzone briefly on dart/startle so the cam eases into the catch-up.
	var surge: float = maxf(burst, startle)
	if surge <= 0.05:
		return base
	return base * lerpf(1.0, 1.85, clampf(surge, 0.0, 1.0))


static func stagger_delay(f: Fish, base_s: float = 0.08) -> float:
	# #182: per-fish delay from reaction latency so sync starts don't broadcast.
	if f == null:
		return 0.0
	var seed_v: int = f.get_instance_id() & 1023
	var bold: float = 0.5
	if f.has_method("_boldness"):
		bold = clampf(f._boldness() / 1.8, 0.0, 1.0)
	# Bold fish react sooner.
	return base_s * lerpf(2.2, 0.35, bold) + float(seed_v % 17) * 0.006


static func curve_intent(f: Fish, goal: Vector3, horizon_s: float = 0.5) -> Vector3:
	# #183: bend the desired path toward the goal early so intent reads.
	if not enabled or f == null:
		return Vector3.ZERO
	var to: Vector3 = goal - f.global_position
	to.y *= 0.35
	if to.length_squared() < 0.04:
		return Vector3.ZERO
	var speed: float = maxf(f.speed, 0.15)
	var look_ahead: float = speed * horizon_s
	if to.length() > look_ahead * 3.0:
		# Still far — gentle curve.
		return to.normalized() * 0.22
	return to.normalized() * lerpf(0.55, 0.18, clampf(to.length() / maxf(look_ahead, 0.1), 0.0, 1.0))


static func rest_clearance_nudge(f: Fish, neighbors: Array, glass_half: Vector2) -> Vector3:
	# #185: push rest spots off glass edges and neighbour silhouettes.
	if not enabled or f == null or f.speed > 0.18:
		return Vector3.ZERO
	var nudge := Vector3.ZERO
	var margin: float = 0.85
	if absf(f.global_position.x) > glass_half.x - margin:
		nudge.x -= signf(f.global_position.x) * 0.35
	if absf(f.global_position.z) > glass_half.y - margin:
		nudge.z -= signf(f.global_position.z) * 0.35
	for n in neighbors:
		if not (n is Node3D) or n == f:
			continue
		var d: Vector3 = f.global_position - (n as Node3D).global_position
		d.y *= 0.3
		var d2: float = d.length_squared()
		if d2 < 0.55 and d2 > 1e-5:
			nudge += d.normalized() * 0.25
	return nudge


static func formation_drift(f: Fish, slot: Vector3, t: float) -> Vector3:
	# #186: slow drift so slots never settle into a lattice.
	if not enabled or f == null:
		return slot
	var seed_v: float = float(f.get_instance_id() & 255) * 0.021
	var drift := Vector3(
		sin(t * 0.11 + seed_v) * 0.35,
		sin(t * 0.07 + seed_v * 1.7) * 0.12,
		cos(t * 0.09 + seed_v * 0.6) * 0.35)
	return slot + drift


static func open_water_bias(f: Fish, plant_push: Vector3) -> Vector3:
	# #192: prefer open water for displays/feeding when behaviour allows.
	if not enabled or f == null:
		return Vector3.ZERO
	if f.current_mode == Fish.Mode.FLEE or f._startle_remaining > 0.05:
		return Vector3.ZERO  # escapes still go to cover
	if f.current_mode == Fish.Mode.COURT or f.current_mode == Fish.Mode.FORAGE \
			or f._courtship_flare:
		# Softly reject dense plant push so the show reads against the background.
		return -plant_push * 0.45
	return Vector3.ZERO


static func fry_trail_allowed(f: Fish) -> bool:
	# #190: only escapes and play chases, not every wander burst.
	if f == null or f.maturity != Fish.MATURITY_FRY:
		return false
	if f._startle_remaining > 0.05:
		return true
	# Play chase sets a short burst while Mode.CRUISE and another fry is near —
	# approximate via meta set by the play block.
	return bool(f.get_meta("_fry_play_chase", false))


static func hero_face_detail(tier: int) -> bool:
	# #191: macro / hero framing keeps face features; wide shots drop them.
	return MotionLod.has(tier, "face") or tier == MotionLod.Tier.HERO


static func plant_aabb(plant: Node) -> AABB:
	# Cheap crown box from canopy sphere / height — enough for LOS tests (#177).
	if plant == null or not is_instance_valid(plant):
		return AABB()
	var pos: Vector3 = (plant as Node3D).global_position if plant is Node3D else Vector3.ZERO
	var radius: float = 0.45
	var height: float = 1.2
	if plant.has_method("canopy_shadow_sphere"):
		var sph: Vector4 = plant.canopy_shadow_sphere()
		pos = Vector3(sph.x, sph.y, sph.z)
		radius = maxf(float(sph.w), 0.2)
		height = maxf(radius * 1.6, 0.6)
	elif plant.get("current_height") != null:
		var vs: float = float(plant.get("VOXEL_SIZE") if plant.get("VOXEL_SIZE") != null else 0.12)
		height = maxf(float(plant.current_height) * vs, 0.5)
		var bio: float = float(plant.call("biomass")) if plant.has_method("biomass") else 4.0
		radius = clampf(sqrt(maxf(bio, 1.0)) * vs * 0.3, 0.2, 1.0)
	return AABB(pos - Vector3(radius, height * 0.55, radius), Vector3(radius * 2.0, height, radius * 2.0))


static func ray_hits_aabb(origin: Vector3, dir: Vector3, box: AABB, max_dist: float) -> bool:
	# Slab test. Returns true if the segment origin→origin+dir*max_dist hits box.
	if box.size.length_squared() < 1e-6 or dir.length_squared() < 1e-8:
		return false
	var inv_x: float = 1e8 if absf(dir.x) <= 1e-8 else 1.0 / dir.x
	var inv_y: float = 1e8 if absf(dir.y) <= 1e-8 else 1.0 / dir.y
	var inv_z: float = 1e8 if absf(dir.z) <= 1e-8 else 1.0 / dir.z
	var inv := Vector3(inv_x, inv_y, inv_z)
	var t0: Vector3 = (box.position - origin) * inv
	var t1: Vector3 = (box.position + box.size - origin) * inv
	var tmin: float = maxf(maxf(minf(t0.x, t1.x), minf(t0.y, t1.y)), minf(t0.z, t1.z))
	var tmax: float = minf(minf(maxf(t0.x, t1.x), maxf(t0.y, t1.y)), maxf(t0.z, t1.z))
	if tmax < 0.0 or tmin > tmax:
		return false
	var hit_t: float = tmin if tmin > 0.0 else tmax
	return hit_t >= 0.0 and hit_t <= max_dist


static func clear_to_camera(world_pos: Vector3, cam: Camera3D, plants: Array,
		max_plants: int = 12) -> bool:
	# #177: cheap LOS — true when no nearby plant AABB blocks the camera ray.
	if cam == null:
		return true
	var to: Vector3 = world_pos - cam.global_position
	var dist: float = to.length()
	if dist < 0.05:
		return true
	var dir: Vector3 = to / dist
	var checked: int = 0
	for p in plants:
		if checked >= max_plants:
			break
		if not is_instance_valid(p):
			continue
		var box: AABB = plant_aabb(p)
		if box.size.length_squared() < 1e-6:
			continue
		# Skip plants whose crown is far from the ray corridor.
		var closest: Vector3 = box.get_center()
		var lateral: float = (closest - cam.global_position).cross(dir).length()
		if lateral > maxf(box.size.x, box.size.z) * 0.75 + 0.4:
			continue
		checked += 1
		# Ignore the plant if the site itself sits inside its crown (sleeping in it).
		if box.has_point(world_pos):
			continue
		if ray_hits_aabb(cam.global_position, dir, box, dist - 0.15):
			return false
	return true


static func prefer_visible_site(site: Vector3, cam: Camera3D, plants: Array,
		radius: float = 0.85) -> Vector3:
	# Nudge a court/spawn/rest site toward a camera-clear offset if blocked.
	if cam == null or clear_to_camera(site, cam, plants):
		return site
	var to_cam: Vector3 = cam.global_position - site
	to_cam.y *= 0.35
	if to_cam.length_squared() < 1e-4:
		return site
	var toward: Vector3 = to_cam.normalized()
	for step in [0.55, 0.9, 1.25]:
		var cand: Vector3 = site + toward * (radius * step)
		if clear_to_camera(cand, cam, plants):
			return cand
	# Lateral orbit around the blocked site.
	var side: Vector3 = toward.cross(Vector3.UP)
	if side.length_squared() < 1e-4:
		side = Vector3.RIGHT
	side = side.normalized()
	for s in [-1.0, 1.0]:
		var cand2: Vector3 = site + side * (radius * s)
		if clear_to_camera(cand2, cam, plants):
			return cand2
	return site


static func contact_shadow_point(node: Node3D, bed_y: float, radius: float) -> Vector4:
	# #181: tight soft blob pinned just above the bed under a contact animal.
	if node == null:
		return Vector4.ZERO
	var h: float = node.global_position.y - bed_y
	if h < -0.2 or h > 0.85:
		return Vector4.ZERO
	var y: float = bed_y + 0.06
	var r: float = clampf(radius, 0.12, 0.55)
	# Encode contact priority as a slightly larger w so the disc reads when
	# competing with mid-water fish shadows (shader uses w as base radius).
	return Vector4(node.global_position.x, y, node.global_position.z, r * 1.05)


static func _prune_big_events() -> void:
	var now: int = Time.get_ticks_msec()
	for i in range(_big_events.size() - 1, -1, -1):
		if int(_big_events[i]["until_ms"]) <= now:
			_big_events.remove_at(i)


static func _apply_rim(f: Fish, rim: float) -> void:
	if f._bank_pivot == null:
		return
	for child in f._bank_pivot.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = child as MeshInstance3D
		if mi == null or not (mi.material_override is ShaderMaterial):
			continue
		var sm: ShaderMaterial = mi.material_override as ShaderMaterial
		if sm.get_shader_parameter("fauna_rim") != null:
			sm.set_shader_parameter("fauna_rim", rim)
