# walstad loom pixel-art style guide

The look is **pixel art with sim depth underneath**. Internal sim runs continuous; render pass quantizes to chunky pixels + a small palette. Animation comes from the sim, not from sprite frames.

## 1. Resolution & camera

- **Internal render target:** `384 × 216` (16:9, 1/5 of 1080p, scales cleanly to 1080p and 4K).
- **Upscale:** nearest-neighbor only. No bilinear. No subpixel AA.
- **Pixel aspect:** 1:1 square.
- **Camera framing:** the tank fills ~70% of the viewport. Leave room above (lid, fixture, room beyond) and below (stand + cabinet) like the reference photo.
- **Above/below water split:** the meniscus line is exactly **1 pixel tall**, value-shifted brighter on the day side. Sample it from the SPH surface field, snapped to the nearest internal row.

## 2. Palettes — three biotopes

Each biotope has a 48-color master palette derived from a 12-color base (warm, cool, neutral, accents) × 4 value steps. Hex codes below are starter values — tune by eye.

### 2a. Planted (your tank — green-lush, neutral water)

```
Water cool ramp:    #0b1a22  #163040  #23475a  #356379  #4b8095  #69a1b3  #92c3d0  #c5e2e7
Plant green ramp:   #102614  #1d3b22  #2c5a30  #3e7f40  #57a253  #79c069  #a5d97e  #d0eb9a
Substrate browns:   #1a120c  #2c1f15  #432f1f  #5d4128  #785538  #95714e  #b18f6a  #cdb088
Stone grays:        #1a1a1f  #2a2a30  #3d3d44  #555560  #707081  #8c8ca0  #a8a8bd  #c4c4d6
Glass/highlight:    #ffffff  #e0eef2  #b9d6df
Tannin tint (mul):  #d8b888  (multiplied over water ramp at high tannin levels)
Fish accents:       #c33b3b  #d97e2c  #e6c92a  #2a7a4b  #4a52c4  #872cb0  #c44a8e
```

### 2b. Blackwater (Rio Negro vibe — tea-stained, low-light)

```
Water:              #0a0907  #15110b  #251c10  #382a14  #4d3a1c  #6a5128  #8c7042  #b9986a
Substrate:          #0c0905  #1a130a  #2b2014  #3d2f1e  #57442d  #735c40  #927758  #b29575
Plant (sparse):     #0e1a0d  #1b2d18  #2c4527  #4a6738  #6c894e  #95ad6f
Light shafts:       very thin, only top 30% of column, dust-mote dither.
```

### 2c. Hard alkaline (Tanganyika-style — pale rock, clear blue-green water)

```
Water:              #0d1f25  #1a3947  #2e5a6e  #467c92  #62a1b4  #87c2cf  #b3def0
Substrate (sand):   #2a2620  #423d34  #5d574b  #7c7466  #9e957f  #c0b899  #ddd6b5
Stone (light):      #4a4943  #6b685d  #8b8678  #aaa595  #c5c0b0  #ddd9c8
Plant: very limited (Vallisneria green) — rock biotopes are sparse on plants.
```

Store palettes as 48×1 RGBA PNGs. Lookup in shader is `texture(palette, vec2(index/48.0, 0.5))`.

## 3. Dithering rules

- **Bayer 4×4** for: water turbidity haze, light attenuation gradient with depth, plant volume shading, tank-glass reflection falloff.
- **Blue-noise dither** for: detritus suspension, fish scale shimmer, bacterial cloudy-water bloom (organic, less patterned).
- **No dither** for: hard edges (glass frame, hardscape silhouettes, fish body outlines).
- Dither only happens at the quantization step in the shader — never bake into sprites.

Bayer 4×4 matrix (divide by 16):

```
 0  8  2 10
12  4 14  6
 3 11  1  9
15  7 13  5
```

## 4. Pixel grid conventions

- **Fish body length:** 6–24 pixels (tetra-sized → adult cichlid). Eye is always a single pixel.
- **Plant stem segment:** 1px wide, 3–6px tall per L-system unit.
- **Plant leaf:** 2–5px wide, dithered interior for volume.
- **Substrate grain:** 1px = one cell. Substrate fills full pixels except at the angle-of-repose slope, where 50% dither edges feather it.
- **Bubble:** 1px (microbubble), 2×2 (small), 3×3 cross-shape (medium), 4×4 with 1px highlight (large). Bubbles wobble by ±1px laterally as they rise.
- **Hardscape:** silhouettes hand-authored, internal shading procedural from the palette ramp.

## 5. Animation philosophy

- **No keyframed sprite animation for sim entities.** Fish swim because the sim moves them; plants sway because flow tilts them; bubbles rise because particles rise. Animation is a side effect of physics.
- **Hand-authored** only for: water-change pouring, scoop tool, UI feedback, photo flash.
- **Sub-pixel motion shows up as dither pattern shifts** — this is the shimmer effect. Do not damp sub-pixel motion in the sim just because the screen snaps to integers; that's what creates the life.

## 6. Lighting

- Per-column light attenuation: `I(y) = I0 * exp(-k * (depth + turbidity*scale))`.
- Output light value modulates palette **index**, not RGB — slides you down the palette ramp, preserving the limited-palette look. Never multiply RGB directly.
- Caustics: a slow scrolling 1-bit noise mask added to substrate value, weighted by surface flatness.

## 7. Reference checklist (what the fishing-game image gets right)

- Clean horizon meniscus line, sharp 1px transition.
- Above-water palette warmer + lighter; below-water cooler + darker, but **same value range** so it doesn't feel like two games stitched together.
- Tiny silhouette fish underwater — readable as fish at 4–6px. Aim for the same.
- Sky and clouds use the *same* palette ramp as water, just shifted. The unity of the palette is what makes it feel composed.

## 8. Don'ts

- No outlines that aren't black or palette-darkest.
- No anti-aliasing.
- No HDR bloom on anything except point lights + bubble highlights.
- No more than 48 colors on screen at any time, ever. Counter that in a debug overlay.
- No baking sim motion into spritesheets — it kills the emergence.
