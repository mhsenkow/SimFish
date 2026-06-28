# Pre-authored voxel objects + palette swatches for the build browser.
# AQUASCAPING_CRAFT #41–50, #75.
class_name AquascapeObjectLibrary
extends RefCounted

const CATEGORIES: Array[String] = ["Natural", "Ornaments", "Themed", "Starter"]

const BUILD_PALETTE: Array[Color] = [
	Color8(85, 85, 96), Color8(120, 120, 130), Color8(105, 100, 92),
	Color8(78, 52, 32), Color8(58, 38, 22), Color8(120, 85, 56),
	Color8(225, 215, 185), Color8(180, 160, 120), Color8(200, 200, 210),
	Color8(220, 180, 80), Color8(180, 100, 60), Color8(100, 140, 180),
	Color8(140, 90, 70), Color8(60, 60, 70), Color8(255, 220, 140),
	Color8(100, 200, 220),
]

static func all_objects() -> Array[Dictionary]:
	_ensure_objects()
	var out: Array[Dictionary] = []
	for o in _OBJECTS:
		out.append(o.duplicate(true))
	return out


static func get_object(id: String) -> Dictionary:
	_ensure_objects()
	for o in _OBJECTS:
		if String(o.get("id", "")) == id:
			return o.duplicate(true)
	return {}


static func voxels_for(id: String, params: Dictionary = {}) -> Array:
	if id == "castle" and not params.is_empty():
		return _castle_voxels_parametric(params)
	var o: Dictionary = get_object(id)
	return o.get("voxels", [])


static func list_by_category(cat: String) -> Array[Dictionary]:
	_ensure_objects()
	var out: Array[Dictionary] = []
	for o in _OBJECTS:
		if String(o.get("category", "")) == cat:
			out.append(o.duplicate(true))
	return out


static func themed_kit_ids() -> Array[String]:
	return ["zen", "fantasy", "ruins", "reef"]


static func themed_kit_objects(kit_id: String) -> Array[String]:
	match kit_id:
		"zen":
			return ["torii", "pebble", "arch"]
		"fantasy":
			return ["castle", "crystal_spire", "treasure"]
		"ruins":
			return ["ruin_column", "cave_mouth", "amphora"]
		"reef":
			return ["shipwreck", "treasure", "anchor"]
	return []


static func _v(ix: int, iy: int, iz: int, color: Color, finish: String = "matte") -> Dictionary:
	return {"offset_i": Vector3i(ix, iy, iz), "color": color, "finish": finish}


static func _castle_voxels() -> Array:
	var stone := Color8(130, 125, 135)
	var dark := Color8(75, 70, 78)
	var gold := Color8(220, 190, 90)
	var v: Array = []
	for x in range(-2, 3):
		for z in range(-2, 3):
			for y in range(0, 4):
				if absi(x) == 2 or absi(z) == 2 or y == 0:
					v.append(_v(x, y, z, stone if y > 0 else dark))
	for tx in [-2, 2]:
		for tz in [-2, 2]:
			for y in range(4, 7):
				v.append(_v(tx, y, tz, stone))
			v.append(_v(tx, 7, tz, gold, "glow"))
	v.append(_v(0, 1, 2, Color8(40, 35, 45), "glass"))
	return v


static func _castle_voxels_parametric(params: Dictionary) -> Array:
	var towers: int = clampi(int(params.get("towers", 4)), 2, 6)
	var height: int = clampi(int(params.get("height", 7)), 4, 10)
	var stone := Color8(130, 125, 135)
	var dark := Color8(75, 70, 78)
	var gold := Color8(220, 190, 90)
	var v: Array = []
	for x in range(-2, 3):
		for z in range(-2, 3):
			for y in range(0, mini(4, height - 2)):
				if absi(x) == 2 or absi(z) == 2 or y == 0:
					v.append(_v(x, y, z, stone if y > 0 else dark))
	var tower_positions: Array = []
	if towers <= 4:
		tower_positions = [Vector3i(-2, 0, -2), Vector3i(2, 0, -2), Vector3i(-2, 0, 2), Vector3i(2, 0, 2)]
	else:
		for a in range(towers):
			var ang: float = TAU * float(a) / float(towers)
			tower_positions.append(Vector3i(int(round(cos(ang) * 2.0)), 0, int(round(sin(ang) * 2.0))))
	for tp in tower_positions:
		for y in range(4, height):
			v.append(_v(tp.x, y, tp.z, stone))
		v.append(_v(tp.x, height, tp.z, gold, "glow"))
	return v


static func _shipwreck_voxels() -> Array:
	var hull := Color8(95, 65, 35)
	var deck := Color8(120, 85, 50)
	var v: Array = []
	for x in range(-3, 4):
		v.append(_v(x, 0, 0, hull))
		v.append(_v(x, 1, 0, deck if x % 2 == 0 else hull))
	for z in range(1, 3):
		for x in range(-2, 3):
			v.append(_v(x, 0, z, hull))
	v.append(_v(-3, 2, 0, hull))
	v.append(_v(3, 1, 1, hull))
	return v


static func _arch_voxels() -> Array:
	var rock := Color8(110, 105, 115)
	var v: Array = []
	for y in range(0, 5):
		v.append(_v(-2, y, 0, rock))
		v.append(_v(2, y, 0, rock))
	for x in range(-1, 2):
		v.append(_v(x, 4, 0, rock))
	return v


static func _treasure_voxels() -> Array:
	var wood := Color8(100, 70, 40)
	var gold := Color8(230, 200, 80)
	return [
		_v(0, 0, 0, wood), _v(-1, 0, 0, wood), _v(1, 0, 0, wood),
		_v(0, 0, -1, wood), _v(0, 0, 1, wood),
		_v(0, 1, 0, gold, "metal"), _v(0, 2, 0, gold, "glow"),
	]


static func _torii_voxels() -> Array:
	var red := Color8(180, 50, 45)
	var dark := Color8(50, 35, 25)
	var v: Array = []
	for y in range(0, 4):
		v.append(_v(-2, y, 0, red))
		v.append(_v(2, y, 0, red))
	v.append(_v(-2, 4, 0, dark))
	v.append(_v(2, 4, 0, dark))
	for x in range(-3, 4):
		v.append(_v(x, 4, 0, red))
	return v


static func _ruin_column_voxels() -> Array:
	var stone := Color8(165, 160, 150)
	var v: Array = []
	for y in range(0, 5):
		v.append(_v(0, y, 0, stone))
	v.append(_v(0, 5, 0, stone.lightened(0.1)))
	v.append(_v(1, 3, 0, stone.darkened(0.15)))
	return v


static func _pebble_voxels() -> Array:
	var c := Color8(115, 110, 105)
	return [_v(0, 0, 0, c), _v(1, 0, 0, c.darkened(0.1)), _v(0, 0, 1, c.lightened(0.05))]


static func _boulder_voxels() -> Array:
	var c := Color8(100, 95, 105)
	var v: Array = []
	for x in range(-1, 2):
		for z in range(-1, 2):
			for y in range(0, 2):
				if absi(x) + absi(z) + y < 3:
					v.append(_v(x, y, z, c if y == 0 else c.lightened(0.08)))
	return v


static func _cave_mouth_voxels() -> Array:
	var rock := Color8(95, 90, 100)
	var dark := Color8(45, 40, 48)
	var v: Array = []
	for y in range(0, 4):
		v.append(_v(-2, y, 0, rock))
		v.append(_v(2, y, 0, rock))
	for x in range(-1, 2):
		v.append(_v(x, 4, 0, rock))
		v.append(_v(x, 0, 0, dark, "glass"))
	return v


static func _amphora_voxels() -> Array:
	var clay := Color8(140, 100, 70)
	return [
		_v(0, 0, 0, clay), _v(-1, 0, 0, clay), _v(1, 0, 0, clay),
		_v(0, 1, 0, clay.lightened(0.05)), _v(0, 2, 0, clay),
		_v(0, 3, 0, clay.darkened(0.1)),
	]


static func _crystal_spire_voxels() -> Array:
	var base := Color8(110, 80, 160)
	var tip := Color8(180, 140, 255)
	var v: Array = []
	for y in range(0, 5):
		v.append(_v(0, y, 0, base.lightened(float(y) * 0.06)))
	v.append(_v(0, 5, 0, tip, "glow"))
	v.append(_v(1, 2, 0, tip, "glass"))
	return v


static func _anchor_voxels() -> Array:
	var iron := Color8(90, 95, 105)
	var rust := Color8(120, 70, 45)
	return [
		_v(0, 0, 0, iron), _v(0, 1, 0, iron), _v(0, 2, 0, rust),
		_v(-1, 0, 0, rust), _v(1, 0, 0, rust), _v(0, 0, -1, iron),
	]


static func _seasonal_pumpkin_voxels() -> Array:
	var orange := Color8(200, 110, 40)
	var stem := Color8(80, 120, 50)
	return [
		_v(0, 0, 0, orange), _v(-1, 0, 0, orange), _v(1, 0, 0, orange),
		_v(0, 0, -1, orange), _v(0, 0, 1, orange), _v(0, 1, 0, stem),
	]


static func _seasonal_gift_voxels() -> Array:
	var gift_wrap := Color8(180, 50, 60)
	var ribbon := Color8(220, 210, 80)
	return [
		_v(0, 0, 0, gift_wrap), _v(-1, 0, 0, gift_wrap), _v(1, 0, 0, gift_wrap),
		_v(0, 1, 0, gift_wrap), _v(0, 0, 0, ribbon, "glow"),
	]


static func _seasonal_blossom_voxels() -> Array:
	var trunk := Color8(78, 52, 32)
	var bloom := Color8(240, 180, 210)
	return [
		_v(0, 0, 0, trunk), _v(0, 1, 0, trunk), _v(-1, 2, 0, bloom),
		_v(1, 2, 0, bloom), _v(0, 2, 1, bloom),
	]


static var _OBJECTS: Array[Dictionary] = []


static func _ensure_objects() -> void:
	if not _OBJECTS.is_empty():
		return
	_OBJECTS = [
	{
		"id": "castle", "name": "Stone Castle", "category": "Ornaments", "icon": "🏰",
		"description": "Towers, walls, and a golden keep — classic aquarium kitsch.",
		"voxels": _castle_voxels(),
	},
	{
		"id": "shipwreck", "name": "Shipwreck", "category": "Ornaments", "icon": "🚢",
		"description": "Broken hull with listing deck — fish love the hidey holes.",
		"voxels": _shipwreck_voxels(),
	},
	{
		"id": "treasure", "name": "Treasure Chest", "category": "Ornaments", "icon": "💎",
		"description": "Open chest with a golden glow — bubble emitter ready.",
		"bubble_emitter": true,
		"voxels": _treasure_voxels(),
	},
	{
		"id": "arch", "name": "Stone Arch", "category": "Natural", "icon": "⌒",
		"description": "Natural stone arch — swim-through centerpiece.",
		"voxels": _arch_voxels(),
	},
	{
		"id": "torii", "name": "Torii Gate", "category": "Themed", "icon": "⛩",
		"description": "Zen gate — pairs with stepping stones and lanterns.",
		"voxels": _torii_voxels(),
	},
	{
		"id": "ruin_column", "name": "Broken Column", "category": "Themed", "icon": "🏛",
		"description": "Greek ruin fragment — stack several for a temple row.",
		"voxels": _ruin_column_voxels(),
	},
	{
		"id": "pebble", "name": "Pebble Cluster", "category": "Natural", "icon": "●",
		"description": "Small stones — scatter for texture.",
		"voxels": _pebble_voxels(),
	},
	{
		"id": "boulder", "name": "Boulder", "category": "Natural", "icon": "🪨",
		"description": "Multi-voxel rounded rock — Iwagumi-friendly.",
		"voxels": _boulder_voxels(),
	},
	{
		"id": "cave_mouth", "name": "Cave Mouth", "category": "Natural", "icon": "🕳",
		"description": "Swim-through cave entrance — fish hide inside.",
		"voxels": _cave_mouth_voxels(),
	},
	{
		"id": "amphora", "name": "Amphora", "category": "Themed", "icon": "🏺",
		"description": "Clay pot tunnel — classic swim-through ornament.",
		"voxels": _amphora_voxels(),
	},
	{
		"id": "crystal_spire", "name": "Crystal Spire", "category": "Themed", "icon": "🔮",
		"description": "Fantasy crystal tower with a glowing tip.",
		"voxels": _crystal_spire_voxels(),
	},
	{
		"id": "anchor", "name": "Sunken Anchor", "category": "Themed", "icon": "⚓",
		"description": "Reef wreck accent — rusted iron anchor.",
		"voxels": _anchor_voxels(),
	},
	]
	var month: int = Time.get_datetime_dict_from_system().get("month", 1)
	if month in [10, 11]:
		_OBJECTS.append({
			"id": "pumpkin", "name": "Pumpkin", "category": "Starter", "icon": "🎃",
			"description": "Seasonal novelty — autumn delight.",
			"voxels": _seasonal_pumpkin_voxels(),
		})
	elif month == 12:
		_OBJECTS.append({
			"id": "gift_box", "name": "Gift Box", "category": "Starter", "icon": "🎁",
			"description": "Seasonal novelty — winter cheer.",
			"voxels": _seasonal_gift_voxels(),
		})
	elif month in [3, 4]:
		_OBJECTS.append({
			"id": "blossom_tree", "name": "Blossom Tree", "category": "Starter", "icon": "🌸",
			"description": "Seasonal novelty — spring accent.",
			"voxels": _seasonal_blossom_voxels(),
		})
