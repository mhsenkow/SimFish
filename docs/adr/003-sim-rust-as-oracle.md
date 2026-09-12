# ADR 003: `sim-rust/` earns its place as a chemistry oracle

**Status:** Accepted · **Date:** 2026-09-11 · **Supersedes:** [ADR 001](001-sim-rust-reference.md)

## Context

ADR 001 kept `sim-rust/` as "reference only, no CI `cargo test` until someone
commits to reviving it". Reviewing that decision as part of BROAD_DIRECTIONS #9
("decide the content-as-data fate"), the honest state was worse than parked:

- The crate had **zero `#[test]` functions**.
- CI ran `cargo test --no-run` — compiling a test harness that contained no
  tests — and `cargo run --example cycle >/dev/null`, discarding the output.
- So CI proved the crate **compiled and did not panic**, and asserted nothing
  about its behaviour. It was not reference material; it was decorative.

Writing the tests immediately surfaced three real defects, two of which meant
the crate **did not reproduce the nitrogen cycle its own module docs describe**:

1. **Nitrobacter could never establish.** Uptake used a nitrite
   half-saturation of `0.2` while growth used `0.5` — two different constants
   for one organism on one substrate. `Ks = 0.5` put the growth break-even at
   `0.5 * decay / (growth_max - decay) = 0.047 mg/L`, while the tank's own
   nitrite equilibrium settled at 0.038–0.046 mg/L. Permanently a hair below
   break-even, so the colony decayed from its seed and the documented nitrite
   spike never happened.
2. **Diffusion was massively under-integrated at realistic `dt`.** An explicit
   4-neighbour stencil is only stable for `alpha <= 0.25`, so a single step
   must clamp there — but the code clamped and stopped, silently discarding
   the rest of the timestep. At the `dt = 60 s` the `cycle` example itself
   uses, ammonia wanted `alpha = 10.8` and got `0.24`: **45× under-integrated**.
   The tank was diffusion-starved, so ammonia never reached the thin reactive
   layer at the substrate interface.
3. **A linear scan in the innermost loop.** `field_index` was
   `ALL.iter().position(..).unwrap()` — an 11-element scan on every
   get/set/add, roughly 8 scans per substrate cell per tick.

## Decision

**Keep the crate, and make it load-bearing as a behavioural oracle — not as
shipped code.**

- The GDScript chemistry stays the product. Nothing is wired into Godot, and
  ADR 001's warning still stands: Rust constants are not authoritative for the
  live sim without reconciliation.
- The crate now carries **10 tests** pinning the cycle it claims to model:
  nitrite spikes (rises *then* falls), ammonia is consumed, nitrate
  accumulates, nitrobacter establishes, nothing goes negative or non-finite,
  diffusion conserves mass, and the species discriminants match `ALL`.
- CI runs `cargo fmt --check`, `cargo clippy -- -D warnings`, and
  `cargo test --release`.

### Why not delete it

Deleting was the initial call under #9 and was reversed deliberately. The crate
is **10 tracked files / ~56 KB** (`target/` is gitignored — the 219 MB on disk
is local build output, not repo weight), and it is an *independent
implementation* of the nitrogen cycle the GDScript imitates. Two
implementations that must agree on emergent behaviour is a stronger position
than one, and it directly serves BROAD_DIRECTIONS #13 (determinism) and #20
(validation).

### What can and cannot be cross-validated

The two models are **not** numerically comparable and should never be asserted
against each other cell-by-cell:

| | GDScript (`water_chemistry.gd`) | Rust (`sim-rust`) |
|---|---|---|
| Spatial model | well-mixed, single compartment | 2D grid, per-cell fields |
| Bacteria | one `bacteria_colony` scalar | per-cell nitrosomonas + nitrobacter |
| Purpose | shipped game feel | physical reference |

What they *can* be held to jointly is **curve shape**: ammonia falls, nitrite
peaks after ammonia and then declines, nitrate accumulates monotonically.
That is the oracle worth having, and it is what the Rust tests now pin on
their side.

## Consequences

- The crate can no longer rot silently — a behavioural regression fails CI.
- A future gdext port (META_ENGINEERING #96) now starts from a tested model
  rather than an unverified one.
- Someone must keep the Rust toolchain in CI. That cost is accepted.
- ADR 001's "no CI `cargo test`" clause is **superseded**; the rest of ADR 001
  (not wired in, not authoritative) still holds.

## Alternatives considered

1. **Delete the crate** — rejected. Cheap to keep, and it is the only
   independent check on the chemistry model the game imitates.
2. **Leave it parked** — rejected. "Parked" meant untested, and untested meant
   it had silently stopped reproducing its own documented behaviour.
3. **Wire it into the game now** — deferred. That is META #96 and needs its own
   ADR and binding plan.
