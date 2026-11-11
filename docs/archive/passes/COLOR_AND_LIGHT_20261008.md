# Color as relationship — 8 October 2026

The guiding reference for this pass is Michel-Eugène Chevreul's 1839
*De la loi du contraste simultané des couleurs*. His work describes how a
surrounding color changes the appearance of a color patch. The museum's account
also connects those relationships with the composition of gardens and paintings.
Sources: [Muséum national d'Histoire naturelle](https://bibliotheques.mnhn.fr/fr/de-la-chimie-a-l-art-comment-chevreul-a-inspire-les-artistes),
[1839 volume at the Metropolitan Museum](https://www.metmuseum.org/art/collection/search/900717).

This is an artistic application of that idea, rather than a simulation of human
color perception. Color is composed through neighbouring materials and light;
there is no screen-space filter that artificially recolors every contact edge.

## The composition

The planted palette moves from petrol water through emerald shadows, sage leaf
planes, and pale golden growing tips. Earth and slate provide quiet surrounds
for coral, honey gold, lapis, plum, and rose markings. All 48 slots and their
existing material banks remain in place. Other biotope palettes keep their
individual character.

Fish highlights preserve pigment hue and chroma instead of mixing heavily with
white. Their sculpted shadows retain more body color. Genome colors, complex
markings, inheritance, and explicit tail/marking colors remain the source of each
animal's identity.

Fixture wash is gentler on both fish and leaves, allowing the shaped beam to
supply the brightest passages. Metallic catches are restrained champagne;
legacy iridescence follows a continuous angle-dependent sheen, with the palette
providing the final pixel steps.

## Where light touches

The analytic beam reflects the surface's pigment in its broad wash. Its hot core
still catches lamp-facing planes. Shaded planes receive a small counter-color to
the lamp: a warm key gains a cooler surround, while a cool key gains a warmer one.
Existing occluders, cone falloff, and contact-shadow geometry drive where this
relationship appears.

The visible shaft keeps the lamp color in its core, while deeper water gently
cools its edges. Existing leaf transmission, midribs, margins, and spring motion
remain responsible for the places where leaves meet and overlap.

These changes reuse existing geometry and lighting terms. They add no render
passes, neighbourhood searches, texture reads, shadow samples, or extra lights.
There is some additional shader arithmetic; GPU timing remains hardware-dependent.

## Palette reliability

Runtime planted colors, the generator's source table, the bundled day LUT, and
the bundled night LUT now agree. Previously the PNG had a different accent layout
from the runtime palette. A shared night helper produces the same moonlit colors
for runtime textures and generated assets. Regenerate the game LUTs with:

```bash
./scripts/dev_run.sh --headless --script res://dev/regenerate_planted_palette.gd
```

The Python preview generator reads the authoritative planted table too.
Colorblind remapping, duotone, photo
mode, and the palette lock keep their existing paths.

## Verification

The color regression checks hue-preserving body ramps, bounded highlights,
ordered leaf lightness, and all day/night palette slots against the runtime data.
Isolated daytime and nighttime captures are inspected alongside the original
frame. Shader render logs, compile/warning checks, and the complete smoke suite
cover pipeline and existing behavior contracts. Player saves are isolated.

Final validation: all 242 smoke tests passed; the color suite passed 239
assertions; all 578 scripts compiled with zero analyzer warnings. Day, final
night, and reef renders were inspected. Every isolated run preserved the real
tank inventory. The dense sandbox capture still flags its focal offset and
swimming corridor composition heuristics; this palette pass does not change
the tank's planting layout.

The capture harness still reports resource teardown diagnostics when quitting a
full tank; this art pass does not resolve that separate cleanup issue.

The subsequent [fish flash diagnosis](FISH_FLASH_DIAGNOSIS_20261008.md)
reproduces a hard self-shadow boundary and softens the reflected fish highlights.
