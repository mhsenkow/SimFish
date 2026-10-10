# walstad loom v0.2.39

Released October 9, 2026. This release folds the color/light, habitat, locomotion,
crowded-fish, mind/tending, render/schooling, and long-session retention passes
into a shippable build.

## Color and light

The planted palette, day/night LUTs, and runtime banks agree again. Fish
highlights keep pigment instead of washing toward white. Fixture wash is gentler
so shaped beams supply the bright passages; analytic beams and visible shafts
share the same cone. LED bars keep four parallel spots under one continuous
scattering curtain.

## Living habitats and locomotion

Healthy foliage shelters shrimp; grazers clean film before tissue, pause while
handling food, and respect plant recovery. Snails rasp film in portions and
climb real canopy positions. Locomotion remains continuous and species-aware
rather than keyframed.

## Performance and retention

Crowded tanks reuse spatial school merges and shared bone updates. Render sync
uploads only changed instances; bone-group culling and exact no-op guards cut
repeated work. Long sessions reclaim retired fauna slots, departed-fish
caches/jobs, and weak material registries without discarding living memories.
Mind/tending keeps owned worker handoffs, bounded recall, shared attention
counts, complete starter habitats, and appetite-based automatic feeding.

## Validation

613 scripts compile with zero analyzer warnings. All 260 local smoke tests pass
with zero failures or timeouts (~156 s). Targeted CPU probes are recorded in the
pass notes; they do not measure whole-game FPS. Isolated runs preserve the real
tank inventory.

Detailed pass reports:

- [Color and light](COLOR_AND_LIGHT_20261008.md)
- [Fish flash diagnosis](FISH_FLASH_DIAGNOSIS_20261008.md)
- [Living habitats](HABITAT_INTERACTIONS_20261008.md)
- [Living locomotion](LIVING_LOCOMOTION_20261008.md)
- [Crowded fish](CROWDED_FISH_PERFORMANCE_20261008.md)
- [Mind and tending](TENDING_PERFORMANCE_20261009.md)
- [Render and schooling](RENDER_SCHOOLING_PERFORMANCE_20261009.md)
- [Long-session retention](LONG_SESSION_RETENTION_20261009.md)
