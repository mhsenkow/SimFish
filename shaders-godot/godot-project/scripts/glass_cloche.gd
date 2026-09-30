extends RefCounted
# The glass apothecary cloche from the keeper's own tank (hex_jungle,
# reference photos 1-2): a clear jar on a flared foot, a rounded shoulder into
# a short neck, and a domed lid with a knob. Hair algae mounds on the lid.
#
# Pure geometry: world.gd picks the spot, reserves the ring in the occupancy
# grid, and tags the "LidTop" marker as a hair-mound host. Origin is the base
# of the foot, so the caller places it straight on the substrate surface.
#
# Glass in water barely refracts, so what the eye actually reads is the EDGES:
# the foot ring, the lip and the lid rim catch light as bright lines while the
# walls stay nearly clear. Two materials do that - a faint body and a denser
# edge - instead of one uniform alpha that either vanishes or reads as plastic.

const BODY_ALPHA := 0.13
const EDGE_ALPHA := 0.42
const GLASS_TINT := Color(0.78, 0.94, 0.88)
const RADIAL_SEGMENTS := 20


static func build(radius: float, height: float) -> Node3D:
	var root := Node3D.new()
	var body_mat := _glass_material(BODY_ALPHA, 0.10)
	var edge_mat := _glass_material(EDGE_ALPHA, 0.22)

	var foot_h: float = maxf(0.06, height * 0.04)
	var body_h: float = height * 0.56
	var shoulder_h: float = height * 0.10
	var neck_h: float = height * 0.05
	var rim_h: float = maxf(0.05, height * 0.03)
	var dome_r: float = radius * 0.74
	var dome_h: float = height * 0.13
	var neck_r: float = radius * 0.62

	var y: float = 0.0
	_add_ring(root, "Foot", radius * 1.10, radius * 1.14, foot_h, y, edge_mat, true)
	y += foot_h
	_add_ring(root, "Body", radius, radius, body_h, y, body_mat, false)
	y += body_h
	_add_ring(root, "Shoulder", neck_r, radius, shoulder_h, y, body_mat, false)
	y += shoulder_h
	_add_ring(root, "Neck", neck_r, neck_r, neck_h, y, body_mat, false)
	y += neck_h
	_add_ring(root, "LidRim", dome_r, dome_r, rim_h, y, edge_mat, true)
	y += rim_h

	var dome := MeshInstance3D.new()
	dome.name = "LidDome"
	var dm := SphereMesh.new()
	dm.radius = dome_r
	dm.height = dome_r
	dm.is_hemisphere = true
	dm.radial_segments = RADIAL_SEGMENTS
	dm.rings = 6
	dome.mesh = dm
	dome.material_override = body_mat
	dome.position = Vector3(0.0, y, 0.0)
	dome.scale = Vector3(1.0, dome_h / dome_r, 1.0)
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(dome)
	y += dome_h

	var knob_r: float = radius * 0.18
	var knob := MeshInstance3D.new()
	knob.name = "LidKnob"
	var km := SphereMesh.new()
	km.radius = knob_r
	km.height = knob_r * 2.0
	km.radial_segments = 12
	km.rings = 6
	knob.mesh = km
	knob.material_override = edge_mat
	knob.position = Vector3(0.0, y + knob_r * 0.7, 0.0)
	knob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(knob)

	# Where a hair-algae mound sits: the crown of the lid, beside the knob.
	var lid_top := Node3D.new()
	lid_top.name = "LidTop"
	lid_top.position = Vector3(radius * 0.18, y - dome_h * 0.08, 0.0)
	root.add_child(lid_top)
	root.set_meta("cloche_height", y + knob_r * 1.7)
	root.set_meta("cloche_radius", radius)
	return root


static func _add_ring(root: Node3D, node_name: String, top_r: float, bottom_r: float,
		h: float, y0: float, mat: Material, capped: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bottom_r
	cm.height = h
	cm.radial_segments = RADIAL_SEGMENTS
	cm.rings = 1
	cm.cap_top = capped
	cm.cap_bottom = capped
	mi.mesh = cm
	mi.material_override = mat
	mi.position = Vector3(0.0, y0 + h * 0.5, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


static func _glass_material(alpha: float, rim: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(GLASS_TINT.r, GLASS_TINT.g, GLASS_TINT.b, alpha)
	m.roughness = 0.05
	m.metallic_specular = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.rim_enabled = true
	m.rim = rim * 3.0
	m.rim_tint = 0.4
	m.emission_enabled = true
	m.emission = GLASS_TINT * 0.12
	return m
