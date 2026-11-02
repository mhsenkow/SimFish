# walstad loom v0.2.52

Released November 2, 2026. A motion and performance release: fish bend like
one body with a travelling wave, the twelve principles of animation start to
show on every stroke, and crowded tanks spend far less CPU syncing fauna.

## Motion that reads as life

Phases 0–3 of the creature-motion backlog land in the tank:

- **One stroke clock.** Thrust and the visible tail share a clock; the wave
  travels head to tail instead of a standing counter-wag.
- **Anticipation and follow-through.** Head and bank lead a turn; caudal,
  bank and pitch springs hang after a stroke; fins tuck and flare with effort.
- **Pose tools.** A pose library, exposure-sheet timing, staging for
  legibility, and exaggeration that scales with distance and music.
- **Timing.** Strouhal, diel, bout, Q10 and oxygen curves drive how fast a
  body moves; shrimp and snails pick up the same latency language.
- **Invertebrates.** Snail pedal-wave bands, shell rock, and shrimp antenna
  chains stop looking like attached props.

## Crowded tanks stay light

Shared species batches now skin on the GPU: bone transforms live in a small
palette texture, voxels stay in bone-local space, and per-frame sync drops
from ~10 ms to under 1 ms on the measured probe (~14×). A rollback switch
keeps the old CPU path for A/B.

## Store and Play

Capsule art refreshed for the Steam store page. Android Play console notes
and marketing assets land under `docs/ANDROID_PLAY.md` and `marketing/play/`.

## Notes

- Saves keep working.
- Motion lab: Shift+M overlay and `dev/motion_lab` for species-by-species
  review.
- GPU skinning: `FaunaSpeciesBatch.set_gpu_skin_enabled(false)` or
  `FAUNA_SYNC_LEGACY=1` restores the prior sync path.
