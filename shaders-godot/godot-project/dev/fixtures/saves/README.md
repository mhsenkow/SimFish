# Synthetic save fixtures (Holistic #011)

Small, anonymized `state.json`-shaped tanks for migration/repair tests.
No private player dialogue text.

| File | Intent |
|---|---|
| `old_tank.json` | High `tank_age_s`, story/chronicle skeleton |
| `breeding_tank.json` | Eggs + gestating livebearer + breed cooldowns |
| `learned_fish.json` | Feed heatmap + `mind.learned_mind` beliefs |
| `custom_scape.json` | Aquascape voxels / build cells |
| `reef.json` | `ocean_sand` + reef preset |

Validate: `./scripts/run_smokes.sh --include save_fixtures`
