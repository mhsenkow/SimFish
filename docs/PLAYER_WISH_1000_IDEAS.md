# I Wish This Was Better — 1000 Player-Facing Improvements

*Drafted 2026-09-10. Director's mega-backlog for the "make the game feel finished" pass.*

The brief: a thousand things a real player is likely to hit and go **"I wish
this was better."** Not deep sim science. Not plant naturalism. Not another
sentience architecture. **Friction, clarity, care, feedback, trust, and
delight** — the stuff that turns a deep aquarium into a thing people keep open
on their desk for months.

This doc **extends** what already shipped. Do not rebuild GOALS A–H, the plant
naturalism 1000, the sentience pillar stack, or ONBOARDING_LEGIBILITY (marked
complete — verify in play, don't rewrite). Ground truth lives in
`main.gd`, `tank_menu.gd`, `scenario_picker.gd`, `settings_panel.gd`,
`onboarding_runtime.gd`, `hud_controller.gd`, `sim_driver.gd`,
`residents_panel.gd`, `library_panel.gd`, `sound_panel.gd`, `mobile_hud.gd`,
`walkthrough.gd`, and the Steam/store copy.

**Format:** checkboxes; assume S–M unless flagged **(L)**. Mark `- [x]` as
items ship. One idea, one commit, one verification. Prefer fixing the existing
path over inventing a new panel.

## If this doc only does ten (do these first)

1. **#1 Care dock** — shipped (footer Water + Filter beside Feed).
2. **#41 Always-on controls legend** — shipped (footer hint = sacred verbs).
3. **#81 Desktop photo feedback** — shipped (toast + Reveal on all platforms).
4. **#121 Autosave ceremony** — shipped (quiet "Saved" when focused).
5. **#161 Settings Apply preview** — still open.
6. **#201 Unified Accessibility tab** — still open.
7. **#281 Calm desk mode up front** — still open.
8. **#361 Chip → meaning** — still open.
9. **#441 Death with dignity** — still open (partial memorial toasts exist).
10. **#521 First five minutes rewrite** — still open.

**Sequencing:** foundations above, then section order (journey → chrome → care →
watching → trust → long-run). One idea at a time.

---

## Section 1 — First five minutes: land soft (1–40)

*Grounding: `tank_menu.gd`, `scenario_picker.gd`, `walkthrough.gd`, coachmarks in `main.gd`.*

- [x] **1. Care dock.** Persistent Feed + Water + Filter verbs on the same strip — the keeper loop must be visible without a nudge. **(L)** — `_setup_care_dock` in `main.gd`; `do_water_change(0.25)` / `rinse_filter()`.
- [ ] **2. Delay coachmarks until first wonder.** Let the tank breathe 20–30 s before any chrome tutorial.
- [ ] **3. Empty-shelf warmth.** Empty tank shelf shows one living preview tank, not a void of buttons.
- [ ] **4. Beginner default path.** "New tank" lands Beginner Sandbox unless the player opts into the full scenario grid.
- [ ] **5. Scenario count pressure.** Collapse advanced scenarios behind "More worlds" so first choice is three, not twenty.
- [ ] **6. Guided start that ends in watching.** Guided flow's last step is "just watch for a minute" with chrome dimmed.
- [ ] **7. Skip-tutorial that isn't a trap.** Skipping walkthrough still leaves a one-line footer of the three verbs (orbit, feed, tap).
- [ ] **8. First feed guaranteed success.** First food drop always attracts at least one fish within 2 s — never a lonely flake.
- [ ] **9. First follow feels special.** First creature follow gets a soft PiP border pulse + name reveal, once.
- [ ] **10. Promise/docs sync.** Align README / store "how to feed" with click-water + FeedDock (kill ⌘+LMB drift).
- [ ] **11. Startle vs feed clarity.** Shift+tap glass vs click-water feed get distinct cursors for 60 s of first run.
- [ ] **12. Scenario spicy warnings.** Hard scenarios show "needs attention" badge before enter, not after a crash.
- [ ] **13. Name your tank at birth.** Optional tank name on create — shelf cards stop being anonymous timestamps.
- [ ] **14. First-session quit soft landing.** Quit on day one offers "keep this tank on the shelf" confirmation with thumbnail.
- [ ] **15. No LLM homework on minute one.** Guardian model consent never interrupts the first five minutes of a fresh tank.
- [ ] **16. Walking-speed camera.** First-run orbit sensitivity slightly lower until the player proves they can handle it.
- [ ] **17. Quiet chrome default.** First session starts with HUD dimmed harder; player discovers density later.
- [ ] **18. One emotional beat.** First successful feed triggers one guardian-or-caption line, then silence.
- [ ] **19. Scenario preview that moves.** Scenario cards show a tiny live/looped tank, not a still if performance allows.
- [ ] **20. "What is this game?" one sentence.** Info / first shelf line: *watch more than play; feed, follow, keep.*
- [ ] **21. Undo first panic.** First accidental glass tap / startle offers a one-shot "calm them" undo.
- [ ] **22. Don't open Settings first.** Rail never highlights Settings before Feed/Residents on a brand-new save.
- [ ] **23. Mobile first-run parity.** Mobile coachmarks cover pinch zoom + feed tap explicitly in the first minute.
- [ ] **24. Desktop feed dock discoverability.** FeedDock pulses once on first hover of the water column.
- [ ] **25. Tank shape without jargon.** Shape names use plain language ("tall jar", "wide desk") under technical names.
- [ ] **26. Saltwater warning.** Reef scenarios warn freshwater players once before they invent a disaster.
- [ ] **27. Load last tank one-click.** Shelf offers "Continue" as the biggest button when a recent save exists.
- [ ] **28. Crash recovery greeting.** After unclean exit, shelf says "we saved your tank" if autosave held.
- [ ] **29. No achievement spam.** First minutes never fire achievement toasts (if achievements ship).
- [ ] **30. Cursor affordance.** Cursor changes over water / creature / glass / UI — three readable modes.
- [ ] **31. First plant touch.** Tapping a plant in the first session shows a tiny "growing" whisper, not a genome wall.
- [ ] **32. Hide Design scape until second tank.** Advanced aquascape entry can wait; first tank is about life.
- [ ] **33. Walkthrough skip remembers.** Never re-ask walkthrough after an explicit skip (unless Reset Tips).
- [ ] **34. Tip budget.** At most one tip every 45 s in the first session — respect attention.
- [ ] **35. Fail-soft scenario load.** If a scenario fails to boot, fall back to Beginner with an apology, never a blank tree.
- [ ] **36. Audio fades in.** First boot eases ambient up over 3 s so the room doesn't bark.
- [ ] **37. Window focus kindness.** Alt-tab back doesn't blast a startle if the tank was calm.
- [ ] **38. Store ↔ first run.** Steam "play" lands the same soft path as GitHub first run — no special-case harshness.
- [ ] **39. First screenshot invite.** After ~3 minutes of calm watching, a single optional "capture this?" whisper.
- [ ] **40. First-five smoke.** Headless/scripted journey asserts Continue, feed success, and no LLM modal in first 300 s.

## Section 2 — Controls & discoverability (41–80)

*Grounding: `OnboardingLegibility`, `main.gd` input, FeedDock, mobile_hud.*

- [x] **41. Always-on controls legend.** Optional thin bottom strip: Orbit · Feed · Follow · Care · Photo — toggleable. **(L)** — footer `ControlsHint` + `_refresh_controls_hint`; cheat sheet lists Care.
- [ ] **42. Remappable keys.** Feed, photo, follow-next, care — in Settings, saved per user.
- [ ] **43. Hold-to-show legend.** Holding `?` shows bindings as long as held; release hides — no modal tax.
- [ ] **44. Gamepad glyph correctness.** Platform-correct button art for Steam Deck / DualSense / Xbox.
- [ ] **45. Mouse wheel zoom curve.** Softer near, faster far — stop the "telescope punch."
- [ ] **46. Orbit inertia settle.** Camera eases to rest instead of hard-stopping.
- [ ] **47. Double-click focus creature.** Double-click fish = follow; single click water = feed — teach in legend.
- [ ] **48. Right-click context whisper.** Right-click creature: Follow / Name / Favorite — three items max.
- [ ] **49. Escape stacks correctly.** Escape closes top panel only; second Escape dims chrome; third never quits without confirm.
- [ ] **50. Feed key vs digit confusion.** Food subtype 9/0 need labels on the dock, not only keyhints.
- [ ] **51. Accidental UI clicks.** Click-through protection: UI swallows clicks that would feed/startle.
- [ ] **52. Drag threshold.** Tiny mouse jitter while holding shouldn't orbit; raise slop to match mobile.
- [ ] **53. Pinch-to-zoom desktop trackpad.** Explicit support + legend entry for Mac trackpad pinch.
- [ ] **54. Space to pause clarity.** Pause freezes sim *and* shows a quiet PAUSED word — never ambiguous stillness.
- [ ] **55. Tab order.** Keyboard-only users can reach Feed, Care, Residents, Settings in a sane order.
- [ ] **56. Focus ring contrast.** Keyboard focus rings survive palette quantize (light edge + dark edge).
- [ ] **57. Tooltips with verbs.** Hover FeedDock: "Drop food where you click in the water."
- [ ] **58. Disabled control honesty.** Greyed actions say why ("tank at plant capacity").
- [ ] **59. Chord conflict audit.** No binding fights Steam overlay / OS screenshots without a note.
- [ ] **60. Middle-click pan.** Optional pan mode for people who hate orbit.
- [ ] **61. Reset camera.** One key returns to default comfortable framing.
- [ ] **62. Follow next/prev.** Cycle favorites with `[` `]` — desk watchers need it.
- [ ] **63. Locked cursor modes.** Optional mouselook for immersion freaks; default stays casual.
- [ ] **64. Gesture cheat sheet art.** One static image in Help: finger/mouse diagrams, not a paragraph.
- [ ] **65. Input recorder for bug reports.** Optional last-30s input log for "controls feel wrong" reports.
- [ ] **66. Sensitivity presets.** Gentle / Normal / Snappy camera — three buttons, not a raw float.
- [ ] **67. Invert Y optional.** For the half of humanity that needs it.
- [ ] **68. Click-water only when aimed at water.** Clicks on UI, frames, or out-of-tank never drop food.
- [ ] **69. Feed aim reticle.** Brief soft circle where food will land while holding feed mode.
- [ ] **70. Long-press mobile feed.** Distinguishes feed from camera drag without a mode button fight.
- [ ] **71. Haptics optional.** Soft rumble on feed/photo for gamepad; off by default for desk zen.
- [ ] **72. Sticky keys warning.** Accidental modifier sticks get a tiny HUD note.
- [ ] **73. Binding conflict toast.** Remap that steals Photo warns before save.
- [ ] **74. Locale-aware punctuation.** Shortcuts display with local keyboard symbols.
- [ ] **75. Help search.** Help panel search box finds "water change" → Care dock.
- [ ] **76. Coachmark re-run.** Settings → "Show tips again" without wiping the save.
- [ ] **77. Contextual binding hints.** When Care dock opens, show its keys once as ghosts.
- [ ] **78. No silent key swallow.** Unbound keys don't eat Steam big-picture chords.
- [ ] **79. Accessibility sticky keys compatible.** Remaps work with OS sticky keys.
- [ ] **80. Controls smoke.** Script asserts feed/care/photo bindings resolve and legend strings match.

## Section 3 — Care loop: water, filter, maintenance (81–120)

*Grounding: `sim_driver.do_water_change`, `rinse_filter`, `onboarding_runtime` nudges.*

- [x] **81. Desktop photo toast.** Show path + "Open folder" after F12 on desktop (stop early-returning toast). **(L)** — `_show_status_toast` + Reveal via `OS.shell_show_in_file_manager` on all platforms.
- [x] **82. Water change button.** One clear Care-dock control calling `do_water_change` with confirm for large %. — 25% from Care dock (large-% confirm still open).
- [x] **83. Filter rinse button.** Same dock; shows clog level as a simple bar before rinse. — button highlights when clogged; bar still open.
- [ ] **84. Care preview.** Hover Water Change: "nitrates ↓, temp blip, plants like this."
- [ ] **85. Care undo window.** 8 s undo after water change if the player panics.
- [ ] **86. Nudge → action deep link.** Tapping a water-change nudge focuses the Care dock button.
- [ ] **87. Maintenance calendar whisper.** After long runs, a quiet "filter's due" without alarm red.
- [ ] **88. Partial water change sizes.** 10% / 25% / 50% presets — technique matters (#899 chemistry doc can wait).
- [ ] **89. Temp-matched change.** Default water change matches tank temp; advanced can shock for science.
- [ ] **90. Visual siphon moment.** Brief hose/siphon cue during water change — ritual, not a spreadsheet.
- [ ] **91. Filter gunk visual.** Clog isn't only a number — media looks darker when due.
- [ ] **92. Overcare soft cap.** Spamming water changes has diminishing returns + gentle caption.
- [ ] **93. Undercare honesty.** Neglect shows in water chip *before* fish gasp — early warning.
- [ ] **94. Care from mobile.** Mobile HUD gains Water + Filter actions parity with desktop.
- [ ] **95. Root-tab rename.** If root tabs are care-ish, rename to Care language humans use.
- [ ] **96. Substrate vacuum optional.** Light mulm tidy tool with fertility tradeoff stated once.
- [ ] **97. Algae wipe glass.** Slow satisfying wipe gesture; algae returns honestly.
- [ ] **98. Plant trim in Care.** Scissors mode from Care dock, not buried in Aquascape only.
- [ ] **99. Dose fertilizer verb.** Optional advanced Care item with "less is more" default.
- [ ] **100. Care log.** Tiny journal of last 10 care actions — "what did I do yesterday?"
- [ ] **101. Care streak without gamification.** Optional quiet "you've been steady" — no badges required.
- [ ] **102. Crash recovery after care.** Care actions force an autosave checkpoint.
- [ ] **103. Confirm destructive care.** 90% water change needs typed confirm or hold.
- [ ] **104. Care disabled underwater photo mode.** Letterbox photo mode doesn't hide Care forever.
- [ ] **105. Teach nitrogen in one metaphor.** "The tank's lungs and pantry" — one caption, not a textbook.
- [ ] **106. Filter type plain names.** Sponge / HOB / canister as feelings, not SKUs.
- [ ] **107. Aeration toggle reachable.** Bubbler on/off without Advanced archaeology.
- [ ] **108. Heater visible state.** When heater fights a cold change, show a tiny coil cue.
- [ ] **109. Care tooltip on chips.** Water chip hover: "Tap Care to change water."
- [ ] **110. First water change celebration.** Soft clarity bloom once — reinforce the verb.
- [ ] **111. Saltwater care fork.** Reef care verbs differ; don't show freshwater rinse on reef.
- [ ] **112. Care difficulty mode.** Forgiving / Normal / Rigorous rates — matches chemistry wish without rewriting sim.
- [ ] **113. Pause-safe care.** Care works while paused (preview) or clearly says it doesn't.
- [ ] **114. Multiplayer-proof language.** Even single-player: "your tank" not "the simulation."
- [ ] **115. Care accessibility.** Large hit targets; screen reader labels for Water/Filter.
- [ ] **116. Care sound design.** Soft pour / rinse — never a UI beep.
- [ ] **117. Care after away.** Away recap offers one suggested care action with a button.
- [ ] **118. No care popups during photo.** Photo mode suppresses care modals.
- [ ] **119. Care tutorial card once.** One card: Feed · Water · Watch — dismiss forever.
- [ ] **120. Care smoke.** Assert Care dock calls `do_water_change` / `rinse_filter` and logs an entry.

## Section 4 — Save, load, photo, share (121–160)

*Grounding: autosave in `main.gd`, `_take_photo`, tank shelf cards, `TankSaves`.*

- [x] **121. Autosave ceremony.** Tiny checkmark / "Saved" ghost every autosave — 1.2 s, corner, no block. **(L)** — focused-window autosave shows `_show_status_toast("Saved")`.
- [ ] **122. Manual save.** Explicit Save Now in System menu + binding.
- [ ] **123. Save thumbnail freshness.** Shelf cards refresh thumbnail on save, not only on quit.
- [ ] **124. Photo open folder.** Desktop photo toast includes Reveal in Finder/Explorer.
- [ ] **125. Photo album in-game.** Last 20 shots browsable without leaving the tank.
- [ ] **126. Timelapse findability.** T key explained in legend + post-export toast with path.
- [ ] **127. Cloud save story.** If Steam Cloud, say so on shelf; if not, don't imply it.
- [ ] **128. Save conflict resolve.** Two devices / copies: pick newer vs keep both.
- [ ] **129. Corrupt save repair UX.** `save_repair` results in human language, not stack traces.
- [ ] **130. Export tank gift.** Export a shareable tank file for a friend (local).
- [ ] **131. Import tank gift.** Import with capacity warnings.
- [ ] **132. Screenshot naming.** Files include tank name + date — sortable memories.
- [ ] **133. Photo without UI.** Default F12 hides chrome; optional with-UI variant.
- [ ] **134. Clipboard copy photo.** One click copies image for Discord/Steam chat.
- [ ] **135. Steam screenshot hook.** Optional Steam overlay screenshot also archives in-game album.
- [ ] **136. Quit save guarantee.** Quit never races autosave; block quit until flush.
- [ ] **137. Power-loss honesty.** On next boot, "restored from autosave at …"
- [ ] **138. Version migrate toast.** Old save upgraded: one sentence what changed.
- [ ] **139. Delete save undo.** 10 s undelete from shelf.
- [ ] **140. Duplicate tank.** Clone a save to experiment safely.
- [ ] **141. Read-only museum mode.** Open a save without autosaving over it.
- [ ] **142. Photo letterbox optional.** Some players hate bars — toggle.
- [ ] **143. Flash intensity.** Photo flash strength slider for photosensitive comfort.
- [ ] **144. Storage meter.** "Screenshots using 400MB" with cleanup button.
- [ ] **145. Missing media graceful.** Broken thumbnail doesn't blank the whole shelf.
- [ ] **146. Save slot names.** Rename saves on shelf without opening them.
- [ ] **147. Pin favorite saves.** Pinned row above recents.
- [ ] **148. Sort shelf.** Recent / Name / Hours watched.
- [ ] **149. Hours watched stat.** Shelf glance shows time with tank — vanity that bonds.
- [ ] **150. Photo mode grid.** Thirds overlay toggle while framing.
- [ ] **151. Burst photo.** Hold F12 for 3-shot burst during a wonder.
- [ ] **152. Fail toast.** If write fails (disk full), scream politely with action.
- [ ] **153. Android share sheet.** Mobile photo → OS share.
- [ ] **154. Linux path clarity.** xdg pictures dir documented in toast.
- [ ] **155. Timelapse length presets.** 30s / 2m / 10m of tank time.
- [ ] **156. Save before scenario switch.** Switching worlds prompts save.
- [ ] **157. Autosave interval setting.** 2 / 5 / 10 min — Advanced but findable.
- [ ] **158. Photo EXIF tank note.** Embed tank name in metadata when possible.
- [ ] **159. Wallpaper export.** One-click desktop wallpaper size export (ties GOALS #50 later).
- [ ] **160. Save/photo smoke.** Headless asserts save flush, photo write, toast strings non-empty on desktop path.

## Section 5 — Settings without fear (161–200)

*Grounding: `settings_panel.gd`, `render_panel.gd`, `TankSaves.is_active_save_compatible`.*

- [ ] **161. Apply preview.** Diff of what Apply will change before reload; cancel stays. **(L)**
- [ ] **162. Dangerous Apply badge.** Substrate/preset incompat: red plain-English warning.
- [ ] **163. Soft settings vs hard.** Visual/audio apply live; world-rewriting settings gated.
- [ ] **164. Settings search.** Filter tabs by query ("font", "bloom", "guardian").
- [ ] **165. Reset this tab.** Per-tab restore defaults.
- [ ] **166. Settings undo.** Last Apply revert for 30 s.
- [ ] **167. No surprise stocking wipe.** Stocking edits preview population delta.
- [ ] **168. Advanced is advanced.** Move potato/fps next to Quality, not buried only in Advanced.
- [ ] **169. Plain labels.** Replace internal enum names with human phrases.
- [ ] **170. Immediate audio.** Volume sliders audible while dragging.
- [ ] **171. Graphics presets.** Beautiful / Balanced / Potato — one click.
- [ ] **172. Why did my save break?** If Apply invalidates save, offer Duplicate-then-Apply.
- [ ] **173. Settings deep links.** From a nudge "open lighting settings" jumps to the control.
- [ ] **174. Restart-required list.** Collect "needs restart" into one checklist, not popups.
- [ ] **175. Tooltips with defaults.** Every slider shows default on hover.
- [ ] **176. Locked by scenario.** Scenario-locked options say which scenario unlocked them.
- [ ] **177. Import/export settings.** Dotfile for the obsessive.
- [ ] **178. Per-tank overrides.** Lighting can be tank-local without changing global defaults.
- [ ] **179. Accessibility separate.** See #201 — remove duplicates from Advanced.
- [ ] **180. AI tab calm.** Guardian settings use consent language, not ML jargon first.
- [ ] **181. Model download progress.** Slim builds: clear % + cancel + size.
- [ ] **182. Offline mode.** Explicit "no network features" for paranoid LAN parties.
- [ ] **183. Validation on blur.** Bad numbers clamp with a whisper, not a crash.
- [ ] **184. Settings panel remember tab.** Reopen on last tab.
- [ ] **185. Compact mode.** Settings density toggle for Steam Deck small screen.
- [ ] **186. Apply doesn't steal focus.** Tank keeps input focus policy sane after Apply.
- [ ] **187. Preview lighting live.** Light yaw/color preview without Apply when safe.
- [ ] **188. Stocking capacity meter.** Before confirm, show soft/hard caps.
- [ ] **189. Fauna personality defaults.** Bold/shy global bias explained as "tank mood."
- [ ] **190. Hide unfinished.** Feature flags don't show dead toggles in release.
- [ ] **191. Settings changelog.** "New in this version" pin at top after update.
- [ ] **192. Confirm language.** Buttons say Save lighting / Reload tank — never OK/Cancel only.
- [ ] **193. Escape discards safely.** Escape with dirty soft settings asks; dirty hard settings always asks.
- [ ] **194. Controller settings nav.** Full gamepad traversal of settings.
- [ ] **195. High contrast settings chrome.** Settings readable on bright aquariums.
- [ ] **196. Units.** °C/°F toggle beside temp; persist.
- [ ] **197. Time format.** 12/24h for journals and timestamps.
- [ ] **198. Reduced data.** Disable optional downloads globally.
- [ ] **199. Settings snapshot for bug reports.** Copy diagnostics JSON one click.
- [ ] **200. Settings smoke.** Assert safe Apply path doesn't wipe save; dangerous path prompts.

## Section 6 — Accessibility & comfort (201–240)

*Grounding: font scale, reduced motion, colorblind in render_panel, flash.*

- [ ] **201. Unified Accessibility tab.** Font, motion, colorblind, flash, haptics, captions — one home. **(L)**
- [ ] **202. Font scale live preview.** Scale UI without "reopen panels" footgun; fix layout reflow.
- [ ] **203. Colorblind presets moved.** From Render → Accessibility; Render keeps link.
- [ ] **204. Reduced motion completeness.** Audit every tween/sway/ripple respects the flag.
- [ ] **205. Photosensitivity.** Disable photo flash / lightning / pearl glitter bursts.
- [ ] **206. Screen reader labels.** Critical buttons expose accessible names.
- [ ] **207. Captions for guardian voice.** Optional captions for spoken lines.
- [ ] **208. Dyslexia-friendly font option.** Alternate face from shipped fonts if license allows.
- [ ] **209. UI contrast checker.** Dev/QA mode flags low-contrast labels on quantized BG.
- [ ] **210. Hold-to-confirm.** Destructive actions support hold instead of click-spam.
- [ ] **211. Sticky hover time.** Tooltips appear slightly faster when Accessibility asks.
- [ ] **212. Color is not only signal.** Care urgency uses icon + text, not red alone.
- [ ] **213. Motion sickness camera.** Flatten orbit / reduce bob options.
- [ ] **214. One-hand mobile.** Primary verbs reachable by thumb zone.
- [ ] **215. Remap for one-hand desktop.** Cluster feed/care near each other.
- [ ] **216. Audio mono mix.** Optional mono for single-ear / hearing setups.
- [ ] **217. Separate music/SFX/voice.** Already partly there — expose clearly in Accessibility too.
- [ ] **218. Blink-free HUD.** No looping opacity pulses for critical info.
- [ ] **219. Large care targets.** 48×48 dp minimum for Water/Feed on all platforms.
- [ ] **220. Keyboard-only photo.** Full capture path without mouse.
- [ ] **221. Focus not trapped.** Closing modal returns focus to prior control.
- [ ] **222. Timeout extensions.** Nudge cards don't expire too fast for readers.
- [ ] **223. Language hooks.** Even before localization, wrap new strings in `tr()`.
- [ ] **224. Content warnings.** Optional: hide death visuals / show soft despawn.
- [ ] **225. Calm color mode.** Desaturate UI chrome; leave tank art alone.
- [ ] **226. Cursor scale.** Larger cursor for high-DPI + visual impairment.
- [ ] **227. Subtitles background.** Caption plate with opaque scrim.
- [ ] **228. No seizure patterns.** Audit strobing algae/lightning; clamp frequency.
- [ ] **229. Cognitive load mode.** Hide Advanced tabs entirely until toggled.
- [ ] **230. Remember a11y globally.** Accessibility is user-level, not per-tank.
- [ ] **231. First-run a11y ask.** Optional "make text bigger?" before first tank — once.
- [ ] **232. Voiceover pause.** Opening menus pauses guardian speech.
- [ ] **233. Haptic off master.** One switch kills all rumble.
- [ ] **234. Test tone.** Hearing check button in Accessibility.
- [ ] **235. Colorblind proof of chips.** Mood/water/alert distinct under deuteranopia sim.
- [ ] **236. Reduced transparency.** Solid panels option.
- [ ] **237. Animation speed.** Global 0.5×–1.5× for UI tweens only.
- [ ] **238. Auto-pause on focus loss.** Optional for readers who alt-tab mid-tooltip.
- [ ] **239. Accessibility help page.** Short in-game page linking every a11y control.
- [ ] **240. A11y smoke.** Assert reduced-motion kills listed tweens; font scale reflows Care dock.

## Section 7 — HUD, chips & "what does this mean?" (241–280)

*Grounding: `hud_controller`, water/mood/alert chips, captions.*

- [ ] **241. Chip plain English.** Every chip expands to one sentence a non-aquarist gets.
- [ ] **242. Numbers optional.** Mode: icons only / icons+words / icons+numbers.
- [ ] **243. Alert priority.** One alert at a time; queue the rest.
- [ ] **244. Alert without panic red.** Urgent uses amber + icon; reserve red for dying.
- [ ] **245. Mood chip teaches fish.** "Skittish — something startled them."
- [ ] **246. Water chip teaches chemistry.** "Heavy — consider a small water change."
- [ ] **247. Dismissible captions.** Captions never stack into a wall.
- [ ] **248. Caption rate limit.** Max one ambient caption / 20 s unless critical.
- [ ] **249. HUD dim curve.** Idle dim slower; mouse-near restores instantly.
- [ ] **250. Hide HUD hotkey.** Clean watch mode; legend still available on hold-?.
- [ ] **251. PiP clarity.** Follow PiP labeled with name + species.
- [ ] **252. PiP click-through.** Clicking PiP focuses creature, doesn't feed.
- [ ] **253. Stat flicker die.** Values don't jitter every frame; show smoothed.
- [ ] **254. Units on chips.** ppm / °C visible or explained once.
- [ ] **255. Empty chip states.** "—" means unknown, not zero — say so.
- [ ] **256. First chip tap tutorial.** Once: "chips explain the tank."
- [ ] **257. Mobile chip parity.** Same meanings, larger tap areas.
- [ ] **258. Alert deep link.** Alert tap opens the relevant Care/Settings control.
- [ ] **259. No overlapping toasts.** Photo / save / alert share one toast lane.
- [ ] **260. Chronicle toggle.** Optional scrollback of recent captions.
- [ ] **261. Color-blind chip patterns.** Shape + hatch, not hue alone.
- [ ] **262. Night HUD.** Night mode softens HUD emissives.
- [ ] **263. Pause HUD.** Paused state unmistakable.
- [ ] **264. Performance chip optional.** FPS only if enabled — hide from zen default.
- [ ] **265. Biomass vanity.** Optional "life in the tank" soft count for curious keepers.
- [ ] **266. Time-of-day chip.** Dawn/day/dusk/night word for atmosphere learners.
- [ ] **267. Mute captions.** Separate from mute audio.
- [ ] **268. HUD scale independent.** Scale HUD without scaling world UI fonts if needed.
- [ ] **269. Corner collision.** HUD never covers Care dock / FeedDock.
- [ ] **270. Safe margins.** Notches / rounded displays respected.
- [ ] **271. Tooltip delay consistency.** Same delay everywhere.
- [ ] **272. Right-rail overflow.** Too many buttons → overflow menu, don't shrink into mush.
- [ ] **273. Icon metaphor test.** Playtest: 8/10 guess Feed/Care/Photo icons.
- [ ] **274. Alert sound optional.** Soft chime default off for desk tanks.
- [ ] **275. Critical alert sticky.** Dying O₂ stays until acknowledged.
- [ ] **276. Chip history sparkline.** Tiny 5-min trend on expand — teaches drift.
- [ ] **277. Localization length.** Chips tolerate German-length strings without clip.
- [ ] **278. HUD screenshot clean.** Hide HUD binding documented next to photo.
- [ ] **279. Coachmark vs HUD z-order.** Coachmarks never trap under chips.
- [ ] **280. HUD smoke.** Assert chip expand strings exist for mood/water/alert.

## Section 8 — Sound, calm & desk zen (281–320)

*Grounding: `sound_panel.gd`, ambient day/night, music dance.*

- [ ] **281. Calm desk mode.** One shelf/settings toggle: low motion UI, soft ambient, captions rare. **(L)**
- [ ] **282. First-run audio choice.** Calm / Rich / Mute — three big buttons.
- [ ] **283. Sound Studio later.** Don't push mixer on day one; gate behind "Customize sound."
- [ ] **284. Vibe presets first.** When Studio opens, presets row is above sliders.
- [ ] **285. Music ducking.** Guardian speech ducks music automatically.
- [ ] **286. Night volume curve.** Auto-quiet after local evening if enabled.
- [ ] **287. Mute while screenshot.** Optional.
- [ ] **288. Per-category defaults.** Sensible factory: ambient up, UI click near zero.
- [ ] **289. No default festival.** Music-dance off until opted in.
- [ ] **290. Spotify failure grace.** Sync fail → local ambient, one quiet note.
- [ ] **291. Click sound diet.** Fewer UI clicks; more water.
- [ ] **292. Feed sound satisfaction.** Soft plink distinguishable from UI.
- [ ] **293. Bubbler distance attenuate.** Loud only when camera near.
- [ ] **294. Silence is a feature.** "Mute all but water" preset.
- [ ] **295. Device change recover.** Unplug headset doesn't stick muted forever.
- [ ] **296. Latency note.** Bluetooth lag warning for rhythm features.
- [ ] **297. Visualizer optional.** Studio meters hidden in Calm.
- [ ] **298. Caption for important audio.** Filter alarms get text if muted.
- [ ] **299. Volume remember per output.** Headphones vs speakers if OS allows.
- [ ] **300. Start muted respectful.** If OS session muted, don't unmute proudly.
- [ ] **301. Ambient crossfade.** Day↔night crossfade without dip to zero.
- [ ] **302. Species quiet hours.** Optional: less splash at night.
- [ ] **303. Test playlist.** One button plays a safe preview bed.
- [ ] **304. Loudness normalize.** Prevent one SFX slamming the bed.
- [ ] **305. Haptic linked to SFX.** If rumble on, match feed plink — or neither.
- [ ] **306. Mute when unfocused.** Optional auto-mute on alt-tab.
- [ ] **307. Deck default calm.** Steam Deck profile starts Calm desk mode.
- [ ] **308. Accessibility flash audio.** Replace strobes with audio cues when motion reduced.
- [ ] **309. Journal read-aloud optional.** Long journal entries can speak.
- [ ] **310. Sound credits.** Where samples came from — respect + curiosity.
- [ ] **311. Compression for shared space.** "Office" preset reduces dynamic range.
- [ ] **312. No voice by surprise.** Guardian voice off until consent / Calm allows text-only.
- [ ] **313. Mixer reset.** Studio one-click factory.
- [ ] **314. Per-tank vibe.** This tank jazz, that tank silence.
- [ ] **315. Loud cue budget.** Max one attention sound / minute.
- [ ] **316. Ear fatigue reminder.** Optional 2-hour soft "stretch" whisper — off by default.
- [ ] **317. Reverse stereo fix.** Detect weird setups? At least a swap-LR toggle.
- [ ] **318. Music bed without beat games.** Default beds ignore dance systems.
- [ ] **319. Sound onboarding card.** One card explaining Calm vs Studio.
- [ ] **320. Calm smoke.** Assert Calm mode forces dance off + caption rate low.

## Section 9 — Feeding & creature interaction (321–360)

*Grounding: FeedDock, `_drop_food_at_cursor`, follow/pick, grazing.*

- [ ] **321. Food type labels.** Flake / wafer / freeze-dried named on dock with who likes what.
- [ ] **322. Overfeed whisper.** Soft "that's plenty" before the tank clouds — teach restraint.
- [ ] **323. Feed cooldown feel.** Visible but gentle meter; not a hard silent ignore.
- [ ] **324. Target feed.** Hold aim on a shy fish to feed near them without startle.
- [ ] **325. Sinking vs floating clarity.** Food behavior matches label; tooltip shows path.
- [ ] **326. Shrimp dinner.** Occasional cue that wafers help the cleanup crew.
- [ ] **327. No feed through glass misclick.** Clicks on frame don't spawn food outside water.
- [ ] **328. Follow from Residents.** Tap name → camera eases to them.
- [ ] **329. Favorite star.** Star in PiP and Residents; cycle favorites (#62).
- [ ] **330. Rename frictionless.** Inline rename on follow; Enter commits, Esc cancels.
- [ ] **331. Auto-name veto.** One-tap reroll name without opening Library.
- [ ] **332. Hand shadow optional.** Cursor-as-presence soft shadow on glass for bond feel (no webcam required).
- [ ] **333. Tap startle radius preview.** Ghost ripple before release when Shift held.
- [ ] **334. Double-tap mobile follow.** Documented and reliable.
- [ ] **335. Drag-select? No.** Keep interactions singular — multi-select is not this game.
- [ ] **336. Creature tooltip.** Hover: name, species, mood word — 3 tokens max.
- [ ] **337. Hidden fish finder.** "Where's Moss?" from Residents flies camera gently.
- [ ] **338. Feed animation readability.** Flakes readable at potato resolution.
- [ ] **339. Snails get love.** Tap snail shows a tiny personality line sometimes.
- [ ] **340. Don't feed the dead.** Obvious, but handle gracefully if click races death.
- [ ] **341. Breeding privacy.** Optional dim chrome when fry appear — wonder first.
- [ ] **342. Fry protection tip.** Once: "big fish may hunt — plants help."
- [ ] **343. Territorial warning.** Before stocking aggressors, plain warning.
- [ ] **344. Click-accuracy assist.** Soft magnet to nearest creature when following intent.
- [ ] **345. PiP hide.** Dismiss follow without losing favorite.
- [ ] **346. Feed count today.** Optional soft counter for mindful keepers.
- [ ] **347. Fasting day mode.** One toggle pauses hunger penalties for display tanks.
- [ ] **348. Species diet icons.** Library entries show diet icons used by FeedDock.
- [ ] **349. Cursor feed mode sticky.** Optional sticky feed mode with Esc to exit.
- [ ] **350. Interaction tutorial replay.** "Practice feeding" sandbox tip.
- [ ] **351. No accidental rename.** Require deliberate rename gesture.
- [ ] **352. Touch-safe startle.** Mobile startle is a distinct button, not a mis-tap.
- [ ] **353. Creature blocked by UI.** Picking ignores dead zones under docks.
- [ ] **354. School-aware follow.** Following one highlights school faintly.
- [ ] **355. Lurk mode.** Camera follow without PiP chrome.
- [ ] **356. Gift food animation.** Rare: fish does a little dance after feed — delight, rare.
- [ ] **357. Interaction log.** Optional: last fed / last followed timestamps on Residents.
- [ ] **358. Accessibility hold-feed.** Hold space to arm feed for motor impairment.
- [ ] **359. Fair hitboxes.** Tiny shrimp still tappable.
- [ ] **360. Interaction smoke.** Feed armed only over water; follow pick ignores UI rects.

## Section 10 — Watching: camera, framing, presence (361–400)

*Grounding: orbit camera, isometric views, photo mode, idle dim.*

- [ ] **361. Chip → Care meaning.** Water chip tap opens Care with the right verb highlighted. **(L)**
- [ ] **362. Default hero framing.** First camera frame always a postcard composition.
- [ ] **363. Saved camera slots.** Three bookmarks per tank (desk / detail / wide).
- [ ] **364. Isometric without nausea.** Iso easing + reduced motion path.
- [ ] **365. Auto-tour idle.** Optional slow Ken Burns when AFK — off in Calm.
- [ ] **366. Focus plane.** Soft DOF optional for screenshots only.
- [ ] **367. Collision with glass.** Camera never clips ugly through silicone seams.
- [ ] **368. Room quieter than tank.** If room still screams, dim room lights (VISUAL_POLISH debt).
- [ ] **369. Watch timer.** Optional gentle session time — vanity, hideable.
- [ ] **370. Screensaver etiquette.** Fullscreen idle doesn't burn a static HUD pixel.
- [ ] **371. Multi-monitor.** Prefer start on the monitor the window is on.
- [ ] **372. Ultrawide safe.** HUD margins for 21:9 / 32:9.
- [ ] **373. Portrait mobile.** Tank letterboxes gracefully; docks reflow.
- [ ] **374. Zoom to cursor.** Zoom toward pointer, not frame center only.
- [ ] **375. Follow smoothing.** Less motion sickness; more documentary.
- [ ] **376. Cutaway moment.** Rare: camera finds a wonder without stealing control (#993 law from plants — same spirit).
- [ ] **377. Manual framing guides.** Photo thirds / golden optional.
- [ ] **378. Black bars taste.** Letterbox color matches UI theme.
- [ ] **379. Camera reset double-tap.** Homing key documented.
- [ ] **380. Top-down clarity.** Topdown mode keeps feed/care usable.
- [ ] **381. Parallax restraint.** Background parallax optional off.
- [ ] **382. Fog density user.** Soft slider for "mystery vs clarity."
- [ ] **383. Night watching.** Moonlight mode one toggle from HUD.
- [ ] **384. Sunrise alarm optional.** Tank wakes with real dawn if linked to clock.
- [ ] **385. Presence indicator.** Soft "you're here" for fish glance system — no webcam needed.
- [ ] **386. Away dim.** When unfocused, dim and quiet (battery + zen).
- [ ] **387. Resume fade.** Focus return fades light/audio up.
- [ ] **388. Tripod mode.** Lock camera completely for timelapse.
- [ ] **389. Handheld micro-sway off.** Pure static for photosensitive + potato.
- [ ] **390. Framing presets per scenario.** Jar vs long tank default differently.
- [ ] **391. Click-off UI refocuses tank.** Obvious but often broken — audit.
- [ ] **392. Camera help card.** Orbit diagrams once.
- [ ] **393. No camera punch on UI open.** Panels don't yank FOV.
- [ ] **394. Follow lost target.** If fish dies mid-follow, ease out kindly (#441).
- [ ] **395. Spectator UI.** Watch-only profile: hide edit tools.
- [ ] **396. Desk aspect.** Remembers window size per machine.
- [ ] **397. Snap to front glass.** One key squares the view for classic aquascape look.
- [ ] **398. Zoom limits honest.** Soft bump at limits, not hard wall.
- [ ] **399. Camera debug off in release.** No accidental free-cam cheats exposed.
- [ ] **400. Camera smoke.** Assert bookmarks save/load; follow release on target free.

## Section 11 — Death, loss & hard moments (401–440)

*Grounding: fish lifecycle, plant death, waste, alerts.*

- [ ] **401. Death with dignity.** No silent despawn — short animation + quiet name line. **(L)**
- [ ] **402. Cause in plain words.** "Oxygen ran low overnight" > "O2<x."
- [ ] **403. Memorial note.** Optional journal line; never a dunk meme.
- [ ] **404. Mass death handling.** One summary, not 40 toasts.
- [ ] **405. Warn before wipeout.** Predictive alert when trajectory is fatal.
- [ ] **406. Soft mode deaths.** Accessibility: fade instead of belly-up if preferred.
- [ ] **407. Corpse cleanup option.** Auto vs manual — player taste.
- [ ] **408. Plant melt explanation.** Crypt melt teaches patience, not failure.
- [ ] **409. Rehome fantasy.** Optional "gift to Library memory" instead of delete.
- [ ] **410. Undo stocking mistake.** Short window after adding incompatible fish.
- [ ] **411. Aggression foreshadow.** Chase intensity caption before the kill.
- [ ] **412. Fry loss honesty.** "Most fry don't make it" once — set expectations.
- [ ] **413. Filter crash drama.** Equipment fail is rare, telegraphed, recoverable.
- [ ] **414. Power outage scenario.** Optional challenge; default tanks don't fake cruelty.
- [ ] **415. Grief without gamification.** No "death points."
- [ ] **416. Save scum temptation.** Museum/duplicate (#140) reduces rage-reloads — support it.
- [ ] **417. Hardcore optional.** Permadeath tank flag for masochists; off by default.
- [ ] **418. Recovery arcs.** After crash, visible healing path (#912 spirit).
- [ ] **419. Name persists in journal.** Dead favorites remain searchable.
- [ ] **420. Condolence once.** Guardian may notice once — never nag.
- [ ] **421. Accidental cull confirm.** Aquascape delete selected fauna confirms.
- [ ] **422. Disease? If present, readable.** Symptoms before death; cure path clear.
- [ ] **423. Senescence vs neglect.** Old age death wording differs from neglect.
- [ ] **424. Shrimp/snail deaths count.** Small lives matter in the log.
- [ ] **425. Pause on critical.** Optional auto-pause when fatal alert fires.
- [ ] **426. Teach without blame.** Copy avoids "you killed" unless Hardcore.
- [ ] **427. Aftermath care.** Death alert offers Water Change button.
- [ ] **428. Body physics taste.** Toggle simplified remains.
- [ ] **429. Soundtrack dip.** Brief respectful duck — not a stinger.
- [ ] **430. Photo of the living.** Nudge to photograph favorites while alive — once, kind.
- [ ] **431. Lineage continues.** Children noted when a parent dies.
- [ ] **432. Empty tank after collapse.** Offer restart / recover backup / sit with emptiness.
- [ ] **433. No ad timing.** Never pair loss with upsell (future-proof).
- [ ] **434. Accessibility skip animation.** Jump to memorial text.
- [ ] **435. Moderation of gore.** Pixel-art remains suggestive, not gross.
- [ ] **436. Multi-cause.** If several factors, list top two only.
- [ ] **437. Time-to-fail estimate.** "About 20 minutes unless you act" when sure.
- [ ] **438. Practice tank.** Sandbox where death is reversible for learning.
- [ ] **439. Respectful notifications.** OS notify only if enabled; never for every snail.
- [ ] **440. Death smoke.** Assert death emits journal cause string + single toast path.

## Section 12 — Residents, Library, naming, bond (441–480)

*Grounding: `residents_panel.gd`, `library_panel.gd`, `creature_naming.gd`.*

- [ ] **441. Death notification restraint already noted — Residents shows living first.** Dead section collapsed by default.
- [ ] **442. Residents search.** Find by name/species/favorite.
- [ ] **443. Residents sort.** Name / age / mood / last fed.
- [ ] **444. Empty Residents kindness.** "Nobody here yet" + Add creature CTA.
- [ ] **445. Library onboarding.** First open: "this is your discovered life" — 2 sentences.
- [ ] **446. Library ≠ Creator dump.** Separate Discoveries from Creator tools visually.
- [ ] **447. Name quality.** Reroll names until taste clicks; history of last 5.
- [ ] **448. Name uniqueness soft.** Warn duplicate names, allow anyway.
- [ ] **449. Pronouns? Skip.** Don't force identity UI; keep names poetic.
- [ ] **450. Favorite limit?** Soft pin top 12 for cycle keys.
- [ ] **451. Lineage view entry.** From a fish → family tree without Library maze.
- [ ] **452. Portrait cards.** Residents show tiny silhouette/portrait.
- [ ] **453. Mood words shared.** Same lexicon as chips — no synonym soup.
- [ ] **454. Hide stats mode.** Bond-first: names + one feeling.
- [ ] **455. Gift name from journal.** Click highlighted name to follow.
- [ ] **456. Import/export creature.** Share a genome file with a friend.
- [ ] **457. Library search speed.** Instant filter on large discoveries.
- [ ] **458. Tagging.** Custom tags: "shy", "showgirl", "trouble."
- [ ] **459. Notes field.** 140-char keeper note per creature.
- [ ] **460. Last seen camera.** Jump to last known area if lost in plants.
- [ ] **461. Breeding pair hint.** Soft "these two keep company" — not eugenics UI.
- [ ] **462. Don't expose raw genome.** Advanced disclosure behind toggle.
- [ ] **463. Mobile Residents.** Full parity list + follow.
- [ ] **464. Keyboard Residents.** Arrow through list, Enter follow.
- [ ] **465. Bulk favorite.** Shift-select stars for a school.
- [ ] **466. Archive tank mates.** Remember transferred/rehomed.
- [ ] **467. Naming cultures.** Optional name packs (river, star, soft vowels).
- [ ] **468. Censor list.** Block accidental rude autogen names.
- [ ] **469. Rename plants too.** Beloved swords deserve names (#939 naturalism spirit).
- [ ] **470. Bond meter? No.** Keep familiarity invisible; show behavior instead.
- [ ] **471. Familiarity teach-once.** "They come closer when you feed near them."
- [ ] **472. Residents performance.** Virtualized list for 200+ shrimp worlds.
- [ ] **473. Open from alert.** "Moss is stressed" → Residents row highlighted.
- [ ] **474. Close returns to follow.** Panel close keeps PiP if was following.
- [ ] **475. Library image privacy.** Local only; no upload.
- [ ] **476. Discovery celebration quiet.** New species: soft stamp, not fireworks every time.
- [ ] **477. Compare two.** Side-by-side two fish traits for curious keepers.
- [ ] **478. Export family tree image.** Shareable PNG of lineage.
- [ ] **479. Accessibility names.** Screen reader reads name + species + mood.
- [ ] **480. Residents smoke.** Search/filter/follow from list; notes persist save/load.

## Section 13 — Performance feel (not just FPS) (481–520)

*Grounding: potato tier, perf governor, battery saver, Advanced fps cap.*

- [ ] **481. Potato discoverable.** First stutter offers "Make it smoother?" → Potato. **(L)**
- [ ] **482. Battery saver one-tap.** Especially macOS / Deck / Android.
- [ ] **483. Thermal honesty.** Soften load before the OS throttles into sludge.
- [ ] **484. Quality vs mind.** Explain if AI minds reduce under load — no silent stupidity.
- [ ] **485. Hitch attribution.** Optional: "saving…" / "compiling shaders…" banners.
- [ ] **486. Shader warmup.** First-run compile progress instead of multi-second freeze.
- [ ] **487. Population governors visible.** When soft-capped, tell the keeper why births paused.
- [ ] **488. Streamer mode.** Hides names/IPs/debug; locks FPS; disables risky overlays.
- [ ] **489. Background FPS cap.** Default low when unfocused.
- [ ] **490. Docked Deck profile.** Fan/performance defaults sensible.
- [ ] **491. Resolution scale.** 50–100% render scale without changing UI scale.
- [ ] **492. Fish count estimate.** Settings stocking warns when over perf budget.
- [ ] **493. Spillover plants.** At capacity, say "garden is full" not fail silently (#601).
- [ ] **494. Memory warning.** Large albums / timelapses warn before OOM.
- [ ] **495. Long-session leak watch.** Dev metric; release soft cleanup tips.
- [ ] **496. Sim speed ≠ watch speed.** If fast-forward exists, label clearly; default 1×.
- [ ] **497. Pause is free.** Pause drops GPU work aggressively.
- [ ] **498. Potato still pretty.** Acceptance: potato must remain cute, not broken.
- [ ] **499. Mobile thermals.** Auto Calm + potato outdoors in sun (temp if available).
- [ ] **500. Perf telemetry opt-in.** Anonymous hitch reports — off by default.
- [ ] **501. VSync options.** On / off / adaptive — explained.
- [ ] **502. Frame pacing.** Prefer stable 30 over jumpy 50–60 on weak machines.
- [ ] **503. Reduce bloom first.** Auto quality steps bloom/DOF before killing fish minds.
- [ ] **504. User override.** "I know my PC" unlocks higher than auto.
- [ ] **505. Startup splash short.** Don't make people wait on a logo for the tank.
- [ ] **506. Asset streaming.** Big models (LLM) never block first frame of tank.
- [ ] **507. Disk hitch.** Autosave on thread; see #121 ceremony only when done.
- [ ] **508. Audio underrun.** Fail soft; don't freeze the sim.
- [ ] **509. Network optional.** No online check on boot critical path.
- [ ] **510. Perf HUD friendly.** If shown, color-blind safe + movable.
- [ ] **511. Explain FPS cap.** "Caps heat and battery; tank still lives."
- [ ] **512. Scenario perf tags.** "Heavy" scenarios badged on picker.
- [ ] **513. Shrink particles.** Quality step reduces pearls/waste motes first.
- [ ] **514. Shadow policy.** Soft shadows optional; potato off.
- [ ] **515. UI at 60, world at 30.** If needed, decouple for feel.
- [ ] **516. Long compile once.** Cache shader cache across runs; tell user first time.
- [ ] **517. Cleanup tool.** "Free space / clear caches" in System.
- [ ] **518. Benchmark scene.** Optional 30s score for bug reports.
- [ ] **519. Graceful Android background.** Resume without black tank.
- [ ] **520. Perf smoke.** Focus-loss FPS cap engages; potato preset loads without errors.

## Section 14 — Mobile & touch (521–560)

*Grounding: `mobile_hud.gd`, touch slop in `main.gd`.*

- [ ] **521. First-five mobile rewrite.** Thumb-first verbs: Feed, Care, Follow, Photo. **(L)**
- [ ] **522. Care on mobile HUD.** Water + Filter icons (#94).
- [ ] **523. Feed subtypes mobile.** Long-press feed for flake/wafer.
- [ ] **524. Gesture conflicts.** Orbit vs UI scroll never fight.
- [ ] **525. Edge swipes.** Don't steal OS back gesture; inset controls.
- [ ] **526. Notch / island safe.** Critical buttons clear Dynamic Island / cutouts.
- [ ] **527. Haptics taste.** Light taps; disable in Calm.
- [ ] **528. Touch target audit.** Every icon ≥44pt.
- [ ] **529. Tablet layout.** Use space; don't blow up phone UI 2× awkwardly.
- [ ] **530. Keyboard on Android.** External keyboard bindings work.
- [ ] **531. Pause on phone call.** Audio focus respectful.
- [ ] **532. Share photo sheet.** (#153)
- [ ] **533. Battery indicator soft.** If tank heavy, suggest Battery saver.
- [ ] **534. Offline Android.** No network required for core loop.
- [ ] **535. Storage permission clarity.** Why photos need access — one sentence.
- [ ] **536. Back button.** Android back closes panels, then shelf confirm.
- [ ] **537. Multi-touch photo.** Two-finger doesn't drop food.
- [ ] **538. Gyro optional.** Subtle parallax off by default.
- [ ] **539. Flat place warning.** "Best on a table" for gyro modes.
- [ ] **540. Mobile walkthrough.** Finger movies, not mouse language.
- [ ] **541. Text field zoom.** Mobile keyboards don't cover rename fields forever.
- [ ] **542. Autocorrect names.** Disable autocorrect on name fields.
- [ ] **543. Cloud? Optional later.** Don't block on sign-in.
- [ ] **544. Performance toaster.** One-time "enable Potato?" on detected jank.
- [ ] **545. Landscape lock optional.** Some prefer locked landscape aquarium.
- [ ] **546. Portrait watching.** Still beautiful; docks reflow (#373).
- [ ] **547. Blind spots.** No critical control under gesture bars.
- [ ] **548. Stylus friendly.** Samsung/iPad pencil tap = click.
- [ ] **549. Mobile Residents parity.** (#463)
- [ ] **550. Suspend save.** OnPause flush save (#136).
- [ ] **551. Resume continuity.** Same camera, same follow target.
- [ ] **552. Touch feed aim assist.** Larger magnet on phones.
- [ ] **553. Disable accidental calls.** Immersive mode sticky while playing.
- [ ] **554. APK size honesty.** Store listing matches what ships.
- [ ] **555. Guardian on mobile.** Template voice default; LLM off per AGENTS matrix — say so in UI.
- [ ] **556. Mobile FAQ.** Short: feed, care, photo, save.
- [ ] **557. Split-screen.** Usable at 50% width or gracefully refuse.
- [ ] **558. Foldables.** Continuity across fold if reasonable.
- [ ] **559. Touch accessibility.** Switch control / voice access doesn't brick UI.
- [ ] **560. Mobile smoke.** Care+Feed hit targets present; back stack closes panels.

## Section 15 — Steam, store, product framing (561–600)

*Grounding: `steam/store`, achievements jot, wishlist page.*

- [ ] **561. Store page depth.** Feature list matching real verbs: watch, feed, care, follow, photo. **(L)**
- [ ] **562. Short description truth.** No AI hype the build can't keep on every platform.
- [ ] **563. Screenshot captions.** Each shot teaches a verb.
- [ ] **564. Trailer: desk zen.** Sell stillness; flash the wonder once.
- [ ] **565. Achievements tasteful.** If shipped: quiet, optional popup density low.
- [ ] **566. Achievement non-cruelty.** None that require killing.
- [ ] **567. Steam Cloud decision.** Ship or explicitly "local saves only."
- [ ] **568. Deck verified work.** Controls + performance profile.
- [ ] **569. Proton notes.** If any, documented.
- [ ] **570. Localization plan.** Even English-only: announce honestly.
- [ ] **571. Age rating clarity.** Everyone / mild wildlife — set expectations.
- [ ] **572. Tags accuracy.** Cozy / Simulation / Pixel art — avoid misleading tags.
- [ ] **573. EA communication.** Roadmap link from in-game Info.
- [ ] **574. Known issues page.** In-game → web, short.
- [ ] **575. Wishlist CTA in-game?** Optional, once, never nag.
- [ ] **576. Overlay friendly.** Shift+Tab doesn't break input.
- [ ] **577. Rich presence.** "Watching a blackwater jar" — cozy, not sweaty.
- [ ] **578. Steam input default.** Official template.
- [ ] **579. Workshop? Later.** Don't tease if unshipped.
- [ ] **580. Multiplayer tease removal.** GOALS "visit tanks" — don't advertise until real.
- [ ] **581. Wallpaper #50.** Multi-tank desktop wallpaper mode — still open product fantasy. **(L)**
- [ ] **582. Refund-period clarity.** First hour must show Care + Feed success (#8).
- [ ] **583. Support email/path.** In-game Help → how to report.
- [ ] **584. Version number visible.** Shelf/Info shows build.
- [ ] **585. Credits reachable.** Humans + audio + fonts.
- [ ] **586. Licenses.** OSS licenses screen.
- [ ] **587. Trademark care.** walstad loom naming consistent (not three names in UI).
- [ ] **588. Press kit link.** For the day it's needed.
- [ ] **589. Demo vs full.** If demo, clear limits; saves migrate.
- [ ] **590. Seasonal sale assets.** Capsules ready — craft debt.
- [ ] **591. Review prompt timing.** Only after a bonded hour; OS/Steam polite.
- [ ] **592. Crash reporter opt-in.** With privacy sentence.
- [ ] **593. Anti-cheat? No.** Never.
- [ ] **594. Family share.** Confirm saves isolation expectations.
- [ ] **595. Timed exclusive? No surprises.** Platforms get same verbs.
- [ ] **596. Console? Out of scope note.** Don't half-promise.
- [ ] **597. Speedrun.org? Determinism friendliness already valued — don't break for UI.
- [ ] **598. Mod policy.** If scripts exposed, say what's allowed.
- [ ] **599. Community links.** Discord/Reddit once in Info, not popups.
- [ ] **600. Store smoke.** Internal checklist: screenshots, captions, build number match tag.

## Section 16 — Clarity of the living sim (601–640)

*Grounding: chemistry chips, plant growth, ecology — teach without textbooks.*

- [ ] **601. Metaphor layer.** Lungs / pantry / compost — one consistent metaphor set in UI copy. **(L)**
- [ ] **602. Cause→effect toasts.** After Care, show the chip movement: "nitrates eased."
- [ ] **603. Why is it cloudy?** Diagnostic one-liner from water state.
- [ ] **604. Why are fish gasping?** Same.
- [ ] **605. Why won't plants grow?** Top limiter in plain words (ties plant inspector later).
- [ ] **606. Algae meaning.** "Extra light + leftover food" — actionable.
- [ ] **607. Bloom ≠ beauty always.** Green water explained; recovery path offered.
- [ ] **608. Salt vs fresh lock.** Can't dose the wrong world's care items.
- [ ] **609. Temperature feel.** "Cool / cozy / warm" beside degrees.
- [ ] **610. Flow feel.** "Still pocket / breeze / jet" from flow field.
- [ ] **611. Day length teach.** Photoperiod slider explains plant/fish mood.
- [ ] **612. Stocking calculator soft.** "This many is cozy for this tank size."
- [ ] **613. Biotope honesty.** Scenario claims match species present.
- [ ] **614. Invasive warning.** Fast floaters: "will cover surface — skim anytime."
- [ ] **615. Hidden systems list.** Help → "what's simulated" short list — builds trust.
- [ ] **616. What's not simulated.** Equally important for trust.
- [ ] **617. Parameter ranges.** Soft ideal bands on expanded chips.
- [ ] **618. Trend arrows.** Rising/falling, not only absolute.
- [ ] **619. Correlate actions.** "After feeding, ammonia blip normal."
- [ ] **620. First crash debrief.** Post-disaster card with 3 learnings max.
- [ ] **621. Sandbox cheats labeled.** God-mode nutrients clearly "practice."
- [ ] **622. Observe mode.** Disables feeding/care for museum display — sim still runs.
- [ ] **623. Time labels.** "Tank afternoon" vs wall clock — pick one default.
- [ ] **624. Season optional.** If seasons ship, teach with phenology, not a badge (#759).
- [ ] **625. Fish hunger readable.** Behavior first; meters optional Advanced.
- [ ] **626. Plant hunger readable.** Pale tips / stretch — already visual; caption once.
- [ ] **627. Detritus role.** "Brown stuff feeds the cycle" — don't shame mulm.
- [ ] **628. Snails as partners.** Copy respects cleanup crew.
- [ ] **629. Shrimp as partners.** Same.
- [ ] **630. Filter bacteria story.** Rinse warning: "don't sterilize the good microbes."
- [ ] **631. New tank syndrome.** Named once with patience guidance.
- [ ] **632. Cycled tank pride.** Quiet "the tank is mature" when true (#623 naturalism).
- [ ] **633. Light height.** If adjustable, explain burn vs stretch.
- [ ] **634. CO2 optional advanced.** High-tech path labeled optional.
- [ ] **635. Test kit ritual.** Optional slow test-kit interaction for immersion (#896).
- [ ] **636. False precision die.** Don't show 0.0001 ppm to humans.
- [ ] **637. Compare to real hobby.** Loading tip: "like a real Walstad — watch longer than tweak."
- [ ] **638. Glossary.** Ten terms max; linked from chips.
- [ ] **639. Teacher mode.** Extra captions for classrooms; off by default.
- [ ] **640. Clarity smoke.** Each critical alert maps to a glossary id + Care CTA.

## Section 17 — UI craft & chrome taste (641–680)

*Grounding: `PanelTheme`, rails, docks, modal stacks.*

- [ ] **641. One chrome language.** Corners, paddings, type sizes — audit drift across panels. **(L)**
- [ ] **642. Fewer borders.** If removing a box doesn't hurt, remove it.
- [ ] **643. Type hierarchy.** Tank name > panel title > body > legal.
- [ ] **644. No Inter/Roboto.** Stick to shipped expressive fonts.
- [ ] **645. Quantize-safe UI.** Text remains readable on dithered backgrounds.
- [ ] **646. Modal scrim.** Always dim tank behind modal; click-out policy consistent.
- [ ] **647. Panel memory.** Size/position of floating panels persisted.
- [ ] **648. Dock collision solver.** Feed/Care/Photo never overlap.
- [ ] **649. Right rail overflow.** (#272)
- [ ] **650. Icon set consistency.** Same stroke weight; one artist pass.
- [ ] **651. Empty states illustrated.** Soft pixel empty art, not blank lists.
- [ ] **652. Loading skeletons.** Panels don't pop layout.
- [ ] **653. Button verbs.** "Change water" not "OK."
- [ ] **654. Destructive red restrained.**
- [ ] **655. Focus visible.** (#56)
- [ ] **656. Motion 200–300ms.** UI tweens consistent; respect reduced motion.
- [ ] **657. Sound with UI rare.** Prefer silence.
- [ ] **658. Scrollbars themed.** Visible enough to find, quiet enough to ignore.
- [ ] **659. Nested scroll trap.** Fix rail-inside-panel scroll fights.
- [ ] **660. Drag handles.** Floating panels need clear grab affordance.
- [ ] **661. Close affordance.** Always a clear X; Esc works.
- [ ] **662. Toast lane.** (#259)
- [ ] **663. Banner vs toast.** Persistent needs banner; ephemeral toast.
- [ ] **664. Badge counts.** Alerts badge saturates at 9+.
- [ ] **665. Pixel alignment.** UI snaps to integer pixels — no blurry text.
- [ ] **666. HiDPI.** @2x icons where needed.
- [ ] **667. Dark room chrome.** UI respects night without going pure black mush.
- [ ] **668. Light room chrome.** Same for bright biotopes.
- [ ] **669. Contrast themes.** Auto vs force.
- [ ] **670. Panel screenshots.** Dev gallery of every panel for QA.
- [ ] **671. Reduce emoji.** Pixel game — prefer icons over emoji in UI.
- [ ] **672. Avoid purple AI sludge.** Guardian UI stays on-brand.
- [ ] **673. Cards only for interaction.** No decorative card stacks.
- [ ] **674. Hero shelf.** Shelf remains one composition — brand first.
- [ ] **675. Info page craft.** Landing-quality layout, not a wall of markdown.
- [ ] **676. Legal text collapsible.**
- [ ] **677. Cursor desktop.** Custom cursor optional; default OS ok.
- [ ] **678. Selection color.** Readable on green water.
- [ ] **679. Form errors inline.** Not only toast.
- [ ] **680. UI craft smoke.** Screenshot diff critical panels at 1x/2x (dev).

## Section 18 — Aquascape & stocking without regret (681–720)

*Grounding: `aquascape_controller.gd`, stocking settings, Creator.*

- [ ] **681. Preview before place.** Ghost hardscape/plant before commit.
- [ ] **682. Undo stack.** 20 steps for scape edits.
- [ ] **683. Redo.**
- [ ] **684. Non-destructive explore.** Duplicate tank before "Design scape" experiments (#140).
- [ ] **685. Stocking cart.** Add fauna to a cart → confirm once.
- [ ] **686. Compatibility matrix soft.** Warn betta + fancy longfins etc.
- [ ] **687. Capacity meter.** (#188)
- [ ] **688. Place on substrate snap.** Plants don't float in water column by accident.
- [ ] **689. Epiphyte attach snap.** To wood/rock only — teach niche.
- [ ] **690. Delete confirm.** Especially "clear all plants."
- [ ] **691. Scape mode chrome.** Distinct border so you know you're editing.
- [ ] **692. Exit scape restores watch UI.**
- [ ] **693. Budget beauty.** Cheap/cozy stocking presets.
- [ ] **694. Biotope kits.** One-click legal communities.
- [ ] **695. Randomize tasteful.** Random stocking within compatibility.
- [ ] **696. Creator vs Library.** Clear labels; don't drop players into genome hell.
- [ ] **697. Mobile scape limited.** Honest "desktop recommended" or solid touch tools.
- [ ] **698. Grid optional.** Snap grid for perfectionists; off for wild.
- [ ] **699. Measure tool.** Rough cm/inches for aquarists who care.
- [ ] **700. Photo while scaping.** Allowed.
- [ ] **701. Scape tutorials.** Three micro-lessons: hardscape, plants, fauna.
- [ ] **702. Disaster wipe.** "Reset scape" separate from "delete save."
- [ ] **703. Paint substrate.** If supported, brush size obvious.
- [ ] **704. Move vs copy.** Two tools, labeled.
- [ ] **705. Group select.** For aquascapers; still not for watching mode.
- [ ] **706. Hidden collision.** Can't place inside glass.
- [ ] **707. Path for fish.** Don't brick swimming lanes without warning.
- [ ] **708. Tall plant rear bias.** Soft assist for classic layout.
- [ ] **709. Carpet front bias.** Same.
- [ ] **710. Scape autosave.** Differs from sim autosave — label it.
- [ ] **711. Version scapes.** Slot A/B compare.
- [ ] **712. Share scape file.** Without fauna if preferred.
- [ ] **713. Seed bank from Library.** Place discovered plants.
- [ ] **714. Cost? Skip.** No fake currency unless designed.
- [ ] **715. Achievements for scape? Soft.** Optional.
- [ ] **716. Performance while editing.** Ghosts cheap.
- [ ] **717. Undo care actions separate.** Don't mix siphon with rock move.
- [ ] **718. Exit confirm dirty.**
- [ ] **719. Scape help legend.** Tool keys.
- [ ] **720. Scape smoke.** Undo/redo; attach rules; capacity warn.

## Section 19 — Long-run desk tank (721–760)

*Grounding: away recap, night watch, maturation, wallpaper fantasy.*

- [ ] **721. Away recap that sings.** 3 bullets max + one photo if a wonder happened. **(L)**
- [ ] **722. Overnight story.** Night watch summary: slept well / struggled.
- [ ] **723. Week in review.** Optional Sunday card — off by default.
- [ ] **724. Maturation badges quiet.** "Biofilm settled" as journal, not popup.
- [ ] **725. Desk hours tracked.** Shelf vanity (#149).
- [ ] **726. Multi-tank wallpaper.** GOALS #50 — live or photo mosaic. **(L)**
- [ ] **727. Always-on PC mode.** Extremely low FPS + Calm when idle overnight.
- [ ] **728. Morning hello.** Soft once if tank thrived overnight.
- [ ] **729. Don't nag care.** If player is a watcher, rarer nudges (preference).
- [ ] **730. Watcher vs keeper profiles.** Two default nudge personalities.
- [ ] **731. Seasonal chrome.** Optional light UI seasonal tint.
- [ ] **732. Anniversary.** Tank birthday (#750 spirit) — one postcard.
- [ ] **733. Long-run perf.** 8h soak without leak — CI goal.
- [ ] **734. Dusty save reopen.** Years later: migrate kindly (#138).
- [ ] **735. Archive old tanks.** Compress without delete.
- [ ] **736. Favorite tank pin.** (#147)
- [ ] **737. Continue across devices.** Only if Cloud real (#567).
- [ ] **738. Idle wonders.** Rare events can fire AFK but never steal focus (#993 law).
- [ ] **739. Screensaver export.** (#159)
- [ ] **740. Desk companion docs.** README section: "leave it running."
- [ ] **741. Power schedule.** Optional sleep tank with OS — careful.
- [ ] **742. Quiet updates.** Game update doesn't reset tips aggressively.
- [ ] **743. Changelog in-game.** Short, player-facing.
- [ ] **744. Long-run bonding.** Familiarity persists correctly across updates.
- [ ] **745. Population soft ceiling comfort.** Explain steady state as success.
- [ ] **746. Boredom prevention ethical.** Suggest a new scenario once a month max.
- [ ] **747. Photo of the year.** Auto-pick best shot if album exists.
- [ ] **748. Journal export.** Markdown/PDF of tank life.
- [ ] **749. Backup reminder.** Monthly optional.
- [ ] **750. Legacy tank.** Read-only shrine for a beloved finished save.
- [ ] **751. Second monitor mode.** UI on A, pure tank on B.
- [ ] **752. Stream deck / macropad.** Optional hotkeys doc.
- [ ] **753. Torpor when hidden.** Window occluded → deep sleep CPU.
- [ ] **754. Resume exact.** Same sim time feel; no giant skip without recap.
- [ ] **755. AFK feed? No.** Never auto-feed unless user builds a rule later.
- [ ] **756. Rules engine light.** Optional: "if nitrate high, remind" — user-authored.
- [ ] **757. Long-run survey.** Opt-in after 10h: what felt bad — feeds this doc.
- [ ] **758. Stability contract.** Patch notes say if saves break.
- [ ] **759. Nostalgia reel.** Timelapse from month of screenshots.
- [ ] **760. Long-run smoke.** 30-min headless soak + save/load identity.

## Section 20 — Trust, honesty & anti-annoyance (761–800)

- [ ] **761. No dark patterns.** No fake urgency, no disguised ads. **(L)**
- [ ] **762. Consent for mic/cam.** If bond sensors ship, refuse-by-default + clear why.
- [ ] **763. Data stays local.** State it in Info; keep it true.
- [ ] **764. Opt-in analytics only.**
- [ ] **765. Uninstall clean.** Saves in documented path; leave crumbs optional.
- [ ] **766. No review hostage.**
- [ ] **767. Tip frequency cap.** Global.
- [ ] **768. Tip respect.** Dismiss forever sticks.
- [ ] **769. No tip during wonder.** Detect photo mode / follow / bloom — hush.
- [ ] **770. Error copy kind.** Human, actionable, no blame.
- [ ] **771. Failure ownership.** "We couldn't save" > "Save failed (err 3)."
- [ ] **772. Feature honesty.** Disabled platforms say why (LLM on Android).
- [ ] **773. Experimental badges.** Risky toggles marked.
- [ ] **774. Rollback advice.** If update hurts, how to prior build.
- [ ] **775. Mod warning.** Unsupported mods void support kindly.
- [ ] **776. Time-respect.** No forced video. No unskippable.
- [ ] **777. Pause respects life.** Sim pause means pause.
- [ ] **778. No FOMO events.** If seasonal, catch-up kind.
- [ ] **779. Loot boxes? Never.**
- [ ] **780. Energy systems? Never.**
- [ ] **781. Pay-to-win? Never.** Cosmetics only if ever — not needed now.
- [ ] **782. Child safety.** No chat with strangers; no UGC creep without moderation plan.
- [ ] **783. Names filter.** (#468)
- [ ] **784. Screenshot privacy.** No accidental account ids in HUD.
- [ ] **785. Streamer mode.** (#488)
- [ ] **786. Randomness disclosed.** Seeded tanks for science; say when random.
- [ ] **787. Promise tracker.** Internal: store claims ↔ QA checklist.
- [ ] **788. Broken window rule.** Fix small UI lies fast (wrong keyhints).
- [ ] **789. Changelog honesty.** "Fixed" only if fixed.
- [ ] **790. Credit artists.**
- [ ] **791. No engagement Skinner.** Favorites aren't streaks that punish.
- [ ] **792. Mute forever works.**
- [ ] **793. Notification permission.** Ask only when enabling.
- [ ] **794. Background CPU respect.** (#489/#753)
- [ ] **795. Disk respect.** Cap album with cleanup (#144).
- [ ] **796. Battery respect.**
- [ ] **797. Accessibility not paywalled.**
- [ ] **798. Difficulty not humiliation.**
- [ ] **799. Player is keeper not god.** Copy tone check.
- [ ] **800. Trust smoke.** Tips dismissed stay dismissed across relaunch.

## Section 21 — Copy, tone & microtext (801–840)

- [ ] **801. Voice guide.** Short style doc: warm, specific, non-condescending. **(L)**
- [ ] **802. Kill "simulation" in player UI.** Prefer tank / water / life.
- [ ] **803. Kill "entity/spawn."**
- [ ] **804. Error strings inventory.** Rewrite top 50.
- [ ] **805. Tooltip length cap.** 140 chars.
- [ ] **806. Humor rarity.** Witty once an hour max.
- [ ] **807. No meme speak.**
- [ ] **808. No shame copy.**
- [ ] **809. Inclusive "they" for fish.** Or names only.
- [ ] **810. Species names.** Common first, Latin secondary.
- [ ] **811. Consistent Care verbs.** Change water / rinse filter / trim plants.
- [ ] **812. Consistent camera verbs.** Orbit / zoom / follow.
- [ ] **813. Button casing.** Title case vs sentence — pick one.
- [ ] **814. Ellipsis meaning.** Loading vs more — don't overload.
- [ ] **815. Timezones.** Journal stamps local.
- [ ] **816. Pluralization.** 1 snail / 2 snails.
- [ ] **817. Count formatting.** 1.2k only in Advanced.
- [ ] **818. Avoid ALL CAPS.** Except PAUSED.
- [ ] **819. Reading level.** Aim grade 7 for care tips.
- [ ] **820. Translate-ready.** `tr()` on new strings.
- [ ] **821. Glossary links.** Subtle underline once.
- [ ] **822. Guardian voice ≠ UI voice.** Keep distinct.
- [ ] **823. No fake AI certainty.** "Might be hungry" > "is hungry" when unsure.
- [ ] **824. Loading tips rotate.** Useful, not lore spam.
- [ ] **825. Empty string audit.** No blank buttons.
- [ ] **826. Truncation with expand.** Names don't die in `...` without hover.
- [ ] **827. Units in copy.** Always.
- [ ] **828. Scenario blurbs.** Sell feeling, not parameter dumps.
- [ ] **829. Death copy review.** (#401 family)
- [ ] **830. Success copy quiet.** Prefer visuals.
- [ ] **831. Confirm questions.** Specific: "Change 25% water?"
- [ ] **832. Avoid yes/no traps.** Prefer labeled actions.
- [ ] **833. Credits tone.** Grateful, short.
- [ ] **834. Update notes player-facing.**
- [ ] **835. Support macros.** Canned helpful replies for common bugs.
- [ ] **836. Onboarding verbs match UI.**
- [ ] **837. No conflicting key names.**
- [ ] **838. Accessibility names meaningful.**
- [ ] **839. Copy QA checklist.** Before each release.
- [ ] **840. Copy smoke.** Snapshot critical strings; fail if empty/placeholder.

## Section 22 — Delight, wonder & "one more minute" (841–880)

- [ ] **841. Daily quiet wonder budget.** At most one scheduled delight/hour — scarcity. **(L)**
- [ ] **842. First pearling moment.** Teach once when it happens.
- [ ] **843. First baby.** Soft celebration.
- [ ] **844. First bloom.** Soft celebration.
- [ ] **845. Golden hour reminder.** Optional, once per day max.
- [ ] **846. Fish greeting.** Rare approach to glass when you're present (#385).
- [ ] **847. Name whisper.** Caption uses the name you gave — bond glue.
- [ ] **848. Photo of wonder auto-suggest.** Once; never spam.
- [ ] **849. Secret corner.** Discoverable quiet view.
- [ ] **850. Rain on glass rare.** If weather ships — tasteful.
- [ ] **851. Snail trails.** Temporary beauty.
- [ ] **852. Shrimp parade.** Rare synchronized molt window — watchable.
- [ ] **853. Moon path.** Night caustics shift.
- [ ] **854. Hand-fed trust.** Familiar fish take from nearer drops.
- [ ] **855. Journal poetry optional.** Off by default; some keepers want it.
- [ ] **856. Tank dreams.** Away recap can be slightly lyrical — still true.
- [ ] **857. Composer's hour.** Music bed change once a week if enabled.
- [ ] **858. Pixel dust in light.** Already wanted in plant doc — ensure visible.
- [ ] **859. Follow cam documentary fade.**
- [ ] **860. Easter egg restraint.** One or two; never undermine tone.
- [ ] **861. Birthday fish.** Optional.
- [ ] **862. Player birthday?** Opt-in only; privacy.
- [ ] **863. Rainy day preset.** Soft lighting pack.
- [ ] **864. Cozy load tip.** "They're still swimming while you were away."
- [ ] **865. Thank-you on quit.** Rare, warm, skippable.
- [ ] **866. Crediting the tank.** Photo captions can include tank name.
- [ ] **867. Wonder without UI.** If chrome hidden, wonders still show in-world.
- [ ] **868. Dual delight rule.** Never stack death + joke.
- [ ] **869. Keepers' gallery.** Local best photos.
- [ ] **870. Share card.** Auto 1:1 crop with name for social — optional.
- [ ] **871. Soft applause?** No. Silence after wonder.
- [ ] **872. Fireflies? Only if biotope-true.**
- [ ] **873. Fog of spores beauty.** If moss ships event — photo bait.
- [ ] **874. Vallisneria wedding.** If naturalism #965 ships — ensure player can witness.
- [ ] **875. Seatbelt for delight.** Reduced motion still gets a static beauty cue.
- [ ] **876. Captions during delight.** Off by default.
- [ ] **877. Second screen delight.** Mirror-safe.
- [ ] **878. No paywalled wonder.**
- [ ] **879. Delight telemetry opt-in.** Which wonders were witnessed.
- [ ] **880. Delight smoke.** Scheduler respects Calm + reduced motion.

## Section 23 — Onboarding verification & regression (881–920)

*ONBOARDING_LEGIBILITY is marked done — these items verify it still feels done.*

- [ ] **881. Playtest first 10 minutes monthly.** Scripted observer notes. **(L)**
- [ ] **882. Coachmark z-order test.**
- [ ] **883. Nudge deep links work.**
- [ ] **884. Cheat sheet matches bindings.**
- [ ] **885. Calm mode offered up front.**
- [ ] **886. Font scale doesn't break docks.**
- [ ] **887. Colorblind path findable.**
- [ ] **888. Walkthrough skip persistence.**
- [ ] **889. Feed dock visible on default layout.**
- [ ] **890. Care discoverable without nudge.** (fails today — #1 fixes)
- [ ] **891. Photo path visible desktop.** (#81)
- [ ] **892. Autosave known to user.** (#121)
- [ ] **893. Scenario spicy labeled.**
- [ ] **894. Guardian consent not minute-one.** (#15)
- [ ] **895. Mobile coachmarks finger-true.**
- [ ] **896. Desktop footer not empty.**
- [ ] **897. Help search finds Care.**
- [ ] **898. Reset tips works.**
- [ ] **899. No double modals on boot.**
- [ ] **900. Performance of tips.** Tips don't hitch.
- [ ] **901. Localization expands don't break.**
- [ ] **902. Gamepad first-run.** Completes feed+follow.
- [ ] **903. Keyboard-only first-run.**
- [ ] **904. Screen reader first-run smoke.**
- [ ] **905. New save → wonder before chrome.** (#2)
- [ ] **906. Continue button dominance.** (#27)
- [ ] **907. Crash recovery message.** (#28)
- [ ] **908. Audio fade-in.** (#36)
- [ ] **909. Focus return calm.** (#37)
- [ ] **910. Promise/docs sync CI.** Grep README keys vs legend.
- [ ] **911. Tip budget enforced.** (#34)
- [ ] **912. Alert vs tip priority.** Alerts win.
- [ ] **913. Photo mode suppresses tips.**
- [ ] **914. Pause suppresses tips.**
- [ ] **915. First session metrics opt-in.** Time-to-first-feed.
- [ ] **916. Drop-off survey rare.**
- [ ] **917. Onboarding feature flag.** Kill switch if broken.
- [ ] **918. Golden path video.** Internal 60s capture each release.
- [ ] **919. Checklist in PR template.** Player-facing PRs tick journey items.
- [ ] **920. Onboarding smoke suite.** Automate #882–#914 where possible.

## Section 24 — Cross-cutting quality bar (921–960)

- [ ] **921. "I wish" triage tag.** Label issues `player-wish` in tracker. **(L)**
- [ ] **922. Severity: rage / frown / shrug.** Prioritize rage.
- [ ] **923. Five-second rule.** Confusion >5s → ticket.
- [ ] **924. Desk test.** Leave running 4h while working — note interruptions.
- [ ] **925. Mom test.** Non-gamer finds Feed/Care.
- [ ] **926. Aquarist test.** Hobbyist trusts the chemistry metaphors.
- [ ] **927. Child-adjacent test.** Tone safe; no chat predators possible.
- [ ] **928. Potato laptop test.**
- [ ] **929. Deck couch test.**
- [ ] **930. Phone bus test.**
- [ ] **931. Blind screenshot test.** Can you tell brand/game from a still?
- [ ] **932. Mute test.** Game still understandable muted.
- [ ] **933. Colorblind test.**
- [ ] **934. Bright room / dark room.**
- [ ] **935. No mouse test.**
- [ ] **936. No keyboard test (mobile).**
- [ ] **937. Save scum test.** Duplicate workflow works.
- [ ] **938. Update test.** Old save → new build.
- [ ] **939. Locale fake test.** Long German strings.
- [ ] **940. Timezone test.**
- [ ] **941. Disk full test.**
- [ ] **942. Lost network test.**
- [ ] **943. Alt-tab thrash test.**
- [ ] **944. Resolution thrash test.**
- [ ] **945. Aspect thrash test.**
- [ ] **946. Audio device thrash.**
- [ ] **947. Focus steal test.** Notifications don't break tank.
- [ ] **948. Long name test.**
- [ ] **949. Empty tank test.**
- [ ] **950. Overfull tank test.**
- [ ] **951. Reef vs fresh mix test.** Impossible states blocked.
- [ ] **952. Speed vs zen test.** Fast players and watchers both served.
- [ ] **953. Accessibility solemnity.** A11y never "bonus."
- [ ] **954. Performance solemnity.** Jank is a bug.
- [ ] **955. Copy solemnity.** Typos are bugs.
- [ ] **956. Keyhint solemnity.** Wrong hints are bugs.
- [ ] **957. Promise solemnity.** Store lies are release blockers.
- [ ] **958. Wonder solemnity.** Fabricated wonders are release blockers.
- [ ] **959. Death solemnity.** Mocking loss is a release blocker.
- [ ] **960. Quality smoke meta.** Checklist runs in CI notes each tag.

## Section 25 — The thousandth cut: ship the feeling (961–1000)

- [ ] **961. Rare-event player mirror.** When naturalism #961 ships, wire witness UX here (toast optional, album clip). **(L)**
- [ ] **962. Care dock ships before new panels.** Process rule: verbs > chrome.
- [ ] **963. Delete one tip for every new tip.** Tip budget conservation.
- [ ] **964. Delete one setting for every new setting.** Or hide under Advanced.
- [ ] **965. Screenshot the default tank weekly.** Eye-QA drift.
- [ ] **966. Record first five minutes weekly.**
- [ ] **967. Keep a rage list.** Top 10 player frowns on a sticky note / issue milestone.
- [ ] **968. Close the loop.** Each rage item maps to a checkbox in this doc.
- [ ] **969. Prefer fix over option.** Don't add a toggle if the default should just be good.
- [ ] **970. Prefer in-world over modal.**
- [ ] **971. Prefer quiet over loud.**
- [ ] **972. Prefer specific over clever.**
- [ ] **973. Prefer reversible over clever.**
- [ ] **974. Prefer local over cloud.** Until Cloud is real.
- [ ] **975. Prefer names over numbers.**
- [ ] **976. Prefer verbs over nouns in UI.**
- [ ] **977. Prefer one path.** Duplicate verbs confuse.
- [ ] **978. Prefer ship stub with honesty.** "Coming later" only if true.
- [ ] **979. Prefer playtest over opinion.**
- [ ] **980. Prefer save safety over feature speed.**
- [ ] **981. The Continue button is sacred.** Never bury it.
- [ ] **982. The Feed verb is sacred.**
- [ ] **983. The Care verb is sacred.**
- [ ] **984. The Follow verb is sacred.**
- [ ] **985. The Photo verb is sacred.**
- [ ] **986. The name you gave them is sacred.**
- [ ] **987. The quiet hour is sacred.**
- [ ] **988. The overnight tank is sacred.**
- [ ] **989. The first pearling is sacred.**
- [ ] **990. The first baby is sacred.**
- [ ] **991. The old scarred fish is sacred.**
- [ ] **992. The desk is the altar.** Design for leaving it on.
- [ ] **993. Never yank the camera for delight.**
- [ ] **994. Never punish watching.**
- [ ] **995. Never make maintenance homework without teaching.**
- [ ] **996. Never ship a keyhint lie.**
- [ ] **997. Never mock the player's dead fish.**
- [ ] **998. Acceptance: mom finds Feed and Care in 30s.**
- [ ] **999. Acceptance: aquarist says "this feels like a tank."**
- [ ] **1000. Acceptance: you leave it running while you work — and when you glance back, you smile.**

---

## Coda

The plant naturalism doc makes life *wild*. This doc makes the **player's life
with that wildness** kinder: find the verb, trust the save, understand the
water, name the fish, take the photo, leave it on the desk.

Work the foundations shortlist first. Verify with playtests and small smokes.
Mark items done here as they ship. Do not open a new sentience doc when a Care
dock would do.

