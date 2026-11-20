# Status

Updated 2026-11-20. Five categories of truth (Revision 2.0 quality gates):

- **Studio-verified**: seen working in a Roblox Studio playtest.
- **Automated tests**: covered by `./scripts/check.sh` (StyLua, Selene,
  strict luau-lsp, Lune unit tests, Rojo build).
- **Implemented, not Studio-verified**: code exists and passes the gate,
  but nobody has watched it work yet.
- **Not implemented**: designed, no code.
- **Blocked**: cannot move until something outside the code changes.

**Success criterion (vertical slice):** a new player wakes in a cozy house,
interacts with Caramelo, talks to Maya by radio, chops wood with a visible
axe, visits Maya, returns before dark, secures the house, survives a
Watcher investigation and finishes the night in comfort. **Not met yet**:
the code for every beat exists, but the full day-1 run has not been played
in Studio.

## Chapter 37 progression (branch `feat/progression`, 2026-11-20)

Since the playtests below, the branch was rebased onto `main` (terrain,
Chaoscope, Chapter 38 dog AI), Caramelo's part was narrowed to Martha's
trail (`DogTracking`; the old dog-panel Find it and practice buttons are
gone), the weather station and Martha's cottage were made taller, and the
quest framework gained campaign objectives, evidence, alternatives and a
shared town. **None of that has been booted in Studio**; it passes the
gate (150 + 18 tests).

Studio-verified (two playtests of `feat/progression` builds db74813 and
earlier, before the rebase, 2026-11-20). Items, teleports and time skips
came from the Studio-only debug hook (`docs/TESTING.md`); every talk,
repair, cook, scarf, table, shop and dog command went through the real
prompts and panels:

- Server starts with the new sites and services and logs no error from
  them; world built in 6.3 to 8.7 s.
- Pinehaven Hardware, Ellen's Diner, the weather station, the storm-wrecked
  shed, the sensor mast, Martha's cottage and Maya's garden stand on the
  ground; Frank, Ellen, Martha and Dr. Hale stand at their posts with Talk
  (E), and the counters show Browse (R).
- All five missions start and complete:
  - Frank (played twice): collect, three repairs, talk. The shed visibly
    changes from leaning walls and loose boards to straight walls, a red
    roof, a door, a lantern and a toolbox. "+15 credits +10 reputation
    +2 Scrap metal".
  - Ellen: collect, cook at the stove (F), serve. "+10 credits +8
    reputation". The burner and ceiling lamp light at once, and at dusk her
    windows glow.
  - Martha (old tracking code): Talk starts it; the final Talk pays "+10
    credits +8 reputation". The steps in between completed as objectives
    (scarf, Biscuit located, brought home), but Biscuit was never on
    screen, and the scarf step completed without a deliberate F press (see
    below). Tracking has since been rewritten as `DogTracking`.
  - Maya: lunch, then the trellis quest. Two repairs turn the flattened
    bed into a framed trellis with green vines and flowers. Showing her
    pays "+3 reputation +2 Berries" plus her garden gift. Then she asks for
    supper: the stew is delivered by talking, and sitting at her table (F)
    completes "Supper at Maya's" with "This is nice. Just this." and a
    comfort rise.
  - Dr. Hale: needs Frank's mission first. Hike to the mast, inspect,
    collect (the scrap was in the pack from Frank), cups then wiring (the
    cups appear and spin, the beacon lights), report. "+15 credits +10
    reputation".
- Dialogue changes after missions: Ellen "Stove's warm. People keep coming
  in just to smell it."; Frank "Shed's holding up fine. Best roof in
  Pinehaven, don't tell anyone."
- The radio card names "DR. HALE".
- Ellen's counter lists stew, berries and a mushroom; buying a stew takes 10
  credits down to 6 and the toast confirms it.
- The old tracking started and waited for the player ("Caramelo waits for
  you, ears up, then looks ahead").
- Rejoin path: `StillnessDebug:Invoke("rejoin")` sent the live state (1,342
  bytes) through JSON into a fresh state. The summary before and after was
  identical: 46 credits, 45 reputation, six quests done, all three projects
  restored, the same seven flags.
- Day 2: the incident director posted "A fallen branch blocks a trail" in
  the journal. On day 3 Dr. Hale radioed the morning forecast ("Tonight
  feels restless. Curtains drawn, I'd say."), which is right for the
  scripted uneasy night 3.
- Life Journal: HOME (forecast, today's incident, Caramelo), TOWN (tier,
  credits, restoration with benefits, "Because of you", finished missions
  with what they opened), PEOPLE (Maya's three milestones done, trust per
  neighbour), MYSTERIES (the two optional research quests, observations).

Found in the playtests and fixed afterwards, not yet booted:

- Dr. Hale looked taller than the weather station (an 8-stud hut with its
  sign at head height in front of him). The station is now 10 studs to the
  eaves, 9 under the porch, with the sign on top of the awning; Martha's
  cottage got the same headroom.

- In the old terrain, Martha's porch and the old wood shed stood in a
  creek. Sites now search outward for a dry footprint.
- The station's status lamp glowed before the forecast worked; it now
  lights with the forecast.
- A repair prompt accepted a press before the repair step and spent what
  the collect step still needed. Repairs now wait for their step.
- The errand card overlapped Roblox's chat window; it now sits lower on
  the left.

Unexplained, seen once: the scarf step completed right after Martha's
quest started, without a deliberate F press. Not reproduced.

Automated tests (`tests/progression.spec.luau`, called from
`tests/logic.spec.luau`; 150 + 18 tests in all after the rebase):

- Every objective component, phase limits, target matching, progress text.
- Quest prerequisites, ordered objectives, consequences, follow-ups opening,
  expiry, restore from bad data.
- One-time payouts, capped small earnings across a rejoin, tiers, every shop
  rule, clamped restore.
- Restoration stages, finishing twice pays nothing, union of players.
- Incident eligibility, cooldowns, daily budget, weighted choice; a peaceful
  errand exists on a plain day.
- Martha's reward raises Tracking by one, once.
- Campaign framework: inspect, escort, track, communicate, activate,
  coordinate and survive objectives; evidence counted once per quest, also
  after a JSON save; evidence that moves nothing is not burned;
  alternatives complete a step, record the choice and set its flag, with
  partial progress surviving a save.
- SharedTown: only moves forward, merges two servers' saves without loss,
  readiness summary, JSON round trip, rejects bad data, town-scope projects
  advance shared buildings.
- Dialogue changes after a mission and with trust.
- Config integrity: every NPC, item, site, interaction, project, creature
  and weather named by a quest resolves; repair quests ask for exactly what
  the repairs cost; monster research is never required.
- All five missions played through the real logic with correct rewards;
  a JSON save and restore gives an identical journal, keeps mid-quest steps
  and refuses a second claim.

Implemented, not Studio-verified:

- A real DataStore rejoin. An unpublished local place has no DataStore, so
  only the in-game snapshot, JSON and restore path above ran. The section
  is written in the same `SetAsync` as the inventory.
- `DogTracking`: the scarf starting the trail, paw prints and scent,
  waiting, stuck recovery, hiding taking over, Biscuit found and following
  home and asleep on the porch, her lantern.
- `SharedTownService` saving and merging across servers (no DataStore in a
  local place), and any town-scope project (none exists in the slice).
- Maya's night radio line, the optional rain log and Watcher notes, and
  clearing an incident (the branch was posted but not cleared).
- Multiplayer: the world shows the furthest stage held by the players
  present. Only one player was tested.
- Walking the whole route on foot at normal speed. Teleports were used.

## Studio-verified

- World generation on server start (6.7 s, 2 km map), terrain, lake, snowy
  mountain backdrop, asset trees (12 ponderosa, 6 birch, 1 cedar, 1 oak, snow
  pines), neighbor houses, radio tower. This was the pre-rebuild world: the
  valley terrain, forest and haze that replaced it have not been seen in
  Studio yet (see below).
- The old main menu over a live camera shot of the cabin, Play, spawn.
- Cabin exterior: porch, posts, porch light, flower boxes, firewood, chimney.
- Objective tracker advancing through the old opening (find shelter,
  collect wood, repair door, light fire, dog inside, survive the night).
- Old HUD comfort and exposure bars.
- Caramelo: caramel mesh dog follows and runs with the walk animation; the
  old pet prompt showed a message.
- Chop prompt on marked trees, wood gathering (two trees gave 12 wood), door
  repair and opening, fireplace flames and light.
- Dog panel (G). Pack on P (Roblox reserves Tab and I).
- 80/80 licensed audio ids load; 13 vetted models import with zero scripts;
  "The Mechanism" (85164647841567) loads.

Seen in Studio on 2026-11-20 (builds head5 and head6):

- The new menu, then waking in the cabin: the radio crackles, the objective
  card reads "Answer the radio", the morning call plays on its own after
  45 s and the objective moves to firewood. New HUD time pill, objective
  card and vitals panel.
- Imported creature models: Watcher (R15, about 11 studs), Dweller (deer
  skull), Crawler (grey beast) and the Old One (74-stud black Watcher). The
  Watcher and Dweller play Roblox's walk animation when moving.
- The Watcher at night: a near-black silhouette with two pale eye points;
  its head turns toward the camera. Its fear energy fell from 0.8 to 0.35
  with nobody afraid nearby (starving works). It stood near the north wall
  for about 30 s in searching states, then moved on; whether that was the
  gaze freeze is not confirmed (a finished stare should end in a dash or a
  retreat, and the log showed neither).
- Caramelo's mood (build head7, night 2): asleep on his bed, his agitation
  rose as a Watcher approached; head up (level 1) at about 40 studs,
  suspicious (level 2, the growl level) at about 16 studs, back to sleep
  when the Watcher lost interest. A Watcher outside the secure cabin never
  pushed him to barking. With the coat on, the "Hide together" prompt
  appears on him.

## Automated tests

- 110 Lune unit tests over the pure logic: TimeCycle, Perception,
  CreatureBrain, Shelter, Noise, CollectiveMind, Inventory, NightClass
  (including the 65/25/9/1 night weights and the scripted first nights),
  Comfort, LightVisibility, MusicState (including storm night), Journal,
  StoryProgress, Mystery, Breath, AudioConfig, FearEcology (fear bounds,
  diminishing returns, starving, temperament limits), DogMind (senses,
  hysteresis, bark odds, step-by-step calming, familiarity), RadioConfig
  (every condition and story fact exists), ChaosField and Dissonance.
- Chapter 36 rules pinned by tests: peaceful nights drift; calm rain alone
  stays at or below DRIFT; a storm alone stays below CONVERGENCE and only
  adds uncertainty; a field of calm creatures reads STABLE; anomalies
  happen with no creatures; REGIONAL barely moves for a local anomaly; an
  Absence reads exactly zero (UNKNOWN); the Echo never keeps the original
  timing; PASSIVE with real noise samples is damped, rarely flaps and still
  shows the climb; the scan emitter warns before it pulses and cools down; every
  director event is nonviolent and has a cooldown; and a pure-logic replay
  of the 36.12 rainy night (onset climb, local disturbance, regional calm,
  the phrase repeating and coming through whole, the needle settling).
- 18 terrain specs over the valley height function (Heightfield): flat
  building pads at the gameplay heights, the lake (depth, water only in the
  lake, irregular shore), every building and landmark on dry land, zones,
  creature spawn and patrol points (Watcher and opening points on land,
  fewer random points in the lake than before), the cabin window's view of
  Maya's house, the hill house and the Old One's spots, dry and walkable
  paths (the path to Maya under 0.35 grade), and the valley shape (uneven
  horizon under 21°, no snow or ramp inside the play area, no visible
  terrain edge from the lowlands). The pre-rebuild terrain runs as a
  control and fails the shape checks.
- Every server service, client controller and world builder is type-checked
  in strict mode and built by Rojo, but **no service has a behavioural
  test**. That includes MayaService, OpeningService, ToolService, the HUD
  and the menu.

## Implemented, not Studio-verified

Chapter 35, the unnatural creatures (ca7b018, 8287b7e):

- The Watcher's dash after a long stare (sideways to a spot by a tree,
  then stillness) and its displacement while nobody can see it (never into
  a shelter, never within 20 studs of a player). Not yet seen in a test.
- Slow stalking and long observation pauses facing the lit house; burst
  gait (rush, dead stop) for the Crawler and Dweller; the Crawler's facing
  fix and gait bob; the Dweller's red eye sockets and darker body.
- Creature noises tied to behaviour (distant calls, close breathing, a tap
  or scratch at a wall that repeats a few seconds later).
- Temperaments and the fear ecology raising boldness (characters' fear from
  fictional signals, creatures feeding within 90 studs).
- The window encounter (another window, tapping), false departures, and
  Maya darkening her house when something is near the cabin (e45a3db).
- Night stories for Peaceful and Uneasy nights (933d919) and Caramelo's
  frightened body language (f79fb37).
- Fixes after a code review: a tap, scratch or dash now startles Caramelo,
  so a Watcher at the glass can make an untrained dog bark (spec added); a
  defensive bark resets only the nearest Crawler; a window hop or a return
  walks all the way before the "lost sight" clock starts; the night-1 look
  step checks observedBy; passing Watchers avoid the lake.
- Studio test aids: DebugSpawn, DebugEnergy, DebugTemperament and
  DebugStory attributes on ReplicatedStorage, and a LastMove attribute
  (dash, displace, hop, return) on each creature.
- The radio drawing every line from what is happening (569ea4e).

Chapter 38, Caramelo (ac163c4, 638d6d1):

- Not yet seen: the growl and whimper sounds playing, barking as noise
  creatures react to, the new bark sound (9113956187), calming step by step
  (T while he is agitated), actually hiding together (crouch with C, then
  E; automation could not hold a crouch), seeking you when frightened,
  learning and training. Training lives only for the session; it is not
  saved yet.

Valley rebuild (merged from `feat/terrain-rebuild`, 2026-11-20; details in
[docs/WORLD.md](docs/WORLD.md)):

- The ring of jagged snow walls is gone. The terrain is a 3.2 km
  Pacific-Northwest valley from one deterministic height function:
  lowlands, forested asymmetric ridges with passes, far snowy ranges with
  low gaps to the south, a lone volcano to the south-east. The playable
  square is unchanged.
- Irregular lake with coves, an islet, beaches, mud and pebble shores;
  muted, less reflective water.
- New paths: around the lake to Maya's porch, up over Hemlock Pass, out
  over the west pass, and the Valley Road to the reserved Pinehaven site.
- Clustered, biome-aware forest with ferns, bushes, logs, rocks and
  stumps, clear sightlines from the cabin, and a shadowless scenery fringe
  outside the play area.
- Cooler atmosphere haze so the far peaks read as distant.
- Every landmark and gameplay coordinate stays where it was.
- Not measured yet: world build time, tree count and frame rate in
  Studio. A Lune simulation of the grove rules gives about 2,100 tree
  candidates before spacing and exclusions; the server prints the real
  count (`[Forest]`) and the terrain timing (`[Terrain]`).

Revision 2.0 (commits d248a33 and faf03a6, 2026-11-20):

- Complete-cabin start: door hung, fire lit, windows latched, new north
  bedroom window facing the lake, spawn by the bed, coat available.
- Maya in her own house across the lake: R15 NPC (free catalog hair
  7193448258, body colors), spots by phase (kitchen, window, upstairs),
  window lights at dusk, Talk prompt with a lunch scene and a stew gift,
  radio lines. Idle animation uses Roblox's default R15 idle id.
- Day-1 opening (OpeningService): morning radio call with a 45 s fallback,
  firewood, fire, visit Maya, sunset warning, home before dark, guided first
  Watcher (look, coat, go dark, stay still, hold breath), calm rain and her
  lamp afterwards. Hunts are broken off during the lesson; every step has a
  fallback; no sleeping on night 1 until the Watcher is gone.
- Night weights Peaceful 65 / Uneasy 25 / Bad 9 / Black 1; nights 1-2
  Peaceful, 3 Uneasy; no Black Night before day 14.
- Rebuilt HUD: top time pill, objective card, vitals panel with status
  chips, toasts, radio transcript card, fading key hints.
- Rebuilt menu with working music, ambience and cue volume sliders.
- Axe tool (key 1, built-in slash animation), chips and shake per hit, the
  last hit fells the tree away from the player, stump, regrowth. Uses the
  imported Creator Store axe (87307912628259); its look in hand is not yet
  checked.
- Visible petting: dog stops, faces the player and sits; the player bends
  and strokes it (IKControl).

Chapter 36, the Dissonance (branch `feat/dissonance`, 2026-11-20). Passes
the gate; **not run in Studio**:

- H-17 Chaoscope on the cabin table: dial, trace and lamps drawn on the
  client from scope attributes, R to switch on/off, F to look closely
  (POWER, mode, sensitivity). On by default in PASSIVE. The needle is
  damped per mode so it drifts rather than jumps.
- ChaoticEnergyService: 17x17 sector field (covers the ±1600 valley) ticking at 1 Hz on real time;
  rain, night, collective level and creature `FearEnergy` / `Hunger`
  attributes as inputs (missing reads 0); one anomaly at a time, none on
  day 1; Studio seeding through `DissonanceForce`.
- DissonanceEventDirector: transmissions on the radio card ("Unknown: ..."),
  radio static, window rattle, one flicker, the hush, Maya's window (skipped
  when MayaService keeps her dark), a startle for Caramelo through his mood
  system (`StartleStrength` / `StartledAt`), the Echo, the needle moving
  while off; journal entries through `ObservationService.note`. Not done:
  Caramelo facing the doorway (the startle hook carries no direction).
  Muted on day 1 and while `TimeScale` is above 1.
- Scan signature with charge, warning, pulse and cooldown; published as
  workspace `ChaosSignal`, `ChaosSignalPosition`, `ChaosSignalAt` for the
  creature code to read later (nothing reads it yet).
- Audio: the scope's clicks and static reuse verified cues (light switch,
  radio static). The hum and the faint tone are silent until an id is
  verified.

Older systems:

- Gathering, inventory, crafting, building placement.
- Doors, windows (curtains, latches, quiet close vs slam, shutters, repair),
  lights, fuse box, fireplace and cooking, bed sleep, radios, wardrobe.
- Day/night lighting keyframes, weather (continuous rain, fog, gusts that
  force unlatched windows, thunder and lightning).
- Creatures: Watcher, Dweller, Crawler with perception, memory, search,
  window stare, shelter respect; collective mind and group breaching on bad
  nights; Old One silhouette.
- Night classification and bad-night warnings.
- Hold breath, coat, comfort, exposure.
- Observation mode and journal; the night mystery now at the hill house.
- Adaptive music and ambience with real audio.
- Wildlife (deer, rabbits, crows) that leave at dusk and flee creatures.

## Not implemented

- Living neighborhood: neighbors with daily routines (Chapter 37 NPCs stand
  at their posts; only Maya moves).
- Food beyond one stew recipe; hunger; dog feeding.
- Forecasting beyond Dr. Hale's morning radio line (barometer, weather radio).
- Bad Night verification pass and blackout behaviour.
- Observer profession (Human Watchers), optional path.
- Maya visiting or staying over; the Maya rescue system (Chapter 32).
- Pinehaven town with interiors and loot (partial work parked on branch
  `wip/helpers-partial`, not merged). The valley now reserves a flat,
  tree-free site for it at (360, 440) on the Valley Road.
- Highland phase: the highland lookout (knoll reserved at (-470, -560)),
  the trail up the Old One's Crest, deep-forest content.
- Skippable opening cinematic.
- Richer, layered soundtrack (the owner wants more than one music-box voice).
- Window wetness, indoor puddles, rain streaks on glass.
- StreamingEnabled plan for a 4096-stud map; performance measurements.

## Blocked

- **Every Studio check above** needs the Mac unlocked: computer use cannot
  drive Studio on a locked screen.
- **Pushing to GitHub** (`melocalex/the_stillness`): blocked for the
  automated session; the owner pushes.
- **Studio check of the valley rebuild**: computer-use access to Roblox
  Studio was declined on 2026-11-20, so the new terrain has no Studio
  screenshots or build time yet. The camera rig is
  `tools/studio/shot-rig/build.sh` (base commit for "before": ba2d2a0);
  the checklist is in docs/TESTING.md (Environment, Before/after shots).
- **Dog animations in a published game**: the account owner must publish
  the Dog KeyframeSequences as Animation assets.
- **Publishing**: File > Publish to Roblox As, from the owner's account.
- **Chapter 36 in Studio**: the session that built it was not given access
  to Studio, so the slice has not been played and the hum and tone
  candidates (ProSoundEffects 9112889082, 9112889525, 9125784811,
  9120972942; relay click 9118145455) are unverified. Run
  `tools/studio/verify_dissonance_audio.luau` and the checklist in
  `docs/TESTING.md`.

## Known issues

- The deer (5114925772) is one rigid mesh with no skeleton: its legs never
  move; it only bobs while walking (3d7ce84). Rigged, script-free
  candidates to vet in Studio: "Lobo's Rigged Deers" (12835993547, 7,320
  triangles) and "deer rigged?" (3573829012, 28,581 triangles). The
  rabbit already has bones. Ground placement and house window glass were
  fixed in the same commit; neither has been seen in Studio yet.
- Bookshelf asset faces the wrong way; rocking chair a bit small.
- The stew message in InteractionService still says "(Tab)"; the pack is
  on P.
- No licensed glass-shatter or bark sound verified in Studio yet.
- The daylight brightness tweak was lost to `wip/helpers-partial`.
- Random creature points (crawlers, patrols, Watchers rolled at 100 to 120
  studs) can still land in the lake, as before the rebuild but fewer.
- The playable boundary is still a square of invisible walls; it now
  stands in low ground behind the ridges.

## Studio checklist for the opening

1. New server: spawn by the bed; radio crackles; answering plays Maya's
   three lines; objective moves to firewood.
2. Key 1 shows the axe; chopping a ribboned tree swings, chips, fells it.
3. T near Caramelo: both characters animate.
4. Walk to the lake house: Maya stands in the kitchen; Talk plays lunch and
   gives a stew.
5. Dusk: her windows light; the warning plays; reaching the cabin completes
   "Head home".
6. Night: the Watcher appears north; each coaching line advances with the
   real action; it never captures; afterwards rain, her lamp, her line.
7. Sleep works only after it has gone; wake at dawn; "Survive your first
   night" completes.
