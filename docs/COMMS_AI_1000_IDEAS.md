# Speak Clearer — 1000 Ideas for Notifications & Innate AI Comms

*Drafted 2026-09-10. Director's mega-backlog for the calm inbox.*

The brief: the tank already has a mind. Players need **communications that feel
finished** — one toast lane, honest voice tiers, mute that works, return
ceremonies that don't double-greet, and speech that never buries the glass.

This doc owns **player-facing communication UX**. It does **not** rebuild
Guardian mind, conversation architecture, embedded LLM contracts, or night-watch
simulation (those pillars are largely shipped). Prefer fixing
`_push_notification` / toast lanes / mute prefs over new cognition.

Ground truth: `main.gd` (notif center + toasts), `sim_driver.gd`,
`ai_director.gd`, `guardian_llm.gd`, `guardian_mind.gd`, `mind_narrator.gd`,
`keeper_care.gd`, `mind_conversation.gd`, `onboarding_runtime.gd`,
`settings_panel.gd`, `tank_config.gd`, `tank_mind.gd`, `night_watch.gd`.

See also [PLAYER_WISH_1000_IDEAS.md](PLAYER_WISH_1000_IDEAS.md) (cross-link, don't
fork), GUARDIAN_*, SENTIENCE_THE_CONVERSATION, SENTIENCE_EMBEDDED,
SENTIENCE_THE_NIGHT_WATCH, MAKE_IT_THERE, ONBOARDING_LEGIBILITY.

**Format:** checkboxes; S–M unless **(L)**. One idea → one commit → smoke.

## If this doc only does ten (do these first)

1. **#1 Toast lane arbiter** — one priority queue for all ephemeral text.
2. **#41 Complete kind filters** — guardian/care/fish_thought/residents/system.
3. **#121 Quiet-first mute matrix** — voice + ambient toasts; critical water remains.
4. **#241 Return ceremony dedupe** — away recap XOR welcome_back.
5. **#401 Caption budget** — 1 ambient caption / 20s into the arbiter.
6. **#44 Mark-as-read on open** — badge honesty.
7. **#281 Consent deferral** — no LLM modal in the first five minutes.
8. **#161 Tier honesty chip** — templates vs built-in vs Ollama, once/session.
9. **#361 Death summary toast** — N deaths → one card.
10. **#801 Communications smoke** — concurrent toasts, quiet, away XOR welcome.

**Sequencing:** 1 → 121 → 241 → 41 → 44, then consent/honesty/death/smoke.

**Foundations shipped 2026-09-10:** #1, #41, #44, #121, #161, #241, #281, #361, #401, #801 (`comms_inbox.gd` + main/sim/onboarding/settings wiring).

---

## Section — Toast lane unification & stacking (1–40)

*Grounding: `_push_notification`, `_show_status_toast`, `_show_feed_toast`, `onboarding_runtime._show_caption`.*

- [x] **1. One toast lane arbiter. All ephemeral text (notif / status / feed / caption) enters one priority queue. **(L)****
- [ ] **2. Priority order law. Critical water > care confirm > guardian important > status > feed hint > ambient caption.**
- [ ] **3. Max two visible toasts. Hard cap shared across lanes (today only notif lane caps at 2).**
- [ ] **4. Typing focus hush. Already pauses notif pump — extend to status/feed/caption.**
- [ ] **5. Follow-strip clearance for all lanes. Status/feed toasts respect `_layout_follow_thought_strip`.**
- [ ] **6. Photo mode hush. No toasts while letterbox photo is active (except critical).**
- [ ] **7. Pause hush. Ambient toasts pause with sim; critical still fire.**
- [ ] **8. Immersive / focus mode hush. Ambient off; critical badge only.**
- [ ] **9. Toast collision resolve. Newer lower-priority never covers critical.**
- [ ] **10. Slide-in from one edge only. Pick right stack; migrate status into stack or keep bottom with arbiter gate.**
- [ ] **11. Status toast joins arbiter. Autosave/photo/care use same stack with Reveal affordance preserved.**
- [ ] **12. Feed toast joins arbiter. Feed hints become low-priority stack cards.**
- [ ] **13. Caption joins arbiter. Onboarding captions are ambient priority, not a free z=260 overlay.**
- [ ] **14. Away recap card is a ceremony, not a toast. One modal/card; suppresses stack for its lifetime.**
- [ ] **15. Welcome toast merges with recap. Never both.**
- [ ] **16. Guardian toast uses arbiter. `_present_guardian_toast` no longer special-cases outside policy.**
- [ ] **17. Death summary uses arbiter once. Mass death = one card.**
- [ ] **18. Dedup window tunable. 180s default; critical bypasses body-dedup.**
- [ ] **19. Kind+body+severity dedup key. Same body different severity can escalate.**
- [ ] **20. Queue drop policy. If queue > 8, drop oldest ambient first.**
- [ ] **21. Toast duration by severity. Info 3s · important 4.5s · critical sticky until ack.**
- [ ] **22. Tap toast to open center. Focuses matching row.**
- [ ] **23. Swipe dismiss on mobile.**
- [ ] **24. Click-out dismiss desktop for ambient only.**
- [ ] **25. Sound optional per severity. Default off for info.**
- [ ] **26. Reduced motion: fade only, no slide.**
- [ ] **27. Colorblind severity: icon + label, not hue alone.**
- [ ] **28. Toast copy length cap. 120 chars body; ellipsis with open-for-more.**
- [ ] **29. No emoji in toast titles unless UiIcons glyph.**
- [ ] **30. z-index law documented. One constant table for toast/caption/coachmark.**
- [ ] **31. Coachmarks defer to critical toasts.**
- [ ] **32. Nudge cards defer to critical toasts.**
- [ ] **33. Radial menu open hushes ambient.**
- [ ] **34. Settings open hushes ambient.**
- [ ] **35. Creator / Library open hushes ambient.**
- [ ] **36. Aquascape mode: care/status allowed; guardian ambient soft-muted.**
- [ ] **37. Battery saver: ambient toast rate ×0.5.**
- [ ] **38. Calm desk: ambient off; important+ only.**
- [ ] **39. Telemetry opt-in: toast drops / collisions counted.**
- [ ] **40. Toast arbiter smoke. Concurrent ≤2; critical never dropped for ambient.**

## Section — Notification center completeness (41–80)

*Grounding: `_ensure_notifications_ui`, kind filter, badge, `_build_notification_row`.*

- [x] **41. Complete kind filter list. Add guardian, care, fish_thought, residents, system, mind_upgrade, guardian_llm. **(L)****
- [ ] **42. Kind icons for every kind. `_kind_icon` covers new kinds.**
- [ ] **43. Filter chip row. Multi-select kinds optional later; start with complete dropdown.**
- [x] **44. Mark visible as read on open. Opening panel marks currently listed rows read. **(L)****
- [ ] **45. Mark all read button. Beside Clear all.**
- [ ] **46. Clear filtered only. Don't wipe unread other kinds by accident.**
- [ ] **47. Archive voice lines. Optional: guardian/fish_thought auto-archive after 24h tank-time.**
- [ ] **48. Fish thoughts don't inflate badge by default. Pref: history-only unless Follow or opt-in.**
- [ ] **49. Guardian lines always listed. Even if toast suppressed.**
- [ ] **50. Search box. Filter title/body.**
- [ ] **51. Relative timestamps. '2m ago' with absolute on hover.**
- [ ] **52. Group by hour. Collapsible sections for long sessions.**
- [ ] **53. Empty state illustration. Soft, not 'No notifications yet.' only.**
- [ ] **54. Deep link from row. Care → Care dock; water → Care; residents → follow if alive.**
- [ ] **55. Pin critical. Critical stay atop until ack.**
- [ ] **56. Ack critical button on row.**
- [ ] **57. Export journal+notifs. One markdown dump.**
- [ ] **58. Unread badge saturates at 9+.**
- [ ] **59. Badge ignores muted kinds.**
- [ ] **60. Panel remembers filter/sort.**
- [ ] **61. Keyboard nav in list.**
- [ ] **62. Screen reader row labels.**
- [ ] **63. Severity color + glyph.**
- [ ] **64. Meta payload view Advanced. For debug.**
- [ ] **65. OS notification opt-in. Separate from in-game; critical water only by default.**
- [ ] **66. OS permission ask only when enabling.**
- [ ] **67. Click OS notif focuses game + panel.**
- [ ] **68. Do not disturb respects OS DND if detectable.**
- [ ] **69. Clear on tank switch? Ask; default keep global user inbox.**
- [ ] **70. Per-tank filter optional.**
- [ ] **71. Corruption-safe history. Cap + drop oldest.**
- [ ] **72. Save notif prefs with TankConfig user scope.**
- [ ] **73. Rail Alerts tooltip shows unread count.**
- [ ] **74. Flyout 'Mark all read' quick action.**
- [ ] **75. Discovery kind distinct from milestone.**
- [ ] **76. Population kind for births/deaths summaries.**
- [ ] **77. Welcome kind only for return ceremony.**
- [ ] **78. System kind for photo/save (if logged).**
- [ ] **79. Guardian_llm kind for model status — filterable, quiet default toast=false.**
- [ ] **80. Center smoke. Filters include guardian/care; open marks read.**

## Section — Severity, rate & spam policy (81–120)

*Grounding: toast dedup, guardian SPEAK_COOLDOWN, MindNarrator GLOBAL_VOICE_COOLDOWN.*

- [ ] **81. Global ambient rate. Max 1 ambient toast / 20s. **(L)****
- [ ] **82. Per-kind rate tables. water critical uncapped (sensible); discovery ≤1/min.**
- [ ] **83. Guardian speak already 55s — present that as player-facing 'they don't chatter'.**
- [ ] **84. Global voice 18s — don't stack fish+guardian same second.**
- [ ] **85. Story event batching. Collapse 5 story lines into one notif.**
- [ ] **86. Water alert hysteresis. Don't flip-flop toast every tick.**
- [ ] **87. Care confirm not spam. Cooldown already — share with notif dedup.**
- [ ] **88. Population boom summary. '+12 shrimp' one line.**
- [ ] **89. Discovery stampede. First species only toasts; rest history.**
- [ ] **90. Mind upgrade once per version. Already — verify no repeats.**
- [ ] **91. Voiced wake once per session max.**
- [ ] **92. LLM status toasts: errors yes, 'thinking' no.**
- [ ] **93. Template refinement flash. Optional; off in Calm.**
- [ ] **94. Spam score debug overlay. Dev only.**
- [ ] **95. Player 'quiet for 10 minutes' button.**
- [ ] **96. Session soft cap. After 30 ambient toasts, remaining history-only until reopen.**
- [ ] **97. Escalate only. Info→important allowed; never demote in queue.**
- [ ] **98. Death window 60s. Count deaths → one summary.**
- [ ] **99. Birth window 60s. Same.**
- [ ] **100. Feed overfeed whisper rate-limited.**
- [ ] **101. Filter due reminder ≤1 per hour.**
- [ ] **102. Nitrate climb reminder ≤1 per 30m.**
- [ ] **103. O₂ critical sticky single instance.**
- [ ] **104. No achievement spam in first hour (cross PLAYER_WISH #29).**
- [ ] **105. No tip during toast.**
- [ ] **106. No toast during tip.**
- [ ] **107. Coachmark vs toast mutex.**
- [ ] **108. Caption vs toast mutex for ambient.**
- [ ] **109. Rate prefs in Settings → Communications.**
- [ ] **110. Defaults match Calm desk when Calm on.**
- [ ] **111. Streamer quieter default profile.**
- [ ] **112. Deck default slightly quieter.**
- [ ] **113. Mobile slightly fewer ambient (attention).**
- [ ] **114. Desktop can opt into richer.**
- [ ] **115. Telemetry: drops by policy reason.**
- [ ] **116. Ship one good policy — no A/B needed.**
- [ ] **117. Document policy in Help → Communications.**
- [ ] **118. Guardian journal not a spam channel — never toast every journal append.**
- [ ] **119. Fish journal same.**
- [ ] **120. Rate smoke. 50 rapid pushes → ≤3 toasts in 10s sim.**

## Section — Mute taxonomy & quiet defaults (121–160)

*Grounding: `tank_config.sentience_voice_off`, voice toggles; no notif mute today.*

- [x] **121. Master Communications quiet. One switch: voice off + ambient toasts off; critical water remains. **(L)****
- [ ] **122. Separate toggles: Guardian voice · Fish thoughts · Ambient toasts · Captions · OS notify.**
- [ ] **123. Quiet mode matrix documented in Help.**
- [ ] **124. sentience_voice_off implies toast ambient off for guardian/fish kinds.**
- [ ] **125. Critical water escapes quiet (unless Hard mute).**
- [ ] **126. Hard mute (nuclear): everything including water — confirm.**
- [ ] **127. Per-session mute 10/30/60m.**
- [ ] **128. Mute remembers across launches (user scope).**
- [ ] **129. Mute indicator in HUD (subtle).**
- [ ] **130. Click indicator to unmute.**
- [ ] **131. Calm desk enables quiet-first defaults.**
- [ ] **132. First-run asks Calm vs Rich audio/comms.**
- [ ] **133. Declined LLM ≠ muted tank — templates still speak unless quiet.**
- [ ] **134. Settings AI tab renamed Communications & Voice.**
- [ ] **135. Fish thought history-only toggle.**
- [ ] **136. Guardian toast vs journal-only toggle.**
- [ ] **137. Caption mute separate from voice.**
- [ ] **138. Coachmark mute separate.**
- [ ] **139. Feed hints mute.**
- [ ] **140. Autosave ceremony mute (photo still shows).**
- [ ] **141. Care confirm always shows (safety).**
- [ ] **142. Quiet on unfocused window (optional).**
- [ ] **143. Quiet on night hours schedule.**
- [ ] **144. Stream deck mute hotkey.**
- [ ] **145. Gamepad mute chord.**
- [ ] **146. Mute doesn't delete history.**
- [ ] **147. Unmute affects future only — no backfill.**
- [ ] **148. Badge respects mute.**
- [ ] **149. OS notify respects mute.**
- [ ] **150. Welcome/recap respects quiet (journal still).**
- [ ] **151. Guardian morning line skipped if quiet.**
- [ ] **152. Voiced wake skipped if quiet.**
- [ ] **153. Mind upgrade still once (important).**
- [ ] **154. LLM download prompts skipped if quiet+declined.**
- [ ] **155. Tooltip on greyed voice: why.**
- [ ] **156. Accessibility: mute labeled clearly.**
- [ ] **157. No shame copy when muted.**
- [ ] **158. Quiet smoke: zero guardian/fish toasts.**
- [ ] **159. Critical-still smoke under quiet.**
- [ ] **160. Prefs round-trip save/load.**

## Section — Guardian presentation honesty (161–200)

*Grounding: `_on_guardian_spoke`, `MindNarrator.tier_display_name`, `active_llm_tier`.*

- [x] **161. Tier chip once per session. 'Voice: templates / built-in / Ollama'. **(L)****
- [ ] **162. Guardian presentation: rate-limit ambient without silencing critical.**
- [ ] **163. Guardian presentation: respect quiet / Calm / battery saver.**
- [ ] **164. Guardian presentation: deep-link to Care / Residents / Settings when actionable.**
- [ ] **165. Guardian presentation: history vs toast policy explicit.**
- [ ] **166. Guardian presentation: mobile + desktop parity.**
- [ ] **167. Guardian presentation: gamepad dismiss/ack path.**
- [ ] **168. Guardian presentation: reduced-motion path.**
- [ ] **169. Guardian presentation: screen-reader label.**
- [ ] **170. Guardian presentation: tr() strings.**
- [ ] **171. Guardian presentation: save/load prefs.**
- [ ] **172. Guardian presentation: no spam on tank switch.**
- [ ] **173. Guardian presentation: no spam on focus thrash.**
- [ ] **174. Guardian presentation: photo-mode hush.**
- [ ] **175. Guardian presentation: aquascape hush for ambient.**
- [ ] **176. Guardian presentation: typing-focus hush.**
- [ ] **177. Guardian presentation: follow-strip coexistence.**
- [ ] **178. Guardian presentation: badge honesty.**
- [ ] **179. Guardian presentation: dedup window.**
- [ ] **180. Guardian presentation: severity mapping audited.**
- [ ] **181. Guardian presentation: copy tone warm/solemn as fit.**
- [ ] **182. Guardian presentation: Help docs sentence.**
- [ ] **183. Guardian presentation: Settings exposure.**
- [ ] **184. Guardian presentation: smoke assert.**
- [ ] **185. Guardian presentation: telemetry opt-in counter.**
- [ ] **186. Guardian presentation: Streamer profile interaction.**
- [ ] **187. Guardian presentation: Deck defaults.**
- [ ] **188. Guardian presentation: platform-disabled honesty (web/android LLM).**
- [ ] **189. Guardian presentation: refuse chatbot engagement loops.**
- [ ] **190. Guardian presentation: local privacy sentence when relevant.**
- [ ] **191. Guardian presentation: don't rebuild shipped mind pillars.**
- [ ] **192. Guardian presentation: cross-link PLAYER_WISH if overlapping.**
- [ ] **193. Guardian presentation: one commit per item when shipping.**
- [ ] **194. Guardian presentation: verify with headless smoke.**
- [ ] **195. Guardian presentation: mark checkbox in this doc.**
- [ ] **196. Guardian presentation: prefer journal over toast.**
- [ ] **197. Guardian presentation: prefer strip over toast when following.**
- [ ] **198. Guardian presentation: prefer Care CTA over essay.**
- [ ] **199. Guardian presentation: never mock death or nag consent.**
- [ ] **200. Guardian presentation: never yank camera for a line.**

## Section — Fish thought & reply UX (201–240)

*Grounding: `_on_fish_thought_spoke`, follow strip, `mind_conversation.gd`.*

- [ ] **201. Non-follow thoughts history-only by default. **(L)****
- [ ] **202. Fish thought UX: rate-limit ambient without silencing critical.**
- [ ] **203. Fish thought UX: respect quiet / Calm / battery saver.**
- [ ] **204. Fish thought UX: deep-link to Care / Residents / Settings when actionable.**
- [ ] **205. Fish thought UX: history vs toast policy explicit.**
- [ ] **206. Fish thought UX: mobile + desktop parity.**
- [ ] **207. Fish thought UX: gamepad dismiss/ack path.**
- [ ] **208. Fish thought UX: reduced-motion path.**
- [ ] **209. Fish thought UX: screen-reader label.**
- [ ] **210. Fish thought UX: tr() strings.**
- [ ] **211. Fish thought UX: save/load prefs.**
- [ ] **212. Fish thought UX: no spam on tank switch.**
- [ ] **213. Fish thought UX: no spam on focus thrash.**
- [ ] **214. Fish thought UX: photo-mode hush.**
- [ ] **215. Fish thought UX: aquascape hush for ambient.**
- [ ] **216. Fish thought UX: typing-focus hush.**
- [ ] **217. Fish thought UX: follow-strip coexistence.**
- [ ] **218. Fish thought UX: badge honesty.**
- [ ] **219. Fish thought UX: dedup window.**
- [ ] **220. Fish thought UX: severity mapping audited.**
- [ ] **221. Fish thought UX: copy tone warm/solemn as fit.**
- [ ] **222. Fish thought UX: Help docs sentence.**
- [ ] **223. Fish thought UX: Settings exposure.**
- [ ] **224. Fish thought UX: smoke assert.**
- [ ] **225. Fish thought UX: telemetry opt-in counter.**
- [ ] **226. Fish thought UX: Streamer profile interaction.**
- [ ] **227. Fish thought UX: Deck defaults.**
- [ ] **228. Fish thought UX: platform-disabled honesty (web/android LLM).**
- [ ] **229. Fish thought UX: refuse chatbot engagement loops.**
- [ ] **230. Fish thought UX: local privacy sentence when relevant.**
- [ ] **231. Fish thought UX: don't rebuild shipped mind pillars.**
- [ ] **232. Fish thought UX: cross-link PLAYER_WISH if overlapping.**
- [ ] **233. Fish thought UX: one commit per item when shipping.**
- [ ] **234. Fish thought UX: verify with headless smoke.**
- [ ] **235. Fish thought UX: mark checkbox in this doc.**
- [ ] **236. Fish thought UX: prefer journal over toast.**
- [ ] **237. Fish thought UX: prefer strip over toast when following.**
- [ ] **238. Fish thought UX: prefer Care CTA over essay.**
- [ ] **239. Fish thought UX: never mock death or nag consent.**
- [ ] **240. Fish thought UX: never yank camera for a line.**

## Section — Away, welcome & night ledger presentation (241–280)

*Grounding: `_show_welcome_back_if_returning`, `_emit_away_recap`, NightWatch.*

- [x] **241. Single return ceremony. Recap XOR welcome_back. **(L)****
- [ ] **242. Away/welcome ceremony: rate-limit ambient without silencing critical.**
- [ ] **243. Away/welcome ceremony: respect quiet / Calm / battery saver.**
- [ ] **244. Away/welcome ceremony: deep-link to Care / Residents / Settings when actionable.**
- [ ] **245. Away/welcome ceremony: history vs toast policy explicit.**
- [ ] **246. Away/welcome ceremony: mobile + desktop parity.**
- [ ] **247. Away/welcome ceremony: gamepad dismiss/ack path.**
- [ ] **248. Away/welcome ceremony: reduced-motion path.**
- [ ] **249. Away/welcome ceremony: screen-reader label.**
- [ ] **250. Away/welcome ceremony: tr() strings.**
- [ ] **251. Away/welcome ceremony: save/load prefs.**
- [ ] **252. Away/welcome ceremony: no spam on tank switch.**
- [ ] **253. Away/welcome ceremony: no spam on focus thrash.**
- [ ] **254. Away/welcome ceremony: photo-mode hush.**
- [ ] **255. Away/welcome ceremony: aquascape hush for ambient.**
- [ ] **256. Away/welcome ceremony: typing-focus hush.**
- [ ] **257. Away/welcome ceremony: follow-strip coexistence.**
- [ ] **258. Away/welcome ceremony: badge honesty.**
- [ ] **259. Away/welcome ceremony: dedup window.**
- [ ] **260. Away/welcome ceremony: severity mapping audited.**
- [ ] **261. Away/welcome ceremony: copy tone warm/solemn as fit.**
- [ ] **262. Away/welcome ceremony: Help docs sentence.**
- [ ] **263. Away/welcome ceremony: Settings exposure.**
- [ ] **264. Away/welcome ceremony: smoke assert.**
- [ ] **265. Away/welcome ceremony: telemetry opt-in counter.**
- [ ] **266. Away/welcome ceremony: Streamer profile interaction.**
- [ ] **267. Away/welcome ceremony: Deck defaults.**
- [ ] **268. Away/welcome ceremony: platform-disabled honesty (web/android LLM).**
- [ ] **269. Away/welcome ceremony: refuse chatbot engagement loops.**
- [ ] **270. Away/welcome ceremony: local privacy sentence when relevant.**
- [ ] **271. Away/welcome ceremony: don't rebuild shipped mind pillars.**
- [ ] **272. Away/welcome ceremony: cross-link PLAYER_WISH if overlapping.**
- [ ] **273. Away/welcome ceremony: one commit per item when shipping.**
- [ ] **274. Away/welcome ceremony: verify with headless smoke.**
- [ ] **275. Away/welcome ceremony: mark checkbox in this doc.**
- [ ] **276. Away/welcome ceremony: prefer journal over toast.**
- [ ] **277. Away/welcome ceremony: prefer strip over toast when following.**
- [ ] **278. Away/welcome ceremony: prefer Care CTA over essay.**
- [ ] **279. Away/welcome ceremony: never mock death or nag consent.**
- [ ] **280. Away/welcome ceremony: never yank camera for a line.**

## Section — Consent, first-run silence & boot (281–320)

*Grounding: `guardian_llm` consent, PLAYER_WISH #15.*

- [x] **281. Defer LLM consent past first 5 minutes. **(L)****
- [ ] **282. Consent/boot: rate-limit ambient without silencing critical.**
- [ ] **283. Consent/boot: respect quiet / Calm / battery saver.**
- [ ] **284. Consent/boot: deep-link to Care / Residents / Settings when actionable.**
- [ ] **285. Consent/boot: history vs toast policy explicit.**
- [ ] **286. Consent/boot: mobile + desktop parity.**
- [ ] **287. Consent/boot: gamepad dismiss/ack path.**
- [ ] **288. Consent/boot: reduced-motion path.**
- [ ] **289. Consent/boot: screen-reader label.**
- [ ] **290. Consent/boot: tr() strings.**
- [ ] **291. Consent/boot: save/load prefs.**
- [ ] **292. Consent/boot: no spam on tank switch.**
- [ ] **293. Consent/boot: no spam on focus thrash.**
- [ ] **294. Consent/boot: photo-mode hush.**
- [ ] **295. Consent/boot: aquascape hush for ambient.**
- [ ] **296. Consent/boot: typing-focus hush.**
- [ ] **297. Consent/boot: follow-strip coexistence.**
- [ ] **298. Consent/boot: badge honesty.**
- [ ] **299. Consent/boot: dedup window.**
- [ ] **300. Consent/boot: severity mapping audited.**
- [ ] **301. Consent/boot: copy tone warm/solemn as fit.**
- [ ] **302. Consent/boot: Help docs sentence.**
- [ ] **303. Consent/boot: Settings exposure.**
- [ ] **304. Consent/boot: smoke assert.**
- [ ] **305. Consent/boot: telemetry opt-in counter.**
- [ ] **306. Consent/boot: Streamer profile interaction.**
- [ ] **307. Consent/boot: Deck defaults.**
- [ ] **308. Consent/boot: platform-disabled honesty (web/android LLM).**
- [ ] **309. Consent/boot: refuse chatbot engagement loops.**
- [ ] **310. Consent/boot: local privacy sentence when relevant.**
- [ ] **311. Consent/boot: don't rebuild shipped mind pillars.**
- [ ] **312. Consent/boot: cross-link PLAYER_WISH if overlapping.**
- [ ] **313. Consent/boot: one commit per item when shipping.**
- [ ] **314. Consent/boot: verify with headless smoke.**
- [ ] **315. Consent/boot: mark checkbox in this doc.**
- [ ] **316. Consent/boot: prefer journal over toast.**
- [ ] **317. Consent/boot: prefer strip over toast when following.**
- [ ] **318. Consent/boot: prefer Care CTA over essay.**
- [ ] **319. Consent/boot: never mock death or nag consent.**
- [ ] **320. Consent/boot: never yank camera for a line.**

## Section — Care-gated speech without nag (321–360)

*Grounding: `keeper_care.gd`, guardian advisor lines.*

- [ ] **321. Care-gate advisor ≤1 per crisis episode. **(L)****
- [ ] **322. Care-gate speech: rate-limit ambient without silencing critical.**
- [ ] **323. Care-gate speech: respect quiet / Calm / battery saver.**
- [ ] **324. Care-gate speech: deep-link to Care / Residents / Settings when actionable.**
- [ ] **325. Care-gate speech: history vs toast policy explicit.**
- [ ] **326. Care-gate speech: mobile + desktop parity.**
- [ ] **327. Care-gate speech: gamepad dismiss/ack path.**
- [ ] **328. Care-gate speech: reduced-motion path.**
- [ ] **329. Care-gate speech: screen-reader label.**
- [ ] **330. Care-gate speech: tr() strings.**
- [ ] **331. Care-gate speech: save/load prefs.**
- [ ] **332. Care-gate speech: no spam on tank switch.**
- [ ] **333. Care-gate speech: no spam on focus thrash.**
- [ ] **334. Care-gate speech: photo-mode hush.**
- [ ] **335. Care-gate speech: aquascape hush for ambient.**
- [ ] **336. Care-gate speech: typing-focus hush.**
- [ ] **337. Care-gate speech: follow-strip coexistence.**
- [ ] **338. Care-gate speech: badge honesty.**
- [ ] **339. Care-gate speech: dedup window.**
- [ ] **340. Care-gate speech: severity mapping audited.**
- [ ] **341. Care-gate speech: copy tone warm/solemn as fit.**
- [ ] **342. Care-gate speech: Help docs sentence.**
- [ ] **343. Care-gate speech: Settings exposure.**
- [ ] **344. Care-gate speech: smoke assert.**
- [ ] **345. Care-gate speech: telemetry opt-in counter.**
- [ ] **346. Care-gate speech: Streamer profile interaction.**
- [ ] **347. Care-gate speech: Deck defaults.**
- [ ] **348. Care-gate speech: platform-disabled honesty (web/android LLM).**
- [ ] **349. Care-gate speech: refuse chatbot engagement loops.**
- [ ] **350. Care-gate speech: local privacy sentence when relevant.**
- [ ] **351. Care-gate speech: don't rebuild shipped mind pillars.**
- [ ] **352. Care-gate speech: cross-link PLAYER_WISH if overlapping.**
- [ ] **353. Care-gate speech: one commit per item when shipping.**
- [ ] **354. Care-gate speech: verify with headless smoke.**
- [ ] **355. Care-gate speech: mark checkbox in this doc.**
- [ ] **356. Care-gate speech: prefer journal over toast.**
- [ ] **357. Care-gate speech: prefer strip over toast when following.**
- [ ] **358. Care-gate speech: prefer Care CTA over essay.**
- [ ] **359. Care-gate speech: never mock death or nag consent.**
- [ ] **360. Care-gate speech: never yank camera for a line.**

## Section — Death, population & discovery restraint (361–400)

*Grounding: memorial toasts, population events.*

- [x] **361. Mass death summary toast. **(L)****
- [ ] **362. Death restraint: rate-limit ambient without silencing critical.**
- [ ] **363. Death restraint: respect quiet / Calm / battery saver.**
- [ ] **364. Death restraint: deep-link to Care / Residents / Settings when actionable.**
- [ ] **365. Death restraint: history vs toast policy explicit.**
- [ ] **366. Death restraint: mobile + desktop parity.**
- [ ] **367. Death restraint: gamepad dismiss/ack path.**
- [ ] **368. Death restraint: reduced-motion path.**
- [ ] **369. Death restraint: screen-reader label.**
- [ ] **370. Death restraint: tr() strings.**
- [ ] **371. Death restraint: save/load prefs.**
- [ ] **372. Death restraint: no spam on tank switch.**
- [ ] **373. Death restraint: no spam on focus thrash.**
- [ ] **374. Death restraint: photo-mode hush.**
- [ ] **375. Death restraint: aquascape hush for ambient.**
- [ ] **376. Death restraint: typing-focus hush.**
- [ ] **377. Death restraint: follow-strip coexistence.**
- [ ] **378. Death restraint: badge honesty.**
- [ ] **379. Death restraint: dedup window.**
- [ ] **380. Death restraint: severity mapping audited.**
- [ ] **381. Death restraint: copy tone warm/solemn as fit.**
- [ ] **382. Death restraint: Help docs sentence.**
- [ ] **383. Death restraint: Settings exposure.**
- [ ] **384. Death restraint: smoke assert.**
- [ ] **385. Death restraint: telemetry opt-in counter.**
- [ ] **386. Death restraint: Streamer profile interaction.**
- [ ] **387. Death restraint: Deck defaults.**
- [ ] **388. Death restraint: platform-disabled honesty (web/android LLM).**
- [ ] **389. Death restraint: refuse chatbot engagement loops.**
- [ ] **390. Death restraint: local privacy sentence when relevant.**
- [ ] **391. Death restraint: don't rebuild shipped mind pillars.**
- [ ] **392. Death restraint: cross-link PLAYER_WISH if overlapping.**
- [ ] **393. Death restraint: one commit per item when shipping.**
- [ ] **394. Death restraint: verify with headless smoke.**
- [ ] **395. Death restraint: mark checkbox in this doc.**
- [ ] **396. Death restraint: prefer journal over toast.**
- [ ] **397. Death restraint: prefer strip over toast when following.**
- [ ] **398. Death restraint: prefer Care CTA over essay.**
- [ ] **399. Death restraint: never mock death or nag consent.**
- [ ] **400. Death restraint: never yank camera for a line.**

## Section — Caption, coachmark & teaching coexistence (401–440)

*Grounding: `onboarding_runtime._show_caption`, coachmarks.*

- [x] **401. Global ambient caption budget 1 / 20s into arbiter. **(L)****
- [ ] **402. Caption budget: rate-limit ambient without silencing critical.**
- [ ] **403. Caption budget: respect quiet / Calm / battery saver.**
- [ ] **404. Caption budget: deep-link to Care / Residents / Settings when actionable.**
- [ ] **405. Caption budget: history vs toast policy explicit.**
- [ ] **406. Caption budget: mobile + desktop parity.**
- [ ] **407. Caption budget: gamepad dismiss/ack path.**
- [ ] **408. Caption budget: reduced-motion path.**
- [ ] **409. Caption budget: screen-reader label.**
- [ ] **410. Caption budget: tr() strings.**
- [ ] **411. Caption budget: save/load prefs.**
- [ ] **412. Caption budget: no spam on tank switch.**
- [ ] **413. Caption budget: no spam on focus thrash.**
- [ ] **414. Caption budget: photo-mode hush.**
- [ ] **415. Caption budget: aquascape hush for ambient.**
- [ ] **416. Caption budget: typing-focus hush.**
- [ ] **417. Caption budget: follow-strip coexistence.**
- [ ] **418. Caption budget: badge honesty.**
- [ ] **419. Caption budget: dedup window.**
- [ ] **420. Caption budget: severity mapping audited.**
- [ ] **421. Caption budget: copy tone warm/solemn as fit.**
- [ ] **422. Caption budget: Help docs sentence.**
- [ ] **423. Caption budget: Settings exposure.**
- [ ] **424. Caption budget: smoke assert.**
- [ ] **425. Caption budget: telemetry opt-in counter.**
- [ ] **426. Caption budget: Streamer profile interaction.**
- [ ] **427. Caption budget: Deck defaults.**
- [ ] **428. Caption budget: platform-disabled honesty (web/android LLM).**
- [ ] **429. Caption budget: refuse chatbot engagement loops.**
- [ ] **430. Caption budget: local privacy sentence when relevant.**
- [ ] **431. Caption budget: don't rebuild shipped mind pillars.**
- [ ] **432. Caption budget: cross-link PLAYER_WISH if overlapping.**
- [ ] **433. Caption budget: one commit per item when shipping.**
- [ ] **434. Caption budget: verify with headless smoke.**
- [ ] **435. Caption budget: mark checkbox in this doc.**
- [ ] **436. Caption budget: prefer journal over toast.**
- [ ] **437. Caption budget: prefer strip over toast when following.**
- [ ] **438. Caption budget: prefer Care CTA over essay.**
- [ ] **439. Caption budget: never mock death or nag consent.**
- [ ] **440. Caption budget: never yank camera for a line.**

## Section — Settings → Communications surface (441–480)

*Grounding: `settings_panel.gd` AI tab.*

- [ ] **441. Communications & Voice settings section. **(L)****
- [ ] **442. Communications settings: rate-limit ambient without silencing critical.**
- [ ] **443. Communications settings: respect quiet / Calm / battery saver.**
- [ ] **444. Communications settings: deep-link to Care / Residents / Settings when actionable.**
- [ ] **445. Communications settings: history vs toast policy explicit.**
- [ ] **446. Communications settings: mobile + desktop parity.**
- [ ] **447. Communications settings: gamepad dismiss/ack path.**
- [ ] **448. Communications settings: reduced-motion path.**
- [ ] **449. Communications settings: screen-reader label.**
- [ ] **450. Communications settings: tr() strings.**
- [ ] **451. Communications settings: save/load prefs.**
- [ ] **452. Communications settings: no spam on tank switch.**
- [ ] **453. Communications settings: no spam on focus thrash.**
- [ ] **454. Communications settings: photo-mode hush.**
- [ ] **455. Communications settings: aquascape hush for ambient.**
- [ ] **456. Communications settings: typing-focus hush.**
- [ ] **457. Communications settings: follow-strip coexistence.**
- [ ] **458. Communications settings: badge honesty.**
- [ ] **459. Communications settings: dedup window.**
- [ ] **460. Communications settings: severity mapping audited.**
- [ ] **461. Communications settings: copy tone warm/solemn as fit.**
- [ ] **462. Communications settings: Help docs sentence.**
- [ ] **463. Communications settings: Settings exposure.**
- [ ] **464. Communications settings: smoke assert.**
- [ ] **465. Communications settings: telemetry opt-in counter.**
- [ ] **466. Communications settings: Streamer profile interaction.**
- [ ] **467. Communications settings: Deck defaults.**
- [ ] **468. Communications settings: platform-disabled honesty (web/android LLM).**
- [ ] **469. Communications settings: refuse chatbot engagement loops.**
- [ ] **470. Communications settings: local privacy sentence when relevant.**
- [ ] **471. Communications settings: don't rebuild shipped mind pillars.**
- [ ] **472. Communications settings: cross-link PLAYER_WISH if overlapping.**
- [ ] **473. Communications settings: one commit per item when shipping.**
- [ ] **474. Communications settings: verify with headless smoke.**
- [ ] **475. Communications settings: mark checkbox in this doc.**
- [ ] **476. Communications settings: prefer journal over toast.**
- [ ] **477. Communications settings: prefer strip over toast when following.**
- [ ] **478. Communications settings: prefer Care CTA over essay.**
- [ ] **479. Communications settings: never mock death or nag consent.**
- [ ] **480. Communications settings: never yank camera for a line.**

## Section — Accessibility for voice & text (481–520)

*Grounding: captions, reduced motion, pause-on-menu.*

- [ ] **481. Captions for guardian/fish when voice on. **(L)****
- [ ] **482. Comms accessibility: rate-limit ambient without silencing critical.**
- [ ] **483. Comms accessibility: respect quiet / Calm / battery saver.**
- [ ] **484. Comms accessibility: deep-link to Care / Residents / Settings when actionable.**
- [ ] **485. Comms accessibility: history vs toast policy explicit.**
- [ ] **486. Comms accessibility: mobile + desktop parity.**
- [ ] **487. Comms accessibility: gamepad dismiss/ack path.**
- [ ] **488. Comms accessibility: reduced-motion path.**
- [ ] **489. Comms accessibility: screen-reader label.**
- [ ] **490. Comms accessibility: tr() strings.**
- [ ] **491. Comms accessibility: save/load prefs.**
- [ ] **492. Comms accessibility: no spam on tank switch.**
- [ ] **493. Comms accessibility: no spam on focus thrash.**
- [ ] **494. Comms accessibility: photo-mode hush.**
- [ ] **495. Comms accessibility: aquascape hush for ambient.**
- [ ] **496. Comms accessibility: typing-focus hush.**
- [ ] **497. Comms accessibility: follow-strip coexistence.**
- [ ] **498. Comms accessibility: badge honesty.**
- [ ] **499. Comms accessibility: dedup window.**
- [ ] **500. Comms accessibility: severity mapping audited.**
- [ ] **501. Comms accessibility: copy tone warm/solemn as fit.**
- [ ] **502. Comms accessibility: Help docs sentence.**
- [ ] **503. Comms accessibility: Settings exposure.**
- [ ] **504. Comms accessibility: smoke assert.**
- [ ] **505. Comms accessibility: telemetry opt-in counter.**
- [ ] **506. Comms accessibility: Streamer profile interaction.**
- [ ] **507. Comms accessibility: Deck defaults.**
- [ ] **508. Comms accessibility: platform-disabled honesty (web/android LLM).**
- [ ] **509. Comms accessibility: refuse chatbot engagement loops.**
- [ ] **510. Comms accessibility: local privacy sentence when relevant.**
- [ ] **511. Comms accessibility: don't rebuild shipped mind pillars.**
- [ ] **512. Comms accessibility: cross-link PLAYER_WISH if overlapping.**
- [ ] **513. Comms accessibility: one commit per item when shipping.**
- [ ] **514. Comms accessibility: verify with headless smoke.**
- [ ] **515. Comms accessibility: mark checkbox in this doc.**
- [ ] **516. Comms accessibility: prefer journal over toast.**
- [ ] **517. Comms accessibility: prefer strip over toast when following.**
- [ ] **518. Comms accessibility: prefer Care CTA over essay.**
- [ ] **519. Comms accessibility: never mock death or nag consent.**
- [ ] **520. Comms accessibility: never yank camera for a line.**

## Section — Journal, diary & chronicle UX (521–560)

*Grounding: `guardian_journal.gd`, story popup.*

- [ ] **521. Diary tab opens to newest; append never toasts. **(L)****
- [ ] **522. Journal/diary: rate-limit ambient without silencing critical.**
- [ ] **523. Journal/diary: respect quiet / Calm / battery saver.**
- [ ] **524. Journal/diary: deep-link to Care / Residents / Settings when actionable.**
- [ ] **525. Journal/diary: history vs toast policy explicit.**
- [ ] **526. Journal/diary: mobile + desktop parity.**
- [ ] **527. Journal/diary: gamepad dismiss/ack path.**
- [ ] **528. Journal/diary: reduced-motion path.**
- [ ] **529. Journal/diary: screen-reader label.**
- [ ] **530. Journal/diary: tr() strings.**
- [ ] **531. Journal/diary: save/load prefs.**
- [ ] **532. Journal/diary: no spam on tank switch.**
- [ ] **533. Journal/diary: no spam on focus thrash.**
- [ ] **534. Journal/diary: photo-mode hush.**
- [ ] **535. Journal/diary: aquascape hush for ambient.**
- [ ] **536. Journal/diary: typing-focus hush.**
- [ ] **537. Journal/diary: follow-strip coexistence.**
- [ ] **538. Journal/diary: badge honesty.**
- [ ] **539. Journal/diary: dedup window.**
- [ ] **540. Journal/diary: severity mapping audited.**
- [ ] **541. Journal/diary: copy tone warm/solemn as fit.**
- [ ] **542. Journal/diary: Help docs sentence.**
- [ ] **543. Journal/diary: Settings exposure.**
- [ ] **544. Journal/diary: smoke assert.**
- [ ] **545. Journal/diary: telemetry opt-in counter.**
- [ ] **546. Journal/diary: Streamer profile interaction.**
- [ ] **547. Journal/diary: Deck defaults.**
- [ ] **548. Journal/diary: platform-disabled honesty (web/android LLM).**
- [ ] **549. Journal/diary: refuse chatbot engagement loops.**
- [ ] **550. Journal/diary: local privacy sentence when relevant.**
- [ ] **551. Journal/diary: don't rebuild shipped mind pillars.**
- [ ] **552. Journal/diary: cross-link PLAYER_WISH if overlapping.**
- [ ] **553. Journal/diary: one commit per item when shipping.**
- [ ] **554. Journal/diary: verify with headless smoke.**
- [ ] **555. Journal/diary: mark checkbox in this doc.**
- [ ] **556. Journal/diary: prefer journal over toast.**
- [ ] **557. Journal/diary: prefer strip over toast when following.**
- [ ] **558. Journal/diary: prefer Care CTA over essay.**
- [ ] **559. Journal/diary: never mock death or nag consent.**
- [ ] **560. Journal/diary: never yank camera for a line.**

## Section — Follow strip & PiP coexistence (561–600)

*Grounding: `_follow_thought_strip`, portal PiP.*

- [ ] **561. Strip vs toast clearance shared with status lane. **(L)****
- [ ] **562. Follow strip: rate-limit ambient without silencing critical.**
- [ ] **563. Follow strip: respect quiet / Calm / battery saver.**
- [ ] **564. Follow strip: deep-link to Care / Residents / Settings when actionable.**
- [ ] **565. Follow strip: history vs toast policy explicit.**
- [ ] **566. Follow strip: mobile + desktop parity.**
- [ ] **567. Follow strip: gamepad dismiss/ack path.**
- [ ] **568. Follow strip: reduced-motion path.**
- [ ] **569. Follow strip: screen-reader label.**
- [ ] **570. Follow strip: tr() strings.**
- [ ] **571. Follow strip: save/load prefs.**
- [ ] **572. Follow strip: no spam on tank switch.**
- [ ] **573. Follow strip: no spam on focus thrash.**
- [ ] **574. Follow strip: photo-mode hush.**
- [ ] **575. Follow strip: aquascape hush for ambient.**
- [ ] **576. Follow strip: typing-focus hush.**
- [ ] **577. Follow strip: follow-strip coexistence.**
- [ ] **578. Follow strip: badge honesty.**
- [ ] **579. Follow strip: dedup window.**
- [ ] **580. Follow strip: severity mapping audited.**
- [ ] **581. Follow strip: copy tone warm/solemn as fit.**
- [ ] **582. Follow strip: Help docs sentence.**
- [ ] **583. Follow strip: Settings exposure.**
- [ ] **584. Follow strip: smoke assert.**
- [ ] **585. Follow strip: telemetry opt-in counter.**
- [ ] **586. Follow strip: Streamer profile interaction.**
- [ ] **587. Follow strip: Deck defaults.**
- [ ] **588. Follow strip: platform-disabled honesty (web/android LLM).**
- [ ] **589. Follow strip: refuse chatbot engagement loops.**
- [ ] **590. Follow strip: local privacy sentence when relevant.**
- [ ] **591. Follow strip: don't rebuild shipped mind pillars.**
- [ ] **592. Follow strip: cross-link PLAYER_WISH if overlapping.**
- [ ] **593. Follow strip: one commit per item when shipping.**
- [ ] **594. Follow strip: verify with headless smoke.**
- [ ] **595. Follow strip: mark checkbox in this doc.**
- [ ] **596. Follow strip: prefer journal over toast.**
- [ ] **597. Follow strip: prefer strip over toast when following.**
- [ ] **598. Follow strip: prefer Care CTA over essay.**
- [ ] **599. Follow strip: never mock death or nag consent.**
- [ ] **600. Follow strip: never yank camera for a line.**

## Section — Mobile & gamepad communications (601–640)

*Grounding: mobile_hud, gamepad menu.*

- [ ] **601. Mobile Alerts + toast tap targets ≥44pt. **(L)****
- [ ] **602. Mobile/gamepad comms: rate-limit ambient without silencing critical.**
- [ ] **603. Mobile/gamepad comms: respect quiet / Calm / battery saver.**
- [ ] **604. Mobile/gamepad comms: deep-link to Care / Residents / Settings when actionable.**
- [ ] **605. Mobile/gamepad comms: history vs toast policy explicit.**
- [ ] **606. Mobile/gamepad comms: mobile + desktop parity.**
- [ ] **607. Mobile/gamepad comms: gamepad dismiss/ack path.**
- [ ] **608. Mobile/gamepad comms: reduced-motion path.**
- [ ] **609. Mobile/gamepad comms: screen-reader label.**
- [ ] **610. Mobile/gamepad comms: tr() strings.**
- [ ] **611. Mobile/gamepad comms: save/load prefs.**
- [ ] **612. Mobile/gamepad comms: no spam on tank switch.**
- [ ] **613. Mobile/gamepad comms: no spam on focus thrash.**
- [ ] **614. Mobile/gamepad comms: photo-mode hush.**
- [ ] **615. Mobile/gamepad comms: aquascape hush for ambient.**
- [ ] **616. Mobile/gamepad comms: typing-focus hush.**
- [ ] **617. Mobile/gamepad comms: follow-strip coexistence.**
- [ ] **618. Mobile/gamepad comms: badge honesty.**
- [ ] **619. Mobile/gamepad comms: dedup window.**
- [ ] **620. Mobile/gamepad comms: severity mapping audited.**
- [ ] **621. Mobile/gamepad comms: copy tone warm/solemn as fit.**
- [ ] **622. Mobile/gamepad comms: Help docs sentence.**
- [ ] **623. Mobile/gamepad comms: Settings exposure.**
- [ ] **624. Mobile/gamepad comms: smoke assert.**
- [ ] **625. Mobile/gamepad comms: telemetry opt-in counter.**
- [ ] **626. Mobile/gamepad comms: Streamer profile interaction.**
- [ ] **627. Mobile/gamepad comms: Deck defaults.**
- [ ] **628. Mobile/gamepad comms: platform-disabled honesty (web/android LLM).**
- [ ] **629. Mobile/gamepad comms: refuse chatbot engagement loops.**
- [ ] **630. Mobile/gamepad comms: local privacy sentence when relevant.**
- [ ] **631. Mobile/gamepad comms: don't rebuild shipped mind pillars.**
- [ ] **632. Mobile/gamepad comms: cross-link PLAYER_WISH if overlapping.**
- [ ] **633. Mobile/gamepad comms: one commit per item when shipping.**
- [ ] **634. Mobile/gamepad comms: verify with headless smoke.**
- [ ] **635. Mobile/gamepad comms: mark checkbox in this doc.**
- [ ] **636. Mobile/gamepad comms: prefer journal over toast.**
- [ ] **637. Mobile/gamepad comms: prefer strip over toast when following.**
- [ ] **638. Mobile/gamepad comms: prefer Care CTA over essay.**
- [ ] **639. Mobile/gamepad comms: never mock death or nag consent.**
- [ ] **640. Mobile/gamepad comms: never yank camera for a line.**

## Section — Performance of the inbox (641–680)

*Grounding: history cap 300, toast GPU.*

- [ ] **641. History list virtualized; toast cards pooled. **(L)****
- [ ] **642. Inbox performance: rate-limit ambient without silencing critical.**
- [ ] **643. Inbox performance: respect quiet / Calm / battery saver.**
- [ ] **644. Inbox performance: deep-link to Care / Residents / Settings when actionable.**
- [ ] **645. Inbox performance: history vs toast policy explicit.**
- [ ] **646. Inbox performance: mobile + desktop parity.**
- [ ] **647. Inbox performance: gamepad dismiss/ack path.**
- [ ] **648. Inbox performance: reduced-motion path.**
- [ ] **649. Inbox performance: screen-reader label.**
- [ ] **650. Inbox performance: tr() strings.**
- [ ] **651. Inbox performance: save/load prefs.**
- [ ] **652. Inbox performance: no spam on tank switch.**
- [ ] **653. Inbox performance: no spam on focus thrash.**
- [ ] **654. Inbox performance: photo-mode hush.**
- [ ] **655. Inbox performance: aquascape hush for ambient.**
- [ ] **656. Inbox performance: typing-focus hush.**
- [ ] **657. Inbox performance: follow-strip coexistence.**
- [ ] **658. Inbox performance: badge honesty.**
- [ ] **659. Inbox performance: dedup window.**
- [ ] **660. Inbox performance: severity mapping audited.**
- [ ] **661. Inbox performance: copy tone warm/solemn as fit.**
- [ ] **662. Inbox performance: Help docs sentence.**
- [ ] **663. Inbox performance: Settings exposure.**
- [ ] **664. Inbox performance: smoke assert.**
- [ ] **665. Inbox performance: telemetry opt-in counter.**
- [ ] **666. Inbox performance: Streamer profile interaction.**
- [ ] **667. Inbox performance: Deck defaults.**
- [ ] **668. Inbox performance: platform-disabled honesty (web/android LLM).**
- [ ] **669. Inbox performance: refuse chatbot engagement loops.**
- [ ] **670. Inbox performance: local privacy sentence when relevant.**
- [ ] **671. Inbox performance: don't rebuild shipped mind pillars.**
- [ ] **672. Inbox performance: cross-link PLAYER_WISH if overlapping.**
- [ ] **673. Inbox performance: one commit per item when shipping.**
- [ ] **674. Inbox performance: verify with headless smoke.**
- [ ] **675. Inbox performance: mark checkbox in this doc.**
- [ ] **676. Inbox performance: prefer journal over toast.**
- [ ] **677. Inbox performance: prefer strip over toast when following.**
- [ ] **678. Inbox performance: prefer Care CTA over essay.**
- [ ] **679. Inbox performance: never mock death or nag consent.**
- [ ] **680. Inbox performance: never yank camera for a line.**

## Section — Trust, honesty & anti-annoyance for AI voice (681–720)

*Grounding: template honesty, no chatbot vibe.*

- [ ] **681. Never claim feelings the model didn't earn; show tier honesty. **(L)****
- [ ] **682. Trust/honesty: rate-limit ambient without silencing critical.**
- [ ] **683. Trust/honesty: respect quiet / Calm / battery saver.**
- [ ] **684. Trust/honesty: deep-link to Care / Residents / Settings when actionable.**
- [ ] **685. Trust/honesty: history vs toast policy explicit.**
- [ ] **686. Trust/honesty: mobile + desktop parity.**
- [ ] **687. Trust/honesty: gamepad dismiss/ack path.**
- [ ] **688. Trust/honesty: reduced-motion path.**
- [ ] **689. Trust/honesty: screen-reader label.**
- [ ] **690. Trust/honesty: tr() strings.**
- [ ] **691. Trust/honesty: save/load prefs.**
- [ ] **692. Trust/honesty: no spam on tank switch.**
- [ ] **693. Trust/honesty: no spam on focus thrash.**
- [ ] **694. Trust/honesty: photo-mode hush.**
- [ ] **695. Trust/honesty: aquascape hush for ambient.**
- [ ] **696. Trust/honesty: typing-focus hush.**
- [ ] **697. Trust/honesty: follow-strip coexistence.**
- [ ] **698. Trust/honesty: badge honesty.**
- [ ] **699. Trust/honesty: dedup window.**
- [ ] **700. Trust/honesty: severity mapping audited.**
- [ ] **701. Trust/honesty: copy tone warm/solemn as fit.**
- [ ] **702. Trust/honesty: Help docs sentence.**
- [ ] **703. Trust/honesty: Settings exposure.**
- [ ] **704. Trust/honesty: smoke assert.**
- [ ] **705. Trust/honesty: telemetry opt-in counter.**
- [ ] **706. Trust/honesty: Streamer profile interaction.**
- [ ] **707. Trust/honesty: Deck defaults.**
- [ ] **708. Trust/honesty: platform-disabled honesty (web/android LLM).**
- [ ] **709. Trust/honesty: refuse chatbot engagement loops.**
- [ ] **710. Trust/honesty: local privacy sentence when relevant.**
- [ ] **711. Trust/honesty: don't rebuild shipped mind pillars.**
- [ ] **712. Trust/honesty: cross-link PLAYER_WISH if overlapping.**
- [ ] **713. Trust/honesty: one commit per item when shipping.**
- [ ] **714. Trust/honesty: verify with headless smoke.**
- [ ] **715. Trust/honesty: mark checkbox in this doc.**
- [ ] **716. Trust/honesty: prefer journal over toast.**
- [ ] **717. Trust/honesty: prefer strip over toast when following.**
- [ ] **718. Trust/honesty: prefer Care CTA over essay.**
- [ ] **719. Trust/honesty: never mock death or nag consent.**
- [ ] **720. Trust/honesty: never yank camera for a line.**

## Section — OS, Steam & external notify (721–760)

*Grounding: OS notifications, rich presence.*

- [ ] **721. OS notify opt-in default off; critical water preset. **(L)****
- [ ] **722. OS/Steam notify: rate-limit ambient without silencing critical.**
- [ ] **723. OS/Steam notify: respect quiet / Calm / battery saver.**
- [ ] **724. OS/Steam notify: deep-link to Care / Residents / Settings when actionable.**
- [ ] **725. OS/Steam notify: history vs toast policy explicit.**
- [ ] **726. OS/Steam notify: mobile + desktop parity.**
- [ ] **727. OS/Steam notify: gamepad dismiss/ack path.**
- [ ] **728. OS/Steam notify: reduced-motion path.**
- [ ] **729. OS/Steam notify: screen-reader label.**
- [ ] **730. OS/Steam notify: tr() strings.**
- [ ] **731. OS/Steam notify: save/load prefs.**
- [ ] **732. OS/Steam notify: no spam on tank switch.**
- [ ] **733. OS/Steam notify: no spam on focus thrash.**
- [ ] **734. OS/Steam notify: photo-mode hush.**
- [ ] **735. OS/Steam notify: aquascape hush for ambient.**
- [ ] **736. OS/Steam notify: typing-focus hush.**
- [ ] **737. OS/Steam notify: follow-strip coexistence.**
- [ ] **738. OS/Steam notify: badge honesty.**
- [ ] **739. OS/Steam notify: dedup window.**
- [ ] **740. OS/Steam notify: severity mapping audited.**
- [ ] **741. OS/Steam notify: copy tone warm/solemn as fit.**
- [ ] **742. OS/Steam notify: Help docs sentence.**
- [ ] **743. OS/Steam notify: Settings exposure.**
- [ ] **744. OS/Steam notify: smoke assert.**
- [ ] **745. OS/Steam notify: telemetry opt-in counter.**
- [ ] **746. OS/Steam notify: Streamer profile interaction.**
- [ ] **747. OS/Steam notify: Deck defaults.**
- [ ] **748. OS/Steam notify: platform-disabled honesty (web/android LLM).**
- [ ] **749. OS/Steam notify: refuse chatbot engagement loops.**
- [ ] **750. OS/Steam notify: local privacy sentence when relevant.**
- [ ] **751. OS/Steam notify: don't rebuild shipped mind pillars.**
- [ ] **752. OS/Steam notify: cross-link PLAYER_WISH if overlapping.**
- [ ] **753. OS/Steam notify: one commit per item when shipping.**
- [ ] **754. OS/Steam notify: verify with headless smoke.**
- [ ] **755. OS/Steam notify: mark checkbox in this doc.**
- [ ] **756. OS/Steam notify: prefer journal over toast.**
- [ ] **757. OS/Steam notify: prefer strip over toast when following.**
- [ ] **758. OS/Steam notify: prefer Care CTA over essay.**
- [ ] **759. OS/Steam notify: never mock death or nag consent.**
- [ ] **760. OS/Steam notify: never yank camera for a line.**

## Section — Copy tone for the speaking tank (761–800)

*Grounding: MindNarrator sanitize, toast titles.*

- [ ] **761. Communications copy guide; no 'AI' in player toasts. **(L)****
- [ ] **762. Comms copy: rate-limit ambient without silencing critical.**
- [ ] **763. Comms copy: respect quiet / Calm / battery saver.**
- [ ] **764. Comms copy: deep-link to Care / Residents / Settings when actionable.**
- [ ] **765. Comms copy: history vs toast policy explicit.**
- [ ] **766. Comms copy: mobile + desktop parity.**
- [ ] **767. Comms copy: gamepad dismiss/ack path.**
- [ ] **768. Comms copy: reduced-motion path.**
- [ ] **769. Comms copy: screen-reader label.**
- [ ] **770. Comms copy: tr() strings.**
- [ ] **771. Comms copy: save/load prefs.**
- [ ] **772. Comms copy: no spam on tank switch.**
- [ ] **773. Comms copy: no spam on focus thrash.**
- [ ] **774. Comms copy: photo-mode hush.**
- [ ] **775. Comms copy: aquascape hush for ambient.**
- [ ] **776. Comms copy: typing-focus hush.**
- [ ] **777. Comms copy: follow-strip coexistence.**
- [ ] **778. Comms copy: badge honesty.**
- [ ] **779. Comms copy: dedup window.**
- [ ] **780. Comms copy: severity mapping audited.**
- [ ] **781. Comms copy: copy tone warm/solemn as fit.**
- [ ] **782. Comms copy: Help docs sentence.**
- [ ] **783. Comms copy: Settings exposure.**
- [ ] **784. Comms copy: smoke assert.**
- [ ] **785. Comms copy: telemetry opt-in counter.**
- [ ] **786. Comms copy: Streamer profile interaction.**
- [ ] **787. Comms copy: Deck defaults.**
- [ ] **788. Comms copy: platform-disabled honesty (web/android LLM).**
- [ ] **789. Comms copy: refuse chatbot engagement loops.**
- [ ] **790. Comms copy: local privacy sentence when relevant.**
- [ ] **791. Comms copy: don't rebuild shipped mind pillars.**
- [ ] **792. Comms copy: cross-link PLAYER_WISH if overlapping.**
- [ ] **793. Comms copy: one commit per item when shipping.**
- [ ] **794. Comms copy: verify with headless smoke.**
- [ ] **795. Comms copy: mark checkbox in this doc.**
- [ ] **796. Comms copy: prefer journal over toast.**
- [ ] **797. Comms copy: prefer strip over toast when following.**
- [ ] **798. Comms copy: prefer Care CTA over essay.**
- [ ] **799. Comms copy: never mock death or nag consent.**
- [ ] **800. Comms copy: never yank camera for a line.**

## Section — Debug, QA & spam telemetry (801–840)

*Grounding: smokes, hitch banners.*

- [x] **801. smoke_comms_inbox.gd covers foundations. **(L)****
- [ ] **802. Comms QA/smoke: rate-limit ambient without silencing critical.**
- [ ] **803. Comms QA/smoke: respect quiet / Calm / battery saver.**
- [ ] **804. Comms QA/smoke: deep-link to Care / Residents / Settings when actionable.**
- [ ] **805. Comms QA/smoke: history vs toast policy explicit.**
- [ ] **806. Comms QA/smoke: mobile + desktop parity.**
- [ ] **807. Comms QA/smoke: gamepad dismiss/ack path.**
- [ ] **808. Comms QA/smoke: reduced-motion path.**
- [ ] **809. Comms QA/smoke: screen-reader label.**
- [ ] **810. Comms QA/smoke: tr() strings.**
- [ ] **811. Comms QA/smoke: save/load prefs.**
- [ ] **812. Comms QA/smoke: no spam on tank switch.**
- [ ] **813. Comms QA/smoke: no spam on focus thrash.**
- [ ] **814. Comms QA/smoke: photo-mode hush.**
- [ ] **815. Comms QA/smoke: aquascape hush for ambient.**
- [ ] **816. Comms QA/smoke: typing-focus hush.**
- [ ] **817. Comms QA/smoke: follow-strip coexistence.**
- [ ] **818. Comms QA/smoke: badge honesty.**
- [ ] **819. Comms QA/smoke: dedup window.**
- [ ] **820. Comms QA/smoke: severity mapping audited.**
- [ ] **821. Comms QA/smoke: copy tone warm/solemn as fit.**
- [ ] **822. Comms QA/smoke: Help docs sentence.**
- [ ] **823. Comms QA/smoke: Settings exposure.**
- [ ] **824. Comms QA/smoke: smoke assert.**
- [ ] **825. Comms QA/smoke: telemetry opt-in counter.**
- [ ] **826. Comms QA/smoke: Streamer profile interaction.**
- [ ] **827. Comms QA/smoke: Deck defaults.**
- [ ] **828. Comms QA/smoke: platform-disabled honesty (web/android LLM).**
- [ ] **829. Comms QA/smoke: refuse chatbot engagement loops.**
- [ ] **830. Comms QA/smoke: local privacy sentence when relevant.**
- [ ] **831. Comms QA/smoke: don't rebuild shipped mind pillars.**
- [ ] **832. Comms QA/smoke: cross-link PLAYER_WISH if overlapping.**
- [ ] **833. Comms QA/smoke: one commit per item when shipping.**
- [ ] **834. Comms QA/smoke: verify with headless smoke.**
- [ ] **835. Comms QA/smoke: mark checkbox in this doc.**
- [ ] **836. Comms QA/smoke: prefer journal over toast.**
- [ ] **837. Comms QA/smoke: prefer strip over toast when following.**
- [ ] **838. Comms QA/smoke: prefer Care CTA over essay.**
- [ ] **839. Comms QA/smoke: never mock death or nag consent.**
- [ ] **840. Comms QA/smoke: never yank camera for a line.**

## Section — Cross-links to PLAYER_WISH / shipped pillars (841–880)

*Grounding: do not fork; ship or reference.*

- [ ] **841. PLAYER_WISH cross-links: ship once, mark both docs. **(L)****
- [ ] **842. Cross-link discipline: rate-limit ambient without silencing critical.**
- [ ] **843. Cross-link discipline: respect quiet / Calm / battery saver.**
- [ ] **844. Cross-link discipline: deep-link to Care / Residents / Settings when actionable.**
- [ ] **845. Cross-link discipline: history vs toast policy explicit.**
- [ ] **846. Cross-link discipline: mobile + desktop parity.**
- [ ] **847. Cross-link discipline: gamepad dismiss/ack path.**
- [ ] **848. Cross-link discipline: reduced-motion path.**
- [ ] **849. Cross-link discipline: screen-reader label.**
- [ ] **850. Cross-link discipline: tr() strings.**
- [ ] **851. Cross-link discipline: save/load prefs.**
- [ ] **852. Cross-link discipline: no spam on tank switch.**
- [ ] **853. Cross-link discipline: no spam on focus thrash.**
- [ ] **854. Cross-link discipline: photo-mode hush.**
- [ ] **855. Cross-link discipline: aquascape hush for ambient.**
- [ ] **856. Cross-link discipline: typing-focus hush.**
- [ ] **857. Cross-link discipline: follow-strip coexistence.**
- [ ] **858. Cross-link discipline: badge honesty.**
- [ ] **859. Cross-link discipline: dedup window.**
- [ ] **860. Cross-link discipline: severity mapping audited.**
- [ ] **861. Cross-link discipline: copy tone warm/solemn as fit.**
- [ ] **862. Cross-link discipline: Help docs sentence.**
- [ ] **863. Cross-link discipline: Settings exposure.**
- [ ] **864. Cross-link discipline: smoke assert.**
- [ ] **865. Cross-link discipline: telemetry opt-in counter.**
- [ ] **866. Cross-link discipline: Streamer profile interaction.**
- [ ] **867. Cross-link discipline: Deck defaults.**
- [ ] **868. Cross-link discipline: platform-disabled honesty (web/android LLM).**
- [ ] **869. Cross-link discipline: refuse chatbot engagement loops.**
- [ ] **870. Cross-link discipline: local privacy sentence when relevant.**
- [ ] **871. Cross-link discipline: don't rebuild shipped mind pillars.**
- [ ] **872. Cross-link discipline: cross-link PLAYER_WISH if overlapping.**
- [ ] **873. Cross-link discipline: one commit per item when shipping.**
- [ ] **874. Cross-link discipline: verify with headless smoke.**
- [ ] **875. Cross-link discipline: mark checkbox in this doc.**
- [ ] **876. Cross-link discipline: prefer journal over toast.**
- [ ] **877. Cross-link discipline: prefer strip over toast when following.**
- [ ] **878. Cross-link discipline: prefer Care CTA over essay.**
- [ ] **879. Cross-link discipline: never mock death or nag consent.**
- [ ] **880. Cross-link discipline: never yank camera for a line.**

## Section — Edge cases & failure modes (881–920)

*Grounding: LLM errors, offline, decline consent.*

- [ ] **881. LLM errors → one quiet status; fallback to template. **(L)****
- [ ] **882. Edge/failure: rate-limit ambient without silencing critical.**
- [ ] **883. Edge/failure: respect quiet / Calm / battery saver.**
- [ ] **884. Edge/failure: deep-link to Care / Residents / Settings when actionable.**
- [ ] **885. Edge/failure: history vs toast policy explicit.**
- [ ] **886. Edge/failure: mobile + desktop parity.**
- [ ] **887. Edge/failure: gamepad dismiss/ack path.**
- [ ] **888. Edge/failure: reduced-motion path.**
- [ ] **889. Edge/failure: screen-reader label.**
- [ ] **890. Edge/failure: tr() strings.**
- [ ] **891. Edge/failure: save/load prefs.**
- [ ] **892. Edge/failure: no spam on tank switch.**
- [ ] **893. Edge/failure: no spam on focus thrash.**
- [ ] **894. Edge/failure: photo-mode hush.**
- [ ] **895. Edge/failure: aquascape hush for ambient.**
- [ ] **896. Edge/failure: typing-focus hush.**
- [ ] **897. Edge/failure: follow-strip coexistence.**
- [ ] **898. Edge/failure: badge honesty.**
- [ ] **899. Edge/failure: dedup window.**
- [ ] **900. Edge/failure: severity mapping audited.**
- [ ] **901. Edge/failure: copy tone warm/solemn as fit.**
- [ ] **902. Edge/failure: Help docs sentence.**
- [ ] **903. Edge/failure: Settings exposure.**
- [ ] **904. Edge/failure: smoke assert.**
- [ ] **905. Edge/failure: telemetry opt-in counter.**
- [ ] **906. Edge/failure: Streamer profile interaction.**
- [ ] **907. Edge/failure: Deck defaults.**
- [ ] **908. Edge/failure: platform-disabled honesty (web/android LLM).**
- [ ] **909. Edge/failure: refuse chatbot engagement loops.**
- [ ] **910. Edge/failure: local privacy sentence when relevant.**
- [ ] **911. Edge/failure: don't rebuild shipped mind pillars.**
- [ ] **912. Edge/failure: cross-link PLAYER_WISH if overlapping.**
- [ ] **913. Edge/failure: one commit per item when shipping.**
- [ ] **914. Edge/failure: verify with headless smoke.**
- [ ] **915. Edge/failure: mark checkbox in this doc.**
- [ ] **916. Edge/failure: prefer journal over toast.**
- [ ] **917. Edge/failure: prefer strip over toast when following.**
- [ ] **918. Edge/failure: prefer Care CTA over essay.**
- [ ] **919. Edge/failure: never mock death or nag consent.**
- [ ] **920. Edge/failure: never yank camera for a line.**

## Section — Long-run desk companion communications (921–960)

*Grounding: overnight, AFK, multi-hour.*

- [ ] **921. Overnight quiet hours; morning one line or critical. **(L)****
- [ ] **922. Desk long-run: rate-limit ambient without silencing critical.**
- [ ] **923. Desk long-run: respect quiet / Calm / battery saver.**
- [ ] **924. Desk long-run: deep-link to Care / Residents / Settings when actionable.**
- [ ] **925. Desk long-run: history vs toast policy explicit.**
- [ ] **926. Desk long-run: mobile + desktop parity.**
- [ ] **927. Desk long-run: gamepad dismiss/ack path.**
- [ ] **928. Desk long-run: reduced-motion path.**
- [ ] **929. Desk long-run: screen-reader label.**
- [ ] **930. Desk long-run: tr() strings.**
- [ ] **931. Desk long-run: save/load prefs.**
- [ ] **932. Desk long-run: no spam on tank switch.**
- [ ] **933. Desk long-run: no spam on focus thrash.**
- [ ] **934. Desk long-run: photo-mode hush.**
- [ ] **935. Desk long-run: aquascape hush for ambient.**
- [ ] **936. Desk long-run: typing-focus hush.**
- [ ] **937. Desk long-run: follow-strip coexistence.**
- [ ] **938. Desk long-run: badge honesty.**
- [ ] **939. Desk long-run: dedup window.**
- [ ] **940. Desk long-run: severity mapping audited.**
- [ ] **941. Desk long-run: copy tone warm/solemn as fit.**
- [ ] **942. Desk long-run: Help docs sentence.**
- [ ] **943. Desk long-run: Settings exposure.**
- [ ] **944. Desk long-run: smoke assert.**
- [ ] **945. Desk long-run: telemetry opt-in counter.**
- [ ] **946. Desk long-run: Streamer profile interaction.**
- [ ] **947. Desk long-run: Deck defaults.**
- [ ] **948. Desk long-run: platform-disabled honesty (web/android LLM).**
- [ ] **949. Desk long-run: refuse chatbot engagement loops.**
- [ ] **950. Desk long-run: local privacy sentence when relevant.**
- [ ] **951. Desk long-run: don't rebuild shipped mind pillars.**
- [ ] **952. Desk long-run: cross-link PLAYER_WISH if overlapping.**
- [ ] **953. Desk long-run: one commit per item when shipping.**
- [ ] **954. Desk long-run: verify with headless smoke.**
- [ ] **955. Desk long-run: mark checkbox in this doc.**
- [ ] **956. Desk long-run: prefer journal over toast.**
- [ ] **957. Desk long-run: prefer strip over toast when following.**
- [ ] **958. Desk long-run: prefer Care CTA over essay.**
- [ ] **959. Desk long-run: never mock death or nag consent.**
- [ ] **960. Desk long-run: never yank camera for a line.**

## Section — Ship the feeling: acceptance & coda items (961–1000)

*Grounding: playtest bars for a calm inbox.*

- [ ] **961. Acceptance: mom isn't overwhelmed in 10 minutes. **(L)****
- [ ] **962. Acceptance/coda: rate-limit ambient without silencing critical.**
- [ ] **963. Acceptance/coda: respect quiet / Calm / battery saver.**
- [ ] **964. Acceptance/coda: deep-link to Care / Residents / Settings when actionable.**
- [ ] **965. Acceptance/coda: history vs toast policy explicit.**
- [ ] **966. Acceptance/coda: mobile + desktop parity.**
- [ ] **967. Acceptance/coda: gamepad dismiss/ack path.**
- [ ] **968. Acceptance/coda: reduced-motion path.**
- [ ] **969. Acceptance/coda: screen-reader label.**
- [ ] **970. Acceptance/coda: tr() strings.**
- [ ] **971. Acceptance/coda: save/load prefs.**
- [ ] **972. Acceptance/coda: no spam on tank switch.**
- [ ] **973. Acceptance/coda: no spam on focus thrash.**
- [ ] **974. Acceptance/coda: photo-mode hush.**
- [ ] **975. Acceptance/coda: aquascape hush for ambient.**
- [ ] **976. Acceptance/coda: typing-focus hush.**
- [ ] **977. Acceptance/coda: follow-strip coexistence.**
- [ ] **978. Acceptance/coda: badge honesty.**
- [ ] **979. Acceptance/coda: dedup window.**
- [ ] **980. Acceptance/coda: severity mapping audited.**
- [ ] **981. Acceptance/coda: copy tone warm/solemn as fit.**
- [ ] **982. Acceptance/coda: Help docs sentence.**
- [ ] **983. Acceptance/coda: Settings exposure.**
- [ ] **984. Acceptance/coda: smoke assert.**
- [ ] **985. Acceptance/coda: telemetry opt-in counter.**
- [ ] **986. Acceptance/coda: Streamer profile interaction.**
- [ ] **987. Acceptance/coda: Deck defaults.**
- [ ] **988. Acceptance/coda: platform-disabled honesty (web/android LLM).**
- [ ] **989. Acceptance/coda: refuse chatbot engagement loops.**
- [ ] **990. Acceptance/coda: local privacy sentence when relevant.**
- [ ] **991. Acceptance/coda: don't rebuild shipped mind pillars.**
- [ ] **992. Acceptance/coda: cross-link PLAYER_WISH if overlapping.**
- [ ] **993. Acceptance/coda: one commit per item when shipping.**
- [ ] **994. Acceptance/coda: verify with headless smoke.**
- [ ] **995. Acceptance/coda: mark checkbox in this doc.**
- [ ] **996. Acceptance/coda: prefer journal over toast.**
- [ ] **997. Acceptance/coda: prefer strip over toast when following.**
- [ ] **998. Acceptance/coda: prefer Care CTA over essay.**
- [ ] **999. Acceptance/coda: never mock death or nag consent.**
- [ ] **1000. Acceptance/coda: never yank camera for a line.**

---

## Coda

The minds are deep. The inbox should be calm. Work the foundations shortlist,
verify with `smoke_comms_inbox.gd`, mark items done here, and cross-link
PLAYER_WISH when an item ships for both.
