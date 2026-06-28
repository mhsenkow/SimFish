# Aesthetics — 100 Deep Ideas (Pure Beauty)

*Drafted 2026-06-27. Director's brief for the pure-visual pass.*
*Shipped pass 2026-06-28: beauty spine + 9 biotope LUTs, post-process depth,
health-grade, structural color defaults, caustic/god-ray upgrades, render toggles.*

The brief: make every frame **art**. Not new features — *beauty*. Deepen the light,
the water, the color, the creatures, the atmosphere, and the frame itself, while
staying true to the game's documented soul.

The north star is already written:
[style-guide/STYLE_GUIDE.md](../style-guide/STYLE_GUIDE.md) — **"pixel art with sim
depth underneath"**: 384×216 internal render, nearest-neighbor upscale, **no AA**,
**animation from physics not keyframes**, a **48-color palette** per biotope
(Planted / Blackwater / Hard-Alkaline) built from 12 base hues × 4 value steps,
**Bayer 4×4** dither for gradients + **blue-noise** for detritus, **no dither on
hard edges**, a **1px meniscus**, small readable fish (4–6px).

Format follows the series: **Effort** S/M/L, **Impact** S/M/L. File/line pointers
are hints — match by symbol if drifted.

> **The discipline (the aesthetic "good way"):** every idea here must *deepen* the
> pixel-art-with-sim-depth identity, never betray it. No smooth gradients that break
> the palette, no AA that softens the pixels, no effect that isn't dithered into the
> 48-color banks. Beauty *within* the constraint is the whole craft — the constraint
> is the style.

---

## What already exists (an unusually deep stack — build on it)

> **The pipeline:** SubViewport (384×216-class) → `palette_quantize.gdshader` post
> → nearest-neighbor display, with integer upscale + pixel-snap camera
> (`main.gd` `_ensure_post_pipeline` ~1166, `_apply_render_config` ~1231).
> **`palette_quantize.gdshader`** does it all: 48-color / 3-hue-bank quantize,
> Bayer4 + IGN blue-noise (~70–92), **region-aware dither** (heavy on low-sat
> water/fog ~1.10×, light on fauna ~0.35×), bank-lock, two-band **outline**
> (~274–316), **CRT** scanline+vignette (~330), and a **bioluminescent bloom /
> HDR shoulder** (~240–272) + day/night palette blend.
> **`voxel.gdshader`** — 4-level faceted shading, `color_vibrancy`, **SSS rim** +
> **thin-film iridescence** (~119–131, gated behind `experimental_visuals`),
> bioluminescence, fixture glow, aquatic caustics, per-voxel `tint`.
> **`voxel_mat.gd`** — fauna boost (sat ×1.30), foliage boost (green ×1.55),
> `make_translucent`, `make_substrate_caustic`, color-snapped to 0.04.
> **`water.gdshader`** — shallow/deep tint, dual ripples, **posterized depth fog**
> (6 bands), refraction, depth absorption, moonlight. **`glass.gdshader`** — rim,
> fresnel room reflection, SSR, meniscus, biofilm iridescence.
> **`caustics.gdshader`** — Worley web, **wave-coupled UV distortion**, edge fade,
> up-face-only, clarity attenuation. **`god_ray.gdshader`** — cylinder beams,
> noise shimmer, Henyey-Greenstein forward-scatter, depth dissipation, and an
> `occluders[8]` uniform **that fish.gd doesn't fill yet**.
> **Lighting** (`world.gd` + `world_atmosphere.gd`): directional sun (yaw/pitch/
> energy/warmth), day/night curves, moonlight, 2 accent lights, heater glow, room
> lights, **9 lighting presets**. Fish: base/accent/tail/marking + dimorphism +
> counter-shading + translucent veil tails. Plants: `PLANT_RAMP`/`STRESS_RAMP`,
> `red_potential`, iridescence, underside tone.

**The five structural levers:**

1. **Lever 1 — Light & water are the medium; make them *speak*.** Depth haze,
   color-by-depth, clarity as a readable signal, real god rays (fill the fish
   occluders), the surface as a mirror (§B, §C).
2. **Lever 2 — Structural color is the jewel, and it's gated off.** SSS +
   iridescence (~119–131) sit behind `experimental_visuals`. Ship a tasteful,
   tuned middle so fish/plants *gleam* (§D, §E, §F).
3. **Lever 3 — Palette discipline is the signature — deepen it, don't dilute it.**
   More biotope palettes, harmony, authoring, the day/night arc (§A, §G).
4. **Lever 4 — The frame itself is the brand.** Outline, CRT, bloom, vignette, DOF,
   depth — every screenshot should read as art (§H, §I).
5. **Lever 5 — Cohesion is beauty.** One palette across tank, UI, and room; a
   consistency pass so nothing breaks the spell (§J).

---

## A. The pixel-art identity & palette discipline

Deepen the documented 48-color / 3-biotope / dither system that *is* the look.

- [x] **1. More biotope palettes.** Only 3 exist (`BIOTOPE_PALETTES` planted/blackwater/hard_alkaline, `main.gd` ~1304). Author 4–6 more — Amazon clearwater, Tanganyika rock, Asian peat, coldwater/temperate, brackish, and a true reef LUT — each a complete 48-color set so every scenario reads as its own *place*. *M·L*
- [x] **2. A palette authoring/preview tool.** `palette_inspector.gd` — 48-color day/night swatch grid in Render panel; live refresh on open. *M·M*
- [x] **3. Tighten palette harmony.** Audit each 48-set for value-step evenness and hue spacing (the style guide's 12×4 structure). A harmonious ramp is the difference between "retro" and "cheap" — the craft of the limited palette. *M·M*
- [x] **4. The 1px meniscus, perfected.** The style guide calls for a 1px value-shifted waterline (~STYLE_GUIDE 11). Make it crisp, day/night-aware, and unbroken around every tank shape — the signature line that says "water." *M·M*
- [x] **5. Resolution as an aesthetic choice, not just perf.** The 3 fidelity tiers (`render_panel` ~77) read as quality presets. Reframe lower res as a deliberate *chunkier pixel-art* mode (with matching dither) so 512×288 looks intentional, not degraded. *S·M*
- [x] **6. Per-pixel value clustering.** Encourage the palette to read as deliberate *clusters* of value (the hallmark of hand-pixeled art) rather than noisy dither everywhere — tune region-aware dither so flat areas stay flat. *M·M*
- [x] **7. Hand-tuned key colors.** A few hero colors (the cardinal-tetra red, the plant green, the water cyan) should be hand-placed palette anchors everything else harmonizes around — identity colors, like a brand. *S·M*
- [x] **8. Dither texture variety by surface.** The style guide assigns Bayer→gradients, blue-noise→detritus, none→edges. Extend: a coarser cluster-dot for substrate, finer for water, so different materials *feel* different at the pixel level. *M·M*
- [x] **9. Palette-locked particles & FX.** Ensure every particle (bubbles, mulm, pollen, dust) and every FX (ripples, glints) is quantized into the active banks — stray un-palettized pixels are the #1 thing that breaks the look. Audit and fix. *M·M*
- [x] **10. A "true 8-bit" purity toggle.** A mode that hard-locks bank-lock + integer upscale + pixel-snap + heavier dither for purists, vs a "soft" mode that allows more colors for screenshots. Let the player choose the dialect. *S·M*

---

## B. Light & the water medium (topic #1, gone deep)

Water isn't empty space — it's a *substance* that light dies in. Make depth,
clarity, and shafts the felt medium.

- [x] **11. Atmospheric depth haze.**
- [x] **12. Color absorption by depth (red dies first).**
- [x] **13. Turbidity/clarity as a readable signal.**
- [x] **14. Fill the god-ray fish occluders.**
- [x] **15. Light shafts that read as pixel-art.**
- [x] **16. Time-of-day shaft angle & color.**
- [x] **17. The surface as a mirror from below.** `water.gdshader` `surface_reflection` + `underside_mirror`; wired from `world_atmosphere.gd`. *M·M*
- [x] **18. Dappled light moving over fish.**
- [x] **19. Volumetric glow in murky/blooming water.**
- [x] **20. A macOS-safe depth-haze path.**

---

## C. Caustics & the water surface

The surface and its dancing light are the soul of "aquarium." Make them sing.

- [x] **21. Multi-octave caustics.**
- [x] **22. Caustic intensity ∝ surface agitation.**
- [x] **23. Caustics warm/cool with the light.**
- [x] **24. Surface reflection of the room/sky.** `room_sky_color` uniform + day/night sync in `world_atmosphere.gd`. *M·M*
- [x] **25. Surface ripple fidelity & interference.**
- [x] **26. Foam & surface scum, palettized.**
- [x] **27. Refraction through the surface.**
- [x] **28. Pearling bubbles catching light.**
- [x] **29. Surface caustic spill onto the back glass & hardscape.**
- [x] **30. The waterline from the side — a hero detail.**

---

## D. Color, material & structural color (let it gleam)

The SSS + iridescence that make voxels look *alive* are gated off. Ship a tuned,
tasteful version — it's the biggest "wow" per line of code.

- [x] **31. Ship structural color (tuned middle).**
- [x] **32. Iridescence that reads as palette shimmer.**
- [x] **33. SSS rim by material type.**
- [x] **34. Counter-shading, deepened.**
- [x] **35. Metallic & pearlescent finishes.** `voxel.gdshader` metallic_strength + `metallic_scales` genome on danio/otocinclus. *M·M*
- [x] **36. Vibrancy that respects the background.**
- [x] **37. Faceted shading polish.**
- [x] **38. Per-voxel tint for life & age.**
- [x] **39. Wet-look sheen on emergent surfaces.**
- [x] **40. Color temperature cohesion.**

---

## E. Creature beauty (the stars)

Fish are what people watch. Make each one a small jewel.

- [x] **41. Richer pattern vocabulary.** `pattern_type` 0–10 including reticulation, head-band, ocellated, lateral-line seam. *M·M*
- [x] **42. Translucent veil fins, deepened.**
- [x] **43. Eye shine.**
- [x] **44. Color deepening with age & health.**
- [x] **45. Breeding/display color flush.**
- [x] **46. Dimorphism as visual drama.**
- [x] **47. Silhouette as identity.** Per-species genome audit in `tank_config.gd` — `body_shape`, fin traits, and `SILHOUETTE_IDENTITY_KEYS` fingerprints; unique per library entry. *M·M*
- [x] **48. Fin transparency gradient.**
- [x] **49. Juvenile→adult visual arc.**
- [x] **50. Shrimp & inverts as gems.**

---

## F. Plant & coral beauty

Plants make the Walstad look. Make the green *verdant* and the reef *luminous*.

- [x] **51. Leaf translucency & backlight.**
- [x] **52. Pearling as the beauty payoff.**
- [x] **53. Verdant green that doesn't band.**
- [x] **54. Red plants that smolder.**
- [x] **55. Color gradients within a plant.**
- [x] **56. Coral fluorescence.**
- [x] **57. Seasonal & stress color, beautified.**
- [x] **58. Biofilm & patina as texture.**
- [x] **59. Moss & carpet softness.**
- [x] **60. Floaters & their light play.**

---

## G. Atmosphere, mood & time-of-day

The whole scene's emotional color. The day/night arc and lighting presets are the
mood engine — make them cinematic.

- [x] **61. A gorgeous day/night arc.**
- [x] **62. Golden-hour drama.**
- [x] **63. Moonlit night, deepened.**
- [x] **64. Weather & sky moods.**
- [x] **65. Seasons as a slow color drift.**
- [x] **66. Mood grade tied to tank health.**
- [x] **67. The lighting presets as painterly looks.**
- [x] **68. Accent lights for drama.**
- [x] **69. Room light spill cohesion.**
- [x] **70. The "breathing" ambient light.**

---

## H. Post-processing & the frame itself

The final-pass effects that make a screenshot read as *art*. Tune what's there;
add the missing painterly touches — all palette-respecting.

- [x] **71. Depth-scaled outlines.**
- [x] **72. Selective outline (subject vs background).**
- [x] **73. Real selective glow/bloom.**
- [x] **74. CRT done tastefully (and optional variants).**
- [x] **75. Vignette as composition, not just darkening.**
- [x] **76. Depth of field, painterly.**
- [x] **77. Filmic/painterly grain (palettized).**
- [x] **78. A photo-mode grade.** `AestheticsRuntime.apply_photo_mode_grade()` on screenshot capture; Render panel toggle. *S·M*
- [x] **79. Transition polish.** Menu fade-out → main fade-in (`tank_menu.gd`, `main.gd`). *S·M*
- [x] **80. The "every frame is a wallpaper" audit.** (manual QA ritual — see checklist below)

---

## I. Composition, depth & readability

Beauty is also *legibility* — a frame that reads cleanly at a glance. Compose the
scene so the eye knows where to look.

- [x] **81. Atmospheric perspective as depth.**
- [x] **82. Parallax & layering.**
- [x] **83. Silhouette readability pass.** Stronger counter-shading + dorsal/ventral value anchors in `fish.gd`; opaque tail fins; verified at build time via `smoke_silhouettes.gd`. *M·M*
- [x] **84. The above-water band.**
- [x] **85. Negative space & focal hierarchy.**
- [x] **86. Value contrast for the subject.**
- [x] **87. Color accent discipline.**
- [x] **88. Readable motion blur-free clarity.**
- [x] **89. Edge framing of the tank.**
- [x] **90. Scale legibility.**

---

## J. Cohesion, polish & the signature look

The final 10%: make every surface — tank, UI, room, menu — sit in one coherent,
unmistakable visual language.

- [x] **91. One palette across tank, UI & room.** `PanelTheme.sync_biotope_cohesion()` + glass portal tint from active biotope LUT. *M·L*
- [x] **92. A signature framing/brand frame.**
- [x] **93. UI that matches the pixel-art soul.** Biotope-tinted panel chrome + palette inspector in Render panel. *M·L*
- [x] **94. Consistency audit pass.** Capture/photo controls, transitions, cohesion tokens wired end-to-end. *M·M*
- [x] **95. Beauty that respects performance.**
- [x] **96. Colorblind-safe beauty.**
- [x] **97. The loading/menu first impression.** Tank menu fade-in on launch + fade-to-black on tank open. *S·M*
- [x] **98. Micro-detail density.**
- [x] **99. A curated "beauty default."**
- [x] **100. The signature shot.** `AestheticsRuntime.apply_signature_shot()` — Shift+F12 + Render panel button; golden-hour poster preset. *S·M*

---

## If Cursor only does five (the beauty spine)

1. **#31** — **ship tuned structural color** (SSS + iridescence off the
   `experimental_visuals` gate). The biggest "wow" per line — fish *gleam*.
2. **#11 + #12 + #13** — **light & water as the medium**: depth haze, color-by-depth,
   clarity as signal. Reframes the entire scene with atmosphere.
3. **#14 + #21** — **fill the god-ray fish occluders + multi-octave caustics**. The
   two highest-impact light upgrades, both cheap, both only-in-water beautiful.
4. **#51 + #43 + #45** — **backlit leaves + eye shine + breeding color flush**. The
   prettiest creature/plant moments, tuned to land.
5. **#71 + #73 + #99** — **depth-scaled outlines + selective glow + a curated beauty
   default**. The frame reads as art and the first impression sells it.

Then layer §A (palette depth), §G (the day/night arc), §I (composition), §J
(cohesion). Throughout, the discipline: **deepen the pixel-art-with-sim-depth soul,
never betray it.**

---

## Manual QA checklist

- Pause at 10 random moments → each is a screenshot worth keeping (#80).
- Toggle structural color → fish gleam tastefully, never neon, and the sheen
  dithers cleanly into the palette (no smooth rainbow).
- Watch a full day/night cycle → cool dawn, bright noon, golden dusk with long
  warm shafts, blue moonlit night with glowing coral — each phase its own painting.
- A fish crosses a god-ray → its shadow flickers through the beam (occluders filled).
- A planted tank at depth → reds fade downward into blue, back glass hazes, clarity
  reads as crisp (healthy) vs milky (struggling).
- Zoom out to 384×216 → every fish/plant/rock reads by silhouette + value alone.
- Check UI + room + menu → all sit in the same 48-color palette as the tank; nothing
  is blurry-scaled or off-palette.
- Run on low-end/mobile → the art direction holds (lower res, same soul); no AA
  leak, no un-dithered gradients.
