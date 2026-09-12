# Chemistry oracle — shared invariants

Two independent implementations model this tank's water chemistry:

| | `shaders-godot/.../water_chemistry.gd` | `sim-rust/` |
|---|---|---|
| Role | **the product** — what players see | reference oracle, not shipped |
| Spatial model | well-mixed, single compartment | 2D grid, per-cell fields |
| Bacteria | one `bacteria_colony` scalar | per-cell nitrosomonas + nitrobacter |
| Units | game-tuned, normalised | lumped mg/L |

They are **not numerically comparable** and must never be asserted against each
other value-by-value. What they *can* be held to jointly is **curve shape** —
the qualitative behaviour any credible aquarium chemistry must show.

That shared set is below. Each invariant has an ID, and both test suites
reference the ID in their assertion messages, so a failure on either side
points at the same claim.

- Rust: `sim-rust/src/chemistry.rs` `mod tests`
- GDScript: `scripts/smoke_chemistry_oracle.gd`

Why bother: writing the first pass of these found that the Rust crate had
silently stopped reproducing its own documented nitrogen cycle (see
[ADR 003](adr/003-sim-rust-as-oracle.md)). An invariant nobody checks is a
comment.

---

## Nitrogen cycle

| ID | Invariant |
|---|---|
| **N1** | Ammonia introduced into a cycling tank is consumed over time. |
| **N2** | Nitrite **rises then falls** — a peak strictly inside the window, not a monotonic ramp. This is the classic nitrite spike, and it exists because nitrobacter lags nitrosomonas. |
| **N3** | Nitrate accumulates while nitrification runs. |
| **N4** | The nitrite peak occurs **after** the ammonia peak. Ordering is the load-bearing part: it is what makes the curve a *cycle* rather than three independent series. |

## Oxygen

| ID | Invariant |
|---|---|
| **O1** | Oxygen trends toward saturation when the surface is agitated, and aeration raises the rate. |
| **O2** | Nitrification consumes oxygen — a tank under ammonia load has lower O₂ than the same tank without it. |

## pH

| ID | Invariant |
|---|---|
| **P1** | pH falls as CO₂ rises, at fixed KH. |
| **P2** | KH buffers: for the same CO₂ change, **low KH swings more** than high KH. |

## Denitrification

| ID | Invariant |
|---|---|
| **D1** | Anaerobic zones remove nitrate; a tank with anaerobic substrate accumulates less nitrate than one without. |

---

## Adding an invariant

Add the row here first, then the assertion on both sides citing the ID. An
invariant asserted on only one side is not an oracle — it is just a test.
