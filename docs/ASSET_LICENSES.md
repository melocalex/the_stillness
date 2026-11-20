# Asset licenses

Every third-party asset in THE STILLNESS, where it came from, and how it was
checked. Nothing was purchased.

## How assets are vetted

- **Models** come from the Roblox Creator Store (free). Each was checked with
  `tools/assets/search_store.py` (creator, price, `hasScripts`, triangle
  count), loaded in Studio with `tools/studio/import_assets.luau`, stripped of
  scripts, and extracted with `tools/assets/extract_assets.luau`, which refuses
  to write a model that still contains a script. The models live in
  `assets/StillnessAssets.rbxm` and reference their meshes and textures by
  Roblox asset id, so they only work inside Roblox.
- **Audio** comes from Roblox's licensed partner catalogs on the Creator Store
  (ProSoundEffects, APMOfficial, DistrokidOfficial). Every id was loaded in
  Studio by `tools/studio/verify_audio.luau`: 59 of 59 loaded (2026-11-20).
- Creator Store items may be used inside Roblox experiences under the
  [Roblox Terms of Use](https://en.help.roblox.com/hc/en-us/articles/115004647846)
  and Creator Store rules. They are not CC0 and must not be redistributed
  outside Roblox.

## Rejected during vetting

- Two low-poly tree packs inserted from the Toolbox contained 13 hidden
  scripts (a 5.6 KB "Runtime" Script and a 35 KB "WindowDriver" LocalScript
  that builds a screen overlay inside a tree mesh). Typical free-model
  backdoor. All 13 were deleted and the packs were discarded.
- Models named after other games ("99 Nights in the Forest", "DOORS",
  "Hello Neighbor") and user uploads of other games' sounds were skipped.

## Models (`assets/StillnessAssets.rbxm`)

| Name in pack | Asset id | Title | Creator | Scripts | Triangles | Modifications |
| --- | --- | --- | --- | --- | --- | --- |
| Trees_Ponderosa | 130515502281374 | Ponderosa Pine Tree Pack Realistic | Letaij | 0 | 72,355 (12 trees) | scaled 1.25-1.7x, anchored, collisions replaced by a trunk collider |
| Trees_RedCedar | 113109119460825 | [PBR] Realistic Red Cedar Pine Tree | Letaij | 0 | 4,932 | same |
| Trees_Birch | 11351912067 | Realistic Birch Tree Pack Free PBR | Letaij | 0 | 5,957 (6 trees) | same |
| Tree_AutumnOak | 10071825333 | Autumn Oak Tree | Letaij | 0 | 10,481 | same, placed near the lake |
| Tree_SnowPine | 11590212184 | Snowy Pine Tree | V1VEX | 0 | 10,048 | mountain slopes only |
| Dog | 72361172511972 | FREE Golden Retriever Dog - Rigged & Animated | RSG_Ukraine | 0 | 4,924 | tinted caramel (SurfaceAppearance.Color), scaled 1.2x, welded over the dog rig |
| Deer | 5114925772 | Whitetail Deer | fashionzoo10 | 0 | 4,110 | scaled 1.15x, wildlife |
| Rabbit | 8984402484 | Rabbit | SakakiAme | 0 | 2,578 | scaled 1.6x |
| Crow | 676471054 | Crow/Bird | V_alor | 0 | 1,786 | scaled 0.12x |
| RockingChair | 303336108 | Rocking Chair | Hypermatter | 0 | 384 | cabin window chair |
| Bookshelf | 56449804 | Bookshelf | Roblox | 0 | 96 | beside the fireplace |
| Bed | 98266706858536 | Realistic Roblox Wooden Bed | THExWRATHxKING | 0 | 3,368 | scaled 0.8x |
| Lantern | 9666312574 | Realistic Lantern | arnavmahesh | 0 | 2,380 | on the mantel |
| Creature_Watcher | 18629586862 | R15 monster Slum Tree | BotDrone_Studios | 0 | 8,086 | R15 rig, scaled 0.8x (about 11 studs), skin tinted near-black; also the Old One, scaled to 74 studs and blacked out |
| Creature_Dweller | 15020057104 | Wendigo | iamsocool123e | 0 | 13,754 | R15 rig, unchanged (deer skull, ribcage) |
| Creature_Crawler | 103037817796984 | Crawler monster | IAmASwedishMale | 0 | 20,000 | single unrigged mesh, scaled 0.8x, rides the crawler part rig |
| Axe | 87307912628259 | Axe Tool | Elio_Bro gruppe | 0 | 4,752 | the player's axe (Tool inside) |

Creature walk, run and idle use Roblox's own default R15 animations
(507777826, 507767714, 507766666), which play in any experience.

Everything else (terrain, cabin, houses, town, rocks, bushes) is
original procedural geometry built by the code in `src/server/World` and
`src/server/Creatures`.

## Audio (`src/shared/Config/AudioConfig.luau`)

Built-in client sounds (`rbxasset://sounds/...`) ship with Roblox and are
used for footsteps, jumps and splashes.

| Key | Asset id | Title | Catalog |
| --- | --- | --- | --- |
| `bark` | 9113956187 | Coyotes Gruff Barking 13 (SFX), Caramelo's bark; not yet loaded in Studio | ProSoundEffects |
| `birdsDay` | 9112835056 | Neighborhood Birds 1 (SFX) | ProSoundEffects |
| `birdsDay2` | 9112835068 | Neighborhood Birds 2 (SFX) | ProSoundEffects |
| `cricketsNight` | 9112764573 | Crickets Night 3 (SFX) | ProSoundEffects |
| `owl` | 9117181540 | Owl Hooting Reverberant Several 1 (SFX) | ProSoundEffects |
| `wolvesDistant` | 9120051816 | Timber Wolves Distant Howling Chorus 2 (SFX) | ProSoundEffects |
| `coyotesDistant` | 9114683804 | Group Of Coyotes Distant Howling 1 (SFX) | ProSoundEffects |
| `crowsDistant` | 9114009761 | Crow Caw Distant Circling Traffic 1 (SFX) | ProSoundEffects |
| `windLight` | 9114057104 | Desert Wind Whistley Light Gusts 1 (SFX) | ProSoundEffects |
| `windHowl` | 81404060588532 | Howling Wind (Sound) | DistrokidOfficial |
| `windGust` | 9120697823 | Whoosh By Howling Wind Light Rumbling 1 (SFX) | ProSoundEffects |
| `rainLight` | 9120020741 | Thunder Light Rain 1 (SFX) | ProSoundEffects |
| `rainOutside` | 9112853422 | Rain Heavy Rainfall Grass Wooden Roof 1 (SFX) | ProSoundEffects |
| `rainRoof` | 9112853653 | Rain Hitting Roof 2 (SFX) | ProSoundEffects |
| `rainRoofHeavy` | 9112853563 | Rain Heavy Rainfall Grass Wooden Roof 2 (SFX) | ProSoundEffects |
| `thunderDistant` | 9120018411 | Thunder Distant Rumble 1 (SFX) | ProSoundEffects |
| `thunderDistant2` | 9120018695 | Thunder Distant Rumble 2 (SFX) | ProSoundEffects |
| `thunderCrack` | 9120016037 | Thunder Cracks Big Rumbling Blasts Booming 1 (SFX) | ProSoundEffects |
| `thunderCrack2` | 9120016256 | Thunder Cracks Big Rumbling Blasts Booming 3 (SFX) | ProSoundEffects |
| `fireplace` | 77688442375055 | Crackling Fireplace for Deep Sleep | DistrokidOfficial |
| `eerieRumble` | 9112795463 | Hollow Rumble 1 (SFX) | ProSoundEffects |
| `eeriePresence` | 9112775612 | Eerie Presence 1 (SFX) | ProSoundEffects |
| `windowRattle` | 9120762268 | Window Rattle 14 (SFX) | ProSoundEffects |
| `windowRattleLong` | 9120766393 | Window Rattle 23 (SFX) | ProSoundEffects |
| `curtain` | 9114018343 | Curtains Curtain Hardware Rattle 4 (SFX) | ProSoundEffects |
| `switch` | 9125609743 | Hotel Light Switch Turn On Off Sharp Clicks  (SFX) | ProSoundEffects |
| `doorOpen` | 9120839581 | Wood Door Open Soft Close 1 (SFX) | ProSoundEffects |
| `doorClose` | 9120839870 | Wood Door Open Soft Close 4 (SFX) | ProSoundEffects |
| `doorSlam` | 1837829565 | HIT-Door Slam 02 | APMOfficial |
| `doorPound` | 9114148088 | Door Pound 2 (SFX) | ProSoundEffects |
| `doorBreak` | 9120805690 | Wood Break Breaking Open Wood Door Cracks 1 (SFX) | ProSoundEffects |
| `woodCreak` | 9126282474 | Wood Strain Stress Metal Creaking Squeaking  (SFX) | ProSoundEffects |
| `woodScrape` | 9116908825 | Metal Wood Scrapes 1 (SFX) | ProSoundEffects |
| `chop` | 9120808574 | Wood Chopping Exterior Single Hits 12 (SFX) | ProSoundEffects |
| `mine` | 9118612665 | Rock Impact 7 (SFX) | ProSoundEffects |
| `gasp` | 9125572450 | Gasps Male Deep Breaths Fast Pants Frightene (SFX) | ProSoundEffects |
| `exhale` | 9113586144 | Breath Exhale 17 (SFX) | ProSoundEffects |
| `heartbeat` | 9043365842 | HEARTBEAT 02 96BPM | APMOfficial |
| `radioStatic` | 9125774208 | Police Radio Line Feed Radio Voices Static 1 (SFX) | ProSoundEffects |
| `creatureBreath` | 9113983944 | Creature Mix Weird Deep Monster Breathing 1 (SFX) | ProSoundEffects |
| `creatureBreath2` | 9113984054 | Creature Mix Weird Deep Monster Breathing 2 (SFX) | ProSoundEffects |
| `creatureGrowl` | 9125467848 | Creature Growls Lion Deep Guttural Rumbling  (SFX) | ProSoundEffects |
| `creatureRoarDeep` | 9113985466 | Creature Roar Constant Deep Throaty Growls 3 (SFX) | ProSoundEffects |
| `birdsTakeOff` | 9125738421 | Pigeon Surges Sudden Bursts Of Birds Flying  (SFX) | ProSoundEffects |
| `wingFlaps` | 9113444620 | Bird Wing Flaps Pigeon Two 1 (SFX) | ProSoundEffects |
| `dogBarkFar` | 9114370187 | Farm Animals Dog Barking Rooster Crows 1 (SFX) | ProSoundEffects |
| `musicMenu` | 1838792473 | Dawn 2 | APMOfficial |
| `musicHome` | 113205710506304 | Relaxing Piano and Crackling Fireplace | DistrokidOfficial |
| `musicHome2` | 129193633608000 | Armchair Twilight Sonata | DistrokidOfficial |
| `musicHomeRain` | 133914369779227 | Quiet Morning Drizzle | DistrokidOfficial |
| `musicDay` | 135947284128563 | Autumn whispers | DistrokidOfficial |
| `musicDay2` | 113725748108878 | Echoes of the Ancient Wood | DistrokidOfficial |
| `musicDusk` | 9046385674 | Sunset Glow | APMOfficial |
| `musicNightSafe` | 84591888439601 | Soft Mantel Clock | DistrokidOfficial |
| `musicNightOutside` | 99895453377463 | Existential Dread (Deep Dark Ambient Drone) | DistrokidOfficial |
| `musicCreatureNear` | 1839621827 | Ominous | APMOfficial |
| `musicCreatureHunt` | 1837795171 | Skin Crawler | APMOfficial |
| `musicCreatureLost` | 1835935237 | Tempus Oris | APMOfficial |
| `musicDawn` | 9042042586 | Eternal Ice (b) | APMOfficial |
| `musicDiscovery` | 113592187486066 | Moon TAG | APMOfficial |
Inspiration note: the Watcher's unease motif is meant to evoke a slow,
repetitive, high-pitched wrongness. It uses licensed APM catalog music; no
existing game melody is copied.

## Known Studio log message

`ContentId: rbxassetid://203785492 failed due to: Asset type does not match
requested type - Studio`. Asset 203785492 is the audio asset "Pop Close
Sound" (creator Zyleak). Nothing in this repository or in
`StillnessAssets.rbxm` references it; the message is tagged `Studio`, not
`Server` or `Client`, and appears when the editor UI loads. It is not a game
asset failure.

## Original audio uploaded to the owner's account

| Key | Asset id | Title | Source |
| --- | --- | --- | --- |
| `STORM_NIGHT` | 85164647841567 | The Mechanism (storm-night music box) | Original composition, `tools/audio/compose_storm_musicbox.py`; uploaded with Studio Asset Manager on 2026-11-20; loads in Studio |
