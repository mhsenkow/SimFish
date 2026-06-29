# The Active-Inference Core (META #1)

*Drafted 2026-06-29. The last headline sentience-architecture call: collapse the
~15 hand-tuned drives in `global_workspace.gd` into **one** principled objective —
expected free energy — so curiosity, foraging, caution, and rest stop being three-
plus separate formulas and become terms of a single quantity the fish minimises.
Gated end-to-end by the sentience eval harness (13/13 today), behind a flag,
strangler-fig, so the riskiest change in the codebase can't silently break the mind.*

> **Why this is the capstone.** Every other Tier-1 item *added* a faculty. This one
> *unifies* them. In Friston's free-energy account, a mind doesn't have separate
> "drives" — it has one imperative (minimise expected surprise) whose pragmatic and
> epistemic components *look like* hunger, fear, and curiosity from the outside. Our
> `collect_bids` already approximates that with ~15 hand-tuned salience formulas.
> #1-full makes the approximation exact: compute the expected free energy directly,
> and the hand-tuned constants fall out as special cases.

---

## 1. The thesis, precisely

**Expected free energy** of attending to / acting on an option:

```
G(option) = − pragmatic_value(option)  − epistemic_value(option)
```

and the mind **minimises G** — i.e. salience ∝ `pragmatic + epistemic`, precision-
weighted. The two terms (Friston's standard decomposition):

- **Pragmatic value** (extrinsic): how much the option is expected to move the fish
  toward its **preferred outcomes** — its homeostatic priors: *fed, safe, calm,
  socially satisfied.* This is `food` (reduces hunger-error), `threat`/`safety`
  (reduces harm-error), `mate` (reduces social-error), `rest` (reduces sleep-debt).
- **Epistemic value** (intrinsic): how much the option is expected to **reduce the
  fish's uncertainty** — information gain, driven by the world model's variance /
  prediction error. This is `novelty`, `free_energy`, `uncertainty`.

**The unification claim (and the safety property):** today's hand-tuned formulas are
*approximations of this*. `food = hunger + 0.1` ≈ the pragmatic value of eating when
hungry. `novelty = curiosity·0.75` ≈ epistemic value. `free_energy = EFE·0.7` is
*already* epistemic value, bolted on beside the rest. #1-full computes the whole
thing from one function — so a correctly-built core **reproduces current behaviour
as a special case**, then improves on it (one coherent trade-off instead of fifteen
constants that can disagree).

The win, concretely: *a hungry-and-curious fish near an uncertain region* currently
fires `food`, `novelty`, and `uncertainty` as three independent bids that the
workspace must reconcile by accident. Under one EFE objective, "go investigate the
patch where food *might* be" is a *single* high-value option (pragmatic + epistemic
aligned) — which is exactly the "it's actually thinking" behaviour.

---

## 2. Current state (what we're replacing)

- [`global_workspace.gd` `collect_bids()`](../shaders-godot/godot-project/scripts/global_workspace.gd):
  ~15 `_bid(label, hand_tuned_salience, coalition)` calls. Each salience is its own
  formula (`spooked+0.45`, `hunger+0.1`, `curiosity·0.75`, …).
- `MindWorldModel.expected_free_energy_explore(f)` — **already** computes
  info-gain + goal; consumed only by the `free_energy` bid (1A). The epistemic half
  exists in isolation.
- `MindWorldModel.precision_scale(f, label)` — already used in
  `_apply_precision_and_mods` to sharpen/dampen salience by model confidence. This
  is the precision-weighting active inference needs — already in place.
- `guardian_generative.gd` — runs **policy-level** EFE (Markov blanket, counter-
  factual policies, free-energy-over-policies) for the Guardian *only*. This is the
  reference for the richer form (#19 promotes it to all fish; #1-full is the
  per-drive form that makes it the *kernel's* objective).
- The **eval harness** (`mind_eval.gd`, 13/13) — the gate. Especially **S1**
  (surprise minimisation), **S2** (information seeking), **A1** (ignition), **D1**
  (committed choice), **L1/L2** (learning). #1-full must hold or raise these.

So three of the four pieces already exist (epistemic value, precision weighting, the
verifier). #1-full is mostly *composition + migration*, not invention — which is
what makes it tractable despite the XL rating.

---

## 3. Target architecture

A new pure module, `mind_active_inference.gd` (Phase 0, scaffolded now):

```
preferred_error(f)        -> {hunger, safety, social, rest}   # divergence from priors
pragmatic_value(f, label) -> float   # need-error this drive would reduce
epistemic_value(f, label) -> float   # info gain (world-model variance / curiosity)
efe_salience(f, label)    -> float   # pragmatic·precision + W·epistemic  (drop-in salience)
```

`efe_salience` returns a salience in the **same range as the current bids**, so it is
a *drop-in* for the hand-tuned numbers. `collect_bids` keeps emitting the same labels
+ coalitions; only the *salience source* changes (flagged). Action selection
(`run_competition` → `broadcast` → DDM) is unchanged in Phase 1 — it just receives
principled saliences. The DDM/commitment graduates to EFE in Phase 2.

**Nothing about GWT, the felt-self spine, memory, or the eval changes.** This is a
swap of *how salience is computed*, not the architecture around it.

---

## 4. The phased migration (each phase flag-gated + eval-verified)

Flag: `TankConfig.consciousness_active_inference` (default **false**). The eval
harness is run before/after every phase; a phase ships only if the functional
sentience index **holds at 13/13** (and ideally improves S1/S2/D1).

- **Phase 0 — the objective, scaffolded (DONE this commit).**
  `mind_active_inference.gd` + `smoke_active_inference_core.gd`. Pure functions,
  consumed by nothing. Smoke proves: pragmatic value tracks need (food↑ with hunger,
  threat↑ with spook), epistemic value tracks world-model variance, and
  `efe_salience` **reproduces the legacy drive** for food/threat within tolerance
  (the safety property). Eval unchanged (flag off) → 13/13.

- **Phase 1 — EFE drives the bid saliences (flagged, additive).** When the flag is
  on, `collect_bids` sources the saliences for the *homeostatic + epistemic* drives
  (food, threat, novelty, uncertainty, free_energy, mate, interoception, rest) from
  `efe_salience` instead of their hand-tuned formula. Keep labels/coalitions. **Gate:**
  eval index stays 13/13 with the flag ON; tune the EFE weights against the harness
  (this is the real work — the harness makes it a tuning loop, not a guess). Ship
  with flag still default-off for the fleet; enable for named/guardian first (#20
  tier T2+).

- **Phase 2 — EFE informs action selection.** The DDM (`tick_ddm`) and
  `foraging_commitment` take their drift/threshold from the EFE gradient (commit
  faster when one option's G is clearly lowest; deliberate when G is flat — which is
  exactly **M1** metacognition + **D1** committed-choice). **Gate:** D1 and M1 hold/
  improve; no oscillation regressions.

- **Phase 3 — collapse the duplication.** Once EFE-sourced saliences match-or-beat
  the hand-tuned ones on the eval, delete the legacy formulas; the `free_energy` and
  `uncertainty` bids merge into the unified epistemic term; flip the flag default to
  on. **Gate:** full eval 13/13 with the legacy code removed. This is the moment the
  three drives *become one* in the source, not just in behaviour.

**Rollback at any phase:** flip the flag off → instant return to the hand-tuned
kernel. The flag is the safety net; the eval is the tripwire.

---

## 5. Risk analysis

| Risk | Mitigation |
|---|---|
| Rebalanced saliences change emergent behaviour subtly | The eval harness (13 behavioural+integration invariants) is the tripwire; tune against it. Flag-gated + per-tier rollout. |
| EFE weights become a *new* set of hand-tuned constants | They're far fewer (one pragmatic + one epistemic weight + precision, already principled) and they're *fit against the eval*, not guessed. |
| Pragmatic/epistemic double-counts what a bid already encoded | Phase 0 smoke asserts `efe_salience` ≈ legacy for the main drives before anything consumes it. |
| Action-selection (Phase 2) destabilises the DDM | Phase 2 is separate + gated on D1/M1; Phase 1 leaves selection untouched. |
| The change is invisible to players (all internal) | Out of scope here — that's the separate "make it felt" pass; #1-full is the engine. |

---

## 6. Task list (Cursor builds Phases 1–3 against the eval)

Each task: implement, run `smoke_mind_eval.gd`, require **13/13 + honesty PASS**,
mark done with the measured index. Never ship a phase that drops the index.

**Phase 0 (DONE):**
1. ✅ `mind_active_inference.gd` — pragmatic/epistemic/efe_salience + preferred_error.
2. ✅ `smoke_active_inference_core.gd` — need-tracking + legacy-reproduction safety.

**Phase 1 — EFE as bid salience (flag-gated):**
3. Add `consciousness_active_inference: bool = false` to `tank_config.gd` (mirror
   `consciousness_workspace_enabled`).
4. In `collect_bids`, when the flag is on, source `food` salience from
   `MindActiveInference.efe_salience(f, "food")`; **run the eval**; tune weights until
   13/13. (Do one drive at a time — food first, it's the cleanest pragmatic case.)
5. Repeat #4 for `threat`, then `mate`, `interoception`, `rest` (pragmatic drives).
6. Repeat for `novelty`/`uncertainty`/`free_energy` → the single epistemic term;
   **assert S2 still passes** (info-seeking) and the three no longer double-count.
7. Per-tier rollout: enable the flag for `MindLOD` tier ≥ T2 fish only at first.

**Phase 2 — EFE in action selection:**
8. `tick_ddm` drift ∝ the EFE gap between the top two options; **gate on D1**.
9. Commitment threshold ∝ EFE flatness (flat G → deliberate → **M1**); **gate on M1**.

**Phase 3 — collapse:**
10. Delete the hand-tuned salience formulas the EFE path now covers; merge the
    `free_energy`/`uncertainty` bids; flip the flag default on; **full eval 13/13
    with legacy removed.**

**Acceptance for the whole epic:** flag-on fleet runs at **≥ 13/13** with S1, S2,
D1, M1 measurably *as good or better*, the legacy drive formulas deleted, and a
hungry-curious fish demonstrably treating "investigate the maybe-food patch" as one
high-value option (a new eval invariant **S3 — pragmatic+epistemic alignment** —
should be added in Phase 1 to lock this in).

---

## 7. Why this stays honest

EFE is a *functional* objective — surprise minimisation over a generative model. It
is not, and the harness's honesty gate (H) will not let it be described as, a claim
that the fish *feels* its drives unified. What we can say, truthfully, when this
lands: *the fish's behaviour is now governed by one principled objective the way our
best theory of biological agency says minds are* — and the number proves it.
