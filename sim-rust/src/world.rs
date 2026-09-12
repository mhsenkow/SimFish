//! Top-level world: composes substrate + chemistry, exposes a single tick.

use crate::chemistry::{nitrogen_cycle_step, ChemistryField, Species};
use crate::substrate::{SubstrateKind, SubstrateSim};
use rand::SeedableRng;
use rand_xoshiro::Xoshiro256StarStar;

pub struct World {
    pub substrate: SubstrateSim,
    pub chem: ChemistryField,
    pub surface_y: usize,
    /// 0..1, raised by the bubbler. Affects surface gas exchange rate.
    pub agitation: f32,
    /// Sim age in seconds since start.
    pub elapsed: f32,
    rng: Xoshiro256StarStar,
}

impl World {
    pub fn new(width: usize, height: usize, seed: u64) -> Self {
        Self {
            substrate: SubstrateSim::new(width, height),
            chem: ChemistryField::new(width, height),
            surface_y: (height as f32 * 0.15) as usize,
            agitation: 0.1,
            elapsed: 0.0,
            rng: Xoshiro256StarStar::seed_from_u64(seed),
        }
    }

    /// Convenience for tests/demos: drop a 12-cell deep aquasoil bed across the
    /// floor, set baseline water chemistry that matches "tap water plus a fresh
    /// dose of ammonia" - i.e. a tank that's about to start its nitrogen cycle.
    pub fn seed_starter_tank(&mut self) {
        let h = self.chem.height;
        let w = self.chem.width;
        // Substrate slab.
        self.substrate
            .fill_region(SubstrateKind::Aquasoil, 0, h - 14, w - 1, h - 3);
        self.substrate
            .fill_region(SubstrateKind::Gravel, 0, h - 3, w - 1, h - 1);

        // Tap water chemistry baseline + initial ammonia "ghost feeding" dose.
        for y in self.surface_y..h {
            for x in 0..w {
                if !self.substrate.grid.get(x, y).kind.is_empty() {
                    continue;
                }
                self.chem.set(Species::Oxygen, x, y, 8.0);
                self.chem.set(Species::Co2, x, y, 3.0);
                self.chem.set(Species::Kh, x, y, 4.0);
                self.chem.set(Species::Gh, x, y, 6.0);
                self.chem.set(Species::Ammonia, x, y, 2.0);
                self.chem.set(Species::Iron, x, y, 0.05);
                self.chem.set(Species::Potassium, x, y, 5.0);
                self.chem.set(Species::Phosphate, x, y, 0.5);
            }
        }
    }

    /// Advance the world by `dt` seconds (sim time). All systems are stepped
    /// in a stable order; deterministic given the RNG state.
    pub fn tick(&mut self, dt: f32) {
        self.elapsed += dt;
        self.substrate.step(dt, &mut self.rng);
        self.chem
            .surface_exchange(self.surface_y, self.agitation, dt);
        nitrogen_cycle_step(&mut self.chem, &mut self.substrate, dt);
        self.chem.diffuse(dt, &self.substrate);
    }

    /// Average pH across all water cells (slow O(N) - fine for UI).
    pub fn average_ph(&self) -> f32 {
        let mut sum = 0.0;
        let mut count = 0;
        for y in 0..self.chem.height {
            for x in 0..self.chem.width {
                if self.substrate.grid.get(x, y).kind.is_empty() && y >= self.surface_y {
                    sum += self.chem.ph_at(x, y);
                    count += 1;
                }
            }
        }
        if count == 0 {
            7.0
        } else {
            sum / count as f32
        }
    }

    /// Total bacteria biomass across all substrate cells (both populations).
    /// Good "cycle complete" indicator: it climbs as the tank matures.
    pub fn total_bacteria(&self) -> (f32, f32) {
        let mut nso = 0.0;
        let mut nbc = 0.0;
        for c in &self.substrate.grid.cells {
            let cap = c.kind.bacterial_capacity();
            nso += c.nitrosomonas * cap;
            nbc += c.nitrobacter * cap;
        }
        (nso, nbc)
    }
}
