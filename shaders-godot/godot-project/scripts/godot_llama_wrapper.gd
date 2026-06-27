extends RefCounted

# Wrapper around the GDExtension — typed loosely so the script still parses
# when the extension failed to load (missing dylibs on macOS dev builds).
# Intentionally no class_name: install_godot_llama.sh copies this to
# addons/godot_llama/godot_llama.gd and a duplicate global would break load.

var model: Variant = null
var context: Variant = null


func _init() -> void:
	if not ClassDB.class_exists("LlamaModel"):
		return
	model = ClassDB.instantiate("LlamaModel")
	context = ClassDB.instantiate("LlamaContext")


func is_available() -> bool:
	return model != null and context != null


func load_model(path: String, params: Dictionary = {}) -> Error:
	if model == null:
		return ERR_UNAVAILABLE
	return model.load(path, params)


func create_context(params: Dictionary = {}) -> Error:
	if context == null or model == null:
		return ERR_UNAVAILABLE
	return context.create(model, params)


func generate(prompt: String, max_tokens: int = 128, params: Dictionary = {}) -> String:
	if context == null:
		return ""
	context.set_prompt(prompt)
	return context.generate(max_tokens, params)
