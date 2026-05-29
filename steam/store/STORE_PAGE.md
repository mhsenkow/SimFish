# Store page drafts for Steam (App ID 4796460)

## Short description (≤ 300 chars)

A generative pixel-art Walstad aquarium. Plants grow, fish school and breed, shrimp climb stems, snails crawl the glass. Watch a closed nutrient loop settle into equilibrium — chunky pixels, sim depth underneath.

## About the game

walstad loom is a living tank you watch more than you play. A 3D voxel aquascape runs through a palette-quantize shader so everything reads as pixel art, while plants, fish, shrimp, and snails interact in a Walstad-style food web underneath.

Stock a preset or build your own mix. Feed the tank, follow a creature, take photos, timelapse a bloom crash. The ecosystem self-balances over a few minutes — algae spikes when nutrients run hot, snails and shrimp graze it back, fry hide in the stems.

## Suggested tags

Simulation, Casual, Pixel Graphics, Relaxing, Nature, Singleplayer, Indie

## Launch executables

| OS | Binary |
|----|--------|
| Windows | `WalstadLoom.exe` |
| Linux | `WalstadLoom-linux.x86_64` |
| macOS | `WalstadLoom.app` |

## Generated assets

Run from repo root:

```bash
cd steam/store && .venv/bin/python generate_assets.py
open assets   # drag all folders onto Steamworks → Graphical Assets drop zone
```

Outputs under `steam/store/assets/`:

| Folder | Contents |
|--------|----------|
| `screenshots/` | 5× 1920×1080 gameplay shots |
| `capsules/` | Main, header, small, library hero/logo/header/capsule |
| `icons/` | Client icon + 256/512 |

## System requirements (draft)

**Minimum**
- OS: Windows 10 / macOS 11 / Ubuntu 22.04
- Processor: Dual-core 2 GHz
- Memory: 4 GB RAM
- Graphics: OpenGL 3.3 / Metal / Vulkan-capable GPU
- Storage: 200 MB

**Recommended**
- Memory: 8 GB RAM
- Display: 1920×1080
