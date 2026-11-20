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

## Automated tests

- 64 Lune unit tests over the pure logic: TimeCycle, Perception,
  CreatureBrain, Shelter, Noise, CollectiveMind, Inventory, NightClass
  (including the 65/25/9/1 night weights and the scripted first nights),
  Comfort, LightVisibility, MusicState (including storm night), Journal,
  StoryProgress, Mystery, Breath, AudioConfig.
- 18 terrain specs over the valley height function (Heightfield): flat
  building pads at the gameplay heights, the lake (depth, water only in the
  lake, irregular shore), every building and landmark on dry land, zones,
  creature spawn and patrol points (Watcher and opening points on land,
  fewer random points in the lake than before), the cabin window's view of
  Maya's house, the hill house and the Old One's spots, dry and walkable
  paths (the path to Maya under 0.35 grade), and the valley shape (uneven
  horizon under 21°, no snow or ramp inside the play area, no visible
  terrain edge from the lowlands). The pre-rebuild terrain runs as a
  control and fails the shape checks. 82 specs in all.
- Every server service, client controller and world builder is type-checked
  in strict mode and built by Rojo, but **no service has a behavioural
  test**. That includes MayaService, OpeningService, ToolService, the HUD
  and the menu.

## Implemented, not Studio-verified

Valley rebuild (branch `feat/terrain-rebuild`, 2026-11-20; details in
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
  last hit fells the tree away from the player, stump, regrowth. Uses a
  procedural axe until the Creator Store axe is imported.
- Visible petting: dog stops, faces the player and sits; the player bends
  and strokes it (IKControl).

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

- Living neighborhood: named neighbors with routines.
- Food beyond one stew recipe; hunger; dog feeding.
- Forecasting (barometer, weather radio, station).
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
- **Studio check of the valley rebuild**: computer-use access to Roblox
  Studio was declined on 2026-11-20, so the new terrain has no Studio
  screenshots or build time yet. The camera rig is
  `tools/studio/shot-rig/build.sh` (base commit for "before": ba2d2a0);
  the checklist is in docs/TESTING.md (Environment, Before/after shots).
- **Creator Store axe** (87307912628259, 0 scripts): import needs Studio.
- **Dog animations in a published game**: the account owner must publish
  the Dog KeyframeSequences as Animation assets.
- **Publishing**: File > Publish to Roblox As, from the owner's account.

## Known issues

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
