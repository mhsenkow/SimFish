# Fish flash diagnosis — October 8, 2026

## Whole-fish whitening in Iwagumi

The later screenshot identified a second, larger fault. A copy of the player's
Iwagumi Stone Garden (tank 29) reproduced entire pink/red fish becoming cream
or white in the final palette image. The raw image already showed the pigment
washing out. The affected fish had no bioluminescence, metallic finish, or
belly-flash signal active.

Four routines independently wrote colors derived from the original voxel
color: age, maturity, stress flush, and emotional/courtship pallor. Adults
restored original colors every biological tick (10 Hz), while pallor wrote
at a different render cadence. Juvenile and senescent washes could similarly
be erased by another writer. A deterministic probe of one body voxel produced
green-channel values 0.233 → 0.129 → 0.468 → 0.000 as those writers ran.
The palette amplified these real pigment jumps into the conspicuous pale
fish in the screenshot. Reducing specular highlights alone could not fix it.

There is now one whole-body color writer. It composes life stage, emotional
pallor, courtship, and a small warm-tissue flush, then eases the combined state
over time. Juvenile and stressed colors soften within their pigment hue;
neither treatment paints the entire animal silver-grey. Blue markings and
dark eyes remain distinct. Senescence is gradual and can recover naturally
if feeding reduces biological age. Fin tissue density is preserved.

The writer runs outside motion substeps, admits color uploads at most 10 Hz,
and skips changes below 0.008 in the wash state. Calm adults no longer rewrite
every voxel's original color on every biological tick. No blur, extra draw
pass, render texture, or temporal-history buffer was added for this fix.

### Saved-tank comparison

Both runs restored the same saved tank inside verified development isolation,
with its 1024×576 render size, sunny lighting, and quality tier 2. Each captured
120 consecutive raw/final frames and sampled a body voxel's CPU upload color
for each tracked fish. Both populations grew from 30 to 40 fish during capture.

| Uploaded pigment measurement | Before | Final |
|---|---:|---:|
| Adjacent tracked-fish comparisons | 3,932 | 3,942 |
| Largest channel jump (0–1) | 0.461700 | 0.007622 |
| 99th percentile channel jump | 0.148173 | 0.003099 |
| Channel jumps above 0.1 | 52 | 0 |
| Largest adult channel jump | 0.237006 | 0.002926 |

These are uploaded pigment measurements, not a claim that every screen pixel
remains constant as fish swim. Live trajectories, births, shader time, and
background coverage differ between runs. Visual inspection of the raw/final
sequences confirms the reproduced cream-white body transitions disappear;
the quantitative comparison isolates their color-writing cause rather than
counting bright window pixels behind a fish.

The same pass found that `init_genome()` rerolled each individual's hue,
saturation, and value variation on save restore. The cosmetic roll now lives
in save state, outside heritable genome traits. Old saves derive a repeatable
roll from the fish's persistent identity. Their precise previous cosmetic roll
cannot be recovered because it was never saved, but later reloads are stable.

`scripts/smoke_fish_pigment.gd` exercises real interleaved biological/render
ticks, bounded pigment changes, visible emotional response, preserved membrane
density, new save restoration, and repeatable legacy-save appearance.
Its 144 assertions pass. The full suite passes all 243 smokes in 138 seconds
with zero failures or timeouts; all 582 scripts compile with zero analyzer
warnings. Each saved-tank capture preserved the real tanks inventory.

A subsequent senescent-fish run exposed one missed caller in
`MakeItThere._tick_breaking_beauty()`: it still read the removed `_aged_applied`
render flag. The behavior now relies on its existing senescent-life-stage
guard. The pigment regression adds guaranteed senescent and adult branch
checks (146 assertions total); it and the existing presence smoke pass.
All removed color fields and functions were checked for remaining callers,
and the follow-up compile check remains at 582 scripts with zero warnings.

Reproduce the saved-tank inspection with a read-only snapshot folder containing
`config.cfg`, `state.json`, and `meta.cfg`:

```bash
FISH_FLASH_SLOT_DIR="$PWD/output/iwagumi_snapshot" \
VISUAL_CAPTURE_ANGLES=custom \
VISUAL_CAPTURE_CAM=-0.06,0.05,32.3,0.56 \
VISUAL_CAPTURE_SETTLE=120 VISUAL_CAPTURE_SEQUENCE_FRAMES=120 \
VISUAL_CAPTURE_OUT="$PWD/output/iwagumi_pigment" \
  ./scripts/dev_run.sh res://dev/fish_flash_probe.tscn
```

The probe records raw/final frames, uploaded body pigment, original pigment,
age, color maturity, stress, mood, and effect signals. Diagnostic iridescence
disabling now clears both the shared material uniform and per-voxel custom
data, so an ablation cannot accidentally leave half of the sheen enabled.

## Earlier reproduced shadow fault

The shared analytic shadow shader skipped a sphere entirely whenever a
fragment lay inside it. Immediately outside its radius, that sphere could
apply its full shadow. A moving fish voxel could therefore jump between two
lighting states at the boundary.

A controlled render of the actual fauna shader placed a sphere one radius
above a fixed surface fragment. Moving its centre from radius minus 0.000001
to radius plus 0.000001 world units changed measured output luminance from
0.862646 to 0.590689: a 0.271957 jump across a tiny position change. These
are pixel measurements from the renderer, rather than a reimplementation of
the lighting formula.

The self-shadow exclusion now feathers over the outer quarter of the sphere's
radius. Squared distances keep this within the existing fragment loop. The
perpendicular-distance square root also clamps small negative rounding errors
to zero, avoiding undefined shading on nearly collinear light rays.

After the change, both boundary samples render at 0.682270 on the MultiMesh
path and 0.489279 on the legacy material path. Cast shadows still darken the
surface farther from the exclusion boundary. This reproduces and fixes one
definite source of abrupt fish lighting; it does not establish that every
possible intermittent artifact has the same cause.

## Softer reflections

Fish scale, fixture-core and rim catches use a 22% reflection layer. Rim and
metallic highlights keep most of the surface pigment instead of adding an
opaque white tint. Caustics on fish are weaker and modulate their pigment;
the small shimmer amplitude is reduced too.

The shared scale highlight has a broad smooth falloff. Fragment derivatives
soften catches smaller than a render pixel. This gives the highlight a soft
appearance while leaving the fish's markings sharp. There is no screen blur,
temporal history texture, extra draw pass or additional shadow sample.

Legacy fauna now use continuous world-space face shading and continuous
metallic sheen rather than hard view-space brightness buckets. The beam's
full-strength catches remain available to other materials. Genuine
bioluminescence retains its separate path.

## Diagnostic tools and evidence

`dev/fish_flash_probe.tscn` extends the shipped visual capture harness. It
writes consecutive raw and palette-processed frames, fish effect state,
projected positions and readback timestamps in microseconds. Those timestamps
describe frame sampling; they do not claim a renderer capable of displaying
one million distinct frames per second.

The initial sandbox trace had no active belly, display or bioluminescent
signal. A separate saved-tank run restored a copy of tank 28 inside verified
development isolation. An early fixed close angle was inside that tall tank's
hardscape, so the useful saved-tank comparisons use a camera aimed into its
upper swimming column instead.

Before/after sequences comprise 80 frames each for the sandbox and 60 each
for the framed saved-tank copy. Fish paths and shader time vary between live
runs, so these are qualitative motion checks; the controlled surface render
provides the exact numerical comparison. The first sandbox run's inventory
check detected the player's concurrent game updating tank 28. That capture
was isolated and its preflight succeeded; no recovery copy was restored over
the player's newer save. Subsequent validation preserved the real inventory.

Run the rendered regression with a real renderer, through isolation:

```bash
FAUNA_REFLECTION_OUT="$PWD/output/flash_shadow" \
  ./scripts/dev_run.sh --script res://dev/fauna_reflection_probe.gd
FAUNA_REFLECTION_LEGACY=1 FAUNA_REFLECTION_OUT="$PWD/output/flash_shadow_legacy" \
  ./scripts/dev_run.sh --script res://dev/fauna_reflection_probe.gd
```

Each material path passes nine rendered assertions: boundary continuity,
actual shadow response, restrained reflected light and finite pixel output.
All 242 smoke tests passed in 144 seconds, with no failures or timeouts.
The final compile check covers 580 scripts with zero errors and zero analyzer
warnings. Full-tank captures still produce the previously documented resource
teardown diagnostics on exit; the small controlled probes shut down cleanly.
