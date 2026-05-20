# Vivarium

A generative pixel-art aquarium running as a 3D voxel scene through a palette-quantize + dither shader pipeline. Plants grow, fish school and breed, shrimp climb plants and snap at fry, snails crawl the glass and eat detritus. The whole thing self-balances into a Walstad-style equilibrium over a few minutes of watching.

The aesthetic is **pixel art with sim depth underneath**. Internal sim runs continuous; render pass quantizes to chunky pixels + a 48-color palette. Animation emerges from physics, not keyframes.

## Download (macOS)

Grab the latest `Vivarium-mac.zip` from the [Releases page](https://github.com/mhsenkow/SimFish/releases). Unzip, then run `Vivarium.app`.

First launch: macOS Gatekeeper will probably refuse to open an unsigned app. Right-click `Vivarium.app` → **Open** → **Open** in the dialog. macOS only nags you the first time.

## What's in the tank

- **89 plants** in four zones (background blades, midground rosettes, foreground carpet, moss clumps on driftwood) — each grows voxel-by-voxel over real time, fed by the substrate nutrient field
- **11 fish** in two species: glassdarts (red mid-water schoolers, mild herbivory) and mudsifters (brown bottom-dwellers, stronger herbivory)
- **8 shrimp** in two color morphs (cherry-red and amber). They walk on the substrate, climb plants to nibble tips, and snap at the occasional baby fish or snail
- **6 snails** on the glass walls. They crawl with a visible foot-pulse gait, seek out detritus, breed by laying egg sacs that hatch into babies

Each creature is an **agent with a genome and a behavior tree**, ticking at 10 Hz with smooth render-rate motion. The food web is fully wired:

```
Plants ← substrate nutrients ← (waste settling + aquasoil reservoir leak + plant decay)
Shrimp ← detritus, plant tips, rare baby-snail/fry predation
Snails ← detritus (produce smaller pellets that settle)
Fish ← detritus, tall plants (≥12 biomass), rare baby-shrimp predation
Substrate nutrients ← waste deposits + reservoir trickle
```

## Watch for

- Plants visibly growing taller every few seconds
- Fish school: cohesion + alignment + separation with view cones + position prediction. The school anticipates turns instead of reacting to them
- **Courtship**: an adult pair finds each other, swims alongside for 6 seconds, then lays a clutch of visible eggs on a nearby plant. ~30 sim seconds later, the eggs wobble and hatch into fry
- Shrimp climbing plants, nibbling the tip, dropping back down
- Snails leaving small dark pellets behind as they crawl
- Aging fish visibly fading in color before they die
- Population dynamics cycling — fry born, some eaten, survivors mature, breed, repeat

## Controls

| Input | Action |
|---|---|
| Drag any mouse button | Orbit camera around the tank |
| Scroll wheel | Zoom in / out |
| W / S | Pan target forward / back |
| A / D | Pan target left / right |
| Q / E | Pan target down / up |
| F | Reset view |
| Space | Toggle slow auto-orbit (cinematic) |

The header at the top shows live ecosystem stats: fish (adults / fry), shrimp, eggs incubating, plants + total biomass, waste particles in transit, substrate nutrient pool.

## Build it yourself

Requires [Godot 4.2+](https://godotengine.org/download).

```bash
git clone https://github.com/mhsenkow/SimFish.git
cd SimFish/shaders-godot/godot-project
godot --path . main.tscn
```

Or open `shaders-godot/godot-project/project.godot` in the Godot editor and press F5.

To export your own macOS build:

```bash
cd shaders-godot/godot-project
godot --path . --headless --export-debug "macOS" build/Vivarium.app
```

## Repository layout

```
SimFish/
├── shaders-godot/godot-project/    # the actual playable game
│   ├── main.tscn                   # root scene with SubViewport + palette display
│   ├── scripts/
│   │   ├── main.gd                 # orbit camera + ecosystem HUD
│   │   ├── world.gd                # builds substrate, hardscape, initial population
│   │   ├── sim_driver.gd           # fixed-tick coordinator (10 Hz)
│   │   ├── substrate_grid.gd       # nutrient field with diffusion + reservoir leak
│   │   ├── plant.gd                # L-system-ish growing voxel plant
│   │   ├── fish.gd                 # boids + courtship + lifecycle
│   │   ├── shrimp.gd               # walk + climb + forage + breed
│   │   ├── snail.gd                # glass-cling crawl with foot-pulse gait
│   │   ├── waste_particle.gd       # detritus with kind (fish/shrimp/snail)
│   │   ├── egg.gd                  # incubating egg
│   │   └── voxel_mat.gd            # ShaderMaterial factory
│   ├── shaders/
│   │   ├── voxel.gdshader          # faceted unshaded voxel material
│   │   └── palette_quantize.gdshader # palette LUT + Bayer dither
│   └── palettes/planted_48.png     # 48-color planted-biotope palette
├── shaders-godot/                  # supporting tools
│   ├── make_palette.py             # generates palette PNGs from hex lists
│   └── README.md
├── sim-rust/                       # standalone Rust crate: chemistry sim
│   ├── src/                        # falling-sand substrate, scalar fields,
│   ├── examples/cycle.rs           #   two-population nitrogen cycle
│   └── README.md
├── data-schemas/                   # JSON Schemas for species data
├── style-guide/STYLE_GUIDE.md      # palettes, pixel rules, dithering
└── render_preview.py               # static pixel-art preview generator
```

## Architecture notes

**Rendering pipeline.** The 3D voxel scene lives in a `SubViewport` at 512×288. A full-window `TextureRect` displays the SubViewport's render through `palette_quantize.gdshader`, which snaps every output pixel to one of 48 palette colors using Bayer 4×4 dither between the two nearest hits. Voxel materials use `voxel.gdshader` — unshaded, face-based brightness (top 100%, sides 82% / 68%, bottom 50%) so cubes self-light without a directional light fighting the palette. Light energy in the environment is at 0.3 for soft fill only.

**Simulation pipeline.** Behavior decisions run at 10 Hz in `SimDriver._tick()`. Motion runs at render rate in each creature's `_process()` — fish and shrimp use a **heading + speed** model with bounded turn rate and linear acceleration so they curve through arcs instead of teleporting. Banking on yaw rate gives them a visible roll into turns.

**Schooling.** Boids with three upgrades: view cone (~115° in front), position prediction (cohesion targets `neighbor.position + neighbor.velocity * 0.4`), and speed matching toward school average.

**Food web.** Waste particles are produced by every eat event and decay. Each "eat waste" event produces a smaller leftover at the eater's position (40% of original value) — energy cascades down through the trophic levels until it falls below 0.04 and is lost. The substrate grid has a slow reservoir leak representing aquasoil bedrock; without it the nutrient pool would bleed out as waste gets snapped up before settling.

**Lifecycles.** All fish + shrimp move through fry → juvenile → adult → senescent → dead. Senescent fish visibly fade their voxel colors. Adult pairs court (fish 6s, shrimp 4s) before spawning. Fish lay visible egg clusters that incubate ~30s before hatching. Shrimp spawn fry directly.

## Roadmap

- [ ] Spectator mode that auto-orbits and zooms on whoever's currently doing something interesting (breeding, hunting, dying)
- [ ] Algae blooms when nutrients spike and plant biomass is low
- [ ] Multiple biotopes (palettes for blackwater + hard-alkaline already exist in `shaders-godot/make_palette.py`)
- [ ] Save/load tank state with a deterministic seed for shareable "tank genealogies"
- [ ] Generative ambient audio keyed to population entropy
- [ ] More fish species, more plant L-systems

## License

MIT for code. Palettes + style guide CC0.
