# GPU bone palette for shared fauna batches — 2 November 2026

Implements item 3 of the "next architectural work" list in
[CROWDED_FISH_PERFORMANCE_20261008.md](CROWDED_FISH_PERFORMANCE_20261008.md):
*"Move bone transforms into a GPU palette … so shared rendering no longer
writes a full transform per voxel per frame."* Applies to the shared species
batches (`fauna_species_batch.gd`, active at ≥36 fish); the per-pivot path for
small tanks is unchanged.

## What changed

- Voxel instances in a skinned species batch are written **once**, in
  bone-local space, at `track_sync`. They never receive per-frame transform
  writes again; hide/retire still zero-scales the static instance immediately.
- Each moving bone (one `SyncGroup`) owns a slot in a per-batch
  **bone-matrix texture** (`SkinPalette`: 3 RGBAF texels per slot, one row per
  slot, slot 0 pinned to identity for untracked static geometry). `sync_all()`
  now writes one 3×4 matrix per bone per frame — `pivot_global * root_inv` —
  and uploads one small texture per batch, instead of composing and uploading
  `bone * local` for every voxel.
- A new shader, `voxel_fauna_skinned.gdshader`
  (`skip_vertex_transform`), fetches the bone matrix by `floor(INSTANCE_CUSTOM.g)`
  and composes `bone * MODEL_MATRIX` in the vertex stage. The entire fragment
  stage, the INSTANCE_CUSTOM contract, and the body-ripple/fin-flutter wave
  moved verbatim into `fauna_mm_common.gdshaderinc`, shared with
  `voxel_fauna_mm.gdshader`, so both batch paths render identically. The wave
  now rides the composed world matrix, so a skinned voxel's S-curve phase is
  the same one the per-pivot path shows.
- `INSTANCE_CUSTOM.g` carries the bone slot in its integer part; belly flash
  stays in the fraction. `fish.gd._push_fauna_inst_custom` preserves the floor
  when it writes flash/vibrancy/quiet, and both shaders read `fract(g)`.
- Culling: group bounds work as before (bone transform × cached local union).
  A skinned batch that also holds untracked static geometry merges the exact
  per-voxel mirror scan into the conservative bounds
  (`VoxelBatch.set_conservative_bounds(…, merge_mirror)`), because tracked
  mirrors are bone-local there — the union can only over-include.
- Skinned materials come from `VoxelMat.make_fauna_skinned()` and join the
  same registry as `make_fauna_mm()`, so aquatic/fixture/rim uniform pushes
  reach both variants.
- **Rollback:** `FaunaSpeciesBatch.set_gpu_skin_enabled(false)` restores the
  legacy per-voxel CPU path (kept intact, still smoke-covered). New batches
  pick up the mode; `FAUNA_SYNC_LEGACY=1` runs the cost probe against it.
- Dead-handle bookkeeping for skinned groups (slot + group reclamation) runs
  at the 1 Hz maintenance tick instead of per frame; retirement itself still
  hides the voxel instantly.

## Measurements

Apple M2 Ultra, Godot 4.6.2, `dev/fauna_sync_cost_probe.gd` (fixed workload:
400 bones, 9,600 voxels, full poses every frame, dummy renderer — isolates the
script/instance-API sync cost this change targets, not GPU shading):

| Path | median | p95 |
| --- | --- | --- |
| Legacy per-voxel CPU (`FAUNA_SYNC_LEGACY=1`) | 10.007 ms | 10.791 ms |
| GPU bone palette | 0.695 ms | 0.772 ms |

**~14× less per-frame sync time** on the exact path that cost ~9.6 ms/frame in
the 197-fish stress scene. The remaining skinned cost is one `global_transform`
read + two `Transform3D` multiplies + 12 float writes per bone, plus one
texture upload per batch. Receipts: ignored `output/gpu_skinning/`
(`sync_legacy.json`, `sync_skinned.json`).

This does not by itself make the 197-fish overload scene smooth — cognition
and the sim tick still dominate there (see the crowded-fish doc) — it removes
the render-sync slice and scales it with bones instead of voxels.

## Validation

- `smoke_fauna_render_lifecycle.gd` now covers **both** paths (103 checks):
  skinned — static bone-local instances, slot stamping with fraction
  preserved, palette row composing the **exact** world transform the legacy
  path wrote (rotation + non-uniform scale), identity slot 0, merged bounds
  covering tracked and untracked corners, maintenance reclamation, slot
  free-list return; legacy (flag off) — the original contract verbatim.
- `smoke_retired_voxel_slots.gd`, `smoke_voxel_commit.gd`,
  `smoke_perf_realtime.gd`, `smoke_motion_phase1.gd`,
  `smoke_render_material_lifetime.gd` green.
- `smoke_light_model.gd`'s lit-coverage gate now scans the composed source
  (local `#include` resolution) and lists `voxel_fauna_skinned` in
  MUST_BE_LIT.
- Visual check on the real renderer: `dev/visual_capture.gd` via
  `scripts/dev_run.sh`, beginner sandbox with a 60-glassdart custom stock
  (skinned batch engaged for fish 37+): school renders with correct bodies,
  fins, banking and color; per-pivot and skinned fish indistinguishable.
- Full suite: no new failures attributable to this change (remaining failures
  reproduce at HEAD or come from the in-flight motion pass in the working
  tree; verified in a clean HEAD worktree with and without this diff).

## Reproduce

```bash
FAUNA_SYNC_LEGACY=1 FAUNA_SYNC_PROBE_OUT=/tmp/sync_legacy.json \
  ./scripts/godot.sh --headless --path shaders-godot/godot-project \
  --script res://dev/fauna_sync_cost_probe.gd
FAUNA_SYNC_PROBE_OUT=/tmp/sync_skinned.json \
  ./scripts/godot.sh --headless --path shaders-godot/godot-project \
  --script res://dev/fauna_sync_cost_probe.gd
./scripts/godot.sh --headless --path shaders-godot/godot-project \
  --script res://scripts/smoke_fauna_render_lifecycle.gd
VISUAL_CAPTURE_SCENARIO=beginner_sandbox \
  VISUAL_CAPTURE_CFG="tank_preset=custom;custom_glassdart_count=60" \
  VISUAL_CAPTURE_ANGLES=front ./scripts/dev_run.sh res://dev/visual_capture.tscn
```
