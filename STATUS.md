# Status

Updated 2026-11-20. Four columns of truth:

- **Implemented**: code exists.
- **Checked**: passes `./scripts/check.sh` (strict types, lint, unit tests, build).
- **Studio-tested**: seen working in a Roblox Studio playtest.
- **Open**: not done, partial, or known issues.

## Studio-tested

- World generation on server start (6.7 s, 2 km map), terrain, lake, snowy
  mountain backdrop, asset trees (12 ponderosa, 6 birch, 1 cedar, 1 oak, snow
  pines), neighbor houses, radio tower.
- Main menu over a live camera shot of the cabin, Play button, spawn on the
  forest trail.
- Cabin exterior: porch, posts, porch light, flower boxes, firewood, chimney.
- Objective tracker: "Find shelter" completes when you reach the cabin and
  advances to "Collect wood".
- HUD comfort and exposure bars.
- Caramelo: caramel mesh dog follows and runs with the walk animation;
  T pets him (message shown; no petting animation yet).
- Core loop: orange-ribbon trees show "Chop" (hold E), two trees gave 12
  wood, "Collect wood" completed; door repair (5 wood) completed; door opens;
  fireplace lights with flames and warm light; "Bring your dog inside"
  completed; objective reached "Survive the first night".
- Dog panel (G) opens. Pack moved to P (Roblox reserves Tab and I).
- 80/80 licensed audio ids load in Studio; 13 vetted models import with zero
  scripts; "The Mechanism" uploaded (85164647841567) and loads.

## Implemented and checked, not yet Studio-tested

- Gathering, inventory, crafting, building placement.
- Door repair/reinforce, windows (curtains, latches, quiet close vs slam,
  shutters, repair), lights, fuse box, fireplace and cooking, bed sleep,
  radios, wardrobe coat.
- Day/night lighting keyframes, weather (continuous rain, fog, gusts that can
  force unlatched windows, thunder and lightning flashes).
- Creatures: Watcher, Dweller, Crawler with perception, memory, search,
  window stare, shelter respect; collective mind and group breaching on bad
  nights; Old One silhouette.
- Night classification and bad-night warnings.
- Hold breath, coat, comfort, exposure.
- Observation mode and journal; lake-house routines.
- Adaptive music and ambience with real audio.
- Wildlife (deer, rabbits, crows) that leave at dusk and flee creatures.
- Caramelo: caramel-tinted rigged mesh dog, walk/idle sequences (Studio) or
  procedural legs, heart and message when petted.

## Implemented 2026-11-20, waiting for a Studio check

- Axe tool (StarterPack, key 1): built-in slash animation; trees need the
  axe; chips and shake per hit; the last hit fells the tree away from the
  player, then a stump; regrows. Uses a procedural axe until the Creator
  Store axe (87307912628259, 0 scripts) is imported.
- Petting: dog stops, faces the player and sits wagging; the player turns,
  bends and strokes the dog (IKControl).

## In progress

- Pinehaven town with grocery, hardware, pharmacy and vet interiors,
  persistent loot, town lights and bad-night blackout (Chapter 31).
- Narrative prologue and first seven days; Maya as a routine-driven NPC
  with radio dialogue and a storm emergency (Chapters 32 and 33).

## Open

- Petting animation for Caramelo.
- Richer soundtrack: "The Mechanism" is a single-voice music box; the owner
  wants more complex, layered music.
- Toast messages overlap prompts at the bottom of the screen.
- Bookshelf asset faces the wrong way; rocking chair a bit small.

- Full Studio playthrough of the three-night loop, creatures and bad night.
- Dog walk animation in a published game needs the KeyframeSequences
  uploaded as Animation assets by the account owner.
- No licensed glass-shatter, dog growl or bark sound yet (cues are silent or
  use a stand-in).
- Watcher unease motif (APM "Music Box Of Death", 1837805876) not yet
  verified in Studio or added to AudioConfig.
- StreamingEnabled is off; needs a plan before the map grows to 4096 studs.
- Window wetness, indoor puddles, rain streaks on glass.
- Performance not yet measured beyond world generation time.

## Manual steps for you

- Sign in to Roblox Studio (done).
- To publish: File > Publish to Roblox As (your account).
- To keep dog animations in a published game: open the Dog model's
  KeyframeSequences in the Animation Editor and publish them to your account.
