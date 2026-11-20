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
  breath, and the config files they read.
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

## Performance

Report measured numbers only (Studio **View > Stats / MicroProfiler**).
Measured so far: server world generation 6.7 s for the old 2 km map
(Studio test, 2026-11-20). The rebuilt 3.2 km valley has not been timed in
Studio yet.
