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


# BLOCKING: llama.cpp's generate() (and generate_stream()) run tokenize, prompt
# decode and every sampled token on the CALLING thread. Only call this from a
# worker Thread (guardian_llm.gd does) or a headless smoke — never from a
# frame callback on the main thread.
func generate(prompt: String, max_tokens: int = 128, params: Dictionary = {}) -> String:
	if context == null:
		return ""
	context.set_prompt(prompt)
	return context.generate(max_tokens, params)


# Thread-safe request to stop an in-flight generation at its next token.
func cancel() -> void:
	if context != null and context.has_method("cancel"):
		context.cancel()
