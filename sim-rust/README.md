# vivarium-sim

Core simulation for the walstad loom pixel-art aquarium project: substrate
falling-sand + chemistry diffusion + nitrogen cycle with two bacterial
populations (nitrosomonas, nitrobacter).

## Run the demo

```bash
cargo run --release --example cycle
```

Prints a 42-day fishless-cycle table to your terminal:

```
 day |     NH3     NO2     NO3 |    O2     pH |     Nso     Nbc
--------------------------------------------------------------------
   0 |   1.305   0.024   0.263 |  6.65   7.09 |   143.7   135.8
   ...
  21 |   0.490   0.038   1.068 |  6.75   7.26 |    15.8     7.9
    > added a fish (ammonia bump)
  22 |   0.797   0.040   1.159 |  6.57   7.26 |   143.7    24.2
   ...
```

Architecturally what you're watching:

- Day 0: tank dosed with 2 mg/L ammonia; bacteria start growing.
- Days 1-7: nitrosomonas saturate the substrate surface (Nso climbs to 143), nitrobacter follows behind (Nbc lags).
- Days 8-21: ammonia drifts down; nitrate accumulates; bacteria settle into a steady state.
- Day 21: a fish is added (ammonia bump). Nitrosomonas spike back up, then re-equilibrate.
- Bacteria re-saturate after a disturbance - this is the cycle's "memory."

## Modules

| File | Responsibility |
|---|---|
| `grid.rs` | Plain 2D grid, used by everything |
| `substrate.rs` | Cellular automaton for falling sand, substrate kinds, bacteria populations |
| `chemistry.rs` | Scalar fields per species; diffusion; surface gas exchange; nitrogen cycle reactions |
| `world.rs` | Composes everything, `tick(dt)`, deterministic from seed |

## Known calibration TODOs

- **Diffusion is rate-limited at large `dt`.** The explicit 4-neighbor stencil clamps `alpha` to 0.24 for stability. At the demo's `dt = 300 s`, that effectively caps the diffusion rate to roughly 0.0008/s regardless of the species constant. Real demos show a slow asymptotic ammonia drop instead of a sharp bell curve. Fixes worth picking from:
  - Substep diffusion adaptively (bounded N).
  - Switch to an implicit (Crank-Nicolson / red-black Gauss-Seidel) step.
  - Add water-flow advection from the bubbler so bulk water actively circulates past substrate — most realistic, and the right fix long-term.
- **Reactions only fire on substrate cells with a water-cell neighbor.** That's basically the top row of substrate. Real tanks host biofilm everywhere oxygen reaches. Add a "biofilm penetration" concept: oxygen diffusion gradient into the substrate, with reactions happening at all cells above some O2 threshold.
- **Rate constants are tuned for the demo, not for absolute accuracy.** They're high enough to make the cycle visible in a 42-day window. Once advection lands, dial them back.

## Wiring into Godot

Build with `crate-type = ["cdylib"]` and wrap with `gdext` (the Godot-Rust binding). Expose:

```rust
World::new(width, height, seed) -> *mut World
World::tick(world, dt)
World::write_density_to_image(world, *mut u8)
World::write_chemistry_to_image(world, *mut u8)   // RGBA: R=tannins G=NH3 B=cloudiness A=O2
World::write_substrate_to_image(world, *mut u8)
```

Godot sets up an `ImageTexture` per layer and `World::tick` writes into them each frame. Render shaders read those textures (see `../shaders-godot/`).
