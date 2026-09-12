//! Water chemistry: scalar fields with diffusion + reaction.
//!
//! Each tracked species is one f32 grid. Diffusion is implemented as a 4-neighbor
//! averaging step (explicit, stable for small dt and rate). Advection by water
//! flow is not in this crate yet - this is the chemistry layer in isolation.
//!
//! Nitrogen cycle:
//!   NH4 --(nitrosomonas, needs O2)--> NO2
//!   NO2 --(nitrobacter,  needs O2)--> NO3
//!   NO3 --(anaerobic denitrifiers)--> N2 (lost from system)
//!
//! pH is derived each frame from KH, CO2, and tannins (rough approximation).

use crate::grid::Grid;
use crate::substrate::SubstrateSim;

/// Discriminants are explicit and load-bearing: `index()` is `self as usize`,
/// so the variant order here MUST match `ALL`. `species_index_matches_all`
/// pins that.
#[derive(Copy, Clone, Debug, Eq, PartialEq, Hash)]
#[repr(usize)]
pub enum Species {
    Ammonia = 0,    // NH3 + NH4 lumped, in mg/L
    Nitrite = 1,    // NO2
    Nitrate = 2,    // NO3
    Oxygen = 3,     // O2 dissolved, mg/L
    Co2 = 4,        // CO2 dissolved, mg/L
    Tannins = 5,    // unitless 0..1
    Kh = 6,         // carbonate hardness, dKH
    Gh = 7,         // general hardness, dGH
    Iron = 8,       // Fe, mg/L
    Potassium = 9,  // K, mg/L
    Phosphate = 10, // PO4, mg/L
}

impl Species {
    pub const ALL: &'static [Species] = &[
        Species::Ammonia,
        Species::Nitrite,
        Species::Nitrate,
        Species::Oxygen,
        Species::Co2,
        Species::Tannins,
        Species::Kh,
        Species::Gh,
        Species::Iron,
        Species::Potassium,
        Species::Phosphate,
    ];

    /// Index into `ChemistryField`'s field vector. O(1).
    ///
    /// This used to be a linear `ALL.iter().position(..).unwrap()`, called on
    /// every get/set/add — i.e. ~8 scans of an 11-element slice per substrate
    /// cell per tick, inside `nitrogen_cycle_step`'s innermost loop.
    #[inline]
    pub const fn index(self) -> usize {
        self as usize
    }

    /// Diffusion rate (per second). Gases diffuse faster than dissolved solids.
    pub fn diffusion_rate(self) -> f32 {
        match self {
            Species::Oxygen | Species::Co2 => 0.25,
            Species::Ammonia => 0.18,
            Species::Nitrite | Species::Nitrate => 0.12,
            Species::Tannins => 0.10,
            Species::Iron | Species::Potassium | Species::Phosphate => 0.08,
            Species::Kh | Species::Gh => 0.06,
        }
    }
}

// ---- Nitrogen-cycle kinetics -------------------------------------------
//
// Monod (Michaelis-Menten) kinetics throughout. Units are the crate's lumped
// mg/L, not literature mg-N/L, so these are tuned for the model's own
// operating range rather than lifted from a paper.

/// O2 half-saturation for both aerobic nitrifiers.
const O2_HALF_SAT: f32 = 1.0;
/// Ammonia half-saturation for nitrosomonas.
const KS_NH4: f32 = 0.5;
/// Nitrite half-saturation for nitrobacter. MUST stay below the tank's
/// working nitrite concentration or the colony can never establish.
const KS_NO2: f32 = 0.05;
/// Nitrate half-saturation for anaerobic denitrifiers.
const KS_NO3: f32 = 1.0;

/// Maximum specific uptake rates (per unit population, per second).
const NSO_UPTAKE_MAX: f32 = 0.10;
const NBC_UPTAKE_MAX: f32 = 0.12;
const DENITRIFY_MAX: f32 = 0.015;

/// Maximum specific growth rates, and the shared starvation decay. Decay
/// must be below `GROWTH_MAX * monod(working_concentration)` for a colony to
/// establish at all — that ratio sets the break-even concentration.
const NSO_GROWTH_MAX: f32 = 0.0006;
const NBC_GROWTH_MAX: f32 = 0.00035;
const BACTERIA_DECAY: f32 = 0.00003;

/// O2 consumed per unit N oxidised.
const O2_PER_N: f32 = 1.5;

/// Cap fraction-consumed-per-tick for integrator stability.
const MAX_FRAC_PER_TICK: f32 = 0.2;

/// Nitrite concentration above which nitrobacter grows rather than decays.
/// Exposed so tests can assert the tank actually operates above it.
pub fn nitrobacter_break_even_no2() -> f32 {
    KS_NO2 * BACTERIA_DECAY / (NBC_GROWTH_MAX - BACTERIA_DECAY)
}

pub struct ChemistryField {
    pub width: usize,
    pub height: usize,
    fields: Vec<Grid<f32>>,
    /// Scratch buffer for diffusion to avoid per-tick allocation.
    scratch: Grid<f32>,
}

impl ChemistryField {
    pub fn new(width: usize, height: usize) -> Self {
        let fields = Species::ALL
            .iter()
            .map(|_| Grid::filled(width, height, 0.0_f32))
            .collect();
        Self {
            width,
            height,
            fields,
            scratch: Grid::filled(width, height, 0.0),
        }
    }

    #[inline]
    pub fn get(&self, s: Species, x: usize, y: usize) -> f32 {
        *self.fields[s.index()].get(x, y)
    }

    #[inline]
    pub fn set(&mut self, s: Species, x: usize, y: usize, v: f32) {
        *self.fields[s.index()].get_mut(x, y) = v.max(0.0);
    }

    #[inline]
    pub fn add(&mut self, s: Species, x: usize, y: usize, v: f32) {
        let cell = self.fields[s.index()].get_mut(x, y);
        *cell = (*cell + v).max(0.0);
    }

    /// Whole-tank average of a species, restricted to water cells.
    /// Substrate cells contain stale values; including them skews the test-kit reading.
    pub fn average(&self, s: Species, substrate: &SubstrateSim) -> f32 {
        let f = &self.fields[s.index()];
        let mut sum = 0.0;
        let mut count = 0usize;
        for y in 0..self.height {
            for x in 0..self.width {
                if substrate.grid.get(x, y).kind.is_empty() {
                    sum += *f.get(x, y);
                    count += 1;
                }
            }
        }
        if count == 0 {
            0.0
        } else {
            sum / count as f32
        }
    }

    /// Derived pH from KH, CO2, tannins. Rough approximation matching aquarist
    /// charts: pH ~ 7.0 + log10(KH/CO2) * 0.5 - tannins * 0.5.
    pub fn ph_at(&self, x: usize, y: usize) -> f32 {
        let kh = self.get(Species::Kh, x, y).max(0.1);
        let co2 = self.get(Species::Co2, x, y).max(0.1);
        let tannins = self.get(Species::Tannins, x, y);
        7.0 + (kh / co2).log10() * 0.5 - tannins * 0.5
    }

    /// Diffuse every species using an explicit 4-neighbor stencil.
    /// Only water cells (substrate kind = Empty) participate.
    ///
    /// SUB-STEPPING. An explicit 4-neighbour stencil is only stable for
    /// alpha <= 0.25, so a single step must clamp there. This used to clamp
    /// and stop, which silently threw the rest of the timestep away: at the
    /// dt = 60 s the `cycle` example runs, ammonia wanted alpha = 10.8 and
    /// got 0.24 — **45x under-integrated**. The tank was therefore
    /// diffusion-starved, ammonia never reached the thin reactive layer at
    /// the substrate interface, and the nitrogen cycle ran far slower than
    /// the model intends.
    ///
    /// Now the requested alpha is split across as many stable sub-steps as it
    /// needs. `MAX_SUBSTEPS` bounds the cost; past that the field is
    /// effectively well-mixed anyway and the remaining error is not
    /// observable at tank scale.
    pub fn diffuse(&mut self, dt: f32, substrate: &SubstrateSim) {
        const STABLE_ALPHA: f32 = 0.24;
        const MAX_SUBSTEPS: usize = 8;
        let w = self.width;
        let h = self.height;
        for (si, sp) in Species::ALL.iter().enumerate() {
            let rate = sp.diffusion_rate();
            let wanted = (rate * dt).max(0.0);
            if wanted <= 0.0 {
                continue;
            }
            let substeps = ((wanted / STABLE_ALPHA).ceil() as usize).clamp(1, MAX_SUBSTEPS);
            let alpha = (wanted / substeps as f32).min(STABLE_ALPHA);
            for _ in 0..substeps {
                self.scratch.cells.copy_from_slice(&self.fields[si].cells);
                for y in 0..h {
                    for x in 0..w {
                        if !substrate.grid.get(x, y).kind.is_empty() {
                            continue;
                        }
                        let c = *self.scratch.get(x, y);
                        let mut sum = 0.0;
                        let mut count = 0.0;
                        for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                            let nx = x as isize + dx;
                            let ny = y as isize + dy;
                            if self.scratch.try_get(nx, ny).is_some() {
                                let nx = nx as usize;
                                let ny = ny as usize;
                                if substrate.grid.get(nx, ny).kind.is_empty() {
                                    sum += *self.scratch.get(nx, ny);
                                    count += 1.0;
                                }
                            }
                        }
                        if count > 0.0 {
                            let avg = sum / count;
                            let new = c + alpha * (avg - c);
                            *self.fields[si].get_mut(x, y) = new.max(0.0);
                        }
                    }
                }
            }
        }
    }

    /// Surface gas exchange: at the water surface row, O2 trends toward
    /// saturation and CO2 outgasses. `surface_y` is the row index of the
    /// meniscus; `agitation` (0..1) scales the rate (bubbler raises it).
    pub fn surface_exchange(&mut self, surface_y: usize, agitation: f32, dt: f32) {
        let o2_sat = 8.5; // mg/L target at 25C, freshwater.
        let co2_air = 0.5;
        // First-order relaxation toward saturation; clamp the per-tick factor
        // so we never overshoot even at large dt.
        let k_per_sec = 0.0008 + agitation * 0.005;
        let factor = (1.0 - (-k_per_sec * dt).exp()).min(0.9);
        for x in 0..self.width {
            let o2 = self.get(Species::Oxygen, x, surface_y);
            let co2 = self.get(Species::Co2, x, surface_y);
            self.set(Species::Oxygen, x, surface_y, o2 + (o2_sat - o2) * factor);
            self.set(Species::Co2, x, surface_y, co2 + (co2_air - co2) * factor);
        }
    }
}

/// Run nitrogen-cycle bacterial reactions on every substrate cell, mutating
/// chemistry fields in the cells of water *adjacent* to substrate (that's where
/// the biofilm lives + draws from).
///
/// This is the load-bearing function for "tank cycling" — getting the cells
/// to consume ammonia and produce nitrate is the heart of the sim.
pub fn nitrogen_cycle_step(chem: &mut ChemistryField, substrate: &mut SubstrateSim, dt: f32) {
    let w = chem.width;
    let h = chem.height;
    // For each substrate cell, find a water cell to its north (typical biofilm
    // facing). We do reactions there, scaled by bacteria population.
    for y in 0..h {
        for x in 0..w {
            let kind = substrate.grid.get(x, y).kind;
            if kind.is_empty() {
                continue;
            }
            // Water cell to consume from = first empty neighbor we find.
            let mut wxy: Option<(usize, usize)> = None;
            for (dx, dy) in [(0, -1), (-1, 0), (1, 0), (0, 1)] {
                let nx = x as isize + dx;
                let ny = y as isize + dy;
                if nx < 0 || ny < 0 || nx as usize >= w || ny as usize >= h {
                    continue;
                }
                let nx = nx as usize;
                let ny = ny as usize;
                if substrate.grid.get(nx, ny).kind.is_empty() {
                    wxy = Some((nx, ny));
                    break;
                }
            }
            let Some((wx, wy)) = wxy else {
                continue;
            };

            let cap = kind.bacterial_capacity();
            let nitrosomonas = substrate.grid.get(x, y).nitrosomonas;
            let nitrobacter = substrate.grid.get(x, y).nitrobacter;
            let nso_pop = nitrosomonas * cap;
            let nbc_pop = nitrobacter * cap;

            // Available substrates for the reactions.
            let nh4 = chem.get(Species::Ammonia, wx, wy);
            let no2 = chem.get(Species::Nitrite, wx, wy);
            let no3 = chem.get(Species::Nitrate, wx, wy);
            let o2 = chem.get(Species::Oxygen, wx, wy);

            // Aerobic reactions need O2; their rate is gated by it via
            // Michaelis-Menten on a half-saturation constant.
            let o2_factor = o2 / (o2 + O2_HALF_SAT);

            // Monod saturation terms. ONE half-saturation constant per
            // organism/substrate pair, shared by uptake and growth.
            //
            // These used to disagree: nitrobacter took up nitrite with
            // Ks = 0.2 but grew on it with Ks = 0.5, which is not a
            // defensible pair of numbers for one organism on one substrate.
            // Worse, KS_NO2 = 0.5 put the growth break-even at
            //     0.5 * DECAY / (NBC_GROWTH_MAX - DECAY) = 0.047 mg/L,
            // while the tank's own nitrite equilibrium settles at
            // 0.038-0.046 mg/L — permanently a hair BELOW break-even. So
            // nitrobacter decayed from its seed and never established, and
            // the nitrite spike this model exists to reproduce never
            // happened (see the module docs and `cycle_produces_nitrite_spike`).
            //
            // Nitrobacter has a high affinity for nitrite in the literature;
            // a Ks an order of magnitude below the working concentration is
            // the wrong shape. KS_NO2 now sits below that equilibrium so the
            // colony can actually take hold.
            let nh4_monod = nh4 / (nh4 + KS_NH4);
            let no2_monod = no2 / (no2 + KS_NO2);

            let raw_nh4 = NSO_UPTAKE_MAX * nso_pop * o2_factor * nh4_monod * dt;
            let r_nh4 = raw_nh4.min(nh4 * MAX_FRAC_PER_TICK);
            let raw_no2 = NBC_UPTAKE_MAX * nbc_pop * o2_factor * no2_monod * dt;
            let r_no2 = raw_no2.min(no2 * MAX_FRAC_PER_TICK);

            let anaero = substrate.grid.get(x, y).anaerobic;
            let raw_no3 = DENITRIFY_MAX * nso_pop * anaero * no3 / (no3 + KS_NO3) * dt;
            let r_no3 = raw_no3.min(no3 * MAX_FRAC_PER_TICK);

            chem.add(Species::Ammonia, wx, wy, -r_nh4);
            chem.add(Species::Nitrite, wx, wy, r_nh4 - r_no2);
            chem.add(Species::Nitrate, wx, wy, r_no2 - r_no3);
            chem.add(Species::Oxygen, wx, wy, -(r_nh4 + r_no2) * O2_PER_N);

            // Bacterial growth: each population grows on its own food and
            // decays slowly when starved. Nitrobacter is slower to establish
            // because its food (NO2) only appears once nitrosomonas runs - that
            // lag is what creates the nitrite spike in the cycle.
            let nso_growth = nh4_monod * NSO_GROWTH_MAX * o2_factor - BACTERIA_DECAY;
            let nbc_growth = no2_monod * NBC_GROWTH_MAX * o2_factor - BACTERIA_DECAY;
            let cell = substrate.grid.get_mut(x, y);
            cell.nitrosomonas = (cell.nitrosomonas + nso_growth * dt).clamp(0.0, 1.0);
            cell.nitrobacter = (cell.nitrobacter + nbc_growth * dt).clamp(0.0, 1.0);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::substrate::SubstrateKind;
    use crate::world::World;

    /// `index()` is `self as usize`, so the enum's discriminants and the order
    /// of `ALL` must agree. Reorder one without the other and every chemistry
    /// read silently returns a different species' field.
    #[test]
    fn species_index_matches_all() {
        for (i, sp) in Species::ALL.iter().enumerate() {
            assert_eq!(sp.index(), i, "{sp:?} index disagrees with ALL order");
        }
        assert_eq!(Species::ALL.len(), Species::Phosphate.index() + 1);
    }

    /// The tank must operate ABOVE nitrobacter's break-even nitrite
    /// concentration, or the colony decays from its seed and never
    /// establishes. This is the exact bug KS_NO2 = 0.5 caused: break-even
    /// landed at 0.047 mg/L while the tank settled at 0.038-0.046.
    #[test]
    fn nitrobacter_break_even_is_below_working_nitrite() {
        let be = nitrobacter_break_even_no2();
        assert!(be > 0.0, "break-even must be positive, got {be}");
        assert!(
            be < 0.02,
            "break-even nitrite {be:.4} is too high — nitrobacter will not \
             establish at the concentrations this tank actually reaches"
        );
    }

    /// One daily reading. Named rather than a 4-tuple: the tuple form made
    /// the argmax helper's type complex enough that clippy rejected it, and
    /// `s.1` told the reader nothing.
    #[derive(Copy, Clone, Debug)]
    struct DaySample {
        nh4: f32,
        no2: f32,
        no3: f32,
        nbc: f32,
    }

    /// Index of the sample maximising `f`.
    fn argmax(series: &[DaySample], f: impl Fn(&DaySample) -> f32) -> usize {
        series
            .iter()
            .enumerate()
            .fold((0usize, f32::MIN), |acc, (i, s)| {
                let v = f(s);
                if v > acc.1 {
                    (i, v)
                } else {
                    acc
                }
            })
            .0
    }

    fn run_days(days: usize) -> Vec<DaySample> {
        let mut w = World::new(48, 40, 42);
        w.seed_starter_tank();
        let mut out = Vec::with_capacity(days);
        // 60 ticks of 60 s = one sim hour per step, 24 steps per day.
        for _ in 0..days {
            for _ in 0..24 {
                w.tick(60.0);
            }
            let nh4 = w.chem.average(Species::Ammonia, &w.substrate);
            let no2 = w.chem.average(Species::Nitrite, &w.substrate);
            let no3 = w.chem.average(Species::Nitrate, &w.substrate);
            let (_nso, nbc) = w.total_bacteria();
            out.push(DaySample { nh4, no2, no3, nbc });
        }
        out
    }

    /// N2 — nitrite RISES THEN FALLS. The headline behaviour this crate
    /// exists to reproduce. See docs/CHEMISTRY_ORACLE.md.
    #[test]
    fn cycle_produces_nitrite_spike() {
        let series = run_days(60);
        let no2: Vec<f32> = series.iter().map(|s| s.no2).collect();

        let (peak_i, peak) =
            no2.iter().enumerate().fold(
                (0usize, 0.0f32),
                |acc, (i, v)| if *v > acc.1 { (i, *v) } else { acc },
            );

        // A spike is a peak strictly inside the window that is meaningfully
        // above both ends — not a monotonic ramp, and not a flat line.
        assert!(
            peak_i > 0 && peak_i < no2.len() - 1,
            "nitrite peaked at the edge of the window (day {peak_i}) — that is \
             a ramp, not a spike. series head={:?}",
            &no2[..8.min(no2.len())]
        );
        assert!(
            peak > no2[0] * 1.5,
            "nitrite peak {peak:.4} is not meaningfully above its start {:.4} \
             — the spike never happened",
            no2[0]
        );
        assert!(
            *no2.last().unwrap() < peak * 0.8,
            "nitrite never came back down: peak {peak:.4}, final {:.4}",
            no2.last().unwrap()
        );
    }

    /// N1 + N3 — ammonia is consumed, nitrate accumulates.
    #[test]
    fn ammonia_falls_and_nitrate_accumulates() {
        let series = run_days(60);
        let first = series[0];
        let last = *series.last().unwrap();
        assert!(
            last.nh4 < first.nh4 * 0.5,
            "N1: ammonia should be largely consumed: {:.4} -> {:.4}",
            first.nh4,
            last.nh4
        );
        assert!(
            last.no3 > first.no3,
            "N3: nitrate should accumulate: {:.4} -> {:.4}",
            first.no3,
            last.no3
        );
    }

    /// Nitrobacter must actually take hold rather than decaying to nothing.
    #[test]
    fn nitrobacter_establishes() {
        let series = run_days(60);
        let start_nbc = series[0].nbc;
        let peak_nbc = series.iter().map(|s| s.nbc).fold(0.0f32, f32::max);
        assert!(
            peak_nbc > start_nbc,
            "nitrobacter never grew above its seed ({start_nbc:.2} -> peak {peak_nbc:.2}) \
             — it is decaying, so nitrite can never be consumed"
        );
    }

    /// Nothing may go negative. Every field is clamped at zero on write; this
    /// catches a reaction that subtracts more than is present.
    #[test]
    fn concentrations_never_go_negative() {
        let mut w = World::new(32, 32, 7);
        w.seed_starter_tank();
        for step in 0..2000 {
            w.tick(30.0);
            for sp in Species::ALL {
                let v = w.chem.average(*sp, &w.substrate);
                assert!(
                    v >= 0.0 && v.is_finite(),
                    "{sp:?} went bad at step {step}: {v}"
                );
            }
        }
    }

    /// Deterministic given a seed — the property the whole crate claims in its
    /// module docs, and the precondition for using it as a test oracle.
    #[test]
    fn same_seed_same_result() {
        let run = |seed: u64| {
            let mut w = World::new(32, 32, seed);
            w.seed_starter_tank();
            for _ in 0..500 {
                w.tick(60.0);
            }
            (
                w.chem.average(Species::Ammonia, &w.substrate),
                w.chem.average(Species::Nitrate, &w.substrate),
                w.total_bacteria(),
            )
        };
        let a = run(12345);
        let b = run(12345);
        assert_eq!(a.0.to_bits(), b.0.to_bits(), "ammonia differs across runs");
        assert_eq!(a.1.to_bits(), b.1.to_bits(), "nitrate differs across runs");
        assert_eq!(a.2 .0.to_bits(), b.2 .0.to_bits(), "nitrosomonas differs");
    }

    /// The seed only reaches the simulation through falling-sand slip, so a
    /// tank whose substrate is already settled is seed-INDEPENDENT. That is a
    /// real property of this model, not a bug, and it is worth pinning: it
    /// means `seed_starter_tank` produces the same chemistry for every seed,
    /// and any future seed-sensitive chemistry would break this test loudly.
    #[test]
    fn settled_tank_is_seed_independent() {
        let run = |seed: u64| {
            let mut w = World::new(32, 32, seed);
            w.seed_starter_tank();
            for _ in 0..200 {
                w.tick(60.0);
            }
            w.chem.average(Species::Nitrate, &w.substrate)
        };
        assert_eq!(
            run(1).to_bits(),
            run(999_999).to_bits(),
            "a settled tank became seed-dependent — if that is intended, this \
             test should be replaced rather than relaxed"
        );
    }

    /// ...but a substrate mid-collapse does consume the RNG, so seeds must
    /// diverge THERE. Note the equilibrium is seed-independent: slip is a
    /// probabilistic gate, so the seed changes how fast a pile reaches its
    /// angle of repose, not what that angle is. Sample mid-collapse or this
    /// proves nothing.
    #[test]
    fn unsettled_substrate_diverges_by_seed() {
        let settle = |seed: u64| {
            let mut w = World::new(24, 24, seed);
            // A narrow loose column that must collapse into a slope — every
            // diagonal slip is an RNG draw.
            w.substrate.fill_region(SubstrateKind::Sand, 10, 2, 13, 20);
            // Mid-collapse: enough ticks for slip to matter, few enough that
            // the pile has not yet reached its (seed-independent) repose.
            for _ in 0..6 {
                w.tick(1.0);
            }
            let mut profile = Vec::new();
            for x in 0..24 {
                let mut col = 0u32;
                for y in 0..24 {
                    if !w.substrate.grid.get(x, y).kind.is_empty() {
                        col += 1;
                    }
                }
                profile.push(col);
            }
            profile
        };
        let a = settle(1);
        let b = settle(1);
        assert_eq!(a, b, "same seed must settle identically");
        let c = settle(987_654);
        assert_ne!(
            a, c,
            "different seeds produced an identical sand slope — the RNG is \
             not actually feeding the falling-sand step"
        );
    }

    // ---- Oracle invariants shared with the GDScript sim ----
    // See docs/CHEMISTRY_ORACLE.md. IDs here match the IDs asserted in
    // scripts/smoke_chemistry_oracle.gd, so a failure on either side points
    // at the same claim.

    /// N4 — the nitrite peak comes AFTER the ammonia peak. Ordering is what
    /// makes this a cycle rather than three unrelated curves.
    #[test]
    fn n4_nitrite_peaks_after_ammonia() {
        let series = run_days(60);
        let nh4_peak = argmax(&series, |s| s.nh4);
        let no2_peak = argmax(&series, |s| s.no2);
        assert!(
            no2_peak >= nh4_peak,
            "N4: nitrite peaked on day {no2_peak} but ammonia peaked on day \
             {nh4_peak} — nitrite must not lead ammonia"
        );
    }

    /// O1 — oxygen trends toward saturation at the surface, and agitation
    /// makes it get there faster.
    #[test]
    fn o1_oxygen_trends_to_saturation_with_agitation() {
        let run = |agitation: f32| -> f32 {
            let mut w = World::new(24, 24, 5);
            w.agitation = agitation;
            // Start deoxygenated, no substrate, so only surface exchange acts.
            for y in 0..24 {
                for x in 0..24 {
                    w.chem.set(Species::Oxygen, x, y, 1.0);
                }
            }
            for _ in 0..400 {
                w.chem.surface_exchange(w.surface_y, w.agitation, 60.0);
            }
            w.chem.get(Species::Oxygen, 12, w.surface_y)
        };
        let still = run(0.0);
        let bubbled = run(1.0);
        assert!(
            still > 1.0,
            "O1: oxygen must rise toward saturation even unagitated, got {still:.3}"
        );
        assert!(
            bubbled > still,
            "O1: aeration must raise the exchange rate — still={still:.3} \
             bubbled={bubbled:.3}"
        );
        assert!(
            bubbled <= 8.6,
            "O1: oxygen must not overshoot saturation, got {bubbled:.3}"
        );
    }

    /// O2 — nitrification consumes oxygen. The same tank under ammonia load
    /// must end lower in O2 than one without.
    #[test]
    fn o2_nitrification_consumes_oxygen() {
        let run = |ammonia: f32| -> f32 {
            let mut w = World::new(32, 32, 11);
            w.seed_starter_tank();
            w.agitation = 0.0; // no resupply, so demand is visible
            for y in 0..32 {
                for x in 0..32 {
                    if w.substrate.grid.get(x, y).kind.is_empty() {
                        w.chem.set(Species::Ammonia, x, y, ammonia);
                        w.chem.set(Species::Oxygen, x, y, 8.0);
                    }
                }
            }
            for _ in 0..300 {
                w.tick(60.0);
            }
            w.chem.average(Species::Oxygen, &w.substrate)
        };
        let loaded = run(4.0);
        let clean = run(0.0);
        assert!(
            loaded < clean,
            "O2: a tank under ammonia load must end lower in oxygen — \
             loaded={loaded:.4} clean={clean:.4}"
        );
    }

    /// P1 — pH falls as CO2 rises, at fixed KH.
    #[test]
    fn p1_ph_falls_as_co2_rises() {
        let mut w = World::new(8, 8, 1);
        let ph_at_co2 = |w: &mut World, co2: f32| -> f32 {
            w.chem.set(Species::Kh, 4, 4, 4.0);
            w.chem.set(Species::Co2, 4, 4, co2);
            w.chem.ph_at(4, 4)
        };
        let low = ph_at_co2(&mut w, 1.0);
        let high = ph_at_co2(&mut w, 30.0);
        assert!(
            high < low,
            "P1: more CO2 must mean lower pH — co2=1 gave {low:.3}, \
             co2=30 gave {high:.3}"
        );
    }

    /// P2 — KH buffers. For the same CO2 change, low KH must swing more.
    #[test]
    fn p2_low_kh_swings_more() {
        let mut w = World::new(8, 8, 1);
        let swing = |w: &mut World, kh: f32| -> f32 {
            w.chem.set(Species::Kh, 4, 4, kh);
            w.chem.set(Species::Co2, 4, 4, 2.0);
            let a = w.chem.ph_at(4, 4);
            w.chem.set(Species::Co2, 4, 4, 20.0);
            let b = w.chem.ph_at(4, 4);
            (a - b).abs()
        };
        let soft = swing(&mut w, 1.0);
        let hard = swing(&mut w, 12.0);
        assert!(
            soft >= hard,
            "P2: soft water (KH 1) must swing at least as much as hard \
             (KH 12) — soft={soft:.4} hard={hard:.4}"
        );
    }

    /// D1 — anaerobic zones remove nitrate.
    #[test]
    fn d1_anaerobic_zones_remove_nitrate() {
        let run = |anaerobic: f32| -> f32 {
            let mut w = World::new(32, 32, 13);
            w.seed_starter_tank();
            for c in w.substrate.grid.cells.iter_mut() {
                if c.kind.is_empty() {
                    continue;
                }
                // `anaerobic` is DERIVED each step from
                // `compaction * kind.anaerobic_susceptibility()`, so setting
                // it directly is pointless — substrate.step() overwrites it
                // on the first tick. Drive the inputs instead, and use Sand
                // (susceptibility 1.0) so a compacted bed can actually go
                // anoxic. This is why the first version of this test saw
                // 5.0000 vs 5.0000.
                c.kind = SubstrateKind::Sand;
                c.compaction = anaerobic;
                // Give denitrifiers something to work with.
                c.nitrosomonas = 0.5;
            }
            for y in 0..32 {
                for x in 0..32 {
                    if w.substrate.grid.get(x, y).kind.is_empty() {
                        w.chem.set(Species::Nitrate, x, y, 5.0);
                        w.chem.set(Species::Ammonia, x, y, 0.0);
                    }
                }
            }
            for _ in 0..200 {
                w.tick(60.0);
            }
            w.chem.average(Species::Nitrate, &w.substrate)
        };
        let anoxic = run(1.0);
        let oxic = run(0.0);
        assert!(
            anoxic < oxic,
            "D1: anaerobic substrate must consume nitrate — \
             anaerobic={anoxic:.4} aerobic={oxic:.4}"
        );
    }

    /// Diffusion conserves mass in a closed region: it moves solute between
    /// water cells, it must not create or destroy it.
    #[test]
    fn diffusion_conserves_mass() {
        let mut w = World::new(24, 24, 3);
        // No substrate at all — every cell is water, so nothing is excluded
        // and the total must hold exactly.
        for y in 0..24 {
            for x in 0..24 {
                w.chem
                    .set(Species::Nitrate, x, y, ((x * 7 + y * 3) % 11) as f32);
            }
        }
        let total = |w: &World| -> f64 {
            let mut t = 0.0f64;
            for y in 0..24 {
                for x in 0..24 {
                    t += w.chem.get(Species::Nitrate, x, y) as f64;
                }
            }
            t
        };
        let before = total(&w);
        for _ in 0..50 {
            let sub = &w.substrate;
            w.chem.diffuse(1.0, sub);
        }
        let after = total(&w);
        assert!(
            (after - before).abs() / before < 1e-3,
            "diffusion changed total nitrate by {:.6}% ({before:.3} -> {after:.3})",
            (after - before).abs() / before * 100.0
        );
    }
}
