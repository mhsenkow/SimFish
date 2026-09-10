extends SceneTree

# Loads every .gdshader so the parser reports errors. Catches a broken
# #include or a typo in a shared snippet before it reaches a GPU.
func _initialize() -> void:
	var dir := DirAccess.open("res://shaders")
	var bad: int = 0
	var n: int = 0
	dir.list_dir_begin()
	var f: String = dir.get_next()
	while f != "":
		if f.ends_with(".gdshader"):
			n += 1
			var sh: Shader = ResourceLoader.load("res://shaders/" + f, "Shader",
				ResourceLoader.CACHE_MODE_IGNORE) as Shader
			if sh == null:
				push_error("SHADER LOAD FAILED: " + f)
				bad += 1
			else:
				# Touching the uniform list forces the parse to complete.
				var u: Array = sh.get_shader_uniform_list(true)
				if u.is_empty() and f != "circle_mask.gdshader":
					print("  (note) %s exposes no uniforms" % f)
		f = dir.get_next()
	dir.list_dir_end()
	print("[shader_check] %d shaders, %d failed" % [n, bad])
	quit(1 if bad > 0 else 0)
