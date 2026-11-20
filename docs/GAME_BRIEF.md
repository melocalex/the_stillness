# THE STILLNESS — Full Game Brief for Design Review

> **How to use this document.** Paste it into another AI and ask it to act as
> a senior game director and Roblox technical lead. It should critique,
> simplify and improve the design, flag contradictions and scope risks,
> and propose a prioritized roadmap. The requested output format is at the
> end ("What we want from the reviewer").

---

## 1. One-line pitch

A cozy survival horror game on Roblox. You live in a warm wooden house in
Pinehaven, a half-abandoned mountain town, with your girlfriend Maya and your
caramel street dog Caramelo. By day you gather, cook, explore and help
neighbors. At night something intelligent walks the forest, and you learn to
switch off the lights, close the curtains, wear the old coat, hold your
breath, and wait for dawn.

**The horror exists to make the comfort meaningful.** The target feeling:

> "I am cozy. I am safe. I am home. Something terrible is outside, but here I
> am protected."

It is **not** a chase game, a shooter or an obby. Most nights are peaceful.
The best moments are quiet: rain on the roof, the fire low, the dog asleep,
and a tall figure standing at the edge of the trees.

## 2. Pillars

1. **Comfort first, horror second.** The player starts with a life worth
   protecting: a finished home, Maya, the dog, food, neighbors.
2. **Predictable safety.** A properly secured home is safe on ordinary nights.
   Rules are learnable; nothing kills you unfairly inside a secure house.
3. **Intelligent but imperfect creatures.** They see, hear and sense; they
   remember a last known position, never your true one; they share
   information as a group; they make mistakes.
4. **Observation is gameplay.** Windows, binoculars, a journal, distant
   houses, neighbors' lights, storms. Watching the world is as rewarding as
   exploring it.
5. **Silence and stillness are valid strategies.** Darkness, quiet, the coat
   and holding your breath can beat a search without combat.
6. **A living town.** Named neighbors with routines, shops, a diner, a
   weather station, and a small group of people who chase monsters in storms.

## 3. Setting and lore

**Pinehaven**: an isolated mountain town (once about 1,800 people), founded as
a logging settlement. Lakes, pine forest, snowy peaks, a church tower, a
textile mill. Every winter it held the Festival of Lights: a lit window meant
someone was home.

Seventeen years ago a tall figure in an old coat stood in a family's yard for
six hours without moving. Its footprints started in the middle of the yard and
went nowhere. Reports grew: footsteps, windows found open after storms,
figures in abandoned houses. Then the first **Bad Night**: at 9:17 PM the
power died and dozens of figures walked the streets. A police officer's last
message: *"They're not coming after us individually. They're looking for the
houses that are still awake."*

The town learned three rules:

1. Creatures are drawn to **light, noise and movement**.
2. They **communicate without sound** (a collective awareness).
3. Old **coats** from the local textile mill interfere with their ability to
   find people.

Storms made everything worse: windows blew open, neighborhoods lost power,
creatures learned to enter damaged homes. A radio transmission repeated
nightly at 11:13 PM: *"Do not answer the knocking. Do not turn on the lights.
If you hear someone breathing beside you, do not breathe back."* Then it
stopped. Some residents stayed.

**Long mystery (kept unresolved for a long time):** the coats were research
work garments from experiments with materials found under the mountain; the
creatures share awareness; the player's grandfather knew how to interrupt it.
First twist (after Day 7): the coat goes missing and is found on a tree facing
the bedroom window with a note: *"It isn't the coat that hides you. It's what
they think you are when you wear it."*

## 4. Characters

| Character | Role |
| --- | --- |
| **The player** | Lives in Pinehaven. Not a soldier or investigator. |
| **Maya** | Girlfriend. Lives with the player at the start; also keeps her own house across the lake (later missions, emergencies, rescues). Independent, capable, sometimes rescues the player. Age-appropriate, platform-safe relationship. |
| **Caramelo** | The player's caramel street dog (Brazilian "vira-lata caramelo" style). Companion, early-warning system, never dies. |
| **Frank Miller** | Hardware store owner: axes, materials, latches, storm shutters. Knows Bad Nights. |
| **Ellen Brooks** | Diner owner: meals, ingredients, rumors. Social hub. |
| **Dr. Hale** | Weather researcher at a small station; links storms to creature activity; forecasting equipment. |
| **Noah Reed** | Professional monster observer ("Human Watcher"). Coat, binoculars, camera, radio, notebook. Introduces storm chasing. |
| **Martha** | Elderly neighbor; brings food, gardens, sometimes needs help securing windows; knows early Pinehaven stories. |

Target population: 15-25 persistent named NPCs over time; six fully functional
first.

## 5. The opening (current direction, Chapter 34)

1. **Main menu**: premium, atmospheric. Background: wooden cabin in a dark
   forest, warm windows, rain, wind, mist, rare lightning, a rare silhouette.
   Options: Continue, New Game, Play With Friends, Settings (volumes per
   channel, sensitivity, subtitles, accessibility, graphics), Credits. Only
   functional options are enabled.
2. **Skippable 60-90 s cinematic**: aerial pass over mountains and forest,
   the town alive (cars, people, chimneys), title *THE STILLNESS*, subtitle
   *PINEHAVEN — 8:42 AM*, the neighborhood, then the player's house: Maya
   making breakfast, the dog asleep by the fire.
3. Maya: *"Morning. Looks like another beautiful day."* / *"We're running low
   on firewood. Could you grab some before tonight?"* / *"And don't stay out
   too late. The weather's been strange."* Control returns immediately.
4. **GATHER FIREWOOD FOR TONIGHT**: find and equip the axe, go out with the
   dog, chop a tree (visible axe, chopping animation, impact sounds, the tree
   falls), collect wood, return, stack it by the fireplace. Maya
   acknowledges it.
5. **ENJOY THE EVENING**: pet and feed the dog, cook, sit, radio, windows.
6. **Sunset**: birds go quiet, the music turns melancholic, neighbors' windows
   light up. Radio: *"Residents of Pinehaven, an unstable weather system is
   approaching from the northern ridge."* Then a distorted *"...keep your
   windows closed..."* The dog stares at the forest.
7. **First monster reveal**: a tall creature (a WatcherCreature) stands
   between distant trees and slowly turns toward the house. No chase. Maya:
   *"Don't move."* / *"That's a Watcher."* / *"They notice movement. Noise
   makes things worse. And if more of them come, they start sharing what they
   know."*
8. **Interactive stealth tutorial** using the real systems: EQUIP THE COAT ->
   DARKEN THE HOUSE (lights off, curtains closed, door shut) -> stay still,
   hold breath (H) as it investigates the window -> it loses interest and
   leaves. Forgiving; mistakes are recoverable.
9. Maya: *"I think it's gone."* Rain begins. *"Let's stay inside tonight."*
   -> SURVIVE YOUR FIRST NIGHT.

**The first seven days** (arc): 1 Coming Home, 2 The Empty Town (supplies in
Pinehaven), 3 The Coat (concealment), 4 The Storm (wind, windows, breath),
5 The House Across the Lake (Maya's emergency), 6 The Listening Winter
(sheriff's records), 7 The First Bad Night.

## 6. Core systems

### Time and weather
- Day 12 min, dusk 3, night 8, dawn 2 (configurable). Server-authoritative.
- **Rain is continuous (intensity 0-5)**: drizzle, moderate, heavy,
  torrential, violent storm. **Most rain is calm**; storms are rare. Fog.
- **Wind gusts** can rattle windows, force **unlatched** windows open, crack
  damaged glass. Reinforced or shuttered windows resist.
- Thunder at irregular intervals; lightning can briefly reveal real creature
  positions.
- **Forecasting** (planned): visual signs, barometer, weather radio, Dr.
  Hale's station, radar; forecasts carry uncertainty; storms form and move
  regionally.

### Shelter
- The home is a registered shelter volume with registered entry points
  (doors, windows, roof). **Secure** = every entry installed, shut, unbroken.
- On ordinary nights ordinary creatures cannot enter or harm players inside a
  secure shelter. They may stare through windows.
- On **Bad Nights**, coordinated groups can damage and breach entry points
  (one creature scratches; three or more break in). Breaches are physical
  openings; nothing passes through intact walls.

### Creature perception and AI
- Channels: **vision** (distance, field of view, line of sight, light on the
  player, movement, weather), **hearing** (noise events through walls and
  rain), **presence** (supernatural sense; the coat suppresses it).
- Brain states: DORMANT, PATROL, SUSPICIOUS, INVESTIGATE, SEARCH, HUNT,
  LOST_TARGET, RETREAT. Memory of last known position with expiry.
- **Collective mind**: creatures report evidence per sector; evidence decays;
  levels AWARE, INVESTIGATING, CONVERGING, BREACHING (bad nights only),
  SEARCHING, DISPERSING; shared positions grow less reliable with age.
- **Window paradox**: a creature may see you through a window, walk up and
  stare, but cannot get in if the house is secure. Curtains break sight.

### Creature types
- **WatcherCreature**: tall, still, watches lit windows, moves when not
  observed, rarely chases. Psychological pressure.
- **Dweller**: lives in abandoned interiors, hunts by sound, day and night.
- **Crawler**: low, fast, bad nights, part of the collective, breaches as a
  group.
- **Mimic** (planned): imitates human routines in houses; subtle wrongness.
- **Listener** (planned): blind-ish, hunts sound.
- **Housebound** (planned): tied to one house's nightly routine; mysteries.
- **Giant / The Old One**: rare silhouette over the ridge; smaller creatures
  avoid it.

### The coat, stillness and breath
- The coat is not invisibility: it strongly suppresses presence, helps when
  still, never cancels noise.
- **Hold Breath (H)**: capacity about 10 s; reduces close-range detection;
  running out causes an audible gasp; slow release is quiet.
- Crouch (C) is quieter and less visible; running is loud.

### Lights and power
- Every light has a switch; a fuse box cuts the house circuit; the fireplace
  and lanterns are independent. A lit house with open curtains advertises
  itself at night; lights off with curtains closed is near invisible.

### Observation and journal
- At any window: E to look out (bounded camera, zoom; binoculars zoom more).
- The journal records real sightings (species, place, time, weather,
  behavior) and distinguishes observations from theories.
- Neighbor houses have visible routines (lights, silhouettes); a lake-house
  mystery progresses over nights; distant attacks on bad nights can be
  watched.

### Dog (Caramelo)
- Follow, stay, come, sit, sleep, go to bed, hide with you, calm.
- Growls at nearby creatures; barking can be calmed; hides with the player.
- Never dies; teleports back if lost.
- **Petting must be a visible two-character interaction** (player reaches
  down, the dog sits, leans in and wags). Currently it shows only a message.

### Survival loop
- **Gathering**: trees (with an **axe** tool: visible in hand, chop animation,
  hit feedback, the tree falls, stump, regrows), rocks, bushes, berries,
  mushrooms, scrap.
- **Food and hunger** (planned): slow hunger; pantry, fridge, grocery, diner,
  foraging, fishing; cooking at stove, fireplace or campfire; warm meals give
  comfort and warmth; dog food and water bowls.
- **Building**: grid placement validated by the server (walls, floors,
  furniture, lanterns); cabin upgrades (reinforced door, shutters, latches).
- **Comfort**: physical, emotional, weather, observational, routine and
  achieved coziness; improves recovery.
- **Exposure**: a readout of the real perception inputs, never a dice roll.

### Pinehaven town and scavenging
- Grocery, pharmacy, hardware store, vet, gas station, diner, sheriff, church,
  textile mill, warehouse, houses. Persistent, server-side loot that
  replenishes. Town lights at night; staggered blackouts on bad nights.
- Neighbors with daily routines: shops open by day, people return at dusk,
  lit windows at night, simplified simulation when far away.

### Human Watchers (storm-chaser profession, planned)
- Internal names: `HumanObserver` (people) vs `WatcherCreature` (monster).
- Loop: check forecast -> pick a storm -> prepare gear and food -> coat on ->
  travel to a lookout -> observe without being detected -> record behavior ->
  leave before it gets too dangerous -> submit findings to Noah -> unlock gear,
  better forecasts and story clues. Optional for players who prefer cozy play.

### Maya systems (planned)
- State machine: DAILY_ROUTINE, TRAVELING, VISITING_PLAYER,
  PREPARING_FOR_NIGHT, SHELTERING, HIDING, UNDER_THREAT,
  REQUESTING_ASSISTANCE, ESCAPING, RECOVERING. Same survival rules as the
  player.
- Radio talk reflects real world state. Emergencies (window forced open in a
  storm, power failure, trapped in town, surrounded house, missing signal)
  are decisions, not forced quest markers: guide her by radio, observe and
  inform, travel there, distract, or wait for dawn. No permanent death.

## 7. Audio and music direction

- Environmental audio matters more than music: layered rain (outdoor, roof,
  window, gutters, drips), wind (light, trees, howling, gusts, through an open
  window), thunder near and far, house creaks, latches, shutters, breathing,
  the dog.
- The sound must change sharply when a window opens (wind and rain flood in)
  and return to muffled comfort when it closes.
- Adaptive music states: main menu, home safe, home rain, day exploration,
  dusk, night safe, night outside, creature nearby, hunting, lost, dawn,
  discovery, blackout (silent), storm night. Silence is intentional.
- Storm nights use an unsettling music-box motif in the spirit of
  slow, high, repetitive and slightly wrong. **No existing melody may be
  copied or varied** (for example the Pokemon Lavender Town theme is
  copyrighted); compose originals. The owner wants richer, layered music than
  the current single-voice music box.

## 8. Art direction

Semi-realistic, cohesive: dense pine/cedar/birch forest, autumn maples by the
lake, snowy jagged mountains, warm cabin interiors with layered roofs, porches,
curtains and firelight; muted dark UI with warm amber accents; avoid heavy
bloom and filters that hide the world. Night must be dark but readable; lit
windows are landmarks.

## 9. World layout

- Current: ~2 km valley (terrain to +/-1000 studs, playable +/-860): cabin
  by a lake, lake house across the water, abandoned house, radio tower on a
  hill, nine neighbor buildings along dirt roads, meadows with wildlife
  (deer, rabbits, crows that flee creatures), a north ridge highland, distant
  snowy peaks.
- Target: ~4096 x 4096 studs with StreamingEnabled and regions (starting
  forest, Pinehaven town, abandoned village, deep forest, lake district,
  mountain region, caves). Cabin to town should feel like a meaningful walk.

## 10. Technical frame

- Roblox (Luau, strict types), Rojo filesystem workflow, StyLua, Selene,
  luau-lsp analysis, Lune unit tests for pure logic.
- **Server-authoritative** for time, weather, creatures, inventory,
  gathering, building, shelter state, story progress; validated, rate-limited
  remotes; clients present only.
- Pure logic modules (perception, brain, shelter, noise, collective mind,
  inventory, comfort, music state, story progress...) are tested outside
  Roblox.
- Assets: Roblox Creator Store (scripts stripped and audited; one free tree
  pack hid a 35 KB overlay script), Roblox licensed audio partners
  (ProSoundEffects, APM, DistroKid), originals. Animations and audio not
  owned by the experience owner must be uploaded by the owner to work in a
  published game.
- Multiplayer-ready: one consistent world state; Maya and NPCs are single
  persistent world characters.

## 11. Current implementation state (honest)

**Verified in Roblox Studio:** world generation (~6-7 s), menu over a live
camera shot, spawn, realistic forest and mountains, the cabin (bedroom, porch,
furniture), Caramelo (caramel mesh dog, follows, runs with a walk animation),
marked trees with a Chop prompt, wood gathering, door repair, door opening,
fireplace with flames and light, objective progression up to "Survive the
first night", dog command panel, 80 licensed sounds plus one original track
loading.

**Implemented, not yet verified in Studio:** creatures and their AI,
collective mind and breaching, bad nights, storms forcing windows open,
curtains/latches/shutters, lights and fuse box, hold breath, coat,
observation mode and journal, adaptive music, wildlife reactions, building.

**Not implemented yet:** Pinehaven town and loot, NPC neighbors and routines,
Maya as an NPC, dialogue system, cinematic system, new menu, settings,
hunger and cooking beyond one stew recipe, dog feeding, axe tool and chop
animation, falling trees, petting animation, forecasting, Human Watchers
profession, StreamingEnabled plan, performance measurements.

**Owner feedback to address now:** the menu feels weak; chopping without an
axe looks bad (the tree simply vanishes, no animation, no movement); petting
has no animation; the game should start in a complete home with Maya and the
dog, gather firewood, then a mood shift at night and a guided first-monster
lesson; music should be more complex.

## 12. Constraints and rules

- No purchases. Only assets whose license allows use in a Roblox experience.
- No copying of other games' names, characters, art, music or levels.
- Romance stays age-appropriate and Roblox-safe.
- No unavoidable deaths inside a correctly secured home; no permanent dog or
  Maya death in the first prototype.
- Hunger must never become an annoying interruption.
- Every feature must be real gameplay, not a scripted cutscene pretending.

## 13. What we want from the reviewer

Please respond with:

1. **Verdict**: what is strong, what is muddled, what is over-scoped.
2. **Contradictions and risks**: design conflicts (for example Watchers as a
   monster and as a human profession; Maya living with the player vs her own
   house; cozy pacing vs survival pressure), technical risks on Roblox
   (performance on a 4096 map, NPC count, animation ownership, streaming vs
   window observation), and moderation/IP risks.
3. **A tightened core loop** for the first hour and for a typical day/night.
4. **The first 20 minutes, beat by beat**, ready to implement, with what the
   player does, sees and hears, and which system teaches each mechanic.
5. **A prioritized roadmap**: vertical slice (must-have), next milestone,
   later; with rough effort and what to cut.
6. **Specific improvements** to: the menu, axe and chopping feel, petting
   interaction, the first monster lesson, Maya's role, music.
7. **Open questions** the owner must decide.
