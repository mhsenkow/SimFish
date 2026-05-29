# walstad loom data schemas

Three JSON Schemas + example data files. Drop content into the example folders
to add species, substrates, and hardscape without recompiling the sim.

| Schema | Files describe... | Examples |
|---|---|---|
| `plant.schema.json` | A plant species: L-system rules, nutrient demands, growth params, reproduction mode | `riverblade.json`, `crownleaf.json`, `spirevine.json` |
| `fauna.schema.json` | A fish/inverte species: genome ranges, behavior, lifecycle | `glassdart.json`, `mudsifter.json`, `spiralsnail.json` |
| `substrate.schema.json` | A substrate or hardscape kind: chemistry traits, visual palette indices | `aquasoil.json`, `lava_rock.json`, `seiryu_stone.json` |

## Why JSON

- Hot-reloadable in dev: edit a value, restart the scene, see the effect.
- Modders can ship species packs without your build chain.
- Easy to migrate later to TOML / RON / a binary format - the structure is the contract.

## Validation

Run the included validator:

```bash
pip install jsonschema
python3 validate.py
```

It walks every `examples/*.json`, picks the right schema based on a `kind`
discriminator, and prints any violations.

## Field naming

`snake_case` everywhere. Numeric ranges are `[min, max]` arrays. Vectors of
floats use plain arrays. Anything sampled from a range is named `*_range`;
anything fixed is named without the suffix.
