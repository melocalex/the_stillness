# Architecture

Rojo maps `src/shared` to `ReplicatedStorage.Shared`, `src/server` to
`ServerScriptService.Server`, `src/client` to
`StarterPlayer.StarterPlayerScripts.Client`, and `assets/StillnessAssets.rbxm`
to `ServerStorage.StillnessAssets`.

## Layers

```
Config (pure data)  ->  Logic (pure functions, Lune-tested)
        \                       |
         ->  Server services (authoritative state, Roblox APIs)
                    |  remotes (Net), attributes, tags
                    v
             Client controllers and UI (presentation only)
```

- `src/shared/Config`: tunables. `GameConfig` (time, player, weather,
  nights, collective, breach, comfort, gather, build, dog, lake-house
  script), `CreatureConfig` (archetypes: senses, brain, speeds, flags),
  `ItemConfig`, `StoryConfig`, `WorldConfig` (layout, terrain forms, lake,
  paths, regions, sightlines, forest, atmosphere), `AudioConfig`.
- `src/shared/Logic`: `TimeCycle`, `Perception`, `CreatureBrain`, `Shelter`,
  `Noise`, `CollectiveMind`, `Inventory`, `NightClass`, `Comfort`,
  `LightVisibility`, `MusicState`, `Journal`, `StoryProgress`, `Mystery`,
  `Breath`, `FearEcology`, `ChaosField`, `Dissonance`, `Heightfield` (the
  valley's deterministic height function, see [WORLD.md](WORLD.md)), and
  for Chapter 37 `Objectives`, `Quests`, `Town`, `Restoration`,
  `Incidents`, `Dialogue`, `LifeJournal`. No requires, no Roblox services
  (`Quests` receives the objective components as an argument).
  `DissonanceConfig` holds the Chapter 36 tunables.
- Chapter 37 config: `QuestConfig` (quests) and `TownConfig` (sites, NPCs,
  dialogue, projects, shop, tiers, limits, incidents, Caramelo's saved
  Tracking skill).
- `src/shared/Net.luau`: remote names, creation, per-player token-bucket
  rate limiting.

## Server

Started in dependency order by `Main.server.luau` after the world is built
(`Players.CharacterAutoLoads = false`; players spawn on the menu's Play).

| Module | Role |
| --- | --- |
| `World/*` | Terrain (heights from `Logic/Heightfield`, chunked, height-banded `WriteVoxels`), forest (seeded groves of asset trees + collider, understory, scenery fringe), cabin, neighbor houses, landmarks, wildlife, asset access |
| `TimeService` | Authoritative clock; publishes Day, Phase, ClockTime, NightFactor |
| `WeatherService` | Continuous rain intensity, fog, wind, gusts that force unlatched windows, thunder |
| `ShelterService` | Registered shelters and entry points; `Secure`, `Reasons`, `Weakest` |
| `LightService` | Lights, switches, circuits, flicker; illumination and house beacon |
| `NoiseService` | Noise events, attenuation through walls and weather |
| `PlayerService` | Stance, stamina, breath, coat, comfort, exposure, inventory, capture |
| `InteractionService` | Every cabin/landmark prompt (doors, windows, lights, fire, bed, radio...) |
| `GatherService` | Resource nodes, depletion, respawn, tree felling |
| `ToolService` | The axe tool: swing animation, chop the tree in front |
| `StoryService` | Facts and objective progression |
| `MayaService` | Maya's R15 NPC in her own house: routine spots by phase, window lights, Talk prompt, radio lines |
| `OpeningService` | Day 1 script: morning radio call, sunset warning, the guided first Watcher, rain and lamp afterwards; every step has a fallback |
| `CreatureService`, `Creatures/Creature`, `Creatures/Rigs` | Spawning, AI tick budgets, senses, brain, pathfinding, window paradox, breaching |
| `CollectiveService` | Shared creature awareness and coordinated attacks |
| `NightDirector` | Night classification, warnings, spawning (from night 2; night 1 belongs to the opening), dawn retreat |
| `DogService` | Caramelo: follow, commands, alert, hide, pet |
| `HouseActivityService`, `OldOneService`, `ObservationService` | Distant house routines, the Old One, window observation and journal |
| `BuildService` | Grid placement validated on the server |
| `ChaoticEnergyService`, `World/Chaoscope` | Chapter 36: the chaotic energy field (1 Hz, real time), anomalies, the H-17 Chaoscope on the cabin table and its validated `Chaoscope` remote |
| `DissonanceEventDirector` | Answers anomaly beats with nonvisual events through LightService, MayaService, the dog's startle attributes and ObservationService.note |
| `World/Town` | Chapter 37 sites from `TownConfig.Sites`, built by `Main` after the world and before services; dry ground by raycast, staged parts, clears trees in each site radius |
| `ProgressBus` | Dependency-free progress events (`emit`/`listen`) so Maya, observation and others report without requiring progression |
| `ProgressionService` | Per-player quests, standing, projects and Caramelo's Tracking skill; the `progression` save section; Life Journal view; forecast |
| `TownService` | Frank, Ellen, Martha, Dr. Hale; dialogue; quest, repair and shop prompts; restoration visuals; Biscuit; Maya's talk hook |
| `DogTracking` | Martha's scent trail: steers Caramelo through `DogService.setDriver` (the one Chapter 37 hook in DogService) and `dogOf` |
| `IncidentService` | Daytime incident director from day 2 |
| `DebugService` | Studio only: `ServerStorage.StillnessDebug` for command-bar checks |

## Client

`Main.client.luau` starts: `LightingController`, `WeatherController`,
`AudioController` (ambience mixer + MusicDirector), `Prompts` (custom
ProximityPrompt renderer), `HUD`, `Panels`, `InputController`,
`ObservationController`, `BuildController`, `DogAnimator`,
`CreatureAnimator`, `ChaoscopeController`, then `Menu`.
Chapter 37 adds `UI/LifeJournal` (the J panel, errand card, objective
marker, shop counter; registered through `Panels.register`) and
`Controllers/TownFx` (spins parts marked `Spinning`).

## Contracts between world builders and services

- Tags: `Shelter`, `ShelterVolume`, `EntryPoint`, `Door`, `Window`,
  `StillnessLight`, `Fireplace`, `DogBed`, `Chest`, `Workbench`, `CabinRadio`,
  `ResourceNode`, `LootCrate`, `DwellerPoint`, `Zone`, `WatchedHouse`,
  `HousePane`, `OldOne`, `Creature`, `Dog`, `Wildlife`, `AxeTool`,
  `MayaHouse`, `Maya`.
- Maya's house holds invisible `MayaSpot` parts; the `Spot` attribute
  (`Kitchen`, `Window`, `Porch`, `Upstairs`) is the name `MayaService.goTo`
  uses. Rooms are lit with the same `Room` attribute rules as watched houses.
- Entry point attributes: `EntryId`, `EntryKind`, `Installed`, `Open`,
  `Health`, `MaxHealth`, `Shelter`, plus windows' `Latched`, `LatchBroken`,
  `CurtainsClosed`, `Shuttered`, `Tier`.
- Light attributes: `On`, `Lit`, `Electric`, `Indoor`, `Circuit`, `Shelter`,
  `Brightness`.
- Prompt names: `DoorPrompt`, `UpgradePrompt`, `CurtainPrompt`, `LatchPrompt`,
  `ObservePrompt`, `SwitchPrompt`, `SwitchPrompt2`, `LampPrompt`,
  `PowerPrompt`, `FirePrompt`, `CookPrompt`, `SleepPrompt`, `RadioPrompt`,
  `WardrobePrompt`, `PetPrompt`, `MayaPrompt`, `ScopePrompt`,
  `ScopePowerPrompt`; all prompts use `ProximityPromptStyle.Custom`.

## The Dissonance (Chapter 36)

- Tag `Chaoscope` on the H-17 model; parts `Case`, `Face`, `Dial`, `Screen`,
  `LampPower`, `LampSignal`, `LampEmit`, `LampFault`, `Knob`, `Switch`.
- Scope attributes (server-written, the only Dissonance data a client sees):
  `Powered`, `Mode` (`PASSIVE`, `LOCAL`, `REGIONAL`), `Sensitivity` (1-5),
  `Needle` (displayed CEU, noisy), `Jitter`, `Wave`, `Level`, `Emit`.
  True energy, anomaly families and stages and hidden positions never leave
  the server.
- Creature hook: workspace `ChaosSignal` (0-1), `ChaosSignalPosition`,
  `ChaosSignalAt` after each scan pulse.
- ReplicatedStorage `Hush` (0-1) pauses ambience, fire and music on the
  client (the `Hushable` SoundGroup). `DissonanceForce` (Studio only) seeds
  an anomaly at the house.
- Caramelo reacts through his own mood system: the director sets
  `StartleStrength` (0.22 to 0.45) and `StartledAt` on dog models within
  45 studs of the scope. DogService turns that into agitation (head up at
  ALERT, a low growl at SUSPICIOUS) and he calms down by himself.
- Maya's window blink skips, and never relights, when MayaService would keep
  her house dark (a creature within 60 studs of the cabin, or the
  `mayaSilent` night story).
- Remotes: `Chaoscope` (client to server, rate 4/s, within 12 studs) and
  `Dissonance` (server to client; `echo` replays the client's own recent
  in-game cues).

## Progression (Chapter 37)

- Tags: `TownSite` (site models, `Site` attribute), `TownVisual` (staged or
  lit parts), `TownNpc` (NPC models, `Npc` attribute), `TownForage`
  (incident pickups). Biscuit is tagged `Dog` without an `Owner`, so only
  `DogAnimator` treats him as a dog.
- Part attributes (set by `World/Town`): `NpcSpot` (as `Npc`),
  `Interaction`, `RepairProject`, `SiteAnchor`, `ShopVendor`, `MissingSpot`,
  `HomeSpot`, `StageOf` + `ShowFrom` + `ShowUntil`, `ShowFlag`, `HideFlag`,
  `LitFlag`, `NightOnly`, `LightWhenShown`, `Glow`, `NeonWhenLit`, `Spin` +
  `SpinFrom` (server sets `Spinning`).
- Prompt names: `TownTalkPrompt` (E, people), `TownPrompt`, `RepairPrompt`,
  `InspectPrompt` (F, things), `ShopPrompt` (R, counters), `IncidentPrompt`.
- Dog: while `DogTracking` steers him, the dog model has `Tracking = true`
  and `Pose` may be `track` (nose down). DogService's only Chapter 37 change
  is `setDriver(player, driver?)`; concealing, seeking the owner and hiding
  always win over a driver.
- Remotes: `LifeRequest` (client to server), `Life`, `Shop` (server to
  client), `GetLife` (function).

## Performance choices

- `StreamingEnabled` is off for the prototype so distant houses and creatures
  always exist for window observation. Revisit with persistent models for
  landmarks when the map grows.
- Trees are anchored meshes with no collision plus one invisible trunk
  cylinder each. Scenery trees outside the play area have no collider and
  cast no shadows.
- Terrain heights are evaluated once per 4-stud column; chunks outside the
  play area get a thin band and no rock floor; the writer yields on a time
  budget.
- Creatures tick at their archetype rate near players and 1 Hz far away.
- Wildlife updates at 15 Hz on the server; animals outside view are cheap.
