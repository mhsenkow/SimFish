extends SceneTree
const Photos = preload("res://scripts/tank_thumbnail.gd")

func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_tank_thumbnails")
	var path: String = "user://thumbnail_test/photo.png"
	var source: Image = Photos.illustration(20)
	var source_size: Vector2i = source.get_size()
	t.equals(Photos.save_image(source, path), OK, "photo saves atomically")
	t.equals(source.get_size(), source_size, "saving never mutates shared readback")
	var good: Image = Photos.load_image(path)
	t.check(good != null and good.get_width() == 480, "saved photo is usable at shelf resolution")
	var before: PackedByteArray = FileAccess.get_file_as_bytes(path)
	t.equals(Photos.save_image(Image.new(), path), ERR_INVALID_PARAMETER, "empty readback is rejected")
	t.equals(FileAccess.get_file_as_bytes(path), before, "failed capture preserves last good photo")
	t.check(not FileAccess.file_exists(path + ".pending.png"), "no partial file remains")
	t.equals(Photos.illustration(20).get_data(), source.get_data(), "legacy illustration is stable")
	t.check(Photos.illustration(21).get_data() != source.get_data(), "different slots have distinct illustrations")
	var corrupt: String = "user://thumbnail_test/corrupt.png"
	var f := FileAccess.open(corrupt, FileAccess.WRITE)
	f.store_string("not an image")
	f.close()
	t.check(Photos.load_image(corrupt) == null, "corrupt image gets a safe fallback")

	var shared: ShaderMaterial = VoxelMat.make_fauna(Color.CORAL)
	shared.set_shader_parameter("belly_flash", 0.0)
	var a := Fish.new()
	var b := Fish.new()
	var ma := MeshInstance3D.new()
	var mb := MeshInstance3D.new()
	ma.material_override = shared
	mb.material_override = shared
	a.add_child(ma)
	b.add_child(mb)
	a._apply_belly_flash_uniform(0.5)
	t.check(ma.material_override != shared, "legacy belly flash owns its material")
	t.approx(float(shared.get_shader_parameter("belly_flash")), 0.0, "neighbor material is untouched", 0.001)
	var owned: Material = ma.material_override
	a._apply_belly_flash_uniform(0.3)
	t.check(ma.material_override == owned, "flash animation reuses owned material")
	a.free()
	b.free()
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(corrupt)
	quit(t.finish())
