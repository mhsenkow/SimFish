# Development save isolation incident — 2026-10-07

## What happened

During the holistic improvement regression run, the old `scripts/dev_run.sh` launcher appended custom user-directory settings to `override.cfg`. On the tested Godot 4.6.2 macOS build, this did not redirect `user://` away from the real game directory. The existing `smoke_scenario_layouts.gd` explicitly called `TankSaves.clear_active_state()`, which deleted the active slot's current and previous state files.

The launcher's inventory comparison detected the deletion at the end of the run. The affected slot was **13, “Iwagumi Stone Garden.”** Its configuration and metadata content survived. Other tank file content matched the before-run inventory. This is a development-run failure, not a successful save-preservation check.

Deleted files, under `~/Library/Application Support/Godot/app_userdata/walstad loom/tanks/13/`:

| File | Bytes before deletion | SHA-256 before deletion |
|---|---:|---|
| `state.json` | 3,009,677 | `0288fa96427de522fde139e41ee1c2f4f3ea7e19c59393a898581ff6af15a3e6` |
| `state.json.bak` | 2,075,580 | `de1d271464d71a381a7d6da6f7b3a43aad62da11edfaf150a1ad9db63356d8ae` |

Evidence: `.scratch/inventories/20261007T185532Z_35037_before.txt`, corresponding `_after.txt`, and `output/improvement_pass_20261007/full_smokes_verified.log`.

## Recovery status

**Unresolved.** No exact copy has been found in remaining Godot/Vivarium saves, repository output, local temporary directories, the local review sandbox, or the searched home-directory state files. All 38 remaining Godot state/backup files were compared against the deleted hashes; none matched. No local Time Machine snapshots were listed. The user has been asked whether an external/manual backup exists. No replacement tank state has been invented or written over the remaining slot.

## Corrections

- The launcher now creates an isolated `project.godot` with the custom directory settings present at initial engine startup. Assets/scripts are shared through symlinks; the real project's configuration is never edited.
- A preflight project with no game autoloads checks `OS.get_user_data_dir()` against the requested scratch directory before the game can start. A mismatch aborts the run.
- Every isolated launch retains a full copy of the current real tank directory in `.scratch/save_backups/<run-id>/tanks/`, in addition to the before/after inventory check. These new copies were created after the incident and do not recover the deleted slot 13 state.
- The scenario smoke uses capture mode and no longer clears the active save.
- `TankSaves.clear_active_state()` now moves incompatible current/previous states into a timestamped `invalidated/` archive instead of deleting them. A regression verifies exact contents, absence from the load path, and repeat-call behavior.
- Repository guidance now warns that `override.cfg` alone is insufficient for save isolation on the tested build.

Subsequent verified isolated runs have left real tank inventory unchanged. Retain this report until recovery is resolved; passing later tests does not undo the incident.
