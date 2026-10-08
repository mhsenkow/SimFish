# walstad loom — 1,000 ways to make the aquarium better

Reviewed: **October 7, 2026**. Scope: the whole repository, with emphasis on the shipping Godot game. **This is an understanding and proposal document. No improvement tasks were implemented, no game scenes were run, and no real tank saves were touched for this review.**

## What “better” means here

A beautiful aquarium whose inhabitants are recognizable, whose actions have understandable causes, whose ecological cycles remain coherent over time, and whose interface helps the keeper watch and care. More detail is useful when it increases recognition, agency, or understanding. More menus, particles, cognitive modules, and chemistry variables are not automatically improvements.

The strongest direction is to connect what already exists: **body → movement → perception → choice → consequence → memory → visible expression**. Feeding should change condition and waste; courtship should lead to understandable reproductive outcomes; chemistry should affect behavior before unexplained collapse; a learned preference should change where a fish goes. The keeper should be able to notice those connections without reading implementation terminology.

For “sentience,” this review follows the project's existing functional-signature framing: learning, memory, prediction, stable choices, individual relationships, and embodied responses. It does not interpret a proxy metric, generated speech, or a passing test as proof of subjective experience. See [the existing evaluation harness](SENTIENCE_EVAL_HARNESS.md).

## Review basis and limits

This was a repository review with targeted code reading, subsystem mapping, existing evidence review, and inspection of saved images. It was not an exhaustive line-by-line audit or a fresh runtime benchmark. Proposals are design opportunities, not 1,000 confirmed defects. Where behavior already exists, the proposal means **refine, reconcile, or validate it**, not build a second implementation. Exact scope should be checked against current code and evidence before execution.

| Area | Evidence inspected | Implication |
|---|---|---|
| Project map and prior work | [README](../README.md), [repo instructions](../AGENTS.md), [existing finishing plan](HOLISTIC_FINISHING_PLAN_400.md), [execution ledger](HOLISTIC_FINISHING_LEDGER.md), [goals](GOALS.md) | Many seemingly new ideas already have implementations; extend those systems and avoid claiming their absence. The older “400” plan currently has eight authored topic sections, so its title alone is not evidence of coverage. |
| Anatomy and aesthetics | Shared fauna builder, style guide, fish motion/depth helpers; existing `output/fauna_pass/final/fish_guppy.png` | The portrait retains pronounced bright planar fins. Whether these should be softened is an aesthetic judgment requiring live-scale comparison, not a geometry failure claim. Recent recorded fixes already address buried pupils, fin attachment, shrimp anatomy, and shell continuity. |
| Interface | HUD regions, Residents code, existing `output/ui_baselines/layout_pass_final/1152x648/16_library.png` | Recent panel work already keeps footer actions visible in its recorded desktop captures. The library still presents a dense mix of roster, preview, genome, and sharing concepts; information hierarchy and portrait/enlarged-text coverage merit further review. |
| Historical visual context | `docs/img/planted-community.png` | This saved marketing frame has strong surrounding-room patterning, small fish, a dense HUD, and collapse notifications. It is an example of competing visual priorities, not proof those conditions persist in the current build. |
| Reproduction | `egg.gd` and relevant spawn/release functions in `sim_driver.gd` | The inspected egg path has a shared 30-second sim-time incubation and a four-cell cluster visual; several brood paths cap release at four. These are simplifications to assess. The direct livebearer path and gestation release path merit contract reconciliation; reachability and actual double-spawn behavior were not established. |
| Chemistry and time | `water_chemistry.gd`, sim-driver clock hooks, ecological baseline script | Shipping chemistry uses a colony-strength proxy, normalized resource variables, soft ceilings, and a constant `SIM_DAY_S = 864.0`; daylight uses configurable `day_length_s`. Their relationship should be explicit before calling day labels or cycles realistic. No instability was measured in this review. |
| Cognition and voice | `mind_eval.gd`, `mind_legible.gd`, keeper model, conversation code, existing harness document | Functional evaluation already exists. Required and optional invariants coexist; extensions should demonstrate causal live behavior and use controls, rather than report an undifferentiated consciousness score. No current test pass status is asserted here. |
| Reliability and delivery | Save manager, performance governor, smoke baseline, test/release workflows, recorded Steam feedback, landing-page source | Save migration, frame-cap-aware budgets, sharded smoke CI, and multiplatform exports already exist. The baseline has three active failure entries at review time. Public copy still contains July launch messaging; live publication and current distribution status were not checked. |
| Reference and future paths | [Rust reference README](../sim-rust/README.md), [schema README](../data-schemas/README.md) | Rust chemistry is not wired into the game, and JSON schemas are not a shipping runtime species loader. Treat them as references or future contracts. Intentional web/game font duplication must remain. |

Existing uncommitted edits were present before this review, including fauna, panels, callbacks, and their tests. They were left untouched. The execution ledger describes those edits and earlier batches; its claims were read as historical evidence, not independently rerun. Existing saved images are also snapshots, not a live inspection of the user's current tank.

## How to use the list

There are exactly **40 sections × 25 proposals = 1,000 ideas**, with stable IDs **WL-0001–WL-1000**. These IDs are separate from all earlier roadmap numbering. This review implements none of these proposals; existing behavior may already satisfy some of them. No checkboxes are marked complete.

- **P1**: prioritize assessing this area because it directly affects recognition, coherence, usability, or continuity. Priority applies to the section, not a commitment to implement all its items together.
- **P2**: consider after the most visible foundational issues are understood; many items depend on P1 contracts.
- **Sources** identify where to begin, not an exhaustive list of files that would change.
- **Review intent** gives the local acceptance direction. A proposal is worth doing when its stated behavior can be observed, compared, or explained, not merely when code is added.

Dependencies matter: establish time and resource contracts before calibrating cycles; establish lifecycle and identity contracts before complex lineage or social continuity; preserve readable anatomy before adding decoration; measure behavior before adding another cognition layer. Do not turn all 1,000 ideas into one simultaneous scope. Reject ideas whose cost or complexity exceeds the demonstrated benefit.

## Suggested first assessment shortlist

These are selections from the numbered list below, not extra ideas or an execution order approved by the user.

| IDs | Focus | Why it is a strong starting point |
|---|---|---|
| WL-0002, WL-0013 | Species recognition at gameplay scale | Establish what viewers can actually identify before expanding visual detail. |
| WL-0028, WL-0052 | Tail form and restrained fin color | Investigate the large bright plates visible in the saved guppy portrait. |
| WL-0076, WL-0077 | Tailbeat and current-carried movement | Connect visible locomotion to effort rather than generic motion. |
| WL-0104, WL-0126 | Habitat routes and independent school motion | Make fish occupy believable space while avoiding a synchronized particle-cloud look. |
| WL-0213, WL-0223 | Breeding blocker and attempt-to-success evidence | Let keeper understanding guide gate tuning instead of blind permissiveness. |
| WL-0226, WL-0229, WL-0245 | Incubation, representation, and birth contracts | Clarify what a clutch means and how its outcome develops. |
| WL-0476, WL-0479, WL-0480 | Time, nitrogen budgets, timestep safety | Resolve shared foundations before making chemistry more elaborate. |
| WL-0517, WL-0523 | Daily oxygen minima and brood respiratory demand | Connect reproduction and daily metabolic consequences. |
| WL-0622, WL-0633, WL-0665 | Useful perception, retained learning, live cognition evaluation | Demonstrate lived behavior without relying on narrator eloquence. |
| WL-0751, WL-0752, WL-0778 | HUD hierarchy and resident detail structure | Reduce interpretation effort while preserving useful depth. |
| WL-0826, WL-0849 | Text scaling and realistic localized layout checks | Address screen configurations not covered by the recorded desktop panel pass. |
| WL-0901, WL-0924 | Consistent saves and continuation of behavior | Preserve what makes an individual feel like the same animal. |
| WL-0951, WL-0956, WL-0962 | Ownership, time bases, and diagnostic noninterference | Make cross-system improvements safer and easier to reason about. |
| WL-0976, WL-0978, WL-0985 | Honest release evidence and exported-build verification | Ensure public promises match the experience players actually receive. |

## Topic index

- [01. Art direction and evidence](#topic-01) — WL-0001–WL-0025
- [02. Fish silhouette and anatomy](#topic-02) — WL-0026–WL-0050
- [03. Fish color and markings](#topic-03) — WL-0051–WL-0075
- [04. Swimming animation and physical expression](#topic-04) — WL-0076–WL-0100
- [05. Habitat use and navigation](#topic-05) — WL-0101–WL-0125
- [06. Schools and collective movement](#topic-06) — WL-0126–WL-0150
- [07. Social encounters and territories](#topic-07) — WL-0151–WL-0175
- [08. Age, health, and lived bodies](#topic-08) — WL-0176–WL-0200
- [09. Courtship and reproductive readiness](#topic-09) — WL-0201–WL-0225
- [10. Eggs, gestation, and fry survival](#topic-10) — WL-0226–WL-0250
- [11. Inheritance and lineage](#topic-11) — WL-0251–WL-0275
- [12. Food, foraging, and nutrition](#topic-12) — WL-0276–WL-0300
- [13. Predation and trophic relationships](#topic-13) — WL-0301–WL-0325
- [14. Shrimp and crustacean life](#topic-14) — WL-0326–WL-0350
- [15. Snails and benthic detail](#topic-15) — WL-0351–WL-0375
- [16. Reef residents and saltwater ecology](#topic-16) — WL-0376–WL-0400
- [17. Plant silhouettes and aquascape composition](#topic-17) — WL-0401–WL-0425
- [18. Plant growth, competition, and succession](#topic-18) — WL-0426–WL-0450
- [19. Substrate, hardscape, and microorganisms](#topic-19) — WL-0451–WL-0475
- [20. Nitrogen cycle and chemistry coherence](#topic-20) — WL-0476–WL-0500
- [21. Oxygen, carbon, and daily metabolism](#topic-21) — WL-0501–WL-0525
- [22. Water, flow, temperature, and equipment](#topic-22) — WL-0526–WL-0550
- [23. Time, seasons, and offline continuity](#topic-23) — WL-0551–WL-0575
- [24. Ecological balance and scenario pacing](#topic-24) — WL-0576–WL-0600
- [25. Perception and embodied attention](#topic-25) — WL-0601–WL-0625
- [26. Memory, learning, and personal history](#topic-26) — WL-0626–WL-0650
- [27. Decisions, goals, and functional sentience](#topic-27) — WL-0651–WL-0675
- [28. Social cognition and individual relationships](#topic-28) — WL-0676–WL-0700
- [29. Keeper relationship and care loop](#topic-29) — WL-0701–WL-0725
- [30. Voice, narration, and meaning](#topic-30) — WL-0726–WL-0750
- [31. HUD hierarchy and information design](#topic-31) — WL-0751–WL-0775
- [32. Panels, library, and editing workflows](#topic-32) — WL-0776–WL-0800
- [33. Onboarding, discovery, and player purpose](#topic-33) — WL-0801–WL-0825
- [34. Accessibility, localization, and input](#topic-34) — WL-0826–WL-0850
- [35. Camera, observation, and photo tools](#topic-35) — WL-0851–WL-0875
- [36. Sound, music, and atmosphere](#topic-36) — WL-0876–WL-0900
- [37. Save integrity and continuity of identity](#topic-37) — WL-0901–WL-0925
- [38. Performance, fidelity, and device budgets](#topic-38) — WL-0926–WL-0950
- [39. Architecture, contracts, and developer understanding](#topic-39) — WL-0951–WL-0975
- [40. Verification, releases, documentation, and community](#topic-40) — WL-0976–WL-1000

## The 1,000 proposals

<a id="topic-01"></a>

### 01. Art direction and evidence — WL-0001–WL-0025

**Priority:** P1. **Sources:** [style-guide/STYLE_GUIDE.md](../style-guide/STYLE_GUIDE.md); [docs/HOLISTIC_FINISHING_LEDGER.md](../docs/HOLISTIC_FINISHING_LEDGER.md); [scripts/visual_baseline_matrix.sh](../scripts/visual_baseline_matrix.sh).

**Review intent:** Extend existing visual evidence with observable quality targets; judge the aquarium at gameplay scale.

- **WL-0001 [P1]** Define a reference frame for each biotope with explicit subject hierarchy.
- **WL-0002 [P1]** Grade fish recognition at normal tank distance before approving portrait details.
- **WL-0003 [P1]** Choose one default beauty profile and reconcile documented versus shipping defaults.
- **WL-0004 [P1]** Compare palette variants with identical stocking, lighting, camera, and simulation seed.
- **WL-0005 [P1]** Measure subject readability separately from whole-frame contrast and shadow coverage.
- **WL-0006 [P1]** Create a visual checklist for calm, feeding, courtship, spawning, and emergency states.
- **WL-0007 [P1]** Give every scenario an intentional focal region and protected negative space.
- **WL-0008 [P1]** Track visual defects by reproducible frame, camera, species, and configuration.
- **WL-0009 [P1]** Require before-and-after clips for changes whose benefit depends on motion.
- **WL-0010 [P1]** Review visual presets in grayscale to expose competing value hierarchies.
- **WL-0011 [P1]** Preserve the pixel-art rules when adding transparency, highlights, and effects.
- **WL-0012 [P1]** Identify which stylizations serve beauty and which undermine biological readability.
- **WL-0013 [P1]** Create a species recognition sheet using unlabelled silhouettes at shipping resolution.
- **WL-0014 [P1]** Establish an effect budget so bubbles, shimmer, and dust cannot obscure residents.
- **WL-0015 [P1]** Maintain separate acceptance criteria for hero views, close-ups, and UI previews.
- **WL-0016 [P1]** Evaluate visual upgrades across all supported fidelity tiers before adopting defaults.
- **WL-0017 [P1]** Document acceptable scene density independently from sustainable ecological stocking.
- **WL-0018 [P1]** Add a consistent review rubric for anatomy, silhouette, movement, and habitat fit.
- **WL-0019 [P1]** Capture every scenario at dawn, noon, dusk, and night for comparison.
- **WL-0020 [P1]** Separate current evidence from older marketing images when triaging visual problems.
- **WL-0021 [P1]** Record observed aesthetic preferences without treating subjective ratings as correctness tests.
- **WL-0022 [P1]** Use paired human reviews to identify changes that improve recognizability reliably.
- **WL-0023 [P1]** Require an accessible alternate presentation for effects essential to understanding state.
- **WL-0024 [P1]** Set a minimum unobscured aquarium area for every primary UI configuration.
- **WL-0025 [P1]** Archive superseded visual decisions with their reason to prevent repeated reversals.

<a id="topic-02"></a>

### 02. Fish silhouette and anatomy — WL-0026–WL-0050

**Priority:** P1. **Sources:** [shaders-godot/godot-project/scripts/fish.gd](../shaders-godot/godot-project/scripts/fish.gd); [shaders-godot/godot-project/scripts/fauna_voxel_builder.gd](../shaders-godot/godot-project/scripts/fauna_voxel_builder.gd); [shaders-godot/godot-project/dev/fauna_portrait.tscn](../shaders-godot/godot-project/dev/fauna_portrait.tscn).

**Review intent:** Refine the shared builder after the recorded geometry fixes; assess species and morph extremes.

- **WL-0026 [P1]** Give each species a distinct head-to-body ratio visible in miniature.
- **WL-0027 [P1]** Shape caudal peduncles so broad tails transition naturally from the body.
- **WL-0028 [P1]** Reduce planar slab appearance in fancy tails using layered stepped membranes.
- **WL-0029 [P1]** Tune dorsal-fin height by body plan instead of generic visual exuberance.
- **WL-0030 [P1]** Differentiate rounded, forked, lyre, and veil tails at low resolution.
- **WL-0031 [P1]** Keep eyes readable without turning distant fish into oversized-eyed mascots.
- **WL-0032 [P1]** Align mouth position with surface feeding, grazing, and substrate-sifting strategies.
- **WL-0033 [P1]** Give bottom dwellers flatter bellies and substrate-compatible resting silhouettes.
- **WL-0034 [P1]** Define juvenile proportions separately from uniformly scaled adult geometry.
- **WL-0035 [P1]** Create restrained sex differences that remain recognizable in dim tanks.
- **WL-0036 [P1]** Preserve believable fin attachment across extreme inherited length values.
- **WL-0037 [P1]** Add asymmetry limits so mutations remain animals with usable silhouettes.
- **WL-0038 [P1]** Make barbels distinct from fins through position, thickness, and movement.
- **WL-0039 [P1]** Build a thin-body profile for laterally compressed fish viewed head-on.
- **WL-0040 [P1]** Prevent tail markings from breaking the apparent continuous fin contour.
- **WL-0041 [P1]** Give pectoral fins recognizable paired placement in front three-quarter views.
- **WL-0042 [P1]** Check silhouette continuity when all fin pivots reach their animation extremes.
- **WL-0043 [P1]** Reserve mouth and gill detail for close-up tiers where it actually reads.
- **WL-0044 [P1]** Differentiate benthic heads from open-water heads without adding noisy ornament.
- **WL-0045 [P1]** Tune fin thickness to avoid opaque sheets dominating small bodies.
- **WL-0046 [P1]** Keep caudal rays sparse enough that the membrane remains the main shape.
- **WL-0047 [P1]** Scale catchlights by projected size so distant eyes do not sparkle excessively.
- **WL-0048 [P1]** Distinguish healthy slender fish from starvation by abdomen rather than global scale.
- **WL-0049 [P1]** Create species-specific body curvature limits to avoid rubbery extreme bends.
- **WL-0050 [P1]** Compare preview and live silhouettes through the same camera projection.

<a id="topic-03"></a>

### 03. Fish color and markings — WL-0051–WL-0075

**Priority:** P1. **Sources:** [shaders-godot/godot-project/scripts/fish.gd](../shaders-godot/godot-project/scripts/fish.gd); [shaders-godot/godot-project/scripts/fauna_voxel_builder.gd](../shaders-godot/godot-project/scripts/fauna_voxel_builder.gd); [shaders-godot/godot-project/shaders/](../shaders-godot/godot-project/shaders/); [style-guide/STYLE_GUIDE.md](../style-guide/STYLE_GUIDE.md).

**Review intent:** Improve color identity through the existing palette pipeline rather than bypassing quantization.

- **WL-0051 [P1]** Give each species a small identifiable set of color landmarks.
- **WL-0052 [P1]** Reduce fully saturated fin plates where they overpower the body.
- **WL-0053 [P1]** Keep body patterns legible after quantization rather than only in raw rendering.
- **WL-0054 [P1]** Preserve diagnostic stripes under blackwater tint and nighttime illumination.
- **WL-0055 [P1]** Limit iridescent flashes by viewing angle and species material identity.
- **WL-0056 [P1]** Use quieter belly values to separate anatomy from decorative markings.
- **WL-0057 [P1]** Match tail accents to body accents without forcing every region equally bright.
- **WL-0058 [P1]** Separate structural metallic sheen from pigment saturation in material controls.
- **WL-0059 [P1]** Add subtle stable individual pattern offsets without frame-to-frame noise.
- **WL-0060 [P1]** Blend maturation color changes continuously while preserving recognizable species identity.
- **WL-0061 [P1]** Make stress paling gradual and recoverable rather than a sudden palette swap.
- **WL-0062 [P1]** Give courtship color amplification a bounded species-specific peak.
- **WL-0063 [P1]** Avoid identical brightness for unrelated warning, courtship, and healthy-color states.
- **WL-0064 [P1]** Keep transparent species readable through contour and sparse internal landmarks.
- **WL-0065 [P1]** Improve contrast of pale fish against sand using restrained dorsal shading.
- **WL-0066 [P1]** Improve contrast of dark fish against wood using habitat-aware lighting.
- **WL-0067 [P1]** Offer a natural-color morph set alongside intentionally ornamental morphs.
- **WL-0068 [P1]** Keep sibling variation within inherited palette families instead of arbitrary rainbow drift.
- **WL-0069 [P1]** Define pattern scale relative to body dimensions rather than world units.
- **WL-0070 [P1]** Preserve marking alignment when body length and girth genes vary independently.
- **WL-0071 [P1]** Check bilateral patterns for continuity at mesh segment seams.
- **WL-0072 [P1]** Reduce visual moire from dense stripes crossing the pixel grid.
- **WL-0073 [P1]** Make scar and fin-repair markings distinguishable from inherited patterns.
- **WL-0074 [P1]** Validate grayscale recognition for species differentiated mainly by red and green.
- **WL-0075 [P1]** Show representative live-lighting swatches beside neutral-lighting genome colors.

<a id="topic-04"></a>

### 04. Swimming animation and physical expression — WL-0076–WL-0100

**Priority:** P1. **Sources:** [shaders-godot/godot-project/scripts/fish_life_bouts.gd](../shaders-godot/godot-project/scripts/fish_life_bouts.gd); [shaders-godot/godot-project/scripts/hydrodynamics.gd](../shaders-godot/godot-project/scripts/hydrodynamics.gd); [shaders-godot/godot-project/scripts/fish.gd](../shaders-godot/godot-project/scripts/fish.gd).

**Review intent:** Refine existing bouts, turn inertia, and fin effort; verify changes with motion clips and the behavior probe.

- **WL-0076 [P1]** Tune tailbeat frequency against body lengths travelled rather than absolute speed.
- **WL-0077 [P1]** Separate propulsive tail strokes from low-effort current-carried drifting.
- **WL-0078 [P1]** Give braking fish a visible pectoral-fin response before their speed settles.
- **WL-0079 [P1]** Prevent stationary fish from inheriting large cruise body-wave amplitude.
- **WL-0080 [P1]** Blend turns through the body so the head does not rotate independently.
- **WL-0081 [P1]** Match banking strength to turn radius and body compression.
- **WL-0082 [P1]** Make acceleration start with a small anticipatory body bend.
- **WL-0083 [P1]** Give sustained fast swimming a different rhythm from a brief escape burst.
- **WL-0084 [P1]** Stagger gill breathing phases so resting schools do not pulse together.
- **WL-0085 [P1]** Keep respiratory effort responsive to oxygen demand as well as low speed.
- **WL-0086 [P1]** Let long fins lag behind body turns without clipping through the torso.
- **WL-0087 [P1]** Give bottom sitters occasional repositioning strokes instead of continuous wagging.
- **WL-0088 [P1]** Make hovering corrections intermittent and directional rather than uniform jitter.
- **WL-0089 [P1]** Vary dart duration by species while retaining recovery pauses.
- **WL-0090 [P1]** Let fatigue lengthen recovery after repeated escape bursts.
- **WL-0091 [P1]** Give older fish lower peak acceleration without making them motionless.
- **WL-0092 [P1]** Show feeding nips with a short mouth-and-head action aligned to contact.
- **WL-0093 [P1]** Distinguish mouthbrooder throat motion from livebearer abdominal motion.
- **WL-0094 [P1]** Prevent wall corrections from appearing as impossible instantaneous reversals.
- **WL-0095 [P1]** Tune turn damping separately for slender and deep-bodied fish.
- **WL-0096 [P1]** Keep animations continuous across simulation-speed changes and quality-tier switches.
- **WL-0097 [P1]** Use swimming-effort history to smooth fin motion through short frame spikes.
- **WL-0098 [P1]** Give fry shorter coordinated stroke sequences rather than adult rhythms.
- **WL-0099 [P1]** Allow mild individual locomotor signatures that persist across save reloads.
- **WL-0100 [P1]** Measure perceived animation improvement with side-by-side seeded behavior clips.

<a id="topic-05"></a>

### 05. Habitat use and navigation — WL-0101–WL-0125

**Priority:** P1. **Sources:** [shaders-godot/godot-project/scripts/fish_depth_bands.gd](../shaders-godot/godot-project/scripts/fish_depth_bands.gd); [shaders-godot/godot-project/scripts/fish.gd](../shaders-godot/godot-project/scripts/fish.gd); [shaders-godot/godot-project/scripts/world.gd](../shaders-godot/godot-project/scripts/world.gd).

**Review intent:** Extend the existing shared depth contract into more convincing local habitat choices.

- **WL-0101 [P1]** Bias resting sites toward cover appropriate to each species.
- **WL-0102 [P1]** Make surface dwellers patrol the meniscus without repeatedly leaving their band.
- **WL-0103 [P1]** Let bottom fish follow substrate contours rather than a flat depth target.
- **WL-0104 [P1]** Account for usable corridors when choosing routes through dense vegetation.
- **WL-0105 [P1]** Prefer curved detours around hardscape over repeated collision corrections.
- **WL-0106 [P1]** Let fish remember several shelter locations instead of one nearest plant.
- **WL-0107 [P1]** Distinguish safe shelter from dense vegetation containing an active predator.
- **WL-0108 [P1]** Use local flow strength when choosing energy-efficient holding positions.
- **WL-0109 [P1]** Let hypoxia override preferred depth smoothly and visibly.
- **WL-0110 [P1]** Return fish gradually to preferred habitat after emergency conditions recover.
- **WL-0111 [P1]** Avoid crowding every shelter-seeking animal into the same cover point.
- **WL-0112 [P1]** Give territorial residents stable home areas compatible with vessel geometry.
- **WL-0113 [P1]** Account for adult body width when judging traversable gaps.
- **WL-0114 [P1]** Let fry use smaller gaps that adults cannot enter.
- **WL-0115 [P1]** Recognize overhangs and wood arches as useful shelter affordances.
- **WL-0116 [P1]** Prevent repeated destination selection inside unreachable hardscape.
- **WL-0117 [P1]** Add species-specific tolerance for exposed crossings between cover patches.
- **WL-0118 [P1]** Give exploratory fish occasional purposeful excursions beyond their habitual zone.
- **WL-0119 [P1]** Let established residents inspect recently placed objects before adopting them.
- **WL-0120 [P1]** Reduce edge-following loops when the interior offers a usable route.
- **WL-0121 [P1]** Distinguish plant-canopy feeding from substrate feeding in target placement.
- **WL-0122 [P1]** Keep navigation intent stable across small fluctuations in plant biomass.
- **WL-0123 [P1]** Make disturbance recovery depend on the distance to available shelter.
- **WL-0124 [P1]** Measure depth occupancy separately during resting, feeding, and threat events.
- **WL-0125 [P1]** Compare habitat choice across box, hexagonal, cylindrical, and spherical tanks.

<a id="topic-06"></a>

### 06. Schools and collective movement — WL-0126–WL-0150

**Priority:** P1. **Sources:** [shaders-godot/godot-project/scripts/motion_school.gd](../shaders-godot/godot-project/scripts/motion_school.gd); [shaders-godot/godot-project/dev/fish_behaviour_probe.tscn](../shaders-godot/godot-project/dev/fish_behaviour_probe.tscn).

**Review intent:** Improve existing collective motion without reinstating identical speed rhythms.

- **WL-0126 [P1]** Keep personal swimming bouts while preserving recognizable group direction.
- **WL-0127 [P1]** Vary nearest-neighbor spacing with threat, feeding, and resting context.
- **WL-0128 [P1]** Allow loose shoals to become tighter schools during credible disturbances.
- **WL-0129 [P1]** Give group turns a short propagation delay instead of simultaneous rotation.
- **WL-0130 [P1]** Let group leaders change through context rather than permanent hidden rank.
- **WL-0131 [P1]** Reduce schooling attraction across impenetrable wood or rock barriers.
- **WL-0132 [P1]** Keep mixed species near each other without merging all fish into one cloud.
- **WL-0133 [P1]** Allow a few temporary stragglers with believable catch-up behavior.
- **WL-0134 [P1]** Let split groups rejoin through visible route choices.
- **WL-0135 [P1]** Create calmer shoal spacing when residents are well fed and secure.
- **WL-0136 [P1]** Make nighttime grouping species-dependent instead of universally dense.
- **WL-0137 [P1]** Let juveniles school more tightly than confident adults where appropriate.
- **WL-0138 [P1]** Reduce school compression near corners before fish visually overlap.
- **WL-0139 [P1]** Let feeding schools disperse toward multiple available food patches.
- **WL-0140 [P1]** Preserve safe separation during synchronized escape acceleration.
- **WL-0141 [P1]** Use visual-neighbor limits so distant fish do not coordinate perfectly.
- **WL-0142 [P1]** Allow large individuals to occupy positions suited to their turning radius.
- **WL-0143 [P1]** Prevent school-centroid pursuit from trapping fish inside plant clusters.
- **WL-0144 [P1]** Let cautious individuals pull a group toward cover through bounded influence.
- **WL-0145 [P1]** Make alarm contagion decay after the initiating threat disappears.
- **WL-0146 [P1]** Track group cohesion and neighbor lockstep as separate quality measures.
- **WL-0147 [P1]** Expose school-size preferences in species descriptions with honest simplification labels.
- **WL-0148 [P1]** Check group movement at both low and high resident counts.
- **WL-0149 [P1]** Give lone schooling fish observable insecurity without forcing permanent panic.
- **WL-0150 [P1]** Support natural group dissolution when food, territory, or sleep takes priority.

<a id="topic-07"></a>

### 07. Social encounters and territories — WL-0151–WL-0175

**Priority:** P2. **Sources:** [shaders-godot/godot-project/scripts/fish.gd](../shaders-godot/godot-project/scripts/fish.gd); [shaders-godot/godot-project/scripts/mind_contagion.gd](../shaders-godot/godot-project/scripts/mind_contagion.gd).

**Review intent:** Make social behavior legible and bounded; pair visible encounters with tracked consequences.

- **WL-0151 [P2]** Use approach, display, chase, and disengage stages for territorial confrontations.
- **WL-0152 [P2]** Let weaker rivals retreat before contact when threat assessment warrants it.
- **WL-0153 [P2]** Give territory boundaries soft negotiation zones rather than sharp invisible walls.
- **WL-0154 [P2]** Keep aggression recovery long enough to avoid endless repeated charges.
- **WL-0155 [P2]** Let habitat quality influence territory choice alongside empty space.
- **WL-0156 [P2]** Distinguish courtship pursuit from harassment through duration and recipient response.
- **WL-0157 [P2]** Allow familiar neighbors closer approach than unknown newcomers.
- **WL-0158 [P2]** Make subordinate fish choose routes around dominant residents.
- **WL-0159 [P2]** Limit pursuit distance so every territorial dispute does not cross the tank.
- **WL-0160 [P2]** Give displays species-specific posture rather than a universal speed increase.
- **WL-0161 [P2]** Let resource-rich sites create temporary competition without permanent hostility.
- **WL-0162 [P2]** Preserve nonaggressive passing behavior when two residents share a corridor.
- **WL-0163 [P2]** Use interrupted feeding as a visible consequence of repeated intimidation.
- **WL-0164 [P2]** Let juveniles remain socially peripheral without being permanently excluded.
- **WL-0165 [P2]** Allow pair bonds to weaken after prolonged separation or repeated rejection.
- **WL-0166 [P2]** Represent reunion through approach and reduced vigilance rather than dialogue alone.
- **WL-0167 [P2]** Make newcomers undergo a settling period before stable social roles emerge.
- **WL-0168 [P2]** Show social tension in habitat occupancy before health deteriorates.
- **WL-0169 [P2]** Let overcrowding increase encounter frequency without scaling aggression unboundedly.
- **WL-0170 [P2]** Avoid cyclic chase chains in three-way dominance situations.
- **WL-0171 [P2]** Give each species clear limits on interspecies social attraction.
- **WL-0172 [P2]** Allow protective parents to tolerate their own nearby fry.
- **WL-0173 [P2]** Let a safe divider or shelter reduce social pressure measurably.
- **WL-0174 [P2]** Include encounter summaries in journals only when relationships materially change.
- **WL-0175 [P2]** Evaluate social scenes with three or more individuals to expose pairwise artifacts.

<a id="topic-08"></a>

### 08. Age, health, and lived bodies — WL-0176–WL-0200

**Priority:** P2. **Sources:** [shaders-godot/godot-project/scripts/fish.gd](../shaders-godot/godot-project/scripts/fish.gd); [shaders-godot/godot-project/scripts/fish_journal.gd](../shaders-godot/godot-project/scripts/fish_journal.gd); [shaders-godot/godot-project/scripts/sim_driver.gd](../shaders-godot/godot-project/scripts/sim_driver.gd).

**Review intent:** Refine existing lifecycle presentation and avoid unexplained disappearance.

- **WL-0176 [P2]** Give fry, juveniles, adults, and seniors recognizable proportions and activity ranges.
- **WL-0177 [P2]** Separate normal aging from acute illness in visible movement cues.
- **WL-0178 [P2]** Let recovery from starvation restore body condition gradually.
- **WL-0179 [P2]** Make damaged fins regrow through small visible stages.
- **WL-0180 [P2]** Tie physical growth to assimilated food rather than age alone.
- **WL-0181 [P2]** Make growth rates respond to crowding without permanently stunting every offspring.
- **WL-0182 [P2]** Track cumulative stress exposure separately from current stress.
- **WL-0183 [P2]** Let healthy aging reduce stamina before it affects basic locomotion.
- **WL-0184 [P2]** Provide plain-language cause summaries for declining health.
- **WL-0185 [P2]** Show oxygen distress before lethal damage accumulates.
- **WL-0186 [P2]** Differentiate reproductive exhaustion from disease or hunger.
- **WL-0187 [P2]** Let injured fish favor safer routes and avoid costly displays.
- **WL-0188 [P2]** Give resting behavior a clear distinction from an incapacitated animal.
- **WL-0189 [P2]** Make environmental recovery produce believable improvement over time.
- **WL-0190 [P2]** Avoid uniformly shrinking all body parts when an animal loses condition.
- **WL-0191 [P2]** Preserve meaningful physical condition across save and offline updates.
- **WL-0192 [P2]** Record first adulthood as a journal milestone for followed individuals.
- **WL-0193 [P2]** Keep individual birth dates independent from the tank creation date.
- **WL-0194 [P2]** Use lifespan ranges rather than synchronized death at one exact age.
- **WL-0195 [P2]** Let keeper assistance improve survival without guaranteeing immortality.
- **WL-0196 [P2]** Offer clear controls for gentler mortality pacing in cozy play.
- **WL-0197 [P2]** Treat body anomalies as bounded variation with appropriate movement consequences.
- **WL-0198 [P2]** Show natural senescence without excessive alarming notification volume.
- **WL-0199 [P2]** Allow memorial entries to retain appearance, lineage, and meaningful relationships.
- **WL-0200 [P2]** Audit every death path for consistent removal, diary, and ecological consequences.

<a id="topic-09"></a>

### 09. Courtship and reproductive readiness — WL-0201–WL-0225

**Priority:** P1. **Sources:** [shaders-godot/godot-project/scripts/fish_life_bouts.gd](../shaders-godot/godot-project/scripts/fish_life_bouts.gd); [shaders-godot/godot-project/scripts/fish.gd](../shaders-godot/godot-project/scripts/fish.gd).

**Review intent:** Build on existing per-species dances and livebearer displays; improve eligibility and outcomes.

- **WL-0201 [P1]** Show readiness through posture and habitat choice before a spawn event.
- **WL-0202 [P1]** Make receptive partners visibly respond to a successful display.
- **WL-0203 [P1]** Give rejected suitors a brief recovery cooldown instead of immediate retry.
- **WL-0204 [P1]** Keep courtship energy costs visible in subsequent feeding and resting.
- **WL-0205 [P1]** Separate mate discovery from pair compatibility and successful fertilization.
- **WL-0206 [P1]** Let mature females decline pursuit under unsuitable environmental conditions.
- **WL-0207 [P1]** Limit repeated pursuit of the same unreceptive partner.
- **WL-0208 [P1]** Bias displays toward safe open spaces suited to the species.
- **WL-0209 [P1]** Make courtship duration respond to disturbance without restarting indefinitely.
- **WL-0210 [P1]** Preserve current pregnancy when decorative courtship is interrupted.
- **WL-0211 [P1]** Let territorial nesting preparation precede partner invitation.
- **WL-0212 [P1]** Use species-specific light and temperature windows for reproductive readiness.
- **WL-0213 [P1]** Expose the strongest current breeding blocker in the resident inspector.
- **WL-0214 [P1]** Distinguish insufficient maturity from incompatible sex or breeding strategy.
- **WL-0215 [P1]** Require compatible reproductive anatomy even for ornamental hybrid experiments.
- **WL-0216 [P1]** Let mate preferences vary modestly between individuals.
- **WL-0217 [P1]** Give pair-bonding species a durable relationship state through breeding attempts.
- **WL-0218 [P1]** Make display coloration fade after disengagement rather than snap off.
- **WL-0219 [P1]** Let nearby aggressive residents interrupt a display through observable events.
- **WL-0220 [P1]** Avoid simultaneous duplicate fertilization when both parents emit breeding events.
- **WL-0221 [P1]** Make breeding cooldowns describe recovery rather than unexplained denial timers.
- **WL-0222 [P1]** Provide a quiet observation cue when a pair begins nest preparation.
- **WL-0223 [P1]** Track attempt-to-success ratios to identify overly strict or permissive gates.
- **WL-0224 [P1]** Evaluate courtship under normal stocking rather than only forced test conditions.
- **WL-0225 [P1]** Offer a breeding observation view showing both partners without obstructing interaction.

<a id="topic-10"></a>

### 10. Eggs, gestation, and fry survival — WL-0226–WL-0250

**Priority:** P1. **Sources:** [shaders-godot/godot-project/scripts/egg.gd](../shaders-godot/godot-project/scripts/egg.gd); [shaders-godot/godot-project/scripts/sim_driver.gd](../shaders-godot/godot-project/scripts/sim_driver.gd).

**Review intent:** The inspected egg path uses a shared 30-second incubation and four-cell visual clusters; brood release paths cap counts at four. Treat these as design levers, not proven bugs.

- **WL-0226 [P1]** Replace universal egg incubation with bounded species-specific development profiles.
- **WL-0227 [P1]** Scale incubation progress with temperature while preventing unsafe numerical jumps.
- **WL-0228 [P1]** Make oxygen conditions affect embryo survival separately from hatch timing.
- **WL-0229 [P1]** Align displayed egg-cluster count with the number of represented offspring.
- **WL-0230 [P1]** State clearly when a visual clutch represents multiple biological eggs.
- **WL-0231 [P1]** Track embryos individually where variation meaningfully affects survival or lineage.
- **WL-0232 [P1]** Attach eggs to actual leaf surfaces rather than plant-top approximations.
- **WL-0233 [P1]** Keep eggs attached when their chosen plant moves or grows.
- **WL-0234 [P1]** Define outcomes when an egg-bearing leaf dies or is trimmed.
- **WL-0235 [P1]** Differentiate adhesive eggs, scattered eggs, and nest-bound eggs visually.
- **WL-0236 [P1]** Make failed eggs visibly stop developing before their eventual dissolution.
- **WL-0237 [P1]** Give parent fanning a measurable local incubation benefit.
- **WL-0238 [P1]** Keep parental guarding duration consistent with the current clutch development stage.
- **WL-0239 [P1]** Give hatching a short emergence sequence instead of immediate adult-like motion.
- **WL-0240 [P1]** Add a yolk-dependent fry stage before active independent feeding.
- **WL-0241 [P1]** Match first-food needs to fry size and feeding anatomy.
- **WL-0242 [P1]** Let cover quality affect early survival without guaranteeing total refuge.
- **WL-0243 [P1]** Distinguish gestation age from ordinary creature age in saves and inspectors.
- **WL-0244 [P1]** Keep pregnancy and brood progress continuous across scene reloads.
- **WL-0245 [P1]** Reconcile direct livebearer birth and gestation release paths under one lifecycle contract.
- **WL-0246 [P1]** Give siblings independent inherited trait samples where the model supports them.
- **WL-0247 [P1]** Explain hard brood-count limits as simulation representation rather than natural fecundity.
- **WL-0248 [P1]** Preserve parent identifiers from fertilization through eggs and newborn registration.
- **WL-0249 [P1]** Record clutch outcomes including laid, hatched, lost, and surviving juveniles.
- **WL-0250 [P1]** Evaluate reproduction over several generations rather than one successful spawn.

<a id="topic-11"></a>

### 11. Inheritance and lineage — WL-0251–WL-0275

**Priority:** P2. **Sources:** [shaders-godot/godot-project/scripts/fish.gd](../shaders-godot/godot-project/scripts/fish.gd); [shaders-godot/godot-project/scripts/library_panel.gd](../shaders-godot/godot-project/scripts/library_panel.gd); [shaders-godot/godot-project/scripts/sim_driver.gd](../shaders-godot/godot-project/scripts/sim_driver.gd).

**Review intent:** Extend existing genomes and lineage records; keep ancestry distinct from learned experience.

- **WL-0251 [P2]** Separate inherited temperament from behavior learned during an individual's life.
- **WL-0252 [P2]** Keep parent identity stable when creatures are renamed or moved between tanks.
- **WL-0253 [P2]** Display inherited appearance landmarks alongside actual juvenile and adult portraits.
- **WL-0254 [P2]** Model dominance explicitly for traits that should not blend arithmetically.
- **WL-0255 [P2]** Bound mutations so offspring retain a functional species-compatible body plan.
- **WL-0256 [P2]** Prevent color mutation from overwhelming parent palette identity each generation.
- **WL-0257 [P2]** Show uncertain ancestry honestly when importing strains without parent records.
- **WL-0258 [P2]** Distinguish a genetic strain from one specific animal in library actions.
- **WL-0259 [P2]** Track kinship sufficiently to support existing inbreeding consequences consistently.
- **WL-0260 [P2]** Explain reduced fecundity in related pairs without exposing raw implementation fields.
- **WL-0261 [P2]** Let selective breeding preserve attractive traits without monotonically maximizing every stat.
- **WL-0262 [P2]** Separate ornamental traits from metabolic and locomotor tradeoffs.
- **WL-0263 [P2]** Preserve viable hybrid classifications across save migrations.
- **WL-0264 [P2]** Keep phenotype development reproducible for the same saved genome and age.
- **WL-0265 [P2]** Expose family resemblance through a compact sibling comparison view.
- **WL-0266 [P2]** Let offspring inherit species-appropriate trait bounds rather than unrestricted parent extremes.
- **WL-0267 [P2]** Avoid copying acquired wounds or transient stress into newborn genomes.
- **WL-0268 [P2]** Distinguish socially transmitted vocabulary from biological inheritance in journal descriptions.
- **WL-0269 [P2]** Track generation depth without traversing the entire family graph every frame.
- **WL-0270 [P2]** Maintain archived ancestor summaries after live parent nodes disappear.
- **WL-0271 [P2]** Show breeder-selected traits separately from emergent natural selection outcomes.
- **WL-0272 [P2]** Offer a plain explanation for infertility, incompatibility, or nonviable offspring.
- **WL-0273 [P2]** Make strain sharing round-trip all appearance traits visible in the preview.
- **WL-0274 [P2]** Compare diversity trends over multiple generations in isolated breeding scenarios.
- **WL-0275 [P2]** Keep lineage export small by referencing shared ancestor records once.

<a id="topic-12"></a>

### 12. Food, foraging, and nutrition — WL-0276–WL-0300

**Priority:** P1. **Sources:** [shaders-godot/godot-project/scripts/food_web_trace.gd](../shaders-godot/godot-project/scripts/food_web_trace.gd); [shaders-godot/godot-project/scripts/sim_driver.gd](../shaders-godot/godot-project/scripts/sim_driver.gd); [shaders-godot/godot-project/scripts/fish.gd](../shaders-godot/godot-project/scripts/fish.gd).

**Review intent:** Build on current feed types and food-web tracing; prioritize causal meals over decorative feeding.

- **WL-0276 [P1]** Match food size to mouth size so fry cannot swallow oversized pellets.
- **WL-0277 [P1]** Give floating, sinking, and adhered foods distinct useful feeding niches.
- **WL-0278 [P1]** Make food detection depend on distance, turbidity, and species sensing.
- **WL-0279 [P1]** Let fish switch feeding targets when their current pellet is consumed.
- **WL-0280 [P1]** Reserve bite claims briefly to prevent several animals eating one particle.
- **WL-0281 [P1]** Distinguish attempted bites from consumed mass in food-web diagnostics.
- **WL-0282 [P1]** Let grazing provide small sustained intake rather than full-meal rewards.
- **WL-0283 [P1]** Show satiated fish leaving a feeding cloud before hungry companions.
- **WL-0284 [P1]** Give dominant feeders a cost when defending more food than they need.
- **WL-0285 [P1]** Provide multiple feeding locations to reduce avoidable competitive exclusion.
- **WL-0286 [P1]** Use species-appropriate diet quality as well as food quantity.
- **WL-0287 [P1]** Separate immediate hunger relief from longer-term body-condition recovery.
- **WL-0288 [P1]** Keep feeding calories and subsequent metabolic waste traceable.
- **WL-0289 [P1]** Show uneaten food becoming detritus through an observable decay sequence.
- **WL-0290 [P1]** Make water-current transport influence where feeding opportunities gather.
- **WL-0291 [P1]** Let bottom feeders investigate settled food before sediment sifting resumes.
- **WL-0292 [P1]** Provide an estimated portion based on resident biomass rather than head count.
- **WL-0293 [P1]** Explain why a selected food may not suit the current fry population.
- **WL-0294 [P1]** Let live-food escapes create brief pursuit rather than generic pellet behavior.
- **WL-0295 [P1]** Keep grazer nutrition dependent on actual available film or algae.
- **WL-0296 [P1]** Avoid spawning edible resources inside unreachable hardscape.
- **WL-0297 [P1]** Give filter capture of food an explicit accounting outcome.
- **WL-0298 [P1]** Make overfeeding consequences delayed enough to read as a cycle.
- **WL-0299 [P1]** Show which residents missed recent meals in an optional care summary.
- **WL-0300 [P1]** Measure distribution of intake across residents instead of only total consumption.

<a id="topic-13"></a>

### 13. Predation and trophic relationships — WL-0301–WL-0325

**Priority:** P2. **Sources:** [shaders-godot/godot-project/scripts/sim_driver.gd](../shaders-godot/godot-project/scripts/sim_driver.gd); [shaders-godot/godot-project/scripts/fish.gd](../shaders-godot/godot-project/scripts/fish.gd); [shaders-godot/godot-project/scripts/food_web_trace.gd](../shaders-godot/godot-project/scripts/food_web_trace.gd).

**Review intent:** Make existing predator-prey dynamics comprehensible and sustainable across scenarios.

- **WL-0301 [P2]** Use prey size and predator mouth capacity in eligibility decisions.
- **WL-0302 [P2]** Require a reachable encounter before predation succeeds.
- **WL-0303 [P2]** Give prey an escape opportunity shaped by cover and reaction distance.
- **WL-0304 [P2]** Let predators stop hunting after sufficient intake rather than kill continuously.
- **WL-0305 [P2]** Separate pursuit energy cost from the nutritional reward of capture.
- **WL-0306 [P2]** Make ambush predators favor concealment and short bursts.
- **WL-0307 [P2]** Make active hunters patrol plausible routes between prey-rich locations.
- **WL-0308 [P2]** Keep refuge value dependent on gap size and predator anatomy.
- **WL-0309 [P2]** Show prey vigilance increasing after observed nearby attacks.
- **WL-0310 [P2]** Let predator hunger influence risk-taking without overriding physical constraints.
- **WL-0311 [P2]** Distinguish scavenging dead material from attacking live residents.
- **WL-0312 [P2]** Make snail-shell protection vary by predator feeding strategy.
- **WL-0313 [P2]** Prevent population-control mechanics from selecting victims across the whole tank.
- **WL-0314 [P2]** Let abundant alternative food reduce pressure on vulnerable young.
- **WL-0315 [P2]** Provide stocking previews that identify likely predatory relationships.
- **WL-0316 [P2]** Show cohort survival curves to clarify losses after a breeding boom.
- **WL-0317 [P2]** Keep dead biomass entering the detrital loop consistently.
- **WL-0318 [P2]** Let predator removal change prey behavior before populations visibly rebound.
- **WL-0319 [P2]** Avoid perfectly periodic predator-prey cycles caused by synchronized spawn timers.
- **WL-0320 [P2]** Preserve rare prey refuges so local extinction is not inevitable by default.
- **WL-0321 [P2]** Let trophic pressure differ among tanks with equal population counts.
- **WL-0322 [P2]** Record significant captures sparingly without flooding the chronicle.
- **WL-0323 [P2]** Offer gentler predation settings with clear ecological consequences.
- **WL-0324 [P2]** Evaluate food-web stability after the loss of one key predator.
- **WL-0325 [P2]** Explain extirpation as an observed outcome with likely contributing causes.

<a id="topic-14"></a>

### 14. Shrimp and crustacean life — WL-0326–WL-0350

**Priority:** P2. **Sources:** [shaders-godot/godot-project/scripts/shrimp.gd](../shaders-godot/godot-project/scripts/shrimp.gd); [shaders-godot/godot-project/scripts/sim_driver.gd](../shaders-godot/godot-project/scripts/sim_driver.gd); [shaders-godot/godot-project/scripts/fauna_voxel_builder.gd](../shaders-godot/godot-project/scripts/fauna_voxel_builder.gd).

**Review intent:** Refine existing body-plan geometry, grazing, brood release, and locomotion.

- **WL-0326 [P2]** Make walking legs contact the traversed surface rather than cycle in air.
- **WL-0327 [P2]** Let antennae sample ahead of movement and avoid crossing the head excessively.
- **WL-0328 [P2]** Differentiate grazing pauses from alert immobility through claw motion.
- **WL-0329 [P2]** Use surface normals to orient shrimp on leaves, wood, and substrate.
- **WL-0330 [P2]** Give climbing a visible transition at the edge of a leaf.
- **WL-0331 [P2]** Let shrimp choose biofilm patches according to actual food availability.
- **WL-0332 [P2]** Make tail-flick escapes directional and followed by a short settling period.
- **WL-0333 [P2]** Scale escape distance with body size and nearby obstacles.
- **WL-0334 [P2]** Show berried eggs under the abdomen with restrained species tint.
- **WL-0335 [P2]** Differentiate brood development from simple belly enlargement.
- **WL-0336 [P2]** Give newborn shrimp recognizable proportions and sheltered first habitats.
- **WL-0337 [P2]** Keep sibling trait variation reproducible through simulation-owned random streams.
- **WL-0338 [P2]** Make molting a brief vulnerable stage with useful shelter-seeking behavior.
- **WL-0339 [P2]** Leave shed exoskeletons as temporary visible recyclable material.
- **WL-0340 [P2]** Let mineral shortage affect molt success with clear early care cues.
- **WL-0341 [P2]** Avoid making every shrimp climb toward the highest available object.
- **WL-0342 [P2]** Make social grazing aggregations loose rather than fish-like schooling.
- **WL-0343 [P2]** Give fan-feeding forms current-facing posture distinct from claw grazers.
- **WL-0344 [P2]** Let larger crustaceans use claws with species-appropriate reach and restraint.
- **WL-0345 [P2]** Keep long-body morph feet and facial appendages attached during animation.
- **WL-0346 [P2]** Show cleaning interactions as brief mutual encounters where biologically appropriate.
- **WL-0347 [P2]** Let poor oxygen interrupt grazing before severe health decline.
- **WL-0348 [P2]** Balance shrimp reproduction against edible surface area rather than tank count alone.
- **WL-0349 [P2]** Make colony age structure visible in a simple brood-and-juvenile summary.
- **WL-0350 [P2]** Compare crustacean motion on all supported body plans in live lighting.

<a id="topic-15"></a>

### 15. Snails and benthic detail — WL-0351–WL-0375

**Priority:** P2. **Sources:** [shaders-godot/godot-project/scripts/snail_shell.gd](../shaders-godot/godot-project/scripts/snail_shell.gd); [shaders-godot/godot-project/scripts/snail_surface.gd](../shaders-godot/godot-project/scripts/snail_surface.gd); [shaders-godot/godot-project/scripts/snail_egg.gd](../shaders-godot/godot-project/scripts/snail_egg.gd).

**Review intent:** Extend recorded shell and corner-transfer work into surface ecology and lifecycle readability.

- **WL-0351 [P2]** Make snail foot contact readable without exposing a floating shell gap.
- **WL-0352 [P2]** Keep eyestalks oriented ahead during wall-to-wall transitions.
- **WL-0353 [P2]** Let shell weight influence turning speed without rotating the foot unnaturally.
- **WL-0354 [P2]** Vary grazing speed according to local edible film density.
- **WL-0355 [P2]** Leave a subtle temporary cleaned trail where film is actually consumed.
- **WL-0356 [P2]** Make slime visibility depend on viewing angle and restrained contrast.
- **WL-0357 [P2]** Differentiate substrate crawling from glass adhesion in foot posture.
- **WL-0358 [P2]** Keep round-vessel movement continuous across path wrapping boundaries.
- **WL-0359 [P2]** Show shell growth at the aperture rather than uniform whole-shell expansion.
- **WL-0360 [P2]** Let mineral deficiency affect new shell material before established shell.
- **WL-0361 [P2]** Make repaired shell chips remain subtle individual landmarks.
- **WL-0362 [P2]** Give egg clutches species-appropriate attachment surfaces and organization.
- **WL-0363 [P2]** Make hatchling shell proportions distinct from scaled adult spires.
- **WL-0364 [P2]** Keep shell patterns continuous around growing whorls.
- **WL-0365 [P2]** Let predation risk trigger retraction before contact when sensed.
- **WL-0366 [P2]** Differentiate sleeping or retracted snails from dead individuals.
- **WL-0367 [P2]** Prevent film-seeking routes from entering the dry region above the waterline.
- **WL-0368 [P2]** Give corner transfers enough duration to read as deliberate locomotion.
- **WL-0369 [P2]** Avoid detached slime chords across the tank interior.
- **WL-0370 [P2]** Let shell diversity influence recognition without extreme silhouette noise.
- **WL-0371 [P2]** Measure glass-cleaning benefits in the same surface resource model.
- **WL-0372 [P2]** Show egg and hatchling counts separately from adult snail counts.
- **WL-0373 [P2]** Let population pressure emerge from food scarcity before arbitrary spawn suppression.
- **WL-0374 [P2]** Keep library shell previews synchronized with live inherited pattern parameters.
- **WL-0375 [P2]** Evaluate snail continuity during camera close-ups as well as wide views.

<a id="topic-16"></a>

### 16. Reef residents and saltwater ecology — WL-0376–WL-0400

**Priority:** P2. **Sources:** [shaders-godot/godot-project/scripts/coral.gd](../shaders-godot/godot-project/scripts/coral.gd); [shaders-godot/godot-project/scripts/clam.gd](../shaders-godot/godot-project/scripts/clam.gd); [shaders-godot/godot-project/scripts/water_chemistry.gd](../shaders-godot/godot-project/scripts/water_chemistry.gd).

**Review intent:** The reef path is explicitly proxy chemistry; improve presentation and consistency without implying full marine accuracy.

- **WL-0376 [P2]** Label reef chemistry proxies clearly beside their gameplay implications.
- **WL-0377 [P2]** Give coral polyps flow-dependent extension rather than constant uniform opening.
- **WL-0378 [P2]** Make nighttime coral emission selective instead of illuminating every colony equally.
- **WL-0379 [P2]** Show bleaching as progressive loss of pigment across a colony.
- **WL-0380 [P2]** Let surviving coral recover gradually after the stressor is removed.
- **WL-0381 [P2]** Distinguish tissue death from reversible bleaching visually.
- **WL-0382 [P2]** Give coral forms recognizable branching, plating, and mound silhouettes.
- **WL-0383 [P2]** Separate photosynthetic growth from particulate feeding contributions.
- **WL-0384 [P2]** Let colony shading affect growth without recalculating every branch every frame.
- **WL-0385 [P2]** Show coral competition as local contact stress instead of global penalties.
- **WL-0386 [P2]** Make clam shell opening respond to actual filtration and disturbance.
- **WL-0387 [P2]** Orient filter-feeding clams toward useful flow where placement allows.
- **WL-0388 [P2]** Show filtration reducing a traced suspended resource rather than cosmetic particles alone.
- **WL-0389 [P2]** Give clam mantle color identity that survives underwater palette grading.
- **WL-0390 [P2]** Prevent clam pumping from synchronizing across the whole tank.
- **WL-0391 [P2]** Represent salinity disturbance separately from freshwater hardness.
- **WL-0392 [P2]** Keep marine stocking compatibility visible during scenario selection.
- **WL-0393 [P2]** Avoid presenting freshwater substrate assumptions as marine care advice.
- **WL-0394 [P2]** Give anemone motion slower, cohesive waves instead of independent tentacle noise.
- **WL-0395 [P2]** Let reef fish use crevices sized to their bodies.
- **WL-0396 [P2]** Show reef-night behavior distinct from planted-tank sleep routines.
- **WL-0397 [P2]** Give cleanup organisms limited ecological roles instead of universal waste removal.
- **WL-0398 [P2]** Make reef nutrient shortages visible before coral growth ceases entirely.
- **WL-0399 [P2]** Evaluate thermal stress under both sudden spikes and prolonged mild exposure.
- **WL-0400 [P2]** Document which reef parameters are normalized gameplay values and which have units.

<a id="topic-17"></a>

### 17. Plant silhouettes and aquascape composition — WL-0401–WL-0425

**Priority:** P1. **Sources:** [shaders-godot/godot-project/scripts/plant.gd](../shaders-godot/godot-project/scripts/plant.gd); [shaders-godot/godot-project/scripts/scape_composition.gd](../shaders-godot/godot-project/scripts/scape_composition.gd); [shaders-godot/godot-project/scripts/world.gd](../shaders-godot/godot-project/scripts/world.gd).

**Review intent:** Preserve recent ribbon and LOD refinements while improving plant identity and aquarium composition.

- **WL-0401 [P1]** Give stem, rosette, ribbon, carpet, moss, and floater forms distinct massing.
- **WL-0402 [P1]** Keep leaf tips connected and recognizable at reduced foliage fidelity.
- **WL-0403 [P1]** Vary internode spacing within plausible species ranges.
- **WL-0404 [P1]** Arrange leaves around stems with stable botanical patterns rather than random clutter.
- **WL-0405 [P1]** Give rosettes clear crown centers and outward leaf arcs.
- **WL-0406 [P1]** Keep carpet plants low enough to preserve foreground substrate readability.
- **WL-0407 [P1]** Reserve tall plant masses for intentional background and side framing.
- **WL-0408 [P1]** Protect open swimming lanes when procedural planting becomes dense.
- **WL-0409 [P1]** Use leaf-size hierarchy to prevent every plant reading as equal noise.
- **WL-0410 [P1]** Let young leaves differ in angle and size before reaching maturity.
- **WL-0411 [P1]** Preserve recognizable ribbon curves when plants sway in currents.
- **WL-0412 [P1]** Reduce repeated identical plant silhouettes within a visible cluster.
- **WL-0413 [P1]** Keep species color masses coherent while allowing small individual variation.
- **WL-0414 [P1]** Show root crowns resting in substrate rather than hovering above it.
- **WL-0415 [P1]** Use hardscape scale to establish depth without crowding the hero fish region.
- **WL-0416 [P1]** Place red accent plants sparingly where they support the focal composition.
- **WL-0417 [P1]** Make floating plant shadows patchy enough to leave readable water-column windows.
- **WL-0418 [P1]** Preserve negative space intentionally in sparse Iwagumi scenarios.
- **WL-0419 [P1]** Keep jungle density rich without hiding all behavioral interactions.
- **WL-0420 [P1]** Make trimming previews show the resulting silhouette before committing.
- **WL-0421 [P1]** Let plant groups form connected visual masses rather than scattered confetti.
- **WL-0422 [P1]** Give emergent stems a clear crossing of the water surface.
- **WL-0423 [P1]** Keep plant library previews representative of mature live growth forms.
- **WL-0424 [P1]** Compare scape corridors using actual body-size clearance as well as coarse occupancy.
- **WL-0425 [P1]** Offer composition hints explaining one specific spatial issue at a time.

<a id="topic-18"></a>

### 18. Plant growth, competition, and succession — WL-0426–WL-0450

**Priority:** P2. **Sources:** [shaders-godot/godot-project/scripts/plant.gd](../shaders-godot/godot-project/scripts/plant.gd); [shaders-godot/godot-project/scripts/plant_ecology_adapter.gd](../shaders-godot/godot-project/scripts/plant_ecology_adapter.gd); [shaders-godot/godot-project/scripts/floating_plant.gd](../shaders-godot/godot-project/scripts/floating_plant.gd).

**Review intent:** Extend existing growth, shade competition, melt, propagation, and resource accounting.

- **WL-0426 [P2]** Make new growth appear at appropriate meristems rather than arbitrary existing surfaces.
- **WL-0427 [P2]** Let light shortage lengthen or reorient new growth within species limits.
- **WL-0428 [P2]** Differentiate nutrient deficiency patterns by old versus newly growing leaves.
- **WL-0429 [P2]** Keep deficiency colors tied to actual modeled resources rather than generic weakness.
- **WL-0430 [P2]** Make pruning remove corresponding biomass and nutrient stores consistently.
- **WL-0431 [P2]** Let stem cuttings develop roots before behaving like established plants.
- **WL-0432 [P2]** Give runner offspring a visible connection to their parent during establishment.
- **WL-0433 [P2]** Let floating plants respond to crowding with bounded reproduction slowdown.
- **WL-0434 [P2]** Show older leaves declining before the entire plant disappears.
- **WL-0435 [P2]** Make melt recovery retain a plausible surviving crown or root system.
- **WL-0436 [P2]** Prevent immediate healthy regrowth after irreversible total plant death.
- **WL-0437 [P2]** Let competition include local light access as well as neighbor height.
- **WL-0438 [P2]** Distinguish water-column feeders from root feeders in uptake routes.
- **WL-0439 [P2]** Keep floater uptake from double-counting substrate nutrients.
- **WL-0440 [P2]** Let root growth follow nutrient patches gradually rather than instant optimization.
- **WL-0441 [P2]** Show flowering only when species and resource conditions support it.
- **WL-0442 [P2]** Make detached leaves contribute traced detritus instead of disappearing without mass.
- **WL-0443 [P2]** Provide growth-rate summaries over useful observation windows.
- **WL-0444 [P2]** Let algae shading slow plants through a visible local mechanism.
- **WL-0445 [P2]** Keep tall plants from exploiting unlimited light through ceiling clipping.
- **WL-0446 [P2]** Use establishment time to differentiate newly planted and mature specimens.
- **WL-0447 [P2]** Balance carpet spread against space and local resource availability.
- **WL-0448 [P2]** Let plant succession change habitat suitability for fish over several days.
- **WL-0449 [P2]** Evaluate planted-tank recovery after a major trim or partial die-off.
- **WL-0450 [P2]** Explain stalled growth with the strongest modeled limitation rather than every possible cause.

<a id="topic-19"></a>

### 19. Substrate, hardscape, and microorganisms — WL-0451–WL-0475

**Priority:** P2. **Sources:** [shaders-godot/godot-project/scripts/substrate_grid.gd](../shaders-godot/godot-project/scripts/substrate_grid.gd); [shaders-godot/godot-project/scripts/world.gd](../shaders-godot/godot-project/scripts/world.gd); [shaders-godot/godot-project/scripts/food_web_trace.gd](../shaders-godot/godot-project/scripts/food_web_trace.gd).

**Review intent:** Connect existing substrate channels and decorative detail to local ecology where useful.

- **WL-0451 [P2]** Separate visible detritus coverage from chemically available substrate nutrients.
- **WL-0452 [P2]** Let settled waste enrich the cells where it actually lands.
- **WL-0453 [P2]** Make substrate oxygen penetration depend on depth and local disturbance.
- **WL-0454 [P2]** Give roots a localized effect on oxygen and uptake around their paths.
- **WL-0455 [P2]** Keep anaerobic pockets spatially coherent instead of isolated random warnings.
- **WL-0456 [P2]** Let digging briefly redistribute particles without creating nutrients from nothing.
- **WL-0457 [P2]** Show disturbed substrate settling with a short visible recovery sequence.
- **WL-0458 [P2]** Differentiate coarse gravel, sand, and soil in slope and particle size.
- **WL-0459 [P2]** Keep hardscape surface biofilm separate from nitrifier colony strength.
- **WL-0460 [P2]** Let new wood biofilm rise and decline through a readable bounded lifecycle.
- **WL-0461 [P2]** Make edible film loss follow grazing contacts rather than whole-tank resets.
- **WL-0462 [P2]** Give microfauna refuges in porous substrate and dense moss.
- **WL-0463 [P2]** Make substrate worms appear near detritus-rich regions with plausible density limits.
- **WL-0464 [P2]** Represent bacterial clouding separately from green algal turbidity.
- **WL-0465 [P2]** Let major substrate replacement affect established cycling capacity explicitly.
- **WL-0466 [P2]** Keep decorative stone placement from silently changing substrate chemistry.
- **WL-0467 [P2]** Give mineral-leaching hardscape a clear labeled gameplay effect where modeled.
- **WL-0468 [P2]** Track substrate compaction only if it changes useful player decisions.
- **WL-0469 [P2]** Show exposed roots responding to erosion or digging.
- **WL-0470 [P2]** Preserve local resource patterns across save and loading.
- **WL-0471 [P2]** Let old mulm support ecosystem functions without making all visible dirt beneficial.
- **WL-0472 [P2]** Explain cleaning tradeoffs between appearance and established biological surfaces.
- **WL-0473 [P2]** Provide a localized substrate inspection lens with resource and oxygen summaries.
- **WL-0474 [P2]** Prevent resource diffusion across disconnected dry or solid cells.
- **WL-0475 [P2]** Measure whether substrate detail improves ecosystem readability at normal zoom.

<a id="topic-20"></a>

### 20. Nitrogen cycle and chemistry coherence — WL-0476–WL-0500

**Priority:** P1. **Sources:** [shaders-godot/godot-project/scripts/water_chemistry.gd](../shaders-godot/godot-project/scripts/water_chemistry.gd); [shaders-godot/godot-project/scripts/substrate_grid.gd](../shaders-godot/godot-project/scripts/substrate_grid.gd); [sim-rust/README.md](../sim-rust/README.md).

**Review intent:** The shipping path is GDScript; use the separate Rust prototype only as a documented comparison reference.

- **WL-0476 [P1]** Reconcile tank-age days with configurable light-cycle duration in all labels.
- **WL-0477 [P1]** Separate ammonia-oxidizing and nitrite-oxidizing capacities if that improves cycle shape.
- **WL-0478 [P1]** Document normalized nitrogen quantities and any conversion to displayed units.
- **WL-0479 [P1]** Track nitrogen inputs, transformations, uptake, and declared losses in one budget.
- **WL-0480 [P1]** Bound reaction transfer by available source mass for large timesteps.
- **WL-0481 [P1]** Verify cycle progression remains comparable across supported simulation speeds.
- **WL-0482 [P1]** Replace hidden background ammonia with an explicit documented source budget.
- **WL-0483 [P1]** Make bacteria growth respond to available food as well as elapsed age.
- **WL-0484 [P1]** Prevent starving colony decay from being overwhelmed by unconditional growth.
- **WL-0485 [P1]** Give established tanks meaningful resilience without instant recovery from major shocks.
- **WL-0486 [P1]** Show cycling stage based on current chemistry and trend, not age alone.
- **WL-0487 [P1]** Add phase hysteresis so borderline values do not flicker between labels.
- **WL-0488 [P1]** Distinguish toxic ammonia fraction from total ammonia in care messages.
- **WL-0489 [P1]** Keep temperature and pH effects on ammonia toxicity consistently sourced.
- **WL-0490 [P1]** Make nitrite stress distinct from oxygen distress where the model supports it.
- **WL-0491 [P1]** Let rapid stocking additions produce explainable mini-cycles.
- **WL-0492 [P1]** Represent seeded filter media as transferred capacity rather than instant maturity.
- **WL-0493 [P1]** Make aggressive cleaning reduce bacterial habitat through a visible tradeoff.
- **WL-0494 [P1]** Compare plant-heavy and lightly planted cycling under equal input budgets.
- **WL-0495 [P1]** Keep denitrification losses separately accounted from plant nitrate uptake.
- **WL-0496 [P1]** Explain soft ceilings as numerical design choices rather than physical concentration limits.
- **WL-0497 [P1]** Prevent display rounding from showing zero while meaningful toxicity persists.
- **WL-0498 [P1]** Compare the Rust and GDScript models using shared dimensionless scenarios.
- **WL-0499 [P1]** Report model differences without treating the higher-fidelity prototype as shipping behavior.
- **WL-0500 [P1]** Evaluate repeated feed pulses after maturity to expose unstable cycle feedback.

<a id="topic-21"></a>

### 21. Oxygen, carbon, and daily metabolism — WL-0501–WL-0525

**Priority:** P1. **Sources:** [shaders-godot/godot-project/scripts/water_chemistry.gd](../shaders-godot/godot-project/scripts/water_chemistry.gd); [shaders-godot/godot-project/scripts/sim_driver.gd](../shaders-godot/godot-project/scripts/sim_driver.gd); [shaders-godot/godot-project/scripts/plant_ecology_adapter.gd](../shaders-godot/godot-project/scripts/plant_ecology_adapter.gd).

**Review intent:** Strengthen existing oxygen, CO2, pH, respiration, and pearling feedbacks as a coupled daily cycle.

- **WL-0501 [P1]** Track photosynthesis and respiration as separate visible contributors to oxygen.
- **WL-0502 [P1]** Make nighttime plant respiration contribute consistently to overnight oxygen demand.
- **WL-0503 [P1]** Tie resident respiration to biomass and activity rather than count alone.
- **WL-0504 [P1]** Let warmer water change oxygen capacity as well as metabolic demand.
- **WL-0505 [P1]** Make surface gas exchange respond to aeration and exposed surface area.
- **WL-0506 [P1]** Keep flow circulation distinct from true air-water gas exchange.
- **WL-0507 [P1]** Let dense surface plants reduce exchange without fully sealing the tank.
- **WL-0508 [P1]** Show oxygen trends approaching dawn when overnight depletion is strongest.
- **WL-0509 [P1]** Make CO2 uptake respond to usable light and actual growing biomass.
- **WL-0510 [P1]** Avoid treating unlimited light as unlimited photosynthetic oxygen production.
- **WL-0511 [P1]** Keep pH response to CO2 buffered by the modeled carbonate pool.
- **WL-0512 [P1]** Separate injected CO2 from biological respiration contributions.
- **WL-0513 [P1]** Represent nitrification oxygen demand in the same budget as fauna respiration.
- **WL-0514 [P1]** Let decaying biomass create delayed respiratory load.
- **WL-0515 [P1]** Give low-oxygen shelters lower attractiveness when refuge and breathing compete.
- **WL-0516 [P1]** Explain daytime pearling without implying guaranteed nighttime safety.
- **WL-0517 [P1]** Show daily oxygen minimum alongside the current oxygen reading.
- **WL-0518 [P1]** Give aeration improvements a measurable recovery curve rather than instant refill.
- **WL-0519 [P1]** Prevent positive feedback from exhausted fish indefinitely raising respiration.
- **WL-0520 [P1]** Compare morning and evening pH with the same clock interpretation.
- **WL-0521 [P1]** Keep oxygen saturation presentation distinct from normalized oxygen state.
- **WL-0522 [P1]** Define compatible units before exposing dissolved-gas values as physical measurements.
- **WL-0523 [P1]** Let high-density breeding cohorts visibly increase the next night's demand.
- **WL-0524 [P1]** Evaluate cloudy-day lighting reductions against nighttime respiratory stability.
- **WL-0525 [P1]** Make oxygen-related care recommendations identify the main modeled demand or supply problem.

<a id="topic-22"></a>

### 22. Water, flow, temperature, and equipment — WL-0526–WL-0550

**Priority:** P2. **Sources:** [shaders-godot/godot-project/scripts/world.gd](../shaders-godot/godot-project/scripts/world.gd); [shaders-godot/godot-project/scripts/hydrodynamics.gd](../shaders-godot/godot-project/scripts/hydrodynamics.gd); [shaders-godot/godot-project/scripts/water_chemistry.gd](../shaders-godot/godot-project/scripts/water_chemistry.gd).

**Review intent:** Connect water presentation and existing equipment to intelligible physical effects.

- **WL-0526 [P2]** Give filter outflow an identifiable circulation path through visible particles.
- **WL-0527 [P2]** Let sheltered zones hold weaker currents than exposed open water.
- **WL-0528 [P2]** Make plant sway direction agree with nearby particle drift.
- **WL-0529 [P2]** Keep fish station-holding orientation consistent with local flow.
- **WL-0530 [P2]** Represent heater influence through bounded thermal mixing rather than decorative glow alone.
- **WL-0531 [P2]** Show heater state with a restrained indicator meaningful to the current temperature.
- **WL-0532 [P2]** Give temperature changes inertia proportional to water volume.
- **WL-0533 [P2]** Let replacement water temperature create a gradual mixing response.
- **WL-0534 [P2]** Separate tannin color from reduced clarity caused by suspended particles.
- **WL-0535 [P2]** Make green-water haze distinct from sediment dust in color and persistence.
- **WL-0536 [P2]** Keep glass reflection subdued where it competes with followed residents.
- **WL-0537 [P2]** Reduce water-surface shimmer in already busy scenes.
- **WL-0538 [P2]** Give the meniscus consistent thickness across camera views and quality tiers.
- **WL-0539 [P2]** Let equipment placement show expected flow reach before purchase or placement.
- **WL-0540 [P2]** Make filter media cleaning and replacement separate care actions.
- **WL-0541 [P2]** Describe aeration, filtration, and circulation as different useful roles.
- **WL-0542 [P2]** Keep equipment power changes from instantly changing ecological capacity.
- **WL-0543 [P2]** Give evaporation effects only to systems with a coherent water-volume model.
- **WL-0544 [P2]** Distinguish topping up evaporation from removing waste through water changes.
- **WL-0545 [P2]** Make water-change fractions act consistently on dissolved resource pools.
- **WL-0546 [P2]** Track removed and introduced materials during water changes.
- **WL-0547 [P2]** Let equipment failure cues precede major ecological collapse when pacing allows.
- **WL-0548 [P2]** Offer quiet equipment visualization so technical overlays remain optional.
- **WL-0549 [P2]** Make temperature warnings species-aware rather than one universal threshold.
- **WL-0550 [P2]** Evaluate circulation in nonrectangular tanks for persistent dead zones.

<a id="topic-23"></a>

### 23. Time, seasons, and offline continuity — WL-0551–WL-0575

**Priority:** P1. **Sources:** [shaders-godot/godot-project/scripts/sim_driver.gd](../shaders-godot/godot-project/scripts/sim_driver.gd); [shaders-godot/godot-project/scripts/tank_config.gd](../shaders-godot/godot-project/scripts/tank_config.gd); [shaders-godot/godot-project/scripts/save_manager.gd](../shaders-godot/godot-project/scripts/save_manager.gd).

**Review intent:** Clarify the relationship between render time, simulation time, ecological age, and real absence.

- **WL-0551 [P1]** Define a single documented conversion among real seconds, sim seconds, and tank days.
- **WL-0552 [P1]** Show which systems accelerate when the player changes simulation speed.
- **WL-0553 [P1]** Keep day labels coherent after changing photoperiod settings.
- **WL-0554 [P1]** Distinguish light intensity transitions from absolute calendar progression.
- **WL-0555 [P1]** Make dawn and dusk long enough to reveal changing resident behavior.
- **WL-0556 [P1]** Let nocturnal activity emerge before the entire scene becomes hard to see.
- **WL-0557 [P1]** Keep sleep progression consistent during paused rendering or background operation.
- **WL-0558 [P1]** Advance offline state through bounded steps that preserve reaction stability.
- **WL-0559 [P1]** Report offline approximation and simulated duration plainly in the return summary.
- **WL-0560 [P1]** Offer explicit cozy limits for deterioration during long absences.
- **WL-0561 [P1]** Avoid repeatedly applying the same offline interval after a failed load.
- **WL-0562 [P1]** Preserve gestation and incubation progress through offline catch-up.
- **WL-0563 [P1]** Keep future-dated saves from causing negative ages or reversed progression.
- **WL-0564 [P1]** Handle wall-clock changes without duplicating simulation elapsed time.
- **WL-0565 [P1]** Separate seasonal presets from physical claims of a full seasonal model.
- **WL-0566 [P1]** Let optional temperature seasons develop slowly enough for keeper adaptation.
- **WL-0567 [P1]** Use repeatable weather schedules for testing environmental responses.
- **WL-0568 [P1]** Make time-lapse captures include clock and configuration metadata.
- **WL-0569 [P1]** Let population histories preserve useful intervals across different speed settings.
- **WL-0570 [P1]** Prevent replay speed from changing random event probability per simulated day.
- **WL-0571 [P1]** Keep chronicle timestamps interpretable across save imports and tank transfers.
- **WL-0572 [P1]** Show long-term trends without confusing a compressed day with real elapsed time.
- **WL-0573 [P1]** Give returning players a causal summary before presenting unrelated notifications.
- **WL-0574 [P1]** Evaluate one long offline step against many smaller equivalent updates.
- **WL-0575 [P1]** Provide a preview of the configured absence policy before leaving a tank unattended.

<a id="topic-24"></a>

### 24. Ecological balance and scenario pacing — WL-0576–WL-0600

**Priority:** P1. **Sources:** [scripts/ecological_baseline.sh](../scripts/ecological_baseline.sh); [shaders-godot/godot-project/scripts/scenario_picker.gd](../shaders-godot/godot-project/scripts/scenario_picker.gd); [shaders-godot/godot-project/scripts/sim_driver.gd](../shaders-godot/godot-project/scripts/sim_driver.gd).

**Review intent:** Evaluate existing scenarios as coupled ecosystems, including recovery and generational behavior.

- **WL-0576 [P1]** Define scenario-specific healthy ranges instead of one global flourishing formula.
- **WL-0577 [P1]** Measure sustainable biomass alongside the existing soft population limits.
- **WL-0578 [P1]** Tune starter scenarios to survive reasonable novice feeding variability.
- **WL-0579 [P1]** Let expert scenarios reveal tradeoffs without relying on opaque failure triggers.
- **WL-0580 [P1]** Evaluate each scenario through multiple reproductive generations.
- **WL-0581 [P1]** Track juvenile recruitment separately from birth rate.
- **WL-0582 [P1]** Use resource scarcity to slow population growth before hard node ceilings intervene.
- **WL-0583 [P1]** Expose simulation representation caps separately from ecological carrying capacity.
- **WL-0584 [P1]** Give population booms an observable cost before sudden mortality.
- **WL-0585 [P1]** Measure recovery time after a standardized overfeeding event.
- **WL-0586 [P1]** Measure recovery time after a partial plant loss.
- **WL-0587 [P1]** Compare equal-volume tanks with different surface area and habitat structure.
- **WL-0588 [P1]** Verify scaled scenarios retain their intended trophic relationships.
- **WL-0589 [P1]** Keep single predators and bonded pairs from multiplying with template size.
- **WL-0590 [P1]** Tune food supply and plant uptake together instead of independently.
- **WL-0591 [P1]** Give high-density scenarios more useful habitat rather than only larger counts.
- **WL-0592 [P1]** Make empty tanks ecologically valid instead of permanently classified as failures.
- **WL-0593 [P1]** Distinguish low-diversity intentional displays from unhealthy ecosystem collapse.
- **WL-0594 [P1]** Offer visible reasons for a changed tank mood.
- **WL-0595 [P1]** Include daily minima and maxima in balance evaluation instead of averages alone.
- **WL-0596 [P1]** Let scenario identity survive moderate player edits rather than prescribe one exact build.
- **WL-0597 [P1]** Test whether removing one cleanup species causes believable compensatory dynamics.
- **WL-0598 [P1]** Evaluate scarce-food conditions for persistent competitive exclusion.
- **WL-0599 [P1]** Track unintended positive feedback loops across algae, oxygen, and mortality.
- **WL-0600 [P1]** Document intended difficulty and intervention frequency for every scenario.

<a id="topic-25"></a>

### 25. Perception and embodied attention — WL-0601–WL-0625

**Priority:** P2. **Sources:** [shaders-godot/godot-project/scripts/mind_world_model.gd](../shaders-godot/godot-project/scripts/mind_world_model.gd); [shaders-godot/godot-project/scripts/mind_cycle.gd](../shaders-godot/godot-project/scripts/mind_cycle.gd); [shaders-godot/godot-project/scripts/fish_mind.gd](../shaders-godot/godot-project/scripts/fish_mind.gd).

**Review intent:** Extend existing functional cognition with percepts constrained by each animal’s body and habitat.

- **WL-0601 [P2]** Limit visual perception by field of view and actual facing direction.
- **WL-0602 [P2]** Let turbidity reduce detection confidence before eliminating detection entirely.
- **WL-0603 [P2]** Prevent fish from sensing food through solid hardscape without an alternate channel.
- **WL-0604 [P2]** Give chemical cues slower broader reach than visual cues.
- **WL-0605 [P2]** Distinguish perceived threat from the simulator's omniscient threat state.
- **WL-0606 [P2]** Let occluded neighbors leave short-lived uncertain beliefs rather than immediate erasure.
- **WL-0607 [P2]** Make inspection turns reveal new information before curiosity declines.
- **WL-0608 [P2]** Bound attention switching so salient events do not create constant dithering.
- **WL-0609 [P2]** Give hunger a perceptual salience effect without guaranteeing the food drive wins.
- **WL-0610 [P2]** Separate tactile contact from distant visual recognition in memory entries.
- **WL-0611 [P2]** Use species-specific sensory ranges tied to ecological roles.
- **WL-0612 [P2]** Make alert fish react faster without giving them impossible global knowledge.
- **WL-0613 [P2]** Let shelter reduce visual coverage while increasing perceived safety.
- **WL-0614 [P2]** Give unfamiliar objects initial uncertainty that decays through repeated safe exposure.
- **WL-0615 [P2]** Avoid perfect recognition of individuals at distances where only silhouettes resolve.
- **WL-0616 [P2]** Treat current direction as a local sensed cue with limited accuracy.
- **WL-0617 [P2]** Let body condition affect perception latency within clear bounded limits.
- **WL-0618 [P2]** Preserve attention targets briefly across ordinary frame-to-frame occlusion.
- **WL-0619 [P2]** Distinguish novel events from repeated identical stimulation.
- **WL-0620 [P2]** Give sudden light changes an appropriate bounded startle response.
- **WL-0621 [P2]** Let auditory or vibration cues matter independently from visual glass-tap location.
- **WL-0622 [P2]** Track whether attended information changes the next action.
- **WL-0623 [P2]** Keep perception updates coherent when mind LOD reduces tick frequency.
- **WL-0624 [P2]** Expose one or two actual percepts in the inspector instead of omniscient facts.
- **WL-0625 [P2]** Evaluate sensory limitations with identical scenes containing controlled occluders.

<a id="topic-26"></a>

### 26. Memory, learning, and personal history — WL-0626–WL-0650

**Priority:** P1. **Sources:** [shaders-godot/godot-project/scripts/fish_learned_mind.gd](../shaders-godot/godot-project/scripts/fish_learned_mind.gd); [shaders-godot/godot-project/scripts/mind_world_model.gd](../shaders-godot/godot-project/scripts/mind_world_model.gd); [shaders-godot/godot-project/scripts/mind_eval.gd](../shaders-godot/godot-project/scripts/mind_eval.gd).

**Review intent:** Build on existing episodic learning and sleep consolidation; validate retained behavior, not just stored numbers.

- **WL-0626 [P1]** Let repeated safe exposure reduce fear of previously startling locations.
- **WL-0627 [P1]** Distinguish one frightening incident from sustained adverse experience.
- **WL-0628 [P1]** Make remembered food locations affect routes before fresh food appears.
- **WL-0629 [P1]** Let memory confidence decline when a familiar location changes.
- **WL-0630 [P1]** Keep recent episodes and generalized habits visibly distinct.
- **WL-0631 [P1]** Give repeated failed feeding attempts a useful target-selection consequence.
- **WL-0632 [P1]** Let sleep consolidate meaningful experiences without inventing unwitnessed events.
- **WL-0633 [P1]** Preserve learned shelter preferences across save reloads.
- **WL-0634 [P1]** Bound memory growth while retaining emotionally significant experiences.
- **WL-0635 [P1]** Avoid erasing identity-defining experiences solely because a ring buffer fills.
- **WL-0636 [P1]** Let memory retrieval depend on context similarity rather than exact coordinates only.
- **WL-0637 [P1]** Use safe exploration to revise outdated threat beliefs.
- **WL-0638 [P1]** Make learning rate vary moderately with temperament and age.
- **WL-0639 [P1]** Let juveniles acquire habits differently from already established adults.
- **WL-0640 [P1]** Prevent one extreme event from permanently saturating all learned caution.
- **WL-0641 [P1]** Give food prediction a measured expectation and a response to omission.
- **WL-0642 [P1]** Record which experience supports a displayed behavioral interpretation.
- **WL-0643 [P1]** Separate innate depth preference from learned local habitat use.
- **WL-0644 [P1]** Let relocation preserve identity while resetting place-specific confidence appropriately.
- **WL-0645 [P1]** Show a small history of changed habits in the fish journal.
- **WL-0646 [P1]** Measure retention after distraction rather than immediately after training.
- **WL-0647 [P1]** Evaluate generalization to nearby untrained locations.
- **WL-0648 [P1]** Use unpaired control events to distinguish learning from global arousal.
- **WL-0649 [P1]** Compare trained fish with matched untrained fish under the same conditions.
- **WL-0650 [P1]** Make forgetting gradual and useful instead of an unexplained full reset.

<a id="topic-27"></a>

### 27. Decisions, goals, and functional sentience — WL-0651–WL-0675

**Priority:** P1. **Sources:** [shaders-godot/godot-project/scripts/mind_active_inference.gd](../shaders-godot/godot-project/scripts/mind_active_inference.gd); [shaders-godot/godot-project/scripts/mind_eval.gd](../shaders-godot/godot-project/scripts/mind_eval.gd); [docs/SENTIENCE_EVAL_HARNESS.md](../docs/SENTIENCE_EVAL_HARNESS.md).

**Review intent:** Use the existing functional-signature framing; “more sentient” here means more coherent observable agency, not a claim of subjective experience.

- **WL-0651 [P1]** Require internal need changes to alter real action selection measurably.
- **WL-0652 [P1]** Let food-versus-threat decisions produce stable risk-sensitive routes.
- **WL-0653 [P1]** Keep committed actions interruptible by genuine emergencies.
- **WL-0654 [P1]** Give uncertainty a visible information-seeking consequence when the cost is reasonable.
- **WL-0655 [P1]** Make curiosity recede after useful information is acquired.
- **WL-0656 [P1]** Let predicted outcomes be compared with subsequent actual outcomes.
- **WL-0657 [P1]** Show recovery from a mistaken prediction through revised behavior.
- **WL-0658 [P1]** Bound deliberation so uncertain fish still act before starvation.
- **WL-0659 [P1]** Separate action confidence from positive mood in the inspector.
- **WL-0660 [P1]** Let fatigue change chosen goals before lowering every movement parameter.
- **WL-0661 [P1]** Use goal persistence to avoid alternating between nearly equal bids every tick.
- **WL-0662 [P1]** Give failed actions a reason-specific retry strategy.
- **WL-0663 [P1]** Measure intention completion rather than only workspace activation counts.
- **WL-0664 [P1]** Keep behavioral meaning stable when native and GDScript mind backends differ.
- **WL-0665 [P1]** Test functional signatures in live locomotion as well as isolated state hosts.
- **WL-0666 [P1]** Show honest causal explanations grounded in the selected action and evidence.
- **WL-0667 [P1]** Avoid turning a single proxy score into a consciousness percentage.
- **WL-0668 [P1]** Report optional eval invariants separately from required passing invariants.
- **WL-0669 [P1]** Calibrate cognitive metrics against simple scripted and random baselines.
- **WL-0670 [P1]** Use ablations to confirm each added mind layer improves useful behavior.
- **WL-0671 [P1]** Retire cognition modules that add cost without observable benefit.
- **WL-0672 [P1]** Test recovery from conflicting goals over long observation windows.
- **WL-0673 [P1]** Check agency continuity when a creature moves between mind fidelity tiers.
- **WL-0674 [P1]** Let individual strategy differences emerge within species-compatible limits.
- **WL-0675 [P1]** Prioritize a few credible learned behaviors over additional unexplained theory terminology.

<a id="topic-28"></a>

### 28. Social cognition and individual relationships — WL-0676–WL-0700

**Priority:** P2. **Sources:** [shaders-godot/godot-project/scripts/mind_contagion.gd](../shaders-godot/godot-project/scripts/mind_contagion.gd); [shaders-godot/godot-project/scripts/mind_pair_cache.gd](../shaders-godot/godot-project/scripts/mind_pair_cache.gd); [shaders-godot/godot-project/scripts/fish_mind.gd](../shaders-godot/godot-project/scripts/fish_mind.gd).

**Review intent:** Make existing social predictions and contagion influence encounters without global omniscience.

- **WL-0676 [P2]** Let repeated aggression from one neighbor alter anticipatory avoidance of that neighbor.
- **WL-0677 [P2]** Keep fear of one aggressor from generalizing automatically to every resident.
- **WL-0678 [P2]** Make familiar calm companions reduce vigilance through proximity.
- **WL-0679 [P2]** Give relationship strength a gradual bounded update after actual encounters.
- **WL-0680 [P2]** Distinguish co-location from meaningful social interaction in relationship histories.
- **WL-0681 [P2]** Let social predictions include uncertainty for newly encountered animals.
- **WL-0682 [P2]** Use observed behavior rather than hidden personality fields to update neighbor beliefs.
- **WL-0683 [P2]** Keep panic transmission dependent on sensed neighbors and finite propagation range.
- **WL-0684 [P2]** Make reassuring social cues compete with alarm cues after a disturbance.
- **WL-0685 [P2]** Prevent repeated contagion from creating self-sustaining maximum arousal.
- **WL-0686 [P2]** Let pair separation create temporary searching only for species with relevant bonds.
- **WL-0687 [P2]** Make reunion behavior depend on recognition rather than instant identifier matching.
- **WL-0688 [P2]** Give offspring familiarity with caregivers through actual early encounters.
- **WL-0689 [P2]** Allow social learning of safe feeding locations through observed success.
- **WL-0690 [P2]** Keep socially acquired habits distinguishable from personally reinforced habits.
- **WL-0691 [P2]** Let shy fish watch a bold companion before crossing exposed space.
- **WL-0692 [P2]** Represent rival intent predictions as fallible estimates with corrective learning.
- **WL-0693 [P2]** Prevent relationship caches from carrying stale references after death or transfer.
- **WL-0694 [P2]** Preserve important relationship summaries without saving live node identifiers.
- **WL-0695 [P2]** Show social comfort through spacing and posture before textual narration.
- **WL-0696 [P2]** Let repeated rejected courtship alter future approach choices.
- **WL-0697 [P2]** Make social preferences context-dependent rather than permanent universal friendship scores.
- **WL-0698 [P2]** Evaluate social learning with observer and nonobserver control groups.
- **WL-0699 [P2]** Track whether removing a familiar companion changes subsequent behavior.
- **WL-0700 [P2]** Bound relationship complexity so large schools retain plausible local social structure.

<a id="topic-29"></a>

### 29. Keeper relationship and care loop — WL-0701–WL-0725

**Priority:** P2. **Sources:** [shaders-godot/godot-project/scripts/keeper_care.gd](../shaders-godot/godot-project/scripts/keeper_care.gd); [shaders-godot/godot-project/scripts/mind_keeper_model.gd](../shaders-godot/godot-project/scripts/mind_keeper_model.gd); [shaders-godot/godot-project/scripts/mind_conversation.gd](../shaders-godot/godot-project/scripts/mind_conversation.gd).

**Review intent:** Build on care-gated conversation and per-fish keeper models; make trust visible and proportional.

- **WL-0701 [P2]** Let repeated consistent feeding increase approach confidence toward the keeper location.
- **WL-0702 [P2]** Keep care trust dependent on actual tank actions as well as speech tone.
- **WL-0703 [P2]** Make calming words reduce arousal without repairing toxic water instantly.
- **WL-0704 [P2]** Show the care gate's specific unmet condition beside the conversation control.
- **WL-0705 [P2]** Give stressed fish brief nonverbal responses when full conversation is unavailable.
- **WL-0706 [P2]** Preserve relationship continuity through return sessions and ordinary save reloads.
- **WL-0707 [P2]** Let individual residents respond differently to the same keeper routine.
- **WL-0708 [P2]** Make newcomer trust develop separately from long-established resident trust.
- **WL-0709 [P2]** Distinguish the fish's inferred keeper mood from a claim about player emotion.
- **WL-0710 [P2]** Provide a quiet interaction mode for players who prefer observation over dialogue.
- **WL-0711 [P2]** Let repeated glass taps teach bounded avoidance rather than reward engagement.
- **WL-0712 [P2]** Show gentle care success through habitat exploration and relaxed posture.
- **WL-0713 [P2]** Allow useful interaction without requiring players to type elaborate prompts.
- **WL-0714 [P2]** Give simple care rituals a visible consistent effect over time.
- **WL-0715 [P2]** Explain blocked conversation without sounding punitive or accusatory.
- **WL-0716 [P2]** Keep keeper reminders proportional to urgency and actual actionable conditions.
- **WL-0717 [P2]** Let a returning fish greet through movement before generating a line.
- **WL-0718 [P2]** Make player monikers stable while allowing explicit correction.
- **WL-0719 [P2]** Separate general keeper familiarity from trust in one particular routine.
- **WL-0720 [P2]** Show unresolved care needs in the same place as the relevant action.
- **WL-0721 [P2]** Let absence policies avoid implying moral failure for not opening the game.
- **WL-0722 [P2]** Give recovery stories observable care-action anchors instead of generic praise.
- **WL-0723 [P2]** Keep spoken reassurance and actual emergency interventions complementary.
- **WL-0724 [P2]** Allow residents to disengage naturally when feeding, sleep, or danger takes priority.
- **WL-0725 [P2]** Evaluate relationship changes with recorded actions and subsequent approach behavior.

<a id="topic-30"></a>

### 30. Voice, narration, and meaning — WL-0726–WL-0750

**Priority:** P2. **Sources:** [shaders-godot/godot-project/scripts/mind_narrator.gd](../shaders-godot/godot-project/scripts/mind_narrator.gd); [shaders-godot/godot-project/scripts/mind_legible.gd](../shaders-godot/godot-project/scripts/mind_legible.gd); [shaders-godot/godot-project/scripts/mind_conversation.gd](../shaders-godot/godot-project/scripts/mind_conversation.gd).

**Review intent:** Refine the existing template/embedded voice paths without using eloquence as evidence of cognition.

- **WL-0726 [P2]** Ground every narrated observation in recent actual creature or tank state.
- **WL-0727 [P2]** Keep fish language short enough to accompany watching rather than dominate it.
- **WL-0728 [P2]** Differentiate voices through consistent rhythm and vocabulary instead of random flourish.
- **WL-0729 [P2]** Prevent narration from describing an event the creature could not perceive.
- **WL-0730 [P2]** Give repeated routine states varied phrasing without changing their meaning.
- **WL-0731 [P2]** Prioritize meaningful changes over continuous commentary on stable conditions.
- **WL-0732 [P2]** Let uncertainty appear naturally when behavioral evidence is weak.
- **WL-0733 [P2]** Keep template fallback emotionally coherent with the embedded-model voice.
- **WL-0734 [P2]** Make model loading and opt-in state understandable in settings.
- **WL-0735 [P2]** Preserve conversation turn context when a generated response arrives late.
- **WL-0736 [P2]** Discard obsolete replies after the fish dies, transfers, or changes urgent state.
- **WL-0737 [P2]** Bind response delivery to stable creature identity rather than current selection alone.
- **WL-0738 [P2]** Let silent behavior remain a valid expressive outcome.
- **WL-0739 [P2]** Keep narrator confidence separate from the underlying animal's decision confidence.
- **WL-0740 [P2]** Avoid factual aquarium-care claims unsupported by the game's modeled systems.
- **WL-0741 [P2]** Make non-fish voices fit their simpler observable behavior and sensory world.
- **WL-0742 [P2]** Let naming and species terms remain consistent across journal and dialogue.
- **WL-0743 [P2]** Reduce repeated farewell and return messages during rapid panel switching.
- **WL-0744 [P2]** Expose a concise source-state explanation for interested players.
- **WL-0745 [P2]** Keep generated text length bounded for narrow screens and accessibility scaling.
- **WL-0746 [P2]** Allow narration frequency and dialogue frequency to be controlled separately.
- **WL-0747 [P2]** Make language localization preserve urgency and uncertainty distinctions.
- **WL-0748 [P2]** Keep absence recaps causal and focused on important changes.
- **WL-0749 [P2]** Compare narrated interpretations against behavior clips before approving new templates.
- **WL-0750 [P2]** Treat functional sentience language consistently across game, documentation, and store copy.

<a id="topic-31"></a>

### 31. HUD hierarchy and information design — WL-0751–WL-0775

**Priority:** P1. **Sources:** [shaders-godot/godot-project/scripts/hud_layout.gd](../shaders-godot/godot-project/scripts/hud_layout.gd); [shaders-godot/godot-project/scripts/main.gd](../shaders-godot/godot-project/scripts/main.gd); [shaders-godot/godot-project/scripts/panel_theme.gd](../shaders-godot/godot-project/scripts/panel_theme.gd).

**Review intent:** Refine the current shared region layout; prioritize watching, then understanding, then acting.

- **WL-0751 [P1]** Give the primary HUD one dominant care summary instead of competing dense chips.
- **WL-0752 [P1]** Show resident counts with clear adult and juvenile labels rather than unexplained abbreviations.
- **WL-0753 [P1]** Move rarely used diagnostics behind a deliberate detail affordance.
- **WL-0754 [P1]** Let metric chips reveal trend and consequence before raw subsystem detail.
- **WL-0755 [P1]** Keep the most urgent actionable condition visible without enlarging every warning.
- **WL-0756 [P1]** Reserve a stable location for simulation speed and pause state.
- **WL-0757 [P1]** Use consistent icon meaning across rail, chips, panels, and tooltips.
- **WL-0758 [P1]** Let the bottom action bar adapt by available width and selected task.
- **WL-0759 [P1]** Keep feed and care actions distinguishable from destructive editing actions.
- **WL-0760 [P1]** Group related water metrics under a readable chemistry summary.
- **WL-0761 [P1]** Give selected creatures a clear identity anchor without covering the fish.
- **WL-0762 [P1]** Preserve tank visibility when thoughts, chat, and notifications compete for space.
- **WL-0763 [P1]** Use notification queues instead of stacking several large simultaneous messages.
- **WL-0764 [P1]** Deduplicate warnings that share the same underlying cause.
- **WL-0765 [P1]** Show recovery acknowledgment only when a previously important condition improves.
- **WL-0766 [P1]** Keep transient messages separate from persistent unresolved care needs.
- **WL-0767 [P1]** Avoid placing primary actions behind decorative glass-like low-contrast surfaces.
- **WL-0768 [P1]** Make disabled actions explain their current prerequisite in plain language.
- **WL-0769 [P1]** Prefer clear names to isolated unfamiliar glyphs in frequently used actions.
- **WL-0770 [P1]** Let users choose a minimal observing HUD with essential emergency access.
- **WL-0771 [P1]** Keep keyboard hints contextual rather than a dense permanent footer.
- **WL-0772 [P1]** Ensure chips remain interpretable when numeric values are clipped or rounded.
- **WL-0773 [P1]** Expose tank mood contributors without asking players to decode an opaque score.
- **WL-0774 [P1]** Give selection, hover, and warning states distinct visual treatments.
- **WL-0775 [P1]** Evaluate HUD comprehension with a new player completing one care action.

<a id="topic-32"></a>

### 32. Panels, library, and editing workflows — WL-0776–WL-0800

**Priority:** P1. **Sources:** [shaders-godot/godot-project/scripts/library_panel.gd](../shaders-godot/godot-project/scripts/library_panel.gd); [shaders-godot/godot-project/scripts/residents_panel.gd](../shaders-godot/godot-project/scripts/residents_panel.gd); [shaders-godot/godot-project/scripts/adopt_panel.gd](../shaders-godot/godot-project/scripts/adopt_panel.gd); [shaders-godot/godot-project/scripts/ui_panel_manager.gd](../shaders-godot/godot-project/scripts/ui_panel_manager.gd).

**Review intent:** Build on recorded responsive fixes; assess information architecture and unmet screen configurations.

- **WL-0776 [P1]** Keep primary panel actions visible while long content scrolls independently.
- **WL-0777 [P1]** Distinguish resident selection from a library template selection visually.
- **WL-0778 [P1]** Organize resident details into current state, history, and lineage.
- **WL-0779 [P1]** Let library entries identify whether they are species, strains, or individuals.
- **WL-0780 [P1]** Give empty search results an explanation and a clear reset action.
- **WL-0781 [P1]** Preserve search and scroll position when returning from a detail view.
- **WL-0782 [P1]** Avoid reshuffling roster rows while the player is choosing an individual.
- **WL-0783 [P1]** Show full names accessibly when narrow layouts require truncation.
- **WL-0784 [P1]** Let related panels share the same selected creature consistently.
- **WL-0785 [P1]** Give previews representative lighting with an optional neutral comparison.
- **WL-0786 [P1]** Explain adoption as free introduction consistently throughout the flow.
- **WL-0787 [P1]** Preview stocking compatibility before adding residents to the live tank.
- **WL-0788 [P1]** Show environmental needs beside appearance during adoption choices.
- **WL-0789 [P1]** Distinguish import validation failure from incompatible game-version failure.
- **WL-0790 [P1]** Make strain sharing provide clear success feedback and format guidance.
- **WL-0791 [P1]** Let lineage views focus on a selected family without overwhelming whole-tank graphs.
- **WL-0792 [P1]** Keep creator controls grouped by visible anatomical effect.
- **WL-0793 [P1]** Show the effect of a changed gene beside the relevant control.
- **WL-0794 [P1]** Offer reversible preview state before replacing an established creature template.
- **WL-0795 [P1]** Keep close and back behavior consistent across nested detail views.
- **WL-0796 [P1]** Make resizing preserve selected content rather than reset the panel.
- **WL-0797 [P1]** Provide a compact single-column variant for genuinely narrow portrait screens.
- **WL-0798 [P1]** Reflow enlarged text without burying footer actions.
- **WL-0799 [P1]** Use a stable detail header when live values update beneath it.
- **WL-0800 [P1]** Compare workflow completion time before adding more controls to existing panels.

<a id="topic-33"></a>

### 33. Onboarding, discovery, and player purpose — WL-0801–WL-0825

**Priority:** P2. **Sources:** [shaders-godot/godot-project/scripts/scenario_picker.gd](../shaders-godot/godot-project/scripts/scenario_picker.gd); [shaders-godot/godot-project/scripts/keeper_care.gd](../shaders-godot/godot-project/scripts/keeper_care.gd); [README.md](../README.md).

**Review intent:** Make the rich simulation understandable through a calm sequence of observable cause and effect.

- **WL-0801 [P2]** Start with a stable beautiful tank before introducing advanced simulation concepts.
- **WL-0802 [P2]** Teach one feeding action with immediate visible animal response.
- **WL-0803 [P2]** Explain where to see care needs before a first serious problem occurs.
- **WL-0804 [P2]** Let players choose observation-focused, creative, or ecology-focused onboarding.
- **WL-0805 [P2]** Show scenario difficulty through expected care frequency and ecological tradeoffs.
- **WL-0806 [P2]** Give the first followed fish a short understandable behavioral description.
- **WL-0807 [P2]** Demonstrate a normal day-night change before introducing chemical detail.
- **WL-0808 [P2]** Explain that a cycling tank differs from an established tank.
- **WL-0809 [P2]** Introduce breeding through a real successful pair rather than a static tutorial only.
- **WL-0810 [P2]** Teach fry survival needs when the first clutch appears.
- **WL-0811 [P2]** Reveal lineage exploration after players have witnessed meaningful parent-offspring resemblance.
- **WL-0812 [P2]** Give aquascaping a small reversible first placement exercise.
- **WL-0813 [P2]** Show how shelter changes animal behavior through a guided comparison.
- **WL-0814 [P2]** Explain pause and accelerated time before presenting long-term objectives.
- **WL-0815 [P2]** Provide a glossary reachable from unfamiliar in-game terms.
- **WL-0816 [P2]** Let tooltips describe what the player can notice or change.
- **WL-0817 [P2]** Keep technical cognitive vocabulary optional behind plain-language descriptions.
- **WL-0818 [P2]** Use milestones that reward observation as well as intervention.
- **WL-0819 [P2]** Avoid requiring constant interaction to maintain a deliberately relaxing scenario.
- **WL-0820 [P2]** Give players a concise next observation rather than a permanent task checklist.
- **WL-0821 [P2]** Let returning players resume tutorials without restarting the tank.
- **WL-0822 [P2]** Make skipped onboarding available later through a discoverable help entry.
- **WL-0823 [P2]** Introduce difficult scenarios only with clear expected failure and recovery paths.
- **WL-0824 [P2]** Show completed learning moments in a small optional keeper notebook.
- **WL-0825 [P2]** Evaluate first-session success by comprehension and confidence rather than clicks.

<a id="topic-34"></a>

### 34. Accessibility, localization, and input — WL-0826–WL-0850

**Priority:** P1. **Sources:** [shaders-godot/godot-project/scripts/panel_theme.gd](../shaders-godot/godot-project/scripts/panel_theme.gd); [shaders-godot/godot-project/assets/i18n/README.md](../shaders-godot/godot-project/assets/i18n/README.md); [steam/REVIEW_FEEDBACK.md](../steam/REVIEW_FEEDBACK.md).

**Review intent:** Expand the existing accessibility and input contracts to complete real user journeys.

- **WL-0826 [P1]** Support text scaling across HUD, tooltips, dialogue, and all panel footers.
- **WL-0827 [P1]** Give color-coded conditions a redundant shape or text cue.
- **WL-0828 [P1]** Offer reduced motion for camera drift, previews, and intense surface effects.
- **WL-0829 [P1]** Provide separate control over flashing iridescence and other high-frequency effects.
- **WL-0830 [P1]** Keep controller focus visible against every panel background.
- **WL-0831 [P1]** Make every primary care workflow usable without a pointer.
- **WL-0832 [P1]** Keep focus order aligned with the visible layout after responsive reflow.
- **WL-0833 [P1]** Restore focus to the initiating control when a dialog closes.
- **WL-0834 [P1]** Provide a reliable back action for controller and keyboard navigation.
- **WL-0835 [P1]** Use remappable shortcuts with conflict feedback and restore-default controls.
- **WL-0836 [P1]** Make drag actions available through discrete alternatives where feasible.
- **WL-0837 [P1]** Give touch targets enough spacing when controls wrap into additional rows.
- **WL-0838 [P1]** Avoid hover-only access to essential information on touch devices.
- **WL-0839 [P1]** Let long localized labels wrap without changing action meaning.
- **WL-0840 [P1]** Translate dynamic resident and chemistry messages with structured placeholders.
- **WL-0841 [P1]** Distinguish biological sex labels from input-device button labels in localization contexts.
- **WL-0842 [P1]** Offer readable high-contrast UI independently from the aquarium art palette.
- **WL-0843 [P1]** Keep critical text outside post-processing that can distort readability.
- **WL-0844 [P1]** Provide captions or equivalent visual cues for meaningful audio events.
- **WL-0845 [P1]** Make alerts understandable with all audio muted.
- **WL-0846 [P1]** Allow notification dwell time to scale for reading comfort.
- **WL-0847 [P1]** Support logical safe areas on devices with display cutouts.
- **WL-0848 [P1]** Keep input-device glyphs updated when the active device changes.
- **WL-0849 [P1]** Evaluate large-text layouts using both long names and long translated strings.
- **WL-0850 [P1]** Publish an honest accessibility matrix based on completed user journeys.

<a id="topic-35"></a>

### 35. Camera, observation, and photo tools — WL-0851–WL-0875

**Priority:** P2. **Sources:** [shaders-godot/godot-project/scripts/camera_controller.gd](../shaders-godot/godot-project/scripts/camera_controller.gd); [shaders-godot/godot-project/scripts/camera_views_panel.gd](../shaders-godot/godot-project/scripts/camera_views_panel.gd); [shaders-godot/godot-project/scripts/main.gd](../shaders-godot/godot-project/scripts/main.gd).

**Review intent:** Refine existing hero framing, follow modes, pixel snapping, and panel-aware camera behavior.

- **WL-0851 [P2]** Give default framing a clearly readable tank silhouette with minimal wasted stand area.
- **WL-0852 [P2]** Keep followed fish inside unobscured space when side panels open.
- **WL-0853 [P2]** Let close-up framing adapt to body length and fin extent.
- **WL-0854 [P2]** Prevent camera follow from amplifying tiny creature navigation corrections.
- **WL-0855 [P2]** Use gentle lead framing during sustained travel and quieter framing during rest.
- **WL-0856 [P2]** Make manual camera input immediately understandable as taking control.
- **WL-0857 [P2]** Offer a one-action return to a dependable tank overview.
- **WL-0858 [P2]** Preserve preferred views separately for each tank.
- **WL-0859 [P2]** Give cinema tours longer pauses on meaningful behavior.
- **WL-0860 [P2]** Avoid touring hidden, occluded, or visually indistinguishable residents repeatedly.
- **WL-0861 [P2]** Let players focus a breeding pair or clutch as an observation subject.
- **WL-0862 [P2]** Provide a low-disturbance plant-growth observation view.
- **WL-0863 [P2]** Keep orbit speed appropriate to vessel size and camera distance.
- **WL-0864 [P2]** Prevent near-plane clipping during fish portraits inside the tank.
- **WL-0865 [P2]** Make glass visibility adjust predictably for interior close-ups.
- **WL-0866 [P2]** Offer optional depth and flow overlays aligned with the viewed water column.
- **WL-0867 [P2]** Keep camera transitions compatible with reduced-motion preferences.
- **WL-0868 [P2]** Make photo mode preserve palette and species identity at export resolution.
- **WL-0869 [P2]** Offer clean captures with explicit inclusion or exclusion of UI.
- **WL-0870 [P2]** Save photo metadata including scenario, time, palette, and followed individual.
- **WL-0871 [P2]** Let captions use actual observed life events rather than generated fictional history.
- **WL-0872 [P2]** Keep integer-upscale letterboxing centered during window resizing.
- **WL-0873 [P2]** Compare front, three-quarter, and isometric views for each vessel.
- **WL-0874 [P2]** Make zoom bounds fit tall and shallow tanks without losing the meniscus.
- **WL-0875 [P2]** Provide predictable input hints only while the relevant camera mode is active.

<a id="topic-36"></a>

### 36. Sound, music, and atmosphere — WL-0876–WL-0900

**Priority:** P2. **Sources:** [shaders-godot/godot-project/scripts/ambient_audio.gd](../shaders-godot/godot-project/scripts/ambient_audio.gd); [shaders-godot/godot-project/dev/audio_probe.tscn](../shaders-godot/godot-project/dev/audio_probe.tscn); [scripts/audio_baseline.sh](../scripts/audio_baseline.sh).

**Review intent:** Refine existing state-driven synthesis and measured gain staging without making every event conspicuous.

- **WL-0876 [P2]** Keep ambient, music, interaction, and alert volume controls independent.
- **WL-0877 [P2]** Make day-night transitions crossfade without abrupt timbral discontinuities.
- **WL-0878 [P2]** Let low-oxygen tension remain subtle until an actionable threshold is reached.
- **WL-0879 [P2]** Avoid celebrating a birth with the same sound used for routine feeding.
- **WL-0880 [P2]** Give water-change and equipment actions restrained tactile feedback.
- **WL-0881 [P2]** Keep repeated grazing and bubble sounds from becoming rhythmic clutter.
- **WL-0882 [P2]** Let large and small tanks differ in room and water resonance.
- **WL-0883 [P2]** Make fish-follow audio focus optional rather than automatically amplifying events.
- **WL-0884 [P2]** Preserve spatial cues when the camera rotates around the tank.
- **WL-0885 [P2]** Keep event sounds audible without forcing users to raise master volume excessively.
- **WL-0886 [P2]** Bound peak levels during simultaneous births, warnings, and UI actions.
- **WL-0887 [P2]** Use long smooth transitions when ecosystem mood changes.
- **WL-0888 [P2]** Prevent short metric spikes from rebuilding the musical arrangement repeatedly.
- **WL-0889 [P2]** Offer a pure aquarium soundscape with no musical synthesis.
- **WL-0890 [P2]** Keep nighttime audio comfortable for long background listening.
- **WL-0891 [P2]** Let equipment hum reflect enabled equipment without dominating the mix.
- **WL-0892 [P2]** Use water-flow sound intensity tied to actual modeled flow activity.
- **WL-0893 [P2]** Avoid a new sound for every minor statistic change.
- **WL-0894 [P2]** Make muted audio stop unnecessary synthesis work where feasible.
- **WL-0895 [P2]** Provide visible equivalents for care cues conveyed musically.
- **WL-0896 [P2]** Measure clipping, RMS, and bus balance in representative dense-event scenes.
- **WL-0897 [P2]** Check sound continuity after pause, speed changes, and scene reloads.
- **WL-0898 [P2]** Keep low-fidelity audio musically coherent with higher-fidelity arrangements.
- **WL-0899 [P2]** Test headphones, laptop speakers, and mono playback for important cue clarity.
- **WL-0900 [P2]** Let sound presets describe the listening experience in ordinary language.

<a id="topic-37"></a>

### 37. Save integrity and continuity of identity — WL-0901–WL-0925

**Priority:** P1. **Sources:** [shaders-godot/godot-project/scripts/save_manager.gd](../shaders-godot/godot-project/scripts/save_manager.gd); [shaders-godot/godot-project/scripts/save_migrations.gd](../shaders-godot/godot-project/scripts/save_migrations.gd); [shaders-godot/godot-project/scripts/tank_saves.gd](../shaders-godot/godot-project/scripts/tank_saves.gd).

**Review intent:** Strengthen the existing migration, repair, and isolation contracts where further evidence is needed.

- **WL-0901 [P1]** Make save snapshots preserve creature identity, relationships, and pending reproductive stages together.
- **WL-0902 [P1]** Keep atomic-write recovery explainable when the newest snapshot is unusable.
- **WL-0903 [P1]** Retain a small bounded recovery history per tank.
- **WL-0904 [P1]** Show the timestamp and reason before restoring an older snapshot.
- **WL-0905 [P1]** Avoid autosaving over a refused newer-format tank.
- **WL-0906 [P1]** Make repaired fields visible in a concise recovery report.
- **WL-0907 [P1]** Distinguish missing optional data from structural corruption.
- **WL-0908 [P1]** Keep autosave failures visible without repeated intrusive popups.
- **WL-0909 [P1]** Ensure scene changes flush or safely preserve pending save requests.
- **WL-0910 [P1]** Serialize random-stream state alongside behaviorally important timers.
- **WL-0911 [P1]** Keep current selection and camera preferences optional to ecological restoration.
- **WL-0912 [P1]** Preserve ancestor references when only some live creatures survive migration.
- **WL-0913 [P1]** Prevent imported tanks from reusing identities already present elsewhere.
- **WL-0914 [P1]** Give tank export a complete manifest of included and omitted data.
- **WL-0915 [P1]** Make deletion offer a reversible archive where practical.
- **WL-0916 [P1]** Keep migration fixtures covering pregnancy, eggs, juveniles, and social memory.
- **WL-0917 [P1]** Test interruption between snapshot serialization and final file replacement.
- **WL-0918 [P1]** Prevent decorative preview scenes from claiming or writing real tank slots.
- **WL-0919 [P1]** Make isolated development runs verify real save inventory remains unchanged.
- **WL-0920 [P1]** Separate user screenshots from state files so cleanup cannot remove tanks.
- **WL-0921 [P1]** Document platform-specific save locations accurately for support.
- **WL-0922 [P1]** Let tank duplication intentionally remap identities while retaining family relationships.
- **WL-0923 [P1]** Keep shared strain imports separate from full save imports.
- **WL-0924 [P1]** Test saved ecological behavior after loading rather than only dictionary equality.
- **WL-0925 [P1]** Provide a support export that omits private keeper dialogue by default.

<a id="topic-38"></a>

### 38. Performance, fidelity, and device budgets — WL-0926–WL-0950

**Priority:** P1. **Sources:** [shaders-godot/godot-project/scripts/perf_governor.gd](../shaders-godot/godot-project/scripts/perf_governor.gd); [shaders-godot/godot-project/scripts/mind_lod.gd](../shaders-godot/godot-project/scripts/mind_lod.gd); [scripts/perf_workload_baseline.sh](../scripts/perf_workload_baseline.sh).

**Review intent:** Build on frame-cap-aware budgeting and existing workload reports; protect behavior as well as frame time.

- **WL-0926 [P1]** Measure representative frame percentiles during feeding, breeding, and dense vegetation.
- **WL-0927 [P1]** Track CPU and GPU bottlenecks separately before reducing fidelity.
- **WL-0928 [P1]** Keep adaptive quality from oscillating rapidly around one pressure threshold.
- **WL-0929 [P1]** Preserve recognizable fish silhouettes at the lowest supported render tier.
- **WL-0930 [P1]** Reduce cosmetic particles before removing behaviorally important visual cues.
- **WL-0931 [P1]** Make selected creatures retain enough cognition for continuous personal behavior.
- **WL-0932 [P1]** Keep lower mind tick rates from changing simulated learning rates.
- **WL-0933 [P1]** Bound per-frame spawn and geometry work during large brood events.
- **WL-0934 [P1]** Batch distant fauna without erasing stable individual color landmarks.
- **WL-0935 [P1]** Avoid rebuilding previews every frame when their genome has not changed.
- **WL-0936 [P1]** Virtualize large rosters while retaining stable selection and scroll position.
- **WL-0937 [P1]** Cache repeated chemistry and ecology queries once per relevant tick.
- **WL-0938 [P1]** Use spatial queries rather than whole-population scans for local encounters.
- **WL-0939 [P1]** Budget relationship caches with predictable cleanup after creature removal.
- **WL-0940 [P1]** Move costly serialization off the interaction path where consistency permits.
- **WL-0941 [P1]** Keep audio synthesis catch-up within an explicit frame budget.
- **WL-0942 [P1]** Measure memory after repeated panel opening and scene reloads.
- **WL-0943 [P1]** Check detached preview viewports for retained rendering resources.
- **WL-0944 [P1]** Let background observation mode use an explicit lower power budget.
- **WL-0945 [P1]** Make battery-saver choices clear without silently rewriting tank settings.
- **WL-0946 [P1]** Preserve simulation determinism when worker counts or device tiers change.
- **WL-0947 [P1]** Measure worst-case mutation geometry instead of only default bodies.
- **WL-0948 [P1]** Compare low-end device results with review-machine samples explicitly.
- **WL-0949 [P1]** Avoid treating a healthy capped frame rate as an overloaded device.
- **WL-0950 [P1]** Report quality reductions in a quiet discoverable place when they affect appearance.

<a id="topic-39"></a>

### 39. Architecture, contracts, and developer understanding — WL-0951–WL-0975

**Priority:** P2. **Sources:** [README.md](../README.md); [shaders-godot/godot-project/scripts/sim_gate.gd](../shaders-godot/godot-project/scripts/sim_gate.gd); [scripts/check_warnings.sh](../scripts/check_warnings.sh); [data-schemas/README.md](../data-schemas/README.md).

**Review intent:** Improve the existing project rather than introduce parallel replacement systems without evidence.

- **WL-0951 [P2]** Document ownership of each ecological quantity and every permitted mutation path.
- **WL-0952 [P2]** Separate lifecycle events from their visual, audio, journal, and save consumers.
- **WL-0953 [P2]** Extract large controller responsibilities only around stable observed boundaries.
- **WL-0954 [P2]** Keep SimGate contracts current instead of proliferating new duck-typed guards.
- **WL-0955 [P2]** Use typed state objects where they reduce ambiguous dictionary shape handling.
- **WL-0956 [P2]** Record units and time bases next to tunable simulation constants.
- **WL-0957 [P2]** Centralize species identifiers used by genomes, UI, and behavior fallbacks.
- **WL-0958 [P2]** Avoid duplicating trait defaults across live builders and preview builders.
- **WL-0959 [P2]** Make configuration provenance visible for defaults, presets, user changes, and saves.
- **WL-0960 [P2]** Keep autoload order documented outside comment-free project configuration.
- **WL-0961 [P2]** Turn repeated lifecycle setup into shared registration contracts.
- **WL-0962 [P2]** Keep diagnostic code from modifying live simulation state during inspection.
- **WL-0963 [P2]** Document experimental versus shipping mind backends in one architecture map.
- **WL-0964 [P2]** Treat data schemas as proposed contracts until a real runtime loader exists.
- **WL-0965 [P2]** Keep reference Rust model limitations explicit in comparison tooling.
- **WL-0966 [P2]** Reduce comments that claim stronger behavior than current evidence demonstrates.
- **WL-0967 [P2]** Use focused warning annotations only for intentional analyzer limitations.
- **WL-0968 [P2]** Name test helpers so discovery cannot accidentally boot the game.
- **WL-0969 [P2]** Require smoke suites to report nonzero meaningful assertions.
- **WL-0970 [P2]** Make test fixture isolation reusable across visual, ecology, and cognition probes.
- **WL-0971 [P2]** Keep generated outputs out of source discovery and shipping exports.
- **WL-0972 [P2]** Document signals and callbacks that survive scene transitions.
- **WL-0973 [P2]** Use stable event identifiers to deduplicate cross-subsystem consequences.
- **WL-0974 [P2]** Maintain a concise system diagram showing food, chemistry, lifecycle, and cognition dependencies.
- **WL-0975 [P2]** Prefer retiring redundant ideas over growing several competing roadmap documents.

<a id="topic-40"></a>

### 40. Verification, releases, documentation, and community — WL-0976–WL-1000

**Priority:** P2. **Sources:** [.github/workflows/test.yml](../.github/workflows/test.yml); [.github/workflows/release.yml](../.github/workflows/release.yml); [scripts/smoke_baseline.txt](../scripts/smoke_baseline.txt); [steam/REVIEW_FEEDBACK.md](../steam/REVIEW_FEEDBACK.md); [docs/index.html](../docs/index.html).

**Review intent:** The repository already has smoke CI and multiplatform exports; extend evidence and reconcile dated public copy without assuming live store status.

- **WL-0976 [P2]** Keep release claims synchronized with verified exported-build behavior.
- **WL-0977 [P2]** Refresh public launch-date wording only after confirming current distribution status.
- **WL-0978 [P2]** Replace outdated screenshots with representative stable scenarios and accurate captions.
- **WL-0979 [P2]** Explain functional cognition to players through observed examples rather than theory lists.
- **WL-0980 [P2]** Publish a small known-limitations list covering chemistry proxies and representation caps.
- **WL-0981 [P2]** Triage each baselined smoke with a reproducible platform-specific explanation.
- **WL-0982 [P2]** Give known failures an owner and retirement condition.
- **WL-0983 [P2]** Keep performance-sensitive tests serial and isolated from competing workloads.
- **WL-0984 [P2]** Retain per-script timeout reports distinct from genuine assertion failures.
- **WL-0985 [P2]** Add exported-build checks for input, saves, and missing bundled resources.
- **WL-0986 [P2]** Verify embedded voice availability against the documented platform matrix.
- **WL-0987 [P2]** Check package contents without relying on development-machine caches.
- **WL-0988 [P2]** Make release notes explain changed player behavior and migration implications.
- **WL-0989 [P2]** Keep store terminology consistent with free adoption and actual monetization.
- **WL-0990 [P2]** Close recorded platform review issues with evidence from the reviewed build.
- **WL-0991 [P2]** Provide a bug-report template collecting scenario, build, device, and reproduction steps.
- **WL-0992 [P2]** Offer optional diagnostic exports with private dialogue excluded.
- **WL-0993 [P2]** Document where to find logs without requiring players to understand repository internals.
- **WL-0994 [P2]** Use accessibility feedback to prioritize complete workflows rather than isolated controls.
- **WL-0995 [P2]** Collect aesthetic feedback with comparable seeded clips and representative hardware.
- **WL-0996 [P2]** Keep the website's species and feature descriptions aligned with the shipping game.
- **WL-0997 [P2]** Maintain downloadable examples demonstrating care, breeding, and learned behavior.
- **WL-0998 [P2]** Distinguish proposed improvements from implemented and verified work in every roadmap.
- **WL-0999 [P2]** Review this thousand-item list periodically to merge, reject, or retire outdated proposals.
- **WL-1000 [P2]** Choose the next improvement batch by visible player benefit and verified system leverage.
