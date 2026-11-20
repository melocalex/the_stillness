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
  `Breath`, `Heightfield` (the valley's deterministic height function, see
  [WORLD.md](WORLD.md)). No requires, no Roblox services.
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

## Client

`Main.client.luau` starts: `LightingController`, `WeatherController`,
`AudioController` (ambience mixer + MusicDirector), `Prompts` (custom
ProximityPrompt renderer), `HUD`, `Panels`, `InputController`,
`ObservationController`, `BuildController`, `DogAnimator`, then `Menu`.

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
  `WardrobePrompt`, `PetPrompt`, `MayaPrompt`; all prompts use
  `ProximityPromptStyle.Custom`.

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
