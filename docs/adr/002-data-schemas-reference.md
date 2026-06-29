# ADR 002: Keep `data-schemas/` as non-normative reference

**Status:** Accepted · **Date:** 2026-06-28

## Context

`data-schemas/` defines JSON Schemas and example species/substrate/hardscape files for a
moddable content path. The game loads species from GDScript (`species_library.gd`,
`tank_config.gd` `SPECIES_LIBRARY`). `validate.py` exists but is not run in CI.

## Decision

**Keep as reference spec — not consumed by the game until explicitly activated.**

- README states **data-design reference — not yet consumed**.
- Example species names may not match the in-game roster.
- Do **not** treat schema fields as the live contract for game behavior.
- Activation (GDScript loader + CI validation) requires a follow-up ADR and GOALS entry.

## Consequences

- Mod authors should treat examples as illustrative, not drop-in game mods.
- Reconciliation with `species_library.gd` is backlog work (SYSTEMIC #54).
- Renaming the folder is optional; clarity comes from README + this ADR, not a move.

## Alternatives considered

1. **Wire loader now** — rejected; no mod pipeline or hot-reload path in the game yet.
2. **Delete** — rejected; schemas document intended structure for future modding.
