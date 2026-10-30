# Motion review protocol

*Drafted 2026-10-30 for [CREATURE_MOTION_700.md](CREATURE_MOTION_700.md) #117
(a blind real-or-game review) and #116 (a principle line on every PR).*

Metrics catch regressions, but only people can say whether a creature looks
alive. This page defines two habits. The first is a blind review, run at
milestones, that compares game clips with real footage and tracks the score
over time. The second is a one-line motion note on every pull request that
changes motion.

## 1. The blind real-or-game review

### When

- At every phase gate in the backlog's plan (Phase 0 → 1, 1 → 2, and so on).
- Before a release that changes creature motion.
- Not more often than every two weeks. Raters who have seen recent clips stop
  being blind.

### The clip set

A fixed list of behaviour pairs, one real clip and one game clip each. Keep the
list the same across milestones so scores compare. Add new pairs as behaviours
ship, and report them separately until they have two milestones of history.

| Pair | Family | Behaviour | Real footage (see [MOTION_REFERENCE.md](MOTION_REFERENCE.md)) |
|---|---|---|---|
| F1 | Fish | Tetra or rasbora cruising in a shoal | Own tank |
| F2 | Fish | Angelfish hovering | Own tank or hobby footage |
| F3 | Fish | Danio burst-and-glide | Own tank |
| F4 | Fish | Startle or escape | Lab high-speed footage, slowed to real time, or own tank |
| F5 | Fish | Guppy sigmoid display | Hobby footage |
| F6 | Fish | Otocinclus or pleco grazing on glass | Own tank |
| F7 | Fish | Corydoras sifting, or the air dash | Own tank |
| S1 | Shrimp | Cherry shrimp picking | Own tank |
| S2 | Shrimp | Shrimp walking, then a tail flip | Own tank |
| G1 | Snails | Snail crawling on the front glass | Own tank |
| G2 | Snails | Snail clamping, then re-emerging | Own tank |
| W1 | Worms | Tubifex patch, then a withdrawal | Hobby footage |
| M1 | Microfauna | Daphnia swarm | Hobby or microscope footage |

Fill the gaps (crabs, sessile animals, eggs) as those behaviours become
reviewable.

### Clip specification

- **Length.** 10 s per clip, cut from one continuous take with no edits
  (#117). `dev/swimming_capture.tscn` records 240 frames at 30 fps, which is
  8 s. Until clip capture (#98) can record 10 s, use 8 s for **both** clips in
  a pair.
- **Frame rate.** 30 fps for both clips, the frame rate mobile players see.
  Real footage is shown at real speed.
- **Framing.** Side-on through the front glass, the camera tilted down about
  10° (#692), and the creature the same height in pixels in both clips:
  roughly its on-screen size at the default camera. Same crop, same aspect
  ratio, no zoom or pan during the clip. For a follow shot, follow in both.
- **No audio, no UI**, no captions or timestamps.
- **Two presentations.**
  - **Track A (motion only), the scored one.** Both clips reduced to a
    silhouette: the animal flat dark on a flat light background, at the
    game's pixel size. Point-light and silhouette displays are enough for
    people to judge biological motion (Johansson 1973), and they remove the
    rendering style that would otherwise give the game away. The game side
    uses the silhouette mode (#176); until it exists, threshold the captured
    frames. The real side is masked by hand or by thresholding.
  - **Track B (as shipped).** The real clip next to the unmodified game clip.
    Raters can tell which is which, so it is rated, not guessed.
- **Isolation.** Capture game clips only through `scripts/dev_run.sh`. The
  capture scenes build a real World and otherwise write to a real save slot
  (see [../AGENTS.md](../AGENTS.md)).
- **Storage.** Put clips in `output/motion_review/<milestone>/` (git-ignored),
  with a `clips.csv` manifest: pair id, side (real or game), source, commit,
  scenario, seed, species, capture command, crop. Commit only the manifest
  and the results row, never third-party video. Use real footage we shot, or
  footage we have permission to use.

### Raters

- **At least five** per review.
- **Blind to the work.** Nobody who has worked on, reviewed or watched motion
  work in the last milestone. Someone who rated last time may rate again.
- **A mix:** at least two people who keep or have kept aquarium fish, and at
  least two who don't.
- Raters are not told how many pairs there are, which family is being tested,
  or what changed.

### Scoring

For each pair:

1. **Track A, forced choice.** Show the two silhouettes side by side in random
   left-right order, looping. Ask: "Which one is the real animal?" Record the
   answer and whether the rater was sure.
2. **Track A, rating.** Separately, and in a shuffled order that mixes real
   and game, show each silhouette alone. Ask: "How alive does this look?"
   on a 1–5 scale.
3. **Track B, rating.** Show the as-shipped pair, labelled. Ask: "How alive
   does the game animal look next to the real one?" on a 1–5 scale, and "What
   gives the game one away?" (free text).

Then compute, per family and overall:

- **Identification rate:** the share of forced choices that picked the real
  clip. 50% means people can't tell them apart, which is the goal. 100% means
  the game is obviously fake.
- **Alive gap:** the mean Track A rating of real clips minus that of game
  clips. 0 is the goal.
- **Shipped rating:** the mean Track B rating.
- **Giveaways:** tag each free-text answer with the principle it names (SQ,
  AN, … AP). Count the tags. The most common tags point at the next pass and
  feed the scorecard.

**Noise.** With five raters and twelve pairs (60 forced choices), the 95%
interval on an identification rate near 50% is about ±13 points. Treat a
change between milestones as real only if it is larger than that, or if it
holds over two reviews. Per-family rates rest on few trials; report them, but
don't act on one review alone.

### Tracking

Add one row per review to the results log below. Update the scorecard
([MOTION_SCORECARD.md](MOTION_SCORECARD.md)) from it: a family needs a review
result to be graded A on any principle.

| Date | Commit | Milestone | Raters | Pairs | ID rate overall | Fish | Shrimp | Snails | Worms | Micro | Alive gap | Shipped rating | Top giveaways |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| — | — | Phase 0 baseline (not yet run) | — | — | — | — | — | — | — | — | — | — | — |

## 2. The motion line on every PR (#116)

Every pull request or commit that changes how a creature moves carries one
line in its description:

```
Motion: <principle tags> · <metric: name, before → after> · <clip: path or attachment>
```

For example:

```
Motion: FT SI · tail amplitude decay after thrust stops 0.00 s → 0.34 s (the #108 smoke) · output/motion_lab/guppy_stop_before_after.gif
```

- **Principle tags** are the backlog's (SQ, AN, ST, PP, FT, SI, AR, SA, TI,
  EX, SD, AP). Use `—` for infrastructure.
- **Metric** names the measurement and gives the numbers before and after.
  If no metric exists yet, name the smoke that pins the behaviour, or write
  "none yet: #N" for the metric item that would.
- **Clip** points to a before/after clip (#99), from the motion lab when it
  exists, otherwise `dev/swimming_capture.tscn` or `inspect` stills, all
  through `scripts/dev_run.sh`. Clips live under `output/` (git-ignored); link
  or attach them, don't commit them.
- A PR that changes steering or paths on purpose says so in the same line and
  names the re-baselined golden test (#696).

The same rule is in [../CONTRIBUTING.md](../CONTRIBUTING.md#motion-changes).
