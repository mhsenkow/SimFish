# CPU schooling reference

`schooling_cpu_baseline.json` records the implementation before the 2026-10-09
cached worst-neighbor selector and local packed-input optimization. The fixture
includes mixed species, metric and topological swimming, partner preference,
coincident positions, vertical bands and zero headings, at 16/64/128/256 fish.
Each row contains separation/alignment/cohesion vectors (9 components), neighbor
count, school speed in millimeters and seven ordered topological neighbor slots.

`smoke_schooling_force_equivalence.gd` compares all outputs, including order and
integer speed, and independently exercises ties and float32 distance rounding.
This is a behavior-preservation fixture: do not regenerate it to bless a failing
performance change. Deliberate future behavior changes need reviewed expectations.
