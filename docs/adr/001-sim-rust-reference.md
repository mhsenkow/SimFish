# ADR 001: Keep `sim-rust/` as reference-only

**Status:** Accepted · **Date:** 2026-06-28

## Context

`sim-rust/` (~1.3k LOC) models Walstad nitrogen cycling in Rust with a falling-sand
substrate and diffusion chemistry. The shipping game runs chemistry in GDScript
(`water_chemistry.gd`, `substrate_grid.gd`, `sim_driver.gd`). The crate is neither wired
into Godot nor validated in CI.

## Decision

**Keep as reference — do not archive, do not wire into the game in the near term.**

- README and crate header state **reference prototype, not wired in**.
- Use `cargo run --example cycle` locally when calibrating chemistry intuition.
- Do **not** treat Rust constants as authoritative for the live sim without reconciliation.
- `vivarium_serve` binary remains undocumented/orphaned until explicitly archived or wired
  (see SYSTEMIC #46).

## Consequences

- No CI `cargo test` job until someone commits to reviving the crate (SYSTEMIC #45).
- Future native backend work starts with a new ADR + binding plan, not silent drift.
- Contributors should not block game features on Rust parity.

## Alternatives considered

1. **Archive to `archived/sim-rust/`** — rejected; the demo is still useful for cycle intuition.
2. **Revive + CI** — deferred; cost exceeds benefit while GDScript sim is the product.
