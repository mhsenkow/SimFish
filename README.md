# Vivarium
<img width="2560" height="1440" alt="image" src="https://github.com/user-attachments/assets/82432dbc-8338-4bc1-9313-0b54c24aff27" />

<img width="2560" height="1440" alt="Screenshot 2026-05-20 at 10 57 35 AM" src="https://github.com/user-attachments/assets/b0d223df-5dc5-4149-a863-265be0290852" />
<img width="2560" height="1440" alt="Screenshot 2026-05-20 at 4 06 02 PM" src="https://github.com/user-attachments/assets/8b8a9c07-869c-4462-98bf-074c32911a56" />
<img width="2560" height="1440" alt="Screenshot 2026-05-20 at 3 44 23 PM" src="https://github.com/user-attachments/assets/1838bd1a-bddf-4924-be2e-1de1b5e5b71a" />





A generative pixel-art aquarium running as a 3D voxel scene through a palette-quantize + dither shader pipeline. Plants grow, fish school and breed, shrimp climb plants and snap at fry, snails crawl the glass and eat detritus. The whole thing self-balances into a Walstad-style equilibrium over a few minutes of watching.

The aesthetic is **pixel art with sim depth underneath**. Internal sim runs continuous; render pass quantizes to chunky pixels + a 48-color palette. Animation emerges from physics, not keyframes.

## Download

All builds live on the [Releases page](https://github.com/mhsenkow/SimFish/releases). Pick your platform:

### macOS — [`Vivarium-mac.zip`](https://github.com/mhsenkow/SimFish/releases/latest/download/Vivarium-mac.zip) (universal, Intel + Apple Silicon)

Unzip, then double-click `Vivarium.app`. The app is **ad-hoc signed** but not Apple-notarized, so Gatekeeper will warn you on first launch:

1. **Right-click `Vivarium.app` → Open → Open** in the dialog.
2. If macOS instead says *"Vivarium.app is damaged and can't be opened"* (Chrome downloads sometimes trigger this), open Terminal and run:
   ```bash
   xattr -dr com.apple.quarantine ~/Downloads/Vivarium.app
   ```
   then double-click again.

macOS only nags once.

### Windows — [`Vivarium-windows.zip`](https://github.com/mhsenkow/SimFish/releases/latest/download/Vivarium-windows.zip) (x86_64)

Unzip, then double-click `Vivarium.exe`. SmartScreen will warn that the publisher is unknown — click **More info** → **Run anyway**.

### Linux — [`Vivarium-linux.tar.gz`](https://github.com/mhsenkow/SimFish/releases/latest/download/Vivarium-linux.tar.gz) (x86_64)

```bash
tar -xzf Vivarium-linux.tar.gz
./Vivarium-linux.x86_64
```

Tested on Ubuntu / Debian-based distros. The binary already has the exec bit set.

## What's in the tank

The tank is configured via a **stocking preset**. Pick one from the Settings
panel; it sets the starting species mix, the phenotype spread, and (for the
reef preset) the substrate type. The included presets:

| Preset | What it produces |
|---|---|
| Community (balanced) | Tetras + guppies + bottom group + 1 betta apex — the default |
| Tetra school (peaceful) | Pure schoolers + dense shrimp colony, no apex predator |
| Apex predator + prey | Lots of prey + a betta and a puffer competing for snacks |
| Diverse founding stock | Every species, wide phenotype spread, evolution diverges fast |
| Single species (clones) | All glassdarts start identical; drift emerges slowly |
| Exotic mix (full reef) | All six new species, no glassdart/betta, angelfish centerpiece |
| Showcase tank | Tall angelfish over a community of guppies + cory + killifish |
| Reef (saltwater) | Coral reef + mixed tropical school, each fish rolls a unique morph |
| Custom | Hand-set counts (UI exposes glassdart/mudsifter/shrimp counts) |

Species are defined in `tank_config.gd`'s `SPECIES_LIBRARY` — currently
glassdart tetra, mudsifter (kuhli-like), betta, killifish, guppy, dwarf
pufferfish, zebra danio, corydoras, angelfish, and a mixed reef school
that rolls one of 9 tropical morphs per individual. Adding a new species
is one entry in the library; presets reference species by key and pick
them up automatically.

Plus the cast that's not configurable per preset:
- **Plants** in four zones (background blades, midground rosettes, foreground carpet, moss clumps on driftwood) — voxel-by-voxel growth fed by the substrate nutrient field. Saltwater tanks replace plants with corals.
- **Shrimp** walking the substrate, climbing plants to nibble tips, snapping at the occasional baby fish or snail. Two color morphs (cherry-red and amber).
- **Snails** on the glass walls. Foot-pulse crawl, seek detritus, lay egg sacs that hatch into babies. Population-capped so the tank doesn't carpet.

Each creature is an **agent with a genome and a behavior tree**, ticking at 10 Hz with smooth render-rate motion. The food web is fully wired:

```
Plants ← substrate nutrients ← (waste settling + aquasoil reservoir leak + plant decay)
Shrimp ← detritus, plant tips, rare baby-snail/fry predation
Snails ← detritus (produce smaller pellets that settle)
Fish ← detritus, tall plants (≥12 biomass), rare baby-shrimp predation, specialist diets (snail-hunter, algae-grazer)
Substrate nutrients ← waste deposits + reservoir trickle
```

## Watch for

- Plants visibly growing taller every few seconds
- Fish schooling with cohesion + alignment + separation, view cones, and position prediction — the school anticipates turns instead of reacting to them
- **Courtship**: an adult pair finds each other, swims alongside for ~6 seconds (with color pulse + fin flare), then lays a clutch of visible eggs on a nearby plant. The eggs wobble and hatch into fry ~30 sim seconds later
- Shrimp climbing plants, nibbling the tip, dropping back down
- Snails leaving small dark pellets behind as they crawl
- **Day / night activity shift** — diurnal fish slow to a drift at night while bottom-dwellers (cory, mudsifter) pick up the pace, like real nocturnal loaches. Shrimp peak around dawn / dusk
- **Death sequence** — old or starved fish tilt onto a flank, drift to the substrate, wither, and decompose into a mulm particle that fertilizes the substrate
- Population dynamics cycling — fry born, some eaten, survivors mature, breed, repeat

## Controls

### Camera

| Input | Action |
|---|---|
| Drag any mouse button | Orbit camera around the tank |
| Scroll wheel | Zoom in / out |
| W / S | Pan target forward / back |
| A / D | Pan target left / right |
| Q / E | Pan target down / up |
| F | Reset view |
| Space | Toggle slow auto-orbit (cinematic) |
| Click on a creature | Open the PiP portal that follows it |
| C | Toggle PiP portal |
| ESC | Clear follow target |

### Simulation

| Input | Action |
|---|---|
| P | Pause / resume |
| 1 / 2 / 3 | Time-scale 1× / 4× / 16× |
| F12 | Photo (saved to user data dir) |
| T | Start / stop timelapse |
| B | Aquascape mode (place dirt / stone / driftwood, dig, drag logs) |
| O | Toggle Settings panel |
| R | Toggle Render panel |

### Top HUD

The top bar is responsive — desktop / iPad landscape get the full chip strip
with sublabels (state, fish, shrimp, snails, flora, water, morphs, alerts).
Medium widths drop the sublabels; phone-narrow widths fold the right-side
action cluster down to a bottom-right thumb zone. The HUD dims after a few
seconds of inactivity so it doesn't compete with the scene.

The Settings panel (`O`) lets you change tank dimensions, shape, lighting,
substrate, aeration fixture, and the stocking preset. Clicking **Apply**
saves the config and reloads the tank — if the substrate or preset changes
in a way the saved state can't survive (saltwater → freshwater, or a
different fish mix), the save is invalidated so the new stocking spawns
fresh.

### Multiple tanks

The main menu (back from any tank via the **≡ Menu** button) shows your
saved tanks as cards with thumbnails. Each tank has its own slot under
`user://tanks/<n>/` containing the per-tank config, save state, and a
last-rendered screenshot. Duplicate a tank to fork a configuration; delete
to free a slot.

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

### CI releases (macOS + Windows + Linux)

Pushing a version tag builds all three platforms on GitHub Actions and uploads the zips to [Releases](https://github.com/mhsenkow/SimFish/releases):

```bash
git tag v0.1.30
git push origin v0.1.30
```

Workflow: `.github/workflows/release.yml` (Godot 4.6.3, export presets in `export_presets.cfg`). You can also run it manually from **Actions → Release builds → Run workflow** (artifacts only; no Release unless you pushed a tag).

## Repository layout

```
SimFish/
├── shaders-godot/godot-project/    # the actual playable game
│   ├── main.tscn                   # root scene with SubViewport + palette display + TopHUD
│   ├── tank_menu.tscn              # tank-picker shown on launch
│   ├── scripts/
│   │   ├── main.gd                 # orbit camera + responsive top HUD + chip renderer
│   │   ├── world.gd                # builds substrate, hardscape, initial population
│   │   ├── sim_driver.gd           # fixed-tick coordinator (10 Hz) + save/load
│   │   ├── tank_config.gd          # autoload: per-tank config + species library + presets
│   │   ├── tank_saves.gd           # autoload: slot directories + compatibility checks
│   │   ├── tank_menu.gd            # menu scene: tank cards, new/duplicate/delete
│   │   ├── substrate_grid.gd       # nutrient field with diffusion + reservoir leak
│   │   ├── plant.gd                # L-system-ish growing voxel plant
│   │   ├── branch_plant.gd         # ... + branchy variants
│   │   ├── spiral_plant.gd         # ... + spiral, nautilus, fractal moss
│   │   ├── nautilus_plant.gd
│   │   ├── fractal_moss.gd
│   │   ├── cattail_plant.gd        # emergent cattail
│   │   ├── lily_pad.gd             # floating lily + flower + runners
│   │   ├── coral.gd                # saltwater plant equivalent
│   │   ├── fish.gd                 # boids + courtship + lifecycle + death anim
│   │   ├── shrimp.gd               # walk + climb + forage + breed + death anim
│   │   ├── snail.gd                # glass-cling crawl with foot-pulse gait
│   │   ├── waste_particle.gd       # detritus with kind (fish/shrimp/snail)
│   │   ├── egg.gd / snail_egg.gd   # incubating eggs
│   │   ├── fish_store.gd           # procedurally-generated buy-new-fish shop
│   │   ├── settings_panel.gd       # tank/light/substrate/preset/aeration UI
│   │   ├── render_panel.gd         # resolution/dither/fog/FOV/MSAA UI
│   │   ├── panel_theme.gd          # shared chrome + typography + form helpers
│   │   ├── mobile_hud.gd           # bottom-corner controls on touch devices
│   │   ├── ambient_audio.gd        # day/night ambient layer
│   │   ├── camera_orbit.gd
│   │   ├── voxel_mat.gd            # ShaderMaterial factory
│   │   ├── leaf_shapes.gd          # plant stress-color ramp
│   │   ├── save_helpers.gd
│   │   └── capture.gd              # F12 photo + timelapse
│   ├── shaders/
│   │   ├── voxel.gdshader          # faceted unshaded voxel material
│   │   ├── circle_mask.gdshader    # PiP portal mask
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
├── docs/
│   ├── GOALS.md                    # 50-item backlog + bonus ideas
│   ├── index.html / style.css      # github-pages landing
│   └── img/                        # screenshots
├── style-guide/STYLE_GUIDE.md      # palettes, pixel rules, dithering
└── render_preview.py               # static pixel-art preview generator
```

## Architecture notes

**Rendering pipeline.** The 3D voxel scene lives in a `SubViewport` at 512×288. A full-window `TextureRect` displays the SubViewport's render through `palette_quantize.gdshader`, which snaps every output pixel to one of 48 palette colors using Bayer 4×4 dither between the two nearest hits. Voxel materials use `voxel.gdshader` — unshaded, face-based brightness (top 100%, sides 82% / 68%, bottom 50%) so cubes self-light without a directional light fighting the palette. Light energy in the environment is at 0.3 for soft fill only.

**Simulation pipeline.** Behavior decisions run at 10 Hz in `SimDriver._tick()`. Motion runs at render rate in each creature's `_process()` — fish and shrimp use a **heading + speed** model with bounded turn rate and linear acceleration so they curve through arcs instead of teleporting. Banking on yaw rate gives them a visible roll into turns.

**Schooling.** Boids with three upgrades: view cone (~115° in front), position prediction (cohesion targets `neighbor.position + neighbor.velocity * 0.4`), and speed matching toward school average.

**Food web.** Waste particles are produced by every eat event and decay. Each "eat waste" event produces a smaller leftover at the eater's position (40% of original value) — energy cascades down through the trophic levels until it falls below 0.04 and is lost. The substrate grid has a slow reservoir leak representing aquasoil bedrock; without it the nutrient pool would bleed out as waste gets snapped up before settling.

**Lifecycles.** All fish + shrimp move through fry → juvenile → adult → senescent → dead. Senescent fish visibly fade their voxel colors. Adult pairs court (fish 6s, shrimp 4s) before spawning. Fish lay visible egg clusters that incubate ~30s before hatching. Shrimp spawn fry directly. Natural deaths (old age, starvation) play a 3.5s sink + tilt + wither animation before queue_free; predator kills are still instant so eaten-vs-died-of-old-age reads distinctly.

**HUD.** The top bar is a single `TopHUD` Control with three child panels: left cluster (Menu / Render toggle), center StatsBar (BBCode-tinted chip strip), right cluster (Portal / Aquascape / Buy / Settings toggles). A responsive layout function (`_apply_hud_layout`) detects viewport width + touch and switches between wide / medium / compact presentations — compact moves the right cluster to the bottom-right thumb zone. The HUD auto-dims to ~45% modulate after 6 seconds of no input.

**Panels.** `panel_theme.gd` is a static helper class that provides shared chrome, typography, form rows, and primary/secondary buttons for the Settings, Render, and Fish Store panels. One palette token change cascades across every panel — no per-panel restyle.

**Motion stability.** Fish run their physics in sub-steps of ≤0.05s so high time-scale (4×, 16×) doesn't overshoot the steering target and produce the "spinning in place" bug. Shrimp use a simpler 0.04s dt cap. Both have a heading-finite NaN guard and skip `look_at` when speed is below 0.04 (to stop micro-orientation snaps when nearly stationary).

**Persistence.** Each tank slot has its own directory under `user://tanks/<slot>/` with `config.cfg` (tank parameters), `state.json` (full sim snapshot — substrate, plants, fish, shrimp, snails, eggs, waste), `meta.cfg` (name, runtime, timestamps), and `thumbnail.png`. The save header includes `substrate_type` and `tank_preset` so `TankSaves.is_active_save_compatible()` can reject loads that would put saltwater fish in a freshwater tank or load the old preset's stocking after the player switched presets.

## Roadmap

Done since the original roadmap:

- [x] Save/load tank state — per-slot state.json with substrate + preset compatibility checks
- [x] Multi-tank menu — duplicate, delete, switch between tanks
- [x] More fish species — 10 species in the library + a mixed-morph reef school
- [x] Multiple biotopes — the Reef preset switches the world to saltwater + corals
- [x] Mobile support — touch input, bottom-right action cluster, idle-dim HUD
- [x] Day / night behavior shifts — diurnal vs nocturnal activity multipliers
- [x] Death sequence — sink + tilt + wither + mulm drop, instead of instant pop

Up next: see [`docs/GOALS.md`](docs/GOALS.md) for a checklist of 50 ideas
organized by category (motion, breeding, food web, plants, environment).
Open it to pick the next session of work.

## License

MIT for code. Palettes + style guide CC0.
