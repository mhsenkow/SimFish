# Living habitat interaction pass — 8 October 2026

This pass connects plant surfaces, shelter, grazing, and detritus more closely.
It preserves the existing growth architecture, water chemistry, reproduction,
and crawling/swimming systems rather than introducing a separate ecosystem.

## Behavior

- Healthy ordinary foliage provides shrimp shelter as well as the existing
  anemone/sponge/hydra cover. Dying or melting plants stop offering durable cover.
- Shrimp seek food on live leaf geometry and clean surface biofilm/hair algae
  before eating tissue. Tissue grazing requires severe hunger.
- Crabs and lobsters reject leaf targets above their bottom reach. Swimming
  shrimp can forage among foliage. Floater-root targeting uses the nearest root
  that was actually selected, instead of always heading for the first root.
- Feeding includes short handling pauses, while physiology keeps ticking and
  predators can interrupt. A successful detritus claim receives nutrition only
  when SimDriver resolves consumption, preventing competing shrimp from being
  rewarded for the same particle.
- Snails rasp one algae portion at a time, pause between bites, and stop foraging
  when satiated. Empty bites produce neither nutrition nor pellets.
- Snails seek actual film-bearing leaf positions, including on small plants.
  Severe-hunger tissue fallback spares small establishing plants. Plant climbing
  uses the local spatial query and actual canopy height.
- Leaf detritus can only be picked within reach. Successful feeding still returns
  pellets to the existing nutrient cycle.

## Plant recovery and visual stability

Surface cleaning preserves growing tips and does not induce tissue-damage
pressure. Mixed film/tissue bites subtract the cleaned portion before structural
removal. Transient grazing pressure now decays below its defense threshold too.

Algae tint is composed from current ecology and the base tint each update;
it no longer accumulates warmth/desaturation indefinitely. Cleaned broad leaves
recover their color. Fine-leaved detritus effects run once per plant tick rather
than once per leaf, avoiding leaf-count-dependent effects and repeated work.

## Validation and limits

`smoke_habitat_interactions.gd` exercises real plant and shrimp behavior, reachable
surface meals, stem preservation, empty snail bites, portion sizes, feeding
pauses, shelter health, bottom reach, detritus claim timing, tint recovery, and
per-plant ecology cadence. Compile/warning checks and the broader smoke suite
cover existing growth, reproduction, movement, and save contracts.

Validation: 240/240 smoke tests passed. Final follow-up checks passed all 50
plant tests, both snail tests, the shrimp gait test, and the 31-check habitat
regression. All 575 scripts compile with zero analyzer warnings.

An isolated populated-tank capture was inspected; real save inventory remained
unchanged. The rendering harness reports resource leaks at shutdown; this pass
does not resolve those teardown diagnostics. A still frame does not establish long-term colony balance or prove
motion quality. Feeding uses the game's existing coarse food units, and bottom
reach is a behavioral limit rather than a general climbing/pathfinding system.

## Follow-up: removal during ecology updates

The live game log identified a freed neighbor in `Plant._recompute_shade`.
Shade and pollination both tested a cached object's type before checking its
validity. Both now check validity first and skip nodes queued for removal.
Plant and algae spatial queries prune removed candidates before returning them,
without forcing a grid rebuild for each query.

Grazing also deleted detritus flecks while their plant-owned timers retained a
lambda capture of the freed mesh. Retirement timers now belong to the fleck and
use a weak reference. Natural expiration clears the habitat slot; early grazing
cancels the timer; externally deleted flecks are pruned before the spawn cap.

`smoke_ecology_lifecycle.gd` reproduced both exact runtime errors before the fix
and failed eight assertions. Its 16 checks now pass without those errors.
All 583 scripts compile with zero analyzer warnings. The full 244-test smoke
suite passed, including the performance gates; the isolated run verified that
the real tank save inventory was unchanged.
