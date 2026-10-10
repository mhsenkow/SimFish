# Locomotion and contact pass — 8 October 2026

This pass makes physical movement follow the animal's intent and the surface it
is using. It extends the habitat feeding/shelter work rather than adding a
parallel behavior system.

## Shrimp, crabs, and lobsters

Routine acceleration no longer triggers a backwards tail escape. Nearby predator
pressure triggers the escape bout; movement follows the selected safe direction,
while the shrimp's display can face backwards during the tail flip. Escape speed
is bounded under sustained threat, and reaching cover ends the burst. Animals without
reachable shelter can move away from the predator instead of continuing to forage.

Physics no longer accumulates gravity inside the brain's steering command.
Swimming shrimp settle gently between bouts. Bottom walkers flatten vertical
steering, use leg traction, and remain on the substrate. Resting animals stop
rather than receiving residual swimming thrust. A throttled local terrain sample
updates the floor reference as the animal moves across the tank.

Walking phases advance from actual horizontal travel after boundary constraints.
Blocked animals don't keep stepping in place. Legs have a longer loaded stance
and a shorter lifted recovery. Body bob keeps its rest offset, and feeding pitch
and reach relax back to neutral after the meal. Motion oscillators advance even
when the cosmetic rendering path is skipped.

## Snails

Snail steering follows a bounded angular turn, including directly opposite goals.
Vector blending previously collapsed opposite headings to zero or snapped them
around. The foot slows during tight turns, and feeding slows translation to rest
while the visible rasp continues. Threat retreat takes priority over feeding.

## Plant contact

The plant brush response previously clamped every positive contact to a large
minimum bend. It now scales with contact strength, ignores zero contact, and
retains the existing spring recovery and upper bound. Grazing at a reachable
leaf adds a small touch response. Moving animals can therefore disturb foliage
without every contact looking like a violent collision.

## Verification

The locomotion regression exercises real shrimp physics, target direction,
resting contact, blocked gait, safe escape direction, bottom reach, oscillator
progress, walking consistency at 30/60/120 Hz, snail turning/feeding, and bounded
plant contact. The complete 241-test suite passed. The final focused locomotion test passed
19 checks using an initialized walking model. All 576 scripts compiled with zero
analyzer warnings. Two rendered walking poses for shrimp, crab, and lobster were
inspected in an isolated scene; the real player tank inventory stayed unchanged.
Existing movement, habitat, growth, and save tests also apply.

This remains stylized voxel locomotion: leg poses do not use per-foot terrain IK,
and the local-floor sample is a bounded-cost approximation. Long-term ecosystem
balance requires longer observation than these movement checks establish.
