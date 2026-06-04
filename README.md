# walstad loom



<img width="2560" height="1440" alt="Screenshot 2026-05-20 at 10 57 35 AM" src="https://github.com/user-attachments/assets/b0d223df-5dc5-4149-a863-265be0290852" />
<img width="2560" height="1440" alt="Screenshot 2026-05-20 at 4 06 02 PM" src="https://github.com/user-attachments/assets/8b8a9c07-869c-4462-98bf-074c32911a56" />
<img width="2560" height="1440" alt="Screenshot 2026-05-20 at 3 44 23 PM" src="https://github.com/user-attachments/assets/1838bd1a-bddf-4924-be2e-1de1b5e5b71a" />





A generative pixel-art aquarium running as a 3D voxel scene through a palette-quantize + dither shader pipeline. Plants grow, fish school and breed, shrimp climb plants and snap at fry, snails crawl the glass and eat detritus, **clams filter waste from the column, corals respire + bleach + glow at night, dwarf gourami defend their territory and incubate fry in their throats**. The whole thing self-balances into a Walstad-style equilibrium over a few minutes of watching.

The aesthetic is **pixel art with sim depth underneath**. Internal sim runs continuous; render pass quantizes to chunky pixels + a 48-color palette with region-aware dither, hue-bank palette lock, optional outline + CRT overlay, and time-of-day tinting. Animation emerges from physics, not keyframes.

## Download

All builds live on the [Releases page](https://github.com/mhsenkow/SimFish/releases). Pick your platform:

### macOS — [`walstad-loom-mac.zip`](https://github.com/mhsenkow/SimFish/releases/latest/download/walstad-loom-mac.zip) (universal, Intel + Apple Silicon)

Unzip, then double-click `WalstadLoom.app`. The app is **ad-hoc signed** but not Apple-notarized, so Gatekeeper will warn you on first launch:

1. **Right-click `WalstadLoom.app` → Open → Open** in the dialog.
2. If macOS instead says *"WalstadLoom.app is damaged and can't be opened"* (Chrome downloads sometimes trigger this), open Terminal and run:
   ```bash
   xattr -dr com.apple.quarantine ~/Downloads/WalstadLoom.app
   ```
   then double-click again.

macOS only nags once.

### Windows — [`walstad-loom-windows.zip`](https://github.com/mhsenkow/SimFish/releases/latest/download/walstad-loom-windows.zip) (x86_64)

Unzip, then double-click `WalstadLoom.exe`. SmartScreen will warn that the publisher is unknown — click **More info** → **Run anyway**.

### Linux — [`walstad-loom-linux.tar.gz`](https://github.com/mhsenkow/SimFish/releases/latest/download/walstad-loom-linux.tar.gz) (x86_64)

```bash
tar -xzf walstad-loom-linux.tar.gz
./WalstadLoom-linux.x86_64
```

Tested on Ubuntu / Debian-based distros. The binary already has the exec bit set.

### Steam

Coming to Steam as **walstad loom** (App ID `4796460`). See [`steam/README.md`](steam/README.md) for depot setup, GodotSteam install, and upload steps.

## Pick your tank

Tapping **+ New tank** opens the scenario picker — eight curated themes
that each combine a distinct tank shape + footprint + substrate + aeration
+ lighting + stocking. Every scenario produces a visibly different
silhouette of glass on the desk, not just a different fish mix.

| Scenario | Shape · W×D×H | Highlights |
|---|---|---|
| **Walstad Jungle** | box · 8×4×7 | Default planted community: cardinal tetras, harlequins, cory, mouthbrooding gourami pair, cleaner shrimp |
| **Iwagumi Stone Garden** | wide box · 11×3×5 | Sand + bright sun + a single tetra school over almost-empty negative space |
| **Blackwater Biotope** | column · 6×3×9 | Tall narrow tank, driftwood-stained warm water, killifish + cory + guppy |
| **Coral Reef Cube** | **cube** · 6.5²×7 | Saltwater · ocean sand · corals, anemones, clams, mixed reef morphs |
| **Cichlid Hex Showtank** | **hex** · 7²×8 | Hexagonal show tank, angelfish + gourami pairs defend wedges of floor |
| **Polyp Biosphere** | **sphere** · 5²×6 | NO fish — cherry shrimp colony, freshwater hydra polyps, filter-feeding clams |
| **Nature Aquarium Column** | **cylinder** · 5.5²×8 | Tall planted column, every behavior on display at once |
| **Apex Predator Den** | box · 6×4×6 | Cozy dim tank, betta + dwarf puffer contest opposite corners |

The picker writes a config dict into `TankConfig` per scenario, so each tank
opens with the right `tank_shape`, `tank_half_w/d`, `tank_height`,
`substrate_type`, `aeration_type`, `light_warmth/energy/fixture`, and
`environment_preset` already set. Adding a new scenario is one Dictionary
entry in [`scenario_picker.gd`](shaders-godot/godot-project/scripts/scenario_picker.gd).

The **Guided setup** button still works the same way — empty tank, walk
through stocking it manually.

## What's in the tank

The tank is configured via a **stocking preset**. The scenario picker sets
one for you, but you can also pick directly from the Settings panel; it
sets the starting species mix, the phenotype spread, and (for the
reef preset) the substrate type. The included presets:

| Preset | What it produces |
|---|---|
| Classic community *(default)* | Cardinal tetras + harlequins + cory + dwarf gourami pair + cleaner shrimp |
| Community (balanced) | Tetras + guppies + bottom group + 1 betta apex |
| Tetra school (peaceful) | Pure schoolers + dense shrimp colony, no apex predator |
| Iwagumi (single school) | One tetra school over sand — pure negative space (used by scenario picker) |
| Apex predator + prey | Lots of prey + a betta and a puffer competing for snacks |
| Cichlid pairs | Angelfish + gourami pairs + cory (used by Cichlid Hex scenario) |
| Polyp lab (no fish) | Shrimp colony only — freshwater hydra polyps auto-spawn (sphere scenario) |
| Blackwater biotope | Killifish + cory + guppy + shrimp (used by Blackwater scenario) |
| Diverse founding stock | Every species, wide phenotype spread, evolution diverges fast |
| Single species (clones) | All glassdarts start identical; drift emerges slowly |
| Exotic mix (full reef) | All six new species, no glassdart/betta, angelfish centerpiece |
| Showcase tank | Every behavior on display: angelfish + gourami pairs + killifish + guppy + cory |
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

- Plants visibly growing taller every few seconds, with a soft warm rim at grazing angles (subsurface scattering, day-tracked so it fades at night)
- Fish schooling with cohesion + alignment + separation, view cones, and position prediction — the school anticipates turns instead of reacting to them
- **Per-species courtship** — the male's dance pattern matches the species' swim pattern: school/shoal → side-by-side parallel S-curve, dart → jerky lateral snap, hover → vertical figure-8 (angelfish), cruise → wide circling, meander → slow lateral display
- **Mouthbrooding** — after spawn, mouthbrooder females (angelfish, dwarf gourami) carry the brood visibly in their throats. A small bulge under the head grows for ~40 sim seconds before fry tumble out around her face
- **Territorial defense** — flagged species (betta, puffer, angelfish, dwarf gourami) defend a `home_radius` around their home point. Alpha rank = size_potential × age; bigger/older fish chases conspecific intruders away and nudges their stress up. Subordinates yield instead of fighting back
- **Cleaning symbiosis** — when a fish's stress rises, it swims to the nearest cleaner shrimp/wrasse, parks, tilts a flank toward the cleaner, and gets a stress drain while the shrimp gets a meal
- **Night sleep posture** — diurnal fish at deep night develop a small per-fish roll, hold near plant cover, and twitch awake every 8–25 seconds
- **Pre-stress gill flush** — rare head-pulse cough when stress is climbing (0.30–0.55) AND water quality is borderline (low O₂ or high waste). Visible early warning before actual panic
- **Pecking order at feed events** — ⌘+LMB on the water surface drops pellets. Bold fish (high dart_chance, low stress) see food from farther away and converge first; timid fish hang back at the rear of the queue
- **Spatial memory of feed taps** — the tank remembers your last 5 drop spots for 30 seconds. Hungry fish drift toward those locations even before pellets land, the way real fish learn habitual feeding stations
- **Stress contagion** — one startled fish broadcasts a flee impulse to nearby conspecifics. Tight-schoolers copy the heading exactly; loose-groupers flee directly away from the panic source. Panic rings ripple outward through the school
- **Coral polyp respiration** — each coral form pulses its growing-edge voxels (dome, branching, plate, feathery, brain, staghorn-fern). Anemone tentacles ribbon-wave with the current. Tips glow softly at night (bioluminescence)
- **Coral bleaching** — corals pale toward bone white when warmth crosses 0.78 or O₂ drops below 0.35. Polyp pulse collapses; recovery is slow when conditions return to safe
- **Clams** — bivalve shells open and close on a cycle. While open, a small siphon extends and pulls nearby waste particles in, depositing nutrients back to the substrate
- **Epiphytes** — moss and java fern attach to driftwood + rocks (not the substrate). They draw water-column micros instead of substrate nutrients
- **Trim-response branching** — when a fish grazes a stem voxel off a plant, the plant sprouts a side shoot from the cut node on the next growth tick (real apical-dominance loss → lateral bud activation)
- **Distinct algae types** — surface scum at the air-water film, hair algae anchored to hardscape, green-spot dots on the glass walls, and the classic biofilm cluster all coexist instead of one global tint
- **Caustic-wave coupling** — caustic light spots on the substrate dance with the surface ripple field; disturbances visibly modulate the spotlight pattern
- **God-ray fish shadows** — when god rays are on, the 8 fish nearest the camera cast soft shafts of shadow through the beams
- **Glass meniscus** — a bright thin ring just above the waterline with a faint dark hairline below (faux refraction trick) curves the visible glass→water interface
- **Substrate sand ripples** — a low-frequency streak pattern on the top sand voxels walks forward over real-time sim-hours, suggesting current shaping the bed
- **Driftwood substrate-joint algae** — green moss/algae concentrates at the wood-meets-gravel band; cream biofilm dominates higher up
- **Day / night activity shift** — diurnal fish slow to a drift at night while bottom-dwellers (cory, mudsifter) pick up the pace, like real nocturnal loaches. Shrimp peak around dawn / dusk
- **Time-of-day palette** — same 48-color palette but the screen tint blends dawn → midday → dusk → midnight anchors continuously, breathing color across the day cycle
- **Death sequence** — old or starved fish tilt onto a flank, drift to the substrate, wither, and decompose into a mulm particle that fertilizes the substrate
- Population dynamics cycling — fry born, some eaten, survivors mature, breed, repeat

## Recent additions

Major systems shipped in the v0.1.66+ window:

### Fauna intelligence (#16–24)
- **Mouthbrooding** — `is_mouthbrooder` genome flag; throat bulge mesh + delayed fry release event in `sim_driver.gd._release_brooded_fry`
- **Per-species courtship** — five distinct dance variants gated by `swim_pattern` inside `_tick_behavior`'s breed branch
- **Hierarchical territory defense** — alpha-vs-subordinate chase tier with stress-contagion to drive intruders out of `home_radius`
- **Cleaning symbiosis (fish side)** — stressed fish steer to nearest cleaner shrimp, slow, tilt, and gain stress drain
- **Sleep posture variation** — per-fish night-roll + occasional twitch (8–25s) for diurnal species
- **Pre-stress gill flush** — head-pivot pulse cough when water quality is borderline before stress hits the hide threshold
- **Pecking order at feed events** — `_boldness()` (dart_chance + low stress) scales food awareness range and pursuit cost
- **Spatial memory of feed taps** — sim-side 5-entry × 30 s ring buffer; fish drift toward remembered spots even before pellets land
- **Stress contagion** — extended startle propagation to all swim patterns; loose-groupers flee away, tight-schoolers copy heading

### Plant / coral precision (#25–32)
- **Coral polyp pulse** — per-tip voxel respiration on every coral form (dome, branching, plate, feathery, brain, staghorn-fern, anemone, sponge, hydra-fresh)
- **Anemone tentacle ribbon motion** — distinct two-axis undulation field, tips lifted past the base axis
- **Epiphytic plants** — `is_epiphyte` flag skips substrate consumption, uses water-column micros, anchors moss/java-fern to driftwood + rocks
- **Trim-response branching** — grazed nodes sprout side shoots on the next growth tick
- **Coral bleaching** — temperature/O₂ stress → pale-out + growth penalty; recovery is slow when conditions return
- **Distinct algae types** — `Algae.AlgaeKind` enum: cluster / surface-scum / hair / GSA-glass with niche-aware placement
- **Wider flower color variety** — 14 palettes weighted by light/warmth/saltwater/substrate + a 6% rare-bloom branch
- **Freshwater clams** — new `Clam` class: sessile bivalve filter feeders with shell hinge animation + siphon

### Retro 8-bit aesthetic (#1–7)
- Per-region dither strength (heavy on water/fog, light on saturated fauna)
- Time-of-day palette tint blending dawn → day → dusk → night anchors
- Integer-only nearest-neighbor upscale lock (optional)
- Toggleable 1-px edge outline shader
- 16-color hue-bank palette restriction
- Optional CRT scanline + vignette overlay
- Sprite-rounding camera (snaps eye position to render-pixel grid)

### Beauty & water fidelity (#8–15)
- Caustic intensity coupling to surface wave height
- Night bioluminescence (coral tips + `is_bioluminescent` fish lure)
- God-ray occlusion by 8 nearest fish silhouettes
- Plant subsurface scattering rim (day-gated)
- Filter intake bubble column (distinct from substrate gas escape)
- Glass meniscus ring with dark hairline below
- Substrate sand-ripple sculpting evolving over sim-hours
- Driftwood substrate-joint algae concentration

### Performance & responsiveness (#41–45)
- Plant spatial grid (cuts O(plants × fish) per-tick scans by ~5–10×)
- Distance LOD for fauna voxels via Godot's `visibility_range_end`
- Self-tuning render tier — rolling FPS average auto-steps resolution
- Frame-budget sparkline in the Render panel
- Lazy substrate cell ticks (only diffuses dirty cells near active plants/waste)

### Tank scenarios (the picker shown above)
- Eight curated themes with distinct shapes (box, cube, hex, cylinder, sphere) + footprints + lighting + stocking
- Three new tank presets: `polyp_lab` (fishless), `iwagumi_school`, `cichlid_pairs`, `blackwater_biotope`

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

For desktop Steam integration, install GodotSteam once:

```bash
./steam/install_godotsteam.sh
```

```bash
git clone https://github.com/mhsenkow/SimFish.git
cd SimFish/shaders-godot/godot-project
godot --path . main.tscn
```

Or open `shaders-godot/godot-project/project.godot` in the Godot editor and press F5.

To export your own macOS build:

```bash
cd shaders-godot/godot-project
godot --path . --headless --export-debug "macOS" ../../build/WalstadLoom.app
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
│   │   ├── fish.gd                 # boids + courtship + lifecycle + death anim + mouthbrooding + territory
│   │   ├── shrimp.gd               # walk + climb + forage + breed + cleaner station
│   │   ├── snail.gd                # glass-cling crawl with foot-pulse gait
│   │   ├── clam.gd                 # sessile bivalve filter feeder
│   │   ├── algae.gd                # algae cluster / surface scum / hair / GSA glass
│   │   ├── waste_particle.gd       # detritus with kind (fish/shrimp/snail)
│   │   ├── egg.gd / snail_egg.gd   # incubating eggs
│   │   ├── evolution_pressure.gd   # genome-nudge helpers tied to tank env
│   │   ├── fish_store.gd           # procedurally-generated buy-new-fish shop
│   │   ├── scenario_picker.gd      # new-tank modal — 8 themed scenarios
│   │   ├── settings_panel.gd       # tank/light/substrate/preset/aeration UI
│   │   ├── render_panel.gd         # resolution/dither/fog/FOV/MSAA + frame-budget sparkline
│   │   ├── panel_theme.gd          # shared chrome + typography + form helpers
│   │   ├── mobile_hud.gd           # bottom-corner controls on touch devices
│   │   ├── ambient_audio.gd        # day/night ambient layer
│   │   ├── aquarium_visuals.gd     # caustics, biofilm aging, mineral spots, slime
│   │   ├── camera_orbit.gd
│   │   ├── voxel_mat.gd            # ShaderMaterial factory + cache update helpers
│   │   ├── leaf_shapes.gd          # plant stress-color ramp
│   │   ├── save_helpers.gd
│   │   └── capture.gd              # F12 photo + timelapse
│   ├── shaders/
│   │   ├── voxel.gdshader          # faceted unshaded voxel material + bioluminescence
│   │   ├── voxel_mm.gdshader / voxel_translucent.gdshader
│   │   ├── foliage.gdshader / foliage_mm.gdshader  # plant sway + SSS rim
│   │   ├── water.gdshader          # surface waves + caustics + meniscus
│   │   ├── glass.gdshader          # tank glass + meniscus ring + biofilm
│   │   ├── caustics.gdshader / substrate_caustic.gdshader  # wave-coupled caustics + sand ripples
│   │   ├── surface_ripple.gdshader / bubble.gdshader
│   │   ├── god_ray.gdshader        # volumetric beams + fish-silhouette occluders
│   │   ├── circle_mask.gdshader    # PiP portal mask
│   │   └── palette_quantize.gdshader # palette LUT + Bayer + region dither + outline + CRT
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
├── steam/                          # Steamworks depots, upload scripts, store copy
│   ├── README.md
│   ├── install_godotsteam.sh
│   └── store/STORE_PAGE.md
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
- [x] Mouthbrooding + per-species courtship + territorial defense + cleaning symbiosis (fauna intelligence batch)
- [x] Coral polyp pulse, anemone ribbon motion, bleaching, distinct algae types, epiphytes, trim-response, flower variety, clams (plant/coral precision batch)
- [x] Region-aware dither, time-of-day palette, integer upscale, outline shader, palette bank lock, CRT overlay, pixel-snap camera (8-bit aesthetic batch)
- [x] Wave-coupled caustics, night bioluminescence, god-ray fish occlusion, plant SSS, filter bubble stream, glass meniscus ring, sand ripple sculpting, driftwood algae (beauty + water fidelity batch)
- [x] Plant spatial grid, voxel LOD, self-tuning render tier, frame-budget sparkline, lazy substrate ticks (performance batch)
- [x] New-tank scenario picker — 8 themed combos with distinct shapes + footprints + stocking

Up next: see [`docs/GOALS.md`](docs/GOALS.md) for the full 50-item checklist
organized by category (motion, breeding, food web, plants, environment, etc.).
Remaining work clusters around the background-object mode (transparent
window, click-through, multi-monitor), Walstad-cycle UI banner, more
generative variety (markings, pattern types, asymmetry), and per-tier
mobile polish.

## License

MIT for code. Palettes + style guide CC0.
