# Procedural 3D meshes for the aquascape object library (first-pass shapes).
class_name AquascapeObjectMeshes
extends RefCounted

static func footprint(id: String, params: Dictionary = {}) -> Vector3:
	match id:
		"castle":
			var h: int = clampi(int(params.get("height", 7)), 4, 10)
			return Vector3(1.8, float(h) * 0.38 + 0.35, 1.8)
		"shipwreck":
			return Vector3(2.4, 0.85, 1.2)
		"treasure":
			return Vector3(0.75, 0.55, 0.55)
		"arch", "cave_mouth":
			return Vector3(1.6, 1.35, 0.55)
		"torii":
			return Vector3(1.7, 1.45, 0.35)
		"ruin_column":
			return Vector3(0.55, 1.55, 0.55)
		"pebble":
			return Vector3(0.55, 0.28, 0.55)
		"boulder":
			return Vector3(1.05, 0.75, 1.05)
		"amphora":
			return Vector3(0.55, 1.05, 0.55)
		"crystal_spire":
			return Vector3(0.45, 1.65, 0.45)
		"anchor":
			return Vector3(0.85, 0.95, 0.85)
		"pumpkin", "gift_box":
			return Vector3(0.75, 0.75, 0.75)
		"blossom_tree":
			return Vector3(0.95, 1.15, 0.95)
		_:
			return Vector3(0.8, 0.8, 0.8)


static func spawn(id: String, params: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "AquaObject_%s" % id
	match id:
		"boulder":
			_boulder(root)
		"pebble":
			_pebble(root)
		"arch":
			_arch(root)
		"torii":
			_torii(root)
		"castle":
			_castle(root, params)
		"treasure":
			_treasure(root)
		"shipwreck":
			_shipwreck(root)
		"ruin_column":
			_ruin_column(root)
		"cave_mouth":
			_cave_mouth(root)
		"amphora":
			_amphora(root)
		"crystal_spire":
			_crystal_spire(root)
		"anchor":
			_anchor(root)
		"pumpkin":
			_pumpkin(root)
		"gift_box":
			_gift_box(root)
		"blossom_tree":
			_blossom_tree(root)
		_:
			_box(root, Vector3(0.6, 0.6, 0.6), Vector3(0, 0.3, 0), Color8(120, 115, 125))
	return root


static func _mat(color: Color) -> Material:
	return VoxelMat.make(color)


static func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _boulder(parent: Node3D) -> void:
	var c := Color8(100, 95, 105)
	_box(parent, Vector3(0.95, 0.55, 0.85), Vector3(0, 0.28, 0), c)
	_box(parent, Vector3(0.65, 0.45, 0.6), Vector3(0.22, 0.48, 0.12), c.lightened(0.06))
	_box(parent, Vector3(0.5, 0.35, 0.45), Vector3(-0.18, 0.42, -0.1), c.darkened(0.05))


static func _pebble(parent: Node3D) -> void:
	var c := Color8(115, 110, 105)
	_box(parent, Vector3(0.32, 0.18, 0.28), Vector3(0, 0.09, 0), c)
	_box(parent, Vector3(0.22, 0.14, 0.2), Vector3(0.14, 0.06, 0.08), c.darkened(0.06))
	_box(parent, Vector3(0.18, 0.12, 0.16), Vector3(-0.1, 0.05, -0.06), c.lightened(0.04))


static func _arch(parent: Node3D) -> void:
	var rock := Color8(110, 105, 115)
	_box(parent, Vector3(0.35, 1.15, 0.45), Vector3(-0.62, 0.58, 0), rock)
	_box(parent, Vector3(0.35, 1.15, 0.45), Vector3(0.62, 0.58, 0), rock)
	_box(parent, Vector3(1.45, 0.28, 0.45), Vector3(0, 1.08, 0), rock.lightened(0.05))


static func _torii(parent: Node3D) -> void:
	var red := Color8(180, 50, 45)
	var cap := Color8(50, 35, 25)
	_box(parent, Vector3(0.22, 1.15, 0.22), Vector3(-0.72, 0.58, 0), red)
	_box(parent, Vector3(0.22, 1.15, 0.22), Vector3(0.72, 0.58, 0), red)
	_box(parent, Vector3(1.65, 0.16, 0.28), Vector3(0, 1.08, 0), red)
	_box(parent, Vector3(0.28, 0.12, 0.28), Vector3(-0.72, 1.18, 0), cap)
	_box(parent, Vector3(0.28, 0.12, 0.28), Vector3(0.72, 1.18, 0), cap)


static func _castle(parent: Node3D, params: Dictionary) -> void:
	var towers: int = clampi(int(params.get("towers", 4)), 2, 6)
	var height: int = clampi(int(params.get("height", 7)), 4, 10)
	var stone := Color8(130, 125, 135)
	var dark := Color8(75, 70, 78)
	var gold := Color8(220, 190, 90)
	var wall_h: float = minf(1.35, float(height) * 0.18 + 0.55)
	_box(parent, Vector3(1.55, wall_h, 1.55), Vector3(0, wall_h * 0.5, 0), stone)
	_box(parent, Vector3(1.35, 0.12, 1.35), Vector3(0, 0.06, 0), dark)
	var tower_positions: Array = []
	if towers <= 4:
		tower_positions = [
			Vector3(-0.72, 0, -0.72), Vector3(0.72, 0, -0.72),
			Vector3(-0.72, 0, 0.72), Vector3(0.72, 0, 0.72),
		]
	else:
		for a in range(towers):
			var ang: float = TAU * float(a) / float(towers)
			tower_positions.append(Vector3(cos(ang) * 0.72, 0, sin(ang) * 0.72))
	var tower_h: float = float(height) * 0.38
	for tp in tower_positions:
		_box(parent, Vector3(0.28, tower_h, 0.28), Vector3(tp.x, tower_h * 0.5 + wall_h * 0.15, tp.z), stone)
		_box(parent, Vector3(0.22, 0.18, 0.22), Vector3(tp.x, tower_h + wall_h * 0.15 + 0.09, tp.z), gold)


static func _treasure(parent: Node3D) -> void:
	var wood := Color8(100, 70, 40)
	var gold := Color8(230, 200, 80)
	_box(parent, Vector3(0.62, 0.32, 0.48), Vector3(0, 0.16, 0), wood)
	_box(parent, Vector3(0.68, 0.14, 0.52), Vector3(0, 0.39, 0), wood.darkened(0.08))
	_box(parent, Vector3(0.28, 0.12, 0.22), Vector3(0, 0.48, 0), gold)


static func _shipwreck(parent: Node3D) -> void:
	var hull := Color8(95, 65, 35)
	var deck := Color8(120, 85, 50)
	_box(parent, Vector3(2.1, 0.32, 0.75), Vector3(0, 0.16, 0), hull)
	_box(parent, Vector3(1.4, 0.22, 0.55), Vector3(-0.35, 0.38, 0.05), deck)
	_box(parent, Vector3(0.55, 0.45, 0.35), Vector3(0.85, 0.28, -0.05), hull.darkened(0.08))
	_box(parent, Vector3(0.35, 0.65, 0.25), Vector3(-1.0, 0.42, 0.08), hull)


static func _ruin_column(parent: Node3D) -> void:
	var stone := Color8(165, 160, 150)
	_box(parent, Vector3(0.42, 1.25, 0.42), Vector3(0, 0.62, 0), stone)
	_box(parent, Vector3(0.48, 0.18, 0.48), Vector3(0, 1.34, 0), stone.lightened(0.08))
	_box(parent, Vector3(0.28, 0.35, 0.22), Vector3(0.22, 0.72, 0), stone.darkened(0.12))


static func _cave_mouth(parent: Node3D) -> void:
	var rock := Color8(95, 90, 100)
	var dark := Color8(45, 40, 48)
	_box(parent, Vector3(0.38, 1.05, 0.48), Vector3(-0.62, 0.52, 0), rock)
	_box(parent, Vector3(0.38, 1.05, 0.48), Vector3(0.62, 0.52, 0), rock)
	_box(parent, Vector3(1.35, 0.24, 0.48), Vector3(0, 0.98, 0), rock)
	_box(parent, Vector3(0.55, 0.55, 0.32), Vector3(0, 0.42, 0.02), dark)


static func _amphora(parent: Node3D) -> void:
	var clay := Color8(140, 100, 70)
	_box(parent, Vector3(0.48, 0.22, 0.48), Vector3(0, 0.11, 0), clay.darkened(0.06))
	_box(parent, Vector3(0.38, 0.35, 0.38), Vector3(0, 0.38, 0), clay)
	_box(parent, Vector3(0.28, 0.28, 0.28), Vector3(0, 0.68, 0), clay.lightened(0.05))
	_box(parent, Vector3(0.18, 0.18, 0.18), Vector3(0, 0.95, 0), clay.darkened(0.08))


static func _crystal_spire(parent: Node3D) -> void:
	var base := Color8(110, 80, 160)
	var tip := Color8(180, 140, 255)
	_box(parent, Vector3(0.32, 0.45, 0.32), Vector3(0, 0.22, 0), base)
	_box(parent, Vector3(0.24, 0.55, 0.24), Vector3(0, 0.68, 0), base.lightened(0.08))
	_box(parent, Vector3(0.16, 0.45, 0.16), Vector3(0, 1.12, 0), tip)
	_box(parent, Vector3(0.12, 0.22, 0.12), Vector3(0, 1.48, 0), tip.lightened(0.12))


static func _anchor(parent: Node3D) -> void:
	var iron := Color8(90, 95, 105)
	var rust := Color8(120, 70, 45)
	_box(parent, Vector3(0.18, 0.65, 0.18), Vector3(0, 0.32, 0), iron)
	_box(parent, Vector3(0.72, 0.14, 0.14), Vector3(0, 0.12, 0), rust)
	_box(parent, Vector3(0.14, 0.14, 0.72), Vector3(0, 0.12, 0.28), iron)
	_box(parent, Vector3(0.22, 0.18, 0.22), Vector3(0, 0.72, 0), rust.darkened(0.05))


static func _pumpkin(parent: Node3D) -> void:
	var orange := Color8(200, 110, 40)
	var stem := Color8(80, 120, 50)
	_box(parent, Vector3(0.62, 0.52, 0.62), Vector3(0, 0.26, 0), orange)
	_box(parent, Vector3(0.14, 0.18, 0.14), Vector3(0, 0.58, 0), stem)


static func _gift_box(parent: Node3D) -> void:
	var wrap_color := Color8(180, 50, 60)
	var ribbon := Color8(220, 210, 80)
	_box(parent, Vector3(0.62, 0.52, 0.62), Vector3(0, 0.26, 0), wrap_color)
	_box(parent, Vector3(0.68, 0.08, 0.12), Vector3(0, 0.48, 0), ribbon)
	_box(parent, Vector3(0.12, 0.48, 0.12), Vector3(0, 0.28, 0), ribbon)


static func _blossom_tree(parent: Node3D) -> void:
	var trunk := Color8(78, 52, 32)
	var bloom := Color8(240, 180, 210)
	_box(parent, Vector3(0.16, 0.55, 0.16), Vector3(0, 0.28, 0), trunk)
	_box(parent, Vector3(0.55, 0.35, 0.55), Vector3(0, 0.72, 0), bloom)
	_box(parent, Vector3(0.32, 0.22, 0.32), Vector3(0.22, 0.88, 0.08), bloom.lightened(0.06))
