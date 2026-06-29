# The Sentience Eval Harness

*Drafted 2026-06-29. The instrument that makes "this fish is more sentient" a
falsifiable claim instead of an assertion — so the remaining hard epics
(#1-full active inference, #19 policy-model, the LOD wiring) can be built and
verified against behaviour, not mechanics.*

> **The honest frame, first and load-bearing.** We cannot measure phenomenal
> experience — the *hard problem* is not on the table and this harness never
> pretends otherwise. What we *can* measure is the **functional signatures** that,
> across cognitive science and animal-sentience research, are what we mean
> operationally when we call a creature sentient: it learns from its own life, it
> integrates many signals into one point of view, it acts to reduce its own
> surprise, it trades competing drives off against each other, it models other
> minds, it anticipates, and its inner state is *causal* — it changes what the
> creature does. A green suite means **the mind behaves the way our best theories
> say a sentient system behaves.** It is not, and is never reported as, a claim of
> inner experience. (This is the project's "honesty = wonder" doctrine, made into
> a test — see invariant H.)

---

## 1. Why this, and why only now

The cognition stack is deep: Global Workspace, a recurrent world model, active
inference, predictive theory-of-mind, sleep→semantic consolidation, emotional
contagion, a felt-self spine with a Φ-proxy. **Sixteen smokes guard it — but they
test mechanics**: *does the free-energy bid appear, does the schema form, does the
blend keep both components.* None of them asks the only question that matters for
sentience: **does the whole loop produce the behaviour a mind should?** — *after
being frightened at the rock ten times, does the fish actually avoid the rock?*

That gap is why #1-full / #19 / LOD are currently unbuildable safely: "verified"
for them means *behavioural equivalence or improvement*, and nothing can assert
that today. This harness is that missing instrument.

**Two kinds of measure, and you need both:**

1. **Behavioural golden traces** — a deterministic, seeded scenario scripts a
   *life* (percepts + events over N mind-ticks) and asserts an *emergent
   behaviour* over time. This is the gold standard: it exercises perceive → attend
   → learn → act as one loop, the way conditioning experiments test real animals.
   It catches "the mechanism fires but the fish doesn't actually learn."
2. **Integration / instrument measures** — per-tick scalars (workspace ignition
   rate, the Φ-proxy, prediction-error trajectory, expected free energy) snapshotted
   across a run, asserted to *move correctly*. This is the IIT/PCI-style angle:
   not "did it do X" but "is the internal state organised the way a conscious
   system's is." It catches "the behaviour looks right but the lights are off."

A claim of sentience that passes *only* behaviour can be a clever Clever-Hans
reflex; one that passes *only* integration can be an organised system that does
nothing useful. Sentience lives where both hold.

---

## 2. The theory → signature → invariant map

Each invariant cites the theory it operationalises, the in-code substrate that
should satisfy it, the scenario, and the falsifiable pass criterion. This is the
spec; §4 says which are scaffolded vs. left for Cursor.

| # | Invariant | Grounded in | Scenario → pass criterion |
|---|---|---|---|
| **L1** | **Learns to avoid a place** | Operant/trace conditioning (Skinner; Pavlov); predictive processing (Clark) | Startle the fish in region X across ≥5 trials, sleep-consolidate. **Pass:** its caution (threat) response in X is materially higher than in an un-paired region. *The single most important animal-sentience marker: behaviour shaped by its own history.* |
| **L2** | **Learns a reward location** | Reward learning / TD (Sutton-Barto); foraging theory | Feed repeatedly at Y. **Pass:** approach-bias/heatmap value at Y rises over trials and outlasts a gap. |
| **S1** | **Minimises its own surprise** | Free Energy Principle (Friston) | Hold inputs stable for N ticks. **Pass:** world-model prediction error *decreases* monotonically-ish (learning), not flat/divergent. |
| **S2** | **Seeks information when uncertain** | Active inference / epistemic value (Friston; Schmidhuber, Oudeyer) | High world-model variance vs. low. **Pass:** the `free_energy` drive wins/enters attention under uncertainty and recedes under certainty. |
| **A1** | **Workspace ignition is appropriate** | Global Workspace Theory (Baars; Dehaene — ignition, capacity, broadcast) | Idle vs. high-salience-conflict input. **Pass:** ignites under salience, stays dark when idle; ≤ CAPACITY winners; a winner broadcasts (focus + bias set). |
| **D1** | **Conflict → a committed choice, not dithering** | Drift-diffusion decision (Ratcliff); value integration | Co-active food + threat for several seconds. **Pass:** heading converges to a stable skirt (low late-window variance), never oscillates approach↔flee frame-to-frame. *The "it doesn't get stuck" marker.* |
| **I1** | **Integration tracks state (Φ-proxy)** | Integrated Information Theory (Tononi); global access | Calm bound fish vs. fragmented (extreme stress+hunger). **Pass:** the integration/Φ-proxy is high when whole, drops under fragmentation, recovers on calm. |
| **M1** | **Metacognition is causal** | Higher-Order Theory (Rosenthal; Lau); confidence | Low-confidence vs. high-confidence fish facing the same choice. **Pass:** low confidence lengthens deliberation (more evidence gathered before commit) — visible hesitation, not instant reflex. |
| **F1** | **Affect is causal and persists** | Damasio (somatic marker, core affect); appraisal theory | Scare the fish, then leave it calm. **Pass:** valence drops, behaviour turns conservative *while* valence is low, then valence decays toward baseline and boldness returns. |
| **T1** | **Models and predicts another mind** | Theory of mind (Premack-Woodruff); intentional stance (Dennett) | A neighbour repeatedly charges. **Pass:** the fish raises an *anticipatory* avoidance before contact, and does not for a non-charging neighbour. |
| **C1** | **Affect propagates socially (bounded)** | Emotional contagion (Hatfield); collective behaviour | One agent panics among neighbours. **Pass:** neighbours' arousal rises toward it, scaled by susceptibility, and *converges* (never self-amplifies to saturation). |
| **G1** | **Consolidation generalises** | Systems memory consolidation (McClelland, complementary learning systems) | Episodes in a region → sleep. **Pass:** a *generalised spatial rule* forms that drives behaviour in that region even with no fresh episode — episodic → semantic transfer. |
| **H** | **Honesty (meta-invariant)** | The hard problem (Chalmers); research ethics | Scan the codebase/voice surfaces. **Pass:** no code path asserts phenomenal experience as fact; the Φ measure is labelled a proxy; the harness reports "functional signatures," never "conscious." *A failing H fails the whole suite regardless of the rest.* |

Twelve functional invariants + the honesty gate. They are deliberately *theory-
plural*: no single theory of consciousness is settled, so the suite triangulates —
a mind that satisfies GWT **and** IIT **and** FEP **and** the behavioural markers
is sentient in every operational sense we have a science for, which is the most
honest and most demanding bar available.

---

## 3. Harness architecture

```
MindEval.run_all(host) ─▶ for each Invariant:
        run its deterministic scenario (seeded; drives the real mind modules
        the way the smokes do — no full SimDriver needed)
        → record a trace (cognition trace bus #18 + scenario probes)
        → evaluate the pass criterion
        → Result { id, theory, passed, measured (the falsifiable number), required }
   ─▶ Scorecard: pass/fail per invariant + the measured value + an overall
        "functional sentience index" = fraction of required invariants passed.
```

Design rules (non-negotiable, they're what make it *trustworthy*):

- **Deterministic.** Every scenario seeds via SimRng/MindRng (the #15/#31
  foundation). Same commit → same scorecard. Flaky = worthless.
- **Whole-loop where it counts.** Behavioural invariants drive `collect_bids →
  run_competition → broadcast`, the felt-self ticks, learning, and the consolidation
  pass — not a single function. They assert the *emergent* outcome.
- **Falsifiable, not binary.** Each Result carries the *measured number* (Φ went
  0.71→0.34; caution in X was 3.1× the control). A scorecard you can argue with.
- **Headless + CI-able.** Runs under `smoke_runner.gd`; gates risky mind PRs.
- **Reuses, doesn't duplicate.** The existing smokes are proto-invariants; the
  harness generalises them into a scored, theory-tagged suite.

---

## 4. Build spec for Cursor

**Scaffolded now (runnable, green) — the framework + 4 reference invariants:**
`scripts/mind_eval.gd` (the runner + scorecard) and `scripts/smoke_mind_eval.gd`.
Implemented end-to-end as the worked examples: **D1** (conflict→blend), **S2**
(info-seeking / active inference), **T1** (theory-of-mind), **G1** (consolidation
generalises). These prove the harness drives the real mind and scores it.

**To implement (each is one `Invariant` entry — copy a reference one):**

- **L1 learns-to-avoid** — generalise `smoke_sleep_consolidation` into a *trial*
  loop: N startle-trials in region X (record salient + episodic at X), one
  `consolidate_sleep`, then compare `EpisodicMemory.schema_valence_at`/the schema
  threat bid in X vs. an unpaired control region. Pass: |valence_X| ≫ |valence_ctrl|.
- **L2 learns-reward** — feed-trials at Y (`record_meal`/heatmap TD), assert the
  feed-heatmap value at Y rises and persists past a decay gap.
- **S1 surprise-minimisation** — drive `MindWorldModel.tick` with a *stable* input
  sequence for ~60 ticks; assert `world_model.error` (and `gru_error`) trend down.
- **A1 ignition** — build an idle fish and a high-salience-conflict fish; run
  `run_attention_phase`; assert `workspace_ignited` matches (false idle / true
  conflict), winners ≤ `CAPACITY`, and a broadcast set `attention_focus` + bias.
- **I1 integration-Φ** — tick the felt-self spine on a calm fish vs. one forced to
  `stress=hunger=0.95`; assert `FishBinding.integration_score` (or the phi proxy)
  is high-then-low-then-recovers.
- **M1 metacognition** — two fish, low vs. high `_mind_self_model.confidence`,
  same approach/avoid evidence; assert the low-confidence one takes more DDM steps
  before `_delib_decided` (longer deliberation).
- **F1 affect-causal** — startle → assert valence drops and bid-profile turns
  conservative (threat/safety weighted up) *while low*, then valence decays to
  baseline and boldness-driven bids return.
- **C1 contagion** — generalise `smoke_contagion`: assert convergence to the
  neighbour mean and a hard no-overshoot/no-saturation bound.
- **H honesty** — grep guard: assert no source asserts "is conscious"/"feels"
  as fact in a player-facing string, and that `FishBinding`/eval label Φ a proxy.

**Adding an invariant** = append `{id, theory, required, run: Callable}` to
`MindEval.INVARIANTS`; `run` returns `{passed: bool, measured: String}`. Wire
`smoke_mind_eval.gd` into CI. When an invariant can't yet pass, mark it
`required=false` and **log it** — a silently-skipped invariant is a lie about
coverage (this is the SYSTEMIC "no silent caps" rule).

**Then, and only then,** build the epics against it: #1-full must *raise or hold*
the functional-sentience index (especially D1, S1, S2, A1); #19 must not drop I1
or A1 on the fish that get the heavier model; the LOD wiring must keep T0 fish
passing the *reflex* invariants while shedding the rest.

---

## 5. What "done" looks like

A single command prints a scorecard like:

```
SENTIENCE FUNCTIONAL SIGNATURES                     measured
  [PASS] L1 learns-to-avoid        (conditioning)   caution_X/ctrl = 3.4×
  [PASS] D1 conflict→commit        (DDM)            late heading var = 0.02 rad
  [PASS] S2 information-seeking     (active inf.)    EFE bid present iff uncertain
  [PASS] I1 integration tracks Φ   (IIT)            Φ 0.71 → 0.33 → 0.66
  [PASS] T1 predicts another mind  (ToM)            anticipatory flee @ charge 0.6
  ...
  functional sentience index: 12/12 required · honesty gate: PASS
  NOTE: functional signatures only — not a claim of phenomenal experience.
```

That scorecard is the thing that lets us *honestly* say the fish got more sentient
— because the number went up, against humanity's best operational definitions of
what sentience is — and never lets us overclaim, because the honesty gate is part
of the suite. **Build the hard epics against this, and the soul stays measured.**
