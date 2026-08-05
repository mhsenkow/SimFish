extends SceneTree
# Boot main.tscn, dump raw SubViewport + final Display texture.

func _initialize() -> void:
	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		push_error("main.tscn missing")
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	for i in 120:
		await process_frame
	var art_dir := ProjectSettings.globalize_path("res://").path_join("../../artifacts")
	var sv := main.get_node_or_null("SubViewport") as SubViewport
	if sv != null:
		var img: Image = sv.get_texture().get_image()
		if img != null:
			img.save_png(art_dir.path_join("smoke_raw.png"))
			print("[smoke_capture] raw ", img.get_size(), " center=", img.get_pixel(img.get_width()/2, img.get_height()/2))
	# Final on-screen TextureRect (post quantize).
	var display := main.get_node_or_null("Display") as TextureRect
	if display != null and display.texture != null:
		var dimg: Image = display.texture.get_image()
		if dimg != null:
			dimg.save_png(art_dir.path_join("smoke_post.png"))
			print("[smoke_capture] post ", dimg.get_size(), " center=", dimg.get_pixel(dimg.get_width()/2, dimg.get_height()/2))
	# Also whole window
	var root_img: Image = root.get_viewport().get_texture().get_image()
	if root_img != null:
		root_img.save_png(art_dir.path_join("smoke_window.png"))
		print("[smoke_capture] window ", root_img.get_size())
	quit(0)
