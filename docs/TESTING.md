# Testing

## Automated

`./scripts/check.sh` runs:

- StyLua format check and Selene lint over `src` and `tests`.
- luau-lsp strict analysis of every script against the Roblox API
  definitions (catches misspelled properties, wrong enum items, bad types).
- Lune unit tests in `tests/logic.spec.luau` for the pure modules in
  `src/shared/Logic`: time cycle, perception, creature brain, shelter rules,
  noise, collective mind, inventory, night classification, comfort,
  light visibility, music state, journal, story progress, mystery,
  breath, fear ecology, the chaotic energy field and the Dissonance rules,
  and the config files they read.
- Terrain specs in `tests/terrain.spec.luau` for the valley height
  function: building pads, the lake, creature spawn points, sightlines,
  the Old One's spots, dry and walkable paths, and the valley shape, with
  the pre-rebuild terrain as a control (details in [WORLD.md](WORLD.md#tests)).
- A Rojo build of the place file.

Gameplay inside Roblox cannot run under Lune; it is checked in Studio.

## Studio checklist

Mark each item only after seeing it in a Studio playtest.

### Environment
- [ ] Character spawns at the forest trail, not inside terrain
- [ ] Cabin exists, doors and windows render, porch light is on
- [ ] Terrain has collision everywhere you can walk; boundary walls stop you
- [ ] No wall of snow or ice around the valley; snowy peaks only far away, hazy
- [ ] From the cabin's north window: the lake and Maya's house, no tree in the way
- [ ] The lakeside path leads to Maya's porch; Caramelo follows the whole way
- [ ] Lake shore shows beach, mud and pebble stretches; water is not flat blue
- [ ] From Radio Hill and the hill house: ridges, gaps, no edge of the terrain
- [ ] `[Terrain]`, `[Forest]` and `[World] built in` lines in the server output
- [ ] Gather prompt appears on marked trees, rocks and bushes; yields items
- [ ] Neighbor houses, lake house, radio tower and town are visible from afar

### Day and night
- [ ] Clock advances; lighting changes smoothly through dusk and dawn
- [ ] Weather changes; rain intensity eases in and out; most rain is calm
- [ ] Lights and storefronts glow at night and read from a distance

### Creatures
- [ ] Watcher appears at night, investigates noise, searches last known position
- [ ] Watcher stops at a secure cabin and stares through an uncovered window
- [ ] Closing curtains breaks its line of sight; it eventually leaves
- [ ] Dweller patrols the abandoned house and reacts strongly to sound
- [ ] Bad night: crawlers converge, attack the weakest entry point, breach, search

### Dog (Caramelo)
- [ ] Follows at a comfortable distance; Stay, Come, Sit, Sleep, Home work
- [ ] Pet shows a heart, a message and the happy pose
- [ ] Growls at nearby creatures; calm command stops barking
- [ ] Never permanently stuck (teleports back when lost)

### Building and shelter
- [ ] Repair costs are enforced; secure shelter status updates on the HUD
- [ ] Invalid build placement is rejected; no resource duplication

### Story
- [ ] Objectives advance in order and can be completed late without soft-locks

### The Dissonance (Chapter 36)
Setup: `rojo build -o <scratch>/dissonance.rbxlx`, open it, Play. In Server
view set ReplicatedStorage `TimeScale` to 200 until day 3 Dusk (scripted
rain), then back to 1. Walk to the cabin table, Caramelo on his bed.
- [ ] The H-17 sits on the table beside the radio, facing the stools; the
  dial, trace and POWER lamp show; the needle drifts, it does not jump
- [ ] R switches it off and on (click); F frames it and shows POWER, mode
  and sensitivity; Esc leaves; the radio and lamp prompts still work on E
- [ ] Set ReplicatedStorage `DissonanceForce` to `Arrival` (Server view):
  the needle climbs over the next half minute; LOCAL reads about 40 with a
  jagged trace; REGIONAL stays mostly normal
- [ ] Caramelo's `DogMood` turns ALERT (head up) at least once during it,
  maybe SUSPICIOUS with a low growl; he never barks from it alone and
  settles afterwards
- [ ] "Unknown: ..." appears on the radio card with letters missing, then
  whole after raising sensitivity in LOCAL; the EMIT lamp warms, blinks,
  flashes; workspace `ChaosSignal` goes above 0 and back to 0
- [ ] At most one short flicker of the cabin lights
- [ ] Switching the scope off after the peak sometimes gives a click and a
  needle swing while it is off, then it settles
- [ ] Rain, fire and music fade out for a few seconds and come back; the dog
  settles
- [ ] No creature appears because of any of this; no damage, no breach
- [ ] `Echo` and `Absence` seeds: the Echo plays recent house sounds from the
  scope, out of time; the Absence drops the needle to 0 (FAULT lamp) and
  then the house goes quiet
- [ ] `tools/studio/verify_dissonance_audio.luau` prints loaded=true for the
  candidates before any is added to `AudioConfig.Chaoscope`

### Before/after shots

`tools/studio/shot-rig/build.sh <commit> <out.rbxlx>` builds any commit
with a screenshot rig added. The rig is a tool and never ships in the
game. In the built place:

- **Clock.** The server fast-forwards to 11:00 and freezes the clock.
- **Cameras.** After you click Play in the menu, the client hides the
  HUD and cycles five cameras, 14 s each. The cameras are: the cabin's
  north yard toward Maya's house, the lake shore, Radio Hill toward the
  north, the porch toward the south-east and a high aerial view.
- **Output.** Each camera prints `[Shot] <name>` to the output.

Build two commits, open each in Studio and screenshot the same camera.

### Chapter 37: progression

The Studio command bar cannot reach live game modules (its `require()`
returns fresh copies). In Studio only, the server creates
`ServerStorage.StillnessDebug`; use it from the command bar in the Server
view (paste from the clipboard, then click Run):

```lua
local D = game.ServerStorage.StillnessDebug
print(D:Invoke("give", "Wood", 8))
print(D:Invoke("goto", "npc:frank"))   -- npc:, site:, project:, interact:, missing:
print(D:Invoke("state"))               -- quests, credits, projects, flags
print(D:Invoke("rejoin"))              -- save data through JSON into a fresh state
print(D:Invoke("incident", "fallen_branch"))
print(D:Invoke("phase", "Dusk"))
```

Keys: E talks, F uses things (stove, scarf, table, repairs, the mast),
R opens a counter, J the Life Journal.

Prompts only trigger while they are on screen. After a `goto`, turn the
camera (arrow keys) until the prompt shows.

Items marked [x] were seen before the rebase onto main (build db74813);
everything since (the rebase, the DogTracking rewrite, the taller station,
the framework additions) has only passed the gate.

- [x] Frank: talk, collect, three repairs change the shed, talk pays out
- [x] Ellen: cook at the stove (F), serve; the windows light at dusk; her counter sells
- [x] Martha (old build): talk starts it, the final talk pays out
- [ ] Martha: F at the scarf with Caramelo close starts the trail; paw prints and scent show; he waits when ahead; Biscuit found near the old wood shed follows home and sleeps on the porch; Tracking 1/3 in the journal
- [ ] Dr. Hale stands clearly under the station's porch and sign; Martha under hers
- [x] Maya: trellis stages, show her, bring a stew, supper at her table before night
- [x] Dr. Hale: hike, inspect, cups and wiring, the cups spin, forecast on the next morning's radio
- [x] `rejoin` keeps quests, credits, projects and flags
- [ ] Sites sit on dry ground after the water fix (look for "[Town] ... moved off water")
- [ ] An incident can be cleared and pays a small, capped amount
- [x] Life Journal HOME, TOWN, PEOPLE and MYSTERIES show real progress

## Performance

Report measured numbers only (Studio **View > Stats / MicroProfiler**).
Measured so far: server world generation 6.7 s for the old 2 km map
(Studio test, 2026-11-20). The rebuilt 3.2 km valley has not been timed in
Studio yet.
