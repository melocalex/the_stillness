# Working on THE STILLNESS

Rules for anyone (human or agent) changing this repository.

## Gate

Run `./scripts/check.sh` before every commit. It must print
`All checks passed.` (StyLua, Selene, luau-lsp strict analysis, Lune tests,
Rojo build). Run `stylua src tests` first to format.

## Architecture rules

- **Server authority.** Inventory, building, gathering, time, weather,
  creature state, shelter state, damage and story progress live on the
  server. Clients only present state and send validated, rate-limited
  requests (`Net.allow`).
- **Pure logic is testable.** Modules in `src/shared/Logic` take plain values,
  require nothing and use no Roblox services, so Lune can test them. Add a
  test in `tests/logic.spec.luau` for every new pure module.
- **Config is data.** Tunables live in `src/shared/Config`. No magic numbers
  in services when a config value fits.
- **Shelter rules are explicit.** The cabin is a registered shelter volume
  with registered entry points (door, windows, roof). Never infer enclosure
  from geometry, and never let a creature pass through intact walls.
- **Names are contracts.** World builders publish tags, attribute names and
  prompt names that services rely on (listed in `docs/ARCHITECTURE.md`).
  Rename only together with every consumer.

## Assets

- Only use assets whose license allows use in a Roblox experience: Roblox
  Creator Store items, Roblox's licensed audio partners, or CC0.
- Vet every model: `tools/assets/search_store.py` shows creator and the
  scripts flag; `tools/studio/sanitize_assets.luau` deletes scripts;
  `tools/assets/extract_assets.luau` refuses to save a model with scripts.
- Verify every audio id loads in Studio (`tools/studio/verify_audio.luau`)
  before adding it to `AudioConfig`. An empty id means silent; never invent ids.
- Record every asset in `docs/ASSET_LICENSES.md`.

## Honesty

Keep `STATUS.md` truthful: separate implemented, statically checked,
Studio-tested and unverified. Do not claim something was tested in Studio
unless it ran there.
