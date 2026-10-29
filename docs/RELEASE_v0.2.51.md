# walstad loom v0.2.51

Released October 29, 2026. A realism pass: the water is a fluid, the tank
lights its room, and every surface in it - plants, fish, wood, sand, the
surface itself - looks like it has been underwater for months.

## The water moves like water

One current now drives the whole tank: a real incompressible fluid solve on a
worker thread. Airstones lift a plume, the hang-on-back filter pulls water in
at the intake and pours it out of the spout, the heater turns a slow
convection cell, and rocks, substrate and curved glass block the water while
plant beds slow it. Plants sway with the water at their own position, marine
snow and bubbles ride the circulation, food and detritus settle where the
current dies, and ripples travel with the surface flow.

Fish swim *through the water*, not over the ground: to hold station they face
into the current and work, slow fish hold position in the filter stream,
carried fry get swept along, and fish working hard drift into the lee of a
rock or plant bed.

## The tank lights its room

While the lamp is on, the room dims around a tank whose surface is brightest,
light falls off toward the floor, and a water-tinted spill reaches the desk.
The milky veil from four layers of glass and the water box is gone, so the
scape keeps its contrast. A new **Tank glow** slider in the Light panel sets
how strongly the tank owns the room.

## Depth you can see

Haze now builds with the water you look through, toward lit water, so the back
glass recedes and the front stays crisp. From below, the surface is a mirror
of the tank - fish and blades meet their upside-down copies at the waterline.
From above it reflects the dimmed room and the lamp.

## Plants, fish and hardscape with a history

- **Plants** are planted in stands - stem bunches, crypt clumps, carpet
  patches, wall-to-wall valli - and stem plants carry a leaf pair at every
  node rising to a crown. Bunches dome; carpets fan into lawn.
- **Fish** have a spindle profile: deepest behind the head, a pinched waist
  before the tail, and fins solid enough to read at tank distance.
- **Driftwood** in the community tanks is a climbing branch, and all wood and
  stone carry mulm, biofilm, algae patches and a dark algae band at the bed.
- **The substrate at the glass** is a gravel cap over dark soil, mixed through
  the boundary, with roots running down it.
- **Established tanks** open with a real snail colony (dozens, every size).

## The reef is built on rock

The reef cube and pico reef get stacked live rock - an arch over a cave, a
bommie, a pillar - crusted in coralline algae, with corals settled on its
ledges. The water is clearer, the sand no longer blows out, staghorns and soft
corals come in several colours, and the reef palette gained coralline violets.

## Notes

- Saves keep working; tanks built before this version keep their layout until
  they are rebuilt from a template.
- `dev/visual_capture.gd` takes `VISUAL_CAPTURE_CFG` overrides and sequence
  strides; `dev/fish_behaviour_probe` reports current at fish, a flow map and
  a small-life census.
