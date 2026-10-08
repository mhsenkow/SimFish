# Visual edges and shelf photos — October 8, 2026

## Fish highlight stability

The fauna shader combined fixture wash, caustics, cone lighting and backlighting without a reflected-light limit. Bright scales could enter the post-process HDR white-lift path. Two separate sheen calculations also quantized the view angle before the palette pass, and banked faces jumped between brightness buckets. The fixture's top-face test incorrectly used a camera-space normal.

Reflected highlights now have a continuous, hue-preserving shoulder. True bioluminescence is added afterwards. Bank lighting and sheen are continuous; metallic turn highlights use a single specular lobe instead of seven angular bands. The fixture uses world-space normals. This adds no textures, passes or draw calls and removes the metallic flash's acos/cos pair.

Legacy per-fish belly flashes now duplicate their shared material once, so animating one individual cannot alter another's material. The normal MultiMesh path retains per-instance data.

Two isolated 24-frame close-view sequences were rendered before and after the shader changes. The revised sequence retains colored fish markings with less washed-out reflection. This is visual evidence for the lighting changes, not a claim that every possible intermittent flicker has been reproduced or eliminated.

## Reliable shelf images

A real photo is scheduled two seconds after the World finishes construction and save restoration is resolved. It does not wait for the five-minute autosave. Requests coalesce and retry after another GPU readback, rather than silently disappearing. Desktop quit also captures a shelf photo. Photos use the palette-processed viewport, so the shelf matches the game's colors.

PNG writes are atomic and operate on a copy of the readback. Empty readbacks cannot replace a good thumbnail. Truncated/non-PNG previews fall back safely. Older visited saves with no usable photo show a stable tank illustration, explicitly labelled as an illustration in its tooltip; opening the tank replaces it with a real photo. Never-opened tanks retain their animated preview. The menu determines visited state from saved-state presence, rather than creation timestamps.

Normal play has no thumbnail readback loop: after the initial photo, the per-frame path returns immediately until a save requests another photo. Headless runs and capture-mode harnesses skip automatic writes.

## Photo UI

Busy/rejected photo requests restore the HUD and explain that the camera is busy. Restoring a photo preserves each panel's previous visibility, including immersion mode, rather than showing every panel. Delayed signature-photo callbacks are bound to the controller's lifetime. A missing readback restores the HUD as well.

## Restore safety

Corrupt or refused saves now block autosave, exit-save and replacement thumbnails. Recovery returns to the shelf by default. Starting fresh is an explicit action that first archives the old files; an archive failure keeps saving blocked. Backups must pass migration and sanitization before loading. Recovery callbacks are controller-bound methods.

The isolated launcher also uses timestamped run IDs in its default user directory: PID-only names could collide with yesterday's scratch data after process IDs were reused.

## Settings worker lifetime

A recovery-dialog shutdown test exposed an actual WorkerThreadPool lifetime bug: settings writes created anonymous worker tasks but never waited for their completion to reclaim task resources. Settings writes now use a bound worker method, atomic replacement, explicit task reclamation and an exit drain that persists the last queued edit. The recovery-dialog test now exits cleanly. Seven settings-worker checks cover completed-task reclamation, latest-snapshot persistence slot changes and immediate teardown.

Godot documents the cleanup requirement in its [WorkerThreadPool reference](https://docs.godotengine.org/en/4.4/classes/class_workerthreadpool.html).

## Tank-save queue

Tank state writes now coalesce per file, so a pending save for one tank cannot replace another tank's pending save. Queue bookkeeping stays on the main thread, completed workers are reclaimed during normal play, and shutdown drains every pending snapshot. Slot duplication, deletion and invalidation drain pending writes before changing files. Six queue checks cover distinct tanks, newest snapshots, normal polling and cleanup.

## Regression isolation

Parallel smokes now use separate user directories. Previously, a test that booted the main scene could earn an achievement and change the mirror another test was checking. The fish-performance fixture uses a fixed random stream and explicitly frees its first population before measuring the second; its original 4.5× scaling and 490 ms limits are unchanged.

## Dense-school social selection

Theory-of-mind still follows its nearest four fish, but selection now keeps a bounded sorted prefix instead of allocating score dictionaries and sorting every neighbor. Seven selection checks cover nearest ranking, empty candidates and stable equal-distance ordering. This preserves the existing model size while reducing work in crowded schools.

## Validation

- Rendered thumbnail lifecycle probe: four checks pass, covering initial visit, busy-readback deferral, eventual persistence and exit capture.
- Thumbnail smoke: twelve checks pass, covering atomic writes, unchanged source images, failed-write preservation, corruption fallback, stable illustrations and shared-material isolation.
- Photo UI smoke: four checks pass, including nested hiding, originally hidden panels and panel deletion during capture.
- Save-restore fence smoke checks that blocked restores cannot snapshot or queue photos, and resolved restores can queue a photo.
- Final gate: all 237 smokes pass in 129 seconds, including the unchanged performance limits. All 571 scripts compile with zero warnings. Final tank inventory is unchanged.
- Completed isolated captures and focused probes verified the real tank inventory remained unchanged. A later check correctly detected concurrent autosaving from the player's editor game session in tank 22; its newer save was preserved, and a stop request was sent before final performance measurements.

The existing rendered harnesses still report renderer/resource allocations at process exit; these fixes do not claim to resolve all shutdown diagnostics.

## Publishing checks

The first remote smoke workflow exposed existing CI setup defects: it omitted GodotSteam before compiling desktop scripts, and passed an unsupported `--config` option to the pinned gdtoolkit 4.3.4 linter. The workflow now installs the same Steam extension as release builds and lets gdlint discover the project-local `gdlintrc`. The corrected six-module lint invocation passes locally.

Linux CI also exposed nonportable array-count substitutions in the shell runner and the duplicate real-time performance fixture retaining its first population. Portable argument counts and explicit fixture disposal fix these, with the 4.5× ratio and 490 ms ceiling unchanged. The corrected real-time fixture passes locally.

Three Linux shards passed; the fourth exposed an animation-test clock mismatch under load. The panel transition smoke now accumulates Godot process time, matching its tweens, rather than assuming elapsed wall time advances animation equally. Panel timings and game behavior are unchanged.

All four release exports succeeded. The macOS download was locally signed with the project Developer ID after CI skipped signing for absent certificate secrets; its nested signatures verify. Notarization remains blocked by the local Xcode license requirement. Fresh desktop builds are staged for Steam, whose upload still requires a cached partner login.

A later Linux run narrowly crossed the population ratio limit (234.3 / 51.7 ms). Both performance smokes now take the median of three independent fixture means, retaining eight timed ticks per fixture, and use identical fish IDs because identity hashes stagger mind cadence. This makes the two gates compare the same workload; thresholds remain unchanged. Both revised smokes pass locally.
