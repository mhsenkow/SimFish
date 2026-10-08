# Small, atomic shelf photos. A failed write keeps the last usable image.
extends RefCounted

static func load_image(path: String) -> Image:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	# Reject truncated/non-PNG files quietly before invoking the decoder.
	if bytes.size() < 33 or bytes.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK or img.is_empty():
		return null
	return img

static func save_image(source: Image, path: String) -> Error:
	if source == null or source.is_empty() or path.is_empty():
		return ERR_INVALID_PARAMETER
	var err: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if err != OK:
		return err
	# Never resize the shared readback image: other photo consumers may use it.
	var img: Image = source.duplicate()
	img.resize(480, maxi(1, roundi(float(img.get_height()) * 480.0 / img.get_width())), Image.INTERPOLATE_BILINEAR)
	var pending: String = path + ".pending.png"
	err = img.save_png(pending)
	if err == OK:
		err = DirAccess.rename_absolute(pending, path)
	if err != OK and FileAccess.file_exists(pending):
		DirAccess.remove_absolute(pending)
	return err

# An honest illustration for older visited tanks whose photo is unavailable.
# No World boot, save mutation, per-frame shader or heavyweight JSON parsing.
static func illustration(slot: int) -> Image:
	var img := Image.create(480, 270, false, Image.FORMAT_RGB8)
	img.fill(Color("111c26"))
	img.fill_rect(Rect2i(24, 25, 432, 215), Color("25434b"))
	img.fill_rect(Rect2i(26, 26, 428, 5), Color("5c8b8c"))
	img.fill_rect(Rect2i(26, 216, 428, 22), Color("4e5140"))
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(slot) * 7919 + 83
	for i in 17:
		var x: int = rng.randi_range(42, 438)
		var h: int = rng.randi_range(35, 115)
		var green := Color("49775d") if i % 2 == 0 else Color("638267")
		img.fill_rect(Rect2i(x, 216 - h, 4, h), green)
		for j in 4:
			img.fill_rect(Rect2i(x - 9 + (j % 2) * 9, 216 - h + j * 15, 13, 7), green)
	for i in 8:
		var x: int = rng.randi_range(65, 405)
		var y: int = rng.randi_range(65, 180)
		var fish := Color("c99c65") if i % 2 == 0 else Color("84b7ba")
		img.fill_rect(Rect2i(x, y, 17, 7), fish)
		img.fill_rect(Rect2i(x - 5, y - 2, 5, 11), fish.darkened(0.15))
		img.fill_rect(Rect2i(x + 13, y + 1, 2, 2), Color("192a30"))
	return img
