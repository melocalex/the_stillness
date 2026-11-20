# Development

## Toolchain

Installed on the reference machine (macOS 26, Apple M2) with Homebrew,
official formulas only, no remote install scripts:

| Tool | Version | Purpose |
| --- | --- | --- |
| Roblox Studio | 0.748 (Homebrew cask `robloxstudio`, from `setup.rbxcdn.com`, sha256-checked) | Editor and playtests |
| Rojo | 7.7.1 | Filesystem to Studio sync and place builds |
| StyLua | 2.6.0 | Formatting (`stylua.toml`) |
| Selene | 0.32.0 | Linting with the Roblox standard library |
| luau-lsp | 1.70.1 (GitHub release binary) | Strict type analysis with Roblox definitions |
| Lune | 0.11.1 | Runs unit tests and asset tooling outside Roblox |

`rokit.toml` pins the same versions for [Rokit](https://github.com/rojo-rbx/rokit)
users. `./scripts/setup.sh` downloads the Roblox type definitions used by
luau-lsp (a data file pinned to the luau-lsp release).

## Daily loop

```bash
rojo serve
```

In Studio, open the Rojo plugin and connect; edits under `src/` sync live.
Start a test with **Test > Start Test Session > Test**.

Or build a place file and open it:

```bash
./scripts/check.sh
```

```bash
open build/TheStillness.rbxlx
```

### Fast-forward time while testing

In a running test, select the **Server** view and run in the command bar:

```lua
game.ReplicatedStorage:SetAttribute("TimeScale", 30)
```

`1` is real time; the day/night durations are in `GameConfig.Time.Durations`.

## Adding assets

1. Search: `python3 -I tools/assets/search_store.py models "pine tree" 15`
   (or `audio`). Prefer verified creators, `FREE`, no `HAS-SCRIPTS`.
2. Add the id to `tools/studio/import_assets.luau`, paste it into the Studio
   command bar in Edit mode, and run it. It loads every pick into
   `ServerStorage.StillnessAssets` and deletes scripts.
3. Save the place (Cmd+S), then extract:
   `lune run tools/assets/extract_assets build/TheStillness.rbxlx`.
4. Audio: add to `tools/assets/audio_candidates.lua`, regenerate
   `tools/studio/verify_audio.luau`, run it in Studio, then copy verified ids
   into `src/shared/Config/AudioConfig.luau`.
5. Record the asset in `docs/ASSET_LICENSES.md`.

## Publishing

Publishing needs your Roblox account and is a manual step:

1. Open the built place in Studio.
2. **File > Publish to Roblox As**, create a new experience.
3. In **Game Settings > Security**, enable **Studio Access to API Services**
   if you want inventory saving (DataStore) to work in Studio tests.
4. Keep the experience private until the prototype is tested with friends.

The dog's walk/idle animations come from KeyframeSequences in the asset pack.
They play in Studio. In a published game they need to be uploaded as
Animation assets owned by your account (Animation Editor > Publish), or the
dog falls back to procedural leg motion.
