# Translation catalogues

Compiled `.translation` files dropped here are picked up automatically by
`scripts/localization.gd` — adding a locale is a data change, not a code one.

The project uses **English-as-key**: the source string *is* the catalogue key,
so `tr("Adopt fish")` looks up `"Adopt fish"`. A locale with no entry for a key
falls back to readable English rather than a raw identifier.

## Workflow

1. Extract the current key set:
   `./scripts/godot.sh --headless --path shaders-godot/godot-project --script res://dev/i18n_extract.gd`
   — writes `strings.pot`-style CSV here.
2. Translate the CSV.
3. Import it in the Godot editor (it produces `.translation`), leave the
   result in this directory.

## Before translating anything, run the pseudolocale

Settings → Advanced → Language → **Pseudolocale (dev)**. Every string that went
through `tr()` renders as `⟦Ådöpt fïšh···⟧`. Two things become visible:

- **Plain English on screen = never wrapped.** That is the extraction gap.
- **Clipped or overflowing text** = the layout cannot survive a real
  translation. The padding simulates the ~30% expansion German and Finnish
  routinely bring.

Fixing those first is cheaper than discovering them after a translator has
been paid.

## Why the pseudolocale is `qps`, not `en_XA`

Godot's `TranslationServer` matches locales by **prefix**, so an `en_XA`
catalogue counts as a match for `en` — the pseudolocale leaks into the English
build and real players see `⟦…⟧`. `qps` is the reserved pseudo-locale range
(as in Windows' `qps-ploc`) and shares no prefix with any shipping locale.
`smoke_localization.gd` asserts this, because it was found by running the
thing rather than by reading the code.
