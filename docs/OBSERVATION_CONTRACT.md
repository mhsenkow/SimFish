# Observation contract (HOLISTIC #018)

Fixture-driven checklist for behaviours a player should be able to **see** and
a harness should be able to **measure**. This is a minimum contract — not a
requirement that every event fire every minute.

Each row: **trigger** (how to provoke), **visible sign** (what the eye gets),
**measurable transition** (state / signal / probe field). Prefer fixtures and
existing probes (`fish_behaviour_probe`, balance soak, Chronicle signals) over
new systems.

| Behavior | Trigger | Visible sign | Measurable state transition |
|---|---|---|---|
| **Food response** | `SimDriver.spawn_player_food` / feed UI / feed toast path | Fish converge on pellets; surface boil / mid-water rush by subtype | `feed_anticipation_active()` true briefly; waste KIND_FOOD count rises then falls; hunger / forage bout fraction up in behaviour probe |
| **Rest** | Night phase (`day_phase` ≈ 0.7–0.9) or species nocturnal/diurnal schedule | Hover / settle near preferred depth; reduced darting | Speed CV and dart% drop vs day sample; depth band shifts toward species rest band (`fish_depth_bands`) |
| **Shelter** | Open space stress, predator nearby, or plant canopy available | Fish tuck into plants / hardscape shadow | Position samples cluster near plant AABBs; shelter bout / cover affinity fields rise |
| **Schooling** | Stock ≥ school threshold of a schooling species (e.g. tetras) | Tight group motion, parallel headings | Neighbour lockstep / shoal count in `fish_behaviour_probe`; heading variance within radius falls |
| **Grazing** | Algae / biofilm present on glass or leaves; herbivore / shrimp stocked | Rasping along glass or leaf surfaces | Algae / biofilm biomass decreases; grazer `eat_*` / forage events in tick return dict |
| **Growth** | Time advance with adequate food + O₂ (multi-day soak or matured start) | Larger body / maturity stage change on individuals | `maturity` / length / biomass fields increase; plant `biomass()` up across soak samples |
| **Decay** | Starvation, crash chemistry, bleach (reef), or plant death path | Death animation, mulm, bleach pale tips, fallen leaves | `creature_removed` / Chronicle death notes; plant `_on_death`; reef bleach metric; mulm / waste up |

## Fixture notes

- **One behaviour per fixture** when asserting. A crowded “everything happens”
  tank is for soak evidence (#006), not for isolating a contract row.
- **Time budgets** may be long (rest, growth, decay). Headless soaks and probes
  are the right tools; interactive playtests confirm the visible sign.
- **Absence is allowed.** Quiet minutes without schooling or grazing are fine
  if the trigger conditions are not met.

## Related paths

- Behaviour numbers: `dev/fish_behaviour_probe.tscn`
- Ecology trajectories: `dev/balance_soak.tscn` / `scripts/ecological_baseline.sh`
- Deaths / births: `creature_added` / `creature_removed` on `SimDriver`
- Feed: `SimDriver.spawn_player_food`
