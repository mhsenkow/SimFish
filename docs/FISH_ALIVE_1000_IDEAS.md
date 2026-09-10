# Dumb Little Fish — 1000 Ways to Feel Alive

*Drafted 2026-09-10. Director's mega-backlog for body-first aliveness.*

The brief: you made a **dumb little fish**. Give it a life and a world.
A thousand points that make it feel alive **even if it isn't** — even with
Guardian voice off, LLM declined, thoughts muted. Motion, posture, breath,
feeding theater, fear arcs, schools, wear, death, and a tank that answers back.

This is **not** another sentience architecture doc. Do **not** rebuild
`FishMind`, global workspace, embedded LLM, or conversation stacks.
Prefer body-readable loops in [`fish.gd`](../shaders-godot/godot-project/scripts/fish.gd),
[`motion_school.gd`](../shaders-godot/godot-project/scripts/motion_school.gd),
[`motion_wave.gd`](../shaders-godot/godot-project/scripts/motion_wave.gd),
[`motion_field.gd`](../shaders-godot/godot-project/scripts/motion_field.gd),
[`fish_locomotion.gd`](../shaders-godot/godot-project/scripts/fish_locomotion.gd),
[`creature_naming.gd`](../shaders-godot/godot-project/scripts/creature_naming.gd),
[`fish_signals.gd`](../shaders-godot/godot-project/scripts/fish_signals.gd),
[`world.gd`](../shaders-godot/godot-project/scripts/world.gd),
[`sim_driver.gd`](../shaders-godot/godot-project/scripts/sim_driver.gd),
[`shrimp.gd`](../shaders-godot/godot-project/scripts/shrimp.gd),
[`snail.gd`](../shaders-godot/godot-project/scripts/snail.gd).

See also [SENTIENT_FISH_IDEAS.md](SENTIENT_FISH_IDEAS.md) (inner life — don't fork),
[LIVING_MOTION_IDEAS.md](LIVING_MOTION_IDEAS.md) (murmuration/school),
[PLANT_NATURALISM_1000_IDEAS.md](PLANT_NATURALISM_1000_IDEAS.md),
[COMMS_AI_1000_IDEAS.md](COMMS_AI_1000_IDEAS.md),
[PLAYER_WISH_1000_IDEAS.md](PLAYER_WISH_1000_IDEAS.md), GOALS A/H9.
**Much of the substrate already ships** — this doc inventories body tells,
fills thin spots (idle continuity, posture matrix, fin wear, world answers),
and forbids inventing a second brain.

**Format:** checkboxes; S–M unless **(L)**. One idea → one commit → smoke.
Voice-off must still pass the 'alive' test.

## If this doc only does ten (do these first)

1. **#1 Continuous micro-idle** — shipped (`FishAlive.micro_idle_y` / velocity floor).
2. **#41 Personality → posture matrix** — shipped (`posture_y_offset` / `posture_sep_mult`).
3. **#121 Breath as continuous tell** — shipped (always-on breath bob).
4. **#641 Fin nicks render path** — shipped (`apply_fin_nicks_visual` on tail).
5. **#481 Home loiter magnet** — shipped (`home_soft_attract` / loiter mult).
6. **#521 Fear recovery arc** — shipped (freeze→flee→hide→peek→recover).
7. **#761 Species habit kit** — shipped (`FishAlive.habit_kit` / `apply_habit_kit`).
8. **#841 Lateral-line flinch** — shipped (`lateral_line_flinch`).
9. **#881 World-answer table** — shipped (`world_answer` dart/gulp/sift/hide).
10. **#999/#1000 Miracle budget + thesis** — shipped (`smoke_fish_alive.gd`).

**Sequencing:** 1 → 121 → 41 → 641 → 481 → 521, then habit/lateral/world/wonder.
Ignore mind_* files unless a body tell already hooks them.

**Foundations shipped 2026-09-10:** #1, #41, #121, #481, #521, #641, #761, #841, #881, #999/#1000 (`fish_alive.gd` + fish.gd wiring; `smoke_fish_alive.gd`).

---

## Section — Never truly still — continuous micro-life (1–40)

*Grounding: fish.gd idle fidgets (`_fidget_kind`), gill flush, breath hover, locomotion pivots; LIVING_MOTION_IDEAS.*

- [x] **1. Continuous micro-idle service. A fish at rest still breathes, fin-flicks, and drifts 2–4 mm — never a frozen MultiMesh. **(L)**
- [ ] **2. Breath-coupled bob. `_breath_load` modulates a 1–2 mm vertical hover so still water still moves.**
- [ ] **3. Pectoral idle fan. Pecs alternate tiny sculls while body rests — station-keeping you can feel.**
- [ ] **4. Tail tip whisper. Caudal tip oscillates at low amplitude during REST so the silhouette never locks.**
- [ ] **5. Asymmetric fidget seed. Use `asymmetry`/id hash so two idle fish never sync fidgets.**
- [ ] **6. Fidget budget by calm. High `calm` → rarer fidgets; low calm → restless micro-turns.**
- [ ] **7. Shimmy only when watched. Soften idle intensity off-camera; keep full when followed/PiP.**
- [ ] **8. Yawn-gape cooldown honesty. Existing yawn fidget gets a readable 0.4 s mouth open, not a blink.**
- [ ] **9. Substrate-flash for shuffle only. Bottom-dwellers flash sand; midwater never does it mid-column.**
- [ ] **10. Micro-orient to nearest neighbor. Idle fish occasionally yaw 8° toward a schoolmate then settle.**
- [ ] **11. Idle curiosity glance. Every 12–20 s, a 0.3 s gaze toward a novel region without leaving REST.**
- [ ] **12. Never-zero velocity floor. Clamp cruise speed soft-floor so physics never parks at exact 0.**
- [ ] **13. Gill cover flutter cadence. Visible operculum pulse rate scales with `_breath_load`.**
- [ ] **14. Fin soft-collision. Idle fish that brush plants get a 1-frame recoil twitch.**
- [ ] **15. Surface film kiss. Top-dwellers occasionally kiss surface film without full gulp.**
- [ ] **16. Bottom sit with pecs. Shuffle species plant pecs in sand and hold — real resting posture.**
- [ ] **17. Hover species station drift. Hover pattern orbits a 5 cm ellipsoid, not a point.**
- [ ] **18. Sleep micro-twitch already exists — raise night visibility slightly when player is watching.**
- [ ] **19. Post-feed loaf. After a meal, 8–15 s of heavy idle before cruise resumes.**
- [ ] **20. Stress still fidgets. Even high-stress hide includes rapid gill + tiny shakes — not statue fear.**
- [ ] **21. Dual-rate idle. Slow body sway (0.2 Hz) + fast fin (3 Hz) layered — biological, not noise.**
- [ ] **22. Idle facing preference. Persist a preferred yaw per fish so loitering has character.**
- [ ] **23. Mirror-avoid idle. Near glass, idle orientation biases slightly away after habituation.**
- [ ] **24. Plant-lean rest. Fish resting in cover lean 5–10° into the leaf mass.**
- [ ] **25. Open-water rest rarer. Timid fish almost never idle in empty midwater.**
- [ ] **26. Bold open loaf. Bold fish will idle in the open after feeding — personality as posture.**
- [ ] **27. Energy-gated fidget. Low energy → fewer, larger sighs; high energy → tiny busy flicks.**
- [ ] **28. Mode-exit settle. Leaving FLEE/COURT always passes through 0.5 s settle fidget.**
- [ ] **29. Camera-aware idle amp. Immersive/focus mode amplifies idle tells slightly.**
- [ ] **30. Reduced-motion idle. Accessibility: keep breath bob, kill shimmy/yawn spam.**
- [ ] **31. Idle LOD. Far fish: breath bob only; near: full fidget kit.**
- [ ] **32. Fidget exclusivity. One fidget at a time — no yawn+shimmy stack.**
- [ ] **33. School idle phase offset. Schoolmates' fidgets desync by lead_score.**
- [ ] **34. Senescence slower idle. Old fish idle heavier, longer pauses between flicks.**
- [ ] **35. Fry busy idle. Fry almost never 'rest quiet' — constant micro-chase of nothing.**
- [ ] **36. Idle soundless cue. Optional tiny water tick when pec sculls near mic (opt-in).**
- [ ] **37. Document idle kinds. Enumerate fidget kinds in one comment block for designers.**
- [ ] **38. Idle debug overlay. Dev-only: show fidget kind + breath load on follow.**
- [ ] **39. Idle vs deliberation. Delib pause uses a distinct hold posture, not generic idle.**
- [ ] **40. Smoke: never-still. Assert N fish over 3 s never all have velocity≈0 simultaneously.**

## Section — Posture & personality as body language (41–80)

*Grounding: personality traits (boldness/curiosity/sociability/gluttony/calm); Mode overlays; stress hide.*

- [x] **41. Personality → posture matrix. Map bold/timid to hang angle, school distance, open-water time. **(L)**
- [ ] **42. Timid crouch. Low boldness lowers body 5–8% toward substrate in open water.**
- [ ] **43. Bold high-ride. High boldness rides slightly higher in the column than preferred_y.**
- [ ] **44. Curious tilt-up. High curiosity pitches nose up toward surface interest more often.**
- [ ] **45. Glutton lean-forward. High gluttony biases pitch toward food scent / surface feed.**
- [ ] **46. Calm parallel. High calm keeps body more level; low calm adds roll jitter.**
- [ ] **47. Sociability flank. High sociability biases idle yaw toward nearest conspecific.**
- [ ] **48. Stress pallor already ships — couple it to posture: pale + lower + tighter fins.**
- [ ] **49. Fin clamp under stress. Soft-clamp dorsal/anal when stress > threshold.**
- [ ] **50. Fin flare under court/threat display. Distinct from clamp — readable opposite.**
- [ ] **51. Rank posture. Higher rank_within_species gets fractionally larger personal space bubble.**
- [ ] **52. Submit curl. On SUBMIT signal, brief downward curl + slowed wag.**
- [ ] **53. Leader loft. Transient leaders (lead_score) swim 3–5% higher than school mean.**
- [ ] **54. Follower tuck. Low lead_score fish tuck slightly behind and below leader.**
- [ ] **55. Hide posture commit. Stress-hide uses a true tucked pose, not just a target point.**
- [ ] **56. Inspect hover pitch. Investigation tilts body toward object, not just steering.**
- [ ] **57. Flee body stretch. FLEE elongates silhouette briefly (speed lines via stretch).**
- [ ] **58. Rest banana. Sleep tilt already exists — add species variance (some hang, some sit).**
- [ ] **59. Territory side-display. Chase uses lateral presentation, not only pursuit vector.**
- [ ] **60. Hunger hollow. High hunger slightly thins belly scale (shader), satiation rounds it.**
- [ ] **61. Contentment loosen. High mood loosens fin clamp and slows turn rate.**
- [ ] **62. Arousal sharpness. High arousal = sharper turns, shorter coast.**
- [ ] **63. Vigilance head-up. High vigilance holds head slightly above body line.**
- [ ] **64. Spooked freeze then micro. Spooked starts with 0.15 s freeze before flee.**
- [ ] **65. Familiarity ease. High familiarity-with-player softens glass-startle posture.**
- [ ] **66. Grudge stiff. Near a grudged fish, body stiffens and school gap widens.**
- [ ] **67. Bond parallel swim. Bonded pair prefer parallel headings when cruising.**
- [ ] **68. Pair drift distance. Bonds maintain a soft preferred distance band.**
- [ ] **69. Epithet posture hint. 'the Bold' fish actually uses bold posture knobs harder.**
- [ ] **70. Dimorphism posture. Males flare more; females keep fuller body silhouette in court.**
- [ ] **71. Gestation lumber. Pregnant livebearers pitch and turn heavier — visible mass.**
- [ ] **72. Mouthbrood cheek. Mouthbrooders hold a fuller jaw silhouette while brooding.**
- [ ] **73. Senescence droop. Old fish dorsal softens; tip of fin droops slightly.**
- [ ] **74. Fry proportion. Fry head-heavy silhouette already — exaggerate motion clumsiness.**
- [ ] **75. Posture lerp. Never snap posture; 0.2–0.5 s blend between posture targets.**
- [ ] **76. Posture vs Mode table. Document which postures each Mode may use.**
- [ ] **77. One posture driver. Single service writes posture offsets so modules don't fight.**
- [ ] **78. Follow-cam posture readable. PiP framing prefers showing posture tells.**
- [ ] **79. Photo-mode posture freeze-frame. Capture holds a mid-fidget, not T-pose.**
- [ ] **80. Smoke: posture matrix. Bold vs timid sample differ in mean height / school gap.**

## Section — Eyes, gaze, and noticing (81–120)

*Grounding: `_eye_look`, `_blink_remaining`, `_gaze_yaw`, glance-at-player, novelty pause, interest target.*

- [ ] **81. Gaze stickiness. Eyes linger 0.2 s after a target leaves the cone — noticing residue.**
- [ ] **82. Blink rate by stress. Stress raises blink frequency; calm slows it.**
- [ ] **83. Independent eye lag. Eyes track interest with slight lag behind body yaw.**
- [ ] **84. Blink before turn. A blink often precedes a large reorient — animal tell.**
- [ ] **85. Glance cone honesty. Player glance only if player is in forward FOV.**
- [ ] **86. Occluded interest. Interest targets behind dense plants fail until fish rounds them.**
- [ ] **87. Double-take. Rare second glance at the same novelty within 3 s.**
- [ ] **88. School gaze contagion polish. If neighbor looks, 20% chance to look same way.**
- [ ] **89. Food lock eyes. FORAGE locks eyes to flake more tightly than cruise.**
- [ ] **90. Threat lock. FLEE eyes lock predator; body may lag one frame.**
- [ ] **91. Mate gaze. COURT includes mutual eye-line moments.**
- [ ] **92. Sleep eye soft-close. Asleep eyes half-lid (shader), not open stare.**
- [ ] **93. Dark pupil widen. Low light widens pupil proxy on eye voxels.**
- [ ] **94. Startle eye flash. Startle briefly saturates eye accent.**
- [ ] **95. Follow-player eye priority. When followed, eyes sometimes track camera gently.**
- [ ] **96. Ignore behind. Rear hemisphere targets need lateral-line or turn to see.**
- [ ] **97. Saccade snaps. Gaze jumps in small steps, not continuous servo.**
- [ ] **98. Interest timeout fade. Eyes return to neutral over 0.4 s, not pop.**
- [ ] **99. Novelty eye pop. First visit to a region gets a longer stare.**
- [ ] **100. Mirror self-check. Near glass, brief self-orient then habituate.**
- [ ] **101. Cleaning-station eye. While cleaned, eyes roll slightly / idle.**
- [ ] **102. Predator stare-down. Rare bold fish locks eyes with predator before fleeing.**
- [ ] **103. Fry eye proportion. Fry eyes relatively larger — already; motion exaggerate tracking.**
- [ ] **104. Senile slow track. Old fish eye tracking lags more.**
- [ ] **105. Blink asymmetry. Occasional one-eye blink for organic feel.**
- [ ] **106. Eye contact with keeper. Sustained gaze when player face/webcam optional — soft.**
- [ ] **107. No eye spam. Cap gaze retargets to 3/s.**
- [ ] **108. Debug gaze ray. Dev overlay for look target.**
- [ ] **109. Species eye placement. Eye height on skull differs by body_shape.**
- [ ] **110. Eye wetness specular. Tiny specular tick on blink open.**
- [ ] **111. Closed-eye death. Dying eyes settle closed/half.**
- [ ] **112. Courtship side-eye. Lateral display includes eye toward mate.**
- [ ] **113. Food miss look-down. Missed flake → look down then reacquire.**
- [ ] **114. Alarm look-up. ALARM signal biases eyes upward briefly.**
- [ ] **115. Plant peep. From cover, only eyes/nose peek then retreat.**
- [ ] **116. Hover stare. Hover species hold stare longer than dart species.**
- [ ] **117. School leader look-ahead. Leaders look farther along path.**
- [ ] **118. Follower look-to-leader. Followers glance leader more than world.**
- [ ] **119. Blind side honesty. Monocular bias: prefer targets on last-seen side.**
- [ ] **120. Smoke: gaze cone. Target behind fish not acquired until turn.**

## Section — Breath, gills, and oxygen theater (121–160)

*Grounding: `SURFACE_GULP_O2`, labyrinth, `_breath_load`, `_gill_flush_t`, dissolved_o2 coupling.*

- [x] **121. Breath as continuous tell. Operculum rate always on; scales with O2 and effort. **(L)**
- [ ] **122. Surface gulp choreography. Rise → break → mouth open → sink with bubbles — one readable arc.**
- [ ] **123. Labyrinth air gulp distinct. Labyrinth species gulp differently from O2-panic gulp.**
- [ ] **124. Pre-gulp restless. 1–2 s of upward bias before committing to surface.**
- [ ] **125. Post-gulp relief. Visible gill ease + mood bump after successful gulp.**
- [ ] **126. Gulp contagion. Nearby fish may follow to surface (social breathing).**
- [ ] **127. Night gulp rarer. Lower metabolism at night unless O2 critical.**
- [ ] **128. Plant O2 relief tell. High plant biomass + O2: slower gills, higher hang.**
- [ ] **129. Nitrite cough. Existing gill flush on chem stress — make cadence readable.**
- [ ] **130. Chase breath debt. After FLEE burst, elevated breath for 3–5 s.**
- [ ] **131. Feed breath hold. Brief breath pause while mouth-gaping on flake.**
- [ ] **132. Rest breath deep. REST uses slower, deeper gill strokes.**
- [ ] **133. Fry rapid breath. Fry gill rate higher — tiny engine look.**
- [ ] **134. Senescence weak gulp. Old fish gulp less efficiently — more trips.**
- [ ] **135. Bubble trail after gulp. 1–3 voxels of bubble rise — world answers.**
- [ ] **136. Surface ripples on gulp. Couple to spawn_burst_ripple at snout.**
- [ ] **137. Hypoxia school rise. Whole school drifts up as O2 falls — communal tell.**
- [ ] **138. Bold gulps later. Bold fish delay surface trip vs timid.**
- [ ] **139. Timid gulp from cover. Timid rise along plant wall, not open column.**
- [ ] **140. Gulp fail thrash. If blocked by lid/low water, thrash tell (rare).**
- [ ] **141. Aerial excursion polish. `_aerial_timer` trips read as purposeful leaps.**
- [ ] **142. Breath LOD. Far: rate only; near: cover motion.**
- [ ] **143. Breath vs speech. Voice off doesn't mute breath tells.**
- [ ] **144. Acclimation pant. New tank arrivals pant harder for N minutes.**
- [ ] **145. Relief pulse sync. Chem relief pulse slows breath visibly.**
- [ ] **146. Dorsal break on gulp. Dorsal briefly breaks surface on big gulp.**
- [ ] **147. Mouth open duration by hunger. Hungrier = longer gape at surface feed.**
- [ ] **148. No false gulp. Don't gulp when O2 is fine — avoid noisy tells.**
- [ ] **149. Gulp cooldown species. Species-specific min interval.**
- [ ] **150. Debug O2→breath meter. Dev follow overlay.**
- [ ] **151. Breath sound opt-in. Soft tick only if audio enabled.**
- [ ] **152. Filter outflow preference. Fish may gulp near high-O2 outflow if present.**
- [ ] **153. Crowd hypoxia. Dense school locally raises breath rate.**
- [ ] **154. Alone calm breath. Isolated fish in good water breathes easy — solitude peace.**
- [ ] **155. Post-water-change sigh. After care water change, tank-wide breath ease beat.**
- [ ] **156. Ammonia eye-burn proxy. High ammonia → more blink + gill flush.**
- [ ] **157. Clarity and breath. Murk doesn't change O2 but raises vigilance breath slightly.**
- [ ] **158. Document gulp thresholds. One table for SURFACE_GULP_O2 vs species.**
- [ ] **159. Gulp vs court conflict. Courtship can delay gulp briefly — tension.**
- [ ] **160. Smoke: hypoxia rise. Drop O2 → mean preferred hang height rises.**

## Section — Feeding as theater (161–200)

*Grounding: FORAGE, mouth gape, food glow, waste sift, herbivory nibble, meal age revival.*

- [ ] **161. Flake approach deceleration. Slow last 10 cm so feeding isn't a teleport snatch.**
- [ ] **162. Miss and retry. Occasional miss + loop-back — competence theater.**
- [ ] **163. Spit and rechew. Rare spit of oversized flake then re-take.**
- [ ] **164. Food type preference tell. Pellets vs flakes: different approach angles.**
- [ ] **165. Surface film feed. Top fish skim film; body nearly horizontal.**
- [ ] **166. Midwater intercept. Arc approach from below — classic aquarium shot.**
- [ ] **167. Bottom sift cloud. Shuffle species kick visible detritus when foraging.**
- [ ] **168. Waste vs food discrimination. Clear body language difference in approach speed.**
- [ ] **169. Herbivory nibble cadence. Plant bites are rhythmic, not one-shot deletes.**
- [ ] **170. Algae scrape posture. Body tilts against glass/hardscape while scraping.**
- [ ] **171. Competition flare. Two fish at one flake: brief lateral flare then winner.**
- [ ] **172. Yield to rank. Lower rank waits a beat before taking contested food.**
- [ ] **173. Glutton overshoot. High gluttony takes extra bites then sluggish loaf.**
- [ ] **174. Satiety cruise. After meals_eaten bump, wider lazy turns.**
- [ ] **175. Food glow honesty. `_food_glow` only while digesting, fades smoothly.**
- [ ] **176. Mouth gape sync to bite. Gape peaks on contact frame.**
- [ ] **177. Chew bubbles. Tiny mouth bubbles after bite (rare).**
- [ ] **178. Feed heatmap loiter. Return to cells that paid off — visible routes.**
- [ ] **179. Ignore old flake. Stale food approached slower / abandoned.**
- [ ] **180. Keeper-hand association. Food near glass after player feed → approach glass.**
- [ ] **181. Startle mid-feed. Glass tap drops flake chase — priorities readable.**
- [ ] **182. School feed boil. School feeding creates local motion boil + ripples.**
- [ ] **183. Lone shy feed. Timid waits until others feed first.**
- [ ] **184. Bold first strike. Bold takes first flake more often.**
- [ ] **185. Night scavenging. Nocturnal shuffle feeds more at lights-out.**
- [ ] **186. Fry food scramble. Fry zig-zag chaos around microfood.**
- [ ] **187. Parent feed restraint. Mouthbrooders feed less / carefully while holding.**
- [ ] **188. Post-fast frenzy. After hunger high, first feed is frantic then settles.**
- [ ] **189. Leftover courtesy. Some fish leave crumbs — shrimp opportunity.**
- [ ] **190. Filter-outflow drift feed. Chase food on current lines.**
- [ ] **191. Plant-leaf buffet. Grazers work a leaf systematically left-to-right.**
- [ ] **192. Glass-fed expectation. After many top-feeds, fish wait at surface at session start.**
- [ ] **193. Feed dock teach. First feed always succeeds within 2 s (player-wish cross).**
- [ ] **194. No omniscient snatch. Prefer scent/vision gated approaches when available.**
- [ ] **195. Forage mode exit clear. Leave FORAGE with a visible swallow + turn-away.**
- [ ] **196. Multi-flake attention. Attend one flake at a time — tunnel vision.**
- [ ] **197. Food mirror confusion. Rare glance at glass reflection of flake.**
- [ ] **198. Debug forage target. Dev show current food id.**
- [ ] **199. Document food subtypes. Approach table per WasteParticle subtype.**
- [ ] **200. Smoke: sift cloud. Shuffle forage raises local suspended waste briefly.**

## Section — Glass, keeper, and the outside world (201–240)

*Grounding: player glass glance, habituation, glass-tap ripples, FishSparkBehavior, familiarity.*

- [ ] **201. Glass as weather. Player presence is a climate the fish dress for.**
- [ ] **202. Approach-then-habituate curve. First sessions: strong glance; later: soft.**
- [ ] **203. Bold greeter. High boldness approaches glass when player returns.**
- [ ] **204. Timid retreat-on-face. Timid backs to plants when face appears suddenly.**
- [ ] **205. Tap graded response. Soft vs hard tap (if detectable) different startle.**
- [ ] **206. Tap habituation memory. Existing spark habituation — persist across short absences.**
- [ ] **207. Finger-follow. Optional: fish track a slow finger along glass (curiosity).**
- [ ] **208. Ignore frantic tapping. Over-tap → fish ignore (learned helplessness soft).**
- [ ] **209. Return welcome body. After away, fish gather mid/front briefly — no speech required.**
- [ ] **210. Feed-hand Pavlov. Rise to glass when feed dock opens — conditioned.**
- [ ] **211. Camera loom. Fast camera push = mild startle; slow orbit = calm.**
- [ ] **212. PiP intimacy. Followed fish glances camera more — relationship.**
- [ ] **213. Photo hush body. During photo letterbox, fish calm slightly (hush).**
- [ ] **214. Immersive trust. Immersive mode reduces glass vigilance over time.**
- [ ] **215. Knock from room. Rare external thump (optional) → whole tank flinch.**
- [ ] **216. Night keeper soft. Night glass approach less startle if lights dim.**
- [ ] **217. Multiple keepers? Single familiarity channel is fine — document it.**
- [ ] **218. No guilt stare. Fish never 'accuse' via posture after neglect — care not shame.**
- [ ] **219. Relief on care. Water change → collective ease posture within seconds.**
- [ ] **220. Filter rinse curiosity. Fish inspect outflow change briefly.**
- [ ] **221. New decor inspect. Hardscape add → novelty pause tour.**
- [ ] **222. Plant trim startle then explore. After scape edit, re-map routes.**
- [ ] **223. Lid open light change. Sudden light → blink + dive (if lid modeled).**
- [ ] **224. Phone flash hush. Screen brightness spike soft-startles once.**
- [ ] **225. Voice-off still body. Quiet mode keeps body tells; only text hushes.**
- [ ] **226. Familiarity decay slow. Days away reset glance intensity partially.**
- [ ] **227. Session clock ease. First 30 s of session: higher vigilance then settle.**
- [ ] **228. Children-hand chaos. Fast many taps → school to back glass.**
- [ ] **229. Gentle orbit reward. Calm camera → fish resume open-water sooner.**
- [ ] **230. Debug familiarity. Show habituated['player'] on follow.**
- [ ] **231. Glass thickness feel. Near-glass swimming slows / slides — hydro near wall.**
- [ ] **232. Corner trap fear. Timid avoid corners when spooked (escape psychology).**
- [ ] **233. Front-glass stage. School prefers front third when keeper present + calm.**
- [ ] **234. Hide when loom. Large dark shape at glass → plant hide.**
- [ ] **235. Curiosity bump to new UI. First Care dock use → fish glance down/front.**
- [ ] **236. No OS notif startle. External toasts don't spike fish (comms cross).**
- [ ] **237. Document glass API. One function for 'keeper salience'.**
- [ ] **238. Keeper salience LOD. Far camera reduces glass response.**
- [ ] **239. Return XOR voice. Body welcome doesn't need welcome_back toast (comms).**
- [ ] **240. Smoke: habituation. N taps → startle magnitude falls.**

## Section — Day, night, and light on the body (241–280)

*Grounding: `sim.daylight()`, night REST/sleep tilt, nocturnal shuffle, bioluminescence.*

- [ ] **241. Dawn stretch. At lights-on, fish uncurl from sleep with a long glide.**
- [ ] **242. Dusk gather. Pre-night, school tightens and drifts to sleep nooks.**
- [ ] **243. Sleep nook fidelity. `_sleep_nook` persists night to night per fish.**
- [ ] **244. Sleep tilt species kit. Some hang, some sit, some wedge in plants.**
- [ ] **245. Night twitch honesty. Rare twitches only — not disco.**
- [ ] **246. Nocturnal shuffle awaken. Shuffle species become primary night actors.**
- [ ] **247. Diurnal school sleep. School species nearly still at night.**
- [ ] **248. Moonlight activity. If night not pitch-black, partial activity.**
- [ ] **249. Biolum soft pulse. Biolum species pulse with arousal at night.**
- [ ] **250. Light shock dive. Sudden full bright → dive then recover.**
- [ ] **251. Dim acuity. Sight range shortens in low light — already thesis; enforce.**
- [ ] **252. Siesta mid-day. Optional low-activity band for some tropicals.**
- [ ] **253. Color day/night. Night desaturates body slightly; day restores.**
- [ ] **254. Dawn feed anticipation. Surface waiters gather if usually fed mornings.**
- [ ] **255. Photoperiod personality. Bold wakes earlier; timid later.**
- [ ] **256. Shadow pass. Hand shadow over tank → flinch.**
- [ ] **257. Lamp move re-map. Moving light retargets preferred hang over hours.**
- [ ] **258. Algae light link. Greener glass days → grazers busier (world).**
- [ ] **259. Night keeper red-light soft. If night UI, less startle.**
- [ ] **260. Sleep debt body. Rest debt → yawns + earlier sleep next night.**
- [ ] **261. Courtship day-gated. Most dances prefer daylight.**
- [ ] **262. Night spawn rare. Some species exception — flag in genome.**
- [ ] **263. Fry night huddle. Fry cluster tighter at night.**
- [ ] **264. Predator night hunt. Predators slightly more active in dusk.**
- [ ] **265. Light flicker storm. Rare flicker → vigilance spike.**
- [ ] **266. Cloud day. Soft ambient dim day → calmer cruise.**
- [ ] **267. UV/blue hour tint. Body specular shifts with skylight color.**
- [ ] **268. Document daylight curve. One chart for activity mult.**
- [ ] **269. Sleep interrupt feed. Night feed wakes local fish briefly.**
- [ ] **270. True still only in deep sleep. Deep sleep allows nearer-zero motion.**
- [ ] **271. Roost hierarchy. Preferred sleep spots contested softly by rank.**
- [ ] **272. Alone sleeper. Timid may sleep apart from school.**
- [ ] **273. Bold open roost. Bold sleeps more exposed.**
- [ ] **274. Morning school reform. Fission overnight, fusion at dawn.**
- [ ] **275. Night snail freedom. Snails more active when fish sleep (neighbor).**
- [ ] **276. Debug day phase. Overlay dawn/day/dusk/night.**
- [ ] **277. No false night. Time scale extremes still keep readable phases.**
- [ ] **278. Battery saver night simplify. Fewer twitches, keep roosts.**
- [ ] **279. Photo at dusk. Encourage golden hour framing — soft gather.**
- [ ] **280. Smoke: dawn uncurl. At day flip, sleep_tilt declines across population.**

## Section — Chemistry you can see on them (281–320)

*Grounding: ammonia/nitrite stress, chem pallor, acclimation, relief pulse, water clarity acuity.*

- [ ] **281. Pallor is the headline chem tell. Keep it stronger than any toast.**
- [ ] **282. Ammonia flush cadence. Gill flush rate maps to ppm bands.**
- [ ] **283. Nitrite brown-blood proxy. Slight chocolate gill tint under nitrite.**
- [ ] **284. Nitrate long drab. Chronic nitrate → duller colors over days.**
- [ ] **285. pH itch. Extreme pH → scratch-on-plant / glass rub behavior.**
- [ ] **286. Temp lethargy. Cold → slow wag; hot → rapid breath + surface.**
- [ ] **287. Acclimation bag feel. New arrivals stay pale + lower for minutes.**
- [ ] **288. Relief bloom. Chem improve → color returns over minutes, not instant.**
- [ ] **289. Clarity fog behavior. Murk → closer schooling + shorter strikes.**
- [ ] **290. Tannin calm tint. Soft tea water → slightly calmer motion.**
- [ ] **291. Salt creep (if brackish). Behavior shift flags for future species.**
- [ ] **292. Copper/med caution. If meds ever ship, lethargy tell reserved.**
- [ ] **293. Planted vs sterile body. High plants → better color hold.**
- [ ] **294. Crowd waste stress. Dense bioload → more pallor variance.**
- [ ] **295. After crash survivors. Post-crash fish stay vigilant longer.**
- [ ] **296. Chem ignore when fleeing. FLEE suppresses itch behaviors briefly.**
- [ ] **297. Curiosity down when sick. Low mood + chem → less novelty tours.**
- [ ] **298. Feed refusal. Bad chem → approach food then abort.**
- [ ] **299. Spawn cancel. Poor water aborts COURT mid-dance.**
- [ ] **300. Hide more in bad water. Stress-hide threshold lowers.**
- [ ] **301. Surface crowd in hypoxia only — don't misuse for other chem.**
- [ ] **302. Debug chem body. Overlay pallor + flush drivers.**
- [ ] **303. Species hardiness. Some shrug ammonia longer — genome flag.**
- [ ] **304. Fry fragility. Fry show chem stress earlier than adults.**
- [ ] **305. Senescence sensitivity. Old fish fade faster in mediocre water.**
- [ ] **306. Color recovery montage. Over 10 min, watchables regain chroma.**
- [ ] **307. No fake illness. Don't invent diseases; keep abiotic tells.**
- [ ] **308. Water change theater. Fish inspect currents after change.**
- [ ] **309. Filter clog body. Lower flow → lazier cruise before chip warns.**
- [ ] **310. Aeration preference. Fish hang nearer bubbles when O2 low.**
- [ ] **311. Document chem→body table. One designer sheet.**
- [ ] **312. Quiet mode keeps chem body. Never mute pallor/gulp with voice-off.**
- [ ] **313. Care dock teach. Bad chem + care verbs nearby (player-wish).**
- [ ] **314. Chip↔body. Water chip should match what eyes already see.**
- [ ] **315. False alarm avoid. Don't pale on tiny blips — hysteresis.**
- [ ] **316. Regional chem. If gradients exist, hang in better pocket.**
- [ ] **317. Waste weather. Mulm spikes after overfeed → bottom fish busier.**
- [ ] **318. Algae boom graze. Green days → herbivores work harder.**
- [ ] **319. Bloom shade. Heavy bloom → top-light seeking.**
- [ ] **320. Smoke: pallor hysteresis. Spike then ease; pallor lags both ways.**

## Section — Water as medium — flow, drift, weight (321–360)

*Grounding: world.sample_flow, Hydrodynamics bank/coast, burst ripples, MotionField.*

- [ ] **321. Flow as weather vane. Body yaw often aligns with local flow.**
- [ ] **322. Coast on current. Hydrodynamics coast lengthens downstream.**
- [ ] **323. Upstream effort. Wag amp up when swimming up-current.**
- [ ] **324. Eddy playground. Fish briefly play in outlet eddies (curiosity).**
- [ ] **325. Lee rest. Rest on down-current side of hardscape.**
- [ ] **326. Burst wake. Dart leaves a short turbidity / ripple wake.**
- [ ] **327. School in shear. School stretches in velocity gradients.**
- [ ] **328. Filter outflow highway. Commute routes along strong flow.**
- [ ] **329. Dead-water boredom. Low flow corners get restless looping.**
- [ ] **330. Flood after change. Water change impulse current → ride it.**
- [ ] **331. Plant wake dancing. Pass behind leaves → flutter recovery.**
- [ ] **332. Surface wind (if). Soft surface push for top dwellers.**
- [ ] **333. Sink vs swim. Neutral buoyancy micro-corrections always on.**
- [ ] **334. Heavy after meal. Brief sink bias post-gluttony.**
- [ ] **335. Fry weak against flow. Fry shelter in lee more.**
- [ ] **336. Bold cross-current. Bold cut across flow; timid go around.**
- [ ] **337. Hover fight current. Hover species visibly correct in flow.**
- [ ] **338. Shuffle ignore mid flow. Bottom fish less affected by midwater jets.**
- [ ] **339. Snails clamp in surge. Neighbor reaction to flow spikes.**
- [ ] **340. Debris surf. Waste rides flow; fish intercept on the line.**
- [ ] **341. MotionField feeding burst polish. Deposit readable local boil.**
- [ ] **342. Startle against flow. Flee prefers downstream escape when possible.**
- [ ] **343. Courtship against current. Display holds station in flow — strength.**
- [ ] **344. Debug flow arrows. Dev overlay sampled vectors on follow.**
- [ ] **345. Flow LOD. Far fish approximate; near full sample.**
- [ ] **346. Document sample_flow users. Single integration point note.**
- [ ] **347. Bubble stream toy. Chase bubble curtain playfully (rare).**
- [ ] **348. Airstone party. Social swirl near aeration.**
- [ ] **349. Powerhead blast (if). Avoidance cone in front of strong jet.**
- [ ] **350. Calm desk lower jets. Optional softer visual flow in calm mode.**
- [ ] **351. Bank into turns. Existing bank — exaggerate in strong flow.**
- [ ] **352. Tail as rudder. Visible yaw from caudal in crossflow.**
- [ ] **353. Pec braking. Arrive at food with pec brake flare.**
- [ ] **354. Wall slide. Along glass, boundary layer slide motion.**
- [ ] **355. Corner slow. Corners reduce speed automatically.**
- [ ] **356. Vertical flow. Upwellings lift; downwellings press — use if field has Y.**
- [ ] **357. Turbidity from dig. Sift raises local opacity briefly.**
- [ ] **358. Ripple only near surface. Deep darts don't fake surface rings.**
- [ ] **359. World answer: plants sway from pass-by wake.**
- [ ] **360. Smoke: flow align. Mean heading correlates with flow in jet zone.**

## Section — Plants & hardscape as architecture of life (361–400)

*Grounding: stress-hide into plants, fry shelter, herbivory, cleaner stations, occlusion.*

- [ ] **361. Plants as rooms. Crowns are rooms fish enter, not transparent props.**
- [ ] **362. Leaf doorways. Prefer gaps; don't path through dense cores.**
- [ ] **363. Hide commit time. Once hidden, stay 2–8 s unless critical.**
- [ ] **364. Peek-and-withdraw. From cover: peek, scan, withdraw.**
- [ ] **365. Fry absolute cover. Fry refuse open water when cover exists.**
- [ ] **366. Herbivore garden path. Grazers leave visible browse trails over days.**
- [ ] **367. Nibble etiquette. Don't delete a plant in one tick — cadence.**
- [ ] **368. Stem rub itch. Chem itch → rub along stems.**
- [ ] **369. Cleaning station plant. Specific plant/hardscape as cleaner meet point.**
- [ ] **370. Territory plant. Claim a bush; chase others from it.**
- [ ] **371. Sleep in canopy. Some roost in mid-leaf, not only substrate.**
- [ ] **372. Courtship arena. Open sand patch between plants for dances.**
- [ ] **373. Ambush shadow. Predators use plant shade edge.**
- [ ] **374. School split around clump. Fusion after obstacle — living motion.**
- [ ] **375. Hardscape cave. Rock caves as true hide nodes.**
- [ ] **376. Glass vs plant choice. Spooked prefer plants over back glass.**
- [ ] **377. New plant inspect. Novelty tour of freshly planted stems.**
- [ ] **378. Trim trauma. Heavy trim → temporary open-water fear.**
- [ ] **379. Root tab curiosity. Fish investigate substrate disturbance.**
- [ ] **380. Floating plant shade. Under duckweed, fish hang cooler/dimmer.**
- [ ] **381. Lily pad ceiling. Top fish treat pads as roof.**
- [ ] **382. Carpet graze. Bottom fish nose through carpet species.**
- [ ] **383. Wood biofilm browse. Soft browse on hardscape slime.**
- [ ] **384. Occlusion honesty. Food behind bush not seen — sentience cross but body.**
- [ ] **385. Plant sway from body. Big fish passing moves leaves.**
- [ ] **386. Timid commute. Timid routes hug plant walls.**
- [ ] **387. Bold crossing. Bold crosses open lanes more.**
- [ ] **388. Rank plant perch. Dominant claims best lookout stem tip.**
- [ ] **389. Debug cover map. Show hide nodes.**
- [ ] **390. Document hide API. STRESS_HIDE_THRESHOLD + cover query.**
- [ ] **391. No ghost collide. Soft collision with foliage MM.**
- [ ] **392. Algae on glass vs plants. Scrapers prefer glass; nibblers leaves.**
- [ ] **393. Spawn on leaves. Egg-scatterers choose leaf undersides.**
- [ ] **394. Mouthbrood in shade. Brooders hang shaded.**
- [ ] **395. Post-hide shake. Exit cover with a shake-settling fidget.**
- [ ] **396. Cover competition. Two timid fish share a bush awkwardly.**
- [ ] **397. Empty tank fear. No plants → higher baseline stress posture.**
- [ ] **398. Jungle calm. Dense planting → lower vigilance.**
- [ ] **399. Scape edit repath. After aquascape, rebuild commute graph.**
- [ ] **400. Smoke: hide commit. Spooked fish remain near plant >2 s.**

## Section — School, shoal, and the lonely fish (401–440)

*Grounding: MotionSchool, swim_pattern, lead_score, schooling_strength, fission/fusion.*

- [ ] **401. School as one animal. Tighten visual cohesion without killing individuality.**
- [ ] **402. Shoal looser. Shoal pattern keeps wider gaps than school.**
- [ ] **403. Dart fission. Dart species explode apart then reform.**
- [ ] **404. Hover not schooling. Hover species mostly ignore school pull.**
- [ ] **405. Meander pair. Meander prefers 2–3, not 20.**
- [ ] **406. Cruise highway. Cruise species form lanes along glass.**
- [ ] **407. Leader election visible. Lead_score fish at tip, others trail.**
- [ ] **408. Leader tire. Leadership rotates — visible tip change.**
- [ ] **409. Merge ceremony. Two groups meet with a swirl then align.**
- [ ] **410. Split at decor. Obstacle-induced split with delayed fusion.**
- [ ] **411. Lone fish ache. Sociable fish alone show restless search.**
- [ ] **412. Alone bold fine. Bold/asocial OK alone — no fake loneliness toast.**
- [ ] **413. Mirror school fake. Glass may fake a partner briefly then habituate.**
- [ ] **414. Night school dissolve. Sleep fission; dawn fusion.**
- [ ] **415. Feed boil then reform. Feeding breaks school then rebuilds.**
- [ ] **416. Alarm crush. ALARM tightens school instantly.**
- [ ] **417. Predator split. Flee in multiple directions — confusion effect.**
- [ ] **418. Size-sort. Similar sizes school tighter (fry separate).**
- [ ] **419. Species purity soft. Prefer conspecifics but allow mixed shoals.**
- [ ] **420. Rank edge. Low rank on outside; high rank center optional.**
- [ ] **421. Sick outsider. Pale fish drifts to edge (chem).**
- [ ] **422. Bonded pair subplot. Pair keeps tighter than school mean.**
- [ ] **423. Grudge exclusion. Grudged fish kept at edge.**
- [ ] **424. MotionWave polish. Agitation cascade readable across school.**
- [ ] **425. Turn intent telegraph. Neighbors turn before you finish turning.**
- [ ] **426. Speed match soft. Match without robotic lock.**
- [ ] **427. Jitter desync. Phase offset so school isn't clone army.**
- [ ] **428. Topological neighbors. Prefer existing boids topology — document.**
- [ ] **429. School LOD. Far: one ribbon; near: individuals.**
- [ ] **430. Follow school hero. Follow picks leader preferentially.**
- [ ] **431. Photo school peak. Capture prefers tight formation moments.**
- [ ] **432. Empty school ghost. Last fish of species swims differently (wider).**
- [ ] **433. Repopulation joy. When second fish added, immediate school seek.**
- [ ] **434. Overcrowd boil. Too many → more fission, stress.**
- [ ] **435. Debug school_id colors. Dev tint by school.**
- [ ] **436. Document swim_pattern vs school.**
- [ ] **437. Calm desk softer boil. Less frantic fission in calm mode.**
- [ ] **438. Player parting. Hand at glass parts school like Moses briefly.**
- [ ] **439. Return gather. Keeper return → front-glass soft school.**
- [ ] **440. Smoke: fission/fusion. Obstacle causes split then merge <8 s.**

## Section — Dumb social — signals without speech (441–480)

*Grounding: FishSignals ALARM/FOOD/MATE/SUBMIT, bonds, grudges, rank, gaze contagion.*

- [ ] **441. Alarm is body first. ALARM signal → flash + tighten; text optional.**
- [ ] **442. Food call. FOOD signal → reorient toward caller heading.**
- [ ] **443. Mate call soft. MATE signal raises COURT propensity nearby.**
- [ ] **444. Submit bow. SUBMIT → curl + yield lane.**
- [ ] **445. Gaze contagion already — tune rates by sociability.**
- [ ] **446. Fin flick dialect. Species-specific flick meanings (threat vs hello).**
- [ ] **447. Lateral display hello. Non-aggressive side flash on approach.**
- [ ] **448. Chase vs play. Play chases slower, loop back; aggression doesn't.**
- [ ] **449. Cleaner dance. Host holds still; cleaner works — readable duo.**
- [ ] **450. Queue at cleaner. Second fish waits midwater.**
- [ ] **451. Egg plant respect. Soft avoid of guarded clutch zone.**
- [ ] **452. Fry mercy. Adults of same species soft-avoid fry (not all).**
- [ ] **453. Predator respect radius. Prey maintain ring distance.**
- [ ] **454. Curious inspect other species. Brief hover then leave.**
- [ ] **455. Snail ignore mostly. Fish don't false-flee snails.**
- [ ] **456. Shrimp jump startle. Sudden shrimp motion → micro flinch.**
- [ ] **457. Dead neighbor space. Mourning spacing already — keep sacred.**
- [ ] **458. Fight scar chance. Fights_won may add fin nick.**
- [ ] **459. Reconcile swim. After chase, parallel swim resets.**
- [ ] **460. Rank challenge dance. Short display without damage.**
- [ ] **461. No chat bubbles. Dumb social never requires LLM lines.**
- [ ] **462. Signal LOD. Far: only alarm; near: full kit.**
- [ ] **463. Signal debug. Show last signal type above fish.**
- [ ] **464. Habituated neighbor. Known tankmates startle less.**
- [ ] **465. Newcomer inspect. New fish gets novelty tours from residents.**
- [ ] **466. Exile then accept. After many yields, low rank accepted at edge.**
- [ ] **467. Pair bond escort. Bonded pair travel with one leading.**
- [ ] **468. Jealous third. Third fish briefly interferes with pair (rare).**
- [ ] **469. School vote. Direction change needs a few turn intents.**
- [ ] **470. Silent argument. Two fish flare then both leave — unresolved.**
- [ ] **471. Food monopoly. Dominant hogs flake; others wait — drama.**
- [ ] **472. Altruism none. Don't fake rescue; keep honest selfishness.**
- [ ] **473. Document FishSignals lifetimes.**
- [ ] **474. Cross-species alarm. Predator strike alarms mixed tank.**
- [ ] **475. False alarm cost. Too many alarms → desensitization.**
- [ ] **476. Play bow (rare). Invitation loop before chase-play.**
- [ ] **477. Mirror threat. Glass rival display then fade.**
- [ ] **478. Touch Nudge. Soft body bump as social, not collision only.**
- [ ] **479. Personal space ring by trait.**
- [ ] **480. Smoke: alarm tighten. ALARM reduces mean neighbor distance.**

## Section — Home, territory, and favorite water (481–520)

*Grounding: home_*, preferred_y, visited_regions, feed_heatmap, territory chase.*

- [x] **481. Home is a place. `home_*` is a loiter magnet, not only spawn.**
- [ ] **482. Favorite nook. Persist a sleep/hide nook per individual.**
- [ ] **483. Commute loops. Daily path repeats enough to recognize.**
- [ ] **484. Feed corner loyalty. feed_heatmap creates a 'kitchen'.**
- [ ] **485. Novelty map. visited_regions tours then settles.**
- [ ] **486. Territory oval. Chase radius ellipse, not circle.**
- [ ] **487. Border patrol. Territory holders cruise the edge.**
- [ ] **488. Intruder display. At border: flare, not always chase.**
- [ ] **489. Yield corridors. Low rank uses edge lanes.**
- [ ] **490. Preferred_y soft band. Hang in a band, not a plane.**
- [ ] **491. Seasonal home shift. Light move slowly shifts home.**
- [ ] **492. Post-scape amnesia. Soft reset homes after major scape.**
- [ ] **493. Pair shared home. Bonds share a home centroid.**
- [ ] **494. Fry nursery zone. Parents (if guarding) define a nursery.**
- [ ] **495. Lone wanderer. Low sociability has larger home range.**
- [ ] **496. School home. School centroid has a preferred tank third.**
- [ ] **497. Front stage when keeper. Home shifts forward when familiar player.**
- [ ] **498. Back stage when scared. Home shifts to plant wall.**
- [ ] **499. Debug home gizmo. Show home point + radius.**
- [ ] **500. Document home persistence in saves.**
- [ ] **501. No teleport home. Return home by swimming.**
- [ ] **502. Hunger expands range. Hungry fish enlarge search radius.**
- [ ] **503. Sated contracts. After feed, loaf near home.**
- [ ] **504. Senile smaller world. Old fish shrink range.**
- [ ] **505. Fry explode range then shrink. Exploration then settle.**
- [ ] **506. Map learning visible. First hour: more wall bumps; later smooth.**
- [ ] **507. Dead ends remembered. Avoid repeated stuck corners.**
- [ ] **508. Current highway commute. Use flow routes between homes.**
- [ ] **509. Night home ≠ day home. Separate roost vs day hang.**
- [ ] **510. Conflict homes. Two territories overlap → display zone.**
- [ ] **511. Empty real estate. After death, neighbors expand into space.**
- [ ] **512. Newcomer edge. New fish starts at edge home, moves in.**
- [ ] **513. Bold center. Bold homes more central.**
- [ ] **514. Timid periphery. Timid homes near cover.**
- [ ] **515. Hover station = home. Hover species home is a point station.**
- [ ] **516. Shuffle patch. Bottom fish home is a sand patch.**
- [ ] **517. Top balcony. Top dwellers home near surface front.**
- [ ] **518. Photo home. Capture prefers fish in their home context.**
- [ ] **519. Follow home return. After follow clear, fish goes home.**
- [ ] **520. Smoke: home loiter. Time-in-radius above chance baseline.**

## Section — Fear, freeze, and the recovery arc (521–560)

*Grounding: spooked, startle, FLEE, mourning spacing, calm recovery, trauma scar body.*

- [x] **521. Fear has an arc: freeze → flee → hide → peek → recover.**
- [ ] **522. Freeze frame 150–300 ms before flee — animal truth.**
- [ ] **523. Flee line not random. Prefer cover vector if known.**
- [ ] **524. Zigzag escape. Prey zig; predators cut — drama.**
- [ ] **525. Plant slam. Enter cover hard, settle soft.**
- [ ] **526. Peek recovery. After hide, peek before full exit.**
- [ ] **527. Calm half-life. Stress decays with visible easing posture.**
- [ ] **528. Trauma scar body. Survived predator → wider gap forever (soft).**
- [ ] **529. Habituation to safe scare. Decor drop startles less over time.**
- [ ] **530. Glass tap graded recover. Faster recover if habituated.**
- [ ] **531. False alarm laugh. Brief shake then resume — relief.**
- [ ] **532. School crush recover. After alarm, spacing re-expands slowly.**
- [ ] **533. Lone panic longer. Alone fish hide longer than schooled.**
- [ ] **534. Bold shorter hide. Bold exits cover sooner.**
- [ ] **535. Timid longer peek. Timid multi-peeks.**
- [ ] **536. Hunger overrides fear. Desperation already — keep body readable.**
- [ ] **537. Parent fear. Guarding parents flee less / threaten more.**
- [ ] **538. Fry scatter. Fry explode to many hide nodes.**
- [ ] **539. Predator afterglow. After strike miss, predator prowls.**
- [ ] **540. Prey afterglow. Prey keep edge for minutes.**
- [ ] **541. Mourning space. Soft radius around death site.**
- [ ] **542. No guilt fear. Neglect doesn't make 'sad eyes' — keep honest.**
- [ ] **543. Startle refractory. MotionWave refractory prevents chatter.**
- [ ] **544. Cascade readable. One dart → neighbors flinch in order.**
- [ ] **545. Recovery feed. After scare, delayed return to food.**
- [ ] **546. Sleep after stress. Big scare → earlier sleep that night.**
- [ ] **547. Color drain then return. Pallor during fear, chroma on recover.**
- [ ] **548. Breath debt after flee. Pant then ease.**
- [ ] **549. Debug fear state. Show scare arc phase.**
- [ ] **550. Document spooked timers.**
- [ ] **551. Photo mid-flee. Capture can freeze a dramatic dart.**
- [ ] **552. Reduced motion flee. Soften zig intensity if a11y.**
- [ ] **553. Quiet mode keeps fear body.**
- [ ] **554. Care during fear. Player care mid-panic still helps water, fish ignore UI.**
- [ ] **555. Second scare harder. Stacked scares deepen hide.**
- [ ] **556. Safe day reset. Good day slowly erodes trauma soft.**
- [ ] **557. Familiar keeper reduces fear. Familiarity softens loom.**
- [ ] **558. Stranger loom. New silhouette at glass = stronger.**
- [ ] **559. Night fear amp. Same stimulus worse at night.**
- [ ] **560. Smoke: recover peek. After hide, peek occurs before open cruise.**

## Section — Courtship you can watch (561–600)

*Grounding: COURT/SPAWN, courtship flare/sync, dimorphism, dances by swim_pattern.*

- [ ] **561. Dance must be watchable from sofa distance.**
- [ ] **562. Parallel cruise dance. Matching headings + soft color up.**
- [ ] **563. S-curve dance. Lateral undulation display.**
- [ ] **564. Vertical figure-8. Up-down courtship.**
- [ ] **565. Circle parade. Wide circling around mate.**
- [ ] **566. Jerky snap display. Dart species courtship.**
- [ ] **567. Color saturation court. `_courtship_intensity` pushes chroma.**
- [ ] **568. Fin flare court. Dorsal/anal max during peak.**
- [ ] **569. Sync swim. `_courtship_sync` locks phase briefly.**
- [ ] **570. Reject turn-away. Female (or mate) turns out — clear no.**
- [ ] **571. Persist then give up. Failed court → loaf, not loop forever.**
- [ ] **572. Rival interrupt. Third fish breaks dance.**
- [ ] **573. Arena choice. Prefer open sand / clear water.**
- [ ] **574. Dimorphism readable. Male showier motion + color.**
- [ ] **575. Egg scatter release. Visible tremble + egg voxels.**
- [ ] **576. Livebearer birth posture. Stillness + fry pop.**
- [ ] **577. Mouthbrood transfer. Jaw flare as eggs taken.**
- [ ] **578. Guarding figure-8. Parents patrol clutch.**
- [ ] **579. False spawn. Practice dance without eggs (young).**
- [ ] **580. Water quality gate. Bad water aborts dance early.**
- [ ] **581. Audience fish. Others watch from edge (rare).**
- [ ] **582. Night refuse. Most court day-only.**
- [ ] **583. Pair bond renewal. Bonds re-dance softly sometimes.**
- [ ] **584. Sterile still dance. Sterile may display without spawn.**
- [ ] **585. Debug court stage. Show COURT subphase.**
- [ ] **586. Document dance × swim_pattern table.**
- [ ] **587. Photo courtship. Soft prompt when dance peaks (optional).**
- [ ] **588. Follow courtship. PiP prefers the pair.**
- [ ] **589. Soundless drumming. Occasional body thump vs leaf (rare).**
- [ ] **590. Post-spawn calm. Both fish loaf after success.**
- [ ] **591. Failed spawn recover. Eat stress, then separate.**
- [ ] **592. Clutch respect zone. Soft avoid by others.**
- [ ] **593. Egg fungus tell later — skip disease; keep clean fail as eat eggs.**
- [ ] **594. Male nest (if). Future bubble-nest flag reserved.**
- [ ] **595. Court hunger conflict. Hungry fish break dance for flake — funny true.**
- [ ] **596. Keeper hush. Big loom aborts dance.**
- [ ] **597. School space. School opens a hole for dancers.**
- [ ] **598. Color blind safe. Dance uses motion not only hue.**
- [ ] **599. Reduced motion dance. Simpler arcs if a11y.**
- [ ] **600. Smoke: dance sync. Peak intensity correlates with pair distance band.**

## Section — Growing up — silhouette of a life (601–640)

*Grounding: maturity fry→senescent, growth_factor, aging tint, dimorphism, generation.*

- [ ] **601. Fry are different animals. Motion clumsy, hunger high, fear high.**
- [ ] **602. Juvenile practice. Mock court / mock chase without full strength.**
- [ ] **603. Adult peak color. Adult chroma highest.**
- [ ] **604. Senescent fade. Soft dull + slower turn.**
- [ ] **605. Growth spurt after meals. Tiny scale pops over hours.**
- [ ] **606. Size honesty. effective_size drives collision and school sort.**
- [ ] **607. Head-heavy fry. Already — exaggerate yaw inertia.**
- [ ] **608. Fin grow-in. Fry fins shorter proportion; lengthen with age.**
- [ ] **609. Voice of age without voice. Motion age-reads offline.**
- [ ] **610. Generation tint optional. Very subtle lineage hue drift.**
- [ ] **611. Dimorphism onset. Male show traits appear at adult.**
- [ ] **612. Pregnancy timeline body. Gradual bulge, not step.**
- [ ] **613. Brood jaw timeline. Mouthbrood fullness eases as fry develop.**
- [ ] **614. Age rewind meals. Existing revival — keep subtle not immortal.**
- [ ] **615. Max age variance. `_life_jitter` visible as different lifespans.**
- [ ] **616. Elder leader rare. Sometimes old fish lead slowly.**
- [ ] **617. Elder edge. Often old fish on school edge.**
- [ ] **618. Fry school of their own. Size-matched fry cloud.**
- [ ] **619. Cannibal risk soft. Adults may chase fry of other species only.**
- [ ] **620. Maturity mode gates. COURT blocked for fry.**
- [ ] **621. Debug maturity label. Follow shows stage.**
- [ ] **622. Document maturity thresholds.**
- [ ] **623. Photo family. Capture fry+parent when brooding.**
- [ ] **624. Name delay. Fry unnamed until juvenile (optional).**
- [ ] **625. Epithet unlock. Personality epithet after adult.**
- [ ] **626. Scar accumulate with age. More nicks possible.**
- [ ] **627. Color morph adult lock. Morph_label stable at adult.**
- [ ] **628. Senile home shrink.**
- [ ] **629. Youth explore. Juveniles maximize novelty tours.**
- [ ] **630. Adult commute. Adults settle routes.**
- [ ] **631. Death of elder event. Soft school pause.**
- [ ] **632. Birth of fry event. Soft curiosity from others.**
- [ ] **633. Growth energy cost. Fast growth → more feed need.**
- [ ] **634. Stunt in bad water. Chem slows growth visibly.**
- [ ] **635. Planted paradise growth. Good tank → richer adult color.**
- [ ] **636. LOD age. Far: size only; near: stage tells.**
- [ ] **637. No age UI spam. Body first; panel secondary.**
- [ ] **638. Calm desk still ages. Time doesn't stop in calm.**
- [ ] **639. Time scale respect. Age rates scale honestly.**
- [ ] **640. Smoke: fry clumsiness. Fry turn jerk higher than adults.**

## Section — Wear, injury, and history on the body (641–680)

*Grounding: `_fin_nicks` (thin today), fights_won in bio, scars, fin tear, scale dull.*

- [x] **641. Fin nicks render path. `_fin_nicks` must affect mesh/shader — ship it. **(L)**
- [ ] **642. Nick from fights. fights_won/lost chance to add nick.**
- [ ] **643. Nick from decor. Rare scrape on hardscape.**
- [ ] **644. Nick heal slow. Over long time, nicks soften (not magic).**
- [ ] **645. Tear asymmetry. Nicks prefer one side — history.**
- [ ] **646. Scale dull patch. Local desat after impact.**
- [ ] **647. Split fin. Caudal split rare after big flee hit.**
- [ ] **648. Barbel wear (if). Whisker species tip fade.**
- [ ] **649. Eye cloud rare. Skip disease — use temporary after injury only.**
- [ ] **650. Missing scale glitter. Tiny specular hole.**
- [ ] **651. Worn elders. Senescent start with micro-wear.**
- [ ] **652. Cleaner helps. After clean, micro-recovery of dullness.**
- [ ] **653. No gore. Wear is tasteful, aquarium-pretty.**
- [ ] **654. Photo scars. Scars make individuals recognizable.**
- [ ] **655. Follow scar story. Bio can mention nick without LLM.**
- [ ] **656. Debug nicks. Show nick count.**
- [ ] **657. Document wear API.**
- [ ] **658. Species fin fragility. Long-fin more nick prone.**
- [ ] **659. Courtship risk. Rivals nick more in season.**
- [ ] **660. Plant snag. Dense stems rare nick.**
- [ ] **661. Net trauma (if catch UI). Future — reserve.**
- [ ] **662. Transport pale. New arrivals micro-wear + pale.**
- [ ] **663. Healed kink. Old nick becomes darker seam.**
- [ ] **664. Bilateral symmetry break. Wear sells individuality hard.**
- [ ] **665. School still accepts. Nicked fish not excluded cruelly.**
- [ ] **666. Rank vs wear. Rank not reduced only by nicks.**
- [ ] **667. Predator bite miss. Graze nick on prey escape.**
- [ ] **668. Substrate scrape. Shuffle species belly dull.**
- [ ] **669. Glass rub wear. Chronic glass sitters slight nose dull.**
- [ ] **670. Coloration under wear. Pattern continues under nick.**
- [ ] **671. LOD wear. Near only.**
- [ ] **672. A11y: wear not only red. Shape break + value.**
- [ ] **673. Save nicks. Persist in bio/save.**
- [ ] **674. Breeding wear inherit? No — only acquired.**
- [ ] **675. Fry pristine. Fry start clean.**
- [ ] **676. Adult earn history. Wear = time in tank.**
- [ ] **677. Memorial keep scars. Death pose preserves nicks.**
- [ ] **678. World answer: shed scale particle rare.**
- [ ] **679. Quiet dignity. No 'hurt' toast spam.**
- [ ] **680. Smoke: nick visible. Shader/mesh differs when nicks>0.**

## Section — Dying with dignity (body first) (681–720)

*Grounding: start_dying, death drift pose, waste, epitaph, school mourning — no guilt voice.*

- [ ] **681. Death is quiet theater. Drift, fade, settle — no speech required.**
- [ ] **682. Dying slows. start_dying reduces wag, tilts, drifts.**
- [ ] **683. Surface list. Some deaths list toward surface; some sink — species.**
- [ ] **684. School pause. Brief spacing / slow when witnessing.**
- [ ] **685. No circle of blame. Keep mourning intensity soft.**
- [ ] **686. Body to mulm. Waste spawn honest; nutrients continue life.**
- [ ] **687. Epitaph later. Body first; text in panel/journal.**
- [ ] **688. Favorite memorial toast. COMMS death summary — cross-link.**
- [ ] **689. Non-favorite soft. No toast storm for unnamed deaths.**
- [ ] **690. Fry death quieter. Smaller pose, less school pause.**
- [ ] **691. Elder death heavier pause. Slightly longer stillness.**
- [ ] **692. Predator kill distinct. Brief thrash then carry — careful taste.**
- [ ] **693. Starve distinct. Slow fade, not thrash.**
- [ ] **694. Senescence distinct. Gradual then stop.**
- [ ] **695. Remove option dignity. If player removes body, soft fade.**
- [ ] **696. Leave-in-place. Default: body becomes ecology.**
- [ ] **697. Color death desat. Final chroma drop.**
- [ ] **698. Eye settle. Eyes soft-close.**
- [ ] **699. Fin relax. Fins unclamp limp.**
- [ ] **700. Current carries. Flow moves body gently.**
- [ ] **701. Shrimp arrive. Cleaners investigate — cycle of life.**
- [ ] **702. Snail pass. Snails may approach mulm.**
- [ ] **703. Plant indifferent. Plants don't 'react' emotionally — good.**
- [ ] **704. Debug death phase.**
- [ ] **705. Document die events.**
- [ ] **706. Photo ban mid-death optional. Or allow solemn capture.**
- [ ] **707. Follow handoff. Already — keep gentle.**
- [ ] **708. Lineage continues. Births elsewhere soft-balance mood.**
- [ ] **709. Empty species ache. Last of kind swims wide search briefly.**
- [ ] **710. Repopulation ease. Newcomer softens ache.**
- [ ] **711. No reincarnation fake. New fish is new.**
- [ ] **712. Save respects dying. Don't checkpoint mid-garish pose.**
- [ ] **713. Time scale: death duration readable at 1×.**
- [ ] **714. Reduced motion death. Simpler fade.**
- [ ] **715. Quiet mode: still show death body.**
- [ ] **716. Away recap deaths. Summarize, don't dramatize (comms).**
- [ ] **717. Night death softer. Less school reaction at night.**
- [ ] **718. Dawn discover. Morning notice of night death — soft.**
- [ ] **719. Player absence deaths. Honest; no accusation.**
- [ ] **720. Smoke: death desat. Dying fish chroma below living mean.**

## Section — Fry, eggs, and parental body care (721–760)

*Grounding: eggs, livebearer, mouthbrood, brooding hover, guards_clutch, fry shelter.*

- [ ] **721. Eggs as objects. Visible, settle, guarded or eaten — drama.**
- [ ] **722. Scatter tremble. Female tremble release.**
- [ ] **723. Sticky leaf eggs. Underside attach.**
- [ ] **724. Cave eggs. Hardscape cave clutches.**
- [ ] **725. Guard figure-8. Parent patrol path.**
- [ ] **726. Fan eggs. Parent pecs fan — oxygen theater.**
- [ ] **727. Mouthbrood show. Jaw full silhouette.**
- [ ] **728. Mouthbrood spit tour. Brief fry release then re-collect (rare).**
- [ ] **729. Livebearer drop. Fry appear near plants.**
- [ ] **730. Fry dash to cover. Immediate hide seek.**
- [ ] **731. Fry food frenzy micro.**
- [ ] **732. Parent warn. Display to intruders near clutch.**
- [ ] **733. Parent feed less. Tradeoff visible.**
- [ ] **734. Clutch loss eat. Parents may eat failed clutch — honest.**
- [ ] **735. Helper fish rare. Soft future flag.**
- [ ] **736. Sterile watch. Sterile fish may watch dances.**
- [ ] **737. Breed season light. Longer day → more COURT.**
- [ ] **738. Crowd suppress breed. Overstock lowers fecundity behavior.**
- [ ] **739. Pair fidelity soft. Bonds re-pair more.**
- [ ] **740. Sneaker male. Brief interrupt spawn (rare).**
- [ ] **741. Debug clutch id.**
- [ ] **742. Document repro modes.**
- [ ] **743. Photo nursery. Soft framing for fry clouds.**
- [ ] **744. Follow parent. Prefer guardian parent if any.**
- [ ] **745. Fry school shimmer. Tight fry cloud motion.**
- [ ] **746. Juvenile leave nursery. Gradual range expand.**
- [ ] **747. Father mouthbrood species. Sex roles by genome.**
- [ ] **748. Both guard. Some species both parents.**
- [ ] **749. Abandon under stress. Bad water → abandon — hard truth.**
- [ ] **750. Keeper finger near eggs. Soft parent threat display.**
- [ ] **751. No egg UI spam. Body first.**
- [ ] **752. Save eggs. Persist clutch state.**
- [ ] **753. Time scale eggs. Development readable.**
- [ ] **754. Fungus skip. Prefer eat/fail over disease sim.**
- [ ] **755. Bubble nest reserve. Future anabantoid flag.**
- [ ] **756. Substrate pit. Cichlid-like dig rare (shuffle+).**
- [ ] **757. Dig cloud. Pit making stirs waste.**
- [ ] **758. Fry mimic adult pattern faint.**
- [ ] **759. Generation counter quiet. Body lineage via size classes.**
- [ ] **760. Smoke: fry cover. New fry spend >50% time near plants first minute.**

## Section — Species habit authenticity (761–800)

*Grounding: swim_pattern kits: school/shoal/dart/hover/cruise/meander/shuffle; preferred_y.*

- [x] **761. Habit kit per swim_pattern. One table drives defaults. **(L)**
- [ ] **762. School: tight, mid, flash alarm.**
- [ ] **763. Shoal: loose, browsing, easy split.**
- [ ] **764. Dart: still then explode; surface rings.**
- [ ] **765. Hover: station keep; pec scull heavy.**
- [ ] **766. Cruise: lane swimming along glass.**
- [ ] **767. Meander: curious S-paths, inspect.**
- [ ] **768. Shuffle: bottom sit, sift, night active.**
- [ ] **769. preferred_y sacred. Habit respects column niche.**
- [ ] **770. Herbivory kit. Grazers angle to leaves.**
- [ ] **771. Predator kit. Slow stalk + burst.**
- [ ] **772. Labyrinth kit. Air gulp choreography.**
- [ ] **773. Livebearer kit. Gestation lumber.**
- [ ] **774. Mouthbrood kit. Jaw care.**
- [ ] **775. Biolum kit. Night pulse.**
- [ ] **776. Top skater. Surface film habit.**
- [ ] **777. Cave loach-like. Hardscape hug (shuffle+).**
- [ ] **778. Open pelagic. Avoid walls when calm.**
- [ ] **779. Brackish reserve. Future habit flags.**
- [ ] **780. Species library sync. Habits from species_library.**
- [ ] **781. Creator habit preview. Creature creator shows habit blurb.**
- [ ] **782. Library habit icons. Readable icons for patterns.**
- [ ] **783. Mixed tank niches. Different preferred_y reduce conflict.**
- [ ] **784. Niche fight. Same niche → more chase.**
- [ ] **785. Debug habit label.**
- [ ] **786. Document habit kit.**
- [ ] **787. Moddable habits later. Schema note in data-schemas.**
- [ ] **788. Habit vs personality. Personality modulates, habit sets base.**
- [ ] **789. Habit vs Mode. Mode overlays habit, doesn't erase.**
- [ ] **790. Photo habit. Framing by niche (top/mid/bottom).**
- [ ] **791. Follow habit camera. Camera bias by preferred_y.**
- [ ] **792. Onboarding habit whisper. First follow names habit once.**
- [ ] **793. No wrong habit shame. All kits valid beauty.**
- [ ] **794. Rare habit morph. Mutation may soft-shift pattern.**
- [ ] **795. Hybrid offspring blend. Child averages parent kits.**
- [ ] **796. Elder habit rigid. Old fish stick to routes.**
- [ ] **797. Fry habit learn. Fry adopt adult kit gradually.**
- [ ] **798. Empty niche invite. After extinction, newcomers claim.**
- [ ] **799. Calm desk niches. Still respect preferred_y.**
- [ ] **800. Smoke: niche separation. Mean Y differs school vs shuffle samples.**

## Section — Neighbors — shrimp, snails, the rest of the cast (801–840)

*Grounding: shrimp cleaner/molt, snail freeze-under-fish, predation tells, shared alarm.*

- [ ] **801. Shrimp are co-stars. Cleaner holds, molt hides — fish react.**
- [ ] **802. Fish at cleaner: freeze tremble.**
- [ ] **803. Shrimp jump: fish micro-flinch.**
- [ ] **804. Molt shrine. Soft avoid freshly molted shrimp.**
- [ ] **805. Snail freeze under fish hover — already; keep strong.**
- [ ] **806. Snail clamp on startle wave.**
- [ ] **807. Fish ignore snail mostly — good.**
- [ ] **808. Predatory fish vs shrimp. Occasional hunt tell.**
- [ ] **809. Shrimp alarm to fish? Optional soft.**
- [ ] **810. Shared food etiquette. Shrimp take leftovers after fish.**
- [ ] **811. Snail clean glass; fish scrape — parallel.**
- [ ] **812. Night shift. Shrimp/snails busier at night while fish roost.**
- [ ] **813. Death cleanup. Inverts process mulm — cycle visible.**
- [ ] **814. No invert speech. Keep dumb.**
- [ ] **815. Debug multi-fauna interactions.**
- [ ] **816. Document cleaner station API.**
- [ ] **817. Photo multi-species. Encourage mixed frames.**
- [ ] **818. Follow shrimp sometimes. Equal dignity.**
- [ ] **819. Fish curiosity to snail eggs.**
- [ ] **820. Fish may eat snail eggs — honest tension.**
- [ ] **821. Shrimp graze fish waste — link.**
- [ ] **822. Crowd: inverts suffer under bioload too — body dull.**
- [ ] **823. Plant triangle. Fish-plant-invert food web readable.**
- [ ] **824. Amano-like busy. Shrimp constant micro-work.**
- [ ] **825. Mystery snail leisure. Slow dignity.**
- [ ] **826. Ramshorn boom. Population tell on glass.**
- [ ] **827. Fish startle from snail fall.**
- [ ] **828. Invert hide from big fish shadow.**
- [ ] **829. Big fish shadow = cloud.**
- [ ] **830. Fry vs shrimp. Fry compete microfood.**
- [ ] **831. Adult fish leave shrimp food — size gate.**
- [ ] **832. Territory: shrimp not in fish territory logic — OK.**
- [ ] **833. School parts around snail.**
- [ ] **834. Cleaner queue includes shrimp host rare.**
- [ ] **835. World answer: shrimp eat leftover flake bits.**
- [ ] **836. Quiet coexistence default.**
- [ ] **837. Drama rare. Don't force constant conflict.**
- [ ] **838. Ecosystem chip later — body first.**
- [ ] **839. Save all fauna equally.**
- [ ] **840. Smoke: cleaner hold. Host speed ≈0 while cleaned.**

## Section — Silent sound — vibration, wake, presence (841–880)

*Grounding: lateral-line flinch, pass-by plant sway, substrate sift cloud, glass thrum.*

- [x] **841. Lateral-line flinch. Off-screen dart still felt — body turns. **(L)**
- [ ] **842. Pass-by plant sway. Wake moves leaves.**
- [ ] **843. Substrate thud. Heavy landings puff sand.**
- [ ] **844. Glass thrum. Body near glass soft vibration cue (haptic opt).**
- [ ] **845. Wake visibility. Tiny particulate trail after dart.**
- [ ] **846. Bubble kiss soundless. Visual only.**
- [ ] **847. School turn whoosh as motion, not audio.**
- [ ] **848. Surface ring language. Rings mean gulp/dart/feed.**
- [ ] **849. Filter hum coupling. Optional: fish less startle when filter on steady.**
- [ ] **850. Tap vibration vs visual. Distinguish if possible.**
- [ ] **851. Neighbor thrash felt. Struggle broadcasts flinch.**
- [ ] **852. Quiet tank baseline. Still water makes motion meaningful.**
- [ ] **853. Storm mode rare. Agitation field event.**
- [ ] **854. Haptic feed. Controller tick on bite (opt).**
- [ ] **855. Haptic startle. Soft rumble on big flee (opt).**
- [ ] **856. No mandatory audio. All tells work muted.**
- [ ] **857. Mic presence (keeper). Volume as weather — existing path polish.**
- [ ] **858. Debug vibration events.**
- [ ] **859. Document lateral-line radius.**
- [ ] **860. LOD: far skip wake particles.**
- [ ] **861. A11y flash. Alternative to motion-only cues.**
- [ ] **862. Photo wake. Capture rings mid-expand.**
- [ ] **863. Sift cloud as speech. Bottom fish 'talk' via silt.**
- [ ] **864. Fin slap rare. Threat display slap on water.**
- [ ] **865. Jaw click visual. Mouth snap without sound.**
- [ ] **866. Egg fan pulse. Visible water pulse from pecs.**
- [ ] **867. Brood cough. Mouthbrood spit micro-current.**
- [ ] **868. Death settle puff. Soft silt when body lands.**
- [ ] **869. Shrimp flick felt by nearby fry.**
- [ ] **870. Snail scrape visual on glass.**
- [ ] **871. Plant pearl pop. Pearling draws fish glance.**
- [ ] **872. World answers pearling with curiosity hover.**
- [ ] **873. Light caustic flicker on scales as 'sound'.**
- [ ] **874. Shadow flicker vigilance.**
- [ ] **875. Current change announce. Fish reorient together.**
- [ ] **876. Care water pour (if). Soft collective flinch then ease.**
- [ ] **877. Never rely on captions for these.**
- [ ] **878. Comms quiet keeps vibration tells.**
- [ ] **879. Battery saver: fewer particles, keep flinch.**
- [ ] **880. Smoke: lateral flinch. Neighbor dart behind raises turn rate.**

## Section — The world answers back (881–920)

*Grounding: ripples, plant lean, waste stir, light flicker on scales, camera-readable beats.*

- [x] **881. World answers every important fish verb.**
- [ ] **882. Dart → ripple (top) / silt (bottom).**
- [ ] **883. Gulp → bubbles + ring.**
- [ ] **884. Feed → boil + heatmap.**
- [ ] **885. Hide → leaf tremble.**
- [ ] **886. Court → sand puff optional.**
- [ ] **887. Death → mulm + shrimp interest.**
- [ ] **888. Birth → fry shimmer + adult glance.**
- [ ] **889. Alarm → school crush + freeze others beat.**
- [ ] **890. Care → current + breath ease.**
- [ ] **891. Light on → dawn uncurl.**
- [ ] **892. Light off → roost gather.**
- [ ] **893. Scape edit → novelty tours.**
- [ ] **894. Overfeed → waste weather + grazer busy.**
- [ ] **895. Filter rinse → outflow inspect.**
- [ ] **896. Plant pearling → curiosity.**
- [ ] **897. Algae bloom → scrape uptick.**
- [ ] **898. Crash → survivors vigilant.**
- [ ] **899. Recovery → color return montage.**
- [ ] **900. Keeper face → glance climate.**
- [ ] **901. Away return → front gather XOR toast.**
- [ ] **902. Follow → intimacy glances.**
- [ ] **903. Photo → hush + hold fidget.**
- [ ] **904. Immersive → trust ease.**
- [ ] **905. Quiet mode → body remains.**
- [ ] **906. Calm desk → softer answers, not dead.**
- [ ] **907. Debug answer log. Last world answers.**
- [ ] **908. Document answer table.**
- [ ] **909. No orphan verbs. Every Mode has a world tell.**
- [ ] **910. LOD answers. Far fewer particles.**
- [ ] **911. A11y answers. Shape/motion not color alone.**
- [ ] **912. Photo answers. Rings readable in stills.**
- [ ] **913. Trailer answers. Design for watchability.**
- [ ] **914. Performance budget. Answers share particle pool.**
- [ ] **915. Determinism. Answers seeded for replays if needed.**
- [ ] **916. Mod note. Future hooks for answers.**
- [ ] **917. Shrimp answers too.**
- [ ] **918. Snail answers too.**
- [ ] **919. Plant answers (naturalism cross).**
- [ ] **920. Smoke: dart ripple. Top dart near surface spawns ring.**

## Section — Individual quirks without a mind stack (921–960)

*Grounding: bio habits, home nook, favorite flake side, habitual route — readable, offline.*

- [ ] **921. Quirk: always enters from left glass.**
- [ ] **922. Quirk: waits at filter corner at 'mealtime'.**
- [ ] **923. Quirk: prefer red flake if typed.**
- [ ] **924. Quirk: sleeps in same stem crotch.**
- [ ] **925. Quirk: greets keeper first.**
- [ ] **926. Quirk: last to feed.**
- [ ] **927. Quirk: first to hide.**
- [ ] **928. Quirk: patrols front every dawn.**
- [ ] **929. Quirk: ignores snails completely.**
- [ ] **930. Quirk: bullies one rival only.**
- [ ] **931. Quirk: best friends pair route.**
- [ ] **932. Quirk: explores new decor first.**
- [ ] **933. Quirk: never explores — homebody.**
- [ ] **934. Quirk: surface waiter.**
- [ ] **935. Quirk: bottom hermit.**
- [ ] **936. Quirk: midwater only.**
- [ ] **937. Quirk: glass sitter.**
- [ ] **938. Quirk: plant tunnel runner.**
- [ ] **939. Quirk: bubble chaser.**
- [ ] **940. Quirk: mirror dancer (rare).**
- [ ] **941. Quirks from bio stats. Derive, don't hardcode all.**
- [ ] **942. Quirk persistence in save.**
- [ ] **943. Quirk readable in 60 s watch.**
- [ ] **944. Quirk without names. Still readable if unnamed.**
- [ ] **945. Quirk without LLM. Offline always.**
- [ ] **946. Quirk debug list on follow.**
- [ ] **947. Max 2–3 quirks active. Avoid noise.**
- [ ] **948. Quirk conflict resolve. Priority list.**
- [ ] **949. Personality seeds quirks. Bold→greeter etc.**
- [ ] **950. Experience writes quirks. Survived scare→hidey.**
- [ ] **951. Age shifts quirks. Elder homebody.**
- [ ] **952. Breeding soft-inherits quirk tendency.**
- [ ] **953. Photo quirk. Capture signature pose.**
- [ ] **954. Residents panel quirk one-liner (no LLM).**
- [ ] **955. Memorial quirk. Epitaph uses quirk.**
- [ ] **956. Player can notice without UI.**
- [ ] **957. UI optional amplify.**
- [ ] **958. Don't label too early. Let watch teach.**
- [ ] **959. Smoke: quirk persistence. Restart keeps nook id.**
- [ ] **960. Foundation: quirk registry service. **(L)**

## Section — Rare wonder & long-watch rewards (961–1000)

*Grounding: once-a-session miracles that prove the tank is a place, not a screensaver.*

- [ ] **961. Once-per-session miracle budget. Max 1–2 wonder beats.**
- [ ] **962. Full-tank turn: entire school rotates as one sheet.**
- [ ] **963. Silence beat: 3 s where almost nothing moves, then a dart.**
- [ ] **964. Sunbeam dust: caustics + fish glide through glitter.**
- [ ] **965. Double gulp sync: two labyrinths gulp together.**
- [ ] **966. Cleaner moment: perfect still host + shrimp.**
- [ ] **967. Fry cloud parting for adult then reseal.**
- [ ] **968. Night biolum constellation soft pulse.**
- [ ] **969. Dawn first stretch of the boldest fish.**
- [ ] **970. Pair spiral courtship peak perfect loop.**
- [ ] **971. Predator miss + elegant escape arc.**
- [ ] **972. Glass greet of the greeter quirk fish.**
- [ ] **973. Pearling + three fish inspect in turn.**
- [ ] **974. Post-care color bloom across school.**
- [ ] **975. Last-of-kind wide search then settle.**
- [ ] **976. Newcomer acceptance spiral into school.**
- [ ] **977. Elder leading a slow parade once.**
- [ ] **978. Silt angel: sift cloud lit from side.**
- [ ] **979. Surface ring calligraphy from two darts.**
- [ ] **980. Plant tunnel chase with leaf wake.**
- [ ] **981. Mirror dissolve: glass rivalry ends in peace.**
- [ ] **982. Return gather without toast — pure body.**
- [ ] **983. Photo perfect: fish poses mid-fidget as if.**
- [ ] **984. Follow intimacy eye contact soft.**
- [ ] **985. Away dream residue: night_watch soft body leftover.**
- [ ] **986. Rain mode (menu): soft surface tick + fish ease.**
- [ ] **987. Anniversary quiet: school front-glass hang.**
- [ ] **988. Empty wonder: single fish in big scape still alive.**
- [ ] **989. Crowded wonder: chaos that still reads as life.**
- [ ] **990. No LLM required for any wonder.**
- [ ] **991. Wonder never guilt.**
- [ ] **992. Wonder respects quiet mode.**
- [ ] **993. Wonder rare — scarcity is the point.**
- [ ] **994. Debug force wonder (dev).**
- [ ] **995. Document miracle budget.**
- [ ] **996. Trailer bait: 5 wonders safe to film.**
- [ ] **997. Player-wish cross: first five minutes one wonder.**
- [ ] **998. Plant naturalism cross: pearling wonder.**
- [x] **999. Smoke: miracle budget ≤2/session; closing watch works with voice off.**
- [x] **1000. Closing thesis: if voice dies, the fish still live.**

