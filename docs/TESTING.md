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
- A Rojo build of the place file.

Gameplay inside Roblox cannot run under Lune; it is checked in Studio.

## Studio checklist

Mark each item only after seeing it in a Studio playtest.

### Environment
- [ ] Character spawns at the forest trail, not inside terrain
- [ ] Cabin exists, doors and windows render, porch light is on
- [ ] Terrain has collision everywhere you can walk; boundary walls stop you
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
  dial, trace and POWER lamp show; a faint hum
- [ ] R switches it off and on (click); E frames it and shows POWER, mode
  and sensitivity; Esc leaves
- [ ] Set ReplicatedStorage `DissonanceForce` to `Arrival` (Server view):
  the needle climbs over the next half minute; LOCAL reads about 40 with a
  jagged trace; REGIONAL stays mostly normal
- [ ] Caramelo lifts his head on his bed at least once during it
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

## Performance

Report measured numbers only (Studio **View > Stats / MicroProfiler**).
Measured so far: server world generation 6.7 s for the 2 km map
(Studio test, 2026-11-20).
