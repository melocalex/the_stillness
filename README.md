# THE STILLNESS

A cozy survival horror game for Roblox. You live in your grandfather's cabin
by a lake outside Pinehaven, a mountain town that went quiet, with Caramelo,
your caramel street dog. Maya, your girlfriend, lives in her own house across
the water; at night you can see her lamp. By day you chop wood, cook, repair
and explore. At night you close the curtains, keep the fire low and stay
still. Something is outside. You are home.

The horror exists to make the comfort mean something: the core loop is
building a safe, warm life in a world that is not safe.

## What it plays like

- **Most nights are quiet.** Peaceful 65%, Uneasy 25%, Bad 9%, Black 1%.
  Bad nights are warned in advance: the birds go silent, the radio crackles.
- **No weapons.** You survive with light, sound, curtains, latches,
  shutters, an old coat, stillness and your breath.
- **Creatures that think.** They see light and movement, hear noise through
  walls and rain, sense presence, remember where they last saw you, and
  share what they notice. A secure house is safe on an ordinary night.
- **Windows are gameplay.** Look out, watch the treeline, record what you
  see in your journal. Curtains block sight both ways.
- **The first day teaches it all.** Maya radios in the morning, you gather
  firewood with the axe, visit her for lunch, get home before dark, and she
  talks you through your first Watcher over the radio.

## Run it

You need macOS or Windows with [Roblox Studio](https://create.roblox.com/)
(signed in with a Roblox account) and the toolchain below.

```bash
brew install rojo stylua selene lune luau
```

```bash
./scripts/setup.sh
```

```bash
./scripts/check.sh
```

`check.sh` formats, lints, type-checks (strict Luau), runs the unit tests and
builds `build/TheStillness.rbxlx`. Open that file in Studio and press
**Test > Start Test Session > Test**. The world is generated when the server
starts (a few seconds), then the menu appears; press **Begin**.

For live editing, run `rojo serve` and connect the Rojo plugin in Studio
(installed with `rojo plugin install`).

## Controls

| Key | Action |
| --- | --- |
| WASD | Move |
| Shift | Run |
| C | Crouch / sneak |
| 1 | Axe (click near a tree with an orange ribbon) |
| H (hold) | Hold your breath |
| Q | Coat on / off |
| E, F, R | Interact (prompts show which) |
| T | Pet Caramelo |
| G | Dog commands |
| P | Pack |
| J | Journal |
| B | Build mode (R rotates, click places, X cancels) |
| Mouse wheel | Zoom while looking out of a window |

## What is in the prototype

See [STATUS.md](STATUS.md) for what is implemented, what has been verified in
Studio, and what is still open. Design notes live in [docs/](docs/).

## Repository layout

| Path | Contents |
| --- | --- |
| `src/server` | Server scripts: world generation, gameplay services, creatures |
| `src/client` | Client scripts: UI, input, camera, weather, audio |
| `src/shared` | Config (pure data), pure gameplay logic, remotes |
| `tests` | Lune unit tests for `src/shared/Logic` |
| `assets` | Vetted Creator Store models (`StillnessAssets.rbxm`) and original music; credits in [docs/ASSET_LICENSES.md](docs/ASSET_LICENSES.md) |
| `tools` | Asset search, extraction and Studio helper scripts |
| `docs` | Design, architecture, development, testing, asset licenses |
