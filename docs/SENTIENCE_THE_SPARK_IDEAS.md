# Sentience — The Spark

*Director's brief: surface the invisible mind, close emergence loops, and wire
expression/perf so cognition reads in motion, shader, sound, and save.*

Format: **Effort** S (≤2h) / M (half-day) / L (full day+) · **Impact** S / M / L.
Line numbers drift — follow symbols.

> **The thesis (read this first).** Cognition is **deep**; expression and feedback
> loops are **thin**. Felt-self modules (`fish_protoself`, `fish_volition`,
> `fish_binding`, `global_workspace`, …) tick every frame under
> [`mind_cycle.gd`](../shaders-godot/godot-project/scripts/mind_cycle.gd), but the
> player mostly sees cruise/forage animation and debug text. This doc closes the
> loop: every item wires **real fields** → legible motion, shader, sound, or save
> behavior. No invented state. Template voice fallback stays sacred.

---

## What already exists (don't rebuild)

- **Mind stack** — MindState, global workspace + ignition, DDM deliberation,
  episodic memory + schemas, felt-self layer (Vol. VIII), daring mind, narrator
  contract. See [SENTIENCE_THE_FELT_SELF_IDEAS.md](SENTIENCE_THE_FELT_SELF_IDEAS.md).
- **Expression bridge (partial)** —
  [`fish_spark_expression.gd`](../shaders-godot/godot-project/scripts/fish_spark_expression.gd)
  + [`fish_spark_behavior.gd`](../shaders-godot/godot-project/scripts/fish_spark_behavior.gd).
- **Persistence (mostly ahead of doc)** — `mood`, `arousal`, `habituated`,
  `feed_heatmap`, `bonds`, `grudges`, `familiarity`, `longing_residue` in
  [`fish.gd`](../shaders-godot/godot-project/scripts/fish.gd) `to_save_dict()` /
  [`FishMind.mind_to_dict()`](../shaders-godot/godot-project/scripts/fish_mind.gd).
- **Render stack** — palette quantize, voxel SSS/irid, water refraction, glass SSR,
  caustics, god rays. See [AESTHETICS_IDEAS.md](AESTHETICS_IDEAS.md).

---

## The three structural levers

**Lever 1 — One expression substrate.** Most §A items share the same pattern:
read grounded mind fields in `fish_spark_expression.gd`, write motion modifiers +
shader uniforms + tank ambient params. Build the bridge once; each idea is a thin
commit.

**Lever 2 — Close emergence loops.** §B items turn one-shot behaviors (courtship
reset, instant algae removal, tap spikes) into **persistent** state changes the sim
remembers and the player can read.

**Lever 3 — Perf headroom before polish.** §G87–90 must land before §A adds
per-fish uniform writes or the ~60-fish ceiling collapses.

---

## Section A — Surface the invisible (1–25)

*Make the computed mind legible in motion, shader, and follow-mode UI.*

- [x] **1. Prediction-error shimmer.** Route `_prediction_error` spikes from
  [`mind_world_model.gd`](../shaders-godot/godot-project/scripts/mind_world_model.gd)
  → brief `irid_strength` lift + micro-startle in
  [`fish_spark_expression.gd`](../shaders-godot/godot-project/scripts/fish_spark_expression.gd)
  / [`voxel.gdshader`](../shaders-godot/godot-project/shaders/voxel.gdshader). The
  cheapest “something surprised it” tell. *S · L*
- [x] **2. Confidence posture.** Low `mind_self_model` confidence → wider turns,
  shorter venture distance, more glance-back in
  [`fish_spark_expression.gd`](../shaders-godot/godot-project/scripts/fish_spark_expression.gd)
  `motion_modifiers()`. Doubt visible in carriage, not just DDM threshold. *M · M*
- [x] **3. Stance silhouette.** `_life_stance` from
  [`mind_daring.gd`](../shaders-godot/godot-project/scripts/mind_daring.gd) → fin
  spread, tail cadence, spacing bias constants in spark motion. *M · M*
- [x] **4. Longing visible.** Wire `MindDaring.on_goal_lost()` call sites +
  `_longing_residue` → linger near last goal, slower drift, dimmer hue via spark
  bridge. *M · L*
- [x] **5. Afterglow trail (partial).** `fish_felt_now.present_width` + afterglow
  ring → motion-echo length / wander damp in spark motion; full shader trail optional.
  *M · M*
- [x] **6. Ignition tell.** `_workspace_ignited` rising edge → one-beat stillness +
  gaze decouple flag in
  [`fish_spark_expression.gd`](../shaders-godot/godot-project/scripts/fish_spark_expression.gd).
  *S · L*
- [x] **7. Gaze decoupling (partial).** `attention_focus` → `_gaze_yaw` toward focus
  object while body cruises; head saccade path exists, full decouple still tuning.
  *M · M*
- [x] **8. Effort in swim.** `fish_volition.effort` / depleted `will_pool` → tail
  amplitude + locomotion weight in spark motion. *M · M*
- [x] **9. Veto hitch.** `FishVolition.try_veto()` → brief decel + reorient via
  `notify_veto()` + motion hitch scale. *S · M*
- [x] **10. Qualia contrast color.** `fish_qualia` contrast delta →
  `color_vibrancy` shader delta in spark `apply_shaders()`. *M · M*
- [x] **11. Proto-concepts.** `fish_concepts` `"scarcity"` / `"safety"` → patrol
  tightness / cruise height via spark motion modifiers. *M · M*
- [x] **12. Curiosity orient (partial).** `MindWorldModel.curiosity_target_bias()`
  → orient-and-hold before approach; bias exists, hold beat still thin. *M · M*
- [x] **13. Self-summary (rare).** `mind_self_model.update_self_summary()` at
  milestone → one-shot narrator line grounded in real state change. *M · M*
- [x] **14. φ tank glow.** Tank-mean `phi_proxy` from
  [`fish_binding.gd`](../shaders-godot/godot-project/scripts/fish_binding.gd) →
  caustic sync coherence in
  [`world_atmosphere.gd`](../shaders-godot/godot-project/scripts/world_atmosphere.gd)
  / [`world.gd`](../shaders-godot/godot-project/scripts/world.gd). *M · M*
- [x] **15. Disintegration snap (partial).** `fragmented` → suppress afterglow/gaze/
  stance tells for one beat; irid damp wired, full tell suppression partial. *M · M*
- [x] **16. Inner-life panel (partial).** Promote
  [`mind_debug.gd`](../shaders-godot/godot-project/scripts/mind_debug.gd)
  `inspector_text()` → follow-mode **Inner Life** panel (Settings toggle, not debug-only).
  *M · L*
- [x] **17. Affect circumplex.** Follow panel valence×arousal dot from
  [`fish_core_affect.gd`](../shaders-godot/godot-project/scripts/fish_core_affect.gd).
  *S · M*
- [x] **18. Interoceptive tells.** Bind `fish_protoself` gill/gut/fin/fatigue → gill
  flush, belly scale, fin rigidity (parallel `_tick_gill_flush` today). *M · M*
- [x] **19. Pre-boredom listless.** Flat affect + low curiosity → repetitive pathing
  before boredom bid fires. *M · M*
- [x] **20. Surprise double-take.** `fish_relevance` surprise boost →
  `FishMind.maybe_double_take()` hook. *S · M*
- [x] **21. Habituation fade (partial).** Write `habituated` on encounter via
  [`fish_spark_behavior.gd`](../shaders-godot/godot-project/scripts/fish_spark_behavior.gd);
  decay on repeat feeds §B30. *M · M*
- [x] **22. Signal hesitation (partial).** `fish_signals` reliability → reaction
  delay before dart in `signal_reaction_delay()`; full kinetic “wait, is that real?”
  still tuning. *M · M*
- [x] **23. Feed anticipation.** `feed_heatmap` + time-of-day → drift toward surface/
  spot pre-feed via `feed_anticipation_drift()`. *M · M*
- [x] **24. Empathy echo (partial).** Bondmate distress → sympathetic stress tell /
  stance bias via daring empathy term; full echo still thin. *M · M*
- [x] **25. Intention hold line.** `intention_hold` → reduce wander noise in spark
  motion pathing. *S · M*

---

## Section B — Emergence loops (26–40)

*Turn one-shot behaviors into persistent, readable dynamics.*

- [x] **26. Courtship can be refused.** Partner stress/energy/bond gate rejection;
  suitor `_courtship_reject_cd` + `MindDaring.on_goal_lost()` on decline.
  [`fish.gd`](../shaders-godot/godot-project/scripts/fish.gd) courtship tier. *M · L*
- [x] **27. Territory escalation tiers.** Display → chase → nip → injury; fin damage
  visible (#69); grudge history beyond timed float. *L · L*
- [x] **28. Hunt outcomes persist.** Predator learns hunting ground; prey danger
  memory on capture/escape in episodic spatial write. *L · M*
- [x] **29. Algae grazing pressure.** Per-patch graze counter slows `_age` /
  bloom_pressure in [`algae.gd`](../shaders-godot/godot-project/scripts/algae.gd);
  herbivore boom clears, crash lets bloom return. *M · M*
- [x] **30. Glass-tap habituation write path.** Route
  `pulse_glass_tap()` through `habituated`; cry-wolf stress when novelty low in
  [`sim_driver.gd`](../shaders-godot/godot-project/scripts/sim_driver.gd) +
  `glass_tap_habituation()`. *M · M*
- [x] **31. School fission/fusion.** Density-triggered sub-school split/merge — not
  just topdown cosmetic `flock_split_pull`. *L · M*
- [x] **32. Grudge geometry in boids.** Enemy lanes at scale beyond local separation
  defer in `_boids`. *M · M*
- [x] **33. Danger schema patrol bias.** `schema_patrol_avoidance()` +
  `bias_patrol_anchors_from_schemas()` in
  [`fish_spark_behavior.gd`](../shaders-godot/godot-project/scripts/fish_spark_behavior.gd);
  heatmap refresh skips bad corners. *M · M*
- [x] **34. Feeding frenzy contagion.** Feed event → local arousal spike +
  school rush via `tick_feed_contagion()` + `pulse_feed_contagion_at()` on eat.
  *M · M*
- [x] **35. Cleaning-station relationships.** Client–cleaner familiarity, preferred
  station, queue ritual beyond one-shot stress relief. *M · M*
- [x] **36. Mourning ripple stance arc.** Extend `_mate_grief` → multi-day stance
  shift + spacing recovery. *M · L*
- [x] **37. Enrichment restock.** Hardscape/plant changes bump novelty via
  `_bid_salience_mods` / tank enrichment API. *M · M*
- [x] **38. Cross-species feeding niches.** `cross_species_feeding_penalty()` in waste
  search — timid fish avoid pellets another species is working. *M · M*
- [x] **39. Landscape of fear.** `_landscape_fear` contracts patrol/home range;
  ignores asleep predators; relaxes when threat leaves. *M · L*
- [x] **40. Rank → boldness drift (partial).** `tick_rank_boldness_drift()` nudges
  `personality.boldness` + carriage over sim-days; full fight-history arc open. *M · M*

---

## Section C — Wake the dead hooks (41–50)

*Wire stubs that compute but never act.*

- [x] **41. Counterfactual → DDM (partial).** Ground
  [`fish_generative_self.gd`](../shaders-godot/godot-project/scripts/fish_generative_self.gd)
  stub in deliberation tie-break + rare narrator line; full protention loop open. *M · M*
- [x] **42. Markov blanket gates percepts.** Under extremis (`stress > 0.85`), gate
  percept integration width via `markov_blanket()` consumer. *M · M*
- [x] **43. Affordances → motor pattern.** `fish_spark_behavior.gd` maps winning bid
  affordance (`edible`, `hide_from`, …) to approach/eat/mate/hide motor scale. *M · L*
- [x] **44. Dark-room guard.** Chronic hide timer → curiosity bid /
  `tick_dark_room_guard()` emerge drive. *S · M*
- [x] **45. Episodic pos pull (partial).** Retrieval hint `pos` → spatial pull via
  `schema_spatial_pull()` + workspace `"memory"` bias; relevance kind-match still open.
  *M · M*
- [x] **46. Keeper ambient fields.** Feeding/water-change/gaze populate
  `keeper_intent` / `keeper_felt` in
  [`keeper_care.gd`](../shaders-godot/godot-project/scripts/keeper_care.gd). *M · M*
- [x] **47. Bid salience API (partial).** Tank-level `set_bid_salience_mods()` for
  enrichment; internal writeback works, external API thin. *M · M*
- [x] **48. Sensing voice.** Template sensing lines on player glance
  (`PLAYER_SENSING_VOICE` path in
  [`mind_narrator.gd`](../shaders-godot/godot-project/scripts/mind_narrator.gd)). *M · M*
- [x] **49. Salient → episodic promotion.** Promote strongest salient-ring entries to
  episodic; retire duplicate encode path. *M · M*
- [x] **50. Trait-change beat (partial).** `tick_trait_change_notice()` → rare
  self-summary hook; player-facing line still thin. *S · M*

---

## Section D — Aesthetics & light (51–70)

*Deepen the frame without breaking palette discipline.*

- [x] **51. Real fish contact shadows.** Fish shadow pass → substrate caustic shadow
  array or decal under each fish. *L · L*
- [x] **52. Depth-aware refraction.** Depth texture sample in
  [`water.gdshader`](../shaders-godot/godot-project/shaders/water.gdshader) for
  column-aware bend. *L · L*
- [x] **53. Caustics on glass walls.** Travelling caustic band on vertical panes in
  [`glass.gdshader`](../shaders-godot/godot-project/shaders/glass.gdshader). *M · M*
- [x] **54. Living water surface.** Surface mesh displacement from fish/feed/aeration
  events. *L · M*
- [x] **55. Fin subsurface scatter.** View-dependent translucency in voxel thin
  regions beyond SSS rim. *L · M*
- [x] **56. Environment-probe glass reflections.** Low-res reflection probe / SSR
  upgrade beyond screen-space mirror. *L · M*
- [x] **57. Morph room-preset transitions.** LUT + light param cross-fade in
  [`world_atmosphere.gd`](../shaders-godot/godot-project/scripts/world_atmosphere.gd).
  *M · M*
- [x] **58. Follow-mode depth of field.** Enable/default-tune existing
  `follow_depth_of_field` in [`tank_config.gd`](../shaders-godot/godot-project/scripts/tank_config.gd).
  *S · M*
- [x] **59. God-ray dust motes.** Particulate in light shaft + fish occlusion fill for
  [`god_ray.gdshader`](../shaders-godot/godot-project/shaders/god_ray.gdshader)
  `occluders[]`. *M · M*
- [x] **60. True bloom pass.** Separate GPU bloom on emissive pass vs palette-quantize
  shoulder only. *M · M*
- [x] **61. Wake ribbons rendered.** Visualize `deposit_wake()` flow deposit from
  [`world.gd`](../shaders-godot/godot-project/scripts/world.gd). *M · M*
- [x] **62. Visible flow field.** Particulate/caustic-shear on
  [`tank_flow_field.gd`](../shaders-godot/godot-project/scripts/tank_flow_field.gd).
  *M · M*
- [x] **63. Glass wipe clears mineral spots.** Input clears `MINERAL_SPOT` streaks
  accumulated in `world.gd`. *M · S*
- [x] **64. Health iridescence.** Vitality + pred-error → `irid_strength` in
  [`fish_spark_expression.gd`](../shaders-godot/godot-project/scripts/fish_spark_expression.gd).
  *S · M*
- [x] **65. Circadian grade LUT.** Dawn/dusk full-palette LUT shift beyond lighting
  curves. *M · M*
- [x] **66. Sleep visible.** `_asleep` dims vibrancy/irid + fin/tail slack via spark
  motion. *S · M*
- [x] **67. Startle flash.** Unify `_startle_*` → body tension pose + water pulse via
  `sim_driver`. *S · M*
- [x] **68. Fry fragile look.** Maturity → translucency + oversized-eye fry shader pass.
  *M · M*
- [x] **69. Age wear.** Tie injuries/scars from territory (#27) to visible markings.
  *M · M*
- [x] **70. Attention halo.** Follow-mode torus on `_interest_target` when
  `attention_focus` set ([`main.gd`](../shaders-godot/godot-project/scripts/main.gd)
  `_update_attention_halo`). *S · M*

---

## Section E — Sound & motion (71–78)

*Audio and locomotion signatures that read inner state.*

- [x] **71. Responsive soundscape floor.** O₂-stress dawn tone, substrate rustle on dig
  — extend [`ambient_audio.gd`](../shaders-godot/godot-project/scripts/ambient_audio.gd).
  *M · M*
- [x] **72. Spatialised feeding + startle.** Positioned pan or `AudioStreamPlayer3D` at
  event position (global eat SFX today). *M · M*
- [x] **73. Contagion harmonic.** Tank mean-arousal spike → `pulse_contagion_harmonic()`
  in [`ambient_audio.gd`](../shaders-godot/godot-project/scripts/ambient_audio.gd);
  sampled from [`sim_driver.gd`](../shaders-godot/godot-project/scripts/sim_driver.gd).
  *M · M*
- [x] **74. Hush beat on favourite death.** Favourite death / calm → near-silence
  (pairs §H98). *M · L*
- [x] **75. Stance motion signatures (partial).** `_life_stance` → tail cadence /
  fin spread in spark motion (overlap §A3). *M · M*
- [x] **76. Idle-drift personality.** Boldness/curiosity shape rest meander signature.
  *M · M*
- [x] **77. Turn-cost realism.** Speed × body size → `max_turn_rate` coupling. *M · S*
- [x] **78. Breath-linked hover.** Rest/hover vertical bob from
  `fish_protoself.gill_rhythm` via `breath_hover_offset()`. *S · M*

---

## Section F — Continuity & persistence (79–86)

*The soul must survive save/load and absence.*

- [x] **79. Emotional state survives load.** `mood`, `arousal`, full affect in
  `MindState.to_dict()` — verify round-trip. *S · L*
- [x] **80. Habituation + feed heatmap persist.** `habituated`, `feed_heatmap` in
  `to_save_dict()` / `apply_save_dict()`. *S · M*
- [x] **81. Social graph persists.** `bonds`, `grudges`, `partner_id`, `familiarity`,
  `mate_id` beyond doc’s original “partner + grudges only”. *S · L*
- [x] **82. Sleep/fatigue on load.** Serialize `_asleep` + protoself fatigue snapshot
  in `to_save_dict()`. *M · M*
- [x] **83. Newborns don’t vanish.** Audit egg→fry race; ensure fry in `sim.fish` at
  save time. *M · M*
- [x] **84. Continuity beat on return.** On load + absence: bonded fish approach/settle
  using restored `familiarity` (beyond `fish_continuity.gd` text). *M · L*
- [x] **85. Longing residue persists.** `longing_residue` in `FishMind.mind_to_dict()`.
  *S · M*
- [x] **86. Save-soul smoke test.** Extend
  [`smoke_felt_self.gd`](../shaders-godot/godot-project/scripts/smoke_felt_self.gd):
  affect + habituation + bonds + residue byte-stable round-trip. *M · M*

---

## Section G — Performance & determinism (87–94)

*Headroom for the spark layer — lossless where possible.*

- [x] **87. Fix material-duplication churn.** Finish per-fish duplicated `ShaderMaterial`
  cache for belly-flash + stress + spark paths in
  [`fish.gd`](../shaders-godot/godot-project/scripts/fish.gd) (~3009–3040). *M · L*
- [x] **88. Grid snail predation search.** Route snail predation through spatial grid
  (mirror algae `query_*_in_radius`) instead of O(snails) walk. *M · M*
- [x] **89. Reuse spatial neighbor array.** Pool scratch `Array` in
  [`sim_driver.gd`](../shaders-godot/godot-project/scripts/sim_driver.gd)
  `_spatial_query()`. *S · L*
- [x] **90. LOD inner life by distance (partial).** Wire
  [`MindLOD.tier_for()`](../shaders-godot/godot-project/scripts/mind_lod.gd) into
  `sim_driver` off-frustum throttle + `mind_cycle` phase skip. *M · L*
- [x] **91. Adaptive quality default.** `TankConfig.adaptive_quality` default `true` +
  doc comment; stepped in `main.gd` `_adaptive_quality_tick`. *S · M*
- [x] **92. Batch skip unchanged shader params.** Glass/world uniform cache in
  [`world.gd`](../shaders-godot/godot-project/scripts/world.gd) ambient tick. *M · M*
- [x] **93. Seed last raw RNG paths.** Route genome/spawn/mutation through `MindRng` /
  sim seed stream. *M · M*
- [x] **94. Perf HUD behind flag (partial).** Dev overlay: fish-brain ms, draw calls
  via `main.gd` frame history; full alloc-rate HUD open. *S · M*

---

## Section H — Bond moments (95–100)

*Scarce, gated beats — never on tap. Persist `spark_milestones` to prevent repeats.*

- [x] **95. First recognition (partial).** One-time familiarity threshold → glass
  approach; `_spark_milestones["first_recognition"]` in
  [`fish.gd`](../shaders-godot/godot-project/scripts/fish.gd). *M · L*
- [x] **96. Away recap grounded.** One true tank event in away_recap via logged state
  (no invented drama). *M · M*
- [x] **97. 2am glance.** Night-watch fish drift on odd-hour open
  ([`night_watch.gd`](../shaders-godot/godot-project/scripts/night_watch.gd) hook).
  *M · M*
- [x] **98. Witnessed death.** No toast; spacing loosen + music hush (#74) + delayed
  guardian line. *M · L*
- [x] **99. Damaged bond.** Over-tap habituation → cursor avoidance / trust scar.
  *M · M*
- [x] **100. One first-person line.** Single apex milestone → grounded honest frame
  line from fish POV, never repeat. *L · L*

---

## Sequencing note

**Shortest path (visible spark in a week):** §G87+89+90 → scaffold
`fish_spark_expression.gd` → §A1,6,9,17,20 → §F82 verify → §B29,30,33 → §D64,66,70.

**If you only do five:** (1) prediction-error shimmer #1, (2) ignition tell #6,
(3) material cache #87, (4) MindLOD wiring #90, (5) inner-life panel #16 + circumplex #17.

One doc item = one commit (`SENTIENCE_THE_SPARK #N`). Mark `- [x]` after headless smoke:

```bash
./scripts/godot.sh --headless --path shaders-godot/godot-project \
  --script res://scripts/smoke_tank_shapes.gd
```

Targeted smokes: `smoke_spark_expression.gd`, `smoke_spark_surface.gd`,
`smoke_spark_emergence.gd`; extend `smoke_felt_self.gd` for #86.

**L-tier confirm before starting:** §B26–28, §D51–52,54,56.

---

## Related docs

| Doc | Relationship |
|---|---|
| [SENTIENCE_THE_FELT_SELF_IDEAS.md](SENTIENCE_THE_FELT_SELF_IDEAS.md) | Computes the mind §A surfaces |
| [PLAYER_BOND_IDEAS.md](PLAYER_BOND_IDEAS.md) | Sensing + familiarity substrate for §H |
| [AESTHETICS_IDEAS.md](AESTHETICS_IDEAS.md) | Render epics §D51–63 overlap |
| [REFINEMENT_100_IDEAS.md](REFINEMENT_100_IDEAS.md) | Polish-only pass; defers new features |
| [GOALS.md](GOALS.md) | Master shipped tracker |
