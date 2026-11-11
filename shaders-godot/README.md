# Godot 4 rendering pipeline

Doc map: [docs/INDEX.md](../docs/INDEX.md). Clocks and sim layers:
[ARCHITECTURE.md](../ARCHITECTURE.md). Render + carve details:
[docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) §11.

The look is a **3D voxel scene rendered through a 2D palette-quantize +
dither shader**. The internal sim runs continuous — fish swim, plants grow,
substrate diffuses — and the final pixel grid emerges from the shader pass,
not from hand-authored sprites.

## Pipeline

```
  Camera3D in SubViewport (TankConfig default 1024×576)
        │ renders voxel scene to a low-res texture
        ▼
  Display TextureRect
        │ applies palette_quantize.gdshader (snap to 48-color palette + Bayer dither)
        ▼
  Window (nearest-neighbor upscale to 1536×864)
```

Shipping internal size is **1024×576** (`TankConfig.render_width/height`).
512×288 is the beauty / first-launch **mid** fidelity tier, not the
default. Adaptive quality can step potato (256×144) through desktop.
The voxel scene lives in `SubViewport/World/...`. The `Display`
`TextureRect` samples that buffer through the palette shader.

## Shaders

| File | Purpose |
|---|---|
| `palette_quantize.gdshader` | Output stage. Snaps every pixel to the nearest of 48 palette colors using a Bayer 4×4 dither between the two nearest hits. |
| `voxel.gdshader` | Unshaded, face-based brightness (top 100%, sides 82% / 68%, bottom 50%). Lets cubes self-light without a directional light fighting the palette. |
| `circle_mask.gdshader` | PiP portal — circular feathered cutout for the follow-camera bubble. |

The full shader set lives in `godot-project/shaders/` (water, glass, caustics,
foliage/SSS, god rays, substrate, bubbles, plus the `voxel*` material family).
See the root [README.md](../README.md) "shaders (the pipeline)" section for the map.

## Scene structure (current — Godot 4, 3D)

```
Main (Node)                          # main.gd, root
├── SubViewport (1024×576 default)   # the actual 3D scene
│   └── World (Node3D)               # world.gd, builds substrate + plants + creatures
│       ├── WorldEnvironment         # palette-friendly soft env
│       ├── DirectionalLight3D       # very low energy, fill only
│       ├── Camera3D                 # driven by main.gd's orbit code
│       ├── SimDriver (Node)         # sim_driver.gd, 10 Hz brain tick
│       ├── SubstrateGrid            # nutrient field + voxel substrate
│       ├── Hardscape                # stones, driftwood
│       ├── PlantsRoot               # plant.gd children
│       ├── Fish / Shrimp / Snails   # agent containers
│       └── Waste                    # mulm + detritus
├── Display (TextureRect)            # palette_quantize material
├── PortalContainer (Control)        # PiP follow-cam
├── TopHUD (Control)                 # cluster pills + chip strip
├── Panels                           # Settings / Render / Sound / Library /
│                                    #   FishStore / ScenarioPicker / Walkthrough
├── AquascapeToolPalette             # build-mode dirt/stone/wood/dig
├── ControlsHint (Label)             # bottom-edge keyboard hint
├── MobileHUD                        # bottom-corner touch buttons
└── AmbientAudio
```

The Sim runs at 10 Hz inside `SimDriver._tick()`; every agent's `_process()`
runs at render rate and does smooth heading + speed integration so motion
stays fluid between brain ticks. See the top-level [README.md](../README.md)
for architecture details on the food web, schooling, lifecycles, motion
stability, and persistence.

## Editor setup

| Setting | Value |
|---|---|
| `Rendering / Default Texture Filter` | Nearest |
| `Rendering / Mobile renderer` (preferred for color stability) | Mobile |
| `Display / Window / Stretch / Mode` | canvas_items (aspect expand) |
| `Display / Window / Handheld / Orientation` | sensor |
| `2D / Snap / Snap 2D Transforms to Pixel` | true |
| Project name | walstad loom |
| Main scene | `res://tank_menu.tscn` |

## Quickstart

1. Open Godot 4.6+, **Import** this `godot-project/` directory.
2. If the palette PNG looks off, regenerate it: `python3 ../make_palette.py`.
3. Press **F5** — should open the tank menu. Click **+ New tank**.

## Adding a species

Append an entry to `scripts/tank_config.gd`'s `SPECIES_LIBRARY` dict
(18 playable spawn templates today). Required fields: `label`,
`description`, `genome` (with at least `species`, colors,
`adult_voxel_scale`, `max_speed`, `preferred_y`). `world.gd` reads the
library at spawn time. `real_species_library.gd` / `real_species_fauna.gd`
are discovery catalogs, not spawn tables.

Then reference the new species by key in any preset's `stocking` dict in
`TANK_PRESETS`, or add a brand new preset. Both the settings dropdown
and the Species & Diet chart pick up the new entry automatically.
