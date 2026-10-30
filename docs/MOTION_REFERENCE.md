# Motion reference — what the real animals do

*Drafted 2026-10-30 for [CREATURE_MOTION_700.md](CREATURE_MOTION_700.md) #96
(reference library) and #97 (published kinematics). Code anchors are from
`5ad6dd3`. Phase 1 work is changing `fish.gd`, `hydrodynamics.gd`,
`fauna_voxel_builder.gd` and the fauna shader in the working tree, so grep the
symbol before trusting a line number.*

Tune motion against footage of real animals, not against memory or against
other games. This page lists, for each creature family and behaviour, what to
look for and where to find good footage. It ends with one table of published
numbers. Each tuning constant should cite a row in that table.

## How to use this

- **Watch slowly.** Step through footage a frame at a time, then at 0.25×,
  then at real speed. Most of what matters (the head turning before the body,
  the tail still swinging after a stop) happens in a few frames.
- **Measure in body lengths and frames,** not millimetres. The code has no
  declared world scale. Backlog #581 assumes 1 u ≈ 6 cm, but a comment in
  `snail.gd` (`STUCK_PROGRESS_MIN_SQ`,
  [snail.gd:174](../shaders-godot/godot-project/scripts/snail.gd:174)) treats
  0.008 u as about 8 mm, which implies 1 u ≈ 1 m. For fish, the code's own
  body length is `adult_voxel_scale * 5.5 * body_elongation * scale.x`
  ([fish.gd:7295](../shaders-godot/godot-project/scripts/fish.gd:7295)), so
  express targets as L (body lengths) and L/s.
- **Film our own reference.** A phone in 240 fps slow motion against the front
  glass, with a ruler card taped to the glass, gives calibrated, licence-free
  footage of exactly the species the game has. Prefer it for the blind review
  ([MOTION_REVIEW_PROTOCOL.md](MOTION_REVIEW_PROTOCOL.md)).
- **Match the view.** The game is mostly seen side-on through the front glass.
  Lab footage is often dorsal (from above). A dorsal view shows the body wave
  at full amplitude; a side view hides most of it (backlog #172, #394).
- **Convert rates.** Game phases are in radians per second. Divide by 2π for
  hertz.

**Citation rule.** The references below are ones we are confident exist. They
are given as author, year, title and journal or publisher. Volume and page
numbers are left out on purpose: look them up rather than trust a copy. Where
we were not sure a specific paper exists, the entry gives search terms instead,
sometimes with author names to search for. There are no URLs on this page.

## General references

| Reference | Use it for |
|---|---|
| Thomas & Johnston (1981), *The Illusion of Life: Disney Animation* | The twelve principles the backlog is graded against |
| Williams (2001), *The Animator's Survival Kit* | Timing, spacing and exposure-sheet practice |
| Videler (1993), *Fish Swimming* (Chapman & Hall) | Body waves, stride length, swimming modes, fast starts |
| Webb (1975), *Hydrodynamics and energetics of fish propulsion*, Bulletin of the Fisheries Research Board of Canada | Classic kinematics and energetics |
| Lindsey (1978), "Form, function and locomotory habits in fish", *Fish Physiology* vol. VII | The swimming-mode names the code uses (anguilliform, subcarangiform, thunniform, ostraciiform, labriform) and the tetraodontiform mode #331 proposes |
| Sfakiotakis, Lane & Davies (1999), "Review of fish swimming modes for aquatic locomotion", *IEEE Journal of Oceanic Engineering* | A readable modern summary of the same modes |
| Shadwick & Lauder (eds, 2006), *Fish Biomechanics* (*Fish Physiology* vol. 23) | Chapters on undulatory swimming, fins and fast starts |
| Domenici & Kapoor (eds, 2010), *Fish Locomotion: An Eco-Ethological Perspective* | Behaviour-level locomotion: escapes, predation, schooling |
| Johansson (1973), "Visual perception of biological motion and a model for its analysis", *Perception & Psychophysics* | Why silhouettes and point lights are enough to judge "alive" (used by the review protocol) |

**Footage that is usually good:** supplementary movies attached to *Journal of
Experimental Biology* papers (many of the papers below have them); high-speed
lab video from university biomechanics labs; nature-documentary slow motion;
and hobbyist macro and slow-motion clips of the exact aquarium species, which
are often the best source for the small freshwater animals.

---

## Fish

### Steady body-caudal swimming (the baseline every fish is judged against)

**Look for:**
- A wave that travels from head to tail. Each point of the body reaches its
  maximum sideways swing a little later than the point in front of it.
- Amplitude that is small at the head and grows toward the tail. The head yaws
  only slightly.
- The tail tip drawing a flattened figure-eight when seen from the side.
- Tail-beat frequency that rises with speed, while the tip amplitude stays
  roughly constant.

**Sources:** Bainbridge (1958), "The speed of swimming of fish as related to
size and to the frequency and amplitude of the tail beat", *Journal of
Experimental Biology*; Videler (1993); Taylor, Nudds & Thomas (2003), "Flying
and swimming animals cruise at a Strouhal number tuned for high power
efficiency", *Nature*; Tytell & Lauder (2004), "The hydrodynamics of eel
swimming: I. Wake structure", *Journal of Experimental Biology* (anguilliform).

**Search terms:** "fish midline kinematics dorsal view", "carangiform swimming
high speed video", "eel swimming kinematics", "zebrafish swimming slow motion".

**Game:** the three sibling pivots and their phases in `_motion_substep`
([fish.gd:7793](../shaders-godot/godot-project/scripts/fish.gd:7793)); backlog
#64–#66 (spine and travelling wave), #87 (phase-lag metric), #88 (Strouhal).

### C-start and fast-start escape

**Look for:**
- **Stage 1:** the body bends into a C, with the head swinging away from the
  threat. The centre of mass barely moves forward. In real fish this lasts
  only tens of milliseconds.
- **Stage 2:** one large stroke the other way. The body straightens, and the
  fish accelerates harder than at any other time.
- A coast with the fins folded, then a curved recovery.
- Escape directions that vary from trial to trial. There is no fixed angle.

**Sources:** Eaton, Bombardieri & Meyer (1977), "The Mauthner-initiated
startle response in teleost fish", *Journal of Experimental Biology*; Domenici
& Blake (1997), "The kinematics and performance of fish fast-start swimming",
*Journal of Experimental Biology*; Budick & O'Malley (2000), "Locomotor
repertoire of the larval zebrafish: swimming, turning and prey capture",
*Journal of Experimental Biology*; Burgess & Granato (2007), "Sensorimotor
gating in larval zebrafish", *Journal of Neuroscience* (short- and
long-latency C-starts); Tytell & Lauder (2008), "Hydrodynamics of the escape
response in bluegill sunfish", *Journal of Experimental Biology*.

**Search terms:** "zebrafish C-start high speed video", "goldfish Mauthner
escape response", "fish fast start 1000 fps".

**Game:** startles are set in `tick()` (for example
[fish.gd:6298](../shaders-godot/godot-project/scripts/fish.gd:6298)), and the
heading change is limited by `FishLifeBouts.inertial_turn`
([fish_life_bouts.gd:151](../shaders-godot/godot-project/scripts/fish_life_bouts.gd:151)).
There is no coil. Backlog #145, #122, #342, #360; the timing spec is in
[MOTION_EXPOSURE_SHEETS.md](MOTION_EXPOSURE_SHEETS.md).

### Burst-and-coast (danios, tetras, larval zebrafish)

**Look for:**
- A few strong beats, then a straight glide with the tail held straight and
  the fins tucked.
- Speed that drops fast at the start of the glide, then slowly. That is drag,
  not a linear slowdown.
- In danios, a visible rhythm of bursts every half second to a second and a
  half (backlog #338; observational, so measure it).

**Sources:** Weihs (1974), "Energetic advantages of burst swimming of fish",
*Journal of Theoretical Biology*; Videler & Weihs (1982), "Energetic advantages
of burst-and-coast swimming of fish at high speeds", *Journal of Experimental
Biology*; Müller & van Leeuwen (2004), "Swimming of larval zebrafish: ontogeny
of body waves and implications for locomotory development", *Journal of
Experimental Biology*.

**Search terms:** "zebra danio swimming slow motion", "beat and glide
swimming", "intermittent swimming fish".

**Game:** `TopdownMotion.burst_glide_speed_mult`, `_motion_glide_bias`
([fish.gd:2203](../shaders-godot/godot-project/scripts/fish.gd:2203)), and the
dart, hover and cruise bouts that every species shares
([fish_life_bouts.gd:109](../shaders-godot/godot-project/scripts/fish_life_bouts.gd:109)).
Backlog #338, #254, #255, #337.

### Labriform rowing, hovering and braking (angelfish, severum, gourami, reef fish)

**Look for:**
- Pectorals beating while the body stays nearly straight.
- The fin tip tracing a loop, not a hinge flap. Fins that move mostly front to
  back are rowing; fins that move mostly up and down are flapping.
- A small body rock with each stroke.
- Hovering held on alternating pectoral sculls, and turning on one side's fin.
- Braking with both pectorals flared forward.

**Sources:** Webb (1973), "Kinematics of pectoral fin propulsion in
*Cymatogaster aggregata*", *Journal of Experimental Biology*; Walker &
Westneat (2002), "Performance limits of labriform propulsion and correlates
with fin shape and motion", *Journal of Experimental Biology*; Drucker & Lauder
(1999), "Locomotor forces on a swimming fish: three-dimensional vortex wake
dynamics quantified using digital particle image velocimetry", *Journal of
Experimental Biology*.

**Search terms:** "angelfish pectoral fin slow motion", "bluegill pectoral fin
hovering", "wrasse labriform swimming", "trout pectoral fin braking".

**Game:** `pec_freq_base` and the labriform branch
([fish.gd:7797](../shaders-godot/godot-project/scripts/fish.gd:7797),
[fish.gd:7825](../shaders-godot/godot-project/scripts/fish.gd:7825)); the
single-axis pectoral writes
([fish.gd:8053](../shaders-godot/godot-project/scripts/fish.gd:8053)). Backlog
#284, #345, #328, #408, #156.

### Guppy sigmoid display

**Look for:**
- The male positions himself in front of or beside the female and bends into
  an S, with his fins spread, holding it briefly while he quivers.
- Display bouts that repeat. Gonopodial thrusts and "sneak" attempts are
  separate behaviours.
- The female turning away, diving or ignoring him.

**Sources:** Baerends, Brouwer & Waterbolk (1955), "Ethological studies on
*Lebistes reticulatus* (Peters). I. An analysis of the male courtship
pattern", *Behaviour*; Houde (1997), *Sex, Color, and Mate Choice in Guppies*
(Princeton University Press); Magurran (2005), *Evolutionary Ecology: The
Trinidadian Guppy* (Oxford University Press).

**Search terms:** "guppy sigmoid display", "guppy courtship slow motion",
"Poecilia reticulata courtship behaviour".

**Game:** `FishLifeBouts.sigmoid_env`
([fish_life_bouts.gd:276](../shaders-godot/godot-project/scripts/fish_life_bouts.gd:276))
and the S applied in the pose pass
([fish.gd:7943](../shaders-godot/godot-project/scripts/fish.gd:7943)). Backlog
#401, #325, #358.

### Corydoras air dash and wink

**Look for:**
- **The dash:** a near-vertical rush from the bottom to the surface, a gulp,
  then a roll and a slower curved glide back down. Several fish in a group
  often go within a short time of each other.
- **The wink:** one eye rotates downward for a moment while the fish rests.
  It is eye rotation; corydoras have no eyelids.

**Sources:** Kramer & McClure (1980), "Aerial respiration in the catfish,
*Corydoras aeneus* (Callichthyidae)", *Canadian Journal of Zoology*; Kramer &
McClure (1982), "Aquatic surface respiration, a widespread adaptation to
hypoxia in tropical freshwater fishes", *Environmental Biology of Fishes*.

**Search terms:** "corydoras air breathing dash", "corydoras going to the
surface", "corydoras wink", "corydoras eye roll".

**Game:** surface trips use the `_aerial_timer` and `home_y` override
([fish.gd:4310](../shaders-godot/godot-project/scripts/fish.gd:4310)). There is
no eye pivot. Backlog #279, #317, #166, #131.

### Pleco and otocinclus suckermouth grazing

**Look for:**
- The oral disc sealed on the glass, with the teeth rasping in a steady pulse.
  This is best seen from the front, through the pane the fish is on.
- A small forward creep between bites; the body flat to the surface; the tail
  fanning gently.
- Breathing while attached: water still passes the gills.

**Sources:** Geerinckx, Herrel & Adriaens (2011), "Suckermouth armored catfish
resolve the paradox of simultaneous respiration and suction attachment: a
kinematic study of *Pterygoplichthys disjunctivus*", *Journal of Experimental
Zoology A*.

**Search terms:** "bristlenose pleco mouth on glass", "otocinclus grazing glass
close up", "suckermouth catfish rasping slow motion".

**Game:** no mouth disc or grazing rhythm yet. Backlog #319, #484, #201, #320.

### Betta flare and bubble nest

**Look for:**
- **Frontal display:** gill covers and the membrane beneath them flared, and
  every fin spread. **Lateral display:** broadside to the rival, with the tail
  beating.
- Display bouts that come and go, not a constant flare.
- **Bubble nest:** the male gulps at the surface, blows mucus-coated bubbles
  under a floating plant or leaf, and carries stray bubbles (and later eggs)
  back to the nest.

**Sources:** Simpson (1968), "The display of the Siamese fighting fish,
*Betta splendens*", *Animal Behaviour Monographs*.

**Search terms:** "betta flaring slow motion", "betta splendens opercular
flare", "betta bubble nest building", "betta spawning embrace".

**Game:** the courtship flare raises wag and pectoral amplitude and puffs
`_display_scale`
([fish.gd:8084](../shaders-godot/godot-project/scripts/fish.gd:8084)). There
are no opercula and no nest. Backlog #197, #198, #322, #399, #188.

### Puffer median-fin swimming and eye rotation

**Look for:**
- The dorsal and anal fins buzzing, with the tail folded. The tail is used as
  a rudder and only beats for a burst.
- Very precise hovering and turning in place.
- Each eye moving on its own, looking at a different thing.

**Sources:** Gordon, Plaut & Kim (1996), "How puffers (Teleostei:
Tetraodontidae) swim", *Journal of Fish Biology*; Wainwright & Turingan
(1997), "Evolution of pufferfish inflation behavior", *Evolution*; Fritsches &
Marshall (2002), "Independent and conjugate eye movements during optokinesis
in teleost fish", *Journal of Experimental Biology*.

**Search terms:** "pufferfish swimming slow motion dorsal fin", "pea puffer
eyes moving independently", "dwarf puffer hunting snails".

**Game:** body shape `globiform` maps to `ostraciiform`, a tail-driven mode
([fish.gd:2614](../shaders-godot/godot-project/scripts/fish.gd:2614)),
so the puffer swims with the wrong fins. Backlog #405, #239, #298, #127, #331.

### Goby perching and hopping

**Look for:**
- Resting propped on the pelvic fins (in many gobies, fused into a sucker)
  with the head raised.
- Short hops of a few beats, landing at once. Gobies don't hover.
- Swivelling eyes. Climbing species use the sucker to climb rock and glass.

**Sources:** Schoenfuss & Blob (2003), "Kinematics of waterfall climbing in
Hawaiian freshwater fishes (Gobiidae): vertical propulsion at the
aquatic–terrestrial interface", *Journal of Zoology*.

**Search terms:** "bumblebee goby hopping", "Stiphodon goby climbing glass",
"Rhinogobius perching".

**Game:** the goby uses the shared `dart` swim pattern. Backlog #293, #416,
#132.

### Hillstream loach adherent gliding

**Look for:**
- A flattened body with the pectoral and pelvic fins forming a seal on the
  surface.
- A glide with no visible swimming, then a sudden short skitter.
- Grazing while holding position in a current.

**Sources:** no paper we are certain of. **Search terms:** "hillstream loach
gliding on glass", "Sewellia lineolata", "Gastromyzon", "Beaufortia",
and the author search "De Meyer Geerinckx hillstream loach".

**Game:** body shape `depressed` maps to `labriform`. Backlog #414, #201, #381.

### Gar ambush and the S-start strike

**Look for:**
- **Gar:** hanging motionless near the surface like a stick, sculling only
  its fins, then a fast **sideways snap of the head and jaws**. The body
  barely lunges.
- **Pike-type predators (and killifish strikes):** the body coils into an S,
  then straightens into a straight lunge with the head on line with the prey.
  That differs from the C-start, where the head swings away.

**Sources:** Porter & Motta (2004), "A comparison of strike and prey capture
kinematics of three species of piscivorous fishes: Florida gar (*Lepisosteus
platyrhincus*), redfin needlefish (*Strongylura notata*), and great barracuda
(*Sphyraena barracuda*)", *Marine Biology*; Webb & Skadsen (1980), "Strike
tactics of *Esox*", *Canadian Journal of Zoology*; Harper & Blake (1991), "Prey
capture and the fast-start performance of northern pike *Esox lucius*",
*Journal of Experimental Biology*.

**Search terms:** "Florida gar strike slow motion", "spotted gar feeding",
"pike strike high speed S-start".

**Game:** no stalk or strike shape. The backlog's gar entry (#415) names an
S-start; footage of gar shows a sideways head strike, so treat #146 as the
pike/killifish shape and give the gar its own. Backlog #146, #168, #415,
#485.

### Suction feeding and the strike at food

**Look for:**
- The mouth and throat expanding *before* contact, so the particle is pulled
  in rather than bitten.
- The gill covers flaring just after, to expel the water. Cichlids also push
  the upper jaw forward.
- In larval zebrafish, both eyes converging when the hunt starts.

**Sources:** Day, Higham, Holzman & Van Wassenbergh (2015), "Morphology,
kinematics, and dynamics: the mechanics of suction feeding in fishes",
*Integrative and Comparative Biology*; Wainwright, Carroll, Collar, Day, Higham
& Holzman (2007), "Suction feeding mechanics, performance, and diversity in
fishes", *Integrative and Comparative Biology*; Bianco, Kampff & Engert (2011),
"Prey capture behavior evoked by simple visual stimuli in larval zebrafish",
*Frontiers in Systems Neuroscience*.

**Search terms:** "suction feeding high speed video", "cichlid jaw protrusion
slow motion", "larval zebrafish prey capture eye convergence".

**Game:** the gape fires after the meal is recorded (`_trigger_mouth_gape`,
[fish.gd:1739](../shaders-godot/godot-project/scripts/fish.gd:1739)). Backlog
#124, #343, #476, #477, #299.

---

## Shrimp

### Caridean tail flip

**Look for:**
- The abdomen flexing under the body in one fast stroke, sending the shrimp
  backward and up while the head still faces the threat.
- The tail fan spreading during the flip.
- A slower re-extension, often followed by a second or third flip.
- Legs tucked and antennae swept forward during the flip.

**Sources:** Arnott, Neil & Ansell (1998), "Tail-flip mechanism and
size-dependent kinematics of escape swimming in the brown shrimp *Crangon
crangon*", *Journal of Experimental Biology*. For the crayfish version: Wine &
Krasne (1972), "The organization of escape behaviour in the crayfish",
*Journal of Experimental Biology*; Edwards, Heitler & Krasne (1999), "Fifty
years of a command neuron: the neurobiology of escape behavior in the
crayfish", *Trends in Neurosciences*.

**Search terms:** "shrimp tail flip slow motion", "cherry shrimp jump slow
motion", "Crangon escape response", "crayfish tail flip high speed".

**Game:** `_escape_remaining` and the flip pitch
([shrimp.gd:915](../shaders-godot/godot-project/scripts/shrimp.gd:915),
[shrimp.gd:1813](../shaders-godot/godot-project/scripts/shrimp.gd:1813)).
Backlog #518, #519, #23, #291, #541.

### Pleopod swimming

**Look for:**
- The swimmerets beating from back to front in a wave, each pair a little
  behind the one behind it.
- The legs folded and the body level while swimming. Hovering is possible.

**Sources:** Murphy, Webster, Kawaguchi, King & Yen (2011), "Metachronal
swimming in Antarctic krill: gait kinematics and system design", *Marine
Biology*. Krill are not shrimp, but the stroke is the same kind.

**Search terms:** "shrimp swimmerets slow motion", "amano shrimp swimming",
"metachronal swimming krill".

**Game:** `_pleopod_phase` is advanced and never drawn
([shrimp.gd:1806](../shaders-godot/godot-project/scripts/shrimp.gd:1806)).
Backlog #520, #521.

### Cheliped picking

**Look for:**
- The two small clawed front pairs alternating between the surface and the
  mouth, quickly and continuously, while the body stays still.
- The mouthparts fluttering and the short antennules flicking.

**Sources:** no paper we are certain of. **Search terms:** "cherry shrimp
picking slow motion", "Neocaridina eating close up", "shrimp chelipeds feeding
macro".

**Game:** the feeding pose is a body nod (`grab`,
[shrimp.gd:1830](../shaders-godot/godot-project/scripts/shrimp.gd:1830)). Backlog #524, #539, #523.

### Cleaner shrimp rocking

**Look for:**
- Side-to-side body rocking to advertise, with the antennae waving.
- The client fish holding still with its mouth and gill covers open.

**Sources:** Becker, Curtis & Grutter (2005), "Cleaner shrimp use a rocking
dance to advertise cleaning service to clients", *Current Biology*.

**Search terms:** "cleaner shrimp rocking dance", "Lysmata amboinensis
cleaning fish".

**Game:** CLEAN is a held position. Backlog #532.

## Crabs, lobsters and mantis shrimp

### Crab sideways gait

**Look for:**
- Walking sideways: the leading legs pull and the trailing legs push.
- The legs moving in alternating sets rather than one at a time, with the
  body slung low between arched legs.
- Underwater, lighter "punting" and bounding gaits.

**Sources:** Blickhan & Full (1987), "Locomotion energetics of the ghost crab.
II. Mechanics of the centre of mass during walking and running", *Journal of
Experimental Biology*; Martinez, Full & Koehl (1998), "Underwater punting by an
intertidal crab: a novel gait revealed by the kinematics of pedestrian
locomotion in air versus water", *Journal of Experimental Biology*.

**Search terms:** "crab walking sideways slow motion", "red claw crab
walking", "crab alternating tetrapod gait".

**Game:** crab legs are hinged (#24) and their phases are
`(3 − i)·π/2`, sides opposite
([shrimp.gd:692](../shaders-godot/godot-project/scripts/shrimp.gd:692)).
That is a quarter-cycle wave from rear to front, not alternating sets.
Backlog #542, #543, #516.

### Claw-to-mouth feeding

**Look for:** the claws alternately picking food and passing it to the
mouthparts, with the maxillipeds working. Backlog #544 estimates 1–2 Hz;
measure it.

**Sources:** no paper we are certain of. **Search terms:** "crab eating close
up claws", "fiddler crab feeding", "Thai micro crab feeding".

**Game:** claws are static. Backlog #544, #560.

### Lobsters and crayfish

**Look for:** walking forward with the claws carried raised; the long
antennae sweeping alternately; backward tail flips in a series, slower and
bigger than a shrimp's.

**Sources:** Wine & Krasne (1972); Edwards, Heitler & Krasne (1999).

**Search terms:** "crayfish walking", "crayfish tail flip escape", "lobster
antennae sweeping".

**Game:** lobster gait profile `steps_per_unit` 3.2
([shrimp.gd:1666](../shaders-godot/godot-project/scripts/shrimp.gd:1666));
flips are shared with shrimp. Backlog #548–#552.

### Mantis shrimp raptorial strike, and the pistol snap

**Look for:**
- The stalked eyes scanning and moving independently, then fixing on a
  target.
- A strike lasting a few milliseconds, which is invisible at 60 fps; only
  high-speed footage shows it. Spearers and smashers strike differently.
- The pistol shrimp's claw closing almost instantly, with a cavitation bubble.

**Sources:** Patek, Korff & Caldwell (2004), "Deadly strike mechanism of a
mantis shrimp", *Nature*; Land, Marshall, Brownless & Cronin (1990), "The
eye-movements of the mantis shrimp *Odontodactylus scyllarus* (Crustacea:
Stomatopoda)", *Journal of Comparative Physiology A*; Versluis, Schmitz, von der
Heydt & Lohse (2000), "How snapping shrimp snap: through cavitating bubbles",
*Science*.

**Search terms:** "mantis shrimp strike high speed", "peacock mantis shrimp
eyes moving", "pistol shrimp snap slow motion".

**Game:** the raptorial arms are static
([shrimp.gd:585](../shaders-godot/godot-project/scripts/shrimp.gd:585)).
Backlog #554, #555, #533.

## Snails

### Pedal waves on the glass

**Look for:**
- Dark bands travelling along the sole, seen through the glass.
- Which way they travel relative to the snail. **Direct** waves move the same
  way as the snail (typical of pulmonates); **retrograde** waves move the
  other way (common in prosobranchs). Some snails show two staggered sets
  (**ditaxic**).
- Snails with no bands at all. Some freshwater pulmonates, *Lymnaea* among
  them, glide mainly on cilia in the mucus. Check each species before giving
  it bands.

**Sources:** Lissmann (1945), "The mechanism of locomotion in gastropod
molluscs. I. Kinematics", *Journal of Experimental Biology*; Denny (1980),
"The role of gastropod pedal mucus in locomotion", *Nature*; Lai, del Álamo,
Rodríguez-Rodríguez & Lasheras (2010), "The mechanics of the adhesive
locomotion of terrestrial gastropods", *Journal of Experimental Biology* (land
snails, but the clearest wave measurements).

**Search terms:** "snail foot through glass pedal waves", "nerite snail
underside glass", "mystery snail crawling underside", "Lymnaea ciliary
gliding".

**Game:** there are no pedal waves. The foot squashes as a whole on
`_pulse_phase` ([snail.gd:802](../shaders-godot/godot-project/scripts/snail.gd:802)).
Backlog #565, #566, #581.

### Shell sway

**Look for:** the shell rocking side to side and hitching forward on the
foot; the shell lagging the head in a turn and settling after it; ramshorns
carrying the shell upright.

**Sources:** no paper we are certain of. **Search terms:** "ramshorn snail
crawling", "apple snail crawling on glass", "nerite snail crawling time
lapse".

**Game:** the shell is rigid on the foot. Backlog #567, #568, #573.

### Tentacle withdrawal and full retraction

**Look for:**
- The order: tentacles shorten first, then the head pulls in and the foot
  retracts, and last the shell clamps down or the operculum closes.
- Re-emergence in reverse, slowly and cautiously.

**Sources:** Ferguson & Benjamin (1991), "The whole-body withdrawal response
of *Lymnaea stagnalis*. I. Identification of central motoneurones and
muscles", *Journal of Experimental Biology*.

**Search terms:** "snail tentacle retraction slow motion", "mystery snail
operculum closing", "nerite snail clamping to glass".

**Game:** stalks and shell tuck ease in and out, but start on the same frame
(`EYE_RETRACT_RATE`, `TUCK_IN_RATE`,
[snail.gd:252](../shaders-godot/godot-project/scripts/snail.gd:252)).
Backlog #576, #577, #39, #28.

### Righting

**Look for:** the foot reaching out and twisting to find purchase, gripping,
then levering the shell over, often after several tries.

**Sources:** no paper we are certain of. **Search terms:** "snail righting
itself", "mystery snail flipping over".

**Game:** a fixed slerp (`RIGHTING_RATE`,
[snail.gd:289](../shaders-godot/godot-project/scripts/snail.gd:289)). Backlog
#575, #292.

## Worms

### Tubifex withdrawal and tail waving

**Look for:**
- Heads down in tubes and tails waving in the water.
- Waving that gets more vigorous as oxygen falls.
- The whole patch vanishing into the substrate in a fraction of a second when
  disturbed, then worms re-emerging one by one.

**Sources:** for the rapid escape reflex in a close relative (the blackworm),
Drewes & Fourtner (1989), "Hindsight and rapid escape in a freshwater
oligochaete", *Biological Bulletin*. For tubifex itself, no paper we are
certain of. **Search terms:** "tubifex colony tail waving", "tubifex worms
retract", "tubificid respiration low oxygen", "blackworm escape reflex".

**Game:** fixed-rate wriggle (`WRIGGLE_FREQ`,
[tubifex_patch.gd:20](../shaders-godot/godot-project/scripts/tubifex_patch.gd:20));
grazing hides one worm in a frame
([tubifex_patch.gd:102](../shaders-godot/godot-project/scripts/tubifex_patch.gd:102)).
Backlog #605–#607.

## Microfauna

### Daphnia hop-and-sink

**Look for:** a quick stroke of the large antennae lifting the animal, then a
passive sink with the body upright, repeated several times a second; swarms
gathering toward light.

**Sources:** no paper we are certain enough to cite. **Search terms:** "daphnia
hop and sink", "daphnia swimming behavior microscope", and the author search
"Dodson Daphnia swimming behavior".

**Game:** morph 1 rises and sinks on a square wave
([microfauna_swarm.gd:184](../shaders-godot/godot-project/scripts/microfauna_swarm.gd:184)).
Backlog #638, #639.

### Copepod escape jumps

**Look for:** a copepod hanging or cruising, then a burst of explosive jumps
(antennae folded, legs kicking), each covering several body lengths, aimed
away from the disturbance.

**Sources:** Buskey, Lenz & Hartline (2002), "Escape behavior of planktonic
copepods in response to hydrodynamic disturbances: high speed video analysis",
*Marine Ecology Progress Series*; Kiørboe, Andersen, Langlois & Jakobsen
(2010), "Unsteady motion: escape jumps in planktonic copepods, their kinematics
and energetics", *Journal of the Royal Society Interface*.

**Search terms:** "copepod escape jump high speed", "cyclops copepod swimming".

**Game:** morph 0 hops when a wake reaches it
([microfauna_swarm.gd:163](../shaders-godot/godot-project/scripts/microfauna_swarm.gd:163)).
Backlog #640, #641.

## Clams, anemones and hydra

### Clams and mussels

**Look for:** siphons that extend only after the valves have opened, then
pulse while filtering; valves that close quickly when a shadow passes or the
clam is touched, and reopen slowly; the foot digging (extend, anchor, pull).

**Sources:** no single paper we are certain of. **Search terms:** "freshwater
mussel siphon closing", "valvometry mussel valve closure", "giant clam shadow
response mantle", "fingernail clam burrowing".

**Game:** symmetric exponential gape
([clam.gd:230](../shaders-godot/godot-project/scripts/clam.gd:230)). Backlog
#619–#624.

### Anemones

**Look for:** tentacle withdrawal spreading out from the point of touch; the
whole body contracting; slow re-expansion over minutes; tentacles bending in
the flow.

**Sources:** no paper we are certain of. **Search terms:** "anemone retracting
tentacles", "Aiptasia contraction", "anemone time lapse feeding".

**Game:** backlog #625–#627.

### Hydra

**Look for:** spontaneous contraction into a ball, then slow elongation; the
same contractions repeating every few minutes; somersaulting and inching
locomotion; tentacles bringing prey to the mouth.

**Sources:** Dupre & Yuste (2017), "Non-overlapping neural networks in *Hydra
vulgaris*", *Current Biology* (imaging of the contraction bursts). **Search
terms:** "hydra contraction burst", "hydra somersault", "hydra eating daphnia",
"Passano McCullough hydra pacemaker".

**Game:** the tentacles sway on sines only
([coral.gd:805](../shaders-godot/godot-project/scripts/coral.gd:805)). Backlog
#612, #613.

---

## Published kinematics (#97)

The numbers a tuner needs, in one place. Each row says how sure we are and
which game constant it should calibrate. "Game at `5ad6dd3`" is read from the
code, and where it says *computed*, the value was worked out from the
constants by hand, not measured in a running game.

Confidence: **High** means a well-established result quoted in many sources.
**Medium** means the order of magnitude is right, but species, size and
conditions move it. **Low** means observational or hobby-level; measure it from
footage before relying on it.

### Fish

| Quantity | Published or observed value | Conf. | Source | Calibrates | Game at `5ad6dd3` |
|---|---|---|---|---|---|
| Tail-tip amplitude (peak to peak) | ≈ 0.2 L, roughly constant across speed once beating fast | High | Bainbridge 1958; Videler 1993 | Per-type `tail_amp` in the locomotion match ([fish.gd:7798](../shaders-godot/godot-project/scripts/fish.gd:7798)) × `_fin_tail_activity`; shader ripple `0.30 * s_ref` ([voxel_fauna_mm.gdshader:160](../shaders-godot/godot-project/shaders/voxel_fauna_mm.gdshader:160)) | `TailPivot` yaw 0.35 rad base (subcarangiform). Tip excursion not measured. Rough geometry (tip 1–2 voxels behind the pivot on a ~5.5-voxel body) gives about 0.1–0.3 L: an estimate only; needs #84 |
| Strouhal number St = f·A/U (A peak to peak) | 0.2–0.4 when cruising | High | Taylor, Nudds & Thomas 2003 | Beat rate and amplitude together; check with #88 | Not measured. Combining the stride and amplitude estimates gives St ≈ 0.15–0.25: low, meaning the tail beats too slowly for the speed (*computed, rough*) |
| Stride length (distance per beat) | ≈ 0.6–0.7 L in steady swimming, toward ~0.7–0.8 L at high beat rates | Medium–high | Bainbridge 1958; Videler 1993 | `speed_gain` and `base_rate` in `locomotion_tailbeat_rate` ([hydrodynamics.gd:257](../shaders-godot/godot-project/scripts/hydrodynamics.gd:257)) | Stride = 2π·U / (base + gain·U/L). Subcarangiform (2.5, 5.5): 0.79 L at 1 L/s, 0.93 L at 2 L/s, approaching 1.14 L (*computed, before mood and effort multipliers*) |
| Tail-beat frequency of small fish | Several Hz to 20 Hz or more in bursts; rises linearly with speed | Medium | Bainbridge 1958 | The 18 rad/s clamp in `tailbeat_rate` ([hydrodynamics.gd:254](../shaders-godot/godot-project/scripts/hydrodynamics.gd:254)); #333's visible cap of about fps/6 (10 Hz at 60 fps, 5 Hz at 30) | Base rate capped at 18 rad/s (2.9 Hz). The visible-tail multipliers (effort ≤ 1.28, mood ≤ 1.7, jitter ≤ 1.12) allow about 7 Hz, more during courtship |
| Body wavelength | Anguilliform ≈ 0.6–0.7 L; carangiform about 1 L or longer | Medium | Tytell & Lauder 2004; Videler 1993 | `body_phase`, `head_phase` per type ([fish.gd:7793](../shaders-godot/godot-project/scripts/fish.gd:7793)); #66 | Default `body_phase = π`: a standing counter-wag with no wavelength. Anguilliform −0.55π and −1.1π approximate travel |
| Amplitude envelope | Small at the head, largest at the tail | High (qualitative) | Videler 1993 | `head_amp` (0 except anguilliform); `tail_recoil_yaw` 0.07·effort ([hydrodynamics.gd:269](../shaders-godot/godot-project/scripts/hydrodynamics.gd:269)) | Head yaw comes from recoil and saccades only |
| C-start latency | Mauthner-initiated escapes start within roughly 5–10 ms. Larval zebrafish have short- and long-latency forms; the long form is several times slower | Medium | Eaton et al. 1977; Burgess & Granato 2007 | Where the startle is raised (`tick()`, 10 Hz); `signal_reaction_delay` (unwired, #163) | Startle is set in `tick()`, so latency is 0–100 ms depending on tick phase |
| C-start stage 1 duration | Of order 10–20 ms in small fish, longer in larger fish | Medium–high (order) | Domenici & Blake 1997; Eaton et al. 1977 | New C-start envelope (#145, #342); spec in the exposure sheets | No coil |
| C-start stage 2 duration | Comparable to or longer than stage 1 (tens of ms) | Medium | Domenici & Blake 1997 | Same envelope | — |
| C-start turn in stage 1 | Large and variable: tens of degrees to beyond 90°. Escape directions are spread, not fixed | Medium | Domenici & Blake 1997 | The C-start must bypass `inertial_turn` ([fish_life_bouts.gd:151](../shaders-godot/godot-project/scripts/fish_life_bouts.gd:151)) | Startle heading change is rate-limited by `inertial_turn` |
| Burst-and-coast | A few beats, then an unpowered glide that slows by drag | High (qualitative) | Weihs 1974; Videler & Weihs 1982 | `burst_glide_speed_mult`, the `coasting` branch of `integrate_speed` ([hydrodynamics.gd:102](../shaders-godot/godot-project/scripts/hydrodynamics.gd:102)), bout durations ([fish_life_bouts.gd:109](../shaders-godot/godot-project/scripts/fish_life_bouts.gd:109)) | Every species: dart 0.4–0.8 s, hover 1.2–3.8 s, cruise 2.5–8 s |
| Labriform pectoral beat frequency | Roughly 1–4 Hz across speeds | Medium | Webb 1973; Walker & Westneat 2002 | `pec_freq_base` ([fish.gd:7797](../shaders-godot/godot-project/scripts/fish.gd:7797), labriform [fish.gd:7825](../shaders-godot/godot-project/scripts/fish.gd:7825)) | Default 4.5 + 3.0·speed rad/s (0.72 Hz at rest); labriform 5.5 + 4.5·speed (0.88 Hz at rest) |
| Pectoral fin-tip path | A closed loop (rowing front to back, or flapping up and down) | Medium | Walker & Westneat 2002 | Pectoral writes ([fish.gd:8053](../shaders-godot/godot-project/scripts/fish.gd:8053)); #284 | One axis (`rotation.z`) only |
| Resting ventilation (opercular) rate | Small tropical fish: roughly 1–3 Hz, faster when hypoxic or warm | Low (strongly species- and temperature-dependent; measure) | Search "opercular beat rate" + species | `_gill_phase` rate ([fish.gd:8006](../shaders-godot/godot-project/scripts/fish.gd:8006)); `_breath_phase` ([fish.gd:7253](../shaders-godot/godot-project/scripts/fish.gd:7253)) | Gill pulse 2.2 × `_breath_load` rad/s = 0.14–0.77 Hz. Body bob 0.7–1.55 Hz on a separate clock |
| Suction-feeding timing | Mouth opening in tens of ms; many strikes over in well under 100 ms; buccal expansion before contact | Medium–high | Day et al. 2015; Wainwright et al. 2007 | `_trigger_mouth_gape` ([fish.gd:1739](../shaders-godot/godot-project/scripts/fish.gd:1739)); `_mouth_gape` decay 5.5/s ([fish.gd:6900](../shaders-godot/godot-project/scripts/fish.gd:6900)) | Gape follows the meal |
| Eye convergence before a strike | Both eyes converge at the start of the hunt (larval zebrafish) | High (larvae) | Bianco, Kampff & Engert 2011 | Eye pivots (#297, #299) | No eye pivots |
| Guppy sigmoid display | An S-posture held briefly with quivering, in repeated bouts | High (pattern); measure durations | Baerends et al. 1955; Houde 1997 | `_lb_display_t`, `sigmoid_env`, `_lb_quiver` ([fish_life_bouts.gd:237](../shaders-godot/godot-project/scripts/fish_life_bouts.gd:237), [fish_life_bouts.gd:276](../shaders-godot/godot-project/scripts/fish_life_bouts.gd:276)) | Hold 0.9–1.9 s; in 0.25 s, out 0.4 s; quiver 19 rad/s (3 Hz) |
| Corydoras air breathing | A fast dash to the surface and back; more frequent as dissolved O₂ falls | High (pattern); rates are in the paper | Kramer & McClure 1980 | `_aerial_timer` interval and trip length ([fish.gd:4310](../shaders-godot/godot-project/scripts/fish.gd:4310)) | A trip every 25–40 s lasting 2.0–3.5 s, whatever the oxygen level. Check against the paper's rates |
| Puffer cruising | Dorsal and anal fins, tail folded | High (pattern) | Gordon, Plaut & Kim 1996 | Locomotion type (#19, #331) | Classified ostraciiform (tail-driven) |

### Crustaceans

| Quantity | Published or observed value | Conf. | Source | Calibrates | Game at `5ad6dd3` |
|---|---|---|---|---|---|
| Caridean tail flip | Flexion lasts tens of ms in small shrimp; the full flip and re-extension about a tenth of a second; longer in larger animals. Use the paper's size-specific values for a 2–3 cm animal | Medium | Arnott, Neil & Ansell 1998 | `_escape_remaining` ([shrimp.gd:915](../shaders-godot/godot-project/scripts/shrimp.gd:915)) and the flip pitch ([shrimp.gd:1813](../shaders-godot/godot-project/scripts/shrimp.gd:1813)); #518 | 0.28 s of tail pitch `sin(_swim_phase) × (0.65 + 0.4·remaining)`. At 3 + 4·speed rad/s that is under half a cycle (*computed*), so the flex direction depends on the starting phase |
| Crayfish and lobster escape | Giant-fibre flips start within about 10 ms; slower non-giant flips steer and repeat | Medium | Wine & Krasne 1972; Edwards et al. 1999 | Same envelope, heavier timing (#549, #556) | Shared with shrimp; crabs never flip (`body_shape != "crab"`) |
| Pleopod beat | A back-to-front wave, neighbouring pairs a fraction of a cycle apart (about a quarter); a few Hz | Medium–low (krill) | Murphy et al. 2011 | `_pleopod_phase` rate ([shrimp.gd:1806](../shaders-godot/godot-project/scripts/shrimp.gd:1806)); #520 | 4.5 + 5.0·speed rad/s, computed and never drawn |
| Decapod leg coordination | Alternating sets; legs of one segment out of phase across the body | Medium | Blickhan & Full 1987; search "decapod alternating tetrapod gait" | Leg phase tables ([shrimp.gd:666](../shaders-godot/godot-project/scripts/shrimp.gd:666), [shrimp.gd:692](../shaders-godot/godot-project/scripts/shrimp.gd:692)); #516 | Shrimp: a three-leg wave per side, sides opposite. Crabs: a quarter-cycle rear-to-front wave (from reading the table, not measured) |
| Steps per distance | Measure from footage | Low | — | `steps_per_unit` per body plan ([shrimp.gd:1666](../shaders-godot/godot-project/scripts/shrimp.gd:1666)) | Shrimp 9.0, crab 7.5, mantis 4.5, lobster 3.2 cycles per unit |
| Mantis smasher strike | A few milliseconds; appendage tip speeds above 10 m/s | High | Patek, Korff & Caldwell 2004 | Raptorial arm pivot (#554) | Arms static ([shrimp.gd:585](../shaders-godot/godot-project/scripts/shrimp.gd:585)) |
| Snapping-shrimp claw | Closes in well under a millisecond; the snap is a collapsing cavitation bubble | High | Versluis et al. 2000 | `claw_asymmetry` claw (#533) | No snap |

### Snails, worms, microfauna and sessile animals

| Quantity | Published or observed value | Conf. | Source | Calibrates | Game at `5ad6dd3` |
|---|---|---|---|---|---|
| Snail crawl speed | Aquarium snails mostly around 1–3 mm/s, varying with species, size and surface | Low (backlog #581's hobby figures; measure in shell lengths per second) | Search "snail crawling speed mm/s" + species | `SPEED` ([snail.gd:77](../shaders-godot/godot-project/scripts/snail.gd:77)) × `crawl_speed` gene ([snail.gd:364](../shaders-godot/godot-project/scripts/snail.gd:364)); pulse gating ([snail.gd:820](../shaders-godot/godot-project/scripts/snail.gd:820)) | 0.11 u/s × 0.3–2.5, gated to 28–100% by the pulse (mean about 51%, *computed*). No world scale to convert to mm |
| Pedal wave direction | Pulmonates usually direct; many prosobranchs retrograde; some ditaxic; *Lymnaea* mostly ciliary | Medium (by group); Low (for any one aquarium species) | Lissmann 1945; Denny 1980 | A pedal-wave band on `GlassFootPad` (#565) | No waves. Whole-foot pulse at 1.35 rad/s (0.21 Hz); 2.2 when chasing food; 4.6 while rasping ([snail.gd:802](../shaders-godot/godot-project/scripts/snail.gd:802)) |
| Snail turning | A reversal takes several seconds | Low (observational, #266) | — | `FACING_TURN_RATE` ([snail.gd:286](../shaders-godot/godot-project/scripts/snail.gd:286)) | 5.5 rad/s: 180° in 0.57 s |
| Tentacle withdrawal | Fast in (a fraction of a second), slow out (seconds) | Low–medium | Ferguson & Benjamin 1991 for the order; measure the times | `EYE_RETRACT_RATE`, `EYE_EXTEND_RATE` ([snail.gd:252](../shaders-godot/godot-project/scripts/snail.gd:252)) | 95% in 0.15 s, back out over 1.5 s |
| Shell clamp | Fast down, slow up | Low | Measure | `TUCK_IN_RATE`, `TUCK_OUT_RATE` ([snail.gd:258](../shaders-godot/godot-project/scripts/snail.gd:258)) | 95% in 0.17 s, back over 1.4 s |
| Righting | Several seconds, often several attempts | Low | Measure | `RIGHTING_RATE` ([snail.gd:289](../shaders-godot/godot-project/scripts/snail.gd:289)) | A 1.9 s slerp |
| Tubifex tail waving | Faster and more vigorous as O₂ falls | High (pattern); Low (rates) | Search terms above | `WRIGGLE_FREQ`, `WRIGGLE_AMP` ([tubifex_patch.gd:20](../shaders-godot/godot-project/scripts/tubifex_patch.gd:20)) | 5.5 rad/s and 0.024, whatever the oxygen level |
| Oligochaete rapid withdrawal | A giant-fibre reflex; very fast | Medium–low | Drewes & Fourtner 1989 | `graze_one` hide ([tubifex_patch.gd:102](../shaders-godot/godot-project/scripts/tubifex_patch.gd:102)); #606 | One worm hidden in one frame |
| Daphnia hop-and-sink | A fast antennal stroke and a passive sink, several hops per second (#638 says 2–4) | Medium (pattern); Low (rate) | Search terms above | Morph-1 rise and sink ([microfauna_swarm.gd:184](../shaders-godot/godot-project/scripts/microfauna_swarm.gd:184)); `BOB_SPEED` ([microfauna_swarm.gd:20](../shaders-godot/godot-project/scripts/microfauna_swarm.gd:20)) | Rises at 0.042 u/s while `sin(bob·1.25) > 0.55`, otherwise sinks at 0.026: one cycle per 3.6 s, about 0.28 per second (*computed*) |
| Copepod escape jump | Individual jumps last milliseconds to tens of ms, at hundreds of body lengths per second, often in series | High (order) | Buskey, Lenz & Hartline 2002; Kiørboe et al. 2010 | Morph-0 hop ([microfauna_swarm.gd:163](../shaders-godot/godot-project/scripts/microfauna_swarm.gd:163), [microfauna_swarm.gd:170](../shaders-godot/godot-project/scripts/microfauna_swarm.gd:170)) | Hops of 0.11–0.14 s, with 0.8–3.8 s cooldowns. The swarm steps at a fixed 30 Hz (`STEP`, [microfauna_swarm.gd:28](../shaders-godot/godot-project/scripts/microfauna_swarm.gd:28)) |
| Bivalve valve closure | Shuts quickly when disturbed, reopens slowly | Medium (pattern) | Search "valvometry" | `_open_amount` rate ([clam.gd:230](../shaders-godot/godot-project/scripts/clam.gd:230)); mode durations ([clam.gd:66](../shaders-godot/godot-project/scripts/clam.gd:66)) | Rate 4.0 both ways (95% in about 0.75 s); REST 4.5 s, OPENING 1.0, FEEDING 6.0, CLOSING 0.8 |
| Hydra contraction | Spontaneous whole-body contraction bursts, repeating over minutes | Medium | Dupre & Yuste 2017 | Hydra branch of `coral.gd` ([coral.gd:805](../shaders-godot/godot-project/scripts/coral.gd:805)); #613 | Tentacle sines only |

**What the table already says.** The fish tail beats too slowly for its speed:
stride is near 1 L per beat against a published 0.65 L, and Strouhal is at or
below the bottom of the band. Snails turn about ten times too fast, and daphnia
hop about ten times too slowly. Each of these is a constant change once the
metric exists (#88, #101) to confirm it.
