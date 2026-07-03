# MindKernelNative (optional GDExtension)

Optional native acceleration for `MindKernel` (#49). The game ships with a
full GDScript twin (`scripts/mind_kernel.gd`); this extension is not required
for play or CI.

When built and enabled in `project.godot`, `ClassDB` exposes `MindKernelNative`
with:

- `competition(saliences: PackedFloat32Array, coal_masks: PackedInt32Array, labels: PackedStringArray) -> Dictionary`
- `dot_top_k(query, entries, k) -> Array`

Build (Godot 4.6+, SCons):

```bash
cd extensions/mind_kernel
scons platform=macos target=template_release
```

Copy the resulting `.dylib`/`.so`/`.dll` beside this folder and register in
`mind_kernel.gdextension`.

Verify:

```bash
./scripts/godot.sh --headless --path shaders-godot/godot-project \
  --script res://scripts/smoke_mind_kernel.gd
```
