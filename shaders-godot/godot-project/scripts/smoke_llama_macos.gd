extends SceneTree

# Headless macOS repro: load bundled Guardian GGUF + create llama context.
# Run after install_godot_llama.sh + fetch_guardian_model.sh:
#   ./scripts/godot.sh --headless --path shaders-godot/godot-project \
#     --script res://scripts/smoke_llama_macos.gd

const MODEL_RES: String = "res://assets/guardian/SmolLM2-360M-Instruct-Q4_K_M.gguf"


func _init() -> void:
	if OS.get_name() != "macOS":
		print("[smoke_llama_macos] skip — macOS only")
		quit()
		return
	if not ClassDB.class_exists("LlamaModel"):
		push_error("LlamaModel GDExtension missing — run scripts/install_godot_llama.sh")
		quit(1)
		return
	if not FileAccess.file_exists(ProjectSettings.globalize_path(MODEL_RES)):
		push_error("Guardian GGUF missing — run scripts/fetch_guardian_model.sh")
		quit(1)
		return
	var path: String = ProjectSettings.globalize_path(MODEL_RES)
	var wrapper: GDScript = load("res://addons/godot_llama/godot_llama.gd") as GDScript
	if wrapper == null:
		push_error("godot_llama wrapper missing")
		quit(1)
		return
	var ll: RefCounted = wrapper.new() as RefCounted
	if ll == null or not ll.is_available():
		push_error("Llama wrapper unavailable (dylibs?)")
		quit(1)
		return
	var err: int = ll.load_model(path, {"n_gpu_layers": 0})
	if err != OK:
		push_error("load_model failed: %s" % error_string(err))
		quit(1)
		return
	var threads: int = maxi(1, mini(2, OS.get_processor_count() - 1))
	err = ll.create_context({
		"n_ctx": 512,
		"threads": threads,
		"threads_batch": threads,
	})
	if err != OK:
		push_error("create_context failed: %s" % error_string(err))
		quit(1)
		return
	var out: String = ll.generate("Reply with one word: ready", 8, {"temperature": 0.05})
	if out.strip_edges() == "":
		push_error("generate returned empty")
		quit(1)
		return
	print("[smoke_llama_macos] OK — %s" % out.strip_edges())
	quit()
